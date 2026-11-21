// OLIVE BRANCH — a child device that was connected and has been cut off boots into the calm closing-step card
// ("A grown-up does this") behind the adult gate: no code field, no error sentence, no digit, no pairing word.
// main_live.dart's signed-out child boot (the app the unified entry opens when a connected device is signed out).
// Owner rules P1-P11, MASTERFILE 2.1 and 5.23.2. Verified by CI, headless.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:olive_client/main_live.dart' show signedOutChildBootForTest;

String _everythingShown(WidgetTester t) {
  final List<String> out = <String>[];
  for (final Text w in t.widgetList<Text>(find.byType(Text))) {
    out.add(w.data ?? w.textSpan?.toPlainText() ?? '');
  }
  for (final Tooltip w in t.widgetList<Tooltip>(find.byType(Tooltip))) {
    out.add(w.message ?? '');
  }
  return out.join(' | ');
}

void _nothingToTypeOrRead(WidgetTester t) {
  expect(find.byType(TextField), findsNothing, reason: 'no field of any kind');
  expect(find.byType(EditableText), findsNothing);
  expect(find.byKey(const Key('pairingCodeField')), findsNothing);
  expect(find.byKey(const Key('pairingErrorMessage')), findsNothing);
  expect(find.byKey(const Key('pairingConnectButton')), findsNothing);
  final String all = _everythingShown(t);
  expect(all, isNot(matches(RegExp(r'[0-9]'))), reason: 'no digit anywhere: $all');
  for (final String bad in <String>[
    'code', 'Code', 'Pairing', 'Connect', 'expired', 'already', 'Too many', 'wrong', 'rror', 'server', 'connection',
    'Exception', "Couldn't", 'Check your',
  ]) {
    expect(all, isNot(contains(bad)), reason: '"$bad" is shown to a child: $all');
  }
}

void main() {
  Future<void> boot(WidgetTester t, http.Client client) async {
    await t.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(signedOutChildBootForTest('http://olive.test', httpClient: client));
    await t.pumpAndSettle();
  }

  testWidgets('signed out, server reachable: the grown-up card and nothing to type or read', (WidgetTester t) async {
    await boot(t, MockClient((http.Request r) async => http.Response('{}', 404)));
    expect(find.byKey(const Key('adultGateCard')), findsOneWidget);
    expect(find.text('A grown-up does this'), findsOneWidget);
    _nothingToTypeOrRead(t);
  });

  testWidgets('signed out, no connection: a picture-only state, still no field and no sentence', (WidgetTester t) async {
    await boot(t, MockClient((http.Request r) async => throw http.ClientException('no route to secret-host.internal')));
    expect(find.byKey(const Key('pairingOfflinePicture')), findsOneWidget);
    _nothingToTypeOrRead(t);
    expect(_everythingShown(t), isNot(contains('secret-host')));
  });

  testWidgets('only the grown-up\'s deliberate tap leads on, to the adult keypad, and a refused code ends in the one calm card',
      (WidgetTester t) async {
    await boot(
        t,
        MockClient((http.Request r) async => r.url.path == '/v1/device-pairing/redeem'
            ? http.Response(jsonEncode(<String, Object?>{'error': 'not_found'}), 404)
            : http.Response('{}', 404)));
    await t.tap(find.byKey(const Key('adultGateGrownUp')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('pairingChooseType')));
    await t.pumpAndSettle();
    for (final String d in '123456'.split('')) {
      await t.tap(find.text(d));
      await t.pump();
    }
    await t.pumpAndSettle();
    expect(find.byKey(const Key('childConnectTryAgain')), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    final String all = _everythingShown(t);
    expect(all, isNot(contains('not_found')));
    expect(all.toLowerCase(), isNot(contains("doesn't match")));
  });
}
