/**
 * Converts the five draft care guides to the ONE schema (docs/care-guides/SCHEMA.md).
 *
 *   node tools/care-guides-convert.mjs          writes the outputs
 *   node tools/care-guides-convert.mjs --check  fails if the committed outputs differ from a fresh conversion
 *
 * Reads  docs/care-guides/<id>.json                       (the originals; never modified)
 * Writes docs/care-guides/converted/<id>.json              (full, lossless, includes reviewOnly)
 *        docs/care-guides/app-draft/<id>.json              (the app-format copy, reviewOnly removed: NOT bundled)
 *        scaffold/client/assets/care_guides/index.json     (the guides the app bundles: EMPTY until a guide is REVIEWED)
 *
 * No draft is ever written under scaffold/client/assets/: the pubspec bundles that directory, so a draft there would be
 * extractable from a release APK even though the gate stops it being drawn. A reviewer promotes a guide by copying its
 * app-draft file into assets/care_guides, filling its review record and status, and listing its id in index.json
 * (docs/care-guides/SCHEMA.md, "Promoting a guide"). test/care_guide_structure_test.dart refuses any non-REVIEWED file there.
 */
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { bundleForApp, convertCareGuide } from './care_guides_lib.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
export const REPO = join(HERE, '..', '..');
export const SRC = join(REPO, 'docs', 'care-guides');
export const OUT_FULL = join(SRC, 'converted');
export const OUT_DRAFT = join(SRC, 'app-draft');
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
    files.set(join(OUT_DRAFT, `${id}.json`), json(bundleForApp(full)));
  }
  // Nothing is REVIEWED yet, so nothing is bundled.
  files.set(join(OUT_APP, 'index.json'), json({ schemaVersion: 1, guides: [] }));
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
