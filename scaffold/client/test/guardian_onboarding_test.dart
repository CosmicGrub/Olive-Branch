// OLIVE BRANCH — guardian_onboarding.dart tests: the guardian's first run builds a LOCAL family and
// a LOCAL PIN with no server, and offers "Connect this device" last. No longer UNVERIFIED —
// verified by CI. MASTERFILE §8.5.9.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:olive_client/contact_labels.dart';
import 'package:olive_client/device_role.dart';
import 'package:olive_client/guardian_local_scope.dart';
import 'package:olive_client/guardian_onboarding.dart';
import 'package:olive_client/local_family.dart';

class _FailingFamilies implements LocalFamilyRepository {
  @override
  Future<LocalFamily?> load() async => null;
  @override
  Future<void> save(LocalFamily family) async => throw StateError('disk full');
  @override
  Future<void> clear() async {}
}

void main() {
  late GuardianLocalServices services;
  late List<LocalFamily> finished;
  late List<Map<String, dynamic>> redeemed;

  setUp(() {
    services = GuardianLocalServices.memory(pinIterations: 500);
    finished = <LocalFamily>[];
    redeemed = <Map<String, dynamic>>[];
  });

  Future<void> pump(
    WidgetTester t, {
    DeviceRole role = DeviceRole.mom,
    bool serverAvailable = false,
    GuardianLocalServices? withServices,
    http.Client? client,
  }) async {
    await t.binding.setSurfaceSize(const Size(800, 3200));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(MaterialApp(
      home: GuardianOnboardingFlow(
        role: role,
        services: withServices ?? services,
        serverAvailable: serverAvailable,
        baseUrl: 'http://olive.test',
        httpClient: client,
        onRedeemed: redeemed.add,
        onFinished: finished.add,
      ),
    ));
    await t.pumpAndSettle();
  }

  Future<void> fillYou(WidgetTester t, {String name = 'Sam', String? label}) async {
    await t.enterText(find.byKey(const Key('goName')), name);
    if (label != null) await t.enterText(find.byKey(const Key('goLabel')), label);
    await t.tap(find.byKey(const Key('goYouNext')));
    await t.pumpAndSettle();
  }

  Future<void> fillHer(WidgetTester t, {String name = 'Ivy', int age = 7}) async {
    await t.enterText(find.byKey(const Key('goChild')), name);
    await t.tap(find.byKey(Key('goAge_$age')));
    await t.pump();
    await t.tap(find.byKey(const Key('goHerNext')));
    await t.pumpAndSettle();
  }

  Future<void> savePin(WidgetTester t, String pin) async {
    await t.runAsync(() async {
      await t.enterText(find.byKey(const Key('localPinNew')), pin);
      await t.enterText(find.byKey(const Key('localPinConfirm')), pin);
      await t.tap(find.byKey(const Key('localPinSave')));
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    await t.pumpAndSettle();
  }

  group('a Mom\'s first run, start to finish, with no server', () {
    testWidgets('name and label, her name and age, zone, a PIN: the local family and PIN are persisted',
        (t) async {
      await pump(t);
      // Step 1: the label is already "Mom" for the Mom role.
      expect(find.text('About you'), findsOneWidget);
      expect(t.widget<TextField>(find.byKey(const Key('goLabel'))).controller!.text, 'Mom');
      await fillYou(t, name: 'Sam');

      // Step 2: her name, her age; the lock is said in plain words.
      expect(find.text('About her'), findsOneWidget);
      expect(find.textContaining('locked'), findsOneWidget);
      await fillHer(t, name: 'Ivy', age: 7);

      // Step 3: the zone; "same as this phone" is already chosen.
      expect(find.text('Where does she live?'), findsOneWidget);
      await t.tap(find.byKey(const Key('goZoneNext')));
      await t.pumpAndSettle();

      // Step 4: the PIN. Not skippable: there is no Next, only Save.
      expect(find.text('A PIN for this device'), findsOneWidget);
      expect(find.byKey(const Key('goYouNext')), findsNothing);
      expect(find.text('Next'), findsNothing);
      expect(finished, isEmpty);
      expect(await services.families.load(), isNull, reason: 'nothing is kept until the PIN is');
      await savePin(t, '4821');

      expect(finished.length, 1);
      final LocalFamily f = finished.single;
      expect(f.guardianName, 'Sam');
      expect(f.guardianLabel, 'Mom');
      expect(f.guardianKind, GrownupKind.mom);
      expect(f.childName, 'Ivy');
      expect(f.age, 7);
      expect(f.ageLocked, isTrue);
      expect(f.homeZone, kHomeZoneDevice);

      // Persisted: a restart reads the same family, and the PIN is set (as a hash).
      final LocalFamily? stored = await t.runAsync<LocalFamily?>(services.families.load);
      expect(stored?.toJson(), f.toJson());
      expect(await t.runAsync(services.pin.isSet), isTrue);
      expect((await t.runAsync(() => services.pin.verify('4821')))!.ok, isTrue);
      expect(redeemed, isEmpty, reason: 'no server was involved');
    });

    testWidgets('a Dad can pick Dad with one tap; his own word works too and is not treated as a Dad', (t) async {
      await pump(t, role: DeviceRole.dad);
      expect(t.widget<TextField>(find.byKey(const Key('goLabel'))).controller!.text, 'Dad');
      await t.tap(find.byKey(const Key('goLabel_Mom')));
      await t.pump();
      expect(t.widget<TextField>(find.byKey(const Key('goLabel'))).controller!.text, 'Mom');
      await t.tap(find.byKey(const Key('goLabel_Dad')));
      await t.pump();
      expect(t.widget<TextField>(find.byKey(const Key('goLabel'))).controller!.text, 'Dad');
      await fillYou(t, name: 'Alex', label: 'Papa');
      await fillHer(t, age: 10);
      await t.tap(find.byKey(const Key('goZoneNext')));
      await t.pumpAndSettle();
      await savePin(t, '1357');
      expect(finished.single.guardianLabel, 'Papa');
      expect(finished.single.guardianKind, GrownupKind.other,
          reason: 'a word of their own is shown to her as it is (no Daddy swap)');
    });

    testWidgets('someone else starts with no label and must choose their own word', (t) async {
      await pump(t, role: DeviceRole.other);
      expect(t.widget<TextField>(find.byKey(const Key('goLabel'))).controller!.text, '');
      await t.enterText(find.byKey(const Key('goName')), 'Rosa');
      await t.tap(find.byKey(const Key('goYouNext')));
      await t.pumpAndSettle();
      expect(find.text('Please choose what she should call you.'), findsOneWidget);
      expect(find.text('About her'), findsNothing);
      await fillYou(t, name: 'Rosa', label: 'Nana');
      await fillHer(t, age: 12);
      await t.tap(find.byKey(const Key('goZoneNext')));
      await t.pumpAndSettle();
      await savePin(t, '9090');
      expect(finished.single.guardianLabel, 'Nana');
      expect(finished.single.guardianKind, GrownupKind.other);
    });

    testWidgets('the home time zone she lives in is kept', (t) async {
      await pump(t);
      await fillYou(t);
      await fillHer(t);
      await t.tap(find.byKey(const Key('goZone_Europe/London')));
      await t.pump();
      await t.tap(find.byKey(const Key('goZoneNext')));
      await t.pumpAndSettle();
      await savePin(t, '4821');
      expect(finished.single.homeZone, 'Europe/London');
    });
  });

  group('every step holds the grown-up until it is answered, in plain words', () {
    testWidgets('your name is needed', (t) async {
      await pump(t);
      await t.tap(find.byKey(const Key('goYouNext')));
      await t.pumpAndSettle();
      expect(find.text('Please add your name.'), findsOneWidget);
      expect(find.text('About her'), findsNothing);
    });

    testWidgets('her name and her age are needed, and the ages offered are 3 to 17 (a grown-up\'s range)', (t) async {
      await pump(t);
      await fillYou(t);
      for (int a = 3; a <= 17; a++) {
        expect(find.byKey(Key('goAge_$a')), findsOneWidget, reason: 'age $a');
      }
      expect(find.byKey(const Key('goAge_2')), findsNothing);
      expect(find.byKey(const Key('goAge_18')), findsNothing);
      await t.tap(find.byKey(const Key('goHerNext')));
      await t.pumpAndSettle();
      expect(find.text('Please add her first name.'), findsOneWidget);
      await t.enterText(find.byKey(const Key('goChild')), 'Ivy');
      await t.tap(find.byKey(const Key('goHerNext')));
      await t.pumpAndSettle();
      expect(find.text('Please choose her age.'), findsOneWidget);
      expect(find.text('Where does she live?'), findsNothing);
    });

    testWidgets('a name that is too long is refused', (t) async {
      await pump(t);
      await t.enterText(find.byKey(const Key('goName')), 'x' * 41);
      await t.tap(find.byKey(const Key('goYouNext')));
      await t.pumpAndSettle();
      expect(find.text('That is a little too long.'), findsOneWidget);
    });
  });

  group('the family is only reported saved when it is saved', () {
    testWidgets('a store that cannot be written says so, stays on the PIN step, and finishes nothing', (t) async {
      final GuardianLocalServices flaky = GuardianLocalServices(
        roles: services.roles, families: _FailingFamilies(), pin: services.pin);
      await pump(t, withServices: flaky);
      await fillYou(t);
      await fillHer(t);
      await t.tap(find.byKey(const Key('goZoneNext')));
      await t.pumpAndSettle();
      await savePin(t, '4821');
      expect(finished, isEmpty);
      expect(find.text('Could not keep your family on this device. Please try again.'), findsOneWidget);
      expect(find.textContaining('disk full'), findsNothing, reason: 'no raw error text');
      expect(find.text('A PIN for this device'), findsOneWidget);
    });
  });

  group('Connect this device is LAST, optional, and only where a server exists', () {
    http.Client okClient() => MockClient((http.Request r) async {
          if (r.url.path == '/v1/device-pairing/redeem') {
            expect(jsonDecode(r.body), <String, Object?>{'code': '123456', 'role': 'guardian'});
            return http.Response(jsonEncode(<String, Object?>{
              'sessionToken': 't', 'deviceId': 'd', 'role': 'guardian', 'targetId': 'g-1', 'deviceCredential': 'c',
            }), 201);
          }
          return http.Response('{}', 404);
        });

    testWidgets('with a server it comes after the PIN; the family and PIN are ALREADY saved when it shows',
        (t) async {
      await pump(t, serverAvailable: true, client: okClient());
      await fillYou(t);
      await fillHer(t);
      await t.tap(find.byKey(const Key('goZoneNext')));
      await t.pumpAndSettle();
      await savePin(t, '4821');

      expect(find.text('Connect this device'), findsOneWidget);
      expect(find.byKey(const Key('pairingGuardianLocalFirst')), findsOneWidget);
      expect(find.textContaining('optional'), findsWidgets);
      expect(find.byKey(const Key('pairingGuardianWhy')), findsNothing, reason: 'not the "connect first" copy');
      expect(finished, isEmpty, reason: 'not finished until she connects or says not now');
      // A restart here (or "Not now") never repeats the questions: it is all saved.
      expect((await t.runAsync<LocalFamily?>(services.families.load))?.childName, 'Ivy');
      expect(await t.runAsync(services.pin.isSet), isTrue);
    });

    testWidgets('"Not now" is a real way on: the local family works offline and finishes', (t) async {
      await pump(t, serverAvailable: true, client: okClient());
      await fillYou(t);
      await fillHer(t);
      await t.tap(find.byKey(const Key('goZoneNext')));
      await t.pumpAndSettle();
      await savePin(t, '4821');
      await t.tap(find.byKey(const Key('pairingGuardianNotNow')));
      await t.pumpAndSettle();
      expect(finished.single.childName, 'Ivy');
      expect(redeemed, isEmpty);
    });

    testWidgets('connecting hands the redeem result to the caller', (t) async {
      await pump(t, serverAvailable: true, client: okClient());
      await fillYou(t);
      await fillHer(t);
      await t.tap(find.byKey(const Key('goZoneNext')));
      await t.pumpAndSettle();
      await savePin(t, '4821');
      await t.enterText(find.byKey(const Key('pairingCodeField')), '123456');
      await t.tap(find.byKey(const Key('pairingConnectButton')));
      // The button spins until the caller replaces the screen, so pump rather than settle.
      await t.pump();
      await t.pump(const Duration(milliseconds: 100));
      expect(redeemed.single['targetId'], 'g-1');
      expect(finished, isEmpty, reason: 'the caller boots the connected shell instead');
    });

    testWidgets('the connect step fits a small phone at 1.5x text without overflowing (it scrolls)', (t) async {
      await pump(t, serverAvailable: true, client: okClient());
      await fillYou(t);
      await fillHer(t);
      await t.tap(find.byKey(const Key('goZoneNext')));
      await t.pumpAndSettle();
      await savePin(t, '4821');
      await t.binding.setSurfaceSize(const Size(360, 640));
      await t.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(360, 640), textScaler: TextScaler.linear(1.5)),
          child: GuardianOnboardingFlow(
            role: DeviceRole.mom,
            services: GuardianLocalServices.memory(pinIterations: 500),
            serverAvailable: true,
            baseUrl: 'http://olive.test',
            httpClient: okClient(),
            onRedeemed: (_) {},
            onFinished: (_) {},
          ),
        ),
      ));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });

    testWidgets('with no server the step does not exist: the family is finished right after the PIN', (t) async {
      await pump(t, serverAvailable: false);
      await fillYou(t);
      await fillHer(t);
      await t.tap(find.byKey(const Key('goZoneNext')));
      await t.pumpAndSettle();
      await savePin(t, '4821');
      expect(finished.length, 1);
      expect(find.text('Connect this device'), findsNothing);
    });
  });
}
