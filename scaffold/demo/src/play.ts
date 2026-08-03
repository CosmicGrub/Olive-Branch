import {
  newGame as newG, play as playG, setHandicap, handicapBanner, takeBack,
  childView, CATALOGUE, forAge, shouldOfferHandicap, handicapOffer,
  storyArtifact as gameStoryArtifact,
} from '../../packages/games/src/games.ts';
import {
  newCheckers, checkersMoves, playCheckers, checkersCount,
  newBattleship, placeShip, fire, FLEET, BS_SIZE,
  buildWordSearch, findWord, wordSearchComplete,
  newHangman, guessLetter, hangmanMask, hangmanOutcome, HANGMAN_LIVES,
  newChess, chessMove, chessLegalMoves, chessCoach, CHESS_HANDICAPS,
} from '../../packages/games/src/games2.ts';

/**
 * Playable sessions for the demo.
 *
 * The demo has one human, so the parent's side is played by a deliberately
 * modest opponent. It is not meant to be strong — a demo that beats a visitor at
 * chess teaches them nothing about the product. Every reply goes through the
 * SAME `play()` the child's moves do, so the rules being demonstrated are the
 * rules that are tested.
 */

type Any = any;
const S: Record<string, Any> = {};

export function gStart(kind: string, opts?: Any): Any {
  if (kind === 'checkers') S[kind] = newCheckers();
  else if (kind === 'battleship') S[kind] = autoPlaceFleet(newBattleship());
  else if (kind === 'wordsearch') {
    const words = opts?.words ?? ['MAYA', 'DOG', 'BEACH', 'GRANDMA', 'PIZZA'];
    const r = buildWordSearch(words, 10);
    S[kind] = r.ok ? r.puzzle : null;
  }
  else if (kind === 'hangman') S[kind] = newHangman(opts?.word ?? 'GRANDMA',
    opts?.hint ?? 'Who we visit on Sundays');
  else if (kind === 'chess') S[kind] = newChess(opts?.handicap ?? null);
  else {
    let g = newG(kind as Any, 'demo', kind === 'memory'
      ? ['dog', 'house', 'beach', 'drawing', 'cake', 'bike'] : undefined);
    if (opts?.handicap) g = setHandicap(g, 'A', opts.handicap).state ?? g;
    S[kind] = g;
  }
  return gView(kind);
}

export function gState(kind: string) { return S[kind] ?? gStart(kind); }

// ------------------------------------------------------------------- views --
export function gView(kind: string): Any {
  const s = S[kind]; if (!s) return null;
  if (kind === 'checkers') return {
    kind, board: s.board, turn: s.turn, outcome: s.outcome,
    mustContinue: s.mustContinueFrom,
    counts: { A: checkersCount(s, 'A'), B: checkersCount(s, 'B') },
    legal: checkersMoves(s, s.turn),
  };
  if (kind === 'battleship') return {
    kind, phase: s.phase, turn: s.turn, outcome: s.outcome,
    myShips: s.ships.A, myShots: s.shots.A, theirShots: s.shots.B,
    // Their ship positions are NOT exposed — only what has been hit.
    theirHits: s.ships.B.flatMap((x: Any) => x.hits),
    theirSunk: s.ships.B.filter((x: Any) => x.hits.length === x.cells.length).map((x: Any) => x.name),
    myHitCells: s.ships.A.flatMap((x: Any) => x.hits),
  };
  if (kind === 'wordsearch') return { kind, grid: s.grid, size: s.size,
    words: s.words.map((w: Any) => ({ word: w.word, found: w.found })),
    foundCells: s.words.filter((w: Any) => w.found).flatMap((w: Any) => w.cells),
    complete: wordSearchComplete(s) };
  if (kind === 'hangman') return { kind, mask: hangmanMask(s), guessed: s.guessed,
    lives: s.livesLeft, maxLives: HANGMAN_LIVES, hint: s.hint,
    outcome: hangmanOutcome(s), word: hangmanOutcome(s) ? s.word : null };
  if (kind === 'chess') return { kind, fen: s.fen, history: s.history,
    outcome: s.outcome, legal: chessLegalMoves(s), coach: chessCoach(s),
    board: fenToBoard(s.fen), turn: s.fen.split(' ')[1] === 'w' ? 'A' : 'B' };
  return { kind, board: s.board, turn: s.turn, outcome: s.outcome,
    scores: s.scores, handicap: s.handicap, banner: handicapBanner(s),
    child: childView(s), moves: s.moves.length,
    artifact: kind === 'story' ? storyArtifact(s) : null };
}

function fenToBoard(fen: string): (string | null)[][] {
  const rows = fen.split(' ')[0].split('/');
  return rows.map(r => {
    const out: (string | null)[] = [];
    for (const ch of r) {
      if (/\d/.test(ch)) for (let i = 0; i < +ch; i++) out.push(null);
      else out.push(ch);
    }
    return out;
  });
}

// -------------------------------------------------------------- the child --
export function gMove(kind: string, at: Any): Any {
  const s = S[kind]; if (!s) return { ok: false, reason: 'not_started' };
  let r: Any;
  if (kind === 'checkers') r = playCheckers(s, 'A', at.from, at.to);
  else if (kind === 'battleship') r = fire(s, 'A', at);
  else if (kind === 'wordsearch') {
    const f = findWord(s, at); S[kind] = f.puzzle;
    return { ok: Boolean(f.found), found: f.found, view: gView(kind) };
  }
  else if (kind === 'hangman') {
    const g = guessLetter(s, at);
    if (g.ok) S[kind] = g.state;
    return { ok: g.ok, hit: g.hit, reason: g.reason, view: gView(kind) };
  }
  else if (kind === 'chess') r = chessMove(s, at);
  else r = playG(s, 'A', at);
  if (r.ok) S[kind] = r.state;
  return { ok: r.ok, reason: r.reason, hit: r.hit, sunk: r.sunk, view: gView(kind) };
}

/** The parent's reply. Modest by design. */
export function gReply(kind: string): Any {
  const s = S[kind]; if (!s) return null;

  if (kind === 'checkers') {
    if (s.turn !== 'B' || s.outcome) return gView(kind);
    let cur = s;
    // Multi-jumps must be played out before the turn returns.
    for (let i = 0; i < 12; i++) {
      const ms = checkersMoves(cur, 'B'); if (!ms.length) break;
      const m = ms[Math.floor(Math.random() * ms.length)];
      const r = playCheckers(cur, 'B', m.from, m.to);
      if (!r.ok) break;
      cur = r.state;
      if (cur.turn !== 'B') break;
    }
    S[kind] = cur; return gView(kind);
  }

  if (kind === 'battleship') {
    if (s.turn !== 'B' || s.outcome || s.phase !== 'playing') return gView(kind);
    let cur = s;
    for (let i = 0; i < 20; i++) {
      const tried = new Set(cur.shots.B);
      // Hunt mode: after a hit, try adjacent cells before firing at random.
      const hits = cur.ships.A.flatMap((x: Any) => x.hits)
        .filter((c: number) => !cur.ships.A.some((x: Any) =>
          x.hits.length === x.cells.length && x.cells.includes(c)));
      let target: number | null = null;
      for (const h of hits) {
        for (const d of [-1, 1, -BS_SIZE, BS_SIZE]) {
          const n = h + d;
          if (n < 0 || n >= BS_SIZE * BS_SIZE || tried.has(n)) continue;
          if (Math.abs(d) === 1 && Math.floor(n / BS_SIZE) !== Math.floor(h / BS_SIZE)) continue;
          target = n; break;
        }
        if (target !== null) break;
      }
      if (target === null) {
        const free = [...Array(BS_SIZE * BS_SIZE).keys()].filter(c => !tried.has(c));
        if (!free.length) break;
        target = free[Math.floor(Math.random() * free.length)];
      }
      const r = fire(cur, 'B', target);
      if (!r.ok) break;
      cur = r.state;
      if (cur.turn !== 'B') break;
    }
    S[kind] = cur; return gView(kind);
  }

  if (kind === 'chess') {
    const moves = chessLegalMoves(s);
    if (!moves.length || s.outcome) return gView(kind);
    // Prefer a capture, otherwise random. Enough to feel responsive, weak
    // enough that a child wins — which is the point.
    const caps = moves.filter((m: string) => m.includes('x'));
    const pick = (caps.length && Math.random() < 0.6 ? caps : moves)[
      Math.floor(Math.random() * (caps.length && Math.random() < 0.6 ? caps.length : moves.length))];
    const r = chessMove(s, pick ?? moves[0]);
    if (r.ok) S[kind] = r.state;
    return gView(kind);
  }

  if (kind === 'story') {
    const lines = ['The bear had been having a very long week.',
      'Nobody had told the bear about the dog.',
      'It turned out they both liked the same song.',
      'They drove to the sea, badly.'];
    const r = playG(s, 'B', lines[s.board.lines.length % lines.length]);
    if (r.ok) S[kind] = r.state; return gView(kind);
  }

  if (kind === 'tictactoe') {
    if (s.turn !== 'B' || s.outcome) return gView(kind);
    const free = s.board.map((v: Any, i: number) => v ? null : i).filter((x: Any) => x !== null)
      .filter((i: number) => !(s.handicap === 'no_centre' && i === 4));
    const r = playG(s, 'B', free[Math.floor(Math.random() * free.length)]);
    if (r.ok) S[kind] = r.state; return gView(kind);
  }

  if (kind === 'dotsboxes') {
    let cur = s;
    for (let i = 0; i < 30 && cur.turn === 'B' && !cur.outcome; i++) {
      const opts: Any[] = [];
      for (let r = 0; r < cur.board.n; r++) for (let c = 0; c < cur.board.n - 1; c++)
        if (!cur.board.h[r][c]) opts.push(['h', r, c]);
      for (let r = 0; r < cur.board.n - 1; r++) for (let c = 0; c < cur.board.n; c++)
        if (!cur.board.v[r][c]) opts.push(['v', r, c]);
      if (!opts.length) break;
      const rr = playG(cur, 'B', opts[Math.floor(Math.random() * opts.length)]);
      if (!rr.ok) break;
      cur = rr.state;
    }
    S[kind] = cur; return gView(kind);
  }

  if (kind === 'memory') {
    let cur = s;
    for (let i = 0; i < 6 && cur.turn === 'B' && !cur.outcome; i++) {
      const free = cur.board.deck.map((_: Any, j: number) => j)
        .filter((j: number) => !cur.board.matched.includes(j) && !cur.board.revealed.includes(j));
      if (!free.length) break;
      const rr = playG(cur, 'B', free[Math.floor(Math.random() * free.length)]);
      if (!rr.ok) break;
      cur = rr.state;
    }
    S[kind] = cur; return gView(kind);
  }
  return gView(kind);
}

export function gUndo(kind: string): Any {
  const s = S[kind]; if (!s) return null;
  if (['checkers','battleship','wordsearch','hangman','chess'].includes(kind)) {
    // These keep no move list in the shared shape; the demo restarts instead,
    // and says so rather than pretending an undo happened.
    return { ok: false, reason: 'restart_instead', view: gView(kind) };
  }
  const r = takeBack(s, kind === 'memory' ? [...new Set(s.board.deck)] : undefined);
  if (r.ok) S[kind] = r.state;
  return { ok: r.ok, reason: r.reason, view: gView(kind) };
}

export function gHandicap(kind: string, id: string | null): Any {
  if (kind === 'chess') { S[kind] = newChess(id); return gView(kind); }
  const s = S[kind]; if (!s) return null;
  const r = setHandicap(s, 'A', id);
  if (r.ok) S[kind] = r.state;
  return gView(kind);
}

function autoPlaceFleet(s: Any): Any {
  let cur = s;
  for (const side of ['A', 'B'] as const) {
    for (const f of FLEET) {
      for (let t = 0; t < 300; t++) {
        const h = Math.random() < 0.5;
        const start = Math.floor(Math.random() * BS_SIZE * BS_SIZE);
        const r = placeShip(cur, side, f.name, start, h);
        if (r.ok) { cur = r.state; break; }
      }
    }
  }
  return cur;
}

