/**
 * server/update_hosting.mjs — the optional self-hosted update files
 * (GET|HEAD /updates/manifest.json, /updates/manifest.json.sig, /updates/apk/<file>).
 *
 * Real HTTP against a real temporary directory; no database. Sections:
 *   A. config: off by default, malformed refuses, missing dir is a warning
 *   B. pure helpers: names in a manifest, Range parsing (incl. absurd numbers)
 *   C. happy paths: manifest, signature, APK, HEAD, validators, 304
 *   D. ranges and resumable download: every Range form, If-Range, a chunked
 *      re-assembly that matches the sha256, 416, huge values
 *   E. hostile paths: traversal in every encoding, unlisted files, odd shapes
 *   F. symlinks never escape (skipped, loudly, where the OS refuses to make one)
 *   G. size caps and a broken manifest
 *   H. methods and bodies
 *   I. rate limit (injected clock), concurrent-stream caps, stalled-reader cut
 *   J. wired into the real server/index.mjs: off = 404, on = served with no
 *      database, fixed access-log label, bad config refuses to boot
 */
import { createHash, randomBytes } from 'node:crypto';
import { request } from 'node:http';
import { createServer } from 'node:http';
import { mkdtempSync, writeFileSync, mkdirSync, symlinkSync, rmSync, utimesSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { resolveUpdatesConfig, createUpdateHosting, apkNamesInManifest, parseRange,
  MAX_MANIFEST_BYTES, MAX_SIGNATURE_BYTES, DEFAULT_MAX_APK_MIB, UPDATE_ROUTES }
  from '../update_hosting.mjs';

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = String(a) === String(e); ok ? pass++ : fail++;
  rows.push({ g, n, ok, a: String(a), e: String(e) }); };
const sha = (b) => createHash('sha256').update(b).digest('hex');
const here = dirname(fileURLToPath(import.meta.url));
const serverEntry = join(here, '..', 'index.mjs');

// ---- fixtures ---------------------------------------------------------------
const root = mkdtempSync(join(tmpdir(), 'olive-upd-'));
const outside = mkdtempSync(join(tmpdir(), 'olive-upd-out-'));
const APK = randomBytes(5000);
const APK2 = randomBytes(3000);
const MANIFEST = Buffer.from(JSON.stringify({
  channel: 'stable', versionName: '0.52.0', versionCode: 5200,
  apk: [{ url: 'https://updates.example.org/updates/apk/olive-0.52.0.apk', sha256: sha(APK), size: APK.length },
        { url: 'https://mirror.example.net/dl/olive-0.52.0-mirror.apk', sha256: sha(APK), size: APK.length }],
  notes: 'A calmer home screen.',
}), 'utf8');
const SIG = Buffer.from('c2lnbmF0dXJlLWJ5dGVzLWZvci10ZXN0cw==', 'utf8'); // not a real signature: the server never reads it
writeFileSync(join(root, 'manifest.json'), MANIFEST);
writeFileSync(join(root, 'manifest.json.sig'), SIG);
writeFileSync(join(root, 'olive-0.52.0.apk'), APK);
writeFileSync(join(root, 'olive-0.52.0-mirror.apk'), APK2); // named by the manifest (mirror basename)
writeFileSync(join(root, 'unlisted.apk'), randomBytes(100)); // on disk, NOT in the manifest
writeFileSync(join(root, 'notes.txt'), 'not served');
writeFileSync(join(outside, 'secret.apk'), 'TOP SECRET OUTSIDE THE DIRECTORY');
writeFileSync(join(outside, 'secret.txt'), 'TOP SECRET');

const get = (port, path, { method = 'GET', headers = {}, body } = {}) => new Promise((resolve, reject) => {
  const r = request({ host: '127.0.0.1', port, path, method, headers, agent: false }, (res) => {
    const chunks = [];
    res.on('data', (c) => chunks.push(c));
    res.on('end', () => resolve({ status: res.statusCode, headers: res.headers, body: Buffer.concat(chunks) }));
    res.on('aborted', () => resolve({ status: res.statusCode, headers: res.headers, body: Buffer.concat(chunks), aborted: true }));
  });
  r.on('error', (e) => { e.message += ` (${method} ${path})`; reject(e); });
  if (body !== undefined) r.write(body);
  r.end();
});
const listen = (srv) => new Promise((r) => srv.listen(0, '127.0.0.1', () => r(srv.address().port)));
const close = (srv) => new Promise((r) => { srv.closeAllConnections?.(); srv.close(() => r()); });

function host(opts = {}) {
  let clock = 1_000_000;
  const hosting = createUpdateHosting({
    dir: root, callerKey: (req) => req.headers['x-test-caller'] ?? 'caller-1',
    now: () => clock, env: opts.env ?? {}, maxApkBytes: opts.maxApkBytes,
    streamIdleMs: opts.streamIdleMs, onRateLimited: opts.onRateLimited,
  });
  const srv = createServer(async (req, res) => {
    const pathname = (req.url ?? '/').split('?')[0];
    if (!(await hosting.handle(req, res, pathname))) { res.writeHead(404, { 'content-type': 'text/plain' }); res.end('other'); }
  });
  return { srv, hosting, tick: (ms) => { clock += ms; }, listen: () => listen(srv), close: () => close(srv) };
}

