/**
 * A lost or stolen phone or tablet (db/migrations/0057_lost_device.sql), end to end against a REAL Postgres through
 * the REAL Api (strict ids ON, as in production). Every account comes from POST /v1/auth/signup, every extra device
 * from the real pairing routes.
 *
 *   A. mark / found   a grown-up marks their own other phone: it is refused at once, nothing is deleted, the others
 *                     are told, "I have it" brings it back after the owner shows their PIN once.
 *   B. two grown-ups  another grown-up marks it; only the owner can say "It is lost"; a report the owner made cannot
 *                     be undone by the other grown-up (unless the phone it came from was itself cut off).
 *   C. the 72 hours   the notice ends by itself, exactly once; "I have it" arriving at the last instant loses, one
 *                     a millisecond earlier wins; found vs confirm race: exactly one wins.
 *   D. hostile        stranger family, wrong PIN, PIN lockout burned by a thief (the other grown-up still marks),
 *                     the thief's phone refused mid-flight, replayed answers, rate limit, malformed input, child
 *                     sessions, a tablet.
 *   E. the list       what a grown-up sees and may do; no credential ever in it.
 *   F. storage        the history is append-only, the pause row shape is enforced, nothing readable by a stranger.
 *
 * Needs a NOSUPERUSER NOBYPASSRLS DATABASE_URL (app_owner or app_runtime) and an ADMIN_DATABASE_URL for setup and
 * cleanup. Prints "N passed, M failed" for verify.sh.
 */
import pg from 'pg';
import os from 'node:os';
import path from 'node:path';
import fs from 'node:fs/promises';
import { randomUUID, randomBytes } from 'node:crypto';
import { Api } from '../../packages/api/src/api.mjs';
import { createPool, dbPort, withSession, issueSignupAllowance, setSignupPolicy,
  markDeviceLost, foundDevice, confirmDeviceLost, pairedDeviceStanding, orderDeviceWipe, acknowledgeDeviceWiped,
  LOST_NOTICE_MS, LOST_MARK_LIMIT_PER_DAY } from '../../packages/db/src/pool.mjs';
import { registerRoutes } from '../routes.mjs';
import { FilesystemStorage } from '../../packages/storage/src/storage.mjs';

const DATABASE_URL = process.env.DATABASE_URL;
const ADMIN_DATABASE_URL = process.env.ADMIN_DATABASE_URL ?? DATABASE_URL;
if (!DATABASE_URL) {
  console.error('DATABASE_URL required — this suite needs a real Postgres, not a fake.');
  process.exit(2);
}

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) }); };

const pool = createPool(DATABASE_URL);
const admin = new pg.Client({ connectionString: ADMIN_DATABASE_URL });
await admin.connect();

const SECRET = Buffer.from('l'.repeat(32), 'utf8');
const tmpRoot = await fs.mkdtemp(path.join(os.tmpdir(), 'olive-lost-test-'));
const api = new Api(SECRET, dbPort(pool), () => Date.now(), { strictIds: true });
registerRoutes(api, pool, new FilesystemStorage(tmpRoot), {
  callEnv: { CALL_PROVIDER: 'jitsi', NODE_ENV: 'test', JITSI_APP_ID: 'olive-calls',
    JITSI_APP_SECRET: randomBytes(32).toString('hex'), JITSI_SERVER_URL: 'https://calls.example.test:8443' },
});

const hdr = (tok) => (tok ? { authorization: `Bearer ${tok}` } : {});
const call = (method, p, tok, body) => api.handle(
  method, p, hdr(tok), body === undefined ? '' : JSON.stringify(body));
const RUN = randomUUID().slice(0, 8);
const LABEL = `losttest-${RUN}`;
const users = [];
const children = [];

const signup = async (label, over = {}) => {
  const token = (await issueSignupAllowance(pool, { label })).token;
  const r = await call('POST', '/v1/auth/signup', null, {
    allowanceToken: token, displayName: 'Mom', homeTz: 'America/Chicago', pin: '4821',
    deviceLabel: 'Phone', ...over });
  if (r.status !== 201) throw new Error(`signup failed: ${r.status} ${JSON.stringify(r.body)}`);
  users.push(r.body.userId);
  return { userId: r.body.userId, tok: r.body.token, deviceId: r.body.deviceId, cred: r.body.deviceCredential };
};
const edge = (childId, userId) => admin.query(
  `INSERT INTO guardianship (child_id, user_id, role, scope, valid)
   VALUES ($1, $2, 'guardian', '{}', tstzrange(now() - interval '1 minute', NULL))`, [childId, userId]);
const pairPhone = async (g, pin = '4821') => {
  const code = await call('POST', '/v1/me/device-pairing-codes', g.tok, { pin });
  if (code.status !== 201) throw new Error('code failed: ' + code.status + ' ' + JSON.stringify(code.body));
  const r = await call('POST', '/v1/device-pairing/redeem', null, { code: code.body.numericCode, role: 'guardian' });
  if (r.status !== 201) throw new Error(`pair phone failed: ${r.status} ${JSON.stringify(r.body)}`);
  return { userId: g.userId, tok: r.body.sessionToken, deviceId: r.body.deviceId, cred: r.body.deviceCredential };
};
const pairTablet = async (g, childId, pin = '4821') => {
  const code = await call('POST', `/v1/children/${childId}/device-pairing-codes`, g.tok, { pin });
  const r = await call('POST', '/v1/device-pairing/redeem', null, { code: code.body.numericCode, role: 'child' });
  if (r.status !== 201) throw new Error(`pair tablet failed: ${r.status} ${JSON.stringify(r.body)}`);
  return { tok: r.body.sessionToken, deviceId: r.body.deviceId, cred: r.body.deviceCredential };
};
const mark = (by, deviceId, pin = '4821') => call('POST', `/v1/me/devices/${deviceId}/mark-lost`, by.tok, { pin });
const found = (by, deviceId, incidentId, pin = '4821') => call('POST', `/v1/me/devices/${deviceId}/found`, by.tok, { pin, incidentId });
const confirm = (by, deviceId, incidentId, pin = '4821') => call('POST', `/v1/me/devices/${deviceId}/confirm-lost`, by.tok, { pin, incidentId });
const refresh = (d, pin) => call('POST', '/v1/auth/session/refresh', null, { deviceId: d.deviceId, deviceCredential: d.cred, ...(pin ? { pin } : {}) });
const ping = (d) => call('GET', '/v1/me/children', d.tok);
const unlockPin = (userId) => admin.query(
  `UPDATE pin_credential SET failed_attempts = 0, locked_until = NULL WHERE user_id = $1`, [userId]);
