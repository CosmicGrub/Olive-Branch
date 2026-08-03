-- ============================================================================
--  OLIVE BRANCH — session context + isolation integration suite
--  Run after 0001, 0002, 0003. Must be run as a NON-SUPERUSER owner or it
--  measures nothing (see v0.4.1 finding).
-- ============================================================================
\pset pager off
\set QUIET on

-- ------------------------------------------------------------- fixtures -----
INSERT INTO app_user (id, display_name, home_tz) VALUES
  ('11111111-1111-1111-1111-111111111111','Dad','America/Chicago'),
  ('22222222-2222-2222-2222-222222222222','Mom','America/New_York')
ON CONFLICT DO NOTHING;

INSERT INTO child (id, display_name, birth_date, home_tz) VALUES
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Maya','2016-04-02','America/New_York'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','Eli','2019-09-11','America/New_York')
ON CONFLICT DO NOTHING;

-- Siblings. Dad guards Maya ONLY.
INSERT INTO sibling_link (child_a, child_b, kind) VALUES
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','full')
ON CONFLICT DO NOTHING;

-- REOPEN, do not insert. `UNIQUE (child_id, user_id)` means a closed edge
-- blocks a new one for the same pair, so ON CONFLICT DO NOTHING silently
-- leaves a dead edge in place if any earlier suite closed it. This is the
-- reunification pattern the v0.4.1 note predicted: restoring a previously
-- revoked parent reopens the existing row so their history cannot fork.
INSERT INTO guardianship (child_id, user_id, role, valid) VALUES
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','11111111-1111-1111-1111-111111111111',
   'guardian','[2020-01-01,)')
ON CONFLICT (child_id, user_id) DO UPDATE
  SET closed_at = NULL, closed_reason = NULL, restricted = false,
      expires_at = NULL, valid = '[2020-01-01,)';

-- An expired sitter and a restricted parent, both on Maya.
INSERT INTO guardianship (child_id, user_id, role, valid, expires_at) VALUES
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','22222222-2222-2222-2222-222222222222',
   'sitter','[2020-01-01,)', now() - interval '1 day')
ON CONFLICT DO NOTHING;

-- Idempotent fixtures. These two tables have no natural unique key, so a
-- re-run silently doubles the row counts and the assertions fail against
-- correct code. Clear first.
DELETE FROM child_journal_entry
 WHERE child_id IN ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
                    'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');
DELETE FROM media_artifact WHERE storage_key IN ('maya-1','eli-1');

INSERT INTO child_journal_entry (child_id, body) VALUES
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','maya private'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','eli private');

INSERT INTO media_artifact (child_id, kind, storage_key, captured_at, captured_tz, expires_at)
VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','video_msg','maya-1',now(),'America/New_York',now()+interval '90 days'),
       ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','video_msg','eli-1', now(),'America/New_York',now()+interval '90 days');

-- Non-superuser owner. Anything else measures nothing.
-- Idempotent: DROP ROLE fails if the role owns objects in ANY database, so
-- create-if-absent rather than drop-and-recreate. A test that cannot be re-run
-- is a test that gets skipped.
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_owner') THEN
    CREATE ROLE app_owner LOGIN NOSUPERUSER NOBYPASSRLS;
  END IF;
END $$;
GRANT USAGE ON SCHEMA public TO app_owner;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app_owner;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO app_owner;
ALTER TABLE child_journal_entry OWNER TO app_owner;


-- Explicit assertions. An earlier version printed raw values and relied on a
-- shell parser to interpret them; the parser miscounted and reported failures
-- against correct output. A suite whose result must be eyeballed is a suite
-- that gets misread.
CREATE OR REPLACE FUNCTION assert_eq(label text, got anyelement, want anyelement)
RETURNS void AS $$
BEGIN
  IF got::text IS NOT DISTINCT FROM want::text
    THEN RAISE NOTICE 'PASS  % (= %)', label, want;
    ELSE RAISE WARNING 'FAIL  % — want %, got %', label, want, got;
  END IF;
END $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION assert_raises(label text, stmt text) RETURNS void AS $$
BEGIN
  BEGIN EXECUTE stmt;
    RAISE WARNING 'FAIL  % — no exception raised', label;
  EXCEPTION WHEN others THEN RAISE NOTICE 'PASS  % — blocked (%)', label, SQLERRM;
  END;
END $$ LANGUAGE plpgsql;

GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO app_owner;
SET ROLE app_owner;

\echo ''
\echo '=== GUC HARDENING — the empty-string crash ==================='
SELECT set_config('app.role','child',false), set_config('app.child_id','',false);
SELECT assert_eq('empty app.child_id returns 0 rows, does not raise',
                 (SELECT count(*) FROM child_journal_entry), 0::bigint);
SELECT assert_eq('current_child() collapses empty to NULL',
                 current_child() IS NULL, true);
SELECT assert_eq('current_role_name() reads through',
                 current_role_name(), 'child');

\echo ''
\echo '=== P7 — journal isolation =================================='
SELECT set_config('app.child_id','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',false);
SELECT assert_eq('Maya sees exactly her own entry',
                 (SELECT count(*) FROM child_journal_entry WHERE body = 'maya private'), 1::bigint);
SELECT set_config('app.child_id','bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',false);
SELECT assert_eq('Eli sees only his own, not Maya''s',
                 (SELECT count(*) FROM child_journal_entry WHERE body = 'eli private'), 1::bigint);
SELECT assert_eq('Eli cannot read Maya''s row specifically',
                 (SELECT count(*) FROM child_journal_entry WHERE body = 'maya private'), 0::bigint);

SELECT set_config('app.role','guardian',false),
       set_config('app.user_id','11111111-1111-1111-1111-111111111111',false),
       set_config('app.child_id','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',false);
SELECT assert_eq('guardian as TABLE OWNER with full context sees nothing',
                 (SELECT count(*) FROM child_journal_entry), 0::bigint);

\echo ''
\echo '=== LATERAL PRIVILEGE — sibling traversal ===================='
SELECT assert_eq('Dad holds a live edge to Maya',
                 actor_has_edge('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'), true);
SELECT assert_eq('Dad does NOT reach sibling Eli despite sibling_link',
                 actor_has_edge('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), false);
-- Scoped to THIS suite's fixtures. A global count made the assertion depend on
-- whatever the constraint suite happened to leave behind — the third time this
-- defect has appeared. See CHANGELOG 0.6.0.
SELECT assert_eq('archive export is edge-scoped (Maya)',
                 (SELECT count(*) FROM exportable_artifacts('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa')
                   WHERE storage_key = 'maya-1'), 1::bigint);
SELECT assert_eq('archive export leaks nothing sideways (Eli)',
                 (SELECT count(*) FROM exportable_artifacts('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb')
                   WHERE storage_key = 'eli-1'), 0::bigint);

\echo ''
\echo '=== EDGE LIFECYCLE ==========================================='
SELECT set_config('app.user_id','22222222-2222-2222-2222-222222222222',false);
SELECT assert_eq('expired sitter token grants nothing',
                 actor_has_edge('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'), false);
SELECT assert_eq('expired edge excluded from effective_guardianship',
                 (SELECT count(*) FROM effective_guardianship
                   WHERE user_id='22222222-2222-2222-2222-222222222222'), 0::bigint);

\echo ''
\echo '=== P6 — child financial guard ==============================='
SELECT set_config('app.role','child',false);
SELECT assert_raises('child role blocked from financial surface',
                     'SELECT assert_no_child_financial_access()');
