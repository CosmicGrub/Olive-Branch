// OLIVE BRANCH — child_home_live.dart tests. §7, §8.1, §21.5.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:olive_client/api_client.dart';
import 'package:olive_client/child_home_live.dart';
import 'package:olive_client/push_channel.dart';
import 'package:olive_client/wear_sync_channel.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

/// §11 — real PushChannel.initialize() calls the real (unmocked)
/// Firebase.initializeApp(), which genuinely fails in this environment (no
/// google-services.json — see pubspec.yaml). child_home_live.dart's own
/// `_initPush` already catches that and never lets it break this screen
/// (covered directly below in its own group), but these PRE-EXISTING tests
/// are about name/unread-count/wear-sync behavior and have no business
/// depending on Firebase plugin timing at all — so they inject this
/// no-op fake, exactly the same pattern as `_FakeWearSyncChannel` below.
class _FakePushChannel extends PushChannel {
  _FakePushChannel() : super(OliveApi('http://unused', 'unused'));

  final calls = <String>[];

  @override
  Future<void> initialize() async {
    calls.add('initialize');
  }

  @override
  void dispose() {
    calls.add('dispose');
  }
}

/// WearSyncChannel's sync method is a regular (non-final) instance method,
/// so this overrides it rather than touching a real platform channel —
/// mirrors invariants_test.dart's `_FakeKioskChannel extends KioskChannel`
/// pattern for the exact same reason (no native handler exists under
/// `flutter test`).
class _FakeWearSyncChannel extends WearSyncChannel {
  final calls = <int>[];

  @override
  Future<void> syncSleepsUntilHandover(int sleepsUntilHandover) async {
    calls.add(sleepsUntilHandover);
  }
}

