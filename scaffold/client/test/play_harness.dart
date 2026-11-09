// OLIVE BRANCH — test harness: two devices at one table over the in-memory transport.
// Device 'a' is the guest (Ivy's side), device 'b' is the dealer / authority (Dad's side), exactly as on the real pair.
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/play_game.dart';
import 'package:olive_client/play_loopback.dart';
import 'package:olive_client/play_save.dart';
import 'package:olive_client/play_session.dart';

class TwoDevices<G extends PlayGame> {
  TwoDevices(this.spec, {PlaySaveStore? storeForDealer, Duration? quietEndAfter, int seed = 7, List<int>? dealerSid, Timer Function(Duration, void Function())? timerFactory}) {
    final (ta, tb) = LoopbackPlayTransport.pair();
    guestT = ta;
    dealerT = tb;
    guestGame = spec.create(PlayContext(
      mode: PlayMode.pair, localSeatId: 'a', authoritySeatId: 'b', seatIds: const ['a', 'b'], rng: Random(seed + 1))) as G;
    dealerGame = spec.create(PlayContext(
      mode: PlayMode.pair, localSeatId: 'b', authoritySeatId: 'b', seatIds: const ['a', 'b'], rng: Random(seed))) as G;
    guest = PlaySessionController(spec: spec, game: guestGame, transport: guestT, quietEndAfter: quietEndAfter, timerFactory: timerFactory);
    dealer = PlaySessionController(
        spec: spec, game: dealerGame, transport: dealerT, store: storeForDealer, quietEndAfter: quietEndAfter, timerFactory: timerFactory,
        sidBytes: () => dealerSid ?? const [1, 2, 3, 4, 5, 6, 7, 8]);
  }

  final PlayGameSpec spec;
  late final LoopbackPlayTransport guestT, dealerT;
  late final G guestGame, dealerGame;
  late final PlaySessionController guest, dealer;

  /// Dealer first (so it is listening), then the guest, who says hello.
  Future<void> start() async {
    dealer.start();
    guest.start();
    await pumpEventQueue();
  }

  /// Every envelope either side handed over, decoded.
  List<Map<String, dynamic>> get allSent => [
        for (final s in [...guestT.sent, ...dealerT.sent]) jsonDecode(s) as Map<String, dynamic>,
      ];

  void dispose() {
    guest.dispose();
    dealer.dispose();
  }
}

/// Every key in [x] at any depth.
Set<String> keysOf(Object? x) {
  final out = <String>{};
  void walk(Object? y) {
    if (y is Map) {
      for (final e in y.entries) {
        out.add(e.key.toString());
        walk(e.value);
      }
    } else if (y is List) {
      y.forEach(walk);
    }
  }

  walk(x);
  return out;
}

/// A timer a test fires by hand, so "a long quiet" takes no real time.
class ManualTimer implements Timer {
  ManualTimer(this.duration, this._cb);
  final Duration duration;
  final void Function() _cb;
  bool _active = true;
  void fire() {
    if (!_active) return;
    _active = false;
    _cb();
  }

  @override
  void cancel() => _active = false;
  @override
  bool get isActive => _active;
  @override
  int get tick => 0;
}
