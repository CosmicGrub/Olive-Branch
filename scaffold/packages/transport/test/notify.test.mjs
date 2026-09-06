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

// F3 · admitDevice()'s ok:false ("silent_device") branch — unreachable with
// any real shipped channel (devices.ts's own CHANNELS table has none that
// combine push:false with fallback:'none'), but live code in a path this
// codebase's own header calls "the worst class of defect this product can
// have." An adversarial audit found it had never executed under test.
// Injected via the new admitDevice seam (v0.49.14) rather than left
// unreachable — proving the `: admission.note` ternary arm produces the
// right shape, not just that it type-checks.
{
  const id = await registerDeviceToken(pool, dadP, 'android', 'tok-notify-F3-silent');

  const results = await notifyDevices(pool, { userId: DAD },
    { kind: 'message_ready', ref: 'r8' },
    {
      admitDevice: () => ({ ok: false, reason: 'silent_device',
        note: 'Manufactured for this test: a channel with neither push nor a fallback.' }),
    });

  const r = results.find(x => x.deviceTokenId === id);
  check('F3 silent device', 'the device is skipped, not sent to', r?.ok, 'false');
  check('F3 silent device', 'carries the same no_push_capability code as the real refusal path',
    r?.code, 'no_push_capability');
  check('F3 silent device', "advice is admitDevice()'s own note, not channelAdvice() "
    + '(there is no capability to ask channelAdvice() about)',
    r?.advice, 'Manufactured for this test: a channel with neither push nor a fallback.');

  await admin.query(`DELETE FROM device_token WHERE id = $1`, [id]);
}

// F4 · the device-prune catch, when removeDeviceTokenSystem() itself throws
// during a deviceGone cleanup — the exact scenario the file's own comment
// describes ("best-effort cleanup; the send failure is still reported
// below") but had never actually been driven through a real throw.
// Injected via the new removeDeviceTokenSystem seam (v0.49.14).
{
  const id = await registerDeviceToken(pool, dadP, 'android', 'tok-notify-F4-prune-fails');

  const results = await notifyDevices(pool, { userId: DAD },
    { kind: 'message_ready', ref: 'r9' },
    {
      sendFcm: async () => { throw Object.assign(new Error('gone'),
        { code: 'fcm_send_failed', deviceGone: true }); },
      removeDeviceTokenSystem: async () => { throw new Error('transient db failure during prune'); },
    });

  const r = results.find(x => x.deviceTokenId === id);
  check('F4 prune throws', 'the send failure is still reported (outer result unaffected '
    + 'by the inner catch)', r?.ok, 'false');
  check('F4 prune throws', 'pruned correctly stays false — the throw never reached the assignment',
    r?.pruned, 'false');
  check('F4 prune throws', 'the original send failure code passes through untouched',
    r?.code, 'fcm_send_failed');
  const stillThere = await admin.query(`SELECT 1 FROM device_token WHERE id = $1`, [id]);
  check('F4 prune throws', 'the row genuinely still exists — the failed prune did not '
    + 'somehow still delete it', stillThere.rows.length, '1');

  await admin.query(`DELETE FROM device_token WHERE id = $1`, [id]);
}

