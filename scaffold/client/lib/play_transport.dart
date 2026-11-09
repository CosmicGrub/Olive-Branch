// No longer UNVERIFIED — verified by CI (client/test/play_session_test.dart, play_transport_test.dart).
// OLIVE BRANCH — the transport a play game talks through. A game never touches a socket: it hands the
// session controller (play_session.dart) a message, and the controller hands this interface a wire map. Two
// implementations: [LocalPairingTransport] (the real one, over local_pairing.dart's mDNS + one POST per
// message) and LoopbackPlayTransport (play_loopback.dart, an in-memory twin so two-device play is unit-testable).
//
// THE SENDER RULE (envelope rule E1): every inbound message arrives WITH the seat that sent it, supplied by this
// transport from the connection it came in on, never read from the message body. On the real transport that
// is the paired device's seat (the one other device we found); a message cannot claim to be anyone else
// because the body has no sender field at all.
import 'dart:async';

import 'live_games.dart' show Side;
import 'local_pairing.dart';

/// Whether the other device is reachable right now. [away] is a calm state, never an error.
enum PeerPresence { present, away }

class PlayInbound {
  const PlayInbound(this.raw, this.senderSeat);

  /// The decoded JSON exactly as it arrived (a Map, normally). Untrusted: parse it with parsePlayEnvelope.
  final Object? raw;

  /// Who sent it, as established by the transport.
  final String senderSeat;
}

abstract class PlayTransport {
  /// This device's seat id.
  String get mySeat;

  /// The one other device's seat id (two-device play today; seat ids are strings so a third could be added).
  String get peerSeat;

  Stream<PlayInbound> get incoming;
  Stream<PeerPresence> get presence;
  PeerPresence get currentPresence;

  /// Hands [wire] to the other device. Returns whether it was handed over; false when the other device is away or
  /// the send did not get through. Never throws, never shows anything.
  Future<bool> send(Map<String, dynamic> wire);

  void dispose();
}

/// The real transport: [LocalPairingController] under the [PlayTransport] interface.
class LocalPairingTransport implements PlayTransport {
  LocalPairingTransport(this._pairing) {
    _last = _presenceOf(_pairing);
    _pairing.addListener(_onPairing);
    _turnSub = _pairing.incomingTurns.listen((LocalTurnPayload p) => _in.add(PlayInbound(p, peerSeat)));
  }

  final LocalPairingController _pairing;
  late PeerPresence _last;
  StreamSubscription<LocalTurnPayload>? _turnSub;
  final StreamController<PlayInbound> _in = StreamController<PlayInbound>.broadcast();
  final StreamController<PeerPresence> _pres = StreamController<PeerPresence>.broadcast();

  static String seatOf(Side s) => s == Side.a ? 'a' : 'b';

  /// The controller's own side is this device's seat; the other side is the peer's.
  @override
  String get mySeat => seatOf(_pairing.mySide);
  @override
  String get peerSeat => seatOf(_pairing.mySide == Side.a ? Side.b : Side.a);

  static PeerPresence _presenceOf(LocalPairingController c) =>
      c.phase == PairingPhase.found ? PeerPresence.present : PeerPresence.away;

  void _onPairing() {
    final PeerPresence now = _presenceOf(_pairing);
    if (now == _last) return;
    _last = now;
    if (!_pres.isClosed) _pres.add(now);
  }

  @override
  Stream<PlayInbound> get incoming => _in.stream;
  @override
  Stream<PeerPresence> get presence => _pres.stream;
  @override
  PeerPresence get currentPresence => _last;

  @override
  Future<bool> send(Map<String, dynamic> wire) => _pairing.sendTurn(wire, failureIsError: false);

  @override
  void dispose() {
    _pairing.removeListener(_onPairing);
    unawaited(_turnSub?.cancel());
    unawaited(_in.close());
    unawaited(_pres.close());
  }
}