const feed = async (by, childId) => (await call('GET', `/v1/children/${childId}/security-events`, by.tok)).body?.events?.map((e) => e.kind) ?? [];
const row = async (id) => (await admin.query(`SELECT * FROM paired_device WHERE id = $1`, [id])).rows[0];
const events = async (id) => (await admin.query(`SELECT kind FROM device_lost_event WHERE device_id = $1 ORDER BY seq`, [id])).rows.map((r) => r.kind);
const counts = async () => ({
  edges: (await admin.query(`SELECT count(*)::int n FROM guardianship WHERE child_id = ANY($1::uuid[])`, [children])).rows[0].n,
  kids: (await admin.query(`SELECT count(*)::int n FROM child WHERE id = ANY($1::uuid[])`, [children])).rows[0].n,
  devices: (await admin.query(`SELECT count(*)::int n FROM paired_device WHERE target_id = ANY($1::uuid[]) OR target_id = ANY($2::uuid[])`, [users, children])).rows[0].n,
});

await setSignupPolicy(pool, { enabled: true, maxAccounts: null });

// Family A: Mom (phones M1 and M2), Dad (phone D1), Ivy (tablet T1). Family B: a stranger (phone B1).
const mom = await signup(LABEL, { displayName: `Mom-${RUN}` });
const stranger = await signup(`${LABEL}-b`, { displayName: `Other-${RUN}`, pin: '7315' });
const mkChild = async (g, name, pin) => {
  const r = await call('POST', '/v1/children', g.tok, { displayName: name, birthDate: '2018-03-04', homeTz: 'America/Chicago', pin });
  if (r.status !== 201) throw new Error('child create failed');
  children.push(r.body.child.id);
  return r.body.child.id;
};
const CHILD_A = await mkChild(mom, 'Ivy', '4821');
await mkChild(stranger, 'Otis', '7315');
const dad = await signup(`${LABEL}-dad`, { displayName: `Dad-${RUN}`, pin: '2468' });
await edge(CHILD_A, dad.userId);
const M1 = mom;                              // the phone that will be lost
const M2 = await pairPhone(mom);             // mom's other phone, in her hand
const D1 = dad;
const T1 = await pairTablet(M2, CHILD_A);
const baseline = await counts();
check('setup', 'two families, a co-parent, three grown-up phones and a tablet are real and signed in',
  `${(await ping(M1)).status}${(await ping(M2)).status}${(await ping(D1)).status}${(await call('GET', `/v1/children/${CHILD_A}/paired-devices`, M2.tok)).status}`, '200200200200');

// ===========================================================================
// A · MARK, FOUND
// ===========================================================================
let inc1;
{
  const r = await mark(M2, M1.deviceId);
  check('A mark', 'mom marks her own other phone from her phone in hand -> 201 paused', `${r.status} ${r.body?.state}`, '201 paused');
  inc1 = r.body?.incidentId;
  check('A mark', '...it names an incident and a deadline 72 hours out',
    Math.abs(new Date(r.body.revokeDueAt).getTime() - Date.now() - LOST_NOTICE_MS) < 60000 && /^[0-9a-f-]{36}$/.test(inc1), 'true');
  const p = await ping(M1);
  check('A mark', 'the marked phone is refused on its very next request -> 401 device_paused', `${p.status} ${p.body?.error}`, '401 device_paused');
  const rf = await refresh(M1);
  check('A mark', '...and cannot get a new session either (own word, not "revoked")', `${rf.status} ${rf.body?.error}`, '401 device_paused');
  check('A mark', '...but a wrong credential still learns nothing about its standing',
    (await call('POST', '/v1/auth/session/refresh', null, { deviceId: M1.deviceId, deviceCredential: 'x'.repeat(43) })).body?.error, 'invalid_device_credential');
  check('A mark', 'her other phone is unaffected', (await ping(M2)).status, 200);
  const c = await counts();
  check('A mark', 'NOTHING was deleted: same grown-ups, children and devices as before', JSON.stringify(c), JSON.stringify(baseline));
  check('A mark', 'the device row is still there, paused, not revoked',
    `${(await row(M1.deviceId)).paused_at !== null}${(await row(M1.deviceId)).revoked_at === null}`, 'truetrue');
  check('A mark', 'the other grown-up is told, in the security feed', (await feed(D1, CHILD_A)).includes('device_lost'), 'true');
  check('A mark', 'so is mom, on her other phone', (await feed(M2, CHILD_A)).includes('device_lost'), 'true');
  check('A mark', 'the history has one "marked" line', (await events(M1.deviceId)).join(), 'marked');

  const again = await mark(M2, M1.deviceId);
  check('A mark', 'marking again is idempotent: 200, same incident, same deadline',
    `${again.status} ${again.body?.incidentId === inc1} ${again.body?.revokeDueAt === r.body.revokeDueAt} ${again.body?.already}`, '200 true true true');
  check('A mark', '...and never restarts the 72 hours or adds a second line', (await events(M1.deviceId)).join(), 'marked');

  // found: the owner, from the phone in her hand, with her PIN, quoting the incident
  const f = await found(M2, M1.deviceId, inc1);
  check('A found', '"I have it" from her other phone -> 200 active', `${f.status} ${f.body?.state}`, '200 active');
  check('A found', '...the pause fields are cleared', `${(await row(M1.deviceId)).paused_at}|${(await row(M1.deviceId)).lost_incident}`, 'null|null');
  const need = await refresh(M1);
  check('A found', 'the found phone must show its owner\'s PIN before it gets a session -> 403 pin_required', `${need.status} ${need.body?.error}`, '403 pin_required');
  const wrong = await refresh(M1, '1111');
  check('A found', '...a wrong PIN is refused and still no session', `${wrong.status} ${wrong.body?.error} ${wrong.body?.sessionToken}`, '403 pin_incorrect undefined');
  const okr = await refresh(M1, '4821');
  check('A found', '...her own PIN brings it back with a fresh session', `${okr.status} ${typeof okr.body?.sessionToken}`, '200 string');
  M1.tok = okr.body.sessionToken;
  check('A found', '...and it works again', (await ping(M1)).status, 200);
  check('A found', '...once only: the next refresh needs no PIN', (await refresh(M1)).status, 200);
  check('A found', 'the feed says it was found', (await feed(D1, CHILD_A)).includes('device_found'), 'true');
  check('A found', 'the history reads marked, found', (await events(M1.deviceId)).join(), 'marked,found');
  check('A found', 'still nothing deleted anywhere', JSON.stringify(await counts()), JSON.stringify(baseline));
}

