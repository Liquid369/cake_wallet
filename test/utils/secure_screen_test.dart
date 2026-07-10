import 'package:cake_wallet/utils/secure_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(SecureScreenNativeScope.resetForTest);

  group('SecureScreenNativeScope', () {
    test('enables native secure mode for the first active scope only', () {
      final calls = <bool>[];
      SecureScreenNativeScope.setNativeSetterForTest(calls.add);

      SecureScreenNativeScope.enter();
      SecureScreenNativeScope.enter();

      expect(calls, <bool>[true]);
      expect(SecureScreenNativeScope.activeScopes, 2);
    });

    test('restores native secure mode only after the final scope exits', () {
      final calls = <bool>[];
      SecureScreenNativeScope.setNativeSetterForTest(calls.add);

      SecureScreenNativeScope.enter();
      SecureScreenNativeScope.enter();
      SecureScreenNativeScope.exit(restoreTo: false);
      SecureScreenNativeScope.exit(restoreTo: false);

      expect(calls, <bool>[true, false]);
      expect(SecureScreenNativeScope.activeScopes, 0);
    });

    test('restores to the current persisted secure-screen setting', () {
      final calls = <bool>[];
      SecureScreenNativeScope.setNativeSetterForTest(calls.add);

      SecureScreenNativeScope.enter();
      SecureScreenNativeScope.exit(restoreTo: true);

      expect(calls, <bool>[true, true]);
    });

    test('ignores unmatched exits', () {
      final calls = <bool>[];
      SecureScreenNativeScope.setNativeSetterForTest(calls.add);

      SecureScreenNativeScope.exit(restoreTo: false);

      expect(calls, isEmpty);
      expect(SecureScreenNativeScope.activeScopes, 0);
    });
  });
}
