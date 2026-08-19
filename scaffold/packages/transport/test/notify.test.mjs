/**
 * packages/transport/src/notify.ts — notifyDevices(): the single dispatch
 * point a PushPayload leaves this codebase through. MASTERFILE §11.
 *
 * Requires a real Postgres (device_token rows are looked up for real via
 * deviceTokensFor/db/migrations/0008) — same DATABASE_URL/ADMIN_DATABASE_URL
 * gating as packages/db/test/device_token.test.mjs, and NOT part of `npm
 * test`'s default chain for the same reason.
 *
 * What this proves:
 *   A) STRUCTURAL — notify.ts's own source really does call sendGuard()
 *      between buildPush() and the transport calls, and imports it from
 *      push.ts rather than reimplementing it.
 *   B) BEHAVIORAL — sendGuard() actually runs and blocks a leaky payload:
 *      via notify.ts's own injection seam (NotifyDeviceDeps — see its own
 *      header for why it exists), a fake buildPush() is substituted to
 *      produce a KNOWN-LEAKY payload while the REAL sendGuard runs
 *      unmodified; the send must be refused AND the transport spies must
 *      never be called.
 *   C) one device's failure does not abort another's send (real DB rows,
 *      injected per-platform senders).
 *   D) a device FCM/APNs reports as permanently gone gets pruned for real
 *      (removeDeviceTokenSystem actually runs; the row is actually gone).
 *   E) with NO overrides at all — the real fcm.ts/apns.ts, real env
 *      (deliberately unset) — a missing credential fails loudly per device
 *      and does not silently no-op, and does not abort the other platform.
 */
import pg from 'pg';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { createPool, registerDeviceToken } from '../../db/src/pool.mjs';
import { notifyDevices } from '../src/notify.mjs';
import { auditPush } from '../src/push.mjs';

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

const DAD = 'b1111111-1111-1111-1111-111111111111';
await admin.query('BEGIN');
await admin.query(`DELETE FROM device_token WHERE owner_user_id = $1`, [DAD]);
await admin.query(`DELETE FROM app_user WHERE id = $1`, [DAD]);
await admin.query(`INSERT INTO app_user (id, display_name, home_tz) VALUES ($1,'Dad','America/Chicago')`, [DAD]);
await admin.query('COMMIT');

const dadP = { roleName: 'guardian', userId: DAD, childId: null };

// ===========================================================================
// A · STRUCTURAL — the source really wires sendGuard between build and send
// ===========================================================================
{
  const src = readFileSync(
    fileURLToPath(new URL('../src/notify.ts', import.meta.url)), 'utf8');
  check('A structural', "imports sendGuard from push.ts, doesn't reimplement it",
    /import\s*\{[^}]*\bsendGuard\b[^}]*\}\s*from\s*'\.\/push\.ts'/.test(src), 'true');

  const buildIdx = src.indexOf('_buildPush({');
  const guardIdx = src.indexOf('_sendGuard(payload)');
  const fcmIdx = src.indexOf('await _sendFcm(payload)');
  check('A structural', 'buildPush is called before sendGuard', buildIdx < guardIdx && buildIdx >= 0, 'true');
  check('A structural', 'sendGuard is called before the FCM send', guardIdx < fcmIdx && guardIdx >= 0, 'true');
}

// ===========================================================================
// B · sendGuard ACTUALLY BLOCKS a leaky payload — real sendGuard, fake builder
// ===========================================================================
{
  const id = await registerDeviceToken(pool, dadP, 'android', 'tok-notify-B');

  const leakyPayload = {
    token: 'tok-notify-B',
    data: { kind: 'message_ready', ref: 'r1', v: '1', senderName: 'Dad' }, // THE LEAK
    notification: { title: 'Olive', body: 'Something new is waiting for you.' },
  };
  check('B guard', 'sanity: the fixture really IS a leak per auditPush',
    auditPush(leakyPayload).ok, 'false');

  let fcmCalled = false, apnsCalled = false;
  const results = await notifyDevices(pool, { userId: DAD },
    { kind: 'message_ready', ref: 'r1' },
    {
      buildPush: () => leakyPayload,
      sendFcm: async () => { fcmCalled = true; return { ok: true }; },
      sendApns: async () => { apnsCalled = true; return { ok: true }; },
      // sendGuard is DELIBERATELY NOT overridden — the real one from push.ts runs.
    });

  check('B guard', 'the leaky send is reported as a failure', results[0].ok, 'false');
  check('B guard', 'failure message names the audit rejection',
    /push audit failed/.test(results[0].message), 'true');
  check('B guard', 'fcm.ts was NEVER called with the leaky payload', fcmCalled, 'false');
  check('B guard', 'apns.ts was NEVER called with the leaky payload', apnsCalled, 'false');

  await admin.query(`DELETE FROM device_token WHERE id = $1`, [id]);
}