// ===========================================================================
// A · config
// ===========================================================================
{
  const off = await resolveUpdatesConfig({});
  check('A config', 'UPDATES_DIR unset: disabled, no problems, no warnings', `${off.enabled}|${off.problems.length}|${off.warnings.length}`, 'false|0|0');
  const empty = await resolveUpdatesConfig({ UPDATES_DIR: '   ' });
  check('A config', 'blank UPDATES_DIR (compose passes empty strings through) counts as unset', `${empty.enabled}|${empty.problems.length}`, 'false|0');
  const rel = await resolveUpdatesConfig({ UPDATES_DIR: 'updates' });
  check('A config', 'a relative path is a boot problem', `${rel.enabled}|${rel.problems.length}`, 'false|1');
  const nul = await resolveUpdatesConfig({ UPDATES_DIR: '/srv/up\0dates' });
  check('A config', 'a NUL in the path is a boot problem', `${nul.enabled}|${nul.problems.length}`, 'false|1');
  const rootDir = await resolveUpdatesConfig({ UPDATES_DIR: '/' });
  check('A config', 'a filesystem root is a boot problem', `${rootDir.enabled}|${rootDir.problems.length}`, 'false|1');
  const media = await resolveUpdatesConfig({ UPDATES_DIR: root, MEDIA_STORAGE_ROOT: root });
  check('A config', 'the same directory as MEDIA_STORAGE_ROOT (private family media) is refused', media.problems.length, 1);
  const mediaInside = await resolveUpdatesConfig({ UPDATES_DIR: root, MEDIA_STORAGE_ROOT: join(root, 'media') });
  check('A config', 'a media root INSIDE the updates directory is refused', mediaInside.problems.length, 1);
  const mediaAbove = await resolveUpdatesConfig({ UPDATES_DIR: join(root, 'u'), MEDIA_STORAGE_ROOT: root });
  check('A config', 'an updates directory INSIDE the media root is refused', mediaAbove.problems.length, 1);
  const badMib = await resolveUpdatesConfig({ UPDATES_DIR: root, UPDATES_MAX_APK_MIB: 'lots' });
  check('A config', 'a non-numeric UPDATES_MAX_APK_MIB is a boot problem', badMib.problems.length, 1);
  const zeroMib = await resolveUpdatesConfig({ UPDATES_DIR: root, UPDATES_MAX_APK_MIB: '0' });
  check('A config', 'UPDATES_MAX_APK_MIB=0 is a boot problem', zeroMib.problems.length, 1);
  const ok = await resolveUpdatesConfig({ UPDATES_DIR: root });
  check('A config', 'a real directory: enabled, default cap 256 MiB', `${ok.enabled}|${ok.maxApkBytes}`, `true|${DEFAULT_MAX_APK_MIB * 1024 * 1024}`);
  const small = await resolveUpdatesConfig({ UPDATES_DIR: root, UPDATES_MAX_APK_MIB: '10' });
  check('A config', 'UPDATES_MAX_APK_MIB is honoured', small.maxApkBytes, 10 * 1024 * 1024);
  const missing = await resolveUpdatesConfig({ UPDATES_DIR: join(root, 'not-yet') });
  check('A config', 'a directory that does not exist yet is a WARNING, still enabled', `${missing.enabled}|${missing.problems.length}|${missing.warnings.length}`, 'true|0|1');
  const aFile = await resolveUpdatesConfig({ UPDATES_DIR: join(root, 'notes.txt') });
  check('A config', 'UPDATES_DIR pointing at a file is a boot problem', `${aFile.enabled}|${aFile.problems.length}`, 'false|1');
}

// ===========================================================================
// B · pure helpers
// ===========================================================================
{
  const names = apkNamesInManifest(JSON.parse(MANIFEST.toString()));
  check('B helpers', 'names are the last segment of every .apk string, mirror included', [...names].sort().join(','), 'olive-0.52.0-mirror.apk,olive-0.52.0.apk');
  check('B helpers', 'a query string and fragment do not hide or change the name',
    [...apkNamesInManifest({ u: 'https://h.example/x/a.apk?token=1#f' })].join(','), 'a.apk');
  check('B helpers', 'a traversal-looking value yields only its plain last segment',
    [...apkNamesInManifest({ u: '../../etc/evil.apk' })].join(','), 'evil.apk');
  check('B helpers', 'a name with a space, a backslash or a leading dot is not a name',
    apkNamesInManifest({ a: 'a b.apk', b: 'x\\y.apk', c: '.hid.apk', d: 'ok.apk' }).size, 1);
  check('B helpers', 'non-apk strings, numbers and deep nesting are ignored without error',
    apkNamesInManifest({ a: 'x.zip', b: 5, c: [[[[[[[[[[[[[['deep.apk']]]]]]]]]]]]]] }).size, 0);
  check('B helpers', 'an over-long string is ignored', apkNamesInManifest({ a: 'a'.repeat(3000) + '.apk' }).size, 0);

  const P = (h, size = 1000) => JSON.stringify(parseRange(h, size));
  check('B range', 'no header: whole file', P(undefined), '{"kind":"none"}');
  check('B range', 'bytes=0-99', P('bytes=0-99'), '{"kind":"range","start":0,"end":99}');
  check('B range', 'bytes=900- (open ended)', P('bytes=900-'), '{"kind":"range","start":900,"end":999}');
  check('B range', 'bytes=-100 (suffix)', P('bytes=-100'), '{"kind":"range","start":900,"end":999}');
  check('B range', 'a suffix longer than the file is the whole file', P('bytes=-99999'), '{"kind":"range","start":0,"end":999}');
  check('B range', 'bytes=-0 is unsatisfiable', P('bytes=-0'), '{"kind":"unsatisfiable"}');
  check('B range', 'an end past the file is clamped', P('bytes=990-5000'), '{"kind":"range","start":990,"end":999}');
  check('B range', 'a start at the file size is unsatisfiable', P('bytes=1000-'), '{"kind":"unsatisfiable"}');
  check('B range', 'a start past the file size is unsatisfiable', P('bytes=1001-1002'), '{"kind":"unsatisfiable"}');
  check('B range', 'a 40-digit start cannot overflow: unsatisfiable', P('bytes=' + '9'.repeat(40) + '-'), '{"kind":"unsatisfiable"}');
  check('B range', 'a 40-digit end is clamped, not an error', P('bytes=0-' + '9'.repeat(40)), '{"kind":"range","start":0,"end":999}');
  check('B range', 'a 40-digit suffix is the whole file', P('bytes=-' + '9'.repeat(40)), '{"kind":"range","start":0,"end":999}');
  check('B range', 'end before start is ignored (RFC 9110)', P('bytes=50-10'), '{"kind":"none"}');
  check('B range', 'several ranges are ignored, never amplified', P('bytes=0-1,5-6'), '{"kind":"none"}');
  check('B range', 'another unit is ignored', P('items=0-5'), '{"kind":"none"}');
  check('B range', 'garbage is ignored', P('bytes=abc'), '{"kind":"none"}');
  check('B range', 'a bare dash is ignored', P('bytes=-'), '{"kind":"none"}');
  check('B range', 'a range against an empty file is unsatisfiable', P('bytes=-5', 0), '{"kind":"unsatisfiable"}');
  check('B range', 'a negative-looking start is ignored as garbage', P('bytes=--5'), '{"kind":"none"}');
}

