-- ============================================================================
--  OLIVE BRANCH — custody_order
--  MASTERFILE §5.4 (schema), §9.4 (calendar), §4.1 (child-local is canonical),
--  §8.2.5 ("3 sleeps until Dad's week" — computed on HER local day boundaries).
--
--  Closes a real gap found by audit: packages/custody/src/schedule.mjs's
--  sleepsUntilSideChange() is a real, unit-tested pure function (see
--  packages/custody/test/custody.test.mjs) that GET /v1/children/:childId/now
--  never called, because no table existed to feed it. This migration adds
--  that table and nothing else — routes.mjs and packages/db wire it up.
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- §5.4 names this table with four columns: id, child_id, order_tz, pattern,
-- rrule, holiday_rules, cost_split. That shape is necessary but NOT
-- sufficient to drive the real engine: schedule.ts's `Order` (the type
-- sleepsUntilSideChange/patternSideOn/blocks/exchanges actually consume) also
-- requires anchor_local_date and exchange_time (the rotation has to be
-- anchored to a real date and the exchange has to happen at a real wall-clock
-- time — §5.4's `rrule` is an alternative, not-yet-built representation of
-- the same thing) and an effective window (§5.4's snippet has no way to say
-- WHICH order is active today, and nothing else in that section supplies one
-- either). Rather than inventing an unrelated ad hoc shape, this migration
-- keeps every §5.4 column verbatim (order_tz, pattern, rrule, holiday_rules,
-- cost_split) and adds only what the tested engine demonstrably requires,
-- called out below.
CREATE TABLE custody_order (
  id                uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  child_id          uuid NOT NULL REFERENCES child(id) ON DELETE CASCADE,

  -- §5.4, verbatim. "Friday 6:00 PM" is meaningless without this; NEVER
  -- default to the server zone. Default is the child's primary-residence
  -- zone at entry (application-layer concern, not enforced here).
  order_tz          text NOT NULL,

  -- §5.4 lists pattern as '2-2-3'|'2-2-5-5'|'alternating_weeks'|'custom', but
  -- the real rotation engine (schedule.mjs's CYCLES map) has cycle templates
  -- for '2-2-3', '2-2-5-5', 'alternating_weeks' and 'week_on_week_off' —
  -- 'week_on_week_off' is real code with no mention in §5.4's prose, and
  -- 'custom' is prose with no cycle template and no rrule-based renderer
  -- behind it. The CHECK below reflects what patternSideOn() can actually
  -- compute today; storing a row the engine would crash on (CYCLES['custom']
  -- is undefined) is worse than rejecting it at write time. Widen this CHECK
  -- the day a 'custom'/rrule renderer actually exists.
  pattern           text NOT NULL
                    CHECK (pattern IN ('2-2-3','2-2-5-5','alternating_weeks',
                                        'week_on_week_off')),

  -- §5.4, verbatim, kept for the future 'custom' pattern. NOT consumed by
  -- schedule.mjs today — see the CHECK above.
  rrule             text,

  -- schedule.ts's Order.anchorLocalDate / Order.exchangeTime — the two
  -- columns §5.4 does not have. Side A holds day 0 of the 14-day cycle
  -- (dayIndex() in schedule.mjs); without an anchor, "which day is which
  -- side" is undefined. exchange_time is a wall-clock TIME, matching this
  -- codebase's existing convention for order-time-of-day (day_part.starts_local
  -- is the same type for the same reason: §4.1's order-time frame is a wall
  -- clock, not an instant).
  anchor_local_date date NOT NULL,
  exchange_time     time NOT NULL,

  -- §5.4 names this holiday_rules (kept verbatim); shape is
  -- HolidayRule[] from schedule.ts: [{name, startMonthDay, endMonthDay,
  -- evenYearSide, priority}, ...]. A holiday rule overrides the base pattern
  -- — see schedule.mjs's holidayOn()/sideOn() precedence.
  holiday_rules     jsonb NOT NULL DEFAULT '[]',

  -- §5.4, verbatim. Phase 3 (§5.11 split_rule); shipped now, unused until
  -- expenses read it — same "cheap now, expensive later" reasoning as
  -- media_artifact.preserved in 0001.
  cost_split        jsonb NOT NULL DEFAULT '{}',

  -- Neither §5.4 column exists to answer "which order is in force today" —
  -- a child can have more than one custody_order over her life (the court
  -- modifies the order; the old one does not retroactively stop having
  -- existed). Plain inclusive DATE columns, not a `daterange`: this
  -- codebase's ranges (guardianship.valid, day_part.effective,
  -- child_tz_interval.valid) default to an EXCLUSIVE upper bound, but
  -- schedule.ts's effectiveTo is INCLUSIVE ('the last local date the order
  -- applies') and schedule.mjs's blocks() compares against it with
  -- `iso > order.effectiveTo`. Storing an exclusive bound and handing its
  -- upper() straight to that comparison would silently shift every order's
  -- last valid day back by one — a one-line diff nobody would catch in
  -- review. Two plain DATE columns make the inclusive contract explicit
  -- instead of implicit in a bound flag.
  effective_from    date NOT NULL,
  effective_to      date,

  created_at        timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT custody_order_range_ordered
    CHECK (effective_to IS NULL OR effective_to >= effective_from),

  -- A child cannot be under two custody orders on the same day. Same
  -- technique as child_tz_interval/contact_ladder's own EXCLUDE constraints
  -- (btree_gist, extended here from a date pair to a daterange literal built
  -- with '[]' so BOTH bounds are treated as inclusive, matching the columns
  -- they are built from).
  EXCLUDE USING gist (
    child_id WITH =,
    daterange(effective_from, effective_to, '[]') WITH &&
  )
);

CREATE INDEX ON custody_order (child_id, effective_from DESC);

-- ---------------------------------------------------------------------------
-- RLS. custody_order is NOT a P6/P7 table — the child is meant to see her own
-- schedule (§8.2.5's "3 sleeps until Dad's week" is shown to HER, not just to
-- guardians; §9.4 explicitly has a child view of the calendar). So unlike
-- expense/message_log (which block the child role outright), a child session
-- gets a policy that admits her own row rather than none. Every other role
-- follows the exact same "not the child" shape already used for
-- expense_no_child / log_no_child in 0006 — cross-guardian isolation for
-- those roles is enforced at the application layer (can() + edgesFor(), the
-- "first lock", §5.17) via the childId-from-path check in api.ts, not by a
-- second, redundant edge check here.
ALTER TABLE custody_order ENABLE ROW LEVEL SECURITY;
ALTER TABLE custody_order FORCE  ROW LEVEL SECURITY;

CREATE POLICY custody_order_child_own ON custody_order
  FOR ALL USING (
    current_role_name() = 'child'
    AND current_child() IS NOT NULL
    AND child_id = current_child()
  );

CREATE POLICY custody_order_not_child_scope ON custody_order
  FOR ALL USING (current_role_name() IS DISTINCT FROM 'child');

COMMIT;
