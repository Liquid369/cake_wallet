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
/// - Testnet: 201

import 'dart:typed_data';
import 'package:convert/convert.dart';

/// Helper class for batch fetch results.
class _BatchResult {
  final List<SaplingBlock> blocks;
  final int endHeight;
  _BatchResult(this.blocks, this.endHeight);
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
  
  SaplingShieldedOutput({
    required this.cmu,
    required this.epk,
    required this.ciphertext,
    required this.cv,
    required this.outCiphertext,
  });
  
  factory SaplingShieldedOutput.fromJson(Map<String, dynamic> json) {
    return SaplingShieldedOutput(
      cmu: json['cmu'] as String,
      epk: json['epk'] as String,
      ciphertext: json['ciphertext'] as String,
      cv: json['cv'] as String,
      outCiphertext: json['out_ciphertext'] as String,
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
  Uint8List get outCiphertextBytes => Uint8List.fromList(hex.decode(outCiphertext));
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
        ?.map((e) => SaplingShieldedOutput.fromJson(e as Map<String, dynamic>))
        .toList() ?? [];
    
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
          ?.map((e) => SaplingShieldedOutput.fromJson(e as Map<String, dynamic>))
          .toList() ?? [],
      spends: (json['spends'] as List<dynamic>?)
          ?.map((e) => SaplingSpend.fromJson(e as Map<String, dynamic>))
          .toList() ?? [],
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
          ?.map((e) => SaplingTransaction.fromJson(e as Map<String, dynamic>))
          .toList() ?? [],
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
  
  /// Get the Sapling activation height for this network.
  int get activationHeight => 
      isTestnet ? SaplingActivation.testnet : SaplingActivation.mainnet;
  
  /// Check if a nullifier has been spent.
  /// 
  /// [nullifier] - 32-byte nullifier as hex string.
  Future<NullifierStatus> getNullifierStatus(String nullifier) async {
    final result = await _client.call(
      method: 'blockchain.nullifier.get_spend',
      params: <Object>[nullifier],
    );
    return NullifierStatus.fromJson(result as Map<String, dynamic>);
  }
  
  /// Get information about a note commitment.
  /// 
  /// [commitment] - 32-byte cmu as hex string.
  Future<CommitmentInfo> getCommitmentInfo(String commitment) async {
    final result = await _client.call(
      method: 'blockchain.commitment.get_info',
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
    
    final result = await _client.call(
      method: 'blockchain.sapling.get_outputs',
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
    
    try {
      final result = await _client.call(
        method: 'blockchain.sapling.get_block_range',
        params: params,
      );
      
      // Handle null response (method not supported or no blocks found)
      if (result == null) {
        return [];
      }
      
      // Handle empty list (no Sapling txs in range)
      if (result is List && result.isEmpty) {
        return [];
      }
      
      final blocks = (result as List<dynamic>)
          .map((e) => SaplingBlock.fromJson(e as Map<String, dynamic>))
          .toList();
      
      return blocks;
    } catch (e) {
      // Silently return empty on error - sync will retry
      return [];
    }
  }
  
  /// Get the block height where an anchor was valid.
  /// 
  /// [anchor] - 32-byte Merkle root as hex string.
  /// Returns null if anchor not found.
  Future<int?> getAnchorHeight(String anchor) async {
    final result = await _client.call(
      method: 'blockchain.anchor.get_height',
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
      throw Exception('Could not find any tree state from height $maxHeight down to $activationHeight');
    }
    
    final anchor = treeState['root'] as String? ?? treeState['anchor'] as String?;
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
  Future<List<String>> getNullifiersInRange(int startHeight, int endHeight) async {
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
    final result = await _client.call(
      method: 'blockchain.sapling.get_tree_state',
      params: <Object>[height],
    );
    return result as Map<String, dynamic>?;
  }
  
  /// Get Merkle witness for spend proof construction.
  /// 
  /// [commitment] - 32-byte commitment (cmu) as hex.
  /// [anchorHeight] - Block height of anchor.
  Future<Map<String, dynamic>?> getWitness(String commitment, int anchorHeight) async {
    final result = await _client.call(
      method: 'blockchain.sapling.get_witness',
      params: <Object>[commitment, anchorHeight],
    );
    return result as Map<String, dynamic>?;
  }
  
  /// Get Sapling data for a specific transaction.
  /// 
  /// [txid] - Transaction ID as hex.
  Future<Map<String, dynamic>?> getTransactionSapling(String txid) async {
    final result = await _client.call(
      method: 'blockchain.transaction.get_sapling',
      params: <Object>[txid],
    );
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
    void Function(int rangeEnd)? onRangeComplete,
  }) async {
    // Server enforces max 100 blocks per request
    final effectiveBatchSize = batchSize.clamp(1, 100);
    
    int currentStart = fromHeight;
    
    while (currentStart <= toHeight) {
      // Create parallel batch requests
      final batchFutures = <Future<_BatchResult>>[];
      
      for (int i = 0; i < parallelBatches && currentStart + i * effectiveBatchSize <= toHeight; i++) {
        final start = currentStart + i * effectiveBatchSize;
        final end = (start + effectiveBatchSize - 1).clamp(fromHeight, toHeight);
        
        batchFutures.add(_fetchBatchWithRetry(start, end));
      }
      
      // Wait for all parallel batches
      final results = await Future.wait(batchFutures);
      
      // Process results in order
      for (final result in results) {
        if (result.blocks.isNotEmpty) {
          await onBatch(result.blocks);
        }
        onRangeComplete?.call(result.endHeight);
      }
      
      currentStart += parallelBatches * effectiveBatchSize;
    }
  }
  
  /// Fetch a batch with retry logic.
  Future<_BatchResult> _fetchBatchWithRetry(int start, int end, {int retries = 2}) async {
    for (int attempt = 0; attempt <= retries; attempt++) {
      try {
        final blocks = await getBlockRange(start, endHeight: end);
        return _BatchResult(blocks, end);
      } catch (e) {
        if (attempt == retries) {
          return _BatchResult([], end);
        }
        await Future.delayed(Duration(milliseconds: 100 * (attempt + 1)));
      }
    }
    return _BatchResult([], end);
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