// ===========================================================================
// G · P1 — MASTERFILE §6.4's recipient-side gate, now real INSIDE
// notifyDevices() itself, not just the read-only GET /now route (see this
// file's own header for the full before/after). Real child + real day_part
// rows, no gate()/childCtxFor() injection anywhere in this section — a real,
// reachable-with-real-data path, per NotifyDeviceDeps's own "only add a seam
// when a real path genuinely can't be reached with real data" discipline.
// ===========================================================================
{
  const CHILD = 'c1111111-1111-1111-1111-111111111111';
  await admin.query(`DELETE FROM device_token WHERE owner_child_id = $1`, [CHILD]);
  await admin.query(`DELETE FROM day_part WHERE child_id = $1`, [CHILD]);
  await admin.query(`DELETE FROM child WHERE id = $1`, [CHILD]);
  await admin.query(
    `INSERT INTO child (id, display_name, birth_date, home_tz)
     VALUES ($1, 'Ivy', '2016-04-02', 'America/Chicago')`, [CHILD]);
  const childP = { roleName: 'child', userId: null, childId: CHILD };
  const childDeviceId = await registerDeviceToken(pool, childP, 'android', 'tok-notify-G-child');

  // Three OVERLAPPING reachable:false windows, not two complementary ones.
  // This was originally a deliberate workaround for a real precision
  // mismatch found while writing this section: childCtxFor() cast
  // starts_local/ends_local via Postgres's `time::text` (seconds-precision,
  // e.g. '12:00:00') while gate()'s `hhmm` is luxon's minute-precision
  // 'HH:mm' (e.g. '12:00'); JS string comparison treats the shorter string
  // as LESS than the longer one it's a prefix of, so a two-row split at
  // exact boundaries would have made this section's result depend on which
  // minute it happened to run in. That mismatch is now fixed at the source
  // — childCtxFor() (packages/db/src/pool.ts) truncates the `::text` cast
  // to 'HH:mm' width before gate() ever sees it, and
  // packages/delivery-engine/test/delivery.test.mjs's "G4b boundary minute"
  // section locks down gate()'s own comparison operators at exact boundary
  // minutes — so the overlap below is no longer load-bearing, just left in
  // place as harmless belt-and-suspenders since it costs nothing here.
  await admin.query(
    `INSERT INTO day_part (child_id, kind, starts_local, ends_local, days_of_week, reachable, effective)
     VALUES
       ($1, 'asleep', '00:00', '09:00', ARRAY[0,1,2,3,4,5,6]::smallint[], false,
        daterange(CURRENT_DATE - 1, CURRENT_DATE + 1)),
       ($1, 'school', '08:00', '17:00', ARRAY[0,1,2,3,4,5,6]::smallint[], false,
        daterange(CURRENT_DATE - 1, CURRENT_DATE + 1)),
       ($1, 'asleep', '16:00', '01:00', ARRAY[0,1,2,3,4,5,6]::smallint[], false,
        daterange(CURRENT_DATE - 1, CURRENT_DATE + 1))`,
    [CHILD]);

  // G1 · a CHILD-targeted call_incoming push is blocked, not fired — the
  // real production caller (server/routes.mjs's calls route) sends exactly
  // this kind, and MASTERFILE §6.4's own text ("block arrivals during
  // asleep/school") names no calls-specific exception.
  const calls = [];
  const blocked = await notifyDevices(pool, { childId: CHILD },
    { kind: 'call_incoming', ref: 'r10', callRoomHandle: 'room-g1' },
    { sendFcm: async (p) => { calls.push(p.token); return { ok: true }; } });

  check('G1 gate blocks', 'exactly one result, for the one real device', blocked.length, 1);
  check('G1 gate blocks', 'the device is reported as gated, not sent to', blocked[0]?.ok, 'false');
  check('G1 gate blocks', 'carries the gated_quiet_hours code', blocked[0]?.code, 'gated_quiet_hours');
  check('G1 gate blocks', 'the message names which day-part blocked it',
    /asleep|school/.test(blocked[0]?.message ?? ''), 'true');
  check('G1 gate blocks', 'sendFcm was NEVER called — blocked before any per-device send',
    calls.length, 0);

  // G2 · 'emergency' priority bypasses the SAME blocking day-parts —
  // gate.ts's own contract, now reachable via NotifyInput.priority.
  const emergency = await notifyDevices(pool, { childId: CHILD },
    { kind: 'call_incoming', ref: 'r11', callRoomHandle: 'room-g2', priority: 'emergency' },
    { sendFcm: async (p) => { calls.push(p.token); return { ok: true }; } });
  check('G2 emergency bypass', 'an emergency-priority send is NOT blocked by the same day-parts',
    emergency[0]?.ok, 'true');
  check('G2 emergency bypass', 'sendFcm WAS called this time',
    calls.includes('tok-notify-G-child'), 'true');

  // G3 · remove every day-part row — an honest absence (no day-part
  // classified for "now") allows through, same as gate.ts's own
  // `current === undefined` fallthrough; `message_ready`, not
  // `call_incoming`, to also prove the gate isn't call-kind-specific.
  await admin.query(`DELETE FROM day_part WHERE child_id = $1`, [CHILD]);
  const calls2 = [];
  const open = await notifyDevices(pool, { childId: CHILD },
    { kind: 'message_ready', ref: 'r12' },
    { sendFcm: async (p) => { calls2.push(p.token); return { ok: true }; } });
  check('G3 no day-part = open', 'the send goes through with no day-part rows at all',
    open[0]?.ok, 'true');
  check('G3 no day-part = open', 'sendFcm WAS called', calls2.includes('tok-notify-G-child'), 'true');

  // G4 · the gate is CHILD-scoped only (childCtxFor()'s day-part rows are
  // keyed by child_id; there is no guardian equivalent) — a guardian-
  // targeted ({userId}) send is never subject to it, proven here with a
  // real device right after this same section proved the gate itself works.
  const dadDeviceId = await registerDeviceToken(pool, dadP, 'android', 'tok-notify-G4-guardian');
  const calls3 = [];
  const guardianSend = await notifyDevices(pool, { userId: DAD },
    { kind: 'message_ready', ref: 'r13' },
    { sendFcm: async (p) => { calls3.push(p.token); return { ok: true }; } });
  check('G4 guardian ungated', "a {userId} target never reaches the 'childId' in target branch",
    guardianSend[0]?.ok, 'true');
  check('G4 guardian ungated', 'sendFcm WAS called (no gate consulted for a guardian target)',
    calls3.includes('tok-notify-G4-guardian'), 'true');

  await admin.query(`DELETE FROM device_token WHERE id = $1 OR id = $2`, [childDeviceId, dadDeviceId]);
  await admin.query(`DELETE FROM day_part WHERE child_id = $1`, [CHILD]);
  await admin.query(`DELETE FROM child WHERE id = $1`, [CHILD]);
}

