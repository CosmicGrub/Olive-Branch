/**
 * Identity lane (db/migrations/0050_identity_signup.sql): the core live chain,
 * end to end, against a REAL Postgres through the REAL Api (strict ids ON, as in
 * production), with NO SQL-seeded family. Everything below is created by the
 * routes under test:
 *
 *   A. sign-up   operator allowance -> account + first PIN + enrolled device;
 *                replay, expiry, unknown token, concurrency, kill switch, cap,
 *                the device credential refreshing a session, RLS on the tables.
 *   B. children  POST /v1/children (PIN step-up), GET /v1/me/children, the edge
 *                it creates, and cross-family isolation between two real families.
 *   C. invites   claim -> inviter confirm creates the edge (and only confirm
 *                does); decline, revoke, expiry, non-inviter, closed inviter,
 *                email_already_registered -> claim path.
 *   D. deactivation  a deactivated grown-up's enrolled device dies at once.
 *   E. reach     a sign-up-created child: pair her device, queue a message that
 *                materializes (the default bedtime day part), and the call-session
 *                id surviving the strict-ids guard. The delivery WORKER is the
 *                delivery lane's (PR #220), not tested here.
 *   F. operator CLI  tools/provision-signup.mjs.
 *
 * Needs a NOSUPERUSER NOBYPASSRLS DATABASE_URL (app_owner or app_runtime) and an
 * ADMIN_DATABASE_URL for cleanup. Prints "N passed, M failed" for verify.sh.
 */
import pg from 'pg';
import os from 'node:os';
import path from 'node:path';
import fs from 'node:fs/promises';
import { randomUUID, randomBytes, createHash } from 'node:crypto';
import { DateTime } from 'luxon';
import { Api } from '../../packages/api/src/api.mjs';
import { createPool, dbPort, withSession, issueSignupAllowance, setSignupPolicy,
  signupPolicyFor, signupAllowanceDigest } from '../../packages/db/src/pool.mjs';
import { registerRoutes } from '../routes.mjs';
import { FilesystemStorage } from '../../packages/storage/src/storage.mjs';
import { runRematerializeSweep } from '../../tools/scheduler.mjs';
import { run as provisionCli } from '../../tools/provision-signup.mjs';

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

const SECRET = Buffer.from('i'.repeat(32), 'utf8');
const JITSI_ENV = { CALL_PROVIDER: 'jitsi', NODE_ENV: 'test', JITSI_APP_ID: 'olive-calls',
  JITSI_APP_SECRET: randomBytes(32).toString('hex'),   // throwaway, generated per run
  JITSI_SERVER_URL: 'https://calls.example.test:8443' };
const tmpRoot = await fs.mkdtemp(path.join(os.tmpdir(), 'olive-identity-test-'));
// strictIds ON: exactly how server/index.mjs boots the real server.
const api = new Api(SECRET, dbPort(pool), () => Date.now(), { strictIds: true });
registerRoutes(api, pool, new FilesystemStorage(tmpRoot), { callEnv: JITSI_ENV });

const hdr = (tok) => (tok ? { authorization: `Bearer ${tok}` } : {});
const call = (method, p, tok, body) => api.handle(
  method, p, hdr(tok), body === undefined ? '' : JSON.stringify(body));
const RUN = randomUUID().slice(0, 8);
const emailFor = (who) => `${who}-${RUN}@example.test`;
const LABEL = `idtest-${RUN}`;

const users = [];     // every app_user the routes created
const children = [];  // every child the routes created
const track = (u) => { users.push(u); return u; };

const newAllowance = async (opts = {}) => (await issueSignupAllowance(pool, { label: LABEL, ...opts })).token;
const signup = (token, over = {}) => call('POST', '/v1/auth/signup', null, {
  allowanceToken: token, displayName: 'Dad', homeTz: 'America/Chicago', pin: '4821',
  deviceLabel: 'Test phone', ...over });

// Restore global policy no matter what, so a failed run cannot leave sign-up off.
const restorePolicy = () => setSignupPolicy(pool, { enabled: true, maxAccounts: null });
await restorePolicy();

