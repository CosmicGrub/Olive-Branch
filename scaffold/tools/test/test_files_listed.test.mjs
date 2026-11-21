/**
 * Guard: a test file that tools/verify.sh does not run is not a test, it is a file.
 *
 * ISS-030: three suites (the game-sync table, the game_tables wiring, the family-ledger vectors) existed, passed
 * locally and were never run by CI, so a regression in any of them merged green. Nothing noticed, because nothing
 * compared the files on disk with the list verify.sh runs. This does.
 *
 * Rule: every `*.test.mjs`, `*_test.mjs` and `*.test.sql` under scaffold/ (outside node_modules and build output) is
 * either named in verify.sh or listed in ALLOW below WITH A REASON. The Dart tests are not subject to this: one
 * `flutter test` runs everything under client/test.
 *
 * The detector is a pure function and is tested on synthetic inputs first, so "fails on an unlisted file" is proven,
 * not assumed; then it is applied to the real tree.
 */
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join, relative, sep, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) }); };

/**
 * Files that are deliberately NOT run by verify.sh. Path (relative to scaffold/, forward slashes) -> why.
 * Empty on purpose: add an entry only with a real reason, never to make this test pass.
 */
export const ALLOW = {};

export const isTestFile = (p) => /(\.test\.mjs|_test\.mjs|\.test\.sql)$/.test(p);

const esc = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
/** The whole path as a token (not as the tail of a longer path, not as the head of a longer name). */
export const isReferenced = (f, text) => new RegExp(`(^|[\\s"'|=(])${esc(f)}(?=$|[\\s"'|;)\\\\])`).test(text);

/** Returns the test files that are neither referenced in `verifyText` nor allow-listed. */
export function findUnlisted(files, verifyText, allow = ALLOW) {
  return files.filter(isTestFile).filter((f) => !isReferenced(f, verifyText) && !Object.hasOwn(allow, f)).sort();
}

const SKIP = new Set(['node_modules', '.git', 'dist', 'build', 'coverage', '.dart_tool', '.gradle']);
function walk(dir, out = []) {
  for (const name of readdirSync(dir)) {
    if (SKIP.has(name)) continue;
    const full = join(dir, name);
    const st = statSync(full);
    if (st.isDirectory()) walk(full, out); else out.push(full);
  }
  return out;
}

// ---- A · the detector, on synthetic input ---------------------------------------------------------------------
{
  const g = 'A detector';
  const verify = 'tools/test/a.test.mjs\n"x|server/test/b_test.mjs"\ndb/test/0001_c.test.sql';
  check(g, 'a listed file is fine', findUnlisted(['tools/test/a.test.mjs'], verify, {}).join(), '');
  check(g, 'an unlisted *.test.mjs is reported', findUnlisted(['tools/test/new.test.mjs'], verify, {}).join(), 'tools/test/new.test.mjs');
  check(g, 'an unlisted *_test.mjs is reported', findUnlisted(['server/test/other_test.mjs'], verify, {}).join(), 'server/test/other_test.mjs');
  check(g, 'an unlisted *.test.sql is reported', findUnlisted(['db/test/0009_z.test.sql'], verify, {}).join(), 'db/test/0009_z.test.sql');
  check(g, 'a listed _test.mjs and .test.sql are fine', findUnlisted(['server/test/b_test.mjs', 'db/test/0001_c.test.sql'], verify, {}).join(), '');
  check(g, 'an allow-listed file is not reported', findUnlisted(['tools/test/new.test.mjs'], verify, { 'tools/test/new.test.mjs': 'why' }).join(), '');
  check(g, 'a helper that is not a test file is ignored', findUnlisted(['tools/test/helper.mjs', 'db/test/0002_seed.sql'], verify, {}).join(), '');
  check(g, 'a longer name that starts with a listed one is not thereby listed',
    findUnlisted(['tools/test/a.test.mjs.bak.test.mjs'], verify, {}).length, 1);
  check(g, 'the same file name under another directory is not thereby listed',
    findUnlisted(['other/tools/test/a.test.mjs', 'x/server/test/b_test.mjs'], verify, {}).length, 2);
  check(g, 'several unlisted files are all reported, sorted',
    findUnlisted(['z.test.mjs', 'a.test.mjs'], '', {}).join(), 'a.test.mjs,z.test.mjs');
}

// ---- B · the real tree ----------------------------------------------------------------------------------------
{
  const g = 'B tree';
  const here = dirname(fileURLToPath(import.meta.url));
  const root = join(here, '..', '..');
  const files = walk(root).map((f) => relative(root, f).split(sep).join('/')).filter(isTestFile);
  const verifyText = readFileSync(join(root, 'tools', 'verify.sh'), 'utf8');
  check(g, `the walk found the repository's test files (${files.length}; a vacuous walk would pass anything)`, files.length > 100, 'true');
  check(g, 'every test file is run by tools/verify.sh or allow-listed with a reason',
    findUnlisted(files, verifyText).join(', ') || 'none', 'none');
  check(g, 'the three suites ISS-030 named are now run',
    ['packages/game-sync/test/table.test.mjs', 'server/test/game_tables.test.mjs', 'tools/test/family_ledger_vectors.test.mjs']
      .filter((f) => !isReferenced(f, verifyText)).join() || 'none', 'none');
  check(g, 'every allow-list entry names a real test file',
    Object.keys(ALLOW).filter((f) => !files.includes(f)).join() || 'none', 'none');
  check(g, 'every allow-list entry has a reason of at least a sentence',
    Object.entries(ALLOW).filter(([, why]) => typeof why !== 'string' || why.trim().length < 20).map(([f]) => f).join() || 'none', 'none');
  check(g, 'no allow-list entry is also run by verify.sh (a stale excuse hides the next omission)',
    Object.keys(ALLOW).filter((f) => isReferenced(f, verifyText)).join() || 'none', 'none');
}

let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(60)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
