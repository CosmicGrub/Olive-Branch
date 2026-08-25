-- OLIVE BRANCH — Docker dev-stack Postgres bootstrap.
--
-- app_owner must be NOSUPERUSER NOBYPASSRLS, on purpose: the server (and
-- every RLS policy packages/db/src/pool.ts's queries depend on) only proves
-- anything if the connecting role can't silently bypass row-level security
-- the way a superuser (including the default `postgres` role) always can.
-- This exact gap — a live-test database provisioned under `postgres`
-- instead of a real NOBYPASSRLS role — produced a real bug this session
-- (a grants-gap 500 on a freshly-migrated table) before being caught and
-- fixed by hand; this file exists so a fresh Docker-provisioned database
-- never starts from that same hole.
--
-- Runs automatically on first container start via Postgres's own
-- /docker-entrypoint-initdb.d convention — see docker-compose.dev.yml's
-- volume mount. Only fires against a truly empty data directory; changing
-- this file has no effect on an already-initialized volume (drop the
-- volume to re-run it, same as any other initdb script).
CREATE ROLE app_owner NOSUPERUSER NOBYPASSRLS LOGIN PASSWORD 'app_owner';
CREATE DATABASE olive_devicetest OWNER app_owner;

-- backup_reader: the identity tools/backup-db.sh actually connects as.
-- BYPASSRLS, on purpose and ONLY here — 11 tables in this schema carry
-- FORCE ROW LEVEL SECURITY (message_log, child_journal_entry, app_user,
-- custody_order, expense, export_record, and five more; the authoritative
-- list lives in health_check's own rls_unforced check,
-- 0013_court_tier_flag.sql), which means even app_owner, the table OWNER,
-- cannot read them all: FORCE applies RLS to the owner too unless the owner
-- also holds BYPASSRLS, and app_owner is deliberately NOBYPASSRLS (see this
-- file's own header). `pg_dump -U app_owner` against this exact schema
-- fails outright with "query would be affected by row-level security
-- policy" — proven while building tools/backup-db.sh, not assumed. Creating
-- a SEPARATE role for this rather than granting app_owner itself BYPASSRLS
-- keeps that protection intact for the one connection (the server) that
-- handles untrusted request-shaped input; backup_reader only ever runs
-- pg_dump. It gets no INSERT/UPDATE/DELETE grant anywhere — see
-- db/migrations/0022_backup_reader_role.sql for the SELECT-only grants,
-- which (unlike role creation) app_owner can and does apply itself, as the
-- owner of every table.
CREATE ROLE backup_reader NOSUPERUSER NOCREATEDB NOCREATEROLE BYPASSRLS
  LOGIN PASSWORD 'backup_reader';