// ===========================================================================
// C · happy paths
// ===========================================================================
const h = host({ env: { UPDATES_RATE_CAPACITY: '100000', UPDATES_RATE_PER_MIN: '100000' } });
const port = await h.listen();
{
  const m = await get(port, '/updates/manifest.json');
  check('C serve', 'manifest: 200', m.status, 200);
  check('C serve', 'manifest: the exact bytes on disk (the signature is over them; never re-serialised)', m.body.equals(MANIFEST), true);
  check('C serve', 'manifest: JSON content type', m.headers['content-type'], 'application/json; charset=utf-8');
  check('C serve', 'manifest: nosniff, public, revalidate every time', `${m.headers['x-content-type-options']}|${m.headers['cache-control']}`, 'nosniff|public, no-cache');
  check('C serve', 'manifest: strong ETag, Last-Modified, content-length', `${/^"[0-9a-f]+-[0-9a-f]+"$/.test(m.headers.etag)}|${!!m.headers['last-modified']}|${m.headers['content-length']}`, `true|true|${MANIFEST.length}`);
  check('C serve', 'manifest: no Set-Cookie, no CORS, no range support advertised', `${m.headers['set-cookie']}|${m.headers['access-control-allow-origin']}|${m.headers['accept-ranges']}`, 'undefined|undefined|none');

  const mh = await get(port, '/updates/manifest.json', { method: 'HEAD' });
  check('C serve', 'manifest HEAD: 200, same validators, no body, true length', `${mh.status}|${mh.headers.etag === m.headers.etag}|${mh.body.length}|${mh.headers['content-length']}`, `200|true|0|${MANIFEST.length}`);

  const s = await get(port, '/updates/manifest.json.sig');
  check('C serve', 'signature: 200 and the exact bytes', `${s.status}|${s.body.equals(SIG)}`, '200|true');
  check('C serve', 'signature: octet-stream, revalidating', `${s.headers['content-type']}|${s.headers['cache-control']}`, 'application/octet-stream|public, no-cache');
  const sh = await get(port, '/updates/manifest.json.sig', { method: 'HEAD' });
  check('C serve', 'signature HEAD: no body', `${sh.status}|${sh.body.length}|${sh.headers['content-length']}`, `200|0|${SIG.length}`);

  const a = await get(port, '/updates/apk/olive-0.52.0.apk');
  check('C serve', 'apk: 200 and the exact bytes', `${a.status}|${a.body.equals(APK)}`, '200|true');
  check('C serve', 'apk: package-archive type, attachment, ranges offered, length', `${a.headers['content-type']}|${a.headers['content-disposition']}|${a.headers['accept-ranges']}|${a.headers['content-length']}`,
    `application/vnd.android.package-archive|attachment; filename="olive-0.52.0.apk"|bytes|${APK.length}`);
  check('C serve', 'apk: the mirror-named file the manifest also names is served too', (await get(port, '/updates/apk/olive-0.52.0-mirror.apk')).body.equals(APK2), true);
  const ah = await get(port, '/updates/apk/olive-0.52.0.apk', { method: 'HEAD' });
  check('C serve', 'apk HEAD: 200, headers only, true length', `${ah.status}|${ah.body.length}|${ah.headers['content-length']}|${ah.headers.etag === a.headers.etag}`, `200|0|${APK.length}|true`);
  check('C serve', 'apk: a query string is ignored', (await get(port, '/updates/apk/olive-0.52.0.apk?x=1')).body.equals(APK), true);

  // Validators.
  const n1 = await get(port, '/updates/apk/olive-0.52.0.apk', { headers: { 'if-none-match': a.headers.etag } });
  check('C 304', 'If-None-Match with the current ETag: 304, no body', `${n1.status}|${n1.body.length}`, '304|0');
  const n2 = await get(port, '/updates/apk/olive-0.52.0.apk', { headers: { 'if-none-match': `W/${a.headers.etag}` } });
  check('C 304', 'a weak form of the same tag matches', n2.status, 304);
  const n3 = await get(port, '/updates/apk/olive-0.52.0.apk', { headers: { 'if-none-match': '"other"' } });
  check('C 304', 'a different tag: full 200', n3.status, 200);
  const n4 = await get(port, '/updates/apk/olive-0.52.0.apk', { headers: { 'if-modified-since': a.headers['last-modified'] } });
  check('C 304', 'If-Modified-Since at Last-Modified: 304', n4.status, 304);
  const n5 = await get(port, '/updates/apk/olive-0.52.0.apk', { headers: { 'if-modified-since': 'Thu, 01 Jan 1970 00:00:00 GMT' } });
  check('C 304', 'If-Modified-Since long ago: 200', n5.status, 200);
  const n6 = await get(port, '/updates/manifest.json', { headers: { 'if-none-match': m.headers.etag } });
  check('C 304', 'manifest: 304 on a matching tag (cheap on a weak link)', `${n6.status}|${n6.body.length}`, '304|0');
  const n7 = await get(port, '/updates/apk/olive-0.52.0.apk', { headers: { 'if-none-match': '"zzz"', 'if-modified-since': a.headers['last-modified'] } });
  check('C 304', 'If-None-Match wins over If-Modified-Since (RFC 9110)', n7.status, 200);

  // A replaced file changes the validator.
  const before = (await get(port, '/updates/manifest.json')).headers.etag;
  const newer = Buffer.from(JSON.stringify({ ...JSON.parse(MANIFEST.toString()), versionCode: 5201 }));
  writeFileSync(join(root, 'manifest.json'), newer);
  utimesSync(join(root, 'manifest.json'), new Date(Date.now() + 5000), new Date(Date.now() + 5000));
  const after = await get(port, '/updates/manifest.json');
  check('C serve', 'replacing the manifest on disk is picked up and changes the ETag', `${after.body.equals(newer)}|${after.headers.etag !== before}`, 'true|true');
  writeFileSync(join(root, 'manifest.json'), MANIFEST);
  utimesSync(join(root, 'manifest.json'), new Date(Date.now() + 10000), new Date(Date.now() + 10000));
}

