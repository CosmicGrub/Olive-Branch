/**
 * server/routes.mjs - the 'lan-p2p' call provider end to end through the real routes, against a real Postgres and
 * real RLS (run as app_owner AND as app_runtime in tools/verify.sh). 2026-11-21, MASTERFILE 5.19, 5.25.2, 16.2 #6.
 *
 * What it proves, in this order:
 *   A  a grown-up starts a call: the grant says lan-p2p, carries NO token or media-server address, is never
 *      recorded, and the ICE list is EMPTY by default (host candidates only, no outside service)
 *   B  the tablet's foreground ring: the pending poll shows the call to HER and to nobody else, makes the grown-up's
 *      "can she be reached" honest, and answering stamps the call log
 *   C  the signalling mailbox: offer, answer and ICE pass between exactly the two participants; a message is never
 *      echoed back to its sender; a second grown-up, another family's child and a stranger are all refused
 *   D  hostile input: bad kinds, bad payloads, oversized messages, a closed call
 *   E  ending: cancelled, declined and answered are recorded with the right reason; the mailbox closes with the call
 *   F  the child calls an approved grown-up (and only one): the grown-up's poll shows it, nobody else's does, the
 *      child is told nothing about rings or reasons
 *   G  quiet hours: no ring in her quiet hours, the grown-up is told why, and she cannot start one into it
 *   H  the ICE list is configuration: STUN, short-lived TURN credentials, relay-only reach BOTH sides of a call
 */
import pg from 'pg';
import { createHmac } from 'node:crypto';
import { Api } from '../../packages/api/src/api.mjs';
import { createPool, dbPort } from '../../packages/db/src/pool.mjs';
import { registerRoutes } from '../routes.mjs';
import { issueSession } from '../../packages/auth/src/auth.mjs';

const DATABASE_URL = process.env.DATABASE_URL;
const ADMIN_DATABASE_URL = process.env.ADMIN_DATABASE_URL ?? DATABASE_URL;
if (!DATABASE_URL) { console.error('DATABASE_URL required - this suite needs a real Postgres, not a fake.'); process.exit(2); }

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) }); };

const pool = createPool(DATABASE_URL);
const admin = new pg.Client({ connectionString: ADMIN_DATABASE_URL });
await admin.connect();

const CHILD = 'a1a1a1a1-1234-4234-8234-aaaaaaaaaaa1';     // Dad and Mom are her approved grown-ups
const CHILD_B = 'a1a1a1a1-1234-4234-8234-aaaaaaaaaaa2';   // another family's child
const CHILD_Q = 'a1a1a1a1-1234-4234-8234-aaaaaaaaaaa3';   // in quiet hours all day
const DAD = 'b2b2b2b2-1234-4234-8234-bbbbbbbbbbb1';
const MOM = 'b2b2b2b2-1234-4234-8234-bbbbbbbbbbb2';
const OTHER_DAD = 'b2b2b2b2-1234-4234-8234-bbbbbbbbbbb3'; // guardian of CHILD_B only

const cleanup = async () => {
  await admin.query(`DELETE FROM call_log WHERE child_id IN ($1,$2,$3)`, [CHILD, CHILD_B, CHILD_Q]);
  await admin.query(`DELETE FROM day_part WHERE child_id IN ($1,$2,$3)`, [CHILD, CHILD_B, CHILD_Q]);
  for (const cid of [CHILD, CHILD_B, CHILD_Q]) {
    await admin.query(`DELETE FROM guardianship WHERE child_id = $1`, [cid]);
    await admin.query(`DELETE FROM child WHERE id = $1`, [cid]);
  }
  await admin.query(`DELETE FROM app_user WHERE id IN ($1,$2,$3)`, [DAD, MOM, OTHER_DAD]);
};
await cleanup();
await admin.query('BEGIN');
await admin.query(`INSERT INTO app_user (id, display_name, home_tz) VALUES
  ($1,'Dad','America/Chicago'), ($2,'Mom','America/Chicago'), ($3,'Otherdad','America/Chicago')`, [DAD, MOM, OTHER_DAD]);
