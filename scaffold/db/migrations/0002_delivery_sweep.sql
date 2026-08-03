-- ============================================================================
--  OLIVE BRANCH — delivery sweep and rematerialization
--  MASTERFILE §4.5, §6.3
--
--  Two hazards this file exists to close:
--    1. Concurrent sweeps double-delivering the same intent.
--    2. A stale scheduled_at surviving a zone change mid-batch.
-- ============================================================================

BEGIN;

-- ------------------------------------------------------------------ claim ---
-- FOR UPDATE SKIP LOCKED lets N workers drain the queue without blocking each
-- other. The `AND state = 'ready'` inside the UPDATE is the compare-and-swap:
-- even if two workers somehow select the same row, only one transition wins.
CREATE OR REPLACE FUNCTION claim_due_intents(p_limit int DEFAULT 100)
RETURNS TABLE (id uuid, child_id uuid, payload_kind text, payload_ref uuid) AS $$
  WITH claimed AS (
    SELECT di.id
      FROM delivery_intent di
     WHERE di.state = 'ready'
       AND di.scheduled_at <= now()
       AND di.expires_at   >  now()
     ORDER BY di.scheduled_at
     LIMIT p_limit
     FOR UPDATE SKIP LOCKED
  )
  UPDATE delivery_intent d
     SET state = 'delivered'
    FROM claimed c
   WHERE d.id = c.id
     AND d.state = 'ready'          -- compare-and-swap; prevents double-fire
  RETURNING d.id, d.child_id, d.payload_kind, d.payload_ref;
$$ LANGUAGE sql;

-- Expire anything whose retention window closed before it was ever delivered.
-- COPPA §10.1: an undeliverable intent does not linger.
CREATE OR REPLACE FUNCTION expire_stale_intents()
RETURNS integer AS $$
  WITH x AS (
    UPDATE delivery_intent
       SET state = 'expired'
     WHERE state IN ('pending','ready')
       AND expires_at <= now()
    RETURNING 1
  ) SELECT count(*)::int FROM x;
$$ LANGUAGE sql;

-- --------------------------------------------------------- invalidation -----
-- §4.5. Called on: child_tz_interval change, day_part change, custody schedule
-- change, calendar event move, and the nightly DST sweep.
--
-- Scope is deliberately narrow: only intents that have NOT yet been delivered
-- and whose scheduled_at is still in the future. A delivered message is the
-- child's and is never retroactively re-timed.
CREATE OR REPLACE FUNCTION invalidate_for_child(p_child uuid)
RETURNS integer AS $$
  WITH x AS (
    UPDATE delivery_intent
       SET state           = 'pending',
           scheduled_at    = NULL,
           materialized_tz = NULL,
           materialized_at = NULL
     WHERE child_id = p_child
       AND state IN ('pending','ready')
       AND (scheduled_at IS NULL OR scheduled_at > now())
    RETURNING 1
  ) SELECT count(*)::int FROM x;
$$ LANGUAGE sql;

-- Trigger: any change to the timezone timeline or day-parts invalidates that
-- child's undelivered queue.
--
-- STATEMENT-level with transition tables, NOT row-level. A row-level trigger
-- re-invalidates the entire queue once per changed row: seeding 10 day-parts
-- against a 550-intent batch produced 5,500 redundant UPDATEs. Statement-level
-- collapses that to one invalidation per affected child per statement.
CREATE OR REPLACE FUNCTION trg_invalidate_ins() RETURNS trigger AS $$
BEGIN
  PERFORM invalidate_for_child(s.child_id)
     FROM (SELECT DISTINCT child_id FROM changed) s;
  RETURN NULL;
END $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION trg_invalidate_del() RETURNS trigger AS $$
BEGIN
  PERFORM invalidate_for_child(s.child_id)
     FROM (SELECT DISTINCT child_id FROM gone) s;
  RETURN NULL;
END $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION trg_invalidate_upd() RETURNS trigger AS $$
BEGIN
  PERFORM invalidate_for_child(s.child_id) FROM (
    SELECT DISTINCT child_id FROM changed
    UNION
    SELECT DISTINCT child_id FROM gone
  ) s;
  RETURN NULL;
END $$ LANGUAGE plpgsql;

CREATE TRIGGER tz_interval_invalidates_ins AFTER INSERT ON child_tz_interval
  REFERENCING NEW TABLE AS changed
  FOR EACH STATEMENT EXECUTE FUNCTION trg_invalidate_ins();
CREATE TRIGGER tz_interval_invalidates_upd AFTER UPDATE ON child_tz_interval
  REFERENCING NEW TABLE AS changed OLD TABLE AS gone
  FOR EACH STATEMENT EXECUTE FUNCTION trg_invalidate_upd();
CREATE TRIGGER tz_interval_invalidates_del AFTER DELETE ON child_tz_interval
  REFERENCING OLD TABLE AS gone
  FOR EACH STATEMENT EXECUTE FUNCTION trg_invalidate_del();

CREATE TRIGGER day_part_invalidates_ins AFTER INSERT ON day_part
  REFERENCING NEW TABLE AS changed
  FOR EACH STATEMENT EXECUTE FUNCTION trg_invalidate_ins();
CREATE TRIGGER day_part_invalidates_upd AFTER UPDATE ON day_part
  REFERENCING NEW TABLE AS changed OLD TABLE AS gone
  FOR EACH STATEMENT EXECUTE FUNCTION trg_invalidate_upd();
CREATE TRIGGER day_part_invalidates_del AFTER DELETE ON day_part
  REFERENCING OLD TABLE AS gone
  FOR EACH STATEMENT EXECUTE FUNCTION trg_invalidate_del();

-- ------------------------------------------------------------ batch view ----
-- Parent-facing progress. §8.2.8: the CHILD is never shown any of this.
CREATE OR REPLACE VIEW batch_progress AS
SELECT b.id, b.child_id, b.sender_id, b.label, b.reason,
       count(*)                                              AS total,
       count(*) FILTER (WHERE d.state IN ('delivered','opened')) AS delivered,
       count(*) FILTER (WHERE d.state IN ('pending','ready'))    AS remaining,
       count(*) FILTER (WHERE d.state = 'expired')               AS missed,
       min(d.scheduled_at) FILTER (WHERE d.state = 'ready')      AS next_at
  FROM intent_batch b
  JOIN delivery_intent d ON d.batch_id = b.id
 GROUP BY b.id;

COMMIT;
