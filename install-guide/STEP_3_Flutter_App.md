# 📖 STEP 3: Flutter App Install Karo
## Mac Mini pe Flutter Setup aur App Banao

---

## ⏱️ Kitna Time Lagega?
Lagbhag **45-60 minutes** (pehli baar)

---

## 🔧 PART A: Flutter Install Karo

### Step 1.1 — Flutter Download Karo
Terminal mein:
```bash
cd ~
git clone https://github.com/flutter/flutter.git -b stable
```

### Step 1.2 — PATH Add Karo
```bash
echo 'export PATH="$HOME/flutter/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

### Step 1.3 — Verify Karo
```bash
flutter --version
```

### Step 1.4 — Flutter Doctor Chalao
```bash
flutter doctor
```
Yeh batayega kya kya install karna baaki hai.

---

## 🍎 PART B: Xcode Install Karo (Mac App ke liye)

### Step 2.1 — App Store se Install Karo
1. Mac pe **App Store** kholo
2. `Xcode` search karo
3. Install karo (bada download hai — 10-15 GB)

### Step 2.2 — Xcode Setup
```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
```

### Step 2.3 — CocoaPods Install Karo
```bash
sudo gem install cocoapods
```

---

## 📱 PART C: Android Setup (Android App ke liye)

### Step 3.1 — Android Studio Download Karo
Browser mein jao: **https://developer.android.com/studio**
Download aur install karo.

### Step 3.2 — Android SDK Setup
Android Studio kholo → More Actions → SDK Manager

Yeh install karo:
- Android SDK Platform 34
- Android SDK Build-Tools
- Android Emulator (optional)

### Step 3.3 — License Accept Karo
```bash
flutter doctor --android-licenses
```
Sab ke liye `y` dabaao.

---

## 📁 PART D: App Code Setup

### Step 4.1 — Flutter App Folder
Jo `flutter_app` folder mila hai usse copy karo:
```
~/personal-ai-assistant/flutter_app/
```

### Step 4.2 — Dependencies Install Karo
```bash
cd ~/personal-ai-assistant/flutter_app
flutter pub get
```

---

## 🖥️ PART E: Mac App Banao

### Step 5.1 — Mac Desktop Support Enable Karo
```bash
flutter config --enable-macos-desktop
```

### Step 5.2 — Mac App Build Karo
```bash
cd ~/personal-ai-assistant/flutter_app
flutter build macos --release
```

Build complete hone ke baad app yahan milegi:
```
~/personal-ai-assistant/flutter_app/build/macos/Build/Products/Release/
```

### Step 5.3 — App Install Karo
`personal_ai_assistant.app` file ko Applications folder mein drag karo. ✅

---

## 📱 PART F: Android APK Banao

### Step 6.1 — APK Build Karo
```bash
cd ~/personal-ai-assistant/flutter_app
flutter build apk --release
```

APK yahan milegi:
```
~/personal-ai-assistant/flutter_app/build/app/outputs/flutter-apk/app-release.apk
```

### Step 6.2 — APK Phone pe Transfer Karo
**Option 1 — USB se:**
Phone ko USB se Mac se connect karo
APK file phone ke Downloads folder mein copy karo

**Option 2 — WhatsApp/Email se:**
APK file khud ko WhatsApp ya email karo
Phone pe download karo

### Step 6.3 — APK Install Karo
1. Phone pe Settings → Security → Unknown Sources ON karo
2. Downloads mein `app-release.apk` dhundho
3. Install karo

---

## ✅ Step 3 Complete!

App dono pe install ho gayi! Ab **Step 4 — Pehli Baar Setup** karo.
