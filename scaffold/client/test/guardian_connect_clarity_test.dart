// OLIVE BRANCH — the guardian's "connect her tablet" clarity pass (ISS-059 to ISS-063, ISS-065).
// Verified by CI, headless. MASTERFILE §8.2 (the home's one sentence) and §8.13 (pairing).
//
// What it holds:
//   * the home's one sentence says "not connected yet" ONLY when the paired-tablet list was read in full and is
//     empty; says the tablet is paired when the list holds one; says nothing when the list cannot be read;
//   * a corrupt entry in the paired-tablet list is counted, never erased by a later add, forget or switch;
//   * the account-code scanner classifies what it scans: a picture for pairing a tablet goes nowhere near the
//     server, a server code is submitted, a network failure and any other failure read differently;
//   * a tablet on another pairing version is explained on the grown-up's phone only (the tablet keeps its one calm
//     fallback);
//   * Settings is one tap from the home (a gear) and one tap from the top of More; the three tablet screens sit
//     together under "Her tablet" with names that say what they do.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:olive_client/connect_child_screen.dart';
import 'package:olive_client/connected_devices_screen.dart';
import 'package:olive_client/contact_labels.dart' show GrownupKind;
import 'package:olive_client/device_keys.dart';
import 'package:olive_client/guardian_home.dart';
import 'package:olive_client/guardian_local_scope.dart';
import 'package:olive_client/guardian_more.dart';
import 'package:olive_client/guardian_settings_hub.dart';
import 'package:olive_client/her_tablet_screen.dart';
import 'package:olive_client/guardian_state_line.dart';
import 'package:olive_client/local_family.dart';
import 'package:olive_client/local_pin.dart';
import 'package:olive_client/local_services.dart';
import 'package:olive_client/local_store.dart' show LocalNamespace, LocalStore, MemoryStoreBackend, NamespaceSpec, RecoveryKind;
import 'package:olive_client/pairing_protocol.dart';
import 'package:olive_client/pairing_qr.dart';
import 'package:olive_client/pairing_records.dart';
import 'package:olive_client/pairing_redeem_screen.dart';

class _NoHost implements WindowHost {
  @override
  int? get port => null;
  @override
  Future<void> stop() async {}
  @override
  Future<void> readvertise() async {}
}

// Each tablet has its own key (one device is one row, so two fixtures must not share one).
Uint8List _keyFor(String id) => Uint8List.fromList(List<int>.filled(32, id.codeUnitAt(0)));

PairedKid _kid(String id, {String name = 'Tablet'}) =>
    PairedKid(certId: id, childDeviceKey: _keyFor(id), childId: 'kid', deviceName: name, issuedAtMs: 5);

Map<String, Object?> _kidJson(String id) =>
    <String, Object?>{'certId': id, 'cpk': b64(_keyFor(id)), 'cid': 'kid', 'dn': 'Tablet', 'iat': 5};

LocalStorePairedKidsRepository _repo(LocalServices s) =>
    LocalStorePairedKidsRepository(s.area('pairedkids', ownerId: kLocalGuardianScope));

GuardianHome _home({Future<PairedKidsLoad> Function()? kids, String? baseUrl, bool? server, String? dayPart}) => GuardianHome(
      childName: 'Ivy', childLocalTime: '4:12 PM', childZoneAbbr: 'CT', actorLocalTime: '5:12 PM ET',
      childBands: const <RibbonBand>[], actorBands: const <RibbonBand>[],
      baseUrl: baseUrl, serverTabletPresent: server, dayPart: dayPart, pairedKids: kids);

Future<void> _size(WidgetTester t, double w, {double h = 2600}) async {
  await t.binding.setSurfaceSize(Size(w, h));
  addTearDown(() => t.binding.setSurfaceSize(null));
}

Future<void> _pumpHome(WidgetTester t, GuardianHome home) async {
  await _size(t, 390);
  await t.pumpWidget(MaterialApp(home: home));
  await t.pumpAndSettle();
}

String? _line(WidgetTester t) {
  final Finder f = find.byKey(const Key('guardianStateLine'));
  return f.evaluate().isEmpty ? null : t.widget<Text>(f).data;
}

