#!/bin/zsh
set -eu
PROJECT_ROOT="${0:A:h}"
NODE="$PROJECT_ROOT/work/runtime/node_modules/.bin/node"
[[ -x "$NODE" ]] || { echo 'Runtime locale assente. Ripristina la cartella completa di Scale.' >&2; exit 1; }
cd "$PROJECT_ROOT/ble-scale-sync"
export PATH="$PROJECT_ROOT/work/runtime/node_modules/.bin:$PATH"
export TZ=Europe/Rome
echo 'Apri https://intervals.icu/settings e cerca Developer / API Key.'
echo 'La chiave resta su questo Mac e non viene mostrata mentre la incolli.'
python3 - <<'PY'
import getpass
import os
from pathlib import Path
os.umask(0o077)
key = getpass.getpass('Chiave API Intervals.icu: ').strip()
if not key or any(c in key for c in "\r\n'\\"):
    raise SystemExit('Chiave vuota o non valida. Nessuna modifica salvata.')
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
  console.error('Collegamento non riuscito: ' + result.error);
  process.exit(1);
}
console.log('Intervals.icu collegato. La verifica non ha modificato alcuna misurazione.');
JS
echo 'Ora apri "2 - Avvia sincronizzazione.command".'
read -r '?Premi Invio per chiudere. '
