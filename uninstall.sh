#!/bin/bash
# Removes Hey AI, its login item, its settings, its logs and its macOS permissions.
#
#   curl -fsSL https://raw.githubusercontent.com/notorious-d-e-v/hey-ai/main/uninstall.sh | bash
#
# Each step carries on if another fails; anything left behind is listed at the end.
set -uo pipefail

main() {
  local bundle_id="dev.notorious.heyai"
  local left=()

  local found=false dir app
  for dir in /Applications "$HOME/Applications"; do
    [ -d "$dir/Hey AI.app" ] && found=true
  done

  # Hey AI can only remove its own login item while it's running.
  if pgrep -x HeyAI >/dev/null; then
    open -g "heyai://login/off" && sleep 1.5
    pkill -x HeyAI 2>/dev/null
    sleep 0.5
  elif $found; then
    left+=("If Hey AI still appears in System Settings → General → Login Items, remove it there.")
  fi

  for dir in /Applications "$HOME/Applications"; do
    app="$dir/Hey AI.app"
    [ -d "$app" ] || continue
    if rm -rf "$app" 2>/dev/null; then
      echo "Removed $app"
    else
      left+=("Couldn't delete $app. Drag it to the Trash.")
    fi
  done

  defaults delete "$bundle_id" >/dev/null 2>&1
  rm -rf "$HOME/Library/Logs/HeyAI"

  # Forget the Microphone, Speech Recognition and Accessibility permissions.
  if ! tccutil reset All "$bundle_id" >/dev/null 2>&1; then
    left+=("Couldn't reset its permissions. Remove Hey AI under System Settings → Privacy & Security → Microphone, Speech Recognition and Accessibility.")
  fi

  if [ ${#left[@]} -eq 0 ]; then
    echo "Hey AI is uninstalled."
  else
    echo "Hey AI is mostly uninstalled. Left to do:"
    printf '  - %s\n' "${left[@]}"
  fi
}

main "$@"
