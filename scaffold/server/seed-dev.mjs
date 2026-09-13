#!/usr/bin/env node
// OLIVE BRANCH — dev seed data. Local development only, matches the demo
// constants already hardcoded in scaffold/client/lib/main.dart (childName:
// 'Ivy', ParentPresence('Dad', ...)) so the real backend and the Flutter
// client's existing placeholder data describe the same family.
import pg from 'pg';

const DATABASE_URL = process.env.DATABASE_URL;
if (!DATABASE_URL) { console.error('DATABASE_URL required'); process.exit(2); }

export const IVY = 'aaaaaaaa-0000-4000-8000-000000000001';
export const DAD = 'aaaaaaaa-0000-4000-8000-000000000002';
// Added alongside real device-testing infra for the coordination-layer
// features (handover notes and its siblings) — every one of those needs a
// SECOND live guardian to actually exercise guardian-to-guardian
// coordination (the "You" vs. real-name distinction, a real other party to
// post a note to). Sequential id, same convention DAD/IVY already use.
export const MOM = 'aaaaaaaa-0000-4000-8000-000000000003';

const client = new pg.Client({ connectionString: DATABASE_URL });
await client.connect();
await client.query('BEGIN');

await client.query(
  `INSERT INTO app_user (id, display_name, home_tz) VALUES ($1, 'Dad', 'America/Chicago')
   ON CONFLICT (id) DO NOTHING`, [DAD]);
await client.query(
  `INSERT INTO app_user (id, display_name, home_tz) VALUES ($1, 'Mom', 'America/Denver')
   ON CONFLICT (id) DO NOTHING`, [MOM]);
await client.query(
  `INSERT INTO child (id, display_name, birth_date, home_tz)
   VALUES ($1, 'Ivy', '2016-04-02', 'America/New_York')
   ON CONFLICT (id) DO NOTHING`, [IVY]);
await client.query(
  `INSERT INTO guardianship (child_id, user_id, role, scope, valid)
   VALUES ($1, $2, 'guardian', '{"calls":true,"message":true,"calendar.view":true}',
           tstzrange(now() - interval '1 year', null))
   ON CONFLICT (child_id, user_id) DO NOTHING`, [IVY, DAD]);
await client.query(
  `INSERT INTO guardianship (child_id, user_id, role, scope, valid)
   VALUES ($1, $2, 'guardian', '{"calls":true,"message":true,"calendar.view":true}',
           tstzrange(now() - interval '1 year', null))
   ON CONFLICT (child_id, user_id) DO NOTHING`, [IVY, MOM]);
await client.query(
  `INSERT INTO child_tz_interval (child_id, tz, valid, source)
   VALUES ($1, 'America/New_York', tstzrange(now() - interval '1 year', null), 'manual')
   ON CONFLICT DO NOTHING`, [IVY]);
// A real custody order for Ivy so GET /v1/children/:childId/now's
// sleepsUntilHandover is manually verifiable end to end, not just in
// packages/db/test/custody_order.test.mjs's fixture. Same shape as that
// suite's own order (2-2-3, anchored on a real Monday, 6pm Eastern
// exchanges), open-ended. custody_order.id is a generated uuid with no
// natural conflict target, so idempotency is a plain existence check rather
// than ON CONFLICT, matching this table's own EXCLUDE constraint (one active
// order per child per date range).
await client.query(
  `INSERT INTO custody_order
     (child_id, order_tz, pattern, anchor_local_date, exchange_time,
      holiday_rules, effective_from, effective_to)
   SELECT $1, 'America/New_York', '2-2-3', '2026-01-05', '18:00',
          '[]', '2024-01-01', null
    WHERE NOT EXISTS (SELECT 1 FROM custody_order WHERE child_id = $1)`,
  [IVY]);
const artifact = await client.query(
  `INSERT INTO media_artifact (id, child_id, author_id, kind, storage_key, captured_at, captured_tz, expires_at)
   VALUES (gen_random_uuid(), $1, $2, 'video_msg', 'dev/goodnight-1.mp4', now() - interval '2 hours',
           'America/Chicago', now() + interval '88 days')
   RETURNING id`, [IVY, DAD]);
await client.query(
  `INSERT INTO delivery_intent
     (id, child_id, sender_id, payload_kind, payload_ref, policy, state, materialized_at, expires_at)
   VALUES (gen_random_uuid(), $1, $2, 'video_msg', $3, 'immediate', 'delivered',
           now() - interval '1 hour', now() + interval '88 days')`,
  [IVY, DAD, artifact.rows[0].id]);

await client.query('COMMIT');
console.log(`seeded: child ${IVY} (Ivy), guardians ${DAD} (Dad) + ${MOM} (Mom), one delivered message`);
await client.end();
