/**
 * OLIVE BRANCH - the signed update manifest: strict parser, canonical form, schema validator, Ed25519 signature and the
 * decision the app makes about a downloaded manifest. Pure functions of text and bytes: no network, no git, no Flutter.
 *
 * The format of record is docs/UPDATE-MANIFEST.md; docs/update-manifest.schema.json is the same rules as JSON Schema and
 * tools/test/update_manifest.test.mjs keeps the two from drifting. The Dart client (client/lib/update_manifest.dart) makes
 * the same checks; tools/update/test-vectors.json is the shared truth both must reproduce byte for byte.
 *
 * THE RULE THIS FILE EXISTS TO KEEP: nothing in a manifest is believed until the signature over its CANONICAL form verifies
 * under a PUBLIC key built into the app, and nothing about the APK is believed until its size, every chunk hash and its
 * SHA-256 match that signed manifest. The private key never touches this file: only sign-update-manifest.mjs and
 * gen-update-key.mjs ever see it, and they run on the owner's own machine.
 *
 * DIRECTION OF STRICTNESS. Where this file and the app differ, this file is the stricter one. A publisher check that is
 * stricter than the app can only turn a release away; a check that is looser than the app could let a release through that
 * every phone then refuses. The one exception is explicit and named: `strict:false` in verifyDocument, which exists only so
 * the verifier can say "the app would accept this" about a document that carries a member this version does not know.
 */
import { createHash, createPublicKey, sign as edSign, verify as edVerify } from 'node:crypto';

export const SCHEMA_VERSION = 1;
export const APP_ID = 'com.olivebranch.olive_client';
/** Domain separation: a signature over a manifest can never be mistaken for a signature over anything else. */
export const SIGN_DOMAIN = 'olive-update-manifest-v1\n';
export const SIG_ALG = 'ed25519';
export const ABIS = Object.freeze(['arm64-v8a', 'armeabi-v7a', 'x86_64', 'universal']);

/** Hard caps, identical to the constants in client/lib/update_manifest.dart. Refused before anything is hashed or downloaded. */
export const LIMITS = Object.freeze({
  manifestBytes: 256 * 1024,
  apkBytes: 500 * 1024 * 1024,
  chunkMin: 16 * 1024,
  chunkMax: 8 * 1024 * 1024,
  chunksMax: 32768,
  apks: 4,
  urls: 4,
  notes: 12,
  noteChars: 300,
  urlChars: 2000,
  headlineChars: 100,
  textChars: 100,
  versionCodeMax: 2147483647,
  safeInt: Number.MAX_SAFE_INTEGER,
  validityDays: 400,
  jsonDepth: 8,
  /** A published manifest dated further ahead than this is "from the future" (a wrong clock or a forgery). */
  clockSkewMs: 24 * 3600 * 1000,
  /** Publisher policy: how far above issuedAt (in epoch seconds) a sequence may be. */
  sequenceSlackSeconds: 86400,
  /** Publisher policy: the signing tool refuses an issuedAt further ahead of the real clock than this. */
  signSkewMs: 10 * 60 * 1000,
  zipEntries: 20000,
  zipUncompressedBytes: 2 * 1024 * 1024 * 1024,
  zipRatio: 1000,
  /** Default chunk size the build script picks, and the most chunk hashes it will write. */
  chunkDefault: 1024 * 1024,
  chunksPreferred: 2048,
});

/** Why something was refused. Same names as UpdateRefusalCode in the Dart client so a log line means one thing in both. */
export const CODES = Object.freeze([
  'notJson', 'tooLarge', 'badShape', 'noKeyConfigured', 'unknownKey', 'badSignature', 'wrongApp', 'wrongChannel', 'expired',
  'notYetValid', 'replayed', 'rollback', 'noApkForDevice', 'badUrl', 'certMismatch', 'apkMismatch', 'sizeTooLarge', 'hashMismatch',
  'truncated', 'tooMuchData', 'badRedirect', 'noSpace', 'lowBattery', 'needsWifi', 'offline', 'cancelled', 'httpError',
]);

export class Refusal extends Error {
  constructor(code, detail = '') {
    super(`${code}${detail ? `: ${detail}` : ''}`);
    this.code = code;
    this.detail = detail;
  }
}

// ------------------------------------------------------------------------------------------------ strict JSON ----

/**
 * A strict JSON parser. JSON.parse is too forgiving for something that is signed: it keeps the LAST of two equal keys,
 * accepts lone surrogates and floats. This one refuses duplicate keys, a byte-order mark, trailing bytes, non-integer numbers,
 * numbers beyond 2^53-1, lone surrogates and nesting deeper than LIMITS.jsonDepth. Objects come back with a null prototype.
 * @returns {{ok:true, value:any}|{ok:false, error:string}}
 */
