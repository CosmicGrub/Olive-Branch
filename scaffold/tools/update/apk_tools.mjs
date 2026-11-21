/**
 * OLIVE BRANCH - the Android SDK tools the release side leans on, found and run in one place.
 *
 *   apksigner  `verify --print-certs`: is the APK validly signed, and by which certificate (SHA-256)?
 *   aapt2      `dump badging`: which package, versionCode and versionName does the file really carry?
 *
 * Both ship in the SDK's build-tools. They are found through OLIVE_APKSIGNER / OLIVE_AAPT2, else the newest
 * build-tools folder under ANDROID_HOME / ANDROID_SDK_ROOT. Nothing here signs anything: signing an APK is the owner's
 * keystore step (android/RELEASE_SIGNING.md); this only READS the result.
 */
import { existsSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { parseApksignerCerts, parseBadging } from './manifest_lib.mjs';

const WIN = process.platform === 'win32';

function newestBuildTool(env, names) {
  const sdk = env.ANDROID_HOME || env.ANDROID_SDK_ROOT;
  if (!sdk || !existsSync(join(sdk, 'build-tools'))) return null;
  const versions = readdirSync(join(sdk, 'build-tools')).sort((a, b) => b.localeCompare(a, undefined, { numeric: true }));
  for (const v of versions) for (const n of names) { const p = join(sdk, 'build-tools', v, n); if (existsSync(p)) return p; }
  return null;
}

export const findApksigner = (env = process.env) => env.OLIVE_APKSIGNER || newestBuildTool(env, WIN ? ['apksigner.bat'] : ['apksigner']);
export const findAapt2 = (env = process.env) => env.OLIVE_AAPT2 || newestBuildTool(env, WIN ? ['aapt2.exe'] : ['aapt2']);

function exec(cmd, args) {
  const bat = WIN && /\.(bat|cmd)$/i.test(cmd);
  const r = bat
    ? spawnSync(`"${cmd}" ${args.map((a) => `"${a}"`).join(' ')}`, { encoding: 'utf8', shell: true })
    : spawnSync(cmd, args, { encoding: 'utf8' });
  return { code: r.status ?? 1, out: `${r.stdout || ''}${r.stderr || ''}` };
}

/** { ok, certs:[sha256 hex], detail }. ok is false when apksigner says the signature does not verify. */
export function apkSigners(apkPath, env = process.env) {
  const tool = findApksigner(env);
  if (!tool) return { ok: false, certs: [], detail: 'apksigner not found (set ANDROID_HOME, or OLIVE_APKSIGNER)', missing: true };
  const r = exec(tool, ['verify', '--print-certs', apkPath]);
  if (r.code !== 0) return { ok: false, certs: [], detail: `apksigner refused the file: ${r.out.split('\n').find((l) => l.trim()) || 'no output'}` };
  return { ok: true, certs: parseApksignerCerts(r.out), detail: 'verified' };
}

/** { ok, pkg, versionCode, versionName } or { ok:false, missing } when aapt2 is not available. */
export function apkBadging(apkPath, env = process.env) {
  const tool = findAapt2(env);
  if (!tool) return { ok: false, missing: true, detail: 'aapt2 not found' };
  const r = exec(tool, ['dump', 'badging', apkPath]);
  const b = r.code === 0 ? parseBadging(r.out) : null;
  return b ? { ok: true, ...b } : { ok: false, detail: 'aapt2 could not read the file' };
}
