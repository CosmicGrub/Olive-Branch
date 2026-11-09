/**
 * play-envelope — the versioned, sequenced wrapper around ad-hoc "Play together" messages.
 * Design: docs/superpowers/research/gamesuite-multiplayer-for-play-together.md §5.1.
 *
 * Same discipline as co-view/test/coview.test.mjs: every deny path is a real assertion, hostile
 * inputs are named for what they are, and the shared vectors the Dart port replays are pinned to the engine.
 */
import {
  PROTOCOL_VERSION, MAX_ENVELOPE_BYTES, MAX_UNACKED, MAX_PAYLOAD_DEPTH, KINDS, FORBIDDEN_KEYS, ALWAYS_HIDDEN_KEYS,
  parseEnvelope, newSession, makeSid, stamp, receive, pendingResend, canonicalJson, fnv1a32, stateDigest, hiddenLeaks,
} from '../src/envelope.mjs';
import { readFileSync } from 'node:fs';
import { generate } from '../../../tools/gen-playenvelope-vectors.mjs';

let pass = 0, fail = 0; const rows = [];
function check(group, name, actual, expected) {
  const ok = String(actual) === String(expected);
  ok ? pass++ : fail++;
  rows.push({ group, name, ok, actual: String(actual), expected: String(expected) });
}
const j = (o) => JSON.stringify(o);
const SID = '9f2c41d07a3b88e1';
const env = (o) => ({ v: 1, sid: SID, n: 1, ack: 0, t: 'move', g: 'connect4', p: { column: 3 }, ...o });
const reason = (x) => { const r = parseEnvelope(x); return r.ok ? 'OK' : r.reason; };
const authority = () => newSession({ role: 'authority', mySeat: 'b', authoritySeat: 'b', sid: SID });
const guest = () => newSession({ role: 'guest', mySeat: 'a', authoritySeat: 'b', sid: '' });
const verdict = (s, e, from) => { const v = receive(s, e, from); return v.accept ? 'accept' : v.reason; };

// ---------------------------------------------------------------- constants ---
{
  const g = 'constants';
  check(g, 'protocol version is 1', PROTOCOL_VERSION, 1);
  check(g, 'strict size cap is 8 KiB', MAX_ENVELOPE_BYTES, 8192);
  check(g, 'seven message kinds', KINDS.length, 7);
  check(g, 'kinds are hello, req_state, state, move, bye, rematch, rematch_ok', KINDS.join(','), 'hello,req_state,state,move,bye,rematch,rematch_ok');
  check(g, 'the forbidden-key list is the same twelve words as live_games.dart', FORBIDDEN_KEYS.join(','),
    'score,points,streak,record,best,highScore,reactionMs,reaction_ms,accuracy,rank,timeLeft,countdown');
  check(g, 'a seed can never leave the dealer', ALWAYS_HIDDEN_KEYS.includes('seed') && ALWAYS_HIDDEN_KEYS.includes('rngSeed'), true);
}

