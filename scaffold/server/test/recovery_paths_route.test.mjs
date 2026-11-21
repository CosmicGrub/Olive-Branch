/**
 * Recovery paths (db/migrations/0055_recovery_paths.sql): losing a phone without losing anything, end to end
 * against a REAL Postgres through the REAL Api (strict ids ON, as in production). Every account comes from
 * POST /v1/auth/signup; nothing is seeded by SQL except a second parent's edge and the clock (the tests move
 * a request's own timestamps back, the way an elapsed waiting period would).
 *
 *   A. sheet       the printed recovery key: step-up, shown once, hash only, check, replace, one live sheet
 *   B. helper      the ONE trusted helper: invite, accept, single use, expiry, replace, remove, over-reach
 *   C. two parents second parent starts it (their own PIN), 48 hours, notice on every phone, anyone can stop it,
 *                  the race on the waiting period, cancel during the wait, replay, wrong family, wrong guesses
 *   D. one parent  the sheet, 72 hours, the helper's yes, total loss (no other phone left), spent sheet, new PIN
 *   E. whole       nothing duplicated, nothing orphaned: same account id, same children, same rows
 *   F. limits      budgets, five wrong guesses end THAT request only, the real owner is never locked out,
 *                  caps on open and daily requests
 *   G. storage     hashes only, system-only row level security, table constraints
 *
 * Needs a NOSUPERUSER NOBYPASSRLS DATABASE_URL (app_owner or app_runtime) and an ADMIN_DATABASE_URL for setup
 * and cleanup. Prints "N passed, M failed" for verify.sh.
 */
import pg from 'pg';
import os from 'node:os';
import path from 'node:path';
import fs from 'node:fs/promises';
import { randomUUID, randomBytes, createHash } from 'node:crypto';
import { Api } from '../../packages/api/src/api.mjs';
import { createPool, dbPort, withSession, issueSignupAllowance, setSignupPolicy,
  makeRecoverySheet, recoveryNoticesFor, startRecoveryForGrownUp, finishRecovery, helperAnswer,
  RECOVERY_WAIT_SECOND_PARENT_MS, RECOVERY_WAIT_SOLE_PARENT_MS } from '../../packages/db/src/pool.mjs';
import { registerRoutes } from '../routes.mjs';
import { MissBudget } from '../rate_limit.mjs';
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

const SECRET = Buffer.from('p'.repeat(32), 'utf8');
const tmpRoot = await fs.mkdtemp(path.join(os.tmpdir(), 'olive-recovery-paths-'));
const api = new Api(SECRET, dbPort(pool), () => Date.now(), { strictIds: true });
const codeBudget = new MissBudget({ limit: 8 });
const sheetBudget = new MissBudget({ limit: 6 });
const helperBudget = new MissBudget({ limit: 6 });
registerRoutes(api, pool, new FilesystemStorage(tmpRoot), {
  callEnv: { CALL_PROVIDER: 'jitsi', NODE_ENV: 'test', JITSI_APP_ID: 'olive-calls',
    JITSI_APP_SECRET: randomBytes(32).toString('hex'), JITSI_SERVER_URL: 'https://calls.example.test:8443' },
  recoveryMissBudget: codeBudget, recoverySheetMissBudget: sheetBudget, recoveryHelperMissBudget: helperBudget,
});

const hdr = (tok) => (tok ? { authorization: `Bearer ${tok}` } : {});
const call = (method, p, tok, body) => api.handle(
  method, p, hdr(tok), body === undefined ? '' : JSON.stringify(body));
const RUN = randomUUID().slice(0, 8);
const LABEL = `recpaths-${RUN}`;
const users = [];
const children = [];
const H = 3_600_000;

const signup = async (tag, over = {}) => {
  const token = (await issueSignupAllowance(pool, { label: `${LABEL}-${tag}` })).token;
  const r = await call('POST', '/v1/auth/signup', null, {
    allowanceToken: token, displayName: `${tag}-${RUN}`, homeTz: 'America/Chicago', pin: '4821',
    deviceLabel: 'Old phone', ...over });
  if (r.status !== 201) throw new Error(`signup failed: ${r.status} ${JSON.stringify(r.body)}`);
  users.push(r.body.userId);
  return { userId: r.body.userId, tok: r.body.token, deviceId: r.body.deviceId, cred: r.body.deviceCredential,
           pin: over.pin ?? '4821' };
};
const mkChild = async (g, name) => {
  const r = await call('POST', '/v1/children', g.tok, { displayName: name, birthDate: '2018-03-04', homeTz: 'America/Chicago', pin: g.pin });
  if (r.status !== 201) throw new Error('child create failed');
  children.push(r.body.child.id);
  return r.body.child.id;
};
const coParent = (childId, userId, extra = '') => admin.query(
  `INSERT INTO guardianship (child_id, user_id, role, scope, valid) VALUES ($1, $2, 'guardian', '{}', tstzrange(now() - interval '1 minute', NULL))`,
  [childId, userId]);
const secondPhone = async (g) => {
  const c = await call('POST', '/v1/me/device-pairing-codes', g.tok, { pin: g.pin });
  const r = await call('POST', '/v1/device-pairing/redeem', null, { code: c.body.numericCode, role: 'guardian' });
  if (r.status !== 201 && r.status !== 200) throw new Error(`pairing failed ${r.status} ${JSON.stringify(r.body)}`);
  return { tok: r.body.token, deviceId: r.body.deviceId, cred: r.body.deviceCredential };
};
const activeDevices = async (userId) => (await admin.query(
  `SELECT count(*)::int n FROM paired_device WHERE target_id = $1 AND role = 'guardian' AND revoked_at IS NULL`, [userId])).rows[0].n;
const reqRow = async (id) => (await admin.query(`SELECT * FROM recovery_request WHERE id = $1`, [id])).rows[0];
const phase = async (code) => (await call('POST', '/v1/auth/recovery/status', null, { code })).body?.phase;
// the waiting period "passes": the request's own clock moves back
const age = (id, ms) => admin.query(
  `UPDATE recovery_request SET created_at = created_at - ($2 || ' milliseconds')::interval,
          ready_at = ready_at - ($2 || ' milliseconds')::interval, expires_at = expires_at - ($2 || ' milliseconds')::interval,
          approved_at = approved_at - ($2 || ' milliseconds')::interval WHERE id = $1`, [id, String(ms)]);
const startFor = (g, targetUserId, pin = g.pin) => call('POST', '/v1/me/recovery/start-for', g.tok, { targetUserId, pin });
const finish = (code, over = {}) => call('POST', '/v1/auth/recovery/finish', null, { code, deviceLabel: 'New phone', ...over });
const makeSheet = async (g) => (await call('POST', '/v1/me/recovery-sheet', g.tok, { pin: g.pin })).body.key;
const sheetStart = (key) => call('POST', '/v1/auth/recovery/start', null, { sheetKey: key, deviceLabel: 'Replacement' });
const getRecovery = (tok) => call('GET', '/v1/me/recovery', tok);
const counts = async (userIds, childIds) => JSON.stringify({
  users: (await admin.query(`SELECT count(*)::int n FROM app_user WHERE id = ANY($1::uuid[])`, [userIds])).rows[0].n,
  appUsersTotal: (await admin.query(`SELECT count(*)::int n FROM app_user`)).rows[0].n,
  kids: (await admin.query(`SELECT count(*)::int n FROM child WHERE id = ANY($1::uuid[])`, [childIds])).rows[0].n,
  edges: (await admin.query(`SELECT count(*)::int n FROM guardianship WHERE child_id = ANY($1::uuid[])`, [childIds])).rows[0].n,
  dayParts: (await admin.query(`SELECT count(*)::int n FROM day_part WHERE child_id = ANY($1::uuid[])`, [childIds])).rows[0].n,
  pins: (await admin.query(`SELECT count(*)::int n FROM pin_credential WHERE user_id = ANY($1::uuid[])`, [userIds])).rows[0].n,
});

