#!/usr/bin/env bash
# ============================================================================
#  OLIVE BRANCH — Postgres restore. Companion to tools/backup-db.sh; see that
#  file's header for why this exists and the two-mode (DATABASE_URL vs
#  PG_DUMP_CMD-style container) split. This one is PG_RESTORE_CMD.
#
#  Restores a `pg_dump -Fc` archive into a TARGET database that must already
#  exist and already be reachable — this script creates dumps' worth of
#  objects, never databases or roles. `--clean --if-exists` means the target
#  does not need to be empty first: existing objects are dropped and
#  recreated, so restoring twice in a row (or restoring on top of a partially
#  broken database) is safe. `--no-owner` + `--role` reassigns everything to
#  one role explicitly rather than trusting the dump's recorded owner to
#  still exist/match on the target — the same app_owner-not-postgres
#  discipline tools/docker-dev/init-db.sql documents for migrations applies
#  here too.
#
#  Usage:
#    tools/restore-db.sh <dump-file> [target]
#
#    Direct mode   (local pg_restore + DATABASE_URL):
#      DATABASE_URL=postgres://app_owner:app_owner@host:5432/olive_devicetest \
#        tools/restore-db.sh backups/olive_olive_devicetest_20260823T000000Z.dump
#
#    Container mode (PG_RESTORE_CMD runs pg_restore INSIDE a container,
#    reading the archive over stdin — <dump-file> is still a path on the
#    HOST, this script pipes it in for you):
#      PG_RESTORE_CMD="docker exec -i olive-dev-db-1 pg_restore -U app_owner" \
#        tools/restore-db.sh backups/olive_....dump olive_devicetest
#
#  Exit codes: 0 success, 1 pg_restore reported errors, 2 misconfiguration.
# ============================================================================
set -u

DUMP="${1:-}"
if [ -z "$DUMP" ] || [ ! -f "$DUMP" ]; then
  echo "usage: tools/restore-db.sh <dump-file> [target-db-name]" >&2
  echo "  (dump-file must exist on this host — got: '${DUMP:-<none>}')" >&2
  exit 2
fi

RESTORE_ROLE="${RESTORE_ROLE:-app_owner}"

if [ -n "${PG_RESTORE_CMD:-}" ]; then
  TARGET="${2:-}"
  if [ -z "$TARGET" ]; then
    echo "target db name required as \$2 alongside PG_RESTORE_CMD" >&2
    exit 2
  fi
  # No filename argument -> pg_restore reads the archive from stdin.
  # shellcheck disable=SC2086
  if ! $PG_RESTORE_CMD --clean --if-exists --no-owner --role="$RESTORE_ROLE" \
       -d "$TARGET" < "$DUMP"; then
    echo "RESTORE FAILED (container mode, target: $TARGET)" >&2
    exit 1
  fi
else
  TARGET_URL="${2:-${DATABASE_URL:-}}"
  if [ -z "$TARGET_URL" ]; then
    echo "target DATABASE_URL required (as \$2 or \$DATABASE_URL) when PG_RESTORE_CMD is unset" >&2
    exit 2
  fi
  if ! "${PG_RESTORE_BIN:-pg_restore}" --clean --if-exists --no-owner \
       --role="$RESTORE_ROLE" -d "$TARGET_URL" "$DUMP"; then
    echo "RESTORE FAILED (direct mode)" >&2
    exit 1
  fi
fi

echo "restore complete from $DUMP" >&2
