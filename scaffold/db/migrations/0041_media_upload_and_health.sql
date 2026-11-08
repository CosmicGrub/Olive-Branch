-- ============================================================================
--  OLIVE BRANCH — media_upload ledger (audit S-B8, S-B9)
--
--  POST .../media used to write a blob before any media_artifact row existed
--  and remember nothing about it. That left three holes: (S-B9) POST
--  .../messages accepted any storageKey, so a message could point at another
--  child's blob; (S-B8) a blob that never got a message lived forever (an
--  unreferenced photo of a child is a retention exposure), and nothing capped
--  how much one child could upload.
--
--  media_upload is the server's own record of every blob it accepted: who put
--  it, for which child, how big, and what it really is (MIME sniffed from the
--  magic bytes, not trusted from the client). It is what a message's storageKey
--  is validated against (same child, same uploader, exists), what the per-child
--  byte quota sums, and what the orphan sweeper (tools/scheduler.mjs) walks.
--
--  Written and read by `system` only: the route records the row through a
--  pool.ts accessor after it has already authorized the caller via can().
--  health_check's rls_unforced list is extended here for every table this audit
--  round adds or newly protects.
-- ============================================================================

BEGIN;

CREATE TABLE media_upload (
  storage_key       text PRIMARY KEY,
  child_id          uuid NOT NULL REFERENCES child(id) ON DELETE CASCADE,
  uploader_user_id  uuid REFERENCES app_user(id) ON DELETE SET NULL,
  uploader_role     text NOT NULL,
  mime              text NOT NULL,
  byte_size         bigint NOT NULL CHECK (byte_size > 0),
  created_at        timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX media_upload_child_idx ON media_upload (child_id, created_at);
CREATE INDEX media_upload_created_idx ON media_upload (created_at);

ALTER TABLE media_upload ENABLE ROW LEVEL SECURITY;
ALTER TABLE media_upload FORCE  ROW LEVEL SECURITY;
CREATE POLICY media_upload_system_all ON media_upload
  FOR ALL USING (current_role_name() = 'system')
  WITH CHECK (current_role_name() = 'system');

COMMENT ON TABLE media_upload IS
  'Ledger of every blob the upload route accepted (key, child, uploader, sniffed MIME, size). '
  'Validates a message storageKey, backs the per-child byte quota, and feeds the orphan sweeper.';

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
     -- Carried forward from 0036, plus the tables this audit round adds
     -- (security_event, media_upload) or newly protects (child, guardianship).
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
                        'guardian_house_rule','medical_record_history',
                        'security_event','media_upload','child','guardianship')
     AND (c.relrowsecurity=false OR c.relforcerowsecurity=false)
  UNION ALL
  SELECT 'log_sequence_gap','critical',count(*),0,
         'Parent log sequences are not contiguous. P8 has been circumvented.'
    FROM (SELECT child_id, seq, lag(seq) OVER (PARTITION BY child_id ORDER BY seq) prev
            FROM message_log) x
   WHERE prev IS NOT NULL AND seq <> prev + 1
) h;

COMMIT;
