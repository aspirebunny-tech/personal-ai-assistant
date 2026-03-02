#!/usr/bin/env python3
import os
import sys
from pathlib import Path
import subprocess

BASE = Path.home() / "Desktop" / "personal-ai-assistant"
FLUTTER_APP = BASE / "flutter_app"
MAC_INFO_PLIST = FLUTTER_APP / "macos" / "Runner" / "Info.plist"
PODFILE = FLUTTER_APP / "macos" / "Podfile"
PBXPROJ = FLUTTER_APP / "macos" / "Runner.xcodeproj" / "project.pbxproj"


def run(cmd, shell=False, check=True):
    print(f"$ {cmd}")
    res = subprocess.run(cmd, shell=shell, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    print(res.stdout)
    if check and res.returncode != 0:
        print(f"Command failed with exit code {res.returncode}")
        sys.exit(res.returncode)
    return res


def add_plist_usage():
    if not MAC_INFO_PLIST.exists():
        print("Missing: Info.plist")
        return
    text = MAC_INFO_PLIST.read_text()
    if "<key>NSSpeechRecognitionUsageDescription</key>" in text:
        print("Info.plist already contains NSSpeechRecognitionUsageDescription.")
        return
    # insert after opening <dict>
    insert_after = "<dict>";
    new_entry = "\n\t<key>NSSpeechRecognitionUsageDescription</key>\n\t<string>We use speech recognition to understand voice commands in the app.</string>"
    text = text.replace(insert_after + "\n", insert_after + "\n" + new_entry + "\n", 1)
    MAC_INFO_PLIST.write_text(text)
    print("Added NSSpeechRecognitionUsageDescription to Info.plist")


def macos_deploy_13_patch():
    if PODFILE.exists():
        txt = PODFILE.read_text()
        if "platform :osx, '13.0'" in txt:
            print("Podfile already targets macOS 13.0")
        else:
            txt = txt.replace("platform :osx, '10.15'", "platform :osx, '13.0'")
            PODFILE.write_text(txt)
            print("Updated Podfile to macOS 13.0")
    else:
        print("Podfile not found; skipping Podfile patch")

    pbx = PBXPROJ
    if pbx.exists():
        content = pbx.read_text()
        if "MACOSX_DEPLOYMENT_TARGET = 13.0;" in content:
            print("PBXProj already 13.0")
        else:
            content = content.replace("MACOSX_DEPLOYMENT_TARGET = 10.15;", "MACOSX_DEPLOYMENT_TARGET = 13.0;")
            pbx.write_text(content)
            print("PBXProj macOS deployment target set to 13.0")
    else:
        print("PBXProj not found; skipping PBXProj patch")


def build_and_install():
    # Build macOS
    run(["bash", "-lc", f"cd '{FLUTTER_APP}' && flutter clean && flutter pub get && flutter build macos --release"], shell=False)
    # Copy to /Applications
    apps = "/Applications/personal_ai_assistant.app"
    if os.path.exists(apps):
        run(["rm", "-rf", apps], shell=False)
        print("Removed old /Applications/personal_ai_assistant.app")
    src = FLUTTER_APP / "build" / "macos" / "Build" / "Products" / "Release" / "personal_ai_assistant.app"
    if not src.exists():
        print("macOS app not found at", src)
        sys.exit(1)
    run(["cp", "-R", str(src), "/Applications/"], shell=False)
    print("Copied new macOS app to /Applications/")


def main():
    print("=== macOS fix + build + reinstall (un_macos_fix) ===")
    add_plist_usage()
    macos_deploy_13_patch()
    build_and_install()
    print("=== Done ===")

if __name__ == "__main__":
    main()
