import 'package:cw_pivx/src/sapling/pivx_sapling_electrumx.dart';
import 'package:cw_pivx/src/sapling/sapling_factories.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeElectrumClient {
  FakeElectrumClient(this.responses);

  final List<dynamic> responses;
  final Map<int, String> errors = {};
  final calledMethods = <String>[];
  final calledParams = <List<Object>>[];
  int calls = 0;
  int _id = 0;

  Future<dynamic> call({
    required String method,
    List<Object> params = const [],
    Function(int)? idCallback,
  }) async {
    calls++;
    calledMethods.add(method);
    calledParams.add(List<Object>.from(params));
    _id++;
    idCallback?.call(_id);
    final response = responses.removeAt(0);
    if (response is FakeRpcError) {
      errors[_id] = response.message;
      return null;
    }
    if (response is Exception) {
      throw response;
    }
    return response;
  }

  String getErrorMessage(int id) => errors[id] ?? '';
}

class FakeRpcError {
  FakeRpcError(this.message);

  final String message;
}

Map<String, dynamic> bestAnchorJson() => {
      'anchor':
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      'height': 2701000,
    };

Map<String, dynamic> nullifierUnspentJson() => {'spent': false};

Map<String, dynamic> commitmentMissingJson() => {'exists': false};

Map<String, dynamic> v1CapabilitiesJson({
  String contract = SaplingRpcCapabilities.v1ContractId,
  List<String>? methods,
  Map<String, dynamic>? features,
  Map<String, dynamic>? rangeResponseFormat,
}) =>
    {
      'contract': contract,
      'server_version': 'ElectrumX 1.19.0-pivx',
      'pivx_core_version': 'v5.6.1',
      'network': 'mainnet',
      'sapling_activation_height': SaplingActivation.mainnet,
      'max_block_range': 100,
      'methods': methods ??
          [
            'blockchain.sapling.get_block_range',
            'blockchain.sapling.get_best_anchor',
            'blockchain.sapling.get_witness',
            'blockchain.sapling.get_nullifier_status',
            'blockchain.sapling.get_commitment_info',
          ],
      'features': features ??
          {
            'global_output_positions': true,
            'block_hashes': true,
            'structured_errors': true,
          },
      'range_response_format': rangeResponseFormat ??
          {
            'global_output_positions': true,
            'block_hashes': true,
          },
    };

