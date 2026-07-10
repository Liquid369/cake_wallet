import 'dart:typed_data';
import 'package:bitcoin_base/bitcoin_base.dart';
import 'package:blockchain_utils/base58/base58.dart';
import 'package:blockchain_utils/bip/bip/bip.dart';
import 'package:blockchain_utils/bip/coin_conf/coin_conf.dart';
import 'package:blockchain_utils/bip/coin_conf/coins_name.dart';
import 'package:blockchain_utils/crypto/quick_crypto.dart';
import 'package:blockchain_utils/utils/binary/utils.dart';

/// PIVX network configuration based on PIVX Core specifications.
/// 
/// Source: https://github.com/PIVX-Project/PIVX/blob/master/src/chainparams.cpp
/// 
/// PIVX uses BIP44 coin type 119 (SLIP-44).
/// Standard P2PKH derivation path: m/44'/119'/account'/change/address_index
/// 
/// Base58 Prefixes (from chainparams.cpp lines ~326-346):
/// - PUBKEY_ADDRESS: 30 -> prefix 'D'
/// - SCRIPT_ADDRESS: 13 -> prefix '8'
/// - STAKING_ADDRESS: 63 -> prefix 'S'
/// - EXCHANGE_ADDRESS: {0x01, 0xb9, 0xa2} -> prefix 'EXM'
/// - SECRET_KEY: 212 -> WIF prefix
/// - EXT_PUBLIC_KEY: {0x02, 0x2D, 0x25, 0x33}
/// - EXT_SECRET_KEY: {0x02, 0x21, 0x31, 0x2B}
/// 
/// Network Parameters:
/// - Magic bytes: 0x90, 0xc4, 0xfd, 0xe9
/// - P2P Port: 51472
/// - RPC Port: 51473
/// - Coinbase maturity: 100 blocks
/// - Block time: 60 seconds
/// - minRelayTxFee: 10000 sat/kB

/// Custom CoinConf for PIVX mainnet
final CoinConf pivxMainNetConf = CoinConf(
  coinName: const CoinNames("PIVX", "PIVX"),
  params: const CoinParams(
    p2pkhNetVer: [30],  // 0x1E - 'D' prefix
    p2shNetVer: [13],   // 0x0D - '8' prefix
    wifNetVer: [212],   // 0xD4 - WIF prefix
  ),
);

/// Custom CoinConf for PIVX testnet
final CoinConf pivxTestNetConf = CoinConf(
  coinName: const CoinNames("PIVX TestNet", "PIVX"),
  params: const CoinParams(
    p2pkhNetVer: [139], // 0x8B - testnet P2PKH prefix
    p2shNetVer: [19],   // 0x13 - testnet P2SH prefix  
    wifNetVer: [239],   // 0xEF - testnet WIF prefix
  ),
);

/// PIVX mainnet network implementation
class PivxNetwork implements BasedUtxoNetwork {
  /// Mainnet configuration
  static const PivxNetwork mainnet = PivxNetwork._("pivxMainnet");
  
  /// Testnet configuration
  static const PivxNetwork testnet = _PivxTestnet._("pivxTestnet");

  @override
  final String value;

  /// Private constructor
  const PivxNetwork._(this.value);

  /// Get the coin configuration
  @override
  CoinConf get conf => pivxMainNetConf;

  /// WIF version bytes
  @override
  List<int> get wifNetVer => conf.params.wifNetVer!;

  /// P2PKH version bytes (produces 'D' addresses)
  @override
  List<int> get p2pkhNetVer => conf.params.p2pkhNetVer!;

  /// P2SH version bytes (produces '8' addresses)
  @override
  List<int> get p2shNetVer => conf.params.p2shNetVer!;

  /// PIVX does not support native SegWit (P2WPKH/P2WSH)
  /// Return empty string instead of throwing to allow graceful fallback
  /// in address type detection code.
  @override
  String get p2wpkhHrp => "";

  /// Supported address types
  @override
  final List<BitcoinAddressType> supportedAddress = const [
    PubKeyAddressType.p2pk,
    P2pkhAddressType.p2pkh,
    P2shAddressType.p2pkhInP2sh,
    P2shAddressType.p2pkInP2sh,
  ];

  /// Check if this is mainnet
  @override
  bool get isMainnet => this == PivxNetwork.mainnet;

