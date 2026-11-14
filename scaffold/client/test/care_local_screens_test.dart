// OLIVE BRANCH — the care and coordination screens on this device. Each one is driven the way a
// grown-up would: type, tap, confirm. The deny paths come first: a child sees one neutral line and no
// record is read; a second dose names who and when; nobody answers their own expense; a handover note
// needs the "can never be changed" confirm and there is no edit or delete anywhere. Posture: the
// screens hold at 344, 390, 600 and 800 dp at 2.0x text with nothing overflowing.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/care_local.dart';
import 'package:olive_client/care_local_screens.dart';
import 'package:olive_client/care_screens.dart';
import 'package:olive_client/court_export.dart' show LogEntry;
import 'package:olive_client/emergency_card_editor_screen.dart';
import 'package:olive_client/emergency_card_local.dart';
import 'package:olive_client/family_structure_logic.dart' show FamilyPrincipal;
import 'package:olive_client/growing_care_store.dart';

const FamilyPrincipal mom = FamilyPrincipal(roleName: 'guardian', userId: 'mom');
const FamilyPrincipal dad = FamilyPrincipal(roleName: 'guardian', userId: 'dad');
const FamilyPrincipal kid = FamilyPrincipal(roleName: 'child', userId: 'ivy', childId: 'ivy');

class Clock {
  Clock(this.t);
  DateTime t;
  DateTime call() => t;
  void add(Duration d) => t = t.add(d);
}

CareService svc(Clock c, {int guardians = 1}) =>
    CareService.memory(childScope: 'ivy', guardianCount: guardians, clock: c.call);

Future<void> show(WidgetTester t, Widget w, {Size size = const Size(700, 3000), double text = 1.0}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(MaterialApp(
      builder: (BuildContext c, Widget? child) =>
          MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(text)), child: child!),
      home: w));
  await t.pumpAndSettle();
}

Future<void> type(WidgetTester t, String key, String text) async {
  await t.ensureVisible(find.byKey(Key(key)));
  await t.enterText(find.byKey(Key(key)), text);
  await t.pump();
}

Future<void> tap(WidgetTester t, String key) async {
  await t.ensureVisible(find.byKey(Key(key)));
  await t.tap(find.byKey(Key(key)));
  await t.pumpAndSettle();
}

