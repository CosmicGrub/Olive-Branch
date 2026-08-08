// OLIVE BRANCH — child_home_live.dart tests. §7, §8.1.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:olive_client/child_home_live.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

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
      // Honest absence, not a guess — no live custody-schedule source yet.
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
  });
}
