-- ============================================================================
--  OLIVE BRANCH — media_artifact / intent_batch / delivery_intent RLS
--  (db/migrations/0023_message_media_delivery_rls.sql)
--
--  Same discipline db/test/0005_court.test.sql's own P6 section and
--  db/test/0003_session.test.sql already established for expense/
--  child_journal_entry: a RLS policy that is only ever exercised as
--  `postgres` (this whole file's default connection — see tools/verify.sh)
--  proves nothing, since a superuser bypasses row security unconditionally,
--  FORCE or not. Every assertion below runs under a real, connectable
--  NOSUPERUSER NOBYPASSRLS role. See db/DEPLOYMENT.md.
--
--  Idempotent and order-independent (this file's own standing rule, per
--  MASTERFILE §20.4's standing rules): reuses db/test/0003_session.test.sql's
--  own Maya/Eli/Dad/Mom fixtures BUT re-inserts them itself with
--  ON CONFLICT/reopen handling rather than assuming 0003 already ran, so
--  this file measures the same thing run alone, after 0003, or against a
--  dirty database.
-- ============================================================================
\pset pager off
\set QUIET on

-- ------------------------------------------------------------- fixtures -----
INSERT INTO app_user (id, display_name, home_tz) VALUES
  ('11111111-1111-1111-1111-111111111111','Dad','America/Chicago'),
  ('22222222-2222-2222-2222-222222222222','Mom','America/New_York'),
  ('33333333-3333-3333-3333-333333333333','StepMom','America/New_York'),
  ('44444444-4444-4444-4444-444444444444','CourtCoordinator','America/New_York')
ON CONFLICT DO NOTHING;

INSERT INTO child (id, display_name, birth_date, home_tz) VALUES
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Maya','2016-04-02','America/New_York'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','Eli','2019-09-11','America/New_York')
ON CONFLICT DO NOTHING;

-- Dad: LIVE guardian of Maya only — never touches Eli.
INSERT INTO guardianship (child_id, user_id, role, valid) VALUES
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','11111111-1111-1111-1111-111111111111',
   'guardian','[2020-01-01,)')
ON CONFLICT (child_id, user_id) DO UPDATE
  SET closed_at = NULL, closed_reason = NULL, restricted = false,
      expires_at = NULL, valid = '[2020-01-01,)', role = 'guardian';

-- Mom: an EXPIRED sitter edge to Eli — stricter than "no edge at all":
-- proves actor_has_edge() correctly treats a lapsed edge as no access, not
-- merely an absent one.
INSERT INTO guardianship (child_id, user_id, role, valid, expires_at) VALUES
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','22222222-2222-2222-2222-222222222222',
   'sitter','[2020-01-01,)', now() - interval '1 day')
ON CONFLICT (child_id, user_id) DO UPDATE
  SET closed_at = NULL, closed_reason = NULL, restricted = false,
      expires_at = now() - interval '1 day', valid = '[2020-01-01,)', role = 'sitter';

-- StepMom: LIVE step_parent edge to Maya — proves the policy's role list
-- generalizes beyond 'guardian' (0017/0018's own precedent hardcodes
-- 'guardian' because THOSE two tables really are guardian-only by product
-- design; media_artifact/delivery_intent are not — see 0023's own header).
INSERT INTO guardianship (child_id, user_id, role, valid) VALUES
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','33333333-3333-3333-3333-333333333333',
   'step_parent','[2020-01-01,)')
ON CONFLICT (child_id, user_id) DO UPDATE
  SET closed_at = NULL, closed_reason = NULL, restricted = false,
      expires_at = NULL, valid = '[2020-01-01,)', role = 'step_parent';

-- CourtCoordinator: LIVE edge to Maya, role='coordinator' — coordinator is
-- NOT in ROLE_CAPS['message'] (packages/family-graph/src/authorize.ts) and
-- must still see ZERO rows despite holding a real, live, unrestricted edge.
-- Proves the policy's role allowlist is doing real work, not merely
-- actor_has_edge() alone (which does not filter by role at all).
INSERT INTO guardianship (child_id, user_id, role, valid) VALUES
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','44444444-4444-4444-4444-444444444444',
   'coordinator','[2020-01-01,)')
ON CONFLICT (child_id, user_id) DO UPDATE
  SET closed_at = NULL, closed_reason = NULL, restricted = false,
      expires_at = NULL, valid = '[2020-01-01,)', role = 'coordinator';

-- Idempotent: this file's own rows, cleared and re-inserted every run rather
-- than relying on ON CONFLICT (none of these three tables have a natural
-- unique key suited to it).
DELETE FROM media_artifact WHERE storage_key IN ('maya-rls-1','eli-rls-1');
DELETE FROM delivery_intent WHERE id IN
  ('c0000000-0000-0000-0000-000000000c01','c0000000-0000-0000-0000-000000000c02');
DELETE FROM intent_batch WHERE id = 'c0000000-0000-0000-0000-000000000c03';

