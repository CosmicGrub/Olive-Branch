/**
 * MASTERFILE §9.2, §3.1, §5.19 — live games, played during a call.
 *
 * The job of a live game is not entertainment. A five-year-old runs out of
 * things to say on a video call in about ninety seconds, and then it is "what
 * did you do today" / "nothing" / silence, and the call ends early with both
 * people feeling worse. **A live game is a spine for the call.**
 *
 * Three constraints are enforced here rather than written down and forgotten:
 *
 *   1. Nothing may require sub-200ms response. Reflex games break over a real
 *      connection and the CHILD gets blamed for the network.
 *   2. The parent's face is never hidden. A game that goes fullscreen over the
 *      video has inverted the entire product.
 *   3. A live game degrades to asynchronous play. The call drops on a train;
 *      the game becomes turn-based and waits, rather than vanishing.
 */

export type Side = 'A' | 'B';
export type LiveKind =
  | 'simon_says' | 'copy_me' | 'freeze_dance' | 'charades' | 'i_spy'
  | 'show_me' | 'twenty_questions' | 'would_you_rather' | 'two_truths'
  | 'pictionary';

/** Never 'hidden'. The type has no such member, deliberately. */
export type VideoLayout = 'side_by_side' | 'picture_in_picture';

export interface LiveGame {
  kind: LiveKind;
  title: string;
  minAge: number;
  /**
   * The slowest connection this game still works on. Anything below
   * MIN_VIABLE_LATENCY_MS is rejected at registration — see `register()`.
   */
  minViableLatencyMs: number;
  videoLayout: VideoLayout;
  /** Can this game continue when the call drops? */
  degradesToAsync: boolean;
  blurb: string;
}

/**
 * Below this, a game is a reflex test and the network decides the winner.
 * Whack-a-mole fails here; freeze dance and Simon Says do not.
 */
export const MIN_VIABLE_LATENCY_MS = 200;

const REGISTRY: LiveGame[] = [];

export class UnplayableOverNetwork extends Error {
  constructor(kind: string, ms: number) {
    super(`${kind} needs ${ms}ms response; anything under ` +
      `${MIN_VIABLE_LATENCY_MS}ms makes the network the opponent and the child ` +
      `takes the blame for it.`);
  }
}

export function register(g: LiveGame): LiveGame {
  if (g.minViableLatencyMs < MIN_VIABLE_LATENCY_MS) {
    throw new UnplayableOverNetwork(g.kind, g.minViableLatencyMs);
  }
  REGISTRY.push(g);
  return g;
}

export const LIVE_GAMES: LiveGame[] = [
  { kind: 'simon_says', title: 'Simon says', minAge: 4, minViableLatencyMs: 800,
    videoLayout: 'side_by_side', degradesToAsync: false,
    blurb: 'The camera is the whole game.' },
  { kind: 'copy_me', title: 'Copy me', minAge: 4, minViableLatencyMs: 800,
    videoLayout: 'side_by_side', degradesToAsync: false,
    blurb: 'Mirror what Dad does. Then swap.' },
  { kind: 'freeze_dance', title: 'Freeze dance', minAge: 4, minViableLatencyMs: 1000,
    videoLayout: 'side_by_side', degradesToAsync: false,
    blurb: 'Dad controls the music. Lag is fine — that is the point.' },
  { kind: 'charades', title: 'Charades', minAge: 5, minViableLatencyMs: 600,
    videoLayout: 'side_by_side', degradesToAsync: false,
    blurb: 'Act it out. Animal noises count.' },
  { kind: 'i_spy', title: 'I spy', minAge: 4, minViableLatencyMs: 1000,
    videoLayout: 'side_by_side', degradesToAsync: true,
    blurb: 'You can see his room. He can see yours.' },
  { kind: 'show_me', title: 'Show me something…', minAge: 4, minViableLatencyMs: 1500,
    videoLayout: 'side_by_side', degradesToAsync: true,
    blurb: 'Round, blue, that you made today. Go and get it.' },
  { kind: 'twenty_questions', title: 'Twenty questions', minAge: 8,
    minViableLatencyMs: 2000, videoLayout: 'side_by_side', degradesToAsync: true,
    blurb: 'Conversation wearing a game costume.' },
  { kind: 'would_you_rather', title: 'Would you rather', minAge: 8,
    minViableLatencyMs: 2000, videoLayout: 'side_by_side', degradesToAsync: true,
    blurb: 'Keeps a teenager on the call.' },
  { kind: 'two_truths', title: 'Two truths and a lie', minAge: 11,
    minViableLatencyMs: 2000, videoLayout: 'side_by_side', degradesToAsync: true,
    blurb: 'You will learn something about him.' },
  { kind: 'pictionary', title: 'Pictionary', minAge: 6, minViableLatencyMs: 400,
    videoLayout: 'picture_in_picture', degradesToAsync: true,
    blurb: 'Draw on the same page. He watches the line appear.' },
].map(register);

export const liveForAge = (age: number) => LIVE_GAMES.filter(g => age >= g.minAge);

