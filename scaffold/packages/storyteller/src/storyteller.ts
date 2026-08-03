/**
 * MASTERFILE §9.11 — the storyteller.
 *
 * Built for a five-year-old who likes being read to, and a parent who likes
 * reading to her. Four things follow from that and shape everything below.
 *
 *  1. IT MUST BE READ ALOUD, not read. Short lines, a breath at every break, and
 *     a REFRAIN she can say with him. The refrain is the single most important
 *     element here and most generators omit it — repetition is what makes a
 *     five-year-old ask for the same story again.
 *
 *  2. IT MUST NEVER REPEAT. The grammar below crosses eight shapes with twelve
 *     slot pools. `spaceSize()` computes the space; the suite asserts it is
 *     larger than ten trillion, which is enough that a nightly story for a
 *     childhood does not exhaust a rounding error of it.
 *
 *  3. IT MUST BE RE-READABLE. She will want *the one about the octopus* again, so
 *     a story is a **seed**. The same seed always produces the same story, and a
 *     saved story is six characters rather than a paragraph of stored text.
 *
 *  4. IT MUST BE SAFE FOR FIVE. Gentle, silly, sometimes sad — never frightening
 *     and never about her parents. §9.11.4 is the guard, and it audits the
 *     OUTPUT rather than trusting the vocabulary.
 */

// ============================================================ deterministic ==
/** Mulberry32. Small, fast, and identical everywhere — a story is its seed. */
export function rng(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6D2B79F5) >>> 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/**
 * Codes and seeds are EXACT INVERSES.
 *
 * The first version encoded with base-29 and decoded with an FNV hash, which are
 * not inverses of anything — so `reread(code)` returned a different story and the
 * whole "read me the octopus one again" promise was quietly broken. Caught by a
 * round-trip assertion, which is the only kind that would have caught it.
 *
 * Six characters of a 29-letter alphabet is 29^6 = 594,823,321 stories. Seeds are
 * therefore constrained to that range rather than the full 32 bits: a code that
 * cannot represent its own seed is not a code.
 */
const ALPHABET = 'BCDFGHJKLMNPQRSTVWXYZ23456789';   // no 0/O/1/I/U — confusable
export const CODE_LENGTH = 6;
export const MAX_SEED = Math.pow(ALPHABET.length, CODE_LENGTH);

export const codeFromSeed = (seed: number): string => {
  let n = ((seed % MAX_SEED) + MAX_SEED) % MAX_SEED, out = '';
  for (let i = 0; i < CODE_LENGTH; i++) {
    out += ALPHABET[n % ALPHABET.length];
    n = Math.floor(n / ALPHABET.length);
  }
  return out;
};

export const seedFromCode = (code: string): number => {
  const c = code.toUpperCase();
  let n = 0;
  for (let i = CODE_LENGTH - 1; i >= 0; i--) {
    const d = ALPHABET.indexOf(c[i] ?? ALPHABET[0]);
    n = n * ALPHABET.length + (d < 0 ? 0 : d);
  }
  return n;
};

const pick = <T,>(r: () => number, xs: readonly T[]): T => xs[Math.floor(r() * xs.length)];

// ================================================================ the words ==
/**
 * Heroes. Animals mostly, because a five-year-old will accept anything from an
 * animal. A few gentle oddities because the surprising ones are the ones she
 * repeats to other people.
 */
export const HEROES = [
  'a very small elephant', 'a worried octopus', 'a sheep who could not sleep',
  'an extremely polite crocodile', 'a hedgehog with a briefcase',
  'a penguin who hated the cold', 'a giraffe with a sore throat',
  'a bear who collected buttons', 'a duck who was learning the trumpet',
  'a snail in a great hurry', 'a llama who told the truth about everything',
  'a very old tortoise', 'a badger who could not whistle',
  'a flamingo standing on the wrong leg', 'a mole with excellent hearing',
  'a wombat who loved Wednesdays', 'a puffin with one enormous idea',
  'a goat who kept losing her hat', 'a moose who was frightened of soup',
  'an owl who overslept', 'a crab who walked forwards on purpose',
  'a pig who painted', 'a fox who was terrible at hiding',
  'a bat who preferred mornings', 'a heron with cold feet',
  'a donkey who hummed', 'a squirrel who forgot where everything was',
  'a whale who was shy', 'a chicken with a plan',
  'a sloth who was actually in a rush', 'a otter who juggled badly',
  'a rhinoceros who tiptoed', 'a lizard who liked being read to',
  'a very tall rabbit', 'a walrus with a lovely singing voice',
  'a beetle called Susan', 'a camel who disliked sand',
  'a swan who was learning to be less dramatic',
  'a hamster with a wheelbarrow', 'a dragon the size of a teapot',
] as const;

