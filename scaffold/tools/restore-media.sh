#!/usr/bin/env bash
# ============================================================================
#  OLIVE BRANCH — media volume restore. Companion to tools/backup-media.sh;
#  see that file's header for why this exists.
#
#  Extracts a tools/backup-media.sh archive into a target directory — the
#  real deployment target is the `olive-prod-media` volume mounted at
#  MEDIA_STORAGE_ROOT, same pairing tools/restore-db.sh has with a real
#  Postgres database.
#
#  Usage:
#    tools/restore-media.sh <archive> <target-dir>
#
#  Exit codes: 0 success, 1 tar itself failed, 2 misconfiguration.
# ============================================================================
set -u

ARCHIVE="${1:-}"
TARGET="${2:-}"

if [ -z "$ARCHIVE" ] || [ ! -f "$ARCHIVE" ]; then
  echo "usage: tools/restore-media.sh <archive> <target-dir>" >&2
  echo "  (archive must exist on this host — got: '${ARCHIVE:-<none>}')" >&2
  exit 2
fi
if [ -z "$TARGET" ]; then
  echo "usage: tools/restore-media.sh <archive> <target-dir>" >&2
  exit 2
fi

mkdir -p "$TARGET" || { echo "cannot create $TARGET" >&2; exit 2; }

tar -xzf "$ARCHIVE" -C "$TARGET"
rc=$?
if [ "$rc" -ne 0 ]; then
  echo "MEDIA RESTORE FAILED — tar exited $rc" >&2
  exit "$rc"
fi

echo "media restored into: $TARGET" >&2
