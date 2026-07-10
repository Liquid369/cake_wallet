import 'dart:async';
import 'dart:convert';
import 'dart:io';

const _defaultProbeRanges = <(int, int)>[
  (2700500, 2700599),
  (2700900, 2700999),
  (2705000, 2705099),
];

const _pivxSaplingMainnetActivationHeight = 2700500;

const _requiredV1Methods = <String>{
  'blockchain.sapling.get_block_range',
  'blockchain.sapling.get_best_anchor',
  'blockchain.sapling.get_witness',
  'blockchain.sapling.get_nullifier_status',
  'blockchain.sapling.get_commitment_info',
};

Future<void> main(List<String> args) async {
  final endpoints = args.isEmpty
      ? _readDefaultNodes(File('assets/pivx_electrum_server_list.yml'))
      : args.map(_endpointFromArg).toList();

  final generatedAt = DateTime.now().toUtc().toIso8601String();
  stdout.writeln('# PIVX Sapling Default-Node Probe');
  stdout.writeln();
  stdout.writeln('- generated_at_utc: `$generatedAt`');
  stdout.writeln('- probe_ranges: `${_defaultProbeRanges.join(', ')}`');
  stdout.writeln(
    '- note: capability and range summaries only; no wallet secrets are used.',
  );
  stdout.writeln();

  for (final endpoint in endpoints) {
    await _probeEndpoint(endpoint);
  }
}

List<_Endpoint> _readDefaultNodes(File file) {
  final endpoints = <_Endpoint>[];
  final fields = <String, String>{};

  void flush() {
    final uri = fields['uri'];
    if (uri == null || uri.isEmpty) {
      fields.clear();
      return;
    }
    final parts = uri.split(':');
    if (parts.length != 2) {
      throw FormatException('Invalid node uri: $uri');
    }
    endpoints.add(_Endpoint(
      host: parts.first,
      port: int.parse(parts.last),
      useSsl: fields['useSSL'] == 'true',
      isDefault: fields['is_default'] == 'true',
    ));
    fields.clear();
  }

  for (final rawLine in file.readAsLinesSync()) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;
    if (line == '-') {
      flush();
      continue;
    }
    final separator = line.indexOf(':');
    if (separator <= 0) continue;
    final key = line.substring(0, separator).trim();
    final value = line.substring(separator + 1).trim();
    fields[key] = value;
  }
  flush();

  return endpoints;
}

_Endpoint _endpointFromArg(String arg) {
  final parts = arg.split(':');
  if (parts.length < 2 || parts.length > 3) {
    throw FormatException(
      'Use host:port[:ssl|plain], for example electrum01.chainster.org:50002:ssl',
    );
  }
  final scheme = parts.length == 3 ? parts[2].toLowerCase() : '';
  return _Endpoint(
    host: parts[0],
    port: int.parse(parts[1]),
    useSsl: scheme == 'ssl' || parts[1] == '50002',
  );
}

