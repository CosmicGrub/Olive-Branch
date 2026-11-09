// No longer UNVERIFIED — verified by CI (client/test/play_registry_test.dart, play_session_test.dart).
// OLIVE BRANCH — the game contract for ad-hoc "Play together" games: ONE spec per game, and a headless [PlayGame]
// the shared session controller (play_session.dart) drives. A game no longer opens a socket, parses its own
// wire dialect or writes its own "stepped out of range" screen; it declares what it is, answers four questions
// (what is the state for this seat, what does this move do, what is the public view, how do I save myself) and the
// controller does the rest — envelope, order, resend, resume, rematch, calm notices, saving.
//
// Design source: docs/superpowers/research/gamesuite-multiplayer-for-play-together.md section 5.3.
//
// WHAT THE CONTRACT MAKES STRUCTURAL (the child-safety rules are not left to each screen):
//  - hiddenInfo games must declare the key names they keep to themselves ([PlayGameSpec.hiddenKeys]); the
//    controller refuses to send a state that carries one (the host never sends another seat's hand, a seed never
//    leaves the dealer), and a registry sweep test checks every registered game's redaction.
//  - no spec field may be named in live_games.dart's liveForbidden (score, streak, rank, countdown, ...), the
//    payload audit runs on send AND on receive, and a game that saves itself is refused a snapshot with an outcome.
//  - computer-controlled seats act only on the authority (the dealing device). A move that arrives from the other
//    device for a CPU seat is refused: a peer can only ever move the seat that is its own.
//  - seats are strings, not a two-value enum, so a third device (a sibling's tablet, a grown-up watching) is a
//    later addition, not a rewrite. Two devices are what ships.
//
// The existing screens keep their hub tiles and age tables (games_hub.dart, game_logic.dart localPlayMinAge);
// [playGameRegistry] is checked against that table by a test so the two cannot drift.
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'play_envelope.dart' show alwaysHiddenKeys;

enum PlayMode { pair, vsCpu, passAndPlay }

/// What the dealing device did with a move another seat asked for.
enum PlayMoveOutcome { applied, refused, ignored }

/// What a game is told about the table it is sitting at.
class PlayContext {
  PlayContext({
    required this.mode,
    required this.localSeatId,
    required this.authoritySeatId,
    required this.seatIds,
    Random? rng,
    Set<String>? cpuSeatIds,
  })  : rng = rng ?? Random(),
        cpuSeatIds = cpuSeatIds ?? const <String>{};

  final PlayMode mode;
  final String localSeatId;

  /// The seat that holds the truth (the dealer).
  final String authoritySeatId;
  final List<String> seatIds;
  final Random rng;

  /// Seats a computer plays. Only the authority ever moves for these.
  final Set<String> cpuSeatIds;

  bool get isAuthority => localSeatId == authoritySeatId;
  String get peerSeatId => seatIds.firstWhere((String s) => s != localSeatId);
}

/// The two things the controller gives a game so it can talk without knowing how.
abstract class PlayLink {
  /// Authority only: send the (redacted) state to the other device now.
  Future<void> broadcastState();

  /// Send a move to the other device. Kept and resent until it is acknowledged.
  Future<void> sendMove(Map<String, dynamic> payload);
}

abstract class PlayGame extends ChangeNotifier {
  PlayGame(this.ctx);
  final PlayContext ctx;

  /// Set by the session controller when the game is attached.
  PlayLink? link;

  /// Whether this device has a game to show (the authority has dealt, or a guest has received a state).
  bool get started;

  /// A finished game. A rematch is honoured only for a finished game.
  bool get finished;

  /// Authority only: the state for [seatId], ALREADY REDACTED for that seat. Null when there is nothing to send.
  Map<String, dynamic>? stateFor(String seatId) => null;

  /// The PUBLIC view as ints, strings, bools, lists and maps only (no floats), or null to skip desync checks.
  /// Both devices compute it after a state is applied; it must come out the same.
  Object? publicDigestInput() => null;

  /// Guest: take a state from the authority. False means it was malformed and nothing changed.
  bool applyState(Map<String, dynamic> payload) => false;

  /// A move from [senderSeat] (set by the transport, never by the message).
  PlayMoveOutcome onMove(String senderSeat, Map<String, dynamic> payload) => PlayMoveOutcome.ignored;

  /// Authority only: everything needed to carry on after the app is killed, or null when there is nothing worth
  /// saving (not started, or finished). NEVER an outcome, a result or a tally.
  Map<String, dynamic>? snapshot() => null;