void main() {
  group('a child, or nobody, gets one neutral line and nothing is read (P6)', () {
    for (final FamilyPrincipal? p in <FamilyPrincipal?>[kid, null]) {
      testWidgets('principal ${p?.roleName}', (t) async {
        final CareService s = svc(Clock(DateTime(2026, 11, 13, 9)));
        await s.appendNote(mom, 'secret note');
        await s.proposeExpense(mom, 'Secret expense', '12');
        for (final Widget w in <Widget>[
          CareHubScreen(service: s, principal: p),
          LocalMedsScreen(service: s, principal: p),
          LocalExpensesScreen(service: s, principal: p),
          LocalHandoverScreen(service: s, principal: p),
        ]) {
          await show(t, w);
          expect(find.byKey(const Key('careNotForYou')), findsOneWidget);
          expect(find.textContaining('secret', findRichText: true), findsNothing);
          expect(find.textContaining('Secret'), findsNothing);
          expect(find.textContaining(r'$'), findsNothing);
        }
      });
    }

    test('no child-facing file mentions the care screens or the care records', () {
      final List<String> files = Directory('lib')
          .listSync()
          .whereType<File>()
          .map((File f) => f.path)
          .where((String p) =>
              RegExp(r'(child_home|child_more|kiosk_shell|inbox_screen|receipt_screen|journal_screen|letters_screen)')
                  .hasMatch(p))
          .toList();
      expect(files, isNotEmpty);
      for (final String f in files) {
        final String src = File(f).readAsStringSync().replaceAll(RegExp(r'//.*'), '');
        for (final String bad in <String>['care_local', 'LocalExpensesScreen', 'LocalMedsScreen', 'LocalHandoverScreen']) {
          expect(src.contains(bad), isFalse, reason: '$f mentions $bad');
        }
      }
    });
  });

  group('the hub', () {
    testWidgets('lists the care and coordination rows with live subtitles', (t) async {
      final Clock c = Clock(DateTime(2026, 11, 13, 9));
      final CareService s = svc(c);
      await s.addMedication(mom, const CareMedication(id: '', name: 'Vitamin D', slots: <String>['08:00']));
      await s.appendNote(mom, 'one');
      await s.appendNote(mom, 'two');
      await s.proposeExpense(mom, 'Shoes', '30');
      await show(t, CareHubScreen(service: s, principal: mom, childName: 'Ivy', clock: c.call, emergencyVersion: () async => 3));
      for (final String k in <String>[
        'careRowCard', 'careRowHospital', 'careRowMeds', 'careRowBag', 'careRowBinder', 'careRowAppt',
        'careRowHandover', 'careRowSchedule', 'careRowSwap', 'careRowExpenses', 'careRowOverlap',
      ]) {
        expect(find.byKey(Key(k)), findsOneWidget, reason: k);
      }
      expect(find.text('1 due now'), findsOneWidget);
      expect(find.text('2 in the log. Never deletable'), findsOneWidget);
      expect(find.text('1 waiting for you'), findsOneWidget);
      expect(find.textContaining('Version 3'), findsOneWidget);
      expect(find.textContaining("never shown on Ivy's device", skipOffstage: false), findsNothing);
      expect(find.textContaining("Nothing here is ever shown on Ivy's device"), findsOneWidget);
    });

    testWidgets('swap a night is an honest later card and saves nothing', (t) async {
      final CareService s = svc(Clock(DateTime(2026, 11, 13, 9)));
      await show(t, CareHubScreen(service: s, principal: mom));
      expect(find.textContaining('Later'), findsWidgets);
      await tap(t, 'careRowSwap');
      expect(find.byKey(const Key('swapLaterBanner')), findsOneWidget);
      expect(find.textContaining('nothing can be asked or saved here'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('a row whose screen is elsewhere says so rather than opening nothing', (t) async {
      final CareService s = svc(Clock(DateTime(2026, 11, 13, 9)));
      await show(t, CareHubScreen(service: s, principal: mom));
      await tap(t, 'careRowBag');
      expect(find.textContaining('not available here'), findsOneWidget);
    });
  });

  group('medicines', () {
    testWidgets('add a medicine, see it due, log a dose, and a second attempt names who and when', (t) async {
      final Clock c = Clock(DateTime(2026, 11, 13, 8, 10));
      final CareService s = svc(c);
      await show(t, LocalMedsScreen(service: s, principal: mom, byName: 'Mom', clock: c.call));
      expect(find.byKey(const Key('medsEmpty')), findsOneWidget);
      expect(find.textContaining('not medical advice'), findsOneWidget);
      await tap(t, 'addMedicineLocal');
      await type(t, 'medFormName', 'Vitamin D');
      await type(t, 'medFormDose', '1 drop');
      await type(t, 'medFormT1', '08:00');
      await tap(t, 'saveMedicine');
      expect(find.text('Vitamin D, 1 drop'), findsOneWidget);
      expect(find.text('Due'), findsOneWidget);
      expect(find.text('Due since 8:00 AM'), findsOneWidget);
      // Open it and log a dose.
      await t.tap(find.text('Vitamin D, 1 drop'));
      await t.pumpAndSettle();
      await tap(t, 'logDose');
      expect(find.textContaining('Given'), findsWidgets);
      // Again: refused, who and when, nothing logged.
      c.add(const Duration(minutes: 15));
      await tap(t, 'logDose');
      expect(find.byKey(const Key('alreadyGiven')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('alreadyGiven')), matching: find.textContaining('by you')), findsOneWidget);
      expect(find.textContaining('Nothing was logged'), findsOneWidget);
      await tap(t, 'alreadyGivenOk');
      expect((await s.read(mom)).meds.single.doses, hasLength(1));
      // The log is shown and has no edit or delete.
      expect(find.text('Dose log'.toUpperCase()), findsOneWidget);
      expect(find.byIcon(Icons.delete), findsNothing);
      expect(find.textContaining('never edited or deleted'), findsOneWidget);
    });

    testWidgets("someone else's dose is named by their name", (t) async {
      final Clock c = Clock(DateTime(2026, 11, 13, 8, 10));
      final CareService s = svc(c, guardians: 2);
      final String id = (await s.addMedication(mom, const CareMedication(id: '', name: 'Vitamin D', slots: <String>['08:00']))).value!;
      await s.logDose(dad, id, byName: 'Dad');
      c.add(const Duration(minutes: 10));
      await show(t, LocalMedScreen(service: s, principal: mom, medicationId: id, clock: c.call));
      await tap(t, 'logDose');
      expect(find.descendant(of: find.byKey(const Key('alreadyGiven')), matching: find.textContaining('by Dad')), findsOneWidget);
    });

    testWidgets('an as-needed medicine says when the next dose is allowed; retire keeps the log', (t) async {
      final Clock c = Clock(DateTime(2026, 11, 13, 14));
      final CareService s = svc(c);
      final String id = (await s.addMedication(mom, const CareMedication(id: '', name: 'Paracetamol', kind: MedKind.prn, gapHours: 4))).value!;
      await show(t, LocalMedScreen(service: s, principal: mom, medicationId: id, clock: c.call));
      await tap(t, 'logDose');
      expect(find.textContaining('Next allowed 6:00 PM'), findsOneWidget);
      c.add(const Duration(hours: 1));
      await tap(t, 'logDose');
      expect(find.textContaining('The next dose is allowed from 6:00 PM'), findsOneWidget);
      await tap(t, 'alreadyGivenOk');
      await tap(t, 'retireMedicine');
      await tap(t, 'confirmRetire');
      final CareMedication m = (await s.read(mom)).meds.single;
      expect(m.retired, isTrue);
      expect(m.doses, hasLength(1));
    });

    testWidgets('a form with no name or no time says so in words', (t) async {
      final CareService s = svc(Clock(DateTime(2026, 11, 13, 9)));
      await show(t, LocalMedScreen(service: s, principal: mom));
      await tap(t, 'saveMedicine');
      expect(find.text('A name is needed.'), findsOneWidget);
      await type(t, 'medFormName', 'X');
      await tap(t, 'saveMedicine');
      expect(find.text('Add at least one time.'), findsOneWidget);
      await type(t, 'medFormT1', '8am');
      await tap(t, 'saveMedicine');
      expect(find.text('That time is not valid.'), findsOneWidget);
      expect((await s.read(mom)).meds, isEmpty);
    });

    testWidgets('retired medicines are listed apart, with their doses kept', (t) async {
      final Clock c = Clock(DateTime(2026, 11, 13, 9));
      final CareService s = svc(c);
      final String id = (await s.addMedication(mom, const CareMedication(id: '', name: 'Old', slots: <String>['08:00']))).value!;
      await s.logDose(mom, id);
      await s.retireMedication(mom, id);
      await show(t, LocalMedsScreen(service: s, principal: mom, clock: c.call));
      expect(find.text('RETIRED'), findsOneWidget);
      expect(find.text('Retired. 1 dose kept'), findsOneWidget);
    });
  });

  group('expenses', () {
    testWidgets('a sole guardian proposes, accepts their own (marked), then marks it reimbursed', (t) async {
      final Clock c = Clock(DateTime(2026, 11, 13, 10));
      final CareService s = svc(c);
      await show(t, LocalExpensesScreen(service: s, principal: mom, byName: 'Mom', childName: 'Ivy'));
      expect(find.textContaining("never moves money"), findsOneWidget);
      expect(find.textContaining("Ivy can't see any of this"), findsOneWidget);
      await tap(t, 'proposeExpense');
      expect(find.text('Say what it was for.'), findsOneWidget);
      await type(t, 'expenseTitle', 'School shoes');
      await type(t, 'expenseAmount', '48.00');
      await tap(t, 'proposeExpense');
      expect(find.text('Waiting for you to accept it'), findsOneWidget);
      expect(find.textContaining('You are the only grown-up on this device'), findsOneWidget);
      // A sole guardian never gets a Dispute button on their own expense.
      expect(find.widgetWithText(OutlinedButton, 'Dispute'), findsNothing);
      final String id = (await s.read(mom)).expenses.single.id;
      await tap(t, 'accept-$id');
      expect(find.text('Accepted by you, as the only grown-up here'), findsOneWidget);
      expect(find.byKey(const Key('expenseBalance')), findsOneWidget);
      expect(find.text(r'$48.00'), findsOneWidget, reason: 'the recorded total, not a debt');
      await tap(t, 'reimburse-$id');
      expect(find.text('Reimbursed'), findsWidgets);
      expect(find.text(r'$0.00'), findsOneWidget);
      expect(find.byKey(ValueKey<String>('accept-$id')), findsNothing);
    });

    testWidgets('two guardians: no accept or dispute on your own; the other guardian disputes with a reason', (t) async {
      final Clock c = Clock(DateTime(2026, 11, 13, 10));
      final CareService s = svc(c, guardians: 2);
      final String id = (await s.proposeExpense(mom, 'Soccer cleats', '60', byName: 'Mom')).value!;
      await show(t, LocalExpensesScreen(service: s, principal: mom, guardianCount: 2));
      expect(find.text('Waiting for the other grown-up'), findsOneWidget);
      expect(find.byKey(ValueKey<String>('accept-$id')), findsNothing);
      expect(find.byKey(ValueKey<String>('dispute-$id')), findsNothing);
      expect(find.textContaining("The other grown-up decides. You can't accept your own."), findsOneWidget);
      // Dad's screen over the same records.
      await show(t, LocalExpensesScreen(service: s, principal: dad, byName: 'Dad', guardianCount: 2));
      expect(find.text('Waiting for you'), findsOneWidget);
      await tap(t, 'dispute-$id');
      await tap(t, 'sendDispute-$id');
      expect(find.text('Say briefly why.'), findsOneWidget);
      await type(t, 'disputeReason', 'Wrong size');
      await tap(t, 'sendDispute-$id');
      expect(find.text('Disputed: Wrong size'), findsOneWidget);
      // Disputed can still be accepted after all.
      expect(find.text('Accept after all'), findsOneWidget);
      await tap(t, 'accept-$id');
      expect(find.text('Accepted'), findsWidgets);
      expect(find.textContaining('You owe the other grown-up'), findsOneWidget);
    });

    testWidgets('a bad amount is refused in words and nothing is recorded', (t) async {
      final CareService s = svc(Clock(DateTime(2026, 11, 13, 10)));
      await show(t, LocalExpensesScreen(service: s, principal: mom));
      await type(t, 'expenseTitle', 'Shoes');
      await type(t, 'expenseAmount', 'lots');
      await tap(t, 'proposeExpense');
      expect(find.text('That amount looks wrong.'), findsOneWidget);
      expect((await s.read(mom)).expenses, isEmpty);
    });
  });

  group('handover log', () {
    testWidgets('a note needs the "can never be changed" confirm, then shows its fingerprint and the intact chain', (t) async {
      final Clock c = Clock(DateTime(2026, 11, 13, 18, 30));
      final CareService s = svc(c);
      await show(t, LocalHandoverScreen(service: s, principal: mom, byName: 'Mom', childName: 'Ivy'));
      expect(find.textContaining('can never be edited or deleted'), findsOneWidget);
      expect(find.text('Intact, 0 notes'), findsOneWidget);
      await tap(t, 'noteReview');
      expect(find.text('Write something first.'), findsOneWidget);
      await type(t, 'noteField', 'Ivy had a late snack. Blue bunny is in her bag.');
      await tap(t, 'noteReview');
      expect(find.byKey(const Key('noteConfirm')), findsOneWidget);
      expect(find.text('This can never be changed'), findsOneWidget);
      // Keep editing: nothing was added.
      await tap(t, 'noteKeepEditing');
      expect((await s.read(mom)).notes, isEmpty);
      await tap(t, 'noteReview');
      await tap(t, 'noteSendForGood');
      expect(find.textContaining('#1. Ivy had a late snack.'), findsOneWidget);
      expect(find.text('Intact, 1 note'), findsOneWidget);
      final CareDoc d = await s.read(mom);
      final String h = d.notes.single.hash;
      expect(find.text('${h.substring(0, 12)} after ${'0' * 8}'), findsOneWidget);
      expect(find.byKey(const Key('noteSyncLater')), findsOneWidget);
      expect(find.textContaining('Later'), findsWidgets);
      // No edit or delete controls anywhere on a note.
      expect(find.byIcon(Icons.delete), findsNothing);
      expect(find.textContaining('Delete'), findsNothing);
      expect(find.textContaining('Edit note'), findsNothing);
    });

    testWidgets('add a correction starts a NEW note about the old one, which is untouched', (t) async {
      final Clock c = Clock(DateTime(2026, 11, 13, 18, 30));
      final CareService s = svc(c);
      await s.appendNote(mom, 'Gave her the blue inhaler.', byName: 'Mom');
      c.add(const Duration(minutes: 1));
      await show(t, LocalHandoverScreen(service: s, principal: mom));
      await tap(t, 'correct-1');
      expect(t.widget<TextField>(find.byKey(const Key('noteField'))).controller!.text, 'Correction to note #1: ');
      await type(t, 'noteField', 'Correction to note #1: it was the green one.');
      await tap(t, 'noteReview');
      await tap(t, 'noteSendForGood');
      final CareDoc d = await s.read(mom);
      expect(d.notes, hasLength(2));
      expect(d.notes.first.body, 'Gave her the blue inhaler.');
      expect(find.text('Intact, 2 notes'), findsOneWidget);
    });

    testWidgets('1000 characters is the limit and says so', (t) async {
      final CareService s = svc(Clock(DateTime(2026, 11, 13, 18)));
      await show(t, LocalHandoverScreen(service: s, principal: mom));
      expect(t.widget<TextField>(find.byKey(const Key('noteField'))).maxLength, 1000);
      expect((await s.appendNote(mom, 'x' * 1001)).reason, 'too_long');
    });

    testWidgets('a broken chain is named by the note it breaks at', (t) async {
      final Clock c = Clock(DateTime(2026, 11, 13, 18));
      final MemoryCareRepository repo = MemoryCareRepository();
      final CareService s = CareService(repo, childScope: 'ivy', clock: c.call);
      await s.appendNote(mom, 'one');
      c.add(const Duration(minutes: 1));
      await s.appendNote(mom, 'two');
      // Damage the stored second note directly (nothing in the app can do this).
      final CareDoc d = await s.read(mom);
      final LogEntry n = d.notes[1];
      await repo.save(d.copyWith(notes: <LogEntry>[
        d.notes[0],
        LogEntry(
            seq: n.seq, childId: n.childId, authorId: n.authorId, at: n.at, body: 'rewritten',
            prevHash: n.prevHash, hash: n.hash),
      ]));
      await show(t, LocalHandoverScreen(service: s, principal: mom));
      expect(find.text('Broken at note 2'), findsOneWidget);
    });
  });

  group('her time, your time', () {
    test('the awake overlap is 7 AM to 9 PM each, on my clock', () {
      expect(awakeOverlap(-300, -300), (from: 420, to: 1260));
      // She is three hours ahead of me: her 7 AM is my 4 AM, her 9 PM is my 6 PM.
      expect(awakeOverlap(-300, -480), (from: 420, to: 1080));
      // She is nine hours ahead of me: her 7 AM to 9 PM is my 10 PM to noon next day... overlap is 7 AM to noon.
      expect(awakeOverlap(60, -480), (from: 420, to: 720));
      // Fourteen hours apart the awake days still meet at the end of mine: 5 PM to 9 PM.
      expect(awakeOverlap(0, -840), (from: 1020, to: 1260));
    });

    test('overlapText is plain words', () {
      expect(overlapText((from: 420, to: 1260)), 'Both awake, 7 AM to 9 PM each, from 7 AM to 9 PM your time.');
      expect(overlapText((from: 450, to: 1080)), 'Both awake, 7 AM to 9 PM each, from 7:30 AM to 6 PM your time.');
      expect(overlapText(null), 'No shared waking hours.');
    });

    testWidgets('same zone shows both clocks and the window; another zone says it cannot convert', (t) async {
      final Clock c = Clock(DateTime(2026, 11, 13, 15, 5));
      await show(t, OverlapScreen(childName: 'Ivy', clock: c.call));
      expect(find.byKey(const Key('herClock')), findsOneWidget);
      expect(find.byKey(const Key('myClock')), findsOneWidget);
      expect(find.text('3:05 PM'), findsNWidgets(2));
      expect(find.text('Both awake, 7 AM to 9 PM each, from 7 AM to 9 PM your time.'), findsOneWidget);
      await show(t, OverlapScreen(childName: 'Ivy', sameZone: false, herZoneLabel: 'London', clock: c.call));
      expect(find.textContaining('no zone clock to convert with'), findsOneWidget);
      expect(find.text('London'), findsOneWidget);
    });
  });

  group('hospital mode reads the active medicines from the medicine list', () {
    testWidgets('active ones appear (as needed marked), retired ones do not, a child reads none', (t) async {
      final Clock c = Clock(DateTime(2026, 11, 13, 9));
      final CareService s = svc(c);
      await s.addMedication(mom, const CareMedication(id: '', name: 'Vitamin D', dose: '1 drop', slots: <String>['08:00']));
      await s.addMedication(mom, const CareMedication(id: '', name: 'Inhaler', dose: '2 puffs', kind: MedKind.prn));
      final String old = (await s.addMedication(mom, const CareMedication(id: '', name: 'Retired one', slots: <String>['09:00']))).value!;
      await s.retireMedication(mom, old);
      await show(t, HospitalModeScreen(stores: GrowingCareStores.memory(), medicines: s, principal: mom));
      expect(find.byKey(const Key('hospMedList')), findsOneWidget);
      expect(find.textContaining('Vitamin D  -  1 drop'), findsOneWidget);
      expect(find.textContaining('Inhaler  -  2 puffs (as needed)'), findsOneWidget);
      expect(find.textContaining('Retired one'), findsNothing);
      await t.pumpWidget(const SizedBox());
      await show(t, HospitalModeScreen(stores: GrowingCareStores.memory(), medicines: s, principal: kid));
      expect(find.byKey(const Key('hospMedList')), findsNothing);
    });
  });

  group('emergency card history: restore as a new version', () {
    testWidgets('the button asks, then saves the earlier card as the next version', (t) async {
      final EmergencyCardService s = EmergencyCardService.memory(clock: () => DateTime(2026, 11, 13, 9));
      await s.save(mom, const LocalEmergencyCard(allergies: <String>['Peanuts']), expectedVersion: 0, byName: 'Mom');
      await s.save(mom, const LocalEmergencyCard(allergies: <String>['Peanuts', 'Latex']), expectedVersion: 1);
      await show(t, EmergencyCardHistoryScreen(service: s, principal: mom));
      await tap(t, 'change-2');
      expect(find.byKey(const ValueKey<String>('restore-1')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('restore-0')), findsNothing, reason: 'version 0 was blank');
      await tap(t, 'restore-1');
      expect(find.text('Restore version 1?'), findsOneWidget);
      expect(find.textContaining('saved as version 3'), findsOneWidget);
      await tap(t, 'restoreGo');
      final EmergencyCardDoc d = await s.read(mom);
      expect(d.version, 3);
      expect(d.card!.allergies, <String>['Peanuts']);
      expect(d.history, hasLength(3), reason: 'nothing was deleted');
    });
  });

  group('postures: 344, 390, 600 and 800 dp at 2.0x text, nothing overflows', () {
    const List<double> widths = <double>[344, 390, 600, 800];
    for (final double w in widths) {
      testWidgets('all five screens at ${w.toInt()} dp', (t) async {
        final Clock c = Clock(DateTime(2026, 11, 13, 8, 30));
        final CareService s = svc(c);
        final String medId = (await s.addMedication(mom, const CareMedication(id: '', name: 'Vitamin D', dose: '1 drop', slots: <String>['08:00', '20:00'], note: 'With breakfast'))).value!;
        await s.logDose(mom, medId);
        await s.proposeExpense(mom, 'A rather long expense description for school shoes and socks', '1234.56');
        await s.appendNote(mom, 'A long note ${'about the handover '.padRight(120, 'x')}');
        final Size size = Size(w, 900);
        final List<Widget> screens = <Widget>[
          CareHubScreen(service: s, principal: mom, childName: 'Ivy', clock: c.call, emergencyVersion: () async => 12),
          LocalMedsScreen(service: s, principal: mom, clock: c.call),
          LocalMedScreen(service: s, principal: mom, medicationId: medId, clock: c.call),
          LocalMedScreen(service: s, principal: mom),
          LocalExpensesScreen(service: s, principal: mom, childName: 'Ivy'),
          LocalHandoverScreen(service: s, principal: mom, childName: 'Ivy'),
          OverlapScreen(childName: 'Ivy', clock: c.call),
          const SwapLaterScreen(),
        ];
        for (final Widget screen in screens) {
          await show(t, screen, size: size, text: 2.0);
          expect(t.takeException(), isNull, reason: '${screen.runtimeType} at $w');
        }
      });
    }
  });
}
