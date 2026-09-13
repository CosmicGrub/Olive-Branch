/**
 * offline.ts — MASTERFILE §5.22, offline queueing + §5.22.2 conflict
 * resolution. Zero test coverage for the TS source anywhere in this
 * repository before this file — distinct from (and not covered by) the
 * Dart client's own separately-disclosed partial port. Every one of the
 * nine real exported functions/consts is exercised directly here, including
 * the safety-critical §5.22.2 rule this module's own comment states plainly:
 * "the child's edit beats a guardian's... a guardian silently overwriting
 * it is precisely the failure this rule prevents."
 */
import {
  NOT_QUEUEABLE, MAX_ATTEMPTS, enqueue, nextToSend, recordFailure, backoffMs,
  sent, offlineChildView, offlineGuardianView, resolve, conflictNotice,
  OFFLINE_FORBIDDEN,
} from '../src/offline.mjs';

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) }); };

const item = (kind, id, createdAt) =>
  ({ id, kind, createdAt, payload: { x: 1 }, attempts: 0, lastError: null });

// ===========================================================================
// A · enqueue() — queueable items land; NOT_QUEUEABLE ones are dropped, not
//     banked and not erred
// ===========================================================================
{
  const r1 = enqueue([], item('drawing', 'd1', '2026-01-01T00:00:00Z'));
  check('A enqueue', 'a queueable item is actually queued', r1.outbox.length, 1);
  check('A enqueue', 'not reported as dropped', r1.dropped, 'false');
  check('A enqueue', 'the queued item starts at zero attempts', r1.outbox[0].attempts, 0);
  check('A enqueue', 'the queued item starts with no lastError', r1.outbox[0].lastError, 'null');

  const r2 = enqueue([], item('ping', 'p1', '2026-01-01T00:00:00Z'));
  check('A enqueue', 'a real NOT_QUEUEABLE kind (ping) is never added to the outbox',
    r2.outbox.length, 0);
  check('A enqueue', 'it is honestly reported as dropped, not silently ignored',
    r2.dropped, 'true');
  check('A enqueue', 'NOT_QUEUEABLE really names ping and only ping (the exact "meaningless '
    + 'late" case the module\'s own header describes)', NOT_QUEUEABLE.join(','), 'ping');

  const r3 = enqueue(r1.outbox, item('message', 'm1', '2026-01-02T00:00:00Z'));
  check('A enqueue', 'enqueueing onto an existing non-empty outbox appends, not replaces',
    r3.outbox.length, 2);
  check('A enqueue', 'the original item is still first (insertion order preserved)',
    r3.outbox[0].id, 'd1');
}

// ===========================================================================
// B · nextToSend() — oldest first, and permanently-failed items excluded
// ===========================================================================
{
  check('B nextToSend', 'an empty outbox has nothing to send', nextToSend([]), null);

  const outbox = [
    item('drawing', 'newer', '2026-01-05T00:00:00Z'),
    item('drawing', 'oldest', '2026-01-01T00:00:00Z'),
    item('drawing', 'middle', '2026-01-03T00:00:00Z'),
  ];
  check('B nextToSend', 'the genuinely oldest item by createdAt is returned first, '
    + 'regardless of array order', nextToSend(outbox).id, 'oldest');

  const withExhausted = [
    { ...item('drawing', 'exhausted', '2026-01-01T00:00:00Z'), attempts: MAX_ATTEMPTS },
    item('drawing', 'still-trying', '2026-01-02T00:00:00Z'),
  ];
  check('B nextToSend', 'an item that has hit MAX_ATTEMPTS is excluded, even though it is '
    + 'the oldest', nextToSend(withExhausted).id, 'still-trying');

  const allExhausted = [
    { ...item('drawing', 'x', '2026-01-01T00:00:00Z'), attempts: MAX_ATTEMPTS },
  ];
  check('B nextToSend', 'when every item is exhausted, null is returned rather than a '
    + 'stuck item retried forever', nextToSend(allExhausted), null);
}

