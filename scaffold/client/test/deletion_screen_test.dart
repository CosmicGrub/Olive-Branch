// OLIVE BRANCH — deletion screen tests. §2.10, §2.11, §9.8, P8.
//
// The invariant: what deletion means is stated BEFORE any destructive
// control is reachable, and confirming never CLAIMS success it did not get
// — a real backend exists now (server/routes.mjs's POST /v1/me/delete), so
// this file proves both directions for real: a genuine success shows real
// confirmation copy that still passes the audit, and a genuine failure
// (wrong session, unreachable server) shows a real error rather than a
// fake success.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:olive_client/deletion_screen.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

Future<void> pump(WidgetTester tester, Widget child) async {
  await tester.binding.setSurfaceSize(const Size(800, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(wrap(child));
}

/// Acknowledges the retention checkbox and taps confirm — the shared setup
/// every real-backend test below needs before it can exercise `_confirm()`.
Future<void> ackAndConfirm(WidgetTester t) async {
  await t.tap(find.byType(CheckboxListTile));
  await t.pump();
  await t.tap(find.widgetWithText(FilledButton, 'Delete my account'));
}

void main() {
  group('deletion copy audit — pure logic', () {
    test('clean copy passes the audit', () {
      expect(auditDeletionCopy('Delivered messages belong to her, not to the account '
        'that sent them.').ok, isTrue);
    });

    test('copy contradicting §2.10/§2.11/P8 is caught', () {
      final ({bool ok, List<String> found}) r =
        auditDeletionCopy('This wipes her archive and removes the log for good.');
      expect(r.ok, isFalse);
      expect(r.found, containsAll(<String>['wipes her archive', 'removes the log']));
    });

    test('every fact in whatDeletionKeeps passes the audit', () {
      for (final RetentionFact f in whatDeletionKeeps) {
        expect(auditDeletionCopy(f.why).ok, isTrue, reason: f.why);
      }
    });
  });

  group('DeletionScreen widget', () {
    testWidgets('states what survives BEFORE any destructive control is enabled',
        (t) async {
      await pump(t, const DeletionScreen(childName: 'Ivy'));
      expect(find.textContaining('Delivered messages'), findsOneWidget);
      expect(find.textContaining('belong to her'), findsOneWidget);
      expect(find.textContaining('Cannot be deleted or edited'), findsOneWidget);

      final FilledButton confirm =
        t.widget(find.widgetWithText(FilledButton, 'Delete my account'));
      expect(confirm.onPressed, isNull, reason: 'must be disabled before acknowledgment');
    });

    testWidgets('the confirm control enables only after acknowledgment', (t) async {
      await pump(t, const DeletionScreen());
      await t.tap(find.byType(CheckboxListTile));
      await t.pump();
      final FilledButton confirm =
        t.widget(find.widgetWithText(FilledButton, 'Delete my account'));
      expect(confirm.onPressed, isNotNull);
    });

    testWidgets('a genuine success shows real confirmation copy that passes the audit',
        (t) async {
      final mock = MockClient((req) async {
        expect(req.method, 'POST');
        expect(req.url.path, '/v1/me/delete');
        expect(req.headers['authorization'], 'Bearer tok-123');
        return http.Response(jsonEncode({
          'ok': true, 'userId': 'u1', 'cancelledDeliveryIntents': 2,
          'removedPinCredentials': 1, 'removedWebauthnCredentials': 1,
          'removedWebauthnChallenges': 0,
        }), 200);
      });
      await pump(t, DeletionScreen(
        childName: 'Ivy', baseUrl: 'http://api.test', sessionToken: 'tok-123', httpClient: mock));
      await ackAndConfirm(t);
      await t.pumpAndSettle();

      // Real success copy is shown, and it passes the very audit that gates
      // whatDeletionKeeps — a real backend must not slip into forbidden
      // language any more than the old stub could.
      for (final String claim in deletionForbiddenClaims) {
        expect(find.textContaining(claim), findsNothing, reason: claim);
      }
      expect(find.text('Account deleted'), findsOneWidget);
      // The SAME copy is shown twice by design (the transient SnackBar and
      // the persistent card share one string — see deletion_screen.dart's
      // own comment on why). Target the persistent CARD specifically so
      // this assertion is about the durable on-screen record, not about
      // whether the SnackBar happens to still be visible when this runs.
      expect(find.descendant(of: find.byType(Card), matching: find.text(deletionConfirmationCopy)),
        findsOneWidget);

      // The confirm control retires once the account is actually gone —
      // it must not be re-tappable.
      final FilledButton confirm =
        t.widget(find.widgetWithText(FilledButton, 'Account deleted'));
      expect(confirm.onPressed, isNull);
    });

    testWidgets('shows a real progress state while the request is in flight', (t) async {
      final mock = MockClient((req) async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return http.Response(jsonEncode({'ok': true, 'userId': 'u1'}), 200);
      });
      await pump(t, DeletionScreen(
        baseUrl: 'http://api.test', sessionToken: 'tok-123', httpClient: mock));
      await ackAndConfirm(t);
      await t.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await t.pumpAndSettle();
    });

    testWidgets('a genuine failure (wrong/expired session) shows a real error, '
        'never a fake success', (t) async {
      final mock = MockClient((req) async =>
          http.Response(jsonEncode({'error': 'no_session'}), 401));
      await pump(t, DeletionScreen(
        baseUrl: 'http://api.test', sessionToken: '', httpClient: mock));
      await ackAndConfirm(t);
      await t.pumpAndSettle();

      expect(find.textContaining('Could not delete your account'), findsOneWidget);
      expect(find.textContaining('no_session'), findsOneWidget);
      expect(find.textContaining('Nothing has changed'), findsOneWidget);
      expect(find.text('Account deleted'), findsNothing);

      // A real failure must leave the control re-tappable, not stuck.
      final FilledButton confirm =
        t.widget(find.widgetWithText(FilledButton, 'Delete my account'));
      expect(confirm.onPressed, isNotNull);
    });

    testWidgets('an unreachable server shows a real error, never a fake success', (t) async {
      final mock = MockClient((req) async => throw Exception('connection refused'));
      await pump(t, DeletionScreen(
        baseUrl: 'http://api.test', sessionToken: 'tok-123', httpClient: mock));
      await ackAndConfirm(t);
      await t.pumpAndSettle();

      expect(find.textContaining('Could not reach the server'), findsOneWidget);
      expect(find.textContaining('Nothing has changed'), findsOneWidget);
      expect(find.text('Account deleted'), findsNothing);
    });

    testWidgets('raw export is offered as free and unlimited, never a paywall',
        (t) async {
      await pump(t, const DeletionScreen(childName: 'Ivy'));
      expect(find.textContaining('free, unlimited, every tier'), findsOneWidget);
      await t.tap(find.textContaining('Download'));
      await t.pump();
      expect(find.textContaining('When it exists it is free'), findsOneWidget);
    });
  });

  group('responsive — Fold5 cover/main, phone, and desktop widths', () {
    Future<void> atSize(WidgetTester t, Size size, Widget child) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(wrap(child));
      await t.pumpAndSettle();
    }

    testWidgets('renders on the Fold5 cover-screen width (344 CSS px) without overflow',
        (t) async {
      await atSize(t, const Size(344, 882), const DeletionScreen(childName: 'Ivy'));
      expect(t.takeException(), isNull);
    });

    testWidgets('renders on the Fold5 unfolded main screen (~673x841) without overflow',
        (t) async {
      await atSize(t, const Size(673, 841), const DeletionScreen(childName: 'Ivy'));
      expect(t.takeException(), isNull);
    });

    testWidgets('renders at a standard phone width (390 logical px) without overflow',
        (t) async {
      await atSize(t, const Size(390, 900), const DeletionScreen(childName: 'Ivy'));
      expect(t.takeException(), isNull);
    });

    testWidgets('renders at a tablet/desktop width (1100, short-and-wide) without overflow',
        (t) async {
      await atSize(t, const Size(1100, 700), const DeletionScreen(childName: 'Ivy'));
      expect(t.takeException(), isNull);
    });
  });
}
