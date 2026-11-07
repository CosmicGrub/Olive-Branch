/**
 * co-view — "Read together" / "Watch together" pure core.
 * Design: docs/superpowers/specs/2026-11-07-co-viewing-design.md.
 *
 * Same discipline as game-sync/test/table.test.mjs: every deny path is a real
 * assertion, hostile inputs are named for what they are.
 */
import {
  DEAD_ZONE_S, HARD_SEEK_S, RATE_BAND, TICK_S, TICK_STALE_MS,
  MAX_MESSAGE_BYTES, MAX_POSITION_S,
  DEFAULT_ALLOWANCE_MIN, MIN_ALLOWANCE_MIN, MAX_ALLOWANCE_MIN, LAST_ONE_MIN,
  parseCoViewMessage, canLead, mayEmit, newSeqState, acceptSeq,
  sampleFromPing, estimateOffset, correct, expectedPosition, followerStep,
  changeAllowance, budgetState, remainingSeconds, chooseTransport, reannounce,
} from '../src/coview.mjs';
import { readFileSync } from 'node:fs';
import { generate } from '../../../tools/gen-coview-vectors.mjs';

let pass = 0, fail = 0; const rows = [];
function check(group, name, actual, expected) {
  const ok = String(actual) === String(expected);
  ok ? pass++ : fail++;
  rows.push({ group, name, ok, actual: String(actual), expected: String(expected) });
}
const j = (o) => JSON.stringify(o);

const GUARDIAN = { kind: 'guardian', role: 'guardian' };
const CHILD = { kind: 'child' };
const SITTER = { kind: 'adult', role: 'sitter' };
const CO_GUARDIAN = { kind: 'guardian', role: 'guardian' };

// ------------------------------------------------------------ C2 parsing ---
{
  const g = 'C2 parse: valid messages';
  const tick = { t: 'tick', seq: 1, pos: 12.5, rate: 1, paused: false, sentAt: 1_700_000_000_000 };
  check(g, 'tick round-trips', j(parseCoViewMessage(j(tick))), j({ ok: true, msg: tick }));
  check(g, 'tick as an already-parsed object is accepted too', parseCoViewMessage(tick).ok, true);
  check(g, 'seek', parseCoViewMessage(j({ t: 'seek', seq: 2, pos: 0, sentAt: 5 })).ok, true);
  check(g, 'start with a well-formed asset id', parseCoViewMessage(j({ t: 'start', seq: 0, at: 5, assetId: 'story_01-AB' })).ok, true);
  for (const by of ['guardian', 'child', 'budget'])
    check(g, `stop by ${by}`, parseCoViewMessage(j({ t: 'stop', seq: 3, by })).ok, true);
}
{
  const g = 'C2 parse: hostile input is refused, never thrown';
  const reason = (x) => { const r = parseCoViewMessage(x); return r.ok ? 'OK' : r.reason; };
  check(g, 'oversized message', reason('x'.repeat(MAX_MESSAGE_BYTES + 1)), 'too_large');
  check(g, 'oversized by multibyte characters (bytes, not chars)', reason('é'.repeat(MAX_MESSAGE_BYTES)), 'too_large');
  check(g, 'not JSON', reason('{nope'), 'not_json');
  check(g, 'JSON null', reason('null'), 'not_object');
  check(g, 'JSON array', reason('[1,2]'), 'not_object');
  check(g, 'JSON number', reason('7'), 'not_object');
  check(g, 'unknown type', reason(j({ t: 'detonate', seq: 1 })), 'bad_type');
  check(g, 'missing type', reason(j({ seq: 1 })), 'bad_type');
  check(g, 'missing seq', reason(j({ t: 'stop', by: 'child' })), 'bad_field');
  check(g, 'negative seq', reason(j({ t: 'stop', seq: -1, by: 'child' })), 'bad_field');
  check(g, 'fractional seq', reason(j({ t: 'stop', seq: 1.5, by: 'child' })), 'bad_field');
  check(g, 'string seq', reason(j({ t: 'stop', seq: '1', by: 'child' })), 'bad_field');
  check(g, 'unsafe-integer seq', reason(j({ t: 'stop', seq: 2 ** 60, by: 'child' })), 'bad_field');
  check(g, 'negative position', reason(j({ t: 'seek', seq: 1, pos: -0.1, sentAt: 1 })), 'bad_field');
  check(g, 'position beyond the 24 h bound', reason(j({ t: 'seek', seq: 1, pos: MAX_POSITION_S + 1, sentAt: 1 })), 'bad_field');
  check(g, 'NaN position (object path)', reason({ t: 'seek', seq: 1, pos: NaN, sentAt: 1 }), 'bad_field');
  check(g, 'Infinity sentAt (object path)', reason({ t: 'seek', seq: 1, pos: 1, sentAt: Infinity }), 'bad_field');
  check(g, 'rate below 0.5', reason(j({ t: 'tick', seq: 1, pos: 1, rate: 0.4, paused: false, sentAt: 1 })), 'bad_field');
  check(g, 'rate above 2', reason(j({ t: 'tick', seq: 1, pos: 1, rate: 2.5, paused: false, sentAt: 1 })), 'bad_field');
  check(g, 'paused is not a boolean', reason(j({ t: 'tick', seq: 1, pos: 1, rate: 1, paused: 'no', sentAt: 1 })), 'bad_field');
  check(g, 'asset id with a path separator', reason(j({ t: 'start', seq: 1, at: 1, assetId: '../etc/passwd' })), 'bad_field');
  check(g, 'asset id with a space', reason(j({ t: 'start', seq: 1, at: 1, assetId: 'a b' })), 'bad_field');
  check(g, 'empty asset id', reason(j({ t: 'start', seq: 1, at: 1, assetId: '' })), 'bad_field');
  check(g, 'asset id over 64 chars', reason(j({ t: 'start', seq: 1, at: 1, assetId: 'a'.repeat(65) })), 'bad_field');
  check(g, 'stop by an unknown party', reason(j({ t: 'stop', seq: 1, by: 'admin' })), 'bad_field');
  check(g, 'null input (non-string, non-object)', reason(null), 'not_object');
  check(g, 'undefined input', reason(undefined), 'not_object');
  check(g, '__proto__ key cannot smuggle a type', reason('{"__proto__":{"t":"tick"},"seq":1}'), 'bad_type');
}

