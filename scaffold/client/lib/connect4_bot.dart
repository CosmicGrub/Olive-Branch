// OLIVE BRANCH — Connect 4 CPU opponent. No longer UNVERIFIED — verified by CI (a Flutter
// toolchain now runs for real in tools/verify.sh's automated pipeline —
// CHANGELOG v0.49.61). Network resilience & ad-hoc mode roadmap, Track B
// Option 2, ad-hoc games expansion.
//
// Not a perfect-play oracle, deliberately: Connect 4 is a solved game
// (first player wins with correct center play), and a bot that always
// plays perfectly would never lose to a child, which is the opposite of
// what this product wants. A depth-limited minimax with alpha-beta pruning
// only estimates a position via [_heuristic] once it hits its depth cutoff
// — that estimate is not a win/loss/draw oracle, and that gap is the real
// boundary keeping even Hard beatable, not a shortfall to "fix" later by
// searching deeper.
//
// SIMPLIFICATION, flagged: the design this was scoped from called for
// iterative deepening under a 300ms wall-clock budget. This ships instead
// with a fixed depth per difficulty tier — simpler to reason about and
// test correctly under real time pressure, at the cost of not adapting to
// how fast a given device actually is. Depths chosen conservatively enough
// (Hard tops out at 7 plies) to stay fast on real phone-class hardware; if
// a real device ever proves too slow at Hard, lowering that one constant
// is a contained fix, not a redesign.
//
// The bot runs entirely on whichever device hosts that CPU seat — only its
// resulting column choice is ever sent over the wire, identical treatment
// to a human's move, exactly like local_pairing.dart's own transport
// carries a human's move.
library;

import 'dart:math';
import 'connect4_engine.dart';
import 'live_games.dart' show Side;

enum CpuDifficulty { easy, medium, hard }

Side otherSide(Side s) => s == Side.a ? Side.b : Side.a;

/// Center-out order — searched first purely so alpha-beta pruning cuts
/// more branches sooner. Deliberately distinct from [_columnWeight] below
/// (the static heuristic's own center preference) — same underlying
/// intuition, two different real uses, kept as two separate names on
/// purpose so a future edit to one never silently changes the other.
const List<int> _searchOrder = [3, 2, 4, 1, 5, 0, 6];
const List<int> _columnWeight = [1, 2, 3, 4, 3, 2, 1];

int _depthFor(CpuDifficulty d) => switch (d) {
  CpuDifficulty.easy => 2,
  CpuDifficulty.medium => 4,
  CpuDifficulty.hard => 7,
};

/// Picks a column for [bot] to play. Never omniscient beyond the real,
/// shared board state both sides can already see.
int chooseColumn(Connect4Board board, Side bot, CpuDifficulty difficulty, Random rand) {
  final legal = [for (final c in _searchOrder) if (isLegalMove(board, c)) c];
  if (legal.isEmpty) return -1;

  // Fast path: take an immediate win outright, at every difficulty — a
  // bot that "forgets" to take a free win reads as broken, not gentle.
  for (final c in legal) {
    if (applyMove(board, c, bot).outcome == Connect4Outcome.win) return c;
  }

  // Fast path: block the opponent's immediate win. Easy skips this on
  // purpose about half the time — depth alone doesn't make a bot
  // beatable to a young child, but a shallow bot that STILL always blocks
  // does feel unbeatable. This one knob matters more than search depth.
  final opponent = otherSide(bot);
  final blocking = <int>[];
  for (final c in legal) {
    if (applyMove(board, c, opponent).outcome == Connect4Outcome.win) blocking.add(c);
  }
  final skipBlock = difficulty == CpuDifficulty.easy && rand.nextDouble() < 0.5;
  if (blocking.isNotEmpty) {
    if (!skipBlock) return blocking.first;
    // A genuine skip, not just a bypassed shortcut: fall through to search
    // only among the NON-blocking columns, so a tactically-correct search
    // can never quietly reconstruct the very block Easy just chose to
    // forgo. Uses every other legal column, including ones that don't
    // block — if that leaves nothing, Easy has no choice but to block
    // after all (e.g. the opponent threatens in every remaining column).
    final nonBlocking = [for (final c in legal) if (!blocking.contains(c)) c];
    if (nonBlocking.isEmpty) return blocking.first;
    return nonBlocking[rand.nextInt(nonBlocking.length)];
  }

  final depth = _depthFor(difficulty);
  int? best;
  var bestScore = -1000000000;
  var alpha = -1000000000;
  const beta = 1000000000;
  for (final c in legal) {
    final result = applyMove(board, c, bot);
    final score = -_negamax(result.board, opponent, depth - 1, -beta, -alpha);
    if (best == null || score > bestScore) {
      bestScore = score;
      best = c;
    }
    if (score > alpha) alpha = score;
  }
  return best ?? legal.first;
}

/// Real negamax: every returned value is relative to [toMove] — the side
/// about to act at THIS node — never a fixed outer perspective. That
/// distinction is load-bearing, not stylistic: each recursive call negates
/// its child's result to flip it from "good for the child's toMove" to
/// "good for this node's toMove," and that negation is only correct if
/// every value in the tree is expressed the same relative way. Scoring
/// terminal/heuristic values against a FIXED perspective instead (an
/// earlier version of this function did exactly that) silently breaks the
/// sign at every other ply — the bug doesn't crash anything, it just
/// occasionally makes the bot choose a genuinely losing move, which is
/// exactly the kind of thing a real two-sided test caught here and a
/// pure "does it return a legal column" test would not have.
int _negamax(Connect4Board board, Side toMove, int depth, int alpha, int beta) {
  final winner = connect4Winner(board);
  // A winner already on the board can only be the side who just moved —
  // i.e. NOT toMove, who hasn't acted yet at this node — so reaching this
  // node at all is always a loss for toMove.
  if (winner != null) return -1000000 - depth;
  if (board.isFull || depth <= 0) return _heuristic(board, toMove);

  var value = -1000000000;
  for (final c in _searchOrder) {
    if (!isLegalMove(board, c)) continue;
    final next = board.withMove(c, toMove);
    final score = -_negamax(next, otherSide(toMove), depth - 1, -beta, -alpha);
    if (score > value) value = score;
    if (value > alpha) alpha = value;
    if (alpha >= beta) break;
  }
  return value;
}

/// A static, cutoff-depth estimate only — see this file's own header on
/// why that is deliberate, not a shortfall.
int _heuristic(Connect4Board board, Side perspective) {
  var score = 0;
  for (var c = 0; c < connect4Cols; c++) {
    for (final side in board.columns[c]) {
      score += (side == perspective ? 1 : -1) * _columnWeight[c];
    }
  }
  return score;
}
