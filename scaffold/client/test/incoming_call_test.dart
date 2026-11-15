// OLIVE BRANCH — incoming_call.dart tests. MASTERFILE §5.25.2, §5.20, §7.18.
//
// The rules of a ring on a child's device, one by one: it knocks (never alarms), it is shown once however many
// roads bring it, a hang-up that beats its ring is remembered, a stale ring is dropped, a call in progress and a
// knock already showing are never covered, a grown-up in Guardian mode is never covered, a hostile ref never gets
// anywhere, and nothing the child sees ever says anything went wrong.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:olive_client/api_client.dart';
import 'package:olive_client/call_knock.dart';
import 'package:olive_client/call_presence.dart';
import 'package:olive_client/incoming_call.dart';
import 'package:olive_client/incoming_call_channel.dart';
import 'package:olive_client/lock_controller.dart' show Surface;

const _a = '3f2c1a9e-7d4b-4c1e-9a55-0b1c2d3e4f50';
const _b = '8a1d2e3f-4b5c-4d6e-8f70-1a2b3c4d5e6f';
const _child = 'c0ffee00-0000-4000-8000-000000000001';

class _Rig {
  _Rig(this.t) {
    messenger = t.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(chan, (MethodCall call) async {
      nativeCalls.add('${call.method}:${call.arguments is Map ? (call.arguments as Map)['ref'] : ''}');
      if (call.method == IncomingCallChannel.mAttach) return pending;
      return null;
    });
    controller = IncomingCallController(
      navigatorKey: nav,
      channel: IncomingCallChannel(channel: chan),
      childId: _child,
      apiProvider: () async => OliveApi('http://api.test', 'tok', client: server),
      now: () => clock,
      surface: surface,
      presence: CallPresence.active,
      buildKnock: (String ref, void Function(KnockEnd) ended, Future<void> Function() callEnded) {
        endedCallbacks[ref] = ended;
        callEndedCallbacks[ref] = callEnded;
        return Scaffold(body: Center(child: Text('knock $ref', key: const Key('theKnock'))));
      },
    );
  }

  final WidgetTester t;
  late final TestDefaultBinaryMessenger messenger;
  final MethodChannel chan = const MethodChannel('test/incoming_call');
  final GlobalKey<NavigatorState> nav = GlobalKey<NavigatorState>();
  final ValueNotifier<Surface?> surface = ValueNotifier<Surface?>(null);
  final List<String> nativeCalls = <String>[];
  final List<String> serverCalls = <String>[];
  final Map<String, void Function(KnockEnd)> endedCallbacks = <String, void Function(KnockEnd)>{};
  final Map<String, Future<void> Function()> callEndedCallbacks = <String, Future<void> Function()>{};
  Map<String, Object?>? pending;
  DateTime clock = DateTime.utc(2026, 11, 15, 12);
  late final IncomingCallController controller;
  late final MockClient server = MockClient((http.Request req) async {
    serverCalls.add('${req.method} ${req.url.path}');
    return http.Response(jsonEncode(<String, Object?>{'ended': true, 'reason': 'declined'}), 200);
  });

  Future<void> start({bool navigator = true}) async {
    await t.pumpWidget(MaterialApp(
      navigatorKey: navigator ? nav : null,
      home: const Scaffold(body: Text('home')),
    ));
  }

  Future<void> settle() => t.pumpAndSettle();
  bool get knocking => find.byKey(const Key('theKnock')).evaluate().isNotEmpty;
}

