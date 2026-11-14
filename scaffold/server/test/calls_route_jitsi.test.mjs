/**
 * server/routes.mjs — the call routes under CALL_PROVIDER=jitsi (the default)
 * and, side by side, under livekit. MASTERFILE §16.2 #6 (third reversal).
 *
 * What this proves: authorization is IDENTICAL for both providers (same
 * refusals, same reasons), only the grant differs; the Jitsi grant is a real
 * per-participant HS256 JWT scoped to one derived room; an unconfigured Jitsi
 * is reported (503) BEFORE any session exists or any device is rung; no secret
 * ever appears in a response. Real Postgres through the real Api, the same
 * pattern as calls_route.test.mjs.
 */
import { createHmac, timingSafeEqual } from 'node:crypto';
import pg from 'pg';
import { Api } from '../../packages/api/src/api.mjs';
import { createPool, dbPort } from '../../packages/db/src/pool.mjs';
import { registerRoutes } from '../routes.mjs';
import { issueSession } from '../../packages/auth/src/auth.mjs';

const DATABASE_URL = process.env.DATABASE_URL;
const ADMIN_DATABASE_URL = process.env.ADMIN_DATABASE_URL ?? DATABASE_URL;
if (!DATABASE_URL) { console.error('DATABASE_URL required — this suite needs a real Postgres, not a fake.'); process.exit(2); }

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) }); };

const pool = createPool(DATABASE_URL);
const admin = new pg.Client({ connectionString: ADMIN_DATABASE_URL });
await admin.connect();

const CHILD = 'e1e1e1e1-1234-1234-1234-eeeeeeeeeee1';
const CHILD_B = 'e1e1e1e1-2222-1234-1234-333333333332';   // DAD has no edge
const CHILD_D = 'e1e1e1e1-4444-1234-1234-555555555534';   // DAD observer-only
const DAD = 'f1f1f1f1-1234-1234-1234-fffffffffff1';
const MOM = 'c1c1c1c1-1234-1234-1234-ccccccccccc1';
const CHILDREN = [CHILD, CHILD_B, CHILD_D];

const cleanup = async () => {
  await admin.query(`DELETE FROM call_log WHERE child_id = ANY($1)`, [CHILDREN]);
  await admin.query(`DELETE FROM device_token WHERE owner_child_id = ANY($1)`, [CHILDREN]);
  for (const cid of CHILDREN) {
    await admin.query(`DELETE FROM guardianship WHERE child_id = $1`, [cid]);
    await admin.query(`DELETE FROM child WHERE id = $1`, [cid]);
  }
  await admin.query(`DELETE FROM app_user WHERE id IN ($1, $2)`, [DAD, MOM]);
};
await cleanup();
await admin.query('BEGIN');
await admin.query(`INSERT INTO app_user (id, display_name, home_tz) VALUES ($1,'Dad','America/Chicago'), ($2,'Mom','America/Chicago')`, [DAD, MOM]);
await admin.query(`INSERT INTO child (id, display_name, birth_date, home_tz) VALUES
  ($1,'Ivy','2016-04-02','America/New_York'), ($2,'Otherchild','2016-04-02','America/New_York'), ($3,'Observedchild','2016-04-02','America/New_York')`, CHILDREN);
await admin.query(`INSERT INTO guardianship (child_id, user_id, role, scope, valid) VALUES
  ($1, $2, 'guardian', '{}', tstzrange(now() - interval '1 year', null)),
  ($1, $3, 'guardian', '{}', tstzrange(now() - interval '1 year', null))`, [CHILD, DAD, MOM]);
await admin.query(`INSERT INTO guardianship (child_id, user_id, role, scope, observer_only, valid) VALUES
  ($1, $2, 'guardian', '{}', true, tstzrange(now() - interval '1 year', null))`, [CHILD_D, DAD]);
await admin.query('COMMIT');

const SECRET = Buffer.from('b'.repeat(32), 'utf8');
const NOW = Date.now();
const JITSI_SECRET_HEX = '9f3a61c07be24d58a1c9e0374bd62f85d7013ac9e86b4f520c1d3e5f7a9b2d4f';
const JITSI_ENV = { CALL_PROVIDER: 'jitsi', NODE_ENV: 'test', JITSI_APP_ID: 'olive-calls',
  JITSI_APP_SECRET: JITSI_SECRET_HEX, JITSI_SERVER_URL: 'https://192.168.1.50:8443' };
const LK_ENV = { CALL_PROVIDER: 'livekit', LIVEKIT_URL: 'wss://x.invalid', LIVEKIT_API_KEY: 'devkey',
  LIVEKIT_API_SECRET: 'devsecret_at_least_32_chars_long_xx' };

