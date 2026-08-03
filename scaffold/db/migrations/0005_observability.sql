-- ============================================================================
--  OLIVE BRANCH — observability
--  §20.2b: "orphan_risk and retention_breach are views with no alerting."
--  A view nobody queries is a comment. These become checks with severities.
-- ============================================================================

BEGIN;

-- Any pending intent whose artifact expires before it does. Introduced in
-- v0.9.0 but defined inside a TEST file, so it existed only where that test had
-- been run — a production view that was never deployed. Moved here.
CREATE OR REPLACE VIEW orphan_risk AS
SELECT d.id AS intent_id, d.payload_ref, d.expires_at AS intent_expiry,
       m.expires_at AS artifact_expiry
  FROM delivery_intent d
  JOIN media_artifact m ON m.id = d.payload_ref
 WHERE d.state IN ('pending','ready')
   AND m.preserved = false
   AND m.expires_at IS NOT NULL
   AND m.expires_at <= d.expires_at;

CREATE OR REPLACE VIEW health_check AS
-- COPPA retention breach: a blob whose delete failed and has stayed failed.
SELECT 'retention_breach'::text AS check_name,
       'critical'::text        AS severity,
       count(*)::bigint        AS observed,
       0::bigint               AS threshold,
       'Media past its retention window still exists in storage. Each is a '
       'live COPPA exposure.'::text AS meaning
  FROM retention_breach
UNION ALL
-- An intent whose artifact will be reaped before it is delivered.
SELECT 'orphan_risk', 'high', count(*), 0,
       'A queued message points at media that expires before delivery. The '
       'child would watch it arrive and play nothing.'
  FROM orphan_risk
UNION ALL
-- Intents materialized long ago and never swept: the sweep has stopped.
SELECT 'stalled_delivery', 'high', count(*), 0,
       'Ready intents whose scheduled time passed over an hour ago. The sweep '
       'is not running.'
  FROM delivery_intent
 WHERE state = 'ready' AND scheduled_at < now() - interval '1 hour'
UNION ALL
-- Pending intents that never materialized: the materializer has stopped.
SELECT 'unmaterialized', 'high', count(*), 0,
       'Pending intents with no scheduled_at for over an hour. Rematerialization '
       'is not running.'
  FROM delivery_intent
 WHERE state = 'pending' AND scheduled_at IS NULL
   AND created_at < now() - interval '1 hour'
UNION ALL
-- Artifacts with neither clock nor preservation should be unrepresentable.
SELECT 'retention_invariant_broken', 'critical', count(*), 0,
       'Artifacts with no retention clock and no preservation. The §5.6 CHECK '
       'has been dropped or bypassed.'
  FROM media_artifact
 WHERE preserved = false AND expires_at IS NULL
UNION ALL
-- A guardianship closed without a reason should be impossible.
SELECT 'closure_without_reason', 'high', count(*), 0,
       'Guardianship edges closed with no recorded reason.'
  FROM guardianship
 WHERE closed_at IS NOT NULL AND closed_reason IS NULL
UNION ALL
-- RLS disabled or unforced on a protected table is a silent P6/P7 breach.
SELECT 'rls_unforced', 'critical', count(*), 0,
       'Tables that must enforce RLS but do not FORCE it. The table owner can '
       'read them, which is how most applications connect.'
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'public'
   AND c.relname IN ('child_journal_entry','pin_credential')
   AND (c.relrowsecurity = false OR c.relforcerowsecurity = false);

COMMIT;
