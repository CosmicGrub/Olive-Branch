#!/usr/bin/env bash
# ============================================================================
#  OLIVE BRANCH — media volume backup.
#
#  Real bug, found by this project's own post-tier audit: docker-compose.
#  prod.yml's `backup` service ran tools/backup-db.sh (Postgres only) and
#  nothing else, while scaffold/docs/backup-and-restore.md and
#  db/DEPLOYMENT.md's own pre-production checklist BOTH claimed "backups
#  exclude nothing — preserved artifacts are irreplaceable." Both statements
#  were false: media_artifact.storage_key (db/migrations/0001_phase0_init.sql)
#  is a `text` column, a POINTER, not the bytes — the actual video/voice/
#  photo content lives only on the `olive-prod-media` filesystem volume
#  (packages/storage/src/storage.ts's FilesystemStorage), which nothing in
#  the backup path ever touched. A database restored from the documented
#  process would contain fully intact media_artifact rows — including every
#  explicitly `preserved=true` artifact a guardian chose to keep forever —
#  with storage_keys pointing at files that no longer exist anywhere.
#
#  This closes that gap the simple way a plain filesystem volume actually
#  needs: unlike Postgres, no special client binary or connection protocol
#  is required to read it, so the `backup` Compose service mounts the real
#  volume read-only and this script just tars it — no two-mode DATABASE_URL-
#  vs-PG_DUMP_CMD split like backup-db.sh needs, because there is no
#  equivalent "no local pg_dump on PATH" problem for a bind-mounted
#  directory.
#
#  Usage:
#    tools/backup-media.sh <media-root> [output_dir]   # output_dir defaults to ./backups
#
#  Exit codes: 0 success, 1 tar itself failed, 2 misconfiguration.
# ============================================================================
set -u

MEDIA_ROOT="${1:-}"
OUT_DIR="${2:-./backups}"

if [ -z "$MEDIA_ROOT" ] || [ ! -d "$MEDIA_ROOT" ]; then
  echo "usage: tools/backup-media.sh <media-root> [output_dir]" >&2
  echo "  (media-root must be a real, mounted directory — got: '${MEDIA_ROOT:-<none>}')" >&2
  exit 2
fi

mkdir -p "$OUT_DIR" || { echo "cannot create $OUT_DIR" >&2; exit 2; }

TS="$(date -u +%Y%m%dT%H%M%SZ)"
OUT="$OUT_DIR/olive_media_${TS}.tar.gz"
TMP="$OUT.partial"

# An EMPTY media root (a brand-new deployment with no uploads yet) is a real,
# legitimate state — tar it successfully, matching backup-db.sh's own
# size-sanity-check SPIRIT but not its exact threshold: zero bytes of real
# media is honest here in a way a zero-byte pg_dump never is.
tar -czf "$TMP" -C "$MEDIA_ROOT" .
rc=$?
if [ "$rc" -ne 0 ]; then
  rm -f "$TMP"
  echo "MEDIA BACKUP FAILED — tar exited $rc, no partial file left behind" >&2
  exit "$rc"
fi

mv "$TMP" "$OUT"
SIZE=$(wc -c < "$OUT" | tr -d ' ')
# Human-readable confirmation to stderr, bare path on stdout — same
# DUMP=$(tools/backup-db.sh) composability backup-db.sh's own header
# documents, so a caller can do
#   MEDIA_ARCHIVE=$(tools/backup-media.sh "$MEDIA_ROOT")
# and feed the result straight to restore-media.sh.
echo "media backup written: $OUT ($SIZE bytes)" >&2
echo "$OUT"
