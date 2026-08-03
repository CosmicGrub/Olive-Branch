-- ============================================================================
--  OLIVE BRANCH — court tier
--  Tamper-evident parent↔parent log, expense ledger, export ledger.
--  MASTERFILE §12 Phase 3, §14, §16.1 #3. Prohibitions P6, P8.
-- ============================================================================

BEGIN;

-- ------------------------------------------------------- parent↔parent log --
-- P8: no deletion or editing, ever. Enforced by trigger, because a policy that
-- lives only in a code review is not a property. A log with an unsend button is
-- not evidence.
CREATE TABLE message_log (
  child_id   uuid NOT NULL REFERENCES child(id) ON DELETE RESTRICT,
  seq        bigint NOT NULL,
  author_id  uuid NOT NULL REFERENCES app_user(id) ON DELETE RESTRICT,
  at         timestamptz NOT NULL DEFAULT now(),
  body       text NOT NULL,
  prev_hash  text NOT NULL,
  hash       text NOT NULL,
  PRIMARY KEY (child_id, seq),
  CONSTRAINT hash_is_sha256 CHECK (hash ~ '^[0-9a-f]{64}$'),
  CONSTRAINT prev_is_sha256 CHECK (prev_hash ~ '^[0-9a-f]{64}$')
);
CREATE UNIQUE INDEX ON message_log (child_id, hash);

CREATE OR REPLACE FUNCTION reject_log_mutation() RETURNS trigger AS $$
BEGIN
  RAISE EXCEPTION
    'P8: the parent-to-parent log is append-only. % is not permitted.', TG_OP;
END $$ LANGUAGE plpgsql;

CREATE TRIGGER message_log_no_update BEFORE UPDATE ON message_log
  FOR EACH ROW EXECUTE FUNCTION reject_log_mutation();
CREATE TRIGGER message_log_no_delete BEFORE DELETE ON message_log
  FOR EACH ROW EXECUTE FUNCTION reject_log_mutation();

-- The chain must link. Enforced at write time so a broken chain cannot exist
-- in the table at all, rather than being discovered at export.
CREATE OR REPLACE FUNCTION enforce_log_chain() RETURNS trigger AS $$
DECLARE last_hash text; last_seq bigint;
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
  RETURN NEW;
END $$ LANGUAGE plpgsql;

CREATE TRIGGER message_log_chain BEFORE INSERT ON message_log
  FOR EACH ROW EXECUTE FUNCTION enforce_log_chain();

-- ---------------------------------------------------------- expense ledger --
CREATE TABLE expense (
  id           uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  child_id     uuid NOT NULL REFERENCES child(id) ON DELETE CASCADE,
  paid_by      uuid NOT NULL REFERENCES app_user(id),
  amount_cents bigint NOT NULL CHECK (amount_cents > 0),
  category     text NOT NULL CHECK (category IN
                 ('medical','school','activity','clothing','childcare','other')),
  incurred_on  date NOT NULL,
  receipt_key  text,
  split_rule   jsonb NOT NULL,
  status       text NOT NULL DEFAULT 'proposed'
               CHECK (status IN ('proposed','accepted','disputed','reimbursed')),
  created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ON expense (child_id, incurred_on);

-- PROHIBITION P6, ENFORCED. No SELECT policy exists for the child role and none
-- may be added. FORCE, because the table owner otherwise bypasses this entirely.
ALTER TABLE expense ENABLE ROW LEVEL SECURITY;
ALTER TABLE expense FORCE  ROW LEVEL SECURITY;
CREATE POLICY expense_no_child ON expense
  FOR ALL USING (current_role_name() IS DISTINCT FROM 'child');

-- The log is not child-facing either: it is the parents' channel.
ALTER TABLE message_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE message_log FORCE  ROW LEVEL SECURITY;
CREATE POLICY log_no_child ON message_log
  FOR ALL USING (current_role_name() IS DISTINCT FROM 'child');

-- ------------------------------------------------------------ export ledger --
-- §16.1 #3 — one free certified export per guardian per rolling 12 months.
CREATE TABLE export_record (
  id            uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  child_id      uuid NOT NULL REFERENCES child(id) ON DELETE CASCADE,
  requested_by  uuid NOT NULL REFERENCES app_user(id),
  kind          text NOT NULL CHECK (kind IN ('raw','certified')),
  was_free      boolean NOT NULL,
  head_hash     text,
  bundle_hash   text,
  created_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX ON export_record (requested_by, kind, created_at);

CREATE OR REPLACE FUNCTION certified_exports_last_year(p_user uuid, p_child uuid)
RETURNS integer AS $$
  SELECT count(*)::int FROM export_record
   WHERE requested_by = p_user AND child_id = p_child
     AND kind = 'certified' AND created_at > now() - interval '12 months';
$$ LANGUAGE sql STABLE;

-- Extend the health view with the court-tier invariants.
CREATE OR REPLACE VIEW health_check AS
SELECT * FROM (
  SELECT 'retention_breach'::text AS check_name, 'critical'::text AS severity,
         count(*)::bigint AS observed, 0::bigint AS threshold,
         'Media past its retention window still exists in storage.'::text AS meaning
    FROM retention_breach
  UNION ALL
  SELECT 'orphan_risk','high',count(*),0,
         'A queued message points at media that expires before delivery.' FROM orphan_risk
  UNION ALL
  SELECT 'stalled_delivery','high',count(*),0,'The sweep is not running.'
    FROM delivery_intent WHERE state='ready' AND scheduled_at < now() - interval '1 hour'
  UNION ALL
  SELECT 'unmaterialized','high',count(*),0,'Rematerialization is not running.'
    FROM delivery_intent WHERE state='pending' AND scheduled_at IS NULL
      AND created_at < now() - interval '1 hour'
  UNION ALL
  SELECT 'retention_invariant_broken','critical',count(*),0,
         'Artifacts with no clock and no preservation. The §5.6 CHECK is gone.'
    FROM media_artifact WHERE preserved=false AND expires_at IS NULL
  UNION ALL
  SELECT 'closure_without_reason','high',count(*),0,
         'Guardianship edges closed with no recorded reason.'
    FROM guardianship WHERE closed_at IS NOT NULL AND closed_reason IS NULL
  UNION ALL
  SELECT 'rls_unforced','critical',count(*),0,
         'Tables that must enforce RLS but do not FORCE it.'
    FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='public'
     AND c.relname IN ('child_journal_entry','pin_credential','expense','message_log')
     AND (c.relrowsecurity=false OR c.relforcerowsecurity=false)
  UNION ALL
  -- A log whose sequence has a gap means an append-only table was mutated.
  SELECT 'log_sequence_gap','critical',count(*),0,
         'Parent log sequences are not contiguous. P8 has been circumvented.'
    FROM (SELECT child_id, seq, lag(seq) OVER (PARTITION BY child_id ORDER BY seq) prev
            FROM message_log) x
   WHERE prev IS NOT NULL AND seq <> prev + 1
) h;

COMMIT;
