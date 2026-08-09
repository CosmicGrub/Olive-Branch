// OLIVE BRANCH — chess. UNVERIFIED (no Flutter toolchain in
// tools/verify.sh's automated pipeline). MASTERFILE §9.2, P2.
//
// The rules engine below (ChSide/ChPiece/ChessState/chessLegalMoves/
// chessMove/chessCoach/chessHandicaps) is written to the same shape as
// game_checkers.dart's port of games2.ts — same spirit of naming, same
// "engine section, then widget section" layout — but it is NOT a 1:1 port,
// for one unavoidable reason: games2.ts's chess section is a thin wrapper
// around the `chess.js` npm package, and no equivalent pure-Dart chess rules
// engine ships in this repo's pubspec.yaml. This group may only ADD new
// files, never edit an existing one (including pubspec.yaml), so adding a
// package dependency was not an option either. The board representation,
// move generator, check/checkmate/stalemate detection, castling, en
// passant, promotion, threefold repetition and the fifty-move rule are all
// hand-rolled below instead of delegated to chess.js.
//
// SIMPLIFICATION, flagged per the assignment brief: insufficient-material
// detection (`_hasInsufficientMaterial`) recognises king-vs-king and
// king-plus-one-minor-vs-king only. It does NOT detect king+bishop vs
// king+bishop on same-coloured squares (a real but rare dead draw). Missing
// that one case never produces a WRONG result, only a slightly late one —
// the game keeps offering legal moves in a dead position until someone
// repeats it three times or hits the fifty-move mark, both of which ARE
// detected. Chosen because implementing bishop-square-colour comparison for
// one rare case wasn't worth the risk of a subtly-wrong board scan in
// otherwise-untested territory.
//
// DELIBERATE CORRECTION, flagged rather than silently "fixed": games2.ts's
// CHESS_HANDICAPS ship FEN strings ('.../PPPPPPPP/RNB1KBNR w KQkq - 0 1')
// that strip pieces from the LAST rank field — which FEN defines as rank 1,
// White's own back rank — while that same file's newChess() comment says
// "the child plays white". Read literally, the reference source hands the
// missing queen to the CHILD, exactly backwards from every handicap label
// ("Dad plays without his queen") and from §9.2's entire point ("she
// chooses what the PARENT gives up"). `chessHandicaps` below removes pieces
// from the PARENT's (ChSide.parent's) side instead, matching the label text
// and the stated design intent rather than reproducing what reads as a
// transposed FEN in the canonical source.
//
// Chess coaching reuses §9.1's posture exactly, per the assignment: `_coach`
// (used to build the on-screen hint) asks the grown-up a Socratic question
// and never states a move — and, unlike games2.ts's own `chessCoach`, never
// touches algebraic notation at all, because this file has no notation
// generator to begin with (chessLegalMoves() returns structured ChMove
// values, not SAN strings) and the assignment explicitly forbids showing it
// as a hint.
//
// As in game_checkers.dart: the "parent" is a simulated local opponent
// (a random legal move, after a short "thinking" pause) because this
// preview build has no session runtime (§3.1) to relay moves between two
// real devices. A move carrying a voice note (§9.2's third shared
// mechanic) is acknowledged as not built here for the same reason checkers
// takes — no audio-capture infrastructure exists yet in this preview build.
//
// P2 governs the whole screen: no ELO, no rank, no move-accuracy score, no
// "you lost" screen. A finished game — win, loss, or draw — closes with
// "Good game." only; the child can still see who is actually in checkmate
// on the board itself, exactly as she could across a real table, but the
// product never narrates it as a verdict on her.
import 'dart:math';
import 'package:flutter/material.dart';

// ============================================================ RULES ENGINE ==
enum ChSide { child, parent }

extension ChSideX on ChSide {
  ChSide get opposite => this == ChSide.child ? ChSide.parent : ChSide.child;
}

enum ChPieceType { pawn, knight, bishop, rook, queen, king }

class ChPiece {
  const ChPiece({required this.type, required this.side});
  final ChPieceType type;
  final ChSide side;
}

/// (rank, file), both 0-7. Rank 0 is the child's home rank; the child's
/// pieces advance toward rank 7, mirroring newChess()'s "the child plays
/// white and moves first". File 0 is the "a" file, kept internal — no
/// square is ever rendered or spoken as a coordinate or in algebraic form.
typedef ChCell = (int r, int c);

typedef ChBoard = List<List<ChPiece?>>;

const List<ChPieceType> _backRank = [
  ChPieceType.rook, ChPieceType.knight, ChPieceType.bishop, ChPieceType.queen,
  ChPieceType.king, ChPieceType.bishop, ChPieceType.knight, ChPieceType.rook,
];

/// Handicaps the CHILD may impose on the parent — material, the honest
/// lever (§9.2). See the file header for why this removes pieces from the
/// PARENT's back rank rather than reproducing games2.ts's FEN literally.
class ChessHandicap {
  const ChessHandicap({required this.id, required this.label, required this.removeFiles});
  final String id;
  final String label;
  /// Files (0-7) cleared from the parent's back rank at game start.
  final List<int> removeFiles;
}

