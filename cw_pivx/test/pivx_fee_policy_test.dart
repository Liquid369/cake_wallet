import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:cw_pivx/src/sapling/sapling_constants.dart';
import 'package:cw_pivx/src/sapling/sapling_factories.dart';
import 'package:cw_core/utils/proxy_wrapper.dart';
import 'package:cw_core/utils/tor/disabled.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PivxFeePolicy', () {
    test('uses one transparent fee and dust policy', () {
      expect(PivxFeePolicy.transparentDustThreshold, 5460);
      expect(PivxFeePolicy.shieldedDustThreshold, 1446000);
      expect(
          PivxFeePolicy.dustThreshold, PivxFeePolicy.transparentDustThreshold);
      expect(PivxFeePolicy.feeForSize(182), 10000);
      expect(
        PivxFeePolicy.feeForSize(
          182,
          feePerKb: PivxFeePolicy.dustRelayFeePerKb,
        ),
        5460,
      );
      expect(PivxFeePolicy.transparentTxSize(1, 1), 192);
    });

    test('calculates Sapling fees from transaction size', () {
      expect(
        PivxFeePolicy.saplingFee(saplingInputs: 1, saplingOutputs: 1),
        1417000,
      );
      expect(
        PivxFeePolicy.saplingFee(saplingInputs: 1, saplingOutputs: 2),
        2365000,
      );
    });

    test('derives shielded dust threshold from PIVX Core formula', () {
      final coreShieldedDust = PivxFeePolicy.saplingFeeFactor *
          PivxFeePolicy.feeForSize(
            PivxFeePolicy.saplingSpendSize +
                PivxFeePolicy.transparentOutputSize +
                64,
            feePerKb: PivxFeePolicy.dustRelayFeePerKb,
          );

      expect(coreShieldedDust, 1446000);
      expect(PivxFeePolicy.shieldedDustThreshold, coreShieldedDust);
    });
  });

  group('SaplingParams', () {
    test('uses the verified PIVX-hosted Sapling parameter metadata', () {
      expect(SaplingParams.spendParamsSize, 47958396);
      expect(SaplingParams.outputParamsSize, 3592860);
      expect(
        SaplingParams.spendParamsHash,
        '8e48ffd23abb3a5fd9c5589204f32d9c31285a04b78096ba40a79b75677efc13',
      );
      expect(
        SaplingParams.outputParamsHash,
        '2f0ebbcbb9bb0bcffe95a397e7eba89c29eb4dde6191c339db88570e3f3fb0e4',
      );
      expect(
        SaplingParams.spendParamsUrl,
        'https://duddino.com/sapling-spend.params',
      );
      expect(
        SaplingParams.outputParamsUrl,
        'https://duddino.com/sapling-output.params',
      );
    });
  });

  group('Sapling proving parameter download', () {
    setUp(() {
      CakeTor.instance = CakeTorDisabled();
    });

    test('streams files to temp paths, verifies them, and renames finals',
        () async {
      final spendBytes = List<int>.generate(257, (i) => i % 251);
      final outputBytes = List<int>.generate(113, (i) => (i * 3) % 251);
      final server = await _serveParams(
        spendBytes: spendBytes,
        outputBytes: outputBytes,
      );
      final dir = await Directory.systemTemp.createTemp('pivx_params_test_');
      final progress = <double>[];

      try {
        await SaplingTransactionBuilderWrapper.downloadProvingParamsToPath(
          path: dir.path,
          onProgress: progress.add,
          spendParamsUrl: _serverUrl(server, SaplingParams.spendParamsFileName),
          spendParamsSize: spendBytes.length,
          spendParamsHash: sha256.convert(spendBytes).toString(),
          outputParamsUrl:
              _serverUrl(server, SaplingParams.outputParamsFileName),
          outputParamsSize: outputBytes.length,
          outputParamsHash: sha256.convert(outputBytes).toString(),
        );

        final spendFile =
            File('${dir.path}/${SaplingParams.spendParamsFileName}');
        final outputFile =
            File('${dir.path}/${SaplingParams.outputParamsFileName}');

        expect(await spendFile.readAsBytes(), spendBytes);
        expect(await outputFile.readAsBytes(), outputBytes);
        expect(await File('${spendFile.path}.download').exists(), isFalse);
        expect(await File('${outputFile.path}.download').exists(), isFalse);
        expect(progress.last, 1.0);
      } finally {
        await server.close(force: true);
        await dir.delete(recursive: true);
      }
    });

    test('deletes temp files when verification fails', () async {
      final spendBytes = List<int>.filled(16, 7);
      final outputBytes = List<int>.filled(16, 9);
      final server = await _serveParams(
        spendBytes: spendBytes,
        outputBytes: outputBytes,
      );
      final dir = await Directory.systemTemp.createTemp('pivx_params_bad_');

      try {
        await expectLater(
          SaplingTransactionBuilderWrapper.downloadProvingParamsToPath(
            path: dir.path,
            onProgress: (_) {},
            spendParamsUrl:
                _serverUrl(server, SaplingParams.spendParamsFileName),
            spendParamsSize: spendBytes.length,
            spendParamsHash: '00',
            outputParamsUrl:
                _serverUrl(server, SaplingParams.outputParamsFileName),
            outputParamsSize: outputBytes.length,
            outputParamsHash: sha256.convert(outputBytes).toString(),
          ),
          throwsA(isA<Exception>()),
        );

        final spendFile =
            File('${dir.path}/${SaplingParams.spendParamsFileName}');
        expect(await spendFile.exists(), isFalse);
        expect(await File('${spendFile.path}.download').exists(), isFalse);
      } finally {
        await server.close(force: true);
        await dir.delete(recursive: true);
      }
    });
  });

  group('SaplingTransactionBuilderWrapper note planning', () {
    test('selects enough notes to cover amount and fee', () {
      final selected = SaplingTransactionBuilderWrapper.selectNotesForAmount(
        [
          {'value': 3000000},
          {'value': 500000},
        ],
        2000000,
      );

      expect(selected.length, 2);
    });

    test('deducts dust change into fee instead of creating dust output', () {
      final plan = SaplingTransactionBuilderWrapper.planShieldedSpend(
        totalInput: 3426000,
        amount: 2000000,
        saplingInputs: 1,
      );

      expect(plan.canBuild, isTrue);
      expect(plan.change, 0);
      expect(plan.fee, 1426000);
    });

    test('send-all spends all selected notes with no change', () {
      final notes = [
        {'value': 3000000},
        {'value': 500000},
      ];

      final selected = SaplingTransactionBuilderWrapper.selectNotesForAmount(
        notes,
        2000000,
        spendAll: true,
      );

      expect(selected.length, 2);
    });

    test('z-to-t spend plan uses transparent destination output size', () {
      // 1 spend + 1 transparent vout, no shielded change:
      // size = 85 + 384 + 34 = 503 -> fee = ceil(503*10000/1000)*100.
      final expectedNoChangeFee = PivxFeePolicy.saplingFee(
        saplingInputs: 1,
        saplingOutputs: 0,
        transparentOutputs: 1,
      );
      final plan = SaplingTransactionBuilderWrapper.planShieldedSpend(
        totalInput: 2000000 + expectedNoChangeFee,
        amount: 2000000,
        saplingInputs: 1,
        transparentDestination: true,
      );

      expect(plan.canBuild, isTrue);
      expect(plan.change, 0);
      expect(plan.fee, expectedNoChangeFee);
      expect(expectedNoChangeFee,
          lessThan(PivxFeePolicy.saplingFee(saplingInputs: 1, saplingOutputs: 1)));
    });

    test('z-to-t spend plan pays shielded change above dust', () {
      final withChangeFee = PivxFeePolicy.saplingFee(
        saplingInputs: 1,
        saplingOutputs: 1,
        transparentOutputs: 1,
      );
      final change = PivxFeePolicy.shieldedDustThreshold + 1;
      final plan = SaplingTransactionBuilderWrapper.planShieldedSpend(
        totalInput: 2000000 + withChangeFee + change,
        amount: 2000000,
        saplingInputs: 1,
        transparentDestination: true,
      );

      expect(plan.canBuild, isTrue);
      expect(plan.change, change);
      expect(plan.fee, withChangeFee);
    });

    test('t-to-z shield plan pays transparent change above dust', () {
      final withChangeFee = PivxFeePolicy.saplingFee(
        saplingOutputs: 1,
        transparentInputs: 2,
        transparentOutputs: 1,
      );
      final change = PivxFeePolicy.transparentDustThreshold + 1;
      final plan = SaplingTransactionBuilderWrapper.planShieldSpend(
        totalInput: 2000000 + withChangeFee + change,
        amount: 2000000,
        transparentInputs: 2,
      );

      expect(plan.canBuild, isTrue);
      expect(plan.change, change);
      expect(plan.fee, withChangeFee);
    });

    test('t-to-z shield plan absorbs dust change into the fee', () {
      final noChangeFee = PivxFeePolicy.saplingFee(
        saplingOutputs: 1,
        transparentInputs: 1,
      );
      final dust = PivxFeePolicy.transparentDustThreshold;
      final plan = SaplingTransactionBuilderWrapper.planShieldSpend(
        totalInput: 2000000 + noChangeFee + dust,
        amount: 2000000,
        transparentInputs: 1,
      );

      expect(plan.canBuild, isTrue);
      expect(plan.change, 0);
      expect(plan.fee, noChangeFee + dust);
    });

    test('z-to-t dust change is absorbed into the fee', () {
      final noChangeFee = PivxFeePolicy.saplingFee(
        saplingInputs: 1,
        saplingOutputs: 0,
        transparentOutputs: 1,
      );
      final dustRemainder = PivxFeePolicy.shieldedDustThreshold;
      final plan = SaplingTransactionBuilderWrapper.planShieldedSpend(
        totalInput: 2000000 + noChangeFee + dustRemainder,
        amount: 2000000,
        saplingInputs: 1,
        transparentDestination: true,
      );

      expect(plan.canBuild, isTrue);
      expect(plan.change, 0);
      expect(plan.fee, noChangeFee + dustRemainder);
    });
  });
}

Future<HttpServer> _serveParams({
  required List<int> spendBytes,
  required List<int> outputBytes,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) {
    final requestedFile =
        request.uri.pathSegments.isEmpty ? '' : request.uri.pathSegments.last;
    final bytes = requestedFile == SaplingParams.spendParamsFileName
        ? spendBytes
        : requestedFile == SaplingParams.outputParamsFileName
            ? outputBytes
            : null;

    if (bytes == null) {
      request.response.statusCode = HttpStatus.notFound;
      request.response.close();
      return;
    }

    request.response.contentLength = bytes.length;
    request.response.add(bytes);
    request.response.close();
  });
  return server;
}

String _serverUrl(HttpServer server, String filename) =>
    'http://${InternetAddress.loopbackIPv4.address}:${server.port}/$filename';
