/**
 * tools/list-test-failures.sh -- names every failing test in a
 * `flutter test --reporter compact` log.
 *
 * The fixtures reproduce the REAL reporter output byte for byte in structure
 * (progress lines overwritten with a bare \r, " [E]" on a failing test's line,
 * "To run this test again" blocks), captured from a real flutter test run with
 * one expectation failure, one thrown error and a test whose own name contains
 * "-2". The old verify.sh looked for a "Failing tests:" section the reporter never
 * prints, so a red run named nothing.
 */
import { spawnSync } from 'node:child_process';
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) }); };

const here = dirname(fileURLToPath(import.meta.url));
const SH = join(here, '..', 'list-test-failures.sh').replace(/\\/g, '/');
const pad = (s) => s + ' '.repeat(Math.max(0, 100 - s.length));
const CR = '\r';
// one compact-reporter progress "frame"
const frame = (t, p, f, name, e = false) =>
  `${CR}${t} +${p}${f ? ` -${f}` : ''}: ${name}${e ? ' [E]' : ''}`.replace(/(\S)$/, '$1');

const FILE = 'test/zz_tmp_fail_test.dart';
const realRun = [
  frame('00:00', 0, 0, `loading ${FILE}`),
  frame('00:04', 0, 0, `loading ${FILE}`),
  frame('00:04', 0, 0, 'first passes'),
  frame('00:04', 1, 0, 'first passes'),
  frame('00:04', 1, 0, 'grp this one fails -2 odd name'),
  pad(frame('00:04', 1, 1, 'grp this one fails -2 odd name', true)) + '\n',
  `\nTo run this test again: dart test ${FILE} -p vm --plain-name "grp this one fails -2 odd name"\n`,
  frame('00:04', 1, 1, 'grp this one throws'),
  pad(frame('00:04', 1, 2, 'grp this one throws', true)) + '\n',
  `\nTo run this test again: dart test ${FILE} -p vm --plain-name "grp this one throws"\n`,
  frame('00:04', 1, 2, 'last passes'),
  frame('00:04', 2, 2, 'last passes'),
  frame('00:04', 2, 2, 'Some tests failed.') + '\n',
].join('');

const allGreen = [
  frame('00:01', 0, 0, 'a'), frame('00:01', 1, 0, 'a'), frame('00:02', 1, 0, 'b'),
  frame('00:02', 2, 0, 'All tests passed!') + '\n',
].join('');

const run = (text, args = []) => {
  const dir = mkdtempSync(join(tmpdir(), 'ltf-'));
  try {
    const f = join(dir, 'log.txt');
    writeFileSync(f, text);
    const viaFile = spawnSync('bash', [SH, ...args, f.replace(/\\/g, '/')], { encoding: 'utf8' });
    const viaStdin = spawnSync('bash', [SH, ...args], { encoding: 'utf8', input: text });
    return { file: viaFile, stdin: viaStdin };
  } finally { rmSync(dir, { recursive: true, force: true }); }
};

{
  const g = 'A real reporter output';
  const r = run(realRun);
  check(g, 'names BOTH failing tests (expectation failure and thrown error)',
    r.file.stdout, 'FAILED: grp this one fails -2 odd name\nFAILED: grp this one throws\n');
  check(g, 'reading stdin gives the identical answer', r.stdin.stdout, r.file.stdout);
  check(g, 'exit 0 when names were listed', r.file.status, 0);
  check(g, 'a test whose NAME contains "-2" is reported by name, not mistaken for a counter',
    /fails -2 odd name/.test(r.file.stdout), true);
  check(g, 'passing tests are not listed', /passes/.test(r.file.stdout), false);
  check(g, 'the "To run this test again" lines are not listed', /To run/.test(r.file.stdout), false);
}
{
  const g = 'B no failures';
  const r = run(allGreen);
  check(g, 'an all-green log prints nothing', r.file.stdout, '');
  check(g, 'and exits 0', r.file.status, 0);
  check(g, 'an empty log prints nothing and exits 0', `${run('').file.status}/${run('').file.stdout.length}`, '0/0');
}
{
  const g = 'C edge cases';
  const loadFail = [frame('00:01', 0, 0, `loading ${FILE}`),
    pad(frame('00:02', 0, 1, `loading ${FILE}`, true)) + '\n',
    'Failed to load: compile error\n', frame('00:02', 0, 1, 'Some tests failed.') + '\n'].join('');
  check(g, 'a test FILE that fails to load/compile is named', run(loadFail).file.stdout, `FAILED: loading ${FILE}\n`);

  const dup = [pad(frame('00:02', 0, 1, 'same name', true)) + '\n', pad(frame('00:03', 0, 2, 'same name', true)) + '\n'].join('');
  check(g, 'the same test reported twice is listed once', run(dup).file.stdout, 'FAILED: same name\n');

  const brackets = pad(frame('00:02', 3, 1, 'case [E] inside the name', true)) + '\n';
  check(g, 'a name that itself contains "[E]" is kept whole',
    run(brackets).file.stdout, 'FAILED: case [E] inside the name\n');

  const fake = '00:01 +5 -3: this stray line is not a progress frame because it was not emitted by the reporter [E]x\n';
  check(g, '"[E]" not at the END of a frame is not a failure', run(fake).file.stdout, '');

  const crlf = realRun.replace(/\n/g, '\r\n');
  check(g, 'a CRLF-converted log (Windows capture) still yields both names',
    run(crlf).file.stdout, 'FAILED: grp this one fails -2 odd name\nFAILED: grp this one throws\n');

  const unnamed = frame('00:04', 2, 2, 'last passes') + frame('00:04', 2, 2, 'Some tests failed.') + '\n';
  const u = run(unnamed);
  check(g, 'counter says failed but no name could be extracted -> exit 3 (caller must fall back to the raw log)',
    u.file.status, 3);
  check(g, '...and prints nothing that could be mistaken for a name', u.file.stdout, '');

  const many = Array.from({ length: 500 }, (_, i) => pad(frame('00:09', i, i + 1, `t${i}`, true)) + '\n').join('');
  check(g, '500 failures are all listed', run(many).file.stdout.trim().split('\n').length, 500);

  const bad = spawnSync('bash', [SH, '/no/such/file.log'], { encoding: 'utf8' });
  check(g, 'unreadable file -> exit 2', bad.status, 2);
  const two = spawnSync('bash', [SH, 'a', 'b'], { encoding: 'utf8' });
  check(g, 'too many arguments -> exit 2', two.status, 2);
}

let gname = '';
for (const r of rows) {
  if (r.g !== gname) { gname = r.g; console.log(`\n${gname}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${JSON.stringify(r.e)}, got ${JSON.stringify(r.a)}`));
}
console.log(`\n${'-'.repeat(60)}\n${pass} passed, ${fail} failed\n`);
process.exitCode = fail === 0 ? 0 : 1;
