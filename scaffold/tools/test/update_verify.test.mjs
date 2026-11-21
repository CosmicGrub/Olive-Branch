/**
 * The verifier (tools/update/verify-update-release.mjs) and the careful download (net_lib.mjs) against REAL local servers that
 * misbehave on purpose. Every server listens on 127.0.0.1 only; the developer option that allows plain http to a literal
 * loopback address is on, which is the only way a test can run without TLS. The hostile cases the app must survive:
 *   a mirror that serves a modified file (MITM), a truncated download, an endless stream (disk fill), extra bytes,
 *   a redirect to cleartext or to another host or to file: or in a loop, a 404/500, a manifest tampered on the server,
 *   signed by the wrong key, replayed, rolled back, for another channel, expired; a zip bomb whose hashes are signed;
 *   and a signing certificate that is not the pinned one.
 *
 * usage: node tools/test/update_verify.test.mjs
 */
import { mkdtempSync, rmSync, writeFileSync, mkdirSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { download } from '../update/net_lib.mjs';
import { run as verifyCli, verifyRelease } from '../update/verify-update-release.mjs';
import * as L from '../update/manifest_lib.mjs';
import { NOW, apkEntry, clone, fakeApk, fakeApksigner, hx, keypair, noise, payload, serve, zip } from './update_testkit.mjs';

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = JSON.stringify(a) === JSON.stringify(e); ok ? pass++ : fail++; rows.push({ g, n, ok, a: JSON.stringify(a), e: JSON.stringify(e) }); };

const dir = mkdtempSync(join(tmpdir(), 'olive-verify-test-'));
const K = keypair();
const OTHER = keypair();
const noSdk = { ...process.env, ANDROID_HOME: '', ANDROID_SDK_ROOT: '', OLIVE_APKSIGNER: '', OLIVE_AAPT2: '' };
const apkBytes = fakeApk(300 * 1024, 'good');
const apkPath = join(dir, 'good.apk'); writeFileSync(apkPath, apkBytes);
const signedDoc = (p, k = K) => L.signPayload(p, k.privateKey, k.kid);
const base = (extra = {}) => ({ pubkeys: K.trust, manifest: null, channel: 'stable', installedVersionCode: 5100, extraHosts: [], allowUnchecked: true, allowLoopbackHttp: true, now: NOW, ...extra });
const verdict = (r) => ({ ok: r.ok, failed: r.checks.filter((c) => c.status === 'fail').map((c) => c.name) });
const failedWith = (r, re) => r.checks.some((c) => c.status === 'fail' && re.test(`${c.name} ${c.detail}`));

// a normal publisher: manifest + primary + mirror, each its own server
const primary = await serve((req, res) => { if (req.url === '/a.apk') { res.writeHead(200, { 'content-length': apkBytes.length }); res.end(apkBytes); } else { res.writeHead(404); res.end(); } });
const mirror = await serve((req, res) => { res.writeHead(200, { 'content-length': apkBytes.length }); res.end(apkBytes); });
const entry = await apkEntry(apkPath, [primary.url('/a.apk'), mirror.url('/a.apk')]);
const goodPayload = payload([entry]);
let manifestText = `${JSON.stringify(signedDoc(goodPayload), null, 2)}\n`;
const site = await serve((req, res) => { if (req.url === '/update-manifest.json') { res.writeHead(200, { 'content-type': 'application/json' }); res.end(manifestText); } else { res.writeHead(404); res.end(); } });

// ================================================================ the happy path
{
  const g = 'published update';
  const r = await verifyRelease(base({ manifest: site.url('/update-manifest.json') }), noSdk);
  check(g, 'a good manifest with a primary and a mirror verifies end to end', verdict(r), { ok: true, failed: [] });
  check(g, 'both addresses were downloaded and matched byte for byte', r.checks.filter((c) => /bytes match the signed manifest/.test(c.name) && c.status === 'pass').length, 2);
  check(g, 'the zip structure of the file was inspected', r.checks.some((c) => /zip structure/.test(c.name) && c.status === 'pass'), true);
  check(g, 'without apksigner the certificate is reported as NOT CHECKED (a warning only because it was allowed)', r.checks.find((c) => /signing certificate/.test(c.name)).status, 'warn');
  const strictR = await verifyRelease(base({ manifest: site.url('/update-manifest.json'), allowUnchecked: false }), noSdk);
  check(g, 'without apksigner and without the allowance, verification FAILS (a gap is not a pass)', failedWith(strictR, /apksigner not found/), true);
  const lines = []; const code = await verifyCli(['--manifest', site.url('/update-manifest.json'), '--pubkeys', K.trust, '--installed-version-code', '5100', '--allow-unchecked-signer', '--allow-loopback-http', '--now', L.formatTime(NOW)], { log: (s) => lines.push(s), env: noSdk });
  check(g, 'the command line prints VERIFIED and exits 0', [code, lines.some((l) => l.trim().startsWith('VERIFIED'))], [0, true]);
  const lines2 = []; const code2 = await verifyCli(['--manifest', site.url('/update-manifest.json'), '--pubkeys', OTHER.trust, '--allow-loopback-http', '--now', L.formatTime(NOW)], { log: (s) => lines2.push(s), env: noSdk });
  check(g, 'the command line with the wrong public key prints NOT VERIFIED and exits 1', [code2, lines2.some((l) => l.trim().startsWith('NOT VERIFIED'))], [1, true]);
  check(g, 'with no arguments it prints usage and exits 1', await verifyCli([], { log: () => {}, env: noSdk }), 1);
}

