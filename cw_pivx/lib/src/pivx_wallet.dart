import 'dart:async';

import 'package:bitcoin_base/bitcoin_base.dart';
import 'package:bech32/bech32.dart';
import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:cw_bitcoin/bitcoin_address_record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cw_bitcoin/bitcoin_mnemonics_bip39.dart';
import 'package:cw_bitcoin/bitcoin_transaction_credentials.dart';
import 'package:cw_bitcoin/bitcoin_unspent.dart';
import 'package:cw_bitcoin/electrum.dart' as electrum;
import 'package:cw_bitcoin/electrum_balance.dart';
import 'package:cw_bitcoin/electrum_transaction_info.dart';
import 'package:cw_bitcoin/electrum_wallet.dart';
import 'package:cw_bitcoin/electrum_wallet_addresses.dart';
import 'package:cw_bitcoin/electrum_wallet_snapshot.dart';
import 'package:cw_core/crypto_currency.dart';
import 'package:cw_core/encryption_file_utils.dart';
import 'package:cw_core/pending_transaction.dart';
import 'package:cw_core/transaction_direction.dart';
import 'package:cw_core/transaction_priority.dart';
import 'package:cw_core/unspent_coin_type.dart';
import 'package:cw_core/unspent_coins_info.dart';
import 'package:cw_core/utils/print_verbose.dart';
import 'package:cw_core/wallet_info.dart';
import 'package:cw_core/wallet_keys_file.dart';
import 'package:cw_core/wallet_type.dart';
import 'package:cw_core/sync_status.dart' as core_sync;
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';
import 'package:mobx/mobx.dart';
import 'package:synchronized/synchronized.dart';

import 'pivx_network.dart';
import 'pivx_wallet_addresses.dart';
import 'pending_pivx_shielded_transaction.dart';
// Import only what we need from sapling modules to avoid conflicts
import 'sapling/sapling_constants.dart';
import 'sapling/sapling_factories.dart';
import 'sapling/sapling_note_storage.dart';

part 'pivx_wallet.g.dart';

const bool _debugClearPendingShieldedSpends =
    bool.fromEnvironment('PIVX_CLEAR_PENDING_SHIELDED_SPENDS');

/// PIVX wallet implementation with full Sapling shielded transaction support.
///
/// Extends ElectrumWallet to provide PIVX-specific functionality while
/// leveraging the existing Bitcoin/Electrum infrastructure.
///
/// ## Features
///
/// ### Transparent Layer (Bitcoin-compatible)
/// - Uses BIP44 coin type 119 (m/44'/119'/account'/change/index)
/// - P2PKH addresses only (starting with 'D')
/// - Different dust threshold based on PIVX Core rules
/// - Coinstake transaction awareness (for proper balance calculation)
///
/// ### Shielded Layer (Sapling Protocol)
/// - Shielded addresses (starting with 'ps' on mainnet)
/// - Private transactions with zero-knowledge proofs
/// - Shield/deshield between transparent and shielded pools
/// - Full note scanning and witness tracking
///
/// ## Balance Types
/// - Transparent balance: Standard UTXO-based balance
/// - Shielded balance: Sum of unspent Sapling notes
/// - Total balance: transparent + shielded
///
/// ## Transaction Types
/// - Transparent-to-transparent (t→t): Standard Bitcoin-style
/// - Transparent-to-shielded (t→z): Shield funds for privacy
/// - Shielded-to-shielded (z→z): Fully private transfer
/// - Shielded-to-transparent (z→t): Deshield funds for spending
class PivxWallet = PivxWalletBase with _$PivxWallet;

abstract class PivxWalletBase extends ElectrumWallet with Store {
  static const int _shieldedRestoreAddressReuseScanLimit = 1000;
  static const int _shieldedBirthdayRewindBlocks = 1440;

  static String sanitizeShieldSyncError(Object error) {
    final text = error.toString().toLowerCase();

    if (text.contains('tree cursor') ||
        text.contains('global output positions')) {
      return 'PIVX Sapling sync requires a Sapling v1 ElectrumX node with global output positions. Switch nodes and retry.';
    }
    if (text.contains('advertises v1') ||
        text.contains('release contract features')) {
      return 'Current PIVX node advertises incomplete Sapling v1 support. Switch to a fully upgraded Sapling v1 node and retry.';
    }
    if (text.contains('incomplete range') ||
        text.contains('partial_index') ||
        text.contains('index_not_ready') ||
        text.contains('backend_timeout')) {
      return 'Current PIVX node did not return a complete Sapling block range yet. Wait for the node to finish indexing and retry.';
    }
    if (text.contains('block scanning') ||
        text.contains('get_block_range') ||
        text.contains('rpc method unavailable')) {
      return 'Current PIVX node does not support Sapling block scanning. Switch to a Sapling-capable node and retry.';
    }
    if (text.contains('network mismatch')) {
      return 'Current PIVX node is on the wrong network for this wallet. Switch nodes and retry.';
    }
    if (text.contains('activation height mismatch')) {
      return 'Current PIVX node reports an unexpected Sapling activation height. Switch nodes and retry.';
    }

    return 'PIVX Sapling sync failed. Check node capability and retry.';
  }

  PivxWalletBase({
    required String mnemonic,
    required String password,
    required WalletInfo walletInfo,
    required DerivationInfo derivationInfo,
    required Box<UnspentCoinsInfo> unspentCoinsInfo,
    required Uint8List seedBytes,
    required EncryptionFileUtils encryptionFileUtils,
    PivxNetwork pivxNetwork = PivxNetwork.mainnet,
    String? passphrase,
    BitcoinAddressType? addressPageType,
    List<BitcoinAddressRecord>? initialAddresses,
    ElectrumBalance? initialBalance,
    Map<String, int>? initialRegularAddressIndex,
    Map<String, int>? initialChangeAddressIndex,
    electrum.ElectrumClient? electrumClient,
  }) : super(
          mnemonic: mnemonic,
          password: password,
          walletInfo: walletInfo,
          derivationInfo: derivationInfo,
          unspentCoinsInfo: unspentCoinsInfo,
          network: pivxNetwork,
          initialAddresses: initialAddresses,
          initialBalance: initialBalance,
          seedBytes: seedBytes,
          currency: CryptoCurrency.pivx,
          encryptionFileUtils: encryptionFileUtils,
          passphrase: passphrase,
          electrumClient: electrumClient,
        ) {
    walletAddresses = PivxWalletAddresses(
      walletInfo,
      initialAddresses: initialAddresses,
      initialRegularAddressIndex: initialRegularAddressIndex,
      initialChangeAddressIndex: initialChangeAddressIndex,
      mainHd: hd,
      sideHd: accountHD.childKey(Bip32KeyIndex(1)),
      network: pivxNetwork,
      initialAddressPageType: addressPageType,
      isHardwareWallet: walletInfo.isHardwareWallet,
    );
    autorun((_) {
      this.walletAddresses.isEnabledAutoGenerateSubaddress =
          this.isEnabledAutoGenerateSubaddress;
    });
  }

  @override
  Future<void> init() async {
    await super.init();
    // Try to initialize Sapling (won't throw if native library is unavailable)
    await tryInitializeSapling();
    _ensureShieldedHeaderSyncSubscription();
  }

  @override
  Future<void> close({bool shouldCleanup = false}) async {
    await _shieldedHeaderSyncSubscription?.cancel();
    _shieldedHeaderSyncSubscription = null;
    await super.close(shouldCleanup: shouldCleanup);
  }

  // ============================================================
  // SAPLING SHIELDED TRANSACTION SUPPORT
  // ============================================================

  /// The Sapling key manager for shielded key derivation.
  /// Initialized lazily when Sapling features are first accessed.
  SaplingKeyManagerWrapper? _saplingKeyManager;

  /// The shield sync engine for note scanning.
  /// Initialized lazily when Sapling sync is started.
  ShieldSyncEngineWrapper? _shieldSyncEngine;
  bool _shieldSyncEngineInitialized = false;

  /// The Sapling transaction builder.
  /// Initialized lazily when building shielded transactions.
  SaplingTransactionBuilderWrapper? _saplingTxBuilder;

  /// Lock for synchronizing balance updates to prevent race conditions.
  final _balanceLock = Lock();

  StreamSubscription<Object>? _shieldedHeaderSyncSubscription;
  DateTime? _lastHeaderTriggeredShieldSync;

  /// Whether Sapling is enabled for this wallet.
  /// Default true for PIVX wallets.
  @observable
  bool saplingEnabled = true;

  /// The shielded balance in zatoshis (1 PIV = 10^8 zatoshis).
  @observable
  int shieldedBalance = 0;