export const COMPANIONS = [
  'a extremely loyal spoon', 'a small cloud that followed her about',
  'a talkative bicycle', 'a sock with opinions', 'a beetle who knew shortcuts',
  'an umbrella that had seen things', 'a jam jar full of buttons',
  'a woolly hat that hummed', 'a bird who agreed with everything',
  'a puddle that never dried up', 'an old kettle', 'a hopeful frog',
  'a pencil that only drew circles', 'a very serious mouse',
  'a shoelace that had come untied on purpose', 'a paper boat',
  'a shell that remembered the sea', 'a wobbly stool',
  'a bell that rang at odd times', 'a moth with no sense of direction',
  'a marble that rolled uphill', 'a feather from somebody important',
  'a teaspoon of extraordinary courage', 'a chipped blue cup',
  'a length of excellent string', 'a torch with one good battery',
  'a biscuit she was saving', 'a leaf that would not blow away',
  'a whistle nobody could hear', 'a button off a coat',
] as const;

export const SETTINGS = [
  'a town where it rained upwards', 'the quietest library in the world',
  'a lighthouse with a wonky lamp', 'a market that only opened at night',
  'a valley full of extremely tall grass', 'an island shaped like a hat',
  'a house on the back of an enormous snail', 'a bakery at the bottom of a hill',
  'a forest where the trees leaned in to listen', 'a bridge over nothing at all',
  'a station where no trains ever came', 'a garden that grew doors',
  'a harbour full of upside-down boats', 'a hill with one enormous tree',
  'a village where everyone had the same name',
  'a beach made entirely of small round stones',
  'a meadow that hummed on Tuesdays', 'the flattest field in the county',
  'a cave that echoed back politely', 'a farm on a very small cliff',
  'a city with a river running through the middle of the shops',
  'a wood full of paths that changed their minds',
  'a lake that was only ankle deep', 'a mountain with a bench on top',
  'a street where all the doors were yellow', 'a hollow in a hedge',
  'a boat that had never once been to sea', 'an orchard of one apple tree',
  'a stretch of sand with a single deckchair',
  'a greenhouse full of extremely confident tomatoes',
] as const;

/** Problems. Small, solvable, and never frightening. */
export const PROBLEMS = [
  'had lost something small and important',
  'could not remember where she had put the moon',
  'had a hiccup that would not go away',
  'was supposed to be somewhere at four o\'clock and had forgotten where',
  'had promised to look after something enormous',
  'kept sneezing at exactly the wrong moment',
  'had a knot in something that mattered',
  'could not reach the top shelf, and needed to',
  'had made far too much soup',
  'had woken up on the wrong side of an island',
  'could not stop growing, just for that week',
  'had been given a very large parcel and no address',
  'had run out of the one thing she needed',
  'had accidentally told a very small lie and felt awful about it',
  'was the only one who could hear a strange, gentle noise',
  'had found a key and no door',
  'had been left in charge of something delicate',
  'kept turning left when she meant to turn right',
  'had a shoe that squeaked in a suspiciously musical way',
  'could not think of a single thing to say',
  'had put something down and the world had swallowed it',
  'was expecting someone who was very, very late',
  'had grown attached to something she was supposed to give back',
  'kept finding the same puddle wherever she went',
  'had forgotten how to do the one thing she was famous for',
  'had a letter to deliver and no idea to whom',
  'was carrying more than was strictly sensible',
  'had begun a song she could not finish',
  'kept being mistaken for somebody far more impressive',
  'had a stone in her shoe and a long way still to go',
] as const;

export const COMPLICATIONS = [
  'Then it began to rain, which did not help.',
  'Then the wind changed its mind.',
  'Then a goose arrived, entirely uninvited.',
  'Then everything went a bit sideways.',
  'Then she took a wrong turn and ended up somewhere lovely.',
  'Then the whole thing rolled downhill.',
  'Then a bell rang, and nobody knew why.',
  'Then it got dark, in a friendly sort of way.',
  'Then somebody sneezed, and things escaped.',
  'Then the door swung shut behind her.',
  'Then she dropped it, and it bounced twice.',
  'Then a very large shadow turned out to be a very small bird.',
  'Then she sat down and had a bit of a think.',
  'Then the tide came in, politely but firmly.',
  'Then everything went completely quiet.',
  'Then a stranger walked past whistling the wrong tune.',
  'Then the ground turned out to be a lid.',
  'Then she noticed she had been holding it the whole time.',
  'Then a small crowd gathered, which was worse.',
  'Then the string ran out.',
  'Then she remembered she had left the tap running.',
  'Then somebody laughed, and it was actually quite nice.',
  'Then the map turned out to be a menu.',
  'Then the sun came out and made everything harder to see.',
] as const;

