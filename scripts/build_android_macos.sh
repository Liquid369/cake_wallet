#!/bin/bash
set -e

# Cake Wallet Android Build Script for macOS
# This script automates the Android build process

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
echo_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
echo_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if we're in the right directory
if [ ! -f "pubspec.yaml" ]; then
  echo_error "Please run this script from the cake_wallet root directory"
  exit 1
fi

# Parse arguments
BUILD_TYPE="debug"
SKIP_NATIVE=false
SKIP_CODEGEN=false
CLEAN=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --release)
      BUILD_TYPE="release"
      shift
      ;;
    --skip-native)
      SKIP_NATIVE=true
      shift
      ;;
    --skip-codegen)
      SKIP_CODEGEN=true
      shift
      ;;
    --clean)
      CLEAN=true
      shift
      ;;
    --help)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --release       Build release APK instead of debug"
      echo "  --skip-native   Skip building native libraries (if already built)"
      echo "  --skip-codegen  Skip Dart code generation (if already done)"
      echo "  --clean         Clean before building"
      echo "  --help          Show this help message"
      exit 0
      ;;
    *)
      echo_error "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Verify environment
echo_info "Checking environment..."

if [ -z "$JAVA_HOME" ]; then
  echo_error "JAVA_HOME not set. Please set it to Java 21 JDK path"
  exit 1
fi

if [ -z "$ANDROID_HOME" ]; then
  echo_error "ANDROID_HOME not set. Please set Android SDK path"
  exit 1
fi

if [ -z "$ANDROID_NDK_HOME" ]; then
  echo_warn "ANDROID_NDK_HOME not set. Using default: $ANDROID_HOME/ndk/27.2.12479018"
  export ANDROID_NDK_HOME="$ANDROID_HOME/ndk/27.2.12479018"
fi

# Check for required tools
command -v fvm >/dev/null 2>&1 || { echo_error "fvm not installed"; exit 1; }
command -v cargo >/dev/null 2>&1 || { echo_error "cargo (Rust) not installed"; exit 1; }
command -v go >/dev/null 2>&1 || { echo_error "go not installed"; exit 1; }

echo_info "✅ Environment checks passed"

# Clean if requested
if [ "$CLEAN" = true ]; then
  echo_info "Cleaning project..."
  fvm flutter clean
  find . -name "*.g.dart" -not -path "*/.dart_tool/*" -not -path "*/build/*" -delete
  rm -rf build/
fi

# Build native libraries
if [ "$SKIP_NATIVE" = false ]; then
  echo_info "Building native libraries..."
  
  # PIVX
  echo_info "Building PIVX libraries..."
  cd cw_pivx
  if [ ! -f "android/src/main/jniLibs/arm64-v8a/libcw_pivx_sapling.so" ]; then
    cargo ndk -t arm64-v8a -o android/src/main/jniLibs build --release
    cargo ndk -t armeabi-v7a -o android/src/main/jniLibs build --release
    cargo ndk -t x86_64 -o android/src/main/jniLibs build --release
    cargo ndk -t x86 -o android/src/main/jniLibs build --release
    echo_info "✅ PIVX libraries built"
  else
    echo_info "✅ PIVX libraries already exist"
  fi
  cd ..
  
  # MWEB
  echo_info "Building MWEB libraries..."
  if [ ! -f "cw_mweb/android/src/main/jniLibs/arm64-v8a/libmweb.so" ]; then
    cd scripts/android
    export ANDROID_NDK_VERSION=27.2.12479018
    ./build_mwebd.sh
    cd ../..
    echo_info "✅ MWEB libraries built"
  else
    echo_info "✅ MWEB libraries already exist"
  fi
  
  # BitBox
  echo_info "Building BitBox library..."
  if [ ! -f "scripts/bitbox_flutter/go/api/api.aar" ] || [ ! -s "scripts/bitbox_flutter/go/api/api.aar" ]; then
    cd scripts/bitbox_flutter
    export PATH=$PATH:~/go/bin
    gomobile init
    ./build_bindings.sh --dont-install
    cd ../..
    echo_info "✅ BitBox library built"
  else
    echo_info "✅ BitBox library already exists"
  fi
