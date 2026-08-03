/**
 * MASTERFILE §8.5 — the child's first run.
 *
 * Three steps: she spells her name, she says how old she is, and she is told who
 * she is here to talk to.
 *
 * Spelling your own name is very often the first thing a child learns to write,
 * so it is the correct opening: the app asks her for the one thing she is
 * already certain she can do. Nothing here may fail, and no step may trap her —
 * every step is skippable, because a five-year-old who cannot get past screen one
 * has been locked out of her father.
 */

export type Side = 'A' | 'B';

// ================================================================= the gate =
/**
 * MASTERFILE §8.5.0 — the entry gate. New in v0.41.0.
 *
 * Raised as an idea to make onboarding "all-inclusive and comprehensive": one
 * unified modal that reads an age and decides whether the device becomes the
 * child's kiosk or the guardian's full app. Evaluated and rejected in that
 * exact form, then rebuilt into something that keeps the underlying goal.
 *
 * AgeStep (§8.5, below) already exists to guard against precisely this
 * failure mode one layer down — a six-year-old who taps 10 must not thereby
 * unlock a privacy tier. Routing FULL GUARDIAN AUTHORITY off a self-reported,
 * unverified age is the same mistake at a far higher stakes level.
 *
 * What ships instead is a role question, not an age gate: two buttons, "my
 * child's device" or "the grown-up's device." Nothing on this screen grants
 * anything.
 *   - Choosing child routes, unchanged, into the existing first-run flow —
 *     begin(), ages 2-17, still feeding §21.
 *   - Choosing grown-up routes to the real account path — passkey/WebAuthn
 *     (§11) — and every guardian capability afterward is still gated exactly
 *     as it always was, by family-graph/authorize.ts's can(), which reads
 *     real edges and has never heard of this screen.
 *
 * A device that already has a child's birth date on record (because a
 * guardian set one up here before) pre-highlights the child button. Absence
 * of a birth date suggests nothing — it never defaults toward guardian.
 *
 * One more thing this screen is not: the child side is not a one-way
 * "receiver." She already sends homework photos, drawings, showcase items,
 * and letters to the guardian side today.
 */
export type EntryRole = 'child' | 'grownup';

export interface EntryChoice {
  role: EntryRole;
}

/** Records the tap. See ENTRY_CHOICE_GRANTS_NO_AUTHORITY — that is all it does. */
export function chooseEntry(role: EntryRole): EntryChoice {
  return { role };
}

/**
 * A suggestion, never an authority. A birth date already on record for this
 * device pre-highlights "child." Its absence suggests nothing — it must
 * never default toward "grownup," so there is no value this can return that
 * reads as steering an unknown device to the guardian side.
 */
export function suggestEntryRole(hasChildBirthDateOnRecord: boolean): EntryRole | null {
  return hasChildBirthDateOnRecord ? 'child' : null;
}

export type EntryRoute = 'child_kiosk' | 'grownup_account_setup';

/**
 * Pure routing, nothing else. "child" leads to the existing begin() flow,
 * unchanged. "grownup" leads to the real account path (passkey/WebAuthn,
 * §11) — every guardian capability past that point is still gated exactly as
 * it always was, by family-graph/authorize.ts's can(), which reads real
 * edges and has never heard of this screen.
 */
export function routeFromEntry(role: EntryRole): EntryRoute {
  return role === 'child' ? 'child_kiosk' : 'grownup_account_setup';
}

/**
 * The invariant this whole screen rests on. Tapping "the grown-up's device"
 * is a routing decision, not a credential — it grants precisely nothing.
 * Real authority is only ever granted by family-graph edges, checked by
 * can(). The test suite proves this directly: it calls the real authorizer
 * with a guardian-role tap and zero edges, and confirms denial.
 */
export const ENTRY_CHOICE_GRANTS_NO_AUTHORITY = true;

// ================================================================= the name =
export interface NameStep {
  /** Exactly what she typed. Not corrected, not title-cased, not validated. */
  spelled: string;
  /** What the guardian entered at setup. Used only if she skips. */
  fallback: string;
  skipped: boolean;
}

export const MAX_NAME_LENGTH = 24;

/**
 * Her spelling stands.
 *
 * If she writes OLIVEE, the app says OLIVEE. Correcting a child's spelling of
 * her own name on the first screen of a product about being known by her father
 * would be a small, precise cruelty — and §21's direction of travel is authority
 * toward the child, starting here. The guardian-entered legal name stays on the
 * record for exports and the emergency card; this is her name inside her app.
 */
