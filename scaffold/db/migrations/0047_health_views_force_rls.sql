-- ============================================================================
--  OLIVE BRANCH — 0047: health_check reads TRUE counts under FORCE RLS, without
--  exposing a single row.
--
--  THE BUG (a monitoring blind spot).
--  health_check (and orphan_risk, retention_breach under it) read four tables
--  that carry FORCE ROW LEVEL SECURITY: delivery_intent, media_artifact (0023),
--  guardianship, message_log (0040, 0006). A view runs with its OWNER's
--  privileges, and in production the owner is app_owner, the unprivileged
--  migrator that also owns every table. FORCE applies RLS to a table's owner,
--  so inside the view every one of those reads was filtered by the policies,
--  which only admit a session that has declared itself `system` (or an adult
--  with an edge to ONE child). The counters therefore depended on who was
--  asking and on a GUC the caller had to remember to raise:
--
--    orphan_risk, stalled_delivery, unmaterialized, closure_without_reason,
--    log_sequence_gap, retention_invariant_broken   read 0 for any session
--                                                    that was not app.role=
--                                                    'system' -- including a
--                                                    dedicated monitoring
--                                                    login, the operator
--                                                    console, and a bare
--                                                    `SELECT ... FROM
--                                                    health_check`
--    retention_breach, rls_unforced                 correct for everyone (they
--                                                    read reap_tombstone and
--                                                    pg_class, neither of
--                                                    which has RLS)
--
--  Wrong zeros are the worst failure a monitor can have: nothing alerts. CI
--  never saw it because tools/verify.sh migrates as the `postgres` superuser,
--  which makes `postgres` the view owner, and a superuser bypasses RLS even
--  when forced; the same suites passed there and failed on an app_owner-
--  migrated database (tools/test/migrate_nonsuper.test.mjs is the production
--  shape). tools/health-alert.mjs and tools/healthcheck.mjs only worked
--  because each hand-raised app.role='system', which hands the monitor a
--  blanket read of every family's rows just to count them.
--
--  THE FIX.
--  health_check is now `SELECT * FROM health_counts()`, where health_counts()
--  is an aggregate-only SECURITY DEFINER function owned by app_owner, and each
--  of the four tables gets one narrow SELECT policy that opens ONLY while the
--  transaction-local flag app.health_probe is 'on'. The function raises the
--  flag itself, runs the counting query to completion, and puts the flag back
--  exactly as it found it (the same pattern as actor_child_ids(), 0040).
--
--  Why this shape, and what was rejected:
--   * Policies `TO <monitor role> USING (true)` plus a security_invoker view
--     would work, but then the monitor needs SELECT on the base tables, and a
--     role that can SELECT delivery_intent can read its rows: not aggregate-
--     only. Here the monitoring login holds SELECT on health_check plus EXECUTE on
--     health_counts() (the same aggregate rows) and nothing else; it cannot read one row of anything.
--   * SECURITY DEFINER alone does not help: FORCE RLS applies to the definer
--     too when the definer owns the table (the same reason 0040 gave for
--     rejecting it). The flag + policy is what makes the definer's reads pass.
--   * A function-level `SET app.health_probe = 'on'` is refused to an
--     unprivileged migrator on PG15+ (custom GUC in proconfig needs superuser
--     or SET ON PARAMETER): the body calls set_config() instead, which needs no
--     privilege (migrate_nonsuper.test.mjs checks no function stores one).
--   * BYPASSRLS on a monitor role (the backup_reader route, 0022) was rejected:
--     it would read every row, and creating it needs a superuser.
--
--  What the flag does and does not protect (be honest): it is a plain GUC, so
--  any session running as app_owner can set it, exactly as it can already set
--  app.role = 'system'. Like 0040's edge_lookup, the layer contains a
--  forgotten WHERE, not SQL injection (S-B11's DML-only runtime role is the
--  answer to that). What it DOES give is: (1) the counts are true for every
--  caller, independent of app.role; (2) the monitoring login is structurally
--  unable to read rows (no table grant; the flag is useless without one);
--  (3) a family-scoped session that merely SELECTs health_check learns global
--  counts (numbers, no ids, no text), never rows, and the flag is back to its
--  prior value when the function returns.
--
--  orphan_risk and retention_breach stay row-level views (they list intent and
--  artifact ids for an operator); they are system-only, as before, and are NOT
--  granted to the monitor role.
--
--  THE MONITOR ROLE. `health_monitor` is a cluster role and, like backup_reader
--  (0022), cannot be created here: app_owner has no CREATEROLE, and that is
--  deliberate. tools/docker-dev/init-db.sql and init-db.prod.sh create it
--  (NOSUPERUSER NOBYPASSRLS, no table grants). This migration only GRANTs to it
--  when it already exists; an operator who adds the role later runs
--      GRANT USAGE ON SCHEMA public TO health_monitor;
--      GRANT SELECT ON health_check TO health_monitor;
--      GRANT EXECUTE ON FUNCTION health_counts() TO health_monitor;
--  once (docs: scaffold/db/DEPLOYMENT.md). health-alert.mjs connects with
--  HEALTH_DATABASE_URL (the monitor login) when set.
--
--  rls_coverage / rls_allow_list (0044): unchanged and still correct. No table
--  is added; the four tables stay ENABLE + FORCE and gain one more permissive
--  SELECT policy each, so nothing leaves the catalog-driven rls_unforced check.
--  0040's edge policies are untouched.
-- ============================================================================

