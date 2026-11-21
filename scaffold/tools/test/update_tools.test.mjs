/**
 * The offline half of the release side: the key generator, the local signing script, the notes tool and the build-and-package
 * script (driven with a prebuilt file, so no Flutter and no Android SDK are needed). The properties that matter:
 *   - a signing key can never be written to, or read from, a path inside a git working tree;
 *   - the private key never appears in anything printed or in any file but the one the owner named;
 *   - the signing script refuses everything the app would refuse (and a rollback or a stale sequence), and its output verifies;
 *   - the package script refuses a DRAFT notes file, a debug-signed build, an unreadable certificate, a bad address.
 *
 * usage: node tools/test/update_tools.test.mjs
 */
import { existsSync, mkdirSync, mkdtempSync, readFileSync, readdirSync, rmSync, statSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { run as genKey } from '../update/gen-update-key.mjs';
import { run as signRun } from '../update/sign-update-manifest.mjs';
import { run as packRun } from '../update/build-update-package.mjs';
import { run as draftNotes, changelogTitle } from '../update/draft-release-notes.mjs';
import { OWN_REPO, keyPathProblem, loadUpdateKey } from '../update/key_lib.mjs';
import * as L from '../update/manifest_lib.mjs';
import { buildNumber, readVersions } from '../release_lib.mjs';
import { clone, fakeApk, hx, payload, zip } from './update_testkit.mjs';

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = JSON.stringify(a) === JSON.stringify(e); ok ? pass++ : fail++; rows.push({ g, n, ok, a: JSON.stringify(a), e: JSON.stringify(e) }); };
const capture = () => { const lines = []; return { log: (s = '') => lines.push(String(s)), lines, text: () => lines.join('\n') }; };

const base = mkdtempSync(join(tmpdir(), 'olive-tools-'));
const sub = (n) => { const d = join(base, n); mkdirSync(d, { recursive: true }); return d; };

