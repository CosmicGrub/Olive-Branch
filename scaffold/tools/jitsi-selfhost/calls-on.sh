#!/usr/bin/env bash
# calls-on.sh — switch calls ON: start the self-hosted Jitsi compose project
# (and only that project), wait until it answers, print the LAN URL.
#
# Calls work on the LAN (same Wi-Fi as this PC) only while this PC is on and
# this has been run. See docs/calls-on-the-lan.md.
#
#   ./calls-on.sh                  start + wait + print the LAN URL
#   ./calls-on.sh --server-env     also (re)write olive-server.env next to the
#                                  stack (mode 600) with the CALL_PROVIDER /
#                                  JITSI_* lines the Olive server needs; the
#                                  secret is never printed, only the file path
#   ./calls-on.sh --recreate       allow applying the JWT config to a stack
#                                  that is ALREADY RUNNING (this restarts its
#                                  containers; without the flag, we refuse)
#   ./calls-on.sh --timeout 180    seconds to wait for health (default 120)
#
# Environment:
#   JITSI_STACK_DIR   the docker-jitsi-meet checkout (default: ./.jitsi-docker,
#                     created by setup.sh)
#   JITSI_PROJECT     compose project name (default: jitsi-docker)
#
# Never touches any other container (olive-fresh-* etc.): every docker call
# below is `docker compose -p <jitsi project>`.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
HERE="$PWD"

STACK_DIR="${JITSI_STACK_DIR:-$HERE/.jitsi-docker}"
PROJECT="${JITSI_PROJECT:-jitsi-docker}"
WRITE_SERVER_ENV=0
RECREATE=0
TIMEOUT=120
while [ $# -gt 0 ]; do
  case "$1" in
    --server-env) WRITE_SERVER_ENV=1 ;;
    --recreate)   RECREATE=1 ;;
    --timeout)    shift; TIMEOUT="${1:?--timeout needs seconds}" ;;
    -h|--help)    sed -n '2,25p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

if [ ! -f "$STACK_DIR/.env" ] || [ ! -f "$STACK_DIR/docker-compose.yml" ]; then
  echo "No Jitsi stack at $STACK_DIR." >&2
  echo "Run ./setup.sh first, or point JITSI_STACK_DIR at your docker-jitsi-meet checkout." >&2
  exit 2
fi
if ! docker info >/dev/null 2>&1; then
  echo "Docker is not running. Start Docker Desktop, wait for it to say 'running', then run this again." >&2
  exit 2
fi

cd "$STACK_DIR"
dc() { docker compose -p "$PROJECT" "$@"; }
envval() { grep -E "^$1=" .env | tail -n 1 | cut -d= -f2- || true; }

# --- JWT auth: per-participant tokens, no anonymous guests -------------------
# The Olive server mints one short-lived JWT per participant (adults moderate,
# the child does not). That only means something if the stack REQUIRES a token.
# Idempotent: added once, never rotated here (the server must keep matching it).
JWT_ADDED=0
if ! grep -q '^JWT_APP_SECRET=' .env; then
  if [ -n "$(dc ps -q 2>/dev/null)" ] && [ "$RECREATE" != 1 ]; then
    echo "The stack is already running without JWT auth. Applying it restarts the Jitsi containers." >&2
    echo "Run again with --recreate when no call is in progress." >&2
    exit 2
  fi
  SECRET="$(openssl rand -hex 32)"
  {
    echo ""
    echo "# --- Olive call auth (added by calls-on.sh) ---"
    echo "ENABLE_AUTH=1"
    echo "AUTH_TYPE=jwt"
    echo "ENABLE_GUESTS=0"
    echo "JWT_APP_ID=olive-calls"
    echo "JWT_APP_SECRET=$SECRET"
    echo "JWT_ACCEPTED_ISSUERS=olive-calls"
    echo "JWT_ACCEPTED_AUDIENCES=jitsi"
  } >> .env
  JWT_ADDED=1
  echo "JWT auth configured in $STACK_DIR/.env (secret generated, not shown)."