// ===========================================================================
// B · TWO GROWN-UPS
// ===========================================================================
let inc2;
{
  const r = await mark(D1, M1.deviceId, '2468');
  check('B two', 'dad marks mom\'s phone with HIS PIN -> 201 paused', `${r.status} ${r.body?.state}`, '201 paused');
  inc2 = r.body?.incidentId;
  check('B two', 'mom\'s phone is refused', (await ping(M1)).body?.error, 'device_paused');
  check('B two', 'mom, on her other phone, is told who and when', (await call('GET', '/v1/me/devices', M2.tok)).body.devices.find((d) => d.id === M1.deviceId)?.markedByName, `Dad-${RUN}`);
  const dc = await confirm(D1, M1.deviceId, inc2, '2468');
  check('B two', 'dad cannot make it final before the 72 hours: only the owner may say "It is lost"', `${dc.status} ${dc.body?.error}`, '403 owner_only');
  check('B two', '...the phone is still only paused', (await row(M1.deviceId)).revoked_at, null);
  const df = await found(D1, M1.deviceId, inc2, '2468');
  check('B two', 'dad can bring it back (he marked it, "I have it" by any grown-up of the family)', `${df.status} ${df.body?.state}`, '200 active');
  const rr = await refresh(M1, '4821');
  M1.tok = rr.body.sessionToken;
  check('B two', 'mom must still show her own PIN on that phone', rr.status, 200);

  // a report the OWNER made cannot be undone by the other grown-up
  const own = await mark(M2, M1.deviceId);
  const inc3 = own.body.incidentId;
  const blocked = await found(D1, M1.deviceId, inc3, '2468');
  check('B two', 'mom marks her own phone; dad cannot undo her report -> 403 owner_only', `${blocked.status} ${blocked.body?.error}`, '403 owner_only');
  check('B two', '...it stays paused', (await ping(M1)).body?.error, 'device_paused');
  const cl = await confirm(M2, M1.deviceId, inc3);
  check('B two', 'mom says "It is lost" -> 200 revoked at once', `${cl.status} ${cl.body?.state}`, '200 revoked');
  const gone = await ping(M1);
  check('B two', 'the phone now gets the permanent word -> 401 device_revoked', `${gone.status} ${gone.body?.error}`, '401 device_revoked');
  const rg = await refresh(M1, '4821');
  check('B two', '...its credential is dead for good', `${rg.status} ${rg.body?.error}`, '401 device_revoked');
  const late = await found(M2, M1.deviceId, inc3);
  check('B two', 'a found answer after the cut-off is too late -> 409 too_late (it comes back by being added again)', `${late.status} ${late.body?.error}`, '409 too_late');
  check('B two', 'marking an already cut-off phone -> 409 already_revoked', (await mark(D1, M1.deviceId, '2468')).body?.error, 'already_revoked');
  check('B two', 'the feed says it was removed from the family', (await feed(D1, CHILD_A)).includes('device_lost_final'), 'true');
  check('B two', 'the history reads marked, found, marked, found, marked, confirmed', (await events(M1.deviceId)).join(), 'marked,found,marked,found,marked,confirmed');
  check('B two', 'mom\'s account, her other phone and the family are intact', `${(await ping(M2)).status} ${(await counts()).edges} ${(await counts()).kids}`, `200 ${baseline.edges} ${baseline.kids}`);
}

// the owner-marked report CAN be undone by dad once the phone it came from was itself cut off (a thief who knew the PIN)
{
  const thief = await pairPhone(M2);        // M3: "stolen", still in the thief's hand, knows the PIN
  const real = await pairPhone(M2);         // M4: mom's real phone, at home
  const t = await mark(thief, real.deviceId);   // the thief pauses her real phone, as "her"
  check('B thief-pin', 'a thief who knows the PIN pauses mom\'s real phone from the stolen one -> 201', t.status, 201);
  check('B thief-pin', '...dad cannot undo it while the stolen phone is still active (owner-marked)',
    (await found(D1, real.deviceId, t.body.incidentId, '2468')).body?.error, 'owner_only');
  const dm = await mark(D1, thief.deviceId, '2468');
  check('B thief-pin', 'dad pauses the stolen phone -> 201', dm.status, 201);
  const back = await found(D1, real.deviceId, t.body.incidentId, '2468');
  check('B thief-pin', '...now dad CAN bring mom\'s real phone back -> 200 active', `${back.status} ${back.body?.state}`, '200 active');
  check('B thief-pin', '...and the thief stays cut off', (await ping(thief)).body?.error, 'device_paused');
  await confirm(D1, thief.deviceId, dm.body.incidentId, '2468').catch(() => {});
}

