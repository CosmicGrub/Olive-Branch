/**
 * server/routes.mjs — POST /v1/children/:childId/guardianships, the actual
 * guardian-invite CREATION route. MASTERFILE §11, §8.5.
 *
 * A recent audit flagged "guardian-invite creation" as thin/missing test
 * coverage (Tier-3). That finding is real: packages/db/test/guardian_invite.test.mjs
 * and packages/api/test/guardian_bootstrap_route.test.mjs together exercise
 * createGuardianInvite()/getGuardianInvite()/acceptGuardianInvite()/
 * revokeGuardianInvite()/bootstrapGuardianInvite() thoroughly, and
 * packages/api/test/contract.test.mjs checks this route's registration
 * METADATA (action:null, identityScopedByHandler:true) — but nothing
 * anywhere had ever driven a real HTTP request through THIS route, the one
 * a real inviting guardian's client actually calls. In particular, the
 * route's own "first lock" (routes.mjs's own name for it) — the hand-rolled
 * edgesFor() scan that decides who is allowed to invite at all — had zero
 * coverage: not the child_cannot_invite branch, not not_a_guardian_of_child,
 * not one of the restricted/closed/expired edge shapes edgesFor()'s own
 * doc comment says it deliberately returns and trusts the caller to filter,
 * and not the "different child" case this task names explicitly. Nor did
 * the route's own body validation (invalid_role/label_required/
 * invited_email_required) ever run over real HTTP.
 *
 * Six sections:
 *   A. SUCCESS — a live, unrestricted guardian of the child creates a real,
 *      persisted invite; the response and the row it produced both checked.
 *   B. AUTHORIZATION — the "first lock", every shape edgesFor() can return:
 *      no session, a child session, no edge at all, an edge to a DIFFERENT
 *      child only (this task's own named case), a restricted edge, a closed
 *      edge, an expired edge, and an edge that is live but the WRONG role
 *      (trusted_adult, not guardian) — eight real refusals, none tested
 *      before this file.
 *   C. VALIDATION — the route's own body checks, run before the DB is ever
 *      touched: invalid_role, label_required, invited_email_required.
 *   D. DUPLICATE / COEXISTENCE — two real product-behavior gaps the audit
 *      named and nothing tested: inviting an email that is ALREADY a live
 *      guardian of the same child (succeeds — no such check exists in
 *      routes.mjs or createGuardianInvite()), and inviting the SAME email
 *      twice for the same child (the second call does not supersede or
 *      refuse the first — both invites coexist as independently addressable
 *      rows). Documented here as the real, current behavior, not asserted
 *      to be correct or incorrect.
 *   E. RLS vs APPLICATION BOUNDARY — this task's own named question, "does
 *      a guardian of a DIFFERENT child get refused?", answered at BOTH
 *      layers rather than assumed from one: (E1) yes, over the real HTTP
 *      route, by the application-level edgesFor() check in B4. (E2) NO, if
 *      that check is bypassed and createGuardianInvite() is called
 *      directly — guardian_invite's RLS policy
 *      (`invited_by = current_actor()`, db/migrations/0014) has no child_id
 *      clause at all, unlike revokeGuardianInvite()'s ownership check
 *      (packages/db/test/guardian_invite.test.mjs's own "D" section), so
 *      RLS provides NO defense-in-depth for child-scoping on invite
 *      creation — routes.mjs's own B4 check is the ONLY lock. Proven
 *      empirically here, not inferred from the migration's comments alone.
 */
import pg from 'pg';
import { randomUUID, randomBytes } from 'node:crypto';
import { Api } from '../src/api.mjs';
import { createPool, dbPort, createGuardianInvite, getGuardianInvite } from '../../db/src/pool.mjs';
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
const GUARDIAN_A = randomUUID();          // live, unrestricted guardian of CHILD_A — the positive control
const CO_GUARDIAN_A = randomUUID();       // a SECOND live guardian of CHILD_A, with a known email (for D1)
const GUARDIAN_B_ONLY = randomUUID();     // live guardian of CHILD_B ONLY — the "different child" negative control
const GUARDIAN_NO_EDGE = randomUUID();    // a real account, zero guardianship rows anywhere
const GUARDIAN_RESTRICTED = randomUUID(); // live edge to CHILD_A, but restricted = true (protective order)
const GUARDIAN_CLOSED = randomUUID();     // edge to CHILD_A that is closed
const GUARDIAN_EXPIRED = randomUUID();    // edge to CHILD_A that has already expired
const GUARDIAN_WRONG_ROLE = randomUUID(); // live edge to CHILD_A, but role = trusted_adult, not guardian

