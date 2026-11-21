/**
 * Erase on next contact for a lost grown-up's phone (db/migrations/0056_lost_device.sql), end to end against a REAL
 * Postgres through the REAL Api (strict ids ON). Every account comes from POST /v1/auth/signup, every extra device from
 * the real pairing routes.
 *
 *   G. the order     only the OWNER, only for a phone already marked as lost, never a tablet, never the last copy;
 *                    wrong PIN, stranger, stale incident, replay.
 *   H. the 24 hours  the phone is told only after the grace; any grown-up can call it off; "I have it" calls it off.
 *   I. contact       the lost phone hears it on its next refresh (credential proved first), says it is done once, and
 *                    is cut off for good; a wrong credential learns nothing; nothing in the family is deleted.
 *   J. races         order vs "I have it", six simultaneous acknowledgements, an old order replayed after a second loss.
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
  markDeviceLost, foundDevice, orderDeviceErase, cancelDeviceErase, ackDeviceErased, pairedDeviceStanding,
  LOST_NOTICE_MS, ERASE_GRACE_MS } from '../../packages/db/src/pool.mjs';
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

const SECRET = Buffer.from('e'.repeat(32), 'utf8');
const tmpRoot = await fs.mkdtemp(path.join(os.tmpdir(), 'olive-erase-test-'));
const api = new Api(SECRET, dbPort(pool), () => Date.now(), { strictIds: true });
registerRoutes(api, pool, new FilesystemStorage(tmpRoot), {
  callEnv: { CALL_PROVIDER: 'jitsi', NODE_ENV: 'test', JITSI_APP_ID: 'olive-calls',
    JITSI_APP_SECRET: randomBytes(32).toString('hex'), JITSI_SERVER_URL: 'https://calls.example.test:8443' },
});

const hdr = (tok) => (tok ? { authorization: `Bearer ${tok}` } : {});
const call = (method, p, tok, body) => api.handle(
  method, p, hdr(tok), body === undefined ? '' : JSON.stringify(body));
const RUN = randomUUID().slice(0, 8);
const LABEL = `erasetest-${RUN}`;
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

const order = (by, deviceId, incidentId, pin = '4821') => call('POST', `/v1/me/devices/${deviceId}/erase`, by.tok, { pin, incidentId });
const cancelE = (by, deviceId, incidentId, pin = '4821') => call('POST', `/v1/me/devices/${deviceId}/erase-cancel`, by.tok, { pin, incidentId });
const ack = (d, cred = d.cred) => call('POST', '/v1/auth/session/erased', null, { deviceId: d.deviceId, deviceCredential: cred });
const backdateOrder = (id, ms) => admin.query(
  `UPDATE paired_device SET wipe_ordered_at = now() - ($2 || ' milliseconds')::interval WHERE id = $1`, [id, String(ms)]);

// Family A: Mom (phones M1, M2), Dad (phone D1), Ivy (tablet T1). Family B: a stranger (phone B1).
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
const M1 = mom;
const M2 = await pairPhone(mom);
const D1 = dad;
const T1 = await pairTablet(M2, CHILD_A);
const baseline = await counts();
check('setup', 'a family of two grown-ups, mom with two phones, and a tablet are real and signed in',
  `${(await ping(M1)).status}${(await ping(M2)).status}${(await ping(D1)).status}`, '200200200');

// ===========================================================================
// G · THE ORDER
// ===========================================================================
let inc1;
{
  const early = await order(M2, M1.deviceId, randomUUID());
  check('G order', 'a phone that is NOT marked as lost cannot be ordered to erase -> 409 not_paused', `${early.status} ${early.body?.error}`, '409 not_paused');
  const m = await mark(M2, M1.deviceId);
  inc1 = m.body.incidentId;
  check('G order', 'mom marks her phone lost from her other phone -> 201', m.status, 201);
  const dadTry = await order(D1, M1.deviceId, inc1, '2468');
  check('G order', 'dad (another grown-up) may NOT order mom\'s phone to erase -> 403 owner_only', `${dadTry.status} ${dadTry.body?.error}`, '403 owner_only');
  check('G order', 'a stranger family sees nothing: 404', (await order(stranger, M1.deviceId, inc1, '7315')).status, 404);
  const tm = await mark(M2, T1.deviceId);
  const tab = await order(M2, T1.deviceId, tm.body.incidentId);
  check('G order', 'a CHILD\'S TABLET can never be ordered to erase (her private areas are hers) -> 422', `${tab.status} ${tab.body?.error}`, '422 not_a_grown_up_phone');
  await found(M2, T1.deviceId, tm.body.incidentId);
  const wrong = await order(M2, M1.deviceId, inc1, '0000');
  check('G order', 'a wrong PIN is refused and orders nothing', `${wrong.status} ${(await row(M1.deviceId)).wipe_ordered_at}`, '403 null');
  await unlockPin(mom.userId);
  check('G order', 'a malformed incident is refused', `${(await order(M2, M1.deviceId, 'nope')).status}`, '400');
  check('G order', 'an old incident is refused -> 409 stale_incident', (await order(M2, M1.deviceId, randomUUID())).body?.error, 'stale_incident');
  const o = await order(M2, M1.deviceId, inc1);
  check('G order', 'mom orders it from her other phone -> 201 eraseOrdered', `${o.status} ${o.body?.eraseOrdered}`, '201 true');
  const again = await order(M2, M1.deviceId, inc1);
  check('G order', 'ordering twice changes nothing -> 200 (the first order keeps its time)', `${again.status}`, '200');
  check('G order', 'the history reads marked, wipe_ordered (once)', (await events(M1.deviceId)).join(), 'marked,wipe_ordered');
  check('G order', 'every grown-up is told, in the security feed', `${(await feed(D1, CHILD_A)).includes('device_wipe_ordered')}`, 'true');
  const list = (await call('GET', '/v1/me/devices', M2.tok)).body.devices.find((d) => d.id === M1.deviceId);
  check('G order', 'the list says: ordered, due in about 24 hours, cancellable, not orderable again',
    `${list.eraseOrdered} ${Math.abs(new Date(list.eraseDueAt).getTime() - Date.now() - ERASE_GRACE_MS) < 60000} ${list.canCancelErase} ${list.canOrderErase}`, 'true true true false');
  const dadList = (await call('GET', '/v1/me/devices', D1.tok)).body.devices.find((d) => d.id === M1.deviceId);
  check('G order', 'dad sees it too and can call it off, but cannot order', `${dadList.eraseOrdered} ${dadList.canCancelErase} ${dadList.canOrderErase}`, 'true true false');
  check('G order', 'a tablet is never offered the erase',
    JSON.stringify((await call('GET', '/v1/me/devices', M2.tok)).body.devices.filter((d) => d.role === 'child').map((d) => d.canOrderErase)), '[false]');
}

// ===========================================================================
// H · THE 24 HOURS, AND CALLING IT OFF
// ===========================================================================
{
  const rf = await refresh(M1);
  check('H grace', 'inside the 24 hours the lost phone is just "paused": no erase word yet', `${rf.status} ${rf.body?.error} ${rf.body?.wipe}`, '401 device_paused undefined');
  const early = await ack(M1);
  check('H grace', '...and it cannot say "done" early (it has not been told) -> 401', early.status, 401);
  check('H grace', '...nothing changed', `${(await row(M1.deviceId)).wiped_at}`, 'null');
  const c = await cancelE(D1, M1.deviceId, inc1, '2468');
  check('H grace', 'ANY grown-up can call the order off: dad does -> 200', `${c.status} ${c.body?.eraseOrdered}`, '200 false');
  check('H grace', '...so the phone is never told to erase, and cannot say it did', `${(await refresh(M1)).body?.wipe} ${(await ack(M1)).status}`, 'undefined 401');
  check('H grace', 'calling off again -> 409 no_erase_ordered', (await cancelE(D1, M1.deviceId, inc1, '2468')).body?.error, 'no_erase_ordered');
  const reorder = await order(M2, M1.deviceId, inc1);
  check('H grace', 'mom can order again -> 201', reorder.status, 201);
  const f = await found(M2, M1.deviceId, inc1);
  check('H grace', '"I have it" brings the phone back -> 200 active', `${f.status} ${f.body?.state}`, '200 active');
  check('H grace', '...and the pending order goes with it', `${(await row(M1.deviceId)).wipe_ordered_at}`, 'null');
  check('H grace', '...the history says so', (await events(M1.deviceId)).join(), 'marked,wipe_ordered,wipe_cancelled,wipe_ordered,wipe_cancelled,found');
  check('H grace', '...and the phone needs its owner\'s PIN once, as for any phone that comes back',
    `${(await refresh(M1)).status} ${(await refresh(M1)).body?.error}`, '403 pin_required');
  await unlockPin(mom.userId);
  check('H grace', '...which it shows, and is back in use', (await refresh(M1, '4821')).status, 200);
}

// ===========================================================================
// I · CONTACT: the lost phone hears it, erases, says so once
// ===========================================================================
let inc2;
const M3 = await pairPhone(mom);         // a second phone of mom's, lost for real this time
{
  const m = await mark(M2, M3.deviceId);
  inc2 = m.body.incidentId;
  const o = await order(M2, M3.deviceId, inc2);
  check('I contact', 'mom marks M3 and orders it to erase -> 201', o.status, 201);
  await backdateOrder(M3.deviceId, ERASE_GRACE_MS + 1000);
  const bad = await call('POST', '/v1/auth/session/refresh', null, { deviceId: M3.deviceId, deviceCredential: 'x'.repeat(43) });
  check('I contact', 'a wrong credential learns nothing, not even that there is an order', `${bad.status} ${bad.body?.error} ${bad.body?.wipe}`, '401 invalid_device_credential undefined');
  const rf = await refresh(M3);
  check('I contact', 'after the 24 hours the phone, on its next contact, is told to erase -> 401 device_paused + wipe', `${rf.status} ${rf.body?.error} ${rf.body?.wipe}`, '401 device_paused true');
  check('I contact', '...and it still gets NO session', (await ping(M3)).status, 401);
  const wrongAck = await ack(M3, 'y'.repeat(43));
  check('I contact', 'a wrong credential cannot say "done" -> 401', wrongAck.status, 401);
  const otherAck = await ack({ deviceId: M3.deviceId }, M2.cred);
  check('I contact', 'another phone\'s credential cannot say it for M3 -> 401', otherAck.status, 401);
  check('I contact', '...a phone that was never ordered cannot say it', (await ack(M2)).status, 401);
  const a1 = await ack(M3);
  check('I contact', 'the phone says it has erased -> 200', `${a1.status} ${a1.body?.erased}`, '200 true');
  const r2 = await row(M3.deviceId);
  check('I contact', '...it is cut off for good at that moment, and the row records it', `${r2.wiped_at !== null} ${r2.revoked_at !== null}`, 'true true');
  const rf2 = await refresh(M3);
  check('I contact', '...a later refresh says revoked and no longer says erase', `${rf2.status} ${rf2.body?.error} ${rf2.body?.wipe}`, '401 device_revoked undefined');
  check('I contact', 'saying "done" again is harmless -> 200', (await ack(M3)).status, 200);
  check('I contact', '...and is recorded once', (await events(M3.deviceId)).join(), 'marked,wipe_ordered,wiped');
  check('I contact', '"I have it" after the erase is too late (it comes back by being added again)', (await found(M2, M3.deviceId, inc2)).body?.error, 'too_late');
  check('I contact', 'ordering again -> 409 already_erased', (await order(M2, M3.deviceId, inc2)).body?.error, 'already_erased');
  check('I contact', 'every grown-up is told it was done', `${(await feed(D1, CHILD_A)).includes('device_wiped')}`, 'true');
  const c = await counts();
  check('I contact', 'NOTHING in the family was deleted: same grown-ups, children and edges (one more device row, kept)',
    `${c.edges} ${c.kids} ${c.devices}`, `${baseline.edges} ${baseline.kids} ${baseline.devices + 1}`);
  check('I contact', 'mom\'s other phone and dad\'s phone are untouched', `${(await ping(M2)).status}${(await ping(D1)).status}`, '200200');
  const erasedRow = (await call('GET', '/v1/me/devices', M2.tok)).body.devices.find((d) => d.id === M3.deviceId);
  check('I contact', 'the list shows it as erased and cut off, with nothing left to do', `${erasedRow.erased} ${erasedRow.state} ${erasedRow.canOrderErase} ${erasedRow.canCancelErase}`, 'true revoked false false');
}

// ===========================================================================
// J · LAST COPY, RACES, REPLAY
// ===========================================================================
{
  // last copy: a one-grown-up family whose only OTHER phone has been signed out
  const b1 = stranger;
  const b2 = await pairPhone(b1, '7315');
  const mb = await mark(b2, b1.deviceId, '7315');
  await admin.query(`UPDATE paired_device SET revoked_at = now() WHERE id = $1`, [b2.deviceId]);
  const r = await orderDeviceErase(pool, { deviceId: b1.deviceId, userId: b1.userId, fromDeviceId: null, incidentId: mb.body.incidentId, now: new Date() });
  check('J last copy', 'with no other grown-up phone in use the order is refused: it can never destroy the last copy', `${r.ok} ${r.reason}`, 'false no_other_copy');
  check('J last copy', '...and nothing was ordered', `${(await row(b1.deviceId)).wipe_ordered_at}`, 'null');
}
{
  // order vs "I have it": whichever wins, the end state is whole and nothing is erased
  const x = await pairPhone(mom);
  const m = await mark(M2, x.deviceId);
  const [o, f] = await Promise.all([order(M2, x.deviceId, m.body.incidentId), found(M2, x.deviceId, m.body.incidentId)]);
  const rw = await row(x.deviceId);
  check('J race', 'order vs "I have it" at the same instant: the phone ends active with NO order standing', `${rw.paused_at} ${rw.wipe_ordered_at} ${f.status}`, 'null null 200');
  check('J race', '...and it can never say it erased', (await ack(x)).status, 401);
  void o;
}
{
  // six simultaneous "done" answers: one erase, one history line
  const y = await pairPhone(mom);
  const m = await mark(M2, y.deviceId);
  await order(M2, y.deviceId, m.body.incidentId);
  await backdateOrder(y.deviceId, ERASE_GRACE_MS + 1000);
  const rs = await Promise.all([1, 2, 3, 4, 5, 6].map(() => ack(y)));
  check('J race', 'six simultaneous "done" answers all succeed, one erase is recorded', `${rs.every((r) => r.status === 200)} ${(await events(y.deviceId)).filter((k) => k === 'wiped').length}`, 'true 1');
}
{
  // replay: an old order cannot be re-used for a second loss of the same phone
  const z = await pairPhone(mom);
  const m1 = await mark(M2, z.deviceId);
  const old = m1.body.incidentId;
  await found(M2, z.deviceId, old);
  await refresh(z, '4821');
  const m2 = await mark(M2, z.deviceId);
  check('J replay', 'a second loss is a new incident', m2.body.incidentId !== old, 'true');
  check('J replay', 'an erase order quoting the FIRST incident is refused -> 409 stale_incident', (await order(M2, z.deviceId, old)).body?.error, 'stale_incident');
  check('J replay', 'and an old "call off" cannot touch the second', (await cancelE(M2, z.deviceId, old)).body?.error, 'stale_incident');
}

// ===========================================================================
// K · STORAGE
// ===========================================================================
{
  const bad = (sql, args) => admin.query(sql, args).then(() => 'accepted', () => 'refused');
  check('K storage', 'a child\'s tablet row can never carry an erase order (the table refuses)',
    await bad(`UPDATE paired_device SET wipe_ordered_at = now() WHERE id = $1`, [T1.deviceId]), 'refused');
  check('K storage', 'the new history lines are fixed words only',
    (await admin.query(`SELECT summary FROM security_event WHERE kind IN ('device_wipe_ordered','device_wiped') AND actor_id = ANY($1::uuid[])`, [users])).rows.every((r) => !/Mom|Dad|Phone|Ivy/.test(r.summary)), 'true');
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
