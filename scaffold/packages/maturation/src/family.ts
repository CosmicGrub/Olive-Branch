/**
 * MASTERFILE §21.7 (siblings) and §9.14 (teach me something).
 *
 * Two gaps that have been named in the spec for several increments without being
 * built. The sibling one is a risk the ladder created: a family with three
 * children now has three handovers across six years, and the guardian shell has
 * to survive losing them one at a time.
 */

export type Side = 'A' | 'B';

// ================================================ siblings, staggered ======
export interface Child {
  id: string;
  displayName: string;
  birthDate: string;
  /** Null while guardianship is open. */
  guardianshipClosedAt: string | null;
  colourId: string | null;
}

export interface SiblingSet {
  /** Ordered oldest first — the order they will leave in. */
  children: Child[];
}

export function ageOf(c: Child, now: Date): number {
  const b = new Date(c.birthDate);
  let a = now.getUTCFullYear() - b.getUTCFullYear();
  const m = now.getUTCMonth() - b.getUTCMonth();
  if (m < 0 || (m === 0 && now.getUTCDate() < b.getUTCDate())) a--;
  return a;
}

export const openChildren = (s: SiblingSet) =>
  s.children.filter(c => !c.guardianshipClosedAt);

export const closedChildren = (s: SiblingSet) =>
  s.children.filter(c => c.guardianshipClosedAt);

/**
 * Guardianship closes **per child**, never per family.
 *
 * This is the sentence the whole feature turns on. A parent whose eldest turns
 * eighteen has not stopped being a parent, and a shell that treats one closure as
 * the end of the relationship would be both wrong and cruel.
 */
export function closeFor(
  s: SiblingSet, childId: string, at: string,
): { ok: true; set: SiblingSet; remaining: number } | { ok: false; reason: 'unknown_child' | 'already_closed' } {
  const c = s.children.find(x => x.id === childId);
  if (!c) return { ok: false, reason: 'unknown_child' };
  if (c.guardianshipClosedAt) return { ok: false, reason: 'already_closed' };
  const set = { children: s.children.map(x =>
    x.id === childId ? { ...x, guardianshipClosedAt: at } : x) };
  return { ok: true, set, remaining: openChildren(set).length };
}

/**
 * §21.7 — the surface nobody had designed: what a parent sees the week his eldest
 * leaves, while two younger ones are still here.
 *
 * The tone is the whole thing. This is not an offboarding flow and it is not a
 * bereavement; it is a fact stated once, alongside the plain business of the
 * children who are still on the schedule.
 */
export interface StaggerNotice {
  leavingName: string;
  remaining: string[];
  line: string;
  /** Shown once, on the day. Never again. */
  showOnce: true;
}

export function staggerNotice(s: SiblingSet, childId: string): StaggerNotice | null {
  const c = s.children.find(x => x.id === childId);
  if (!c || !c.guardianshipClosedAt) return null;
  const rest = openChildren(s).map(x => x.displayName);
  return {
    leavingName: c.displayName,
    remaining: rest,
    line: rest.length === 0
      ? `${c.displayName}'s archive has transferred to her. That is all of them.`
      : rest.length === 1
        ? `${c.displayName}'s archive has transferred to her. ${rest[0]} is still here.`
        : `${c.displayName}'s archive has transferred to her. ${rest.slice(0, -1).join(', ')} and ${rest[rest.length - 1]} are still here.`,
    showOnce: true,
  };
}

/** Copy that must never appear when a child ages out. */
export const STAGGER_FORBIDDEN = [
  'no longer', 'lost access', 'removed', 'terminated', 'expired', 'downgrade',
  'you have lost', 'goodbye', 'sorry to see', 'ended',
] as const;

export function auditStagger(n: StaggerNotice): { ok: true } | { ok: false; found: string[] } {
  const t = n.line.toLowerCase();
  const found = (STAGGER_FORBIDDEN as readonly string[]).filter(w => t.includes(w));
  return found.length ? { ok: false, found } : { ok: true };
}

/**
 * A sibling link **survives** closure. She and her brother are still siblings at
 * thirty, and the archive should still be able to say so.
 */
export function siblingsOf(s: SiblingSet, childId: string): Child[] {
  return s.children.filter(c => c.id !== childId);
}

/**
 * The guardian shell has to switch between children without pretending they are
 * interchangeable — each carries her own colour (§8.6) and her own age.
 */
