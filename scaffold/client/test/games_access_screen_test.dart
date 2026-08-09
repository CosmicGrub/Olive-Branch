// OLIVE BRANCH — games_access_screen.dart tests. §5.17, §5.18.
// db/migrations/0008_games_access.sql, server/routes.mjs's
// `PATCH /v1/children/:childId/games-access`.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:olive_client/games_access_screen.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

/// A mock transport that answers dev-login for real, then answers the PATCH
/// however the test wants -- matches child_home_live_test.dart's own
/// `MockClient` shape for the same two-call (login, then real call) flow.
MockClient patchMock(Future<http.Response> Function(http.Request req) onPatch) {
  return MockClient((req) async {
    if (req.method == 'POST' && req.url.path == '/v1/auth/dev-login') {
      return http.Response(jsonEncode({'token': 'tok'}), 200);
    }
    if (req.method == 'PATCH') return onPatch(req);
    return http.Response('not found', 404);
  });
}

void main() {
  group('GamesAccessScreen — the real guardian-only lock/unlock control', () {
    testWidgets('starts unset -- never claims a confirmed value it never read',
        (t) async {
      final mock = patchMock((req) async =>
          http.Response(jsonEncode({'childId': 'child-a', 'gamesEnabled': true}), 200));
      await t.pumpWidget(wrap(GamesAccessScreen(
        childId: 'child-a', guardianUserId: 'dad-1', httpClient: mock)));
      await t.pump();
      expect(find.textContaining('Not confirmed yet'), findsOneWidget);
      final Switch sw = t.widget(find.byType(Switch));
      expect(sw.value, isFalse);
    });

    testWidgets('turning ON calls the real PATCH with enabled:true and shows confirmed-on',
        (t) async {
      Map<String, dynamic>? sentBody;
      String? method;
      Uri? url;
      final mock = patchMock((req) async {
        method = req.method;
        url = req.url;
        sentBody = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response(jsonEncode({'childId': 'child-a', 'gamesEnabled': true}), 200);
      });
      await t.pumpWidget(wrap(GamesAccessScreen(
        childId: 'child-a', childName: 'Ivy', guardianUserId: 'dad-1', httpClient: mock)));
      await t.pump();

      await t.tap(find.byType(Switch));
      await t.pumpAndSettle();

      expect(method, 'PATCH');
      expect(url.toString(), 'http://10.0.2.2:8123/v1/children/child-a/games-access');
      expect(sentBody, {'enabled': true});
      final Switch sw = t.widget(find.byType(Switch));
      expect(sw.value, isTrue);
      expect(find.textContaining('On for Ivy'), findsOneWidget);
      expect(find.textContaining('confirmed by the server'), findsOneWidget);
    });

    testWidgets('turning OFF calls the real PATCH with enabled:false and shows confirmed-off',
        (t) async {
      // Start already "on" locally by flipping it on once, then off.
      final mock = patchMock((req) async {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response(
            jsonEncode({'childId': 'child-a', 'gamesEnabled': body['enabled']}), 200);
      });
      await t.pumpWidget(wrap(GamesAccessScreen(
        childId: 'child-a', childName: 'Ivy', guardianUserId: 'dad-1', httpClient: mock)));
      await t.pump();
      await t.tap(find.byType(Switch));
      await t.pumpAndSettle();
      expect((t.widget(find.byType(Switch)) as Switch).value, isTrue);

      await t.tap(find.byType(Switch));
      await t.pumpAndSettle();

      expect((t.widget(find.byType(Switch)) as Switch).value, isFalse);
      expect(find.textContaining('Off for Ivy'), findsOneWidget);
    });

    testWidgets('shows a real loading state while the PATCH is in flight', (t) async {
      final mock = patchMock((req) async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return http.Response(jsonEncode({'childId': 'child-a', 'gamesEnabled': true}), 200);
      });
      await t.pumpWidget(wrap(GamesAccessScreen(childId: 'child-a', httpClient: mock)));
      await t.pump();

      await t.tap(find.byType(Switch));
      await t.pump(); // one frame -- request still in flight
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.textContaining('Saving'), findsOneWidget);
      // The switch is disabled while saving, not just visually busy.
      final Switch sw = t.widget(find.byType(Switch));
      expect(sw.onChanged, isNull);

      await t.pumpAndSettle(); // drain the delayed response
    });

    testWidgets(
        'a failed toggle reverts the switch and shows an error -- '
        'never silently looks like it worked', (t) async {
      final mock = patchMock((req) async =>
          http.Response(jsonEncode({'error': 'no_edge'}), 403));
      await t.pumpWidget(wrap(GamesAccessScreen(
        childId: 'child-a', childName: 'Ivy', httpClient: mock)));
      await t.pump();

      await t.tap(find.byType(Switch));
      await t.pumpAndSettle();

      final Switch sw = t.widget(find.byType(Switch));
      expect(sw.value, isFalse); // reverted, not left on
      expect(find.textContaining("Couldn't reach the server"), findsOneWidget);
      expect(find.textContaining('403: no_edge'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });

    testWidgets('Try again retries the same intent and can recover into confirmed',
        (t) async {
      var attempt = 0;
      final mock = patchMock((req) async {
        attempt++;
        if (attempt == 1) return http.Response(jsonEncode({'error': 'no_edge'}), 403);
        return http.Response(jsonEncode({'childId': 'child-a', 'gamesEnabled': true}), 200);
      });
      await t.pumpWidget(wrap(GamesAccessScreen(
        childId: 'child-a', childName: 'Ivy', httpClient: mock)));
      await t.pump();

      await t.tap(find.byType(Switch));
      await t.pumpAndSettle();
      expect(find.text('Try again'), findsOneWidget);
      expect((t.widget(find.byType(Switch)) as Switch).value, isFalse);

      await t.tap(find.text('Try again'));
      await t.pumpAndSettle();

      expect((t.widget(find.byType(Switch)) as Switch).value, isTrue);
      expect(find.textContaining('On for Ivy'), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
    });
  });
}