  /// BIP coins supported
  @override
  List<BipCoins> get coins {
    // PIVX uses coin type 119 - we use Bitcoin's Bip44 coin as 
    // blockchain_utils doesn't have PIVX specifically
    // The actual coin type will be overridden in derivation
    if (isMainnet) return [Bip44Coins.bitcoin];
    return [Bip44Coins.bitcoinTestnet];
  }

  // --- PIVX-specific extensions (not part of BasedUtxoNetwork) ---

  /// PIVX staking address prefix (produces 'S' addresses)
  static const int stakingAddressPrefix = 63;

  /// SLIP-44 coin type for PIVX
  static const int coinType = 119;

  /// Network magic bytes for P2P protocol
  static const List<int> magicBytes = [0x90, 0xc4, 0xfd, 0xe9];

  /// Default P2P port
  static const int defaultPort = 51472;

  /// Default RPC port
  static const int rpcPort = 51473;

  /// Coinbase maturity (blocks before coinbase can be spent)
  static const int coinbaseMaturity = 100;

  /// Target block time in seconds
  static const int targetBlockTime = 60;

  /// Minimum relay transaction fee in satoshis per kB
  static const int minRelayTxFee = 10000;

  /// Dust relay fee in satoshis per kB
  static const int dustRelayFee = 30000;

  /// Dust threshold in satoshis
  static const int dustThreshold = 5460;

  /// PIVX Sapling payment address HRP
  static const String saplingPaymentAddressHrp = 'ps';

  /// PIVX Sapling full viewing key HRP
  static const String saplingFullViewingKeyHrp = 'pviews';

  /// PIVX Sapling incoming viewing key HRP
  static const String saplingIncomingViewingKeyHrp = 'pivks';

  /// PIVX Sapling extended spending key HRP
  static const String saplingExtendedSpendingKeyHrp = 'p-secret-extended-key-main';

  /// Helper to validate a PIVX address format
  static bool isValidAddress(String address) {
    // PIVX P2PKH addresses start with 'D'
    if (address.startsWith('D') && address.length >= 26 && address.length <= 35) {
      return true;
    }
    // PIVX P2SH addresses start with '8'
    if (address.startsWith('8') && address.length >= 26 && address.length <= 35) {
      return true;
    }
    // PIVX Staking addresses start with 'S'
    if (address.startsWith('S') && address.length >= 26 && address.length <= 35) {
      return true;
    }
    // PIVX Exchange addresses start with 'EXM'
    if (address.startsWith('EXM') && address.length >= 26 && address.length
        <= 35) {
      return true;
    }
    // PIVX Sapling addresses start with 'ps'
    if (address.startsWith('ps') && address.length > 50) {
      return true;
    }
    return false;
  }

  /// Helper to identify address type
  static String getAddressType(String address) {
    if (address.startsWith('D')) return 'P2PKH';
    if (address.startsWith('8')) return 'P2SH';
    if (address.startsWith('S')) return 'Staking';
    if (address.startsWith('EXM')) return 'Exchange';
    if (address.startsWith('ps')) return 'Sapling';
    return 'Unknown';
  }

  /// Exchange address version bytes (produces 'EXM' prefix addresses)
  /// From chainparams.cpp: EXCHANGE_ADDRESS = {0x01, 0xb9, 0xa2}
  /// These addresses are used for exchange accounting and cannot receive shielded transactions.
  static const List<int> exchangeAddressPrefix = [0x01, 0xb9, 0xa2];

  /// OP_EXCHANGEADDR opcode value (from script.h)
  /// This opcode is appended to exchange address scriptPubKeys
  static const int opExchangeAddr = 0xe0;

  /// Compute scripthash for a PIVX address (P2PKH or Exchange).
  /// This avoids the SegWit-related exceptions in the bitcoin_base package.
  /// 
  /// The scripthash is the reversed SHA256 of the scriptPubKey.
  /// 
  /// For P2PKH: 
  ///   OP_DUP OP_HASH160 <20-byte pubkeyhash> OP_EQUALVERIFY OP_CHECKSIG
  /// 
  /// For Exchange (EXM):
  ///   OP_DUP OP_HASH160 <20-byte pubkeyhash> OP_EQUALVERIFY OP_CHECKSIG OP_EXCHANGEADDR
  /// 
  /// PIVX address types:
  /// - 'D...' - Standard P2PKH (1-byte version: 30)
  /// - 'EXM...' - Exchange addresses (3-byte version: [0x01, 0xb9, 0xa2])
  /// - 'S...' - Staking addresses (1-byte version: 63)
  /// - 'ps1...' - Sapling shielded addresses (not handled here)
  /// Build the 25-byte P2PKH scriptPubKey hex for a standard PIVX
  /// transparent address ('D...' mainnet, 'x.../y...' testnet).
  /// Returns an empty string for unsupported address shapes.
  static String p2pkhScriptPubKeyHex(String address) {
    try {
      final decoded = Base58Decoder.checkDecode(address);
      if (decoded.length != 21) return '';
      final pubkeyHash = decoded.sublist(1);
      final script = Uint8List(25);
      script[0] = 0x76; // OP_DUP
      script[1] = 0xa9; // OP_HASH160
      script[2] = 0x14; // push 20 bytes
      script.setRange(3, 23, pubkeyHash);
      script[23] = 0x88; // OP_EQUALVERIFY
      script[24] = 0xac; // OP_CHECKSIG
      return script
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
    } catch (_) {
      return '';
    }
  }