// ===========================================================================
// C · recordFailure() / backoffMs() — attempts increment, backoff grows and
//     caps
// ===========================================================================
{
  const outbox = [item('drawing', 'd1', '2026-01-01T00:00:00Z')];
  const failed = recordFailure(outbox, 'd1', 'network unreachable');
  check('C recordFailure', 'the real item\'s attempts count increments by exactly one',
    failed[0].attempts, 1);
  check('C recordFailure', 'the real error message is recorded, not discarded',
    failed[0].lastError, 'network unreachable');
  check('C recordFailure', 'a DIFFERENT item id in the outbox is left untouched',
    recordFailure([...outbox, item('drawing', 'd2', '2026-01-01T00:00:00Z')], 'd1', 'x')
      .find((i) => i.id === 'd2').attempts, 0);

  check('C backoffMs', 'zero attempts is the real one-minute floor', backoffMs(0), 60_000);
  check('C backoffMs', 'backoff genuinely doubles per attempt (exponential, not linear)',
    backoffMs(2), 240_000);
  check('C backoffMs', 'backoff is capped at the real six-hour ceiling, not left to grow '
    + 'unbounded', backoffMs(20), 6 * 60 * 60_000);
}

// ===========================================================================
// D · sent() — removes exactly the delivered item, nothing else
// ===========================================================================
{
  const outbox = [item('drawing', 'd1', '2026-01-01T00:00:00Z'),
    item('drawing', 'd2', '2026-01-02T00:00:00Z')];
  const after = sent(outbox, 'd1');
  check('D sent', 'the delivered item is actually removed', after.length, 1);
  check('D sent', 'the OTHER item survives untouched', after[0].id, 'd2');
  check('D sent', 'removing an id that was never in the outbox is a safe no-op',
    sent(outbox, 'never-existed').length, 2);
}

// ===========================================================================
// E · offlineChildView() — deliberately not a queue; no numbers, no anxiety
// ===========================================================================
{
  const empty = offlineChildView([]);
  check('E offlineChildView', 'an empty outbox reports nothing waiting', empty.anythingWaiting, 'false');
  check('E offlineChildView', 'and shows no line at all when there is nothing to say',
    empty.line, '');

  const full = offlineChildView([item('drawing', 'd1', '2026-01-01T00:00:00Z'),
    item('drawing', 'd2', '2026-01-02T00:00:00Z')]);
  check('E offlineChildView', 'a non-empty outbox reports something waiting', full.anythingWaiting, 'true');
  check('E offlineChildView', 'the real reassurance line, not an engineering status string '
    + '(no "2 pending" anywhere in it)', full.line, 'It will go when you have internet again. It is safe.');
  check('E offlineChildView', 'the child-facing line never mentions a raw count',
    /\d/.test(full.line), 'false');
}

// ===========================================================================
// F · offlineGuardianView() — the mechanics, since he can act on them
// ===========================================================================
{
  const empty = offlineGuardianView([]);
  check('F offlineGuardianView', 'an empty outbox reports zero waiting', empty.waiting, 0);
  check('F offlineGuardianView', 'and no oldest timestamp', empty.oldest, 'null');
  check('F offlineGuardianView', 'and nothing stuck', empty.stuck.length, 0);

  const outbox = [
    { ...item('drawing', 'newer', '2026-01-05T00:00:00Z'), attempts: 0 },
    { ...item('drawing', 'oldest', '2026-01-01T00:00:00Z'), attempts: 0 },
    { ...item('drawing', 'stuck-one', '2026-01-03T00:00:00Z'), attempts: MAX_ATTEMPTS },
  ];
  const full = offlineGuardianView(outbox);
  check('F offlineGuardianView', 'the real total waiting count', full.waiting, 3);
  check('F offlineGuardianView', 'the real oldest createdAt, not the first array element',
    full.oldest, '2026-01-01T00:00:00Z');
  check('F offlineGuardianView', 'exactly the item at MAX_ATTEMPTS is reported stuck',
    full.stuck.map((i) => i.id).join(','), 'stuck-one');
}

