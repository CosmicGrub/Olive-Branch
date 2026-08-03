import {
  scryptSync, randomBytes, timingSafeEqual, createHmac, createVerify,
  createPublicKey, createHash,
} from 'node:crypto';

/**
 * MASTERFILE §7.1, §8.1, db/DEPLOYMENT.md — the layer that produces a
 * `VerifiedPrincipal`. Until this exists, `withSession()` is inert and P6/P7
 * rest on nothing.
 *
 * Two ceremonies, deliberately different in strength:
 *   Guardians  passkey (WebAuthn, ES256) — phishing-resistant, no shared secret.
 *   Children   device-bound token + PIN — a 6-year-old cannot manage a passkey,
 *              and a child profile must not require an email address (§11).
 *
 * Escalation to guardian scope needs PIN **and** biometric (§8.3), because the
 * child is sitting right there watching the keypad.
 */

// --------------------------------------------------------------- PIN hashing --
/**
 * scrypt with per-PIN salt. N=2^15 is chosen for a 4–6 digit secret: the
 * keyspace is tiny (10^4–10^6), so the only defence against an offline attack on
 * a stolen database is making each guess expensive. A fast hash here is
 * equivalent to storing the PIN in plaintext.
 */
export const SCRYPT_N = 32768;
export const SCRYPT_R = 8;
export const SCRYPT_P = 1;
export const PIN_KEYLEN = 32;

/**
 * Node's default scrypt `maxmem` is 32 MiB, but N=32768 r=8 requires
 * 128 * N * r ≈ 33.5 MiB — so scryptSync THROWS on the first call unless maxmem
 * is raised. A cost parameter chosen without checking the runtime's ceiling is
 * not a strong hash, it is an outage; and an implementation that "helpfully"
 * fell back to weaker parameters would be worse still.
 */
export const scryptMaxmem = (N: number, r: number) => 128 * N * r + 1024 * 1024;

export function hashPin(pin: string): string {
  if (!/^\d{4,8}$/.test(pin)) throw new Error('pin must be 4-8 digits');
  const salt = randomBytes(16);
  const key = scryptSync(pin, salt, PIN_KEYLEN,
    { N: SCRYPT_N, r: SCRYPT_R, p: SCRYPT_P,
      maxmem: scryptMaxmem(SCRYPT_N, SCRYPT_R) });
  return `scrypt$${SCRYPT_N}$${SCRYPT_R}$${SCRYPT_P}$${salt.toString('base64url')}$${key.toString('base64url')}`;
}

export function verifyPin(pin: string, stored: string): boolean {
  const parts = stored.split('$');
  if (parts.length !== 6 || parts[0] !== 'scrypt') return false;
  const [, n, r, p, saltB64, keyB64] = parts;
  let expected: Buffer, actual: Buffer;
  try {
    expected = Buffer.from(keyB64, 'base64url');
    actual = scryptSync(pin, Buffer.from(saltB64, 'base64url'), expected.length,
      { N: +n, r: +r, p: +p, maxmem: scryptMaxmem(+n, +r) });
  } catch { return false; }
  // Constant-time. A length-varying or early-returning compare leaks the prefix.
  if (expected.length !== actual.length) return false;
  return timingSafeEqual(expected, actual);
}

// ------------------------------------------------------------------ WebAuthn --
export interface Credential {
  credentialId: string;          // base64url
  publicKeyPem: string;          // ES256 SPKI
  signCount: number;
  userId: string;
}

export interface Assertion {
  credentialId: string;
  clientDataJSON: string;        // base64url
  authenticatorData: string;     // base64url
  signature: string;             // base64url (DER)
}

export type AuthFailure =
  | 'unknown_credential' | 'challenge_mismatch' | 'origin_mismatch'
  | 'type_mismatch' | 'rpid_mismatch' | 'user_not_present'
  | 'bad_signature' | 'signcount_replay' | 'challenge_expired';

const b64u = (s: string) => Buffer.from(s, 'base64url');

/**
 * Verify a WebAuthn assertion. Order matters: cheap structural checks before the
 * expensive signature verification, but **every** check is performed — skipping
 * the signCount comparison is the difference between a passkey and a bearer
 * token that can be replayed forever.
 */