// ================================================================ the key generator
{
  const g = 'gen-update-key';
  const dir = sub('keys');
  const out = join(dir, 'olive-update.key');
  const c = capture();
  check(g, 'writes a key to a folder outside every repository', genKey(['--out', out], process.env, c.log), 0);
  check(g, 'the private key file exists, with the public entry beside it', [existsSync(out), existsSync(`${out}.pub`)], [true, true]);
  const pem = readFileSync(out, 'utf8');
  check(g, 'the private key file is a PKCS#8 PEM', pem.startsWith(`${'-----BEGIN'} ${'PRIVATE'} KEY-----`), true);
  const body = pem.replace(/-----[A-Z ]+-----|\s/g, '');
  check(g, 'nothing printed contains the private key material', c.text().includes(body.slice(0, 40)) || c.text().includes('BEGIN'), false);
  check(g, 'what is printed is the public entry for the dart-define', /--dart-define=OLIVE_UPDATE_PUBKEYS=[0-9a-f]{16}:[A-Za-z0-9_-]{43}/.test(c.text()), true);
  check(g, 'the .pub file holds exactly that entry', readFileSync(`${out}.pub`, 'utf8').trim(), c.text().match(/OLIVE_UPDATE_PUBKEYS=(\S+)/)[1]);
  if (process.platform !== 'win32') check(g, 'the key file is mode 0600', (statSync(out).mode & 0o777).toString(8), '600');
  check(g, 'it never overwrites an existing key', [genKey(['--out', out], process.env, capture().log), readFileSync(out, 'utf8') === pem], [1, true]);

  const inRepo = join(OWN_REPO, 'scaffold', 'out', 'olive-update.key');
  const c2 = capture();
  check(g, 'REFUSES a path inside this repository', [genKey(['--out', inRepo], process.env, c2.log), existsSync(inRepo)], [1, false]);
  check(g, '...and says why', /inside the Olive Branch repository tree/.test(c2.text()), true);
  check(g, 'REFUSES the repository root itself', genKey(['--out', join(OWN_REPO, 'k.key')], process.env, capture().log), 1);
  check(g, 'REFUSES a path in a not-yet-created folder inside the repository', [genKey(['--out', join(OWN_REPO, 'no', 'such', 'dir', 'k.key')], process.env, capture().log), existsSync(join(OWN_REPO, 'no'))], [1, false]);
  const other = sub('other-repo'); mkdirSync(join(other, '.git'));
  const c3 = capture();
  check(g, 'REFUSES a path inside ANY other git working tree', [genKey(['--out', join(other, 'k.key')], process.env, c3.log), existsSync(join(other, 'k.key'))], [1, false]);
  check(g, '...and a deeper path under that tree', genKey(['--out', join(other, 'a', 'b', 'k.key')], process.env, capture().log), 1);
  const worktree = sub('a-worktree'); writeFileSync(join(worktree, '.git'), 'gitdir: elsewhere\n');
  check(g, 'REFUSES a linked worktree (.git is a file)', genKey(['--out', join(worktree, 'k.key')], process.env, capture().log), 1);
  check(g, 'REFUSES a relative path (no doubt where it lands)', genKey(['--out', 'k.key'], process.env, capture().log), 1);
  check(g, 'REFUSES a missing folder', genKey(['--out', join(base, 'nope', 'k.key')], process.env, capture().log), 1);
  check(g, 'REFUSES with no --out', genKey([], process.env, capture().log), 1);
  check(g, 'REFUSES an unknown argument', genKey(['--out', join(dir, 'z.key'), '--print-private'], process.env, capture().log), 1);
  let linked = null;
  try { symlinkSync(join(OWN_REPO, 'scaffold'), join(dir, 'link'), 'junction'); linked = join(dir, 'link', 'k.key'); } catch { /* no privilege to link here */ }
  if (linked) check(g, 'REFUSES a path that reaches the repository through a symlink or junction', [genKey(['--out', linked], process.env, capture().log), existsSync(join(OWN_REPO, 'scaffold', 'k.key'))], [1, false]);

  const pp = join(dir, 'enc.key');
  check(g, 'a short passphrase is refused', genKey(['--out', pp, '--passphrase-env', 'P'], { P: 'short' }, capture().log), 1);
  check(g, 'an unset passphrase variable is refused', genKey(['--out', pp, '--passphrase-env', 'MISSING'], {}, capture().log), 1);
  check(g, 'an encrypted key is written with a good passphrase', genKey(['--out', pp, '--passphrase-env', 'P'], { P: 'correct horse battery' }, capture().log), 0);
  check(g, 'the encrypted file is an ENCRYPTED PKCS#8 PEM', readFileSync(pp, 'utf8').startsWith(`${'-----BEGIN'} ENCRYPTED ${'PRIVATE'} KEY-----`), true);
  const loaded = loadUpdateKey(pp, 'correct horse battery');
  check(g, 'it loads with the passphrase and the public entry matches the .pub file', `${loaded.trust}\n`, readFileSync(`${pp}.pub`, 'utf8'));
  const thrown = (f) => { try { f(); return null; } catch (e) { return e.message; } };
  check(g, 'it does not load with a wrong passphrase', /passphrase/.test(thrown(() => loadUpdateKey(pp, 'wrong wrong wrong')) ?? ''), true);
  check(g, 'it does not load without a passphrase', /passphrase/.test(thrown(() => loadUpdateKey(pp)) ?? ''), true);
  check(g, 'loadUpdateKey refuses to read from inside the repository', /refusing to read/.test(thrown(() => loadUpdateKey(join(OWN_REPO, 'scaffold', 'tools', 'update', 'k.key'))) ?? ''), true);
  check(g, 'keyPathProblem is null for a clean absolute path', keyPathProblem(join(dir, 'fresh.key')), null);
}

