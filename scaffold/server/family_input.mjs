// OLIVE BRANCH — input rules for creating a family. Pure, no I/O. Audit G2.
//
// Everything here is attacker-controlled text arriving on an unauthenticated
// route, so every field is checked for TYPE, SHAPE and BOUNDS before it can touch
// SQL, and every refusal names one stable reason code (no echo of the input).
import { DateTime, IANAZone } from 'luxon';
import { createHash, timingSafeEqual } from 'node:crypto';

export const MAX_NAME_CHARS = 60;
/** A child must be younger than this; child.majority_age defaults to 18. */
export const MAX_CHILD_AGE_YEARS = 17;
export const MIN_SETUP_CODE_CHARS = 16;

/** Display names: trimmed, 1..60 characters, no control characters. */
export function cleanName(v) {
  if (typeof v !== 'string') return null;
  const t = v.normalize('NFC').trim().replace(/\s+/g, ' ');
  if (!t || [...t].length > MAX_NAME_CHARS) return null;
  // eslint-disable-next-line no-control-regex
  if (/[\u0000-\u001f\u007f-\u009f  ]/.test(t)) return null;
  return t;
}

/** An IANA zone name luxon recognises (not an offset, not 'local', not the empty string). */
export function cleanTz(v) {
  if (typeof v !== 'string' || v.length > 64) return null;
  return IANAZone.isValidZone(v) && /^[A-Za-z_]+(?:\/[A-Za-z0-9_+\-]+){0,2}$/.test(v) ? v : null;
}

/** 'YYYY-MM-DD', a real calendar date, not in the future, child under 18. */
export function cleanBirthDate(v, now = DateTime.utc()) {
  if (typeof v !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(v)) return null;
  const d = DateTime.fromISO(v, { zone: 'utc' });
  if (!d.isValid || d.toISODate() !== v) return null;          // rejects 2026-02-30
  if (d > now.startOf('day').plus({ days: 1 })) return null;   // not tomorrow or later
  if (now.diff(d, 'years').years >= MAX_CHILD_AGE_YEARS + 1) return null;
  return v;
}

/**
 * @returns {{ ok: true, value: { displayName: string, birthDate: string, homeTz: string } }
 *          | { ok: false, reason: string }}
 */
export function parseChild(c, now = DateTime.utc()) {
  if (!c || typeof c !== 'object' || Array.isArray(c)) return { ok: false, reason: 'child_required' };
  const displayName = cleanName(c.displayName);
  if (!displayName) return { ok: false, reason: 'child_name_invalid' };
  const birthDate = cleanBirthDate(c.birthDate, now);
  if (!birthDate) return { ok: false, reason: 'child_birth_date_invalid' };
  const homeTz = cleanTz(c.homeTz);
  if (!homeTz) return { ok: false, reason: 'child_time_zone_invalid' };
  return { ok: true, value: { displayName, birthDate, homeTz } };
}

/** POST /v1/families body -> the guardian and child it describes, or one reason code. */
export function parseFamilyBody(b, now = DateTime.utc()) {
  if (!b || typeof b !== 'object' || Array.isArray(b)) return { ok: false, reason: 'bad_request' };
  const g = b.guardian;
  if (!g || typeof g !== 'object' || Array.isArray(g)) return { ok: false, reason: 'guardian_required' };
  const displayName = cleanName(g.displayName);
  if (!displayName) return { ok: false, reason: 'guardian_name_invalid' };
  const homeTz = cleanTz(g.homeTz);
  if (!homeTz) return { ok: false, reason: 'guardian_time_zone_invalid' };
  const child = parseChild(b.child, now);
  if (!child.ok) return child;
  return { ok: true, value: { guardian: { displayName, homeTz }, child: child.value } };
}

/**
 * The operator's setup code (FAMILY_SETUP_CODE) is what makes sign-up invite-only:
 * HOSTING-AND-CALLS asks for "invite-only sign-up with a family cap, a waitlist and
 * a kill switch". The route does not exist unless the code is configured, and
 * removing the code is the kill switch. At least 16 characters so it cannot be
 * guessed inside the miss budget.
 *
 * @returns {{ enabled: boolean, problem: string|null, digest: Buffer|null }}
 */
export function setupCodeConfig(env = process.env) {
  const raw = env.FAMILY_SETUP_CODE;
  if (raw === undefined || raw === '') return { enabled: false, problem: null, digest: null };
  if (typeof raw !== 'string' || raw.length < MIN_SETUP_CODE_CHARS) {
    return { enabled: false, digest: null,
      problem: `FAMILY_SETUP_CODE must be at least ${MIN_SETUP_CODE_CHARS} characters` };
  }
  return { enabled: true, problem: null, digest: createHash('sha256').update(raw, 'utf8').digest() };
}

/** Constant-time comparison of a presented code against the configured digest. */
export function setupCodeMatches(presented, digest) {
  if (typeof presented !== 'string' || presented.length > 256 || !digest) return false;
  const got = createHash('sha256').update(presented, 'utf8').digest();
  return got.length === digest.length && timingSafeEqual(got, digest);
}
