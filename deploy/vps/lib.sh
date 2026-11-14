# shellcheck shell=bash
# Shared helpers for the Olive VPS kit. Sourced, never executed.
# Overridable for tests: OLIVE_ROOT, OLIVE_PROJECT, HTTP_PORT, HTTPS_PORT,
# CADDY_LOCAL_CERTS, HEALTH_CURL_OPTS.

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$KIT_DIR/../.." && pwd)"
OLIVE_ROOT="${OLIVE_ROOT:-/opt/olive}"
OLIVE_PROJECT="${OLIVE_PROJECT:-olive}"
ENV_FILE="${ENV_FILE:-$OLIVE_ROOT/.env}"
STATE_DIR="$OLIVE_ROOT/state"
BACKUP_DIR="${BACKUP_DIR:-$OLIVE_ROOT/backups}"
RECIPIENT_FILE="$OLIVE_ROOT/backup-recipient.txt"
COMPOSE_FILE="$KIT_DIR/docker-compose.vps.yml"
IMAGE_NAME="olive-server"

log()  { printf '%s %s\n' "$(date -u +%FT%TZ)" "$*"; }
warn() { printf '%s WARN %s\n' "$(date -u +%FT%TZ)" "$*" >&2; }
die()  { printf '%s ERROR %s\n' "$(date -u +%FT%TZ)" "$*" >&2; exit "${2:-1}"; }

env_get() { # env_get KEY  (reads $ENV_FILE, never prints other keys)
  [ -f "$ENV_FILE" ] || return 0
  sed -n "s/^$1=//p" "$ENV_FILE" | tail -1
}

state_get() { if [ -f "$STATE_DIR/$1" ]; then cat "$STATE_DIR/$1"; fi; }
state_set() { mkdir -p "$STATE_DIR"; printf '%s\n' "$2" > "$STATE_DIR/$1"; }

# dc <compose args...>. OLIVE_TAG defaults to the recorded current tag.
dc() {
  OLIVE_TAG="${OLIVE_TAG:-$(state_get current_tag)}"
  OLIVE_TAG="${OLIVE_TAG:-none}"
  export OLIVE_TAG
  if [ -n "${CADDY_LOCAL_CERTS:-}" ]; then export CADDY_LOCAL_CERTS; fi
  docker compose -p "$OLIVE_PROJECT" -f "$COMPOSE_FILE" --env-file "$ENV_FILE" "$@"
}

vol_name() { printf '%s_%s' "$OLIVE_PROJECT" "$1"; }

# Public IPv4 -> sslip.io host name ("1.2.3.4" -> "1-2-3-4.sslip.io").
sslip_host() {
  case "$1" in
    *[!0-9.]*|"") return 1 ;;
  esac
  local IFS=. a b c d x
  read -r a b c d x <<<"$1"
  [ -n "$d" ] && [ -z "$x" ] || return 1
  for x in "$a" "$b" "$c" "$d"; do [ "$x" -le 255 ] 2>/dev/null || return 1; done
  printf '%s-%s-%s-%s.sslip.io' "$a" "$b" "$c" "$d"
}

is_public_ipv4() {
  sslip_host "$1" >/dev/null 2>&1 || return 1
  case "$1" in
    10.*|127.*|0.*|192.168.*|169.254.*|172.1[6-9].*|172.2[0-9].*|172.3[01].*) return 1 ;;
    100.6[4-9].*|100.[7-9][0-9].*|100.1[01][0-9].*|100.12[0-7].*) return 1 ;;
  esac
  return 0
}

# The server's own public IPv4. Hetzner metadata first (no third party), then
# a plain echo service. Oracle/AWS/others have no public-IP metadata field
# usable here, so they fall through to the echo services.
detect_public_ip() {
  local ip url
  ip="$(curl -fsS --max-time 3 http://169.254.169.254/hetzner/v1/metadata/public-ipv4 2>/dev/null | tr -d '[:space:]')" || ip=""
  if is_public_ipv4 "$ip"; then printf '%s' "$ip"; return 0; fi
  for url in https://api.ipify.org https://ifconfig.me/ip; do
    ip="$(curl -4 -fsS --max-time 5 "$url" 2>/dev/null | tr -d '[:space:]')" || ip=""
    if is_public_ipv4 "$ip"; then printf '%s' "$ip"; return 0; fi
  done
  return 1
}

rand_hex() { openssl rand -hex "${1:-32}"; }

set_env_value() { # file key value (hex/host only: no sed-special characters)
  case "$3" in *[!A-Za-z0-9._:/-]*) die "refusing unsafe value for $2" ;; esac
  if grep -q "^$2=" "$1"; then sed -i "s|^$2=.*|$2=$3|" "$1"; else printf '%s=%s\n' "$2" "$3" >> "$1"; fi
}

# gen_env <env-file> <public-host>: create the env file from the template with
# fresh secrets. Idempotent: an existing file is kept; only an explicit
# PUBLIC_HOST is applied. Secrets are never printed.
gen_env() {
  local file="$1" host="${2:-}"
  if [ ! -f "$file" ]; then
    local old; old="$(umask)"; umask 077
    cp "$KIT_DIR/env.example" "$file"; umask "$old"
    chmod 600 "$file"
    set_env_value "$file" POSTGRES_SUPERUSER_PASSWORD "$(rand_hex 24)"
    set_env_value "$file" APP_OWNER_PASSWORD "$(rand_hex 24)"
    set_env_value "$file" BACKUP_READER_PASSWORD "$(rand_hex 24)"
    set_env_value "$file" SESSION_SECRET "$(rand_hex 32)"
    set_env_value "$file" MEDIA_SIGNING_SECRET "$(rand_hex 32)"
  fi
  if [ -n "$host" ]; then set_env_value "$file" PUBLIC_HOST "$host"; fi
  chmod 600 "$file"
}

# wait_healthy <service> <seconds>: 0 when the container reports healthy.
wait_healthy() {
  local svc="$1" limit="$2" t=0 cid st
  while [ "$t" -lt "$limit" ]; do
    cid="$(dc ps -q "$svc" 2>/dev/null | head -1)"
    if [ -n "$cid" ]; then
      st="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$cid" 2>/dev/null || true)"
      [ "$st" = healthy ] && return 0
    fi
    sleep 3; t=$((t+3))
  done
  return 1
}

# End-to-end probe through Caddy and TLS on this host.
probe_public() {
  local host port; host="$(env_get PUBLIC_HOST)"; port="${HTTPS_PORT:-443}"
  # shellcheck disable=SC2086
  curl -fsS --max-time 10 ${HEALTH_CURL_OPTS:-} --resolve "$host:$port:127.0.0.1" "https://$host:$port/healthz" >/dev/null 2>&1
}

# Is the age recipient configured? Backups refuse to run without one.
age_recipient() { if [ -f "$RECIPIENT_FILE" ]; then head -1 "$RECIPIENT_FILE"; fi; }
