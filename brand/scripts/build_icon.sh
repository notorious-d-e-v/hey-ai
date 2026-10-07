#!/bin/bash
# Rebuilds the app icon: logo/app-icon.svg → logo/app-icon-1024.png → Resources/AppIcon.icns.
# Needs Google Chrome (to render the SVG) and Python 3.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/make_icon_svg.py logo/app-icon.svg
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new --disable-gpu --hide-scrollbars \
  --default-background-color=00000000 --window-size=1024,1024 \
  --screenshot=logo/app-icon-1024.png "file://$PWD/logo/app-icon.svg" >/dev/null 2>&1
set=$(mktemp -d)/AppIcon.iconset
mkdir -p "$set"
for s in 16 32 128 256 512; do
  sips -z $s $s logo/app-icon-1024.png --out "$set/icon_${s}x${s}.png" >/dev/null
  sips -z $((s * 2)) $((s * 2)) logo/app-icon-1024.png --out "$set/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$set" -o ../Resources/AppIcon.icns
echo "✓ Resources/AppIcon.icns"
