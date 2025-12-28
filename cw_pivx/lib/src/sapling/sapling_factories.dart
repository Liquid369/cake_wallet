/// Factory classes for creating Sapling implementations.
/// 
/// These factories handle creating the appropriate implementations
/// (native FFI vs pure Dart) based on platform capabilities.

import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:convert/convert.dart';
import 'package:cw_core/utils/print_verbose.dart';
import 'package:cw_pivx/src/sapling/native_sapling_key_manager.dart';
import 'package:cw_pivx/src/sapling/native_shield_sync_engine.dart';
import 'package:cw_pivx/src/sapling/pivx_sapling_electrumx.dart';
import 'package:cw_pivx/src/sapling/sapling_note_storage.dart';
import 'package:cw_pivx/src/sapling/sapling_transaction_builder.dart' show TransparentUtxo;
import 'package:cw_pivx/src/sapling/sapling_ffi.dart' as ffi;
import 'package:cw_pivx/src/sapling/utils/atomic_tree_position.dart';
import 'package:cw_pivx/src/sapling/utils/ordered_batch_processor.dart';

/// Factory for creating Sapling key managers.
class SaplingKeyManagerFactory {
  /// Create a key manager from seed.
  static Future<SaplingKeyManagerWrapper> create({
    required Uint8List seed,
    bool isTestnet = false,
    int accountIndex = 0,
  }) async {
    final nativeManager = await NativeSaplingKeyManager.fromSeed(
      seed,
      isTestnet: isTestnet,
    );
    return SaplingKeyManagerWrapper(nativeManager);
  }
}

/// Wrapper around native key manager that provides a simpler interface
/// for use in the wallet.
class SaplingKeyManagerWrapper {
  final NativeSaplingKeyManager _manager;
  String? _defaultAddressCached;
  int _nextIndex = 0;
  
  SaplingKeyManagerWrapper(this._manager);
  
  /// Initialize the key manager.
  Future<void> initialize() async {
    _defaultAddressCached = await _manager.getDefaultAddress();
  }
  
  /// Get the default address.
  Future<SaplingAddressResult> getDefaultAddress() async {
    final encoded = _defaultAddressCached ?? await _manager.getDefaultAddress();
    return SaplingAddressResult(encoded: encoded);
  }
  
  /// Get an address at a specific index.
  Future<SaplingAddressResult?> getAddressAtIndex(Uint8List indexBytes) async {
    // Convert bytes to int
    int index = 0;
    for (int i = 0; i < 8 && i < indexBytes.length; i++) {
      index |= indexBytes[i] << (i * 8);
    }
    final encoded = await _manager.deriveAddress(index);
    return SaplingAddressResult(encoded: encoded);
  }
  
  /// Get the next address (incrementing index).
  Future<SaplingAddressResult> getNextAddress() async {
    final encoded = await _manager.deriveAddress(_nextIndex);
    _nextIndex++;
    return SaplingAddressResult(encoded: encoded);
  }
  
  /// Derive an address at a specific diversifier index.
  /// Returns the Bech32-encoded shielded address.
  Future<String> deriveAddress(int index) async {
    return await _manager.deriveAddress(index);
  }
  
  /// Get the full viewing key.
  Future<String> getFullViewingKey() async {
    return await _manager.getFullViewingKey();
  }
  
  /// Validate an address.
  bool validateAddress(String address) {
    return _manager.validateAddress(address);
  }
  
  void dispose() {
    _manager.dispose();
  }
}

/// Result of address generation.
class SaplingAddressResult {
  final String encoded;
  
  SaplingAddressResult({required this.encoded});
}

