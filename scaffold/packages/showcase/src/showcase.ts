/**
 * MASTERFILE §9.10 — the showcase. "Show me."
 *
 * THE OBSERVATION THIS IS BUILT ON:
 *
 * A child can be highly communicative in person and near-silent on a video call,
 * and the reason is not shyness. In person you share a room — there is always
 * something to point at. Over video the shared referent is gone, and what remains
 * is "how was your day", which is an interview. Children are bad at interviews.
 *
 * **Showing restores the shared referent.** It is not a workaround for a child
 * who will not talk; it is the native register for most children, and this
 * module treats it as first class rather than as a fallback.
 *
 * Nothing here may ever imply she is failing to talk. That framing would take a
 * thing she is good at and re-describe it as a deficiency.
 */

export type Side = 'A' | 'B';   // A = child, B = parent

// =============================================================== the matrix =
export type ShowKind =
  | 'object'      // "show me your favourite one"
  | 'creation'    // "show me what you made"
  | 'knowledge'   // "show me what you learned"
  | 'skill'       // "show me what you can do"
  | 'place'       // "show me where you are"
  | 'collection'  // "show me all of them"
  | 'teach'       // she explains it to him — the reversal
  | 'spontaneous';// "look what happened" — she starts it

export type Initiator = 'child' | 'parent' | 'either';
export type Mode = 'live' | 'async' | 'both';
export type Remains = 'ephemeral' | 'artifact' | 'collection_entry';

export interface ShowType {
  kind: ShowKind;
  title: string;
  minAge: number;
  initiator: Initiator;
  mode: Mode;
  remains: Remains;
  /** What the PARENT is asked to do. The hardest and most important column. */
  parentRole: string;
  why: string;
}

/**
 * The matrix. The `parentRole` column is the one that matters most: a parent who
 * responds to "look at my dinosaur" with "that's nice, how was school" has ended
 * the exchange. Every row tells them what to do instead.
 */
export const MATRIX: ShowType[] = [
  { kind: 'object', title: 'Show me a thing', minAge: 2,
    initiator: 'either', mode: 'both', remains: 'artifact',
    parentRole: 'Ask one specific question about it. Not "is that nice" — '
      + '"which bit is your favourite" or "where did it come from".',
    why: 'The lowest floor of any feature here. A two-year-old can hold something up.' },

  { kind: 'creation', title: 'Show me what you made', minAge: 3,
    initiator: 'child', mode: 'both', remains: 'artifact',
    parentRole: 'Ask how it was made before saying whether you like it. '
      + 'Process before praise.',
    why: 'She chooses what counts as made, which makes it hers.' },

  { kind: 'knowledge', title: 'Show me what you learned', minAge: 4,
    initiator: 'either', mode: 'both', remains: 'artifact',
    parentRole: 'Be told something you did not know, and say so out loud.',
    why: 'The only educational feature where she is the one who knows.' },

  { kind: 'skill', title: 'Show me what you can do', minAge: 3,
    initiator: 'either', mode: 'both', remains: 'artifact',
    parentRole: 'Watch the whole thing. Ask to see it again.',
    why: 'A cartwheel, a scale, a card trick. Progress is visible over months.' },

  { kind: 'place', title: 'Show me where you are', minAge: 3,
    initiator: 'either', mode: 'live', remains: 'ephemeral',
    parentRole: 'Ask about something in the background you have not seen before.',
    why: 'Rebuilds the shared room. Works in both directions — he shows her his.' },

  { kind: 'collection', title: 'Show me all of them', minAge: 5,
    initiator: 'child', mode: 'both', remains: 'collection_entry',
    parentRole: 'Learn two of the names. Use them next time.',
    why: 'Children\'s interests are usually enumerable sets. A collection is the '
      + 'long-running shape the product otherwise lacks.' },

  { kind: 'teach', title: 'Let me teach you', minAge: 6,
    initiator: 'child', mode: 'both', remains: 'artifact',
    parentRole: 'Be genuinely taught. Get it wrong once on purpose is fine; '
      + 'pretending to be taught is not — children detect it instantly.',
    why: '§21 — the only show type that gets BETTER as she ages instead of fading.' },

  { kind: 'spontaneous', title: 'Look what happened', minAge: 4,
    initiator: 'child', mode: 'async', remains: 'artifact',
    parentRole: 'Reply in kind, not in words. Send one back.',
    why: 'She starts it. No prompt, no schedule — the tap she reaches for when '
      + 'something happens.' },
];

