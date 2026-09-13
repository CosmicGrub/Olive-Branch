/**
 * server/routes.mjs — POST /v1/guardian-invites/:inviteId/bootstrap. MASTERFILE
 * §11, §8.5, §7.1. Closes the account-creation gap CHANGELOG v0.49.9 found and
 * explicitly declined to invent an answer for: guardian_setup.dart's passkey
 * registration has ALWAYS required an already-authenticated guardian session,
 * and nowhere did a first-time guardian ever acquire one.
 *
 * Mirrors packages/api/test/messages_route.test.mjs's own pattern (real
 * Postgres, real Api + registerRoutes, api.handle() called in-process rather
 * than over a real socket) and packages/db/test/guardian_invite.test.mjs's own
 * "G" section (the exact no-session dispatch an invited party's real client
 * uses). Requires DATABASE_URL to be a NOSUPERUSER NOBYPASSRLS role
 * (db/DEPLOYMENT.md's app_owner) — not part of `npm test`'s default JS-suite
 * chain, same reason messages_route.test.mjs isn't.
 *
 * Eight sections:
 *   A. success — a real, accepted invite bootstraps: a real app_user row
 *      lands with the right email/display_name/home_tz, guardian_invite's own
 *      bootstrapped_at/bootstrap_user_id are set, and the minted token
 *      actually completes the next, UNCHANGED step of the real flow
 *      (POST .../webauthn/register/challenge).
 *   B. not_found — a never-existed invite id.
 *   C. not_accepted — a real invite that skipped the real accept route.
 *   D. expired — accepted, then backdated past its own decision window
 *      (defense in depth: acceptGuardianInvite() itself should already have
 *      refused this, so this proves the SECOND, independent check).
 *   E. revoked — a revoked-before-ever-accepted invite (0014's own CHECK
 *      permits that state) is refused as 'revoked', the more specific reason,
 *      not the also-true 'not_accepted'.
 *   F. already_bootstrapped — the single-use guarantee: calling bootstrap
 *      twice on the SAME invite does not mint a second account or a second
 *      token.
 *   G. email_already_registered — the real authentication-bypass boundary:
 *      an invite whose invited_email already has an app_user row (case-
 *      insensitively, citext) is refused outright, mints NO token, and
 *      creates NO row — this route must never become a way to acquire a
 *      session for an account that already exists.
 *   H. no leak into any OTHER route's authorization — two independently
 *      bootstrapped sessions (for two different children) hold ZERO
 *      guardianship edges anywhere (none is created here — a real, separate,
 *      still-open gap), so both are refused by every edge-gated route
 *      against EITHER child, while the one route this pass exists to unlock
 *      (webauthn register/challenge) stays open for each — proven over real
 *      HTTP, not asserted from the route table.
 *   I. the DB-level CHECK/UNIQUE constraints — bypassing bootstrapGuardianInvite()
 *      entirely via raw admin UPDATEs, mirroring guardian_invite.test.mjs's
 *      own "E" section for 0014's constraint.
 */
import pg from 'pg';
import { randomUUID, randomBytes } from 'node:crypto';
import { Api } from '../src/api.mjs';
import { createPool, dbPort, createGuardianInvite, acceptGuardianInvite,
  revokeGuardianInvite } from '../../db/src/pool.mjs';
import { registerRoutes } from '../../../server/routes.mjs';
import { issueSession } from '../../auth/src/auth.mjs';

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

const CHILD_A = randomUUID();
const CHILD_B = randomUUID();
const GUARDIAN_A = randomUUID();      // the one sending invites
const EXISTING_GUARDIAN = randomUUID(); // pre-existing account, for the G section

// app_user rows this run creates dynamically via the real route — collected
// so cleanup can find them without guessing ids.
const mintedUserIds = [];

await admin.query('BEGIN');
await admin.query(
  `INSERT INTO app_user (id, display_name, home_tz, email) VALUES
     ($1,'Guardian A (inviting)','America/Chicago', NULL),
     ($2,'Already Registered','America/Denver','Existing@Example.com')`,
  [GUARDIAN_A, EXISTING_GUARDIAN]);
await admin.query(
  `INSERT INTO child (id, display_name, birth_date, home_tz) VALUES
     ($1,'Wren','2017-06-11','America/New_York'),
     ($2,'Otis','2019-02-03','America/Los_Angeles')`,
  [CHILD_A, CHILD_B]);
