/// PIVX Sapling ElectrumX API client.
///
/// This module provides type-safe access to PIVX Sapling-specific
/// ElectrumX RPC methods for shielded transaction support.
///
/// ## API Methods
///
/// - `blockchain.sapling.capabilities` - Probe v1 Sapling RPC contract metadata
/// - `blockchain.sapling.get_block_range` - Get v1 block-range envelopes
/// - `blockchain.sapling.get_nullifier_status` - Check if nullifier is spent
/// - `blockchain.sapling.get_commitment_info` - Get commitment details
/// - `blockchain.sapling.get_best_anchor` - Get current anchor metadata
/// - `blockchain.sapling.get_witness` - Get anchor-bound Merkle witness data
/// - legacy aliases remain as fallbacks until default nodes expose v1 metadata
///
/// ## Activation Heights
///
/// - Mainnet: 2,700,500
/// - Testnet: 201

import 'dart:typed_data';
import 'package:convert/convert.dart';
import 'package:cw_core/utils/print_verbose.dart';

int? _optionalInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

String? _optionalString(Object? value) {
  if (value == null) return null;
  final text = value.toString();
  return text.isEmpty ? null : text;
}

const String _v1LiveProbeHex32 =
    '0000000000000000000000000000000000000000000000000000000000000000';

/// Helper class for batch fetch results.
class _BatchResult {
  final List<SaplingBlock> blocks;
  final int startHeight;
  final int endHeight;
  final Map<int, String> blockHashes;
  _BatchResult(this.blocks, this.startHeight, this.endHeight, this.blockHashes);
}

class SaplingRpcException implements Exception {
  final String message;
  final Object? cause;

  SaplingRpcException(this.message, [this.cause]);

  @override
  String toString() => cause == null ? message : '$message: $cause';
}

class SaplingRpcCapabilities {
  static const String v1ContractId = 'pivx.sapling.electrumx.v1';
  static const String legacyBlockRangeContractId = 'legacy.block_range';

  final bool supportsBlockRange;
  final bool supportsGlobalOutputPositions;
  final bool supportsBestAnchor;
  final bool supportsWitness;
  final bool supportsBlockHashes;
  final bool supportsStructuredErrors;
  final String? network;
  final int? activationHeight;
  final int? maxBlockRange;
  final String? contract;
  final String? serverVersion;
  final String? pivxCoreVersion;
  final Set<String> methods;

  static const Set<String> requiredV1Methods = {
    'blockchain.sapling.get_block_range',
    'blockchain.sapling.get_best_anchor',
    'blockchain.sapling.get_witness',
    'blockchain.sapling.get_nullifier_status',
    'blockchain.sapling.get_commitment_info',
  };

  const SaplingRpcCapabilities({
    required this.supportsBlockRange,
    required this.supportsGlobalOutputPositions,
    required this.supportsBestAnchor,
    required this.supportsWitness,
    this.supportsBlockHashes = false,
    this.supportsStructuredErrors = false,
    this.network,
    this.activationHeight,
    this.maxBlockRange,
    this.contract,
    this.serverVersion,
    this.pivxCoreVersion,
    this.methods = const {},
  });