/// Factory for creating shield sync engines.
class ShieldSyncEngineFactory {
  /// Create a sync engine.
  static Future<ShieldSyncEngineWrapper> create({
    required SaplingKeyManagerWrapper keyManager,
    required String walletId,
    bool isTestnet = false,
    required dynamic electrumClient,
  }) async {
    final nativeEngine = NativeShieldSyncEngine(isTestnet: isTestnet);
    final saplingClient = PIVXSaplingElectrumX(
      electrumClient: electrumClient,
      isTestnet: isTestnet,
    );
    final storage = SaplingNoteStorage(
      walletId: walletId,
      isTestnet: isTestnet,
    );
    await storage.load();
    
    return ShieldSyncEngineWrapper(
      nativeEngine, 
      electrumClient,
      saplingClient,
      keyManager: keyManager,
      storage: storage,
      isTestnet: isTestnet,
    );
  }
}

/// Wrapper around native sync engine.
class ShieldSyncEngineWrapper {
  final NativeShieldSyncEngine _engine;
  final dynamic electrumClient;
  final PIVXSaplingElectrumX saplingClient;
  final SaplingKeyManagerWrapper keyManager;
  final SaplingNoteStorage storage;
  final bool isTestnet;
  bool _isSyncing = false;
  final AtomicTreePosition _treePosition = AtomicTreePosition(); // Thread-safe position tracking
  
  ShieldSyncEngineWrapper(
    this._engine, 
    this.electrumClient,
    this.saplingClient, {
    required this.keyManager,
    required this.storage,
    this.isTestnet = false,
  });
  
  /// Get the native FFI handle for direct sync state access.
  int get nativeSyncHandle => _engine.handle;
  
  /// Initialize the sync engine.
  Future<void> initialize() async {
    // Load notes from storage
    await storage.load();
    final lastPosition = storage.notes.isNotEmpty 
        ? storage.notes.map((n) => n.treePosition).reduce((a, b) => a > b ? a : b) + 1
        : 0;
    _treePosition.initialize(lastPosition);
    
    // Restore notes to native engine
    await restoreNotesFromStorage();
  }
  
  /// Restore notes from Dart storage to the native sync engine.
  /// 
  /// This is needed after app restart since the native sync state
  /// is recreated empty. Notes are persisted in Dart storage but
  /// need to be restored to the native engine for transaction building.
  Future<void> restoreNotesFromStorage() async {
    final keyHandle = keyManager._manager.nativeKeys.handle;
    final syncHandle = _engine.handle;
    
    printV('[PIVX Sapling] Restoring notes from storage. Total notes: ${storage.notes.length}');
    
    var restoredCount = 0;
    var skippedSpent = 0;
    var skippedNoData = 0;
    
    for (final note in storage.notes) {
      if (note.isSpent) {
        skippedSpent++;
        continue; // Skip spent notes
      }
      if (!note.hasSpendingData) {
        printV('[PIVX Sapling] Note ${note.id} missing spending data: rseed=${note.rseed != null}, div=${note.diversifier != null}, pkd=${note.pkD != null}, nf=${note.nullifier != null}');
        skippedNoData++;
        continue;
      }
      
      final restoreJson = note.toNativeRestoreJson();
      printV('[PIVX Sapling] Restoring note ${note.id}: value=${restoreJson['value']}, addr_len=${(restoreJson['address'] as String).length}');
      
      final success = ffi.restoreNote(
        keyHandle: keyHandle,
        syncHandle: syncHandle,
        noteData: note.toNativeRestoreJson(),
      );
      
      if (success) {
        restoredCount++;
      } else {
        final error = ffi.getLastError();
        printV('[PIVX Sapling] Failed to restore note ${note.id}: $error');
      }
    }
    
    printV('[PIVX Sapling] Restore complete: $restoredCount restored, $skippedSpent spent, $skippedNoData missing data');
  }
  
  /// Reset the native sync engine.
  /// Used when rescanning to clear the in-memory state.
  void resetNativeEngine() {
    _engine.nativeEngine.reset();
    _treePosition.initialize(0);
    printV('[PIVX Sapling] Reset native sync engine');
  }
  
  /// Get the current balance from stored notes.
  int get balance => storage.balance;
  
  /// Get the pending balance (unconfirmed notes).
  int get pendingBalance {
    // Pending balance would come from unconfirmed notes
    // For now, return 0 as we don't track pending separately
    return 0;
  }
  
