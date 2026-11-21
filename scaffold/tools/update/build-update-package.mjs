#!/usr/bin/env node
/**
 * OLIVE BRANCH - build and package the 'direct' APK and draft its update manifest (docs/RELEASING.md, "Publishing an update").
 *
 *   node tools/update/build-update-package.mjs \
 *       --pubkeys 1f7c31942912896a:<base64url key> \
 *       --manifest-url https://github.com/<owner>/<repo>/releases/download/updates/update-manifest.json \
 *       --download-base https://github.com/<owner>/<repo>/releases/download/v0.52.0 \
 *       --download-base https://mirror.example.org/olive            (repeat: the first is primary, the rest are mirrors)
 *
 * What it does, in order, and stops at the first thing that is wrong:
 *   1. checks the five version places agree and takes versionName / versionCode from pubspec (never chosen by hand);
 *   2. reads the plain-words notes docs/release-notes/<version>.txt (refuses a file that still says DRAFT);
 *   3. builds the APK for each --abi: `flutter build apk --release --flavor direct` with the app's PUBLIC update key and the
 *      manifest address as dart-defines (so the update feature is present), signed by YOUR keystore through android/key.properties.
 *      Or, with --apk <abi>=<file>, packages an APK you already built and signed (for example the CI artifact, re-signed
 *      with apksigner: see RELEASING.md);
 *   4. checks each APK: a valid signature (apksigner), its signing-certificate SHA-256 (pinned into the manifest), its package and
 *      versionCode (aapt2) against the version, and its zip structure (no duplicate entries, no zip bomb);
 *   5. computes size, SHA-256 and the per-chunk SHA-256 list, and writes the DRAFT manifest, SHA256SUMS.direct and NEXT-STEPS.txt.
 * It does NOT sign the manifest and never reads a private key: signing is the separate, offline step
 * (tools/update/sign-update-manifest.mjs). Nothing is uploaded.
 *
 * Refusals: a debug-signed APK (only with --allow-debug-signed, for a dry run: the app refuses it over a release-signed
 * install); android/app/google-services.json present (it would be compiled into a public file); a download address that is not
 * https; a manifest that would not pass the same validator the app uses.
 *
 * Options
 *   --channel NAME          default "stable"
 *   --abi ABI               repeatable: arm64-v8a (default), armeabi-v7a, x86_64, universal
 *   --apk ABI=FILE          use a prebuilt, already release-signed APK for that abi instead of building. The file must ALREADY
 *                           carry the update public key and manifest address (built with the same dart-defines this script uses);
 *                           the script cannot see inside the app, so it also needs --has-update-key to say you checked. A build
 *                           without them (the CI artifact) has no update feature: phones that took it could never be updated in place.
 *   --has-update-key        confirm that every --apk file was built with OLIVE_UPDATE_PUBKEYS and OLIVE_UPDATE_MANIFEST_URL
 *   --valid-days N          how long the manifest stays valid (default 180, at most 400): an old copy cannot be replayed for ever
 *   --min-supported CODE    versionCode below which adults see "Please update" (default 1: nobody is nudged; raise it only for a security fix)
 *   --issued ISO            default now; --sequence N default seconds since the epoch of --issued (must rise with every manifest)
 *   --notes FILE            default docs/release-notes/<version>.txt
 *   --out DIR               default scaffold/out/update/<version>/ (git-ignored)
 *   --base-url URL          bake ONE public https server address into the build (default: none)
 *   --entry FILE            default lib/main_live.dart
 *   --signer-sha256 HEX     only when apksigner cannot be found; verify-update-release.mjs still checks it on a machine that has it
 *   --allow-debug-signed    dry runs only
 */
