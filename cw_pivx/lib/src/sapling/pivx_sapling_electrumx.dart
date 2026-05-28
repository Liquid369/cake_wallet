/// PIVX Sapling ElectrumX API client.
///
/// This module provides type-safe access to PIVX Sapling-specific
/// ElectrumX RPC methods for shielded transaction support.
///
/// ## API Methods
///
/// - `blockchain.nullifier.get_spend` - Check if nullifier is spent
/// - `blockchain.commitment.get_info` - Get commitment details
/// - `blockchain.sapling.get_outputs` - Get shielded outputs for trial decryption
/// - `blockchain.sapling.get_block_range` - Get blocks with Sapling txs
/// - `blockchain.sapling.get_nullifiers` - Get nullifiers in height range
/// - `blockchain.sapling.get_tree_state` - Get tree state at height
/// - `blockchain.sapling.get_witness` - Get Merkle witness for spending
/// - `blockchain.anchor.get_height` - Get height for anchor
///
/// ## Activation Heights
///
/// - Mainnet: 2,700,500
/// - Testnet: 1,164,637

import 'dart:typed_data';
import 'package:convert/convert.dart';

int? _optionalInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

/// Helper class for batch fetch results.
class _BatchResult {
  final List<SaplingBlock> blocks;
  final int endHeight;
  _BatchResult(this.blocks, this.endHeight);
}

class SaplingRpcException implements Exception {
  final String message;
  final Object? cause;

  SaplingRpcException(this.message, [this.cause]);

  @override
  String toString() => cause == null ? message : '$message: $cause';
}

class SaplingRpcCapabilities {
  final bool supportsBlockRange;
  final bool supportsGlobalOutputPositions;
  final bool supportsBestAnchor;
  final bool supportsWitness;
  final String? network;
  final int? activationHeight;
  final Set<String> methods;

  const SaplingRpcCapabilities({
    required this.supportsBlockRange,
    required this.supportsGlobalOutputPositions,
    required this.supportsBestAnchor,
    required this.supportsWitness,
    this.network,
    this.activationHeight,
    this.methods = const {},
  });

  factory SaplingRpcCapabilities.fromJson(Map<String, dynamic> json) {
    final rawMethods = json['methods'] as List<dynamic>? ??
        json['supported_methods'] as List<dynamic>?;
    final methodList =
        rawMethods?.map((e) => e.toString()).toSet() ?? const <String>{};
    final features = json['features'] as Map<String, dynamic>?;
    final network = json['network'] as String?;
    final activationHeight = _optionalInt(json['sapling_activation_height']) ??
        _optionalInt(json['activation_height']);

    bool hasMethod(String name) => methodList.contains(name);

    return SaplingRpcCapabilities(
      supportsBlockRange: hasMethod('blockchain.sapling.get_block_range') ||
          json['supports_block_range'] == true,
      supportsGlobalOutputPositions: json['global_output_positions'] == true ||
          json['supports_global_output_positions'] == true ||
          features?['global_output_positions'] == true,
      supportsBestAnchor: hasMethod('blockchain.sapling.get_best_anchor') ||
          hasMethod('blockchain.sapling.get_tree_state') ||
          json['supports_best_anchor'] == true,
      supportsWitness: hasMethod('blockchain.sapling.get_witness') ||
          json['supports_witness'] == true,
      network: network,
      activationHeight: activationHeight,
      methods: methodList,
    );
  }

  static SaplingRpcCapabilities legacyBlockRangeOnly() =>
      const SaplingRpcCapabilities(
        supportsBlockRange: true,
        supportsGlobalOutputPositions: false,
        supportsBestAnchor: false,
        supportsWitness: false,
      );
}

/// PIVX Sapling activation heights.
class SaplingActivation {
  static const int mainnet = 2700500;
  static const int testnet = 1164637;
}

/// Result from get_nullifier_status RPC.
class NullifierStatus {
  /// Whether the nullifier has been spent.
  final bool spent;

  /// Transaction ID where the nullifier was spent (if spent).
  final String? txid;

  /// Block height where the nullifier was spent (if spent).
  final int? height;

  NullifierStatus({
    required this.spent,
    this.txid,
    this.height,
  });

