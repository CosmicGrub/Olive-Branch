// OLIVE BRANCH — the phone-unlock surfaces: the child gate's phone option, the grown-up's unlock screen, and the
// connected-devices list (forget, phone-only). Verified by CI, headless.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/adult_gate.dart';
import 'package:olive_client/connected_devices_screen.dart';
import 'package:olive_client/device_keys.dart';
import 'package:olive_client/local_pin.dart';
import 'package:olive_client/pairing_protocol.dart';
import 'package:olive_client/pairing_records.dart';
import 'package:olive_client/pin_gate.dart';
import 'package:olive_client/unlock_challenge.dart';
import 'package:olive_client/unlock_child_screen.dart';

Future<DeviceKey> _key() => DeviceKey.loadOrCreate(MemoryDeviceKeyRepository());

Future<void> _settle(WidgetTester t) async {
  for (int i = 0; i < 20; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
    await t.pump(const Duration(milliseconds: 30));
  }
}

void main() {
  testWidgets('gate with a phone: the grown-up taps, chooses; phone-only skips the keypad entirely', (t) async {
    final DeviceKey ak = (await t.runAsync(_key))!, ck = (await t.runAsync(_key))!;
    final ChildUnlockHost host = ChildUnlockHost(childKey: ck, adultKey: ak.publicKey);
    await t.pumpWidget(MaterialApp(home: AdultGate(digits: 4, onPin: (_) {}, phone: PhoneUnlock(host: host))));
    expect(find.byKey(const Key('adultGateCard')), findsOneWidget);
    await t.tap(find.byKey(const Key('adultGateGrownUp')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('adultGateChoose')), findsOneWidget);
    expect(find.byType(PinGate), findsNothing, reason: 'the keypad is a choice, not the default');
    await t.tap(find.byKey(const Key('adultGateTypeCode')));
    await t.pumpAndSettle();
    expect(find.byType(PinGate), findsOneWidget);

    await t.pumpWidget(MaterialApp(home: AdultGate(key: UniqueKey(), digits: 4, onPin: (_) {}, phone: PhoneUnlock(host: host, phoneOnly: true))));
    await t.tap(find.byKey(const Key('adultGateGrownUp')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('adultGatePhone')), findsOneWidget);
    expect(find.byType(PinGate), findsNothing, reason: 'phone-only: there is no keypad to find');
    expect(find.byKey(const Key('adultGateTypeCode')), findsNothing);
  });

  testWidgets('gate end to end: the tablet shows a challenge, the phone answers, the gate yields the phone proof', (t) async {
    final DeviceKey ak = (await t.runAsync(_key))!, ck = (await t.runAsync(_key))!;
    final PairedKid kid = PairedKid(certId: 'c', childDeviceKey: ck.publicKey, childId: 'k', deviceName: 'Tablet', issuedAtMs: 1);
    final ChildUnlockHost host = ChildUnlockHost(childKey: ck, adultKey: ak.publicKey);
    final UnlockResponder phone = UnlockResponder(adultKey: ak, kids: () async => <PairedKid>[kid]);
    String? got;
    void Function(String)? feed;
    await t.pumpWidget(MaterialApp(
        home: AdultGate(
      digits: 4,
      onPin: (String p) => got = p,
      phone: PhoneUnlock(host: host, phoneOnly: true, scannerBuilder: (void Function(String) onValue) {
        feed = onValue;
        return const SizedBox();
      }),
    )));
    await t.tap(find.byKey(const Key('adultGateGrownUp')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('adultGateChallengeQr')), findsOneWidget);
    // A wrong picture leaves no words and no result.
    await t.tap(find.byKey(const Key('adultGateScanPhone')));
    await t.pumpAndSettle();
    feed!('olive://grant/1?n=AAAA&s=BBBB');
    await _settle(t);
    expect(got, isNull);
    expect(find.textContaining('wrong'), findsNothing);
    // The real answer to the CURRENT challenge. (The wrong scan issued a fresh one; reach it through the host.)
    final UnlockChallenge c = host.issue(UnlockPurpose.unlock);
    final String grant = (await t.runAsync(() async => phone.grant((await phone.inspect(c.toQr()))!)))!;
    feed!(grant);
    await _settle(t);
    expect(got, kPhoneProof);
  });

  testWidgets('the grown-up screen: wrong PIN refused, right PIN shows an answer, a stranger tablet is refused', (t) async {
    final DeviceKey ak = (await t.runAsync(_key))!, ck = (await t.runAsync(_key))!, other = (await t.runAsync(_key))!;
    final PairedKid kid = PairedKid(certId: 'c', childDeviceKey: ck.publicKey, childId: 'k', deviceName: 'Tablet', issuedAtMs: 1);
    final LocalPinService pin = LocalPinService(MemoryLocalPinRepository(), iterations: 1);
    await t.runAsync(() => pin.setPin('4829'));
    final ChildUnlockHost host = ChildUnlockHost(childKey: ck, adultKey: ak.publicKey);
    final ChildUnlockHost strangerHost = ChildUnlockHost(childKey: other, adultKey: ak.publicKey);
    void Function(String)? feed;
    await t.pumpWidget(MaterialApp(
        home: UnlockChildScreen(
      pin: pin,
      responder: UnlockResponder(adultKey: ak, kids: () async => <PairedKid>[kid]),
      childName: 'Ivy',
      scannerBuilder: (void Function(String) onValue) {
        feed = onValue;
        return const SizedBox();
      },
    )));
    feed!(strangerHost.issue(UnlockPurpose.unlock).toQr());
    await _settle(t);
    expect(find.byKey(const Key('unlockMessage')), findsOneWidget);
    expect(find.byKey(const Key('unlockConfirmTitle')), findsNothing);

    feed!(host.issue(UnlockPurpose.unlock).toQr());
    await _settle(t);
    expect(find.byKey(const Key('unlockConfirmTitle')), findsOneWidget);
    expect(find.textContaining('unlock Tablet'), findsOneWidget);
    await t.enterText(find.byKey(const Key('unlockPinField')), '0000');
    await t.tap(find.byKey(const Key('unlockApprove')));
    await _settle(t);
    expect(find.byKey(const Key('unlockAnswerQr')), findsNothing);
    await t.enterText(find.byKey(const Key('unlockPinField')), '4829');
    await t.tap(find.byKey(const Key('unlockApprove')));
    await _settle(t);
    expect(find.byKey(const Key('unlockAnswerQr')), findsOneWidget);
  });

  testWidgets('connected devices: phone-only turns on and stays on; forget asks, then removes', (t) async {
    final MemoryPairedKidsRepository kids = MemoryPairedKidsRepository();
    await kids.add(PairedKid(certId: 'a', childDeviceKey: Uint8List(32), childId: 'k', deviceName: 'Tablet', issuedAtMs: 1));
    await t.pumpWidget(MaterialApp(home: ConnectedDevicesScreen(kids: kids, childName: 'Ivy')));
    await _settle(t);
    expect(find.byKey(const Key('connectedName_a')), findsOneWidget);
    await t.tap(find.byKey(const Key('connectedPhoneOnly_a')));
    await _settle(t);
    expect((await kids.load()).single.phoneOnly, isTrue);
    expect(t.widget<SwitchListTile>(find.byKey(const Key('connectedPhoneOnly_a'))).onChanged, isNull, reason: 'one way');
    await t.tap(find.byKey(const Key('connectedForget_a')));
    await t.pumpAndSettle();
    expect(find.textContaining('keeps its connection'), findsOneWidget);
    await t.tap(find.byKey(const Key('forgetCancel')));
    await t.pumpAndSettle();
    expect(await kids.load(), isNotEmpty);
    await t.tap(find.byKey(const Key('connectedForget_a')));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('forgetConfirm')));
    await _settle(t);
    expect(await kids.load(), isEmpty);
    expect(find.byKey(const Key('connectedEmpty')), findsOneWidget);
  });
}
