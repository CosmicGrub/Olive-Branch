-- ============================================================================
-- 0045  Expense rules: a sole guardian may accept their own proposal, and a
--       disputed expense may still be accepted.            (owner, 2026-11-08)
--
--   (a) The person who proposed an expense still cannot accept or dispute it
--       when the child has two or more live guardians (the other one decides).
--       With exactly ONE live guardian there is nobody else to decide, so that
--       guardian may accept their own proposal. It is never silent: the
--       expense_event row carries self_accept = true, with the actor.
--       Disputing your own expense stays refused in every family.
--   (b) disputed -> accepted is a legal transition (the people talked it
--       through). The proposer rule above applies to it unchanged, and the
--       event is recorded like any other.
--   (c) reimbursing an expense that is not accepted is still refused.
--
-- Runs as the unprivileged migrator (app_owner): only ALTER TABLE on a table it
-- owns and CREATE OR REPLACE FUNCTION; no GUC is stored on a function.
-- ============================================================================
BEGIN;

ALTER TABLE expense_event ADD COLUMN self_accept boolean NOT NULL DEFAULT false;

ALTER TABLE expense_event DROP CONSTRAINT expense_event_transition;
ALTER TABLE expense_event ADD CONSTRAINT expense_event_transition CHECK (
  backfilled OR
  (from_status IS NULL      AND to_status = 'proposed') OR
  (from_status = 'proposed' AND to_status IN ('accepted', 'disputed')) OR
  (from_status = 'disputed' AND to_status = 'accepted') OR
  (from_status = 'accepted' AND to_status = 'reimbursed'));
ALTER TABLE expense_event ADD CONSTRAINT expense_event_self_accept_shape CHECK (
  NOT self_accept OR (to_status = 'accepted' AND from_status IN ('proposed', 'disputed')));

CREATE OR REPLACE FUNCTION expense_guard_update() RETURNS trigger AS $$
DECLARE
  actor uuid := current_actor();
  guardians integer;
BEGIN
  IF (to_jsonb(NEW) - 'status') IS DISTINCT FROM (to_jsonb(OLD) - 'status') THEN
    RAISE EXCEPTION 'expense_immutable: only the status of an expense may change';
  END IF;
  IF NEW.status = OLD.status THEN RETURN NEW; END IF;

  IF NOT ((OLD.status IN ('proposed', 'disputed') AND NEW.status = 'accepted')
          OR (OLD.status = 'proposed' AND NEW.status = 'disputed')
          OR (OLD.status = 'accepted' AND NEW.status = 'reimbursed')) THEN
    RAISE EXCEPTION 'expense_invalid_transition: % -> % is not allowed', OLD.status, NEW.status;
  END IF;
  IF actor IS NULL THEN
    RAISE EXCEPTION 'expense_actor_required: a status change must name who made it';
  END IF;
  IF NEW.status IN ('accepted', 'disputed') AND actor = OLD.paid_by THEN
    -- A sole guardian may accept their own proposal (recorded as self_accept by
    -- expense_record_event); nobody may dispute their own.
    SELECT count(*) INTO guardians FROM effective_guardianship g
     WHERE g.child_id = NEW.child_id AND g.role = 'guardian';
    IF NEW.status = 'disputed' OR guardians <> 1 THEN
      RAISE EXCEPTION 'expense_own_proposal: the person who proposed an expense cannot accept or dispute it';
    END IF;
  END IF;
  RETURN NEW;
END $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION expense_record_event() RETURNS trigger AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO expense_event (expense_id, child_id, seq, from_status, to_status, actor_id, backfilled)
    VALUES (NEW.id, NEW.child_id, 1, NULL, NEW.status, COALESCE(current_actor(), NEW.paid_by),
            NEW.status <> 'proposed');
  ELSIF NEW.status IS DISTINCT FROM OLD.status THEN
    INSERT INTO expense_event (expense_id, child_id, seq, from_status, to_status, actor_id, self_accept)
    VALUES (NEW.id, NEW.child_id,
            (SELECT COALESCE(max(seq), 0) + 1 FROM expense_event WHERE expense_id = NEW.id),
            OLD.status, NEW.status, current_actor(),
            NEW.status = 'accepted' AND current_actor() IS NOT DISTINCT FROM OLD.paid_by);
  END IF;
  RETURN NULL;
END $$ LANGUAGE plpgsql;

COMMIT;
