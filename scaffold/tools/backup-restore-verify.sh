#!/usr/bin/env bash
# ============================================================================
#  OLIVE BRANCH — backup/restore round-trip proof.
#
#  Does NOT touch any real dev or prod database. Spins up its own throwaway
#  Postgres container, applies every real migration, seeds two real fixtures
#  (db/test/0002_seed.sql's 560-row delivery-engine load, plus this pass's
#  own db/test/0006_backup_fixture.sql covering the message hash-chain,
#  child journal, custody order, export record, and expense ledger — the
#  categories a real custody dispute would actually turn on), takes a real
#  backup, DROPS the database outright (not TRUNCATE — an actual "the volume
#  is gone" simulation), restores from the backup alone, and diffs a
#  per-table content checksum computed before and after. Any mismatch is a
#  real, reported failure, not a note — exit code follows.
#
#  This is the test that backs the claim in scaffold/docs/backup-and-restore.md
#  and in tools/backup-db.sh/restore-db.sh's own headers that the round trip
#  actually works, not just that the two scripts run without error. Rerun it
#  any time either script, any migration, or the RLS grant story
#  (db/migrations/0022_backup_reader_role.sql) changes.
#
#  Requires: Docker. Nothing else — no local psql/pg_dump/pg_restore, no
#  local Postgres. Everything runs inside the container this script starts.
#
#  Usage: bash tools/backup-restore-verify.sh
#  Exit:  0 all checksums matched: 1 a mismatch or step failed.
# ============================================================================
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONTAINER="${CONTAINER:-olive-backup-verify}"
HOST_PORT="${HOST_PORT:-15532}"
DBNAME="olive_devicetest"
WORKDIR="$(mktemp -d 2>/dev/null || echo "$ROOT/.backup-verify-tmp")"
mkdir -p "$WORKDIR"