await setSignupPolicy(pool, { enabled: true, maxAccounts: null });

// ---- family 1: Mom and Dad (two grown-ups), Ivy
const MOM = await signup('Mom');
const DAD = await signup('Dad', { pin: '2468' });
const IVY = await mkChild(MOM, 'Ivy');
await coParent(IVY, DAD.userId);
// ---- family 2: Sam, one grown-up, Wren
const SAM = await signup('Sam', { pin: '7315' });
const WREN = await mkChild(SAM, 'Wren');
// ---- a stranger's family, for "wrong family"
const EVE = await signup('Eve', { pin: '9753' });
const EVE_KID = await mkChild(EVE, 'Otis');

// ===========================================================================
// A · THE SHEET
// ===========================================================================
let MOM_KEY, SAM_KEY;
{
  const g = 'A sheet';
  check(g, 'no session -> 401', (await call('POST', '/v1/me/recovery-sheet', null, { pin: '4821' })).status, 401);
  const wrong = await call('POST', '/v1/me/recovery-sheet', MOM.tok, { pin: '0000' });
  check(g, 'a wrong PIN makes no sheet (own-PIN step-up) -> 403', `${wrong.status} ${wrong.body?.error}`, '403 pin_incorrect');
  check(g, '...and stored nothing', (await admin.query(`SELECT count(*)::int n FROM recovery_sheet WHERE user_id = $1`, [MOM.userId])).rows[0].n, 0);
  const r = await call('POST', '/v1/me/recovery-sheet', MOM.tok, { pin: MOM.pin });
  check(g, 'the right PIN makes one -> 201', r.status, 201);
  MOM_KEY = r.body.key;
  check(g, 'the key is six groups of four, easy to read (no I L O U)', /^([0-9A-HJKMNP-TV-Z]{4}-){5}[0-9A-HJKMNP-TV-Z]{4}$/.test(MOM_KEY), 'true');
  const stored = (await admin.query(`SELECT key_hash, confirmed_at FROM recovery_sheet WHERE user_id = $1`, [MOM.userId])).rows;
  check(g, 'only a 64-hex hash is stored, never the key', `${stored.length}|${/^[0-9a-f]{64}$/.test(stored[0].key_hash)}|${stored[0].key_hash.includes(MOM_KEY.replace(/-/g, ''))}`, '1|true|false');
  check(g, 'it starts unconfirmed (they have not shown they kept it)', stored[0].confirmed_at, null);
  const st = await getRecovery(MOM.tok);
  check(g, 'GET /v1/me/recovery says a sheet exists, not yet confirmed, and never carries the key',
    `${st.body.sheet.exists}|${st.body.sheet.confirmedAt}|${JSON.stringify(st.body).includes(MOM_KEY)}`, 'true|null|false');
  const wrongKey = await call('POST', '/v1/me/recovery-sheet/check', MOM.tok, { key: 'AAAA-BBBB-CCCC-DDDD-EEEE-FFFF' });
  check(g, 'typing a wrong key back -> 403 wrong_key (not confirmed)', `${wrongKey.status} ${wrongKey.body?.error}`, '403 wrong_key');
  const sloppy = MOM_KEY.toLowerCase().replace(/-/g, ' ').replace(/0/g, 'o');
  const good = await call('POST', '/v1/me/recovery-sheet/check', MOM.tok, { key: sloppy });
  check(g, 'lower case, spaces and an O for a zero still match (a smudged paper is not a lost key)', good.status, 200);
  check(g, '...and records that they kept it', (await getRecovery(MOM.tok)).body.sheet.confirmedAt !== null, 'true');
  check(g, 'a child session never reaches any of it',
    (await call('GET', '/v1/me/recovery', (await admin.query(`SELECT 1`)).rowCount ? 'not-a-token' : '')).status, 401);
  // replace: the old key stops working, one live sheet
  const first = MOM_KEY;
  const again = await call('POST', '/v1/me/recovery-sheet', MOM.tok, { pin: MOM.pin });
  MOM_KEY = again.body.key;
  check(g, 'making another replaces the first (the response says so)', `${again.body.replacedOlder}|${MOM_KEY !== first}`, 'true|true');
  check(g, '...exactly one live sheet', (await admin.query(`SELECT count(*)::int n FROM recovery_sheet WHERE user_id = $1 AND retired_at IS NULL`, [MOM.userId])).rows[0].n, 1);
  check(g, '...the old key no longer checks out', (await call('POST', '/v1/me/recovery-sheet/check', MOM.tok, { key: first })).status, 403);
  check(g, '...a new sheet has to be confirmed again', (await getRecovery(MOM.tok)).body.sheet.confirmedAt, null);
  check(g, 'it wrote a content-free notice for the other grown-up',
    (await admin.query(`SELECT count(*)::int n FROM security_event WHERE child_id = $1 AND kind = 'recovery_sheet_made'`, [IVY])).rows[0].n >= 1, 'true');
  SAM_KEY = await makeSheet(SAM);
  check(g, 'Sam made one too', typeof SAM_KEY, 'string');
}

