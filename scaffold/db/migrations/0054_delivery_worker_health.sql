-- ============================================================================
--  OLIVE BRANCH — 0054: a dead delivery worker is visible, and a stuck
--  `pending` row can no longer crowd out a fresh one.
--
--  TWO LIVE GAPS, ONE MIGRATION (both are about the delivery worker).
--
--  1. A worker that is not running is silent. Nothing recorded that a worker
--     had ever ticked, so a stopped or crash-looping `delivery` container, or a
--     server started with DELIVERY_IN_SERVER=0 beside no worker at all, looked
--     exactly like a healthy idle system: /readyz degraded never failed a
--     healthcheck and health_check had no delivery-worker row. Fixed here by a
--     one-row-per-worker heartbeat table plus an aggregate-only reader.
--
--  2. The rematerialize scan ordered pending rows oldest-first with a LIMIT.
--     A pending row that can legitimately stay pending for a long time (no
--     bedtime defined yet, an on-event row whose event has not happened) stays
--     at the front of that order for ever, so enough of them (the batch limit
--     is 500) starve every newer row: a fresh message never became `ready`.
--     Fixed by ordering on a last-checked stamp (never-checked first), stamped
--     each time a row is looked at and left pending, with a partial index on
--     exactly the pending rows so the scan stays an index walk. Never-checked rows
--     (a freshly queued message) go first, newest first, so a new message is
--     promoted on the very next tick however many stuck rows sit behind it; a
--     stamped row then waits its turn behind every row that has not been looked
--     at since, oldest stamp first.
--
--  WHAT IS STORED. worker_heartbeat holds a worker NAME, timestamps, the tick
--  interval and a failure counter. No family data, no child id, no host name.
--  It is FORCE-RLS like every table here: only a `system` session reads or
--  writes it, plus a read-only policy that opens while app.health_probe is on.
--
--  THE READER. delivery_health() is the same shape as health_counts() (0047):
--  an aggregate-only SECURITY DEFINER function that raises app.health_probe for
--  one counting query and puts it back, returning ages in seconds and counts,
--  never a row. The monitoring login (health_monitor) is granted EXECUTE and
--  nothing else, so it can alert on a dead worker without being able to read a
--  message. The server's boot watch and tools/health-alert.mjs both read it.
-- ============================================================================

BEGIN;

-- ---- 2. round-robin rematerialize: last-checked stamp + partial index -------
ALTER TABLE delivery_intent ADD COLUMN rematerialize_checked_at timestamptz;

COMMENT ON COLUMN delivery_intent.rematerialize_checked_at IS
  'When the rematerialize sweep last looked at this row and left it pending. NULL = never looked at, '
  'or freshly (re)queued. The sweep orders on this (NULLS FIRST) so a row that stays pending for a '
  'legitimate reason goes to the back of the queue instead of blocking every newer row.';

-- Exactly the rows the sweep reads, in exactly the order it reads them.
CREATE INDEX delivery_intent_pending_sweep
  ON delivery_intent (rematerialize_checked_at NULLS FIRST, created_at DESC)
  WHERE state = 'pending';

-- Same body as 0002, plus: a re-queued row starts again at the FRONT of the sweep.
CREATE OR REPLACE FUNCTION invalidate_for_child(p_child uuid)
RETURNS integer AS $$
  WITH x AS (
    UPDATE delivery_intent
       SET state                    = 'pending',
           scheduled_at             = NULL,
           materialized_tz          = NULL,
           materialized_at          = NULL,
           rematerialize_checked_at = NULL
     WHERE child_id = p_child
       AND state IN ('pending','ready')
       AND (scheduled_at IS NULL OR scheduled_at > now())
    RETURNING 1
  ) SELECT count(*)::int FROM x;
$$ LANGUAGE sql;

