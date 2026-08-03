/**
 * MASTERFILE §9.10.7–§9.10.11 — closing the gaps in "show me".
 *
 * The module shipped in v0.22.0 pointed one way. Seven of its eight show types
 * were child→parent, which made it a feature about a child performing for an
 * absent adult. These five additions turn it into an exchange.
 */

export type Side = 'A' | 'B';

// =========================================== §9.10.7 the pending ask ========
/**
 * A prompt she has to go looking for is a menu. A prompt waiting for her, from
 * her father, by name, is a message.
 *
 * THE DESIGN PROBLEM: if he asks six things and she answers none, the app has
 * built her a backlog of disappointment. So pending asks are **capped**, the
 * oldest falls off **silently**, and no count is ever shown to her.
 */
export interface Ask {
  id: string;
  fromUserId: string;
  fromLabel: string;          // "Daddy" — his own word (§8.5.3)
  prompt: string;
  askedAt: string;
  answeredWithShowId: string | null;
}

/** Three. A fourth pushes the oldest out rather than stacking. */
export const MAX_PENDING_ASKS = 3;

export function askForShow(
  pending: Ask[], ask: Omit<Ask, 'answeredWithShowId'>,
): { asks: Ask[]; displaced: Ask | null } {
  const open = pending.filter(a => !a.answeredWithShowId);
  const next = [...open, { ...ask, answeredWithShowId: null }];
  if (next.length <= MAX_PENDING_ASKS) return { asks: next, displaced: null };
  // Oldest out, and she is never told it happened.
  const [displaced, ...kept] = next;
  return { asks: kept, displaced };
}

export function answerAsk(pending: Ask[], askId: string, showId: string): Ask[] {
  return pending.map(a => a.id === askId ? { ...a, answeredWithShowId: showId } : a);
}

/**
 * What she sees. No count, no age, no "2 unanswered" — an ask that has been
 * waiting four days looks exactly like one from this morning.
 */
export function asksChildView(pending: Ask[]): { line: string; prompt: string }[] {
  return pending.filter(a => !a.answeredWithShowId)
    .map(a => ({ line: `${a.fromLabel} asked you something`, prompt: a.prompt }));
}

/** Fields that would turn an ask list into a chore list. */
export const ASK_FORBIDDEN = [
  'unanswered', 'pending', 'count', 'waiting', 'overdue', 'daysAgo',
  'age', 'ignored', 'streak',
] as const;

// ==================================== §9.10.8 reply in kind ================
/**
 * The matrix already says *reply in kind, not in words*. Nothing enforced it, and
 * "nice!" is what a tired parent types at eleven at night.
 *
 * This does not refuse a text reply — refusing would mean some shows go
 * unanswered, which is worse. It **nudges**, once, with the reason.
 */
export type ReplyKind = 'artifact' | 'text' | 'voice';

export interface ReplyGuidance {
  preferred: ReplyKind[];
  nudge: string | null;
}

export function replyGuidance(showKind: string, proposed: ReplyKind): ReplyGuidance {
  const inKindOnly = ['spontaneous', 'creation', 'collection'];
  if (!inKindOnly.includes(showKind)) return { preferred: ['text', 'voice', 'artifact'], nudge: null };
  if (proposed === 'text') {
    return { preferred: ['artifact', 'voice'],
      nudge: 'She sent you a thing, not a sentence. Send one back — a photo of '
           + 'anything, or say it out loud. "Nice!" is the reply that ends it.' };
  }
  return { preferred: ['artifact', 'voice'], nudge: null };
}

// ======================================== §9.10.9 the shelf ================
export interface ShelfEntry {
  interestId: string;
  label: string;
  count: number;              // parent side only
  newest: string | null;
  lastAddedAt: string | null;
}

/**
 * All her collections in one place, most recently added to first — because the
 * one she is filling now is the one she wants.
 *
 * Counts are on the shelf for the parent (they are how he knows what she has been
 * doing); `shelfChildView` strips them. P2.
 */