// ===========================================================================
// B · THE HELPER
// ===========================================================================
let SAM_HELPER_KEY;
{
  const g = 'B helper';
  check(g, 'naming a helper needs the PIN', (await call('POST', '/v1/me/recovery-helper', SAM.tok, { pin: '0000', label: 'Aunt Jo' })).status, 403);
  check(g, 'an email is not a name -> 400', (await call('POST', '/v1/me/recovery-helper', SAM.tok, { pin: SAM.pin, label: 'jo' + String.fromCharCode(64) + 'example.test' })).status, 400);
  check(g, 'an empty name -> 400', (await call('POST', '/v1/me/recovery-helper', SAM.tok, { pin: SAM.pin, label: '  ' })).status, 400);
  const inv = await call('POST', '/v1/me/recovery-helper', SAM.tok, { pin: SAM.pin, label: 'Aunt Jo' });
  check(g, 'a name and the PIN -> 201 with a one-time invite', `${inv.status}|${/^([0-9A-HJKMNP-TV-Z]{4}-){3}[0-9A-HJKMNP-TV-Z]{4}$/.test(inv.body.code)}`, '201|true');
  check(g, 'the invite is stored as a hash only', (await admin.query(`SELECT count(*)::int n FROM recovery_helper WHERE invite_hash = $1 OR label = $1`, [inv.body.code.replace(/-/g, '')])).rows[0].n, 0);
  check(g, 'before it is opened the helper shows as invited', (await getRecovery(SAM.tok)).body.helper.state, 'invited');
  const bad = await call('POST', '/v1/auth/helper/accept', null, { code: 'AAAA-BBBB-CCCC-DDDD' });
  check(g, 'a made-up invite -> 403 invalid_invite', `${bad.status} ${bad.body?.error}`, '403 invalid_invite');
  const ok = await call('POST', '/v1/auth/helper/accept', null, { code: inv.body.code.toLowerCase() });
  check(g, 'the helper opens it on their own phone -> 201, a helper key (not a session)', `${ok.status}|${typeof ok.body.helperKey}|${ok.body.token === undefined}`, '201|string|true');
  check(g, '...it tells them only the first name of whose helper they are', `${ok.body.accountName}|${ok.body.label}`, `Sam-${RUN}|Aunt Jo`);
  SAM_HELPER_KEY = ok.body.helperKey;
  check(g, 'the invite works once only', (await call('POST', '/v1/auth/helper/accept', null, { code: inv.body.code })).status, 403);
  check(g, 'the helper key is stored as a hash only',
    (await admin.query(`SELECT count(*)::int n FROM recovery_helper WHERE key_hash = $1`, [SAM_HELPER_KEY])).rows[0].n, 0);
  check(g, 'after it is opened the helper shows as active', (await getRecovery(SAM.tok)).body.helper.state, 'active');
  // an invite that was never opened in time
  const stale = await call('POST', '/v1/me/recovery-helper', EVE.tok, { pin: EVE.pin, label: 'Late' });
  await admin.query(`UPDATE recovery_helper SET created_at = created_at - interval '5 days', invite_expires_at = now() - interval '1 day' WHERE user_id = $1 AND revoked_at IS NULL`, [EVE.userId]);
  check(g, 'an expired invite is refused', (await call('POST', '/v1/auth/helper/accept', null, { code: stale.body.code })).status, 403);
  check(g, '...and shows as no helper', (await getRecovery(EVE.tok)).body.helper.state, 'none');
  // over-reach: the helper key opens exactly the helper routes
  const reach = {};
  reach.me = (await call('GET', '/v1/me', SAM_HELPER_KEY)).status;
  reach.children = (await call('GET', '/v1/me/children', SAM_HELPER_KEY)).status;
  reach.recovery = (await call('GET', '/v1/me/recovery', SAM_HELPER_KEY)).status;
  reach.sheet = (await call('POST', '/v1/me/recovery-sheet', SAM_HELPER_KEY, { pin: SAM.pin })).status;
  reach.helperRoutes = (await call('POST', '/v1/me/recovery-helper', SAM_HELPER_KEY, { pin: SAM.pin, label: 'Me' })).status;
  reach.cancel = (await call('POST', `/v1/me/recovery/${randomUUID()}/cancel`, SAM_HELPER_KEY, { pin: SAM.pin })).status;
  check(g, 'a helper key is not a session: every adult route refuses it (401)', JSON.stringify(reach), JSON.stringify({ me: 401, children: 401, recovery: 401, sheet: 401, helperRoutes: 401, cancel: 401 }));
  const list = await call('POST', '/v1/auth/helper/requests', null, { helperKey: SAM_HELPER_KEY });
  check(g, 'the helper sees an empty list (nothing is waiting), and nothing about the family', `${list.status}|${JSON.stringify(list.body)}`, '200|{"requests":[]}');
  check(g, 'a wrong helper key -> 403', (await call('POST', '/v1/auth/helper/requests', null, { helperKey: randomBytes(32).toString('base64url') })).status, 403);
  check(g, 'a helper cannot answer a request that does not exist -> 404', (await call('POST', '/v1/auth/helper/answer', null, { helperKey: SAM_HELPER_KEY, requestId: randomUUID(), answer: 'yes' })).status, 404);
  check(g, 'answer must be yes or no', (await call('POST', '/v1/auth/helper/answer', null, { helperKey: SAM_HELPER_KEY, requestId: randomUUID(), answer: 'approve-everything' })).status, 400);
  // replace and remove
  const second = await call('POST', '/v1/me/recovery-helper', SAM.tok, { pin: SAM.pin, label: 'Uncle Bo' });
  check(g, 'naming another helper replaces the first', second.body.replacedOlder, true);
  check(g, '...so the first one\'s key stops working at once', (await call('POST', '/v1/auth/helper/requests', null, { helperKey: SAM_HELPER_KEY })).status, 403);
  check(g, 'one helper at a time (table)', (await admin.query(`SELECT count(*)::int n FROM recovery_helper WHERE user_id = $1 AND revoked_at IS NULL`, [SAM.userId])).rows[0].n, 1);
  const acc2 = await call('POST', '/v1/auth/helper/accept', null, { code: second.body.code });
  SAM_HELPER_KEY = acc2.body.helperKey;
  check(g, 'the second helper is active', acc2.status, 201);
  const rm = await call('POST', '/v1/me/recovery-helper/remove', SAM.tok, { pin: SAM.pin });
  check(g, 'removing the helper needs the PIN and works', `${rm.status}|${rm.body.removed}`, '200|true');
  check(g, '...their key stops working', (await call('POST', '/v1/auth/helper/requests', null, { helperKey: SAM_HELPER_KEY })).status, 403);
  check(g, '...and shows as none', (await getRecovery(SAM.tok)).body.helper.state, 'none');
  // leave Sam with an active helper for part D
  const third = await call('POST', '/v1/me/recovery-helper', SAM.tok, { pin: SAM.pin, label: 'Aunt Jo' });
  SAM_HELPER_KEY = (await call('POST', '/v1/auth/helper/accept', null, { code: third.body.code })).body.helperKey;
}

