/**
 * MASTERFILE §9.2 — the jokebook.
 *
 * A fixed, hand-written library of kid-friendly jokes: dad jokes, puns,
 * wordplay, and plain silliness. Nothing here is generated — every entry was
 * written and read by a person before it shipped, which is the whole reason
 * this file can be small and boring: there is no safety sweep to run because
 * there is no unbounded supply to sweep.
 *
 * Age gating follows games.ts's `forAge()` exactly: each joke carries a
 * `minAge`, and `forAge(age)` keeps the ones at or below her real age. That
 * floor is a COMPREHENSION floor, not a content rating. Every joke in this
 * file is appropriate for every age; the floor only stops a joke she cannot
 * get yet (a spelling gag before she spells, "abominable snowman" before
 * she's met one) from landing flat and teaching her the jokebook is not for
 * her. Nothing is gated above 12.
 *
 * `category` is for the people writing this list, so the mix stays honest —
 * a jokebook that drifts into forty puns and two knock-knocks is a worse
 * jokebook. It is not surfaced to her as a picker; she asked for a joke,
 * not a genre.
 *
 * Prohibition P2 governs the favourites half: no read count, no "jokes
 * told" streak, no favourite tally is ever exposed. A favourite is a code
 * and nothing else — the type has no field to leak.
 */

export type JokeCategory = 'dadJoke' | 'pun' | 'wordplay' | 'silly' | 'knockKnock';

export interface Joke {
  /** Stable id — favourites are lists of these, so it must never change once shipped. */
  id: string;
  setup: string;
  punchline: string;
  /** Comprehension floor — see the file header. Never a content rating. */
  minAge: number;
  category: JokeCategory;
}

