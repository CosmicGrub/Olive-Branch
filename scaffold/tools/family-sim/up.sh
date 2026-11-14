#!/usr/bin/env bash
# Bring up the throwaway `olive-sim` stack and wait until the server is healthy.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
F="$HERE/docker-compose.sim.yml"
if ! docker ps >/dev/null 2>&1; then
  echo "docker engine unavailable -- start Docker Desktop, or use the in-process harness (see docs/operators/family-sim.md)" >&2
  exit 2
fi
docker compose -p olive-sim -f "$F" up -d --build
echo "waiting for olive-sim server health..."
for i in $(seq 1 90); do
  st="$(docker inspect -f '{{.State.Health.Status}}' olive-sim-server-1 2>/dev/null || echo none)"
  if [ "$st" = "healthy" ]; then echo "olive-sim ready: server http://127.0.0.1:8141  db 127.0.0.1:5481"; exit 0; fi
  sleep 2
done
echo "olive-sim did not become healthy" >&2
docker compose -p olive-sim -f "$F" logs --tail 40 >&2 || true
exit 1
