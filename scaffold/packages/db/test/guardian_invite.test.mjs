/**
 * packages/db — guardian invitation: real Postgres, real RLS.
 * MASTERFILE §11, §8.5. db/migrations/0014_guardian_invite.sql and
 * packages/db/src/pool.ts's createGuardianInvite()/getGuardianInvite()/
 * acceptGuardianInvite()/revokeGuardianInvite() are what make this real.
 *
 * Same posture as deletion.test.mjs / pool.test.mjs, which this suite
 * mirrors: requires a real Postgres with 0014 applied, DATABASE_URL MUST be
 * a NOSUPERUSER NOBYPASSRLS role (db/DEPLOYMENT.md's app_owner) — a probe of
 * RLS run as `postgres` measures nothing.
 *
 * Seven sections:
 *   A. create — a real row lands, scoped correctly
 *   B. read — getGuardianInvite() finds a real invite by id, and honestly
 *      returns null for one that never existed
 *   C. accept — success, then idempotency (already_accepted), then a
 *      genuinely expired invite refused, then a revoked one refused
 *   D. revoke — only the inviting guardian can revoke; a different
 *      guardian's attempt is indistinguishable from not_found (RLS, not app
 *      logic, is what makes that true — proven by querying AS guardian B and
 *      finding zero rows, not by trusting revokeGuardianInvite()'s own
 *      return value alone)
 *   E. the DB-level CHECK — accepted_at and revoked_at can never both be set,
 *      even via a raw admin UPDATE that bypasses every function above
 *   F. health_check's rls_unforced — guardian_invite reports 0, proving
 *      FORCE ROW LEVEL SECURITY actually took
 *   G. THE REAL HTTP ROUTE, no session — added post-merge after an
 *      adversarial audit found A-F above all call pool.mjs functions
 *      directly, bypassing api.handle() entirely, so nothing anywhere had
 *      ever proven the actual HTTP route an unauthenticated invited party
 *      calls (GET .../accept sending no Authorization header, matching
 *      api_client.dart's own fetchGuardianInvite()/acceptGuardianInvite())
 *      was reachable. It was not: api.handle() 401'd both, unconditionally,
 *      before noSessionRequired existed (see api.ts's own doc comment on
 *      that fix). This section drives the REAL Api + registerRoutes wiring
 *      against this same real Postgres — the route layer AND the query
 *      layer together, which is exactly the boundary the bug lived on.
 */
import pg from 'pg';
import { randomUUID, randomBytes } from 'node:crypto';
import { createPool, createGuardianInvite, getGuardianInvite,
  acceptGuardianInvite, revokeGuardianInvite, withSession, dbPort } from '../src/pool.mjs';
import { Api } from '../../api/src/api.mjs';
import { registerRoutes } from '../../../server/routes.mjs';

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

// Fresh random ids every run — same reasoning deletion.test.mjs's own header
// gives: message_log's append-only trigger and this suite's own fixtures
// would otherwise collide or silently accumulate across runs.
const CHILD = randomUUID();
const GUARDIAN_A = randomUUID(); // the one inviting
const GUARDIAN_B = randomUUID(); // a co-parent, RLS negative control

await admin.query('BEGIN');
await admin.query(
  `INSERT INTO app_user (id, display_name, home_tz) VALUES
     ($1,'Guardian A (inviting)','America/Chicago'),
     ($2,'Guardian B (co-parent)','America/New_York')`,
  [GUARDIAN_A, GUARDIAN_B]);
await admin.query(
  `INSERT INTO child (id, display_name, birth_date, home_tz) VALUES
     ($1,'Wren','2017-06-11','America/New_York')`, [CHILD]);
await admin.query(
  `INSERT INTO guardianship (child_id, user_id, role, scope, valid) VALUES
     ($1, $2, 'guardian', '{}', tstzrange(now() - interval '1 year', null))`,
  [CHILD, GUARDIAN_A]);
await admin.query('COMMIT');

// A · CREATE — a real row lands, scoped correctly
{
  const r = await createGuardianInvite(
    pool, GUARDIAN_A, CHILD, 'step_parent', 'Baba', 'baba@example.com');
  check('A create', 'a real invite is created', r.ok, 'true');
  check('A create', 'child_id is exactly the one asked for', r.invite.childId, CHILD);
  check('A create', 'invited_by is the calling guardian', r.invite.invitedBy, GUARDIAN_A);
  check('A create', 'role round-trips', r.invite.role, 'step_parent');
  check('A create', 'label round-trips (her own word, not a hard-coded one)', r.invite.label, 'Baba');
  check('A create', 'starts unaccepted', r.invite.acceptedAt, 'null');
  check('A create', 'starts unrevoked', r.invite.revokedAt, 'null');
  check('A create', 'expires roughly 14 days out',
    Math.round((new Date(r.invite.expiresAt) - new Date(r.invite.createdAt)) / 86400000), 14);

  const bad = await createGuardianInvite(
    pool, GUARDIAN_A, CHILD, 'not_a_real_role', 'X', 'x@example.com');
  check('A create', 'an invalid role is refused, not silently coerced', bad.ok, 'false');
  check('A create', 'refusal reason is invalid_role', bad.reason, 'invalid_role');
}