fi

# --- the address devices will use --------------------------------------------
HTTPS_PORT="$(envval HTTPS_PORT)"; HTTPS_PORT="${HTTPS_PORT:-8443}"
PUBLIC_URL="$(envval PUBLIC_URL)"
ADV_IP="$(envval JVB_ADVERTISE_IPS)"
TURN_HOST="$(envval TURN_HOST)"
if [ -z "$ADV_IP" ] || [ -z "$TURN_HOST" ] || [ -z "$PUBLIC_URL" ]; then
  echo "JVB_ADVERTISE_IPS, TURN_HOST and PUBLIC_URL must all be set in $STACK_DIR/.env" >&2
  echo "(this PC's LAN IP; see olive.env and README.md). Refusing to start a stack phones cannot reach." >&2
  exit 2
fi
case "$PUBLIC_URL" in https://*) ;; *) echo "PUBLIC_URL must be https:// (got $PUBLIC_URL)" >&2; exit 2 ;; esac
if [ "$ADV_IP" != "$TURN_HOST" ] || [ "$PUBLIC_URL" != "https://$ADV_IP:$HTTPS_PORT" ]; then
  echo "Warning: JVB_ADVERTISE_IPS ($ADV_IP), TURN_HOST ($TURN_HOST) and PUBLIC_URL ($PUBLIC_URL) should name the same address." >&2
fi

echo "Starting Jitsi (project $PROJECT) ..."
dc up -d

# --- wait for it to answer ---------------------------------------------------
deadline=$(( $(date +%s) + TIMEOUT ))
ok=0
while [ "$(date +%s)" -lt "$deadline" ]; do
  if curl -sfk -o /dev/null "https://127.0.0.1:${HTTPS_PORT}/"; then ok=1; break; fi
  sleep 3
done
if [ "$ok" != 1 ]; then
  echo "Jitsi did not answer on :${HTTPS_PORT} within ${TIMEOUT}s. Container state:" >&2
  dc ps >&2 || true
  echo "Logs: docker compose -p $PROJECT logs --tail 50  (run inside $STACK_DIR)" >&2
  exit 2
fi
# the media bridge and the signalling server are what a call actually needs
for svc in prosody jvb; do
  if [ -z "$(dc ps -q --status running "$svc" 2>/dev/null)" ]; then
    echo "The $svc container is not running. Check: docker compose -p $PROJECT ps" >&2
    exit 2
  fi
done

if [ "$WRITE_SERVER_ENV" = 1 ]; then
  OUT="$STACK_DIR/olive-server.env"
  ( umask 077
    {
      echo "# Olive server call settings, written by calls-on.sh. Contains a secret: do not commit."
      echo "# Copy these lines into scaffold/.env, then restart ONLY the olive server when convenient."
      echo "CALL_PROVIDER=jitsi"
      echo "JITSI_APP_ID=$(envval JWT_APP_ID)"
      echo "JITSI_APP_SECRET=$(envval JWT_APP_SECRET)"
      echo "JITSI_SERVER_URL=$PUBLIC_URL"
      [ -n "$(envval XMPP_DOMAIN)" ] && echo "JITSI_XMPP_DOMAIN=$(envval XMPP_DOMAIN)"
      true
    } > "$OUT" )
  chmod 600 "$OUT" 2>/dev/null || true
  echo "Server settings written to $OUT (mode 600; secret not shown)."
fi

echo ""
echo "Calls are ON."
echo "  LAN URL     : $PUBLIC_URL   (self-signed cert; phones trust the pinned cert in the app)"
echo "  Media (UDP) : $ADV_IP:10000   TURN: $TURN_HOST:3478 (udp+tcp), relay 49160-49200/udp"
echo "  Phones must be on the same Wi-Fi as this PC. Switch off with ./calls-off.sh"
if [ "$JWT_ADDED" = 1 ]; then
  echo "  JWT auth was just added: run ./calls-on.sh --server-env and give the server the lines it writes."
fi
