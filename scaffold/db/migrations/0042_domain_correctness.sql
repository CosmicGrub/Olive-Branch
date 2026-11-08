-- ============================================================================
--  OLIVE BRANCH — 0042: domain correctness (data-model audit S-D6, S-D10,
--  S-D20).
--
--  Everything here is a constraint or a column that makes a rule the engines
--  already state impossible to bypass at the database. Nothing is dropped except
--  the one index the PRN fix has to narrow. Every ADD CONSTRAINT is validated
--  against existing rows, so a database that already holds data breaking a rule
--  FAILS this migration loudly (and rolls back) rather than being silently
--  waved through with NOT VALID.
--
--  1. Medication safety (S-D6).
--       medication.max_doses_per_24h   PRN cap in any rolling 24 h, enforced by
--                                      packages/care checkDose() inside
--                                      recordDose (pool.ts).
--       medication_dose.recorded_at    when the server learned of the dose
--       medication_dose.backdated      true when the guardian supplied a
--                                      "given at" time; administered_at is then
--                                      the CLAIMED time and recorded_at the real
--                                      one, so a retroactive entry is audited,
--                                      never indistinguishable from a live one.
--       medication_dose.is_prn         the one-given-per-slot-per-day unique
--                                      index used to cover PRN doses too, which
--                                      made a SECOND legitimate PRN dose on the
--                                      same day impossible; it now covers only
--                                      scheduled (non-PRN) doses.
--  2. Day-parts (S-D10, S-D20).
--       days_of_week must be 0..6; two rows of the SAME kind for the same child
--       cannot overlap in effective dates, weekdays AND time of day (the engine
--       used to take whichever row Postgres returned first).
--  3. Time-zone names are validated against pg_timezone_names (S-D20): a bad
--       zone used to throw inside resolveWallClock and abort a whole scheduler
--       sweep for every family.
--  4. Enumerations (S-D20): delivery_intent.payload_kind / target_daypart and
--       intent_batch.daypart were free text.
-- ============================================================================

BEGIN;

-- ------------------------------------------------------------ 1. medication --
ALTER TABLE medication
  ADD COLUMN max_doses_per_24h integer
    CONSTRAINT medication_max_doses_sane CHECK (max_doses_per_24h BETWEEN 1 AND 24);

ALTER TABLE medication_dose
  ADD COLUMN recorded_at timestamptz,
  ADD COLUMN backdated   boolean NOT NULL DEFAULT false,
  ADD COLUMN is_prn      boolean NOT NULL DEFAULT false;

-- Existing rows were always written with administered_at = now(), so the moment
-- the server learned of them IS administered_at; none was back-dated.
UPDATE medication_dose SET recorded_at = administered_at;
UPDATE medication_dose d SET is_prn = m.is_prn
  FROM medication m WHERE m.id = d.medication_id;

ALTER TABLE medication_dose
  ALTER COLUMN recorded_at SET NOT NULL,
  ALTER COLUMN recorded_at SET DEFAULT now(),
  ADD CONSTRAINT medication_dose_backdating_audited CHECK (
    (backdated     AND administered_at <= recorded_at + interval '5 minutes') OR
    (NOT backdated AND administered_at  = recorded_at));

DROP INDEX medication_dose_no_double_given;
CREATE UNIQUE INDEX medication_dose_no_double_given
  ON medication_dose (medication_id, local_date, slot)
  WHERE status = 'given' AND NOT is_prn;

-- recordDose() reads the recent 'given' doses of one medication on both sides of
-- the candidate time for the PRN gap and the rolling-24h cap.
CREATE INDEX medication_dose_given_recent
  ON medication_dose (medication_id, administered_at DESC) WHERE status = 'given';

-- -------------------------------------------------------------- 2. day_part --
CREATE EXTENSION IF NOT EXISTS intarray;      -- trusted extension; gist__int_ops

ALTER TABLE day_part
  ADD CONSTRAINT day_part_days_valid CHECK (
    cardinality(days_of_week) BETWEEN 1 AND 7
    -- cast both sides: with intarray installed an smallint[] <@ smallint[]
    -- is an ambiguous operator.
    AND (days_of_week::int[]) <@ ARRAY[0,1,2,3,4,5,6]::int[]);

-- Same child + same kind + overlapping effective dates + overlapping weekdays +
-- overlapping time of day = ambiguous. A part that wraps midnight is modelled as
-- running to the same clock time the next day; start == end is an empty range.
ALTER TABLE day_part
  ADD CONSTRAINT day_part_no_overlap EXCLUDE USING gist (
    child_id WITH =,
    kind WITH =,
    effective WITH &&,
    ((days_of_week::int[])) gist__int_ops WITH &&,
    (tsrange(date '2000-01-01' + starts_local,
             date '2000-01-01' + ends_local
               + CASE WHEN ends_local < starts_local THEN interval '1 day'
                      ELSE interval '0' END)) WITH &&);

-- ------------------------------------------------------------- 3. time zones --
CREATE FUNCTION olive_valid_tz(tz text) RETURNS boolean
LANGUAGE sql STABLE PARALLEL SAFE AS
$$ SELECT EXISTS (SELECT 1 FROM pg_timezone_names WHERE name = tz) $$;

ALTER TABLE child
  ADD CONSTRAINT child_home_tz_valid CHECK (olive_valid_tz(home_tz));
ALTER TABLE custody_order
  ADD CONSTRAINT custody_order_tz_valid CHECK (olive_valid_tz(order_tz));
ALTER TABLE child_tz_interval
  ADD CONSTRAINT child_tz_interval_tz_valid CHECK (olive_valid_tz(tz));

-- ----------------------------------------------------------- 4. enumerations --
ALTER TABLE delivery_intent
  ADD CONSTRAINT delivery_intent_payload_kind_known CHECK (payload_kind IN
    ('video_msg','voice_note','drawing','homework','photo','call_clip','e2e_video','nudge')),
  ADD CONSTRAINT delivery_intent_target_daypart_known CHECK (target_daypart IS NULL OR
    target_daypart IN ('wake','before_school','school','after_school','activity',
                       'dinner','wind_down','bedtime','asleep','free'));
ALTER TABLE intent_batch
  ADD CONSTRAINT intent_batch_daypart_known CHECK (daypart IN
    ('wake','before_school','school','after_school','activity',
     'dinner','wind_down','bedtime','asleep','free'));

COMMIT;