export function parseStrictJson(text) {
  if (typeof text !== 'string') return { ok: false, error: 'not text' };
  if (text.charCodeAt(0) === 0xfeff) return { ok: false, error: 'byte-order mark' };
  let i = 0;
  const fail = (m) => { const e = new Error(m); e.strict = true; throw e; };
  const ws = () => { while (i < text.length && (text[i] === ' ' || text[i] === '\t' || text[i] === '\n' || text[i] === '\r')) i++; };
  const value = (depth) => {
    if (depth > LIMITS.jsonDepth) fail('nested too deeply');
    ws();
    const c = text[i];
    if (c === '{') {
      i++;
      const o = Object.create(null);
      ws();
      if (text[i] === '}') { i++; return o; }
      for (;;) {
        ws();
        if (text[i] !== '"') fail('object key must be a string');
        const k = str();
        if (k in o) fail(`duplicate key ${JSON.stringify(k)}`);
        ws();
        if (text[i] !== ':') fail('expected ":"');
        i++;
        o[k] = value(depth + 1);
        ws();
        if (text[i] === ',') { i++; continue; }
        if (text[i] === '}') { i++; return o; }
        fail('expected "," or "}"');
      }
    }
    if (c === '[') {
      i++;
      const a = [];
      ws();
      if (text[i] === ']') { i++; return a; }
      for (;;) {
        a.push(value(depth + 1));
        ws();
        if (text[i] === ',') { i++; continue; }
        if (text[i] === ']') { i++; return a; }
        fail('expected "," or "]"');
      }
    }
    if (c === '"') return str();
    if (text.startsWith('true', i)) { i += 4; return true; }
    if (text.startsWith('false', i)) { i += 5; return false; }
    if (text.startsWith('null', i)) { i += 4; return null; }
    const m = /^-?(0|[1-9]\d*)/.exec(text.slice(i, i + 24));
    if (!m) fail('unexpected character');
    i += m[0].length;
    if (text[i] === '.' || text[i] === 'e' || text[i] === 'E') fail('numbers must be integers');
    const n = Number(m[0]);
    if (!Number.isSafeInteger(n)) fail('number out of range');
    return n;
  };
  const str = () => {
    i++; // opening quote
    let out = '';
    for (;;) {
      if (i >= text.length) fail('unterminated string');
      const ch = text[i];
      const code = text.charCodeAt(i);
      if (ch === '"') { i++; break; }
      if (code < 0x20) fail('raw control character in string');
      if (ch === '\\') {
        const e = text[i + 1];
        const simple = { '"': '"', '\\': '\\', '/': '/', b: '\b', f: '\f', n: '\n', r: '\r', t: '\t' };
        if (e in simple) { out += simple[e]; i += 2; continue; }
        if (e === 'u') {
          const h = text.slice(i + 2, i + 6);
          if (!/^[0-9a-fA-F]{4}$/.test(h)) fail('bad \\u escape');
          out += String.fromCharCode(parseInt(h, 16));
          i += 6;
          continue;
        }
        fail('bad escape');
      }
      out += ch;
      i++;
    }
    if (!isWellFormed(out)) fail('lone surrogate in string');
    return out;
  };
  try {
    const v = value(0);
    ws();
    if (i !== text.length) fail('trailing data after the document');
    return { ok: true, value: v };
  } catch (e) {
    if (e && e.strict) return { ok: false, error: `${e.message} (at offset ${i})` };
    throw e;
  }
}

function isWellFormed(s) {
  for (let k = 0; k < s.length; k++) {
    const c = s.charCodeAt(k);
    if (c >= 0xd800 && c <= 0xdbff) {
      const d = s.charCodeAt(k + 1);
      if (!(d >= 0xdc00 && d <= 0xdfff)) return false;
      k++;
    } else if (c >= 0xdc00 && c <= 0xdfff) return false;
  }
  return true;
}

// ---------------------------------------------------------------------------------------------- canonical form ----

/**
 * The one byte form a signature covers. Object keys sorted by UTF-16 code unit, no whitespace, integers only. A string
 * escapes `"` and `\` and EVERY control character below 0x20 as \u00xx (lower-case hex; so a newline is \u000a, not \n),
 * and writes everything else as the character itself (UTF-8 on the wire). This is deliberately NOT JSON.stringify: the Dart
 * client writes control characters this way, and the two must agree byte for byte (pinned by test-vectors.json).
 */
export function canonicalize(v) {
  const out = [];
  canon(v, out);
  return out.join('');
}
function canon(v, out) {
  if (v === null) out.push('null');
  else if (typeof v === 'boolean') out.push(v ? 'true' : 'false');
  else if (typeof v === 'number') {
    if (!Number.isSafeInteger(v)) throw new Error('canonical form holds integers only (up to 2^53-1)');
    out.push(String(v));
  } else if (typeof v === 'string') canonString(v, out);
  else if (Array.isArray(v)) {
    out.push('[');
    v.forEach((x, k) => { if (k) out.push(','); canon(x, out); });
    out.push(']');
  } else if (typeof v === 'object') {
    const keys = Object.keys(v).sort();
    out.push('{');
    keys.forEach((k, n) => { if (n) out.push(','); canonString(k, out); out.push(':'); canon(v[k], out); });
    out.push('}');
  } else throw new Error(`cannot canonicalize a ${typeof v}`);
}
function canonString(s, out) {
  let r = '"';
  for (let k = 0; k < s.length; k++) {
    const c = s.charCodeAt(k);
    if (c === 0x22) r += '\\"';
    else if (c === 0x5c) r += '\\\\';
    else if (c < 0x20) r += `\\u${c.toString(16).padStart(4, '0')}`;
    else r += s[k];
  }
  out.push(`${r}"`);
}

/** The exact bytes the owner's offline key signs for a manifest payload (the object under "manifest"). */
export function signingBytes(payload) {
  return Buffer.from(SIGN_DOMAIN + canonicalize(payload), 'utf8');
}

// -------------------------------------------------------------------------------------------------- the keys ----

const SPKI_ED25519_PREFIX = Buffer.from('302a300506032b6570032100', 'hex');
const KID_RE = /^[A-Za-z0-9._-]{1,32}$/;

