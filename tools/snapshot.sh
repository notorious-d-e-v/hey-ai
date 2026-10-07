#!/bin/bash
# Renders the app's SwiftUI screens to PNGs (default /tmp/heyai-snapshots) for review.
set -euo pipefail
cd "$(dirname "$0")/.."
SOURCES=$(ls Sources/*.swift | grep -v main.swift)
swiftc -O -swift-version 5 -D SNAPSHOT $SOURCES tools/snapshot/main.swift \
  -framework AppKit -framework SwiftUI -framework AVFoundation -framework Speech -framework CoreAudio \
  -framework ApplicationServices -framework ServiceManagement -framework IOKit -o build/snapshot
./build/snapshot "${1:-/tmp/heyai-snapshots}"
