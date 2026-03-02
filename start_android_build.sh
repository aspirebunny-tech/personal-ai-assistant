#!/bin/bash
set -euo pipefail

ROOT="$HOME/Desktop/personal-ai-assistant"
APP_DIR="$ROOT/flutter_app"
BUILD_DIR="$APP_DIR/build/app/outputs/flutter-apk"
APK_PATH="$BUILD_DIR/app-release.apk"

echo "=== Android APK Build: Start ==="
cd "$APP_DIR"

echo "Step 1: flutter pub get"
flutter pub get

echo "Step 2: flutter build apk --release"
flutter build apk --release

echo "Step 3: verify APK"
if [ -f "$APK_PATH" ]; then
  echo "APK found: $APK_PATH"
else
  echo "ERROR: APK not found at $APK_PATH"
  echo "Listing build dir contents:"
  ls -la "$BUILD_DIR" 2>&1 | sed -n '1,200p'
  echo "Tip: ensure Android SDK/Gradle setup and licenses are OK."
  exit 1
fi

echo "Step 4: APK path"
echo "APK path: $APK_PATH"
echo "=== Android APK Build: Completed ==="