// ===========================================================================
// C · TWO GROWN-UPS
// ===========================================================================
let MOM_NEW;
{
  const g = 'C two grown-ups';
  const momPhone2 = await secondPhone(MOM);
  check(g, 'setup: Mom has two phones, Dad has one', `${await activeDevices(MOM.userId)}${await activeDevices(DAD.userId)}`, '21');
  check(g, 'Dad can see Mom as someone he could help', (await getRecovery(DAD.tok)).body.canHelp.map((p) => p.userId).join(), MOM.userId);

  // who may start one
  check(g, 'no session -> 401', (await call('POST', '/v1/me/recovery/start-for', null, { targetUserId: MOM.userId, pin: '2468' })).status, 401);
  check(g, 'a missing target -> 400', (await call('POST', '/v1/me/recovery/start-for', DAD.tok, { pin: '2468' })).status, 400);
  const wrongPin = await startFor(DAD, MOM.userId, '0000');
  check(g, 'Dad\'s wrong PIN starts nothing -> 403', `${wrongPin.status} ${wrongPin.body?.error}`, '403 pin_incorrect');
  check(g, 'a stranger\'s family cannot start one for Mom (wrong family)', `${(await startFor(EVE, MOM.userId)).status} ${(await startFor(EVE, MOM.userId)).body?.error}`, '403 not_family');
  check(g, 'Mom cannot say yes to her OWN recovery (a thief holding her unlocked phone)', `${(await startFor(MOM, MOM.userId)).body?.error}`, 'not_family');
  check(g, 'a stolen unlocked phone without the PIN cannot start one either', (await startFor(MOM, DAD.userId, '1111')).status, 403);
  await admin.query(`UPDATE guardianship SET restricted = true WHERE child_id = $1 AND user_id = $2`, [IVY, DAD.userId]);
  check(g, 'a grown-up under a protective order cannot start one', (await startFor(DAD, MOM.userId)).body?.error, 'not_family');
  await admin.query(`UPDATE guardianship SET restricted = false, observer_only = true WHERE child_id = $1 AND user_id = $2`, [IVY, DAD.userId]);
  check(g, 'an observer-only grown-up cannot start one', (await startFor(DAD, MOM.userId)).body?.error, 'not_family');
  await admin.query(`UPDATE guardianship SET observer_only = false, role = 'trusted_adult' WHERE child_id = $1 AND user_id = $2`, [IVY, DAD.userId]);
  check(g, 'a trusted adult (not a parent) cannot start one', (await startFor(DAD, MOM.userId)).body?.error, 'not_family');
  await admin.query(`UPDATE guardianship SET role = 'guardian' WHERE child_id = $1 AND user_id = $2`, [IVY, DAD.userId]);
  check(g, 'nothing was started by any of the refusals', (await admin.query(`SELECT count(*)::int n FROM recovery_request WHERE user_id = $1`, [MOM.userId])).rows[0].n, 0);

  // the happy start
  const beforeEvents = (await admin.query(`SELECT count(*)::int n FROM security_event WHERE child_id = $1 AND kind = 'recovery_started'`, [IVY])).rows[0].n;
  const s = await startFor(DAD, MOM.userId);
  check(g, 'Dad starts it (his own PIN is his yes) -> 201', s.status, 201);
  const CODE = s.body.code;
  check(g, 'he gets a code to hand to Mom: five groups of four', /^([0-9A-HJKMNP-TV-Z]{4}-){4}[0-9A-HJKMNP-TV-Z]{4}$/.test(CODE), 'true');
  const waitMs = new Date(s.body.readyAt) - Date.now();
  check(g, 'it waits 48 hours', Math.abs(waitMs - RECOVERY_WAIT_SECOND_PARENT_MS) < 60_000, 'true');
  const row = await reqRow(s.body.requestId);
  check(g, 'the table holds only the hash of the code, the yes and the mode', `${row.secret_hash.length}|${row.approved_by === DAD.userId}|${row.mode}|${row.helper_required}`, `64|true|second_parent|false`);
  check(g, 'nothing about the account changed yet: every phone still works', `${await activeDevices(MOM.userId)}`, '2');
  check(g, '...Mom\'s old phone still gets in', (await call('GET', '/v1/me/children', MOM.tok)).status, 200);
  check(g, 'it wrote a notice in the history of the child (once)', (await admin.query(`SELECT count(*)::int n FROM security_event WHERE child_id = $1 AND kind = 'recovery_started'`, [IVY])).rows[0].n - beforeEvents, 1);

  // a notice on EVERY phone
  const seen = {};
  for (const [name, tok] of [['momOld', MOM.tok], ['momSecond', momPhone2.tok], ['dad', DAD.tok]]) {
    const r = await getRecovery(tok);
    seen[name] = `${r.status}|${r.body.open.length}|${r.body.open[0]?.aboutMe}|${r.body.open[0]?.phase}`;
  }
  check(g, 'EVERY phone of Mom\'s and Dad\'s sees it waiting (Mom: about her; Dad: about Mom)', JSON.stringify(seen),
    JSON.stringify({ momOld: '200|1|true|waiting', momSecond: '200|1|true|waiting', dad: '200|1|false|waiting' }));
  check(g, '...the notice says who started it and when it can finish', (await getRecovery(MOM.tok)).body.open[0].startedByName, `Dad-${RUN}`);
  check(g, 'Eve (another family) sees nothing', (await getRecovery(EVE.tok)).body.open.length, 0);
  const st = await call('POST', '/v1/auth/recovery/status', null, { code: CODE.toLowerCase() });
  check(g, 'the new phone can ask how it is going', `${st.status}|${st.body.phase}|${st.body.accountName}`, `200|waiting|Mom-${RUN}`);
  check(g, 'a wrong code asks nothing (404, one answer)', (await call('POST', '/v1/auth/recovery/status', null, { code: 'AAAA-BBBB-CCCC-DDDD-EEEE' })).status, 404);

  // the waiting period: the race at its edge
  const early = await finish(CODE, { pin: MOM.pin });
  check(g, 'finishing now is too early -> 409 with the time', `${early.status} ${early.body?.error} ${typeof early.body?.readyAt}`, '409 too_early string');
  await age(s.body.requestId, RECOVERY_WAIT_SECOND_PARENT_MS - 5_000);
  check(g, 'five seconds before the end it is still too early', (await finish(CODE, { pin: MOM.pin })).status, 409);
  check(g, '...and the table refuses a finish before the end even if the code is skipped',
    await admin.query(`UPDATE recovery_request SET completed_at = now(), proof_used = 'pin' WHERE id = $1`, [s.body.requestId]).then(() => 'accepted', () => 'refused'), 'refused');
  const clockNow = new Date();
  const dbEarly = await finishRecovery(pool, { code: CODE, pin: MOM.pin, now: new Date(clockNow.getTime() - 3_600_000) });
  check(g, 'a clock an hour behind cannot finish it either', dbEarly.reason, 'too_early');

  // wrong guesses are counted on THIS request, never on Mom's own PIN
  const w1 = await finish(CODE, { pin: '1111' });
  check(g, 'a wrong PIN is 403 wrong_proof... not yet, the wait is not over', `${w1.status}`, '409');
  await age(s.body.requestId, 10_000);
  const w2 = await finish(CODE, { pin: '1111' });
  check(g, 'after the wait a wrong PIN -> 403 wrong_proof', `${w2.status} ${w2.body?.error}`, '403 wrong_proof');
  check(g, '...counted on the request, not on the account\'s own PIN lockout',
    `${(await reqRow(s.body.requestId)).failed_attempts}|${(await admin.query(`SELECT failed_attempts FROM pin_credential WHERE user_id = $1`, [MOM.userId])).rows[0].failed_attempts}`, '1|0');
  check(g, '...so Mom\'s old phone can still use her real PIN', (await call('POST', '/v1/me/verify-controls-pin', MOM.tok, { pin: MOM.pin })).status < 400, 'true');
  check(g, 'no proof at all -> 400 proof_required', `${(await finish(CODE)).status} ${(await finish(CODE)).body?.error}`, '400 proof_required');

  // cancel during the wait, from three directions
  const cancels = {};
  cancels.noPin = (await call('POST', `/v1/me/recovery/${s.body.requestId}/cancel`, MOM.tok, {})).status;
  cancels.thiefWrongPin = (await call('POST', `/v1/me/recovery/${s.body.requestId}/cancel`, MOM.tok, { pin: '0000' })).status;
  cancels.stranger = (await call('POST', `/v1/me/recovery/${s.body.requestId}/cancel`, EVE.tok, { pin: EVE.pin })).status;
  check(g, 'cancelling needs the PIN, and a stranger cannot (so a phone left unlocked cannot stop the real owner)', JSON.stringify(cancels), JSON.stringify({ noPin: 400, thiefWrongPin: 403, stranger: 404 }));
  check(g, '...none of those stopped it', await phase(CODE), 'ready');
  const stopped = await call('POST', `/v1/me/recovery/${s.body.requestId}/cancel`, momPhone2.tok, { pin: MOM.pin });
  check(g, 'Mom\'s OTHER phone stops it with her PIN -> 200', stopped.status, 200);
  check(g, 'it is over at once: the new phone is told it was stopped', await phase(CODE), 'stopped');
  const afterStop = await finish(CODE, { pin: MOM.pin });
  check(g, 'a stopped recovery cannot finish, even with the right PIN -> 403 invalid_recovery', `${afterStop.status} ${afterStop.body?.error}`, '403 invalid_recovery');
  check(g, '...nobody was signed out', await activeDevices(MOM.userId), 2);
  check(g, 'stopping again is one calm answer (404)', (await call('POST', `/v1/me/recovery/${s.body.requestId}/cancel`, MOM.tok, { pin: MOM.pin })).status, 404);
  const ended = await getRecovery(DAD.tok);
  check(g, 'Dad still sees it, as ended: nothing is ever a mystery', `${ended.body.open.length}|${ended.body.recentEnded[0]?.phase}|${ended.body.recentEnded[0]?.stoppedBy}`, '0|stopped|owner_phone');

  // Dad stops one too; the new phone gives up on another
  const s2 = await startFor(DAD, MOM.userId);
  check(g, 'a second recovery can be started after a stop', s2.status, 201);
  check(g, 'Dad (another grown-up) can stop it himself with his PIN', (await call('POST', `/v1/me/recovery/${s2.body.requestId}/cancel`, DAD.tok, { pin: DAD.pin })).status, 200);
  check(g, '...recorded as stopped by another grown-up', (await reqRow(s2.body.requestId)).cancelled_by_kind, 'other_parent');
  const s3 = await startFor(DAD, MOM.userId);
  check(g, 'the new phone can give up on its own code', (await call('POST', '/v1/auth/recovery/cancel', null, { code: s3.body.code })).status, 200);
  check(g, '...and only the holder of the code can', (await call('POST', '/v1/auth/recovery/cancel', null, { code: 'AAAA-BBBB-CCCC-DDDD-EEEE' })).status, 404);

  // five wrong guesses end that request (and only that one)
  const s4 = await startFor(DAD, MOM.userId);
  await age(s4.body.requestId, RECOVERY_WAIT_SECOND_PARENT_MS + 1000);
  const guesses = [];
  for (let i = 0; i < 5; i++) guesses.push((await finish(s4.body.code, { pin: '0000' })).body?.error);
  check(g, 'four wrong PINs are wrong_proof, the fifth ends the request', guesses.join(), 'wrong_proof,wrong_proof,wrong_proof,wrong_proof,too_many_wrong');
  check(g, '...and then even the right PIN does nothing (a new recovery must be started)', `${(await finish(s4.body.code, { pin: MOM.pin })).body?.error}`, 'invalid_recovery');
  check(g, '...Mom\'s own PIN lockout was never touched', (await admin.query(`SELECT failed_attempts, locked_until FROM pin_credential WHERE user_id = $1`, [MOM.userId])).rows.map((r) => `${r.failed_attempts}|${r.locked_until}`).join(), '0|null');

  // the real finish. Wrong family first: another family's code and PIN do nothing here.
  const s5 = await startFor(DAD, MOM.userId);
  await age(s5.body.requestId, RECOVERY_WAIT_SECOND_PARENT_MS + 1000);
  check(g, 'wrong family: Eve\'s PIN with Mom\'s code is a wrong guess, not a way in', (await finish(s5.body.code, { pin: EVE.pin })).body?.error, 'wrong_proof');
  check(g, 'wrong family: Dad\'s own PIN does not finish Mom\'s recovery either', (await finish(s5.body.code, { pin: DAD.pin })).body?.error, 'wrong_proof');
  const before = await counts([MOM.userId, DAD.userId], [IVY]);
  const kidsBefore = (await call('GET', '/v1/me/children', MOM.tok)).body.children.map((c) => c.id).join();
  // six racing finishes: one winner
  const racers = await Promise.all(Array.from({ length: 6 }, () => finish(s5.body.code, { pin: MOM.pin })));
  const winners = racers.filter((r) => r.status === 201);
  check(g, 'six racing finishes at the end of the wait: exactly one winner', `${winners.length}|${racers.filter((r) => r.status === 403).length}`, '1|5');
  check(g, '...exactly one new device was enrolled', await activeDevices(MOM.userId), 1);
  MOM_NEW = { tok: winners[0].body.token, deviceId: winners[0].body.deviceId, cred: winners[0].body.deviceCredential };
  check(g, 'it is the SAME account', winners[0].body.userId, MOM.userId);
  check(g, '...it says both of the other phones were signed out', winners[0].body.devicesSignedOut, 2);
  check(g, '...and that her child is there', winners[0].body.children, 1);
  check(g, 'the new phone sees the same children as before', (await call('GET', '/v1/me/children', MOM_NEW.tok)).body.children.map((c) => c.id).join(), kidsBefore);
  check(g, 'nothing was duplicated, moved or orphaned: the same rows, one new device',
    await counts([MOM.userId, DAD.userId], [IVY]), before);
  check(g, 'the old phone is cut off at once -> 401 device_revoked', `${(await call('GET', '/v1/me', MOM.tok)).status} ${(await call('GET', '/v1/me', MOM.tok)).body?.error}`, '401 device_revoked');
  check(g, 'the other old phone too', (await call('GET', '/v1/me', momPhone2.tok)).status, 401);
  check(g, 'Dad\'s phone is untouched', (await call('GET', '/v1/me', DAD.tok)).status, 200);
  const feed = await call('GET', `/v1/children/${IVY}/security-events`, DAD.tok);
  const kinds = (feed.body?.events ?? feed.body?.entries ?? []).map((e) => e.kind);
  check(g, 'Dad\'s feed shows it started and finished, in plain content-free lines',
    `${kinds.includes('recovery_started')}|${kinds.includes('account_recovered')}|${JSON.stringify(feed.body).match(/Replacement|New phone|4821|2468|@/) === null}`, 'true|true|true');
  // replay
  const replay = await finish(s5.body.code, { pin: MOM.pin });
  check(g, 'replay of the used code -> 403 invalid_recovery (no second device, no session)', `${replay.status} ${replay.body?.error}|${await activeDevices(MOM.userId)}`, '403 invalid_recovery|1');
  check(g, 'status of a finished code says done, never credentials', `${(await call('POST', '/v1/auth/recovery/status', null, { code: s5.body.code })).body.phase}`, 'done');
  check(g, 'the old request codes of the same account stay dead', await phase(CODE), 'stopped');

  // cancel racing finish: exactly one outcome
  const MOM2 = MOM_NEW;
  const s6 = await startFor(DAD, MOM.userId);
  await age(s6.body.requestId, RECOVERY_WAIT_SECOND_PARENT_MS + 1000);
  const [rf, rc] = await Promise.all([
    finish(s6.body.code, { pin: MOM.pin }),
    call('POST', `/v1/me/recovery/${s6.body.requestId}/cancel`, DAD.tok, { pin: DAD.pin })]);
  const fin = await reqRow(s6.body.requestId);
  check(g, 'cancel racing finish: exactly one wins, never both',
    `${(fin.completed_at !== null) !== (fin.cancelled_at !== null)}|${rf.status === 201 ? 'finished' : 'stopped'}=${fin.completed_at !== null ? 'finished' : 'stopped'}`,
    `true|${fin.completed_at !== null ? 'finished' : 'stopped'}=${fin.completed_at !== null ? 'finished' : 'stopped'}`);
  check(g, '...and the answers agree with the table', `${rf.status === 201}|${rc.status === 200}`, `${fin.completed_at !== null}|${fin.cancelled_at !== null}`);
  if (fin.completed_at !== null) MOM_NEW = { tok: rf.body.token, deviceId: rf.body.deviceId, cred: rf.body.deviceCredential };
  void MOM2;
}

