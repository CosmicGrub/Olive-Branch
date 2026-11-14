#!/usr/bin/env bash
# Tear the `olive-sim` stack down. `-p olive-sim` scopes everything: only
# olive-sim containers, network and volumes are removed.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
docker compose -p olive-sim -f "$HERE/docker-compose.sim.yml" down -v --remove-orphans
echo "olive-sim removed (containers, network, olive-sim-pgdata, olive-sim-media)"
