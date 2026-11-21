// OLIVE BRANCH - the foreground ring for a device with no push service. MASTERFILE 5.25.2, 7.20 (2026-11-21).
//
// A call normally reaches a closed app through a push (FCM), and that needs a Firebase project the owner has not
// provided. Until it exists, a device that is OPEN (the child's tablet in its kiosk, the grown-up's phone with
// Olive in front) asks the server every couple of seconds "is anyone calling me?" (GET .../calls/pending) and hands
// what it finds to the same one place that decides whether a ring becomes a knock: [IncomingCallController]
// (incoming_call.dart), with all its rules (once only, never over a call, never over Guardian mode, never stale).
//
// This is quiet by construction. A failed poll is silent and tried again at the next tick; nothing here is ever
// shown, counted or reported to the child. The poll also tells the server her tablet is awake, which is how a
// grown-up is told "her tablet can't be reached right now" BEFORE a call is wasted (call_lifecycle.dart).
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;

import 'api_client.dart' show OliveApi;

/// One call waiting for this side.
class PendingCall {
  const PendingCall(this.sessionId, this.from);
  final String sessionId;

  /// The caller's first name as the server resolved it, or null.
  final String? from;
}

/// Reads the server's answer defensively: a wrong-typed field is skipped, never a crash.
List<PendingCall> parsePendingCalls(Object? body) {
  if (body is! Map) return const <PendingCall>[];
  final Object? list = body['calls'];
  if (list is! List) return const <PendingCall>[];
  final List<PendingCall> out = <PendingCall>[];
  for (final Object? c in list) {
    if (c is! Map) continue;
    final Object? id = c['sessionId'], from = c['from'];
    if (id is! String) continue;
    out.add(PendingCall(id, from is String && from.trim().isNotEmpty ? from.trim() : null));
  }
  return out;
}

typedef PendingFetch = Future<Map<String, dynamic>> Function();

class PendingCallPoller {
  PendingCallPoller({
    required this.fetch,
    required this.onCall,
    this.every = const Duration(seconds: 2),
  });

  /// Real wiring is [PendingCallPoller.forApi].
  final PendingFetch fetch;
  final void Function(PendingCall call) onCall;
  final Duration every;

  Timer? _timer;
  bool _busy = false;
  bool _stopped = false;

  /// For tests: how many polls have run.
  @visibleForTesting
  int polls = 0;

  /// A poller that asks with a fresh signed-in client each time (a renewed session, a changed network).
  factory PendingCallPoller.forApi({
    required Future<OliveApi> Function() apiProvider,
    required String childId,
    required void Function(PendingCall call) onCall,
    Duration every = const Duration(seconds: 2),
  }) =>
      PendingCallPoller(
        every: every,
        onCall: onCall,
        fetch: () async {
          final OliveApi api = await apiProvider();
          try {
            return await api.fetchPendingCalls(childId);
          } finally {
            api.close();
          }
        },
      );

  void start() {
    if (_timer != null || _stopped) return;
    _timer = Timer.periodic(every, (_) => unawaited(poll()));
    unawaited(poll());
  }

  /// One poll. Never throws; never overlaps itself.
  Future<void> poll() async {
    if (_busy || _stopped) return;
    _busy = true;
    polls++;
    try {
      final List<PendingCall> calls = parsePendingCalls(await fetch());
      for (final PendingCall c in calls) {
        if (_stopped) return;
        onCall(c);
      }
    } catch (e) {
      // A sleeping radio, a restarting server, a signed-out session: not worth a word, tried again next tick.
      debugPrint('[olive.call] ring poll did not get through: ${e.runtimeType}');
    } finally {
      _busy = false;
    }
  }

  void stop() {
    _stopped = true;
    _timer?.cancel();
    _timer = null;
  }
}
