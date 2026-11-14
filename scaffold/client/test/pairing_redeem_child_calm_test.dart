// OLIVE BRANCH — the child build's account-code step (PairingRedeemScreen, closingStep) shows a child nothing to
// type, no code, no number and no error sentence: a calm grown-up card, and one calm fallback when something does
// not work. The grown-up types the code on the adult-only keypad behind a deliberate tap.
// Owner rules: P1-P11, MASTERFILE 2.1 and 5.23.2 (a child never sees PINs, errors, counts or pairing words).
// Verified by CI, headless.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:olive_client/pairing_redeem_screen.dart';

class _Offline implements Exception {
  @override
  String toString() => 'SocketException: Connection refused secret-host.internal';
}

/// Every string a child could read right now: Text widgets, tooltips and semantics labels.
String _everythingShown(WidgetTester t) {
  final List<String> out = <String>[];
  for (final Text w in t.widgetList<Text>(find.byType(Text))) {
    out.add(w.data ?? w.textSpan?.toPlainText() ?? '');
  }
  for (final TextField w in t.widgetList<TextField>(find.byType(TextField))) {
    out.add(w.decoration?.hintText ?? '');
    out.add(w.decoration?.labelText ?? '');
  }
  for (final Tooltip w in t.widgetList<Tooltip>(find.byType(Tooltip))) {
    out.add(w.message ?? '');
  }
  return out.join(' | ');
}

void _expectNothingForAChildToTypeOrRead(WidgetTester t) {
  expect(find.byType(TextField), findsNothing, reason: 'no field of any kind');
  expect(find.byKey(const Key('pairingCodeField')), findsNothing);
  expect(find.byKey(const Key('pairingErrorMessage')), findsNothing);
  expect(find.byKey(const Key('pairingConnectButton')), findsNothing);
  expect(find.byKey(const Key('pairingScanQrButton')), findsNothing);
  final String all = _everythingShown(t);
  expect(all, isNot(matches(RegExp(r'[0-9]'))), reason: 'no digit anywhere: $all');
  for (final String bad in <String>[
    'code', 'Code', 'digit', 'number', 'expired', 'cancelled', 'already', 'Too many', 'attempt', 'wrong', 'error',
    'server', 'connection', 'different kind', "doesn't match", 'Exception', 'secret-host', '000000',
  ]) {
    expect(all, isNot(contains(bad)), reason: '"$bad" is shown to a child: $all');
  }
}

http.Client _answering(int status, Map<String, Object?> body, {void Function(http.Request)? onRedeem}) =>
    MockClient((http.Request r) async {
      if (r.url.path == '/v1/device-pairing/redeem') {
        onRedeem?.call(r);
        return http.Response(jsonEncode(body), status);
      }
      return http.Response('{}', 404); // any answer at all means "reachable"
    });

