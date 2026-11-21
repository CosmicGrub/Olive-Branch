// OLIVE BRANCH — guardian_send_screens.dart tests. Run by CI; nothing here has run on a device.
// MASTERFILE §8.31, §8.2.3, §8.1. The real service over a fake server; no device, no camera.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:olive_client/guardian_home_live.dart';
import 'package:olive_client/send_time_guard.dart';
import 'package:olive_client/guardian_send_logic.dart';
import 'package:olive_client/guardian_send_screens.dart';
import 'package:olive_client/guardian_send_service.dart';
import 'package:olive_client/local_services.dart';

import 'guardian_send_fakes.dart';

final DateTime kToday = DateTime(2026, 11, 20);
final List<int> kBytes = List<int>.generate(4096, (int i) => i % 200);

Widget wrap(Widget child) => MaterialApp(home: child);

class Harness {
  Harness() {
    clock = FakeClock();
    services = LocalServices.memory(childId: 'ivy', guardianId: 'dad-a');
    service = serviceWith(api, services: services, clock: clock);
  }
  final FakeSendApi api = FakeSendApi();
  late final FakeClock clock;
  late final LocalServices services;
  late final GuardianSendService service;
  int picks = 0;

  Future<PickedVideo?> pick(VideoSource s) async {
    picks++;
    return PickedVideo(kBytes, 3000);
  }

  Widget compose({VideoPickerFn? picker, NightPickerFn? night}) => wrap(GuardianComposeScreen(
      childName: 'Ivy', service: service, pickVideo: picker ?? pick, today: kToday,
      pickNight: night ?? (BuildContext c, DateTime a, DateTime b) async => DateTime(2026, 12, 24)));

  Widget sent() => wrap(GuardianSentScreen(childName: 'Ivy', service: service, retryEvery: const Duration(hours: 1)));

  Widget day({TimePickerFn? pickTime}) => wrap(DayPartsScreen(
      childName: 'Ivy', service: service,
      pickTime: pickTime ?? (BuildContext c, TimeOfDay t) async => const TimeOfDay(hour: 19, minute: 0)));
}

/// The sealed on-device store does real asynchronous crypto, which only completes outside the fake clock, so each
/// pump is preceded by a short real wait (a bare pump leaves a save or a read half done). [until] ends the wait early
/// once a send has visibly finished; without it a fixed, short settle is used.
Future<void> settle(WidgetTester t, {bool Function()? until}) async {
  final int rounds = until == null ? 10 : 150;
  for (int i = 0; i < rounds; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
    await t.pump(const Duration(milliseconds: 50));
    if (until != null && until()) break;
  }
}

/// Runs service work (a real sealed-store read or write) outside the fake clock.
Future<T> real<T>(WidgetTester t, Future<T> Function() f) async => (await t.runAsync<T>(f)) as T;

Future<void> tapKey(WidgetTester t, String key) async {
  await t.ensureVisible(find.byKey(Key(key)));
  await t.tap(find.byKey(Key(key)));
  // A send or a retry writes and reads the sealed store several times: wait for its result line, not a fixed time.
  final bool sends = key == 'composeSend';
  await settle(t, until: sends ? () => find.byKey(const Key('composeResult')).evaluate().isNotEmpty : null);
}

Future<void> end(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump();
}

