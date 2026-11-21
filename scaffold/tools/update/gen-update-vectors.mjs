#!/usr/bin/env node
/**
 * OLIVE BRANCH - regenerate tools/update/test-vectors.json, the shared truth for the signed update manifest.
 *
 *   node tools/update/gen-update-vectors.mjs > tools/update/test-vectors.json
 *
 * The file is consumed by tools/test/update_manifest.test.mjs (Node) and is meant to be consumed by the Dart client's test
 * (client/test/update_manifest_test.dart) so the two implementations are proved byte for byte against ONE set of documents:
 * canonical forms, signatures that verify, and a labelled set of documents each of which must be accepted or refused with
 * a named code.
 *
 * It makes TWO FRESH throwaway Ed25519 keys on every run and discards both private keys when the process ends. Only the public
 * entries and the signatures are written, so the committed file holds no secret and cannot be used to sign anything; and a
 * regeneration changes every signature (so do it only when the format changes, and tell the client lane).
 * It is not the release key and has nothing to do with it.
 */
import { generateKeyPairSync } from 'node:crypto';
import {
  APP_ID, SIGN_DOMAIN, canonicalize, formatTime, kidOf, rawPublicKey, signPayload, signingBytes, trustEntry,
} from './manifest_lib.mjs';

const ch = (n) => String.fromCharCode(n);
const key = () => {
  const { privateKey, publicKey } = generateKeyPairSync('ed25519');
  const raw = rawPublicKey(publicKey);
  const kid = kidOf(raw);
  return { privateKey, kid, trust: trustEntry(kid, raw) };
};
const trusted = key();
const stranger = key();

const NOW = Date.UTC(2026, 11, 1, 0, 0, 0);
const ISSUED = Date.UTC(2026, 10, 21, 10, 0, 0);
const h = (c) => c.repeat(64);

const base = {
  schema: 1,
  app: APP_ID,
  channel: 'stable',
  versionName: '0.52.0',
  versionCode: 5200,
  minSupportedVersionCode: 5100,
  sequence: 1795255200,
  issuedAt: formatTime(ISSUED),
  expiresAt: formatTime(ISSUED + 180 * 86400000),
  publishedAt: formatTime(ISSUED),
  headline: 'A calmer first run',
  notes: ['The first screen now explains who it is for.', 'Fewer taps to reach a saved message.'],
  apks: [{
    abi: 'arm64-v8a',
    size: 3 * 1048576 + 17,
    sha256: h('a'),
    signerSha256: h('b'),
    chunkSize: 1048576,
    chunks: [h('1'), h('2'), h('3'), h('4')],
    urls: ['https://downloads.example.org/olive/olive-0.52.0-direct-arm64-v8a.apk', 'https://mirror.example.net/olive/olive-0.52.0-direct-arm64-v8a.apk'],
  }],
};
const clone = (o) => JSON.parse(JSON.stringify(o));
const mutate = (fn) => { const o = clone(base); fn(o); return o; };
const signed = (payload, k = trusted) => signPayload(payload, k.privateKey, k.kid);
const text = (doc) => `${JSON.stringify(doc, null, 2)}\n`;

const ctx = (extra = {}) => ({ channel: 'stable', installedVersionCode: 5100, highestSeenSequence: null, nowIso: formatTime(NOW), ...extra });

const docs = [];
const add = (name, doc, expect, c = ctx(), note = '') => docs.push({ name, note, ctx: c, text: typeof doc === 'string' ? doc : text(doc), expect });

add('valid: a newer version', signed(base), { ok: true, status: 'update' });
add('valid: the same version is up to date', signed(base), { ok: true, status: 'up-to-date' }, ctx({ installedVersionCode: 5200 }));
add('valid: below the minimum supported version', signed(base), { ok: true, status: 'update', belowMinimum: true }, ctx({ installedVersionCode: 5000 }), 'a valid update; adults would also see "Please update"');
add('valid: a mirror-less single address is still a valid manifest', signed(mutate((o) => { o.apks[0].urls = [o.apks[0].urls[0]]; })), { ok: true, status: 'update' });
add('valid: an empty headline is allowed', signed(mutate((o) => { o.headline = ''; })), { ok: true, status: 'update' });