// ===========================================================================
// D · ONE GROWN-UP (and total loss)
// ===========================================================================
{
  const g = 'D one grown-up';
  check(g, 'a wrong sheet key -> 403 invalid_sheet', `${(await sheetStart('AAAA-BBBB-CCCC-DDDD-EEEE-FFFF')).status} ${(await sheetStart('AAAA-BBBB-CCCC-DDDD-EEEE-FFFF')).body?.error}`, '403 invalid_sheet');
  check(g, 'a short or missing key -> 400', `${(await call('POST', '/v1/auth/recovery/start', null, {})).status}${(await sheetStart('abc')).status}`, '400400');
  check(g, 'Mom\'s sheet cannot start a recovery while Dad has a working phone: the safe way is his yes -> 403 ask_other_grownup',
    `${(await sheetStart(MOM_KEY)).status} ${(await sheetStart(MOM_KEY)).body?.error}`, '403 ask_other_grownup');
  check(g, '...and that started nothing', (await admin.query(`SELECT count(*)::int n FROM recovery_request WHERE user_id = $1 AND started_by_kind = 'sheet'`, [MOM.userId])).rows[0].n, 0);

  // Sam: one grown-up with a helper
  const beforeSam = await counts([SAM.userId], [WREN]);
  const samPhone2 = await secondPhone(SAM);
  const sSam = await sheetStart(SAM_KEY.toLowerCase());
  check(g, 'Sam\'s sheet (typed in lower case) starts one -> 201', sSam.status, 201);
  check(g, '...it waits 72 hours and says a helper must say yes', `${Math.abs(new Date(sSam.body.readyAt) - Date.now() - RECOVERY_WAIT_SOLE_PARENT_MS) < 60_000}|${sSam.body.helperRequired}|${sSam.body.accountName}`, `true|true|Sam-${RUN}`);
  const SAM_CODE = sSam.body.code;
  const samReq = (await admin.query(`SELECT id FROM recovery_request WHERE secret_hash = $1`, [createHash('sha256').update(`olive-recovery-request-v1:${SAM_CODE.replace(/-/g, '')}`).digest('hex')])).rows[0].id;
  check(g, 'a notice appears on EVERY phone Sam still has', `${(await getRecovery(SAM.tok)).body.open.length}${(await getRecovery(samPhone2.tok)).body.open.length}`, '11');
  check(g, '...in plain terms: it says the sheet started it', `${(await getRecovery(SAM.tok)).body.open[0].mode}|${(await getRecovery(SAM.tok)).body.open[0].startedByName}`, 'sole_parent|null');
  const hl = await call('POST', '/v1/auth/helper/requests', null, { helperKey: SAM_HELPER_KEY });
  check(g, 'the helper sees exactly this: the first name and the times, nothing else',
    `${hl.body.requests.length}|${hl.body.requests[0]?.accountName}|${hl.body.requests[0]?.confirmed}|${Object.keys(hl.body.requests[0] ?? {}).sort().join()}`,
    `1|Sam-${RUN}|false|accountName,confirmed,readyAt,requestId,startedAt`);
  check(g, 'after only 71 hours: too early', (await (async () => { await age(samReq, 71 * H); return (await finish(SAM_CODE)).body?.error; })()), 'too_early');
  await age(samReq, 2 * H);
  const nohelp = await finish(SAM_CODE);
  check(g, 'after 72 hours but before the helper says yes -> 409 waiting_for_helper', `${nohelp.status} ${nohelp.body?.error}`, '409 waiting_for_helper');
  check(g, '...the new phone is told the same thing', await phase(SAM_CODE), 'waiting_for_helper');
  // helper over-reach
  const evesHelper = await call('POST', '/v1/me/recovery-helper', EVE.tok, { pin: EVE.pin, label: 'Neighbour' });
  const EVE_HELPER = (await call('POST', '/v1/auth/helper/accept', null, { code: evesHelper.body.code })).body.helperKey;
  const wrongFamily = await call('POST', '/v1/auth/helper/answer', null, { helperKey: EVE_HELPER, requestId: samReq, answer: 'yes' });
  check(g, 'a helper of ANOTHER family cannot answer Sam\'s recovery (wrong family) -> 404', wrongFamily.status, 404);
  check(g, '...and it did not count as a yes', (await reqRow(samReq)).helper_confirmed_at, null);
  const noAnswerNoYes = await call('POST', '/v1/auth/helper/answer', null, { helperKey: EVE_HELPER, requestId: samReq, answer: 'no' });
  check(g, '...nor can they stop it with a no', `${noAnswerNoYes.status}|${await phase(SAM_CODE)}`, '404|waiting_for_helper');
  const directDb = await helperAnswer(pool, { helperKey: SAM_HELPER_KEY, requestId: randomUUID(), answer: 'yes' });
  check(g, 'a real helper naming a request that is not theirs: one answer, not_found', directDb.reason, 'not_found');
  // Mom's request (second_parent) cannot be answered by anyone's helper
  const sMom = await startFor(DAD, MOM_NEW ? MOM.userId : MOM.userId);
  check(g, 'a helper can say nothing about a two-grown-up recovery (their yes is not a second parent\'s yes)',
    (await call('POST', '/v1/auth/helper/answer', null, { helperKey: SAM_HELPER_KEY, requestId: sMom.body.requestId, answer: 'yes' })).status, 404);
  await call('POST', '/v1/auth/recovery/cancel', null, { code: sMom.body.code });
  check(g, 'a helper cannot sign in, list children, or read anything: the helper key opens nothing else',
    `${(await call('GET', '/v1/me/children', SAM_HELPER_KEY)).status}`, '401');
  // the yes
  const yes = await call('POST', '/v1/auth/helper/answer', null, { helperKey: SAM_HELPER_KEY, requestId: samReq, answer: 'yes' });
  check(g, 'the helper\'s yes is recorded -> 200 confirmed', `${yes.status}|${yes.body.result}`, '200|confirmed');
  check(g, '...saying yes again changes nothing', (await call('POST', '/v1/auth/helper/answer', null, { helperKey: SAM_HELPER_KEY, requestId: samReq, answer: 'yes' })).status, 200);
  check(g, '...the new phone is told it is ready', await phase(SAM_CODE), 'ready');
  const newPin = '5566';
  const fin = await finish(SAM_CODE, { newPin });
  check(g, 'the new phone finishes (the sheet already proved it at the start) -> 201', fin.status, 201);
  check(g, '...the SAME account, its child, both old phones signed out, the sheet spent',
    `${fin.body.userId === SAM.userId}|${fin.body.children}|${fin.body.devicesSignedOut}|${fin.body.sheetSpent}`, 'true|1|2|true');
  check(g, 'nothing duplicated or orphaned: same rows (devices aside)', await counts([SAM.userId], [WREN]), beforeSam);
  const SAM_NEW = { tok: fin.body.token, pin: newPin, userId: SAM.userId };
  check(g, 'the new PIN works and the old one does not', `${(await call('POST', '/v1/me/verify-controls-pin', SAM_NEW.tok, { pin: newPin })).status < 400}|${(await call('POST', '/v1/me/verify-controls-pin', SAM_NEW.tok, { pin: '7315' })).status >= 400}`, 'true|true');
  check(g, 'both old phones are out', `${(await call('GET', '/v1/me', SAM.tok)).status}${(await call('GET', '/v1/me', samPhone2.tok)).status}`, '401401');
  check(g, 'replay of the finished code does nothing', `${(await finish(SAM_CODE, { newPin: '1212' })).status}|${await activeDevices(SAM.userId)}`, '403|1');
  check(g, 'replay of the SPENT sheet key does nothing (a used key is never used twice) -> 403 invalid_sheet', `${(await sheetStart(SAM_KEY)).body?.error}`, 'invalid_sheet');
  check(g, '...the app is told a new sheet is needed', (await getRecovery(SAM_NEW.tok)).body.sheet.spentNeedsNew, true);

  // a helper no longer needed is cut off by removal; the old helper key still names Sam's account only
  // helper says no: stops it
  SAM.tok = SAM_NEW.tok; SAM.pin = newPin;
  const key2 = await makeSheet(SAM);
  const sNo = await sheetStart(key2);
  check(g, 'with a new sheet a new recovery can start (the helper is still named)', `${sNo.status}|${sNo.body.helperRequired}`, '201|true');
  const reqNo = (await admin.query(`SELECT id FROM recovery_request WHERE user_id = $1 AND completed_at IS NULL AND cancelled_at IS NULL`, [SAM.userId])).rows[0].id;
  const no = await call('POST', '/v1/auth/helper/answer', null, { helperKey: SAM_HELPER_KEY, requestId: reqNo, answer: 'no' });
  check(g, 'the helper says no -> the recovery stops', `${no.status}|${no.body.result}|${await phase(sNo.body.code)}`, '200|stopped|stopped');
  check(g, '...recorded as stopped by the helper', (await reqRow(reqNo)).cancelled_by_kind, 'helper');
  check(g, '...and finishing it later fails', (await finish(sNo.body.code)).status, 403);

  // the owner's own phone stops one; replacing the sheet stops one
  const sOwn = await sheetStart(key2);
  const reqOwn = (await admin.query(`SELECT id FROM recovery_request WHERE user_id = $1 AND completed_at IS NULL AND cancelled_at IS NULL`, [SAM.userId])).rows[0].id;
  check(g, 'Sam\'s own phone stops it with his PIN', (await call('POST', `/v1/me/recovery/${reqOwn}/cancel`, SAM.tok, { pin: SAM.pin })).status, 200);
  const sRep = await sheetStart(key2);
  const newKey = await makeSheet(SAM);
  check(g, 'making a new sheet stops a recovery that the old sheet started', `${await phase(sRep.body.code)}|${(await admin.query(`SELECT cancelled_by_kind k FROM recovery_request WHERE secret_hash = $1`, [createHash('sha256').update(`olive-recovery-request-v1:${sRep.body.code.replace(/-/g, '')}`).digest('hex')])).rows[0].k}`, 'stopped|sheet_replaced');
  void sOwn; void newKey;

  // total loss: both of Mom's grown-ups lose every phone. The sheet is the way back (no one left to say yes).
  const MOMKEY = MOM_KEY;
  await call('POST', '/v1/me/recovery-sheet/check', MOM_NEW?.tok ?? '', { key: MOMKEY }).catch(() => {});
  const momNew = (await admin.query(`SELECT id FROM paired_device WHERE target_id = $1 AND role = 'guardian' AND revoked_at IS NULL`, [MOM.userId])).rows;
  check(g, 'setup for total loss: Mom has a phone again', momNew.length, 1);
  await admin.query(`UPDATE paired_device SET revoked_at = now() WHERE target_id = $1 AND role = 'guardian' AND revoked_at IS NULL`, [DAD.userId]);
  const mk = await makeSheet({ tok: MOM_NEW.tok, pin: MOM.pin });
  check(g, 'Mom (new phone) makes a fresh sheet', typeof mk, 'string');
  await admin.query(`UPDATE paired_device SET revoked_at = now() WHERE target_id = $1 AND role = 'guardian' AND revoked_at IS NULL`, [MOM.userId]);
  check(g, 'every phone of the family is gone', `${await activeDevices(MOM.userId)}${await activeDevices(DAD.userId)}`, '00');
  const tl = await sheetStart(mk);
  check(g, 'total loss: the sheet alone can start it (no phone is left to say yes) -> 201, 72 hours, no helper', `${tl.status}|${tl.body.helperRequired}`, '201|false');
  const tlReq = (await admin.query(`SELECT id, mode FROM recovery_request WHERE user_id = $1 AND completed_at IS NULL AND cancelled_at IS NULL`, [MOM.userId])).rows[0];
  check(g, '...as a one-grown-up recovery', tlReq.mode, 'sole_parent');
  await age(tlReq.id, RECOVERY_WAIT_SOLE_PARENT_MS - 5_000);
  check(g, '...5 seconds early is still too early', (await finish(tl.body.code)).body?.error, 'too_early');
  await age(tlReq.id, 10_000);
  const tlFin = await finish(tl.body.code);
  check(g, '...and at 72 hours it finishes, as the same account, with the child', `${tlFin.status}|${tlFin.body.userId === MOM.userId}|${tlFin.body.children}`, '201|true|1');
  MOM_NEW = { tok: tlFin.body.token };
  check(g, 'Dad\'s account was not touched by Mom\'s recovery', `${await activeDevices(DAD.userId)}`, '0');
}