Future<void> _probeEndpoint(_Endpoint endpoint) async {
  stdout.writeln('## ${endpoint.label}');
  stdout.writeln();

  final client = _ElectrumRpcClient(endpoint);
  try {
    await client.connect();
    final serverVersion = await client.call(
      'server.version',
      const ['CakeWalletPIVXProbe', '1.4'],
    );
    stdout.writeln('- reachable: `true`');
    stdout.writeln('- server_version: `${_compact(serverVersion)}`');

    final capabilities = await _callCapability(client);
    final readiness = _readinessFromCapabilities(capabilities);
    stdout.writeln('- capability_method: `${readiness.method}`');
    stdout.writeln('- contract: `${readiness.contract ?? 'missing'}`');
    stdout.writeln('- release_contract_ready: `${readiness.isReady}`');
    stdout.writeln('- network: `${readiness.network ?? 'missing'}`');
    stdout.writeln(
      '- sapling_activation_height: `${readiness.activationHeight ?? 'missing'}`',
    );
    stdout.writeln('- supports_block_hashes: `${readiness.blockHashes}`');
    stdout.writeln(
      '- supports_global_output_positions: `${readiness.globalPositions}`',
    );
    stdout.writeln('- required_methods_present: `${readiness.methodsPresent}`');

    var liveHelperMethodsReady = true;
    final degradedReasons = <String>[];
    if (!readiness.isReady) {
      degradedReasons.add('capability_not_release_ready');
    }
    for (final probe in _methodProbes) {
      final result = await _callMethodProbe(client, probe);
      liveHelperMethodsReady = liveHelperMethodsReady && result.isSuccess;
      if (!result.isSuccess) {
        degradedReasons.add('method_${probe.label}_${result.status}');
      }
      stdout.writeln('- method_${probe.label}: `${result.summary}`');
    }
    stdout.writeln(
      '- live_helper_methods_ready: `$liveHelperMethodsReady`',
    );

    for (final range in _defaultProbeRanges) {
      final result = await _callRange(client, range.$1, range.$2);
      if (!result.isCompleteV1Envelope) {
        degradedReasons.add('range_${range.$1}_${range.$2}_${result.status}');
      }
      stdout.writeln(
        '- range_${range.$1}_${range.$2}: `${result.summary}`',
      );
    }

    final realOutput = await _findRealSaplingOutput(client);
    if (realOutput == null) {
      degradedReasons.add('real_commitment_unavailable');
      stdout.writeln('- real_commitment: `unavailable`');
    } else {
      stdout.writeln(
        '- real_commitment: `height=${realOutput.height} '
        'position=${realOutput.position} cmu=${_truncateHex(realOutput.cmu)}`',
      );
      final anchorBound = await _callRealWitness(
        client,
        realOutput,
        useAnchor: true,
      );
      if (!anchorBound.isSuccess) {
        degradedReasons.add('real_witness_anchor_bound_${anchorBound.status}');
      }
      stdout.writeln('- real_witness_anchor_bound: `${anchorBound.summary}`');
      final commitmentOnly = await _callRealWitness(
        client,
        realOutput,
        useAnchor: false,
      );
      if (!commitmentOnly.isSuccess) {
        degradedReasons
            .add('real_witness_commitment_only_${commitmentOnly.status}');
      }
      stdout.writeln(
        '- real_witness_commitment_only: `${commitmentOnly.summary}`',
      );
    }

    final tip = await _callCurrentTip(client);
    stdout.writeln('- current_tip: `${tip ?? 'unavailable'}`');
    if (tip != null) {
      final tipRange = await _callRange(client, tip, tip);
      if (!tipRange.isCompleteV1Envelope) {
        degradedReasons.add('range_current_tip_${tipRange.status}');
      }
      stdout.writeln(
        '- range_current_tip_${tip}_$tip: `${tipRange.summary}`',
      );
      if (tip > _pivxSaplingMainnetActivationHeight) {
        final previousTip = tip - 1;
        final previousTipRange = await _callRange(
          client,
          previousTip,
          previousTip,
        );
        if (!previousTipRange.isCompleteV1Envelope) {
          degradedReasons.add('range_previous_tip_${previousTipRange.status}');
        }
        stdout.writeln(
          '- range_previous_tip_${previousTip}_$previousTip: `${previousTipRange.summary}`',
        );
      }
    } else {
      degradedReasons.add('current_tip_unavailable');
    }

    final endpointProbeReady = readiness.isReady &&
        liveHelperMethodsReady &&
        degradedReasons.isEmpty;
    stdout.writeln('- endpoint_probe_ready: `$endpointProbeReady`');
    stdout.writeln(
      '- degraded_reasons: `${degradedReasons.isEmpty ? 'none' : degradedReasons.join(',')}`',
    );
  } catch (error) {
    stdout.writeln('- reachable: `false`');
    stdout.writeln('- error: `${_sanitizeError(error)}`');
    stdout.writeln('- endpoint_probe_ready: `false`');
    stdout.writeln('- degraded_reasons: `endpoint_unreachable`');
  } finally {
    await client.close();
    stdout.writeln();
  }
}