INSERT INTO media_artifact (child_id, kind, storage_key, captured_at, captured_tz, expires_at)
VALUES
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','photo','maya-rls-1',now(),'America/New_York',now()+interval '90 days'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','photo','eli-rls-1', now(),'America/New_York',now()+interval '90 days');

INSERT INTO intent_batch (id, child_id, sender_id, label, cadence, daypart, starts_local, ends_local)
VALUES ('c0000000-0000-0000-0000-000000000c03','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        '11111111-1111-1111-1111-111111111111','RLS test batch','daily','bedtime',
        current_date, current_date + 7);

INSERT INTO delivery_intent (id, child_id, sender_id, payload_kind, payload_ref, policy,
                              state, expires_at)
VALUES
  ('c0000000-0000-0000-0000-000000000c01','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
   '11111111-1111-1111-1111-111111111111','video_msg','d0000000-0000-0000-0000-0000000000d1',
   'immediate','pending', now()+interval '90 days'),
  ('c0000000-0000-0000-0000-000000000c02','bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
   '22222222-2222-2222-2222-222222222222','video_msg','d0000000-0000-0000-0000-0000000000d2',
   'immediate','pending', now()+interval '90 days');

-- Non-superuser owner. Anything else measures nothing — see this file's
-- own header.
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

\echo ''
\echo '=== SYSTEM role sees every family, every table ================'
SELECT set_config('app.role','system',false), set_config('app.user_id','',false),
       set_config('app.child_id','',false);
SELECT assert_eq('system sees both delivery_intent rows',
  (SELECT count(*) FROM delivery_intent
    WHERE id IN ('c0000000-0000-0000-0000-000000000c01','c0000000-0000-0000-0000-000000000c02')),
  2::bigint);
SELECT assert_eq('system sees both media_artifact rows',
  (SELECT count(*) FROM media_artifact WHERE storage_key IN ('maya-rls-1','eli-rls-1')),
  2::bigint);
SELECT assert_eq('system sees the intent_batch row',
  (SELECT count(*) FROM intent_batch WHERE id = 'c0000000-0000-0000-0000-000000000c03'),
  1::bigint);

\echo ''
\echo '=== CHILD role — own delivery_intent yes, cross-child no, media/batch zero ==='
SELECT set_config('app.role','child',false),
       set_config('app.child_id','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',false);
SELECT assert_eq('Maya (child role) sees her own delivery_intent row',
  (SELECT count(*) FROM delivery_intent WHERE id = 'c0000000-0000-0000-0000-000000000c01'),
  1::bigint);
SELECT assert_eq('Maya (child role) does NOT see Eli''s delivery_intent row',
  (SELECT count(*) FROM delivery_intent WHERE id = 'c0000000-0000-0000-0000-000000000c02'),
  0::bigint);
SELECT assert_eq('Maya (child role) sees ZERO media_artifact rows — even her own '
  || '(no call site ever opens a child session against this table; see 0023''s header)',
  (SELECT count(*) FROM media_artifact WHERE storage_key IN ('maya-rls-1','eli-rls-1')),
  0::bigint);
SELECT assert_eq('Maya (child role) sees ZERO intent_batch rows',
  (SELECT count(*) FROM intent_batch WHERE id = 'c0000000-0000-0000-0000-000000000c03'),
  0::bigint);

SELECT set_config('app.child_id','bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',false);
SELECT assert_eq('Eli (child role) sees his own delivery_intent row',
  (SELECT count(*) FROM delivery_intent WHERE id = 'c0000000-0000-0000-0000-000000000c02'),
  1::bigint);
SELECT assert_eq('Eli (child role) does NOT see Maya''s delivery_intent row',
  (SELECT count(*) FROM delivery_intent WHERE id = 'c0000000-0000-0000-0000-000000000c01'),
  0::bigint);

\echo ''
\echo '=== GUARDIAN with a live edge — sees that childs rows, all 3 tables ==='
SELECT set_config('app.role','guardian',false),
       set_config('app.user_id','11111111-1111-1111-1111-111111111111',false);
SELECT assert_eq('Dad (guardian, live edge to Maya) sees Maya''s delivery_intent row',
  (SELECT count(*) FROM delivery_intent WHERE id = 'c0000000-0000-0000-0000-000000000c01'),
  1::bigint);
SELECT assert_eq('Dad sees Maya''s media_artifact row',
  (SELECT count(*) FROM media_artifact WHERE storage_key = 'maya-rls-1'), 1::bigint);
SELECT assert_eq('Dad sees Maya''s intent_batch row',
  (SELECT count(*) FROM intent_batch WHERE id = 'c0000000-0000-0000-0000-000000000c03'),
  1::bigint);

\echo ''
\echo '=== GUARDIAN with NO edge to a different child — the core new protection ==='
SELECT assert_eq('Dad (no edge to Eli at all) sees ZERO of Eli''s delivery_intent rows — '
  || 'the actual new cross-family protection this migration adds (previously only an '
  || 'app-layer WHERE child_id=$1 stood between them)',
  (SELECT count(*) FROM delivery_intent WHERE id = 'c0000000-0000-0000-0000-000000000c02'),
  0::bigint);