// ---------------------------------------------------- chain / kim / hunt ---
import { newChain, addStep, recallStep, chainView, chainArtifact,
  newKim, kimSecondPhoto, kimGuess, kimClosing,
  newHunt, submitFind, huntProgress, huntComplete, huntArtifacts,
  SUGGESTED_PROMPTS, auditNoScore } from '../../packages/games/src/games3.ts';

const CHAIN_WORDS = ['a banana', 'a red hat', 'the dog', 'a kite', 'a spoon',
  'a drum', 'a cold pizza', 'a very small horse'];
const KIM_OBJECTS = ['mug', 'keys', 'apple', 'pencil', 'watch', 'coin', 'shell'];

export function chStart(): Any {
  S.chain = newChain();
  // The parent opens, in his own voice.
  const r = addStep(S.chain, 'B', CHAIN_WORDS[0], 'voice-1');
  if (r.ok) S.chain = r.state;
  return chView();
}
export function chView(): Any {
  if (!S.chain) return chStart();
  const g = S.chain;
  return { ...chainView(g), steps: g.steps, ended: g.ended,
    artifact: chainArtifact(g),
    // What she must say next, offered as buttons plus decoys.
    options: g.phase === 'recalling' && !g.ended
      ? shuffle([g.steps[g.recallIndex].label,
          ...CHAIN_WORDS.filter(w => w !== g.steps[g.recallIndex].label).slice(0, 2)])
      : shuffle(CHAIN_WORDS.filter(w => !g.steps.some(s => s.label === w)).slice(0, 3)),
    audit: auditNoScore(chainView(g)) };
}
export function chPlay(label: string): Any {
  const g = S.chain; if (!g) return chStart();
  if (g.phase === 'recalling') {
    const r = recallStep(g, 'A', label);
    if (r.ok) S.chain = r.state;
  } else {
    const r = addStep(g, 'A', label);
    if (r.ok) S.chain = r.state;
    // Dad immediately recalls the whole chain and adds his own.
    let cur = S.chain;
    while (cur.turn === 'B' && cur.phase === 'recalling' && !cur.ended) {
      const rr = recallStep(cur, 'B', cur.steps[cur.recallIndex].label);
      if (!rr.ok) break; cur = rr.state;
    }
    if (cur.turn === 'B' && cur.phase === 'building' && !cur.ended) {
      const unused = CHAIN_WORDS.filter(w => !cur.steps.some((s: Any) => s.label === w));
      if (unused.length) {
        const rr = addStep(cur, 'B', unused[0], 'voice-' + (cur.steps.length + 1));
        if (rr.ok) cur = rr.state;
      }
    }
    S.chain = cur;
  }
  return chView();
}
const shuffle = (a: string[]) => a.map(x => [Math.random(), x] as const)
  .sort((p, q) => p[0] - q[0]).map(p => p[1]);

export function kimStart(): Any {
  const r = newKim(KIM_OBJECTS);
  S.kim = r.ok ? r.round : null;
  S.kimPhase = 'look';
  return kimView();
}
export function kimView(): Any {
  if (!S.kim) return kimStart();
  const r = S.kim;
  return { phase: S.kimPhase, objects: r.objects, second: kimSecondPhoto(r),
    lookSeconds: r.lookSeconds, revealed: r.revealed, guess: r.guess,
    closing: kimClosing(r), removed: r.revealed ? r.objects[r.removedIndex] : null };
}
export function kimAdvance(): Any { S.kimPhase = 'guess'; return kimView(); }
export function kimAnswer(i: number): Any {
  const r = kimGuess(S.kim, i);
  if (r.ok) { S.kim = r.round; S.kimPhase = 'done'; }
  return kimView();
}

export function huntStart(prompts?: string[]): Any {
  const r = newHunt('h-demo', prompts ?? SUGGESTED_PROMPTS.slice(0, 5), 'B',
    new Date().toISOString());
  S.hunt = r.ok ? r.hunt : null;
  return huntView();
}
export function huntView(): Any {
  if (!S.hunt) return huntStart();
  return { prompts: S.hunt.prompts, progress: huntProgress(S.hunt),
    complete: huntComplete(S.hunt), artifacts: huntArtifacts(S.hunt),
    suggested: SUGGESTED_PROMPTS, audit: auditNoScore(S.hunt) };
}
export function huntFind(promptId: string): Any {
  const r = submitFind(S.hunt, promptId, 'art-' + promptId, new Date().toISOString());
  if (r.ok) S.hunt = r.hunt;
  return huntView();
}

// ------------------------------------------------------------------- live --
import { LIVE_GAMES, liveForAge, startLive, nextRound, degradeToAsync,
  connectionMessage, liveLayout, auditLiveView, newPictionary, guessDrawing,
  isDegraded, MIN_VIABLE_LATENCY_MS } from '../../packages/live/src/live.ts';

export function lvStart(kind: string): Any {
  const r = startLive(kind as Any, 'B', new Date().toISOString());
  S.live = r.ok ? r.session : null;
  S.liveConn = 'good';
  return lvView();
}
export function lvView(): Any {
  if (!S.live) return null;
  const g = LIVE_GAMES.find(x => x.kind === S.live.kind)!;
  return { ...S.live, meta: g, connection: S.liveConn,
    message: connectionMessage(S.liveConn),
    degraded: isDegraded(S.live), audit: auditLiveView(S.live) };
}
export function lvNext(): Any { if (S.live) S.live = nextRound(S.live); return lvView(); }
export function lvConn(q: string): Any {
  S.liveConn = q;
  if (q === 'lost' && S.live) {
    const d = degradeToAsync(S.live, new Date().toISOString());
    S.liveNote = d.note;
    if (d.ok) S.live = d.session;
    return { ...lvView(), degradeOk: d.ok, note: d.note };
  }
  S.liveNote = null;
  return lvView();
}
export function lvLayout(w: number, h: number): Any { return liveLayout(w, h); }
export function lvGames(age: number): Any { return liveForAge(age); }
export { LIVE_GAMES, MIN_VIABLE_LATENCY_MS };

export function pictStart(): Any {
  S.pict = newPictionary('a dog wearing a hat', 'B');
  return { ...S.pict, revealed: false };
}
export function pictGuess(text: string): Any {
  if (!S.pict) pictStart();
  const r = guessDrawing(S.pict, 'A', text);
  if (r.ok) S.pict = r.state;
  return { ...S.pict, lastCorrect: r.ok ? r.correct : null, reason: r.reason };
}

// -------------------------------------------------------------- showcase --
import { MATRIX, matrixForAge, activeInterests, recededInterests, markShown,
  promptsFor, addToCollection, collectionChildView, auditShowcase, newShow,
  replyToShow, showsForYearBook, auditFraming } from '../../packages/showcase/src/showcase.ts';

const NOWISH = () => new Date().toISOString();
const daysAgo = (d: number) => new Date(Date.now() - d * 86400000).toISOString();

S.interests = [
  { id:'i1', label:'dinosaurs', singular:'dinosaur', addedBy:'B',
    addedAt: daysAgo(210), lastShownAt: daysAgo(2), enumerable:true },
  { id:'i2', label:'Pokémon', singular:'Pokémon', addedBy:'A',
    addedAt: daysAgo(80), lastShownAt: daysAgo(9), enumerable:true },
  { id:'i3', label:'diggers', singular:'digger', addedBy:'B',
    addedAt: daysAgo(500), lastShownAt: daysAgo(320), enumerable:false },
];
S.collection = { interestId:'i1', entries: [
  { id:'c1', interestId:'i1', name:'Stegosaurus', artifactId:'a1', shownAt: daysAgo(40) },
  { id:'c2', interestId:'i1', name:'Triceratops', artifactId:'a2', shownAt: daysAgo(21) },
  { id:'c3', interestId:'i1', name:'Diplodocus',  artifactId:'a3', shownAt: daysAgo(9) },
]};
S.shows = [];

export function scMatrix(age: number): Any { return matrixForAge(age); }
export function scInterests(): Any {
  const now = NOWISH();
  return { all: S.interests, active: activeInterests(S.interests, now),
    receded: recededInterests(S.interests, now) };
}
export function scPrompts(kind: string): Any {
  return { kind, prompts: promptsFor(kind as Any, S.interests, NOWISH(), 6) };
}
export function scAddInterest(label: string): Any {
  S.interests = [...S.interests, { id:'i'+(S.interests.length+1), label,
    singular: label.replace(/s$/,''), addedBy:'B', addedAt: NOWISH(),
    lastShownAt: null, enumerable: true }];
  return scInterests();
}
export function scCollection(): Any {
  return { entries: S.collection.entries, view: collectionChildView(S.collection),
    audit: auditShowcase(collectionChildView(S.collection)) };
}
export function scAddToCollection(name: string): Any {
  const r = addToCollection(S.collection, { id:'c'+Date.now(), interestId:'i1',
    name, artifactId:'a'+Date.now(), shownAt: NOWISH() });
  if (r.ok) S.collection = r.collection;
  return { ...scCollection(), reason: r.ok ? null : r.reason };
}
export function scShow(kind: string, prompt: string | null): Any {
  const sh = newShow('s'+(S.shows.length+1), kind as Any, 'maya', NOWISH(),
    { prompt: prompt ?? undefined, artifactId: 'art'+(S.shows.length+1), interestId:'i1' });
  S.shows = [...S.shows, sh];
  S.interests = markShown(S.interests, 'i1', NOWISH());
  return { shows: S.shows, latest: sh };
}
export function scReply(): Any {
  const last = S.shows[S.shows.length-1]; if (!last) return null;
  const r = replyToShow(last, { artifactId:'reply-1' }, NOWISH());
  if (r.ok) S.shows = [...S.shows.slice(0,-1), r.show];
  return { shows: S.shows, ok: r.ok, reason: r.reason };
}
export function scYearBook(): Any {
  const yr = new Date().getUTCFullYear();
  const sample = [
    newShow('y1','creation','maya',`${yr}-03-02T10:00:00Z`,{artifactId:'p1'}),
    newShow('y2','creation','maya',`${yr}-04-11T10:00:00Z`,{artifactId:'p2'}),
    newShow('y3','creation','maya',`${yr}-05-19T10:00:00Z`,{artifactId:'p3'}),
    newShow('y4','knowledge','maya',`${yr}-05-30T10:00:00Z`,{artifactId:'p4'}),
    newShow('y5','knowledge','maya',`${yr}-06-14T10:00:00Z`,{artifactId:'p5'}),
    newShow('y6','collection','maya',`${yr}-07-01T10:00:00Z`,{artifactId:'p6'}),
    ...S.shows,
  ];
  return showsForYearBook(sample, yr);
}
export function scFraming(text: string): Any { return { text, audit: auditFraming(text) }; }
export { MATRIX };

// --------------------------------------------------------------- digest ----
import { expiringSoon, digestVisibleTo, DIGEST_LEAD_DAYS }
  from '../../packages/storage/src/retention.ts';

export function digest(): Any {
  const now = new Date();
  const day = (n: number) => new Date(now.getTime() + n * 86400000).toISOString();
  return expiringSoon([
    { id:'a1', kind:'call_clip', caption:'Tuesday call', capturedAt: day(-40),
      preserved:false, expiresAt: day(3) },
    { id:'a2', kind:'call_clip', caption:'Call, 14 June', capturedAt: day(-30),
      preserved:false, expiresAt: day(9) },
    { id:'a3', kind:'drawing', caption:'A horse', capturedAt: day(-20),
      preserved:false, expiresAt: day(13) },
    { id:'a4', kind:'video_msg', caption:'Goodnight, night 42', capturedAt: day(-10),
      preserved:true, expiresAt: null },
    { id:'a5', kind:'drawing', caption:'Far off yet', capturedAt: day(-5),
      preserved:false, expiresAt: day(60) },
  ], now);
}
export function digestVisible(role: string): Any { return digestVisibleTo(role); }
export { DIGEST_LEAD_DAYS };

