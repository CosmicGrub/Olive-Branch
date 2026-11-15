/**
 * The live chain, over REAL HTTP against the REAL booted server process
 * (node server/index.mjs, NO DEV_LOGIN) and REAL Postgres, with a REAL HTTP
 * server standing in for Google (OAuth + FCM v1) so the exact bytes the sender
 * puts on the wire are what is asserted -- not a mocked fetch:
 *
 *   A  sign-up (operator allowance) -> first child -> pair a child device ->
 *      register push tokens (creating the child seeds her day-parts: no test
 *      inserts any, so a bedtime message materializes for a real family; the
 *      clock-dependent stages only MOVE those seeded rows, see windowsFor())
 *   B  a guardian SENDS (media upload + message), the child sees nothing yet,
 *      the ONE delivery worker (scheduler.mjs `deliver`) runs, and only then
 *      does the child's inbox show it and "opened" work; no direct state inserts
 *   C  the wake-up push: the exact FCM v1 body, content-free, only the child's
 *      device, once per child per sweep, never repeated
 *   D  hostile/edge delivery: a stranger's inbox, an expired intent, two
 *      concurrent workers (no double delivery), quiet hours (delivered, not
 *      woken), a dead token (pruned) and a failing device (does not abort the
 *      others), DELIVERY_PUSH=off (delivered, no push); the server process is
 *      started with DELIVERY_IN_SERVER=0 so THIS test drives the worker
 *   E  calls: real names, ringState, call_log written first (a failing insert
 *      rings nobody), answered/cancelled/declined reasons, call_cancelled push,
 *      stale-call sweep and the max-age join refusal, availability
 *   F  operator surface: /internal/metrics push state with no secret in it
 */
import pg from 'pg';
import http from 'node:http';
import net from 'node:net';
import { spawn } from 'node:child_process';
import { once } from 'node:events';
import { randomBytes, generateKeyPairSync, createVerify } from 'node:crypto';
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createPool, issueSignupAllowance, setSignupPolicy, endStaleCalls } from '../../packages/db/src/pool.mjs';
import { runNamedJob, runDeliverSweep, runRematerializeSweep } from '../../tools/scheduler.mjs';
import { notifyDevices } from '../../packages/transport/src/notify.mjs';
import { randomUUID } from 'node:crypto';

const DATABASE_URL = process.env.DATABASE_URL;
const ADMIN_DATABASE_URL = process.env.ADMIN_DATABASE_URL ?? DATABASE_URL;
if (!DATABASE_URL) {
  console.error('DATABASE_URL required -- this suite needs a real Postgres, not a fake.');
  process.exit(2);
}
let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) }); };

const INDEX = fileURLToPath(new URL('../index.mjs', import.meta.url));
const hex = () => randomBytes(32).toString('hex');
const pool = createPool(DATABASE_URL);
const admin = new pg.Client({ connectionString: ADMIN_DATABASE_URL });
await admin.connect();
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const RUN = randomUUID().slice(0, 8);
const deliverSweep = (p, o = {}) => runDeliverSweep(p, { notify: notifyDevices, ...o });
await setSignupPolicy(pool, { enabled: true, maxAccounts: null });

// ------------------------------------------------------- stub Google --------
const fcmSends = [];      // { path, auth, body }
const oauthHits = [];
const stub = http.createServer((req, res) => {
  let raw = '';
  req.on('data', (d) => { raw += d; });
  req.on('end', () => {
    if (req.url === '/token') {
      oauthHits.push(raw);
      res.writeHead(200, { 'content-type': 'application/json' });
      return res.end(JSON.stringify({ access_token: 'stub-access', expires_in: 3600 }));
    }
    const body = JSON.parse(raw || '{}');
    fcmSends.push({ path: req.url, auth: req.headers.authorization, body });
    const tok = body?.message?.token ?? '';
    if (tok.includes('dead')) {
      res.writeHead(404, { 'content-type': 'application/json' });
      return res.end(JSON.stringify({ error: { status: 'NOT_FOUND', details: [{ errorCode: 'UNREGISTERED' }] } }));
    }
    if (tok.includes('boom')) {
      res.writeHead(500, { 'content-type': 'application/json' });
      return res.end(JSON.stringify({ error: { status: 'INTERNAL' } }));
    }
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ name: `projects/olive-test/messages/${fcmSends.length}` }));
  });
});
stub.listen(0, '127.0.0.1'); await once(stub, 'listening');
const STUB = `http://127.0.0.1:${stub.address().port}`;