export const CATALOGUE: Joke[] = [
  // ---- 4+ : the simplest possible shapes — a sound, an animal, a knock ----
  { id: 'dino-snore', minAge: 4, category: 'silly',
    setup: 'What do you call a sleeping dinosaur?', punchline: 'A dino-snore!' },
  { id: 'gummy-bear', minAge: 4, category: 'silly',
    setup: 'What do you call a bear with no teeth?', punchline: 'A gummy bear!' },
  { id: 'cow-reads', minAge: 4, category: 'silly',
    setup: 'What do cows like to read?', punchline: 'Moo-spapers!' },
  { id: 'kk-boo', minAge: 4, category: 'knockKnock',
    setup: 'Knock knock. Who’s there? Boo. Boo who?', punchline: 'Don’t cry, it’s just a joke!' },
  { id: 'kk-cow-says', minAge: 4, category: 'knockKnock',
    setup: 'Knock knock. Who’s there? Cow says. Cow says who?', punchline: 'No, silly — a cow says MOO!' },
  { id: 'brown-sticky', minAge: 4, category: 'silly',
    setup: 'What’s brown and sticky?', punchline: 'A stick!' },

  // ---- 5+ : one simple pun she can hear -----------------------------------
  { id: 'teddy-stuffed', minAge: 5, category: 'pun',
    setup: 'Why did the teddy bear say no to dessert?', punchline: 'Because she was already stuffed!' },
  { id: 'wall-corner', minAge: 5, category: 'silly',
    setup: 'What did one wall say to the other wall?', punchline: 'Meet you at the corner!' },
  { id: 'kk-lettuce', minAge: 5, category: 'knockKnock',
    setup: 'Knock knock. Who’s there? Lettuce. Lettuce who?', punchline: 'Lettuce in, it’s cold out here!' },
  { id: 'ocean-waves', minAge: 5, category: 'pun',
    setup: 'How does the ocean say hello?', punchline: 'It waves!' },
  { id: 'carrot-parrot', minAge: 5, category: 'wordplay',
    setup: 'What’s orange and sounds like a parrot?', punchline: 'A carrot!' },
  { id: 'flower-bud', minAge: 5, category: 'pun',
    setup: 'What did the big flower say to the little flower?', punchline: 'Hi, bud!' },
  { id: 'cookie-crummy', minAge: 5, category: 'pun',
    setup: 'Why did the cookie go to the doctor?', punchline: 'Because it was feeling crummy!' },
  { id: 'elsa-balloon', minAge: 5, category: 'silly',
    setup: 'Why can’t Elsa have a balloon?', punchline: 'Because she’ll let it go!' },

  // ---- 6+ : a pun that needs one more word in her vocabulary --------------
  { id: 'palm-tree', minAge: 6, category: 'pun',
    setup: 'What kind of tree fits in your hand?', punchline: 'A palm tree!' },
  { id: 'cornfield-ears', minAge: 6, category: 'pun',
    setup: 'What has ears but cannot hear?', punchline: 'A cornfield!' },
  { id: 'nacho-cheese', minAge: 6, category: 'pun',
    setup: 'What do you call cheese that isn’t yours?', punchline: 'Nacho cheese!' },
  { id: 'eggs-crack-up', minAge: 6, category: 'pun',
    setup: 'Why don’t eggs tell jokes?', punchline: 'They’d crack each other up!' },
  { id: 'boomerang-stick', minAge: 6, category: 'silly',
    setup: 'What do you call a boomerang that won’t come back?', punchline: 'A stick!' },
  { id: 'zero-eight-belt', minAge: 6, category: 'wordplay',
    setup: 'What did the zero say to the eight?', punchline: 'Nice belt!' },
  { id: 'bees-honeycomb', minAge: 6, category: 'pun',
    setup: 'Why do bees have sticky hair?', punchline: 'Because they use honeycombs!' },
  { id: 'cant-opener', minAge: 6, category: 'wordplay',
    setup: 'What do you call a can opener that doesn’t work?', punchline: 'A can’t opener!' },
  { id: 'tissue-boogie', minAge: 6, category: 'pun',
    setup: 'How do you make a tissue dance?', punchline: 'You put a little boogie in it!' },
  { id: 'cat-mountain', minAge: 6, category: 'wordplay',
    setup: 'What do you call a pile of cats?', punchline: 'A meow-ntain!' },
  { id: 'bulldozer', minAge: 6, category: 'pun',
    setup: 'What do you call a sleeping bull?', punchline: 'A bulldozer!' },
  { id: 'seven-eight-nine', minAge: 6, category: 'wordplay',
    setup: 'Why was six afraid of seven?', punchline: 'Because seven eight nine!' },
  { id: 'robot-chips', minAge: 6, category: 'pun',
    setup: 'What’s a robot’s favourite snack?', punchline: 'Computer chips!' },
  { id: 'pork-chop', minAge: 6, category: 'pun',
    setup: 'What do you call a pig that does karate?', punchline: 'A pork chop!' },

  // ---- 7+ : two ideas colliding, or a bit of spelling ---------------------
  { id: 'fsh', minAge: 7, category: 'wordplay',
    setup: 'What do you call a fish with no eyes?', punchline: 'A fsh!' },
  { id: 'labracadabrador', minAge: 7, category: 'wordplay',
    setup: 'What do you call a dog who does magic tricks?', punchline: 'A labracadabrador!' },
  { id: 'math-problems', minAge: 7, category: 'pun',
    setup: 'Why was the maths book sad?', punchline: 'It had too many problems!' },
  { id: 'two-tired', minAge: 7, category: 'pun',
    setup: 'Why did the bicycle fall over?', punchline: 'It was two-tired!' },
  { id: 'impasta', minAge: 7, category: 'pun',
    setup: 'What do you call a fake noodle?', punchline: 'An impasta!' },
  { id: 'open-toad', minAge: 7, category: 'pun',
    setup: 'What kind of shoes do frogs wear?', punchline: 'Open-toad sandals!' },
  { id: 't-rex-wrecks', minAge: 7, category: 'wordplay',
    setup: 'What do you call a dinosaur that crashes his car?', punchline: 'Tyrannosaurus wrecks!' },
  { id: 'dont-know-y', minAge: 7, category: 'dadJoke',
    setup: 'I only know 25 letters of the alphabet.', punchline: 'I don’t know Y.' },
  { id: 'homework-cake', minAge: 7, category: 'pun',
    setup: 'Why did the student eat his homework?', punchline: 'Because the teacher said it was a piece of cake!' },
  { id: 'little-horse', minAge: 7, category: 'pun',
    setup: 'Why couldn’t the pony sing?', punchline: 'She was a little horse!' },

  // ---- 8+ : an idiom she has started to hear grown-ups use ----------------
  { id: 'outstanding-field', minAge: 8, category: 'dadJoke',
    setup: 'Why did the scarecrow win an award?', punchline: 'Because he was outstanding in his field!' },
  { id: 'dinners-on-me', minAge: 8, category: 'pun',
    setup: 'What did one plate say to the other plate?', punchline: 'Dinner’s on me!' },
  { id: 'salad-dressing', minAge: 8, category: 'pun',
    setup: 'Why did the tomato turn red?', punchline: 'Because it saw the salad dressing!' },
  { id: 'frostbite', minAge: 8, category: 'pun',
    setup: 'What do you get when you cross a snowman with a dog?', punchline: 'Frostbite!' },
  { id: 'investigator', minAge: 8, category: 'wordplay',
    setup: 'What do you call an alligator in a vest?', punchline: 'An investigator!' },
  { id: 'skeleton-guts', minAge: 8, category: 'pun',
    setup: 'Why don’t skeletons fight each other?', punchline: 'They don’t have the guts!' },
  { id: 'you-planet', minAge: 8, category: 'pun',
    setup: 'How do you organise a party in space?', punchline: 'You planet!' },

  // ---- 9+ : a reference she has to already own ----------------------------
  { id: 'abdominal-snowman', minAge: 9, category: 'wordplay',
    setup: 'What do you call a snowman with a six-pack?', punchline: 'An abdominal snowman!' },
  { id: 'hole-in-one', minAge: 9, category: 'dadJoke',
    setup: 'Why did the golfer bring two pairs of trousers?', punchline: 'In case he got a hole in one!' },
  { id: 'picture-framed', minAge: 9, category: 'wordplay',
    setup: 'Why did the picture go to jail?', punchline: 'Because it was framed!' },
  { id: 'janitor-supplies', minAge: 9, category: 'wordplay',
    setup: 'What did the janitor shout when he jumped out of the cupboard?', punchline: '“Supplies!”' },
  { id: 'bison', minAge: 9, category: 'wordplay',
    setup: 'What did the buffalo say when his son left for school?', punchline: 'Bison!' },

  // ---- 10+ : proper dad jokes — a groan is the correct response -----------
  { id: 'anti-gravity', minAge: 10, category: 'dadJoke',
    setup: 'I’m reading a book about anti-gravity.', punchline: 'It’s impossible to put down!' },
  { id: 'atoms-make-up', minAge: 10, category: 'dadJoke',
    setup: 'Why don’t scientists trust atoms?', punchline: 'Because they make up everything!' },
  { id: 'facial-hair', minAge: 10, category: 'dadJoke',
    setup: 'I used to hate facial hair.', punchline: 'But then it grew on me.' },
  { id: 'astronaut-space', minAge: 10, category: 'dadJoke',
    setup: 'Did you hear about the claustrophobic astronaut?', punchline: 'He just needed a little space!' },
  { id: 'coffee-mugged', minAge: 10, category: 'dadJoke',
    setup: 'Why did the coffee file a police report?', punchline: 'It got mugged!' },

  // ---- 11+ / 12+ : wordplay that needs a bigger vocabulary ----------------
  { id: 'satisfactory', minAge: 11, category: 'wordplay',
    setup: 'What do you call a factory that makes okay products?', punchline: 'A satisfactory!' },
  { id: 'swiss-flag', minAge: 11, category: 'dadJoke',
    setup: 'What’s the best thing about Switzerland?', punchline: 'I don’t know, but the flag is a big plus!' },
  { id: 'emotional-baggage', minAge: 12, category: 'dadJoke',
    setup: 'I told my suitcase there’d be no holiday this year.', punchline: 'Now I’m dealing with emotional baggage.' },
  { id: 'parallel-lines', minAge: 12, category: 'dadJoke',
    setup: 'Parallel lines have so much in common.', punchline: 'It’s a shame they’ll never meet.' },
];