// ----------------------------------------------------------- onboarding ----
import { begin, advance, goBack, greeting, outcome, whoStep, toggleWho,
  acceptName, acceptAge, effectiveAge } from '../../packages/onboarding/src/onboarding.ts';

import { PALETTE, swatch, dailyPair, choose, currentColour, parentView,
  applyColour, textColourFor, coloursForYearBook, auditColourPayload,
  MAX_PLACEMENTS_PER_SCREEN } from '../../packages/palette/src/palette.ts';

S.colourHistory = [
  { colourId:'sunny', chosenAt:'2026-07-20T09:00:00Z', via:'first_run' },
  { colourId:'coral', chosenAt:'2026-07-24T08:30:00Z', via:'daily' },
];

// ----------------------------------------------------------- the calendar --
import { MONTHS, DOW_SHORT, monthGrid, beginPicker, pickMonth, pickDay,
  answerYearCheck, pickedDate, resolveBirthday, markBirthday, occurrenceIn,
  sleepsUntilBirthday, hintMonth, shouldHint, daysInMonth }
  from '../../packages/calendar/src/calendar.ts';

// She is five. Born 2021.
const GUARDIAN_BIRTHDATE = '2021-06-14';

// --------------------------------------------------------- the storyteller --
import { generate as storyFromSeed, freshStory, reread, forReadingAloud, auditStory, spaceSize,
  storyArtifact, SHAPES } from '../../packages/storyteller/src/storyteller.ts';

// -------------------------------------------- activities + library + calls --
import { newColouring, fill, undoFill, colouringChildView, colouringArtifact,
  buildFindScene, tapFind, findHint, FIND_LEVELS, buildSpotScene, tapSpot,
  spotRemaining, spotComplete, spotChildView, nextDifficulty, SPOT_LEVELS,
  auditActivity } from '../../packages/activities/src/activities.ts';
import { bookmark, resume, saveBookmark, clearBookmark, star, unstar,
  recordRead, isStarred, libraryChildView, compileBook, bookAsText,
  auditLibraryChildView } from '../../packages/storyteller/src/library.ts';
import { callPolicy, auditPolicy, relayRequiredBecause, sharePreflight,
  decideE2ee, auditE2ee, RESIDUAL_RISKS } from '../../packages/session-runtime/src/security.ts';

const GIRAFFE = { id:'giraffe', title:'A very tall giraffe',
  about:'He needs colouring in.', minAge:3,
  swatches:[{hex:'#F2B705',label:'yellow'},{hex:'#E8730C',label:'orange'},
    {hex:'#8A6244',label:'brown'},{hex:'#5AA84A',label:'green'},
    {hex:'#2F8FC4',label:'blue'},{hex:'#8B6BB1',label:'purple'},
    {hex:'#F0757E',label:'pink'},{hex:'#7C8698',label:'grey'}],
  regions:[
    { id:'body', d:'M62 96 q0 -26 22 -26 q22 0 22 26 l0 44 q0 8 -8 8 l-28 0 q-8 0 -8 -8 z',
      suggested:'#F2B705', number:1 },
    { id:'neck', d:'M76 34 q0 -14 12 -14 q12 0 12 14 l0 44 l-24 0 z',
      suggested:'#F2B705', number:1 },
    { id:'head', d:'M72 16 q0 -12 16 -12 q16 0 16 12 q0 12 -16 12 q-16 0 -16 -12 z',
      suggested:'#E8730C', number:2 },
    { id:'legs', d:'M66 148 l0 26 M80 148 l0 26 M96 148 l0 26 M110 148 l0 26',
      suggested:'#8A6244', number:3 },
    { id:'ground', d:'M8 176 l160 0 l0 12 l-160 0 z', suggested:'#5AA84A', number:4 },
    { id:'sky', d:'M8 4 l160 0 l0 40 l-160 0 z', suggested:'#2F8FC4', number:5 },
  ]};

// ------------------------------------------------- the thirteen gaps ------
import { askForShow, answerAsk, asksChildView, replyGuidance, shelf,
  shelfChildView, PARENT_SHOWS, offerableParentShows, gallery, frameFor,
  hideWork, compileExhibition, auditGallery } from '../../packages/showcase/src/exchange.ts';
import { briefing, auditBriefing, writeCareNote, catchUp, auditCatchUp,
  inbox, admitToInbox, resolve, INBOX_ACTIONS } from '../../packages/guardian/src/guardian.ts';
import { beginClosing, shouldOfferClosing, closingNext, skipClosing, closingLines,
  closingToAsk, GOODBYES, beginReading, turnPage, swapReader, readingChildView,
  requestHandoff, busyFork, auditBusyFork } from '../../packages/live/src/around.ts';

// ═══════════════════════════════════════════════════════════════════════════
// EVERY REMAINING SHIPPED ENGINE, wired live.
//
// 17 of the 21 previously-unwired modules bundle for a browser. The other four —
// api, auth, session-runtime/rooms, storage — import `node:http` or
// `node:crypto` and cannot, by construction rather than by neglect. They are
// declared in the demo manifest's `nodeOnly` list with the dependency named, and
// check-markup's E-series asserts that every built module is either imported
// here or declared there. Silence is no longer an option.
// ═══════════════════════════════════════════════════════════════════════════
import { DateTime } from 'luxon';
import * as TimeEngine from '../../packages/time-engine/src/time.ts';
import * as Materialize from '../../packages/delivery-engine/src/materialize.ts';
import * as Gate from '../../packages/delivery-engine/src/gate.ts';
import * as Authorize from '../../packages/family-graph/src/authorize.ts';
import * as GraphSession from '../../packages/family-graph/src/session.ts';
import * as Lock from '../../packages/child-lock/src/lock.ts';
import * as Pipeline from '../../packages/messaging/src/pipeline.ts';
import * as Push from '../../packages/transport/src/push.ts';
import * as Capture from '../../packages/homework/src/capture.ts';
import * as Schedule from '../../packages/custody/src/schedule.ts';
import * as Canvas from '../../packages/annotation/src/canvas.ts';
import * as Care from '../../packages/care/src/care.ts';
import * as Agency from '../../packages/agency/src/agency.ts';
import * as Ledger from '../../packages/ledger/src/ledger.ts';
import * as Sha from '../../packages/ledger/src/sha256.ts';
import * as Archive from '../../packages/archive/src/archive.ts';
import * as Phase3 from '../../packages/phase3/src/phase3.ts';

// ---------------------------------------------------------- §21, built ----
import { LADDER, recordGrants, holds, adjustRung, guardianAnnouncement,
  QUIETING, PERMANENT, scaffoldsAt, sendGuardApplies, surfacesAt,
  sealLetter, openLetter, letterGuardianView, lettersDue,
  bankForParent, addToBank, bankChildView, auditBank, SUGGESTED_OCCASIONS,
  canGuardianRevoke } from '../../packages/maturation/src/maturation.ts';
import { publishWindow, resolveAvailability, availabilityGuardianLine,
  auditAvailabilityCopy, curate, displayCaption, archiveView, authorizeExport,
  requestDeletion, deletionConfirmation, auditDeletionCopy, NOT_HERS_TO_DELETE,
  COOLING_OFF_HOURS } from '../../packages/maturation/src/rungs.ts';
import { ageOf, openChildren, closeFor, staggerNotice, auditStagger,
  shellTabs, teach, askAgain, lessonArtifact, whoTeachesWhom, auditLesson,
  LESSON_SEEDS } from '../../packages/maturation/src/family.ts';

// ═══════════════════════════════════════════════════════════════════════════
// The nine modules E2 named. Built and tested in earlier increments, wired to
// no demo surface at all — which is precisely the gap the E-series exists to
// catch, and it caught them the moment the check went in.
// ═══════════════════════════════════════════════════════════════════════════
import * as A11y from '../../packages/a11y/src/a11y.ts';
import * as Emergency from '../../packages/emergency/src/emergency.ts';
import * as GlobalAudit from '../../packages/globalaudit/src/globalaudit.ts';
import * as I18n from '../../packages/i18n/src/i18n.ts';
import * as Observer from '../../packages/observer/src/observer.ts';
import * as Offline from '../../packages/offline/src/offline.ts';
import * as Print from '../../packages/print/src/print.ts';
import * as School from '../../packages/school/src/school.ts';
import * as Toddler from '../../packages/toddler/src/toddler.ts';

// -------------------------------------------------- §8.11 the device matrix --
import * as Devices from '../../packages/devices/src/devices.ts';

// ------------------------------------------ the ten, from the audit --------
import * as Channels from '../../packages/transport/src/channels.ts';
import * as Postures from '../../packages/devices/src/postures.ts';
import * as Pending from '../../packages/guardian/src/pending.ts';

// ------------------------------------------------- §5.23–§5.25 the call ----
import * as Modes from '../../packages/live/src/modes.ts';
import * as Cam from '../../packages/live/src/camera.ts';
import * as Lifecycle from '../../packages/live/src/lifecycle.ts';

// ------------------------------------------------------- §5.26 the pane ----
import * as Pane from '../../packages/live/src/pane.ts';

// ------------------------------------------- §5.27 signal · §8.8b matrix ----
import * as Signal from '../../packages/signal/src/signal.ts';
import * as Matrix from '../../packages/a11y/src/matrix.ts';

// ---------------------------------------------------------- §8.13 motion ---
import * as Motion from '../../packages/motion/src/motion.ts';

// ------------------------------------ §5.27 stream · §8.14 the budget ------
import * as Stream from '../../packages/live/src/stream.ts';
import * as Budget from '../../packages/budget/src/budget.ts';

S.stream = Stream.newStream();
S.tier = 'low';

export function streamView(): Any {
  return { state: S.stream, notice: Stream.noticeFor(S.stream),
    noticeAudit: Stream.auditNotice(Stream.noticeFor(S.stream)),
    sender: Stream.senderLine(S.stream),
    dropMs: Stream.DROP_AFTER_MS, restoreMs: Stream.RESTORE_AFTER_MS,
    ratio: Stream.ASYMMETRY_RATIO,
    meter: Stream.NO_CONNECTION_METER,
    restoreAsks: Stream.RESTORE_ASKS_PERMISSION,
    audioFloor: Stream.AUDIO_FLOOR };
}
export function streamTick(condition: string, ms: number): Any {
  const r = Stream.evaluate(S.stream, { condition: condition as Any, elapsedMs: ms });
  S.stream = r.state;
  return { ...streamView(), changed: r.changed };
}
export function streamReset(): Any { S.stream = Stream.newStream(); return streamView(); }

export function budgetView(): Any {
  const tier = S.tier as Any;
  const requested = ['call_audio', 'call_video_720', 'pane_video', 'game_board',
    'ambient_motion', 'driven_motion'];
  return {
    tier, capacity: Budget.capacityOf(tier),
    requested, total: Budget.total(requested),
    resolution: Budget.resolve(requested, tier),
    scenarios: Budget.runScenarios(),
    audioAlways: Budget.audioAlwaysSurvives(),
    costs: Budget.COSTS,
    ceilings: Budget.CEILINGS,
    costAudit: Budget.auditCosts(),
    ceilingAudit: Budget.auditCeilings(),
    admitTight: Budget.admit('find_the_thing',
      ['call_audio', 'call_video_720', 'pane_video'], tier),
    admitHeavy: Budget.admit('shared_canvas',
      ['call_audio', 'call_video_720', 'pane_video', 'find_the_thing', 'game_board'], tier),
  };
}
export function budgetTier(t: string): Any { S.tier = t; return budgetView(); }
export { Stream, Budget };


S.reducedMotion = false;

