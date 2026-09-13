#!/usr/bin/env bash
# ============================================================================
#  OLIVE BRANCH — Postgres backup.
#
#  CHANGELOG v0.49.32's "Not fixed, out of scope for this pass" named a real
#  Postgres backup strategy as a disclosed gap alongside healthcheck
#  directives, a production compose profile, and CI image publishing. This
#  closes that one. Everything this app exists to protect — the message
#  hash-chain (§9.6, the literal court-export chain), the child's private
#  journal (§9.9), custody orders, media, the expense ledger — lives in one
#  Postgres volume. Losing it is not a bug; it is the one failure mode this
#  entire product cannot recover from for a real family. See
#  scaffold/docs/backup-and-restore.md for the operator runbook, and
#  tools/backup-restore-verify.sh for the driver that proves this round-trips
#  real data (seeds real rows across the tables above, backs up, drops the
#  database, restores, and diffs per-table checksums — actually run, not just
#  asserted, before this file was written).
#
#  Produces a single timestamped, compressed dump: `pg_dump -Fc` — Postgres's
#  own "custom" archive format, which is compressed by construction (zlib,
#  same as `pg_dump | gzip` would give you) but ALSO restorable selectively
#  and in parallel (`pg_restore -j`), unlike a plain-SQL + gzip pipe. That is
#  the format Postgres's own docs recommend for anything beyond a trivial
#  toy database, and it is what tools/restore-db.sh expects on the other end.
#
#  Two ways to reach the target database, deliberately mirroring
#  tools/migrate.mjs's own PSQL_CMD-vs-DATABASE_URL split (same reasoning: a
#  bare `pg_dump` binary is not guaranteed to be on the operator's PATH —
#  this project's own dev machine has none — while a running Postgres
#  container always has a version-matched one built in):
#
#    DATABASE_URL   Direct mode. Requires a local `pg_dump` (or $PG_DUMP_BIN)
#                    on PATH. Real production hosts with Postgres client
#                    tools installed use this.
#
#    PG_DUMP_CMD + BACKUP_DB   Container mode. PG_DUMP_CMD is a full command
#                    prefix that runs pg_dump SOMEWHERE ELSE (a Docker
#                    container, typically) and prints the dump to its own
#                    stdout; BACKUP_DB is the database name to pass it. This
#                    is the path that needs nothing installed on the host:
#                      PG_DUMP_CMD="docker exec olive-dev-db-1 pg_dump -U app_owner" \
#                      BACKUP_DB=olive_devicetest \
#                      tools/backup-db.sh
#
#  Usage:
#    tools/backup-db.sh [output_dir]      # output_dir defaults to ./backups
#
#  Exit codes: 0 success, 1 pg_dump itself failed, 2 misconfiguration.
# ============================================================================
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="${1:-$ROOT/backups}"
mkdir -p "$OUT_DIR" || { echo "cannot create $OUT_DIR" >&2; exit 2; }

TS="$(date -u +%Y%m%dT%H%M%SZ)"

run_dump() { # writes the dump to stdout; caller redirects
  if [ -n "${PG_DUMP_CMD:-}" ]; then
    if [ -z "${BACKUP_DB:-}" ]; then
      echo "BACKUP_DB required alongside PG_DUMP_CMD (e.g. BACKUP_DB=olive_devicetest)" >&2
      return 2
    fi
    # shellcheck disable=SC2086 -- PG_DUMP_CMD is an intentionally-split command prefix
    $PG_DUMP_CMD -Fc "$BACKUP_DB"
  else
    if [ -z "${DATABASE_URL:-}" ]; then
      echo "DATABASE_URL or PG_DUMP_CMD+BACKUP_DB required" >&2
      return 2
    fi
    "${PG_DUMP_BIN:-pg_dump}" -Fc "$DATABASE_URL"
  fi
}

DBNAME="${BACKUP_DB:-$(basename "${DATABASE_URL:-unknown}" | sed 's/[?#].*//')}"
OUT="$OUT_DIR/olive_${DBNAME}_${TS}.dump"
TMP="$OUT.partial"

# NOT `if ! run_dump > "$TMP"; then rc=$?; ...` — POSIX defines `!`'s own
# exit status as the logical negation of the command it precedes (0<->1,
# any nonzero collapses to 0), so `$?` immediately inside that `then` branch
# reads `!`'s negated result, never pg_dump's real code: a genuine pg_dump
# failure was silently reported as `rc=0`, i.e. success, both to this
# script's own exit code AND to anything (the nightly scheduler backup job,
# an operator's own alerting) that trusts it. Reproduced live and fixed
# 2026-08-24 (round-5 engineering-systems review) — capture the real,
# un-negated status first, THEN branch on it.
run_dump > "$TMP"
rc=$?
if [ "$rc" -ne 0 ]; then
  rm -f "$TMP"
  echo "BACKUP FAILED — no partial file left behind" >&2
  exit "$rc"
fi

# A zero-byte or truncated dump is worse than no backup at all — it looks
# like success in a directory listing. pg_dump's own exit code already
# covers "the process failed"; this guards the separate case where the
# process exited 0 but produced nothing worth keeping (e.g. piped through a
# `docker exec` that connected but the target database didn't exist).
SIZE=$(wc -c < "$TMP" | tr -d ' ')
if [ "$SIZE" -lt 100 ]; then
  rm -f "$TMP"
  echo "BACKUP FAILED — output was only $SIZE bytes, refusing to keep it as a backup" >&2
  exit 1
fi

mv "$TMP" "$OUT"
# Human-readable confirmation goes to stderr so stdout carries ONLY the bare
# path — lets a caller do DUMP=$(tools/backup-db.sh) and feed the result
# straight to restore-db.sh without scraping a sentence for it.
echo "backup written: $OUT ($SIZE bytes)" >&2
echo "$OUT"
