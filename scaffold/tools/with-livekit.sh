#!/usr/bin/env bash
# Start a livekit-server, run a command against it, stop it. The server does not
# survive between shells, and a suite that silently skips when its dependency is
# absent is a false green — so this wrapper owns the lifecycle.
set -u
BIN=${LIVEKIT_BIN:-/tmp/livekit-server}
CFG=${LIVEKIT_CFG:-/tmp/lk.yaml}
[ -x "$BIN" ] || { echo "livekit-server not found at $BIN"; exit 2; }
"$BIN" --config "$CFG" >/tmp/lk.log 2>&1 &
LK=$!
for i in $(seq 1 25); do
  curl -sf -o /dev/null http://127.0.0.1:7880/ && break
  sleep 0.4
done
curl -sf -o /dev/null http://127.0.0.1:7880/ || { echo "livekit failed to start"; cat /tmp/lk.log; kill $LK 2>/dev/null; exit 2; }
"$@"; rc=$?
kill $LK 2>/dev/null; wait $LK 2>/dev/null
exit $rc
