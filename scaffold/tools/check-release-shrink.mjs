#!/usr/bin/env node
/**
 * OLIVE BRANCH - static guard for a real release-only crash.
 *
 * The Jitsi SDK (React Native underneath) reads string resources at startup
 * (org.jitsi.meet.sdk.DropboxModule). Flutter's Gradle plugin turns resource shrinking ON for a release
 * build unless the app says otherwise, and the shrinker removed those strings: the release APK crashed on
 * launch with "String resource ID #0x0" on both devices while every debug build and every CI job was green.
 * The fix is an explicit `isShrinkResources = false` in the release build type of
 * client/android/app/build.gradle.kts. This script catches that line being removed or flipped, without an
 * emulator (the emulator smoke test is .github/workflows/release-smoke.yml).
 *
 * Rule: the `release { }` build type must either
 *   (a) set `isShrinkResources = false` explicitly (an unset value is NOT enough: Flutter then enables it), or
 *   (b) set it to true AND ship keep rules for the Jitsi strings: a res/raw/*.xml whose tools:keep names the
 *       Jitsi string resources (a broad `@string/*` also counts), AND proguard-rules.pro keeping org.jitsi.meet.sdk.
 *
 * LIMITS (it is a text check, not a Gradle evaluation): it reads only the app module's `release { }` block and takes the
 * LAST literal `true`/`false` assigned to isShrinkResources there. A value set through a variable or helper, or by a
 * different build type, flavor or another module, is not seen, and a stray literal could hide it. A restructured file
 * with no literal release block fails closed. The emulator smoke test is the check that does not depend on how the
 * flag is written.
 *
 * usage: node tools/check-release-shrink.mjs        (exit 1 on a problem)
 */
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

export const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const APP = 'client/android/app';

const stripComments = (s) => s.replace(/\r\n/g, '\n').replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/[^\n]*/g, '$1');

/** Body of `name { ... }` (brace-balanced) searched inside `src`, or null. */
function block(src, name) {
  const m = new RegExp(`(^|[^\\w])${name}\\s*\\{`, 'm').exec(src);
  if (!m) return null;
  let i = m.index + m[0].length, depth = 1;
  const start = i;
  while (i < src.length && depth > 0) { if (src[i] === '{') depth++; else if (src[i] === '}') depth--; i++; }
  return depth === 0 ? src.slice(start, i - 1) : null;
}

/**
 * Pure: returns a list of problems (empty = fine).
 * @param {string} gradle   build.gradle.kts text
 * @param {string} proguard proguard-rules.pro text
 * @param {string[]} keepXmls texts of res/raw/*.xml files
 */
export function shrinkProblems(gradle, proguard, keepXmls = []) {
  const g = stripComments(gradle);
  const buildTypes = block(g, 'buildTypes');
  const release = buildTypes == null ? null : block(buildTypes, 'release');
  if (release == null) return ['build.gradle.kts has no buildTypes { release { } } block this guard can read'];
  const settings = [...release.matchAll(/\b(?:isShrinkResources|shrinkResources)\s*(?:=\s*|\s)(true|false)\b/g)].map((m) => m[1]);
  if (settings.length === 0) {
    return ['the release build type does not set isShrinkResources: Flutter\'s Gradle plugin then turns resource shrinking ON and the Jitsi SDK crashes at launch ("String resource ID #0x0"). Set `isShrinkResources = false`.'];
  }
  if (settings[settings.length - 1] === 'false') return [];
  const problems = [];
  const keep = keepXmls.map((x) => x.replace(/<!--[\s\S]*?-->/g, '')).join('\n');
  const keepsJitsi = /tools:keep\s*=\s*"[^"]*(@string\/\*|@string\/[^",]*(?:jitsi|dropbox)[^",]*)/i.test(keep);
  if (!keepsJitsi) problems.push('isShrinkResources is true but no res/raw/*.xml tools:keep rule keeps the Jitsi string resources (or @string/*)');
  if (!/-keep\s+class\s+org\.jitsi\.meet\.sdk\.\*\*/.test(proguard.replace(/^\s*#.*$/gm, ''))) {
    problems.push('isShrinkResources is true but proguard-rules.pro does not keep org.jitsi.meet.sdk.**');
  }
  return problems;
}

export function realTreeProblems(root = ROOT) {
  const rd = (p) => readFileSync(join(root, p), 'utf8');
  const rawDir = join(root, APP, 'src/main/res/raw');
  const xmls = existsSync(rawDir) ? readdirSync(rawDir).filter((f) => f.endsWith('.xml')).map((f) => rd(`${APP}/src/main/res/raw/${f}`)) : [];
  return shrinkProblems(rd(`${APP}/build.gradle.kts`), rd(`${APP}/proguard-rules.pro`), xmls);
}

if (process.argv[1] && fileURLToPath(import.meta.url) === join(process.argv[1])) {
  const problems = realTreeProblems();
  if (problems.length === 0) { console.log('  PASS  release build type keeps resources the Jitsi SDK reads at startup'); }
  else { for (const p of problems) console.log(`  FAIL  ${p}`); process.exit(1); }
}