const List<ChessHandicap> chessHandicaps = [
  ChessHandicap(id: 'no_queen', label: "Dad plays without his queen", removeFiles: [3]),
  ChessHandicap(id: 'no_rooks', label: 'Dad plays without both rooks', removeFiles: [0, 7]),
  ChessHandicap(id: 'no_queen_rooks', label: 'Dad plays without his queen and rooks',
    removeFiles: [0, 3, 7]),
];

class ChCastleRights {
  const ChCastleRights({required this.childK, required this.childQ,
    required this.parentK, required this.parentQ});
  final bool childK, childQ, parentK, parentQ;
  ChCastleRights copyWith({bool? childK, bool? childQ, bool? parentK, bool? parentQ}) =>
    ChCastleRights(
      childK: childK ?? this.childK, childQ: childQ ?? this.childQ,
      parentK: parentK ?? this.parentK, parentQ: parentQ ?? this.parentQ);
}

class ChMove {
  const ChMove({required this.from, required this.to, this.promotion,
    this.castle, this.enPassant = false});
  final ChCell from;
  final ChCell to;
  final ChPieceType? promotion;
  /// null | 'K' | 'Q' — kept as a short internal tag, never surfaced.
  final String? castle;
  final bool enPassant;
}

enum ChessOutcome {
  checkmateChild, checkmateParent, drawStalemate, drawRepetition,
  drawInsufficientMaterial, drawFiftyMove,
}

class ChessState {
  const ChessState({required this.board, required this.turn, required this.castleRights,
    required this.enPassantTarget, required this.halfmoveClock, required this.history,
    required this.positionCounts, required this.outcome});
  final ChBoard board;
  final ChSide turn;
  final ChCastleRights castleRights;
  final ChCell? enPassantTarget;
  /// Half-moves since the last capture or pawn push — the fifty-move rule.
  final int halfmoveClock;
  /// Every move actually played, in order. Structured, not algebraic — see
  /// the file header. Replayed from scratch for takebacks, same as
  /// games.ts's takeBack() and checkers' _history stack.
  final List<ChMove> history;
  /// Counts by position key, for threefold repetition.
  final Map<String, int> positionCounts;
  final ChessOutcome? outcome;
}

bool _inB(int r, int c) => r >= 0 && r < 8 && c >= 0 && c < 8;

ChBoard _cloneBoard(ChBoard b) => [for (final row in b) [...row]];

String _posKey(ChBoard board, ChSide turn, ChCastleRights cr, ChCell? ep) {
  final sb = StringBuffer();
  for (final row in board) {
    for (final p in row) {
      sb.write(p == null ? '.' : '${p.side == ChSide.child ? 'c' : 'p'}${_typeCode(p.type)}');
    }
  }
  sb
    ..write(turn == ChSide.child ? 'c' : 'p')
    ..write(cr.childK ? 'K' : '-')
    ..write(cr.childQ ? 'Q' : '-')
    ..write(cr.parentK ? 'k' : '-')
    ..write(cr.parentQ ? 'q' : '-')
    ..write(ep == null ? 'none' : '${ep.$1},${ep.$2}');
  return sb.toString();
}

String _typeCode(ChPieceType t) => switch (t) {
  ChPieceType.pawn => 'p', ChPieceType.knight => 'n', ChPieceType.bishop => 'b',
  ChPieceType.rook => 'r', ChPieceType.queen => 'q', ChPieceType.king => 'k',
};

/// New game. §9.2 — the child always moves first, same default as every
/// other game in games.ts's newGame().
ChessState newChess({String? handicapId}) {
  final board = List<List<ChPiece?>>.generate(8, (_) => List<ChPiece?>.filled(8, null));
  for (var f = 0; f < 8; f++) {
    board[0][f] = ChPiece(type: _backRank[f], side: ChSide.child);
    board[1][f] = const ChPiece(type: ChPieceType.pawn, side: ChSide.child);
    board[6][f] = const ChPiece(type: ChPieceType.pawn, side: ChSide.parent);
    board[7][f] = ChPiece(type: _backRank[f], side: ChSide.parent);
  }
  var parentK = true, parentQ = true;
  ChessHandicap? h;
  for (final candidate in chessHandicaps) {
    if (candidate.id == handicapId) { h = candidate; break; }
  }
  if (h != null) {
    for (final file in h.removeFiles) {
      board[7][file] = null;
      if (file == 0) parentQ = false;
      if (file == 7) parentK = false;
    }
  }
  final cr = ChCastleRights(childK: true, childQ: true, parentK: parentK, parentQ: parentQ);
  final key = _posKey(board, ChSide.child, cr, null);
  return ChessState(board: board, turn: ChSide.child, castleRights: cr, enPassantTarget: null,
    halfmoveClock: 0, history: const [], positionCounts: {key: 1}, outcome: null);
}

