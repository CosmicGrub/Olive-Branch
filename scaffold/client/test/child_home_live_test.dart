// OLIVE BRANCH — child_home_live.dart tests. §7, §8.1, §21.5.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:olive_client/child_home_live.dart';
import 'package:olive_client/wear_sync_channel.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

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

    testWidgets('renders real fetched name and unread count through the real ChildHome',
        (t) async {
      final mock = MockClient((req) async {
        if (req.url.path == '/v1/auth/dev-login') {
          return http.Response(jsonEncode({'token': 'tok'}), 200);
        }
        if (req.url.path == '/v1/me') {
          return http.Response(jsonEncode({'displayName': 'Ivy'}), 200);
        }
        if (req.url.path.endsWith('/inbox')) {
          return http.Response(jsonEncode({'messages': [
            {'id': '1'}, {'id': '2'}, {'id': '3'},
          ]}), 200);
        }
        return http.Response('not found', 404);
      });
      await t.pumpWidget(wrap(LiveChildHomeScreen(
        baseUrl: 'http://api.test', childId: 'child-a', httpClient: mock)));
      await t.pumpAndSettle();

      expect(find.text('Hi Ivy'), findsOneWidget);
      expect(find.text('3'), findsOneWidget); // the unread badge on Messages
      // Honest absence, not a guess. A real custody-schedule endpoint was
      // built and independently verified elsewhere (packages/db/test/
      // custody_order.test.mjs, 16/16), but was found reverted out of this
      // shared repo tree before child_home_live.dart could be wired to it —
      // see that file's header. /v1/children/:id/now as actually deployed
      // right now doesn't return sleepsUntilHandover, and this screen doesn't
      // even call /now yet, so this must keep asserting absence.
      expect(find.textContaining('sleeps until'), findsNothing);
      expect(find.textContaining('sleep until'), findsNothing);
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
        return http.Response('not found', 404);
      });
      await t.pumpWidget(wrap(LiveChildHomeScreen(
        baseUrl: 'http://api.test', childId: 'child-a', httpClient: mock)));
      await t.pumpAndSettle();
      expect(find.text("Couldn't reach the server"), findsOneWidget);

      await t.tap(find.text('Try again'));
      await t.pumpAndSettle();
      expect(find.text('Hi Ivy'), findsOneWidget);
    });

    testWidgets(
        'never syncs a placeholder to the Wear companion while '
        'sleepsUntilHandover is still null', (t) async {
      // §21.5 — child_home_live.dart now has a real call site
      // (`_syncWear()`) that would forward `sleepsUntilHandover` to a
      // paired watch. Today that field always resolves to null (custody
      // endpoint reverted out of the shared tree -- see the file's own
      // header), so this asserts the new wiring's guard actually holds:
      // loading and settling a real, successful fetch must NOT call the
      // wear channel at all, let alone with a guessed/demo value. Without
      // the `if (sleeps != null)` guard in `_syncWear()`, this would call
      // through with `null`, which a real MethodChannel int argument
      // cannot represent honestly anyway.
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
        return http.Response('not found', 404);
      });
      await t.pumpWidget(wrap(LiveChildHomeScreen(
        baseUrl: 'http://api.test', childId: 'child-a',
        httpClient: mock, wearSync: fakeWear)));
      await t.pumpAndSettle();

      expect(find.text('Hi Ivy'), findsOneWidget);
      expect(fakeWear.calls, isEmpty);
    });
  });
}
