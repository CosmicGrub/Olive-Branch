#!/usr/bin/env node
/**
 * apply-total.mjs -- write CI's COMPUTED TOTAL into the two places that quote it.
 *
 * tools/verify.sh sums what every suite reported and prints
 *
 *     COMPUTED TOTAL   20007 passed   0 failed
 *     APPLY  node tools/apply-total.mjs 20007
 *
 * Two documents quote that figure and tools/check-markup.mjs (C7, D2) holds them to it:
 *
 *     MARKUP.html            <strong>N assertions</strong>
 *     scaffold/demo/shell.html   "assertions": N,
 *
 * Until now a PR that added or removed one test failed C7 and D2, someone hand-typed two numbers, and a second
 * 18-23 minute CI round ran just to see them agree. This is that edit as a tool: it rewrites exactly those two
 * figures and nothing else.
 *
 *   - Exactly one figure per file. Zero or several matches in either file is an error and NOTHING is written
 *     (all or nothing), so a reformatted document cannot be half-edited.
 *   - Line endings are preserved byte for byte. Both files are CRLF in this repository; the figure is replaced in
 *     place and no newline is touched.
 *   - It never invents a total. The argument is the number verify.sh printed (a plain positive integer; the
 *     "COMPUTED TOTAL" of a run where a suite failed is not final and verify.sh does not print an APPLY line then).
 *
 * Usage: node tools/apply-total.mjs <total> [--check]
 *   --check   report whether the two figures already equal <total>; write nothing; exit 1 if they do not.
 */
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const REPO = fileURLToPath(new URL('../../', import.meta.url));

/** The two quoted figures: file (relative to the repository root), the pattern, and how to rebuild the match. */
export const FIGURES = [
  { file: 'MARKUP.html', re: /(<strong>)(\d+)( assertions<\/strong>)/g },
  { file: 'scaffold/demo/shell.html', re: /("assertions"\s*:\s*)(\d+)(\s*,)/g },
];

/** A total must be a plain positive integer: no sign, no separators, no leading zero, not NaN. */
export function parseTotal(arg) {
  if (typeof arg !== 'string' || !/^[1-9]\d{0,8}$/.test(arg)) {
    throw new Error(`total must be a plain positive integer (the number verify.sh printed), got ${JSON.stringify(arg)}`);
  }
  return Number(arg);
}

/**
 * Pure core. `texts` maps each FIGURES file to its content. Returns { texts, before } where `texts` holds the rewritten
 * content and `before` the figure each file quoted. Throws, having changed nothing, if any file does not contain
 * exactly one figure.
 */
export function applyTotal(texts, total) {
  const next = {};
  const before = {};
  for (const { file, re } of FIGURES) {
    const text = texts[file];
    if (typeof text !== 'string') throw new Error(`${file}: not provided`);
    const matches = [...text.matchAll(new RegExp(re.source, 'g'))];
    if (matches.length !== 1) {
      throw new Error(`${file}: expected exactly one quoted assertion figure, found ${matches.length}; nothing was written`);
    }
    before[file] = Number(matches[0][2]);
    next[file] = text.replace(new RegExp(re.source), (_m, a, _n, c) => `${a}${total}${c}`);
  }
  return { texts: next, before };
}

function main(argv) {
  const check = argv.includes('--check');
  const args = argv.filter((a) => !a.startsWith('--'));
  if (args.length !== 1) {
    console.error('usage: node tools/apply-total.mjs <total> [--check]');
    return 2;
  }
  let total;
  try { total = parseTotal(args[0]); } catch (e) { console.error(e.message); return 2; }

  const texts = {};
  for (const { file } of FIGURES) texts[file] = readFileSync(REPO + file, 'utf8');
  let res;
  try { res = applyTotal(texts, total); } catch (e) { console.error(e.message); return 2; }

  const stale = FIGURES.filter(({ file }) => res.before[file] !== total);
  if (check) {
    for (const { file } of FIGURES) console.log(`${res.before[file] === total ? 'ok   ' : 'STALE'}  ${file} quotes ${res.before[file]}`);
    return stale.length ? 1 : 0;
  }
  if (!stale.length) { console.log(`both figures already say ${total}; nothing to do`); return 0; }
  for (const { file } of stale) {
    writeFileSync(REPO + file, res.texts[file]);
    console.log(`${file}: ${res.before[file]} -> ${total}`);
  }
  return 0;
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) process.exit(main(process.argv.slice(2)));