// ===========================================================================
// C · THE 72 HOURS (time is injected into the pool functions)
// ===========================================================================
{
  const t0 = new Date(Date.now() + 10 * 86400000);   // far enough ahead that no earlier line is "recent"
  const mk = async () => pairPhone(M2);
  const a = await mk();
  const m = await markDeviceLost(pool, { deviceId: a.deviceId, userId: dad.userId, fromDeviceId: D1.deviceId, now: t0 });
  check('C notice', 'marked at T: paused, due exactly T + 72h', `${m.ok} ${m.state} ${new Date(m.revokeDueAt).getTime() - t0.getTime()}`, `true paused ${LOST_NOTICE_MS}`);
  check('C notice', 'at T + 71h59m the device is still paused', await pairedDeviceStanding(pool, a.deviceId, new Date(t0.getTime() + LOST_NOTICE_MS - 60000)), 'paused');
  check('C notice', 'at T + 72h it counts as revoked (the notice ended by itself)', await pairedDeviceStanding(pool, a.deviceId, new Date(t0.getTime() + LOST_NOTICE_MS)), 'revoked');
  check('C notice', '...the row was rewritten once, at exactly the deadline',
    new Date((await row(a.deviceId)).revoked_at).getTime() - t0.getTime(), LOST_NOTICE_MS);
  await pairedDeviceStanding(pool, a.deviceId, new Date(t0.getTime() + LOST_NOTICE_MS + 1000));
  await pairedDeviceStanding(pool, a.deviceId, new Date(t0.getTime() + LOST_NOTICE_MS + 5000));
  check('C notice', '...and recorded once, however many requests came after', (await events(a.deviceId)).join(), 'marked,cut_off');
  const late = await foundDevice(pool, { deviceId: a.deviceId, userId: mom.userId, fromDeviceId: M2.deviceId, incidentId: m.incidentId, now: new Date(t0.getTime() + LOST_NOTICE_MS) });
  check('C notice', '"I have it" at the last instant (T + 72h) is too late', `${late.ok} ${late.reason}`, 'false too_late');

  const b = await mk();
  const mb = await markDeviceLost(pool, { deviceId: b.deviceId, userId: dad.userId, fromDeviceId: D1.deviceId, now: t0 });
  const early = await foundDevice(pool, { deviceId: b.deviceId, userId: mom.userId, fromDeviceId: M2.deviceId, incidentId: mb.incidentId, now: new Date(t0.getTime() + LOST_NOTICE_MS - 1) });
  check('C notice', '"I have it" one millisecond before the deadline wins', `${early.ok} ${early.state}`, 'true active');
  check('C notice', '...and the device is not cut off afterwards (no stale deadline survives)',
    await pairedDeviceStanding(pool, b.deviceId, new Date(t0.getTime() + 2 * LOST_NOTICE_MS)), 'active');

  // found vs confirm at the same instant: exactly one wins, the state is whole either way
  const c = await mk();
  const mc = await markDeviceLost(pool, { deviceId: c.deviceId, userId: mom.userId, fromDeviceId: M2.deviceId, now: t0 });
  const at = new Date(t0.getTime() + 3600000);
  const res = await Promise.all([
    foundDevice(pool, { deviceId: c.deviceId, userId: mom.userId, fromDeviceId: M2.deviceId, incidentId: mc.incidentId, now: at }),
    confirmDeviceLost(pool, { deviceId: c.deviceId, userId: mom.userId, fromDeviceId: M2.deviceId, incidentId: mc.incidentId, now: at }),
  ]);
  check('C race', 'found and "It is lost" at the same instant: exactly one wins', res.filter((x) => x.ok).length, 1);
  const rc = await row(c.deviceId);
  const winner = res[0].ok ? 'found' : 'confirmed';
  check('C race', '...the device ends whole in the winner\'s state (no half-paused, half-revoked row)',
    winner === 'found' ? `${rc.paused_at}|${rc.revoked_at}` : `${rc.revoked_at !== null}`, winner === 'found' ? 'null|null' : 'true');
  check('C race', '...and exactly one answer line was written after "marked"', (await events(c.deviceId)).filter((k) => k !== 'marked').join(), winner);

  // two grown-ups mark at the same instant: one incident, one line
  const d = await mk();
  const two = await Promise.all([
    markDeviceLost(pool, { deviceId: d.deviceId, userId: mom.userId, fromDeviceId: M2.deviceId, now: t0 }),
    markDeviceLost(pool, { deviceId: d.deviceId, userId: dad.userId, fromDeviceId: D1.deviceId, now: t0 }),
  ]);
  check('C race', 'two grown-ups marking the same phone at once: one new report, one "already"', two.filter((x) => x.ok && !x.already).length + '/' + two.filter((x) => x.ok && x.already).length, '1/1');
  check('C race', '...one incident id for both', two[0].incidentId === two[1].incidentId, 'true');
  check('C race', '...one history line', (await events(d.deviceId)).join(), 'marked');
}

// ===========================================================================
// D · HOSTILE
// ===========================================================================
{
  const v = await pairPhone(M2);   // a fresh victim phone
  // a stranger family
  const s = await mark(stranger, v.deviceId, '7315');
  check('D hostile', 'a grown-up of ANOTHER family marking mom\'s phone -> 404 (same answer as an id that does not exist)', `${s.status} ${s.body?.error}`, '404 not_found');
  check('D hostile', '...or finding / confirming it', `${(await found(stranger, v.deviceId, randomUUID(), '7315')).status}/${(await confirm(stranger, v.deviceId, randomUUID(), '7315')).status}`, '404/404');
  check('D hostile', 'an id that does not exist -> 404', (await mark(M2, randomUUID())).status, 404);
  check('D hostile', 'an id that is not a uuid -> 400 bad_path (never reaches a handler)', (await mark(M2, 'not-a-uuid')).status, 400);
  check('D hostile', 'no session -> 401', (await call('POST', `/v1/me/devices/${v.deviceId}/mark-lost`, null, { pin: '4821' })).status, 401);
  check('D hostile', 'a child\'s tablet session cannot use the routes -> 403', `${(await call('POST', `/v1/me/devices/${v.deviceId}/mark-lost`, T1.tok, { pin: '4821' })).status}/${(await call('GET', '/v1/me/devices', T1.tok)).status}`, '403/403');
  check('D hostile', 'a phone cannot mark itself (it is in somebody\'s hand, not lost) -> 409 this_device', (await mark(v, v.deviceId)).body?.error, 'this_device');
  check('D hostile', 'a missing PIN -> 400 pin_required', (await call('POST', `/v1/me/devices/${v.deviceId}/mark-lost`, M2.tok, {})).body?.error, 'pin_required');
  const wrong = await mark(M2, v.deviceId, '0000');
  check('D hostile', 'a wrong PIN -> 403 and nothing changed', `${wrong.status} ${wrong.body?.error} ${(await row(v.deviceId)).paused_at}`, '403 pin_incorrect null');
  await unlockPin(mom.userId);
  check('D hostile', 'found without an incident -> 400 incident_required', (await call('POST', `/v1/me/devices/${v.deviceId}/found`, M2.tok, { pin: '4821' })).body?.error, 'incident_required');
  check('D hostile', 'found on a phone that is not marked -> 409 not_paused', (await found(M2, v.deviceId, randomUUID())).body?.error, 'not_paused');

  // replay: an old "I have it" cannot undo a newer report
  const i1 = (await mark(M2, v.deviceId)).body.incidentId;
  await found(M2, v.deviceId, i1);
  const i2 = (await mark(M2, v.deviceId)).body.incidentId;
  check('D replay', 'a second report has a new incident id', i1 !== i2, 'true');
  const replay = await found(M2, v.deviceId, i1);
  check('D replay', 'replaying the OLD "I have it" does nothing -> 409 stale_incident', `${replay.status} ${replay.body?.error}`, '409 stale_incident');
  check('D replay', '...the phone is still paused', (await ping(v)).body?.error, 'device_paused');
  check('D replay', 'replaying an old "It is lost" does nothing either', (await confirm(M2, v.deviceId, i1)).body?.error, 'stale_incident');
  check('D replay', 'a made-up incident id is refused the same way', (await found(M2, v.deviceId, randomUUID())).body?.error, 'stale_incident');
  check('D replay', 'the real one still works', (await found(M2, v.deviceId, i2)).status, 200);

  // rate limit: a loop of mark / found is a loop, not a loss
  const w = await pairPhone(M2);
  let last;
  for (let i = 0; i < LOST_MARK_LIMIT_PER_DAY; i++) {
    const m = await mark(M2, w.deviceId);
    last = m.status;
    if (m.status === 201) await found(M2, w.deviceId, m.body.incidentId);
  }
  check('D limit', `${LOST_MARK_LIMIT_PER_DAY} marks of one phone in a day are allowed`, last, 201);
  const over = await mark(M2, w.deviceId);
  check('D limit', '...the next is refused -> 429 rate_limited', `${over.status} ${over.body?.error}`, '429 rate_limited');
  check('D limit', '...and the phone was not touched by the refused one', (await row(w.deviceId)).paused_at, null);
}