  /// The pending (unconfirmed) shielded balance in zatoshis.
  @observable
  int pendingShieldedBalance = 0;

  /// The last synced block for shield scanning.
  @observable
  int lastShieldSyncedBlock = 0;

  /// Whether shield sync is currently in progress.
  @observable
  bool isShieldSyncing = false;

  /// The current shielded address.
  @observable
  String? currentShieldedAddress;

  /// Whether the active node passed the PIVX Sapling RPC capability probe.
  @observable
  bool saplingRpcAvailable = false;

  /// Sanitized shielded sync error for UI/support state.
  @observable
  String? lastShieldSyncError;

  /// Get the transparent balance in zatoshis.
  int get transparentBalance {
    final electrumBalance = balance[currency];
    return electrumBalance?.confirmed ?? 0;
  }

  /// Get the total balance (transparent + shielded) in zatoshis.
  int get totalBalance => transparentBalance + shieldedBalance;

  /// Get the total balance in PIVX.
  double get totalBalancePivx => totalBalance / 100000000.0;

  /// Get the shielded balance in PIVX.
  double get shieldedBalancePivx => shieldedBalance / 100000000.0;

  /// PIVX supports rescan for both transparent and shielded balances.
  @override
  bool get hasRescan => true;

  /// Rescan both transparent and shielded transactions.
  ///
  /// [height] - The block height to start rescanning from.
  @override
  Future<void> rescan({required int height, bool? doSingleScan}) async {
    syncStatus = core_sync.SyncronizingSyncStatus();

    // First rescan transparent layer
    await super.rescan(height: height, doSingleScan: doSingleScan);

    // Then rescan shielded layer from the specified height
    await rescanShielded(fromHeight: height);

    syncStatus = core_sync.SyncedSyncStatus();
  }

  /// Initialize Sapling support.
  ///
  /// Initializes the key manager and prepares for shielded operations.
  /// Seed bytes are zeroed after use, errors leave wallet in clean state.
  Future<void> initializeSapling() async {
    if (_saplingKeyManager != null) return;

    // Temporary variables for transactional initialization
    SaplingKeyManagerWrapper? tempKeyManager;
    SaplingAddressResult? tempAddress;
    Uint8List? saplingSeeds;

    try {
      // Get the seed bytes from the mnemonic
      final mnemonic = seed;
      if (mnemonic == null) {
        throw StateError('Cannot initialize Sapling without mnemonic seed');
      }
      saplingSeeds = MnemonicBip39.toSeed(mnemonic, passphrase: passphrase);

      // Create and initialize the key manager
      tempKeyManager = await SaplingKeyManagerFactory.create(
        seed: saplingSeeds,
        isTestnet: network == PivxNetwork.testnet,
        accountIndex: 0,
      );
      await tempKeyManager.initialize();

      // Get the default shielded address
      tempAddress = await tempKeyManager.getDefaultAddress();

      // Only commit state if everything succeeded
      _saplingKeyManager = tempKeyManager;
      currentShieldedAddress = tempAddress.encoded;
      saplingEnabled = true;
    } catch (e) {
      // Clean up partial state on error
      if (tempKeyManager != null) {
        try {
          tempKeyManager.dispose();
        } catch (_) {
          // Ignore disposal errors during error handling
        }
      }

      // Sapling not available (native library not loaded or other error)
      saplingEnabled = false;
      rethrow;
    } finally {
      // Zero seed bytes from memory
      if (saplingSeeds != null) {
        saplingSeeds.fillRange(0, saplingSeeds.length, 0);
      }
    }
  }

  /// Try to initialize Sapling support without throwing.
  /// Returns true if Sapling was initialized successfully.
  Future<bool> tryInitializeSapling() async {
    if (_saplingKeyManager != null) return true;
    if (!saplingEnabled) return false;

    try {
      await initializeSapling();

      // Load shielded balance and restore notes from storage
      await _loadShieldedBalanceFromStorage();

      // Also initialize the sync engine and restore notes to native layer
      // This ensures notes are available for spending after app restart
      await _restoreNotesToNativeEngine();

      return true;
    } catch (e) {
      printV('[PIVX] Sapling initialization failed');
      saplingEnabled = false;
      return false;
    }
  }

  /// Restore notes from storage to the native Rust engine.
  /// This is essential after app restart since the Rust SYNC_STATES is empty.
  Future<void> _restoreNotesToNativeEngine() async {
    if (_saplingKeyManager == null) return;

    try {
      // Initialize the sync engine if not already done
      _shieldSyncEngine ??= await ShieldSyncEngineFactory.create(
        keyManager: _saplingKeyManager!,
        walletId: walletInfo.id,
        isTestnet: network == PivxNetwork.testnet,
        electrumClient: electrumClient,
        encryptionFileUtils: encryptionFileUtils,
        password: password,
      );
      if (!_shieldSyncEngineInitialized) {
        await _shieldSyncEngine!.initialize();
        _shieldSyncEngineInitialized = true;
      }
      _restoreCurrentShieldedAddressFromStorage();

      await _debugClearPendingShieldedSpendReservations();

      // Restore notes from storage to native engine
      await _shieldSyncEngine!.restoreNotesFromStorage();
      printV('[PIVX] Restored spendable notes to native engine');
    } catch (e) {
      printV('[PIVX] Failed to restore notes to native engine');
      // Don't fail initialization, notes can be restored during sync
    }
  }

  /// Load the shielded balance from persisted storage.
  /// This is called on wallet initialization to restore the balance
  /// without needing to run a full sync.
  Future<void> _loadShieldedBalanceFromStorage() async {
    try {
      final storage = SaplingNoteStorage(
        walletId: walletInfo.id,
        isTestnet: network == PivxNetwork.testnet,
        encryptionFileUtils: encryptionFileUtils,
        password: password,
      );
      await storage.load();

      final storedBalance = storage.spendableBalanceAt(
        chainHeight: storage.lastSyncedHeight,
      );
      final storedPendingBalance = storage.pendingReceivedBalanceAt(
        chainHeight: storage.lastSyncedHeight,
      );

      shieldedBalance = storedBalance;
      pendingShieldedBalance = storedPendingBalance;
      // Update the balance map directly with shielded balance, including zero,
      // so stale shielded display state cannot survive storage reloads.
      final currentBalance = balance[currency];
      if (currentBalance != null) {
        balance[currency] = ElectrumBalance(
          confirmed: currentBalance.confirmed,
          unconfirmed: currentBalance.unconfirmed,
          frozen: currentBalance.frozen,
          secondConfirmed: storedBalance,
          secondUnconfirmed: storedPendingBalance,
        );
      } else {
        balance[currency] = ElectrumBalance(
          confirmed: 0,
          unconfirmed: 0,
          frozen: 0,
          secondConfirmed: storedBalance,
          secondUnconfirmed: storedPendingBalance,
        );
      }
    } catch (e) {
      printV('[PIVX] Failed to load shielded balance from storage');
    }
  }

  /// Reconcile shielded balance between Dart state and Rust engine.
  ///
  /// The Rust engine is the source of truth for balance.
  ///
  /// Call this after:
  /// - Sync operations complete
  /// - Transaction broadcasting
  /// - Wallet restoration
  /// - Any operation that modifies notes
  ///
  /// Uses a lock to prevent race conditions between concurrent operations.
  Future<void> _reconcileShieldedBalance() async {
    if (_shieldSyncEngine == null) {
      printV('[PIVX] Cannot reconcile balance: Sync engine not initialized');
      return;
    }

    await _balanceLock.synchronized(() async {
      try {
        // Rust engine is source of truth
        final rustBalance = _shieldSyncEngine!.balance;
        final rustPending = _shieldSyncEngine!.pendingBalance;

        // Check if Dart state diverged
        if (shieldedBalance != rustBalance ||
            pendingShieldedBalance != rustPending) {
          printV('[PIVX] Shielded balance reconciled');

          // Update Dart state to match Rust (source of truth)
          shieldedBalance = rustBalance;
          pendingShieldedBalance = rustPending;

          // Note: Balance is computed from notes in storage, not stored separately.
          // The Rust sync engine maintains the authoritative note set.
          // No need to explicitly save balance - it will be recomputed from notes.

          // Trigger UI update to reflect reconciled balance
          await updateBalance();
        }
      } catch (e) {
        printV('[PIVX] Balance reconciliation failed');
        // Don't rethrow - this is a best-effort operation
      }
    });
  }

