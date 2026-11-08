#!/usr/bin/env bash
# Build the live CHILD and GUARDIAN shells against the local dev server and push them to the two test devices.
# Re-run after every change: it rebuilds, reinstalls in place (no uninstall, data kept), and refreshes `adb reverse`.
#
#   FOLD=<serial> TAB=<serial> bash tools/device-sync.sh [child|guardian|both]
#
# Defaults: Fold5 = guardian shell (dev login), Tab S9 FE = child shell (real pairing). Needs the dev stack
# (docker compose -f docker-compose.dev.yml up -d db migrate server) and DEV_LOGIN=1 in scaffold/.env.
# It never launches an app and never uninstalls one. Signing: release, debug-signed (olive.allowDebugSignedRelease).
set -euo pipefail
WHICH="${1:-both}"
ADB="${ADB:-/c/Users/Obliv/android-sdk/platform-tools/adb}"
FOLD="${FOLD:-RFCW80CK2RW}"
TAB="${TAB:-R52X101MB6W}"
PORT="${PORT:-8123}"
URL="http://127.0.0.1:${PORT}"
OUT="${OUT:-$(mktemp -d)}"
cd "$(dirname "$0")/../client"

build() { # $1 entry, $2 name, rest = extra dart-defines
  local entry="$1" name="$2"; shift 2
  echo "== build $name"
  flutter build apk --release --target-platform android-arm64 -t "lib/$entry.dart" \
    --dart-define=OLIVE_API_BASE_URL="$URL" "$@" \
    --android-project-arg=olive.allowDebugSignedRelease=true >"$OUT/$name.log" 2>&1 || { tail -20 "$OUT/$name.log"; exit 1; }
  cp build/app/outputs/flutter-apk/app-release.apk "$OUT/$name.apk"
}
push() { # $1 serial, $2 apk
  echo "== install $2 -> $1"
  "$ADB" -s "$1" install -r "$OUT/$2.apk" | tail -1
  "$ADB" -s "$1" reverse "tcp:$PORT" "tcp:$PORT" >/dev/null
  "$ADB" -s "$1" shell "dumpsys package com.olivebranch.olive_client | grep -m1 lastUpdateTime" | tr -d '\r'
}
curl -fsS -m 5 "$URL/healthz" >/dev/null || { echo "server not healthy at $URL"; exit 1; }
if [ "$WHICH" = child ] || [ "$WHICH" = both ]; then build main_live child; push "$TAB" child; fi
if [ "$WHICH" = guardian ] || [ "$WHICH" = both ]; then build main_live_guardian guardian --dart-define=OLIVE_DEV_LOGIN=1; push "$FOLD" guardian; fi
echo "done. apks in $OUT"
