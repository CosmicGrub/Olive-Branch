// OLIVE BRANCH — the "Her tablet" umbrella on the grown-up's phone: every state and every button, the disconnect with its PIN,
// the home banner, the connect screen's methods, a11y labels, large text and the Fold's cover width. Verified by CI, headless.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/connect_child_screen.dart';
import 'package:olive_client/device_keys.dart';
import 'package:olive_client/her_tablet.dart';
import 'package:olive_client/her_tablet_screen.dart';
import 'package:olive_client/local_pin.dart';
import 'package:olive_client/pairing_protocol.dart';
import 'package:olive_client/pairing_records.dart';
import 'package:olive_client/pairing_trust.dart';

PairedKid _kid(String id, {String name = 'Ivy tablet', int at = 1000}) => PairedKid(
    certId: id, childDeviceKey: Uint8List.fromList(List<int>.filled(32, id.codeUnitAt(0))), childId: 'kid', deviceName: name, issuedAtMs: at, phoneOnly: true);

/// A paired-tablet list that cannot be read at all (a damaged store).
class _Unreadable extends MemoryPairedKidsRepository {
  @override
  Future<PairedKidsLoad> loadChecked() async => const PairedKidsLoad(<PairedKid>[], unreadable: true);
}

class _World {
  _World(this.kids, this.trust, this.pin, this.services);
  final PairedKidsRepository kids;
  final TrustBook trust;
  final LocalPinService pin;
  final HerTabletServices services;
}

Future<_World> _world(WidgetTester t, {PairedKidsRepository? kids, List<PairedKid> connected = const <PairedKid>[]}) async {
  final PairedKidsRepository k = kids ?? MemoryPairedKidsRepository();
  final TrustBook trust = TrustBook(MemoryTrustRepository());
  final LocalPinService pin = LocalPinService(MemoryLocalPinRepository(), iterations: 1);
  await t.runAsync(() async {
    await pin.setPin('4829');
    for (final PairedKid x in connected) {
      await k.add(x);
      await trust.add(certId: x.certId, deviceKey: x.childDeviceKey, deviceName: x.deviceName, role: PairedRole.child, addedBy: 'Mom');
    }
  });
  return _World(k, trust, pin, HerTabletServices(kids: k, trust: trust, pin: pin, deviceKeys: MemoryDeviceKeyRepository(), adultName: 'Mom', scannerEnabled: false));
}

Future<void> _open(WidgetTester t, _World w, {double width = 390, double height = 900, double textScale = 1}) async {
  await t.binding.setSurfaceSize(Size(width, height));
  addTearDown(() => t.binding.setSurfaceSize(null));
  await t.pumpWidget(MediaQuery(
    data: MediaQueryData(size: Size(width, height), textScaler: TextScaler.linear(textScale)),
    child: MaterialApp(home: HerTabletScreen(services: w.services, childName: 'Ivy', now: () => DateTime.fromMillisecondsSinceEpoch(1000 + 3 * 86400000))),
  ));
  await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  await t.pumpAndSettle();
}