// ===========================================================================
// A · SIGN-UP
// ===========================================================================
let A, B;   // { userId, tok, deviceId, cred }
{
  // validation (all before any DB write)
  const tok0 = await newAllowance();
  check('A signup', 'no allowance token -> 400', (await signup('')).status, 400);
  check('A signup', 'a too-short token -> 400 (never reaches the DB)', (await signup('abc')).status, 400);
  check('A signup', 'blank name -> 400', (await signup(tok0, { displayName: '  ' })).status, 400);
  check('A signup', 'overlong name -> 400', (await signup(tok0, { displayName: 'x'.repeat(61) })).status, 400);
  check('A signup', 'a made-up time zone -> 400', (await signup(tok0, { homeTz: 'Mars/Olympus' })).status, 400);
  check('A signup', 'missing pin -> 400 pin_required', (await signup(tok0, { pin: undefined })).body?.error, 'pin_required');
  check('A signup', 'a non-numeric pin -> 400 invalid_pin_format', (await signup(tok0, { pin: 'abcd' })).body?.error, 'invalid_pin_format');
  check('A signup', 'a 3-digit pin -> 400', (await signup(tok0, { pin: '123' })).status, 400);
  const unredeemed = await admin.query(`SELECT count(*)::int n FROM signup_allowance WHERE token_hash = $1 AND redeemed_at IS NULL`, [signupAllowanceDigest(tok0)]);
  check('A signup', 'every rejected attempt left the allowance unredeemed', unredeemed.rows[0].n, 1);

  const bogus = await signup('B'.repeat(43));
  check('A signup', 'an unknown token -> 403 invalid_allowance', `${bogus.status} ${bogus.body?.error}`, '403 invalid_allowance');

  // The route judges the allowance BEFORE it hashes the PIN (scrypt blocks the
  // one event loop and this route is unauthenticated). A junk token with a
  // PIN that hashPin would refuse therefore gets the allowance answer, not
  // invalid_pin_format: the PIN was never looked at. A live token still gets
  // the PIN error (checked above with tok0).
  const junkBadPin = await signup('J'.repeat(43), { pin: 'abcd' });
  check('A signup', 'a junk token is refused before the PIN is even hashed (403 invalid_allowance, not 400 invalid_pin_format)',
    `${junkBadPin.status} ${junkBadPin.body?.error}`, '403 invalid_allowance');

  // success
  const ok = await signup(tok0);
  check('A signup', 'a valid allowance signs a grown-up up -> 201', ok.status, 201);
  check('A signup', 'returns a session token, userId, deviceId and a deviceCredential',
    ['token', 'userId', 'deviceId', 'deviceCredential'].every((k) => typeof ok.body?.[k] === 'string' && ok.body[k].length > 8), 'true');
  A = { userId: track(ok.body.userId), tok: ok.body.token, deviceId: ok.body.deviceId, cred: ok.body.deviceCredential };
  check('A signup', 'the new session is a guardian session that works (GET /v1/me)', (await call('GET', '/v1/me', A.tok)).status, 200);

  const u = await admin.query(`SELECT display_name, home_tz, email FROM app_user WHERE id = $1`, [A.userId]);
  check('A signup', 'app_user row has the name and zone', `${u.rows[0].display_name}|${u.rows[0].home_tz}`, 'Dad|America/Chicago');
  const pin = await admin.query(`SELECT pin_hash FROM pin_credential WHERE user_id = $1`, [A.userId]);
  check('A signup', 'the PIN is stored hashed, never in the clear', pin.rows[0].pin_hash.includes('4821'), 'false');
  const dev = await admin.query(`SELECT role, target_id, paired_via, credential_hash FROM paired_device WHERE id = $1`, [A.deviceId]);
  check('A signup', 'a guardian device was enrolled at sign-up (paired_via NULL)',
    `${dev.rows[0].role}|${dev.rows[0].target_id === A.userId}|${dev.rows[0].paired_via}`, 'guardian|true|null');
  check('A signup', 'only the credential\'s digest is stored', dev.rows[0].credential_hash === createHash('sha256').update(A.cred).digest('hex'), 'true');
  const al = await admin.query(`SELECT redeemed_by, redeemed_at FROM signup_allowance WHERE token_hash = $1`, [signupAllowanceDigest(tok0)]);
  check('A signup', 'the allowance is marked redeemed by this account', al.rows[0].redeemed_by === A.userId && al.rows[0].redeemed_at !== null, 'true');
  const plain = await admin.query(`SELECT count(*)::int n FROM signup_allowance WHERE token_hash = $1 OR label = $1`, [tok0]);
  check('A signup', 'the plaintext token is not stored anywhere in the table', plain.rows[0].n, 0);

  // replay / expiry / uniform answer
  const replay = await signup(tok0, { displayName: 'Replayer' });
  check('A signup', 'replaying a redeemed token -> 403 invalid_allowance (same as unknown)',
    JSON.stringify(replay.body) + replay.status, JSON.stringify(bogus.body) + bogus.status);
  const dup = await admin.query(`SELECT count(*)::int n FROM app_user WHERE display_name = 'Replayer'`);
  check('A signup', 'the replay created no account', dup.rows[0].n, 0);
  const expiredTok = await newAllowance({ now: new Date(Date.now() - 20 * 86_400_000), ttlDays: 14 });
  const exp = await signup(expiredTok, { displayName: 'Expired' });
  check('A signup', 'an expired allowance is indistinguishable from an unknown one',
    JSON.stringify(exp.body) + exp.status, JSON.stringify(bogus.body) + bogus.status);

  // the device credential keeps the grown-up signed in
  const ref = await call('POST', '/v1/auth/session/refresh', null, { deviceId: A.deviceId, deviceCredential: A.cred });
  check('A signup', 'the enrolled device refreshes its session with the credential', ref.status, 200);
  const refTok = ref.body?.token ?? ref.body?.sessionToken;
  check('A signup', 'the refreshed session works', (await call('GET', '/v1/me', refTok)).status, 200);
  check('A signup', 'a wrong credential -> 401 invalid_device_credential',
    (await call('POST', '/v1/auth/session/refresh', null, { deviceId: A.deviceId, deviceCredential: 'nope' + A.cred })).body?.error, 'invalid_device_credential');

  // concurrency: ONE allowance, many racers -> exactly one account
  const racing = await newAllowance();
  const raced = await Promise.all([1, 2, 3, 4, 5].map((i) => signup(racing, { displayName: `Racer${i}-${RUN}` })));
  const winners = raced.filter((r) => r.status === 201);
  winners.forEach((w) => track(w.body.userId));
  check('A signup', 'five concurrent redemptions of one allowance create exactly one account', winners.length, 1);
  check('A signup', 'the losers all got 403', raced.filter((r) => r.status === 403).length, 4);

  // kill switch
  const held = await newAllowance();
  await setSignupPolicy(pool, { enabled: false });
  const off = await signup(held, { displayName: 'WhileOff' });
  check('A signup', 'kill switch off -> 403 signup_disabled', `${off.status} ${off.body?.error}`, '403 signup_disabled');
  check('A signup', 'a refused sign-up does not burn the allowance',
    (await admin.query(`SELECT count(*)::int n FROM signup_allowance WHERE token_hash = $1 AND redeemed_at IS NULL`, [signupAllowanceDigest(held)])).rows[0].n, 1);
  // ...but a caller with no live token learns nothing about the kill switch:
  // the allowance is judged first, so a junk token gets the uniform answer.
  const offBogus = await signup('K'.repeat(43), { displayName: 'NoTokenWhileOff' });
  check('A signup', 'kill switch off + junk token -> 403 invalid_allowance (the switch is not readable without a token)',
    `${offBogus.status} ${offBogus.body?.error}`, '403 invalid_allowance');
  await setSignupPolicy(pool, { enabled: true });
  // cap
  const pol = await signupPolicyFor(pool);
  await setSignupPolicy(pool, { maxAccounts: pol.redeemed });
  const capped = await signup(held, { displayName: 'OverCap' });
  check('A signup', 'cap reached -> 403 signup_cap_reached', `${capped.status} ${capped.body?.error}`, '403 signup_cap_reached');
  const cappedBogus = await signup('L'.repeat(43), { displayName: 'NoTokenAtCap' });
  check('A signup', 'cap reached + junk token -> 403 invalid_allowance (the cap is not readable without a token)',
    `${cappedBogus.status} ${cappedBogus.body?.error}`, '403 invalid_allowance');
  await setSignupPolicy(pool, { maxAccounts: pol.redeemed + 1 });
  const underCap = await signup(held, { displayName: `Second-${RUN}`, pin: '7315' });
  check('A signup', 'raising the cap by one lets exactly one more family in', underCap.status, 201);
  B = { userId: track(underCap.body.userId), tok: underCap.body.token, deviceId: underCap.body.deviceId, cred: underCap.body.deviceCredential };
  const another = await newAllowance();
  check('A signup', 'and then the cap holds again', (await signup(another, { displayName: 'ThirdOverCap' })).body?.error, 'signup_cap_reached');
  await restorePolicy();

  // RLS: no session can see or write the new tables
  const seen = await withSession(pool, { roleName: 'guardian', userId: A.userId, childId: null },
    (q) => q(`SELECT count(*)::int n FROM signup_allowance`));
  check('A rls', 'a guardian session sees ZERO signup_allowance rows (FORCE RLS, system only)', seen[0].n, 0);
  let wrote = 'wrote';
  try {
    await withSession(pool, { roleName: 'guardian', userId: A.userId, childId: null },
      (q) => q(`INSERT INTO signup_allowance (token_hash, expires_at) VALUES ($1, now() + interval '1 day')`, ['a'.repeat(64)]));
  } catch { wrote = 'refused'; }
  check('A rls', 'a guardian session cannot mint itself an allowance', wrote, 'refused');
  const polSeen = await withSession(pool, { roleName: 'guardian', userId: A.userId, childId: null },
    (q) => q(`SELECT count(*)::int n FROM signup_policy`));
  check('A rls', 'a guardian session cannot read signup_policy either', polSeen[0].n, 0);
  const childSeen = await withSession(pool, { roleName: 'child', userId: null, childId: randomUUID() },
    (q) => q(`SELECT count(*)::int n FROM signup_allowance`));
  check('A rls', 'a child session sees zero allowances', childSeen[0].n, 0);
}

