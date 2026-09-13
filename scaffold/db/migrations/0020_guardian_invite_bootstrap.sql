-- ============================================================================
--  OLIVE BRANCH — guardian invite bootstrap: the account-creation gap
--  CHANGELOG v0.49.9 found and explicitly declined to invent an answer for.
--  MASTERFILE §11, §8.5, §7.1.
--
--  0014_guardian_invite.sql's own header named this precisely: accept
--  records a real decision, but closing the loop needs "an account-creation
--  route this codebase has never built for a brand-new guardian" —
--  guardian_setup.dart's passkey registration
--  (POST /v1/auth/webauthn/register/challenge, server/routes.mjs) has always
--  required an ALREADY-AUTHENTICATED guardian session, and nowhere does a
--  first-time guardian ever acquire one.
--
--  This migration does NOT touch WebAuthn registration itself, and it does
--  NOT create a guardianship row — that stays the real, separate, still-open
--  gap 0014's own header already named (turning an accepted invite into an
--  actual edge in the family graph is a decision this pass does not invent).
--  It closes exactly one thing: given an invite that has ALREADY been
--  through the real POST .../accept route, packages/db/src/pool.ts's new
--  bootstrapGuardianInvite() (this pass) creates the invited party's FIRST
--  app_user row so server/routes.mjs's new POST .../bootstrap route can mint
--  them a session — the one missing ingredient the EXISTING register/
--  challenge and register/verify routes need, completely unchanged, to
--  actually run.
--
--  Two new columns on the existing row, not a new table: bootstrapping is an
--  event that happens to an invite at most once, the same shape accepted_at/
--  revoked_at already record other one-time decisions in.
-- ============================================================================

BEGIN;

ALTER TABLE guardian_invite
  ADD COLUMN bootstrapped_at   timestamptz,
  ADD COLUMN bootstrap_user_id uuid REFERENCES app_user(id) ON DELETE RESTRICT;

-- Single-use, by construction, not just by the route's own "already_
-- bootstrapped" branch — the invite's own id is the ONLY thing an
-- unauthenticated first-time guardian ever holds (0014's own RLS comment:
-- "the id itself... standing in for the credential a session would
-- otherwise provide"), so unlike accepted_at/revoked_at, which only gate
-- what a caller may still DO, bootstrap_user_id is what stands between that
-- one id and a live, re-mintable session forever. This CHECK is the second
-- lock behind bootstrapGuardianInvite()'s own read-before-write —
-- symmetric with 0014's own invite_not_both_accepted_and_revoked, and with
-- this same migration's own bootstrap_needs_accept below.
ALTER TABLE guardian_invite
  ADD CONSTRAINT bootstrap_columns_paired
    CHECK ((bootstrapped_at IS NULL) = (bootstrap_user_id IS NULL));

-- Cannot bootstrap an invite that was never accepted — defense in depth,
-- since bootstrapGuardianInvite() already checks accepted_at IS NOT NULL
-- itself before ever writing this column; this is what keeps that true even
-- if a future bug in that one function forgets to.
ALTER TABLE guardian_invite
  ADD CONSTRAINT bootstrap_needs_accept
    CHECK (bootstrapped_at IS NULL OR accepted_at IS NOT NULL);

-- One app_user row per invite, the mirror case the CHECK pair above cannot
-- see (both constraints are per-row; this is per-COLUMN, across every row).
-- bootstrapGuardianInvite() always INSERTs a brand-new app_user row and
-- never attaches an existing one to a second invite, so this should never
-- actually bind through the real code path — kept as the same "the DB
-- enforces it independently" second lock 0008/0014's own RLS already state
-- for their own invariants, not as a hedge against a case believed likely.
-- Partial or NULL <> NULL under Postgres's own UNIQUE semantics would
-- silently exempt every not-yet-bootstrapped invite, which is most of them.
CREATE UNIQUE INDEX guardian_invite_bootstrap_user_uidx
  ON guardian_invite (bootstrap_user_id) WHERE bootstrap_user_id IS NOT NULL;

COMMENT ON COLUMN guardian_invite.bootstrapped_at IS
  'Set exactly once, by server/routes.mjs''s POST .../bootstrap route, the '
  'moment this invite mints the invited party''s first app_user row and '
  'session. NULL for every invite that has not reached that step — '
  'including every invite created before this migration.';
COMMENT ON COLUMN guardian_invite.bootstrap_user_id IS
  'The app_user row this invite''s bootstrap created. NOT a guardianship '
  'grant — that row still holds no edge to any child until a real, '
  'separate, still-undecided step (see this migration''s own header and '
  '0014''s) creates one.';

COMMIT;
