// OLIVE BRANCH — a call arrives on the child's device. MASTERFILE §5.25.2, §5.20, §7.18.
//
// ONE PLACE decides whether a ring becomes a knock on the child's screen. It is reached from three roads and
// treats them the same: a push that arrives while the app is open (push_channel.dart's foreground pointer), a ring
// the phone's own notification or full-screen intent hands over (incoming_call_channel.dart), and the caller
// hanging up first (`call_cancelled`). What it never does is tell a child anything went wrong.
//
// THE RULES (every one is a branch of [decideRing], tested one by one):
//  * A ring is a knock, not an alarm (§5.25.2): it waits ninety seconds, never escalates, and ends quietly.
//  * Only a canonical session id is believed. A ref with a slash, a space or a script in it is dropped before it
//    can reach a request path or a screen.
//  * The same ring is shown once, however many roads brought it (the push, the notification, a redelivered intent).
//  * A hang-up that arrives BEFORE its ring (pushes can overtake each other) is remembered, so the late ring is dropped.
//  * A ring older than the knock's own ninety seconds is stale and is dropped (a full-screen intent redelivered
//    after an app restart must not knock for a call that ended long ago).
//  * She is never taken off a call, and two knocks never stack.
//  * A grown-up in Guardian mode on her tablet is never covered by a knock (the kiosk rules, §5.20). Every other
//    kiosk surface lets the knock sit on top, because calling never changes the lock (kiosk_shell.dart).
//
// WHAT THE CHILD SEES: the knock screen, and nothing else. A cancelled ring simply goes away. No "missed call",
// no count, no error, no reason.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'api_client.dart' show OliveApi;
import 'call_knock.dart' show KnockEnd, knockWaitsSeconds;
import 'call_lifecycle.dart' show isCallSessionId;
import 'call_presence.dart';
import 'incoming_call_channel.dart';
import 'lock_controller.dart' show Surface;

enum RingDecision { present, invalid, cancelled, duplicate, stale, busy, grownUpIsHere }

/// Everything [decideRing] needs, as plain values, so every rule is testable without a widget.
@immutable
class RingFacts {
  const RingFacts({
    required this.ref,
    this.cancelledBefore = false,
    this.seenBefore = false,
    this.age,
    this.knockShowing = false,
    this.inCall = false,
    this.surface,
  });
  final Object? ref;
  final bool cancelledBefore;
  final bool seenBefore;

  /// How long ago the phone received the push, or null when it is happening right now.
  final Duration? age;
  final bool knockShowing;
  final bool inCall;

  /// The kiosk surface showing, or null when there is no kiosk shell.
  final Surface? surface;
}

RingDecision decideRing(RingFacts f) {
  if (!isCallSessionId(f.ref)) return RingDecision.invalid;
  if (f.cancelledBefore) return RingDecision.cancelled;
  if (f.seenBefore) return RingDecision.duplicate;
  final Duration? age = f.age;
  if (age != null && age > const Duration(seconds: knockWaitsSeconds)) return RingDecision.stale;
  if (f.inCall || f.knockShowing) return RingDecision.busy;
  if (f.surface == Surface.guardianEscalation) return RingDecision.grownUpIsHere;
  return RingDecision.present;
}

typedef KnockBuilder = Widget Function(
    String sessionId, void Function(KnockEnd end) ended, Future<void> Function() callEnded);

class IncomingCallController {
  IncomingCallController({
    required this.navigatorKey,
    required this.buildKnock,
    this.channel,
    this.apiProvider,
    this.childId,
    DateTime Function()? now,
    ValueListenable<Surface?>? surface,
    ValueListenable<int>? presence,
  })  : _now = now ?? DateTime.now,
        _surface = surface ?? KioskSurfaceSignal.current,
        _presence = presence ?? CallPresence.active;

  final GlobalKey<NavigatorState> navigatorKey;
  final KnockBuilder buildKnock;
  final IncomingCallChannel? channel;

  /// A fresh signed-in client, used only to tell the server a knock was put away ("Not now") or a call ended.
  final Future<OliveApi> Function()? apiProvider;
  final String? childId;
  final DateTime Function() _now;
  final ValueListenable<Surface?> _surface;
  final ValueListenable<int> _presence;

  static const int _memory = 32;
  final List<String> _seen = <String>[];
  final List<String> _cancelled = <String>[];
  String? _activeRef;
  Route<void>? _activeRoute;
  bool _answeredFromRing = false;
  bool _attached = false;

