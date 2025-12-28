# Android Build Guide - macOS Development Environment

This guide documents the complete Android build setup for Cake Wallet on macOS, including all native dependencies and troubleshooting steps.

## Prerequisites

### 1. Install Homebrew (if not already installed)
```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

### 2. Install Java 21 LTS
```bash
brew install --cask temurin@21
export JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home
```

**Important:** Add to `~/.zshrc` or `~/.bash_profile`:
```bash
export JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home
export PATH=$JAVA_HOME/bin:$PATH
```

**Note:** Gradle 8.10.2 (used by this project) requires Java 21 or lower. Java 25+ will cause "Unsupported class file major version 69" errors.

### 3. Install Android Command Line Tools
```bash
brew install android-commandlinetools
```

### 4. Set Up Android SDK
```bash
export ANDROID_HOME=~/Library/Android/sdk
export ANDROID_SDK_ROOT=~/Library/Android/sdk
export PATH=$ANDROID_HOME/cmdline-tools/latest/bin:$PATH
export PATH=$ANDROID_HOME/platform-tools:$PATH

# Create SDK directory
mkdir -p $ANDROID_HOME

# Install required SDK components
sdkmanager "platform-tools"
sdkmanager "platforms;android-34"
sdkmanager "build-tools;34.0.0"
sdkmanager "ndk;27.2.12479018"

# Accept all licenses
yes | sdkmanager --licenses
```

**Important:** Add these to `~/.zshrc` or `~/.bash_profile`:
```bash
export ANDROID_HOME=~/Library/Android/sdk
export ANDROID_SDK_ROOT=~/Library/Android/sdk
export ANDROID_NDK_HOME=$ANDROID_HOME/ndk/27.2.12479018
export PATH=$ANDROID_HOME/cmdline-tools/latest/bin:$PATH
export PATH=$ANDROID_HOME/platform-tools:$PATH
export PATH=$ANDROID_HOME/build-tools/34.0.0:$PATH
```

### 5. Install Rust and Android Targets
```bash
# Install Rust
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

# Add Android targets
rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android i686-linux-android

# Install cargo-ndk
cargo install cargo-ndk
```

### 6. Install Go and Mobile Tools
```bash
brew install go

# Install gomobile and gobind
go install golang.org/x/mobile/cmd/gomobile@latest
go install golang.org/x/mobile/cmd/gobind@latest

# Add Go bin to PATH
export PATH=$PATH:~/go/bin

# Initialize gomobile
export ANDROID_HOME=~/Library/Android/sdk
export ANDROID_NDK_HOME=~/Library/Android/sdk/ndk/27.2.12479018
gomobile init
```

**Important:** Add to `~/.zshrc` or `~/.bash_profile`:
```bash
export PATH=$PATH:~/go/bin
```

### 7. Install FVM (Flutter Version Manager)
```bash
brew tap leoafarias/fvm
brew install fvm

# Install Flutter 3.32.0 (project version)
fvm install 3.32.0
fvm use 3.32.0
```

## Initial Project Setup

### 1. Clone Repository
```bash
git clone https://github.com/cake-tech/cake_wallet.git
cd cake_wallet
git checkout pivx-integration  # or your target branch
```

### 2. Configure Flutter
```bash
fvm flutter doctor  # Check for any issues
```

### 3. Build Native Dependencies

#### Build PIVX Sapling Libraries
```bash
cd cw_pivx
export ANDROID_NDK_HOME=~/Library/Android/sdk/ndk/27.2.12479018

# Build for all Android architectures
cargo ndk -t arm64-v8a -o android/src/main/jniLibs build --release
cargo ndk -t armeabi-v7a -o android/src/main/jniLibs build --release
cargo ndk -t x86_64 -o android/src/main/jniLibs build --release
cargo ndk -t x86 -o android/src/main/jniLibs build --release

cd ..
```

**Verify:** Check that these files exist:
- `cw_pivx/android/src/main/jniLibs/arm64-v8a/libcw_pivx_sapling.so`
- `cw_pivx/android/src/main/jniLibs/armeabi-v7a/libcw_pivx_sapling.so`
- `cw_pivx/android/src/main/jniLibs/x86_64/libcw_pivx_sapling.so`
- `cw_pivx/android/src/main/jniLibs/x86/libcw_pivx_sapling.so`

#### Build MWEB Libraries (for Litecoin)
```bash
cd scripts/android
export ANDROID_NDK_VERSION=27.2.12479018
./build_mwebd.sh
cd ../..
```

**Verify:** Check that these files exist:
- `cw_mweb/android/src/main/jniLibs/arm64-v8a/libmweb.so`
- `cw_mweb/android/src/main/jniLibs/armeabi-v7a/libmweb.so`
- `cw_mweb/android/src/main/jniLibs/x86_64/libmweb.so`
- `cw_mweb/lib/generated_bindings.g.dart`

#### Build BitBox Hardware Wallet Library
```bash
cd scripts/bitbox_flutter
export PATH=$PATH:~/go/bin
export ANDROID_HOME=~/Library/Android/sdk
export ANDROID_NDK_HOME=~/Library/Android/sdk/ndk/27.2.12479018