else
  echo_info "Skipping native library builds"
fi

# Project configuration
echo_info "Configuring project..."

# Check if pubspec needs regeneration
if [ ! -f "lib/wallet_types.g.dart" ]; then
  echo_info "Generating pubspec..."
  cp -f pubspec_description.yaml pubspec.yaml
  fvm flutter pub get
  fvm dart tool/generate_pubspec.dart
  fvm flutter pub get
  
  echo_info "Configuring wallet types..."
  fvm dart tool/configure.dart --monero --bitcoin --ethereum --polygon --nano --bitcoinCash --solana --tron --wownero --zano --dogecoin --base --pivx
else
  echo_info "✅ Project already configured"
  fvm flutter pub get
fi

# Generate secrets
if [ ! -f "lib/.secrets.g.dart" ]; then
  echo_info "Generating secrets..."
  fvm dart tool/import_secrets_config.dart
  echo_info "✅ Secrets generated"
else
  echo_info "✅ Secrets already exist"
fi

# Code generation
if [ "$SKIP_CODEGEN" = false ]; then
  echo_info "Generating Dart code..."
  
  # Main project
  echo_info "Generating main project code..."
  fvm dart run build_runner build --delete-conflicting-outputs
  
  # Sub-packages
  echo_info "Generating code for sub-packages..."
  for dir in cw_*; do
    if [ -f "$dir/pubspec.yaml" ] && [ -f "$dir/pubspec.lock" ]; then
      echo_info "  - $dir"
      cd "$dir"
      fvm dart run build_runner build --delete-conflicting-outputs > /dev/null 2>&1 || true
      cd ..
    fi
  done
  
  # Reown packages
  echo_info "Generating code for reown packages..."
  for pkg in reown_core reown_sign reown_walletkit; do
    if [ -d "scripts/reown_flutter/packages/$pkg" ]; then
      echo_info "  - $pkg"
      cd "scripts/reown_flutter/packages/$pkg"
      fvm dart run build_runner build --delete-conflicting-outputs > /dev/null 2>&1 || true
      cd ../../../..
    fi
  done
  
  echo_info "✅ Code generation complete"
else
  echo_info "Skipping code generation"
fi

# Ensure debug keystore exists
if [ ! -f "android/app/debug.keystore" ]; then
  echo_info "Setting up debug keystore..."
  if [ -f "android/debug.keystore" ]; then
    cp android/debug.keystore android/app/debug.keystore
  else
    keytool -genkey -v -keystore android/app/debug.keystore \
      -keyalg RSA -keysize 2048 -validity 10000 \
      -alias androiddebugkey \
      -storepass android -keypass android \
      -dname "CN=Android Debug, O=Android, C=US"
  fi
  echo_info "✅ Debug keystore ready"
fi

# Build
echo_info "Building APK ($BUILD_TYPE)..."
if [ "$BUILD_TYPE" = "release" ]; then
  fvm flutter build apk --release --split-per-abi
else
  fvm flutter build apk --debug
fi

# Success message
echo ""
echo_info "========================================="
echo_info "✅ Build complete!"
echo_info "========================================="
echo ""

if [ "$BUILD_TYPE" = "release" ]; then
  echo_info "Release APKs:"
  ls -lh build/app/outputs/flutter-apk/*.apk 2>/dev/null || true
else
  echo_info "Debug APK:"
  ls -lh build/app/outputs/flutter-apk/app-debug.apk 2>/dev/null || true
  echo ""
  echo_info "To install on device:"
  echo "  adb install build/app/outputs/flutter-apk/app-debug.apk"
fi

echo ""
