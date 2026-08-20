-- ============================================================================
--  OLIVE BRANCH — child-initiated take-and-go (export + majority handover)
--  MASTERFILE §2.10, §2.11, §9.8/§9.8.4, §21.2 rung 17, §21.7, prohibitions
--  P6/P7/P8.
--
--  packages/archive/src/archive.ts's `handover()` — real, tested
--  (packages/ledger/test/phase3.test.mjs's "P archive" section), UNWIRED to
--  any route or table until now — is the actual spec this migration exists
--  to make real: at the age of majority (`child.majority_age`, already a
--  real column since 0001_phase0_init.sql, default 18) she takes a full
--  export of her own data and every guardianship edge closes with reason
--  'majority' (also already a valid value in guardianship's own
--  closed_reason CHECK since 0001 — neither of those two facts needed a
--  schema change; both have been sitting ready, unused, since the very
--  first migration). The ONE real gap this migration closes: `export_record`
--  (0006_court_tier.sql) has `requested_by uuid NOT NULL REFERENCES
--  app_user(id)` — a child principal has no app_user row (readSession()'s own
--  invariant, packages/auth/src/auth.ts), so there was no honest id to write
--  there. server/routes.mjs's `GET .../export` route has said so explicitly,
--  in its own comment, since the day it shipped: "child-self export is not
--  implemented here... export_record.requested_by has no app_user row a
--  child principal could honestly be attributed to."
--
--  THE FIX, mirroring an EXISTING pattern in this exact schema rather than
--  inventing a new one: device_token (0012_push_device_token.sql) already
--  solved "a row may be owned by EITHER a user OR a child, never both" with
--  a pair of nullable owner columns plus a CHECK requiring exactly one.
--  export_record gets the identical shape.
--
--  RLS IS DELIBERATELY UNTOUCHED. export_record_no_child (0013) reads
--  `USING (current_role_name() IS DISTINCT FROM 'child')` — a session
--  running as the 'child' role can never read OR write this table, full
--  stop, no exception carved out here. packages/db/src/pool.ts's
--  takeAndGo() does not need one: like deactivateAccount() before it, it
--  runs its actual writes as 'system' (current_role_name() = 'system' is
--  "distinct from 'child'", so export_record_no_child already admits it)
--  ONLY AFTER the route layer has independently verified
--  (identityScopedByHandler, same posture as kiosk-pin/verify) that the
--  caller's own verified session really is this exact child. Loosening
--  export_record_no_child to admit 'child' directly would widen a policy
--  written, deliberately, to admit NO child session at all — the safer
--  change is the one every other identity-scoped-but-system-executed
--  mutation in this file already makes.
-- ============================================================================

BEGIN;

ALTER TABLE export_record
  ALTER COLUMN requested_by DROP NOT NULL;

ALTER TABLE export_record
  ADD COLUMN requested_by_child_id uuid REFERENCES child(id);

ALTER TABLE export_record
  ADD CONSTRAINT export_record_has_exactly_one_requester CHECK (
    (requested_by IS NOT NULL AND requested_by_child_id IS NULL) OR
    (requested_by IS NULL AND requested_by_child_id IS NOT NULL)
  );

CREATE INDEX ON export_record (requested_by_child_id) WHERE requested_by_child_id IS NOT NULL;

COMMENT ON COLUMN export_record.requested_by IS
  'The requesting GUARDIAN/coordinator, for a guardian-initiated export. '
  'Exactly one of requested_by / requested_by_child_id is set — see '
  'export_record_has_exactly_one_requester.';
COMMENT ON COLUMN export_record.requested_by_child_id IS
  'The child herself, for her own take-and-go export at majority '
  '(§21.2 rung 17, §9.8.4). Exactly one of requested_by / '
  'requested_by_child_id is set — see export_record_has_exactly_one_requester.';

COMMIT;