export const matrixForAge = (age: number) => MATRIX.filter(m => age >= m.minAge);
export const childInitiated = () =>
  MATRIX.filter(m => m.initiator === 'child' || m.initiator === 'either');

// ============================================================== interests ===
/**
 * Dinosaurs now. In eighteen months it will be something else, and in three
 * years she will be faintly embarrassed by both.
 *
 * So interests are **recorded lightly and expire gently**. There is no intensity
 * score, no ranking, and nothing is ever deleted — she may come back to
 * dinosaurs. An interest that has not been shown in a while simply stops
 * generating prompts.
 *
 * THE RULE THAT MATTERS: the product NEVER says "you used to like dinosaurs".
 * Nothing here surfaces a receded interest to her, ever. Being reminded of what
 * you have outgrown is a small humiliation, and P9 already says resurfacing is
 * dangerous in this population.
 */
export interface Interest {
  id: string;
  label: string;          // 'dinosaurs', 'Pokémon', 'horses', 'rocks'
  /** Singular form for prompts, when it differs. */
  singular?: string;
  addedBy: Side;
  addedAt: string;
  lastShownAt: string | null;
  /** True when it can be counted — drives whether a collection is offered. */
  enumerable: boolean;
}

/** After this long with nothing shown, an interest quietly stops prompting. */
export const RECEDE_AFTER_DAYS = 120;

const daysBetween = (a: string, b: string) =>
  Math.floor((Date.parse(b) - Date.parse(a)) / 86_400_000);

export function activeInterests(all: Interest[], now: string): Interest[] {
  return all.filter(i => {
    const ref = i.lastShownAt ?? i.addedAt;
    return daysBetween(ref, now) < RECEDE_AFTER_DAYS;
  });
}

/**
 * Receded interests, for the GUARDIAN side only — a parent glancing back at what
 * she was into two years ago is warm. The same list shown to her is not.
 */
export function recededInterests(all: Interest[], now: string): Interest[] {
  return all.filter(i => {
    const ref = i.lastShownAt ?? i.addedAt;
    return daysBetween(ref, now) >= RECEDE_AFTER_DAYS;
  });
}

export function markShown(all: Interest[], id: string, at: string): Interest[] {
  return all.map(i => i.id === id ? { ...i, lastShownAt: at } : i);
}

/**
 * P5 — interests are family context and nothing else. They are never used for
 * advertising, recommendation, or model training, and this list is asserted
 * against every payload that leaves the family graph.
 */
export const INTEREST_FORBIDDEN_USES = [
  'ad_targeting', 'recommendation_engine', 'model_training', 'analytics_segment',
  'lookalike_audience', 'content_feed',
] as const;

// ================================================== prompts from interests ==
/**
 * Templates are parameterised, so an interest nobody anticipated works exactly
 * as well as one we thought of. Hard-coding dinosaurs would have been faster and
 * would have failed the moment she moved on.
 */
const TEMPLATES: Record<ShowKind, string[]> = {
  object: ['Show me your favourite {one}', 'Which {one} is the best one?',
    'Show me the {plural} you keep closest to your bed'],
  creation: ['Have you drawn a {one} lately?', 'Show me a {one} you made',
    'Can you make me a {one} out of anything you like?'],
  knowledge: ['Teach me something about {plural} I definitely do not know',
    'What is the strangest fact about {plural}?',
    'Which {one} would win, and why?'],
  skill: ['Can you do a {one} noise?', 'Show me how you sort your {plural}'],
  place: ['Show me where you keep your {plural}'],
  collection: ['Show me all your {plural}', 'Which {plural} are you still missing?',
    'Show me the newest one'],
  teach: ['Teach me the names of three {plural}',
    'Explain {plural} to me like I know nothing'],
  spontaneous: [],
};

