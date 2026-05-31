import 'package:cw_pivx/src/sapling/sapling_constants.dart';
import 'package:cw_pivx/src/sapling/sapling_factories.dart';
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
  });
}