  Future<void> _refreshShieldedTransactionHistory() async {
    if (_shieldSyncEngine == null) return;

    final storage = _shieldSyncEngine!.storage;
    final currentHeight = storage.lastSyncedHeight;
    final byTxid = <String, List<StoredSaplingNote>>{};
    for (final note in storage.notes) {
      byTxid.putIfAbsent(note.txid, () => <StoredSaplingNote>[]).add(note);
    }

    var changed = false;
    final staleShieldedReceives = transactionHistory.transactions.entries
        .where((entry) =>
            entry.value.additionalInfo['isPivxShielded'] == true &&
            entry.value.additionalInfo['pivxRoute'] == 'z-receive' &&
            !byTxid.containsKey(entry.key))
        .map((entry) => entry.key)
        .toList();
    for (final txid in staleShieldedReceives) {
      transactionHistory.transactions.remove(txid);
      changed = true;
    }

    for (final entry in byTxid.entries) {
      final notes = entry.value;
      final amount = notes.fold<int>(0, (sum, note) => sum + note.value);
      final height =
          notes.map((note) => note.height).reduce((a, b) => a < b ? a : b);
      final confirmations = height > 0 && currentHeight >= height
          ? currentHeight - height + 1
          : 0;
      final existing = transactionHistory.transactions[entry.key];

      if (existing == null) {
        transactionHistory.addOne(ElectrumTransactionInfo(
          WalletType.pivx,
          id: entry.key,
          height: height,
          amount: amount,
          fee: 0,
          direction: TransactionDirection.incoming,
          isPending: confirmations <
              PivxShieldedConfirmationPolicy.receiveConfirmations,
          date: notes
              .map((note) => note.discoveredAt)
              .reduce((a, b) => a.isBefore(b) ? a : b),
          confirmations: confirmations,
          additionalInfo: {
            'isPivxShielded': true,
            'pivxPool': 'shielded',
            'pivxRoute': 'z-receive',
            'pivxRequiredConfirmations':
                PivxShieldedConfirmationPolicy.receiveConfirmations,
          },
        ));
        changed = true;
      } else if (existing.additionalInfo['isPivxShielded'] == true) {
        existing.height = height;
        existing.amount = amount;
        existing.confirmations = confirmations;
        existing.isPending =
            confirmations < PivxShieldedConfirmationPolicy.receiveConfirmations;
        changed = true;
      }
    }

    if (changed) {
      await transactionHistory.save();
    }
  }

  Future<void> _recordPendingShieldedOutgoing({
    required String txid,
    required int amount,
    required int fee,
    required String toAddress,
  }) async {
    transactionHistory.addOne(ElectrumTransactionInfo(
      WalletType.pivx,
      id: txid,
      height: 0,
      amount: amount,
      fee: fee,
      direction: TransactionDirection.outgoing,
      isPending: true,
      date: DateTime.now(),
      confirmations: 0,
      to: toAddress,
      additionalInfo: {
        'isPivxShielded': true,
        'pivxPool': 'shielded',
        'pivxRoute': 'z-to-z',
        'pivxRequiredConfirmations':
            PivxShieldedConfirmationPolicy.receiveConfirmations,
      },
    ));
    await transactionHistory.save();
  }

  Future<void> _ensureShieldSyncEngineInitialized() async {
    await initializeSapling();

    if (_shieldSyncEngine != null) {
      if (!_shieldSyncEngineInitialized) {
        await _shieldSyncEngine!.initialize();
        _shieldSyncEngineInitialized = true;
        await _debugClearPendingShieldedSpendReservations();
      }
      _restoreCurrentShieldedAddressFromStorage();
      return;
    }

    _shieldSyncEngine = await ShieldSyncEngineFactory.create(
      keyManager: _saplingKeyManager!,
      walletId: walletInfo.id,
      isTestnet: network == PivxNetwork.testnet,
      electrumClient: electrumClient,
      encryptionFileUtils: encryptionFileUtils,
      password: password,
    );
    await _shieldSyncEngine!.initialize();
    _shieldSyncEngineInitialized = true;
    _restoreCurrentShieldedAddressFromStorage();
    await _debugClearPendingShieldedSpendReservations();
  }

  void _restoreCurrentShieldedAddressFromStorage() {
    final addresses = _shieldSyncEngine?.storage.addresses;
    if (addresses == null || addresses.isEmpty) return;

    final current = currentShieldedReceiveAddressFromStorage(addresses);
    currentShieldedAddress = current.address;
  }

  @visibleForTesting
  static StoredShieldedAddress currentShieldedReceiveAddressFromStorage(
    List<StoredShieldedAddress> addresses,
  ) {
    if (addresses.isEmpty) {
      throw StateError('No stored PIVX shielded receive addresses');
    }

    return addresses.reduce((a, b) =>
        a.diversifierIndex >= b.diversifierIndex ? a : b);
  }

  Future<void> _debugClearPendingShieldedSpendReservations() async {
    if (!kDebugMode || !_debugClearPendingShieldedSpends) return;
    if (_shieldSyncEngine == null) return;

    final cleared = await _shieldSyncEngine!.storage.clearPendingSpentNotes();
    final staleHistoryTxids = transactionHistory.transactions.entries
        .where((entry) =>
            entry.value.additionalInfo['isPivxShielded'] == true &&
            entry.value.additionalInfo['pivxRoute'] == 'z-to-z' &&
            entry.value.direction == TransactionDirection.outgoing &&
            entry.value.isPending)
        .map((entry) => entry.key)
        .toList(growable: false);

    for (final txid in staleHistoryTxids) {
      transactionHistory.transactions.remove(txid);
    }

    if (staleHistoryTxids.isNotEmpty) {
      await transactionHistory.save();
    }

    printV(
      '[PIVX Sapling] Debug pending shielded spend cleanup: '
      'cleared_value=$cleared stale_history=${staleHistoryTxids.length}',
    );

    if (cleared <= 0 && staleHistoryTxids.isEmpty) return;

    printV('[PIVX Sapling] Debug cleared pending shielded spends');
    await _shieldSyncEngine!.restoreNotesFromStorage();
    await _reconcileShieldedBalance();
  }

  Future<void> _ensureSaplingRpcSupportsShieldedSync() async {
    await _ensureShieldSyncEngineInitialized();
    final capabilities =
        await _shieldSyncEngine!.saplingClient.probeCapabilities();
    if (!capabilities.supportsBlockRange) {
      throw StateError(
          'Current PIVX node does not support Sapling block scanning');
    }
    saplingRpcAvailable = true;
    lastShieldSyncError = null;
  }

  Future<void> _ensureSaplingRpcSupportsShieldedSend() async {
    await _ensureSaplingRpcSupportsShieldedSync();
    final capabilities =
        await _shieldSyncEngine!.saplingClient.probeCapabilities();
    if (!capabilities.supportsBestAnchor || !capabilities.supportsWitness) {
      saplingRpcAvailable = false;
      lastShieldSyncError =
          'Current PIVX node cannot provide Sapling anchors/witnesses for shielded sends.';
      throw StateError(lastShieldSyncError!);
    }
  }

  /// Get a shielded payment address.
  ///
  /// [index] - Diversifier index (default: current address).
  /// Returns the Bech32-encoded shielded address (ps1...).
  Future<String> getShieldedAddress({int? index}) async {
    if (index != null) {
      await initializeSapling();
      final address = await _saplingKeyManager!.deriveAddress(index);
      return address;
    }

    await _ensureShieldSyncEngineInitialized();
    return currentShieldedAddress!;
  }

  /// Get all stored shielded addresses.
  List<StoredShieldedAddress> get shieldedAddresses {
    if (_shieldSyncEngine == null) return [];
    return _shieldSyncEngine!.storage.addresses;
  }

  /// Generate a new shielded address.
  ///
  /// Creates a new diversified payment address for receiving shielded funds.
  /// All addresses are derived from the same viewing key and can receive
  /// funds to the same shielded balance.
  ///
  /// [label] - Optional label for the new address.
  Future<String> generateNewShieldedAddress({String? label}) async {
    await _ensureShieldSyncEngineInitialized();

    // Get next diversifier index
    final index = _shieldSyncEngine!.storage.getAndIncrementDiversifierIndex();

    // Derive the address
    final address = await _saplingKeyManager!.deriveAddress(index);

    // Store the address
    final storedAddress = StoredShieldedAddress(
      diversifierIndex: index,
      address: address,
      label: label,
    );
    await _shieldSyncEngine!.storage.addAddress(storedAddress);

    // Update current address
    currentShieldedAddress = address;

    return address;
  }

  /// Update the label for a shielded address.
  Future<void> updateShieldedAddressLabel(String address, String? label) async {
    if (_shieldSyncEngine != null) {
      await _shieldSyncEngine!.storage.updateAddressLabel(address, label);
    }
  }

