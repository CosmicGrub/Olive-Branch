-- OLIVE BRANCH -- create the least-privilege runtime role on an EXISTING database (S-B11).
--
-- A fresh dev volume gets app_runtime from init-db.sql; a volume initialised before the
-- role split has no such role, and Postgres only runs initdb scripts on an empty data
-- directory. Run this ONCE, as the postgres superuser, then re-run the migrator (its
-- grants file does the rest):
--
--   docker compose -f docker-compose.dev.yml exec -T db \
--     psql -U postgres -v runtime_password=app_runtime -f - < tools/docker-dev/create-runtime-role.sql
--   docker compose -f docker-compose.dev.yml run --rm migrate
--
-- Production: pass a real password (the same value as APP_RUNTIME_PASSWORD in .env.prod).
-- Safe to re-run: an existing role only has its attributes and password reset.
SELECT format('CREATE ROLE app_runtime NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE NOINHERIT LOGIN PASSWORD %L', :'runtime_password')
 WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_runtime')
\gexec
SELECT format('ALTER ROLE app_runtime NOSUPERUSER NOBYPASSRLS NOCREATEDB NOCREATEROLE NOINHERIT LOGIN PASSWORD %L', :'runtime_password')
\gexec