  factory SaplingRpcCapabilities.fromJson(Map<String, dynamic> json) {
    final methodList = <String>{};
    final rawMethods = json['methods'] as List<dynamic>? ??
        json['supported_methods'] as List<dynamic>?;
    if (rawMethods != null) {
      methodList.addAll(rawMethods.map((e) => e.toString()));
    }
    final aliases = json['aliases'];
    if (aliases is Map) {
      methodList.addAll(aliases.keys.map((e) => e.toString()));
      for (final value in aliases.values) {
        if (value is List) {
          methodList.addAll(value.map((e) => e.toString()));
        } else if (value != null) {
          methodList.add(value.toString());
        }
      }
    } else if (aliases is List) {
      methodList.addAll(aliases.map((e) => e.toString()));
    }
    final rawFeatures = json['features'];
    final features = rawFeatures is Map ? rawFeatures : null;
    final rawRangeFormat = json['range_response_format'];
    final rangeFormat = rawRangeFormat is Map ? rawRangeFormat : null;
    final network = _optionalString(json['network']);
    final activationHeight = _optionalInt(json['sapling_activation_height']) ??
        _optionalInt(json['activation_height']);

    bool hasMethod(String name) => methodList.contains(name);

    return SaplingRpcCapabilities(
      supportsBlockRange: hasMethod('blockchain.sapling.get_block_range') ||
          json['supports_block_range'] == true,
      supportsGlobalOutputPositions: json['global_output_positions'] == true ||
          json['supports_global_output_positions'] == true ||
          features?['global_output_positions'] == true ||
          rangeFormat?['global_output_positions'] == true,
      supportsBestAnchor: hasMethod('blockchain.sapling.get_best_anchor') ||
          hasMethod('blockchain.sapling.get_tree_state') ||
          json['supports_best_anchor'] == true,
      supportsWitness: hasMethod('blockchain.sapling.get_witness') ||
          json['supports_witness'] == true,
      supportsBlockHashes: json['block_hashes'] == true ||
          json['supports_block_hashes'] == true ||
          features?['block_hashes'] == true ||
          rangeFormat?['block_hashes'] == true,
      supportsStructuredErrors: json['structured_errors'] == true ||
          json['supports_structured_errors'] == true ||
          features?['structured_errors'] == true,
      network: network,
      activationHeight: activationHeight,
      maxBlockRange: _optionalInt(json['max_block_range']) ??
          _optionalInt(json['max_range_size']),
      contract: _optionalString(json['contract']) ??
          _optionalString(json['contract_id']),
      serverVersion: _optionalString(json['server_version']) ??
          _optionalString(json['electrumx_version']),
      pivxCoreVersion: _optionalString(json['pivx_core_version']) ??
          _optionalString(json['core_version']),
      methods: methodList,
    );
  }

  bool get advertisesV1Contract => contract?.toLowerCase() == v1ContractId;

  bool get supportsV1ReleaseContract =>
      advertisesV1Contract &&
      supportsBlockRange &&
      supportsGlobalOutputPositions &&
      supportsBestAnchor &&
      supportsWitness &&
      supportsBlockHashes &&
      supportsStructuredErrors &&
      methods.containsAll(requiredV1Methods);

  bool get isLegacyBlockRangeOnly => contract == legacyBlockRangeContractId;

  static SaplingRpcCapabilities legacyBlockRangeOnly() =>
      const SaplingRpcCapabilities(
        supportsBlockRange: true,
        supportsGlobalOutputPositions: false,
        supportsBestAnchor: false,
        supportsWitness: false,
        contract: legacyBlockRangeContractId,
      );
}

/// PIVX Sapling activation heights.
class SaplingActivation {
  static const int mainnet = 2700500;
  static const int testnet = 201;
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

/// Parsed result from a Sapling block-range response.
class SaplingBlockRangeResult {
  final int startHeight;
  final int endHeight;
  final List<SaplingBlock> blocks;
  final Map<int, String> blockHashes;

  SaplingBlockRangeResult({
    required this.startHeight,
    required this.endHeight,
    required this.blocks,
    this.blockHashes = const {},
  });
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
    final anchor = json['anchor'] as String? ?? json['root'] as String?;
    final height = _optionalInt(json['anchor_height']) ??
        _optionalInt(json['anchorHeight']) ??
        _optionalInt(json['height']);
    if (anchor == null || anchor.isEmpty) {
      throw SaplingRpcException(
          'PIVX Sapling best-anchor response has no anchor');
    }
    if (height == null) {
      throw SaplingRpcException(
          'PIVX Sapling best-anchor response has no anchor height');
    }

    return BestAnchorResult(
      anchor: anchor,
      height: height,
    );
  }

  /// Get anchor as bytes.
  Uint8List get anchorBytes => Uint8List.fromList(hex.decode(anchor));
}