// ================================================================ the manifest is hostile
{
  const g = 'manifest';
  const run = async (text, extra = {}) => { manifestText = text; return verifyRelease(base({ manifest: site.url('/update-manifest.json'), ...extra }), noSdk); };
  const good = `${JSON.stringify(signedDoc(goodPayload), null, 2)}\n`;
  const t = clone(JSON.parse(good)); t.manifest.versionCode = 5300;
  check(g, 'a manifest tampered on the server is refused', failedWith(await run(JSON.stringify(t)), /badSignature/), true);
  check(g, 'a manifest signed by a different key is refused', failedWith(await run(JSON.stringify(signedDoc(goodPayload, OTHER))), /unknownKey/), true);
  check(g, 'a rollback (installed build is newer) is refused', failedWith(await run(good, { installedVersionCode: 5300 }), /rollback/), true);
  check(g, 'a replay (an app already accepted a newer sequence) is refused', failedWith(await run(good, { highestSequence: 5000 }), /replayed/), true);
  check(g, 'a manifest for another channel is refused', failedWith(await run(good, { channel: 'beta' }), /wrongChannel/), true);
  check(g, 'an expired manifest is refused', failedWith(await run(good, { now: NOW + 400 * 86400000 }), /expired/), true);
  check(g, 'garbage is refused', failedWith(await run('<html>captive portal</html>'), /notJson/), true);
  check(g, 'an empty answer is refused', failedWith(await run(''), /notJson/), true);
  check(g, 'a manifest larger than 256 KiB is refused before it is read', failedWith(await run(' '.repeat(300 * 1024)), /tooMuchData|tooLarge/), true);
  // The publisher check is never looser than the app: text the app refuses must FAIL here, not warn and end VERIFIED.
  for (const [what, extra] of [['markup in a note', { notes: ['Tap <b>here</b>'] }], ['a bidi override in the headline', { headline: `Safe${String.fromCharCode(0x202e)}fas` }], ['edge spaces in a note', { notes: [' padded '] }]]) {
    const r = await run(JSON.stringify(signedDoc({ ...goodPayload, ...extra })));
    check(g, `${what}: the app would silently ignore this manifest, so the verifier FAILS it`, [r.ok, failedWith(r, /accepted by the app[^]*badShape/)], [false, true]);
  }
  const poisonedSeq = await run(JSON.stringify(signedDoc({ ...goodPayload, sequence: Number.MAX_SAFE_INTEGER })));
  check(g, 'a sequence far above the issue time fails the release policy (it would strand every phone that accepted it)', [poisonedSeq.ok, failedWith(poisonedSeq, /release policy[^]*replayed/)], [false, true]);
  check(g, 'a versionCode not derived from the version fails the release policy even though it is signed', failedWith(await run(JSON.stringify(signedDoc({ ...goodPayload, versionCode: 5201 }))), /release policy/), true);
  check(g, 'a mirror-less manifest passes with a warning, not a failure', await (async () => { const r = await run(JSON.stringify(signedDoc(payload([{ ...entry, urls: [entry.urls[0]] }])))); return [r.ok, r.checks.find((c) => /mirror is named/.test(c.name)).status]; })(), [true, 'warn']);
  const cleartext = base({ manifest: site.url('/update-manifest.json'), allowLoopbackHttp: false });
  manifestText = good;
  const r = await verifyRelease(cleartext, noSdk);
  check(g, 'a manifest address in cleartext is refused unless the developer option is on', failedWith(r, /cleartext/), true);
  const r2 = await verifyRelease(base({ manifest: join(dir, 'absent.json') }), noSdk);
  check(g, 'a missing local file is a failure', r2.ok, false);
  writeFileSync(join(dir, 'm.json'), good);
  check(g, 'a local manifest file verifies the same as a downloaded one', (await verifyRelease(base({ manifest: join(dir, 'm.json') }), noSdk)).ok, true);
  check(g, 'a missing public key is a failure before anything is fetched', (await verifyRelease(base({ manifest: join(dir, 'm.json'), pubkeys: '' }), noSdk)).ok, false);
  manifestText = good;
}

