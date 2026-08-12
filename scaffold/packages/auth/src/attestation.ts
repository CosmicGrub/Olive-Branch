import { createPublicKey } from 'node:crypto';

/**
 * WebAuthn REGISTRATION — the half auth.ts's verifyAssertion() does not cover.
 * verifyAssertion() checks a LOGIN: an already-registered credential signing a
 * challenge. Registration is the opposite problem: a brand-new credential's
 * public key arrives wrapped in a CBOR-encoded `attestationObject`, and it has
 * to be unwrapped before there is anything to store or ever verify against.
 * Nothing in this repository did that before this file — there is no CBOR
 * library dependency here (this repo does not carry one), and the surface
 * this ceremony actually needs is small and bounded, so this is a real,
 * minimal decoder written against the specs below, not a reduced port of one.
 *
 * Specs implemented against:
 *   - WebAuthn Level 2 §6.5.1 — attestationObject is a CBOR map:
 *       { fmt: text string, attStmt: map, authData: byte string }
 *   - RFC 8152 §13.1.1 / RFC 9053 — COSE_Key, EC2 subset only:
 *       1 (kty) => 2 (EC2), 3 (alg) => -7 (ES256), -1 (crv) => 1 (P-256),
 *       -2 (x) / -3 (y) => 32-byte big-endian coordinates.
 *   - CBOR itself is RFC 8949; only the major types WebAuthn's own encoders
 *     actually produce are implemented (see decodeItem() below) — this is a
 *     parser for "CBOR as CTAP2/WebAuthn authenticators emit it", not a
 *     general-purpose CBOR library. Indefinite-length items (RFC 8949 §3.2)
 *     are refused rather than guessed at: real authenticators do not emit
 *     them (CTAP2 mandates definite-length, canonical encoding), so refusing
 *     is a correct rejection of malformed/adversarial input, not a missing
 *     feature this ceremony would ever need.
 *
 * What this file deliberately does NOT do: verify the attestation
 * SIGNATURE (attStmt's own contents — format-specific: 'packed', 'fido-u2f',
 * 'none', etc.). This repo's trust model for the guardian ceremony is "the
 * guardian present at registration time is authoritative" (the request runs
 * under an already-authenticated guardian session — see server/routes.mjs's
 * /v1/auth/webauthn/register/verify), not "a hardware manufacturer's
 * attestation chain is" — verifying attStmt would be real, non-trivial code
 * (X.509 chain validation, format-specific signature schemes) with no
 * consumer anywhere in §7's routes for its result. Extracting the public key
 * from `authData` — the part every future login actually depends on — is
 * this file's entire job.
 */

// ============================================================================
// A minimal CBOR decoder (RFC 8949), scoped to what an attestationObject and
// a COSE_Key ever contain: unsigned/negative integers, byte strings, text
// strings, arrays, maps, and simple values (true/false/null) — enough to
// correctly walk PAST an attStmt of arbitrary shape (a real 'packed'
// attestation's attStmt contains nested maps, byte strings, and an array of
// x5c certificate byte strings) without needing to interpret it, and to
// decode a COSE_Key map's integer keys directly.
// ============================================================================

interface CborResult { value: unknown; bytesConsumed: number }

function fail(msg: string): never { throw new Error(`CBOR: ${msg}`); }

/** Decodes exactly one CBOR data item starting at `offset`. Recurses for
 * arrays/maps/tags. Throws — never silently truncates or guesses — on any
 * structural problem: truncated buffer, a reserved additional-info value
 * (28-30), or an indefinite-length item (31), all of which are either
 * malformed input or an encoding this ceremony's real producers never use. */
