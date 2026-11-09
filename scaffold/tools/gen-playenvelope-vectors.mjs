// Generates packages/play-envelope/test/vectors.json: golden inputs and the outputs the TypeScript engine
// (packages/play-envelope/src/envelope.ts) gives for them. The Dart port (client/lib/play_envelope.dart) is
// tested against the SAME file, so the two implementations cannot drift apart silently. The TS suite asserts
// this file equals a fresh generation, so editing the engine without regenerating fails CI.
//
// usage: node tools/gen-playenvelope-vectors.mjs            (writes the file)
//        node tools/gen-playenvelope-vectors.mjs --print    (prints, writes nothing)
import { writeFileSync } from 'node:fs';
import {
  parseEnvelope, newSession, stamp, receive, makeSid, canonicalJson, fnv1a32, stateDigest, hiddenLeaks,
  MAX_ENVELOPE_BYTES, MAX_UNACKED, ALWAYS_HIDDEN_KEYS,
} from '../packages/play-envelope/src/envelope.mjs';

const SID = '9f2c41d07a3b88e1';
const OTHER = '0123456789abcdef';
const env = (o) => ({ v: 1, sid: SID, n: 1, ack: 0, t: 'move', g: 'connect4', p: { column: 3 }, ...o });
const j = JSON.stringify;

function snap(s) {
  return { sid: s.sid, sendN: s.sendN, lastPeerN: s.lastPeerN, peerAck: s.peerAck, unacked: s.unacked.map((e) => e.n), overflowed: s.overflowed };
}