  factory NullifierStatus.fromJson(Map<String, dynamic> json) {
    return NullifierStatus(
      spent: json['spent'] as bool? ?? false,
      txid: json['txid'] as String?,
      height: json['height'] as int?,
    );
  }
}

/// Result from get_commitment_info RPC.
class CommitmentInfo {
  /// Whether the commitment exists in the tree.
  final bool exists;

  /// Transaction ID containing the commitment (if exists).
  final String? txid;

  /// Block height of the transaction (if exists).
  final int? height;

  /// Index of the commitment in the tree (if exists).
  final int? index;

  CommitmentInfo({
    required this.exists,
    this.txid,
    this.height,
    this.index,
  });

  factory CommitmentInfo.fromJson(Map<String, dynamic> json) {
    return CommitmentInfo(
      exists: json['exists'] as bool? ?? false,
      txid: json['txid'] as String?,
      height: json['height'] as int?,
      index: json['index'] as int?,
    );
  }
}

/// A Sapling shielded output from the blockchain.
class SaplingShieldedOutput {
  /// Note commitment (cmu) - 32 bytes hex.
  final String cmu;

  /// Ephemeral public key - 32 bytes hex.
  final String epk;

  /// Encrypted note ciphertext - 580 bytes hex (1160 hex chars).
  final String ciphertext;

  /// Value commitment (cv) - 32 bytes hex.
  final String cv;

  /// Outgoing ciphertext - 80 bytes hex (160 hex chars).
  final String outCiphertext;

  /// Canonical global Sapling commitment tree position, if returned by server.
  final int? globalPosition;

  SaplingShieldedOutput({
    required this.cmu,
    required this.epk,
    required this.ciphertext,
    required this.cv,
    required this.outCiphertext,
    this.globalPosition,
  });

  factory SaplingShieldedOutput.fromJson(Map<String, dynamic> json) {
    return SaplingShieldedOutput(
      cmu: json['cmu'] as String,
      epk: json['epk'] as String,
      ciphertext: json['ciphertext'] as String,
      cv: json['cv'] as String,
      outCiphertext: json['out_ciphertext'] as String,
      globalPosition: _optionalInt(json['global_position']) ??
          _optionalInt(json['tree_position']) ??
          _optionalInt(json['position']) ??
          _optionalInt(json['index']),
    );
  }

  /// Get cmu as bytes.
  Uint8List get cmuBytes => Uint8List.fromList(hex.decode(cmu));

  /// Get epk as bytes.
  Uint8List get epkBytes => Uint8List.fromList(hex.decode(epk));

  /// Get encrypted ciphertext as bytes.
  Uint8List get ciphertextBytes => Uint8List.fromList(hex.decode(ciphertext));

  /// Get value commitment as bytes.
  Uint8List get cvBytes => Uint8List.fromList(hex.decode(cv));

  /// Get outgoing ciphertext as bytes.
  Uint8List get outCiphertextBytes =>
      Uint8List.fromList(hex.decode(outCiphertext));
}

/// Result from get_outputs_by_height RPC.
class SaplingOutputsResult {
  /// Start height of the range.
  final int startHeight;

  /// End height of the range.
  final int endHeight;

  /// Total number of outputs in the range.
  final int totalOutputs;

  /// The shielded outputs.
  final List<SaplingShieldedOutput> outputs;

  /// Whether results were truncated due to limit.
  final bool truncated;

  SaplingOutputsResult({
    required this.startHeight,
    required this.endHeight,
    required this.totalOutputs,
    required this.outputs,
    required this.truncated,
  });

  factory SaplingOutputsResult.fromJson(Map<String, dynamic> json) {
    final outputsList = (json['outputs'] as List<dynamic>?)
            ?.map((e) =>
                SaplingShieldedOutput.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];

    return SaplingOutputsResult(
      startHeight: json['start_height'] as int,
      endHeight: json['end_height'] as int,
      totalOutputs: json['total_outputs'] as int? ?? outputsList.length,
      outputs: outputsList,
      truncated: json['truncated'] as bool? ?? false,
    );
  }
}

/// A Sapling spend from the blockchain.
class SaplingSpend {
  /// Nullifier being revealed (marks a note as spent).
  final String nullifier;

  /// Value commitment.
  final String cv;

  /// Anchor used for the spend proof (Merkle tree root).
  final String anchor;

