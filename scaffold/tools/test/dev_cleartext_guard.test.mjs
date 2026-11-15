/**
 * The dev-cleartext guard (tools/check-dev-cleartext.mjs): the legitimate layout passes, every kind of planted
 * offender (workflow, Dockerfile, release script, gradle, launch config, define file, env file, other script, Dart)
 * is caught, the device script losing or mangling the define is caught, and the real tree is clean.
 * usage: node tools/test/dev_cleartext_guard.test.mjs
 */
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { cleartextProblems, realTreeProblems, readTree, DEVICE_SCRIPT } from '../check-dev-cleartext.mjs';

let pass = 0, fail = 0;
const check = (name, ok) => { if (ok) { pass++; console.log(`  PASS  ${name}`); } else { fail++; console.log(`  FAIL  ${name}`); } };

const DEV = 'flutter build apk --release --dart-define=OLIVE_ALLOW_SCREENSHOTS=true --dart-define=OLIVE_ALLOW_DEV_CLEARTEXT=true "$@"\n';
const good = () => new Map([
  [DEVICE_SCRIPT, DEV],
  ['scaffold/client/lib/server_transport_policy.dart', "const bool k = bool.fromEnvironment('OLIVE_ALLOW_DEV_CLEARTEXT');"],
  ['scaffold/tools/cut-release.mjs', 'flutter build appbundle --release'],
  ['.github/workflows/release-smoke.yml', 'flutter build apk --release --dart-define=OLIVE_API_BASE_URL=http://10.0.2.2:8123'],
  ['MASTERFILE.md', 'the define --dart-define=OLIVE_ALLOW_DEV_CLEARTEXT=true is dev only'],
]);
const planted = (path, text) => { const m = good(); m.set(path, text); return cleartextProblems(m); };

check('the intended layout passes', cleartextProblems(good()).length === 0);
check('prose documents may describe the define', cleartextProblems(new Map([...good(), ['docs/x.html', 'OLIVE_ALLOW_DEV_CLEARTEXT']])).length === 0);

const OFFENDER = 'flutter build apk --release --dart-define=OLIVE_ALLOW_DEV_CLEARTEXT=true';
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
  const p = planted(path, label === 'a dart-define-from-file JSON' ? '{"OLIVE_ALLOW_DEV_CLEARTEXT":"true"}' : OFFENDER);
  check(`planted in ${label} is caught and named`, p.length === 1 && p[0].startsWith(path));
}
check('a re-spelled / lower-cased name still trips it', planted('scaffold/tools/x.sh', 'olive_allow_dev_cleartext=true').length === 1);
check('a CRLF offender is caught', planted('scaffold/tools/x.sh', OFFENDER.replace(/ /g, '\r\n')).length === 1);
check('two offenders give two problems', (() => { const m = good(); m.set('a.sh', OFFENDER); m.set('b.yml', OFFENDER); return cleartextProblems(m).length === 2; })());

const noDefine = good(); noDefine.set(DEVICE_SCRIPT, 'flutter build apk --release\n');
check('device script that drops the define FAILS (the lane would break silently)', cleartextProblems(noDefine).length === 1);
const wrongVal = good(); wrongVal.set(DEVICE_SCRIPT, 'flutter build apk --dart-define=OLIVE_ALLOW_DEV_CLEARTEXT=1\n');
check('device script passing =1 FAILS (bool.fromEnvironment needs exactly true)', cleartextProblems(wrongVal).length === 1);
const trueish = good(); trueish.set(DEVICE_SCRIPT, 'flutter build apk --dart-define=OLIVE_ALLOW_DEV_CLEARTEXT=trueish\n');
check('device script passing =trueish FAILS', cleartextProblems(trueish).length === 1);
const commented = good(); commented.set(DEVICE_SCRIPT, '# --dart-define=OLIVE_ALLOW_DEV_CLEARTEXT=true\nflutter build apk\n');
check('a commented-out define in the device script does not count', cleartextProblems(commented).length === 1);
check('a Windows path separator is normalised', cleartextProblems(new Map([[DEVICE_SCRIPT.replace(/\//g, '\\'), DEV], ['.github\\workflows\\a.yml', OFFENDER]])).length === 1);

// A real directory tree, written to disk, to prove readTree/realTreeProblems see planted files in dot-folders,
// skip vendored trees and survive binary files.
const tmp = mkdtempSync(join(tmpdir(), 'olive-cleartext-'));
try {
  const put = (rel, text) => { const f = join(tmp, rel); mkdirSync(dirname(f), { recursive: true }); writeFileSync(f, text); };
  put(DEVICE_SCRIPT, DEV);
  put('.github/workflows/ok.yml', 'run: flutter build apk --release\n');
  put('node_modules/pkg/x.sh', OFFENDER);
  writeFileSync(join(tmp, 'blob.bin'), Buffer.from([0, 1, 2, 0x4f]));
  check('a clean temp tree passes (vendored trees and binaries skipped)', realTreeProblems(tmp).length === 0);
  put('.github/workflows/bad.yml', 'run: ' + OFFENDER + '\n');
  const p = realTreeProblems(tmp);
  check('a workflow planted on disk is caught by the tree walk', p.length === 1 && p[0].startsWith('.github/workflows/bad.yml'));
  check('readTree reports forward-slash relative paths', [...readTree(tmp).keys()].includes('.github/workflows/bad.yml'));
  rmSync(join(tmp, DEVICE_SCRIPT));
  check('a tree without the device script is reported, not silently passed', realTreeProblems(tmp).length === 1);
} finally { rmSync(tmp, { recursive: true, force: true }); }

const real = realTreeProblems();
for (const p of real) console.log(`        ${p}`);
check('the real repository is clean', real.length === 0);

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
