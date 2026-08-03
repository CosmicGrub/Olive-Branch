/**
 * MASTERFILE §21 — the maturation ladder, built.
 *
 * Promoted from `SCAFFOLD.ts`, which was types only. This is items 1–3 of the
 * §21.10 sequencing: the grant record, the quieting, letters to self, and reverse
 * banking. Rungs 15, 16, 17 and the deletion at 18 live in their own files
 * because each carries a decision that deserves its own reasoning.
 */

export type Side = 'A' | 'B';

// ============================================= 1. the grant record =========
export type Grant =
  | 'own_list' | 'journal_absolute' | 'own_calendar' | 'publish_availability'
  | 'curate_archive' | 'own_export' | 'everything';

export interface Rung {
  age: number;
  grant: Grant;
  ceremony: string;
  guardianNote: string;
  /** §21.9 answer B: only rungs that change what a parent can SEE notify them. */
  notifiesGuardian: boolean;
  requiresTier?: 1 | 2 | 3;
}

export const LADDER: Rung[] = [
  { age: 10, grant: 'own_list', notifiesGuardian: false,
    ceremony: 'Your list is yours now. Nobody else can change what you put on it.',
    guardianNote: 'Maya now controls her own wants and needs list.' },
  { age: 13, grant: 'journal_absolute', notifiesGuardian: false, requiresTier: 2,
    ceremony: 'Your journal was always private. Now it is private forever.',
    guardianNote: 'Standard privacy tier change at 13. Nothing is required of you.' },
  { age: 14, grant: 'own_calendar', notifiesGuardian: false, requiresTier: 2,
    ceremony: 'You can add your own things to the calendar now.',
    guardianNote: 'Maya can now add and edit her own school and activity events.' },
  { age: 15, grant: 'publish_availability', notifiesGuardian: true, requiresTier: 2,
    ceremony: 'You decide when you are free. They will see what you set.',
    guardianNote: 'Maya now sets her own availability. The ribbon shows what she '
                + 'publishes rather than what we inferred.' },
  { age: 16, grant: 'curate_archive', notifiesGuardian: false, requiresTier: 3,
    ceremony: 'You can decide what stays in your archive, and what gets put away.',
    guardianNote: '' },
  { age: 17, grant: 'own_export', notifiesGuardian: false, requiresTier: 3,
    ceremony: 'You can take a copy of everything, any time, without asking.',
    guardianNote: '' },
  { age: 18, grant: 'everything', notifiesGuardian: true, requiresTier: 3,
    ceremony: 'This is yours now.',
    guardianNote: 'Guardianship has closed. The archive has transferred.' },
];

/**
 * An append-only record. A rung reached is a fact about a date, not a setting —
 * so there is `record()` and there is no `revoke()`, and the absence is the
 * mechanism. Same construction as P7 and P8.
 */
export interface MaturationGrant {
  childId: string;
  grant: Grant;
  age: number;
  reachedAt: string;
  /** Which rung produced it, for the audit trail. */
  rungAge: number;
}

export function recordGrants(
  existing: MaturationGrant[], childId: string, age: number, at: string,
): { grants: MaturationGrant[]; newly: MaturationGrant[] } {
  const have = new Set(existing.map(g => g.grant));
  const newly = LADDER.filter(r => age >= r.age && !have.has(r.grant))
    .map(r => ({ childId, grant: r.grant, age, reachedAt: at, rungAge: r.age }));
  return { grants: [...existing, ...newly], newly };
}

export const holds = (grants: MaturationGrant[], g: Grant) =>
  grants.some(x => x.grant === g);

/** There is no inverse. §21.1. */
export function canGuardianRevoke(): false { return false; }

/**
 * §21.9 answer A, settled: ages are adjustable **upward by mutual consent only,
 * never downward, and never by one guardian alone.**
 *
 * Shifting a rung later is kind to an unusually vulnerable child. Shifting it
 * earlier, or unilaterally, is the obvious lever for a controlling parent — so
 * the function refuses both, and refuses a single-guardian request even when the
 * direction is legitimate.
 */
export type AdjustError = 'earlier_not_permitted' | 'needs_both_guardians' | 'unknown_rung';

