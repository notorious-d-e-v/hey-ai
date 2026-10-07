#!/bin/bash
# Runs scripts/stats.py every morning at 09:05 on this Mac (and at the next wake if the
# Mac was asleep then), so GitHub's 14-day traffic window is never lost.
#
#   scripts/install-stats-job.sh            # install or update the job
#   scripts/install-stats-job.sh --remove   # remove it
set -euo pipefail

label="dev.notorious.heyai.stats"
plist="$HOME/Library/LaunchAgents/$label.plist"
script="$(cd "$(dirname "$0")" && pwd)/stats.py"
data="${HEYAI_STATS_DIR:-$HOME/workspace/hey-ai-stats}"

launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
if [ "${1:-}" = "--remove" ]; then
  rm -f "$plist"
  echo "Removed the daily Hey AI stats job."
  exit 0
fi

mkdir -p "$HOME/Library/LaunchAgents" "$data"
cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$label</string>
  <key>ProgramArguments</key>
  <array><string>/usr/bin/python3</string><string>$script</string></array>
  <key>EnvironmentVariables</key>
  <dict><key>HEYAI_STATS_DIR</key><string>$data</string></dict>
  <key>StartCalendarInterval</key>
  <dict><key>Hour</key><integer>9</integer><key>Minute</key><integer>5</integer></dict>
  <key>StandardOutPath</key><string>$data/last-run.txt</string>
  <key>StandardErrorPath</key><string>$data/last-run.txt</string>
</dict>
</plist>
EOF
launchctl bootstrap "gui/$(id -u)" "$plist"
echo "Daily Hey AI stats job installed (09:05). Data: $data"