await admin.query('COMMIT');

const rowCounts = async (email) => {
  const r = await admin.query(`SELECT count(*)::int AS n FROM app_user WHERE email = $1`, [email]);
  return r.rows[0].n;
};

const SECRET = Buffer.from('b'.repeat(32), 'utf8');
const NOW = Date.now();
const api = new Api(SECRET, dbPort(pool), () => NOW);
registerRoutes(api, pool);

const guardianATok = issueSession(SECRET,
  { userId: GUARDIAN_A, roleName: 'guardian', childId: null, escalated: false }, NOW);

const bootstrap = (inviteId, displayName) => api.handle(
  'POST', `/v1/guardian-invites/${inviteId}/bootstrap`, {},
  displayName === undefined ? '' : JSON.stringify({ displayName }),
);
const accept = (inviteId) => api.handle('POST', `/v1/guardian-invites/${inviteId}/accept`, {}, '');
const registerChallenge = (tok) => api.handle(
  'POST', '/v1/auth/webauthn/register/challenge',
  tok ? { authorization: `Bearer ${tok}` } : {}, '');
const getAvailability = (childId, tok) => api.handle(
  'GET', `/v1/children/${childId}/availability`,
  tok ? { authorization: `Bearer ${tok}` } : {}, '');

// ===========================================================================
// A · SUCCESS — real accept, real bootstrap, real downstream route
// ===========================================================================
{
  const created = await createGuardianInvite(
    pool, GUARDIAN_A, CHILD_A, 'guardian', 'Nana', 'nana@example.com');
  check('A success', 'invite created', created.ok, 'true');
  const inviteId = created.invite.id;

  const acceptRes = await accept(inviteId);
  check('A success', 'the real accept route succeeds first', acceptRes.status, '200');

  const before = await rowCounts('nana@example.com');
  const res = await bootstrap(inviteId, 'Nana Actual Name');
  check('A success', 'bootstrap on a real accepted invite returns 201', res.status, '201');
  check('A success', 'response carries ok:true', res.body?.ok, 'true');
  check('A success', 'response names the invited child', res.body?.childId, CHILD_A);
  check('A success', 'response carries a real token', typeof res.body?.token === 'string'
    && res.body.token.length > 0, 'true');
  const userId = res.body.userId;
  check('A success', 'response carries a real userId', typeof userId === 'string'
    && userId.length > 0, 'true');
  mintedUserIds.push(userId);

  const after = await rowCounts('nana@example.com');
  check('A success', 'exactly one app_user row was written', after - before, 1);

  const row = await admin.query(
    `SELECT display_name, home_tz, email, deactivated_at FROM app_user WHERE id = $1`, [userId]);
  check('A success', 'display_name round-trips (trimmed)', row.rows[0].display_name,
    'Nana Actual Name');
  check('A success', 'home_tz defaults from the CHILD the invite named',
    row.rows[0].home_tz, 'America/New_York');
  check('A success', 'email is the invite\'s own invited_email', row.rows[0].email,
    'nana@example.com');
  check('A success', 'the new account is not deactivated', row.rows[0].deactivated_at, 'null');

  const inviteRow = await admin.query(
    `SELECT bootstrapped_at, bootstrap_user_id FROM guardian_invite WHERE id = $1`, [inviteId]);
  check('A success', 'guardian_invite.bootstrapped_at is set',
    inviteRow.rows[0].bootstrapped_at !== null, 'true');
  check('A success', 'guardian_invite.bootstrap_user_id is the new account',
    inviteRow.rows[0].bootstrap_user_id, userId);

  // The one thing this route exists to unlock: the REAL, UNCHANGED WebAuthn
  // registration challenge route, called with nothing but this token.
  const challengeRes = await registerChallenge(res.body.token);
  check('A success', 'the minted token completes the real, EXISTING '
    + 'register/challenge route (200, not 401/403)', challengeRes.status, '200');
  check('A success', 'the challenge response is scoped to the same, real userId',
    challengeRes.body?.userId, userId);
  check('A success', 'a real challenge string is returned',
    typeof challengeRes.body?.challenge === 'string' && challengeRes.body.challenge.length > 0,
    'true');
}

