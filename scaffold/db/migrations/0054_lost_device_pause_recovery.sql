-- ============================================================================
--  OLIVE BRANCH -- a lost phone, a pause, ending a parent, and recovery with a
--  second grown-up's yes and a waiting period
--
--  What this adds, and the one rule behind each part. NOTHING here deletes
--  anything: every step only stops a device or a person from acting, and every
--  step but the last can be undone.
--
--  1. paired_device gains a LOST state (lost_at, lost_by, lost_seq, found_at,
--     found_by, needs_reapproval) and a WIPE order (wipe_ordered_at, wiped_at).
--     A lost phone is cut off at once (isPairedDeviceRevoked also answers true
--     for it, so its live session dies on its next request) but its row, its
--     credential and its history stay, so "I have it" can bring it back after
--     a grown-up approves. revoked_at stays what it was: permanent.
--     lost_seq counts how many times the phone has been marked lost, so a
--     replayed "found" aimed at an earlier loss cannot undo a later one.
--
--  2. account_pause: either parent may pause another parent's reach. A pause is
--     visible (a security_event), reversible (any OTHER grown-up resumes it)
--     and lapses by itself after 14 days (expires_at), so it can never turn
--     into a quiet removal. The paused person cannot resume themselves and
--     nobody can pause themselves.
--
--  3. parent_end_request: ending a parent needs both parents or a 14 day wait.
--     "Both" means the person being ended agrees. Otherwise it takes effect
--     only after 14 days (ready_at) and only if nobody (the person, or any
--     other parent) has stopped it. Everyone is told when it starts.
--
--  4. recovery_sheet / recovery_helper / account_recovery_request: a new phone
--     asks to take over an account with the family's printed recovery sheet.
--     It is let in only after a second grown-up (or the one named helper, who
--     can ONLY confirm) says yes AND 48 hours have passed AND nobody stopped
--     it. A sole grown-up with nobody to ask waits 72 hours. Every grown-up is
--     told when it starts; anyone can stop it. Only digests are stored.
--
--  5. security_event learns the new kinds, and a subject_user_id so a notice
--     can say WHOSE phone ("Sam marked Alex's phone as lost").
--
--  RLS: every new table is ENABLE + FORCE with a system-only policy. The routes
--  (PIN step-up, live-edge checks) are the first lock; no session of any kind
--  reads or writes these tables directly.
-- ============================================================================

BEGIN;

-- ---------------------------------------------------- paired_device -------
ALTER TABLE paired_device
  ADD COLUMN lost_at            timestamptz,
  ADD COLUMN lost_by            uuid REFERENCES app_user(id) ON DELETE SET NULL,
  ADD COLUMN lost_seq           integer NOT NULL DEFAULT 0 CHECK (lost_seq >= 0),
  ADD COLUMN found_at           timestamptz,
  ADD COLUMN found_by           uuid REFERENCES app_user(id) ON DELETE SET NULL,
  ADD COLUMN needs_reapproval   boolean NOT NULL DEFAULT false,
  ADD COLUMN wipe_ordered_at    timestamptz,
  ADD COLUMN wipe_ordered_by    uuid REFERENCES app_user(id) ON DELETE SET NULL,
  ADD COLUMN wiped_at           timestamptz;

ALTER TABLE paired_device
  ADD CONSTRAINT paired_device_wipe_needs_lost
    CHECK (wipe_ordered_at IS NULL OR lost_at IS NOT NULL),
  ADD CONSTRAINT paired_device_wipe_is_for_grown_ups
    CHECK (wipe_ordered_at IS NULL OR role = 'guardian'),
  ADD CONSTRAINT paired_device_lost_seq_counts
    CHECK (lost_at IS NULL OR lost_seq >= 1);

COMMENT ON COLUMN paired_device.lost_at IS
  'Set when a grown-up marks the phone as lost; cleared by "found". While set the device is cut off '
  '(isPairedDeviceRevoked) but nothing is deleted (0054). revoked_at is the permanent one.';
COMMENT ON COLUMN paired_device.lost_seq IS
  'How many times the device has been marked lost. A "found" must name the seq it saw, so an old '
  'answer cannot undo a newer loss.';
