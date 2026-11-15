#!/usr/bin/env node
/**
 * Turns the owner's `google-services.json` (downloaded from the Firebase console for the Android app) into the four
 * `--dart-define` values the client reads (client/lib/push_config.dart), in a git-ignored file.
 *
 *   node tools/fcm-defines.mjs <path to google-services.json>
 *   node tools/fcm-defines.mjs <path to google-services.json> --out secrets/fcm.defines.json
 *
 * Then build with   flutter build apk ... --dart-define-from-file=<that file>
 * (tools/device-sync.sh does this by itself when the default file exists).
 *
 * WHAT IT NEVER DOES: print a value, write outside the git-ignored `scaffold/secrets/` folder, overwrite a file it did
 * not write itself without being told, or accept a file for a different app. It prints names and a count only. The
 * output file is a secret in the same sense `google-services.json` is: keep it out of git, chat and screenshots.
 *
 * The shape checks are the same as the client's (push_config.dart). They can say a value is the wrong SHAPE; only a
 * real device can say Google accepts it.
 */
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { dirname, resolve, relative, isAbsolute, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

export const APP_PACKAGE = 'com.olivebranch.olive_client';

const PROJECT_ID = /^[a-z][a-z0-9-]{4,28}[a-z0-9]$/;
const APP_ID = /^1:(\d{6,20}):android:[0-9a-f]{8,40}$/;
const SENDER_ID = /^\d{6,20}$/;
const API_KEY = /^[A-Za-z0-9_-]{20,80}$/;

/**
 * @param {string} text the contents of google-services.json
 * @param {string} [packageName] the Android application id the entry must be for
 * @returns {{ok: true, defines: Record<string,string>} | {ok: false, problems: string[]}}
 *   Problems name WHAT is wrong, never a value.
 */
export function defineFromGoogleServices(text, packageName = APP_PACKAGE) {
  let j;
  try { j = JSON.parse(text); } catch { return { ok: false, problems: ['not valid JSON'] }; }
  if (j === null || typeof j !== 'object' || Array.isArray(j)) return { ok: false, problems: ['not a JSON object'] };
  const info = j.project_info;
  const clients = j.client;
  if (info === null || typeof info !== 'object') return { ok: false, problems: ['project_info is missing'] };
  if (!Array.isArray(clients)) return { ok: false, problems: ['client list is missing'] };
  const mine = clients.filter((c) => c?.client_info?.android_client_info?.package_name === packageName);
  if (mine.length === 0) {
    return { ok: false, problems: [`no client entry for the Android app id ${packageName} (register that exact id in the Firebase console)`] };
  }
  if (mine.length > 1) return { ok: false, problems: [`more than one client entry for ${packageName}`] };
  const c = mine[0];
  const projectId = info.project_id;
  const senderId = info.project_number;
  const appId = c.client_info.mobilesdk_app_id;
  const keys = Array.isArray(c.api_key) ? c.api_key : [];
  const apiKey = keys.length === 1 ? keys[0]?.current_key : undefined;

  const problems = [];
  if (typeof projectId !== 'string' || !PROJECT_ID.test(projectId)) problems.push('project_id is missing or not a Firebase project id');
  if (typeof senderId !== 'string' || !SENDER_ID.test(senderId)) problems.push('project_number is missing or not a number');
  const appMatch = typeof appId === 'string' ? APP_ID.exec(appId) : null;
  if (!appMatch) problems.push('mobilesdk_app_id is missing or not an Android app id');
  else if (typeof senderId === 'string' && appMatch[1] !== senderId) problems.push('the app id and the project number disagree');
  if (keys.length !== 1) problems.push('expected exactly one api_key entry');
  else if (typeof apiKey !== 'string' || !API_KEY.test(apiKey)) problems.push('current_key is missing or not an API key');
  if (problems.length) return { ok: false, problems };
  return {
    ok: true,
    defines: {
      OLIVE_FCM_PROJECT_ID: projectId,
      OLIVE_FCM_APP_ID: appId,
      OLIVE_FCM_API_KEY: apiKey,
      OLIVE_FCM_SENDER_ID: senderId,
    },
  };
}

/** The only folder an output may go in: scaffold/secrets/, which .gitignore covers. */
export function secretsDir(scaffoldRoot) {
  return resolve(scaffoldRoot, 'secrets');
}

/** null when `out` is inside the secrets folder, otherwise why not. */
export function outsideSecrets(scaffoldRoot, out) {
  const rel = relative(secretsDir(scaffoldRoot), resolve(out));
  if (rel === '' || rel.startsWith('..') || isAbsolute(rel) || rel.split(sep).includes('..')) {
    return 'the output must be a file inside scaffold/secrets/ (the git-ignored folder)';
  }
  return null;
}

function main(argv) {
  const scaffoldRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
  const args = argv.slice(2);
  const outIdx = args.indexOf('--out');
  const out = outIdx >= 0 ? args[outIdx + 1] : resolve(scaffoldRoot, 'secrets', 'fcm.defines.json');
  const force = args.includes('--force');
  const input = args.find((a, i) => !a.startsWith('--') && args[i - 1] !== '--out');
  if (!input || (outIdx >= 0 && !args[outIdx + 1])) {
    console.error('usage: node tools/fcm-defines.mjs <google-services.json> [--out secrets/<file>] [--force]');
    return 2;
  }
  const bad = outsideSecrets(scaffoldRoot, out);
  if (bad) { console.error(bad); return 2; }
  let text;
  try { text = readFileSync(input, 'utf8'); } catch { console.error('cannot read the input file'); return 2; }
  const r = defineFromGoogleServices(text);
  if (!r.ok) {
    console.error('google-services.json is not usable:');
    for (const p of r.problems) console.error(`  - ${p}`);
    return 1;
  }
  if (existsSync(out) && !force) {
    console.error('the output file already exists; pass --force to replace it');
    return 1;
  }
  mkdirSync(dirname(resolve(out)), { recursive: true });
  writeFileSync(resolve(out), JSON.stringify(r.defines, null, 2) + '\n', { mode: 0o600 });
  console.log(`wrote ${Object.keys(r.defines).length} settings to ${relative(scaffoldRoot, resolve(out)).split(sep).join('/')}`);
  console.log('build with: flutter build apk --dart-define-from-file=<that file>   (tools/device-sync.sh does this for you)');
  return 0;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.exit(main(process.argv));
}
