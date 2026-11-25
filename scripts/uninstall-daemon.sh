#!/bin/bash
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Ejecuta este script con sudo." >&2
  exit 1
fi

LABEL="com.santiagodetuna.huerequeque-zen.daemon"
DEST_BIN="/Library/PrivilegedHelperTools/$LABEL"
PLIST="/Library/LaunchDaemons/$LABEL.plist"
STATE="/Library/Application Support/HuerequequeZen/state.json"
FORCE="${1:-}"

if [[ -f "$STATE" && "$FORCE" != "--force" ]]; then
  if python3 -c '
import json, datetime, sys
data = json.load(open(sys.argv[1]))
b = data.get("activeBlock")
if b and b.get("endsAt"):
    end = datetime.datetime.fromisoformat(b["endsAt"].replace("Z", "+00:00"))
    if end > datetime.datetime.now(datetime.timezone.utc):
        sys.exit(2)
' "$STATE" 2>/dev/null; then
    :
  else
    echo "Hay un bloqueo irrompible activo. Espera a que termine (o usa --force como root)." >&2
    exit 1
  fi
fi

launchctl bootout "system/$LABEL" 2>/dev/null || true
rm -f "$PLIST" "$DEST_BIN" /var/run/huerequeque-zen.sock /etc/pf.anchors/com.santiagodetuna.huerequeque-zen
pfctl -a com.santiagodetuna.huerequeque-zen -F all 2>/dev/null || true
echo "Guardian de Huerequeque Zen desinstalado."