  /// The ring on the screen right now, if any. For tests.
  String? get activeRef => _activeRef;

  /// Starts listening to the phone's own ring surface and picks up the ring that opened the app, if one did.
  Future<void> attach() async {
    if (_attached) return;
    _attached = true;
    _presence.addListener(_onPresence);
    final IncomingCallChannel? c = channel;
    if (c == null) return;
    final IncomingRing? first = await c.attach(
      onRing: (IncomingRing r) => onRing(r.ref, postedAtMs: r.postedAtMs),
      onCancel: onCancel,
    );
    if (first != null) onRing(first.ref, postedAtMs: first.postedAtMs);
  }

  void dispose() {
    _presence.removeListener(_onPresence);
    channel?.detach();
    _attached = false;
  }

  void _note(List<String> list, String ref) {
    list.remove(ref);
    list.add(ref);
    while (list.length > _memory) {
      list.removeAt(0);
    }
  }

  /// A ring arrived (from the push or from the phone's notification). Returns what was decided, for tests.
  RingDecision onRing(Object? ref, {int? postedAtMs}) {
    final Duration? age = postedAtMs == null
        ? null
        : Duration(milliseconds: (_now().millisecondsSinceEpoch - postedAtMs).clamp(0, 1 << 40));
    final RingDecision d = decideRing(RingFacts(
      ref: ref,
      cancelledBefore: ref is String && _cancelled.contains(ref),
      seenBefore: ref is String && _seen.contains(ref),
      age: age,
      knockShowing: _activeRef != null,
      inCall: CallPresence.inCall,
      surface: _surface.value,
    ));
    if (d == RingDecision.invalid) return d;
    final String id = ref! as String;
    if (d != RingDecision.present) {
      // Put the phone's own ring away for anything that will not knock (a duplicate or a busy second ring
      // leaves the one that is showing alone).
      if (d != RingDecision.duplicate && d != RingDecision.busy) unawaited(_finish(id));
      return d;
    }
    final NavigatorState? nav = navigatorKey.currentState;
    if (nav == null) return RingDecision.busy; // no screen to knock on yet; nothing was shown or remembered
    _note(_seen, id);
    _answeredFromRing = false;
    final MaterialPageRoute<void> route = MaterialPageRoute<void>(
      builder: (BuildContext _) => buildKnock(id, (KnockEnd end) => _knockEnded(id, end), () => _callEnded(id)),
    );
    _activeRef = id;
    _activeRoute = route;
    unawaited(nav.push(route));
    unawaited(route.popped.whenComplete(() {
      if (identical(_activeRoute, route)) {
        _activeRoute = null;
        _activeRef = null;
        if (!_answeredFromRing) unawaited(_finish(id));
      }
    }));
    return d;
  }

  /// The caller hung up (or the call ended) before she answered. Quiet: the knock goes away, nothing is said.
  void onCancel(Object? ref) {
    if (!isCallSessionId(ref)) return;
    final String id = ref! as String;
    _note(_cancelled, id);
    if (_activeRef == id) {
      final Route<void>? r = _activeRoute;
      final NavigatorState? nav = navigatorKey.currentState;
      if (r != null && r.isActive && nav != null) nav.removeRoute(r);
    }
    unawaited(_finish(id));
  }

  void _knockEnded(String id, KnockEnd end) {
    if (end == KnockEnd.answered) {
      _answeredFromRing = true;
      return;
    }
    // Her "Not now" closes the call's record on the server; she is told nothing about it.
    if (end == KnockEnd.notNow) unawaited(_tellServerEnded(id));
    unawaited(_finish(id));
  }

  Future<void> _callEnded(String id) => _tellServerEnded(id);

  Future<void> _tellServerEnded(String id) async {
    final Future<OliveApi> Function()? provide = apiProvider;
    final String? child = childId;
    if (provide == null || child == null) return;
    try {
      final OliveApi api = await provide();
      try {
        await api.endCall(child, id);
      } finally {
        api.close();
      }
    } catch (e) {
      // Record-keeping only. Nothing about the call depends on this, and nothing is shown for it.
      debugPrint('[olive.call] could not record the end: ${e.runtimeType}');
    }
  }

  Future<void> _finish(String id) async => channel?.ringFinished(id);

  void _onPresence() {
    // The call this device answered from a ring is over: let the phone's lock screen have the tablet back.
    if (_presence.value == 0 && _answeredFromRing) {
      _answeredFromRing = false;
      unawaited(channel?.ringFinished());
    }
  }
}
