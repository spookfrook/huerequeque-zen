#!/bin/bash
set -euo pipefail

# Instala el guardian root (LaunchDaemon) de Huerequeque Zen.
# Uso: sudo ./install-daemon.sh <ruta-binario-daemon> <owner-uid>

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Este script debe ejecutarse como root." >&2
  exit 1
fi

DAEMON_SRC="${1:-}"
OWNER_UID="${2:-0}"

if [[ -z "$DAEMON_SRC" || ! -f "$DAEMON_SRC" ]]; then
  echo "Binario del guardian no encontrado: $DAEMON_SRC" >&2
  exit 1
fi

LABEL="com.santiagodetuna.huerequeque-zen.daemon"
DEST_BIN="/Library/PrivilegedHelperTools/$LABEL"
PLIST="/Library/LaunchDaemons/$LABEL.plist"
SUPPORT_DIR="/Library/Application Support/HuerequequeZen"
LOG_DIR="/Library/Logs/HuerequequeZen"

mkdir -p /Library/PrivilegedHelperTools "$SUPPORT_DIR" "$LOG_DIR"
chmod 755 "$SUPPORT_DIR" "$LOG_DIR"

# Guardar UID del usuario propietario para autorizar IPC por getpeereid()
printf '%s\n' "$OWNER_UID" > "$SUPPORT_DIR/owner.uid"
chown root:wheel "$SUPPORT_DIR/owner.uid"
chmod 644 "$SUPPORT_DIR/owner.uid"

# Detener instancia previa del daemon si existia (sin borrar state.json)
launchctl bootout "system/$LABEL" 2>/dev/null || true

install -m 755 -o root -g wheel "$DAEMON_SRC" "$DEST_BIN"

cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$DEST_BIN</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>$LOG_DIR/stdout.log</string>
  <key>StandardErrorPath</key>
  <string>$LOG_DIR/stderr.log</string>
  <key>ProcessType</key>
  <string>Background</string>
</dict>
</plist>
PLIST

chown root:wheel "$PLIST"
chmod 644 "$PLIST"

launchctl bootstrap system "$PLIST"
launchctl kickstart -k "system/$LABEL" 2>/dev/null || true
echo "Huerequeque Zen daemon instalado y activo ($LABEL)."
