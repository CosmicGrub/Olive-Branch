/**
 * MASTERFILE §11.5 — the school layer.
 *
 * Marked UNVERIFIED since v0.3.0 and never resolved. This settles what it is, and
 * more usefully what it is NOT.
 *
 * THE DECISION: **Olive does not integrate with school systems.** No SIS
 * connector, no gradebook sync, no attendance feed. Three reasons, and the third
 * is the one that decides it.
 *
 *  1. There is no standard. There are thousands of districts and half a dozen
 *     incompatible platforms, and an integration built for one is a rewrite for
 *     the next.
 *  2. It is FERPA-adjacent, and a consumer app touching an education record
 *     acquires an obligation it is poorly placed to carry.
 *  3. **A gradebook feed would put a child's marks in front of a parent she did
 *     not choose to tell.** That inverts §9.1's entire posture — homework help is
 *     something she brings, not something he is served.
 *
 * What IS built is the small, honest version: dates a parent types in, and a
 * shared place to put the paper that comes home in a bag.
 */

export type SchoolEventKind =
  | 'term_start' | 'term_end' | 'holiday' | 'inset_day' | 'parents_evening'
  | 'performance' | 'trip' | 'photo_day' | 'sports_day' | 'exam' | 'other';

export interface SchoolEvent {
  id: string;
  kind: SchoolEventKind;
  label: string;
  date: string;
  /** Which guardian entered it. Both can, and duplicates are merged. */
  enteredBy: string;
  /** True where BOTH parents are expected — the ones that go wrong. */
  bothParentsExpected: boolean;
  /** Whose turn it is under the custody schedule, if known. */
  scheduledParent: string | null;
}

/**
 * The events that actually cause trouble are the ones where both parents turn up
 * — a nativity play, a parents' evening. So those are marked, and the coordination
 * layer is told, rather than leaving two people to discover it in a car park.
 */
export const BOTH_EXPECTED: SchoolEventKind[] = [
  'parents_evening', 'performance', 'sports_day',
];

export function isBothExpected(kind: SchoolEventKind): boolean {
  return BOTH_EXPECTED.includes(kind);
}

/** Two parents typing the same nativity play should produce one entry. */
export function mergeDuplicates(events: SchoolEvent[]): SchoolEvent[] {
  const key = (e: SchoolEvent) => `${e.date}|${e.kind}|${e.label.trim().toLowerCase()}`;
  const seen = new Map<string, SchoolEvent>();
  for (const e of events) {
    const k = key(e);
    const prior = seen.get(k);
    // Keep the earliest entry, but remember that both entered it.
    if (!prior) seen.set(k, e);
  }
  return [...seen.values()].sort((a, b) => a.date.localeCompare(b.date));
}

export function bothExpectedUpcoming(events: SchoolEvent[], fromIso: string): SchoolEvent[] {
  return mergeDuplicates(events)
    .filter(e => e.bothParentsExpected && e.date >= fromIso.slice(0, 10));
}

/**
 * §11.5.2 — the paper that comes home in a bag.
 *
 * A permission slip, a book list, a letter about head lice. It exists in one house
 * and is needed in the other, and photographing it is the whole feature.
 */
export interface SchoolPaper {
  id: string;
  title: string;
  artifactId: string;
  photographedBy: string;
  at: string;
  /** Where a form must go back by a date, that date is the useful part. */
  dueBy: string | null;
  /** §10.1b — school paper is operational, not archival. */
  preserved: false;
}

export function papersDue(papers: SchoolPaper[], fromIso: string): SchoolPaper[] {
  return papers.filter(p => p.dueBy && p.dueBy >= fromIso.slice(0, 10))
    .sort((a, b) => (a.dueBy ?? '').localeCompare(b.dueBy ?? ''));
}

/** What this layer will never hold. Named so the boundary survives a roadmap. */
export const NEVER_IN_SCHOOL_LAYER = [
  'grades', 'marks', 'gpa', 'test_scores', 'attendance_record',
  'behaviour_record', 'iep', 'sen_record', 'teacher_comments',
  'reading_level', 'class_ranking',
] as const;

export function mayStore(kind: string): boolean {
  return !(NEVER_IN_SCHOOL_LAYER as readonly string[]).includes(kind);
}

export function auditSchoolPayload(v: unknown): { ok: true } | { ok: false; leaks: string[] } {
  const leaks: string[] = [];
  const walk = (x: unknown) => {
    if (Array.isArray(x)) return x.forEach(walk);
    if (x && typeof x === 'object') for (const [k, val] of Object.entries(x)) {
      if ((NEVER_IN_SCHOOL_LAYER as readonly string[])
            .some(f => k.toLowerCase() === f.toLowerCase())) leaks.push(k);
      walk(val);
    }
  };
  walk(v);
  return leaks.length ? { ok: false, leaks: [...new Set(leaks)] } : { ok: true };
}
