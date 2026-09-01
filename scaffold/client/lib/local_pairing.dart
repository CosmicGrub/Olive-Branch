// OLIVE BRANCH — local pairing, the shared foundation under every ad-hoc
// local-play activity. VERIFIED on real hardware (2026-08-30): the real
// Fold5 + Galaxy Tab pair found each other and played Twenty Questions
// through this controller exactly as before the extraction (Round 1
// through Round 2, both directions). The real peer-lost/re-found recovery
// path (this file's own header, below) was also exercised for real during
// that same verification pass — not simulated — when the tablet's app
// process was killed by the OS while backgrounded and had to re-pair from
// scratch; "Dad stepped out of range..." rendered correctly and pairing
// recovered cleanly on relaunch. Network resilience & ad-hoc mode roadmap,
// Track B Option 2, foundation step for the games-expansion pass that
// follows Twenty Questions (see local_play_screen.dart's own header for
// that original real, hardware-verified proof — this file is a
// behavior-preserving extraction of its pairing half, not a rewrite of
// it).
//
// WHY THIS EXISTS: local_play_screen.dart originally owned both (a) finding
// a peer and moving a small HTTP turn back and forth, and (b) Twenty
// Questions' own game state — the two were never actually coupled, they
// just lived in one file because there was only one game. Five more games
// (War, Connect 4, Uno, a drawing game, a puzzle) means five more copies of
// the exact same mDNS-discovery-and-handoff state machine unless it moves
// out first. Everything below is copied, not reinvented, from
// local_play_screen.dart's own _start/_handlePeerFound/_handlePeerLost/
// _sendCurrentState/dispose — including the real bug fix already proven on
// hardware (2026-08-30): _handlePeerLost clears _peer, not just the phase,
// specifically so a genuine mDNS re-resolution can land again rather than
// being silently dropped forever (bonsoir/Android's own TXT-record
// resolution is confirmed, on real hardware, to sometimes report a peer as
// briefly "lost" that re-resolves within the same second).
//
// WHAT THIS FILE DELIBERATELY DOES NOT KNOW ABOUT: any specific game. There
// is no "playing" phase here — a live round is entirely the calling
// screen's own state (its own session object, its own turn payload shape).
// This matters for the exact same peer-lost/re-found real bug above: the
// original fix had to fold "was a game already under way" into the pairing
// phase itself (jumping straight to a game-specific `playing` phase on
// re-found). Splitting pairing from gameplay means each game screen now
// expresses that same resume-not-restart behavior itself, simply: keep
// showing its own game view whenever it already has local session state,
// and only defer to [PairingPhase] when it doesn't. See
// local_play_screen.dart's own updated build() for the concrete pattern —
// every new game screen should follow it. A hard transport failure
// ([PairingPhase.error], from a real thrown [LocalSessionException]) still
// takes priority over an in-progress game, same as it always did — only a
// transient peer-lost blip gets absorbed.
library;

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'live_games.dart' show Side;
import 'local_discovery.dart';
import 'local_session.dart';

// Re-exported so a game screen built on this controller never needs its own
// direct import of local_session.dart just to name the payload type it
// sends/receives through [LocalPairingController.sendTurn]/[incomingTurns].
export 'local_session.dart' show LocalTurnPayload;

/// Pairing-only phases — deliberately does not include anything
/// game-specific (no "playing"). See this file's own header for why.
enum PairingPhase { searching, found, peerLost, error }

/// Owns exactly what every ad-hoc local-play screen needs before it can
/// start moving turns: bind this device's own small HTTP server, advertise
/// and browse for the one other real device in the room, and hand back
/// whichever peer is found. A [ChangeNotifier] rather than a bespoke stream
/// bundle — every consumer here is a widget that already knows how to
/// listen to one, and it keeps [phase]/[peer]/[errorMessage] readable as
/// plain getters rather than requiring every screen to re-derive them from
/// a raw event stream.
class LocalPairingController extends ChangeNotifier {
  LocalPairingController({required this.role, required this.displayName});

  /// 'dad' or 'ivy' — the same real identity vocabulary call_screen.dart
  /// already uses.
  final String role;
  final String displayName;