await admin.query('BEGIN');
await admin.query(
  `INSERT INTO app_user (id, display_name, home_tz, email) VALUES
     ($1,'Guardian A (inviting)','America/Chicago', NULL),
     ($2,'Co-Guardian (already on the child)','America/Chicago','coguardian@example.com'),
     ($3,'Guardian B (different child only)','America/New_York', NULL),
     ($4,'No Edge At All','America/Denver', NULL),
     ($5,'Restricted Guardian','America/Chicago', NULL),
     ($6,'Closed Guardian','America/Chicago', NULL),
     ($7,'Expired Guardian','America/Chicago', NULL),
     ($8,'Wrong Role Guardian','America/Chicago', NULL)`,
  [GUARDIAN_A, CO_GUARDIAN_A, GUARDIAN_B_ONLY, GUARDIAN_NO_EDGE,
   GUARDIAN_RESTRICTED, GUARDIAN_CLOSED, GUARDIAN_EXPIRED, GUARDIAN_WRONG_ROLE]);
await admin.query(
  `INSERT INTO child (id, display_name, birth_date, home_tz) VALUES
     ($1,'Wren','2017-06-11','America/New_York'),
     ($2,'Otis','2019-02-03','America/Los_Angeles')`,
  [CHILD_A, CHILD_B]);
await admin.query(
  `INSERT INTO guardianship (child_id, user_id, role, scope, valid) VALUES
     ($1, $2, 'guardian', '{}', tstzrange(now() - interval '1 year', null)),
     ($1, $3, 'guardian', '{}', tstzrange(now() - interval '1 year', null)),
     ($4, $5, 'guardian', '{}', tstzrange(now() - interval '1 year', null))`,
  [CHILD_A, GUARDIAN_A, CO_GUARDIAN_A, CHILD_B, GUARDIAN_B_ONLY]);
await admin.query(
  `INSERT INTO guardianship (child_id, user_id, role, scope, valid, restricted) VALUES
     ($1, $2, 'guardian', '{}', tstzrange(now() - interval '1 year', null), true)`,
  [CHILD_A, GUARDIAN_RESTRICTED]);
await admin.query(
  `INSERT INTO guardianship
     (child_id, user_id, role, scope, valid, closed_at, closed_reason) VALUES
     ($1, $2, 'guardian', '{}', tstzrange(now() - interval '1 year', now() - interval '1 day'),
      now() - interval '1 day', 'revoked')`,
  [CHILD_A, GUARDIAN_CLOSED]);
await admin.query(
  `INSERT INTO guardianship (child_id, user_id, role, scope, valid, expires_at) VALUES
     ($1, $2, 'guardian', '{}', tstzrange(now() - interval '1 year', null), now() - interval '1 day')`,
  [CHILD_A, GUARDIAN_EXPIRED]);
await admin.query(
  `INSERT INTO guardianship (child_id, user_id, role, scope, valid) VALUES
     ($1, $2, 'trusted_adult', '{}', tstzrange(now() - interval '1 year', null))`,
  [CHILD_A, GUARDIAN_WRONG_ROLE]);
await admin.query('COMMIT');

const SECRET = Buffer.from('c'.repeat(32), 'utf8');
const NOW = Date.now();
const api = new Api(SECRET, dbPort(pool), () => NOW);
registerRoutes(api, pool);

const guardianTok = (userId) => issueSession(
  SECRET, { userId, roleName: 'guardian', childId: null, escalated: false }, NOW);
const childTok = (childId) => issueSession(
  SECRET, { userId: null, roleName: 'child', childId, escalated: false }, NOW);

const invite = (childId, tok, payload) => api.handle(
  'POST', `/v1/children/${childId}/guardianships`,
  tok ? { authorization: `Bearer ${tok}` } : {},
  payload === undefined ? '' : JSON.stringify(payload));