await admin.query(`INSERT INTO child (id, display_name, birth_date, home_tz) VALUES
  ($1,'Ivy','2016-04-02','America/New_York'), ($2,'Otherchild','2016-04-02','America/New_York'),
  ($3,'Quietchild','2016-04-02','America/New_York')`, [CHILD, CHILD_B, CHILD_Q]);
for (const [c, u] of [[CHILD, DAD], [CHILD, MOM], [CHILD_B, OTHER_DAD], [CHILD_Q, DAD]]) {
  await admin.query(`INSERT INTO guardianship (child_id, user_id, role, scope, valid)
    VALUES ($1,$2,'guardian','{}', tstzrange(now() - interval '1 year', null))`, [c, u]);
}
await admin.query(`INSERT INTO day_part (child_id, kind, starts_local, ends_local, days_of_week, reachable, effective)
  VALUES ($1,'asleep','00:00','24:00','{0,1,2,3,4,5,6}', false, '[2020-01-01,2099-01-01)')`, [CHILD_Q]);
await admin.query('COMMIT');

const SECRET = Buffer.from('c'.repeat(32), 'utf8');
const NOW = Date.now();
const api = new Api(SECRET, dbPort(pool), () => Date.now(), { strictIds: true });
registerRoutes(api, pool, undefined, { callEnv: { CALL_PROVIDER: 'lan-p2p' } });

const tok = (who) => issueSession(SECRET, who === 'child' || who === 'childB' || who === 'childQ'
  ? { userId: null, roleName: 'child', childId: { child: CHILD, childB: CHILD_B, childQ: CHILD_Q }[who], escalated: false }
  : { userId: { dad: DAD, mom: MOM, otherDad: OTHER_DAD }[who], roleName: 'guardian', childId: null, escalated: false }, NOW);
const T = { dad: tok('dad'), mom: tok('mom'), otherDad: tok('otherDad'), child: tok('child'), childB: tok('childB'), childQ: tok('childQ') };
const call = (a, method, path, token, body) => a.handle(method, path,
  token ? { authorization: `Bearer ${token}` } : {}, body === undefined ? '' : JSON.stringify(body));
const start = (childId, token, a = api, body) => call(a, 'POST', `/v1/children/${childId}/calls`, token, body);
const joinC = (childId, sid, token, a = api) => call(a, 'POST', `/v1/children/${childId}/calls/${sid}/join`, token);
const endC = (childId, sid, token, a = api) => call(a, 'POST', `/v1/children/${childId}/calls/${sid}/end`, token);
const pending = (childId, token, a = api) => call(a, 'GET', `/v1/children/${childId}/calls/pending`, token);
const avail = (childId, token, a = api) => call(a, 'GET', `/v1/children/${childId}/calls/availability`, token);
const sigPost = (childId, sid, token, kind, payload, a = api) =>
  call(a, 'POST', `/v1/children/${childId}/calls/${sid}/signal`, token, { kind, payload });
const sigGet = (childId, sid, token, after = 0, a = api) =>
  call(a, 'GET', `/v1/children/${childId}/calls/${sid}/signal?after=${after}`, token);
const logRow = async (sid) => (await admin.query(`SELECT * FROM call_log WHERE id = $1`, [sid])).rows[0];

