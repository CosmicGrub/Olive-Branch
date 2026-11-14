/**
 * Converts the five draft care guides to the ONE schema (docs/care-guides/SCHEMA.md).
 *
 *   node tools/care-guides-convert.mjs          writes the outputs
 *   node tools/care-guides-convert.mjs --check  fails if the committed outputs differ from a fresh conversion
 *
 * Reads  docs/care-guides/<id>.json                       (the originals; never modified)
 * Writes docs/care-guides/converted/<id>.json              (full, lossless, includes reviewOnly)
 *        scaffold/client/assets/care_guides/<id>.json      (what the app bundles; reviewOnly removed)
 *        scaffold/client/assets/care_guides/index.json     (ids, in library order)
 */
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { bundleForApp, convertCareGuide } from './care_guides_lib.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
export const REPO = join(HERE, '..', '..');
export const SRC = join(REPO, 'docs', 'care-guides');
export const OUT_FULL = join(SRC, 'converted');
export const OUT_APP = join(REPO, 'scaffold', 'client', 'assets', 'care_guides');
// Library order. who-to-call first: it is the emergency guide.
export const GUIDE_IDS = ['who-to-call', 'choking', 'head-injury', 'high-fever', 'childproofing-home'];

const json = (o) => JSON.stringify(o, null, 2) + '\n';

export function buildAll() {
  const files = new Map();
  for (const id of GUIDE_IDS) {
    const original = JSON.parse(readFileSync(join(SRC, `${id}.json`), 'utf8'));
    const full = convertCareGuide(original);
    files.set(join(OUT_FULL, `${id}.json`), json(full));
    files.set(join(OUT_APP, `${id}.json`), json(bundleForApp(full)));
  }
  files.set(join(OUT_APP, 'index.json'), json({ schemaVersion: 1, guides: GUIDE_IDS }));
  return files;
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const files = buildAll();
  if (process.argv.includes('--check')) {
    const flat = (p) => readFileSync(p, 'utf8').replaceAll(String.fromCharCode(13, 10), String.fromCharCode(10));
    const stale = [...files].filter(([p, t]) => !existsSync(p) || flat(p) !== t).map(([p]) => p);
    if (stale.length) { console.error('stale outputs, re-run tools/care-guides-convert.mjs:\n' + stale.join('\n')); process.exit(1); }
    console.log(`care guides: ${files.size} outputs are current`);
  } else {
    for (const [p, t] of files) { mkdirSync(dirname(p), { recursive: true }); writeFileSync(p, t); }
    console.log(`care guides: wrote ${files.size} files`);
  }
}
