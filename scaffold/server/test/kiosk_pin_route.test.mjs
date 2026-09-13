/**
 * server/routes.mjs — route contract test: POST
 * /v1/children/:childId/kiosk-pin/verify. MASTERFILE §7.1, §8.1, §8.3.
 * client/lib/lock_controller.dart's guardian-escalation ceremony is what
 * calls this route.
 *
 * Same technique as this directory's own routes.test.mjs (custody-order):
 * the REAL `Api` + `registerRoutes` wiring, driven through `api.handle()`,
 * against a hand-written fake `pg.Pool` — no real Postgres. The difference
 * from that file is WHAT the fake pool has to emulate: this route is
 * `skipOuterSession: true` (it never touches the Api's own caller-scoped
 * `q`), so every bit of its real behavior runs through
 * `packages/db/src/pool.mjs`'s REAL `guardiansOfChild()` and
 * `attemptPinFor()` — imported here unmodified, not reimplemented — against
 * this file's fake pool. `attemptPinFor()` in turn calls the REAL
 * `verifyPin()`/`hashPin()` (packages/auth/src/auth.mjs) against REAL scrypt
 * hashes this file builds with `hashPin()`, so a wrong-PIN or lockout
 * assertion below is proving the actual production code path end to end,
 * not a fake's opinion of what it should do.
 *
 * What this file does NOT re-prove, deliberately, because it is already
 * proven elsewhere against a REAL Postgres connection with REAL row locks:
 *   - The lockout counter/CASE arithmetic itself, and the specific
 *     concurrent-burst row-lock fix (attemptPinFor()'s own header comment,
 *     "Proven live in packages/db/test/auth_credentials.test.mjs's
 *     'F concurrency' section") — that requires real MVCC/locking semantics
 *     a fake pool cannot honestly simulate, so re-asserting it here with a
 *     fake would only be theater.
 *   - `guardiansOfChild()`'s own `effective_guardianship` semantics
 *     (expires_at vs closed_at) — packages/db/test/auth_credentials.test.mjs
 *     and packages/db/test/*  already cover that against real RLS.
 *
 * What WAS actually missing before this file (confirmed by grep across
 * packages/*\/test and server/test): nothing anywhere calls the real
 * kiosk-pin/verify HANDLER through `api.handle()`. `contract.test.mjs`'s own
 * "C A1" section only asserts the route's DECLARED metadata (`action: null`,
 * `identityScopedByHandler: true`) — it never invokes the route, so it
 * cannot catch a regression in the handler's own manual identity check,
 * which is the ONLY thing gating this route: `action: null` means the Api's
 * generic A3 authorization block (api.ts's own `handle()`, the
 * `m.route.action !== null` branch) is skipped entirely for this path, by
 * design (identityScopedByHandler's own doc comment) — so
 * `c.principal.roleName !== 'child' || c.principal.childId !== c.childId`
 * in routes.mjs is the ENTIRE authorization boundary for this route, and
 * until now it had zero direct test coverage. Section A below closes that.
 */
import { randomBytes } from 'node:crypto';
import { issueSession, hashPin } from '../../packages/auth/src/auth.mjs';
import { Api } from '../../packages/api/src/api.mjs';
import { registerRoutes } from '../routes.mjs';

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) }); };

const SECRET = randomBytes(32);
const NOW = Date.parse('2026-08-24T12:00:00Z');

const CHILD_A = 'child-alpha';          // two real, unlocked guardians
const CHILD_B = 'child-beta';           // one LOCKED guardian + one unlocked guardian
const CHILD_NOGUARD = 'child-no-guardians'; // a real child, zero guardians

const MOM_A = 'mom-a', DAD_A = 'dad-a';
const LOCKED_B = 'locked-b', OTHER_B = 'other-b';

// ---- fake "Postgres": just enough of pin_credential + effective_guardianship
// for the REAL guardiansOfChild()/attemptPinFor() (packages/db/src/pool.mjs)
// to run against. Mutable, in-memory, keyed exactly the way the real tables
// are, so the SQL text pool.mjs emits is matched by shape, not paraphrased.
const guardiansByChild = new Map([
  [CHILD_A, [MOM_A, DAD_A]],
  [CHILD_B, [LOCKED_B, OTHER_B]],
  // CHILD_NOGUARD deliberately has no entry -> guardiansOfChild() returns [].
]);
const credentials = new Map(); // userId -> { pin_hash, failed_attempts, locked_until }
const setCred = (userId, pin, { failedAttempts = 0, lockedUntil = null } = {}) => {
  credentials.set(userId, { pin_hash: hashPin(pin), failed_attempts: failedAttempts, locked_until: lockedUntil });
};
setCred(MOM_A, '4242');
setCred(DAD_A, '1357');
setCred(OTHER_B, '2222');
// LOCKED_B's PIN really is '1111' -- the whole point of section E below is
// proving that a correct-but-locked PIN is still refused, and that trying it
// leaves her counter untouched (skipped, not run-and-discarded, per
// attemptPinFor()'s own comment in pool.ts).
setCred(LOCKED_B, '1111', { failedAttempts: 0, lockedUntil: new Date(Date.now() + 999_000_000) });

