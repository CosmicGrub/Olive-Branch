-- ============================================================================
--  OLIVE BRANCH -- delivery receipts and the delivery worker's index
--  MASTERFILE section 7.13 (delivery timestamps and receipts), section 4.5.
--
--  Three facts the delivery chain could not record before this file:
--    1. WHEN a message became hers. delivery_intent only had `state` and
--       `materialized_at` (when the sweep last scheduled it), so the inbox
--       label "delivered N ago" was really "scheduled N ago", and a sender had
--       nothing to read a receipt from.
--    2. WHEN she opened it. POST .../inbox/:id/opened flipped `state` and
--       nothing else.
--
--    3. WHAT was true when she opened it (zone and day-part), see below.
--
--  All columns are nullable on purpose and are NOT backfilled here: this
--  file may run as the table owner under FORCE ROW LEVEL SECURITY, where an
--  UPDATE touching rows would silently match none of them. Readers use
--  COALESCE(delivered_at, materialized_at), which is exactly what the old
--  label used, so a row delivered before this migration reads as it always did.
--
--  Child safety: these are TIMESTAMPS, not counts. Nothing here is ever shown
--  to the child; the sender reads them through a guardian-only route.
-- ============================================================================

BEGIN;

ALTER TABLE delivery_intent
  ADD COLUMN delivered_at timestamptz,
  ADD COLUMN opened_at    timestamptz,
  -- What was true when she opened it, so a receipt is FIXED at that moment and
  -- a later edit of her day-parts or a back-dated zone move cannot re-word it:
  --   opened_zone  the IANA zone she was in at that instant
  --   opened_part  the day-part kind that was active (NULL = none)
  -- A reader that finds opened_zone set uses it and never consults the
  -- schedule again; NULL (rows opened before this) falls back to computing.
  -- A zone name and a part name: never a count, never on a child surface.
  ADD COLUMN opened_zone  text,
  ADD COLUMN opened_part  text;

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

-- An opened row was necessarily delivered first; a row that has not been
-- delivered cannot have been opened. (Rows from before this migration have
-- both NULL, which satisfies it.)
ALTER TABLE delivery_intent
  ADD CONSTRAINT delivery_intent_open_after_delivery
    CHECK (opened_at IS NULL OR delivered_at IS NULL OR opened_at >= delivered_at);

-- The delivery worker's claim scans state = 'ready' ordered by scheduled_at.
-- The init migration indexed only the 'pending' side.
CREATE INDEX IF NOT EXISTS delivery_intent_ready_due
  ON delivery_intent (scheduled_at) WHERE state = 'ready';

-- Same body as 0002 (FOR UPDATE SKIP LOCKED + compare-and-swap), plus the
-- moment of delivery, plus the one guard 0001 promised and no code yet kept:
-- child.deceased_at "halts all automation" (section 18.3). Now that a worker
-- really runs this, a message must not be delivered to a child recorded as
-- deceased; it stays `ready` (and expires with its retention window) until a
-- human resolves it. Signature unchanged, so existing callers and grants
-- carry over.
CREATE OR REPLACE FUNCTION claim_due_intents(p_limit int DEFAULT 100)
RETURNS TABLE (id uuid, child_id uuid, payload_kind text, payload_ref uuid) AS $$
  WITH claimed AS (
    SELECT di.id
      FROM delivery_intent di
     WHERE di.state = 'ready'
       AND di.scheduled_at <= now()
       AND di.expires_at   >  now()
       AND NOT EXISTS (SELECT 1 FROM child c
                        WHERE c.id = di.child_id AND c.deceased_at IS NOT NULL)
     ORDER BY di.scheduled_at
     LIMIT p_limit
     FOR UPDATE SKIP LOCKED
  )
  UPDATE delivery_intent d
     SET state = 'delivered', delivered_at = now()
    FROM claimed c
   WHERE d.id = c.id
     AND d.state = 'ready'          -- compare-and-swap; prevents double-fire
  RETURNING d.id, d.child_id, d.payload_kind, d.payload_ref;
$$ LANGUAGE sql;

COMMIT;
