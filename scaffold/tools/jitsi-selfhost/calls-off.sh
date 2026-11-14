#!/usr/bin/env bash
# calls-off.sh — switch calls OFF: stop the self-hosted Jitsi compose project
# (and only that project). Containers and the prosody volumes are kept, so
# ./calls-on.sh is quick and the JWT/TURN/cert config survives.
#
#   ./calls-off.sh          stop the containers
#   ./calls-off.sh --down   also remove the containers (volumes stay)
#
# Environment: JITSI_STACK_DIR, JITSI_PROJECT (same as calls-on.sh).
# Never touches any other container (olive-fresh-* etc.).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
STACK_DIR="${JITSI_STACK_DIR:-$PWD/.jitsi-docker}"
PROJECT="${JITSI_PROJECT:-jitsi-docker}"
MODE=stop
case "${1:-}" in
  "") ;;
  --down) MODE=down ;;
  -h|--help) sed -n '2,10p' "${BASH_SOURCE[0]}"; exit 0 ;;
  *) echo "unknown option: $1" >&2; exit 2 ;;
esac

if [ ! -f "$STACK_DIR/docker-compose.yml" ]; then
  echo "No Jitsi stack at $STACK_DIR (set JITSI_STACK_DIR). Nothing to switch off." >&2
  exit 2
fi
if ! docker info >/dev/null 2>&1; then
  echo "Docker is not running, so no Jitsi container can be running either. Nothing to do."
  exit 0
fi
cd "$STACK_DIR"
docker compose -p "$PROJECT" "$MODE"
echo "Calls are OFF (project $PROJECT: $MODE). Other containers were not touched."