// ===========================================================================
// H · P2 — the per-device fan-out runs concurrently, and every iOS send in
// one notifyDevices() batch shares ONE real session object rather than
// opening its own. Proven via the new openApnsSession seam (NotifyDeviceDeps)
// — no real Apple credential or real HTTP/2 socket needed to prove the
// SHARING itself, exactly the reasoning notify.test.mjs's own header already
// gives for why deps seams exist at all.
// ===========================================================================
{
  const androidId = await registerDeviceToken(pool, dadP, 'android', 'tok-notify-H-android');
  const ios1 = await registerDeviceToken(pool, dadP, 'ios', 'tok-notify-H-ios-1');
  const ios2 = await registerDeviceToken(pool, dadP, 'ios', 'tok-notify-H-ios-2');

  let opens = 0, closes = 0;
  const fakeSession = { marker: 'shared-session-h' };
  const sessionsSeenByApns = [];
  const results = await notifyDevices(pool, { userId: DAD },
    { kind: 'message_ready', ref: 'r14' },
    {
      sendFcm: async () => ({ ok: true }),
      sendApns: async (_p, opts) => { sessionsSeenByApns.push(opts?.session); return { ok: true }; },
      openApnsSession: () => {
        opens++;
        return { session: fakeSession, close: () => { closes++; } };
      },
    });

  check('H1 session sharing', 'all three devices report success', results.every(r => r.ok), 'true');
  check('H1 session sharing', 'openApnsSession was called exactly ONCE for the whole batch (not per iOS device)',
    opens, 1);
  check('H1 session sharing', 'both iOS sends received the SAME session object',
    sessionsSeenByApns.length === 2 && sessionsSeenByApns[0] === fakeSession
      && sessionsSeenByApns[1] === fakeSession, 'true');
  check('H1 session sharing', 'the shared session was closed exactly ONCE, after both sends settled',
    closes, 1);

  await admin.query(`DELETE FROM device_token WHERE id = $1 OR id = $2 OR id = $3`,
    [androidId, ios1, ios2]);
}

{
  // H2 · an all-Android batch never opens a session at all — the
  // optimization is scoped to batches that actually have an iOS send. A
  // FRESH device set, isolated from H1's (already deleted above) — this
  // batch must contain no iOS device at all for the assertion to mean
  // anything.
  const androidOnlyId = await registerDeviceToken(pool, dadP, 'android', 'tok-notify-H2-android');
  let opens2 = 0;
  await notifyDevices(pool, { userId: DAD }, { kind: 'message_ready', ref: 'r15' },
    {
      sendFcm: async () => ({ ok: true }),
      openApnsSession: () => { opens2++; return { session: {}, close: () => {} }; },
    });
  check('H2 android-only skips session', 'openApnsSession is never called for a batch with no iOS device',
    opens2, 0);
  await admin.query(`DELETE FROM device_token WHERE id = $1`, [androidOnlyId]);
}

{
  // H3 · if opening the shared session itself throws (missing credentials,
  // a real connect failure), the batch degrades gracefully — each iOS send
  // still gets attempted with no session, exactly pre-P2 behavior, rather
  // than the whole batch failing over an optimization that didn't pan out.
  const iosOnlyId = await registerDeviceToken(pool, dadP, 'ios', 'tok-notify-H3-ios');
  const sessionsSeenH3 = [];
  const resultsH3 = await notifyDevices(pool, { userId: DAD }, { kind: 'message_ready', ref: 'r16' },
    {
      sendApns: async (_p, opts) => { sessionsSeenH3.push(opts?.session); return { ok: true }; },
      openApnsSession: () => { throw Object.assign(new Error('boom'), { code: 'apns_config_missing' }); },
    });
  check('H3 graceful fallback', 'iOS sends still succeed when opening the shared session throws',
    resultsH3.filter(r => r.platform === 'ios').every(r => r.ok), 'true');
  check('H3 graceful fallback', 'each iOS send falls back to no session (undefined), not a crash',
    sessionsSeenH3.every(s => s === undefined), 'true');
  await admin.query(`DELETE FROM device_token WHERE id = $1`, [iosOnlyId]);
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