function decodeItem(buf: Buffer, offset: number): CborResult {
  if (offset >= buf.length) fail('unexpected end of buffer reading initial byte');
  const initial = buf[offset];
  const majorType = initial >> 5;
  const additionalInfo = initial & 0x1f;

  let argument: number;
  let headerLen: number;
  if (additionalInfo <= 23) {
    argument = additionalInfo; headerLen = 1;
  } else if (additionalInfo === 24) {
    if (offset + 2 > buf.length) fail('truncated 1-byte length');
    argument = buf.readUInt8(offset + 1); headerLen = 2;
  } else if (additionalInfo === 25) {
    if (offset + 3 > buf.length) fail('truncated 2-byte length');
    argument = buf.readUInt16BE(offset + 1); headerLen = 3;
  } else if (additionalInfo === 26) {
    if (offset + 5 > buf.length) fail('truncated 4-byte length');
    argument = buf.readUInt32BE(offset + 1); headerLen = 5;
  } else if (additionalInfo === 27) {
    if (offset + 9 > buf.length) fail('truncated 8-byte length');
    const big = buf.readBigUInt64BE(offset + 1);
    if (big > BigInt(Number.MAX_SAFE_INTEGER)) fail('8-byte length exceeds safe integer range');
    argument = Number(big); headerLen = 9;
  } else if (additionalInfo === 31) {
    fail('indefinite-length items are not supported (no real authenticator emits them)');
  } else {
    fail(`reserved additional-info value ${additionalInfo}`);
  }

  const start = offset + headerLen;

  switch (majorType) {
    case 0: // unsigned integer
      return { value: argument, bytesConsumed: headerLen };
    case 1: // negative integer: value = -1 - argument
      return { value: -1 - argument, bytesConsumed: headerLen };
    case 2: { // byte string
      if (start + argument > buf.length) fail('truncated byte string');
      return { value: buf.subarray(start, start + argument), bytesConsumed: headerLen + argument };
    }
    case 3: { // text string
      if (start + argument > buf.length) fail('truncated text string');
      return { value: buf.subarray(start, start + argument).toString('utf8'),
                bytesConsumed: headerLen + argument };
    }
    case 4: { // array
      const arr: unknown[] = [];
      let pos = start;
      for (let i = 0; i < argument; i++) {
        const item = decodeItem(buf, pos);
        arr.push(item.value);
        pos += item.bytesConsumed;
      }
      return { value: arr, bytesConsumed: pos - offset };
    }
    case 5: { // map — argument is the number of KEY/VALUE PAIRS
      const map = new Map<unknown, unknown>();
      let pos = start;
      for (let i = 0; i < argument; i++) {
        const key = decodeItem(buf, pos); pos += key.bytesConsumed;
        const val = decodeItem(buf, pos); pos += val.bytesConsumed;
        map.set(key.value, val.value);
      }
      return { value: map, bytesConsumed: pos - offset };
    }
    case 6: { // tag — transparent: decode and return the tagged item's value
      const inner = decodeItem(buf, start);
      return { value: inner.value, bytesConsumed: headerLen + inner.bytesConsumed };
    }
    case 7: // simple/float
      if (additionalInfo === 20) return { value: false, bytesConsumed: headerLen };
      if (additionalInfo === 21) return { value: true, bytesConsumed: headerLen };
      if (additionalInfo === 22) return { value: null, bytesConsumed: headerLen };
      if (additionalInfo === 23) return { value: undefined, bytesConsumed: headerLen };
      // Half/single/double floats (additionalInfo 25/26/27) and other simple
      // values: never produced by an attestationObject or a COSE_Key in this
      // ceremony (fmt/attStmt keys are text strings; COSE_Key's values here
      // are all small integers or 32-byte coordinates) — refusing rather
      // than silently mis-decoding a class of value this parser was never
      // asked to support.
      fail(`unsupported major-type-7 simple/float value (additionalInfo=${additionalInfo})`);
    default:
      fail(`impossible major type ${majorType}`);
  }
}

// ============================================================================
// attestationObject (WebAuthn L2 §6.5.1)
// ============================================================================

export function parseAttestationObject(
  attestationObjectB64u: string,
): { fmt: string; authData: Buffer } {
  let buf: Buffer;
  try {
    buf = Buffer.from(attestationObjectB64u, 'base64url');
  } catch {
    throw new Error('attestationObject: not valid base64url');
  }
  if (buf.length === 0) throw new Error('attestationObject: empty');

  let decoded: CborResult;
  try {
    decoded = decodeItem(buf, 0);
  } catch (e) {
    throw new Error(`attestationObject: malformed CBOR — ${(e as Error).message}`);
  }

  const top = decoded.value;
  if (!(top instanceof Map)) {
    throw new Error('attestationObject: top-level CBOR value is not a map');
  }
  if (!top.has('fmt')) throw new Error('attestationObject: missing fmt');
  if (!top.has('attStmt')) throw new Error('attestationObject: missing attStmt');
  if (!top.has('authData')) throw new Error('attestationObject: missing authData');

  const fmt = top.get('fmt');
  const authData = top.get('authData');
  if (typeof fmt !== 'string') throw new Error('attestationObject: fmt is not a text string');
  if (!Buffer.isBuffer(authData)) throw new Error('attestationObject: authData is not a byte string');

  return { fmt, authData };
}

// ============================================================================
// authData (WebAuthn L2 §6.1) + COSE_Key EC2 (RFC 9053 / RFC 8152 §13.1.1)
// ============================================================================

/** Bit 0x40 of the flags byte: "attested credential data included" — set
 * only on a REGISTRATION authData, never a login one. */
