// OLIVE BRANCH - the handshake channel for a direct ('lan-p2p') call. MASTERFILE 5.19, 16.2 #6.
//
// Two devices set up a call by passing a few small messages (an offer, an answer, ICE candidates, "restart", the
// mode, "bye"). They go ONLY through the server's authenticated call routes (POST/GET
// /v1/children/:childId/calls/:sessionId/signal), so a call works wherever the server is reachable from both
// devices: the home Wi-Fi through `adb reverse`, a private network, or a future public https address. The server
// never sees audio or video, and it refuses anyone who is not one of the two people in THIS call.
//
// This file is engine-free and Flutter-free: the engine (lan_call_engine.dart) depends only on [CallSignaling], so
// it is tested with an in-memory pair ([MemoryCallSignaling]) and the real transport is just [ServerCallSignaling].
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, immutable, visibleForTesting;

import 'api_client.dart' show ApiException, OliveApi;
import 'call_provider.dart' show CallGrant;

/// One message from the other side.
@immutable
class CallSignal {
  const CallSignal(this.kind, this.payload, {this.seq = 0});
  final String kind; // offer | answer | ice | restart | mode | bye
  final Map<String, dynamic> payload;
  final int seq;
}

/// What the signalling channel can say besides messages.
enum CallSignalingEnd {
  /// The server says the call is over (it ended, or the other side said bye).
  closed,
  /// The server has been out of reach for longer than a network change can explain.
  lost,
}

abstract class CallSignaling {
  /// Best-effort send. Throws nothing the caller must act on: a failed send is retried by the engine's own timers.
  Future<void> send(String kind, Map<String, dynamic> payload);

  /// Messages from the other side, in order, each exactly once.
  Stream<CallSignal> get signals;

  /// Completes once, with why the channel will deliver nothing more.
  Future<CallSignalingEnd> get ended;

  Future<void> close();
}

typedef CallSignalingFactory = CallSignaling Function(CallGrant grant);

/// The real transport: long-polling the server's signalling route with a fresh signed-in client per request (a
/// session renewed in the meantime, or a network that just changed, is picked up by the next poll).
class ServerCallSignaling implements CallSignaling {
  ServerCallSignaling({
    required this.apiProvider,
    required this.childId,
    required this.sessionId,
    this.waitSeconds = 8,
    this.lostAfter = const Duration(seconds: 90),
    this.retryEvery = const Duration(milliseconds: 800),
    this.minPollGap = const Duration(milliseconds: 250),
  }) {
    unawaited(_loop());
  }

  /// A signed-in client, as in call_knock_screen.dart. Closed after every use.
  final Future<OliveApi> Function() apiProvider;
  final String childId;
  final String sessionId;
  final int waitSeconds;

  /// How long the server may stay unreachable before the channel gives up. Long enough to ride out a handover from
  /// Wi-Fi to cellular, short enough that a dead call does not hang forever.
  final Duration lostAfter;
  final Duration retryEvery;

  /// A poll that comes back empty faster than this (a server that does not hold the request open) waits out the
  /// rest of it, so a quick empty answer can never turn the loop into a busy one.
  final Duration minPollGap;

  final StreamController<CallSignal> _ctl = StreamController<CallSignal>.broadcast();
  final Completer<CallSignalingEnd> _end = Completer<CallSignalingEnd>();
  int _after = 0;
  bool _closed = false;
  Timer? _sleepTimer;
  Completer<void>? _sleeper;

  /// A wait that [close] cuts short, so ending a call never leaves a timer behind.
  Future<void> _sleep(Duration d) {
    if (_closed) return Future<void>.value();
    final Completer<void> c = Completer<void>();
    _sleeper = c;
    _sleepTimer = Timer(d, () {
      if (!c.isCompleted) c.complete();
    });
    return c.future;
  }

  @override
  Stream<CallSignal> get signals => _ctl.stream;
  @override
  Future<CallSignalingEnd> get ended => _end.future;

  /// A factory for the real grants: `ServerCallSignaling.factory(apiProvider, childId)`.
  static CallSignalingFactory factory(Future<OliveApi> Function() apiProvider, String childId) =>
      (CallGrant g) => ServerCallSignaling(apiProvider: apiProvider, childId: childId, sessionId: g.sessionId ?? '');

