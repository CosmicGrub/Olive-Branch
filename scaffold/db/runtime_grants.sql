-- ============================================================================
--  OLIVE BRANCH — the least-privilege RUNTIME role's grants (S-B11).
--
--  Applied by tools/migrate.mjs at the end of EVERY run (idempotent; see that
--  file). Not a numbered migration on purpose: schema_migration is created by
--  the runner, and a role created after the schema must pick the grants up
--  without a new migration.
--
--  app_runtime is what the RUNNING server, the scheduler and the health tools
--  connect as. It owns nothing, holds no DDL right, and is bound by every row
--  security policy (including on tables that are not FORCE-ed, which the owner
--  would bypass). app_owner stays the migrator and the table owner. The role is
--  created outside SQL migrations because CREATE ROLE needs CREATEROLE or
--  superuser (tools/docker-dev/init-db.sql, init-db.prod.sh, create-runtime-
--  role.sql, tools/verify.sh). Without it this file only prints a NOTICE.
--
--  What this removes: ALTER/DROP/CREATE of any object, DISABLE ROW LEVEL
--  SECURITY, DROP POLICY, dropping a trigger that makes a table append-only,
--  rewriting the migration ledger. What it does not: forging the three
--  transaction-local identity settings (app.role / app.user_id / app.child_id)
--  by an attacker who can already run arbitrary SQL as this role.
-- ============================================================================
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_runtime') THEN
    RAISE NOTICE 'runtime_grants: role app_runtime does not exist; the server may still connect as app_owner (not recommended). See tools/docker-dev/create-runtime-role.sql.';
    RETURN;
  END IF;
  GRANT USAGE ON SCHEMA public TO app_runtime;
  GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app_runtime;
  GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO app_runtime;
  GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO app_runtime;
  -- the migration ledger belongs to the owner: a runtime role must not be able to
  -- rewrite which migrations (and which checksums) the database believes it has
  REVOKE ALL ON schema_migration FROM app_runtime;
  -- tables and sequences a later migration creates get the same grants
  ALTER DEFAULT PRIVILEGES FOR ROLE app_owner IN SCHEMA public
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app_runtime;
  ALTER DEFAULT PRIVILEGES FOR ROLE app_owner IN SCHEMA public
    GRANT USAGE, SELECT ON SEQUENCES TO app_runtime;
END
$$;
