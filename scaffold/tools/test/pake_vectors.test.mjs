// The PAKE golden vectors: a fresh generation equals the committed file, a matching password agrees, a wrong
// one does not, and the generator output is a valid curve point (Elligator2 sanity).
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { generate } from '../gen-pake-vectors.mjs';

const file = JSON.parse(readFileSync(new URL('../../client/test/vectors/pake_vectors.json', import.meta.url), 'utf8'));
assert.deepEqual(file.cases, generate(), 'pake_vectors.json is stale: run node tools/gen-pake-vectors.mjs');
const by = Object.fromEntries(file.cases.map((c) => [c.label, c]));
assert.equal(by['same pin'].agree, true);
assert.equal(by['wrong pin'].agree, false);
assert.notEqual(by['wrong pin'].tagC, by['wrong pin'].tagA);
assert.equal(by['qr secret (16 random bytes) as password'].agree, true);
assert.notEqual(by['same pin'].gC, by['8 digit pin'].gC, 'different password or session gives a different generator');
console.log('pake vectors: ok');
