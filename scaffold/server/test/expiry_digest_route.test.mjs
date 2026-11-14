/**
 * server/routes.mjs -- GET /v1/children/:childId/expiry-digests, the guardian's
 * quiet reader for the scheduler's expiry-digest records (migration 0044).
 *
 * Real Postgres, real RLS (DATABASE_URL = the unprivileged app_owner role,
 * ADMIN_DATABASE_URL = superuser for fixtures), real Api instance.
 *
 * Proves:
 *   (a) a guardian with an edge to the child reads her digests, newest first.
 *   (b) only ids, kinds and dates come back: no caption key, no capturedAt.
 *   (c) a digest whose last expiry has already passed is not sent.
 *   (d) a child session is refused (403 not_a_child_surface): section 16.2 #5.
 *   (e) a guardian with no edge to this child is refused, and sees nothing of hers.
 *   (f) no session at all is refused.
 */
import pg from 'pg';
import { Api } from '../../packages/api/src/api.mjs';
import { createPool, dbPort } from '../../packages/db/src/pool.mjs';
import { registerRoutes } from '../routes.mjs';
import { issueSession } from '../../packages/auth/src/auth.mjs';

const DATABASE_URL = process.env.DATABASE_URL;
const ADMIN_DATABASE_URL = process.env.ADMIN_DATABASE_URL ?? DATABASE_URL;
if (!DATABASE_URL) {
  console.error('DATABASE_URL required -- this suite needs a real Postgres, not a fake.');
  process.exit(2);
}

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) }); };

const pool = createPool(DATABASE_URL);
const admin = new pg.Client({ connectionString: ADMIN_DATABASE_URL });
await admin.connect();

const DAD = '11111111-1111-4111-9111-0000000000d1';
const STRANGER = '33333333-3333-4333-9333-0000000000d1';
const CHILD = '55555555-5555-4555-9555-0000000000d1';
const OTHER_CHILD = '66666666-6666-4666-9666-0000000000d1';

async function cleanup() {
  await admin.query(`DELETE FROM expiry_digest WHERE child_id = ANY($1::uuid[])`, [[CHILD, OTHER_CHILD]]);
  await admin.query(`DELETE FROM guardianship WHERE child_id = ANY($1::uuid[])`, [[CHILD, OTHER_CHILD]]);
  await admin.query(`DELETE FROM child WHERE id = ANY($1::uuid[])`, [[CHILD, OTHER_CHILD]]);
  await admin.query(`DELETE FROM app_user WHERE id = ANY($1::uuid[])`, [[DAD, STRANGER]]);
}
await cleanup();

await admin.query(`INSERT INTO app_user (id, display_name, home_tz) VALUES
  ($1,'Dad','America/Chicago'), ($2,'Stranger','America/New_York')`, [DAD, STRANGER]);
await admin.query(`INSERT INTO child (id, display_name, birth_date, home_tz) VALUES
  ($1,'Ivy','2016-04-02','America/Los_Angeles'), ($2,'Other','2016-04-02','America/Los_Angeles')`,
  [CHILD, OTHER_CHILD]);
await admin.query(`INSERT INTO guardianship (child_id, user_id, role, scope, valid) VALUES
  ($1, $2, 'guardian', '{}', tstzrange(now() - interval '1 year', null))`, [CHILD, DAD]);