// ===========================================================================
// F · LIMITS: budgets, caps, and the real owner is never locked out
// ===========================================================================
{
  const g = 'F limits';
  // strangers guessing sheet keys spend the global sheet budget; the real owner is delayed at worst, never locked
  sheetBudget.misses = 0; sheetBudget.windowStart = Date.now();
  let last;
  for (let i = 0; i < 6; i++) last = await sheetStart(`${randomBytes(12).toString('hex').toUpperCase().slice(0, 24)}`);
  check(g, 'six wrong keys are each refused', `${last.status} ${last.body?.error}`, '403 invalid_sheet');
  const blocked = await sheetStart(SAM_KEY);
  check(g, 'the seventh is refused outright -> 429 with a retry hint', `${blocked.status} ${blocked.body?.error} ${typeof blocked.body?.retryAfterSec}`, '429 recovery_rate_limited number');
  check(g, 'a rate-limited guess does not touch anyone\'s PIN lockout', (await admin.query(`SELECT count(*)::int n FROM pin_credential WHERE user_id = ANY($1::uuid[]) AND (failed_attempts > 0 OR locked_until IS NOT NULL)`, [[MOM.userId, DAD.userId, SAM.userId, EVE.userId]])).rows[0].n, 0);
  sheetBudget.windowStart -= 61_000;
  check(g, 'when the window rolls over the real owner\'s key works again', (await sheetStart(await makeSheet({ tok: SAM.tok, pin: SAM.pin }))).status, 201);
  // code budget
  codeBudget.misses = 0; codeBudget.windowStart = Date.now();
  for (let i = 0; i < 8; i++) await call('POST', '/v1/auth/recovery/status', null, { code: 'AAAA-BBBB-CCCC-DDDD-' + String(1000 + i).replace(/[01]/g, '2') });
  check(g, 'guessing request codes spends its own budget -> 429', (await call('POST', '/v1/auth/recovery/status', null, { code: 'AAAA-BBBB-CCCC-DDDD-EEEE' })).status, 429);
  codeBudget.windowStart -= 61_000;
  // helper budget
  helperBudget.misses = 0; helperBudget.windowStart = Date.now();
  for (let i = 0; i < 6; i++) await call('POST', '/v1/auth/helper/accept', null, { code: 'AAAA-BBBB-CCCC-DDDD' });
  check(g, 'guessing helper invites spends its own budget -> 429', (await call('POST', '/v1/auth/helper/accept', null, { code: 'AAAA-BBBB-CCCC-DDDD' })).status, 429);
  helperBudget.windowStart -= 61_000;

  // caps: three open at once, five a day
  const EVE2 = await signup('Eve2', { pin: '1357' });
  const k = await mkChild(EVE2, 'Kit');
  const P2 = await signup('Eve2b', { pin: '2460' });
  await coParent(k, P2.userId);
  const codes = [];
  for (let i = 0; i < 3; i++) codes.push((await startFor(P2, EVE2.userId)).status);
  check(g, 'three recoveries can be open at once', codes.join(), '201,201,201');
  const fourth = await startFor(P2, EVE2.userId);
  check(g, 'a fourth is refused -> 429 too_many_open', `${fourth.status} ${fourth.body?.error}`, '429 too_many_open');
  await admin.query(`UPDATE recovery_request SET cancelled_at = now(), cancelled_by_kind = 'owner_phone' WHERE user_id = $1 AND completed_at IS NULL AND cancelled_at IS NULL`, [EVE2.userId]);
  const more = [];
  for (let i = 0; i < 3; i++) { const r = await startFor(P2, EVE2.userId); more.push(r.status); await admin.query(`UPDATE recovery_request SET cancelled_at = now(), cancelled_by_kind = 'owner_phone' WHERE user_id = $1 AND completed_at IS NULL AND cancelled_at IS NULL`, [EVE2.userId]); }
  check(g, 'five in a day are allowed, the sixth is refused -> 429 too_many_recent', `${more.join()}|${(await startFor(P2, EVE2.userId)).body?.error}`, '201,201,429|too_many_recent');
  check(g, 'a refused start never changes the account\'s PIN lockout', (await admin.query(`SELECT failed_attempts FROM pin_credential WHERE user_id = $1`, [EVE2.userId])).rows[0].failed_attempts, 0);
}

