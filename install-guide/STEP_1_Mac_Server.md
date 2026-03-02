# 📖 STEP 1: Mac Mini Setup
## Personal AI Assistant - Mac Mini pe Server Install Karo

---

## ⏱️ Kitna Time Lagega?
Lagbhag **30-45 minutes** — pehli baar thoda time lagta hai, phir sab automatic hai.

---

## 🔧 PART A: Homebrew Install Karo

Homebrew ek tool hai jo Mac pe software install karne mein help karta hai.

### Step 1.1 — Terminal Kholo
1. Mac pe **Spotlight Search** kholo: `Command (⌘) + Space`
2. `Terminal` type karo
3. Enter dabaao

### Step 1.2 — Homebrew Install Karo
Terminal mein yeh command copy-paste karo aur Enter dabaao:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

⚠️ **Note:** Yeh thoda time lega (5-10 minutes). Password maange toh apna Mac login password daalo.

### Step 1.3 — Verify Karo
```bash
brew --version
```
Agar version number aaya (jaise `Homebrew 4.x.x`) toh Homebrew install ho gaya! ✅

---

## 🟢 PART B: Node.js Install Karo

Node.js se hamare server ka code chalega.

### Step 2.1 — Node.js Install Karo
```bash
brew install node
```

### Step 2.2 — Verify Karo
```bash
node --version
npm --version
```
Dono mein version number aana chahiye. ✅

---

## 📁 PART C: Server Files Setup Karo

### Step 3.1 — Project Folder Banao
```bash
mkdir -p ~/personal-ai-assistant/server
cd ~/personal-ai-assistant/server
```

### Step 3.2 — Server Files Copy Karo
Aapko jo `server` folder mila hai (is guide ke saath), uske saare files yahan copy karo:
```
~/personal-ai-assistant/server/
```

### Step 3.3 — Dependencies Install Karo
```bash
cd ~/personal-ai-assistant/server
npm install
```
Yeh thoda time lega — saari libraries download hongi.

### Step 3.4 — Config File Banao
```bash
cp .env.example .env
nano .env
```

Nano editor mein yeh fields edit karo:
```
JWT_SECRET=koi_bhi_password_yahan_likho_jaise_meri_secret_key_2024
OPENROUTER_API_KEY=apni_openrouter_api_key_yahan
```

**Save karne ke liye:** `Ctrl+X` → `Y` → `Enter`

### Step 3.5 — Upload Folders Banao
```bash
mkdir -p ~/personal-ai-assistant/server/uploads/images
mkdir -p ~/personal-ai-assistant/server/uploads/videos
mkdir -p ~/personal-ai-assistant/server/data
```

---

## 🚀 PART D: Server Start Karo

### Step 4.1 — Pehli Baar Test Karo
```bash
cd ~/personal-ai-assistant/server
npm start
```

Agar yeh message dikhega toh server chal raha hai:
```
🚀 Personal AI Assistant Server running on port 3000
✅ Database initialized
⏰ Reminder checker active
```

### Step 4.2 — Browser mein Check Karo
Mac pe Safari ya Chrome kholo aur yahan jao:
```
http://localhost:3000/api/health
```

Agar yeh dikhega toh sab theek hai ✅:
```json
{"status": "ok", "message": "Personal AI Assistant Server Running!"}
```

**Terminal band karne ke liye:** `Ctrl+C`

---

## 🔄 PART E: Server Auto-Start Setup Karo

Jab Mac restart ho tab server automatically start ho.

### Step 5.1 — LaunchAgent File Banao
```bash
nano ~/Library/LaunchAgents/com.personal-ai-assistant.plist
```

Yeh content paste karo (apna username replace karo jahan `YOUR_USERNAME` likha hai):
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.personal-ai-assistant</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/node</string>
        <string>/Users/YOUR_USERNAME/personal-ai-assistant/server/src/index.js</string>
    </array>
    <key>WorkingDirectory</key>
    <string>/Users/YOUR_USERNAME/personal-ai-assistant/server</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/Users/YOUR_USERNAME/personal-ai-assistant/server.log</string>
    <key>StandardErrorPath</key>
    <string>/Users/YOUR_USERNAME/personal-ai-assistant/server-error.log</string>
</dict>
</plist>
```

**Save:** `Ctrl+X` → `Y` → `Enter`

### Step 5.2 — Apna Username Dhundho
```bash
whoami
```
Jo naam aaye woh `YOUR_USERNAME` ki jagah daalo.

### Step 5.3 — LaunchAgent Load Karo
```bash
launchctl load ~/Library/LaunchAgents/com.personal-ai-assistant.plist
```

Ab server Mac restart hone ke baad bhi automatically start hoga! ✅

---

## ✅ Step 1 Complete!

Server ready hai. Ab **Step 2 — Cloudflare Tunnel** setup karo.