COMMENT ON COLUMN paired_device.needs_reapproval IS
  'Set by "found": the device stays cut off until its owner proves the account PIN on it (grown-up '
  'phone) and the credential is rotated. A child tablet never sees a PIN screen and is not flagged.';
COMMENT ON COLUMN paired_device.wipe_ordered_at IS
  'A grown-up asked this LOST grown-up phone to erase the app''s local copy the next time it connects. '
  'Never for a child tablet (her private areas are hers; no parent lever may erase them).';

-- ------------------------------------------------------ account_pause -----
CREATE TABLE account_pause (
  id          uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id     uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  paused_by   uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  paused_at   timestamptz NOT NULL DEFAULT now(),
  expires_at  timestamptz NOT NULL,
  resumed_at  timestamptz,
  resumed_by  uuid REFERENCES app_user(id) ON DELETE SET NULL,
  CONSTRAINT account_pause_not_self CHECK (paused_by <> user_id),
  CONSTRAINT account_pause_resume_not_self CHECK (resumed_by IS NULL OR resumed_by <> user_id),
  -- resumed_at set with resumed_by NULL means the pause lapsed on its own (expires_at)
  -- a pause is a short, visible thing by design: at most 14 days
  CONSTRAINT account_pause_short CHECK (expires_at > paused_at AND expires_at <= paused_at + interval '14 days')
);
CREATE UNIQUE INDEX account_pause_one_live_idx ON account_pause (user_id) WHERE resumed_at IS NULL;
CREATE INDEX account_pause_user_idx ON account_pause (user_id, paused_at DESC);

ALTER TABLE account_pause ENABLE ROW LEVEL SECURITY;
ALTER TABLE account_pause FORCE  ROW LEVEL SECURITY;
CREATE POLICY account_pause_system_all ON account_pause
  FOR ALL USING (current_role_name() = 'system')
  WITH CHECK (current_role_name() = 'system');

COMMENT ON TABLE account_pause IS
  'One grown-up pausing another grown-up''s reach (0054). Visible, reversible by any OTHER grown-up, '
  'lapses after at most 14 days. System-only RLS; the routes are the lock.';

-- ---------------------------------------------------- parent_end_request --
CREATE TABLE parent_end_request (
  id            uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  subject_id    uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  proposed_by   uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  created_at    timestamptz NOT NULL DEFAULT now(),
  -- the 14 day wait: nothing takes effect before this unless the subject agrees
  ready_at      timestamptz NOT NULL,
  agreed_at     timestamptz,
  cancelled_at  timestamptz,
  cancelled_by  uuid REFERENCES app_user(id) ON DELETE SET NULL,
  completed_at  timestamptz,
  completed_how text CHECK (completed_how IN ('agreed', 'waited')),
  CONSTRAINT parent_end_not_self CHECK (proposed_by <> subject_id),
  CONSTRAINT parent_end_wait_floor CHECK (ready_at >= created_at + interval '14 days'),
  CONSTRAINT parent_end_one_outcome CHECK (NOT (cancelled_at IS NOT NULL AND completed_at IS NOT NULL)),
  CONSTRAINT parent_end_complete_pair CHECK ((completed_at IS NULL) = (completed_how IS NULL))
);
CREATE UNIQUE INDEX parent_end_one_live_idx ON parent_end_request (subject_id)
  WHERE cancelled_at IS NULL AND completed_at IS NULL;

ALTER TABLE parent_end_request ENABLE ROW LEVEL SECURITY;
ALTER TABLE parent_end_request FORCE  ROW LEVEL SECURITY;
CREATE POLICY parent_end_request_system_all ON parent_end_request
  FOR ALL USING (current_role_name() = 'system')
  WITH CHECK (current_role_name() = 'system');

COMMENT ON TABLE parent_end_request IS
  'Ending a parent: needs the person''s own yes, or a 14 day wait nobody stopped (0054). '
  'Never takes effect alone and sooner. System-only RLS.';

