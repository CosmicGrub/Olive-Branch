// Reference (Node) implementation of the PAKE the pairing protocol uses: CPace as specified in
// draft-irtf-cfrg-cpace-21 for the suite CPACE-X25519-SHA512 (group G_X25519 with the Elligator2 generator
// map from RFC 9380, hash SHA-512), run in the initiator/responder setting. In Olive the CHILD device is the
// initiator ("A" in the draft) and the ADULT device is the responder ("B").
//
// CONFORMANCE. client/test/vectors/cpace_draft21_vectors.json holds appendix B.1 of the draft (B.1.1 to B.1.7
// and B.1.10), copied from the draft text; tools/test/cpace_draft21.test.mjs checks this file against it byte
// for byte, and client/test/cpace_draft21_test.dart checks the Dart port (client/lib/cpace.dart) against the
// SAME file. The two implementations were written separately, so agreement between them is also a cross-check.
//
// WHAT IS NOT THE DRAFT. Key confirmation tags, the short authentication string and the channel key
// (confirmTag, sasBytes, matchBytes, channelKey below) are Olive's own layer on top of ISK and are NOT part of
// CPace. They are kept separate on purpose, below the "Olive layer" line. The draft does not define them.
//
// NOT CONSTANT TIME. This is a test reference (BigInt arithmetic, OpenSSL for X25519). The shipped Dart port
// has its own note on that in cpace.dart. Nothing on a device runs this file.
import { createHash, createHmac, createPrivateKey, createPublicKey, diffieHellman } from 'node:crypto';

export const DSI = 'CPace255'; // G_X25519.DSI
export const S_IN_BYTES = 128; // SHA-512 input block size
const P = (1n << 255n) - 19n;
const A = 486662n;

const mod = (a) => ((a % P) + P) % P;
const pow = (b, e) => { let r = 1n; b = mod(b); while (e > 0n) { if (e & 1n) r = mod(r * b); b = mod(b * b); e >>= 1n; } return r; };
const inv = (a) => pow(a, P - 2n);
const leToBig = (buf) => { let r = 0n; for (let i = buf.length - 1; i >= 0; i--) r = (r << 8n) | BigInt(buf[i]); return r; };
const bigToLe32 = (n) => { const o = Buffer.alloc(32); for (let i = 0; i < 32; i++) { o[i] = Number(n & 255n); n >>= 8n; } return o; };

/** prepend_len: LEB128 length, then the bytes. */
export const lv = (b) => {
  b = Buffer.from(b);
  const len = []; let n = b.length;
  do { let byte = n & 0x7f; n >>= 7; if (n) byte |= 0x80; len.push(byte); } while (n);
  return Buffer.concat([Buffer.from(len), b]);
};
/** lv_cat(a0, a1, ...) */
export const lvCat = (...parts) => Buffer.concat(parts.map(lv));
export const sha512 = (...p) => createHash('sha512').update(Buffer.concat(p.map((x) => Buffer.from(x)))).digest();

/** decodeUCoordinate (RFC 7748): 32 bytes little endian with bit 255 cleared. */
export function decodeUCoordinate(u32) {
  const masked = Buffer.from(u32); masked[31] &= 0x7f;
  return masked;
}

/** map_to_curve_elligator2 (RFC 9380) for curve25519, u-coordinate only (v is discarded, as the draft says). */
export function elligator2(u32) {
  const u = mod(leToBig(decodeUCoordinate(u32)));
  const den = mod(1n + 2n * u * u);
  const w = den === 0n ? mod(-A) : mod(-A * inv(den));
  const v = mod(w * w * w + A * w * w + w);
  const square = v === 0n || pow(v, (P - 1n) / 2n) === 1n;
  return bigToLe32(square ? w : mod(-A - w));
}

/** generator_string(DSI, PRS, CI, sid, s_in_bytes) = lv_cat(DSI, PRS, zero_bytes(len_zpad), CI, sid) */
export function generatorString(prs, sid, ci) {
  const lenZpad = Math.max(0, S_IN_BYTES - lv(prs).length - lv(Buffer.from(DSI)).length - 1);
  return lvCat(Buffer.from(DSI), prs, Buffer.alloc(lenZpad), ci, sid);
}
export const generatorHash = (prs, sid, ci) => sha512(generatorString(prs, sid, ci)).subarray(0, 32);
export const generator = (prs, sid, ci) => elligator2(generatorHash(prs, sid, ci));

const PKCS8 = Buffer.from('302e020100300506032b656e04220420', 'hex');
const SPKI = Buffer.from('302a300506032b656e032100', 'hex');
/**
 * G_X25519.scalar_mult_vfy: X25519(s, u), returning the neutral element G.I (32 zero bytes) when the result is
 * the all-zero string. OpenSSL signals that by throwing "failed during derivation"; any other failure is rethrown.
 */