Future<int?> _callCurrentTip(_ElectrumRpcClient client) async {
  try {
    final response = await client.call(
      'blockchain.headers.subscribe',
      const [],
    );
    if (response is Map<String, dynamic>) {
      return _intValue(response['height']);
    }
    return null;
  } catch (_) {
    return null;
  }
}

const _dummyHex32 =
    '0000000000000000000000000000000000000000000000000000000000000000';

const _methodProbes = <_MethodProbe>[
  _MethodProbe(
    label: 'get_best_anchor',
    method: 'blockchain.sapling.get_best_anchor',
    params: [],
  ),
  _MethodProbe(
    label: 'get_nullifier_status_dummy',
    method: 'blockchain.sapling.get_nullifier_status',
    params: [_dummyHex32],
  ),
  _MethodProbe(
    label: 'get_commitment_info_dummy',
    method: 'blockchain.sapling.get_commitment_info',
    params: [_dummyHex32],
  ),
];

Future<_CapabilityResult> _callCapability(_ElectrumRpcClient client) async {
  for (final method in const [
    'blockchain.sapling.capabilities',
    'blockchain.sapling.get_capabilities',
  ]) {
    try {
      final response = await client.call(method, const []);
      if (response is Map<String, dynamic>) {
        return _CapabilityResult(method: method, json: response);
      }
      throw FormatException('capability response was ${response.runtimeType}');
    } catch (error) {
      if (!_isUnsupported(error) && !_isServerMethodFailure(error)) {
        rethrow;
      }
    }
  }

  throw StateError('Sapling capability method unavailable');
}

Future<_ProbeResult> _callMethodProbe(
  _ElectrumRpcClient client,
  _MethodProbe probe,
) async {
  try {
    final response = await client.call(probe.method, probe.params);
    return _ProbeResult(_summarizeMethodResponse(response));
  } catch (error) {
    final status = _isUnsupported(error) ? 'unsupported' : 'error';
    return _ProbeResult('$status=${_sanitizeError(error)}');
  }
}

Future<_RangeResult> _callRange(
  _ElectrumRpcClient client,
  int start,
  int end,
) async {
  try {
    final response = await client.call(
      'blockchain.sapling.get_block_range',
      [start, end],
    );
    if (response is Map<String, dynamic>) {
      final success = response['success'];
      final complete = response['complete'];
      final empty = response['empty'];
      final status = _rangeMapStatus(response);
      final blockHashCount = _collectionLength(response['block_hashes']);
      return _RangeResult(
        'success=$success complete=$complete empty=$empty '
        'height_count=${response['height_count'] ?? 'missing'} '
        'block_hash_count=${blockHashCount ?? 'missing'} '
        'block_count=${response['block_count'] ?? 'missing'} '
        'sapling_tx_count=${response['sapling_tx_count'] ?? 'missing'}',
        status,
      );
    }
    if (response is List<dynamic>) {
      return _RangeResult(
        'legacy_list length=${response.length}',
        'legacy_list',
      );
    }
    return _RangeResult('malformed ${response.runtimeType}', 'malformed');
  } catch (error) {
    return _RangeResult(
      'error=${_sanitizeError(error)}',
      _errorStatus(error),
    );
  }
}

