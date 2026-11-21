// OLIVE BRANCH — the pairing-picture screens, both directions, headless: the adult's "Show my picture" / "Scan the
// child's picture" / Match / "Make a new code", the child's nameless windows, its own picture card, the neutral
// failure, and the layout in every posture. UNVERIFIED on a device (no camera, no mDNS, no sockets here); the
// crypto is real. Design: docs/planning/PERSISTENT-QR-PAIRING.md section 5.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/child_connect_screen.dart';
import 'package:olive_client/connect_child_screen.dart';
import 'package:olive_client/device_keys.dart';
import 'package:olive_client/lan_pairing_transport.dart';
import 'package:olive_client/local_pin.dart';
import 'package:olive_client/pairing_limits.dart';
import 'package:olive_client/pairing_match.dart';
import 'package:olive_client/pairing_picture.dart';
import 'package:olive_client/pairing_picture_widgets.dart';
import 'package:olive_client/pairing_protocol.dart';
import 'package:olive_client/pairing_records.dart';
import 'package:olive_client/pairing_trust.dart';

Future<LocalPinRecord> _cheap(String pin) async => LocalPinRecord(iterations: 1, salt: Uint8List(16), hash: Uint8List(32));
Uint8List _b(int n, int f) => Uint8List.fromList(List<int>.filled(n, f));

class _FakeHost implements WindowHost {
  @override
  int? get port => 4242;
  @override
  Future<void> stop() async {}
  int readvertised = 0;
  @override
  Future<void> readvertise() async => readvertised++;
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
    await t.pump(const Duration(milliseconds: 60));
  }
}

class _Adult {
  _Adult(this.pin, this.pics, this.trust, this.lock, this.host);
  final LocalPinService pin;
  final MemoryPairingPictureRepository pics;
  final TrustBook trust;
  final AddingLock lock;
  final _FakeHost host;
  AdultWindow? opened;
  void Function(String raw)? scan;
  final MemoryPairedKidsRepository kids = MemoryPairedKidsRepository();
}

Future<_Adult> _pumpAdult(WidgetTester t) async {
  final LocalPinService pin = LocalPinService(MemoryLocalPinRepository(), iterations: 1);
  await t.runAsync(() => pin.setPin('4829'));
  final _Adult a = _Adult(pin, MemoryPairingPictureRepository(), TrustBook(MemoryTrustRepository()), AddingLock(), _FakeHost());
  await t.pumpWidget(MaterialApp(
      home: ConnectChildScreen(
        initialMethod: ConnectMethod.pin,
    pin: pin,
    deviceKeys: MemoryDeviceKeyRepository(),
    kids: a.kids,
    adultName: 'Mom',
    childName: 'Ivy',
    makeUnlockVerifier: _cheap,
    localAddress: () async => '192.168.1.5',
    pictures: a.pics,
    trust: a.trust,
    lock: a.lock,
    cooldown: FailureCooldown(),
    scannerBuilder: (BuildContext c, void Function(String) onRaw) {
      a.scan = onRaw;
      return const SizedBox(key: Key('fakeScanner'));
    },
    startHost: (AdultWindow w) async {
      a.opened = w;
      return a.host;
    },
  )));
  await t.enterText(find.byKey(const Key('connectPinField')), '4829');
  await _act(t, () => t.tap(find.byKey(const Key('connectOpen'))));
  return a;
}

PairingPicture? _shownPayload(WidgetTester t, Key tileKey) {
  final Finder f = find.descendant(of: find.byKey(tileKey), matching: find.byType(PictureTile));
  if (f.evaluate().isEmpty) return null;
  return parsePairingPicture(t.widget<PictureTile>(f).data);
}

Future<PairingPicture> _childPicture(WidgetTester t, {Uint8List? familyKey, int salt = 5}) async {
  return (await t.runAsync(() async {
    final DeviceKey k = await DeviceKey.loadOrCreate(MemoryDeviceKeyRepository());
    final Uint8List s = _b(16, salt);
    return PairingPicture(
        role: PictureRole.child, publicKey: k.publicKey, salt: s, epoch: 0,
        familyTag: familyKey == null ? null : await familyTag(familyKey, PictureRole.child, s, k.publicKey));
  }))!;
}