List<ChCell> _knightOffsets(int r, int c) => [
  (r + 1, c + 2), (r + 2, c + 1), (r + 2, c - 1), (r + 1, c - 2),
  (r - 1, c - 2), (r - 2, c - 1), (r - 2, c + 1), (r - 1, c + 2),
];
List<ChCell> _kingOffsets(int r, int c) => [
  (r + 1, c), (r + 1, c + 1), (r + 1, c - 1), (r - 1, c),
  (r - 1, c + 1), (r - 1, c - 1), (r, c + 1), (r, c - 1),
];
const List<ChCell> _diagDirs = [(1, 1), (1, -1), (-1, 1), (-1, -1)];
const List<ChCell> _orthoDirs = [(1, 0), (-1, 0), (0, 1), (0, -1)];

/// True if any [bySide] piece on [board] attacks (r, c) — used for check
/// detection and for vetting the squares a king castles across.
bool _attacked(ChBoard board, int r, int c, ChSide bySide) {
  final pawnFromRank = bySide == ChSide.child ? r - 1 : r + 1;
  for (final df in [-1, 1]) {
    if (_inB(pawnFromRank, c + df)) {
      final p = board[pawnFromRank][c + df];
      if (p != null && p.side == bySide && p.type == ChPieceType.pawn) return true;
    }
  }
  for (final (kr, kc) in _knightOffsets(r, c)) {
    if (_inB(kr, kc)) {
      final p = board[kr][kc];
      if (p != null && p.side == bySide && p.type == ChPieceType.knight) return true;
    }
  }
  for (final (kr, kc) in _kingOffsets(r, c)) {
    if (_inB(kr, kc)) {
      final p = board[kr][kc];
      if (p != null && p.side == bySide && p.type == ChPieceType.king) return true;
    }
  }
  for (final (dr, dc) in _diagDirs) {
    var pr = r + dr, pc = c + dc;
    while (_inB(pr, pc)) {
      final p = board[pr][pc];
      if (p != null) {
        if (p.side == bySide && (p.type == ChPieceType.bishop || p.type == ChPieceType.queen)) return true;
        break;
      }
      pr += dr; pc += dc;
    }
  }
  for (final (dr, dc) in _orthoDirs) {
    var pr = r + dr, pc = c + dc;
    while (_inB(pr, pc)) {
      final p = board[pr][pc];
      if (p != null) {
        if (p.side == bySide && (p.type == ChPieceType.rook || p.type == ChPieceType.queen)) return true;
        break;
      }
      pr += dr; pc += dc;
    }
  }
  return false;
}

ChCell? _findKing(ChBoard board, ChSide side) {
  for (var r = 0; r < 8; r++) {
    for (var c = 0; c < 8; c++) {
      final p = board[r][c];
      if (p != null && p.side == side && p.type == ChPieceType.king) return (r, c);
    }
  }
  return null; // shouldn't happen in a reachable position
}

bool isInCheck(ChBoard board, ChSide side) {
  final k = _findKing(board, side);
  return k != null && _attacked(board, k.$1, k.$2, side.opposite);
}

List<ChMove> _pseudoMovesFrom(ChessState s, int r, int c) {
  final p = s.board[r][c];
  if (p == null) return const [];
  return switch (p.type) {
    ChPieceType.pawn => _pawnMoves(s, r, c, p.side),
    ChPieceType.knight => [
      for (final (tr, tc) in _knightOffsets(r, c))
        if (_inB(tr, tc) && s.board[tr][tc]?.side != p.side) ChMove(from: (r, c), to: (tr, tc)),
    ],
    ChPieceType.bishop => _slideMoves(s.board, r, c, p.side, _diagDirs),
    ChPieceType.rook => _slideMoves(s.board, r, c, p.side, _orthoDirs),
    ChPieceType.queen => _slideMoves(s.board, r, c, p.side, [..._diagDirs, ..._orthoDirs]),
    ChPieceType.king => _kingMoves(s, r, c, p.side),
  };
}

List<ChMove> _pawnMoves(ChessState s, int r, int c, ChSide side) {
  final moves = <ChMove>[];
  final dir = side == ChSide.child ? 1 : -1;
  final startRank = side == ChSide.child ? 1 : 6;
  final lastRank = side == ChSide.child ? 7 : 0;
  final oneR = r + dir;
  void add(int tr, int tc, {bool ep = false}) {
    if (tr == lastRank) {
      for (final promo in const [ChPieceType.queen, ChPieceType.rook,
          ChPieceType.bishop, ChPieceType.knight]) {
        moves.add(ChMove(from: (r, c), to: (tr, tc), promotion: promo, enPassant: ep));
      }
    } else {
      moves.add(ChMove(from: (r, c), to: (tr, tc), enPassant: ep));
    }
  }
  if (_inB(oneR, c) && s.board[oneR][c] == null) {
    add(oneR, c);
    final twoR = r + dir * 2;
    if (r == startRank && s.board[twoR][c] == null) moves.add(ChMove(from: (r, c), to: (twoR, c)));
  }
  for (final df in [-1, 1]) {
    final tc = c + df;
    if (!_inB(oneR, tc)) continue;
    final target = s.board[oneR][tc];
    if (target != null && target.side != side) {
      add(oneR, tc);
    } else if (target == null && s.enPassantTarget == (oneR, tc)) {
      add(oneR, tc, ep: true);
    }
  }
  return moves;
}

