// OLIVE BRANCH — optional self-hosted app-update files (the server half of the
// in-app update pipeline, MASTERFILE 9.4).
//
// WHAT THIS IS. A static, read-only, PUBLIC route set so a family that runs
// its own server does not depend on a third-party host to get app updates:
//
//   GET|HEAD  /updates/manifest.json        the signed update manifest
//   GET|HEAD  /updates/manifest.json.sig    its detached signature
//   GET|HEAD  /updates/apk/<file>.apk       an APK the manifest names
//
// WHAT IT IS NOT. It is not a place that decides anything. The server never
// signs, never verifies and never edits a byte: the manifest is signed offline
// by the owner's Ed25519 key and the app checks that signature (plus sha256,
// version and signing certificate) itself. A hostile or broken server can at
// worst withhold an update; it cannot make the app install one. So these
// routes carry no per-family data, no session and no authentication, by
// design, and a request here never touches the database.
//
// OFF BY DEFAULT. UPDATES_DIR unset (or empty) means resolveUpdatesConfig()
// reports enabled:false, index.mjs never builds this handler, and /updates/*
// is an ordinary unknown path (404). Nothing is registered.
//
// THE STRICT PART (every one of these has a test in test/update_hosting.test.mjs):
//   - Only three route shapes exist, matched against the RAW path with an
//     anchored regexp. A '%' anywhere, a '..', a backslash, a NUL, a doubled
//     slash or a trailing slash simply does not match: 404, nothing decoded.
//   - An APK is served only if its file name is NAMED IN THE CURRENT MANIFEST
//     (any string value ending in .apk, last path segment) AND is a strict
//     plain name (letters, digits, dot, dash, underscore; <= 128 chars).
//     A file sitting in the directory that the manifest does not name is not
//     reachable. So is a leftover old release the owner has retired.
//   - Symlinks never escape: the entry must be a regular file by lstat, its
//     realpath must be exactly <real root>/<name> (so no link in the path, at
//     any level), it is opened with O_NOFOLLOW where the platform has it, and
//     the opened descriptor must be the same file (dev + ino) that was
//     checked. A symlink swapped in after the check is therefore refused too.
//   - Size caps: a manifest over 256 KiB, a signature over 8 KiB, an APK over
//     UPDATES_MAX_APK_MIB (default 256) is not served (404, never a partial).
//   - Ranges (resumable download): single byte range only; suffix and open
//     ended forms; an end past the file is clamped; a start past the file is
//     416 with Content-Range: bytes */size; syntactically bad or multi-range
//     requests are IGNORED (a full 200), never amplified; absurd digit
//     strings cannot overflow. If-Range with anything but the current ETag
//     (or the exact Last-Modified) gets the whole file.
//   - ETag (strong, from size + mtime) and Last-Modified, If-None-Match and
//     If-Modified-Since (304), HEAD with no body.
//   - Rate limit: every request spends a token from a per-caller bucket (the
//     daily-salted pseudonym from netid.mjs, never an address); downloads also
//     take a per-caller and a global concurrent-stream slot, and a stalled or
//     very long stream is cut. 429 + Retry-After, before any disk access.

import { createReadStream } from 'node:fs';
import { open, lstat, realpath, stat } from 'node:fs/promises';
import { constants as fsc } from 'node:fs';
import { join, sep, isAbsolute, resolve as pathResolve } from 'node:path';
import { pipeline } from 'node:stream';
import { TokenBuckets, InFlightLimiter } from './rate_limit.mjs';

export const MANIFEST_NAME = 'manifest.json';
export const SIGNATURE_NAME = 'manifest.json.sig';
export const MAX_MANIFEST_BYTES = 256 * 1024;
export const MAX_SIGNATURE_BYTES = 8 * 1024;
export const DEFAULT_MAX_APK_MIB = 256;
/** The only URL shapes this module answers. Exported so the drift test can pin them. */
export const UPDATE_ROUTES = Object.freeze([
  '/updates/manifest.json',
  '/updates/manifest.json.sig',
  '/updates/apk/:file',
]);
export const APK_CONTENT_TYPE = 'application/vnd.android.package-archive';