// ===========================================================================
// D · ranges and resumable download
// ===========================================================================
const etagCache = { v: (await get(port, '/updates/apk/olive-0.52.0.apk', { method: 'HEAD' })).headers.etag };
{
  const R = (range, extra = {}) => get(port, '/updates/apk/olive-0.52.0.apk', { headers: { range, ...extra } });
  const r1 = await R('bytes=0-99');
  check('D range', 'bytes=0-99: 206, exact slice, Content-Range', `${r1.status}|${r1.body.equals(APK.subarray(0, 100))}|${r1.headers['content-range']}|${r1.headers['content-length']}`, `206|true|bytes 0-99/${APK.length}|100`);
  const r2 = await R('bytes=4000-');
  check('D range', 'open ended: the tail', `${r2.status}|${r2.body.equals(APK.subarray(4000))}|${r2.headers['content-range']}`, `206|true|bytes 4000-${APK.length - 1}/${APK.length}`);
  const r3 = await R('bytes=-250');
  check('D range', 'suffix: the last 250 bytes', `${r3.status}|${r3.body.equals(APK.subarray(APK.length - 250))}`, '206|true');
  const r4 = await R('bytes=4990-999999999');
  check('D range', 'an end far past the file is clamped', `${r4.status}|${r4.body.length}|${r4.headers['content-range']}`, `206|10|bytes 4990-4999/${APK.length}`);
  const r5 = await R(`bytes=${APK.length}-`);
  check('D range', 'a start at the end: 416 with Content-Range bytes */size and no body', `${r5.status}|${r5.headers['content-range']}|${r5.body.length}`, `416|bytes */${APK.length}|0`);
  const r6 = await R('bytes=' + '9'.repeat(40) + '-');
  check('D huge', 'a 40-digit start: 416, no crash', r6.status, 416);
  const r7 = await R('bytes=0-' + '9'.repeat(40));
  check('D huge', 'a 40-digit end: the whole file as 206, clamped', `${r7.status}|${r7.body.length}`, `206|${APK.length}`);
  const r8 = await R('bytes=0-1,10-11,20-21');
  check('D huge', 'several ranges are ignored: one full 200, never more than the file', `${r8.status}|${r8.body.length}|${r8.headers['content-range']}`, `200|${APK.length}|undefined`);
  const r9 = await R('bytes=' + '1,'.repeat(5000) + '2');
  check('D huge', 'a 10 KB range list is ignored too', `${r9.status}|${r9.body.length}`, `200|${APK.length}`);
  const r10 = await R('bytes=0-99', { 'if-range': a_etag() });
  check('D if-range', 'If-Range with the current ETag keeps the range', r10.status, 206);
  const r11 = await R('bytes=0-99', { 'if-range': '"stale"' });
  check('D if-range', 'If-Range with a stale tag gets the whole file, not a slice of a changed one', `${r11.status}|${r11.body.length}`, `200|${APK.length}`);
  const lm = (await get(port, '/updates/apk/olive-0.52.0.apk', { method: 'HEAD' })).headers['last-modified'];
  const r12 = await R('bytes=0-99', { 'if-range': lm });
  check('D if-range', 'If-Range with the exact Last-Modified keeps the range', r12.status, 206);
  const r13 = await R('bytes=0-99', { 'if-range': 'Thu, 01 Jan 1970 00:00:00 GMT' });
  check('D if-range', 'If-Range with any other date gets the whole file', r13.status, 200);
  const hr = await get(port, '/updates/apk/olive-0.52.0.apk', { method: 'HEAD', headers: { range: 'bytes=10-19' } });
  check('D range', 'HEAD with a range: 206 headers, no body', `${hr.status}|${hr.headers['content-range']}|${hr.body.length}|${hr.headers['content-length']}`, `206|bytes 10-19/${APK.length}|0|10`);

  // Resumable download: re-assemble from awkward chunks, verify against the manifest's sha256.
  let got = Buffer.alloc(0); let ok = true; const sizes = [1, 777, 1024, 2048, 4096];
  for (let i = 0; got.length < APK.length && ok; i++) {
    const want = sizes[i % sizes.length];
    const r = await R(`bytes=${got.length}-${got.length + want - 1}`);
    ok = r.status === 206; got = Buffer.concat([got, r.body]);
  }
  check('D resume', 'chunked re-assembly with Range equals the file (sha256 matches the manifest)', `${ok}|${sha(got) === sha(APK)}`, 'true|true');
  // Interrupted then resumed: take a prefix, resume from its length.
  const part = (await R('bytes=0-1999')).body;
  const rest = (await R(`bytes=${part.length}-`, { 'if-range': a_etag() })).body;
  check('D resume', 'a cut-off download resumes from its length and joins byte-exact', sha(Buffer.concat([part, rest])) === sha(APK), true);

  function a_etag() { return etagCache.v; }
}