export const b64u = (buf) => Buffer.from(buf).toString('base64url');
/** Strict base64url (no standard-alphabet characters, no whitespace); padding tolerated as the Dart side tolerates it. Null on any problem. */
export function fromB64u(s) {
  if (typeof s !== 'string' || !/^[A-Za-z0-9_-]*={0,2}$/.test(s)) return null;
  const buf = Buffer.from(s, 'base64url');
  return buf.toString('base64url') === s.replace(/=+$/, '') ? buf : null;
}

/** Raw 32-byte public key -> Node KeyObject. */
export function publicKeyObject(raw32) {
  if (!Buffer.isBuffer(raw32) || raw32.length !== 32) throw new Error('a public key is exactly 32 bytes');
  return createPublicKey({ key: Buffer.concat([SPKI_ED25519_PREFIX, raw32]), format: 'der', type: 'spki' });
}
/** Node public KeyObject -> raw 32 bytes. */
export function rawPublicKey(keyObject) {
  const der = keyObject.export({ type: 'spki', format: 'der' });
  return Buffer.from(der.subarray(der.length - 32));
}
/** The short label a signature carries so an app can tell which of its built-in keys to use: 16 hex digits of SHA-256(raw key). */
export function kidOf(raw32) { return createHash('sha256').update(raw32).digest('hex').slice(0, 16); }

/** One `--dart-define=OLIVE_UPDATE_PUBKEYS=` entry. */
export const trustEntry = (kid, raw32) => `${kid}:${b64u(raw32)}`;

/** Parses the define exactly as the app does: `kid:base64url(32 bytes)` entries, comma separated, malformed ones ignored. Map<kid, Buffer>. */
export function parseTrust(csv) {
  const out = new Map();
  for (const part of String(csv).split(',')) {
    const p = part.trim();
    const at = p.indexOf(':');
    if (at < 1) continue;
    const kid = p.slice(0, at);
    if (!KID_RE.test(kid)) continue;
    const k = fromB64u(p.slice(at + 1));
    if (k && k.length === 32) out.set(kid, k);
  }
  return out;
}

// ------------------------------------------------------------------------------------------------- the schema ----

const HEX64 = /^[0-9a-f]{64}$/;
const CHANNEL_RE = /^[a-z0-9][a-z0-9-]{0,31}$/;
const VERSION_RE = /^\d{1,4}\.\d{1,4}\.\d{1,4}(-[0-9A-Za-z.-]{1,20})?$/;
const PLAIN_VERSION_RE = /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/;
const ISO_UTC_RE = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(\.\d{1,3})?Z$/;
/** Release notes are plain text for a grown-up: no markup, no code, no control characters, no bidirectional overrides. */
const NOTE_FORBIDDEN = new RegExp('[<>`' + [[0, 0x1f], [0x7f, 0x9f], [0x200b, 0x200f], [0x202a, 0x202e], [0x2028, 0x2029], [0x2060, 0x2064], [0xfeff, 0xfeff]].map(([a, b]) => String.fromCharCode(a) + '-' + String.fromCharCode(b)).join('') + ']');

export const TOP_KEYS = Object.freeze(['manifest', 'signature']);
export const PAYLOAD_KEYS = Object.freeze(['schema', 'app', 'channel', 'versionName', 'versionCode', 'minSupportedVersionCode', 'sequence', 'issuedAt', 'expiresAt', 'publishedAt', 'headline', 'notes', 'apks']);
export const APK_KEYS = Object.freeze(['abi', 'size', 'sha256', 'signerSha256', 'chunkSize', 'chunks', 'urls']);
export const SIG_KEYS = Object.freeze(['alg', 'kid', 'sig']);

/** ms since epoch for a UTC time the way the app reads it (optional .mmm), or null when it is not a real instant. */
export function parseTime(s) {
  const m = ISO_UTC_RE.exec(String(s));
  if (!m) return null;
  const [y, mo, d, h, mi, se] = m.slice(1, 7).map(Number);
  const ms = m[7] ? Math.round(Number(`0${m[7]}`) * 1000) : 0;
  const t = Date.UTC(y, mo - 1, d, h, mi, se, ms);
  const e = new Date(t);
  if (e.getUTCFullYear() !== y || e.getUTCMonth() !== mo - 1 || e.getUTCDate() !== d || e.getUTCHours() !== h || e.getUTCMinutes() !== mi || e.getUTCSeconds() !== se) return null;
  return t;
}
export const formatTime = (ms) => new Date(ms).toISOString().replace(/\.\d{3}Z$/, 'Z');

/**
 * The URL rule for anything a manifest tells an app to fetch. https only, a public host name, default port, no credentials, no
 * fragment, and written exactly as the URL parser writes it (so a backslash, a tab or an upper-case host cannot hide a second
 * reading). `allowLoopbackHttp` exists for tests and the developer lane: plain http to the literal addresses 127.0.0.1 and ::1
 * only, never a name, never a LAN address (the same carve-out as the app's transport policy). A query is allowed: a signed-URL
 * mirror needs one; a fragment never is.
 */
