// OLIVE BRANCH — the care profile screens, driven by taps: the hub, a part, both versions, the PIN on the
// locked parts, who sees what and "show as", the photos of a plan, the doctor sheet, the teen preview and the
// posture at 344 dp and 2.0x text. UNVERIFIED until CI runs this file. MASTERFILE section 8.24.8.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/care_local.dart';
import 'package:olive_client/care_profile_logic.dart';
import 'package:olive_client/care_profile_screens.dart';
import 'package:olive_client/care_profile_store.dart';
import 'package:olive_client/emergency_card_local.dart';
import 'package:olive_client/family_structure_logic.dart';
import 'package:olive_client/growing_care_logic.dart';
import 'package:olive_client/growing_care_store.dart';

const FamilyPrincipal mom = FamilyPrincipal(roleName: 'guardian', userId: 'mom');
const FamilyPrincipal dad = FamilyPrincipal(roleName: 'guardian', userId: 'dad');
const FamilyPrincipal kid = FamilyPrincipal(roleName: 'child', userId: 'ivy', childId: 'ivy');

Future<bool> _pinOk(String pin) async => pin == '2580';
Uint8List _jpeg() => Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3, 4]);

class Clock {
  Clock(this.t);
  DateTime t;
  DateTime call() => t;
}

Future<void> _show(WidgetTester t, Widget w, {double width = 800, double scale = 1.0}) async {
  t.view.physicalSize = Size(width, 2600);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(MaterialApp(
    builder: (BuildContext c, Widget? child) => MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
    home: w,
  ));
  await t.pumpAndSettle();
}

/// A page with a button that opens [w] on top, so a screen that pops itself has somewhere to go.
Future<void> _showPushed(WidgetTester t, Widget Function() w) async {
  await _show(t, Builder(builder: (BuildContext c) => Scaffold(body: Center(child: ElevatedButton(key: const Key('go'), onPressed: () => Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => w())), child: const Text('go'))))));
  await t.tap(find.byKey(const Key('go')));
  await t.pumpAndSettle();
}

