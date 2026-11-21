/**
 * The tail of tools/verify.sh (tools/verify-finish.sh + tools/check-markup.mjs --skip-total).
 *
 * ISS-023. The exact-total gate (C7: MARKUP quotes the computed total, D2: the demo manifest does) was reporting one
 * failing suite as THREE failures: the suite, then C7, then D2, because the failed suite pulled the computed total
 * below the figures and the two documents "disagreed" with a number that was not final. This proves, against the real
 * MARKUP, CHANGELOG and demo manifest and the real scripts:
 *
 *   A  check-markup: with --skip-total C7 and D2 are SKIP (not FAIL); with a wrong --total both FAIL; with the right
 *      --total both PASS. Everything else it checks is identical in all three runs.
 *   B  verify-finish.sh, driven with synthetic counts the way verify.sh calls it:
 *        - one failed suite  -> NOT GREEN, exactly that one problem, C7/D2 not reported as failures, no APPLY figure;
 *        - all green, stale figures -> strict: C7 and D2 fail, and the APPLY line names the command and the total;
 *        - all green, right figures -> ALL GREEN with the APPLY line;
 *        - a suite that ran nothing counts as a failure (the total is not final then either).
 *
 * The comparison is always against a baseline run, so an unrelated drift elsewhere in the correspondence check does
 * not make this suite fail for a reason it is not about.
 */
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) }); };

const here = dirname(fileURLToPath(import.meta.url));
const SCAFFOLD = join(here, '..', '..');
const run = (cmd, args) => spawnSync(cmd, args, { cwd: SCAFFOLD, encoding: 'utf8', timeout: 120000 });

// check-markup reads the generated DEMO.html (git-ignored output of demo/build.mjs); verify.sh builds it after this
// suite runs, so build it here exactly as verify.sh does.
const built = run(process.execPath, ['demo/build.mjs']);
check('0 setup', 'the demo builds (check-markup reads it)', built.status, 0);

const figure = Number(/<strong>(\d+) assertions<\/strong>/.exec(readFileSync(join(SCAFFOLD, '..', 'MARKUP.html'), 'utf8'))[1]);
const rowsOf = (out) => Object.fromEntries([...out.matchAll(/^\s+(PASS|FAIL|SKIP)\s+(\S+)\s/gm)].map((m) => [m[2], m[1]]));
const failing = (r) => Object.keys(r).filter((k) => r[k] === 'FAIL').sort();

// ---- A · check-markup --------------------------------------------------------------------------------------------
const skip = run(process.execPath, ['tools/check-markup.mjs', '--skip-total']);
const wrong = run(process.execPath, ['tools/check-markup.mjs', '--total', '1']);
const right = run(process.execPath, ['tools/check-markup.mjs', '--total', String(figure)]);
const rs = rowsOf(skip.stdout), rw = rowsOf(wrong.stdout), rr = rowsOf(right.stdout);
const baseline = failing(rs); // whatever is already drifting for reasons unrelated to the total
{
  const g = 'A check-markup';
  check(g, 'C7 and D2 are both reported SKIP with --skip-total', `${rs.C7}/${rs.D2}`, 'SKIP/SKIP');
  check(g, 'a skipped check is not a failure: --skip-total fails only on what already drifts', failing(rs).join(','), baseline.join(','));
  check(g, 'with a wrong --total both C7 and D2 FAIL', `${rw.C7}/${rw.D2}`, 'FAIL/FAIL');
  check(g, 'with a wrong --total exactly those two are added to the baseline', failing(rw).join(','), [...baseline, 'C7', 'D2'].sort().join(','));
  check(g, 'with the figure the documents quote, C7 and D2 PASS', `${rr.C7}/${rr.D2}`, 'PASS/PASS');
  check(g, 'every other check reports the same in all three runs',
    Object.keys(rs).filter((k) => k !== 'C7' && k !== 'D2').every((k) => rs[k] === rw[k] && rs[k] === rr[k]), true);
  check(g, 'the skip is stated in the output, not silent', /SKIPPED \(a suite failed/.test(skip.stdout), true);
  check(g, 'the real figure is a plausible assertion count (a vacuous read would pass anything)', figure > 1000, true);
}

// ---- B · verify-finish.sh ----------------------------------------------------------------------------------------
const finish = (p, f, problems) => run('bash', ['tools/verify-finish.sh', String(p), String(f), String(problems)]);
const text = (r) => r.stdout + r.stderr;
const problemsIn = (out) => Number(/NOT GREEN — (\d+) suite/.exec(out)?.[1] ?? 0);
{
  const g = 'B one failing suite';
  const r = finish(figure - 7, 1, 1);
  const rows2 = rowsOf(text(r));
  const extra = baseline.length ? 1 : 0; // an unrelated drift adds its own single problem
  check(g, 'the run is NOT GREEN (exit 1)', r.status, 1);
  check(g, 'it reports exactly one failing suite, not three', problemsIn(text(r)), 1 + extra);
  check(g, 'C7 and D2 are not reported as failures', rows2.C7 !== 'FAIL' && rows2.D2 !== 'FAIL', true);
  check(g, 'it says why they were skipped', /C7\/D2, the assertion-count checks, were skipped|SKIP\s+C7/.test(text(r)), true);
  check(g, 'no APPLY command is offered for a total that is not final', /APPLY  withheld/.test(text(r)) && !/apply-total\.mjs \d/.test(text(r)), true);
  check(g, 'the computed total is still shown', new RegExp(`COMPUTED TOTAL\\s+${figure - 7} passed\\s+1 failed`).test(text(r)), true);
}
{
  const g = 'B a suite that ran nothing';
  const r = finish(figure, 0, 1);
  check(g, 'it is NOT GREEN and the total is not final (no APPLY figure)', `${r.status}/${/APPLY  withheld/.test(text(r))}`, '1/true');
}
{
  const g = 'B all green, figures stale';
  const r = finish(figure + 12, 0, 0);
  const rows2 = rowsOf(text(r));
  check(g, 'the gate stays strict: NOT GREEN', r.status, 1);
  check(g, 'C7 and D2 both FAIL', `${rows2.C7}/${rows2.D2}`, 'FAIL/FAIL');
  check(g, 'the APPLY line names the command and the computed total', text(r).includes(`APPLY  node tools/apply-total.mjs ${figure + 12}`), true);
  check(g, 'the stale-figure failure is one problem (markup drift), not one per figure', problemsIn(text(r)), 1);
}
{
  const g = 'B all green, figures current';
  const r = finish(figure, 0, 0);
  const rows2 = rowsOf(text(r));
  check(g, 'C7 and D2 do not fail (the correspondence step passes, or fails only on an unrelated drift)',
    baseline.length ? rows2.C7 !== 'FAIL' && rows2.D2 !== 'FAIL' : /markup correspondence\s+\d+ passed\s+0 failed/.test(text(r)), true);
  check(g, 'the APPLY line is printed with the total', text(r).includes(`APPLY  node tools/apply-total.mjs ${figure}`), true);
  check(g, baseline.length ? 'exit status follows the unrelated drift (not green)' : 'ALL GREEN, exit 0',
    `${r.status}/${/ALL GREEN/.test(text(r))}`, baseline.length ? '1/false' : '0/true');
}
{
  const g = 'B arguments';
  check(g, 'non-integer arguments are refused (exit 2)', finish('x', 0, 0).status, 2);
  check(g, 'missing arguments are refused', run('bash', ['tools/verify-finish.sh']).status !== 0, true);
}

let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(60)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
