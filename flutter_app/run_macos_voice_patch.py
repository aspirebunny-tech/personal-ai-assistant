#!/usr/bin/env python3
import os
import sys
from pathlib import Path
import subprocess

ROOT = Path.home() / "Desktop" / "personal-ai-assistant"
FLUTTER_APP = ROOT / "flutter_app"
MAC_INFO_PLIST = FLUTTER_APP / "macos" / "Runner" / "Info.plist"
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


def add_mic_usage():
    if not MAC_INFO_PLIST.exists():
        print("Missing: Info.plist")
        return False
    s = MAC_INFO_PLIST.read_text()
    if "<key>NSMicrophoneUsageDescription</key>" in s:
        print("Info.plist already has NSMicrophoneUsageDescription.")
        return True
    patch = "\n\t<key>NSMicrophoneUsageDescription</key>\n\t<string>We use the microphone to capture voice input for commands.</string>"
    if "<dict>" in s:
        s = s.replace("<dict>", "<dict>" + patch, 1)
        MAC_INFO_PLIST.write_text(s)
        print("Added NSMicrophoneUsageDescription to Info.plist")
        return True
    print("Could not patch Info.plist (unexpected format).")
    return False


def patch_deploy_target():
    if PODFILE.exists():
        t = PODFILE.read_text()
        if "platform :osx, '13.0'" in t:
            print("Podfile already targets macOS 13.0")
        else:
            t = t.replace("platform :osx, '10.15'", "platform :osx, '13.0'")
            PODFILE.write_text(t)
            print("Podfile updated to macOS 13.0")
    else:
        print("Podfile not found; skipping patch in Podfile")

    if PBXPROJ.exists():
        content = PBXPROJ.read_text()
        if "MACOSX_DEPLOYMENT_TARGET = 13.0;" in content:
            print("PBXProj already 13.0")
        else:
            content = content.replace("MACOSX_DEPLOYMENT_TARGET = 10.15;", "MACOSX_DEPLOYMENT_TARGET = 13.0;")
            PBXPROJ.write_text(content)
            print("PBXProj macOS deployment target set to 13.0")
    else:
        print("PBXProj not found; skipping PBXProj patch")


def build_and_install():
    run(["bash","-lc", f"cd '{FLUTTER_APP}' && flutter clean && flutter pub get && flutter build macos --release"], shell=False)
    if TARGET_APP.exists():
        run(["rm","-rf", str(TARGET_APP)], shell=False)
        print("Removed old /Applications/personal_ai_assistant.app")
    if not BUILD_MACOS_APP.exists():
        print("macOS app not found at", BUILD_MACOS_APP)
        sys.exit(1)
    run(["cp","-R", str(BUILD_MACOS_APP), "/Applications/"], shell=False)
    print("Copied new macOS app to /Applications/")
    if (TARGET_APP / "Contents" / "MacOS" / "personal_ai_assistant").exists():
        print("New macOS binary present.")
    else:
        print("Warning: macOS binary not found after copy.")


def main():
    print("=== macOS fix + build + reinstall (python patch) ===")
    add_mic_usage()
    patch_deploy_target()
    build_and_install()
    print("Open the app to test: open /Applications/personal_ai_assistant.app")
    print("=== Done ===")

if __name__ == "__main__":
    main()