export function scalarMultVfy(seed32, u32) {
  const priv = createPrivateKey({ key: Buffer.concat([PKCS8, seed32]), format: 'der', type: 'pkcs8' });
  const pub = createPublicKey({ key: Buffer.concat([SPKI, u32]), format: 'der', type: 'spki' });
  try {
    return Buffer.from(diffieHellman({ privateKey: priv, publicKey: pub }));
  } catch (e) {
    if (String(e && e.message).includes('failed during derivation')) return Buffer.alloc(32);
    throw e;
  }
}
const isNeutral = (b) => b.every((x) => x === 0);

/** X25519 for protocol use: aborts (throws) on the neutral element, as the draft's "MUST abort if K = G.I". */
export function x25519(seed32, u32) {
  const out = scalarMultVfy(seed32, u32);
  if (isNeutral(out)) throw new Error('low order');
  return out;
}
export const share = (seed, g) => x25519(seed, g);

// transcripts (draft section 6.3). The first share belongs to the initiator (the child device in Olive).
export const transcriptIr = (ya, ada, yb, adb) => Buffer.concat([lv(ya), lv(ada), lv(yb), lv(adb)]);
/** o_cat: the lexicographically larger string first, prefixed with b"oc". Only the symmetric mode uses it. */
export const oCat = (b1, b2) => (Buffer.compare(b1, b2) >= 0 ? Buffer.concat([Buffer.from('oc'), b1, b2]) : Buffer.concat([Buffer.from('oc'), b2, b1]));
export const transcriptOc = (ya, ada, yb, adb) => oCat(lvCat(ya, ada), lvCat(yb, adb));

/** ISK = H.hash(lv_cat(G.DSI || b"_ISK", sid, K) || transcript). `transcript` is transcriptIr(...) or transcriptOc(...). */
export const iskFromTranscript = (sid, K, transcript) => sha512(lvCat(Buffer.from(DSI + '_ISK'), sid, K), transcript);
export const isk = (sid, K, yInit, adInit, yResp, adResp) => iskFromTranscript(sid, K, transcriptIr(yInit, adInit, yResp, adResp));
/** Optional output of the draft (B.1.7): H.hash(b"CPaceSidOutput" + transcript). */
export const sidOutput = (transcript) => sha512(Buffer.from('CPaceSidOutput'), transcript);

// ---------------------------------------------------------------- Olive layer (not part of CPace) ----------
const kdf = (key, label) => sha512(lv(Buffer.from(label)), lv(key)).subarray(0, 32);
/** What the confirmation tags are computed over: shares, channel identifier and session id (Olive's own layout). */
export const confirmTranscript = (yc, ya, ci, sid) => Buffer.concat([lv(yc), lv(ya), lv(ci), lv(sid)]);
export const confirmTag = (iskBytes, role, tr) =>
  createHmac('sha256', kdf(iskBytes, 'confirm')).update(Buffer.concat([lv(Buffer.from(role)), tr])).digest();
export const sasBytes = (iskBytes) => kdf(iskBytes, 'sas').subarray(0, 2);
export const matchBytes = (iskBytes) => kdf(iskBytes, 'match').subarray(0, 3);
export const channelKey = (iskBytes) => kdf(iskBytes, 'channel');

/**
 * The channel identifier Olive passes as CI (draft 10.1.1: initiator identity first, responder identity second,
 * each length-prefixed). Initiator = the child device (its public key); responder = the adult device (key
 * fingerprint, family id, display name). The session id is NOT inside CI: it is its own CPace input.
 */
export function channelId({ cpk, afp, fid, an }) {
  return lvCat(cpk, lvCat(afp, Buffer.from(fid), Buffer.from(an)));
}

/** One whole exchange between a child (initiator) and an adult (responder) with the Olive layer on top. */
export function run({ prsC, prsA, sid, ci, yc, ya, adC = Buffer.alloc(0), adA = Buffer.alloc(0) }) {
  const gC = generator(prsC, sid, ci), gA = generator(prsA, sid, ci);
  const Yc = share(yc, gC), Ya = share(ya, gA);
  const Kc = x25519(yc, Ya), Ka = x25519(ya, Yc);
  const iskC = isk(sid, Kc, Yc, adC, Ya, adA), iskA = isk(sid, Ka, Yc, adC, Ya, adA);
  const tr = confirmTranscript(Yc, Ya, ci, sid);
  return {
    gC, gA, Yc, Ya, iskC, iskA, tagC: confirmTag(iskC, 'C', tr), tagA: confirmTag(iskA, 'A', tr),
    sas: sasBytes(iskC), match: matchBytes(iskC),
  };
}