void main() {
  Future<void> pump(WidgetTester t, http.Client client,
      {void Function(Map<String, dynamic>)? onRedeemed, VoidCallback? onNotNow}) async {
    await t.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(MaterialApp(
        home: PairingRedeemScreen(
            baseUrl: 'http://olive.test', role: 'child', closingStep: true, httpClient: client,
            onRedeemed: onRedeemed ?? (_) {}, onNotNow: onNotNow)));
    await t.pumpAndSettle();
  }

  Future<void> typeCode(WidgetTester t, String code) async {
    await t.tap(find.byKey(const Key('adultGateGrownUp')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('pairingChooseType')));
    await t.pumpAndSettle();
    for (final String d in code.split('')) {
      await t.tap(find.text(d));
      await t.pump();
    }
    // Bounded pumps, not pumpAndSettle: a successful redeem leaves the spinner running by design (the caller
    // replaces the whole app root the moment onRedeemed fires).
    for (int i = 0; i < 4; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('the child sees the calm grown-up card only: no field, no number, no code word', (t) async {
    await pump(t, _answering(404, <String, Object?>{}));
    expect(find.byKey(const Key('adultGateCard')), findsOneWidget);
    expect(find.text('A grown-up does this'), findsOneWidget);
    _expectNothingForAChildToTypeOrRead(t);
  });

  testWidgets('the choice behind the grown-up tap offers a keypad and a scan, and still no field or digit', (t) async {
    await pump(t, _answering(404, <String, Object?>{}));
    await t.tap(find.byKey(const Key('adultGateGrownUp')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('pairingChooseType')), findsOneWidget);
    expect(find.byKey(const Key('pairingChooseScan')), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.byKey(const Key('pairingCodeField')), findsNothing);
  });

  testWidgets('the grown-up path still works: tap, type the code on the adult keypad, it redeems with role child', (t) async {
    final List<Map<String, Object?>> calls = <Map<String, Object?>>[];
    Map<String, dynamic>? result;
    await pump(
      t,
      _answering(201, <String, Object?>{'sessionToken': 'tok', 'deviceId': 'device-1', 'role': 'child', 'targetId': 'child-1'},
          onRedeem: (http.Request r) => calls.add(<String, Object?>{'body': jsonDecode(r.body)})),
      onRedeemed: (Map<String, dynamic> r) => result = r,
    );
    await typeCode(t, '123456');
    expect(calls, hasLength(1));
    expect(calls.single['body'], <String, Object?>{'code': '123456', 'role': 'child'});
    expect(result?['deviceId'], 'device-1');
  });

  testWidgets('the grown-up can scan the picture from the account instead', (t) async {
    await pump(t, _answering(404, <String, Object?>{}));
    await t.tap(find.byKey(const Key('adultGateGrownUp')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('pairingChooseScan')));
    await t.pump();
    expect(find.byKey(const Key('pairingScanner')), findsOneWidget);
    await t.tap(find.byKey(const Key('pairingScanBack')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('pairingChooseType')), findsOneWidget);
  });

  testWidgets('camera denied while scanning: only the one calm card, never raw error text from the plugin', (t) async {
    await pump(t, _answering(404, <String, Object?>{}));
    await t.tap(find.byKey(const Key('adultGateGrownUp')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('pairingChooseScan')));
    await t.pump();
    final MobileScanner scanner = t.widget<MobileScanner>(find.byKey(const Key('pairingScanner')));
    expect(scanner.errorBuilder, isNotNull, reason: 'without one the plugin shows raw English error text');
    await t.pumpWidget(MaterialApp(
        home: Builder(builder: (BuildContext c) => scanner.errorBuilder!(
            c, const MobileScannerException(errorCode: MobileScannerErrorCode.permissionDenied, errorDetails: MobileScannerErrorDetails(message: 'CAMERA_PERMISSION_DENIED raw text'))))));
    expect(find.byKey(const Key('childConnectTryAgain')), findsOneWidget);
    final String all = _everythingShown(t);
    expect(all, isNot(contains('PERMISSION')));
    expect(all, isNot(contains('denied')));
    expect(all, isNot(contains('rror')));
  });

  for (final String reason in <String>[
    'role_mismatch', 'expired', 'revoked', 'already_redeemed', 'locked', 'not_found', 'something_new',
  ]) {
    testWidgets('server answer "$reason": the child sees only the one calm fallback, never a sentence about it', (t) async {
      bool redeemed = false;
      await pump(t, _answering(400, <String, Object?>{'error': reason}), onRedeemed: (_) => redeemed = true);
      await typeCode(t, '000000');
      expect(redeemed, isFalse);
      expect(find.byKey(const Key('childConnectTryAgain')), findsOneWidget);
      expect(find.text('Your grown-up can try again'), findsOneWidget);
      // Nothing else is readable: the fallback's one line and its OK.
      final String all = _everythingShown(t);
      expect(all, 'Your grown-up can try again | OK');
      expect(all, isNot(contains(reason)));
      _expectNothingForAChildToTypeOrRead(t);
      // OK goes back to the calm card.
      await t.tap(find.byKey(const Key('childConnectBack')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('adultGateCard')), findsOneWidget);
    });
  }

  testWidgets('losing the connection while redeeming shows the picture-only state, never the exception', (t) async {
    bool down = false;
    final http.Client client = MockClient((http.Request r) async {
      if (down) throw _Offline();
      return http.Response('{}', 404);
    });
    await pump(t, client);
    down = true;
    await typeCode(t, '123456');
    expect(find.byKey(const Key('pairingOfflinePicture')), findsOneWidget);
    expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);
    _expectNothingForAChildToTypeOrRead(t);
  });

  testWidgets('"Not now" is a quiet close on the card and calls the caller', (t) async {
    int notNow = 0;
    await pump(t, _answering(404, <String, Object?>{}), onNotNow: () => notNow++);
    await t.tap(find.byKey(const Key('adultGateClose')));
    await t.pump();
    expect(notNow, 1);
  });

  testWidgets('the standalone layout is unchanged for the grown-up build', (t) async {
    await t.pumpWidget(MaterialApp(
        home: PairingRedeemScreen(
            baseUrl: 'http://olive.test', role: 'guardian', onRedeemed: (_) {},
            httpClient: _answering(404, <String, Object?>{}))));
    await t.pump();
    expect(find.byKey(const Key('pairingCodeField')), findsOneWidget);
  });
}
