-- ============================================================================
--  OLIVE BRANCH — 0044: health_check watches the catalog, not a hand-kept list
--  (data-model audit S-D21), and the expiry digest has somewhere to be recorded
--  (S-D2).
--
--  1. health_check's `rls_unforced` sub-check was a hard-coded list of table
--     names copied into the view definition by every migration that added a
--     table (and forgotten three times; see rls_coverage.test.mjs's history).
--     A new table with no policy was never flagged, and the core tables from
--     0001 (child, guardianship, day_part, ...) were in no list at all.
--     It now reads pg_class: ANY ordinary table in the public schema that does
--     not ENABLE and FORCE row-level security is a critical breach, unless it
--     is named in rls_allow_list with a reason.
--
--     rls_allow_list is seeded here with every table that lacks RLS TODAY, so
--     this migration introduces no new breach and other work that adds RLS to
--     more tables can land in either order: such a migration just deletes its
--     tables from the list (a table that gains RLS stops being flagged either
--     way; rls_coverage.test.mjs fails if a list entry is stale).
--  2. expense.currency + expense.split_bp (S-D19): basis points per participant
--     and an ISO-4217 currency, so the ledger engine's allocate() has something
--     to read. Existing rows: USD, and no split_bp (legacy payerSharePercent).
--  3. expiry_digest: the recorded output of the scheduler's `expiry-digest`
--     job (tools/scheduler.mjs). One row per child per distinct set of
--     about-to-expire artifacts. It stores ids, kinds and dates only — never a
--     caption — so it cannot keep text the retention reaper has deleted. It is
--     guardian-only (the digest is never shown to the child, §16.2 #5).
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------- the allow-list --
CREATE TABLE rls_allow_list (
  table_name text PRIMARY KEY,
  reason     text NOT NULL,
  added_at   timestamptz NOT NULL DEFAULT now()
);
COMMENT ON TABLE rls_allow_list IS
  'Public tables that deliberately (or not yet) lack ENABLE+FORCE row-level security. '
  'health_check.rls_unforced flags every public table missing RLS that is NOT named here. '
  'A migration that adds RLS to a table should DELETE its row.';

INSERT INTO rls_allow_list (table_name, reason)
SELECT c.relname,
       CASE c.relname
         WHEN 'schema_migration' THEN 'migration bookkeeping; holds checksums only, no personal data'
         WHEN 'rls_allow_list'   THEN 'this configuration table'
         ELSE 'no row-level security today (S-D21 inventory, 0044); add RLS and delete this row'
       END
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'public' AND c.relkind IN ('r', 'p')
   AND (c.relrowsecurity = false OR c.relforcerowsecurity = false);

-- ------------------------------------------------------------ expiry digest --
CREATE TABLE expiry_digest (
  id              uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  child_id        uuid NOT NULL REFERENCES child(id) ON DELETE CASCADE,
  generated_at    timestamptz NOT NULL DEFAULT now(),
  lead_days       integer NOT NULL CHECK (lead_days BETWEEN 1 AND 90),
  item_count      integer NOT NULL CHECK (item_count > 0),
  earliest_expiry timestamptz NOT NULL,
  latest_expiry   timestamptz NOT NULL,
  -- sha256 over the sorted (artifact id, expiry) pairs: the same set is
  -- recorded once, not once per nightly run.
  digest_key      text NOT NULL CHECK (digest_key ~ '^[0-9a-f]{64}$'),
  -- ids, kinds, expiry and days left. NEVER captions (they would outlive the
  -- artifact the reaper deletes).
  digest          jsonb NOT NULL,
  UNIQUE (child_id, digest_key),
  CHECK (latest_expiry >= earliest_expiry)
);
CREATE INDEX ON expiry_digest (child_id, generated_at DESC);

ALTER TABLE expiry_digest ENABLE ROW LEVEL SECURITY;
ALTER TABLE expiry_digest FORCE  ROW LEVEL SECURITY;
-- §16.2 #5: "a child is never shown this digest" -- invisible at every depth.
CREATE POLICY expiry_digest_no_child ON expiry_digest
  FOR ALL USING (current_role_name() IS DISTINCT FROM 'child');

-- ------------------------------------------- expense currency + participants --
-- S-D19. The stored split was a scalar ({"payerSharePercent": 60}): two parties
-- only, no currency. ledger.ts allocate() already works in basis points per
-- participant; the table now stores what the engine consumes.
--   currency  ISO-4217 code. Every existing row is USD (the only currency the
--             product has ever handled), so the default is also the backfill.
--   split_bp  {user_id: basis points}, whole numbers 0..10000 totalling 10000,
--             keyed by uuid. NULL on rows written before this migration, which
--             keep their legacy payerSharePercent (the other party is not
--             recorded on those rows, so a split cannot be invented for them).
CREATE FUNCTION olive_split_bp_ok(s jsonb) RETURNS boolean
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS
$$ SELECT jsonb_typeof(s) = 'object'
      AND (SELECT count(*) FROM jsonb_each(s)) BETWEEN 1 AND 12
      AND NOT EXISTS (SELECT 1 FROM jsonb_each(s) e(k, v)
                       WHERE jsonb_typeof(v) <> 'number' OR (v::text) !~ '^[0-9]{1,5}$'
                          OR k !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
      AND (SELECT sum((v::text)::int) FROM jsonb_each(s) e(k, v)) = 10000
      AND NOT EXISTS (SELECT 1 FROM jsonb_each(s) e(k, v) WHERE (v::text)::int > 10000) $$;

ALTER TABLE expense
  ADD COLUMN currency text NOT NULL DEFAULT 'USD'
    CONSTRAINT expense_currency_iso4217 CHECK (currency ~ '^[A-Z]{3}$'),
  ADD COLUMN split_bp jsonb
    CONSTRAINT expense_split_bp_valid CHECK (split_bp IS NULL OR olive_split_bp_ok(split_bp));

-- ---------------------------------------------- health_check, catalog-driven --
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
  -- S-D21: read from the catalog. Every public table must ENABLE and FORCE RLS
  -- or be named (with a reason) in rls_allow_list.
  SELECT 'rls_unforced','critical',count(*),0,
         'Public tables that do not ENABLE and FORCE row-level security and are not on rls_allow_list.'
    FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
   WHERE n.nspname='public' AND c.relkind IN ('r','p')
     AND (c.relrowsecurity=false OR c.relforcerowsecurity=false)
     AND NOT EXISTS (SELECT 1 FROM rls_allow_list a WHERE a.table_name = c.relname)
  UNION ALL
  SELECT 'log_sequence_gap','critical',count(*),0,
         'Parent log sequences are not contiguous. P8 has been circumvented.'
    FROM (SELECT child_id, seq, lag(seq) OVER (PARTITION BY child_id ORDER BY seq) prev
            FROM message_log) x
   WHERE prev IS NOT NULL AND seq <> prev + 1
) h;

COMMIT;