fail=0
cleanup() {
  docker rm -f "$CONTAINER" >/dev/null 2>&1
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

step() { echo ""; echo "── $1 ──"; }
abort() { echo "ABORT: $1" >&2; exit 2; }

# ------------------------------------------------------------- 1. bring up --
step "starting throwaway Postgres (container: $CONTAINER, port: $HOST_PORT)"
docker rm -f "$CONTAINER" >/dev/null 2>&1
docker run -d --name "$CONTAINER" -e POSTGRES_PASSWORD=postgres \
  -p "127.0.0.1:${HOST_PORT}:5432" postgres:16 >/dev/null \
  || abort "docker run failed — is Docker running?"

ready=0
for _ in $(seq 1 30); do
  if docker exec "$CONTAINER" pg_isready -U postgres >/dev/null 2>&1; then ready=1; break; fi
  sleep 1
done
[ "$ready" = 1 ] || abort "Postgres never became ready"

# --------------------------------------------------- 2. bootstrap + migrate-
step "bootstrapping roles/database (tools/docker-dev/init-db.sql, unmodified)"
docker exec -i "$CONTAINER" psql -U postgres -d postgres -v ON_ERROR_STOP=1 \
  < tools/docker-dev/init-db.sql >/dev/null \
  || abort "init-db.sql failed"

step "applying every migration (tools/migrate.mjs)"
DATABASE_URL="postgres://app_owner:app_owner@127.0.0.1:${HOST_PORT}/${DBNAME}" \
  node tools/migrate.mjs || abort "migration run failed"

# -------------------------------------------------------------- 3. seed ----
step "seeding real fixtures (0002_seed.sql + 0006_backup_fixture.sql)"
docker exec -i "$CONTAINER" psql -U app_owner -d "$DBNAME" -v ON_ERROR_STOP=1 \
  < db/test/0002_seed.sql >/dev/null || abort "0002_seed.sql failed"
docker exec -i "$CONTAINER" psql -U app_owner -d "$DBNAME" -v ON_ERROR_STOP=1 \
  < db/test/0006_backup_fixture.sql >/dev/null || abort "0006_backup_fixture.sql failed"

# --------------------------------------------------------- checksum query --
CHECKSUM_SQL="$WORKDIR/checksums.sql"
cat > "$CHECKSUM_SQL" <<'SQL'
CREATE OR REPLACE FUNCTION pg_temp.olive_table_checksums()
RETURNS TABLE(tablename text, row_count bigint, checksum text) AS $$
DECLARE r record;
BEGIN
  FOR r IN SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
           WHERE n.nspname='public' AND c.relkind='r' AND c.relname <> 'schema_migration'
           ORDER BY c.relname
  LOOP
    RETURN QUERY EXECUTE format(
      'SELECT %L::text, count(*)::bigint, coalesce(md5(string_agg(md5(t.*::text), '','' ORDER BY md5(t.*::text))), ''EMPTY'') FROM %I t',
      r.relname, r.relname);
  END LOOP;
END $$ LANGUAGE plpgsql;
SELECT * FROM pg_temp.olive_table_checksums();
SQL
# Run as the postgres SUPERUSER, deliberately, not app_owner or
# backup_reader — 11 tables carry FORCE ROW LEVEL SECURITY (see
# db/migrations/0022_backup_reader_role.sql's header), so any role without
# BYPASSRLS would silently see (and "verify") an incomplete subset of some
# tables — a checksum that matched for the wrong reason. Superuser here is
# the verification ORACLE, not the credential either script uses to do its
# real job; see this file's own header, and backup-and-restore.md, for why
# backup-db.sh/restore-db.sh use backup_reader/postgres instead.
checksums_of() {
  docker exec -i "$CONTAINER" psql -U postgres -d "$DBNAME" -v ON_ERROR_STOP=1 -t -A -F'|' \
    < "$CHECKSUM_SQL" 2>/dev/null | grep -v '^CREATE FUNCTION$' | grep -v '^$'
}

step "computing per-table checksums BEFORE backup"
checksums_of > "$WORKDIR/before.txt" || abort "checksum query failed"
BEFORE_TABLES=$(wc -l < "$WORKDIR/before.txt" | tr -d ' ')
echo "  $BEFORE_TABLES tables checksummed"

# ------------------------------------------------------------- 4. backup ---
step "running tools/backup-db.sh (as backup_reader — the real operator path)"
DUMP=$(PG_DUMP_CMD="docker exec $CONTAINER pg_dump -U backup_reader" \
       BACKUP_DB="$DBNAME" \
       bash tools/backup-db.sh "$WORKDIR/backups") \
  || abort "backup-db.sh failed"
echo "  dump: $DUMP"

# ------------------------------------------------- 5. simulate total loss --
step "SIMULATING CATASTROPHIC LOSS — dropping the database outright"
docker exec "$CONTAINER" psql -U postgres -c \
  "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='$DBNAME' AND pid <> pg_backend_pid();" \
  >/dev/null 2>&1
docker exec "$CONTAINER" psql -U postgres -c "DROP DATABASE $DBNAME;" >/dev/null \
  || abort "could not drop $DBNAME"
docker exec "$CONTAINER" psql -U postgres -c "CREATE DATABASE $DBNAME OWNER app_owner;" >/dev/null \
  || abort "could not recreate empty $DBNAME"
echo "  database dropped and recreated EMPTY — zero rows, zero tables"

# ------------------------------------------------------------ 6. restore ---
step "running tools/restore-db.sh (as postgres — see file header for why)"
PG_RESTORE_CMD="docker exec -i $CONTAINER pg_restore -U postgres" \
  bash tools/restore-db.sh "$DUMP" "$DBNAME" \
  || abort "restore-db.sh failed"

# ------------------------------------------------------- 7. diff checksums-
step "computing per-table checksums AFTER restore"
checksums_of > "$WORKDIR/after.txt" || abort "post-restore checksum query failed"
AFTER_TABLES=$(wc -l < "$WORKDIR/after.txt" | tr -d ' ')
echo "  $AFTER_TABLES tables checksummed"

echo ""
echo "── diff ──"
if diff -u "$WORKDIR/before.txt" "$WORKDIR/after.txt"; then
  echo "MATCH — every table's row count and content checksum is identical"
  echo "before/after: $BEFORE_TABLES / $AFTER_TABLES tables compared"
else
  echo "MISMATCH — backup/restore did NOT round-trip real data intact" >&2
  fail=1
fi

exit "$fail"