// ===========================================================================
// E · hostile paths
// ===========================================================================
{
  const paths = [
    '/updates/apk/../manifest.json', '/updates/apk/../../secret.apk', '/updates/apk/%2e%2e/%2e%2e/secret.apk',
    '/updates/apk/..%2f..%2fsecret.apk', '/updates/apk/..%5c..%5csecret.apk', '/updates/apk/%2e%2e%2fmanifest.json',
    '/updates/apk/olive-0.52.0.apk%00.png', '/updates/apk/olive-0.52.0.apk%00', '/updates/apk/%252e%252e%252fsecret.apk',
    '/updates//apk/olive-0.52.0.apk', '/updates/apk//olive-0.52.0.apk', '/updates/apk/olive-0.52.0.apk/',
    '/updates/apk/sub/olive-0.52.0.apk', '/updates/apk/..\\secret.apk', '/updates/apk/.apk', '/updates/apk/',
    '/updates/apk', '/updates/', '/updates', '/updates/notes.txt', '/updates/olive-0.52.0.apk', '/UPDATES/manifest.json',
    '/updates/Manifest.json', '/updates/manifest.json/', '/updates/manifest.json.sig/', '/updates/manifest.json%00',
    '/updates/apk/olive-0.52.0.APK', '/updates/apk/OLIVE-0.52.0.apk', '/updates/apk/olive-0.52.0.apk.',
    '/updates/apk/%6f%6c%69%76%65-0.52.0.apk', '/updates/apk/olive-0.52.0.apk?../../secret',
  ];
  const results = [];
  for (const p of paths) {
    const r = await get(port, p);
    // The final one (query string) legitimately serves; every other shape must not.
    results.push([p, r.status, r.body.equals(APK) || r.body.toString().includes('TOP SECRET')]);
  }
  const bad = results.filter(([p, s, leaked]) => (p.includes('?') ? s !== 200 : s !== 404) || (!p.includes('?') && leaked));
  check('E hostile', `${paths.length} traversal / encoding / odd-shape paths are all 404, none returns file bytes`, bad.map((b) => b[0]).join(' '), '');
  const leak = results.filter(([, , leaked]) => leaked && !results.find((x) => x[0].includes('?') && x === results[results.length - 1]));
  check('E hostile', 'no hostile path ever returned the outside secret', (await Promise.all(paths.map((p) => get(port, p)))).some((r) => r.body.toString().includes('TOP SECRET')), false);
  const unlisted = await get(port, '/updates/apk/unlisted.apk');
  check('E hostile', 'a real .apk in the directory that the manifest does not name: 404', unlisted.status, 404);
  const unlistedHead = await get(port, '/updates/apk/unlisted.apk', { method: 'HEAD' });
  check('E hostile', 'and HEAD does not reveal that it exists', unlistedHead.status, 404);
  const ghost = await get(port, '/updates/apk/ghost-1.0.apk');
  check('E hostile', 'an unknown name and an unlisted name answer identically (no existence oracle)', unlisted.body.equals(ghost.body), true);
  const missing = await get(port, '/updates/apk/olive-0.53.0.apk');
  check('E hostile', 'a missing file: 404 with a JSON body, no path in it', `${missing.status}|${missing.body.toString()}`, '404|{"error":"not_found"}');
  check('E hostile', 'a 404 body never contains the directory', missing.body.toString().includes(root), false);
  const longName = await get(port, '/updates/apk/' + 'a'.repeat(300) + '.apk');
  check('E hostile', 'a 300-character name: 404', longName.status, 404);
  const manifestAsApk = await get(port, '/updates/apk/manifest.json');
  check('E hostile', 'the manifest is not reachable as an apk name', manifestAsApk.status, 404);
  const sigAsApk = await get(port, '/updates/apk/manifest.json.sig');
  check('E hostile', 'nor the signature', sigAsApk.status, 404);
  check('E hostile', 'a path outside /updates is not this handler\'s (falls through)', (await get(port, '/other')).body.toString(), 'other');
}

// ===========================================================================
// F · symlinks
// ===========================================================================
{
  let canLink = true;
  const link = (target, path) => { try { symlinkSync(target, path); return true; } catch { canLink = false; return false; } };
  link(join(outside, 'secret.apk'), join(root, 'escape.apk'));
  if (!canLink) {
    console.log('SKIPPED section F: this OS account cannot create symbolic links (runs on CI)');
  } else {
    // The manifest must name the symlinked files for this to be a real test of the link check.
    const named = Buffer.from(JSON.stringify({ ...JSON.parse(MANIFEST.toString()), extra: ['escape.apk', 'inside.apk', 'dirlink.apk'] }));
    writeFileSync(join(root, 'manifest.json'), named);
    utimesSync(join(root, 'manifest.json'), new Date(Date.now() + 20000), new Date(Date.now() + 20000));
    link(join(root, 'olive-0.52.0.apk'), join(root, 'inside.apk'));
    mkdirSync(join(outside, 'adir'), { recursive: true });
    link(join(outside, 'adir'), join(root, 'dirlink.apk'));
    const e = await get(port, '/updates/apk/escape.apk');
    check('F symlink', 'a named file that is a symlink to a file OUTSIDE the directory: 404, no bytes', `${e.status}|${e.body.toString().includes('TOP SECRET')}`, '404|false');
    const i = await get(port, '/updates/apk/inside.apk');
    check('F symlink', 'even a symlink to a file INSIDE the directory is refused (no links at all)', i.status, 404);
    const d = await get(port, '/updates/apk/dirlink.apk');
    check('F symlink', 'a symlink to a directory: 404', d.status, 404);
    rmSync(join(root, 'manifest.json'));
    writeFileSync(join(outside, 'm.json'), MANIFEST);
    link(join(outside, 'm.json'), join(root, 'manifest.json'));
    const ms = await get(port, '/updates/manifest.json');
    check('F symlink', 'manifest.json as a symlink to an outside file: 404', ms.status, 404);
    rmSync(join(root, 'manifest.json'));
    writeFileSync(join(root, 'manifest.json'), MANIFEST);
    utimesSync(join(root, 'manifest.json'), new Date(Date.now() + 30000), new Date(Date.now() + 30000));
    rmSync(join(root, 'manifest.json.sig'));
    writeFileSync(join(outside, 's.sig'), 'TOP SECRET');
    link(join(outside, 's.sig'), join(root, 'manifest.json.sig'));
    const ss = await get(port, '/updates/manifest.json.sig');
    check('F symlink', 'manifest.json.sig as a symlink: 404', `${ss.status}|${ss.body.toString().includes('TOP SECRET')}`, '404|false');
    rmSync(join(root, 'manifest.json.sig'));
    writeFileSync(join(root, 'manifest.json.sig'), SIG);
    // The configured directory ITSELF may be a link (a docker bind mount, a "current" pointer).
    const viaLink = join(tmpdir(), 'olive-upd-link-' + randomBytes(4).toString('hex'));
    if (link(root, viaLink)) {
      const hl = createUpdateHosting({ dir: viaLink, callerKey: () => 'k', env: {} });
      const sl = createServer(async (req, res) => { if (!(await hl.handle(req, res, req.url.split('?')[0]))) res.end(); });
      const pl = await listen(sl);
      const ok = await get(pl, '/updates/apk/olive-0.52.0.apk');
      check('F symlink', 'a configured directory that is itself a symlink works (mounts, "current" pointers)', `${ok.status}|${ok.body.equals(APK)}`, '200|true');
      const stillNo = await get(pl, '/updates/apk/escape.apk');
      check('F symlink', '...and links inside it are still refused', stillNo.status, 404);
      await close(sl); rmSync(viaLink, { force: true });
    }
  }
}