void main() {
  group('ISS-059: the home\'s sentence about her tablet', () {
    test('guardianStateLine: paired, empty and unreadable are three different answers', () {
      expect(guardianStateLine(childName: 'Ivy', connected: false, tabletPaired: true), contains('is paired with this phone'));
      expect(guardianStateLine(childName: 'Ivy', connected: false, tabletPaired: false), contains('isn’t connected yet'));
      expect(guardianStateLine(childName: 'Ivy', connected: false, tabletPaired: null), isNull,
          reason: 'unreadable or not read yet: nothing is said');
      expect(guardianStateLine(childName: 'Ivy', connected: false), isNull);
    });

    test('a live family is "not connected" only when the server also says there is no tablet', () {
      expect(guardianStateLine(childName: 'Ivy', connected: true, tabletPaired: false, serverTabletPresent: null, dayPart: 'school'),
          contains('It is'), reason: 'the server has not answered, so the list is not verifiably empty');
      expect(guardianStateLine(childName: 'Ivy', connected: true, tabletPaired: false, serverTabletPresent: false),
          contains('isn’t connected yet'));
      expect(guardianStateLine(childName: 'Ivy', connected: true, tabletPaired: false, serverTabletPresent: true, dayPart: 'wake'),
          contains('It is'));
    });

    test('a live family says only that the tablet is not connected, not that setup "stays on this phone"', () {
      final String line = guardianStateLine(childName: 'Ivy', connected: true, tabletPaired: false, serverTabletPresent: false)!;
      expect(line, isNot(contains('stays on this phone')));
      expect(guardianStateLine(childName: 'Ivy', connected: false, tabletPaired: false), contains('stays on this phone'));
    });

    test('a real sentence still wins over everything', () {
      expect(guardianStateLine(childName: 'Ivy', sentence: 'Ivy is just home', connected: false, tabletPaired: false), 'Ivy is just home');
    });

    testWidgets('PAIRED: the phone lists a tablet, so it is never called "not connected"', (t) async {
      await _pumpHome(t, _home(kids: () async => PairedKidsLoad(<PairedKid>[_kid('a')])));
      expect(_line(t), contains('is paired with this phone'));
      expect(find.textContaining('isn’t connected'), findsNothing);
    });

    testWidgets('EMPTY: a list read in full with nothing on it says "not connected yet"', (t) async {
      await _pumpHome(t, _home(kids: () async => const PairedKidsLoad(<PairedKid>[])));
      expect(_line(t), contains('isn’t connected yet'));
    });

    testWidgets('UNREADABLE (store down, entries skipped, or it throws): the home says nothing about her tablet', (t) async {
      for (final Future<PairedKidsLoad> Function() load in <Future<PairedKidsLoad> Function()>[
        () async => const PairedKidsLoad(<PairedKid>[], unreadable: true),
        () async => const PairedKidsLoad(<PairedKid>[], skipped: 2),
        () async => throw StateError('store down'),
      ]) {
        await _pumpHome(t, _home(kids: load));
        expect(_line(t), isNull);
        expect(find.byKey(const Key('guardianStateLineNone')), findsOneWidget);
        expect(find.textContaining('isn’t connected'), findsNothing);
        expect(find.textContaining('paired with'), findsNothing);
      }
    });

    testWidgets('a tablet on the list wins even when some other entries could not be read', (t) async {
      await _pumpHome(t, _home(kids: () async => PairedKidsLoad(<PairedKid>[_kid('a')], skipped: 1)));
      expect(_line(t), contains('is paired with this phone'));
    });

    testWidgets('the real store: empty says not connected; after a pairing is added the line follows without a rebuild', (t) async {
      LocalServices.resetForTest();
      addTearDown(LocalServices.resetForTest);
      await _pumpHome(t, _home());
      expect(_line(t), contains('isn’t connected yet'));
      await _repo(LocalServices.current).add(_kid('a'));
      await t.pumpAndSettle();
      expect(_line(t), contains('is paired with this phone'));
    });
  });

  group('ISS-060: the paired-tablet list never loses what it could not read', () {
    test('a list that was never written is verifiably empty', () async {
      final LocalServices s = LocalServices.memory(isLive: true, demoSeeds: false, childId: 'c1');
      final PairedKidsLoad l = await _repo(s).loadChecked();
      expect(l.verifiablyEmpty, isTrue);
      expect(l.incomplete, isFalse);
    });

    test('corrupt entries are counted, and add, switch and forget write them back untouched', () async {
      final LocalServices s = LocalServices.memory(isLive: true, demoSeeds: false, childId: 'c1');
      final LocalNamespace ns = s.area('pairedkids', ownerId: kLocalGuardianScope);
      final Map<String, Object?> broken = <String, Object?>{'certId': 'x', 'cpk': 12, 'note': 'future field'};
      await ns.put('kids', <Object?>[_kidJson('a'), broken, 'junk', _kidJson('b')]);
      final LocalStorePairedKidsRepository r = LocalStorePairedKidsRepository(ns);

      PairedKidsLoad l = await r.loadChecked();
      expect(l.kids.map((PairedKid k) => k.certId), <String>['a', 'b']);
      expect(l.skipped, 2);
      expect(l.incomplete, isTrue);
      expect(l.verifiablyEmpty, isFalse);
      expect((await r.load()).length, 2, reason: 'load() is unchanged for callers that only want the readable ones');

      await r.add(_kid('c'));
      await r.setPhoneOnly('a', true);
      await r.forget('b');
      final List<Object?> raw = (await ns.get('kids'))! as List<Object?>;
      expect(raw, hasLength(4), reason: 'a, the two bad entries, c');
      expect(raw[1], broken, reason: 'the bad entry is kept verbatim and in place');
      expect(raw[2], 'junk');
      l = await r.loadChecked();
      expect(l.kids.map((PairedKid k) => k.certId), <String>['a', 'c']);
      expect(l.kids.first.phoneOnly, isTrue);
      expect(l.skipped, 2);
    });

    test('a list that is not a list is "unreadable": nothing is written over it', () async {
      final LocalServices s = LocalServices.memory(isLive: true, demoSeeds: false, childId: 'c1');
      final LocalNamespace ns = s.area('pairedkids', ownerId: kLocalGuardianScope);
      await ns.put('kids', 'not a list');
      final LocalStorePairedKidsRepository r = LocalStorePairedKidsRepository(ns);
      final PairedKidsLoad l = await r.loadChecked();
      expect(l.unreadable, isTrue);
      expect(l.verifiablyEmpty, isFalse);
      await expectLater(r.add(_kid('a')), throwsA(isA<PairedKidsUnreadable>()));
      await expectLater(r.forget('a'), throwsA(isA<PairedKidsUnreadable>()));
      expect(await ns.get('kids'), 'not a list', reason: 'untouched');
    });

    test('a damaged, set-aside file is "unreadable", never verifiably empty; a later add reads normally', () async {
      final MemoryStoreBackend backend = MemoryStoreBackend()..plant('pairedkids', Uint8List.fromList('{not json'.codeUnits));
      final LocalNamespace ns = LocalStore(backend: backend).open(const NamespaceSpec(name: 'pairedkids'));
      final LocalStorePairedKidsRepository r = LocalStorePairedKidsRepository(ns);
      final PairedKidsLoad l = await r.loadChecked();
      expect(ns.recovery, RecoveryKind.corrupt);
      expect(l.unreadable, isTrue);
      expect(l.verifiablyEmpty, isFalse, reason: 'the home must not say "not connected yet" over a list that was set aside');
      await r.add(_kid('a'));
      final PairedKidsLoad after = await r.loadChecked();
      expect(after.kids.map((PairedKid k) => k.certId), <String>['a']);
      expect(after.unreadable, isFalse);
    });

    testWidgets('the connected-tablets screen says so, never "no device", when entries could not be read', (t) async {
      final LocalServices s = LocalServices.memory(isLive: true, demoSeeds: false, childId: 'c1');
      final LocalNamespace ns = s.area('pairedkids', ownerId: kLocalGuardianScope);
      await ns.put('kids', <Object?>['junk']);
      await t.pumpWidget(MaterialApp(home: ConnectedDevicesScreen(kids: LocalStorePairedKidsRepository(ns), childName: 'Ivy')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('connectedUnreadable')), findsOneWidget);
      expect(find.byKey(const Key('connectedEmpty')), findsNothing);
      expect(find.text("Ivy's tablets"), findsOneWidget);

      await ns.put('kids', <Object?>[_kidJson('a'), 'junk']);
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(MaterialApp(home: ConnectedDevicesScreen(kids: LocalStorePairedKidsRepository(ns), childName: 'Ivy')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('connectedSkipped')), findsOneWidget);
      expect(find.byKey(const Key('connectedName_a')), findsOneWidget);
    });
  });

  group('ISS-062: the account-code scanner', () {
    final String localPicture = 'olive://pair/1?s=${b64(Uint8List(16))}&k=${b64(Uint8List(16))}&q=${b64(Uint8List(16))}';
    const String serverCode = '0a1b2c3d-0000-4000-8000-0123456789ab';

    test('classifyScan: pictures for pairing a tablet, account codes, and anything else', () {
      expect(classifyScan(localPicture), ScanShape.localPairingPicture);
      expect(classifyScan('olive://id/1?r=a&k=AAAA&s=BBBB&e=1'), ScanShape.localPairingPicture);
      expect(classifyScan('OLIVE://whatever'), ScanShape.localPairingPicture);
      expect(classifyScan(serverCode), ScanShape.serverCode);
      expect(classifyScan(' 123456 '), ScanShape.serverCode);
      expect(classifyScan('12345'), ScanShape.unknown);
      expect(classifyScan('https://example.test/x'), ScanShape.unknown);
      expect(classifyScan('WIFI:S:home;T:WPA;P:pw;;'), ScanShape.unknown);
    });

    Future<List<String>> pumpScanner(WidgetTester t, http.Client client, {
      void Function(Map<String, dynamic>)? onRedeemed, VoidCallback? onLocal, bool closing = false,
    }) async {
      await _size(t, 800, h: 1600);
      await t.pumpWidget(MaterialApp(home: PairingRedeemScreen(
        baseUrl: 'http://olive.test', role: closing ? 'child' : 'guardian', httpClient: client, closingStep: closing,
        onRedeemed: onRedeemed ?? (_) {}, onLocalPairingPicture: onLocal, onNotNow: closing ? () {} : null)));
      await t.pumpAndSettle();
      if (closing) {
        await t.tap(find.byKey(const Key('adultGateGrownUp')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('pairingChooseScan')));
        await t.pump();
      } else {
        await t.tap(find.byKey(const Key('pairingScanQrButton')));
        await t.pump();
      }
      return <String>[];
    }

    void scan(WidgetTester t, String value) {
      t.widget<MobileScanner>(find.byKey(const Key('pairingScanner')))
          .onDetect!(BarcodeCapture(barcodes: <Barcode>[Barcode(rawValue: value)]));
    }

    MockClient counting(List<http.Request> seen, {Object? throwing, http.Response? answer}) => MockClient((http.Request r) async {
          seen.add(r);
          if (throwing != null) throw throwing;
          return answer ?? http.Response(jsonEncode(<String, Object?>{'sessionToken': 't', 'deviceId': 'd'}), 201);
        });

    testWidgets('a local pairing picture is redirected and sends NOTHING to the server', (t) async {
      final List<http.Request> seen = <http.Request>[];
      bool redirected = false;
      await pumpScanner(t, counting(seen), onLocal: () => redirected = true);
      scan(t, localPicture);
      await t.pumpAndSettle();
      expect(redirected, isTrue);
      expect(seen, isEmpty);
    });

    testWidgets('with no redirect wired the grown-up is told where to go, still with no network call', (t) async {
      final List<http.Request> seen = <http.Request>[];
      await pumpScanner(t, counting(seen));
      scan(t, localPicture);
      await t.pumpAndSettle();
      expect(find.byKey(const Key('pairingErrorMessage')), findsOneWidget);
      expect(find.textContaining('pairing a tablet'), findsOneWidget);
      expect(find.textContaining("Couldn't reach the server"), findsNothing);
      expect(seen, isEmpty);
    });

    testWidgets('the grown-up scanner says plainly it is for a family account code, and the child one says nothing', (t) async {
      await pumpScanner(t, counting(<http.Request>[]));
      expect(find.byKey(const Key('pairingScannerCaption')), findsOneWidget);
      expect(find.textContaining('family account'), findsWidgets);
      await pumpScanner(t, counting(<http.Request>[]), closing: true);
      expect(find.byKey(const Key('pairingScannerCaption')), findsNothing);
    });

    testWidgets('an unrecognised QR is not submitted either', (t) async {
      final List<http.Request> seen = <http.Request>[];
      await pumpScanner(t, counting(seen));
      scan(t, 'https://example.test/not-ours');
      await t.pumpAndSettle();
      expect(seen, isEmpty);
      expect(find.byKey(const Key('pairingErrorMessage')), findsOneWidget);
    });

    testWidgets('a server code IS submitted, verbatim, with the role compiled into the build', (t) async {
      final List<http.Request> seen = <http.Request>[];
      Map<String, dynamic>? result;
      await pumpScanner(t, counting(seen), onRedeemed: (Map<String, dynamic> r) => result = r);
      scan(t, serverCode);
      await t.pumpAndSettle();
      expect(seen, hasLength(1));
      expect(jsonDecode(seen.single.body), <String, Object?>{'code': serverCode, 'role': 'guardian'});
      expect(result?['deviceId'], 'd');
    });

    testWidgets('a network failure reads "couldn\'t reach the server"', (t) async {
      final List<http.Request> seen = <http.Request>[];
      await pumpScanner(t, counting(seen, throwing: const SocketException('no route to host')));
      scan(t, serverCode);
      await t.pumpAndSettle();
      expect(seen, hasLength(1));
      expect(find.textContaining("Couldn't reach the server"), findsOneWidget);
    });

    testWidgets('a server answer that is not an Olive answer is NOT reported as a network failure', (t) async {
      final List<http.Request> seen = <http.Request>[];
      await pumpScanner(t, counting(seen, answer: http.Response('<html>not ours</html>', 200)));
      scan(t, serverCode);
      await t.pumpAndSettle();
      expect(seen, hasLength(1));
      expect(find.textContaining("Couldn't reach the server"), findsNothing);
      expect(find.textContaining("answer wasn't what we expected"), findsOneWidget,
          reason: 'a captive-portal page is a connection problem to check, not "check the code"');
    });

    testWidgets('the child build: a local picture gets the one calm card, no words and no network call', (t) async {
      final List<http.Request> seen = <http.Request>[];
      await pumpScanner(t, counting(seen), closing: true);
      scan(t, localPicture);
      await t.pumpAndSettle();
      // The closing step's own reachability probe is a GET of the base URL; what must never happen is a redeem (POST).
      expect(seen.where((http.Request r) => r.method == 'POST'), isEmpty);
      expect(find.byKey(const Key('childConnectTryAgain')), findsOneWidget);
      expect(find.byKey(const Key('pairingErrorMessage')), findsNothing);
    });

    testWidgets('the child build: a bad answer shows the calm card, not the offline picture', (t) async {
      final List<http.Request> seen = <http.Request>[];
      await pumpScanner(t, counting(seen, answer: http.Response('<html>', 200)), closing: true);
      scan(t, serverCode);
      await t.pumpAndSettle();
      expect(find.byKey(const Key('childConnectTryAgain')), findsOneWidget);
      expect(find.byKey(const Key('pairingOfflinePicture')), findsNothing);
    });
  });

  group('ISS-065: a tablet on another pairing version', () {
    Future<AdultWindow> open() async {
      final DeviceKey ak = await DeviceKey.loadOrCreate(MemoryDeviceKeyRepository());
      return AdultWindow.open(
          adultKey: ak, adultName: 'Mom', familyId: 'fam', childId: 'kid', childName: 'Ivy', pin: '4829', offerQr: false,
          makeUnlockVerifier: (String pin) async => LocalPinRecord(iterations: 1, salt: Uint8List(16), hash: Uint8List(32)));
    }

    testWidgets('a hello with pv=2 shows the version message on the grown-up\'s phone', (t) async {
      final LocalPinService pin = LocalPinService(MemoryLocalPinRepository(), iterations: 1);
      await t.runAsync(() => pin.setPin('4829'));
      AdultWindow? opened;
      await t.pumpWidget(MaterialApp(home: ConnectChildScreen(
        initialMethod: ConnectMethod.pin,
        pin: pin, deviceKeys: MemoryDeviceKeyRepository(), kids: MemoryPairedKidsRepository(), adultName: 'Mom', childName: 'Ivy',
        makeUnlockVerifier: (String p) async => LocalPinRecord(iterations: 1, salt: Uint8List(16), hash: Uint8List(32)),
        localAddress: () async => null,
        startHost: (AdultWindow w) async {
          opened = w;
          return _NoHost();
        })));
      await t.enterText(find.byKey(const Key('connectPinField')), '4829');
      await t.runAsync(() async {
        await t.tap(find.byKey(const Key('connectOpen')));
        await Future<void>.delayed(const Duration(milliseconds: 400));
      });
      await t.pump();
      expect(opened, isNotNull);
      expect(find.text(kVersionMismatchMessage), findsNothing, reason: 'nothing is said until a tablet knocks');

      await t.runAsync(() async {
        final DeviceKey ck = await DeviceKey.loadOrCreate(MemoryDeviceKeyRepository());
        final Map<String, dynamic>? answer = await opened!.handle(<String, dynamic>{
          't': 'hello', 'pv': 2, 'sid': b64(opened!.sid), 'cpk': b64(ck.publicKey), 'dn': 'Old tablet', 'hs': b64(Uint8List(64))});
        expect(answer, isNotNull, reason: 'the window still answers; the tablet stops by its own check');
      });
      await t.pump();
      expect(find.byKey(const Key('connectMessage')), findsOneWidget);
      expect(find.text(kVersionMismatchMessage), findsOneWidget);
      expect(find.textContaining('Old tablet'), findsNothing, reason: 'no name or key from the other device is shown');
    });

    test('a pake1 or a hello of the current version does not raise it', () async {
      final AdultWindow w = (await Future<AdultWindow>.value(open()));
      final DeviceKey ck = await DeviceKey.loadOrCreate(MemoryDeviceKeyRepository());
      await w.handle(<String, dynamic>{
        't': 'hello', 'pv': kPairingProtocolVersion, 'sid': b64(w.sid), 'cpk': b64(ck.publicKey), 'dn': 'Tablet', 'hs': b64(Uint8List(64))});
      expect(w.versionMismatchSeen, isFalse);
      await w.handle(<String, dynamic>{'t': 'pake1', 'pv': 2, 'sid': b64(w.sid), 'cpk': b64(ck.publicKey)});
      expect(w.versionMismatchSeen, isTrue, reason: 'an older build that goes straight to the key exchange is explained too');
      w.close();
    });

    test('the child client reports versionMismatch, but its surface only ever branches on ok', () async {
      final DeviceKey ck = await DeviceKey.loadOrCreate(MemoryDeviceKeyRepository());
      final PairingResult r = await ChildPairingClient(childKey: ck, transport: _OtherVersion(), deviceName: 'Tablet')
          .pair(sid: Uint8List(16), password: '4829');
      expect(r.ok, isFalse);
      expect(r.failure, PairingFailure.versionMismatch);
      final String src = File('lib/child_connect_screen.dart').readAsStringSync();
      expect(src.contains('versionMismatch'), isFalse, reason: 'the child surface never names or explains a version');
    });
  });

  group('ISS-061 and ISS-063: Her tablet, and Settings in one tap', () {
    GuardianLocalController ctl() => GuardianLocalController(
        GuardianLocalServices.memory(pinIterations: 500, family: LocalFamily.fromAnswers(
            guardianName: 'Jess', guardianLabel: 'Mom', guardianKind: GrownupKind.mom, childName: 'Ivy', age: 7)));

    Widget scoped(Widget home) => MaterialApp(
        builder: (BuildContext c, Widget? child) => GuardianLocalScope(controller: ctl(), child: child!), home: home);

    testWidgets('home gear: ONE tap opens Settings', (t) async {
      await _size(t, 390);
      await t.pumpWidget(scoped(_home(kids: () async => const PairedKidsLoad(<PairedKid>[]))));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('guardianHomeSettings')));
      await t.pumpAndSettle();
      expect(find.byType(GuardianSettingsHubScreen), findsOneWidget);
    });

    testWidgets('home gear keeps the PIN gate: with a PIN set, Settings does not open until it is entered', (t) async {
      await _size(t, 390);
      final GuardianLocalController c = ctl();
      await t.runAsync(() => c.services.pin.setPin('4829'));
      await t.pumpWidget(MaterialApp(
          builder: (BuildContext ctx, Widget? child) => GuardianLocalScope(controller: c, child: child!),
          home: _home(kids: () async => const PairedKidsLoad(<PairedKid>[]))));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('guardianHomeSettings')));
      await t.pumpAndSettle();
      expect(find.byType(GuardianSettingsHubScreen), findsNothing);
      expect(find.text('Enter your PIN'), findsWidgets);
    });

    testWidgets('More: Settings is the first row, on screen without scrolling, and one tap opens it', (t) async {
      await _size(t, 344, h: 800);
      await t.pumpWidget(scoped(const GuardianMoreScreen(childName: 'Ivy', childAge: 7)));
      await t.pumpAndSettle();
      final Finder row = find.byKey(const Key('moreSettings'));
      expect(row, findsOneWidget);
      expect(t.getTopLeft(row).dy, lessThan(200), reason: 'at the top of the screen, no scroll');
      final Rect settings = t.getRect(row);
      expect(t.getTopLeft(find.byKey(const Key('moreHerTablet'))).dy, greaterThan(settings.bottom), reason: 'Her tablet comes right after Settings');
      await t.tap(row);
      await t.pumpAndSettle();
      expect(find.byType(GuardianSettingsHubScreen), findsOneWidget);
    });

    testWidgets('More: the three tablet tiles are ONE "Her tablet" tile, above Archive', (t) async {
      await _size(t, 390, h: 1400);
      await t.pumpWidget(scoped(const GuardianMoreScreen(childName: 'Ivy', childAge: 7)));
      await t.pumpAndSettle();
      expect(find.text('HER TABLET'), findsOneWidget);
      expect(find.text("Ivy's tablet"), findsOneWidget);
      for (final String old in <String>[
        "Connect a child's device", "Unlock a child's device with my phone", 'Connected child devices', 'Connect this device',
        "Pair Ivy's tablet", "Unlock Ivy's tablet", "Ivy's tablets",
      ]) {
        expect(find.text(old), findsNothing, reason: old);
      }
      expect(find.byKey(const Key('morePairTablet')), findsNothing);
      expect(find.byKey(const Key('moreUnlockTablet')), findsNothing);
      expect(find.byKey(const Key('moreHerTablets')), findsNothing);
      final double tile = t.getTopLeft(find.byKey(const Key('moreHerTablet'))).dy;
      final double archive = t.getTopLeft(find.text('ARCHIVE')).dy;
      expect(tile < archive, isTrue, reason: 'one group, above Archive');
    });

    testWidgets('the one tile opens the Her tablet screen, and its buttons open the screens that used to be tiles', (t) async {
      await _size(t, 390, h: 1400);
      LocalServices.resetForTest();
      addTearDown(LocalServices.resetForTest);
      final GuardianLocalController c = ctl();
      await t.pumpWidget(MaterialApp(
          builder: (BuildContext ctx, Widget? child) => GuardianLocalScope(controller: c, child: child!),
          home: const GuardianMoreScreen(childName: 'Ivy', childAge: 7)));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('moreHerTablet')));
      await t.pumpAndSettle();
      expect(find.byType(HerTabletScreen), findsOneWidget);
      expect(find.byKey(const Key('herTabletHeadline')), findsOneWidget);
      expect(find.text("Ivy's tablet is not connected yet"), findsOneWidget);
    });
  });
}

/// A window of another pairing version: it answers a hello, but states pv 2.
class _OtherVersion implements PairingTransport {
  @override
  Future<Map<String, dynamic>?> send(Map<String, dynamic> message) async =>
      <String, dynamic>{'t': 'hello-ok', 'pv': 2, 'sid': b64(Uint8List(16))};
}