  /// Whether sync is in progress.
  bool get isSyncing => _isSyncing;
  
  /// Start syncing.
  /// 
  /// This will:
  /// 1. Get current blockchain height from ElectrumX
  /// 2. Fetch Sapling blocks from last synced height to current
  /// 3. Trial decrypt outputs to find notes
  /// 4. Update commitment tree and witnesses
  /// 5. Track spent notes via nullifiers
  /// 
  /// [startHeight] - Optional starting height. Defaults to last synced or activation height.
  /// [targetHeight] - Optional target height. If not provided, syncs to current tip.
  /// [viewingKey] - Full viewing key bytes for trial decryption.
  Future<void> startSync({
    int? startHeight,
    int? targetHeight,
    Uint8List? viewingKey,
    required void Function(SyncStatus) onProgress,
  }) async {
    if (_isSyncing) {
      return; // Already syncing
    }
    
    _isSyncing = true;
    
    try {
      // Determine start height
      final lastSyncedBlock = storage.lastSyncedHeight;
      final activationHeight = saplingClient.activationHeight;
      
      // If startHeight is explicitly provided, use it (but not before activation)
      // Otherwise, continue from last synced block or activation height
      int effectiveStartHeight;
      if (startHeight != null) {
        // User explicitly requested a height - use max of that and activation
        effectiveStartHeight = startHeight < activationHeight 
            ? activationHeight 
            : startHeight;
      } else {
        // No explicit height - continue from where we left off
        effectiveStartHeight = lastSyncedBlock > activationHeight 
            ? lastSyncedBlock + 1 
            : activationHeight;
      }
      
      // Report initial progress
      onProgress(SyncStatus(
        lastSyncedBlock: effectiveStartHeight,
        chainTip: effectiveStartHeight,
        blocksRemaining: 0,
        progress: 0.0,
      ));
      
      // Check if electrum client is connected
      final isConnected = electrumClient.isConnected ?? false;
      
      // Get target height if not provided - query the blockchain tip
      int effectiveTargetHeight = targetHeight ?? effectiveStartHeight;
      if (targetHeight == null) {
        try {
          final tip = await electrumClient.getCurrentBlockChainTip();
          if (tip != null && tip > effectiveStartHeight) {
            effectiveTargetHeight = tip as int;
          }
        } catch (e) {
          // Fall back to start height, no sync will happen
        }
      }
      
      if (effectiveTargetHeight <= effectiveStartHeight) {
        onProgress(SyncStatus(
          lastSyncedBlock: effectiveStartHeight,
          chainTip: effectiveStartHeight,
          blocksRemaining: 0,
          progress: 1.0,
        ));
        return;
      }
      
      // Sync blocks using ElectrumX Sapling RPC with ordered processing
      var outputsChecked = 0;
      var blocksWithSapling = 0;
      
      // Create ordered batch processor for sequential block processing
      final batchProcessor = OrderedBatchProcessor(
        startHeight: effectiveStartHeight,
        batchSize: 100,
      );
      
      await saplingClient.syncBlocks(
        fromHeight: effectiveStartHeight,
        toHeight: effectiveTargetHeight,
        batchSize: 100, // Max 100 blocks per request per server limit
        parallelBatches: 5, // Parallel requests (network I/O remains parallel)
        onBatch: (blocks) async {
          // Add batch to ordered queue (fast, non-blocking)
          if (blocks.isNotEmpty) {
            batchProcessor.addBatch(blocks.first.height, blocks);
          }
          
          // Process any sequential batches that are ready
          await batchProcessor.processAvailableBatches(
            onBlock: (block) => _processSingleBlock(
              block,
              keyManager,
              storage,
              (count) => outputsChecked += count,
              () => blocksWithSapling++,
            ),
          );
        },
        onRangeComplete: (rangeEnd) {
          // Update progress even when no Sapling blocks found
          final progress = (rangeEnd - effectiveStartHeight) / 
                           (effectiveTargetHeight - effectiveStartHeight);
          final remaining = effectiveTargetHeight - rangeEnd;
          onProgress(SyncStatus(
            lastSyncedBlock: rangeEnd,
            chainTip: effectiveTargetHeight,
            blocksRemaining: remaining > 0 ? remaining : 0,
            progress: progress.clamp(0.0, 1.0),
          ));
          // Update storage sync height for empty ranges too
          storage.setLastSyncedHeight(rangeEnd);
          _engine.nativeEngine.setSyncHeight(rangeEnd);
        },
      );
      
      // Process any remaining buffered blocks at the end
      await batchProcessor.drainRemaining(
        onBlock: (block) => _processSingleBlock(
          block,
          keyManager,
          storage,
          (count) => outputsChecked += count,
          () => blocksWithSapling++,
        ),
      );
      
      // Log sync completion statistics
      printV('[PIVX Sapling] Sync complete: checked $outputsChecked outputs in $blocksWithSapling blocks with Sapling txs');
      printV('[PIVX Sapling] Synced from $effectiveStartHeight to $effectiveTargetHeight');
      printV('[PIVX Sapling] Storage now has ${storage.notes.length} notes, balance: ${storage.balance}');
      
      // Final progress
      onProgress(SyncStatus(
        lastSyncedBlock: effectiveTargetHeight,
        chainTip: effectiveTargetHeight,
        blocksRemaining: 0,
        progress: 1.0,
      ));
    } finally {
      _isSyncing = false;
    }
  }
  