const VALID_BODY = { role: 'sitter', label: 'Sitter Sam', invitedEmail: 'sam@example.com' };

// ===========================================================================
// A · SUCCESS — a live, unrestricted guardian of the child, over real HTTP
// ===========================================================================
{
  const res = await invite(CHILD_A, guardianTok(GUARDIAN_A),
    { role: 'trusted_adult', label: 'Aunt Jo', invitedEmail: 'aunt-jo@example.com' });
  check('A success', 'a live guardian of the child gets 201', res.status, '201');
  check('A success', 'response carries ok:true', res.body?.ok, 'true');
  check('A success', 'the invite names the right child', res.body?.invite?.childId, CHILD_A);
  check('A success', 'the invite names the inviting guardian', res.body?.invite?.invitedBy, GUARDIAN_A);
  check('A success', 'role round-trips', res.body?.invite?.role, 'trusted_adult');
  check('A success', 'label round-trips', res.body?.invite?.label, 'Aunt Jo');
  check('A success', 'invitedEmail round-trips', res.body?.invite?.invitedEmail, 'aunt-jo@example.com');
  check('A success', 'starts unaccepted', res.body?.invite?.acceptedAt, 'null');

  // Not just a response shape — a real row a stranger-facing route can find.
  const found = await getGuardianInvite(pool, res.body.invite.id);
  check('A success', 'the invite the route reports is really persisted', found?.id, res.body.invite.id);
  check('A success', 'persisted label matches what the route returned', found?.label, 'Aunt Jo');
}

// ===========================================================================
// B · AUTHORIZATION — the "first lock", every real shape, none tested before
// ===========================================================================
{
  const noSession = await invite(CHILD_A, null, VALID_BODY);
  check('B1 no session', 'no Authorization header at all is refused', noSession.status, '401');
  check('B1 no session', 'refused for the real reason', noSession.body?.error, 'no_session');

  const childSession = await invite(CHILD_A, childTok(CHILD_A), VALID_BODY);
  check('B2 child session', 'a child session cannot invite — even for herself', childSession.status, '403');
  check('B2 child session', 'refused for the real reason', childSession.body?.error, 'child_cannot_invite');

  const noEdge = await invite(CHILD_A, guardianTok(GUARDIAN_NO_EDGE), VALID_BODY);
  check('B3 no edge', 'a real account with ZERO guardianship rows anywhere is refused', noEdge.status, '403');
  check('B3 no edge', 'refused for the real reason', noEdge.body?.error, 'not_a_guardian_of_child');

  // The exact case this task names: a guardian of a DIFFERENT child, asked
  // to invite for a child they do not guard.
  const differentChild = await invite(CHILD_A, guardianTok(GUARDIAN_B_ONLY), VALID_BODY);
  check('B4 different child', 'a guardian of a DIFFERENT child only is refused', differentChild.status, '403');
  check('B4 different child', 'refused for the real reason, not a coincidental 403',
    differentChild.body?.error, 'not_a_guardian_of_child');
  // And the mirror: that SAME guardian can invite for the child they DO guard.
  const ownChild = await invite(CHILD_B, guardianTok(GUARDIAN_B_ONLY),
    { role: 'sitter', label: 'For Otis', invitedEmail: 'otis-sitter@example.com' });
  check('B4 different child', 'and succeeds for their OWN child', ownChild.status, '201');

  const restricted = await invite(CHILD_A, guardianTok(GUARDIAN_RESTRICTED), VALID_BODY);
  check('B5 restricted edge', 'a restricted (protective-order) edge cannot invite', restricted.status, '403');
  check('B5 restricted edge', 'refused for the real reason', restricted.body?.error, 'not_a_guardian_of_child');

  const closed = await invite(CHILD_A, guardianTok(GUARDIAN_CLOSED), VALID_BODY);
  check('B6 closed edge', 'a closed edge cannot invite', closed.status, '403');
  check('B6 closed edge', 'refused for the real reason', closed.body?.error, 'not_a_guardian_of_child');

  const expired = await invite(CHILD_A, guardianTok(GUARDIAN_EXPIRED), VALID_BODY);
  check('B7 expired edge', 'an expired edge cannot invite', expired.status, '403');
  check('B7 expired edge', 'refused for the real reason', expired.body?.error, 'not_a_guardian_of_child');

  // A live, unrestricted, unexpired edge — but the WRONG role. edgesFor()
  // returns it (it is a real edge); the route's own e.role === 'guardian'
  // check is what refuses it, not edgesFor() filtering it out already.
  const wrongRole = await invite(CHILD_A, guardianTok(GUARDIAN_WRONG_ROLE), VALID_BODY);
  check('B8 wrong role', 'a live trusted_adult edge (not guardian) cannot invite', wrongRole.status, '403');
  check('B8 wrong role', 'refused for the real reason', wrongRole.body?.error, 'not_a_guardian_of_child');
}

