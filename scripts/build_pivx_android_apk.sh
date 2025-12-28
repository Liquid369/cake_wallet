#!/bin/bash

# PIVX Android APK Build Script for Testing
# This script builds a debug/release APK for PIVX integration testing

set -e

echo "🚀 PIVX Android APK Build Script"
echo "================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
BUILD_TYPE="${1:-debug}"  # debug or release
APP_TYPE="cakewallet"
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo -e "${YELLOW}Build Type: ${BUILD_TYPE}${NC}"
echo -e "${YELLOW}Project Root: ${PROJECT_ROOT}${NC}"

# Step 1: Build PIVX Rust library for Android
echo ""
echo -e "${GREEN}Step 1/6: Building PIVX Rust library for Android...${NC}"
cd "$PROJECT_ROOT/cw_pivx/scripts"
if [ -f "./build_android.sh" ]; then
    ./build_android.sh
    echo -e "${GREEN}✓ PIVX Rust library built${NC}"
else
    echo -e "${YELLOW}⚠ PIVX build script not found, skipping...${NC}"
fi

# Step 2: Set up Android environment
echo ""
echo -e "${GREEN}Step 2/6: Setting up Android environment...${NC}"
cd "$PROJECT_ROOT"
export APP_ANDROID_TYPE="$APP_TYPE"
source ./scripts/android/app_env.sh $APP_TYPE

# Step 3: Clean previous builds
echo ""
echo -e "${GREEN}Step 3/6: Cleaning previous builds...${NC}"
fvm flutter clean
fvm flutter pub get

# Step 4: Configure app for Android
echo ""
echo -e "${GREEN}Step 4/6: Configuring app...${NC}"
cd scripts/android
./app_config.sh
cd "$PROJECT_ROOT"

# Step 5: Generate necessary files
echo ""
echo -e "${GREEN}Step 5/6: Generating code...${NC}"
fvm flutter pub run tool/generate_localization.dart
fvm flutter packages pub run build_runner build --delete-conflicting-outputs

# Step 6: Build APK
echo ""
echo -e "${GREEN}Step 6/6: Building APK...${NC}"
if [ "$BUILD_TYPE" = "release" ]; then
    echo -e "${YELLOW}Building release APK (requires signing keys)...${NC}"
    fvm flutter build apk --release --split-per-abi
    
    APK_DIR="$PROJECT_ROOT/build/app/outputs/flutter-apk"
    echo ""
    echo -e "${GREEN}✓ Release APK built successfully!${NC}"
    echo -e "${GREEN}Output directory: ${APK_DIR}${NC}"
    echo ""
    echo "APK files:"
    ls -lh "$APK_DIR"/*.apk 2>/dev/null || echo "No APK files found"
else
    echo -e "${YELLOW}Building debug APK...${NC}"
    fvm flutter build apk --debug
    
    APK_FILE="$PROJECT_ROOT/build/app/outputs/flutter-apk/app-debug.apk"
    echo ""
    echo -e "${GREEN}✓ Debug APK built successfully!${NC}"
    echo -e "${GREEN}Output file: ${APK_FILE}${NC}"
    
    if [ -f "$APK_FILE" ]; then
        APK_SIZE=$(ls -lh "$APK_FILE" | awk '{print $5}')
        echo -e "${GREEN}APK size: ${APK_SIZE}${NC}"
    fi
fi

# Installation instructions
echo ""
echo -e "${GREEN}═══════════════════════════════════════${NC}"
echo -e "${GREEN}Installation Instructions:${NC}"
echo -e "${GREEN}═══════════════════════════════════════${NC}"
echo ""
echo "For debug build:"
echo "  adb install build/app/outputs/flutter-apk/app-debug.apk"
echo ""
echo "For release build (split ABIs):"
echo "  # For ARM64 devices (most modern phones):"
echo "  adb install build/app/outputs/flutter-apk/app-arm64-v8a-release.apk"
echo ""
echo "  # For ARM32 devices:"
echo "  adb install build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk"
echo ""
echo "  # For x86_64 emulators:"
echo "  adb install build/app/outputs/flutter-apk/app-x86_64-release.apk"
echo ""
echo -e "${YELLOW}Note: For release builds, ensure you have configured key.properties${NC}"
echo -e "${YELLOW}in android/key.properties with your signing keys.${NC}"
echo ""
echo -e "${GREEN}🎉 Build complete!${NC}"