List<ChMove> _slideMoves(ChBoard board, int r, int c, ChSide side, List<ChCell> dirs) {
  final moves = <ChMove>[];
  for (final (dr, dc) in dirs) {
    var tr = r + dr, tc = c + dc;
    while (_inB(tr, tc)) {
      final target = board[tr][tc];
      if (target == null) {
        moves.add(ChMove(from: (r, c), to: (tr, tc)));
      } else {
        if (target.side != side) moves.add(ChMove(from: (r, c), to: (tr, tc)));
        break;
      }
      tr += dr; tc += dc;
    }
  }
  return moves;
}

List<ChMove> _kingMoves(ChessState s, int r, int c, ChSide side) {
  final moves = <ChMove>[
    for (final (tr, tc) in _kingOffsets(r, c))
      if (_inB(tr, tc) && s.board[tr][tc]?.side != side) ChMove(from: (r, c), to: (tr, tc)),
  ];
  final homeRank = side == ChSide.child ? 0 : 7;
  if (r != homeRank || c != 4) return moves;
  final canK = side == ChSide.child ? s.castleRights.childK : s.castleRights.parentK;
  final canQ = side == ChSide.child ? s.castleRights.childQ : s.castleRights.parentQ;
  if (_attacked(s.board, homeRank, 4, side.opposite)) return moves; // can't castle out of check
  if (canK && s.board[homeRank][5] == null && s.board[homeRank][6] == null &&
      s.board[homeRank][7]?.type == ChPieceType.rook && s.board[homeRank][7]?.side == side &&
      !_attacked(s.board, homeRank, 5, side.opposite) &&
      !_attacked(s.board, homeRank, 6, side.opposite)) {
    moves.add(ChMove(from: (r, c), to: (homeRank, 6), castle: 'K'));
  }
  if (canQ && s.board[homeRank][1] == null && s.board[homeRank][2] == null &&
      s.board[homeRank][3] == null &&
      s.board[homeRank][0]?.type == ChPieceType.rook && s.board[homeRank][0]?.side == side &&
      !_attacked(s.board, homeRank, 3, side.opposite) &&
      !_attacked(s.board, homeRank, 2, side.opposite)) {
    moves.add(ChMove(from: (r, c), to: (homeRank, 2), castle: 'Q'));
  }
  return moves;
}

/// All fully-legal moves for whoever's turn it is — pseudo-legal moves with
/// any that leave that side's own king in check filtered out.
List<ChMove> chessLegalMoves(ChessState s) {
  final side = s.turn;
  final result = <ChMove>[];
  for (var r = 0; r < 8; r++) {
    for (var c = 0; c < 8; c++) {
      final p = s.board[r][c];
      if (p == null || p.side != side) continue;
      for (final m in _pseudoMovesFrom(s, r, c)) {
        final next = _applyToBoard(s, m);
        if (!isInCheck(next, side)) result.add(m);
      }
    }
  }
  return result;
}

ChBoard _applyToBoard(ChessState s, ChMove m) {
  final board = _cloneBoard(s.board);
  final moving = board[m.from.$1][m.from.$2]!;
  if (m.enPassant) board[m.from.$1][m.to.$2] = null; // captured pawn sits beside the mover
  board[m.from.$1][m.from.$2] = null;
  board[m.to.$1][m.to.$2] = m.promotion != null
      ? ChPiece(type: m.promotion!, side: moving.side) : moving;
  if (m.castle == 'K') {
    board[m.from.$1][5] = board[m.from.$1][7];
    board[m.from.$1][7] = null;
  } else if (m.castle == 'Q') {
    board[m.from.$1][3] = board[m.from.$1][0];
    board[m.from.$1][0] = null;
  }
  return board;
}

/// Applies a legal move and returns the resulting state, including outcome
/// detection. Callers are expected to have already checked the move against
/// chessLegalMoves() — mirrors checkers' playCheckers() shape (explicit
/// cells, not notation) rather than games2.ts's SAN-string chessMove(), for
/// the reasons in the file header.
class ChessMoveResult {
  const ChessMoveResult.ok(this.state) : reason = null;
  const ChessMoveResult.err(this.reason) : state = null;
  final ChessState? state;
  final String? reason;
  bool get ok => state != null;
}

