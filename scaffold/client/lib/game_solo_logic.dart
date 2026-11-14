// OLIVE BRANCH — solo and same-screen game rules (wave 8, child games parity). No longer UNVERIFIED —
// verified by CI (test/game_solo_logic_test.dart). Pure Dart, no Flutter import.
//
// What lives here, all offline, all in the child's own game doors:
//   - tic-tac-toe CPU levels: Easy (random), Normal (win, block, centre, then random) and Hard (full
//     minimax, so it never loses) — the prototype's three levels (mod-child.js k.g.ttt). The shipped bot was a
//     single random level; that stays as Easy.
//   - Memory pairs: a pair count that grows with age (3 for the youngest, then 4 / 6 / 8 by band) and the
//     flip / match / flip-back rules. Nothing here counts attempts: there is no move counter, no timer, no score
//     (MASTERFILE §2.1 P1-P3).
//   - Guess the word: a built-in word bank per band with a hint, so a child can play without a grown-up typing
//     the word in. A grown-up's own typed word (HangmanSetupScreen) is untouched.
//   - War against the game: both piles are held here (the two-device engine in game_war.dart only ever knows its
//     own pile), with the same tie-takes-all rule and the same round cap.
//
// Ages follow the standing decision: early ages are kept and more unlocks as she grows. Nothing here adds a
// minimum age; every table below only chooses HOW MUCH a given age sees.
import 'dart:math';
import 'game_logic.dart' show Side;
import 'game_tictactoe.dart' show TttState, tttLegalMoves, tttPlay, TttOutcome;
import 'war_deck.dart';

// ========================================================= tic-tac-toe CPU ==

enum TttLevel { easy, normal, hard }

const List<List<int>> _lines = <List<int>>[
  <int>[0, 1, 2], <int>[3, 4, 5], <int>[6, 7, 8],
  <int>[0, 3, 6], <int>[1, 4, 7], <int>[2, 5, 8],
  <int>[0, 4, 8], <int>[2, 4, 6],
];

/// The square the game (Side.b) plays at [level]. Always one of [tttLegalMoves] for Side.b, so a handicap such as
/// no_centre is honoured by construction. Returns null only when the board is full.
int? tttCpuPick(TttState s, TttLevel level, Random rng) {
  final List<int> legal = tttLegalMoves(s, Side.b);
  if (legal.isEmpty) return null;
  switch (level) {
    case TttLevel.easy:
      return legal[rng.nextInt(legal.length)];
    case TttLevel.normal:
      final int? win = _completing(s.board, Side.b, legal);
      if (win != null) return win;
      final int? block = _completing(s.board, Side.a, legal);
      if (block != null) return block;
      if (legal.contains(4)) return 4;
      return legal[rng.nextInt(legal.length)];
    case TttLevel.hard:
      return _minimaxPick(s, legal, rng);
  }
}

/// A legal square that finishes a line of [side]'s own marks, or null.
int? _completing(List<Side?> b, Side side, List<int> legal) {
  for (final int i in legal) {
    for (final List<int> line in _lines) {
      if (!line.contains(i)) continue;
      if (line.where((int j) => j != i).every((int j) => b[j] == side)) return i;
    }
  }
  return null;
}

int _minimaxPick(TttState s, List<int> legal, Random rng) {
  int best = -100;
  final List<int> bestMoves = <int>[];
  for (final int i in legal) {
    final TttState next = tttPlay(s, Side.b, i).state!;
    final int v = -_negamax(next, Side.a, 1);
    if (v > best) {
      best = v;
      bestMoves
        ..clear()
        ..add(i);
    } else if (v == best) {
      bestMoves.add(i);
    }
  }
  return bestMoves[rng.nextInt(bestMoves.length)];
}

/// Value of [s] for the side to move: a win scores higher the sooner it comes (so Hard takes the quickest win
/// and the slowest loss), a draw is 0.
int _negamax(TttState s, Side toMove, int ply) {
  if (s.outcome != null) {
    if (s.outcome == TttOutcome.draw) return 0;
    final Side winner = s.outcome == TttOutcome.childWin ? Side.a : Side.b;
    return winner == toMove ? 10 - ply : ply - 10;
  }
  int best = -100;
  for (final int i in tttLegalMoves(s, toMove)) {
    final TttState next = tttPlay(s, toMove, i).state!;
    final int v = -_negamax(next, toMove == Side.a ? Side.b : Side.a, ply + 1);
    if (v > best) best = v;
  }
  // No legal move for the side to move (a handicap can do this): call it level rather than guess.
  return best == -100 ? 0 : best;
}

