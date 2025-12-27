/// PIVX Sapling FFI bindings.
/// 
/// This module provides Dart bindings to the native Rust library for
/// PIVX Sapling shielded transaction support.

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

/// FFI buffer structure matching Rust's FFIBuffer.
class FFIBuffer extends Struct {
  external Pointer<Uint8> data;
  
  @Size()
  external int len;
}

/// Load the native PIVX Sapling library.
DynamicLibrary _loadLibrary() {
  if (Platform.isAndroid) {
    return DynamicLibrary.open('libcw_pivx_sapling.so');
  } else if (Platform.isIOS) {
    // On iOS, the Rust static library is force-loaded into cw_pivx.framework
    // First try the framework, then fall back to process lookup
    try {
      final lib = DynamicLibrary.open('cw_pivx.framework/cw_pivx');
      // Verify symbols are present
      lib.lookup('cw_pivx_version');
      return lib;
    } catch (e) {
      // Fall back to process lookup (symbols may be linked into main binary)
      return DynamicLibrary.process();
    }
  } else if (Platform.isMacOS) {
    return DynamicLibrary.open('libcw_pivx_sapling.dylib');
  } else if (Platform.isLinux) {
    return DynamicLibrary.open('libcw_pivx_sapling.so');
  } else if (Platform.isWindows) {
    return DynamicLibrary.open('cw_pivx_sapling.dll');
  }
  throw UnsupportedError('Unsupported platform: ${Platform.operatingSystem}');
}

/// Native library instance.
late final DynamicLibrary _nativeLib;
bool _nativeLibLoaded = false;
String? _nativeLibError;

/// Check if the native library is available.
bool get isSaplingFFIAvailable {
  _ensureLoaded();
  return _nativeLibLoaded;
}

/// Get any error from library loading.
String? get saplingFFIError => _nativeLibError;

void _ensureLoaded() {
  if (_nativeLibLoaded) return;
  try {
    _nativeLib = _loadLibrary();
    _nativeLibLoaded = true;
  } catch (e) {
    _nativeLibError = e.toString();
  }
}

// ============================================================================
// FFI Function Typedefs
// ============================================================================

// String management
typedef _FreeStringC = Void Function(Pointer<Utf8>);
typedef _FreeStringDart = void Function(Pointer<Utf8>);

typedef _FreeBufferC = Void Function(FFIBuffer);
typedef _FreeBufferDart = void Function(FFIBuffer);

// Error handling
typedef _GetLastErrorC = Pointer<Utf8> Function();
typedef _GetLastErrorDart = Pointer<Utf8> Function();

// Version
typedef _VersionC = Pointer<Utf8> Function();
typedef _VersionDart = Pointer<Utf8> Function();

// Key management
typedef _InitKeysC = Int64 Function(Pointer<Uint8> seed, Size seedLen, Uint8 isTestnet);
typedef _InitKeysDart = int Function(Pointer<Uint8> seed, int seedLen, int isTestnet);

typedef _DisposeKeysC = Void Function(Int64 handle);
typedef _DisposeKeysDart = void Function(int handle);

typedef _GetDefaultAddressC = Pointer<Utf8> Function(Int64 handle);
typedef _GetDefaultAddressDart = Pointer<Utf8> Function(int handle);

typedef _DeriveAddressC = Pointer<Utf8> Function(Int64 handle, Uint64 index);
typedef _DeriveAddressDart = Pointer<Utf8> Function(int handle, int index);

typedef _GetViewingKeyC = Pointer<Utf8> Function(Int64 handle);
typedef _GetViewingKeyDart = Pointer<Utf8> Function(int handle);

typedef _ValidateAddressC = Uint8 Function(Pointer<Utf8> address, Uint8 isTestnet);
typedef _ValidateAddressDart = int Function(Pointer<Utf8> address, int isTestnet);

// Sync engine
typedef _InitSyncEngineC = Int64 Function(Uint8 isTestnet);
typedef _InitSyncEngineDart = int Function(int isTestnet);

typedef _DisposeSyncEngineC = Void Function(Int64 handle);
typedef _DisposeSyncEngineDart = void Function(int handle);

typedef _GetSyncHeightC = Uint32 Function(Int64 handle);
typedef _GetSyncHeightDart = int Function(int handle);

typedef _GetShieldedBalanceC = Uint64 Function(Int64 handle);
typedef _GetShieldedBalanceDart = int Function(int handle);