// ================================================================ the files are hostile
{
  const g = 'files';
  const withUrls = async (urls, apkOver = {}) => {
    manifestText = JSON.stringify(signedDoc(payload([{ ...entry, ...apkOver, urls }])));
    return verifyRelease(base({ manifest: site.url('/update-manifest.json') }), noSdk);
  };

  // MITM on the mirror: right length, one flipped byte
  const evil = Buffer.from(apkBytes); evil[evil.length - 100] ^= 0xff;
  const mitm = await serve((req, res) => { res.writeHead(200, { 'content-length': evil.length }); res.end(evil); });
  let r = await withUrls([primary.url('/a.apk'), mitm.url('/a.apk')]);
  check(g, 'a mirror serving a modified file (right size) is caught by the hashes', [r.ok, failedWith(r, /hashMismatch/)], [false, true]);
  check(g, '...while the honest primary still passes on its own', r.checks.some((c) => /address 1 \(primary\) bytes match/.test(c.name) && c.status === 'pass'), true);
  await mitm.close();

  // MITM that also fixes the length (shorter) and one that adds bytes
  const shorter = apkBytes.subarray(0, apkBytes.length - 7);
  const srvShort = await serve((req, res) => { res.writeHead(200, { 'content-length': shorter.length }); res.end(shorter); });
  r = await withUrls([srvShort.url('/a.apk')]);
  check(g, 'a complete-looking but shorter file is refused as truncated', failedWith(r, /truncated/), true);
  await srvShort.close();
  const longer = Buffer.concat([apkBytes, Buffer.from('tail')]);
  const srvLong = await serve((req, res) => { res.writeHead(200, { 'content-length': longer.length }); res.end(longer); });
  r = await withUrls([srvLong.url('/a.apk')]);
  check(g, 'a file with extra bytes appended is refused', failedWith(r, /tooMuchData/), true);
  await srvLong.close();

  // truncation on the wire: promise N bytes, send half, hang up
  const srvCut = await serve((req, res) => { res.writeHead(200, { 'content-length': apkBytes.length }); res.write(apkBytes.subarray(0, apkBytes.length / 2)); setTimeout(() => res.socket.destroy(), 20); });
  r = await withUrls([srvCut.url('/a.apk')]);
  check(g, 'a download cut off mid-stream is refused as truncated and leaves nothing behind', failedWith(r, /truncated/), true);
  await srvCut.close();

  // an endless stream with no length: must stop at the cap, quickly
  let sent = 0;
  const srvEndless = await serve((req, res) => { res.writeHead(200); const pump = () => { while (res.write(Buffer.alloc(65536, 1))) { sent += 65536; if (sent > 64 * 1024 * 1024) return; } res.once('drain', pump); }; pump(); });
  const t0 = Date.now();
  r = await withUrls([srvEndless.url('/a.apk')]);
  check(g, 'an endless stream is cut at the signed size and refused (no disk or memory fill)', [failedWith(r, /tooMuchData/), Date.now() - t0 < 10000], [true, true]);
  check(g, '...and the server was told to stop long before 64 MiB', sent < 64 * 1024 * 1024, true);
  await srvEndless.close();

  // a lie in Content-Length
  const srvBig = await serve((req, res) => { res.writeHead(200, { 'content-length': 10 * 1024 * 1024 * 1024 }); res.end('x'); });
  r = await withUrls([srvBig.url('/a.apk')]);
  check(g, 'a Content-Length far beyond the signed size is refused before any byte is read', failedWith(r, /tooMuchData/), true);
  await srvBig.close();

  // status codes
  for (const code of [404, 500, 403, 204, 206]) {
    const s = await serve((req, res) => { res.writeHead(code); res.end(); });
    r = await withUrls([s.url('/a.apk')]);
    check(g, `HTTP ${code} is a failure, not a pass`, failedWith(r, /httpError/), true);
    await s.close();
  }

  // a zip bomb whose size and hashes ARE signed: the manifest is honest about a hostile file
  const bombBytes = zip([{ name: 'AndroidManifest.xml', data: Buffer.from('a') }, { name: 'classes.dex', data: Buffer.from('b') }, { name: 'x.bin', data: Buffer.from('z'), comp: 100, unc: 3 * 1024 * 1024 * 1024 }]);
  const bombPath = join(dir, 'bomb.apk'); writeFileSync(bombPath, bombBytes);
  const bomb = await serve((req, res) => { res.writeHead(200, { 'content-length': bombBytes.length }); res.end(bombBytes); });
  r = await withUrls([bomb.url('/a.apk')], await apkEntry(bombPath, [bomb.url('/a.apk')]));
  check(g, 'a signed-and-hashed zip bomb is still refused by the structure check', [failedWith(r, /zip structure/), failedWith(r, /uncompressed/)], [true, true]);
  await bomb.close();

  // duplicate zip entries
  const dupBytes = zip([{ name: 'AndroidManifest.xml', data: Buffer.from('a') }, { name: 'classes.dex', data: Buffer.from('b') }, { name: 'classes.dex', data: Buffer.from('evil') }]);
  const dupPath = join(dir, 'dup.apk'); writeFileSync(dupPath, dupBytes);
  const dup = await serve((req, res) => { res.writeHead(200, { 'content-length': dupBytes.length }); res.end(dupBytes); });
  r = await withUrls([dup.url('/a.apk')], await apkEntry(dupPath, [dup.url('/a.apk')]));
  check(g, 'a file with duplicate zip entries is refused', failedWith(r, /duplicate entry/), true);
  await dup.close();

  // not a zip at all but correctly hashed
  const junk = Buffer.from('this is not an apk, but its hash is signed');
  const junkPath = join(dir, 'junk.apk'); writeFileSync(junkPath, junk);
  const jsrv = await serve((req, res) => { res.writeHead(200, { 'content-length': junk.length }); res.end(junk); });
  r = await withUrls([jsrv.url('/a.apk')], await apkEntry(junkPath, [jsrv.url('/a.apk')]));
  check(g, 'a hashed file that is not a zip is refused', failedWith(r, /zip structure/), true);
  await jsrv.close();

  // --apk-dir: check before uploading
  const upload = join(dir, 'upload'); mkdirSync(upload); writeFileSync(join(upload, 'a.apk'), apkBytes);
  manifestText = JSON.stringify(signedDoc(payload([{ ...entry, urls: ['https://downloads.example.org/olive/a.apk', 'https://mirror.example.net/olive/a.apk'] }])));
  r = await verifyRelease(base({ manifest: site.url('/update-manifest.json'), apkDir: upload }), noSdk);
  check(g, '--apk-dir checks local files named by the last part of each address (pre-upload check)', verdict(r), { ok: true, failed: [] });
  writeFileSync(join(upload, 'a.apk'), evil);
  r = await verifyRelease(base({ manifest: site.url('/update-manifest.json'), apkDir: upload }), noSdk);
  check(g, '--apk-dir catches a corrupted local file', failedWith(r, /hashMismatch/), true);
  rmSync(join(upload, 'a.apk'));
  r = await verifyRelease(base({ manifest: site.url('/update-manifest.json'), apkDir: upload }), noSdk);
  check(g, '--apk-dir reports a file that was not copied', failedWith(r, /not in --apk-dir/), true);
}

