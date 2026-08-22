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