BEGIN;

-- ---- the probe-flag policies: one per table the health checks read ---------
CREATE POLICY delivery_intent_health_probe ON delivery_intent
  FOR SELECT USING (current_setting('app.health_probe', true) = 'on');
CREATE POLICY media_artifact_health_probe ON media_artifact
  FOR SELECT USING (current_setting('app.health_probe', true) = 'on');
CREATE POLICY guardianship_health_probe ON guardianship
  FOR SELECT USING (current_setting('app.health_probe', true) = 'on');
CREATE POLICY message_log_health_probe ON message_log
  FOR SELECT USING (current_setting('app.health_probe', true) = 'on');

-- ---- the aggregate-only reader ---------------------------------------------
-- Same checks, same order and same text as 0044's view (observed/threshold
-- unchanged), now evaluated inside the one place that raises the flag.
-- search_path is pinned (a SECURITY DEFINER function must not resolve names
-- through the caller's path); pg_temp last so a caller cannot shadow a table.
CREATE FUNCTION health_counts()
RETURNS TABLE (check_name text, severity text, observed bigint, threshold bigint, meaning text)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, pg_catalog, pg_temp
AS $$
DECLARE
  v_prev text := coalesce(current_setting('app.health_probe', true), '');
BEGIN
  PERFORM set_config('app.health_probe', 'on', true);
  RETURN QUERY
  SELECT h.check_name, h.severity, h.observed, h.threshold, h.meaning FROM (
    SELECT 'retention_breach'::text AS check_name, 'critical'::text AS severity,
           count(*)::bigint AS observed, 0::bigint AS threshold,
           'Media past its retention window still exists in storage.'::text AS meaning
      FROM retention_breach
    UNION ALL
    SELECT 'orphan_risk','high',count(*),0,
           'A queued message points at media that expires before delivery.' FROM orphan_risk
    UNION ALL
    SELECT 'stalled_delivery','high',count(*),0,'The sweep is not running.'
      FROM delivery_intent WHERE state='ready' AND scheduled_at < now() - interval '1 hour'
    UNION ALL
    SELECT 'unmaterialized','high',count(*),0,'Rematerialization is not running.'
      FROM delivery_intent WHERE state='pending' AND scheduled_at IS NULL
        AND created_at < now() - interval '1 hour'
    UNION ALL
    SELECT 'retention_invariant_broken','critical',count(*),0,
           'Artifacts with no clock and no preservation. The §5.6 CHECK is gone.'
      FROM media_artifact WHERE preserved=false AND expires_at IS NULL
    UNION ALL
    SELECT 'closure_without_reason','high',count(*),0,
           'Guardianship edges closed with no recorded reason.'
      FROM guardianship WHERE closed_at IS NOT NULL AND closed_reason IS NULL
    UNION ALL
    SELECT 'rls_unforced','critical',count(*),0,
           'Public tables that do not ENABLE and FORCE row-level security and are not on rls_allow_list.'
      FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
     WHERE n.nspname='public' AND c.relkind IN ('r','p')
       AND (c.relrowsecurity=false OR c.relforcerowsecurity=false)
       AND NOT EXISTS (SELECT 1 FROM rls_allow_list a WHERE a.table_name = c.relname)
    UNION ALL
    SELECT 'log_sequence_gap','critical',count(*),0,
           'Parent log sequences are not contiguous. P8 has been circumvented.'
      FROM (SELECT m.child_id, m.seq, lag(m.seq) OVER (PARTITION BY m.child_id ORDER BY m.seq) prev
              FROM message_log m) x
     WHERE prev IS NOT NULL AND seq <> prev + 1
  ) h;
  PERFORM set_config('app.health_probe', v_prev, true);
  RETURN;
END;
$$;

COMMENT ON FUNCTION health_counts() IS
  'Aggregate-only monitoring read (0047): raises app.health_probe for the duration of one counting '
  'query so the FORCE-RLS tables answer, returns counts and static text, never a row of family data.';

-- Not PUBLIC: EXECUTE is granted to the monitoring login below. (A function
-- named inside a view is permission-checked against the CALLER, not the view
-- owner, so the monitor needs EXECUTE as well as SELECT on the view. Calling it
-- directly returns exactly the view's rows: counts and static text.)
REVOKE ALL ON FUNCTION health_counts() FROM PUBLIC;

CREATE OR REPLACE VIEW health_check AS
  SELECT check_name, severity, observed, threshold, meaning FROM health_counts();

COMMENT ON VIEW health_check IS
  'Operational counters. Reads through health_counts() (0047), so the numbers are true for every '
  'caller under FORCE RLS; grant SELECT on this view (only) to a monitoring login.';

-- ---- the monitoring login's one grant --------------------------------------
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'health_monitor') THEN
    GRANT USAGE ON SCHEMA public TO health_monitor;
    GRANT SELECT ON health_check TO health_monitor;
    GRANT EXECUTE ON FUNCTION health_counts() TO health_monitor;
  END IF;
END $$;

COMMIT;
