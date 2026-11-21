#!/usr/bin/env node
/**
 * OLIVE BRANCH - static guard for the two Android distribution flavors, `direct` and `play` (docs/RELEASING.md, "Two flavors").
 *
 * The flavors exist so that ONE code base can be updated two different ways: `direct` (sideload, GitHub release, a family's own
 * server) may download a verified APK and hand it to Android's PackageInstaller; `play` is updated by Google Play only and must
 * never carry the install permission or any code that installs a package (Play policy). Gradle is not run by this guard (no
 * Gradle in the checks that run on a laptop); it reads the files that decide the outcome and fails closed when a restructured
 * file can no longer be read. What it holds:
 *
 *   gradle      exactly one flavor dimension with exactly the flavors direct and play; no applicationIdSuffix / applicationId
 *               override / versionNameSuffix anywhere in a flavor (a direct update must replace the installed app in place, and
 *               the Play application id is permanent); the release-signing task guard still matches the FLAVORED task names
 *               (assembleDirectRelease, bundlePlayRelease, ...), by evaluating its own pattern on sample task names
 *   manifests   REQUEST_INSTALL_PACKAGES is declared in src/direct, REMOVED (tools:node="remove") in src/play, and appears nowhere
 *               in src/main or in any other manifest (a real declaration, not a mention in a comment)
 *   play code   nothing under src/play or src/main (shared by both flavors) names PackageInstaller, ACTION_INSTALL_PACKAGE,
 *               ACTION_VIEW on an apk mime type, or REQUEST_INSTALL_PACKAGES in code; the installer lives in src/direct only
 *   pubspec     `default-flavor: direct`, so a plain `flutter build apk` / `flutter run` keeps working
 *   ci          verify.sh compiles BOTH flavors (compileDirectDebugKotlin and compilePlayDebugKotlin), and release-smoke.yml builds
 *               and launches both (a `--flavor` for each, direct and play)
 *
 * usage: node tools/check-flavors.mjs        (exit 1 on a problem)
 */
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { dirname, join } from 'node:path';

export const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..');

const stripKotlinComments = (s) => s.replace(/\r\n/g, '\n').replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/[^\n]*/g, '$1');
const stripXmlComments = (s) => s.replace(/\r\n/g, '\n').replace(/<!--[\s\S]*?-->/g, '');
const lf = (s) => s.replace(/\r\n/g, '\n');

/** Body of `name { ... }` (brace-balanced) searched inside `src`, or null. */
function block(src, name) {
  const m = new RegExp(`(^|[^\\w])${name}\\s*\\{`, 'm').exec(src);
  if (!m) return null;
  let i = m.index + m[0].length, depth = 1;
  const start = i;
  while (i < src.length && depth > 0) { if (src[i] === '{') depth++; else if (src[i] === '}') depth--; i++; }
  return depth === 0 ? src.slice(start, i - 1) : null;
}

const INSTALL_PERMISSION = /android\.permission\.REQUEST_INSTALL_PACKAGES/;
const INSTALL_API = /PackageInstaller|ACTION_INSTALL_PACKAGE|ACTION_VIEW[\s\S]{0,200}application\/vnd\.android\.package-archive|application\/vnd\.android\.package-archive[\s\S]{0,200}ACTION_VIEW|REQUEST_INSTALL_PACKAGES|canRequestPackageInstalls/;

/**
 * Pure: returns a list of problems (empty = fine).
 * @param {{ gradle:string, manifests:Record<string,string>, code:Record<string,string>, pubspec:string, verify:string, smoke:string }} f
 *   manifests: source-set name ('main', 'direct', 'play', 'debug', ...) -> AndroidManifest.xml text
 *   code: repo-relative path of every Kotlin/Java file under src/main and src/play -> text
 */