/** Structural audit: no live game may hide the video or need reflexes. */
export function auditLive(g: LiveGame): { ok: true } | { ok: false; problems: string[] } {
  const problems: string[] = [];
  if ((g.videoLayout as string) === 'hidden' || (g.videoLayout as string) === 'fullscreen') {
    problems.push('hides the parent — the product is inverted');
  }
  if (g.minViableLatencyMs < MIN_VIABLE_LATENCY_MS) problems.push('reflex game');
  return problems.length ? { ok: false, problems } : { ok: true };
}

// ------------------------------------------------------------ prompt decks --
export interface Deck { kind: LiveKind; prompts: string[] }

export const DECKS: Deck[] = [
  { kind: 'simon_says', prompts: [
    'Simon says touch your nose', 'Simon says stand on one leg',
    'Simon says make your scariest face', 'Clap three times',
    'Simon says wave with both hands', 'Simon says pretend to be asleep',
    'Touch your toes', 'Simon says show me your teeth' ] },
  { kind: 'copy_me', prompts: [
    'Big slow arm circles', 'Pat your head and rub your tummy',
    'Blink one eye at a time', 'A very slow robot walk',
    'Shrug like you have no idea', 'Wiggle just your eyebrows' ] },
  { kind: 'charades', prompts: [
    'A cat who has just seen a cucumber', 'Brushing your teeth',
    'A very tired elephant', 'Someone carrying too many bags',
    'A chicken crossing a road', 'Trying not to sneeze',
    'A robot that needs charging', 'Eating something far too hot' ] },
  { kind: 'i_spy', prompts: [
    'something in my room that is blue', 'something behind me that is old',
    'something you gave me', 'something in your room that is round',
    'something I have had since before you were born' ] },
  { kind: 'show_me', prompts: [
    'Show me something round', 'Show me something you made',
    'Show me the softest thing near you', 'Show me something blue',
    'Show me something you are proud of', 'Show me where you like to sit',
    'Show me something noisy' ] },
  { kind: 'would_you_rather', prompts: [
    'Would you rather be invisible or be able to fly?',
    'Would you rather never eat chocolate again or never watch TV again?',
    'Would you rather have a pet dragon or a pet dinosaur?',
    'Would you rather it always be raining or always be too hot?',
    'Would you rather be able to talk to animals or speak every language?' ] },
  { kind: 'two_truths', prompts: [
    'Two things I did before you were born, one made up',
    'Two things about my first job, one made up',
    'Two things about my worst holiday, one made up' ] },
  { kind: 'freeze_dance', prompts: ['Dance!', 'FREEZE', 'Dance!', 'FREEZE',
    'Slow motion dance', 'FREEZE'] },
  { kind: 'twenty_questions', prompts: ['Think of something. I get twenty questions.'] },
  { kind: 'pictionary', prompts: [
    'a house', 'a dog wearing a hat', 'the beach', 'a birthday cake',
    'a rocket', 'someone sneezing', 'a very tall tree', 'a bicycle' ] },
];

export interface DeckState { kind: LiveKind; remaining: string[]; drawn: string[] }

export function newDeck(kind: LiveKind, rand: () => number = Math.random): DeckState {
  const d = DECKS.find(x => x.kind === kind);
  const prompts = [...(d?.prompts ?? [])];
  // Shuffle so a second call is not the same call.
  for (let i = prompts.length - 1; i > 0; i--) {
    const j = Math.floor(rand() * (i + 1));
    [prompts[i], prompts[j]] = [prompts[j], prompts[i]];
  }
  return { kind, remaining: prompts, drawn: [] };
}

/**
 * Draw the next prompt. When the deck runs out it RESHUFFLES rather than
 * ending — a call should never be cut short because the cards ran out.
 */
export function draw(d: DeckState, rand: () => number = Math.random):
  { prompt: string; deck: DeckState } | null {
  if (!d.remaining.length && !d.drawn.length) return null;
  if (!d.remaining.length) {
    const fresh = newDeck(d.kind, rand);
    return { prompt: fresh.remaining[0],
      deck: { ...fresh, remaining: fresh.remaining.slice(1), drawn: [fresh.remaining[0]] } };
  }
  const [prompt, ...rest] = d.remaining;
  return { prompt, deck: { ...d, remaining: rest, drawn: [...d.drawn, prompt] } };
}

// ------------------------------------------------------------- the session --
export type ConnectionQuality = 'good' | 'poor' | 'lost';

export interface LiveSession {
  kind: LiveKind;
  startedAt: string;
  leader: Side;
  deck: DeckState;
  currentPrompt: string | null;
  /** Rounds completed. Not a score — there is no target and no record. */
  rounds: number;
  connection: ConnectionQuality;
  /** Set once the call drops and the game has become turn-based. */
  degradedAt: string | null;
}

export function startLive(
  kind: LiveKind, leader: Side, at: string, rand: () => number = Math.random,
): { ok: true; session: LiveSession } | { ok: false; reason: 'unknown_game' } {
  const g = LIVE_GAMES.find(x => x.kind === kind);
  if (!g) return { ok: false, reason: 'unknown_game' };
  const deck = newDeck(kind, rand);
  const d = draw(deck, rand);
  return { ok: true, session: {
    kind, leader, startedAt: at, deck: d?.deck ?? deck,
    currentPrompt: d?.prompt ?? null, rounds: 0,
    connection: 'good', degradedAt: null,
  }};
}

