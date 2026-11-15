// Generates client/test/vectors/pake_vectors.json: golden inputs and the outputs of tools/pake_cpace.mjs
// (CPace draft-21 CPACE-X25519-SHA512 plus Olive's confirmation layer). These are Olive's OWN end-to-end cases;
// the draft's published vectors live in client/test/vectors/cpace_draft21_vectors.json (tools/test/cpace_draft21.test.mjs).
// The Dart port (client/lib/cpace.dart) is tested against the SAME file (client/test/pake_vectors_test.dart);
// tools/test/pake_vectors.test.mjs asserts the file equals a fresh generation.
// usage: node tools/gen-pake-vectors.mjs   (writes)   |   --print
import { writeFileSync } from 'node:fs';
import { run, channelId } from './pake_cpace.mjs';

const hex = (b) => Buffer.from(b).toString('hex');
const fill = (n, tag) => Buffer.alloc(n, tag);
// A real-shaped channel identifier: child key, adult key fingerprint, family id, adult display name.
const parts = { cpk: fill(32, 0xc5), afp: fill(16, 0xaf), fid: 'fam-1', an: 'Mom' };
const cases = [
  ['same pin', '4829', '4829', 1],
  ['wrong pin', '4829', '4830', 2],
  ['8 digit pin', '48291735', '48291735', 3],
  ['qr secret (16 random bytes) as password', hex(fill(16, 0xa5)), hex(fill(16, 0xa5)), 4],
  ['channel identifier built from the pairing fields', '4829', '4829', 5],
];
export function generate() {
  return cases.map(([label, pc, pa, n]) => {
    const sid = fill(16, n);
    const channel = n === 5;
    const ci = channel ? channelId(parts) : Buffer.from(`ci-case-${n}`);
    const yc = fill(32, 0x10 + n), ya = fill(32, 0x20 + n);
    const r = run({ prsC: Buffer.from(pc), prsA: Buffer.from(pa), sid, ci, yc, ya });
    return {
      label, prsC: pc, prsA: pa, sid: hex(sid), ci: hex(ci), yc: hex(yc), ya: hex(ya),
      ...(channel ? { ciParts: { cpk: hex(parts.cpk), afp: hex(parts.afp), fid: parts.fid, an: parts.an } } : {}),
      gC: hex(r.gC), gA: hex(r.gA), Yc: hex(r.Yc), Ya: hex(r.Ya), iskC: hex(r.iskC), iskA: hex(r.iskA),
      tagC: hex(r.tagC), tagA: hex(r.tagA), sas: hex(r.sas), match: hex(r.match), agree: hex(r.iskC) === hex(r.iskA),
    };
  });
}
if (process.argv[1]?.endsWith('gen-pake-vectors.mjs')) {
  const out = JSON.stringify({ generatedBy: 'tools/gen-pake-vectors.mjs', cases: generate() }, null, 1) + String.fromCharCode(10);
  if (process.argv.includes('--print')) process.stdout.write(out);
  else writeFileSync(new URL('../client/test/vectors/pake_vectors.json', import.meta.url), out);
}