typedef _GetUnspentNoteCountC = Size Function(Int64 handle);
typedef _GetUnspentNoteCountDart = int Function(int handle);

typedef _ResetSyncC = Void Function(Int64 handle);
typedef _ResetSyncDart = void Function(int handle);

// Trial decryption for detecting incoming shielded transactions
typedef _TryDecryptOutputC = Uint64 Function(
  Int64 keyHandle,
  Int64 syncHandle,
  Pointer<Uint8> cmu,
  Pointer<Uint8> epk,
  Pointer<Uint8> encCiphertext,
  Uint32 height,
  Uint32 txIndex,
  Uint32 outputIndex,
  Uint64 position,
);
typedef _TryDecryptOutputDart = int Function(
  int keyHandle,
  int syncHandle,
  Pointer<Uint8> cmu,
  Pointer<Uint8> epk,
  Pointer<Uint8> encCiphertext,
  int height,
  int txIndex,
  int outputIndex,
  int position,
);

// Check nullifier (mark notes as spent)
typedef _CheckNullifierC = Uint8 Function(Int64 syncHandle, Pointer<Uint8> nullifier);
typedef _CheckNullifierDart = int Function(int syncHandle, Pointer<Uint8> nullifier);

// Set sync height
typedef _SetSyncHeightC = Void Function(Int64 syncHandle, Uint32 height);
typedef _SetSyncHeightDart = void Function(int syncHandle, int height);

// Fee estimation
typedef _EstimateFeeC = Uint64 Function(Size spends, Size outputs, Size tInputs, Size tOutputs);
typedef _EstimateFeeDart = int Function(int spends, int outputs, int tInputs, int tOutputs);

// Prover management
typedef _InitProverC = Int32 Function(Pointer<Utf8> paramsDir);
typedef _InitProverDart = int Function(Pointer<Utf8> paramsDir);

typedef _IsProverInitializedC = Uint8 Function();
typedef _IsProverInitializedDart = int Function();

typedef _DisposeProverC = Void Function();
typedef _DisposeProverDart = void Function();

typedef _HasProvingParamsC = Uint8 Function(Pointer<Utf8> path);
typedef _HasProvingParamsDart = int Function(Pointer<Utf8> path);

// Transaction building
typedef _CreateTransactionC = FFIBuffer Function(
  Int64 keyHandle,
  Int64 syncHandle,
  Pointer<Utf8> toAddress,
  Uint64 amount,
  Pointer<Utf8> memo,
  Uint32 height,
  Pointer<Utf8> provingParamsPath,
);
typedef _CreateTransactionDart = FFIBuffer Function(
  int keyHandle,
  int syncHandle,
  Pointer<Utf8> toAddress,
  int amount,
  Pointer<Utf8> memo,
  int height,
  Pointer<Utf8> provingParamsPath,
);

// Advanced transaction building with explicit notes/witnesses
typedef _BuildShieldedTxC = FFIBuffer Function(
  Int64 keyHandle,
  Pointer<Utf8> notesJson,
  Pointer<Utf8> toAddress,
  Uint64 amount,
  Pointer<Utf8> memo,
  Uint64 fee,
  Pointer<Utf8> anchorHex,
);
typedef _BuildShieldedTxDart = FFIBuffer Function(
  int keyHandle,
  Pointer<Utf8> notesJson,
  Pointer<Utf8> toAddress,
  int amount,
  Pointer<Utf8> memo,
  int fee,
  Pointer<Utf8> anchorHex,
);

// ============================================================================
// FFI Function Bindings
// ============================================================================

late final _freeString = _nativeLib
    .lookupFunction<_FreeStringC, _FreeStringDart>('cw_pivx_free_string');

late final _freeBuffer = _nativeLib
    .lookupFunction<_FreeBufferC, _FreeBufferDart>('cw_pivx_free_buffer');

late final _getLastError = _nativeLib
    .lookupFunction<_GetLastErrorC, _GetLastErrorDart>('cw_pivx_get_last_error');

late final _version = _nativeLib
    .lookupFunction<_VersionC, _VersionDart>('cw_pivx_version');

late final _initKeys = _nativeLib
    .lookupFunction<_InitKeysC, _InitKeysDart>('cw_pivx_init_keys');

late final _disposeKeys = _nativeLib
    .lookupFunction<_DisposeKeysC, _DisposeKeysDart>('cw_pivx_dispose_keys');