  /// Process a single block with thread-safe position tracking.
  /// 
  /// This method processes one block at a time in sequential order,
  /// eliminating race conditions in tree position assignment.
  Future<void> _processSingleBlock(
    SaplingBlock block,
    SaplingKeyManagerWrapper keyManager,
    SaplingNoteStorage storage,
    void Function(int count) onOutputsChecked,
    void Function() onBlockWithSapling,
  ) async {
    // Get native handles for FFI calls
    final nativeKeys = keyManager._manager.nativeKeys;
    final nativeEngine = _engine.nativeEngine;
    
    // Count total outputs in this block
    final outputCount = block.txs.fold<int>(0, (sum, tx) => sum + tx.outputs.length);
    if (outputCount > 0) {
      onBlockWithSapling();
    }
    
    // ATOMIC: Reserve all positions for this block upfront
    final startPosition = await _treePosition.reservePositions(outputCount);
    var currentPosition = startPosition;
    
    // Process spends (nullifiers) first - mark our notes as spent
    for (final tx in block.txs) {
      for (final spend in tx.spends) {
        nativeEngine.checkNullifier(spend.nullifierBytes);
        // Also check if this nullifier matches any of our stored notes
        await storage.markSpentByNullifier(spend.nullifier, tx.txid);
      }
    }
    
    // Process outputs (trial decryption)
    for (var txIdx = 0; txIdx < block.txs.length; txIdx++) {
      final tx = block.txs[txIdx];
      for (var outIdx = 0; outIdx < tx.outputs.length; outIdx++) {
        final output = tx.outputs[outIdx];
        onOutputsChecked(1);
        
        // Try to decrypt this output with pre-assigned position
        final value = nativeEngine.tryDecryptOutput(
          keys: nativeKeys,
          cmu: output.cmuBytes,
          epk: output.epkBytes,
          encCiphertext: output.ciphertextBytes,
          height: block.height,
          txIndex: txIdx,
          outputIndex: outIdx,
          position: currentPosition,
        );
        
        if (value > 0) {
          // Found a note! Get full data from native engine and save to storage.
          printV('[PIVX Sapling] Found note: $value zatoshis at height ${block.height}, position $currentPosition');
          
          // Get full note data from native engine (includes rseed, address, etc.)
          final allNotes = ffi.getSpendableNotes(nativeEngine.handle);
          printV('[PIVX Sapling] Native engine has ${allNotes.length} notes');
          
          // Find the note we just added (should be the last one with matching value/position)
          Map<String, dynamic>? fullNoteData;
          for (final n in allNotes.reversed) {
            if (n['value'] == value && n['position'] == currentPosition) {
              fullNoteData = n;
              break;
            }
          }
          
          if (fullNoteData != null) {
            printV('[PIVX Sapling] Got full note data: rseed=${fullNoteData['rseed'] != null}, nullifier=${fullNoteData['nullifier'] != null}');
          } else {
            printV('[PIVX Sapling] WARNING: Could not find note in native engine!');
            // Try to find by value only
            for (final n in allNotes.reversed) {
              if (n['value'] == value) {
                printV('[PIVX Sapling] Found note by value only, position in native: ${n['position']}');
                fullNoteData = n;
                break;
              }
            }
          }
          
          final note = StoredSaplingNote(
            id: '${tx.txid}:$outIdx',
            value: value,
            height: block.height,
            txid: tx.txid,
            outputIndex: outIdx,
            treePosition: currentPosition,
            cmu: hex.encode(output.cmuBytes),
            // Include cryptographic data for spending
            nullifier: fullNoteData?['nullifier'] as String?,
            rseed: fullNoteData?['rseed'] as String?,
            diversifier: fullNoteData?['diversifier'] as String?,
            pkD: fullNoteData?['pk_d'] as String?,
            address: fullNoteData?['address'] as String?,
            txIndex: txIdx,
          );
          await storage.addNote(note);
        }
        
        // Move to next position (no race - positions are pre-assigned)
        currentPosition++;
      }
    }
    
    // Update sync height in storage
    await storage.setLastSyncedHeight(block.height);
    nativeEngine.setSyncHeight(block.height);
  }
  
