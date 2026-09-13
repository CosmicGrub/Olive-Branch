/**
 * MASTERFILE §9.6.3 — the emergency card.
 *
 * A screen existed in MARKUP from v0.6.0. There was no engine behind it, which
 * meant the one surface in this product that might matter at 3 a.m. was a
 * picture.
 *
 * DESIGN CONSTRAINT: it must work when everything else does not. No network, no
 * PIN, no session, no unlock. A card that requires authentication is a card that
 * fails in exactly the situation it exists for.
 */

export type ContactKind =
  | 'guardian' | 'emergency_services' | 'doctor' | 'dentist' | 'poison_control'
  | 'school' | 'nurse' | 'named_adult' | 'insurance';

export interface Contact {
  kind: ContactKind;
  label: string;
  /** Stored plainly on device. Encrypted-at-rest is right; unreachable is not. */
  number: string;
  /** Shown under the number, because a panicking adult needs the context. */
  note: string | null;
}

export interface MedicalFact {
  kind: 'allergy' | 'condition' | 'medication' | 'blood_type' | 'note';
  text: string;
  /** Severe allergies sort to the top and are visually marked. */
  critical: boolean;
}

export interface EmergencyCard {
  childName: string;
  dateOfBirth: string;
  contacts: Contact[];
  medical: MedicalFact[];
  /** Available with no PIN, no network, no session. This is the whole point. */
  requiresAuth: false;
  requiresNetwork: false;
  lastReviewedAt: string | null;
}

export const US_EMERGENCY = '911';
export const US_POISON_CONTROL = '1-800-222-1222';

/**
 * Ordering is the feature. In an emergency nobody reads a list — they tap the
 * first thing. So: services, poison control, then guardians, then everyone else.
 */
const ORDER: ContactKind[] = ['emergency_services', 'poison_control', 'guardian',
  'doctor', 'nurse', 'named_adult', 'school', 'dentist', 'insurance'];

export function orderContacts(cs: Contact[]): Contact[] {
  return [...cs].sort((a, b) => ORDER.indexOf(a.kind) - ORDER.indexOf(b.kind));
}

export function orderMedical(ms: MedicalFact[]): MedicalFact[] {
  return [...ms].sort((a, b) => Number(b.critical) - Number(a.critical));
}

export function buildCard(
  childName: string, dateOfBirth: string,
  contacts: Contact[], medical: MedicalFact[], lastReviewedAt: string | null,
): EmergencyCard {
  // Real, live bug this closes: this used to unconditionally PREPEND the
  // hardcoded US defaults and FILTER OUT any caller-supplied contact of
  // these two kinds — so a guardian's corrected local number, a non-US
  // emergency line, or a building-specific line was silently dropped, with
  // no error, warning, or trace, on the one surface this file's own header
  // says "must work when everything else does not." A guardian-supplied
  // contact of a given kind now wins; the hardcoded default is only used
  // when the guardian hasn't supplied one for that kind.
  const supplied = (kind: 'emergency_services' | 'poison_control') =>
    contacts.find(c => c.kind === kind);
  const withDefaults: Contact[] = [
    supplied('emergency_services')
      ?? { kind: 'emergency_services', label: 'Emergency', number: US_EMERGENCY, note: null },
    supplied('poison_control')
      ?? { kind: 'poison_control', label: 'Poison control', number: US_POISON_CONTROL,
        note: 'Free, 24 hours, and they would rather you called for nothing.' },
    ...contacts.filter(c => c.kind !== 'emergency_services' && c.kind !== 'poison_control'),
  ];
  return { childName, dateOfBirth, contacts: orderContacts(withDefaults),
    medical: orderMedical(medical), requiresAuth: false, requiresNetwork: false,
    lastReviewedAt };
}

/**
 * A card nobody has looked at in a year is probably wrong, and a wrong card is
 * worse than no card. This nudges the guardian, never the child.
 */
export const REVIEW_AFTER_DAYS = 180;

export function needsReview(card: EmergencyCard, nowIso: string): boolean {
  if (!card.lastReviewedAt) return true;
  return (Date.parse(nowIso) - Date.parse(card.lastReviewedAt)) / 86_400_000
    > REVIEW_AFTER_DAYS;
}

/**
 * The child-facing version. She can reach it, and she should — but a five-year-old
 * does not need her own blood type, and a list of adult phone numbers with medical
 * notes is frightening rather than useful.
 *
 * She gets: who to call, in order, with faces. Nothing clinical.
 */
export function childCard(card: EmergencyCard): {
  people: { label: string; number: string }[]; line: string;
} {
  return {
    people: card.contacts
      .filter(c => c.kind === 'emergency_services' || c.kind === 'guardian'
        || c.kind === 'named_adult')
      .map(c => ({ label: c.label, number: c.number })),
    line: 'If you need a grown-up, tap one of these. It is never the wrong thing to do.',
  };
}

export type CardFault = 'no_guardian' | 'requires_auth' | 'requires_network'
  | 'missing_emergency_number' | 'clinical_detail_shown_to_child';

export function auditCard(card: EmergencyCard): { ok: true } | { ok: false; faults: CardFault[] } {
  const faults: CardFault[] = [];
  if (!card.contacts.some(c => c.kind === 'guardian')) faults.push('no_guardian');
  if ((card as { requiresAuth: boolean }).requiresAuth) faults.push('requires_auth');
  if ((card as { requiresNetwork: boolean }).requiresNetwork) faults.push('requires_network');
  if (!card.contacts.some(c => c.number === US_EMERGENCY)) {
    faults.push('missing_emergency_number');
  }
  const child = childCard(card);
  if (JSON.stringify(child).match(/allerg|blood|dose|mg\b|diagnos/i)) {
    faults.push('clinical_detail_shown_to_child');
  }
  return faults.length ? { ok: false, faults } : { ok: true };
}