// ================================================================ redirects
{
  const g = 'redirects';
  const target = await serve((req, res) => { res.writeHead(200, { 'content-length': apkBytes.length }); res.end(apkBytes); });
  const redirectTo = async (loc, status = 302) => serve((req, res) => { res.writeHead(status, { location: loc }); res.end(); });
  const opts = (extra = {}) => ({ maxBytes: apkBytes.length + 1, to: 'memory', allowLoopbackHttp: true, allowedHosts: ['127.0.0.1'], ...extra });
  const code = async (url, o) => { try { await download(url, o); return 'ok'; } catch (e) { return e.code; } };

  const ok = await redirectTo(target.url('/a.apk'));
  check(g, 'a redirect inside the trusted loopback host is followed', await code(ok.url('/x'), opts()), 'ok');
  check(g, '...every redirect status (301, 302, 303, 307, 308) alike', (await Promise.all([301, 303, 307, 308].map(async (s) => { const r = await redirectTo(target.url('/a.apk'), s); const c = await code(r.url('/x'), opts()); await r.close(); return c; }))).every((c) => c === 'ok'), true);
  const toClear = await redirectTo('http://127.0.0.2:9/a.apk');
  check(g, 'a redirect to cleartext on a non-loopback address is refused', await code(toClear.url('/x'), opts()), 'badRedirect');
  const toOther = await redirectTo('https://evil.example.net/a.apk');
  check(g, 'a redirect to another host is refused without connecting', await code(toOther.url('/x'), opts()), 'badRedirect');
  const toFile = await redirectTo('file:///etc/passwd');
  check(g, 'a redirect to file: is refused', await code(toFile.url('/x'), opts()), 'badRedirect');
  const toCreds = await redirectTo('https://user:pw@127.0.0.1/a.apk');
  check(g, 'a redirect carrying credentials is refused', await code(toCreds.url('/x'), opts()), 'badRedirect');
  const toData = await redirectTo('data:text/plain,hello');
  check(g, 'a redirect to data: is refused', await code(toData.url('/x'), opts()), 'badRedirect');
  let loopUrl;
  const loop = await serve((req, res) => { res.writeHead(302, { location: loopUrl }); res.end(); });
  loopUrl = loop.url('/x');
  check(g, 'a redirect loop ends (at most five hops)', await code(loop.url('/x'), opts()), 'badRedirect');
  const toLook = await redirectTo('https://127.0.0.1.evil.example.net/a.apk');
  check(g, 'a look-alike host is refused', await code(toLook.url('/x'), opts()), 'badRedirect');
  const noLoc = await serve((req, res) => { res.writeHead(302); res.end(); });
  check(g, 'a 302 with no Location is a plain HTTP failure', await code(noLoc.url('/x'), opts()), 'httpError');
  check(g, 'without the developer option the same loopback redirect is refused (cleartext)', await code(ok.url('/x'), opts({ allowLoopbackHttp: false })), 'badRedirect');
  const hostile = await redirectTo(target.url('/a.apk'));
  const r = await verifyRelease(base({ manifest: join(dir, 'm.json') }), noSdk);
  void r; void hostile;
  for (const s of [target, ok, toClear, toOther, toFile, toCreds, toData, loop, toLook, noLoc, hostile]) await s.close();
}