// ===========================================================================
// B · not_found — a never-existed invite id
// ===========================================================================
{
  const res = await bootstrap(randomUUID(), 'Whoever');
  check('B not_found', 'bootstrapping a nonexistent invite is refused', res.status, '404');
  check('B not_found', 'reason is not_found', res.body?.error, 'not_found');
  check('B not_found', 'no token is minted', res.body?.token === undefined, 'true');
}

// ===========================================================================
// B2 · display name validation — checked before any invite is even looked
//     up, so a bad body never reaches (and never leaks the existence of) a
//     real invite id.
// ===========================================================================
{
  const anyId = randomUUID();
  const noBody = await bootstrap(anyId, undefined);
  check('B2 validation', 'no body at all is refused', noBody.status, '400');
  check('B2 validation', 'reason is display_name_required', noBody.body?.error,
    'display_name_required');

  const blank = await bootstrap(anyId, '   ');
  check('B2 validation', 'a whitespace-only displayName is refused', blank.status, '400');
  check('B2 validation', 'reason is display_name_required', blank.body?.error,
    'display_name_required');

  const wrongType = await api.handle(
    'POST', `/v1/guardian-invites/${anyId}/bootstrap`, {}, JSON.stringify({ displayName: 123 }));
  check('B2 validation', 'a non-string displayName is refused', wrongType.status, '400');
  check('B2 validation', 'reason is display_name_required', wrongType.body?.error,
    'display_name_required');
}

// ===========================================================================
// C · not_accepted — a real invite that skipped the real accept route
// ===========================================================================
{
  const created = await createGuardianInvite(
    pool, GUARDIAN_A, CHILD_A, 'guardian', 'Skipped Accept', 'skipped@example.com');
  const before = await rowCounts('skipped@example.com');
  const res = await bootstrap(created.invite.id, 'Skipped Accept');
  check('C not_accepted', 'bootstrap before accept is refused', res.status, '409');
  check('C not_accepted', 'reason is not_accepted', res.body?.error, 'not_accepted');
  const after = await rowCounts('skipped@example.com');
  check('C not_accepted', 'no app_user row was written', after, before);
}

// ===========================================================================
// D · expired — accepted, then backdated past its own decision window
//     (defense in depth: proves bootstrapGuardianInvite()'s OWN expires_at
//     check, independent of acceptGuardianInvite()'s, which should already
//     make this state unreachable through the real accept route alone).
// ===========================================================================
{
  const created = await createGuardianInvite(
    pool, GUARDIAN_A, CHILD_A, 'guardian', 'Expires Later', 'expireslater@example.com');
  const acceptRes = await accept(created.invite.id);
  check('D expired', 'accept succeeds while still live', acceptRes.status, '200');
  await admin.query(
    `UPDATE guardian_invite SET expires_at = now() - interval '1 day' WHERE id = $1`,
    [created.invite.id]);
  const before = await rowCounts('expireslater@example.com');
  const res = await bootstrap(created.invite.id, 'Expires Later');
  check('D expired', 'bootstrap on an accepted-but-now-expired invite is refused',
    res.status, '410');
  check('D expired', 'reason is expired', res.body?.error, 'expired');
  const after = await rowCounts('expireslater@example.com');
  check('D expired', 'no app_user row was written', after, before);
}

// ===========================================================================
// E · revoked — revoked BEFORE ever being accepted (0014's own CHECK
//     permits that state); named 'revoked', not the also-true 'not_accepted'.
// ===========================================================================
{
  const created = await createGuardianInvite(
    pool, GUARDIAN_A, CHILD_A, 'guardian', 'Revoked Before Accept', 'revoked@example.com');
  const revoked = await revokeGuardianInvite(pool, created.invite.id, GUARDIAN_A, new Date(NOW));
  check('E revoked', 'the real revoke succeeds', revoked.ok, 'true');
  const before = await rowCounts('revoked@example.com');
  const res = await bootstrap(created.invite.id, 'Revoked Before Accept');
  check('E revoked', 'bootstrap on a revoked invite is refused', res.status, '409');
  check('E revoked', 'reason is revoked, the more specific reason, not not_accepted',
    res.body?.error, 'revoked');
  const after = await rowCounts('revoked@example.com');
  check('E revoked', 'no app_user row was written', after, before);
}

