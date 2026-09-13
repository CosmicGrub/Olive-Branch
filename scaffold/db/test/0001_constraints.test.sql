-- ============================================================================
--  OLIVE BRANCH — Phase 0 adversarial suite
--  Every guarantee in the migration gets attacked. A guarantee that cannot be
--  violated in this file is not proven, it is merely asserted.
-- ============================================================================
\set ON_ERROR_STOP off
\pset pager off
\set QUIET on

CREATE OR REPLACE FUNCTION must_fail(label text, stmt text) RETURNS void AS $$
BEGIN
  BEGIN
    EXECUTE stmt;
    RAISE WARNING 'FAIL  % — statement SUCCEEDED but must have been rejected', label;
  EXCEPTION WHEN others THEN
    RAISE NOTICE 'PASS  % — rejected (%)', label, SQLERRM;
  END;
END $$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION must_pass(label text, stmt text) RETURNS void AS $$
BEGIN
  BEGIN
    EXECUTE stmt;
    RAISE NOTICE 'PASS  % — accepted', label;
  EXCEPTION WHEN others THEN
    RAISE WARNING 'FAIL  % — rejected but should have been accepted (%)', label, SQLERRM;
  END;
END $$ LANGUAGE plpgsql;

-- ---------------------------------------------------------------- fixtures --
INSERT INTO app_user (id, display_name, home_tz) VALUES
  ('11111111-1111-1111-1111-111111111111','Dad','America/Chicago'),
  ('22222222-2222-2222-2222-222222222222','Mom','America/New_York'),
  ('33333333-3333-3333-3333-333333333333','Coordinator','America/New_York');

INSERT INTO child (id, display_name, birth_date, home_tz) VALUES
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Maya','2016-04-02','America/New_York'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','Eli','2019-09-11','America/New_York');

INSERT INTO guardianship (id, child_id, user_id, role, valid) VALUES
  ('dddddddd-dddd-dddd-dddd-dddddddddddd',
   'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
   '11111111-1111-1111-1111-111111111111','guardian','[2020-01-01,)');

\echo ''
\echo '=== §5.6  ARCHIVE RETENTION ==================================='

SELECT must_fail('retention_or_preserved: neither clock nor preservation', $q$
  INSERT INTO media_artifact (child_id, kind, storage_key, captured_at, captured_tz)
  VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','video_msg','k1',now(),'America/New_York')
$q$);

SELECT must_fail('preservation_is_attributed: preserved with no preserver', $q$
  INSERT INTO media_artifact (child_id, kind, storage_key, captured_at, captured_tz, preserved)
  VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','video_msg','k2',now(),'America/New_York',true)
$q$);

SELECT must_pass('artifact on a retention clock', $q$
  INSERT INTO media_artifact (child_id, kind, storage_key, captured_at, captured_tz, expires_at)
  VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','video_msg','k3',now(),'America/New_York',
          now() + interval '90 days')
$q$);

SELECT must_pass('artifact preserved and attributed', $q$
  INSERT INTO media_artifact (child_id, kind, storage_key, captured_at, captured_tz,
                              preserved, preserved_by, preserved_at)
  VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','video_msg','k4',now(),'America/New_York',
          true,'11111111-1111-1111-1111-111111111111',now())
$q$);

\echo ''
\echo '=== §5.2  TIMEZONE TIMELINE =================================='

SELECT must_pass('first tz interval', $q$
  INSERT INTO child_tz_interval (child_id, tz, valid, source)
  VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','America/New_York',
          '[2026-01-01,2026-06-12)','custody')
$q$);

SELECT must_fail('OVERLAPPING tz interval for the same child', $q$
  INSERT INTO child_tz_interval (child_id, tz, valid, source)
  VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','America/Chicago',
          '[2026-05-01,2026-08-01)','travel')
$q$);

SELECT must_pass('abutting tz interval (no overlap)', $q$
  INSERT INTO child_tz_interval (child_id, tz, valid, source)
  VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','America/Chicago',
          '[2026-06-12,2026-07-25)','custody')
$q$);

SELECT must_pass('same window, DIFFERENT child is fine', $q$
  INSERT INTO child_tz_interval (child_id, tz, valid, source)
  VALUES ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','America/Chicago',
          '[2026-05-01,2026-08-01)','travel')
$q$);

\echo ''
\echo '=== §5.15  CONTACT LADDER ==================================='

