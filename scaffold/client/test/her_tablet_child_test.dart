// OLIVE BRANCH — "Her tablet" on the TABLET and the two screens together: "Connect to a phone" (six numbers), the whole code
// way end to end across both screens with the real key exchange, a mistyped code, a child tapping, the simulation seam, and the
// connected-state buttons. Verified by CI, headless. The transport is in-process here; the real LAN transport carries the same
// messages in her_tablet_connect_e2e_test.dart.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/adult_gate.dart';
import 'package:olive_client/child_connect_screen.dart';
import 'package:olive_client/connect_child_screen.dart';
import 'package:olive_client/device_keys.dart';
import 'package:olive_client/lan_pairing_transport.dart';
import 'package:olive_client/local_pin.dart';
import 'package:olive_client/pairing_limits.dart';
import 'package:olive_client/pairing_picture.dart';
import 'package:olive_client/pairing_protocol.dart';
import 'package:olive_client/pairing_records.dart';
import 'package:olive_client/pairing_trust.dart';
import 'package:olive_client/unlock_challenge.dart';

Future<LocalPinRecord> _cheap(String pin) async => LocalPinRecord(iterations: 1, salt: Uint8List(16), hash: Uint8List(32));

class _FakeHost implements WindowHost {
  @override
  int? get port => 4242;
  @override
  Future<void> stop() async {}
  @override
  Future<void> readvertise() async {}
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

/// Real time for the async crypto, then fake time for the screens' timers, repeatedly.
Future<void> _settle(WidgetTester t, {int rounds = 50}) async {
  for (int i = 0; i < rounds; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
    await t.pump(const Duration(milliseconds: 80));
  }
}

Future<void> _act(WidgetTester t, Future<void> Function() gesture) async {
  await t.runAsync(() async {
    await gesture();
    await Future<void>.delayed(const Duration(milliseconds: 400));
  });
  await t.pump();
}

void main() {
  group('the tablet: the grown-up button reveals "Connect to a phone"', () {
    testWidgets('a child sees only the card; the grown-up tap shows one big "Connect to a phone"; its numbers show only then', (t) async {
      await t.pumpWidget(MaterialApp(
          home: ChildConnectScreen(deviceKeys: MemoryDeviceKeyRepository(), onPaired: (_) async {}, finderFactory: _FakeFinder.new, simulate: false)));
      expect(find.byKey(const Key('adultGateCard')), findsOneWidget);
      expect(find.byKey(const Key('childConnectToPhone')), findsNothing);
      expect(find.byKey(const Key('childCodeDigits')), findsNothing);
      await t.tap(find.byKey(const Key('adultGateGrownUp')));
      await _settle(t, rounds: 2);
      expect(find.byKey(const Key('childConnectToPhone')), findsOneWidget);
      expect(find.text('Connect to a phone'), findsOneWidget);
      expect(find.byKey(const Key('childCodeDigits')), findsNothing, reason: 'nothing is shown until Connect to a phone is tapped');
      expect(t.getSize(find.byKey(const Key('childConnectToPhone'))).height, greaterThanOrEqualTo(56));
      expect(find.byKey(const Key('childConnectSimulate')), findsNothing, reason: 'no simulation in a normal build');
      await t.tap(find.byKey(const Key('childConnectToPhone')));
      await _settle(t, rounds: 3);
      final String digits = t.widget<Text>(find.byKey(const Key('childCodeDigits'))).data!;
      expect(RegExp(r'^\d{3} \d{3}$').hasMatch(digits), isTrue, reason: 'six numbers in two groups: "$digits"');
      for (final String bad in <String>['rror', 'wrong', 'failed', 'PIN', 'denied']) {
        expect(find.textContaining(bad), findsNothing, reason: 'no error words on the tablet: $bad');
      }
    });

    testWidgets('a fresh set of numbers each time the screen is opened', (t) async {
      await t.pumpWidget(MaterialApp(
          home: ChildConnectScreen(deviceKeys: MemoryDeviceKeyRepository(), onPaired: (_) async {}, finderFactory: _FakeFinder.new, simulate: false)));
      final Set<String> seen = <String>{};
      await t.tap(find.byKey(const Key('adultGateGrownUp')));
      await _settle(t, rounds: 2);
      for (int i = 0; i < 6; i++) {
        await t.tap(find.byKey(const Key('childConnectToPhone')));
        await _settle(t, rounds: 2);
        seen.add(t.widget<Text>(find.byKey(const Key('childCodeDigits'))).data!);
        await t.tap(find.byKey(const Key('childCodeBack')));
        await _settle(t, rounds: 2);
      }
      expect(seen.length, greaterThan(1), reason: 'six runs gave more than one distinct set of numbers');
    });

    testWidgets('a child alone: nothing nearby, so it just waits; no error, no way to finish; Back returns to the grown-up screen', (t) async {
      bool paired = false;
      await t.pumpWidget(MaterialApp(
          home: ChildConnectScreen(deviceKeys: MemoryDeviceKeyRepository(), onPaired: (_) async => paired = true, finderFactory: _FakeFinder.new, simulate: false)));
      await t.tap(find.byKey(const Key('adultGateGrownUp')));
      await _settle(t, rounds: 2);
      await t.tap(find.byKey(const Key('childConnectToPhone')));
      await _settle(t, rounds: 120); // a long time with nobody there
      expect(paired, isFalse);
      expect(find.byKey(const Key('childCodeDigits')), findsOneWidget, reason: 'still waiting, calmly');
      expect(find.byKey(const Key('childConnectTryAgain')), findsNothing);
      await t.tap(find.byKey(const Key('childCodeBack')));
      await _settle(t, rounds: 2);
      expect(find.byKey(const Key('childConnectToPhone')), findsOneWidget);
    });

    testWidgets('large text and a narrow or a wide screen: the numbers and the picture fit, no overflow', (t) async {
      for (final Size size in <Size>[const Size(904, 700), const Size(800, 1280), const Size(1280, 800), const Size(360, 640)]) {
        await t.binding.setSurfaceSize(size);
        addTearDown(() => t.binding.setSurfaceSize(null));
        await t.pumpWidget(MediaQuery(
          data: MediaQueryData(size: size, textScaler: const TextScaler.linear(2.0)),
          child: MaterialApp(
              key: UniqueKey(),
              home: ChildConnectScreen(
                  deviceKeys: MemoryDeviceKeyRepository(), onPaired: (_) async {}, finderFactory: _FakeFinder.new, simulate: false,
                  pictures: MemoryPairingPictureRepository())),
        ));
        await t.tap(find.byKey(const Key('adultGateGrownUp')));
        await _settle(t, rounds: 2);
        await t.tap(find.byKey(const Key('childConnectToPhone')));
        await _settle(t, rounds: 4);
        expect(t.takeException(), isNull, reason: '$size');
        expect(find.byKey(const Key('childCodeDigits')), findsOneWidget, reason: '$size');
      }
    });
  });

  group('both screens: the numbers way, end to end with the real key exchange', () {
    testWidgets('the grown-up types the six numbers her tablet shows; Match; Yes; connected on both screens, and listed', (t) async {
      await t.binding.setSurfaceSize(const Size(1500, 1500));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final LocalPinService pin = LocalPinService(MemoryLocalPinRepository(), iterations: 1);
      await t.runAsync(() => pin.setPin('4829'));
      final MemoryPairedKidsRepository kids = MemoryPairedKidsRepository();
      final TrustBook trust = TrustBook(MemoryTrustRepository());
      AdultWindow? opened;
      ChildPairing? got;
      bool phoneSaidConnected = false;
      final _FakeFinder finder = _FakeFinder();

      await t.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: Row(children: <Widget>[
          Expanded(
            child: MaterialApp(
                home: ConnectChildScreen(
              pin: pin, deviceKeys: MemoryDeviceKeyRepository(), kids: kids, trust: trust, adultName: 'Mom', childName: 'Ivy',
              makeUnlockVerifier: _cheap, localAddress: () async => '192.0.2.5', simulate: false,
              onConnected: () => phoneSaidConnected = true,
              startHost: (AdultWindow w) async {
                opened = w;
                return _FakeHost();
              },
            )),
          ),
          Expanded(
            child: MaterialApp(
                home: ChildConnectScreen(
              deviceKeys: MemoryDeviceKeyRepository(), finderFactory: () => finder, simulate: false,
              codeSettle: const Duration(milliseconds: 10), codeRetryEvery: const Duration(milliseconds: 50),
              transportFor: (String h, int p) => LoopbackPairingTransport(opened!),
              pollEvery: const Duration(milliseconds: 30),
              onPaired: (ChildPairing p) async => got = p,
            )),
          ),
        ]),
      ));

      // The grown-up types their PIN on the phone and starts: the numbers way is already chosen.
      await t.enterText(find.byKey(const Key('connectPinField')), '4829');
      await _act(t, () => t.tap(find.byKey(const Key('connectOpen'))));
      expect(opened, isNotNull);
      expect(opened!.awaitCode, isTrue);
      expect(find.byKey(const Key('connectCodeField')), findsOneWidget);
      expect(find.text("Waiting for Ivy's tablet…"), findsOneWidget);

      // On the tablet: the grown-up button, then "Connect to a phone".
      await t.tap(find.byKey(const Key('adultGateGrownUp')));
      await _settle(t, rounds: 2);
      await t.tap(find.byKey(const Key('childConnectToPhone')));
      await _settle(t, rounds: 2);
      finder.emit(NearbyWindow(label: opened!.label, handle: opened!.discoveryHandle, host: 'x', port: 1));
      await _settle(t, rounds: 12);
      final String code = t.widget<Text>(find.byKey(const Key('childCodeDigits'))).data!.replaceAll(' ', '');
      expect(opened!.tabletSeen, isTrue, reason: 'the tablet found the window by itself');
      expect(find.text("Ivy's tablet found this phone."), findsOneWidget, reason: 'the phone says so, live');

      // The grown-up types the numbers on the phone (it sends on the sixth, no extra tap).
      await t.enterText(find.byKey(const Key('connectCodeField')), code);
      await _settle(t, rounds: 30);

      // Match: three pictures and a colour on the tablet; the grown-up picks the same card on the phone.
      expect(find.byKey(const Key('childConnectMatch')), findsOneWidget);
      await t.tap(find.byKey(Key('connectMatch_${opened!.matchChoices!.correct}')));
      await t.pump();
      await _act(t, () => t.tap(find.byKey(const Key('connectApprove'))));
      await _settle(t, rounds: 40);

      expect(got, isNotNull, reason: 'the tablet was handed its connection');
      expect(got!.adultName, 'Mom');
      expect(find.byKey(const Key('connectDone')), findsOneWidget);
      expect(phoneSaidConnected, isTrue);
      expect((await t.runAsync(() => kids.load()))!.length, 1, reason: 'listed only now that the tablet has it');
    });

    testWidgets('a mistyped code: the phone says so plainly, the tablet asks again by itself, and the right numbers then connect', (t) async {
      await t.binding.setSurfaceSize(const Size(1500, 1500));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final LocalPinService pin = LocalPinService(MemoryLocalPinRepository(), iterations: 1);
      await t.runAsync(() => pin.setPin('4829'));
      final MemoryPairedKidsRepository kids = MemoryPairedKidsRepository();
      AdultWindow? opened;
      ChildPairing? got;
      final _FakeFinder finder = _FakeFinder();
      await t.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: Row(children: <Widget>[
          Expanded(
            child: MaterialApp(
                home: ConnectChildScreen(
              pin: pin, deviceKeys: MemoryDeviceKeyRepository(), kids: kids, adultName: 'Mom', childName: 'Ivy',
              makeUnlockVerifier: _cheap, localAddress: () async => null, simulate: false,
              startHost: (AdultWindow w) async {
                opened = w;
                return _FakeHost();
              },
            )),
          ),
          Expanded(
            child: MaterialApp(
                home: ChildConnectScreen(
              deviceKeys: MemoryDeviceKeyRepository(), finderFactory: () => finder, simulate: false,
              codeSettle: const Duration(milliseconds: 10), codeRetryEvery: const Duration(milliseconds: 50),
              transportFor: (String h, int p) => LoopbackPairingTransport(opened!),
              pollEvery: const Duration(milliseconds: 30),
              onPaired: (ChildPairing p) async => got = p,
            )),
          ),
        ]),
      ));
      await t.enterText(find.byKey(const Key('connectPinField')), '4829');
      await _act(t, () => t.tap(find.byKey(const Key('connectOpen'))));
      await t.tap(find.byKey(const Key('adultGateGrownUp')));
      await _settle(t, rounds: 2);
      await t.tap(find.byKey(const Key('childConnectToPhone')));
      await _settle(t, rounds: 2);
      finder.emit(NearbyWindow(label: opened!.label, handle: opened!.discoveryHandle, host: 'x', port: 1));
      await _settle(t, rounds: 12);
      final String code = t.widget<Text>(find.byKey(const Key('childCodeDigits'))).data!.replaceAll(' ', '');
      final String wrong = code == '000000' ? '111111' : '000000';

      await t.enterText(find.byKey(const Key('connectCodeField')), wrong);
      await _settle(t, rounds: 40);
      expect(find.byKey(const Key('connectCodeNote')), findsOneWidget);
      expect(find.textContaining('That was not it'), findsOneWidget);
      expect(find.byKey(const Key('childConnectTryAgain')), findsNothing, reason: 'the tablet shows no error: it keeps its numbers up');
      expect(find.byKey(const Key('childCodeDigits')), findsOneWidget);
      expect(got, isNull);

      await t.enterText(find.byKey(const Key('connectCodeField')), code);
      await _settle(t, rounds: 30);
      await t.tap(find.byKey(Key('connectMatch_${opened!.matchChoices!.correct}')));
      await t.pump();
      await _act(t, () => t.tap(find.byKey(const Key('connectApprove'))));
      await _settle(t, rounds: 40);
      expect(got, isNotNull);
      expect(find.byKey(const Key('connectDone')), findsOneWidget);
    });

    testWidgets('"None of these" at the Match step: nothing is shared, the phone says so, and starting again is one tap', (t) async {
      await t.binding.setSurfaceSize(const Size(1500, 1500));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final LocalPinService pin = LocalPinService(MemoryLocalPinRepository(), iterations: 1);
      await t.runAsync(() => pin.setPin('4829'));
      final MemoryPairedKidsRepository kids = MemoryPairedKidsRepository();
      AdultWindow? opened;
      ChildPairing? got;
      final _FakeFinder finder = _FakeFinder();
      await t.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: Row(children: <Widget>[
          Expanded(
            child: MaterialApp(
                home: ConnectChildScreen(
              pin: pin, deviceKeys: MemoryDeviceKeyRepository(), kids: kids, adultName: 'Mom', childName: 'Ivy', lock: AddingLock(),
              cooldown: FailureCooldown(), makeUnlockVerifier: _cheap, localAddress: () async => null, simulate: false,
              startHost: (AdultWindow w) async {
                opened = w;
                return _FakeHost();
              },
            )),
          ),
          Expanded(
            child: MaterialApp(
                home: ChildConnectScreen(
              deviceKeys: MemoryDeviceKeyRepository(), finderFactory: () => finder, simulate: false,
              codeSettle: const Duration(milliseconds: 10),
              transportFor: (String h, int p) => LoopbackPairingTransport(opened!),
              pollEvery: const Duration(milliseconds: 30),
              onPaired: (ChildPairing p) async => got = p,
            )),
          ),
        ]),
      ));
      await t.enterText(find.byKey(const Key('connectPinField')), '4829');
      await _act(t, () => t.tap(find.byKey(const Key('connectOpen'))));
      await t.tap(find.byKey(const Key('adultGateGrownUp')));
      await _settle(t, rounds: 2);
      await t.tap(find.byKey(const Key('childConnectToPhone')));
      await _settle(t, rounds: 2);
      finder.emit(NearbyWindow(label: opened!.label, handle: opened!.discoveryHandle, host: 'x', port: 1));
      await _settle(t, rounds: 12);
      final String code = t.widget<Text>(find.byKey(const Key('childCodeDigits'))).data!.replaceAll(' ', '');
      await t.enterText(find.byKey(const Key('connectCodeField')), code);
      await _settle(t, rounds: 30);
      await t.tap(find.byKey(const Key('connectMatchNone')));
      await _settle(t, rounds: 20);
      expect(got, isNull);
      expect(await t.runAsync(() => kids.load()), isEmpty);
      expect(find.textContaining('Nothing was shared'), findsOneWidget);
      expect(find.byKey(const Key('connectOpen')), findsOneWidget, reason: 'back to the first step, ready to start again');
    });
  });

  group('the simulation seam (dev only): one device shows the whole flow with a simulated other end', () {
    testWidgets('a normal build has no simulation anywhere', (t) async {
      final LocalPinService pin = LocalPinService(MemoryLocalPinRepository(), iterations: 1);
      await t.runAsync(() => pin.setPin('4829'));
      await t.binding.setSurfaceSize(const Size(500, 1600));
      addTearDown(() => t.binding.setSurfaceSize(null));
      AdultWindow? opened;
      await t.pumpWidget(MaterialApp(
          home: ConnectChildScreen(
        pin: pin, deviceKeys: MemoryDeviceKeyRepository(), kids: MemoryPairedKidsRepository(), adultName: 'Mom', childName: 'Ivy',
        makeUnlockVerifier: _cheap, localAddress: () async => null,
        startHost: (AdultWindow w) async {
          opened = w;
          return _FakeHost();
        },
      )));
      await t.enterText(find.byKey(const Key('connectPinField')), '4829');
      await _act(t, () => t.tap(find.byKey(const Key('connectOpen'))));
      expect(opened, isNotNull);
      expect(find.byKey(const Key('connectSimCard')), findsNothing);
      expect(find.byKey(const Key('connectSimulate')), findsNothing);
    });

    testWidgets('simulate her tablet: the phone walks every step with a tablet that says it is simulated, and really lists it', (t) async {
      await t.binding.setSurfaceSize(const Size(500, 1800));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final LocalPinService pin = LocalPinService(MemoryLocalPinRepository(), iterations: 1);
      await t.runAsync(() => pin.setPin('4829'));
      final MemoryPairedKidsRepository kids = MemoryPairedKidsRepository();
      AdultWindow? opened;
      await t.pumpWidget(MaterialApp(
          home: ConnectChildScreen(
        pin: pin, deviceKeys: MemoryDeviceKeyRepository(), kids: kids, adultName: 'Mom', childName: 'Ivy', simulate: true,
        makeUnlockVerifier: _cheap, localAddress: () async => null,
        startHost: (AdultWindow w) async {
          opened = w;
          return _FakeHost();
        },
      )));
      await t.enterText(find.byKey(const Key('connectPinField')), '4829');
      await _act(t, () => t.tap(find.byKey(const Key('connectOpen'))));
      expect(find.byKey(const Key('connectSimCard')), findsOneWidget);
      expect(find.textContaining('Simulated tablet'), findsWidgets);
      await _act(t, () => t.tap(find.byKey(const Key('connectSimulate'))));
      await _settle(t, rounds: 6);
      final String code = t.widget<Text>(find.byKey(const Key('connectSimCode'))).data!;
      expect(isPairingCode(code), isTrue);
      await t.enterText(find.byKey(const Key('connectCodeField')), code);
      await _settle(t, rounds: 30);
      expect(find.byKey(const Key('connectSimMatch')), findsOneWidget, reason: 'the simulated tablet "shows" its pictures, labelled');
      expect(find.textContaining('simulated tablet shows'), findsOneWidget);
      await t.tap(find.byKey(Key('connectMatch_${opened!.matchChoices!.correct}')));
      await t.pump();
      await _act(t, () => t.tap(find.byKey(const Key('connectApprove'))));
      await _settle(t, rounds: 40);
      expect(find.byKey(const Key('connectDone')), findsOneWidget);
      final List<PairedKid> list = (await t.runAsync(() => kids.load()))!;
      expect(list.single.deviceName, 'Simulated tablet', reason: 'a real record, plainly named as simulated');
    });

    testWidgets('simulate a phone: the tablet shows its numbers and a banner, a simulated grown-up types them, and it ends connected', (t) async {
      ChildPairing? got;
      await t.pumpWidget(MaterialApp(
          home: ChildConnectScreen(
        deviceKeys: MemoryDeviceKeyRepository(), onPaired: (ChildPairing p) async => got = p, finderFactory: _FakeFinder.new,
        simulate: true, pollEvery: const Duration(milliseconds: 30), codeRetryEvery: const Duration(milliseconds: 50),
      )));
      await t.tap(find.byKey(const Key('adultGateGrownUp')));
      await _settle(t, rounds: 2);
      expect(find.byKey(const Key('childConnectSimulate')), findsOneWidget);
      await t.tap(find.byKey(const Key('childConnectSimulate')));
      await _settle(t, rounds: 4);
      expect(find.byKey(const Key('childSimBanner')), findsOneWidget);
      expect(find.textContaining('Simulated phone'), findsOneWidget);
      await _settle(t, rounds: 90);
      expect(got, isNotNull, reason: 'the whole real exchange ran against the simulated phone');
      expect(got!.adultName, 'Simulated phone');
    });
  });

  group('the tablet, connected: three big plain buttons, and a child alone changes nothing', () {
    testWidgets('Type my code, Use my phone and Disconnect this tablet are all big; Disconnect only shows a picture for the phone', (t) async {
      final DeviceKey ck = await t.runAsync(() => DeviceKey.loadOrCreate(MemoryDeviceKeyRepository())) as DeviceKey;
      final DeviceKey ak = await t.runAsync(() => DeviceKey.loadOrCreate(MemoryDeviceKeyRepository())) as DeviceKey;
      final PairingCert cert = await t.runAsync(() => PairingCert.issue(ak, childDeviceKey: ck.publicKey, familyId: 'f', childId: 'c', certId: 'x', issuedAtMs: 1)) as PairingCert;
      int forgot = 0;
      final ChildUnlockHost host = ChildUnlockHost(childKey: ck, adultKey: ak.publicKey, cert: cert, onForget: () async => forgot++);
      await t.pumpWidget(MaterialApp(home: AdultGate(digits: 8, onPin: (_) {}, startOpen: true, phone: PhoneUnlock(host: host))));
      await t.pump();
      for (final String k in <String>['adultGateTypeCode', 'adultGateUsePhone', 'adultGateDisconnect']) {
        expect(find.byKey(Key(k)), findsOneWidget, reason: k);
        expect(t.getSize(find.byKey(Key(k))).height, greaterThanOrEqualTo(56), reason: '$k is big');
      }
      await t.tap(find.byKey(const Key('adultGateDisconnect')));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('adultGatePhone')), findsOneWidget, reason: 'it only shows the picture the grown-up\'s phone must answer');
      expect(forgot, 0, reason: 'a child tapping changes nothing: the tablet is not disconnected by being asked');
    });
  });
}
