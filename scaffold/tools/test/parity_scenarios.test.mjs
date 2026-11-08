/**
 * Parity-scenario drift guard. The prototype (docs/superpowers/mockups/live) is the REFERENCE; the Flutter
 * parity harness replays client/test/parity/scenarios.json, which tools/gen-parity-scenarios.mjs writes by
 * running the prototype's OWN scenarios and rule probes headless. This fails if the committed file is stale,
 * if a rule the prototype states stopped being true, or if the harness wiring is missing.
 *
 *   regenerate: cd scaffold && node tools/gen-parity-scenarios.mjs
 */
import { readFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { render, OUT } from '../gen-parity-scenarios.mjs';

const SCAFFOLD = fileURLToPath(new URL('../../', import.meta.url));
const rd = (p) => readFileSync(p, 'utf8').replace(/\r\n/g, '\n');

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = JSON.stringify(a) === JSON.stringify(e); ok ? pass++ : fail++; rows.push({ g, n, ok, a: JSON.stringify(a), e: JSON.stringify(e) }); };

const fresh = await render();
const D = JSON.parse(fresh);
const R = D.rules;

{
  const g = 'A drift';
  check(g, 'scenarios.json exists', existsSync(OUT), true);
  check(g, 'scenarios.json equals a fresh run of the prototype (run: node tools/gen-parity-scenarios.mjs)', rd(OUT) === fresh, true);
  check(g, 'the generator is deterministic (two runs, identical bytes)', (await render()) === fresh, true);
}
{
  const g = 'B scenarios';
  check(g, 'the seven prototype scenarios', D.scenarios.map((s) => s.id).join(), 'golden,offline,birthday,call,play,family,deletion');
  for (const s of D.scenarios) {
    check(g, `${s.id}: has steps`, s.steps.length > 0, true);
    check(g, `${s.id}: every step has a caption, acts, and at least one matrix row`, s.steps.every((x) => x.cap && Array.isArray(x.acts) && x.rows.length > 0), true);
    check(g, `${s.id}: step ids are sequential`, s.steps.every((x, i) => x.id === `${s.id}.${String(i + 1).padStart(2, '0')}`), true);
  }
  const gold = D.scenarios[0];
  check(g, 'golden ends with the child tablet watching the message and the guardian queue showing it', gold.steps.some((x) => x.expect.some((e) => e.probe === 'msg.0.state' && e.value === 'watched')), true);
  check(g, 'golden: the tablet is paired and the age locked', gold.steps.some((x) => x.expect.some((e) => e.probe === 'dev.k.paired' && e.value === true)) && gold.steps.some((x) => x.expect.some((e) => e.probe === 'child.ageLocked' && e.value === true)), true);
  const off = D.scenarios[1];
  check(g, 'offline: the message is never reported delivered while the tablet is offline', off.steps.some((x) => x.expect.some((e) => e.probe === 'msg.0.state' && e.value === 'delivering')), true);
  check(g, 'birthday: turning 13 moves the band to t1317', D.scenarios[2].steps.some((x) => x.expect.some((e) => e.probe === 'band' && e.value === 't1317')), true);
  check(g, 'deletion: sign-in is paused and then recovered', D.scenarios[6].steps.some((x) => x.expect.some((e) => e.probe === 'acct.state' && e.value === 'pending')) && D.scenarios[6].steps.some((x) => x.expect.some((e) => e.probe === 'acct.state' && e.value === 'active')), true);
}
{
  const g = 'C rule table';
  check(g, 'PIN lockout: the 5th wrong try locks for 15 minutes', [R.pinLockout.wrongTriesToLock, R.pinLockout.lockMinutes, R.pinLockout.windowMinutes], [5, 15, 15]);
  check(g, 'PIN lockout: a correct PIN is refused while locked and accepted after', [R.pinLockout.correctPinWhileLocked.status, R.pinLockout.correctPinAfterLock.status, R.pinLockout.fourWrongThenRight.status], [423, 201, 201]);
  check(g, 'a child can never make a pairing code', R.pinLockout.childMayNotMakeCode, { status: 403, code: 'forbidden' });
  check(g, 'pairing code: 6 digits, 1 to 9 only, valid 10 minutes', [R.pairing.codeLength, R.pairing.alphabet, R.pairing.ttlMinutes], [6, '1-9', 10]);
  check(g, 'redeem: the 6th wrong code is rate limited for 5 minutes', [R.pairing.redeemLockoutTries[5].status, R.pairing.redeemLockoutMinutes], [429, 5]);
  check(g, 'label rule: locked 3..15 is Mommy/Daddy, 16..17 and unlocked stay Mom/Dad', [R.labels.table.locked['3'], R.labels.table.locked['15'], R.labels.table.locked['16'], R.labels.table.unlocked['9']], [['Mommy', 'Daddy'], ['Mommy', 'Daddy'], ['Mom', 'Dad'], ['Mom', 'Dad']]);
  check(g, 'label rule: her nickname wins and a guardian can never rename it', [R.labels.nicknameWins, R.labels.guardianCannotRename], [true, true]);
  check(g, 'bands start at 3, 5, 8, 13', R.bands.firstAgeOfBand, { t34: 3, t57: 5, t812: 8, t1317: 13 });
  check(g, 'watched means played through (1.5 s tolerance)', [R.messages.watchedToleranceMs, R.messages.notPlayedThroughCode, R.messages.playedMsAtToleranceAccepted.status], [1500, 'not_played_through', 200]);
  check(g, 'message length 3 s to 10 min', [R.messages.minMs, R.messages.maxMs, R.messages.tooShort.code, R.messages.tooLong.code], [3000, 600000, 'message_too_short', 'message_too_long']);
  check(g, 'retry cadence: 10 minutes, then hourly, 8 tries then failed', [R.retryCadence.firstRetryAfterMinutes, R.retryCadence.laterRetryAfterMinutes, R.retryCadence.maxAttempts, R.retryCadence.finalState], [10, 60, 8, 'failed']);
  check(g, 'her replies are kept 14 days; grown-up messages are preserved', [R.expiry.replyKeptDays, R.expiry.guardianSentMessagesPreserved], [14, true]);
  check(g, 'only guardians start calls; only the child knocks', [R.calls.childStartsCall.code, R.calls.guardianKnocks.code], ['child_cannot_start_call', 'not_a_child_surface']);
  check(g, 'play window: open 07:30, winding 19:30 to 19:45, closed after', [R.playWindow.states['07:29'], R.playWindow.states['07:30'], R.playWindow.states['19:29'], R.playWindow.states['19:30'], R.playWindow.states['19:45']], ['closed', 'open', 'open', 'winding', 'closed']);
  check(g, 'Messages can never be hidden', R.parentalControls.hideMessages, { status: 403, code: 'cannot_hide_messages' });
  check(g, 'emergency card: a stale base is a 409 that returns the current version', [R.emergencyCard.staleBase.code, R.emergencyCard.staleReturnsCurrentVersion], ['stale_version', true]);
  check(g, 'double dose: the second dose is refused', R.medications.doubleDose.second, { status: 409, code: 'already_given' });
  check(g, 'deletion: 182 to 365 day recovery window', [R.deletion.minDays, R.deletion.maxDays], [182, 365]);
  check(g, 'family change: stale base 409, a held change applies only on release', [R.familyChanges.staleBase.code, R.familyChanges.held.result, R.familyChanges.peopleBeforeRelease < R.familyChanges.peopleAfterRelease], ['stale_version', 'held', true]);
  check(g, 'a locked age is never overwritten by the tablet', R.session.lockedAgeNeverOverwritten, true);
  check(g, 'route table lists the pairing route with its error codes', D.routes.some((r) => r.path.endsWith('/device-pairing-codes') && r.errors.includes('423 pin_locked')), true);
}
{
  const g = 'D wiring';
  const pkg = JSON.parse(rd(SCAFFOLD + 'package.json'));
  check(g, 'package.json has test:parity-scenarios, part of npm test', !!pkg.scripts['test:parity-scenarios'] && pkg.scripts.test.includes('test:parity-scenarios'), true);
  check(g, 'verify.sh runs this test', rd(SCAFFOLD + 'tools/verify.sh').includes('tools/test/parity_scenarios.test.mjs'), true);
  for (const f of ['ledger_baseline.json', 'scenario_runner.dart', 'fake_server.dart', 'rules_parity_test.dart', 'scenario_parity_test.dart'])
    check(g, `client/test/parity/${f} is committed`, existsSync(SCAFFOLD + 'client/test/parity/' + f), true);
}

let g = '';
for (const r of rows) {
  if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`));
}
console.log(`\n${'-'.repeat(60)}\n${pass} passed, ${fail} failed\n`);
setImmediate(() => process.exit(fail === 0 ? 0 : 1));
