// OLIVE BRANCH -- encrypted family backup: the pure, side-effect-free parts.
// MASTERFILE 7.22. Nothing here touches a database, a clock or the network, so
// the same functions are used by the server to CHECK what a phone sent and by
// the tests (and, ported, by the phone) to detect a server that tampers with,
// drops, reorders or rolls back a family's backup.
//
// WHAT THE SERVER CAN AND CANNOT DO WITH THESE
//   The phone computes, for every backup version it uploads,
//
//     chain = SHA-256( "olive-backup-chain-v1" 0x00
//                      vaultId (16 bytes) | seq (u64 big-endian)
//                      | prevChain (32) | blobSha256 (32) | size (u64 big-endian)
//                      | SHA-256(manifest) (32) )
//
//   and signs `chain` with a key only a family phone holds. The server verifies
//   the LINK (prev matches the head it holds, the claimed chain really is that
//   hash of the claimed parts, the bytes it stored hash to blobSha256) so it
//   never accepts a broken chain; it cannot verify the SIGNATURE (it holds no
//   family key) and does not try to. The phone verifies the signatures and the
//   whole chain on restore and remembers the newest (seq, chain) it has seen,
//   so a server that serves an old head, hides a version, edits one or swaps in
//   another family's is caught by the phone, not trusted.
import { createHash, createPublicKey, verify as edVerify, randomBytes } from 'node:crypto';

export const CHAIN_DOMAIN = 'olive-backup-chain-v1';
export const RESTORE_DOMAIN = 'olive-backup-restore-v1';
/** The chain value before the first version exists: 32 zero bytes. */
export const GENESIS_CHAIN = Buffer.alloc(32);

const HEX64 = /^[0-9a-f]{64}$/;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const B64 = /^[A-Za-z0-9+/]*={0,2}$/;

export const sha256 = (...parts) => {
  const h = createHash('sha256');
  for (const p of parts) h.update(p);
  return h.digest();
};

export const uuidBytes = (id) => {
  if (!UUID.test(String(id))) throw new Error('not a uuid');
  return Buffer.from(String(id).replace(/-/g, ''), 'hex');
};

const u64 = (n) => {
  const b = Buffer.alloc(8);
  b.writeBigUInt64BE(BigInt(n));
  return b;
};

/** Strict hex of exactly 32 bytes, or null. */
export function hex32(v) {
  return typeof v === 'string' && HEX64.test(v) ? Buffer.from(v, 'hex') : null;
}

/** Strict standard base64 (no whitespace, canonical padding) with a decoded size window, or null. */
export function b64(v, minBytes, maxBytes) {
  if (typeof v !== 'string' || v.length === 0 || v.length % 4 !== 0 || !B64.test(v)) return null;
  const buf = Buffer.from(v, 'base64');
  if (buf.toString('base64') !== v) return null;
  if (buf.length < minBytes || buf.length > maxBytes) return null;
  return buf;
}

/** The chain value for one version. `prevChain`, `blobSha256` are 32-byte Buffers; `manifest` a Buffer. */
export function chainHash({ vaultId, seq, prevChain, blobSha256, size, manifest }) {
  return sha256(
    Buffer.from(CHAIN_DOMAIN, 'utf8'), Buffer.from([0]),
    uuidBytes(vaultId), u64(seq), prevChain, blobSha256, u64(size), sha256(manifest));
}

/**
 * What the family's recovery key signs to start a restore. Binds the vault, the
 * account, THIS phone and a one-time server nonce, so a signature cannot be
 * replayed for another vault, another person, another phone or another time.
 */
export function restoreChallengeMessage({ vaultId, userId, deviceId, nonce }) {
  return Buffer.concat([
    Buffer.from(RESTORE_DOMAIN, 'utf8'), Buffer.from([0]),
    uuidBytes(vaultId), uuidBytes(userId), uuidBytes(deviceId), nonce]);
}

const ED25519_SPKI_PREFIX = Buffer.from('302a300506032b6570032100', 'hex');

/** Ed25519 verify with a raw 32-byte public key. Never throws: a malformed key or signature is just `false`. */
export function ed25519Verify(rawPublicKey, message, signature) {
  try {
    if (!Buffer.isBuffer(rawPublicKey) || rawPublicKey.length !== 32) return false;
    if (!Buffer.isBuffer(signature) || signature.length !== 64) return false;
    const key = createPublicKey({ key: Buffer.concat([ED25519_SPKI_PREFIX, rawPublicKey]), format: 'der', type: 'spki' });
    return edVerify(null, message, key, signature);
  } catch { return false; }
}

/** A 256-bit URL-safe token and its digest (only the digest is stored). */
export function newToken() {
  const token = randomBytes(32).toString('base64url');
  return { token, digest: tokenDigest(token) };
}
export const tokenDigest = (token) => createHash('sha256').update(String(token), 'utf8').digest('hex');

/**
 * THE CLIENT'S CHECK, as a reference implementation the server's own tests run
 * against what the server returns (and which the phone ports). Given the
 * versions the server lists (oldest first, tombstones included) and the newest
 * (seq, chain) this phone has already seen, say whether the history is intact:
 *
 *   ok               the chain is unbroken from the first listed version, every
 *                    chain value is recomputed from its own parts, signatures
 *                    pass `verifySignature(chainHashBuffer, signatureBuffer, versionRow)`,
 *                    and the head is not older than the phone's high-water mark.
 *   reason           'chain_broken' | 'chain_value_wrong' | 'bad_signature' |
 *                    'gap' | 'rollback' | 'high_water_changed'
 *
 * `versions[i]` = { seq, prevChainHash, chainHash, blobSha256, sizeBytes, manifest, signature }
 * with 32-byte hashes as hex strings and manifest/signature as base64.
 */
export function verifyHistory({ vaultId, versions, highWater = null, verifySignature = () => true, startPrev = GENESIS_CHAIN }) {
  let prev = startPrev;
  let expectSeq = versions.length ? Number(versions[0].seq) : null;
  for (const v of versions) {
    if (Number(v.seq) !== expectSeq) return { ok: false, reason: 'gap', seq: Number(v.seq) };
    if (Buffer.from(v.prevChainHash, 'hex').compare(prev) !== 0) return { ok: false, reason: 'chain_broken', seq: Number(v.seq) };
    const manifest = Buffer.from(v.manifest, 'base64');
    const want = chainHash({
      vaultId, seq: v.seq, prevChain: prev, blobSha256: Buffer.from(v.blobSha256, 'hex'),
      size: v.sizeBytes, manifest });
    if (want.toString('hex') !== v.chainHash) return { ok: false, reason: 'chain_value_wrong', seq: Number(v.seq) };
    if (!verifySignature(want, Buffer.from(v.signature, 'base64'), v)) return { ok: false, reason: 'bad_signature', seq: Number(v.seq) };
    prev = want;
    expectSeq += 1;
  }
  const head = versions.length ? versions[versions.length - 1] : null;
  if (highWater) {
    if (!head || Number(head.seq) < Number(highWater.seq)) return { ok: false, reason: 'rollback' };
    const at = versions.find((v) => Number(v.seq) === Number(highWater.seq));
    if (at && at.chainHash !== highWater.chainHash) return { ok: false, reason: 'high_water_changed', seq: Number(highWater.seq) };
  }
  return { ok: true, headSeq: head ? Number(head.seq) : 0, headChain: head ? head.chainHash : GENESIS_CHAIN.toString('hex') };
}