import { spawnSync } from 'node:child_process';
import { copyFileSync, existsSync, mkdirSync, readFileSync, statSync, writeFileSync } from 'node:fs';
import { basename, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { REPO, baseUrlProblem, buildNumber, readVersions, versionProblems } from '../release_lib.mjs';
import { apkBadging, apkSigners } from './apk_tools.mjs';
import {
  ABIS, APP_ID, LIMITS, chooseChunkSize, formatTime, hashFile, inspectApkZip, parseTime, parseTrust, policyProblems, trustEntry, urlProblem, validatePayload,
} from './manifest_lib.mjs';
import { parseNotesFile } from './notes_lib.mjs';

const CLIENT = join(REPO, 'scaffold', 'client');
const TARGET_PLATFORM = { 'arm64-v8a': 'android-arm64', 'armeabi-v7a': 'android-arm', x86_64: 'android-x64' };

function parseArgs(argv) {
  const o = { channel: 'stable', abis: [], apks: {}, downloadBases: [], validDays: 180, minSupported: 1, entry: 'lib/main_live.dart', allowDebugSigned: false, allowLoopbackHttp: false, hasUpdateKey: false };
  const need = (i, a) => { if (i >= argv.length) throw new Error(`${a} needs a value`); return argv[i]; };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--channel') o.channel = need(++i, a);
    else if (a === '--abi') o.abis.push(need(++i, a));
    else if (a === '--apk') { const v = need(++i, a); const at = v.indexOf('='); if (at < 1) throw new Error('--apk takes ABI=FILE'); o.apks[v.slice(0, at)] = v.slice(at + 1); }
    else if (a === '--pubkeys') o.pubkeys = need(++i, a);
    else if (a === '--manifest-url') o.manifestUrl = need(++i, a);
    else if (a === '--download-base') o.downloadBases.push(need(++i, a).replace(/\/+$/, ''));
    else if (a === '--valid-days') o.validDays = Number(need(++i, a));
    else if (a === '--min-supported') o.minSupported = Number(need(++i, a));
    else if (a === '--issued') o.issued = need(++i, a);
    else if (a === '--sequence') o.sequence = Number(need(++i, a));
    else if (a === '--notes') o.notes = need(++i, a);
    else if (a === '--out') o.out = need(++i, a);
    else if (a === '--base-url') o.baseUrl = need(++i, a);
    else if (a === '--entry') o.entry = need(++i, a);
    else if (a === '--signer-sha256') o.signerSha256 = need(++i, a);
    else if (a === '--has-update-key') o.hasUpdateKey = true;
    else if (a === '--allow-debug-signed') o.allowDebugSigned = true;
    else if (a === '--allow-loopback-http') o.allowLoopbackHttp = true;
    else if (a === '-h' || a === '--help') o.help = true;
    else throw new Error(`unknown argument: ${a}`);
  }
  if (o.abis.length === 0) o.abis = Object.keys(o.apks).length ? Object.keys(o.apks) : ['arm64-v8a'];
  return o;
}

/**
 * The draft manifest object (no signature) for already-measured files. Pure.
 * @param {object} p  { versionName, versionCode, channel, issuedAt (ms), validDays, sequence, minSupported, notes:{headline,notes}, apks:[{abi,size,sha256,signerSha256,chunkSize,chunks,fileName}], downloadBases:[] }
 */
export function draftManifest(p) {
  const issued = p.issuedAt;
  return {
    schema: 1,
    app: APP_ID,
    channel: p.channel,
    versionName: p.versionName,
    versionCode: p.versionCode,
    minSupportedVersionCode: p.minSupported,
    sequence: p.sequence ?? Math.floor(issued / 1000),
    issuedAt: formatTime(issued),
    expiresAt: formatTime(issued + p.validDays * 86400000),
    publishedAt: formatTime(issued),
    headline: p.notes.headline,
    notes: p.notes.notes,
    apks: p.apks.map((a) => ({
      abi: a.abi,
      size: a.size,
      sha256: a.sha256,
      signerSha256: a.signerSha256,
      chunkSize: a.chunkSize,
      chunks: a.chunks,
      urls: p.downloadBases.map((b) => `${b}/${a.fileName}`),
    })),
  };
}

export const apkFileName = (version, abi) => `olive-${version}-direct-${abi}.apk`;

const die = (m) => { throw new Error(m); };

/**
 * Why [v] may not be handed to the build command as one argument, or null. On Windows the build runs through cmd.exe, which
 * would read `&`, `|`, `%`, `^`, quotes and the like as commands; they are refused on every platform so the rule is the same
 * (and testable) everywhere. A manifest address with a query is fine as long as it avoids those characters.
 */