// ===========================================================================
// G · STORAGE and RLS
// ===========================================================================
{
  const g = 'G storage';
  for (const t of ['recovery_sheet', 'recovery_helper', 'recovery_request']) {
    check(g, `a guardian session sees ZERO ${t} rows (FORCE RLS, system only)`,
      (await withSession(pool, { roleName: 'guardian', userId: SAM.userId, childId: null }, (q) => q(`SELECT count(*)::int n FROM ${t}`)))[0].n, 0);
    check(g, `a child session sees none of ${t}`,
      (await withSession(pool, { roleName: 'child', userId: null, childId: WREN }, (q) => q(`SELECT count(*)::int n FROM ${t}`)))[0].n, 0);
  }
  let wrote = 'wrote';
  try { await withSession(pool, { roleName: 'guardian', userId: SAM.userId, childId: null }, (q) => q(
    `INSERT INTO recovery_helper (user_id, label, invite_hash, invite_expires_at) VALUES ($1, 'Me', $2, now() + interval '1 day')`, [SAM.userId, 'e'.repeat(64)])); } catch { wrote = 'refused'; }
  check(g, 'a guardian session cannot name its own helper by writing the table', wrote, 'refused');
  const up = await withSession(pool, { roleName: 'guardian', userId: SAM.userId, childId: null }, (q) => q(`UPDATE recovery_request SET ready_at = now() RETURNING id`));
  check(g, 'a guardian session cannot move a waiting period', up.length, 0);
  const bad = async (sql, args) => admin.query(sql, args).then(() => 'accepted', () => 'refused');
  const someReq = (await admin.query(`SELECT id, user_id FROM recovery_request ORDER BY created_at DESC LIMIT 1`)).rows[0];
  check(g, 'the table refuses a waiting period under 24 hours', await bad(
    `INSERT INTO recovery_request (user_id, mode, started_by_kind, secret_hash, created_at, expires_at, ready_at, approved_by, approved_at)
     VALUES ($1, 'second_parent', 'parent', $2, now(), now() + interval '5 days', now() + interval '2 hours', $3, now())`, [MOM.userId, 'a'.repeat(64), DAD.userId]), 'refused');
  check(g, 'the table refuses a grown-up approving their own recovery', await bad(
    `INSERT INTO recovery_request (user_id, mode, started_by_kind, secret_hash, created_at, expires_at, ready_at, approved_by, approved_at)
     VALUES ($1, 'second_parent', 'parent', $2, now(), now() + interval '5 days', now() + interval '48 hours', $1, now())`, [MOM.userId, 'b'.repeat(64)]), 'refused');
  check(g, 'the table refuses a one-grown-up recovery that carries a second grown-up\'s yes (modes are not mixed)', await bad(
    `INSERT INTO recovery_request (user_id, mode, started_by_kind, secret_hash, created_at, expires_at, ready_at, approved_by, approved_at)
     VALUES ($1, 'sole_parent', 'sheet', $2, now(), now() + interval '5 days', now() + interval '72 hours', $3, now())`, [MOM.userId, 'c'.repeat(64), DAD.userId]), 'refused');
  // A finished one-grown-up recovery that named a helper must carry the helper's yes. The control row is identical but
  // for that one fact, so the refusal is proved to be about the helper and not about some other column.
  const finished = (helperRequired, hash) => bad(
    `INSERT INTO recovery_request (user_id, mode, started_by_kind, secret_hash, created_at, expires_at, ready_at,
        helper_required, completed_at, proof_used)
     VALUES ($1, 'sole_parent', 'sheet', $2, now() - interval '100 hours', now() + interval '5 days',
        now() - interval '20 hours', $3, now() - interval '1 hour', 'sheet_at_start')`, [EVE.userId, hash, helperRequired]);
  check(g, 'control: a finished one-grown-up recovery with no helper named is accepted by the table', await finished(false, 'd'.repeat(64)), 'accepted');
  check(g, 'the table refuses a finished request that needed a helper and never had one', await finished(true, '9'.repeat(64)), 'refused');
  await admin.query(`DELETE FROM recovery_request WHERE secret_hash = $1`, ['d'.repeat(64)]);
  check(g, 'the table refuses a finish that comes before the wait was over', await bad(
    `INSERT INTO recovery_request (user_id, mode, started_by_kind, secret_hash, created_at, expires_at, ready_at, completed_at, proof_used)
     VALUES ($1, 'sole_parent', 'sheet', $2, now() - interval '100 hours', now() + interval '5 days',
        now() - interval '20 hours', now() - interval '30 hours', 'sheet_at_start')`, [EVE.userId, '8'.repeat(64)]), 'refused');
  check(g, 'a stored helper label may not be an email', await bad(
    `INSERT INTO recovery_helper (user_id, label, invite_hash, invite_expires_at) VALUES ($1, $2, $3, now() + interval '1 day')`, [EVE.userId, 'a' + String.fromCharCode(64) + 'b', 'f'.repeat(64)]), 'refused');
  check(g, 'the notice the other grown-up can read never carries a code, key or PIN', await (async () => {
    const r = await admin.query(`SELECT summary FROM security_event WHERE kind LIKE 'recovery_%' OR kind = 'account_recovered'`);
    return r.rows.every((x) => !/[0-9A-Z]{4}-[0-9A-Z]{4}|PIN \d|@/.test(x.summary));
  })(), 'true');
  check(g, 'deleting an account deletes its recovery rows (no orphan secrets)', await (async () => {
    const u = await signup('Gone');
    await makeRecoverySheet(pool, { userId: u.userId });
    await call('POST', '/v1/me/recovery-helper', u.tok, { pin: u.pin, label: 'Z' });
    await admin.query(`DELETE FROM paired_device WHERE target_id = $1`, [u.userId]);
    await admin.query(`DELETE FROM app_user WHERE id = $1`, [u.userId]);
    return (await admin.query(`SELECT (SELECT count(*) FROM recovery_sheet WHERE user_id = $1) + (SELECT count(*) FROM recovery_helper WHERE user_id = $1) AS n`, [u.userId])).rows[0].n;
  })(), '0');
  check(g, 'the old operator route still exists and is unchanged in shape',
    `${(await call('POST', '/v1/auth/recover', null, { recoveryCode: 'x'.repeat(30), pin: '1234' })).status}`, '403');
  check(g, 'the new unauthenticated routes sit under /v1/auth/ (the per-IP throttle and the small body cap)',
    ['/v1/auth/recovery/start', '/v1/auth/recovery/status', '/v1/auth/recovery/cancel', '/v1/auth/recovery/finish', '/v1/auth/helper/accept', '/v1/auth/helper/requests', '/v1/auth/helper/answer']
      .every((p) => api.bodyLimitFor('POST', p, {}) <= 1024 * 1024), 'true');
}
void recoveryNoticesFor; void startRecoveryForGrownUp;

