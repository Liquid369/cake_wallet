/// Native implementation of Sapling key manager.
/// 
/// This implementation uses the Rust FFI bindings for actual
/// cryptographic operations.

import 'dart:typed_data';
import 'package:cw_pivx/src/sapling/sapling_constants.dart';
import 'package:cw_pivx/src/sapling/sapling_ffi.dart' as ffi;

/// Native Sapling key manager using Rust FFI.
/// 
/// This is a simpler implementation that provides the core key operations
/// without implementing the full abstract interface. The factories wrap
/// this to provide the full wallet interface.
class NativeSaplingKeyManager {
  final ffi.SaplingKeys _keys;
  final bool _isTestnet;
  int _nextDiversifierIndex = 0;
  
  NativeSaplingKeyManager._(this._keys, this._isTestnet);
  
  /// Create from a seed.
  static Future<NativeSaplingKeyManager> fromSeed(
    Uint8List seed, {
    bool isTestnet = false,
  }) async {
    final keys = ffi.SaplingKeys.fromSeed(seed, isTestnet: isTestnet);
    return NativeSaplingKeyManager._(keys, isTestnet);
  }
  
  /// Get the default shielded address.
  Future<String> getDefaultAddress() async {
    return _keys.getDefaultAddress();
  }
  
  /// Derive an address at a specific diversifier index.
  Future<String> deriveAddress(int index) async {
    return _keys.deriveAddress(index);
  }
  
  /// Get the next address (incrementing index).
  Future<String> getNextAddress() async {
    final address = _keys.deriveAddress(_nextDiversifierIndex);
    _nextDiversifierIndex++;
    return address;
  }
  
  /// Get the full viewing key.
  Future<String> getFullViewingKey() async {
    return _keys.getViewingKey();
  }
  
  /// Validate an address.
  bool validateAddress(String address) {
    return ffi.validateAddress(address, isTestnet: _isTestnet);
  }
  
  /// Check if testnet.
  bool get isTestnet => _isTestnet;
  
  /// Get the payment address HRP.
  String get paymentAddressHrp => 
    _isTestnet ? PivxSaplingNetwork.testnetPaymentAddressHrp : PivxSaplingNetwork.mainnetPaymentAddressHrp;
  
  /// Dispose the key manager.
  void dispose() {
    _keys.dispose();
  }
  
  /// Get the native keys handle (internal use).
  ffi.SaplingKeys get nativeKeys => _keys;
}
