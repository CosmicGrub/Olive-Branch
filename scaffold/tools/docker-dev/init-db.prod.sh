#!/usr/bin/env bash
# ============================================================================
#  OLIVE BRANCH — production Postgres bootstrap.
#
#  Same two roles + database as tools/docker-dev/init-db.sql (that file's own
#  header explains WHY app_owner is NOSUPERUSER NOBYPASSRLS, and
#  db/migrations/0022_backup_reader_role.sql explains WHY backup_reader
#  exists and is BYPASSRLS). The DEV file hardcodes both passwords —
#  'app_owner' / 'backup_reader' — because it never runs anywhere but a
#  throwaway local Postgres volume nobody depends on. That is not an
#  acceptable password for anything docker-compose.prod.yml starts, so THIS
#  file exists as a separate entrypoint that reads real secrets from the
#  environment instead — a .sql file has no way to do that (Postgres's own
#  /docker-entrypoint-initdb.d convention runs .sh scripts with the
#  container's environment already in scope, which is exactly what this
#  needs), which is the whole reason this isn't just init-db.sql with two
#  lines changed.
#
#  Fails closed, matching docker-compose.dev.yml's own
#  SESSION_SECRET:?-required pattern: an unset password is a startup abort,
#  never a silent fallback to something guessable.
#
#  psql's `\set x 'value'` + `:'x'` quoting is used for both passwords
#  rather than string-interpolating them into the SQL text directly — psql
#  quotes the value as a proper SQL literal (escaping embedded quotes
#  correctly), which plain shell interpolation would not do safely.
# ============================================================================
set -euo pipefail

: "${APP_OWNER_PASSWORD:?APP_OWNER_PASSWORD must be set — see scaffold/.env.prod.example}"
: "${BACKUP_READER_PASSWORD:?BACKUP_READER_PASSWORD must be set — see scaffold/.env.prod.example}"
: "${POSTGRES_DB_NAME:=olive_prod}"

psql -v ON_ERROR_STOP=1 --username postgres --dbname postgres \
  --set app_owner_password="$APP_OWNER_PASSWORD" \
  --set backup_reader_password="$BACKUP_READER_PASSWORD" \
  --set db_name="$POSTGRES_DB_NAME" <<'SQL'
CREATE ROLE app_owner NOSUPERUSER NOBYPASSRLS LOGIN PASSWORD :'app_owner_password';
CREATE DATABASE :"db_name" OWNER app_owner;
CREATE ROLE backup_reader NOSUPERUSER NOCREATEDB NOCREATEROLE BYPASSRLS
  LOGIN PASSWORD :'backup_reader_password';
SQL

echo "init-db.prod.sh: app_owner, backup_reader, and ${POSTGRES_DB_NAME} created"