// the stolen-phone race: a thief holds an UNLOCKED phone M5 (a live session, no PIN)
{
  const m5 = await pairPhone(M2);
  const burn = [];
  for (let i = 0; i < 6; i++) burn.push((await mark(m5, M2.deviceId, '0000')).body?.error);
  check('D stolen', 'the thief guesses the PIN to pause her real phone: refused, then locked', burn.slice(0, 5).every((e) => e === 'pin_incorrect') && burn[5] === 'pin_locked', 'true');
  check('D stolen', '...mom\'s real phone was never paused by the guessing', (await row(M2.deviceId)).paused_at, null);
  const noPin = await mark(M2, m5.deviceId);
  check('D stolen', 'the burned PIN also locks MOM out for a while (the honest cost) -> 403 pin_locked', `${noPin.status} ${noPin.body?.error}`, '403 pin_locked');

  // ...but the other grown-up still can, and the thief is cut off even while it is mid-flight
  const seq = [];
  let markDone = false;
  const thiefLoop = (async () => {
    for (let i = 0; i < 60; i++) {
      const startedAfterMark = markDone;   // sampled BEFORE the request: one still in flight when the mark landed may legitimately win
      const r = await ping(m5);
      seq.push({ s: r.status, afterMark: startedAfterMark });
      if (markDone && i > 3 && seq.filter((x) => x.afterMark).length >= 3) break;
    }
  })();
  const stopper = (async () => {
    await new Promise((r) => setTimeout(r, 15));
    const r = await mark(D1, m5.deviceId, '2468');
    markDone = true;
    return r;
  })();
  const [, mres] = await Promise.all([thiefLoop, stopper]);
  check('D stolen', 'the other grown-up marks the stolen phone while it is mid-flight -> 201', mres.status, 201);
  const firstBad = seq.findIndex((x) => x.s === 401);
  check('D stolen', 'its requests are 200s and then 401s, never a 200 after the first refusal',
    firstBad === -1 || seq.slice(firstBad).every((x) => x.s === 401), 'true');
  check('D stolen', 'every request started after the mark returned is refused', seq.filter((x) => x.afterMark).every((x) => x.s === 401), 'true');
  check('D stolen', 'the stolen phone cannot refresh, cannot mark, cannot find itself',
    `${(await refresh(m5)).body?.error}/${(await mark(m5, M2.deviceId)).body?.error}/${(await found(m5, m5.deviceId, mres.body.incidentId)).body?.error}`, 'device_paused/device_paused/device_paused');
  await unlockPin(mom.userId);
  const owner = await confirm(M2, m5.deviceId, mres.body.incidentId);
  check('D stolen', 'mom, once her PIN lock ends, makes it final from her real phone -> 200 revoked', `${owner.status} ${owner.body?.state}`, '200 revoked');
}

// a child's tablet
{
  const t2 = await pairTablet(M2, CHILD_A);
  const r = await mark(D1, t2.deviceId, '2468');
  check('D tablet', 'dad marks Ivy\'s tablet lost -> 201 paused', `${r.status} ${r.body?.state}`, '201 paused');
  check('D tablet', '...its next request gets the paused word (the app shows her the calm "ask a grown-up" screen, nothing else)',
    (await call('GET', `/v1/children/${CHILD_A}/inbox`, t2.tok)).body?.error, 'device_paused');
  check('D tablet', '...a stranger grown-up cannot touch it', (await mark(stranger, t2.deviceId, '7315')).status, 404);
  const cf = await confirm(M2, t2.deviceId, r.body.incidentId);
  check('D tablet', 'any grown-up of the family may make a TABLET final (it holds no one\'s PIN) -> 200 revoked', `${cf.status} ${cf.body?.state}`, '200 revoked');
  check('D tablet', '...the tablet\'s credential is dead', (await call('POST', '/v1/auth/session/refresh', null, { deviceId: t2.deviceId, deviceCredential: t2.cred })).body?.error, 'device_revoked');
  const t3 = await pairTablet(M2, CHILD_A);
  const m3 = await mark(D1, t3.deviceId, '2468');
  const f3 = await found(M2, t3.deviceId, m3.body.incidentId);
  check('D tablet', 'a found tablet comes back with no PIN of its own to show', `${f3.status} ${(await call('POST', '/v1/auth/session/refresh', null, { deviceId: t3.deviceId, deviceCredential: t3.cred })).status}`, '200 200');
}