void main() {
  group('adult: Show my picture', () {
    testWidgets('shows a public picture: role adult, key, salt, epoch and a family tag, nothing else; Hide removes it', (t) async {
      final _Adult a = await _pumpAdult(t);
      expect(find.byKey(const Key('connectWaiting')), findsOneWidget);
      await _act(t, () => t.tap(find.byKey(const Key('connectShowPicture'))));
      final PairingPicture p = _shownPayload(t, const Key('connectPictureQr'))!;
      expect(p.role, PictureRole.adult);
      expect(p.familyTag, isNotNull, reason: 'a blinded family tag lets another family refuse it at scan time');
      final String payload = t.widget<PictureTile>(find.byType(PictureTile)).data;
      expect(payload, startsWith('olive://id/1?'));
      for (final String forbidden in <String>['pin', 'sid', 'q=', 'Mom', 'Ivy', 'a=']) {
        expect(payload, isNot(contains(forbidden)), reason: forbidden);
      }
      expect(a.opened!.hasPicture, isTrue);
      expect(a.host.readvertised, 1);
      // The tile is white with a quiet zone, whatever the theme.
      final BoxDecoration d = t.widget<Container>(find.descendant(of: find.byType(PictureTile), matching: find.byType(Container)).first).decoration as BoxDecoration;
      expect(d.color, Colors.white);
      await _act(t, () => t.tap(find.byKey(const Key('connectShowPicture'))));
      expect(find.byType(PictureTile), findsNothing);
    });

    testWidgets('Make a new code: the picture changes (next epoch, new salt), old copies stop matching, history says so', (t) async {
      final _Adult a = await _pumpAdult(t);
      await _act(t, () => t.tap(find.byKey(const Key('connectShowPicture'))));
      final PairingPicture before = _shownPayload(t, const Key('connectPictureQr'))!;
      await _act(t, () => t.tap(find.byKey(const Key('connectNewCode'))));
      final PairingPicture after = _shownPayload(t, const Key('connectPictureQr'))!;
      expect(after.epoch, before.epoch + 1);
      expect(after.salt, isNot(before.salt));
      expect(after.publicKey, before.publicKey, reason: 'the device key is never rotated by this');
      final Uint8List tag = (await t.runAsync(() => a.opened!.windowTag()))!;
      expect(await t.runAsync(() => tagMatches(before.salt, a.opened!.discoveryHandle, tag)), isFalse, reason: 'the old photo finds nothing');
      expect(await t.runAsync(() => tagMatches(after.salt, a.opened!.discoveryHandle, tag)), isTrue);
      expect((await t.runAsync(() => a.trust.repo.load()))!.history.map((HistoryEntry e) => e.kind), contains(HistoryKind.newCode));
    });
  });

  group("adult: Scan the child's picture", () {
    testWidgets("a child picture of ANOTHER family is refused with neutral wording and the window stays wide closed to it", (t) async {
      final _Adult a = await _pumpAdult(t);
      await t.tap(find.byKey(const Key('connectScanChild')));
      await t.pump();
      expect(find.byKey(const Key('fakeScanner')), findsOneWidget);
      final PairingPicture foreign = await _childPicture(t, familyKey: _b(16, 77));
      await _act(t, () async => a.scan!(foreign.payload));
      expect(find.text('This code belongs to a different family. Nothing was shared.'), findsOneWidget);
      expect(a.opened!.allowedChildKey, isNull);
      expect((await t.runAsync(() => a.trust.repo.load()))!.history.map((HistoryEntry e) => e.kind), contains(HistoryKind.refusedOtherFamily));
    });

    testWidgets('a child picture of the SAME family narrows the window to that device', (t) async {
      final _Adult a = await _pumpAdult(t);
      final Uint8List fk = (await t.runAsync(() => a.pics.load()))!.familyKey!;
      await t.tap(find.byKey(const Key('connectScanChild')));
      await t.pump();
      final PairingPicture mine = await _childPicture(t, familyKey: fk);
      await _act(t, () async => a.scan!(mine.payload));
      expect(a.opened!.allowedChildKey, mine.publicKey);
      expect(find.byKey(const Key('connectScannedNote')), findsOneWidget);
    });

    testWidgets("a child picture with no family tag (an unclaimed tablet) is accepted; an adult's picture and rubbish are not", (t) async {
      final _Adult a = await _pumpAdult(t);
      await t.tap(find.byKey(const Key('connectScanChild')));
      await t.pump();
      await _act(t, () async => a.scan!('olive://id/1?r=a&k=${b64(_b(32, 1))}&s=${b64(_b(16, 2))}&e=0'));
      expect(a.opened!.allowedChildKey, isNull);
      expect(find.textContaining('grown-up'), findsWidgets);
      await _act(t, () async => a.scan!('https://example.com/?x=1'));
      await _act(t, () async => a.scan!('olive://pair/1?s=AAAA'));
      expect(a.opened!.allowedChildKey, isNull);
      final PairingPicture bare = await _childPicture(t);
      await _act(t, () async => a.scan!(bare.payload));
      expect(a.opened!.allowedChildKey, bare.publicKey);
    });
  });

  group('adult: Match and Approve', () {
    Future<(Future<PairingResult>, DeviceKey)> startChild(WidgetTester t, _Adult a) async {
      final DeviceKey ck = await t.runAsync(() => DeviceKey.loadOrCreate(MemoryDeviceKeyRepository())) as DeviceKey;
      final Future<PairingResult> run = ChildPairingClient(
              childKey: ck, transport: LoopbackPairingTransport(a.opened!), deviceName: 'Tab\u202e', pollEvery: const Duration(milliseconds: 20))
          .pair(sid: a.opened!.sid, password: '4829');
      await _settle(t);
      return (run, ck);
    }

    testWidgets('a wrong pick refuses: nothing issued, adding locked for 10 minutes, history says so, the next open is refused', (t) async {
      final _Adult a = await _pumpAdult(t);
      final (Future<PairingResult> run, _) = await startChild(t, a);
      expect(find.byKey(const Key('connectMatchStep')), findsOneWidget);
      // Four candidate cards and "None of these", each a large tap target.
      for (int i = 0; i < 4; i++) {
        expect(find.byKey(Key('connectMatch_$i')), findsOneWidget);
      }
      expect(t.getSize(find.byKey(const Key('connectMatchNone'))).height, greaterThanOrEqualTo(56));
      final int wrong = (a.opened!.matchChoices!.correct + 1) % 4;
      await _act(t, () => t.tap(find.byKey(Key('connectMatch_$wrong'))));
      await _settle(t);
      final PairingResult r = await run;
      expect(r.ok, isFalse);
      expect(await a.kids.load(), isEmpty);
      expect(a.lock.blockedFor(), isNotNull);
      expect(find.text('Nothing was shared. Adding is off for 10 minutes.'), findsOneWidget);
      expect((await t.runAsync(() => a.trust.repo.load()))!.history.map((HistoryEntry e) => e.kind), contains(HistoryKind.refusedMatch));
      await t.enterText(find.byKey(const Key('connectPinField')), '4829');
      await _act(t, () => t.tap(find.byKey(const Key('connectOpen'))));
      expect(find.byKey(const Key('connectWaiting')), findsNothing, reason: 'the lock holds');
      expect(find.textContaining('Adding is off'), findsOneWidget);
    });

    testWidgets('"None of these" also refuses', (t) async {
      final _Adult a = await _pumpAdult(t);
      final (Future<PairingResult> run, _) = await startChild(t, a);
      await _act(t, () => t.tap(find.byKey(const Key('connectMatchNone'))));
      await _settle(t);
      expect((await run).ok, isFalse);
      expect(a.lock.blockedFor(), isNotNull);
    });

    testWidgets('the right pick, the grown-up chooses the role, Yes: the device is added, New, with a sanitized name', (t) async {
      final _Adult a = await _pumpAdult(t);
      final (Future<PairingResult> run, DeviceKey ck) = await startChild(t, a);
      await _act(t, () => t.tap(find.byKey(Key('connectMatch_${a.opened!.matchChoices!.correct}'))));
      expect(find.text('Only you choose this. The device cannot choose for itself.'), findsOneWidget);
      expect(await a.kids.load(), isEmpty, reason: 'a right pick is not an approval: nothing is added until "Yes, connect it"');
      await _act(t, () => t.tap(find.byKey(const Key('connectApprove'))));
      await _settle(t);
      final PairingResult r = await run;
      await _settle(t);
      expect(r.ok, isTrue);
      expect(r.pairing!.familyKey, isNotNull, reason: 'the family key arrives sealed inside the credential');
      final List<TrustedDevice> d = (await t.runAsync(() => a.trust.devices()))!;
      expect(d.single.role, PairedRole.child);
      expect(d.single.name, 'Tab', reason: 'the bidi override is stripped');
      expect(d.single.deviceKey, ck.publicKey);
      expect(d.single.isNew(DateTime.now().millisecondsSinceEpoch), isTrue);
      expect(find.byKey(const Key('connectDone')), findsOneWidget);
      expect(find.text('Added. It is new for 24 hours.'), findsOneWidget);
    });

    testWidgets('"Not mine" refuses and locks', (t) async {
      final _Adult a = await _pumpAdult(t);
      final (Future<PairingResult> run, _) = await startChild(t, a);
      await _act(t, () => t.tap(find.byKey(Key('connectMatch_${a.opened!.matchChoices!.correct}'))));
      await _act(t, () => t.tap(find.byKey(const Key('connectDecline'))));
      await _settle(t);
      expect((await run).ok, isFalse);
      expect(a.lock.blockedFor(), isNotNull);
      expect(await a.kids.load(), isEmpty);
    });
  });

  group('child: nameless windows, picture cards, one neutral failure', () {
    Future<_ChildRig> pumpChild(WidgetTester t, {String? claimed, Duration helloFor = const Duration(minutes: 10), Uint8List? fk}) async {
      final MemoryPairingPictureRepository pics = MemoryPairingPictureRepository();
      if (fk != null) await t.runAsync(() => pics.save(PairingPictureState(_b(16, 3), 0, familyKey: fk)));
      final _FakeFinder finder = _FakeFinder();
      final _ChildRig rig = _ChildRig(pics, finder, MemoryDeviceKeyRepository());
      await t.pumpWidget(MaterialApp(
          home: ChildConnectScreen(
        deviceKeys: rig.keys,
        pictures: pics,
        claimedFamilyId: claimed,
        helloFor: helloFor,
        finderFactory: () => finder,
        scannerBuilder: (BuildContext c, void Function(String) onRaw) {
          rig.scan = onRaw;
          return const SizedBox(key: Key('fakeScanner'));
        },
        onPaired: (_) async {},
      )));
      await t.tap(find.byKey(const Key('adultGateGrownUp')));
      await _settle(t);
      return rig;
    }

    Future<AdultWindow> window(WidgetTester t, {String fid = 'fam'}) async {
      return (await t.runAsync(() async {
        final DeviceKey ak = await DeviceKey.loadOrCreate(MemoryDeviceKeyRepository());
        return AdultWindow.open(requireMatch: false, adultKey: ak, adultName: 'Mom', familyId: fid, childId: 'k', childName: 'Ivy', pin: '4829', makeUnlockVerifier: _cheap);
      }))!;
    }

    testWidgets('open windows are nameless picture tiles; no name, no digits, no error words', (t) async {
      final _ChildRig rig = await pumpChild(t);
      final AdultWindow w1 = await window(t), w2 = await window(t);
      rig.finder.emit(NearbyWindow(handle: w1.discoveryHandle, host: 'x', port: 1));
      rig.finder.emit(NearbyWindow(handle: w2.discoveryHandle, host: 'y', port: 1));
      await _settle(t);
      expect(find.byType(GlyphTile), findsNWidgets(2));
      expect(find.textContaining('Mom'), findsNothing);
      expect(find.textContaining('Ivy'), findsNothing);
    });

    testWidgets("a claimed child refuses another family's picture: one neutral picture, no words, nothing sent", (t) async {
      final Uint8List mine = _b(16, 9);
      final _ChildRig rig = await pumpChild(t, claimed: 'fam', fk: mine);
      await t.tap(find.byKey(const Key('childConnectScan')));
      await t.pump();
      final DeviceKey ak = await t.runAsync(() => DeviceKey.loadOrCreate(MemoryDeviceKeyRepository())) as DeviceKey;
      final Uint8List salt = _b(16, 4);
      final PairingPicture foreign = PairingPicture(
          role: PictureRole.adult, publicKey: ak.publicKey, salt: salt, epoch: 0,
          familyTag: await t.runAsync(() => familyTag(_b(16, 200), PictureRole.adult, salt, ak.publicKey)));
      await _act(t, () async => rig.scan!(foreign.payload));
      await _settle(t);
      expect(find.byKey(const Key('childConnectTryAgain')), findsOneWidget);
      // The shared calm card (CalmTryAgainCard) is all the child reads: its one gentle line and OK. No reason, no
      // family or picture word, no number.
      expect(t.widgetList<Text>(find.byType(Text)).map((Text x) => x.data).toList(), <String?>['Your grown-up can try again', 'OK']);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets("the grown-up's picture picks ONE window by its tag; a look-alike window with another tag is ignored; then the keypad", (t) async {
      final _ChildRig rig = await pumpChild(t);
      await t.tap(find.byKey(const Key('childConnectScan')));
      await t.pump();
      final DeviceKey ak = await t.runAsync(() => DeviceKey.loadOrCreate(MemoryDeviceKeyRepository())) as DeviceKey;
      final PairingPicture pic = PairingPicture(role: PictureRole.adult, publicKey: ak.publicKey, salt: _b(16, 6), epoch: 0);
      await _act(t, () async => rig.scan!(pic.payload));
      final AdultWindow other = await window(t), real = await window(t);
      final Uint8List wrongTag = (await t.runAsync(() => rendezvousTag(_b(16, 99), other.sid)))!;
      final Uint8List rightTag = (await t.runAsync(() => rendezvousTag(pic.salt, real.discoveryHandle)))!;
      rig.finder.emit(NearbyWindow(handle: other.discoveryHandle, host: 'x', port: 1, tag: wrongTag));
      await _settle(t);
      expect(find.byKey(const Key('pinGateConfirm')), findsNothing, reason: 'a window the picture does not recognise is never chosen');
      rig.finder.emit(NearbyWindow(handle: real.discoveryHandle, host: 'y', port: 1, tag: rightTag));
      await _settle(t);
      expect(find.byKey(const Key('pinGateConfirm')), findsOneWidget);
    });

    testWidgets("a child's picture or rubbish on the camera is ignored without a word", (t) async {
      final _ChildRig rig = await pumpChild(t);
      await t.tap(find.byKey(const Key('childConnectScan')));
      await t.pump();
      final PairingPicture childPic = await _childPicture(t);
      await _act(t, () async => rig.scan!(childPic.payload));
      await _act(t, () async => rig.scan!('not a picture'));
      expect(find.byKey(const Key('fakeScanner')), findsOneWidget);
      expect(find.byKey(const Key('childConnectTryAgain')), findsNothing);
    });

    testWidgets("this device's own picture: a card with the QR and no words, for 10 minutes at most; a window addressed to it opens the keypad", (t) async {
      final _ChildRig rig = await pumpChild(t, helloFor: const Duration(seconds: 30));
      await _act(t, () => t.tap(find.byKey(const Key('childConnectShowPicture'))));
      final PairingPicture p = _shownPayload(t, const Key('childHelloCard'))!;
      expect(p.role, PictureRole.child);
      expect(find.byType(Text), findsNothing, reason: 'the card has no words');
      final AdultWindow w = await window(t);
      final Uint8List tag = (await t.runAsync(() => rendezvousTag(p.salt, w.discoveryHandle)))!;
      rig.finder.emit(NearbyWindow(handle: w.discoveryHandle, host: 'x', port: 1, tag: tag));
      await _settle(t);
      expect(find.byKey(const Key('pinGateConfirm')), findsOneWidget);
    });

    testWidgets('the picture card goes away on its own', (t) async {
      await pumpChild(t, helloFor: const Duration(milliseconds: 900));
      await _act(t, () => t.tap(find.byKey(const Key('childConnectShowPicture'))));
      expect(find.byKey(const Key('childHelloCard')), findsOneWidget);
      await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 900)));
      await t.pump();
      expect(find.byKey(const Key('childHelloCard')), findsNothing);
      expect(find.byKey(const Key('adultGateCard')), findsOneWidget);
    });
  });

  group('Match pictures', () {
    testWidgets("the child's set carries no text and no semantic label; the adult's has a label and a shape for the colour", (t) async {
      const MatchSet s = MatchSet(<int>[1, 2, 3], 4);
      await t.pumpWidget(const MaterialApp(home: Scaffold(body: Column(children: <Widget>[
        MatchCard(key: Key('c'), set: s, iconSize: 96, forChild: true),
        MatchCard(key: Key('a'), set: s, iconSize: 40),
      ]))));
      expect(find.byType(Text), findsNothing);
      final SemanticsHandle h = t.ensureSemantics();
      expect(t.getSemantics(find.byKey(const Key('c'))).label, isEmpty);
      expect(t.getSemantics(find.byKey(const Key('a'))).label, contains('teal ring'));
      h.dispose();
      expect(t.getSize(find.byKey(const Key('c'))).width, greaterThan(96 * 3), reason: 'each picture is at least 96 dp');
    });

    test('64 pictures map to 64 different icons and 8 colours to 8 shapes', () {
      expect(<int>{for (int i = 0; i < 64; i++) matchIcon(i).codePoint}, hasLength(64));
      expect(<int>{for (int i = 0; i < 8; i++) matchShapeIcon(i).codePoint}, hasLength(8));
      expect(kMatchColourValues.toSet(), hasLength(8));
    });
  });

  group('layout per posture', () {
    Future<void> pumpLayout(WidgetTester t, Size size) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      await t.pumpWidget(MaterialApp(
          home: Scaffold(
              body: PictureLayout(
        picture: (double side) => SizedBox(key: const Key('pic'), width: side, height: side),
        steps: Column(children: List<Widget>.generate(6, (int i) => const SizedBox(height: 56, child: Text('step')))),
      ))));
    }

    testWidgets('phone and Tab portrait: one column, picture about 70 percent of the width', (t) async {
      await pumpLayout(t, const Size(360, 800));
      expect(find.byKey(const Key('pictureLayoutNarrow')), findsOneWidget);
      expect(t.getSize(find.byKey(const Key('pic'))).width, closeTo(360 * 0.7 - 24 * 0, 60));
      expect(t.takeException(), isNull);
    });

    testWidgets('Fold cover: narrow, no overflow', (t) async {
      await pumpLayout(t, const Size(280, 653));
      expect(find.byKey(const Key('pictureLayoutNarrow')), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('Fold inner and tablet landscape: two panes, picture left', (t) async {
      for (final Size s in const <Size>[Size(884, 760), Size(1000, 600), Size(700, 840)]) {
        await pumpLayout(t, s);
        expect(find.byKey(const Key('pictureLayoutWide')), findsOneWidget, reason: '$s');
        expect(t.getRect(find.byKey(const Key('pic'))).right, lessThan(s.width * 0.6), reason: '$s');
        expect(t.takeException(), isNull, reason: '$s');
      }
    });

    testWidgets('Fold tabletop: the picture sits wholly in the lower half, clear of the hinge', (t) async {
      await pumpLayout(t, const Size(700, 400));
      expect(find.byKey(const Key('pictureLayoutTabletop')), findsOneWidget);
      expect(t.getRect(find.byKey(const Key('pic'))).top, greaterThanOrEqualTo(400 / 2));
      expect(t.takeException(), isNull);
    });
  });
}

class _ChildRig {
  _ChildRig(this.pics, this.finder, this.keys);
  final MemoryPairingPictureRepository pics;
  final _FakeFinder finder;
  final MemoryDeviceKeyRepository keys;
  void Function(String raw)? scan;
}