  Future<void> _loop() async {
    DateTime? failingSince;
    while (!_closed) {
      OliveApi? api;
      final DateTime began = DateTime.now();
      var gotAny = false;
      try {
        api = await apiProvider();
        final Map<String, dynamic> body = await api.fetchCallSignals(childId, sessionId, after: _after, waitSeconds: waitSeconds);
        failingSince = null;
        final Object? raw = body['signals'];
        if (raw is List) {
          for (final Object? m in raw) {
            if (m is! Map) continue;
            final Object? seq = m['seq'], kind = m['kind'], payload = m['payload'];
            if (seq is! int || kind is! String || payload is! Map) continue;
            if (seq > _after) _after = seq;
            gotAny = true;
            if (!_ctl.isClosed) _ctl.add(CallSignal(kind, Map<String, dynamic>.from(payload), seq: seq));
          }
        }
        if (body['closed'] == true) {
          _finish(CallSignalingEnd.closed);
          return;
        }
      } on ApiException catch (e) {
        // 404 call_not_found / 403: this call is over or was never ours. Anything else (a 5xx, a 429) is retried.
        if (e.statusCode == 404 || e.statusCode == 403 || e.statusCode == 401) {
          _finish(CallSignalingEnd.closed);
          return;
        }
        failingSince ??= DateTime.now();
      } catch (e) {
        // No route to the server: a network change, a sleeping radio. Keep trying for a while.
        failingSince ??= DateTime.now();
        debugPrint('[olive.call] signalling poll did not reach the server: ${e.runtimeType}');
      } finally {
        api?.close();
      }
      if (failingSince != null) {
        if (DateTime.now().difference(failingSince) > lostAfter) {
          _finish(CallSignalingEnd.lost);
          return;
        }
        await _sleep(retryEvery);
      } else if (!gotAny) {
        final Duration took = DateTime.now().difference(began);
        if (took < minPollGap) await _sleep(minPollGap - took);
      }
    }
  }

  void _finish(CallSignalingEnd why) {
    if (!_end.isCompleted) _end.complete(why);
    if (!_ctl.isClosed) unawaited(_ctl.close());
  }

  @override
  Future<void> send(String kind, Map<String, dynamic> payload) async {
    if (_closed) return;
    // A few quick tries: a candidate lost to a momentary network change is worth one more attempt, not a failed call.
    for (var attempt = 0; attempt < 3; attempt++) {
      OliveApi? api;
      try {
        api = await apiProvider();
        await api.postCallSignal(childId, sessionId, kind, payload);
        return;
      } on ApiException catch (e) {
        if (e.statusCode != 429 && e.statusCode < 500) return; // a refusal will not change by asking again
      } catch (_) {
        // fall through to the retry
      } finally {
        api?.close();
      }
      await _sleep(Duration(milliseconds: 300 * (attempt + 1)));
      if (_closed) return;
    }
  }

  @override
  Future<void> close() async {
    _closed = true;
    _sleepTimer?.cancel();
    final Completer<void>? s = _sleeper;
    if (s != null && !s.isCompleted) s.complete();
    _finish(CallSignalingEnd.closed);
  }
}

/// In-memory, in-process pair for tests and for the dev "simulate the other end" seam: what one side sends the
/// other receives, in order. [a] and [b] are the two ends.
class MemoryCallSignaling implements CallSignaling {
  MemoryCallSignaling._(this._outbox);
  late MemoryCallSignaling _peer;
  final List<CallSignal> _outbox;
  late final StreamController<CallSignal> _ctl = StreamController<CallSignal>.broadcast(onListen: startListening);
  final Completer<CallSignalingEnd> _end = Completer<CallSignalingEnd>();
  int _seq = 0;
  bool _closed = false;

  /// Everything this end has sent, for assertions.
  @visibleForTesting
  List<CallSignal> get sent => List<CallSignal>.unmodifiable(_outbox);

  /// When true, [send] throws away what it is given (a lost network), for tests of recovery.
  bool dropOutgoing = false;

  static (MemoryCallSignaling, MemoryCallSignaling) pair() {
    final MemoryCallSignaling a = MemoryCallSignaling._(<CallSignal>[]);
    final MemoryCallSignaling b = MemoryCallSignaling._(<CallSignal>[]);
    a._peer = b;
    b._peer = a;
    return (a, b);
  }

  @override
  Stream<CallSignal> get signals => _ctl.stream;
  @override
  Future<CallSignalingEnd> get ended => _end.future;

  /// Messages sent before the other side listened are held and delivered when it does, like the real mailbox.
  final List<CallSignal> _held = <CallSignal>[];
  bool _listening = false;

  void _deliver(CallSignal s) {
    if (_closed) return;
    if (!_listening) {
      _held.add(s);
    } else if (!_ctl.isClosed) {
      _ctl.add(s);
    }
  }

  /// Starts delivery (the engine calls this by listening); held messages flow first.
  void startListening() {
    if (_listening) return;
    _listening = true;
    for (final CallSignal s in _held) {
      if (!_ctl.isClosed) _ctl.add(s);
    }
    _held.clear();
  }

  @override
  Future<void> send(String kind, Map<String, dynamic> payload) async {
    if (_closed || dropOutgoing) return;
    final CallSignal s = CallSignal(kind, Map<String, dynamic>.from(payload), seq: ++_seq);
    _outbox.add(s);
    // microtask, like a network hop: never re-entrant into the sender's own handler
    scheduleMicrotask(() => _peer._deliver(s));
    if (kind == 'bye') scheduleMicrotask(() => _peer._finish(CallSignalingEnd.closed));
  }

  void _finish(CallSignalingEnd why) {
    if (!_end.isCompleted) _end.complete(why);
  }

  /// Test hook: the channel dies (the server says the call is over, or it is lost).
  void endWith(CallSignalingEnd why) => _finish(why);

  @override
  Future<void> close() async {
    _closed = true;
    _finish(CallSignalingEnd.closed);
    if (!_ctl.isClosed) await _ctl.close();
  }
}