/// Anchor-bound Merkle witness for spend proof construction.
class SaplingWitnessResult {
  static const String sourceUnknown = 'unknown';
  static const String sourceAnchorBound = 'anchor_bound';
  static const String sourceCommitmentOnlyFallback = 'commitment_only_fallback';
  static const int saplingTreeDepth = 32;
  static const int saplingNodeHexLength = 64;
  static final BigInt _jubjubBaseFieldModulus = BigInt.parse(
      '73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001',
      radix: 16);
  static const List<String> _emptyRoots = [
    '0100000000000000000000000000000000000000000000000000000000000000',
    '817de36ab2d57feb077634bca77819c8e0bd298c04f6fed0e6a83cc1356ca155',
    'ffe9fc03f18b176c998806439ff0bb8ad193afdb27b2ccbc88856916dd804e34',
    'd8283386ef2ef07ebdbb4383c12a739a953a4d6e0d6fb1139a4036d693bfbb6c',
    'e110de65c907b9dea4ae0bd83a4b0a51bea175646a64c12b4c9f931b2cb31b49',
    '912d82b2c2bca231f71efcf61737fbf0a08befa0416215aeef53e8bb6d23390a',
    '8ac9cf9c391e3fd42891d27238a81a8a5c1d3a72b1bcbea8cf44a58ce7389613',
    'd6c639ac24b46bd19341c91b13fdcab31581ddaf7f1411336a271f3d0aa52813',
    '7b99abdc3730991cc9274727d7d82d28cb794edbc7034b4f0053ff7c4b680444',
    '43ff5457f13b926b61df552d4e402ee6dc1463f99a535f9a713439264d5b616b',
    'ba49b659fbd0b7334211ea6a9d9df185c757e70aa81da562fb912b84f49bce72',
    '4777c8776a3b1e69b73a62fa701fa4f7a6282d9aee2c7a6b82e7937d7081c23c',
    'ec677114c27206f5debc1c1ed66f95e2b1885da5b7be3d736b1de98579473048',
    '1b77dac4d24fb7258c3c528704c59430b630718bec486421837021cf75dab651',
    'bd74b25aacb92378a871bf27d225cfc26baca344a1ea35fdd94510f3d157082c',
    'd6acdedf95f608e09fa53fb43dcd0990475726c5131210c9e5caeab97f0e642f',
    '1ea6675f9551eeb9dfaaa9247bc9858270d3d3a4c5afa7177a984d5ed1be2451',
    '6edb16d01907b759977d7650dad7e3ec049af1a3d875380b697c862c9ec5d51c',
    'cd1c8dbf6e3acc7a80439bc4962cf25b9dce7c896f3a5bd70803fc5a0e33cf00',
    '6aca8448d8263e547d5ff2950e2ed3839e998d31cbc6ac9fd57bc6002b159216',
    '8d5fa43e5a10d11605ac7430ba1f5d81fb1b68d29a640405767749e841527673',
    '08eeab0c13abd6069e6310197bf80f9c1ea6de78fd19cbae24d4a520e6cf3023',
    '0769557bc682b1bf308646fd0b22e648e8b9e98f57e29f5af40f6edb833e2c49',
    '4c6937d78f42685f84b43ad3b7b00f81285662f85c6a68ef11d62ad1a3ee0850',
    'fee0e52802cb0c46b1eb4d376c62697f4759f6c8917fa352571202fd778fd712',
    '16d6252968971a83da8521d65382e61f0176646d771c91528e3276ee45383e4a',
    'd2e1642c9a462229289e5b0e3b7f9008e0301cbb93385ee0e21da2545073cb58',
    'a5122c08ff9c161d9ca6fc462073396c7d7d38e8ee48cdb3bea7e2230134ed6a',
    '28e7b841dcbc47cceb69d7cb8d94245fb7cb2ba3a7a6bc18f13f945f7dbd6e2a',
    'e1f34b034d4a3cd28557e2907ebf990c918f64ecb50a94f01d6fda5ca5c7ef72',
    '12935f14b676509b81eb49ef25f39269ed72309238b4c145803544b646dca62d',
    'b2eed031d4d6a4f02a097f80b54cc1541d4163c6b6f5971f88b6e41d35c53814',
    'fbc2f4300c01f0b7820d00e3347c8da4ee614674376cbc45359daa54f9b5493e',
  ];

  final int position;
  final List<String> path;
  final String anchor;
  final int anchorHeight;
  final String commitment;
  final String source;
  final Map<String, dynamic> raw;

  SaplingWitnessResult({
    required this.position,
    required this.path,
    required this.anchor,
    required this.anchorHeight,
    required this.commitment,
    this.source = sourceUnknown,
    required this.raw,
  });

