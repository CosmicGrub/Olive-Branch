// OLIVE BRANCH — the grown-up's side of a call, against the server's availability and ring answers.
// MASTERFILE §5.25.2, §7.18. Complements guardian_more_test.dart's call tests (same harness).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:olive_client/call_screen.dart';
import 'package:olive_client/guardian_more.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.binding.setSurfaceSize(const Size(800, 1800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(home: child));
}

MockClient _server({
  required Map<String, Object?>? availability,
  int availabilityStatus = 200,
  String ringState = 'rang',
  List<String>? log,
}) =>
    MockClient((http.Request req) async {
      log?.add('${req.method} ${req.url.path}');
      if (req.url.path == '/v1/auth/dev-login') return http.Response(jsonEncode(<String, Object?>{'token': 'tok'}), 200);
      if (req.method == 'GET' && req.url.path == '/v1/children/child-1/calls/availability') {
        return http.Response(jsonEncode(availability), availabilityStatus);
      }
      if (req.method == 'POST' && req.url.path == '/v1/children/child-1/calls') {
        return http.Response(jsonEncode(<String, Object?>{
          'token': 'real-lk-token-abc',
          'wsURL': 'wss://project.livekit.cloud',
          'identity': 'dad-1',
          'rang': ringState == 'rang',
          'ringState': ringState,
          'sessionId': '3f2c1a9e-7d4b-4c1e-9a55-0b1c2d3e4f50',
        }), 201);
      }
      return http.Response('not found', 404);
    });

void main() {
  testWidgets('calls switched off: the grown-up is told before anything is started, and no call is made', (t) async {
    final log = <String>[];
    await _pump(t, GuardianMoreScreen(
      childName: 'Mia', childAge: 9, baseUrl: 'http://api.test', guardianId: 'dad-1', childId: 'child-1',
      availabilityHttpClient: _server(availability: <String, Object?>{'provider': 'jitsi', 'available': false, 'sameNetworkOnly': false}, log: log),
    ));
    final tile = find.text('Call Mia');
    await t.ensureVisible(tile);
    await t.pumpAndSettle();
    await t.tap(tile);
    await t.pumpAndSettle();
    expect(find.textContaining('switched off'), findsOneWidget);
    expect(find.byType(CallScreen), findsNothing);
    expect(log.where((l) => l == 'POST /v1/children/child-1/calls'), isEmpty, reason: 'no call may be started when the server says calls are off');
    expect(log, contains('GET /v1/children/child-1/calls/availability'));
  });

  testWidgets('an availability answer that cannot be read does not stop the call: the server still has the last word', (t) async {
    final log = <String>[];
    await _pump(t, GuardianMoreScreen(
      childName: 'Mia', childAge: 9, baseUrl: 'http://api.test', guardianId: 'dad-1', childId: 'child-1',
      availabilityHttpClient: _server(availability: <String, Object?>{'available': 'true'}, log: log),
    ));
    final tile = find.text('Call Mia');
    await t.ensureVisible(tile);
    await t.pumpAndSettle();
    await t.tap(tile);
    await t.runAsync(() async {
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
    });
    expect(log, contains('POST /v1/children/child-1/calls'));
    expect(find.byType(CallScreen), findsOneWidget);
  });

  testWidgets('home-network-only calls say so, and the call still goes ahead', (t) async {
    await _pump(t, GuardianMoreScreen(
      childName: 'Mia', childAge: 9, baseUrl: 'http://api.test', guardianId: 'dad-1', childId: 'child-1',
      availabilityHttpClient: _server(availability: <String, Object?>{'provider': 'jitsi', 'available': true, 'sameNetworkOnly': true}),
    ));
    final tile = find.text('Call Mia');
    await t.ensureVisible(tile);
    await t.pumpAndSettle();
    await t.tap(tile);
    await t.runAsync(() async {
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
    });
    expect(find.byType(CallScreen), findsOneWidget);
    expect(find.textContaining('home Wi-Fi'), findsOneWidget);
  });

  testWidgets('a call that did not ring says why, in a grown-up\'s words, and the call is still open', (t) async {
    await _pump(t, GuardianMoreScreen(
      childName: 'Mia', childAge: 9, baseUrl: 'http://api.test', guardianId: 'dad-1', childId: 'child-1',
      availabilityHttpClient: _server(availability: <String, Object?>{'provider': 'livekit', 'available': true, 'sameNetworkOnly': false}, ringState: 'quiet_hours'),
    ));
    final tile = find.text('Call Mia');
    await t.ensureVisible(tile);
    await t.pumpAndSettle();
    await t.tap(tile);
    await t.runAsync(() async {
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
    });
    expect(find.byType(CallScreen), findsOneWidget);
    expect(find.textContaining("Mia's tablet is in quiet time"), findsOneWidget);
  });

  testWidgets('a call that rang says nothing extra', (t) async {
    await _pump(t, GuardianMoreScreen(
      childName: 'Mia', childAge: 9, baseUrl: 'http://api.test', guardianId: 'dad-1', childId: 'child-1',
      availabilityHttpClient: _server(availability: <String, Object?>{'provider': 'livekit', 'available': true, 'sameNetworkOnly': false}),
    ));
    final tile = find.text('Call Mia');
    await t.ensureVisible(tile);
    await t.pumpAndSettle();
    await t.tap(tile);
    await t.runAsync(() async {
      await t.pump();
      await t.pump(const Duration(milliseconds: 500));
    });
    expect(find.byType(CallScreen), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });
}
