/**
 * The guided-first-run simulation guard (tools/check-sim-onboarding.mjs): the legitimate layout passes, every kind of planted
 * offender (workflow, Dockerfile, release script, device script, gradle, launch config, define file, env file, other Dart)
 * is caught, a re-spelling is caught, the reader losing or mangling the define is caught, and the real tree is clean.
 * usage: node tools/test/sim_onboarding_guard.test.mjs
 */
import { simProblems, realTreeProblems, readTree, READER } from '../check-sim-onboarding.mjs';

let pass = 0, fail = 0;
const check = (name, ok) => { if (ok) { pass++; console.log(`  PASS  ${name}`); } else { fail++; console.log(`  FAIL  ${name}`); } };

const good = () => new Map([
  [READER, "const bool kSimOnboarding = bool.fromEnvironment('OLIVE_SIM_ONBOARDING');"],
  ['scaffold/tools/device-sync.sh', 'flutter build apk --release --dart-define=OLIVE_ALLOW_DEV_CLEARTEXT=true "$@"'],
  ['scaffold/tools/cut-release.mjs', 'flutter build appbundle --release'],
  ['.github/workflows/release-smoke.yml', 'flutter build apk --release'],
  ['docs/planning/ONBOARDING-SCRIPT.md', 'the define --dart-define=OLIVE_SIM_ONBOARDING=true is dev only'],
]);
const planted = (path, text) => { const m = good(); m.set(path, text); return simProblems(m); };

check('the intended layout passes', simProblems(good()).length === 0);
check('prose documents may describe the define', simProblems(new Map([...good(), ['docs/x.html', 'OLIVE_SIM_ONBOARDING']])).length === 0);

const OFFENDER = 'flutter build apk --release --dart-define=OLIVE_SIM_ONBOARDING=true';
for (const [label, path] of [
  ['a GitHub workflow', '.github/workflows/publish.yml'],
  ['a Dockerfile', 'scaffold/Dockerfile'],
  ['a release-cut script', 'scaffold/tools/cut-release.mjs'],
  ['the device sync script', 'scaffold/tools/device-sync.sh'],
  ['another shell script', 'scaffold/tools/release-smoke.sh'],
  ['a gradle file', 'scaffold/client/android/app/build.gradle.kts'],
  ['a VS Code launch config', '.vscode/launch.json'],
  ['a dart-define-from-file JSON', 'scaffold/secrets/release.defines.json'],
  ['an env file', 'scaffold/.env.release'],
  ['a different Dart file', 'scaffold/client/lib/api_client.dart'],
  ['a docker compose file', 'scaffold/docker-compose.prod.yml'],
]) {
  check(`${label} that passes it is caught`, planted(path, OFFENDER).length === 1);
}
check('a re-spelling without the OLIVE_ prefix is caught', planted('scaffold/tools/x.sh', 'flutter build --dart-define=sim_onboarding=true').length === 1);
check('a lower-case re-spelling is caught', planted('scaffold/tools/x.sh', 'olive_sim_onboarding').length === 1);
check('the reader no longer reading the name is caught', simProblems(new Map([...good(), [READER, 'const bool k = false;']])).length === 1);
check('the reader reading a different name is caught', simProblems(new Map([...good(), [READER, "bool.fromEnvironment('OLIVE_SIM_ONBOARD')"]])).length === 1);
check('the reader only naming it in a comment is caught', simProblems(new Map([...good(), [READER, "// bool.fromEnvironment('OLIVE_SIM_ONBOARDING')\nconst bool k = false;"]])).length === 1);
check('a tree without the reader file is reported by the real-tree check', realTreeProblems('/nonexistent-root-for-test').length === 1);

const tree = readTree();
check('the real tree has the reader', tree.has(READER));
const real = realTreeProblems();
check('the real tree is clean (nothing passes the simulation define)', real.length === 0);
if (real.length) for (const p of real) console.log(`        ${p}`);

console.log(`\n  ${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