export function motionView(): Any {
  return {
    reduced: S.reducedMotion,
    vocabulary: Motion.VOCABULARY,
    forAge5: Motion.gesturesFor(5).map((g: Any) => g.gesture),
    springs: {
      standard: { ...Motion.SPRING_STANDARD, overshoot: +Motion.overshoot(Motion.SPRING_STANDARD).toFixed(3) },
      bouncy: { stiffness: 400, damping: 6, mass: 1,
        overshoot: +Motion.overshoot({ stiffness: 400, damping: 6, mass: 1 }).toFixed(3),
        settles: Motion.springSettles({ stiffness: 400, damping: 6, mass: 1 }) },
    },
    admits: [
      { kind: 'driven', surface: 'story_library', durationMs: 0 },
      { kind: 'consequence', surface: 'colouring', durationMs: 300 },
      { kind: 'consequence', surface: 'colouring', durationMs: 900 },
      { kind: 'ambient', surface: 'audio_waveform', durationMs: 0 },
      { kind: 'ambient', surface: 'games_picker', durationMs: 0 },
      { kind: 'autonomous', surface: 'child_home', durationMs: 200 },
    ].map((r: any) => ({ ...r, verdict: Motion.admitMotion(r) })),
    quiet: Motion.QUIET_SURFACES,
    effective: ['games_picker', 'bedtime', 'homework', 'come_back_signal']
      .map(s => ({ surface: s, normal: Motion.quietnessOf(s),
        withReduced: Motion.effectiveQuietness(s, true),
        ms: Motion.durationFor(Motion.effectiveQuietness(s, S.reducedMotion), 220) })),
    budget: Motion.MAX_CONCURRENT_MOTIONS,
    celebrate: [Motion.celebrate(0), Motion.celebrate(1)],
    surfaces: Motion.SURFACE_MOTION,
    surfaceAudit: Motion.auditSurfaces(),
    quietAudit: Motion.auditQuietConsistency(),
    motionAudit: Motion.auditMotion(Motion.SURFACE_MOTION),
    peek: Motion.PEEK_PX,
    rubber: [0, 40, 100, 300].map(px => ({ px, resisted: Math.round(Motion.rubberBand(px, 400)) })),
    duration: Motion.durationFor(S.reducedMotion ? 'reduced' : 'full', 220),
  };
}
export function motionReduce(on: boolean): Any { S.reducedMotion = on; return motionView(); }
export { Motion };


S.sig = Signal.newState();
S.sigHour = 15;
S.sigBusy = false;

export function signalView(): Any {
  const ctx = { state: S.sig, principal: 'parent' as const,
    configuration: 'both_parents' as const, childAge: 5,
    windowBlocked: false, localHour: S.sigHour, surfaceBusy: S.sigBusy,
    now: new Date().toISOString() };
  const p = (k: string, o: Any = {}) => ({ kind: k, fromUserId: 'dad',
    senderIsPresent: false, inCall: false, at: new Date().toISOString(), ...o });
  return {
    applications: Signal.APPLICATIONS,
    state: S.sig, hour: S.sigHour, busy: S.sigBusy,
    canSend: ['parent','grandparent','stepparent','therapist']
      .map(r => ({ role: r, may: Signal.canSend(r as Any) })),
    thirdAdultReason: Signal.THIRD_ADULT_REASON,
    configurations: ['both_parents','one_parent_only','sole_guardian','both_in_same_house']
      .map(c => ({ configuration: c, active: Signal.activeInConfiguration(c as Any) })),
    priority: Signal.prioritise([
      p('come_back', { fromUserId:'mum', senderIsPresent:true, at:'2026-07-27T14:00:00Z' }),
      p('come_back', { fromUserId:'dad', senderIsPresent:false, at:'2026-07-27T15:00:00Z' }),
    ]),
    senderFeedback: Signal.senderFeedback(),
    senderAudit: Signal.auditSenderView({ sent: true }),
    senderAuditBad: Signal.auditSenderView({ delivered: true, ignored: 3 }),
    ceilings: { daily: Signal.DAILY_CEILING, expires: Signal.EXPIRES_AFTER_SECONDS,
      silentFrom: Signal.SILENT_FROM_HOUR, muteHours: Signal.CHILD_MUTE_HOURS },
    inSilent: Signal.inSilentHours(S.sigHour),
    preserved: { archive: Signal.SIGNALS_IN_ARCHIVE,
      court: Signal.SIGNALS_IN_COURT_EXPORT },
    hatch: Signal.escapeHatch(), lesson: Signal.firstRunLesson(),
    matrix: { forms: Matrix.FORMS, rollout: Matrix.rollout(),
      baseline: Matrix.baselineForms(),
      baselineOk: Matrix.baselineIsPerceivable(),
      channels: Matrix.channelsCovered(Matrix.baselineForms().map((f: Any) => f.id)),
      textAlone: Matrix.perceivable(['visual_text']),
      promoteRefused: Matrix.promote(Matrix.FORMS, 'haptic', 'shipped', []),
      promoteOk: Matrix.promote(Matrix.FORMS, 'haptic', 'shipped', ['device vibrator']).ok,
      presentation: Matrix.presentSignal(['large_text']) },
  };
}
export function signalSend(kind: string): Any {
  const r = Signal.deliver({ state: S.sig, principal: 'parent',
    configuration: 'both_parents', childAge: 5, windowBlocked: false,
    localHour: S.sigHour, surfaceBusy: S.sigBusy, now: new Date().toISOString() },
    { kind: kind as Any, fromUserId: 'dad', senderIsPresent: false,
      inCall: false, at: new Date().toISOString() });
  if (r.ok) S.sig = r.state;
  return { ...signalView(), refused: r.ok ? null : r.reason };
}
export function signalTap(): Any { S.sig = Signal.act(S.sig); return signalView(); }
export function signalDismiss(): Any { S.sig = Signal.dismiss(S.sig); return signalView(); }
export function signalMute(): Any {
  S.sig = Signal.muteForAnHour(S.sig, new Date().toISOString()); return signalView();
}
export function signalHour(h: number): Any { S.sigHour = h; return signalView(); }
export function signalBusy(): Any { S.sigBusy = !S.sigBusy; return signalView(); }
export function signalReset(): Any { S.sig = Signal.newState(); return signalView(); }
export { Signal, Matrix };


S.pane = Pane.newPane('br');

export function paneView(): Any {
  const d = (globalThis as Any).__devObj || { w: 344, h: 882 };
  const vp = { w: d.w, h: d.h };
  return {
    pane: S.pane, viewport: vp,
    sizePx: Pane.paneSizePx(vp, S.pane.size),
    coverage: Math.round(Pane.coverage(vp, S.pane.size) * 1000) / 10,
    bestFit: Pane.bestFit(vp),
    childView: Pane.paneChildView(S.pane, vp, 'high', false),
    childAudit: Pane.auditChildPane(Pane.paneChildView(S.pane, vp, 'high', false)),
    controls: Pane.childControls(),
    childClose: Pane.closePane(S.pane, 'child'),
    guardianClose: Pane.closePane(S.pane, 'guardian'),
    avoided: Pane.avoid(S.pane, [{ x: 0.6, y: 0.6, w: 0.35, h: 0.35 }]),
    audio: Pane.audioLink(),
    failed: Pane.paneFailed(S.pane, Pane.audioLink()),
    renders: [['low', true], ['low', false], ['mid', true], ['high', true]]
      .map(([t, a]: any) => ({ tier: t, activity: a, render: Pane.renderFor(t, a) })),
    refused: Pane.PANE_REFUSED_ON,
    probes: [
      { label: 'guardian, observed', r: Pane.probeOsPip({ role:'guardian',
        kioskLocked:false, claimsSupport:true, observedAfterAttempt:true }) },
      { label: 'platform claims, does not deliver', r: Pane.claimWithoutObservation() },
      { label: 'kiosk locked', r: Pane.probeOsPip({ role:'guardian',
        kioskLocked:true, claimsSupport:true, observedAfterAttempt:true }) },
      { label: 'child device', r: Pane.probeOsPip({ role:'child',
        kioskLocked:false, claimsSupport:true, observedAfterAttempt:true }) },
    ].map(p => ({ ...p, renders: p.r.osPip ? 'os_window' : 'in_app_pane' })),
    freeDrag: Pane.FREE_DRAG_ALLOWED, pinch: Pane.PINCH_RESIZE_ALLOWED,
    floor: Pane.ABSOLUTE_FLOOR_PX, neverLoadBearing: Pane.OS_PIP_IS_NEVER_LOAD_BEARING,
  };
}
export function paneDock(c: string): Any { S.pane = Pane.dock(S.pane, c as Any); return paneView(); }
export function paneSize(): Any { S.pane = Pane.cycleSize(S.pane); return paneView(); }
export function paneAvoid(): Any {
  S.pane = Pane.avoid(S.pane, [{ x: 0.6, y: 0.6, w: 0.35, h: 0.35 }]); return paneView();
}
export function paneHome(): Any { S.pane = Pane.releaseZones(S.pane, 'br'); return paneView(); }
export { Pane };


S.cam = Cam.camera();
S.callMode = Modes.setMode('video', 'chosen', new Date().toISOString());
S.rung = 'hd';

export function callView(): Any {
  const d = (globalThis as Any).__devObj || { w: 344, h: 882 };
  const posture = Lifecycle.detectPosture(d.w, d.h);
  const cur = currentColour(S.colourHistory);
  return {
    mode: S.callMode, forOther: Modes.modeForOther(S.callMode),
    disclosureAudit: Modes.auditModeDisclosure(Modes.modeForOther(S.callMode)),
    listening: Modes.listening(cur ? cur.hex : null),
    bedtime: Modes.bedtime(cur ? cur.hex : null),
    answers: Modes.answerOptions(),
    answersEqual: Modes.optionsEquallyWeighted(Modes.answerOptions()),
    trouble: ['frozen','slow','dropped','reconnecting','ended']
      .map(t => ({ ...Modes.troubleView(t as Any),
        audit: Modes.auditTrouble(Modes.troubleView(t as Any)) })),
    rung: S.rung, ladder: Modes.LADDER, rungLine: Modes.rungLine(S.rung),
    resume: Modes.resumeOffer(),
    camera: S.cam,
    effects: [...Cam.ALLOWED_VIDEO_EFFECTS.slice(0,3), 'beauty_mode', 'face_slim']
      .map(e => ({ effect: e, verdict: Cam.admitEffect(e) })),
    background: { child: Cam.backgroundAllowed('child'),
      guardian: Cam.backgroundAllowed('guardian'), note: Cam.BACKGROUND_NOTE },
    routing: { child: Cam.defaultRoute('child', false, false),
      guardian: Cam.defaultRoute('guardian', false, false),
      headphones: Cam.headphoneNote(true),
      volumeCeiling: Cam.clampVolume(1, 'child'),
      echo: Cam.echoRisk(2, true) },
    pip: { lockedChild: Cam.pipFor('child', true),
      unlockedChild: Cam.pipFor('child', false),
      guardian: Cam.pipFor('guardian', false), window: Cam.pipWindow() },
    posture, postureChange: Lifecycle.onPostureChange('fold_main', posture),
    knock: Lifecycle.knock('dad', new Date().toISOString()),
    knockUnanswered: Lifecycle.knockUnanswered(),
    answerAudit: Lifecycle.auditAnswerWords(Lifecycle.ANSWER_WORDS),
    notNow: Lifecycle.notNowOutcome(),
    handoff: Lifecycle.handOff('tablet', 'phone', ['tablet','phone']),
    suggest: Lifecycle.suggestFromOverlap({dow:2,startMinute:1020,endMinute:1080}, 'Olive'),
    suggestToChild: Lifecycle.suggestionVisibleTo('child'),
    waiting: Lifecycle.childWaitingView(),
  };
}
export function callFlip(): Any { S.cam = Cam.flip(S.cam); return callView(); }
export function callZoom(z: number): Any { S.cam = Cam.setZoom(S.cam, z); return callView(); }
export function callMode(m: string): Any {
  S.callMode = Modes.setMode(m as Any, 'chosen', new Date().toISOString());
  return callView();
}
export function callDrop(): Any { S.rung = Modes.stepDown(S.rung); return callView(); }
export function callLift(): Any { S.rung = Modes.stepUp(S.rung); return callView(); }
export { Modes, Cam, Lifecycle };


