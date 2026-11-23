#!/usr/bin/env bash
# Build the live CHILD and GUARDIAN shells against the local dev server and push them to the two test devices.
# Re-run after every change: it rebuilds, reinstalls in place (no uninstall, data kept), and refreshes `adb reverse`.
#
#   FOLD=<serial> TAB=<serial> [ADB=<path to adb>] bash tools/device-sync.sh [child|guardian|both]
#
# FOLD = the phone that gets the guardian shell (dev login), TAB = the tablet that gets the child shell (real
# pairing). Serials come from `adb devices`; there are no defaults, because a serial does not belong in a public
# repository. ADB defaults to the `adb` on PATH. Needs the dev stack
#   docker compose -p olive-fresh -f docker-compose.dev.yml up -d --build db migrate server delivery
# (the `delivery` worker is what moves a banked message into the child's inbox) and, for the guardian shell,
# DEV_LOGIN=1 in scaffold/.env plus `node server/seed-dev.mjs`. The server must answer on 127.0.0.1:$PORT (default
# 8123); this script then runs `adb reverse` so the device reaches it. It never launches an app and never
# uninstalls one. Signing: release, debug-signed (olive.allowDebugSignedRelease).
#
# Cleartext: a release build refuses plain http by design. These device builds reach the server over `adb reverse`
# (http to the phone's own 127.0.0.1), so they alone pass --dart-define=OLIVE_ALLOW_DEV_CLEARTEXT=true, which lets
# the app speak http to the literal addresses 127.0.0.1 and ::1 and to nothing else (lib/server_transport_policy.dart).
# No other script, workflow, Dockerfile or release config may pass it: tools/check-dev-cleartext.mjs fails CI if one does.
#
# Simulated connect: with SIMULATE_CONNECT=1 the builds also pass --dart-define=OLIVE_SIMULATE_CONNECT=true, which adds a
# dev-only "Simulate her tablet" (phone) and "Simulate a phone" (tablet) so ONE device can walk the connect flow with a simulated
# other end (lib/connect_simulation.dart). Off unless asked; tools/check-simulate-connect.mjs fails CI if any other script,
# workflow, Dockerfile or release config passes it.
set -euo pipefail
WHICH="${1:-both}"
ADB="${ADB:-adb}"
FOLD="${FOLD:-}"
TAB="${TAB:-}"
PORT="${PORT:-8123}"
URL="http://127.0.0.1:${PORT}"
OUT="${OUT:-$(mktemp -d)}"
cd "$(dirname "$0")/../client"

# Push: when the owner has turned their google-services.json into settings (node tools/fcm-defines.mjs), every build
# below carries them; without the file nothing changes and the app simply has no push. The file lives in the
# git-ignored scaffold/secrets/ folder and is never printed.
FCM_DEFINES="${FCM_DEFINES:-../secrets/fcm.defines.json}"
FCM_ARGS=()
SIM_ARGS=()
if [ "${SIMULATE_CONNECT:-}" = 1 ]; then SIM_ARGS=(--dart-define=OLIVE_SIMULATE_CONNECT=true); echo "dev seam: simulated connect is ON in these builds"; fi
if [ -f "$FCM_DEFINES" ]; then FCM_ARGS=(--dart-define-from-file="$FCM_DEFINES"); echo "push: using the Firebase settings in the secrets folder"; fi

# Developer-only: OLIVE_DEV_FIRST_RUN_PREVIEW=1 builds the guardian shell so it opens the grown-up's first run (Choose
# your PIN included) over an in-memory store, on a phone that is already set up. Nothing on the phone is read or changed.
# Off unless asked for; tools/check-dev-first-run.mjs fails CI if any other file passes the define.
FIRSTRUN_ARGS=()
if [ "${OLIVE_DEV_FIRST_RUN_PREVIEW:-}" = 1 ]; then
  FIRSTRUN_ARGS=(--dart-define=OLIVE_DEV_GUARDIAN_FIRST_RUN=true)
  echo "first-run preview: the guardian build opens the first run over an in-memory store"
fi

build() { # $1 entry, $2 name, rest = extra dart-defines
  local entry="$1" name="$2"; shift 2
  echo "== build $name"
  flutter build apk --release --target-platform android-arm64 -t "lib/$entry.dart" \
    --dart-define=OLIVE_API_BASE_URL="$URL" --dart-define=OLIVE_ALLOW_SCREENSHOTS=true --dart-define=OLIVE_ALLOW_DEV_CLEARTEXT=true ${FCM_ARGS[@]+"${FCM_ARGS[@]}"} ${SIM_ARGS[@]+"${SIM_ARGS[@]}"} "$@" \
    --android-project-arg=olive.allowDebugSignedRelease=true >"$OUT/$name.log" 2>&1 || { tail -20 "$OUT/$name.log"; exit 1; }
  cp build/app/outputs/flutter-apk/app-release.apk "$OUT/$name.apk"
}
push() { # $1 serial, $2 apk
  echo "== install $2 -> $1"
  "$ADB" -s "$1" install -r "$OUT/$2.apk" | tail -1
  "$ADB" -s "$1" reverse "tcp:$PORT" "tcp:$PORT" >/dev/null
  "$ADB" -s "$1" shell "dumpsys package com.olivebranch.olive_client | grep -m1 lastUpdateTime" | tr -d '\r'
}
curl -fsS -m 5 "$URL/readyz" >/dev/null || { echo "server not ready at $URL (GET /readyz)"; exit 1; }
if [ "$WHICH" = child ] || [ "$WHICH" = both ]; then
  [ -n "$TAB" ] || { echo "set TAB=<tablet serial> (see: adb devices)"; exit 2; }
  build main_live child; push "$TAB" child
fi
if [ "$WHICH" = guardian ] || [ "$WHICH" = both ]; then
  [ -n "$FOLD" ] || { echo "set FOLD=<phone serial> (see: adb devices)"; exit 2; }
  build main_live_guardian guardian --dart-define=OLIVE_DEV_LOGIN=1 ${FIRSTRUN_ARGS[@]+"${FIRSTRUN_ARGS[@]}"}; push "$FOLD" guardian
fi
echo "done. apks in $OUT"
