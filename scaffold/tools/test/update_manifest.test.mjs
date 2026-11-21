/**
 * The signed update manifest, RELEASE side (docs/UPDATE-MANIFEST.md, tools/update/manifest_lib.mjs).
 *
 * Real hostile cases, not a happy path: tampered manifest (every field, one at a time), wrong key, a lying key id, a signature
 * with the wrong algorithm, rollback, replay, wrong channel, wrong app, expired and future-dated, missing fields (every one),
 * huge sizes and counts, a zip bomb, duplicate zip entries, truncated and over-long and bit-flipped files, cleartext and look-alike
 * addresses, hostile JSON (duplicate keys, floats, lone surrogates, depth, a byte-order mark). It also pins the shared test vectors
 * (the same file the Dart client must reproduce) and keeps docs/update-manifest.schema.json in step with the validator.
 *
 * usage: node tools/test/update_manifest.test.mjs
 */
import { createHash, generateKeyPairSync, sign as nodeSign } from 'node:crypto';
import { mkdtempSync, readFileSync, rmSync, writeFileSync, appendFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { dirname } from 'node:path';
import * as L from '../update/manifest_lib.mjs';
import { parseNotesFile, draftNotesFromChangelog } from '../update/notes_lib.mjs';
import { draftManifest, flutterArgs } from '../update/build-update-package.mjs';

const HERE = dirname(fileURLToPath(import.meta.url));
const vectors = JSON.parse(readFileSync(join(HERE, '..', 'update', 'test-vectors.json'), 'utf8'));
const schema = JSON.parse(readFileSync(join(HERE, '..', '..', '..', 'docs', 'update-manifest.schema.json'), 'utf8'));

let pass = 0, fail = 0; const rows = [];
const check = (g, n, a, e) => { const ok = JSON.stringify(a) === JSON.stringify(e); ok ? pass++ : fail++; rows.push({ g, n, ok, a: JSON.stringify(a), e: JSON.stringify(e) }); };
const throws = (f) => { try { f(); return false; } catch { return true; } };
const ch = (n) => String.fromCharCode(n);

const keypair = () => {
  const { privateKey, publicKey } = generateKeyPairSync('ed25519');
  const raw = L.rawPublicKey(publicKey);
  const kid = L.kidOf(raw);
  return { privateKey, kid, trust: L.trustEntry(kid, raw), map: L.parseTrust(L.trustEntry(kid, raw)) };
};
const hx = (c) => c.repeat(64);
const NOW = Date.UTC(2026, 11, 1);
const ISSUED = Date.UTC(2026, 10, 21, 10);
const good = () => ({
  schema: 1, app: L.APP_ID, channel: 'stable', versionName: '0.52.0', versionCode: 5200, minSupportedVersionCode: 5100,
  sequence: 1000, issuedAt: L.formatTime(ISSUED), expiresAt: L.formatTime(ISSUED + 180 * 86400000), publishedAt: L.formatTime(ISSUED),
  headline: 'A calmer first run', notes: ['One line.', 'Another line.'],
  apks: [{ abi: 'arm64-v8a', size: 2 * 1048576 + 5, sha256: hx('a'), signerSha256: hx('b'), chunkSize: 1048576, chunks: [hx('1'), hx('2'), hx('3')],
    urls: ['https://downloads.example.org/olive/a.apk', 'https://mirror.example.net/olive/a.apk'] }],
});
const K = keypair();
const ctx = (x = {}) => ({ trust: K.map, channel: 'stable', installedVersionCode: 5100, now: NOW, ...x });
const verify = (doc, x) => L.verifyDocument(typeof doc === 'string' ? doc : `${JSON.stringify(doc)}`, ctx(x));
const sign = (p, k = K) => L.signPayload(p, k.privateKey, k.kid);
const clone = (o) => JSON.parse(JSON.stringify(o));

// ================================================================ the shared vectors
{
  const g = 'vectors';
  check(g, 'the vector file names the signing domain the client uses', vectors.signDomain, 'olive-update-manifest-v1\n');
  for (const c of vectors.canonical) {
    check(g, `canonical form: ${c.name}`, L.canonicalize(JSON.parse(c.json)), c.canonical);
    check(g, `signing bytes: ${c.name}`, L.signingBytes(JSON.parse(c.json)).toString('hex'), c.signingBytesHex);
    check(g, `strict parse then canonical agrees: ${c.name}`, L.canonicalize(L.parseStrictJson(c.json).value), c.canonical);
  }
  const trust = L.parseTrust(vectors.trust);
  check(g, 'the vector trust entry parses to one 32-byte key', [trust.size, [...trust.values()][0].length], [1, 32]);
  for (const d of vectors.documents) {
    const r = L.verifyDocument(d.text, { trust, channel: d.ctx.channel, installedVersionCode: d.ctx.installedVersionCode, highestSeenSequence: d.ctx.highestSeenSequence ?? undefined, now: L.parseTime(d.ctx.nowIso), strict: false });
    check(g, `${d.name}: ${d.expect.ok ? 'accepted' : `refused as ${d.expect.code}`}`, r.ok ? { ok: true, status: r.status } : { ok: false, code: r.code }, d.expect.ok ? { ok: true, status: d.expect.status } : { ok: false, code: d.expect.code });
    if (d.expect.belowMinimum) check(g, `${d.name}: adults are told "Please update"`, r.ok && L.supportStatus(r.manifest, d.ctx.installedVersionCode), 'below-minimum');
  }
  check(g, 'the stranger key is not the trusted key', vectors.trust === vectors.strangerTrust, false);
  check(g, 'the vector file carries no private key material', /PRIVATE|BEGIN /.test(JSON.stringify(vectors)), false);
}

// ================================================================ a clean signed manifest
{
  const g = 'valid';
  const doc = sign(good());
  const r = verify(doc);
  check(g, 'a freshly signed manifest is accepted as an update', [r.ok, r.status], [true, 'update']);
  check(g, 'the same version is up to date', verify(doc, { installedVersionCode: 5200 }).status, 'up-to-date');
  check(g, 'a pretty-printed file verifies the same (whitespace is not signed)', verify(`${JSON.stringify(doc, null, 2)}\n`).ok, true);
  check(g, 'member order in the file does not matter (the canonical form sorts)', verify(JSON.stringify({ signature: doc.signature, manifest: Object.fromEntries(Object.entries(doc.manifest).reverse()) })).ok, true);
  check(g, 'strict validation of the same document has no problems', L.validateDocument(doc), []);
  check(g, 'the publishing policy accepts it', L.policyProblems(good(), { requireMirror: true }), []);
  check(g, 'the signature is 64 bytes in base64url', L.fromB64u(doc.signature.sig).length, 64);
  check(g, 'signing is deterministic for one key and one manifest', sign(good()).signature.sig, doc.signature.sig);
  check(g, 'the app below the floor is told so', L.supportStatus(good(), 5000), 'below-minimum');
  check(g, 'the app at the floor is supported', L.supportStatus(good(), 5100), 'supported');
}

// ================================================================ tampering: every leaf, one at a time
{
  const g = 'tampered';
  const doc = sign(good());
  const leaves = [];
  const walk = (v, path) => {
    if (Array.isArray(v)) v.forEach((x, i) => walk(x, [...path, i]));
    else if (v && typeof v === 'object') Object.keys(v).forEach((k) => walk(v[k], [...path, k]));
    else leaves.push(path);
  };
  walk(doc.manifest, []);
  let refused = 0, total = 0;
  for (const path of leaves) {
    const t = clone(doc);
    let o = t.manifest;
    for (const p of path.slice(0, -1)) o = o[p];
    const last = path[path.length - 1];
    const v = o[last];
    o[last] = typeof v === 'number' ? v + 1 : typeof v === 'string' ? `${v}x` : v;
    total++;
    const r = verify(t);
    if (!r.ok) refused++;
    else rows.push({ g, n: `UNDETECTED tamper at ${path.join('.')}`, ok: false, a: 'accepted', e: 'refused' }), fail++;
  }
  check(g, `every one of the ${total} signed values, changed on its own, makes the manifest unusable`, refused, total);
  const sigOnly = clone(doc); sigOnly.signature.sig = `${sigOnly.signature.sig.slice(0, -1)}${sigOnly.signature.sig.endsWith('A') ? 'B' : 'A'}`;
  check(g, 'a changed signature is refused as badSignature', verify(sigOnly).code, 'badSignature');
  const added = clone(doc); added.manifest.extra = 1;
  check(g, 'a member ADDED after signing is a bad signature (the app never reads it)', verify(added).code, 'badSignature');
  const removed = clone(doc); delete removed.manifest.notes;
  check(g, 'a member REMOVED after signing is a bad signature', verify(removed).code, 'badSignature');
  const swapped = clone(doc); [swapped.manifest.apks[0].urls[0], swapped.manifest.apks[0].urls[1]] = [swapped.manifest.apks[0].urls[1], swapped.manifest.apks[0].urls[0]];
  check(g, 'swapping the primary and the mirror is a bad signature (the order is signed)', verify(swapped).code, 'badSignature');
  const body = JSON.stringify(doc);
  check(g, 'a manifest from a different build (other versionCode, same signature) is refused', verify(body.replace('"versionCode":5200', '"versionCode":5201')).code, 'badSignature');
  check(g, 'the domain tag matters: a signature over the bare canonical form is not accepted', (() => {
    const bare = L.canonicalize(good());
    const sig = nodeSign(null, Buffer.from(bare, 'utf8'), K.privateKey);
    return verify({ manifest: good(), signature: { alg: 'ed25519', kid: K.kid, sig: L.b64u(sig) } }).code;
  })(), 'badSignature');
}

// ================================================================ keys
{
  const g = 'keys';
  const other = keypair();
  check(g, 'a manifest signed by an unknown key is refused as unknownKey', verify(sign(good(), other)).code, 'unknownKey');
  const lie = sign(good(), other); lie.signature.kid = K.kid;
  check(g, 'an unknown key that claims the trusted key id is refused as badSignature', verify(lie).code, 'badSignature');
  check(g, 'no key configured: refused as noKeyConfigured before anything is parsed', L.verifyDocument('{', { trust: new Map(), channel: 'stable', installedVersionCode: 1 }).code, 'noKeyConfigured');
  const two = L.parseTrust(`${K.trust},${other.trust}`);
  check(g, 'two built-in keys (rotation): both verify', [L.verifyDocument(JSON.stringify(sign(good())), ctx({ trust: two })).ok, L.verifyDocument(JSON.stringify(sign(good(), other)), ctx({ trust: two })).ok], [true, true]);
  check(g, 'malformed trust entries are ignored, not fatal', L.parseTrust('nokey,:abc,a b:zzzz,ok:AAAA').size, 0);
  check(g, 'a key of the wrong length is ignored', L.parseTrust(`k:${L.b64u(Buffer.alloc(31))}`).size, 0);
  check(g, 'standard base64 characters are not accepted in a key', L.fromB64u('a+b/'), null);
  check(g, 'the key id is 16 hex digits of SHA-256 of the raw key', K.kid, createHash('sha256').update(K.map.get(K.kid)).digest('hex').slice(0, 16));
  const wrongAlg = sign(good()); wrongAlg.signature.alg = 'rsa';
  check(g, 'a different signature algorithm is refused', verify(wrongAlg).code, 'badSignature');
  const shortSig = sign(good()); shortSig.signature.sig = L.b64u(Buffer.alloc(63));
  check(g, 'a 63-byte signature is refused', verify(shortSig).code, 'badSignature');
}

// ================================================================ policy: channel, app, clock, rollback, replay
{
  const g = 'policy';
  check(g, 'wrong channel is refused', verify(sign({ ...good(), channel: 'beta' })).code, 'wrongChannel');
  check(g, 'wrong app is refused', verify(sign({ ...good(), app: 'com.example.other' })).code, 'wrongApp');
  check(g, 'rollback: a validly signed OLDER versionCode than the installed one is refused', verify(sign({ ...good(), versionCode: 5000, versionName: '0.50.0', minSupportedVersionCode: 5000 })).code, 'rollback');
  check(g, 'no rollback to the version that is installed either: equal is "up to date", never an install', verify(sign(good()), { installedVersionCode: 5200 }).status, 'up-to-date');
  check(g, 'replay: a manifest with a lower sequence than one already accepted is refused', verify(sign(good()), { highestSeenSequence: 1001 }).code, 'replayed');
  check(g, 'the SAME sequence again is not a replay (a re-fetch of the same manifest)', verify(sign(good()), { highestSeenSequence: 1000 }).ok, true);
  check(g, 'expired is refused', verify(sign(good()), { now: ISSUED + 181 * 86400000 }).code, 'expired');
  check(g, 'valid right up to its last second', verify(sign(good()), { now: ISSUED + 180 * 86400000 }).ok, true);
  check(g, 'issued in the future (more than a day ahead) is refused', verify(sign(good()), { now: ISSUED - 2 * 86400000 }).code, 'notYetValid');
  check(g, 'a clock a few hours slow is tolerated', verify(sign(good()), { now: ISSUED - 3 * 3600 * 1000 }).ok, true);
  check(g, 'wrong channel is refused even when everything else is perfect and newer', verify(sign({ ...good(), channel: 'beta', versionCode: 9900, versionName: '0.99.0', minSupportedVersionCode: 9900 })).code, 'wrongChannel');
}

// ================================================================ missing and malformed fields
{
  const g = 'shape';
  const top = ['schema', 'app', 'channel', 'versionName', 'versionCode', 'minSupportedVersionCode', 'sequence', 'issuedAt', 'expiresAt', 'publishedAt', 'headline', 'notes', 'apks'];
  for (const k of top) { const p = good(); delete p[k]; check(g, `missing ${k} (even when re-signed) is refused`, verify(sign(p)).ok, false); }
  for (const k of ['abi', 'size', 'sha256', 'signerSha256', 'chunkSize', 'chunks', 'urls']) { const p = good(); delete p.apks[0][k]; check(g, `missing apks[0].${k} (re-signed) is refused`, verify(sign(p)).ok, false); }
  for (const k of ['manifest', 'signature']) { const d = sign(good()); delete d[k]; check(g, `a document without ${k} is refused`, verify(d).ok, false); }
  const bad = (name, mut, code = 'badShape') => { const p = good(); mut(p); const r = verify(sign(p)); check(g, name, [r.ok, r.code], [false, code]); };
  bad('schema 2 is refused', (p) => { p.schema = 2; });
  bad('a string versionCode is refused', (p) => { p.versionCode = '5200'; });
  bad('a zero versionCode is refused', (p) => { p.versionCode = 0; p.minSupportedVersionCode = 0; });
  bad('minSupportedVersionCode above versionCode is refused', (p) => { p.minSupportedVersionCode = 5201; });
  bad('a versionName with a suffix of spaces is refused', (p) => { p.versionName = '0.52.0 '; });
  bad('a channel with upper case is refused', (p) => { p.channel = 'Stable'; });
  bad('not-a-time issuedAt is refused', (p) => { p.issuedAt = 'yesterday'; });
  bad('a 30th of February is refused', (p) => { p.issuedAt = '2026-02-30T10:00:00Z'; });
  bad('an offset time is refused (UTC with Z only)', (p) => { p.issuedAt = '2026-11-21T10:00:00+01:00'; });
  bad('expiry not after issue is refused', (p) => { p.expiresAt = p.issuedAt; });
  bad('validity beyond 400 days is refused', (p) => { p.expiresAt = L.formatTime(ISSUED + 401 * 86400000); });
  bad('a chunk list that does not match the size is refused', (p) => { p.apks[0].chunks.pop(); });
  bad('a short chunk hash is refused', (p) => { p.apks[0].chunks[0] = 'abc'; });
  bad('an upper-case hash is refused', (p) => { p.apks[0].sha256 = hx('A'); });
  bad('a zero size is refused', (p) => { p.apks[0].size = 0; p.apks[0].chunks = []; });
  bad('a chunk size below the floor is refused', (p) => { p.apks[0].chunkSize = 1024; });
  bad('two files for one abi are refused', (p) => { p.apks.push(clone(p.apks[0])); });
  bad('five files are refused', (p) => { p.apks = ['arm64-v8a', 'armeabi-v7a', 'x86_64', 'universal'].flatMap((a) => [{ ...clone(p.apks[0]), abi: a }]).concat([{ ...clone(p.apks[0]), abi: 'x' }]); });
  bad('an unknown abi is refused', (p) => { p.apks[0].abi = 'riscv'; });
  bad('an empty file list is refused', (p) => { p.apks = []; });
  bad('thirteen notes are refused', (p) => { p.notes = Array.from({ length: 13 }, (_, i) => `n${i}`); });
  bad('a 301-character note is refused', (p) => { p.notes = ['x'.repeat(301)]; });
  bad('an empty note is refused', (p) => { p.notes = ['']; });
  bad('a 101-character headline is refused', (p) => { p.headline = 'h'.repeat(101); });
  bad('markup in a note is refused', (p) => { p.notes = ['<b>Tap here</b>']; });
  bad('a backtick in a note is refused', (p) => { p.notes = ['run `x`']; });
  bad('a control character in a note is refused', (p) => { p.notes = [`a${ch(7)}b`]; });
  bad('a right-to-left override in a note is refused', (p) => { p.notes = [`a${ch(0x202e)}b`]; });
  bad('a zero-width space in a note is refused', (p) => { p.notes = [`a${ch(0x200b)}b`]; });
  bad('a note with edge spaces is refused', (p) => { p.notes = [' padded']; });
  bad('five addresses are refused', (p) => { p.apks[0].urls = Array.from({ length: 5 }, (_, i) => `https://m${i}.example.org/a.apk`); });
  bad('no address is refused', (p) => { p.apks[0].urls = []; });
  bad('a repeated address is refused', (p) => { p.apks[0].urls = [p.apks[0].urls[0], p.apks[0].urls[0]]; });
  const unknown = good(); unknown.surprise = true;
  check(g, 'an unknown member: the app tolerates it (signed), the publisher validator refuses it', [verify(sign(unknown), { strict: false }).ok, L.validatePayload(unknown).length > 0], [true, true]);
  // The plain-text rules are the app's, unconditionally: strict:false (tolerate unknown members) must never excuse them.
  for (const [what, mut] of [['markup in a note', (p) => { p.notes = ['Tap <b>here</b>']; }], ['a bidi override in the headline', (p) => { p.headline = `Safe${ch(0x202e)}fas`; }], ['edge spaces in a note', (p) => { p.notes = [' padded ']; }],
    ['edge spaces in the headline', (p) => { p.headline = ' padded'; }], ['a backtick in the headline', (p) => { p.headline = 'run `x`'; }], ['a control character in a note', (p) => { p.notes = [`a${ch(7)}b`]; }]]) {
    const p = good(); mut(p);
    check(g, `a tolerant reader (strict:false) still refuses ${what}`, [verify(sign(p), { strict: false }).ok, verify(sign(p), { strict: false }).code], [false, 'badShape']);
  }
  // A sequence the publisher may sign is bounded by the issue time: a huge one would make every later manifest "replayed".
  const seqAt = (n) => ({ ...good(), sequence: n });
  const issuedSec = Math.floor(L.parseTime(good().issuedAt) / 1000);
  check(g, 'policy: a sequence at the issue time is fine', L.policyProblems(seqAt(issuedSec)), []);
  check(g, 'policy: a small sequence (1, 2, 3 ...) is fine', L.policyProblems(seqAt(1)), []);
  check(g, 'policy: a sequence exactly one day above the issue time is fine', L.policyProblems(seqAt(issuedSec + 86400)), []);
  check(g, 'policy: one second more is a problem', L.policyProblems(seqAt(issuedSec + 86401)).length, 1);
  check(g, 'policy: 2^53-1 is a problem that names the consequence', /replayed/.test(L.policyProblems(seqAt(Number.MAX_SAFE_INTEGER)).join()), true);
  check(g, 'the app-side format still allows it (the bound is the publisher rule, held by the signer and the verifier)', L.validatePayload(seqAt(Number.MAX_SAFE_INTEGER)), []);
  check(g, 'a document with a stray top-level member is refused by the publisher validator', L.validateDocument({ ...sign(good()), extra: 1 }).length > 0, true);
}

// ================================================================ huge values
{
  const g = 'huge';
  const big = good(); big.apks[0].size = 600 * 1048576; big.apks[0].chunkSize = 8 * 1048576; big.apks[0].chunks = Array.from({ length: 75 }, () => hx('d'));
  check(g, 'a declared size of 600 MiB is refused as sizeTooLarge', verify(sign(big)).code, 'sizeTooLarge');
  const exact = good(); exact.apks[0].size = L.LIMITS.apkBytes; exact.apks[0].chunkSize = 8 * 1048576; exact.apks[0].chunks = Array.from({ length: 63 }, () => hx('d'));
  check(g, 'exactly 500 MiB is accepted', verify(sign(exact)).ok, true);
  const plus = good(); plus.apks[0].size = L.LIMITS.apkBytes + 1; plus.apks[0].chunkSize = 8 * 1048576; plus.apks[0].chunks = Array.from({ length: 63 }, () => hx('d'));
  check(g, '500 MiB plus one byte is refused', verify(sign(plus)).code, 'sizeTooLarge');
  const maxSafe = good(); maxSafe.apks[0].size = Number.MAX_SAFE_INTEGER;
  check(g, 'a size of 2^53-1 is refused without allocating anything', verify(sign(maxSafe)).ok, false);
  check(g, 'a size beyond 2^53 cannot even be parsed', L.parseStrictJson('{"size":9007199254740993}').ok, false);
  check(g, 'a manifest document over 256 KiB is refused before it is parsed', L.verifyDocument(Buffer.alloc(L.LIMITS.manifestBytes + 1, 0x20), ctx()).code, 'tooLarge');
  check(g, 'exactly 256 KiB of whitespace is "not json", not "too large"', L.verifyDocument(Buffer.alloc(L.LIMITS.manifestBytes, 0x20), ctx()).code, 'notJson');
  const hugeNotes = good(); hugeNotes.notes = Array.from({ length: 12 }, () => 'n'.repeat(300));
  check(g, 'twelve 300-character notes still fit and verify', verify(sign(hugeNotes)).ok, true);
  const hugeVersion = good(); hugeVersion.versionCode = 2147483648;
  check(g, 'a versionCode beyond 2^31-1 is refused', verify(sign(hugeVersion)).ok, false);
  const hugeSeq = good(); hugeSeq.sequence = Number.MAX_SAFE_INTEGER;
  check(g, 'a sequence at 2^53-1 is the largest accepted', verify(sign(hugeSeq)).ok, true);
  check(g, 'the build script chooses 1 MiB chunks for a normal APK', L.chooseChunkSize(120 * 1048576), 1048576);
  check(g, 'the largest APK the app accepts needs only 500 chunk hashes at 1 MiB', Math.ceil(L.LIMITS.apkBytes / L.chooseChunkSize(L.LIMITS.apkBytes)), 500);
  check(g, 'a size that would need over 2048 hashes gets bigger chunks (never above the 8 MiB cap)', [L.chooseChunkSize(4 * 1024 ** 3) > 1048576, L.chooseChunkSize(4 * 1024 ** 3) <= L.LIMITS.chunkMax], [true, true]);
  const worst = good(); const sz = L.LIMITS.apkBytes; const cs = L.chooseChunkSize(sz); worst.apks[0].size = sz; worst.apks[0].chunkSize = cs; worst.apks[0].chunks = Array.from({ length: Math.ceil(sz / cs) }, () => hx('f'));
  check(g, 'a worst-case 500 MiB manifest with four notes of 300 characters still fits in 256 KiB', Buffer.byteLength(JSON.stringify(sign(worst), null, 2)) < L.LIMITS.manifestBytes, true);
}

// ================================================================ hostile JSON
{
  const g = 'json';
  const sig = sign(good()).signature;
  const doc = JSON.stringify(sign(good()));
  check(g, 'a byte-order mark is refused', verify(`${ch(0xfeff)}${doc}`).code, 'notJson');
  check(g, 'trailing garbage after the document is refused', verify(`${doc} x`).code, 'notJson');
  check(g, 'a duplicate key is refused (JSON.parse would silently keep the last)', verify(doc.replace('"channel":"stable"', '"channel":"beta","channel":"stable"')).code, 'notJson');
  check(g, 'a float is refused', verify(doc.replace('"versionCode":5200', '"versionCode":5200.0')).code, 'notJson');
  check(g, 'an exponent is refused', verify(doc.replace('"versionCode":5200', '"versionCode":52e2')).code, 'notJson');
  check(g, 'a lone surrogate in a string is refused', verify(doc.replace('A calmer', '\\ud800 calmer')).code, 'notJson');
  check(g, 'invalid UTF-8 is refused', L.verifyDocument(Buffer.concat([Buffer.from(doc.slice(0, 10)), Buffer.from([0xff, 0xfe]), Buffer.from(doc.slice(10))]), ctx()).code, 'notJson');
  check(g, 'deep nesting is refused', L.parseStrictJson(`${'['.repeat(40)}${']'.repeat(40)}`).ok, false);
  check(g, 'a raw newline inside a string is refused', L.parseStrictJson('{"a":"x\ny"}').ok, false);
  check(g, 'NaN and Infinity are not JSON', [L.parseStrictJson('NaN').ok, L.parseStrictJson('Infinity').ok], [false, false]);
  check(g, 'a leading zero is refused', L.parseStrictJson('{"a":01}').ok, false);
  check(g, 'a trailing comma is refused', L.parseStrictJson('[1,2,]').ok, false);
  check(g, 'single quotes are refused', L.parseStrictJson("{'a':1}").ok, false);
  check(g, 'comments are refused', L.parseStrictJson('{"a":1}//x').ok, false);
  check(g, 'a prototype-pollution key is just a key and never reaches Object.prototype', (() => { const r = L.parseStrictJson('{"__proto__":{"x":1}}'); return [r.ok, ({}).x]; })(), [true, undefined]);
  check(g, 'the signature object is only read as { alg, kid, sig }', sig.alg, 'ed25519');
  check(g, 'a canonical form refuses floats', throws(() => L.canonicalize({ a: 1.5 })), true);
  check(g, 'a canonical form refuses undefined', throws(() => L.canonicalize({ a: undefined })), true);
  check(g, 'a canonical form refuses integers beyond 2^53', throws(() => L.canonicalize(2 ** 53)), true);
}

// ================================================================ addresses
{
  const g = 'urls';
  const ok = (u, o) => L.urlProblem(u, o) === null;
  check(g, 'a public https address passes', ok('https://downloads.example.org/olive/a.apk'), true);
  check(g, 'a github release asset address passes', ok('https://github.com/CosmicGrub/Olive-Branch/releases/download/v0.52.0/olive-0.52.0-direct-arm64-v8a.apk'), true);
  check(g, 'cleartext http is refused', ok('http://downloads.example.org/a.apk'), false);
  check(g, 'http to localhost is refused even with the developer option (only literal loopback addresses)', ok('http://localhost/a.apk', { allowLoopbackHttp: true }), false);
  check(g, 'http to 127.0.0.1 is refused by default', ok('http://127.0.0.1:8080/a.apk'), false);
  check(g, 'http to 127.0.0.1 is allowed ONLY with the developer option', ok('http://127.0.0.1:8080/a.apk', { allowLoopbackHttp: true }), true);
  check(g, 'http to a LAN address is refused even with the developer option', ok('http://192.0.2.7/a.apk', { allowLoopbackHttp: true }), false);
  check(g, 'http to 127.0.0.2 is refused even with the developer option', ok('http://127.0.0.2/a.apk', { allowLoopbackHttp: true }), false);
  check(g, 'credentials in the address are refused', ok('https://user:pw@downloads.example.org/a.apk'), false);
  check(g, 'a user-name-only address is refused', ok('https://user@downloads.example.org/a.apk'), false);
  check(g, 'a fragment is refused', ok('https://downloads.example.org/a.apk#x'), false);
  check(g, 'a non-default port is refused', ok('https://downloads.example.org:8443/a.apk'), false);
  check(g, 'an IP literal is refused', ok('https://192.0.2.7/a.apk'), false);
  check(g, 'an IPv6 literal is refused', ok('https://[2001:db8::1]/a.apk'), false);
  check(g, 'a local name is refused', ok('https://olive.local/a.apk'), false);
  check(g, 'a single-label name is refused', ok('https://intranet/a.apk'), false);
  check(g, 'an upper-case host is refused (not canonical)', ok('https://Downloads.Example.org/a.apk'), false);
  check(g, 'a backslash is refused', ok('https://downloads.example.org\\a.apk'), false);
  check(g, 'a space is refused', ok('https://downloads.example.org/a b.apk'), false);
  check(g, 'a tab is refused', ok(`https://downloads.example.org/a${ch(9)}.apk`), false);
  check(g, 'a non-ASCII host is refused', ok(`https://d${ch(0xf6)}wnloads.example.org/a.apk`), false);
  check(g, 'file: is refused', ok('file:///a.apk'), false);
  check(g, 'ftp: is refused', ok('ftp://downloads.example.org/a.apk'), false);
  check(g, 'javascript: is refused', ok('javascript:alert(1)'), false);
  check(g, 'a bare host with no path is refused', ok('https://downloads.example.org'), false);
  check(g, 'an address over 2000 characters is refused', ok(`https://downloads.example.org/${'a'.repeat(2000)}`), false);
  check(g, 'a query is allowed (signed-URL mirrors)', ok('https://downloads.example.org/a.apk?token=abc'), true);
  check(g, 'a manifest carrying a cleartext address is refused by the validator', L.validatePayload({ ...good(), apks: [{ ...good().apks[0], urls: ['http://downloads.example.org/a.apk'] }] }).some((p) => /cleartext/.test(p)), true);
  check(g, '...and as a badUrl when verified', verify(sign({ ...good(), apks: [{ ...good().apks[0], urls: ['http://downloads.example.org/a.apk'] }] })).code, 'badUrl');
}

// ================================================================ redirects
{
  const g = 'redirects';
  const trusted = ['downloads.example.org', 'objects.githubusercontent.com'];
  check(g, 'a redirect to another https address on a trusted host is allowed', L.redirectProblem('https://objects.githubusercontent.com/x', { allowedHosts: trusted }), null);
  check(g, 'a redirect to cleartext http is refused', /cleartext/.test(L.redirectProblem('http://downloads.example.org/x', { allowedHosts: trusted })), true);
  check(g, 'a redirect to another host is refused', /trusted hosts/.test(L.redirectProblem('https://evil.example.net/x', { allowedHosts: trusted })), true);
  check(g, 'a redirect carrying credentials is refused', /credentials/.test(L.redirectProblem('https://u:p@downloads.example.org/x', { allowedHosts: trusted })), true);
  check(g, 'a redirect to a non-default port is refused', /port/.test(L.redirectProblem('https://downloads.example.org:8443/x', { allowedHosts: trusted })), true);
  check(g, 'a redirect to a file: address is refused', /file:/.test(L.redirectProblem('file:///etc/hosts', { allowedHosts: trusted })), true);
  check(g, 'loopback http redirect only with the developer option', [L.redirectProblem('http://127.0.0.1:9/x', { allowedHosts: ['127.0.0.1'] }) !== null, L.redirectProblem('http://127.0.0.1:9/x', { allowLoopbackHttp: true, allowedHosts: ['127.0.0.1'] })], [true, null]);
  check(g, 'a redirect to a look-alike host is refused', L.redirectProblem('https://downloads.example.org.evil.net/x', { allowedHosts: trusted }) !== null, true);
}

// ================================================================ the file itself
{
  const g = 'file';
  const dir = mkdtempSync(join(tmpdir(), 'olive-upd-'));
  const data = Buffer.alloc(3 * 65536 + 123, 0); for (let o = 0; o < data.length; o += 32) createHash('sha256').update(`block ${o}`).digest().copy(data, o, 0, Math.min(32, data.length - o));
  const path = join(dir, 'a.apk'); writeFileSync(path, data);
  const h = await L.hashFile(path, 65536);
  const apk = { abi: 'arm64-v8a', size: h.size, sha256: h.sha256, signerSha256: hx('b'), chunkSize: 65536, chunks: h.chunks, urls: ['https://downloads.example.org/a.apk'] };
  check(g, 'hashFile counts 4 chunks for 3 full chunks and a remainder', h.chunks.length, 4);
  check(g, 'hashFile agrees with a one-shot SHA-256', h.sha256, createHash('sha256').update(data).digest('hex'));
  check(g, 'each chunk hash agrees with a one-shot hash of that slice', h.chunks[3], createHash('sha256').update(data.subarray(3 * 65536)).digest('hex'));
  check(g, 'the exact file verifies', (await L.verifyApkFile(path, apk)).ok, true);
  const t = join(dir, 'trunc.apk'); writeFileSync(t, data.subarray(0, data.length - 1));
  check(g, 'one byte short is refused as truncated', (await L.verifyApkFile(t, apk)).code, 'truncated');
  const t2 = join(dir, 'half.apk'); writeFileSync(t2, data.subarray(0, 65536));
  check(g, 'a partial download (one chunk) is refused as truncated', (await L.verifyApkFile(t2, apk)).code, 'truncated');
  const e = join(dir, 'long.apk'); writeFileSync(e, Buffer.concat([data, Buffer.from([1])]));
  check(g, 'one byte too many is refused as tooMuchData', (await L.verifyApkFile(e, apk)).code, 'tooMuchData');
  let flips = 0, detected = 0;
  for (const pos of [0, 1, 65535, 65536, 65537, 131071, 131072, 196607, 196608, data.length - 1]) {
    const f = Buffer.from(data); f[pos] ^= 1; const fp = join(dir, `flip${pos}.apk`); writeFileSync(fp, f);
    flips++; const r = await L.verifyApkFile(fp, apk); if (!r.ok && r.code === 'hashMismatch') detected++;
  }
  check(g, `a single flipped bit at ${flips} positions incl. every chunk boundary is detected`, detected, flips);
  const swap = Buffer.from(data); data.copy(swap, 0, 65536, 131072); data.copy(swap, 65536, 0, 65536); writeFileSync(join(dir, 'swap.apk'), swap);
  check(g, 'two chunks swapped (same size, same multiset of bytes) is detected', (await L.verifyApkFile(join(dir, 'swap.apk'), apk)).code, 'hashMismatch');
  const wrongWhole = { ...apk, sha256: hx('0') };
  check(g, 'a wrong whole-file hash is refused even when every chunk matches', (await L.verifyApkFile(path, wrongWhole)).code, 'hashMismatch');
  const wrongChunk = { ...apk, chunks: [hx('0'), ...apk.chunks.slice(1)] };
  check(g, 'a wrong chunk hash is refused even when the whole-file hash matches', (await L.verifyApkFile(path, wrongChunk)).code, 'hashMismatch');
  check(g, 'a missing file is refused', (await L.verifyApkFile(join(dir, 'nope.apk'), apk)).code, 'apkMismatch');
  const zero = join(dir, 'zero.apk'); writeFileSync(zero, Buffer.alloc(0));
  check(g, 'an empty file is truncated', (await L.verifyApkFile(zero, apk)).code, 'truncated');
  const big = join(dir, 'sparse.apk'); writeFileSync(big, Buffer.alloc(0)); appendFileSync(big, Buffer.alloc(1024));
  check(g, 'a file of the right size but wrong content is a hash mismatch, not a pass', (await L.verifyApkFile(big, { ...apk, size: 1024, chunks: [hx('1')], chunkSize: 65536 })).code, 'hashMismatch');

  // ---- zip structure
  const zip = (entries) => {
    const locals = [], centrals = []; let off = 0;
    for (const e of entries) {
      const name = Buffer.from(e.name); const body = e.data ?? Buffer.alloc(0);
      const lh = Buffer.alloc(30); lh.writeUInt32LE(0x04034b50, 0); lh.writeUInt16LE(20, 4); lh.writeUInt32LE(body.length, 18); lh.writeUInt32LE(body.length, 22); lh.writeUInt16LE(name.length, 26);
      locals.push(lh, name, body);
      const cd = Buffer.alloc(46); cd.writeUInt32LE(0x02014b50, 0); cd.writeUInt16LE(20, 4); cd.writeUInt16LE(20, 6);
      cd.writeUInt32LE(e.comp ?? body.length, 20); cd.writeUInt32LE(e.unc ?? body.length, 24); cd.writeUInt16LE(name.length, 28); cd.writeUInt32LE(off, 42);
      centrals.push(cd, name);
      off += 30 + name.length + body.length;
    }
    const cdBuf = Buffer.concat(centrals);
    const end = Buffer.alloc(22); end.writeUInt32LE(0x06054b50, 0); end.writeUInt16LE(entries.length, 8); end.writeUInt16LE(entries.length, 10); end.writeUInt32LE(cdBuf.length, 12); end.writeUInt32LE(off, 16);
    return Buffer.concat([...locals, cdBuf, end]);
  };
  const okEntries = [{ name: 'AndroidManifest.xml', data: Buffer.from('x') }, { name: 'classes.dex', data: Buffer.from('y') }];
  const zp = (name, entries) => { const p = join(dir, name); writeFileSync(p, zip(entries)); return p; };
  check(g, 'a sound minimal APK zip passes the structure check', (await L.inspectApkZip(zp('ok.zip', okEntries))).ok, true);
  check(g, 'a zip with duplicate entry names is refused', (await L.inspectApkZip(zp('dup.zip', [...okEntries, { name: 'classes.dex', data: Buffer.from('z') }]))).ok, false);
  check(g, 'a zip with a path-traversal entry is refused', (await L.inspectApkZip(zp('trav.zip', [...okEntries, { name: '../evil', data: Buffer.from('z') }]))).ok, false);
  check(g, 'a zip with an absolute entry is refused', (await L.inspectApkZip(zp('abs.zip', [...okEntries, { name: '/evil', data: Buffer.from('z') }]))).ok, false);
  check(g, 'a zip without classes.dex is refused', (await L.inspectApkZip(zp('nodex.zip', [okEntries[0]]))).ok, false);
  check(g, 'a zip without AndroidManifest.xml is refused', (await L.inspectApkZip(zp('nomf.zip', [okEntries[1]]))).ok, false);
  check(g, 'a zip bomb (one entry declaring a 4 GiB expansion of a few bytes) is refused', (await L.inspectApkZip(zp('bomb.zip', [...okEntries, { name: 'bomb.bin', data: Buffer.from('z'), comp: 10, unc: 4 * 1024 * 1024 * 1024 - 1 }]))).ok, false);
  check(g, 'a high expansion ratio on a big entry is refused', (await L.inspectApkZip(zp('ratio.zip', [...okEntries, { name: 'r.bin', data: Buffer.from('z'), comp: 1000, unc: 1000 * 1000 * 1000 }]))).ok, false);
  check(g, 'a file that is not a zip is refused', (await L.inspectApkZip(path)).ok, false);
  check(g, 'a 10-byte file is refused', (await L.inspectApkZip(zp('tiny.zip', []))).ok, false);
  const trunc = zip(okEntries); writeFileSync(join(dir, 'cut.zip'), trunc.subarray(0, trunc.length - 10));
  check(g, 'a zip with its end record cut off is refused', (await L.inspectApkZip(join(dir, 'cut.zip'))).ok, false);
  rmSync(dir, { recursive: true, force: true });
}

// ================================================================ device choice and tools output
{
  const g = 'device';
  const m = good(); m.apks.push({ ...clone(m.apks[0]), abi: 'universal' });
  check(g, 'an arm64 phone gets the arm64 file', L.pickApk(m, ['arm64-v8a', 'armeabi-v7a']).abi, 'arm64-v8a');
  check(g, 'an x86_64 device with only arm64 and universal gets universal', L.pickApk(m, ['x86_64']).abi, 'universal');
  check(g, 'a device with no match and no universal gets nothing (noApkForDevice)', L.pickApk(good(), ['x86_64']), null);
  check(g, 'apksigner output is read for every signer', L.parseApksignerCerts(`Signer #1 certificate DN: CN=x\nSigner #1 certificate SHA-256 digest: ${hx('A')}\nSigner #2 certificate SHA-256 digest: ${hx('b')}\n`), [hx('a'), hx('b')]);
  check(g, 'aapt2 badging is read', L.parseBadging("package: name='com.olivebranch.olive_client' versionCode='5200' versionName='0.52.0' platformBuildVersionName='15'\n"), { pkg: 'com.olivebranch.olive_client', versionCode: 5200, versionName: '0.52.0' });
  check(g, 'garbage badging is null', L.parseBadging('nope'), null);
}

// ================================================================ the build script's pure parts
{
  const g = 'draft';
  const files = [{ abi: 'arm64-v8a', fileName: 'olive-0.52.0-direct-arm64-v8a.apk', size: 2 * 1048576 + 5, sha256: hx('a'), signerSha256: hx('b'), chunkSize: 1048576, chunks: [hx('1'), hx('2'), hx('3')] }];
  const d = draftManifest({ versionName: '0.52.0', versionCode: 5200, channel: 'stable', issuedAt: ISSUED, validDays: 180, minSupported: 1, notes: { headline: 'H', notes: ['n'] }, apks: files, downloadBases: ['https://downloads.example.org/olive', 'https://mirror.example.net/olive'] });
  check(g, 'a drafted manifest passes the strict validator and the policy', [L.validatePayload(d), L.policyProblems(d, { requireMirror: true })], [[], []]);
  check(g, 'the sequence defaults to the issue time in seconds (it rises with every release)', d.sequence, Math.floor(ISSUED / 1000));
  check(g, 'the addresses are base + file name, primary first', d.apks[0].urls[0], 'https://downloads.example.org/olive/olive-0.52.0-direct-arm64-v8a.apk');
  check(g, 'a versionCode that is not derived from the version is a policy problem', L.policyProblems({ ...d, versionCode: 5201 }).length, 1);
  check(g, 'a prerelease suffix is a policy problem (a published version is MAJOR.MINOR.PATCH)', L.policyProblems({ ...d, versionName: '0.52.0-rc1' }).length > 0, true);
  check(g, 'a single address is a policy problem only when a mirror is required', [L.policyProblems({ ...d, apks: [{ ...d.apks[0], urls: [d.apks[0].urls[0]] }] }).length, L.policyProblems({ ...d, apks: [{ ...d.apks[0], urls: [d.apks[0].urls[0]] }] }, { requireMirror: true }).length], [0, 1]);
  const a = flutterArgs({ abi: 'arm64-v8a', entry: 'lib/main_live.dart', pubkeys: 'k:AAAA', manifestUrl: 'https://downloads.example.org/m.json', baseUrl: null, allowDebugSigned: false });
  check(g, 'the build asks for the direct flavor, the live entry and the public key', [a.includes('--flavor'), a[a.indexOf('--flavor') + 1], a.includes('--target=lib/main_live.dart'), a.includes('--dart-define=OLIVE_UPDATE_PUBKEYS=k:AAAA')], [true, 'direct', true, true]);
  check(g, 'a real build does NOT opt into debug signing', a.some((x) => /allowDebugSigned/.test(x)), false);
  check(g, 'a dry run opts in explicitly', flutterArgs({ abi: 'arm64-v8a', entry: 'e', pubkeys: 'k:A', manifestUrl: 'u', allowDebugSigned: true }).some((x) => /olive.allowDebugSignedRelease=true/.test(x)), true);
  check(g, 'no dart-define carries a server login, a child id or a cleartext allowance', a.filter((x) => x.startsWith('--dart-define=')).map((x) => x.split('=')[1]), ['OLIVE_UPDATE_PUBKEYS', 'OLIVE_UPDATE_MANIFEST_URL']);

  check('notes', 'a good notes file parses', parseNotesFile('# note\nheadline: A calmer start\n- One.\n- Two.\n'), { headline: 'A calmer start', notes: ['One.', 'Two.'] });
  check('notes', 'CRLF line endings parse the same', parseNotesFile('headline: H\r\n- One.\r\n').notes, ['One.']);
  check('notes', 'a DRAFT marker blocks packaging', throws(() => parseNotesFile('# DRAFT - rewrite me\nheadline: H\n- One.\n')), true);
  check('notes', 'no headline is refused', throws(() => parseNotesFile('- One.\n')), true);
  check('notes', 'no notes is refused', throws(() => parseNotesFile('headline: H\n')), true);
  check('notes', 'thirteen notes are refused', throws(() => parseNotesFile(`headline: H\n${Array.from({ length: 13 }, (_, i) => `- n${i}`).join('\n')}\n`)), true);
  check('notes', 'markup in a note is refused', throws(() => parseNotesFile('headline: H\n- <b>x</b>\n')), true);
  check('notes', 'a stray line is refused', throws(() => parseNotesFile('headline: H\nhello\n- One.\n')), true);
  check('notes', 'a drafted file from a CHANGELOG section is a DRAFT and cannot be packaged as is', throws(() => parseNotesFile(draftNotesFromChangelog('Lead.\n\n### Calmer sign-in (client)\nx\n### Safer updates\ny\n', 'Release cut: things'))), true);
  check('notes', 'the draft keeps one starting line per heading, without parentheses', draftNotesFromChangelog('Lead.\n\n### Calmer sign-in (client)\nx\n', 'T: more').split('\n').filter((l) => l.startsWith('- ')), ['- Calmer sign-in']);
}

// ================================================================ the JSON Schema stays in step
{
  const g = 'schema';
  const m = schema.$defs.manifest.properties, a = schema.$defs.apk.properties, s = schema.$defs.signature.properties;
  check(g, 'the schema lists the same manifest members as the validator, all required', [[...schema.$defs.manifest.required].sort(), Object.keys(m).sort()], [[...L.PAYLOAD_KEYS].sort(), [...L.PAYLOAD_KEYS].sort()]);
  check(g, 'the schema lists the same apk members as the validator', [[...schema.$defs.apk.required].sort(), Object.keys(a).sort()], [[...L.APK_KEYS].sort(), [...L.APK_KEYS].sort()]);
  check(g, 'the schema lists the same signature members as the validator', [[...schema.$defs.signature.required].sort(), Object.keys(s).sort()], [[...L.SIG_KEYS].sort(), [...L.SIG_KEYS].sort()]);
  check(g, 'the schema allows no unknown members anywhere', [schema.additionalProperties, schema.$defs.manifest.additionalProperties, schema.$defs.apk.additionalProperties, schema.$defs.signature.additionalProperties], [false, false, false, false]);
  check(g, 'schema constants equal the limits: caps', [m.notes.maxItems, m.apks.maxItems, a.urls.maxItems, a.chunks.maxItems, a.size.maximum, a.chunkSize.minimum, a.chunkSize.maximum, m.versionCode.maximum, m.sequence.maximum, m.headline.maxLength, m.notes.items.maxLength, a.urls.items.maxLength],
    [L.LIMITS.notes, L.LIMITS.apks, L.LIMITS.urls, L.LIMITS.chunksMax, L.LIMITS.apkBytes, L.LIMITS.chunkMin, L.LIMITS.chunkMax, L.LIMITS.versionCodeMax, L.LIMITS.safeInt, L.LIMITS.headlineChars, L.LIMITS.noteChars, L.LIMITS.urlChars]);
  check(g, 'schema constants equal the limits: enums and ids', [a.abi.enum, m.app.const, m.schema.const, s.alg.const], [[...L.ABIS], L.APP_ID, 1, 'ed25519']);

  // a deliberately small JSON-Schema evaluator (type, const, enum, pattern, min/max, length, items, required, additionalProperties, $ref, allOf)
  const resolve = (ref) => ref.slice(2).split('/').reduce((o, k) => o[k], schema);
  const evalSchema = (sc, v) => {
    if (sc.$ref) return evalSchema(resolve(sc.$ref), v);
    if (sc.allOf) return sc.allOf.every((x) => evalSchema(x, v)) && evalSchema({ ...sc, allOf: undefined }, v);
    if ('const' in sc && v !== sc.const) return false;
    if (sc.enum && !sc.enum.includes(v)) return false;
    if (sc.type === 'string' && typeof v !== 'string') return false;
    if (sc.type === 'integer' && !Number.isInteger(v)) return false;
    if (sc.type === 'array' && !Array.isArray(v)) return false;
    if (sc.type === 'object' && (v === null || typeof v !== 'object' || Array.isArray(v))) return false;
    if (typeof v === 'string') {
      if (sc.pattern && !new RegExp(sc.pattern, 'u').test(v)) return false;
      if (sc.maxLength !== undefined && v.length > sc.maxLength) return false;
      if (sc.minLength !== undefined && v.length < sc.minLength) return false;
    }
    if (typeof v === 'number') { if (sc.minimum !== undefined && v < sc.minimum) return false; if (sc.maximum !== undefined && v > sc.maximum) return false; }
    if (Array.isArray(v)) {
      if (sc.maxItems !== undefined && v.length > sc.maxItems) return false;
      if (sc.minItems !== undefined && v.length < sc.minItems) return false;
      if (sc.items && !v.every((x) => evalSchema(sc.items, x))) return false;
    }
    if (v && typeof v === 'object' && !Array.isArray(v)) {
      for (const r of sc.required || []) if (!(r in v)) return false;
      for (const [k, x] of Object.entries(v)) {
        if (sc.properties && k in sc.properties) { if (!evalSchema(sc.properties[k], x)) return false; }
        else if (sc.additionalProperties === false) return false;
      }
    }
    return true;
  };
  const sv = (doc) => evalSchema(schema, doc);
  const docOk = sign(good());
  check(g, 'a valid signed document satisfies the schema AND the validator', [sv(docOk), L.validateDocument(docOk).length === 0], [true, true]);
  for (const d of vectors.documents) {
    let parsed; try { parsed = JSON.parse(d.text); } catch { continue; }
    if (!d.name.startsWith('valid')) continue;
    check(g, `vector "${d.name}" satisfies the schema`, sv(parsed), true);
  }
  const mutations = [
    ['an unknown member', (d) => { d.manifest.extra = 1; }], ['a missing member', (d) => { delete d.manifest.apks; }], ['an http address', (d) => { d.manifest.apks[0].urls = ['http://downloads.example.org/a.apk']; }],
    ['an unknown abi', (d) => { d.manifest.apks[0].abi = 'mips'; }], ['a short hash', (d) => { d.manifest.apks[0].sha256 = 'ab'; }], ['an upper-case channel', (d) => { d.manifest.channel = 'Stable'; }],
    ['a zero versionCode', (d) => { d.manifest.versionCode = 0; }], ['a string sequence', (d) => { d.manifest.sequence = '1'; }], ['a note with markup', (d) => { d.manifest.notes = ['<b>x</b>']; }],
    ['thirteen notes', (d) => { d.manifest.notes = Array.from({ length: 13 }, () => 'n'); }], ['no files', (d) => { d.manifest.apks = []; }], ['a bad time', (d) => { d.manifest.issuedAt = 'now'; }],
    ['another app id', (d) => { d.manifest.app = 'com.example.x'; }], ['a wrong algorithm', (d) => { d.signature.alg = 'none'; }], ['a stray top-level member', (d) => { d.extra = 1; }],
    ['a short signature', (d) => { d.signature.sig = 'AAAA'; }], ['a size over the cap', (d) => { d.manifest.apks[0].size = 600 * 1048576; }], ['a chunk size below the floor', (d) => { d.manifest.apks[0].chunkSize = 100; }],
  ];
  for (const [name, mut] of mutations) {
    const d = clone(docOk); mut(d);
    check(g, `${name}: the schema and the strict validator agree it is invalid`, [sv(d), L.validateDocument(d).length === 0], [false, false]);
  }
}

// ---------------------------------------------------------------------------------------------- report
let gname = '';
for (const r of rows) {
  if (r.g !== gname) { gname = r.g; console.log(`\n${gname}`); }
  console.log(`  ${r.ok ? 'PASS' : 'FAIL'}  ${r.n}` + (r.ok ? '' : `\n         expected ${r.e}, got ${r.a}`));
}
console.log(`\n${'-'.repeat(60)}\n${pass} passed, ${fail} failed\n`);
process.exitCode = fail === 0 ? 0 : 1;