  /// This device's fixed identity for the whole pairing session. Deliberately
  /// [Side] from live_games.dart, not game_logic.dart's own separately-defined
  /// `Side{a,b}` (child/parent role, used by the single-device catalogue
  /// games) — same name, same shape, different type, different meaning. Every
  /// ad-hoc local-play game built on this controller must import Side from
  /// live_games.dart for the same reason this field does.
  late final Side mySide = role == 'ivy' ? Side.a : Side.b;

  LocalDiscovery? _discovery;
  LocalSessionServer? _server;
  StreamSubscription<LocalPeer>? _peerSub;
  StreamSubscription<String>? _lostSub;
  bool _disposed = false;

  PairingPhase _phase = PairingPhase.searching;
  PairingPhase get phase => _phase;

  LocalPeer? _peer;
  LocalPeer? get peer => _peer;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  final _incoming = StreamController<LocalTurnPayload>.broadcast();

  /// Every payload this device's own small server receives, regardless of
  /// which game is live — the calling screen filters/interprets its own
  /// shape (see local_play_screen.dart's _handleIncomingTurn for the
  /// pattern: read whatever keys that one game's protocol defines).
  Stream<LocalTurnPayload> get incomingTurns => _incoming.stream;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> start() async {
    final address = await ownLocalIPv4();
    if (address == null) {
      _phase = PairingPhase.error;
      // Honest, calm, no banned phrase — the same discipline
      // call_screen.dart's own _honestErrorMessage holds itself to.
      _errorMessage = "Can't find a local network to play on right now.";
      _notify();
      return;
    }
    if (_disposed) return;

    final server = LocalSessionServer(onTurnReceived: (payload) => _incoming.add(payload));
    await server.start();
    if (_disposed) {
      unawaited(server.stop());
      return;
    }
    _server = server;

    final discovery = LocalDiscovery(role: role, displayName: displayName, servePort: server.port!);
    _discovery = discovery;
    _peerSub = discovery.peers.listen(_handlePeerFound);
    _lostSub = discovery.lost.listen(_handlePeerLost);
    await discovery.start();
  }

  void _handlePeerFound(LocalPeer peer) {
    // First real peer wins — a same-room session is exactly two people;
    // finding a second signal for the same peer (bonsoir can re-resolve)
    // must never restart a session already under way. This guard only
    // holds while _peer is actually set, though — _handlePeerLost below
    // clears it on a real loss specifically so a genuine re-resolution can
    // land here again, rather than being silently dropped forever.
    if (_peer != null) return;
    _peer = peer;
    _phase = PairingPhase.found;
    _notify();
  }

  void _handlePeerLost(String name) {
    if (_peer?.name != name) return;
    // MASTERFILE §5.23.2's own vocabulary for a call that drops applies
    // just as honestly here: state the fact, reassure, never blame either
    // device or its network.
    _errorMessage = '${_peer!.name} stepped out of range. Nothing is lost — '
        'find each other again to keep playing.';
    _phase = PairingPhase.peerLost;
    // Clear the peer, not just the phase — _handlePeerFound's own "first
    // peer wins" guard above must see this as available again, or a real
    // re-resolution (the common case — see this file's own header) can
    // never actually land.
    _peer = null;
    _notify();
  }

  /// Sends one turn to the current peer, whatever shape the calling game
  /// gives it — this controller has no opinion on payload contents. A real,
  /// honest send failure ([LocalSessionException]) moves to
  /// [PairingPhase.error] the same way it always did in
  /// local_play_screen.dart, which takes priority over any game already in
  /// progress (unlike a transient peer-lost blip — see this file's header).
  Future<void> sendTurn(LocalTurnPayload payload) async {
    final peer = _peer;
    if (peer == null) return;
    try {
      await LocalSessionClient(peer).sendTurn(payload);
    } on LocalSessionException catch (e) {
      _phase = PairingPhase.error;
      _errorMessage = e.message;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_peerSub?.cancel());
    unawaited(_lostSub?.cancel());
    unawaited(_discovery?.stop());
    unawaited(_server?.stop());
    unawaited(_incoming.close());
    super.dispose();
  }
}