/// Finds a real on-chain Sapling output (commitment + indexed global
/// position) from the activation-era probe ranges so witness probes can run
/// against real chain data instead of dummy values. No wallet secrets are
/// involved; commitments are public chain data.
Future<_RealSaplingOutput?> _findRealSaplingOutput(
  _ElectrumRpcClient client,
) async {
  for (final range in _defaultProbeRanges) {
    try {
      final response = await client.call(
        'blockchain.sapling.get_block_range',
        [range.$1, range.$2],
      );
      if (response is! Map<String, dynamic>) continue;
      if (response['success'] != true || response['complete'] != true) {
        continue;
      }
      final blocks = response['blocks'];
      if (blocks is! List<dynamic>) continue;
      for (final block in blocks) {
        if (block is! Map<String, dynamic>) continue;
        final outputs = block['outputs'];
        if (outputs is! List<dynamic>) continue;
        for (final output in outputs) {
          if (output is! Map<String, dynamic>) continue;
          final cmu = _stringValue(output['cmu']);
          final position = _intValue(output['global_position']) ??
              _intValue(output['position']);
          if (cmu == null || cmu.length != 64 || position == null) continue;
          return _RealSaplingOutput(
            cmu: cmu.toLowerCase(),
            position: position,
            height: _intValue(block['height']) ?? range.$1,
          );
        }
      }
    } catch (_) {
      continue;
    }
  }
  return null;
}

/// Fetches and validates a witness for a real commitment, mirroring the
/// wallet's `getAnchorBoundWitness` acceptance rules: parseable v1 fields,
/// matching commitment, 32 canonical path nodes, and (for the anchor-bound
/// attempt) anchor root/height equal to the requested best anchor.
Future<_ProbeResult> _callRealWitness(
  _ElectrumRpcClient client,
  _RealSaplingOutput output, {
  required bool useAnchor,
}) async {
  try {
    String? requestedAnchor;
    int? requestedAnchorHeight;
    if (useAnchor) {
      final bestAnchor = await client.call(
        'blockchain.sapling.get_best_anchor',
        const [],
      );
      if (bestAnchor is! Map<String, dynamic>) {
        return const _ProbeResult('best_anchor_malformed');
      }
      requestedAnchor = (_stringValue(bestAnchor['anchor']) ??
              _stringValue(bestAnchor['root']))
          ?.toLowerCase();
      requestedAnchorHeight = _intValue(bestAnchor['anchor_height']) ??
          _intValue(bestAnchor['anchorHeight']) ??
          _intValue(bestAnchor['height']);
      if (requestedAnchor == null || requestedAnchorHeight == null) {
        return const _ProbeResult('best_anchor_missing_fields');
      }
    }

    final params = <Object>[output.cmu];
    if (requestedAnchor != null) {
      params.add(requestedAnchor);
    }
    final response = await client.call(
      'blockchain.sapling.get_witness',
      params,
    );
    if (response is! Map<String, dynamic>) {
      return _ProbeResult('malformed ${response.runtimeType}');
    }

    final witnessAnchor = (_stringValue(response['anchor']) ??
            _stringValue(response['root']))
        ?.toLowerCase();
    final witnessAnchorHeight = _intValue(response['anchor_height']) ??
        _intValue(response['height']) ??
        _intValue(response['anchorHeight']);
    final witnessCommitment = (_stringValue(response['commitment']) ??
            _stringValue(response['cmu']))
        ?.toLowerCase();
    final witnessPosition = _intValue(response['position']) ??
        _intValue(response['tree_position']) ??
        _intValue(response['global_position']);
    final rawPath = response['path'] ?? response['witness'];

    final issues = <String>[];
    if (witnessAnchor == null) issues.add('missing_anchor');
    if (witnessAnchorHeight == null) issues.add('missing_anchor_height');
    if (witnessCommitment == null) issues.add('missing_commitment');
    if (witnessPosition == null) issues.add('missing_position');

    var pathCount = 0;
    var canonicalCount = 0;
    if (rawPath is! List<dynamic>) {
      issues.add('missing_path');
    } else {
      pathCount = rawPath.length;
      for (final node in rawPath) {
        if (node is String &&
            node.length == 64 &&
            _isCanonicalSaplingNodeHex(node)) {
          canonicalCount++;
        }
      }
      if (pathCount != 32) issues.add('path_count_$pathCount');
      if (canonicalCount != pathCount) {
        issues.add('non_canonical_nodes_${pathCount - canonicalCount}');
      }
    }

    if (witnessCommitment != null && witnessCommitment != output.cmu) {
      issues.add('commitment_mismatch');
    }
    if (witnessPosition != null && witnessPosition != output.position) {
      issues.add('position_mismatch');
    }
    if (useAnchor) {
      if (witnessAnchor != null && witnessAnchor != requestedAnchor) {
        issues.add('anchor_mismatch');
      }
      if (witnessAnchorHeight != null &&
          witnessAnchorHeight != requestedAnchorHeight) {
        issues.add('anchor_height_mismatch');
      }
    }

    final detail = 'anchor_height=${witnessAnchorHeight ?? 'missing'} '
        'position=${witnessPosition ?? 'missing'} '
        'path_count=$pathCount canonical_count=$canonicalCount';
    if (issues.isNotEmpty) {
      return _ProbeResult('rejected ${issues.join(',')} $detail');
    }
    return _ProbeResult(
      'success source=${useAnchor ? 'anchor_bound' : 'commitment_only'} '
      '$detail',
    );
  } catch (error) {
    final status = _isUnsupported(error) ? 'unsupported' : 'error';
    return _ProbeResult('$status=${_sanitizeError(error)}');
  }
}