// ------------------------------------------------------------------ parsing ---
{
  const g = 'E2 parse: valid envelopes';
  const m = env({});
  check(g, 'a move round-trips', j(parseEnvelope(j(m))), j({ ok: true, env: m }));
  check(g, 'an already-decoded object is accepted too', parseEnvelope(m).ok, true);
  check(g, 'a guest hello may have an empty session id', reason(j(env({ t: 'hello', sid: '', p: { resume: false } }))), 'OK');
  check(g, 'req_state needs no payload', reason(j(env({ t: 'req_state', p: undefined }))), 'OK');
  check(g, 'a state carries its digest', reason(j(env({ t: 'state', p: { turn: 'a' }, d: '9f3a1c2e' }))), 'OK');
  for (const t of KINDS) check(g, `kind ${t} parses`, reason(j(env({ t, p: { x: 1 } }))), 'OK');
  check(g, 'unknown fields are dropped, not copied', Object.keys(parseEnvelope(j(env({ extra: 1, from: 'a' }))).env).join(','), 'v,sid,n,ack,t,g,p');
}
{
  const g = 'E1 sender is never read from the body';
  const r = parseEnvelope(j(env({ from: 'a', seat: 'b', sender: 'c' })));
  check(g, 'a from/seat/sender field parses but is not carried into the envelope', r.ok && !('from' in r.env) && !('seat' in r.env) && !('sender' in r.env), true);
}
{
  const g = 'E2 parse: hostile input is refused, never thrown';
  check(g, 'oversized by ASCII', reason('x'.repeat(MAX_ENVELOPE_BYTES + 1)), 'too_large');
  check(g, 'oversized by multibyte characters (bytes, not chars)', reason(j(env({ p: { pad: 'é'.repeat(MAX_ENVELOPE_BYTES / 2) } }))), 'too_large');
  check(g, 'a decoded object that would be oversized on the wire', reason(env({ p: { pad: 'x'.repeat(MAX_ENVELOPE_BYTES) } })), 'too_large');
  check(g, 'not JSON', reason('{nope'), 'not_json');
  check(g, 'empty string', reason(''), 'not_json');
  check(g, 'JSON null', reason('null'), 'not_object');
  check(g, 'JSON array', reason('[1,2]'), 'not_object');
  check(g, 'a bare number', reason('7'), 'not_object');
  check(g, 'a bare string', reason('"text"'), 'not_object');
  check(g, 'undefined', reason(undefined), 'not_object');
  check(g, 'unknown kind', reason(j(env({ t: 'detonate' }))), 'bad_type');
  check(g, 'kind is not a string', reason(j(env({ t: 5 }))), 'bad_type');
  check(g, 'a move needs a payload', reason(j(env({ p: undefined }))), 'bad_field');
  check(g, 'a state needs a payload', reason(j(env({ t: 'state', p: undefined }))), 'bad_field');
  check(g, 'payload must be an object, not an array', reason(j(env({ p: [1] }))), 'bad_field');
  check(g, 'payload must not be null', reason(j(env({ p: null }))), 'bad_field');
  check(g, 'an empty session id is only for hello', reason(j(env({ sid: '' }))), 'bad_field');
  check(g, 'session id must be 16 lowercase hex characters', reason(j(env({ sid: SID.toUpperCase() }))), 'bad_field');
  check(g, 'session id too long', reason(j(env({ sid: SID + '0' }))), 'bad_field');
  check(g, 'negative n', reason(j(env({ n: -1 }))), 'bad_field');
  check(g, 'fractional n', reason(j(env({ n: 1.5 }))), 'bad_field');
  check(g, 'string n', reason(j(env({ n: '1' }))), 'bad_field');
  check(g, 'negative ack', reason(j(env({ ack: -1 }))), 'bad_field');
  check(g, 'game id must be lowercase', reason(j(env({ g: 'Connect4' }))), 'bad_field');
  check(g, 'game id is capped at 24 characters', reason(j(env({ g: 'a'.repeat(25) }))), 'bad_field');
  check(g, 'digest must be 8 lowercase hex', reason(j(env({ d: '9F3A1C2E' }))), 'bad_field');
  let deep = { x: 1 }; for (let i = 0; i < MAX_PAYLOAD_DEPTH + 8; i++) deep = { d: deep };
  check(g, 'a payload nested past the cap', reason(j(env({ p: deep }))), 'bad_field');
}
{
  const g = 'unknown-version handling';
  check(g, 'a newer protocol version is refused as unsupported, not misread', reason(j(env({ v: 2 }))), 'unsupported_version');
  check(g, 'a far-future version', reason(j(env({ v: 99 }))), 'unsupported_version');
  check(g, 'version 0 is not a version', reason(j(env({ v: 0 }))), 'bad_field');
  check(g, 'fractional version', reason(j(env({ v: 1.5 }))), 'bad_field');
  check(g, 'string version', reason(j(env({ v: '1' }))), 'bad_field');
  check(g, 'no version at all is the old dialect, flagged for the one-release shim', reason(j({ type: 'connect4_move', column: 3 })), 'legacy');
}
{
  const g = 'E2 child-safety audit on receive';
  for (const k of FORBIDDEN_KEYS) check(g, `a "${k}" key in the payload is refused`, reason(j(env({ p: { [k]: 1 } }))), 'forbidden_key');
  check(g, 'case-insensitive: Streak', reason(j(env({ p: { nested: { Streak: 4 } } }))), 'forbidden_key');
  check(g, 'inside an array', reason(j(env({ p: { list: [{ countdown: 3 }] } }))), 'forbidden_key');
  check(g, 'a longer word that merely contains one is fine (scores, highscore)', reason(j(env({ p: { scores: 1 } }))), 'OK');
  check(g, 'the same word as a VALUE is fine', reason(j(env({ p: { note: 'score' } }))), 'OK');
}

