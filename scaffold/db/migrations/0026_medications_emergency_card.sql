-- ============================================================================
--  OLIVE BRANCH — medication, medication_dose, medical_record
--
--  Real backend for the SECOND AND THIRD coordination-layer features closed
--  this pass (the handover log and expenses came first, v0.49.52/v0.49.53).
--  Found by this project's own coordination-layer audit (MASTERFILE §20.2b):
--  meds_care.dart (dosing log + a "shared medical record" section) and
--  emergency_card.dart (the compact, allergy-first offline card) have real,
--  tested client UI and — for the dosing side — a real, already-ported pure
--  TS engine (packages/care/src/care.ts's DoseKey/DoseRecord/recordDose/
--  prnAllowed) but NO table, route, or pool.ts function anywhere. Neither
--  screen has ever made a network call.
--
--  ONE canonical table backs both screens' shared data (allergies,
--  conditions, blood type — meds_care.dart's own "Shared medical record"
--  section — plus pediatrician/insurance, which only emergency_card.dart's
--  demo fixture shows) rather than two duplicating stores, matching this
--  project's own audit recommendation: "emergency_card's GET/PUT should
--  read from this same table, not duplicate it." "Guardians" (name + phone)
--  is NOT stored here at all — it is derived at read time from the real
--  guardianship + app_user.phone_e164 columns (0001_phase0_init.sql),
--  which already exist and are already the actual source of truth for who
--  a child's guardians are; duplicating that into medical_record would be
--  exactly the kind of second, driftable copy this schema elsewhere avoids
--  (see custody_order.side_a_guardian_id's own header, 0024, for the same
--  "don't invent a second source of truth" reasoning applied to a different
--  table).
--
--  RLS: `..._no_child` throughout, the identical `current_role_name() IS
--  DISTINCT FROM 'child'` shape `log_no_child`/`expense_no_child` already
--  use — MASTERFILE §9.6's own blanket "invisible to the child at every
--  depth" statement, same posture as every other guardian-only coordination
--  table this codebase has. The sitter role (an existing `guardianship.role`
--  value) is NOT `child`, so this same policy already admits her real,
--  narrower read (emergency_card.view + medication.view/log, per
--  authorize.ts's own ROLE_CAPS) — RLS is the child-exclusion backstop
--  here, not the fine-grained scoping; that's the route's own action gate's
--  job, same division of labor every other table in this migration series
--  already has.
-- ============================================================================

BEGIN;

CREATE TABLE medical_record (
  child_id              uuid PRIMARY KEY REFERENCES child(id) ON DELETE CASCADE,
  blood_type            text,
  allergies             jsonb NOT NULL DEFAULT '[]',
  conditions            jsonb NOT NULL DEFAULT '[]',
  pediatrician_name     text,
  pediatrician_practice text,
  pediatrician_phone    text,
  insurance_provider    text,
  insurance_member_id   text,
  updated_at            timestamptz NOT NULL DEFAULT now(),
  updated_by            uuid REFERENCES app_user(id)
);

ALTER TABLE medical_record ENABLE ROW LEVEL SECURITY;
ALTER TABLE medical_record FORCE  ROW LEVEL SECURITY;
CREATE POLICY medical_record_no_child ON medical_record
  FOR ALL USING (current_role_name() IS DISTINCT FROM 'child');

CREATE TABLE medication (
  id            uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  child_id      uuid NOT NULL REFERENCES child(id) ON DELETE CASCADE,
  name          text NOT NULL,
  dose          text NOT NULL,
  -- e.g. '["morning"]', '["morning","evening"]', '["prn"]' — meds_care.dart's
  -- own _Medication.slots list, verbatim.
  slots         jsonb NOT NULL DEFAULT '[]',
  is_prn        boolean NOT NULL DEFAULT false,
  min_gap_hours numeric,
  active        boolean NOT NULL DEFAULT true,
  created_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ON medication (child_id) WHERE active;

ALTER TABLE medication ENABLE ROW LEVEL SECURITY;
ALTER TABLE medication FORCE  ROW LEVEL SECURITY;
CREATE POLICY medication_no_child ON medication
  FOR ALL USING (current_role_name() IS DISTINCT FROM 'child');

CREATE TABLE medication_dose (
  id              uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  medication_id   uuid NOT NULL REFERENCES medication(id) ON DELETE CASCADE,
  -- Denormalized from medication.child_id, deliberately — every sibling
  -- table this migration/its siblings define scopes RLS and route lookups
  -- by child_id directly; requiring a join through `medication` just to
  -- answer "whose dose log is this" would be the odd one out.
  child_id        uuid NOT NULL REFERENCES child(id) ON DELETE CASCADE,
  -- Child-LOCAL date, per doseKey()'s own doc comment ("An 8am dose in one
  -- house and 'the morning dose' in the other are the same slot on the same
  -- child-local day") — computed server-side from child_tz_interval/
  -- home_tz, the same resolution every other child-local-time write in this
  -- codebase already uses, never trusted from the client.
  local_date      date NOT NULL,
  slot            text NOT NULL,
  administered_at timestamptz NOT NULL,
  by_user_id      uuid NOT NULL REFERENCES app_user(id),
  status          text NOT NULL CHECK (status IN ('given', 'skipped', 'refused', 'missed')),
  created_at      timestamptz NOT NULL DEFAULT now()
);
-- The real double-dose guard: recordDose()'s own pure-function collision
-- check (packages/care/src/care.ts, ported into meds_care.dart) becomes
-- this partial unique index server-side — only one 'given' dose per
-- medication/day/slot can ever exist, enforced by Postgres itself, not just
-- trusted from the app layer that queried first (a real TOCTOU risk two
-- guardians logging at the exchange, at the same moment, would otherwise
-- have).
CREATE UNIQUE INDEX medication_dose_no_double_given
  ON medication_dose (medication_id, local_date, slot) WHERE status = 'given';
CREATE INDEX ON medication_dose (medication_id, local_date DESC);

ALTER TABLE medication_dose ENABLE ROW LEVEL SECURITY;
ALTER TABLE medication_dose FORCE  ROW LEVEL SECURITY;
CREATE POLICY medication_dose_no_child ON medication_dose
  FOR ALL USING (current_role_name() IS DISTINCT FROM 'child');

COMMIT;
