// OLIVE BRANCH — receipt_screen.dart tests. §8.2.4, §9.5.
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:olive_client/offline_outbox.dart' show offlineForbidden;
import 'package:olive_client/receipt_screen.dart';
import 'package:olive_client/send_back_outbox.dart';

import 'send_back_fakes.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

/// A send-back queue over in-memory fakes, so a widget test never touches app storage.
SendBackQueue _q() => queueOver(FakeOutboxDisk(), FakeRecordings(), FakeClock(DateTime.utc(2026, 11, 21, 12)));

/// A fake recorded clip — no real file I/O, no platform channel.
XFile _fakeClip() => XFile.fromData(Uint8List(0), name: 'clip.mp4');

void main() {
  group('Receipt — §8.2.4, her frame first', () {
    testWidgets('renders the exact quoted phrase shape, her frame, her name', (tester) async {
      await tester.pumpWidget(wrap(const ReceiptScreen(
        childName: 'Ivy', senderName: 'Dad',
        watchedAtLabel: '7:04 AM', dayPartKind: 'before_school')));
      expect(find.text("Watched at 7:04 AM Ivy's time — before school."), findsOneWidget);
    });

    testWidgets('names the sender and the child, not an id', (tester) async {
      await tester.pumpWidget(wrap(const ReceiptScreen(
        childName: 'Ivy', senderName: 'Dad',
        watchedAtLabel: '7:04 AM', dayPartKind: 'before_school')));
      expect(find.textContaining("Dad's message"), findsOneWidget);
    });

    testWidgets('a null day-part still renders an honest phrase with no dangling dash',
        (tester) async {
      await tester.pumpWidget(wrap(const ReceiptScreen(
        childName: 'Ivy', senderName: 'Dad',
        watchedAtLabel: '2:00 PM', dayPartKind: null)));
      expect(find.text("Watched at 2:00 PM Ivy's time."), findsOneWidget);
      expect(find.textContaining('—'), findsNothing);
    });

    testWidgets('never shows a zone abbreviation, UTC, or raw offset arithmetic',
        (tester) async {
      await tester.pumpWidget(wrap(const ReceiptScreen(
        childName: 'Ivy', senderName: 'Dad',
        watchedAtLabel: '7:04 AM', dayPartKind: 'before_school')));
      expect(find.textContaining('UTC'), findsNothing);
      expect(find.textContaining('GMT'), findsNothing);
      expect(find.textContaining('+1'), findsNothing);
    });

    testWidgets('NO settings affordance, no price, no error copy anywhere before any tap',
        (tester) async {
      await tester.pumpWidget(wrap(const ReceiptScreen(
        childName: 'Ivy', senderName: 'Dad',
        watchedAtLabel: '7:04 AM', dayPartKind: 'before_school')));
      expect(find.byIcon(Icons.settings), findsNothing);
      expect(find.textContaining(r'$'), findsNothing);
      expect(find.textContaining('error'), findsNothing);
      expect(find.textContaining('failed'), findsNothing);
    });

    testWidgets(
        "'Send one back' with no live wiring reports itself honestly, not a faked success",
        (tester) async {
      // No baseUrl/childId/sessionToken supplied -- the real shape of every
      // call site today (inbox_screen.dart is still the offline demo build).
      await tester.pumpWidget(wrap(const ReceiptScreen(
        childName: 'Ivy', senderName: 'Dad',
        watchedAtLabel: '7:04 AM', dayPartKind: 'before_school')));
      await tester.tap(find.text('Send one back'));
      await tester.pump();
      expect(find.text("That didn't go. Let's try again."), findsOneWidget);
      expect(find.textContaining('server'), findsNothing);
      expect(find.textContaining('Sent!'), findsNothing);
    });

    testWidgets('both primary buttons meet the 48dp+ touch target minimum', (tester) async {
      await tester.pumpWidget(wrap(const ReceiptScreen(
        childName: 'Ivy', senderName: 'Dad',
        watchedAtLabel: '7:04 AM', dayPartKind: 'before_school')));
      expect(tester.getSize(find.byType(FilledButton)).height, greaterThanOrEqualTo(48.0));
      expect(tester.getSize(find.byType(OutlinedButton)).height, greaterThanOrEqualTo(48.0));
    });

    group('responsive — no overflow at any required viewport width', () {
      Future<void> pumpAt(WidgetTester tester, Size size) async {
        await tester.binding.setSurfaceSize(size);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(wrap(const ReceiptScreen(
          childName: 'Ivy', senderName: 'Dad',
          watchedAtLabel: '7:04 AM', dayPartKind: 'before_school')));
        await tester.pump();
      }

      testWidgets('Fold5 cover screen (344 CSS px wide)', (tester) async {
        await pumpAt(tester, const Size(344, 900));
        expect(tester.takeException(), isNull);
      });

      testWidgets('Fold5 unfolded main screen (~673x841, nearly square)', (tester) async {
        await pumpAt(tester, const Size(673, 841));
        expect(tester.takeException(), isNull);
      });

      testWidgets('standard phone width (~390px)', (tester) async {
        await pumpAt(tester, const Size(390, 844));
        expect(tester.takeException(), isNull);
      });

      testWidgets('tablet/desktop width (~1100px, short and wide)', (tester) async {
        await pumpAt(tester, const Size(1100, 800));
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets("'Back to messages' pops the route", (tester) async {
      await tester.pumpWidget(wrap(Builder(builder: (context) => Scaffold(
        body: Center(child: FilledButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => const ReceiptScreen(
              childName: 'Ivy', senderName: 'Dad',
              watchedAtLabel: '7:04 AM', dayPartKind: 'before_school'))),
          child: const Text('open'))),
      ))));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.byType(ReceiptScreen), findsOneWidget);
      await tester.tap(find.text('Back to messages'));
      await tester.pumpAndSettle();
      expect(find.byType(ReceiptScreen), findsNothing);
    });
  });

  group('Receipt — "Send one back" really wired (live params + injected picker/client)', () {
    testWidgets('records, uploads the real bytes, POSTs the REAL server-'
        'assigned storage key, and shows a real success state', (tester) async {
      final List<Uri> seenUrls = <Uri>[];
      Map<String, dynamic>? uploadBody;
      Map<String, dynamic>? sendBody;
      // A real (if tiny) delay on the mocked transport — otherwise every
      // await in _sendOneBack resolves within the same microtask flush a
      // single tester.pump() already drains, and the busy state below would
      // never actually be observable, real or not.
      final MockClient mock = MockClient((http.Request req) async {
        await Future<void>.delayed(const Duration(milliseconds: 15));
        seenUrls.add(req.url);
        if (req.url.path.endsWith('/media')) {
          uploadBody = jsonDecode(req.body) as Map<String, dynamic>;
          // The REAL storage key server/routes.mjs's FilesystemStorage would
          // assign — never a client-fabricated `device/...` reference.
          return http.Response(
            jsonEncode({'storageKey': 'children/child-a/messages/real-uuid-1', 'etag': 'e1'}),
            201);
        }
        sendBody = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({'id': 'intent-1', 'artifactId': 'artifact-1', 'state': 'pending'}), 201);
      });

      await tester.pumpWidget(wrap(ReceiptScreen(
        childName: 'Ivy', senderName: 'Dad',
        watchedAtLabel: '7:04 AM', dayPartKind: 'before_school',
        baseUrl: 'http://api.test', childId: 'child-a', sessionToken: 'tok-1',
        httpClient: mock, pickVideo: () async => _fakeClip(), sendBackQueue: _q(),
      )));

      await tester.tap(find.text('Send one back'));
      await tester.pump();
      // Mid-flight: a real busy state, not an instant fake success.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Sending…'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 60));
      expect(find.text('Sent!'), findsOneWidget);
      expect(find.text('Send one back'), findsNothing);

      // BOTH real requests actually reached api_client.dart's real paths,
      // upload before send.
      expect(seenUrls.map((u) => u.toString()), <String>[
        'http://api.test/v1/children/child-a/media',
        'http://api.test/v1/children/child-a/messages',
      ]);
      // The real recorded bytes travelled to the upload route.
      expect(uploadBody?['bytes'], isA<String>());
      // ...and the message-send route received the REAL key the (mocked)
      // upload response assigned — not a locally-fabricated reference. This
      // is the real object-storage gap MASTERFILE §20.2b named, closed.
      expect(sendBody?['storageKey'], 'children/child-a/messages/real-uuid-1');
      expect(sendBody?['durationMs'], isA<int>());
      expect((sendBody?['durationMs'] as int) > 0, isTrue);
    });

    testWidgets('a real server rejection shows a real error, not a faked success',
        (tester) async {
      final MockClient mock = MockClient((http.Request req) async =>
          http.Response(jsonEncode({'error': 'not_authorized'}), 403));

      await tester.pumpWidget(wrap(ReceiptScreen(
        childName: 'Ivy', senderName: 'Dad',
        watchedAtLabel: '7:04 AM', dayPartKind: 'before_school',
        baseUrl: 'http://api.test', childId: 'child-a', sessionToken: 'tok-1',
        httpClient: mock, pickVideo: () async => _fakeClip(), sendBackQueue: _q(),
      )));

      await tester.tap(find.text('Send one back'));
      await tester.pumpAndSettle();

      expect(find.text('Sent!'), findsNothing);
      // The recording is on the device and stays there: a refusal is never a reason to lose it. She is told only
      // the one calm kept-safe line, never the status code or the server's word for it.
      expect(find.textContaining('403'), findsNothing);
      expect(find.textContaining('not_authorized'), findsNothing);
      expect(find.text('Kept safe'), findsOneWidget);
      expect(find.text(kSendBackTryAgainLine), findsNothing);
    });

    testWidgets('cancelling the camera picker returns to idle, no request sent', (tester) async {
      bool requestMade = false;
      final MockClient mock = MockClient((http.Request req) async {
        requestMade = true;
        return http.Response('{}', 201);
      });

      await tester.pumpWidget(wrap(ReceiptScreen(
        childName: 'Ivy', senderName: 'Dad',
        watchedAtLabel: '7:04 AM', dayPartKind: 'before_school',
        baseUrl: 'http://api.test', childId: 'child-a', sessionToken: 'tok-1',
        httpClient: mock, pickVideo: () async => null, sendBackQueue: _q(),
      )));

      await tester.tap(find.text('Send one back'));
      await tester.pumpAndSettle();

      expect(requestMade, isFalse);
      expect(find.text('Send one back'), findsOneWidget);
      expect(find.textContaining('error'), findsNothing);
    });
  });

  group('Receipt — offline-outbox honesty (queued/in-flight vs confirmed-sent '
      'vs failed-will-retry, MASTERFILE §5.22, offline_outbox.dart)', () {
    testWidgets(
        'a connectivity failure is queued and reassures her honestly -- '
        'never "Sent!", never the raw exception, never the banned '
        'engineering vocabulary', (tester) async {
      final MockClient mock =
          MockClient((http.Request req) async => throw Exception('connection refused'));

      await tester.pumpWidget(wrap(ReceiptScreen(
        childName: 'Ivy', senderName: 'Dad',
        watchedAtLabel: '7:04 AM', dayPartKind: 'before_school',
        baseUrl: 'http://api.test', childId: 'child-a', sessionToken: 'tok-1',
        httpClient: mock, pickVideo: () async => _fakeClip(), sendBackQueue: _q(),
        // Real backoff is minutes-to-hours; overridden to something that
        // will not fire during this test, which only asserts the FIRST
        // honest state a connectivity gap lands on.
        retryBackoff: (_) => const Duration(minutes: 10),
      )));

      await tester.tap(find.text('Send one back'));
      await tester.pump();

      // The one honest sentence offline_outbox.dart's offlineChildView
      // allows -- her thing is safe, and that is all she is told.
      expect(find.text('It will go when you have internet again. It is safe.'),
          findsOneWidget);
      expect(find.text('Kept safe'), findsOneWidget);

      // Never claims further along than it truly is, and never leaks the
      // raw exception or this codebase's own banned queue/retry vocabulary.
      expect(find.text('Sent!'), findsNothing);
      expect(find.textContaining('connection refused'), findsNothing);
      expect(find.textContaining('Exception'), findsNothing);
      for (final String word in offlineForbidden) {
        expect(find.textContaining(word), findsNothing,
            reason: 'banned offline vocabulary "$word" must never reach her screen');
      }
    });

    testWidgets(
        'a connectivity failure really retries on its own -- "Sent!" only '
        'appears once a real retry genuinely succeeds', (tester) async {
      // Counts UPLOAD attempts specifically (a real connectivity gap blocks
      // whichever real HTTP call happens to go first, same as it would for
      // any single request) -- the first upload attempt fails, the retry's
      // own upload succeeds, and the send that follows it succeeds too.
      int uploadAttempts = 0;
      final MockClient mock = MockClient((http.Request req) async {
        if (req.url.path.endsWith('/media')) {
          uploadAttempts += 1;
          if (uploadAttempts == 1) throw Exception('connection refused');
          return http.Response(
              jsonEncode({'storageKey': 'children/child-a/messages/real-uuid-2', 'etag': 'e2'}),
              201);
        }
        return http.Response(
            jsonEncode({'id': 'intent-2', 'artifactId': 'artifact-2', 'state': 'pending'}), 201);
      });

      await tester.pumpWidget(wrap(ReceiptScreen(
        childName: 'Ivy', senderName: 'Dad',
        watchedAtLabel: '7:04 AM', dayPartKind: 'before_school',
        baseUrl: 'http://api.test', childId: 'child-a', sessionToken: 'tok-1',
        httpClient: mock, pickVideo: () async => _fakeClip(), sendBackQueue: _q(),
        // Real backoff is offline_outbox.dart's own backoffMs (minutes to
        // hours); overridden here only so this test can observe a real
        // automatic retry firing without actually waiting.
        retryBackoff: (_) => const Duration(milliseconds: 20),
      )));

      await tester.tap(find.text('Send one back'));
      await tester.pump();
      expect(find.text('Kept safe'), findsOneWidget);
      expect(uploadAttempts, 1);

      // Advancing past the real (if shortened) backoff fires the scheduled
      // retry -- a genuine second attempt, not a fabricated success. The
      // retry's own upload succeeds and is never repeated a third time (see
      // receipt_screen.dart's own storageKey-caching comment) -- exactly one
      // more upload call, then the send that follows it.
      await tester.pump(const Duration(milliseconds: 30));
      expect(uploadAttempts, 2);
      expect(find.text('Sent!'), findsOneWidget);
      expect(find.text('Kept safe'), findsNothing);
    });

    testWidgets(
        'a server refusal keeps the recording and asks again later, silently (never deleted for a refusal)',
        (tester) async {
      int attempts = 0;
      final MockClient mock = MockClient((http.Request req) async {
        attempts += 1;
        return http.Response(jsonEncode({'error': 'not_authorized'}), 403);
      });
      final SendBackQueue q = _q();

      await tester.pumpWidget(wrap(ReceiptScreen(
        childName: 'Ivy', senderName: 'Dad',
        watchedAtLabel: '7:04 AM', dayPartKind: 'before_school',
        baseUrl: 'http://api.test', childId: 'child-a', sessionToken: 'tok-1',
        httpClient: mock, pickVideo: () async => _fakeClip(), sendBackQueue: q,
        retryBackoff: (_) => const Duration(milliseconds: 20),
      )));

      await tester.tap(find.text('Send one back'));
      await tester.pump();

      expect(find.text('Kept safe'), findsOneWidget);
      expect(find.textContaining('403'), findsNothing);
      expect(find.text(kSendBackTryAgainLine), findsNothing);
      expect(attempts, 1);

      // Waiting past the backoff asks again on its own: the recording was never given up on.
      await tester.pump(const Duration(milliseconds: 30));
      await tester.pump();
      expect(attempts, greaterThan(1));
      expect(find.text('Kept safe'), findsOneWidget);
    });
  });

  group('Receipt — what she may read when "Send one back" does not go (ISS-040)', () {
    /// Every string drawn by any Text on screen.
    List<String> allText(WidgetTester tester) => <String>[
          for (final Text t in tester.widgetList<Text>(find.byType(Text))) t.data ?? t.textSpan?.toPlainText() ?? '',
        ];

    void expectNoLeak(WidgetTester tester) {
      for (final String t in allText(tester)) {
        final String low = t.toLowerCase();
        for (final String bad in <String>[
          'exception', 'socket', 'timeout', 'http', 'status', 'server', 'connected', '403', '500', '404',
          'not_authorized', 'platformexception', 'camera_access', 'null', 'instance of',
        ]) {
          expect(low.contains(bad), isFalse, reason: '"$t" must not carry "$bad"');
        }
      }
    }

    void expectCalm(WidgetTester tester) {
      expectNoLeak(tester);
      expect(find.text(kSendBackTryAgainLine), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_off_outlined), findsOneWidget);
    }

    testWidgets('a status code and a server error name reach no Text', (tester) async {
      final MockClient mock = MockClient((http.Request req) async =>
          http.Response(jsonEncode(<String, Object>{'error': 'not_authorized_500'}), 403));
      await tester.pumpWidget(wrap(ReceiptScreen(
        childName: 'Ivy', senderName: 'Dad', watchedAtLabel: '7:04 AM', dayPartKind: null,
        baseUrl: 'http://api.test', childId: 'child-a', sessionToken: 'tok-1',
        httpClient: mock, pickVideo: () async => _fakeClip(), sendBackQueue: _q())));
      await tester.tap(find.text('Send one back'));
      await tester.pumpAndSettle();
      expectNoLeak(tester);
      expect(find.text('Kept safe'), findsOneWidget);
    });

    testWidgets('a raw exception from the camera reaches no Text', (tester) async {
      await tester.pumpWidget(wrap(ReceiptScreen(
        childName: 'Ivy', senderName: 'Dad', watchedAtLabel: '7:04 AM', dayPartKind: null,
        baseUrl: 'http://api.test', childId: 'child-a', sessionToken: 'tok-1',
        pickVideo: () async => throw Exception('PlatformException(camera_access_denied, 192.0.2.5)'),
        sendBackQueue: _q())));
      await tester.tap(find.text('Send one back'));
      await tester.pumpAndSettle();
      expectCalm(tester);
    });

    testWidgets('a screen with no live session says the same calm line, not "isn\'t connected to a server"',
        (tester) async {
      await tester.pumpWidget(wrap(const ReceiptScreen(
        childName: 'Ivy', senderName: 'Dad', watchedAtLabel: '7:04 AM', dayPartKind: null)));
      await tester.tap(find.text('Send one back'));
      await tester.pumpAndSettle();
      expectCalm(tester);
    });

    test('the try-again line passes the child-copy audit, and the audit really fails a leaky line', () {
      expect(auditSendBackCopy(kSendBackTryAgainLine), isTrue);
      expect(auditSendBackCopy('Error 403: not_authorized'), isFalse);
      expect(auditSendBackCopy('Try again in 5 minutes'), isFalse);
      expect(auditSendBackCopy('Your attempts failed'), isFalse);
    });
  });

  group('Receipt — "Kept safe" only after the durable write (ISS-039)', () {
    testWidgets('a copy that cannot be made is never promised: try-again, no "Kept safe", nothing sent',
        (tester) async {
      final FakeRecordings files = FakeRecordings()..failKeep = true;
      int requests = 0;
      final MockClient mock = MockClient((http.Request req) async {
        requests++;
        return http.Response('{}', 201);
      });
      await tester.pumpWidget(wrap(ReceiptScreen(
        childName: 'Ivy', senderName: 'Dad', watchedAtLabel: '7:04 AM', dayPartKind: null,
        baseUrl: 'http://api.test', childId: 'child-a', sessionToken: 'tok-1',
        httpClient: mock, pickVideo: () async => _fakeClip(),
        sendBackQueue: queueOver(FakeOutboxDisk(), files, FakeClock(DateTime.utc(2026, 11, 21))))));
      await tester.tap(find.text('Send one back'));
      await tester.pumpAndSettle();
      expect(find.text('Kept safe'), findsNothing);
      expect(find.text(kSendBackTryAgainLine), findsOneWidget);
      expect(requests, 0);
    });

    testWidgets('a row that cannot be written is never promised, and the copy is removed again', (tester) async {
      final FakeRecordings files = FakeRecordings();
      final FakeOutboxDisk disk = FakeOutboxDisk()..failSave = true;
      final MockClient mock = MockClient((http.Request req) async => throw Exception('offline'));
      await tester.pumpWidget(wrap(ReceiptScreen(
        childName: 'Ivy', senderName: 'Dad', watchedAtLabel: '7:04 AM', dayPartKind: null,
        baseUrl: 'http://api.test', childId: 'child-a', sessionToken: 'tok-1',
        httpClient: mock, pickVideo: () async => _fakeClip(),
        sendBackQueue: queueOver(disk, files, FakeClock(DateTime.utc(2026, 11, 21))))));
      await tester.tap(find.text('Send one back'));
      await tester.pumpAndSettle();
      expect(find.text('Kept safe'), findsNothing);
      expect(find.text(kSendBackTryAgainLine), findsOneWidget);
      expect(files.files, isEmpty);
    });

    testWidgets('dispose the screen mid-retry, rebuild over the same store, and the send completes',
        (tester) async {
      final FakeRecordings files = FakeRecordings();
      final FakeOutboxDisk disk = FakeOutboxDisk();
      final FakeClock clock = FakeClock(DateTime.utc(2026, 11, 21, 8));

      // 1. No signal: the screen keeps the recording and says so.
      final MockClient down = MockClient((http.Request req) async => throw Exception('connection refused'));
      await tester.pumpWidget(wrap(ReceiptScreen(
        childName: 'Ivy', senderName: 'Dad', watchedAtLabel: '7:04 AM', dayPartKind: null,
        baseUrl: 'http://api.test', childId: 'child-a', sessionToken: 'tok-1',
        httpClient: down, pickVideo: () async => _fakeClip(),
        retryBackoff: (_) => const Duration(minutes: 10),
        sendBackQueue: queueOver(disk, files, clock))));
      await tester.tap(find.text('Send one back'));
      await tester.pump();
      expect(find.text('Kept safe'), findsOneWidget);
      expect(files.files, hasLength(1));
      expect(disk.rows, hasLength(1));

      // 2. The screen goes away mid-retry (back out, or the app is closed). Its timer goes with it.
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump(const Duration(minutes: 11));
      expect(files.files, hasLength(1), reason: 'the recording outlives the screen');
      expect(disk.rows, hasLength(1));

      // 3. A new owner over the same store, later, with signal: the send completes.
      clock.advance(const Duration(hours: 1));
      final List<String> seen = <String>[];
      final MockClient up = MockClient((http.Request req) async {
        seen.add(req.url.path);
        if (req.url.path.endsWith('/media')) {
          return http.Response(jsonEncode(<String, Object>{'storageKey': 'children/child-a/messages/k1'}), 201);
        }
        expect((jsonDecode(req.body) as Map<String, dynamic>)['storageKey'], 'children/child-a/messages/k1');
        return http.Response(jsonEncode(<String, Object>{'id': 'i1', 'artifactId': 'a1', 'state': 'pending'}), 201);
      });
      await tester.runAsync(() => drainSendBacks(
          baseUrl: 'http://api.test', childId: 'child-a', sessionToken: 'tok-1', httpClient: up,
          queue: queueOver(disk, files, clock)));
      expect(seen, <String>['/v1/children/child-a/media', '/v1/children/child-a/messages']);
      expect(disk.rows, isEmpty);
      expect(files.files, isEmpty, reason: 'a sent recording is removed from app storage');
    });
  });
}