export function shellUnsafeProblem(v) {
  return /^[A-Za-z0-9._~:/?=+@,-]*$/.test(String(v)) ? null : 'contains a character a command line would treat specially (such as & | < > ^ % ! quotes, backticks, ; ( ) $, spaces or non-ASCII); use a plain address without them';
}

/** The manifest address that gets compiled into the app: the same URL rule as the files it points at, and a shell-safe spelling. */
export function manifestUrlProblem(url, { allowLoopbackHttp = false } = {}) {
  return urlProblem(url, { allowLoopbackHttp }) ?? shellUnsafeProblem(url);
}

/** The `flutter build apk` argument list for one abi. Exported so a test can assert exactly what is (and is not) passed. */
export function flutterArgs({ abi, entry, pubkeys, manifestUrl, baseUrl, allowDebugSigned }) {
  return [
    'build', 'apk', '--release', '--flavor', 'direct',
    ...(TARGET_PLATFORM[abi] ? ['--target-platform', TARGET_PLATFORM[abi]] : []),
    `--target=${entry}`,
    `--dart-define=OLIVE_UPDATE_PUBKEYS=${pubkeys}`,
    `--dart-define=OLIVE_UPDATE_MANIFEST_URL=${manifestUrl}`,
    ...(baseUrl ? [`--dart-define=OLIVE_API_BASE_URL=${baseUrl}`] : []),
    ...(allowDebugSigned ? ['--android-project-arg=olive.allowDebugSignedRelease=true'] : []),
  ];
}

