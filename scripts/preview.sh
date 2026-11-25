#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCH="$(uname -m)"
APP="$ROOT/.build/Preview.app"
OUT="$ROOT/.build/previews"

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$OUT"
cp "$ROOT/Resources/Huerequeque.png" "$APP/Contents/Resources/Huerequeque.png"

swiftc -O \
  -target "${ARCH}-apple-macos13.0" \
  -framework AppKit \
  -framework SwiftUI \
  -framework Combine \
  "$ROOT"/Sources/Shared/*.swift \
  "$ROOT"/Sources/App/StatusMark.swift \
  "$ROOT"/Sources/App/ZenDial.swift \
  "$ROOT"/Sources/App/ZenStore.swift \
  "$ROOT"/Sources/App/Panel.swift \
  "$ROOT/tests/PreviewMain.swift" \
  -o "$APP/Contents/MacOS/preview"

"$APP/Contents/MacOS/preview" "$OUT"