// ------------------------------------------------------ C1 authorization ---
{
  const g = 'C1 who may lead';
  check(g, 'a guardian may lead', canLead(GUARDIAN), true);
  check(g, 'a child may not lead', canLead(CHILD), false);
  check(g, 'a sitter may not lead', canLead(SITTER), false);
  check(g, 'a guardian-kind principal with a non-guardian role may not lead', canLead({ kind: 'guardian', role: 'sitter' }), false);
  check(g, 'null principal fails closed', canLead(null), false);
  check(g, 'undefined principal fails closed', canLead(undefined), false);
  check(g, 'empty object fails closed', canLead({}), false);
}
{
  const g = 'C1 who may emit what';
  const tick = { t: 'tick', seq: 1, pos: 1, rate: 1, paused: false, sentAt: 1 };
  check(g, 'guardian may send a tick', mayEmit(GUARDIAN, tick), true);
  check(g, 'child may NOT send a tick (cannot steer the guardian)', mayEmit(CHILD, tick), false);
  check(g, 'child may NOT send a seek', mayEmit(CHILD, { t: 'seek', seq: 1, pos: 1, sentAt: 1 }), false);
  check(g, 'child may NOT start a show', mayEmit(CHILD, { t: 'start', seq: 1, at: 1, assetId: 'x' }), false);
  check(g, 'child may end their own view', mayEmit(CHILD, { t: 'stop', seq: 1, by: 'child' }), true);
  check(g, 'child may NOT forge a guardian stop', mayEmit(CHILD, { t: 'stop', seq: 1, by: 'guardian' }), false);
  check(g, 'child may NOT forge a budget stop', mayEmit(CHILD, { t: 'stop', seq: 1, by: 'budget' }), false);
  check(g, 'a sitter may not emit anything', mayEmit(SITTER, tick), false);
  check(g, 'null principal may not emit', mayEmit(null, tick), false);
  check(g, 'child may answer an invitation (join)', mayEmit(CHILD, { t: 'join', seq: 1 }), true);
  check(g, 'a sitter may not join', mayEmit(SITTER, { t: 'join', seq: 1 }), false);
  check(g, 'a guardian may send join too (the engine does not forbid it)', mayEmit(GUARDIAN, { t: 'join', seq: 1 }), true);
  check(g, 'join parses', parseCoViewMessage('{"t":"join","seq":4}').ok, true);
  check(g, 'join without seq is refused', parseCoViewMessage('{"t":"join"}').ok, false);
}