// ===========================================================================
// F · already_bootstrapped — the single-use guarantee
// ===========================================================================
{
  const created = await createGuardianInvite(
    pool, GUARDIAN_A, CHILD_A, 'guardian', 'Bootstrap Twice', 'twice@example.com');
  await accept(created.invite.id);
  const first = await bootstrap(created.invite.id, 'Bootstrap Twice');
  check('F replay', 'the first bootstrap succeeds', first.status, '201');
  mintedUserIds.push(first.body.userId);

  const before = await rowCounts('twice@example.com');
  const second = await bootstrap(created.invite.id, 'Bootstrap Twice');
  check('F replay', 'a second bootstrap on the SAME invite is refused', second.status, '409');
  check('F replay', 'reason is already_bootstrapped', second.body?.error, 'already_bootstrapped');
  check('F replay', 'no second token is minted', second.body?.token === undefined, 'true');
  const after = await rowCounts('twice@example.com');
  check('F replay', 'no second app_user row was written', after, before);
}

// ===========================================================================
// G · email_already_registered — the real authentication-bypass boundary.
//     This must refuse outright, not attach a fresh session to the EXISTING
//     account — that would let anyone holding an accepted invite's id sign
//     in as an unrelated, already-registered guardian with no passkey at all.
// ===========================================================================
{
  // Same email as EXISTING_GUARDIAN, different case — citext, proven, not
  // assumed: a naive case-sensitive check would miss this.
  const created = await createGuardianInvite(
    pool, GUARDIAN_A, CHILD_A, 'guardian', 'Collides With Existing', 'existing@example.com');
  await accept(created.invite.id);
  const before = await rowCounts('Existing@Example.com');
  const res = await bootstrap(created.invite.id, 'Should Not Land');
  check('G email collision', 'bootstrap for an already-registered email is refused',
    res.status, '409');
  check('G email collision', 'reason is email_already_registered',
    res.body?.error, 'email_already_registered');
  check('G email collision', 'NO token is minted for the existing account',
    res.body?.token === undefined, 'true');
  const after = await rowCounts('Existing@Example.com');
  check('G email collision', 'still exactly one app_user row for that email '
    + '(no duplicate, no attach)', after, before);
}

// ===========================================================================
// H · no leak into any OTHER route's authorization — two independently
//     bootstrapped sessions hold ZERO guardianship edges (none is created by
//     this route), so both are refused by an edge-gated route against
//     EITHER child, while the one route this pass exists to unlock stays
//     open for each.
// ===========================================================================
{
  const invA = await createGuardianInvite(
    pool, GUARDIAN_A, CHILD_A, 'guardian', 'Leak Check A', 'leak-a@example.com');
  await accept(invA.invite.id);
  const bootA = await bootstrap(invA.invite.id, 'Leak Check A');
  check('H no leak', 'bootstrap A succeeds', bootA.status, '201');
  mintedUserIds.push(bootA.body.userId);
  const tokenA = bootA.body.token;

  const invB = await createGuardianInvite(
    pool, GUARDIAN_A, CHILD_B, 'guardian', 'Leak Check B', 'leak-b@example.com');
  await accept(invB.invite.id);
  const bootB = await bootstrap(invB.invite.id, 'Leak Check B');
  check('H no leak', 'bootstrap B succeeds', bootB.status, '201');
  mintedUserIds.push(bootB.body.userId);

  check('H no leak', 'the two bootstraps mint two DIFFERENT accounts',
    bootA.body.userId === bootB.body.userId, 'false');

  // tokenA against CHILD_A — the very child A's OWN invite named. No
  // guardianship edge exists, so even this is refused.
  const aOnA = await getAvailability(CHILD_A, tokenA);
  check('H no leak', 'token A has no edge even to CHILD A (bootstrap grants no '
    + 'guardianship — a real, separate, still-open gap)', aOnA.status, '403');

  // tokenA against CHILD_B — the cross-child case named explicitly by this
  // task's own security requirement.
  const aOnB = await getAvailability(CHILD_B, tokenA);
  check('H no leak', 'token A cannot reach CHILD B\'s data either', aOnB.status, '403');
  check('H no leak', 'refused for the real reason (no live edge), not a '
    + 'coincidental status', aOnB.body?.error, 'no_edge');

  // The one door this route DOES open stays open, on the SAME token that
  // every child-scoped route above just refused.
  const chalA = await registerChallenge(tokenA);
  check('H no leak', 'the SAME token still completes real webauthn '
    + 'register/challenge (the one thing bootstrap exists to unlock)',
    chalA.status, '200');

  // And the reverse never held either — a session with no token at all
  // still cannot read either child's availability.
  const noTok = await getAvailability(CHILD_A, null);
  check('H no leak', 'no session at all is refused for the real reason',
    noTok.body?.error, 'no_session');
}