/** Prompts that need no interest at all — the floor when nothing is recorded. */
export const GENERIC_PROMPTS: Record<ShowKind, string[]> = {
  object: ['Show me something you like', 'Show me something in your pocket'],
  creation: ['Show me something you made today', 'Show me your latest drawing'],
  knowledge: ['Tell me one thing you learned today', 'Teach me a new word'],
  skill: ['Show me something you can do now that you could not before'],
  place: ['Show me your room', 'Show me out of your window'],
  collection: ['Show me something you are collecting'],
  teach: ['Teach me something. Anything.'],
  spontaneous: [],
};

export function promptsFor(
  kind: ShowKind, interests: Interest[], now: string, limit = 5,
): string[] {
  const active = activeInterests(interests, now);
  const out: string[] = [];
  for (const i of active) {
    const one = i.singular ?? i.label.replace(/s$/, '');
    for (const t of TEMPLATES[kind] ?? []) {
      out.push(t.replace(/\{one\}/g, one).replace(/\{plural\}/g, i.label));
    }
  }
  // Generic prompts always available, so a child with no recorded interest is
  // never worse off than one with several.
  out.push(...(GENERIC_PROMPTS[kind] ?? []));
  return out.slice(0, limit);
}

// ============================================================= collections ==
/**
 * §9.2 lesson applied: a collection is a RECORD, not a target.
 *
 * There is deliberately no denominator. "You've shown me 23" is a record of what
 * happened; "23 of 151" is a homework assignment, and P2 forbids the pressure
 * that comes with it. Pokémon has over a thousand; a completion bar there is a
 * small cruelty.
 */
export interface CollectionEntry {
  id: string;
  interestId: string;
  name: string;            // 'Stegosaurus', 'Bulbasaur'
  artifactId: string | null;
  shownAt: string;
  /** Her words, not a database field. */
  note?: string;
}

export interface Collection {
  interestId: string;
  entries: CollectionEntry[];
}

export function addToCollection(
  c: Collection, e: CollectionEntry,
): { ok: true; collection: Collection } | { ok: false; reason: 'duplicate' } {
  if (c.entries.some(x => x.name.toLowerCase() === e.name.toLowerCase())) {
    return { ok: false, reason: 'duplicate' };
  }
  return { ok: true, collection: { ...c, entries: [...c.entries, e] } };
}

export interface CollectionChildView {
  shownCount: number;
  newest: string | null;
  /** Never a percentage, never a total, never "missing". */
  line: string;
}

export function collectionChildView(c: Collection): CollectionChildView {
  const n = c.entries.length;
  const newest = n ? c.entries[n - 1].name : null;
  return { shownCount: n, newest,
    line: n === 0 ? 'Show me your first one.'
      : n === 1 ? `You have shown me one so far.`
      : `You have shown me ${n} of them.` };
}

/** Fields that must never appear in a child-facing showcase payload. */
export const SHOWCASE_FORBIDDEN = [
  'total', 'percent', 'percentComplete', 'completion', 'missing', 'remaining',
  'streak', 'score', 'rank', 'goal', 'target', 'quota',
] as const;

export function auditShowcase(v: unknown): { ok: true } | { ok: false; leaks: string[] } {
  const leaks: string[] = [];
  const walk = (x: unknown) => {
    if (Array.isArray(x)) return x.forEach(walk);
    if (x && typeof x === 'object') for (const [k, val] of Object.entries(x)) {
      if ((SHOWCASE_FORBIDDEN as readonly string[]).some(f => k.toLowerCase() === f.toLowerCase())) {
        leaks.push(k);
      }
      walk(val);
    }
  };
  walk(v);
  return leaks.length ? { ok: false, leaks: [...new Set(leaks)] } : { ok: true };
}