// ===========================================================================
// B · CHILDREN
// ===========================================================================
let CHILD_A, CHILD_B;
{
  const body = { displayName: 'Ivy', birthDate: '2018-03-04', homeTz: 'America/Chicago', pin: '4821' };
  check('B child', 'no session -> 401', (await call('POST', '/v1/children', null, body)).status, 401);
  check('B child', 'no pin -> 400 pin_required', (await call('POST', '/v1/children', A.tok, { ...body, pin: undefined })).body?.error, 'pin_required');
  const wrong = await call('POST', '/v1/children', A.tok, { ...body, pin: '0000' });
  check('B child', 'wrong pin -> 403 pin_incorrect', `${wrong.status} ${wrong.body?.error}`, '403 pin_incorrect');
  check('B child', 'blank name -> 400', (await call('POST', '/v1/children', A.tok, { ...body, displayName: '' })).status, 400);
  check('B child', 'a future birth date -> 400', (await call('POST', '/v1/children', A.tok, { ...body, birthDate: '2999-01-01' })).body?.error, 'invalid_birth_date');
  check('B child', 'an adult birth date -> 400', (await call('POST', '/v1/children', A.tok, { ...body, birthDate: '1980-01-01' })).body?.error, 'invalid_birth_date');
  check('B child', 'a malformed birth date -> 400', (await call('POST', '/v1/children', A.tok, { ...body, birthDate: '2018-13-45' })).body?.error, 'invalid_birth_date');
  check('B child', 'a bad zone -> 400', (await call('POST', '/v1/children', A.tok, { ...body, homeTz: 'Nowhere/Land' })).body?.error, 'invalid_home_tz');
  check('B child', 'nothing was created by any rejected attempt',
    (await admin.query(`SELECT count(*)::int n FROM guardianship WHERE user_id = $1`, [A.userId])).rows[0].n, 0);
  check('B child', 'before any child exists, GET /v1/me/children is empty',
    JSON.stringify((await call('GET', '/v1/me/children', A.tok)).body), '{"children":[]}');

  const made = await call('POST', '/v1/children', A.tok, body);
  check('B child', 'a guardian creates a child -> 201', made.status, 201);
  CHILD_A = made.body.child.id; children.push(CHILD_A);
  check('B child', 'the response names the child and the caller\'s role', `${made.body.child.displayName}|${made.body.child.role}`, 'Ivy|guardian');
  const listed = await call('GET', '/v1/me/children', A.tok);
  check('B child', 'GET /v1/me/children lists exactly that child', listed.body.children.map((c) => c.id).join(), CHILD_A);
  const g = await admin.query(`SELECT role, observer_only, restricted, valid @> now() AS live FROM guardianship WHERE child_id = $1 AND user_id = $2`, [CHILD_A, A.userId]);
  check('B child', 'the creator holds a LIVE, unrestricted guardian edge', `${g.rows[0].role}|${g.rows[0].observer_only}|${g.rows[0].restricted}|${g.rows[0].live}`, 'guardian|false|false|true');
  check('B child', 'the edge actually works: GET .../now -> 200', (await call('GET', `/v1/children/${CHILD_A}/now`, A.tok)).status, 200);
  const dp = await admin.query(`SELECT kind FROM day_part WHERE child_id = $1 ORDER BY starts_local`, [CHILD_A]);
  check('B child', 'a default day-part plan with a bedtime part exists (so messages can deliver)', dp.rows.some((r) => r.kind === 'bedtime'), 'true');
  const tzi = await admin.query(`SELECT tz FROM child_tz_interval WHERE child_id = $1 AND valid @> now()`, [CHILD_A]);
  check('B child', 'a live timezone interval exists for the child', tzi.rows[0]?.tz, 'America/Chicago');

  // a second real family: full isolation
  check('B isolation', 'family B starts with no children', (await call('GET', '/v1/me/children', B.tok)).body.children.length, 0);
  const madeB = await call('POST', '/v1/children', B.tok, { displayName: 'Otis', birthDate: '2017-06-11', homeTz: 'America/Denver', pin: '7315' });
  check('B isolation', 'family B creates its own child', madeB.status, 201);
  CHILD_B = madeB.body.child.id; children.push(CHILD_B);
  check('B isolation', 'A never sees B\'s child in /v1/me/children', (await call('GET', '/v1/me/children', A.tok)).body.children.map((c) => c.id).join(), CHILD_A);
  check('B isolation', 'B never sees A\'s child', (await call('GET', '/v1/me/children', B.tok)).body.children.map((c) => c.id).join(), CHILD_B);
  check('B isolation', 'A cannot read B\'s child (GET .../now) -> 403', (await call('GET', `/v1/children/${CHILD_B}/now`, A.tok)).status, 403);
  check('B isolation', 'A cannot list invites for B\'s child -> 403', (await call('GET', `/v1/children/${CHILD_B}/guardian-invites`, A.tok)).status, 403);
  check('B isolation', 'A cannot invite into B\'s child -> 403', (await call('POST', `/v1/children/${CHILD_B}/guardianships`, A.tok, { role: 'guardian', label: 'x', invitedEmail: emailFor('x'), pin: '4821' })).status, 403);
  const rlsSeen = await withSession(pool, { roleName: 'guardian', userId: A.userId, childId: null },
    (q) => q(`SELECT id FROM child WHERE id = $1`, [CHILD_B]));
  check('B isolation', 'RLS itself hides B\'s child from A\'s session', rlsSeen.length, 0);
  const kidTok = api.issueSessionToken({ userId: null, roleName: 'child', childId: CHILD_A, escalated: false });
  check('B isolation', 'a child-role session cannot create a child',
    (await call('POST', '/v1/children', kidTok, { displayName: 'Z', birthDate: '2018-03-04', homeTz: 'UTC', pin: '4821' })).status, 403);
  check('B isolation', 'a child-role session cannot list "my children"', (await call('GET', '/v1/me/children', kidTok)).status, 403);
}

