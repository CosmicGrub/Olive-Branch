/**
 * The simulate-connect guard (tools/check-simulate-connect.mjs): the legitimate layout passes, every kind of planted offender is
 * caught, the device script mangling or defaulting the define is caught, and the real tree is clean.
 * usage: node tools/test/sim_connect_guard.test.mjs
 */
import { simulateProblems, realTreeProblems, DEVICE_SCRIPT } from '../check-simulate-connect.mjs';

let pass = 0, fail = 0;
const check = (name, ok) => { if (ok) { pass++; console.log(`  PASS  ${name}`); } else { fail++; console.log(`  FAIL  ${name}`); } };

const DEV = 'SIM_ARGS=()\nif [ "${SIMULATE_CONNECT:-}" = 1 ]; then SIM_ARGS=(--dart-define=OLIVE_SIMULATE_CONNECT=true); fi\nflutter build apk\n';
const good = () => new Map([
  [DEVICE_SCRIPT, DEV],
  ['scaffold/client/lib/connect_simulation.dart', "const bool k = bool.fromEnvironment('OLIVE_SIMULATE_CONNECT');"],
  ['scaffold/tools/cut-release.mjs', 'flutter build appbundle --release'],
  ['.github/workflows/release-smoke.yml', 'flutter build apk --release --dart-define=OLIVE_API_BASE_URL=http://10.0.2.2:8123'],
  ['MASTERFILE.md', 'the define --dart-define=OLIVE_SIMULATE_CONNECT=true is dev only'],
]);
const planted = (path, text) => { const m = good(); m.set(path, text); return simulateProblems(m); };

check('the intended layout passes', simulateProblems(good()).length === 0);
check('prose documents may describe the define', simulateProblems(new Map([...good(), ['docs/x.html', 'OLIVE_SIMULATE_CONNECT']])).length === 0);
check('a device script that never passes it is fine (it is optional)', (() => { const m = good(); m.set(DEVICE_SCRIPT, 'flutter build apk\n'); return simulateProblems(m).length === 0; })());

const OFFENDER = 'flutter build apk --release --dart-define=OLIVE_SIMULATE_CONNECT=true';
for (const [label, path] of [
  ['a GitHub workflow', '.github/workflows/publish.yml'],
  ['a Dockerfile', 'scaffold/Dockerfile'],
  ['a release-cut script', 'scaffold/tools/cut-release.mjs'],
  ['another shell script', 'scaffold/tools/release-smoke.sh'],
  ['a gradle file', 'scaffold/client/android/app/build.gradle.kts'],
  ['a VS Code launch config', '.vscode/launch.json'],
  ['a dart-define-from-file JSON', 'scaffold/secrets/release.defines.json'],
  ['an env file', 'scaffold/.env.release'],
  ['a different Dart file', 'scaffold/client/lib/child_connect_screen.dart'],
]) {
  const p = planted(path, label === 'a dart-define-from-file JSON' ? '{"OLIVE_SIMULATE_CONNECT":"true"}' : OFFENDER);
  check(`planted in ${label} is caught and named`, p.length === 1 && p[0].startsWith(path));
}
check('a re-spelled / lower-cased name still trips it', planted('scaffold/tools/x.sh', 'olive_simulate_connect=true').length === 1);
check('a CRLF offender is caught', planted('scaffold/tools/x.sh', OFFENDER.replace(/ /g, '\r\n')).length === 1);

const wrongVal = good(); wrongVal.set(DEVICE_SCRIPT, 'if [ "${SIMULATE_CONNECT:-}" = 1 ]; then A=(--dart-define=OLIVE_SIMULATE_CONNECT=1); fi\n');
check('device script passing =1 FAILS (bool.fromEnvironment needs exactly true)', simulateProblems(wrongVal).length >= 1);
const byDefault = good(); byDefault.set(DEVICE_SCRIPT, 'flutter build apk --dart-define=OLIVE_SIMULATE_CONNECT=true\n');
check('device script passing it by default FAILS (it must be asked for)', simulateProblems(byDefault).length === 1);
const commented = good(); commented.set(DEVICE_SCRIPT, '# --dart-define=OLIVE_SIMULATE_CONNECT=true\nflutter build apk\n');
check('a commented-out define in the device script does not count', simulateProblems(commented).length === 0);
check('a Windows path separator is normalised', simulateProblems(new Map([[DEVICE_SCRIPT.replace(/\//g, '\\'), DEV], ['.github\\workflows\\a.yml', OFFENDER]])).length === 1);

const real = realTreeProblems();
check('the real tree is clean', real.length === 0);
if (real.length) console.log(real.join('\n'));

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