export function generate() {
  const out = {};

  const parseInputs = [
    j(env({})), j(env({ t: 'hello', sid: '', p: { resume: false } })), j(env({ t: 'hello', sid: SID, p: { resume: true } })),
    j(env({ t: 'req_state', p: undefined })), j(env({ t: 'state', p: { discardTop: 'R7' }, d: '9f3a1c2e' })),
    j(env({ t: 'bye', p: undefined })), j(env({ t: 'rematch', p: undefined })), j(env({ t: 'rematch_ok', p: undefined })),
    j(env({ t: 'move', p: undefined })), j(env({ t: 'state', p: undefined })),
    j(env({ sid: '' })), j(env({ sid: 'ZZZZ' })), j(env({ sid: SID.toUpperCase() })), j(env({ sid: SID + '0' })),
    j(env({ v: 2 })), j(env({ v: 0 })), j(env({ v: 1.5 })), j(env({ v: '1' })), j({ t: 'connect4_move', column: 3 }),
    j({ type: 'connect4_move', column: 3 }),
    j(env({ n: -1 })), j(env({ n: 1.5 })), j(env({ n: '1' })), j(env({ ack: -1 })), j(env({ ack: null })),
    j(env({ t: 'detonate' })), j(env({ t: 5 })), j(env({ g: '' })), j(env({ g: 'Connect4' })), j(env({ g: 'a'.repeat(25) })),
    j(env({ g: 'a'.repeat(24) })), j(env({ d: 'XYZ' })), j(env({ d: '9F3A1C2E' })), j(env({ d: 5 })),
    j(env({ p: [1, 2] })), j(env({ p: 'x' })), j(env({ p: null })),
    j(env({ from: 'a', seat: 'b', sender: 'c' })), j(env({ extra: { deep: 1 } })),
    j(env({ p: { column: 3, score: 10 } })), j(env({ p: { nested: { Streak: 4 } } })), j(env({ p: { list: [{ countdown: 3 }] } })),
    j(env({ p: { timeLeft: 3 } })), j(env({ p: { scores: 3 } })), j(env({ p: { highscore: 3 } })),
    JSON.stringify(env({ p: { pad: 'x'.repeat(MAX_ENVELOPE_BYTES) } })),
    JSON.stringify(env({ p: { pad: 'é'.repeat(MAX_ENVELOPE_BYTES / 2) } })),
    'x'.repeat(MAX_ENVELOPE_BYTES + 1),
    '{nope', 'null', '[1,2]', '7', '"text"', '',
  ];
  // nesting deeper than the cap, and nesting just inside it
  let deep = { x: 1 }; for (let i = 0; i < 20; i++) deep = { d: deep };
  parseInputs.push(j(env({ p: deep })));
  let ok = { x: 1 }; for (let i = 0; i < 10; i++) ok = { d: ok };
  parseInputs.push(j(env({ p: ok })));
  out.parse = parseInputs.map((input) => ({ input, expect: parseEnvelope(input) }));

  out.sid = [[0, 0, 0, 0, 0, 0, 0, 0], [1, 2, 3, 4, 5, 6, 7, 8], [255, 254, 253, 252, 251, 250, 249, 248], [1, 2, 3], [256, 257, 0, 0, 0, 0, 0, 0]]
    .map((bytes) => ({ bytes, expect: makeSid(bytes) }));

  const A = { role: 'authority', mySeat: 'b', authoritySeat: 'b', sid: SID };
  const G = { role: 'guest', mySeat: 'a', authoritySeat: 'b', sid: '' };
  const scenarios = [];
  const run = (name, init, steps) => {
    const s = newSession(init);
    const results = [];
    for (const st of steps) {
      if (st.op === 'stamp') {
        const e = stamp(s, st.t, st.g ?? 'connect4', st.p, st.d);
        results.push({ env: e, state: snap(s) });
      } else {
        const v = receive(s, st.env, st.from);
        results.push({ verdict: v, state: snap(s) });
      }
    }
    scenarios.push({ name, init, steps, results });
  };
  const rx = (e, from) => ({ op: 'receive', env: e, from });
  const tx = (t, p, d) => ({ op: 'stamp', t, p, d });
  const hello = (o) => env({ t: 'hello', p: {}, ...o });

  // A hello carries the sender's counter WITHOUT using one up (n = how many ordered messages it has sent so far).
  run('guest hears the authority hello, then ordered messages arrive in order', G, [
    rx(hello({ n: 0 }), 'b'),
    rx(env({ t: 'state', n: 1, p: { toMove: 'b' } }), 'b'),
    rx(env({ n: 2 }), 'b'),
    rx(env({ n: 3 }), 'b'),
  ]);
  run('guest: a message before any hello is for an unknown session', G, [rx(env({ n: 1 }), 'b'), rx(env({ t: 'state', n: 1, p: {} }), 'b')]);
  run('guest: wrong session id is dropped', G, [rx(hello({ n: 0 }), 'b'), rx(env({ sid: OTHER, n: 1 }), 'b')]);
  run('duplicates and older messages are dropped (replay)', A, [
    rx(hello({ sid: '', n: 0 }), 'a'), rx(env({ n: 1 }), 'a'), rx(env({ n: 1 }), 'a'), rx(env({ n: 2 }), 'a'),
    rx(env({ n: 1 }), 'a'), rx(env({ n: 0 }), 'a'), rx(env({ n: 3 }), 'a'),
  ]);
  run('a skipped message is held back and the receiver is told to ask for the state', A, [
    rx(hello({ sid: '', n: 0 }), 'a'), rx(env({ n: 1 }), 'a'), rx(env({ n: 3 }), 'a'), rx(env({ n: 2 }), 'a'), rx(env({ n: 3 }), 'a'),
  ]);
  run('a state snapshot is idempotent: the newest wins, an older one is dropped', G, [
    rx(hello({ n: 0 }), 'b'), rx(env({ t: 'state', n: 5, p: {} }), 'b'), rx(env({ t: 'state', n: 3, p: {} }), 'b'),
    rx(env({ t: 'state', n: 5, p: {} }), 'b'), rx(env({ t: 'state', n: 6, p: {} }), 'b'), rx(env({ n: 7 }), 'b'),
  ]);
  run('a state snapshot repairs a gap in the ordered messages', G, [
    rx(hello({ n: 0 }), 'b'), rx(env({ n: 2 }), 'b'), rx(env({ t: 'state', n: 3, p: {} }), 'b'), rx(env({ n: 4 }), 'b'),
  ]);
  run('only the authority may send state', A, [rx(hello({ sid: '', n: 0 }), 'a'), rx(env({ t: 'state', n: 1, p: {} }), 'a')]);
  run('a guest refuses a state from anyone but the authority seat', G, [rx(hello({ n: 0 }), 'b'), rx(env({ t: 'state', n: 1, p: {} }), 'c')]);
  run('a guest ignores a hello that is not from the authority', G, [rx(hello({ n: 0 }), 'c')]);
  run('our own message coming back is dropped', A, [rx(hello({ sid: '', n: 0 }), 'b'), rx(env({ n: 1 }), 'b')]);
  run('req_state is accepted as a control message and does not move the counter', A, [
    rx(hello({ sid: '', n: 0 }), 'a'), rx(env({ n: 1 }), 'a'), rx(env({ t: 'req_state', n: 1, p: undefined }), 'a'), rx(env({ n: 2 }), 'a'),
  ]);
  run('req_state for an unknown session is dropped', A, [rx(env({ t: 'req_state', sid: OTHER, n: 0, p: undefined }), 'a')]);
  run('sent moves are kept until the peer acknowledges them', A, [
    tx('move', { column: 1 }), tx('move', { column: 2 }), tx('state', { x: 1 }), tx('move', { column: 3 }),
    rx(hello({ n: 0, ack: 0 }), 'a'),
    rx(env({ n: 1, ack: 2 }), 'a'), rx(env({ n: 2, ack: 4 }), 'a'),
  ]);
  run('an ack beyond what we sent is refused', A, [tx('move', { column: 1 }), rx(hello({ n: 0, ack: 9 }), 'a')]);
  run('an ack beyond what we sent is refused on a move too', A, [
    rx(hello({ sid: '', n: 0 }), 'a'), tx('move', { c: 1 }), rx(env({ n: 1, ack: 5 }), 'a'),
  ]);
  run('ack never goes backwards', A, [
    tx('move', { c: 1 }), tx('move', { c: 2 }), rx(hello({ n: 0, ack: 2 }), 'a'), rx(env({ n: 1, ack: 1 }), 'a'),
  ]);
  run('stamp: a control message carries the counter without using one up', A, [
    rx(hello({ sid: '', n: 7 }), 'a'), tx('hello', { resume: true }), tx('state', { toMove: 'a' }, '9f3a1c2e'), tx('req_state'), tx('move', { c: 1 }), tx('hello', { resume: true }), tx('bye'),
  ]);
  run('the authority restarted from its save: the guest adopts the new session and counts again', G, [
    rx(hello({ n: 0 }), 'b'), rx(env({ n: 1 }), 'b'), rx(hello({ sid: OTHER, n: 0 }), 'b'), rx(env({ sid: OTHER, n: 1 }), 'b'), rx(env({ sid: OTHER, n: 2 }), 'b'),
  ]);
  run('the same hello again is a resume: counters are kept and a lost message is not hidden', G, [
    rx(hello({ n: 0 }), 'b'), rx(env({ n: 1 }), 'b'), rx(hello({ n: 3, p: { resume: true } }), 'b'), rx(env({ n: 3 }), 'b'), rx(env({ n: 2 }), 'b'),
  ]);
  run('a guest that restarted says hello with no session and the authority counts it afresh', A, [
    rx(hello({ sid: '', n: 0 }), 'a'), rx(env({ n: 1 }), 'a'), rx(env({ n: 2 }), 'a'),
    rx(hello({ sid: '', n: 0 }), 'a'), rx(env({ n: 1 }), 'a'),
  ]);
  run('a guest that knows the session says hello again: a resume, no counter reset', A, [
    rx(hello({ sid: '', n: 0 }), 'a'), rx(env({ n: 1 }), 'a'), rx(hello({ n: 1 }), 'a'), rx(env({ n: 1 }), 'a'), rx(env({ n: 2 }), 'a'),
  ]);
  run('a hello from an older session carries an ack that means nothing here: it is not refused for it', A, [
    tx('state', { x: 1 }), rx(hello({ sid: OTHER, n: 3, ack: 99 }), 'a'), rx(env({ n: 4 }), 'a'),
  ]);
  run('a new dealer session drops what we had sent to the old one', G, [
    rx(hello({ n: 0 }), 'b'), tx('move', { c: 1 }), tx('move', { c: 2 }), rx(hello({ sid: OTHER, n: 0, ack: 77 }), 'b'), tx('move', { c: 3 }),
  ]);
  run('rematch and rematch_ok are ordered like moves; bye too', A, [
    rx(hello({ sid: '', n: 0 }), 'a'), rx(env({ t: 'rematch', n: 1, p: undefined }), 'a'),
    rx(env({ t: 'rematch', n: 1, p: undefined }), 'a'), rx(env({ t: 'bye', n: 2, p: undefined }), 'a'), rx(env({ t: 'rematch_ok', n: 4, p: undefined }), 'a'),
  ]);

  // The retained list is bounded: more than MAX_UNACKED unacknowledged moves drops the oldest.
  {
    const s = newSession(A);
    const steps = [];
    for (let i = 0; i < MAX_UNACKED + 3; i++) steps.push(tx('move', { c: i }));
    const results = steps.map((st) => ({ env: stamp(s, st.t, 'connect4', st.p, st.d), state: snap(s) }));
    scenarios.push({ name: 'the retained list is bounded', init: A, steps, results });
  }
  out.scenarios = scenarios;

  const states = [
    { a: 1, b: [1, 2, 3], c: 'x' }, { c: 'x', b: [1, 2, 3], a: 1 }, { z: null, y: true, x: false }, {}, [], [[], {}],
    { name: 'é "\\\n\t\u0001', n: -4, big: 9007199254740991 }, { f: 1.5 }, { n: 1e21 }, 'plain', null, true, 7,
    { nested: { b: { d: 1, c: 2 }, a: [3, { y: 1, x: 2 }] } }, { discardTop: 'R7', turn: 'b', counts: { a: 7, b: 6 }, color: 'red' },
    { x: [1, 2.5] }, { 'ключ': 1, a: 2, B: 3, 'é': 4 },
  ];
  out.canonical = states.map((value) => ({ value, expect: canonicalJson(value), digest: stateDigest(value) }));

  out.fnv = ['', 'a', 'foobar', 'hello', 'Olive Branch', 'é', '日本語', '😀', 'x'.repeat(1000)].map((text) => ({ text, expect: fnv1a32(text) }));

  const hiddenCases = [
    [{ myHandForPeer: ['R7'], opponentHandCount: 6 }, ['hands', ...ALWAYS_HIDDEN_KEYS]],
    [{ hands: { a: [], b: [] } }, ['hands']], [{ nested: { list: [{ drawPile: [] }] } }, ['drawPile']],
    [{ seed: 123, rngSeed: 1 }, ALWAYS_HIDDEN_KEYS], [{ Seed: 1 }, ALWAYS_HIDDEN_KEYS], [{ deck: [], hands: 1 }, ['hands', ...ALWAYS_HIDDEN_KEYS]],
    [{}, ['hands']], [[{ a: { seed: 1 } }], ALWAYS_HIDDEN_KEYS],
  ];
  out.hidden = hiddenCases.map(([payload, keys]) => ({ payload, keys, expect: hiddenLeaks(payload, keys) }));

  out.constants = { maxEnvelopeBytes: MAX_ENVELOPE_BYTES, maxUnacked: MAX_UNACKED, alwaysHidden: [...ALWAYS_HIDDEN_KEYS] };
  return JSON.parse(JSON.stringify(out));
}

if (process.argv[1] && process.argv[1].endsWith('gen-playenvelope-vectors.mjs')) {
  const text = JSON.stringify(generate(), null, 1) + '\n';
  if (process.argv.includes('--print')) process.stdout.write(text);
  else { writeFileSync(new URL('../packages/play-envelope/test/vectors.json', import.meta.url), text); console.log('wrote packages/play-envelope/test/vectors.json', text.length, 'bytes'); }
}
