// OLIVE BRANCH — the on-device care records: medicines and their dose log, shared expenses, and the
// handover log. The deny paths first: a child (or nobody) reads and writes nothing; a second dose is
// refused with who and when; nobody answers their own expense (except a sole guardian, who is marked);
// the handover chain is the SAME chain the court export verifies, and nothing in it can be edited.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/care_local.dart';
import 'package:olive_client/court_export.dart' show LogEntry, verifyChain;
import 'package:olive_client/emergency_card_local.dart';
import 'package:olive_client/family_structure_logic.dart' show FamilyPrincipal;
import 'package:olive_client/local_services.dart';

const FamilyPrincipal mom = FamilyPrincipal(roleName: 'guardian', userId: 'mom');
const FamilyPrincipal dad = FamilyPrincipal(roleName: 'guardian', userId: 'dad');
const FamilyPrincipal kid = FamilyPrincipal(roleName: 'child', userId: 'ivy', childId: 'ivy');

/// A clock the test moves.
class Clock {
  Clock(this.t);
  DateTime t;
  DateTime call() => t;
  void add(Duration d) => t = t.add(d);
}

CareService svc(Clock c, {int guardians = 1}) =>
    CareService.memory(childScope: 'ivy', guardianCount: guardians, clock: c.call);

CareMedication sched(String name, List<String> slots) =>
    CareMedication(id: '', name: name, dose: '1 tablet', slots: slots);