export function adjustRung(
  ladder: Rung[], grant: Grant, newAge: number, consentingGuardians: string[],
): { ok: true; ladder: Rung[] } | { ok: false; reason: AdjustError } {
  const rung = ladder.find(r => r.grant === grant);
  if (!rung) return { ok: false, reason: 'unknown_rung' };
  if (newAge < rung.age) return { ok: false, reason: 'earlier_not_permitted' };
  if (consentingGuardians.length < 2) return { ok: false, reason: 'needs_both_guardians' };
  return { ok: true, ladder: ladder.map(r =>
    r.grant === grant ? { ...r, age: newAge } : r) };
}

/**
 * §21.9 answer C: the day after rung 15, announce **once, warmly**, then never
 * mention it again. A permanent banner explaining that a fifteen-year-old now
 * controls her own time would be a daily reminder that she once did not.
 */
export function guardianAnnouncement(newly: MaturationGrant[]): string | null {
  const notifying = newly.filter(g =>
    LADDER.find(r => r.grant === g.grant)?.notifiesGuardian);
  if (!notifying.length) return null;
  return LADDER.find(r => r.grant === notifying[0].grant)!.guardianNote || null;
}

// ================================================ 2. the quieting ==========
export interface Scaffold { feature: string; fadesAt: number; why: string }

export const QUIETING: Scaffold[] = [
  { feature: 'sleeps_countdown', fadesAt: 11,
    why: 'She can read a calendar. Counting sleeps for her is talking down.' },
  { feature: 'prompt_decks', fadesAt: 13,
    why: 'A thirteen-year-old does not need a card telling her what to say to her father.' },
  { feature: 'send_time_guard_child_side', fadesAt: 14,
    why: 'She knows what time it is where he lives.' },
  { feature: 'game_prominence', fadesAt: 14,
    why: 'Games move to the back of the app, not out of it.' },
  { feature: 'day_part_labels', fadesAt: 15,
    why: 'Superseded by her published availability.' },
  { feature: 'handicap_offer', fadesAt: 15,
    why: 'Offering to handicap a parent to a fifteen-year-old reads as pity.' },
  { feature: 'ritual_reminders', fadesAt: 16,
    why: 'A ritual she still wants at sixteen is one she keeps herself.' },
];

export const PERMANENT = [
  'calendar', 'call', 'archive', 'journal', 'coordination_layer_guardian_side',
] as const;

export const scaffoldsAt = (age: number) =>
  QUIETING.filter(s => age < s.fadesAt).map(s => s.feature);

export const showsScaffold = (feature: string, age: number) => {
  const s = QUIETING.find(x => x.feature === feature);
  return s ? age < s.fadesAt : true;
};

/**
 * THE ASYMMETRY THAT MATTERS, and the one the whole quieting turns on.
 *
 * The send-time guard fades on HER side at fourteen — she knows what time it is
 * where he lives, and guarding her is patronising. **It never fades on his.**
 *
 * A parent messaging a sleeping child at 2am is a different act from a teenager
 * messaging a parent at 2am, and no amount of her growing up changes that. The
 * guard exists to protect her sleep, not to teach her manners.
 */
export function sendGuardApplies(side: Side, childAge: number): boolean {
  if (side === 'B') return true;                        // the guardian: always
  return showsScaffold('send_time_guard_child_side', childAge);
}

/** Everything still shown to her, for a surface deciding what to render. */
export function surfacesAt(age: number): { faded: string[]; showing: string[]; permanent: string[] } {
  return {
    faded: QUIETING.filter(s => age >= s.fadesAt).map(s => s.feature),
    showing: scaffoldsAt(age),
    permanent: [...PERMANENT],
  };
}

// ========================================= 3a. letters to her future self ==
export interface Letter {
  id: string;
  childId: string;
  writtenAtAge: number;
  openAtAge: number;
  artifactId: string;
  writtenAt: string;
  preserved: true;
  openedAt: string | null;
}

export const MIN_SEAL_YEARS = 1;
export const MAX_SEAL_TO_AGE = 25;

export type SealError = 'too_soon' | 'too_far' | 'not_yet' | 'already_open';

/**
 * Sealed at nine, opened at eighteen.
 *
 * `preserved` is a literal `true`: a letter on a 90-day retention clock is a lost
 * letter, and there is no configuration in which that would be acceptable.
 */
export function sealLetter(
  id: string, childId: string, writtenAtAge: number, openAtAge: number,
  artifactId: string, at: string,
): { ok: true; letter: Letter } | { ok: false; reason: SealError } {
  if (openAtAge - writtenAtAge < MIN_SEAL_YEARS) return { ok: false, reason: 'too_soon' };
  if (openAtAge > MAX_SEAL_TO_AGE) return { ok: false, reason: 'too_far' };
  return { ok: true, letter: { id, childId, writtenAtAge, openAtAge, artifactId,
    writtenAt: at, preserved: true, openedAt: null } };
}

