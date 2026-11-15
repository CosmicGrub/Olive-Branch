-- ============================================================================
--  OLIVE BRANCH -- a receipt is fixed at the moment she opens the message
--  MASTERFILE section 7.13 / 7.16.
--
--  Until now the sender's receipt phrase ("Watched at 8:45 PM her time -- at
--  bedtime.") was recomputed on every read from the child's CURRENT day-parts
--  and time-zone timeline. Both are editable: replacing the schedule or
--  recording a back-dated move silently rewrote what an old receipt said.
--
--  These two columns record what was true when she opened it:
--    opened_zone  the IANA zone she was in at that instant
--    opened_part  the day-part kind that was active (NULL = none / a free part)
--  A reader that finds opened_zone set uses it and never consults the
--  schedule again. Rows opened before this migration have both NULL and keep
--  the old computed behaviour (they are not backfilled: this file may run as
--  the table owner under FORCE ROW LEVEL SECURITY, where an UPDATE would
--  silently match nothing, and the history to compute from is exactly what is
--  unreliable).
--
--  Child safety: a zone name and a part name, neither a count or a score,
--  neither ever returned on a child surface. The sender reads them through a
--  guardian-only route.
-- ============================================================================

BEGIN;

ALTER TABLE delivery_intent
  ADD COLUMN opened_zone text,
  ADD COLUMN opened_part text;

ALTER TABLE delivery_intent
  ADD CONSTRAINT delivery_intent_opened_zone_valid
    CHECK (opened_zone IS NULL OR olive_valid_tz(opened_zone)),
  ADD CONSTRAINT delivery_intent_opened_part_valid
    CHECK (opened_part IS NULL OR opened_part IN
      ('wake','before_school','school','after_school','activity',
       'dinner','wind_down','bedtime','asleep','free')),
  -- a part without a zone would be a half-written snapshot
  ADD CONSTRAINT delivery_intent_opened_snapshot_whole
    CHECK (opened_part IS NULL OR opened_zone IS NOT NULL);

COMMIT;
