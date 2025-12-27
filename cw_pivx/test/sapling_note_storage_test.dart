import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:cw_pivx/src/sapling/sapling_note_storage.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

// Mock path provider for testing
class MockPathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() async {
    return Directory.systemTemp.path;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  
  setUpAll(() {
    PathProviderPlatform.instance = MockPathProviderPlatform();
  });

  group('SaplingNoteStorage Thread Safety', () {
    late SaplingNoteStorage storage;
    
    setUp(() async {
      storage = SaplingNoteStorage(
        walletId: 'test_wallet_${DateTime.now().millisecondsSinceEpoch}',
        isTestnet: true,
      );
      await storage.load();
    });
    
    tearDown(() async {
      // Clean up test files - storage will clean up on its own
      // We don't need to manually delete as temp files will be cleared
    });

    test('concurrent addNote operations do not lose notes', () async {
      // Add 100 notes concurrently
      final futures = List.generate(100, (i) {
        final note = StoredSaplingNote(
          id: 'tx$i:0',
          value: 1000 + i,
          height: 1000 + i,
          txid: 'txid_$i',
          outputIndex: 0,
          treePosition: i,
          cmu: 'cmu_$i',
        );
        return storage.addNote(note);
      });
      
      await Future.wait(futures);
      
      // Verify all notes were saved
      expect(storage.notes.length, equals(100));
      
      // Verify all values are present
      final values = storage.notes.map((n) => n.value).toSet();
      expect(values.length, equals(100));
      for (int i = 0; i < 100; i++) {
        expect(values.contains(1000 + i), true);
      }
    });

    test('concurrent markSpentByNullifier operations are thread-safe', () async {
      // Add notes first
      for (int i = 0; i < 50; i++) {
        await storage.addNote(StoredSaplingNote(
          id: 'tx$i:0',
          value: 1000,
          height: 1000 + i,
          txid: 'txid_$i',
          outputIndex: 0,
          treePosition: i,
          cmu: 'cmu_$i',
          nullifier: 'nf_$i',
        ));
      }
      
      // Mark them all spent concurrently
      final futures = List.generate(50, (i) {
        return storage.markSpentByNullifier('nf_$i', 'spending_tx_$i');
      });
      
      await Future.wait(futures);
      
      // Verify all marked as spent
      final spentCount = storage.notes.where((n) => n.isSpent).length;
      expect(spentCount, equals(50));
    });

    test('concurrent balance calculations are consistent', () async {
      // Add notes
      for (int i = 0; i < 20; i++) {
        await storage.addNote(StoredSaplingNote(
          id: 'tx$i:0',
          value: 1000,
          height: 1000 + i,
          txid: 'txid_$i',
          outputIndex: 0,
          treePosition: i,
          cmu: 'cmu_$i',
        ));
      }
      
      // Read balance concurrently using thread-safe method
      final futures = List.generate(100, (_) async {
        return await storage.getBalanceSafe();
      });
      
      final balances = await Future.wait(futures);
      
      // All balances should be the same
      expect(balances.toSet().length, equals(1));
      expect(balances.first, equals(20000));
    });

    test('concurrent addNote with duplicate IDs updates existing', () async {
      // Add same note ID multiple times concurrently
      final futures = List.generate(50, (i) {
        final note = StoredSaplingNote(
          id: 'same_tx:0',
          value: 1000 + i, // Different values
          height: 1000,
          txid: 'same_tx',
          outputIndex: 0,
          treePosition: 0,
          cmu: 'cmu',
        );
        return storage.addNote(note);
      });
      
      await Future.wait(futures);
      
      // Should only have 1 note (duplicates updated)
      expect(storage.notes.length, equals(1));
      expect(storage.notes.first.id, equals('same_tx:0'));
      // Value will be from one of the concurrent updates
      expect(storage.notes.first.value, greaterThanOrEqualTo(1000));
      expect(storage.notes.first.value, lessThan(1050));
    });

    test('concurrent setLastSyncedHeight operations maintain consistency', () async {
      // Update height concurrently
      final futures = List.generate(100, (i) {
        return storage.setLastSyncedHeight(2700000 + i);
      });
      
      await Future.wait(futures);
      
      // Last synced height should be one of the values we set
      expect(storage.lastSyncedHeight, greaterThanOrEqualTo(2700000));
      expect(storage.lastSyncedHeight, lessThan(2700100));
    });

    test('mixed concurrent operations (add, mark spent, read)', () async {
      // Add initial notes
      for (int i = 0; i < 20; i++) {
        await storage.addNote(StoredSaplingNote(
          id: 'tx$i:0',
          value: 1000,
          height: 1000 + i,
          txid: 'txid_$i',
          outputIndex: 0,
          treePosition: i,
          cmu: 'cmu_$i',
          nullifier: 'nf_$i',
        ));
      }
      
      final futures = <Future>[];
      
      // Add more notes concurrently
      for (int i = 20; i < 40; i++) {
        futures.add(storage.addNote(StoredSaplingNote(
          id: 'tx$i:0',
          value: 1000,
          height: 1000 + i,
          txid: 'txid_$i',
          outputIndex: 0,
          treePosition: i,
          cmu: 'cmu_$i',
          nullifier: 'nf_$i',
        )));
      }
      
      // Mark some spent concurrently
      for (int i = 0; i < 10; i++) {
        futures.add(storage.markSpentByNullifier('nf_$i', 'spending_tx'));
      }
      
      // Read balance concurrently
      for (int i = 0; i < 20; i++) {
        futures.add(storage.getBalanceSafe());
      }
      
      await Future.wait(futures);
      
      // Verify final state
      expect(storage.notes.length, equals(40));
      final spentCount = storage.notes.where((n) => n.isSpent).length;
      expect(spentCount, equals(10));
      
      // Balance should be 30 unspent notes * 1000
      final finalBalance = await storage.getBalanceSafe();
      expect(finalBalance, equals(30000));
    });

    test('persistence survives concurrent writes', () async {
      final storage1 = SaplingNoteStorage(
        walletId: 'persist_test',
        isTestnet: true,
      );
      await storage1.load();
      
      // Add notes concurrently
      final futures = List.generate(50, (i) {
        final note = StoredSaplingNote(
          id: 'tx$i:0',
          value: 1000,
          height: 1000 + i,
          txid: 'txid_$i',
          outputIndex: 0,
          treePosition: i,
          cmu: 'cmu_$i',
        );
        return storage1.addNote(note);
      });
      
      await Future.wait(futures);
      
      // Load in new instance
      final storage2 = SaplingNoteStorage(
        walletId: 'persist_test',
        isTestnet: true,
      );
      await storage2.load();
      
      // Verify all notes persisted
      expect(storage2.notes.length, equals(50));
      final balance = await storage2.getBalanceSafe();
      expect(balance, equals(50000));
      
      // Cleanup happens automatically with temp directory
    });

    test('stress test with very high concurrency', () async {
      // 1000 concurrent operations
      final futures = <Future>[];
      
      for (int i = 0; i < 1000; i++) {
        if (i % 2 == 0) {
          // Add note
          futures.add(storage.addNote(StoredSaplingNote(
            id: 'tx$i:0',
            value: i,
            height: 1000 + i,
            txid: 'txid_$i',
            outputIndex: 0,
            treePosition: i,
            cmu: 'cmu_$i',
            nullifier: i % 4 == 0 ? 'nf_$i' : null,
          )));
        } else {
          // Read balance using thread-safe method
          futures.add(storage.getBalanceSafe());
        }
      }
      
      await Future.wait(futures);
      
      // Should have 500 notes (half were adds)
      expect(storage.notes.length, equals(500));
      
      // Verify no corruption
      final ids = storage.notes.map((n) => n.id).toSet();
      expect(ids.length, equals(500)); // All unique
    });
  });
}
