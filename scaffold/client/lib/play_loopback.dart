// No longer UNVERIFIED — verified by CI (client/test/play_session_test.dart and every two-device game test).
// OLIVE BRANCH — an in-memory [PlayTransport] pair, so two-device play runs in a unit test with no sockets, no mDNS
// and no real clock. Same idea as co_view_session.dart's LoopbackTransport, plus the knobs the real network has:
// the other device going away and returning, messages lost after a "successful" send, duplicated, held back
// and delivered out of order.
//
// Delivery is synchronous unless [hold] is on, so a test can reason about exactly what has arrived.
import 'dart:async';
import 'dart:convert';

import 'play_transport.dart';

class LoopbackPlayTransport implements PlayTransport {
  LoopbackPlayTransport._(this.mySeat, this.peerSeat);

  static (LoopbackPlayTransport, LoopbackPlayTransport) pair({String seatA = 'a', String seatB = 'b'}) {
    final LoopbackPlayTransport x = LoopbackPlayTransport._(seatA, seatB);
    final LoopbackPlayTransport y = LoopbackPlayTransport._(seatB, seatA);
    x._peer = y;
    y._peer = x;
    y._pump = x._pump;
    return (x, y);
  }

  @override
  final String mySeat;
  @override
  final String peerSeat;
  late LoopbackPlayTransport _peer;
  _Pump _pump = _Pump();

  final StreamController<PlayInbound> _in = StreamController<PlayInbound>.broadcast(sync: true);
  final StreamController<PeerPresence> _pres = StreamController<PeerPresence>.broadcast(sync: true);
  PeerPresence _presence = PeerPresence.present;

  /// Everything this end handed over successfully, as JSON text, in order (what the other end could have seen).
  final List<String> sent = <String>[];

  /// Sends that were refused because the link was down.
  int refused = 0;

  /// Lose the next N messages after reporting a successful send (the network ate them).
  int dropNext = 0;

  /// Deliver the next N messages twice.
  int duplicateNext = 0;

  /// While true, sends are queued and delivered only by [release].
  bool hold = false;
  final List<Map<String, dynamic>> _held = <Map<String, dynamic>>[];

  @override
  Stream<PlayInbound> get incoming => _in.stream;
  @override
  Stream<PeerPresence> get presence => _pres.stream;
  @override
  PeerPresence get currentPresence => _presence;

  /// Takes the link down or brings it back, on BOTH ends at once (the two devices lose each other together).
  void setLinked(bool up) {
    final PeerPresence next = up ? PeerPresence.present : PeerPresence.away;
    final List<LoopbackPlayTransport> changed = <LoopbackPlayTransport>[
      for (final LoopbackPlayTransport t in <LoopbackPlayTransport>[this, _peer]) if (t._presence != next) t,
    ];
    // Both ends change first, THEN each is told, so neither hears the news while the other still thinks the link is down.
    for (final LoopbackPlayTransport t in changed) {
      t._presence = next;
    }
    for (final LoopbackPlayTransport t in changed) {
      t._pres.add(next);
    }
  }

  @override
  Future<bool> send(Map<String, dynamic> wire) async {
    if (_presence == PeerPresence.away) {
      refused++;
      return false;
    }
    final Map<String, dynamic> copy = jsonDecode(jsonEncode(wire)) as Map<String, dynamic>;
    sent.add(jsonEncode(copy));
    if (dropNext > 0) {
      dropNext--;
      return true;
    }
    final int times = duplicateNext > 0 ? 2 : 1;
    if (duplicateNext > 0) duplicateNext--;
    for (int i = 0; i < times; i++) {
      if (hold) {
        _held.add(copy);
      } else {
        _pump.deliver(_peer, PlayInbound(copy, mySeat));
      }
    }
    return true;
  }

  /// Delivers everything held, optionally newest first (out of order).
  void release({bool reversed = false}) {
    final List<Map<String, dynamic>> batch = List<Map<String, dynamic>>.of(_held);
    _held.clear();
    for (final Map<String, dynamic> m in reversed ? batch.reversed : batch) {
      _pump.deliver(_peer, PlayInbound(m, mySeat));
    }
  }

  /// Injects a message into THIS end as if it came from [asSeat] (a hostile or stray device on the network).
  void inject(Object? raw, {String? asSeat}) => _pump.deliver(this, PlayInbound(raw, asSeat ?? peerSeat));

  @override
  void dispose() {
    unawaited(_in.close());
    unawaited(_pres.close());
  }
}

/// Delivers in order, one at a time, but never while a delivery is already under way: a reply sent from inside a
/// handler waits its turn, as it would on a real network, instead of re-entering the stream that is still firing.
class _Pump {
  final List<(LoopbackPlayTransport, PlayInbound)> _queue = <(LoopbackPlayTransport, PlayInbound)>[];
  bool _draining = false;

  void deliver(LoopbackPlayTransport to, PlayInbound m) {
    _queue.add((to, m));
    if (_draining) return;
    _draining = true;
    try {
      int delivered = 0;
      while (_queue.isNotEmpty) {
        // Two honest devices never talk forever; if a test ever does, say so instead of hanging.
        if (++delivered > 5000) {
          _queue.clear();
          throw StateError('message storm: more than 5000 deliveries from one send');
        }
        final (LoopbackPlayTransport target, PlayInbound msg) = _queue.removeAt(0);
        if (!target._in.isClosed) target._in.add(msg);
      }
    } finally {
      _draining = false;
    }
  }
}