// ===========================================================================
// G · resolve() — §5.22.2's safety-critical rule: her edit ALWAYS beats his
// ===========================================================================
{
  const childEdit = { actor: 'child', at: '2026-01-01T00:00:00Z', value: 'her version', by: 'ivy' };
  const guardianEdit = { actor: 'guardian', at: '2026-01-05T00:00:00Z', value: 'his version', by: 'dad' };

  // The guardian's edit is LATER by timestamp — a naive last-write-wins
  // would pick him. The real rule must not.
  const r1 = resolve(childEdit, guardianEdit);
  check('G resolve', 'the CHILD wins even though her edit is chronologically OLDER — '
    + 'this is the one assertion this whole file exists to prove', r1.winner.by, 'ivy');
  check('G resolve', 'the guardian edit is the loser, not silently applied',
    r1.loser.by, 'dad');
  check('G resolve', 'the real, honest reason names WHY, not just WHAT',
    r1.reason, 'it is her list — a guardian edit never silently overwrites hers');

  // Same pair, arguments reversed — the rule must not depend on argument order.
  const r2 = resolve(guardianEdit, childEdit);
  check('G resolve', 'the child still wins with the arguments reversed — order-independent',
    r2.winner.by, 'ivy');

  // Two guardians conflicting: later wins, by real timestamp.
  const guardianA = { actor: 'guardian', at: '2026-01-01T00:00:00Z', value: 'a', by: 'dad' };
  const guardianB = { actor: 'guardian', at: '2026-01-05T00:00:00Z', value: 'b', by: 'stepdad' };
  const r3 = resolve(guardianA, guardianB);
  check('G resolve', 'between two guardians, the chronologically LATER edit wins',
    r3.winner.by, 'stepdad');
  check('G resolve', 'the reason correctly names the later-wins rule for this case',
    r3.reason, 'later edit wins; the earlier one is kept');

  // Two children (co-parented siblings sharing a list is not this module's
  // concern, but the same actor twice must still resolve deterministically)
  const childA = { actor: 'child', at: '2026-01-01T00:00:00Z', value: 'a', by: 'ivy' };
  const childB = { actor: 'child', at: '2026-01-05T00:00:00Z', value: 'b', by: 'ivy' };
  const r4 = resolve(childA, childB);
  check('G resolve', 'same-actor conflicts also resolve later-wins, symmetrically',
    r4.winner.value, 'b');
}

// ===========================================================================
// H · conflictNotice() — a losing edit is never destroyed, both told honestly
// ===========================================================================
{
  const guardianLoser = { actor: 'guardian', at: '2026-01-01T00:00:00Z', value: 'x', by: 'dad' };
  check('H conflictNotice', 'a losing GUARDIAN edit is told, plainly, that hers is showing '
    + 'and his is kept — never silently dropped',
    conflictNotice(guardianLoser),
    'She changed this while you were both offline, so hers is showing. Yours is kept.');

  const childLoser = { actor: 'child', at: '2026-01-01T00:00:00Z', value: 'x', by: 'ivy' };
  check('H conflictNotice', 'a losing CHILD edit (the two-guardians case) gets the neutral '
    + '"both are kept" framing, not the same guardian-specific line',
    conflictNotice(childLoser), 'This was changed in two places. Both are kept.');
}

// ===========================================================================
// I · OFFLINE_FORBIDDEN — the child-facing anxiety-vocabulary ban
// ===========================================================================
{
  check('I OFFLINE_FORBIDDEN', 'the real list bans the exact engineering words the child '
    + 'view must never use (spot-check a few)',
    ['pending', 'failed', 'retry', 'stuck'].every((w) => OFFLINE_FORBIDDEN.includes(w)), 'true');
}

let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