const { privateKey, publicKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
const tmp = mkdtempSync(join(tmpdir(), 'olive-push-e2e-'));
const SA_FILE = join(tmp, 'sa.json');
// assembled, not written out: a reserved, undeliverable service-account name, nobody's mailbox
const AT = String.fromCharCode(64);
const SA = { client_email: `olive-push${AT}olive-test.iam.gserviceaccount.test`,
  private_key: privateKey.export({ type: 'pkcs8', format: 'pem' }),
  project_id: 'olive-test', token_uri: `${STUB}/token` };
writeFileSync(SA_FILE, JSON.stringify(SA));
const sendsTo = (tok) => fcmSends.filter((s) => s.body?.message?.token === tok);

// the in-process scheduler uses THIS process's env; the server subprocess gets the same
process.env.NODE_ENV = 'test';
process.env.FCM_SERVICE_ACCOUNT_FILE = SA_FILE;
process.env.FCM_API_BASE_URL = STUB;
delete process.env.FCM_SERVICE_ACCOUNT_JSON;
delete process.env.DELIVERY_PUSH;

// ----------------------------------------------- the real server process ---
async function freePort() {
  const s = net.createServer(); s.listen(0, '127.0.0.1'); await once(s, 'listening');
  const p = s.address().port; s.close(); await once(s, 'close'); return p;
}
const port = await freePort();
const mediaRoot = join(tmp, 'media');
const JITSI_SECRET = hex();
const child = spawn(process.execPath, [INDEX], {
  env: { PATH: process.env.PATH, SystemRoot: process.env.SystemRoot, PORT: String(port), DATABASE_URL,
    SESSION_SECRET: hex(), MEDIA_SIGNING_SECRET: hex(), NODE_ENV: 'development', ALLOW_OWNER_DB_ROLE: '1',
    DELIVERY_IN_SERVER: '0',
    MEDIA_STORAGE_ROOT: mediaRoot, FCM_SERVICE_ACCOUNT_FILE: SA_FILE, FCM_API_BASE_URL: STUB,
    CALL_PROVIDER: 'jitsi', JITSI_APP_ID: 'olive-e2e', JITSI_APP_SECRET: JITSI_SECRET,
    JITSI_SERVER_URL: 'https://meet.example.test' },
  stdio: ['ignore', 'pipe', 'pipe'] });
let out = '', err = '';
child.stdout.on('data', (d) => { out += d; }); child.stderr.on('data', (d) => { err += d; });
const up = await new Promise((resolve) => {
  const iv = setInterval(() => { if (/listening on/.test(out)) { clearInterval(iv); resolve('up'); } }, 25);
  child.on('exit', (c) => { clearInterval(iv); resolve(`exit:${c}`); });
  setTimeout(() => { clearInterval(iv); resolve('timeout'); }, 20000);
});
check('A boot', 'the real server boots with no DEV_LOGIN', up, 'up');
check('A boot', 'it logs the push state as booleans only', /push: \{"androidRing":"ready","fcm":\{"configured":true,"source":"file"\}/.test(out), true);
if (up !== 'up') { console.error(err); }

const req = async (method, path, { body, token } = {}) => {
  const r = await fetch(`http://127.0.0.1:${port}${path}`, { method,
    headers: { ...(body !== undefined ? { 'content-type': 'application/json' } : {}),
               ...(token ? { authorization: `Bearer ${token}` } : {}) },
    body: body === undefined ? undefined : JSON.stringify(body) });
  const text = await r.text(); let json = null; try { json = JSON.parse(text); } catch { /* */ }
  return { status: r.status, body: json, text };
};
const created = { users: [], children: [] };

/** Signs a family up over HTTP (allowance -> account + PIN + device -> first child), pairs a child device. */
async function newFamily(label, { guardianName = 'Alex Morgan', childName = 'Robin' } = {}) {
  const { token: allowance } = await issueSignupAllowance(pool, { label: `pushe2e-${RUN}` });
  const e = await req('POST', '/v1/auth/signup', { body: { allowanceToken: allowance, displayName: guardianName,
    homeTz: 'America/Chicago', pin: '2468', deviceLabel: 'e2e phone' } });
  if (e.status !== 201) throw new Error(`sign-up failed ${e.status} ${e.text}`);
  const f = { userId: e.body.userId, gTok: e.body.token, deviceId: e.body.deviceId, cred: e.body.deviceCredential };
  created.users.push(f.userId);
  const k = await req('POST', '/v1/children', { token: f.gTok, body: { displayName: childName,
    birthDate: '2018-05-17', homeTz: 'America/Chicago', pin: '2468' } });
  if (k.status !== 201) throw new Error(`child failed ${k.status} ${k.text}`);
  f.childId = k.body.child.id; created.children.push(f.childId);
  const pc = await req('POST', `/v1/children/${f.childId}/device-pairing-codes`, { body: { pin: '2468' }, token: f.gTok });
  const cr = await req('POST', '/v1/device-pairing/redeem', { body: { code: pc.body.numericCode, role: 'child' } });
  f.kTok = cr.body.sessionToken;
  return f;
}
const dayPartsOf = async (childId) => (await admin.query(
  `SELECT kind, to_char(starts_local,'HH24:MI') AS s, to_char(ends_local,'HH24:MI') AS e, reachable
     FROM day_part WHERE child_id = $1 ORDER BY kind`, [childId])).rows;
// The whole-day window for ONE kind, for the stages that must not depend on the wall clock
// (quiet hours, a push that must wake). Replaces the day-parts enrolment seeded for this
// child: the default kinds would otherwise overlap the new one and the test would be at
// the mercy of the hour it runs at.
const allDay = async (childId, kind, reachable) => {
  await admin.query(`DELETE FROM day_part WHERE child_id = $1`, [childId]);
  await admin.query(
    `INSERT INTO day_part (child_id, kind, starts_local, ends_local, days_of_week, reachable, effective)
     VALUES ($1, $2, '00:00', '23:59:59', '{0,1,2,3,4,5,6}', $3, '[2020-01-01,2099-01-01)')`,
    [childId, kind, reachable]);
};
// Moves the bedtime window that enrolment SEEDED so it started 30 minutes ago in the child's zone
// (clipped at midnight) and removes the unreachable night, so a message sent now (policy
// at_daypart) materialises to a past-but-within-grace instant and is due at once, whatever the
// hour: the chain runs with the real policy, not with a hand-set scheduled_at. It edits rows
// that exist; it does not create the child's day-parts.
const windowsFor = async (childId) => {
  const moved = await admin.query(
    `UPDATE day_part SET
       starts_local = CASE WHEN (now() AT TIME ZONE 'America/Chicago')::time < time '00:30' THEN time '00:00'
                           ELSE (now() AT TIME ZONE 'America/Chicago')::time - interval '30 minutes' END,
       ends_local = '23:59:59'
     WHERE child_id = $1 AND kind = 'bedtime'`, [childId]);
  await admin.query(`DELETE FROM day_part WHERE child_id = $1 AND kind = 'asleep'`, [childId]);
  return moved.rowCount;
};
const MP4 = Buffer.concat([Buffer.from([0, 0, 0, 0x18]), Buffer.from('ftypisom'), Buffer.alloc(32, 7)]);
const sendMessage = async (f) => {
  const up2 = await req('POST', `/v1/children/${f.childId}/media`, { body: { bytes: MP4.toString('base64') }, token: f.gTok });
  const m = await req('POST', `/v1/children/${f.childId}/messages`, { body: { storageKey: up2.body.storageKey, durationMs: 4200, daypart: 'bedtime' }, token: f.gTok });
  return { up: up2, m };
};
const intentState = async (id) => (await admin.query(`SELECT state FROM delivery_intent WHERE id = $1`, [id])).rows[0]?.state;

// ===========================================================================
// A · enrol -> pair -> register tokens
// ===========================================================================
const fam = await newFamily('push-e2e');
check('A chain', 'a family exists from an empty start with no dev-login and no hand-inserted row', typeof fam.childId, 'string');
const refresh = await req('POST', '/v1/auth/session/refresh', { body: { deviceId: fam.deviceId, deviceCredential: fam.cred } });
check('A chain', 'its device credential refreshes into a session', refresh.status, 200);
const kidTokenReg = await req('POST', '/v1/me/device-tokens', { body: { platform: 'android', token: 'child-fcm-token-1' }, token: fam.kTok });
const dadTokenReg = await req('POST', '/v1/me/device-tokens', { body: { platform: 'android', token: 'guardian-fcm-token-1' }, token: fam.gTok });
check('A chain', 'the child device and the guardian device register push tokens', `${kidTokenReg.status}/${dadTokenReg.status}`, '200/200');
const seeded = await dayPartsOf(fam.childId);
check('A chain', 'creating the child seeded her day-parts (nothing in this test inserted them)',
  seeded.map((r) => `${r.kind}:${r.s}-${r.e}:${r.reachable}`).join(' '),
  'asleep:20:30-06:30:false bedtime:19:30-20:30:true free:08:00-19:30:true wake:06:30-08:00:true');
check('A chain', 'the seeded bedtime window can be moved for the clock-independent stages', await windowsFor(fam.childId), 1);

// ===========================================================================
// B · send -> nothing yet -> worker -> delivered -> opened
// ===========================================================================
let intentId;
{
  const g = 'B delivery';
  const { m } = await sendMessage(fam);
  check(g, 'the guardian sends a message: 201, stored ready at send time', `${m.status}/${m.body?.state}`, '201/ready');
  intentId = m.body.id;
  const before = await req('GET', `/v1/children/${fam.childId}/inbox`, { token: fam.kTok });
  check(g, 'BEFORE the worker the child sees nothing', before.body.entries.length, 0);
  const r1 = await runRematerializeSweep(pool, {});
  check(g, 'the nightly rematerialize sweep leaves a timed message alone', await intentState(intentId), 'ready');
  const stillNothing = await req('GET', `/v1/children/${fam.childId}/inbox`, { token: fam.kTok });
  check(g, '"ready" is still not visible to the child', stillNothing.body.entries.length, 0);

  fcmSends.length = 0;
  const run = await runNamedJob(pool, DATABASE_URL, 'deliver');
  check(g, 'the deliver job runs under its advisory lock and reports ok', JSON.stringify(run), '{"ok":true,"skipped":false}');
  check(g, 'the intent is now delivered', await intentState(intentId), 'delivered');
  const inbox = await req('GET', `/v1/children/${fam.childId}/inbox`, { token: fam.kTok });
  check(g, 'the child inbox shows exactly that message', inbox.body.entries.map((e) => e.id).join(','), intentId);
  const opened = await req('POST', `/v1/children/${fam.childId}/inbox/${intentId}/opened`, { token: fam.kTok });
  check(g, '"opened" works on it', opened.status, 200);
  check(g, 'and the state is opened', await intentState(intentId), 'opened');
  const again = await deliverSweep(pool, {});
  check(g, 'a second sweep delivers nothing more', again.delivered, 0);
}

// ===========================================================================
// B2 · a freshly enrolled family, with NOTHING adjusted, is schedulable
// ===========================================================================
{
  const g = 'B2 default day-parts';
  const fresh = await newFamily('push-e2e-defaults', { guardianName: 'Dana', childName: 'Wren' });
  const { m } = await sendMessage(fresh);
  check(g, 'a bedtime message to a family that only ever signed up is accepted and timed (ready)', `${m.status}/${m.body?.state}`, '201/ready');
  const at = (await admin.query(
    `SELECT to_char(scheduled_at AT TIME ZONE 'America/Chicago', 'HH24:MI') AS t FROM delivery_intent WHERE id = $1`,
    [m.body.id])).rows[0].t;
  check(g, 'scheduled for her seeded bedtime, 19:30 her time', at, '19:30');
  // retire it so no later sweep in this run depends on the hour
  await admin.query(`UPDATE delivery_intent SET state = 'revoked' WHERE id = $1`, [m.body.id]);
}

// ===========================================================================
// C · the wake-up push, byte for byte
// ===========================================================================
{
  const g = 'C push';
  const toKid = sendsTo('child-fcm-token-1');
  check(g, 'the child device got exactly one push', toKid.length, 1);
  check(g, 'the guardian device got none (message_ready targets the child)', sendsTo('guardian-fcm-token-1').length, 0);
  const s = toKid[0];
  check(g, 'the FCM v1 path names the project', s.path, '/v1/projects/olive-test/messages:send');
  check(g, 'it carries the OAuth bearer the stub issued', s.auth, 'Bearer stub-access');
  check(g, 'the OAuth assertion is a real RS256 JWT verifiable with the public key', (() => {
    const a = new URLSearchParams(oauthHits[0]).get('assertion');
    const [h, p, sig] = a.split('.');
    const v = createVerify('RSA-SHA256'); v.update(`${h}.${p}`);
    return v.verify(publicKey, Buffer.from(sig, 'base64url'));
  })(), true);
  const m = s.body.message;
  check(g, 'data is exactly {kind, ref, v}', JSON.stringify(Object.keys(m.data).sort()), '["kind","ref","v"]');
  check(g, 'kind is message_ready and ref is the opaque intent id', `${m.data.kind}/${m.data.ref === intentId}`, 'message_ready/true');
  check(g, 'the banner is the approved generic constant', JSON.stringify(m.notification), '{"title":"Olive","body":"Something new is waiting for you."}');
  check(g, 'high priority on the reminders channel with a collapse key', `${m.android.priority}/${m.android.notification.channel_id}/${m.android.collapse_key}`, 'HIGH/reminders/message_ready');
  const wire = JSON.stringify(s.body);
  check(g, 'no name, caption, storage key, bytes or location appears anywhere on the wire',
    ['Alex', 'Morgan', 'Robin', 'children/', fam.childId, fam.userId, 'latitude', 'caption', 'storageKey'].some((n) => wire.includes(n)), false);
  check(g, 'only one OAuth mint served the whole run (token cached)', oauthHits.length, 1);
}

// ===========================================================================
// D · hostile and edge delivery
// ===========================================================================
{
  const g = 'D edge';
  // wrong child: another family's child cannot read this inbox
  const other = await newFamily('push-e2e-other', { guardianName: 'Sam', childName: 'Kit' });
  const cross = await req('GET', `/v1/children/${fam.childId}/inbox`, { token: other.kTok });
  check(g, "another family's child device is refused this inbox", cross.status === 403 || cross.status === 404, true);
  const crossGuardian = await req('POST', `/v1/children/${fam.childId}/messages`, { body: { storageKey: `children/${fam.childId}/messages/x`, durationMs: 100 }, token: other.gTok });
  check(g, "another family's guardian cannot send to this child", crossGuardian.status === 403 || crossGuardian.status === 404, true);

  // expired: a ready intent past its retention window is retired, never delivered or pushed
  const art = await admin.query(`INSERT INTO media_artifact (child_id, author_id, kind, storage_key, captured_at, captured_tz, expires_at)
    VALUES ($1,$2,'video_msg','dev/x',now(),'America/Chicago',now() + interval '1 day') RETURNING id`, [other.childId, other.userId]);
  const exp = await admin.query(`INSERT INTO delivery_intent (child_id, sender_id, payload_kind, payload_ref, policy, state, scheduled_at, expires_at)
    VALUES ($1,$2,'video_msg',$3,'immediate','ready', now() - interval '2 hours', now() - interval '1 hour') RETURNING id`, [other.childId, other.userId, art.rows[0].id]);
  await req('POST', '/v1/me/device-tokens', { body: { platform: 'android', token: 'other-child-token' }, token: other.kTok });
  fcmSends.length = 0;
  const r = await deliverSweep(pool, {});
  check(g, 'an expired intent is retired, not delivered', await intentState(exp.rows[0].id), 'expired');
  check(g, '...and counted as expired', r.expired >= 1, true);
  check(g, '...and no push went out for it', sendsTo('other-child-token').length, 0);

  // concurrency: 24 due intents, two workers at once -> each delivered exactly once
  const ids = [];
  for (let i = 0; i < 24; i++) {
    ids.push((await admin.query(`INSERT INTO delivery_intent (child_id, sender_id, payload_kind, payload_ref, policy, state, scheduled_at, expires_at)
      VALUES ($1,$2,'video_msg',$3,'immediate','ready', now() - interval '1 minute', now() + interval '1 day') RETURNING id`,
      [other.childId, other.userId, art.rows[0].id])).rows[0].id);
  }
  fcmSends.length = 0;
  const [w1, w2, w3] = await Promise.all([deliverSweep(pool, { limit: 10 }), deliverSweep(pool, { limit: 10 }), deliverSweep(pool, { limit: 10 })]);
  const delivered = w1.delivered + w2.delivered + w3.delivered;
  const rest = await deliverSweep(pool, { limit: 100 });
  check(g, 'three concurrent workers + a mop-up deliver all 24, none twice', delivered + rest.delivered, 24);
  const states = (await admin.query(`SELECT state, count(*)::int AS n FROM delivery_intent WHERE id = ANY($1::uuid[]) GROUP BY state`, [ids])).rows;
  check(g, 'all 24 are delivered', JSON.stringify(states), '[{"state":"delivered","n":24}]');
  check(g, 'the child was woken once per sweep that delivered something, never once per message',
    sendsTo('other-child-token').length <= 4, true);

  // quiet hours: delivered, but not woken
  const quiet = await newFamily('push-e2e-quiet', { guardianName: 'Quinn', childName: 'Sleepy' });
  await allDay(quiet.childId, 'asleep', false);
  await req('POST', '/v1/me/device-tokens', { body: { platform: 'android', token: 'quiet-child-token' }, token: quiet.kTok });
  const qi = await admin.query(`INSERT INTO delivery_intent (child_id, sender_id, payload_kind, payload_ref, policy, state, scheduled_at, expires_at)
    VALUES ($1,$2,'video_msg',$3,'immediate','ready', now() - interval '1 minute', now() + interval '1 day') RETURNING id`, [quiet.childId, quiet.userId, art.rows[0].id]);
  fcmSends.length = 0;
  const qr = await deliverSweep(pool, {});
  check(g, 'a message due in quiet hours is still delivered', await intentState(qi.rows[0].id), 'delivered');
  check(g, '...but the sleeping child is not woken', sendsTo('quiet-child-token').length, 0);
  check(g, '...and the sweep counts it as silent', qr.silent >= 1, true);
  const qInbox = await req('GET', `/v1/children/${quiet.childId}/inbox`, { token: quiet.kTok });
  check(g, '...and she finds it when she opens the app', qInbox.body.entries.length, 1);

  // a dead token is pruned; a failing device does not abort the others
  const mixed = await newFamily('push-e2e-mixed', { guardianName: 'Max', childName: 'Mixy' });
  await allDay(mixed.childId, 'bedtime', true);
  for (const t of ['mixed-dead-token', 'mixed-boom-token', 'mixed-good-token']) {
    await req('POST', '/v1/me/device-tokens', { body: { platform: 'android', token: t }, token: mixed.kTok });
  }
  await admin.query(`INSERT INTO delivery_intent (child_id, sender_id, payload_kind, payload_ref, policy, state, scheduled_at, expires_at)
    VALUES ($1,$2,'video_msg',$3,'immediate','ready', now() - interval '1 minute', now() + interval '1 day')`, [mixed.childId, mixed.userId, art.rows[0].id]);
  fcmSends.length = 0;
  const mr = await deliverSweep(pool, {});
  check(g, 'the good device is woken even though two siblings fail', sendsTo('mixed-good-token').length, 1);
  check(g, 'all three were attempted', ['mixed-dead-token', 'mixed-boom-token', 'mixed-good-token'].every((t) => sendsTo(t).length === 1), true);
  const left = (await admin.query(`SELECT token FROM device_token WHERE owner_child_id = $1 ORDER BY token`, [mixed.childId])).rows.map((r2) => r2.token);
  check(g, 'UNREGISTERED prunes only the dead token', left.join(','), 'mixed-boom-token,mixed-good-token');
  check(g, 'and the sweep did not throw', mr.pushFailed, 0);

  // DELIVERY_PUSH=off still delivers
  const off = await admin.query(`INSERT INTO delivery_intent (child_id, sender_id, payload_kind, payload_ref, policy, state, scheduled_at, expires_at)
    VALUES ($1,$2,'video_msg',$3,'immediate','ready', now() - interval '1 minute', now() + interval '1 day') RETURNING id`, [mixed.childId, mixed.userId, art.rows[0].id]);
  fcmSends.length = 0;
  const offRun = await deliverSweep(pool, { env: { DELIVERY_PUSH: 'off' } });
  check(g, 'DELIVERY_PUSH=off still delivers', await intentState(off.rows[0].id), 'delivered');
  check(g, '...and sends nothing', `${fcmSends.length}/${offRun.pushed}`, '0/0');

  // a notify that throws is isolated per child
  const boom = await admin.query(`INSERT INTO delivery_intent (child_id, sender_id, payload_kind, payload_ref, policy, state, scheduled_at, expires_at)
    VALUES ($1,$2,'video_msg',$3,'immediate','ready', now() - interval '1 minute', now() + interval '1 day'), ($4,$5,'video_msg',$3,'immediate','ready', now() - interval '1 minute', now() + interval '1 day') RETURNING id`,
    [quiet.childId, quiet.userId, art.rows[0].id, mixed.childId, mixed.userId]);
  let calls = 0;
  const iso = await deliverSweep(pool, { notify: async () => { calls++; if (calls === 1) throw new Error('boom'); return [{ ok: true }]; } });
  check(g, 'one child\'s failing push does not stop the next child', `${iso.pushFailed}/${iso.pushed}/${calls}`, '1/1/2');
  check(g, 'both messages are delivered regardless', (await intentState(boom.rows[0].id)) === 'delivered' && (await intentState(boom.rows[1].id)) === 'delivered', true);

  // the unconfigured path: no credential -> a clean per-device failure, delivery unaffected
  const savedFile = process.env.FCM_SERVICE_ACCOUNT_FILE;
  delete process.env.FCM_SERVICE_ACCOUNT_FILE;
  const nc = await admin.query(`INSERT INTO delivery_intent (child_id, sender_id, payload_kind, payload_ref, policy, state, scheduled_at, expires_at)
    VALUES ($1,$2,'video_msg',$3,'immediate','ready', now() - interval '1 minute', now() + interval '1 day') RETURNING id`, [mixed.childId, mixed.userId, art.rows[0].id]);
  fcmSends.length = 0;
  const ncRun = await deliverSweep(pool, {});
  process.env.FCM_SERVICE_ACCOUNT_FILE = savedFile;
  check(g, 'with push unconfigured the message is still delivered', await intentState(nc.rows[0].id), 'delivered');
  check(g, '...nothing was sent and the sweep did not crash', `${fcmSends.length}/${ncRun.pushFailed}`, '0/0');
  fam.other = other; fam.quiet = quiet; fam.mixed = mixed;
}

// ===========================================================================
// E · calls
// ===========================================================================
{
  const g = 'E calls';
  const jwtName = (jwt) => JSON.parse(Buffer.from(jwt.split('.')[1], 'base64url').toString()).context.user.name;
  fcmSends.length = 0;
  const avail = await req('GET', `/v1/children/${fam.childId}/calls/availability`, { token: fam.gTok });
  check(g, 'availability: jitsi configured, and the .test host is not LAN-only', JSON.stringify(avail.body), '{"provider":"jitsi","available":true,"sameNetworkOnly":false}');
  check(g, 'availability never leaks the URL, app id or secret', /meet\.example|olive-e2e|secret/i.test(avail.text), false);
  const availKid = await req('GET', `/v1/children/${fam.childId}/calls/availability`, { token: fam.kTok });
  check(g, 'the child may ask too', availKid.status, 200);
  const availStranger = await req('GET', `/v1/children/${fam.childId}/calls/availability`, { token: fam.other.gTok });
  check(g, "another family's guardian may not", availStranger.status === 403 || availStranger.status === 404, true);

  const call1 = await req('POST', `/v1/children/${fam.childId}/calls`, { token: fam.gTok });
  check(g, 'a guardian starts a call: 201', call1.status, 201);
  check(g, 'the grant carries her REAL name, not a constant', jwtName(call1.body.jwt), 'Alex Morgan');
  check(g, 'ringState says it rang and rang is true', `${call1.body.ringState}/${call1.body.rang}`, 'rang/true');
  const ring = sendsTo('child-fcm-token-1').filter((s) => s.body.message.data.kind === 'call_incoming');
  check(g, 'the child device received the ring', ring.length, 1);
  check(g, 'the ring is data-only (no banner) at high priority with the call handle',
    `${ring[0].body.message.notification === undefined}/${ring[0].body.message.android.priority}/${typeof ring[0].body.message.data.callHandle}`, 'true/HIGH/string');
  check(g, 'the ring carries no name', JSON.stringify(ring[0].body).includes('Alex'), false);
  const row1 = (await admin.query(`SELECT rang, answered_at, ended_at, ended_reason FROM call_log WHERE id = $1`, [call1.body.sessionId])).rows[0];
  check(g, 'call_log was written with rang=true, unanswered and live', `${row1.rang}/${row1.answered_at}/${row1.ended_at}`, 'true/null/null');

  const join = await req('POST', `/v1/children/${fam.childId}/calls/${call1.body.sessionId}/join`, { token: fam.kTok });
  check(g, 'the child answers: 200 with HER real name', `${join.status}/${jwtName(join.body.jwt)}`, '200/Robin');
  const row2 = (await admin.query(`SELECT answered_at FROM call_log WHERE id = $1`, [call1.body.sessionId])).rows[0];
  check(g, 'the server stamped the answer', row2.answered_at !== null, true);
  fcmSends.length = 0;
  const end1 = await req('POST', `/v1/children/${fam.childId}/calls/${call1.body.sessionId}/end`, { token: fam.gTok });
  check(g, 'ending an answered call records "answered"', `${end1.body.ended}/${end1.body.reason}`, 'true/answered');
  check(g, '...and sends no cancel push (nothing is ringing)', fcmSends.length, 0);
  const end1b = await req('POST', `/v1/children/${fam.childId}/calls/${call1.body.sessionId}/end`, { token: fam.kTok });
  check(g, 'a second end is a harmless no-op', `${end1b.status}/${end1b.body.ended}`, '200/false');
  const joinEnded = await req('POST', `/v1/children/${fam.childId}/calls/${call1.body.sessionId}/join`, { token: fam.kTok });
  check(g, 'an ended call cannot be joined', joinEnded.status, 404);

  // caller hangs up before it is answered -> cancelled + the ring is cancelled on the device
  const call2 = await req('POST', `/v1/children/${fam.childId}/calls`, { token: fam.gTok });
  fcmSends.length = 0;
  const end2 = await req('POST', `/v1/children/${fam.childId}/calls/${call2.body.sessionId}/end`, { token: fam.gTok });
  check(g, 'a caller hanging up unanswered records "cancelled"', end2.body.reason, 'cancelled');
  const cancel = sendsTo('child-fcm-token-1');
  check(g, 'the child device is told to stop ringing', cancel.length, 1);
  check(g, 'the cancel is data-only, content-free and names the session', `${cancel[0].body.message.data.kind}/${cancel[0].body.message.data.ref === call2.body.sessionId}/${cancel[0].body.message.notification === undefined}`, 'call_cancelled/true/true');

  // the child's device declines
  const call3 = await req('POST', `/v1/children/${fam.childId}/calls`, { token: fam.gTok });
  const end3 = await req('POST', `/v1/children/${fam.childId}/calls/${call3.body.sessionId}/end`, { token: fam.kTok });
  check(g, 'the child ending it unanswered records "declined"', end3.body.reason, 'declined');

  // no device -> honest ringState
  const lonely = await newFamily('push-e2e-lonely', { guardianName: 'Lee', childName: 'Solo' });
  fcmSends.length = 0;
  const call4 = await req('POST', `/v1/children/${lonely.childId}/calls`, { token: lonely.gTok });
  check(g, 'a child with no registered device: call still starts, ringState no_devices', `${call4.status}/${call4.body.rang}/${call4.body.ringState}`, '201/false/no_devices');
  check(g, 'and a name from a different guardian is her own, not "Alex Morgan"', jwtName(call4.body.jwt), 'Lee');
  // quiet hours -> honest ringState
  const callQ = await req('POST', `/v1/children/${fam.quiet.childId}/calls`, { token: fam.quiet.gTok });
  check(g, 'inside quiet hours: rang false, ringState quiet_hours (no device is silently dropped)', `${callQ.body.rang}/${callQ.body.ringState}`, 'false/quiet_hours');
  check(g, 'ringState is the only ring detail returned (no device message leaks)', Object.keys(callQ.body).some((k) => /message|devices|token/i.test(k)), false);
  // a child cannot start a call; a stranger cannot join
  check(g, 'a child cannot start a call', (await req('POST', `/v1/children/${fam.childId}/calls`, { token: fam.kTok })).status, 403);
  const call5 = await req('POST', `/v1/children/${fam.childId}/calls`, { token: fam.gTok });
  const strangerJoin = await req('POST', `/v1/children/${fam.childId}/calls/${call5.body.sessionId}/join`, { token: fam.other.kTok });
  check(g, "another family's child cannot join this call", strangerJoin.status === 403 || strangerJoin.status === 404, true);

  // call_log is written FIRST: a failing insert rings nobody and mints nothing
  await admin.query(`CREATE OR REPLACE FUNCTION pc_e2e_block() RETURNS trigger AS $$ BEGIN
      IF NEW.child_id = '${fam.mixed.childId}' THEN RAISE EXCEPTION 'injected call_log failure'; END IF; RETURN NEW; END $$ LANGUAGE plpgsql`);
  await admin.query(`CREATE TRIGGER pc_e2e_block BEFORE INSERT ON call_log FOR EACH ROW EXECUTE FUNCTION pc_e2e_block()`);
  fcmSends.length = 0;
  const failed = await req('POST', `/v1/children/${fam.mixed.childId}/calls`, { token: fam.mixed.gTok });
  await admin.query(`DROP TRIGGER pc_e2e_block ON call_log`); await admin.query(`DROP FUNCTION pc_e2e_block()`);
  check(g, 'a failing call_log insert is a 503, not a ring', failed.status, 503);
  check(g, '...with no grant and no jwt in the body', failed.body.jwt === undefined && failed.body.sessionId === undefined, true);
  check(g, '...and not one push was sent', fcmSends.length, 0);

  // stale: an abandoned session is refused at join, then ended by the sweep
  const staleId = randomUUID();
  const freshId = randomUUID();
  for (const [id, ago] of [[staleId, '5 hours'], [freshId, '5 minutes']]) {
    await admin.query(`INSERT INTO call_log (id, child_id, started_by, participant_ids, room_name, ladder_step, started_at)
      VALUES ($1,$2,$3,$4,$5,'open', now() - $6::interval)`, [id, fam.childId, fam.userId, [fam.userId, fam.childId], 'room' + id, ago]);
  }
  const staleJoin = await req('POST', `/v1/children/${fam.childId}/calls/${staleId}/join`, { token: fam.kTok });
  check(g, 'a session older than the max age cannot be joined, even before the sweep', staleJoin.status, 404);
  const freshJoin = await req('POST', `/v1/children/${fam.childId}/calls/${freshId}/join`, { token: fam.kTok });
  check(g, 'a 5-minute-old session still can', freshJoin.status, 200);
  const sweep = await runNamedJob(pool, DATABASE_URL, 'end-stale-calls');
  check(g, 'the end-stale-calls job runs under its lock', JSON.stringify(sweep), '{"ok":true,"skipped":false}');
  const after = (await admin.query(`SELECT id, ended_at IS NOT NULL AS ended, ended_reason FROM call_log WHERE id = ANY($1)`, [[staleId, freshId]])).rows;
  const byId = Object.fromEntries(after.map((r2) => [r2.id, r2]));
  check(g, 'the stale call is ended with reason "stale"', `${byId[staleId].ended}/${byId[staleId].ended_reason}`, 'true/stale');
  check(g, 'the fresh call is untouched', byId[freshId].ended, false);
  check(g, 'a second sweep ends nothing', await endStaleCalls(pool), 0);
  // an end racing the sweep: one wins, never an error
  const raceId = randomUUID();
  await admin.query(`INSERT INTO call_log (id, child_id, started_by, participant_ids, room_name, ladder_step, started_at)
    VALUES ($1,$2,$3,$4,'roomrace','open', now() - interval '6 hours')`, [raceId, fam.childId, fam.userId, [fam.userId, fam.childId]]);
  const [e1, e2] = await Promise.all([endStaleCalls(pool), req('POST', `/v1/children/${fam.childId}/calls/${raceId}/end`, { token: fam.gTok })]);
  check(g, 'a concurrent end and sweep: exactly one records the end', (e1 === 1 ? 1 : 0) + (e2.body.ended ? 1 : 0), 1);
  await admin.query(`DELETE FROM call_log WHERE id = ANY($1)`, [[staleId, freshId, raceId]]);
}

// ===========================================================================
// F · the operator surface
// ===========================================================================
{
  const g = 'F operator';
  const m = await req('GET', '/internal/metrics');
  check(g, 'loopback /internal/metrics reports the push state', JSON.stringify(m.body.push), '{"androidRing":"ready","fcm":{"configured":true,"source":"file"},"apns":{"configured":false},"problems":0}');
  check(g, 'it carries no key, e-mail, project id or file path', ['BEGIN', 'olive-push@', 'olive-test', SA_FILE, tmp].some((x) => m.text.includes(x)), false);
  check(g, 'the server process logged no private key and no token', /BEGIN|stub-access|child-fcm-token/.test(out + err), false);
}

// ------------------------------------------------------------------ teardown
child.kill('SIGTERM'); await Promise.race([once(child, 'exit'), sleep(3000)]); if (child.exitCode === null) child.kill('SIGKILL');
stub.close();
try {
  await admin.query(`DELETE FROM delivery_intent WHERE child_id = ANY($1::uuid[])`, [created.children]);
  await admin.query(`DELETE FROM media_artifact WHERE child_id = ANY($1::uuid[])`, [created.children]);
  await admin.query(`DELETE FROM media_upload WHERE child_id = ANY($1::uuid[])`, [created.children]);
  await admin.query(`DELETE FROM device_token WHERE owner_child_id = ANY($1::uuid[]) OR owner_user_id = ANY($2::uuid[])`, [created.children, created.users]);
  await admin.query(`DELETE FROM call_log WHERE child_id = ANY($1::uuid[])`, [created.children]);
  await admin.query(`DELETE FROM paired_device WHERE target_id = ANY($1::uuid[])`, [[...created.users, ...created.children]]);
  await admin.query(`DELETE FROM guardianship WHERE child_id = ANY($1::uuid[])`, [created.children]);
  await admin.query(`DELETE FROM child WHERE id = ANY($1::uuid[])`, [created.children]);
  await admin.query(`DELETE FROM signup_allowance WHERE label = $1`, [`pushe2e-${RUN}`]);
  await admin.query(`DELETE FROM app_user WHERE id = ANY($1::uuid[])`, [created.users]);
} catch { /* append-only audit rows pin some ids: harmless */ }
rmSync(tmp, { recursive: true, force: true });
await admin.end(); await pool.end();

let gg = '';
for (const r of rows) { if (r.g !== gg) { gg = r.g; console.log(`\n${gg}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