// ======================================================================= A
let sidA;
{
  const before = await avail(CHILD, T.dad);
  check('A start', 'availability says lan-p2p is available', `${before.body.provider} ${before.body.available}`, 'lan-p2p true');
  check('A start', 'with no STUN or TURN it says this works on one network only', before.body.sameNetworkOnly, true);
  check('A start', 'her tablet has not asked yet, so the grown-up is told it may be unreachable', before.body.tabletReachable, false);

  const r = await start(CHILD, T.dad);
  check('A start', 'a guardian starts a call: 201', r.status, 201);
  sidA = r.body.sessionId;
  check('A start', 'the grant names the provider', r.body.provider, 'lan-p2p');
  check('A start', 'caller role', r.body.role, 'caller');
  check('A start', 'identity is her own user id, never client-supplied', r.body.identity, DAD);
  check('A start', 'NO token, jwt, room or media-server address in a lan-p2p grant',
    JSON.stringify(['token', 'jwt', 'room', 'wsURL', 'serverURL'].filter((k) => k in r.body)), '[]');
  check('A start', 'the call is never recorded', r.body.recorded, false);
  check('A start', 'the ICE list is EMPTY by default (host candidates only)', JSON.stringify(r.body.iceServers), '[]');
  check('A start', 'the ICE policy is all', r.body.iceTransportPolicy, 'all');
  check('A start', 'the tablet had not asked: the grown-up is told it could not be reached', r.body.ringState, 'tablet_unreachable');
  check('A start', 'rang is false then', r.body.rang, false);
  const row = await logRow(sidA);
  check('A start', 'the call log row was written first, started by the grown-up', `${row.started_by === DAD} ${row.started_by_child}`, 'true false');
  check('A start', 'recorded is false in the log', row.recorded, false);
  check('A start', 'no answer yet', row.answered_at, null);
}

// ======================================================================= B
{
  const p = await pending(CHILD, T.child);
  check('B ring', 'the tablet sees the call', p.body.calls?.length, 1);
  check('B ring', 'it names the caller by her own word for the grown-up', p.body.calls?.[0]?.from, 'Dad');
  check('B ring', 'it carries the session id and a start time only', JSON.stringify(Object.keys(p.body.calls[0]).sort()), '["from","sessionId","startedAt"]');
  check('B ring', 'after the tablet asked, it is reachable', (await avail(CHILD, T.dad)).body.tabletReachable, true);
  const second = await start(CHILD, T.mom);
  check('B ring', 'a second call, now that the tablet has asked, rang', `${second.body.ringState} ${second.body.rang}`, 'rang true');
  await endC(CHILD, second.body.sessionId, T.mom);
  check('B ring', 'Mom may not read the tablet side: a guardian polling gets only calls the child started', (await pending(CHILD, T.mom)).body.calls.length, 0);
  check('B ring', 'another family\'s child cannot poll this child', (await pending(CHILD, T.childB)).status, 403);
  check('B ring', 'another family\'s grown-up cannot poll this child', (await pending(CHILD, T.otherDad)).status, 403);
  check('B ring', 'unauthenticated is refused', (await pending(CHILD, null)).status, 401);

  const j = await joinC(CHILD, sidA, T.child);
  check('B ring', 'she answers: the join grant is lan-p2p, callee, no token', `${j.status} ${j.body.provider} ${j.body.role} ${'token' in j.body}`, '200 lan-p2p callee false');
  check('B ring', 'her identity is her own child id', j.body.identity, CHILD);
  check('B ring', 'answering stamps the call log', (await logRow(sidA)).answered_at !== null, true);
  check('B ring', 'an answered call no longer rings', (await pending(CHILD, T.child)).body.calls.length, 0);
  const dadJoin = await joinC(CHILD, sidA, T.dad);
  check('B ring', 'the caller re-joining is still the caller', dadJoin.body.role, 'caller');
}

