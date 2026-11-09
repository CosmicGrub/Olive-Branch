// Node reference for the encrypted play frame (client/lib/play_frame.dart): ChaCha20-Poly1305 and HKDF-SHA256 from
// node:crypto, and the layout only. The Dart port must agree byte for byte (client/test/vectors/play_frame_vectors.json).
import { createCipheriv, createDecipheriv, hkdfSync } from 'node:crypto';
import { lv } from './pake_cpace.mjs';

export const VERSION = 1;
export const BUCKETS = [256, 1024, 4096, 16384, 32768];

export const hkdf = (ikm, salt, info) => Buffer.from(hkdfSync('sha256', ikm, salt, Buffer.from(info), 32));

export function deriveSessionKeys(dhEphemeral, dhLobby, sid) {
  const ikm = Buffer.concat([lv(dhEphemeral), lv(dhLobby)]);
  return {
    c2s: hkdf(ikm, sid, 'olive-play-c2s-v1'),
    s2c: hkdf(ikm, sid, 'olive-play-s2c-v1'),
    sas: hkdf(ikm, sid, 'olive-play-sas-v1'),
  };
}

export function bucketFor(n) {
  for (const b of BUCKETS) if (n + 2 <= b) return b;
  return null;
}

export function pad(payload) {
  const b = bucketFor(payload.length);
  if (b === null) throw new Error('too large');
  const out = Buffer.alloc(b);
  out.writeUInt16BE(payload.length, 0);
  payload.copy(out, 2);
  return out;
}

const seqBytes = (seq) => { const b = Buffer.alloc(8); b.writeBigUInt64BE(BigInt(seq)); return b; };

export function seal(key, sid, seq, payload) {
  const s = seqBytes(seq);
  const nonce = Buffer.concat([Buffer.alloc(4), s]);
  const aad = Buffer.concat([lv(Buffer.from('olive-play-frame-v1')), lv(sid), Buffer.from([VERSION]), s]);
  const c = createCipheriv('chacha20-poly1305', key, nonce, { authTagLength: 16 });
  c.setAAD(aad);
  const ct = Buffer.concat([c.update(pad(payload)), c.final()]);
  return Buffer.concat([Buffer.from([VERSION]), s, ct, c.getAuthTag()]);
}

export function open(key, sid, frame) {
  const s = frame.subarray(1, 9);
  const nonce = Buffer.concat([Buffer.alloc(4), s]);
  const aad = Buffer.concat([lv(Buffer.from('olive-play-frame-v1')), lv(sid), Buffer.from([VERSION]), s]);
  const d = createDecipheriv('chacha20-poly1305', key, nonce, { authTagLength: 16 });
  d.setAAD(aad);
  d.setAuthTag(frame.subarray(frame.length - 16));
  const plain = Buffer.concat([d.update(frame.subarray(9, frame.length - 16)), d.final()]);
  const n = plain.readUInt16BE(0);
  return plain.subarray(2, 2 + n);
}
