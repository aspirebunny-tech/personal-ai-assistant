# 📖 STEP 4: Pehli Baar Setup aur Use Karo
## Sab kuch connect karo aur shuru karo!

---

## 🔑 PART A: OpenRouter API Key Lao

### Step 1.1
Browser mein jao: **https://openrouter.ai**

### Step 1.2
**Sign Up** karo (Google account se bhi ho sakta hai)

### Step 1.3
Dashboard pe jao → **API Keys** → **Create Key**

### Step 1.4
Key copy karo (ek baar hi dikhega — save karo!)

### Step 1.5 — Server mein daalo
Mac Mini pe terminal:
```bash
nano ~/personal-ai-assistant/server/.env
```

`OPENROUTER_API_KEY=` ke baad apni key daalo.

**Save:** `Ctrl+X` → `Y` → `Enter`

Server restart karo:
```bash
launchctl unload ~/Library/LaunchAgents/com.personal-ai-assistant.plist
launchctl load ~/Library/LaunchAgents/com.personal-ai-assistant.plist
```

---

## 🌐 PART B: Cloudflare URL Pata Karo

### Step 2.1
Mac Mini pe terminal mein:
```bash
cat ~/cloudflared.log | grep "https://"
```

Jo URL dikhega woh copy karo. Jaise:
```
https://abc123-xyz.trycloudflare.com
```

Yahi URL app mein daalni hai!

---

## 📱 PART C: Android App Pehli Baar Open Karo

### Step 3.1 — App Kholo
Phone pe `Personal AI Assistant` app open karo.

### Step 3.2 — Server URL Daalo
Login screen pe **Server URL** field mein Cloudflare URL daalo:
```
https://abc123-xyz.trycloudflare.com
```

### Step 3.3 — Account Banao
**"Naya account banao? Register karo"** pe tap karo.

Daalo:
- Apna naam
- Email (fake bhi chal sakta hai jaise `me@myapp.com`)
- Password (yaad rakhne wala)

### Step 3.4 — Login Karo
Register hone ke baad automatically login ho jaayega.

---

## 🖥️ PART D: Mac App Pehli Baar Open Karo

### Step 4.1 — App Kholo
Applications mein `Personal AI Assistant` open karo.

### Step 4.2 — Server URL
Mac pe local URL use kar sakte ho:
```
http://localhost:3000
```

**Ya** wohi Cloudflare URL bhi chal sakta hai!

### Step 4.3 — Wahi Account se Login Karo
Phone wali email aur password daalo — same account dono pe! ✅

---

## 📁 PART E: Pehle Folder Banao

### Step 5.1
Home screen pe **"Naya"** button pe tap karo.

### Step 5.2
Naam daalo — jaise:
- `GF` ❤️
- `Work` 💼
- `Ideas` 💡
- `Health` 🌱
- `Random` 📋

### Step 5.3
Icon chuno aur **Banao** pe tap karo.

---

## 🎤 PART F: Pehla Note Banao

### Step 6.1
Folder pe tap karo → `+` button dabaao

### Step 6.2 — Voice se
Bottom mein 🎤 button dabaao → Hindi mein bolo → Stop dabaao

### Step 6.3 — Type karke
Ya seedha text type karo

### Step 6.4 — Save
Top right mein **Save** dabaao. ✅

---

## 🤖 PART G: AI Features Use Karo

### AI Search
Home screen → **AI Search** → Voice ya text mein poocho

### Summarize
Koi bhi note open karo → ✨ icon dabaao

### Style Seekhne ke liye
10-15 notes likhne ke baad AI automatically aapki style seekh lega.

---

## 🔄 Daily Use Kaise Karo

```
🌅 Subah:
  → Mac pe app open karo
  → Raat ke pending notes sync ho jaate hain

📱 Bahar:
  → Phone pe app open karo
  → Note likho (voice ya type)
  → Internet ho → turant sync
  → Net na ho → baad mein sync

🏠 Ghar pe:
  → Mac pe directly kaam karo
  → Sab notes wahan honge
```

---

## ⚠️ Common Problems aur Solutions

### Problem: App server se connect nahi ho raha
**Solution:**
1. Mac Mini on hai?
2. Server chal raha hai? → `cat ~/personal-ai-assistant/server.log`
3. Cloudflare tunnel chal rahi hai? → `cat ~/cloudflared.log`
4. URL sahi hai?

### Problem: Voice recognition kaam nahi kar raha
**Solution:**
1. Phone Settings → App Permissions → Microphone → ON karo
2. App restart karo

### Problem: Notes sync nahi ho rahe
**Solution:**
1. Internet check karo
2. App close karke dobara kholo
3. Pull-to-refresh karo (screen neeche se upar kheeencho)

### Problem: AI search kaam nahi kar raha
**Solution:**
1. OpenRouter API key sahi hai?
2. Credits available hain?
3. Free models try karo — `google/gemma-2-9b-it:free`

---

## 📊 Server Status Check Karo

Kabhi bhi Mac pe yeh URL check karo:
```
http://localhost:3000/api/health
```

---

## 🎉 Congratulations!

Aapka **Personal AI Assistant** ready hai!

```
✅ Mac Mini pe server chal raha hai
✅ Cloudflare se internet pe accessible hai
✅ Android app install hai
✅ Mac app install hai
✅ Real-time sync kaam kar raha hai
✅ Voice notes ready
✅ AI search ready
✅ Reminders ready
```

**Ab aapka apna personal digital brain ready hai! 🧠**
