-- ============================================================================
--  OLIVE BRANCH — 0043: court-evidence integrity (data-model audit S-D14,
--  S-D15).
--
--  "Chained, tamper-evident" was true of message_log's SHAPE only. This closes
--  the gaps the audit found, without breaking any existing chain:
--
--  1. message_log (S-D15)
--       - enforce_log_chain() now RECOMPUTES the hash (pgcrypto SHA-256, the
--         same length-prefixed framing as packages/ledger/src/ledger.ts
--         entryHash) instead of checking only its hex shape. A role that can
--         INSERT could previously append a linked but FORGED row; now the row's
--         hash must be the hash of the row.
--       - hash_version, so the framing can change one day without ambiguity.
--       - TRUNCATE is refused like UPDATE and DELETE.
--       - Before any of that, EVERY existing chain is verified (recomputed hash,
--         link, contiguous seq, genesis). A chain that does not verify FAILS THIS
--         MIGRATION, loudly, naming the child and seq: a database whose
--         evidence is already broken must be looked at by a person, not
--         silently blessed by a migration.
--  2. Expenses (S-D14)
--       - expense_event: append-only history of every status change, with the
--         ACTOR and the TIMESTAMP, and a CHECK that only legal transitions can
--         be recorded.
--       - A trigger on expense: only `status` may change; only from the legal
--         predecessor (proposed -> accepted|disputed, accepted -> reimbursed);
--         and the person who proposed an expense cannot accept or dispute it.
--  3. Exchange logs (S-D14): exchange_running_late_log and
--       exchange_arrival_event are append-only (no UPDATE, DELETE or TRUNCATE).
--
--  Append-only tables allow a DELETE only when it is a cascade from a parent
--  row being removed (pg_trigger_depth() > 1) — the account-deletion path — and
--  never a direct one. Test fixtures that need to clear them disable the
--  trigger explicitly, as court_export.test.mjs already does for message_log.
-- ============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;      -- trusted extension; digest()

-- ----------------------------------------------- hashing, same as the engine --
-- JavaScript's String.length counts UTF-16 code units; Postgres' char_length
-- counts code points. They differ for anything outside the Basic Multilingual
-- Plane (emoji), and the framing prefix is that length — so it must be the
-- UTF-16 length or a body with an emoji would never verify.
CREATE FUNCTION olive_utf16_length(s text) RETURNS integer
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS
$$ SELECT char_length(s) + (SELECT count(*)::int FROM regexp_matches(s, '[\U00010000-\U0010FFFF]', 'g')) $$;

CREATE FUNCTION olive_frame(s text) RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS
$$ SELECT olive_utf16_length(s)::text || ':' || s $$;

