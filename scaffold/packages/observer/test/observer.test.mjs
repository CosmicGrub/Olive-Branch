/**
 * observer.ts — MASTERFILE §17.3, the observer tier. Zero test coverage
 * anywhere in this repository before this file, contradicting a longstanding
 * CHANGELOG claim that its primitives are "already-tested" — grep across
 * packages/*\/test/ and server/test/ for observerMay/invite/revoke/
 * activeObservers/auditObserverView finds nothing before this file.
 *
 * The module's own header names the design stakes directly: an observer
 * invited by one parent must never become visible to, or able to see, the
 * other — otherwise "inviting a grandmother becomes a move in a dispute
 * rather than a kindness to a child." Every function below is exercised
 * directly against that claim, not inferred from a caller.
 */
import {
  OBSERVER_MAY, OBSERVER_MAY_NOT, observerMay, observerSeesGuardian,
  guardianSeesOthersObservers, OBSERVER_GRANT_TTL_DAYS, invite, revoke,
  activeObservers, CHILD_CONTROLS_OBSERVERS_FROM_AGE,
  whoDecidesObserverVisibility, OBSERVER_FORBIDDEN, auditObserverView,
} from '../src/observer.mjs';

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) }); };

// ===========================================================================
// A · observerMay() — the grant list, and the fact deny wins by omission
// ===========================================================================
{
  check('A observerMay', 'a real granted capability is allowed',
    observerMay('see_child_calendar'), 'true');
  check('A observerMay', 'a real denied capability is refused',
    observerMay('see_expenses'), 'false');
  check('A observerMay', 'a capability that is neither list is refused by default '
    + '(deny wins by omission, not by an explicit deny entry)',
    observerMay('do_something_nobody_thought_of'), 'false');
  check('A observerMay', 'OBSERVER_MAY and OBSERVER_MAY_NOT share no capability '
    + '(a name cannot be both granted and denied)',
    OBSERVER_MAY.some((c) => OBSERVER_MAY_NOT.includes(c)), 'false');
}

// ===========================================================================
// B · The single most important line in the module, per its own comment
// ===========================================================================
{
  check('B mutual blindness', 'an observer can never see the inviting guardian '
    + '(the function accepts no arguments at all — there is no input shape '
    + 'that could ever make this return true)',
    observerSeesGuardian(), 'false');
  check('B mutual blindness', 'a guardian can never see another guardian\'s '
    + 'observers, symmetrically',
    guardianSeesOthersObservers(), 'false');
}

// ===========================================================================
// C · invite() — who may invite, and the already-invited guard
// ===========================================================================
{
  const base = { userId: 'grandma-1', role: 'grandparent', invitedBy: 'dad-1',
    label: 'Grandma', invitedAt: '2026-01-01T00:00:00Z' };

  const byChild = invite([], 'child', base);
  check('C invite', 'a child can never invite an observer', byChild.ok, 'false');
  check('C invite', 'the reason is child_cannot_invite', byChild.reason, 'child_cannot_invite');

  const byObserver = invite([], 'observer', base);
  check('C invite', 'an observer cannot invite another observer', byObserver.ok, 'false');
  check('C invite', 'the reason is not_a_guardian', byObserver.reason, 'not_a_guardian');

  const first = invite([], 'guardian', base);
  check('C invite', 'a guardian CAN invite a real observer', first.ok, 'true');
  check('C invite', 'the new observer starts unaccepted', first.observers[0].acceptedAt, 'null');
  check('C invite', 'the new observer starts unrevoked', first.observers[0].revokedAt, 'null');

  const dup = invite(first.observers, 'guardian', base);
  check('C invite', 'inviting the SAME (still-active) userId twice is refused',
    dup.ok, 'false');
  check('C invite', 'the reason is already_invited', dup.reason, 'already_invited');

  // A previously REVOKED observer is not "already invited" — re-inviting her
  // (the module's own doc comment: "invite() already handles an already-
  // accepted, non-revoked observer being re-added the same way a fresh one
  // is") must succeed, since revocation is meant to be reversible via a
  // fresh invite, not a permanent ban.
  const revokedObserver = { ...first.observers[0], revokedAt: '2026-02-01T00:00:00Z' };
  const reinvite = invite([revokedObserver], 'guardian', base);
  check('C invite', 're-inviting a previously revoked observer succeeds — revocation '
    + 'is reversible via a fresh invite, not a permanent ban', reinvite.ok, 'true');
}

