#!/bin/bash
# Installs Hey AI: say "Hey Claude" (or "Hey Chatty", "Hey Codex", "Hey Claude Code")
# and that assistant opens, ready to talk.
#
#   curl -fsSL https://raw.githubusercontent.com/notorious-d-e-v/hey-ai/main/install.sh | bash
#
# Downloads the latest release, checks its SHA-256, puts "Hey AI.app" in /Applications
# (or ~/Applications) and opens it. Nothing else on your Mac is changed.
set -euo pipefail

REPO="${HEYAI_REPO:-notorious-d-e-v/hey-ai}"
ZIP_URL="${HEYAI_ZIP_URL:-https://github.com/$REPO/releases/latest/download/Hey-AI.zip}"
APP_NAME="Hey AI.app"

bold=$'\033[1m'; dim=$'\033[2m'; reset=$'\033[0m'
[ -t 1 ] || { bold=""; dim=""; reset=""; }
say() { printf '%s\n' "$*"; }
fail() { printf 'Hey AI install failed: %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || fail "Hey AI runs on macOS."
major=$(sw_vers -productVersion | cut -d. -f1)
[ "$major" -ge 14 ] || fail "Hey AI needs macOS 14 Sonoma or later (this Mac has $(sw_vers -productVersion))."

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

say "${bold}Downloading Hey AI${reset}"
curl -fL --progress-bar "$ZIP_URL" -o "$tmp/Hey-AI.zip" || fail "couldn't download $ZIP_URL"

if expected=$(curl -fsSL "$ZIP_URL.sha256" 2>/dev/null | awk '{print $1}') && [ -n "$expected" ]; then
  actual=$(shasum -a 256 "$tmp/Hey-AI.zip" | awk '{print $1}')
  [ "$expected" = "$actual" ] || fail "checksum mismatch (expected $expected, got $actual)"
  say "${dim}Checksum OK${reset}"
fi

ditto -x -k "$tmp/Hey-AI.zip" "$tmp/unzipped" || fail "couldn't unzip the download"
[ -d "$tmp/unzipped/$APP_NAME" ] || fail "the download didn't contain $APP_NAME"

dest="/Applications"
[ -w "$dest" ] || { dest="$HOME/Applications"; mkdir -p "$dest"; }

pkill -x HeyAI 2>/dev/null && sleep 0.5 || true
rm -rf "$dest/$APP_NAME"
mv "$tmp/unzipped/$APP_NAME" "$dest/"
# Downloads made with curl aren't quarantined, but clear the flag in case.
xattr -dr com.apple.quarantine "$dest/$APP_NAME" 2>/dev/null || true

open "$dest/$APP_NAME"
say "${bold}Hey AI is installed${reset} in $dest."
say "Allow the three permissions in the window that just opened, then say ${bold}“Hey Claude”${reset}."