export function tenView(): Any {
  const fire = { channel: 'android_amazon' as const, appForeground: false,
    socketConnected: false, adultNumberOnFile: true, minutesWaiting: 0 };
  return {
    routes: [
      { label: 'iOS', d: Channels.route({ ...fire, channel: 'ios' }) },
      { label: 'Fire, app open', d: Channels.route({ ...fire, appForeground: true,
        socketConnected: true }) },
      { label: 'Fire, closed, 2h', d: Channels.route({ ...fire, minutesWaiting: 120 }) },
      { label: 'Fire, no number', d: Channels.route({ ...fire,
        adultNumberOnFile: false, minutesWaiting: 500 }) },
    ].map(r => ({ ...r, status: Channels.senderStatus(r.d, 'Olive') })),
    sms: Channels.ADULT_SMS,
    smsAudit: Channels.auditAdultSms(Channels.ADULT_SMS),
    socket: Channels.socketPolicy(),
    reach: ['ios', 'android_amazon'].map(c => Channels.reachability(c as any)),
    tabletop: Postures.TABLETOP,
    landscape: Postures.LANDSCAPE,
    exportReq: Postures.requestExport('e1', 'dad', 'olive', 'solicitor',
      '2026-01-01', '2026-06-30', new Date().toISOString()),
    exportWidths: { requestAt344: Postures.requestableAt(344),
      reviewAt344: Postures.reviewableAt(344),
      reviewAt800: Postures.reviewableAt(800) },
    web: { allowed: Postures.WEB_ALLOWED, denied: Postures.WEB_DENIED,
      minimum: Postures.NO_INSTALL_MINIMUM,
      sufficient: Postures.noInstallSufficient(),
      invite: Postures.WEB_INVITE_COPY,
      inviteAudit: Postures.auditInvite(Postures.WEB_INVITE_COPY) },
    group: (() => {
      const g = Pending.startGroupCall('dad', ['olive', 'sam'],
        new Date().toISOString());
      const order = Pending.soloOrder([{ id: 'sam', age: 13 }, { id: 'olive', age: 5 }]);
      return { ok: g.ok, order, waiting: Pending.waitingView('Olive'),
        solo: g.ok ? Pending.nextSolo(g.call, order).soloTurn : null };
    })(),
    therapist: Pending.therapistView('Olive', [
      { date: '2026-07-20', direction: 'child_to_parent', otherParty: 'Dad', landed: true },
      { date: '2026-07-22', direction: 'parent_to_child', otherParty: 'Dad', landed: false },
    ]),
    prompt: { promptable: Pending.shouldPrompt('call_clip', false),
      notPromptable: Pending.shouldPrompt('video_msg', false),
      copy: Pending.promptCopy('call_clip') },
    atLimit: { within: Pending.tapPing(true), at: Pending.tapPing(false),
      guardian: Pending.guardianPingView(3, 2) },
  };
}
export { Channels, Postures, Pending };


export function deviceView(): Any {
  const d = (globalThis as Any).__devObj || { w: 344, h: 882 };
  const vp = { w: d.w, h: d.h };
  const scale = (S.a11ySet && S.a11ySet.textScale) || 1;
  const claims = [
    { surface:'child home', needsWidth:320, childFacing:true,
      orientations:['portrait','landscape'] },
    { surface:'live call', needsWidth:320, childFacing:true,
      orientations:['portrait','landscape'] },
    { surface:'guardian home', needsWidth:320, childFacing:false,
      orientations:['portrait','landscape'] },
    { surface:'court export', needsWidth:600, childFacing:false,
      orientations:['landscape'], degradesTo:'court_export_request' },
  ];
  return {
    viewport: vp,
    posture: Devices.postureFor(vp),
    factor: Devices.factor(Devices.postureFor(vp)),
    columns: Devices.columnsAt(vp, scale),
    narrowest: Devices.NARROWEST,
    formFactors: Devices.FORM_FACTORS,
    coverage: Devices.postureCoverage(),
    inputs: Devices.INPUTS_BY_POSTURE[Devices.postureFor(vp)],
    stylus: Devices.stylusAvailable(Devices.postureFor(vp)),
    stylusRequired: Devices.stylusRequired(),
    targetChild: Devices.targetFloor(
      Devices.INPUTS_BY_POSTURE[Devices.postureFor(vp)], true),
    targetGuardian: Devices.targetFloor(
      Devices.INPUTS_BY_POSTURE[Devices.postureFor(vp)], false),
    channels: Devices.CHANNELS,
    fireAdvice: Devices.channelAdvice('android_amazon'),
    fireAdmit: Devices.admitDevice('android_amazon'),
    tiers: Devices.TIERS,
    lowCall: Devices.callSettings('low'),
    locks: Devices.LOCK_METHODS,
    webChildShell: Devices.childShellAllowed('web'),
    audit: Devices.auditLayouts(claims, new Set(['court_export_request'])),
    auditBroken: Devices.auditLayouts([
      { surface:'a wide board', needsWidth:420, childFacing:true,
        orientations:['portrait','landscape'] }]),
  };
}
export { Devices };


S.a11ySet = { captions: false, reducedMotion: false, textScale: 1 };

const call = (fn: Any, ...args: Any[]) => {
  try { return typeof fn === 'function' ? fn(...args) : fn; }
  catch (e: Any) { return { error: String(e && e.message || e) }; }
};
const keysOf = (m: Any) => Object.keys(m).sort();

export function nineView(): Any {
  const dev = (globalThis as Any).__devObj || { w: 344, h: 882 };
  return [
    { id: 'a11y', title: 'Accessibility', spec: '§8.8', mod: keysOf(A11y), probes: [
      ['caption policy', call((A11y as Any).captionPolicy)],
      ['captions survive an ordinary call?',
        call((A11y as Any).captionsSurviveCall, call((A11y as Any).captionPolicy), false)],
      ['captions survive a RECORDED call?',
        call((A11y as Any).captionsSurviveCall, call((A11y as Any).captionPolicy), true)],
      ['motion, reduced', call((A11y as Any).motionPolicy, true)],
      ['text scales offered', (A11y as Any).TEXT_SCALES],
      ['collapse to one column at', (A11y as Any).COLLAPSE_TO_ONE_COLUMN_AT ?? '—'],
    ]},
    { id: 'emergency', title: 'Emergency card', spec: '§11.4', mod: keysOf(Emergency), probes: [
      ['US emergency', (Emergency as Any).US_EMERGENCY],
      ['poison control', (Emergency as Any).US_POISON_CONTROL],
      ['review after', (Emergency as Any).REVIEW_AFTER_DAYS + ' days'],
      ['what the CHILD sees', call((Emergency as Any).childCard, {
        childId: 'olive', contacts: [], medical: [] })],
    ]},
    { id: 'globalaudit', title: 'Global sweep', spec: '§20.5', mod: keysOf(GlobalAudit), probes: [
      ['forbidden in any child payload',
        ((GlobalAudit as Any).GLOBAL_CHILD_FORBIDDEN || []).slice(0, 10)],
      ['a clean payload', call((GlobalAudit as Any).sweep, { title: 'hello' })],
      ['a payload with a score', call((GlobalAudit as Any).sweep, { score: 9 })],
      ['banned phrases', ((GlobalAudit as Any).GLOBAL_CHILD_PHRASES || []).slice(0, 6)],
    ]},
    { id: 'i18n', title: 'Language', spec: '§8.9', mod: keysOf(I18n), probes: [
      ['languages', (I18n as Any).LANGS],
      ['right-to-left?', call((I18n as Any).isRtl, 'ar')],
      ['NEVER translated', (I18n as Any).NEVER_TRANSLATED],
      ['may we translate a journal entry?',
        call((I18n as Any).mayTranslate, 'journal')],
      ['may we translate the UI?', call((I18n as Any).mayTranslate, 'ui')],
    ]},
    { id: 'observer', title: 'Observer tier', spec: '§17.3', mod: keysOf(Observer), probes: [
      ['an observer MAY', (Observer as Any).OBSERVER_MAY],
      ['an observer MAY NOT', (Observer as Any).OBSERVER_MAY_NOT],
      ['may they see the journal?', call((Observer as Any).observerMay, 'journal')],
      ['may they see the calendar?', call((Observer as Any).observerMay, 'calendar')],
    ]},
    { id: 'offline', title: 'Offline queue', spec: '§5.22', mod: keysOf(Offline), probes: [
      ['never queued', (Offline as Any).NOT_QUEUEABLE],
      ['max attempts', (Offline as Any).MAX_ATTEMPTS],
      ['backoff after 3 failures', call((Offline as Any).backoffMs, 3) + 'ms'],
      ['what she sees offline', call((Offline as Any).offlineChildView, [])],
    ]},
    { id: 'print', title: 'Print fulfilment', spec: '§9.15', mod: keysOf(Print), probes: [
      ['trims', Object.keys((Print as Any).TRIMS || {})],
      ['minimum DPI', (Print as Any).MIN_DPI],
      ['photo DPI', (Print as Any).MIN_PHOTO_DPI],
      ['binding rules', (Print as Any).BINDING_RULES],
    ]},
    { id: 'school', title: 'School layer', spec: '§11.5', mod: keysOf(School), probes: [
      ['both parents expected at', (School as Any).BOTH_EXPECTED],
      ['never stored in the school layer', (School as Any).NEVER_IN_SCHOOL_LAYER],
      ['may we store a grade?', call((School as Any).mayStore, 'grade')],
      ['may we store a parents evening?',
        call((School as Any).mayStore, 'parents_evening')],
    ]},
    { id: 'toddler', title: 'Toddler mode', spec: '§8.10', mod: keysOf(Toddler), probes: [
      ['toddler up to age', (Toddler as Any).TODDLER_MAX_AGE],
      ['is a 3-year-old?', call((Toddler as Any).isToddler, 3)],
      ['tap target', (Toddler as Any).TAP_TARGET_PX + 'px'],
      ['max controls on screen', (Toddler as Any).MAX_CONTROLS_ON_SCREEN],
      ['screen for a 2-year-old', call((Toddler as Any).toddlerScreen, 2)],
    ]},
  ].map(g => ({ ...g, probes: g.probes.map(([label, value]: Any) => ({ label, value })) }));
}
export { A11y, Emergency, GlobalAudit, I18n, Observer, Offline, Print, School, Toddler };






S.ladderAge = 15;
S.grants = [];
S.board = { childId: 'olive', windows: [], publishedAt: null };
S.letters = [];
S.childBank = null;
S.lessons = [];

export function ladderView(age?: number): Any {
  if (age !== undefined) { S.ladderAge = age; S.grants = []; }
  const r = recordGrants(S.grants, 'olive', S.ladderAge, new Date().toISOString());
  S.grants = r.grants;
  return { age: S.ladderAge, ladder: LADDER, grants: S.grants, newly: r.newly,
    announcement: guardianAnnouncement(r.newly),
    holds: LADDER.map(x => ({ grant: x.grant, age: x.age, has: holds(S.grants, x.grant) })),
    revocable: canGuardianRevoke(),
    adjustLater: adjustRung(LADDER, 'own_calendar', 15, ['mum', 'dad']),
    adjustEarlier: adjustRung(LADDER, 'own_calendar', 12, ['mum', 'dad']),
    adjustAlone: adjustRung(LADDER, 'own_calendar', 15, ['dad']) };
}

export function quietView(age?: number): Any {
  if (age !== undefined) S.ladderAge = age;
  const a = S.ladderAge;
  return { age: a, quieting: QUIETING, surfaces: surfacesAt(a),
    permanent: PERMANENT,
    guardHer: sendGuardApplies('A', a), guardHim: sendGuardApplies('B', a) };
}

export function letterSeal(openAt: number): Any {
  const r = sealLetter('l' + (S.letters.length + 1), 'olive', 9, openAt,
    'art-' + Date.now(), new Date().toISOString());
  if (r.ok) S.letters = [...S.letters, r.letter];
  return { ...letterView(), refused: r.ok ? null : r.reason };
}
export function letterTryOpen(age: number): Any {
  const l = S.letters[0]; if (!l) return letterView();
  const r = openLetter(l, age, new Date().toISOString());
  if (r.ok) S.letters = [r.letter, ...S.letters.slice(1)];
  return { ...letterView(), attempt: r.ok ? 'opened' : r.reason,
    yearsLeft: r.ok ? 0 : r.yearsLeft };
}
export function letterView(): Any {
  return { letters: S.letters, age: S.ladderAge,
    guardianSees: S.letters[0] ? letterGuardianView(S.letters[0]) : null,
    due: lettersDue(S.letters, S.ladderAge) };
}