// ===========================================================================
// C · INVITES: the inviter's confirm is the ONLY thing that creates the edge
// ===========================================================================
let NANA;
{
  const inviteBody = (email, over = {}) => ({ role: 'guardian', label: 'Nana', invitedEmail: email, pin: '4821', ...over });
  const nanaEmail = emailFor('nana');
  const created = await call('POST', `/v1/children/${CHILD_A}/guardianships`, A.tok, inviteBody(nanaEmail));
  check('C invite', 'A invites Nana -> 201', created.status, 201);
  const inv1 = created.body.invite.id;
  const statusOf = async (id) => (await call('GET', `/v1/children/${CHILD_A}/guardian-invites`, A.tok)).body.invites.find((i) => i.id === id);
  check('C invite', 'listing: freshly created = sent', (await statusOf(inv1)).status, 'sent');
  const pre = await call('POST', `/v1/guardian-invites/${inv1}/confirm`, A.tok, { pin: '4821' });
  check('C invite', 'confirming an invite nobody has presented -> 409 not_claimed', `${pre.status} ${pre.body?.error}`, '409 not_claimed');
  check('C invite', 'anonymous accept works', (await call('POST', `/v1/guardian-invites/${inv1}/accept`, null)).status, 200);
  check('C invite', 'listing: accepted', (await statusOf(inv1)).status, 'accepted');

  const boot = await call('POST', `/v1/guardian-invites/${inv1}/bootstrap`, null, { displayName: 'Nana', enrol: true });
  check('C invite', 'bootstrap with enrol -> 201 with a session AND a device credential',
    `${boot.status}|${typeof boot.body?.deviceCredential}|${typeof boot.body?.deviceId}`, '201|string|string');
  NANA = { userId: track(boot.body.userId), tok: boot.body.token, deviceId: boot.body.deviceId, cred: boot.body.deviceCredential };
  const refreshNana = await call('POST', '/v1/auth/session/refresh', null, { deviceId: NANA.deviceId, deviceCredential: NANA.cred });
  check('C invite', 'Nana\'s enrolled device can refresh (she is not stranded after the hour)', refreshNana.status, 200);

  // BEFORE confirm: zero access (the gap the audit found, now asserted as the safe pre-state)
  check('C invite', 'before confirm Nana lists no children', (await call('GET', '/v1/me/children', NANA.tok)).body.children.length, 0);
  check('C invite', 'before confirm Nana is refused A\'s child (GET .../now -> 403)', (await call('GET', `/v1/children/${CHILD_A}/now`, NANA.tok)).status, 403);
  const waiting = await statusOf(inv1);
  check('C invite', 'listing: waiting_for_you, with only the NAME she gave', `${waiting.status}|${waiting.claimantName}`, 'waiting_for_you|Nana');
  check('C invite', 'the listing carries no user id for the claimant', JSON.stringify(waiting).includes(NANA.userId), 'false');

  // confirm is inviter-only, PIN-gated
  check('C invite', 'a different family\'s guardian confirming A\'s invite -> 404 (indistinguishable from none)',
    (await call('POST', `/v1/guardian-invites/${inv1}/confirm`, B.tok, { pin: '7315' })).status, 404);
  check('C invite', 'Nana (the claimant) cannot confirm her own invite', (await call('POST', `/v1/guardian-invites/${inv1}/confirm`, NANA.tok, { pin: '1234' })).status, 403);
  check('C invite', 'confirm with no pin -> 400', (await call('POST', `/v1/guardian-invites/${inv1}/confirm`, A.tok, {})).body?.error, 'pin_required');
  check('C invite', 'confirm with the wrong pin -> 403', (await call('POST', `/v1/guardian-invites/${inv1}/confirm`, A.tok, { pin: '9999' })).body?.error, 'pin_incorrect');
  check('C invite', 'none of those created an edge',
    (await admin.query(`SELECT count(*)::int n FROM guardianship WHERE child_id = $1 AND user_id = $2`, [CHILD_A, NANA.userId])).rows[0].n, 0);

  const conf = await call('POST', `/v1/guardian-invites/${inv1}/confirm`, A.tok, { pin: '4821' });
  check('C invite', 'the inviter confirms with her PIN -> 200', `${conf.status}|${conf.body?.role}`, '200|guardian');
  const edge = await admin.query(`SELECT role, scope, observer_only, restricted, valid @> now() AS live FROM guardianship WHERE child_id = $1 AND user_id = $2`, [CHILD_A, NANA.userId]);
  check('C invite', 'the edge has exactly the invite\'s role and scope, live and unrestricted',
    `${edge.rows[0].role}|${JSON.stringify(edge.rows[0].scope)}|${edge.rows[0].restricted}|${edge.rows[0].live}`, 'guardian|{}|false|true');
  const consumed = await admin.query(`SELECT confirmed_at, confirmed_by FROM guardian_invite WHERE id = $1`, [inv1]);
  check('C invite', 'the invite is consumed by the inviter in the same step', consumed.rows[0].confirmed_by === A.userId && consumed.rows[0].confirmed_at !== null, 'true');
  check('C invite', 'Nana now lists A\'s child', (await call('GET', '/v1/me/children', NANA.tok)).body.children.map((c) => c.id).join(), CHILD_A);
  check('C invite', 'Nana can now read the child (GET .../now -> 200)', (await call('GET', `/v1/children/${CHILD_A}/now`, NANA.tok)).status, 200);
  check('C invite', 'but Nana still cannot reach B\'s child', (await call('GET', `/v1/children/${CHILD_B}/now`, NANA.tok)).status, 403);
  const ev = await admin.query(`SELECT kind, summary FROM security_event WHERE child_id = $1 AND kind = 'guardian_added'`, [CHILD_A]);
  check('C invite', 'a content-free guardian_added security event was recorded for the family', `${ev.rows.length}|${ev.rows[0]?.summary.includes('Nana')}|${ev.rows[0]?.summary.includes('@')}`, '1|false|false');
  const again = await call('POST', `/v1/guardian-invites/${inv1}/confirm`, A.tok, { pin: '4821' });
  check('C invite', 'confirming twice -> 409 already_confirmed, still one edge', `${again.status} ${again.body?.error}|${(await admin.query(`SELECT count(*)::int n FROM guardianship WHERE child_id = $1 AND user_id = $2`, [CHILD_A, NANA.userId])).rows[0].n}`, '409 already_confirmed|1');
  check('C invite', 'listing: confirmed', (await statusOf(inv1)).status, 'confirmed');
  check('C invite', 'a confirmed invite can no longer be claimed', (await call('POST', `/v1/guardian-invites/${inv1}/claim`, NANA.tok)).body?.error, 'already_confirmed');

  // scope and role come from the invite, not from the claimant
  const sitterEmail = emailFor('sitter');
  const si = (await call('POST', `/v1/children/${CHILD_A}/guardianships`, A.tok, inviteBody(sitterEmail, { role: 'sitter', label: 'Sam' }))).body.invite.id;
  await call('POST', `/v1/guardian-invites/${si}/accept`, null);
  const sitterBoot = await call('POST', `/v1/guardian-invites/${si}/bootstrap`, null, { displayName: 'Sam' });
  track(sitterBoot.body.userId);
  check('C invite', 'bootstrap WITHOUT enrol keeps the pre-0050 response shape (no device fields)', `${'deviceCredential' in sitterBoot.body}|${'deviceId' in sitterBoot.body}`, 'false|false');
  await call('POST', `/v1/guardian-invites/${si}/confirm`, A.tok, { pin: '4821' });
  const sEdge = await admin.query(`SELECT role FROM guardianship WHERE child_id = $1 AND user_id = $2`, [CHILD_A, sitterBoot.body.userId]);
  check('C invite', 'a sitter invite yields a SITTER edge, not a guardian one', sEdge.rows[0]?.role, 'sitter');
  check('C invite', 'a sitter cannot invite (not a guardian of the child)',
    (await call('POST', `/v1/children/${CHILD_A}/guardianships`, sitterBoot.body.token, inviteBody(emailFor('z')))).status, 403);
  check('C invite', 'a sitter cannot list the inviter\'s invites', (await call('GET', `/v1/children/${CHILD_A}/guardian-invites`, sitterBoot.body.token)).status, 403);

  // decline
  const dEmail = emailFor('declined');
  const di = (await call('POST', `/v1/children/${CHILD_A}/guardianships`, A.tok, inviteBody(dEmail, { label: 'Stranger' }))).body.invite.id;
  await call('POST', `/v1/guardian-invites/${di}/accept`, null);
  const dBoot = await call('POST', `/v1/guardian-invites/${di}/bootstrap`, null, { displayName: 'Not Who I Meant' });
  track(dBoot.body.userId);
  check('C decline', 'a non-inviter cannot decline -> 404', (await call('POST', `/v1/guardian-invites/${di}/decline`, B.tok)).status, 404);
  check('C decline', 'the inviter declines -> 200', (await call('POST', `/v1/guardian-invites/${di}/decline`, A.tok)).status, 200);
  check('C decline', 'declining twice is idempotent', (await call('POST', `/v1/guardian-invites/${di}/decline`, A.tok)).status, 200);
  const dc = await call('POST', `/v1/guardian-invites/${di}/confirm`, A.tok, { pin: '4821' });
  check('C decline', 'a declined invite cannot be confirmed -> 410 declined', `${dc.status} ${dc.body?.error}`, '410 declined');
  check('C decline', 'the declined stranger holds no edge and sees no children',
    `${(await admin.query(`SELECT count(*)::int n FROM guardianship WHERE user_id = $1`, [dBoot.body.userId])).rows[0].n}|${(await call('GET', '/v1/me/children', dBoot.body.token)).body.children.length}`, '0|0');
  check('C decline', 'listing: declined', (await statusOf(di)).status, 'declined');
  const dAccept = await call('POST', `/v1/guardian-invites/${di}/accept`, null);
  check('C decline', 'a declined invite cannot be accepted again', dAccept.status, 409);

  // revoke (before accept)
  const ri = (await call('POST', `/v1/children/${CHILD_A}/guardianships`, A.tok, inviteBody(emailFor('revoked')))).body.invite.id;
  check('C revoke', 'revoke works before accept', (await call('POST', `/v1/guardian-invites/${ri}/revoke`, A.tok)).status, 200);
  check('C revoke', 'a revoked invite cannot be accepted', (await call('POST', `/v1/guardian-invites/${ri}/accept`, null)).status, 409);
  check('C revoke', 'a revoked invite cannot bootstrap', (await call('POST', `/v1/guardian-invites/${ri}/bootstrap`, null, { displayName: 'X' })).status, 409);
  const rc = await call('POST', `/v1/guardian-invites/${ri}/confirm`, A.tok, { pin: '4821' });
  check('C revoke', 'a revoked invite cannot be confirmed -> 410 revoked', `${rc.status} ${rc.body?.error}`, '410 revoked');

  // expiry between claim and confirm
  const xi = (await call('POST', `/v1/children/${CHILD_A}/guardianships`, A.tok, inviteBody(emailFor('late')))).body.invite.id;
  await call('POST', `/v1/guardian-invites/${xi}/accept`, null);
  const xBoot = await call('POST', `/v1/guardian-invites/${xi}/bootstrap`, null, { displayName: 'Late' });
  track(xBoot.body.userId);
  await admin.query(`UPDATE guardian_invite SET expires_at = now() - interval '1 minute' WHERE id = $1`, [xi]);
  const xc = await call('POST', `/v1/guardian-invites/${xi}/confirm`, A.tok, { pin: '4821' });
  check('C expiry', 'an invite that expired before confirm -> 410 expired', `${xc.status} ${xc.body?.error}`, '410 expired');
  check('C expiry', '...and created no edge', (await admin.query(`SELECT count(*)::int n FROM guardianship WHERE user_id = $1`, [xBoot.body.userId])).rows[0].n, 0);
  check('C expiry', 'listing: expired', (await statusOf(xi)).status, 'expired');

  // existing account: the second invite to a registered email
  const madeTwo = await call('POST', '/v1/children', A.tok, { displayName: 'June', birthDate: '2020-09-09', homeTz: 'America/Chicago', pin: '4821' });
  const CHILD_A2 = madeTwo.body.child.id; children.push(CHILD_A2);
  const statusOf2 = async (id) => (await call('GET', `/v1/children/${CHILD_A2}/guardian-invites`, A.tok)).body.invites.find((i) => i.id === id);
  const second = (await call('POST', `/v1/children/${CHILD_A2}/guardianships`, A.tok, inviteBody(nanaEmail, { role: 'trusted_adult', label: 'Nana' }))).body.invite.id;
  await call('POST', `/v1/guardian-invites/${second}/accept`, null);
  const dead = await call('POST', `/v1/guardian-invites/${second}/bootstrap`, null, { displayName: 'Nana' });
  check('C claim', 'bootstrap for an already-registered email -> 409 email_already_registered (no session minted)', `${dead.status} ${dead.body?.error} ${'token' in (dead.body ?? {})}`, '409 email_already_registered false');
  // KNOWN LIMIT, recorded rather than hidden: `claim` matches app_user.email
  // against the invited email, and no route sets or verifies an email on a
  // sign-up-created account (POST /v1/auth/signup stores none; only the invite
  // bootstrap writes one). B was created by sign-up, so it can never claim an
  // invite addressed to anyone, even to the person who owns it. Closing that
  // needs a verified-email step (a mailer), which this lane does not build.
  const bEmail = await admin.query(`SELECT email FROM app_user WHERE id = $1`, [B.userId]);
  check('C claim', 'a sign-up-created account has no email (claim cannot match it)', bEmail.rows[0].email, null);
  check('C claim', 'so a sign-up-created account cannot claim an invite -> 404 (claim covers bootstrap-created accounts only)',
    (await call('POST', `/v1/guardian-invites/${second}/claim`, B.tok)).status, 404);
  check('C claim', 'claim needs a session', (await call('POST', `/v1/guardian-invites/${second}/claim`, null)).status, 401);
  check('C claim', 'another family\'s account (different email) cannot claim it -> 404', (await call('POST', `/v1/guardian-invites/${second}/claim`, B.tok)).status, 404);
  check('C claim', 'the inviter\'s own account cannot claim it either -> 404', (await call('POST', `/v1/guardian-invites/${second}/claim`, A.tok)).status, 404);
  const cl = await call('POST', `/v1/guardian-invites/${second}/claim`, NANA.tok);
  check('C claim', 'the account with the invited email claims it -> waiting', `${cl.status} ${cl.body?.status}`, '200 waiting_for_confirmation');
  check('C claim', 'claim granted nothing yet', (await call('GET', `/v1/children/${CHILD_A2}/now`, NANA.tok)).status, 403);
  check('C claim', 'claiming twice by the same account is idempotent', (await call('POST', `/v1/guardian-invites/${second}/claim`, NANA.tok)).status, 200);
  check('C claim', 'listing shows her waiting', (await statusOf2(second)).status, 'waiting_for_you');
  const conf2 = await call('POST', `/v1/guardian-invites/${second}/confirm`, A.tok, { pin: '4821' });
  check('C claim', 'the inviter confirms -> 200', conf2.status, 200);
  check('C claim', 'Nana now holds a trusted_adult edge to the second child and a guardian edge to the first',
    (await call('GET', '/v1/me/children', NANA.tok)).body.children.map((c) => `${c.displayName}:${c.role}`).sort().join(), 'Ivy:guardian,June:trusted_adult');

  // inviter loses guardianship before confirming
  const lateEmail = emailFor('closed');
  const ci = (await call('POST', `/v1/children/${CHILD_A2}/guardianships`, A.tok, inviteBody(lateEmail))).body.invite.id;
  await call('POST', `/v1/guardian-invites/${ci}/accept`, null);
  const cBoot = await call('POST', `/v1/guardian-invites/${ci}/bootstrap`, null, { displayName: 'Closed' });
  track(cBoot.body.userId);
  await admin.query(`UPDATE guardianship SET closed_at = now(), closed_reason = 'revoked' WHERE child_id = $1 AND user_id = $2`, [CHILD_A2, A.userId]);
  const cc = await call('POST', `/v1/guardian-invites/${ci}/confirm`, A.tok, { pin: '4821' });
  check('C closed', 'an inviter whose own edge was closed can no longer confirm -> 403', `${cc.status} ${cc.body?.error}`, '403 inviter_not_guardian');
  check('C closed', '...and no edge was created', (await admin.query(`SELECT count(*)::int n FROM guardianship WHERE user_id = $1`, [cBoot.body.userId])).rows[0].n, 0);
  await admin.query(`UPDATE guardianship SET closed_at = NULL, closed_reason = NULL WHERE child_id = $1 AND user_id = $2`, [CHILD_A2, A.userId]);

  // database-level: the new invariants hold even for a direct writer
  let dbRefused = 'accepted';
  try { await admin.query(`UPDATE guardian_invite SET confirmed_at = now() WHERE id = $1`, [ri]); } catch { dbRefused = 'refused'; }
  check('C db', 'a confirm with no claim is refused by the table\'s own CHECK', dbRefused, 'refused');
  dbRefused = 'accepted';
  try { await admin.query(`UPDATE guardian_invite SET declined_at = now() WHERE id = $1`, [inv1]); } catch { dbRefused = 'refused'; }
  check('C db', 'a confirmed invite cannot also be declined (CHECK)', dbRefused, 'refused');
}

