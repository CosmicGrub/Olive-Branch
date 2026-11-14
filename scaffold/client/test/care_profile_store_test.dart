// OLIVE BRANCH — the care profile's stored half: guardian only, the PIN on the locked parts, never a silent
// overwrite, today's heads-up that leaves for good, sharing on one device, the binder copied in without loss,
// the review dates, the sealed photos and the sealed documents. UNVERIFIED until CI runs this file.
// MASTERFILE section 8.24.8.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/care_local.dart';
import 'package:olive_client/care_profile_logic.dart';
import 'package:olive_client/care_profile_store.dart';
import 'package:olive_client/clear_local_data_screen.dart' show kLocalDataAreaNames;
import 'package:olive_client/family_structure_logic.dart';
import 'package:olive_client/growing_care_logic.dart';
import 'package:olive_client/growing_care_store.dart';
import 'package:olive_client/local_services.dart';
import 'package:olive_client/local_store.dart';
import 'package:olive_client/store_cipher.dart';

const FamilyPrincipal mom = FamilyPrincipal(roleName: 'guardian', userId: 'mom');
const FamilyPrincipal dad = FamilyPrincipal(roleName: 'guardian', userId: 'dad');
const FamilyPrincipal kid = FamilyPrincipal(roleName: 'child', userId: 'ivy', childId: 'ivy');

final Uint8List _key = Uint8List.fromList(List<int>.filled(32, 9));
LocalServices _device(MemoryStoreBackend b) =>
    LocalServices(store: LocalStore(backend: b, cipher: AesGcmStoreCipher(_key)), childId: 'ivy', isLive: false, demoSeeds: false);

class Clock {
  Clock(this.t);
  DateTime t;
  DateTime call() => t;
  void add(Duration d) => t = t.add(d);
}

Uint8List _jpeg([int extra = 0]) => Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3, 4, ...List<int>.filled(extra, 7)]);

Future<bool> _pinOk(String pin) async => pin == '2580';