export function verifyAssertion(input: {
  assertion: Assertion;
  credential: Credential | null;
  expectedChallenge: string;     // base64url
  expectedOrigin: string;
  expectedRpIdHash: Buffer;      // sha256(rpId)
  challengeIssuedAt: number;
  now: number;
  challengeTtlMs?: number;
}): { ok: true; newSignCount: number } | { ok: false; reason: AuthFailure } {
  const ttl = input.challengeTtlMs ?? 5 * 60 * 1000;
  const c = input.credential;
  if (!c) return { ok: false, reason: 'unknown_credential' };
  if (input.now - input.challengeIssuedAt > ttl) {
    return { ok: false, reason: 'challenge_expired' };
  }

  let clientData: { type?: string; challenge?: string; origin?: string };
  try { clientData = JSON.parse(b64u(input.assertion.clientDataJSON).toString('utf8')); }
  catch { return { ok: false, reason: 'type_mismatch' }; }

  if (clientData.type !== 'webauthn.get') return { ok: false, reason: 'type_mismatch' };
  if (clientData.origin !== input.expectedOrigin) {
    return { ok: false, reason: 'origin_mismatch' };
  }
  // Constant-time challenge compare; a timing oracle here is a challenge oracle.
  const gotCh = Buffer.from(clientData.challenge ?? '', 'utf8');
  const wantCh = Buffer.from(input.expectedChallenge, 'utf8');
  if (gotCh.length !== wantCh.length || !timingSafeEqual(gotCh, wantCh)) {
    return { ok: false, reason: 'challenge_mismatch' };
  }

  const authData = b64u(input.assertion.authenticatorData);
  if (authData.length < 37) return { ok: false, reason: 'rpid_mismatch' };
  const rpIdHash = authData.subarray(0, 32);
  if (rpIdHash.length !== input.expectedRpIdHash.length ||
      !timingSafeEqual(rpIdHash, input.expectedRpIdHash)) {
    return { ok: false, reason: 'rpid_mismatch' };
  }
  const flags = authData[32];
  if ((flags & 0x01) === 0) return { ok: false, reason: 'user_not_present' };
  const signCount = authData.readUInt32BE(33);

  // Signed payload is authenticatorData || sha256(clientDataJSON).
  const clientHash = createHash('sha256')
    .update(b64u(input.assertion.clientDataJSON)).digest();
  const v = createVerify('sha256');
  v.update(Buffer.concat([authData, clientHash]));
  v.end();
  let sigOk = false;
  try { sigOk = v.verify(createPublicKey(c.publicKeyPem), b64u(input.assertion.signature)); }
  catch { sigOk = false; }
  if (!sigOk) return { ok: false, reason: 'bad_signature' };

  // Replay guard. A counter that never increases is either a cloned key or a
  // replayed assertion; either way the ceremony must fail.
  if (signCount !== 0 && signCount <= c.signCount) {
    return { ok: false, reason: 'signcount_replay' };
  }
  return { ok: true, newSignCount: signCount };
}

export function newChallenge(): string {
  return randomBytes(32).toString('base64url');
}

// ------------------------------------------------------- principal issuance --
export interface VerifiedPrincipal {
  readonly verified: true;
  readonly userId: string | null;
  readonly roleName: string;
  readonly childId: string | null;
  readonly escalated: boolean;
  readonly expiresAt: number;
}

export const SESSION_TTL_MS = 60 * 60 * 1000;        // 1h ordinary session
export const ESCALATION_TTL_MS = 15 * 60 * 1000;     // §8.3

/**
 * Sessions are signed, not stored — but they are **short** and carry no
 * authority beyond identity. Every authorization decision re-reads the
 * guardianship edge (§5.19 I4), so a stale session cannot outlive a revoked
 * edge. That property is what makes a stateless token safe here.
 */
export function issueSession(
  secret: Buffer,
  p: Omit<VerifiedPrincipal, 'verified' | 'expiresAt'>,
  now: number,
  ttlMs = SESSION_TTL_MS,
): string {
  const body = { ...p, exp: now + ttlMs };
  const payload = Buffer.from(JSON.stringify(body)).toString('base64url');
  const mac = createHmac('sha256', secret).update(payload).digest('base64url');
  return `${payload}.${mac}`;
}

export function readSession(
  secret: Buffer, token: string, now: number,
): { ok: true; principal: VerifiedPrincipal } | { ok: false; reason: string } {
  const dot = token.lastIndexOf('.');
  if (dot < 1) return { ok: false, reason: 'malformed' };
  const payload = token.slice(0, dot);
  const mac = Buffer.from(token.slice(dot + 1), 'base64url');
  const expect = createHmac('sha256', secret).update(payload).digest();
  if (mac.length !== expect.length || !timingSafeEqual(mac, expect)) {
    return { ok: false, reason: 'bad_signature' };
  }
  let body: any;
  try { body = JSON.parse(Buffer.from(payload, 'base64url').toString('utf8')); }
  catch { return { ok: false, reason: 'malformed' }; }
  if (typeof body.exp !== 'number' || body.exp <= now) {
    return { ok: false, reason: 'expired' };
  }
  if (body.roleName === 'child' && !body.childId) {
    return { ok: false, reason: 'child_without_child_id' };
  }
  if (body.roleName !== 'child' && !body.userId) {
    return { ok: false, reason: 'actor_without_user_id' };
  }
  return {
    ok: true,
    principal: {
      verified: true, userId: body.userId ?? null, roleName: body.roleName,
      childId: body.childId ?? null, escalated: Boolean(body.escalated),
      expiresAt: body.exp,
    },
  };
}

/** §8.3 — escalation requires both factors and expires on its own clock. */
export function escalateSession(
  secret: Buffer, p: VerifiedPrincipal,
  pinOk: boolean, biometricOk: boolean, now: number,
): { ok: true; token: string } | { ok: false; reason: 'pin' | 'biometric' | 'role' } {
  if (p.roleName === 'child') return { ok: false, reason: 'role' };
  if (!pinOk) return { ok: false, reason: 'pin' };
  if (!biometricOk) return { ok: false, reason: 'biometric' };
  return {
    ok: true,
    token: issueSession(secret, {
      userId: p.userId, roleName: p.roleName, childId: p.childId, escalated: true,
    }, now, ESCALATION_TTL_MS),
  };
}
