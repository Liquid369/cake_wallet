import 'package:flutter_test/flutter_test.dart';
import 'package:cw_pivx/src/sapling/utils/ordered_batch_processor.dart';
import 'package:cw_pivx/src/sapling/pivx_sapling_electrumx.dart';

void main() {
  group('OrderedBatchProcessor', () {
    // Helper to create mock blocks
    List<SaplingBlock> createMockBlocks(int startHeight, int count) {
      return List.generate(count, (i) {
        final height = startHeight + i;
        return SaplingBlock(
          height: height,
          hash: 'hash_$height',
          time: 1000000 + height,
          txs: [],
        );
      });
    }

    test('processes blocks in order when added sequentially', () async {
      final processor = OrderedBatchProcessor(
        startHeight: 100,
        batchSize: 10,
      );
      
      final processedHeights = <int>[];
      
      // Add batches in order
      processor.addBatch(100, createMockBlocks(100, 10));
      processor.addBatch(110, createMockBlocks(110, 10));
      processor.addBatch(120, createMockBlocks(120, 10));
      
      // Process all
      await processor.processAvailableBatches(
        onBlock: (block) async {
          processedHeights.add(block.height);
        },
      );
      
      expect(processedHeights, equals([
        100, 101, 102, 103, 104, 105, 106, 107, 108, 109,
        110, 111, 112, 113, 114, 115, 116, 117, 118, 119,
        120, 121, 122, 123, 124, 125, 126, 127, 128, 129,
      ]));
    });

    test('buffers out-of-order batches and processes when ready', () async {
      final processor = OrderedBatchProcessor(
        startHeight: 100,
        batchSize: 10,
      );
      
      final processedHeights = <int>[];
      
      // Add batch 3 first (out of order)
      processor.addBatch(120, createMockBlocks(120, 10));
      
      await processor.processAvailableBatches(
        onBlock: (block) async {
          processedHeights.add(block.height);
        },
      );
      
      // Nothing processed yet (waiting for 100)
      expect(processedHeights, isEmpty);
      expect(processor.hasPendingBatches, true);
      expect(processor.pendingBatchCount, equals(1));
      
      // Add batch 2 (still out of order)
      processor.addBatch(110, createMockBlocks(110, 10));
      
      await processor.processAvailableBatches(
        onBlock: (block) async {
          processedHeights.add(block.height);
        },
      );
      
      // Still nothing processed
      expect(processedHeights, isEmpty);
      expect(processor.pendingBatchCount, equals(2));
      
      // Add batch 1 (the missing one!)
      processor.addBatch(100, createMockBlocks(100, 10));
      
      await processor.processAvailableBatches(
        onBlock: (block) async {
          processedHeights.add(block.height);
        },
      );
      
      // Now all 30 blocks should be processed in order
      expect(processedHeights.length, equals(30));
      expect(processedHeights.first, equals(100));
      expect(processedHeights.last, equals(129));
      
      // Verify sequential
      for (int i = 1; i < processedHeights.length; i++) {
        expect(processedHeights[i], equals(processedHeights[i-1] + 1));
      }
      
      expect(processor.hasPendingBatches, false);
    });

    test('processes batches as they become sequential', () async {
      final processor = OrderedBatchProcessor(
        startHeight: 100,
        batchSize: 10,
      );
      
      final processedHeights = <int>[];
      
      // Add and process batch 1
      processor.addBatch(100, createMockBlocks(100, 10));
      await processor.processAvailableBatches(
        onBlock: (block) async {
          processedHeights.add(block.height);
        },
      );
      
      expect(processedHeights.length, equals(10));
      expect(processor.nextExpectedHeight, equals(110));
      
      // Add batch 3 (gap)
      processor.addBatch(120, createMockBlocks(120, 10));
      await processor.processAvailableBatches(
        onBlock: (block) async {
          processedHeights.add(block.height);
        },
      );
      
      // Still only 10 processed (batch 3 is buffered)
      expect(processedHeights.length, equals(10));
      
      // Add batch 2 (fills gap)
      processor.addBatch(110, createMockBlocks(110, 10));
      await processor.processAvailableBatches(
        onBlock: (block) async {
          processedHeights.add(block.height);
        },
      );
      
      // Now batches 2 and 3 should be processed
      expect(processedHeights.length, equals(30));
    });

    test('drainRemaining processes all buffered batches in order', () async {
      final processor = OrderedBatchProcessor(
        startHeight: 100,
        batchSize: 10,
      );
      
      final processedHeights = <int>[];
      
      // Add batches completely out of order
      processor.addBatch(140, createMockBlocks(140, 10));
      processor.addBatch(100, createMockBlocks(100, 10));
      processor.addBatch(130, createMockBlocks(130, 10));
      processor.addBatch(110, createMockBlocks(110, 10));
      processor.addBatch(120, createMockBlocks(120, 10));
      
      // Process what we can (only 100 will process)
      await processor.processAvailableBatches(
        onBlock: (block) async {
          processedHeights.add(block.height);
        },
      );
      
      // Drain the rest
      await processor.drainRemaining(
        onBlock: (block) async {
          processedHeights.add(block.height);
        },
      );
      
      expect(processedHeights.length, equals(50));
      expect(processor.hasPendingBatches, false);
      
      // Verify all in order
      for (int i = 1; i < processedHeights.length; i++) {
        expect(processedHeights[i], equals(processedHeights[i-1] + 1));
      }
    });

    test('handles empty batches', () async {
      final processor = OrderedBatchProcessor(
        startHeight: 100,
        batchSize: 10,
      );
      
      final processedHeights = <int>[];
      
      // Add empty batch
      processor.addBatch(100, []);
      
      await processor.processAvailableBatches(
        onBlock: (block) async {
          processedHeights.add(block.height);
        },
      );
      
      // No blocks processed, but position should advance
      expect(processedHeights, isEmpty);
      expect(processor.nextExpectedHeight, equals(110)); // Advances by batchSize
    });

    test('realistic sync scenario with network delays', () async {
      final processor = OrderedBatchProcessor(
        startHeight: 2700000,
        batchSize: 100,
      );
      
      final processedHeights = <int>[];
      
      // Simulate 5 parallel requests arriving in random order
      // Batch 3 arrives first (fastest server)
      processor.addBatch(2700200, createMockBlocks(2700200, 100));
      await processor.processAvailableBatches(
        onBlock: (block) async {
          processedHeights.add(block.height);
        },
      );
      expect(processedHeights, isEmpty); // Buffered
      
      // Batch 1 arrives second
      processor.addBatch(2700000, createMockBlocks(2700000, 100));
      await processor.processAvailableBatches(
        onBlock: (block) async {
          processedHeights.add(block.height);
        },
      );
      expect(processedHeights.length, equals(100)); // Batch 1 processed
      
      // Batch 5 arrives third
      processor.addBatch(2700400, createMockBlocks(2700400, 100));
      await processor.processAvailableBatches(
        onBlock: (block) async {
          processedHeights.add(block.height);
        },
      );
      expect(processedHeights.length, equals(100)); // Still waiting for batch 2
      
      // Batch 2 arrives fourth
      processor.addBatch(2700100, createMockBlocks(2700100, 100));
      await processor.processAvailableBatches(
        onBlock: (block) async {
          processedHeights.add(block.height);
        },
      );
      expect(processedHeights.length, equals(300)); // Batches 2 and 3 processed
      
      // Batch 4 arrives last
      processor.addBatch(2700300, createMockBlocks(2700300, 100));
      await processor.processAvailableBatches(
        onBlock: (block) async {
          processedHeights.add(block.height);
        },
      );
      expect(processedHeights.length, equals(500)); // All processed
      
      // Verify perfect sequential order
      expect(processedHeights.first, equals(2700000));
      expect(processedHeights.last, equals(2700499));
      for (int i = 1; i < processedHeights.length; i++) {
        expect(processedHeights[i], equals(processedHeights[i-1] + 1));
      }
    });

    test('maintains state across multiple process calls', () async {
      final processor = OrderedBatchProcessor(
        startHeight: 100,
        batchSize: 10,
      );
      
      final processedHeights = <int>[];
      
      // Add batch 1
      processor.addBatch(100, createMockBlocks(100, 10));
      await processor.processAvailableBatches(
        onBlock: (block) async {
          processedHeights.add(block.height);
        },
      );
      expect(processedHeights.length, equals(10));
      
      // Add batch 3 (gap)
      processor.addBatch(120, createMockBlocks(120, 10));
      await processor.processAvailableBatches(
        onBlock: (block) async {
          processedHeights.add(block.height);
        },
      );
      expect(processedHeights.length, equals(10)); // No change
      
      // Add batch 2 multiple times (should fill gap)
      processor.addBatch(110, createMockBlocks(110, 10));
      await processor.processAvailableBatches(
        onBlock: (block) async {
          processedHeights.add(block.height);
        },
      );
      
      expect(processedHeights.length, equals(30));
      expect(processor.nextExpectedHeight, equals(130));
    });

    test('handles variable batch sizes', () async {
      final processor = OrderedBatchProcessor(
        startHeight: 100,
        batchSize: 50,
      );
      
      final processedHeights = <int>[];
      
      // Add batches with different actual sizes
      processor.addBatch(100, createMockBlocks(100, 30)); // Partial batch
      await processor.processAvailableBatches(
        onBlock: (block) async {
          processedHeights.add(block.height);
        },
      );
      
      expect(processedHeights.length, equals(30));
      // Next expected should be based on actual block range
      expect(processor.nextExpectedHeight, equals(130));
    });
  });
}