// ======================================================================= C
{
  const o = await sigPost(CHILD, sidA, T.dad, 'offer', { sdp: 'v=0 offer' });
  check('C signal', 'the caller posts an offer', `${o.status} ${o.body.seq}`, '200 1');
  const g = await sigGet(CHILD, sidA, T.child, 0);
  check('C signal', 'the callee reads exactly that offer', `${g.body.signals.length} ${g.body.signals[0].kind} ${g.body.signals[0].from}`, '1 offer caller');
  check('C signal', 'the sender never reads her own message back', (await sigGet(CHILD, sidA, T.dad, 0)).body.signals.length, 0);
  await sigPost(CHILD, sidA, T.child, 'answer', { sdp: 'v=0 answer' });
  await sigPost(CHILD, sidA, T.child, 'ice', { candidates: [{ candidate: 'candidate:1 1 udp 1 192.0.2.7 5000 typ host' }] });
  const back = await sigGet(CHILD, sidA, T.dad, 0);
  check('C signal', 'the caller reads the answer and the candidates', back.body.signals.map((m) => m.kind).join(','), 'answer,ice');
  check('C signal', 'reading after a sequence number returns only the newer', (await sigGet(CHILD, sidA, T.dad, back.body.signals[0].seq)).body.signals.length, 1);

  const momPost = await sigPost(CHILD, sidA, T.mom, 'offer', { sdp: 'x' });
  check('C signal', 'a second grown-up of the same child who is not in THIS call is refused', `${momPost.status} ${momPost.body.error}`, '403 not_a_participant');
  check('C signal', 'she cannot read it either', (await sigGet(CHILD, sidA, T.mom, 0)).status, 403);
  check('C signal', 'another family\'s child cannot post to it', (await sigPost(CHILD, sidA, T.childB, 'offer', { sdp: 'x' })).status, 403);
  check('C signal', 'another family\'s grown-up cannot read it', (await sigGet(CHILD, sidA, T.otherDad, 0)).status, 403);
  check('C signal', 'a session id from another child\'s path is not found, not leaked', (await sigGet(CHILD_B, sidA, T.otherDad, 0)).status, 404);
  check('C signal', 'unauthenticated is refused', (await sigGet(CHILD, sidA, null, 0)).status, 401);
  check('C signal', 'an unknown session is a plain 404', (await sigGet(CHILD, 'cccccccc-1234-4234-8234-cccccccccccc', T.dad, 0)).status, 404);
}

// ======================================================================= D
{
  check('D hostile', 'an unknown kind is refused', (await sigPost(CHILD, sidA, T.dad, 'record', { x: 1 })).status, 400);
  check('D hostile', 'a missing kind is refused', (await call(api, 'POST', `/v1/children/${CHILD}/calls/${sidA}/signal`, T.dad, { payload: {} })).status, 400);
  check('D hostile', 'an array payload is refused', (await sigPost(CHILD, sidA, T.dad, 'ice', [1, 2])).status, 400);
  check('D hostile', 'a string payload is refused', (await sigPost(CHILD, sidA, T.dad, 'ice', 'x')).status, 400);
  check('D hostile', 'a null payload is refused', (await sigPost(CHILD, sidA, T.dad, 'ice', null)).status, 400);
  check('D hostile', 'an oversized payload is refused', (await sigPost(CHILD, sidA, T.dad, 'offer', { sdp: 'x'.repeat(20000) })).status, 413);
}

// ======================================================================= E
{
  const c1 = await start(CHILD, T.dad);
  const e1 = await endC(CHILD, c1.body.sessionId, T.dad);
  check('E end', 'the caller hanging up before she answers is cancelled', `${e1.body.ended} ${e1.body.reason}`, 'true cancelled');
  check('E end', 'a second end is a harmless no-op', (await endC(CHILD, c1.body.sessionId, T.dad)).body.ended, false);
  check('E end', 'the mailbox is closed with the call', (await sigGet(CHILD, c1.body.sessionId, T.child, 0)).status, 404);
  check('E end', 'she cannot join a call that ended', (await joinC(CHILD, c1.body.sessionId, T.child)).status, 404);

  const c2 = await start(CHILD, T.dad);
  const e2 = await endC(CHILD, c2.body.sessionId, T.child);
  check('E end', 'her device putting it away unanswered is declined (recorded, never shown to her)', `${e2.body.ended} ${e2.body.reason}`, 'true declined');

  const e3 = await endC(CHILD, sidA, T.child);
  check('E end', 'an answered call ends as answered', `${e3.body.ended} ${e3.body.reason}`, 'true answered');
  check('E end', 'the log has an end time and the reason', `${(await logRow(sidA)).ended_at !== null} ${(await logRow(sidA)).ended_reason}`, 'true answered');
  const c4 = await start(CHILD, T.dad);
  check('E end', 'a second grown-up of the family cannot end a call she is not part of', (await endC(CHILD, c4.body.sessionId, T.mom)).status, 403);
  await endC(CHILD, c4.body.sessionId, T.dad);
}