ChessMoveResult chessMove(ChessState s, ChCell from, ChCell to, {ChPieceType? promotion}) {
  if (s.outcome != null) return const ChessMoveResult.err('game_over');
  final candidates = chessLegalMoves(s).where((m) => m.from == from && m.to == to).toList();
  if (candidates.isEmpty) return const ChessMoveResult.err('illegal_move');
  ChMove chosen;
  if (candidates.length > 1) {
    if (promotion == null) return const ChessMoveResult.err('promotion_required');
    final match = candidates.where((m) => m.promotion == promotion);
    if (match.isEmpty) return const ChessMoveResult.err('illegal_move');
    chosen = match.first;
  } else {
    chosen = candidates.first;
  }

  final moving = s.board[from.$1][from.$2]!;
  final wasCapture = s.board[to.$1][to.$2] != null || chosen.enPassant;
  final board = _applyToBoard(s, chosen);

  var cr = s.castleRights;
  if (moving.type == ChPieceType.king) {
    cr = moving.side == ChSide.child
        ? cr.copyWith(childK: false, childQ: false)
        : cr.copyWith(parentK: false, parentQ: false);
  }
  void loseRookRight(ChCell at) {
    if (at == (0, 0)) cr = cr.copyWith(childQ: false);
    if (at == (0, 7)) cr = cr.copyWith(childK: false);
    if (at == (7, 0)) cr = cr.copyWith(parentQ: false);
    if (at == (7, 7)) cr = cr.copyWith(parentK: false);
  }
  if (moving.type == ChPieceType.rook) loseRookRight(from);
  loseRookRight(to); // a captured rook loses its own side's right too

  ChCell? ep;
  if (moving.type == ChPieceType.pawn && (to.$1 - from.$1).abs() == 2) {
    ep = ((to.$1 + from.$1) ~/ 2, from.$2);
  }
  final halfmove = (moving.type == ChPieceType.pawn || wasCapture) ? 0 : s.halfmoveClock + 1;
  final nextTurn = s.turn.opposite;
  final key = _posKey(board, nextTurn, cr, ep);
  final positionCounts = Map<String, int>.from(s.positionCounts);
  positionCounts[key] = (positionCounts[key] ?? 0) + 1;

  var next = ChessState(board: board, turn: nextTurn, castleRights: cr, enPassantTarget: ep,
    halfmoveClock: halfmove, history: [...s.history, chosen],
    positionCounts: positionCounts, outcome: null);
  next = ChessState(board: next.board, turn: next.turn, castleRights: next.castleRights,
    enPassantTarget: next.enPassantTarget, halfmoveClock: next.halfmoveClock,
    history: next.history, positionCounts: next.positionCounts,
    outcome: _computeOutcome(next, key));
  return ChessMoveResult.ok(next);
}

/// King-vs-king and king-plus-one-minor-vs-king only — see the file header's
/// SIMPLIFICATION note.
bool _hasInsufficientMaterial(ChBoard board) {
  final nonKings = <ChPiece>[];
  for (final row in board) {
    for (final p in row) {
      if (p != null && p.type != ChPieceType.king) nonKings.add(p);
    }
  }
  if (nonKings.isEmpty) return true;
  return nonKings.length == 1 &&
      (nonKings.first.type == ChPieceType.bishop || nonKings.first.type == ChPieceType.knight);
}

ChessOutcome? _computeOutcome(ChessState s, String currentKey) {
  if (chessLegalMoves(s).isEmpty) {
    if (isInCheck(s.board, s.turn)) {
      return s.turn == ChSide.child ? ChessOutcome.checkmateParent : ChessOutcome.checkmateChild;
    }
    return ChessOutcome.drawStalemate;
  }
  if (s.halfmoveClock >= 100) return ChessOutcome.drawFiftyMove;
  if ((s.positionCounts[currentKey] ?? 0) >= 3) return ChessOutcome.drawRepetition;
  if (_hasInsufficientMaterial(s.board)) return ChessOutcome.drawInsufficientMaterial;
  return null;
}

/// Free, unlimited takebacks (§9.2) — implemented by replaying from the
/// start, same approach and same reasoning as games.ts's takeBack() and
/// game_checkers.dart's _undo(): inverting the last move is where takeback
/// bugs live, especially around castling and en passant here.
ChessState chessTakeBack(ChessState s, {String? handicapId}) {
  if (s.history.isEmpty) return s;
  final keep = s.history.sublist(0, s.history.length - 1);
  var replay = newChess(handicapId: handicapId);
  for (final m in keep) {
    final r = chessMove(replay, m.from, m.to, promotion: m.promotion);
    if (r.ok) replay = r.state!;
  }
  return replay;
}

/// §9.1's "hint, don't solve" posture, ported to chess: coaches the grown-up
/// with a Socratic question and never states the move — and never touches
/// algebraic notation, because nothing in this file generates any.
String chessCoach(ChessState s) {
  if (isInCheck(s.board, s.turn)) {
    return "Your king is in check. Ask her which pieces could block it, "
        'or whether the king has anywhere safe to go.';
  }
  final moves = chessLegalMoves(s);
  final canCapture = moves.any((m) => s.board[m.to.$1][m.to.$2] != null || m.enPassant);
  if (canCapture) {
    return "There's something she can take. Ask her what she notices is undefended, "
        "rather than pointing it out.";
  }
  if (s.history.length < 6) {
    return 'Ask her which of her pieces still cannot move, and why that matters.';
  }
  return 'Ask her what her last move was defending, before she moves again.';
}

// ================================================================= WIDGET ===
class GameChess extends StatefulWidget {
  const GameChess({
    super.key,
    this.childName = 'Ivy',
    this.parentName = 'Dad',
    this.botThinkDelay = const Duration(milliseconds: 550),
  });

  final String childName;
  final String parentName;
  /// How long the simulated opponent "thinks" before replying. Exposed for
  /// tests, not because a settings affordance belongs on this screen —
  /// there is none, anywhere in this file.
  final Duration botThinkDelay;

  @override
  State<GameChess> createState() => _GameChessState();
}

