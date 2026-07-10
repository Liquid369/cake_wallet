import 'dart:async';

import 'package:cw_core/set_app_secure_native.dart';
import 'package:flutter/foundation.dart';

typedef SecureScreenSetter = FutureOr<void> Function(bool isSecure);

class SecureScreenNativeScope {
  static int _activeScopes = 0;
  static SecureScreenSetter _setNative = setIsAppSecureNative;

  static int get activeScopes => _activeScopes;

  static void enter() {
    if (_activeScopes++ == 0) {
      unawaited(Future<void>.sync(() => _setNative(true)));
    }
  }

  static void exit({required bool restoreTo}) {
    if (_activeScopes == 0) {
      return;
    }

    _activeScopes--;

    if (_activeScopes == 0) {
      unawaited(Future<void>.sync(() => _setNative(restoreTo)));
    }
  }

  @visibleForTesting
  static void setNativeSetterForTest(SecureScreenSetter setter) {
    _setNative = setter;
  }

  @visibleForTesting
  static void resetForTest() {
    _activeScopes = 0;
    _setNative = setIsAppSecureNative;
  }
}