void main() {
  group('compose', () {
    testWidgets('opens with her clock, the real day-part choices, and Send off until there is a video', (t) async {
      final Harness h = Harness();
      await t.pumpWidget(h.compose());
      await settle(t);
      expect(find.byKey(const Key('composeNow')), findsOneWidget);
      expect(find.text('It is 9:14 PM for Ivy right now.'), findsOneWidget);
      for (final String k in <String>['wake', 'free', 'bedtime', 'asleep']) {
        expect(find.byKey(Key('composePart_$k')), findsOneWidget, reason: k);
      }
      expect(find.byKey(const Key('composePart_dinner')), findsNothing, reason: 'only parts she has');
      expect(find.text('Arrives at bedtime, from 7:30 PM her time.'), findsOneWidget);
      expect(t.widget<FilledButton>(find.byKey(const Key('composeSend'))).onPressed, isNull);
      expect(find.byKey(const Key('composeMode_now')), findsOneWidget, reason: 'right away is offered: the route has it');
      await end(t);
    });

    testWidgets('record, send, and the status is honest: sent, set for bedtime, and the video is not offered twice', (t) async {
      final Harness h = Harness();
      await t.pumpWidget(h.compose());
      await settle(t);
      await tapKey(t, 'composeRecord');
      expect(find.byKey(const Key('composeReady')), findsOneWidget);
      expect(t.widget<FilledButton>(find.byKey(const Key('composeSend'))).onPressed, isNotNull);
      await tapKey(t, 'composeSend');
      expect(find.text('Sent. It will arrive at bedtime.'), findsOneWidget);
      expect(find.byKey(const Key('composeReady')), findsNothing);
      expect(t.widget<FilledButton>(find.byKey(const Key('composeSend'))).onPressed, isNull);
      expect(h.api.calls.where((String c) => c == 'send').length, 1);
      expect(h.api.sends.single['daypart'], 'bedtime');
      await end(t);
    });

    testWidgets('picking the same part by name sends that part; a named night sends the date', (t) async {
      final Harness h = Harness();
      await t.pumpWidget(h.compose());
      await settle(t);
      await tapKey(t, 'composePart_wake');
      await tapKey(t, 'composeRecord');
      await tapKey(t, 'composeSend');
      expect(h.api.sends.last['daypart'], 'wake');

      await t.tap(find.text('A night I pick'));
      await settle(t);
      await tapKey(t, 'composeNight');
      expect(find.text('Thu 24 Dec'), findsOneWidget);
      expect(find.textContaining('Arrives the night of Thu 24 Dec, at 6:30 AM her time.'), findsOneWidget);
      await tapKey(t, 'composeRecord');
      await tapKey(t, 'composeSend');
      expect(h.api.sends.last['targetLocalDate'], '2026-12-24');
      expect(h.api.sends.last['daypart'], 'wake');
      await end(t);
    });

    testWidgets('a night that has already gone is blocked in words and Send stays off', (t) async {
      final Harness h = Harness();
      await t.pumpWidget(h.compose(night: (BuildContext c, DateTime a, DateTime b) async => DateTime(2026, 11, 2)));
      await settle(t);
      await t.tap(find.text('A night I pick'));
      await settle(t);
      await tapKey(t, 'composeNight');
      await tapKey(t, 'composeRecord');
      expect(find.byKey(const Key('composeBlocker')), findsOneWidget);
      expect(find.textContaining('already gone by'), findsOneWidget);
      expect(t.widget<FilledButton>(find.byKey(const Key('composeSend'))).onPressed, isNull);
      await end(t);
    });

    testWidgets('a part she cannot be reached in warns but still lets the grown-up decide', (t) async {
      final Harness h = Harness();
      await t.pumpWidget(h.compose());
      await settle(t);
      await tapKey(t, 'composePart_asleep');
      await tapKey(t, 'composeRecord');
      expect(find.byKey(const Key('composeCaution')), findsOneWidget);
      expect(find.textContaining('cannot be reached while she is asleep'), findsOneWidget);
      expect(t.widget<FilledButton>(find.byKey(const Key('composeSend'))).onPressed, isNotNull);
      await end(t);
    });

    testWidgets('Right away: no part is asked for, her clock and the guard are shown, and it goes with delivery=now', (t) async {
      final Harness h = Harness();
      await t.pumpWidget(h.compose());
      await settle(t);
      await tapKey(t, 'composeMode_now');
      expect(find.byKey(const Key('composePart_bedtime')), findsNothing, reason: 'right away has no part to pick');
      // The fake server says it is 9:14 PM, asleep, not reachable: warn in her clock, and still let her decide.
      expect(find.byKey(const Key('composeRightAwayGuard')), findsOneWidget);
      expect(find.textContaining('It is 9:14 PM for Ivy right now.'), findsNWidgets(2), reason: 'the top line and the guard');
      expect(find.byKey(const Key('composeArrival')), findsOneWidget);
      await tapKey(t, 'composeRecord');
      expect(t.widget<FilledButton>(find.byKey(const Key('composeSend'))).onPressed, isNotNull);
      await tapKey(t, 'composeSend');
      expect(find.text('Sent. It will arrive right away.'), findsOneWidget);
      expect(h.api.sends.single['delivery'], 'now');
      expect(h.api.sends.single.containsKey('targetLocalDate'), isFalse);
      await end(t);
    });

    testWidgets('Right away with her reachable shows no warning; with her day unknown (offline) shows none and still works', (t) async {
      final Harness h = Harness();
      h.api.onNow = () => <String, dynamic>{'childLocalTime': '4:10 PM', 'dayPart': null, 'reachable': true};
      await t.pumpWidget(h.compose());
      await settle(t);
      await tapKey(t, 'composeMode_now');
      expect(find.byKey(const Key('composeRightAwayGuard')), findsNothing);
      await end(t);

      final Harness off = Harness();
      off.api.onNow = () => throw StateError('offline');
      off.api.onGetDayParts = () => throw StateError('offline');
      await t.pumpWidget(off.compose());
      await settle(t);
      await tapKey(t, 'composeMode_now');
      await tapKey(t, 'composeRecord');
      expect(t.widget<FilledButton>(find.byKey(const Key('composeSend'))).onPressed, isNotNull);
      await end(t);
    });

    testWidgets('Right away against an older server says "scheduled", never "right away"', (t) async {
      final Harness h = Harness();
      h.api.echoDelivery = false;
      await t.pumpWidget(h.compose());
      await settle(t);
      await tapKey(t, 'composeMode_now');
      await tapKey(t, 'composeRecord');
      await tapKey(t, 'composeSend');
      expect(find.text('Sent. It is scheduled.'), findsOneWidget);
      await end(t);
    });

    testWidgets('a stale right-away on the sent screen says it waited too long and offers Right away again', (t) async {
      final Harness h = Harness();
      h.api.onUpload = (int n) => throw StateError('offline');
      await real(t, () => h.service.compose(bytes: kBytes, durationMs: 100, delivery: const DeliveryChoice.now()));
      h.api.onUpload = null;
      h.clock.ms += kStaleNowAfter.inMilliseconds + 5000;
      await t.pumpWidget(h.sent());
      await settle(t);
      final QueuedSend q = (await real(t, () => h.service.queued())).single;
      expect(q.phase, SendPhase.needsAttention);
      expect(t.widget<Text>(find.byKey(Key('queuedStatus_${q.id}'))).data, staleNowWords);
      await tapKey(t, 'queuedChange_${q.id}');
      expect(find.byKey(const Key('changeTo_now')), findsOneWidget);
      await tapKey(t, 'changeTo_now');
      expect(h.api.sends.single['delivery'], 'now');
      await end(t);
    });

    testWidgets('no signal: the video is saved on this phone, the words say so, and it waits under What you have sent', (t) async {
      final Harness h = Harness();
      h.api.onUpload = (int n) => throw StateError('socket');
      await t.pumpWidget(h.compose());
      await settle(t);
      await tapKey(t, 'composeRecord');
      await tapKey(t, 'composeSend');
      expect(find.textContaining('saved on this phone and will go by itself'), findsOneWidget);
      expect(find.textContaining('socket'), findsNothing, reason: 'no raw error text');
      expect(find.textContaining('StateError'), findsNothing);
      expect(find.byKey(const Key('composeWaitingNote')), findsOneWidget);
      expect((await real(t, () => h.service.queued())).length, 1);

      await tapKey(t, 'composeOpenSentLink');
      expect(find.textContaining('Waiting on this phone'), findsOneWidget);
      expect(find.textContaining('Video message · arrives at bedtime'), findsOneWidget);
      await end(t);
    });

    testWidgets('the server refuses (no bedtime set): needs-attention words, the recording kept, a way to fix it', (t) async {
      final Harness h = Harness();
      h.api.onSend = (int n, Map<String, Object?> b) => throw answer(400, 'daypart_undefined');
      await t.pumpWidget(h.compose());
      await settle(t);
      await tapKey(t, 'composeRecord');
      await tapKey(t, 'composeSend');
      expect(find.textContaining('Set her day first'), findsOneWidget);
      expect(find.textContaining('daypart_undefined'), findsNothing);
      expect((await real(t, () => h.service.queued())).single.phase, SendPhase.needsAttention);
      await end(t);
    });

    testWidgets('a picker that fails, returns nothing, or returns too much never crashes and says what to do', (t) async {
      final Harness h = Harness();
      await t.pumpWidget(h.compose(picker: (VideoSource s) async => throw StateError('camera_access_denied')));
      await settle(t);
      await tapKey(t, 'composeRecord');
      expect(find.byKey(const Key('composePickProblem')), findsOneWidget);
      expect(find.textContaining('camera_access_denied'), findsNothing);
      expect(find.textContaining('could not open the camera'), findsOneWidget);

      await t.pumpWidget(h.compose(picker: (VideoSource s) async => null));
      await settle(t);
      await tapKey(t, 'composeChoose');
      expect(find.byKey(const Key('composeReady')), findsNothing);
      expect(find.byKey(const Key('composePickProblem')), findsNothing);

      await t.pumpWidget(h.compose(picker: (VideoSource s) async => PickedVideo(List<int>.filled(kMaxHeldBytes + 1, 1), 5)));
      await settle(t);
      await tapKey(t, 'composeChoose');
      expect(find.textContaining('too large to send'), findsOneWidget);
      expect(find.byKey(const Key('composeReady')), findsNothing);

      await t.pumpWidget(h.compose(picker: (VideoSource s) async => const PickedVideo(<int>[], 5)));
      await settle(t);
      await tapKey(t, 'composeRecord');
      expect(find.textContaining('was empty'), findsOneWidget);
      await end(t);
    });

    testWidgets('her day could not be loaded: only Bedtime is offered and the screen says why, still usable', (t) async {
      final Harness h = Harness();
      h.api.onGetDayParts = () => throw StateError('offline');
      await t.pumpWidget(h.compose());
      await settle(t);
      expect(find.byKey(const Key('composeNoParts')), findsOneWidget);
      expect(find.byKey(const Key('composePart_bedtime')), findsOneWidget);
      expect(find.byKey(const Key('composePart_wake')), findsNothing);
      await tapKey(t, 'composeRecord');
      expect(t.widget<FilledButton>(find.byKey(const Key('composeSend'))).onPressed, isNotNull);
      await end(t);
    });

    testWidgets('a day with no parts says so and points to her day', (t) async {
      final Harness h = Harness();
      h.api.dayPartsBody = <String, dynamic>{'dayParts': <Object?>[], 'hasBedtime': false};
      await t.pumpWidget(h.compose());
      await settle(t);
      expect(find.byKey(const Key('composeEmptyDay')), findsOneWidget);
      await end(t);
    });

    testWidgets('tapping Send twice quickly sends once', (t) async {
      final Harness h = Harness();
      final Completer<void> gate = Completer<void>();
      h.api.onUpload = (int n) => gate.future;
      await t.pumpWidget(h.compose());
      await settle(t);
      await tapKey(t, 'composeRecord');
      await t.tap(find.byKey(const Key('composeSend')));
      await t.pump();
      await t.tap(find.byKey(const Key('composeSend')), warnIfMissed: false);
      await t.pump();
      gate.complete();
      await settle(t);
      expect(h.api.sends.length, 1);
      expect(h.api.uploads.length, 1);
      await end(t);
    });

    testWidgets('nothing on the screen is a count, streak or score, and no zone or UTC is shown (§8.2.3)', (t) async {
      final Harness h = Harness();
      await t.pumpWidget(h.compose());
      await settle(t);
      await tapKey(t, 'composeRecord');
      await tapKey(t, 'composeSend');
      final String text = t.widgetList<Text>(find.byType(Text)).map((Text w) => w.data ?? '').join(' ').toLowerCase();
      for (final String bad in <String>['streak', 'score', 'points', 'utc', 'gmt', 'est', ' +1']) {
        expect(text, isNot(contains(bad)), reason: bad);
      }
      await end(t);
    });

    for (final Size size in const <Size>[Size(344, 820), Size(390, 844), Size(673, 841), Size(1100, 800)]) {
      testWidgets('renders without overflow at ${size.width.toInt()} wide, at text scale 2.0 too', (t) async {
        t.view.physicalSize = size;
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        final Harness h = Harness();
        h.api.onUpload = (int n) => throw StateError('x');
        await t.pumpWidget(MediaQuery(
            data: MediaQueryData(size: size, textScaler: const TextScaler.linear(2.0)), child: h.compose()));
        await settle(t);
        await tapKey(t, 'composeRecord');
        await tapKey(t, 'composePart_asleep');
        await tapKey(t, 'composeSend');
        expect(t.takeException(), isNull);
        await tapKey(t, 'composeMode_now');
        expect(t.takeException(), isNull, reason: 'the three choices and the guard wrap, never overflow');
        await end(t);
      });
    }
  });

  group('what you have sent', () {
    testWidgets('shows the server\'s own states in plain sentences, and what each was set for', (t) async {
      final Harness h = Harness();
      h.api.onSent = () => <String, dynamic>{
            'messages': <Object?>[
              <String, Object?>{'id': 'wait-0001', 'state': 'waiting', 'sentAt': '2026-11-20T10:00:00.000Z'},
              <String, Object?>{'id': 'deli-0001', 'state': 'delivered', 'sentAt': '2026-11-19T10:00:00.000Z', 'deliveredAt': '2026-11-20T01:30:00.000Z'},
              <String, Object?>{'id': 'open-0001', 'state': 'opened', 'sentAt': '2026-11-18T10:00:00.000Z', 'receipt': <String, Object?>{'phrase': 'Watched at 7:42 PM her time — at bedtime.'}},
              <String, Object?>{'id': 'expi-0001', 'state': 'expired'},
              <String, Object?>{'id': 'revo-0001', 'state': 'revoked'},
            ],
          };
      await t.pumpWidget(h.sent());
      await settle(t);
      expect(find.byKey(const Key('sentStatus_wait-0001')), findsOneWidget);
      expect(t.widget<Text>(find.byKey(const Key('sentStatus_wait-0001'))).data, startsWith('Waiting to arrive.'));
      expect(t.widget<Text>(find.byKey(const Key('sentStatus_deli-0001'))).data, contains('She has not opened it yet.'));
      expect(t.widget<Text>(find.byKey(const Key('sentStatus_open-0001'))).data, 'Watched at 7:42 PM her time — at bedtime.');
      expect(t.widget<Text>(find.byKey(const Key('sentStatus_expi-0001'))).data, contains('did not reach her'));
      expect(t.widget<Text>(find.byKey(const Key('sentStatus_revo-0001'))).data, contains('taken back'));
      await end(t);
    });

    testWidgets('an empty list says nothing sent yet, not a blank screen', (t) async {
      final Harness h = Harness();
      await t.pumpWidget(h.sent());
      await settle(t);
      expect(find.byKey(const Key('sentEmpty')), findsOneWidget);
      await end(t);
    });

    testWidgets('server unreachable: says so, never shows a stale list as current, and still shows what waits on this phone', (t) async {
      final Harness h = Harness();
      h.api.onUpload = (int n) => throw StateError('x');
      await real(t, () => h.service.compose(bytes: kBytes, durationMs: 100, delivery: const DeliveryChoice.atDayPart('bedtime')));
      h.api.onSent = () => throw StateError('offline');
      await t.pumpWidget(h.sent());
      await settle(t);
      expect(find.byKey(const Key('sentOffline')), findsOneWidget);
      expect(find.byKey(const Key('sentEmpty')), findsNothing);
      expect(find.textContaining('Waiting on this phone'), findsOneWidget);
      await end(t);
    });

    testWidgets('a waiting message: Try again sends it once the network is back, and it leaves the list', (t) async {
      final Harness h = Harness();
      h.api.onUpload = (int n) => throw StateError('x');
      await real(t, () => h.service.compose(bytes: kBytes, durationMs: 100, delivery: const DeliveryChoice.atDayPart('bedtime')));
      await t.pumpWidget(h.sent());
      await settle(t);
      final QueuedSend q = (await real(t, () => h.service.queued())).single;
      expect(find.byKey(Key('queued_${q.id}')), findsOneWidget);
      h.api.onUpload = null;
      await tapKey(t, 'queuedRetry_${q.id}');
      expect(find.byKey(Key('queued_${q.id}')), findsNothing);
      expect(find.textContaining('Sent. It will arrive at bedtime.'), findsOneWidget);
      await end(t);
    });

    testWidgets('needs attention: the reason in words; Change when it arrives re-sends for the new part', (t) async {
      final Harness h = Harness();
      h.api.onSend = (int n, Map<String, Object?> b) =>
          b['daypart'] == 'bedtime' ? throw answer(400, 'daypart_undefined') : <String, dynamic>{'id': 'intent-00009'};
      await real(t, () => h.service.compose(bytes: kBytes, durationMs: 100, delivery: const DeliveryChoice.atDayPart('bedtime')));
      await t.pumpWidget(h.sent());
      await settle(t);
      final QueuedSend q = (await real(t, () => h.service.queued())).single;
      expect(t.widget<Text>(find.byKey(Key('queuedStatus_${q.id}'))).data, contains('Set her day first'));
      await tapKey(t, 'queuedChange_${q.id}');
      await tapKey(t, 'changeTo_free');
      expect(h.api.sends.last['daypart'], 'free');
      expect(find.byKey(Key('queued_${q.id}')), findsNothing);
      await end(t);
    });

    testWidgets('Throw away asks first; Keep it keeps, Throw it away removes only that message', (t) async {
      final Harness h = Harness();
      h.api.onUpload = (int n) => throw StateError('x');
      await real(t, () => h.service.compose(bytes: kBytes, durationMs: 100, delivery: const DeliveryChoice.atDayPart('bedtime')));
      await t.pumpWidget(h.sent());
      await settle(t);
      final QueuedSend q = (await real(t, () => h.service.queued())).single;
      await tapKey(t, 'queuedDiscard_${q.id}');
      expect(find.text('Throw this message away?'), findsOneWidget);
      await tapKey(t, 'discardNo');
      expect((await real(t, () => h.service.queued())).length, 1);
      await tapKey(t, 'queuedDiscard_${q.id}');
      await tapKey(t, 'discardYes');
      expect(await real(t, () => h.service.queued()), isEmpty);
      await end(t);
    });

    testWidgets('opening the screen retries what is due, by itself', (t) async {
      final Harness h = Harness();
      h.api.onUpload = (int n) => n == 1 ? throw StateError('x') : null;
      await real(t, () => h.service.compose(bytes: kBytes, durationMs: 100, delivery: const DeliveryChoice.atDayPart('bedtime')));
      h.clock.ms += 10 * 60 * 1000;
      await t.pumpWidget(h.sent());
      await settle(t);
      expect(await real(t, () => h.service.queued()), isEmpty);
      expect(h.api.sends.length, 1);
      await end(t);
    });

    testWidgets('no overflow at the four widths, at text scale 2.0, with a waiting message and a list', (t) async {
      for (final Size size in const <Size>[Size(344, 820), Size(390, 844), Size(673, 841), Size(1100, 800)]) {
        t.view.physicalSize = size;
        t.view.devicePixelRatio = 1;
        final Harness h = Harness();
        h.api.onUpload = (int n) => throw StateError('x');
        await real(t, () => h.service.compose(bytes: kBytes, durationMs: 100, delivery: const DeliveryChoice.atDayPart('bedtime')));
        h.api.onSent = () => <String, dynamic>{
              'messages': <Object?>[<String, Object?>{'id': 'open-0001', 'state': 'opened', 'receipt': <String, Object?>{'phrase': 'Watched at 7:42 PM her time — at bedtime.'}}],
            };
        await t.pumpWidget(MediaQuery(data: MediaQueryData(size: size, textScaler: const TextScaler.linear(2.0)), child: h.sent()));
        await settle(t);
        expect(t.takeException(), isNull, reason: '${size.width}');
        await end(t);
      }
      t.view.reset();
    });
  });

  group('her day', () {
    testWidgets('reads the schedule in adult words, with the placeholder note', (t) async {
      final Harness h = Harness();
      await t.pumpWidget(h.day());
      await settle(t);
      expect(find.byKey(const Key('dayPlaceholderNote')), findsOneWidget);
      expect(t.widget<Text>(find.byKey(const Key('dayPartText_2'))).data, 'Bedtime: 7:30 PM to 8:30 PM, every day. She can be reached.');
      expect(t.widget<Text>(find.byKey(const Key('dayPartText_3'))).data, contains('8:30 PM to 6:30 AM the next morning'));
      expect(t.widget<FilledButton>(find.byKey(const Key('daySave'))).onPressed, isNull, reason: 'nothing changed yet');
      await end(t);
    });

    testWidgets('edit a time, save: the whole schedule goes, the server\'s answer is shown, and Save is off again', (t) async {
      final Harness h = Harness();
      await t.pumpWidget(h.day());
      await settle(t);
      await tapKey(t, 'dayEdit_2');
      await tapKey(t, 'partStart'); // the injected picker answers 7:00 PM
      expect(find.text('From 7:00 PM'), findsOneWidget);
      await tapKey(t, 'partOk');
      expect(t.widget<Text>(find.byKey(const Key('dayPartText_2'))).data, startsWith('Bedtime: 7:00 PM'));
      expect(t.widget<FilledButton>(find.byKey(const Key('daySave'))).onPressed, isNotNull);
      await tapKey(t, 'daySave');
      expect(find.byKey(const Key('daySaveLine')), findsOneWidget);
      expect(find.textContaining('Saved.'), findsOneWidget);
      expect(h.api.putBodies.single.length, 4);
      expect(t.widget<FilledButton>(find.byKey(const Key('daySave'))).onPressed, isNull);
      await end(t);
    });

    testWidgets('an overlap is explained before saving, on the part, and Save stays off', (t) async {
      final Harness h = Harness();
      h.api.dayPartsBody = <String, dynamic>{
        'dayParts': <Object?>[
          <String, Object?>{'kind': 'free', 'startsLocal': '08:00', 'endsLocal': '12:00', 'daysOfWeek': <int>[0, 1, 2, 3, 4, 5, 6], 'reachable': true},
          <String, Object?>{'kind': 'bedtime', 'startsLocal': '19:30', 'endsLocal': '20:30', 'daysOfWeek': <int>[0, 1, 2, 3, 4, 5, 6], 'reachable': true},
        ],
      };
      await t.pumpWidget(h.day(pickTime: (BuildContext c, TimeOfDay x) async => const TimeOfDay(hour: 10, minute: 0)));
      await settle(t);
      await tapKey(t, 'dayAdd'); // new part defaults to Free time 8:00 AM to 3:00 PM, overlapping the existing Free time
      await tapKey(t, 'partOk');
      expect(find.byKey(const Key('dayPartProblem_2')), findsOneWidget);
      expect(find.textContaining('appears twice at overlapping times'), findsOneWidget);
      expect(t.widget<FilledButton>(find.byKey(const Key('daySave'))).onPressed, isNull);
      expect(h.api.putBodies, isEmpty);
      await end(t);
    });

    testWidgets('the edit dialog itself refuses a part that starts and ends together and says why', (t) async {
      final Harness h = Harness();
      await t.pumpWidget(h.day(pickTime: (BuildContext c, TimeOfDay x) async => const TimeOfDay(hour: 8, minute: 0)));
      await settle(t);
      await tapKey(t, 'dayEdit_1');
      await tapKey(t, 'partEnd'); // end 8:00, start already 8:00
      expect(find.byKey(const Key('partProblem')), findsOneWidget);
      expect(find.textContaining('last no time at all'), findsOneWidget);
      expect(t.widget<FilledButton>(find.byKey(const Key('partOk'))).onPressed, isNull);
      await tapKey(t, 'partCancel');
      await end(t);
    });

    testWidgets('removing every bedtime warns that messages for bedtime could not be sent; the last part cannot be removed', (t) async {
      final Harness h = Harness();
      await t.pumpWidget(h.day());
      await settle(t);
      await tapKey(t, 'dayRemove_2'); // bedtime
      expect(find.byKey(const Key('dayWarning')), findsOneWidget);
      expect(find.textContaining('no Bedtime'), findsOneWidget);
      await tapKey(t, 'dayRemove_0');
      await tapKey(t, 'dayRemove_0');
      expect(t.widget<TextButton>(find.byKey(const Key('dayRemove_0'))).onPressed, isNull, reason: 'the last part stays');
      await end(t);
    });

    testWidgets('someone else changed her day: nothing is overwritten, the new day is shown, and the words say so', (t) async {
      final Harness h = Harness();
      await t.pumpWidget(h.day());
      await settle(t);
      await tapKey(t, 'dayEdit_2');
      await tapKey(t, 'partStart');
      await tapKey(t, 'partOk');
      // Meanwhile another grown-up saves a different day on the server.
      h.api.dayPartsBody = <String, dynamic>{
        'dayParts': <Object?>[<String, Object?>{'kind': 'bedtime', 'startsLocal': '18:00', 'endsLocal': '19:00', 'daysOfWeek': <int>[0, 1, 2, 3, 4, 5, 6], 'reachable': true}],
      };
      await tapKey(t, 'daySave');
      expect(find.textContaining('Another grown-up changed her day'), findsOneWidget);
      expect(h.api.putBodies, isEmpty);
      expect(t.widget<Text>(find.byKey(const Key('dayPartText_0'))).data, startsWith('Bedtime: 6:00 PM'));
      expect(find.byKey(const Key('dayPart_1')), findsNothing);
      await end(t);
    });

    testWidgets('the server says no: the words, and the edits stay on screen', (t) async {
      final Harness h = Harness();
      h.api.onPutDayParts = (List<Map<String, Object?>> p) => throw answer(409, 'day_parts_overlap');
      await t.pumpWidget(h.day());
      await settle(t);
      await tapKey(t, 'dayEdit_2');
      await tapKey(t, 'partStart');
      await tapKey(t, 'partOk');
      await tapKey(t, 'daySave');
      expect(find.textContaining('overlap on the same day. Nothing was changed.'), findsOneWidget);
      expect(find.textContaining('day_parts_overlap'), findsNothing);
      expect(t.widget<Text>(find.byKey(const Key('dayPartText_2'))).data, startsWith('Bedtime: 7:00 PM'));
      await end(t);
    });

    testWidgets('a double-tap on Save writes once', (t) async {
      final Harness h = Harness();
      final Completer<void> gate = Completer<void>();
      h.api.onGetDayParts = () async {
        await gate.future;
        return h.api.dayPartsBody;
      };
      await t.pumpWidget(h.day());
      // The first load also waits on the gate: release it for the load, then hold it for the save.
      gate.complete();
      await settle(t);
      h.api.onGetDayParts = null;
      await tapKey(t, 'dayEdit_2');
      await tapKey(t, 'partStart');
      await tapKey(t, 'partOk');
      final Completer<void> g2 = Completer<void>();
      h.api.onGetDayParts = () async {
        await g2.future;
        return h.api.dayPartsBody;
      };
      await t.tap(find.byKey(const Key('daySave')));
      await t.pump();
      await t.tap(find.byKey(const Key('daySave')), warnIfMissed: false);
      await t.pump();
      g2.complete();
      await settle(t);
      expect(h.api.putBodies.length, 1);
      await end(t);
    });

    testWidgets('offline on open: says nothing changed, with Try again; no fake schedule is shown', (t) async {
      final Harness h = Harness();
      h.api.onGetDayParts = () => throw StateError('offline');
      await t.pumpWidget(h.day());
      await settle(t);
      expect(find.byKey(const Key('dayLoadProblem')), findsOneWidget);
      expect(find.byKey(const Key('dayPart_0')), findsNothing);
      h.api.onGetDayParts = null;
      await tapKey(t, 'dayRetry');
      expect(find.byKey(const Key('dayPart_0')), findsOneWidget);
      await end(t);
    });

    testWidgets('a part this build cannot read turns saving off and says why', (t) async {
      final Harness h = Harness();
      h.api.dayPartsBody = <String, dynamic>{
        'dayParts': <Object?>[
          <String, Object?>{'kind': 'bedtime', 'startsLocal': '19:30', 'endsLocal': '20:30', 'daysOfWeek': <int>[0, 1, 2, 3, 4, 5, 6], 'reachable': true},
          <String, Object?>{'kind': 'x', 'startsLocal': 'bad'},
        ],
      };
      await t.pumpWidget(h.day());
      await settle(t);
      expect(find.byKey(const Key('daySkipped')), findsOneWidget);
      await tapKey(t, 'dayEdit_0');
      await tapKey(t, 'partStart');
      await tapKey(t, 'partOk');
      expect(t.widget<FilledButton>(find.byKey(const Key('daySave'))).onPressed, isNull);
      await end(t);
    });

    for (final Size size in const <Size>[Size(344, 820), Size(390, 844), Size(673, 841), Size(1100, 800)]) {
      testWidgets('renders and edits without overflow at ${size.width.toInt()} wide, text scale 2.0', (t) async {
        t.view.physicalSize = size;
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        final Harness h = Harness();
        await t.pumpWidget(MediaQuery(data: MediaQueryData(size: size, textScaler: const TextScaler.linear(2.0)), child: h.day()));
        await settle(t);
        await tapKey(t, 'dayEdit_3');
        expect(t.takeException(), isNull);
        await tapKey(t, 'partCancel');
        await end(t);
      });
    }
  });

  group('wiring: the tiles open the real thing in a live session, the preview with none', () {
    MockClient server() => MockClient((http.Request req) async {
          final String p = req.url.path;
          http.Response j(Object b) => http.Response(jsonEncode(b), 200, headers: <String, String>{'content-type': 'application/json'});
          if (p == '/v1/auth/dev-login') return j(<String, Object?>{'token': 'tok'});
          if (p.endsWith('/now')) {
            return j(<String, Object?>{'childLocalTime': '9:14 PM', 'zoneAbbr': 'EST', 'zone': 'America/New_York', 'dayPart': 'asleep', 'reachable': false});
          }
          if (p.endsWith('/ribbon')) return j(<String, Object?>{'childName': 'Ivy', 'dayParts': <Object?>[], 'actorWindows': <Object?>[]});
          if (p.endsWith('/day-parts')) {
            return j(<String, Object?>{
              'dayParts': <Object?>[<String, Object?>{'kind': 'bedtime', 'startsLocal': '19:30', 'endsLocal': '20:30', 'daysOfWeek': <int>[0, 1, 2, 3, 4, 5, 6], 'reachable': true}],
              'hasBedtime': true,
            });
          }
          if (p.endsWith('/sent')) return j(<String, Object?>{'messages': <Object?>[]});
          return http.Response('not found', 404);
        });

    testWidgets('Message banking opens the real composer with her real day, not the in-memory preview', (t) async {
      await t.pumpWidget(wrap(LiveGuardianHomeScreen(
          baseUrl: 'http://api.test', guardianId: 'dad-a', childId: 'child-a', httpClient: server())));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Message banking'));
      await t.tap(find.text('Message banking'));
      await t.pumpAndSettle();
      expect(find.byType(GuardianComposeScreen), findsOneWidget);
      expect(find.text('Bank this message'), findsNothing, reason: 'the preview is not shown to a real family');
      expect(find.byKey(const Key('composePart_bedtime')), findsOneWidget, reason: 'her real day was fetched');
      await end(t);
    });

    testWidgets('the Send-time guard opens the same composer, and says nothing was sent when nothing was', (t) async {
      await t.pumpWidget(wrap(LiveGuardianHomeScreen(
          baseUrl: 'http://api.test', guardianId: 'dad-a', childId: 'child-a', httpClient: server())));
      await t.pumpAndSettle();
      await t.ensureVisible(find.text('Send-time guard'));
      await t.tap(find.text('Send-time guard'));
      await t.pumpAndSettle();
      expect(find.byType(SendTimeGuardScreen), findsOneWidget);
      expect(find.byKey(const Key('guardRealNote')), findsOneWidget);
      expect(find.textContaining('June 1st'), findsNothing, reason: 'the invented anchor section is preview-only');
      await t.tap(find.byKey(const Key('guardOpenComposer')));
      await t.pumpAndSettle();
      expect(find.byType(GuardianComposeScreen), findsOneWidget);
      await end(t);
    });

    test('the settings hub has a live-session row for her day, in the Her group', () {
      final String src = File('lib/guardian_more.dart').readAsStringSync();
      final int her = src.indexOf("SettingsGroup('Her'");
      final int row = src.indexOf("id: 'dayparts'");
      final int family = src.indexOf("SettingsGroup('Family'");
      expect(row, greaterThan(her));
      expect(row, lessThan(family));
      expect(src, contains('DayPartsScreen('));
    });

    test('her app has no way in: no child-side file mentions the guardian send path (P1 to P11)', () {
      for (final String f in <String>[
        'lib/child_home.dart', 'lib/child_more.dart', 'lib/child_home_live.dart', 'lib/inbox_screen.dart',
        'lib/receipt_screen.dart', 'lib/child_receive.dart',
      ]) {
        final String src = File(f).readAsStringSync();
        for (final String w in <String>['guardian_send', 'GuardianSendService', 'DayPartsScreen', 'GuardianComposeScreen']) {
          expect(src, isNot(contains(w)), reason: '$f mentions $w');
        }
      }
    });
  });
}
