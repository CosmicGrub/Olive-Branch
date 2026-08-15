// OLIVE BRANCH — deletion screen tests. §2.10, §2.11, §9.8, P8, §16.1 #3.
//
// The invariant: what deletion means is stated BEFORE any destructive
// control is reachable, and confirming never CLAIMS success it did not get
// — a real backend exists now (server/routes.mjs's POST /v1/me/delete), so
// this file proves both directions for real: a genuine success shows real
// confirmation copy that still passes the audit, and a genuine failure
// (wrong session, unreachable server) shows a real error rather than a
// fake success. Raw export (`_export()`) is likewise wired to a real route
// (server/routes.mjs's `GET /v1/children/:childId/export`) — its own tests
// below exercise that real network round trip through a MockClient (mirrors
// child_home_live_test.dart's own pattern) and a real (temp-directory) file
// write, rather than asserting a placeholder message.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:olive_client/deletion_screen.dart';
import 'package:olive_client/sha256.dart';

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

/// Pumps until [finder] matches or [maxPumps] is exhausted — used instead of
/// `pumpAndSettle()` for `_export()`'s async flow below. `_export()`
/// transiently shows a real indeterminate `CircularProgressIndicator`
/// (`_exporting`) while in flight; polling for the concrete expected outcome
/// sidesteps any question of whether that interacts badly with
/// `pumpAndSettle()`'s own "no frame scheduled" settle condition, and fails
/// via a plain, readable `expect()` if the outcome never arrives rather than
/// via a generic framework timeout.
Future<void> pumpUntil(WidgetTester tester, Finder finder, {int maxPumps = 200}) async {
  for (var i = 0; i < maxPumps; i++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 50));
  }
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
    });
  });

  group('DeletionScreen raw export — wired to the real route (mocked transport)', () {
    // Sync dart:io, deliberately, both here and in `_export()`'s own file
    // write (`file.writeAsStringSync`, deletion_screen.dart): a REAL async
    // dart:io call (`Directory.createTemp`, `File.writeAsString`, ...) made
    // from inside a `testWidgets` body hangs indefinitely under the plain
    // `AutomatedTestWidgetsFlutterBinding` used here — confirmed directly
    // this session by isolating it to a two-line repro (an `await
    // Directory.systemTemp.createTemp(...)` with nothing else around it
    // hung for the full 10-minute test timeout; swapping it for
    // `createTempSync` fixed it instantly). Flutter's own docs name the
    // proper fix as `tester.runAsync(...)` for tests that must keep the
    // operation genuinely asynchronous; the sync variant is simpler and
    // sufficient here since these are small, one-shot local writes, not
    // something a real app would want to keep off the UI thread for long.
    late Directory tempDir;
    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('olive_export_test_');
    });
    tearDown(() {
      // Best-effort: on Windows a just-written file can still be
      // momentarily locked by the OS immediately after a test — a
      // filesystem-timing artifact of the test harness, not a defect in
      // `_export()` itself, so it must not fail an unrelated test.
      try {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    testWidgets('a successful export makes a real dev-login + export round trip, '
        'writes a real file, and verifies the hash against it — not a placeholder',
        (t) async {
      // Exactly the JSON string a real sha256 was computed over server-side
      // (packages/db/src/pool.mjs's rawExportBundleFor) — see api_client
      // .dart's fetchRawExport doc comment on why `bundleJson`, not `bundle`,
      // is what gets hashed/written.
      const String bundleJson =
          '{"childId":"child-a","childName":"Ivy","delivered":[],'
          '"journalEntries":[],"messageLog":[]}';
      final String realHash = sha256Hex(bundleJson);
      var sawDevLogin = false, sawExport = false;

      final http.Client mock = MockClient((http.Request req) async {
        if (req.url.path == '/v1/auth/dev-login') {
          sawDevLogin = true;
          final Map<String, dynamic> loginBody =
              jsonDecode(req.body) as Map<String, dynamic>;
          expect(loginBody['userId'], isNotEmpty);
          return http.Response(jsonEncode(<String, String>{'token': 'tok'}), 200);
        }
        if (req.url.path.endsWith('/export')) {
          sawExport = true;
          expect(req.headers['authorization'], 'Bearer tok');
          return http.Response(jsonEncode(<String, dynamic>{
            'bundle': <String, dynamic>{},
            'bundleJson': bundleJson,
            'exportRecordId': 'rec-1',
            'bundleHash': realHash,
          }), 200);
        }
        return http.Response('not found', 404);
      });

      await pump(t, DeletionScreen(
        childName: 'Ivy', baseUrl: 'http://api.test', childId: 'child-a',
        httpClient: mock, documentsDirectory: () async => tempDir));
      await t.tap(find.textContaining('Download'));
      await pumpUntil(t, find.text('Raw export saved'));

      expect(sawDevLogin, isTrue, reason: 'a real network call must actually be made');
      expect(sawExport, isTrue);
      expect(find.text('Raw export saved'), findsOneWidget,
        reason: 'a hash that verifies must say so, not just "saved"');

      final File file = File(
          '${tempDir.path}${Platform.pathSeparator}olive-raw-export-child-a-rec-1.json');
      // Sync — see the group's own header comment on why: real async dart:io
      // calls hang under this test binding.
      expect(file.existsSync(), isTrue, reason: 'the button must persist a real file');
      expect(file.readAsStringSync(), bundleJson,
        reason: 'the saved bytes must be exactly what was hashed, not a re-encoding');
      expect(find.text(realHash), findsOneWidget,
        reason: 'the real hash is shown, not hidden or fabricated');

      // Dismiss — `_export()`'s `await showDialog(...)` only resolves once
      // the route is popped; leaving it open would leave that Future (and
      // the test) hanging forever rather than a normal pass/fail.
      await t.tap(find.text('Done'));
      await t.pump();
    });

    testWidgets('a mismatched hash is reported as unverified, never silently accepted',
        (t) async {
      const String bundleJson = '{"childId":"child-a"}';
      final http.Client mock = MockClient((http.Request req) async {
        if (req.url.path == '/v1/auth/dev-login') {
          return http.Response(jsonEncode(<String, String>{'token': 'tok'}), 200);
        }
        return http.Response(jsonEncode(<String, dynamic>{
          'bundle': <String, dynamic>{},
          'bundleJson': bundleJson,
          'exportRecordId': 'rec-2',
          'bundleHash': '0' * 64, // deliberately wrong
        }), 200);
      });

      await pump(t, DeletionScreen(
        baseUrl: 'http://api.test', childId: 'child-a',
        httpClient: mock, documentsDirectory: () async => tempDir));
      await t.tap(find.textContaining('Download'));
      await pumpUntil(t, find.text('Saved — hash did not verify'));

      expect(find.text('Saved — hash did not verify'), findsOneWidget);
      expect(find.text('Raw export saved'), findsNothing);

      await t.tap(find.text('Done'));
      await t.pump();
    });

    testWidgets('a server denial (e.g. no live guardian edge) surfaces honestly, '
        'never a fake success', (t) async {
      final http.Client mock = MockClient((http.Request req) async {
        if (req.url.path == '/v1/auth/dev-login') {
          return http.Response(jsonEncode(<String, String>{'token': 'tok'}), 200);
        }
        return http.Response(jsonEncode(<String, String>{'error': 'no_edge'}), 403);
      });

      await pump(t, DeletionScreen(
        baseUrl: 'http://api.test', childId: 'someone-elses-child',
        httpClient: mock, documentsDirectory: () async => tempDir));
      await t.tap(find.textContaining('Download'));
      await pumpUntil(t, find.textContaining('Raw export failed'));

      expect(find.textContaining('Raw export failed'), findsOneWidget);
      expect(find.textContaining('no_edge'), findsOneWidget);
      expect(find.text('Raw export saved'), findsNothing);
      expect(tempDir.listSync(), isEmpty,
        reason: 'a denied export must not write a file at all');
    });

    testWidgets('the button shows a real in-flight state and disables itself while exporting',
        (t) async {
      final http.Client mock = MockClient((http.Request req) async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        if (req.url.path == '/v1/auth/dev-login') {
          return http.Response(jsonEncode(<String, String>{'token': 'tok'}), 200);
        }
        return http.Response(jsonEncode(<String, dynamic>{
          'bundle': <String, dynamic>{}, 'bundleJson': '{}',
          'exportRecordId': 'rec-3', 'bundleHash': sha256Hex('{}'),
        }), 200);
      });

      await pump(t, DeletionScreen(
        baseUrl: 'http://api.test', childId: 'child-a',
        httpClient: mock, documentsDirectory: () async => tempDir));
      await t.tap(find.textContaining('Download'));
      await t.pump();

      expect(find.text('Exporting…'), findsOneWidget);
      final OutlinedButton btn = t.widget(find.byType(OutlinedButton));
      expect(btn.onPressed, isNull, reason: 'must not allow a second tap mid-flight');

      await pumpUntil(t, find.text('Raw export saved'));
      expect(find.text('Raw export saved'), findsOneWidget);

      await t.tap(find.text('Done'));
      await t.pump();
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
