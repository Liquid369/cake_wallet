import 'package:bitcoin_base/bitcoin_base.dart';
import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:cw_bitcoin/electrum_wallet_addresses.dart';
import 'package:cw_bitcoin/utils.dart';
import 'package:cw_core/wallet_info.dart';
import 'package:mobx/mobx.dart';

part 'pivx_wallet_addresses.g.dart';

/// PIVX wallet address management.
/// 
/// PIVX uses BIP44 with coin type 119:
/// Standard derivation path: m/44'/119'/account'/change/address_index
/// 
/// Address types:
/// - P2PKH: Standard addresses starting with 'D'
/// - P2SH: Script addresses starting with '8' (for compatibility)
/// - Staking: Cold staking addresses starting with 'S'
/// - Sapling: Shielded addresses starting with 'ps1'
/// 
/// Note: PIVX does not use native SegWit, but this class follows the
/// Electrum wallet pattern for consistency with other Bitcoin-like coins.
class PivxWalletAddresses = PivxWalletAddressesBase with _$PivxWalletAddresses;

abstract class PivxWalletAddressesBase extends ElectrumWalletAddresses with Store {
  PivxWalletAddressesBase(
    WalletInfo walletInfo, {
    required super.mainHd,
    required super.sideHd,
    required super.network,
    required super.isHardwareWallet,
    super.initialAddresses,
    super.initialRegularAddressIndex,
    super.initialChangeAddressIndex,
    super.initialAddressPageType,
  }) : super(walletInfo);

  @override
  String getAddress({
    required int index,
    required Bip32Slip10Secp256k1 hd,
    BitcoinAddressType? addressType,
  }) =>
      generateP2PKHAddress(hd: hd, index: index, network: network);

  /// Currently selected shielded address (for display purposes).
  @observable
  String? selectedShieldedAddress;

  /// Returns the currently selected address (shielded or transparent).
  @override
  @computed
  String get address {
    // If a shielded address is selected, return it
    if (selectedShieldedAddress != null) {
      return selectedShieldedAddress!;
    }
    // Otherwise return the transparent address from parent
    return super.address;
  }

  @override
  set address(String addr) {
    // Handle PIVX Sapling shielded addresses (start with 'ps')
    // These are not stored in the regular address list
    if (addr.startsWith('ps1') || addr.startsWith('ps')) {
      selectedShieldedAddress = addr;
      return;
    }
    // Clear shielded selection when a transparent address is selected
    selectedShieldedAddress = null;
    // For regular transparent addresses, use the parent implementation
    super.address = addr;
  }
}
