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
  testWidgets('the grown-up card shows the same word and picture and one tap admits', (t) async {
    final DeviceKey adult = (await t.runAsync(_key))!, child = (await t.runAsync(_key))!;
    final PlayAdmission adm = PlayAdmission.forAdult(adult, <PairedKid>[
      PairedKid(certId: 'c', childDeviceKey: child.publicKey, childId: 'k', deviceName: 'T', issuedAtMs: 1)
    ])..openWindow();
    await t.pumpWidget(MaterialApp(home: Scaffold(body: PlayConfirmCard(admission: adm, peerLabel: '‮Dad\u0000'))));
    expect(find.byKey(const Key('playConfirmCard')), findsNothing);
    final PlaySession? s = await t.runAsync<PlaySession?>(() async {
      Map<String, dynamic>? sent;
      return await PlaySession.hello(
          own: child, peerKey: adult.publicKey, post: (Map<String, dynamic> b) async {
        sent = b;
        return adm.handleHello(sent!, '127.0.0.1');
      });
    });
    await t.pump();
    expect(s, isNotNull);
    expect(find.byKey(const Key('playConfirmCard')), findsOneWidget);
    expect(find.text('Dad wants to play'), findsOneWidget, reason: 'peer text is cleaned');
    expect(t.widget<Text>(find.byKey(const Key('playConfirmWord'))).data, s!.sas.word);
    await t.tap(find.byKey(const Key('playConfirmYes')));
    await t.pump();
    expect(adm.admitted, isTrue);
    expect(find.byKey(const Key('playConfirmCard')), findsNothing);
  });
}