// ================================================================= memory ===

/// How many pairs a child of [age] sees. 3 for the youngest (3-4), then the prototype's 4 / 6 / 8 by band.
int memoryPairsForAge(int age) => age < 5 ? 3 : age < 8 ? 4 : age < 13 ? 6 : 8;

/// Eight symbols, each drawn with its own shape AND its own colour in the screen, so a pair is never told apart by
/// colour alone.
const List<String> memorySymbols = <String>['star', 'heart', 'moon', 'sun', 'leaf', 'fish', 'paw', 'flower'];

class MemoryState {
  const MemoryState({required this.cards, required this.matched, required this.faceUp});

  /// A symbol index (into [memorySymbols]) per position.
  final List<int> cards;
  final Set<int> matched;

  /// Positions turned over right now and not yet resolved: 0, 1 or 2.
  final List<int> faceUp;

  bool get complete => matched.length == cards.length;
  bool get needsResolve => faceUp.length == 2;
}

MemoryState newMemory(int pairs, Random rng) {
  final int n = pairs.clamp(1, memorySymbols.length);
  final List<int> deck = <int>[for (int i = 0; i < n; i++) ...<int>[i, i]]..shuffle(rng);
  return MemoryState(cards: deck, matched: <int>{}, faceUp: const <int>[]);
}

/// Turn card [i] over. Ignored when it is already up or matched, out of range, or two are already waiting to be
/// resolved (the screen resolves them after a pause).
MemoryState memoryFlip(MemoryState s, int i) {
  if (i < 0 || i >= s.cards.length) return s;
  if (s.matched.contains(i) || s.faceUp.contains(i) || s.faceUp.length >= 2) return s;
  return MemoryState(cards: s.cards, matched: s.matched, faceUp: <int>[...s.faceUp, i]);
}

/// Resolve the two face-up cards: a match stays together, a miss turns back over. Does nothing with fewer than two.
MemoryState memoryResolve(MemoryState s) {
  if (!s.needsResolve) return s;
  final bool match = s.cards[s.faceUp[0]] == s.cards[s.faceUp[1]];
  return MemoryState(
    cards: s.cards,
    matched: match ? <int>{...s.matched, ...s.faceUp} : s.matched,
    faceUp: const <int>[],
  );
}

// ============================================================== guess a word ==

class WordEntry {
  const WordEntry(this.word, this.hint);
  final String word;
  final String hint;
}

/// Per-band word banks (prototype mod-child.js k.g.word). Short, concrete, gentle words only. The hint is always
/// shown, because a hint is help, not a penalty.
const List<WordEntry> wordsYoung = <WordEntry>[
  WordEntry('CAT', 'It says meow'),
  WordEntry('DOG', 'It wags its tail'),
  WordEntry('SUN', 'It shines in the day'),
  WordEntry('MOON', 'You see it at night'),
  WordEntry('FISH', 'It swims'),
  WordEntry('TREE', 'Birds sit in it'),
  WordEntry('BED', 'Where you sleep'),
  WordEntry('CAKE', 'A birthday treat'),
];

const List<WordEntry> wordsMiddle = <WordEntry>[
  WordEntry('GARDEN', 'Flowers grow here'),
  WordEntry('PLANET', 'Earth is one'),
  WordEntry('BRIDGE', 'It goes over water'),
  WordEntry('ISLAND', 'Land with water all round'),
  WordEntry('RAINBOW', 'Colours after the rain'),
  WordEntry('PUZZLE', 'Pieces that fit together'),
  WordEntry('DRAGON', 'A story creature that breathes fire'),
  WordEntry('SANDCASTLE', 'You build it at the beach'),
];

const List<WordEntry> wordsOlder = <WordEntry>[
  WordEntry('LANTERN', 'A light you can carry'),
  WordEntry('HARVEST', 'Gathering the crops'),
  WordEntry('JOURNEY', 'A long trip'),
  WordEntry('MYSTERY', 'Something nobody can explain yet'),
  WordEntry('COMPASS', 'It points north'),
  WordEntry('SILHOUETTE', 'A dark shape against the light'),
  WordEntry('ORCHESTRA', 'Many instruments, one piece'),
  WordEntry('ADVENTURE', 'An exciting thing you set out to do'),
];

List<WordEntry> wordBankForAge(int age) => age < 8 ? wordsYoung : age < 13 ? wordsMiddle : wordsOlder;

