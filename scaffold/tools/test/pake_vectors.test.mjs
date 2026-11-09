// The PAKE golden vectors: a fresh generation equals the committed file, a matching password agrees, a wrong
// one does not, and different passwords or sessions give different generators.
import { readFileSync } from 'node:fs';
import { generate } from '../gen-pake-vectors.mjs';

let pass = 0, fail = 0;
const ok = (cond, name) => { if (cond) pass++; else { fail++; console.error('FAIL: ' + name); } };

const file = JSON.parse(readFileSync(new URL('../../client/test/vectors/pake_vectors.json', import.meta.url), 'utf8'));
ok(JSON.stringify(file.cases) === JSON.stringify(generate()), 'pake_vectors.json equals a fresh generation (run node tools/gen-pake-vectors.mjs)');
const by = Object.fromEntries(file.cases.map((c) => [c.label, c]));
ok(by['same pin'].agree === true, 'same pin agrees');
ok(by['wrong pin'].agree === false, 'wrong pin does not agree');
ok(by['wrong pin'].tagC !== by['wrong pin'].tagA, 'wrong pin gives different tags');
ok(by['qr secret (16 random bytes) as password'].agree === true, 'qr secret agrees');
ok(by['same pin'].gC !== by['8 digit pin'].gC, 'different password or session gives a different generator');
ok(file.cases.every((c) => c.gC.length === 64 && c.Yc.length === 64 && c.Ya.length === 64), 'every point is 32 bytes');
ok(file.cases.every((c) => c.gC === c.gA || c.agree === false), 'equal generators imply the passwords matched');
console.log(`${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
