import 'package:cw_pivx/src/sapling/pivx_sapling_electrumx.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeElectrumClient {
  FakeElectrumClient(this.responses);

  final List<dynamic> responses;
  int calls = 0;

  Future<dynamic> call({
    required String method,
    List<Object> params = const [],
  }) async {
    calls++;
    final response = responses.removeAt(0);
    if (response is Exception) {
      throw response;
    }
    return response;
  }
}

void main() {
  group('PIVXSaplingElectrumX getBlockRange', () {
    test('accepts complete empty v1 envelopes', () async {
      final client = FakeElectrumClient([
        {
          'from_height': 2700500,
          'to_height': 2700599,
          'complete': true,
          'blocks': <Map<String, dynamic>>[],
        }
      ]);
      final sapling = PIVXSaplingElectrumX(electrumClient: client);

      final blocks = await sapling.getBlockRange(2700500, endHeight: 2700599);

      expect(blocks, isEmpty);
    });

    test('rejects incomplete v1 envelopes', () async {
      final client = FakeElectrumClient([
        {
          'from_height': 2700500,
          'to_height': 2700599,
          'complete': false,
          'blocks': <Map<String, dynamic>>[],
        }
      ]);
      final sapling = PIVXSaplingElectrumX(electrumClient: client);

      expect(
        sapling.getBlockRange(2700500, endHeight: 2700599),
        throwsA(isA<SaplingRpcException>()),
      );
    });

    test('rejects mismatched v1 envelope ranges', () async {
      final client = FakeElectrumClient([
        {
          'from_height': 2700501,
          'to_height': 2700599,
          'complete': true,
          'blocks': <Map<String, dynamic>>[],
        }
      ]);
      final sapling = PIVXSaplingElectrumX(electrumClient: client);

      expect(
        sapling.getBlockRange(2700500, endHeight: 2700599),
        throwsA(isA<SaplingRpcException>()),
      );
    });
  });

  group('PIVXSaplingElectrumX syncBlocks', () {
    test('does not complete a failed range', () async {
      final client = FakeElectrumClient([
        Exception('daemon unavailable'),
        Exception('daemon unavailable'),
        Exception('daemon unavailable'),
      ]);
      final sapling = PIVXSaplingElectrumX(electrumClient: client);
      final completedRanges = <int>[];

      await expectLater(
        sapling.syncBlocks(
          fromHeight: 2700500,
          toHeight: 2700500,
          parallelBatches: 1,
          onBatch: (_) async {},
          onRangeComplete: (rangeEnd) async {
            completedRanges.add(rangeEnd);
          },
        ),
        throwsA(isA<SaplingRpcException>()),
      );

      expect(completedRanges, isEmpty);
      expect(client.calls, equals(3));
    });
  });

  group('PIVXSaplingElectrumX getAnchorBoundWitness', () {
    const anchorHex =
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    const commitmentHex =
        'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

    test('accepts witness bound to selected anchor and commitment', () async {
      final client = FakeElectrumClient([
        {
          'position': 42,
          'path': [
            'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc'
          ],
          'anchor': anchorHex,
          'anchor_height': 2700600,
          'commitment': commitmentHex,
        }
      ]);
      final sapling = PIVXSaplingElectrumX(electrumClient: client);

      final witness = await sapling.getAnchorBoundWitness(
        commitment: commitmentHex,
        anchor: BestAnchorResult(anchor: anchorHex, height: 2700600),
      );

      expect(witness.position, equals(42));
      expect(witness.anchor, equals(anchorHex));
      expect(witness.anchorHeight, equals(2700600));
      expect(witness.commitment, equals(commitmentHex));
    });

    test('rejects witness for a different anchor root', () async {
      final client = FakeElectrumClient([
        {
          'position': 42,
          'path': [
            'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc'
          ],
          'anchor':
              'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
          'anchor_height': 2700600,
          'commitment': commitmentHex,
        }
      ]);
      final sapling = PIVXSaplingElectrumX(electrumClient: client);

      expect(
        sapling.getAnchorBoundWitness(
          commitment: commitmentHex,
          anchor: BestAnchorResult(anchor: anchorHex, height: 2700600),
        ),
        throwsA(isA<SaplingRpcException>()),
      );
    });

    test('rejects witness without anchor metadata', () async {
      final client = FakeElectrumClient([
        {
          'position': 42,
          'path': [
            'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc'
          ],
          'commitment': commitmentHex,
        }
      ]);
      final sapling = PIVXSaplingElectrumX(electrumClient: client);

      expect(
        sapling.getAnchorBoundWitness(
          commitment: commitmentHex,
          anchor: BestAnchorResult(anchor: anchorHex, height: 2700600),
        ),
        throwsA(isA<SaplingRpcException>()),
      );
    });

    test('rejects witness for a different commitment', () async {
      final client = FakeElectrumClient([
        {
          'position': 42,
          'path': [
            'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc'
          ],
          'anchor': anchorHex,
          'anchor_height': 2700600,
          'commitment':
              'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee',
        }
      ]);
      final sapling = PIVXSaplingElectrumX(electrumClient: client);

      expect(
        sapling.getAnchorBoundWitness(
          commitment: commitmentHex,
          anchor: BestAnchorResult(anchor: anchorHex, height: 2700600),
        ),
        throwsA(isA<SaplingRpcException>()),
      );
    });
  });
}
