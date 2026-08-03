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
SELECT must_pass('genesis entry accepted', $q$
  INSERT INTO message_log (child_id, seq, author_id, body, prev_hash, hash)
  VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',0,
          '11111111-1111-1111-1111-111111111111','first',
          repeat('0',64), repeat('a',64)) $q$);
SELECT must_fail('a second genesis is rejected', $q$
  INSERT INTO message_log (child_id, seq, author_id, body, prev_hash, hash)
  VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',0,
          '11111111-1111-1111-1111-111111111111','again',
          repeat('0',64), repeat('b',64)) $q$);
SELECT must_pass('a linked entry is accepted', $q$
  INSERT INTO message_log (child_id, seq, author_id, body, prev_hash, hash)
  VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',1,
          '11111111-1111-1111-1111-111111111111','second',
          repeat('a',64), repeat('b',64)) $q$);
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
  INSERT INTO expense (child_id, paid_by, amount_cents, category, incurred_on, split_rule)
  VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','11111111-1111-1111-1111-111111111111',
          4500,'medical',current_date,'{"dad":5000,"mom":5000}') $q$);
SELECT must_fail('a zero amount', $q$
  INSERT INTO expense (child_id, paid_by, amount_cents, category, incurred_on, split_rule)
  VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','11111111-1111-1111-1111-111111111111',
          0,'medical',current_date,'{}') $q$);
SELECT must_fail('an unknown category', $q$
  INSERT INTO expense (child_id, paid_by, amount_cents, category, incurred_on, split_rule)
  VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','11111111-1111-1111-1111-111111111111',
          100,'yacht',current_date,'{}') $q$);