  /// Start syncing shielded notes.
  ///
  /// Scans the blockchain for incoming shielded transactions and updates
  /// the shielded balance. This should be called periodically or when
  /// expecting incoming shielded funds.
  ///
  /// [fromHeight] - Start scanning from this block (default: last synced).
  /// [onProgress] - Callback for sync progress updates.
  Future<void> syncShielded({
    int? fromHeight,
    SyncProgressCallback? onProgress,
  }) async {
    if (isShieldSyncing) return;

    await _ensureShieldSyncEngineInitialized();

    // Wait for connection to be stable before syncing
    int retries = 0;
    while (!electrumClient.isConnected && retries < 10) {
      await Future.delayed(const Duration(milliseconds: 500));
      retries++;
    }
    if (!electrumClient.isConnected) {
      printV('[PIVX Sapling] Connection not available, aborting sync');
      return;
    }

    isShieldSyncing = true;

    try {
      await _ensureSaplingRpcSupportsShieldedSync();

      final initialRestoreHeight = await _initialShieldSyncHeight();

      // Start from specified height or last synced height
      await _shieldSyncEngine!.startSync(
        startHeight: fromHeight ?? initialRestoreHeight,
        onProgress: (status) async {
          lastShieldSyncedBlock = status.lastSyncedBlock;

          // Use lock to prevent race conditions
          await _balanceLock.synchronized(() async {
            shieldedBalance =
                _shieldSyncEngine!.balanceAt(status.lastSyncedBlock);
            pendingShieldedBalance =
                _shieldSyncEngine!.pendingBalanceAt(status.lastSyncedBlock);
          });

          // Update wallet syncStatus so UI can display progress
          final shieldProgressStatus = syncStatusForShieldProgress(status);
          if (shieldProgressStatus != null) {
            syncStatus = shieldProgressStatus;
          }

          onProgress?.call(status);
        },
      );

      // Final reconciliation after sync completes
      await _advanceShieldedDiversifierIndexPastObservedNotes();
      await _reconcileShieldedBalance();
      await _refreshShieldedTransactionHistory();
      saplingRpcAvailable = true;
      lastShieldSyncError = null;
    } catch (e) {
      saplingRpcAvailable = false;
      lastShieldSyncError = sanitizeShieldSyncError(e);
      rethrow;
    } finally {
      isShieldSyncing = false;
    }
  }

  void _ensureShieldedHeaderSyncSubscription() {
    if (_shieldedHeaderSyncSubscription != null || !saplingEnabled) {
      return;
    }

    final subject = electrumClient.chainTipSubscribe();
    if (subject == null) {
      return;
    }

    _shieldedHeaderSyncSubscription = subject.listen((event) async {
      final height = _heightFromHeaderEvent(event);
      if (height != null) {
        currentChainTip = height;
      }

      if (!saplingEnabled ||
          _saplingKeyManager == null ||
          _shieldSyncEngine == null ||
          isShieldSyncing) {
        return;
      }
      if (height != null &&
          lastShieldSyncedBlock > 0 &&
          height <= lastShieldSyncedBlock) {
        return;
      }

      final now = DateTime.now();
      if (!shouldRunShieldedHeaderSync(
        lastSyncAt: _lastHeaderTriggeredShieldSync,
        now: now,
      )) {
        return;
      }

      _lastHeaderTriggeredShieldSync = now;
      try {
        printV('[PIVX Sapling] Header-triggered shielded sync');
        await syncShielded();
      } catch (e) {
        printV(
            '[PIVX Sapling] Header-triggered shielded sync failed: ${sanitizeShieldSyncError(e)}');
      }
    });
  }

  @visibleForTesting
  static bool shouldRunShieldedHeaderSync({
    required DateTime? lastSyncAt,
    required DateTime now,
  }) {
    if (lastSyncAt == null) return true;
    return now.difference(lastSyncAt) >=
        const Duration(seconds: PivxNetwork.targetBlockTime);
  }

  static int? _heightFromHeaderEvent(Object? event) {
    if (event is int) return event;
    if (event is num) return event.toInt();
    if (event is Map) {
      return _intFromHeaderField(event['height']) ??
          _intFromHeaderField(event['block_height']);
    }
    return null;
  }

