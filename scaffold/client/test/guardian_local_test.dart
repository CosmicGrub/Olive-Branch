// OLIVE BRANCH — the guardian shell with a LOCAL family: the offline home, the settings hub behind
// the local PIN, the locked-age change behind the PIN gate, "Data on this device" with no session,
// "Connect this device" in Settings > Account, and the boot gate's three answers. No longer
// UNVERIFIED — verified by CI. MASTERFILE §8.5.9, §8.5.10.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/age_lock_screens.dart';
import 'package:olive_client/contact_labels.dart';
import 'package:olive_client/family_structure_screens.dart' show AgeBandsScreen;
import 'package:olive_client/guardian_boot.dart';
import 'package:olive_client/guardian_home.dart';
import 'package:olive_client/guardian_home_live.dart';
import 'package:olive_client/guardian_local_scope.dart';
import 'package:olive_client/guardian_more.dart';
import 'package:olive_client/guardian_settings_hub.dart';
import 'package:olive_client/guardian_setup.dart';
import 'package:olive_client/live_boot_plan.dart';
import 'package:olive_client/local_family.dart';
import 'package:olive_client/local_guardian_home.dart';
import 'package:olive_client/local_pin.dart';
import 'package:olive_client/local_pin_screens.dart';
import 'package:olive_client/local_services.dart';

class _FailingFamilies implements LocalFamilyRepository {
  _FailingFamilies(this.inner);
  final LocalFamilyRepository inner;
  @override
  Future<LocalFamily?> load() => inner.load();
  @override
  Future<void> save(LocalFamily family) async => throw StateError('disk full');
  @override
  Future<void> clear() => inner.clear();
}

LocalFamily family({int age = 7, String label = 'Dad', GrownupKind kind = GrownupKind.dad}) =>
    LocalFamily.fromAnswers(
        guardianName: 'Sam', guardianLabel: label, guardianKind: kind, childName: 'Ivy', age: age);

