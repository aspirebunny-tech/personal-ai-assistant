#!/usr/bin/env python3
import subprocess, sys
from pathlib import Path

ROOT = Path.home() / "Desktop" / "personal-ai-assistant"
FLUTTER_APP = ROOT / "flutter_app"
MAC_INFO_PLIST = FLUTTER_APP / "macos" / "Runner" / "Info.plist"
DEBUG_ENT = FLUTTER_APP / "macos" / "Runner" / "DebugProfile.entitlements"
RELEASE_ENT = FLUTTER_APP / "macos" / "Runner" / "Release.entitlements"
PODFILE = FLUTTER_APP / "macos" / "Podfile"
PBXPROJ = FLUTTER_APP / "macos" / "Runner.xcodeproj" / "project.pbxproj"
BUILD_MACOS_APP = FLUTTER_APP / "build" / "macos" / "Build" / "Products" / "Release" / "personal_ai_assistant.app"
APPLICATIONS = Path("/Applications")
TARGET_APP = APPLICATIONS / "personal_ai_assistant.app"


def run(cmd, shell=False, check=True):
    print(f">>> {cmd}")
    res = subprocess.run(cmd if isinstance(cmd, list) else cmd, shell=shell, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    print(res.stdout)
    if check and res.returncode != 0:
        print(f"Command failed with exit code {res.returncode}")
        sys.exit(res.returncode)
    return res


def ensure_mic_uri():
    if not MAC_INFO_PLIST.exists():
        print("Missing: Info.plist")
        return False
    s = MAC_INFO_PLIST.read_text()
    if "<key>NSMicrophoneUsageDescription</key>" in s:
        print("NSMicrophoneUsageDescription exists.")
        return True
    patch = "\n\t<key>NSMicrophoneUsageDescription</key>\n\t<string>We use the microphone to capture voice input for commands.</string>"
    if "<dict>" in s:
        s = s.replace("<dict>", "<dict>" + patch, 1)
        MAC_INFO_PLIST.write_text(s)
        print("Patched NSMicrophoneUsageDescription in Info.plist")
        return True
    print("Could not patch Info.plist format.")
    return False


def patch_entitlements():
    for ent in (DEBUG_ENT, RELEASE_ENT):
        if not ent.exists():
            print(f"Entitlement file missing: {ent}")
            continue
        t = ent.read_text()
        if "com.apple.security.device.audio-input" in t:
            print(f"Entitlements already patched: {ent}")
            continue
        # naive insert before </dict>
        if "</dict>" in t:
            t = t.replace("</dict>", "\t<key>com.apple.security.device.audio-input</key>\n\t<true/>\n</dict>")
            ent.write_text(t)
            print(f"Patched entitlements: {ent}")
        else:
            print(f"Could not patch entitlements: {ent}")


def patch_targets():
    if PODFILE.exists():
        t = PODFILE.read_text()
        if "platform :osx, '13.0'" in t:
            print("Podfile targets macOS 13.0 already")
        else:
            t = t.replace("platform :osx, '10.15'", "platform :osx, '13.0'")
            PODFILE.write_text(t)
            print("Patched Podfile target to 13.0")
    if PBXPROJ.exists():
        c = PBXPROJ.read_text()
        if "MACOSX_DEPLOYMENT_TARGET = 13.0;" in c:
            print("PBXProj target already 13.0")
        else:
            c = c.replace("MACOSX_DEPLOYMENT_TARGET = 10.15;", "MACOSX_DEPLOYMENT_TARGET = 13.0;")
            PBXPROJ.write_text(c)
            print("Patched PBXProj target to 13.0")


def build_and_install():
    run(["bash","-lc", f"cd '{FLUTTER_APP}' && flutter clean && flutter pub get && flutter build macos --release"], shell=False)
    if TARGET_APP.exists():
        run(["rm","-rf", str(TARGET_APP)], shell=False)
        print("Removed old app in /Applications")
    if not BUILD_MACOS_APP.exists():
        print("macOS app not found at expected path")
        sys.exit(1)
    run(["cp","-R", str(BUILD_MACOS_APP), "/Applications/"], shell=False)
    print("Copied new macOS app to /Applications/")
    if (TARGET_APP / "Contents" / "MacOS" / "personal_ai_assistant").exists():
        print("New macOS binary present ✔")
    else:
        print("Warning: macOS binary missing after copy")


def main():
    print("=== macOS mic fix (run_macos_mic_fix.py) ===")
    ensure_mic_uri()
    patch_entitlements()
    patch_targets()
    build_and_install()
    print("Open the app to test: open /Applications/personal_ai_assistant.app")

if __name__ == '__main__':
    main()