export function urlProblem(s, { allowLoopbackHttp = false } = {}) {
  if (typeof s !== 'string') return 'not a string';
  if (s.length > LIMITS.urlChars) return `longer than ${LIMITS.urlChars} characters`;
  if (!/^[\x21-\x7e]+$/.test(s)) return 'must be printable ASCII with no spaces';
  let u;
  try { u = new URL(s); } catch { return 'not a URL'; }
  if (u.href !== s) return 'is not written in canonical form';
  if (u.username || u.password) return 'must not embed credentials';
  if (u.hash || s.includes('#')) return 'must not carry a fragment';
  if (u.pathname === '/' || u.pathname === '') return 'must name a file path';
  const h = u.hostname.toLowerCase();
  if (u.protocol === 'http:') {
    if (allowLoopbackHttp && (h === '127.0.0.1' || h === '[::1]')) return null;
    return 'cleartext http is refused (https only)';
  }
  if (u.protocol !== 'https:') return `unsupported scheme ${u.protocol}`;
  if (u.port && u.port !== '443') return 'must use the default https port';
  if (h === 'localhost' || /\.(localhost|local|lan|internal|test|invalid|home|corp|example)$/.test(h)) return `${h} is a local or reserved name`;
  if (/^\d{1,3}(\.\d{1,3}){3}$/.test(h) || h.startsWith('[') || h.includes(':')) return `${h} is an IP literal; use the public name`;
  if (!h.includes('.')) return `${h} is not a public host name`;
  return null;
}

/**
 * Validates the signed OBJECT (the payload under "manifest"). Returns "path: reason" strings; empty means it has the shape the
 * spec says. It does not check the signature and no policy beyond shape (those are verifyDocument / policyProblems).
 * @param {object} o
 * @param {{strict?:boolean, allowLoopbackHttp?:boolean}} [opts]  strict (the default) also refuses members this version does not know
 */
export function validatePayload(o, { strict = true, allowLoopbackHttp = false } = {}) {
  const out = [];
  const bad = (p, why) => out.push(`${p}: ${why}`);
  const isObj = (x) => x !== null && typeof x === 'object' && !Array.isArray(x);
  const int = (p, v, lo, hi) => {
    if (typeof v !== 'number' || !Number.isSafeInteger(v)) { bad(p, 'must be an integer'); return false; }
    if (v < lo || v > hi) { bad(p, `must be between ${lo} and ${hi}`); return false; }
    return true;
  };
  const short = (p, v, max, { nonEmpty = true } = {}) => {
    if (typeof v !== 'string' || (nonEmpty && v === '') || v.length > max) { bad(p, `must be a${nonEmpty ? ' non-empty' : ''} string of at most ${max} characters`); return false; }
    return true;
  };
  const keys = (p, x, allowed, required) => {
    if (strict) for (const k of Object.keys(x)) if (!allowed.includes(k)) bad(`${p}${k}`, 'is not a known member');
    for (const k of required) if (!(k in x)) bad(`${p}${k}`, 'is required');
  };
  if (!isObj(o)) return ['(manifest): must be a JSON object'];
  keys('', o, PAYLOAD_KEYS, PAYLOAD_KEYS);

  if ('schema' in o && o.schema !== SCHEMA_VERSION) bad('schema', `must be ${SCHEMA_VERSION}`);
  if ('app' in o && short('app', o.app, LIMITS.textChars) && o.app !== APP_ID) bad('app', `must be ${APP_ID}`);
  if ('channel' in o && short('channel', o.channel, 32) && !CHANNEL_RE.test(o.channel)) bad('channel', 'must be a short lower-case word such as "stable"');
  if ('versionName' in o && short('versionName', o.versionName, 40) && !VERSION_RE.test(o.versionName)) bad('versionName', 'must look like 1.2.3');
  let vc = null, min = null;
  if ('versionCode' in o && int('versionCode', o.versionCode, 1, LIMITS.versionCodeMax)) vc = o.versionCode;
  if ('minSupportedVersionCode' in o && int('minSupportedVersionCode', o.minSupportedVersionCode, 1, LIMITS.versionCodeMax)) min = o.minSupportedVersionCode;
  if (vc !== null && min !== null && min > vc) bad('minSupportedVersionCode', 'must not be greater than versionCode');
  if ('sequence' in o) int('sequence', o.sequence, 1, LIMITS.safeInt);
  const t = {};
  for (const k of ['issuedAt', 'expiresAt', 'publishedAt']) {
    if (!(k in o)) continue;
    t[k] = parseTime(o[k]);
    if (t[k] === null) bad(k, 'must be a real UTC time like 2026-11-21T10:00:00Z');
  }
  if (t.issuedAt != null && t.expiresAt != null) {
    if (t.expiresAt <= t.issuedAt) bad('expiresAt', 'must be after issuedAt');
    else if (t.expiresAt - t.issuedAt > LIMITS.validityDays * 86400000) bad('expiresAt', `must be within ${LIMITS.validityDays} days of issuedAt`);
  }
  if ('headline' in o) short('headline', o.headline, LIMITS.headlineChars, { nonEmpty: false });

  if ('notes' in o) {
    if (!Array.isArray(o.notes)) bad('notes', 'must be an array of plain-words lines');
    else {
      if (o.notes.length > LIMITS.notes) bad('notes', `holds more than ${LIMITS.notes} lines`);
      o.notes.forEach((n, k) => {
        if (!short(`notes[${k}]`, n, LIMITS.noteChars)) return;
        // Plain-text rules are NOT relaxed by strict:false (the app refuses these unconditionally); strict only governs unknown members.
        if (NOTE_FORBIDDEN.test(n)) bad(`notes[${k}]`, 'must be plain text: no angle brackets, backticks, control or invisible characters');
        else if (n !== n.trim()) bad(`notes[${k}]`, 'must not start or end with spaces');
      });
    }
  }
  if (typeof o.headline === 'string' && (NOTE_FORBIDDEN.test(o.headline) || o.headline !== o.headline.trim())) bad('headline', 'must be plain text with no markup, control characters or edge spaces');

  if ('apks' in o) {
    if (!Array.isArray(o.apks) || o.apks.length < 1 || o.apks.length > LIMITS.apks) bad('apks', `must hold 1 to ${LIMITS.apks} files`);
    else {
      const abis = new Set();
      o.apks.forEach((a, k) => {
        const p = `apks[${k}].`;
        if (!isObj(a)) { bad(`apks[${k}]`, 'must be an object'); return; }
        keys(p, a, APK_KEYS, APK_KEYS);
        if ('abi' in a) {
          if (!ABIS.includes(a.abi)) bad(`${p}abi`, `must be one of ${ABIS.join(', ')}`);
          else if (abis.has(a.abi)) bad(`${p}abi`, 'a second file for the same abi');
          else abis.add(a.abi);
        }
        const sizeOk = 'size' in a && int(`${p}size`, a.size, 1, LIMITS.apkBytes);
        for (const f of ['sha256', 'signerSha256']) if (f in a && !(typeof a[f] === 'string' && HEX64.test(a[f]))) bad(`${p}${f}`, 'must be 64 lower-case hex digits');
        const csOk = 'chunkSize' in a && int(`${p}chunkSize`, a.chunkSize, LIMITS.chunkMin, LIMITS.chunkMax);
        if ('chunks' in a) {
          if (!Array.isArray(a.chunks)) bad(`${p}chunks`, 'must be an array of SHA-256 hex digests');
          else {
            if (a.chunks.length > LIMITS.chunksMax) bad(`${p}chunks`, `holds more than ${LIMITS.chunksMax} hashes`);
            if (a.chunks.some((h) => !(typeof h === 'string' && HEX64.test(h)))) bad(`${p}chunks`, 'every entry must be 64 lower-case hex digits');
            if (sizeOk && csOk && a.chunks.length !== Math.ceil(a.size / a.chunkSize)) bad(`${p}chunks`, `must hold exactly ceil(size / chunkSize) = ${Math.ceil(a.size / a.chunkSize)} hashes, has ${a.chunks.length}`);
          }
        }
        if ('urls' in a) {
          if (!Array.isArray(a.urls) || a.urls.length < 1 || a.urls.length > LIMITS.urls) bad(`${p}urls`, `must hold 1 to ${LIMITS.urls} addresses (the first is primary, the rest are mirrors)`);
          else {
            a.urls.forEach((u, c) => { const pr = urlProblem(u, { allowLoopbackHttp }); if (pr) bad(`${p}urls[${c}]`, pr); });
            if (new Set(a.urls).size !== a.urls.length) bad(`${p}urls`, 'must not repeat an address');
          }
        }
      });
    }
  }
  return out;
}