export async function run(argv, { log = console.log, env = process.env } = {}) {
  let o;
  try { o = parseArgs(argv); } catch (e) { log(`build-update-package: ${e.message}`); return 1; }
  if (o.help) { log(readFileSync(fileURLToPath(import.meta.url), 'utf8').split('*/')[0].replace(/^\/\*\*\n|^ \* ?/gm, '')); return 0; }
  try {
    // ---- 1. the version
    const v = readVersions();
    const vp = versionProblems(v);
    if (vp.length) die(`the version places disagree, fix that first:\n  - ${vp.join('\n  - ')}`);
    const versionName = v.changelog.version;
    const versionCode = buildNumber(versionName);
    log(`version ${versionName} (versionCode ${versionCode}, derived from the version)`);

    // ---- inputs
    if (!o.pubkeys) die('--pubkeys is required: the app\'s PUBLIC update key, from gen-update-key.mjs');
    const trust = parseTrust(o.pubkeys);
    if (trust.size === 0) die('--pubkeys holds no usable "kid:key" entry');
    // The define is rebuilt from what parsed, never passed through as typed: junk beside a good entry is a mistake to refuse.
    const rawEntries = o.pubkeys.split(',').map((x) => x.trim()).filter(Boolean);
    if (rawEntries.length !== trust.size) die('--pubkeys holds an entry that is not a valid "kid:key" (or a repeated key id); nothing is built with a mistyped key');
    const pubkeys = [...trust].map(([kid, raw]) => trustEntry(kid, raw)).join(',');
    if (!o.manifestUrl) die('--manifest-url is required: where the app will look for the signed manifest');
    { const p = manifestUrlProblem(o.manifestUrl, { allowLoopbackHttp: o.allowLoopbackHttp }); if (p) die(`--manifest-url: ${p}. This address is compiled into the app; a release build refuses http and a wrong address means the feature silently never works`); }
    { const p = shellUnsafeProblem(o.entry); if (p) die(`--entry: ${p}`); }
    if (o.downloadBases.length === 0) die('--download-base is required (repeat it for a mirror)');
    if (o.downloadBases.length < 2) log('  note  only one download address: a published update should name a primary AND a mirror (--download-base twice)');
    if (o.baseUrl) { const p = baseUrlProblem(o.baseUrl) ?? shellUnsafeProblem(o.baseUrl); if (p) die(`--base-url: ${p}`); }
    for (const abi of o.abis) if (!ABIS.includes(abi)) die(`unknown abi ${abi}`);
    if (!(o.validDays > 0 && o.validDays <= LIMITS.validityDays)) die(`--valid-days must be 1 to ${LIMITS.validityDays}`);
    if (!Number.isSafeInteger(o.minSupported) || o.minSupported < 1 || o.minSupported > versionCode) die('--min-supported must be a versionCode from 1 up to this version');
    const issuedAt = o.issued ? parseTime(o.issued) : Math.floor(Date.now() / 1000) * 1000;
    if (issuedAt === null) die('--issued must be a UTC time like 2026-11-21T10:00:00Z');

    // ---- 2. the notes
    const notesPath = resolve(o.notes || join(REPO, 'docs', 'release-notes', `${versionName}.txt`));
    if (!existsSync(notesPath)) die(`no release notes at ${notesPath}. Make them with tools/update/draft-release-notes.mjs ${versionName}, then rewrite them in plain words.`);
    const notes = parseNotesFile(readFileSync(notesPath, 'utf8'));

    if (Object.keys(o.apks).length) {
      if (!o.hasUpdateKey) die('--apk packages a file this script cannot look inside. An app built WITHOUT the update public key and manifest address (the CI artifact is one) has no update feature, and every phone that installed it could never be updated in place again: the next update would have to be sideloaded by hand. Build the file with --dart-define=OLIVE_UPDATE_PUBKEYS=<your public entry> and --dart-define=OLIVE_UPDATE_MANIFEST_URL=<the manifest address>, then pass --has-update-key to say you did');
      log('  WARNING  --has-update-key: you are vouching that the prebuilt file carries the update key and manifest address; nothing here can check it');
    }
    // ---- hygiene
    if (!Object.keys(o.apks).length) {
      if (existsSync(join(CLIENT, 'android', 'app', 'google-services.json'))) die('android/app/google-services.json exists: it would be compiled into a public file');
      if (!existsSync(join(CLIENT, 'android', 'key.properties')) && !o.allowDebugSigned) die('android/key.properties is missing, so this build would carry the shared debug key and the app would refuse it over a real install. Create the keystore (android/RELEASE_SIGNING.md) or pass --allow-debug-signed for a dry run.');
    }

    const outDir = resolve(o.out || join(REPO, 'scaffold', 'out', 'update', versionName));
    mkdirSync(outDir, { recursive: true });

    // ---- 3 + 4 + 5. each file
    const files = [];
    for (const abi of o.abis) {
      const fileName = apkFileName(versionName, abi);
      const dest = join(outDir, fileName);
      if (o.apks[abi]) {
        if (!existsSync(o.apks[abi])) die(`--apk ${abi}: no such file`);
        copyFileSync(o.apks[abi], dest);
        log(`using the prebuilt ${abi} file`);
      } else {
        if (!TARGET_PLATFORM[abi]) die(`abi ${abi} cannot be built here; pass a prebuilt file with --apk ${abi}=FILE`);
        const args = flutterArgs({ abi, entry: o.entry, pubkeys, manifestUrl: o.manifestUrl, baseUrl: o.baseUrl, allowDebugSigned: o.allowDebugSigned });
        // The public key and manifest address are not secrets; they are printed so the owner can see exactly what was built in.
        log(`flutter ${args.join(' ')}`);
        const r = spawnSync(env.FLUTTER_BIN || 'flutter', args, { cwd: CLIENT, stdio: 'inherit', shell: process.platform === 'win32' });
        if (r.status !== 0) die('flutter build failed (see above)');
        const built = join(CLIENT, 'build', 'app', 'outputs', 'flutter-apk', 'app-direct-release.apk');
        if (!existsSync(built)) die(`expected ${built} after the build`);
        copyFileSync(built, dest);
      }
      files.push(await measure(dest, fileName, abi, { versionName, versionCode, o, log, env }));
    }
    const draft = { manifest: draftManifest({ versionName, versionCode, channel: o.channel, issuedAt, validDays: o.validDays, sequence: o.sequence, minSupported: o.minSupported, notes, apks: files, downloadBases: o.downloadBases }) };
    const problems = [...validatePayload(draft.manifest, { allowLoopbackHttp: o.allowLoopbackHttp }), ...policyProblems(draft.manifest)];
    if (problems.length) die(`the draft would not pass the app's own checks:\n  - ${problems.join('\n  - ')}`);
    const text = `${JSON.stringify(draft, null, 2)}\n`;
    if (Buffer.byteLength(text) > LIMITS.manifestBytes) die(`the manifest would be ${Buffer.byteLength(text)} bytes; the app refuses anything over ${LIMITS.manifestBytes}`);
    writeFileSync(join(outDir, 'update-manifest.draft.json'), text);
    writeFileSync(join(outDir, 'SHA256SUMS.direct'), files.map((f) => `${f.sha256}  ${f.fileName}\n`).join(''));
    writeFileSync(join(outDir, 'NEXT-STEPS.txt'), nextSteps(versionName, files, o));
    log(`\nDraft written to ${outDir}`);
    files.forEach((f) => log(`  ${f.fileName}  ${f.size} bytes  sha256 ${f.sha256.slice(0, 16)}...  signer ${f.signerSha256.slice(0, 16)}...  ${f.chunks.length} chunks of ${f.chunkSize}`));
    log('\nThe manifest is NOT signed. Next, offline: see NEXT-STEPS.txt');
    return 0;
  } catch (e) {
    log(`build-update-package: REFUSED. ${e.message}`);
    return 1;
  }
}