class _GameChessState extends State<GameChess> {
  bool _setupDone = false;
  String? _handicapId;
  ChessState _state = newChess();
  ChCell? _selected;
  List<ChMove> _legalFromSelected = const [];
  bool _parentThinking = false;
  ChCell? _pendingPromotionFrom, _pendingPromotionTo;

  void _startGame(String? handicapId) {
    setState(() {
      _handicapId = handicapId;
      _state = newChess(handicapId: handicapId);
      _setupDone = true;
      _selected = null;
      _legalFromSelected = const [];
      _parentThinking = false;
    });
  }

  void _resetToSetup() {
    setState(() {
      _setupDone = false;
      _state = newChess(handicapId: _handicapId);
      _selected = null;
      _legalFromSelected = const [];
      _parentThinking = false;
    });
  }

  void _playAgainSameSetup() => _startGame(_handicapId);

  void _selectSquare(ChCell cell) {
    final piece = _state.board[cell.$1][cell.$2];
    if (piece == null || piece.side != ChSide.child) return;
    final legal = chessLegalMoves(_state).where((m) => m.from == cell).toList();
    setState(() {
      _selected = legal.isEmpty ? null : cell;
      _legalFromSelected = legal;
    });
  }

  void _tapCell(int r, int c) {
    if (_state.outcome != null || _parentThinking || _state.turn != ChSide.child) return;
    final cell = (r, c);
    if (_selected == null) {
      _selectSquare(cell);
      return;
    }
    if (cell == _selected) {
      setState(() { _selected = null; _legalFromSelected = const []; });
      return;
    }
    final ownPieceHere = _state.board[r][c]?.side == ChSide.child;
    final matches = _legalFromSelected.where((m) => m.to == cell).toList();
    if (matches.isEmpty) {
      if (ownPieceHere) _selectSquare(cell);
      return;
    }
    if (matches.length > 1) {
      // Every match-with-more-than-one case is the four promotion choices.
      setState(() { _pendingPromotionFrom = _selected; _pendingPromotionTo = cell; });
      return;
    }
    _applyMove(_selected!, cell);
  }

  void _applyMove(ChCell from, ChCell to, {ChPieceType? promotion}) {
    final result = chessMove(_state, from, to, promotion: promotion);
    if (!result.ok) return; // engine already vetted via _legalFromSelected
    setState(() {
      _state = result.state!;
      _selected = null;
      _legalFromSelected = const [];
      _pendingPromotionFrom = null;
      _pendingPromotionTo = null;
    });
    if (_state.outcome == null && _state.turn == ChSide.parent) _scheduleParentMove();
  }

  void _scheduleParentMove() {
    setState(() => _parentThinking = true);
    Future.delayed(widget.botThinkDelay, () {
      if (!mounted) return;
      final moves = chessLegalMoves(_state);
      if (moves.isEmpty) { setState(() => _parentThinking = false); return; }
      final pick = moves[Random().nextInt(moves.length)];
      final result = chessMove(_state, pick.from, pick.to, promotion: pick.promotion);
      setState(() {
        _parentThinking = false;
        if (result.ok) _state = result.state!;
      });
    });
  }

  void _takeBack() {
    if (_state.history.isEmpty) return;
    setState(() {
      _state = chessTakeBack(_state, handicapId: _handicapId);
      _selected = null;
      _legalFromSelected = const [];
      _parentThinking = false;
      _pendingPromotionFrom = null;
      _pendingPromotionTo = null;
    });
  }

  void _choosePromotion(ChPieceType type) {
    final from = _pendingPromotionFrom, to = _pendingPromotionTo;
    if (from == null || to == null) return;
    _applyMove(from, to, promotion: type);
  }