  factory SaplingWitnessResult.fromJson(Map<String, dynamic> json) {
    final rawPath = _normalizeWitnessPath(json['path'] ?? json['witness']);
    final path = _expandWitnessPath(rawPath);
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

    if (rawPath == null || rawPath.isEmpty) {
      throw SaplingRpcException('PIVX Sapling witness response has no path');
    }
    if (path == null) {
      throw SaplingRpcException(
          'PIVX Sapling witness response has invalid path');
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
      path: path,
      anchor: anchor,
      anchorHeight: anchorHeight,
      commitment: commitment,
      source: _optionalString(json['source']) ?? sourceUnknown,
      raw: Map<String, dynamic>.from(json),
    );
  }

  SaplingWitnessResult withSource(String source) => SaplingWitnessResult(
        position: position,
        path: path,
        anchor: anchor,
        anchorHeight: anchorHeight,
        commitment: commitment,
        source: source,
        raw: {
          ...raw,
          'source': source,
        },
      );

  static List<String>? _normalizeWitnessPath(Object? rawPath) {
    if (rawPath == null) return null;
    if (rawPath is String) {
      final normalized = _normalizeWitnessPathElement(rawPath);
      return normalized == null ? null : <String>[normalized];
    }
    if (rawPath is! List) return null;

    final path = <String>[];
    for (final element in rawPath) {
      final normalized = _normalizeWitnessPathElement(element);
      if (normalized == null) return null;
      path.add(normalized);
    }
    return path;
  }

  static String? _normalizeWitnessPathElement(Object? element) {
    if (element == null) return null;
    if (element is String) {
      return element;
    }
    if (element is Map) {
      for (final key in const [
        'hash',
        'hex',
        'node',
        'sibling',
        'value',
        'cmu',
      ]) {
        final value = element[key];
        if (value is String && value.isNotEmpty) {
          return value;
        }
      }
      return null;
    }
    if (element is List) {
      for (final value in element) {
        if (value is String && value.isNotEmpty) {
          return value;
        }
      }
    }
    return null;
  }

  static List<String>? _expandWitnessPath(List<String>? rawPath) {
    if (rawPath == null || rawPath.isEmpty) return rawPath;
    final path = _splitWitnessPath(rawPath);
    if (path == null || path.length > saplingTreeDepth) return null;

    final expanded = _padWitnessPath(path);
    final invalidIndex = _firstNonCanonicalNodeIndex(expanded);
    if (invalidIndex == null) return expanded;

    final reversedPath = path.map(_reverseNodeHex).toList(growable: false);
    final reversedExpanded = _padWitnessPath(reversedPath);
    final reversedInvalidIndex = _firstNonCanonicalNodeIndex(reversedExpanded);
    if (reversedInvalidIndex == null) {
      printV('[PIVX Sapling] Witness path byte order corrected');
      return reversedExpanded;
    }

    final originalCanonical = path
        .where((node) => _littleEndianHexToBigInt(node) < _jubjubBaseFieldModulus)
        .length;
    final reversedCanonical = reversedPath
        .where((node) => _littleEndianHexToBigInt(node) < _jubjubBaseFieldModulus)
        .length;
    printV(
        '[PIVX Sapling] Witness path has non-canonical node at index $invalidIndex; canonical_original=$originalCanonical/${path.length}, canonical_reversed=$reversedCanonical/${reversedPath.length}');
    return null;
  }

  static List<String>? _splitWitnessPath(List<String> rawPath) {
    final path = <String>[];
    for (final element in rawPath) {
      final hexElement = element.trim();
      if (hexElement.isEmpty ||
          hexElement.length % saplingNodeHexLength != 0 ||
          !RegExp(r'^[0-9a-fA-F]+$').hasMatch(hexElement)) {
        return null;
      }
      for (var offset = 0;
          offset < hexElement.length;
          offset += saplingNodeHexLength) {
        path.add(hexElement
            .substring(offset, offset + saplingNodeHexLength)
            .toLowerCase());
      }
    }
    return path;
  }

  static List<String> _padWitnessPath(List<String> path) {
    final expanded = List<String>.from(path);
    if (path.length < saplingTreeDepth) {
      expanded.addAll(_emptyRoots.skip(path.length).take(
            saplingTreeDepth - path.length,
          ));
    }
    return expanded;
  }

