#!/bin/zsh
set -eu
SOURCE_DIR="${0:A:h}"
PROJECT_ROOT="${SOURCE_DIR:h}"
APP="$PROJECT_ROOT/Scale.app"
DESTINATION="$HOME/Applications/Scale.app"
[[ -d "$APP" ]] || { echo 'Esegui prima Scale-sorgenti/build.sh.' >&2; exit 1; }
/usr/bin/python3 - "$APP/Contents/Info.plist" "$PROJECT_ROOT/ble-scale-sync" <<'PY'
import plistlib, sys
from pathlib import Path
with open(sys.argv[1], 'rb') as f:
    root = plistlib.load(f).get('ScaleProjectRoot')
if root != str(Path(sys.argv[2]).resolve()):
    raise SystemExit('La cartella è cambiata. Esegui prima Scale-sorgenti/build.sh.')
PY
set +e
/usr/bin/pgrep -x Scale >/dev/null
PROCESS_STATUS=$?
set -e
case "$PROCESS_STATUS" in
  0) echo 'Chiudi Scale prima di reinstallarla.' >&2; exit 1 ;;
  1) ;;
  *) echo 'Impossibile verificare se Scale è chiusa. Installazione annullata.' >&2; exit 1 ;;
esac
codesign --verify --deep --strict "$APP"
mkdir -p "$HOME/Applications" "$PROJECT_ROOT/work/backups"
BACKUP_DIR=$(mktemp -d "$PROJECT_ROOT/work/backups/install.XXXXXX")
STAGING=$(mktemp -d "$HOME/Applications/.scale-install.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
/usr/bin/ditto "$APP" "$STAGING/Scale.app"
codesign --verify --deep --strict "$STAGING/Scale.app"
if [[ -e "$DESTINATION" ]]; then mv "$DESTINATION" "$BACKUP_DIR/Scale.app"; fi
if ! mv "$STAGING/Scale.app" "$DESTINATION"; then
  if [[ -e "$BACKUP_DIR/Scale.app" ]]; then mv "$BACKUP_DIR/Scale.app" "$DESTINATION"; fi
  exit 1
fi
codesign --verify --deep --strict "$DESTINATION"
echo "Scale installata: $DESTINATION"
echo "Copia precedente: $BACKUP_DIR"
