#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
"$ROOT/scripts/build-app.sh"

if pgrep -x huerequeque-zen >/dev/null; then
  pkill -x huerequeque-zen || true
  sleep 0.5
fi

DEST="/Applications/Huerequeque Zen.app"
if [[ -e "$DEST" ]]; then
  ID="$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$DEST/Contents/Info.plist")"
  [[ "$ID" == "com.santiagodetuna.huerequeque-zen" ]] || { echo "Bundle ID inesperado en $DEST: $ID" >&2; exit 1; }
  rm -rf "$DEST"
fi

ditto "$ROOT/dist/Huerequeque Zen.app" "$DEST"
codesign --verify --deep --strict "$DEST"
echo "Instalado en $DEST"