// ===========================================================================
// D · DEACTIVATION ends a live device session at once
// ===========================================================================
{
  check('D deactivate', 'before deleting, Nana\'s device session works', (await call('GET', '/v1/me', NANA.tok)).status, 200);
  const del = await call('POST', '/v1/me/delete', NANA.tok);
  check('D deactivate', 'POST /v1/me/delete -> 200', del.status, 200);
  const after = await call('GET', '/v1/me', NANA.tok);
  check('D deactivate', 'her already-issued device session is dead immediately -> 401 device_revoked', `${after.status} ${after.body?.error}`, '401 device_revoked');
  const r = await call('POST', '/v1/auth/session/refresh', null, { deviceId: NANA.deviceId, deviceCredential: NANA.cred });
  check('D deactivate', 'her credential can no longer mint a session -> 401', r.status, 401);
}

// ===========================================================================
// E · A SIGN-UP-CREATED CHILD IS REACHABLE: pair a device, queue a message that
//     can materialize, start/join/end a call under strict ids
//     (the delivery WORKER itself is the delivery lane's, PR #220)
// ===========================================================================
{
  // pair a child device to A's child through the real routes
  const code = await call('POST', `/v1/children/${CHILD_A}/device-pairing-codes`, A.tok, { pin: '4821' });
  check('E chain', 'A mints a child pairing code', code.status, 201);
  const red = await call('POST', '/v1/device-pairing/redeem', null, { code: code.body.numericCode, role: 'child' });
  check('E chain', 'the child device redeems it and gets a child session', `${red.status}|${red.body?.targetId === CHILD_A}`, '201|true');
  const kid = red.body.sessionToken;
  check('E chain', 'the paired child device can read its own now', (await call('GET', `/v1/children/${CHILD_A}/now`, kid)).status, 200);
  check('E chain', 'and its inbox is empty, not an error', JSON.stringify((await call('GET', `/v1/children/${CHILD_A}/inbox`, kid)).body.entries), '[]');
  check('E chain', 'the same child session cannot read another family\'s child', (await call('GET', `/v1/children/${CHILD_B}/inbox`, kid)).status, 403);

  // a message to a brand-new child materializes (this needs the default bedtime day part)
  const MP4 = Buffer.concat([Buffer.from([0, 0, 0, 0x18]), Buffer.from('ftypisom'), Buffer.alloc(32, 7)]);
  const up = await call('POST', `/v1/children/${CHILD_A}/media`, A.tok, { bytes: MP4.toString('base64') });
  const sent = await call('POST', `/v1/children/${CHILD_A}/messages`, A.tok, { storageKey: up.body.storageKey, durationMs: 4200 });
  check('E chain', 'A sends a goodnight video to the child she created -> 201 pending', `${sent.status} ${sent.body?.state}`, '201 pending');
  await runRematerializeSweep(pool, { now: DateTime.utc().minus({ days: 3 }) });
  const st = await admin.query(`SELECT state, scheduled_at IS NOT NULL AS timed FROM delivery_intent WHERE id = $1`, [sent.body.id]);
  check('E chain', 'it MATERIALIZES (pending -> ready with an instant): the default day-part plan has a bedtime', `${st.rows[0].state}|${st.rows[0].timed}`, 'ready|true');
  const bare = await call('POST', '/v1/children', A.tok, { displayName: 'Bare', birthDate: '2019-01-01', homeTz: 'America/Chicago', pin: '4821' });
  children.push(bare.body.child.id);
  await admin.query(`DELETE FROM day_part WHERE child_id = $1`, [bare.body.child.id]);
  const up2 = await call('POST', `/v1/children/${bare.body.child.id}/media`, A.tok, { bytes: MP4.toString('base64') });
  const sent2 = await call('POST', `/v1/children/${bare.body.child.id}/messages`, A.tok, { storageKey: up2.body.storageKey, durationMs: 4200 });
  check('E chain', 'control: the same message to a child with NO day parts is refused 400 daypart_undefined (why the default plan exists)',
    `${sent2.status} ${sent2.body?.error}`, '400 daypart_undefined');

  // the call-session id must survive the strict-ids guard (audit gap 7)
  const started = await call('POST', `/v1/children/${CHILD_A}/calls`, A.tok);
  check('E call', 'a guardian starts a call -> 201', started.status, 201);
  const sid = started.body?.sessionId;
  check('E call', 'the session id is a canonical dashed uuid', /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(String(sid)), 'true');
  const joined = await call('POST', `/v1/children/${CHILD_A}/calls/${sid}/join`, kid);
  check('E call', 'the child can JOIN with the id the start returned (was 400 bad_path)', joined.status, 200);
  const ended = await call('POST', `/v1/children/${CHILD_A}/calls/${sid}/end`, A.tok);
  check('E call', 'the guardian can END it with that id', ended.status, 200);
  const again = await call('POST', `/v1/children/${CHILD_A}/calls/${sid}/end`, A.tok);
  check('E call', 'ending twice is a harmless 200 no-op (ended:false)', `${again.status}|${again.body?.ended}`, '200|false');
}

