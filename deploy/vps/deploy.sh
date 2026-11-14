#!/usr/bin/env bash
# Deploy or update Olive on this host, health-gated, with automatic rollback.
#
#   deploy.sh                 git pull --ff-only the checkout this kit lives in, build, migrate, restart
#   deploy.sh --ref v0.52.0   pin a tag or commit instead (detached checkout)
#   deploy.sh --no-pull       build and deploy whatever is checked out now
#   deploy.sh --no-backup     skip the automatic pre-migration backup
#
# Order: build the new image (old stack keeps serving) -> start Postgres ->
# backup -> migrate as app_owner (a failed migration aborts here, nothing
# switched) -> recreate server/scheduler/caddy on the new tag -> wait until
# the server is healthy AND answers /healthz through Caddy over TLS. If that
# fails, the previous image is started again and the script exits non-zero.
# Migrations are forward-only: a rollback restarts the old code on the new
# schema; the pre-migration backup is the real undo (see docs/operators/vps-deploy.md).
set -euo pipefail

main() {
  # shellcheck source=lib.sh
  . "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
  local ref="" pull=1 backup=1 health_timeout="${OLIVE_HEALTH_TIMEOUT:-150}"
  while [ $# -gt 0 ]; do
    case "$1" in
      --ref) ref="${2:?--ref needs a tag or commit}"; shift ;;
      --no-pull) pull=0 ;;
      --no-backup) backup=0 ;;
      --health-timeout) health_timeout="${2:?}"; shift ;;
      -h|--help) sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; return 0 ;;
      *) die "unknown option $1" 2 ;;
    esac
    shift
  done

  command -v docker >/dev/null || die "docker not installed; run bootstrap.sh first"
  [ -f "$ENV_FILE" ] || die "$ENV_FILE missing; run bootstrap.sh first"
  [ -n "$(env_get PUBLIC_HOST)" ] || die "PUBLIC_HOST is empty in $ENV_FILE"
  mkdir -p "$STATE_DIR"
  if command -v flock >/dev/null; then
    exec 9>"$STATE_DIR/deploy.lock"
    flock -n 9 || die "another deploy/backup is running"
  fi

  cd "$REPO_DIR"
  if [ "$pull" = 1 ] && git remote get-url origin >/dev/null 2>&1; then
    log "fetching"
    git fetch --tags --prune --quiet origin
    if [ -n "$ref" ]; then
      git checkout --detach --quiet "$ref"
    else
      git symbolic-ref -q HEAD >/dev/null || die "checkout is detached; pass --ref or run: git checkout main"
      git merge --ff-only --quiet '@{upstream}'
    fi
  elif [ -n "$ref" ] && [ "$pull" = 0 ]; then
    git checkout --detach --quiet "$ref"
  fi

  local tag prev dirty=""
  tag="$(git rev-parse --short=12 HEAD)"
  if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
    warn "working tree has local changes; building them as a one-off tag"
    dirty="-dirty$(date +%s)"
  fi
  tag="$tag$dirty"
  prev="$(state_get current_tag)"
  log "deploying $tag (previous: ${prev:-none})"

  if ! docker image inspect "$IMAGE_NAME:$tag" >/dev/null 2>&1; then
    log "building image $IMAGE_NAME:$tag (a few minutes on a small host)"
    OLIVE_TAG="$tag" dc build server
  fi

  export OLIVE_TAG="$tag"
  dc up -d db
  wait_healthy db 120 || die "postgres did not become healthy"

  if [ "$backup" = 1 ] && [ -n "$prev" ] && [ -n "$(age_recipient)" ]; then
    log "pre-deploy backup"
    "$KIT_DIR/backup.sh" --tag pre-deploy || die "pre-deploy backup failed; not deploying (use --no-backup to override)"
  fi

  log "running migrations as app_owner"
  if ! dc run --rm --no-deps migrate; then
    die "migration failed; the running stack was NOT changed"
  fi

  log "switching to $tag"
  dc up -d --remove-orphans || warn "compose reported a problem starting the stack; checking health"

  if wait_healthy server "$health_timeout" && wait_healthy caddy 60 && probe_public; then
    state_set previous_tag "$prev"
    state_set current_tag "$tag"
    state_set deployed_at "$(date -u +%FT%TZ)"
    log "healthy on $tag"
    "$KIT_DIR/prune.sh" --images-only || true
    return 0
  fi

  warn "new version $tag did NOT become healthy"
  state_set last_failed_tag "$tag"
  if [ -n "$prev" ] && docker image inspect "$IMAGE_NAME:$prev" >/dev/null 2>&1; then
    warn "rolling back to $prev"
    export OLIVE_TAG="$prev"
    dc up -d --remove-orphans || true
    if wait_healthy server "$health_timeout" && probe_public; then
      log "rolled back to $prev and healthy"
      return 1
    fi
    die "rollback to $prev also unhealthy; inspect: docker compose logs server (see docs/operators/vps-deploy.md)" 3
  fi
  die "no previous version to roll back to; inspect the logs" 3
}

main "$@"
exit $?
