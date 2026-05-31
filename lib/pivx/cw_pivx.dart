part of 'pivx.dart';

class CWPivx extends Pivx {
  @override
  WalletService createPivxWalletService(
      Box<UnspentCoinsInfo> unspentCoinSource, bool isDirect) {
    return PivxWalletService(unspentCoinSource, isDirect);
  }

  @override
  WalletCredentials createPivxNewWalletCredentials({
    required String name,
    WalletInfo? walletInfo,
    String? password,
    String? passphrase,
    String? mnemonic,
  }) =>
      PivxNewWalletCredentials(
        name: name,
        walletInfo: walletInfo,
        password: password,
        passphrase: passphrase,
        mnemonic: mnemonic,
      );

  @override
  WalletCredentials createPivxRestoreWalletFromSeedCredentials({
    required String name,
    required String mnemonic,
    required String password,
    String? passphrase,
  }) =>
      PivxRestoreWalletFromSeedCredentials(
        name: name,
        mnemonic: mnemonic,
        password: password,
        passphrase: passphrase,
      );

  @override
  TransactionPriority deserializePivxTransactionPriority(int raw) =>
      PivxTransactionPriority.deserialize(raw: raw);

  @override
  TransactionPriority getDefaultTransactionPriority() =>
      PivxTransactionPriority.medium;

  @override
  List<TransactionPriority> getTransactionPriorities() =>
      PivxTransactionPriority.all;

  @override
  TransactionPriority getPivxTransactionPrioritySlow() =>
      PivxTransactionPriority.slow;

  @override
  String getShieldedAddress(Object wallet) {
    final pivxWallet = wallet as PivxWallet;
    return pivxWallet.currentShieldedAddress ?? '';
  }

  @override
  bool isSaplingEnabled(Object wallet) {
    final pivxWallet = wallet as PivxWallet;
    return pivxWallet.saplingEnabled;
  }

  @override
  bool isShieldSyncing(Object wallet) {
    final pivxWallet = wallet as PivxWallet;
    return pivxWallet.isShieldSyncing;
  }

  @override
  bool isSaplingRpcAvailable(Object wallet) {
    final pivxWallet = wallet as PivxWallet;
    return pivxWallet.saplingRpcAvailable;
  }

  @override
  int getLastShieldSyncedBlock(Object wallet) {
    final pivxWallet = wallet as PivxWallet;
    return pivxWallet.lastShieldSyncedBlock;
  }

  @override
  String? getLastShieldSyncError(Object wallet) {
    final pivxWallet = wallet as PivxWallet;
    return pivxWallet.lastShieldSyncError;
  }

  @override
  int getShieldedBalance(Object wallet) {
    final pivxWallet = wallet as PivxWallet;
    return pivxWallet.shieldedBalance;
  }

  @override
  Future<String> generateNewShieldedAddress(Object wallet,
      {String? label}) async {
    final pivxWallet = wallet as PivxWallet;
    return await pivxWallet.generateNewShieldedAddress(label: label);
  }

  @override
  List<Map<String, dynamic>> getShieldedAddresses(Object wallet) {
    final pivxWallet = wallet as PivxWallet;
    return pivxWallet.shieldedAddresses
        .map((addr) => {
              'address': addr.address,
              'label': addr.label,
              'diversifierIndex': addr.diversifierIndex,
              'isDefault': addr.isDefault,
            })
        .toList();
  }

  @override
  Future<void> updateShieldedAddressLabel(Object wallet,
      {required String address, required String label}) async {
    final pivxWallet = wallet as PivxWallet;
    await pivxWallet.updateShieldedAddressLabel(address, label);
  }
}
