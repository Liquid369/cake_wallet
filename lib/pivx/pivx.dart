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
  WalletService createPivxWalletService(
      Box<UnspentCoinsInfo> unspentCoinSource, bool isDirect);

  WalletCredentials createPivxNewWalletCredentials(
      {required String name,
      WalletInfo? walletInfo,
      String? password,
      String? passphrase,
      String? mnemonic});

  WalletCredentials createPivxRestoreWalletFromSeedCredentials(
      {required String name,
      required String mnemonic,
      required String password,
      String? passphrase});

  TransactionPriority deserializePivxTransactionPriority(int raw);

  TransactionPriority getDefaultTransactionPriority();

  List<TransactionPriority> getTransactionPriorities();

  TransactionPriority getPivxTransactionPrioritySlow();

  // Sapling/shielded address methods
  Future<String> generateNewShieldedAddress(Object wallet, {String? label});

  Future<void> updateShieldedAddressLabel(Object wallet,
      {required String address, required String label});

  bool isSaplingEnabled(Object wallet);

  String getShieldedAddress(Object wallet);

  int getShieldedBalance(Object wallet);

  bool isShieldSyncing(Object wallet);

  bool isSaplingRpcAvailable(Object wallet);

  int getLastShieldSyncedBlock(Object wallet);

  String? getLastShieldSyncError(Object wallet);

  List<Map<String, dynamic>> getShieldedAddresses(Object wallet);
}
