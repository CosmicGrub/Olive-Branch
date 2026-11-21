/**
 * Account recovery without email (db/migrations/0053_account_recovery.sql), end to end against a REAL
 * Postgres through the REAL Api (strict ids ON, as in production). Nothing is seeded by SQL except where a
 * check says so: every account comes from POST /v1/auth/signup.
 *
 *   A. operator   tools/provision-recovery.mjs: finds the account by the sign-up note, refuses an ambiguous note,
 *                 an unknown account, an account with no PIN, an email in a note; one live code per account.
 *   B. recover    code + PIN -> a NEW device and a session; every other guardian device of the account is
 *                 signed out (its session AND its refresh credential); the other grown-up sees a security event.
 *   C. hostile    replay, unknown / expired / revoked / superseded codes (ONE answer), wrong PIN (code survives,
 *                 fifth burns it), PIN lockout, the OTHER family's PIN, a code never touches another family,
 *                 a deactivated account, an account with no PIN, concurrency (exactly one wins).
 *   D. limits     the global miss budget (429), malformed bodies, the unauthenticated route costs nothing for junk.
 *   E. storage    only a digest is stored; no session of any kind can read or write the table.
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
  recoveryTokenDigest, issueRecoveryCode, PIN_MAX_ATTEMPTS } from '../../packages/db/src/pool.mjs';
import { registerRoutes } from '../routes.mjs';
import { MissBudget } from '../rate_limit.mjs';
import { FilesystemStorage } from '../../packages/storage/src/storage.mjs';
import { run as recoveryCli } from '../../tools/provision-recovery.mjs';

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

const SECRET = Buffer.from('r'.repeat(32), 'utf8');
const tmpRoot = await fs.mkdtemp(path.join(os.tmpdir(), 'olive-recovery-test-'));
const api = new Api(SECRET, dbPort(pool), () => Date.now(), { strictIds: true });
const budget = new MissBudget({ limit: 6 });
registerRoutes(api, pool, new FilesystemStorage(tmpRoot), {
  callEnv: { CALL_PROVIDER: 'jitsi', NODE_ENV: 'test', JITSI_APP_ID: 'olive-calls',
    JITSI_APP_SECRET: randomBytes(32).toString('hex'), JITSI_SERVER_URL: 'https://calls.example.test:8443' },
  recoveryMissBudget: budget,
});

const hdr = (tok) => (tok ? { authorization: `Bearer ${tok}` } : {});
const call = (method, p, tok, body) => api.handle(
  method, p, hdr(tok), body === undefined ? '' : JSON.stringify(body));
const RUN = randomUUID().slice(0, 8);
const LABEL = `rectest-${RUN}`;
const users = [];
const children = [];

const signup = async (label, over = {}) => {
  const token = (await issueSignupAllowance(pool, { label })).token;
  const r = await call('POST', '/v1/auth/signup', null, {
    allowanceToken: token, displayName: 'Dad', homeTz: 'America/Chicago', pin: '4821',
    deviceLabel: 'Old phone', ...over });
  if (r.status !== 201) throw new Error(`signup failed: ${r.status} ${JSON.stringify(r.body)}`);
  users.push(r.body.userId);
  return { userId: r.body.userId, tok: r.body.token, deviceId: r.body.deviceId, cred: r.body.deviceCredential };
};
const recover = (code, pin, over = {}) => call('POST', '/v1/auth/recover', null, {
  recoveryCode: code, pin, deviceLabel: 'New phone', ...over });
const issue = async (userId, over = {}) => {
  const r = await issueRecoveryCode(pool, { userId, ...over });
  if (!r.ok) throw new Error(`issue failed: ${r.reason}`);
  return r.token;
};
const liveCodes = async (userId) => (await admin.query(
  `SELECT count(*)::int n FROM account_recovery_code
    WHERE user_id = $1 AND redeemed_at IS NULL AND revoked_at IS NULL`, [userId])).rows[0].n;
const activeDevices = async (userId) => (await admin.query(
  `SELECT count(*)::int n FROM paired_device WHERE target_id = $1 AND role = 'guardian' AND revoked_at IS NULL`,
  [userId])).rows[0].n;
const unlockPin = (userId) => admin.query(
  `UPDATE pin_credential SET failed_attempts = 0, locked_until = NULL WHERE user_id = $1`, [userId]);

await setSignupPolicy(pool, { enabled: true, maxAccounts: null });

// Two real families (A and B) and a second grown-up for family A.
const A = await signup(LABEL, { displayName: `Mom-${RUN}` });
const B = await signup(`${LABEL}-b`, { displayName: `Other-${RUN}`, pin: '7315' });
const mkChild = async (g, name, pin) => {
  const r = await call('POST', '/v1/children', g.tok, { displayName: name, birthDate: '2018-03-04', homeTz: 'America/Chicago', pin });
  if (r.status !== 201) throw new Error('child create failed');
  children.push(r.body.child.id);
  return r.body.child.id;
};
const CHILD_A = await mkChild(A, 'Ivy', '4821');
const CHILD_B = await mkChild(B, 'Otis', '7315');
// A's co-parent: a second account that holds a live edge to the same child (so there is someone to be told)
const A2 = await signup(`${LABEL}-a2`, { displayName: `Dad-${RUN}`, pin: '2468' });
await admin.query(
  `INSERT INTO guardianship (child_id, user_id, role, scope, valid)
   VALUES ($1, $2, 'guardian', '{}', tstzrange(now() - interval '1 minute', NULL))`, [CHILD_A, A2.userId]);
check('setup', 'two families and a co-parent exist, each with one signed-in device',
  `${await activeDevices(A.userId)}${await activeDevices(B.userId)}${await activeDevices(A2.userId)}`, '111');

// ===========================================================================
// A · OPERATOR
// ===========================================================================
{
  const out = []; const say = (s) => out.push(String(s));
  check('A cli', 'no arguments -> usage, exit 2', await recoveryCli([], pool, say), 2);
  check('A cli', 'issue with neither --label nor --user -> exit 2', await recoveryCli(['issue'], pool, say), 2);
  check('A cli', 'issue with BOTH -> exit 2', await recoveryCli(['issue', '--label', LABEL, '--user', A.userId], pool, say), 2);
  check('A cli', 'issue with a junk --user -> exit 2 (never reaches SQL)', await recoveryCli(['issue', '--user', "x'; drop table app_user;--"], pool, say), 2);
  check('A cli', 'a label nobody redeemed -> exit 1', await recoveryCli(['issue', '--label', `nobody-${RUN}`], pool, say), 1);
  check('A cli', 'an unknown account id -> exit 1', await recoveryCli(['issue', '--user', randomUUID()], pool, say), 1);
  check('A cli', 'an email in the note is refused (no PII in the table)',
    await recoveryCli(['issue', '--user', A.userId, '--note', 'mom' + String.fromCharCode(64) + 'example.test'], pool, say), 2);
  check('A cli', 'an absurd life is refused', await recoveryCli(['issue', '--user', A.userId, '--hours', '9999'], pool, say), 2);
  check('A cli', 'none of the refused attempts left a live code', await liveCodes(A.userId), 0);

  // ambiguity: two accounts redeemed allowances with the same note
  const dup1 = await signup(`${LABEL}-dup`, { displayName: `Dup1-${RUN}` });
  const dup2 = await signup(`${LABEL}-dup`, { displayName: `Dup2-${RUN}` });
  out.length = 0;
  check('A cli', 'an ambiguous note is refused and the accounts are listed (exit 1)', await recoveryCli(['issue', '--label', `${LABEL}-dup`], pool, say), 1);
  check('A cli', '...it printed both ids and issued nothing',
    out.join('|').includes(dup1.userId) && out.join('|').includes(dup2.userId) && (await liveCodes(dup1.userId)) + (await liveCodes(dup2.userId)) === 0, 'true');

  out.length = 0;
  check('A cli', 'issue by the sign-up note returns 0', await recoveryCli(['issue', '--label', LABEL], pool, say), 0);
  const printed = out.find((l) => /^[A-Za-z0-9_-]{40,}$/.test(l));
  check('A cli', 'it prints one long random code, once', Boolean(printed), 'true');
  check('A cli', 'the stored row is the digest of exactly that code',
    (await admin.query(`SELECT 1 FROM account_recovery_code WHERE token_hash = $1 AND user_id = $2`, [recoveryTokenDigest(printed), A.userId])).rowCount, 1);
  check('A cli', 'a default life of 72 hours',
    (await admin.query(`SELECT round(extract(epoch FROM expires_at - created_at) / 3600)::int h FROM account_recovery_code WHERE token_hash = $1`, [recoveryTokenDigest(printed)])).rows[0].h, 72);
  out.length = 0;
  check('A cli', 'issuing again supersedes the older code (one live code per account)', await recoveryCli(['issue', '--user', A.userId], pool, say), 0);
  check('A cli', '...and says so', out.join('|').includes('older code'), 'true');
  check('A cli', '...exactly one live code remains', await liveCodes(A.userId), 1);
  check('A cli', 'the superseded code no longer works (same answer as an unknown one)',
    `${(await recover(printed, '4821')).status} ${(await recover(printed, '4821')).body?.error}`, '403 invalid_recovery');
  check('A cli', 'cancel revokes the live code', await recoveryCli(['cancel', '--user', A.userId], pool, say), 0);
  check('A cli', '...none left', await liveCodes(A.userId), 0);

  // an account with no PIN cannot get a code
  const noPin = await signup(`${LABEL}-nopin`, { displayName: `NoPin-${RUN}` });
  await admin.query(`DELETE FROM pin_credential WHERE user_id = $1`, [noPin.userId]);
  check('A cli', 'an account with no PIN is refused a code (a code alone would be the only protection)',
    await recoveryCli(['issue', '--user', noPin.userId], pool, say), 1);
  // ...and if a code somehow exists, recover still refuses
  const sneaky = 'N'.repeat(43);
  await admin.query(
    `INSERT INTO account_recovery_code (user_id, token_hash, expires_at) VALUES ($1, $2, now() + interval '1 hour')`,
    [noPin.userId, recoveryTokenDigest(sneaky)]);
  check('A cli', 'recover for a no-PIN account is refused even with a live code -> 403 pin_not_set',
    `${(await recover(sneaky, '1234')).status} ${(await recover(sneaky, '1234')).body?.error}`, '403 pin_not_set');
  check('A cli', '...and no device was enrolled', await activeDevices(noPin.userId), 1);
}

// ===========================================================================
// D · INPUT SHAPE and the global budget (before anything succeeds, so the budget is fresh)
// ===========================================================================
{
  const good = await issue(A.userId);
  check('D input', 'no body -> 400 recovery_code_required', (await call('POST', '/v1/auth/recover', null, {})).body?.error, 'recovery_code_required');
  check('D input', 'a short code -> 400 (never reaches the DB)', (await recover('abc', '4821')).status, 400);
  check('D input', 'an enormous code -> 400', (await recover('x'.repeat(500), '4821')).status, 400);
  check('D input', 'a numeric code value -> 400', (await call('POST', '/v1/auth/recover', null, { recoveryCode: 123456789012345678901234, pin: '4821' })).status, 400);
  check('D input', 'no pin -> 400 pin_required', (await recover(good, undefined)).body?.error, 'pin_required');
  check('D input', 'a non-numeric pin -> 400', (await recover(good, 'abcd')).status, 400);
  check('D input', 'a 3-digit pin -> 400', (await recover(good, '123')).status, 400);
  check('D input', 'a 9-digit pin -> 400', (await recover(good, '123456789')).status, 400);
  check('D input', 'a pin as an object -> 400', (await call('POST', '/v1/auth/recover', null, { recoveryCode: good, pin: { $ne: 1 } })).status, 400);
  check('D input', 'no session needed (the route is the way in)', (await recover(good, '9999')).status !== 401, 'true');
  check('D input', 'every malformed attempt left the live code untouched and unspent',
    (await admin.query(`SELECT failed_attempts, redeemed_at, revoked_at FROM account_recovery_code WHERE token_hash = $1`, [recoveryTokenDigest(good)])).rows.map((r) => `${r.failed_attempts}|${r.redeemed_at}|${r.revoked_at}`).join(), '1|null|null');
  await unlockPin(A.userId);
  await admin.query(`UPDATE account_recovery_code SET failed_attempts = 0 WHERE token_hash = $1`, [recoveryTokenDigest(good)]);

  // the per-IP throttle every /v1/auth/ route gets lives in index.mjs; this route must sit under it, with the small body cap
  const indexSrc = await fs.readFile(new URL('../index.mjs', import.meta.url), 'utf8');
  check('D limits', 'index.mjs throttles every /v1/auth/ path per client address, so /v1/auth/recover is covered', indexSrc.includes("pathname.startsWith('/v1/auth/')"), 'true');
  check('D limits', 'an unauthenticated recover body gets the small cap, not the 40 MiB one', api.bodyLimitFor('POST', '/v1/auth/recover', {}) <= 1024 * 1024, 'true');

  // the global miss budget (limit 6 in this suite): guesses that match NO live code are what spend it
  budget.misses = 0;
  let last;
  for (let i = 0; i < 6; i++) last = await recover(randomBytes(32).toString('base64url'), '4821');
  check('D budget', 'six unknown codes are each refused as invalid_recovery', `${last.status} ${last.body?.error}`, '403 invalid_recovery');
  const blocked = await recover(randomBytes(32).toString('base64url'), '4821');
  check('D budget', 'the seventh guess is refused outright -> 429 recovery_rate_limited', `${blocked.status} ${blocked.body?.error}`, '429 recovery_rate_limited');
  check('D budget', '...with a retry hint', typeof blocked.body?.retryAfterSec, 'number');
  const realWhileBlocked = await recover(good, '4821');
  check('D budget', 'while blocked even the REAL code waits (the budget is global, like pairing\'s)', realWhileBlocked.status, 429);
  check('D budget', '...and the real code was not spent', await liveCodes(A.userId), 1);
  budget.windowStart -= 61_000; // the window rolls over
  check('D budget', 'after the window rolls over the real code works again', (await recover(good, '4821')).status, 201);
  // that recovery replaced A's device: refresh the handle
  const rows2 = await admin.query(`SELECT id FROM paired_device WHERE target_id = $1 AND role = 'guardian' AND revoked_at IS NULL`, [A.userId]);
  A.deviceId = rows2.rows[0].id;
}

// ===========================================================================
// B · RECOVER (the happy path, in detail)
// ===========================================================================
let A_NEW;
{
  // A's current state: sign in again as a "second device" to prove ALL old devices go.
  // (re-use the original signup credentials: the first recovery above already revoked them)
  const old = await signup(`${LABEL}-b-old`, { displayName: `Lost-${RUN}`, pin: '3579' });
  const oldChild = await mkChild(old, 'Wren', '3579');
  const second = await call('POST', '/v1/me/device-pairing-codes', old.tok, { pin: '3579' });
  const pairedSecond = await call('POST', '/v1/device-pairing/redeem', null, { code: second.body.numericCode, role: 'guardian' });
  check('B recover', 'setup: the account has TWO signed-in guardian phones', await activeDevices(old.userId), 2);
  const cousin = await signup(`${LABEL}-cousin`, { displayName: `Cousin-${RUN}`, pin: '2580' });
  await admin.query(
    `INSERT INTO guardianship (child_id, user_id, role, scope, valid)
     VALUES ($1, $2, 'guardian', '{}', tstzrange(now() - interval '1 minute', NULL))`, [oldChild, cousin.userId]);
  const beforeEvents = (await admin.query(`SELECT count(*)::int n FROM security_event WHERE child_id = $1 AND kind = 'account_recovered'`, [oldChild])).rows[0].n;

  const code = await issue(old.userId, { label: 'lost both phones' });
  const r = await recover(code, '3579', { deviceLabel: 'Replacement' });
  check('B recover', 'code + PIN -> 201', r.status, 201);
  check('B recover', 'returns a session, userId, a NEW deviceId and a deviceCredential',
    ['token', 'userId', 'deviceId', 'deviceCredential'].every((k) => typeof r.body?.[k] === 'string' && r.body[k].length > 8), 'true');
  check('B recover', 'it is the SAME account (not a new one)', r.body.userId, old.userId);
  check('B recover', 'it says how many other phones were signed out', r.body.devicesSignedOut, 2);
  A_NEW = { userId: r.body.userId, tok: r.body.token, deviceId: r.body.deviceId, cred: r.body.deviceCredential };
  check('B recover', 'the new session works (GET /v1/me)', (await call('GET', '/v1/me', A_NEW.tok)).status, 200);
  check('B recover', '...and it still sees the account\'s child', (await call('GET', '/v1/me/children', A_NEW.tok)).body.children.map((c) => c.id).join(), oldChild);
  check('B recover', 'the new device\'s credential trades for a fresh session',
    (await call('POST', '/v1/auth/session/refresh', null, { deviceId: A_NEW.deviceId, deviceCredential: A_NEW.cred })).status, 200);
  check('B recover', 'only the digest of the new credential is stored',
    (await admin.query(`SELECT credential_hash FROM paired_device WHERE id = $1`, [A_NEW.deviceId])).rows[0].credential_hash, createHash('sha256').update(A_NEW.cred).digest('hex'));
  check('B recover', 'exactly one guardian device is now active for the account', await activeDevices(old.userId), 1);

  // the lost phones are cut off at once
  const oldSession = await call('GET', '/v1/me', old.tok);
  check('B recover', 'the lost phone\'s existing session is cut off -> 401 device_revoked', `${oldSession.status} ${oldSession.body?.error}`, '401 device_revoked');
  const oldRefresh = await call('POST', '/v1/auth/session/refresh', null, { deviceId: old.deviceId, deviceCredential: old.cred });
  check('B recover', 'the lost phone\'s credential can no longer sign in -> 401 device_revoked', `${oldRefresh.status} ${oldRefresh.body?.error}`, '401 device_revoked');
  const secondRefresh = await call('POST', '/v1/auth/session/refresh', null, { deviceId: pairedSecond.body.deviceId, deviceCredential: pairedSecond.body.deviceCredential });
  check('B recover', 'the account\'s OTHER phone is signed out too', `${secondRefresh.status} ${secondRefresh.body?.error}`, '401 device_revoked');

  // the other grown-up can see it
  const feed = await call('GET', `/v1/children/${oldChild}/security-events`, cousin.tok);
  check('B recover', 'the co-parent can read the event feed', feed.status, 200);
  const ev = (feed.body?.events ?? feed.body?.entries ?? []).filter((e) => e.kind === 'account_recovered');
  check('B recover', 'it shows one "account recovered" event (content-free wording)', `${ev.length}|${ev[0]?.summary?.includes('recovered')}`, '1|true');
  check('B recover', '...and the event carries no code, PIN, device label or email',
    JSON.stringify(ev).match(/Replacement|lost both|3579|@/) === null, 'true');
  check('B recover', 'one event row per child, written once',
    (await admin.query(`SELECT count(*)::int n FROM security_event WHERE child_id = $1 AND kind = 'account_recovered'`, [oldChild])).rows[0].n - beforeEvents, 1);

  // replay of the same, now-spent code
  const replay = await recover(code, '3579');
  check('B recover', 'replaying the spent code -> 403 invalid_recovery (same as an unknown one)', `${replay.status} ${replay.body?.error}`, '403 invalid_recovery');
  check('B recover', '...and it did not enrol another device or sign the new one out', await activeDevices(old.userId), 1);
  check('B recover', 'the new session still works after the replay', (await call('GET', '/v1/me', A_NEW.tok)).status, 200);
  const spent = await admin.query(`SELECT redeemed_at IS NOT NULL AS used, redeemed_device_id FROM account_recovery_code WHERE token_hash = $1`, [recoveryTokenDigest(code)]);
  check('B recover', 'the code row records that it was spent, and by which device', `${spent.rows[0].used}|${spent.rows[0].redeemed_device_id === A_NEW.deviceId}`, 'true|true');
  check('B recover', 'the PIN is unchanged and still works (a recovery does not reset it)',
    (await call('POST', '/v1/me/verify-controls-pin', A_NEW.tok, { pin: '3579' })).status, 200);
}

// ===========================================================================
// C · HOSTILE
// ===========================================================================
budget.windowStart -= 61_000; budget.misses = 0;
{
  const fresh = async () => signup(`${LABEL}-c${Math.random().toString(36).slice(2, 6)}`, { displayName: `C-${RUN}`, pin: '1357' });

  // expired
  {
    const u = await fresh();
    const code = await issue(u.userId);
    await admin.query(`UPDATE account_recovery_code SET created_at = now() - interval '5 days', expires_at = now() - interval '1 minute' WHERE token_hash = $1`, [recoveryTokenDigest(code)]);
    const r = await recover(code, '1357');
    check('C expiry', 'an expired code -> 403 invalid_recovery (same answer as unknown)', `${r.status} ${r.body?.error}`, '403 invalid_recovery');
    check('C expiry', '...and nothing changed on the account', await activeDevices(u.userId), 1);
    check('C expiry', 'the table refuses a code that lives longer than 14 days',
      await admin.query(`INSERT INTO account_recovery_code (user_id, token_hash, expires_at) VALUES ($1, $2, now() + interval '30 days')`, [u.userId, 'e'.repeat(64)]).then(() => 'accepted', () => 'refused'), 'refused');
  }
  // revoked by the operator
  {
    const u = await fresh();
    const code = await issue(u.userId);
    await recoveryCli(['cancel', '--user', u.userId], pool, () => {});
    const r = await recover(code, '1357');
    check('C revoked', 'a cancelled code -> 403 invalid_recovery', `${r.status} ${r.body?.error}`, '403 invalid_recovery');
  }
  // wrong PIN: code survives; correct PIN afterwards works; counters
  {
    const u = await fresh();
    const code = await issue(u.userId);
    const w1 = await recover(code, '0000');
    check('C pin', 'a wrong PIN on a live code -> 403 pin_incorrect', `${w1.status} ${w1.body?.error}`, '403 pin_incorrect');
    check('C pin', '...no device was enrolled, nothing signed out', `${await activeDevices(u.userId)}|${(await call('GET', '/v1/me', u.tok)).status}`, '1|200');
    check('C pin', '...the code survives with one strike', (await admin.query(`SELECT failed_attempts, revoked_at FROM account_recovery_code WHERE token_hash = $1`, [recoveryTokenDigest(code)])).rows.map((r) => `${r.failed_attempts}|${r.revoked_at}`).join(), '1|null');
    check('C pin', '...and the account\'s own PIN counter moved too (one counter for every PIN check)',
      (await admin.query(`SELECT failed_attempts FROM pin_credential WHERE user_id = $1`, [u.userId])).rows[0].failed_attempts, 1);
    const ok = await recover(code, '1357');
    check('C pin', 'the right PIN afterwards still recovers the account', ok.status, 201);
    check('C pin', '...and a success clears the PIN strike counter', (await admin.query(`SELECT failed_attempts FROM pin_credential WHERE user_id = $1`, [u.userId])).rows[0].failed_attempts, 0);
  }
  // five wrong PINs burn the code AND lock the account's PIN
  {
    const u = await fresh();
    const code = await issue(u.userId);
    const answers = [];
    for (let i = 0; i < PIN_MAX_ATTEMPTS; i++) answers.push((await recover(code, '0000')).body?.error);
    check('C pin', 'four wrong PINs are pin_incorrect, the fifth reports recovery_locked',
      answers.join(), ['pin_incorrect', 'pin_incorrect', 'pin_incorrect', 'pin_incorrect', 'recovery_locked'].join());
    const afterBurn = await recover(code, '1357');
    check('C pin', 'with the code burned even the RIGHT PIN fails -> 403 invalid_recovery', `${afterBurn.status} ${afterBurn.body?.error}`, '403 invalid_recovery');
    check('C pin', '...nothing was enrolled', await activeDevices(u.userId), 1);
    check('C pin', 'the account\'s PIN is now locked (the lockout is shared)',
      (await call('POST', '/v1/me/verify-controls-pin', u.tok, { pin: '1357' })).body?.error, 'pin_locked');
    const code2 = await issue(u.userId);
    const locked = await recover(code2, '1357');
    check('C pin', 'a NEW code cannot be used while the PIN is locked -> 403 pin_locked', `${locked.status} ${locked.body?.error}`, '403 pin_locked');
    check('C pin', '...and a locked attempt does not burn the new code', await liveCodes(u.userId), 1);
    await unlockPin(u.userId);
    check('C pin', 'once the lockout ends the new code works', (await recover(code2, '1357')).status, 201);
  }
  // the OTHER family's PIN never opens this account, and a code never touches another family
  {
    const victim = await fresh();
    const attacker = await signup(`${LABEL}-att`, { displayName: `Att-${RUN}`, pin: '9753' });
    const attackerChild = await mkChild(attacker, 'Mina', '9753');
    const vcode = await issue(victim.userId);
    const wrongFamily = await recover(vcode, '9753');
    check('C family', 'victim\'s code + the ATTACKER\'S own PIN -> 403 pin_incorrect', `${wrongFamily.status} ${wrongFamily.body?.error}`, '403 pin_incorrect');
    check('C family', '...the attacker\'s PIN counter and devices are untouched',
      `${(await admin.query(`SELECT failed_attempts FROM pin_credential WHERE user_id = $1`, [attacker.userId])).rows[0].failed_attempts}|${await activeDevices(attacker.userId)}`, '0|1');
    check('C family', '...the wrong guess counted against the VICTIM\'s code', (await admin.query(`SELECT failed_attempts FROM account_recovery_code WHERE token_hash = $1`, [recoveryTokenDigest(vcode)])).rows[0].failed_attempts, 1);
    // the attacker's own recovery never reaches the victim
    const acode = await issue(attacker.userId);
    const eventsBefore = (await admin.query(`SELECT count(*)::int n FROM security_event WHERE kind = 'account_recovered' AND child_id = ANY($1::uuid[])`, [[CHILD_A, CHILD_B]])).rows[0].n;
    const mine = await recover(acode, '9753');
    check('C family', 'the attacker recovering their OWN account -> 201', mine.status, 201);
    check('C family', '...signs out only their own devices: the victim still has exactly their device', await activeDevices(victim.userId), 1);
    check('C family', '...the victim\'s session still works', (await call('GET', '/v1/me', victim.tok)).status, 200);
    check('C family', '...and the new session is the attacker\'s account, not the victim\'s', mine.body.userId, attacker.userId);
    check('C family', 'the attacker\'s new session cannot read the victim\'s child',
      (await call('GET', `/v1/children/${CHILD_A}/now`, mine.body.token)).status, 403);
    check('C family', 'no security event leaked onto another family\'s child',
      (await admin.query(`SELECT count(*)::int n FROM security_event WHERE kind = 'account_recovered' AND child_id = ANY($1::uuid[])`, [[CHILD_A, CHILD_B]])).rows[0].n, eventsBefore);
    check('C family', 'a body cannot name another account: extra fields are ignored',
      (await recover(vcode, '9753', { userId: victim.userId, targetId: victim.userId })).body?.error, 'pin_incorrect');
  }
  // deactivated account
  {
    const u = await fresh();
    const code = await issue(u.userId);
    await call('POST', '/v1/me/delete', u.tok, {});
    const r = await recover(code, '1357');
    check('C gone', 'a deactivated account\'s code -> 403 invalid_recovery', `${r.status} ${r.body?.error}`, '403 invalid_recovery');
    check('C gone', '...and no device was enrolled for it', (await admin.query(`SELECT count(*)::int n FROM paired_device WHERE target_id = $1 AND revoked_at IS NULL`, [u.userId])).rows[0].n, 0);
  }
  // concurrency: exactly one winner
  {
    const u = await fresh();
    const code = await issue(u.userId);
    const results = await Promise.all(Array.from({ length: 6 }, () => recover(code, '1357')));
    const won = results.filter((r) => r.status === 201).length;
    check('C race', 'six simultaneous redemptions of one code: exactly ONE wins', won, 1);
    check('C race', '...the rest are invalid_recovery', results.filter((r) => r.status !== 201).every((r) => r.body?.error === 'invalid_recovery'), 'true');
    check('C race', '...exactly one device is active afterwards', await activeDevices(u.userId), 1);
    const winner = results.find((r) => r.status === 201);
    check('C race', '...and it is the winner\'s', (await call('GET', '/v1/me', winner.body.token)).status, 200);
  }
  // the code is not a session and not a credential anywhere else
  budget.misses = 0;
  {
    const u = await fresh();
    const code = await issue(u.userId);
    check('C scope', 'a recovery code is not a bearer session token', (await call('GET', '/v1/me', code)).status, 401);
    check('C scope', 'a recovery code is not a device credential',
      (await call('POST', '/v1/auth/session/refresh', null, { deviceId: u.deviceId, deviceCredential: code })).status, 401);
    check('C scope', 'a recovery code is not a sign-up allowance',
      (await call('POST', '/v1/auth/signup', null, { allowanceToken: code, displayName: 'X', homeTz: 'UTC', pin: '1234' })).body?.error, 'invalid_allowance');
    check('C scope', 'a sign-up allowance is not a recovery code',
      (await recover((await issueSignupAllowance(pool, { label: LABEL })).token, '1357')).body?.error, 'invalid_recovery');
    check('C scope', 'a device pairing code is not a recovery code',
      (await recover('123456123456123456123456', '1357')).body?.error, 'invalid_recovery');
  }
}

// ===========================================================================
// E · STORAGE and RLS
// ===========================================================================
{
  const u = await signup(`${LABEL}-e`, { displayName: `E-${RUN}`, pin: '1122' });
  const code = await issue(u.userId);
  const plain = await admin.query(`SELECT count(*)::int n FROM account_recovery_code WHERE token_hash = $1 OR label = $1`, [code]);
  check('E storage', 'the plaintext code is not stored anywhere in the table', plain.rows[0].n, 0);
  check('E storage', 'a guardian session sees ZERO recovery rows (FORCE RLS, system only)',
    (await withSession(pool, { roleName: 'guardian', userId: u.userId, childId: null }, (q) => q(`SELECT count(*)::int n FROM account_recovery_code`)))[0].n, 0);
  let wrote = 'wrote';
  try {
    await withSession(pool, { roleName: 'guardian', userId: u.userId, childId: null },
      (q) => q(`INSERT INTO account_recovery_code (user_id, token_hash, expires_at) VALUES ($1, $2, now() + interval '1 hour')`, [u.userId, 'c'.repeat(64)]));
  } catch { wrote = 'refused'; }
  check('E storage', 'a guardian session cannot mint itself a recovery code', wrote, 'refused');
  const upd = await withSession(pool, { roleName: 'guardian', userId: u.userId, childId: null },
    (q) => q(`UPDATE account_recovery_code SET expires_at = now() + interval '10 days' WHERE user_id = $1 RETURNING id`, [u.userId]));
  check('E storage', 'a guardian session cannot extend one either', upd.length, 0);
  check('E storage', 'a child session sees nothing',
    (await withSession(pool, { roleName: 'child', userId: null, childId: CHILD_A }, (q) => q(`SELECT count(*)::int n FROM account_recovery_code`)))[0].n, 0);
  check('E storage', 'two live codes for one account are refused by the table itself',
    await admin.query(`INSERT INTO account_recovery_code (user_id, token_hash, expires_at) VALUES ($1, $2, now() + interval '1 hour')`, [u.userId, 'd'.repeat(64)]).then(() => 'accepted', () => 'refused'), 'refused');
  check('E storage', 'deleting the account deletes its codes (no orphan secrets)',
    await (async () => { await admin.query(`DELETE FROM paired_device WHERE target_id = $1`, [u.userId]); await admin.query(`DELETE FROM app_user WHERE id = $1`, [u.userId]); return (await admin.query(`SELECT count(*)::int n FROM account_recovery_code WHERE user_id = $1`, [u.userId])).rows[0].n; })(), 0);
}

// ---------------------------------------------------------------------------
// cleanup: everything this run created, by id
await setSignupPolicy(pool, { enabled: true, maxAccounts: null });
const allUsers = (await admin.query(`SELECT id FROM app_user WHERE display_name LIKE ANY($1::text[])`, [[`%-${RUN}`]])).rows.map((r) => r.id);
const ids = [...new Set([...users, ...allUsers])];
await admin.query(`DELETE FROM security_event WHERE actor_id = ANY($1::uuid[])`, [ids]).catch(() => {});
await admin.query(`DELETE FROM account_recovery_code WHERE user_id = ANY($1::uuid[])`, [ids]);
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