void main() {
  late Clock clock;
  late CareProfileService s;

  setUp(() {
    clock = Clock(DateTime(2026, 11, 14, 9));
    s = CareProfileService.memory(clock: clock.call);
  });

  Future<void> open() async => expect(await s.unlock(mom, _pinOk, '2580'), isTrue);

  group('guardian only', () {
    test('a child and no principal are refused on every call, reads included', () async {
      for (final FamilyPrincipal? p in <FamilyPrincipal?>[kid, null, const FamilyPrincipal(roleName: 'guardian'), const FamilyPrincipal(roleName: 'caregiver', userId: 'nan')]) {
        await expectLater(s.read(p), throwsA(isA<CareProfileRefused>()));
        expect((await s.addEntry(p, CareProfilePart.safe, 'x')).reason, 'guardian_only');
        expect((await s.setHeads(p, 'x')).reason, 'guardian_only');
        expect((await s.addPerson(p, 'Nan', CpPersonKind.carer)).reason, 'guardian_only');
        expect((await s.markReviewed(p, 'fp')).reason, 'guardian_only');
        expect((await s.setTeenPreview(p, true)).reason, 'guardian_only');
        expect((await s.importBinder(p, const <CareSection>[])).reason, 'guardian_only');
        expect(await s.unlock(p, _pinOk, '2580'), isFalse);
      }
      expect((await s.read(mom)).entries, isEmpty, reason: 'nothing was written');
    });

    test('the plan photos too', () async {
      final CarePlanPhotoService ph = CarePlanPhotoService.memory();
      await expectLater(ph.list(kid), throwsA(isA<CareProfileRefused>()));
      expect((await ph.add(kid, 'Plan', _jpeg())).reason, 'guardian_only');
      expect((await ph.add(null, 'Plan', _jpeg())).reason, 'guardian_only');
      expect((await ph.remove(kid, 'ph1')).reason, 'guardian_only');
    });
  });

  group('the PIN on the locked parts', () {
    test('health history and moods are refused until the PIN is right, and a wrong PIN opens nothing', () async {
      expect((await s.addEntry(mom, CareProfilePart.health, 'Asthma')).reason, 'locked');
      expect((await s.addEntry(mom, CareProfilePart.moods, 'Tired at four')).reason, 'locked');
      expect(await s.unlock(mom, _pinOk, '0000'), isFalse);
      expect(await s.unlock(mom, null, '2580'), isFalse, reason: 'no PIN on this device keeps it closed');
      expect(s.isUnlocked, isFalse);
      expect((await s.addEntry(mom, CareProfilePart.health, 'Asthma')).reason, 'locked');
    });

    test('with the PIN they work; a read before the PIN does not contain them; locking closes them again', () async {
      await open();
      expect((await s.addEntry(mom, CareProfilePart.health, 'Asthma since 2024', title: 'Diagnosis')).ok, isTrue);
      expect((await s.addEntry(mom, CareProfilePart.safe, 'Peanut allergy')).ok, isTrue);
      expect((await s.read(mom)).entries, hasLength(2));
      s.lock();
      final CareProfileDoc locked = await s.read(mom);
      expect(locked.entries.map((CpEntry e) => e.part), <CareProfilePart>[CareProfilePart.safe]);
      expect(jsonEncode(locked.toJson()), isNot(contains('Asthma')));
    });

    test('an entry in a locked part cannot be changed, put away or settled while closed', () async {
      await open();
      final String id = (await s.addEntry(mom, CareProfilePart.moods, 'Tired at four')).value!;
      s.lock();
      expect((await s.editEntry(mom, id, 'x')).reason, 'locked');
      expect((await s.putAway(mom, id)).reason, 'locked');
      expect((await s.settle(mom, id)).reason, 'locked');
    });

    test('it closes by itself after five quiet minutes, and use keeps it open', () async {
      await open();
      clock.add(const Duration(minutes: 4));
      expect(s.isUnlocked, isTrue);
      await s.addEntry(mom, CareProfilePart.moods, 'a');
      clock.add(const Duration(minutes: 4));
      expect(s.isUnlocked, isTrue, reason: 'writing slid the window');
      clock.add(const Duration(minutes: 6));
      expect(s.isUnlocked, isFalse);
      expect((await s.addEntry(mom, CareProfilePart.moods, 'b')).reason, 'locked');
    });
  });

  group('entries', () {
    test('a plain entry carries who wrote it and when, and nothing the grown-up did not write', () async {
      final CareResult<String> r = await s.addEntry(mom, CareProfilePart.safe, '  Peanuts: hives  ', title: 'Allergy', byName: 'Sam');
      expect(r.ok, isTrue);
      final CpEntry e = (await s.read(mom)).entries.single;
      expect(e.text, 'Peanuts: hives');
      expect(e.byName, 'Sam');
      expect(cpWrittenBy(e), 'written by Sam, 14 Nov 2026');
    });

    test('empty, over-long and over-full are refused with the document untouched', () async {
      expect((await s.addEntry(mom, CareProfilePart.safe, '   ')).reason, 'text_needed');
      expect((await s.addEntry(mom, CareProfilePart.safe, 'x' * (cpMaxTextChars + 1))).reason, 'too_long');
      expect((await s.addEntry(mom, CareProfilePart.safe, 'x', title: 't' * (cpMaxTitleChars + 1))).reason, 'too_long');
      expect((await s.addEntry(mom, CareProfilePart.heads, 'x')).reason, 'not_found', reason: 'heads is not an entry part');
      for (int i = 0; i < cpMaxEntries; i++) {
        expect((await s.addEntry(mom, CareProfilePart.safe, 'e$i')).ok, isTrue);
      }
      expect((await s.addEntry(mom, CareProfilePart.safe, 'one more')).reason, 'too_many');
      expect((await s.read(mom)).entries, hasLength(cpMaxEntries));
    });

    test('the tone guard refuses what accuses or labels, before anything is written', () async {
      final CareResult<String> r = await s.addEntry(mom, CareProfilePart.helps, 'She is in a bad mood and obviously it is your fault');
      expect(r.reason, 'tone');
      expect(r.detail!['found'], containsAll(<String>['bad mood', 'obviously']));
      expect((await s.addEntry(mom, CareProfilePart.everyday, 'You never remember her bag')).reason, 'tone');
      await open();
      expect((await s.addEntry(mom, CareProfilePart.moods, 'Naughty after school')).reason, 'tone');
      expect((await s.read(mom)).entries, isEmpty);
      expect((await s.addEntry(mom, CareProfilePart.helps, 'Needs quiet after school')).ok, isTrue);
    });

    test('the tone guard runs on an edit too, and leaves the old words', () async {
      final String id = (await s.addEntry(mom, CareProfilePart.helps, 'Needs quiet')).value!;
      expect((await s.editEntry(mom, id, 'Needs quiet, and she is manipulative')).reason, 'tone');
      expect((await s.read(mom)).entries.single.text, 'Needs quiet');
    });

    test('changing your own entry keeps what it said before, with who and when; the history is short', () async {
      final String id = (await s.addEntry(mom, CareProfilePart.everyday, 'Bed at 7', title: 'Bedtime', byName: 'Sam')).value!;
      for (int i = 1; i <= cpMaxRevisions + 3; i++) {
        clock.add(const Duration(days: 1));
        expect((await s.editEntry(mom, id, 'Bed at 7:$i', byName: 'Sam')).ok, isTrue);
      }
      final CpEntry e = (await s.read(mom)).entries.single;
      expect(e.text, 'Bed at 7:${cpMaxRevisions + 3}');
      expect(e.revisions, hasLength(cpMaxRevisions), reason: 'short on purpose');
      expect(e.revisions.last.text, 'Bed at 7:${cpMaxRevisions + 2}');
      expect(e.revisions.last.byName, 'Sam');
      // Not an evidence log: no chain, no hash, no export reference in the stored form.
      final String raw = jsonEncode(e.toJson());
      expect(raw.contains('hash') || raw.contains('prev'), isFalse);
    });

    test('someone else\'s entry cannot be overwritten or put away: add your own version instead', () async {
      final String id = (await s.addEntry(mom, CareProfilePart.everyday, 'Bed at 7:30', title: 'Bedtime', byName: 'Sam')).value!;
      expect((await s.editEntry(dad, id, 'Bed at 8')).reason, 'not_yours');
      expect((await s.putAway(dad, id)).reason, 'not_yours');
      expect((await s.read(dad)).entries.single.text, 'Bed at 7:30');
    });

    test('both versions show until one is chosen; choosing puts the other away and it can come back', () async {
      final String a = (await s.addEntry(mom, CareProfilePart.everyday, 'Bed at 7:30', title: 'Bedtime', byName: 'Sam')).value!;
      final String b = (await s.addMyVersion(dad, a, 'Bed at 8', byName: 'Alex')).value!;
      CareProfileDoc d = await s.read(mom);
      final List<List<CpEntry>> g = cpDisagreements(d, CareProfilePart.everyday);
      expect(g.single.map((CpEntry e) => e.byName).toSet(), <String>{'Sam', 'Alex'});
      expect((await s.settle(mom, a)).value, 1);
      d = await s.read(mom);
      expect(cpDisagreements(d, CareProfilePart.everyday), isEmpty);
      expect(cpEntriesOf(d, CareProfilePart.everyday).single.id, a);
      expect(cpEntriesOf(d, CareProfilePart.everyday, retired: true).single.id, b, reason: 'kept, not deleted');
      expect((await s.bringBack(mom, b)).ok, isTrue);
      expect(cpDisagreements(await s.read(mom), CareProfilePart.everyday), hasLength(1));
    });

    test('a version needs a title to sit beside, and settling something not in dispute is refused', () async {
      final String a = (await s.addEntry(mom, CareProfilePart.everyday, 'Oats')).value!;
      expect((await s.addMyVersion(dad, a, 'Toast')).reason, 'name_needed');
      expect((await s.settle(mom, a)).reason, 'not_found');
    });

    test('putting away your own entry removes it from views but not from the document', () async {
      final String id = (await s.addEntry(mom, CareProfilePart.safe, 'Old plan')).value!;
      expect((await s.putAway(mom, id)).ok, isTrue);
      final CareProfileDoc d = await s.read(mom);
      expect(cpEntriesOf(d, CareProfilePart.safe), isEmpty);
      expect(cpEntriesOf(d, CareProfilePart.safe, retired: true), hasLength(1));
    });
  });

  group("today's heads-up", () {
    test('is for today only: visible today, gone the next day, and removed from the stored file for good', () async {
      final MemoryStoreBackend disk = MemoryStoreBackend();
      final CareProfileService a = CareProfileService.local(_device(disk), clock: clock.call);
      expect((await a.setHeads(mom, 'Slept badly, extra patience', byName: 'Sam')).ok, isTrue);
      expect(cpHeadsToday(await a.read(mom), clock.t)!.text, 'Slept badly, extra patience');
      clock.t = DateTime(2026, 11, 14, 23, 59);
      expect(cpHeadsToday(await a.read(mom), clock.t), isNotNull);
      clock.t = DateTime(2026, 11, 15, 0, 1);
      final CareProfileDoc next = await a.read(mom);
      expect(next.heads, isNull);
      final LocalNamespace ns = _device(disk).area('aboutchild');
      expect(jsonEncode(await ns.get('doc')), isNot(contains('Slept badly')), reason: 'purged, not hidden');
    });

    test('is never kept as a log: rewriting replaces it, and no earlier text survives anywhere in the file', () async {
      final MemoryStoreBackend disk = MemoryStoreBackend();
      final LocalServices dev = _device(disk);
      final CareProfileService a = CareProfileService.local(dev, clock: clock.call);
      await a.setHeads(mom, 'First words about today');
      clock.add(const Duration(hours: 2));
      await a.setHeads(mom, 'Second words about today');
      final String stored = jsonEncode(await dev.area('aboutchild').get('doc'));
      expect(stored, contains('Second words'));
      expect(stored, isNot(contains('First words')));
      expect(stored.toLowerCase().contains('revs'), isFalse);
      // Nor is it in the doctor sheet.
      expect(cpDoctorSheetText(childName: 'Mia', doc: await a.read(mom), now: clock.t), isNot(contains('Second words')));
    });

    test('goes through the tone guard and a length limit; clearing removes it', () async {
      expect((await s.setHeads(mom, 'Obviously a bad mood')).reason, 'tone');
      expect((await s.setHeads(mom, 'x' * (cpMaxHeadsChars + 1))).reason, 'too_long');
      expect((await s.setHeads(mom, '')).reason, 'text_needed');
      await s.setHeads(mom, 'Quiet day');
      await s.clearHeads(mom);
      expect((await s.read(mom)).heads, isNull);
    });
  });

  group('sharing on this device', () {
    test('a new person starts with the table\'s defaults, and a parent can change every one', () async {
      final String nan = (await s.addPerson(mom, 'Nan', CpPersonKind.carer)).value!;
      final String sitter = (await s.addPerson(mom, 'Sitter', CpPersonKind.visit)).value!;
      CareProfileDoc d = await s.read(mom);
      CpPerson p(String id) => d.people.firstWhere((CpPerson x) => x.id == id);
      expect(p(nan).grants.keys.toSet(), <CareProfilePart>{CareProfilePart.safe, CareProfilePart.everyday, CareProfilePart.heads});
      expect(p(sitter).grants[CareProfilePart.safe]!.until, isNotNull);
      expect((await s.setGrant(mom, nan, CareProfilePart.helps)).ok, isTrue);
      expect((await s.setGrant(mom, nan, CareProfilePart.everyday, on: false)).ok, isTrue);
      d = await s.read(mom);
      expect(cpCanSee(p(nan), CareProfilePart.helps, clock.t), isTrue);
      expect(cpCanSee(p(nan), CareProfilePart.everyday, clock.t), isFalse);
    });

    test('Health history and Moods cannot be granted to anyone; a view-only person only gets Keep-safe', () async {
      final String nan = (await s.addPerson(mom, 'Nan', CpPersonKind.carer)).value!;
      final String view = (await s.addPerson(mom, 'Aunt', CpPersonKind.viewOnly)).value!;
      expect((await s.setGrant(mom, nan, CareProfilePart.health)).reason, 'not_shareable');
      expect((await s.setGrant(mom, nan, CareProfilePart.moods)).reason, 'not_shareable');
      expect((await s.setGrant(mom, view, CareProfilePart.everyday)).reason, 'not_allowed');
      expect((await s.setGrant(mom, view, CareProfilePart.safe)).ok, isTrue);
    });

    test('a time box is a real time in the future; it ends by itself', () async {
      final String v = (await s.addPerson(mom, 'Sitter', CpPersonKind.helperPage)).value!;
      expect((await s.setGrant(mom, v, CareProfilePart.safe, until: clock.t.subtract(const Duration(hours: 1)))).reason, 'bad_time');
      expect((await s.setGrant(mom, v, CareProfilePart.safe, until: clock.t.add(const Duration(days: 400)))).reason, 'bad_time');
      expect((await s.setGrant(mom, v, CareProfilePart.safe, until: clock.t.add(const Duration(hours: 3)))).ok, isTrue);
      final CareProfileDoc d = await s.read(mom);
      final CpPerson p = d.people.single;
      expect(cpCanSee(p, CareProfilePart.safe, clock.t.add(const Duration(hours: 2))), isTrue);
      expect(cpCanSee(p, CareProfilePart.safe, clock.t.add(const Duration(hours: 4))), isFalse);
    });

    test('"Show for tonight" gives Keep-safe and the heads-up until 6 in the morning, nothing else', () async {
      clock.t = DateTime(2026, 11, 14, 19);
      final String v = (await s.addPerson(mom, 'Aunt', CpPersonKind.viewOnly)).value!;
      expect((await s.grantTonight(mom, v)).ok, isTrue);
      final CpPerson p = (await s.read(mom)).people.single;
      expect(cpCanSee(p, CareProfilePart.safe, DateTime(2026, 11, 14, 23)), isTrue);
      expect(cpCanSee(p, CareProfilePart.safe, DateTime(2026, 11, 15, 6, 1)), isFalse);
      expect(cpCanSee(p, CareProfilePart.heads, DateTime(2026, 11, 14, 23)), isFalse, reason: 'view only cannot have the heads-up');
    });

    test('a person can be removed, the list is bounded, and a name is needed', () async {
      expect((await s.addPerson(mom, '  ', CpPersonKind.carer)).reason, 'name_needed');
      for (int i = 0; i < cpMaxPeople; i++) {
        expect((await s.addPerson(mom, 'P$i', CpPersonKind.viewOnly)).ok, isTrue);
      }
      expect((await s.addPerson(mom, 'Extra', CpPersonKind.viewOnly)).reason, 'too_many');
      final String id = (await s.read(mom)).people.first.id;
      expect((await s.removePerson(mom, id)).ok, isTrue);
      expect((await s.removePerson(mom, id)).reason, 'not_found');
    });
  });

  group('the care binder is copied in once and not changed', () {
    final List<CareSection> sections = <CareSection>[
      const CareSection(id: 's1', kind: 'allergies', title: 'Allergies (written by a guardian)', body: 'Peanuts: hives', updatedOn: '2026-10-01'),
      const CareSection(id: 's2', kind: 'routines', title: 'Routines', body: 'Bath then book', updatedOn: '2026-10-02'),
      const CareSection(id: 's3', kind: 'school', title: 'School', body: '', updatedOn: '2026-10-03'),
      const CareSection(id: 's4', kind: 'other', title: 'Notes', body: 'Blue blanket', updatedOn: '2026-10-04'),
    ];

    test('allergies go to Keep-safe, the rest to everyday, blank ones wait; each says it came from the binder', () async {
      final CareResult<int> r = await s.importBinder(mom, sections);
      expect(r.value, 3);
      final CareProfileDoc d = await s.read(mom);
      expect(cpEntriesOf(d, CareProfilePart.safe).single.text, 'Peanuts: hives');
      expect(cpEntriesOf(d, CareProfilePart.everyday).map((CpEntry e) => e.text).toSet(), <String>{'Bath then book', 'Blue blanket'});
      expect(cpWrittenBy(cpEntriesOf(d, CareProfilePart.safe).single), 'from the care binder, 1 Oct 2026');
    });

    test('a second open copies nothing twice; a section written later is picked up', () async {
      await s.importBinder(mom, sections);
      expect((await s.importBinder(mom, sections)).value, 0);
      final List<CareSection> later = <CareSection>[
        ...sections.where((CareSection x) => x.id != 's3'),
        const CareSection(id: 's3', kind: 'school', title: 'School', body: 'Gate 2', updatedOn: '2026-11-01'),
      ];
      expect((await s.importBinder(mom, later)).value, 1);
      expect((await s.read(mom)).entries, hasLength(4));
    });

    test('the binder itself loses nothing: every section and contact is still there afterwards', () async {
      final GrowingCareStores stores = GrowingCareStores.memory();
      for (final CareSection x in sections) {
        await stores.sections.save(x);
      }
      await stores.contacts.save(const CareContact(id: 'c1', name: 'Dr Okoye', phone: '555-0100'));
      final String before = jsonEncode(<Object?>[for (final CareSection x in await stores.sections.list()) x.toJson()]);
      await s.importBinder(mom, await stores.sections.list());
      expect(jsonEncode(<Object?>[for (final CareSection x in await stores.sections.list()) x.toJson()]), before);
      expect((await stores.contacts.list()).single.name, 'Dr Okoye');
    });

    test('a binder entry can be taken over by whichever grown-up first changes it', () async {
      await s.importBinder(mom, sections);
      final String id = cpEntriesOf(await s.read(dad), CareProfilePart.safe).single.id;
      expect((await s.editEntry(dad, id, 'Peanuts: hives; carries a pen', byName: 'Alex')).ok, isTrue);
      final CpEntry e = cpEntriesOf(await s.read(dad), CareProfilePart.safe).single;
      expect(e.byName, 'Alex');
      expect(e.revisions.single.text, 'Peanuts: hives');
      expect((await s.editEntry(mom, id, 'x')).reason, 'not_yours', reason: 'now it is Alex\'s');
    });

    test('words already in the binder are copied as written, not refused by the tone guard', () async {
      await s.importBinder(mom, <CareSection>[const CareSection(id: 'n', kind: 'other', title: 'Notes', body: 'bad mood after school', updatedOn: '2026-10-04')]);
      expect((await s.read(mom)).entries.single.text, 'bad mood after school');
    });
  });

  group('keeping it true', () {
    test('the first visit remembers the medicine list; a later change prompts a review; "still right" settles it', () async {
      final CareService meds = CareService.memory(childScope: 'ivy', clock: clock.call);
      await s.addEntry(mom, CareProfilePart.safe, 'Peanut allergy');
      String fp = cpMedicineFingerprint(await meds.read(mom));
      await s.ensureBaseline(mom, fp);
      await s.ensureBaseline(mom, 'ignored: the baseline is only set once');
      CareProfileDoc d = await s.read(mom);
      expect(cpReviewReasons(d, clock.t, medFingerprint: fp), isEmpty);
      await meds.addMedication(mom, const CareMedication(id: '', name: 'Inhaler', kind: MedKind.prn), byName: 'Sam');
      fp = cpMedicineFingerprint(await meds.read(mom));
      expect(cpReviewReasons(d, clock.t, medFingerprint: fp).single.kind, CpReviewKind.medicineChange);
      await s.markReviewed(mom, fp);
      d = await s.read(mom);
      expect(cpReviewReasons(d, clock.t, medFingerprint: fp), isEmpty);
      expect(d.lastReviewedAt, isNotNull);
    });

    test('giving a dose is not a medicine change, and the double-dose guard still belongs to the log', () async {
      final CareService meds = CareService.memory(childScope: 'ivy', clock: clock.call);
      final String id = (await meds.addMedication(mom, const CareMedication(id: '', name: 'Inhaler', kind: MedKind.prn, gapHours: 4))).value!;
      final String before = cpMedicineFingerprint(await meds.read(mom));
      expect((await meds.logDose(mom, id)).ok, isTrue);
      expect(cpMedicineFingerprint(await meds.read(mom)), before);
      final CareResult<DateTime> again = await meds.logDose(dad, id);
      expect(again.reason, 'already_given');
      expect(cpMedicineLines(await meds.read(mom)).single.lastGiven, isNotNull);
    });

    test('a birthday is a real month and day; 29 February is allowed; it can be forgotten', () async {
      expect((await s.setBirthday(mom, 13, 1)).reason, 'bad_date');
      expect((await s.setBirthday(mom, 4, 31)).reason, 'bad_date');
      expect((await s.setBirthday(mom, 2, 29)).ok, isTrue);
      expect((await s.read(mom)).birthMonth, 2);
      expect((await s.setBirthday(mom, null, null)).ok, isTrue);
      expect((await s.read(mom)).birthMonth, isNull);
    });

    test('the teen preview defaults OFF and survives a restart when switched on', () async {
      final MemoryStoreBackend disk = MemoryStoreBackend();
      final CareProfileService a = CareProfileService.local(_device(disk), clock: clock.call);
      expect((await a.read(mom)).teenPreview, isFalse);
      await a.setTeenPreview(mom, true);
      expect((await CareProfileService.local(_device(disk)).read(mom)).teenPreview, isTrue);
    });
  });

  group('the photos of a doctor\'s plan', () {
    late CarePlanPhotoService ph;
    setUp(() => ph = CarePlanPhotoService.memory(clock: clock.call));

    test('a photo a grown-up chose is kept with the label they typed and who kept it', () async {
      final CareResult<String> r = await ph.add(mom, '  Asthma plan ', _jpeg(), byName: 'Sam');
      expect(r.ok, isTrue);
      final CpPlanPhoto p = (await ph.list(mom)).single;
      expect(p.label, 'Asthma plan');
      expect(p.bytes, _jpeg());
      expect(p.byName, 'Sam');
    });

    test('only a JPEG or PNG, a label, a size and a count within limits', () async {
      expect((await ph.add(mom, 'Plan', Uint8List.fromList(<int>[1, 2, 3, 4, 5, 6, 7, 8, 9]))).reason, 'not_an_image');
      expect((await ph.add(mom, ' ', _jpeg())).reason, 'name_needed');
      expect((await ph.add(mom, 'Plan', _jpeg(cpMaxPlanPhotoBytes))).reason, 'photo_too_big');
      for (int i = 0; i < cpMaxPlanPhotos; i++) {
        expect((await ph.add(mom, 'P$i', _jpeg())).ok, isTrue);
      }
      expect((await ph.add(mom, 'Extra', _jpeg())).reason, 'too_many');
      final String id = (await ph.list(mom)).first.id;
      expect((await ph.remove(mom, id)).ok, isTrue);
      expect((await ph.add(mom, 'Again', _jpeg())).ok, isTrue);
      expect((await ph.list(mom)).map((CpPlanPhoto x) => x.id).toSet(), hasLength(cpMaxPlanPhotos), reason: 'ids stay distinct');
    });

    test('is sealed on the device and survives a restart', () async {
      final MemoryStoreBackend disk = MemoryStoreBackend();
      final CarePlanPhotoService a = CarePlanPhotoService.local(_device(disk), clock: clock.call);
      await a.add(mom, 'Peanut action plan', _jpeg(), byName: 'Sam');
      final String raw = utf8.decode(disk.rawFor('child.ivy.aboutplans')!, allowMalformed: true);
      expect(raw, isNot(contains('Peanut')));
      expect((await CarePlanPhotoService.local(_device(disk)).list(mom)).single.label, 'Peanut action plan');
    });

    test('the app never makes one: the only way in is add() with bytes the caller hands over', () {
      // The service has no camera, picker or generator of its own (care_profile_structure_test.dart checks the source).
      expect(CarePlanPhotoService.memory().add, isA<Function>());
    });
  });

  group('storage', () {
    test('both areas are catalogued, per child, sealed, guardian-side, and the wipe screen names them', () {
      for (final String a in <String>['aboutchild', 'aboutplans']) {
        final LocalDataEntry e = localDataEntry(a);
        expect(e.scope, LocalScope.child, reason: a);
        expect(e.encrypted, isTrue, reason: a);
        final String w = e.what.toLowerCase();
        expect(w, contains('never uploaded'), reason: a);
        expect(w, contains('never'), reason: a);
        expect(w, isNot(contains('score')), reason: a);
        expect(kLocalDataAreaNames[a], isNotNull, reason: a);
        expect(describeLocalData(), contains(a));
      }
      expect(localDataEntry('aboutchild').what.toLowerCase(), contains('not an evidence log'));
    });

    test('the profile is unreadable on disk, survives a restart and is scoped to its child', () async {
      final MemoryStoreBackend disk = MemoryStoreBackend();
      final CareProfileService a = CareProfileService.local(_device(disk), clock: clock.call);
      await a.addEntry(mom, CareProfilePart.safe, 'Peanut allergy: hives', byName: 'Okonkwo');
      final String raw = utf8.decode(disk.rawFor('child.ivy.aboutchild')!, allowMalformed: true);
      expect(raw, isNot(contains('Peanut')));
      expect(raw, isNot(contains('Okonkwo')));
      expect((await CareProfileService.local(_device(disk)).read(mom)).entries.single.text, 'Peanut allergy: hives');
      expect((await CareProfileService.local(_device(disk), childId: 'other').read(mom)).entries, isEmpty);
    });

    test('forgetting the child removes the profile and the photos with it', () async {
      final MemoryStoreBackend disk = MemoryStoreBackend();
      final LocalServices dev = _device(disk);
      await CareProfileService.local(dev, clock: clock.call).addEntry(mom, CareProfilePart.safe, 'x');
      await CarePlanPhotoService.local(dev, clock: clock.call).add(mom, 'Plan', _jpeg());
      await dev.forgetChild('ivy');
      expect((await CareProfileService.local(dev).read(mom)).entries, isEmpty);
      expect(await CarePlanPhotoService.local(dev).list(mom), isEmpty);
    });

    test('a full box refuses the write and keeps what it had', () async {
      final MemoryStoreBackend disk = MemoryStoreBackend();
      final LocalStore store = LocalStore(backend: disk, cipher: AesGcmStoreCipher(_key));
      final CareProfileService tiny = CareProfileService(
        LocalStoreCareProfileRepository(store.open(const NamespaceSpec(name: 'child.ivy.aboutchild', schema: 1, encrypted: true, maxBytes: 1500))),
        clock: clock.call,
      );
      expect((await tiny.addEntry(mom, CareProfilePart.safe, 'a' * 400)).ok, isTrue);
      final CareResult<String> r = await tiny.addEntry(mom, CareProfilePart.safe, 'b' * 3000);
      expect(r.reason, 'full');
      final CareProfileDoc d = await tiny.read(mom);
      expect(d.entries, hasLength(1));
      expect(d.entries.single.text, 'a' * 400);
    });

    test('a damaged file reads as an empty profile, never a crash', () async {
      final MemoryStoreBackend disk = MemoryStoreBackend();
      final LocalServices dev = _device(disk);
      await dev.area('aboutchild').put('doc', 'garbage');
      expect((await CareProfileService.local(dev).read(mom)).entries, isEmpty);
    });
  });
}