// ===========================================================================
// E · THE LIST
// ===========================================================================
{
  const res = await call('GET', '/v1/me/devices', M2.tok);
  const list = res.body.devices;
  const ids = list.map((d) => d.id);
  check('E list', 'mom sees her own phones, dad\'s phone and the tablet', [M1, M2, D1, T1].every((d) => ids.includes(d.deviceId)), 'true');
  check('E list', '...and nothing of the stranger family', ids.includes(stranger.deviceId), 'false');
  check('E list', 'it marks which one is this phone', list.filter((d) => d.isThisDevice).map((d) => d.id).join(), M2.deviceId);
  const dd = list.find((d) => d.id === D1.deviceId);
  check('E list', 'dad\'s phone: markable, not "mine", named', `${dd.canMarkLost} ${dd.isOwn} ${dd.ownerName}`, `true false Dad-${RUN}`);
  const tt = list.find((d) => d.id === T1.deviceId);
  check('E list', 'a tablet has no owner name', `${tt.role} ${tt.ownerName}`, 'child null');
  const me = list.find((d) => d.id === M2.deviceId);
  check('E list', 'this phone cannot be marked from itself', me.canMarkLost, false);
  check('E list', 'no credential, hash or token appears anywhere in the list', /credential|hash|token|secret/i.test(JSON.stringify(res.body)), false);
  const strangerList = (await call('GET', '/v1/me/devices', stranger.tok)).body.devices.map((d) => d.id);
  check('E list', 'the stranger sees only their own family', strangerList.every((id) => id === stranger.deviceId), 'true');
  const pausedView = await (async () => {
    const x = await pairPhone(M2);
    const m = await mark(D1, x.deviceId, '2468');
    const v = (await call('GET', '/v1/me/devices', M2.tok)).body.devices.find((d) => d.id === x.deviceId);
    return `${v.state} ${v.incidentId === m.body.incidentId} ${v.canFound} ${v.canConfirmLost} ${v.markedByName === `Dad-${RUN}`}`;
  })();
  check('E list', 'a phone dad marked reads, for mom: paused, its incident, she may say "I have it" or "It is lost"', pausedView, 'paused true true true true');
}

