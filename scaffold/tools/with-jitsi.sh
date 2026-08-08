#!/usr/bin/env bash
# Bring the local self-hosted Jitsi stack up, wait for it to answer, run a
# command against it if given, and (unlike with-livekit.sh) leave it running
# by default — a multi-container compose stack is too slow to cycle per test
# run the way a single livekit-server binary is. Pass `down` to tear it down.
#
# §16.2 #6 Step 2 staging. See tools/jitsi-selfhost/README.md for what this
# does and does not verify. LOCAL DEV/TEST ONLY.
set -u
cd "$(dirname "${BASH_SOURCE[0]}")/jitsi-selfhost/.jitsi-docker" 2>/dev/null || {
  echo "tools/jitsi-selfhost/.jitsi-docker not found — run tools/jitsi-selfhost/setup.sh first." >&2
  exit 2
}

HTTPS_PORT=$(grep -E '^HTTPS_PORT=' .env 2>/dev/null | cut -d= -f2)
HTTPS_PORT=${HTTPS_PORT:-8443}

if [ "${1:-}" = "down" ]; then
  docker compose down
  exit $?
fi

docker compose up -d
for i in $(seq 1 40); do
  curl -sfk -o /dev/null "https://127.0.0.1:${HTTPS_PORT}/" && break
  sleep 3
done
if ! curl -sfk -o /dev/null "https://127.0.0.1:${HTTPS_PORT}/"; then
  echo "Jitsi web UI never came up on :${HTTPS_PORT} — check container health:" >&2
  docker compose ps
  docker compose logs --tail 50
  exit 2
fi

echo "Jitsi is up: https://127.0.0.1:${HTTPS_PORT} (self-signed cert)"
if [ "$#" -gt 0 ]; then
  "$@"; rc=$?
  exit $rc
fi