// --------------------------------------------------------------- sequencing ---
{
  const g = 'E4 session id';
  const a = authority();
  check(g, 'a session id is 16 hex characters from 8 bytes', makeSid([1, 2, 3, 4, 5, 6, 7, 8]), '0102030405060708');
  check(g, 'bytes above 255 are masked', makeSid([256, 257, 0, 0, 0, 0, 0, 0]), '0001000000000000');
  check(g, 'missing bytes are zero', makeSid([1, 2, 3]), '0102030000000000');
  check(g, 'the authority starts with its own id', a.sid, SID);
  check(g, 'a guest starts with none', guest().sid, '');
  const gu = guest();
  check(g, 'a guest drops everything before the authority speaks', verdict(gu, env({ n: 1 }), 'b'), 'unknown_sid');
  receive(gu, env({ t: 'hello', n: 1, p: {} }), 'b');
  check(g, 'after the hello it has adopted the id', gu.sid, SID);
  check(g, 'a message from some other session is dropped', verdict(gu, env({ sid: '0123456789abcdef', n: 2 }), 'b'), 'unknown_sid');
}
{
  const g = 'E3 order, duplicate, replay, gap';
  const a = authority();
  receive(a, env({ t: 'hello', sid: '', n: 1, p: {} }), 'a');
  check(g, 'the next in-order move is accepted', verdict(a, env({ n: 2 }), 'a'), 'accept');
  check(g, 'the same move again is a duplicate', verdict(a, env({ n: 2 }), 'a'), 'duplicate');
  check(g, 'an older move is stale', verdict(a, env({ n: 1 }), 'a'), 'stale');
  check(g, 'a replay of the hello-time message is stale', verdict(a, env({ n: 0 }), 'a'), 'stale');
  check(g, 'a skipped move is held back', verdict(a, env({ n: 5 }), 'a'), 'gap');
  check(g, 'and the receiver is told to ask for the state', receive(a, env({ n: 5 }), 'a').needState, true);
  check(g, 'the counter did not move on a gap', a.lastPeerN, 2);
  check(g, 'the missing move then fills the gap', verdict(a, env({ n: 3 }), 'a'), 'accept');
  const gu = guest();
  receive(gu, env({ t: 'hello', n: 1, p: {} }), 'b');
  check(g, 'a state snapshot jumps ahead (newest wins)', verdict(gu, env({ t: 'state', n: 9, p: {} }), 'b'), 'accept');
  check(g, 'an older snapshot is dropped', verdict(gu, env({ t: 'state', n: 4, p: {} }), 'b'), 'stale');
  check(g, 'the same snapshot twice is a duplicate', verdict(gu, env({ t: 'state', n: 9, p: {} }), 'b'), 'duplicate');
  check(g, 'ordered messages carry on from the snapshot', verdict(gu, env({ n: 10 }), 'b'), 'accept');
  check(g, 'req_state never moves the counter', (() => { const x = authority(); receive(x, env({ t: 'hello', sid: '', n: 1, p: {} }), 'a'); receive(x, env({ t: 'req_state', n: 40, p: undefined }), 'a'); return x.lastPeerN; })(), 1);
}
{
  const g = 'E1/E5 who may say what';
  const a = authority();
  receive(a, env({ t: 'hello', sid: '', n: 1, p: {} }), 'a');
  check(g, 'a guest may not send state', verdict(a, env({ t: 'state', n: 2, p: {} }), 'a'), 'wrong_sender');
  check(g, 'our own message coming back is dropped', verdict(a, env({ n: 2 }), 'b'), 'reflected');
  const gu = guest();
  receive(gu, env({ t: 'hello', n: 1, p: {} }), 'b');
  check(g, 'a guest refuses state from a seat that is not the authority', verdict(gu, env({ t: 'state', n: 2, p: {} }), 'c'), 'wrong_sender');
  check(g, 'a guest refuses a hello from a seat that is not the authority', verdict(guest(), env({ t: 'hello', n: 1, p: {} }), 'c'), 'wrong_sender');
}
{
  const g = 'E7 ack and the retained list';
  const a = authority();
  stamp(a, 'move', 'connect4', { c: 1 }); stamp(a, 'move', 'connect4', { c: 2 }); stamp(a, 'state', 'connect4', { x: 1 }); stamp(a, 'move', 'connect4', { c: 3 });
  check(g, 'moves are kept, a state snapshot is not', a.unacked.map((e) => e.n).join(','), '1,2,4');
  check(g, 'pendingResend lists them in order', pendingResend(a).map((e) => e.n).join(','), '1,2,4');
  receive(a, env({ t: 'hello', sid: '', n: 1, ack: 2, p: {} }), 'a');
  check(g, 'an ack frees what the peer has seen', a.unacked.map((e) => e.n).join(','), '4');
  check(g, 'an ack beyond what we sent is refused', verdict(a, env({ n: 2, ack: 99 }), 'a'), 'bad_ack');
  check(g, 'a refused ack frees nothing', a.unacked.length, 1);
  receive(a, env({ n: 2, ack: 1 }), 'a');
  check(g, 'ack never goes backwards', a.peerAck, 2);
  const b = authority();
  const e1 = stamp(b, 'hello', 'connect4', { resume: true });
  check(g, 'a stamped message has our id, count, and what we have seen', j([e1.sid, e1.n, e1.ack, e1.v]), j([SID, 1, 0, 1]));
  check(g, 'a hello is not retained', b.unacked.length, 0);
  for (let i = 0; i < MAX_UNACKED + 3; i++) stamp(b, 'move', 'connect4', { c: i });
  check(g, 'the retained list is bounded', b.unacked.length, MAX_UNACKED);
  check(g, 'and says when it dropped one', b.overflowed, true);
  check(g, 'the oldest were the ones dropped', b.unacked[0].n, 5);
}
{
  const g = 'resume across a restart';
  const gu = guest();
  receive(gu, env({ t: 'hello', n: 1, p: {} }), 'b'); receive(gu, env({ n: 2 }), 'b');
  check(g, 'the same hello again is a resume and keeps the count', (() => { receive(gu, env({ t: 'hello', n: 3, p: { resume: true } }), 'b'); return gu.lastPeerN; })(), 3);
  receive(gu, env({ t: 'hello', sid: '0123456789abcdef', n: 1, p: {} }), 'b');
  check(g, 'a dealer restarted from its save has a new id: adopted', gu.sid, '0123456789abcdef');
  check(g, 'and its counter starts again', gu.lastPeerN, 1);
  check(g, 'the new session accepts the next message', verdict(gu, env({ sid: '0123456789abcdef', n: 2 }), 'b'), 'accept');
  check(g, 'the old session is now unknown', verdict(gu, env({ n: 3 }), 'b'), 'unknown_sid');
  const a = authority();
  receive(a, env({ t: 'hello', sid: '', n: 1, p: {} }), 'a'); receive(a, env({ n: 2 }), 'a'); receive(a, env({ n: 3 }), 'a');
  receive(a, env({ t: 'hello', sid: '', n: 1, p: {} }), 'a');
  check(g, 'a guest that restarted (no session) is counted afresh', verdict(a, env({ n: 2 }), 'a'), 'accept');
}
{
  const g = 'rematch';
  const a = authority();
  receive(a, env({ t: 'hello', sid: '', n: 1, p: {} }), 'a');
  check(g, 'a rematch ask is an ordered message', verdict(a, env({ t: 'rematch', n: 2, p: undefined }), 'a'), 'accept');
  check(g, 'the same ask again is not applied twice', verdict(a, env({ t: 'rematch', n: 2, p: undefined }), 'a'), 'duplicate');
  check(g, 'an accept is ordered too', verdict(a, env({ t: 'rematch_ok', n: 3, p: undefined }), 'a'), 'accept');
  check(g, 'bye is ordered too', verdict(a, env({ t: 'bye', n: 4, p: undefined }), 'a'), 'accept');
}

