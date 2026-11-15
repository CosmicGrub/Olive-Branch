-- ============================================================================
--  OLIVE BRANCH -- identity lane: a first account, a first child, and a real
--  second grown-up (audit gaps 1, 3 and 4)
--
--  Before this migration a fresh server had NO way to get a first account, a
--  child or a guardianship edge except raw SQL (server/seed-dev.mjs). An
--  invited grown-up could accept and bootstrap an account and then hold zero
--  access (0014/0020 say so, on purpose, until a step they could not
--  invent existed). This adds the three missing tables/columns and nothing
--  else:
--
--    signup_allowance   an operator-issued, single-use, expiring, HASHED token.
--                       The server is invite-only: nobody can create an
--                       account without one (HOSTING-AND-CALLS.md, "Multi-
--                       family readiness"). The token is shown once by
--                       tools/provision-signup.mjs; only its SHA-256 is stored.
--    signup_policy      one row: a kill switch and an optional account cap.
--    guardian_invite    gains the inviter-confirmation step: claimant_user_id
--                       (who showed up), confirmed_at / confirmed_by (the
--                       inviter said "yes, that is who I meant"), declined_at.
--                       The guardianship edge is created ONLY by the confirm
--                       step, never by accept or bootstrap.
--
--  paired_device.paired_via becomes nullable: a device enrolled at the moment
--  its account is created (signup, invite bootstrap) was not paired through a
--  numeric code, but it must still have the same long-lived credential so the
--  existing POST /v1/auth/session/refresh keeps it signed in past the one-hour
--  session. NULL means "enrolled at account creation".
--
--  security_event gains 'guardian_added' so the OTHER guardians see that a new
--  grown-up was given access (the same visibility device_paired gives).
--
--  RLS: both new tables ENABLE + FORCE with a system-only policy (the same
--  shape as 0014's accept path): no session of any kind can read or write
--  them. The signup route and the operator CLI run as `system`.
-- ============================================================================

BEGIN;

CREATE TABLE signup_allowance (
  id           uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  -- lowercase hex SHA-256 of a 256-bit CSPRNG token. A fast hash is correct
  -- here for the same reason deviceCredentialDigest() is: there is no
  -- low-entropy secret to enumerate offline.
  token_hash   text NOT NULL UNIQUE CHECK (token_hash ~ '^[0-9a-f]{64}$'),
  -- The operator's own note ("beta family 3"). Never a person's name or email;
  -- the CLI refuses anything containing '@'.
  label        text NOT NULL DEFAULT '' CHECK (char_length(label) <= 80),
  created_at   timestamptz NOT NULL DEFAULT now(),
  expires_at   timestamptz NOT NULL,
  redeemed_at  timestamptz,
  redeemed_by  uuid REFERENCES app_user(id) ON DELETE SET NULL,
  CONSTRAINT signup_allowance_expiry_after_creation CHECK (expires_at > created_at)
);
CREATE INDEX signup_allowance_redeemed_idx ON signup_allowance (redeemed_at)
  WHERE redeemed_at IS NOT NULL;

ALTER TABLE signup_allowance ENABLE ROW LEVEL SECURITY;
ALTER TABLE signup_allowance FORCE  ROW LEVEL SECURITY;
CREATE POLICY signup_allowance_system_all ON signup_allowance
  FOR ALL USING (current_role_name() = 'system')
  WITH CHECK (current_role_name() = 'system');

CREATE TABLE signup_policy (
  singleton    boolean PRIMARY KEY DEFAULT true CHECK (singleton),
  -- Kill switch. false refuses every sign-up even with a valid allowance.
  enabled      boolean NOT NULL DEFAULT true,
  -- Family cap: the most accounts sign-up may ever create. NULL = no cap.
  max_accounts integer CHECK (max_accounts IS NULL OR max_accounts >= 0)
);
INSERT INTO signup_policy (singleton) VALUES (true);

ALTER TABLE signup_policy ENABLE ROW LEVEL SECURITY;
ALTER TABLE signup_policy FORCE  ROW LEVEL SECURITY;
CREATE POLICY signup_policy_system_all ON signup_policy
  FOR ALL USING (current_role_name() = 'system')
  WITH CHECK (current_role_name() = 'system');

-- ---------------------------------------------------- guardian_invite ------
ALTER TABLE guardian_invite
  ADD COLUMN claimant_user_id uuid REFERENCES app_user(id) ON DELETE SET NULL,
  ADD COLUMN claimed_at       timestamptz,
  ADD COLUMN confirmed_at     timestamptz,
  ADD COLUMN confirmed_by     uuid REFERENCES app_user(id) ON DELETE SET NULL,
  ADD COLUMN declined_at      timestamptz;

-- Invites that already went through bootstrap keep their claimant.
UPDATE guardian_invite
   SET claimant_user_id = bootstrap_user_id, claimed_at = bootstrapped_at
 WHERE bootstrap_user_id IS NOT NULL;

ALTER TABLE guardian_invite
  ADD CONSTRAINT invite_claim_columns_paired
    CHECK (claimant_user_id IS NULL OR claimed_at IS NOT NULL),
  ADD CONSTRAINT invite_confirm_needs_claim
    CHECK (confirmed_at IS NULL OR claimed_at IS NOT NULL),
  ADD CONSTRAINT invite_not_both_confirmed_and_declined
    CHECK (NOT (confirmed_at IS NOT NULL AND declined_at IS NOT NULL));

COMMENT ON COLUMN guardian_invite.claimant_user_id IS
  'The app_user who presented this invite: the account its bootstrap created, '
  'or an existing account whose email matches invited_email and that called '
  'POST .../claim. Holds NO access by itself.';
COMMENT ON COLUMN guardian_invite.confirmed_at IS
  'Set exactly once, by POST .../confirm, in the same transaction that inserts '
  'the guardianship edge. The inviter, with their own PIN, is the only party '
  'who can cause this. Accept and bootstrap never do.';

-- ---------------------------------------------------- paired_device --------
ALTER TABLE paired_device ALTER COLUMN paired_via DROP NOT NULL;
COMMENT ON COLUMN paired_device.paired_via IS
  'The device_pairing_code this device redeemed. NULL = enrolled at account '
  'creation (sign-up or invite bootstrap) with no numeric code (0050).';

-- ---------------------------------------------------- security_event -------
ALTER TABLE security_event DROP CONSTRAINT security_event_kind_check;
ALTER TABLE security_event ADD CONSTRAINT security_event_kind_check
  CHECK (kind IN (
    'passkey_added', 'passkey_removed', 'pin_changed', 'pin_lockout',
    'device_paired', 'export_taken', 'invite_created', 'guardian_added'));

COMMIT;