let guardianLookups = 0;
async function fakeQuery(sql, params = []) {
  if (/^\s*(BEGIN|COMMIT|ROLLBACK)/i.test(sql)) return [];
  if (/set_config/i.test(sql)) return [];
  if (/FROM effective_guardianship WHERE child_id/i.test(sql)) {
    guardianLookups++;
    const [childId] = params;
    return (guardiansByChild.get(childId) ?? []).map((userId) => ({ user_id: userId }));
  }
  if (/SELECT pin_hash, failed_attempts, locked_until\s+FROM pin_credential WHERE user_id = \$1/i.test(sql)) {
    const [userId] = params;
    const c = credentials.get(userId);
    return c ? [{ pin_hash: c.pin_hash, failed_attempts: c.failed_attempts, locked_until: c.locked_until }] : [];
  }
  if (/UPDATE pin_credential SET failed_attempts = 0, locked_until = NULL/i.test(sql) && !/CASE/i.test(sql)) {
    const [userId] = params;
    const c = credentials.get(userId);
    if (c) { c.failed_attempts = 0; c.locked_until = null; }
    return [];
  }
  if (/UPDATE pin_credential[\s\S]*CASE WHEN failed_attempts/i.test(sql)) {
    const [userId, maxAttempts, lockoutMs] = params;
    const c = credentials.get(userId);
    if (c) {
      if (c.failed_attempts + 1 >= maxAttempts) { c.failed_attempts = 0; c.locked_until = new Date(Date.now() + Number(lockoutMs)); }
      else { c.failed_attempts += 1; }
    }
    return [];
  }
  throw new Error(`fake query: unexpected sql: ${sql}`);
}
const pool = {
  connect: async () => ({
    query: async (sql, params = []) => ({ rows: await fakeQuery(sql, params) }),
    release: () => {},
  }),
};

// Fake DbPort for the Api itself. kiosk-pin/verify is `skipOuterSession`, so
// neither of these is ever called FOR THIS ROUTE — kept minimal, same as
// contract.test.mjs's own fakeDb, only so registerRoutes()'s other routes
// (which this file never exercises) can be registered without error.
const db = { edgesFor: async () => [], withSession: async (_p, fn) => fn(async () => []) };

const api = new Api(SECRET, db, () => NOW);
registerRoutes(api, pool);

const childTok = (childId) => issueSession(SECRET, { userId: null, roleName: 'child', childId, escalated: false }, NOW);
const guardianTok = (userId) => issueSession(SECRET, { userId, roleName: 'guardian', childId: null, escalated: false }, NOW);

const path = (childId) => `/v1/children/${childId}/kiosk-pin/verify`;
const hit = (childId, tok, body) => api.handle(
  'POST', path(childId), tok ? { authorization: `Bearer ${tok}` } : {},
  body === undefined ? '' : JSON.stringify(body),
);

// ===========================================================================
// A · the identity boundary — the ENTIRE authz for this route, since
// identityScopedByHandler means api.ts's generic A3 block never runs here.
// ===========================================================================
{
  const res = await hit(CHILD_A, null, { pin: '4242' });
  check('A identity', 'no session -> 401', res.status, 401);

  const asGuardian = await hit(CHILD_A, guardianTok(MOM_A), { pin: '4242' });
  check('A identity', "a GUARDIAN session (even MOM_A's own, even with her own correct PIN) -> 403", asGuardian.status, 403);
  check('A identity', 'reason is not_this_child', asGuardian.body.error, 'not_this_child');

  guardianLookups = 0;
  const wrongChild = await hit(CHILD_B, childTok(CHILD_A), { pin: '1111' });
  check('A identity', "CHILD_A's own session cannot verify a PIN against CHILD_B's kiosk -> 403", wrongChild.status, 403);
  check('A identity', 'reason is not_this_child', wrongChild.body.error, 'not_this_child');
  check('A identity', "CHILD_B's guardians are never even looked up -- refused before any DB access",
    guardianLookups, 0);
}

