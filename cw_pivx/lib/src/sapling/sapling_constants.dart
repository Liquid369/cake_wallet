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
  static const String mainnetExtendedSpendingKeyHrp = 'p-secret-extended-key-main';
  
  /// Human-readable part for Sapling extended spending keys (testnet).
  /// Keys start with "p-secret-extended-key-test" followed by Bech32-encoded data.
  static const String testnetExtendedSpendingKeyHrp = 'p-secret-extended-key-test';
  
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
  static const int testnetSaplingActivationHeight = 1164637;
  
  /// Default starting block for shield sync (slightly before activation).
  /// This provides a buffer to ensure no transactions are missed.
  static const int mainnetDefaultStartingShieldBlock = 2700000;
  
  /// Default starting block for shield sync on testnet.
  static const int testnetDefaultStartingShieldBlock = 1164000;
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
    '8270785a1a0d0bc77196f000ee6d221c9c9894f55307bd9357c3f0105d31ca63';
  
  /// Expected SHA256 hash of sapling-output.params.
  static const String outputParamsHash = 
    '657e3d38dbb5cb5e7dd2970e8b03d69b4571757c1ed76c5c5c0a0b6ed89e7db7';
  
  /// Size of sapling-spend.params file in bytes (approximately 47.5 MB).
  static const int spendParamsSize = 47958085;
  
  /// Size of sapling-output.params file in bytes (approximately 3.6 MB).
  static const int outputParamsSize = 3592860;
  
  /// URL for downloading sapling-spend.params (PIVX hosting).
  static const String spendParamsUrl =
    'https://duddino.com/sapling-spend.params';
  
  /// URL for downloading sapling-output.params (PIVX hosting).
  static const String outputParamsUrl =
    'https://duddino.com/sapling-output.params';
}

/// Sapling transaction fee calculation constants.
/// 
/// PIVX uses a size-based fee model similar to transparent transactions,
/// but Sapling transaction components have different sizes.
abstract class SaplingFees {
  /// Fee per byte for PIVX transactions in satoshis.
  static const int feePerByte = 1000;
  
  /// Size of a Sapling output (ciphertext + proof) in bytes.
  static const int saplingOutputSize = 948;
  
  /// Size of a Sapling spend (nullifier + proof) in bytes.
  static const int saplingSpendSize = 384;
  
  /// Size of a transparent input in bytes.
  static const int transparentInputSize = 150;
  
  /// Size of a transparent output in bytes.
  static const int transparentOutputSize = 34;
  
  /// Fixed transaction overhead in bytes.
  static const int txOverheadSize = 85;
  
  /// Calculate the fee for a Sapling transaction.
  /// 
  /// [saplingInputs] - Number of Sapling spends (shielded inputs).
  /// [saplingOutputs] - Number of Sapling outputs (shielded outputs).
  /// [transparentInputs] - Number of transparent inputs.
  /// [transparentOutputs] - Number of transparent outputs.
  static int calculateFee({
    int saplingInputs = 0,
    int saplingOutputs = 0,
    int transparentInputs = 0,
    int transparentOutputs = 0,
  }) {
    final size = txOverheadSize +
        (saplingInputs * saplingSpendSize) +
        (saplingOutputs * saplingOutputSize) +
        (transparentInputs * transparentInputSize) +
        (transparentOutputs * transparentOutputSize);
    return feePerByte * size;
  }
}
