import 'package:synchronized/synchronized.dart';

/// Thread-safe tree position tracker for Sapling commitment tree.
///
/// Ensures that tree positions are assigned atomically and sequentially,
/// preventing race conditions when multiple batches are synced in parallel.
///
/// Tree positions must be globally sequential for Merkle tree correctness:
/// - Each Sapling output receives a unique position
/// - Positions increment sequentially from the genesis block
/// - Concurrent sync batches must not create duplicate or skipped positions
class AtomicTreePosition {
  int _position = 0;
  final Lock _lock = Lock();

  /// Reserve a block of positions atomically.
  ///
  /// This method is thread-safe and ensures that:
  /// 1. Multiple concurrent calls never receive overlapping position ranges
  /// 2. The global position counter is incremented atomically
  /// 3. The starting position of the reserved block is returned
  ///
  /// Example:
  /// ```dart
  /// final pos = AtomicTreePosition();
  /// // Batch 1 reserves 10 positions
  /// final start1 = await pos.reservePositions(10);  // Returns 0
  /// // Batch 2 reserves 5 positions (concurrent with Batch 1)
  /// final start2 = await pos.reservePositions(5);   // Returns 10 (no overlap)
  /// ```
  ///
  /// [count] The number of consecutive positions to reserve.
  /// Returns the starting position of the reserved block.
  Future<int> reservePositions(int count) async {
    return await _lock.synchronized(() {
      final start = _position;
      _position += count;
      return start;
    });
  }

  /// Move the next position forward without allowing it to go backwards.
  Future<void> setAtLeast(int position) async {
    await _lock.synchronized(() {
      if (position > _position) {
        _position = position;
      }
    });
  }

  /// Get the current position (read-only).
  ///
  /// Note: This is the NEXT position that will be assigned.
  /// The last assigned position is `current - 1`.
  int get current => _position;

  /// Initialize the position counter.
  ///
  /// This should only be called during wallet initialization to restore
  /// the tree position from persistent storage. Do not call during sync.
  ///
  /// [position] The position to initialize to (typically the last known position + 1).
  void initialize(int position) {
    _position = position;
  }

  /// Reset to position 0.
  /// Only used for testing or full wallet resets.
  void reset() {
    _position = 0;
  }
}
