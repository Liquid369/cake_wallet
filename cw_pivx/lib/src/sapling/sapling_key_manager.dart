/// Sapling key derivation and management.
/// 
/// This module handles the derivation of Sapling keys from a BIP39 seed
/// following the ZIP-32 specification (https://zips.z.cash/zip-0032).
/// 
/// Key hierarchy for PIVX Sapling:
/// ```
/// seed (64 bytes from BIP39)
///   └── master extended spending key (m_sapling)
///         └── purpose = 32' (hardened, Sapling)
///               └── coin_type = 119' (hardened, PIVX)
///                     └── account = n' (hardened)
///                           ├── Extended Spending Key (extsk)
///                           │     └── Used to spend notes
///                           └── Extended Full Viewing Key (extfvk)
///                                 ├── Used to scan for incoming notes
///                                 └── Diversified payment addresses
/// ```
library;

import 'dart:typed_data';

import 'sapling_constants.dart';

/// Represents a Sapling extended spending key.
/// 
/// The extended spending key contains:
/// - ask (256 bits): The spend authorizing key
/// - nsk (256 bits): The nullifier private key
/// - ovk (256 bits): The outgoing viewing key
/// - dk (256 bits): The diversifier key
/// - chain_code (256 bits): The chain code for derivation
/// 
/// This key can derive child keys and sign transactions.
class SaplingExtendedSpendingKey {
  SaplingExtendedSpendingKey({
    required this.raw,
    required this.encoded,
    required this.isTestnet,
  });

  /// The raw key bytes.
  final Uint8List raw;

  /// The Bech32-encoded key string.
  /// Format: [HRP]1[data] where HRP is 'p-secret-extended-key-main' or 'p-secret-extended-key-test'
  final String encoded;

  /// Whether this is a testnet key.
  final bool isTestnet;

  /// Get the HRP (Human Readable Part) for this key.
  String get hrp => isTestnet
      ? PivxSaplingNetwork.testnetExtendedSpendingKeyHrp
      : PivxSaplingNetwork.mainnetExtendedSpendingKeyHrp;
}

/// Represents a Sapling extended full viewing key.
/// 
/// The extended full viewing key contains:
/// - ak (256 bits): The spend validating key (derived from ask)
/// - nk (256 bits): The nullifier deriving key (derived from nsk)
/// - ovk (256 bits): The outgoing viewing key
/// - dk (256 bits): The diversifier key
/// - chain_code (256 bits): The chain code for derivation
/// 
/// This key can:
/// - Derive payment addresses
/// - Scan for incoming notes (trial decryption)
/// - Derive nullifiers for spent detection
/// - View outgoing transaction details
/// 
/// It CANNOT sign transactions (that requires the spending key).
class SaplingExtendedFullViewingKey {
  SaplingExtendedFullViewingKey({
    required this.raw,
    required this.encoded,
    required this.isTestnet,
  });

  /// The raw key bytes.
  final Uint8List raw;

  /// The Bech32-encoded key string.
  /// Format: [HRP]1[data] where HRP is 'pviews' or 'pviewtestsapling'
  final String encoded;

  /// Whether this is a testnet key.
  final bool isTestnet;

  /// Get the HRP for this key.
  String get hrp => isTestnet
      ? PivxSaplingNetwork.testnetFullViewingKeyHrp
      : PivxSaplingNetwork.mainnetFullViewingKeyHrp;
}

/// Represents a Sapling incoming viewing key.
/// 
/// The incoming viewing key (ivk) is derived from ak and nk:
/// ivk = CRH^ivk(ak, nk)
/// 
/// This key can only decrypt incoming notes (trial decryption).
/// It cannot derive nullifiers or view outgoing transactions.
class SaplingIncomingViewingKey {
  SaplingIncomingViewingKey({
    required this.raw,
    required this.encoded,
    required this.isTestnet,
  });

  /// The raw key bytes (32 bytes).
  final Uint8List raw;

  /// The Bech32-encoded key string.
  final String encoded;

  /// Whether this is a testnet key.
  final bool isTestnet;
}

/// Represents a Sapling diversifier.
/// 
/// Diversifiers allow generating multiple unlinkable payment addresses
/// from a single viewing key. A diversifier is 11 bytes, and not all
/// 11-byte values are valid diversifiers.
class SaplingDiversifier {
  SaplingDiversifier({
    required this.bytes,
    required this.index,
  });

  /// The diversifier bytes (11 bytes).
  final Uint8List bytes;

  /// The diversifier index used to derive this diversifier.
  final Uint8List index;

  /// Check if this is the default diversifier (index 0).
  bool get isDefault {
    for (final b in index) {
      if (b != 0) return false;
    }
    return true;
  }
}