// ===========================================================================
// C · VALIDATION — the route's own body checks, ahead of the DB
// ===========================================================================
{
  const badRole = await invite(CHILD_A, guardianTok(GUARDIAN_A),
    { role: 'not_a_real_role', label: 'X', invitedEmail: 'x@example.com' });
  check('C1 invalid role', 'an unrecognized role is refused', badRole.status, '400');
  check('C1 invalid role', 'refused for the real reason', badRole.body?.error, 'invalid_role');

  const missingLabel = await invite(CHILD_A, guardianTok(GUARDIAN_A),
    { role: 'sitter', invitedEmail: 'nolabel@example.com' });
  check('C2 missing label', 'a missing label is refused', missingLabel.status, '400');
  check('C2 missing label', 'refused for the real reason', missingLabel.body?.error, 'label_required');

  const blankLabel = await invite(CHILD_A, guardianTok(GUARDIAN_A),
    { role: 'sitter', label: '   ', invitedEmail: 'blanklabel@example.com' });
  check('C2 missing label', 'a whitespace-only label is refused the same way', blankLabel.status, '400');
  check('C2 missing label', 'refused for the real reason', blankLabel.body?.error, 'label_required');

  const missingEmail = await invite(CHILD_A, guardianTok(GUARDIAN_A), { role: 'sitter', label: 'No Email' });
  check('C3 missing email', 'a missing invitedEmail is refused', missingEmail.status, '400');
  check('C3 missing email', 'refused for the real reason', missingEmail.body?.error, 'invited_email_required');

  const badEmail = await invite(CHILD_A, guardianTok(GUARDIAN_A),
    { role: 'sitter', label: 'Bad Email', invitedEmail: 'not-an-email' });
  check('C3 missing email', 'an invitedEmail with no @ is refused the same way', badEmail.status, '400');
  check('C3 missing email', 'refused for the real reason', badEmail.body?.error, 'invited_email_required');

  const emptyBody = await invite(CHILD_A, guardianTok(GUARDIAN_A), {});
  check('C4 empty body', 'an empty body is refused (role checked first)', emptyBody.status, '400');
  check('C4 empty body', 'reports invalid_role, the first check the route makes', emptyBody.body?.error, 'invalid_role');
}

