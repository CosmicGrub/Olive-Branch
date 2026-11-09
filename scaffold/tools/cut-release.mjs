#!/usr/bin/env node
/**
 * OLIVE BRANCH — cut a release (runbook: docs/RELEASING.md).
 *
 *   node tools/cut-release.mjs 0.51.0                 DRY RUN (the default): checks, builds, hashes, writes notes. Publishes nothing.
 *   node tools/cut-release.mjs 0.51.0 --publish       ... and then tags the commit and creates the GitHub release.
 *
 * Options
 *   --out <dir>        where the APK, SHA256SUMS and release-notes.md go (default scaffold/out/release/<version>/, git-ignored)
 *   --skip-build       reuse the APK already in --out (only to re-publish; the hash is re-checked against SHA256SUMS)
 *   --base-url <url>   bake ONE public https server address into the build. Default: none (see below)
 *   --stable           publish as a normal release. Default: a GitHub PRE-RELEASE, because every cut is a debug-signed preview
 *   --prerelease       accepted for compatibility; already the default
 *
 * What it will and will not do
 *   - It builds exactly what RELEASE_SIGNING.md §3 documents: `flutter build apk --release`, lib/main_live.dart (never the
 *     offline demo's hard-coded PIN), arm64 only, debug-signed through the explicit olive.allowDebugSignedRelease opt-in.
 *     It is a PREVIEW tool. It refuses to run if android/key.properties exists (a real keystore would silently sign the
 *     file, which is not what a "debug-signed preview" says it is), and it never reads, creates or prints a key.
 *   - OLIVE_API_BASE_URL is deliberately NOT set by default: the app then falls back to the Android emulator's loopback
 *     alias, so a public APK carries no LAN or developer address, no 127.0.0.1 dev assumptions and no secret, and degrades
 *     to its on-device behaviour. --base-url takes one https public name or nothing. No other dart-define is ever passed
 *     (no OLIVE_DEV_LOGIN, no OLIVE_CHILD_ID, no guardian id).
 *   - Without --publish nothing leaves the machine: no tag, no push, no release. With --publish it needs a clean tree on
 *     main at exactly origin/main, no existing tag or release for the version, an authenticated `gh`, and the APK built
 *     from that same commit in this run. The tag is created by GitHub on that commit (`gh release create --target <sha>`).
 *   - In a dry run the git-state checks (clean tree, on main, at origin/main) are reported but are not fatal, so the build
 *     can be proved from a branch. In --publish they are.
 */
import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, writeFileSync, copyFileSync, statSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  REPO, isPrerelease, parseVersion, buildNumber, readVersions, versionProblems, changelogSection, baseUrlProblem, releaseNotes,
} from './release_lib.mjs';

const SCAFFOLD = join(REPO, 'scaffold');
const CLIENT = join(SCAFFOLD, 'client');
const GH_REPO = 'CosmicGrub/Olive-Branch';

const sh = (cmd, args, opts = {}) => {
  const r = spawnSync(cmd, args, { encoding: 'utf8', cwd: REPO, shell: process.platform === 'win32' && opts.shell !== false, ...opts });
  return { code: r.status ?? 1, out: (r.stdout || '').trim(), err: (r.stderr || '').trim() };
};
const git = (...a) => sh('git', a, { shell: false });

/**
 * What is really different in the tree: tracked files whose CONTENT differs from HEAD (line endings ignored, because
 * `flutter pub get` rewrites tracked generated files with LF under a Windows core.autocrlf checkout, which `git status`
 * reports as modified with an empty diff), plus untracked files that are not git-ignored. Empty string means clean.
 */
function treeDirt() {
  const lines = [];
  const changed = git('diff', '--ignore-cr-at-eol', '--name-only', 'HEAD').out;
  if (changed) lines.push(...changed.split('\n').map((f) => `M ${f}`));
  const untracked = git('ls-files', '--others', '--exclude-standard').out;
  if (untracked) lines.push(...untracked.split('\n').map((f) => `?? ${f}`));
  return lines.join('\n');
}

let problems = 0, warnings = 0;
const ok = (m) => console.log(`  ok    ${m}`);
const bad = (m, fatalOnlyWhenPublishing = false, publishing = false) => {
  if (fatalOnlyWhenPublishing && !publishing) { warnings++; console.log(`  WARN  ${m}   (fatal with --publish)`); }
  else { problems++; console.log(`  FAIL  ${m}`); }
};
const die = (m) => { console.error(`\ncut-release: ${m}`); process.exit(1); };