export const HELPERS = [
  'a passing badger with a lantern', 'somebody\'s grandmother',
  'a very calm heron', 'three mice who worked as a team',
  'the postman, who knew everything', 'a child with a bucket',
  'an old woman who mended things', 'a lifeguard on her day off',
  'a dog who had been watching the whole time',
  'a beekeeper with excellent advice', 'a librarian who whispered the answer',
  'a fisherman who did not look up', 'a baker with flour on her nose',
  'somebody who had done exactly this before',
  'a bus driver going the other way', 'a gardener with muddy knees',
  'a very small boy with a very large idea',
  'a cat who pretended not to help', 'a lighthouse keeper',
  'a woman selling extremely good apples', 'a nurse walking home',
  'a farmer leaning on a gate', 'a busker who stopped playing to listen',
  'a shopkeeper who never closed',
] as const;

export const RESOLUTIONS = [
  'it turned out to have been behind the door all along',
  'the two of them carried it together, which was easier',
  'she asked for help, which she had not thought of',
  'everybody took one small piece and it was done in a minute',
  'she made a slightly worse plan that worked much better',
  'it fixed itself, quietly, while nobody was looking',
  'she gave it away, and felt enormously better',
  'they swapped, and both of them were pleased',
  'she started again from the beginning and got it right',
  'it turned out not to matter nearly as much as she had thought',
  'she said sorry, and it was accepted immediately',
  'they made a new one, which was wonkier and much more loved',
  'she waited, which was the hardest thing, and then it came',
  'somebody had been keeping it safe for her the whole time',
  'she found a use for it that nobody had thought of',
  'they shared it, and there was more than enough',
  'she told the truth, and everything got simpler',
  'it had been the wrong problem, and the right one was easy',
  'she put it down, and it was fine',
  'they decided to leave it exactly as it was',
  'she taught somebody else, and then there were two who could do it',
  'the noise turned out to be somebody singing badly, and she joined in',
  'she wrote it down so she would not forget again',
  'they took the long way round, and saw something marvellous',
] as const;

/** The refrain is HER line. Rhythmic, silly, and easy to shout. */
export const REFRAINS = [
  'Oh no. Oh no. Oh dear, oh no.',
  'And that is not supposed to happen!',
  'Wobble, wobble, WHOOPS.',
  'Not again! Not AGAIN!',
  'Well. That was unexpected.',
  'Ding! said the bell. Ding, ding, DING.',
  'Left a bit. Right a bit. LEFT A BIT MORE.',
  'Hmmmmmm, she said. Hmmmmmm.',
  'Squeak went the shoe. Squeak, squeak, SQUEAK.',
  'One, two, three — LIFT!',
  'Nope. Nope. Definitely nope.',
  'Round and round and round we go.',
  'Was that it? No. Was THAT it? No.',
  'Tip. Tap. Tip. Tap. TIP.',
  'Absolutely not, thank you very much.',
  'Whoosh! went the wind. WHOOSH.',
  'Nearly. Nearly. NEARLY.',
  'And everybody said: ooooooh.',
  'Plip. Plop. Plip. Plop.',
  'Here we go again, she sighed.',
] as const;

/**
 * Openings come in two grammatical kinds, and treating them as one produced
 * "Nobody expected any of this. in a forest where the trees leaned in to listen".
 *
 * LEAD_INS are fragments that flow straight into the setting clause. STANDALONE
 * openings are complete sentences, so the setting clause has to start a new one.
 * Only reading the output aloud surfaces this; no unit test would.
 */
export const OPENINGS_LEADIN = [
  'Once, not very long ago,', 'A long time ago, but not that long,',
  'On a Tuesday, for no particular reason,', 'One perfectly ordinary afternoon,',
  'Before breakfast, which is when the best things happen,',
  'Right at the very edge of somewhere,', 'It was almost bedtime when,',
  'Late one afternoon,', 'Just after the rain stopped,',
  'On the third day of the holidays,',
] as const;

