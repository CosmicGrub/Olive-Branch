-- ============================================================================
--  OLIVE BRANCH — device_token learns its real delivery channel
--  MASTERFILE §8.11.4. Closes this codebase's own top-ranked prior-audit
--  finding: packages/devices/src/devices.ts's CHANNELS/admitDevice()/
--  channelAdvice() have existed, fully tested at the pure-function level,
--  since well before this migration — with zero production callers. This is
--  the schema half of finally wiring them in (see notify.ts's own v0.49.11
--  header for the dispatch-side half).
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- NULLABLE, not defaulted to a guess. device_token.platform (0012) only ever
-- distinguishes 'android'/'ios' — it cannot tell android_play from
-- android_amazon from android_bare, and nothing in this codebase can either,
-- client-side, as of this migration (see devices.ts's own §8.11.4 header for
-- the real, credential-free native detection that WOULD answer this —
-- scoped and explicitly deferred this pass, same reasoning as the
-- already-deferred LOCK_METHODS gap).
--
-- Defaulting an unknown Android device to 'android_play' here would be a
-- FABRICATED fact written into the schema itself — the exact thing this
-- codebase's house rule (§0) forbids. NULL is the honest state: "we do not
-- yet know this device's real channel." notify.ts's own dispatch falls back
-- to a conservative, clearly-commented assumption ONLY at send time, never
-- by writing a guess into storage.
ALTER TABLE device_token
  ADD COLUMN channel text
    CHECK (channel IN ('android_play','android_amazon','android_bare','ios','windows','web'));

COMMENT ON COLUMN device_token.channel IS
  'The real §8.11.4 delivery channel this device reports, when it reports '
  'one. NULL means unknown, not "assume android_play" — nothing client-side '
  'can distinguish android_play/android_amazon/android_bare yet (see '
  'devices.ts §8.11.4 header). iOS/Windows/Web clients CAN report their own '
  'channel today (there is nothing ambiguous about "this is iOS") and '
  'push_channel.dart does so as of v0.49.11.';

COMMIT;
