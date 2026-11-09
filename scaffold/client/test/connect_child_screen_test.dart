// OLIVE BRANCH — both screens of the on-device connect flow, wired together in-process (no sockets, no mDNS).
// Verified by CI, headless. The crypto is real; time is real (tester.runAsync) because the key exchange awaits.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/child_connect_screen.dart';
import 'package:olive_client/connect_child_screen.dart';
import 'package:olive_client/device_keys.dart';
import 'package:olive_client/lan_pairing_transport.dart';
import 'package:olive_client/local_pin.dart';
import 'package:olive_client/pairing_protocol.dart';
import 'package:olive_client/pairing_records.dart';

Future<LocalPinRecord> _cheap(String pin) async => LocalPinRecord(iterations: 1, salt: Uint8List(16), hash: Uint8List(32));

class _FakeHost implements WindowHost {
  @override
  int? get port => 4242;
  @override
  Future<void> stop() async {}
}

class _FakeFinder implements NearbyFinder {
  final StreamController<NearbyWindow> _f = StreamController<NearbyWindow>.broadcast();
  final StreamController<String> _g = StreamController<String>.broadcast();
  @override
  Stream<NearbyWindow> get found => _f.stream;
  @override
  Stream<String> get gone => _g.stream;
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {}
  void emit(NearbyWindow w) => _f.add(w);
}

/// Runs a gesture inside runAsync (so the futures it starts live in the real zone, as local_pin_screens_test
/// does), waits for the async crypto, then pumps.
Future<void> _act(WidgetTester t, Future<void> Function() gesture) async {
  await t.runAsync(() async {
    await gesture();
    await Future<void>.delayed(const Duration(milliseconds: 400));
  });
  await t.pump();
}

Future<void> _settle(WidgetTester t) async {
  for (int i = 0; i < 40; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
    // Advances the fake clock too: the client's poll delay is a fake-zone timer.
    await t.pump(const Duration(milliseconds: 60));
  }
}