// ===========================================================================
// C · one device's failure does not abort another's send (real DB rows)
// ===========================================================================
{
  const androidId = await registerDeviceToken(pool, dadP, 'android', 'tok-notify-C-android');
  const iosId = await registerDeviceToken(pool, dadP, 'ios', 'tok-notify-C-ios');

  const calls = [];
  const results = await notifyDevices(pool, { userId: DAD },
    { kind: 'message_ready', ref: 'r2' },
    {
      sendFcm: async (p) => { calls.push(['fcm', p.token]); throw Object.assign(new Error('boom'), { code: 'fcm_send_failed' }); },
      sendApns: async (p) => { calls.push(['apns', p.token]); return { ok: true }; },
    });

  check('C isolation', 'both devices appear in the results (loop did not abort)', results.length, 2);
  const androidResult = results.find(r => r.deviceTokenId === androidId);
  const iosResult = results.find(r => r.deviceTokenId === iosId);
  check('C isolation', "the android device's failure is reported", androidResult?.ok, 'false');
  check('C isolation', "the android device's failure code passes through",
    androidResult?.code, 'fcm_send_failed');
  check('C isolation', "the ios device still SUCCEEDED despite android's failure", iosResult?.ok, 'true');
  check('C isolation', 'both senders were actually invoked (neither skipped)', calls.length, 2);

  await admin.query(`DELETE FROM device_token WHERE id = $1 OR id = $2`, [androidId, iosId]);
}

// ===========================================================================
// D · a device reported permanently gone is actually pruned
// ===========================================================================
{
  const id = await registerDeviceToken(pool, dadP, 'android', 'tok-notify-D');

  const results = await notifyDevices(pool, { userId: DAD },
    { kind: 'message_ready', ref: 'r3' },
    {
      sendFcm: async () => { throw Object.assign(new Error('gone'), { code: 'fcm_send_failed', deviceGone: true }); },
    });

  check('D prune', 'the failure is reported', results[0].ok, 'false');
  check('D prune', 'the result says the row was pruned', results[0].pruned, 'true');

  const stillThere = await admin.query(`SELECT id FROM device_token WHERE id = $1`, [id]);
  check('D prune', 'the row is REALLY gone from the database, not just reported as gone',
    stillThere.rows.length, 0);

  // A non-deviceGone failure must NOT prune.
  const id2 = await registerDeviceToken(pool, dadP, 'android', 'tok-notify-D2');
  await notifyDevices(pool, { userId: DAD }, { kind: 'message_ready', ref: 'r4' },
    { sendFcm: async () => { throw Object.assign(new Error('transient'), { code: 'fcm_send_failed' }); } });
  const stillThere2 = await admin.query(`SELECT id FROM device_token WHERE id = $1`, [id2]);
  check('D prune', 'a non-deviceGone failure does NOT prune the row', stillThere2.rows.length, 1);
  await admin.query(`DELETE FROM device_token WHERE id = $1`, [id2]);
}

