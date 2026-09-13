-- ============================================================================
--  OLIVE BRANCH — backup/restore round-trip fixture.
--
--  Run AFTER 0001-0021 (any complete migration set) and AFTER 0002_seed.sql
--  (reuses its app_user/child rows: Dad 11111111.../Maya aaaaaaaa...).
--  Companion driver: tools/backup-restore-verify.sh, which applies this file,
--  computes a per-table checksum, backs up, drops the database, restores, and
--  diffs the checksums to prove pg_dump/pg_restore actually round-trip real
--  data intact — not just that the two scripts run without error.
--
--  0002_seed.sql exercises the delivery/scheduling engine (500+ rows in one
--  table). This file deliberately exercises the OTHER shape of data this
--  product exists to protect — the handful of categories named directly in
--  MASTERFILE's data-loss concern: a hash-chained message log (the literal
--  court-export chain), a child's private journal, a custody order, an
--  export record, an expense, and a media artifact tagged 'homework'. A
--  backup strategy that only proves it can round-trip `delivery_intent` rows
--  hasn't proven anything about the tables an actual custody dispute would
--  turn on.
-- ============================================================================
\set QUIET on
\pset pager off

-- Second guardian (Mom), for a real two-guardian guardianship row.
INSERT INTO app_user (id, display_name, home_tz) VALUES
  ('22222222-2222-2222-2222-222222222222','Mom','America/New_York')
ON CONFLICT DO NOTHING;

INSERT INTO guardianship (id, child_id, user_id, role, scope, valid)
VALUES
  ('33333333-3333-3333-3333-333333333333',
   'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
   '11111111-1111-1111-1111-111111111111',
   'guardian', '{}'::jsonb, tstzrange('2020-01-01', null)),
  ('44444444-4444-4444-4444-444444444444',
   'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
   '22222222-2222-2222-2222-222222222222',
   'guardian', '{}'::jsonb, tstzrange('2020-01-01', null))
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------- custody order --------
INSERT INTO custody_order
  (id, child_id, order_tz, pattern, anchor_local_date, exchange_time,
   effective_from)
VALUES
  ('55555555-5555-5555-5555-555555555555',
   'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
   'America/New_York', 'week_on_week_off', '2026-01-02', '18:00',
   '2026-01-01')
ON CONFLICT DO NOTHING;

-- ------------------------------------------------- message log (§9.6) ------
-- A real hash chain — the same shape a certified court export walks. Genesis
-- links to 64 zeros; each subsequent prev_hash is the prior row's real hash.
-- Values below are sha256(prev_hash || '|' || body), computed once with
-- `openssl dgst -sha256` and pinned here — the DB trigger (enforce_log_chain,
-- 0006_court_tier.sql) validates the CHAIN links, not the hash's own
-- preimage, so this is a faithful stand-in for what packages/ledger computes
-- at send time.
INSERT INTO message_log (child_id, seq, author_id, body, prev_hash, hash)
VALUES
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 0,
   '11111111-1111-1111-1111-111111111111',
   'Hi honey, cant wait to see you Friday! Pack the blue jacket, its supposed to be cold.',
   repeat('0', 64),
   '4328dce946443ba14269611cae8f9cb43a192992053769ed6d90c57cce64de1a'),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 1,
   '22222222-2222-2222-2222-222222222222',
   'Miss you too Dad! Ivy has her piano recital Thursday at 6, Mom said you can come.',
   '4328dce946443ba14269611cae8f9cb43a192992053769ed6d90c57cce64de1a',
   'b55cb8d83bfda1959026430f01f6563a81f7169221c46bc21c4ae64b066417a4'),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 2,
   '11111111-1111-1111-1111-111111111111',
   'Wouldn''t miss it. Putting it on my calendar right now.',
   'b55cb8d83bfda1959026430f01f6563a81f7169221c46bc21c4ae64b066417a4',
   '8d19175f85734b5aaad66602acd602521993efccb6033f882742e6232ef75383')
ON CONFLICT DO NOTHING;

-- --------------------------------------------------------- media artifact --
INSERT INTO media_artifact
  (id, child_id, author_child_id, kind, storage_key, captured_at, captured_tz,
   preserved, preserved_by, preserved_at)
VALUES
  ('66666666-6666-6666-6666-666666666666',
   'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
   'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
   'homework', 'dev/homework/long-division-worksheet-4.jpg',
   now() - interval '2 days', 'America/New_York',
   true, '11111111-1111-1111-1111-111111111111', now())
ON CONFLICT DO NOTHING;

-- --------------------------------------------------------- child journal ---
-- RLS-restricted to the owning child role with deliberately no guardian
-- policy (MASTERFILE §9.9) — the app always writes this under a `child`
-- session context, so this fixture does the same rather than relying on a
-- superuser bypass that would mask a real RLS regression.
BEGIN;
SELECT set_config('app.role', 'child', true);
SELECT set_config('app.child_id', 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', true);
INSERT INTO child_journal_entry (id, child_id, body, media_ref)
VALUES
  ('77777777-7777-7777-7777-777777777777',
   'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
   'Today I finished my worksheet by myself and Dad said he was proud of me.',
   '66666666-6666-6666-6666-666666666666')
ON CONFLICT DO NOTHING;
COMMIT;

-- ------------------------------------------------------------ export record-
INSERT INTO export_record
  (id, child_id, requested_by, kind, was_free, head_hash, bundle_hash)
VALUES
  ('88888888-8888-8888-8888-888888888888',
   'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
   '11111111-1111-1111-1111-111111111111',
   'certified', false,
   '8d19175f85734b5aaad66602acd602521993efccb6033f882742e6232ef75383',
   '2b1a6a4f9d3e7c8b0a1f2e3d4c5b6a798877665544332211ffeeddccbbaa998')
ON CONFLICT DO NOTHING;

-- ----------------------------------------------------------------- expense-
INSERT INTO expense
  (id, child_id, paid_by, description, amount_cents, category, incurred_on, split_rule,
   status)
VALUES
  ('99999999-9999-9999-9999-999999999999',
   'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
   '22222222-2222-2222-2222-222222222222',
   'Backup fixture expense',
   6250, 'medical', '2026-08-10', '{"dad":50,"mom":50}'::jsonb, 'accepted')
ON CONFLICT DO NOTHING;
