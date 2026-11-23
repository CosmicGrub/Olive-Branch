// OLIVE BRANCH — "Send to her" on screen: compose, choose when, the guard, honest status, the outbox. Headless, against
// a stand-in written from the real routes. MASTERFILE section 8.31.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/api_client.dart';
import 'package:olive_client/guardian_send_logic.dart';
import 'package:olive_client/guardian_send_screen.dart';
import 'package:olive_client/guardian_send_service.dart';

import 'support/fake_delivery_server.dart';

PickedMedia photo() => PickedMedia(bytes: jpegBytes(), kind: MediaKind.photo, durationMs: 1);
PickedMedia clip() => PickedMedia(bytes: mp4Bytes(), kind: MediaKind.video, durationMs: 9000);

class Harness {
  Harness({FakeDeliveryServer? server, SendOutbox? outbox, this.picker, this.nightPicker})
      : server = server ?? FakeDeliveryServer(),
        outbox = outbox ?? MemorySendOutbox();
  final FakeDeliveryServer server;
  final SendOutbox outbox;
  Future<PickedMedia?> Function(PickSource)? picker;
  NightPicker? nightPicker;
  int clock = 1000000000000;

  Widget app({Size? size, double textScale = 1}) => MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: size ?? const Size(400, 900), textScaler: TextScaler.linear(textScale)),
          child: GuardianSendScreen(
            childName: 'Mia',
            childId: kChild,
            openApi: () async => OliveApi(kBase, 'tok', client: server.client),
            outbox: outbox,
            closeApi: false,
            pickMedia: picker ?? (PickSource _) async => photo(),
            pickNight: nightPicker,
            retryEvery: null,
            nowMs: () => clock,
          ),
        ),
      );
}

