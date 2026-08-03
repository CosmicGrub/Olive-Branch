-- ============================================================================
--  OLIVE BRANCH — sweep concurrency + invalidation integration suite
--  Run AFTER 0001 and 0002. Companion driver: db/test/run_concurrency.sh
-- ============================================================================
\set QUIET on
\pset pager off

-- ------------------------------------------------------------- fixtures -----
INSERT INTO app_user (id, display_name, home_tz) VALUES
  ('11111111-1111-1111-1111-111111111111','Dad','America/Chicago')
ON CONFLICT DO NOTHING;

INSERT INTO child (id, display_name, birth_date, home_tz) VALUES
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Maya','2016-04-02','America/New_York')
ON CONFLICT DO NOTHING;

INSERT INTO intent_batch (id, child_id, sender_id, label, reason, cadence,
                          starts_local, ends_local)
VALUES ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee',
        'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','11111111-1111-1111-1111-111111111111',
        'Deployment Mar-Sep','deployment','daily','2026-09-01','2027-02-28')
ON CONFLICT DO NOTHING;

-- Day-parts FIRST. Inserting them later would fire the invalidation
-- trigger and wipe the very queue this suite is meant to drain.
INSERT INTO day_part (child_id, kind, starts_local, ends_local, days_of_week,
                      reachable, effective)
VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','bedtime','20:30','21:00',
        '{0,1,2,3,4,5,6}', true, '[2026-01-01,2027-12-31)');

-- 500 intents already materialized and DUE. Enough contention to expose a
-- non-atomic claim.
INSERT INTO delivery_intent
  (child_id, sender_id, payload_kind, payload_ref, policy, target_local_date,
   target_daypart, batch_id, batch_seq, scheduled_at, materialized_tz,
   materialized_at, state, expires_at)
SELECT 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
       '11111111-1111-1111-1111-111111111111',
       'video_msg', gen_random_uuid(), 'on_local_date',
       (date '2026-09-01' + g), 'bedtime',
       'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', g,
       now() - interval '1 minute', 'America/New_York', now(),
       'ready', now() + interval '365 days'
  FROM generate_series(0, 499) g;

-- 50 intents scheduled in the FUTURE — must not be swept.
INSERT INTO delivery_intent
  (child_id, sender_id, payload_kind, payload_ref, policy, target_local_date,
   target_daypart, batch_id, batch_seq, scheduled_at, materialized_tz,
   materialized_at, state, expires_at)
SELECT 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
       '11111111-1111-1111-1111-111111111111',
       'video_msg', gen_random_uuid(), 'on_local_date',
       (date '2027-01-01' + g), 'bedtime',
       'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 1000 + g,
       now() + interval '30 days', 'America/New_York', now(),
       'ready', now() + interval '365 days'
  FROM generate_series(0, 49) g;

-- 10 intents whose retention window has already closed.
INSERT INTO delivery_intent
  (child_id, sender_id, payload_kind, payload_ref, policy, target_daypart,
   state, expires_at)
SELECT 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
       '11111111-1111-1111-1111-111111111111',
       'video_msg', gen_random_uuid(), 'at_daypart','bedtime',
       'pending', now() - interval '1 day'
  FROM generate_series(1, 10);