final BigInt _jubjubBaseFieldModulus = BigInt.parse(
  '73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001',
  radix: 16,
);

/// Sapling witness nodes are little-endian field-element encodings; mirror
/// the wallet's canonical-node check by reversing byte order before the
/// modulus comparison.
bool _isCanonicalSaplingNodeHex(String hexValue) {
  if (hexValue.length != 64) return false;
  final buffer = StringBuffer();
  for (var i = hexValue.length - 2; i >= 0; i -= 2) {
    buffer.write(hexValue.substring(i, i + 2));
  }
  final value = BigInt.tryParse(buffer.toString(), radix: 16);
  if (value == null) return false;
  return value < _jubjubBaseFieldModulus;
}

String _truncateHex(String value) =>
    value.length <= 18 ? value : '${value.substring(0, 18)}...';

class _RealSaplingOutput {
  const _RealSaplingOutput({
    required this.cmu,
    required this.position,
    required this.height,
  });

  final String cmu;
  final int position;
  final int height;
}

String _rangeMapStatus(Map<String, dynamic> response) {
  if (response['success'] == false) return 'structured_failure';
  if (response['complete'] != true) return 'incomplete';
  if (response['blocks'] is! List<dynamic>) return 'malformed_blocks';

  final heightCount = _intValue(response['height_count']);
  final blockHashCount = _collectionLength(response['block_hashes']);
  if (heightCount != null &&
      blockHashCount != null &&
      blockHashCount < heightCount) {
    return 'missing_block_hashes';
  }

  return 'complete_v1';
}

String _summarizeMethodResponse(Object? response) {
  if (response is Map<String, dynamic>) {
    // Fail-closed v1 servers return structured unavailable responses (for
    // example best-anchor without a canonical witness backend); those are
    // not usable helper results.
    if (response['available'] == false || response['success'] == false) {
      final error = response['error'];
      final errorType = error is Map<String, dynamic>
          ? (error['type'] ?? 'unknown')
          : (error ?? 'unknown');
      return 'unavailable type=$errorType';
    }
    final keys = response.keys.toList()..sort();
    final usefulPairs = <String>[];
    for (final key in const [
      'height',
      'available',
      'tree_size',
      'anchor_height',
      'root',
      'anchor',
      'spent',
      'exists',
      'txid',
      'position',
      'index',
    ]) {
      if (!response.containsKey(key)) continue;
      final value = response[key];
      usefulPairs.add('$key=${_summarizeValue(value)}');
    }
    if (usefulPairs.isNotEmpty) {
      return 'success ${usefulPairs.join(' ')}';
    }
    return 'success keys=${keys.join(',')}';
  }
  if (response is List<dynamic>) {
    return 'success list_length=${response.length}';
  }
  return 'success ${_summarizeValue(response)}';
}