// ======================================================================= F
{
  const c = await start(CHILD, T.child);
  check('F child calls', 'the child starts a call to an approved grown-up: 201', c.status, 201);
  const sid = c.body.sessionId;
  check('F child calls', 'the grant is lan-p2p, caller, her own child id', `${c.body.provider} ${c.body.role} ${c.body.identity === CHILD}`, 'lan-p2p caller true');
  check('F child calls', 'she is told nothing about rings, reasons or who is reachable', JSON.stringify(['rang', 'ringState', 'reason', 'tabletReachable'].filter((k) => k in c.body)), '[]');
  const row = await logRow(sid);
  check('F child calls', 'the log says the child started it, with no grown-up as starter', `${row.started_by_child} ${row.started_by}`, 'true null');
  check('F child calls', 'both participants are recorded', [...row.participant_ids].sort().join(), [CHILD, DAD].sort().join());
  const dadPending = await pending(CHILD, T.dad);
  check('F child calls', 'the grown-up she called sees it ring', `${dadPending.body.calls.length} ${dadPending.body.calls[0]?.from}`, '1 Ivy');
  check('F child calls', 'the other grown-up of the family (not called) does NOT', (await pending(CHILD, T.mom)).body.calls.length, 0);
  check('F child calls', 'her own tablet is not rung by her own call', (await pending(CHILD, T.child)).body.calls.length, 0);
  const dadJoin = await joinC(CHILD, sid, T.dad);
  check('F child calls', 'the grown-up answers: callee', `${dadJoin.status} ${dadJoin.body.role}`, '200 callee');
  check('F child calls', 'answering stamps the log', (await logRow(sid)).answered_at !== null, true);
  check('F child calls', 'the other grown-up cannot join it', (await joinC(CHILD, sid, T.mom)).status, 403);
  await sigPost(CHILD, sid, T.child, 'offer', { sdp: 'o' });
  check('F child calls', 'signalling works the other way round: the grown-up reads her offer', (await sigGet(CHILD, sid, T.dad, 0)).body.signals[0].from, 'caller');
  const e = await endC(CHILD, sid, T.dad);
  check('F child calls', 'ended after answering: answered', e.body.reason, 'answered');

  const c2 = await start(CHILD, T.child);
  const e2 = await endC(CHILD, c2.body.sessionId, T.child);
  check('F child calls', 'she hangs up before anyone answers: cancelled (she is the caller)', e2.body.reason, 'cancelled');
  const c3 = await start(CHILD, T.child);
  check('F child calls', 'the grown-up putting it away unanswered is declined', (await endC(CHILD, c3.body.sessionId, T.dad)).body.reason, 'declined');

  const pick = await start(CHILD, T.child, api, { toUserId: MOM });
  check('F child calls', 'she can name which approved grown-up', (await pending(CHILD, T.mom)).body.calls.length, 1);
  await endC(CHILD, pick.body.sessionId, T.child);
  const outsider = await start(CHILD, T.child, api, { toUserId: OTHER_DAD });
  check('F child calls', 'naming a grown-up of ANOTHER family is refused', `${outsider.status} ${outsider.body.error}`, '403 no_approved_grownup');
  check('F child calls', 'a grown-up cannot start a call for another family\'s child', (await start(CHILD_B, T.dad)).status, 403);
  check('F child calls', 'another family\'s child cannot start a call into this family', (await start(CHILD, T.childB)).status, 403);
}

