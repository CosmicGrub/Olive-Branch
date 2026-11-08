-- ============================================================================
--  OLIVE BRANCH — emergency card: optimistic concurrency + append-only history
--
--  Audit finding G-11. PUT .../emergency-card (0026's medical_record upsert)
--  was last-write-wins: two guardians editing the same child's card from a
--  stale screen silently overwrote each other, and the one field on the app
--  that can matter in an anaphylaxis emergency (allergies) kept no trace of
--  who changed it or what it used to say.
--
--  1) medical_record.version — integer, starts at 1 on first write, +1 on
--     every write. The route requires the caller to state the version it
--     read (`ifMatch`; 0 means "I saw no card yet"); a mismatch is a 409
--     `stale_version` carrying the current version, never a silent
--     overwrite. Enforced inside one transaction with SELECT ... FOR UPDATE
--     in setMedicalRecord() (packages/db/src/pool.ts).
--
--  2) medical_record_history — APPEND-ONLY. One row per write, holding the
--     values the write REPLACED (prior_values; NULL for the very first
--     write), who made it (changed_by -> app_user, joined for "changed by
--     X" in the UI), and when. Same RLS posture as medical_record (never a
--     child session), but only SELECT and INSERT policies exist — there is
--     deliberately NO update/delete policy, and a trigger refuses UPDATE
--     and refuses a direct DELETE even for the table owner/superuser.
--     (A DELETE reaching the trigger through the child_id ON DELETE CASCADE
--     is allowed — pg_trigger_depth() >= 2 — so deleting a child still
--     erases their history; nothing else can.)
--
--  health_check's rls_unforced list is carried forward in FULL from 0035,
--  plus medical_record_history — packages/db/test/rls_coverage.test.mjs
--  fails outright on a real Postgres if it is missing.
-- ============================================================================

BEGIN;

ALTER TABLE medical_record ADD COLUMN version integer NOT NULL DEFAULT 1;

CREATE TABLE medical_record_history (
  id            bigserial PRIMARY KEY,
  child_id      uuid NOT NULL REFERENCES child(id) ON DELETE CASCADE,
  -- The version this write PRODUCED (medical_record.version after the write).
  version       integer NOT NULL,
  changed_by    uuid NOT NULL REFERENCES app_user(id),
  changed_at    timestamptz NOT NULL DEFAULT now(),
  -- The replaced values, as the wire shape (bloodType, allergies, ...).
  -- NULL for the first write for a child (nothing was replaced).
  prior_values  jsonb,
  UNIQUE (child_id, version)
);
CREATE INDEX medical_record_history_child_idx ON medical_record_history (child_id, version DESC);

ALTER TABLE medical_record_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE medical_record_history FORCE  ROW LEVEL SECURITY;
CREATE POLICY medical_record_history_read ON medical_record_history
  FOR SELECT USING (current_role_name() IS DISTINCT FROM 'child');
CREATE POLICY medical_record_history_insert ON medical_record_history
  FOR INSERT WITH CHECK (current_role_name() IS DISTINCT FROM 'child');

CREATE FUNCTION medical_record_history_append_only() RETURNS trigger AS $$
BEGIN
  IF TG_OP = 'DELETE' AND pg_trigger_depth() >= 2 THEN
    RETURN OLD;  -- child_id ON DELETE CASCADE only
  END IF;
  RAISE EXCEPTION 'medical_record_history is append-only (% refused)', TG_OP
    USING ERRCODE = 'integrity_constraint_violation';
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER medical_record_history_no_change
  BEFORE UPDATE OR DELETE ON medical_record_history
  FOR EACH ROW EXECUTE FUNCTION medical_record_history_append_only();

COMMENT ON TABLE medical_record_history IS
  'Append-only audit trail of emergency-card writes: who, when, and the values replaced. '
  'No update/delete policy; trigger refuses UPDATE and direct DELETE.';

-- ------------------------------------------------- health_check extension --
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
     -- Carried forward from 0035 (Parent Learn), plus medical_record_history
     -- (this migration).
     AND c.relname IN ('child_journal_entry','pin_credential','expense','message_log',
                        'custody_order','webauthn_credential','auth_challenge',
                        'guardian_availability_window','app_user','device_token',
                        'export_record','guardian_invite','child_theme_preference',
                        'call_log','media_artifact','intent_batch','delivery_intent',
                        'medication','medical_record','medication_dose',
                        'exchange_bag_item',
                        'exchange_running_late_log','exchange_arrival_event',
                        'care_note','letter',
                        'guardian_game_favorite','child_game_picker_state',
                        'child_profile','device_pairing_code','paired_device',
                        'guardian_activity_override',
                        'guardian_learn_settings','guardian_reflection',
                        'guardian_house_rule','medical_record_history')
     AND (c.relrowsecurity=false OR c.relforcerowsecurity=false)
  UNION ALL
  SELECT 'log_sequence_gap','critical',count(*),0,
         'Parent log sequences are not contiguous. P8 has been circumvented.'
    FROM (SELECT child_id, seq, lag(seq) OVER (PARTITION BY child_id ORDER BY seq) prev
            FROM message_log) x
   WHERE prev IS NOT NULL AND seq <> prev + 1
) h;

COMMIT;
