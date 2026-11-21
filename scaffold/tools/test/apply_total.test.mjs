/**
 * tools/apply-total.mjs -- writes CI's COMPUTED TOTAL into the two documents that quote it.
 *
 * Proves (ISS-023): it rewrites EXACTLY the two figures (the MARKUP "N assertions" and the demo manifest's
 * "assertions": N), leaves every other byte alone including the line endings, refuses (writing nothing) when a file
 * does not hold exactly one figure or when the total is not a plain positive integer, and works as a real CLI on a
 * scratch copy of the repository layout.
 */
import { spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, copyFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { applyTotal, parseTotal, FIGURES } from '../apply-total.mjs';

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) }); };

const MARKUP = (n, nl) => ['<p class="meta">', 'screens <strong>136</strong> · <strong>' + n + ' assertions</strong> green at this version.</p>',
  '<td>19994 elsewhere is prose, not the figure</td>', '<tr><td>0.51.0</td></tr>', ''].join(nl);
const SHELL = (n, nl) => ['<script type="application/json" id="tl-manifest">', '{', '  "version": "0.51.0",', `  "assertions": ${n},`,
  '  "covers": {}', '}', '</script>', ''].join(nl);
const texts = (n, nl) => ({ 'MARKUP.html': MARKUP(n, nl), 'scaffold/demo/shell.html': SHELL(n, nl) });
const count = (s, re) => (s.match(re) ?? []).length;

// ---- A · the pure core ----------------------------------------------------------------------------------------
for (const [label, nl] of [['CRLF', '\r\n'], ['LF', '\n']]) {
  const g = `A core (${label})`;
  const before = texts(19994, nl);
  const r = applyTotal(before, 20041);
  check(g, 'MARKUP figure rewritten, nothing else', r.texts['MARKUP.html'], MARKUP(20041, nl));
  check(g, 'demo manifest figure rewritten, nothing else', r.texts['scaffold/demo/shell.html'], SHELL(20041, nl));
  check(g, 'the reported "before" figures are the old ones', `${r.before['MARKUP.html']}/${r.before['scaffold/demo/shell.html']}`, '19994/19994');
  check(g, 'the same number in prose (not the figure) is untouched',
    r.texts['MARKUP.html'].includes('<td>19994 elsewhere is prose, not the figure</td>'), true);
  check(g, 'CRLF count unchanged', count(r.texts['MARKUP.html'], /\r\n/g), count(before['MARKUP.html'], /\r\n/g));
  check(g, 'bare LF count unchanged', count(r.texts['MARKUP.html'], /(?<!\r)\n/g), count(before['MARKUP.html'], /(?<!\r)\n/g));
}
{
  const g = 'A core';
  const same = applyTotal(texts(20041, '\r\n'), 20041);
  check(g, 'applying the figure already there changes nothing', same.texts['MARKUP.html'] === MARKUP(20041, '\r\n'), true);
  const grow = applyTotal(texts(999, '\r\n'), 20041);
  check(g, 'a figure may change width', grow.texts['MARKUP.html'].includes('<strong>20041 assertions</strong>'), true);
}