-- hash_version 1: sha256( f(seq) f(child_id) f(author_id) f(at) f(body) f(prev) )
-- where f(x) = len(x) ":" x and `at` is the UTC ISO-8601 instant with
-- millisecond precision and a Z, exactly as the writer's Date.toISOString().
CREATE FUNCTION message_log_hash_v1(
  p_seq bigint, p_child uuid, p_author uuid, p_at timestamptz, p_body text, p_prev text
) RETURNS text LANGUAGE sql IMMUTABLE PARALLEL SAFE AS
$$ SELECT encode(digest(
     olive_frame(p_seq::text) || olive_frame(p_child::text) || olive_frame(p_author::text) ||
     olive_frame(to_char(p_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')) ||
     olive_frame(p_body) || olive_frame(p_prev), 'sha256'), 'hex') $$;

-- ------------------------------------- verify every existing chain, or stop --
DO $verify$
DECLARE r record; bad text := '';
BEGIN
  FOR r IN
    SELECT child_id, seq, author_id, at, body, prev_hash, hash,
           lag(hash)  OVER w AS expected_prev,
           lag(seq)   OVER w AS prev_seq,
           row_number() OVER w AS rn
      FROM message_log
    WINDOW w AS (PARTITION BY child_id ORDER BY seq)
  LOOP
    IF message_log_hash_v1(r.seq, r.child_id, r.author_id, r.at, r.body, r.prev_hash) <> r.hash THEN
      bad := bad || format(E'\n  child %s seq %s: stored hash does not match the row', r.child_id, r.seq);
    END IF;
    IF r.rn = 1 AND (r.prev_hash <> repeat('0', 64) OR r.seq <> 0) THEN
      bad := bad || format(E'\n  child %s seq %s: chain does not start at genesis/seq 0', r.child_id, r.seq);
    END IF;
    IF r.rn > 1 AND r.prev_hash <> r.expected_prev THEN
      bad := bad || format(E'\n  child %s seq %s: does not link to the previous entry', r.child_id, r.seq);
    END IF;
    IF r.rn > 1 AND r.seq <> r.prev_seq + 1 THEN
      bad := bad || format(E'\n  child %s seq %s: sequence gap after %s', r.child_id, r.seq, r.prev_seq);
    END IF;
  END LOOP;
  IF bad <> '' THEN
    RAISE EXCEPTION E'0043 REFUSED: existing message_log chains do not verify.%\n'
      'This is court evidence that is already inconsistent. Investigate (export with '
      'a fault report from a restored backup) before migrating; do not edit rows to '
      'make this pass.', bad;
  END IF;
END
$verify$;

-- ---------------------------------------------------- message_log hardening --
ALTER TABLE message_log
  ADD COLUMN hash_version smallint NOT NULL DEFAULT 1,
  ADD CONSTRAINT message_log_hash_version_known CHECK (hash_version IN (1));

CREATE OR REPLACE FUNCTION enforce_log_chain() RETURNS trigger AS $$
DECLARE last_hash text; last_seq bigint; expected text;
BEGIN
  SELECT hash, seq INTO last_hash, last_seq
    FROM message_log WHERE child_id = NEW.child_id
   ORDER BY seq DESC LIMIT 1;

  IF last_hash IS NULL THEN
    IF NEW.prev_hash <> repeat('0', 64) THEN
      RAISE EXCEPTION 'first log entry must link to genesis';
    END IF;
    IF NEW.seq <> 0 THEN RAISE EXCEPTION 'first log entry must be seq 0'; END IF;
  ELSE
    IF NEW.prev_hash <> last_hash THEN
      RAISE EXCEPTION 'log entry does not link to the current head';
    END IF;
    IF NEW.seq <> last_seq + 1 THEN
      RAISE EXCEPTION 'log sequence must be contiguous (expected %)', last_seq + 1;
    END IF;
  END IF;

  -- S-D15: the hash must be the hash OF THIS ROW, not merely a well-formed one.
  IF NEW.hash_version = 1 THEN
    expected := message_log_hash_v1(NEW.seq, NEW.child_id, NEW.author_id, NEW.at, NEW.body, NEW.prev_hash);
    IF NEW.hash <> expected THEN
      RAISE EXCEPTION 'log entry hash does not match its content (hash_version 1)';
    END IF;
  END IF;
  RETURN NEW;
END $$ LANGUAGE plpgsql;

CREATE TRIGGER message_log_no_truncate BEFORE TRUNCATE ON message_log
  FOR EACH STATEMENT EXECUTE FUNCTION reject_log_mutation();

-- ---------------------------------------------- generic append-only helpers --
-- DELETE is refused unless it is a cascade from a parent row (depth > 1).
CREATE FUNCTION reject_evidence_update() RETURNS trigger AS $$
BEGIN
  RAISE EXCEPTION 'P8: % is append-only. UPDATE is not permitted.', TG_TABLE_NAME;
END $$ LANGUAGE plpgsql;

CREATE FUNCTION reject_evidence_delete() RETURNS trigger AS $$
BEGIN
  IF pg_trigger_depth() > 1 THEN RETURN OLD; END IF;   -- parent cascade only
  RAISE EXCEPTION 'P8: % is append-only. DELETE is not permitted.', TG_TABLE_NAME;
END $$ LANGUAGE plpgsql;

CREATE FUNCTION reject_evidence_truncate() RETURNS trigger AS $$
BEGIN
  RAISE EXCEPTION 'P8: % is append-only. TRUNCATE is not permitted.', TG_TABLE_NAME;
END $$ LANGUAGE plpgsql;

-- --------------------------------------------------------- exchange logs ------
CREATE TRIGGER exchange_running_late_log_no_update BEFORE UPDATE ON exchange_running_late_log
  FOR EACH ROW EXECUTE FUNCTION reject_evidence_update();
CREATE TRIGGER exchange_running_late_log_no_delete BEFORE DELETE ON exchange_running_late_log
  FOR EACH ROW EXECUTE FUNCTION reject_evidence_delete();
CREATE TRIGGER exchange_running_late_log_no_truncate BEFORE TRUNCATE ON exchange_running_late_log
  FOR EACH STATEMENT EXECUTE FUNCTION reject_evidence_truncate();

CREATE TRIGGER exchange_arrival_event_no_update BEFORE UPDATE ON exchange_arrival_event
  FOR EACH ROW EXECUTE FUNCTION reject_evidence_update();
CREATE TRIGGER exchange_arrival_event_no_delete BEFORE DELETE ON exchange_arrival_event
  FOR EACH ROW EXECUTE FUNCTION reject_evidence_delete();
CREATE TRIGGER exchange_arrival_event_no_truncate BEFORE TRUNCATE ON exchange_arrival_event
  FOR EACH STATEMENT EXECUTE FUNCTION reject_evidence_truncate();

-- ------------------------------------------------------------ expense_event --
CREATE TABLE expense_event (
  id          uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  expense_id  uuid NOT NULL REFERENCES expense(id) ON DELETE CASCADE,
  child_id    uuid NOT NULL REFERENCES child(id) ON DELETE CASCADE,
  seq         integer NOT NULL,
  from_status text,
  to_status   text NOT NULL,
  -- NULL only for a row reconstructed by this migration (the actor of a past
  -- change was never recorded) or a maintenance session with no user.
  actor_id    uuid REFERENCES app_user(id),
  at          timestamptz NOT NULL DEFAULT now(),
  backfilled  boolean NOT NULL DEFAULT false,
  UNIQUE (expense_id, seq),
  CONSTRAINT expense_event_transition CHECK (
    backfilled OR
    (from_status IS NULL     AND to_status = 'proposed') OR
    (from_status = 'proposed' AND to_status IN ('accepted', 'disputed')) OR
    (from_status = 'accepted' AND to_status = 'reimbursed'))
);
CREATE INDEX ON expense_event (child_id, at);

ALTER TABLE expense_event ENABLE ROW LEVEL SECURITY;
ALTER TABLE expense_event FORCE  ROW LEVEL SECURITY;
-- P6: a financial surface — invisible to the child role at every depth.
CREATE POLICY expense_event_no_child ON expense_event
  FOR ALL USING (current_role_name() IS DISTINCT FROM 'child');

CREATE TRIGGER expense_event_no_update BEFORE UPDATE ON expense_event
  FOR EACH ROW EXECUTE FUNCTION reject_evidence_update();
CREATE TRIGGER expense_event_no_delete BEFORE DELETE ON expense_event
  FOR EACH ROW EXECUTE FUNCTION reject_evidence_delete();
CREATE TRIGGER expense_event_no_truncate BEFORE TRUNCATE ON expense_event
  FOR EACH STATEMENT EXECUTE FUNCTION reject_evidence_truncate();

-- Reconstruct a history for every expense that already exists: one 'proposed'
-- event at creation (the proposer is paid_by) and, if it has moved on, one
-- backfilled event for its current status with an UNKNOWN actor.
INSERT INTO expense_event (expense_id, child_id, seq, from_status, to_status, actor_id, at, backfilled)
SELECT id, child_id, 1, NULL, 'proposed', paid_by, created_at, false FROM expense;
INSERT INTO expense_event (expense_id, child_id, seq, from_status, to_status, actor_id, at, backfilled)
SELECT id, child_id, 2, 'proposed', status, NULL, created_at, true FROM expense WHERE status <> 'proposed';

-- ----------------------------------------------------- expense transitions ---
CREATE FUNCTION expense_guard_update() RETURNS trigger AS $$
DECLARE actor uuid := current_actor();
BEGIN
  IF (to_jsonb(NEW) - 'status') IS DISTINCT FROM (to_jsonb(OLD) - 'status') THEN
    RAISE EXCEPTION 'expense_immutable: only the status of an expense may change';
  END IF;
  IF NEW.status = OLD.status THEN RETURN NEW; END IF;

  IF NOT ((OLD.status = 'proposed' AND NEW.status IN ('accepted', 'disputed'))
          OR (OLD.status = 'accepted' AND NEW.status = 'reimbursed')) THEN
    RAISE EXCEPTION 'expense_invalid_transition: % -> % is not allowed', OLD.status, NEW.status;
  END IF;
  IF actor IS NULL THEN
    RAISE EXCEPTION 'expense_actor_required: a status change must name who made it';
  END IF;
  IF NEW.status IN ('accepted', 'disputed') AND actor = OLD.paid_by THEN
    RAISE EXCEPTION 'expense_own_proposal: the person who proposed an expense cannot accept or dispute it';
  END IF;
  RETURN NEW;
END $$ LANGUAGE plpgsql;

CREATE TRIGGER expense_guard BEFORE UPDATE ON expense
  FOR EACH ROW EXECUTE FUNCTION expense_guard_update();

CREATE FUNCTION expense_record_event() RETURNS trigger AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    -- A row inserted already past 'proposed' (a fixture, an import) has no
    -- provable history: record it as what it is, a backfilled event.
    INSERT INTO expense_event (expense_id, child_id, seq, from_status, to_status, actor_id, backfilled)
    VALUES (NEW.id, NEW.child_id, 1, NULL, NEW.status, COALESCE(current_actor(), NEW.paid_by),
            NEW.status <> 'proposed');
  ELSIF NEW.status IS DISTINCT FROM OLD.status THEN
    INSERT INTO expense_event (expense_id, child_id, seq, from_status, to_status, actor_id)
    VALUES (NEW.id, NEW.child_id,
            (SELECT COALESCE(max(seq), 0) + 1 FROM expense_event WHERE expense_id = NEW.id),
            OLD.status, NEW.status, current_actor());
  END IF;
  RETURN NULL;
END $$ LANGUAGE plpgsql;

CREATE TRIGGER expense_event_ins AFTER INSERT ON expense
  FOR EACH ROW EXECUTE FUNCTION expense_record_event();
CREATE TRIGGER expense_event_upd AFTER UPDATE ON expense
  FOR EACH ROW EXECUTE FUNCTION expense_record_event();

COMMIT;