export function shelf(
  collections: { interestId: string; entries: { name: string; shownAt: string }[] }[],
  interests: { id: string; label: string }[],
): ShelfEntry[] {
  return collections.map(c => {
    const last = [...c.entries].sort((a, b) => b.shownAt.localeCompare(a.shownAt))[0];
    return { interestId: c.interestId,
      label: interests.find(i => i.id === c.interestId)?.label ?? 'things',
      count: c.entries.length,
      newest: last?.name ?? null,
      lastAddedAt: last?.shownAt ?? null };
  }).sort((a, b) => (b.lastAddedAt ?? '').localeCompare(a.lastAddedAt ?? ''));
}

export function shelfChildView(entries: ShelfEntry[]): { label: string; newest: string | null }[] {
  return entries.map(e => ({ label: e.label, newest: e.newest }));
}

// ================================= §9.10.10 he shows her his world =========
/**
 * The gap that mattered most. A child who has never seen her father's flat cannot
 * picture him anywhere — and a product about presence that only carries her
 * outwards has the arrow the wrong way round.
 *
 * `where_you_sleep` is the important one, and it is why this exists. A child who
 * knows which bed is hers at the other house arrives differently.
 */
export type ParentShowKind =
  | 'where_you_sleep' | 'my_room' | 'the_kitchen' | 'the_view'
  | 'walk_to_work' | 'something_of_mine' | 'something_i_made'
  | 'where_we_will_go' | 'someone_you_will_meet';

export interface ParentShow {
  kind: ParentShowKind;
  title: string;
  /** Why it is worth him doing. Shown to HIM, not to her. */
  because: string;
  /** Offered even before she asks — see `offerable`. */
  offerable: boolean;
  minAge: number;
}

export const PARENT_SHOWS: ParentShow[] = [
  { kind: 'where_you_sleep', title: 'Where you sleep here', minAge: 2, offerable: true,
    because: 'A child who knows which bed is hers arrives differently. If she has '
           + 'not been yet, this is the single most useful thing you can send.' },
  { kind: 'my_room', title: 'My room', minAge: 2, offerable: true,
    because: 'She cannot picture you anywhere. Give her somewhere to put you.' },
  { kind: 'the_kitchen', title: 'My kitchen', minAge: 3, offerable: true,
    because: 'It is where you will eat together. It also makes Kim\'s game work.' },
  { kind: 'the_view', title: 'What I can see out of the window', minAge: 3, offerable: true,
    because: 'Weather, a street, a tree. Small and oddly reassuring.' },
  { kind: 'walk_to_work', title: 'My walk to work', minAge: 4, offerable: true,
    because: 'Where you go when you are not with her, which she thinks about.' },
  { kind: 'something_of_mine', title: 'Something of mine', minAge: 4, offerable: true,
    because: 'Preferably old. Children are fascinated by proof you existed before '
           + 'them.' },
  { kind: 'something_i_made', title: 'Something I made', minAge: 4, offerable: true,
    because: 'It puts you on the same footing as her, which is rarer than it '
           + 'should be.' },
  { kind: 'where_we_will_go', title: 'Where we will go next time', minAge: 4, offerable: true,
    because: 'Turns a visit from an event into a plan.' },
  { kind: 'someone_you_will_meet', title: 'Someone you will meet', minAge: 5, offerable: false,
    // Not offerable: a new partner, a new baby, a stepsibling. That belongs to a
    // conversation, not a prompt deck.
    because: 'Only when you have already talked about it. The app will not suggest '
           + 'this one.' },
];

export const parentShowsFor = (age: number) =>
  PARENT_SHOWS.filter(s => age >= s.minAge);

/** Only `offerable` ones are ever suggested by the product. */
export const offerableParentShows = (age: number) =>
  parentShowsFor(age).filter(s => s.offerable);

// ==================================== §9.10.11 the gallery =================
/**
 * Everything she has ever made, in one room.
 *
 * THE POINT, and the reason it is medium-agnostic: **a five-year-old's best work
 * is usually made of cardboard and glue.** A gallery that held only digital
 * paintings would quietly tell her that the things she is proudest of do not
 * count. So a photograph of a physical model hangs exactly as a canvas drawing
 * does, at the same size, with no badge marking it as second class.
 */
export type Medium =
  | 'digital_paint'      // the §9.1 canvas
  | 'colouring'          // §9.12.1, finished
  | 'photo_of_physical'  // cardboard, glue, paint, Lego, a cake
  | 'collage'
  | 'photo_she_took';