async function measure(path, fileName, abi, { versionName, versionCode, o, log, env }) {
  const size = statSync(path).size;
  if (size > LIMITS.apkBytes) die(`${fileName} is ${size} bytes; the app refuses anything over ${LIMITS.apkBytes}`);
  const zip = await inspectApkZip(path);
  if (!zip.ok) die(`${fileName} is not a sound APK: ${zip.problems.join('; ')}`);

  const sig = apkSigners(path, env);
  let signerSha256 = null;
  if (sig.missing) {
    if (!o.signerSha256) die('apksigner was not found (set ANDROID_HOME), so the signing certificate cannot be read. If you know its SHA-256, pass --signer-sha256 and run verify-update-release.mjs on a machine that has apksigner.');
    signerSha256 = o.signerSha256.toLowerCase();
    log('  note  apksigner not found: the signing certificate was taken from --signer-sha256 and is NOT checked');
  } else {
    if (!sig.ok) die(`${fileName}: ${sig.detail}`);
    if (sig.certs.length !== 1) die(`${fileName} has ${sig.certs.length} signing certificates; exactly one is expected`);
    signerSha256 = sig.certs[0];
    if (o.signerSha256 && o.signerSha256.toLowerCase() !== signerSha256) die(`${fileName}: --signer-sha256 does not match the file's certificate`);
  }
  const badge = apkBadging(path, env);
  if (badge.ok) {
    if (badge.pkg !== APP_ID) die(`${fileName} is package ${badge.pkg}, not ${APP_ID}`);
    if (badge.versionCode !== versionCode) die(`${fileName} carries versionCode ${badge.versionCode}, the version ${versionName} derives ${versionCode}`);
    if (badge.versionName !== versionName) die(`${fileName} carries versionName ${badge.versionName}, expected ${versionName}`);
  } else log('  note  aapt2 not found: the package and version inside the file were NOT cross-checked');
  const chunkSize = chooseChunkSize(size);
  const h = await hashFile(path, chunkSize);
  return { abi, fileName, size: h.size, sha256: h.sha256, signerSha256, chunkSize, chunks: h.chunks };
}

function nextSteps(version, files, o) {
  return [
    `Olive Branch ${version}: what to do next (nothing has been signed or uploaded)`,
    '',
    '1. Read update-manifest.draft.json: version, the notes in plain words, every address, the sizes.',
    '2. On the machine that holds your update-signing key (offline, outside any repository):',
    '     node tools/update/sign-update-manifest.mjs --draft update-manifest.draft.json --key /abs/path/to/olive-update.key --out update-manifest.json [--prev <the manifest now live>]',
    `3. Upload ${files.map((f) => f.fileName).join(', ')} and SHA256SUMS.direct to every download address you listed, and upload`,
    `   update-manifest.json to ${o.manifestUrl} (the manifest last, so no phone ever sees a manifest whose files are not there yet).`,
    '4. Check what is really published, with the same checks the app makes:',
    `     node tools/update/verify-update-release.mjs --manifest ${o.manifestUrl} --pubkeys <the same key entry>`,
    '5. Only then tell anyone. Never edit a published manifest: to change anything, build, sign and publish a new one (a higher sequence).',
    '',
  ].join('\n');
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? '').href) run(process.argv.slice(2)).then((c) => { process.exitCode = c; });