/** Same shape as games.ts's forAge — a floor, never a ceiling. */
export const forAge = (age: number): Joke[] => CATALOGUE.filter(j => age >= j.minAge);

export const byId = (id: string): Joke | undefined => CATALOGUE.find(j => j.id === id);

/**
 * "Tell me another!" — one joke she can get, never the one she just heard.
 * `pick` is injectable so a test can drive it deterministically; production
 * passes nothing and gets Math.random. Returns null only if the age floor
 * leaves nothing at all, which cannot happen at any age ≥ 4 (see the test).
 */
export function randomJoke(
  age: number,
  excludeId: string | null = null,
  pick: () => number = Math.random,
): Joke | null {
  const pool = forAge(age).filter(j => j.id !== excludeId);
  if (pool.length === 0) return null;
  return pool[Math.floor(pick() * pool.length) % pool.length];
}

// ------------------------------------------------------------- favourites --
/**
 * A favourite is a joke id and when she starred it. Nothing else — no
 * timesRead, no tally. Mirrors library.ts's shape for stories, deliberately
 * without the count that file keeps for the parent-side book (P2).
 */
export interface JokeFavourite { id: string; starredAt: string; }

export const isStarred = (list: JokeFavourite[], id: string) => list.some(f => f.id === id);

/** Idempotent — starring twice is one star, not two. */
export function star(list: JokeFavourite[], id: string, at: string): JokeFavourite[] {
  if (isStarred(list, id)) return list;
  return [...list, { id, starredAt: at }];
}

export const unstar = (list: JokeFavourite[], id: string) => list.filter(f => f.id !== id);

/** Her list, newest first — the one she starred tonight is the one she wants tomorrow. */
export function favouritesChildView(list: JokeFavourite[]): Joke[] {
  const sorted = [...list].sort((a, b) => b.starredAt.localeCompare(a.starredAt));
  return sorted.map(f => byId(f.id)).filter((j): j is Joke => j !== undefined);
}

/** Fields that must never reach her — the same runtime-checkable audit library.ts keeps. */
export const JOKEBOOK_FORBIDDEN = ['timesRead', 'times_read', 'mostRead', 'rank', 'score', 'streak', 'count', 'told'];

export function auditChildView(v: unknown): { ok: boolean; leaks: string[] } {
  const leaks = new Set<string>();
  const walk = (x: unknown) => {
    if (Array.isArray(x)) { x.forEach(walk); return; }
    if (x && typeof x === 'object') {
      for (const [k, val] of Object.entries(x as Record<string, unknown>)) {
        if (JOKEBOOK_FORBIDDEN.some(f => f.toLowerCase() === k.toLowerCase())) leaks.add(k);
        walk(val);
      }
    }
  };
  walk(v);
  return { ok: leaks.size === 0, leaks: [...leaks] };
}
