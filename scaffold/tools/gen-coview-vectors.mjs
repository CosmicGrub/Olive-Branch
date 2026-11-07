// Generates packages/co-view/test/vectors.json: golden inputs and the outputs the
// TypeScript engine (packages/co-view/src/coview.ts) gives for them. The Dart
// port (client/lib/co_view_logic.dart) is tested against the SAME file, so the
// two implementations cannot drift apart silently. The TS suite asserts this
// file equals a fresh generation, so editing the engine without regenerating
// fails CI.
//
// usage: node tools/gen-coview-vectors.mjs            (writes the file)
//        node tools/gen-coview-vectors.mjs --print    (prints, writes nothing)
import { writeFileSync } from 'node:fs';
import {
  parseCoViewMessage, canLead, mayEmit, newSeqState, acceptSeq, sampleFromPing, estimateOffset,
  correct, expectedPosition, followerStep, changeAllowance, budgetState, remainingSeconds,
  chooseTransport, reannounce, MAX_MESSAGE_BYTES, MAX_POSITION_S,
} from '../packages/co-view/src/coview.mjs';

// JSON has no NaN or Infinity, so those are spelled as strings in the file and
// translated back by each runner.
const num = (v) => (v === 'NaN' ? NaN : v === 'Infinity' ? Infinity : v === '-Infinity' ? -Infinity : v);
const safe = (v) => (Number.isNaN(v) ? 'NaN' : v === Infinity ? 'Infinity' : v === -Infinity ? '-Infinity' : v);
const GUARDIAN = { kind: 'guardian', role: 'guardian' };
const CHILD = { kind: 'child' };
const SITTER = { kind: 'adult', role: 'sitter' };
const WRONG_ROLE = { kind: 'guardian', role: 'sitter' };