/// Represents a Sapling payment address.
/// 
/// A payment address consists of:
/// - diversifier d (11 bytes): Unique per address
/// - pk_d (32 bytes): Diversified transmission key
/// 
/// The address is encoded as: [HRP]1[Bech32(d || pk_d)]
class SaplingPaymentAddress {
  SaplingPaymentAddress({
    required this.diversifier,
    required this.pkD,
    required this.encoded,
    required this.isTestnet,
  });

  /// The diversifier (11 bytes).
  final Uint8List diversifier;

  /// The diversified transmission key pk_d (32 bytes).
  final Uint8List pkD;

  /// The Bech32-encoded address string.
  /// Format: ps1... (mainnet) or ptestsapling1... (testnet)
  final String encoded;

  /// Whether this is a testnet address.
  final bool isTestnet;

  /// Get the HRP for this address.
  String get hrp => isTestnet
      ? PivxSaplingNetwork.testnetPaymentAddressHrp
      : PivxSaplingNetwork.mainnetPaymentAddressHrp;

  /// Get the raw bytes of this address (43 bytes).
  Uint8List get raw {
    final bytes = Uint8List(43);
    bytes.setAll(0, diversifier);
    bytes.setAll(11, pkD);
    return bytes;
  }
}

/// Manages Sapling key derivation and storage.
/// 
/// This class is responsible for:
/// - Deriving Sapling keys from a BIP39 seed
/// - Managing multiple accounts
/// - Generating diversified payment addresses
/// - Providing keys for transaction signing and note scanning
/// 
/// ## Usage
/// ```dart
/// final seed = Uint8List.fromList(bip39SeedBytes);
/// final keyManager = SaplingKeyManager(seed: seed, isTestnet: false);
/// await keyManager.initialize();
/// 
/// // Get the default payment address
/// final address = await keyManager.getDefaultAddress();
/// print('Shield address: ${address.encoded}');
/// 
/// // Generate a new diversified address
/// final newAddress = await keyManager.getNextAddress();
/// ```
abstract class SaplingKeyManager {
  /// Create a new SaplingKeyManager.
  /// 
  /// [seed] - The 64-byte BIP39 seed.
  /// [isTestnet] - Whether to use testnet parameters.
  /// [accountIndex] - The account index to use (default 0).
  SaplingKeyManager({
    required this.seed,
    required this.isTestnet,
    this.accountIndex = 0,
  });

  /// The BIP39 seed (64 bytes).
  final Uint8List seed;

  /// Whether this is a testnet wallet.
  final bool isTestnet;

  /// The account index (used in key derivation path).
  final int accountIndex;

  /// Get the coin type for key derivation.
  int get coinType => isTestnet
      ? PivxSaplingNetwork.testnetCoinType
      : PivxSaplingNetwork.mainnetCoinType;

  /// Initialize the key manager.
  /// 
  /// This derives the master key and account keys from the seed.
  /// Must be called before any other operations.
  Future<void> initialize();

  /// Get the extended spending key for this account.
  Future<SaplingExtendedSpendingKey> getExtendedSpendingKey();

  /// Get the extended full viewing key for this account.
  Future<SaplingExtendedFullViewingKey> getExtendedFullViewingKey();

  /// Get the incoming viewing key for this account.
  Future<SaplingIncomingViewingKey> getIncomingViewingKey();

  /// Get the default payment address (diversifier index 0).
  Future<SaplingPaymentAddress> getDefaultAddress();

  /// Get the next unused payment address.
  /// 
  /// This increments the diversifier index and finds the next valid
  /// diversifier to create a new payment address.
  Future<SaplingPaymentAddress> getNextAddress();

  /// Get a payment address at a specific diversifier index.
  /// 
  /// [diversifierIndex] - The 11-byte diversifier index.
  /// Returns null if the diversifier at that index is not valid.
  Future<SaplingPaymentAddress?> getAddressAtIndex(Uint8List diversifierIndex);

  /// Check if an address belongs to this wallet.
  /// 
  /// [address] - The Bech32-encoded Sapling address to check.
  Future<bool> isOwnAddress(String address);

  /// Get the current diversifier index.
  Uint8List get currentDiversifierIndex;

  /// Dispose of any resources.
  void dispose();
}

/// Factory for creating SaplingKeyManager instances.
/// 
/// The actual implementation depends on the platform:
/// - Native platforms (iOS, Android, macOS, Linux, Windows): Use FFI to native library
/// - Web: Use WASM-based implementation
abstract class SaplingKeyManagerFactory {
  /// Create a SaplingKeyManager instance.
  /// 
  /// This may involve loading native libraries or initializing WASM modules.
  static Future<SaplingKeyManager> create({
    required Uint8List seed,
    required bool isTestnet,
    int accountIndex = 0,
  }) {
    // This will be implemented by platform-specific code
    throw UnimplementedError(
      'SaplingKeyManager is not yet implemented. '
      'Native library bindings are required for Sapling cryptography.',
    );
  }
}