export function shellTabs(s: SiblingSet, now: Date): {
  id: string; name: string; age: number; colourId: string | null; open: boolean;
}[] {
  return s.children.map(c => ({ id: c.id, name: c.displayName,
    age: ageOf(c, now), colourId: c.colourId,
    open: !c.guardianshipClosedAt }));
}

// ============================================= teach me something ==========
/**
 * §9.14 — the parent is the curriculum.
 *
 * Every educational feature so far treats learning as something she does and he
 * supervises: homework help has an expertise gradient, and §9.1 had to invent the
 * *hint, never solve* guard precisely to stop that gradient becoming corrosive.
 *
 * This inverts it. **He knows how to do things**, and teaching is the most
 * natural form of presence there is. Five minutes, once a week, whatever he
 * actually knows — which costs nothing to build because the canvas, the recording
 * and the showcase already exist.
 */
export type TeachMedium = 'demonstrate' | 'draw' | 'record' | 'do_together';

export interface Lesson {
  id: string;
  fromUserId: string;
  title: string;
  medium: TeachMedium;
  /** Whether it worked is a matter for them, not a score. */
  taughtAt: string;
  artifactId: string | null;
  /** She can ask to be taught it again. That is the only metric here. */
  askedAgain: number;
}

export const LESSON_SEEDS = [
  'How to tie a bowline', 'Why the sky goes red at sunset',
  'A card trick', 'How to whistle with two fingers',
  'The names of three clouds', 'How to fold a paper aeroplane that actually flies',
  'What the moon is doing this week', 'How to skim a stone',
  'A word in another language you use every day',
  'How to tell if bread is done', 'Where our name comes from',
  'How to draw a horse that looks like a horse',
  'What I did at work today, properly explained',
  'How a lock works', 'Why boats float', 'A song I know all the words to',
] as const;

/**
 * The reversal, and the reason §21.5 lists this as the one feature that gets
 * BETTER as she ages: from about eight she can teach him, and by fourteen she
 * will be better at something than he is.
 */
export interface ChildLesson extends Lesson { fromChild: true }

export function teach(
  id: string, fromUserId: string, title: string, medium: TeachMedium, at: string,
): { ok: true; lesson: Lesson } | { ok: false; reason: 'no_title' } {
  if (!title.trim()) return { ok: false, reason: 'no_title' };
  return { ok: true, lesson: { id, fromUserId, title: title.trim(), medium,
    taughtAt: at, artifactId: null, askedAgain: 0 } };
}

export function askAgain(lessons: Lesson[], id: string): Lesson[] {
  return lessons.map(l => l.id === id ? { ...l, askedAgain: l.askedAgain + 1 } : l);
}

/**
 * A lesson she asked for twice is the signal worth acting on — the same rule as
 * a story (§9.11.2), and for the same reason: asking again is the only honest
 * measure a child gives you.
 */
export function lessonArtifact(l: Lesson): { title: string; preserved: true } | null {
  return l.askedAgain >= 1 ? { title: l.title, preserved: true } : null;
}

export function whoTeachesWhom(childAge: number): {
  parentTeaches: boolean; childTeaches: boolean; note: string;
} {
  return {
    parentTeaches: true,
    childTeaches: childAge >= 6,
    note: childAge >= 6
      ? 'Both. Let her teach you something and be genuinely taught — pretending is '
      + 'detected instantly.'
      : 'Mostly you, for now. She will start teaching you at about six.',
  };
}

/** No grading, ever. This is the feature where the temptation is strongest. */
export const TEACH_FORBIDDEN = [
  'score', 'grade', 'level', 'mastery', 'progress', 'passed', 'failed',
  'assessment', 'quiz', 'test', 'correct', 'incorrect', 'streak',
] as const;

export function auditLesson(v: unknown): { ok: true } | { ok: false; leaks: string[] } {
  const leaks: string[] = [];
  const walk = (x: unknown) => {
    if (Array.isArray(x)) return x.forEach(walk);
    if (x && typeof x === 'object') for (const [k, val] of Object.entries(x)) {
      if ((TEACH_FORBIDDEN as readonly string[])
            .some(f => k.toLowerCase() === f.toLowerCase())) leaks.push(k);
      walk(val);
    }
  };
  walk(v);
  return leaks.length ? { ok: false, leaks: [...new Set(leaks)] } : { ok: true };
}
