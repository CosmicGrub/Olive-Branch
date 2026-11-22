/**
 * The dev call-simulation guard (tools/check-dev-call-sim.mjs): the legitimate layout passes, every kind of planted
 * offender (workflow, Dockerfile, release script, gradle, launch config, define file, env file, another script,
 * another Dart file) is caught, the device script passing the define WITHOUT its opt-in (or not at all, or with a
 * wrong value) is caught, and the real tree is clean.
 * usage: node tools/test/dev_call_sim_guard.test.mjs
 */
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { callSimProblems, realTreeProblems, readTree, DEVICE_SCRIPT } from '../check-dev-call-sim.mjs';

let pass = 0, fail = 0;
const check = (name, ok) => { if (ok) { pass++; console.log(`  PASS  ${name}`); } else { fail++; console.log(`  FAIL  ${name}`); } };

const DEV = 'SIM_ARGS=()\nif [ "${OLIVE_DEV_CALL_SIM:-}" = "1" ]; then\n  SIM_ARGS=(--dart-define=OLIVE_DEV_CALL_SIM=true)\nfi\nflutter build apk --release "${SIM_ARGS[@]}"\n';
const good = () => new Map([
  [DEVICE_SCRIPT, DEV],
  ['scaffold/client/lib/call_dev_sim.dart', "const bool kDevCallSim = bool.fromEnvironment('OLIVE_DEV_CALL_SIM');"],
  ['scaffold/client/lib/child_home_live.dart', 'if (kDevCallSim) const DevCallSimBar();'],
  ['scaffold/tools/cut-release.mjs', 'flutter build appbundle --release'],
  ['.github/workflows/release-smoke.yml', 'flutter build apk --release --dart-define=OLIVE_API_BASE_URL=http://10.0.2.2:8123'],
  ['MASTERFILE.md', 'the define --dart-define=OLIVE_DEV_CALL_SIM=true is dev only'],
]);
const planted = (path, text) => { const m = good(); m.set(path, text); return callSimProblems(m); };

check('the intended layout passes', callSimProblems(good()).length === 0);
check('prose documents may describe the define', callSimProblems(new Map([...good(), ['docs/x.html', 'OLIVE_DEV_CALL_SIM']])).length === 0);

const OFFENDER = 'flutter build apk --release --dart-define=OLIVE_DEV_CALL_SIM=true';
for (const [label, path] of [
  ['a GitHub workflow', '.github/workflows/publish.yml'],
  ['a Dockerfile', 'scaffold/Dockerfile'],
  ['a release-cut script', 'scaffold/tools/cut-release.mjs'],
  ['another shell script', 'scaffold/tools/release-smoke.sh'],
  ['a gradle file', 'scaffold/client/android/app/build.gradle.kts'],
  ['a VS Code launch config', '.vscode/launch.json'],
  ['a dart-define-from-file JSON', 'scaffold/secrets/release.defines.json'],
  ['an env file', 'scaffold/.env.release'],
  ['a different Dart file', 'scaffold/client/lib/api_client.dart'],
  ['a docker compose file', 'scaffold/docker-compose.prod.yml'],
]) {
  const p = planted(path, label === 'a dart-define-from-file JSON' ? '{"OLIVE_DEV_CALL_SIM":"true"}' : OFFENDER);
  check(`planted in ${label} is caught and named`, p.length === 1 && p[0].startsWith(path));
}
check('a re-spelled / lower-cased name still trips it', planted('scaffold/tools/x.sh', 'olive_dev_call_sim=true').length === 1);
check('a CRLF offender is caught', planted('scaffold/tools/x.sh', OFFENDER.replace(/ /g, '\r\n')).length === 1);

const unconditional = good(); unconditional.set(DEVICE_SCRIPT, 'flutter build apk --release --dart-define=OLIVE_DEV_CALL_SIM=true\n');
check('device script passing the define with NO opt-in FAILS (every device build would carry the strip)', callSimProblems(unconditional).length === 1);
const wrongTest = good(); wrongTest.set(DEVICE_SCRIPT, 'if [ -n "$SOMETHING" ]; then\n  SIM_ARGS=(--dart-define=OLIVE_DEV_CALL_SIM=true)\nfi\n');
check('device script with a different test above it FAILS', callSimProblems(wrongTest).length === 1);
const farAway = good(); farAway.set(DEVICE_SCRIPT, 'if [ "${OLIVE_DEV_CALL_SIM:-}" = "1" ]; then\n  echo a\n  echo b\n  echo c\nfi\nSIM_ARGS=(--dart-define=OLIVE_DEV_CALL_SIM=true)\n');
check('the opt-in test must be directly above the define, not somewhere earlier', callSimProblems(farAway).length === 1);
const noDefine = good(); noDefine.set(DEVICE_SCRIPT, 'flutter build apk --release\n');
check('device script that drops the define FAILS (the strip would silently never appear)', callSimProblems(noDefine).length === 1);
const wrongVal = good(); wrongVal.set(DEVICE_SCRIPT, 'if [ "${OLIVE_DEV_CALL_SIM:-}" = "1" ]; then\n  SIM_ARGS=(--dart-define=OLIVE_DEV_CALL_SIM=1)\nfi\n');
check('device script passing =1 FAILS (bool.fromEnvironment needs exactly true)', callSimProblems(wrongVal).length === 1);
const commented = good(); commented.set(DEVICE_SCRIPT, '# --dart-define=OLIVE_DEV_CALL_SIM=true\nflutter build apk\n');
check('a commented-out define in the device script does not count', callSimProblems(commented).length === 1);
check('a Windows path separator is normalised', callSimProblems(new Map([[DEVICE_SCRIPT.replace(/\//g, '\\'), DEV], ['.github\\workflows\\a.yml', OFFENDER]])).length === 1);

const tmp = mkdtempSync(join(tmpdir(), 'olive-callsim-'));
try {
  const put = (rel, text) => { const f = join(tmp, rel); mkdirSync(dirname(f), { recursive: true }); writeFileSync(f, text); };
  for (const [p, t] of good()) put(p, t);
  put('.github/workflows/evil.yml', OFFENDER);
  put('node_modules/pkg/x.sh', OFFENDER);          // vendored: skipped
  put('scaffold/client/build/o.txt', OFFENDER);    // build output: skipped
  writeFileSync(join(tmp, 'scaffold/client/blob.bin'), Buffer.from([0, 1, 2, 79, 76, 73]));
  const tree = readTree(tmp);
  const problems = callSimProblems(tree);
  check('a planted dot-folder workflow is found in a real directory tree', problems.length === 1 && problems[0].startsWith('.github/workflows/evil.yml'));
  check('vendored and build trees are skipped', !tree.has('node_modules/pkg/x.sh') && !tree.has('scaffold/client/build/o.txt'));
  check('binary files do not break the walk', !tree.has('scaffold/client/blob.bin'));
  check('realTreeProblems reports a missing device script rather than passing', realTreeProblems(join(tmp, 'nowhere')).length === 1);
} finally { rmSync(tmp, { recursive: true, force: true }); }

const real = realTreeProblems();
check('the real repository is clean', real.length === 0);
if (real.length) for (const p of real) console.log('        ' + p);

console.log(`\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
