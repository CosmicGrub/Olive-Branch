-- ============================================================================
--  OLIVE BRANCH — end-to-end async message chain
--  capture → artifact → intent → materialize → sweep → deliver → open → receipt
--
--  First suite that exercises every layer together. Run after 0001–0003.
--  Must run as a NOSUPERUSER NOBYPASSRLS role.
-- ============================================================================
\pset pager off
\set QUIET on

CREATE OR REPLACE FUNCTION assert_eq(label text, got anyelement, want anyelement)
RETURNS void AS $$
BEGIN
  IF got::text IS NOT DISTINCT FROM want::text
    THEN RAISE NOTICE 'PASS  % (= %)', label, want;
    ELSE RAISE WARNING 'FAIL  % — want %, got %', label, want, got;
  END IF;
END $$ LANGUAGE plpgsql;

-- ------------------------------------------------------------- fixtures -----
INSERT INTO app_user (id, display_name, home_tz) VALUES
  ('11111111-1111-1111-1111-111111111111','Dad','America/Chicago')
ON CONFLICT DO NOTHING;
INSERT INTO child (id, display_name, birth_date, home_tz) VALUES
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Maya','2016-04-02','America/New_York')
ON CONFLICT DO NOTHING;
-- Reopen rather than insert; a closed edge blocks the unique pair (v0.6.0 note).
INSERT INTO guardianship (child_id, user_id, role, valid) VALUES
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','11111111-1111-1111-1111-111111111111',
   'guardian','[2020-01-01,)')
ON CONFLICT (child_id, user_id) DO UPDATE
  SET closed_at=NULL, closed_reason=NULL, restricted=false, expires_at=NULL,
      valid='[2020-01-01,)';

DELETE FROM delivery_intent WHERE payload_kind='e2e_video';
DELETE FROM media_artifact  WHERE storage_key LIKE 'e2e/%';

\echo ''
\echo '=== 1 · CAPTURE — artifact under a retention clock ==========='

INSERT INTO media_artifact
  (id, child_id, author_id, kind, storage_key, duration_ms, captured_at,
   captured_tz, expires_at)
VALUES ('cccccccc-0000-0000-0000-000000000001',
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','11111111-1111-1111-1111-111111111111',
        'video_msg','e2e/goodnight-1', 42000, now(),'America/New_York',
        now() + interval '97 days');

SELECT assert_eq('artifact stored with a retention clock',
  (SELECT count(*) FROM media_artifact WHERE storage_key='e2e/goodnight-1'), 1::bigint);

\echo ''
\echo '=== 2 · SCHEDULE — intent bound to the artifact =============='

INSERT INTO delivery_intent
  (id, child_id, sender_id, payload_kind, payload_ref, policy,
   target_local_date, target_daypart, scheduled_at, materialized_tz,
   materialized_at, state, expires_at)
VALUES ('dddddddd-0000-0000-0000-000000000001',
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','11111111-1111-1111-1111-111111111111',
        'e2e_video','cccccccc-0000-0000-0000-000000000001','on_local_date',
        current_date, 'bedtime', now() - interval '1 minute','America/New_York',
        now(),'ready', now() + interval '90 days');

-- THE SEAM: the artifact must outlive the intent. Nothing in the schema relates
-- these two clocks; they are set by different concerns.
SELECT assert_eq('artifact outlives its intent (no orphaned delivery)',
  (SELECT m.expires_at > d.expires_at
     FROM media_artifact m
     JOIN delivery_intent d ON d.payload_ref = m.id
    WHERE d.id='dddddddd-0000-0000-0000-000000000001'), true);

\echo ''
\echo '=== 3 · SWEEP — exactly-once delivery ========================'

-- Limit must exceed anything another suite may have left queued. A limit of 50
-- silently missed this intent when 500 seed rows sat ahead of it.
SELECT assert_eq('claim delivers the due intent',
  (SELECT count(*) FROM claim_due_intents(100000)
    WHERE id='dddddddd-0000-0000-0000-000000000001'), 1::bigint);
SELECT assert_eq('state advanced to delivered',
  (SELECT state FROM delivery_intent WHERE id='dddddddd-0000-0000-0000-000000000001'),
  'delivered');
SELECT assert_eq('a second sweep does not re-deliver',
  (SELECT count(*) FROM claim_due_intents(100000)
    WHERE id='dddddddd-0000-0000-0000-000000000001'), 0::bigint);

\echo ''
\echo '=== 4 · OPEN — idempotent state transition ==================='

-- Compare-and-swap: only a delivered row may become opened, exactly once.
CREATE OR REPLACE FUNCTION mark_opened(p_intent uuid) RETURNS boolean AS $$
  WITH x AS (
    UPDATE delivery_intent SET state='opened'
     WHERE id = p_intent AND state = 'delivered'
    RETURNING 1
  ) SELECT EXISTS (SELECT 1 FROM x);
$$ LANGUAGE sql;

SELECT assert_eq('first open succeeds',
  mark_opened('dddddddd-0000-0000-0000-000000000001'), true);