const APK_NAME_RE = /^[A-Za-z0-9][A-Za-z0-9._-]{0,123}\.apk$/;
const APK_PATH_RE = /^\/updates\/apk\/([A-Za-z0-9][A-Za-z0-9._-]{0,123}\.apk)$/;

function posNum(raw, fallback) {
  const n = Number(raw);
  return Number.isFinite(n) && n > 0 ? n : fallback;
}

/**
 * Reads UPDATES_DIR and friends. Pure but for one lstat of the directory.
 *   UPDATES_DIR            absolute directory holding manifest.json, its .sig and the APKs.
 *                          Unset/empty = feature off.
 *   UPDATES_MAX_APK_MIB    largest APK served (default 256).
 *   UPDATES_RATE_CAPACITY / UPDATES_RATE_PER_MIN   per-caller request bucket (60 / 60).
 *   UPDATES_MAX_STREAMS_PER_CALLER (3), UPDATES_MAX_STREAMS (16).
 * Set-but-malformed is a boot PROBLEM (like the other server configs); a
 * directory that does not exist yet is only a warning (an operator may mount
 * it after the first release).
 */
export async function resolveUpdatesConfig(env = process.env, { statFn = stat } = {}) {
  const problems = []; const warnings = [];
  const raw = (env.UPDATES_DIR ?? '').trim();
  if (!raw) return { enabled: false, dir: null, problems, warnings };
  if (raw.includes('\0') || !isAbsolute(raw)) {
    problems.push('UPDATES_DIR must be an absolute path');
    return { enabled: false, dir: null, problems, warnings };
  }
  const dir = pathResolve(raw);
  if (dir === pathResolve('/') || /^[A-Za-z]:\\?$/.test(dir)) {
    problems.push('UPDATES_DIR must not be a filesystem root');
    return { enabled: false, dir: null, problems, warnings };
  }
  const media = (env.MEDIA_STORAGE_ROOT ?? '').trim();
  if (media && isAbsolute(media)) {
    const m = pathResolve(media);
    if (m === dir || m.startsWith(dir + sep) || dir.startsWith(m + sep)) {
      problems.push('UPDATES_DIR must not be, contain or sit inside MEDIA_STORAGE_ROOT (that is private family data)');
    }
  }
  const maxMib = env.UPDATES_MAX_APK_MIB;
  if (maxMib !== undefined && maxMib !== '' && !(Number(maxMib) > 0 && Number.isFinite(Number(maxMib)))) {
    problems.push('UPDATES_MAX_APK_MIB must be a positive number');
  }
  try {
    const st = await statFn(dir);
    if (!st.isDirectory()) problems.push('UPDATES_DIR exists but is not a directory');
  } catch {
    warnings.push('UPDATES_DIR does not exist (yet): /updates/* will answer 404 until it does');
  }
  return {
    enabled: problems.length === 0, dir: problems.length ? null : dir, problems, warnings,
    maxApkBytes: Math.floor(posNum(maxMib, DEFAULT_MAX_APK_MIB) * 1024 * 1024),
  };
}