-- ------------------------------------------------------ recovery_sheet ----
CREATE TABLE recovery_sheet (
  id         uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id    uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  -- lowercase hex SHA-256 of a 160-bit CSPRNG token (printed once, in groups of four)
  token_hash text NOT NULL UNIQUE CHECK (token_hash ~ '^[0-9a-f]{64}$'),
  created_at timestamptz NOT NULL DEFAULT now(),
  retired_at timestamptz
);
CREATE UNIQUE INDEX recovery_sheet_one_live_idx ON recovery_sheet (user_id) WHERE retired_at IS NULL;

ALTER TABLE recovery_sheet ENABLE ROW LEVEL SECURITY;
ALTER TABLE recovery_sheet FORCE  ROW LEVEL SECURITY;
CREATE POLICY recovery_sheet_system_all ON recovery_sheet
  FOR ALL USING (current_role_name() = 'system')
  WITH CHECK (current_role_name() = 'system');

COMMENT ON TABLE recovery_sheet IS
  'The printed recovery sheet of one account (0054). Only its SHA-256 is stored; the server can never '
  'show it again. One live sheet per account; making a new one retires the old. System-only RLS.';

-- ----------------------------------------------------- recovery_helper ----
CREATE TABLE recovery_helper (
  id               uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id          uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  offer_hash       text NOT NULL UNIQUE CHECK (offer_hash ~ '^[0-9a-f]{64}$'),
  offer_expires_at timestamptz NOT NULL,
  helper_user_id   uuid REFERENCES app_user(id) ON DELETE CASCADE,
  accepted_at      timestamptz,
  created_at       timestamptz NOT NULL DEFAULT now(),
  ended_at         timestamptz,
  ended_by         uuid REFERENCES app_user(id) ON DELETE SET NULL,
  CONSTRAINT recovery_helper_not_self CHECK (helper_user_id IS NULL OR helper_user_id <> user_id),
  CONSTRAINT recovery_helper_accept_pair CHECK ((helper_user_id IS NULL) = (accepted_at IS NULL)),
  CONSTRAINT recovery_helper_offer_short CHECK (offer_expires_at <= created_at + interval '7 days')
);
CREATE UNIQUE INDEX recovery_helper_one_live_idx ON recovery_helper (user_id) WHERE ended_at IS NULL;
CREATE INDEX recovery_helper_helper_idx ON recovery_helper (helper_user_id) WHERE ended_at IS NULL;

ALTER TABLE recovery_helper ENABLE ROW LEVEL SECURITY;
ALTER TABLE recovery_helper FORCE  ROW LEVEL SECURITY;
CREATE POLICY recovery_helper_system_all ON recovery_helper
  FOR ALL USING (current_role_name() = 'system')
  WITH CHECK (current_role_name() = 'system');

COMMENT ON TABLE recovery_helper IS
  'The ONE trusted helper a sole grown-up may name (0054). The helper can only confirm or stop a recovery '
  'request: no guardianship edge, no data, no other power. System-only RLS.';

-- ------------------------------------------------ account_recovery_request
CREATE TABLE account_recovery_request (
  id            uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id       uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  sheet_id      uuid NOT NULL REFERENCES recovery_sheet(id) ON DELETE CASCADE,
  -- the new phone's own way to ask "is it time yet": a 256-bit token, stored hashed
  poll_hash     text NOT NULL CHECK (poll_hash ~ '^[0-9a-f]{64}$'),
  device_label  text NOT NULL DEFAULT '' CHECK (char_length(device_label) <= 60),
  created_at    timestamptz NOT NULL DEFAULT now(),
  -- who has to say yes: another parent, the named helper, or nobody (every grown-up phone is gone)
  path          text NOT NULL CHECK (path IN ('parent', 'helper', 'sheet_only')),
  wait_hours    integer NOT NULL CHECK (wait_hours BETWEEN 24 AND 168),
  ready_at      timestamptz NOT NULL,
  expires_at    timestamptz NOT NULL,
  confirmed_at  timestamptz,
  confirmed_by  uuid REFERENCES app_user(id) ON DELETE SET NULL,
  confirmed_as  text CHECK (confirmed_as IN ('parent', 'helper')),
  cancelled_at  timestamptz,
  cancelled_by  uuid REFERENCES app_user(id) ON DELETE SET NULL,
  cancelled_as  text CHECK (cancelled_as IN ('own_phone', 'parent', 'helper')),
  completed_at  timestamptz,
  completed_device_id uuid REFERENCES paired_device(id) ON DELETE SET NULL,
  CONSTRAINT recovery_request_wait_floor CHECK (ready_at >= created_at + interval '24 hours'),
  CONSTRAINT recovery_request_confirm_pair
    CHECK ((confirmed_at IS NULL) = (confirmed_by IS NULL) AND (confirmed_at IS NULL) = (confirmed_as IS NULL)),
  CONSTRAINT recovery_request_one_outcome CHECK (NOT (cancelled_at IS NOT NULL AND completed_at IS NOT NULL)),
  CONSTRAINT recovery_request_expiry CHECK (expires_at > ready_at)
);
CREATE UNIQUE INDEX recovery_request_one_live_idx ON account_recovery_request (user_id)
  WHERE cancelled_at IS NULL AND completed_at IS NULL;
