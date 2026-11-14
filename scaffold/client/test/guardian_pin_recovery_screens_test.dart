// OLIVE BRANCH — the adult screens for recovering a forgotten local PIN from a second grown-up's phone. Verified by
// CI, headless. MASTERFILE section 7.12.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/device_keys.dart';
import 'package:olive_client/guardian_local_scope.dart';
import 'package:olive_client/local_pin.dart';
import 'package:olive_client/local_pin_recovery.dart';
import 'package:olive_client/guardian_pin_recovery_screens.dart';
import 'package:olive_client/local_pin_screens.dart';

Future<void> _settle(WidgetTester t) async {
  for (int i = 0; i < 20; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
    await t.pump(const Duration(milliseconds: 30));
  }
}

/// Records the challenge the screen shows, so a test can answer it without a camera.
class _SpyRequester extends PinResetRequester {
  _SpyRequester({required super.key, required super.repo});
  PinResetChallenge? last;
  @override
  Future<PinResetChallenge?> issue() async => last = await super.issue();
}

class _SpyRecovery extends GuardianRecovery {
  _SpyRecovery({required super.peers, required super.deviceKey});
  _SpyRequester? spy;
  @override
  Future<PinResetRequester> requester() async => spy = _SpyRequester(key: await deviceKey(), repo: peers);
}

class _Phone {
  _Phone(this.key, this.peers, this.pin) : recovery = _SpyRecovery(peers: peers, deviceKey: () async => key);
  final DeviceKey key;
  final MemoryGuardianPeerRepository peers;
  final LocalPinService pin;
  final _SpyRecovery recovery;
}

Future<_Phone> _phone(WidgetTester t, String pin) async {
  final DeviceKey k = (await t.runAsync(() => DeviceKey.loadOrCreate(MemoryDeviceKeyRepository())))!;
  final LocalPinService s = LocalPinService(MemoryLocalPinRepository(), iterations: 1);
  await t.runAsync(() => s.setPin(pin));
  return _Phone(k, MemoryGuardianPeerRepository(), s);
}

Future<void> _link(WidgetTester t, _Phone a, _Phone b) async {
  await t.runAsync(() async {
    final GuardianLinker la = await a.recovery.linker(), lb = await b.recovery.linker();
    await la.accept(await lb.offer('Dad phone'));
    await lb.accept(await la.offer('Mum phone'));
  });
}