  @override
  Widget build(BuildContext context) {
    if (!_setupDone) {
      return _ChessSetup(childName: widget.childName, parentName: widget.parentName,
        onStart: _startGame);
    }

    final scheme = Theme.of(context).colorScheme;
    final finished = _state.outcome != null;
    final childInCheck = !finished && isInCheck(_state.board, ChSide.child);
    final parentInCheck = !finished && isInCheck(_state.board, ChSide.parent);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chess'),
        actions: [
          IconButton(
            tooltip: 'Add a voice note',
            icon: const Icon(Icons.mic_none),
            onPressed: () => _notBuiltYetChess(context, 'Voice notes on moves'),
          ),
        ],
      ),
      body: SafeArea(child: LayoutBuilder(builder: (context, constraints) {
        final narrow = constraints.maxWidth < 420;
        return ListView(padding: const EdgeInsets.all(16), children: [
          if (_handicapBanner() != null) Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _CalloutBanner(text: _handicapBanner()!)),
          _TurnBanner(finished: finished, parentThinking: _parentThinking,
            childName: widget.childName, parentName: widget.parentName,
            isChildTurn: _state.turn == ChSide.child),
          if (childInCheck) const Padding(padding: EdgeInsets.only(top: 8),
            child: _CalloutBanner(text: 'Your king is in check!')),
          if (parentInCheck) Padding(padding: const EdgeInsets.only(top: 8),
            child: _CalloutBanner(text: "${widget.parentName}'s king is in check.")),
          if (finished) Padding(padding: const EdgeInsets.only(top: 8),
            child: _EndBanner(line: _outcomeLine(_state.outcome!))),
          if (!finished && _state.turn == ChSide.parent) Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _CoachCard(text: chessCoach(_state))),
          const SizedBox(height: 12),
          Center(child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: narrow ? constraints.maxWidth : 460),
            child: AspectRatio(aspectRatio: 1, child: _ChessBoardView(
              state: _state, selected: _selected,
              legalDestinations: {for (final m in _legalFromSelected) m.to},
              inCheckSquare: finished ? null
                  : (childInCheck ? _findKing(_state.board, ChSide.child)
                      : parentInCheck ? _findKing(_state.board, ChSide.parent) : null),
              onTapCell: _tapCell, scheme: scheme,
            )),
          )),
          const SizedBox(height: 16),
          // Wrap, not a Row: on the Fold5 cover screen (344 CSS px), even
          // just "Take that back" + "Change setup" don't fit on one line —
          // confirmed by a widget test at that width — and a third button
          // once the game finishes makes it worse. This must wrap to
          // additional rows rather than overflow.
          Wrap(alignment: WrapAlignment.center, spacing: 12, runSpacing: 10, children: [
            SizedBox(height: 48, child: OutlinedButton.icon(
              onPressed: _state.history.isEmpty ? null : _takeBack,
              icon: const Icon(Icons.undo),
              label: const Text('Take that back'),
            )),
            SizedBox(height: 48, child: OutlinedButton.icon(
              onPressed: _resetToSetup,
              icon: const Icon(Icons.tune),
              label: const Text('Change setup'),
            )),
            if (finished) SizedBox(height: 48, child: FilledButton.icon(
              onPressed: _playAgainSameSetup,
              icon: const Icon(Icons.refresh),
              label: const Text('Play again'),
            )),
          ]),
        ]);
      })),
      // Only the child's own drag ever lands here — the simulated parent
      // resolves its own promotion choice before calling chessMove() at all
      // (see _scheduleParentMove), so this sheet never needs to ask him.
      bottomSheet: _pendingPromotionFrom == null ? null
          : _PromotionPicker(side: ChSide.child, onChoose: _choosePromotion),
    );
  }

  String? _handicapBanner() {
    if (_handicapId == null) return null;
    for (final h in chessHandicaps) {
      if (h.id == _handicapId) return "${widget.parentName}'s playing the hard way — ${h.label.toLowerCase()}";
    }
    return null;
  }

  // P2 — the board itself shows a checkmate; the product never narrates a
  // verdict on top of it. Every branch below states a chess FACT, never a
  // winner or loser.
  String _outcomeLine(ChessOutcome o) => switch (o) {
    ChessOutcome.checkmateChild || ChessOutcome.checkmateParent => 'Checkmate. Good game.',
    ChessOutcome.drawStalemate => 'Stalemate — nobody can move. Good game.',
    ChessOutcome.drawRepetition => 'The same position happened three times. Good game.',
    ChessOutcome.drawFiftyMove => 'Fifty moves with no capture. Good game.',
    ChessOutcome.drawInsufficientMaterial => "Not enough pieces left for either side to win. Good game.",
  };
}

void _notBuiltYetChess(BuildContext context, String what) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('$what — not built yet.'), duration: const Duration(seconds: 2)));
}

class _ChessSetup extends StatefulWidget {
  const _ChessSetup({required this.childName, required this.parentName, required this.onStart});
  final String childName, parentName;
  final ValueChanged<String?> onStart;
  @override
  State<_ChessSetup> createState() => _ChessSetupState();
}

class _ChessSetupState extends State<_ChessSetup> {
  String? _choice; // null = no handicap
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Chess')),
    body: SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: [
      Text('You go first.', style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 8),
      // Reuses games.ts's handicapOffer() prompt verbatim — her choice, her
      // framing, never "you keep losing".
      Text('Want to make it harder for ${widget.parentName}?',
        style: Theme.of(context).textTheme.bodyMedium),
      const SizedBox(height: 16),
      _SetupOption(label: 'No — play it straight', selected: _choice == null,
        onTap: () => setState(() => _choice = null)),
      for (final h in chessHandicaps) _SetupOption(label: h.label, selected: _choice == h.id,
        onTap: () => setState(() => _choice = h.id)),
      const SizedBox(height: 16),
      SizedBox(width: double.infinity, height: 52, child: FilledButton(
        onPressed: () => widget.onStart(_choice),
        child: const Text('Start game'),
      )),
    ])),
  );
}

class _SetupOption extends StatelessWidget {
  const _SetupOption({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(padding: const EdgeInsets.only(bottom: 8), child: InkWell(
      onTap: onTap, borderRadius: BorderRadius.circular(14),
      child: Container(constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(14),
          color: selected ? scheme.primaryContainer : scheme.surfaceContainerHighest,
          border: selected ? Border.all(color: scheme.primary, width: 2) : null),
        child: Row(children: [
          Icon(selected ? Icons.check_circle : Icons.circle_outlined,
            color: selected ? scheme.primary : scheme.outline),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
        ])),
    ));
  }
}