const ATTESTED_CREDENTIAL_DATA_FLAG = 0x40;

/** rpIdHash(32) + flags(1) + signCount(4) — present on every authData
 * regardless of flags. */
const AUTH_DATA_FIXED_PREFIX_LEN = 32 + 1 + 4;

export function extractCredentialPublicKey(
  authData: Buffer,
): { credentialId: string; publicKeyPem: string } {
  if (authData.length < AUTH_DATA_FIXED_PREFIX_LEN) {
    throw new Error('authData: shorter than the fixed 37-byte prefix');
  }
  const flags = authData[32];
  if ((flags & ATTESTED_CREDENTIAL_DATA_FLAG) === 0) {
    throw new Error(
      'authData: attested credential data flag (0x40) is not set — this is a ' +
      'login authData (or a malformed registration one), not a registration one',
    );
  }

  let offset = AUTH_DATA_FIXED_PREFIX_LEN;
  const AAGUID_LEN = 16;
  const CRED_ID_LEN_FIELD = 2;
  if (authData.length < offset + AAGUID_LEN + CRED_ID_LEN_FIELD) {
    throw new Error('authData: truncated before aaguid/credentialIdLength');
  }
  // aaguid: which authenticator model this is. Unused — this repo maintains
  // no authenticator allowlist/attestation-metadata trust store (see this
  // file's header: attStmt's manufacturer-attestation chain is out of scope
  // by design).
  offset += AAGUID_LEN;

  const credIdLen = authData.readUInt16BE(offset);
  offset += CRED_ID_LEN_FIELD;
  if (authData.length < offset + credIdLen) {
    throw new Error('authData: truncated credentialId');
  }
  const credentialIdBuf = authData.subarray(offset, offset + credIdLen);
  offset += credIdLen;

  if (offset >= authData.length) {
    throw new Error('authData: no COSE_Key bytes follow the credentialId');
  }
  let decoded: CborResult;
  try {
    decoded = decodeItem(authData, offset);
  } catch (e) {
    throw new Error(`authData: malformed COSE_Key CBOR — ${(e as Error).message}`);
  }
  const cose = decoded.value;
  if (!(cose instanceof Map)) throw new Error('authData: COSE_Key is not a CBOR map');

  // RFC 9053 / RFC 8152 §13.1.1 — COSE_Key, EC2 subset only. This repo's
  // only ceremony is ES256/P-256 (auth.ts's verifyAssertion() calls
  // createVerify('sha256') against an EC key and nothing else), so ANY other
  // kty/alg/crv is refused HERE — at extraction time — rather than being
  // silently stored and only failing later, opaquely, inside verifyAssertion
  // on the first real login attempt.
  const kty = cose.get(1);
  const alg = cose.get(3);
  const crv = cose.get(-1);
  const x = cose.get(-2);
  const y = cose.get(-3);

  const COSE_KTY_EC2 = 2;
  const COSE_ALG_ES256 = -7;
  const COSE_CRV_P256 = 1;

  if (kty !== COSE_KTY_EC2) {
    throw new Error(`COSE_Key: unsupported kty ${String(kty)} (only EC2/2 is supported)`);
  }
  if (alg !== COSE_ALG_ES256) {
    throw new Error(`COSE_Key: unsupported alg ${String(alg)} (only ES256/-7 is supported)`);
  }
  if (crv !== COSE_CRV_P256) {
    throw new Error(`COSE_Key: unsupported crv ${String(crv)} (only P-256/1 is supported)`);
  }
  if (!Buffer.isBuffer(x) || x.length !== 32) {
    throw new Error('COSE_Key: x is not a 32-byte P-256 coordinate');
  }
  if (!Buffer.isBuffer(y) || y.length !== 32) {
    throw new Error('COSE_Key: y is not a 32-byte P-256 coordinate');
  }

  // JWK -> SPKI PEM via Node's own crypto — deliberately NOT hand-rolled
  // ASN.1 DER encoding. auth.ts's own header treats crypto surface with real
  // caution ("a fast hash here is equivalent to storing the PIN in
  // plaintext" — same standard applies to hand-written key encoding, which
  // is exactly the kind of low-level surface a one-byte-off DER length would
  // silently corrupt). createPublicKey({format:'jwk'}) does the ASN.1 work.
  const publicKey = createPublicKey({
    key: { kty: 'EC', crv: 'P-256', x: x.toString('base64url'), y: y.toString('base64url') },
    format: 'jwk',
  });
  const publicKeyPem = publicKey.export({ type: 'spki', format: 'pem' }).toString();

  return { credentialId: credentialIdBuf.toString('base64url'), publicKeyPem };
}
