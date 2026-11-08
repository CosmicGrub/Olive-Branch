/**
 * care — golden vectors shared with the Dart port. MASTERFILE §9.6.1, S-D6.
 *
 * The behaviour of checkDose()/prnAllowed() is asserted in
 * packages/agency/test/phase12.test.mjs; THIS suite owns the cross-language
 * contract: tools/gen-care-vectors.mjs writes vectors.json from the engine, the
 * Dart port (client/test/care_vectors_test.dart) must reproduce every case, and
 * this file fails CI if the engine changes without the vectors being
 * regenerated (so the Dart test can never be silently asserting stale answers).
 */
import { readFileSync } from 'node:fs';
import { generate } from '../../../tools/gen-care-vectors.mjs';

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) }); };

const onDisk = JSON.parse(readFileSync(new URL('./vectors.json', import.meta.url), 'utf8'));
const fresh = generate();
const g = 'golden vectors';
check(g, 'vectors.json equals a fresh generation (run: node tools/gen-care-vectors.mjs)',
  JSON.stringify(onDisk) === JSON.stringify(fresh), true);

const reasons = new Set(onDisk.checkDose.map(c => c.expect.ok ? 'ok' : c.expect.reason));
for (const r of ['ok', 'unknown_slot', 'already_administered', 'too_soon', 'daily_max']) {
  check(g, `the vectors exercise the "${r}" outcome`, reasons.has(r), true);
}
check(g, 'the vectors carry a non-trivial number of dose cases', onDisk.checkDose.length >= 25, true);
check(g, 'the vectors cover prnAllowed both ways',
  new Set(onDisk.prnAllowed.map(c => c.expect)).size, 2);
check(g, 'every recorded timestamp is UTC (no zone-dependent parsing in the Dart port)',
  JSON.stringify(onDisk).match(/"administeredAt":"[^"]*"/g).every(s => s.endsWith('Z"')), true);

let cur = '';
for (const r of rows) { if (r.g !== cur) { cur = r.g; console.log(`\n${cur}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
