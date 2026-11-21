/**
 * The first-run-preview guard (tools/check-dev-first-run.mjs): the legitimate layout passes, every kind of planted
 * offender is caught, the device script passing it unconditionally or mangled is caught, and the real tree is clean.
 * usage: node tools/test/dev_first_run_guard.test.mjs
 */
import { firstRunProblems, realTreeProblems, DEVICE_SCRIPT } from '../check-dev-first-run.mjs';

let pass = 0, fail = 0;
const check = (name, ok) => { if (ok) { pass++; console.log(`  PASS  ${name}`); } else { fail++; console.log(`  FAIL  ${name}`); } };

const OPT = 'if [ "${OLIVE_DEV_FIRST_RUN_PREVIEW:-}" = 1 ]; then';
const DEV = [
  'FIRSTRUN_ARGS=()',
  OPT,
  '  FIRSTRUN_ARGS=(--dart-define=OLIVE_DEV_GUARDIAN_FIRST_RUN=true)',
  'fi',
  'flutter build apk --release "${FIRSTRUN_ARGS[@]}"',
  '',
].join('\n');
const good = () => new Map([
  [DEVICE_SCRIPT, DEV],
  ['scaffold/client/lib/dev_first_run_preview.dart', "const bool k = bool.fromEnvironment('OLIVE_DEV_GUARDIAN_FIRST_RUN');"],
  ['scaffold/tools/cut-release.mjs', 'flutter build appbundle --release'],
  ['MASTERFILE.md', 'the define --dart-define=OLIVE_DEV_GUARDIAN_FIRST_RUN=true is dev only'],
]);
const planted = (path, text) => { const m = good(); m.set(path, text); return firstRunProblems(m); };

check('the intended layout passes', firstRunProblems(good()).length === 0);
check('prose documents may describe the define', firstRunProblems(new Map([...good(), ['docs/x.html', 'OLIVE_DEV_GUARDIAN_FIRST_RUN']])).length === 0);

const OFFENDER = 'flutter build apk --release --dart-define=OLIVE_DEV_GUARDIAN_FIRST_RUN=true';
for (const [label, path] of [
  ['a GitHub workflow', '.github/workflows/publish.yml'],
  ['a Dockerfile', 'scaffold/Dockerfile'],
  ['a release-cut script', 'scaffold/tools/cut-release.mjs'],
  ['another shell script', 'scaffold/tools/release-smoke.sh'],
  ['a gradle file', 'scaffold/client/android/app/build.gradle.kts'],
  ['a launch config', '.vscode/launch.json'],
  ['an env file', 'scaffold/.env.release'],
  ['a different Dart file', 'scaffold/client/lib/main_live.dart'],
]) {
  const p = planted(path, OFFENDER);
  check(`planted in ${label} is caught and named`, p.length === 1 && p[0].startsWith(path));
}
check('a re-spelled / lower-cased name still trips it', planted('scaffold/tools/x.sh', 'olive_dev_guardian_first_run=true').length === 1);

const always = good(); always.set(DEVICE_SCRIPT, 'flutter build apk --dart-define=OLIVE_DEV_GUARDIAN_FIRST_RUN=true\n');
check('the device script passing it unconditionally FAILS', firstRunProblems(always).length === 1);
const none = good(); none.set(DEVICE_SCRIPT, 'flutter build apk\n');
check('the device script that lost it FAILS', firstRunProblems(none).length === 1);
const wrongVal = good(); wrongVal.set(DEVICE_SCRIPT, DEV.replace('=true', '=1'));
check('the device script passing =1 FAILS', firstRunProblems(wrongVal).length >= 1);
const twice = good(); twice.set(DEVICE_SCRIPT, DEV + OPT + '\n  X=(--dart-define=OLIVE_DEV_GUARDIAN_FIRST_RUN=true)\nfi\n');
check('the device script passing it twice FAILS', firstRunProblems(twice).length === 1);
const commented = good(); commented.set(DEVICE_SCRIPT, '# --dart-define=OLIVE_DEV_GUARDIAN_FIRST_RUN=true\nflutter build apk\n');
check('a commented-out define does not count', firstRunProblems(commented).length === 1);
const crlf = good(); crlf.set(DEVICE_SCRIPT, DEV.replace(/\n/g, '\r\n'));
check('a CRLF device script still passes', firstRunProblems(crlf).length === 0);

const real = realTreeProblems();
check('the real tree is clean', real.length === 0);
if (real.length) for (const p of real) console.log(`        ${p}`);

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
