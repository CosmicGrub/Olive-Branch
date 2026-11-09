// No longer UNVERIFIED — verified by CI (client/test/connect4_play_test.dart, a two-device test over the in-memory transport).
// OLIVE BRANCH — Connect 4 for two devices, as a [PlayGame] (play_game.dart). The board, the rules and the bot stay in
// connect4_engine.dart / connect4_bot.dart; this file is only the two-device conversation.
//
// WHAT CHANGED FROM THE OLD LOCKSTEP (the report's desync defect): each device used to apply its own move to its own
// board BEFORE the send was known to have arrived, then apply the other device's move to whichever side it
// believed was to move. A move that never arrived (the other device was away, or the POST was lost) left the two boards
// different forever, and nothing noticed. Now the dealing device (the authority, Side.b, which also moves first) is the
// only board that counts: the other device ASKS for a column, the authority checks it is that seat's turn and the
// column is open, applies it, and answers with the whole board. The asking device changes its screen only when
// that answer arrives. A refused or lost ask costs nothing but a moment, and the board is never wrong.
//
// P2 (MASTERFILE section 2.1): nothing here is a score, a streak or a tally. The wire carries the board, whose turn
// it is, and whether the game is over and who completed four, because the other screen has to show "Good game."
// The save (below) is refused any outcome: a finished game is cleared, not kept.
import 'live_games.dart' show Side;
import 'connect4_engine.dart';
import 'game_logic.dart' show localPlayMinAge;
import 'play_game.dart';

Side? _sideOf(Object? s) => s == 'a' ? Side.a : s == 'b' ? Side.b : null;
String _seat(Side s) => s == Side.a ? 'a' : 'b';
Side _other(Side s) => s == Side.a ? Side.b : Side.a;

List<String> _encodeColumns(Connect4Board b) => [for (final c in b.columns) c.map(_seat).join()];

Connect4Board? _decodeColumns(Object? raw) {
  if (raw is! List || raw.length != connect4Cols) return null;
  final cols = <List<Side>>[];
  for (final c in raw) {
    if (c is! String || c.length > connect4Rows) return null;
    final col = <Side>[];
    for (final ch in c.split('')) {
      final s = _sideOf(ch);
      if (s == null) return null;
      col.add(s);
    }
    cols.add(col);
  }
  return Connect4Board(columns: cols);
}

class Connect4PlayGame extends PlayGame {
  Connect4PlayGame(super.ctx);

  Connect4Board board = Connect4Board.empty();
  Side toMove = Side.b;
  Connect4Outcome outcome = Connect4Outcome.none;
  Side? winner;

  /// The asking device has sent a column and is waiting for the board to come back.
  bool awaiting = false;
  Side _firstMover = Side.b;

  Side get mySide => _sideOf(ctx.localSeatId)!;

  /// An empty board is the same on both devices with no message at all, so there is always a game to show.
  @override
  bool get started => true;
  @override
  bool get finished => outcome != Connect4Outcome.none;

  /// Whether a tap on a column does anything right now.
  bool get canPlay => !finished && !awaiting && toMove == mySide;

  /// The local player taps column [col]. The authority plays it; the other device asks the authority.
  void tapColumn(int col) {
    if (!canPlay || !isLegalMove(board, col)) return;
    if (ctx.isAuthority) {
      _apply(col, mySide);
      link?.broadcastState();
    } else {
      awaiting = true;
      notifyListeners();
      link?.sendMove(<String, dynamic>{'column': col});
    }
  }

  bool _apply(int col, Side side) {
    final r = applyMove(board, col, side);
    if (!r.applied) return false;
    board = r.board;
    outcome = r.outcome;
    winner = r.winner;
    toMove = _other(side);
    notifyListeners();
    return true;
  }

  @override
  PlayMoveOutcome onMove(String senderSeat, Map<String, dynamic> payload) {
    if (!ctx.isAuthority) return PlayMoveOutcome.ignored;
    final side = _sideOf(senderSeat);
    final col = payload['column'];
    // The seat is the one the transport says sent it, never anything in the body; a column that is not a number is refused.
    if (side == null || col is! int || side == mySide) return PlayMoveOutcome.refused;
    if (finished || toMove != side) return PlayMoveOutcome.refused;
    return _apply(col, side) ? PlayMoveOutcome.applied : PlayMoveOutcome.refused;
  }

  Map<String, dynamic> _publicView() => <String, dynamic>{
        'columns': _encodeColumns(board),
        'toMove': _seat(toMove),
        'outcome': outcome.name,
        'winner': winner == null ? null : _seat(winner!),
      };

  @override
  Map<String, dynamic>? stateFor(String seatId) => ctx.isAuthority ? _publicView() : null;

  @override
  Object? publicDigestInput() => _publicView();

  @override
  bool applyState(Map<String, dynamic> payload) {
    final b = _decodeColumns(payload['columns']);
    final tm = _sideOf(payload['toMove']);
    final oc = Connect4Outcome.values.where((o) => o.name == payload['outcome']).firstOrNull;
    final w = payload['winner'];
    if (b == null || tm == null || oc == null || (w != null && _sideOf(w) == null)) return false;
    board = b;
    toMove = tm;
    outcome = oc;
    winner = w == null ? null : _sideOf(w);
    awaiting = false;
    notifyListeners();
    return true;
  }

  @override
  Map<String, dynamic>? snapshot() {
    if (!ctx.isAuthority || finished) return null;
    return <String, dynamic>{'columns': _encodeColumns(board), 'toMove': _seat(toMove), 'first': _seat(_firstMover)};
  }

  @override
  bool restore(Map<String, dynamic> snapshot) {
    final b = _decodeColumns(snapshot['columns']);
    final tm = _sideOf(snapshot['toMove']);
    final first = _sideOf(snapshot['first']);
    if (b == null || tm == null || first == null) return false;
    // A saved game must be one still in progress: nobody has four and the board is not full.
    if (connect4Winner(b) != null || b.isFull) return false;
    // Whose turn it is follows from how many discs there are and who opened.
    final expected = b.discCount.isEven ? first : _other(first);
    if (expected != tm) return false;
    board = b;
    toMove = tm;
    _firstMover = first;
    outcome = Connect4Outcome.none;
    winner = null;
    awaiting = false;
    notifyListeners();
    return true;
  }

  @override
  void startRematch() {
    _firstMover = _other(_firstMover); // the opening seat alternates, so neither always starts
    board = Connect4Board.empty();
    toMove = _firstMover;
    outcome = Connect4Outcome.none;
    winner = null;
    awaiting = false;
    notifyListeners();
  }
}

final PlayGameSpec connect4Spec = PlayGameSpec(
  id: 'connect4', title: 'Connect 4', minAge: localPlayMinAge['connect4']!, minSeats: 2, maxSeats: 2,
  modes: const {PlayMode.pair, PlayMode.vsCpu}, create: (ctx) => Connect4PlayGame(ctx), saveable: true,
);
