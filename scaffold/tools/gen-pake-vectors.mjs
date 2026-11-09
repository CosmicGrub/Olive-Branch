// Generates client/test/vectors/pake_vectors.json: golden inputs and the outputs of tools/pake_cpace.mjs.
// The Dart port (client/lib/cpace.dart) is tested against the SAME file (client/test/pake_vectors_test.dart);
// tools/test/pake_vectors.test.mjs asserts the file equals a fresh generation.
// usage: node tools/gen-pake-vectors.mjs   (writes)   |   --print
import { writeFileSync } from 'node:fs';
import { run } from './pake_cpace.mjs';

const hex = (b) => Buffer.from(b).toString('hex');
const fill = (n, tag) => Buffer.alloc(n, tag);
const cases = [
  ['same pin', '4829', '4829', 1],
  ['wrong pin', '4829', '4830', 2],
  ['8 digit pin', '48291735', '48291735', 3],
  ['qr secret (16 random bytes) as password', hex(fill(16, 0xa5)), hex(fill(16, 0xa5)), 4],
];
export function generate() {
  return cases.map(([label, pc, pa, n]) => {
    const sid = fill(16, n), ci = Buffer.from(`ci-case-${n}`);
    const yc = fill(32, 0x10 + n), ya = fill(32, 0x20 + n);
    const r = run({ prsC: Buffer.from(pc), prsA: Buffer.from(pa), sid, ci, yc, ya });
    return {
      label, prsC: pc, prsA: pa, sid: hex(sid), ci: hex(ci), yc: hex(yc), ya: hex(ya),
      gC: hex(r.gC), gA: hex(r.gA), Yc: hex(r.Yc), Ya: hex(r.Ya), iskC: hex(r.iskC), iskA: hex(r.iskA),
      tagC: hex(r.tagC), tagA: hex(r.tagA), sas: hex(r.sas), agree: hex(r.iskC) === hex(r.iskA),
    };
  });
}
if (process.argv[1]?.endsWith('gen-pake-vectors.mjs')) {
  const out = JSON.stringify({ generatedBy: 'tools/gen-pake-vectors.mjs', cases: generate() }, null, 1) + String.fromCharCode(10);
  if (process.argv.includes('--print')) process.stdout.write(out);
  else writeFileSync(new URL('../client/test/vectors/pake_vectors.json', import.meta.url), out);
}