/// A word for [age], never the same as [not] twice in a row when the bank has more than one.
WordEntry pickWord(int age, Random rng, {String? not}) {
  final List<WordEntry> bank = wordBankForAge(age);
  final List<WordEntry> pool = bank.length > 1 ? bank.where((WordEntry w) => w.word != not).toList() : bank;
  return pool[rng.nextInt(pool.length)];
}

// ================================================================== war solo ==

enum WarSoloPhase { ready, revealed, done }

/// War against the game. [pending] cards are on the table face up; [pot] holds earlier tied cards.
class WarSolo {
  const WarSolo({
    required this.mine,
    required this.theirs,
    required this.myTable,
    required this.theirTable,
    required this.pot,
    required this.round,
    required this.phase,
    required this.note,
    required this.ended,
  });

  final List<PlayingCard> mine;
  final List<PlayingCard> theirs;
  final List<PlayingCard> myTable;
  final List<PlayingCard> theirTable;
  final List<PlayingCard> pot;
  final int round;
  final WarSoloPhase phase;

  /// A short, warm line for what just happened. Never a tally.
  final String? note;

  /// 'won' | 'lost' | 'tie' | null.
  final String? ended;
}

/// The prototype caps a game at 120 flips and calls it level.
const int warSoloFlipCap = 120;

WarSolo newWarSolo(Random rng) {
  final List<PlayingCard> deck = shuffledCopy(standardDeck(), rng);
  return WarSolo(
    mine: deck.sublist(0, 26), theirs: deck.sublist(26),
    myTable: const <PlayingCard>[], theirTable: const <PlayingCard>[], pot: const <PlayingCard>[],
    round: 1, phase: WarSoloPhase.ready, note: null, ended: null,
  );
}

/// Both sides turn their next card over (two each while a tie is being settled, as in game_war.dart). The cards
/// are left on the table so the screen can show them before [warSoloResolve] moves them.
WarSolo warSoloFlip(WarSolo s) {
  if (s.phase != WarSoloPhase.ready || s.ended != null) return s;
  final int take = s.pot.isNotEmpty ? 2 : 1;
  final int myTake = min(take, s.mine.length);
  final int theirTake = min(take, s.theirs.length);
  if (myTake == 0 || theirTake == 0) return _finish(s);
  return WarSolo(
    mine: s.mine.sublist(myTake), theirs: s.theirs.sublist(theirTake),
    myTable: s.mine.sublist(0, myTake), theirTable: s.theirs.sublist(0, theirTake),
    pot: s.pot, round: s.round, phase: WarSoloPhase.revealed, note: null, ended: null,
  );
}

WarSolo warSoloResolve(WarSolo s) {
  if (s.phase != WarSoloPhase.revealed) return s;
  final List<PlayingCard> stake = <PlayingCard>[...s.pot, ...s.myTable, ...s.theirTable];
  final PlayingCard a = s.myTable.last, b = s.theirTable.last;
  const List<PlayingCard> none = <PlayingCard>[];
  if (a.rank == b.rank) {
    // A tie: everything stays in the pot and the next flip settles it. If either side cannot go on, it is over.
    final WarSolo tied = WarSolo(
      mine: s.mine, theirs: s.theirs, myTable: none, theirTable: none, pot: stake,
      round: s.round, phase: WarSoloPhase.ready, note: "It's a tie! Flip again.", ended: null,
    );
    return (s.mine.isEmpty || s.theirs.isEmpty) ? _finish(tied, tie: true) : tied;
  }
  final bool iWon = a.rank > b.rank;
  final List<PlayingCard> mine = iWon ? <PlayingCard>[...s.mine, ...stake] : s.mine;
  final List<PlayingCard> theirs = iWon ? s.theirs : <PlayingCard>[...s.theirs, ...stake];
  final WarSolo next = WarSolo(
    mine: mine, theirs: theirs, myTable: none, theirTable: none, pot: none,
    round: s.round + 1, phase: WarSoloPhase.ready,
    note: iWon ? 'You take this one.' : 'The game takes this one.', ended: null,
  );
  if (mine.isEmpty || theirs.isEmpty) return _finish(next);
  if (next.round > warSoloFlipCap) return _finish(next, tie: true);
  return next;
}

WarSolo _finish(WarSolo s, {bool tie = false}) {
  final String ended = tie
      ? 'tie'
      : s.mine.isEmpty && s.theirs.isEmpty ? 'tie' : s.theirs.isEmpty ? 'won' : s.mine.isEmpty ? 'lost' : 'tie';
  return WarSolo(
    mine: s.mine, theirs: s.theirs, myTable: s.myTable, theirTable: s.theirTable, pot: s.pot,
    round: s.round, phase: WarSoloPhase.done, note: null, ended: ended,
  );
}
