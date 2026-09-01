// OLIVE BRANCH — Connect 4, pure board logic. Network resilience & ad-hoc
// mode roadmap, Track B Option 2, ad-hoc games expansion. Hand-rolled, not
// a TS port — same reasoning as war_deck.dart's own header: no
// packages/games/src counterpart exists for this game, and this file's
// whole reason to exist is a game that never touches a server (the point
// of local ad-hoc play). game_chess.dart already establishes real
// precedent in this codebase for a hand-rolled, non-ported engine when
// that's the honest choice.
//
// [Side] is deliberately imported from live_games.dart, NOT game_logic
// .dart's own separately-defined `Side{a,b}` (child/parent role, used by
// the single-device catalogue games) — same name, same shape, different
// type, different meaning. Every ad-hoc local-play game in this expansion
// must import Side from live_games.dart, matching local_pairing.dart's own
// [LocalPairingController.mySide].
library;

import 'live_games.dart' show Side;

const int connect4Cols = 7;
const int connect4Rows = 6;

enum Connect4Outcome { none, win, draw }

/// One list per column, stored bottom-to-top, holding ONLY filled cells —
/// column height == list length, and an empty cell is never represented,
/// let alone serialized. Deliberately not reusing live_games.dart's
/// LiveSession/DeckState: that model has no field for accumulated,
/// persistent board state (currentPrompt is simply overwritten each round,
/// never built up turn over turn) and no win-condition concept at all.
class Connect4Board {
  const Connect4Board({required this.columns});
  final List<List<Side>> columns;

  static Connect4Board empty() =>
      Connect4Board(columns: List.generate(connect4Cols, (_) => const <Side>[]));

  bool isColumnFull(int col) => columns[col].length >= connect4Rows;
  bool get isFull => columns.every((c) => c.length >= connect4Rows);
  int get discCount => columns.fold(0, (sum, c) => sum + c.length);

  Connect4Board withMove(int col, Side side) {
    if (col < 0 || col >= connect4Cols || isColumnFull(col)) return this;
    final next = [for (var i = 0; i < connect4Cols; i++) i == col ? [...columns[i], side] : columns[i]];
    return Connect4Board(columns: next);
  }

  Side? at(int col, int row) {
    if (col < 0 || col >= connect4Cols || row < 0 || row >= connect4Rows) return null;
    final column = columns[col];
    if (row >= column.length) return null;
    return column[row];
  }
}

bool isLegalMove(Connect4Board board, int col) =>
    col >= 0 && col < connect4Cols && !board.isColumnFull(col);

/// Returns the winning side, or null if no 4-in-a-row exists yet. Checked
/// from every occupied cell in all four directions (horizontal, vertical,
/// both diagonals) — simple and correct rather than optimized for the
/// specific cell just played, since a full 7x6 board scan is trivially
/// fast either way.
Side? connect4Winner(Connect4Board board) {
  for (var col = 0; col < connect4Cols; col++) {
    for (var row = 0; row < connect4Rows; row++) {
      final side = board.at(col, row);
      if (side == null) continue;
      if (_fourFrom(board, col, row, side, 1, 0)) return side;
      if (_fourFrom(board, col, row, side, 0, 1)) return side;
      if (_fourFrom(board, col, row, side, 1, 1)) return side;
      if (_fourFrom(board, col, row, side, 1, -1)) return side;
    }
  }
  return null;
}

bool _fourFrom(Connect4Board board, int col, int row, Side side, int dCol, int dRow) {
  for (var i = 1; i < 4; i++) {
    if (board.at(col + dCol * i, row + dRow * i) != side) return false;
  }
  return true;
}

class MoveResult {
  const MoveResult({required this.board, required this.outcome, required this.winner, required this.applied});
  final Connect4Board board;
  final Connect4Outcome outcome;
  final Side? winner;
  /// False for an illegal move (full/out-of-range column) — the board
  /// returned is unchanged in that case, never a crash or a silently
  /// dropped disc.
  final bool applied;
}

MoveResult applyMove(Connect4Board board, int col, Side side) {
  if (!isLegalMove(board, col)) {
    return MoveResult(board: board, outcome: Connect4Outcome.none, winner: null, applied: false);
  }
  final next = board.withMove(col, side);
  final winner = connect4Winner(next);
  if (winner != null) {
    return MoveResult(board: next, outcome: Connect4Outcome.win, winner: winner, applied: true);
  }
  if (next.isFull) {
    return MoveResult(board: next, outcome: Connect4Outcome.draw, winner: null, applied: true);
  }
  return MoveResult(board: next, outcome: Connect4Outcome.none, winner: null, applied: true);
}