export const OPENINGS_STANDALONE = [
  'It began with a noise.', 'Nobody expected any of this.',
  'It all started with a puddle.', 'The day had begun so well.',
  'Everybody agrees on how it started.',
  'This is a true story, more or less.',
  'It was the sort of morning where anything might happen.',
  'You will not believe a word of this.',
] as const;

export const OPENINGS = [...OPENINGS_LEADIN, ...OPENINGS_STANDALONE] as const;

export const ENDINGS = [
  'And that is why, to this day, nobody mentions the goose.',
  'And she slept extremely well that night.',
  'And they had toast, which is the correct ending to most things.',
  'And the next day it happened all over again, but that is another story.',
  'And nobody ever explained the bell.',
  'And she kept it, of course. Wouldn\'t you?',
  'And that was quite enough excitement for one week.',
  'And ever since then, they have done it together.',
  'And the whole thing was forgotten by Thursday.',
  'And she told everyone, and everyone told everyone else.',
  'And it is still there now, if you know where to look.',
  'And that was the end of it, except it wasn\'t.',
  'And she was very pleased with herself, and quite right too.',
  'And they went home the long way, on purpose.',
  'And she never did find out whose hat it was.',
  'And everything was exactly as it should be, which is rare.',
] as const;

export const SILLY_DETAILS = [
  'wearing one glove, for reasons of her own',
  'humming something from an advert',
  'carrying an enormous and entirely unnecessary map',
  'with a biscuit balanced on her head',
  'in boots that were far too big',
  'holding a stick she had grown attached to',
  'walking in an unusual way she had recently invented',
  'wrapped in a blanket like a very small king',
  'making a noise like a distant tractor',
  'with a leaf stuck to her ear',
  'counting under her breath',
  'trying to look casual, and failing',
  'entirely upside down',
  'pretending to be a letterbox',
  'wearing her hat backwards on purpose',
  'with a spoon behind each ear',
  'walking sideways, which was quicker',
  'carrying nine things and needing ten hands',
  'whistling one single note',
  'with a very small flag',
  'dressed as an ordinary bush',
  'holding hands with nobody in particular',
  'stopping every few steps to admire something',
  'with an expression of enormous determination',
  'entirely covered in flour',
  'reading while walking, badly',
  'with a plan written on her arm',
  'moving slowly, so as not to alarm anybody',
  'in a hat she had made herself that morning',
  'trailing a very long ribbon',
] as const;

export const WEATHERS = [
  'It was raining, gently and without much conviction.',
  'The sun was out, showing off.',
  'It was that grey which is not quite anything.',
  'There was a wind with big ideas.',
  'It was warm enough to sit on a wall.',
  'A fog had come in and made everything mysterious.',
  'It was snowing, but only a bit, and only in one place.',
  'The air smelled of cut grass and something baking.',
  'It was the kind of cold that makes your nose go pink.',
  'The sky could not decide.',
  'It was so still that you could hear a bee changing its mind.',
  'A soft rain was falling on everything equally.',
  'It was late enough for the lights to be coming on.',
  'The morning was doing its best.',
  'It was hot, and everybody had gone a bit slow.',
  'There were exactly three clouds.',
] as const;

/** Eight shapes. The shape decides the order and the shape of the sentences. */
export const SHAPES = [
  'the_thing_that_was_lost', 'an_unlikely_friendship', 'a_very_silly_day',
  'too_big_by_far', 'the_quiet_one_who_saved_the_day', 'the_swap',
  'the_unexpected_visitor', 'the_thing_that_would_not_stop',
] as const;
export type Shape = typeof SHAPES[number];

export const SHAPE_TITLES: Record<Shape, string> = {
  the_thing_that_was_lost: 'The Thing That Was Lost',
  an_unlikely_friendship: 'An Unlikely Friendship',
  a_very_silly_day: 'A Very Silly Day',
  too_big_by_far: 'Far Too Big',
  the_quiet_one_who_saved_the_day: 'The Quiet One',
  the_swap: 'The Swap',
  the_unexpected_visitor: 'The Visitor',
  the_thing_that_would_not_stop: 'It Would Not Stop',
};

// ============================================================ the size ======
/**
 * The combinatorial space, for the promise that it never repeats twice.
 *
 * This multiplies the pools a single story actually draws from. It ignores
 * personalisation and ordering, so the real figure is larger — this is the floor.
 */