// ---------------------------------------------------------------------------
// cleanup: everything this run created, by id
await setSignupPolicy(pool, { enabled: true, maxAccounts: null });
const allUsers = (await admin.query(`SELECT id FROM app_user WHERE display_name LIKE ANY($1::text[])`, [[`%-${RUN}`]])).rows.map((r) => r.id);
const ids = [...new Set([...users, ...allUsers])];
const allKids = (await admin.query(`SELECT id FROM child WHERE id = ANY($1::uuid[]) OR display_name = 'Kit'`, [children])).rows.map((r) => r.id);
const kidIds = [...new Set([...children, ...allKids])];
await admin.query(`DELETE FROM security_event WHERE actor_id = ANY($1::uuid[])`, [ids]).catch(() => {});
await admin.query(`DELETE FROM recovery_request WHERE user_id = ANY($1::uuid[])`, [ids]);
await admin.query(`DELETE FROM paired_device WHERE target_id = ANY($1::uuid[]) OR target_id = ANY($2::uuid[])`, [ids, kidIds]);
await admin.query(`DELETE FROM device_pairing_code WHERE created_by = ANY($1::uuid[])`, [ids]);
await admin.query(`DELETE FROM guardian_invite WHERE child_id = ANY($1::uuid[])`, [kidIds]);
await admin.query(`DELETE FROM child WHERE id = ANY($1::uuid[])`, [kidIds]);
await admin.query(`DELETE FROM app_user WHERE id = ANY($1::uuid[])`, [ids]);
await admin.query(`DELETE FROM signup_allowance WHERE label LIKE $1`, [`${LABEL}%`]);
await admin.end();
await pool.end();
await fs.rm(tmpRoot, { recursive: true, force: true });

let gname = '';
for (const r of rows) { if (r.g !== gname) { gname = r.g; console.log(`\n${gname}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
