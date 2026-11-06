#!/bin/zsh
set -eu
SOURCE_DIR="${0:A:h}"
PROJECT_ROOT="${SOURCE_DIR:h}"
APP="${SOURCE_DIR:h}/Scale.app"
mkdir -p "$PROJECT_ROOT/work/build" "$PROJECT_ROOT/work/backups" "$PROJECT_ROOT/work/swift-module-cache-overlay"
BUILD_DIR=$(mktemp -d "$PROJECT_ROOT/work/build/scale.XXXXXX")
trap 'rm -rf "$BUILD_DIR"' EXIT
BUNDLE="$BUILD_DIR/Scale.app"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
[[ -x "$PROJECT_ROOT/work/runtime/node_modules/.bin/node" && -f "$PROJECT_ROOT/ble-scale-sync/dist/index.js" ]] || {
  echo 'Mancano il runtime locale o il motore BLE. Ripristina la cartella completa di Scale.' >&2
  exit 1
}
# Isolate a duplicate legacy module map in this Mac's Command Line Tools.
# This virtual overlay leaves the system installation untouched.
/usr/bin/python3 - "$PROJECT_ROOT" <<'OVERLAY'
from pathlib import Path
import json,sys
root=Path(sys.argv[1]); empty=root/'work/empty.modulemap';empty.write_text('// Legacy duplicate hidden for this build only.\n')
overlay={'version':0,'roots':[{'type':'file','name':'/Library/Developer/CommandLineTools/usr/include/swift/module.modulemap','external-contents':str(empty)}]}
(root/'work/swift-overlay.json').write_text(json.dumps(overlay))
OVERLAY
xcrun swiftc -vfsoverlay "$PROJECT_ROOT/work/swift-overlay.json" -parse-as-library -swift-version 5 -target arm64-apple-macosx14.0 -module-cache-path "$PROJECT_ROOT/work/swift-module-cache-overlay" "$SOURCE_DIR/Pesata.swift" "$SOURCE_DIR/Settings.swift" -o "$BUNDLE/Contents/MacOS/Scale"
cp "$SOURCE_DIR/bridge.mjs" "$SOURCE_DIR/core.mjs" "$SOURCE_DIR/settings.mjs" "$BUNDLE/Contents/Resources/"
/usr/bin/python3 - "$BUNDLE" "$PROJECT_ROOT/ble-scale-sync" <<'PY'
import plistlib,sys
from pathlib import Path
app,root=sys.argv[1:]
info={'CFBundleName':'Scale','CFBundleDisplayName':'Scale','CFBundleIdentifier':'local.chrimatte.scale','CFBundleVersion':'7','CFBundleShortVersionString':'1.1.1','CFBundleExecutable':'Scale','CFBundleIconFile':'AppIcon.icns','CFBundlePackageType':'APPL','LSMinimumSystemVersion':'14.0','NSHighResolutionCapable':True,'NSBluetoothAlwaysUsageDescription':'Scale usa il Bluetooth per leggere la bilancia Renpho e inviare la tua pesata a Intervals.icu.','NSBluetoothPeripheralUsageDescription':'Scale usa il Bluetooth per leggere la tua bilancia Renpho.','ScaleProjectRoot':root}
Path(app,'Contents','Info.plist').write_bytes(plistlib.dumps(info))
PY
cp "$SOURCE_DIR/Scale.icns" "$BUNDLE/Contents/Resources/AppIcon.icns"
cp "$SOURCE_DIR/Scale.png" "$BUNDLE/Contents/Resources/Scale.png"
codesign --force --deep --sign - "$BUNDLE"
codesign --verify --deep --strict "$BUNDLE"
BACKUP_DIR=$(mktemp -d "$PROJECT_ROOT/work/backups/build.XXXXXX")
if [[ -e "$APP" ]]; then mv "$APP" "$BACKUP_DIR/Scale.app"; fi
if ! mv "$BUNDLE" "$APP"; then
  if [[ -e "$BACKUP_DIR/Scale.app" ]]; then mv "$BACKUP_DIR/Scale.app" "$APP"; fi
  exit 1
fi
echo "App creata: $APP"
