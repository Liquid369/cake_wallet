import 'package:cw_core/transaction_priority.dart';
import 'package:cw_core/unspent_coins_info.dart';
import 'package:cw_core/wallet_credentials.dart';
import 'package:cw_core/wallet_info.dart';
import 'package:cw_core/wallet_service.dart';
import 'package:hive/hive.dart';

import 'package:cw_pivx/cw_pivx.dart';

part 'cw_pivx.dart';

Pivx? pivx = CWPivx();

abstract class Pivx {

  WalletService createPivxWalletService(Box<UnspentCoinsInfo> unspentCoinSource, bool isDirect);

  WalletCredentials createPivxNewWalletCredentials(
      {required String name, WalletInfo? walletInfo, String? password, String? passphrase, String? mnemonic});

  WalletCredentials createPivxRestoreWalletFromSeedCredentials(
      {required String name, required String mnemonic, required String password, String? passphrase});

  TransactionPriority deserializePivxTransactionPriority(int raw);

  TransactionPriority getDefaultTransactionPriority();

  List<TransactionPriority> getTransactionPriorities();

  TransactionPriority getPivxTransactionPrioritySlow();

  /// Get the shielded (Sapling) address for the wallet.
  /// Returns null if Sapling is not enabled or not yet initialized.
  String? getShieldedAddress(Object wallet);

  /// Check if Sapling shielded transactions are enabled for this wallet.
  bool isSaplingEnabled(Object wallet);

  /// Get the shielded balance in zatoshis.
  int getShieldedBalance(Object wallet);

  /// Generate a new shielded address.
  /// Returns the new address string.
  Future<String> generateNewShieldedAddress(Object wallet, {String? label});

  /// Get all stored shielded addresses as a list of maps.
  /// Each map contains: 'address', 'label', 'diversifierIndex', 'isDefault'.
  List<Map<String, dynamic>> getShieldedAddresses(Object wallet);

  /// Update the label for a shielded address.
  Future<void> updateShieldedAddressLabel(Object wallet, String address, String? label);
}