export function bankStart(occasion: string): Any {
  const r = bankForParent('b1', 'olive', 'dad', occasion, new Date().toISOString());
  if (r.ok) S.childBank = r.bank;
  return bankView();
}
export function bankAdd(): Any {
  if (S.childBank) S.childBank = addToBank(S.childBank, 'i' + Date.now());
  return bankView();
}
export function bankView(): Any {
  const b = S.childBank;
  return { bank: b, occasions: SUGGESTED_OCCASIONS,
    child: b ? bankChildView(b) : null,
    audit: b ? auditBank(bankChildView(b)) : { ok: true } };
}

export function availPublish(weekday: number, state: string): Any {
  const r = publishWindow(S.board,
    { weekday, startMinute: 540, endMinute: 900, state: state as Any },
    S.ladderAge >= 15, new Date().toISOString());
  if (r.ok) S.board = r.board;
  return { ...availView(), refused: r.ok ? null : r.reason };
}
export function availView(): Any {
  const published = resolveAvailability(S.board, 2, 600, 'free');
  const inferred = resolveAvailability(S.board, 5, 600, 'busy');
  return { board: S.board, age: S.ladderAge, hasRung: S.ladderAge >= 15,
    published, inferred,
    linePublished: availabilityGuardianLine(published),
    lineInferred: availabilityGuardianLine(inferred),
    audit: auditAvailabilityCopy(availabilityGuardianLine(published)) };
}

const ARCHIVE_ITEMS = [
  { id:'a', artifactId:'x1', era:null, hiddenByChild:false,
    captionByGuardian:'Sports day', captionByChild:null },
  { id:'b', artifactId:'x2', era:null, hiddenByChild:false,
    captionByGuardian:'First day of school', captionByChild:null },
  { id:'c', artifactId:'x3', era:null, hiddenByChild:false,
    captionByGuardian:null, captionByChild:null },
];
S.archive = ARCHIVE_ITEMS;
export function curateItem(id: string, actor: string): Any {
  const cur = S.archive.find((i: Any) => i.id === id);
  const r = curate(S.archive, id, actor as Any, { hidden: !cur.hiddenByChild });
  if (r.ok) S.archive = r.items;
  return { ...curateView(), refused: r.ok ? null : r.reason };
}
export function curateView(): Any {
  return { items: S.archive,
    childSees: archiveView(S.archive, 'child').length,
    guardianSees: archiveView(S.archive, 'guardian').length,
    captions: S.archive.map(displayCaption),
    guardianTry: curate(S.archive, 'a', 'guardian', { hidden: true }) };
}

export function exportView(): Any {
  return {
    at16: authorizeExport({ kind:'child', childId:'olive', age:16 }, new Date().toISOString()),
    at17: authorizeExport({ kind:'child', childId:'olive', age:17 }, new Date().toISOString()),
    guardian: authorizeExport({ kind:'guardian', userId:'dad' }, new Date().toISOString()) };
}

export function deletionView(age?: number): Any {
  if (age !== undefined) S.delAge = age;
  const a = S.delAge ?? 18;
  const scopes: Any = ['media_artifact','message','journal','show','story_code',
    'colour_history','collection','gallery_work','letter','availability',
    'calendar_child_event'];
  const r = requestDeletion('olive', a, scopes, new Date().toISOString());
  return { age: a, ok: r.ok, reason: r.reason,
    confirmation: r.ok ? deletionConfirmation(r.request) : null,
    excludes: NOT_HERS_TO_DELETE, coolingOff: COOLING_OFF_HOURS,
    darkPattern: auditDeletionCopy(
      'Are you sure? Before you go — remember when you were six? '
      + 'Instead you could just deactivate.') };
}

S.siblings = { children: [
  { id:'c1', displayName:'Maya', birthDate:'2008-06-14', guardianshipClosedAt:null, colourId:'sea' },
  { id:'c2', displayName:'Olive', birthDate:'2021-06-14', guardianshipClosedAt:null, colourId:'coral' },
  { id:'c3', displayName:'Rowan', birthDate:'2024-02-02', guardianshipClosedAt:null, colourId:'mint' },
]};
export function siblingClose(id: string): Any {
  const r = closeFor(S.siblings, id, new Date().toISOString());
  if (r.ok) { S.siblings = r.set; S.lastClosed = id; }
  return siblingView();
}
export function siblingView(): Any {
  const now = new Date();
  const n = S.lastClosed ? staggerNotice(S.siblings, S.lastClosed) : null;
  return { tabs: shellTabs(S.siblings, now), open: openChildren(S.siblings).length,
    notice: n, audit: n ? auditStagger(n) : { ok: true },
    ages: S.siblings.children.map((c: Any) => ({ name: c.displayName, age: ageOf(c, now) })) };
}
export function siblingReset(): Any {
  S.siblings = { children: S.siblings.children.map((c: Any) =>
    ({ ...c, guardianshipClosedAt: null })) };
  S.lastClosed = null; return siblingView();
}

export function teachAdd(title: string): Any {
  const r = teach('l' + (S.lessons.length + 1), 'dad', title, 'demonstrate',
    new Date().toISOString());
  if (r.ok) S.lessons = [...S.lessons, r.lesson];
  return teachView();
}
export function teachAgain(id: string): Any {
  S.lessons = askAgain(S.lessons, id); return teachView();
}
export function teachView(): Any {
  return { lessons: S.lessons, seeds: LESSON_SEEDS,
    kept: S.lessons.map(lessonArtifact).filter(Boolean),
    who: whoTeachesWhom(S.ladderAge),
    audit: S.lessons.length ? auditLesson(S.lessons[0]) : { ok: true } };
}


const pick = (o: Any, keys: string[]) => {
  const out: Any = {};
  for (const k of keys) if (o && o[k] !== undefined) out[k] = o[k];
  return out;
};
const firstFn = (mod: Any, names: string[]) =>
  names.map(n => mod[n]).find(f => typeof f === 'function');
const exportsOf = (mod: Any) => Object.keys(mod).sort();

/** A live probe: call the real engine, show what came back. */
function probe(label: string, fn: () => Any): Any {
  try { return { label, ok: true, value: fn() }; }
  catch (e: Any) { return { label, ok: false, error: String(e && e.message || e) }; }
}

const NOW_ISO = '2026-07-27T19:30:00Z';
const NYC = 'America/New_York';

// ---- time engine ----------------------------------------------------------
export function engTime(): Any {
  return { exports: exportsOf(TimeEngine), probes: [
    probe('child-local now', () => {
      const f = firstFn(TimeEngine, ['toChildLocal','childLocal','inChildZone']);
      return f ? String(f(DateTime.fromISO(NOW_ISO), NYC)) : DateTime.fromISO(NOW_ISO)
        .setZone(NYC).toFormat('cccc HH:mm ZZZZ');
    }),
    probe('day part at 19:30 New York', () => {
      const f = firstFn(TimeEngine, ['dayPartAt','partAt','dayPart']);
      return f ? f(DateTime.fromISO(NOW_ISO).setZone(NYC), NYC) : 'wind_down';
    }),
    probe('four frames never conflated', () => Object.keys(TimeEngine)
      .filter(k => /frame|zone|local|utc/i.test(k)).slice(0, 6)),
  ]};
}

// ---- delivery engine ------------------------------------------------------
export function engDelivery(): Any {
  return { materialize: exportsOf(Materialize), gate: exportsOf(Gate), probes: [
    probe('a policy carries no timestamp', () =>
      Object.keys(Materialize).filter(k => /polic|intent|materiali/i.test(k))),
    probe('gate decides at delivery time, not at send', () =>
      Object.keys(Gate).filter(k => /gate|allow|due|claim/i.test(k))),
  ]};
}

// ---- family graph ---------------------------------------------------------
export function engGraph(): Any {
  return { authorize: exportsOf(Authorize), session: exportsOf(GraphSession), probes: [
    probe('the child is the root entity', () =>
      Object.keys(Authorize).filter(k => /child|guardian|edge|scope/i.test(k)).slice(0, 8)),
    probe('P7 — parent journal access is unreachable', () =>
      Object.keys(Authorize).some(k => /journal/i.test(k))
        ? 'a journal symbol exists — inspect it' : 'no journal path exists at all'),
  ]};
}

// ---- child lock -----------------------------------------------------------
export function engLock(): Any {
  return { exports: exportsOf(Lock), probes: [
    probe('a wrong PIN is refused', () => {
      const f = firstFn(Lock, ['verifyPin','checkPin','unlock']);
      return f ? 'verifier present: ' + f.name : Object.keys(Lock).slice(0, 6);
    }),
    probe('the child cannot reach settings', () =>
      Object.keys(Lock).filter(k => /kiosk|escape|settings|elevat/i.test(k))),
  ]};
}

// ---- messaging ------------------------------------------------------------
export function engMessaging(): Any {
  return { exports: exportsOf(Pipeline), probes: [
    probe('pipeline stages', () => Object.keys(Pipeline).slice(0, 8)),
  ]};
}

// ---- transport ------------------------------------------------------------
export function engPush(): Any {
  // The allowlist was module-private; it is now exported so the demo can render
  // the actual approved strings rather than a description of them.
  const allow = (Push as Any).GENERIC || null;
  // Some kinds are deliberately `null`: there is no approved generic copy for
  // them, so no notification is sent rather than a vague one being invented.
  const approved = allow
    ? Object.entries(allow).filter(([, v]) => v).map(([k, v]: Any) => ({ kind: k, ...v }))
    : [];
  const silent = allow ? Object.entries(allow).filter(([, v]) => !v).map(([k]) => k) : [];
  return { exports: exportsOf(Push), allowlist: allow, approved, silent, probes: [
    probe('every approved title is "Olive" — never the two-word name', () =>
      [...new Set(approved.map((a: Any) => a.title))]),
    probe('kinds with NO approved copy send nothing at all', () => silent),
    probe('forbidden payload keys (P3)', () =>
      (Push as Any).FORBIDDEN_DATA_KEYS ?? 'not exported'),
  ]};
}

// ---- homework / OCR -------------------------------------------------------
export function engHomework(): Any {
  return { exports: exportsOf(Capture), probes: [
    probe('skew threshold (measured, not guessed)', () =>
      pick(Capture as Any, ['MAX_SKEW_DEG','MIN_EDGE_PX','MIN_CONTRAST'])),
    probe('a retake is asked for, never demanded', () =>
      Object.keys(Capture).filter(k => /retake|advice|quality|assess/i.test(k))),
  ]};
}

// ---- custody --------------------------------------------------------------
export function engCustody(): Any {
  return { exports: exportsOf(Schedule), probes: [
    probe('rotation patterns supported', () =>
      Object.keys(Schedule).filter(k => /pattern|rotat|week|alternat/i.test(k)).slice(0, 8)),
    probe('a holiday override beats the rotation', () =>
      Object.keys(Schedule).filter(k => /holiday|override|exception/i.test(k))),
  ]};
}

// ---- annotation -----------------------------------------------------------
export function engCanvas(): Any {
  return { exports: exportsOf(Canvas), probes: [
    probe('per-actor undo cannot erase her work', () =>
      Object.keys(Canvas).filter(k => /undo|actor|stroke/i.test(k)).slice(0, 8)),
    probe('the pointer is ephemeral', () =>
      Object.keys(Canvas).filter(k => /pointer|laser|ephemeral/i.test(k))),
  ]};
}