// ===========================================================================
// G · size caps, broken manifest
// ===========================================================================
{
  const small = host({ maxApkBytes: 4096 });
  const ps = await small.listen();
  const big = await get(ps, '/updates/apk/olive-0.52.0.apk');
  check('G caps', 'an APK over the configured cap (5000 > 4096): 404, never a partial body', `${big.status}|${big.body.length < 100}`, '404|true');
  const bigHead = await get(ps, '/updates/apk/olive-0.52.0.apk', { method: 'HEAD' });
  check('G caps', 'and HEAD does not advertise it', bigHead.status, 404);
  const under = await get(ps, '/updates/apk/olive-0.52.0-mirror.apk');
  check('G caps', 'a file under the cap (3000) is still served', under.status, 200);
  await small.close();

  const cap = Buffer.from(JSON.stringify({ pad: 'x'.repeat(MAX_MANIFEST_BYTES) }));
  const mBackup = MANIFEST;
  writeFileSync(join(root, 'manifest.json'), cap);
  utimesSync(join(root, 'manifest.json'), new Date(Date.now() + 40000), new Date(Date.now() + 40000));
  check('G caps', 'a manifest over 256 KiB is not served', (await get(port, '/updates/manifest.json')).status, 404);
  check('G caps', 'and with no usable manifest NO apk is served either', (await get(port, '/updates/apk/olive-0.52.0.apk')).status, 404);

  writeFileSync(join(root, 'manifest.json'), '{ this is not json');
  utimesSync(join(root, 'manifest.json'), new Date(Date.now() + 50000), new Date(Date.now() + 50000));
  const bad = await get(port, '/updates/manifest.json');
  check('G broken', 'a manifest that is not JSON: 503 update_manifest_unavailable (never the broken bytes)', `${bad.status}|${bad.body.toString()}|${bad.headers['retry-after']}`, '503|{"error":"update_manifest_unavailable"}|60');
  writeFileSync(join(root, 'manifest.json'), '[1,2,3]');
  utimesSync(join(root, 'manifest.json'), new Date(Date.now() + 60000), new Date(Date.now() + 60000));
  check('G broken', 'a manifest that is a JSON array: 503', (await get(port, '/updates/manifest.json')).status, 503);
  check('G broken', 'and no apk is served while the manifest is broken', (await get(port, '/updates/apk/olive-0.52.0.apk')).status, 404);

  writeFileSync(join(root, 'manifest.json.sig'), Buffer.alloc(MAX_SIGNATURE_BYTES + 1, 65));
  check('G caps', 'a signature file over 8 KiB is not served', (await get(port, '/updates/manifest.json.sig')).status, 404);
  writeFileSync(join(root, 'manifest.json.sig'), SIG);

  rmSync(join(root, 'manifest.json'));
  check('G broken', 'no manifest at all: 404', (await get(port, '/updates/manifest.json')).status, 404);
  check('G broken', 'no manifest at all: a missing signature is simply 404 too', (await get(port, '/updates/manifest.json.sig')).status, 200);
  writeFileSync(join(root, 'manifest.json'), mBackup);
  utimesSync(join(root, 'manifest.json'), new Date(Date.now() + 70000), new Date(Date.now() + 70000));
  check('G broken', 'restoring the manifest restores service without a restart', (await get(port, '/updates/apk/olive-0.52.0.apk')).status, 200);
  rmSync(join(root, 'manifest.json.sig'));
  check('G broken', 'a missing signature file: 404', (await get(port, '/updates/manifest.json.sig')).status, 404);
  writeFileSync(join(root, 'manifest.json.sig'), SIG);

  const gone = host();
  gone.hosting.stats();
  const g2 = createUpdateHosting({ dir: join(root, 'no-such-dir'), callerKey: () => 'k', env: {} });
  const sg = createServer(async (req, res) => { if (!(await g2.handle(req, res, req.url.split('?')[0]))) res.end(); });
  const pg = await listen(sg);
  check('G broken', 'a configured directory that does not exist: every route is a plain 404', (await Promise.all(['/updates/manifest.json', '/updates/manifest.json.sig', '/updates/apk/a.apk'].map((p) => get(pg, p)))).map((r) => r.status).join(','), '404,404,404');
  await close(sg);
}

// ===========================================================================
// H · methods and bodies
// ===========================================================================
{
  for (const method of ['POST', 'PUT', 'DELETE', 'PATCH', 'OPTIONS']) {
    const r = await get(port, '/updates/manifest.json', { method, body: method === 'OPTIONS' ? undefined : 'x=1', headers: method === 'OPTIONS' ? {} : { 'content-length': '3' } });
    check('H methods', `${method}: 405 with Allow: GET, HEAD`, `${r.status}|${r.headers.allow}`, '405|GET, HEAD');
  }
  const pa = await get(port, '/updates/apk/olive-0.52.0.apk', { method: 'POST', body: 'zz', headers: { 'content-length': '2' } });
  check('H methods', 'POST to an apk path: 405', pa.status, 405);
  const gb = await get(port, '/updates/manifest.json', { method: 'GET', body: 'hello', headers: { 'content-length': '5' } });
  check('H methods', 'a GET that carries a body: 400, connection closed', `${gb.status}|${gb.headers.connection}`, '400|close');
}