SELECT assert_eq('Dad sees ZERO of Eli''s media_artifact rows',
  (SELECT count(*) FROM media_artifact WHERE storage_key = 'eli-rls-1'), 0::bigint);

\echo ''
\echo '=== GUARDIAN with an EXPIRED edge — stricter than no edge at all ==='
SELECT set_config('app.role','sitter',false),
       set_config('app.user_id','22222222-2222-2222-2222-222222222222',false);
SELECT assert_eq('Mom (sitter, EXPIRED edge to Eli, and sitter is not in the message-'
  || 'capability role list regardless) sees ZERO of Eli''s delivery_intent rows',
  (SELECT count(*) FROM delivery_intent WHERE id = 'c0000000-0000-0000-0000-000000000c02'),
  0::bigint);
SELECT assert_eq('Mom sees ZERO of Eli''s media_artifact rows',
  (SELECT count(*) FROM media_artifact WHERE storage_key = 'eli-rls-1'), 0::bigint);

\echo ''
\echo '=== STEP_PARENT with a live edge — the role-list generalization =============='
-- The exact case a naive copy of 0017/0018's hardcoded "= 'guardian'" would
-- have silently broken: a real, working step_parent inbox read.
SELECT set_config('app.role','step_parent',false),
       set_config('app.user_id','33333333-3333-3333-3333-333333333333',false);
SELECT assert_eq('StepMom (step_parent, live edge to Maya) sees Maya''s delivery_intent row',
  (SELECT count(*) FROM delivery_intent WHERE id = 'c0000000-0000-0000-0000-000000000c01'),
  1::bigint);
SELECT assert_eq('StepMom sees Maya''s media_artifact row',
  (SELECT count(*) FROM media_artifact WHERE storage_key = 'maya-rls-1'), 1::bigint);

\echo ''
\echo '=== COORDINATOR with a live edge — role list excludes it regardless of edge ==='
-- coordinator holds a REAL, live, unrestricted edge to Maya (fixture above)
-- but is not in ROLE_CAPS['message'] (authorize.ts) — must still see zero.
-- Proves the policy''s role allowlist is real, independent enforcement, not
-- a redundant echo of actor_has_edge() alone.
SELECT set_config('app.role','coordinator',false),
       set_config('app.user_id','44444444-4444-4444-4444-444444444444',false);
SELECT assert_eq('CourtCoordinator (live edge, wrong role) sees ZERO of Maya''s '
  || 'delivery_intent rows',
  (SELECT count(*) FROM delivery_intent WHERE id = 'c0000000-0000-0000-0000-000000000c01'),
  0::bigint);
SELECT assert_eq('CourtCoordinator sees ZERO of Maya''s media_artifact rows',
  (SELECT count(*) FROM media_artifact WHERE storage_key = 'maya-rls-1'), 0::bigint);
SELECT assert_eq('CourtCoordinator sees ZERO of Maya''s intent_batch row',
  (SELECT count(*) FROM intent_batch WHERE id = 'c0000000-0000-0000-0000-000000000c03'),
  0::bigint);

RESET ROLE;

\echo ''
\echo '=== SUPERUSER bypass — unaffected, same as every other FORCE-RLS table ======'
SELECT assert_eq('postgres (superuser, this file''s own default connection) still sees '
  || 'both delivery_intent rows regardless of any policy above',
  (SELECT count(*) FROM delivery_intent
    WHERE id IN ('c0000000-0000-0000-0000-000000000c01','c0000000-0000-0000-0000-000000000c02')),
  2::bigint);

-- Clean up this file's own media_artifact/delivery_intent/intent_batch rows
-- — unlike 0003_session.test.sql's own guardianship/child/app_user fixtures
-- (safely left in place, reused by design), these three tables have no
-- precedent of persistent fixtures anywhere else in this suite order, and
-- leaving them WAS a real, live-reproduced bug: packages/db/test/pool.test.mjs
-- (an unrelated, pre-existing suite, running later in verify.sh's own "DB
-- suites requiring a real NOSUPERUSER NOBYPASSRLS role" section) hardcodes
-- its OWN DAD/MOM as the identical raw UUIDs '11111111-...'/'22222222-...'
-- this file also uses (reused deliberately from 0003_session.test.sql's own
-- fixtures — see this file's own header) — and its setup-time
-- `DELETE FROM app_user WHERE id IN (...)` failed with a real FK violation
-- against this file's own leftover Eli delivery_intent row
-- (sender_id = '22222222-...'), a CI-only failure this exact fix closes.
-- The child/app_user/guardianship rows themselves are left alone, matching
-- 0003's own convention — nothing else in this suite order ever tries to
-- delete THOSE specific rows.
DELETE FROM delivery_intent WHERE id IN
  ('c0000000-0000-0000-0000-000000000c01','c0000000-0000-0000-0000-000000000c02');
DELETE FROM intent_batch WHERE id = 'c0000000-0000-0000-0000-000000000c03';
DELETE FROM media_artifact WHERE storage_key IN ('maya-rls-1','eli-rls-1');
