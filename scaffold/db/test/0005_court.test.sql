-- Court tier: P8 append-only enforcement, chain linking, P6 on expense.
\pset pager off
\set QUIET on
CREATE OR REPLACE FUNCTION must_fail(label text, stmt text) RETURNS void AS $$
BEGIN BEGIN EXECUTE stmt;
  RAISE WARNING 'FAIL  % — SUCCEEDED but must have been rejected', label;
EXCEPTION WHEN others THEN RAISE NOTICE 'PASS  % — rejected', label; END; END $$ LANGUAGE plpgsql;
CREATE OR REPLACE FUNCTION must_pass(label text, stmt text) RETURNS void AS $$
BEGIN BEGIN EXECUTE stmt; RAISE NOTICE 'PASS  % — accepted', label;
EXCEPTION WHEN others THEN RAISE WARNING 'FAIL  % — rejected (%)', label, SQLERRM; END; END $$ LANGUAGE plpgsql;

INSERT INTO app_user (id, display_name, home_tz) VALUES
  ('11111111-1111-1111-1111-111111111111','Dad','America/Chicago')
ON CONFLICT DO NOTHING;
INSERT INTO child (id, display_name, birth_date, home_tz) VALUES
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Maya','2016-04-02','America/New_York')
ON CONFLICT DO NOTHING;
DELETE FROM expense WHERE child_id='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';

\echo ''
\echo '=== P8 — the log is append-only ============================='
-- 0043 (S-D15): the trigger RECOMPUTES the hash, so a fixture must carry the
-- real one. message_log_hash_v1 is the SQL twin of packages/ledger entryHash().
SELECT must_fail('a genesis entry with a well-formed but WRONG hash is rejected (0043)', $q$
  INSERT INTO message_log (child_id, seq, author_id, at, body, prev_hash, hash)
  VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',0,'11111111-1111-1111-1111-111111111111','2026-01-01 00:00:00+00','first',
          repeat('0',64), repeat('a',64)) $q$);
SELECT must_pass('genesis entry accepted', $q$
  INSERT INTO message_log (child_id, seq, author_id, at, body, prev_hash, hash)
  VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',0,'11111111-1111-1111-1111-111111111111','2026-01-01 00:00:00+00','first', repeat('0',64),
          message_log_hash_v1(0,'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid,'11111111-1111-1111-1111-111111111111'::uuid,'2026-01-01 00:00:00+00','first',repeat('0',64))) $q$);
SELECT must_fail('a second genesis is rejected', $q$
  INSERT INTO message_log (child_id, seq, author_id, body, prev_hash, hash)
  VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',0,
          '11111111-1111-1111-1111-111111111111','again',
          repeat('0',64), repeat('b',64)) $q$);
SELECT must_fail('a linked entry whose body was changed after hashing is rejected (0043)', $q$
  INSERT INTO message_log (child_id, seq, author_id, at, body, prev_hash, hash)
  SELECT 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',1,'11111111-1111-1111-1111-111111111111','2026-01-02 00:00:00+00','second EDITED', h,
         message_log_hash_v1(1,'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid,'11111111-1111-1111-1111-111111111111'::uuid,'2026-01-02 00:00:00+00','second',h)
    FROM (SELECT hash AS h FROM message_log WHERE child_id='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' AND seq=0) x $q$);
SELECT must_pass('a linked entry is accepted', $q$
  INSERT INTO message_log (child_id, seq, author_id, at, body, prev_hash, hash)
  SELECT 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',1,'11111111-1111-1111-1111-111111111111','2026-01-02 00:00:00+00','second', h,
         message_log_hash_v1(1,'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid,'11111111-1111-1111-1111-111111111111'::uuid,'2026-01-02 00:00:00+00','second',h)
    FROM (SELECT hash AS h FROM message_log WHERE child_id='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' AND seq=0) x $q$);
SELECT must_fail('an unknown hash_version is rejected (0043)', $q$
  UPDATE message_log SET hash_version = 2 WHERE child_id='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' AND seq=0 $q$);
SELECT must_fail('TRUNCATE of the log is rejected (0043)', $q$ TRUNCATE message_log $q$);
SELECT must_fail('an entry that does not link to the head', $q$
  INSERT INTO message_log (child_id, seq, author_id, body, prev_hash, hash)
  VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',2,
          '11111111-1111-1111-1111-111111111111','forged',
          repeat('9',64), repeat('c',64)) $q$);
SELECT must_fail('a sequence gap', $q$
  INSERT INTO message_log (child_id, seq, author_id, body, prev_hash, hash)
  VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',7,
          '11111111-1111-1111-1111-111111111111','skip',
          repeat('b',64), repeat('d',64)) $q$);
SELECT must_fail('EDITING an entry (P8)', $q$
  UPDATE message_log SET body='rewritten'
   WHERE child_id='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' AND seq=0 $q$);
SELECT must_fail('DELETING an entry (P8)', $q$
  DELETE FROM message_log
   WHERE child_id='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' AND seq=0 $q$);
SELECT must_fail('a non-sha256 hash', $q$
  INSERT INTO message_log (child_id, seq, author_id, body, prev_hash, hash)
  VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',2,
          '11111111-1111-1111-1111-111111111111','x',
          repeat('b',64),'not-a-hash') $q$);

