/**
 * packages/game-sync/test/relay_envelope.test.mjs — the sealed relay envelope
 * (server-snoop hardening, spec section 4.2): pure parse/bucket/tripwire logic
 * and the table-level `applySealedFrame` rules. The wire behaviour with real
 * sockets lives in server/test/sealed_relay.test.mjs.
 */
import { randomBytes } from 'node:crypto';
import {
  ENVELOPE_BUCKETS, ENVELOPE_VERSION, SEALED_GAME, MAX_SEQ, MAX_ENVELOPE_FRAME_BYTES,
  b64urlLength, looksLikePlaintext, parseEnvelope, toRelayed,
} from '../src/relay_envelope.mjs';
import {
  createTable, redeemJoin, applySealedFrame, applyIncomingMove, newTableId, tableIdLeaks,
} from '../src/table.mjs';

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) }); };

const ct = (n) => randomBytes(n).toString('base64url');
const env = (over = {}) => ({ v: 1, t: 'sealed', seq: 0, ct: ct(256), ...over });

// ---- A · constants ---------------------------------------------------------
check('A constants', 'version is 1', ENVELOPE_VERSION, 1);
check('A constants', 'the game id is sealed-v1', SEALED_GAME, 'sealed-v1');
check('A constants', 'buckets are 256/1024/4096', ENVELOPE_BUCKETS.join(','), '256,1024,4096');
check('A constants', 'base64url length of 256 bytes is 342', b64urlLength(256), 342);
check('A constants', 'the frame cap covers the largest bucket plus framing',
  MAX_ENVELOPE_FRAME_BYTES >= b64urlLength(4096) + 40, 'true');

// ---- B · accepted shapes ---------------------------------------------------
for (const size of ENVELOPE_BUCKETS) {
  const r = parseEnvelope(env({ ct: ct(size) }));
  check('B accept', `a ${size}-byte random ciphertext is accepted`, r.ok, 'true');
  check('B accept', `...and decodes to exactly ${size} bytes`, r.ok && r.bytes.length, size);
}
check('B accept', 'seq 0 and MAX_SEQ are valid', [0, MAX_SEQ].every((s) => parseEnvelope(env({ seq: s })).ok), 'true');

// ---- C · deny-by-default ---------------------------------------------------
const deny = (name, value, reason) => check('C deny', name, (() => {
  const r = parseEnvelope(value); return r.ok ? 'accepted' : r.reason; })(), reason);
deny('null', null, 'not_object');
deny('an array', [1], 'not_object');
deny('a string', 'x', 'not_object');
deny('a plaintext field alongside the envelope is refused (move)', { ...env(), move: [1, 2] }, 'bad_keys');
deny('a client-declared seat is refused', { ...env(), seat: 1 }, 'bad_keys');
deny('a hand field is refused', { ...env(), hand: ['A', 'K'] }, 'bad_keys');
deny('a contentId field is refused', { ...env(), contentId: 'abc' }, 'bad_keys');
deny('a missing key is refused', { v: 1, t: 'sealed', seq: 0 }, 'bad_keys');
deny('version 2 is refused', env({ v: 2 }), 'bad_version');
deny('type move is refused', env({ t: 'move' }), 'bad_type');
deny('negative seq', env({ seq: -1 }), 'bad_seq');
deny('fractional seq', env({ seq: 1.5 }), 'bad_seq');
deny('string seq', env({ seq: '1' }), 'bad_seq');
deny('seq past uint32', env({ seq: MAX_SEQ + 1 }), 'bad_seq');
deny('non-string ct', env({ ct: 5 }), 'bad_ct');
deny('ct with a space', env({ ct: ct(256).slice(0, -1) + ' ' }), 'bad_ct');
deny('ct with padding characters', env({ ct: ct(256).slice(0, -1) + '=' }), 'bad_ct');
deny('ct of an unlisted size (300 bytes)', env({ ct: ct(300) }), 'bad_bucket');
deny('ct of 255 bytes', env({ ct: ct(255) }), 'bad_bucket');
deny('ct of 8192 bytes', env({ ct: ct(8192) }), 'bad_bucket');
deny('empty ct', env({ ct: '' }), 'bad_ct');
{
  // Non-canonical spelling of the same bytes: flip the unused low bits of the last char.
  const good = ct(256);
  const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
  const last = alphabet.indexOf(good.at(-1));
  const alt = alphabet[(last & ~3) | ((last + 1) & 3)];
  check('C deny', 'a non-canonical base64url spelling is refused',
    alt === good.at(-1) ? 'skipped' : (parseEnvelope(env({ ct: good.slice(0, -1) + alt })).ok ? 'accepted' : 'refused'),
    alt === good.at(-1) ? 'skipped' : 'refused');
}

