# PIVX Integration Build Scripts

Build scripts for creating Android APK and iOS builds for PIVX integration testing.

## Prerequisites

### Common Requirements
- Flutter SDK (3.x or later)
- Rust toolchain with cargo
- Git

### Android Requirements
- Android Studio or Android SDK
- Android NDK (r26 or later)
- Java JDK 11+

### iOS Requirements (macOS only)
- Xcode 14.0+
- CocoaPods
- Apple Developer account (for device testing)

## Quick Start

### Android APK Build

```bash
# Debug build (faster, for testing)
./scripts/build_pivx_android_apk.sh debug

# Release build (optimized, requires signing keys)
./scripts/build_pivx_android_apk.sh release
```

**Output:**
- Debug: `build/app/outputs/flutter-apk/app-debug.apk`
- Release: `build/app/outputs/flutter-apk/app-{arch}-release.apk`

**Install on device:**
```bash
# Debug APK
adb install build/app/outputs/flutter-apk/app-debug.apk

# Release APK (ARM64 - most devices)
adb install build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

### iOS Build

```bash
# Debug build (for Xcode/simulator)
./scripts/build_pivx_ios.sh debug

# Release build for development distribution
./scripts/build_pivx_ios.sh release development

# Release build for ad-hoc distribution
./scripts/build_pivx_ios.sh release ad-hoc

# Release build for App Store
./scripts/build_pivx_ios.sh release app-store
```

**Output:**
- Debug: Build artifacts in `build/ios/iphoneos/`
- Release: IPA file in `build/ios/ipa/Runner.ipa`

## Build Process

### Android Build Steps

1. **Build PIVX Rust Library**
   - Compiles Rust code for all Android architectures
   - Creates native libraries: `libcw_pivx_sapling.so`
   - Targets: arm64-v8a, armeabi-v7a, x86_64

2. **Configure Environment**
   - Sets up app version, package name, build number
   - Configures app-specific settings

3. **Clean & Fetch Dependencies**
   - Removes previous build artifacts
   - Downloads Dart/Flutter packages

4. **Generate Code**
   - Generates localization files
   - Runs build_runner for code generation

5. **Build APK**
   - Compiles Dart/Flutter code
   - Links native libraries
   - Creates APK package

### iOS Build Steps

1. **Build PIVX Rust Library**
   - Compiles Rust code for iOS architectures
   - Creates static library: `libcw_pivx_sapling.a`
   - Targets: aarch64-apple-ios, x86_64-apple-ios (simulator)

2. **Install CocoaPods**
   - Installs native iOS dependencies
   - Links frameworks and libraries

3. **Clean & Fetch Dependencies**
   - Removes previous builds
   - Downloads Dart/Flutter packages

4. **Generate Code**
   - Generates localization files
   - Runs build_runner

5. **Build iOS App**
   - Compiles Flutter/iOS code
   - Creates Xcode archive
   - Exports IPA (for release)

## Configuration

### Android Signing (Release Builds)

Create `android/key.properties`:

```properties
storePassword=YOUR_KEYSTORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD
keyAlias=YOUR_KEY_ALIAS
storeFile=/path/to/your/keystore.jks
```

**Generate keystore:**
```bash
keytool -genkey -v -keystore cake-pivx.jks -keyalg RSA \
        -keysize 2048 -validity 10000 -alias cake-pivx-key