// ===========================================================================
// E · NO OVERRIDES AT ALL — real fcm.ts/apns.ts, credentials deliberately
// unset: fails loudly per device, does not silently no-op, does not abort
// ===========================================================================
{
  for (const k of ['FCM_SERVICE_ACCOUNT_JSON', 'APNS_KEY_P8', 'APNS_KEY_ID', 'APNS_TEAM_ID', 'APNS_TOPIC']) {
    delete process.env[k];
  }
  const androidId = await registerDeviceToken(pool, dadP, 'android', 'tok-notify-E-android');
  const iosId = await registerDeviceToken(pool, dadP, 'ios', 'tok-notify-E-ios');

  const results = await notifyDevices(pool, { userId: DAD }, { kind: 'message_ready', ref: 'r5' });

  check('E real', 'both real devices are attempted (nothing silently skipped)', results.length, 2);
  const androidResult = results.find(r => r.deviceTokenId === androidId);
  const iosResult = results.find(r => r.deviceTokenId === iosId);
  check('E real', 'android fails loudly with the real fcm.ts config error',
    androidResult?.code, 'fcm_config_missing');
  check('E real', 'ios fails loudly with the real apns.ts config error',
    iosResult?.code, 'apns_config_missing');
  check('E real', "android's config gap did not abort ios's attempt", iosResult?.ok, 'false');
  check('E real', 'neither result silently claims success', results.every(r => r.ok === false), 'true');

  await admin.query(`DELETE FROM device_token WHERE id = $1 OR id = $2`, [androidId, iosId]);
}

// ===========================================================================
// F · §8.11.4 channel awareness (v0.49.11) — a device resolved to a
// push-incapable channel is SKIPPED, never handed to fcm.ts/apns.ts at all.
// This is the one genuinely new, observable behavior change this pass makes.
// ===========================================================================
{
  const fireId = await registerDeviceToken(pool, dadP, 'android', 'tok-notify-F-fireos', 'android_amazon');
  const playId = await registerDeviceToken(pool, dadP, 'android', 'tok-notify-F-play', 'android_play');

  const calls = [];
  const results = await notifyDevices(pool, { userId: DAD },
    { kind: 'message_ready', ref: 'r6' },
    {
      sendFcm: async (p) => { calls.push(p.token); return { ok: true }; },
      sendApns: async () => { calls.push('apns-should-not-happen'); return { ok: true }; },
    });

  check('F channels', 'both rows appear in the results (the FireOS one is reported, not silently dropped)',
    results.length, 2);
  const fireResult = results.find(r => r.deviceTokenId === fireId);
  const playResult = results.find(r => r.deviceTokenId === playId);

  check('F channels', 'the FireOS device is skipped, not sent to', fireResult?.ok, 'false');
  check('F channels', 'and carries the no_push_capability code', fireResult?.code, 'no_push_capability');
  check('F channels', 'and carries real guardian-facing advice text',
    /text the grown-up/.test(fireResult?.advice ?? ''), 'true');
  check('F channels', 'sendFcm was NEVER called for the FireOS device — this is the actual fix',
    calls.includes('tok-notify-F-fireos'), 'false');

  check('F channels', 'the Play Services device still sends normally', playResult?.ok, 'true');
  check('F channels', 'and has no advice attached (nothing to advise about)', playResult?.advice, 'undefined');
  check('F channels', 'sendFcm WAS called for the Play Services device',
    calls.includes('tok-notify-F-play'), 'true');

  await admin.query(`DELETE FROM device_token WHERE id = $1 OR id = $2`, [fireId, playId]);
}

// F2 · a device that never reported a channel at all falls back to the
// documented optimistic default (android -> android_play, so push is still
// attempted) — proving resolveChannel()'s fallback, not just the happy path
// where a channel was already known.
{
  const unknownId = await registerDeviceToken(pool, dadP, 'android', 'tok-notify-F2-unknown');

  const calls = [];
  const results = await notifyDevices(pool, { userId: DAD },
    { kind: 'message_ready', ref: 'r7' },
    { sendFcm: async (p) => { calls.push(p.token); return { ok: true }; } });

  const r = results.find(x => x.deviceTokenId === unknownId);
  check('F2 unknown channel', 'a device with no reported channel is NOT skipped (optimistic default)',
    r?.ok, 'true');
  check('F2 unknown channel', 'sendFcm was attempted for it',
    calls.includes('tok-notify-F2-unknown'), 'true');

  await admin.query(`DELETE FROM device_token WHERE id = $1`, [unknownId]);
}

await admin.query(`DELETE FROM device_token WHERE owner_user_id = $1`, [DAD]);
await admin.query(`DELETE FROM app_user WHERE id = $1`, [DAD]);
await admin.end();
await pool.end();

let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