export function generate() {
  const out = {};

  const parseInputs = [
    JSON.stringify({ t: 'tick', seq: 1, pos: 12.5, rate: 1, paused: false, sentAt: 1700000000000 }),
    JSON.stringify({ t: 'seek', seq: 2, pos: 0, sentAt: 5 }),
    JSON.stringify({ t: 'start', seq: 0, at: 5, assetId: 'story_01-AB' }),
    JSON.stringify({ t: 'join', seq: 4 }),
    JSON.stringify({ t: 'join' }),
    JSON.stringify({ t: 'join', seq: -1 }),
    JSON.stringify({ t: 'stop', seq: 3, by: 'guardian' }),
    JSON.stringify({ t: 'stop', seq: 3, by: 'child' }),
    JSON.stringify({ t: 'stop', seq: 3, by: 'budget' }),
    'x'.repeat(MAX_MESSAGE_BYTES + 1),
    'é'.repeat(MAX_MESSAGE_BYTES),
    '{nope', 'null', '[1,2]', '7',
    JSON.stringify({ t: 'detonate', seq: 1 }),
    JSON.stringify({ seq: 1 }),
    JSON.stringify({ t: 'stop', by: 'child' }),
    JSON.stringify({ t: 'stop', seq: -1, by: 'child' }),
    JSON.stringify({ t: 'stop', seq: 1.5, by: 'child' }),
    JSON.stringify({ t: 'stop', seq: '1', by: 'child' }),
    JSON.stringify({ t: 'seek', seq: 1, pos: -0.1, sentAt: 1 }),
    JSON.stringify({ t: 'seek', seq: 1, pos: MAX_POSITION_S + 1, sentAt: 1 }),
    JSON.stringify({ t: 'seek', seq: 1, pos: MAX_POSITION_S, sentAt: 1 }),
    JSON.stringify({ t: 'tick', seq: 1, pos: 1, rate: 0.4, paused: false, sentAt: 1 }),
    JSON.stringify({ t: 'tick', seq: 1, pos: 1, rate: 0.5, paused: false, sentAt: 1 }),
    JSON.stringify({ t: 'tick', seq: 1, pos: 1, rate: 2, paused: true, sentAt: 1 }),
    JSON.stringify({ t: 'tick', seq: 1, pos: 1, rate: 2.5, paused: false, sentAt: 1 }),
    JSON.stringify({ t: 'tick', seq: 1, pos: 1, rate: 1, paused: 'no', sentAt: 1 }),
    JSON.stringify({ t: 'start', seq: 1, at: 1, assetId: '../etc/passwd' }),
    JSON.stringify({ t: 'start', seq: 1, at: 1, assetId: 'a b' }),
    JSON.stringify({ t: 'start', seq: 1, at: 1, assetId: '' }),
    JSON.stringify({ t: 'start', seq: 1, at: 1, assetId: 'a'.repeat(64) }),
    JSON.stringify({ t: 'start', seq: 1, at: 1, assetId: 'a'.repeat(65) }),
    JSON.stringify({ t: 'stop', seq: 1, by: 'admin' }),
  ];
  out.parse = parseInputs.map((raw) => ({ raw, expect: parseCoViewMessage(raw) }));

  const msgs = [
    { t: 'tick', seq: 1, pos: 1, rate: 1, paused: false, sentAt: 1 },
    { t: 'seek', seq: 1, pos: 1, sentAt: 1 },
    { t: 'start', seq: 1, at: 1, assetId: 'x' },
    { t: 'stop', seq: 1, by: 'child' },
    { t: 'stop', seq: 1, by: 'guardian' },
    { t: 'stop', seq: 1, by: 'budget' },
    { t: 'join', seq: 1 },
  ];
  const principals = [GUARDIAN, CHILD, SITTER, WRONG_ROLE, null, {}];
  out.principals = principals.map((p) => ({ principal: p, canLead: canLead(p), mayEmit: msgs.map((m) => mayEmit(p, m)) }));
  out.msgs = msgs;

  const seqRuns = [[0, 1, 1, 0, 7, 7.5, 7, 8], [5, 4, 5, 6], [0, 0, 0], [-1, 0], [2 ** 40, 2 ** 40, 2 ** 40 + 1]];
  out.seq = seqRuns.map((run) => { const s = newSeqState(); return { run, accepted: run.map((x) => acceptSeq(s, x)), last: s.last }; });

  const mk = (t0, ahead = 500, up = 40, down = 40) => [t0, t0 + up + ahead, t0 + up + ahead + 5, t0 + up + 5 + down];
  const pings = [mk(1000), mk(1000, 500, 100, 20), [0, 0, 0, -5], [0, 1, 2, 3], [10, 20, 25, 40]];
  out.samples = pings.map((p) => ({ ping: p, sample: sampleFromPing(...p) }));
  const sets = [
    [mk(0), mk(1)],
    [mk(0), mk(1), null, null],
    [mk(0, 500, 300, 300), mk(10, 500, 40, 40), mk(20, 500, 200, 200), mk(30, 500, 90, 90)],
    [mk(0, 100, 10, 10), mk(5, 100, 10, 10), mk(9, 100, 10, 10)],
  ];
  out.estimates = sets.map((set) => {
    const samples = set.map((p) => (p ? sampleFromPing(...p) : null));
    return { samples, estimate: estimateOffset(samples) };
  });

  const errs = [0, 0.05, 0.15, 0.1500001, 0.16, 0.4, -0.4, 0.8, 1.99, 2, 2.0000001, -2, -2.5, -5, 'NaN', 'Infinity', '-Infinity'];
  out.correct = errs.map((e) => ({ err: e, expect: correct(num(e)) }));
  out.correctCustom = [[0.2, { dead: 0.05, seek: 1, band: 0.1 }], [0.04, { dead: 0.05, seek: 1, band: 0.1 }], [1.5, { dead: 0.05, seek: 1, band: 0.1 }], [-0.3, { dead: 0.05, seek: 1, band: 0.1 }]]
    .map(([err, cfg]) => ({ err, cfg, expect: correct(err, cfg) }));

  const tick = { t: 'tick', seq: 1, pos: 100, rate: 1, paused: false, sentAt: 10000 };
  const expCases = [[tick, 12000, 0], [tick, 11500, 500], [{ ...tick, rate: 1.5 }, 12000, 0], [{ ...tick, paused: true }, 99000, 0], [tick, 9000, 0], [tick, 10000, -250]];
  out.expected = expCases.map(([tk, now, off]) => ({ tick: tk, nowMs: now, offsetMs: off, expect: expectedPosition(tk, now, off) }));

  const t50 = { t: 'tick', seq: 1, pos: 50, rate: 1, paused: false, sentAt: 0 };
  const steps = [
    { tick: null, receivedAtMs: 1000, nowMs: 1000, localPos: 0, offsetMs: 0 },
    { tick: t50, receivedAtMs: 1000, nowMs: 1000, localPos: 51, offsetMs: 0 },
    { tick: t50, receivedAtMs: 1000, nowMs: 1000, localPos: 50.6, offsetMs: 0 },
    { tick: t50, receivedAtMs: 1000, nowMs: 1000, localPos: 51.4, offsetMs: 0 },
    { tick: t50, receivedAtMs: 1000, nowMs: 1000, localPos: 40, offsetMs: 0 },
    { tick: { ...t50, paused: true }, receivedAtMs: 1000, nowMs: 1000, localPos: 50.05, offsetMs: 0 },
    { tick: { ...t50, paused: true }, receivedAtMs: 1000, nowMs: 1000, localPos: 53, offsetMs: 0 },
    { tick: t50, receivedAtMs: 1000, nowMs: 1000 + 12000 + 1, localPos: 0, offsetMs: 0 },
    { tick: t50, receivedAtMs: 1000, nowMs: 1000 + 12000, localPos: 0, offsetMs: 0 },
    { tick: t50, receivedAtMs: 1000, nowMs: 3000, localPos: 52, offsetMs: 500 },
  ];
  out.followerStep = steps.map((a) => ({ args: a, expect: followerStep(a) }));

  const allowChanges = [
    [GUARDIAN, 120, 90], [GUARDIAN, 120, 180], [GUARDIAN, 120, 120], [GUARDIAN, 120, 0], [GUARDIAN, 120, 480],
    [GUARDIAN, 120, 481], [GUARDIAN, 120, -1], [GUARDIAN, 120, 90.5], [GUARDIAN, 120, '90'], [GUARDIAN, 120, null],
    [CHILD, 120, 480], [SITTER, 120, 60], [null, 120, 60], [WRONG_ROLE, 120, 60], [GUARDIAN, 0, 120], [GUARDIAN, 480, 60],
  ];
  out.allowance = allowChanges.map(([actor, current, requested]) => ({ actor, current, requested, expect: changeAllowance(actor, current, requested) }));

  const budgets = [[0, 0], [-5, 0], [120, 0], [120, 600], [120, 6600], [120, 6599], [120, 7200], [120, 99999], [120, -9999], [180, 7200], [1, 59], [1, 60]];
  out.budget = budgets.map(([limit, used]) => ({ limit, used, state: budgetState(limit, used), remaining: remainingSeconds(limit, used) }));

  out.transport = [[true, true], [true, false], [false, true], [false, false]]
    .map(([c, t]) => ({ callConnected: c, tableAvailable: t, expect: chooseTransport({ callConnected: c, tableAvailable: t }) }));
  out.reannounce = [[{ pos: 321.5, rate: 1, paused: false }, 41, 1700000000000], [{ pos: 5, rate: 1, paused: true }, 0, 1]]
    .map(([leader, lastSeq, now]) => ({ leader, lastSeq, nowMs: now, expect: reannounce(leader, lastSeq, now) }));

  // normalise any NaN/Infinity that leaked into outputs
  return JSON.parse(JSON.stringify(out, (_k, v) => (typeof v === 'number' && !Number.isFinite(v) ? safe(v) : v)));
}

if (process.argv[1] && process.argv[1].endsWith('gen-coview-vectors.mjs')) {
  const text = JSON.stringify(generate(), null, 1) + '\n';
  if (process.argv.includes('--print')) process.stdout.write(text);
  else { writeFileSync(new URL('../packages/co-view/test/vectors.json', import.meta.url), text); console.log('wrote packages/co-view/test/vectors.json', text.length, 'bytes'); }
}