void main() {
  late Clock clock;
  late CareProfileService svc;
  late CarePlanPhotoService plans;
  late CareService meds;
  late EmergencyCardService card;
  late GrowingCareStores binder;

  setUp(() {
    clock = Clock(DateTime(2026, 11, 14, 9));
    svc = CareProfileService.memory(clock: clock.call);
    plans = CarePlanPhotoService.memory(clock: clock.call);
    meds = CareService.memory(childScope: 'ivy', clock: clock.call);
    card = EmergencyCardService.memory(clock: clock.call);
    binder = GrowingCareStores.memory();
  });

  Widget hub({FamilyPrincipal? who = mom, int? age, Future<bool> Function(String)? pin = _pinOk, PlanPhotoSource? photo}) => CareProfileScreen(
        service: svc, plans: plans, principal: who, childName: 'Mia', childAge: age, byName: 'Sam', verifyPin: pin,
        meds: meds, emergency: card, binder: binder, photoSource: photo, clock: clock.call,
        openMedicines: (BuildContext c) => const Scaffold(body: Text('the medicines screen', key: Key('medsOpened'))),
      );

  Widget part(CareProfilePart p, {FamilyPrincipal? who = mom, Future<bool> Function(String)? pin = _pinOk, String name = 'Sam'}) => CareProfilePartScreen(
        service: svc, principal: who, part: p, childName: 'Mia', byName: name, verifyPin: pin, clock: clock.call);

  group('the hub', () {
    testWidgets('says plainly where it is kept, that sharing between phones is not built, and that she never sees it', (t) async {
      await _show(t, hub());
      final String banner = t.widget<Text>(find.descendant(of: find.byKey(const Key('profileBanner')), matching: find.byType(Text))).data!;
      expect(banner, contains('never shown in her app'));
      expect(banner, contains('Sharing between phones is not built yet'));
      expect(banner, contains('no medical advice'));
      for (final String k in <String>['part-safe', 'part-everyday', 'part-helps', 'part-meds', 'part-health', 'part-moods', 'openSharing', 'openPlans', 'openSheet', 'headsCard']) {
        expect(find.byKey(Key(k)), findsOneWidget, reason: k);
      }
    });

    testWidgets('a child, or nobody, gets one neutral line and nothing is read', (t) async {
      await svc.addEntry(mom, CareProfilePart.safe, 'Peanut allergy');
      for (final FamilyPrincipal? p in <FamilyPrincipal?>[kid, null]) {
        await _show(t, hub(who: p));
        expect(find.byKey(const Key('careProfileNotForYou')), findsOneWidget);
        expect(find.textContaining('Peanut'), findsNothing);
        expect(find.byKey(const Key('headsCard')), findsNothing);
      }
    });

    testWidgets('copies the care binder in once, says so, and the binder keeps its own copy', (t) async {
      await binder.sections.save(const CareSection(id: 's1', kind: 'allergies', title: 'Allergies (written by a guardian)', body: 'Peanuts: hives', updatedOn: '2026-10-01'));
      await _show(t, hub());
      expect(find.byKey(const Key('profileCopied')), findsOneWidget);
      expect(find.textContaining('The binder still has its own copy'), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('part-safe')), matching: find.textContaining('1 written')), findsOneWidget);
      expect((await binder.sections.list()).single.body, 'Peanuts: hives');
      // Opening it again (a fresh screen) copies nothing twice.
      await _show(t, const SizedBox());
      await _show(t, hub());
      expect(find.byKey(const Key('profileCopied')), findsNothing);
      expect((await svc.read(mom)).entries, hasLength(1));
    });

    testWidgets('Medicines opens the existing medicines screen', (t) async {
      await _show(t, hub());
      await t.tap(find.byKey(const Key('part-meds')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('medsOpened')), findsOneWidget);
    });

    testWidgets("today's heads-up: the tone guard refuses a label with guidance; a good note shows and is gone tomorrow", (t) async {
      await _show(t, hub());
      expect(find.byKey(const Key('headsEmpty')), findsOneWidget);
      await t.tap(find.byKey(const Key('headsWrite')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('headsField')), 'In a bad mood, obviously');
      await t.tap(find.byKey(const Key('headsSave')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('headsError')), findsOneWidget);
      expect(find.textContaining('describing what is needed'), findsOneWidget);
      expect((await svc.read(mom)).heads, isNull);
      await t.enterText(find.byKey(const Key('headsField')), 'Slept badly, extra patience');
      await t.tap(find.byKey(const Key('headsSave')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('headsText')), findsOneWidget);
      expect(find.textContaining('written by Sam, today'), findsOneWidget);
      clock.t = DateTime(2026, 11, 15, 0, 5);
      await _show(t, hub());
      expect(find.byKey(const Key('headsEmpty')), findsOneWidget);
      expect(find.textContaining('Slept badly'), findsNothing);
    });

    testWidgets('a review prompt appears after 90 days and "Yes, still right" settles it', (t) async {
      await svc.addEntry(mom, CareProfilePart.safe, 'Peanut allergy');
      await svc.ensureBaseline(mom, cpMedicineFingerprint(await meds.read(mom)));
      clock.t = DateTime(2027, 2, 20);
      await _show(t, hub());
      expect(find.byKey(const ValueKey<String>('review-ninetyDays')), findsOneWidget);
      await t.tap(find.byKey(const Key('reviewYes')));
      await t.pumpAndSettle();
      expect(find.byKey(const ValueKey<String>('review-ninetyDays')), findsNothing);
    });

    testWidgets('a medicine change brings the prompt', (t) async {
      // Built here, not in setUp: these services chain their writes on a future made when they are constructed.
      meds = CareService.memory(childScope: 'ivy', clock: clock.call);
      await svc.addEntry(mom, CareProfilePart.safe, 'Peanut allergy');
      await svc.ensureBaseline(mom, cpMedicineFingerprint(await meds.read(mom)));
      await meds.addMedication(mom, const CareMedication(id: '', name: 'Inhaler', kind: MedKind.prn));
      await _show(t, hub());
      expect(find.byKey(const ValueKey<String>('review-medicineChange')), findsOneWidget);
    });

    testWidgets('the teen preview is OFF by default, shows a teen sheet only for 13 to 17 once switched on', (t) async {
      await svc.addEntry(mom, CareProfilePart.safe, 'Peanut allergy');
      await _show(t, hub(age: 14));
      expect(t.widget<SwitchListTile>(find.byKey(const Key('teenPreview'))).value, isFalse);
      expect(find.byKey(const Key('teenSeeSheet')), findsNothing);
      await t.ensureVisible(find.byKey(const Key('teenPreview')));
      await t.tap(find.byKey(const Key('teenPreview')));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const Key('teenSeeSheet')));
      await t.tap(find.byKey(const Key('teenSeeSheet')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('teenNote')), findsOneWidget);
      expect(find.textContaining('Peanut allergy'), findsOneWidget);
      expect(find.textContaining('not on any child'), findsOneWidget);
    });

    testWidgets('for a child who is not a teen the preview says so and offers no sheet', (t) async {
      await svc.setTeenPreview(mom, true);
      await _show(t, hub(age: 9));
      expect(find.byKey(const Key('teenNotTeen')), findsOneWidget);
      expect(find.byKey(const Key('teenSeeSheet')), findsNothing);
    });
  });

  group('a part', () {
    testWidgets('adding an entry shows who wrote it and when', (t) async {
      await _show(t, part(CareProfilePart.safe));
      expect(find.byKey(const Key('partEmpty')), findsOneWidget);
      await t.tap(find.byKey(const Key('addEntry')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('entryTitle')), 'Allergy');
      await t.enterText(find.byKey(const Key('entryText')), 'Peanuts: hives');
      await t.tap(find.byKey(const Key('entrySave')));
      await t.pumpAndSettle();
      expect(find.text('Peanuts: hives'), findsOneWidget);
      expect(find.textContaining('written by Sam, 14 Nov 2026'), findsOneWidget);
    });

    testWidgets('the tone guard names the phrase, writes nothing, and a fair rewrite goes through', (t) async {
      await _show(t, part(CareProfilePart.helps));
      await t.tap(find.byKey(const Key('addEntry')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('entryText')), 'She is naughty when tired');
      await t.tap(find.byKey(const Key('entrySave')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('entryError')), findsOneWidget);
      expect(find.textContaining('naughty'), findsWidgets);
      expect((await svc.read(mom)).entries, isEmpty);
      await t.enterText(find.byKey(const Key('entryText')), 'Needs quiet when tired');
      await t.tap(find.byKey(const Key('entrySave')));
      await t.pumpAndSettle();
      expect(find.text('Needs quiet when tired'), findsOneWidget);
    });

    testWidgets('both versions show side by side, each with its writer; choosing one puts the other away', (t) async {
      final String a = (await svc.addEntry(mom, CareProfilePart.everyday, 'Bed at 7:30', title: 'Bedtime', byName: 'Sam')).value!;
      final String b = (await svc.addMyVersion(dad, a, 'Bed at 8', byName: 'Alex')).value!;
      await _show(t, part(CareProfilePart.everyday));
      expect(find.byKey(ValueKey<String>('differ-$a')), findsOneWidget);
      expect(find.text('Bed at 7:30'), findsOneWidget);
      expect(find.text('Bed at 8'), findsOneWidget);
      expect(find.textContaining('written by Sam'), findsOneWidget);
      expect(find.textContaining('written by Alex'), findsOneWidget);
      // Alex's is not Sam's to change: no Change or Put away on it.
      expect(find.byKey(ValueKey<String>('edit-$b')), findsNothing);
      expect(find.byKey(ValueKey<String>('away-$b')), findsNothing);
      await t.tap(find.byKey(ValueKey<String>('use-$a')));
      await t.pumpAndSettle();
      expect(find.byKey(ValueKey<String>('differ-$a')), findsNothing);
      expect(find.text('Bed at 8'), findsNothing);
      await t.tap(find.byKey(const Key('showAway')));
      await t.pumpAndSettle();
      expect(find.text('Bed at 8'), findsOneWidget, reason: 'kept, and can come back');
      expect(find.byKey(ValueKey<String>('back-$b')), findsOneWidget);
    });

    testWidgets('what changed is a plain note with who and when, and says it is not a record', (t) async {
      final String id = (await svc.addEntry(mom, CareProfilePart.everyday, 'Bed at 7', title: 'Bedtime', byName: 'Sam')).value!;
      await svc.editEntry(mom, id, 'Bed at 7:30', byName: 'Sam');
      await _show(t, part(CareProfilePart.everyday));
      await t.tap(find.byKey(ValueKey<String>('hist-$id')));
      await t.pumpAndSettle();
      expect(find.textContaining('Sam changed this on 14 Nov 2026. It used to say: Bed at 7'), findsOneWidget);
      expect(find.textContaining('not a record of anything'), findsOneWidget);
    });

    testWidgets('someone else\'s entry offers "Write my version" and no Change', (t) async {
      final String a = (await svc.addEntry(dad, CareProfilePart.everyday, 'Oats', title: 'Breakfast', byName: 'Alex')).value!;
      await _show(t, part(CareProfilePart.everyday));
      expect(find.byKey(ValueKey<String>('edit-$a')), findsNothing);
      await t.tap(find.byKey(ValueKey<String>('mine-$a')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('entryText')), 'Toast');
      await t.tap(find.byKey(const Key('entrySave')));
      await t.pumpAndSettle();
      expect(find.text('Oats'), findsOneWidget);
      expect(find.text('Toast'), findsOneWidget);
      expect(find.textContaining('These differ'), findsOneWidget);
    });

    testWidgets('a non-guardian gets the neutral line', (t) async {
      await _show(t, part(CareProfilePart.safe, who: kid));
      expect(find.byKey(const Key('careProfileNotForYou')), findsOneWidget);
    });
  });

  group('the locked parts', () {
    testWidgets('the PIN is asked; a wrong one opens nothing; the right one opens it and the screen locks it again on leaving', (t) async {
      await _show(t, hub());
      await svc.unlock(mom, _pinOk, '2580');
      await svc.addEntry(mom, CareProfilePart.health, 'Asthma since 2024', title: 'Diagnosis');
      svc.lock();
      await t.tap(find.byKey(const Key('part-health')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('profilePinField')), findsOneWidget);
      expect(find.text('Asthma since 2024'), findsNothing);
      await t.enterText(find.byKey(const Key('profilePinField')), '0000');
      await t.tap(find.byKey(const Key('profilePinOk')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('profilePinMessage')), findsOneWidget);
      expect(find.text('Asthma since 2024'), findsNothing);
      await t.enterText(find.byKey(const Key('profilePinField')), '2580');
      await t.tap(find.byKey(const Key('profilePinOk')));
      await t.pumpAndSettle();
      expect(find.text('Asthma since 2024'), findsOneWidget);
      expect(find.byKey(const Key('lockedNote')), findsOneWidget);
      await t.pageBack();
      await t.pumpAndSettle();
      expect(svc.isUnlocked, isFalse, reason: 'leaving the part closes it');
    });

    testWidgets('cancelling leaves the part closed and the screen goes back', (t) async {
      await _showPushed(t, () => part(CareProfilePart.moods));
      expect(find.byKey(const Key('profilePinField')), findsOneWidget);
      await t.tap(find.byKey(const Key('profilePinCancel')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('go')), findsOneWidget, reason: 'back where it started');
      expect(svc.isUnlocked, isFalse);
    });

    testWidgets('with no PIN on the device the part stays closed and says to set one', (t) async {
      await _showPushed(t, () => part(CareProfilePart.health, pin: null));
      expect(find.textContaining('Set a PIN for this phone'), findsOneWidget);
      expect(find.byKey(const Key('addEntry')), findsNothing);
    });
  });

  group('who sees what', () {
    Widget sharing() => CareProfileSharingScreen(service: svc, plans: plans, principal: mom, childName: 'Mia', byName: 'Sam', meds: meds, clock: clock.call);

    testWidgets('says sharing between phones is not built; Health history and Moods have no switch at all', (t) async {
      final String id = (await svc.addPerson(mom, 'Nan', CpPersonKind.carer)).value!;
      await _show(t, sharing());
      expect(find.byKey(const Key('sharingNoSync')), findsOneWidget);
      expect(find.textContaining('Sharing between phones is not built yet'), findsWidgets);
      expect(find.byKey(ValueKey<String>('grant-$id-safe')), findsOneWidget);
      expect(find.byKey(ValueKey<String>('grant-$id-health')), findsNothing);
      expect(find.byKey(ValueKey<String>('grant-$id-moods')), findsNothing);
      expect(find.textContaining('Health history and Moods and habits are for parents only'), findsOneWidget);
    });

    testWidgets('adding a person, switching a part on, and "Show as" shows exactly that and no more', (t) async {
      await svc.addEntry(mom, CareProfilePart.safe, 'Peanut allergy', byName: 'Sam');
      await svc.addEntry(mom, CareProfilePart.everyday, 'Oats', byName: 'Sam');
      await svc.unlock(mom, _pinOk, '2580');
      await svc.addEntry(mom, CareProfilePart.health, 'Asthma since 2024');
      await svc.addEntry(mom, CareProfilePart.moods, 'Tired at four');
      svc.lock();
      await _show(t, sharing());
      await t.tap(find.byKey(const Key('addPerson')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('personName')), 'Sitter');
      await t.tap(find.byKey(const Key('personKind')));
      await t.pumpAndSettle();
      await t.tap(find.text('Visit (time-boxed)').last);
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('personSave')));
      await t.pumpAndSettle();
      final String id = (await svc.read(mom)).people.single.id;
      expect(find.textContaining('Shown until'), findsWidgets, reason: 'a visit starts time-boxed');
      await t.ensureVisible(find.byKey(ValueKey<String>('showAs-$id')));
      await t.tap(find.byKey(ValueKey<String>('showAs-$id')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('viewAsNote')), findsOneWidget);
      expect(find.text('Peanut allergy'), findsOneWidget);
      expect(find.text('Oats'), findsNothing, reason: 'a visit is not given the everyday part');
      expect(find.textContaining('Asthma'), findsNothing);
      expect(find.textContaining('Tired'), findsNothing);
    });

    testWidgets('after the time box the view is empty', (t) async {
      await svc.addEntry(mom, CareProfilePart.safe, 'Peanut allergy');
      final String id = (await svc.addPerson(mom, 'Sitter', CpPersonKind.visit)).value!;
      clock.t = DateTime(2026, 11, 15, 7);
      await _show(t, CareProfileViewAsScreen(service: svc, plans: plans, principal: mom, personId: id, childName: 'Mia', meds: meds, clock: clock.call));
      expect(find.byKey(const Key('viewAsEmpty')), findsOneWidget);
      expect(find.text('Peanut allergy'), findsNothing);
    });

    testWidgets('a view-only person\'s switches for everyday, heads-up and medicines are disabled', (t) async {
      final String id = (await svc.addPerson(mom, 'Aunt', CpPersonKind.viewOnly)).value!;
      await _show(t, sharing());
      for (final CareProfilePart p in <CareProfilePart>[CareProfilePart.everyday, CareProfilePart.helps, CareProfilePart.heads, CareProfilePart.meds]) {
        final SwitchListTile s = t.widget<SwitchListTile>(find.byKey(ValueKey<String>('grant-$id-${p.name}')));
        expect(s.onChanged, isNull, reason: p.name);
      }
      expect(t.widget<SwitchListTile>(find.byKey(ValueKey<String>('grant-$id-safe'))).onChanged, isNotNull);
    });

    testWidgets('"Show for tonight" is one tap', (t) async {
      final String id = (await svc.addPerson(mom, 'Aunt', CpPersonKind.helperPage)).value!;
      await _show(t, sharing());
      await t.ensureVisible(find.byKey(ValueKey<String>('tonight-$id')));
      await t.tap(find.byKey(ValueKey<String>('tonight-$id')));
      await t.pumpAndSettle();
      final CpPerson p = (await svc.read(mom)).people.single;
      expect(cpCanSee(p, CareProfilePart.safe, clock.t), isTrue);
      expect(cpCanSee(p, CareProfilePart.safe, DateTime(2026, 11, 15, 7)), isFalse);
    });
  });

  group("a doctor's plan photo", () {
    testWidgets('a photo the grown-up chose is kept under the label they typed, and can be removed', (t) async {
      await _show(t, CareProfilePlansScreen(plans: plans, principal: mom, byName: 'Sam', photoSource: () async => _jpeg()));
      expect(find.byKey(const Key('plansEmpty')), findsOneWidget);
      await t.tap(find.byKey(const Key('addPlan')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('planLabel')), 'Asthma plan');
      await t.tap(find.byKey(const Key('planChoose')));
      await t.pumpAndSettle();
      expect(find.text('Asthma plan'), findsOneWidget);
      expect((await plans.list(mom)).single.byName, 'Sam');
      await t.ensureVisible(find.byKey(const ValueKey<String>('removePlan-ph1')));
      await t.tap(find.byKey(const ValueKey<String>('removePlan-ph1')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('confirmGo')));
      await t.pumpAndSettle();
      expect(await plans.list(mom), isEmpty);
    });

    testWidgets('nothing is added if no photo is chosen, and a file that is not a photo is refused in plain words', (t) async {
      Uint8List? next;
      await _show(t, CareProfilePlansScreen(plans: plans, principal: mom, photoSource: () async => next));
      await t.tap(find.byKey(const Key('addPlan')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('planLabel')), 'Plan');
      await t.tap(find.byKey(const Key('planChoose')));
      await t.pumpAndSettle();
      expect(await plans.list(mom), isEmpty);
      next = Uint8List.fromList(<int>[1, 2, 3, 4, 5, 6, 7, 8, 9]);
      await t.tap(find.byKey(const Key('addPlan')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('planLabel')), 'Plan');
      await t.tap(find.byKey(const Key('planChoose')));
      await t.pumpAndSettle();
      expect(find.textContaining('not a photo this phone can keep'), findsOneWidget);
      expect(await plans.list(mom), isEmpty);
    });

    testWidgets('a person granted Keep-safe is shown the plan in "Show as"; one who is not, is not', (t) async {
      await plans.add(mom, 'Asthma plan', _jpeg());
      final String a = (await svc.addPerson(mom, 'Nan', CpPersonKind.carer)).value!;
      final String b = (await svc.addPerson(mom, 'Aunt', CpPersonKind.helperPage)).value!;
      await svc.addEntry(mom, CareProfilePart.safe, 'Peanut allergy');
      await _show(t, CareProfileViewAsScreen(service: svc, plans: plans, principal: mom, personId: a, childName: 'Mia', clock: clock.call));
      expect(find.byKey(const ValueKey<String>('plan-ph1')), findsOneWidget);
      await _show(t, CareProfileViewAsScreen(service: svc, plans: plans, principal: mom, personId: b, childName: 'Mia', clock: clock.call));
      expect(find.byKey(const ValueKey<String>('plan-ph1')), findsNothing);
    });
  });

  group('the doctor sheet', () {
    Widget sheet({Future<bool> Function(String)? pin = _pinOk}) => CareProfileSheetScreen(
          service: svc, plans: plans, principal: mom, childName: 'Mia', meds: meds, emergency: card, verifyPin: pin, clock: clock.call);

    String sheetText(WidgetTester t) => t.widget<SelectableText>(find.descendant(of: find.byKey(const Key('doctorSheet')), matching: find.byType(SelectableText))).data!;

    testWidgets('is built from what was written, with who wrote it; the locked parts stay off until the PIN', (t) async {
      meds = CareService.memory(childScope: 'ivy', clock: clock.call);
      card = EmergencyCardService.memory(clock: clock.call);
      await svc.addEntry(mom, CareProfilePart.safe, 'Peanuts: hives', title: 'Allergy', byName: 'Sam');
      await svc.unlock(mom, _pinOk, '2580');
      await svc.addEntry(mom, CareProfilePart.health, 'Asthma since 2024');
      svc.lock();
      await meds.addMedication(mom, const CareMedication(id: '', name: 'Inhaler', dose: '2 puffs', kind: MedKind.prn, gapHours: 4));
      await card.save(mom, const LocalEmergencyCard(allergies: <String>['Peanuts'], doctor: EcDoctor(name: 'Dr Okoye')), expectedVersion: 0);
      await plans.add(mom, 'Asthma plan', _jpeg());
      await _show(t, sheet());
      final String text = sheetText(t);
      expect(text, contains('Mia: sheet for the doctor'));
      expect(text, contains('written by Sam, 14 Nov 2026'));
      expect(text, contains('Inhaler | 2 puffs'));
      expect(text, contains('Dr Okoye'));
      expect(text, contains('Asthma plan'));
      expect(text, isNot(contains('Asthma since')));
      await t.ensureVisible(find.byKey(const Key('optHealth')));
      await t.tap(find.byKey(const Key('optHealth')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('profilePinField')), findsOneWidget);
      await t.enterText(find.byKey(const Key('profilePinField')), '2580');
      await t.tap(find.byKey(const Key('profilePinOk')));
      await t.pumpAndSettle();
      expect(sheetText(t), contains('Asthma since 2024'));
    });

    testWidgets('a wrong PIN leaves the health history off the sheet', (t) async {
      await svc.unlock(mom, _pinOk, '2580');
      await svc.addEntry(mom, CareProfilePart.health, 'Asthma since 2024');
      svc.lock();
      await _show(t, sheet());
      await t.ensureVisible(find.byKey(const Key('optHealth')));
      await t.tap(find.byKey(const Key('optHealth')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('profilePinField')), '1111');
      await t.tap(find.byKey(const Key('profilePinOk')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('profilePinCancel')));
      await t.pumpAndSettle();
      expect(sheetText(t), isNot(contains('Asthma since')));
    });

    testWidgets('copies to the clipboard and says nothing is sent', (t) async {
      await _show(t, sheet());
      expect(find.textContaining('nothing is sent from here'), findsOneWidget);
      expect(find.byKey(const Key('copySheet')), findsOneWidget);
    });
  });

  group('posture', () {
    for (final double w in <double>[344, 390, 600, 800]) {
      testWidgets('every screen fits at $w dp and 2.0x text', (t) async {
        await svc.addEntry(mom, CareProfilePart.everyday, 'A long line of care text that wraps across several lines on a narrow phone at twice the size', title: 'Bedtime and the routine that comes before it', byName: 'Samantha-Jane Okonkwo');
        final String a = (await svc.addPerson(mom, 'A person with a rather long name', CpPersonKind.visit)).value!;
        await svc.setHeads(mom, 'Slept badly, extra patience and a quiet afternoon please');
        final List<Widget> screens = <Widget>[
          hub(age: 14),
          part(CareProfilePart.everyday),
          CareProfileSharingScreen(service: svc, plans: plans, principal: mom, childName: 'Mia', clock: clock.call),
          CareProfileViewAsScreen(service: svc, plans: plans, principal: mom, personId: a, childName: 'Mia', clock: clock.call),
          CareProfilePlansScreen(plans: plans, principal: mom, photoSource: () async => null),
          CareProfileSheetScreen(service: svc, plans: plans, principal: mom, childName: 'Mia', clock: clock.call),
        ];
        for (final Widget s in screens) {
          await _show(t, s, width: w, scale: 2.0);
          expect(t.takeException(), isNull, reason: '${s.runtimeType} at $w');
        }
      });
    }
  });
}