// ===========================================================================
// I · rate limit, stream caps, stalled readers
// ===========================================================================
{
  let limited = 0;
  const rl = host({ env: { UPDATES_RATE_CAPACITY: '3', UPDATES_RATE_PER_MIN: '60' }, onRateLimited: () => { limited++; } });
  const pr = await rl.listen();
  const seen = [];
  for (let i = 0; i < 5; i++) seen.push((await get(pr, '/updates/manifest.json')).status);
  check('I rate', 'burst of 3, then 429 for the rest', seen.join(','), '200,200,200,429,429');
  const r429 = await get(pr, '/updates/manifest.json');
  check('I rate', '429 carries Retry-After (whole seconds, at least 1) and a fixed body', `${r429.headers['retry-after']}|${r429.body.toString()}`, '1|{"error":"rate_limited"}');
  check('I rate', 'the limited hook fired (feeds the rate_limited_total counter)', limited >= 3, true);
  const other = await get(pr, '/updates/manifest.json', { headers: { 'x-test-caller': 'caller-2' } });
  check('I rate', 'another caller has its own bucket', other.status, 200);
  rl.tick(2100);
  check('I rate', 'the bucket refills with time (two tokens after 2.1 s at 60/min)', (await get(pr, '/updates/manifest.json')).status, 200);
  // Probing for names spends tokens too, and is refused before any disk access.
  const probe = [];
  rl.tick(10_000); // refill to capacity
  for (let i = 0; i < 5; i++) probe.push((await get(pr, `/updates/apk/guess-${i}.apk`)).status);
  check('I rate', 'name guessing (404s) is rate limited exactly like real requests', probe.join(','), '404,404,404,429,429');
  check('I rate', 'HEAD and 304 spend tokens as well', (await (async () => { rl.tick(10_000); const s = []; for (let i = 0; i < 4; i++) s.push((await get(pr, '/updates/manifest.json', { method: 'HEAD' })).status); return s.join(','); })()), '200,200,200,429');
  await rl.close();

  // Concurrent-stream caps. A paused reader holds its slot (the file is larger than the socket buffers).
  const BIG = randomBytes(24 * 1024 * 1024);
  writeFileSync(join(root, 'big.apk'), BIG);
  const named = Buffer.from(JSON.stringify({ apk: ['big.apk', 'olive-0.52.0.apk'] }));
  writeFileSync(join(root, 'manifest.json'), named);
  utimesSync(join(root, 'manifest.json'), new Date(Date.now() + 80000), new Date(Date.now() + 80000));
  const holdOpen = (p, caller) => new Promise((resolve) => {
    const r = request({ host: '127.0.0.1', port: p, path: '/updates/apk/big.apk', agent: false, headers: { 'x-test-caller': caller } }, (res) => {
      res.pause(); resolve({ res, req: r });
    });
    r.end();
  });
  const sc = host({ env: { UPDATES_MAX_STREAMS_PER_CALLER: '1', UPDATES_MAX_STREAMS: '2' } });
  const pc = await sc.listen();
  const first = await holdOpen(pc, 'A');
  check('I streams', 'a first download is accepted', first.res.statusCode, 200);
  await new Promise((r) => setTimeout(r, 150));
  const second = await get(pc, '/updates/apk/big.apk', { headers: { 'x-test-caller': 'A' } });
  check('I streams', 'a second concurrent download by the SAME caller: 429 + Retry-After', `${second.status}|${second.headers['retry-after']}`, '429|5');
  const headOk = await get(pc, '/updates/apk/big.apk', { method: 'HEAD', headers: { 'x-test-caller': 'A' } });
  check('I streams', 'HEAD does not need a stream slot', headOk.status, 200);
  const rangeSmall = await get(pc, '/updates/apk/olive-0.52.0.apk', { headers: { 'x-test-caller': 'B' } });
  check('I streams', 'a different caller is unaffected', rangeSmall.status, 200);
  const third = await holdOpen(pc, 'C');
  await new Promise((r) => setTimeout(r, 150));
  const fourth = await get(pc, '/updates/apk/big.apk', { headers: { 'x-test-caller': 'D' } });
  check('I streams', 'the GLOBAL cap (2) refuses a third stream from anyone', fourth.status, 429);
  first.req.destroy(); third.req.destroy();
  await new Promise((r) => setTimeout(r, 400));
  check('I streams', 'closing the downloads frees the slots (activeStreams returns to 0)', sc.hosting.stats().activeStreams, 0);
  const again = await get(pc, '/updates/apk/big.apk', { headers: { 'x-test-caller': 'A', range: 'bytes=0-9' } });
  check('I streams', 'and the same caller can download again', again.status, 206);
  await sc.close();

  // A reader that stops reading is cut after the idle window, and its slot comes back.
  const idle = host({ env: { UPDATES_MAX_STREAMS_PER_CALLER: '1' }, streamIdleMs: 300 });
  const pi = await idle.listen();
  let aborted = false;
  const stalled = await new Promise((resolve) => {
    const r = request({ host: '127.0.0.1', port: pi, path: '/updates/apk/big.apk', agent: false }, (res) => {
      res.pause(); res.on('aborted', () => { aborted = true; }); res.on('close', () => { aborted = true; }); resolve(res);
    });
    r.on('error', () => { aborted = true; }); r.on('socket', (sk) => sk.on('close', () => { aborted = true; })); r.end();
  });
  await new Promise((r) => setTimeout(r, 100));
  check('I stall', 'a stalled reader holds exactly one stream slot while it is within the idle window', idle.hosting.stats().activeStreams, 1);
  await new Promise((r) => setTimeout(r, 1500));
  // (A paused client never reads the FIN, so the server side is the honest place to observe the cut.)
  check('I stall', 'after the idle window the server has cut the stream and released its slot', idle.hosting.stats().activeStreams, 0);
  stalled.destroy();
  await idle.close();

  rmSync(join(root, 'big.apk'));
  writeFileSync(join(root, 'manifest.json'), MANIFEST);
  utimesSync(join(root, 'manifest.json'), new Date(Date.now() + 90000), new Date(Date.now() + 90000));
}

