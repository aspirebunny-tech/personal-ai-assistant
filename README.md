# Personal AI Assistant (macOS + Android + Local Server)

Personal note-taking + AI assistant app with:
- Flutter client (`macOS` and `Android`)
- Node.js local server on Mac Mini
- SQLite database
- Media uploads (image/video/audio)
- Voice-to-text + AI features
- Offline-first behavior on Android with sync queue

This document is the single reference for architecture, connectivity, diagnostics, common failures, and fixes.

## 1) High-Level Architecture

```text
Android App / macOS App (Flutter)
        |
        | HTTP API + JWT + media URLs
        v
Mac Mini Server (Node/Express, port 3000, host 0.0.0.0)
        |
        +-- SQLite DB (server/data/assistant.db)
        +-- Upload storage (server/uploads/*)
        +-- Release files (server/releases/*)
        +-- Backups (server/backups/*)
        |
        +-- AI provider routing (OpenRouter/OpenAI/Ollama)
        +-- STT endpoint (OpenAI STT + fallback handling)
```

Optional network path for Android when not on same Wi-Fi:
- Tailscale MagicDNS/IP (`http://<host>.tailXXXX.ts.net:3000` or `http://100.x.x.x:3000`)
- Cloudflare quick tunnel (temporary URL, less stable for long term)

## 2) Main Components

## 2.1 Flutter app (`flutter_app`)
- Screens:
  - Home, Notes, Add/Edit Note, AI Search, Ask Notes, Quick Summary
  - AI Provider Settings
  - System Diagnostics
- Local cache:
  - Notes/folders cached for offline usage
  - Pending sync queue (Android)
- Media:
  - Fetched via protected media endpoint with auth headers
- Update flow:
  - Android app checks `/api/app/version/android`
  - Downloads APK from `/releases/personal_ai_assistant-latest.apk`

## 2.2 Server (`server`)
- Express routes:
  - `/api/auth`
  - `/api/notes`
  - `/api/folders`
  - `/api/reminders`
  - `/api/ai`
  - `/api/stt`
  - `/api/media`
  - `/api/app`
  - `/api/system`
- Health:
  - `/api/health`
- DB:
  - `better-sqlite3`, WAL mode, FK enabled
- Cron:
  - Reminder checker every minute
  - Nightly backup job at 02:00 (server-side)

## 2.3 Automation (macOS launchd)

Added automation assets:
- Watchdog script:
  - `server/scripts/pai_watchdog.sh`
  - Ensures server health and Tailscale app process readiness
- Nightly backup script:
  - `server/scripts/pai_backup_nightly.sh`
- LaunchAgents:
  - `server/launchd/com.personalai.watchdog.plist`
  - `server/launchd/com.personalai.backup-nightly.plist`

Installed runtime copies:
- `~/Library/Application Support/personal-ai-assistant/scripts/...`
- `~/Library/LaunchAgents/com.personalai.watchdog.plist`
- `~/Library/LaunchAgents/com.personalai.backup-nightly.plist`

## 3) Connectivity Modes

## 3.1 Same machine (macOS app)
- URL: `http://localhost:3000`

## 3.2 Android via Tailscale (recommended)
- URL options:
  - `http://<mac-host>.tailXXXX.ts.net:3000`
  - `http://100.x.x.x:3000` (IP fallback, avoids DNS issues)

## 3.3 Android via Cloudflare quick tunnel
- URL: `https://<random>.trycloudflare.com`
- Good for quick testing
- URL changes when tunnel restarts

## 4) Data and Sync Behavior

## 4.1 What is local on Android
- Cached folders/notes
- Pending note queue
- Auth/session data

## 4.2 What depends on server
- Live sync across devices
- AI server-side features
- Media retrieval if not cached locally
- Reminders processing

## 4.3 Offline logic
- Android can create notes offline
- On reconnect, pending queue syncs
- If server/tunnel down:
  - read cached data
  - destructive operations may be restricted

## 5) Diagnostics System

The app has `System Diagnostics` screen with red/orange/green checks:
- Device Internet
- Server URL validity
- DNS resolve
- Server health
- Auth + API access
- AI availability
- AI provider config
- Media pipeline
- Pending sync queue
- Server internal diagnostics
- Tailscale session state (connected/login-needed/key-expiry warning)

## 6) AI Provider Architecture

Per-user provider config stored in DB (`users.ai_provider_config`):
- Primary provider/model/key
- Fallback provider/model/key
- Use fallback toggle

Possible providers:
- OpenRouter
- OpenAI
- Ollama

Behavior:
- Primary fails -> fallback chain
- If all fail -> fallback mode response

## 7) Important Files

