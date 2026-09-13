-- ============================================================================
--  OLIVE BRANCH — custody_order.side_a_guardian_id / side_b_guardian_id
--
--  Prerequisite for GET /v1/children/:childId/presence (live parent
--  presence on ChildHome). Closes a real, previously undiscovered gap found
--  while designing that feature: schedule.ts's sideOn()/patternSideOn()
--  return an abstract Side ('A'|'B'), and NOTHING in this schema maps that
--  letter to a specific app_user.id — not custody_order itself (this table,
--  0007_custody_order.sql, before this migration), not guardianship (no
--  `side` column, 0001_phase0_init.sql), no join table anywhere. The one
--  place the client renders custody sides at all, family_agreement_screen
--  .dart, shows literal "Side A"/"Side B" labels, never resolved to a
--  guardian's name. So "exclude the on-duty guardian" — the presence
--  feature's own tie-break, MASTERFILE §5.27.4's "presence loses to
--  absence" applied here to a live status card rather than the come-back
--  signal it was written for — cannot be computed without this mapping
--  existing somewhere.
--
--  Both columns nullable, deliberately: a legacy custody_order row (every
--  row that existed before this migration) has no way to know which real
--  guardian held which letter, and GUESSING would be worse than an honest
--  NULL — presence.ts's own on-duty-exclusion step (packages/custody/src/
--  schedule.ts, server/routes.mjs's GET .../presence) treats a NULL side
--  guardian as "skip the exclusion, not guess it", the same honest-absence
--  discipline activeCustodyOrderFor()'s own doc comment already establishes
--  for "no order at all".
--
--  Population at custody-order CREATION time is explicitly out of scope
--  here — no creation route exists yet either (family_agreement_screen
--  .dart's own header: "no editing UI exists here, deliberately"). This
--  migration adds the columns a future creation route will fill in; it does
--  not invent that route.
-- ============================================================================

BEGIN;

ALTER TABLE custody_order
  ADD COLUMN side_a_guardian_id uuid REFERENCES app_user(id),
  ADD COLUMN side_b_guardian_id uuid REFERENCES app_user(id);

COMMIT;
