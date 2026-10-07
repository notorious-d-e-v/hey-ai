#!/bin/bash
# Removes Hey AI, its login item, its settings, its logs and its macOS permissions.
#
#   curl -fsSL https://raw.githubusercontent.com/notorious-d-e-v/hey-ai/main/uninstall.sh | bash
set -euo pipefail

BUNDLE_ID="dev.notorious.heyai"

for dir in /Applications "$HOME/Applications"; do
  app="$dir/Hey AI.app"
  [ -d "$app" ] || continue
  # Turn off launch at login while the app can still unregister itself.
  open -g "heyai://login/off" 2>/dev/null && sleep 1 || true
  pkill -x HeyAI 2>/dev/null || true
  rm -rf "$app"
  echo "Removed $app"
done

defaults delete "$BUNDLE_ID" 2>/dev/null || true
rm -rf "$HOME/Library/Logs/HeyAI"
# Forget the Microphone, Speech Recognition and Accessibility permissions.
tccutil reset All "$BUNDLE_ID" >/dev/null 2>&1 || true
echo "Hey AI is uninstalled."