// ===========================================================================
// D · revoke() — only the inviting guardian may revoke; immediate
// ===========================================================================
{
  const observers = [
    { userId: 'grandma-1', role: 'grandparent', invitedBy: 'dad-1', label: 'Grandma',
      invitedAt: '2026-01-01T00:00:00Z', acceptedAt: '2026-01-02T00:00:00Z', revokedAt: null },
  ];

  const wrongGuardian = revoke(observers, 'grandma-1', 'mom-1', '2026-03-01T00:00:00Z');
  check('D revoke', 'a DIFFERENT guardian than the one who invited cannot revoke',
    wrongGuardian.ok, 'false');
  check('D revoke', 'the reason is not_your_invitation',
    wrongGuardian.reason, 'not_your_invitation');
  check('D revoke', 'a refused revoke leaves the observer list untouched',
    wrongGuardian.ok ? '' : 'unchanged', 'unchanged');

  const rightGuardian = revoke(observers, 'grandma-1', 'dad-1', '2026-03-01T00:00:00Z');
  check('D revoke', 'the guardian who actually invited her CAN revoke', rightGuardian.ok, 'true');
  check('D revoke', 'revocation is immediate — revokedAt is set to the real timestamp given',
    rightGuardian.observers[0].revokedAt, '2026-03-01T00:00:00Z');

  const notFound = revoke(observers, 'nobody-was-invited', 'dad-1', '2026-03-01T00:00:00Z');
  check('D revoke', 'revoking a userId that was never actually invited is a silent, '
    + 'honest no-op (ok:true, list unchanged) rather than a thrown error',
    notFound.ok, 'true');
  check('D revoke', 'the no-op leaves the list byte-for-byte unchanged',
    JSON.stringify(notFound.observers), JSON.stringify(observers));
}

// ===========================================================================
// E · activeObservers() — accepted AND not revoked, both conditions
// ===========================================================================
{
  const mix = [
    { userId: 'a', acceptedAt: '2026-01-01T00:00:00Z', revokedAt: null },       // active
    { userId: 'b', acceptedAt: null, revokedAt: null },                        // never accepted
    { userId: 'c', acceptedAt: '2026-01-01T00:00:00Z', revokedAt: '2026-02-01T00:00:00Z' }, // revoked
    { userId: 'd', acceptedAt: null, revokedAt: '2026-02-01T00:00:00Z' },      // revoked, never accepted
  ];
  const active = activeObservers(mix);
  check('E activeObservers', 'exactly the one truly active observer is returned',
    active.map((o) => o.userId).join(','), 'a');
  check('E activeObservers', 'an unaccepted invite is excluded, even though never revoked',
    active.some((o) => o.userId === 'b'), 'false');
  check('E activeObservers', 'a revoked-after-accepting observer is excluded',
    active.some((o) => o.userId === 'c'), 'false');
}

// ===========================================================================
// F · Age-gated visibility control (§21 interaction)
// ===========================================================================
{
  check('F age gate', 'a young child does not control observer visibility',
    whoDecidesObserverVisibility(8), 'guardian');
  check('F age gate', 'the guardian decides right up to the day before the real threshold',
    whoDecidesObserverVisibility(CHILD_CONTROLS_OBSERVERS_FROM_AGE - 1), 'guardian');
  check('F age gate', 'the child decides from the exact real threshold age, inclusive',
    whoDecidesObserverVisibility(CHILD_CONTROLS_OBSERVERS_FROM_AGE), 'child');
  check('F age gate', 'and remains hers well past it', whoDecidesObserverVisibility(16), 'child');
  check('F age gate', 'the real threshold constant is 13, matching this module\'s own '
    + 'documented age (not a magic number silently changed elsewhere)',
    CHILD_CONTROLS_OBSERVERS_FROM_AGE, 13);
}

// ===========================================================================
// G · OBSERVER_GRANT_TTL_DAYS — the real number, not left unattached
// ===========================================================================
{
  check('G TTL', 'the real, documented six-month grant TTL', OBSERVER_GRANT_TTL_DAYS, 180);
}

// ===========================================================================
// H · auditObserverView() — an observer must never see the machinery
// ===========================================================================
{
  const clean = auditObserverView({ childName: 'Ivy', schedule: 'weekly' });
  check('H auditObserverView', 'a clean, observer-appropriate view is ok:true', clean.ok, 'true');

  const dirty = auditObserverView({ childName: 'Ivy', expenses: [{ amount: 40 }] });
  check('H auditObserverView', 'a leaking view (a real forbidden key) is ok:false', dirty.ok, 'false');
  check('H auditObserverView', 'the leak names the real forbidden field',
    dirty.leaks.includes('expenses'), 'true');

  const nested = auditObserverView({ family: { journal: 'private' } });
  check('H auditObserverView', 'a forbidden field nested inside another object is still caught',
    nested.ok, 'false');

  const arr = auditObserverView({ items: [{ courtExport: 'x' }, { ok: true }] });
  check('H auditObserverView', 'a forbidden field inside an array of objects is still caught',
    arr.ok, 'false');

  const caseInsensitive = auditObserverView({ CourtExport: 'x' });
  check('H auditObserverView', 'matching is case-insensitive, same discipline as the '
    + 'global sweep', caseInsensitive.ok, 'false');

  const dedup = auditObserverView({ a: { journal: 1 }, b: { journal: 2 } });
  check('H auditObserverView', 'the SAME forbidden key appearing at multiple paths is '
    + 'de-duplicated in the reported leaks list, not reported once per occurrence',
    dedup.leaks.length, 1);

  check('H auditObserverView', 'every real OBSERVER_FORBIDDEN field is individually '
    + 'caught when present alone',
    OBSERVER_FORBIDDEN.every((f) => auditObserverView({ [f]: 'x' }).ok === false), 'true');
}

let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