// ================================================================ the signing script
const keyDir = sub('signing');
const keyPath = join(keyDir, 'k.key');
genKey(['--out', keyPath], process.env, () => {});
const trust = L.parseTrust(readFileSync(`${keyPath}.pub`, 'utf8').trim());
const draftOf = (p) => `${JSON.stringify({ manifest: p }, null, 2)}\n`;
const apkEntryFake = (extra = {}) => ({ abi: 'arm64-v8a', size: 2 * 1048576 + 5, sha256: hx('a'), signerSha256: hx('b'), chunkSize: 1048576, chunks: [hx('1'), hx('2'), hx('3')], urls: ['https://downloads.example.org/olive/a.apk', 'https://mirror.example.net/olive/a.apk'], ...extra });
const goodPayload = (extra = {}) => ({ ...payload([apkEntryFake()], { issuedAt: L.formatTime(Date.now() - 3600 * 1000), publishedAt: L.formatTime(Date.now() - 3600 * 1000), expiresAt: L.formatTime(Date.now() + 100 * 86400000), sequence: Math.floor(Date.now() / 1000) }), ...extra });
{
  const g = 'sign-update-manifest';
  const dir = sub('sign');
  const put = (name, text) => { const p = join(dir, name); writeFileSync(p, text); return p; };
  const sign = (draftText, extra = [], keyFile = keyPath, env = process.env) => {
    const c = capture();
    const out = join(dir, `out-${Math.random().toString(36).slice(2)}.json`);
    const code = signRun(['--draft', put(`d-${Math.random().toString(36).slice(2)}.json`, draftText), '--key', keyFile, '--out', out, ...extra], env, c.log);
    return { code, out, text: c.text() };
  };
  const p0 = goodPayload();
  const r = sign(draftOf(p0));
  check(g, 'signs a good draft', r.code, 0);
  const signedText = readFileSync(r.out, 'utf8');
  const v = L.verifyDocument(signedText, { trust, channel: 'stable', installedVersionCode: 5100 });
  check(g, 'the output verifies under the PUBLIC key exactly as an app would check it', [v.ok, v.status], [true, 'update']);
  check(g, 'the manifest inside is untouched by signing', JSON.parse(signedText).manifest, p0);
  check(g, 'what is printed carries no private key', /BEGIN|PRIVATE/.test(r.text), false);
  check(g, 'the output is a { manifest, signature } document and nothing else', Object.keys(JSON.parse(signedText)), ['manifest', 'signature']);
  check(g, 'it refuses to overwrite an existing --out without --force', (() => { const c = capture(); return signRun(['--draft', put('d2.json', draftOf(p0)), '--key', keyPath, '--out', r.out], process.env, c.log); })(), 1);
  check(g, '...and replaces it with --force', (() => { const c = capture(); return signRun(['--draft', put('d3.json', draftOf(p0)), '--key', keyPath, '--out', r.out, '--force'], process.env, c.log); })(), 0);
  check(g, 'it refuses a key file inside the repository (even one that does not exist)', sign(draftOf(p0), [], join(OWN_REPO, 'scaffold', 'k.key')).code, 1);
  check(g, 'it refuses a key file inside another git working tree', (() => { const o = sub('keyrepo'); mkdirSync(join(o, '.git')); writeFileSync(join(o, 'k.key'), readFileSync(keyPath)); return sign(draftOf(p0), [], join(o, 'k.key')).code; })(), 1);
  check(g, 'it refuses an already signed draft', sign(`${JSON.stringify(JSON.parse(signedText), null, 2)}\n`).code, 1);
  check(g, 'it refuses a draft that is a bare manifest (no wrapper)', sign(`${JSON.stringify(p0)}\n`).code, 1);
  check(g, 'it refuses a missing field', sign(draftOf((() => { const p = clone(p0); delete p.notes; return p; })())).code, 1);
  check(g, 'it refuses an unknown member (typos must not be signed)', sign(draftOf({ ...p0, typo: 1 })).code, 1);
  check(g, 'it refuses a cleartext download address', sign(draftOf(payload([apkEntryFake({ urls: ['http://downloads.example.org/a.apk'] })], { sequence: 5 }))).code, 1);
  check(g, 'it refuses a versionCode that is not derived from the version', sign(draftOf({ ...p0, versionCode: 5201 })).code, 1);
  check(g, 'it refuses a manifest that has already expired', sign(draftOf({ ...p0, issuedAt: L.formatTime(Date.now() - 200 * 86400000), publishedAt: L.formatTime(Date.now() - 200 * 86400000), expiresAt: L.formatTime(Date.now() - 20 * 86400000) })).code, 1);
  check(g, 'it refuses duplicate keys in the draft', sign('{"manifest":{"a":1,"a":2}}').code, 1);
  check(g, 'it refuses a draft that is not JSON', sign('nope').code, 1);
  check(g, 'it refuses a missing key file', sign(draftOf(p0), [], join(keyDir, 'absent.key')).code, 1);
  const prev = put('prev.json', signedText);
  check(g, '--prev: the SAME sequence is refused (a re-issue needs a higher one)', sign(draftOf(p0), ['--prev', prev]).code, 1);
  check(g, '--prev: a LOWER sequence is refused', sign(draftOf({ ...p0, sequence: p0.sequence - 1 }), ['--prev', prev]).code, 1);
  check(g, '--prev: a higher sequence with the same version is allowed (refreshing the expiry)', sign(draftOf({ ...p0, sequence: p0.sequence + 1 }), ['--prev', prev]).code, 0);
  check(g, '--prev: a lower versionCode is refused as a rollback', sign(draftOf({ ...p0, sequence: p0.sequence + 5, versionName: '0.51.0', versionCode: 5100, minSupportedVersionCode: 5100 }), ['--prev', prev]).code, 1);
  check(g, '--prev: a different channel is refused', sign(draftOf({ ...p0, sequence: p0.sequence + 5, channel: 'beta' }), ['--prev', prev]).code, 1);
  check(g, '--prev: a file that is not a signed manifest is refused', sign(draftOf(p0), ['--prev', put('junk.json', '{}')]).code, 1);
  check(g, '--prev: a newer version with a higher sequence is allowed', sign(draftOf({ ...p0, sequence: p0.sequence + 9, versionName: '0.53.0', versionCode: 5300, minSupportedVersionCode: 5100 }), ['--prev', prev]).code, 0);
  const encKey = join(keyDir, 'enc.key');
  genKey(['--out', encKey, '--passphrase-env', 'P'], { P: 'a long passphrase' }, () => {});
  check(g, 'an encrypted key signs with its passphrase', sign(draftOf(p0), ['--passphrase-env', 'P'], encKey, { P: 'a long passphrase' }).code, 0);
  check(g, 'an encrypted key refuses a wrong passphrase', sign(draftOf(p0), ['--passphrase-env', 'P'], encKey, { P: 'not the passphrase' }).code, 1);
}