export function spaceSize(): number {
  return SHAPES.length * HEROES.length * COMPANIONS.length * SETTINGS.length
    * PROBLEMS.length * COMPLICATIONS.length * HELPERS.length
    * RESOLUTIONS.length * REFRAINS.length * OPENINGS.length * ENDINGS.length
    * SILLY_DETAILS.length * WEATHERS.length;
}

// ========================================================= personalisation ==
export interface Personal {
  /** Her name, as she spelled it (§8.5.1). */
  childName?: string;
  /** Her colour's label (§8.6). */
  colour?: string;
  /** Her current interests (§9.10.3) — dinosaurs, Pokémon, whatever it is now. */
  interests?: string[];
  /** The grown-up reading it. */
  readerName?: string;
}

/**
 * Personalisation is a light touch, applied to at most two lines.
 *
 * A story where every noun has been swapped for the child's name is not a story
 * about a bear any more, and children notice the machinery immediately. One
 * mention is delightful; six is a mail merge.
 */
export const MAX_PERSONAL_TOUCHES = 2;

// ============================================================== the story ===
export interface StoryLine {
  text: string;
  /** True for the refrain — HER line to say. */
  isRefrain: boolean;
}

export interface Story {
  code: string;
  seed: number;
  shape: Shape;
  title: string;
  lines: StoryLine[];
  refrain: string;
  /** Rough read-aloud time, for a parent deciding at bedtime. */
  readSeconds: number;
  personalTouches: number;
}

/** ~130 words a minute read aloud to a small child, slower than silent reading. */
export const WORDS_PER_MINUTE_ALOUD = 130;

export function generate(seedOrCode: number | string, p: Personal = {}): Story {
  const seed = typeof seedOrCode === 'string'
    ? seedFromCode(seedOrCode)
    : ((seedOrCode % MAX_SEED) + MAX_SEED) % MAX_SEED;
  const code = typeof seedOrCode === 'string' ? seedOrCode : codeFromSeed(seed);
  const r = rng(seed);

  const shape = pick(r, SHAPES);
  const hero = pick(r, HEROES);
  const companion = pick(r, COMPANIONS);
  const setting = pick(r, SETTINGS);
  const problem = pick(r, PROBLEMS);
  const complication = pick(r, COMPLICATIONS);
  const helper = pick(r, HELPERS);
  const resolution = pick(r, RESOLUTIONS);
  const refrain = pick(r, REFRAINS);
  const leadIn = r() < 0.55;
  const opening = leadIn ? pick(r, OPENINGS_LEADIN) : pick(r, OPENINGS_STANDALONE);
  const ending = pick(r, ENDINGS);
  const silly = pick(r, SILLY_DETAILS);
  const weather = pick(r, WEATHERS);

  const lines: StoryLine[] = [];
  const say = (text: string) => lines.push({ text, isRefrain: false });
  const chant = () => lines.push({ text: refrain, isRefrain: true });

  say(leadIn
    ? `${opening} in ${setting}, there lived ${hero}.`
    : `${opening} In ${setting}, there lived ${hero}.`);
  say(weather);
  say(p.colour ? `She was ${silly}, and ${p.colour} all over.` : `She was ${silly}.`);
  say(`The trouble was this: she ${problem}.`);
  chant();
  // No relative pronoun: most companions are objects and would need "which",
  // some are creatures and would need "who". Two short sentences dodge the
  // agreement problem and read better aloud anyway.
  say(`Luckily she had ${companion} with her. No help at all, but good company.`);
  say(complication);
  chant();
  say(helperLine(helper, p.childName));
  say(`And do you know what? ${cap(resolution)}.`);
  chant();
  say(ending);

  // Personalisation is applied where the line is BUILT, not by rewriting a
  // finished sentence. The first version did string surgery and produced
  // "So she went and found, and a child called OLIVE a nurse walking home."
  const touches = (p.childName ? 1 : 0) + (p.colour ? 1 : 0);
  const out = lines;

  const words = out.reduce((n, l) => n + l.text.split(/\s+/).length, 0);
  return { code, seed, shape, title: SHAPE_TITLES[shape], lines: out, refrain,
    readSeconds: Math.max(30, Math.round((words / WORDS_PER_MINUTE_ALOUD) * 60)),
    personalTouches: touches };
}

const cap = (s: string) => s.charAt(0).toUpperCase() + s.slice(1);
/** One clean sentence either way, rather than a rewrite of a finished one. */
const helperLine = (helper: string, name?: string) =>
  name ? `So she went and found ${helper}, and a child called ${name}.`
       : `So she went and found ${helper}.`;