/** The publisher's own rules on top of shape: what RELEASING.md promises about a version (the app does not check these). */
export function policyProblems(o, { buildNumberFn = defaultBuildNumber, requireMirror = false } = {}) {
  const out = [];
  if (typeof o.versionName !== 'string' || !PLAIN_VERSION_RE.test(o.versionName)) out.push('versionName: a published version is MAJOR.MINOR.PATCH with no suffix');
  else {
    let want;
    try { want = buildNumberFn(o.versionName); } catch (e) { out.push(`versionName: ${e.message}`); }
    if (want !== undefined && o.versionCode !== want) out.push(`versionCode: ${o.versionCode} is not major*10000 + minor*100 + patch of ${o.versionName} (= ${want}); the code is derived from the version, never chosen`);
  }
  // A sequence far above the issue time would be remembered by every phone that accepts it, and every later manifest would
  // then look "replayed": updates dead for good. The sequence is therefore bounded by the issue time (in seconds) plus a day.
  const issued = parseTime(o.issuedAt);
  if (Number.isSafeInteger(o.sequence) && issued !== null && o.sequence > Math.floor(issued / 1000) + LIMITS.sequenceSlackSeconds) {
    out.push(`sequence: ${o.sequence} is above the issue time in seconds (${Math.floor(issued / 1000)}) plus ${LIMITS.sequenceSlackSeconds}; a sequence this high would make every later manifest look replayed. Use the default (seconds since the epoch at issue)`);
  }
  if (requireMirror && Array.isArray(o.apks)) o.apks.forEach((a, k) => { if (Array.isArray(a.urls) && a.urls.length < 2) out.push(`apks[${k}].urls: a published update names a primary address AND at least one mirror`); });
  return out;
}
function defaultBuildNumber(v) {
  const m = PLAIN_VERSION_RE.exec(v);
  if (!m) throw new Error('not MAJOR.MINOR.PATCH');
  const [major, minor, patch] = [+m[1], +m[2], +m[3]];
  if (minor > 99 || patch > 99) throw new Error('minor and patch must be 0..99');
  return major * 10000 + minor * 100 + patch;
}

