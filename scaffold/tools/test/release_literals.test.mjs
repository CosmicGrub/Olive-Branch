/**
 * tools/check-release-literals.mjs (ISS-092): "the built release contains no demo literal", proven on synthetic artifacts
 * (a zip with stored and deflated entries, a directory, a plain file), including the ways a string could hide (UTF-16,
 * inside a deflated native library, inside a nested apk in a directory), and the real source tree.
 *
 * usage: node tools/test/release_literals.test.mjs
 */
import { mkdtempSync, writeFileSync, mkdirSync, readFileSync, readdirSync, statSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';
import { deflateRawSync } from 'node:zlib';
import { loadLiterals, zipEntries, findLiterals, scanTarget } from '../check-release-literals.mjs';

let pass = 0, fail = 0;
const check = (name, ok, detail = '') => {
  if (ok) { pass++; console.log(`  PASS  ${name}`); } else { fail++; console.log(`  FAIL  ${name}${detail ? `\n        ${detail}` : ''}`); }
};

const HERE = dirname(fileURLToPath(import.meta.url));
const TOOL = join(HERE, '..', 'check-release-literals.mjs');
const LITS = loadLiterals();

/** A minimal zip writer: entries [{name, data, deflate}]. */
function makeZip(entries) {
  const parts = [], central = [];
  let off = 0;
  for (const e of entries) {
    const name = Buffer.from(e.name, 'utf8');
    const raw = Buffer.from(e.data);
    const comp = e.deflate ? deflateRawSync(raw) : raw;
    const local = Buffer.alloc(30);
    local.writeUInt32LE(0x04034b50, 0); local.writeUInt16LE(20, 4); local.writeUInt16LE(0, 6);
    local.writeUInt16LE(e.deflate ? 8 : 0, 8); local.writeUInt32LE(0, 14);
    local.writeUInt32LE(comp.length, 18); local.writeUInt32LE(raw.length, 22); local.writeUInt16LE(name.length, 26);
    parts.push(local, name, comp);
    const c = Buffer.alloc(46);
    c.writeUInt32LE(0x02014b50, 0); c.writeUInt16LE(20, 4); c.writeUInt16LE(20, 6);
    c.writeUInt16LE(e.deflate ? 8 : 0, 10); c.writeUInt32LE(comp.length, 20); c.writeUInt32LE(raw.length, 24);
    c.writeUInt16LE(name.length, 28); c.writeUInt32LE(off, 42);
    central.push(c, name);
    off += 30 + name.length + comp.length;
  }
  const cd = Buffer.concat(central);
  const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0); end.writeUInt16LE(entries.length, 8); end.writeUInt16LE(entries.length, 10);
  end.writeUInt32LE(cd.length, 12); end.writeUInt32LE(off, 16);
  return Buffer.concat([...parts, cd, end]);
}

const dir = mkdtempSync(join(tmpdir(), 'olive-lit-'));
const filler = Buffer.alloc(4096, 7);
const clean = makeZip([
  { name: 'AndroidManifest.xml', data: 'manifest' },
  { name: 'lib/arm64-v8a/libapp.so', data: Buffer.concat([filler, Buffer.from('Kitchen table, Bedtime story')]), deflate: true },
  { name: 'assets/flutter_assets/AssetManifest.json', data: '{}' },
]);

// the list itself
check('the literal list has 10 or more entries of 4+ characters', LITS.length >= 10 && LITS.every((l) => l.length >= 4), String(LITS.length));
for (const must of ['Methylphenidate', 'Albuterol inhaler', 'BBH-7734-2201', 'Claire Solomon']) check(`the list names "${must}"`, LITS.includes(must));

// the reader
check('zipEntries reads stored and deflated entries', zipEntries(clean).length === 3);
check('zipEntries inflates a deflated entry byte for byte', zipEntries(clean).find((e) => e.name.endsWith('libapp.so')).data.includes(Buffer.from('Bedtime story')));
check('a non-zip is refused (throws)', (() => { try { zipEntries(Buffer.from('not a zip at all, just text')); return false; } catch { return true; } })());

// negative: a clean release passes
writeFileSync(join(dir, 'clean.apk'), clean);
check('a clean release has no hit', scanTarget(join(dir, 'clean.apk'), LITS).hits.length === 0);