late final _getDefaultAddress = _nativeLib
    .lookupFunction<_GetDefaultAddressC, _GetDefaultAddressDart>('cw_pivx_get_default_address');

late final _deriveAddress = _nativeLib
    .lookupFunction<_DeriveAddressC, _DeriveAddressDart>('cw_pivx_derive_address');

late final _getViewingKey = _nativeLib
    .lookupFunction<_GetViewingKeyC, _GetViewingKeyDart>('cw_pivx_get_viewing_key');

late final _validateAddress = _nativeLib
    .lookupFunction<_ValidateAddressC, _ValidateAddressDart>('cw_pivx_validate_address');

late final _initSyncEngine = _nativeLib
    .lookupFunction<_InitSyncEngineC, _InitSyncEngineDart>('cw_pivx_init_sync_engine');

late final _disposeSyncEngine = _nativeLib
    .lookupFunction<_DisposeSyncEngineC, _DisposeSyncEngineDart>('cw_pivx_dispose_sync_engine');

late final _getSyncHeight = _nativeLib
    .lookupFunction<_GetSyncHeightC, _GetSyncHeightDart>('cw_pivx_get_sync_height');

late final _getShieldedBalance = _nativeLib
    .lookupFunction<_GetShieldedBalanceC, _GetShieldedBalanceDart>('cw_pivx_get_shielded_balance');

late final _getUnspentNoteCount = _nativeLib
    .lookupFunction<_GetUnspentNoteCountC, _GetUnspentNoteCountDart>('cw_pivx_get_unspent_note_count');

late final _resetSync = _nativeLib
    .lookupFunction<_ResetSyncC, _ResetSyncDart>('cw_pivx_reset_sync');

late final _tryDecryptOutput = _nativeLib
    .lookupFunction<_TryDecryptOutputC, _TryDecryptOutputDart>('cw_pivx_try_decrypt_output');

late final _checkNullifier = _nativeLib
    .lookupFunction<_CheckNullifierC, _CheckNullifierDart>('cw_pivx_check_nullifier');

late final _setSyncHeight = _nativeLib
    .lookupFunction<_SetSyncHeightC, _SetSyncHeightDart>('cw_pivx_set_sync_height');

late final _estimateFee = _nativeLib
    .lookupFunction<_EstimateFeeC, _EstimateFeeDart>('cw_pivx_estimate_fee');

late final _initProver = _nativeLib
    .lookupFunction<_InitProverC, _InitProverDart>('cw_pivx_init_prover');

late final _isProverInitialized = _nativeLib
    .lookupFunction<_IsProverInitializedC, _IsProverInitializedDart>('cw_pivx_is_prover_initialized');

late final _disposeProver = _nativeLib
    .lookupFunction<_DisposeProverC, _DisposeProverDart>('cw_pivx_dispose_prover');

late final _createTransaction = _nativeLib
    .lookupFunction<_CreateTransactionC, _CreateTransactionDart>('cw_pivx_create_transaction');

late final _buildShieldedTx = _nativeLib
    .lookupFunction<_BuildShieldedTxC, _BuildShieldedTxDart>('cw_pivx_build_shielded_tx');

late final _hasProvingParams = _nativeLib
    .lookupFunction<_HasProvingParamsC, _HasProvingParamsDart>('cw_pivx_has_proving_params');

// Get spendable notes from sync state
typedef _GetSpendableNotesC = Pointer<Utf8> Function(Int64 syncHandle);
typedef _GetSpendableNotesDart = Pointer<Utf8> Function(int syncHandle);

late final _getSpendableNotes = _nativeLib
    .lookupFunction<_GetSpendableNotesC, _GetSpendableNotesDart>('cw_pivx_get_spendable_notes');

// Restore a note from JSON
typedef _RestoreNoteC = Int32 Function(Int64 keyHandle, Int64 syncHandle, Pointer<Utf8> noteJson);
typedef _RestoreNoteDart = int Function(int keyHandle, int syncHandle, Pointer<Utf8> noteJson);

late final _restoreNote = _nativeLib
    .lookupFunction<_RestoreNoteC, _RestoreNoteDart>('cw_pivx_restore_note');

// ============================================================================
// High-Level API
// ============================================================================