// B · READ — found, and an honest null for one that never existed
let liveInviteId;
{
  const created = await createGuardianInvite(
    pool, GUARDIAN_A, CHILD, 'trusted_adult', 'Aunt Jo', 'jo@example.com');
  liveInviteId = created.invite.id;

  const found = await getGuardianInvite(pool, liveInviteId);
  check('B read', 'a real invite is found by id', found?.id, liveInviteId);
  check('B read', 'label survives the round trip', found?.label, 'Aunt Jo');

  const missing = await getGuardianInvite(pool, randomUUID());
  check('B read', 'a never-existed id returns null, not a throw', missing, 'null');
}

// C · ACCEPT — success, idempotency, expiry, and a revoked invite refused
{
  const toAccept = await createGuardianInvite(
    pool, GUARDIAN_A, CHILD, 'sitter', 'Sitter Sam', 'sam@example.com');
  const now = new Date();

  const ok = await acceptGuardianInvite(pool, toAccept.invite.id, now);
  check('C accept', 'a live invite is accepted', ok.ok, 'true');
  check('C accept', 'accepted_at is set', ok.invite.acceptedAt !== null, 'true');

  const again = await acceptGuardianInvite(pool, toAccept.invite.id, now);
  check('C accept', 'accepting twice is refused, not silently repeated', again.ok, 'false');
  check('C accept', 'refusal reason is already_accepted', again.reason, 'already_accepted');

  const notFound = await acceptGuardianInvite(pool, randomUUID(), now);
  check('C accept', 'accepting a never-existed id is refused', notFound.ok, 'false');
  check('C accept', 'refusal reason is not_found', notFound.reason, 'not_found');

  // A genuinely expired invite: backdate expires_at directly (createGuardianInvite
  // has no way to create one pre-expired, on purpose — the DEFAULT is always
  // 14 days out, so this reaches past the function to prove acceptGuardianInvite()
  // itself, not just the default, is what refuses it).
  const toExpire = await createGuardianInvite(
    pool, GUARDIAN_A, CHILD, 'coordinator', 'Coordinator Cam', 'cam@example.com');
  await admin.query(
    `UPDATE guardian_invite SET expires_at = now() - interval '1 day' WHERE id = $1`,
    [toExpire.invite.id]);
  const expired = await acceptGuardianInvite(pool, toExpire.invite.id, now);
  check('C accept', 'an expired invite is refused', expired.ok, 'false');
  check('C accept', 'refusal reason is expired', expired.reason, 'expired');

  const toRevokeThenAccept = await createGuardianInvite(
    pool, GUARDIAN_A, CHILD, 'guardian', 'Guardian G', 'g@example.com');
  await revokeGuardianInvite(pool, toRevokeThenAccept.invite.id, GUARDIAN_A, now);
  const revokedThenAccepted = await acceptGuardianInvite(pool, toRevokeThenAccept.invite.id, now);
  check('C accept', 'a revoked invite cannot then be accepted', revokedThenAccepted.ok, 'false');
  check('C accept', 'refusal reason is revoked', revokedThenAccepted.reason, 'revoked');
}

// D · REVOKE — only the inviting guardian can, and RLS (not app logic
// alone) is what makes a stranger's attempt indistinguishable from not_found
{
  const now = new Date();
  const toRevoke = await createGuardianInvite(
    pool, GUARDIAN_A, CHILD, 'guardian', 'Revoke Me', 'revokeme@example.com');

  // GUARDIAN_B (not the inviter) tries to revoke A's invite.
  const wrongGuardian = await revokeGuardianInvite(pool, toRevoke.invite.id, GUARDIAN_B, now);
  check('D revoke', 'a non-owning guardian\'s attempt is refused', wrongGuardian.ok, 'false');
  check('D revoke', 'refused as not_found — RLS hides the row, not an app-level check',
    wrongGuardian.reason, 'not_found');

  // Prove it is RLS, not revokeGuardianInvite()'s own logic: query the row
  // directly under GUARDIAN_B's own session and confirm RLS returns nothing.
  const bRows = await withSession(pool, { roleName: 'guardian', userId: GUARDIAN_B, childId: null },
    (q) => q(`SELECT id FROM guardian_invite WHERE id = $1`, [toRevoke.invite.id]));
  check('D revoke', 'GUARDIAN_B\'s own session genuinely cannot see the row at all',
    bRows.length, 0);

  // GUARDIAN_A (the real owner) still can.
  const rightGuardian = await revokeGuardianInvite(pool, toRevoke.invite.id, GUARDIAN_A, now);
  check('D revoke', 'the owning guardian succeeds', rightGuardian.ok, 'true');
  const afterRevoke = await getGuardianInvite(pool, toRevoke.invite.id);
  check('D revoke', 'revoked_at is actually set', afterRevoke.revokedAt !== null, 'true');

  const toAcceptFirst = await createGuardianInvite(
    pool, GUARDIAN_A, CHILD, 'guardian', 'Already Accepted', 'aa@example.com');
  await acceptGuardianInvite(pool, toAcceptFirst.invite.id, now);
  const revokeAfterAccept = await revokeGuardianInvite(pool, toAcceptFirst.invite.id, GUARDIAN_A, now);
  check('D revoke', 'an already-accepted invite cannot then be revoked', revokeAfterAccept.ok, 'false');
  check('D revoke', 'refusal reason is already_accepted', revokeAfterAccept.reason, 'already_accepted');
}

