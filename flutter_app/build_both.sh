#!/bin/bash
set -e

# Project Root
PROJECT_DIR="$HOME/Desktop/personal-ai-assistant/flutter_app"
MACOS_DIR="$PROJECT_DIR/macos"
PODFILE="$MACOS_DIR/Podfile"
PBXPROJ="$MACOS_DIR/Runner.xcodeproj/project.pbxproj"
BUILD_MACOS="$PROJECT_DIR/build/macos/Build/Products/Release/personal_ai_assistant.app"
INSTALL_PATH="/Applications/personal_ai_assistant.app"
APK_PATH="$PROJECT_DIR/build/app/outputs/flutter-apk/app-release.apk"

echo "🚀 Starting Full Build Process (macOS + Android)..."

# 1. Fix Deployment Target to 13.0
echo "🔧 Fixing Deployment Targets..."
if [ -f "$PODFILE" ]; then
    sed -i '' "s/platform :osx, '10\.15'/platform :osx, '13.0'/g" "$PODFILE"
    sed -i '' "s/platform :osx, '11\.0'/platform :osx, '13.0'/g" "$PODFILE"
    echo "  ✅ Podfile updated to 13.0"
fi

if [ -f "$PBXPROJ" ]; then
    sed -i '' 's/MACOSX_DEPLOYMENT_TARGET = 10\.[0-9]*;/MACOSX_DEPLOYMENT_TARGET = 13.0;/g' "$PBXPROJ"
    echo "  ✅ PBXProj updated to 13.0"
fi

# 2. Flutter Clean & Pub Get
echo "🧹 Cleaning and Fetching Dependencies..."
cd "$PROJECT_DIR"
flutter clean
flutter pub get

# 3. Build macOS
echo "🍏 Building macOS App (Release)..."
flutter build macos --release

# 4. Install macOS App
echo "📦 Installing macOS App to /Applications..."
if [ -d "$INSTALL_PATH" ]; then
    rm -rf "$INSTALL_PATH"
fi
cp -R "$BUILD_MACOS" "/Applications/"
echo "  ✅ macOS App Installed"

# 5. Build Android APK
echo "🤖 Building Android APK (Release)..."
flutter build apk --release

echo "=========================================="
echo "🎉 BUILD COMPLETE!"
echo "✅ Mac app ready: $INSTALL_PATH"
echo "✅ Android APK ready: $APK_PATH"
echo "=========================================="