const tamperedVersion = clone(signed(base)); tamperedVersion.manifest.versionCode = 5300;
add('tampered: versionCode changed after signing', tamperedVersion, { ok: false, code: 'badSignature' });
const tamperedUrl = clone(signed(base)); tamperedUrl.manifest.apks[0].urls[0] = 'https://evil.example.org/olive.apk';
add('tampered: an address changed after signing', tamperedUrl, { ok: false, code: 'badSignature' });
const tamperedHash = clone(signed(base)); tamperedHash.manifest.apks[0].sha256 = h('c');
add('tampered: the file hash changed after signing', tamperedHash, { ok: false, code: 'badSignature' });
const tamperedNotes = clone(signed(base)); tamperedNotes.manifest.notes[0] = 'Please send your PIN to the address below.';
add('tampered: the release notes changed after signing', tamperedNotes, { ok: false, code: 'badSignature' });
const flippedSig = clone(signed(base)); flippedSig.signature.sig = (flippedSig.signature.sig[0] === 'A' ? 'B' : 'A') + flippedSig.signature.sig.slice(1);
add('tampered: one character of the signature changed', flippedSig, { ok: false, code: 'badSignature' });
add('wrong key: signed by a key the app does not hold', signed(base, stranger), { ok: false, code: 'unknownKey' });
const lyingKid = clone(signed(base, stranger)); lyingKid.signature.kid = trusted.kid;
add('wrong key: signed by another key but naming the trusted key id', lyingKid, { ok: false, code: 'badSignature' });
const algNone = clone(signed(base)); algNone.signature.alg = 'none';
add('wrong algorithm: alg is not ed25519', algNone, { ok: false, code: 'badSignature' });
add('rollback: a signed manifest older than the installed version', signed(mutate((o) => { o.versionCode = 5000; o.versionName = '0.50.0'; o.minSupportedVersionCode = 5000; })), { ok: false, code: 'rollback' });
add('replay: an older sequence than one already accepted', signed(base), { ok: false, code: 'replayed' }, ctx({ highestSeenSequence: base.sequence + 1 }));
add('wrong channel: signed for beta, the app follows stable', signed(mutate((o) => { o.channel = 'beta'; })), { ok: false, code: 'wrongChannel' });
add('wrong app: signed for another application id', signed(mutate((o) => { o.app = 'com.example.other'; })), { ok: false, code: 'wrongApp' });
add('expired: past expiresAt', signed(base), { ok: false, code: 'expired' }, ctx({ nowIso: formatTime(ISSUED + 181 * 86400000) }));
add('not yet valid: issued in the future', signed(mutate((o) => { o.issuedAt = formatTime(NOW + 3 * 86400000); o.publishedAt = o.issuedAt; o.expiresAt = formatTime(NOW + 100 * 86400000); })), { ok: false, code: 'notYetValid' });
add('missing field: versionCode removed (and re-signed)', signed(mutate((o) => { delete o.versionCode; })), { ok: false, code: 'badShape' });
add('missing field: apks removed (and re-signed)', signed(mutate((o) => { delete o.apks; })), { ok: false, code: 'badShape' });
add('missing field: the signed object is not an object', `${JSON.stringify({ manifest: 'x', signature: signed(base).signature })}\n`, { ok: false, code: 'badShape' });
add('shape: minSupportedVersionCode above versionCode', signed(mutate((o) => { o.minSupportedVersionCode = 9999; })), { ok: false, code: 'badShape' });
add('shape: the chunk list does not match the size', signed(mutate((o) => { o.apks[0].chunks.pop(); })), { ok: false, code: 'badShape' });
add('shape: a chunk hash is not 64 hex digits', signed(mutate((o) => { o.apks[0].chunks[1] = 'zz'; })), { ok: false, code: 'badShape' });
add('shape: two files for one abi', signed(mutate((o) => { o.apks.push(clone(o.apks[0])); })), { ok: false, code: 'badShape' });
add('shape: an unknown abi', signed(mutate((o) => { o.apks[0].abi = 'mips'; })), { ok: false, code: 'badShape' });
add('shape: expiry before issue', signed(mutate((o) => { o.expiresAt = formatTime(ISSUED - 1000); })), { ok: false, code: 'badShape' });
add('shape: validity longer than 400 days', signed(mutate((o) => { o.expiresAt = formatTime(ISSUED + 401 * 86400000); })), { ok: false, code: 'badShape' });
add('huge: a declared size far beyond the cap', signed(mutate((o) => { o.apks[0].size = 600 * 1048576; o.apks[0].chunkSize = 8 * 1048576; o.apks[0].chunks = Array.from({ length: 75 }, () => h('d')); })), { ok: false, code: 'sizeTooLarge' });
add('huge: more than four addresses', signed(mutate((o) => { o.apks[0].urls = Array.from({ length: 5 }, (_, i) => `https://m${i}.example.org/olive/a.apk`); })), { ok: false, code: 'badShape' });
add('huge: more than twelve notes', signed(mutate((o) => { o.notes = Array.from({ length: 13 }, (_, i) => `Note ${i}`); })), { ok: false, code: 'badShape' });
add('plain text: a note with markup is refused even by a tolerant reader', signed(mutate((o) => { o.notes[0] = 'Tap <b>here</b> to continue.'; })), { ok: false, code: 'badShape' });
add('plain text: a headline with a bidirectional override is refused', signed(mutate((o) => { o.headline = `Safe${ch(0x202e)}fas`; })), { ok: false, code: 'badShape' });
add('plain text: a note with edge spaces is refused', signed(mutate((o) => { o.notes[1] = ' padded '; })), { ok: false, code: 'badShape' });
add('plain text: a note with a backtick is refused', signed(mutate((o) => { o.notes[0] = 'Run `this` now.'; })), { ok: false, code: 'badShape' });
add('not json', 'this is not json', { ok: false, code: 'notJson' });
add('not json: an array', '[]', { ok: false, code: 'notJson' });