  /// Check multiple nullifiers for spent status.
  /// 
  /// Returns a map of nullifier hex -> spent status.
  Future<Map<String, bool>> checkNullifiers(List<String> nullifiers) async {
    return await saplingClient.checkNullifiers(nullifiers);
  }
  
  /// Get the current best anchor.
  Future<BestAnchorResult> getBestAnchor() async {
    return await saplingClient.getBestAnchor();
  }
  
  /// Force a rescan from a specific height.
  /// Clears all stored notes and resets sync state.
  Future<void> rescan({int? fromHeight}) async {
    await storage.clear();
    _treePosition.reset();
  }
  
  /// Stop syncing.
  void stopSync() {
    _isSyncing = false;
  }
  
  void dispose() {
    _engine.dispose();
  }
}

/// Sync status.
class SyncStatus {
  final int lastSyncedBlock;
  final int chainTip;
  final int blocksRemaining;
  final double progress;
  
  SyncStatus({
    required this.lastSyncedBlock,
    required this.chainTip,
    required this.blocksRemaining,
    required this.progress,
  });
}

/// Callback type for sync progress.
typedef SyncProgressCallback = void Function(SyncStatus status);

/// Factory for creating transaction builders.
class SaplingTransactionBuilderFactory {
  /// Create a transaction builder.
  static Future<SaplingTransactionBuilderWrapper> create({
    required SaplingKeyManagerWrapper keyManager,
    required ShieldSyncEngineWrapper syncEngine,
    bool isTestnet = false,
  }) async {
    return SaplingTransactionBuilderWrapper(
      keyManager: keyManager,
      syncEngine: syncEngine,
      isTestnet: isTestnet,
    );
  }
}

/// Wrapper around transaction builder.
class SaplingTransactionBuilderWrapper {
  final SaplingKeyManagerWrapper keyManager;
  final ShieldSyncEngineWrapper syncEngine;
  final bool isTestnet;
  String? _provingParamsPath;
  bool _proverInitialized = false;
  
  SaplingTransactionBuilderWrapper({
    required this.keyManager,
    required this.syncEngine,
    required this.isTestnet,
  });
  
  /// Whether proving parameters are loaded.
  bool get hasProvingParams => _provingParamsPath != null && _proverInitialized;
  
  /// Get the path where proving params are stored.
  String get provingParamsPath => _provingParamsPath ?? '';
  
