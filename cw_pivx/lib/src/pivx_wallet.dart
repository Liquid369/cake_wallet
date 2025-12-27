import 'package:bitcoin_base/bitcoin_base.dart';
import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:cw_bitcoin/bitcoin_address_record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cw_bitcoin/bitcoin_mnemonics_bip39.dart';
import 'package:cw_bitcoin/bitcoin_transaction_credentials.dart';
import 'package:cw_bitcoin/bitcoin_unspent.dart';
import 'package:cw_bitcoin/electrum_balance.dart';
import 'package:cw_bitcoin/electrum_transaction_info.dart';
import 'package:cw_bitcoin/electrum_wallet.dart';
import 'package:cw_bitcoin/electrum_wallet_addresses.dart';
import 'package:cw_bitcoin/electrum_wallet_snapshot.dart';
import 'package:cw_bitcoin/utils.dart' show generateECPrivate;
import 'package:cw_core/crypto_currency.dart';
import 'package:cw_core/encryption_file_utils.dart';
import 'package:cw_core/pending_transaction.dart';
import 'package:cw_core/transaction_priority.dart';
import 'package:cw_core/unspent_coin_type.dart';
import 'package:cw_core/unspent_coins_info.dart';
import 'package:cw_core/utils/print_verbose.dart';
import 'package:cw_core/wallet_info.dart';
import 'package:cw_core/wallet_keys_file.dart';
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
import 'sapling/sapling_transaction_builder.dart' show TransparentUtxo;

