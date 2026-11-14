// OLIVE BRANCH — Puzzle together for two devices, as a [PlayGame] (play_game.dart). The pieces, the slots and the rules stay
// in together_puzzle.dart; this file is only the two-device conversation. UNVERIFIED on a device; the whole
// conversation runs headless over the in-memory and the real encrypted transports (client/test/puzzle_play_test.dart,
// play_wiring_test.dart).
//
// WHAT CHANGED FROM THE OLD SCREEN: it sent its own `{kind: piecePuzzle, ...}` body on every placement, merged whatever
// arrived into its own board, and drew its own "stepped out of range" view. Now the dealing device (the grown-up's,
// Side.b, which also places first) is the one board that counts: the other device ASKS to place a piece, the dealer
// checks it is that seat's turn and that the piece belongs in that spot, applies it and answers with the whole
// board. A wrong spot is refused where it is dropped (never sent, never recorded), so nothing about a wrong try
// ever exists on either device. The asking device's piece appears when the answer arrives.
//
// P2 (MASTERFILE section 2.1): nothing here is a score, a streak or a tally. The wire carries which pieces are placed
// and whose turn it is; "solved" is the one fact the other screen needs to show "Good job".
import 'live_games.dart' show Side;
import 'game_logic.dart' show localPlayMinAge;
import 'play_game.dart';
import 'together_puzzle.dart';

Side? _sideOf(Object? s) => s == 'a' ? Side.a : s == 'b' ? Side.b : null;
String _seat(Side s) => s == Side.a ? 'a' : 'b';

class PuzzlePlayGame extends PlayGame {
  PuzzlePlayGame(super.ctx, {this.puzzleId = 'farmyard'});

  final String puzzleId;
  TogetherPuzzleState? state;

  /// This device asked the dealer to place a piece and is waiting for the answer.
  bool awaiting = false;

  Side get mySide => _sideOf(ctx.localSeatId) ?? Side.a;

  @override
  bool get started => state != null;

  @override
  bool get finished => state?.solved ?? false;

  /// The dealer opens the puzzle (idempotent). A guest never does: it is given the board.
  void begin() {
    if (!ctx.isAuthority || state != null) return;
    state = newPuzzle(puzzleId);
    notifyListeners();
    link?.broadcastState();
  }

  bool get myTurn => state != null && !finished && state!.mover == mySide && !awaiting;

  /// A piece dropped in a spot on THIS device. A wrong spot or a turn that is not ours does nothing and sends nothing.
  void place(String pieceId, String slotId) {
    final TogetherPuzzleState? s = state;
    if (s == null || finished || s.mover != mySide || awaiting) return;
    final def = puzzleFor(s.puzzleId);
    final piece = def == null ? null : pieceFor(def, pieceId);
    if (piece == null || piece.correctSlotId != slotId || s.placedPieces.contains(pieceId)) return;
    if (ctx.isAuthority) {
      final PlaceResult r = placePiece(s, mySide, pieceId, slotId);
      if (!r.accepted) return;
      state = r.state;
      notifyListeners();
      link?.broadcastState();
    } else {
      awaiting = true;
      notifyListeners();
      link?.sendMove(<String, dynamic>{'piece': pieceId, 'slot': slotId});
    }
  }

  @override
  PlayMoveOutcome onMove(String senderSeat, Map<String, dynamic> payload) {
    if (!ctx.isAuthority) return PlayMoveOutcome.ignored;
    final Side? side = _sideOf(senderSeat);
    final Object? piece = payload['piece'], slot = payload['slot'];
    final TogetherPuzzleState? s = state;
    // The seat is the one the transport says sent it, never anything in the body.
    if (side == null || side == mySide || s == null || piece is! String || slot is! String) return PlayMoveOutcome.refused;
    if (finished) return PlayMoveOutcome.refused;
    final PlaceResult r = placePiece(s, side, piece, slot);
    if (!r.accepted) return PlayMoveOutcome.refused;
    state = r.state;
    notifyListeners();
    return PlayMoveOutcome.applied;
  }

  Map<String, dynamic>? _view() {
    final TogetherPuzzleState? s = state;
    if (s == null) return null;
    return <String, dynamic>{
      'puzzleId': s.puzzleId,
      'mover': _seat(s.mover),
      'placedPieces': (s.placedPieces.toList()..sort()),
      'solved': s.solved,
    };
  }

  @override
  Map<String, dynamic>? stateFor(String seatId) => ctx.isAuthority ? _view() : null;

  @override
  Object? publicDigestInput() => _view();

  @override
  bool applyState(Map<String, dynamic> payload) {
    final Object? id = payload['puzzleId'], placedRaw = payload['placedPieces'];
    final Side? mover = _sideOf(payload['mover']);
    if (id is! String || placedRaw is! List || mover == null) return false;
    final def = puzzleFor(id);
    if (def == null) return false;
    final Set<String> placed = <String>{};
    for (final Object? p in placedRaw) {
      // Only pieces this puzzle really has; anything else makes the whole state malformed.
      if (p is! String || pieceFor(def, p) == null) return false;
      placed.add(p);
    }
    state = TogetherPuzzleState(puzzleId: id, placedPieces: placed, mover: mover);
    awaiting = false;
    notifyListeners();
    return true;
  }

  @override
  Map<String, dynamic>? snapshot() {
    final TogetherPuzzleState? s = state;
    if (!ctx.isAuthority || s == null || finished) return null;
    return <String, dynamic>{'puzzleId': s.puzzleId, 'mover': _seat(s.mover), 'placedPieces': (s.placedPieces.toList()..sort())};
  }

  @override
  bool restore(Map<String, dynamic> snapshot) {
    if (!ctx.isAuthority) return false;
    final Object? raw = snapshot['placedPieces'];
    final Object? id = snapshot['puzzleId'];
    final Side? mover = _sideOf(snapshot['mover']);
    if (id is! String || raw is! List || mover == null) return false;
    final def = puzzleFor(id);
    if (def == null) return false;
    final Set<String> placed = <String>{};
    for (final Object? p in raw) {
      if (p is! String || pieceFor(def, p) == null) return false;
      placed.add(p);
    }
    state = TogetherPuzzleState(puzzleId: id, placedPieces: placed, mover: mover);
    notifyListeners();
    return true;
  }

  @override
  void startRematch() {
    state = newPuzzle(puzzleId);
    awaiting = false;
    notifyListeners();
  }
}

/// Puzzle together's registration (play_game.dart). The age comes from the one table the hub already uses.
final PlayGameSpec puzzleSpec = PlayGameSpec(
  id: 'puzzle', title: 'Puzzle together', minAge: localPlayMinAge['puzzle']!, minSeats: 2, maxSeats: 2,
  modes: const {PlayMode.pair}, create: (ctx) => PuzzlePlayGame(ctx), saveable: true,
);