void main() {
  testWidgets('forgot, with no linked phone: says plainly that clearing the app is the only reset, offers no reset', (t) async {
    final _Phone a = await _phone(t, '4829');
    await t.pumpWidget(MaterialApp(home: ForgotPinScreen(pin: a.pin, recovery: a.recovery)));
    await _settle(t);
    expect(find.byKey(const Key('forgotNoRecovery')), findsOneWidget);
    expect(find.textContaining('erases the family'), findsOneWidget);
    expect(find.byKey(const Key('forgotChallengeQr')), findsNothing);
    expect(find.byKey(const Key('localPinNew')), findsNothing);
  });

  testWidgets('forgot, with no recovery services at all: the same plain words', (t) async {
    final _Phone a = await _phone(t, '4829');
    await t.pumpWidget(MaterialApp(home: ForgotPinScreen(pin: a.pin, recovery: null)));
    await _settle(t);
    expect(find.byKey(const Key('forgotNoRecovery')), findsOneWidget);
  });

  testWidgets('forgot: a wrong picture sets nothing up and leaves the PIN as it was', (t) async {
    final _Phone a = await _phone(t, '4829'), b = await _phone(t, '7316');
    await _link(t, a, b);
    void Function(String)? feed;
    await t.pumpWidget(MaterialApp(
        home: ForgotPinScreen(
      pin: a.pin,
      recovery: a.recovery,
      scannerBuilder: (void Function(String) onValue) {
        feed = onValue;
        return const SizedBox();
      },
    )));
    await _settle(t);
    expect(find.byKey(const Key('forgotChallengeQr')), findsOneWidget);
    await t.tap(find.byKey(const Key('forgotScanAnswer')));
    await t.pump();
    feed!('olive://pin-reset-ok/1?n=AAAA&h=BBBB&s=CCCC');
    await _settle(t);
    expect(find.byKey(const Key('forgotMessage')), findsOneWidget);
    expect(find.byKey(const Key('localPinNew')), findsNothing, reason: 'a wrong picture sets nothing up');
    expect((await t.runAsync(() => a.pin.verify('4829')))!.ok, isTrue, reason: 'the PIN is untouched');

  });

  testWidgets('forgot: the screen accepts the answer to ITS OWN picture, then a new PIN replaces the old one and links stay', (t) async {
    final _Phone a = await _phone(t, '4829'), b = await _phone(t, '7316');
    await _link(t, a, b);
    void Function(String)? feed;
    final GlobalKey shown = GlobalKey();
    await t.pumpWidget(MaterialApp(
        home: ForgotPinScreen(
      key: shown,
      pin: a.pin,
      recovery: a.recovery,
      scannerBuilder: (void Function(String) onValue) {
        feed = onValue;
        return const SizedBox();
      },
    )));
    await _settle(t);
    // The challenge the screen is showing, as the spy requester recorded it.
    final String qrData = a.recovery.spy!.last!.toQr();
    final PinResetHelper h = (await t.runAsync(() => b.recovery.helper()))!;
    final PinResetView v = (await t.runAsync<PinResetView?>(() => h.inspect(qrData)))!;
    final String grant = (await t.runAsync(() => h.grant(v)))!;
    await t.tap(find.byKey(const Key('forgotScanAnswer')));
    await t.pump();
    feed!(grant);
    await _settle(t);
    expect(find.byKey(const Key('forgotApproved')), findsOneWidget);
    await t.enterText(find.byKey(const Key('localPinNew')), '8260');
    await t.enterText(find.byKey(const Key('localPinConfirm')), '8260');
    await t.tap(find.byKey(const Key('localPinSave')));
    await _settle(t);
    expect((await t.runAsync(() => a.pin.verify('8260')))!.ok, isTrue);
    expect((await t.runAsync(() => a.pin.verify('4829')))!.ok, isFalse);
    expect(await a.peers.load(), hasLength(1), reason: 'a reset never touches the links');
  });

  testWidgets('approve: a stranger picture is refused; a wrong own PIN is refused; the right PIN shows a one-time answer', (t) async {
    final _Phone a = await _phone(t, '4829'), b = await _phone(t, '7316'), s = await _phone(t, '1111');
    await _link(t, a, b);
    void Function(String)? feed;
    await t.pumpWidget(MaterialApp(
        home: ApprovePinResetScreen(
      pin: b.pin,
      recovery: b.recovery,
      scannerBuilder: (void Function(String) onValue) {
        feed = onValue;
        return const SizedBox();
      },
    )));
    final PinResetChallenge strange = (await t.runAsync<PinResetChallenge?>(() async {
      await s.recovery.linker();
      await s.peers.save(<GuardianPeer>[GuardianPeer(publicKey: b.key.publicKey, label: 'x', linkedAtMs: 1)]);
      return (await s.recovery.requester()).issue();
    }))!;
    feed!(strange.toQr());
    await _settle(t);
    expect(find.byKey(const Key('approveMessage')), findsOneWidget);
    expect(find.byKey(const Key('approveTitle')), findsNothing);

    final PinResetChallenge real = (await t.runAsync<PinResetChallenge?>(() async => (await a.recovery.requester()).issue()))!;
    feed!(real.toQr());
    await _settle(t);
    expect(find.byKey(const Key('approveTitle')), findsOneWidget);
    expect(find.textContaining('Mum phone'), findsOneWidget, reason: 'named as the helper phone knows it');
    await t.enterText(find.byKey(const Key('approvePin')), '0000');
    await t.tap(find.byKey(const Key('approveYes')));
    await _settle(t);
    expect(find.byKey(const Key('approveAnswerQr')), findsNothing);
    expect(find.text('That is not your PIN.'), findsOneWidget);
    await t.enterText(find.byKey(const Key('approvePin')), '7316');
    await t.tap(find.byKey(const Key('approveYes')));
    await _settle(t);
    expect(find.byKey(const Key('approveAnswerQr')), findsOneWidget);
  });

  testWidgets('phones screen: wrong PIN refused, right PIN opens it, linking by scan lists the phone, remove forgets it', (t) async {
    final _Phone a = await _phone(t, '4829'), b = await _phone(t, '7316');
    void Function(String)? feed;
    await t.pumpWidget(MaterialApp(
        home: GuardianPhonesScreen(
      pin: a.pin,
      recovery: a.recovery,
      scannerBuilder: (void Function(String) onValue) {
        feed = onValue;
        return const SizedBox();
      },
    )));
    await t.enterText(find.byKey(const Key('phonesPin')), '1234');
    await t.tap(find.byKey(const Key('phonesUnlock')));
    await _settle(t);
    expect(find.byKey(const Key('phonesOfferQr')), findsNothing);
    expect(find.text('That is not your PIN.'), findsOneWidget);
    await t.enterText(find.byKey(const Key('phonesPin')), '4829');
    await t.tap(find.byKey(const Key('phonesUnlock')));
    await _settle(t);
    expect(find.byKey(const Key('phonesOfferQr')), findsOneWidget);
    expect(find.byKey(const Key('phonesNone')), findsOneWidget);

    await t.scrollUntilVisible(find.byKey(const Key('phonesScan')), 200, scrollable: find.byType(Scrollable).first);
    await t.tap(find.byKey(const Key('phonesScan')));
    await t.pump();
    final String offer = (await t.runAsync(() async => (await b.recovery.linker()).offer('Mum phone')))!;
    feed!('hello');
    await _settle(t);
    expect(await a.peers.load(), isEmpty);
    feed!(offer);
    await _settle(t);
    expect(await a.peers.load(), hasLength(1));
    await t.scrollUntilVisible(find.byKey(const Key('phonesPeer0')), -200, scrollable: find.byType(Scrollable).first);
    expect(find.byKey(const Key('phonesPeer0')), findsOneWidget);
    expect(find.text('Mum phone'), findsOneWidget);
    await t.tap(find.byKey(const Key('phonesRemove0')));
    await _settle(t);
    expect(await a.peers.load(), isEmpty);
  });

  testWidgets('the PIN prompt offers "Forgot your PIN?" only for this device PIN inside the guardian scope', (t) async {
    final GuardianLocalServices svc = GuardianLocalServices.memory();
    await t.runAsync(() => svc.pin.setPin('4829'));
    final LocalPinService other = LocalPinService(MemoryLocalPinRepository(), iterations: 1);
    Future<void> open(LocalPinService s) async {
      // The scope sits ABOVE the Navigator, as the guardian app puts it, so a dialog route can see it.
      await t.pumpWidget(GuardianLocalScope(
        controller: GuardianLocalController(svc),
        child: MaterialApp(
          home: Builder(builder: (BuildContext c) => TextButton(onPressed: () => askLocalPin(c, s), child: const Text('go'))),
        ),
      ));
      await t.tap(find.text('go'));
      await t.pumpAndSettle();
    }

    await open(svc.pin);
    expect(find.byKey(const Key('localPinForgot')), findsOneWidget);
    await t.tap(find.byKey(const Key('localPinCancel')));
    await t.pumpAndSettle();
    await open(other);
    expect(find.byKey(const Key('localPinForgot')), findsNothing);
  });

  for (final double w in <double>[344, 390, 600, 800]) {
    for (final double scale in <double>[1.0, 2.0]) {
      testWidgets('posture: forgot, phones and approve screens fit ${w}dp at ${scale}x text with no overflow', (t) async {
        final _Phone a = await _phone(t, '4829'), b = await _phone(t, '7316');
        await _link(t, a, b);
        Future<void> show(Widget screen) async {
          await t.binding.setSurfaceSize(Size(w, 760));
          await t.pumpWidget(MaterialApp(
              home: MediaQuery(data: MediaQueryData(size: Size(w, 760), textScaler: TextScaler.linear(scale)), child: screen)));
          await _settle(t);
          expect(t.takeException(), isNull);
        }

        addTearDown(() => t.binding.setSurfaceSize(null));
        await show(ForgotPinScreen(pin: a.pin, recovery: a.recovery, scannerBuilder: (_) => const SizedBox()));
        await show(ForgotPinScreen(pin: a.pin, recovery: null));
        await show(ApprovePinResetScreen(pin: b.pin, recovery: b.recovery, scannerBuilder: (_) => const SizedBox()));
        await show(GuardianPhonesScreen(pin: a.pin, recovery: a.recovery, scannerBuilder: (_) => const SizedBox()));
        await t.enterText(find.byKey(const Key('phonesPin')), '4829');
        await t.tap(find.byKey(const Key('phonesUnlock')));
        await _settle(t);
        expect(find.byKey(const Key('phonesPin')), findsNothing, reason: 'unlocked');
        expect(t.takeException(), isNull);
      });
    }
  }
}
