/// PIVX Sapling protocol constants.
///
/// These constants define the cryptographic parameters and network-specific
/// values for PIVX's implementation of the Sapling shielded protocol.
///
/// PIVX Sapling is based on Zcash Sapling with PIVX-specific network parameters
/// including different HRP (Human Readable Part) strings for address encoding.
library;

/// Sapling commitment tree depth.
///
/// The Sapling note commitment tree is a Merkle tree with 32 levels,
/// allowing for up to 2^32 note commitments.
const int kSaplingTreeDepth = 32;

/// Sapling extended spending key size in bytes.
const int kSaplingExtendedSpendingKeySize = 169;

/// Sapling extended full viewing key size in bytes.
const int kSaplingExtendedFullViewingKeySize = 169;

/// Sapling payment address size in bytes.
const int kSaplingPaymentAddressSize = 43;

/// Sapling note plaintext size in bytes.
const int kSaplingNotePlaintextSize = 580;

/// Sapling diversifier size in bytes.
const int kSaplingDiversifierSize = 11;

/// PIVX Sapling network constants.
abstract class PivxSaplingNetwork {
  /// BIP-44 coin type for mainnet (used in key derivation).
  static const int mainnetCoinType = 119;

  /// BIP-44 coin type for testnet (used in key derivation).
  static const int testnetCoinType = 1;

  /// Human-readable part for Sapling payment addresses (mainnet).
  /// Addresses start with "ps" followed by Bech32-encoded data.
  static const String mainnetPaymentAddressHrp = 'ps';

  /// Human-readable part for Sapling payment addresses (testnet).
  /// Addresses start with "ptestsapling" followed by Bech32-encoded data.
  static const String testnetPaymentAddressHrp = 'ptestsapling';

  /// Human-readable part for Sapling extended spending keys (mainnet).
  /// Keys start with "p-secret-extended-key-main" followed by Bech32-encoded data.
  static const String mainnetExtendedSpendingKeyHrp =
      'p-secret-extended-key-main';

  /// Human-readable part for Sapling extended spending keys (testnet).
  /// Keys start with "p-secret-extended-key-test" followed by Bech32-encoded data.
  static const String testnetExtendedSpendingKeyHrp =
      'p-secret-extended-key-test';

  /// Human-readable part for Sapling full viewing keys (mainnet).
  /// Keys start with "pviews" followed by Bech32-encoded data.
  static const String mainnetFullViewingKeyHrp = 'pviews';

  /// Human-readable part for Sapling full viewing keys (testnet).
  /// Keys start with "pviewtestsapling" followed by Bech32-encoded data.
  static const String testnetFullViewingKeyHrp = 'pviewtestsapling';

  /// Human-readable part for Sapling incoming viewing keys (mainnet).
  /// Keys start with "pivks" followed by Bech32-encoded data.
  static const String mainnetIncomingViewingKeyHrp = 'pivks';

  /// Human-readable part for Sapling incoming viewing keys (testnet).
  /// Keys start with "pivktestsapling" followed by Bech32-encoded data.
  static const String testnetIncomingViewingKeyHrp = 'pivktestsapling';

  /// Block height at which Sapling activated on mainnet.
  /// All shielded transaction scanning starts from this block.
  static const int mainnetSaplingActivationHeight = 2700500;

  /// Block height at which Sapling activated on testnet.
  /// Confirmed against PIVX Core v5.6.1 `src/chainparams.cpp`.
  static const int testnetSaplingActivationHeight = 201;

  /// Default starting block for shield sync (slightly before activation).
  /// This provides a buffer to ensure no transactions are missed.
  static const int mainnetDefaultStartingShieldBlock = 2700000;

  /// Default starting block for shield sync on testnet.
  static const int testnetDefaultStartingShieldBlock = 201;
}

/// Sapling proof parameter file information.
///
/// Sapling transactions require two proving key files for generating
/// zk-SNARK proofs: one for outputs and one for spends.
abstract class SaplingParams {
  /// Sapling spend parameters file name.
  static const String spendParamsFileName = 'sapling-spend.params';

  /// Sapling output parameters file name.
  static const String outputParamsFileName = 'sapling-output.params';

  /// Expected SHA256 hash of sapling-spend.params.
  /// This ensures the file hasn't been corrupted or tampered with.
  static const String spendParamsHash =
      '8e48ffd23abb3a5fd9c5589204f32d9c31285a04b78096ba40a79b75677efc13';