// ---- D · plaintext tripwire ------------------------------------------------
const pad = (s, n) => Buffer.concat([Buffer.from(s), Buffer.alloc(n - Buffer.byteLength(s), 0x20)]).toString('base64url');
deny('JSON padded with spaces to a bucket', env({ ct: pad('{"type":"move","from":[1,2],"to":[3,4]}', 256) }), 'plaintext_suspected');
deny('a padded hand of cards', env({ ct: pad(JSON.stringify({ hand: ['AS', 'KH', '7D'] }), 1024) }), 'plaintext_suspected');
deny('256 zero bytes', env({ ct: Buffer.alloc(256).toString('base64url') }), 'plaintext_suspected');
deny('a repeating 4-byte pattern', env({ ct: Buffer.from('abcd'.repeat(64)).toString('base64url') }), 'plaintext_suspected');
deny('256 bytes of one value', env({ ct: Buffer.alloc(256, 0xff).toString('base64url') }), 'plaintext_suspected');
{
  let wrongly = 0;
  for (let i = 0; i < 5000; i++) if (looksLikePlaintext(randomBytes(256))) wrongly++;
  check('D tripwire', 'no false positive across 5000 random 256-byte ciphertexts', wrongly, 0);
  wrongly = 0;
  for (let i = 0; i < 300; i++) if (looksLikePlaintext(randomBytes(4096))) wrongly++;
  check('D tripwire', 'no false positive across 300 random 4096-byte ciphertexts', wrongly, 0);
  check('D tripwire', 'an empty buffer counts as plaintext', looksLikePlaintext(new Uint8Array(0)), 'true');
}

// ---- E · what the relay forwards ------------------------------------------
{
  const e = parseEnvelope(env({ seq: 7 }));
  const out = toRelayed(e.env, 1);
  check('E relayed', 'the server attaches dir, the client never declares it', out.dir, 1);
  check('E relayed', 'the relayed frame has only type, v, dir, seq, ct',
    Object.keys(out).sort().join(','), 'ct,dir,seq,type,v');
  check('E relayed', 'ct is passed through byte for byte', out.ct, e.env.ct);
}

// ---- F · table-level rules -------------------------------------------------
const ADULT = { kind: 'adult', userId: 'u1', roleName: 'guardian' };
const KID = { kind: 'child', childId: 'c1' };
const NOW = 1_000_000;
function activeTable(game) {
  let t = createTable({ game, principals: [KID, ADULT], now: NOW });
  const r0 = redeemJoin(t, { tableId: t.id, seat: 0, principal: KID }, NOW + 1);
  const r1 = redeemJoin(r0.table, { tableId: t.id, seat: 1, principal: ADULT }, NOW + 2);
  return r1.table;
}
{
  const sealed = activeTable('sealed-v1');
  check('F table', 'a sealed table reaches active like any other', sealed.status, 'active');
  check('F table', 'seats start at lastSeq -1', sealed.seats.map((s) => s.lastSeq).join(','), '-1,-1');
  const a = applySealedFrame(sealed, 0, 0, NOW + 10);
  check('F table', 'seq 0 from seat 0 is accepted', a.ok, 'true');
  check('F table', '...and recorded as that seat\'s lastSeq', a.table.seats[0].lastSeq, 0);
  check('F table', '...without touching the other direction', a.table.seats[1].lastSeq, -1);
  const replay = applySealedFrame(a.table, 0, 0, NOW + 11);
  check('F table', 'a replayed seq is refused', replay.ok ? 'accepted' : replay.reason, 'seq_not_increasing');
  const back = applySealedFrame(a.table, 0, 0 - 1 + 0, NOW + 11);
  check('F table', 'a lower seq is refused', back.ok ? 'accepted' : back.reason, 'seq_not_increasing');
  const gap = applySealedFrame(a.table, 0, 50, NOW + 12);
  check('F table', 'a gap forward is allowed (a dropped frame is not an attack)', gap.ok, 'true');
  const other = applySealedFrame(a.table, 1, 0, NOW + 12);
  check('F table', 'the other direction has its own counter', other.ok, 'true');
  check('F table', 'the sealed table has no turn: either seat may send, repeatedly',
    [1, 2, 3].every((s) => applySealedFrame(a.table, 0, s, NOW + 12).ok), 'true');
}
{
  // rate limit: burst of 8 then refused
  let t = activeTable('sealed-v1'); let ok = 0, last = '';
  for (let i = 0; i < 12; i++) {
    const r = applySealedFrame(t, 0, i, NOW + 20);
    t = r.table; if (r.ok) ok++; else last = r.reason;
  }
  check('F table', 'a burst past the bucket is rate limited', `${ok}/${last}`, '8/rate_limited');
  check('F table', 'a rate-limited frame does not advance lastSeq', t.seats[0].lastSeq, 7);
}
{
  const pending = createTable({ game: 'sealed-v1', principals: [KID, ADULT], now: NOW });
  const r = applySealedFrame(pending, 0, 0, NOW);
  check('F table', 'a pending table refuses frames', r.ok ? 'accepted' : r.reason, 'table_not_active');
  const plain = activeTable('checkers');
  const w = applySealedFrame(plain, 0, 0, NOW + 5);
  check('F table', 'a checkers table refuses sealed frames (no mode mixing)', w.ok ? 'accepted' : w.reason, 'wrong_mode');
  const mv = applyIncomingMove(activeTable('sealed-v1'), 0,
    { type: 'move', from: [0, 0], to: [1, 1], continues: false }, NOW + 5);
  check('F table', 'a sealed table refuses plaintext moves (no downgrade)', mv.ok ? 'accepted' : mv.reason, 'table_not_active');
}
{
  const id = newTableId();
  check('F table', 'room ids are capabilities: t_ + 192 random bits', /^t_[A-Za-z0-9_-]{32}$/.test(id), 'true');
  check('F table', 'a room id never embeds a user or child id',
    tableIdLeaks(id, ['u1', 'c1']), 'false');
  check('F table', 'ids do not repeat across 1000 draws', new Set(Array.from({ length: 1000 }, newTableId)).size, 1000);
}

let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail ? 1 : 0);