```

### iOS Signing (Release Builds)

1. Open `ios/Runner.xcworkspace` in Xcode
2. Select Runner target → Signing & Capabilities
3. Choose your Team
4. Select appropriate Provisioning Profile
5. Update `scripts/build_pivx_ios.sh`:
   - Replace `YOUR_TEAM_ID` with your Apple Team ID

## Distribution

### Android

**Direct Install:**
```bash
adb install path/to/app.apk
```

**Upload to Testing Platforms:**
- Firebase App Distribution
- Google Play Internal Testing
- Diawi (https://www.diawi.com/)
- APKPure, APKMirror

### iOS

**TestFlight (Recommended):**
1. Build with `app-store` export method
2. Upload to App Store Connect
3. Submit for TestFlight review
4. Share with internal/external testers

**Ad-hoc Distribution:**
1. Build with `ad-hoc` export method
2. Register device UDIDs in Apple Developer Portal
3. Distribute IPA via:
   - Diawi (https://www.diawi.com/)
   - TestFairy
   - Direct install via Xcode

**Development Install:**
1. Build with `development` export method
2. Install via Xcode → Devices and Simulators
3. Or run directly: `flutter run --release`

## Troubleshooting

### Android Issues

**"SDK location not found"**
```bash
# Create local.properties
echo "sdk.dir=/path/to/Android/sdk" > android/local.properties
```

**"NDK not found"**
```bash
# Install NDK via Android Studio or:
sdkmanager --install "ndk;26.1.10909125"
```

**Rust build fails**
```bash
# Install Android targets
rustup target add aarch64-linux-android
rustup target add armv7-linux-androideabi
rustup target add x86_64-linux-android
```

### iOS Issues

**"CocoaPods not installed"**
```bash
sudo gem install cocoapods
```

**"No signing certificate found"**
- Open Xcode → Preferences → Accounts
- Add your Apple ID
- Download certificates and provisioning profiles

**"Rust build fails for iOS"**
```bash
# Install iOS targets
rustup target add aarch64-apple-ios
rustup target add x86_64-apple-ios
```

**"Pod install fails"**
```bash
cd ios
pod repo update
pod deintegrate
pod install
```

## Testing on Different Devices

### Android

**Physical Device:**
1. Enable Developer Options
2. Enable USB Debugging
3. Connect via USB
4. Install APK

**Emulator:**
```bash
# List emulators
emulator -list-avds

# Start emulator
emulator -avd Pixel_6_API_33

# Install APK
adb install app.apk
```

### iOS

**Physical Device:**
1. Register device UDID in Apple Developer Portal
2. Create provisioning profile including device
3. Build with development/ad-hoc profile
4. Install via Xcode or IPA

**Simulator:**
```bash
# List simulators
xcrun simctl list devices

# Boot simulator
open -a Simulator

# Run app
flutter run
```

## Build Optimization

### Reduce APK Size
```bash
# Use app bundles (Google Play)
flutter build appbundle --release

# Use split APKs
flutter build apk --release --split-per-abi

# Enable code shrinking in android/app/build.gradle:
minifyEnabled true
shrinkResources true
```

### Reduce IPA Size
```bash
# Enable bitcode optimization
# In Xcode Build Settings → Enable Bitcode: Yes

# Use app thinning (automatic with App Store)
# Uploads include all architectures, Apple slices per device
```

## CI/CD Integration

### GitHub Actions Example

```yaml
name: Build PIVX Test APK

on:
  push:
    branches: [ pivx-integration ]

jobs:
  build-android:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: subosito/flutter-action@v2
      - uses: actions-rs/toolchain@v1
        with:
          toolchain: stable
      - name: Build PIVX Android
        run: ./scripts/build_pivx_android_apk.sh debug
      - uses: actions/upload-artifact@v3
        with:
          name: pivx-apk
          path: build/app/outputs/flutter-apk/*.apk
```

## Security Notes

### Release Builds

- **Never commit signing keys** to version control
- Store keys securely (1Password, HashiCorp Vault)
- Use CI/CD secrets for automated builds
- Rotate signing keys periodically

### Test Distributions

- Use separate signing keys for test builds
- Limit distribution to known testers
- Use short-lived distribution links
- Monitor for unauthorized redistributions

## Support

For build issues specific to PIVX integration:
1. Check PIVX integration documentation
2. Review Rust library build logs
3. Verify Sapling parameter files are present
4. Test with PIVX testnet first

For general Flutter/platform issues:
- Flutter documentation: https://docs.flutter.dev
- Android documentation: https://developer.android.com
- iOS documentation: https://developer.apple.com