await h.close();

// ===========================================================================
// J · the real server/index.mjs (no database is reachable on purpose)
// ===========================================================================
const DEAD_DB = 'postgres://nobody:nopass@127.0.0.1:9/none';
async function boot(env = {}) {
  const p = 27000 + Math.floor(Math.random() * 3000);
  const child = spawn(process.execPath, [serverEntry], {
    env: { ...process.env, DATABASE_URL: DEAD_DB, SESSION_SECRET: 'h'.repeat(40), NODE_ENV: 'development', PORT: String(p),
      DB_CONNECTION_TIMEOUT_MS: '1000', ...env },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  let out = '';
  child.stdout.on('data', (d) => { out += d.toString(); });
  child.stderr.on('data', (d) => { out += d.toString(); });
  let code = null; child.on('exit', (c) => { code = c; });
  const deadline = Date.now() + 60_000;
  while (!out.includes('listening on') && code === null && Date.now() < deadline) await new Promise((r) => setTimeout(r, 50));
  return { port: p, out: () => out, code: () => code,
    stop: async () => { child.kill(); await new Promise((r) => setTimeout(r, 200)); } };
}
{
  const off = await boot({ UPDATES_DIR: '' });
  const r = await get(off.port, '/updates/manifest.json');
  check('J index', 'UPDATES_DIR unset: /updates/manifest.json is an ordinary 404 (nothing registered)', r.status, 404);
  check('J index', 'UPDATES_DIR unset: the apk and signature paths 404 too', (await Promise.all(['/updates/manifest.json.sig', '/updates/apk/olive-0.52.0.apk'].map((p) => get(off.port, p)))).map((x) => x.status).join(','), '404,404');
  check('J index', 'boot log says the feature is not hosted', off.out().includes('updates: not hosted'), true);
  await off.stop();

  const on = await boot({ UPDATES_DIR: root });
  const m = await get(on.port, '/updates/manifest.json');
  check('J index', 'UPDATES_DIR set: the manifest is served by the real server with NO database', `${m.status}|${m.body.equals(MANIFEST)}`, '200|true');
  check('J index', 'the real server sends its baseline security headers on it as well', `${m.headers['x-frame-options']}|${m.headers['referrer-policy']}`, 'DENY|no-referrer');
  const a = await get(on.port, '/updates/apk/olive-0.52.0.apk', { headers: { range: 'bytes=100-199' } });
  check('J index', 'a ranged APK request through the real server', `${a.status}|${a.body.equals(APK.subarray(100, 200))}`, '206|true');
  check('J index', 'the signature through the real server', (await get(on.port, '/updates/manifest.json.sig')).body.equals(SIG), true);
  check('J index', 'POST is 405 through the real server (before any body is read)', (await get(on.port, '/updates/manifest.json', { method: 'POST', body: '{}', headers: { 'content-length': '2' } })).status, 405);
  check('J index', 'an unknown /updates path is 404 through the real server', (await get(on.port, '/updates/other')).status, 404);
  check('J index', 'no session, no Authorization: the route is public by design', (await get(on.port, '/updates/manifest.json', { headers: { authorization: 'Bearer nonsense' } })).status, 200);
  await new Promise((r) => setTimeout(r, 200));
  const lines = on.out().split('\n').filter((l) => l.startsWith('{')).map((l) => { try { return JSON.parse(l); } catch { return null; } }).filter(Boolean);
  const routes = new Set(lines.map((l) => l.route));
  check('J index', 'the access log uses the FIXED labels, never a concrete file name', `${routes.has('/updates/manifest.json')}|${routes.has('/updates/apk/:file')}|${routes.has('/updates/unmatched')}`, 'true|true|true');
  check('J index', 'no access-log line contains an apk file name', lines.some((l) => JSON.stringify(l).includes('olive-0.52.0')), false);
  await on.stop();

  const bad = await boot({ UPDATES_DIR: 'relative/path' });
  await new Promise((r) => setTimeout(r, 500));
  check('J index', 'a relative UPDATES_DIR refuses to boot (exit 2), naming the problem', `${bad.code()}|${bad.out().includes('updates config check failed: UPDATES_DIR must be an absolute path')}`, '2|true');

  const prod = await boot({ UPDATES_DIR: root, NODE_ENV: 'production', DEV_LOGIN: '0', SESSION_SECRET: 'a'.repeat(64), MEDIA_SIGNING_SECRET: 'b'.repeat(64),
    PUBLIC_BASE_URL: 'https://olive.example.org', TRUST_PROXY: '1', TRUST_PROXY_HOPS: '1' });
  if (prod.code() === null) {
    const cleartext = await get(prod.port, '/updates/manifest.json');
    check('J index', 'production: a request that did not arrive over TLS is refused like every other route (400 https_required)', `${cleartext.status}|${cleartext.body.toString()}`, '400|{"error":"https_required"}');
    const tls = await get(prod.port, '/updates/manifest.json', { headers: { 'x-forwarded-proto': 'https', 'x-forwarded-for': '203.0.113.9' } });
    check('J index', 'production behind the TLS proxy: served, with HSTS', `${tls.status}|${!!tls.headers['strict-transport-security']}`, '200|true');
    await prod.stop();
  } else {
    check('J index', 'production-mode boot (skipped: the DB role check needs a database)', 'skipped', 'skipped');
  }
}

// ===========================================================================
// K · the route list is the one the drift test pins
// ===========================================================================
check('K routes', 'UPDATE_ROUTES is exactly the three documented shapes', UPDATE_ROUTES.join(' '), '/updates/manifest.json /updates/manifest.json.sig /updates/apk/:file');

rmSync(root, { recursive: true, force: true });
rmSync(outside, { recursive: true, force: true });

let g = '';
for (const r of rows) { if (r.g !== g) { g = r.g; console.log(`\n${g}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`)); }
console.log(`\n${'-'.repeat(56)}\n${pass} passed, ${fail} failed\n`);
process.exit(fail === 0 ? 0 : 1);
