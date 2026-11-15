/**
 * tools/fcm-defines.mjs: google-services.json -> the four git-ignored dart-defines.
 * Fixtures are made up in this file (no real project, no real key shape from any vendor).
 * usage: node tools/test/fcm_defines.test.mjs
 */
import { spawnSync } from 'node:child_process';
import { readFileSync, writeFileSync, existsSync, rmSync, mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { defineFromGoogleServices, outsideSecrets, APP_PACKAGE } from '../fcm-defines.mjs';

let pass = 0, fail = 0;
const check = (name, ok) => { if (ok) { pass++; console.log(`  PASS  ${name}`); } else { fail++; console.log(`  FAIL  ${name}`); } };

const HERE = dirname(fileURLToPath(import.meta.url));
const SCAFFOLD = resolve(HERE, '..', '..');
const TOOL = resolve(HERE, '..', 'fcm-defines.mjs');

const PROJECT = 'olive-test-project';
const NUMBER = '123456789012';
const APP = `1:${NUMBER}:android:0123456789abcdef`;
const KEY = 'test-only-key-not-real-0123456789';
const good = (over = {}) => ({
  project_info: { project_number: NUMBER, project_id: PROJECT },
  client: [{
    client_info: { mobilesdk_app_id: APP, android_client_info: { package_name: APP_PACKAGE } },
    api_key: [{ current_key: KEY }],
  }],
  ...over,
});
const run = (obj) => defineFromGoogleServices(typeof obj === 'string' ? obj : JSON.stringify(obj));
const noValues = (r) => { const s = JSON.stringify(r); return ![PROJECT, NUMBER, APP, KEY].some((v) => s.includes(v)); };

// ---- the happy path --------------------------------------------------------------------------------------------
const ok = run(good());
check('a good file gives the four settings', ok.ok && Object.keys(ok.defines).sort().join() ===
  'OLIVE_FCM_API_KEY,OLIVE_FCM_APP_ID,OLIVE_FCM_PROJECT_ID,OLIVE_FCM_SENDER_ID');
check('the values are the file\'s own', ok.ok && ok.defines.OLIVE_FCM_PROJECT_ID === PROJECT && ok.defines.OLIVE_FCM_SENDER_ID === NUMBER &&
  ok.defines.OLIVE_FCM_APP_ID === APP && ok.defines.OLIVE_FCM_API_KEY === KEY);
const two = good();
two.client.unshift({ client_info: { mobilesdk_app_id: `1:${NUMBER}:android:fedcba9876543210`, android_client_info: { package_name: 'com.example.other' } }, api_key: [{ current_key: 'another-made-up-key-0123456789' }] });
const pick = run(two);
check('with several apps in the file, only this app\'s entry is used', pick.ok && pick.defines.OLIVE_FCM_APP_ID === APP);

// ---- hostile and broken input: refused, and no problem text ever carries a value --------------------------------
const bad = [
  ['not JSON', 'this is not json {'],
  ['a JSON array', '[]'],
  ['JSON null', 'null'],
  ['no project_info', { ...good(), project_info: undefined }],
  ['no client list', { ...good(), client: undefined }],
  ['a file for a different app', { ...good(), client: [{ client_info: { mobilesdk_app_id: APP, android_client_info: { package_name: 'com.example.other' } }, api_key: [{ current_key: KEY }] }] }],
  ['the same app twice', { ...good(), client: [good().client[0], good().client[0]] }],
  ['no api key', { ...good(), client: [{ ...good().client[0], api_key: [] }] }],
  ['two api keys', { ...good(), client: [{ ...good().client[0], api_key: [{ current_key: KEY }, { current_key: KEY }] }] }],
  ['an api key with a space', { ...good(), client: [{ ...good().client[0], api_key: [{ current_key: 'has a space in it 0123456789' }] }] }],
  ['an api key with a newline', { ...good(), client: [{ ...good().client[0], api_key: [{ current_key: 'line1-0123456789-abcdef\nline2' }] }] }],
  ['a too-short api key', { ...good(), client: [{ ...good().client[0], api_key: [{ current_key: 'short' }] }] }],
  ['an app id for another platform', { ...good(), client: [{ ...good().client[0], client_info: { mobilesdk_app_id: `1:${NUMBER}:ios:0123456789abcdef`, android_client_info: { package_name: APP_PACKAGE } } }] }],
  ['an app id and project number that disagree', { ...good(), project_info: { project_number: '999999999999', project_id: PROJECT } }],
  ['an upper-case project id', { ...good(), project_info: { project_number: NUMBER, project_id: 'Olive-Test-Project' } }],
  ['a project number that is a number, not a string', { ...good(), project_info: { project_number: 123456789012, project_id: PROJECT } }],
  ['a project id with a path in it', { ...good(), project_info: { project_number: NUMBER, project_id: '../../etc/passwd-0000' } }],
];
for (const [name, input] of bad) {
  const r = run(input);
  check(`refused: ${name}`, r.ok === false && r.problems.length > 0);
  check(`refused with no value in the message: ${name}`, r.ok === false && noValues(r));
}

// ---- where an output may go ------------------------------------------------------------------------------------
check('a file inside secrets/ is allowed', outsideSecrets(SCAFFOLD, join(SCAFFOLD, 'secrets', 'fcm.defines.json')) === null);
check('a nested file inside secrets/ is allowed', outsideSecrets(SCAFFOLD, join(SCAFFOLD, 'secrets', 'x', 'y.json')) === null);
check('the scaffold folder itself is refused', outsideSecrets(SCAFFOLD, join(SCAFFOLD, 'fcm.defines.json')) !== null);
check('a ../ escape out of secrets/ is refused', outsideSecrets(SCAFFOLD, join(SCAFFOLD, 'secrets', '..', 'fcm.defines.json')) !== null);
check('a sibling folder that starts with "secrets" is refused', outsideSecrets(SCAFFOLD, join(SCAFFOLD, 'secrets-evil', 'a.json')) !== null);
check('secrets/ itself (not a file) is refused', outsideSecrets(SCAFFOLD, join(SCAFFOLD, 'secrets')) !== null);
check('a temp folder is refused', outsideSecrets(SCAFFOLD, join(tmpdir(), 'fcm.defines.json')) !== null);

// ---- the command line: writes the file, prints no value, will not overwrite, will not write elsewhere ------------
const work = mkdtempSync(join(tmpdir(), 'fcmdefs-'));
const input = join(work, 'google-services.json');
writeFileSync(input, JSON.stringify(good()));
const outName = `secrets/test-fcm-defines-${process.pid}.json`;
const outFile = resolve(SCAFFOLD, outName);
const cli = (...a) => spawnSync(process.execPath, [TOOL, ...a], { encoding: 'utf8' });
try {
  const a = cli(input, '--out', outName);
  check('the command succeeds', a.status === 0);
  check('the command prints no setting value', ![PROJECT, NUMBER, APP, KEY].some((v) => (a.stdout + a.stderr).includes(v)));
  check('the file holds the four settings as JSON', existsSync(outFile) && Object.keys(JSON.parse(readFileSync(outFile, 'utf8'))).length === 4);
  const again = cli(input, '--out', outName);
  check('it will not overwrite without --force', again.status === 1 && again.stderr.includes('--force'));
  const forced = cli(input, '--out', outName, '--force');
  check('it will overwrite with --force', forced.status === 0);
  const elsewhere = cli(input, '--out', join(work, 'x.json'));
  check('it refuses to write outside secrets/', elsewhere.status === 2 && !existsSync(join(work, 'x.json')));
  writeFileSync(input, JSON.stringify({ ...good(), project_info: { project_number: '1', project_id: 'x' } }));
  const broken = cli(input, '--out', `secrets/test-fcm-defines-b-${process.pid}.json`);
  check('a broken file exits 1 and writes nothing', broken.status === 1 && !existsSync(resolve(SCAFFOLD, `secrets/test-fcm-defines-b-${process.pid}.json`)));
  check('the usage line appears with no arguments', cli().status === 2);
} finally {
  rmSync(outFile, { force: true });
  rmSync(work, { recursive: true, force: true });
}

// ---- the repository keeps the file out of git ------------------------------------------------------------------
const ignore = readFileSync(resolve(SCAFFOLD, '..', '.gitignore'), 'utf8');
check('scaffold/secrets/ is git-ignored', /^scaffold\/secrets\/\s*$/m.test(ignore.replace(/\r/g, '')));
check('no google-services.json is tracked anywhere under client/android', !existsSync(resolve(SCAFFOLD, 'client', 'android', 'app', 'google-services.json')));

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
