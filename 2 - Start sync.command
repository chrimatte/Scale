#!/bin/zsh
set -eu
PROJECT_ROOT="${0:A:h}"
NODE="$PROJECT_ROOT/work/runtime/node_modules/.bin/node"
[[ -x "$NODE" ]] || { echo 'Local runtime is missing. Restore the complete Scale folder.' >&2; exit 1; }
cd "$PROJECT_ROOT/ble-scale-sync"
export PATH="$PROJECT_ROOT/work/runtime/node_modules/.bin:$PATH"
export TZ=Europe/Rome
if [[ ! -f .env ]]; then
  echo 'Open "1 - Connect Intervals.command" first to enter your API key.'
  read -r '?Press Return to close. '
  exit 1
fi
"$NODE" dist/index.js validate
echo 'Keep your Mac awake and near the scale. Close Renpho on your phone.'
echo 'Allow Bluetooth if macOS asks. Step on barefoot and wait for the result.'
echo 'Press Ctrl+C in this window to stop.'
exec "$NODE" dist/index.js
