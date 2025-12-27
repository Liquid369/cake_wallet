import '../pivx_sapling_electrumx.dart';

/// Processes batches of blocks in order, even if they arrive out of sequence.
/// 
/// During parallel sync, network batches can arrive in any order due to
/// variable response times. However, block processing must be sequential
/// to maintain correct tree position assignment.
/// 
/// This class buffers out-of-order batches and processes them only when
/// all preceding batches have been received.
/// 
/// Example timeline:
/// ```
/// Time 0: Batch 1 (100-199), Batch 2 (200-299), Batch 3 (300-399) requested
/// Time 1: Batch 3 arrives → buffered (waiting for Batch 1 & 2)
/// Time 2: Batch 1 arrives → processed immediately
/// Time 3: Batch 2 arrives → processed, then Batch 3 processed from buffer
/// ```
class OrderedBatchProcessor {
  /// Buffer for batches that arrived out of order.
  /// Key: Starting height of the batch
  /// Value: List of blocks in that batch
  final Map<int, List<SaplingBlock>> _pendingBatches = {};
  
  /// The next expected starting height to process.
  int _nextExpectedHeight;
  
  /// Size of each batch (number of blocks).
  final int _batchSize;
  
  /// Create a processor starting at [startHeight].
  /// [batchSize] must match the batch size used for fetching.
  OrderedBatchProcessor({
    required int startHeight,
    required int batchSize,
  })  : _nextExpectedHeight = startHeight,
        _batchSize = batchSize;
  
  /// Add a fetched batch to the buffer.
  /// 
  /// Can be called in any order - batches will be processed sequentially.
  /// This method is fast and non-blocking.
  /// 
  /// [startHeight] The height of the first block in this batch.
  /// [blocks] The blocks in this batch.
  void addBatch(int startHeight, List<SaplingBlock> blocks) {
    _pendingBatches[startHeight] = blocks;
  }
  
  /// Process all sequential batches that are ready.
  /// 
  /// This processes batches starting from [_nextExpectedHeight] and continues
  /// as long as the next sequential batch is available in the buffer.
  /// 
  /// Stops when it encounters a gap (missing batch).
  /// 
  /// [onBlock] Callback invoked for each block in sequential order.
  Future<void> processAvailableBatches({
    required Future<void> Function(SaplingBlock block) onBlock,
  }) async {
    while (_pendingBatches.containsKey(_nextExpectedHeight)) {
      final blocks = _pendingBatches.remove(_nextExpectedHeight)!;
      
      // Process all blocks in this batch sequentially
      for (final block in blocks) {
        await onBlock(block);
      }
      
      // Move to next expected batch
      if (blocks.isNotEmpty) {
        // Calculate next height based on actual blocks processed
        _nextExpectedHeight = blocks.last.height + 1;
      } else {
        // Empty batch (e.g., error fetching) - assume standard batch size
        _nextExpectedHeight += _batchSize;
      }
    }
  }
  
  /// Drain all remaining buffered batches.
  /// 
  /// Processes ALL batches in the buffer, regardless of order.
  /// This should only be called at the end of sync when all batches
  /// have been fetched and we need to process any stragglers.
  /// 
  /// Warning: This may process batches out of order if there are gaps!
  /// Only use when you're certain all batches have been added.
  Future<void> drainRemaining({
    required Future<void> Function(SaplingBlock block) onBlock,
  }) async {
    // Sort heights to process in order
    final heights = _pendingBatches.keys.toList()..sort();
    
    for (final height in heights) {
      final blocks = _pendingBatches.remove(height)!;
      
      for (final block in blocks) {
        await onBlock(block);
      }
    }
    
    _pendingBatches.clear();
  }
  
  /// Check if there are any buffered batches waiting to be processed.
  bool get hasPendingBatches => _pendingBatches.isNotEmpty;
  
  /// Get the number of batches waiting in the buffer.
  int get pendingBatchCount => _pendingBatches.length;
  
  /// Get the next expected height.
  int get nextExpectedHeight => _nextExpectedHeight;
}