Future<void> settle(WidgetTester t) async {
  for (int i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
  await t.pumpAndSettle(const Duration(milliseconds: 100));
}

Future<void> choose(WidgetTester t) async {
  await t.tap(find.byKey(const Key('sendPickPhoto')));
  await settle(t);
}

Future<void> tapSend(WidgetTester t) async {
  await t.ensureVisible(find.byKey(const Key('sendButton')));
  await t.tap(find.byKey(const Key('sendButton')));
  await settle(t);
}

void main() {
  testWidgets('first look: nothing sent yet, Send waits for something to send, bedtime is the default', (t) async {
    final Harness h = Harness();
    await t.pumpWidget(h.app());
    await settle(t);
    expect(find.text('Send to Mia'), findsOneWidget);
    expect(find.byKey(const Key('sentEmpty')), findsOneWidget);
    expect(t.widget<FilledButton>(find.byKey(const Key('sendButton'))).onPressed, isNull);
    expect(find.byKey(const Key('sendGuard')), findsNothing);
    expect(find.text('Which part of her day'), findsOneWidget);
  });

  testWidgets('choose, send at bedtime: the server has it, the page says so, and then lists it as waiting in her time', (t) async {
    final Harness h = Harness();
    await t.pumpWidget(h.app());
    await settle(t);
    await choose(t);
    expect(find.text('Ready: a photo'), findsOneWidget);
    expect(t.widget<FilledButton>(find.byKey(const Key('sendButton'))).onPressed, isNotNull);
    await tapSend(t);
    expect(h.server.messageCalls, 1);
    expect(h.server.where('POST', '/messages').single.body['delivery'], 'daypart');
    expect(find.textContaining('Sent. It is with the server now'), findsOneWidget);
    expect(find.text('Ready: a photo'), findsNothing, reason: 'cleared once the server has it');
    expect(find.textContaining("Waiting for Mia's bedtime. It will arrive today at 7:30 PM, her time."), findsOneWidget);
    expect(find.text('Waiting'), findsOneWidget);
    expect(find.textContaining('Saved on this phone'), findsNothing);
  });

  testWidgets('right away while she is asleep: a plain warning, the choice stays theirs, and the button says what it is', (t) async {
    final Harness h = Harness();
    h.server.nowDayPart = 'asleep';
    h.server.nowReachable = false;
    await t.pumpWidget(h.app());
    await settle(t);
    await choose(t);
    await t.tap(find.byKey(const Key('sendWhenNow')));
    await settle(t);
    expect(find.text('Mia is asleep right now.'), findsOneWidget);
    expect(find.textContaining("won't buzz her"), findsOneWidget);
    expect(find.text('Send now anyway'), findsOneWidget);
    await tapSend(t);
    expect(h.server.where('POST', '/messages').single.body['delivery'], 'now');
    expect(find.textContaining('Sent.'), findsWidgets);
    expect(find.textContaining('On its way'), findsOneWidget);
  });

  testWidgets('right away when she is up and about has no warning', (t) async {
    final Harness h = Harness();
    await t.pumpWidget(h.app());
    await settle(t);
    await t.tap(find.byKey(const Key('sendWhenNow')));
    await settle(t);
    expect(find.byKey(const Key('sendGuard')), findsNothing);
    expect(find.text('Send now'), findsOneWidget);
  });

  testWidgets('a day with no bedtime blocks "at bedtime" before the server has to, and offers her day', (t) async {
    final Harness h = Harness();
    h.server.dayParts = <Map<String, dynamic>>[
      <String, dynamic>{'kind': 'free', 'startsLocal': '08:00', 'endsLocal': '19:30',
        'daysOfWeek': <int>[0, 1, 2, 3, 4, 5, 6], 'reachable': true}];
    await t.pumpWidget(h.app());
    await settle(t);
    await choose(t);
    expect(find.text("Mia's day has no bedtime yet."), findsOneWidget);
    expect(find.text("Open Mia's day"), findsOneWidget);
    expect(t.widget<FilledButton>(find.byKey(const Key('sendButton'))).onPressed, isNull);
    expect(h.server.messageCalls, 0);
    // right away is still open to them
    await t.tap(find.byKey(const Key('sendWhenNow')));
    await settle(t);
    expect(find.byKey(const Key('sendGuard')), findsNothing);
    expect(t.widget<FilledButton>(find.byKey(const Key('sendButton'))).onPressed, isNotNull);
  });

  testWidgets('a particular night: the picker sets it, a night is sent as a date', (t) async {
    final Harness h = Harness(nightPicker: (BuildContext c, DateTime a, DateTime b) async => DateTime(2026, 12, 24));
    await t.pumpWidget(h.app());
    await settle(t);
    await choose(t);
    await t.tap(find.byKey(const Key('sendWhenNight')));
    await settle(t);
    expect(t.widget<FilledButton>(find.byKey(const Key('sendButton'))).onPressed, isNull, reason: 'no night picked yet');
    await t.tap(find.byKey(const Key('sendPickNight')));
    await settle(t);
    expect(find.text('Thu, Dec 24'), findsOneWidget);
    await tapSend(t);
    final Map<String, dynamic> b = h.server.where('POST', '/messages').single.body;
    expect(b['delivery'], 'date');
    expect(b['targetLocalDate'], '2026-12-24');
  });

  testWidgets('no server: saved on this phone, said plainly, never called sent; Try now sends it when the server is back', (t) async {
    final Harness h = Harness();
    await t.pumpWidget(h.app());
    await settle(t);
    h.server.offline = true;
    await choose(t);
    await tapSend(t);
    expect(find.textContaining('saved on this phone'), findsWidgets);
    expect(find.textContaining('Nothing is lost'), findsOneWidget);
    expect(find.text('Saved on this phone'), findsOneWidget);
    expect(find.textContaining("hasn't reached the server"), findsOneWidget);
    expect(find.textContaining('Sent. It is with the server'), findsNothing);
    expect(find.byKey(const Key('sentError')), findsOneWidget);
    expect(find.byKey(const Key('sentEmpty')), findsNothing, reason: 'it could not read what was sent, so it does not claim "nothing"');
    expect(find.text('Ready: a photo'), findsNothing, reason: 'it is safe on the phone, so the draft is cleared');
    expect(h.server.messageCalls, 0);
    // back online
    h.server.offline = false;
    await t.tap(find.textContaining('Try now'));
    await settle(t);
    expect(find.text('Saved on this phone'), findsNothing);
    expect(find.textContaining('Sent. It is with the server now'), findsOneWidget);
    expect(h.server.sent, hasLength(1));
    expect(find.byKey(const Key('sentError')), findsNothing);
  });

  testWidgets('a server "no" is said in words and keeps nothing; the draft stays so it can be fixed', (t) async {
    final Harness h = Harness(picker: (PickSource _) async => PickedMedia(bytes: 'GIF89a......'.codeUnits, kind: MediaKind.photo, durationMs: 1));
    await t.pumpWidget(h.app());
    await settle(t);
    await choose(t);
    await tapSend(t);
    expect(find.textContaining("can't be sent"), findsOneWidget);
    expect(find.text('Saved on this phone'), findsNothing);
    expect(find.text('Ready: a photo'), findsOneWidget, reason: 'not cleared: it did not go and was not kept');
  });

  testWidgets('a message too big to keep, with no server, is not claimed safe', (t) async {
    final Harness h = Harness(picker: (PickSource _) async => PickedMedia(
        bytes: <int>[...jpegBytes(), ...List<int>.filled(kMaxKeptBytes + 5, 2)], kind: MediaKind.photo, durationMs: 1));
    await t.pumpWidget(h.app());
    await settle(t);
    h.server.offline = true;
    await choose(t);
    await tapSend(t);
    expect(find.textContaining('too big to keep'), findsOneWidget);
    expect(find.textContaining("wasn't sent"), findsOneWidget);
    expect(find.text('Ready: a photo'), findsOneWidget);
    expect(find.text('Saved on this phone'), findsNothing);
  });

  testWidgets('a "right away" that waited asks what to do, and Send it now sends it', (t) async {
    final Harness h = Harness();
    await t.pumpWidget(h.app());
    await settle(t);
    h.server.offline = true;
    await choose(t);
    await t.tap(find.byKey(const Key('sendWhenNow')));
    await settle(t);
    await tapSend(t);
    h.server.offline = false;
    h.clock += 2 * 60 * 60000;
    await t.tap(find.byKey(const Key('sendRefresh')));
    await settle(t);
    expect(find.textContaining('meant to go right away'), findsOneWidget);
    expect(find.textContaining('Try now'), findsNothing);
    expect(h.server.messageCalls, 0);
    final Finder now = find.textContaining('Send it now');
    await t.ensureVisible(now);
    await t.tap(now);
    await settle(t);
    expect(h.server.where('POST', '/messages').single.body['delivery'], 'now');
    expect(find.textContaining('meant to go right away'), findsNothing);
  });

  testWidgets('Discard lets a waiting message go', (t) async {
    final Harness h = Harness();
    await t.pumpWidget(h.app());
    await settle(t);
    h.server.offline = true;
    await choose(t);
    await tapSend(t);
    expect(find.text('Saved on this phone'), findsOneWidget);
    await t.tap(find.textContaining('Discard'));
    await settle(t);
    expect(find.text('Saved on this phone'), findsNothing);
    expect(await h.outbox.load(), isEmpty);
  });

  testWidgets('what happened to earlier messages: waiting, delivered and opened are each told in adult words, in her time', (t) async {
    final Harness h = Harness();
    h.server.sent
      ..add(SentRow('aaaaaaaa-0000-4000-8000-000000000001', 'daypart', 'bedtime', null)
        ..deliversHer = <String, String>{'day': 'tomorrow', 'time': '8:30 PM'})
      ..add(SentRow('aaaaaaaa-0000-4000-8000-000000000002', 'daypart', 'bedtime', null)
        ..state = 'delivered'
        ..deliveredHer = <String, String>{'day': 'yesterday', 'time': '8:30 PM'})
      ..add(SentRow('aaaaaaaa-0000-4000-8000-000000000003', 'date', null, '2026-11-14')
        ..state = 'opened'
        ..receiptPhrase = 'Watched at 8:42 PM her time — at bedtime.');
    await t.pumpWidget(h.app());
    await settle(t);
    expect(find.textContaining('It will arrive tomorrow at 8:30 PM, her time.'), findsOneWidget);
    expect(find.textContaining("Delivered to Mia's inbox yesterday at 8:30 PM, her time. She has not opened it yet."), findsOneWidget);
    expect(find.text('Watched at 8:42 PM her time — at bedtime.'), findsOneWidget);
    expect(find.text('Waiting'), findsOneWidget);
    expect(find.text('Delivered'), findsOneWidget);
    expect(find.text('Opened'), findsOneWidget);
    expect(find.textContaining('Only your own messages are listed'), findsOneWidget);
  });

  testWidgets('a picker that fails is a calm sentence, and an unsupported file is named as such', (t) async {
    final Harness h = Harness(picker: (PickSource s) async => throw StateError('camera busy'));
    await t.pumpWidget(h.app());
    await settle(t);
    await t.tap(find.byKey(const Key('sendPickVideo')));
    await settle(t);
    expect(find.textContaining("Couldn't open the camera"), findsOneWidget);
    expect(find.textContaining('camera busy'), findsNothing);
    h.picker = (PickSource s) async => throw const FormatException('unsupported');
    await t.tap(find.byKey(const Key('sendPickGallery')));
    await settle(t);
    expect(find.textContaining("That kind of file can't be sent"), findsOneWidget);
  });

  testWidgets('the Send-time guard on a live session cannot pretend: nothing here is a confirmation', (t) async {
    // The old live screen printed "Sent" without sending; the screen above is the only place that says Sent, and only
    // after a 2xx. This asserts the sentence never appears while the server refused.
    final Harness h = Harness();
    await t.pumpWidget(h.app());
    await settle(t);
    h.server.failNextWith = 20;
    h.server.failStatus = 500;
    await choose(t);
    await tapSend(t);
    expect(find.textContaining('Sent. It is with the server'), findsNothing);
    expect(h.server.sent, isEmpty);
  });

  for (final (String label, Size size, double scale) in <(String, Size, double)>[
    ('fold5 cover at 2x text', const Size(344, 820), 2.0),
    ('phone', const Size(390, 844), 1.0),
    ('tablet', const Size(1100, 800), 1.3),
  ]) {
    testWidgets('does not overflow at $label, with a warning, a queued message and sent rows showing', (t) async {
      await t.binding.setSurfaceSize(size);
      addTearDown(() => t.binding.setSurfaceSize(null));
      final Harness h = Harness();
      h.server.nowDayPart = 'asleep';
      h.server.nowReachable = false;
      h.server.sent.add(SentRow('aaaaaaaa-0000-4000-8000-000000000009', 'daypart', 'bedtime', null)
        ..deliversHer = <String, String>{'day': 'Sat, Nov 21', 'time': '8:30 PM'});
      await t.pumpWidget(h.app(size: size, textScale: scale));
      await settle(t);
      h.server.offline = true;
      await choose(t);
      await t.tap(find.byKey(const Key('sendWhenNow')));
      await settle(t);
      await tapSend(t);
      expect(t.takeException(), isNull);
      await t.drag(find.byType(SingleChildScrollView).first, const Offset(0, -2000));
      await settle(t);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('nothing on this page is drawn with the words a child must never see', (t) async {
    // Grown-up page: but it must still never read like a score board. No streak, no count of sends.
    final Harness h = Harness();
    h.server.sent.add(SentRow('aaaaaaaa-0000-4000-8000-000000000011', 'now', null, null)..state = 'opened'
      ..receiptPhrase = 'Watched at 8:42 PM her time.');
    await t.pumpWidget(h.app());
    await settle(t);
    final String all = t.widgetList<Text>(find.byType(Text)).map((Text x) => x.data ?? '').join(' ').toLowerCase();
    for (final String w in <String>['streak', 'score', 'points', 'rank', 'level up', 'sent 1 ', 'total sent']) {
      expect(all, isNot(contains(w)), reason: w);
    }
  });

  test('the live constructor builds with a session opener (no UI)', () {
    final GuardianSendScreen s = GuardianSendScreen.live(
        baseUrl: kBase, guardianId: 'g', childId: kChild, childName: 'Mia', httpClient: FakeDeliveryServer().client);
    expect(s.closeApi, isFalse, reason: 'a supplied client is the caller\'s to close');
    expect(s.childId, kChild);
    expect(const SocketException('x').message, 'x');
  });
}