/** Last path segment of every string value ending in .apk anywhere in the manifest. */
export function apkNamesInManifest(manifest) {
  const out = new Set();
  const walk = (v, depth) => {
    if (depth > 12) return;
    if (typeof v === 'string') {
      if (v.length > 2048) return;
      const noQuery = v.split(/[?#]/)[0];
      if (!/\.apk$/i.test(noQuery)) return;
      const last = noQuery.split('/').pop();
      if (APK_NAME_RE.test(last)) out.add(last);
    } else if (Array.isArray(v)) {
      for (const x of v) walk(x, depth + 1);
    } else if (v && typeof v === 'object') {
      for (const x of Object.values(v)) walk(x, depth + 1);
    }
  };
  walk(manifest, 0);
  return out;
}

/**
 * Parses a Range header against a file of `size` bytes.
 *   { kind: 'none' }                      no usable Range: send the whole file (200)
 *   { kind: 'range', start, end }         inclusive, already clamped (206)
 *   { kind: 'unsatisfiable' }             416
 * Anything the RFC lets a server ignore (wrong unit, several ranges, bad
 * syntax) is 'none': a full response is never larger than what an honest
 * client asked for, and a multi-range request cannot be used to make the
 * server send a file many times over.
 */
export function parseRange(header, size) {
  if (typeof header !== 'string') return { kind: 'none' };
  const m = /^\s*bytes\s*=\s*(\d*)\s*-\s*(\d*)\s*$/i.exec(header);
  if (!m) return { kind: 'none' };
  const [, a, b] = m;
  if (a === '' && b === '') return { kind: 'none' };
  const num = (s) => (s.length > 15 ? Number.MAX_SAFE_INTEGER : Number(s));
  if (a === '') { // suffix: the last n bytes
    const n = num(b);
    if (n === 0) return { kind: 'unsatisfiable' };
    if (size === 0) return { kind: 'unsatisfiable' };
    return { kind: 'range', start: Math.max(0, size - n), end: size - 1 };
  }
  const start = num(a);
  let end = b === '' ? size - 1 : num(b);
  if (b !== '' && end < start) return { kind: 'none' }; // invalid per RFC 9110: ignore
  if (start >= size) return { kind: 'unsatisfiable' };
  if (end >= size) end = size - 1;
  return { kind: 'range', start, end };
}

const etagOf = (st) => `"${st.size.toString(16)}-${Math.floor(st.mtimeMs).toString(16)}"`;
const httpDate = (ms) => new Date(Math.floor(ms / 1000) * 1000).toUTCString();

function etagMatches(headerValue, etag) {
  if (typeof headerValue !== 'string') return false;
  if (headerValue.trim() === '*') return true;
  return headerValue.split(',').some((t) => t.trim().replace(/^W\//, '') === etag);
}

/**
 * @param {object} o
 * @param {string} o.dir  absolute directory
 * @param {number} [o.maxApkBytes]
 * @param {(req)=>string} o.callerKey  pseudonymous caller key (netid.anonKey)
 * @param {object} [o.env]
 * @param {()=>number} [o.now]
 * @returns {{ handle(req,res,pathname):Promise<boolean>, stats():object, buckets }}
 */
export function createUpdateHosting({ dir, maxApkBytes = DEFAULT_MAX_APK_MIB * 1024 * 1024, callerKey,
  env = process.env, now = () => Date.now(), onRateLimited = () => {}, streamIdleMs = 60_000,
  streamMaxMs = 30 * 60_000 }) {
  const cap = posNum(env.UPDATES_RATE_CAPACITY, 60);
  const perMin = posNum(env.UPDATES_RATE_PER_MIN, 60);
  const buckets = new TokenBuckets({ capacity: cap, refillPerSec: perMin / 60, now });
  const perCaller = new InFlightLimiter({ max: posNum(env.UPDATES_MAX_STREAMS_PER_CALLER, 3) });
  const globalMax = posNum(env.UPDATES_MAX_STREAMS, 16);
  let globalActive = 0;
  let manifestCache = null; // { key, body, etag, lastModified, names }

  const json = (res, status, body, extra = {}) => {
    const buf = Buffer.from(JSON.stringify(body));
    res.writeHead(status, { 'content-type': 'application/json; charset=utf-8',
      'content-length': String(buf.length), 'cache-control': 'no-store',
      'x-content-type-options': 'nosniff', ...extra });
    res.end(buf);
  };
  const notFound = (res) => json(res, 404, { error: 'not_found' });

  /**
   * lstat + realpath + root check. Returns { path, st } for a plain regular
   * file that really lives directly inside the (real) root, else null.
   */
  async function resolveFile(name, maxBytes) {
    let realRoot;
    try { realRoot = await realpath(dir); } catch { return null; }
    const path = join(realRoot, name);
    let st;
    try { st = await lstat(path); } catch { return null; }
    if (!st.isFile() || st.isSymbolicLink()) return null;
    if (st.size > maxBytes) return null;
    try { if ((await realpath(path)) !== path) return null; } catch { return null; }
    return { path, st };
  }

  /** Opens the already-checked file and proves the descriptor is the same file. */
  async function openChecked(path, st, maxBytes) {
    let fh;
    try { fh = await open(path, fsc.O_RDONLY | (fsc.O_NOFOLLOW ?? 0)); } catch { return null; }
    try {
      const fst = await fh.stat();
      if (!fst.isFile() || fst.dev !== st.dev || fst.ino !== st.ino || fst.size > maxBytes) {
        await fh.close(); return null;
      }
      return { fh, st: fst };
    } catch { try { await fh.close(); } catch { /* */ } return null; }
  }

  async function loadManifest() {
    const f = await resolveFile(MANIFEST_NAME, MAX_MANIFEST_BYTES);
    if (!f) return { state: 'absent' };
    const key = `${f.st.size}:${f.st.mtimeMs}:${f.st.ino}`;
    if (manifestCache && manifestCache.key === key) return { state: 'ok', ...manifestCache };
    const opened = await openChecked(f.path, f.st, MAX_MANIFEST_BYTES);
    if (!opened) return { state: 'absent' };
    let body;
    try { body = await opened.fh.readFile(); } finally { await opened.fh.close().catch(() => {}); }
    let parsed;
    try { parsed = JSON.parse(body.toString('utf8')); } catch { return { state: 'invalid' }; }
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) return { state: 'invalid' };
    manifestCache = { key, body, etag: etagOf(f.st), lastModified: httpDate(f.st.mtimeMs),
      mtimeMs: Math.floor(f.st.mtimeMs / 1000) * 1000, names: apkNamesInManifest(parsed) };
    return { state: 'ok', ...manifestCache };
  }

  /** 304 / full / range decision shared by every file. Returns null when handled. */
  function conditional(req, res, { etag, lastModified, mtimeMs }, baseHeaders) {
    const inm = req.headers['if-none-match'];
    if (inm !== undefined) {
      if (etagMatches(inm, etag)) { res.writeHead(304, { ...baseHeaders, etag, 'last-modified': lastModified }); res.end(); return true; }
    } else {
      const ims = Date.parse(req.headers['if-modified-since'] ?? '');
      if (Number.isFinite(ims) && mtimeMs <= ims) { res.writeHead(304, { ...baseHeaders, etag, 'last-modified': lastModified }); res.end(); return true; }
    }
    return false;
  }

  async function serveSmall(req, res, bytes, meta, contentType, baseHeaders) {
    const headers = { ...baseHeaders, 'content-type': contentType, etag: meta.etag,
      'last-modified': meta.lastModified, 'accept-ranges': 'none' };
    if (conditional(req, res, meta, baseHeaders)) return;
    res.writeHead(200, { ...headers, 'content-length': String(bytes.length) });
    res.end(req.method === 'HEAD' ? undefined : bytes);
  }

  async function serveSignature(req, res) {
    const f = await resolveFile(SIGNATURE_NAME, MAX_SIGNATURE_BYTES);
    if (!f) return notFound(res);
    const opened = await openChecked(f.path, f.st, MAX_SIGNATURE_BYTES);
    if (!opened) return notFound(res);
    let body;
    try { body = await opened.fh.readFile(); } finally { await opened.fh.close().catch(() => {}); }
    return serveSmall(req, res, body,
      { etag: etagOf(opened.st), lastModified: httpDate(opened.st.mtimeMs),
        mtimeMs: Math.floor(opened.st.mtimeMs / 1000) * 1000 },
      'application/octet-stream', { 'cache-control': 'public, no-cache', 'x-content-type-options': 'nosniff' });
  }

  async function serveApk(req, res, name, callerId) {
    const m = await loadManifest();
    if (m.state !== 'ok' || !m.names.has(name)) return notFound(res);
    const f = await resolveFile(name, maxApkBytes);
    if (!f) return notFound(res);
    const opened = await openChecked(f.path, f.st, maxApkBytes);
    if (!opened) return notFound(res);
    const { fh, st } = opened;
    const etag = etagOf(st);
    const mtimeMs = Math.floor(st.mtimeMs / 1000) * 1000;
    const lastModified = httpDate(st.mtimeMs);
    const base = { 'cache-control': 'public, max-age=300', 'x-content-type-options': 'nosniff' };
    let release = null; let globalHeld = false;
    const cleanup = () => {
      if (release) { release(); release = null; }
      if (globalHeld) { globalActive -= 1; globalHeld = false; }
      fh.close().catch(() => {});
    };
    try {
      if (conditional(req, res, { etag, lastModified, mtimeMs }, base)) return cleanup();
      // Range, honouring If-Range (anything but our current validator -> whole file).
      let range = parseRange(req.headers.range, st.size);
      const ifRange = req.headers['if-range'];
      if (range.kind !== 'none' && ifRange !== undefined) {
        const ok = ifRange.trim() === etag || ifRange.trim() === lastModified;
        if (!ok) range = { kind: 'none' };
      }
      const common = { ...base, 'content-type': APK_CONTENT_TYPE, etag, 'last-modified': lastModified,
        'accept-ranges': 'bytes', 'content-disposition': `attachment; filename="${name}"` };
      if (range.kind === 'unsatisfiable') {
        res.writeHead(416, { ...common, 'content-range': `bytes */${st.size}`, 'content-length': '0' });
        res.end(); return cleanup();
      }
      const start = range.kind === 'range' ? range.start : 0;
      const end = range.kind === 'range' ? range.end : st.size - 1;
      const length = st.size === 0 ? 0 : end - start + 1;
      const headers = { ...common, 'content-length': String(length) };
      if (range.kind === 'range') headers['content-range'] = `bytes ${start}-${end}/${st.size}`;
      const status = range.kind === 'range' ? 206 : 200;
      if (req.method === 'HEAD' || length === 0) {
        res.writeHead(status, headers); res.end(); return cleanup();
      }
      // A body is about to be streamed: take the concurrency slots first.
      if (globalActive >= globalMax) { onRateLimited(); cleanup();
        return json(res, 429, { error: 'rate_limited' }, { 'retry-after': '5' }); }
      release = perCaller.acquire(callerId);
      if (!release) { onRateLimited(); cleanup();
        return json(res, 429, { error: 'rate_limited' }, { 'retry-after': '5' }); }
      globalActive += 1; globalHeld = true;
      res.writeHead(status, headers);
      const stream = createReadStream(null, { fd: fh.fd, start, end, autoClose: false, emitClose: true });
      let idle = setTimeout(() => res.destroy(), streamIdleMs); idle.unref?.();
      const total = setTimeout(() => res.destroy(), streamMaxMs); total.unref?.();
      stream.on('data', () => { clearTimeout(idle); idle = setTimeout(() => res.destroy(), streamIdleMs); idle.unref?.(); });
      pipeline(stream, res, () => { clearTimeout(idle); clearTimeout(total); cleanup(); });
    } catch (e) {
      cleanup();
      if (!res.headersSent) notFound(res); else res.destroy();
    }
  }

  /**
   * Handles a request iff its path is /updates or under /updates/. Returns true
   * when it did (the caller must not touch `res` again).
   */
  async function handle(req, res, pathname) {
    if (pathname !== '/updates' && !pathname.startsWith('/updates/')) return false;
    const method = req.method ?? 'GET';
    if (method !== 'GET' && method !== 'HEAD') {
      req.resume();
      json(res, 405, { error: 'method_not_allowed' }, { allow: 'GET, HEAD', connection: 'close' });
      return true;
    }
    // A GET/HEAD that carries a body is not a request this route answers.
    if ((req.headers['content-length'] && req.headers['content-length'] !== '0') || req.headers['transfer-encoding']) {
      req.resume();
      json(res, 400, { error: 'bad_request' }, { connection: 'close' });
      return true;
    }
    const callerId = callerKey(req);
    const t = buckets.take(callerId);
    if (!t.ok) {
      onRateLimited();
      json(res, 429, { error: 'rate_limited' }, { 'retry-after': String(t.retryAfterSec) });
      return true;
    }
    try {
      if (pathname === '/updates/manifest.json') {
        const m = await loadManifest();
        if (m.state === 'absent') notFound(res);
        else if (m.state === 'invalid') json(res, 503, { error: 'update_manifest_unavailable' }, { 'retry-after': '60' });
        else await serveSmall(req, res, m.body, m, 'application/json; charset=utf-8',
          { 'cache-control': 'public, no-cache', 'x-content-type-options': 'nosniff' });
      } else if (pathname === '/updates/manifest.json.sig') {
        await serveSignature(req, res);
      } else {
        const am = APK_PATH_RE.exec(pathname);
        if (am) await serveApk(req, res, am[1], callerId); else notFound(res);
      }
    } catch {
      if (!res.headersSent) json(res, 500, { error: 'internal' }); else res.destroy();
    }
    return true;
  }

  return { handle, buckets, stats: () => ({ activeStreams: globalActive, bucketKeys: buckets.size }) };
}
