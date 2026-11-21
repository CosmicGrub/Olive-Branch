-- ============================================================================
--  OLIVE BRANCH -- account recovery without email
--
--  Before this migration a grown-up whose only signed-in phone was lost,
--  broken or wiped had NO way back into their account: the server has no
--  mailer (verified email is out of scope, docs/planning/DECISIONS.md), the
--  account has no email on file (sign-up never asks for one), and the only
--  other sign-in door is a pairing code made on a phone that is STILL signed
--  in (POST /v1/me/device-pairing-codes), which is exactly what is gone.
--
--  This adds the one thing the operator path was missing:
--
--    account_recovery_code   an operator-issued, single-use, short-lived,
--                            HASHED recovery code for ONE existing account.
--                            The operator mints it with
--                            tools/provision-recovery.mjs after talking to the
--                            person (the same trusted hand-over the invite-
--                            only sign-up allowance already relies on). Only
--                            its SHA-256 is stored.
--
--  A code alone signs nobody in. POST /v1/auth/recover needs the code AND the
--  account's own PIN (two different secrets held by two different parties),
--  counts every wrong PIN against the code (five and it is burned) and against
--  the account's own PIN lockout, enrols a NEW device and revokes every other
--  guardian device of that account (a lost phone must stop working), and
--  leaves a security_event the account's other grown-ups can see.
--
--  An account with no PIN yet (one made from an invite starts without one)
--  cannot be recovered this way: with no second secret, a code on its own
--  would be a single point of failure.
--
--  One live code per account: issuing a new one revokes the older ones.
--
--  RLS: ENABLE + FORCE with a system-only policy (the same shape as
--  signup_allowance, 0050): no guardian or child session can read, list or
--  write the table. The recover route and the operator CLI run as `system`.
-- ============================================================================

BEGIN;

CREATE TABLE account_recovery_code (
  id               uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id          uuid NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  -- lowercase hex SHA-256 of a 256-bit CSPRNG token (fast hash is correct for
  -- the same reason as signup_allowance.token_hash: nothing low-entropy to
  -- enumerate offline).
  token_hash       text NOT NULL UNIQUE CHECK (token_hash ~ '^[0-9a-f]{64}$'),
  -- The operator's own note ("family 3, lost phone"). Never a name or email.
  label            text NOT NULL DEFAULT '' CHECK (char_length(label) <= 80),
  created_at       timestamptz NOT NULL DEFAULT now(),
  expires_at       timestamptz NOT NULL,
  -- wrong PINs presented with this code; the route burns the code at 5
  failed_attempts  integer NOT NULL DEFAULT 0 CHECK (failed_attempts >= 0),
  revoked_at       timestamptz,
  redeemed_at      timestamptz,
  redeemed_device_id uuid REFERENCES paired_device(id) ON DELETE SET NULL,
  CONSTRAINT account_recovery_expiry_after_creation CHECK (expires_at > created_at),
  -- a recovery code is a short-lived thing by design
  CONSTRAINT account_recovery_short_lived CHECK (expires_at <= created_at + interval '14 days'),
  CONSTRAINT account_recovery_not_both CHECK (NOT (redeemed_at IS NOT NULL AND revoked_at IS NOT NULL))
);

-- At most one LIVE code per account (issuing another revokes the old one).
CREATE UNIQUE INDEX account_recovery_one_live_idx ON account_recovery_code (user_id)
  WHERE redeemed_at IS NULL AND revoked_at IS NULL;

ALTER TABLE account_recovery_code ENABLE ROW LEVEL SECURITY;
ALTER TABLE account_recovery_code FORCE  ROW LEVEL SECURITY;
CREATE POLICY account_recovery_code_system_all ON account_recovery_code
  FOR ALL USING (current_role_name() = 'system')
  WITH CHECK (current_role_name() = 'system');

COMMENT ON TABLE account_recovery_code IS
  'Operator-issued, single-use, hashed recovery code for one existing account '
  '(0053). Signs nobody in alone: POST /v1/auth/recover also needs the '
  'account PIN. System-only RLS.';

-- ---------------------------------------------------- security_event -------
ALTER TABLE security_event DROP CONSTRAINT security_event_kind_check;
ALTER TABLE security_event ADD CONSTRAINT security_event_kind_check
  CHECK (kind IN (
    'passkey_added', 'passkey_removed', 'pin_changed', 'pin_lockout',
    'device_paired', 'export_taken', 'invite_created', 'guardian_added',
    'account_recovered'));

COMMIT;