// ---- B · all or nothing ---------------------------------------------------------------------------------------
{
  const g = 'B refusals';
  const t = texts(19994, '\r\n');
  const throws = (x, total = 5) => { try { applyTotal(x, total); return 'no throw'; } catch (e) { return e.message.includes('exactly one') ? 'exactly-one' : e.message; } };
  check(g, 'a MARKUP with no figure is refused', throws({ ...t, 'MARKUP.html': 'nothing here\r\n' }), 'exactly-one');
  check(g, 'a MARKUP with two figures is refused', throws({ ...t, 'MARKUP.html': t['MARKUP.html'] + t['MARKUP.html'] }), 'exactly-one');
  check(g, 'a demo manifest with no figure is refused', throws({ ...t, 'scaffold/demo/shell.html': '{}' }), 'exactly-one');
  check(g, 'a demo manifest with two figures is refused',
    throws({ ...t, 'scaffold/demo/shell.html': t['scaffold/demo/shell.html'] + t['scaffold/demo/shell.html'] }), 'exactly-one');
  check(g, 'a missing file is refused', throws({ 'MARKUP.html': t['MARKUP.html'] }).includes('not provided'), true);
  const bad = ['0', '-5', '1e3', '12.5', '20,041', ' 20041', '', 'abc', '007', '99999999999'];
  check(g, 'a total that is not a plain positive integer is refused',
    bad.filter((b) => { try { parseTotal(b); return true; } catch { return false; } }).join('|') || 'none', 'none');
  check(g, 'a plain positive integer is accepted', parseTotal('20041'), 20041);
  check(g, 'the two figures are the only two the tool knows', FIGURES.map((f) => f.file).join(','), 'MARKUP.html,scaffold/demo/shell.html');
}

// ---- C · the real CLI on a scratch layout ---------------------------------------------------------------------
{
  const g = 'C cli';
  const here = dirname(fileURLToPath(import.meta.url));
  const base = mkdtempSync(join(tmpdir(), 'apply-total-'));
  try {
    mkdirSync(join(base, 'scaffold', 'tools'), { recursive: true });
    mkdirSync(join(base, 'scaffold', 'demo'), { recursive: true });
    copyFileSync(join(here, '..', 'apply-total.mjs'), join(base, 'scaffold', 'tools', 'apply-total.mjs'));
    const tool = join(base, 'scaffold', 'tools', 'apply-total.mjs');
    const put = (nl, n) => {
      writeFileSync(join(base, 'MARKUP.html'), MARKUP(n, nl));
      writeFileSync(join(base, 'scaffold', 'demo', 'shell.html'), SHELL(n, nl));
    };
    const run = (...a) => spawnSync(process.execPath, [tool, ...a], { encoding: 'utf8' });
    const read = (f) => readFileSync(join(base, f), 'utf8');

    put('\r\n', 19994);
    const r1 = run('20050');
    check(g, 'exit 0 and both files named',
      `${r1.status}/${/MARKUP\.html: 19994 -> 20050/.test(r1.stdout)}/${/shell\.html: 19994 -> 20050/.test(r1.stdout)}`, '0/true/true');
    check(g, 'MARKUP.html on disk: figure rewritten, CRLF kept', read('MARKUP.html') === MARKUP(20050, '\r\n'), true);
    check(g, 'shell.html on disk: figure rewritten, CRLF kept', read('scaffold/demo/shell.html') === SHELL(20050, '\r\n'), true);
    const r2 = run('20050');
    check(g, 'running it again is a no-op', `${r2.status}/${/nothing to do/.test(r2.stdout)}`, '0/true');
    check(g, '--check says ok when current', run('20050', '--check').status, 0);
    check(g, '--check exits 1 when stale and writes nothing', `${run('20051', '--check').status}/${read('MARKUP.html') === MARKUP(20050, '\r\n')}`, '1/true');

    put('\n', 19994);
    run('7');
    check(g, 'an LF checkout (CI on Linux) stays LF', read('MARKUP.html') === MARKUP(7, '\n') && read('scaffold/demo/shell.html') === SHELL(7, '\n'), true);

    put('\r\n', 19994);
    writeFileSync(join(base, 'scaffold', 'demo', 'shell.html'), 'no figure here\r\n');
    const r3 = run('20060');
    check(g, 'a file with no figure: exit 2 and NEITHER file written', `${r3.status}/${read('MARKUP.html') === MARKUP(19994, '\r\n')}`, '2/true');
    check(g, 'a bad total: exit 2', run('twenty').status, 2);
    const r4 = run();
    check(g, 'no argument: exit 2 with usage', `${r4.status}/${/usage/.test(r4.stderr)}`, '2/true');
  } finally { rmSync(base, { recursive: true, force: true }); }
}

let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(60)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