Root:
- `README.md` (this file)
- `install-guide/STEP_*.md`

Flutter:
- `flutter_app/lib/services/api_service.dart`
- `flutter_app/lib/screens/system_diagnostics_screen.dart`
- `flutter_app/lib/screens/ai_provider_settings_screen.dart`
- `flutter_app/lib/screens/add_note_screen.dart`
- `flutter_app/lib/screens/home_screen.dart`

Server:
- `server/src/index.js`
- `server/src/models/database.js`
- `server/src/routes/system.js`
- `server/src/routes/media.js`
- `server/src/routes/stt.js`
- `server/src/routes/ai.js`
- `server/releases/android-latest.json`

Automation:
- `server/scripts/pai_watchdog.sh`
- `server/scripts/pai_backup_nightly.sh`
- `server/launchd/com.personalai.watchdog.plist`
- `server/launchd/com.personalai.backup-nightly.plist`

## 8) Common Errors and Fixes

## 8.1 `Failed host lookup` (DNS fail)
Symptoms:
- Diagnostics shows DNS fail
- Host like `aspires-mac-mini...` not resolving

Fix:
- Use direct Tailscale IP URL:
  - `http://100.x.x.x:3000`
- Or correct host:
  - `http://aspires-mac-mini-1.tailXXXX.ts.net:3000`
- Save URL and run diagnostics again

## 8.2 `Server unavailable` / health fail
Symptoms:
- `/api/health` fail

Fix:
- On Mac:
  - `lsof -iTCP:3000 -sTCP:LISTEN -n -P`
  - restart server if needed:
    - `cd server && node src/index.js`
- Ensure server binds `0.0.0.0` (already configured)

## 8.3 Tailscale connected in app but not resolving
Symptoms:
- VPN on, still DNS fail

Fix:
- Confirm Mac is actually connected in Tailscale admin
- Use Tailscale IP URL as fallback
- If key/session expired, re-login once
- Disable key expiry in Tailscale admin for Mac machine

## 8.4 `AI provider unavailable` / fallback mode
Symptoms:
- AI summary/search poor output
- errors about model endpoint unavailable

Fix:
- Verify provider key in AI settings
- Choose valid model for selected provider
- Set both primary and fallback
- Re-run diagnostics (`AI Provider Config`, `AI Availability`)

## 8.5 Media not showing
Symptoms:
- Notes text visible, media missing until reconnect

Fix:
- Check `Media Pipeline` in diagnostics
- Ensure server `/uploads` and `/api/media/file/:id` accessible
- Reconnect network/server and refresh

## 8.6 Android app update not appearing
Symptoms:
- No in-app update prompt

Fix:
- Ensure:
  - `server/releases/android-latest.json` has higher version/build
  - `server/releases/personal_ai_assistant-latest.apk` replaced
- Verify endpoint:
  - `curl http://localhost:3000/api/app/version/android`

## 9) Operational Commands

## 9.1 Health and server
```bash
curl http://localhost:3000/api/health
lsof -iTCP:3000 -sTCP:LISTEN -n -P
```

## 9.2 Tailscale status
```bash
tailscale status
```

## 9.3 LaunchAgent status
```bash
launchctl print gui/$(id -u)/com.personalai.watchdog
launchctl print gui/$(id -u)/com.personalai.backup-nightly
```

## 9.4 Watchdog logs
```bash
tail -f /tmp/pai_watchdog.log
tail -f /tmp/pai_watchdog.launchd.err
tail -f /tmp/pai_server.log
```

## 9.5 Build Android APK
```bash
cd flutter_app
flutter build apk --release
```

## 9.6 Publish APK for in-app update
```bash
cp flutter_app/build/app/outputs/flutter-apk/app-release.apk \
  server/releases/personal_ai_assistant-latest.apk
```

## 10) Security Notes

- Do not commit real API keys in git.
- Keep `server/.env` private.
- If sharing builds, rotate exposed keys immediately.
- Tailscale gives private network access; only authorize trusted devices.

## 11) Recovery Checklist (Fast)

When app stops syncing:
1. Check `System Diagnostics` in app.
2. If DNS fails, switch to Tailscale IP URL.
3. Confirm Mac server health (`/api/health`).
4. Confirm Tailscale connected on Mac + Android.
5. Retry sync/update from app.

If still failing:
- Capture diagnostics screenshot + latest `/tmp/pai_watchdog.log`
- Verify version/build on Android and update manifest on server.

---

For first-time setup, use:
- `install-guide/STEP_1_Mac_Server.md`
- `install-guide/STEP_2_Cloudflare.md`
- `install-guide/STEP_3_Flutter_App.md`
- `install-guide/STEP_4_First_Setup.md`
