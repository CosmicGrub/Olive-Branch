// OLIVE BRANCH — the adult-side PIN step-up on the two exports (MASTERFILE section 7.12.1): the certified export asks
// for the guardian PIN on an in-page card before it asks the server for anything, a wrong or locked PIN is said
// plainly and nothing is shown as exported, and the raw export from the deletion screen asks in a dialog. Posture:
// the card fits the 344 dp Fold cover at 2.0x text. Verified by CI, headless.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:olive_client/court_export.dart';
import 'package:olive_client/deletion_screen.dart';

http.Response _json(Object body, int status) => http.Response(jsonEncode(body), status,
    headers: {'content-type': 'application/json; charset=utf-8'});

Map<String, dynamic> _attestation() => <String, dynamic>{
      'childId': 'child-a', 'generatedAt': '2026-08-11T00:00:00.000Z', 'entryCount': 2, 'firstSeq': 0, 'lastSeq': 1,
      'headHash': 'a' * 64, 'bundleHash': 'b' * 64, 'chainVerified': true, 'statement': 'Each entry carries a SHA-256 hash...',
    };

Future<void> _settle(WidgetTester t) async {
  for (int i = 0; i < 20; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await t.pump(const Duration(milliseconds: 30));
  }
}

void main() {
  testWidgets('certified export: the PIN card comes first, nothing is asked of the server until a PIN is typed', (t) async {
    await t.binding.setSurfaceSize(const Size(1300, 1400));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final List<http.Request> seen = <http.Request>[];
    final MockClient mock = MockClient((http.Request req) async {
      seen.add(req);
      if (req.url.path == '/v1/auth/dev-login') return _json(<String, String>{'token': 'tok'}, 200);
      return _json(<String, dynamic>{
        'kind': 'certified', 'free': true, 'chain': <dynamic>[], 'attestation': _attestation(),
        'bundleHash': 'c' * 64, 'exportRecordId': 'rec-1',
      }, 200);
    });
    await t.pumpWidget(MaterialApp(
        home: LiveCourtExportScreen(baseUrl: 'http://api.test', guardianId: 'dad', childId: 'child-a', httpClient: mock)));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('guardianPinCardField')), findsOneWidget);
    expect(seen, isEmpty, reason: 'no PIN, no request');
    await t.enterText(find.byKey(const Key('guardianPinCardField')), '5193');
    await t.tap(find.byKey(const Key('guardianPinCardGo')));
    await _settle(t);
    final http.Request export = seen.firstWhere((http.Request r) => r.url.path.endsWith('/export'));
    expect(export.headers['x-guardian-pin'], '5193');
    expect(export.url.toString(), isNot(contains('5193')));
    expect(find.text('Chain verified'), findsOneWidget);
  });

  testWidgets('certified export: a wrong PIN returns to the card with the reason; a locked one says so; neither is a denial', (t) async {
    await t.binding.setSurfaceSize(const Size(1300, 1400));
    addTearDown(() => t.binding.setSurfaceSize(null));
    String error = 'pin_incorrect';
    final MockClient mock = MockClient((http.Request req) async {
      if (req.url.path == '/v1/auth/dev-login') return _json(<String, String>{'token': 'tok'}, 200);
      return _json(<String, String>{'error': error}, 403);
    });
    await t.pumpWidget(MaterialApp(
        home: LiveCourtExportScreen(baseUrl: 'http://api.test', guardianId: 'dad', childId: 'child-a', httpClient: mock)));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('guardianPinCardField')), '1111');
    await t.tap(find.byKey(const Key('guardianPinCardGo')));
    await _settle(t);
    expect(find.text("That PIN doesn't match. Try again."), findsOneWidget);
    expect(find.byKey(const Key('guardianPinCardField')), findsOneWidget);
    error = 'pin_locked';
    await t.enterText(find.byKey(const Key('guardianPinCardField')), '1111');
    await t.tap(find.byKey(const Key('guardianPinCardGo')));
    await _settle(t);
    expect(find.text('Too many wrong tries. Try again in 15 minutes.'), findsOneWidget);
    expect(find.text('Chain verified'), findsNothing);
  });

  for (final double scale in <double>[1.0, 2.0]) {
    testWidgets('the PIN card fits the 344 dp cover screen at ${scale}x text without overflow', (t) async {
      await t.binding.setSurfaceSize(const Size(344, 700));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(MaterialApp(
          home: MediaQuery(
              data: MediaQueryData(size: const Size(344, 700), textScaler: TextScaler.linear(scale)),
              child: LiveCourtExportScreen(
                  baseUrl: 'http://api.test', guardianId: 'dad', childId: 'child-a',
                  httpClient: MockClient((http.Request r) async => _json(<String, String>{}, 500))))));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('guardianPinCardGo')), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('raw export from the deletion screen: a cancelled PIN asks the server nothing and says nothing', (t) async {
    await t.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    int calls = 0;
    final MockClient mock = MockClient((http.Request req) async {
      calls++;
      return _json(<String, String>{'token': 'tok'}, 200);
    });
    await t.pumpWidget(MaterialApp(
        home: DeletionScreen(
            childName: 'Ivy', baseUrl: 'http://api.test', childId: 'child-a', httpClient: mock,
            pinSource: (BuildContext c, {required String title, String? why, String? error}) async => null)));
    await t.tap(find.textContaining('Download'));
    await _settle(t);
    expect(calls, 0);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('raw export from the deletion screen: a locked PIN is said in plain words, nothing is reported as saved', (t) async {
    await t.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final MockClient mock = MockClient((http.Request req) async {
      if (req.url.path == '/v1/auth/dev-login') return _json(<String, String>{'token': 'tok'}, 200);
      return _json(<String, String>{'error': 'pin_locked'}, 403);
    });
    await t.pumpWidget(MaterialApp(
        home: DeletionScreen(
            childName: 'Ivy', baseUrl: 'http://api.test', childId: 'child-a', httpClient: mock,
            pinSource: (BuildContext c, {required String title, String? why, String? error}) async => '5193')));
    await t.tap(find.textContaining('Download'));
    await _settle(t);
    expect(find.text('Too many wrong tries. Try again in 15 minutes.'), findsOneWidget);
    expect(find.text('Raw export saved'), findsNothing);
  });
}