/** Validates the whole document shape: { manifest, signature }. */
export function validateDocument(doc, opts = {}) {
  const isObj = (x) => x !== null && typeof x === 'object' && !Array.isArray(x);
  if (!isObj(doc)) return ['(document): must be a JSON object'];
  const out = [];
  const strict = opts.strict !== false;
  if (strict) for (const k of Object.keys(doc)) if (!TOP_KEYS.includes(k)) out.push(`${k}: is not a known member`);
  if (!('manifest' in doc)) out.push('manifest: is required');
  if (!('signature' in doc)) out.push('signature: is required');
  if ('manifest' in doc) out.push(...validatePayload(doc.manifest, opts));
  if ('signature' in doc) {
    const s = doc.signature;
    if (!isObj(s)) out.push('signature: must be an object');
    else {
      if (strict) for (const k of Object.keys(s)) if (!SIG_KEYS.includes(k)) out.push(`signature.${k}: is not a known member`);
      if (s.alg !== SIG_ALG) out.push(`signature.alg: must be "${SIG_ALG}"`);
      if (!(typeof s.kid === 'string' && KID_RE.test(s.kid))) out.push('signature.kid: must be 1 to 32 characters of A-Z a-z 0-9 . _ -');
      const sig = typeof s.sig === 'string' ? fromB64u(s.sig) : null;
      if (!sig || sig.length !== 64) out.push('signature.sig: must be a 64-byte Ed25519 signature in base64url');
    }
  }
  return out;
}

// --------------------------------------------------------------------------------------------------- signing ----

/** Signs a manifest payload with a Node private KeyObject. Returns the document { manifest, signature }. */
export function signPayload(payload, privateKey, kid) {
  if (!KID_RE.test(kid)) throw new Error('bad key id');
  const sig = edSign(null, signingBytes(payload), privateKey);
  return { manifest: payload, signature: { alg: SIG_ALG, kid, sig: b64u(sig) } };
}

/** The signature check alone: { ok } or { ok:false, code }. The key is looked up by the document's kid in `trust` (Map kid -> raw 32 bytes). */
export function verifySignature(doc, trust) {
  if (!trust || trust.size === 0) return { ok: false, code: 'noKeyConfigured' };
  const s = doc.signature;
  if (!s || s.alg !== SIG_ALG || typeof s.kid !== 'string' || typeof s.sig !== 'string') return { ok: false, code: 'badSignature', detail: 'unsupported algorithm or missing parts' };
  const raw = trust.get(s.kid);
  if (!raw) return { ok: false, code: 'unknownKey' };
  const sig = fromB64u(s.sig);
  if (!sig || sig.length !== 64) return { ok: false, code: 'badSignature' };
  let msg;
  try { msg = signingBytes(doc.manifest); } catch { return { ok: false, code: 'badSignature', detail: 'no canonical form' }; }
  let ok = false;
  try { ok = edVerify(null, msg, publicKeyObject(raw), sig); } catch { ok = false; }
  return ok ? { ok: true } : { ok: false, code: 'badSignature' };
}

// ---------------------------------------------------------------------------------- everything the app checks ----

/**
 * The whole decision about a downloaded manifest, in the order the app makes it, from the bytes to "this is an update":
 *   size cap -> a key to check against -> strict JSON -> document shape -> signature under a built-in key -> payload shape
 *   (nothing that failed the signature is ever read as a model) -> app id -> channel -> clock (not from the future, not past
 *   expiresAt) -> replay (not an older manifest than one already accepted) -> rollback (versionCode not below the installed one).
 *
 * Returns { ok, code, detail, manifest, status }. `status` is meaningful only when ok:
 *   'update'      versionCode is strictly greater than the installed one
 *   'up-to-date'  equal (a valid manifest, nothing to do)
 * `code` on failure is one of CODES.
 *
 * @param {Buffer|string} input
 * @param {object} ctx
 * @param {Map<string,Buffer>} ctx.trust        built-in public keys by kid (parseTrust)
 * @param {string}  ctx.channel                 the channel this app follows
 * @param {number}  ctx.installedVersionCode
 * @param {number} [ctx.highestSeenSequence]    largest sequence of any manifest this device accepted before
 * @param {number} [ctx.now]                    ms since epoch
 * @param {boolean}[ctx.allowLoopbackHttp]
 * @param {boolean}[ctx.strict]                 false: tolerate members this version does not know (what the app does)
 */