  static String computeScriptHash(String address) {
    try {
      // Decode base58check address to get version byte(s) + pubkey hash
      final decoded = Base58Decoder.checkDecode(address);
      if (decoded.isEmpty) return '';
      
      // Determine address type by prefix
      Uint8List pubkeyHash;
      bool isExchangeAddress = false;
      
      if (address.startsWith('EXM')) {
        // Exchange address: 3-byte version prefix [0x01, 0xb9, 0xa2] + 20-byte pubkey hash
        if (decoded.length < 23) return '';
        pubkeyHash = Uint8List.fromList(decoded.sublist(3));
        isExchangeAddress = true;
      } else {
        // Standard address: 1-byte version prefix + 20-byte pubkey hash
        // Works for 'D' (P2PKH), 'S' (staking), '8' (P2SH)
        pubkeyHash = Uint8List.fromList(decoded.sublist(1));
      }
      
      if (pubkeyHash.length != 20) return '';
      
      // Build the scriptPubKey
      Uint8List scriptPubKey;
      
      if (isExchangeAddress) {
        // Exchange address scriptPubKey (26 bytes):
        // OP_EXCHANGEADDR (0xe0) OP_DUP (0x76) OP_HASH160 (0xa9) <length:0x14> 
        // <pubkeyhash:20bytes> OP_EQUALVERIFY (0x88) OP_CHECKSIG (0xac)
        scriptPubKey = Uint8List(26);
        scriptPubKey[0] = 0xe0;  // OP_EXCHANGEADDR
        scriptPubKey[1] = 0x76;  // OP_DUP
        scriptPubKey[2] = 0xa9;  // OP_HASH160
        scriptPubKey[3] = 0x14;  // Push 20 bytes
        scriptPubKey.setRange(4, 24, pubkeyHash);
        scriptPubKey[24] = 0x88; // OP_EQUALVERIFY
        scriptPubKey[25] = 0xac; // OP_CHECKSIG
      } else {
        // Standard P2PKH scriptPubKey (25 bytes):
        // OP_DUP (0x76) OP_HASH160 (0xa9) <length:0x14> <pubkeyhash:20bytes> 
        // OP_EQUALVERIFY (0x88) OP_CHECKSIG (0xac)
        scriptPubKey = Uint8List(25);
        scriptPubKey[0] = 0x76;  // OP_DUP
        scriptPubKey[1] = 0xa9;  // OP_HASH160
        scriptPubKey[2] = 0x14;  // Push 20 bytes
        scriptPubKey.setRange(3, 23, pubkeyHash);
        scriptPubKey[23] = 0x88; // OP_EQUALVERIFY
        scriptPubKey[24] = 0xac; // OP_CHECKSIG
      }
      
      // SHA256 hash of the scriptPubKey
      final hash = QuickCrypto.sha256Hash(scriptPubKey);
      
      // Reverse the bytes and convert to hex
      final reversed = Uint8List.fromList(hash.reversed.toList());
      return BytesUtils.toHexString(reversed);
    } catch (e) {
      return '';
    }
  }
}

/// PIVX testnet network implementation
class _PivxTestnet extends PivxNetwork {
  const _PivxTestnet._(String value) : super._(value);

  @override
  CoinConf get conf => pivxTestNetConf;

  @override
  bool get isMainnet => false;

  /// Testnet magic bytes
  static const List<int> testnetMagicBytes = [0x45, 0x76, 0x65, 0x21];

  /// Testnet P2P port
  static const int testnetPort = 51474;

  /// Testnet RPC port
  static const int testnetRpcPort = 51475;
}