void main() {
  testWidgets('adult screen: wrong PIN is refused; right PIN opens a window; approval names the device; done only after delivery', (t) async {
    final LocalPinService pin = LocalPinService(MemoryLocalPinRepository(), iterations: 1);
    await t.runAsync(() => pin.setPin('4829'));
    AdultWindow? opened;
    final MemoryPairedKidsRepository kids = MemoryPairedKidsRepository();
    await t.pumpWidget(MaterialApp(
        home: ConnectChildScreen(
      pin: pin,
      deviceKeys: MemoryDeviceKeyRepository(),
      kids: kids,
      adultName: 'Mom',
      childName: 'Ivy',
      makeUnlockVerifier: _cheap,
      localAddress: () async => '192.168.1.5',
      startHost: (AdultWindow w) async {
        opened = w;
        return _FakeHost();
      },
    )));

    await t.enterText(find.byKey(const Key('connectPinField')), '1111');
    await _act(t, () => t.tap(find.byKey(const Key('connectOpen'))));
    expect(find.byKey(const Key('connectMessage')), findsOneWidget);
    expect(opened, isNull, reason: 'a wrong PIN opens nothing');

    await t.enterText(find.byKey(const Key('connectPinField')), '4829');
    await t.tap(find.byKey(const Key('connectOfferQr')));
    await _act(t, () => t.tap(find.byKey(const Key('connectOpen'))));
    expect(find.byKey(const Key('connectWaiting')), findsOneWidget);
    expect(find.byKey(const Key('connectQr')), findsOneWidget, reason: 'the optional picture is offered');
    expect(opened!.qrPayload(), isNotNull);

    final DeviceKey ck = await t.runAsync(() => DeviceKey.loadOrCreate(MemoryDeviceKeyRepository())) as DeviceKey;
    final Future<PairingResult> childRun = ChildPairingClient(
            childKey: ck, transport: LoopbackPairingTransport(opened!), deviceName: 'Tablet', pollEvery: const Duration(milliseconds: 20))
        .pair(sid: opened!.sid, password: '4829');
    await _settle(t);
    expect(find.byKey(const Key('connectApproveTitle')), findsOneWidget);
    expect(find.textContaining("Is this Ivy's Tablet?"), findsOneWidget);
    expect(find.byKey(const Key('connectSas')), findsOneWidget);

    await _act(t, () => t.tap(find.byKey(const Key('connectApprove'))));
    await _settle(t);
    final PairingResult r = await childRun;
    await _settle(t);
    expect(r.ok, isTrue);
    expect(find.byKey(const Key('connectDone')), findsOneWidget);
    expect((await kids.load()).single.deviceName, 'Tablet');
  });

  testWidgets('child screen: only a card until the grown-up taps; no keypad, digits or error words', (t) async {
    await t.pumpWidget(MaterialApp(
        home: ChildConnectScreen(deviceKeys: MemoryDeviceKeyRepository(), onPaired: (_) async {}, finderFactory: _FakeFinder.new)));
    expect(find.byKey(const Key('adultGateCard')), findsOneWidget);
    for (int d = 0; d <= 9; d++) {
      expect(find.text('$d'), findsNothing);
    }
    expect(find.byType(TextField), findsNothing);
    expect(find.textContaining('error'), findsNothing);
  });

  testWidgets('child screen end to end: pick the grown-up by name, type the PIN, match shown, paired', (t) async {
    final DeviceKey ak = await t.runAsync(() => DeviceKey.loadOrCreate(MemoryDeviceKeyRepository())) as DeviceKey;
    final AdultWindow w = await t.runAsync(() => AdultWindow.open(
        adultKey: ak, adultName: 'Mom', familyId: 'fam', childId: 'kid', childName: 'Ivy', pin: '4829', makeUnlockVerifier: _cheap)) as AdultWindow;
    w.addListener(() async {
      if (w.state == WindowState.awaitingApproval) await w.approve();
    });
    final _FakeFinder finder = _FakeFinder();
    ChildPairing? got;
    await t.pumpWidget(MaterialApp(
        home: ChildConnectScreen(
      deviceKeys: MemoryDeviceKeyRepository(),
      finderFactory: () => finder,
      transportFor: (String h, int p) => LoopbackPairingTransport(w),
      pollEvery: const Duration(milliseconds: 20),
      onPaired: (ChildPairing p) async => got = p,
    )));
    await t.tap(find.byKey(const Key('adultGateGrownUp')));
    await _settle(t);
    expect(find.byKey(const Key('childConnectWhich')), findsOneWidget);
    finder.emit(NearbyWindow(adultName: 'Mom', sid: w.sid, host: 'x', port: 1));
    await _settle(t);
    await t.tap(find.text('Mom'));
    await t.pumpAndSettle();
    for (final String d in <String>['4', '8', '2', '9']) {
      await t.tap(find.text(d));
      await t.pump();
    }
    await _act(t, () => t.tap(find.byKey(const Key('pinGateConfirm'))));
    expect(got, isNotNull);
    expect(got!.adultName, 'Mom');
    expect(got!.cert.familyId, 'fam');
  });

  testWidgets('child screen: a wrong PIN ends on a calm try-again, with no error words and no counts', (t) async {
    final DeviceKey ak = await t.runAsync(() => DeviceKey.loadOrCreate(MemoryDeviceKeyRepository())) as DeviceKey;
    final AdultWindow w = await t.runAsync(() => AdultWindow.open(
        adultKey: ak, adultName: 'Mom', familyId: 'fam', childId: 'kid', childName: 'Ivy', pin: '4829', makeUnlockVerifier: _cheap)) as AdultWindow;
    final _FakeFinder finder = _FakeFinder();
    bool paired = false;
    await t.pumpWidget(MaterialApp(
        home: ChildConnectScreen(
      deviceKeys: MemoryDeviceKeyRepository(),
      finderFactory: () => finder,
      transportFor: (String h, int p) => LoopbackPairingTransport(w),
      onPaired: (_) async => paired = true,
    )));
    await t.tap(find.byKey(const Key('adultGateGrownUp')));
    await _settle(t);
    finder.emit(NearbyWindow(adultName: 'Mom', sid: w.sid, host: 'x', port: 1));
    await _settle(t);
    await t.tap(find.text('Mom'));
    await t.pumpAndSettle();
    for (final String d in <String>['1', '1', '1', '1']) {
      await t.tap(find.text(d));
      await t.pump();
    }
    await _act(t, () => t.tap(find.byKey(const Key('pinGateConfirm'))));
    expect(paired, isFalse);
    expect(find.byKey(const Key('childConnectTryAgain')), findsOneWidget);
    for (final String bad in <String>['wrong', 'Incorrect', 'error', 'failed', 'left', 'attempt']) {
      expect(find.textContaining(bad), findsNothing, reason: bad);
    }
    expect(w.attemptsLeft, 4, reason: 'the count lives on the adult device');
  });
}