// ================================================================ the signing certificate (with a stand-in apksigner)
{
  const g = 'certificate';
  const goodSigner = fakeApksigner(join(dir, 'tools-good'), hx('b'));
  const otherSigner = fakeApksigner(join(dir, 'tools-other'), hx('9'));
  const brokenSigner = fakeApksigner(join(dir, 'tools-broken'), hx('b'), { fail: true });
  manifestText = JSON.stringify(signedDoc(payload([entry])));
  const run = (signer, extra = {}) => verifyRelease(base({ manifest: site.url('/update-manifest.json'), allowUnchecked: false, ...extra }), { ...noSdk, OLIVE_APKSIGNER: signer });
  let r = await run(goodSigner);
  check(g, 'a file signed by the pinned certificate passes', [r.checks.find((c) => /signing certificate/.test(c.name)).status, r.ok], ['pass', true]);
  r = await run(otherSigner);
  check(g, 'a file signed by a DIFFERENT certificate than the one pinned is refused', [r.ok, failedWith(r, /different certificate/)], [false, true]);
  r = await run(brokenSigner);
  check(g, 'a file whose signature does not verify is refused', [r.ok, failedWith(r, /apksigner refused/)], [false, true]);
  const installed = join(dir, 'installed.apk'); writeFileSync(installed, apkBytes);
  r = await run(goodSigner, { installedApk: installed });
  check(g, 'with the installed build given, an update signed by the same certificate is accepted', r.checks.find((c) => /same signer as the installed/.test(c.name))?.status, 'pass');
  const mixed = fakeApksigner(join(dir, 'tools-mixed'), hx('b'));
  r = await verifyRelease(base({ manifest: site.url('/update-manifest.json'), allowUnchecked: false, installedApk: installed }), { ...noSdk, OLIVE_APKSIGNER: otherSigner });
  check(g, 'an installed build with another certificate than the pinned one is a failure', r.ok, false);
  void mixed;
}

await Promise.all([primary.close(), mirror.close(), site.close()]);
rmSync(dir, { recursive: true, force: true });
let gname = '';
for (const r of rows) {
  if (r.g !== gname) { gname = r.g; console.log(`\n${gname}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`));
}
console.log(`\n${'-'.repeat(60)}\n${pass} passed, ${fail} failed\n`);
process.exitCode = fail === 0 ? 0 : 1;
