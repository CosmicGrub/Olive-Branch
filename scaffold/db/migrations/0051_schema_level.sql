-- ============================================================================
--  OLIVE BRANCH — readiness: which migration is this database at?
--
--  GET /readyz must answer "is the schema this image expects actually here?",
--  and until now the server could not ask. Runtime-role separation (S-B11,
--  db/runtime_grants.sql) deliberately REVOKEs every privilege on
--  schema_migration from app_runtime, so `SELECT max(filename) FROM
--  schema_migration` is "permission denied" for the only role the server runs
--  as. An old image against a newer database (or the reverse) therefore served
--  /healthz 200 and failed later, in a route, for a person.
--
--  This is the narrowest possible answer: a function that returns the single
--  newest applied filename and nothing else (no checksums, no timestamps, no
--  row list). SECURITY DEFINER so it runs as the migration owner, which can
--  read the table; the search_path is pinned so a caller cannot shadow
--  schema_migration with an object of their own. EXECUTE is granted to
--  app_runtime when that role exists; it is not granted to PUBLIC.
--
--  schema_migration has no RLS (it holds no family data), so unlike the 0040
--  helpers a definer-owned function is not filtered out by FORCE RLS here.
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION schema_migration_level() RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, pg_temp
AS $$ SELECT max(filename) FROM schema_migration $$;

REVOKE ALL ON FUNCTION schema_migration_level() FROM PUBLIC;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_runtime') THEN
    GRANT EXECUTE ON FUNCTION schema_migration_level() TO app_runtime;
  END IF;
END
$$;

COMMENT ON FUNCTION schema_migration_level() IS
  'Newest applied migration filename. For the server''s /readyz only: '
  'app_runtime cannot read schema_migration itself (db/runtime_grants.sql).';

COMMIT;