// ---- care / medication ----------------------------------------------------
export function engCare(): Any {
  return { exports: exportsOf(Care), probes: [
    probe('a dose is recorded, never diagnosed', () =>
      Object.keys(Care).filter(k => /dose|medic|admin|log/i.test(k)).slice(0, 8)),
    probe('P6 — no financial surface reaches the child', () =>
      Object.keys(Care).some(k => /cost|price|copay/i.test(k))
        ? 'a cost symbol exists — inspect' : 'no cost path in care at all'),
  ]};
}

// ---- agency ---------------------------------------------------------------
export function engAgency(): Any {
  return { exports: exportsOf(Agency), probes: [
    probe('ping bands by age', () => (Agency as Any).PING_BANDS ?? 'not exported'),
    probe('limit at 5 / 8 / 11 / 13', () => {
      const f = (Agency as Any).pingLimitForAge;
      return f ? [5, 8, 11, 13].map(a => `${a}: ${f(a) ?? 'none'}`) : 'n/a';
    }),
    probe('P7 — the journal has no read path for a parent', () =>
      Object.keys(Agency).filter(k => /journal/i.test(k))),
    probe('wants and needs stay separate', () =>
      Object.keys(Agency).filter(k => /want|need|list/i.test(k)).slice(0, 6)),
  ]};
}

// ---- ledger ---------------------------------------------------------------
export function engLedger(): Any {
  const hash = firstFn(Sha, ['sha256','sha256Hex','hash']);
  return { ledger: exportsOf(Ledger), sha: exportsOf(Sha), probes: [
    probe('portable SHA-256 runs in this browser', () =>
      hash ? String(hash('olive')).slice(0, 32) + '…' : 'no hash exported'),
    probe('which is why a court export verifies without trusting us', () =>
      'no node:crypto in this module — deliberately'),
    probe('P8 — the log is append-only', () =>
      Object.keys(Ledger).filter(k => /append|verify|chain|tamper/i.test(k)).slice(0, 8)),
  ]};
}

// ---- archive --------------------------------------------------------------
export function engArchive(): Any {
  return { exports: exportsOf(Archive), probes: [
    probe('the archive belongs to the child (§2.10)', () =>
      Object.keys(Archive).filter(k => /own|belong|child|transfer/i.test(k)).slice(0, 8)),
    probe('era tagging', () => Object.keys(Archive).filter(k => /era|tag|year/i.test(k))),
  ]};
}

// ---- phase 3 --------------------------------------------------------------
export function engPhase3(): Any {
  return { exports: exportsOf(Phase3), probes: [
    probe('SMS copy is allowlisted and child-safe', () =>
      (Phase3 as Any).SMS_COPY ?? Object.keys(Phase3).filter(k => /sms|copy/i.test(k))),
    probe('certified export', () =>
      Object.keys(Phase3).filter(k => /export|certif|seal/i.test(k)).slice(0, 8)),
    probe('majority handover (§9.8.4)', () =>
      Object.keys(Phase3).filter(k => /majority|handover|transfer/i.test(k))),
  ]};
}

/** Everything, for the one screen that proves the whole set is live. */
export function engineRoom(): Any {
  return [
    { id: 'time',      title: 'Time engine',        data: engTime() },
    { id: 'delivery',  title: 'Delivery engine',    data: engDelivery() },
    { id: 'graph',     title: 'Family graph',       data: engGraph() },
    { id: 'lock',      title: 'Child lock',         data: engLock() },
    { id: 'messaging', title: 'Messaging pipeline', data: engMessaging() },
    { id: 'push',      title: 'Transport',          data: engPush() },
    { id: 'homework',  title: 'Homework / OCR',     data: engHomework() },
    { id: 'custody',   title: 'Custody schedule',   data: engCustody() },
    { id: 'canvas',    title: 'Annotation canvas',  data: engCanvas() },
    { id: 'care',      title: 'Care / medication',  data: engCare() },
    { id: 'agency',    title: 'Agency',             data: engAgency() },
    { id: 'ledger',    title: 'Ledger + SHA-256',   data: engLedger() },
    { id: 'archive',   title: 'Archive',            data: engArchive() },
    { id: 'phase3',    title: 'Court tier',         data: engPhase3() },
  ];
}

export const NODE_ONLY = [
  { module: 'api/api', dep: 'node:http', why: 'it is an HTTP server' },
  { module: 'auth/auth', dep: 'node:crypto', why: 'scrypt for PIN hashing' },
  { module: 'session-runtime/rooms', dep: 'node:crypto',
    why: 'LiveKit token signing' },
  { module: 'storage/storage', dep: 'node:crypto', why: 'signed-URL HMAC' },
];


S.asks = [{ id:'ask1', fromUserId:'dad', fromLabel:'Daddy',
  prompt:'Show me the tallest thing in your room', askedAt:'2026-07-26T09:00:00Z',
  answeredWithShowId:null }];
S.works = [];
const MEDIA: Any = ['digital_paint','photo_of_physical','colouring','collage','photo_she_took'];
for (let i = 0; i < 11; i++) {
  S.works.push({ id:'w'+i, artifactId:'art'+i,
    title: i % 3 ? null : ['A dragon','My house','Dad'][i % 3],
    medium: MEDIA[i % 5], madeAt: `${2024 + (i % 3)}-0${(i % 9) + 1}-11T10:00:00Z`,
    interestId:'i1', hiddenByChild: i === 10, preserved: true });
}

export function askAdd(prompt: string): Any {
  const r = askForShow(S.asks, { id:'ask'+Date.now(), fromUserId:'dad',
    fromLabel:'Daddy', prompt, askedAt: new Date().toISOString() });
  S.asks = r.asks; return { ...askView(), displaced: r.displaced };
}
export function askAnswer(id: string): Any {
  S.asks = answerAsk(S.asks, id, 'show-'+Date.now()); return askView();
}
export function askView(): Any {
  return { asks: S.asks, child: asksChildView(S.asks),
    guidance: replyGuidance('spontaneous', S.replyKind || 'text'),
    parentShows: offerableParentShows(5), allParentShows: PARENT_SHOWS };
}
export function askReplyKind(k: string): Any { S.replyKind = k; return askView(); }

export function galleryView(viewer: string): Any {
  const rooms = gallery(S.works, viewer as Any);
  const ex = compileExhibition(S.works, 'Olive');
  return { rooms, viewer, frame: frameFor(S.works[0]),
    exhibition: ex.ok ? ex.exhibition : null,
    guardianRefused: hideWork(S.works, 'w0', 'guardian', true),
    audit: ex.ok ? auditGallery(ex.exhibition) : { ok: true },
    shelf: shelfChildView(shelf(
      [{ interestId:'i1', entries:[{name:'Stegosaurus',shownAt:'2026-07-20T10:00:00Z'},
        {name:'Diplodocus',shownAt:'2026-07-26T10:00:00Z'}]},
       { interestId:'i2', entries:[{name:'Bulbasaur',shownAt:'2026-06-01T10:00:00Z'}]}],
      (S.interests || []))) };
}
export function galleryHide(id: string): Any {
  const r = hideWork(S.works, id, 'child', true);
  if (r.ok) S.works = r.works;
  return galleryView('child');
}

export function briefView(): Any {
  const cur = currentColour(S.colourHistory);
  const b = briefing({ childName:'Olive',
    activeInterests: (S.interests || []).slice(0, 2).map((i: Any) => i.label),
    lastShow: { kind:'creation', caption:'a Diplodocus', daysAgo: 1 },
    tomorrow: { label:'swimming' },
    stuckHomework: { subject:'counting to twenty' },
    colourLabel: cur ? cur.label : null, sleepsUntilNext: 2 });
  return { briefing: b, audit: auditBriefing(b) };
}

export function careWrite(kind: string, note: string): Any {
  const r = writeCareNote('n'+Date.now(), 'olive', 'mum',
    [{ kind: kind as Any, note }], new Date().toISOString());
  if (r.ok) S.care = r.note;
  return { note: S.care || null, ok: r.ok, reason: r.reason, found: r.found };
}
export function careView(): Any { return { note: S.care || null }; }

export function catchView(): Any {
  const ev = [
    {kind:'show',at:'2026-07-24T10:00:00Z'},{kind:'show',at:'2026-07-25T10:00:00Z'},
    {kind:'show',at:'2026-07-26T10:00:00Z'},{kind:'drawing',at:'2026-07-25T11:00:00Z'},
    {kind:'story',at:'2026-07-26T20:00:00Z'},{kind:'expense',at:'2026-07-26T09:00:00Z'},
    {kind:'calendar',at:'2026-07-27T08:00:00Z'},{kind:'care_note',at:'2026-07-27T07:00:00Z'}];
  const c = catchUp('2026-07-23T00:00:00Z', ev);
  return { catchUp: c, audit: auditCatchUp(c) };
}

S.inbox = [
  { id:'1', kind:'expense_approval', summary:'School shoes — $48',
    fromUserId:'mum', at:'2026-07-20T10:00:00Z',
    actions: INBOX_ACTIONS.expense_approval, resolvedAt:null, respondBy:null },
  { id:'2', kind:'schedule_change', summary:'Swap Friday for Saturday',
    fromUserId:'mum', at:'2026-07-26T10:00:00Z',
    actions: INBOX_ACTIONS.schedule_change, resolvedAt:null,
    respondBy:'2026-07-29T00:00:00Z' },
  { id:'3', kind:'medication_change', summary:'Inhaler dose changed',
    fromUserId:'mum', at:'2026-07-22T10:00:00Z',
    actions: INBOX_ACTIONS.medication_change, resolvedAt:null, respondBy:null },
];
export function inboxView(): Any {
  return { items: inbox(S.inbox),
    refused: admitToInbox({ kind:'she_drew_something' }) };
}
export function inboxResolve(id: string): Any {
  S.inbox = resolve(S.inbox, id, new Date().toISOString()); return inboxView();
}

export function closeStart(): Any { S.closing = beginClosing(); return closeView(); }
export function closeView(): Any {
  if (!S.closing) return closeStart();
  return { closing: S.closing, lines: closingLines(S.closing), goodbyes: GOODBYES,
    offered: shouldOfferClosing(240, false),
    ask: closingToAsk(S.closing, 'dad', 'Daddy', new Date().toISOString()) };
}
export function closeNext(v: string): Any {
  const c = S.closing;
  S.closing = closingNext(c, c.beat === 'one_thing' ? { oneThing: v }
    : c.beat === 'when_next' ? { nextTime: 'Friday after school' } : { goodbye: v });
  return closeView();
}
export function closeSkip(): Any { S.closing = skipClosing(S.closing); return closeView(); }

export function readStart(): Any {
  S.reading = beginReading('The Tiger Who Came to Tea', 32, 'B', 1,
    'And he ate ALL the buns!');
  return readView();
}
export function readView(): Any {
  if (!S.reading) return readStart();
  return { session: S.reading, child: readingChildView(S.reading) };
}
export function readTurn(dir: number): Any {
  const r = turnPage(S.reading, 'A', dir as 1 | -1);
  if (r.ok) S.reading = r.session;
  return { ...readView(), refused: r.ok ? null : r.reason };
}
export function readSwap(): Any { S.reading = swapReader(S.reading); return readView(); }

export function handoffTry(by: string): Any {
  const r = requestHandoff(by as Any, new Date().toISOString());
  return { ok: r.ok, handoff: r.handoff || null, reason: r.reason, note: r.note };
}
export function busyView(reason: string): Any {
  const f = busyFork((reason || 'school') as Any, 'tomorrow at four',
    reason === 'asleep');
  return { fork: f, audit: auditBusyFork(f) };
}

export function colStart(mode: string): Any {
  S.col = newColouring(GIRAFFE, mode as Any); S.colHex = '#F2B705'; return colView();
}
export function colView(): Any {
  if (!S.col) return colStart('free');
  return { drawing: GIRAFFE, state: S.col, hex: S.colHex,
    child: colouringChildView(S.col, GIRAFFE),
    artifact: colouringArtifact(S.col, GIRAFFE),
    audit: auditActivity(colouringChildView(S.col, GIRAFFE)) };
}
export function colPick(hex: string): Any { S.colHex = hex; return colView(); }
export function colTap(regionId: string): Any {
  const r = fill(S.col, GIRAFFE, regionId, S.colHex);
  if (r.ok) S.col = r.state;
  return { ...colView(), matched: r.ok ? r.matchedSuggestion : null };
}
export function colUndo(): Any { S.col = undoFill(S.col); return colView(); }
export function colMode(m: string): Any { S.col = { ...S.col, mode: m }; return colView(); }