/// Get the last error message from the native library.
String? getLastError() {
  _ensureLoaded();
  if (!_nativeLibLoaded) return _nativeLibError;
  
  final ptr = _getLastError();
  if (ptr == nullptr) return null;
  
  final error = ptr.toDartString();
  _freeString(ptr);
  return error;
}

/// Get the library version.
String getVersion() {
  _ensureLoaded();
  if (!_nativeLibLoaded) return 'not loaded';
  
  final ptr = _version();
  if (ptr == nullptr) return 'unknown';
  
  final version = ptr.toDartString();
  _freeString(ptr);
  return version;
}

/// Validate a PIVX shielded address.
bool validateAddress(String address, {bool isTestnet = false}) {
  _ensureLoaded();
  if (!_nativeLibLoaded) return false;
  
  final addressPtr = address.toNativeUtf8();
  try {
    return _validateAddress(addressPtr, isTestnet ? 1 : 0) == 1;
  } finally {
    malloc.free(addressPtr);
  }
}

/// Estimate transaction fee.
int estimateFee({
  int numSpends = 0,
  int numOutputs = 0,
  int numTransparentInputs = 0,
  int numTransparentOutputs = 0,
}) {
  return _estimateFee(numSpends, numOutputs, numTransparentInputs, numTransparentOutputs);
}

/// Check if proving parameters are available.
bool hasProvingParams(String path) {
  final pathPtr = path.toNativeUtf8();
  try {
    return _hasProvingParams(pathPtr) == 1;
  } finally {
    malloc.free(pathPtr);
  }
}

/// Initialize the Groth16 prover with proving parameters.
/// 
/// This loads the ~50MB parameter files into memory.
/// Should be called once before any transaction building.
/// 
/// Returns true on success, false on failure.
/// Check [getLastError] for details on failure.
bool initProver(String paramsDir) {
  _ensureLoaded();
  if (!_nativeLibLoaded) return false;
  
  final dirPtr = paramsDir.toNativeUtf8();
  try {
    return _initProver(dirPtr) == 0;
  } finally {
    malloc.free(dirPtr);
  }
}

/// Check if the prover is initialized.
bool isProverInitialized() {
  _ensureLoaded();
  if (!_nativeLibLoaded) return false;
  return _isProverInitialized() == 1;
}

/// Free the prover and release memory (~50MB).
void disposeProver() {
  _ensureLoaded();
  if (!_nativeLibLoaded) return;
  _disposeProver();
}

/// Get all spendable notes from the sync state as JSON.
/// 
/// Returns a list of note data objects with all fields needed
/// for transaction building.
List<Map<String, dynamic>> getSpendableNotes(int syncHandle) {
  _ensureLoaded();
  if (!_nativeLibLoaded) return [];
  
  final ptr = _getSpendableNotes(syncHandle);
  if (ptr == nullptr) {
    return [];
  }
  
  try {
    final jsonStr = ptr.toDartString();
    final list = jsonDecode(jsonStr) as List<dynamic>;
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  } finally {
    _freeString(ptr);
  }
}

/// Restore a note from JSON data.
/// 
/// This allows restoring notes from persistent storage after app restart.
/// The JSON should contain the same fields returned by getSpendableNotes.
/// 
/// Returns true on success, false on failure.
bool restoreNote({
  required int keyHandle,
  required int syncHandle,
  required Map<String, dynamic> noteData,
}) {
  _ensureLoaded();
  if (!_nativeLibLoaded) return false;
  
  final jsonStr = jsonEncode(noteData);
  final jsonPtr = jsonStr.toNativeUtf8();
  
  try {
    return _restoreNote(keyHandle, syncHandle, jsonPtr) == 1;
  } finally {
    malloc.free(jsonPtr);
  }
}