-- ---- 1. worker heartbeat ----------------------------------------------------
CREATE TABLE worker_heartbeat (
  worker               text PRIMARY KEY CHECK (worker ~ '^[a-z][a-z0-9-]{0,31}$'),
  beat_at              timestamptz NOT NULL DEFAULT now(),
  last_ok_at           timestamptz,
  tick_ms              integer NOT NULL CHECK (tick_ms > 0),
  consecutive_failures integer NOT NULL DEFAULT 0 CHECK (consecutive_failures >= 0)
);

COMMENT ON TABLE worker_heartbeat IS
  'One row per background worker (delivery, delivery-in-server): the last time it completed a tick and '
  'the last time a tick succeeded. No family data. Written by the worker, read through delivery_health().';

ALTER TABLE worker_heartbeat ENABLE ROW LEVEL SECURITY;
ALTER TABLE worker_heartbeat FORCE ROW LEVEL SECURITY;

CREATE POLICY worker_heartbeat_system_all ON worker_heartbeat
  FOR ALL USING (current_role_name() = 'system')
  WITH CHECK (current_role_name() = 'system');
CREATE POLICY worker_heartbeat_health_probe ON worker_heartbeat
  FOR SELECT USING (current_setting('app.health_probe', true) = 'on');

-- ---- the aggregate-only reader ----------------------------------------------
-- worker_*_age_sec is taken over ALL workers (a one-container deployment hosts the worker in the
-- server, a compose stack runs the `delivery` service; either one alive is enough). tick_ms is
-- the freshest beat's own interval so a caller can judge "late" without knowing the env.
CREATE FUNCTION delivery_health()
RETURNS TABLE (
  pending bigint, ready bigint,
  oldest_ready_age_sec bigint, oldest_pending_age_sec bigint, oldest_unswept_age_sec bigint,
  worker_beat_age_sec bigint, worker_ok_age_sec bigint, worker_tick_ms integer)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, pg_catalog, pg_temp
AS $$
DECLARE
  v_prev text := coalesce(current_setting('app.health_probe', true), '');
BEGIN
  PERFORM set_config('app.health_probe', 'on', true);
  RETURN QUERY
  SELECT
    (SELECT count(*) FROM delivery_intent WHERE state = 'pending')::bigint,
    (SELECT count(*) FROM delivery_intent WHERE state = 'ready')::bigint,
    (SELECT EXTRACT(EPOCH FROM (now() - min(scheduled_at)))::bigint
       FROM delivery_intent WHERE state = 'ready' AND scheduled_at <= now()),
    (SELECT EXTRACT(EPOCH FROM (now() - min(created_at)))::bigint
       FROM delivery_intent WHERE state = 'pending'),
    -- how long the sweep has gone without looking at the row it has neglected longest
    (SELECT EXTRACT(EPOCH FROM (now() - min(coalesce(rematerialize_checked_at, created_at))))::bigint
       FROM delivery_intent WHERE state = 'pending'),
    (SELECT EXTRACT(EPOCH FROM (now() - max(beat_at)))::bigint FROM worker_heartbeat),
    (SELECT EXTRACT(EPOCH FROM (now() - max(last_ok_at)))::bigint FROM worker_heartbeat),
    (SELECT h.tick_ms FROM worker_heartbeat h ORDER BY h.beat_at DESC LIMIT 1);
  PERFORM set_config('app.health_probe', v_prev, true);
  RETURN;
END;
$$;

COMMENT ON FUNCTION delivery_health() IS
  'Aggregate-only delivery-worker monitoring read (0054): queue counts, ages in seconds and the worker '
  'heartbeat ages. Raises app.health_probe for one query like health_counts() (0047); never returns a row of family data.';

REVOKE ALL ON FUNCTION delivery_health() FROM PUBLIC;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_runtime') THEN
    GRANT EXECUTE ON FUNCTION delivery_health() TO app_runtime;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'health_monitor') THEN
    GRANT USAGE ON SCHEMA public TO health_monitor;
    GRANT EXECUTE ON FUNCTION delivery_health() TO health_monitor;
  END IF;
END $$;

COMMIT;
