-- ============================================================================
--  OLIVE BRANCH — health_check's rls_unforced list: one real, live gap found
--  by this pass's own new automated coverage test
--  (packages/db/test/rls_coverage.test.mjs), not by the next manual audit.
--
--  0026_medications_emergency_card.sql gave THREE tables real
--  `ENABLE`+`FORCE ROW LEVEL SECURITY`: medication, medical_record, and
--  medication_dose. 0028_care_note_letter.sql's own header names the first
--  two ("medication/medical_record (0026) ... were never added to that
--  list") as an already-found, already-fixed gap — but its own fix only
--  actually added `medication` and `medical_record` to the IN-list, missing
--  medication_dose. A fourth instance of the exact same recurring failure
--  mode 0028 itself describes, caught here by the new coverage test
--  (packages/db/test/rls_coverage.test.mjs) deriving the real RLS-enabled
--  table set straight from pg_class rather than trusting the hand-maintained
--  list to be complete — the test failed on its very first real run,
--  against the actual current database, exactly as designed.
--
--  No other drift found: this is the ONLY table the new test's pg_class scan
--  turned up as RLS-enabled-but-untracked. Every other RLS-enabled table
--  already appears in the list as of 0028.
-- ============================================================================

BEGIN;

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
     -- Carried forward from 0028, plus medication_dose (this migration —
     -- see this file's own header for why it was missing).
     AND c.relname IN ('child_journal_entry','pin_credential','expense','message_log',
                        'custody_order','webauthn_credential','auth_challenge',
                        'guardian_availability_window','app_user','device_token',
                        'export_record','guardian_invite','child_theme_preference',
                        'call_log','media_artifact','intent_batch','delivery_intent',
                        'medication','medical_record','medication_dose',
                        'exchange_bag_item',
                        'exchange_running_late_log','exchange_arrival_event',
                        'care_note','letter')
     AND (c.relrowsecurity=false OR c.relforcerowsecurity=false)
  UNION ALL
  SELECT 'log_sequence_gap','critical',count(*),0,
         'Parent log sequences are not contiguous. P8 has been circumvented.'
    FROM (SELECT child_id, seq, lag(seq) OVER (PARTITION BY child_id ORDER BY seq) prev
            FROM message_log) x
   WHERE prev IS NOT NULL AND seq <> prev + 1
) h;

COMMIT;