void main() {
  group('the phone: Her tablet states', () {
    testWidgets('not connected: the headline says so and the ONE big button is "Connect her tablet"', (t) async {
      await _open(t, await _world(t));
      expect(find.byKey(const Key('herTabletHeadline')), findsOneWidget);
      expect(find.text("Ivy's tablet is not connected yet"), findsOneWidget);
      expect(find.byKey(const Key('herTabletConnect')), findsOneWidget);
      expect(find.text('Connect her tablet'), findsOneWidget);
      for (final String k in <String>['herTabletUnlock', 'herTabletDisconnect', 'herTabletChanges', 'herTabletRetry']) {
        expect(find.byKey(Key(k)), findsNothing, reason: '$k does not apply to a tablet that is not connected');
      }
    });

    testWidgets('connected: name, when it was last seen, and Unlock, Disconnect and See what changed; no Connect', (t) async {
      await _open(t, await _world(t, connected: <PairedKid>[_kid('a')]));
      expect(find.text("Ivy's tablet is connected"), findsOneWidget);
      expect(find.byKey(const Key('herTabletName')), findsOneWidget);
      expect(find.text('Ivy tablet'), findsOneWidget);
      expect(find.textContaining('Last seen'), findsOneWidget);
      expect(find.byKey(const Key('herTabletUnlock')), findsOneWidget);
      expect(find.byKey(const Key('herTabletDisconnect')), findsOneWidget);
      expect(find.byKey(const Key('herTabletChanges')), findsOneWidget);
      expect(find.text('Unlock her tablet'), findsOneWidget);
      expect(find.text('Disconnect her tablet'), findsOneWidget);
      expect(find.text('See what changed'), findsOneWidget);
      expect(find.byKey(const Key('herTabletConnect')), findsNothing);
    });

    testWidgets('a second tablet is said, never hidden', (t) async {
      await _open(t, await _world(t, connected: <PairedKid>[_kid('a'), _kid('b', name: 'Spare')]));
      expect(find.byKey(const Key('herTabletOthers')), findsOneWidget);
      expect(find.text('and one more tablet'), findsOneWidget);
    });

    testWidgets('cannot tell: a list that cannot be read says so calmly and offers only "Try again" (never "not connected")', (t) async {
      await _open(t, await _world(t, kids: _Unreadable()));
      expect(find.text("Can't tell right now"), findsOneWidget);
      expect(find.byKey(const Key('herTabletRetry')), findsOneWidget);
      expect(find.byKey(const Key('herTabletConnect')), findsNothing);
      expect(find.byKey(const Key('herTabletDisconnect')), findsNothing);
      expect(find.textContaining('not connected'), findsNothing);
    });

    testWidgets('no sentence on the screen carries a code, a status number or a certificate id', (t) async {
      await _open(t, await _world(t, connected: <PairedKid>[_kid('zz9')]));
      final Iterable<String> words = t.widgetList<Text>(find.byType(Text)).map((Text w) => w.data ?? '');
      for (final String s in words) {
        expect(RegExp(r'\b\d{3,}\b').hasMatch(s), isFalse, reason: '"$s"');
        expect(s.contains('zz9'), isFalse);
      }
    });
  });

  group('the phone: Disconnect her tablet', () {
    testWidgets('behind the PIN: a wrong PIN changes nothing; the right one ends this phone\'s side and says what happens next', (t) async {
      final _World w = await _world(t, connected: <PairedKid>[_kid('a')]);
      await _open(t, w);
      await t.tap(find.byKey(const Key('herTabletDisconnect')));
      await t.pumpAndSettle();
      expect(find.textContaining('told the next time'), findsOneWidget, reason: 'it says plainly when the tablet finds out');
      await t.enterText(find.byKey(const Key('herTabletPinField')), '1111');
      await t.runAsync(() async {
        await t.tap(find.byKey(const Key('herTabletPinOk')));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await t.pumpAndSettle();
      expect(find.text('That is not your PIN.'), findsOneWidget);
      expect((await t.runAsync(() => w.kids.load()))!.length, 1, reason: 'nothing changed');

      await t.enterText(find.byKey(const Key('herTabletPinField')), '4829');
      await t.runAsync(() async {
        await t.tap(find.byKey(const Key('herTabletPinOk')));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await t.pumpAndSettle();
      expect(find.byKey(const Key('herTabletNote')), findsOneWidget);
      expect(find.textContaining('is disconnected from this phone'), findsOneWidget);
      expect((await t.runAsync(() => w.kids.load()))!, isEmpty);
      expect(await t.runAsync(() => w.trust.isRevoked(_kid('a').childDeviceKey)), isTrue, reason: 'the tablet is told when it meets this phone');
      // The screen now offers to connect it again, and says the tablet has not been told yet.
      expect(find.text("Ivy's tablet is not connected yet"), findsOneWidget);
      expect(find.byKey(const Key('herTabletConnect')), findsOneWidget);
      expect(find.textContaining('told the next time it meets this phone'), findsOneWidget);
    });

    testWidgets('Cancel leaves everything as it was', (t) async {
      final _World w = await _world(t, connected: <PairedKid>[_kid('a')]);
      await _open(t, w);
      await t.tap(find.byKey(const Key('herTabletDisconnect')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('herTabletPinCancel')));
      await t.pumpAndSettle();
      expect((await t.runAsync(() => w.kids.load()))!.length, 1);
      expect(find.byKey(const Key('herTabletDisconnect')), findsOneWidget);
    });

    testWidgets('a list that cannot be saved says so and changes nothing: no stuck state', (t) async {
      final _FailingForget k = _FailingForget();
      final _World w = await _world(t, kids: k, connected: <PairedKid>[_kid('a')]);
      k.fail = true;
      await _open(t, w);
      await t.tap(find.byKey(const Key('herTabletDisconnect')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('herTabletPinField')), '4829');
      await t.runAsync(() async {
        await t.tap(find.byKey(const Key('herTabletPinOk')));
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await t.pumpAndSettle();
      expect(find.textContaining('could not be saved'), findsOneWidget);
      expect(find.byKey(const Key('herTabletDisconnect')), findsOneWidget, reason: 'it can be tried again');
    });
  });

  group('the phone: layouts and accessibility', () {
    testWidgets('the Fold cover (904 wide) and a narrow phone: no overflow, every button at least 56 high', (t) async {
      for (final double width in <double>[904, 344]) {
        final _World w = await _world(t, connected: <PairedKid>[_kid('a')]);
        await _open(t, w, width: width);
        expect(t.takeException(), isNull, reason: 'width $width');
        for (final String k in <String>['herTabletUnlock', 'herTabletDisconnect', 'herTabletChanges']) {
          expect(t.getSize(find.byKey(Key(k))).height, greaterThanOrEqualTo(56), reason: '$k at $width');
        }
      }
    });

    testWidgets('twice the text size: still no overflow and the buttons are still there', (t) async {
      final _World w = await _world(t, connected: <PairedKid>[_kid('a')]);
      await _open(t, w, width: 360, textScale: 2.0);
      expect(t.takeException(), isNull);
      expect(find.byKey(const Key('herTabletDisconnect'), skipOffstage: false), findsOneWidget);
    });

    testWidgets('screen readers: the buttons are labelled with their verbs', (t) async {
      final SemanticsHandle h = t.ensureSemantics();
      await _open(t, await _world(t, connected: <PairedKid>[_kid('a')]));
      expect(find.bySemanticsLabel(RegExp('Unlock her tablet')), findsWidgets);
      expect(find.bySemanticsLabel(RegExp('Disconnect her tablet')), findsWidgets);
      h.dispose();
    });
  });

  group('the phone: the home banner', () {
    testWidgets('says where her tablet stands from the real list, and is one tap to the screen', (t) async {
      final _World w = await _world(t, connected: <PairedKid>[_kid('a')]);
      await t.pumpWidget(MaterialApp(home: Scaffold(body: HerTabletBanner(childName: 'Ivy', services: w.services))));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pumpAndSettle();
      expect(find.text("Ivy's tablet: connected"), findsOneWidget);
      await t.tap(find.byKey(const Key('herTabletBanner')));
      await t.pumpAndSettle();
      expect(find.byType(HerTabletScreen), findsOneWidget);
    });

    testWidgets('not connected: "Connect Ivy\'s tablet"; unreadable: only her name, never a claim', (t) async {
      final _World w = await _world(t);
      await t.pumpWidget(MaterialApp(home: Scaffold(body: HerTabletBanner(childName: 'Ivy', services: w.services))));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pumpAndSettle();
      expect(find.text("Connect Ivy's tablet"), findsOneWidget);
      final _World u = await _world(t, kids: _Unreadable());
      await t.pumpWidget(MaterialApp(home: Scaffold(body: HerTabletBanner(key: UniqueKey(), childName: 'Ivy', services: u.services))));
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await t.pumpAndSettle();
      expect(find.textContaining('connected'), findsNothing);
    });
  });

  group('the phone: Connect her tablet offers every way, the easiest preselected', () {
    testWidgets('three ways with one sentence each; the numbers way is preselected and marked Easiest; no camera is said plainly', (t) async {
      final _World w = await _world(t);
      await t.binding.setSurfaceSize(const Size(390, 1600));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(MaterialApp(
          home: ConnectChildScreen(
        pin: w.pin, deviceKeys: MemoryDeviceKeyRepository(), kids: w.kids, adultName: 'Mom', childName: 'Ivy', scannerEnabled: false,
      )));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('connectMethod_code')), findsOneWidget);
      expect(find.byKey(const Key('connectMethod_picture')), findsOneWidget);
      expect(find.byKey(const Key('connectMethod_pin')), findsOneWidget);
      expect(find.byKey(const Key('connectBest_code')), findsOneWidget);
      expect(find.text('Easiest'), findsOneWidget);
      expect(find.textContaining('No camera, and nothing to type on her tablet'), findsOneWidget);
      expect(find.textContaining('no camera to use here'), findsOneWidget, reason: 'the camera way says plainly why it cannot be chosen');
      // The default is the numbers way: it is the selected card (said to a screen reader too).
      final SemanticsHandle h = t.ensureSemantics();
      expect(t.getSemantics(find.bySemanticsLabel(RegExp(r"^Type her tablet's numbers"))).hasFlag(SemanticsFlag.isSelected), isTrue);
      expect(t.getSemantics(find.bySemanticsLabel(RegExp(r'^Use your PIN'))).hasFlag(SemanticsFlag.isSelected), isFalse);
      await t.tap(find.byKey(const Key('connectMethod_pin')));
      await t.pump();
      expect(t.getSemantics(find.bySemanticsLabel(RegExp(r'^Use your PIN'))).hasFlag(SemanticsFlag.isSelected), isTrue);
      expect(t.getSemantics(find.bySemanticsLabel(RegExp(r"^Type her tablet's numbers"))).hasFlag(SemanticsFlag.isSelected), isFalse);
      h.dispose();
    });
  });

  group('her_tablet.dart: the pure view', () {
    test('lastSeenWords is plain', () {
      const int d = 86400000;
      expect(lastSeenWords(1000, 1000), 'just now');
      expect(lastSeenWords(0, 20 * 60000), '20 minutes ago');
      expect(lastSeenWords(0, 3600000), 'an hour ago');
      expect(lastSeenWords(0, 5 * 3600000), '5 hours ago');
      expect(lastSeenWords(0, d + 1000), 'yesterday');
      expect(lastSeenWords(0, 4 * d), '4 days ago');
      expect(lastSeenWords(null, 5), 'not seen yet');
      expect(lastSeenWords(5000, 1000), 'just now', reason: 'a clock that went back is never "in the future"');
    });

    test('readHerTablet: connected, none, and never a guess from an unreadable list', () async {
      final MemoryPairedKidsRepository k = MemoryPairedKidsRepository();
      expect((await readHerTablet(kids: k)).status, HerTabletStatus.notConnected);
      await k.add(_kid('a'));
      expect((await readHerTablet(kids: k)).status, HerTabletStatus.connected);
      expect((await readHerTablet(kids: _Unreadable())).status, HerTabletStatus.unknown);
    });
  });
}

/// A list whose write fails (a full disk): "disconnect" must say so and change nothing.
class _FailingForget extends MemoryPairedKidsRepository {
  bool fail = false;
  @override
  Future<void> forget(String certId) async {
    if (fail) throw StateError('disk full');
    await super.forget(certId);
  }
}