// ================================================================ the notes tool
{
  const g = 'draft-release-notes';
  check(g, 'a CHANGELOG title is read for the requested version only', changelogTitle('## [Unreleased]\n\n## [0.52.0] — 2026-11-21 — Calmer: first run\n\n## [0.51.0] — 2026-11-08 — Older\n', '0.51.0'), 'Older');
  check(g, 'a title containing the separator keeps its tail', changelogTitle('## [0.52.0] — 2026-11-21 — A — B\n', '0.52.0'), 'A — B');
  check(g, 'a missing version gives null', changelogTitle('## [0.52.0] — 2026-11-21 — A\n', '0.53.0'), null);
  check(g, 'a bad version argument is refused', draftNotes(['banana'], () => {}), 1);
}

// ================================================================ the package script (prebuilt file, no Flutter, no SDK)
{
  const g = 'build-update-package';
  const dir = sub('pack');
  const v = readVersions();
  const version = v.changelog.version;
  const apk = join(dir, 'in.apk'); writeFileSync(apk, fakeApk(200 * 1024));
  const notes = join(dir, 'notes.txt'); writeFileSync(notes, 'headline: A calmer first run\n- One thing in plain words.\n');
  const noSdk = { ...process.env, ANDROID_HOME: '', ANDROID_SDK_ROOT: '', OLIVE_APKSIGNER: '', OLIVE_AAPT2: '' };
  const pub = L.trustEntry(...[[...trust.keys()][0], [...trust.values()][0]]);
  const args = (out, extra = []) => ['--pubkeys', pub, '--manifest-url', 'https://downloads.example.org/olive/update-manifest.json', '--download-base', 'https://downloads.example.org/olive/v', '--download-base', 'https://mirror.example.net/olive', '--apk', `arm64-v8a=${apk}`, '--notes', notes, '--out', out, '--signer-sha256', hx('c'), ...extra];
  const go = async (name, extra = [], mutate = (a) => a) => { const c = capture(); const out = join(dir, name); const code = await packRun(mutate(args(out, extra)), { log: c.log, env: noSdk }); return { code, out, text: c.text() }; };

  const r = await go('ok');
  check(g, 'packages a prebuilt file and drafts a manifest', r.code, 0);
  const draft = JSON.parse(readFileSync(join(r.out, 'update-manifest.draft.json'), 'utf8'));
  check(g, 'the draft is { manifest } with no signature', Object.keys(draft), ['manifest']);
  check(g, 'the draft passes the strict validator and the publishing policy', [L.validatePayload(draft.manifest), L.policyProblems(draft.manifest, { requireMirror: true })], [[], []]);
  check(g, 'the version and versionCode come from the repository, derived', [draft.manifest.versionName, draft.manifest.versionCode], [version, buildNumber(version)]);
  check(g, 'the notes come from the notes file', [draft.manifest.headline, draft.manifest.notes], ['A calmer first run', ['One thing in plain words.']]);
  const a0 = draft.manifest.apks[0];
  check(g, 'size and hashes describe the file', [a0.size, a0.sha256], [statSync(apk).size, (await L.hashFile(apk, a0.chunkSize)).sha256]);
  check(g, 'the pinned signer is the one given when apksigner is unavailable', a0.signerSha256, hx('c'));
  check(g, 'the addresses are the two bases plus the file name, primary first', a0.urls, [`https://downloads.example.org/olive/v/olive-${version}-direct-arm64-v8a.apk`, `https://mirror.example.net/olive/olive-${version}-direct-arm64-v8a.apk`]);
  check(g, 'the package folder holds the APK, the draft, SHA256SUMS and the next steps', readdirSync(r.out).sort(), [`olive-${version}-direct-arm64-v8a.apk`, 'NEXT-STEPS.txt', 'SHA256SUMS', 'update-manifest.draft.json'].sort());
  check(g, 'SHA256SUMS lists the file', readFileSync(join(r.out, 'SHA256SUMS'), 'utf8').includes(a0.sha256), true);
  check(g, 'the next steps say signing is offline and the manifest goes up last', /offline/.test(readFileSync(join(r.out, 'NEXT-STEPS.txt'), 'utf8')) && /manifest last/.test(readFileSync(join(r.out, 'NEXT-STEPS.txt'), 'utf8')), true);
  check(g, 'it says plainly that the manifest is not signed', /NOT signed/.test(r.text), true);
  check(g, 'nothing in the output or the package is a private key', /PRIVATE KEY/.test(r.text + readFileSync(join(r.out, 'NEXT-STEPS.txt'), 'utf8')), false);

  // and the draft really can be signed and verified end to end
  const signed = join(dir, 'signed.json');
  check(g, 'the draft it wrote can be signed with the offline script', signRun(['--draft', join(r.out, 'update-manifest.draft.json'), '--key', keyPath, '--out', signed, '--allow-loopback-http'], process.env, () => {}), 0);
  check(g, 'and the signed result is accepted by the app\'s rules', L.verifyDocument(readFileSync(signed, 'utf8'), { trust, channel: 'stable', installedVersionCode: 1 }).ok, true);

  check(g, 'refuses a notes file that still says DRAFT', (await go('draftnotes', [], (a) => { writeFileSync(notes + '.d', '# DRAFT x\nheadline: H\n- One.\n'); a[a.indexOf('--notes') + 1] = notes + '.d'; return a; })).code, 1);
  check(g, 'refuses a missing notes file', (await go('nonotes', [], (a) => { a[a.indexOf('--notes') + 1] = join(dir, 'absent.txt'); return a; })).code, 1);
  check(g, 'refuses a missing public key', (await go('nokey', [], (a) => { a.splice(a.indexOf('--pubkeys'), 2); return a; })).code, 1);
  check(g, 'refuses a malformed public key', (await go('badkey', [], (a) => { a[a.indexOf('--pubkeys') + 1] = 'nonsense'; return a; })).code, 1);
  check(g, 'refuses a missing manifest address', (await go('nourl', [], (a) => { a.splice(a.indexOf('--manifest-url'), 2); return a; })).code, 1);
  check(g, 'refuses with no download address', (await go('nobase', [], (a) => a.filter((x, i, arr) => !(x === '--download-base' || arr[i - 1] === '--download-base')))).code, 1);
  check(g, 'refuses a cleartext download address (the manifest would not pass)', (await go('httpbase', [], (a) => { a[a.indexOf('--download-base') + 1] = 'http://downloads.example.org/olive'; return a; })).code, 1);
  check(g, 'refuses a cleartext public server address', (await go('httpserver', ['--base-url', 'http://server.example.org'])).code, 1);
  check(g, 'refuses a validity over 400 days', (await go('long', ['--valid-days', '401'])).code, 1);
  check(g, 'refuses a floor above the version', (await go('floor', ['--min-supported', '999999'])).code, 1);
  check(g, 'refuses an unknown abi', (await go('abi', ['--abi', 'mips'])).code, 1);
  check(g, 'refuses a prebuilt file that is not an APK', (await go('notapk', [], (a) => { const p = join(dir, 'x.apk'); writeFileSync(p, 'not a zip at all, just text, long enough'); a[a.indexOf('--apk') + 1] = `arm64-v8a=${p}`; return a; })).code, 1);
  check(g, 'refuses a prebuilt file with duplicate entries (a zip trick)', (await go('dupzip', [], (a) => { const p = join(dir, 'dup.apk'); writeFileSync(p, zip([{ name: 'AndroidManifest.xml', data: Buffer.from('a') }, { name: 'classes.dex', data: Buffer.from('b') }, { name: 'classes.dex', data: Buffer.from('c') }])); a[a.indexOf('--apk') + 1] = `arm64-v8a=${p}`; return a; })).code, 1);
  check(g, 'refuses to continue without apksigner AND without --signer-sha256 (the certificate pin is mandatory)', (await go('nosigner', [], (a) => { const i = a.indexOf('--signer-sha256'); a.splice(i, 2); return a; })).code, 1);
  check(g, 'refuses a sequence below 1', (await go('seq', ['--sequence', '0'])).code, 1);
}

rmSync(base, { recursive: true, force: true });
let gname = '';
for (const r of rows) {
  if (r.g !== gname) { gname = r.g; console.log(`\n${gname}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`));
}
console.log(`\n${'-'.repeat(60)}\n${pass} passed, ${fail} failed\n`);
process.exitCode = fail === 0 ? 0 : 1;