// ======================================================================= G
{
  const q = await start(CHILD_Q, T.dad);
  check('G quiet', 'a grown-up may still open the call (it waits)', q.status, 201);
  check('G quiet', 'and is told why it did not ring', `${q.body.ringState} ${q.body.rang}`, 'quiet_hours false');
  check('G quiet', 'her tablet is shown nothing in her quiet hours', (await pending(CHILD_Q, T.childQ)).body.calls.length, 0);
  const own = await start(CHILD_Q, T.childQ);
  check('G quiet', 'she cannot start a call into her own quiet hours (a calm refusal, not an error shape)', `${own.status} ${own.body.error}`, '409 quiet_hours');
  await endC(CHILD_Q, q.body.sessionId, T.dad);
}

// ======================================================================= H
{
  const turnSecret = 'turn-shared-secret-0123456789abcdef';
  const iceApi = new Api(SECRET, dbPort(pool), () => Date.now(), { strictIds: true });
  registerRoutes(iceApi, pool, undefined, { callEnv: {
    CALL_PROVIDER: 'lan-p2p', CALL_ICE_STUN_URLS: 'stun:192.0.2.10:3478',
    CALL_ICE_TURN_URLS: 'turn:192.0.2.10:3478?transport=udp,turns:192.0.2.10:5349', CALL_ICE_TURN_SECRET: turnSecret,
    CALL_ICE_RELAY_ONLY: '1' } });
  const a = await avail(CHILD, T.dad, iceApi);
  check('H ice', 'with STUN/TURN configured the call is no longer same-network-only', a.body.sameNetworkOnly, false);
  check('H ice', 'availability leaks no address, secret or credential', JSON.stringify(a.body).includes('192.0.2') || JSON.stringify(a.body).includes(turnSecret), false);
  const c = await start(CHILD, T.dad, iceApi);
  const g = c.body;
  check('H ice', 'the caller grant carries the ICE list: a STUN entry and a TURN entry', g.iceServers.map((s) => s.urls.length + (s.username ? 'T' : 'S')).join(','), '1S,2T');
  check('H ice', 'relay-only mode reaches the client as the ICE policy', g.iceTransportPolicy, 'relay');
  const turn = g.iceServers[1];
  const [expiry] = turn.username.split(':');
  check('H ice', 'the TURN credential is short-lived (expiry within the TTL)', Number(expiry) - Math.floor(Date.now() / 1000) <= 600 && Number(expiry) > Math.floor(Date.now() / 1000), true);
  check('H ice', 'and it is the TURN REST HMAC of the shared secret, which never leaves the server',
    turn.credential, createHmac('sha1', turnSecret).update(turn.username).digest('base64'));
  check('H ice', 'the shared secret itself is nowhere in the grant', JSON.stringify(g).includes(turnSecret), false);
  check('H ice', 'the username names no person or child', turn.username.includes(DAD) || turn.username.includes(CHILD), false);
  const j = await joinC(CHILD, c.body.sessionId, T.child, iceApi);
  check('H ice', 'the OTHER side of the call gets the same list, with its own credential',
    `${j.body.iceServers.length} ${j.body.iceTransportPolicy} ${j.body.iceServers[1].username !== turn.username}`, '2 relay true');
  check('H ice', 'and no shared secret either', JSON.stringify(j.body).includes(turnSecret), false);
  await endC(CHILD, c.body.sessionId, T.dad, iceApi);

  // a malformed ICE setting is a plain refusal, never a half-configured call
  const bad = new Api(SECRET, dbPort(pool), () => Date.now(), { strictIds: true });
  registerRoutes(bad, pool, undefined, { callEnv: { CALL_PROVIDER: 'lan-p2p', CALL_ICE_TURN_URLS: 'turn:192.0.2.10:3478' } });
  const ba = await avail(CHILD, T.dad, bad);
  check('H ice', 'TURN urls without a secret: calls are reported not available', ba.body.available, false);
}

await cleanup();
await admin.end();
await pool.end();

let gname = '';
for (const r of rows) { if (r.g !== gname) { gname = r.g; console.log(`\n${gname}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