function mkApi(callEnv) {
  const api = new Api(SECRET, dbPort(pool));
  registerRoutes(api, pool, undefined, { callEnv });
  return api;
}
const dadTok = issueSession(SECRET, { userId: DAD, roleName: 'guardian', childId: null, escalated: false }, NOW);
const momTok = issueSession(SECRET, { userId: MOM, roleName: 'guardian', childId: null, escalated: false }, NOW);
const childTok = issueSession(SECRET, { userId: null, roleName: 'child', childId: CHILD, escalated: false }, NOW);
const hdr = (tok) => (tok ? { authorization: `Bearer ${tok}` } : {});
const post = (api, childId, tok) => api.handle('POST', `/v1/children/${childId}/calls`, hdr(tok), '');
const join = (api, childId, sid, tok) => api.handle('POST', `/v1/children/${childId}/calls/${sid}/join`, hdr(tok), '');
const end = (api, childId, sid, tok) => api.handle('POST', `/v1/children/${childId}/calls/${sid}/end`, hdr(tok), '');

function claimsOf(jwt) {
  const [h, b, s] = jwt.split('.');
  const want = createHmac('sha256', Buffer.from(JITSI_SECRET_HEX, 'hex')).update(`${h}.${b}`).digest();
  const got = Buffer.from(s, 'base64url');
  return { sigOk: want.length === got.length && timingSafeEqual(want, got), c: JSON.parse(Buffer.from(b, 'base64url')) };
}

const jitsi = mkApi(JITSI_ENV);
const livekit = mkApi(LK_ENV);

// A · jitsi success path
let started, startedRoom;
{
  started = await post(jitsi, CHILD, dadTok);
  check('A jitsi start', '201', started.status, 201);
  const b = started.body;
  check('A jitsi start', 'provider is jitsi', b.provider, 'jitsi');
  check('A jitsi start', 'carries jwt, room, serverURL, sessionId', ['jwt', 'room', 'serverURL', 'sessionId'].every((k) => typeof b[k] === 'string'), true);
  check('A jitsi start', 'serverURL is the configured https origin', b.serverURL, 'https://192.168.1.50:8443');
  check('A jitsi start', 'no livekit fields', 'token' in b || 'wsURL' in b, false);
  check('A jitsi start', 'identity is the caller (I3)', b.identity, DAD);
  check('A jitsi start', 'caller is a moderator', b.moderator, true);
  check('A jitsi start', 'rang is a boolean', typeof b.rang, 'boolean');
  const v = claimsOf(b.jwt);
  check('A jitsi start', 'jwt signature verifies against the configured secret', v.sigOk, true);
  check('A jitsi start', 'jwt room claim equals the response room', v.c.room, b.room);
  check('A jitsi start', 'jwt room does not leak child or guardian id',
    [CHILD, DAD, CHILD.replace(/-/g, ''), DAD.replace(/-/g, '')].some((s) => b.room.includes(s)), false);
  check('A jitsi start', 'jwt expires in minutes (<= 15)', v.c.exp - v.c.iat <= 900 && v.c.exp > v.c.iat, true);
  check('A jitsi start', 'the app secret is not in the response', JSON.stringify(b).includes(JITSI_SECRET_HEX), false);
  const row = await admin.query(`SELECT room_name FROM call_log WHERE id = $1`, [b.sessionId]);
  check('A jitsi start', 'call_log stores the SESSION room name, not the Jitsi room', row.rows[0]?.room_name !== b.room && !!row.rows[0]?.room_name, true);
  startedRoom = b.room;
  const second = await post(jitsi, CHILD, dadTok);
  check('A jitsi start', 'a second call mints a different room', second.body.room === startedRoom, false);
}

// B-D · authorization unchanged
for (const [label, api, env] of [['jitsi', jitsi, 'jitsi'], ['livekit', livekit, 'livekit']]) {
  const g = `B auth (${env})`;
  check(g, 'a child principal cannot start a call', `${(await post(api, CHILD, childTok)).status} ${(await post(api, CHILD, childTok)).body.error}`, '403 child_cannot_start_call');
  const noEdge = await post(api, CHILD_B, dadTok);
  check(g, 'a guardian with no edge is refused with the real can() reason', `${noEdge.status} ${noEdge.body.error}`, '403 no_edge');
  check(g, 'an unauthenticated request is refused', (await post(api, CHILD, null)).status, 401);
  const s = await post(api, CHILD, dadTok);
  check(g, 'a guardian with an edge starts', s.status, 201);
  const mom = await join(api, CHILD, s.body.sessionId, momTok);
  check(g, 'a guardian never invited to the session is refused: not_a_participant', `${mom.status} ${mom.body.error}`, '403 not_a_participant');
  const cj = await join(api, CHILD, s.body.sessionId, childTok);
  check(g, 'the child can join her own call', cj.status, 200);
  check(g, 'a nonexistent session is 404', (await join(api, CHILD, 'nope', dadTok)).status, 404);
  check(g, 'unauthenticated join refused', (await join(api, CHILD, s.body.sessionId, null)).status, 401);
  await end(api, CHILD, s.body.sessionId, dadTok);
  check(g, 'joining an ended call is 404', (await join(api, CHILD, s.body.sessionId, childTok)).status, 404);
  check(g, 'ending twice is an honest 200 ended:false', `${(await end(api, CHILD, s.body.sessionId, dadTok)).body.ended}`, 'false');
}

