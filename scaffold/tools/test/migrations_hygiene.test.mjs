/**
 * Migration hygiene — S-C8 (line endings) and S-D22 (references that point at
 * migrations that do not exist).
 *
 *  - A CRLF copy of EVERY migration must hash identically to the LF original, so
 *    a Windows checkout can never make the runner report "changed after being
 *    applied" (S-C8). .gitattributes must pin `*.sql text eol=lf`.
 *  - Every `migration 00NN` / `00NN_name.sql` mentioned in code comments, docs
 *    and scripts must name a migration that actually exists, and a
 *    `00NN_name.sql` must match the REAL file name for that number (S-D22).
 *    Comments citing "0042 re-states the rules" or "0019_child_message_sender"
 *    when no such file existed misled every later reader.
 *  - Migration numbers are contiguous from 0001 except for the documented gap.
 */
import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative, sep } from 'node:path';
import { fileURLToPath } from 'node:url';
import { migrationChecksum, normalizeMigrationText } from '../migrate_lib.mjs';

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) }); };

const SCAFFOLD = fileURLToPath(new URL('../../', import.meta.url));
const REPO = join(SCAFFOLD, '..');
const MIG_DIR = join(SCAFFOLD, 'db', 'migrations');
const files = readdirSync(MIG_DIR).filter(f => f.endsWith('.sql')).sort();
const byNumber = new Map(files.map(f => [f.slice(0, 4), f]));
// db/test/ holds fixtures named like migrations (0002_seed.sql); they are real files too.
const testFixtures = new Set(readdirSync(join(SCAFFOLD, 'db', 'test')).filter(f => f.endsWith('.sql')));

// ------------------------------------------------------------ S-C8 hashing --
{
  const g = 'S-C8 line endings';
  check(g, 'there are migrations to check', files.length >= 37, true);
  let identical = 0, crlfDiffers = 0, loneCr = 0;
  for (const f of files) {
    const lf = normalizeMigrationText(readFileSync(join(MIG_DIR, f), 'utf8'));
    const crlf = lf.replace(/\n/g, '\r\n');
    if (migrationChecksum(crlf) === migrationChecksum(lf)) identical++;
    if (crlf === lf) crlfDiffers++;           // only an empty file could equal its CRLF copy
    if (migrationChecksum(lf.replace(/\n/g, '\r')) !== migrationChecksum(lf)) loneCr++;
  }
  check(g, 'a CRLF copy of every migration hashes identically to the LF original', identical, files.length);
  check(g, 'a lone-CR copy (old Mac) also hashes identically', loneCr, 0);
  check(g, 'no migration is empty (the CRLF comparison above is meaningful)', crlfDiffers, 0);
  check(g, 'a leading BOM does not change the hash',
    migrationChecksum('﻿SELECT 1;\n') === migrationChecksum('SELECT 1;\n'), true);
  check(g, 'a real content change DOES change the hash',
    migrationChecksum('SELECT 1;\n') === migrationChecksum('SELECT 2;\n'), false);
  check(g, 'the hash is a 64-char hex SHA-256', /^[0-9a-f]{64}$/.test(migrationChecksum('x')), true);
  const attrs = readFileSync(join(REPO, '.gitattributes'), 'utf8');
  check(g, '.gitattributes pins *.sql to LF', /^\*\.sql\s+text\s+eol=lf\s*$/m.test(attrs), true);
  const runner = readFileSync(join(SCAFFOLD, 'tools', 'migrate.mjs'), 'utf8');
  check(g, 'the runner hashes through migrationChecksum (not a raw createHash)',
    runner.includes('migrationChecksum') && !/createHash/.test(runner), true);
}

// ------------------------------------------------------- numbering sanity ---
{
  const g = 'migration numbering';
  const nums = files.map(f => Number(f.slice(0, 4)));
  check(g, 'every file is NNNN_name.sql', files.every(f => /^\d{4}_[a-z0-9_]+\.sql$/.test(f)), true);
  check(g, 'numbers are unique', new Set(nums).size, nums.length);
  const missing = [];
  for (let n = 1; n <= nums[nums.length - 1]; n++) if (!nums.includes(n)) missing.push(n);
  // 0019 never existed (a number skipped when the guardian-invite work was
  // renumbered); any new gap must be added here on purpose.
  check(g, 'the only gaps are the documented ones (19 never existed; 39-41 are reserved for a parallel branch and absent until it merges)', missing.filter(n => ![19, 39, 40, 41].includes(n)).join(',') || 'none', 'none');
}

// ------------------------------------------------- S-D22 reference checking --
const SKIP_DIRS = new Set(['node_modules', '.git', 'build', '.dart_tool', '.gradle', '.idea', 'coverage',
  'ephemeral', '.symlinks', '.claude']);
const EXTS = /\.(ts|mjs|js|dart|md|sh|yml|yaml|sql|html|json)$/;
// Historical / narrative records that legitimately mention numbers of
// migrations that were later renumbered or that belong to other branches.
const EXEMPT = [
  'CHANGELOG.md',                       // a dated history; entries are not rewritten
  'BRANCHES.md',
  join('docs', 'superpowers') + sep,    // dated design specs
];

function walk(dir, out) {
  for (const name of readdirSync(dir)) {
    if (SKIP_DIRS.has(name)) continue;
    const p = join(dir, name);
    const st = statSync(p);
    if (st.isDirectory()) walk(p, out);
    else if (EXTS.test(name) && st.size < 2_000_000) out.push(p);
  }
}
const all = []; walk(REPO, all);
const scanned = all.filter(p => !EXEMPT.some(e => relative(REPO, p).startsWith(e) || relative(REPO, p) === e));
// Compiled output sits beside the sources and would double-report them.
const sources = scanned.filter(p => !(/[.]mjs$/.test(p) && existsSync(p.replace(/[.]mjs$/, ".ts"))));

{
  const g = 'S-D22 migration references';
  const bad = [];
  let named = 0, numbered = 0;
  for (const p of sources) {
    // The hygiene test itself quotes bad examples in its prose.
    if (p.endsWith('migrations_hygiene.test.mjs')) continue;
    const text = readFileSync(p, 'utf8');
    const rel = relative(REPO, p);
    for (const m of text.matchAll(/\b(\d{4})_([a-z][a-z0-9_]*)\.sql\b/g)) {
      named++;
      const real = byNumber.get(m[1]);
      if (real !== `${m[1]}_${m[2]}.sql` && !testFixtures.has(m[0])) bad.push(`${rel}: ${m[0]} (real file for ${m[1]}: ${real ?? 'none'})`);
    }
    for (const m of text.matchAll(/\bmigrations?\s+(\d{4})\b(?!_)/gi)) {
      numbered++;
      if (!byNumber.has(m[1])) bad.push(`${rel}: "${m[0]}" (no such migration)`);
    }
  }
  check(g, 'the scan found references to check (so a pass is not vacuous)', named > 30 && numbered > 10, true);
  check(g, 'every NNNN_name.sql and "migration NNNN" reference names a real migration',
    bad.length === 0 ? 'ok' : '\n    ' + bad.join('\n    '), 'ok');
}

let cur = '';
for (const r of rows) { if (r.g !== cur) { cur = r.g; console.log(`\n${cur}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
