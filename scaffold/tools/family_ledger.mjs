// Reference (Node) implementation of the family ledger's canonical encoding, entry hash, vote bytes and agreement
// certificate. It is INDEPENDENT of the Dart port (client/lib/family_ledger.dart): the only cross-check between the
// two is client/test/vectors/family_ledger_vectors.json, produced by tools/gen-family-ledger-vectors.mjs and read by
// client/test/family_ledger_vectors_test.dart. Design: docs/planning/FAMILY-IDENTITY-DESIGN.md section 3.2.
//
// HONEST STATUS. Custom composition over standard primitives (Ed25519, SHA-256). No outside cryptographic review.
import { createHash, createPrivateKey, createPublicKey, sign as edSign, verify as edVerify } from 'node:crypto';

export const LEDGER_DOMAIN = 'olive-ledger-v1';
export const VOTE_DOMAIN = 'olive-ledger-vote-v1';
export const AGREE_CERT_DOMAIN = 'olive-agree-cert-v1';

export const lv = (b) => {
  b = Buffer.from(b);
  const len = []; let n = b.length;
  do { let byte = n & 0x7f; n >>= 7; if (n) byte |= 0x80; len.push(byte); } while (n);
  return Buffer.concat([Buffer.from(len), b]);
};
const cat = (...p) => Buffer.concat(p.map((x) => Buffer.from(x)));

// A value tree: null, boolean, non-negative integer (JS number), string, Buffer (bytes), Array, plain object (map).
const KEY_RE = /^[A-Za-z0-9_.-]{1,24}$/;
export function encodeValue(v, depth = 0) {
  if (depth > 8) throw new Error('too deep');
  if (v === null) return Buffer.from([7]);
  if (typeof v === 'boolean') return Buffer.from([6, v ? 1 : 0]);
  if (typeof v === 'number') {
    if (!Number.isInteger(v) || v < 0) throw new Error('bad integer');
    return cat([2], lv(Buffer.from(String(v), 'ascii')));
  }
  if (typeof v === 'string') return cat([1], lv(Buffer.from(v, 'utf8')));
  if (Buffer.isBuffer(v)) return cat([3], lv(v));
  if (Array.isArray(v)) return cat([4], lv(cat(...v.map((x) => encodeValue(x, depth + 1)))));
  if (typeof v === 'object') {
    const keys = Object.keys(v);
    for (const k of keys) if (!KEY_RE.test(k)) throw new Error('bad key ' + k);
    keys.sort((a, b) => Buffer.compare(Buffer.from(a, 'ascii'), Buffer.from(b, 'ascii')));
    const inner = cat(...keys.map((k) => cat(lv(Buffer.from(k, 'ascii')), encodeValue(v[k], depth + 1))));
    return cat([5], lv(inner));
  }
  throw new Error('unsupported value');
}

export function signedBytes({ type, prev, body, signer, issuedAt }) {
  const ps = prev.map((h) => Buffer.from(h, 'hex')).sort(Buffer.compare);
  return cat(
    lv(Buffer.from(LEDGER_DOMAIN)), lv(Buffer.from(type)), lv(encodeValue(ps)), lv(encodeValue(body)),
    lv(signer), lv(Buffer.from(String(issuedAt), 'ascii')),
  );
}

export const entryHash = (bytes, sig) => createHash('sha256').update(cat(lv(bytes), lv(sig))).digest();

const PKCS8_ED25519 = Buffer.from('302e020100300506032b657004220420', 'hex');
export const privateKeyOf = (seed) => createPrivateKey({ key: Buffer.concat([PKCS8_ED25519, Buffer.from(seed)]), format: 'der', type: 'pkcs8' });
export const publicKeyOf = (seed) => createPublicKey(privateKeyOf(seed)).export({ format: 'der', type: 'spki' }).subarray(-32);
export const edSignBytes = (seed, bytes) => edSign(null, Buffer.from(bytes), privateKeyOf(seed));
const SPKI_ED25519 = Buffer.from('302a300506032b6570032100', 'hex');
export const edVerifyBytes = (pub, bytes, sig) => {
  try {
    return edVerify(null, Buffer.from(bytes), createPublicKey({ key: Buffer.concat([SPKI_ED25519, Buffer.from(pub)]), format: 'der', type: 'spki' }), Buffer.from(sig));
  } catch { return false; }
};

export const voteBytes = (target, answer, voter, at) =>
  cat(lv(Buffer.from(VOTE_DOMAIN)), lv(target), lv(Buffer.from(answer)), lv(voter), lv(Buffer.from(String(at), 'ascii')));

export const agreeCertBytes = (agreePub, devicePub) =>
  cat(lv(Buffer.from(AGREE_CERT_DOMAIN)), lv(agreePub), lv(devicePub));

// Vector bodies are written as JSON in which a byte string is {"$b": "<hex>"}. (A map key can never be "$b".)
export function fromJsonValue(j) {
  if (j === null || typeof j === 'boolean' || typeof j === 'number' || typeof j === 'string') return j;
  if (Array.isArray(j)) return j.map(fromJsonValue);
  if (typeof j === 'object') {
    if (Object.keys(j).length === 1 && '$b' in j) return Buffer.from(j.$b, 'hex');
    return Object.fromEntries(Object.entries(j).map(([k, v]) => [k, fromJsonValue(v)]));
  }
  throw new Error('bad json value');
}