const canonCases = [
  ['sorted keys, no whitespace', '{"b":1,"a":[true,false,null,-7],"c":{"z":"x","y":""}}'],
  ['keys sort by UTF-16 code unit, not by code point', JSON.stringify({ [ch(0xff5e)]: 1, [String.fromCodePoint(0x1f600)]: 2, z: 3, [ch(0xe9)]: 4 })],
  ['control characters are \\u00xx, lower-case, never \\n', JSON.stringify(`a${ch(0)}${ch(9)}${ch(10)}${ch(13)}${ch(31)}b`)],
  ['quote and backslash are escaped, slash and DEL are not', JSON.stringify(`q"b\\s/${ch(127)}`)],
  ['non-ASCII is written as itself', JSON.stringify(`${ch(0xe9)}${String.fromCodePoint(0x1f600)}${ch(0x2028)}`)],
  ['integers at the edge', '[0,-1,9007199254740991,-9007199254740991]'],
  ['nested', '{"x":[{"b":[],"a":{}},[[]]]}'],
];

const out = {
  description: 'Shared test vectors for the Olive Branch signed update manifest (docs/UPDATE-MANIFEST.md). Regenerate only with tools/update/gen-update-vectors.mjs; the keys behind it were discarded.',
  vectorsFormat: 1,
  signDomain: SIGN_DOMAIN,
  now: formatTime(NOW),
  trust: trusted.trust,
  strangerTrust: stranger.trust,
  canonical: canonCases.map(([name, json]) => ({ name, json, canonical: canonicalize(JSON.parse(json)), signingBytesHex: signingBytes(JSON.parse(json)).toString('hex') })),
  documents: docs,
};
process.stdout.write(`${JSON.stringify(out, null, 2)}\n`);