  /// Load proving parameters.
  /// 
  /// Proving parameters are large files (~50MB total) required for
  /// generating Groth16 proofs. They need to be downloaded once and
  /// stored locally.
  Future<void> loadProvingParams({required String path}) async {
    // Check if params exist at path
    final spendPath = '$path/sapling-spend.params';
    final outputPath = '$path/sapling-output.params';
    
    final spendFile = File(spendPath);
    final outputFile = File(outputPath);
    
    if (!await spendFile.exists() || !await outputFile.exists()) {
      throw Exception('Proving parameters not found at $path. '
          'Call downloadProvingParams first.');
    }
    
    // Initialize the prover with FFI
    if (!ffi.initProver(path)) {
      final error = ffi.getLastError();
      throw Exception('Failed to initialize prover: $error');
    }
    
    _provingParamsPath = path;
    _proverInitialized = true;
  }
  
  /// Check if proving parameters exist locally.
  Future<bool> hasLocalProvingParams(String path) async {
    final spendPath = '$path/sapling-spend.params';
    final outputPath = '$path/sapling-output.params';
    
    final spendFile = File(spendPath);
    final outputFile = File(outputPath);
    
    return await spendFile.exists() && await outputFile.exists();
  }
  
  /// Download proving parameters from PIVX servers.
  /// 
  /// [path] - Directory to store the params.
  /// [onProgress] - Callback for download progress (0.0 to 1.0).
  Future<void> downloadProvingParams({
    required String path,
    required void Function(double) onProgress,
  }) async {
    // PIVX Sapling proving params URLs (hosted by Duddino)
    const spendUrl = 'https://duddino.com/sapling-spend.params';
    const outputUrl = 'https://duddino.com/sapling-output.params';
    
    // Expected sizes for progress tracking
    const spendSize = 47958503; // ~47.5 MB
    const outputSize = 3592860;  // ~3.5 MB
    const totalSize = spendSize + outputSize;
    
    // Ensure directory exists
    final dir = Directory(path);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    
    final spendPath = '$path/sapling-spend.params';
    final outputPath = '$path/sapling-output.params';
    
    var downloadedBytes = 0;
    
    // Download spend params
    final spendFile = File(spendPath);
    if (!await spendFile.exists()) {
      await _downloadFile(
        url: spendUrl,
        destination: spendPath,
        onProgress: (bytes) {
          downloadedBytes = bytes;
          onProgress(downloadedBytes / totalSize);
        },
      );
    } else {
      downloadedBytes = spendSize;
      onProgress(downloadedBytes / totalSize);
    }
    
    // Download output params
    final outputFile = File(outputPath);
    if (!await outputFile.exists()) {
      await _downloadFile(
        url: outputUrl,
        destination: outputPath,
        onProgress: (bytes) {
          onProgress((spendSize + bytes) / totalSize);
        },
      );
    }
    
    onProgress(1.0);
    _provingParamsPath = path;
  }
  
  /// Download a file with progress tracking.
  Future<void> _downloadFile({
    required String url,
    required String destination,
    required void Function(int bytesDownloaded) onProgress,
  }) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      
      if (response.statusCode != 200) {
        throw Exception('Failed to download $url: ${response.statusCode}');
      }
      
      final file = File(destination);
      final sink = file.openWrite();
      var downloaded = 0;
      
      await for (final chunk in response) {
        sink.add(chunk);
        downloaded += chunk.length;
        onProgress(downloaded);
      }
      