  static int? _intFromHeaderField(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  @visibleForTesting
  static core_sync.SyncStatus? syncStatusForShieldProgress(SyncStatus status) {
    if (status.blocksRemaining > 0 && status.chainTip > 0) {
      final progress = status.lastSyncedBlock / status.chainTip;
      return core_sync.SyncingSyncStatus(status.blocksRemaining, progress);
    }

    if (status.blocksRemaining == 0 && status.progress >= 1.0) {
      return core_sync.SyncedSyncStatus();
    }

    return null;
  }

  Future<int?> _initialShieldSyncHeight() async {
    if (_shieldSyncEngine!.storage.lastSyncedHeight != 0) {
      return null;
    }

    final activationHeight = _shieldSyncEngine!.saplingClient.activationHeight;
    if (walletInfo.restoreHeight > 0) {
      return walletInfo.restoreHeight < activationHeight
          ? activationHeight
          : walletInfo.restoreHeight;
    }

    if (walletInfo.isRecovery) {
      return null;
    }

    try {
      final tip = await electrumClient.getCurrentBlockChainTip();
      if (tip == null || tip <= activationHeight) {
        return null;
      }

      final birthdayHeight = _estimateShieldedBirthdayHeight(
        chainTip: tip,
        activationHeight: activationHeight,
      );
      await walletInfo.updateRestoreHeight(birthdayHeight);
      return birthdayHeight;
    } catch (_) {
      return null;
    }
  }

  int _estimateShieldedBirthdayHeight({
    required int chainTip,
    required int activationHeight,
  }) {
    final createdAt = DateTime.fromMillisecondsSinceEpoch(walletInfo.timestamp);
    final age = DateTime.now().difference(createdAt);
    final ageInBlocks = age.isNegative ? 0 : age.inMinutes;
    final height = chainTip - ageInBlocks - _shieldedBirthdayRewindBlocks;
    if (height < activationHeight) {
      return activationHeight;
    }
    if (height > chainTip) {
      return chainTip;
    }
    return height;
  }

  /// Override startSync to also sync shielded notes.
  @override
  @action
  Future<void> startSync() async {
    // First sync transparent transactions via parent
    await super.startSync();

    // Then sync shielded notes if Sapling is enabled
    if (saplingEnabled && _saplingKeyManager != null) {
      _ensureShieldedHeaderSyncSubscription();
      try {
        await syncShielded();

        // Reconcile balance after sync (this uses the lock internally)
        await _reconcileShieldedBalance();

        // Trigger balance update to propagate to UI
        await updateBalance();
      } catch (e) {
        if (kDebugMode) {
          printV('[PIVX] Shielded sync debug: ${e.runtimeType}: $e');
        }
        printV('[PIVX] Shielded sync failed: ${sanitizeShieldSyncError(e)}');
        // Don't fail the entire sync if shielded sync fails
      }
    }
  }

  /// DEBUG: Fast-forward the shielded sync to a specific height.
  ///
  /// This skips scanning blocks before [targetHeight], useful for testing
  /// when you know a transaction exists at a specific height.
  /// WARNING: This will miss any notes in skipped blocks!
  Future<void> debugFastForwardShieldedSync(int targetHeight) async {
    await _ensureShieldSyncEngineInitialized();

    await _shieldSyncEngine!.storage.setLastSyncedHeight(targetHeight);
  }

  /// Rescan shielded balance from scratch.
  ///
  /// This clears all stored notes and rescans from the specified height
  /// (or Sapling activation height if not specified). Use this if notes
  /// are missing spending data or if the balance seems incorrect.
  ///
  /// [fromHeight] - Block height to start scanning from. If null, uses
  ///                Sapling activation height.
  Future<void> rescanShielded({
    int? fromHeight,
    void Function(SyncStatus)? onProgress,
  }) async {
    await _ensureShieldSyncEngineInitialized();

    // Clear storage and reset sync height
    await _shieldSyncEngine!.storage.clear();

    // Reset native sync engine
    _shieldSyncEngine!.resetNativeEngine();

    // Sync from the specified height (or activation height if not specified)
    await syncShielded(fromHeight: fromHeight, onProgress: onProgress);
  }

  Future<void> _advanceShieldedDiversifierIndexPastObservedNotes() async {
    if (_saplingKeyManager == null || _shieldSyncEngine == null) {
      return;
    }

    final observedAddressHexes = <String>{};
    for (final note in _shieldSyncEngine!.storage.notes) {
      final addressHex = _storedSaplingNoteAddressHex(note);
      if (addressHex != null) {
        observedAddressHexes.add(addressHex);
      }
    }
    if (observedAddressHexes.isEmpty) {
      return;
    }

    final nextIndex = await nextShieldedDiversifierIndexAfterObservedAddresses(
      currentNextDiversifierIndex:
          _shieldSyncEngine!.storage.nextDiversifierIndex,
      observedAddressHexes: observedAddressHexes,
      deriveAddressHex: (index) async {
        final derived = await _saplingKeyManager!.deriveAddress(index);
        return _decodeSaplingPaymentAddressHex(derived);
      },
    );
    await _shieldSyncEngine!.storage
        .advanceNextDiversifierIndexAtLeast(nextIndex);
  }

  @visibleForTesting
  static Future<int> nextShieldedDiversifierIndexAfterObservedAddresses({
    required int currentNextDiversifierIndex,
    required Set<String> observedAddressHexes,
    required Future<String?> Function(int index) deriveAddressHex,
    int scanLimit = _shieldedRestoreAddressReuseScanLimit,
  }) async {
    final remainingObservedHexes =
        observedAddressHexes.map((address) => address.toLowerCase()).toSet();
    if (remainingObservedHexes.isEmpty) {
      return currentNextDiversifierIndex;
    }

    var highestRecoveredIndex = currentNextDiversifierIndex - 1;
    for (var index = 0;
        index < scanLimit && remainingObservedHexes.isNotEmpty;
        index++) {
      final derivedHex = (await deriveAddressHex(index))?.toLowerCase();
      if (derivedHex != null && remainingObservedHexes.remove(derivedHex)) {
        highestRecoveredIndex = index;
      }
    }

    final nextIndex = highestRecoveredIndex + 1;
    return nextIndex > currentNextDiversifierIndex
        ? nextIndex
        : currentNextDiversifierIndex;
  }

  String? _storedSaplingNoteAddressHex(StoredSaplingNote note) {
    final address = note.address;
    if (address != null && _isHexOfLength(address, 86)) {
      return address.toLowerCase();
    }

    final diversifier = note.diversifier;
    final pkD = note.pkD;
    if (_isHexOfLength(diversifier, 22) && _isHexOfLength(pkD, 64)) {
      return '${diversifier!.toLowerCase()}${pkD!.toLowerCase()}';
    }

    return null;
  }

  bool _isHexOfLength(String? value, int length) {
    if (value == null || value.length != length) {
      return false;
    }
    return RegExp(r'^[0-9a-fA-F]+$').hasMatch(value);
  }

  String? _decodeSaplingPaymentAddressHex(String encodedAddress) {
    try {
      final decoded =
          const Bech32Codec().decode(encodedAddress, encodedAddress.length);
      final expectedHrp = network == PivxNetwork.testnet
          ? PivxSaplingNetwork.testnetPaymentAddressHrp
          : PivxSaplingNetwork.mainnetPaymentAddressHrp;
      if (decoded.hrp != expectedHrp) {
        return null;
      }

      final bytes = _convertBits(decoded.data, 5, 8, false);
      if (bytes.length != kSaplingPaymentAddressSize) {
        return null;
      }
      return hex.encode(bytes);
    } catch (_) {
      return null;
    }
  }

  List<int> _convertBits(List<int> data, int inBits, int outBits, bool pad) {
    var value = 0;
    var bits = 0;
    final maxV = (1 << outBits) - 1;
    final result = <int>[];

    for (final dataValue in data) {
      if (dataValue < 0 || dataValue >> inBits != 0) {
        throw ArgumentError('Invalid Bech32 data value');
      }

      value = (value << inBits) | dataValue;
      bits += inBits;

      while (bits >= outBits) {
        bits -= outBits;
        result.add((value >> bits) & maxV);
      }
    }

    if (pad) {
      if (bits > 0) {
        result.add((value << (outBits - bits)) & maxV);
      }
    } else if (bits >= inBits || ((value << (outBits - bits)) & maxV) != 0) {
      throw ArgumentError('Invalid Bech32 padding');
    }

    return result;
  }

  /// Create a shielded transaction.
  ///
  /// [toAddress] - Destination address (shielded or transparent).
  /// [amount] - Amount to send in zatoshis.
  /// [memo] - Optional memo (up to 512 bytes, only for shielded outputs).
  /// [useShieldedInputs] - Use shielded notes as inputs (default: true).
  ///
  /// Returns the signed transaction ready for broadcast.
  Future<SaplingTransactionResult> createShieldedTransaction({
    required String toAddress,
    required int amount,
    String? memo,
    bool useShieldedInputs = true,
    bool spendAllShieldedInputs = false,
  }) async {
    await _ensureShieldSyncEngineInitialized();
    await _ensureSaplingRpcSupportsShieldedSend();

    // CRITICAL: Transaction creation must be protected by _balanceLock to prevent race conditions.
    // If two transactions are created simultaneously, they could:
    // 1. Select the same notes as inputs (double-spend)
    // 2. Read inconsistent balance state
    // 3. Create invalid transactions that will be rejected by the network
    return await _balanceLock.synchronized(() async {
      if (_saplingTxBuilder == null) {
        _saplingTxBuilder = await SaplingTransactionBuilderFactory.create(
          keyManager: _saplingKeyManager!,
          syncEngine: _shieldSyncEngine!,
          isTestnet: network == PivxNetwork.testnet,
        );
      }

      // Ensure proving params are loaded before building transaction
      await _ensureProvingParamsLoaded();

      final options = SaplingTransactionOptions(
        toAddress: toAddress,
        amount: amount,
        memo: memo,
        useShieldedInputs: useShieldedInputs,
        spendAllShieldedInputs: spendAllShieldedInputs,
      );

      return await _saplingTxBuilder!.buildTransaction(options: options);
    });
  }

  /// Shield transparent funds.
  ///
  /// Moves funds from the transparent pool to the shielded pool.
  /// This converts UTXOs into shielded notes for privacy.
  ///
  /// [amount] - Amount to shield in zatoshis (null for all available).
  ///
  Future<SaplingTransactionResult> shieldFunds({int? amount}) async {
    await initializeSapling();
    final destination =
        (await _saplingKeyManager!.getDefaultAddress()).encoded;
    final built = await _buildShieldTransactionResult(
      toAddress: destination,
      requestedAmount: amount,
      isSendAll: amount == null,
    );
    return built.result;
  }

  /// Build a t-to-z (shield) transaction spending transparent P2PKH UTXOs
  /// into a Sapling output, with transparent change.
  Future<_BuiltShieldTransaction> _buildShieldTransactionResult({
    required String toAddress,
    int? requestedAmount,
    required bool isSendAll,
    String? memo,
  }) async {
    await initializeSapling();
    await _ensureShieldSyncEngineInitialized();

    // Confirmed, spendable, standard P2PKH transparent UTXOs only.
    final available = unspentCoins
        .where((utx) =>
            utx.isSending &&
            !utx.isFrozen &&
            (utx.confirmations ?? 0) > 0 &&
            PivxNetwork.p2pkhScriptPubKeyHex(utx.bitcoinAddressRecord.address)
                .isNotEmpty)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (available.isEmpty) {
      throw Exception('No spendable transparent PIVX coins available.');
    }

    List<BitcoinUnspent> selected;
    int amount;
    ShieldedSpendPlan plan;
    if (isSendAll) {
      selected = available;
      final total = selected.fold<int>(0, (sum, utx) => sum + utx.value);
      final fee = PivxFeePolicy.saplingFee(
        saplingOutputs: 1,
        transparentInputs: selected.length,
      );
      amount = total - fee;
      if (amount < PivxFeePolicy.shieldedDustThreshold) {
        throw Exception('Insufficient transparent balance after PIVX fee.');
      }
      plan = ShieldedSpendPlan(fee: fee, change: 0, canBuild: true);
    } else {
      amount = requestedAmount!;
      if (amount < PivxFeePolicy.shieldedDustThreshold) {
        throw Exception('Amount below PIVX shielded dust threshold');
      }
      selected = <BitcoinUnspent>[];
      var total = 0;
      plan = ShieldedSpendPlan(fee: 0, change: 0, canBuild: false);
      for (final utx in available) {
        selected.add(utx);
        total += utx.value;
        plan = SaplingTransactionBuilderWrapper.planShieldSpend(
          totalInput: total,
          amount: amount,
          transparentInputs: selected.length,
        );
        if (plan.canBuild) break;
      }
      if (!plan.canBuild) {
        throw Exception('Insufficient transparent balance for shield amount.');
      }
    }

    final utxoMaps = selected.map((utx) {
      final record = utx.bitcoinAddressRecord;
      final chain = record.isHidden ? sideHd : hd;
      final privateKey =
          ECPrivate(chain.childKey(Bip32KeyIndex(record.index)).privateKey)
              .toHex();
      final scriptPubKey =
          PivxNetwork.p2pkhScriptPubKeyHex(record.address);
      return <String, dynamic>{
        'txid': utx.hash,
        'vout': utx.vout,
        'value': utx.value,
        'script_pubkey': scriptPubKey,
        'private_key': privateKey,
      };
    }).toList(growable: false);

    final changeAddress = plan.change > 0 ? walletAddresses.address : null;

    final result = await _balanceLock.synchronized(() async {
      _saplingTxBuilder ??= await SaplingTransactionBuilderFactory.create(
        keyManager: _saplingKeyManager!,
        syncEngine: _shieldSyncEngine!,
        isTestnet: network == PivxNetwork.testnet,
      );
      await _ensureProvingParamsLoaded();
      return await _saplingTxBuilder!.buildShieldTransaction(
        utxos: utxoMaps,
        toAddress: toAddress,
        amount: amount,
        memo: memo,
        fee: plan.fee,
        changeAddress: changeAddress,
        change: plan.change,
      );
    });

    return _BuiltShieldTransaction(
      result: result,
      amount: amount,
      fee: result.fee,
    );
  }

  /// Deshield funds.
  ///
  /// Moves funds from the shielded pool to the transparent pool.
  /// This converts shielded notes back to transparent UTXOs.
  ///
  /// [amount] - Amount to deshield in zatoshis.
  /// [toAddress] - Destination transparent address (default: own address).
  Future<SaplingTransactionResult> deshieldFunds({
    required int amount,
    String? toAddress,
  }) async {
    final destination = toAddress ?? walletAddresses.address;
    if (_isShieldedAddress(destination)) {
      throw Exception('Deshield destination must be a transparent address.');
    }
    return await createShieldedTransaction(
      toAddress: destination,
      amount: amount,
      useShieldedInputs: true,
    );
  }

  /// Ensures that the Sapling proving parameters are downloaded and loaded.
  ///
  /// The proving parameters are large files (~51MB total) required for
  /// generating Groth16 zero-knowledge proofs for shielded transactions.
  Future<void> _ensureProvingParamsLoaded() async {
    if (_saplingTxBuilder == null) {
      throw StateError('Transaction builder not initialized');
    }

    if (_saplingTxBuilder!.hasProvingParams) {
      return; // Already loaded
    }

    final appDir = await getApplicationDocumentsDirectory();
    final provingParamsPath = '${appDir.path}/pivx_sapling_params';

    // Check if we need to download params
    if (!await _saplingTxBuilder!.hasLocalProvingParams(provingParamsPath)) {
      printV('Downloading PIVX Sapling proving parameters (~51MB)...');
      await _saplingTxBuilder!.downloadProvingParams(
        path: provingParamsPath,
        onProgress: (progress) {
          printV(
              'Proving params download: ${(progress * 100).toStringAsFixed(1)}%');
        },
      );
      printV('Proving parameters downloaded successfully.');
    }

    // Load the proving params
    printV('Loading PIVX Sapling proving parameters...');
    await _saplingTxBuilder!.loadProvingParams(path: provingParamsPath);
    printV('Proving parameters loaded successfully.');
  }

  /// Check if an address is a valid PIVX shielded address.
  bool isValidShieldedAddress(String address) {
    final isTestnet = network == PivxNetwork.testnet;
    if (isTestnet) {
      return address.startsWith(PivxSaplingNetwork.testnetPaymentAddressHrp);
    }
    return address.startsWith(PivxSaplingNetwork.mainnetPaymentAddressHrp);
  }

  // ============================================================
  // END SAPLING SUPPORT
  // ============================================================

  /// Override fetchBalances to avoid SegWit address type checks.
  /// PIVX doesn't support SegWit or MWEB, so we skip those checks entirely.
  /// Uses custom scripthash computation for PIVX P2PKH addresses.
  @override
  Future<ElectrumBalance> fetchBalances() async {
    final addresses = walletAddresses.allAddresses
        .where((address) => address.address.isNotEmpty)
        .toList();

    final balanceFutures = <Future<Map<String, dynamic>>>[];
    final validAddresses = <BaseBitcoinAddressRecord>[];

    for (var i = 0; i < addresses.length; i++) {
      final addressRecord = addresses[i];
      // Use custom PIVX scripthash computation to avoid SegWit exceptions
      final sh = PivxNetwork.computeScriptHash(addressRecord.address);
      if (sh.isEmpty) continue;
      validAddresses.add(addressRecord);
      final balanceFuture = electrumClient.getBalance(sh);
      balanceFutures.add(balanceFuture);
    }

    var totalFrozen = 0;
    var totalConfirmed = 0;
    var totalUnconfirmed = 0;

    unspentCoinsInfo.values.forEach((info) {
      unspentCoins.forEach((element) {
        if (element.hash == info.hash &&
            element.vout == info.vout &&
            element.bitcoinAddressRecord.address == info.address &&
            element.value == info.value) {
          if (info.isFrozen) {
            totalFrozen += element.value;
          }
        }
      });
    });

    final balances = await Future.wait(balanceFutures);

    if (balances.any((balance) =>
        balance['confirmed'] == null || balance['unconfirmed'] == null)) {
      printV('[PIVX] Got malformed transparent balance response from server');
      syncStatus = core_sync.LostConnectionSyncStatus();
      final previousBalance = balance[currency];

      return ElectrumBalance(
        confirmed: previousBalance?.confirmed ?? 0,
        unconfirmed: previousBalance?.unconfirmed ?? 0,
        frozen: previousBalance?.frozen ?? 0,
        secondConfirmed: shieldedBalance,
        secondUnconfirmed: pendingShieldedBalance,
      );
    }

    for (var i = 0; i < balances.length; i++) {
      final balance = balances[i];
      final confirmed = balance['confirmed'] as int? ?? 0;
      final unconfirmed = balance['unconfirmed'] as int? ?? 0;
      totalConfirmed += confirmed;
      totalUnconfirmed += unconfirmed;

      // Update address record balance
      if (i < validAddresses.length) {
        final addressRecord = validAddresses[i];
        addressRecord.balance = confirmed + unconfirmed;
        if (confirmed > 0 || unconfirmed > 0) {
          addressRecord.setAsUsed();
        }
      }
    }

    // Return balance with shielded amounts as secondary balance
    // Main balance = transparent only
    // Secondary balance = shielded (shown separately in UI)
    return ElectrumBalance(
      confirmed: totalConfirmed,
      unconfirmed: totalUnconfirmed,
      frozen: totalFrozen,
      secondConfirmed: shieldedBalance,
      secondUnconfirmed: pendingShieldedBalance,
    );
  }

  /// Override checkNodeHealth to avoid SegWit address type checks.
  /// Uses custom scripthash computation for PIVX P2PKH addresses.
  @override
  Future<bool> checkNodeHealth() async {
    try {
      final addresses = walletAddresses.allAddresses
          .where((address) => address.address.isNotEmpty)
          .toList();

      if (addresses.isEmpty) {
        return false;
      }

      final firstAddress = addresses.first;
      // Use custom PIVX scripthash computation
      final sh = PivxNetwork.computeScriptHash(firstAddress.address);
      if (sh.isEmpty) return false;

      await electrumClient.getBalance(sh, throwOnError: true);
      if (saplingEnabled) {
        await _ensureSaplingRpcSupportsShieldedSync();
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Override fetchUnspent to use custom PIVX scripthash computation.
  @override
  Future<List<BitcoinUnspent>?> fetchUnspent(
      BitcoinAddressRecord address) async {
    List<BitcoinUnspent> updatedUnspentCoins = [];

    // Use custom PIVX scripthash computation
    final sh = PivxNetwork.computeScriptHash(address.address);
    if (sh.isEmpty) return [];

    final unspents = await electrumClient.getListUnspent(sh);

    // Failed to fetch unspents
    if (unspents == null) return null;

    await Future.wait(unspents.map((unspent) async {
      try {
        final coin = BitcoinUnspent.fromJSON(address, unspent);
        final tx = await fetchTransactionInfo(hash: coin.hash);
        coin.isChange = address.isHidden;
        coin.confirmations = tx?.confirmations;

        updatedUnspentCoins.add(coin);
      } catch (_) {}
    }));

    return updatedUnspentCoins;
  }

  /// Override fetchTransactionsForAddressType to use custom PIVX scripthash.
  /// This is needed because the parent's _fetchAddressHistory method uses
  /// getScriptHash(network) which fails for PIVX addresses.
  @override
  Future<void> fetchTransactionsForAddressType(
    Map<String, ElectrumTransactionInfo> historiesWithDetails,
    BitcoinAddressType type,
  ) async {
    final addressesByType =
        walletAddresses.allAddresses.where((addr) => addr.type == type);
    final hiddenAddresses =
        addressesByType.where((addr) => addr.isHidden == true);
    final receiveAddresses =
        addressesByType.where((addr) => addr.isHidden == false);
    walletAddresses.hiddenAddresses
        .addAll(hiddenAddresses.map((e) => e.address));
    await walletAddresses.saveAddressesInBox();
    await Future.wait(addressesByType.map((addressRecord) async {
      final history = await _fetchPivxAddressHistory(
          addressRecord, await getCurrentChainTip());

      if (history.isNotEmpty) {
        addressRecord.txCount = history.length;
        historiesWithDetails.addAll(history);

        final matchedAddresses =
            addressRecord.isHidden ? hiddenAddresses : receiveAddresses;
        final isUsedAddressUnderGap = matchedAddresses
                .toList()
                .indexOf(addressRecord) >=
            matchedAddresses.length -
                (addressRecord.isHidden
                    ? ElectrumWalletAddressesBase.defaultChangeAddressesCount
                    : ElectrumWalletAddressesBase.defaultReceiveAddressesCount);

        if (isUsedAddressUnderGap) {
          final prevLength = walletAddresses.allAddresses.length;

          // Discover new addresses for the same address type until the gap limit is respected
          await walletAddresses.discoverAddresses(
            matchedAddresses.toList(),
            addressRecord.isHidden,
            (address) async {
              await subscribeForUpdates();
              return _fetchPivxAddressHistory(
                      address, await getCurrentChainTip())
                  .then(
                      (history) => history.isNotEmpty ? address.address : null);
            },
            type: type,
          );

          final newLength = walletAddresses.allAddresses.length;

          if (newLength > prevLength) {
            await fetchTransactionsForAddressType(historiesWithDetails, type);
          }
        }
      }
    }));
  }

  /// Custom address history fetching for PIVX using our scripthash computation.
  Future<Map<String, ElectrumTransactionInfo>> _fetchPivxAddressHistory(
      BitcoinAddressRecord addressRecord, int? currentHeight) async {
    String txid = "";

    try {
      final Map<String, ElectrumTransactionInfo> historiesWithDetails = {};

      // Use custom PIVX scripthash computation
      final sh = PivxNetwork.computeScriptHash(addressRecord.address);
      if (sh.isEmpty) return {};

      final history = await electrumClient.getHistory(sh);

      if (history.isNotEmpty) {
        addressRecord.setAsUsed();
        walletAddresses.clearLockIfMatches(
            addressRecord.type, addressRecord.address);

        await Future.wait(history.map((transaction) async {
          txid = transaction['tx_hash'] as String;
          final height = transaction['height'] as int;
          final storedTx = transactionHistory.transactions[txid];

          if (storedTx != null) {
            if (height > 0) {
              storedTx.height = height;
              // the tx's block itself is the first confirmation so add 1
              if ((currentHeight ?? 0) > 0) {
                storedTx.confirmations = currentHeight! - height + 1;
              }
              storedTx.isPending = storedTx.confirmations == 0;
            }

            historiesWithDetails[txid] = storedTx;
          } else {
            final tx = await fetchTransactionInfo(
                hash: txid, height: height, retryOnFailure: true);

            if (tx != null) {
              historiesWithDetails[txid] = tx;
              transactionHistory.addOne(tx);
              await transactionHistory.save();
            }
          }

          return Future.value(null);
        }));
      }

      return historiesWithDetails;
    } catch (e) {
      printV('PIVX: Error fetching transparent address history');
      return {};
    }
  }

  /// PIVX transparent dust threshold based on PIVX Core dustRelayFee
  /// of 30,000 zatoshis/kB and a typical 182-byte output spend cost.
  @override
  int get networkDustAmount => PivxFeePolicy.transparentDustThreshold;

  /// Estimate PIVX transaction size.
  /// Similar to Bitcoin P2PKH transactions:
  /// - Each input: ~148 bytes
  /// - Each output: ~34 bytes
  /// - Fixed overhead: ~10 bytes
  static int estimatedPivxTransactionSize(int inputsCount, int outputsCounts) =>
      PivxFeePolicy.transparentTxSize(inputsCount, outputsCounts);

  @override
  int feeAmountForPriority(
    TransactionPriority priority,
    int inputsCount,
    int outputsCount, {
    int? size,
  }) =>
      feeRate(priority) *
      (size ?? estimatedPivxTransactionSize(inputsCount, outputsCount)) ~/
      1000;

  @override
  int feeAmountWithFeeRate(int feeRate, int inputsCount, int outputsCount,
          {int? size}) =>
      feeRate *
      (size ?? estimatedPivxTransactionSize(inputsCount, outputsCount)) ~/
      1000;

  /// Create a new PIVX wallet.
  static Future<PivxWallet> create({
    required String mnemonic,
    required String password,
    required WalletInfo walletInfo,
    required DerivationInfo derivationInfo,
    required Box<UnspentCoinsInfo> unspentCoinsInfo,
    required EncryptionFileUtils encryptionFileUtils,
    bool isTestnet = false,
    String? passphrase,
    String? addressPageType,
    List<BitcoinAddressRecord>? initialAddresses,
    ElectrumBalance? initialBalance,
    Map<String, int>? initialRegularAddressIndex,
    Map<String, int>? initialChangeAddressIndex,
  }) async {
    return PivxWallet(
      mnemonic: mnemonic,
      password: password,
      walletInfo: walletInfo,
      derivationInfo: derivationInfo,
      unspentCoinsInfo: unspentCoinsInfo,
      initialAddresses: initialAddresses,
      initialBalance: initialBalance,
      seedBytes: MnemonicBip39.toSeed(mnemonic, passphrase: passphrase),
      encryptionFileUtils: encryptionFileUtils,
      pivxNetwork: isTestnet ? PivxNetwork.testnet : PivxNetwork.mainnet,
      initialRegularAddressIndex: initialRegularAddressIndex,
      initialChangeAddressIndex: initialChangeAddressIndex,
      addressPageType: P2pkhAddressType.p2pkh,
      passphrase: passphrase,
    );
  }

  /// Open an existing PIVX wallet.
  static Future<PivxWallet> open({
    required String name,
    required WalletInfo walletInfo,
    required Box<UnspentCoinsInfo> unspentCoinsInfo,
    required String password,
    required EncryptionFileUtils encryptionFileUtils,
    bool? isTestnet,
  }) async {
    final pivxNetwork = (isTestnet ?? walletInfo.network == 'testnet')
        ? PivxNetwork.testnet
        : PivxNetwork.mainnet;

    final hasKeysFile = await WalletKeysFile.hasKeysFile(name, walletInfo.type);

    ElectrumWalletSnapshot? snp = null;

    try {
      snp = await ElectrumWalletSnapshot.load(
        encryptionFileUtils,
        name,
        walletInfo.type,
        password,
        pivxNetwork,
      );
    } catch (e) {
      if (!hasKeysFile) rethrow;
    }

    final WalletKeysData keysData;
    // Migrate wallet from the old scheme to the new .keys file scheme
    if (!hasKeysFile) {
      keysData = WalletKeysData(
        mnemonic: snp!.mnemonic,
        xPub: snp.xpub,
        passphrase: snp.passphrase,
      );
    } else {
      keysData = await WalletKeysFile.readKeysFile(
        name,
        walletInfo.type,
        password,
        encryptionFileUtils,
      );
    }

    return PivxWallet(
      mnemonic: keysData.mnemonic!,
      password: password,
      walletInfo: walletInfo,
      derivationInfo: await walletInfo.getDerivationInfo(),
      unspentCoinsInfo: unspentCoinsInfo,
      initialAddresses: snp?.addresses,
      initialBalance: snp?.balance,
      seedBytes: await MnemonicBip39.toSeed(keysData.mnemonic!,
          passphrase: keysData.passphrase),
      encryptionFileUtils: encryptionFileUtils,
      pivxNetwork: pivxNetwork,
      initialRegularAddressIndex: snp?.regularAddressIndex,
      initialChangeAddressIndex: snp?.changeAddressIndex,
      addressPageType: P2pkhAddressType.p2pkh,
      passphrase: keysData.passphrase,
    );
  }

  @override
  Future<String> signMessage(String message, {String? address = null}) async {
    int? index;
    try {
      index = address != null
          ? walletAddresses.allAddresses
              .firstWhere((element) => element.address == address)
              .index
          : null;
    } catch (_) {}
    final HD = index == null ? hd : hd.childKey(Bip32KeyIndex(index));
    final priv = ECPrivate.fromWif(
      WifEncoder.encode(HD.privateKey.raw, netVer: network.wifNetVer),
      netVersion: network.wifNetVer,
    );
    return priv.signMessage(StringUtils.encode(message));
  }

  // ============================================================
  // TRANSACTION CREATION WITH SHIELDED ADDRESS DETECTION
  // ============================================================

  /// Helper to detect if an address is a PIVX shielded (Sapling) address.
  /// Shielded addresses start with 'ps1' on mainnet or 'ptestsapling1' on testnet.
  bool _isShieldedAddress(String address) {
    final addr = address.toLowerCase().trim();
    return addr.startsWith('ps1') || addr.startsWith('ptestsapling1');
  }

  /// Override createTransaction to detect shielded addresses and route appropriately.
  ///
  /// If the destination is a shielded address (ps1...), this will use the Sapling
  /// transaction builder instead of the standard Bitcoin transaction builder.
  @override
  Future<PendingTransaction> createTransaction(Object credentials) async {
    final transactionCredentials = credentials as BitcoinTransactionCredentials;
    final spendFromShielded =
        transactionCredentials.coinTypeToSpendFrom == UnspentCoinType.sapling;

    // Check if any output is a shielded address
    var hasShieldedOutput = false;
    var hasTransparentOutput = false;
    for (final out in transactionCredentials.outputs) {
      final address = out.isParsedAddress ? out.extractedAddress! : out.address;

      if (_isShieldedAddress(address)) {
        hasShieldedOutput = true;
      } else {
        hasTransparentOutput = true;
      }
    }

    if (hasShieldedOutput && hasTransparentOutput) {
      throw Exception(
          'PIVX mixed transparent and shielded outputs are not supported yet.');
    }

    if (spendFromShielded && hasTransparentOutput) {
      // z-to-t (deshield): spend shielded notes into a transparent payment
      // output with shielded change, built by the Sapling builder.
      return await _createShieldedPendingTransaction(transactionCredentials);
    }

    if (hasShieldedOutput) {
      if (transactionCredentials.coinTypeToSpendFrom == UnspentCoinType.any) {
        throw Exception(
            'Select a PIVX transparent or shielded source before sending to a shielded address.');
      }
      return await _createShieldedPendingTransaction(transactionCredentials);
    }

    // Standard transparent transaction - use parent implementation
    return await super.createTransaction(credentials);
  }

  /// Create a pending transaction spending shielded notes.
  ///
  /// Supports the z-to-z route (shielded destination) and the z-to-t
  /// deshield route (transparent destination with shielded change).
  /// Transparent-to-shielded routes must fail before construction until the
  /// builder is implemented and verified.
  Future<PendingTransaction> _createShieldedPendingTransaction(
    BitcoinTransactionCredentials credentials,
  ) async {
    // For now, only support single output shielded transactions
    if (credentials.outputs.length != 1) {
      throw Exception(
          'Shielded transactions currently support only single outputs');
    }

    final output = credentials.outputs.first;
    final toAddress =
        output.isParsedAddress ? output.extractedAddress! : output.address;
    final memo = output.memo;
    final isSendAll = output.sendAll;
    final transparentDestination = !_isShieldedAddress(toAddress);

    final coinType = credentials.coinTypeToSpendFrom;
    if (coinType != UnspentCoinType.sapling) {
      // t-to-z (shield): spend transparent UTXOs into the Sapling output.
      final built = await _buildShieldTransactionResult(
        toAddress: toAddress,
        requestedAmount: isSendAll ? null : output.formattedCryptoAmount!,
        isSendAll: isSendAll,
        memo: memo,
      );
      return PendingPivxShieldedTransaction(
        result: built.result,
        electrumClient: electrumClient,
        amount: built.amount,
        fee: built.fee,
        onCommit: (tx) async {
          try {
            await updateAllUnspents();
            await updateBalance();
          } catch (_) {}
          try {
            await syncShielded();
          } catch (e) {
            printV(
                '[PIVX Sapling] Shielded post-broadcast sync failed: ${sanitizeShieldSyncError(e)}');
          }
        },
      );
    }

    // Initialize sapling to get accurate balances
    await initializeSapling();
    await _ensureShieldSyncEngineInitialized();

    final amount = isSendAll
        ? _shieldedSendAllAmount(transparentDestination: transparentDestination)
        : output.formattedCryptoAmount!;

    // Check if we have sufficient shielded balance
    final hasShieldedFunds = shieldedBalance >= amount;

    if (hasShieldedFunds) {
      // Shielded-to-shielded transaction
      final result = await createShieldedTransaction(
        toAddress: toAddress,
        amount: amount,
        memo: memo,
        useShieldedInputs: true,
        spendAllShieldedInputs: isSendAll,
      );

      return PendingPivxShieldedTransaction(
        result: result,
        electrumClient: electrumClient,
        amount: amount,
        fee: result.fee,
        onCommit: (tx) async {
          await _recordPendingShieldedOutgoing(
            txid: result.txId,
            amount: amount,
            fee: result.fee,
            toAddress: toAddress,
          );

          if (result.spentNullifiers.isNotEmpty) {
            await _shieldSyncEngine!.storage.markPendingSpentByNullifiers(
              result.spentNullifiers,
              result.txId,
            );
            await _reconcileShieldedBalance();
          } else {
            await updateBalance();
          }

          try {
            await syncShielded();
          } catch (e) {
            printV(
                '[PIVX Sapling] Shielded post-broadcast sync failed: ${sanitizeShieldSyncError(e)}');
          }
        },
      );
    }

    throw Exception('Insufficient shielded balance.');
  }

  int _shieldedSendAllAmount({bool transparentDestination = false}) {
    final notes = _shieldSyncEngine!.storage.spendableNotesAt(
      chainHeight: _shieldSyncEngine!.storage.lastSyncedHeight,
    );
    if (notes.isEmpty) {
      throw Exception('No spendable shielded notes available.');
    }

    final total = notes.fold<int>(0, (sum, note) => sum + note.value);
    final fee = PivxFeePolicy.saplingFee(
      saplingInputs: notes.length,
      saplingOutputs: transparentDestination ? 0 : 1,
      transparentOutputs: transparentDestination ? 1 : 0,
    );
    final amount = total - fee;
    final dustFloor = transparentDestination
        ? PivxFeePolicy.transparentDustThreshold
        : PivxFeePolicy.shieldedDustThreshold;
    if (amount < dustFloor) {
      throw Exception('Insufficient shielded balance after PIVX fee.');
    }

    return amount;
  }

  /// Check if a transaction is a coinstake transaction.
  ///
  /// PIVX Coinstake transaction identification (from primitives/transaction.cpp):
  /// - vin is not empty
  /// - First vin prevout is not null (unless zerocoin spend)
  /// - First vout is empty (marker for coinstake)
  /// - At least 2 outputs
  ///
  /// This is important for proper balance calculation as coinstake outputs
  /// have different maturity rules than regular transactions.
  static bool isCoinstakeTransaction(Map<String, dynamic> tx) {
    final vins = tx['vin'] as List?;
    final vouts = tx['vout'] as List?;

    if (vins == null || vins.isEmpty) return false;
    if (vouts == null || vouts.length < 2) return false;

    // Check if first vin is not a coinbase (has previous outpoint)
    final firstVin = vins.first as Map<String, dynamic>?;
    if (firstVin == null) return false;
    final txid = firstVin['txid'];
    if (txid == null || txid == '') return false;

    // Check if first vout is empty (value = 0, no script)
    final firstVout = vouts.first as Map<String, dynamic>?;
    if (firstVout == null) return false;
    final value = firstVout['value'];
    if (value != 0 && value != 0.0) return false;

    return true;
  }

  /// Check if a transaction is a coinbase transaction.
  ///
  /// Coinbase transaction identification:
  /// - Single vin with null prevout (coinbase input)
  /// - Not a zerocoin spend
  static bool isCoinbaseTransaction(Map<String, dynamic> tx) {
    final vins = tx['vin'] as List?;
    if (vins == null || vins.length != 1) return false;

    final firstVin = vins.first as Map<String, dynamic>?;
    if (firstVin == null) return false;

    // Coinbase has no previous transaction
    final coinbase = firstVin['coinbase'];
    return coinbase != null;
  }
}

/// Built t-to-z shield transaction with its planned amount and fee.
class _BuiltShieldTransaction {
  _BuiltShieldTransaction({
    required this.result,
    required this.amount,
    required this.fee,
  });

  final SaplingTransactionResult result;
  final int amount;
  final int fee;
}
