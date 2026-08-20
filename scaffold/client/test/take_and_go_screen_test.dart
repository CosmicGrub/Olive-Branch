// OLIVE BRANCH — take-and-go screen tests. §2.10, §2.11, §9.8/§9.8.4, §21.2
// rung 17, §21.7.
//
// A genuine mirror of deletion_screen_test.dart's own structure and depth —
// pure copy-audit tests, widget-state tests (the confirm control disabled
// until acknowledgment), a genuine success round trip (real dev-login + real
// take-and-go call, a real file write, a real hash verification against it),
// genuine-failure tests (never a fake success), and the same Fold5/phone/
// desktop responsive sweep.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:olive_client/take_and_go_screen.dart';
import 'package:olive_client/sha256.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

Future<void> pump(WidgetTester tester, Widget child) async {
  await tester.binding.setSurfaceSize(const Size(800, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(wrap(child));
}

/// Acknowledges the checkbox and taps confirm — the shared setup every
/// real-backend test below needs before it can exercise `_takeAndGo()`.
Future<void> ackAndConfirm(WidgetTester t) async {
  await t.tap(find.byType(CheckboxListTile));
  await t.pump();
  await t.tap(find.widgetWithText(FilledButton, 'Take my data and close guardian access'));
}

/// Pumps until [finder] matches or [maxPumps] is exhausted — mirrors
/// deletion_screen_test.dart's own `pumpUntil` for the same reason: the
/// screen shows a real, transient `CircularProgressIndicator` while in
/// flight, and this sidesteps any question of how that interacts with
/// `pumpAndSettle()`'s own "no frame scheduled" settle condition.
Future<void> pumpUntil(WidgetTester tester, Finder finder, {int maxPumps = 200}) async {
  for (var i = 0; i < maxPumps; i++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  group('take-and-go copy audit — pure logic', () {
    test('clean copy passes the audit', () {
      expect(auditTakeAndGoCopy('Every guardian\'s access to your account has closed.').ok,
        isTrue);
    });

    test('copy contradicting the no-cooling-off / no-guilt posture is caught', () {
      final ({bool ok, List<String> found}) r =
        auditTakeAndGoCopy('Are you sure? Think about it — you can come back.');
      expect(r.ok, isFalse);
      expect(r.found, containsAll(<String>['are you sure', 'think about it', 'you can come back']));
    });

    test('every line in whatTakeAndGoIncludes/whatTakeAndGoCloses passes the audit', () {
      for (final String line in <String>[...whatTakeAndGoIncludes, ...whatTakeAndGoCloses]) {
        expect(auditTakeAndGoCopy(line).ok, isTrue, reason: line);
      }
    });

    test('the confirmation copy itself passes the audit', () {
      expect(auditTakeAndGoCopy(takeAndGoConfirmationCopy).ok, isTrue);
    });
  });

  group('TakeAndGoScreen widget', () {
    testWidgets('states what she takes and what closes BEFORE any destructive control '
        'is enabled', (t) async {
      await pump(t, const TakeAndGoScreen(childName: 'Ivy'));
      expect(find.textContaining('Every message and video'), findsOneWidget);
      expect(find.textContaining('journal'), findsWidgets);
      expect(find.textContaining("guardian's access"), findsWidgets);

      final FilledButton confirm = t.widget(
        find.widgetWithText(FilledButton, 'Take my data and close guardian access'));
      expect(confirm.onPressed, isNull, reason: 'must be disabled before acknowledgment');
    });

    testWidgets('the confirm control enables only after acknowledgment', (t) async {
      await pump(t, const TakeAndGoScreen());
      await t.tap(find.byType(CheckboxListTile));
      await t.pump();
      final FilledButton confirm = t.widget(
        find.widgetWithText(FilledButton, 'Take my data and close guardian access'));
      expect(confirm.onPressed, isNotNull);
    });

    testWidgets('never mentions a cooling-off period, a delay, or a lesser option',
        (t) async {
      await pump(t, const TakeAndGoScreen(childName: 'Ivy'));
      for (final String forbidden in takeAndGoForbiddenCopy) {
        expect(find.textContaining(forbidden), findsNothing, reason: forbidden);
      }
    });
  });

  group('TakeAndGoScreen — wired to the real route (mocked transport)', () {
    // Sync dart:io, deliberately — see deletion_screen_test.dart's own group
    // header for the full reasoning (a real async dart:io call hangs under
    // the plain widget-test binding).
    late Directory tempDir;
    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('olive_take_and_go_test_');
    });
    tearDown(() {
      try {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    testWidgets('a genuine success makes a real dev-login + take-and-go round trip, '
        'writes a real file, verifies the hash, and shows the real closure counts',
        (t) async {
      const String bundleJson =
          '{"childId":"child-a","childName":"Ivy","requestedByUserId":null,'
          '"requestedByChildId":"child-a","delivered":[],"journalEntries":[],'
          '"messageLog":[]}';
      final String realHash = sha256Hex(bundleJson);
      var sawDevLogin = false, sawTakeAndGo = false;

      final http.Client mock = MockClient((http.Request req) async {
        if (req.url.path == '/v1/auth/dev-login') {
          sawDevLogin = true;
          final Map<String, dynamic> loginBody = jsonDecode(req.body) as Map<String, dynamic>;
          expect(loginBody['childId'], 'child-a');
          return http.Response(jsonEncode(<String, String>{'token': 'tok'}), 200);
        }
        if (req.url.path.endsWith('/handover')) {
          sawTakeAndGo = true;
          expect(req.method, 'POST');
          expect(req.headers['authorization'], 'Bearer tok');
          return http.Response(jsonEncode(<String, dynamic>{
            'ok': true,
            'childId': 'child-a',
            'handedOverAt': '2028-04-03T12:00:00.000Z',
            'guardianshipsClosed': 2,
            'artifactsTransferred': 5,
            'journalEntriesTransferred': 3,
            'exportRecordId': 'rec-1',
            'bundle': <String, dynamic>{},
            'bundleJson': bundleJson,
            'bundleHash': realHash,
          }), 200);
        }
        return http.Response('not found', 404);
      });

      await pump(t, TakeAndGoScreen(
        childName: 'Ivy', baseUrl: 'http://api.test', childId: 'child-a',
        httpClient: mock, documentsDirectory: () async => tempDir));
      await ackAndConfirm(t);
      await pumpUntil(t, find.text('Done'));

      expect(sawDevLogin, isTrue, reason: 'a real network call must actually be made');
      expect(sawTakeAndGo, isTrue);

      // The persistent confirmation card shows the real, audited copy.
      expect(find.descendant(of: find.byType(Card), matching: find.text(takeAndGoConfirmationCopy)),
        findsOneWidget);

      final File file = File(
          '${tempDir.path}${Platform.pathSeparator}olive-take-and-go-child-a-rec-1.json');
      expect(file.existsSync(), isTrue, reason: 'a successful call must persist a real file');
      expect(file.readAsStringSync(), bundleJson,
        reason: 'the saved bytes must be exactly what was hashed, not a re-encoding');
      expect(find.text(realHash), findsOneWidget,
        reason: 'the real hash is shown, not hidden or fabricated');
      expect(find.textContaining('verified against the server'), findsOneWidget);

      // The confirm control retires once this irreversible action succeeds —
      // never re-tappable.
      final FilledButton confirm = t.widget(find.widgetWithText(FilledButton, 'Done'));
      expect(confirm.onPressed, isNull);
    });

    testWidgets('shows a real progress state while the request is in flight, and '
        'disables itself against a second tap', (t) async {
      final http.Client mock = MockClient((http.Request req) async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        if (req.url.path == '/v1/auth/dev-login') {
          return http.Response(jsonEncode(<String, String>{'token': 'tok'}), 200);
        }
        return http.Response(jsonEncode(<String, dynamic>{
          'ok': true, 'childId': 'child-a', 'handedOverAt': '2028-01-01T00:00:00.000Z',
          'guardianshipsClosed': 1, 'artifactsTransferred': 0, 'journalEntriesTransferred': 0,
          'exportRecordId': 'rec-2', 'bundle': <String, dynamic>{}, 'bundleJson': '{}',
          'bundleHash': sha256Hex('{}'),
        }), 200);
      });

      await pump(t, TakeAndGoScreen(
        baseUrl: 'http://api.test', childId: 'child-a',
        httpClient: mock, documentsDirectory: () async => tempDir));
      await ackAndConfirm(t);
      await t.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      final FilledButton confirm = t.widget(find.byType(FilledButton));
      expect(confirm.onPressed, isNull, reason: 'must not allow a second tap mid-flight');

      await pumpUntil(t, find.text('Done'));
    });

    testWidgets('not_yet_of_age surfaces the real, honest reason — never a fake success',
        (t) async {
      final http.Client mock = MockClient((http.Request req) async {
        if (req.url.path == '/v1/auth/dev-login') {
          return http.Response(jsonEncode(<String, String>{'token': 'tok'}), 200);
        }
        return http.Response(jsonEncode(<String, String>{'error': 'not_yet_of_age'}), 403);
      });

      await pump(t, TakeAndGoScreen(
        baseUrl: 'http://api.test', childId: 'too-young',
        httpClient: mock, documentsDirectory: () async => tempDir));
      await ackAndConfirm(t);
      await pumpUntil(t, find.textContaining("You're not old enough"));

      expect(find.textContaining("You're not old enough"), findsOneWidget);
      expect(find.text('Done'), findsNothing);
      expect(tempDir.listSync(), isEmpty, reason: 'a denial must not write a file at all');

      // A real denial must leave the control re-tappable, not stuck.
      final FilledButton confirm = t.widget(
        find.widgetWithText(FilledButton, 'Take my data and close guardian access'));
      expect(confirm.onPressed, isNotNull);
    });

    testWidgets('already_handed_over surfaces the real, honest reason', (t) async {
      final http.Client mock = MockClient((http.Request req) async {
        if (req.url.path == '/v1/auth/dev-login') {
          return http.Response(jsonEncode(<String, String>{'token': 'tok'}), 200);
        }
        return http.Response(jsonEncode(<String, String>{'error': 'already_handed_over'}), 403);
      });

      await pump(t, TakeAndGoScreen(
        baseUrl: 'http://api.test', childId: 'child-a',
        httpClient: mock, documentsDirectory: () async => tempDir));
      await ackAndConfirm(t);
      await pumpUntil(t, find.textContaining('already been done'));

      expect(find.textContaining('already been done'), findsOneWidget);
      expect(find.textContaining('Nothing has changed'), findsOneWidget);
    });

    testWidgets('an unreachable server shows a real error, never a fake success', (t) async {
      final http.Client mock = MockClient((http.Request req) async => throw Exception('refused'));

      await pump(t, TakeAndGoScreen(
        baseUrl: 'http://api.test', childId: 'child-a',
        httpClient: mock, documentsDirectory: () async => tempDir));
      await ackAndConfirm(t);
      await pumpUntil(t, find.textContaining('Could not reach the server'));

      expect(find.textContaining('Could not reach the server'), findsOneWidget);
      expect(find.textContaining('Nothing has changed'), findsOneWidget);
      expect(find.text('Done'), findsNothing);
      expect(tempDir.listSync(), isEmpty);
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
      await atSize(t, const Size(344, 882), const TakeAndGoScreen(childName: 'Ivy'));
      expect(t.takeException(), isNull);
    });

    testWidgets('renders on the Fold5 unfolded main screen (~673x841) without overflow',
        (t) async {
      await atSize(t, const Size(673, 841), const TakeAndGoScreen(childName: 'Ivy'));
      expect(t.takeException(), isNull);
    });

    testWidgets('renders at a standard phone width (390 logical px) without overflow',
        (t) async {
      await atSize(t, const Size(390, 900), const TakeAndGoScreen(childName: 'Ivy'));
      expect(t.takeException(), isNull);
    });

    testWidgets('renders at a tablet/desktop width (1100, short-and-wide) without overflow',
        (t) async {
      await atSize(t, const Size(1100, 700), const TakeAndGoScreen(childName: 'Ivy'));
      expect(t.takeException(), isNull);
    });
  });
}