\echo ''
\echo '=== EXPENSE ================================================='
SELECT must_pass('a valid expense', $q$
  INSERT INTO expense (child_id, paid_by, description, amount_cents, category, incurred_on, split_rule)
  VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','11111111-1111-1111-1111-111111111111',
          'Orthodontist visit',4500,'medical',current_date,'{"dad":5000,"mom":5000}') $q$);
SELECT must_fail('a zero amount', $q$
  INSERT INTO expense (child_id, paid_by, amount_cents, category, incurred_on, split_rule)
  VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','11111111-1111-1111-1111-111111111111',
          0,'medical',current_date,'{}') $q$);
SELECT must_fail('an unknown category', $q$
  INSERT INTO expense (child_id, paid_by, amount_cents, category, incurred_on, split_rule)
  VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','11111111-1111-1111-1111-111111111111',
          100,'yacht',current_date,'{}') $q$);

\echo ''
\echo '=== P6 — the child role is DENIED a read, not just an INSERT ='
-- The three checks above only ever proved the CHECK constraints on INSERT.
-- P6's real backstop is 0006_court_tier.sql's `expense_no_child` RLS policy,
-- and nothing here had ever proven a session actually set to app.role =
-- 'child' is denied a SELECT — scaffold/README.md's own "Before Phase 0
-- ships" checklist named this real gap explicitly. Run as `postgres`
-- (this whole file's connection — see tools/verify.sh) that policy is never
-- even evaluated: superusers always bypass row security, FORCE or not. So,
-- matching db/test/0003_session.test.sql's own established pattern exactly,
-- this probe needs a real NOSUPERUSER NOBYPASSRLS role or it measures
-- nothing. See db/DEPLOYMENT.md.
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_owner') THEN
    CREATE ROLE app_owner LOGIN NOSUPERUSER NOBYPASSRLS;
  END IF;
END $$;
GRANT USAGE ON SCHEMA public TO app_owner;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app_owner;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO app_owner;

CREATE OR REPLACE FUNCTION assert_eq(label text, got anyelement, want anyelement)
RETURNS void AS $$
BEGIN
  IF got::text IS NOT DISTINCT FROM want::text
    THEN RAISE NOTICE 'PASS  % (= %)', label, want;
    ELSE RAISE WARNING 'FAIL  % — want %, got %', label, want, got;
  END IF;
END $$ LANGUAGE plpgsql;

SET ROLE app_owner;
SELECT set_config('app.role','child',false);
SELECT assert_eq('child role sees zero expense rows (expense_no_child RLS)',
                 (SELECT count(*) FROM expense
                   WHERE child_id='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), 0::bigint);
-- S-B4 (migration 0040): a guardian sees the row only through a LIVE edge to
-- THIS child. The edge is created as the superuser (guardianship is system-
-- write-only under FORCE RLS), then read back as app_owner.
RESET ROLE;
INSERT INTO guardianship (child_id, user_id, role, scope, valid)
VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','11111111-1111-1111-1111-111111111111','guardian','{}',
        tstzrange(now() - interval '1 year', null))
ON CONFLICT (child_id, user_id) DO UPDATE
  SET closed_at = NULL, closed_reason = NULL, restricted = false, expires_at = NULL,
      valid = tstzrange(now() - interval '1 year', null);
SET ROLE app_owner;
SELECT set_config('app.role','guardian',false);
SELECT set_config('app.user_id','11111111-1111-1111-1111-111111111111',false);
SELECT assert_eq('a guardian WITH a live edge still sees the row (RLS filters by edge, not an empty table)',
                 (SELECT count(*) FROM expense
                   WHERE child_id='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), 1::bigint);
SELECT set_config('app.user_id','99999999-9999-9999-9999-999999999999',false);
SELECT assert_eq('a guardian of ANOTHER family sees zero expense rows (edge-based isolation, S-B4)',
                 (SELECT count(*) FROM expense
                   WHERE child_id='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), 0::bigint);
SELECT set_config('app.role','system',false);
SELECT assert_eq('the system role still sees the row',
                 (SELECT count(*) FROM expense
                   WHERE child_id='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), 1::bigint);
RESET ROLE;