// ===========================================================================
// B · malformed / missing PIN body — must 400, never 500, never silently
// coerce a non-string into a comparison.
// ===========================================================================
{
  const noBody = await hit(CHILD_A, childTok(CHILD_A), undefined);
  check('B malformed', 'no body at all -> 400 pin_required', noBody.status, 400);
  check('B malformed', 'reason', noBody.body.error, 'pin_required');

  const emptyObj = await hit(CHILD_A, childTok(CHILD_A), {});
  check('B malformed', '{} -> 400 pin_required', emptyObj.status, 400);

  const numberPin = await hit(CHILD_A, childTok(CHILD_A), { pin: 4242 });
  check('B malformed', 'pin as a NUMBER (not a string) -> 400 pin_required', numberPin.status, 400);

  const nullPin = await hit(CHILD_A, childTok(CHILD_A), { pin: null });
  check('B malformed', 'pin: null -> 400 pin_required', nullPin.status, 400);

  const arrayPin = await hit(CHILD_A, childTok(CHILD_A), { pin: ['4242'] });
  check('B malformed', 'pin as an array -> 400 pin_required', arrayPin.status, 400);

  // A real string, just an absurd one -- must NOT throw/500, must fall
  // through to a genuine (failing) match against every real guardian.
  const emptyString = await hit(CHILD_A, childTok(CHILD_A), { pin: '' });
  check('B malformed', "pin: '' -> 200, not a crash", emptyString.status, 200);
  check('B malformed', "pin: '' never matches a real credential", emptyString.body.ok, 'false');
}

// ===========================================================================
// C · the real guardian fan-out, through the real route — every guardian
// gets checked, not just the first one in the list (routes.mjs's own
// comment: "Deliberately NOT short-circuited on the first match").
// ===========================================================================
{
  const momMatch = await hit(CHILD_A, childTok(CHILD_A), { pin: '4242' });
  check('C fan-out', "MOM_A's real PIN (first guardian) -> ok:true", momMatch.body.ok, 'true');

  const dadMatch = await hit(CHILD_A, childTok(CHILD_A), { pin: '1357' });
  check('C fan-out', "DAD_A's real PIN (SECOND guardian) also -> ok:true "
    + '-- proves the loop does not stop after the first guardian mismatches', dadMatch.body.ok, 'true');

  const noMatch = await hit(CHILD_A, childTok(CHILD_A), { pin: '0000' });
  check('C fan-out', 'a PIN matching neither guardian -> ok:false', noMatch.body.ok, 'false');
}

// ===========================================================================
// D · a real child with zero guardians -- must resolve to ok:false, not an
// exception/500 (an empty array from guardiansOfChild() must not be treated
// as "nothing to loop over, so throw" or "vacuously true").
// ===========================================================================
{
  const res = await hit(CHILD_NOGUARD, childTok(CHILD_NOGUARD), { pin: '4242' });
  check('D no guardians', 'a child with no guardians at all -> 200, not 500', res.status, 200);
  check('D no guardians', 'ok:false, never true', res.body.ok, 'false');
}

// ===========================================================================
// E · a LOCKED guardian mixed with an unlocked one -- the real fan-out
// property under mixed lock state, never previously proven through the
// route (auth_credentials.test.mjs's own "B lockout" ceremony proof
// re-implements this loop IN THE TEST rather than calling routes.mjs).
// ===========================================================================
{
  const beforeAttempts = credentials.get(LOCKED_B).failed_attempts;
  const lockedButRight = await hit(CHILD_B, childTok(CHILD_B), { pin: '1111' });
  check('E mixed lock', "LOCKED_B's OWN correct PIN, while locked -> ok:false "
    + '(her scrypt check is skipped entirely, not run-and-discarded)', lockedButRight.body.ok, 'false');
  check('E mixed lock', "trying it does not touch her failed_attempts counter "
    + '(skipped means skipped, not silently recorded as a fresh failure)',
    credentials.get(LOCKED_B).failed_attempts, beforeAttempts);

  const otherUnlockedMatch = await hit(CHILD_B, childTok(CHILD_B), { pin: '2222' });
  check('E mixed lock', "OTHER_B's real, unlocked PIN still -> ok:true even though "
    + 'CHILD_B has a locked sibling guardian in the same fan-out', otherUnlockedMatch.body.ok, 'true');
}

// ===========================================================================
// F · response-shape indistinguishability (routes.mjs's own documented
// security property: "Same shape whether the PIN was wrong, no guardian has
// one set yet, or every guardian is currently locked out").
// ===========================================================================
{
  const wrongPinKeys = Object.keys((await hit(CHILD_A, childTok(CHILD_A), { pin: '0000' })).body).sort();
  const noGuardianKeys = Object.keys((await hit(CHILD_NOGUARD, childTok(CHILD_NOGUARD), { pin: '0000' })).body).sort();
  const lockedKeys = Object.keys((await hit(CHILD_B, childTok(CHILD_B), { pin: '1111' })).body).sort();
  check('F shape', 'wrong-PIN response body is exactly {ok}', JSON.stringify(wrongPinKeys), JSON.stringify(['ok']));
  check('F shape', 'no-guardians response body is exactly {ok}, same shape', JSON.stringify(noGuardianKeys), JSON.stringify(['ok']));
  check('F shape', 'locked-guardian response body is exactly {ok}, same shape too', JSON.stringify(lockedKeys), JSON.stringify(['ok']));
}

// ---------------------------------------------------------------------------
let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