/// Build a shielded transaction with explicit notes and witnesses.
/// 
/// [keyHandle] - Handle from SaplingKeys
/// [notesJson] - JSON array of SpendableNoteData objects
/// [toAddress] - Recipient Sapling address (ps1...)
/// [amount] - Amount to send in zatoshis
/// [memo] - Optional memo (max 512 bytes)
/// [fee] - Transaction fee in zatoshis
/// [anchorHex] - 32-byte merkle root as hex string
/// 
/// Returns a Map with transaction details or throws on error.
Map<String, dynamic> buildShieldedTransaction({
  required int keyHandle,
  required String notesJson,
  required String toAddress,
  required int amount,
  String? memo,
  required int fee,
  required String anchorHex,
}) {
  _ensureLoaded();
  if (!_nativeLibLoaded) {
    throw Exception('Native library not available: $_nativeLibError');
  }
  
  final notesPtr = notesJson.toNativeUtf8();
  final toPtr = toAddress.toNativeUtf8();
  final memoPtr = memo?.toNativeUtf8() ?? nullptr;
  final anchorPtr = anchorHex.toNativeUtf8();
  
  try {
    final buffer = _buildShieldedTx(
      keyHandle,
      notesPtr,
      toPtr,
      amount,
      memoPtr,
      fee,
      anchorPtr,
    );
    
    if (buffer.data == nullptr || buffer.len == 0) {
      throw Exception(getLastError() ?? 'Failed to build transaction');
    }
    
    // Parse result JSON
    final resultStr = buffer.data.cast<Utf8>().toDartString(length: buffer.len);
    _freeBuffer(buffer);
    
    return Map<String, dynamic>.from(
      (const JsonDecoder().convert(resultStr)) as Map,
    );
  } finally {
    malloc.free(notesPtr);
    malloc.free(toPtr);
    if (memoPtr != nullptr) {
      malloc.free(memoPtr);
    }
    malloc.free(anchorPtr);
  }
}

/// PIVX Sapling key manager handle.
/// 
/// Manages shielded keys derived from a seed.
class SaplingKeys {
  final int _handle;
  bool _disposed = false;
  
  SaplingKeys._(this._handle);
  
  /// Initialize keys from a seed.
  static SaplingKeys fromSeed(Uint8List seed, {bool isTestnet = false}) {
    _ensureLoaded();
    if (!_nativeLibLoaded) {
      throw Exception('Native library not available: $_nativeLibError');
    }
    
    final seedPtr = malloc<Uint8>(seed.length);
    try {
      seedPtr.asTypedList(seed.length).setAll(0, seed);
      
      final handle = _initKeys(seedPtr, seed.length, isTestnet ? 1 : 0);
      if (handle < 0) {
        throw Exception(getLastError() ?? 'Failed to initialize keys');
      }
      
      return SaplingKeys._(handle);
    } finally {
      malloc.free(seedPtr);
    }
  }
  
  /// Get the default shielded address.
  String getDefaultAddress() {
    _checkDisposed();
    
    final ptr = _getDefaultAddress(_handle);
    if (ptr == nullptr) {
      throw Exception(getLastError() ?? 'Failed to get address');
    }
    
    final address = ptr.toDartString();
    _freeString(ptr);
    return address;
  }
  
  /// Derive an address at a specific diversifier index.
  String deriveAddress(int index) {
    _checkDisposed();
    
    final ptr = _deriveAddress(_handle, index);
    if (ptr == nullptr) {
      throw Exception(getLastError() ?? 'Failed to derive address');
    }
    
    final address = ptr.toDartString();
    _freeString(ptr);
    return address;
  }
  
  /// Get the full viewing key (for watch-only wallets).
  String getViewingKey() {
    _checkDisposed();
    
    final ptr = _getViewingKey(_handle);
    if (ptr == nullptr) {
      throw Exception(getLastError() ?? 'Failed to get viewing key');
    }
    
    final key = ptr.toDartString();
    _freeString(ptr);
    return key;
  }
  
  /// Dispose the key manager.
  void dispose() {
    if (!_disposed) {
      _disposeKeys(_handle);
      _disposed = true;
    }
  }
  
  void _checkDisposed() {
    if (_disposed) {
      throw StateError('SaplingKeys has been disposed');
    }
  }
  
  /// Get the native handle (for internal use).
  int get handle {
    _checkDisposed();
    return _handle;
  }
}

/// PIVX Sapling sync engine handle.
/// 
/// Manages blockchain synchronization and note tracking.
class SaplingSyncEngine {
  final int _handle;
  bool _disposed = false;
  
  SaplingSyncEngine._(this._handle);
  
  /// Get the native handle for direct FFI calls.
  int get handle => _handle;
  
  /// Create a new sync engine.
  factory SaplingSyncEngine({bool isTestnet = false}) {
    final handle = _initSyncEngine(isTestnet ? 1 : 0);
    if (handle < 0) {
      throw Exception(getLastError() ?? 'Failed to initialize sync engine');
    }
    return SaplingSyncEngine._(handle);
  }
  