// ===========================================================================
// G · ERASE ON NEXT CONTACT (a lost grown-up phone's own copy; the family keeps every record)
// ===========================================================================
{
  const orderW = (by, deviceId, pin = '4821') => call('POST', `/v1/me/devices/${deviceId}/order-wipe`, by.tok, { pin });
  const cancelW = (by, deviceId, pin = '4821') => call('POST', `/v1/me/devices/${deviceId}/cancel-wipe`, by.tok, { pin });
  const ackW = (deviceId, cred) => call('POST', '/v1/auth/device/wiped', null, { deviceId, deviceCredential: cred });
  const listed = async (by, id) => (await call('GET', '/v1/me/devices', by.tok)).body.devices.find((d) => d.id === id);
  const before = await counts();

  const a = await pairPhone(M2);
  check('G wipe', 'a working phone cannot be ordered erased -> 409 not_paused',
    `${(await orderW(M2, a.deviceId)).status} ${(await orderW(M2, a.deviceId)).body?.error}`, '409 not_paused');
  check('G wipe', '...and the list does not offer it', (await listed(M2, a.deviceId)).canOrderWipe, false);
  const m = await mark(M2, a.deviceId);
  check('G wipe', 'marked as lost first -> paused; now the list offers "erase it"', `${m.status} ${(await listed(M2, a.deviceId)).canOrderWipe}`, '201 true');
  check('G wipe', 'the other grown-up is not offered it', (await listed(D1, a.deviceId)).canOrderWipe, false);
  const dadTry = await orderW(D1, a.deviceId, '2468');
  check('G wipe', 'dad cannot order mom\'s phone erased -> 403 owner_only', `${dadTry.status} ${dadTry.body?.error}`, '403 owner_only');
  const strTry = await orderW(stranger, a.deviceId, '7315');
  check('G wipe', 'a stranger family gets not_found, learns nothing -> 404', `${strTry.status} ${strTry.body?.error}`, '404 not_found');
  check('G wipe', 'a child\'s tablet session cannot order anything -> 403', (await orderW(T1, a.deviceId)).status, 403);
  const badPin = await orderW(M2, a.deviceId, '9999');
  check('G wipe', 'a wrong PIN orders nothing', `${badPin.status >= 400} ${(await row(a.deviceId)).wipe_ordered_at}`, 'true null');
  await unlockPin(mom.userId);
  check('G wipe', 'the phone itself cannot be told to wipe from itself (no session, a paused phone)', (await orderW(a, a.deviceId)).status, 401);
  const noSignal = await refresh(a);
  check('G wipe', 'before any order the refusal carries no erase instruction', `${noSignal.body?.error} ${noSignal.body?.wipe}`, 'device_paused undefined');

  const o = await orderW(M2, a.deviceId);
  check('G wipe', 'mom orders it erased with her own PIN -> 201', `${o.status} ${o.body?.already}`, '201 false');
  const o2 = await orderW(M2, a.deviceId);
  check('G wipe', 'ordering again is idempotent -> 200 already, one history line', `${o2.status} ${o2.body?.already} ${(await events(a.deviceId)).join()}`, '200 true marked,wipe_ordered');
  check('G wipe', 'the family is told, in fixed words', (await feed(D1, CHILD_A)).includes('device_wipe_ordered'), 'true');
  const l1 = await listed(M2, a.deviceId);
  check('G wipe', 'the list shows it as ordered and offers only "cancel"', `${l1.wipe} ${l1.canOrderWipe} ${l1.canCancelWipe}`, 'ordered false true');
  check('G wipe', 'nothing was deleted anywhere (the server keeps every record)', JSON.stringify(await counts()), JSON.stringify({ ...before, devices: before.devices + 1 }));

  const wrongCred = await call('POST', '/v1/auth/session/refresh', null, { deviceId: a.deviceId, deviceCredential: 'x'.repeat(43) });
  check('G wipe', 'a caller without the phone\'s credential is never told to erase', `${wrongCred.body?.error} ${wrongCred.body?.wipe}`, 'invalid_device_credential undefined');
  const told = await refresh(a);
  check('G wipe', 'the phone itself, proving its credential, is told: device_paused + wipe', `${told.status} ${told.body?.error} ${told.body?.wipe}`, '401 device_paused true');
  check('G wipe', '...it gets no session', told.body?.sessionToken, undefined);
  check('G wipe', 'asking again repeats the instruction until it is done', (await refresh(a)).body?.wipe, true);

  const bad1 = await ackW(a.deviceId, 'y'.repeat(43));
  check('G wipe', 'saying "erased" with a wrong credential -> 401', `${bad1.status} ${bad1.body?.error}`, '401 invalid_device_credential');
  const bad2 = await ackW(a.deviceId, M2.cred);
  check('G wipe', 'saying "erased" with ANOTHER phone\'s credential -> 401', `${bad2.status}`, '401');
  check('G wipe', '...so it is not marked done', (await row(a.deviceId)).wiped_at, null);
  check('G wipe', 'a malformed acknowledgement -> 400', (await call('POST', '/v1/auth/device/wiped', null, { deviceId: a.deviceId })).status, 400);
  const okAck = await ackW(a.deviceId, a.cred);
  check('G wipe', 'the lost phone says it erased itself -> 200', `${okAck.status} ${okAck.body?.already}`, '200 false');
  check('G wipe', '...saying it twice is harmless -> already', `${(await ackW(a.deviceId, a.cred)).body?.already} ${(await events(a.deviceId)).join()}`, 'true marked,wipe_ordered,wiped');
  const done = await refresh(a);
  check('G wipe', 'after that the instruction stops', `${done.body?.error} ${done.body?.wipe}`, 'device_paused undefined');
  check('G wipe', 'the family is told it was erased', (await feed(D1, CHILD_A)).includes('device_wiped'), 'true');
  const l2 = await listed(M2, a.deviceId);
  check('G wipe', 'the list shows it as done and offers nothing more', `${l2.wipe} ${l2.canOrderWipe} ${l2.canCancelWipe}`, 'done false false');
  const foundW = await found(M2, a.deviceId, m.body.incidentId);
  check('G wipe', 'a phone that already erased itself cannot be "found" back: add it again as new -> 409 already_wiped', `${foundW.status} ${foundW.body?.error}`, '409 already_wiped');
  const cancelDone = await cancelW(M2, a.deviceId);
  check('G wipe', 'an erase already carried out cannot be cancelled -> 409', `${cancelDone.status} ${cancelDone.body?.error}`, '409 already_wiped');
  check('G wipe', 'no credential, hash or token appears in the list for it', !/credential|hash|token/i.test(JSON.stringify(l2)), 'true');

  // a child's tablet is never erased by a grown-up: her private areas are hers
  const tab = await pairTablet(M2, CHILD_A);
  const mt = await mark(M2, tab.deviceId);
  const ot = await orderW(M2, tab.deviceId);
  check('G tablet', 'ordering a child\'s tablet erased is refused -> 403 not_a_grown_up_phone', `${ot.status} ${ot.body?.error}`, '403 not_a_grown_up_phone');
  check('G tablet', '...the list never offers it', (await listed(M2, tab.deviceId)).canOrderWipe, false);
  check('G tablet', '...the row cannot carry an order (the table says no too)',
    await admin.query(`UPDATE paired_device SET wipe_ordered_at = now() WHERE id = $1`, [tab.deviceId]).then(() => 'accepted', () => 'refused'), 'refused');
  check('G tablet', '...and the refusal on the tablet carries no instruction', `${(await refresh(tab)).body?.error} ${(await refresh(tab)).body?.wipe}`, 'device_paused undefined');
  await found(M2, tab.deviceId, mt.body.incidentId);

  // changing one's mind: cancel, and found, both withdraw an order that was not carried out
  const b = await pairPhone(M2);
  const mb = await mark(M2, b.deviceId);
  await orderW(M2, b.deviceId);
  check('G cancel', 'dad cannot cancel mom\'s order -> 403', (await cancelW(D1, b.deviceId, '2468')).status, 403);
  const c1 = await cancelW(M2, b.deviceId);
  check('G cancel', 'mom cancels it -> 200', c1.status, 200);
  check('G cancel', '...the phone is no longer told to erase', `${(await refresh(b)).body?.error} ${(await refresh(b)).body?.wipe}`, 'device_paused undefined');
  check('G cancel', '...cancelling again -> 409 no_wipe_ordered', `${(await cancelW(M2, b.deviceId)).status} ${(await cancelW(M2, b.deviceId)).body?.error}`, '409 no_wipe_ordered');
  check('G cancel', '...an "erased" report with no order is refused -> 409', `${(await ackW(b.deviceId, b.cred)).status} ${(await ackW(b.deviceId, b.cred)).body?.error}`, '409 no_wipe_ordered');
  await orderW(M2, b.deviceId);
  const fb = await found(M2, b.deviceId, mb.body.incidentId);
  check('G cancel', 'order again, then "I have it": the order is withdrawn with it', `${fb.status} ${(await row(b.deviceId)).wipe_ordered_at} ${(await row(b.deviceId)).wiped_at}`, '200 null null');
  check('G cancel', '...history records the withdrawal', (await events(b.deviceId)).join(), 'marked,wipe_ordered,wipe_cancelled,wipe_ordered,found,wipe_cancelled');
  const back = await refresh(b, '4821');
  check('G cancel', '...the phone comes back normally (own PIN once) and was never told to erase', `${back.status} ${back.body?.wipe}`, '200 undefined');
  check('G cancel', '...an "erased" report from a working phone is refused -> 409', (await ackW(b.deviceId, b.cred)).status, 409);

  // after "It is lost" (cut off for good) the order still goes out, with the permanent word
  const c = await pairPhone(M2);
  const mc = await mark(M2, c.deviceId);
  await confirm(M2, c.deviceId, mc.body.incidentId);
  const oc = await orderW(M2, c.deviceId);
  check('G revoked', 'a phone cut off for good can still be ordered erased -> 201', `${oc.status} ${oc.body?.state}`, '201 revoked');
  const tc = await refresh(c);
  check('G revoked', '...it is told, with the permanent word', `${tc.body?.error} ${tc.body?.wipe}`, 'device_revoked true');
  // a phone that merely signed itself out was never reported lost: no erase order
  const d2 = await pairPhone(M2);
  await call('POST', '/v1/auth/session/sign-out', d2.tok, {});
  check('G revoked', 'a phone that only signed itself out cannot be ordered erased -> 409 not_paused', (await orderW(M2, d2.deviceId)).body?.error, 'not_paused');

  // the notice running out by itself does not stop an order from being placed or delivered
  const t0 = new Date(Date.now() + 30 * 86400000);
  const e = await pairPhone(M2);
  const me = await markDeviceLost(pool, { deviceId: e.deviceId, userId: mom.userId, fromDeviceId: M2.deviceId, now: t0 });
  const oe = await orderDeviceWipe(pool, { deviceId: e.deviceId, userId: mom.userId, fromDeviceId: M2.deviceId, now: new Date(t0.getTime() + LOST_NOTICE_MS + 1000) });
  check('G notice', 'ordered after the 72 hours ran out: still accepted, state revoked', `${me.ok} ${oe.ok} ${oe.state}`, 'true true revoked');
  const oe2 = await orderDeviceWipe(pool, { deviceId: e.deviceId, userId: dad.userId, fromDeviceId: D1.deviceId, now: new Date(t0.getTime() + LOST_NOTICE_MS + 2000) });
  check('G notice', '...and dad still may not, pool level too', `${oe2.ok} ${oe2.reason}`, 'false owner_only');
  const refused = await acknowledgeDeviceWiped(pool, e.deviceId, 'z'.repeat(43), new Date());
  check('G notice', 'the acknowledgement function itself refuses a wrong credential', `${refused.ok} ${refused.reason}`, 'false invalid_device_credential');

  // a race: "I have it" and "erase it" at the same instant leave one whole state
  const f = await pairPhone(M2);
  const mf = await mark(M2, f.deviceId);
  const [rf, ro] = await Promise.all([
    call('POST', `/v1/me/devices/${f.deviceId}/found`, M2.tok, { pin: '4821', incidentId: mf.body.incidentId }),
    orderW(M2, f.deviceId),
  ]);
  const frow = await row(f.deviceId);
  const consistent = (rf.status === 200 && frow.paused_at === null && frow.wipe_ordered_at === null) ||
    (rf.status !== 200 && frow.paused_at !== null);
  check('G race', '"I have it" racing "erase it": never found AND ordered erased', `${consistent} ${!(frow.paused_at === null && frow.wipe_ordered_at !== null)}`, 'true true');

  check('G wipe', 'through all of this: no grown-up, child or edge was removed, only the phones added',
    `${(await counts()).edges} ${(await counts()).kids}`, `${before.edges} ${before.kids}`);
}