class _TurnBanner extends StatelessWidget {
  const _TurnBanner({required this.finished, required this.parentThinking,
    required this.childName, required this.parentName, required this.isChildTurn});
  final bool finished, parentThinking, isChildTurn;
  final String childName, parentName;
  @override
  Widget build(BuildContext context) {
    final text = finished ? 'Good game.'
        : isChildTurn ? "$childName's move"
        : parentThinking ? "$parentName is thinking…" : "$parentName's move";
    return Text(text, style: Theme.of(context).textTheme.titleLarge);
  }
}

class _EndBanner extends StatelessWidget {
  const _EndBanner({required this.line});
  final String line;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(color: Theme.of(context).colorScheme.tertiaryContainer,
      borderRadius: BorderRadius.circular(16)),
    child: Row(children: [
      const Icon(Icons.emoji_events_outlined),
      const SizedBox(width: 8),
      Expanded(child: Text(line, style: const TextStyle(fontWeight: FontWeight.w600))),
    ]),
  );
}

/// A card for the grown-up, visibly distinct from the rest of the (kid-
/// bright) screen — the coaching is addressed to him, not to her.
class _CoachCard extends StatelessWidget {
  const _CoachCard({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: const Duration(milliseconds: 250),
    child: Container(key: ValueKey<String>(text),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.lightbulb_outline, size: 18),
        const SizedBox(width: 8),
        Expanded(
            child: Text(text,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(fontStyle: FontStyle.italic))),
      ]),
    ),
  );
}

class _CalloutBanner extends StatelessWidget {
  const _CalloutBanner({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 200),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(color: Theme.of(context).colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(12)),
    child: Text(text, style: Theme.of(context).textTheme.bodySmall),
  );
}

class _PromotionPicker extends StatelessWidget {
  const _PromotionPicker({required this.side, required this.onChoose});
  final ChSide side;
  final ValueChanged<ChPieceType> onChoose;
  @override
  Widget build(BuildContext context) => Material(
    // M3 elevation, not a hand-rolled flat box-shadow — see the design-token
    // audit's Finding #5.
    color: Theme.of(context).colorScheme.surface,
    elevation: 6,
    shadowColor: Theme.of(context).colorScheme.shadow,
    surfaceTintColor: Theme.of(context).colorScheme.surfaceTint,
    borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Choose a piece',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          for (final t in const [ChPieceType.queen, ChPieceType.rook,
              ChPieceType.bishop, ChPieceType.knight])
            SizedBox(width: 64, height: 64, child: OutlinedButton(
              onPressed: () => onChoose(t),
              style: OutlinedButton.styleFrom(shape: const CircleBorder()),
              child: Text(_glyph(ChPiece(type: t, side: side)), style: const TextStyle(fontSize: 30)),
            )),
        ]),
      ]),
    ),
  );
}

String _glyph(ChPiece p) {
  final child = p.side == ChSide.child;
  return switch (p.type) {
    ChPieceType.king => child ? '♔' : '♚',
    ChPieceType.queen => child ? '♕' : '♛',
    ChPieceType.rook => child ? '♖' : '♜',
    ChPieceType.bishop => child ? '♗' : '♝',
    ChPieceType.knight => child ? '♘' : '♞',
    ChPieceType.pawn => child ? '♙' : '♟',
  };
}

class _ChessBoardView extends StatelessWidget {
  const _ChessBoardView({required this.state, required this.selected,
    required this.legalDestinations, required this.inCheckSquare,
    required this.onTapCell, required this.scheme});
  final ChessState state;
  final ChCell? selected;
  final Set<ChCell> legalDestinations;
  final ChCell? inCheckSquare;
  final void Function(int r, int c) onTapCell;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 8),
      itemCount: 64,
      itemBuilder: (context, i) {
        // Rank 7 (the parent's home rank) renders at the top of the screen.
        final r = 7 - i ~/ 8, c = i % 8;
        final dark = (r + c) % 2 == 1;
        final piece = state.board[r][c];
        final isSelected = selected == (r, c);
        final isLegal = legalDestinations.contains((r, c));
        final isCheck = inCheckSquare == (r, c);
        return GestureDetector(
          onTap: () => onTapCell(r, c),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            color: isCheck
                ? const Color(0xFFD97757)
                : isSelected
                    ? scheme.primary.withValues(alpha: 0.55)
                    : isLegal
                        ? scheme.primary.withValues(alpha: 0.28)
                        : dark ? const Color(0xFF6B7A4F) : const Color(0xFFF3ECD8),
            child: piece == null
                ? (isLegal ? const Center(child: _EmptyDot()) : null)
                : Center(child: FractionallySizedBox(widthFactor: 0.78, heightFactor: 0.78,
                    child: FittedBox(child: Text(_glyph(piece))))),
          ),
        );
      },
    ),
  );
}

class _EmptyDot extends StatelessWidget {
  const _EmptyDot();
  @override
  Widget build(BuildContext context) => Container(
    width: 14, height: 14,
    decoration: BoxDecoration(shape: BoxShape.circle,
      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.65)),
  );
}
