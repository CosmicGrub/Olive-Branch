/**
 * SEALED RELAY ENVELOPE (server-snoop hardening, docs/superpowers/specs/
 * 2026-11-08-server-snoop-hardening-design.md section 4.2).
 *
 * For any server-relayed play or co-view the server is a courier of OPAQUE
 * bytes. Keys are made on the two devices and never reach the server, so the
 * relay cannot read a move, a hand, a position or a content id. The only
 * thing it may look at is the routing frame defined here:
 *
 *   { "v": 1, "t": "sealed", "seq": <uint32>, "ct": "<base64url>" }
 *
 *  E1  Exactly these four keys. Any other key (move, from, to, hand, card,
 *      seat, pos, contentId, ...) is refused: there is no plaintext field.
 *  E2  `ct` decodes to EXACTLY one size bucket (256, 1024 or 4096 bytes). The
 *      sender pads INSIDE the AEAD plaintext, so message type and move size
 *      are hidden from the operator and from a TLS-record-size observer.
 *  E3  `seq` is a per-direction counter the receiver binds into the AEAD
 *      associated data; the relay only enforces that it strictly increases
 *      (replay and reorder are dropped), never what it means.
 *  E4  Plaintext tripwire: bytes that are valid UTF-8 text, mostly printable
 *      ASCII, or of very low entropy are refused. Real ciphertext fails this
 *      test with negligible probability; a client bug that pads JSON fails at
 *      once. It is a tripwire, not a proof of encryption (a relay cannot
 *      prove that), and the docs say so.
 *
 * AEAD interface the devices implement (compatible in spirit with the
 * local-play framing): AES-256-GCM or XChaCha20-Poly1305; key = HKDF(pairing
 * secret, salt = room id, info = "olive-relay-v1"); nonce = 32-bit direction ||
 * 64-bit counter (counter == seq); associated data = "olive-relay-v1" ||
 * room id || dir || seq || v. A relay that rewrites seq, dir or the room
 * produces an authentication failure on the receiving device.
 */

export const ENVELOPE_VERSION = 1;
export const SEALED_GAME = 'sealed-v1';
/** Allowed decoded ciphertext sizes, in bytes. */
export const ENVELOPE_BUCKETS = [256, 1024, 4096] as const;
export const MAX_SEQ = 0xffffffff;
/** Largest JSON frame a sealed table accepts (base64url of the top bucket plus framing). */
export const MAX_ENVELOPE_FRAME_BYTES = Math.ceil(4096 * 4 / 3) + 96;

export type EnvelopeDeny =
  | 'not_object' | 'bad_keys' | 'bad_version' | 'bad_type' | 'bad_seq'
  | 'bad_ct' | 'bad_bucket' | 'plaintext_suspected';

export interface SealedEnvelope {
  readonly v: 1;
  readonly t: 'sealed';
  readonly seq: number;
  readonly ct: string;
}

const B64URL = /^[A-Za-z0-9_-]+$/;
const ALLOWED_KEYS = new Set(['v', 't', 'seq', 'ct']);

/** Base64url length (no padding) of `n` bytes. */
export const b64urlLength = (n: number): number => Math.ceil((n * 4) / 3);

/** True when the bytes look like text or like something with no entropy. */
export function looksLikePlaintext(bytes: Uint8Array): boolean {
  const n = bytes.length;
  if (n === 0) return true;
  let printable = 0;
  const seen = new Set<number>();
  for (const b of bytes) {
    if ((b >= 0x20 && b < 0x7f) || b === 0x09 || b === 0x0a || b === 0x0d) printable++;
    seen.add(b);
  }
  if (printable / n > 0.85) return true;
  if (seen.size < Math.min(128, Math.floor(n / 3))) return true;
  try {
    new TextDecoder('utf-8', { fatal: true }).decode(bytes);
    return true; // valid UTF-8 end to end: ciphertext is essentially never this
  } catch { /* not text: good */ }
  return false;
}

export type ParseEnvelopeResult =
  | { ok: true; env: SealedEnvelope; bytes: Uint8Array }
  | { ok: false; reason: EnvelopeDeny };

/** Strict, deny-by-default parse of one inbound sealed frame (already JSON-decoded). */
export function parseEnvelope(raw: unknown): ParseEnvelopeResult {
  if (typeof raw !== 'object' || raw === null || Array.isArray(raw)) {
    return { ok: false, reason: 'not_object' };
  }
  const o = raw as Record<string, unknown>;
  const keys = Object.keys(o);
  if (keys.length !== ALLOWED_KEYS.size || keys.some((k) => !ALLOWED_KEYS.has(k))) {
    return { ok: false, reason: 'bad_keys' };
  }
  if (o.v !== ENVELOPE_VERSION) return { ok: false, reason: 'bad_version' };
  if (o.t !== 'sealed') return { ok: false, reason: 'bad_type' };
  if (typeof o.seq !== 'number' || !Number.isInteger(o.seq) || o.seq < 0 || o.seq > MAX_SEQ) {
    return { ok: false, reason: 'bad_seq' };
  }
  if (typeof o.ct !== 'string' || !B64URL.test(o.ct)) return { ok: false, reason: 'bad_ct' };
  const bucket = ENVELOPE_BUCKETS.find((b) => b64urlLength(b) === (o.ct as string).length);
  if (bucket === undefined) return { ok: false, reason: 'bad_bucket' };
  const bytes = Buffer.from(o.ct, 'base64url');
  // Canonical encoding only: a different spelling of the same bytes is refused.
  if (bytes.length !== bucket || bytes.toString('base64url') !== o.ct) {
    return { ok: false, reason: 'bad_ct' };
  }
  if (looksLikePlaintext(bytes)) return { ok: false, reason: 'plaintext_suspected' };
  return { ok: true, env: { v: 1, t: 'sealed', seq: o.seq, ct: o.ct }, bytes };
}

/** What the relay forwards: the sender's seat is attached by the SERVER, never read from the wire. */
export interface RelayedEnvelope {
  readonly type: 'sealed';
  readonly v: 1;
  readonly dir: 0 | 1;
  readonly seq: number;
  readonly ct: string;
}

export function toRelayed(env: SealedEnvelope, dir: 0 | 1): RelayedEnvelope {
  return { type: 'sealed', v: 1, dir, seq: env.seq, ct: env.ct };
}