/**
 * **Nobody can open it early. Not a guardian, and not her.**
 *
 * The second half is the interesting one. A sealed letter she can peek at is not
 * sealed, and the whole value of the mechanic is that nine-year-old-her gets to
 * say something eighteen-year-old-her cannot pre-edit.
 *
 * She *can* delete it — it is hers (§2.10) — but she cannot read it early. Delete
 * without read is an unusual permission and it is the correct one here.
 */
export function openLetter(
  l: Letter, currentAge: number, at: string,
): { ok: true; letter: Letter } | { ok: false; reason: SealError; yearsLeft: number } {
  if (l.openedAt) return { ok: false, reason: 'already_open', yearsLeft: 0 };
  if (currentAge < l.openAtAge) {
    return { ok: false, reason: 'not_yet', yearsLeft: l.openAtAge - currentAge };
  }
  return { ok: true, letter: { ...l, openedAt: at } };
}

export function deleteLetter(
  letters: Letter[], id: string, actor: 'child' | 'guardian',
): { ok: true; letters: Letter[] } | { ok: false; reason: 'guardian_cannot_delete' } {
  if (actor === 'guardian') return { ok: false, reason: 'guardian_cannot_delete' };
  return { ok: true, letters: letters.filter(l => l.id !== id) };
}

/** A guardian may know a letter exists, and nothing else about it. */
export function letterGuardianView(l: Letter): { sealed: true; opensAtAge: number } {
  return { sealed: true, opensAtAge: l.openAtAge };
}

export const lettersDue = (letters: Letter[], age: number) =>
  letters.filter(l => !l.openedAt && age >= l.openAtAge);

// ============================================= 3b. reverse banking =========
/**
 * She banks messages **for him** — for his deployment, his birthday, the week she
 * is away.
 *
 * The delivery engine needs no change; only the direction differs. What does need
 * care is the framing.
 */
export interface ChildBank {
  id: string;
  childId: string;
  forUserId: string;
  occasion: string;
  intentIds: string[];
  createdAt: string;
}

export const SUGGESTED_OCCASIONS = [
  'While you are away',
  'For your birthday',
  'For when you land',
  'For a day you need one',
  'For the week I am at Mum\'s',
] as const;

export function bankForParent(
  id: string, childId: string, forUserId: string, occasion: string, at: string,
): { ok: true; bank: ChildBank } | { ok: false; reason: 'no_occasion' } {
  if (!occasion.trim()) return { ok: false, reason: 'no_occasion' };
  return { ok: true, bank: { id, childId, forUserId, occasion: occasion.trim(),
    intentIds: [], createdAt: at } };
}

export function addToBank(b: ChildBank, intentId: string): ChildBank {
  return { ...b, intentIds: [...b.intentIds, intentId] };
}

/**
 * **A child banking messages for a parent must never become an obligation.**
 *
 * "You have not recorded anything for Dad's deployment" turns a gift into
 * homework, and a child who feels she owes her father a video will send a worse
 * one. So there is no target, no reminder, no count shown to her, and no empty
 * state implying she should have done more.
 */
export const BANK_FORBIDDEN = [
  'target', 'goal', 'remaining', 'quota', 'suggested', 'expected', 'streak',
  'reminder', 'overdue', 'incomplete', 'progress',
] as const;

export function bankChildView(b: ChildBank): { occasion: string; line: string } {
  const n = b.intentIds.length;
  return { occasion: b.occasion,
    line: n === 0 ? 'Record something whenever you feel like it.'
      : n === 1 ? 'One waiting for him.'
      : `${n} waiting for him.` };
}

export function auditBank(v: unknown): { ok: true } | { ok: false; leaks: string[] } {
  const leaks: string[] = [];
  const walk = (x: unknown) => {
    if (Array.isArray(x)) return x.forEach(walk);
    if (x && typeof x === 'object') for (const [k, val] of Object.entries(x)) {
      if ((BANK_FORBIDDEN as readonly string[])
            .some(f => k.toLowerCase() === f.toLowerCase())) leaks.push(k);
      walk(val);
    }
  };
  walk(v);
  return leaks.length ? { ok: false, leaks: [...new Set(leaks)] } : { ok: true };
}
