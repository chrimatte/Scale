#!/bin/zsh
set -eu
PROJECT_ROOT="${0:A:h}"
NODE="$PROJECT_ROOT/work/runtime/node_modules/.bin/node"
[[ -x "$NODE" ]] || { echo 'Local runtime is missing. Restore the complete Scale folder.' >&2; exit 1; }
cd "$PROJECT_ROOT/ble-scale-sync"
export PATH="$PROJECT_ROOT/work/runtime/node_modules/.bin:$PATH"
export TZ=Europe/Rome
echo 'Open https://intervals.icu/settings and find Developer / API Key.'
echo 'The key stays on this Mac and is hidden when you paste it.'
python3 - <<'PY'
import getpass
import os
from pathlib import Path
os.umask(0o077)
key = getpass.getpass('Intervals.icu API key: ').strip()
if not key or any(c in key for c in "\r\n'\\"):
    raise SystemExit('Empty or invalid key. No changes saved.')
path = Path('.env')
lines = path.read_text().splitlines() if path.exists() else []
lines = [line for line in lines if not line.strip().startswith('INTERVALS_API_KEY=')]
lines.append("INTERVALS_API_KEY='" + key + "'")
path.write_text('\n'.join(lines) + '\n')
path.chmod(0o600)
PY
"$NODE" dist/index.js validate
"$NODE" --input-type=module <<'JS'
import { loadAppConfig } from './dist/config/load.js';
import { createExporterFromEntry } from './dist/exporters/registry.js';
const { config } = loadAppConfig();
const exporter = createExporterFromEntry(config.users[0].exporters[0]);
const result = await exporter.healthcheck();
if (!result.success) {
  console.error('Connection failed: ' + result.error);
  process.exit(1);
}
console.log('Connected to Intervals.icu. The check did not change any measurements.');
JS
echo 'Now open "2 - Start sync.command".'
read -r '?Press Return to close. '
