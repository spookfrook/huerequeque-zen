#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/Huerequeque Zen.app"
ARCH="$(uname -m)"

mkdir -p "$ROOT/.build" "$APP/Contents/MacOS" "$APP/Contents/Resources"

# 1. Regenerar iconos vectoriales si falta alguno
if [[ ! -f "$ROOT/Resources/Huerequeque.png" || ! -f "$ROOT/Resources/HuerequequeIcon.png" ]]; then
  node "$ROOT/scripts/render-icon.mjs"
fi

# 2. Compilar binario de la app (barra de menu + popover SwiftUI)
swiftc -O -whole-module-optimization \
  -target "${ARCH}-apple-macos13.0" \
  -framework AppKit \
  -framework SwiftUI \
  -framework Combine \
  "$ROOT"/Sources/Shared/*.swift \
  "$ROOT"/Sources/App/*.swift \
  -o "$APP/Contents/MacOS/huerequeque-zen"

# 3. Compilar binario del guardian root (LaunchDaemon)
swiftc -O -whole-module-optimization \
  -target "${ARCH}-apple-macos13.0" \
  -framework Foundation \
  "$ROOT"/Sources/Shared/Models.swift \
  "$ROOT"/Sources/Shared/HostsFileEditor.swift \
  "$ROOT"/Sources/Shared/PFConfigGenerator.swift \
  "$ROOT"/Sources/Shared/SocketIPC.swift \
  "$ROOT"/Sources/Daemon/*.swift \
  -o "$APP/Contents/MacOS/huerequeque-zen-daemon"

# 4. Recursos e instalador del guardian
cp "$ROOT/Resources/Huerequeque.png" "$APP/Contents/Resources/Huerequeque.png"
cp "$ROOT/scripts/install-daemon.sh" "$APP/Contents/Resources/install-daemon.sh"
chmod 755 "$APP/Contents/Resources/install-daemon.sh"

# 5. Generar AppIcon.icns (usando la version simplificada para 16 px)
ICONSET="$ROOT/.build/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  if [[ "$size" -eq 16 && -f "$ROOT/Resources/HuerequequeSmall32.png" ]]; then
    sips -z 16 16 "$ROOT/Resources/HuerequequeSmall32.png" --out "$ICONSET/icon_16x16.png" >/dev/null
    cp "$ROOT/Resources/HuerequequeSmall32.png" "$ICONSET/icon_16x16@2x.png"
  else
    sips -z "$size" "$size" "$ROOT/Resources/HuerequequeIcon.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$ROOT/Resources/HuerequequeIcon.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
  fi
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

# 6. Info.plist (LSUIElement = true, solo barra de menu)
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.santiagodetuna.huerequeque-zen</string>
<key>CFBundleName</key><string>Huerequeque Zen</string>
<key>CFBundleDisplayName</key><string>Huerequeque Zen</string>
<key>CFBundleExecutable</key><string>huerequeque-zen</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST

codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
echo "$APP"
