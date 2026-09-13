-- ============================================================================
--  OLIVE BRANCH — device pairing & provisioning
--
--  docs/superpowers/specs/2026-09-12-device-pairing-provisioning-design.md.
--  Replaces the build-time `--dart-define=OLIVE_CHILD_ID=...`/
--  `OLIVE_GUARDIAN_ID=...` provisioning step with a real in-app pairing flow,
--  for a family that already exists (child + guardian rows already created
--  by whatever means — today's manual seed-dev.mjs, unchanged by this spec).
--  Does NOT create families, children, or guardians — see the design spec's
--  own "Explicitly out of scope" section.
--
--  Two new tables, real RLS on both.
-- ============================================================================

BEGIN;

CREATE TABLE device_pairing_code (
  id              uuid PRIMARY KEY DEFAULT uuid_generate_v4(),  -- the QR payload; unguessable, sufficient alone
  numeric_code    text NOT NULL,        -- 6 digits, human-typeable fallback; NOT sufficient alone (see the lockout in redeemDevicePairingCode())
  role            text NOT NULL CHECK (role IN ('child','guardian')),
  target_id       uuid NOT NULL,        -- child.id or app_user.id this code will bind a new device to
  created_by      uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  created_at      timestamptz NOT NULL DEFAULT now(),
  expires_at      timestamptz NOT NULL DEFAULT (now() + interval '10 minutes'),
  redeemed_at     timestamptz,          -- single-use
  revoked_at      timestamptz,          -- guardian can cancel before use
  failed_attempts int NOT NULL DEFAULT 0,
  CONSTRAINT pairing_code_not_both_redeemed_and_revoked
    CHECK (NOT (redeemed_at IS NOT NULL AND revoked_at IS NOT NULL))
);
CREATE INDEX device_pairing_code_target_idx ON device_pairing_code (target_id);

CREATE TABLE paired_device (
  id            uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  role          text NOT NULL CHECK (role IN ('child','guardian')),
  target_id     uuid NOT NULL,          -- child.id or app_user.id this device's sessions are bound to
  label         text NOT NULL,          -- e.g. "Paired Sep 12, 2026" — no device-fingerprinting attempted
  paired_via    uuid NOT NULL REFERENCES device_pairing_code(id),
  paired_at     timestamptz NOT NULL DEFAULT now(),
  revoked_at    timestamptz,
  last_seen_at  timestamptz
);
CREATE INDEX paired_device_target_idx ON paired_device (target_id);

-- ------------------------------------------------------------------- RLS ---
-- device_pairing_code: owner-write shape, an EXACT mirror of 0014's
-- guardian_invite_owner_rw — the guardian who created a code sees/manages
-- exactly that code (create, and the cancel-before-use path the design
-- spec's own Flow section describes: "a Cancel button (revokes it early)").
-- No live-guardianship-edge re-derivation here: the ROUTE is the first lock
-- (server/routes.mjs checks the caller holds a live edge to childId, or is
-- minting their own guardian-role code, before ever calling createDevice
-- PairingCode()); this policy is the second, simpler backstop, same split
-- 0014's own header describes for createGuardianInvite().
--
-- The redeem path is the one genuinely new wrinkle, because the calling
-- device has no session at all yet — mirrors 0014's own accept-flow
-- precedent EXACTLY (that migration's own RLS comment: "the INVITED party
-- has no app_user row and therefore no session RLS can key off at all —
-- reading/accepting... runs as 'system' inside the route handler... with
-- the id itself standing in for the credential a session would otherwise
-- provide"). Same `current_role_name() = 'system'` shape, applied here to
-- reading, marking-redeemed, and incrementing failed_attempts on a code by
-- its own id/numeric_code — never by a listing query.
ALTER TABLE device_pairing_code ENABLE ROW LEVEL SECURITY;
ALTER TABLE device_pairing_code FORCE  ROW LEVEL SECURITY;

CREATE POLICY device_pairing_code_owner_rw ON device_pairing_code
  FOR ALL
  USING (current_role_name() = 'system' OR created_by = current_actor())
  WITH CHECK (current_role_name() = 'system' OR created_by = current_actor());

-- paired_device read/revoke: family-scoped, reusing kiosk-pin/verify's own
-- "every live guardian of this child" scoping directly (actor_has_edge(),
-- 0003_session_context.sql) rather than inventing a second definition of
-- "this child's family" — a child-role row is visible/revocable by any
-- guardian holding a live edge to target_id (the child); a guardian-role
-- row is visible/revocable by that guardian themself OR by any guardian who
-- shares a live edge to at least one child with them (the design spec's own
-- "every guardian holding a live edge to that child" list scoping, applied
-- here to a single row rather than a listing — GET .../paired-devices
-- itself still does its OWN query-shaped version of this same reuse in
-- pairedDevicesForChild(), packages/db/src/pool.ts; this policy is the
-- second, independent lock behind it, same "the database enforces it too"
-- posture every RLS policy in this schema already takes).
--
-- INSERT is system-only: no guardian session ever inserts a paired_device
-- row directly — the only INSERT in this codebase is redeemDevicePairingCode
-- ()'s own system-scoped write, atomic with marking the code redeemed. A
-- guardian never gets a paired_device row any other way, so a real, guardian
-- -writable INSERT policy here would be a path that authorizes something no
-- route ever needs and nothing tests: unused surface on a real, regulated
-- security table.
ALTER TABLE paired_device ENABLE ROW LEVEL SECURITY;
ALTER TABLE paired_device FORCE  ROW LEVEL SECURITY;

CREATE POLICY paired_device_family_select ON paired_device
  FOR SELECT
  USING (
    current_role_name() = 'system'
    OR (role = 'child' AND actor_has_edge(target_id))
    OR (role = 'guardian' AND (
          target_id = current_actor()
          OR EXISTS (
               SELECT 1 FROM effective_guardianship eg
                WHERE eg.user_id = target_id AND actor_has_edge(eg.child_id)
             )
        ))
  );

CREATE POLICY paired_device_family_revoke ON paired_device
  FOR UPDATE
  USING (
    current_role_name() = 'system'
    OR (role = 'child' AND actor_has_edge(target_id))
    OR (role = 'guardian' AND (
          target_id = current_actor()
          OR EXISTS (
               SELECT 1 FROM effective_guardianship eg
                WHERE eg.user_id = target_id AND actor_has_edge(eg.child_id)
             )
        ))
  )
  WITH CHECK (
    current_role_name() = 'system'
    OR (role = 'child' AND actor_has_edge(target_id))
    OR (role = 'guardian' AND (
          target_id = current_actor()
          OR EXISTS (
               SELECT 1 FROM effective_guardianship eg
                WHERE eg.user_id = target_id AND actor_has_edge(eg.child_id)
             )
        ))
  );

CREATE POLICY paired_device_system_insert ON paired_device
  FOR INSERT
  WITH CHECK (current_role_name() = 'system');

-- ------------------------------------------------- health_check extension --
-- Same discipline every migration in this series restates: the
-- rls_unforced list is CARRIED FORWARD IN FULL (from 0031), plus
-- device_pairing_code and paired_device (this migration).
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
     -- Carried forward from 0031, plus device_pairing_code and
     -- paired_device (this migration).
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
                        'child_profile','device_pairing_code','paired_device')
     AND (c.relrowsecurity=false OR c.relforcerowsecurity=false)
  UNION ALL
  SELECT 'log_sequence_gap','critical',count(*),0,
         'Parent log sequences are not contiguous. P8 has been circumvented.'
    FROM (SELECT child_id, seq, lag(seq) OVER (PARTITION BY child_id ORDER BY seq) prev
            FROM message_log) x
   WHERE prev IS NOT NULL AND seq <> prev + 1
) h;

COMMENT ON TABLE device_pairing_code IS
  'A short-lived, single-use code (QR id + 6-digit fallback) a guardian '
  'generates to attach an ALREADY-EXISTING child or guardian identity to a '
  'new device. Never creates an identity -- see this migration''s own file '
  'header. Owner-write RLS for the guardian who created it; system-role for '
  'the pre-session redeem path, mirroring guardian_invite''s own accept-flow '
  'precedent (0014) exactly.';

COMMENT ON TABLE paired_device IS
  'A device that has redeemed a device_pairing_code and now holds a '
  'deviceId-bearing session. Family-scoped RLS reusing kiosk-pin/verify''s '
  '"every live guardian of this child" scoping (actor_has_edge()) -- no new '
  'family concept invented. revoked_at is checked on every request carrying '
  'a deviceId claim (packages/api/src/api.ts''s handle()) so a lost/stolen '
  'device can be cut off without touching its owner''s account.';

COMMIT;
