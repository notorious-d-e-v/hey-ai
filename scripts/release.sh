#!/bin/bash
# Builds a release: dist/Hey-AI.zip and dist/Hey-AI.zip.sha256 (install.sh downloads
# releases/latest/download/Hey-AI.zip and checks it against the .sha256).
#
# Public releases are built by .github/workflows/release.yml when you push a tag:
#   git tag v1.0.0 && git push origin v1.0.0
# Run this locally to test a release build.
set -euo pipefail
cd "$(dirname "$0")/.."

./build.sh
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Info.plist)
rm -rf dist && mkdir dist
ditto -c -k --sequesterRsrc --keepParent "build/Hey AI.app" dist/Hey-AI.zip
(cd dist && shasum -a 256 Hey-AI.zip > Hey-AI.zip.sha256)
echo "✓ Hey AI $version → dist/Hey-AI.zip ($(du -h dist/Hey-AI.zip | cut -f1))"
echo "  to publish: git tag v$version && git push origin v$version (GitHub Actions builds and releases it)"