# Build the AAR
./build_bindings.sh --dont-install

cd ../..
```

**Verify:** Check that this file exists and is ~28MB:
- `scripts/bitbox_flutter/go/api/api.aar`

### 4. Configure Project

```bash
# Copy pubspec template
cp -f pubspec_description.yaml pubspec.yaml

# Get dependencies
fvm flutter pub get

# Generate pubspec
fvm dart tool/generate_pubspec.dart

# Get dependencies again
fvm flutter pub get

# Configure wallet types (adjust flags as needed)
fvm dart tool/configure.dart --monero --bitcoin --ethereum --polygon --nano --bitcoinCash --solana --tron --wownero --zano --dogecoin --base --pivx

# Verify wallet_types.g.dart was created
ls -la lib/wallet_types.g.dart
```

### 5. Generate Secrets Files
```bash
# Generate all secrets files
fvm dart tool/import_secrets_config.dart

# Verify secrets files were created
ls -la lib/.secrets.g.dart
ls -la cw_evm/lib/.secrets.g.dart
ls -la cw_solana/lib/.secrets.g.dart
ls -la cw_tron/lib/.secrets.g.dart
ls -la cw_nano/lib/.secrets.g.dart
```

### 6. Generate Dart Code

#### Main Project
```bash
# Clean old generated files
find . -name "*.g.dart" -not -path "*/.dart_tool/*" -not -path "*/build/*" -delete

# Generate all code
fvm dart run build_runner build --delete-conflicting-outputs
```

**Expected:** ~877 outputs in 35-40 seconds

#### Sub-Packages
```bash
# Generate code for all cw_* packages
for dir in cw_*; do
  if [ -f "$dir/pubspec.yaml" ]; then
    echo "Building $dir..."
    cd "$dir"
    fvm dart run build_runner build --delete-conflicting-outputs 2>&1 | tail -3
    cd ..
  fi
done
```

#### Reown Packages (WalletConnect)
```bash
# Generate code for reown packages
for pkg in reown_core reown_sign reown_walletkit; do
  echo "=== $pkg ==="
  cd scripts/reown_flutter/packages/$pkg
  fvm dart run build_runner build --delete-conflicting-outputs
  cd ../../../..
done
```

**Note:** If you encounter errors with `reown_yttrium`, comment it out in `scripts/reown_flutter/packages/reown_walletkit/pubspec.yaml`:
```yaml
# reown_yttrium:
#   path: ../reown_yttrium/
```

### 7. Set Up Debug Signing

```bash
# Copy debug keystore to correct location
cp android/debug.keystore android/app/debug.keystore

# Or create a new one if it doesn't exist
keytool -genkey -v -keystore android/app/debug.keystore \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias androiddebugkey \
  -storepass android -keypass android \
  -dname "CN=Android Debug, O=Android, C=US"
```

## Building

### Debug Build
```bash
export JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home
fvm flutter build apk --debug
```

**Output:** `build/app/outputs/flutter-apk/app-debug.apk` (~270-280 MB)

### Release Build
```bash
# Set up release signing (see docs/builds/ANDROID.md for details)
# Then build:
export JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home
fvm flutter build apk --release --split-per-abi
```

## Common Issues and Solutions

### Issue: "Unsupported class file major version 69"
**Cause:** Java version too new for Gradle 8.10.2
**Solution:** Use Java 21 or lower:
```bash
export JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home
```

### Issue: "Could not find :api:.aar" (BitBox)
**Cause:** BitBox AAR not built
**Solution:** Build BitBox library (see step 3 above)

### Issue: Type errors like "_$EVMChainWallet can't be mixed in"
**Cause:** Missing generated code
**Solution:** Run code generation for all packages:
```bash
find . -name "*.g.dart" -not -path "*/.dart_tool/*" -not -path "*/build/*" -delete
fvm dart run build_runner build --delete-conflicting-outputs

# Then for each cw_* package
for dir in cw_*; do
  [ -f "$dir/pubspec.yaml" ] && cd "$dir" && fvm dart run build_runner build --delete-conflicting-outputs && cd ..
done
```

### Issue: "Method not found: 'Erc20TokenAdapter'"
**Cause:** Hive adapters not generated in cw_core
**Solution:** Generate code in cw_core:
```bash
cd cw_core
fvm dart run build_runner build --delete-conflicting-outputs
cd ..
```

### Issue: "Undefined name 'availableWalletTypes'"
**Cause:** wallet_types.g.dart not generated
**Solution:** Run configure script:
```bash
fvm dart tool/configure.dart --monero --bitcoin --ethereum --polygon --nano --bitcoinCash --solana --tron --wownero --zano --dogecoin --base --pivx
```

### Issue: Build extremely slow or hanging
**Cause:** Gradle daemon issues or insufficient memory
**Solution:**
```bash
# Stop Gradle daemons
cd android
./gradlew --stop

