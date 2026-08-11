-- ============================================================================
--  OLIVE BRANCH — health_check: recording it as the canonical alerting source
--  MASTERFILE §20.2b: "orphan_risk and retention_breach are also still views
--  with no alerting."
--
--  AUDIT FINDING, not a redefinition. Before writing this file the task was
--  to find "the real, current shape of that aggregation in
--  db/migrations/0008_auth_credentials.sql (the latest one)" and, if it were
--  an inline query repeated per migration, consolidate it into one
--  CREATE OR REPLACE VIEW. Neither premise holds in this repository:
--
--    - There is no 0008_auth_credentials.sql here. 0004_auth_and_reaper.sql
--      is the actual auth/credentials migration; 0007_custody_order.sql is
--      the latest migration on this branch, and it does not touch
--      health_check at all.
--    - health_check is NOT duplicated as an inline query per migration.
--      0005_observability.sql and 0006_court_tier.sql each issue a real
--      `CREATE OR REPLACE VIEW health_check AS ...` — the exact same
--      technique this repository already uses to evolve `orphan_risk` and
--      `retention_breach` themselves. 0006's definition is already the
--      single, currently-live, canonical source; there is no second view
--      name and no copy that could drift from it.
--
--  So there is nothing to consolidate. What this migration adds instead is
--  documentation IN THE CATALOG rather than in a comment nobody reads at
--  query time — a `\d+ health_check` or an information_schema lookup now
--  says, in the database itself, that this is the one view
--  tools/healthcheck.mjs and tools/health-alert.mjs both read, so the next
--  person adding a ninth check finds one view to extend, not a choice
--  between two. No table, column, or existing view DEFINITION changes here.
-- ============================================================================

BEGIN;

COMMENT ON VIEW health_check IS
  'Canonical health-check aggregation (MASTERFILE section 20.2b). One row per '
  'check: check_name, severity, observed, threshold, meaning. observed > '
  'threshold is a breach. Read by tools/healthcheck.mjs (human table on '
  'stdout, psql-binary based) and tools/health-alert.mjs (structured stderr '
  'alert lines, pg-driver based, meant for cron/monitoring -- neither sends '
  'an email/Slack/pager alert; see that script''s own header). Defined via '
  'CREATE OR REPLACE VIEW across 0005_observability.sql and '
  '0006_court_tier.sql -- 0006''s definition is the one currently live. Add a '
  'new check there (or in a later migration that replaces it again); do not '
  'create a second view.';

COMMENT ON VIEW orphan_risk IS
  'A queued delivery_intent (state pending/ready) whose payload_ref '
  'media_artifact expires before the intent does -- the child would watch it '
  'arrive and play nothing. Feeds the orphan_risk row of health_check. '
  'Defined in 0005_observability.sql.';

COMMENT ON VIEW retention_breach IS
  'A reap_tombstone (a blob whose delete failed) still unresolved a day '
  'later: a live COPPA retention exposure. Feeds the retention_breach row of '
  'health_check. Defined in 0004_auth_and_reaper.sql.';

COMMIT;
