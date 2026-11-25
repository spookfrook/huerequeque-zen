#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ARCH="$(uname -m)"
mkdir -p "$ROOT/.build"

swiftc -O \
  -target "${ARCH}-apple-macos13.0" \
  -framework Foundation \
  "$ROOT/Sources/Shared/Models.swift" \
  "$ROOT/Sources/Shared/HostsFileEditor.swift" \
  "$ROOT/Sources/Shared/PFConfigGenerator.swift" \
  "$ROOT/Sources/Shared/SocketIPC.swift" \
  "$ROOT/Sources/Daemon/DaemonCore.swift" \
  "$ROOT/tests/CoreTests.swift" \
  -o "$ROOT/.build/core-tests"

"$ROOT/.build/core-tests"
