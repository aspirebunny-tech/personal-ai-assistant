# 📖 STEP 2: Cloudflare Tunnel Setup
## Mac Mini ko Internet pe Accessible Banao — FREE!

---

## 🤔 Yeh Kyun Zaroori Hai?
Aapka Mac Mini ghar ke WiFi pe hai. Bahar se Android phone se connect karna hai.
Cloudflare Tunnel ek free service hai jo aapke Mac Mini ko internet pe ek secure URL deta hai.

---

## ⏱️ Kitna Time Lagega?
Lagbhag **20-30 minutes**

---

## 🌐 PART A: Cloudflare Account Banao

### Step 1.1
Browser mein jao: **https://cloudflare.com**

### Step 1.2
**Sign Up** pe click karo aur free account banao (email se).

### Step 1.3
Email verify karo.

---

## 🔧 PART B: cloudflared Install Karo

### Step 2.1 — Terminal mein install karo
```bash
brew install cloudflared
```

### Step 2.2 — Verify karo
```bash
cloudflared --version
```
Version number aana chahiye. ✅

---

## 🔑 PART C: Login Karo

### Step 3.1 — Login Command
```bash
cloudflared tunnel login
```

Yeh browser khulega aur Cloudflare login page aayega. Apni Cloudflare account se login karo.

Login hone ke baad terminal mein success message aayega. ✅

---

## 🚇 PART D: Tunnel Banao

### Step 4.1 — Naya Tunnel Create Karo
```bash
cloudflared tunnel create personal-assistant
```

Yeh ek Tunnel ID dega — copy karke kahi save karo! Jaise:
```
Created tunnel personal-assistant with id: abc123-def456-...
```

### Step 4.2 — Config File Banao
```bash
mkdir -p ~/.cloudflared
nano ~/.cloudflared/config.yml
```

Yeh content paste karo (apni Tunnel ID daalo):
```yaml
tunnel: ABC123-DEF456-YAHAN-APNI-ID-DAALO
credentials-file: /Users/YOUR_USERNAME/.cloudflared/ABC123-DEF456.json

ingress:
  - service: http://localhost:3000
```

**Save:** `Ctrl+X` → `Y` → `Enter`

### Step 4.3 — Apna Username
```bash
whoami
```
`YOUR_USERNAME` ki jagah apna username daalo.

---

## 🌍 PART E: Public URL Banao

### Step 5.1 — Temporary URL Test Karo (pehle test ke liye)
Pehle server chal raha ho (Step 1 se), phir:
```bash
cloudflared tunnel run personal-assistant
```

Ek URL milega jaise:
```
https://abc123.trycloudflare.com
```

Browser mein jao: `https://abc123.trycloudflare.com/api/health`

Agar `{"status":"ok"}` dikhega toh sab theek hai! ✅

⚠️ **Note:** Yeh URL har baar change hota hai. Stable URL ke liye next step karo.

### Step 5.2 — Stable URL Ke Liye (Free Domain)
Cloudflare Dashboard pe jao → Tunnels → Apna tunnel → Configure

Wahan ek free `*.pages.dev` ya apna domain add kar sakte ho.

**OR simple option:** Har baar jab server start karo, terminal se URL copy karo aur phone mein daalo. Zyada simple!

---

## 🔄 PART F: Auto-Start Ke Saath Tunnel

### Step 6.1 — LaunchAgent Banao
```bash
nano ~/Library/LaunchAgents/com.cloudflared-tunnel.plist
```

Content:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.cloudflared-tunnel</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/cloudflared</string>
        <string>tunnel</string>
        <string>run</string>
        <string>personal-assistant</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/Users/YOUR_USERNAME/cloudflared.log</string>
</dict>
</plist>
```

**Save:** `Ctrl+X` → `Y` → `Enter`

### Step 6.2 — Load Karo
```bash
launchctl load ~/Library/LaunchAgents/com.cloudflared-tunnel.plist
```

---

## 📋 URL Kaise Pata Kare

Jab bhi server chal raha ho, log file check karo:
```bash
cat ~/cloudflared.log | grep "https://"
```

Woh URL Android app mein daalna hoga.

---

## ✅ Step 2 Complete!

Ab Mac Mini internet pe accessible hai. Ab **Step 3 — Flutter App** install karo.