export function acceptName(
  typed: string, fallback: string,
): { ok: true; step: NameStep } | { ok: false; reason: 'too_long' } {
  const spelled = typed.slice(0, MAX_NAME_LENGTH);
  if (typed.length > MAX_NAME_LENGTH) return { ok: false, reason: 'too_long' };
  if (!spelled.trim()) {
    return { ok: true, step: { spelled: fallback, fallback, skipped: true } };
  }
  return { ok: true, step: { spelled, fallback, skipped: false } };
}

/** She can change it later, any time, without asking. §21. */
export function renameSelf(step: NameStep, typed: string): NameStep {
  const spelled = typed.slice(0, MAX_NAME_LENGTH).trim();
  return spelled ? { ...step, spelled, skipped: false } : step;
}

// ================================================================== the age =
export interface AgeStep {
  /** What she tapped. NEVER authoritative — see below. */
  selfReported: number | null;
  /** Derived from the guardian-entered birth date. This is the real one. */
  authoritative: number | null;
  /** Recorded rather than silently corrected. */
  disagrees: boolean;
  skipped: boolean;
}

export const MIN_AGE = 2, MAX_AGE = 17;

/**
 * A child's self-reported age is a UX convenience, not a fact.
 *
 * Age gates real things here — which games unlock, the ping band (§9.9), the
 * §21 rung, the §21.5 quieting schedule — and a six-year-old who taps "10"
 * because ten sounds better must not thereby unlock a privacy tier. So the
 * guardian's birth date always wins, the disagreement is RECORDED rather than
 * overwritten, and nothing she taps can raise a gate.
 *
 * This also matters under §10.2: age is a COPPA-relevant fact and cannot rest on
 * a tap by the subject.
 */
export function acceptAge(
  tapped: number | null, birthDate: string | null, now: Date,
): AgeStep {
  const authoritative = birthDate ? ageFrom(birthDate, now) : null;
  if (tapped === null) {
    return { selfReported: null, authoritative, disagrees: false, skipped: true };
  }
  const clamped = Math.max(MIN_AGE, Math.min(MAX_AGE, Math.round(tapped)));
  return { selfReported: clamped, authoritative,
    disagrees: authoritative !== null && authoritative !== clamped,
    skipped: false };
}

export function ageFrom(birthDate: string, now: Date): number {
  const b = new Date(birthDate);
  let a = now.getUTCFullYear() - b.getUTCFullYear();
  const m = now.getUTCMonth() - b.getUTCMonth();
  if (m < 0 || (m === 0 && now.getUTCDate() < b.getUTCDate())) a--;
  return a;
}

/** The age everything else in the product must use. */
export function effectiveAge(step: AgeStep): number | null {
  return step.authoritative ?? step.selfReported;
}

// ================================================================== the who =
export interface Grownup {
  userId: string;
  /** The guardian's OWN word — Daddy, Papa, Baba, Mum, Mama, Nana. */
  label: string;
  /** False until they have accepted the invitation. */
  joined: boolean;
}

export type WhoStep =
  | { kind: 'no_choice'; only: Grownup; line: string }
  | { kind: 'choose'; options: Grownup[]; selected: string[]; line: string }
  | { kind: 'nobody_yet'; line: string };

/**
 * §17.1 — single-guardian mode is the default assumption, so when only one adult
 * is in the family graph **no choice is presented at all**. She is simply told
 * who she is here to talk to.
 *
 * This is not a shortcut. Asking a child to pick between Mummy and Daddy on the
 * first screen of a co-parenting product would be, at best, tactless — and §2.4
 * says the child never sees the machinery of conflict. She is not choosing which
 * parent exists; she is being told who is already here.
 *
 * Labels come from each guardian's own word. Hard-coding "Mommy" and "Daddy"
 * would fail every family that says Papa, Baba, Mama, Mum, or Nana.
 */
export function whoStep(grownups: Grownup[]): WhoStep {
  const joined = grownups.filter(g => g.joined);
  if (joined.length === 0) {
    return { kind: 'nobody_yet',
      line: 'Nobody is here yet. We will let you know when they are.' };
  }
  if (joined.length === 1) {
    return { kind: 'no_choice', only: joined[0],
      line: `You're here to talk to ${joined[0].label}.` };
  }
  return { kind: 'choose', options: joined,
    // Everyone selected by default. Deselecting is possible; selecting is not
    // a thing she has to earn.
    selected: joined.map(g => g.userId),
    line: 'Who are you here to talk to?' };
}

