// OLIVE BRANCH — boot-time secret validation (security audit round 2, S-B13).
//
// WHY: `Buffer.from('not-hex-value', 'hex')` is a ZERO-length buffer, so a typo
// in MEDIA_SIGNING_SECRET used to give an empty HMAC key and forgeable signed
// media URLs without a single error; SESSION_SECRET was only checked to be
// non-empty, so `SESSION_SECRET=changeme` booted fine. Both now have to be
// valid hex of at least 32 bytes that is not an obvious placeholder, or the
// process refuses to start.
//
// Development (NODE_ENV=development, which docker-compose.dev.yml sets) and
// test (NODE_ENV=test) are relaxed: the server may use any non-empty
// SESSION_SECRET and may omit MEDIA_SIGNING_SECRET (a random per-boot key).
// A MEDIA_SIGNING_SECRET that IS set must still be valid hex in every
// environment: a typo must never silently become an empty key.

export const MIN_SECRET_BYTES = 32;

/** Hex string -> Buffer, or throws a message naming `name`. No weak-secret checks. */
export function parseHexSecret(raw, name) {
  if (typeof raw !== 'string' || !/^(?:[0-9a-fA-F]{2})+$/.test(raw)) {
    throw new Error(`${name} must be a hex string (e.g. openssl rand -hex 32)`);
  }
  const buf = Buffer.from(raw, 'hex');
  if (buf.length < MIN_SECRET_BYTES) {
    throw new Error(`${name} must be at least ${MIN_SECRET_BYTES} bytes (${MIN_SECRET_BYTES * 2} hex characters); got ${buf.length}`);
  }
  return buf;
}

/** True for a value that is one short block repeated (0000..., abababab..., 11 x32). */
export function looksLikePlaceholder(hex) {
  const s = hex.toLowerCase();
  for (let period = 1; period <= 16; period++) {
    if (s.length % period === 0 && s === s.slice(0, period).repeat(s.length / period)) return true;
  }
  return new Set(s).size <= 4;
}

const RELAXED_ENVS = new Set(['development', 'test']);

/**
 * Validates SESSION_SECRET / SESSION_SECRET_PREVIOUS / MEDIA_SIGNING_SECRET.
 * Returns { sessionSecret: Buffer, previousSessionSecret: Buffer|null,
 * problems: string[], warnings: string[] }. A non-empty `problems` means the
 * caller must exit(2).
 */
export function checkBootSecrets(env = process.env) {
  const relaxed = RELAXED_ENVS.has(env.NODE_ENV ?? '');
  const problems = [], warnings = [];
  let sessionSecret = null, previousSessionSecret = null;

  const session = env.SESSION_SECRET;
  if (!session) {
    problems.push('SESSION_SECRET required');
  } else if (relaxed) {
    sessionSecret = Buffer.from(session, 'utf8');
    warnings.push('SESSION_SECRET strength is not enforced because NODE_ENV=' + env.NODE_ENV);
  } else {
    try {
      const b = parseHexSecret(session, 'SESSION_SECRET');
      if (looksLikePlaceholder(session)) throw new Error('SESSION_SECRET looks like a placeholder; generate one with openssl rand -hex 32');
      sessionSecret = Buffer.from(session, 'utf8');
      void b;
    } catch (e) { problems.push(e.message); }
  }

  // Two-key rotation (S-B16): the previous key only VERIFIES tokens already issued.
  const prev = env.SESSION_SECRET_PREVIOUS;
  if (prev) {
    try {
      parseHexSecret(prev, 'SESSION_SECRET_PREVIOUS');
      if (!relaxed && looksLikePlaceholder(prev)) throw new Error('SESSION_SECRET_PREVIOUS looks like a placeholder');
      previousSessionSecret = Buffer.from(prev, 'utf8');
    } catch (e) { problems.push(e.message); }
  }

  const media = env.MEDIA_SIGNING_SECRET;
  if (media) {
    try {
      parseHexSecret(media, 'MEDIA_SIGNING_SECRET');
      if (!relaxed && looksLikePlaceholder(media)) throw new Error('MEDIA_SIGNING_SECRET looks like a placeholder; generate one with openssl rand -hex 32');
    } catch (e) { problems.push(e.message); }
  } else if (!relaxed) {
    problems.push('MEDIA_SIGNING_SECRET required (valid hex, at least 32 bytes)');
  }

  return { sessionSecret, previousSessionSecret, problems, warnings };
}