      await sink.close();
    } finally {
      client.close();
    }
  }
  
  /// Build a shielded-to-shielded transaction.
  Future<SaplingTransactionResult> buildTransaction({
    required SaplingTransactionOptions options,
  }) async {
    // Validate we have sufficient balance
    if (syncEngine.balance < options.amount) {
      throw Exception('Insufficient shielded balance');
    }
    
    // Validate we have proving params
    if (!hasProvingParams) {
      throw Exception('Proving parameters not loaded. Call loadProvingParams first.');
    }
    
    // Validate address format based on network
    if (!keyManager.validateAddress(options.toAddress)) {
      throw Exception('Invalid destination address');
    }
    
    // Get spendable notes from Rust sync state (includes rseed and address data)
    final syncHandle = syncEngine.nativeSyncHandle;
    final allNotes = ffi.getSpendableNotes(syncHandle);
    
    if (allNotes.isEmpty) {
      throw Exception('No spendable notes available');
    }
    
    // Select notes for spending
    final selectedNotes = _selectNotes(allNotes, options.amount);
    if (selectedNotes.isEmpty) {
      throw Exception('Could not select sufficient notes');
    }
    
    // Calculate fee (1 spend per note + 2 outputs = recipient + change)
    final fee = ffi.estimateFee(
      numSpends: selectedNotes.length,
      numOutputs: 2,
    );
    
    // Verify we have enough after fee
    final totalInput = selectedNotes.fold<int>(0, (sum, n) => sum + (n['value'] as int));
    if (totalInput < options.amount + fee) {
      throw Exception('Insufficient balance after fee');
    }
    
    printV('[PIVX Sapling] Selected ${selectedNotes.length} notes with total $totalInput zatoshis');
    
    // Get witnesses for selected notes from ElectrumX
    printV('[PIVX Sapling] Fetching witnesses...');
    final notesWithWitnesses = await _fetchWitnesses(selectedNotes);
    printV('[PIVX Sapling] Witnesses fetched');
    
    // Get current anchor
    printV('[PIVX Sapling] Getting anchor...');
    final anchorResult = await syncEngine.getBestAnchor();
    printV('[PIVX Sapling] Got anchor at height ${anchorResult.height}');
    
    // Get native key handle
    final keyHandle = keyManager._manager.nativeKeys.handle;
    
    // Build JSON for notes (already has rseed, address, nullifier from Rust)
    final notesJson = jsonEncode(notesWithWitnesses);
    printV('[PIVX Sapling] Building transaction with anchor ${anchorResult.anchor.substring(0, 16)}...');
    
    // Call FFI to build transaction
    // Call FFI to build transaction
    printV('[PIVX Sapling] Calling FFI buildShieldedTransaction (this may take 30-60 seconds for proving)...');
    final result = ffi.buildShieldedTransaction(
      keyHandle: keyHandle,
      notesJson: notesJson,
      toAddress: options.toAddress,
      amount: options.amount,
      memo: options.memo,
      fee: fee,
      anchorHex: anchorResult.anchor,
    );
    printV('[PIVX Sapling] FFI returned, status: ${result['status']}');
    
    if (result['status'] == 'error') {
      throw Exception('Transaction build failed: ${result['error']}');
    }
    
    final txHex = result['tx_hex'] as String;
    final txid = result['txid'] as String;
    
    return SaplingTransactionResult(
      rawTx: Uint8List.fromList(hex.decode(txHex)),
      txHex: txHex,
      txId: txid,
      fee: fee,
    );
  }
  
  /// Select notes to cover the required amount.
  List<Map<String, dynamic>> _selectNotes(
    List<Map<String, dynamic>> allNotes,
    int amount,
  ) {
    // Sort by value descending to minimize number of inputs
    final sorted = List<Map<String, dynamic>>.from(allNotes)
      ..sort((a, b) => (b['value'] as int).compareTo(a['value'] as int));
    
    final selected = <Map<String, dynamic>>[];
    var total = 0;
    
    for (final note in sorted) {
      selected.add(note);
      total += note['value'] as int;
      if (total >= amount) break;
    }
    
    return selected;
  }
  
  /// Fetch merkle witnesses for notes from ElectrumX.
  /// 
  /// Uses blockchain.sapling.get_witness RPC:
  /// - commitment_hex: 32-byte commitment (cmu) as hex
  /// - anchor_height: Block height of anchor
  /// 
  /// Returns: {position, path, anchor, commitment, commitment_height}
  Future<List<Map<String, dynamic>>> _fetchWitnesses(
    List<Map<String, dynamic>> notes,
  ) async {
    final result = <Map<String, dynamic>>[];
    
    // Get current anchor height
    final anchorResult = await syncEngine.getBestAnchor();
    
    for (final note in notes) {
      final noteWithWitness = Map<String, dynamic>.from(note);
      
      // We need the commitment (cmu) to fetch the witness
      // The cmu should be computed from the note or stored during sync
      // For now, we'll try to derive it or use position
      
      try {
        // The witness API needs the commitment hex
        // We can compute cmu from the note's address, value, and rseed
        // But for now, try using the stored address as a proxy
        // TODO: Compute proper cmu from note components
        
        // Try to get witness using the note's commitment
        // The note should have a cmu field if stored during sync
        String? cmu = note['cmu'] as String?;
        
        if (cmu == null || cmu.isEmpty) {
          // Need to compute cmu - for now this is a limitation
          // The cmu should be stored during trial decryption
          printV('[PIVX] Note missing cmu, cannot fetch witness');
          noteWithWitness['witness'] = '';
          noteWithWitness['witness_position'] = 0;
          result.add(noteWithWitness);
          continue;
        }
        
        // Fetch witness from ElectrumX
        // API: blockchain.sapling.get_witness(commitment_hex, anchor_height)
        printV('[PIVX] Fetching witness for cmu ${cmu.substring(0, 16)}... at height ${anchorResult.height}');
        final witnessData = await syncEngine.saplingClient.getWitness(
          cmu,
          anchorResult.height,
        );
        
        if (witnessData != null) {
          printV('[PIVX] Got witness response: keys=${witnessData.keys}');
          // Response: {position, path, anchor, commitment, commitment_height}
          final pathList = witnessData['path'] as List<dynamic>?;
          if (pathList != null && pathList.isNotEmpty) {
            // Serialize path as hex-encoded concatenated hashes
            final pathHex = pathList.map((h) => h.toString()).join('');
            printV('[PIVX] Witness path length: ${pathHex.length} chars (expected 2048 for 32 hashes)');
            noteWithWitness['witness'] = pathHex;
            noteWithWitness['witness_position'] = witnessData['position'] ?? 0;
          } else {
            printV('[PIVX] Witness has no path!');
            throw Exception('Failed to get witness path for note - anchor may be too old');
          }
        } else {
          printV('[PIVX] No witness returned for note with cmu $cmu');
          throw Exception('No witness available for note');
        }
      } catch (e) {
        printV('[PIVX] Failed to fetch witness: $e');
        rethrow; // Don't continue with missing witness data
      }
      
      result.add(noteWithWitness);
    }
    
    return result;
  }
  
  /// Build a shielding transaction (t→z).
  Future<SaplingTransactionResult> buildShieldingTransaction({
    required List<TransparentUtxo> utxos,
    required String toShieldedAddress,
    int? amount,
  }) async {
    // TODO: Implement transparent-to-shielded transaction
    throw UnimplementedError(
      'Shielding transaction building not yet implemented.'
    );
  }
  
  /// Build a deshielding transaction (z→t).
  Future<SaplingTransactionResult> buildDeshieldingTransaction({
    required String toTransparentAddress,
    required int amount,
  }) async {
    // TODO: Implement shielded-to-transparent transaction
    throw UnimplementedError(
      'Deshielding transaction building not yet implemented.'
    );
  }
  
  void dispose() {
    // Dispose prover if initialized
    if (_proverInitialized) {
      ffi.disposeProver();
      _proverInitialized = false;
    }
  }
}

/// Transaction options.
class SaplingTransactionOptions {
  final String toAddress;
  final int amount;
  final String? memo;
  final bool useShieldedInputs;
  
  SaplingTransactionOptions({
    required this.toAddress,
    required this.amount,
    this.memo,
    this.useShieldedInputs = true,
  });
}

/// Transaction result.
class SaplingTransactionResult {
  final Uint8List rawTx;
  final String txHex;
  final String txId;
  final int fee;
  
  SaplingTransactionResult({
    required this.rawTx,
    required this.txHex,
    required this.txId,
    required this.fee,
  });
}