export function nextRound(s: LiveSession, rand: () => number = Math.random): LiveSession {
  const d = draw(s.deck, rand);
  return { ...s, deck: d?.deck ?? s.deck, currentPrompt: d?.prompt ?? null,
    rounds: s.rounds + 1,
    // Alternate who leads, so the child is not always the one being tested.
    leader: s.leader === 'A' ? 'B' : 'A' };
}

/**
 * §5.19 — when the call quality drops, say so plainly and blame the connection.
 * "You're being slow" is what a laggy game implicitly tells a child; it must
 * never be what the product says.
 */
export function connectionMessage(q: ConnectionQuality): string | null {
  if (q === 'good') return null;
  if (q === 'poor') return 'The connection is slow right now — not you.';
  return 'The call dropped. Nothing is lost.';
}

/**
 * Constraint 3: a live game degrades rather than dying.
 *
 * Progress is preserved and the game becomes turn-based. Games that cannot
 * survive the transition — the ones that need a live camera, like Simon Says —
 * say so honestly instead of pretending.
 */
export function degradeToAsync(s: LiveSession, at: string):
  | { ok: true; session: LiveSession; note: string }
  | { ok: false; reason: 'needs_live_camera'; note: string } {
  const g = LIVE_GAMES.find(x => x.kind === s.kind)!;
  if (!g.degradesToAsync) {
    return { ok: false, reason: 'needs_live_camera',
      note: `${g.title} needs to see each other. It is saved for next time.` };
  }
  return { ok: true,
    session: { ...s, connection: 'lost', degradedAt: at },
    note: `${g.title} is waiting for you both. Take your turn whenever.` };
}

export function isDegraded(s: LiveSession): boolean { return s.degradedAt !== null; }

// --------------------------------------------------------------- layout ----
/**
 * The Galaxy Z Fold 5's main screen is 673 x 841 — nearly square — so the video
 * and the board genuinely fit SIDE BY SIDE, with the crease as the divider. On a
 * tall phone you would have to choose one or the other. Folded, it is video with
 * the board as a strip beneath.
 *
 * Whatever the layout, the parent's face is never covered. That is the
 * constraint the return type exists to make unrepresentable.
 */
export function liveLayout(viewportWidth: number, viewportHeight: number): {
  arrangement: 'side_by_side' | 'stacked';
  videoFraction: number;
  videoVisible: true;
  reason: string;
} {
  const ratio = viewportWidth / viewportHeight;
  if (viewportWidth >= 600 && ratio > 0.65) {
    return { arrangement: 'side_by_side', videoFraction: 0.5, videoVisible: true,
      reason: 'Nearly square — video and board fit beside each other, gutter on the crease.' };
  }
  return { arrangement: 'stacked', videoFraction: 0.42, videoVisible: true,
    reason: 'Narrow — video on top, board beneath. The face stays visible.' };
}

/** Fields that must never appear in a live session shown to a child. */
export const LIVE_FORBIDDEN = [
  'score', 'points', 'streak', 'record', 'best', 'highScore', 'reactionMs',
  'reaction_ms', 'accuracy', 'rank', 'timeLeft', 'countdown',
] as const;

export function auditLiveView(v: unknown): { ok: true } | { ok: false; leaks: string[] } {
  const leaks: string[] = [];
  const walk = (x: unknown) => {
    if (Array.isArray(x)) return x.forEach(walk);
    if (x && typeof x === 'object') for (const [k, val] of Object.entries(x)) {
      if ((LIVE_FORBIDDEN as readonly string[]).some(f => k.toLowerCase() === f.toLowerCase())) {
        leaks.push(k);
      }
      walk(val);
    }
  };
  walk(v);
  return leaks.length ? { ok: false, leaks: [...new Set(leaks)] } : { ok: true };
}

// ---------------------------------------------------------- pictionary -----
/**
 * Reuses the §9.1 shared canvas entirely — stroke sync, per-actor undo, and the
 * ephemeral pointer are already built and tested. The only new pieces are a word
 * to draw and a guess.
 */
export interface Pictionary {
  word: string;
  drawer: Side;
  guesses: { side: Side; text: string; correct: boolean }[];
  solved: boolean;
}

export function newPictionary(word: string, drawer: Side): Pictionary {
  return { word: word.toLowerCase(), drawer, guesses: [], solved: false };
}

export function guessDrawing(p: Pictionary, side: Side, text: string):
  { ok: true; state: Pictionary; correct: boolean } | { ok: false; reason: string } {
  if (p.solved) return { ok: false, reason: 'already_solved' };
  if (side === p.drawer) return { ok: false, reason: 'drawer_cannot_guess' };
  if (!text.trim()) return { ok: false, reason: 'empty_guess' };
  const correct = text.trim().toLowerCase() === p.word;
  return { ok: true, correct, state: { ...p, solved: correct,
    guesses: [...p.guesses, { side, text: text.trim(), correct }] } };
}