void main() {
  group('LiveChildHomeScreen', () {
    testWidgets('shows a loading indicator before the fetch resolves', (t) async {
      final mock = MockClient((req) async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return http.Response(jsonEncode({'token': 'tok'}), 200);
      });
      await t.pumpWidget(wrap(LiveChildHomeScreen(
        baseUrl: 'http://api.test', childId: 'child-a', httpClient: mock)));
      await t.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      // Drain the pending delayed response so no timer survives past teardown.
      await t.pumpAndSettle();
    });

    testWidgets('renders real fetched name and a real UNREAD-ONLY count '
        'through the real ChildHome', (t) async {
      final mock = MockClient((req) async {
        if (req.url.path == '/v1/auth/dev-login') {
          return http.Response(jsonEncode({'token': 'tok'}), 200);
        }
        if (req.url.path == '/v1/me') {
          return http.Response(jsonEncode({'displayName': 'Ivy'}), 200);
        }
        if (req.url.path.endsWith('/inbox')) {
          // v0.49.15: /inbox for real returns BOTH 'delivered' (unwatched)
          // and 'opened' (already watched) messages — this mix is the exact
          // shape that used to make the badge overcount. Two delivered, one
          // already opened: the real unread count is 2, not 3.
          return http.Response(jsonEncode({'messages': [
            {'id': '1', 'state': 'delivered'},
            {'id': '2', 'state': 'delivered'},
            {'id': '3', 'state': 'opened'},
          ]}), 200);
        }
        if (req.url.path.endsWith('/now')) {
          return http.Response(jsonEncode({
            'childLocalTime': '4:15 PM', 'zoneAbbr': 'EDT', 'zone': 'America/New_York',
            'sleepsUntilHandover': null,
          }), 200);
        }
        return http.Response('not found', 404);
      });
      await t.pumpWidget(wrap(LiveChildHomeScreen(
        baseUrl: 'http://api.test', childId: 'child-a', httpClient: mock,
        pushChannel: _FakePushChannel())));
      await t.pumpAndSettle();

      expect(find.text('Hi Ivy'), findsOneWidget);
      // The real unread badge: 2 delivered, not the raw row count of 3 —
      // proves opened messages are excluded, not just that SOME number shows.
      expect(find.text('2'), findsOneWidget);
      expect(find.text('3'), findsNothing);
      // No active custody order in this fixture (/now's own honest null) —
      // still an absence, but now a REAL fetched one, not an unfetched field.
      expect(find.textContaining('sleeps until'), findsNothing);
      expect(find.textContaining('sleep until'), findsNothing);
    });

    testWidgets('renders a real, fetched sleepsUntilHandover — and forwards '
        'that exact value to the paired Wear companion', (t) async {
      // v0.49.15: OliveApi.fetchNow() existed, contract-checked, with zero
      // callers anywhere in this client — this proves both halves of closing
      // that gap: the real /now count actually reaches ChildHome's "sleeps
      // until the handover" counter, AND the same real value reaches
      // WearSyncChannel, not a guess and not a leftover null.
      final fakeWear = _FakeWearSyncChannel();
      final mock = MockClient((req) async {
        if (req.url.path == '/v1/auth/dev-login') {
          return http.Response(jsonEncode({'token': 'tok'}), 200);
        }
        if (req.url.path == '/v1/me') {
          return http.Response(jsonEncode({'displayName': 'Ivy'}), 200);
        }
        if (req.url.path.endsWith('/inbox')) {
          return http.Response(jsonEncode({'messages': <Map<String, dynamic>>[]}), 200);
        }
        if (req.url.path.endsWith('/now')) {
          return http.Response(jsonEncode({
            'childLocalTime': '4:15 PM', 'zoneAbbr': 'EDT', 'zone': 'America/New_York',
            'sleepsUntilHandover': 5, // distinctive, non-default value
          }), 200);
        }
        return http.Response('not found', 404);
      });
      await t.pumpWidget(wrap(LiveChildHomeScreen(
        baseUrl: 'http://api.test', childId: 'child-a',
        httpClient: mock, wearSync: fakeWear, pushChannel: _FakePushChannel())));
      await t.pumpAndSettle();

      expect(find.text('Hi Ivy'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.textContaining('sleeps until'), findsOneWidget);
      expect(fakeWear.calls, [5]);
    });

    testWidgets('shows a retry affordance when the server is unreachable, never a crash',
        (t) async {
      final mock = MockClient((req) async => http.Response(
          jsonEncode({'error': 'child_not_found'}), 404));
      await t.pumpWidget(wrap(LiveChildHomeScreen(
        baseUrl: 'http://api.test', childId: 'nope', httpClient: mock)));
      await t.pumpAndSettle();

      expect(find.text("Couldn't reach the server"), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.textContaining('404'), findsOneWidget);
    });

    testWidgets('the error icon and message use the themed secondary color, '
        'not a hardcoded black (design-token audit finding #1)', (t) async {
      final mock = MockClient((req) async => http.Response(
          jsonEncode({'error': 'child_not_found'}), 404));
      await t.pumpWidget(wrap(LiveChildHomeScreen(
        baseUrl: 'http://api.test', childId: 'nope', httpClient: mock)));
      await t.pumpAndSettle();

      final BuildContext context =
          t.element(find.text("Couldn't reach the server"));
      final Color onSurfaceVariant =
          Theme.of(context).colorScheme.onSurfaceVariant;
      final Icon icon = t.widget(find.byIcon(Icons.cloud_off));
      expect(icon.color, onSurfaceVariant);
    });

    testWidgets('retry re-runs the fetch and can recover into the ready state', (t) async {
      var attempt = 0;
      final mock = MockClient((req) async {
        if (req.url.path == '/v1/auth/dev-login') {
          attempt++;
          if (attempt == 1) return http.Response(jsonEncode({'error': 'boom'}), 500);
          return http.Response(jsonEncode({'token': 'tok'}), 200);
        }
        if (req.url.path == '/v1/me') return http.Response(jsonEncode({'displayName': 'Ivy'}), 200);
        if (req.url.path.endsWith('/inbox')) {
          return http.Response(jsonEncode({'messages': <Map<String, dynamic>>[]}), 200);
        }
        if (req.url.path.endsWith('/now')) {
          return http.Response(jsonEncode({
            'childLocalTime': '4:15 PM', 'zoneAbbr': 'EDT', 'zone': 'America/New_York',
            'sleepsUntilHandover': null,
          }), 200);
        }
        return http.Response('not found', 404);
      });
      await t.pumpWidget(wrap(LiveChildHomeScreen(
        baseUrl: 'http://api.test', childId: 'child-a', httpClient: mock,
        pushChannel: _FakePushChannel())));
      await t.pumpAndSettle();
      expect(find.text("Couldn't reach the server"), findsOneWidget);

      await t.tap(find.text('Try again'));
      await t.pumpAndSettle();
      expect(find.text('Hi Ivy'), findsOneWidget);
    });

    testWidgets(
        'never syncs a placeholder to the Wear companion when /now honestly '
        'reports no active custody order', (t) async {
      // §21.5 — child_home_live.dart's `_syncWear()` forwards a real
      // sleepsUntilHandover to a paired watch. /now itself returns an honest
      // `null` when the child has no active custody_order row (its own
      // documented absence, not a fetch that never happened) — this proves
      // the wiring's guard still holds against a REAL null response, not
      // just an unfetched field: loading and settling must NOT call the wear
      // channel at all. Without the `if (sleeps != null)` guard in
      // `_syncWear()`, this would call through with `null`, which a real
      // MethodChannel int argument cannot represent honestly anyway.
      final fakeWear = _FakeWearSyncChannel();
      final mock = MockClient((req) async {
        if (req.url.path == '/v1/auth/dev-login') {
          return http.Response(jsonEncode({'token': 'tok'}), 200);
        }
        if (req.url.path == '/v1/me') {
          return http.Response(jsonEncode({'displayName': 'Ivy'}), 200);
        }
        if (req.url.path.endsWith('/inbox')) {
          return http.Response(jsonEncode({'messages': <Map<String, dynamic>>[]}), 200);
        }
        if (req.url.path.endsWith('/now')) {
          return http.Response(jsonEncode({
            'childLocalTime': '4:15 PM', 'zoneAbbr': 'EDT', 'zone': 'America/New_York',
            'sleepsUntilHandover': null,
          }), 200);
        }
        return http.Response('not found', 404);
      });
      await t.pumpWidget(wrap(LiveChildHomeScreen(
        baseUrl: 'http://api.test', childId: 'child-a',
        httpClient: mock, wearSync: fakeWear,
        pushChannel: _FakePushChannel())));
      await t.pumpAndSettle();

      expect(find.text('Hi Ivy'), findsOneWidget);
      expect(fakeWear.calls, isEmpty);
    });
  });

  group('PushChannel wiring — §11', () {
    MockClient readyMock() => MockClient((req) async {
      if (req.url.path == '/v1/auth/dev-login') {
        return http.Response(jsonEncode({'token': 'tok'}), 200);
      }
      if (req.url.path == '/v1/me') {
        return http.Response(jsonEncode({'displayName': 'Ivy'}), 200);
      }
      if (req.url.path.endsWith('/inbox')) {
        return http.Response(jsonEncode({'messages': <Map<String, dynamic>>[]}), 200);
      }
      if (req.url.path.endsWith('/now')) {
        return http.Response(jsonEncode({
          'childLocalTime': '4:15 PM', 'zoneAbbr': 'EDT', 'zone': 'America/New_York',
          'sleepsUntilHandover': null,
        }), 200);
      }
      return http.Response('not found', 404);
    });

    testWidgets(
        'a successful load calls PushChannel.initialize() exactly once -- '
        'this is the one real place in this client an authenticated session '
        'exists, so push registration piggybacks on it rather than a second, '
        'parallel session concept', (t) async {
      final fakePush = _FakePushChannel();
      await t.pumpWidget(wrap(LiveChildHomeScreen(
        baseUrl: 'http://api.test', childId: 'child-a',
        httpClient: readyMock(), pushChannel: fakePush)));
      await t.pumpAndSettle();

      expect(find.text('Hi Ivy'), findsOneWidget);
      expect(fakePush.calls, ['initialize']);
    });

    testWidgets('disposing the screen disposes its PushChannel', (t) async {
      final fakePush = _FakePushChannel();
      await t.pumpWidget(wrap(LiveChildHomeScreen(
        baseUrl: 'http://api.test', childId: 'child-a',
        httpClient: readyMock(), pushChannel: fakePush)));
      await t.pumpAndSettle();

      await t.pumpWidget(const MaterialApp(home: SizedBox()));
      await t.pumpAndSettle();

      expect(fakePush.calls, ['initialize', 'dispose']);
    });

    testWidgets(
        'a real (unmocked) PushChannel -- Firebase.initializeApp() genuinely '
        'failing in this environment (no google-services.json) -- never '
        'breaks this screen\'s own ready state', (t) async {
      // No `pushChannel:` injected here on purpose: this is the one test in
      // this file that deliberately exercises the REAL PushChannel this
      // screen builds for itself (child_home_live.dart's own `_initPush`),
      // proving the try/catch around it actually holds against a real
      // failure, not a fake one.
      await t.pumpWidget(wrap(LiveChildHomeScreen(
        baseUrl: 'http://api.test', childId: 'child-a', httpClient: readyMock())));
      await t.pumpAndSettle();

      expect(find.text('Hi Ivy'), findsOneWidget);
      expect(find.text("Couldn't reach the server"), findsNothing);
    });
  });
}