export interface Work {
  id: string;
  artifactId: string;
  /** Her title, if she gave one. Not required — most children do not. */
  title: string | null;
  medium: Medium;
  madeAt: string;
  /** §9.10.3 — what she was into when she made it. */
  interestId: string | null;
  /** From 16 she can hide a work (§21.2 rung). Guardians never can. */
  hiddenByChild: boolean;
  preserved: true;
}

export interface GalleryRoom {
  /** A year, because that is how a child's work actually divides. */
  year: number;
  works: Work[];
}

export function gallery(works: Work[], viewer: 'child' | 'guardian'): GalleryRoom[] {
  const visible = works.filter(w => viewer === 'child' || !w.hiddenByChild);
  const byYear = new Map<number, Work[]>();
  for (const w of visible) {
    const y = new Date(w.madeAt).getUTCFullYear();
    byYear.set(y, [...(byYear.get(y) ?? []), w]);
  }
  return [...byYear.entries()]
    .map(([year, ws]) => ({ year,
      works: ws.sort((a, b) => b.madeAt.localeCompare(a.madeAt)) }))
    .sort((a, b) => b.year - a.year);
}

/**
 * Every medium is rendered identically. This function exists so that claim is
 * testable — there is no per-medium size, badge, or ordering weight.
 */
export function frameFor(_w: Work): { width: 1; badge: null; sortWeight: 0 } {
  return { width: 1, badge: null, sortWeight: 0 };
}

/** §21.2 rung 16. A guardian may never hide or unhide a work. */
export function hideWork(
  works: Work[], workId: string, actor: 'child' | 'guardian', hidden: boolean,
): { ok: true; works: Work[] } | { ok: false; reason: 'guardian_cannot_curate' } {
  if (actor === 'guardian') return { ok: false, reason: 'guardian_cannot_curate' };
  return { ok: true, works: works.map(w =>
    w.id === workId ? { ...w, hiddenByChild: hidden } : w) };
}

/**
 * The companion to The Book (§9.11.6): stories bound in one volume, pictures in
 * the other. Both are Christmas presents and both regenerate from stored ids.
 */
export interface Exhibition {
  childName: string;
  title: string;
  plates: { number: number; artifactId: string; caption: string; medium: Medium }[];
  meta: { workCount: number; years: number[]; mediums: Medium[] };
  note: string;
}

export const MIN_WORKS_FOR_EXHIBITION = 8;

export function compileExhibition(
  works: Work[], childName: string,
): { ok: true; exhibition: Exhibition } | { ok: false; reason: 'too_few' } {
  const shown = works.filter(w => !w.hiddenByChild);
  if (shown.length < MIN_WORKS_FOR_EXHIBITION) return { ok: false, reason: 'too_few' };
  // Oldest first, like the book — it should read as a growing-up, not a best-of.
  const ordered = [...shown].sort((a, b) => a.madeAt.localeCompare(b.madeAt));
  return { ok: true, exhibition: {
    childName,
    title: `${childName}'s Pictures`,
    plates: ordered.map((w, i) => ({ number: i + 1, artifactId: w.artifactId,
      caption: w.title ?? `${new Date(w.madeAt).getUTCFullYear()}`, medium: w.medium })),
    meta: { workCount: ordered.length,
      years: [...new Set(ordered.map(w => new Date(w.madeAt).getUTCFullYear()))].sort(),
      mediums: [...new Set(ordered.map(w => w.medium))] },
    note: 'Cardboard counts. It always did.',
  }};
}

/** Nothing in the gallery may rank, score, or grade her work. */
export const GALLERY_FORBIDDEN = [
  'score', 'rating', 'stars', 'grade', 'quality', 'best', 'rank', 'featured',
  'improvement', 'progress', 'skill', 'level',
] as const;

export function auditGallery(v: unknown): { ok: true } | { ok: false; leaks: string[] } {
  const leaks: string[] = [];
  const walk = (x: unknown) => {
    if (Array.isArray(x)) return x.forEach(walk);
    if (x && typeof x === 'object') for (const [k, val] of Object.entries(x)) {
      if ((GALLERY_FORBIDDEN as readonly string[])
            .some(f => k.toLowerCase() === f.toLowerCase())) leaks.push(k);
      walk(val);
    }
  };
  walk(v);
  return leaks.length ? { ok: false, leaks: [...new Set(leaks)] } : { ok: true };
}