// --------------------------------------------------------- C3 sequencing ---
{
  const g = 'C3 sequence guard';
  const s = newSeqState();
  check(g, 'first message (seq 0) is fresh', acceptSeq(s, 0), true);
  check(g, 'seq 1 fresh', acceptSeq(s, 1), true);
  check(g, 'replay of seq 1 refused', acceptSeq(s, 1), false);
  check(g, 'older seq 0 refused (stale tick from the old transport)', acceptSeq(s, 0), false);
  check(g, 'a gap is fine: seq 7 fresh', acceptSeq(s, 7), true);
  check(g, 'last advanced to 7', s.last, 7);
  check(g, 'NaN refused', acceptSeq(s, NaN), false);
  check(g, 'fractional refused', acceptSeq(s, 7.5), false);
  check(g, 'a refused message does not move the guard', s.last, 7);
}

// ------------------------------------------------------- clock estimation ---
{
  const g = 'clock offset';
  // Leader clock is 500 ms ahead; one-way 40 ms each way; leader holds 5 ms.
  const mk = (t0, ahead = 500, up = 40, down = 40) =>
    sampleFromPing(t0, t0 + up + ahead, t0 + up + ahead + 5, t0 + up + 5 + down);
  const s = mk(1000);
  check(g, 'recovers a symmetric offset exactly', s.offsetMs, 500);
  check(g, 'rtt excludes the leader hold time', s.rttMs, 80);
  check(g, 'asymmetric path gives a bounded error (half the asymmetry)', mk(1000, 500, 100, 20).offsetMs, 540);
  check(g, 'negative rtt (impossible ordering) is discarded', sampleFromPing(0, 0, 0, -5), null);
  check(g, 'non-finite input is discarded', sampleFromPing(0, NaN, 0, 5), null);
  check(g, 'missing input is discarded', sampleFromPing(0, 1, 2, undefined), null);
  check(g, 'fewer than 3 samples: no estimate', estimateOffset([mk(0), mk(1)]), null);
  check(g, 'discarded samples do not count toward the 3', estimateOffset([mk(0), mk(1), null, null]), null);
  const est = estimateOffset([mk(0, 500, 300, 300), mk(10, 500, 40, 40), mk(20, 500, 200, 200), mk(30, 500, 90, 90)]);
  check(g, 'picks the lowest-rtt sample (least queued)', est.rttMs, 80);
  check(g, 'and reports its offset', est.offsetMs, 500);
  check(g, 'reports how many samples fed it', est.samples, 4);
}