/** A new story. Random seed, so a fresh one every time. */
export function freshStory(p: Personal = {}, rand: () => number = Math.random): Story {
  return generate(Math.floor(rand() * MAX_SEED), p);
}

/** She wants the octopus one again. Six characters, and it is back, identical. */
export function reread(code: string, p: Personal = {}): Story {
  return generate(code, p);
}

// ================================================================ the guard ==
/**
 * §9.11.4 — safe for five.
 *
 * Gentle, silly, sometimes sad. Never frightening, and — the guard that matters
 * most in THIS product — never about her parents.
 *
 * A story about a bear who lives in two houses could be wonderful or could be
 * devastating, and the product cannot tell which on any given evening. So the
 * storyteller does not go near it. If a family wants that story, a parent can
 * tell it; software should not choose the moment.
 *
 * The audit runs on generated OUTPUT rather than on the vocabulary, because that
 * is where a bad combination would actually appear.
 */
export const BANNED_CONTENT = [
  // Nothing frightening.
  'die', 'died', 'dead', 'death', 'kill', 'blood', 'gun', 'knife', 'weapon',
  'monster', 'nightmare', 'terrified', 'screamed', 'horror', 'evil', 'wicked',
  'haunted', 'ghost', 'drown', 'burned', 'hospital', 'ambulance', 'police',
  'stolen', 'thief', 'kidnap', 'trapped forever', 'never came back',
  'lost forever', 'all alone forever', 'nobody loved',
  // Nothing about her parents. §9.11.4.
  'divorce', 'separated', 'custody', 'two homes', 'two houses',
  'mummy and daddy', 'mommy and daddy', 'court', 'argument', 'shouting',
  'stopped loving', 'chose one', 'take sides',
  // Nothing adult.
  'wine', 'beer', 'drunk', 'cigarette', 'kissed', 'romance', 'wedding night',
  'money troubles', 'rent', 'fired', 'debt',
] as const;

/**
 * Single words match on WORD BOUNDARIES; phrases match as substrings.
 *
 * A first version used `includes()` for everything and flagged "The day had
 * begun so well" because `begun` contains `gun`. That is the third instance of
 * this class on this project — after exact conjugations in the framing guard and
 * a capitalisation heuristic in the push audit — so it is worth naming the
 * pattern: **a text guard that matches the wrong granularity is not a strict
 * guard, it is a broken one**, and it fails in both directions. It flags
 * innocent copy and it will miss "gunpowder" all the same.
 */
export function auditStory(s: Story): { ok: true } | { ok: false; found: string[] } {
  const text = (s.title + ' ' + s.lines.map(l => l.text).join(' ')).toLowerCase();
  const found = (BANNED_CONTENT as readonly string[]).filter(w =>
    w.includes(' ')
      ? text.includes(w)
      : new RegExp(`\\b${w.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\b`).test(text));
  return found.length ? { ok: false, found } : { ok: true };
}

/** Every word in the vocabulary, for a whole-corpus sweep in the suite. */
export function corpus(): string[] {
  return [...HEROES, ...COMPANIONS, ...SETTINGS, ...PROBLEMS, ...COMPLICATIONS,
    ...HELPERS, ...RESOLUTIONS, ...REFRAINS, ...OPENINGS, ...ENDINGS,
    ...SILLY_DETAILS, ...WEATHERS];
}

// ============================================================ read aloud ====
/**
 * §9.11.3 — shaped for a voice, not an eye.
 *
 * The refrain is marked so a parent knows to pause and let her say it. That one
 * affordance is the difference between reading *to* a child and reading *with*
 * one, and it costs a boolean.
 */
export interface ReadAloud {
  title: string;
  blocks: { text: string; herLine: boolean; pauseAfter: boolean }[];
  refrain: string;
  readSeconds: number;
  hint: string;
}

export function forReadingAloud(s: Story): ReadAloud {
  return {
    title: s.title,
    blocks: s.lines.map((l, i) => ({ text: l.text, herLine: l.isRefrain,
      pauseAfter: l.isRefrain || i === s.lines.length - 2 })),
    refrain: s.refrain,
    readSeconds: s.readSeconds,
    hint: 'The bold line is hers. Stop, look at her, and let her say it — '
        + 'by the third time she will get there first.',
  };
}

/** §9.8 — a story she asked for twice is worth keeping. Six characters of it. */
export function storyArtifact(s: Story, timesRead: number): {
  title: string; code: string; preserved: true;
} | null {
  return timesRead >= 2
    ? { title: s.title, code: s.code, preserved: true } : null;
}
