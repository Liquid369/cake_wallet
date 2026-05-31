/// Factory classes for creating Sapling implementations.
///
/// These factories handle creating the appropriate implementations
/// (native FFI vs pure Dart) based on platform capabilities.

import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:convert/convert.dart';
import 'package:cw_core/encryption_file_utils.dart';
import 'package:cw_core/utils/print_verbose.dart';
import 'package:cw_core/utils/proxy_wrapper.dart';
import 'package:cw_pivx/src/sapling/native_sapling_key_manager.dart';
import 'package:cw_pivx/src/sapling/native_shield_sync_engine.dart';
import 'package:cw_pivx/src/sapling/pivx_sapling_electrumx.dart';
import 'package:cw_pivx/src/sapling/sapling_constants.dart';
import 'package:cw_pivx/src/sapling/sapling_note_storage.dart';
import 'package:cw_pivx/src/sapling/sapling_transaction_builder.dart'
    show TransparentUtxo;
import 'package:cw_pivx/src/sapling/sapling_ffi.dart' as ffi;
import 'package:cw_pivx/src/sapling/utils/atomic_tree_position.dart';
import 'package:blockchain_utils/crypto/quick_crypto.dart';

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
    required EncryptionFileUtils encryptionFileUtils,
    required String password,
  }) async {
    final nativeEngine = NativeShieldSyncEngine(isTestnet: isTestnet);
    final saplingClient = PIVXSaplingElectrumX(
      electrumClient: electrumClient,
      isTestnet: isTestnet,
    );
    final storage = SaplingNoteStorage(
      walletId: walletId,
      isTestnet: isTestnet,
      encryptionFileUtils: encryptionFileUtils,
      password: password,
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
  bool _treePositionIsTrusted = false;
  final AtomicTreePosition _treePosition =
      AtomicTreePosition(); // Thread-safe position tracking

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
    _treePosition.initialize(storage.nextTreePosition);
    _treePositionIsTrusted = storage.hasPersistedTreePosition;

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

    printV('[PIVX Sapling] Restoring spendable notes from encrypted storage');

    for (final note in storage.notes) {
      if (note.isSpent) {
        continue; // Skip spent notes
      }
      if (note.isPendingSpend) {
        continue;
      }
      if (!note.hasSpendingData) {
        continue;
      }

      final success = ffi.restoreNote(
        keyHandle: keyHandle,
        syncHandle: syncHandle,
        noteData: note.toNativeRestoreJson(),
      );

      if (!success) {
        printV('[PIVX Sapling] Failed to restore one stored note');
      }
    }

    printV('[PIVX Sapling] Stored note restore pass complete');
  }

  /// Reset the native sync engine.
  /// Used when rescanning to clear the in-memory state.
  void resetNativeEngine() {
    _engine.nativeEngine.reset();
    _treePosition.initialize(0);
    _treePositionIsTrusted = false;
    printV('[PIVX Sapling] Reset native sync engine');
  }

  /// Get the current balance from stored notes.
  int get balance => storage.spendableBalanceAt(
        chainHeight: storage.lastSyncedHeight,
      );

  int balanceAt(int chainHeight) => storage.spendableBalanceAt(
        chainHeight: chainHeight,
      );

  /// Get the pending balance (unconfirmed notes).
  int get pendingBalance => storage.pendingReceivedBalanceAt(
        chainHeight: storage.lastSyncedHeight,
      );

  int pendingBalanceAt(int chainHeight) => storage.pendingReceivedBalanceAt(
        chainHeight: chainHeight,
      );

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
        effectiveStartHeight =
            startHeight < activationHeight ? activationHeight : startHeight;
      } else {
        // No explicit height - continue from where we left off
        effectiveStartHeight = lastSyncedBlock > activationHeight
            ? lastSyncedBlock + 1
            : activationHeight;
      }

      final capabilities = await saplingClient.probeCapabilities();
      if (startHeight == null &&
          capabilities.supportsBlockHashes &&
          lastSyncedBlock >= activationHeight) {
        final rewindHeight = await _detectReorgRewindHeight(lastSyncedBlock);
        if (rewindHeight != null) {
          await storage.rewindToHeight(rewindHeight);
          resetNativeEngine();
          await restoreNotesFromStorage();
          effectiveStartHeight = rewindHeight >= activationHeight
              ? rewindHeight + 1
              : activationHeight;
        }
      }
      if (!storage.hasPersistedTreePosition &&
          effectiveStartHeight > activationHeight &&
          !capabilities.supportsGlobalOutputPositions) {
        throw SaplingRpcException(
          'PIVX Sapling sync cannot start after activation without a persisted tree cursor or server global output positions',
        );
      }
      _treePositionIsTrusted = storage.hasPersistedTreePosition ||
          effectiveStartHeight <= activationHeight;

      // Report initial progress
      onProgress(SyncStatus(
        lastSyncedBlock: effectiveStartHeight,
        chainTip: effectiveStartHeight,
        blocksRemaining: 0,
        progress: 0.0,
      ));

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

      if (effectiveTargetHeight < effectiveStartHeight) {
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

      await saplingClient.syncBlocks(
        fromHeight: effectiveStartHeight,
        toHeight: effectiveTargetHeight,
        batchSize: 100, // Max 100 blocks per request per server limit
        parallelBatches: 5, // Parallel requests (network I/O remains parallel)
        onBatch: (blocks) async {
          for (final block in blocks) {
            await _processSingleBlock(
              block,
              keyManager,
              storage,
              (count) => outputsChecked += count,
              () => blocksWithSapling++,
            );
          }
        },
        onRangeComplete: (rangeEnd, blockHashes) async {
          // Update progress even when no Sapling blocks found
          final totalRange = effectiveTargetHeight - effectiveStartHeight + 1;
          final safeTotalRange = totalRange < 1 ? 1 : totalRange;
          final progress =
              (rangeEnd - effectiveStartHeight + 1) / safeTotalRange;
          final remaining = effectiveTargetHeight - rangeEnd;
          onProgress(SyncStatus(
            lastSyncedBlock: rangeEnd,
            chainTip: effectiveTargetHeight,
            blocksRemaining: remaining > 0 ? remaining : 0,
            progress: progress.clamp(0.0, 1.0),
          ));
          // Update storage sync height for empty ranges too, keeping the
          // persisted tree cursor and height in the same sidecar write.
          await storage.completeSyncRange(
            lastSyncedHeight: rangeEnd,
            nextTreePosition: _treePosition.current,
            treePositionIsTrusted: _treePositionIsTrusted,
            blockHashes: blockHashes,
          );
          _engine.nativeEngine.setSyncHeight(rangeEnd);
        },
      );

      // Log sync completion statistics
      printV(
          '[PIVX Sapling] Sync complete: checked $outputsChecked outputs in $blocksWithSapling blocks with Sapling txs');
      printV(
          '[PIVX Sapling] Synced from $effectiveStartHeight to $effectiveTargetHeight');
      printV('[PIVX Sapling] Encrypted storage updated');

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

    final outputs = block.txs.expand((tx) => tx.outputs).toList();
    final outputCount = outputs.length;
    if (outputCount > 0) {
      onBlockWithSapling();
    }

    final explicitPositionCount =
        outputs.where((output) => output.globalPosition != null).length;
    if (explicitPositionCount > 0 && explicitPositionCount != outputCount) {
      throw SaplingRpcException(
          'PIVX Sapling block ${block.height} has partial output position data');
    }

    final hasExplicitPositions = explicitPositionCount == outputCount;
    var currentPosition = _treePosition.current;
    int? previousExplicitPosition;
    var checkedExplicitCursor = false;

    // Process spends (nullifiers) first - mark our notes as spent
    for (final tx in block.txs) {
      for (final spend in tx.spends) {
        nativeEngine.checkNullifier(spend.nullifierBytes);
        // Also check if this nullifier matches any of our stored notes
        await storage.markSpentByNullifier(
          spend.nullifier,
          tx.txid,
          spendingHeight: block.height,
        );
      }
    }

    // Process outputs (trial decryption)
    for (var txIdx = 0; txIdx < block.txs.length; txIdx++) {
      final tx = block.txs[txIdx];
      for (var outIdx = 0; outIdx < tx.outputs.length; outIdx++) {
        final output = tx.outputs[outIdx];
        onOutputsChecked(1);
        final treePosition = output.globalPosition ?? currentPosition;
        if (hasExplicitPositions) {
          if (!checkedExplicitCursor &&
              _treePositionIsTrusted &&
              currentPosition > 0 &&
              treePosition != currentPosition) {
            throw SaplingRpcException(
                'PIVX Sapling block ${block.height} output positions do not match the persisted tree cursor');
          }
          checkedExplicitCursor = true;
          _treePositionIsTrusted = true;
          if (previousExplicitPosition != null &&
              treePosition != previousExplicitPosition + 1) {
            throw SaplingRpcException(
                'PIVX Sapling block ${block.height} output positions are not contiguous');
          }
          previousExplicitPosition = treePosition;
        }

        // Try to decrypt this output with pre-assigned position
        final value = nativeEngine.tryDecryptOutput(
          keys: nativeKeys,
          cmu: output.cmuBytes,
          epk: output.epkBytes,
          encCiphertext: output.ciphertextBytes,
          height: block.height,
          txIndex: txIdx,
          outputIndex: outIdx,
          position: treePosition,
        );

        if (value > 0) {
          // Get full note data from native engine (includes rseed, address, etc.)
          final allNotes = ffi.getSpendableNotes(nativeEngine.handle);

          // Find the note we just added (should be the last one with matching value/position)
          Map<String, dynamic>? fullNoteData;
          for (final n in allNotes.reversed) {
            if (n['value'] == value && n['position'] == treePosition) {
              fullNoteData = n;
              break;
            }
          }

          if (fullNoteData == null) {
            printV('[PIVX Sapling] Native note restore data unavailable');
            // Try to find by value only
            for (final n in allNotes.reversed) {
              if (n['value'] == value) {
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
            treePosition: treePosition,
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

        currentPosition = treePosition + 1;
      }
    }

    // Update sync height in storage
    await _treePosition.setAtLeast(currentPosition);
    await storage.completeSyncRange(
      lastSyncedHeight: block.height,
      nextTreePosition: currentPosition,
      treePositionIsTrusted: _treePositionIsTrusted,
      blockHashes: block.hash.isEmpty
          ? const {}
          : <int, String>{block.height: block.hash},
    );
    nativeEngine.setSyncHeight(block.height);
  }

  Future<int?> _detectReorgRewindHeight(int lastSyncedBlock) async {
    final activationHeight = saplingClient.activationHeight;
    if (lastSyncedBlock < activationHeight) return null;

    final compareStart = lastSyncedBlock - 99 > activationHeight
        ? lastSyncedBlock - 99
        : activationHeight;
    final range = await saplingClient.getBlockRangeResult(
      compareStart,
      endHeight: lastSyncedBlock,
    );
    if (range.blockHashes.isEmpty) return null;

    var firstMismatch = 0;
    for (var height = compareStart; height <= lastSyncedBlock; height++) {
      final localHash = storage.scannedBlockHashes[height];
      final serverHash = range.blockHashes[height];
      if (localHash == null || serverHash == null) {
        continue;
      }
      if (localHash.toLowerCase() != serverHash.toLowerCase()) {
        firstMismatch = height;
        break;
      }
    }

    if (firstMismatch == 0) {
      await storage.completeSyncRange(
        lastSyncedHeight: lastSyncedBlock,
        nextTreePosition: storage.nextTreePosition,
        treePositionIsTrusted: storage.hasPersistedTreePosition,
        blockHashes: range.blockHashes,
      );
      return null;
    }

    var rewindHeight = firstMismatch - 1;
    for (var height = firstMismatch - 1; height >= activationHeight; height--) {
      final localHash = storage.scannedBlockHashes[height];
      final serverHash = range.blockHashes[height];
      if (localHash != null &&
          serverHash != null &&
          localHash.toLowerCase() == serverHash.toLowerCase()) {
        rewindHeight = height;
        break;
      }
    }
    if (rewindHeight < activationHeight) {
      rewindHeight = activationHeight - 1;
    }

    printV('[PIVX Sapling] Reorg detected; rewinding shielded sync state');
    return rewindHeight;
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
    _treePositionIsTrusted = false;
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
    if (!await hasLocalProvingParams(path)) {
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

    return await _verifyParamFile(
          file: File(spendPath),
          expectedSize: SaplingParams.spendParamsSize,
          expectedHash: SaplingParams.spendParamsHash,
        ) &&
        await _verifyParamFile(
          file: File(outputPath),
          expectedSize: SaplingParams.outputParamsSize,
          expectedHash: SaplingParams.outputParamsHash,
        );
  }

  /// Download proving parameters from PIVX servers.
  ///
  /// [path] - Directory to store the params.
  /// [onProgress] - Callback for download progress (0.0 to 1.0).
  Future<void> downloadProvingParams({
    required String path,
    required void Function(double) onProgress,
  }) async {
    const totalSize =
        SaplingParams.spendParamsSize + SaplingParams.outputParamsSize;

    // Ensure directory exists
    final dir = Directory(path);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    var downloadedBytes = 0;

    await _downloadParamIfNeeded(
      url: SaplingParams.spendParamsUrl,
      destination: '$path/${SaplingParams.spendParamsFileName}',
      expectedSize: SaplingParams.spendParamsSize,
      expectedHash: SaplingParams.spendParamsHash,
      onDownloaded: (bytes) {
        downloadedBytes = bytes;
        onProgress(downloadedBytes / totalSize);
      },
    );
    downloadedBytes = SaplingParams.spendParamsSize;
    onProgress(downloadedBytes / totalSize);

    await _downloadParamIfNeeded(
      url: SaplingParams.outputParamsUrl,
      destination: '$path/${SaplingParams.outputParamsFileName}',
      expectedSize: SaplingParams.outputParamsSize,
      expectedHash: SaplingParams.outputParamsHash,
      onDownloaded: (bytes) {
        onProgress((downloadedBytes + bytes) / totalSize);
      },
    );

    onProgress(1.0);
    _provingParamsPath = path;
  }

  Future<void> _downloadParamIfNeeded({
    required String url,
    required String destination,
    required int expectedSize,
    required String expectedHash,
    required void Function(int bytesDownloaded) onDownloaded,
  }) async {
    final destinationFile = File(destination);
    if (await _verifyParamFile(
      file: destinationFile,
      expectedSize: expectedSize,
      expectedHash: expectedHash,
    )) {
      onDownloaded(expectedSize);
      return;
    }

    if (await destinationFile.exists()) {
      await destinationFile.delete();
    }

    await _downloadFileAtomically(
      url: url,
      destination: destination,
      expectedSize: expectedSize,
      expectedHash: expectedHash,
      onProgress: onDownloaded,
    );
  }

  Future<bool> _verifyParamFile({
    required File file,
    required int expectedSize,
    required String expectedHash,
  }) async {
    try {
      if (!await file.exists()) return false;

      final size = await file.length();
      if (size != expectedSize) return false;

      final bytes = await file.readAsBytes();
      final hash = hex.encode(QuickCrypto.sha256Hash(bytes));
      return hash == expectedHash;
    } catch (_) {
      return false;
    }
  }

  /// Download a file through Cake's proxy/Tor wrapper, verify it, then rename.
  Future<void> _downloadFileAtomically({
    required String url,
    required String destination,
    required int expectedSize,
    required String expectedHash,
    required void Function(int bytesDownloaded) onProgress,
  }) async {
    final destinationFile = File(destination);
    final tempFile = File('$destination.download');
    final uri = Uri.parse(url);

    if (await tempFile.exists()) {
      await tempFile.delete();
    }

    final response = await ProxyWrapper().get(clearnetUri: uri);
    if (response.statusCode != 200) {
      throw Exception(
          'PIVX Sapling proving parameter download failed with HTTP ${response.statusCode}');
    }

    final bytes = response.bodyBytes;
    onProgress(bytes.length);

    if (bytes.length != expectedSize) {
      throw Exception(
          'PIVX Sapling proving parameter size mismatch after download');
    }

    final hash = hex.encode(QuickCrypto.sha256Hash(bytes));
    if (hash != expectedHash) {
      throw Exception(
          'PIVX Sapling proving parameter hash mismatch after download');
    }

    await tempFile.writeAsBytes(bytes, flush: true);

    if (!await _verifyParamFile(
      file: tempFile,
      expectedSize: expectedSize,
      expectedHash: expectedHash,
    )) {
      await tempFile.delete();
      throw Exception(
          'PIVX Sapling proving parameter verification failed after write');
    }

    if (await destinationFile.exists()) {
      await destinationFile.delete();
    }
    await tempFile.rename(destination);
  }

  /// Build a shielded-to-shielded transaction.
  Future<SaplingTransactionResult> buildTransaction({
    required SaplingTransactionOptions options,
  }) async {
    if (options.amount < PivxFeePolicy.shieldedDustThreshold) {
      throw Exception('Amount below PIVX shielded dust threshold');
    }

    // Validate we have sufficient balance
    if (syncEngine.balance < options.amount) {
      throw Exception('Insufficient shielded balance');
    }

    // Validate we have proving params
    if (!hasProvingParams) {
      throw Exception(
          'Proving parameters not loaded. Call loadProvingParams first.');
    }

    // Validate address format based on network
    if (!keyManager.validateAddress(options.toAddress)) {
      throw Exception('Invalid destination address');
    }

    // Get spendable notes from Rust sync state (includes rseed and address data)
    final syncHandle = syncEngine.nativeSyncHandle;
    final spendableNullifiers = syncEngine.storage
        .spendableNotesAt(
          chainHeight: syncEngine.storage.lastSyncedHeight,
        )
        .map((note) => note.nullifier)
        .whereType<String>()
        .toSet();
    final allNotes = ffi
        .getSpendableNotes(syncHandle)
        .where((note) => spendableNullifiers.contains(note['nullifier']))
        .toList(growable: false);

    if (allNotes.isEmpty) {
      throw Exception('No spendable notes available');
    }

    final selectedNotes = selectNotesForAmount(
      allNotes,
      options.amount,
      spendAll: options.spendAllShieldedInputs,
    );
    if (selectedNotes.isEmpty) {
      throw Exception('Could not select sufficient notes');
    }

    final totalInput =
        selectedNotes.fold<int>(0, (sum, n) => sum + (n['value'] as int));
    final spendPlan = planShieldedSpend(
      totalInput: totalInput,
      amount: options.amount,
      saplingInputs: selectedNotes.length,
    );
    final fee = spendPlan.fee;

    // Verify we have enough after fee
    if (!spendPlan.canBuild || totalInput < options.amount + fee) {
      throw Exception('Insufficient balance after fee');
    }

    printV('[PIVX Sapling] Shielded note selection complete');

    // Get current anchor once and require every witness to be bound to it.
    printV('[PIVX Sapling] Getting anchor...');
    final anchorResult = await syncEngine.getBestAnchor();
    printV('[PIVX Sapling] Got spend anchor');

    // Get witnesses for selected notes from ElectrumX
    printV('[PIVX Sapling] Fetching witnesses...');
    final notesWithWitnesses =
        await _fetchWitnesses(selectedNotes, anchorResult);
    printV('[PIVX Sapling] Witnesses fetched');

    // Get native key handle
    final keyHandle = keyManager._manager.nativeKeys.handle;

    // Build JSON for notes (already has rseed, address, nullifier from Rust)
    final notesJson = jsonEncode(notesWithWitnesses);
    printV('[PIVX Sapling] Building shielded transaction');

    // Call FFI to build transaction
    // Call FFI to build transaction
    printV(
        '[PIVX Sapling] Calling FFI buildShieldedTransaction (this may take 30-60 seconds for proving)...');
    final result = ffi.buildShieldedTransaction(
      keyHandle: keyHandle,
      notesJson: notesJson,
      toAddress: options.toAddress,
      amount: options.amount,
      memo: options.memo,
      fee: fee,
      anchorHex: anchorResult.anchor,
    );
    printV('[PIVX Sapling] FFI transaction build returned');

    if (result['status'] == 'error') {
      throw Exception('PIVX shielded transaction build failed');
    }

    final txHex = result['tx_hex'] as String;
    final txid = result['txid'] as String;

    return SaplingTransactionResult(
      rawTx: Uint8List.fromList(hex.decode(txHex)),
      txHex: txHex,
      txId: txid,
      fee: fee,
      spentNullifiers: selectedNotes
          .map((note) => note['nullifier'] as String?)
          .whereType<String>()
          .toList(growable: false),
    );
  }

  /// Select notes to cover the required amount plus its fee.
  static List<Map<String, dynamic>> selectNotesForAmount(
    List<Map<String, dynamic>> allNotes,
    int amount, {
    bool spendAll = false,
  }) {
    // Sort by value descending to minimize number of inputs
    final sorted = List<Map<String, dynamic>>.from(allNotes)
      ..sort((a, b) => (b['value'] as int).compareTo(a['value'] as int));

    if (spendAll) {
      return sorted;
    }

    final selected = <Map<String, dynamic>>[];
    var total = 0;

    for (final note in sorted) {
      selected.add(note);
      total += note['value'] as int;
      if (planShieldedSpend(
        totalInput: total,
        amount: amount,
        saplingInputs: selected.length,
      ).canBuild) {
        break;
      }
    }

    return selected;
  }

  static ShieldedSpendPlan planShieldedSpend({
    required int totalInput,
    required int amount,
    required int saplingInputs,
  }) {
    final noChangeFee = PivxFeePolicy.saplingFee(
      saplingInputs: saplingInputs,
      saplingOutputs: 1,
    );

    if (totalInput < amount + noChangeFee) {
      return ShieldedSpendPlan(fee: noChangeFee, change: 0, canBuild: false);
    }

    final noChangeRemainder = totalInput - amount - noChangeFee;
    if (noChangeRemainder <= PivxFeePolicy.shieldedDustThreshold) {
      return ShieldedSpendPlan(
        fee: noChangeFee + noChangeRemainder,
        change: 0,
        canBuild: true,
      );
    }

    final withChangeFee = PivxFeePolicy.saplingFee(
      saplingInputs: saplingInputs,
      saplingOutputs: 2,
    );
    if (totalInput < amount + withChangeFee) {
      return ShieldedSpendPlan(
        fee: withChangeFee,
        change: 0,
        canBuild: false,
      );
    }

    final change = totalInput - amount - withChangeFee;
    if (change <= PivxFeePolicy.shieldedDustThreshold) {
      return ShieldedSpendPlan(
        fee: withChangeFee + change,
        change: 0,
        canBuild: true,
      );
    }

    return ShieldedSpendPlan(
      fee: withChangeFee,
      change: change,
      canBuild: true,
    );
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
    BestAnchorResult anchorResult,
  ) async {
    final result = <Map<String, dynamic>>[];

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

        // Fetch witness from ElectrumX and require it to match the selected
        // anchor that will be passed into FFI signing.
        printV('[PIVX] Fetching shielded witness');
        final witness = await syncEngine.saplingClient.getAnchorBoundWitness(
          commitment: cmu,
          anchor: anchorResult,
        );

        final notePosition = note['position'] as int?;
        if (notePosition != null && witness.position != notePosition) {
          throw SaplingRpcException(
              'PIVX Sapling witness position does not match selected note');
        }

        printV('[PIVX] Got anchor-bound witness response');
        // Serialize path as hex-encoded concatenated hashes for the current
        // FFI transaction builder contract.
        noteWithWitness['witness'] = witness.path.join('');
        noteWithWitness['witness_position'] = witness.position;
        noteWithWitness['anchor'] = witness.anchor;
        noteWithWitness['anchor_height'] = witness.anchorHeight;
      } catch (e) {
        printV('[PIVX] Failed to fetch witness');
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
        'Shielding transaction building not yet implemented.');
  }

  /// Build a deshielding transaction (z→t).
  Future<SaplingTransactionResult> buildDeshieldingTransaction({
    required String toTransparentAddress,
    required int amount,
  }) async {
    // TODO: Implement shielded-to-transparent transaction
    throw UnimplementedError(
        'Deshielding transaction building not yet implemented.');
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
  final bool spendAllShieldedInputs;

  SaplingTransactionOptions({
    required this.toAddress,
    required this.amount,
    this.memo,
    this.useShieldedInputs = true,
    this.spendAllShieldedInputs = false,
  });
}

class ShieldedSpendPlan {
  ShieldedSpendPlan({
    required this.fee,
    required this.change,
    required this.canBuild,
  });

  final int fee;
  final int change;
  final bool canBuild;
}

/// Transaction result.
class SaplingTransactionResult {
  final Uint8List rawTx;
  final String txHex;
  final String txId;
  final int fee;
  final List<String> spentNullifiers;

  SaplingTransactionResult({
    required this.rawTx,
    required this.txHex,
    required this.txId,
    required this.fee,
    this.spentNullifiers = const [],
  });
}