// ===========================================================================
// F · OPERATOR CLI
// ===========================================================================
{
  const out = [];
  const say = (s) => out.push(String(s));
  check('F cli', 'issue returns 0', await provisionCli(['issue', '--label', LABEL, '--days', '3'], pool, say), 0);
  const printed = out[1];
  check('F cli', 'it prints a long random token once', printed.length >= 40, 'true');
  const row = await admin.query(`SELECT label, (expires_at - created_at) AS ttl FROM signup_allowance WHERE token_hash = $1`, [signupAllowanceDigest(printed)]);
  check('F cli', 'the stored row is the digest of exactly that token, with a 3-day life', `${row.rows[0].label}|${row.rows[0].ttl.days}`, `${LABEL}|3`);
  check('F cli', 'a usable token: it actually signs someone up', (await signup(printed, { displayName: `Cli-${RUN}` }).then((r) => { if (r.body?.userId) track(r.body.userId); return r.status; })), 201);
  out.length = 0;
  check('F cli', 'disable returns 0', await provisionCli(['disable'], pool, say), 0);
  check('F cli', '...and sign-up is really off', (await signup(await newAllowance(), { displayName: 'NoWay' })).body?.error, 'signup_disabled');
  check('F cli', 'enable returns 0', await provisionCli(['enable'], pool, say), 0);
  check('F cli', 'cap with junk is refused (exit 2)', await provisionCli(['cap', 'banana'], pool, say), 2);
  check('F cli', 'cap -1 is refused', await provisionCli(['cap', '-1'], pool, say), 2);
  await provisionCli(['cap', 'none'], pool, say);
  out.length = 0;
  await provisionCli(['status'], pool, say);
  check('F cli', 'status prints enabled / cap / outstanding', out.join('|').includes('signup: enabled') && out.join('|').includes('cap: none'), 'true');
  check('F cli', 'unknown command -> usage, exit 2', await provisionCli(['wat'], pool, say), 2);
  let threw = 'no';
  try { await issueSignupAllowance(pool, { label: 'family of a@b.c' }); } catch { threw = 'yes'; }
  check('F cli', 'a label containing an email address is refused (no PII in the allowance table)', threw, 'yes');
  threw = 'no';
  try { await issueSignupAllowance(pool, { ttlDays: 400 }); } catch { threw = 'yes'; }
  check('F cli', 'an absurd lifetime is refused', threw, 'yes');
}

// ---------------------------------------------------------------------------
// cleanup: everything this run created, by id
await restorePolicy();
await admin.query(`DELETE FROM paired_device WHERE target_id = ANY($1::uuid[]) OR target_id = ANY($2::uuid[])`, [users, children]);
await admin.query(`DELETE FROM call_log WHERE child_id = ANY($1::uuid[])`, [children]);
await admin.query(`DELETE FROM child WHERE id = ANY($1::uuid[])`, [children]);
await admin.query(`DELETE FROM app_user WHERE id = ANY($1::uuid[])`, [users]);
await admin.query(`DELETE FROM signup_allowance WHERE label = $1`, [LABEL]);
await admin.end();
await pool.end();
await fs.rm(tmpRoot, { recursive: true, force: true });

let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