part 'pivx_wallet.g.dart';

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
  PivxWalletBase({
    required String mnemonic,
    required String password,
    required WalletInfo walletInfo,
    required DerivationInfo derivationInfo,
    required Box<UnspentCoinsInfo> unspentCoinsInfo,
    required Uint8List seedBytes,
    required EncryptionFileUtils encryptionFileUtils,
    String? passphrase,
    BitcoinAddressType? addressPageType,
    List<BitcoinAddressRecord>? initialAddresses,
    ElectrumBalance? initialBalance,
    Map<String, int>? initialRegularAddressIndex,
    Map<String, int>? initialChangeAddressIndex,
  }) : super(
          mnemonic: mnemonic,
          password: password,
          walletInfo: walletInfo,
          derivationInfo: derivationInfo,
          unspentCoinsInfo: unspentCoinsInfo,
          network: PivxNetwork.mainnet,
          initialAddresses: initialAddresses,
          initialBalance: initialBalance,
          seedBytes: seedBytes,
          currency: CryptoCurrency.pivx,
          encryptionFileUtils: encryptionFileUtils,
          passphrase: passphrase,
        ) {
    walletAddresses = PivxWalletAddresses(
      walletInfo,
      initialAddresses: initialAddresses,
      initialRegularAddressIndex: initialRegularAddressIndex,
      initialChangeAddressIndex: initialChangeAddressIndex,
      mainHd: hd,
      sideHd: accountHD.childKey(Bip32KeyIndex(1)),
      network: network,
      initialAddressPageType: addressPageType,
      isHardwareWallet: walletInfo.isHardwareWallet,
    );
    autorun((_) {
      this.walletAddresses.isEnabledAutoGenerateSubaddress = this.isEnabledAutoGenerateSubaddress;
    });
  }

  @override
  Future<void> init() async {
    await super.init();
    // Try to initialize Sapling (won't throw if native library is unavailable)
    await tryInitializeSapling();
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
  
  /// The Sapling transaction builder.
  /// Initialized lazily when building shielded transactions.
  SaplingTransactionBuilderWrapper? _saplingTxBuilder;
  
  /// Lock for synchronizing balance updates to prevent race conditions.
  final _balanceLock = Lock();
  
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
    SaplingAddress? tempAddress;
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
          await tempKeyManager.dispose();
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
      printV('[PIVX] Sapling initialization failed: $e');
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
      );
      
      // Restore notes from storage to native engine
      await _shieldSyncEngine!.restoreNotesFromStorage();
      printV('[PIVX] Restored notes to native engine');
    } catch (e) {
      printV('[PIVX] Failed to restore notes to native engine: $e');
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
      );
      await storage.load();
      
      final storedBalance = storage.balance;
      
      if (storedBalance > 0) {
        shieldedBalance = storedBalance;
        // Update the balance map directly with shielded balance
        // Don't call updateBalance() here as electrumClient may not be connected
        // Just update the existing balance to include shielded amount
        final currentBalance = balance[currency];
        if (currentBalance != null) {
          balance[currency] = ElectrumBalance(
            confirmed: currentBalance.confirmed,
            unconfirmed: currentBalance.unconfirmed,
            frozen: currentBalance.frozen,
            secondConfirmed: storedBalance,
            secondUnconfirmed: 0,
          );
        } else {
          // If no balance exists yet, create one with just shielded
          balance[currency] = ElectrumBalance(
            confirmed: 0,
            unconfirmed: 0,
            frozen: 0,
            secondConfirmed: storedBalance,
            secondUnconfirmed: 0,
          );
        }
      }
    } catch (e) {
      printV('[PIVX] Failed to load shielded balance from storage: $e');
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
        if (shieldedBalance != rustBalance || pendingShieldedBalance != rustPending) {
          printV('[PIVX] Balance reconciliation: Dart($shieldedBalance) -> Rust($rustBalance)');
          printV('[PIVX] Pending reconciliation: Dart($pendingShieldedBalance) -> Rust($rustPending)');
          
          // Update Dart state to match Rust
          shieldedBalance = rustBalance;
          pendingShieldedBalance = rustPending;
          
          // Persist to storage
          final storage = SaplingNoteStorage(
            walletId: walletInfo.id,
            isTestnet: network == PivxNetwork.testnet,
          );
          await storage.load();
          await storage.updateBalance(rustBalance);
          
          // Trigger UI update
          await updateBalance();
        }
      } catch (e) {
        printV('[PIVX] Balance reconciliation failed: $e');
        // Don't rethrow - this is a best-effort operation
      }
    });
  }
  
  /// Get a shielded payment address.
  /// 
  /// [index] - Diversifier index (default: current address).
  /// Returns the Bech32-encoded shielded address (ps1...).
  Future<String> getShieldedAddress({int? index}) async {
    await initializeSapling();
    
    if (index != null) {
      final address = await _saplingKeyManager!.deriveAddress(index);
      return address;
    }
    
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
    await initializeSapling();
    
    // Ensure sync engine is initialized for storage access
    if (_shieldSyncEngine == null) {
      _shieldSyncEngine = await ShieldSyncEngineFactory.create(
        keyManager: _saplingKeyManager!,
        walletId: walletInfo.id,
        isTestnet: network == PivxNetwork.testnet,
        electrumClient: electrumClient,
      );
      await _shieldSyncEngine!.initialize();
    }
    
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
    
    await initializeSapling();
    
    if (_shieldSyncEngine == null) {
      _shieldSyncEngine = await ShieldSyncEngineFactory.create(
        keyManager: _saplingKeyManager!,
        walletId: walletInfo.id,
        isTestnet: network == PivxNetwork.testnet,
        electrumClient: electrumClient,
      );
      await _shieldSyncEngine!.initialize();
    }
    
    // Wait for connection to be stable before syncing
    int retries = 0;
    while (!(electrumClient.isConnected ?? false) && retries < 10) {
      await Future.delayed(const Duration(milliseconds: 500));
      retries++;
    }
    if (!(electrumClient.isConnected ?? false)) {
      printV('[PIVX Sapling] Connection not available, aborting sync');
      return;
    }
    
    isShieldSyncing = true;
    
    try {
      // Start from specified height or last synced height
      await _shieldSyncEngine!.startSync(
        startHeight: fromHeight,
        onProgress: (status) async {
          lastShieldSyncedBlock = status.lastSyncedBlock;
          
          // Use lock to prevent race conditions
          await _balanceLock.synchronized(() async {
            shieldedBalance = _shieldSyncEngine!.balance;
            pendingShieldedBalance = _shieldSyncEngine!.pendingBalance;
          });
          
          // Update wallet syncStatus so UI can display progress
          if (status.blocksRemaining > 0 && status.chainTip > 0) {
            final progress = status.lastSyncedBlock / status.chainTip;
            syncStatus = core_sync.SyncingSyncStatus(status.blocksRemaining, progress);
          }
          
          onProgress?.call(status);
        },
      );
      
      // Final reconciliation after sync completes
      await _reconcileShieldedBalance();
    } finally {
      isShieldSyncing = false;
    }
  }
  
  /// Override startSync to also sync shielded notes.
  @override
  @action
  Future<void> startSync() async {
    // First sync transparent transactions via parent
    await super.startSync();
    
    // Then sync shielded notes if Sapling is enabled
    if (saplingEnabled && _saplingKeyManager != null) {
      try {
        await syncShielded();
        
        // Reconcile balance after sync (this uses the lock internally)
        await _reconcileShieldedBalance();
        
        // Trigger balance update to propagate to UI
        await updateBalance();
      } catch (e) {
        printV('[PIVX] Shielded sync failed: $e');
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
    await initializeSapling();
    
    if (_shieldSyncEngine == null) {
      _shieldSyncEngine = await ShieldSyncEngineFactory.create(
        keyManager: _saplingKeyManager!,
        walletId: walletInfo.id,
        isTestnet: network == PivxNetwork.testnet,
        electrumClient: electrumClient,
      );
      await _shieldSyncEngine!.initialize();
    }
    
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
    await initializeSapling();
    
    if (_shieldSyncEngine == null) {
      _shieldSyncEngine = await ShieldSyncEngineFactory.create(
        keyManager: _saplingKeyManager!,
        walletId: walletInfo.id,
        isTestnet: network == PivxNetwork.testnet,
        electrumClient: electrumClient,
      );
    }
    
    // Clear storage and reset sync height
    await _shieldSyncEngine!.storage.clear();
    
    // Reset native sync engine
    _shieldSyncEngine!.resetNativeEngine();
    
    // Sync from the specified height (or activation height if not specified)
    await syncShielded(fromHeight: fromHeight, onProgress: onProgress);
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
  }) async {
    await initializeSapling();
    
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
    );
    
    return await _saplingTxBuilder!.buildTransaction(options: options);
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
    
    if (_saplingTxBuilder == null) {
      _saplingTxBuilder = await SaplingTransactionBuilderFactory.create(
        keyManager: _saplingKeyManager!,
        syncEngine: _shieldSyncEngine!,
        isTestnet: network == PivxNetwork.testnet,
      );
    }
    
    // Ensure proving params are loaded
    await _ensureProvingParamsLoaded();
    
    // Build list of UTXOs with their private keys for signing
    final utxos = <TransparentUtxo>[];
    
    for (final coin in unspentCoins.where((c) => c.isSending)) {
      final addressRecord = coin.bitcoinAddressRecord;
      if (addressRecord is! BitcoinAddressRecord) continue;
      
      // Parse the address and get its script pubkey
      // For PIVX, all addresses are P2PKH (starting with 'D')
      final p2pkhAddress = P2pkhAddress.fromAddress(
        address: addressRecord.address,
        network: network,
      );
      final scriptPubKey = p2pkhAddress.toScriptPubKey().toHex();
      
      // Derive the private key using the HD wallet
      // This matches how electrum_wallet does it for transaction signing
      final privkey = generateECPrivate(
        hd: addressRecord.isHidden ? accountHD.childKey(Bip32KeyIndex(1)) : hd,
        index: addressRecord.index,
        network: network,
      );
      
      // Encode the private key as WIF for the Sapling transaction builder
      final wifKey = WifEncoder.encode(
        privkey.toBytes(),
        netVer: network == PivxNetwork.mainnet 
          ? PivxNetwork.mainnet.wifNetVer
          : PivxNetwork.testnet.wifNetVer,
      );
      
      utxos.add(TransparentUtxo(
        txid: coin.hash,
        vout: coin.vout,
        amount: coin.value,
        scriptPubKey: scriptPubKey,
        privateKey: wifKey,
      ));
    }
    
    if (utxos.isEmpty) {
      throw StateError('No transparent funds available to shield');
    }
    
    final shieldedAddress = await getShieldedAddress();
    
    return await _saplingTxBuilder!.buildShieldingTransaction(
      utxos: utxos,
      toShieldedAddress: shieldedAddress,
      amount: amount,
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
    await initializeSapling();
    
    if (_saplingTxBuilder == null) {
      _saplingTxBuilder = await SaplingTransactionBuilderFactory.create(
        keyManager: _saplingKeyManager!,
        syncEngine: _shieldSyncEngine!,
        isTestnet: network == PivxNetwork.testnet,
      );
    }
    
    // Ensure proving params are loaded
    await _ensureProvingParamsLoaded();
    
    final destAddress = toAddress ?? walletAddresses.address;
    
    return await _saplingTxBuilder!.buildDeshieldingTransaction(
      toTransparentAddress: destAddress,
      amount: amount,
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
          printV('Proving params download: ${(progress * 100).toStringAsFixed(1)}%');
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
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Override fetchUnspent to use custom PIVX scripthash computation.
  @override
  Future<List<BitcoinUnspent>?> fetchUnspent(BitcoinAddressRecord address) async {
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
    final addressesByType = walletAddresses.allAddresses.where((addr) => addr.type == type);
    final hiddenAddresses = addressesByType.where((addr) => addr.isHidden == true);
    final receiveAddresses = addressesByType.where((addr) => addr.isHidden == false);
    walletAddresses.hiddenAddresses.addAll(hiddenAddresses.map((e) => e.address));
    await walletAddresses.saveAddressesInBox();
    await Future.wait(addressesByType.map((addressRecord) async {
      final history = await _fetchPivxAddressHistory(addressRecord, await getCurrentChainTip());

      if (history.isNotEmpty) {
        addressRecord.txCount = history.length;
        historiesWithDetails.addAll(history);

        final matchedAddresses = addressRecord.isHidden ? hiddenAddresses : receiveAddresses;
        final isUsedAddressUnderGap = matchedAddresses.toList().indexOf(addressRecord) >=
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
              return _fetchPivxAddressHistory(address, await getCurrentChainTip())
                  .then((history) => history.isNotEmpty ? address.address : null);
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
        walletAddresses.clearLockIfMatches(addressRecord.type, addressRecord.address);

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
            final tx = await fetchTransactionInfo(hash: txid, height: height, retryOnFailure: true);

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
      printV("PIVX: Error fetching history for ${addressRecord.address}: $e");
      return {};
    }
  }

  /// PIVX dust threshold based on dustRelayFee of 30000 sat/kB.
  /// For a standard output (34 bytes) + input (148 bytes) = 182 bytes
  /// dustThreshold = 30000 * 182 / 1000 ≈ 5460 satoshis
  /// We use 10000 satoshis (0.0001 PIVX) as a safe minimum.
  @override
  int get networkDustAmount => 10000;

  /// Estimate PIVX transaction size.
  /// Similar to Bitcoin P2PKH transactions:
  /// - Each input: ~148 bytes
  /// - Each output: ~34 bytes
  /// - Fixed overhead: ~10 bytes
  static int estimatedPivxTransactionSize(int inputsCount, int outputsCounts) =>
      inputsCount * 148 + outputsCounts * 34 + 10;

  @override
  int feeAmountForPriority(
    TransactionPriority priority,
    int inputsCount,
    int outputsCount, {
    int? size,
  }) =>
      feeRate(priority) * (size ?? estimatedPivxTransactionSize(inputsCount, outputsCount)) ~/ 1000;

  @override
  int feeAmountWithFeeRate(int feeRate, int inputsCount, int outputsCount, {int? size}) =>
      feeRate * (size ?? estimatedPivxTransactionSize(inputsCount, outputsCount)) ~/ 1000;

  /// Create a new PIVX wallet.
  static Future<PivxWallet> create({
    required String mnemonic,
    required String password,
    required WalletInfo walletInfo,
    required DerivationInfo derivationInfo,
    required Box<UnspentCoinsInfo> unspentCoinsInfo,
    required EncryptionFileUtils encryptionFileUtils,
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
  }) async {
    final hasKeysFile = await WalletKeysFile.hasKeysFile(name, walletInfo.type);

    ElectrumWalletSnapshot? snp = null;

    try {
      snp = await ElectrumWalletSnapshot.load(
        encryptionFileUtils,
        name,
        walletInfo.type,
        password,
        PivxNetwork.mainnet,
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
      seedBytes: await MnemonicBip39.toSeed(keysData.mnemonic!, passphrase: keysData.passphrase),
      encryptionFileUtils: encryptionFileUtils,
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
    
    // Check if any output is a shielded address
    for (final out in transactionCredentials.outputs) {
      final address = out.isParsedAddress ? out.extractedAddress! : out.address;
      
      if (_isShieldedAddress(address)) {
        // Route to shielded transaction creation
        return await _createShieldedPendingTransaction(transactionCredentials);
      }
    }
    
    // Standard transparent transaction - use parent implementation
    return await super.createTransaction(credentials);
  }

  /// Create a pending transaction for shielded outputs.
  /// 
  /// This method intelligently routes to the right transaction type:
  /// - If shielded balance is sufficient → shielded-to-shielded
  /// - If only transparent balance available → transparent-to-shielded (shielding)
  Future<PendingTransaction> _createShieldedPendingTransaction(
    BitcoinTransactionCredentials credentials,
  ) async {
    // For now, only support single output shielded transactions
    if (credentials.outputs.length != 1) {
      throw Exception('Shielded transactions currently support only single outputs');
    }
    
    final output = credentials.outputs.first;
    final toAddress = output.isParsedAddress ? output.extractedAddress! : output.address;
    final amount = output.formattedCryptoAmount!;
    final memo = output.memo;
    
    // Initialize sapling to get accurate balances
    await initializeSapling();
    
    // Check if we have sufficient shielded balance
    final hasShieldedFunds = shieldedBalance >= amount;
    
    // Determine if we should use shielded or transparent inputs
    final coinType = credentials.coinTypeToSpendFrom;
    final useShieldedInputs = coinType == UnspentCoinType.sapling || 
                               (coinType == null && hasShieldedFunds);
    
    if (useShieldedInputs) {
      // Shielded-to-shielded transaction
      if (!hasShieldedFunds) {
        throw Exception('Insufficient shielded balance. '
            'You have ${shieldedBalance} zatoshis but need $amount. '
            'Consider shielding some transparent funds first.');
      }
      
      final result = await createShieldedTransaction(
        toAddress: toAddress,
        amount: amount,
        memo: memo,
        useShieldedInputs: true,
      );
      
      return PendingPivxShieldedTransaction(
        result: result,
        electrumClient: electrumClient,
        amount: amount,
        fee: result.fee,
        onCommit: (tx) async {
          await updateBalance();
          await syncShielded();
        },
      );
    } else {
      // Transparent-to-shielded transaction (shielding directly to external address)
      // First check if we have transparent balance
      final transparentBalance = balance[currency]?.confirmed ?? 0;
      if (transparentBalance < amount) {
        throw Exception('Insufficient transparent balance. '
            'You have $transparentBalance but need $amount.');
      }
      
      // Use shieldFunds which handles transparent inputs
      // But we need to send to an external shielded address, not our own
      // This requires a different flow - for now, suggest shielding first
      throw Exception('Direct transparent-to-external-shielded transactions are not yet supported. '
          'Please first shield your funds to your own shielded address, then send to the recipient.');
    }
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
