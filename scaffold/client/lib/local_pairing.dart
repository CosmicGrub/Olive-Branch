// OLIVE BRANCH — local pairing, the shared foundation under every ad-hoc
// local-play activity. UNVERIFIED by tools/verify.sh's own automated
// pipeline specifically (it has no Flutter toolchain to compile Dart at
// all) — that is a distinct claim from the real hardware verification
// below, not a contradiction of it. VERIFIED on real hardware (2026-08-30): the real
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
import 'dart:io' show InternetAddress;
import 'package:flutter/foundation.dart';
import 'device_keys.dart';
import 'live_games.dart' show Side;
import 'local_discovery.dart';
import 'local_session.dart';
import 'play_admission.dart';
import 'play_credentials.dart';
import 'play_lifecycle.dart';

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
  /// By default every session is ADMITTED (play_admission.dart): the credentials are read from the sealed pairing
  /// records ([credentials], default [PlayCredentialsSource.current]), the server answers only paired, authenticated
  /// peers, every turn is encrypted, a nearby lobby that is not a pinned peer is ignored, and a device that was never
  /// paired cannot play (the phase goes to [PairingPhase.error] with a calm line and nothing is opened).
  ///
  /// Passing [admission] + [ownKey] + [peerKey]/[peerKeys] uses those instead (tests). [open] is the one way to the
  /// old open behaviour (a plain POST from anyone on the network): for single-device previews and the legacy
  /// dev entry points only; no shipped screen passes it.
  LocalPairingController({
    required this.role,
    required this.displayName,
    PlayAdmission? admission,
    DeviceKey? ownKey,
    Uint8List? peerKey,
    List<Uint8List>? peerKeys,
    this.credentials,
    this.open = false,
    this.network,
  }) {
    _admission = admission;
    _ownKey = ownKey;
    _peerKeys = peerKeys ?? (peerKey == null ? null : <Uint8List>[peerKey]);
  }

  /// Where credentials come from when none were passed in. Null means [PlayCredentialsSource.current].
  final PlayCredentialsSource? credentials;

  /// True only for the legacy open mode described above.
  final bool open;

  /// Tests only: replace the parts of the real network this controller would otherwise use.
  final PlayNetworkSeams? network;

  PlayAdmission? _admission;
  DeviceKey? _ownKey;
  List<Uint8List>? _peerKeys;

  /// The admission in force (null only in the legacy open mode, or before [start] resolved it).
  PlayAdmission? get admission => _admission;
  PlaySession? _session;
  PlayServerGuard? _guard;
  bool _helloing = false;

  /// The grown-up's confirmation card is waiting for an answer (grown-up's device only).
  bool get awaitingGrownUp => _admission?.state == PlayState.awaitingConfirm;

  /// Which seat the nearby device advertised (1 or 2), or null before it is known. The only thing a confirmation card
  /// ever calls the other device.
  int? get peerSeat => parseSeat(_lastPeerSeatText);
  String? _lastPeerSeatText;

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

  PeerDiscovery? _discovery;
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
    if (_admission == null && !open) {
      final PlayCredentials? cred =
          await (credentials ?? PlayCredentialsSource.current).load(adult: role != 'ivy');
      if (_disposed) return;
      if (cred == null) {
        // Never paired: there is nobody this device may play with, so nothing is opened and nothing is advertised.
        _phase = PairingPhase.error;
        _errorMessage = unpairedPlayLine(adult: role != 'ivy');
        _notify();
        return;
      }
      _admission = cred.buildAdmission();
      _ownKey = cred.own;
      _peerKeys = cred.peerKeys;
    }
    final address = network?.ownAddress ?? await ownLocalIPv4();
    if (address == null) {
      _phase = PairingPhase.error;
      // Honest, calm, no banned phrase — the same discipline
      // call_screen.dart's own _honestErrorMessage holds itself to.
      _errorMessage = "Can't find a local network to play on right now.";
      _notify();
      return;
    }
    if (_disposed) return;

    final adm = _admission;
    if (adm != null) {
      await adm.openWindow();
      adm.addListener(_onAdmission);
    }
    final server = LocalSessionServer(
        onTurnReceived: (payload) => _incoming.add(payload),
        admission: adm,
        bindAddresses: network?.bindAddresses,
        allowLoopback: network?.allowLoopback ?? false);
    try {
      await server.start();
    } on LocalSessionException catch (e) {
      _phase = PairingPhase.error;
      _errorMessage = e.message;
      _notify();
      return;
    }
    if (_disposed) {
      unawaited(server.stop());
      return;
    }
    _server = server;

    final PeerDiscovery discovery = network?.discoveryFactory?.call(server.port!, adm?.lobbyToken) ??
        LocalDiscovery(role: role, displayName: displayName, servePort: server.port!, lobbyToken: adm?.lobbyToken);
    _discovery = discovery;
    // Leaving the foreground closes the lobby and the socket: nothing listens while the game is not on screen.
    if (network?.lifecycleGuard ?? true) _guard = PlayServerGuard(onLeave: _leave)..attach();
    _peerSub = discovery.peers.listen(_handlePeerFound);
    _lostSub = discovery.lost.listen(_handlePeerLost);
    await discovery.start();
  }

  /// The app left the foreground (or the game ended): stop listening, stop advertising, close the lobby.
  void _leave() {
    unawaited(_peerSub?.cancel());
    unawaited(_lostSub?.cancel());
    unawaited(_discovery?.stop());
    unawaited(_server?.stop());
    _admission?.removeListener(_onAdmission);
    _admission?.closeWindow();
    _discovery = null;
    _server = null;
    _session = null;
    _peer = null;
    _phase = PairingPhase.error;
    _errorMessage = 'Paused. Open the game again to keep playing.';
    _notify();
  }

  /// A seat label's digit, kept so the confirmation card can name the other device ("Player two") even when the
  /// grown-up's lobby hears the hello before this device has resolved the peer itself.
  void _rememberSeat(LocalPeer peer) {
    final String digit = peer.role.replaceFirst('seat', '');
    if (parseSeat(digit) != null) _lastPeerSeatText = digit;
  }

  /// The admission changed. The grown-up said yes (or the lobby let a child's device in): a peer we already said hello
  /// to is now playable. The grown-up said no: forget that peer, so the other device can try again.
  void _onAdmission() {
    final PlayAdmission? adm = _admission;
    if (_disposed || adm == null || _phase == PairingPhase.error) return;
    if (_peer != null && adm.admitted && _phase != PairingPhase.found) {
      _phase = PairingPhase.found;
    } else if (_peer != null && adm.state == PlayState.none) {
      _peer = null;
      _session = null;
      _phase = PairingPhase.searching;
    }
    _notify();
  }

  Future<void> _handlePeerFound(LocalPeer peer) async {
    _rememberSeat(peer);
    final PlayAdmission? adm = _admission;
    if (adm != null) {
      // Only a pinned, paired device may be played with. A lobby that does not answer our signed hello is a stranger.
      final key = _ownKey, pinned = _peerKeys, token = peer.token;
      if (_peer != null || _helloing || key == null || pinned == null || pinned.isEmpty || token == null) return;
      _helloing = true;
      PlaySession? s;
      try {
        // A grown-up's device is paired with several children's devices; the lobby's signed answer says which.
        for (final Uint8List k in pinned) {
          s = await PlaySession.hello(own: key, peerKey: k, lobbyToken: token, post: LocalSessionClient(peer).postHello);
          if (s != null || _disposed) break;
        }
      } finally {
        _helloing = false;
      }
      if (s == null || _disposed || _peer != null) return;
      _session = s;
      // Found for play only once the lobby on THIS device let that device in (a grown-up's device waits for its yes).
      _peer = peer;
      _phase = adm.admitted ? PairingPhase.found : PairingPhase.searching;
      _notify();
      return;
    }
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
  /// gives it — this controller has no opinion on payload contents. Returns
  /// whether the turn was actually handed to the peer (false when there is no
  /// peer right now, or the send did not get through) so a caller that keeps
  /// its own copy (play_session.dart) can resend it when the peer returns.
  /// A real, honest send failure ([LocalSessionException]) moves to
  /// [PairingPhase.error] the same way it always did in
  /// local_play_screen.dart, which takes priority over any game already in
  /// progress (unlike a transient peer-lost blip — see this file's header) —
  /// unless the caller passes [failureIsError] false, as the play envelope
  /// does: there a send that did not get through simply means the other
  /// device is away, which is a calm notice, never an error screen.
  Future<bool> sendTurn(LocalTurnPayload payload, {bool failureIsError = true}) async {
    final peer = _peer;
    if (peer == null) return false;
    try {
      await LocalSessionClient(peer, session: _session).sendTurn(payload);
      return true;
    } on LocalSessionException catch (e) {
      if (failureIsError) {
        _phase = PairingPhase.error;
        _errorMessage = e.message;
        _notify();
      }
      return false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _guard?.detach();
    _admission?.removeListener(_onAdmission);
    _admission?.closeWindow();
    unawaited(_peerSub?.cancel());
    unawaited(_lostSub?.cancel());
    unawaited(_discovery?.stop());
    unawaited(_server?.stop());
    unawaited(_incoming.close());
    super.dispose();
  }
}

/// Tests only. Lets two controllers in one process find each other over loopback: no mDNS, no LAN interface.
class PlayNetworkSeams {
  const PlayNetworkSeams({
    this.ownAddress,
    this.bindAddresses,
    this.allowLoopback = false,
    this.discoveryFactory,
    this.lifecycleGuard = true,
  });

  /// A stand-in for this device's LAN address (any non-null text skips the interface lookup).
  final String? ownAddress;
  final List<InternetAddress>? bindAddresses;
  final bool allowLoopback;

  /// False in a plain (non-widget) test, where no WidgetsBinding exists to observe.
  final bool lifecycleGuard;

  /// Makes the discovery for a server on [port] with the lobby token of the admission in force.
  final PeerDiscovery Function(int port, String? lobbyToken)? discoveryFactory;
}