void main() {
  group('BestAnchorResult', () {
    test('uses anchor_height instead of chain tip height when present', () {
      final bestAnchor = BestAnchorResult.fromJson({
        'anchor':
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        'height': 5440981,
        'anchor_height': 5440977,
      });

      expect(
          bestAnchor.anchor,
          equals(
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'));
      expect(bestAnchor.height, equals(5440977));
    });
  });

  group('SaplingRpcCapabilities', () {
    test('classifies the complete v1 release contract as release ready', () {
      final capabilities =
          SaplingRpcCapabilities.fromJson(v1CapabilitiesJson());

      expect(capabilities.supportsV1ReleaseContract, isTrue);
      expect(capabilities.advertisesV1Contract, isTrue);
      expect(capabilities.supportsBlockRange, isTrue);
      expect(capabilities.supportsGlobalOutputPositions, isTrue);
      expect(capabilities.supportsBestAnchor, isTrue);
      expect(capabilities.supportsWitness, isTrue);
      expect(capabilities.supportsBlockHashes, isTrue);
      expect(capabilities.supportsStructuredErrors, isTrue);
    });

    test('does not classify partial v1 metadata as release ready', () {
      final capabilities = SaplingRpcCapabilities.fromJson(v1CapabilitiesJson(
        methods: [
          'blockchain.sapling.get_block_range',
          'blockchain.sapling.get_witness',
        ],
        features: {
          'global_output_positions': true,
          'block_hashes': true,
          'structured_errors': true,
        },
      ));

      expect(capabilities.advertisesV1Contract, isTrue);
      expect(capabilities.supportsV1ReleaseContract, isFalse);
    });

    test('marks legacy fallback as compatibility only', () {
      final capabilities = SaplingRpcCapabilities.legacyBlockRangeOnly();

      expect(capabilities.supportsBlockRange, isTrue);
      expect(capabilities.isLegacyBlockRangeOnly, isTrue);
      expect(capabilities.supportsV1ReleaseContract, isFalse);
    });
  });

  group('PIVXSaplingElectrumX probeCapabilities', () {
    test('accepts a complete v1 release contract', () async {
      final client = FakeElectrumClient([
        v1CapabilitiesJson(),
        bestAnchorJson(),
        nullifierUnspentJson(),
        commitmentMissingJson(),
      ]);
      final sapling = PIVXSaplingElectrumX(electrumClient: client);

      final capabilities = await sapling.probeCapabilities();

      expect(capabilities.supportsV1ReleaseContract, isTrue);
      expect(client.calledMethods, [
        'blockchain.sapling.capabilities',
        'blockchain.sapling.get_best_anchor',
        'blockchain.sapling.get_nullifier_status',
        'blockchain.sapling.get_commitment_info',
      ]);
    });

    test('rejects an incomplete advertised v1 release contract', () async {
      final client = FakeElectrumClient([
        v1CapabilitiesJson(
          methods: ['blockchain.sapling.get_block_range'],
        )
      ]);
      final sapling = PIVXSaplingElectrumX(electrumClient: client);

      await expectLater(
        sapling.probeCapabilities(),
        throwsA(isA<SaplingRpcException>()),
      );
    });

    test('rejects advertised v1 when live best-anchor helper fails', () async {
      final client = FakeElectrumClient([
        v1CapabilitiesJson(),
        FakeRpcError('internal server error'),
      ]);
      final sapling = PIVXSaplingElectrumX(electrumClient: client);

      await expectLater(
        sapling.probeCapabilities(),
        throwsA(
          isA<SaplingRpcException>().having(
            (error) => error.message,
            'message',
            contains('live release method validation failed'),
          ),
        ),
      );
      expect(client.calledMethods, [
        'blockchain.sapling.capabilities',
        'blockchain.sapling.get_best_anchor',
      ]);
    });

    test('falls back to legacy block-range compatibility only', () async {
      final client = FakeElectrumClient([
        Exception('unknown method'),
        Exception('method not found'),
        <Map<String, dynamic>>[],
      ]);
      final sapling = PIVXSaplingElectrumX(electrumClient: client);

      final capabilities = await sapling.probeCapabilities();

      expect(capabilities.isLegacyBlockRangeOnly, isTrue);
      expect(capabilities.supportsBlockRange, isTrue);
      expect(capabilities.supportsV1ReleaseContract, isFalse);
      expect(client.calls, equals(3));
    });

    test('tries the legacy capability alias after primary server error',
        () async {
      final client = FakeElectrumClient([
        FakeRpcError('internal server error'),
        v1CapabilitiesJson(),
        bestAnchorJson(),
        nullifierUnspentJson(),
        commitmentMissingJson(),
      ]);
      final sapling = PIVXSaplingElectrumX(electrumClient: client);

      final capabilities = await sapling.probeCapabilities();

      expect(capabilities.supportsV1ReleaseContract, isTrue);
      expect(client.calledMethods, [
        'blockchain.sapling.capabilities',
        'blockchain.sapling.get_capabilities',
        'blockchain.sapling.get_best_anchor',
        'blockchain.sapling.get_nullifier_status',
        'blockchain.sapling.get_commitment_info',
      ]);
    });

    test('does not hide non-capability server errors behind fallbacks',
        () async {
      final client = FakeElectrumClient([
        FakeRpcError('internal server error'),
      ]);
      final sapling = PIVXSaplingElectrumX(electrumClient: client);

      expect(
        sapling.getBlockRange(2700500, endHeight: 2700500),
        throwsA(isA<SaplingRpcException>()),
      );
      expect(client.calls, equals(1));
    });

    test('rejects malformed null capability responses', () async {
      final client = FakeElectrumClient([null]);
      final sapling = PIVXSaplingElectrumX(electrumClient: client);

      await expectLater(
        sapling.probeCapabilities(),
        throwsA(isA<SaplingRpcException>()),
      );
    });
  });

  group('PIVXSaplingElectrumX getBlockRange', () {
    test('accepts complete empty v1 envelopes', () async {
      final client = FakeElectrumClient([
        {
          'from_height': 2700500,
          'to_height': 2700599,
          'complete': true,
          'block_hashes': {
            '2700500': 'hash_a',
            '2700501': 'hash_b',
          },
          'blocks': <Map<String, dynamic>>[],
        }
      ]);
      final sapling = PIVXSaplingElectrumX(electrumClient: client);

      final result =
          await sapling.getBlockRangeResult(2700500, endHeight: 2700599);

      expect(result.blocks, isEmpty);
      expect(result.blockHashes[2700500], equals('hash_a'));
      expect(result.blockHashes[2700501], equals('hash_b'));
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

    test('wraps malformed block entries with block-range context', () async {
      final client = FakeElectrumClient([
        {
          'from_height': 2700500,
          'to_height': 2700500,
          'complete': true,
          'blocks': [
            {'height': 2700500}
          ],
        }
      ]);
      final sapling = PIVXSaplingElectrumX(electrumClient: client);

      expect(
        sapling.getBlockRange(2700500, endHeight: 2700500),
        throwsA(
          isA<SaplingRpcException>().having(
            (error) => error.message,
            'message',
            contains('get_block_range returned malformed block data'),
          ),
        ),
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
      final completedRanges = <String>[];

      await expectLater(
        sapling.syncBlocks(
          fromHeight: 2700500,
          toHeight: 2700500,
          parallelBatches: 1,
          onBatch: (_) async {},
          onRangeComplete: (rangeStart, rangeEnd, blockHashes) async {
            completedRanges.add('$rangeStart-$rangeEnd');
          },
        ),
        throwsA(isA<SaplingRpcException>()),
      );

      expect(completedRanges, isEmpty);
      expect(client.calls, equals(3));
    });

    test('logs first, checkpoint, and final shield sync ranges only', () {
      expect(
        shouldLogPivxShieldSyncCheckpoint(
          rangeStart: 5440400,
          rangeEnd: 5440499,
          startHeight: 5440400,
          targetHeight: 5451000,
        ),
        isTrue,
      );
      expect(
        shouldLogPivxShieldSyncCheckpoint(
          rangeStart: 5440500,
          rangeEnd: 5440599,
          startHeight: 5440400,
          targetHeight: 5451000,
        ),
        isFalse,
      );
      expect(
        shouldLogPivxShieldSyncCheckpoint(
          rangeStart: 5449901,
          rangeEnd: 5450000,
          startHeight: 5440400,
          targetHeight: 5451000,
        ),
        isTrue,
      );
      expect(
        shouldLogPivxShieldSyncCheckpoint(
          rangeStart: 5451000,
          rangeEnd: 5451000,
          startHeight: 5440400,
          targetHeight: 5451000,
        ),
        isTrue,
      );
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
            '0100000000000000000000000000000000000000000000000000000000000000'
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
      expect(witness.source, equals(SaplingWitnessResult.sourceAnchorBound));
      expect(client.calledMethods, contains('blockchain.sapling.get_witness'));
      expect(client.calledParams.single, equals([commitmentHex, anchorHex]));
    });

    test('falls back to commitment-only witness with server-selected anchor',
        () async {
      final client = FakeElectrumClient([
        FakeRpcError('witness not found for 44757'),
        {
          'position': 44757,
          'path': [
            '0100000000000000000000000000000000000000000000000000000000000000'
          ],
          'anchor':
              'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
          'anchor_height': 2700598,
          'commitment': commitmentHex,
        }
      ]);
      final sapling = PIVXSaplingElectrumX(electrumClient: client);

      final witness = await sapling.getAnchorBoundWitness(
        commitment: commitmentHex,
        anchor: BestAnchorResult(anchor: anchorHex, height: 2700600),
        notePosition: 44757,
      );

      expect(witness.position, equals(44757));
      expect(
          witness.anchor,
          equals(
              'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd'));
      expect(witness.anchorHeight, equals(2700598));
      expect(witness.source,
          equals(SaplingWitnessResult.sourceCommitmentOnlyFallback));
      expect(client.calledParams, [
        [commitmentHex, anchorHex],
        [commitmentHex],
      ]);
    });

    test('sanitizes failed real-note witness attempt diagnostics', () async {
      final client = FakeElectrumClient([
        FakeRpcError(
            'canonical_witness_unavailable for $commitmentHex at $anchorHex'),
        FakeRpcError('commitment not found: $commitmentHex'),
        FakeRpcError('method not found for anchor $anchorHex'),
      ]);
      final sapling = PIVXSaplingElectrumX(electrumClient: client);

      await expectLater(
        sapling.getAnchorBoundWitness(
          commitment: commitmentHex,
          anchor: BestAnchorResult(anchor: anchorHex, height: 2700600),
        ),
        throwsA(
          isA<SaplingRpcException>()
              .having(
                (error) => error.message,
                'message',
                contains('commitment_anchor:canonical_witness_unavailable'),
              )
              .having(
                (error) => error.message,
                'message',
                contains('commitment_only:canonical_witness_unavailable'),
              )
              .having(
                (error) => error.message,
                'message',
                isNot(contains(commitmentHex)),
              )
              .having(
                (error) => error.message,
                'message',
                isNot(contains(anchorHex)),
              ),
        ),
      );
      expect(client.calledParams, [
        [commitmentHex, anchorHex],
        [commitmentHex],
        [commitmentHex],
      ]);
    });

    test('normalizes map-shaped witness path elements', () async {
      final client = FakeElectrumClient([
        {
          'position': 42,
          'path': [
            {
              'hash':
                  '0100000000000000000000000000000000000000000000000000000000000000'
            }
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

      expect(witness.path, hasLength(SaplingWitnessResult.saplingTreeDepth));
      expect(witness.path.first,
          '0100000000000000000000000000000000000000000000000000000000000000');
      expect(witness.path[1],
          '817de36ab2d57feb077634bca77819c8e0bd298c04f6fed0e6a83cc1356ca155');
    });

    test('corrects big-endian witness path elements', () async {
      final client = FakeElectrumClient([
        {
          'position': 42,
          'path': [
            '0000000000000000000000000000000000000000000000000000000000000080'
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

      expect(witness.path.first,
          '8000000000000000000000000000000000000000000000000000000000000000');
      expect(witness.path, hasLength(SaplingWitnessResult.saplingTreeDepth));
    });

    test('rejects commitment-only witness for a different commitment',
        () async {
      final client = FakeElectrumClient([
        FakeRpcError('witness not found for anchor'),
        {
          'position': 42,
          'path': [
            '0100000000000000000000000000000000000000000000000000000000000000'
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
          notePosition: 42,
        ),
        throwsA(isA<SaplingRpcException>()),
      );
    });

    test('rejects witness for a different anchor root', () async {
      final client = FakeElectrumClient([
        {
          'position': 42,
          'path': [
            '0100000000000000000000000000000000000000000000000000000000000000'
          ],
          'anchor':
              'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
          'anchor_height': 2700600,
          'commitment': commitmentHex,
        },
        FakeRpcError('witness not found'),
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
            '0100000000000000000000000000000000000000000000000000000000000000'
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
            '0100000000000000000000000000000000000000000000000000000000000000'
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
