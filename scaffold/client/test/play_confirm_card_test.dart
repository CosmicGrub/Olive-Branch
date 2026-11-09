// OLIVE BRANCH — the grown-up's play confirmation card (its own file: a widget binding makes dart:io HTTP return 400,
// so the real-socket suite lives in play_admission_test.dart). Verified by CI, headless.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/device_keys.dart';
import 'package:olive_client/pairing_protocol.dart' show PairedKid;
import 'package:olive_client/play_admission.dart';
import 'package:olive_client/play_confirm_card.dart';

Future<DeviceKey> _key() => DeviceKey.loadOrCreate(MemoryDeviceKeyRepository());

void main() {
  testWidgets('the card says Player two wants to join, shows the match, and never a name', (t) async {
    final DeviceKey adult = (await t.runAsync(_key))!, child = (await t.runAsync(_key))!;
    final PlayAdmission adm = PlayAdmission.forAdult(adult, <PairedKid>[
      PairedKid(certId: 'c', childDeviceKey: child.publicKey, childId: 'k', deviceName: 'Ivy\'s Tablet', issuedAtMs: 1)
    ]);
    await t.runAsync(adm.openWindow);
    await t.pumpWidget(MaterialApp(home: Scaffold(body: PlayConfirmCard(admission: adm, peerSeat: 2))));
    expect(find.byKey(const Key('playConfirmCard')), findsNothing);
    final PlaySession? s = await t.runAsync<PlaySession?>(() async {
      return await PlaySession.hello(
          own: child, peerKey: adult.publicKey, lobbyToken: adm.lobbyToken!, post: (Map<String, dynamic> b) async {
        return adm.handleHello(b, '127.0.0.1');
      });
    });
    await t.pump();
    expect(s, isNotNull);
    expect(find.byKey(const Key('playConfirmCard')), findsOneWidget);
    expect(find.text('Player two wants to join'), findsOneWidget);
    expect(find.textContaining('Ivy'), findsNothing);
    expect(find.textContaining('Tablet'), findsNothing);
    expect(t.widget<Text>(find.byKey(const Key('playConfirmWord'))).data, s!.sas.word);
    await t.tap(find.byKey(const Key('playConfirmYes')));
    await t.pump();
    expect(adm.admitted, isTrue);
    expect(find.byKey(const Key('playConfirmCard')), findsNothing);
  });
}