// ------------------------------------------------------------ digest, hidden ---
{
  const g = 'digest (desync detection)';
  check(g, 'key order does not change the canonical form', canonicalJson({ b: 1, a: 2 }), canonicalJson({ a: 2, b: 1 }));
  check(g, 'canonical form has no whitespace and sorted keys', canonicalJson({ b: [1, { z: 1, y: 2 }], a: null }), '{"a":null,"b":[1,{"y":2,"z":1}]}');
  check(g, 'a float cannot be canonicalised', canonicalJson({ f: 1.5 }), 'null');
  check(g, 'NaN cannot be canonicalised', canonicalJson(NaN), 'null');
  check(g, 'undefined cannot be canonicalised', canonicalJson({ a: undefined }), 'null');
  check(g, 'FNV-1a of the empty string is the offset basis', fnv1a32(''), '811c9dc5');
  check(g, 'FNV-1a of "a"', fnv1a32('a'), 'e40c292c');
  check(g, 'FNV-1a of "foobar"', fnv1a32('foobar'), 'bf9cf968');
  check(g, 'a digest is 8 lowercase hex', /^[0-9a-f]{8}$/.test(stateDigest({ turn: 'a' })), true);
  check(g, 'different states give different digests', stateDigest({ turn: 'a' }) !== stateDigest({ turn: 'b' }), true);
  check(g, 'the same state gives the same digest', stateDigest({ turn: 'a', n: 1 }), stateDigest({ n: 1, turn: 'a' }));
  check(g, 'an uncanonicalisable state has no digest', stateDigest({ f: 0.5 }), 'null');
}
{
  const g = 'E6 hidden information';
  check(g, 'a clean state has no leaks', j(hiddenLeaks({ myHandForPeer: ['R7'], opponentHandCount: 6, mover: 'a' }, ['hands', ...ALWAYS_HIDDEN_KEYS])), '[]');
  check(g, 'the host never sends the hands map', j(hiddenLeaks({ hands: { a: [], b: [] } }, ['hands'])), '["hands"]');
  check(g, 'a draw pile nested deep is found', j(hiddenLeaks({ a: { list: [{ drawPile: [] }] } }, ['drawPile'])), '["drawPile"]');
  check(g, 'a seed never leaves the dealer', j(hiddenLeaks({ seed: 12345 }, ALWAYS_HIDDEN_KEYS)), '["seed"]');
  check(g, 'results are sorted and unique', j(hiddenLeaks({ rngSeed: 1, x: { seed: 2, rngSeed: 3 } }, ALWAYS_HIDDEN_KEYS)), '["rngSeed","seed"]');
}

// ------------------------------------------- shared vectors (the Dart port) ---
{
  const g = 'golden vectors';
  const onDisk = JSON.parse(readFileSync(new URL('./vectors.json', import.meta.url), 'utf8'));
  const fresh = generate();
  check(g, 'vectors.json equals a fresh generation (run: node tools/gen-playenvelope-vectors.mjs)', JSON.stringify(onDisk) === JSON.stringify(fresh), true);
  for (const k of ['parse', 'sid', 'scenarios', 'canonical', 'fnv', 'hidden'])
    check(g, `section "${k}" is present and non-empty`, Array.isArray(onDisk[k]) && onDisk[k].length > 0, true);
  check(g, 'constants are pinned for the Dart side', j(onDisk.constants), j({ maxEnvelopeBytes: 8192, maxUnacked: 32, alwaysHidden: [...ALWAYS_HIDDEN_KEYS] }));
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