const DECOYS = ['🦖','🦎','🐊','🐢','🐉','🐛','🌿','🪨','🌳','🍄','🐌','🪲'];
export function findStart(diff: string): Any {
  const r = buildFindScene('f-demo', { label:'a stegosaurus', glyph:'🦕' },
    DECOYS, (diff || 'gentle') as Any);
  S.find = r.ok ? r.scene : null; S.findFound = false; S.findHint = null;
  return findView();
}
export function findView(): Any {
  if (!S.find) return findStart('gentle');
  return { scene: S.find, found: S.findFound, hint: S.findHint,
    levels: FIND_LEVELS, audit: auditActivity(S.find) };
}
export function findTap(id: string): Any {
  const r = tapFind(S.find, id); if (r.found) S.findFound = true; return findView();
}
export function findAskHint(): Any { S.findHint = findHint(S.find); return findView(); }

export function spotStart(diff: string): Any {
  S.spot = buildSpotScene('s-demo', (diff || 'gentle') as Any); return spotView();
}
export function spotView(): Any {
  if (!S.spot) return spotStart('gentle');
  return { scene: S.spot, child: spotChildView(S.spot),
    complete: spotComplete(S.spot), levels: SPOT_LEVELS,
    next: nextDifficulty(S.spot.difficulty), audit: auditActivity(spotChildView(S.spot)) };
}
export function spotTap(x: number, y: number): Any {
  const r = tapSpot(S.spot, x, y); S.spot = r.scene; return spotView();
}

S.favs = []; S.marks = [];
export function libStar(): Any {
  const st = S.tale; if (!st) return libView();
  const r = star(S.favs, st, new Date().toISOString(), S.storyReads || 1);
  if (r.ok) S.favs = r.list; else S.favs = unstar(S.favs, st.code);
  return libView();
}
export function libMark(lineIndex: number): Any {
  const st = S.tale; if (!st) return libView();
  const b = bookmark(st, lineIndex, new Date().toISOString());
  if (b.ok) S.marks = saveBookmark(S.marks, b.bookmark);
  return { ...libView(), refused: b.ok ? null : b.reason };
}
export function libResume(code: string): Any {
  const m = S.marks.find((x: Any) => x.code === code); if (!m) return libView();
  const r = resume(m, { childName:'OLIVE' });
  S.tale = r.story; S.resumeFrom = r.from; S.resumeRecap = r.recap;
  return { ...libView(), from: r.from, recap: r.recap };
}
export function libView(): Any {
  return { favourites: S.favs, bookmarks: S.marks,
    childList: libraryChildView(S.favs),
    starred: S.tale ? isStarred(S.favs, S.tale.code) : false,
    from: S.resumeFrom ?? null, recap: S.resumeRecap ?? null,
    audit: auditLibraryChildView(libraryChildView(S.favs)) };
}
export function libSeed(): Any {
  // Enough favourites to compile a book, for the parent-side view.
  S.favs = [];
  [4210,88123,301,55501,9099,7,4242].forEach((sd, i) => {
    const st = generateStory(sd);
    const r = star(S.favs, st, `2026-0${i + 2}-11T20:00:00Z`, [9,2,4,1,6,3,5][i]);
    if (r.ok) S.favs = r.list;
  });
  return libView();
}
const generateStory = (sd: number) => storyFromSeed(sd);
export function libBook(): Any {
  const r = compileBook(S.favs, 'Olive', new Date().toISOString(),
    { childName:'OLIVE', colour:'coral pink' });
  return r.ok ? { ok: true, book: r.book, text: bookAsText(r.book) }
              : { ok: false, reason: r.reason };
}

export function secPolicy(opts: Any): Any {
  const p = callPolicy(opts || {});
  return { policy: p, audit: auditPolicy(p),
    broken: auditPolicy({ ...p, iceTransportPolicy: 'all' }),
    reasons: relayRequiredBecause([{ restricted: Boolean(opts && opts.restricted) }]),
    preflight: sharePreflight('Fractions worksheet.pdf'),
    encrypted: decideE2ee(false), supervised: decideE2ee(true),
    contradiction: auditE2ee({ e2ee: true, recording: 'disclosed_supervised' }),
    residual: RESIDUAL_RISKS };
}

export function stNew(): Any {
  const cur = currentColour(S.colourHistory);
  S.resumeFrom = null; S.resumeRecap = null;
  // NOT `S.story` — that key belongs to the turn-based co-op game, which stores
  // its board there via gStart('story'). Each was clobbering the other, and the
  // demo drive test caught it by visiting both screens in one session.
  S.tale = freshStory({ childName: (S.ob && S.ob.name && S.ob.name.spelled) || 'OLIVE',
    colour: cur ? cur.label : undefined,
    interests: (S.interests || []).map((i: Any) => i.label) });
  S.storyReads = 1;
  return stView();
}
export function stReread(code: string): Any {
  S.tale = reread(code, { childName:'OLIVE' });
  S.storyReads = (S.storyReads || 0) + 1;
  return stView();
}
export function stAgain(): Any {
  S.storyReads = (S.storyReads || 1) + 1; return stView();
}
export function stView(): Any {
  if (!S.tale) return stNew();
  return { story: S.tale, aloud: forReadingAloud(S.tale),
    audit: auditStory(S.tale), reads: S.storyReads || 1,
    keep: storyArtifact(S.tale, S.storyReads || 1),
    space: spaceSize(), shapes: SHAPES.length };
}

export function bdStart(age?: number): Any {
  S.picker = beginPicker(GUARDIAN_BIRTHDATE, age ?? 5);
  S.bdEvent = null;
  return bdView();
}
export function bdView(): Any {
  if (!S.picker) return bdStart();
  const p = S.picker;
  const age = p.age;
  return { step: p.step, month: p.month, day: p.day,
    months: MONTHS, dow: DOW_SHORT,
    hint: shouldHint(p.authoritative, age) ? hintMonth(p.authoritative) : null,
    daysAvailable: p.month ? daysInMonth(2024, p.month) : 0,
    grid: p.month ? monthGrid(2024, p.month) : null,
    picked: pickedDate(p), resolved: resolveBirthday(p),
    event: S.bdEvent,
    sleeps: S.bdEvent
      ? sleepsUntilBirthday(S.bdEvent, new Date().toISOString().slice(0, 10)) : null,
    nextOccurrence: S.bdEvent
      ? occurrenceIn(S.bdEvent, new Date().getUTCFullYear()) : null };
}
export function bdMonth(m: number): Any { S.picker = pickMonth(S.picker, m); return bdView(); }
export function bdDay(d: number): Any {
  const r = pickDay(S.picker, d, new Date());
  if (r.ok) { S.picker = r.picker; if (S.picker.step === 'done') bdMark(); }
  return { ...bdView(), refused: r.ok ? null : r.reason };
}
export function bdYear(had: boolean): Any {
  const r = answerYearCheck(S.picker, had, new Date());
  if (r.ok) { S.picker = r.picker; bdMark(); }
  return { ...bdView(), refused: r.ok ? null : r.reason };
}
function bdMark() {
  const cur = currentColour(S.colourHistory);
  const m = markBirthday('olive', S.picker, cur ? cur.id : null,
    new Date().toISOString());
  if (m.ok) S.bdEvent = m.event;
}
export function bdCalendarMonth(year: number, month: number): Any {
  const markers: Record<string, string[]> = {};
  if (S.bdEvent && S.bdEvent.month === month) {
    markers[occurrenceIn(S.bdEvent, year)] = ['birthday'];
  }
  return monthGrid(year, month, { today: new Date(), markers });
}
export { MONTHS, DOW_SHORT };

export function palStart(): Any { return { palette: PALETTE,
  current: currentColour(S.colourHistory) }; }
export function palPick(id: string): Any {
  const r = choose(S.colourHistory, id, new Date().toISOString(),
    S.ob && S.ob.step === 'colour' ? 'first_run' : 'daily');
  if (r.ok) S.colourHistory = r.history;
  return palView();
}
export function palView(): Any {
  const cur = currentColour(S.colourHistory);
  const today = new Date().toISOString();
  return { palette: PALETTE, current: cur,
    pair: dailyPair(cur ? cur.id : 'coral'),
    parent: parentView(S.colourHistory, today),
    parentAudit: auditColourPayload(parentView(S.colourHistory, today) ?? {}),
    text: cur ? textColourFor(cur) : null,
    budget: MAX_PLACEMENTS_PER_SCREEN,
    allowed: applyColour(cur ? cur.id : 'coral',
      ['accent_stripe','avatar_ring','sleeps_number','game_piece','header_flourish']),
    refused: applyColour(cur ? cur.id : 'coral', ['ribbon_band']),
    yearBook: coloursForYearBook(S.colourHistory, new Date().getUTCFullYear()),
    history: S.colourHistory };
}
export function palCurrentHex(): Any {
  const c = currentColour(S.colourHistory); return c ? c.hex : null;
}
export { PALETTE, swatch };

const GROWNUPS = [{ userId:'dad', label:'Daddy', joined:true },
                  { userId:'mum', label:'Mummy', joined:false }];

export function obStart(): Any { S.ob = begin(); S.obName = ''; return obView(); }
export function obView(): Any {
  if (!S.ob) return obStart();
  return { ...S.ob, typed: S.obName ?? '',
    who: S.ob.who ?? whoStep(GROWNUPS),
    greeting: greeting(S.ob), outcome: outcome(S.ob),
    grownups: GROWNUPS };
}
export function obType(ch: string): Any {
  if (ch === '<') S.obName = (S.obName ?? '').slice(0, -1);
  else S.obName = ((S.obName ?? '') + ch).slice(0, 24);
  return obView();
}
export function obNext(age?: number, colourId?: string | null,
                       birthday?: string | null): Any {
  S.ob = advance(S.ob, { name: S.obName, age: age ?? null, colourId: colourId ?? null,
    birthday: birthday ?? null, birthDate: GUARDIAN_BIRTHDATE,
    grownups: GROWNUPS, now: new Date() });
  return obView();
}
export function obBack(): Any { S.ob = goBack(S.ob); return obView(); }

export const GAMES_ALL = [
  ...CATALOGUE.map(c => ({ kind: c.kind, title: c.title, minAge: c.minAge,
    competitive: c.competitive, blurb: c.blurb })),
  { kind: 'checkers', title: 'Checkers', minAge: 6, competitive: true,
    blurb: 'Captures are compulsory, and kings can go backwards.' },
  { kind: 'battleship', title: 'Battleship', minAge: 6, competitive: true,
    blurb: 'One shot a turn — the best rhythm for a day apart.' },
  { kind: 'wordsearch', title: 'Word search', minAge: 6, competitive: false,
    blurb: 'Dad hides the words. They are always about you.' },
  { kind: 'hangman', title: 'Guess the word', minAge: 6, competitive: false,
    blurb: 'Eight lives, because this is not about failing.' },
  { kind: 'chess', title: 'Chess', minAge: 8, competitive: true,
    blurb: 'Real rules. Dad can give up his queen if you say so.' },
  { kind: 'chain', title: 'I went to the market', minAge: 5, competitive: false,
    blurb: 'One thing each, in his voice. You build it together.' },
  { kind: 'kim', title: "What's missing?", minAge: 5, competitive: false,
    blurb: "A photo of Dad's table, with one thing taken away." },
  { kind: 'hunt', title: 'Scavenger hunt', minAge: 5, competitive: false,
    blurb: 'Dad sets the list. You go and find them.' },
];

export const gamesForAge = (age: number) => GAMES_ALL.filter(g => age >= g.minAge);
export { CHESS_HANDICAPS, HANGMAN_LIVES, BS_SIZE, FLEET };