String _summarizeValue(Object? value) {
  if (value == null) return 'null';
  if (value is bool || value is num) return value.toString();
  final text = value.toString();
  if (text.length <= 18) return text;
  return '${text.substring(0, 18)}...';
}

_Readiness _readinessFromCapabilities(_CapabilityResult result) {
  final json = result.json;
  final methods = <String>{};
  final rawMethods = json['methods'] ?? json['supported_methods'];
  if (rawMethods is List<dynamic>) {
    methods.addAll(rawMethods.map((value) => value.toString()));
  }
  final aliases = json['aliases'];
  if (aliases is Map<dynamic, dynamic>) {
    methods.addAll(aliases.keys.map((key) => key.toString()));
    for (final value in aliases.values) {
      if (value is List<dynamic>) {
        methods.addAll(value.map((entry) => entry.toString()));
      } else if (value != null) {
        methods.add(value.toString());
      }
    }
  }

  final features = json['features'];
  final rangeFormat = json['range_response_format'];
  final contract =
      _stringValue(json['contract']) ?? _stringValue(json['contract_id']);
  final globalPositions = json['global_output_positions'] == true ||
      json['supports_global_output_positions'] == true ||
      (features is Map<dynamic, dynamic> &&
          features['global_output_positions'] == true) ||
      (rangeFormat is Map<dynamic, dynamic> &&
          rangeFormat['global_output_positions'] == true);
  final blockHashes = json['block_hashes'] == true ||
      json['supports_block_hashes'] == true ||
      (features is Map<dynamic, dynamic> && features['block_hashes'] == true) ||
      (rangeFormat is Map<dynamic, dynamic> &&
          rangeFormat['block_hashes'] == true);
  final structuredErrors = json['structured_errors'] == true ||
      json['supports_structured_errors'] == true ||
      (features is Map<dynamic, dynamic> &&
          features['structured_errors'] == true);
  final methodsPresent = methods.containsAll(_requiredV1Methods);
  final readyFlag = json['release_contract_ready'] == true;
  final computedReady = contract == 'pivx.sapling.electrumx.v1' &&
      globalPositions &&
      blockHashes &&
      structuredErrors &&
      methodsPresent;

  return _Readiness(
    method: result.method,
    contract: contract,
    isReady: readyFlag || computedReady,
    network: _stringValue(json['network']),
    activationHeight: _intValue(json['sapling_activation_height']) ??
        _intValue(json['activation_height']),
    blockHashes: blockHashes,
    globalPositions: globalPositions,
    methodsPresent: methodsPresent,
  );
}

String? _stringValue(Object? value) {
  if (value == null) return null;
  final text = value.toString();
  return text.isEmpty ? null : text;
}

