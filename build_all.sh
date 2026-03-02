#!/bin/bash

# Navigate to the Flutter app directory
cd ~/Desktop/personal-ai-assistant/flutter_app

# Fetch dependencies
echo "📦 Fetching Flutter dependencies..."
flutter pub get

# Build macOS App
echo "🍏 Building macOS Release..."
flutter build macos --release

# Build Android APK
echo "🤖 Building Android APK..."
flutter build apk --release

# Output Result Paths
echo "---------------------------------------------------"
echo "✅ Mac app: ~/Desktop/personal-ai-assistant/flutter_app/build/macos/Build/Products/Release/personal_ai_assistant.app"
echo "✅ Android APK: ~/Desktop/personal-ai-assistant/flutter_app/build/app/outputs/flutter-apk/app-release.apk"