void main() {
  late GuardianLocalServices services;
  late GuardianLocalController controller;

  setUp(() {
    services = GuardianLocalServices.memory(pinIterations: 500, family: family());
    controller = GuardianLocalController(services, family: family());
  });

  Future<void> setPin(WidgetTester t, [String pin = '1234']) => t.runAsync(() => services.pin.setPin(pin));

  Future<void> typeIntoGate(WidgetTester t, String pin) async {
    await t.runAsync(() async {
      await t.enterText(find.byKey(const Key('localPinField')), pin);
      await t.tap(find.byKey(const Key('localPinOk')));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await t.pumpAndSettle();
  }

  Future<void> pumpMore(WidgetTester t, {GuardianLocalController? ctl, int childAge = 7}) async {
    await t.binding.setSurfaceSize(const Size(800, 2400));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(MaterialApp(
      builder: (BuildContext c, Widget? child) =>
          ctl == null ? child! : GuardianLocalScope(controller: ctl, child: child!),
      home: GuardianMoreScreen(childName: 'Ivy', childAge: childAge),
    ));
    await t.pumpAndSettle();
  }

  Future<void> openSettings(WidgetTester t) async {
    await t.ensureVisible(find.byKey(const Key('moreSettings')));
    await t.tap(find.byKey(const Key('moreSettings')));
    await t.pumpAndSettle();
  }

  group('offline guardian launch reaches the home without a server', () {
    testWidgets('OliveLocalGuardian shows the local family\'s home: her name, this phone\'s clock, no server error',
        (t) async {
      await t.binding.setSurfaceSize(const Size(800, 2000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(OliveLocalGuardian(controller: controller));
      await t.pumpAndSettle();
      expect(find.byType(LocalGuardianHome), findsOneWidget);
      expect(find.byType(GuardianHome), findsOneWidget);
      expect(find.byType(LiveGuardianHomeScreen), findsNothing, reason: 'no live wrapper: nothing asks a server');
      expect(find.byType(GuardianSetupScreen), findsNothing, reason: 'and no server-PIN trap');
      expect(find.textContaining('Ivy'), findsWidgets);
      expect(find.text("Couldn't reach the server"), findsNothing);
      expect(find.byKey(const Key('localHomeBand')), findsOneWidget);
      expect(find.text('On this device only.'), findsOneWidget, reason: 'nothing to connect to in this controller');
    });

    testWidgets('the band says how to connect when this build can', (t) async {
      final GuardianLocalController withConnect =
          GuardianLocalController(services, family: family(), onConnect: (BuildContext _) {});
      await t.binding.setSurfaceSize(const Size(800, 2000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(OliveLocalGuardian(controller: withConnect));
      await t.pumpAndSettle();
      expect(find.textContaining('connect it in Settings, under Account'), findsOneWidget);
    });

    testWidgets('her clock is the phone\'s when her zone is "same as this phone"; any other zone shows its name, no invented time',
        (t) async {
      await t.binding.setSurfaceSize(const Size(800, 2000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(MaterialApp(home: LocalGuardianHome(family: family(), nowHhmm: '14:05')));
      await t.pumpAndSettle();
      expect(find.text('2:05 PM'), findsWidgets);
      final LocalFamily london = LocalFamily.fromAnswers(
          guardianName: 'Sam', guardianLabel: 'Dad', guardianKind: GrownupKind.dad, childName: 'Ivy', age: 7,
          homeZone: 'Europe/London');
      await t.pumpWidget(MaterialApp(home: LocalGuardianHome(family: london, nowHhmm: '14:05')));
      await t.pumpAndSettle();
      expect(find.text('London'), findsOneWidget);
    });

    testWidgets('the local app has no pairing screen, no PIN setup and no Live banner on its way in', (t) async {
      await t.pumpWidget(OliveLocalGuardian(controller: controller));
      await t.pumpAndSettle();
      expect(find.textContaining('Live:'), findsNothing);
      expect(find.byKey(const Key('pairingCodeField')), findsNothing);
    });
  });

  group('the boot gate on the live guardian shell', () {
    testWidgets('entry: localPinSetup shows the local PIN setup (works offline), not the server-PIN screen', (t) async {
      await t.pumpWidget(OliveLiveGuardian(
        guardianId: 'g', session: null, hasPin: true, entry: GuardianEntry.localPinSetup, local: controller));
      await t.pumpAndSettle();
      expect(find.byType(LocalPinSetupScreen), findsOneWidget);
      expect(find.byType(GuardianSetupScreen), findsNothing);
      expect(find.text('Choose a PIN for this device'), findsOneWidget);
    });

    testWidgets('entry: serverPinSetup is the server-PIN setup exactly as before', (t) async {
      await t.pumpWidget(OliveLiveGuardian(
        guardianId: 'g', session: null, hasPin: false, entry: GuardianEntry.serverPinSetup, local: controller));
      await t.pumpAndSettle();
      expect(find.byType(GuardianSetupScreen), findsOneWidget);
      expect(find.byType(LocalPinSetupScreen), findsNothing);
    });

    testWidgets('entry: home is the live home; and with no entry, hasPin keeps its old two-way meaning', (t) async {
      await t.pumpWidget(const OliveLiveGuardian(guardianId: 'g', session: null, hasPin: true, entry: GuardianEntry.home));
      await t.pump();
      expect(find.byType(LiveGuardianHomeScreen), findsOneWidget);
      await t.pumpWidget(const OliveLiveGuardian(guardianId: 'g', session: null, hasPin: false));
      await t.pump();
      expect(find.byType(GuardianSetupScreen), findsOneWidget);
    });

    testWidgets('the local scope is offered to screens below the connected shell too', (t) async {
      GuardianLocalController? seen;
      await t.pumpWidget(OliveLiveGuardian(
        guardianId: 'g', session: null, hasPin: true, entry: GuardianEntry.localPinSetup, local: controller));
      await t.pumpAndSettle();
      seen = GuardianLocalScope.maybeOf(t.element(find.byType(LocalPinSetupScreen)));
      expect(seen, same(controller));
    });
  });

  group('the settings hub is behind the local PIN (and only when one exists)', () {
    testWidgets('no scope (the preview, the connected shell with no local PIN): opens straight away, as it always did',
        (t) async {
      await pumpMore(t);
      await openSettings(t);
      expect(find.byType(GuardianSettingsHubScreen), findsOneWidget);
      expect(find.byKey(const Key('localPinField')), findsNothing);
    });

    testWidgets('a scope but no local PIN set: still opens straight away', (t) async {
      await pumpMore(t, ctl: controller);
      await openSettings(t);
      expect(find.byType(GuardianSettingsHubScreen), findsOneWidget);
    });

    testWidgets('with a local PIN: a wrong PIN does not open it, Cancel does not, the right PIN does', (t) async {
      await setPin(t);
      await pumpMore(t, ctl: controller);
      await openSettings(t);
      expect(find.byKey(const Key('localPinField')), findsOneWidget);
      expect(find.byType(GuardianSettingsHubScreen), findsNothing);
      await typeIntoGate(t, '0000');
      expect(find.text('That is not your PIN.'), findsOneWidget);
      expect(find.byType(GuardianSettingsHubScreen), findsNothing);
      await t.tap(find.byKey(const Key('localPinCancel')));
      await t.pumpAndSettle();
      expect(find.byType(GuardianSettingsHubScreen), findsNothing);
      await openSettings(t);
      await typeIntoGate(t, '1234');
      expect(find.byType(GuardianSettingsHubScreen), findsOneWidget);
    });

    testWidgets('five wrong tries lock the hub for 15 minutes in the server\'s words', (t) async {
      await setPin(t);
      await pumpMore(t, ctl: controller);
      await openSettings(t);
      for (int i = 0; i < 5; i++) {
        await typeIntoGate(t, '0000');
      }
      expect(find.text(kLocalPinLockedMessage), findsOneWidget);
      await typeIntoGate(t, '1234');
      expect(find.byType(GuardianSettingsHubScreen), findsNothing, reason: 'locked: even the right PIN waits');
    });
  });

  group('her locked age changes only through the PIN gate', () {
    Future<void> openAgeRow(WidgetTester t) async {
      await setPin(t);
      await pumpMore(t, ctl: controller);
      await openSettings(t);
      await typeIntoGate(t, '1234');
      expect(find.byType(GuardianSettingsHubScreen), findsOneWidget);
      expect(find.text('Ivy is 7. Locked: your PIN changes it'), findsOneWidget);
      await t.tap(find.byKey(const Key('settingsRow_age')));
      await t.pumpAndSettle();
      // The row opens the real Age bands screen (Wave 3); the PIN-gated change is one tap further.
      expect(find.byType(AgeBandsScreen), findsOneWidget);
      await t.tap(find.byKey(const Key('bandsChangeAge')));
      await t.pumpAndSettle();
    }

    testWidgets('PIN, then 3 to 17, then Save: the family, the controller and the screen all agree', (t) async {
      await openAgeRow(t);
      expect(find.text("Ivy's age is locked. Your PIN lets you change it."), findsOneWidget);
      await typeIntoGate(t, '1234');
      for (int a = 3; a <= 17; a++) {
        expect(find.byKey(Key('lockAge_$a')), findsOneWidget, reason: 'age $a');
      }
      expect(find.byKey(const Key('lockAge_2')), findsNothing);
      await t.tap(find.byKey(const Key('lockAge_12')));
      await t.pump();
      await t.tap(find.byKey(const Key('lockAgeSave')));
      await t.pumpAndSettle();
      expect(controller.family!.age, 12);
      expect(controller.family!.ageLocked, isTrue);
      expect((await t.runAsync(services.families.load))!.age, 12, reason: 'persisted, not just shown');
      expect(find.text('Ivy is now 12.'), findsOneWidget);
    });

    testWidgets('a wrong PIN never reaches the age picker and the age is unchanged', (t) async {
      await openAgeRow(t);
      await typeIntoGate(t, '9999');
      expect(find.byKey(const Key('lockAge_12')), findsNothing);
      await t.tap(find.byKey(const Key('localPinCancel')));
      await t.pumpAndSettle();
      expect(controller.family!.age, 7);
      expect((await t.runAsync(services.families.load))!.age, 7);
    });

    testWidgets('Cancel on the picker changes nothing', (t) async {
      await openAgeRow(t);
      await typeIntoGate(t, '1234');
      await t.tap(find.byKey(const Key('lockAge_14')));
      await t.tap(find.byKey(const Key('lockAgeCancel')));
      await t.pumpAndSettle();
      expect(controller.family!.age, 7);
    });

    testWidgets('a store that cannot be written leaves the old age and says so (never "changed" when it was not)',
        (t) async {
      final GuardianLocalServices flaky = GuardianLocalServices(
          roles: services.roles, families: _FailingFamilies(services.families), pin: services.pin);
      final GuardianLocalController ctl = GuardianLocalController(flaky, family: family());
      await setPin(t);
      await pumpMore(t, ctl: ctl);
      await openSettings(t);
      await typeIntoGate(t, '1234');
      await t.tap(find.byKey(const Key('settingsRow_age')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('bandsChangeAge')));
      await t.pumpAndSettle();
      await typeIntoGate(t, '1234');
      await t.tap(find.byKey(const Key('lockAge_9')));
      await t.tap(find.byKey(const Key('lockAgeSave')));
      await t.pumpAndSettle();
      expect(ctl.family!.age, 7);
      expect(find.text('Could not keep that on this device. Her age is unchanged.'), findsOneWidget);
    });

    testWidgets('the flow itself: no family on this device says so and asks nothing', (t) async {
      final GuardianLocalController empty = GuardianLocalController(GuardianLocalServices.memory(pinIterations: 500));
      late BuildContext ctx;
      await t.pumpWidget(MaterialApp(home: Builder(builder: (BuildContext c) {
        ctx = c;
        return const Scaffold(body: SizedBox());
      })));
      final LocalFamily? r = await changeLockedAgeFlow(ctx, empty);
      await t.pump();
      expect(r, isNull);
      expect(find.text('There is no family set up on this device.'), findsOneWidget);
      expect(find.byKey(const Key('localPinField')), findsNothing);
    });

    testWidgets('without a local family the row opens the Age bands screen with no way to change a locked age (a connected guardian)', (t) async {
      await pumpMore(t);
      await openSettings(t);
      await t.tap(find.byKey(const Key('settingsRow_age')));
      await t.pumpAndSettle();
      expect(find.byType(AgeBandsScreen), findsOneWidget);
      expect(find.byKey(const Key('bandsChangeAge')), findsNothing);
      expect(find.byKey(const Key('lockAge_12')), findsNothing);
    });

    testWidgets('the "More" tile passes the locked age down (so the hub is not stuck on the demo default of 9)',
        (t) async {
      await t.binding.setSurfaceSize(const Size(800, 2400));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(MaterialApp(
        builder: (BuildContext c, Widget? child) => GuardianLocalScope(controller: controller, child: child!),
        home: LocalGuardianHome(family: family(age: 13)),
      ));
      await t.pumpAndSettle();
      await controller.saveFamily(family(age: 13));
      await t.ensureVisible(find.text('More'));
      await t.tap(find.text('More'));
      await t.pumpAndSettle();
      final GuardianMoreScreen more = t.widget<GuardianMoreScreen>(find.byType(GuardianMoreScreen));
      expect(more.childAge, 13);
      expect(more.childName, 'Ivy');
    });
  });

  group('Data on this device works offline with the local PIN, and only with it', () {
    Future<void> openWipe(WidgetTester t, {GuardianLocalController? ctl}) async {
      await pumpMore(t, ctl: ctl);
      await t.scrollUntilVisible(find.byKey(const Key('moreDeviceData')), 300, scrollable: find.byType(Scrollable).first);
      await t.tap(find.byKey(const Key('moreDeviceData')));
      await t.pumpAndSettle();
    }

    testWidgets('with no session and no scope at all it stays unavailable (fail closed, as before)', (t) async {
      await openWipe(t);
      expect(find.byKey(const Key('clearDataUnavailable')), findsOneWidget);
    });

    testWidgets('with a scope but NO local PIN set, no PIN opens it: fail closed', (t) async {
      final LocalServices ls = LocalServices.memory(childId: 'ivy');
      LocalServices.install(ls);
      addTearDown(LocalServices.resetForTest);
      await ls.area('lists').put('wants', <Object?>['bike']);
      await t.binding.setSurfaceSize(const Size(500, 5200));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await openWipe(t, ctl: controller);
      await t.enterText(find.byKey(const Key('clearDataPin')), '1234');
      await t.pump();
      await t.ensureVisible(find.byKey(const Key('clearDataButton')));
      await t.tap(find.byKey(const Key('clearDataButton')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('clearDataWrongPin')), findsOneWidget);
      expect(find.byKey(const Key('clearDataConfirm')), findsNothing);
      expect(await ls.area('lists').get('wants'), <Object?>['bike']);
    });

    testWidgets('with a local PIN and no session: a wrong PIN clears nothing; the right PIN clears everything',
        (t) async {
      final LocalServices ls = LocalServices.memory(childId: 'ivy');
      LocalServices.install(ls);
      addTearDown(LocalServices.resetForTest);
      // Seeded inside the test body (the fake-async zone), like clear_local_data_screen_test.dart.
      await ls.area('lists').put('wants', <Object?>['bike']);
      await services.pin.setPin('1234');
      await t.binding.setSurfaceSize(const Size(500, 5200));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await openWipe(t, ctl: controller);
      expect(find.byKey(const Key('clearDataUnavailable')), findsNothing);

      Future<void> tryPin(String pin) async {
        await t.enterText(find.byKey(const Key('clearDataPin')), pin);
        await t.pump();
        await t.ensureVisible(find.byKey(const Key('clearDataButton')));
        await t.tap(find.byKey(const Key('clearDataButton')));
        await t.pumpAndSettle();
      }

      await tryPin('0000');
      expect(find.byKey(const Key('clearDataWrongPin')), findsOneWidget);
      expect(find.byKey(const Key('clearDataConfirm')), findsNothing);
      expect(await ls.area('lists').get('wants'), <Object?>['bike']);

      await tryPin('1234');
      expect(find.byKey(const Key('clearDataConfirm')), findsOneWidget);
      await t.tap(find.byKey(const Key('clearDataConfirm')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('clearDataDone')), findsOneWidget);
      expect(await ls.area('lists').get('wants'), isNull);
    });
  });

  group('Settings > Account > Connect this device', () {
    testWidgets('it is there only when the build can connect and the device is not connected yet', (t) async {
      int opened = 0;
      final GuardianLocalController withConnect =
          GuardianLocalController(services, family: family(), onConnect: (BuildContext _) => opened++);
      await pumpMore(t, ctl: withConnect);
      await openSettings(t);
      await t.ensureVisible(find.byKey(const Key('settingsRow_connect')));
      expect(find.text('Connect this device'), findsOneWidget);
      expect(find.text('Optional. Share your family with your other devices'), findsOneWidget);
      await t.tap(find.byKey(const Key('settingsRow_connect')));
      await t.pump();
      expect(opened, 1);
    });

    testWidgets('a connected shell (no onConnect) has no such row', (t) async {
      await pumpMore(t, ctl: controller);
      await openSettings(t);
      expect(find.byType(GuardianSettingsHubScreen), findsOneWidget);
      expect(find.byKey(const Key('settingsRow_connect')), findsNothing);
    });

    testWidgets('the preview (no scope) has no such row either', (t) async {
      await pumpMore(t);
      await openSettings(t);
      expect(find.byType(GuardianSettingsHubScreen), findsOneWidget);
      expect(find.byKey(const Key('settingsRow_connect')), findsNothing);
    });
  });

  test('the server PIN is not faked: nothing in the local PIN or local family path calls the account PIN routes', () {
    for (final String f in <String>[
      'local_pin.dart', 'local_pin_screens.dart', 'local_family.dart', 'guardian_onboarding.dart',
      'local_guardian_home.dart', 'age_lock_screens.dart',
    ]) {
      final String src = File('lib/$f')
          .readAsStringSync()
          .split('\n')
          .where((String l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      for (final String bad in <String>['setGuardianPin', 'verifyKioskPin', 'verifyControlsPin', 'changeGuardianPin', '/v1/me/pin']) {
        expect(src, isNot(contains(bad)), reason: '$f must not touch the account PIN: $bad');
      }
    }
  });
}