  /// Authority only: rebuild from [snapshot]. False (and nothing changed) for a stale or damaged one; never throws.
  bool restore(Map<String, dynamic> snapshot) => false;

  /// Authority only: begin a fresh game after a rematch was agreed.
  void startRematch() {}
}

typedef PlayGameFactory = PlayGame Function(PlayContext ctx);

/// One const per game. The hub, the age gate and the checks are driven from this.
class PlayGameSpec {
  const PlayGameSpec({
    required this.id,
    required this.title,
    required this.minAge,
    required this.minSeats,
    required this.maxSeats,
    required this.modes,
    required this.create,
    this.hiddenInfo = false,
    this.hiddenKeys = const <String>[],
    this.authorityModel = true,
    this.competitive = false,
    this.protocolVersion = 1,
    this.saveable = false,
  });

  /// The wire game id: lowercase letters, digits and underscore, up to 24.
  final String id;
  final String title;
  final int minAge;
  final int minSeats;
  final int maxSeats;
  final Set<PlayMode> modes;
  final PlayGameFactory create;

  /// The game keeps something from the other device (a hand, a deck). Then [hiddenKeys] must name it.
  final bool hiddenInfo;

  /// Key names that may never appear in anything sent across (in addition to [alwaysHiddenKeys]).
  final List<String> hiddenKeys;

  /// True: one device validates every move and answers with the state (Connect 4, Uno). False: both devices
  /// apply each other's moves in order (War), and a gap is repaired by resending, not by a state.
  final bool authorityModel;

  /// A game with a winner. It must have a handicap path (MASTERFILE section 9.2); reflex games are refused outright.
  final bool competitive;
  final int protocolVersion;

  /// The authority can save and restore this game ([PlayGame.snapshot]).
  final bool saveable;

  /// Every key that must never be sent across for this game.
  List<String> get allHiddenKeys => hiddenInfo ? <String>[...alwaysHiddenKeys, ...hiddenKeys] : const <String>[];
}

final RegExp _gameIdRe = RegExp(r'^[a-z0-9_]{1,24}$');

/// The registry the hub and the checks read. Games register themselves in [playGameRegistry].
class PlayRegistry {
  PlayRegistry();
  final Map<String, PlayGameSpec> _specs = <String, PlayGameSpec>{};

  /// Problems with a spec, in plain words, empty when it is fine. The registration refuses a spec that has any.
  static List<String> validate(PlayGameSpec s, Iterable<String> forbidden) {
    final List<String> out = <String>[];
    if (!_gameIdRe.hasMatch(s.id)) out.add('id "${s.id}" is not a valid wire game id');
    if (s.minSeats < 2 || s.maxSeats < s.minSeats) out.add('seat range ${s.minSeats}-${s.maxSeats} is not valid');
    if (s.minAge < 2) out.add('minAge ${s.minAge} is below 2');
    if (s.modes.isEmpty) out.add('no play mode');
    if (s.hiddenInfo && s.hiddenKeys.isEmpty) out.add('a hiddenInfo game must name its hiddenKeys');
    if (!s.hiddenInfo && s.hiddenKeys.isNotEmpty) out.add('hiddenKeys given for a game that is not hiddenInfo');
    final Set<String> bad = forbidden.map((String f) => f.toLowerCase()).toSet();
    for (final String k in s.hiddenKeys) {
      if (bad.contains(k.toLowerCase())) out.add('hidden key "$k" is a forbidden child-facing word');
    }
    for (final String f in <String>[s.id, s.title]) {
      if (bad.contains(f.toLowerCase())) out.add('"$f" is a forbidden child-facing word');
    }
    if (s.saveable && !s.modes.contains(PlayMode.pair)) out.add('only a two-device game is saved');
    return out;
  }

  void register(PlayGameSpec spec, {required Iterable<String> forbidden}) {
    final List<String> problems = validate(spec, forbidden);
    if (problems.isNotEmpty) throw ArgumentError('play game "${spec.id}" refused: ${problems.join('; ')}');
    if (_specs.containsKey(spec.id)) throw ArgumentError('play game "${spec.id}" is already registered');
    _specs[spec.id] = spec;
  }

  PlayGameSpec? byId(String id) => _specs[id];
  List<PlayGameSpec> get all => List<PlayGameSpec>.unmodifiable(_specs.values);
}