// ===========================================================================
// F · STORAGE
// ===========================================================================
{
  const ev = (await admin.query(`SELECT seq FROM device_lost_event LIMIT 1`)).rowCount;
  check('F storage', 'the history table has lines', ev > 0, 'true');
  check('F storage', 'a history line cannot be edited, even by the table owner',
    await admin.query(`UPDATE device_lost_event SET kind = 'found' WHERE seq = (SELECT min(seq) FROM device_lost_event)`).then(() => 'edited', () => 'refused'), 'refused');
  check('F storage', '...or deleted', await admin.query(`DELETE FROM device_lost_event WHERE seq = (SELECT min(seq) FROM device_lost_event)`).then(() => 'deleted', () => 'refused'), 'refused');
  check('F storage', 'a pause with no incident is refused by the table',
    await admin.query(`UPDATE paired_device SET paused_at = now() WHERE id = $1`, [M2.deviceId]).then(() => 'accepted', () => 'refused'), 'refused');
  check('F storage', 'a deadline before the pause began is refused too',
    await admin.query(`UPDATE paired_device SET paused_at = now(), lost_incident = $2, lost_revoke_due_at = now() - interval '1 hour' WHERE id = $1`, [M2.deviceId, randomUUID()]).then(() => 'accepted', () => 'refused'), 'refused');
  const strangerSees = await withSession(pool, { roleName: 'guardian', userId: stranger.userId, childId: null },
    (q) => q(`SELECT count(*)::int n FROM device_lost_event WHERE device_id = $1`, [M1.deviceId]));
  check('F storage', 'a stranger\'s session reads none of mom\'s history', strangerSees[0].n, 0);
  const momSees = await withSession(pool, { roleName: 'guardian', userId: mom.userId, childId: null },
    (q) => q(`SELECT count(*)::int n FROM device_lost_event WHERE device_id = $1`, [M1.deviceId]));
  check('F storage', 'mom\'s session reads it', momSees[0].n > 0, 'true');
  let wrote = 'wrote';
  try {
    await withSession(pool, { roleName: 'guardian', userId: mom.userId, childId: null },
      (q) => q(`INSERT INTO device_lost_event (device_id, incident_id, kind) VALUES ($1, $2, 'found')`, [M2.deviceId, randomUUID()]));
  } catch { wrote = 'refused'; }
  check('F storage', 'a guardian session cannot write history lines itself (only the pool functions can)', wrote, 'refused');
  check('F storage', 'the feed lines are fixed words with no names, places or device labels',
    (await admin.query(`SELECT summary FROM security_event WHERE kind IN ('device_lost','device_found','device_lost_final') AND actor_id = ANY($1::uuid[])`, [users])).rows.every((r) => !/Mom|Dad|Phone|Ivy/.test(r.summary)), 'true');
}

// ---------------------------------------------------------------------------
// cleanup: everything this run created, by id
await setSignupPolicy(pool, { enabled: true, maxAccounts: null });
const allUsers = (await admin.query(`SELECT id FROM app_user WHERE display_name LIKE ANY($1::text[])`, [[`%-${RUN}`]])).rows.map((r) => r.id);
const ids = [...new Set([...users, ...allUsers])];
await admin.query(`DELETE FROM security_event WHERE actor_id = ANY($1::uuid[])`, [ids]).catch(() => {});
await admin.query(`UPDATE paired_device SET lost_marked_from = NULL WHERE target_id = ANY($1::uuid[]) OR target_id = ANY($2::uuid[])`, [ids, children]);
await admin.query(`DELETE FROM paired_device WHERE target_id = ANY($1::uuid[]) OR target_id = ANY($2::uuid[])`, [ids, children]);
await admin.query(`DELETE FROM device_pairing_code WHERE created_by = ANY($1::uuid[])`, [ids]);
await admin.query(`DELETE FROM guardian_invite WHERE child_id = ANY($1::uuid[])`, [children]);
await admin.query(`DELETE FROM child WHERE id = ANY($1::uuid[])`, [children]);
await admin.query(`DELETE FROM app_user WHERE id = ANY($1::uuid[])`, [ids]);
await admin.query(`DELETE FROM signup_allowance WHERE label LIKE $1`, [`${LABEL}%`]);
await admin.end();
await pool.end();
await fs.rm(tmpRoot, { recursive: true, force: true });

let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
