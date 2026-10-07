#!/bin/bash
# Build HeyVoice.app. No Xcode needed — Command Line Tools only.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build

echo "· testing wake-phrase matcher"
swiftc -O -swift-version 5 Sources/WakeMatcher.swift Tests/main.swift -o build/matcher-tests
./build/matcher-tests

echo "· compiling HeyVoice"
swiftc -O -swift-version 5 \
  Sources/main.swift Sources/AppDelegate.swift Sources/WakeListener.swift \
  Sources/WakeMatcher.swift Sources/Launcher.swift Sources/NudgePanel.swift Sources/MicActivity.swift \
  Sources/Log.swift \
  -framework AppKit -framework AVFoundation -framework Speech -framework CoreAudio \
  -framework ApplicationServices -framework ServiceManagement \
  -o build/HeyVoice-bin

APP=build/HeyVoice.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp build/HeyVoice-bin "$APP/Contents/MacOS/HeyVoice"
cp Info.plist "$APP/Contents/Info.plist"

# Ad-hoc signature whose designated requirement is just the bundle identifier, so the
# Microphone / Speech / Accessibility grants survive rebuilds (a plain ad-hoc signature
# pins them to this exact binary).
codesign --force -s - --identifier dev.notorious.heyvoice \
  -r='designated => identifier "dev.notorious.heyvoice"' "$APP"
echo "✓ built $APP"
echo ""
echo "  open build/HeyVoice.app      # menu-bar waveform icon"
