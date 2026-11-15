// OLIVE BRANCH — input rules for creating a family. Pure, no I/O. Audit G2.
//
// Everything here is attacker-controlled text arriving on an unauthenticated
// route, so every field is checked for TYPE, SHAPE and BOUNDS before it can touch
// SQL, and every refusal names one stable reason code (no echo of the input).
import { DateTime, IANAZone } from 'luxon';

export const MAX_NAME_CHARS = 60;
/** A child must be younger than this; child.majority_age defaults to 18. */
export const MAX_CHILD_AGE_YEARS = 17;

/** Display names: NFC, trimmed and collapsed, 1..max characters (code points), no control characters. */
export function cleanName(v, max = MAX_NAME_CHARS) {
  if (typeof v !== 'string') return null;
  const t = v.normalize('NFC').trim().replace(/\s+/g, ' ');
  if (!t || [...t].length > max) return null;
  // eslint-disable-next-line no-control-regex
  if (/[\u0000-\u001f\u007f-\u009f\u2028\u2029]/.test(t)) return null;
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
