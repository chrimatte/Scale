#!/bin/zsh
set -eu
PROJECT_ROOT="${0:A:h}"
NODE="$PROJECT_ROOT/work/runtime/node_modules/.bin/node"
[[ -x "$NODE" ]] || { echo 'Runtime locale assente. Ripristina la cartella completa di Scale.' >&2; exit 1; }
cd "$PROJECT_ROOT/ble-scale-sync"
export PATH="$PROJECT_ROOT/work/runtime/node_modules/.bin:$PATH"
export TZ=Europe/Rome
if [[ ! -f .env ]]; then
  echo 'Apri prima "1 - Collega Intervals.command" per inserire la chiave API.'
  read -r '?Premi Invio per chiudere. '
  exit 1
fi
"$NODE" dist/index.js validate
echo 'Tieni il Mac acceso e vicino alla bilancia. Chiudi Renpho sul telefono.'
echo 'Consenti il Bluetooth se macOS lo richiede. Sali a piedi nudi e attendi il risultato.'
echo 'Per interrompere premi Ctrl+C in questa finestra.'
exec "$NODE" dist/index.js