// ===========================================================================
// I · THE DB-LEVEL CHECK/UNIQUE constraints — bypassing bootstrapGuardianInvite()
//     entirely via raw admin UPDATEs, mirroring guardian_invite.test.mjs's own
//     "E" section for 0014's own constraint.
// ===========================================================================
{
  // I1 — bootstrap_columns_paired: bootstrapped_at set with NO
  // bootstrap_user_id.
  const fixture1 = await createGuardianInvite(
    pool, GUARDIAN_A, CHILD_A, 'guardian', 'Constraint Pair', 'pair@example.com');
  await accept(fixture1.invite.id);
  let threw1 = false;
  try {
    await admin.query(
      `UPDATE guardian_invite SET bootstrapped_at = now() WHERE id = $1`, [fixture1.invite.id]);
  } catch (e) {
    threw1 = /bootstrap_columns_paired/.test(String(e.message)) || e.code === '23514';
  }
  check('I db constraints', 'bootstrap_columns_paired refuses bootstrapped_at '
    + 'alone, even via a raw admin UPDATE', threw1, 'true');

  // I2 — bootstrap_needs_accept: both columns set together, but accepted_at
  // is NULL.
  const fixture2 = await createGuardianInvite(
    pool, GUARDIAN_A, CHILD_A, 'guardian', 'Constraint Needs Accept', 'needsaccept@example.com');
  let threw2 = false;
  try {
    await admin.query(
      `UPDATE guardian_invite SET bootstrapped_at = now(), bootstrap_user_id = $2 WHERE id = $1`,
      [fixture2.invite.id, GUARDIAN_A]);
  } catch (e) {
    threw2 = /bootstrap_needs_accept/.test(String(e.message)) || e.code === '23514';
  }
  check('I db constraints', 'bootstrap_needs_accept refuses bootstrap on a '
    + 'never-accepted invite, even via a raw admin UPDATE', threw2, 'true');

  // I3 — guardian_invite_bootstrap_user_uidx: two DIFFERENT invites cannot
  // both claim to have produced the SAME app_user row.
  const fixture3a = await createGuardianInvite(
    pool, GUARDIAN_A, CHILD_A, 'guardian', 'Constraint Unique A', 'uniquea@example.com');
  const fixture3b = await createGuardianInvite(
    pool, GUARDIAN_A, CHILD_A, 'guardian', 'Constraint Unique B', 'uniqueb@example.com');
  await accept(fixture3a.invite.id);
  await accept(fixture3b.invite.id);
  await admin.query(
    `UPDATE guardian_invite SET bootstrapped_at = now(), bootstrap_user_id = $2 WHERE id = $1`,
    [fixture3a.invite.id, GUARDIAN_A]);
  let threw3 = false;
  try {
    await admin.query(
      `UPDATE guardian_invite SET bootstrapped_at = now(), bootstrap_user_id = $2 WHERE id = $1`,
      [fixture3b.invite.id, GUARDIAN_A]);
  } catch (e) {
    threw3 = e.code === '23505';
  }
  check('I db constraints', 'guardian_invite_bootstrap_user_uidx refuses a '
    + 'second invite claiming the same app_user row', threw3, 'true');
}

// ---------------------------------------------------------------------------
await admin.query(`DELETE FROM guardian_invite WHERE child_id = ANY($1::uuid[])`,
  [[CHILD_A, CHILD_B]]);
await admin.query(`DELETE FROM child WHERE id = ANY($1::uuid[])`, [[CHILD_A, CHILD_B]]);
await admin.query(`DELETE FROM app_user WHERE id = ANY($1::uuid[])`,
  [[GUARDIAN_A, EXISTING_GUARDIAN, ...mintedUserIds]]);
await admin.end();
await pool.end();

let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