  /// Randomized public key.
  final String rk;

  SaplingSpend({
    required this.nullifier,
    required this.cv,
    required this.anchor,
    required this.rk,
  });

  factory SaplingSpend.fromJson(Map<String, dynamic> json) {
    return SaplingSpend(
      nullifier: json['nullifier'] as String,
      cv: json['cv'] as String,
      anchor: json['anchor'] as String,
      rk: json['rk'] as String,
    );
  }

  /// Get nullifier as bytes.
  Uint8List get nullifierBytes => Uint8List.fromList(hex.decode(nullifier));

  /// Get value commitment as bytes.
  Uint8List get cvBytes => Uint8List.fromList(hex.decode(cv));

  /// Get anchor as bytes.
  Uint8List get anchorBytes => Uint8List.fromList(hex.decode(anchor));

  /// Get randomized public key as bytes.
  Uint8List get rkBytes => Uint8List.fromList(hex.decode(rk));
}

/// A Sapling transaction from get_block_range.
class SaplingTransaction {
  /// Transaction ID.
  final String txid;

  /// Shielded outputs (new notes being created).
  final List<SaplingShieldedOutput> outputs;

  /// Shielded spends (notes being spent, nullifiers revealed).
  final List<SaplingSpend> spends;

  SaplingTransaction({
    required this.txid,
    required this.outputs,
    required this.spends,
  });

