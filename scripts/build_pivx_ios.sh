#!/bin/bash

# PIVX iOS Build Script for Testing
# This script builds an iOS app for PIVX integration testing

set -e

echo "🚀 PIVX iOS Build Script"
echo "========================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
BUILD_TYPE="${1:-debug}"  # debug or release
EXPORT_METHOD="${2:-development}"  # development, ad-hoc, or app-store
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo -e "${YELLOW}Build Type: ${BUILD_TYPE}${NC}"
echo -e "${YELLOW}Export Method: ${EXPORT_METHOD}${NC}"
echo -e "${YELLOW}Project Root: ${PROJECT_ROOT}${NC}"

# Check if running on macOS
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo -e "${RED}✗ Error: iOS builds require macOS${NC}"
    exit 1
fi

# Check for Xcode
if ! command -v xcodebuild &> /dev/null; then
    echo -e "${RED}✗ Error: Xcode is not installed${NC}"
    exit 1
fi

# Step 1: Build PIVX Rust library for iOS
echo ""
echo -e "${GREEN}Step 1/7: Building PIVX Rust library for iOS...${NC}"
cd "$PROJECT_ROOT/cw_pivx/scripts"
if [ -f "./build_ios.sh" ]; then
    ./build_ios.sh
    echo -e "${GREEN}✓ PIVX Rust library built${NC}"
else
    echo -e "${YELLOW}⚠ PIVX build script not found, skipping...${NC}"
fi

# Step 2: Clean previous builds
echo ""
echo -e "${GREEN}Step 2/7: Cleaning previous builds...${NC}"
cd "$PROJECT_ROOT"
fvm flutter clean
rm -rf ios/Pods
rm -rf ios/Podfile.lock
fvm flutter pub get

# Step 3: Install CocoaPods dependencies
echo ""
echo -e "${GREEN}Step 3/7: Installing CocoaPods dependencies...${NC}"
cd ios
pod install
cd "$PROJECT_ROOT"

# Step 4: Generate necessary files
echo ""
echo -e "${GREEN}Step 4/7: Generating code...${NC}"
fvm flutter pub run tool/generate_localization.dart
fvm flutter packages pub run build_runner build --delete-conflicting-outputs

# Step 5: Build iOS app
echo ""
echo -e "${GREEN}Step 5/7: Building iOS application...${NC}"

if [ "$BUILD_TYPE" = "release" ]; then
    echo -e "${YELLOW}Building release iOS app...${NC}"
    fvm flutter build ios --release --no-codesign
    
    echo ""
    echo -e "${GREEN}Step 6/7: Creating IPA archive...${NC}"
    
    # Build archive
    cd ios
    xcodebuild -workspace Runner.xcworkspace \
               -scheme Runner \
               -sdk iphoneos \
               -configuration Release \
               -archivePath "$PROJECT_ROOT/build/Runner.xcarchive" \
               archive
    
    # Export IPA
    echo ""
    echo -e "${GREEN}Step 7/7: Exporting IPA...${NC}"
    
    # Create export options plist
    cat > "$PROJECT_ROOT/build/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>${EXPORT_METHOD}</string>
    <key>teamID</key>
    <string>YOUR_TEAM_ID</string>
    <key>uploadSymbols</key>
    <true/>
    <key>compileBitcode</key>
    <false/>
</dict>
</plist>
EOF
    
    xcodebuild -exportArchive \
               -archivePath "$PROJECT_ROOT/build/Runner.xcarchive" \
               -exportPath "$PROJECT_ROOT/build/ios/ipa" \
               -exportOptionsPlist "$PROJECT_ROOT/build/ExportOptions.plist"
    
    cd "$PROJECT_ROOT"
    
    IPA_FILE="$PROJECT_ROOT/build/ios/ipa/Runner.ipa"
    if [ -f "$IPA_FILE" ]; then
        IPA_SIZE=$(ls -lh "$IPA_FILE" | awk '{print $5}')
        echo ""
        echo -e "${GREEN}✓ Release IPA built successfully!${NC}"
        echo -e "${GREEN}Output file: ${IPA_FILE}${NC}"
        echo -e "${GREEN}IPA size: ${IPA_SIZE}${NC}"
    else
        echo -e "${RED}✗ IPA file not found${NC}"
        echo -e "${YELLOW}Note: You may need to configure signing in Xcode${NC}"
    fi
else
    echo -e "${YELLOW}Building debug iOS app...${NC}"
    fvm flutter build ios --debug --no-codesign
    
    echo ""
    echo -e "${GREEN}✓ Debug iOS app built successfully!${NC}"
    echo -e "${GREEN}Output directory: ${PROJECT_ROOT}/build/ios/iphoneos/${NC}"
fi

# Installation instructions
echo ""
echo -e "${GREEN}═══════════════════════════════════════${NC}"
echo -e "${GREEN}Installation Instructions:${NC}"
echo -e "${GREEN}═══════════════════════════════════════${NC}"
echo ""

if [ "$BUILD_TYPE" = "release" ]; then
    echo "For release build:"
    echo ""
    echo "1. Install via Xcode:"
    echo "   - Open Xcode"
    echo "   - Window → Devices and Simulators"
    echo "   - Select your device"
    echo "   - Click '+' and select the IPA file"
    echo ""
    echo "2. Install via command line (TestFlight/Ad-hoc):"
    echo "   xcrun altool --upload-app --type ios --file build/ios/ipa/Runner.ipa \\"
    echo "       --apiKey YOUR_API_KEY --apiIssuer YOUR_ISSUER_ID"
    echo ""
    echo "3. Install via third-party tools:"
    echo "   - Diawi: https://www.diawi.com/"
    echo "   - TestFlight (requires App Store Connect)"
    echo "   - iOS App Signer for re-signing"
else
    echo "For debug build:"
    echo ""
    echo "1. Run from Xcode:"
    echo "   - Open ios/Runner.xcworkspace in Xcode"
    echo "   - Select your device/simulator"
    echo "   - Press Run (⌘R)"
    echo ""
    echo "2. Run from command line:"
    echo "   flutter run --debug"
    echo ""
    echo "3. Install on physical device:"
    echo "   - Connect device via USB"
    echo "   - Open ios/Runner.xcworkspace"
    echo "   - Select device and press Run"
fi

echo ""
echo -e "${YELLOW}Important Notes:${NC}"
echo -e "${YELLOW}───────────────${NC}"
echo "• For release builds, configure signing in Xcode:"
echo "  - Open ios/Runner.xcworkspace"
echo "  - Select Runner project → Signing & Capabilities"
echo "  - Select your team and provisioning profile"
echo ""
echo "• For TestFlight distribution:"
echo "  - Use export method 'app-store'"
echo "  - Upload IPA to App Store Connect"
echo ""
echo "• For ad-hoc distribution:"
echo "  - Use export method 'ad-hoc'"
echo "  - Register device UDIDs in Apple Developer Portal"
echo ""
echo -e "${GREEN}🎉 Build complete!${NC}"