  static int? _firstNonCanonicalNodeIndex(List<String> path) {
    for (var i = 0; i < path.length; i++) {
      if (_littleEndianHexToBigInt(path[i]) >= _jubjubBaseFieldModulus) {
        return i;
      }
    }
    return null;
  }

  static BigInt _littleEndianHexToBigInt(String hexValue) {
    final buffer = StringBuffer();
    for (var offset = hexValue.length; offset > 0; offset -= 2) {
      buffer.write(hexValue.substring(offset - 2, offset));
    }
    return BigInt.parse(buffer.toString(), radix: 16);
  }

  static String _reverseNodeHex(String hexValue) {
    final buffer = StringBuffer();
    for (var offset = hexValue.length; offset > 0; offset -= 2) {
      buffer.write(hexValue.substring(offset - 2, offset));
    }
    return buffer.toString();
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
    bool fallbackOnServerError = false,
  }) async {
    Object? lastError;
    for (final method in methods) {
      try {
        int? requestId;
        final result = await _client.call(
          method: method,
          params: params,
          idCallback: (id) => requestId = id,
        );
        final errorMessage = _errorMessageForRequest(requestId);
        if (errorMessage != null) {
          throw SaplingRpcException(errorMessage);
        }
        return result;
      } catch (e) {
        lastError = e;
        if (!_looksLikeUnsupportedMethod(e) &&
            !(fallbackOnServerError && _looksLikeServerMethodFailure(e))) {
          rethrow;
        }
      }
    }
    throw SaplingRpcException('PIVX Sapling RPC method unavailable', lastError);
  }

  String? _errorMessageForRequest(int? requestId) {
    if (requestId == null) return null;
    try {
      final message = _client.getErrorMessage(requestId);
      if (message is String && message.isNotEmpty) {
        return message;
      }
    } catch (_) {}
    return null;
  }

  bool _looksLikeUnsupportedMethod(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('method not found') ||
        text.contains('unknown method') ||
        text.contains('unsupported') ||
        text.contains('not implemented') ||
        text.contains('method unavailable');
  }

  bool _looksLikeServerMethodFailure(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('internal server error') ||
        text.contains('server error');
  }

  /// Probe the Sapling RPC policy/capabilities for the active node.
  Future<SaplingRpcCapabilities> probeCapabilities() async {
    if (_capabilities != null) return _capabilities!;

    try {
      final result = await _callFirstSupported(
        methods: const [
          'blockchain.sapling.capabilities',
          'blockchain.sapling.get_capabilities',
        ],
        params: <Object>[],
        fallbackOnServerError: true,
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
      if (capabilities.advertisesV1Contract &&
          !capabilities.supportsV1ReleaseContract) {
        throw SaplingRpcException(
            'PIVX Sapling node advertises v1 but is missing required release contract features');
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
      if (capabilities.supportsV1ReleaseContract) {
        await _validateLiveV1ReleaseMethods();
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

  Future<void> _validateLiveV1ReleaseMethods() async {
    try {
      final anchorResult = await _callFirstSupported(
        methods: const ['blockchain.sapling.get_best_anchor'],
        params: <Object>[],
      );
      if (anchorResult is! Map) {
        throw SaplingRpcException(
            'get_best_anchor returned ${anchorResult.runtimeType}');
      }
      BestAnchorResult.fromJson(Map<String, dynamic>.from(anchorResult));

      final nullifierResult = await _callFirstSupported(
        methods: const ['blockchain.sapling.get_nullifier_status'],
        params: const <Object>[_v1LiveProbeHex32],
      );
      if (nullifierResult is! Map) {
        throw SaplingRpcException(
            'get_nullifier_status returned ${nullifierResult.runtimeType}');
      }
      NullifierStatus.fromJson(Map<String, dynamic>.from(nullifierResult));

      final commitmentResult = await _callFirstSupported(
        methods: const ['blockchain.sapling.get_commitment_info'],
        params: const <Object>[_v1LiveProbeHex32],
      );
      if (commitmentResult is! Map) {
        throw SaplingRpcException(
            'get_commitment_info returned ${commitmentResult.runtimeType}');
      }
      CommitmentInfo.fromJson(Map<String, dynamic>.from(commitmentResult));
    } catch (e) {
      throw SaplingRpcException(
        'PIVX Sapling node advertises v1 but live release method validation failed',
        e,
      );
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
  }) async =>
      (await getBlockRangeResult(startHeight, endHeight: endHeight)).blocks;

  /// Get blocks plus v1 envelope metadata for a Sapling height range.
  Future<SaplingBlockRangeResult> getBlockRangeResult(
    int startHeight, {
    int? endHeight,
  }) async {
    final expectedEnd = endHeight ?? startHeight;
    final params = <Object>[startHeight];
    if (endHeight != null) params.add(endHeight);

    final result = await _callFirstSupported(
      methods: const ['blockchain.sapling.get_block_range'],
      params: params,
    );

    if (result == null) {
      throw SaplingRpcException(
        'PIVX Sapling get_block_range returned null for $startHeight-$expectedEnd',
      );
    }

    dynamic blocksResult = result;
    var blockHashes = <int, String>{};
    if (result is Map) {
      if (result['complete'] != true) {
        throw SaplingRpcException(
          'PIVX Sapling get_block_range returned an incomplete range for $startHeight-$expectedEnd',
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
      if (responseEnd != null && responseEnd != expectedEnd) {
        throw SaplingRpcException(
          'PIVX Sapling get_block_range returned a mismatched end height',
        );
      }
      blockHashes = _parseBlockHashes(
        result['block_hashes'] ?? result['blockHashes'],
        responseStart ?? startHeight,
      );
      blocksResult = result['blocks'];
    }

    if (blocksResult is! List) {
      throw SaplingRpcException(
        'PIVX Sapling get_block_range returned ${blocksResult.runtimeType} for $startHeight-$expectedEnd',
      );
    }

    final List<SaplingBlock> blocks;
    try {
      blocks = blocksResult
          .map((e) => SaplingBlock.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw SaplingRpcException(
        'PIVX Sapling get_block_range returned malformed block data',
        e,
      );
    }
    for (final block in blocks) {
      if (block.hash.isNotEmpty) {
        blockHashes[block.height] = block.hash;
      }
    }

    return SaplingBlockRangeResult(
      startHeight: startHeight,
      endHeight: expectedEnd,
      blocks: blocks,
      blockHashes: blockHashes,
    );
  }

  Map<int, String> _parseBlockHashes(Object? raw, int startHeight) {
    final hashes = <int, String>{};
    if (raw is Map) {
      for (final entry in raw.entries) {
        final height = entry.key is int
            ? entry.key as int
            : int.tryParse(entry.key.toString());
        final hash = entry.value?.toString();
        if (height != null && hash != null && hash.isNotEmpty) {
          hashes[height] = hash;
        }
      }
    } else if (raw is List) {
      for (var i = 0; i < raw.length; i++) {
        final item = raw[i];
        if (item is Map) {
          final height = _optionalInt(item['height']) ??
              _optionalInt(item['block_height']);
          final hash = _optionalString(item['hash']) ??
              _optionalString(item['block_hash']);
          if (height != null && hash != null) {
            hashes[height] = hash;
          }
        } else if (item != null) {
          final hash = item.toString();
          if (hash.isNotEmpty) {
            hashes[startHeight + i] = hash;
          }
        }
      }
    }
    return hashes;
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
  /// The v1 release contract uses commitment + anchor root. Some simulator and
  /// development nodes have exposed compatible witness data behind position or
  /// height-bound parameter shapes, so callers that need compatibility should
  /// use [getAnchorBoundWitness] instead of calling this low-level method.
  Future<Map<String, dynamic>?> getWitness(
      Object commitmentOrPosition, Object? anchorOrHeight) async {
    final params = <Object>[commitmentOrPosition];
    if (anchorOrHeight != null) {
      params.add(anchorOrHeight);
    }
    final result = await _callFirstSupported(
        methods: const ['blockchain.sapling.get_witness'], params: params);
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
    int? notePosition,
  }) async {
    final attempts = <Map<String, Object>>[
      {
        'label': 'commitment_anchor',
        'params': <Object?>[commitment, anchor.anchor],
        'retries': 1,
      },
      {
        'label': 'commitment_only',
        'params': <Object?>[commitment, null],
        'retries': 2,
      },
    ];

    final failures = <String>[];
    for (final attempt in attempts) {
      final params = attempt['params'] as List<Object?>;
      final label = attempt['label'] as String;
      final retries = attempt['retries'] as int;
      for (var retry = 1; retry <= retries; retry++) {
        try {
          final witnessData = await getWitness(params[0]!, params[1]);
          if (witnessData == null) {
            throw SaplingRpcException('PIVX Sapling witness response is null');
          }

          final witness = SaplingWitnessResult.fromJson(
              Map<String, dynamic>.from(witnessData));
          if (label == 'commitment_only') {
            _validateWitnessCommitment(
              witness: witness,
              commitment: commitment,
            );
          } else {
            _validateAnchorBoundWitness(
              witness: witness,
              commitment: commitment,
              anchor: anchor,
            );
          }
          final source = label == 'commitment_only'
              ? SaplingWitnessResult.sourceCommitmentOnlyFallback
              : SaplingWitnessResult.sourceAnchorBound;
          printV('[PIVX Sapling] Witness accepted via $source');
          return witness.withSource(source);
        } catch (e) {
          final reason = _witnessFailureReason(e);
          failures.add('$label:$reason');
          printV(
              '[PIVX Sapling] Witness attempt $label $retry/$retries failed: $reason');
        }
      }
    }

    throw SaplingRpcException(
      'PIVX Sapling witness lookup failed for selected note position; attempts=${failures.join(',')}',
    );
  }

  static String _witnessFailureReason(Object error) {
    final text = error.toString().toLowerCase();

    if (text.contains('canonical_witness_unavailable') ||
        text.contains('witness not found') ||
        text.contains('commitment not found')) {
      return 'canonical_witness_unavailable';
    }
    if (text.contains('response is null')) {
      return 'null_response';
    }
    if (text.contains('no path')) {
      return 'missing_path';
    }
    if (text.contains('invalid path') ||
        text.contains('non-canonical node')) {
      return 'invalid_path';
    }
    if (text.contains('no anchor')) {
      return 'missing_anchor';
    }
    if (text.contains('anchor does not match')) {
      return 'anchor_mismatch';
    }
    if (text.contains('height does not match')) {
      return 'anchor_height_mismatch';
    }
    if (text.contains('no commitment')) {
      return 'missing_commitment';
    }
    if (text.contains('commitment does not match')) {
      return 'commitment_mismatch';
    }
    if (text.contains('no note position')) {
      return 'missing_position';
    }
    if (text.contains('rpc method unavailable') ||
        text.contains('unknown method') ||
        text.contains('method not found')) {
      return 'witness_method_unavailable';
    }
    if (text.contains('internal server error') ||
        text.contains('server error')) {
      return 'server_error';
    }

    return 'witness_lookup_failed';
  }

  void _validateAnchorBoundWitness({
    required SaplingWitnessResult witness,
    required String commitment,
    required BestAnchorResult anchor,
  }) {
    if (witness.anchor.toLowerCase() != anchor.anchor.toLowerCase()) {
      throw SaplingRpcException(
          'PIVX Sapling witness anchor does not match selected anchor');
    }
    if (witness.anchorHeight != anchor.height) {
      throw SaplingRpcException(
          'PIVX Sapling witness height does not match selected anchor height');
    }
    _validateWitnessCommitment(witness: witness, commitment: commitment);
  }

  void _validateWitnessCommitment({
    required SaplingWitnessResult witness,
    required String commitment,
  }) {
    if (witness.commitment.toLowerCase() != commitment.toLowerCase()) {
      throw SaplingRpcException(
          'PIVX Sapling witness commitment does not match requested note');
    }
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
    Future<void> Function(
      int rangeStart,
      int rangeEnd,
      Map<int, String> blockHashes,
    )? onRangeComplete,
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
        await onRangeComplete?.call(
          result.startHeight,
          result.endHeight,
          result.blockHashes,
        );
      }

      currentStart += parallelBatches * effectiveBatchSize;
    }
  }

  /// Fetch a batch with retry logic.
  Future<_BatchResult> _fetchBatchWithRetry(int start, int end,
      {int retries = 2}) async {
    for (int attempt = 0; attempt <= retries; attempt++) {
      try {
        final result = await getBlockRangeResult(start, endHeight: end);
        return _BatchResult(result.blocks, start, end, result.blockHashes);
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