// E · THE DB-LEVEL CHECK — accepted_at/revoked_at can never both be set,
// even bypassing every function above via a raw admin UPDATE.
{
  const fixture = await createGuardianInvite(
    pool, GUARDIAN_A, CHILD, 'guardian', 'Constraint Check', 'cc@example.com');
  await admin.query(
    `UPDATE guardian_invite SET accepted_at = now() WHERE id = $1`, [fixture.invite.id]);
  let threw = false;
  try {
    await admin.query(
      `UPDATE guardian_invite SET revoked_at = now() WHERE id = $1`, [fixture.invite.id]);
  } catch (e) {
    threw = /invite_not_both_accepted_and_revoked/.test(String(e.message)) ||
            e.code === '23514'; // check_violation
  }
  check('E db check', 'the CHECK constraint itself refuses accepted+revoked, '
    + 'not just application code', threw, 'true');
}

// F · health_check's rls_unforced — guardian_invite is actually monitored
{
  const r = await admin.query(
    `SELECT observed FROM health_check WHERE check_name = 'rls_unforced'`);
  check('F health', 'rls_unforced reports zero unforced tables '
    + '(guardian_invite genuinely has FORCE ROW LEVEL SECURITY)', r.rows[0]?.observed, '0');
}

// G · THE REAL HTTP ROUTE — no session, exactly as an invited party (or
// api_client.dart's own fetchGuardianInvite()/acceptGuardianInvite(), which
// send no Authorization header on purpose) actually calls it. This is the
// section that would have failed loudly before the noSessionRequired fix:
// api.handle() 401'd both routes unconditionally, before ever reaching
// getGuardianInvite()/acceptGuardianInvite() below.
{
  const api = new Api(randomBytes(32), dbPort(pool), () => Date.now());
  registerRoutes(api, pool);

  const created = await createGuardianInvite(
    pool, GUARDIAN_A, CHILD, 'sitter', 'Real HTTP Route Check', 'sitter@example.com');
  const inviteId = created.invite.id;

  // GET, no Authorization header at all.
  const getRes = await api.handle('GET', `/v1/guardian-invites/${inviteId}`, {}, '');
  check('G real route', 'GET with no session reaches the handler (not a 401)',
    getRes.status, '200');
  check('G real route', 'and returns the real invite', getRes.body?.invite?.id, inviteId);

  // POST accept, no Authorization header at all.
  const acceptRes = await api.handle(
    'POST', `/v1/guardian-invites/${inviteId}/accept`, {}, '');
  check('G real route', 'POST accept with no session reaches the handler (not a 401)',
    acceptRes.status, '200');
  check('G real route', 'and the invite is really accepted',
    Boolean(acceptRes.body?.invite?.acceptedAt), 'true');

  // GET on a genuinely nonexistent id still 404s through the same
  // no-session path — the bypass doesn't turn "not found" into something else.
  const missingRes = await api.handle(
    'GET', `/v1/guardian-invites/${randomUUID()}`, {}, '');
  check('G real route', 'GET on a nonexistent id still 404s, not 200 or 401',
    missingRes.status, '404');

  // Control: revoke must NOT have gotten the same bypass — only create/read/
  // accept were ever meant to be reachable without a session; revoke needs
  // the inviting guardian's own real identity (c.principal.userId).
  const secondInvite = await createGuardianInvite(
    pool, GUARDIAN_A, CHILD, 'sitter', 'Revoke Control', 'revoke-control@example.com');
  const revokeRes = await api.handle(
    'POST', `/v1/guardian-invites/${secondInvite.invite.id}/revoke`, {}, '');
  check('G real route', 'POST revoke with no session is correctly still refused',
    revokeRes.status, '401');
  check('G real route', 'refused for the real reason (no_session), not a coincidence',
    revokeRes.body?.error, 'no_session');
}

await admin.end();
await pool.end();

let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