int? _intValue(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

int? _collectionLength(Object? value) {
  if (value is Map<dynamic, dynamic>) return value.length;
  if (value is Iterable<dynamic>) return value.length;
  return null;
}

bool _isUnsupported(Object error) {
  final text = error.toString().toLowerCase();
  return text.contains('unknown method') ||
      text.contains('method not found') ||
      text.contains('unsupported') ||
      text.contains('method unavailable');
}

bool _isServerMethodFailure(Object error) {
  final text = error.toString().toLowerCase();
  return text.contains('internal server error') ||
      text.contains('server error');
}

String _compact(Object? value) => jsonEncode(value);

String _sanitizeError(Object error) {
  final text = error.toString().replaceAll('\n', ' ');
  return text.length <= 180 ? text : '${text.substring(0, 180)}...';
}

String _errorStatus(Object error) {
  final text = error.toString().toLowerCase();
  if (text.contains('timeout') || text.contains('timed out')) {
    return 'timeout';
  }
  if (_isUnsupported(error)) return 'unsupported';
  if (_isServerMethodFailure(error)) return 'server_error';
  if (text.contains('connection closed') ||
      text.contains('connection refused') ||
      text.contains('socket')) {
    return 'connection_error';
  }
  return 'error';
}

class _Endpoint {
  const _Endpoint({
    required this.host,
    required this.port,
    required this.useSsl,
    this.isDefault = false,
  });

  final String host;
  final int port;
  final bool useSsl;
  final bool isDefault;

  String get label =>
      '$host:$port ${useSsl ? 'ssl' : 'plain'}${isDefault ? ' default' : ''}';
}

class _CapabilityResult {
  const _CapabilityResult({
    required this.method,
    required this.json,
  });

  final String method;
  final Map<String, dynamic> json;
}

class _MethodProbe {
  const _MethodProbe({
    required this.label,
    required this.method,
    required this.params,
  });

  final String label;
  final String method;
  final List<Object> params;
}

class _Readiness {
  const _Readiness({
    required this.method,
    required this.contract,
    required this.isReady,
    required this.network,
    required this.activationHeight,
    required this.blockHashes,
    required this.globalPositions,
    required this.methodsPresent,
  });

  final String method;
  final String? contract;
  final bool isReady;
  final String? network;
  final int? activationHeight;
  final bool blockHashes;
  final bool globalPositions;
  final bool methodsPresent;
}

class _ProbeResult {
  const _ProbeResult(this.summary);

  final String summary;

  bool get isSuccess => summary.startsWith('success');

  String get status => isSuccess ? 'success' : _summaryStatus(summary);
}

class _RangeResult {
  const _RangeResult(this.summary, this.status);

  final String summary;
  final String status;

  bool get isCompleteV1Envelope => status == 'complete_v1';
}

String _summaryStatus(String summary) {
  if (summary.contains('timed out') || summary.contains('TimeoutException')) {
    return 'timeout';
  }
  if (summary.startsWith('unsupported=')) return 'unsupported';
  if (summary.contains('internal server error') ||
      summary.contains('server error')) {
    return 'server_error';
  }
  return 'error';
}

class _ElectrumRpcClient {
  _ElectrumRpcClient(this.endpoint);

  final _Endpoint endpoint;
  final _pending = <int, Completer<Object?>>{};
  StreamSubscription<String>? _subscription;
  Socket? _socket;
  int _nextId = 0;

  Future<void> connect() async {
    final socket = endpoint.useSsl
        ? await SecureSocket.connect(
            endpoint.host,
            endpoint.port,
            timeout: const Duration(seconds: 12),
            onBadCertificate: (_) => false,
          )
        : await Socket.connect(
            endpoint.host,
            endpoint.port,
            timeout: const Duration(seconds: 12),
          );
    _socket = socket;
    _subscription = utf8.decoder
        .bind(socket)
        .transform(const LineSplitter())
        .listen(_handleLine, onError: _handleError, onDone: _handleDone);
  }

  Future<Object?> call(String method, List<Object> params) {
    final socket = _socket;
    if (socket == null) {
      throw StateError('Not connected');
    }

    final id = ++_nextId;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    socket.writeln(jsonEncode({
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params,
    }));

    return completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        _pending.remove(id);
        throw TimeoutException('RPC $method timed out');
      },
    );
  }

  Future<void> close() async {
    await _subscription?.cancel();
    _socket?.destroy();
    _socket = null;
  }

  void _handleLine(String line) {
    if (line.trim().isEmpty) return;
    final decoded = jsonDecode(line);
    if (decoded is! Map<String, dynamic>) return;
    final id = decoded['id'];
    if (id is! int) return;
    final completer = _pending.remove(id);
    if (completer == null || completer.isCompleted) return;
    final error = decoded['error'];
    if (error != null) {
      completer.completeError(StateError(_compact(error)));
      return;
    }
    completer.complete(decoded['result']);
  }

  void _handleError(Object error) {
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    }
    _pending.clear();
  }

  void _handleDone() {
    _handleError(StateError('Connection closed'));
  }
}