// ----------------------------------------------------------- drift control ---
{
  const g = 'drift correction zones';
  check(g, 'zero error: nothing', correct(0).action, 'none');
  check(g, 'inside the dead zone (ahead): nothing', correct(DEAD_ZONE_S).action, 'none');
  check(g, 'inside the dead zone (behind): nothing', correct(-DEAD_ZONE_S).action, 'none');
  check(g, 'just outside the dead zone: nudge', correct(DEAD_ZONE_S + 0.01).action, 'rate');
  const ahead = correct(0.4);
  check(g, 'ahead => slow down (rate < 1)', ahead.rate < 1, true);
  const behind = correct(-0.4);
  check(g, 'behind => speed up (rate > 1)', behind.rate > 1, true);
  // Known property, pinned deliberately: half of the smallest error outside the
  // dead zone (0.075) already exceeds the band (0.05), so the nudge saturates at
  // ±band the moment it leaves the dead zone (bang-bang, not proportional). That
  // is what tools/co-viewing-model/sync-sim.mjs validated (~0.2 s steady drift).
  check(g, 'a nudge saturates at the band immediately outside the dead zone', correct(DEAD_ZONE_S + 0.001).rate.toFixed(4), (1 - RATE_BAND).toFixed(4));
  check(g, 'and stays saturated across the soft zone', correct(0.2).rate.toFixed(4), '0.9500');
  check(g, 'a large soft-zone error is clamped to the band (ahead)', correct(1.9).rate.toFixed(4), (1 - RATE_BAND).toFixed(4));
  check(g, 'a large soft-zone error is clamped to the band (behind)', correct(-1.9).rate.toFixed(4), (1 + RATE_BAND).toFixed(4));
  check(g, 'at exactly the seek threshold: still a nudge', correct(HARD_SEEK_S).action, 'rate');
  check(g, 'beyond the seek threshold: hard seek', correct(HARD_SEEK_S + 0.01).action, 'seek');
  check(g, 'beyond the seek threshold (behind): hard seek', correct(-5).action, 'seek');
  check(g, 'NaN error resyncs rather than guessing', correct(NaN).action, 'seek');
  check(g, 'Infinity error resyncs', correct(Infinity).action, 'seek');
  check(g, 'rate never leaves the band for any error',
    [-1.99, -1, -0.5, 0.5, 1, 1.99].every(e => { const r = correct(e).rate; return r >= 1 - RATE_BAND - 1e-12 && r <= 1 + RATE_BAND + 1e-12; }), true);
}
{
  const g = 'expected position';
  const tick = { t: 'tick', seq: 1, pos: 100, rate: 1, paused: false, sentAt: 10_000 };
  check(g, 'advances with leader-clock time since the tick', expectedPosition(tick, 12_000, 0), 102);
  check(g, 'applies the clock offset', expectedPosition(tick, 11_500, 500), 102);
  check(g, 'honours the leader rate', expectedPosition({ ...tick, rate: 1.5 }, 12_000, 0), 103);
  check(g, 'paused leader: position does not advance', expectedPosition({ ...tick, paused: true }, 99_000, 0), 100);
  check(g, 'a tick from the "future" never moves expected backwards', expectedPosition(tick, 9_000, 0), 100);
}
{
  const g = 'follower step';
  const tick = { t: 'tick', seq: 1, pos: 50, rate: 1, paused: false, sentAt: 0 };
  const base = { tick, receivedAtMs: 1000, nowMs: 1000, offsetMs: 0 };
  check(g, 'no tick yet: nothing', followerStep({ ...base, tick: null, localPos: 0 }).action, 'none');
  check(g, 'on target: nothing', followerStep({ ...base, localPos: 51 }).action, 'none');
  const behind = followerStep({ ...base, localPos: 50.6 });
  check(g, 'slightly behind: speed up', `${behind.action}/${behind.rate > 1}`, 'rate/true');
  const far = followerStep({ ...base, localPos: 40 });
  check(g, 'far behind: seek to expected', `${far.action}/${far.to}`, 'seek/51');
  const paused = { ...tick, paused: true };
  check(g, 'leader paused, follower aligned: pause', followerStep({ ...base, tick: paused, localPos: 50.05 }).action, 'pause');
  const drifted = followerStep({ ...base, tick: paused, localPos: 53 });
  check(g, 'leader paused, follower drifted: land on the leader position', `${drifted.action}/${drifted.to}`, 'seek/50');
  check(g, 'a tick older than the stale limit is not steered by',
    followerStep({ ...base, nowMs: 1000 + TICK_STALE_MS + 1, localPos: 0 }).action, 'none');
  check(g, 'a tick exactly at the stale limit still counts',
    followerStep({ ...base, nowMs: 1000 + TICK_STALE_MS, localPos: 0 }).action, 'seek');
}

