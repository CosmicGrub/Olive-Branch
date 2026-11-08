-- ============================================================================
--  OLIVE BRANCH — paired-device long-lived credential (audit G-02/G-06/C-03)
--
--  A paired device used to receive ONE 1-hour session token at redeem time and
--  nothing else: after an hour every request from it was a 401 `expired`, and
--  the client papered over that by calling the dev-only POST /v1/auth/dev-login
--  (404 in production, DEV_LOGIN=0). This migration gives each paired_device
--  row the missing piece: a long-lived device credential, of which only the
--  SHA-256 digest is stored. POST /v1/auth/session/refresh trades
--  {deviceId, deviceCredential} for a fresh short session.
--
--  The credential is 32 random bytes (256 bits) from the CSPRNG, so a plain
--  SHA-256 is the right digest (no offline-guessing problem exists to defend
--  against, unlike a 4-8 digit PIN, which is why pin_credential uses scrypt).
--
--  Nullable on purpose: a device paired BEFORE this migration holds no
--  credential. Such a row can never refresh (it gets invalid_device_credential
--  and must re-pair) — failing closed, never "a NULL hash matches anything".
--
--  No RLS change: paired_device's existing FORCE RLS policies (0032) already
--  cover the whole row. rowToPairedDevice() selects columns by name and never
--  returns this one, so the family-scoped SELECT policy cannot leak it through
--  the paired-devices list route either.
-- ============================================================================

BEGIN;

ALTER TABLE paired_device ADD COLUMN credential_hash text;

COMMENT ON COLUMN paired_device.credential_hash IS
  'Lowercase hex SHA-256 of the device''s long-lived credential (256-bit CSPRNG '
  'value, returned to the device exactly once, at redeem). NULL for a device '
  'paired before 0038 — it cannot refresh and must re-pair. Never returned by '
  'any route.';

COMMIT;