SELECT must_pass('ladder step', $q$
  INSERT INTO contact_ladder (guardianship_id, step, effective)
  VALUES ('dddddddd-dddd-dddd-dddd-dddddddddddd','supervised','[2026-01-01,2026-06-01)')
$q$);

SELECT must_fail('OVERLAPPING ladder steps', $q$
  INSERT INTO contact_ladder (guardianship_id, step, effective)
  VALUES ('dddddddd-dddd-dddd-dddd-dddddddddddd','open','[2026-03-01,2026-09-01)')
$q$);

SELECT must_fail('invalid ladder step name', $q$
  INSERT INTO contact_ladder (guardianship_id, step, effective)
  VALUES ('dddddddd-dddd-dddd-dddd-dddddddddddd','unsupervised','[2027-01-01,)')
$q$);

\echo ''
\echo '=== §5.14  SIBLINGS ========================================='

SELECT must_pass('sibling link in canonical order', $q$
  INSERT INTO sibling_link (child_a, child_b, kind)
  VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','full')
$q$);

SELECT must_fail('REVERSED duplicate sibling link', $q$
  INSERT INTO sibling_link (child_a, child_b, kind)
  VALUES ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','full')
$q$);

SELECT must_fail('child linked to itself', $q$
  INSERT INTO sibling_link (child_a, child_b, kind)
  VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','full')
$q$);

\echo ''
\echo '=== §18.1  GUARDIANSHIP CLOSURE ============================='

SELECT must_fail('closed_at with no reason', $q$
  UPDATE guardianship SET closed_at = now()
  WHERE id = 'dddddddd-dddd-dddd-dddd-dddddddddddd'
$q$);

SELECT must_pass('closure with a reason', $q$
  UPDATE guardianship SET closed_at = now(), closed_reason = 'death'
  WHERE id = 'dddddddd-dddd-dddd-dddd-dddddddddddd'
$q$);

SELECT must_fail('invalid closure reason', $q$
  UPDATE guardianship SET closed_reason = 'ghosted'
  WHERE id = 'dddddddd-dddd-dddd-dddd-dddddddddddd'
$q$);

\echo ''
\echo '=== §5.3  DELIVERY INTENT ==================================='

INSERT INTO intent_batch (id, child_id, sender_id, label, cadence, starts_local, ends_local)
VALUES ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee',
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','11111111-1111-1111-1111-111111111111',
        'Deployment','daily','2026-09-01','2027-02-28');

SELECT must_fail('at_daypart policy with NO target_daypart', $q$
  INSERT INTO delivery_intent (child_id, sender_id, payload_kind, payload_ref, policy, expires_at)
  VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','11111111-1111-1111-1111-111111111111',
          'video_msg', gen_random_uuid(),'at_daypart', now() + interval '30 days')
$q$);

SELECT must_fail('on_local_date policy with NO target_local_date', $q$
  INSERT INTO delivery_intent (child_id, sender_id, payload_kind, payload_ref, policy, expires_at)
  VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','11111111-1111-1111-1111-111111111111',
          'video_msg', gen_random_uuid(),'on_local_date', now() + interval '30 days')
$q$);

SELECT must_fail('COPPA: intent with NULL expires_at', $q$
  INSERT INTO delivery_intent (child_id, sender_id, payload_kind, payload_ref, policy,
                               target_daypart)
  VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','11111111-1111-1111-1111-111111111111',
          'video_msg', gen_random_uuid(),'at_daypart','bedtime')
$q$);

SELECT must_pass('valid at_daypart intent', $q$
  INSERT INTO delivery_intent (child_id, sender_id, payload_kind, payload_ref, policy,
                               target_daypart, expires_at)
  VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','11111111-1111-1111-1111-111111111111',
          'video_msg', gen_random_uuid(),'at_daypart','bedtime', now() + interval '30 days')
$q$);

SELECT must_pass('when_reachable needs no target', $q$
  INSERT INTO delivery_intent (child_id, sender_id, payload_kind, payload_ref, policy, expires_at)
  VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','11111111-1111-1111-1111-111111111111',
          'nudge', gen_random_uuid(),'when_reachable', now() + interval '2 days')
$q$);

-- The three branches above leave half the ENUM unattacked: at_instant,
-- on_event, and immediate had no dedicated probe here at all (scaffold/README.md's
-- own "Before Phase 0 ships" checklist named this real gap explicitly). The
-- CHECK constraint covers all six branches in the migration; this file did not.