// ===========================================================================
// D · DUPLICATE / COEXISTENCE — real, previously-undocumented behavior
// ===========================================================================
{
  // D1 — the invited email already belongs to a LIVE guardian of this SAME
  // child. No check anywhere (routes.mjs's own validation block, or
  // createGuardianInvite()) refuses this — it succeeds.
  const alreadyGuardian = await invite(CHILD_A, guardianTok(GUARDIAN_A),
    { role: 'guardian', label: 'Redundant Invite', invitedEmail: 'coguardian@example.com' });
  check('D1 already-a-guardian', 'inviting an email that already guards this SAME child '
    + 'is NOT refused — no such check exists', alreadyGuardian.status, '201');
  check('D1 already-a-guardian', 'a real, independent invite row is created anyway',
    typeof alreadyGuardian.body?.invite?.id === 'string' && alreadyGuardian.body.invite.id.length > 0, 'true');

  // D2 — the SAME email invited TWICE for the SAME child. The second call
  // does not supersede, merge with, or refuse the first: both coexist as
  // independently addressable rows.
  const first = await invite(CHILD_A, guardianTok(GUARDIAN_A),
    { role: 'sitter', label: 'First Invite', invitedEmail: 'twice-invited@example.com' });
  const second = await invite(CHILD_A, guardianTok(GUARDIAN_A),
    { role: 'coordinator', label: 'Second Invite (same email)', invitedEmail: 'twice-invited@example.com' });
  check('D2 same email twice', 'the first invite succeeds', first.status, '201');
  check('D2 same email twice', 'a second invite to the SAME email is NOT refused '
    + 'as a duplicate', second.status, '201');
  check('D2 same email twice', 'the two invites are genuinely DIFFERENT rows, not the same one echoed back',
    first.body.invite.id === second.body.invite.id, 'false');

  const stillThereFirst = await getGuardianInvite(pool, first.body.invite.id);
  const stillThereSecond = await getGuardianInvite(pool, second.body.invite.id);
  check('D2 same email twice', 'the FIRST invite still exists, untouched by the second',
    stillThereFirst?.label, 'First Invite');
  check('D2 same email twice', 'the SECOND invite also exists, independently',
    stillThereSecond?.label, 'Second Invite (same email)');
  check('D2 same email twice', 'both target the same real invited email',
    `${stillThereFirst?.invitedEmail}/${stillThereSecond?.invitedEmail}`,
    'twice-invited@example.com/twice-invited@example.com');

  const dupeCount = await admin.query(
    `SELECT count(*)::int AS n FROM guardian_invite WHERE child_id = $1 AND invited_email = $2`,
    [CHILD_A, 'twice-invited@example.com']);
  check('D2 same email twice', 'the database really holds both rows, not one row '
    + 'silently updated in place', dupeCount.rows[0].n, 2);
}

// ===========================================================================
// E · RLS vs APPLICATION BOUNDARY — "does a guardian of a DIFFERENT child
//     get refused?", answered at both layers
// ===========================================================================
{
  // E1 — restates B4's headline result as its own named assertion: over the
  // real route, yes, refused.
  const viaRoute = await invite(CHILD_A, guardianTok(GUARDIAN_B_ONLY), VALID_BODY);
  check('E1 via route', 'the real HTTP route refuses a different-child guardian', viaRoute.status, '403');

  // E2 — the SAME caller, the SAME cross-child attempt, but calling
  // createGuardianInvite() directly, bypassing routes.mjs's edgesFor()
  // check entirely (exactly what would happen if any future caller reused
  // this function without redoing that check — pool.ts's own doc comment on
  // createGuardianInvite() says outright it "trusts the caller" to have
  // already confirmed this). guardian_invite's RLS policy (0014) is
  // `USING/WITH CHECK (invited_by = current_actor())` — no child_id clause.
  // If RLS provided real defense-in-depth here the way it does for
  // revokeGuardianInvite()'s ownership check, this would fail too. It does
  // not: this proves the ENTIRE authorization for "which child" lives in
  // the route's application code, not the database.
  const viaPoolDirect = await createGuardianInvite(
    pool, GUARDIAN_B_ONLY, CHILD_A, 'sitter', 'Bypassing The Route', 'bypass@example.com');
  check('E2 via pool direct (RLS only)', 'RLS ALONE does not stop a guardian of a '
    + 'different child from creating an invite for it — the route\'s application-level '
    + 'check is the ONLY lock (no defense-in-depth here, unlike revoke)',
    viaPoolDirect.ok, 'true');
  check('E2 via pool direct (RLS only)', 'and a real, wrong-child-scoped row actually lands',
    viaPoolDirect.invite?.childId, CHILD_A);
}

// ---------------------------------------------------------------------------
await admin.query(`DELETE FROM guardian_invite WHERE child_id = ANY($1::uuid[])`, [[CHILD_A, CHILD_B]]);
await admin.query(`DELETE FROM guardianship WHERE child_id = ANY($1::uuid[])`, [[CHILD_A, CHILD_B]]);
await admin.query(`DELETE FROM child WHERE id = ANY($1::uuid[])`, [[CHILD_A, CHILD_B]]);
await admin.query(`DELETE FROM app_user WHERE id = ANY($1::uuid[])`,
  [[GUARDIAN_A, CO_GUARDIAN_A, GUARDIAN_B_ONLY, GUARDIAN_NO_EDGE,
    GUARDIAN_RESTRICTED, GUARDIAN_CLOSED, GUARDIAN_EXPIRED, GUARDIAN_WRONG_ROLE]]);
await admin.end();
await pool.end();

let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