  factory SaplingTransaction.fromJson(Map<String, dynamic> json) {
    return SaplingTransaction(
      txid: json['txid'] as String,
      outputs: (json['outputs'] as List<dynamic>?)
              ?.map((e) =>
                  SaplingShieldedOutput.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      spends: (json['spends'] as List<dynamic>?)
              ?.map((e) => SaplingSpend.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

/// A block containing Sapling transactions.
class SaplingBlock {
  /// Block height.
  final int height;

  /// Block hash.
  final String hash;

  /// Block timestamp (unix epoch).
  final int time;

  /// Sapling transactions in this block.
  final List<SaplingTransaction> txs;

  SaplingBlock({
    required this.height,
    required this.hash,
    required this.time,
    required this.txs,
  });

  factory SaplingBlock.fromJson(Map<String, dynamic> json) {
    return SaplingBlock(
      height: json['height'] as int,
      hash: json['hash'] as String,
      time: json['time'] as int,
      txs: (json['txs'] as List<dynamic>?)
              ?.map(
                  (e) => SaplingTransaction.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  /// Get total number of outputs in this block.
  int get outputCount {
    int count = 0;
    for (final tx in txs) {
      count += tx.outputs.length;
    }
    return count;
  }

  /// Get total number of spends in this block.
  int get spendCount {
    int count = 0;
    for (final tx in txs) {
      count += tx.spends.length;
    }
    return count;
  }

  /// Get all nullifiers from this block.
  List<Uint8List> get allNullifiers {
    final nullifiers = <Uint8List>[];
    for (final tx in txs) {
      for (final spend in tx.spends) {
        nullifiers.add(spend.nullifierBytes);
      }
    }
    return nullifiers;
  }

  /// Get all outputs from this block.
  List<SaplingShieldedOutput> get allOutputs {
    final outputs = <SaplingShieldedOutput>[];
    for (final tx in txs) {
      outputs.addAll(tx.outputs);
    }
    return outputs;
  }
}

/// Result from get_best_anchor RPC.
class BestAnchorResult {
  /// The current best anchor (Merkle root).
  final String anchor;

  /// Block height of the anchor.
  final int height;

  BestAnchorResult({
    required this.anchor,
    required this.height,
  });

  factory BestAnchorResult.fromJson(Map<String, dynamic> json) {
    return BestAnchorResult(
      anchor: json['anchor'] as String,
      height: json['height'] as int,
    );
  }

  /// Get anchor as bytes.
  Uint8List get anchorBytes => Uint8List.fromList(hex.decode(anchor));
}

/// Anchor-bound Merkle witness for spend proof construction.
class SaplingWitnessResult {
  final int position;
  final List<String> path;
  final String anchor;
  final int anchorHeight;
  final String commitment;
  final Map<String, dynamic> raw;

  SaplingWitnessResult({
    required this.position,
    required this.path,
    required this.anchor,
    required this.anchorHeight,
    required this.commitment,
    required this.raw,
  });

  factory SaplingWitnessResult.fromJson(Map<String, dynamic> json) {
    final path = json['path'] as List<dynamic>?;
    final anchor = json['anchor'] as String? ?? json['root'] as String?;
    final anchorHeight = _optionalInt(json['anchor_height']) ??
        _optionalInt(json['height']) ??
        _optionalInt(json['anchorHeight']);
    final commitment = json['commitment'] as String? ??
        json['cmu'] as String? ??
        json['commitment_hex'] as String?;
    final position = _optionalInt(json['position']) ??
        _optionalInt(json['tree_position']) ??
        _optionalInt(json['global_position']);

    if (path == null || path.isEmpty) {
      throw SaplingRpcException('PIVX Sapling witness response has no path');
    }
    if (anchor == null || anchor.isEmpty) {
      throw SaplingRpcException('PIVX Sapling witness response has no anchor');
    }
    if (anchorHeight == null) {
      throw SaplingRpcException(
          'PIVX Sapling witness response has no anchor height');
    }
    if (commitment == null || commitment.isEmpty) {
      throw SaplingRpcException(
          'PIVX Sapling witness response has no commitment');
    }
    if (position == null) {
      throw SaplingRpcException(
          'PIVX Sapling witness response has no note position');
    }

    return SaplingWitnessResult(
      position: position,
      path: path.map((e) => e.toString()).toList(),
      anchor: anchor,
      anchorHeight: anchorHeight,
      commitment: commitment,
      raw: Map<String, dynamic>.from(json),
    );
  }
}

/// PIVX Sapling ElectrumX client extension.
///
/// Provides Sapling-specific RPC methods for shielded transaction support.
/// This class wraps an existing ElectrumX client to add Sapling methods.
class PIVXSaplingElectrumX {
  /// The underlying ElectrumX client.
  /// This should be the electrumClient from ElectrumWallet.
  final dynamic _client;

  /// Whether this is testnet.
  final bool isTestnet;

  PIVXSaplingElectrumX({
    required dynamic electrumClient,
    this.isTestnet = false,
  }) : _client = electrumClient;

  SaplingRpcCapabilities? _capabilities;

  /// Get the Sapling activation height for this network.
  int get activationHeight =>
      isTestnet ? SaplingActivation.testnet : SaplingActivation.mainnet;

  Future<dynamic> _callFirstSupported({
    required List<String> methods,
    required List<Object> params,
  }) async {
    Object? lastError;
    for (final method in methods) {
      try {
        return await _client.call(method: method, params: params);
      } catch (e) {
        lastError = e;
        if (!_looksLikeUnsupportedMethod(e)) rethrow;
      }
    }
    throw SaplingRpcException('PIVX Sapling RPC method unavailable', lastError);
  }

  bool _looksLikeUnsupportedMethod(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('method not found') ||
        text.contains('unknown method') ||
        text.contains('unsupported') ||
        text.contains('not implemented');
  }

  /// Probe the Sapling RPC policy/capabilities for the active node.
  Future<SaplingRpcCapabilities> probeCapabilities() async {
    if (_capabilities != null) return _capabilities!;

    try {
      final result = await _client.call(
        method: 'blockchain.sapling.get_capabilities',
        params: <Object>[],
      );
      if (result is! Map) {
        throw SaplingRpcException(
            'PIVX Sapling capability probe returned ${result.runtimeType}');
      }
      final capabilities =
          SaplingRpcCapabilities.fromJson(Map<String, dynamic>.from(result));
      if (!capabilities.supportsBlockRange) {
        throw SaplingRpcException(
            'PIVX Sapling node does not advertise get_block_range');
      }
      if (capabilities.network != null) {
        final expected = isTestnet ? 'testnet' : 'mainnet';
        if (capabilities.network!.toLowerCase() != expected) {
          throw SaplingRpcException(
              'PIVX Sapling node network mismatch: expected $expected');
        }
      }
      if (capabilities.activationHeight != null &&
          capabilities.activationHeight != activationHeight) {
        throw SaplingRpcException(
            'PIVX Sapling activation height mismatch for current network');
      }
      _capabilities = capabilities;
      return capabilities;
    } catch (e) {
      if (!_looksLikeUnsupportedMethod(e)) rethrow;

      // Legacy sapling_integration fork: prove block-range support, but do not
      // assume global positions, witnesses, or v1 policy metadata exist.
      await getBlockRange(activationHeight, endHeight: activationHeight);
      _capabilities = SaplingRpcCapabilities.legacyBlockRangeOnly();
      return _capabilities!;
    }
  }

  /// Check if a nullifier has been spent.
  ///
  /// [nullifier] - 32-byte nullifier as hex string.
  Future<NullifierStatus> getNullifierStatus(String nullifier) async {
    final result = await _callFirstSupported(
      methods: const [
        'blockchain.sapling.get_nullifier_status',
        'blockchain.nullifier.get_spend',
      ],
      params: <Object>[nullifier],
    );
    return NullifierStatus.fromJson(result as Map<String, dynamic>);
  }

  /// Get information about a note commitment.
  ///
  /// [commitment] - 32-byte cmu as hex string.
  Future<CommitmentInfo> getCommitmentInfo(String commitment) async {
    final result = await _callFirstSupported(
      methods: const [
        'blockchain.sapling.get_commitment_info',
        'blockchain.commitment.get_info',
      ],
      params: <Object>[commitment],
    );
    return CommitmentInfo.fromJson(result as Map<String, dynamic>);
  }

  /// Get Sapling outputs in a block range.
  ///
  /// [startHeight] - Starting block height (inclusive).
  /// [endHeight] - Ending block height (inclusive), defaults to startHeight.
  /// [limit] - Max outputs to return (default 1000, max 5000).
  ///
  /// Note: Max 100 blocks per request.
  Future<SaplingOutputsResult> getOutputsByHeight(
    int startHeight, {
    int? endHeight,
    int? limit,
  }) async {
    final params = <Object>[startHeight];
    if (endHeight != null) params.add(endHeight);
    if (limit != null) params.add(limit);

    final result = await _callFirstSupported(
      methods: const [
        'blockchain.sapling.get_outputs_by_height',
        'blockchain.sapling.get_outputs',
      ],
      params: params,
    );
    return SaplingOutputsResult.fromJson(result as Map<String, dynamic>);
  }

  /// Get blocks with Sapling transactions in pivx-shield format.
  ///
  /// [startHeight] - Starting block height (inclusive).
  /// [endHeight] - Ending block height (inclusive), defaults to startHeight.
  ///
  /// Note: Max 100 blocks per request.
  /// Only blocks containing Sapling transactions are returned.
  Future<List<SaplingBlock>> getBlockRange(
    int startHeight, {
    int? endHeight,
  }) async {
    final params = <Object>[startHeight];
    if (endHeight != null) params.add(endHeight);

    final result = await _client.call(
      method: 'blockchain.sapling.get_block_range',
      params: params,
    );

    if (result == null) {
      throw SaplingRpcException(
        'PIVX Sapling get_block_range returned null for $startHeight-${endHeight ?? startHeight}',
      );
    }

    dynamic blocksResult = result;
    if (result is Map) {
      if (result['complete'] != true) {
        throw SaplingRpcException(
          'PIVX Sapling get_block_range returned an incomplete range for $startHeight-${endHeight ?? startHeight}',
        );
      }
      final responseStart = _optionalInt(result['from_height']) ??
          _optionalInt(result['start_height']) ??
          _optionalInt(result['from']);
      final responseEnd = _optionalInt(result['to_height']) ??
          _optionalInt(result['end_height']) ??
          _optionalInt(result['to']);
      if (responseStart != null && responseStart != startHeight) {
        throw SaplingRpcException(
          'PIVX Sapling get_block_range returned a mismatched start height',
        );
      }
      if (responseEnd != null && responseEnd != (endHeight ?? startHeight)) {
        throw SaplingRpcException(
          'PIVX Sapling get_block_range returned a mismatched end height',
        );
      }
      blocksResult = result['blocks'];
    }

    if (blocksResult is! List) {
      throw SaplingRpcException(
        'PIVX Sapling get_block_range returned ${blocksResult.runtimeType} for $startHeight-${endHeight ?? startHeight}',
      );
    }

    if (blocksResult.isEmpty) {
      return [];
    }

    return blocksResult
        .map((e) => SaplingBlock.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Get the block height where an anchor was valid.
  ///
  /// [anchor] - 32-byte Merkle root as hex string.
  /// Returns null if anchor not found.
  Future<int?> getAnchorHeight(String anchor) async {
    final result = await _callFirstSupported(
      methods: const [
        'blockchain.sapling.get_anchor_height',
        'blockchain.anchor.get_height',
      ],
      params: <Object>[anchor],
    );
    return result as int?;
  }

  /// Get the best (most recent) anchor and its height.
  ///
  /// This gets the tree state at the most recent height that has one.
  /// Not every block has a tree state - only blocks with Sapling activity.
  ///
  /// [maxHeight] - Optional maximum height to search from. If null, uses chain tip.
  Future<BestAnchorResult> getBestAnchor({int? maxHeight}) async {
    try {
      final result = await _client.call(
        method: 'blockchain.sapling.get_best_anchor',
        params: maxHeight == null ? <Object>[] : <Object>[maxHeight],
      );
      if (result is Map<String, dynamic>) {
        return BestAnchorResult.fromJson(result);
      }
    } catch (e) {
      if (!_looksLikeUnsupportedMethod(e)) rethrow;
    }

    // Get current chain height if not specified
    int searchHeight = maxHeight ?? 0;
    if (searchHeight == 0) {
      final headersResult = await _client.call(
        method: 'blockchain.headers.subscribe',
        params: <Object>[],
      );
      searchHeight = headersResult['height'] as int;
    }

    // Try to get tree state at search height
    var treeState = await getTreeState(searchHeight);

    // If no tree state at current height, search backwards
    // The server may only have tree states for blocks with Sapling txs
    if (treeState == null) {
      // Try recent heights with Sapling activity
      // Search in decreasing order, checking every 100 blocks then binary search
      int step = 1000;
      int minHeight = activationHeight;

      while (treeState == null && searchHeight > minHeight) {
        searchHeight -= step;
        if (searchHeight < minHeight) searchHeight = minHeight;
        treeState = await getTreeState(searchHeight);

        // If still null and step is large, reduce step size
        if (treeState == null && step > 10) {
          searchHeight += step; // Go back
          step = step ~/ 10; // Reduce step
        }
      }
    }

    if (treeState == null) {
      throw Exception(
          'Could not find any tree state from height $maxHeight down to $activationHeight');
    }

    final anchor =
        treeState['root'] as String? ?? treeState['anchor'] as String?;
    if (anchor == null) {
      throw Exception('Tree state at height $searchHeight has no root/anchor');
    }

    return BestAnchorResult(
      anchor: anchor,
      height: searchHeight,
    );
  }

  /// Get nullifiers spent in a height range.
  ///
  /// [startHeight] - Starting block height (inclusive).
  /// [endHeight] - Ending block height (inclusive).
  Future<List<String>> getNullifiersInRange(
      int startHeight, int endHeight) async {
    final result = await _client.call(
      method: 'blockchain.sapling.get_nullifiers',
      params: <Object>[startHeight, endHeight],
    );
    if (result == null) return [];
    return (result as List<dynamic>).map((e) => e.toString()).toList();
  }

  /// Get Sapling commitment tree state at a height.
  ///
  /// [height] - Block height.
  Future<Map<String, dynamic>?> getTreeState(int height) async {
    final result = await _callFirstSupported(
        methods: const ['blockchain.sapling.get_tree_state'],
        params: <Object>[height]);
    return result as Map<String, dynamic>?;
  }

  /// Get Merkle witness for spend proof construction.
  ///
  /// [commitment] - 32-byte commitment (cmu) as hex.
  /// [anchorHeight] - Block height of anchor.
  Future<Map<String, dynamic>?> getWitness(
      String commitment, int anchorHeight) async {
    final result = await _callFirstSupported(
        methods: const ['blockchain.sapling.get_witness'],
        params: <Object>[commitment, anchorHeight]);
    return result as Map<String, dynamic>?;
  }

  /// Get a witness that is explicitly bound to the selected anchor.
  ///
  /// Shielded spend construction must sign with the same anchor used to build
  /// every witness path. Nodes that omit anchor metadata, return a witness for
  /// a different anchor height/root, or return a different commitment are
  /// rejected before proving starts.
  Future<SaplingWitnessResult> getAnchorBoundWitness({
    required String commitment,
    required BestAnchorResult anchor,
  }) async {
    final witnessData = await getWitness(commitment, anchor.height);
    if (witnessData == null) {
      throw SaplingRpcException('PIVX Sapling witness response is null');
    }

    final witness =
        SaplingWitnessResult.fromJson(Map<String, dynamic>.from(witnessData));
    if (witness.anchor.toLowerCase() != anchor.anchor.toLowerCase()) {
      throw SaplingRpcException(
          'PIVX Sapling witness anchor does not match selected anchor');
    }
    if (witness.anchorHeight != anchor.height) {
      throw SaplingRpcException(
          'PIVX Sapling witness height does not match selected anchor height');
    }
    if (witness.commitment.toLowerCase() != commitment.toLowerCase()) {
      throw SaplingRpcException(
          'PIVX Sapling witness commitment does not match requested note');
    }

    return witness;
  }

  /// Get Sapling data for a specific transaction.
  ///
  /// [txid] - Transaction ID as hex.
  Future<Map<String, dynamic>?> getTransactionSapling(String txid) async {
    final result = await _callFirstSupported(
        methods: const ['blockchain.transaction.get_sapling'],
        params: <Object>[txid]);
    return result as Map<String, dynamic>?;
  }

  /// Convenience method to sync blocks in batches.
  ///
  /// [fromHeight] - Starting height.
  /// [toHeight] - Target height.
  /// [batchSize] - Blocks per batch (server may support up to 1000).
  /// [parallelBatches] - Number of parallel batch requests.
  /// [onBatch] - Callback for each batch of blocks.
  /// [onRangeComplete] - Callback when a range completes (even if empty).
  Future<void> syncBlocks({
    required int fromHeight,
    required int toHeight,
    int batchSize = 100,
    int parallelBatches = 5,
    required Future<void> Function(List<SaplingBlock> blocks) onBatch,
    Future<void> Function(int rangeEnd)? onRangeComplete,
  }) async {
    // Server enforces max 100 blocks per request
    final effectiveBatchSize = batchSize.clamp(1, 100);

    int currentStart = fromHeight;

    while (currentStart <= toHeight) {
      // Create parallel batch requests
      final batchFutures = <Future<_BatchResult>>[];

      for (int i = 0;
          i < parallelBatches &&
              currentStart + i * effectiveBatchSize <= toHeight;
          i++) {
        final start = currentStart + i * effectiveBatchSize;
        final end =
            (start + effectiveBatchSize - 1).clamp(fromHeight, toHeight);

        batchFutures.add(_fetchBatchWithRetry(start, end));
      }

      // Wait for all parallel batches
      final results = await Future.wait(batchFutures);

      // Process results in order
      for (final result in results) {
        if (result.blocks.isNotEmpty) {
          await onBatch(result.blocks);
        }
        await onRangeComplete?.call(result.endHeight);
      }

      currentStart += parallelBatches * effectiveBatchSize;
    }
  }

  /// Fetch a batch with retry logic.
  Future<_BatchResult> _fetchBatchWithRetry(int start, int end,
      {int retries = 2}) async {
    for (int attempt = 0; attempt <= retries; attempt++) {
      try {
        final blocks = await getBlockRange(start, endHeight: end);
        return _BatchResult(blocks, end);
      } catch (e) {
        if (attempt == retries) {
          throw SaplingRpcException(
            'PIVX Sapling block range $start-$end failed after ${retries + 1} attempts',
            e,
          );
        }
        await Future.delayed(Duration(milliseconds: 100 * (attempt + 1)));
      }
    }
    throw SaplingRpcException('PIVX Sapling block range $start-$end failed');
  }

  /// Check multiple nullifiers for spent status.
  ///
  /// Returns a map of nullifier -> spent status.
  Future<Map<String, bool>> checkNullifiers(List<String> nullifiers) async {
    final results = <String, bool>{};

    // Check in parallel for efficiency
    final futures = nullifiers.map((nf) async {
      final status = await getNullifierStatus(nf);
      return MapEntry(nf, status.spent);
    });

    final entries = await Future.wait(futures);
    results.addEntries(entries);

    return results;
  }
}