SELECT assert_eq('second open is a no-op, not a duplicate receipt',
  mark_opened('dddddddd-0000-0000-0000-000000000001'), false);
SELECT assert_eq('state is opened',
  (SELECT state FROM delivery_intent WHERE id='dddddddd-0000-0000-0000-000000000001'),
  'opened');

\echo ''
\echo '=== 5 · RETENTION SHORTENS ON OPEN (§10.1) =================='

UPDATE media_artifact
   SET expires_at = LEAST(expires_at, now() + interval '30 days')
 WHERE id='cccccccc-0000-0000-0000-000000000001' AND preserved = false;

SELECT assert_eq('opened artifact retention shortened to ~30d',
  (SELECT expires_at < now() + interval '31 days'
     FROM media_artifact WHERE id='cccccccc-0000-0000-0000-000000000001'), true);
SELECT assert_eq('opening never lengthens retention',
  (SELECT expires_at < now() + interval '97 days'
     FROM media_artifact WHERE id='cccccccc-0000-0000-0000-000000000001'), true);

\echo ''
\echo '=== 6 · REVOCATION does not destroy a preserved artifact ====='

INSERT INTO media_artifact
  (id, child_id, author_id, kind, storage_key, duration_ms, captured_at,
   captured_tz, preserved, preserved_by, preserved_at)
VALUES ('cccccccc-0000-0000-0000-000000000002',
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','11111111-1111-1111-1111-111111111111',
        'video_msg','e2e/preserved-1', 38000, now(),'America/New_York',
        true,'11111111-1111-1111-1111-111111111111', now());

INSERT INTO delivery_intent
  (id, child_id, sender_id, payload_kind, payload_ref, policy,
   target_local_date, target_daypart, state, expires_at)
VALUES ('dddddddd-0000-0000-0000-000000000002',
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','11111111-1111-1111-1111-111111111111',
        'e2e_video','cccccccc-0000-0000-0000-000000000002','on_local_date',
        current_date + 30, 'bedtime','pending', now() + interval '60 days');

UPDATE delivery_intent SET state='revoked'
 WHERE id='dddddddd-0000-0000-0000-000000000002';

SELECT assert_eq('revoking an undelivered intent leaves the artifact intact',
  (SELECT count(*) FROM media_artifact WHERE storage_key='e2e/preserved-1'), 1::bigint);
SELECT assert_eq('preserved artifact still has no retention clock',
  (SELECT expires_at IS NULL FROM media_artifact
    WHERE storage_key='e2e/preserved-1'), true);
SELECT assert_eq('revoked intent is not re-swept',
  (SELECT count(*) FROM claim_due_intents(100000)
    WHERE id='dddddddd-0000-0000-0000-000000000002'), 0::bigint);

\echo ''
\echo '=== 7 · ORPHAN DETECTION ===================================='

-- `orphan_risk` is defined in migration 0005, not here. An earlier version
-- created it inside this test file, which meant the production monitoring
-- view existed only in databases where the test had been run. The migration
-- runner surfaced it on first use.

-- Scoped to this suite's artifacts. A global count depends on what every other
-- suite left behind — the same defect, four times now.
SELECT assert_eq('no orphan-risk rows in a healthy chain',
  (SELECT count(*) FROM orphan_risk o JOIN media_artifact m ON m.id=o.payload_ref
    WHERE m.storage_key LIKE 'e2e/%'), 0::bigint);

-- Prove the detector fires.
INSERT INTO media_artifact
  (id, child_id, author_id, kind, storage_key, duration_ms, captured_at,
   captured_tz, expires_at)
VALUES ('cccccccc-0000-0000-0000-000000000003',
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','11111111-1111-1111-1111-111111111111',
        'video_msg','e2e/short-clock', 5000, now(),'America/New_York',
        now() + interval '5 days');
INSERT INTO delivery_intent
  (id, child_id, sender_id, payload_kind, payload_ref, policy,
   target_local_date, target_daypart, state, expires_at)
VALUES ('dddddddd-0000-0000-0000-000000000003',
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','11111111-1111-1111-1111-111111111111',
        'e2e_video','cccccccc-0000-0000-0000-000000000003','on_local_date',
        current_date + 40, 'bedtime','pending', now() + interval '60 days');

SELECT assert_eq('detector catches an artifact that dies before delivery',
  (SELECT count(*) FROM orphan_risk o JOIN media_artifact m ON m.id=o.payload_ref
    WHERE m.storage_key LIKE 'e2e/%'), 1::bigint);

DELETE FROM delivery_intent WHERE id='dddddddd-0000-0000-0000-000000000003';
DELETE FROM media_artifact  WHERE id='cccccccc-0000-0000-0000-000000000003';

SELECT assert_eq('chain healthy again after cleanup',
  (SELECT count(*) FROM orphan_risk o JOIN media_artifact m ON m.id=o.payload_ref
    WHERE m.storage_key LIKE 'e2e/%'), 0::bigint);