CREATE INDEX recovery_request_user_idx ON account_recovery_request (user_id, created_at DESC);

ALTER TABLE account_recovery_request ENABLE ROW LEVEL SECURITY;
ALTER TABLE account_recovery_request FORCE  ROW LEVEL SECURITY;
CREATE POLICY account_recovery_request_system_all ON account_recovery_request
  FOR ALL USING (current_role_name() = 'system')
  WITH CHECK (current_role_name() = 'system');

COMMENT ON TABLE account_recovery_request IS
  'A new phone asking to take over an account with the printed recovery sheet (0054): a second '
  'grown-up''s (or the helper''s) yes, a 48 hour wait (72 with nobody to ask), anyone can stop it. '
  'System-only RLS.';

-- ---------------------------------------------------- security_event -------
ALTER TABLE security_event ADD COLUMN subject_user_id uuid REFERENCES app_user(id) ON DELETE SET NULL;

ALTER TABLE security_event DROP CONSTRAINT security_event_kind_check;
ALTER TABLE security_event ADD CONSTRAINT security_event_kind_check
  CHECK (kind IN (
    'passkey_added', 'passkey_removed', 'pin_changed', 'pin_lockout',
    'device_paired', 'export_taken', 'invite_created', 'guardian_added',
    'account_recovered',
    'device_lost', 'device_found', 'device_wipe_ordered', 'device_wiped', 'device_reapproved',
    'account_paused', 'account_resumed',
    'parent_end_started', 'parent_end_agreed', 'parent_end_stopped', 'parent_ended',
    'recovery_sheet_made', 'recovery_helper_named', 'recovery_helper_ended',
    'recovery_started', 'recovery_confirmed', 'recovery_stopped', 'recovery_completed'));

-- The append-only trigger now also pins the new column: only notified_at may move.
CREATE OR REPLACE FUNCTION security_event_append_only() RETURNS trigger AS $$
BEGIN
  IF TG_OP = 'DELETE' AND pg_trigger_depth() >= 2 THEN
    RETURN OLD;  -- child_id ON DELETE CASCADE only
  END IF;
  IF TG_OP = 'UPDATE'
     AND NEW.seq = OLD.seq AND NEW.child_id = OLD.child_id AND NEW.actor_id = OLD.actor_id
     AND NEW.kind = OLD.kind AND NEW.summary = OLD.summary AND NEW.created_at = OLD.created_at
     AND NEW.subject_user_id IS NOT DISTINCT FROM OLD.subject_user_id THEN
    RETURN NEW;  -- only notified_at may move
  END IF;
  -- the subject's account may be deleted: its reference is cleared, nothing else changes
  IF TG_OP = 'UPDATE' AND pg_trigger_depth() >= 2
     AND NEW.seq = OLD.seq AND NEW.child_id = OLD.child_id AND NEW.actor_id = OLD.actor_id
     AND NEW.kind = OLD.kind AND NEW.summary = OLD.summary AND NEW.created_at = OLD.created_at
     AND NEW.subject_user_id IS NULL THEN
    RETURN NEW;
  END IF;
  RAISE EXCEPTION 'security_event is append-only (% refused)', TG_OP
    USING ERRCODE = 'integrity_constraint_violation';
END;
$$ LANGUAGE plpgsql;

COMMIT;
