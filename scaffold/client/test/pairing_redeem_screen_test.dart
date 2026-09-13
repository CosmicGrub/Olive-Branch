// OLIVE BRANCH — pairing_redeem_screen.dart tests. docs/superpowers/specs/
// 2026-09-12-device-pairing-provisioning-design.md.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:olive_client/pairing_redeem_screen.dart';

void main() {
  Future<void> pump(WidgetTester tester, {
    required http.Client client,
    required void Function(Map<String, dynamic>) onRedeemed,
    String role = 'child',
  }) =>
      tester.pumpWidget(MaterialApp(home: PairingRedeemScreen(
        baseUrl: 'http://olive.test', role: role, onRedeemed: onRedeemed, httpClient: client)));

  testWidgets('shows the typed-code field and both entry points by default', (tester) async {
    await pump(tester, client: MockClient((req) async => http.Response('{}', 404)),
      onRedeemed: (_) {});
    expect(find.byKey(const Key('pairingCodeField')), findsOneWidget);
    expect(find.byKey(const Key('pairingConnectButton')), findsOneWidget);
    expect(find.byKey(const Key('pairingScanQrButton')), findsOneWidget);
  });

  testWidgets('tapping "scan QR code" swaps in the camera view', (tester) async {
    await pump(tester, client: MockClient((req) async => http.Response('{}', 404)),
      onRedeemed: (_) {});
    await tester.tap(find.byKey(const Key('pairingScanQrButton')));
    await tester.pump();
    expect(find.byKey(const Key('pairingScanner')), findsOneWidget);
    expect(find.byKey(const Key('pairingCodeField')), findsNothing);

    await tester.tap(find.byKey(const Key('pairingCancelScanButton')));
    await tester.pump();
    expect(find.byKey(const Key('pairingCodeField')), findsOneWidget);
  });

  testWidgets('typing a code and tapping Connect calls the real redeem route with role compiled in',
      (tester) async {
    final calls = <Map<String, dynamic>>[];
    Map<String, dynamic>? result;
    final client = MockClient((req) async {
      calls.add({'path': req.url.path, 'body': jsonDecode(req.body)});
      return http.Response(jsonEncode({
        'sessionToken': 'tok', 'deviceId': 'device-1', 'role': 'child', 'targetId': 'child-1',
      }), 201);
    });
    await pump(tester, client: client, onRedeemed: (r) => result = r, role: 'child');
    await tester.enterText(find.byKey(const Key('pairingCodeField')), '123456');
    await tester.tap(find.byKey(const Key('pairingConnectButton')));
    // A bounded pump, not pumpAndSettle() — a successful redeem deliberately
    // leaves this screen mid-"submitting" (its own spinner keeps animating)
    // because the REAL caller (main_live.dart's boot sequence) replaces the
    // whole app root the instant onRedeemed fires; nothing here is meant to
    // reach a settled steady state on its own, so waiting for one would
    // time out on an animation that's supposed to still be running.
    await tester.pump();
    await tester.pump();

    expect(calls, hasLength(1));
    expect(calls.first['path'], '/v1/device-pairing/redeem');
    expect(calls.first['body'], {'code': '123456', 'role': 'child'});
    expect(result?['deviceId'], 'device-1');
  });

  testWidgets('a guardian-build screen always sends role: guardian, never user-editable',
      (tester) async {
    final calls = <Map<String, dynamic>>[];
    final client = MockClient((req) async {
      calls.add({'body': jsonDecode(req.body)});
      return http.Response(jsonEncode({'sessionToken': 't', 'deviceId': 'd', 'role': 'guardian', 'targetId': 'g'}), 201);
    });
    await pump(tester, client: client, onRedeemed: (_) {}, role: 'guardian');
    await tester.enterText(find.byKey(const Key('pairingCodeField')), '654321');
    await tester.tap(find.byKey(const Key('pairingConnectButton')));
    await tester.pump(); // bounded — see the success test above's own comment
    await tester.pump();
    expect(calls.first['body'], {'code': '654321', 'role': 'guardian'});
  });

  testWidgets('role_mismatch is shown with a distinct, specific message, never fires onRedeemed',
      (tester) async {
    var redeemed = false;
    final client = MockClient((req) async =>
      http.Response(jsonEncode({'error': 'role_mismatch'}), 403));
    await pump(tester, client: client, onRedeemed: (_) => redeemed = true);
    await tester.enterText(find.byKey(const Key('pairingCodeField')), '123456');
    await tester.tap(find.byKey(const Key('pairingConnectButton')));
    await tester.pumpAndSettle();
    expect(find.text('This code is for a different kind of device.'), findsOneWidget);
    expect(redeemed, isFalse);
  });

  testWidgets('a generic network failure gets its own distinct, generic message — never the '
      'role_mismatch wording', (tester) async {
    final client = MockClient((req) async => throw Exception('no route to host'));
    await pump(tester, client: client, onRedeemed: (_) {});
    await tester.enterText(find.byKey(const Key('pairingCodeField')), '123456');
    await tester.tap(find.byKey(const Key('pairingConnectButton')));
    await tester.pumpAndSettle();
    expect(find.textContaining("Couldn't reach the server"), findsOneWidget);
    expect(find.text('This code is for a different kind of device.'), findsNothing);
  });

  testWidgets('expired/revoked/already_redeemed/locked/not_found each get their own honest '
      'wording, not a shared generic one', (tester) async {
    Future<void> expectFor(String error, String expectedText) async {
      final client = MockClient((req) async => http.Response(jsonEncode({'error': error}), 400));
      await pump(tester, client: client, onRedeemed: (_) {});
      await tester.enterText(find.byKey(const Key('pairingCodeField')), '123456');
      await tester.tap(find.byKey(const Key('pairingConnectButton')));
      await tester.pumpAndSettle();
      expect(find.textContaining(expectedText), findsOneWidget, reason: 'for error=$error');
    }
    await expectFor('expired', 'expired');
    await expectFor('revoked', 'cancelled');
    await expectFor('already_redeemed', 'already been used');
    await expectFor('locked', 'Too many attempts');
    await expectFor('not_found', "doesn't match anything");
  });

  testWidgets('success genuinely routes into the app — onRedeemed fires with the real payload',
      (tester) async {
    Map<String, dynamic>? received;
    final client = MockClient((req) async => http.Response(jsonEncode({
      'sessionToken': 'real-token', 'deviceId': 'device-9', 'role': 'child', 'targetId': 'child-9',
    }), 201));
    await pump(tester, client: client, onRedeemed: (r) => received = r);
    await tester.enterText(find.byKey(const Key('pairingCodeField')), '111111');
    await tester.tap(find.byKey(const Key('pairingConnectButton')));
    await tester.pump(); // bounded — see the earlier success test's own comment
    await tester.pump();
    expect(received, isNotNull);
    expect(received!['sessionToken'], 'real-token');
    expect(received!['targetId'], 'child-9');
  });
}