// ================================================================ the show ==
export interface Show {
  id: string;
  kind: ShowKind;
  childId: string;
  /** Null when she started it unprompted — which is the best case. */
  prompt: string | null;
  artifactId: string | null;
  interestId: string | null;
  shownAt: string;
  /** §9.8.1 — a show is preserved. It is a record of who she was. */
  preserved: true;
  /** The parent's reply. In kind where possible. */
  reply: { artifactId?: string; text?: string; at: string } | null;
}

export function newShow(
  id: string, kind: ShowKind, childId: string, at: string,
  opts?: { prompt?: string; artifactId?: string; interestId?: string },
): Show {
  return { id, kind, childId, shownAt: at, preserved: true,
    prompt: opts?.prompt ?? null,
    artifactId: opts?.artifactId ?? null,
    interestId: opts?.interestId ?? null,
    reply: null };
}

export function replyToShow(
  s: Show, reply: { artifactId?: string; text?: string }, at: string,
): { ok: true; show: Show } | { ok: false; reason: 'already_replied' | 'empty' } {
  if (s.reply) return { ok: false, reason: 'already_replied' };
  if (!reply.artifactId && !reply.text?.trim()) return { ok: false, reason: 'empty' };
  return { ok: true, show: { ...s, reply: { ...reply, at } } };
}

/**
 * §9.8.2 — a year of shows is a portrait of who she was that year, and it is
 * better material for a Year Book than anything else the product collects.
 */
export function showsForYearBook(shows: Show[], year: number): {
  section: string; count: number; artifactIds: string[];
}[] {
  const byKind = new Map<ShowKind, string[]>();
  for (const s of shows) {
    if (new Date(s.shownAt).getUTCFullYear() !== year || !s.artifactId) continue;
    byKind.set(s.kind, [...(byKind.get(s.kind) ?? []), s.artifactId]);
  }
  const titles: Record<ShowKind, string> = {
    object: 'Things you showed me', creation: 'Things you made',
    knowledge: 'Things you taught me', skill: 'Things you learned to do',
    place: 'Where you were', collection: 'What you were collecting',
    teach: 'Things you taught me', spontaneous: 'Things that happened',
  };
  return [...byKind.entries()]
    .map(([k, ids]) => ({ section: titles[k], count: ids.length, artifactIds: ids }))
    .sort((a, b) => b.count - a.count);
}

/**
 * Language guard. Nothing in this module may describe her as reticent, quiet,
 * shy, or bad at talking — the framing that would turn a thing she is good at
 * into a deficiency.
 */
/**
 * STEMS, not conjugations. A first version listed 'comes out of her shell' and
 * sailed past 'come out of her shell' — a guard that only catches the exact
 * wording someone happened to think of is close to no guard at all.
 */
export const BANNED_FRAMINGS = [
  'shy', 'quiet child', 'reticent', 'talk', 'reluctant', 'struggles to',
  'out of her shell', 'out of his shell', 'out of their shell',
  'break the ice', 'ice breaker', 'icebreaker', 'open her up', 'opens her up',
  'draw her out', 'draws her out', 'get her to open',
] as const;

/**
 * ...but 'talk' as a bare stem would refuse legitimate copy. It is banned only
 * in the constructions that pathologise NOT talking.
 */
const TALK_PATTERNS = [
  /(?:won'?t|doesn'?t|will not|does not|refuses? to|hard to get (?:her|him|them) to) talk/i,
  /(?:get|gets|got|getting) (?:her|him|them) talking/i,
  /(?:reluctant|reticent|hesitant) to talk/i,
];

export function auditFraming(text: string): { ok: true } | { ok: false; found: string[] } {
  const t = text.toLowerCase();
  const found = (BANNED_FRAMINGS as readonly string[])
    .filter(b => b !== 'talk' && t.includes(b));
  for (const re of TALK_PATTERNS) {
    const m = text.match(re);
    if (m) found.push(m[0].toLowerCase());
  }
  return found.length ? { ok: false, found: [...new Set(found)] } : { ok: true };
}
