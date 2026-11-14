// The family-ledger golden vectors: a fresh generation equals the committed file, every signature verifies, and the
// properties the Dart side relies on hold (any change to the bytes changes the hash; prev order does not matter;
// maps are written in key order; a vote names one entry and no other).
import { readFileSync } from 'node:fs';
import { generate, selfCheck } from '../gen-family-ledger-vectors.mjs';
import { encodeValue, entryHash, signedBytes, publicKeyOf, edSignBytes, fromJsonValue } from '../family_ledger.mjs';

let pass = 0, fail = 0;
const ok = (cond, name) => { if (cond) pass++; else { fail++; console.error('FAIL: ' + name); } };

const file = JSON.parse(readFileSync(new URL('../../client/test/vectors/family_ledger_vectors.json', import.meta.url), 'utf8'));
ok(JSON.stringify(file.cases) === JSON.stringify(generate()), 'family_ledger_vectors.json equals a fresh generation (run node tools/gen-family-ledger-vectors.mjs)');
ok(selfCheck(file.cases), 'every signature in the file verifies');
const entries = file.cases.filter((c) => c.kind === 'entry');
ok(entries.length === 5, 'five entries');
ok(new Set(entries.map((e) => e.hash)).size === entries.length, 'every entry has its own hash');
ok(entries.every((e, i) => (i === 0 ? e.prev.length === 0 : e.prev.length === 1 && e.prev[0] === entries[i - 1].hash)), 'the entries form one chain');

const a = encodeValue({ b: 1, a: [null, true, 'x'] }), bb = encodeValue({ a: [null, true, 'x'], b: 1 });
ok(a.equals(bb), 'a map encodes in key order');
let threw = false; try { encodeValue(-1); } catch { threw = true; }
ok(threw, 'a negative integer cannot be encoded');
threw = false; try { encodeValue({ 'a b': 1 }); } catch { threw = true; }
ok(threw, 'a map key outside the allowed characters cannot be encoded');

const g = entries[0], seed = Buffer.from(g.seed, 'hex');
const mk = (overrides) => signedBytes({ type: g.type, prev: g.prev, body: fromJsonValue(g.body), signer: publicKeyOf(seed), issuedAt: g.issuedAt, ...overrides });
ok(mk({}).toString('hex') === g.bytes, 'rebuilding the genesis gives the same bytes');
const h = (bytes) => entryHash(bytes, edSignBytes(seed, bytes)).toString('hex');
ok(h(mk({ issuedAt: g.issuedAt + 1 })) !== g.hash, 'a different time gives a different hash');
ok(h(mk({ body: { ...fromJsonValue(g.body), name: 'Mum' } })) !== g.hash, 'a different body gives a different hash');
const e2 = entries[2];
const x = Buffer.alloc(32, 1).toString('hex'), y = Buffer.alloc(32, 2).toString('hex');
const sg = publicKeyOf(Buffer.from(e2.seed, 'hex'));
ok(signedBytes({ type: e2.type, prev: [x, y], body: fromJsonValue(e2.body), signer: sg, issuedAt: 1 })
  .equals(signedBytes({ type: e2.type, prev: [y, x], body: fromJsonValue(e2.body), signer: sg, issuedAt: 1 })), 'prev order does not matter');
const votes = file.cases.filter((c) => c.kind === 'vote');
ok(votes.every((v) => v.target === entries[2].hash), 'the votes name the member.add');
ok(votes[0].bytes !== votes[1].bytes && votes[0].sig !== votes[1].sig, 'yes and no votes differ');
console.log(`${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