// ----------------------------- end to end: the follower really converges ---
{
  const g = 'convergence (mirror of tools/co-viewing-model/sync-sim.mjs)';
  function run({ startOffset, latency, estErrMs, skew, seconds }) {
    const dt = 0.05, steps = Math.round(seconds / dt), tickSteps = Math.round(TICK_S / dt);
    let leader = 0, follower = -startOffset, rate = 1, tick = null, rx = 0, seeks = 0, worst = 0;
    const pending = [];
    for (let k = 0; k < steps; k++) {
      const nowMs = k * dt * 1000;
      leader += dt;
      if (k % tickSteps === 0) pending.push({ at: nowMs + latency * 1000, t: { t: 'tick', seq: k, pos: leader, rate: 1, paused: false, sentAt: nowMs } });
      for (let i = pending.length - 1; i >= 0; i--) if (pending[i].at <= nowMs) { tick = pending[i].t; rx = nowMs; pending.splice(i, 1); }
      const a = followerStep({ tick, receivedAtMs: rx, nowMs, localPos: follower, offsetMs: estErrMs });
      if (a.action === 'seek') { follower = a.to; rate = 1; seeks++; }
      else if (a.action === 'rate') rate = a.rate;
      else if (a.action === 'none') rate = rate; // hold
      follower += dt * rate * (1 + skew);
      if (nowMs > 30_000) worst = Math.max(worst, Math.abs(follower - leader));
    }
    return { seeks, worst };
  }
  const clean = run({ startOffset: 3, latency: 0.08, estErrMs: 0, skew: 0.005, seconds: 300 });
  check(g, 'joins 3 s late: exactly one initial seek, then none', clean.seeks, 1);
  check(g, 'steady-state drift stays under 0.4 s with a fast follower clock', clean.worst < 0.4, true);
  const biased = run({ startOffset: 3, latency: 0.4, estErrMs: 0, skew: 0.005, seconds: 300 });
  check(g, 'a late-delivered tick (400 ms) is compensated by the offset estimate', biased.worst < 0.8, true);
}

// ------------------------------------------------------------- allowance ---
{
  const g = 'C4 allowance: defaults and bounds';
  check(g, 'default is 2 hours (owner decision 3)', DEFAULT_ALLOWANCE_MIN, 120);
  check(g, 'floor is 0 (off)', MIN_ALLOWANCE_MIN, 0);
  check(g, 'a ceiling exists and is above the default', MAX_ALLOWANCE_MIN > DEFAULT_ALLOWANCE_MIN, true);
}
{
  const g = 'C4 allowance: who changes it, and how';
  const lower = changeAllowance(GUARDIAN, 120, 90);
  check(g, 'a guardian can lower it', `${lower.ok}/${lower.limitMin}/${lower.direction}`, 'true/90/lower');
  check(g, 'lowering never needs co-guardian sign-off', lower.notifyCoGuardian, false);
  const raise = changeAllowance(GUARDIAN, 120, 180);
  check(g, 'a guardian can raise it', `${raise.ok}/${raise.limitMin}/${raise.direction}`, 'true/180/raise');
  check(g, 'a raise is surfaced to the other guardian', raise.notifyCoGuardian, true);
  check(g, 'the co-guardian has the same power', changeAllowance(CO_GUARDIAN, 120, 60).ok, true);
  check(g, 'same value is a no-op, not a raise', changeAllowance(GUARDIAN, 120, 120).direction, 'same');
  check(g, 'a no-op does not notify', changeAllowance(GUARDIAN, 120, 120).notifyCoGuardian, false);
  const off = changeAllowance(GUARDIAN, 120, 0);
  check(g, 'a guardian can switch it off (0)', `${off.ok}/${off.limitMin}`, 'true/0');
  check(g, 'a child cannot change it', changeAllowance(CHILD, 120, 480).reason, 'not_a_guardian');
  check(g, 'a sitter cannot change it', changeAllowance(SITTER, 120, 60).reason, 'not_a_guardian');
  check(g, 'null actor cannot change it', changeAllowance(null, 120, 60).reason, 'not_a_guardian');
  check(g, 'a rejected change leaves the limit alone', changeAllowance(CHILD, 120, 480).limitMin, 120);
  check(g, 'a rejected change never notifies', changeAllowance(CHILD, 120, 480).notifyCoGuardian, false);
  check(g, 'above the ceiling rejected', changeAllowance(GUARDIAN, 120, MAX_ALLOWANCE_MIN + 1).reason, 'above_ceiling');
  check(g, 'exactly the ceiling accepted', changeAllowance(GUARDIAN, 120, MAX_ALLOWANCE_MIN).ok, true);
  check(g, 'negative rejected', changeAllowance(GUARDIAN, 120, -1).reason, 'below_floor');
  check(g, 'fractional minutes rejected', changeAllowance(GUARDIAN, 120, 90.5).reason, 'not_a_number');
  check(g, 'a string is not a number', changeAllowance(GUARDIAN, 120, '90').reason, 'not_a_number');
  check(g, 'NaN rejected', changeAllowance(GUARDIAN, 120, NaN).reason, 'not_a_number');
  check(g, 'Infinity rejected', changeAllowance(GUARDIAN, 120, Infinity).reason, 'not_a_number');
  check(g, 'null rejected', changeAllowance(GUARDIAN, 120, null).reason, 'not_a_number');
}
{
  const g = 'C4 budget state (what the child sees)';
  check(g, 'limit 0 = off', budgetState(0, 0), 'off');
  check(g, 'a negative limit is treated as off', budgetState(-5, 0), 'off');
  check(g, 'plenty left', budgetState(120, 600), 'ok');
  check(g, 'exactly LAST_ONE_MIN left => last one', budgetState(120, (120 - LAST_ONE_MIN) * 60), 'last_one');
  check(g, 'one second more than that is still ok', budgetState(120, (120 - LAST_ONE_MIN) * 60 - 1), 'ok');
  check(g, 'nothing left', budgetState(120, 120 * 60), 'exhausted');
  check(g, 'over budget stays exhausted', budgetState(120, 99999), 'exhausted');
  check(g, 'negative usage is not credit', budgetState(120, -9999), 'ok');
  check(g, 'remaining seconds', remainingSeconds(120, 600), 6600);
  check(g, 'remaining never negative', remainingSeconds(120, 99999), 0);
  check(g, 'remaining with the feature off is 0', remainingSeconds(0, 0), 0);
  check(g, 'raising the limit mid-day restores a spent budget', budgetState(180, 120 * 60), 'ok');
}