function parseArgs(argv) {
  const o = { publish: false, skipBuild: false, prerelease: false, stable: false, out: null, baseUrl: null, version: null };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--publish') o.publish = true;
    else if (a === '--skip-build') o.skipBuild = true;
    else if (a === '--prerelease') o.prerelease = true;
    else if (a === '--stable') o.stable = true;
    else if (a === '--out') o.out = argv[++i];
    else if (a === '--base-url') o.baseUrl = argv[++i];
    else if (a === '-h' || a === '--help') { console.log(readFileSync(fileURLToPath(import.meta.url), 'utf8').split('*/')[0].replace(/^\/\*\*\n|^ \* ?/gm, '')); process.exit(0); }
    else if (!o.version && !a.startsWith('-')) o.version = a;
    else die(`unknown argument: ${a}`);
  }
  return o;
}

function sha256File(p) { return createHash('sha256').update(readFileSync(p)).digest('hex'); }

function main() {
  const o = parseArgs(process.argv.slice(2));
  if (!o.version) die('usage: node tools/cut-release.mjs <version> [--publish] [--out dir] [--base-url https://...] [--skip-build] [--stable]');
  const version = o.version.replace(/^v/, '');
  parseVersion(version);
  const publishing = o.publish;
  console.log(`cut-release ${version}  [${publishing ? 'PUBLISH' : 'dry run'}]`);

  // ---- 1. git state
  console.log('\n1. git state');
  git('fetch', 'origin', 'main', '--tags', '--quiet');
  const status = { out: treeDirt() };
  status.out === '' ? ok('working tree is clean') : bad(`working tree is not clean:\n${status.out}`, true, publishing);
  const branch = git('rev-parse', '--abbrev-ref', 'HEAD').out;
  branch === 'main' ? ok('on main') : bad(`on branch ${branch}, not main`, true, publishing);
  const head = git('rev-parse', 'HEAD').out;
  const originMain = git('rev-parse', 'origin/main').out;
  head === originMain ? ok(`HEAD is origin/main (${head.slice(0, 12)})`) : bad(`HEAD ${head.slice(0, 12)} is not origin/main ${originMain.slice(0, 12)}`, true, publishing);
  const tagThere = git('rev-parse', '-q', '--verify', `refs/tags/v${version}`);
  tagThere.code !== 0 ? ok(`tag v${version} does not exist`) : bad(`tag v${version} already exists; a version is never reused (cut the next patch)`);

  // ---- 2. version sync
  console.log('\n2. version sync (the same check CI runs: tools/test/version_sync.test.mjs)');
  const v = readVersions();
  const vp = versionProblems(v);
  vp.length ? vp.forEach((p) => bad(p)) : ok(`CHANGELOG, MASTERFILE, MARKUP, DEMO manifest and pubspec all say ${v.changelog.version}+${v.pubspecBuild}`);
  if (v.changelog.version !== version) bad(`you asked for ${version} but the CHANGELOG's newest entry is ${v.changelog.version}`);
  const section = (() => { try { return changelogSection(readFileSync(join(REPO, 'CHANGELOG.md'), 'utf8'), version); } catch (e) { bad(e.message); return ''; } })();
  /verified by/i.test(section) && /NOT|not yet|has not|have not/.test(section.slice(0, 4000))
    ? ok('the CHANGELOG section carries a "what this release has, and has not, been verified by" paragraph')
    : bad('the CHANGELOG section has no honest "verified by / NOT verified" paragraph before its first ### heading');
  const guard = sh(process.execPath, [join(SCAFFOLD, 'tools', 'check-release-target.mjs')], { shell: false });
  guard.code === 0 ? ok('check-release-target: RELEASE_SIGNING.md §3 targets lib/main_live.dart') : bad(`check-release-target failed:\n${guard.out}`);

  // ---- 3. build inputs that must not be present
  console.log('\n3. build hygiene');
  existsSync(join(CLIENT, 'android', 'key.properties'))
    ? bad('android/key.properties exists: a real keystore would sign this build. This tool makes debug-signed previews only. Move it away for the cut.')
    : ok('no android/key.properties (the build will be debug-signed, as the notes say)');
  existsSync(join(CLIENT, 'android', 'app', 'google-services.json'))
    ? bad('android/app/google-services.json exists: it would be compiled into a public file')
    : ok('no google-services.json');
  if (o.baseUrl) { const p = baseUrlProblem(o.baseUrl); p ? bad(`--base-url: ${p}`) : ok(`--base-url ${o.baseUrl} is a public https name`); }
  else ok('no server address will be baked in (OLIVE_API_BASE_URL not set; no other dart-define either)');

  const outDir = resolve(o.out || join(SCAFFOLD, 'out', 'release', version));
  const apkName = `olive-branch-v${version}-arm64-preview.apk`;
  const apkOut = join(outDir, apkName);

  if (problems) die(`${problems} problem(s) above; nothing was built or published.`);

  // ---- 4. build
  console.log('\n4. build');
  mkdirSync(outDir, { recursive: true });
  if (o.skipBuild) {
    if (!existsSync(apkOut)) die(`--skip-build but ${apkOut} does not exist`);
    ok(`reusing ${apkOut}`);
  } else {
    const flutter = process.env.FLUTTER_BIN || 'flutter';
    const args = [
      'build', 'apk', '--release', '--target-platform', 'android-arm64', '--target=lib/main_live.dart',
      '--android-project-arg=olive.allowDebugSignedRelease=true',
      ...(o.baseUrl ? [`--dart-define=OLIVE_API_BASE_URL=${o.baseUrl}`] : []),
    ];
    console.log(`  flutter ${args.join(' ')}`);
    const r = spawnSync(flutter, args, { cwd: CLIENT, stdio: 'inherit', shell: process.platform === 'win32' });
    if (r.status !== 0) die('flutter build failed (see above)');
    const built = join(CLIENT, 'build', 'app', 'outputs', 'flutter-apk', 'app-release.apk');
    if (!existsSync(built)) die(`expected ${built} after the build`);
    copyFileSync(built, apkOut);
  }
  const size = statSync(apkOut).size;
  const digest = sha256File(apkOut);
  const sumsPath = join(outDir, 'SHA256SUMS');
  if (o.skipBuild && existsSync(sumsPath) && !readFileSync(sumsPath, 'utf8').includes(digest)) die('--skip-build: the APK does not match SHA256SUMS from the build run');
  writeFileSync(sumsPath, `${digest}  ${apkName}\n`);
  const treeAfter = treeDirt();
  if (treeAfter !== status.out) bad(`the build changed tracked or untracked files in the tree:\n${treeAfter}`);

  const notes = releaseNotes({ version, date: v.changelog.date, title: v.changelog.title, section, sha: head, apk: apkName, sha256: digest, size, baseUrl: o.baseUrl, prerelease: isPrerelease(o) });
  const notesPath = join(outDir, 'release-notes.md');
  writeFileSync(notesPath, notes);

  console.log(`\n  APK      ${apkOut}`);
  console.log(`  size     ${size} bytes (${(size / 1048576).toFixed(1)} MB)`);
  console.log(`  sha256   ${digest}`);
  console.log(`  version  ${version}+${buildNumber(version)} (Android versionCode ${buildNumber(version)})`);
  console.log(`  built from ${head}`);
  console.log(`  notes    ${notesPath}`);
  if (problems) die(`${problems} problem(s); not publishing.`);

  if (!publishing) {
    console.log(`\nDRY RUN complete${warnings ? ` (${warnings} warning(s) that would stop --publish)` : ''}. Nothing was tagged, pushed or published.`);
    console.log(`To publish from main at origin/main:  node tools/cut-release.mjs ${version} --publish`);
    return;
  }

  // ---- 5. publish
  console.log('\n5. publish');
  const auth = sh('gh', ['auth', 'status']);
  if (auth.code !== 0) die('gh is not authenticated');
  const existing = sh('gh', ['release', 'view', `v${version}`, '--repo', GH_REPO], { shell: false });
  if (existing.code === 0) die(`a GitHub release v${version} already exists`);
  const args = ['release', 'create', `v${version}`, apkOut, sumsPath, '--repo', GH_REPO, '--target', head,
    '--title', `v${version} — ${v.changelog.title.split(':')[0].slice(0, 80)}`, '--notes-file', notesPath, ...(isPrerelease(o) ? ['--prerelease'] : [])];
  const r = sh('gh', args, { shell: false });
  if (r.code !== 0) die(`gh release create failed:\n${r.err || r.out}`);
  console.log(`  ${r.out}`);
  const back = sh('gh', ['release', 'view', `v${version}`, '--repo', GH_REPO, '--json', 'assets,tagName,targetCommitish'], { shell: false });
  console.log(`  ${back.out}`);
  console.log(`\nPublished v${version} at ${head}. Next: docs/RELEASING.md "After publishing".`);
}

main();