  /// Expected SHA256 hash of sapling-output.params.
  static const String outputParamsHash =
      '2f0ebbcbb9bb0bcffe95a397e7eba89c29eb4dde6191c339db88570e3f3fb0e4';

  /// Size of sapling-spend.params file in bytes (approximately 47.5 MB).
  static const int spendParamsSize = 47958396;

  /// Size of sapling-output.params file in bytes (approximately 3.6 MB).
  static const int outputParamsSize = 3592860;

  /// URL for downloading sapling-spend.params (PIVX hosting).
  static const String spendParamsUrl =
      'https://duddino.com/sapling-spend.params';

  /// URL for downloading sapling-output.params (PIVX hosting).
  static const String outputParamsUrl =
      'https://duddino.com/sapling-output.params';
}

/// PIVX transaction fee and dust policy shared by transparent and Sapling code.
///
/// These values mirror PIVX Core's v5.6.1 relay policy: min relay fee of
/// 10,000 zatoshis/kB, dust relay fee of 30,000 zatoshis/kB, Sapling relay fee
/// factor of 100, transparent dust threshold of 5,460 zatoshis, and shielded
/// dust threshold of 1,446,000 zatoshis.
abstract class PivxFeePolicy {
  static const int zatoshisPerPiv = 100000000;
  static const int minRelayFeePerKb = 10000;
  static const int dustRelayFeePerKb = 30000;
  static const int saplingFeeFactor = 100;
  static const int transparentDustThreshold = 5460;
  static const int shieldedDustThreshold = 1446000;
  static const int dustThreshold = transparentDustThreshold;
  static const int maxReasonableFee = zatoshisPerPiv;

  static const int transparentInputSize = 148;
  static const int transparentOutputSize = 34;
  static const int transparentTxOverheadSize = 10;

  static const int saplingSpendSize = 384;
  static const int saplingOutputSize = 948;
  static const int saplingTxOverheadSize = 85;

  static int feeForSize(int size, {int feePerKb = minRelayFeePerKb}) {
    if (size <= 0) return minRelayFeePerKb;
    final fee = (feePerKb * size + 999) ~/ 1000;
    return fee < minRelayFeePerKb ? minRelayFeePerKb : fee;
  }

  static int transparentTxSize(int inputsCount, int outputsCount) =>
      inputsCount * transparentInputSize +
      outputsCount * transparentOutputSize +
      transparentTxOverheadSize;

  static int saplingTxSize({
    int saplingInputs = 0,
    int saplingOutputs = 0,
    int transparentInputs = 0,
    int transparentOutputs = 0,
  }) =>
      saplingTxOverheadSize +
      (saplingInputs * saplingSpendSize) +
      (saplingOutputs * saplingOutputSize) +
      (transparentInputs * transparentInputSize) +
      (transparentOutputs * transparentOutputSize);

  static int saplingFee({
    int saplingInputs = 0,
    int saplingOutputs = 0,
    int transparentInputs = 0,
    int transparentOutputs = 0,
  }) =>
      saplingFeeFactor *
      feeForSize(
        saplingTxSize(
          saplingInputs: saplingInputs,
          saplingOutputs: saplingOutputs,
          transparentInputs: transparentInputs,
          transparentOutputs: transparentOutputs,
        ),
      );

  static bool isDust(int amount, {bool shielded = false}) =>
      amount > 0 &&
      amount < (shielded ? shieldedDustThreshold : transparentDustThreshold);
}

/// Backwards-compatible Sapling fee facade.
abstract class SaplingFees {
  static const int feePerKb = PivxFeePolicy.minRelayFeePerKb;
  static const int saplingOutputSize = PivxFeePolicy.saplingOutputSize;
  static const int saplingSpendSize = PivxFeePolicy.saplingSpendSize;
  static const int transparentInputSize = PivxFeePolicy.transparentInputSize;
  static const int transparentOutputSize = PivxFeePolicy.transparentOutputSize;
  static const int txOverheadSize = PivxFeePolicy.saplingTxOverheadSize;

  static int calculateFee({
    int saplingInputs = 0,
    int saplingOutputs = 0,
    int transparentInputs = 0,
    int transparentOutputs = 0,
  }) =>
      PivxFeePolicy.saplingFee(
        saplingInputs: saplingInputs,
        saplingOutputs: saplingOutputs,
        transparentInputs: transparentInputs,
        transparentOutputs: transparentOutputs,
      );
}