export function verifyDocument(input, ctx) {
  const fail = (code, detail = '', manifest = null) => ({ ok: false, code, detail, manifest });
  const buf = Buffer.isBuffer(input) ? input : Buffer.from(String(input), 'utf8');
  if (buf.length > LIMITS.manifestBytes) return fail('tooLarge', `larger than ${LIMITS.manifestBytes} bytes`);
  if (!ctx.trust || ctx.trust.size === 0) return fail('noKeyConfigured');
  let text;
  try { text = new TextDecoder('utf-8', { fatal: true, ignoreBOM: true }).decode(buf); } catch { return fail('notJson', 'not valid UTF-8'); }
  const parsed = parseStrictJson(text);
  if (!parsed.ok) return fail('notJson', parsed.error);
  const doc = parsed.value;
  if (doc === null || typeof doc !== 'object' || Array.isArray(doc)) return fail('notJson', 'not an object');
  if (doc.manifest === null || typeof doc.manifest !== 'object' || Array.isArray(doc.manifest) || doc.signature === null || typeof doc.signature !== 'object' || Array.isArray(doc.signature)) return fail('badShape', 'missing manifest or signature');
  const sig = verifySignature(doc, ctx.trust);
  if (!sig.ok) return fail(sig.code, sig.detail);
  const problems = validatePayload(doc.manifest, { strict: ctx.strict !== false, allowLoopbackHttp: !!ctx.allowLoopbackHttp });
  if (problems.length) {
    const code = doc.manifest.app !== undefined && doc.manifest.app !== APP_ID ? 'wrongApp'
      : problems.some((p) => /\.urls\[/.test(p)) ? 'badUrl'
      : (Array.isArray(doc.manifest.apks) && doc.manifest.apks.some((a) => a && Number.isSafeInteger(a.size) && a.size > LIMITS.apkBytes)) ? 'sizeTooLarge' : 'badShape';
    return fail(code, problems.slice(0, 4).join('; '), doc.manifest);
  }
  const m = doc.manifest;
  if (m.channel !== ctx.channel) return fail('wrongChannel', `signed for "${m.channel}", this app follows "${ctx.channel}"`, m);
  const now = ctx.now ?? Date.now();
  if (parseTime(m.issuedAt) > now + LIMITS.clockSkewMs) return fail('notYetValid', 'issuedAt is in the future', m);
  if (parseTime(m.expiresAt) < now) return fail('expired', 'past expiresAt', m);
  if (ctx.highestSeenSequence != null && m.sequence < ctx.highestSeenSequence) return fail('replayed', `sequence ${m.sequence} is older than ${ctx.highestSeenSequence}, already accepted`, m);
  if (m.versionCode < ctx.installedVersionCode) return fail('rollback', `versionCode ${m.versionCode} is below the installed ${ctx.installedVersionCode}`, m);
  return { ok: true, code: 'ok', detail: 'valid', manifest: m, status: m.versionCode > ctx.installedVersionCode ? 'update' : 'up-to-date' };
}

/** Where the installed build stands against the manifest's floor. Adults see "Please update"; the child never sees anything. */
export const supportStatus = (m, installedVersionCode) => (installedVersionCode < m.minSupportedVersionCode ? 'below-minimum' : 'supported');

/** The file entry for this device's ABI list, most specific first; falls back to a "universal" entry. Null when none fits. */
export function pickApk(m, deviceAbis) {
  for (const abi of deviceAbis) { const a = m.apks.find((x) => x.abi === abi); if (a) return a; }
  return m.apks.find((x) => x.abi === 'universal') ?? null;
}

// ------------------------------------------------------------------------------------------------ the APK ----

/**
 * Streams a file and checks it the way the app's chunked, resumable download does: the exact size, every chunk hash, the
 * whole-file SHA-256. Never reads past size+1 bytes. Returns { ok, code, detail }; code is a Refusal code (truncated,
 * tooMuchData, hashMismatch, apkMismatch).
 */
export async function verifyApkFile(path, apk) {
  const { createReadStream, statSync } = await import('node:fs');
  let st;
  try { st = statSync(path); } catch { return { ok: false, code: 'apkMismatch', detail: 'the file does not exist' }; }
  if (st.size < apk.size) return { ok: false, code: 'truncated', detail: `the file is ${st.size} bytes, the manifest says ${apk.size}` };
  if (st.size > apk.size) return { ok: false, code: 'tooMuchData', detail: `the file is ${st.size} bytes, the manifest says ${apk.size}` };
  const h = await hashFile(path, apk.chunkSize);
  const n = apk.chunks.length;
  if (h.chunks.length !== n) return { ok: false, code: 'hashMismatch', detail: 'the number of chunks does not match the manifest' };
  for (let k = 0; k < n; k++) if (h.chunks[k] !== apk.chunks[k]) return { ok: false, code: 'hashMismatch', detail: `chunk ${k} does not match its hash` };
  if (h.sha256 !== apk.sha256) return { ok: false, code: 'hashMismatch', detail: 'the whole-file SHA-256 does not match the manifest' };
  return { ok: true, code: 'ok', detail: 'size, every chunk and the SHA-256 match' };
}

/** Whole-file SHA-256, size and per-chunk SHA-256 of a file (streamed). */
export async function hashFile(path, chunkSize) {
  const { createReadStream } = await import('node:fs');
  const whole = createHash('sha256');
  const chunks = [];
  let filled = 0, chunk = createHash('sha256'), size = 0;
  for await (const buf of createReadStream(path, { highWaterMark: Math.min(chunkSize, 1 << 20) })) {
    whole.update(buf); size += buf.length;
    let off = 0;
    while (off < buf.length) {
      const take = Math.min(chunkSize - filled, buf.length - off);
      chunk.update(buf.subarray(off, off + take));
      filled += take; off += take;
      if (filled === chunkSize) { chunks.push(chunk.digest('hex')); filled = 0; chunk = createHash('sha256'); }
    }
  }
  if (filled > 0) chunks.push(chunk.digest('hex'));
  return { size, sha256: whole.digest('hex'), chunks };
}

/** The chunk size the build script uses: 1 MiB, doubled until the chunk list is short enough to keep the manifest small. */
export function chooseChunkSize(size) {
  let c = LIMITS.chunkDefault;
  while (Math.ceil(size / c) > LIMITS.chunksPreferred && c < LIMITS.chunkMax) c *= 2;
  return c;
}

/**
 * A cheap structural look inside an APK (a zip) WITHOUT extracting anything: reads only the central directory. It refuses what
 * a hostile or broken file does: no readable central directory, zip64 (an APK is never that big here), too many entries,
 * duplicate entry names (one file for the installer, another for a scanner), names that climb out of a folder, absurd
 * compression ratios or a declared uncompressed total beyond LIMITS, and a missing AndroidManifest.xml or classes.dex.
 * It is NOT a signature check; the signing certificate is compared separately (apksigner here, PackageManager in the app).
 */
export async function inspectApkZip(path) {
  const { openSync, readSync, closeSync, fstatSync } = await import('node:fs');
  const fd = openSync(path, 'r');
  try {
    const size = fstatSync(fd).size;
    if (size < 22) return { ok: false, problems: ['too small to be a zip'] };
    const tailLen = Math.min(size, 22 + 65535);
    const tail = Buffer.alloc(tailLen);
    readSync(fd, tail, 0, tailLen, size - tailLen);
    let e = -1;
    for (let k = tailLen - 22; k >= 0; k--) { if (tail.readUInt32LE(k) === 0x06054b50) { e = k; break; } }
    if (e < 0) return { ok: false, problems: ['no zip end-of-directory record'] };
    const entries = tail.readUInt16LE(e + 10);
    const cdSize = tail.readUInt32LE(e + 12);
    const cdOff = tail.readUInt32LE(e + 16);
    if (entries === 0xffff || cdSize === 0xffffffff || cdOff === 0xffffffff) return { ok: false, problems: ['zip64 archives are not accepted'] };
    if (entries > LIMITS.zipEntries) return { ok: false, problems: [`more than ${LIMITS.zipEntries} entries`] };
    if (cdSize > 16 * 1024 * 1024 || cdOff + cdSize > size) return { ok: false, problems: ['the central directory is out of range'] };
    const cd = Buffer.alloc(cdSize);
    readSync(fd, cd, 0, cdSize, cdOff);
    const problems = [];
    const names = new Set();
    let p = 0, total = 0, sawManifest = false, sawDex = false;
    for (let k = 0; k < entries; k++) {
      if (p + 46 > cd.length || cd.readUInt32LE(p) !== 0x02014b50) { problems.push('the central directory is damaged'); break; }
      const comp = cd.readUInt32LE(p + 20), unc = cd.readUInt32LE(p + 24);
      const nl = cd.readUInt16LE(p + 28), xl = cd.readUInt16LE(p + 30), cl = cd.readUInt16LE(p + 32);
      if (p + 46 + nl > cd.length) { problems.push('an entry name runs past the directory'); break; }
      const name = cd.subarray(p + 46, p + 46 + nl).toString('utf8');
      p += 46 + nl + xl + cl;
      if (names.has(name)) problems.push(`duplicate entry name ${JSON.stringify(name)}`);
      names.add(name);
      if (name.startsWith('/') || name.includes('\\') || name.split('/').includes('..')) problems.push(`unsafe entry name ${JSON.stringify(name)}`);
      total += unc;
      if (unc > 1024 * 1024 && unc / Math.max(comp, 1) > LIMITS.zipRatio) problems.push(`entry ${JSON.stringify(name)} expands more than ${LIMITS.zipRatio} times`);
      if (name === 'AndroidManifest.xml') sawManifest = true;
      if (/^classes\d*\.dex$/.test(name)) sawDex = true;
    }
    if (total > LIMITS.zipUncompressedBytes) problems.push(`declares ${total} bytes uncompressed (limit ${LIMITS.zipUncompressedBytes})`);
    if (!sawManifest) problems.push('has no AndroidManifest.xml');
    if (!sawDex) problems.push('has no classes.dex');
    return { ok: problems.length === 0, problems, entries, uncompressedBytes: total };
  } finally { closeSync(fd); }
}

// ------------------------------------------------------------------------------------------ tools outputs ----

/** Signing certificate SHA-256 digests out of `apksigner verify --print-certs`. Returns the lower-case hex of each signer. */
export function parseApksignerCerts(text) {
  return [...String(text).matchAll(/Signer #\d+ certificate SHA-256 digest:\s*([0-9a-fA-F]{64})/g)].map((m) => m[1].toLowerCase());
}
/** package, versionCode and versionName out of `aapt2 dump badging`. */
export function parseBadging(text) {
  const m = /package: name='([^']+)' versionCode='(\d+)' versionName='([^']*)'/.exec(String(text));
  return m ? { pkg: m[1], versionCode: Number(m[2]), versionName: m[3] } : null;
}

// ----------------------------------------------------------------------------------------------- the network ----

/**
 * Whether following a redirect is allowed. The integrity of a download never depends on where it came from (size, chunks and
 * SHA-256 are signed), but a redirect must still never downgrade to cleartext, never carry credentials, never leave the hosts
 * the publisher trusts, and a chain must end. Cleartext is only ever reachable when the developer option is on AND the target is
 * a literal loopback address. `allowedHosts` are lower-case host names (the hosts of the manifest's own addresses plus the
 * publisher's CDN, e.g. GitHub's asset hosts).
 * @returns {string|null} the reason it is refused, or null
 */
export function redirectProblem(toUrl, { allowLoopbackHttp = false, allowedHosts = [] } = {}) {
  let u;
  try { u = new URL(toUrl); } catch { return 'the redirect target is not a URL'; }
  if (u.username || u.password) return 'the redirect target embeds credentials';
  const h = u.hostname.toLowerCase();
  if (u.protocol === 'http:') {
    if (!(allowLoopbackHttp && (h === '127.0.0.1' || h === '[::1]'))) return 'the redirect goes to cleartext http';
  } else if (u.protocol !== 'https:') return `the redirect goes to ${u.protocol}`;
  if (u.protocol === 'https:' && u.port && u.port !== '443') return 'the redirect uses a non-default port';
  if (!allowedHosts.includes(h)) return `the redirect leaves the trusted hosts (${h})`;
  return null;
}

/** Hosts GitHub serves a release asset from after the github.com address redirects. */
export const GITHUB_ASSET_HOSTS = Object.freeze(['github.com', 'objects.githubusercontent.com', 'release-assets.githubusercontent.com']);
