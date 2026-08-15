// OLIVE BRANCH — receipt_screen.dart tests. §8.2.4, §9.5.
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image_picker/image_picker.dart';
import 'package:olive_client/receipt_screen.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

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
      expect(find.textContaining("isn't connected to a server yet"), findsOneWidget);
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
    testWidgets('records, POSTs, and shows a real success state', (tester) async {
      Uri? seenUrl;
      Map<String, dynamic>? seenBody;
      // A real (if tiny) delay on the mocked transport — otherwise every
      // await in _sendOneBack resolves within the same microtask flush a
      // single tester.pump() already drains, and the busy state below would
      // never actually be observable, real or not.
      final MockClient mock = MockClient((http.Request req) async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        seenUrl = req.url;
        seenBody = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({'id': 'intent-1', 'artifactId': 'artifact-1', 'state': 'pending'}), 201);
      });

      await tester.pumpWidget(wrap(ReceiptScreen(
        childName: 'Ivy', senderName: 'Dad',
        watchedAtLabel: '7:04 AM', dayPartKind: 'before_school',
        baseUrl: 'http://api.test', childId: 'child-a', sessionToken: 'tok-1',
        httpClient: mock, pickVideo: () async => _fakeClip(),
      )));

      await tester.tap(find.text('Send one back'));
      await tester.pump();
      // Mid-flight: a real busy state, not an instant fake success.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Sending…'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 60));
      expect(find.text('Sent!'), findsOneWidget);
      expect(find.text('Send one back'), findsNothing);

      // The real request actually reached api_client.dart's real POST path.
      expect(seenUrl.toString(), 'http://api.test/v1/children/child-a/messages');
      expect(seenBody?['durationMs'], isA<int>());
      expect((seenBody?['durationMs'] as int) > 0, isTrue);
      expect(seenBody?['storageKey'], isA<String>());
      // Nothing here ever claims to have uploaded video bytes — only a
      // locally-meaningful reference travels in the body (see this file's
      // and receipt_screen.dart's own header on the object-storage gap).
      expect(seenBody?['storageKey'], startsWith('device/'));
    });

    testWidgets('a real server rejection shows a real error, not a faked success',
        (tester) async {
      final MockClient mock = MockClient((http.Request req) async =>
          http.Response(jsonEncode({'error': 'not_authorized'}), 403));

      await tester.pumpWidget(wrap(ReceiptScreen(
        childName: 'Ivy', senderName: 'Dad',
        watchedAtLabel: '7:04 AM', dayPartKind: 'before_school',
        baseUrl: 'http://api.test', childId: 'child-a', sessionToken: 'tok-1',
        httpClient: mock, pickVideo: () async => _fakeClip(),
      )));

      await tester.tap(find.text('Send one back'));
      await tester.pumpAndSettle();

      expect(find.text('Sent!'), findsNothing);
      expect(find.textContaining('403'), findsOneWidget);
      expect(find.textContaining('not_authorized'), findsOneWidget);
      // Recoverable — a real retry affordance, not a dead end.
      expect(find.text('Try again'), findsOneWidget);
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
        httpClient: mock, pickVideo: () async => null,
      )));

      await tester.tap(find.text('Send one back'));
      await tester.pumpAndSettle();

      expect(requestMade, isFalse);
      expect(find.text('Send one back'), findsOneWidget);
      expect(find.textContaining('error'), findsNothing);
    });
  });
}