void main() {
  setUp(() {
    CallPresence.reset();
    KioskSurfaceSignal.current.value = null;
  });

  group('decideRing — every rule is one branch', () {
    RingDecision d({Object? ref = _a, bool cancelled = false, bool seen = false, Duration? age, bool knock = false,
        bool inCall = false, Surface? surface}) =>
        decideRing(RingFacts(ref: ref, cancelledBefore: cancelled, seenBefore: seen, age: age, knockShowing: knock,
            inCall: inCall, surface: surface));

    test('a fresh ring on a free child home knocks', () => expect(d(), RingDecision.present));
    test('a ref that is not a session id is invalid', () {
      for (final bad in <Object?>[null, 7, '', 'x', '../v1/me', '$_a/end', '<b>', 'a' * 4000]) {
        expect(d(ref: bad), RingDecision.invalid, reason: '$bad');
      }
    });
    test('a hang-up that came first wins', () => expect(d(cancelled: true), RingDecision.cancelled));
    test('a ring already shown is a duplicate', () => expect(d(seen: true), RingDecision.duplicate));
    test('older than the knock\'s own ninety seconds is stale; exactly at it is not', () {
      expect(d(age: const Duration(seconds: 91)), RingDecision.stale);
      expect(d(age: const Duration(seconds: 90)), RingDecision.present);
      expect(d(age: Duration.zero), RingDecision.present);
    });
    test('never over a call, never stacked on a knock', () {
      expect(d(inCall: true), RingDecision.busy);
      expect(d(knock: true), RingDecision.busy);
    });
    test('never over a grown-up in Guardian mode', () => expect(d(surface: Surface.guardianEscalation), RingDecision.grownUpIsHere));
    test('every other kiosk surface lets the knock sit on top (calling never changes the lock)', () {
      for (final s in <Surface?>[null, Surface.childHome, Surface.childSession, Surface.pinGate, Surface.lockedOut]) {
        expect(d(surface: s), RingDecision.present, reason: '$s');
      }
    });
    test('the order of the rules: invalid beats cancelled beats duplicate beats stale beats busy beats the grown-up', () {
      expect(d(ref: 'x', cancelled: true, seen: true), RingDecision.invalid);
      expect(d(cancelled: true, seen: true), RingDecision.cancelled);
      expect(d(seen: true, age: const Duration(minutes: 5)), RingDecision.duplicate);
      expect(d(age: const Duration(minutes: 5), inCall: true), RingDecision.stale);
      expect(d(inCall: true, surface: Surface.guardianEscalation), RingDecision.busy);
    });
  });

  group('IncomingCallController — a ring on a real navigator', () {
    testWidgets('a ring knocks, once; the same ring again, and another ring while it shows, do not', (t) async {
      final r = _Rig(t);
      await r.start();
      expect(r.controller.onRing(_a), RingDecision.present);
      await r.settle();
      expect(r.knocking, isTrue);
      expect(find.text('knock $_a'), findsOneWidget);
      expect(r.controller.activeRef, _a);

      expect(r.controller.onRing(_a), RingDecision.duplicate);
      expect(r.controller.onRing(_b), RingDecision.busy);
      await r.settle();
      expect(find.byKey(const Key('theKnock')), findsOneWidget);
    });

    testWidgets('after the knock is over the same ring does not come back (a redelivered intent)', (t) async {
      final r = _Rig(t);
      await r.start();
      r.controller.onRing(_a);
      await r.settle();
      r.nav.currentState!.pop();
      await r.settle();
      expect(r.knocking, isFalse);
      expect(r.controller.activeRef, isNull);
      expect(r.controller.onRing(_a), RingDecision.duplicate);
      // ...but a different ring is welcome.
      expect(r.controller.onRing(_b), RingDecision.present);
      await r.settle();
      expect(find.text('knock $_b'), findsOneWidget);
    });

    testWidgets('a hinge never drops a ring: folding, unfolding and standing the phone up leave the knock where it is', (t) async {
      final r = _Rig(t);
      await r.start();
      r.controller.onRing(_a);
      await r.settle();
      for (final size in <Size>[const Size(360, 780), const Size(884, 700), const Size(720, 560), const Size(800, 600)]) {
        await t.binding.setSurfaceSize(size);
        await t.pumpAndSettle();
        expect(r.knocking, isTrue, reason: '$size');
        expect(r.controller.activeRef, _a);
      }
      await t.binding.setSurfaceSize(null);
    });

    testWidgets('a hang-up removes the knock quietly: nothing is said, the phone\'s ring is put away', (t) async {
      final r = _Rig(t);
      await r.start();
      r.controller.onRing(_a);
      await r.settle();
      r.controller.onCancel(_a);
      await r.settle();
      expect(r.knocking, isFalse);
      expect(find.text('home'), findsOneWidget);
      expect(find.textContaining('missed', findRichText: true), findsNothing);
      expect(r.nativeCalls, contains('${IncomingCallChannel.mRingFinished}:$_a'));
      // The knock is gone and so is the activity record.
      expect(r.controller.activeRef, isNull);
    });

    testWidgets('a hang-up that overtakes its ring: the late ring is dropped', (t) async {
      final r = _Rig(t);
      await r.start();
      r.controller.onCancel(_a);
      expect(r.controller.onRing(_a), RingDecision.cancelled);
      await r.settle();
      expect(r.knocking, isFalse);
    });

    testWidgets('a hang-up for some other call leaves this knock alone', (t) async {
      final r = _Rig(t);
      await r.start();
      r.controller.onRing(_a);
      await r.settle();
      r.controller.onCancel(_b);
      await r.settle();
      expect(r.knocking, isTrue);
    });

    testWidgets('a malformed hang-up does nothing', (t) async {
      final r = _Rig(t);
      await r.start();
      r.controller.onRing(_a);
      await r.settle();
      for (final bad in <Object?>[null, 3, '', '../x', '$_a/']) {
        r.controller.onCancel(bad);
      }
      await r.settle();
      expect(r.knocking, isTrue);
    });

    testWidgets('a stale ring is dropped; a fresh one from the phone is shown', (t) async {
      final r = _Rig(t);
      await r.start();
      final nowMs = r.clock.millisecondsSinceEpoch;
      expect(r.controller.onRing(_a, postedAtMs: nowMs - 120000), RingDecision.stale);
      await r.settle();
      expect(r.knocking, isFalse);
      expect(r.controller.onRing(_b, postedAtMs: nowMs - 10000), RingDecision.present);
      await r.settle();
      expect(r.knocking, isTrue);
    });

    testWidgets('a ring posted "in the future" (clock skew) is treated as fresh, not as an error', (t) async {
      final r = _Rig(t);
      await r.start();
      expect(r.controller.onRing(_a, postedAtMs: r.clock.millisecondsSinceEpoch + 5000), RingDecision.present);
    });

    testWidgets('invalid refs never knock, never reach the phone\'s ring surface', (t) async {
      final r = _Rig(t);
      await r.start();
      for (final bad in <Object?>[null, 5, '', 'nope', '../../v1/me', '$_a/end', '<script>x</script>']) {
        expect(r.controller.onRing(bad), RingDecision.invalid);
      }
      await r.settle();
      expect(r.knocking, isFalse);
      expect(r.nativeCalls.where((c) => c.startsWith(IncomingCallChannel.mRingFinished)), isEmpty);
    });

    testWidgets('never over a call in progress; it is put away on the phone and the call is untouched', (t) async {
      final r = _Rig(t);
      await r.start();
      CallPresence.enter();
      expect(r.controller.onRing(_a), RingDecision.busy);
      await r.settle();
      expect(r.knocking, isFalse);
      CallPresence.leave();
    });

    testWidgets('never over a grown-up in Guardian mode; over every other surface it is welcome', (t) async {
      final r = _Rig(t);
      await r.start();
      r.surface.value = Surface.guardianEscalation;
      expect(r.controller.onRing(_a), RingDecision.grownUpIsHere);
      await r.settle();
      expect(r.knocking, isFalse);
      expect(r.nativeCalls, contains('${IncomingCallChannel.mRingFinished}:$_a'));
      r.surface.value = Surface.pinGate;
      expect(r.controller.onRing(_b), RingDecision.present);
      await r.settle();
      expect(r.knocking, isTrue);
    });

    testWidgets('no navigator yet: nothing is shown or remembered, so the ring can still come', (t) async {
      final r = _Rig(t);
      await r.start(navigator: false);
      expect(r.controller.onRing(_a), RingDecision.busy);
      await r.start();
      expect(r.controller.onRing(_a), RingDecision.present);
    });

    testWidgets('memory is bounded: a long run of hang-ups does not grow without end', (t) async {
      final r = _Rig(t);
      await r.start();
      String id(int i) => '00000000-0000-4000-8000-${i.toString().padLeft(12, '0')}';
      for (var i = 0; i < 40; i++) {
        r.controller.onCancel(id(i));
      }
      // The oldest were forgotten (a ring for them is fresh news again); the newest are still remembered.
      expect(r.controller.onRing(id(0)), RingDecision.present);
      await r.settle();
      r.nav.currentState!.pop();
      await r.settle();
      expect(r.controller.onRing(id(39)), RingDecision.cancelled);
    });
  });

  group('a session id is the same call in any letter case', () {
    final upper = _a.toUpperCase();
    testWidgets('a re-cased copy of a ring already shown is a duplicate, and the knock is keyed on the lower-case id', (t) async {
      final r = _Rig(t);
      await r.start();
      expect(r.controller.onRing(upper), RingDecision.present);
      await r.settle();
      expect(r.controller.activeRef, _a);
      expect(r.controller.onRing(_a), RingDecision.duplicate);
      expect(r.controller.onRing(upper), RingDecision.duplicate);
      r.nav.currentState!.pop();
      await r.settle();
      expect(r.controller.onRing(upper), RingDecision.duplicate, reason: 'a forged re-cased intent after the knock ended');
    });

    testWidgets('a hang-up in one case beats a ring in the other', (t) async {
      final r = _Rig(t);
      await r.start();
      r.controller.onCancel(upper);
      expect(r.controller.onRing(_a), RingDecision.cancelled);
      r.controller.onCancel(_b);
      expect(r.controller.onRing(_b.toUpperCase()), RingDecision.cancelled);
      await r.settle();
      expect(r.knocking, isFalse);
    });

    testWidgets('a hang-up in either case takes down the knock that is showing', (t) async {
      final r = _Rig(t);
      await r.start();
      r.controller.onRing(_a);
      await r.settle();
      r.controller.onCancel(upper);
      await r.settle();
      expect(r.knocking, isFalse);
    });

    test('the channel hands Dart lower-case ids whatever case the phone sent', () {
      expect(IncomingRing.tryParse(<String, Object?>{'ref': upper, 'at': 5})!.ref, _a);
    });

    test('a hostile id is still refused in any case', () {
      for (final bad in <String>['$upper/end', ' $upper', '${upper}0', '../${upper.substring(3)}']) {
        expect(IncomingRing.tryParse(<String, Object?>{'ref': bad}), isNull, reason: bad);
      }
    });
  });

  group('how a knock ends', () {
    testWidgets('"Not now" closes the call\'s record on the server and puts the phone\'s ring away; she is told nothing', (t) async {
      final r = _Rig(t);
      await r.start();
      r.controller.onRing(_a);
      await r.settle();
      r.endedCallbacks[_a]!(KnockEnd.notNow);
      await r.settle();
      expect(r.serverCalls, <String>['POST /v1/children/$_child/calls/$_a/end']);
      expect(r.nativeCalls, contains('${IncomingCallChannel.mRingFinished}:$_a'));
    });

    testWidgets('the knock timing out does NOT tell the server she declined; it only puts the ring away', (t) async {
      final r = _Rig(t);
      await r.start();
      r.controller.onRing(_a);
      await r.settle();
      r.endedCallbacks[_a]!(KnockEnd.timedOut);
      await r.settle();
      expect(r.serverCalls, isEmpty);
      expect(r.nativeCalls, contains('${IncomingCallChannel.mRingFinished}:$_a'));
    });

    testWidgets('a join that failed puts the ring away and tells the server nothing', (t) async {
      final r = _Rig(t);
      await r.start();
      r.controller.onRing(_a);
      await r.settle();
      r.endedCallbacks[_a]!(KnockEnd.joinFailed);
      await r.settle();
      expect(r.serverCalls, isEmpty);
    });

    testWidgets('answered: the ring is kept until the call it became is over, then the lock screen is given back', (t) async {
      final r = _Rig(t);
      await r.start();
      r.controller.onRing(_a);
      await r.settle();
      r.endedCallbacks[_a]!(KnockEnd.answered);
      // The knock is replaced by the call screen, which counts itself in.
      r.nav.currentState!.pop();
      CallPresence.enter();
      await r.settle();
      expect(r.nativeCalls.where((c) => c.startsWith(IncomingCallChannel.mRingFinished)), isEmpty);
      // The call ends: the phone gets the lock screen back (a ring with no id means "whatever ring is up").
      await r.controller.attach();
      CallPresence.leave();
      await r.settle();
      expect(r.nativeCalls, contains('${IncomingCallChannel.mRingFinished}:null'));
    });

    testWidgets('the call\'s end is recorded when the call it became ends; a failing server changes nothing she sees', (t) async {
      final r = _Rig(t);
      await r.start();
      r.controller.onRing(_a);
      await r.settle();
      await r.callEndedCallbacks[_a]!();
      expect(r.serverCalls, <String>['POST /v1/children/$_child/calls/$_a/end']);

      // A server that is down: no exception escapes and nothing is shown for it.
      r.nav.currentState!.pop();
      await r.settle();
      Future<void> Function()? downEnded;
      final down = IncomingCallController(
        navigatorKey: r.nav,
        childId: _child,
        apiProvider: () async => throw Exception('offline'),
        buildKnock: (String ref, void Function(KnockEnd) e, Future<void> Function() ce) {
          downEnded = ce;
          return const Scaffold(body: Text('down knock'));
        },
      );
      expect(down.onRing(_b), RingDecision.present);
      await r.settle();
      await downEnded!();
      expect(find.text('down knock'), findsOneWidget);
    });
  });

  group('the phone\'s own ring surface (incoming_call_channel.dart)', () {
    testWidgets('the ring that opened the app is picked up once on attach', (t) async {
      final r = _Rig(t);
      await r.start();
      r.pending = <String, Object?>{'ref': _a, 'at': r.clock.millisecondsSinceEpoch - 2000};
      await r.controller.attach();
      await r.settle();
      expect(find.text('knock $_a'), findsOneWidget);
    });

    testWidgets('an intent that was already stale when the app opened is ignored', (t) async {
      final r = _Rig(t);
      await r.start();
      r.pending = <String, Object?>{'ref': _a, 'at': r.clock.millisecondsSinceEpoch - 600000};
      await r.controller.attach();
      await r.settle();
      expect(r.knocking, isFalse);
    });

    testWidgets('a ring and a hang-up from the native side while attached', (t) async {
      final r = _Rig(t);
      await r.start();
      await r.controller.attach();
      Future<void> fromNative(String method, Object? args) => r.messenger.handlePlatformMessage(
          r.chan.name, const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)), (_) {});
      await fromNative(IncomingCallChannel.eRing, <String, Object?>{'ref': _a, 'at': r.clock.millisecondsSinceEpoch});
      await r.settle();
      expect(r.knocking, isTrue);
      await fromNative(IncomingCallChannel.eCancel, <String, Object?>{'ref': _a});
      await r.settle();
      expect(r.knocking, isFalse);
    });

    testWidgets('garbage from the native side does nothing', (t) async {
      final r = _Rig(t);
      await r.start();
      await r.controller.attach();
      Future<void> fromNative(String method, Object? args) => r.messenger.handlePlatformMessage(
          r.chan.name, const StandardMethodCodec().encodeMethodCall(MethodCall(method, args)), (_) {});
      await fromNative(IncomingCallChannel.eRing, 'a string');
      await fromNative(IncomingCallChannel.eRing, <String, Object?>{'ref': '../../x', 'at': 1});
      await fromNative(IncomingCallChannel.eRing, <String, Object?>{'ref': 12, 'at': 'soon'});
      await fromNative(IncomingCallChannel.eCancel, null);
      await fromNative('unknownMethod', <String, Object?>{'ref': _a});
      await r.settle();
      expect(r.knocking, isFalse);
    });

    testWidgets('with no native side at all (Windows, tests) attach is a quiet no-op', (t) async {
      final nav = GlobalKey<NavigatorState>();
      final c = IncomingCallController(
        navigatorKey: nav,
        channel: IncomingCallChannel(channel: const MethodChannel('nobody/home')),
        buildKnock: (String ref, void Function(KnockEnd) e, Future<void> Function() ce) => const SizedBox(),
      );
      await t.pumpWidget(MaterialApp(navigatorKey: nav, home: const SizedBox()));
      // A real platform call needs the real event loop (flutter_test's fake clock never delivers the engine's reply).
      await t.runAsync(() async {
        await c.attach();
      });
      c.dispose();
    });
  });

  group('IncomingRing and AlertStatus parsing', () {
    test('a good ring', () {
      final x = IncomingRing.tryParse(<String, Object?>{'ref': _a, 'at': 1731672000000});
      expect(x!.ref, _a);
      expect(x.postedAtMs, 1731672000000);
    });
    test('a ring without a time is still a ring', () => expect(IncomingRing.tryParse(<String, Object?>{'ref': _a})!.postedAtMs, isNull));
    test('a negative, zero or non-integer time is "no time"', () {
      for (final at in <Object?>[-5, 0, 'now', 1.5, null]) {
        expect(IncomingRing.tryParse(<String, Object?>{'ref': _a, 'at': at})!.postedAtMs, isNull, reason: '$at');
      }
    });
    test('anything that is not a map with a session id is not a ring', () {
      for (final bad in <Object?>[null, 'x', 5, <Object?>[], <String, Object?>{}, <String, Object?>{'ref': 'x'}]) {
        expect(IncomingRing.tryParse(bad), isNull, reason: '$bad');
      }
    });
    test('the alert status needs two real booleans', () {
      expect(AlertStatus.tryParse(<String, Object?>{'notifications': true, 'fullScreen': false})!.fullScreen, isFalse);
      expect(AlertStatus.tryParse(<String, Object?>{'notifications': 'yes', 'fullScreen': true}), isNull);
      expect(AlertStatus.tryParse(<String, Object?>{'notifications': true}), isNull);
      expect(AlertStatus.tryParse(null), isNull);
    });
  });
}
