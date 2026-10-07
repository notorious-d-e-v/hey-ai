#!/bin/bash
# Re-renders the README banners, social card and brand sheet from the HTML sources here.
# Needs Google Chrome. Fonts load from Google Fonts.
set -euo pipefail
cd "$(dirname "$0")"
CH="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
shot() { "$CH" --headless=new --disable-gpu --hide-scrollbars --virtual-time-budget=5000 "$@" >/dev/null 2>&1; }
for theme in light dark; do
  if [ $theme = light ]; then mark=mark-ink; word=wordmark-ink; else mark=mark-highlight; word=wordmark-white; fi
  sed -e "s/__THEME__/$theme/" -e "s/__MARK__/$mark/" -e "s/__WORD__/$word/" banner.html > ".banner-$theme.html"
  shot --force-device-scale-factor=2 --window-size=1280,420 --screenshot="../readme/banner-$theme.png" "file://$PWD/.banner-$theme.html"
  rm ".banner-$theme.html"
done
shot --window-size=1280,640 --screenshot=../readme/social-preview.png "file://$PWD/social.html"
shot --force-device-scale-factor=2 --window-size=1280,1330 --screenshot=../readme/brand-sheet.png "file://$PWD/sheet.html"
cp ../readme/social-preview.png ../../docs/social-preview.png
echo "rendered brand/readme/*.png"