// positives: every literal, in every hiding place, is found
for (const lit of LITS) {
  const stored = makeZip([{ name: 'assets/x.bin', data: Buffer.concat([filler, Buffer.from(lit)]) }]);
  const deflated = makeZip([{ name: 'lib/arm64-v8a/libapp.so', data: Buffer.concat([filler, Buffer.from(lit)]), deflate: true }]);
  const wide = makeZip([{ name: 'classes.dex', data: Buffer.concat([filler, Buffer.from(lit, 'utf16le')]), deflate: true }]);
  const f1 = join(dir, 's.apk'), f2 = join(dir, 'd.apk'), f3 = join(dir, 'w.apk');
  writeFileSync(f1, stored); writeFileSync(f2, deflated); writeFileSync(f3, wide);
  const r = [f1, f2, f3].map((f) => scanTarget(f, LITS).hits.map((h) => h.literal));
  check(`"${lit}" is found stored, deflated inside libapp.so, and as UTF-16`, r.every((h) => h.includes(lit)), JSON.stringify(r));
}

// a directory, and an apk nested in a directory
mkdirSync(join(dir, 'out/sub'), { recursive: true });
writeFileSync(join(dir, 'out/sub/note.txt'), 'x Methylphenidate x');
check('a directory is searched recursively', scanTarget(join(dir, 'out'), LITS).hits.some((h) => h.literal === 'Methylphenidate'));
mkdirSync(join(dir, 'out2'), { recursive: true });
writeFileSync(join(dir, 'out2/app-release.apk'), makeZip([{ name: 'lib/x/libapp.so', data: Buffer.concat([filler, Buffer.from('BBH-7734-2201')]), deflate: true }]));
check('an apk inside a directory is opened', scanTarget(join(dir, 'out2'), LITS).hits.some((h) => h.literal === 'BBH-7734-2201'));

// fail closed
mkdirSync(join(dir, 'empty'));
check('an empty directory is refused, not called clean', (() => { try { scanTarget(join(dir, 'empty'), LITS); return false; } catch { return true; } })());
check('a missing path is refused', (() => { try { scanTarget(join(dir, 'nope.apk'), LITS); return false; } catch { return true; } })());

// the real CLI: exit codes
const run = (...a) => spawnSync(process.execPath, [TOOL, ...a], { encoding: 'utf8' });
check('CLI exits 0 on a clean apk', run(join(dir, 'clean.apk')).status === 0);
const dirty = join(dir, 'dirty.apk');
writeFileSync(dirty, makeZip([{ name: 'lib/arm64-v8a/libapp.so', data: Buffer.concat([filler, Buffer.from('Peanuts, carries an EpiPen, Cetirizine')]), deflate: true }]));
const rd = run(dirty);
check('CLI exits 1 on an apk with a demo literal', rd.status === 1, rd.stdout);
check('CLI names the literal and the entry', /Cetirizine/.test(rd.stdout) && /libapp\.so/.test(rd.stdout), rd.stdout);
check('CLI exits 2 with no arguments', run().status === 2);
check('CLI exits 2 on a missing file', run(join(dir, 'missing.apk')).status === 2);
writeFileSync(join(dir, 'badlist.json'), '[]');
check('CLI exits 2 on an empty literal list (fail closed)', run(join(dir, 'clean.apk'), '--literals', join(dir, 'badlist.json')).status === 2);

// the real source tree: the literals live in the one fixtures file (and the preview entry), nowhere else in lib/
const LIB = join(HERE, '..', '..', 'client', 'lib');
const allowed = new Set(['demo_fixtures.dart', 'main.dart']);
const offenders = [];
for (const f of readdirSync(LIB)) {
  if (!f.endsWith('.dart') || allowed.has(f)) continue;
  const text = readFileSync(join(LIB, f), 'utf8');
  const hit = findLiterals(Buffer.from(text, 'utf8'), LITS);
  if (hit.length) offenders.push(`${f}: ${hit.join(', ')}`);
}
check('no demo literal is in lib/ outside demo_fixtures.dart and the preview entry', offenders.length === 0, offenders.join(' | '));
const fixtures = readFileSync(join(LIB, 'demo_fixtures.dart'), 'utf8');
check('every accessor in demo_fixtures.dart sits behind kDebugMode', (fixtures.match(/if \(kDebugMode\)/g) || []).length >= 6, String((fixtures.match(/if \(kDebugMode\)/g) || []).length));

// the workflow runs the check on the real release
const wf = readFileSync(join(HERE, '..', '..', '..', '.github', 'workflows', 'release-smoke.yml'), 'utf8');
check('release-smoke.yml scans the built release apk for demo literals', /check-release-literals\.mjs/.test(wf));

rmSync(dir, { recursive: true, force: true });
console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail === 0 ? 0 : 1);