SELECT must_fail('at_instant policy with NO target_instant', $q$
  INSERT INTO delivery_intent (child_id, sender_id, payload_kind, payload_ref, policy, expires_at)
  VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','11111111-1111-1111-1111-111111111111',
          'video_msg', gen_random_uuid(),'at_instant', now() + interval '30 days')
$q$);

SELECT must_pass('valid at_instant intent', $q$
  INSERT INTO delivery_intent (child_id, sender_id, payload_kind, payload_ref, policy,
                               target_instant, expires_at)
  VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','11111111-1111-1111-1111-111111111111',
          'video_msg', gen_random_uuid(),'at_instant', now() + interval '5 days',
          now() + interval '30 days')
$q$);

SELECT must_fail('on_event policy with NO target_event_id', $q$
  INSERT INTO delivery_intent (child_id, sender_id, payload_kind, payload_ref, policy, expires_at)
  VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','11111111-1111-1111-1111-111111111111',
          'video_msg', gen_random_uuid(),'on_event', now() + interval '30 days')
$q$);

SELECT must_pass('valid on_event intent', $q$
  INSERT INTO delivery_intent (child_id, sender_id, payload_kind, payload_ref, policy,
                               target_event_id, expires_at)
  VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','11111111-1111-1111-1111-111111111111',
          'video_msg', gen_random_uuid(),'on_event', gen_random_uuid(),
          now() + interval '30 days')
$q$);

SELECT must_pass('immediate needs no target', $q$
  INSERT INTO delivery_intent (child_id, sender_id, payload_kind, payload_ref, policy, expires_at)
  VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','11111111-1111-1111-1111-111111111111',
          'nudge', gen_random_uuid(),'immediate', now() + interval '2 days')
$q$);

SELECT must_fail('batch window ends before it starts', $q$
  INSERT INTO intent_batch (child_id, sender_id, label, cadence, starts_local, ends_local)
  VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','11111111-1111-1111-1111-111111111111',
          'Backwards','daily','2027-02-28','2026-09-01')
$q$);

\echo ''
\echo '=== §8.4  SMS BRIDGE ========================================'

SELECT must_fail('sms channel with no phone number', $q$
  INSERT INTO app_user (display_name, home_tz, channel)
  VALUES ('Incarcerated Parent','America/Chicago','sms')
$q$);

\echo ''
\echo '=== P7  THE PRIVATE JOURNAL ================================='

INSERT INTO child_journal_entry (child_id, body)
VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','i dont want to go this weekend');

-- Two roles, because they fail differently:
--   app_runtime — plain role, blocked by ENABLE alone
--   app_owner   — OWNS the table. Bypasses RLS unless FORCE is set. This is
--                 how most applications actually connect, and testing only
--                 app_runtime gives a false green.
-- NOTE: neither may be SUPERUSER or BYPASSRLS — those bypass even FORCE.
-- Running this probe as `postgres` measures nothing. See db/DEPLOYMENT.md.
DROP ROLE IF EXISTS app_runtime;
DROP ROLE IF EXISTS app_owner;
CREATE ROLE app_runtime LOGIN NOSUPERUSER NOBYPASSRLS;
CREATE ROLE app_owner   LOGIN NOSUPERUSER NOBYPASSRLS;
GRANT USAGE ON SCHEMA public TO app_runtime, app_owner;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app_runtime, app_owner;
ALTER TABLE child_journal_entry OWNER TO app_owner;

\echo '-- plain app role, claiming to be a GUARDIAN (expect 0):'
SET ROLE app_runtime;
SET app.role = 'guardian';
SET app.child_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
SELECT count(*) AS guardian_sees FROM child_journal_entry;

\echo '-- plain app role, claiming to be the CHILD (expect 1):'
SET app.role = 'child';
SELECT count(*) AS child_sees_own FROM child_journal_entry;

\echo '-- plain app role, claiming to be a DIFFERENT child (expect 0):'
SET app.child_id = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';
SELECT count(*) AS other_child_sees FROM child_journal_entry;
RESET ROLE;

\echo '-- TABLE OWNER claiming to be a guardian (expect 0 — needs FORCE):'
SET ROLE app_owner;
SET app.role = 'guardian';
SET app.child_id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
SELECT count(*) AS table_owner_sees FROM child_journal_entry;
RESET ROLE;