export function toggleWho(step: WhoStep, userId: string): WhoStep {
  if (step.kind !== 'choose') return step;
  const has = step.selected.includes(userId);
  const next = has ? step.selected.filter(x => x !== userId) : [...step.selected, userId];
  // §2.12 — she may never end up with nobody. The last one cannot be turned off.
  return next.length === 0 ? step : { ...step, selected: next };
}

// =============================================================== the flow ===
export type StepName = 'name' | 'age' | 'colour' | 'birthday' | 'who' | 'done';

export interface Onboarding {
  step: StepName;
  name: NameStep | null;
  age: AgeStep | null;
  /** §8.6 — her colour. Skippable like everything else. */
  colourId: string | null;
  /** §8.7 — the birthday she placed on the calendar herself. */
  birthday: string | null;
  who: WhoStep | null;
}

export function begin(): Onboarding {
  return { step: 'name', name: null, age: null, colourId: null,
           birthday: null, who: null };
}

/**
 * Advance. Every step is skippable and no step can fail — a child who cannot get
 * past screen one has been locked out of her father, which is the worst outcome
 * this product can produce.
 */
export function advance(
  o: Onboarding,
  input: { name?: string; age?: number | null; grownups?: Grownup[];
           birthDate?: string | null; now?: Date; colourId?: string | null;
           birthday?: string | null },
): Onboarding {
  const now = input.now ?? new Date();
  if (o.step === 'name') {
    const r = acceptName(input.name ?? '', 'you');
    const step = r.ok ? r.step
      : { spelled: (input.name ?? '').slice(0, MAX_NAME_LENGTH), fallback: 'you', skipped: false };
    return { ...o, name: step, step: 'age' };
  }
  if (o.step === 'age') {
    return { ...o, age: acceptAge(input.age ?? null, input.birthDate ?? null, now),
      step: 'colour' };
  }
  if (o.step === 'colour') {
    // Skipping is fine. A child with no colour simply has no colour, and the
    // app looks exactly as it did before.
    return { ...o, colourId: input.colourId ?? null, step: 'birthday' };
  }
  if (o.step === 'birthday') {
    // Skippable too. The guardian's date remains of record either way; what she
    // loses by skipping is only the act of placing it herself.
    return { ...o, birthday: input.birthday ?? null, step: 'who' };
  }
  if (o.step === 'who') {
    return { ...o, who: whoStep(input.grownups ?? []), step: 'done' };
  }
  return o;
}

export function goBack(o: Onboarding): Onboarding {
  const order: StepName[] = ['name', 'age', 'colour', 'birthday', 'who', 'done'];
  const i = order.indexOf(o.step);
  return i <= 0 ? o : { ...o, step: order[i - 1] };
}

/** The greeting on her home screen, forever after. */
export function greeting(o: Onboarding): string {
  const n = o.name?.spelled?.trim();
  return n && n !== 'you' ? `Hi ${n}` : 'Hi';
}

/**
 * What onboarding is allowed to have decided. Everything else — privacy tier,
 * ladder rung, ping band — reads `effectiveAge`, which prefers the guardian's
 * birth date. Nothing a child taps can raise a gate.
 */
export function outcome(o: Onboarding): {
  displayName: string; effectiveAge: number | null; colourId: string | null;
  birthday: string | null; talkingTo: string[]; ageWasSelfReportedOnly: boolean;
} {
  const age = o.age ? effectiveAge(o.age) : null;
  const who = o.who;
  return {
    displayName: o.name?.spelled ?? 'you',
    effectiveAge: age,
    colourId: o.colourId,
    birthday: o.birthday,
    talkingTo: who?.kind === 'no_choice' ? [who.only.userId]
      : who?.kind === 'choose' ? who.selected : [],
    ageWasSelfReportedOnly: Boolean(o.age && o.age.authoritative === null
      && o.age.selfReported !== null),
  };
}

/** Copy in this flow must not be tested against, praised, or corrected. */
export const ONBOARDING_FORBIDDEN = [
  'correct', 'incorrect', 'wrong', 'try again', 'oops', 'invalid',
  'well done', 'good job', 'nearly', 'almost',
] as const;

export function auditOnboardingCopy(text: string): { ok: true } | { ok: false; found: string[] } {
  const t = text.toLowerCase();
  const found = (ONBOARDING_FORBIDDEN as readonly string[]).filter(w => t.includes(w));
  return found.length ? { ok: false, found } : { ok: true };
}