// E · jitsi join: same room, child is not a moderator
{
  const cj = await join(jitsi, CHILD, started.body.sessionId, childTok);
  check('E jitsi join', 'provider jitsi, 200', `${cj.status} ${cj.body.provider}`, '200 jitsi');
  check('E jitsi join', 'the child lands in the same room as the caller', cj.body.room, startedRoom);
  check('E jitsi join', 'the child is NOT a moderator', cj.body.moderator, false);
  check('E jitsi join', 'her identity is her own childId (I3)', cj.body.identity, CHILD);
  check('E jitsi join', 'her display name is her own', cj.body.displayName, 'Ivy');
  const c = claimsOf(cj.body.jwt);
  check('E jitsi join', 'her jwt verifies and says moderator:false', `${c.sigOk} ${c.c.context.user.moderator}`, 'true false');
  check('E jitsi join', 'her jwt is for the same room', c.c.room, startedRoom);
  check('E jitsi join', 'child payload sweep: no banned keys', /"(age|birth|dob|email)/i.test(JSON.stringify(cj.body) + JSON.stringify(c.c)), false);
  const dj = await join(jitsi, CHILD, started.body.sessionId, dadTok);
  check('E jitsi join', 'the original caller re-mints as moderator', `${dj.status} ${dj.body.moderator}`, '200 true');
}

// F · observer-only: allowed to start (§17.3 is read-only), never a moderator
{
  const o = await post(jitsi, CHILD_D, dadTok);
  check('F observer', 'an observer-only guardian can still start', o.status, 201);
  check('F observer', 'but is not a moderator and is flagged observerOnly', `${o.body.moderator} ${o.body.observerOnly}`, 'false true');
}

// G · unavailable, honestly, BEFORE anything happens
{
  const before = (await admin.query(`SELECT count(*)::int AS n FROM call_log WHERE child_id = $1`, [CHILD])).rows[0].n;
  for (const [label, env] of [['no jitsi env', { CALL_PROVIDER: 'jitsi', NODE_ENV: 'test' }],
                              ['default provider, only livekit env set', { NODE_ENV: 'test', ...LK_ENV, CALL_PROVIDER: undefined }],
                              ['jitsi, secret missing', { ...JITSI_ENV, JITSI_APP_SECRET: undefined }]]) {
    const r = await post(mkApi(env), CHILD, dadTok);
    check('G unavailable', `${label}: 503 call_provider_unavailable`, `${r.status} ${r.body.error}`, '503 call_provider_unavailable');
    check('G unavailable', `${label}: body carries no fake token`, 'jwt' in r.body || 'token' in r.body, false);
  }
  const after = (await admin.query(`SELECT count(*)::int AS n FROM call_log WHERE child_id = $1`, [CHILD])).rows[0].n;
  check('G unavailable', 'no call_log row was written and no device rung for an unmintable call', after, before);
  const j = await join(mkApi({ CALL_PROVIDER: 'jitsi', NODE_ENV: 'test' }), CHILD, started.body.sessionId, childTok);
  check('G unavailable', 'join is also 503, not a fake success', j.status, 503);
  const lkOff = await post(mkApi({ CALL_PROVIDER: 'livekit' }), CHILD, dadTok);
  check('G unavailable', 'livekit unconfigured keeps its historical 500 call_backend_unconfigured', `${lkOff.status} ${lkOff.body.error}`, '500 call_backend_unconfigured');
}

// H · livekit selectable and unchanged in shape
{
  const s = await post(livekit, CHILD, dadTok);
  check('H livekit', 'provider livekit with token + wsURL', `${s.body.provider} ${typeof s.body.token} ${s.body.wsURL}`, 'livekit string wss://x.invalid');
  check('H livekit', 'no jitsi fields', 'jwt' in s.body || 'serverURL' in s.body, false);
}

await cleanup();
await admin.end();
await pool.end();

let gname = '';
for (const r of rows) {
  if (r.g !== gname) { gname = r.g; console.log(`\n${gname}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`));
}
console.log(`\n${'-'.repeat(54)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