const day = 24 * 3600 * 1000;
const iso = (ms) => new Date(ms).toISOString();
const t0 = Date.now();
async function addDigest(childId, keyChar, generatedAgoMs, items) {
  const times = items.map((i) => Date.parse(i.expiresAt));
  await admin.query(
    `INSERT INTO expiry_digest (child_id, generated_at, lead_days, item_count, earliest_expiry, latest_expiry, digest_key, digest)
     VALUES ($1, $2::timestamptz, 14, $3, $4::timestamptz, $5::timestamptz, $6, $7::jsonb)`,
    [childId, iso(t0 - generatedAgoMs), items.length, iso(Math.min(...times)), iso(Math.max(...times)),
     keyChar.repeat(64), JSON.stringify({ items, byKind: [], headline: 'x', audience: 'guardian' })]);
}
const older = [{ artifactId: 'a-1', kind: 'call_clip', caption: null, capturedAt: iso(t0 - 20 * day), expiresAt: iso(t0 + 3 * day), daysLeft: 3 }];
const newer = [
  { artifactId: 'a-1', kind: 'call_clip', caption: null, capturedAt: iso(t0 - 20 * day), expiresAt: iso(t0 + 3 * day), daysLeft: 3 },
  { artifactId: 'a-2', kind: 'screen_frame', caption: null, capturedAt: iso(t0 - 25 * day), expiresAt: iso(t0 + 9 * day), daysLeft: 9 },
];
const gone = [{ artifactId: 'a-0', kind: 'session_media', caption: null, capturedAt: iso(t0 - 40 * day), expiresAt: iso(t0 - 1 * day), daysLeft: 1 }];
await addDigest(CHILD, 'a', 2 * day, older);
await addDigest(CHILD, 'b', 1 * day, newer);
await addDigest(CHILD, 'c', 3 * day, gone);
await addDigest(OTHER_CHILD, 'd', 1 * day, older);

const SECRET = Buffer.from('e'.repeat(32), 'utf8');
const api = new Api(SECRET, dbPort(pool), () => t0);
registerRoutes(api, pool);
const tok = (p) => issueSession(SECRET, p, t0);
const dadTok = tok({ userId: DAD, roleName: 'guardian', childId: null, escalated: false });
const strangerTok = tok({ userId: STRANGER, roleName: 'guardian', childId: null, escalated: false });
const childTok = tok({ userId: null, roleName: 'child', childId: CHILD, escalated: false });
const get = (childId, t) => api.handle('GET', `/v1/children/${childId}/expiry-digests`,
  t ? { authorization: `Bearer ${t}` } : {}, '');

{
  const r = await get(CHILD, dadTok);
  check('A guardian', 'authorized guardian -> 200', r.status, 200);
  check('A guardian', 'two live digests (the expired set is not sent)', r.body.digests.length, 2);
  check('A guardian', 'newest first', r.body.digests[0].items.length, 2);
  check('A guardian', 'the older digest follows', r.body.digests[1].items.length, 1);
  check('A guardian', 'item ids and kinds round-trip',
    r.body.digests[0].items.map((i) => `${i.artifactId}:${i.kind}`).join(','), 'a-1:call_clip,a-2:screen_frame');
  const wire = JSON.stringify(r.body);
  check('B shape', 'no caption key on the wire', wire.includes('caption'), false);
  check('B shape', 'no capturedAt on the wire', wire.includes('capturedAt'), false);
  check('B shape', 'item keys are exactly artifactId, kind, expiresAt',
    Object.keys(r.body.digests[0].items[0]).sort().join(','), 'artifactId,expiresAt,kind');
  check('B shape', 'the expired set is absent', wire.includes('a-0'), false);
}
{
  const r = await get(CHILD, childTok);
  check('D child', 'a child session is refused', r.status, 403);
  check('D child', 'with the named reason', r.body.error, 'not_a_child_surface');
  check('D child', 'and nothing of the digest leaks into the refusal', JSON.stringify(r.body).includes('a-1'), false);
}
{
  const r = await get(CHILD, strangerTok);
  check('E stranger', 'a guardian with no edge to this child is refused', r.status, 403);
  check('E stranger', 'and gets no digests', r.body.digests === undefined, true);
  const mine = await get(OTHER_CHILD, dadTok);
  check('E stranger', 'dad has no edge to the other child either', mine.status, 403);
}
{
  const r = await get(CHILD, null);
  check('F anonymous', 'no session -> 401', r.status, 401);
}

await cleanup();
await admin.end();
await pool.end();

let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