# Then try build again
cd ..
fvm flutter build apk --debug
```

### Issue: "zip file is empty" for BitBox AAR
**Cause:** Empty or corrupted AAR file
**Solution:** Rebuild BitBox library:
```bash
cd scripts/bitbox_flutter/go/api
rm -f api.aar
cd ..
export PATH=$PATH:~/go/bin
export ANDROID_HOME=~/Library/Android/sdk
export ANDROID_NDK_HOME=~/Library/Android/sdk/ndk/27.2.12479018
gomobile init
./build_bindings.sh --dont-install
```

### Issue: Duplicate dependencies in pubspec.yaml
**Cause:** Configure script can create duplicates
**Solution:** Regenerate pubspec cleanly:
```bash
cp -f pubspec_description.yaml pubspec.yaml
fvm flutter pub get
fvm dart tool/generate_pubspec.dart
fvm flutter pub get
# Then run configure
```

## Quick Reference: Environment Variables

Add these to your `~/.zshrc` or `~/.bash_profile`:

```bash
# Java
export JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home

# Android SDK
export ANDROID_HOME=~/Library/Android/sdk
export ANDROID_SDK_ROOT=~/Library/Android/sdk
export ANDROID_NDK_HOME=$ANDROID_HOME/ndk/27.2.12479018

# PATH additions
export PATH=$JAVA_HOME/bin:$PATH
export PATH=$ANDROID_HOME/cmdline-tools/latest/bin:$PATH
export PATH=$ANDROID_HOME/platform-tools:$PATH
export PATH=$ANDROID_HOME/build-tools/34.0.0:$PATH
export PATH=$HOME/go/bin:$PATH
```

Then reload: `source ~/.zshrc`

## Verifying Your Setup

Run this script to verify everything is set up correctly:

```bash
#!/bin/bash
echo "Checking build environment..."

# Check Java
if [ -z "$JAVA_HOME" ]; then
  echo "❌ JAVA_HOME not set"
else
  echo "✅ JAVA_HOME: $JAVA_HOME"
  java -version 2>&1 | head -1
fi

# Check Android SDK
if [ -z "$ANDROID_HOME" ]; then
  echo "❌ ANDROID_HOME not set"
else
  echo "✅ ANDROID_HOME: $ANDROID_HOME"
  [ -d "$ANDROID_HOME/ndk/27.2.12479018" ] && echo "✅ NDK installed" || echo "❌ NDK missing"
fi

# Check Go
which go > /dev/null && echo "✅ Go installed: $(go version)" || echo "❌ Go not found"
which gomobile > /dev/null && echo "✅ gomobile installed" || echo "❌ gomobile not found"

# Check Rust
which cargo > /dev/null && echo "✅ Rust installed: $(rustc --version)" || echo "❌ Rust not found"
which cargo-ndk > /dev/null && echo "✅ cargo-ndk installed" || echo "❌ cargo-ndk not found"

# Check FVM
which fvm > /dev/null && echo "✅ FVM installed" || echo "❌ FVM not found"
[ -d ".fvm" ] && echo "✅ FVM configured for project" || echo "⚠️  FVM not initialized (run: fvm use 3.32.0)"

# Check native libraries
echo ""
echo "Checking native libraries..."
[ -f "cw_pivx/android/src/main/jniLibs/arm64-v8a/libcw_pivx_sapling.so" ] && echo "✅ PIVX libraries built" || echo "❌ PIVX libraries missing"
[ -f "cw_mweb/android/src/main/jniLibs/arm64-v8a/libmweb.so" ] && echo "✅ MWEB libraries built" || echo "❌ MWEB libraries missing"
[ -f "scripts/bitbox_flutter/go/api/api.aar" ] && echo "✅ BitBox AAR built" || echo "❌ BitBox AAR missing"

# Check generated files
echo ""
echo "Checking generated files..."
[ -f "lib/wallet_types.g.dart" ] && echo "✅ wallet_types.g.dart exists" || echo "❌ wallet_types.g.dart missing"
[ -f "lib/.secrets.g.dart" ] && echo "✅ secrets files exist" || echo "❌ secrets files missing"
[ -f "cw_core/lib/erc20_token.g.dart" ] && echo "✅ cw_core generated" || echo "❌ cw_core needs generation"
```

Save this as `check_build_env.sh`, make it executable (`chmod +x check_build_env.sh`), and run it to verify your setup.

## Build Time Estimates

On a typical MacBook Pro (M-series):
- Native libraries (PIVX + MWEB + BitBox): ~5-10 minutes
- Code generation (all packages): ~3-5 minutes
- Debug APK build: ~1-2 minutes (after first build)
- First-time setup: ~30-45 minutes

## Next Steps

After successfully building:
1. Install on device: `adb install build/app/outputs/flutter-apk/app-debug.apk`
2. For release builds, see [docs/builds/ANDROID.md](ANDROID.md) for signing instructions
3. For iOS builds, see [docs/builds/IOS.md](IOS.md)