  /// Get the current sync height.
  int get syncHeight {
    _checkDisposed();
    return _getSyncHeight(_handle);
  }
  
  /// Get the shielded balance (in satoshis).
  int get shieldedBalance {
    _checkDisposed();
    return _getShieldedBalance(_handle);
  }
  
  /// Get the number of unspent notes.
  int get unspentNoteCount {
    _checkDisposed();
    return _getUnspentNoteCount(_handle);
  }
  
  /// Reset the sync engine (for rescan).
  void reset() {
    _checkDisposed();
    _resetSync(_handle);
  }
  
  /// Set the current sync height.
  void setSyncHeight(int height) {
    _checkDisposed();
    _setSyncHeight(_handle, height);
  }
  
  /// Try to decrypt a Sapling output.
  /// 
  /// This is the core function for detecting incoming shielded transactions.
  /// It attempts trial decryption of a Sapling output using the wallet's
  /// incoming viewing key.
  /// 
  /// Returns the note value in zatoshis if decryption succeeds, 0 otherwise.
  int tryDecryptOutput({
    required SaplingKeys keys,
    required Uint8List cmu,
    required Uint8List epk,
    required Uint8List encCiphertext,
    required int height,
    required int txIndex,
    required int outputIndex,
    required int position,
  }) {
    _checkDisposed();
    
    if (cmu.length != 32) throw ArgumentError('cmu must be 32 bytes');
    if (epk.length != 32) throw ArgumentError('epk must be 32 bytes');
    if (encCiphertext.length != 580) throw ArgumentError('encCiphertext must be 580 bytes');
    
    final cmuPtr = malloc<Uint8>(32);
    final epkPtr = malloc<Uint8>(32);
    final encPtr = malloc<Uint8>(580);
    
    try {
      cmuPtr.asTypedList(32).setAll(0, cmu);
      epkPtr.asTypedList(32).setAll(0, epk);
      encPtr.asTypedList(580).setAll(0, encCiphertext);
      
      final result = _tryDecryptOutput(
        keys.handle,
        _handle,
        cmuPtr,
        epkPtr,
        encPtr,
        height,
        txIndex,
        outputIndex,
        position,
      );
      
      return result;
    } finally {
      malloc.free(cmuPtr);
      malloc.free(epkPtr);
      malloc.free(encPtr);
    }
  }
  
  /// Check if a nullifier matches any of our notes and mark them spent.
  /// 
  /// Returns true if a note was marked spent.
  bool checkNullifier(Uint8List nullifier) {
    _checkDisposed();
    
    if (nullifier.length != 32) throw ArgumentError('nullifier must be 32 bytes');
    
    final nullifierPtr = malloc<Uint8>(32);
    try {
      nullifierPtr.asTypedList(32).setAll(0, nullifier);
      return _checkNullifier(_handle, nullifierPtr) == 1;
    } finally {
      malloc.free(nullifierPtr);
    }
  }

  /// Dispose the sync engine.
  void dispose() {
    if (!_disposed) {
      _disposeSyncEngine(_handle);
      _disposed = true;
    }
  }
  
  void _checkDisposed() {
    if (_disposed) {
      throw StateError('SaplingSyncEngine has been disposed');
    }
  }
}

/// Create a shielded transaction.
Uint8List createTransaction({
  required SaplingKeys keys,
  required SaplingSyncEngine syncEngine,
  required String toAddress,
  required int amount,
  String? memo,
  required int height,
  required String provingParamsPath,
}) {
  final toPtr = toAddress.toNativeUtf8();
  final memoPtr = memo?.toNativeUtf8() ?? nullptr;
  final pathPtr = provingParamsPath.toNativeUtf8();
  
  try {
    final buffer = _createTransaction(
      keys.handle,
      syncEngine.handle,
      toPtr,
      amount,
      memoPtr,
      height,
      pathPtr,
    );
    
    if (buffer.data == nullptr || buffer.len == 0) {
      throw Exception(getLastError() ?? 'Failed to create transaction');
    }
    
    // Copy data to Dart
    final result = Uint8List.fromList(
      buffer.data.asTypedList(buffer.len),
    );
    
    // Free native buffer
    _freeBuffer(buffer);
    
    return result;
  } finally {
    malloc.free(toPtr);
    if (memoPtr != nullptr) {
      malloc.free(memoPtr);
    }
    malloc.free(pathPtr);
  }
}
