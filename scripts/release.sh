#!/bin/bash
# Builds a release: dist/Hey-AI.zip and dist/Hey-AI.zip.sha256, ready to attach to a
# GitHub release (install.sh downloads releases/latest/download/Hey-AI.zip).
set -euo pipefail
cd "$(dirname "$0")/.."

./build.sh
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)
rm -rf dist && mkdir dist
ditto -c -k --sequesterRsrc --keepParent "build/Hey AI.app" dist/Hey-AI.zip
(cd dist && shasum -a 256 Hey-AI.zip > Hey-AI.zip.sha256)
echo "✓ Hey AI $version → dist/Hey-AI.zip ($(du -h dist/Hey-AI.zip | cut -f1))"
echo "  publish: gh release create v$version dist/Hey-AI.zip dist/Hey-AI.zip.sha256 --title \"Hey AI $version\" --notes-file RELEASE_NOTES.md"