// ----------------------------------------------------------- transport ---
{
  const g = 'transport choice (both channels)';
  check(g, 'call live => ride the call data channel', chooseTransport({ callConnected: true, tableAvailable: true }), 'livekit');
  check(g, 'call live, no table => still the call', chooseTransport({ callConnected: true, tableAvailable: false }), 'livekit');
  check(g, 'no call => game-sync table', chooseTransport({ callConnected: false, tableAvailable: true }), 'table');
  check(g, 'neither => none (do not start)', chooseTransport({ callConnected: false, tableAvailable: false }), 'none');
}
{
  const g = 'transport migration';
  const tick = reannounce({ pos: 321.5, rate: 1, paused: false }, 41, 1_700_000_000_000);
  check(g, 're-announce carries the leader position', tick.pos, 321.5);
  check(g, 're-announce seq is above everything sent so far', tick.seq, 42);
  check(g, 're-announce is a valid wire message', parseCoViewMessage(j(tick)).ok, true);
  const guard = newSeqState();
  acceptSeq(guard, 41);
  check(g, 'a late tick (seq 41) from the OLD transport is ignored after migration', acceptSeq(guard, 41), false);
  check(g, 'the re-announce (seq 42) is accepted', acceptSeq(guard, tick.seq), true);
  check(g, 're-announce preserves a paused leader', reannounce({ pos: 5, rate: 1, paused: true }, 0, 1).paused, true);
}

// ------------------------------------------- shared vectors (the Dart port) ---
{
  const g = 'golden vectors';
  const onDisk = JSON.parse(readFileSync(new URL('./vectors.json', import.meta.url), 'utf8'));
  const fresh = generate();
  check(g, 'vectors.json equals a fresh generation (run: node tools/gen-coview-vectors.mjs)', JSON.stringify(onDisk) === JSON.stringify(fresh), true);
  for (const k of ['parse', 'principals', 'seq', 'samples', 'estimates', 'correct', 'expected', 'followerStep', 'allowance', 'budget', 'transport', 'reannounce'])
    check(g, `section "${k}" is present and non-empty`, Array.isArray(onDisk[k]) && onDisk[k].length > 0, true);
  check(g, 'NaN and Infinity inputs are spelled as strings, never lost', onDisk.correct.some(c => c.err === 'NaN') && onDisk.correct.some(c => c.err === 'Infinity'), true);
}

// ---------------------------------------------------------------------------
let gname = '';
for (const r of rows) {
  if (r.group !== gname) { gname = r.group; console.log(`\n${gname}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.name}` +
    (r.ok ? '' : `\n         expected ${r.expected}, got ${r.actual}`));
}
console.log(`\n${'-'.repeat(60)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
