#!/bin/bash
# Build "Hey AI.app". No Xcode needed — Command Line Tools only.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build

echo "· testing wake-phrase matcher"
swiftc -O -swift-version 5 Sources/WakeMatcher.swift Tests/main.swift -o build/matcher-tests
./build/matcher-tests

echo "· compiling Hey AI (Apple silicon + Intel)"
SOURCES=(Sources/main.swift Sources/AppDelegate.swift Sources/WakeListener.swift Sources/WakeMatcher.swift
  Sources/Launcher.swift Sources/NudgePanel.swift Sources/MicActivity.swift Sources/Brand.swift
  Sources/Setup.swift Sources/MenuHeader.swift Sources/Log.swift)
FRAMEWORKS=(-framework AppKit -framework SwiftUI -framework AVFoundation -framework Speech -framework CoreAudio
  -framework ApplicationServices -framework ServiceManagement -framework IOKit)
pids=()
for arch in arm64 x86_64; do
  swiftc -O -swift-version 5 -target "$arch-apple-macos14.0" "${SOURCES[@]}" "${FRAMEWORKS[@]}" \
    -o "build/HeyAI-$arch" &
  pids+=($!)
done
for pid in "${pids[@]}"; do wait "$pid"; done
lipo -create build/HeyAI-arm64 build/HeyAI-x86_64 -output build/HeyAI-bin

APP="build/Hey AI.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp build/HeyAI-bin "$APP/Contents/MacOS/HeyAI"
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc signature whose designated requirement is just the bundle identifier, so the
# Microphone / Speech / Accessibility grants survive rebuilds (a plain ad-hoc signature
# pins them to this exact binary).
codesign --force -s - --identifier dev.notorious.heyai \
  -r='designated => identifier "dev.notorious.heyai"' "$APP"
echo "✓ built $APP"
echo ""
echo "  open \"build/Hey AI.app\"      # menu-bar icon"
