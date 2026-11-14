// OLIVE BRANCH — Twenty Questions for two devices, as a [PlayGame] (play_game.dart). The prompts and the deck stay in
// live_games.dart; this file is only the two-device conversation. UNVERIFIED on a device; the conversation runs headless
// over the in-memory and the real encrypted transports (client/test/twenty_questions_play_test.dart,
// play_wiring_test.dart).
//
// WHAT CHANGED FROM THE OLD SCREEN: it sent its own `{currentPrompt, rounds, leader}` body, accepted it from any
// POST at any time, and kept a second deck on the other device "as an accepted, minor imperfection". Now the dealing
// device (the grown-up's) draws every prompt from the one deck and is the only device that does; the other device
// is given the prompt and whose turn it is, and ASKS for the next round when it is the one leading. A message that
// is not from the leader is refused.
//
// P2 (MASTERFILE section 2.1): there is no round counter on the wire or the screen ("Round 3" is a count); the leader
// simply moves on. Nothing is scored.
import 'game_logic.dart' show localPlayMinAge;
import 'live_games.dart' show LiveKind, LiveSession, Side, nextRound, startLive;
import 'play_game.dart';

Side? _sideOf(Object? s) => s == 'a' ? Side.a : s == 'b' ? Side.b : null;
String _seat(Side s) => s == Side.a ? 'a' : 'b';

/// A prompt from the wire: plain text, bounded, no control characters.
String? cleanPrompt(Object? raw) {
  if (raw is! String || raw.isEmpty || raw.runes.length > 200) return null;
  for (final int c in raw.runes) {
    if (c < 0x20 || (c >= 0x7f && c <= 0x9f)) return null;
  }
  return raw;
}

class TwentyQuestionsPlayGame extends PlayGame {
  TwentyQuestionsPlayGame(super.ctx);

  Side get mySide => _sideOf(ctx.localSeatId) ?? Side.a;

  /// The dealer's session (deck and all). Null on the other device, which only ever holds [prompt] and [leader].
  LiveSession? _session;
  String? _prompt;
  Side _leader = Side.b;
  bool _gotState = false;

  String? get prompt => _prompt;
  Side get leader => _leader;
  bool get iAmLeader => _leader == mySide;

  @override
  bool get started => ctx.isAuthority ? _session != null : _gotState;

  @override
  bool get finished => false; // round after round: no end to be told about

  /// The dealer starts the game (the other device is given it). Idempotent.
  void begin() {
    if (!ctx.isAuthority || _session != null) return;
    final result = startLive(LiveKind.twentyQuestions, Side.b, 'now', ctx.rng);
    if (!result.ok || result.session == null) return;
    _session = result.session;
    _prompt = _session!.currentPrompt;
    _leader = _session!.leader;
    notifyListeners();
    link?.broadcastState();
  }

  /// The leader moves to the next round. The dealer draws; the other device asks the dealer to.
  void next() {
    if (!started || !iAmLeader) return;
    if (ctx.isAuthority) {
      _advance();
      link?.broadcastState();
    } else {
      link?.sendMove(<String, dynamic>{'t': 'next'});
    }
  }

  void _advance() {
    final LiveSession? s = _session;
    if (s == null) return;
    _session = nextRound(s, ctx.rng);
    _prompt = _session!.currentPrompt;
    _leader = _session!.leader;
    notifyListeners();
  }

  @override
  PlayMoveOutcome onMove(String senderSeat, Map<String, dynamic> payload) {
    if (!ctx.isAuthority) return PlayMoveOutcome.ignored;
    final Side? from = _sideOf(senderSeat);
    // The seat is the one the transport says sent it. Only the leader may move on, and only the other device asks.
    if (from == null || from == mySide || payload['t'] != 'next' || _session == null || from != _leader) {
      return PlayMoveOutcome.refused;
    }
    _advance();
    return PlayMoveOutcome.applied;
  }

  Map<String, dynamic>? _view() =>
      _session == null ? null : <String, dynamic>{'prompt': _prompt, 'leader': _seat(_leader)};

  @override
  Map<String, dynamic>? stateFor(String seatId) => ctx.isAuthority ? _view() : null;

  @override
  Object? publicDigestInput() => _view();

  @override
  bool applyState(Map<String, dynamic> payload) {
    if (ctx.isAuthority) return false;
    final Object? raw = payload['prompt'];
    final Side? leader = _sideOf(payload['leader']);
    if (leader == null || (raw != null && cleanPrompt(raw) == null)) return false;
    _prompt = raw as String?;
    _leader = leader;
    _gotState = true;
    notifyListeners();
    return true;
  }
}

/// Twenty Questions' registration (play_game.dart). The age is the live-game table's, mirrored in [localPlayMinAge].
final PlayGameSpec twentyQuestionsSpec = PlayGameSpec(
  id: 'twenty_questions', title: 'Twenty questions', minAge: localPlayMinAge['twenty_questions']!, minSeats: 2, maxSeats: 2,
  modes: const {PlayMode.pair}, create: (ctx) => TwentyQuestionsPlayGame(ctx),
);
