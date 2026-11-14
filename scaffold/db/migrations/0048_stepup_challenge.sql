-- ============================================================================
--  OLIVE BRANCH — 0048: a third WebAuthn challenge purpose, 'stepup'.
--
--  Security follow-up to S-B3 (MASTERFILE section 7.12). A guardian session on an
--  account that already holds a passkey but has NO PIN yet could set its first
--  PIN with no proof at all (POST /v1/me/pin accepts the first PIN
--  insert-if-absent), and then add a passkey of its own with that PIN: a
--  stolen session became a permanent takeover. The first PIN now needs a FRESH
--  passkey assertion, and that assertion must be bound to a challenge the
--  server just minted for this purpose. auth_challenge.purpose is a CHECK-ed
--  text column; 'register' and 'login' challenges must never be replayable as
--  step-up proof (or the reverse), so this is a separate purpose, not a reuse.
--
--  Idempotent and additive: the old constraint (auto-named by 0008) is dropped
--  and recreated with one more allowed value; no row is rewritten.
-- ============================================================================
BEGIN;
ALTER TABLE auth_challenge DROP CONSTRAINT IF EXISTS auth_challenge_purpose_check;
ALTER TABLE auth_challenge
  ADD CONSTRAINT auth_challenge_purpose_check CHECK (purpose IN ('register','login','stepup'));
COMMIT;
