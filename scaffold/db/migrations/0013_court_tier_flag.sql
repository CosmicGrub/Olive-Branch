-- ============================================================================
--  OLIVE BRANCH — the court tier flag itself
--  MASTERFILE §2.11, §16.1 #3. Closes the gap client/lib/court_export.dart's
--  own header names: a real, checkable "does this guardian have Court tier"
--  boolean did not exist anywhere in this schema, despite 0006_court_tier.sql
--  (the migration that built the hash-chained log a certified export
--  certifies) being named for it.
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------- the flag --
-- Per-GUARDIAN, not per-household or per-child: §16.1 #3's own wording is
-- "one free certified export per GUARDIAN per rolling 12 months," and
-- ledger.ts's authorizeExport()/ExportRequest carries `courtTier` and
-- `certifiedInLast12Months` as properties of the REQUESTER, never of the
-- child or the family unit — a step-parent and a guardian raising the same
-- child do not share one allowance, and a guardian who also parents a
-- second, unrelated child does not get a second allowance from that.
-- app_user is therefore the only correct home for this column; child and
-- household both describe the wrong entity.
--
-- Defaults false. THERE IS NO PAYMENT PROCESSOR ANYWHERE IN THIS CODEBASE
-- (confirmed by grep — same finding this session already hit for Firebase,
-- APNs, and Twilio) and this migration does not invent one. Nothing in this
-- codebase can ever set this column to true except a manual/admin path
-- (direct SQL, or a future real admin tool this build does not build) —
-- there is no checkout flow, no webhook, no "upgrade" button anywhere that
-- flips it, and packages/db/src/pool.ts's certifiedExportBundleFor() only
-- ever READS it. Client copy (court_export.dart) says so plainly rather than
-- rendering a paywall UI that has nothing real behind it.
ALTER TABLE app_user
  ADD COLUMN court_tier boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN app_user.court_tier IS
  'Whether this guardian has purchased/been granted Court tier (§16.1 #3). '
  'No payment processor exists in this codebase — nothing here can set this '
  'true except a manual/admin path (direct SQL today). Read-only from '
  'application code.';

-- --------------------------------------------------- export_record RLS gap --
-- 0006_court_tier.sql created export_record with NO row-level security at
-- all — expense and message_log both got real policies in that same
-- migration, export_record was left out. (Read before trusting the prose
-- that sent this pass here: it claimed export_record already had real RLS.
-- It does not. Fixed here, now that this pass is the first to actually add a
-- read/write path onto this table.)
--
-- Same shape as expense_no_child / log_no_child / custody_order's own "not
-- child" policy (0006, 0007): export_record is guardian/coordinator business,
-- never child-facing — nothing anywhere grants a child role a reason to read
-- it. Cross-guardian isolation (a guardian reading another family's export
-- history) is — consistent with 0007_custody_order.sql's own documented
-- reasoning for message_log/custody_order — an application-layer concern
-- (can() + edgesFor(), the "first lock", §5.17), enforced inside
-- certifiedExportBundleFor() itself before it ever queries this table, not a
-- second per-edge RLS predicate here.
ALTER TABLE export_record ENABLE ROW LEVEL SECURITY;
ALTER TABLE export_record FORCE  ROW LEVEL SECURITY;
CREATE POLICY export_record_no_child ON export_record
  FOR ALL USING (current_role_name() IS DISTINCT FROM 'child');

-- Extend the health view's rls_unforced check (0006) to catch export_record
-- too — it previously checked only child_journal_entry/pin_credential/
-- expense/message_log, silently missing the table this migration just found
-- unprotected.
CREATE OR REPLACE VIEW health_check AS
SELECT * FROM (
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
         'Tables that must enforce RLS but do not FORCE it.'
    FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='public'
     -- The FULL, independently re-verified set of every table in this
     -- schema with FORCE ROW LEVEL SECURITY (grepped across every migration
     -- file, not assumed from 0008's own list) — carried forward in full,
     -- not just appended to, since CREATE OR REPLACE VIEW replaces the whole
     -- definition and a narrower list here would silently drop monitoring
     -- coverage already established elsewhere:
     --   child_journal_entry (0001), pin_credential (0004/0008), expense
     --   (0006), message_log (0006), custody_order (0007), webauthn_credential
     --   (0008), auth_challenge (0008), guardian_availability_window (0010),
     --   app_user (0011), device_token (0012), export_record (0013, this
     --   migration's own addition).
     -- Four real, pre-existing gaps closed here, none this migration's own
     -- doing: device_token (0012), app_user (0011), custody_order (0007),
     -- and guardian_availability_window (0010) all force RLS but were never
     -- added to this check when their own migrations landed — 0008's own
     -- version of this list (the one this migration started from) was
     -- itself incomplete, missing all four. Caught by grepping every real
     -- FORCE ROW LEVEL SECURITY statement in db/migrations/ directly rather
     -- than trusting 0008's list was already exhaustive. Fixed here rather
     -- than left for whoever next touches health_check to rediscover.
     AND c.relname IN ('child_journal_entry','pin_credential','expense','message_log',
                        'custody_order','webauthn_credential','auth_challenge',
                        'guardian_availability_window','app_user','device_token',
                        'export_record')
     AND (c.relrowsecurity=false OR c.relforcerowsecurity=false)
  UNION ALL
  -- A log whose sequence has a gap means an append-only table was mutated.
  SELECT 'log_sequence_gap','critical',count(*),0,
         'Parent log sequences are not contiguous. P8 has been circumvented.'
    FROM (SELECT child_id, seq, lag(seq) OVER (PARTITION BY child_id ORDER BY seq) prev
            FROM message_log) x
   WHERE prev IS NOT NULL AND seq <> prev + 1
) h;

COMMIT;