void main() {
  group('guardian only: nothing is read or written for a child or for nobody', () {
    test('every call is refused with guardian_only', () async {
      final CareService s = svc(Clock(DateTime(2026, 11, 13, 9)));
      for (final FamilyPrincipal? p in <FamilyPrincipal?>[kid, null, const FamilyPrincipal(roleName: 'guardian')]) {
        await expectLater(s.read(p), throwsA(isA<CareLocalRefused>()));
        expect((await s.addMedication(p, sched('X', <String>['08:00']))).reason, 'guardian_only');
        expect((await s.proposeExpense(p, 'Shoes', '10')).reason, 'guardian_only');
        expect((await s.appendNote(p, 'hello')).reason, 'guardian_only');
        expect((await s.logDose(p, 'm1')).reason, 'guardian_only');
      }
      expect((await s.read(mom)).meds, isEmpty);
    });
  });

  group('medicines', () {
    test('add, edit and retire; the dose log survives; a retired medicine takes no dose', () async {
      final Clock c = Clock(DateTime(2026, 11, 13, 9, 5));
      final CareService s = svc(c);
      final String id = (await s.addMedication(mom, sched('Vitamin D', <String>['08:00']), byName: 'Mom')).value!;
      expect((await s.logDose(mom, id)).ok, isTrue);
      expect((await s.editMedication(mom, id, sched('Vitamin D3', <String>['08:00', '20:00']))).ok, isTrue);
      CareMedication m = (await s.read(mom)).meds.single;
      expect(m.name, 'Vitamin D3');
      expect(m.slots, <String>['08:00', '20:00']);
      expect(m.doses, hasLength(1), reason: 'past doses are unchanged by an edit');
      expect((await s.retireMedication(mom, id)).ok, isTrue);
      m = (await s.read(mom)).meds.single;
      expect(m.retired, isTrue);
      expect(m.doses, hasLength(1), reason: 'retiring keeps the dose log');
      expect((await s.logDose(mom, id)).reason, 'retired');
      expect((await s.editMedication(mom, id, sched('Other', <String>['09:00']))).reason, 'retired');
    });

    test('validation: a name, a time that is a time, at least one slot, lengths', () async {
      final CareService s = svc(Clock(DateTime(2026, 11, 13)));
      expect((await s.addMedication(mom, sched('  ', <String>['08:00']))).reason, 'name_needed');
      expect((await s.addMedication(mom, sched('A', <String>[]))).reason, 'slot_needed');
      expect((await s.addMedication(mom, sched('A', <String>['25:00']))).reason, 'bad_time');
      expect((await s.addMedication(mom, sched('A' * 61, <String>['08:00']))).reason, 'too_long');
      final CareResult<String> prn = await s.addMedication(
          mom, const CareMedication(id: '', name: 'Inhaler', kind: MedKind.prn, gapHours: 6));
      expect(prn.ok, isTrue, reason: 'as-needed has no slots');
      expect((await s.read(mom)).meds.single.gapHours, 6);
    });

    test('a scheduled dose can be logged once per slot: the second is refused with who and when, no override',
        () async {
      final Clock c = Clock(DateTime(2026, 11, 13, 8, 10));
      final CareService s = svc(c);
      final String id = (await s.addMedication(mom, sched('Vitamin D', <String>['08:00']))).value!;
      expect(medState((await s.read(mom)).meds.single, c.t).due, isTrue);
      final CareResult<DateTime> first = await s.logDose(mom, id, byName: 'Mom');
      expect(first.ok, isTrue);
      c.add(const Duration(minutes: 20));
      final CareResult<DateTime> again = await s.logDose(dad, id, byName: 'Dad');
      expect(again.ok, isFalse);
      expect(again.reason, 'already_given');
      expect(again.detail!['byId'], 'mom');
      expect(again.detail!['byName'], 'Mom');
      expect((again.detail!['at'] as DateTime).toLocal(), first.value!.toLocal());
      expect((await s.read(mom)).meds.single.doses, hasLength(1), reason: 'nothing was logged on the refusal');
      // The next slot is a new dose.
      c.t = DateTime(2026, 11, 14, 8, 1);
      expect((await s.logDose(dad, id)).ok, isTrue);
    });

    test('an as-needed dose waits for its gap and says when the next is allowed', () async {
      final Clock c = Clock(DateTime(2026, 11, 13, 14));
      final CareService s = svc(c);
      final String id = (await s.addMedication(
              mom, const CareMedication(id: '', name: 'Paracetamol', kind: MedKind.prn, gapHours: 4)))
          .value!;
      expect((await s.logDose(mom, id, byName: 'Mom')).ok, isTrue);
      c.add(const Duration(hours: 3));
      final CareResult<DateTime> r = await s.logDose(mom, id);
      expect(r.reason, 'already_given');
      expect(r.detail!['next'] as DateTime, DateTime(2026, 11, 13, 18));
      c.add(const Duration(hours: 1, minutes: 1));
      expect((await s.logDose(mom, id)).ok, isTrue);
    });

    test('medState: due inside 8 hours, an early dose within 30 minutes counts, next is the next slot', () {
      const CareMedication m = CareMedication(id: 'a', name: 'A', slots: <String>['08:00', '20:00']);
      MedState st = medState(m, DateTime(2026, 11, 13, 7, 0));
      expect(st.due, isFalse);
      expect(st.next, DateTime(2026, 11, 13, 8));
      st = medState(m, DateTime(2026, 11, 13, 9, 0));
      expect(st.due, isTrue);
      expect(st.slot, DateTime(2026, 11, 13, 8));
      st = medState(m, DateTime(2026, 11, 13, 16, 30));
      expect(st.due, isFalse, reason: 'more than 8 hours past the slot with no dose is not "due now"');
      final CareMedication early = CareMedication(id: 'a', name: 'A', slots: const <String>['08:00'], doses: <CareDose>[
        CareDose(at: DateTime(2026, 11, 13, 7, 40).toUtc(), byId: 'mom', byName: 'Mom'),
      ]);
      expect(medState(early, DateTime(2026, 11, 13, 8, 5)).given, isTrue);
    });

    test('round trip through JSON keeps the dose log and the remembered names', () async {
      final Clock c = Clock(DateTime(2026, 11, 13, 8, 10));
      final CareService s = svc(c);
      final String id = (await s.addMedication(mom, sched('Vitamin D', <String>['08:00']), byName: 'Mom')).value!;
      await s.logDose(mom, id);
      final CareDoc d = await s.read(mom);
      final CareDoc back = CareDoc.fromJson(jsonDecode(jsonEncode(d.toJson())));
      expect(back.meds.single.doses.single.byName, 'Mom');
      expect(back.names['mom'], 'Mom');
    });
  });

  group('expenses (the server rules, PR #174)', () {
    test('parseCents and formatCents', () {
      expect(parseCents('48'), 4800);
      expect(parseCents(r'$48.5'), 4850);
      expect(parseCents('1,200.25'), 120025);
      expect(parseCents('0'), isNull);
      expect(parseCents('-3'), isNull);
      expect(parseCents('4.999'), isNull);
      expect(parseCents('abc'), isNull);
      expect(formatCents(4805), r'$48.05');
    });

    test('propose needs a reason for being and a sane amount', () async {
      final CareService s = svc(Clock(DateTime(2026, 11, 13)));
      expect((await s.proposeExpense(mom, ' ', '10')).reason, 'description_needed');
      expect((await s.proposeExpense(mom, 'Shoes', '0')).reason, 'bad_amount');
      expect((await s.proposeExpense(mom, 'Shoes', '10001')).reason, 'bad_amount');
      expect((await s.proposeExpense(mom, 'S' * 81, '10')).reason, 'too_long');
      expect((await s.proposeExpense(mom, 'Shoes', '48.00')).ok, isTrue);
    });

    test('two guardians: the proposer cannot accept or dispute their own; the other can', () async {
      final Clock c = Clock(DateTime(2026, 11, 13, 10));
      final CareService s = svc(c, guardians: 2);
      final String id = (await s.proposeExpense(mom, 'School shoes', '48.00', byName: 'Mom')).value!;
      expect((await s.resolveExpense(mom, id, ExpenseAction.accept)).reason, 'own_expense');
      expect((await s.resolveExpense(mom, id, ExpenseAction.dispute, reason: 'x')).reason, 'own_expense');
      expect((await s.resolveExpense(dad, id, ExpenseAction.dispute)).reason, 'reason_needed');
      expect((await s.resolveExpense(dad, id, ExpenseAction.reimburse)).reason, 'invalid_transition',
          reason: 'reimbursing needs accepted first');
      expect(
          (await s.resolveExpense(dad, id, ExpenseAction.dispute, reason: 'Wrong size, we agreed on the other pair'))
              .ok,
          isTrue);
      CareExpense e = (await s.read(mom)).expenses.single;
      expect(e.status, ExpenseStatus.disputed);
      expect(e.reason, startsWith('Wrong size'));
      // A disputed expense can still be accepted later (owner decision, migration 0045), by the other one only.
      expect((await s.resolveExpense(mom, id, ExpenseAction.accept)).reason, 'own_expense');
      expect((await s.resolveExpense(dad, id, ExpenseAction.accept, byName: 'Dad')).ok, isTrue);
      e = (await s.read(mom)).expenses.single;
      expect(e.status, ExpenseStatus.accepted);
      expect(e.events.map((ExpenseEvent x) => x.selfAccept), everyElement(isFalse),
          reason: 'a two-guardian accept is not a self-accept');
      expect((await s.resolveExpense(dad, id, ExpenseAction.dispute, reason: 'late')).reason, 'invalid_transition');
      expect((await s.resolveExpense(mom, id, ExpenseAction.reimburse)).ok, isTrue);
      e = (await s.read(mom)).expenses.single;
      expect(e.status, ExpenseStatus.reimbursed);
      expect(e.events.map((ExpenseEvent x) => x.to.name).toList(),
          <String>['proposed', 'disputed', 'accepted', 'reimbursed']);
      expect((await s.resolveExpense(dad, id, ExpenseAction.accept)).reason, 'invalid_transition');
    });

    test('a SOLE guardian may accept their own proposal (marked self_accept) but never dispute it', () async {
      final CareService s = svc(Clock(DateTime(2026, 11, 13, 10)));
      final String id = (await s.proposeExpense(mom, 'Piano book', '14.99', byName: 'Mom')).value!;
      expect((await s.resolveExpense(mom, id, ExpenseAction.dispute, reason: 'no')).reason, 'own_expense');
      expect((await s.resolveExpense(mom, id, ExpenseAction.reimburse)).reason, 'invalid_transition');
      expect((await s.resolveExpense(mom, id, ExpenseAction.accept)).ok, isTrue);
      CareExpense e = (await s.read(mom)).expenses.single;
      expect(e.events.map((ExpenseEvent x) => x.selfAccept).toList(), <bool>[false, true],
          reason: 'only the accept carries the marker');
      expect((await s.resolveExpense(mom, id, ExpenseAction.reimburse)).ok, isTrue);
      e = (await s.read(mom)).expenses.single;
      expect(e.events.map((ExpenseEvent x) => x.selfAccept).toList(), <bool>[false, true, false]);
    });

    test('expenseRefusal is the one table: spot checks of every row', () {
      final DateTime t = DateTime(2026, 11, 13);
      CareExpense e(ExpenseStatus st) => CareExpense(
          id: 'x', description: 'd', cents: 100, paidById: 'mom', paidByName: 'Mom', createdAt: t, status: st);
      expect(expenseRefusal(e(ExpenseStatus.proposed), ExpenseAction.accept, 'dad', 2), isNull);
      expect(expenseRefusal(e(ExpenseStatus.proposed), ExpenseAction.accept, 'mom', 1), isNull);
      expect(expenseRefusal(e(ExpenseStatus.proposed), ExpenseAction.accept, 'mom', 2), 'own_expense');
      expect(expenseRefusal(e(ExpenseStatus.accepted), ExpenseAction.accept, 'dad', 2), 'invalid_transition');
      expect(expenseRefusal(e(ExpenseStatus.disputed), ExpenseAction.dispute, 'dad', 2, reason: 'x'),
          'invalid_transition');
      expect(expenseRefusal(e(ExpenseStatus.accepted), ExpenseAction.reimburse, 'anyone', 2), isNull);
      expect(expenseRefusal(e(ExpenseStatus.reimbursed), ExpenseAction.reimburse, 'mom', 2), 'invalid_transition');
    });

    test('the balance counts accepted, not yet reimbursed, half each, from my side', () async {
      final CareService s = svc(Clock(DateTime(2026, 11, 13, 10)), guardians: 2);
      final String a = (await s.proposeExpense(mom, 'A', '100.00')).value!;
      final String b = (await s.proposeExpense(dad, 'B', '40.00')).value!;
      await s.resolveExpense(dad, a, ExpenseAction.accept);
      await s.resolveExpense(mom, b, ExpenseAction.accept);
      final CareDoc d = await s.read(mom);
      expect(expenseBalance(d.expenses, 'mom').owedToMe, 3000, reason: '50.00 owed to her, 20.00 she owes');
      expect(expenseBalance(d.expenses, 'dad').owedToMe, -3000);
      await s.resolveExpense(mom, a, ExpenseAction.reimburse);
      expect(expenseBalance((await s.read(mom)).expenses, 'mom').owedToMe, -2000);
    });
  });

  group('handover log', () {
    test('the chain is the court export chain: it verifies there, framing and all', () async {
      final Clock c = Clock(DateTime(2026, 11, 13, 18, 0, 0, 123));
      final CareService s = svc(c);
      for (int i = 0; i < 3; i++) {
        expect((await s.appendNote(i.isEven ? mom : dad, 'Note number $i', byName: i.isEven ? 'Mom' : 'Dad')).value,
            i + 1);
        c.add(const Duration(minutes: 5));
      }
      final CareDoc d = await s.read(mom);
      expect(verifyChain(d.notes).ok, isTrue);
      expect(d.notes.first.seq, 0);
      expect(d.notes.first.prevHash, '0' * 64);
      expect(d.notes[1].prevHash, d.notes[0].hash);
      expect(d.notes.first.childId, 'ivy');
      expect(RegExp(r'^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z$').hasMatch(d.notes.first.at), isTrue,
          reason: 'millisecond UTC, exactly the writer format the server hashes');
      expect(chainStatus(d.notes).intact, isTrue);
      expect(d.noteAuthors[1], 'Dad');
    });

    test('a changed note is caught and named by its number', () async {
      final Clock c = Clock(DateTime(2026, 11, 13, 18));
      final CareService s = svc(c);
      for (int i = 0; i < 3; i++) {
        await s.appendNote(mom, 'N$i');
        c.add(const Duration(minutes: 1));
      }
      final CareDoc d = await s.read(mom);
      final List<LogEntry> tampered = <LogEntry>[
        d.notes[0],
        LogEntry(
            seq: 1,
            childId: 'ivy',
            authorId: 'mom',
            at: d.notes[1].at,
            body: 'rewritten',
            prevHash: d.notes[1].prevHash,
            hash: d.notes[1].hash),
        d.notes[2],
      ];
      final ChainStatus st = chainStatus(tampered);
      expect(st.intact, isFalse);
      expect(st.brokenAtNumber, 2);
    });

    test('1000 characters at most, empty refused, text kept exactly as written (inner spacing included)', () async {
      final CareService s = svc(Clock(DateTime(2026, 11, 13)));
      expect((await s.appendNote(mom, '   ')).reason, 'text_needed');
      expect((await s.appendNote(mom, 'x' * 1001)).reason, 'too_long');
      expect((await s.appendNote(mom, 'x' * 1000)).ok, isTrue);
      expect((await s.appendNote(mom, 'Two  spaces\nand a line')).ok, isTrue);
      final CareDoc d = CareDoc.fromJson(jsonDecode(jsonEncode((await s.read(mom)).toJson())));
      expect(d.notes.last.body, 'Two  spaces\nand a line');
      expect(chainStatus(d.notes).intact, isTrue, reason: 'a stored chain still verifies after a read');
    });

    test('a correction is just a new note: the old one is untouched', () async {
      final Clock c = Clock(DateTime(2026, 11, 13));
      final CareService s = svc(c);
      await s.appendNote(mom, 'Gave her the blue inhaler.');
      c.add(const Duration(minutes: 2));
      await s.appendNote(mom, '${correctionStarter(1)}It was the green one.');
      final CareDoc d = await s.read(mom);
      expect(d.notes, hasLength(2));
      expect(d.notes.first.body, 'Gave her the blue inhaler.');
      expect(d.notes.last.body, startsWith('Correction to note #1: '));
    });

    test('there is no edit or delete: the service has no such method (source check)', () {
      final String src = File('lib/care_local.dart').readAsStringSync().replaceAll(RegExp(r'//.*'), '');
      for (final String bad in <String>[
        'deleteNote', 'editNote', 'removeNote', 'updateNote', 'deleteDose', 'editDose', 'removeDose',
      ]) {
        expect(src.contains(bad), isFalse, reason: bad);
      }
    });
  });

  group('storage', () {
    test('the sealed area is catalogued, encrypted, and scoped to the child', () {
      final LocalServices ls = LocalServices.memory(childId: 'ivy');
      final LocalDataEntry e = localDataEntry('coordination');
      expect(e.encrypted, isTrue);
      expect(e.scope, LocalScope.child);
      expect(ls.area('coordination').spec.name, 'child.ivy.coordination');
      expect(e.what.toLowerCase(), isNot(contains('score')));
    });

    test('a CareService over LocalServices survives a "restart" (a new service on the same store)', () async {
      final LocalServices ls = LocalServices.memory(childId: 'ivy');
      final Clock c = Clock(DateTime(2026, 11, 13, 9));
      final CareService a = CareService.local(ls, clock: c.call);
      await a.appendNote(mom, 'Kept.');
      await a.proposeExpense(mom, 'Shoes', '30');
      final CareService b = CareService.local(ls, clock: c.call);
      final CareDoc d = await b.read(mom);
      expect(d.notes.single.body, 'Kept.');
      expect(d.expenses.single.cents, 3000);
      expect(chainStatus(d.notes).intact, isTrue);
    });
  });

  group('emergency card: restore an earlier version as a NEW version (history is never rewritten)', () {
    test('restore re-saves an earlier card; versions only move forward', () async {
      final DateTime t = DateTime(2026, 11, 13, 9);
      final EmergencyCardService s = EmergencyCardService.memory(clock: () => t);
      await s.save(mom, const LocalEmergencyCard(allergies: <String>['Peanuts']), expectedVersion: 0, byName: 'Mom');
      await s.save(mom, const LocalEmergencyCard(allergies: <String>['Peanuts', 'Penicillin']), expectedVersion: 1);
      await s.save(mom, const LocalEmergencyCard(allergies: <String>['Peanuts', 'Penicillin', 'Latex']),
          expectedVersion: 2);
      final EcResult r = await s.restore(mom, 1, expectedVersion: 3);
      expect(r.ok, isTrue);
      expect(r.version, 4);
      final EmergencyCardDoc d = await s.read(mom);
      expect(d.card!.allergies, <String>['Peanuts']);
      expect(d.history.map((EcChange c) => c.version).toList(), <int>[1, 2, 3, 4]);
      expect(d.history.last.previous!.allergies, <String>['Peanuts', 'Penicillin', 'Latex'],
          reason: 'the card it replaced is kept');
      // Every version, including the current one, can be restored.
      expect(EmergencyCardService.cardAt(d, 2)!.allergies, <String>['Peanuts', 'Penicillin']);
      expect(EmergencyCardService.cardAt(d, 4)!.allergies, <String>['Peanuts']);
    });

    test('stale, blank and non-guardian restores are refused and change nothing', () async {
      final EmergencyCardService s = EmergencyCardService.memory();
      await s.save(mom, const LocalEmergencyCard(allergies: <String>['A']), expectedVersion: 0);
      await s.save(mom, const LocalEmergencyCard(allergies: <String>['B']), expectedVersion: 1);
      expect((await s.restore(mom, 1, expectedVersion: 1)).reason, 'stale_version');
      expect((await s.restore(mom, 0, expectedVersion: 2)).reason, 'empty', reason: 'version 0 was blank');
      expect((await s.restore(mom, 9, expectedVersion: 2)).reason, 'empty');
      expect((await s.restore(kid, 1, expectedVersion: 2)).reason, 'guardian_only');
      expect((await s.read(mom)).version, 2);
    });
  });
}