export function flavorProblems(f) {
  const out = [];
  const g = stripKotlinComments(f.gradle);

  // ---- gradle
  const androidBlock = block(g, 'android');
  const flavorsBlock = androidBlock == null ? null : block(androidBlock, 'productFlavors');
  if (flavorsBlock == null) out.push('build.gradle.kts has no android { productFlavors { } } block this guard can read');
  else {
    const names = [...flavorsBlock.matchAll(/create\(\s*"([^"]+)"\s*\)/g)].map((m) => m[1]).sort();
    if (names.join(',') !== 'direct,play') out.push(`the flavors must be exactly "direct" and "play", found: ${names.join(', ') || 'none'}`);
    for (const bad of ['applicationIdSuffix', 'applicationId', 'versionNameSuffix', 'versionCode', 'versionName']) {
      if (new RegExp(`\\b${bad}\\b`).test(flavorsBlock)) out.push(`a flavor sets ${bad}: both flavors must keep the one application id and the pubspec version (a direct update replaces the installed app in place; the Play id is permanent)`);
    }
    const dims = [...flavorsBlock.matchAll(/dimension\s*=\s*"([^"]+)"/g)].map((m) => m[1]);
    if (new Set(dims).size !== 1 || dims.length !== 2) out.push('both flavors must name the same single dimension');
  }
  const dimDecl = [...g.matchAll(/flavorDimensions(?:\.add\(|\s*\+=\s*(?:listOf\()?|\s*=\s*listOf\()\s*"([^"]+)"/g)].map((m) => m[1]);
  if (dimDecl.length !== 1) out.push('there must be exactly one flavorDimensions declaration with exactly one dimension');

  // the release-signing guard must still see flavored task names
  const rx = /Regex\(\s*"([^"]+)"\s*\)/.exec(g.slice(g.indexOf('releasePackagingTask') >= 0 ? g.indexOf('releasePackagingTask') : 0));
  if (g.indexOf('releasePackagingTask') < 0 || !rx) out.push('the release-signing task-graph guard no longer names a releasePackagingTask pattern this guard can read');
  else {
    let re = null;
    try { re = new RegExp(rx[1].replace(/\\\$/g, '$')); } catch { out.push('the releasePackagingTask pattern is not a readable regular expression'); }
    if (re) {
      for (const n of ['assembleRelease', 'bundleRelease', 'packageRelease', 'assembleDirectRelease', 'assemblePlayRelease', 'bundleDirectRelease', 'bundlePlayRelease', 'packageDirectRelease', 'packagePlayRelease']) {
        if (!re.test(n)) out.push(`the release-signing guard does not match the task ${n}: a release build could be debug-signed without the refusal`);
      }
      for (const n of ['assembleDirectDebug', 'compileDirectDebugKotlin', 'compilePlayDebugKotlin', 'assemble', 'assembleReleaseAndroidTest', 'lintDirectRelease']) {
        if (re.test(n)) out.push(`the release-signing guard also matches ${n}, which must never be refused`);
      }
    }
    if (!/releasePackagingTask\.matches\(\s*it\.name\s*\)/.test(g)) out.push('the task-graph check no longer uses releasePackagingTask.matches(it.name)');
  }

  // ---- manifests
  const man = f.manifests;
  const declared = (xml) => INSTALL_PERMISSION.test(stripXmlComments(xml));
  const removed = (xml) => /<uses-permission[^>]*REQUEST_INSTALL_PACKAGES[^>]*tools:node\s*=\s*"remove"[^>]*>/.test(stripXmlComments(xml)) || /<uses-permission[^>]*tools:node\s*=\s*"remove"[^>]*REQUEST_INSTALL_PACKAGES[^>]*>/.test(stripXmlComments(xml));
  if (man.direct == null) out.push('src/direct/AndroidManifest.xml is missing');
  else if (!declared(man.direct) || removed(man.direct)) out.push('src/direct/AndroidManifest.xml must DECLARE REQUEST_INSTALL_PACKAGES (the direct flavor installs updates)');
  if (man.play == null) out.push('src/play/AndroidManifest.xml is missing');
  else {
    if (!removed(man.play)) out.push('src/play/AndroidManifest.xml must REMOVE REQUEST_INSTALL_PACKAGES with tools:node="remove" (Play policy; it also strips a plugin\'s declaration)');
    if (!/xmlns:tools\s*=\s*"http:\/\/schemas\.android\.com\/tools"/.test(man.play)) out.push('src/play/AndroidManifest.xml does not declare the tools namespace its tools:node attribute needs');
  }
  for (const [name, xml] of Object.entries(man)) {
    if (name === 'direct' || name === 'play') continue;
    if (declared(xml)) out.push(`src/${name}/AndroidManifest.xml mentions REQUEST_INSTALL_PACKAGES: only src/direct may declare it (it would ship in the play flavor)`);
  }

  // ---- code shared with, or belonging to, the play flavor
  for (const [path, text] of Object.entries(f.code)) {
    if (INSTALL_API.test(stripKotlinComments(text))) out.push(`${path} uses the package-install API; only src/direct may (src/main and src/play are in the play flavor)`);
  }

  // ---- pubspec
  if (!/^\s{2}default-flavor:\s*direct\s*$/m.test(lf(f.pubspec))) out.push('pubspec.yaml must set `default-flavor: direct` under flutter:');

  // ---- ci
  const v = lf(f.verify);
  for (const t of [':app:compileDirectDebugKotlin', ':app:compilePlayDebugKotlin']) if (!v.includes(t)) out.push(`verify.sh does not compile ${t}`);
  if (/:app:compileDebugKotlin/.test(v.replace(/^\s*#.*$/gm, ''))) out.push('verify.sh still names :app:compileDebugKotlin, which does not exist once there are flavors');
  const smoke = lf(f.smoke);
  if (!/--flavor \$\{\{ matrix\.flavor \}\}/.test(smoke)) out.push('release-smoke.yml must build with --flavor ${{ matrix.flavor }}');
  const flavorsInMatrix = [...smoke.matchAll(/^\s+flavor:\s*(\w+)\s*$/gm)].map((m) => m[1]);
  if (!flavorsInMatrix.includes('direct') || !flavorsInMatrix.includes('play')) out.push('release-smoke.yml must launch BOTH flavors (a matrix entry for direct and one for play)');
  if (!/flutter-apk\/app-\$\{\{ matrix\.flavor \}\}-release\.apk/.test(smoke)) out.push('release-smoke.yml must copy build/app/outputs/flutter-apk/app-<flavor>-release.apk');
  return out;
}

/** Reads the real tree. */
export function readTree(root = ROOT) {
  const app = join(root, 'scaffold', 'client', 'android', 'app');
  const read = (p) => readFileSync(p, 'utf8');
  const manifests = {};
  for (const set of readdirSync(join(app, 'src'))) {
    const m = join(app, 'src', set, 'AndroidManifest.xml');
    if (existsSync(m)) manifests[set] = read(m);
  }
  const code = {};
  const walk = (dir, rel) => {
    if (!existsSync(dir)) return;
    for (const name of readdirSync(dir)) {
      const full = join(dir, name);
      if (statSync(full).isDirectory()) walk(full, `${rel}/${name}`);
      else if (/\.(kt|java)$/.test(name)) code[`${rel}/${name}`] = read(full);
    }
  };
  walk(join(app, 'src', 'main'), 'src/main');
  walk(join(app, 'src', 'play'), 'src/play');
  return {
    gradle: read(join(app, 'build.gradle.kts')),
    manifests,
    code,
    pubspec: read(join(root, 'scaffold', 'client', 'pubspec.yaml')),
    verify: read(join(root, 'scaffold', 'tools', 'verify.sh')),
    smoke: read(join(root, '.github', 'workflows', 'release-smoke.yml')),
  };
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? '').href) {
  const problems = flavorProblems(readTree());
  if (problems.length) { for (const p of problems) console.log(`  FAIL  ${p}`); console.log(`\n${problems.length} flavor problem(s)`); process.exit(1); }
  console.log('  PASS  flavors: direct and play, one application id, install permission only in direct, guards match flavored tasks, CI builds both');
}
