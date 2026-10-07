#!/bin/bash
# Installs Hey AI: say "Hey Claude" (or "Hey Chatty", "Hey Codex", "Hey Claude Code")
# and that assistant opens, ready to talk.
#
#   curl -fsSL https://raw.githubusercontent.com/notorious-d-e-v/hey-ai/main/install.sh | bash
#
# What it does, and nothing else:
#   1. downloads Hey-AI.zip from the latest GitHub release,
#   2. checks it against the release's SHA-256 (and stops if that's missing or wrong),
#   3. puts "Hey AI.app" in /Applications (or ~/Applications if you can't write there),
#   4. opens it.
#
# Everything runs inside main(), so a download cut off halfway can't run half a script.
set -euo pipefail

main() {
  local repo="${HEYAI_REPO:-notorious-d-e-v/hey-ai}"
  local zip_url="${HEYAI_ZIP_URL:-https://github.com/$repo/releases/latest/download/Hey-AI.zip}"
  local app_name="Hey AI.app"

  local bold=$'\033[1m' dim=$'\033[2m' reset=$'\033[0m'
  [ -t 1 ] || { bold=""; dim=""; reset=""; }
  say() { printf '%s\n' "$*"; }
  fail() { printf 'Hey AI install failed: %s\n' "$*" >&2; exit 1; }

  [ "$(uname -s)" = "Darwin" ] || fail "Hey AI runs on macOS."
  local version major
  version=$(sw_vers -productVersion)
  major=${version%%.*}
  [ "$major" -ge 14 ] 2>/dev/null || fail "Hey AI needs macOS 14 Sonoma or later. This Mac has $version."

  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT

  say "${bold}Downloading Hey AI${reset}"
  curl -fL --progress-bar "$zip_url" -o "$tmp/Hey-AI.zip" \
    || fail "couldn't download $zip_url. Check your connection and try again."

  local expected actual
  expected=$(curl -fsSL "$zip_url.sha256" 2>/dev/null | awk '{print $1}') \
    || fail "couldn't download the checksum ($zip_url.sha256), so the download can't be checked."
  [ -n "$expected" ] || fail "the release has no checksum, so the download can't be checked."
  actual=$(shasum -a 256 "$tmp/Hey-AI.zip" | awk '{print $1}')
  [ "$expected" = "$actual" ] || fail "the download doesn't match its checksum (expected $expected, got $actual)."
  say "${dim}SHA-256 matches the release${reset}"

  ditto -x -k "$tmp/Hey-AI.zip" "$tmp/unzipped" || fail "couldn't unzip the download."
  [ -d "$tmp/unzipped/$app_name" ] || fail "the download didn't contain $app_name."

  # Update wherever it's already installed; otherwise prefer /Applications.
  local dest="" updating=false dir
  for dir in /Applications "$HOME/Applications"; do
    if [ -d "$dir/$app_name" ]; then dest="$dir"; updating=true; break; fi
  done
  if [ -z "$dest" ]; then
    dest="/Applications"
    [ -w "$dest" ] || { dest="$HOME/Applications"; mkdir -p "$dest"; }
  fi

  # Check we can replace it before stopping the running copy.
  if [ ! -w "$dest" ] || { $updating && [ ! -w "$dest/$app_name" ]; }; then
    fail "can't write to $dest/$app_name. Delete it from $dest (or ask an admin to), then run this again."
  fi

  if pkill -x HeyAI 2>/dev/null; then
    local i
    for i in 1 2 3 4 5 6 7 8 9 10; do pgrep -x HeyAI >/dev/null || break; sleep 0.5; done
  fi
  rm -rf "${dest:?}/$app_name" 2>/dev/null \
    || fail "couldn't replace $dest/$app_name. Quit Hey AI, delete it from $dest, then run this again."
  mv "$tmp/unzipped/$app_name" "$dest/" || fail "couldn't move Hey AI into $dest."

  open "$dest/$app_name"
  if $updating; then
    say "${bold}Hey AI is updated${reset} and running. Its quote mark is in your menu bar."
  else
    say "${bold}Hey AI is installed${reset} in $dest."
    say "Allow the three permissions in the window that just opened, then say ${bold}“Hey Claude”${reset}."
  fi
}

main "$@"
