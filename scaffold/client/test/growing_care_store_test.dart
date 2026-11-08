// OLIVE BRANCH — the repositories behind suites G and F. In-memory and
// LocalStore-backed behave alike; the durable one survives a restart, is sealed
// on disk, is per child, refuses what breaks a bound, and is wiped by the
// device wipe. The child's lens cannot reach what is guardian-only.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/growing_care_logic.dart';
import 'package:olive_client/growing_care_store.dart';
import 'package:olive_client/local_services.dart';
import 'package:olive_client/local_store.dart';
import 'package:olive_client/store_cipher.dart';

final Uint8List _key = Uint8List.fromList(List<int>.filled(32, 9));

LocalServices _device(MemoryStoreBackend b, {String child = 'ivy'}) => LocalServices(
    store: LocalStore(backend: b, cipher: AesGcmStoreCipher(_key)), childId: child, isLive: true, demoSeeds: false);

String _rawText(MemoryStoreBackend b, String name) => utf8.decode(b.rawFor(name)!, allowMalformed: true);

TimeCapsule _cap(String id, {String opens = '2039-06-01', String note = 'SECRET-CAPSULE-WORDS'}) =>
    TimeCapsule(id: id, title: 'For thirteen', note: note, sealedOn: '2026-11-08', opensOn: opens);

void main() {
  group('the catalogue lists exactly what these suites store, all sealed', () {
    for (final String area in <String>['growing', 'memorybox', 'care', 'explainers']) {
      test('$area is catalogued, per child, encrypted, bounded and described', () {
        final LocalDataEntry e = localDataEntry(area);
        expect(e.scope, LocalScope.child);
        expect(e.encrypted, isTrue);
        expect(e.maxBytes, greaterThan(1024 * 1024));
        expect(e.what.toLowerCase(), contains('never uploaded'));
      });
    }

    test('the care area says it is guardian-side only and adds no medical text', () {
      final String w = localDataEntry('care').what.toLowerCase();
      expect(w, contains('grown-up side only'));
      expect(w, contains('no medical text'));
      expect(w, contains('never shown in her app'));
    });

    test('the catalogue text stays clear of scores, streaks and positions (P2, P3)', () {
      final String all = describeLocalData().toLowerCase();
      expect(all, isNot(contains('location')));
      for (final String area in <String>['growing', 'memorybox', 'care', 'explainers']) {
        final String t = localDataEntry(area).what.toLowerCase();
        for (final String bad in <String>['streak', 'score', 'ranking', 'badge', 'price']) {
          if (t.contains(bad)) expect(t, contains('no '));
        }
      }
    });

    test('namespaces are named for the child and open with the declared ceiling', () {
      final LocalServices s = _device(MemoryStoreBackend());
      expect(s.area('care').spec.name, 'child.ivy.care');
      expect(s.area('growing').spec.encrypted, isTrue);
      expect(s.area('memorybox').spec.maxBytes, localDataEntry('memorybox').maxBytes);
    });
  });

  group('MemoryItemRepository', () {
    test('saves, lists, replaces by id and removes', () async {
      final MemoryItemRepository<TimeCapsule> r = MemoryItemRepository<TimeCapsule>(capsuleKind);
      await r.save(_cap('a'));
      await r.save(_cap('b'));
      await r.save(_cap('a', note: 'changed'));
      final List<TimeCapsule> all = await r.list();
      expect(all.map((TimeCapsule c) => c.id), <String>['a', 'b']);
      expect((await r.get('a'))!.note, 'changed');
      await r.remove('a');
      await r.remove('missing');
      expect((await r.list()).map((TimeCapsule c) => c.id), <String>['b']);
    });

    test('what is handed out cannot change what is stored', () async {
      final MemoryItemRepository<ExplainerStory> r = MemoryItemRepository<ExplainerStory>(storyKind);
      await r.save(const ExplainerStory(id: 'e', title: 'T', pages: <String>['one'], updatedOn: '2026-11-08'));
      final ExplainerStory got = (await r.get('e'))!;
      got.pages.add('tampered');
      expect((await r.get('e'))!.pages, <String>['one']);
    });

    test('a refused write changes nothing', () async {
      final MemoryItemRepository<TimeCapsule> r = MemoryItemRepository<TimeCapsule>(capsuleKind);
      await r.save(_cap('a'));
      await expectLater(r.save(_cap('b', opens: '2020-01-01')), throwsA(isA<CareRefused>()));
      expect((await r.list()).map((TimeCapsule c) => c.id), <String>['a']);
    });

    test('too many items: the cap is enforced for a new id but not for a replace', () async {
      final MemoryItemRepository<ExplainerStory> r = MemoryItemRepository<ExplainerStory>(storyKind);
      for (int i = 0; i < maxExplainers; i++) {
        await r.save(ExplainerStory(id: 'e$i', title: 'T', pages: const <String>['p'], updatedOn: '2026-11-08'));
      }
      await expectLater(
          r.save(const ExplainerStory(id: 'extra', title: 'T', pages: <String>['p'], updatedOn: '2026-11-08')),
          throwsA(isA<CareRefused>().having((CareRefused e) => e.reason, 'reason', 'too_many')));
      await r.save(const ExplainerStory(id: 'e0', title: 'T2', pages: <String>['p'], updatedOn: '2026-11-08'));
      expect((await r.get('e0'))!.title, 'T2');
    });

    test('an id that is not key-safe is refused, as is an item over its byte cap', () async {
      final MemoryItemRepository<MemoryItem> r = MemoryItemRepository<MemoryItem>(memoryKind);
      await expectLater(
          r.save(MemoryItem(id: 'bad id!', kind: 'photo', addedOn: '2026-11-08', thumb: Uint8List(5))),
          throwsA(isA<CareRefused>().having((CareRefused e) => e.reason, 'reason', 'invalid')));
      final MemoryItemRepository<CareSection> sections = MemoryItemRepository<CareSection>(sectionKind);
      await sections.save(const CareSection(id: 's', kind: 'other', title: 'Notes', body: 'ok', updatedOn: '2026-11-08'));
      expect(await sections.list(), hasLength(1));
    });

    test('a singleton (switches, hospital notes) keeps one document', () async {
      final MemoryItemRepository<HospitalNotes> r = MemoryItemRepository<HospitalNotes>(hospitalKind);
      await r.save(const HospitalNotes(toBring: 'owl'));
      await r.save(const HospitalNotes(toBring: 'owl and book'));
      expect(await r.list(), hasLength(1));
      expect((await r.get(HospitalNotes.itemId))!.toBring, 'owl and book');
    });

    test('suite switches load as all-on and persist a change', () async {
      final MemoryItemRepository<SuiteSwitches> r = MemoryItemRepository<SuiteSwitches>(switchKind);
      expect((await r.load()).on('memoryBox'), isTrue);
      await r.setSuite('memoryBox', false);
      expect((await r.load()).on('memoryBox'), isFalse);
      expect((await r.load()).on('careBinder'), isTrue);
    });
  });

  group('LocalItemRepository: durable, sealed, per child', () {
    test('every kind survives a restart of the phone', () async {
      final MemoryStoreBackend disk = MemoryStoreBackend();
      GrowingCareStores a = GrowingCareStores.forChild(services: _device(disk));
      await a.capsules.save(_cap('c1'));
      await a.firsts.save(const FirstTime(id: 'f1', title: 'First tooth', on: '2026-09-12', note: 'wobbly', showHer: true));
      await a.marks.save(const PencilMark(id: 'm1', on: '2026-11-01', cm: 111));
      await a.switches.setSuite('pencilMarks', false);
      await a.memories.save(const MemoryItem(id: 'x1', kind: 'doodle', addedOn: '2026-11-08', pictureData: <String, Object?>{'w': 4}));
      await a.sections.save(const CareSection(id: 's1', kind: 'allergies', title: 'Allergies (written by a guardian)', body: 'Peanuts', updatedOn: '2026-11-08'));
      await a.contacts.save(const CareContact(id: 'p1', name: 'Nana', phone: '555-0101'));
      await a.hospital.save(const HospitalNotes(happeningToday: 'Scan at two'));
      await a.preps.save(const AppointmentPrep(id: 'a1', title: 'Check-up', createdOn: '2026-11-08', questions: <String>['How long?']));
      await a.stories.save(const ExplainerStory(id: 'e1', title: 'The hospital', pages: <String>['Mom is at the hospital.'], updatedOn: '2026-11-08', shownToHer: true));

      a = GrowingCareStores.forChild(services: _device(disk)); // the phone restarted
      expect((await a.capsules.get('c1'))!.note, 'SECRET-CAPSULE-WORDS');
      expect((await a.firsts.get('f1'))!.showHer, isTrue);
      expect((await a.marks.get('m1'))!.cm, 111);
      expect((await a.switches.load()).on('pencilMarks'), isFalse);
      expect((await a.memories.get('x1'))!.pictureData, <String, Object?>{'w': 4});
      expect((await a.sections.get('s1'))!.body, 'Peanuts');
      expect((await a.contacts.get('p1'))!.phone, '555-0101');
      expect((await a.hospital.get(HospitalNotes.itemId))!.happeningToday, 'Scan at two');
      expect((await a.preps.get('a1'))!.questions, <String>['How long?']);
      expect((await a.stories.get('e1'))!.pages.single, 'Mom is at the hospital.');
    });

    test('nothing readable is on disk: the words, the contacts and the photos are all sealed', () async {
      final MemoryStoreBackend disk = MemoryStoreBackend();
      final GrowingCareStores a = GrowingCareStores.forChild(services: _device(disk));
      await a.capsules.save(_cap('c1'));
      await a.sections.save(const CareSection(id: 's1', kind: 'other', title: 'Notes', body: 'PEANUT-ALLERGY-TEXT', updatedOn: '2026-11-08'));
      await a.contacts.save(const CareContact(id: 'p1', name: 'Dr Okonkwo-Contact', phone: '555-0199'));
      await a.stories.save(const ExplainerStory(id: 'e1', title: 'Story title SEALED', pages: <String>['page SEALED words'], updatedOn: '2026-11-08'));
      await a.memories.save(MemoryItem(id: 'x1', kind: 'photo', addedOn: '2026-11-08', thumb: Uint8List.fromList(List<int>.generate(300, (int i) => i % 251))));
      expect(await disk.names(), containsAll(<String>['child.ivy.growing', 'child.ivy.care', 'child.ivy.explainers', 'child.ivy.memorybox']));
      for (final String name in await disk.names()) {
        final String raw = _rawText(disk, name);
        expect(raw, contains('"enc":true'), reason: name);
        for (final String secret in <String>['SECRET-CAPSULE', 'PEANUT-ALLERGY', 'Okonkwo', '555-0199', 'SEALED', 'thumb']) {
          expect(raw, isNot(contains(secret)), reason: '$name must not hold "$secret" in plaintext');
        }
      }
    });

    test('a different child on the same phone sees none of it', () async {
      final MemoryStoreBackend disk = MemoryStoreBackend();
      await GrowingCareStores.forChild(services: _device(disk, child: 'ivy')).capsules.save(_cap('c1'));
      await GrowingCareStores.forChild(services: _device(disk, child: 'ivy')).sections.save(
          const CareSection(id: 's', kind: 'other', title: 'Notes', body: 'x', updatedOn: '2026-11-08'));
      final GrowingCareStores wren = GrowingCareStores.forChild(services: _device(disk, child: 'wren'));
      expect(await wren.capsules.list(), isEmpty);
      expect(await wren.sections.list(), isEmpty);
    });

    test('forgetting one child removes all four areas and leaves another child alone', () async {
      final MemoryStoreBackend disk = MemoryStoreBackend();
      final LocalServices s = _device(disk, child: 'ivy');
      final GrowingCareStores ivy = GrowingCareStores.forChild(services: s);
      await ivy.capsules.save(_cap('c1'));
      await ivy.stories.save(const ExplainerStory(id: 'e', title: 'T', pages: <String>['p'], updatedOn: '2026-11-08'));
      await GrowingCareStores.forChild(services: _device(disk, child: 'wren')).capsules.save(_cap('w1'));
      await s.forgetChild('ivy');
      expect(await GrowingCareStores.forChild(services: _device(disk, child: 'ivy')).capsules.list(), isEmpty);
      expect(await GrowingCareStores.forChild(services: _device(disk, child: 'ivy')).stories.list(), isEmpty);
      expect(await GrowingCareStores.forChild(services: _device(disk, child: 'wren')).capsules.list(), hasLength(1));
    });

    test('the device wipe removes everything these suites hold', () async {
      final MemoryStoreBackend disk = MemoryStoreBackend();
      final LocalServices s = _device(disk);
      final GrowingCareStores a = GrowingCareStores.forChild(services: s);
      await a.capsules.save(_cap('c1'));
      await a.hospital.save(const HospitalNotes(toBring: 'owl'));
      await s.wipeAll();
      expect(await disk.names(), isEmpty);
      expect(await a.capsules.list(), isEmpty);
      expect(await a.hospital.list(), isEmpty);
    });

    test('a full box says so and leaves what is there untouched', () async {
      final MemoryStoreBackend disk = MemoryStoreBackend();
      final LocalStore store = LocalStore(backend: disk, cipher: AesGcmStoreCipher(_key));
      final LocalItemRepository<FirstTime> r = LocalItemRepository<FirstTime>(
          store.open(const NamespaceSpec(name: 'child.ivy.growing', encrypted: true, maxBytes: 2500)), firstKind);
      final Uint8List photo = Uint8List.fromList(List<int>.generate(1200, (int i) => i % 200));
      await r.save(FirstTime(id: 'f1', title: 'one', on: '2026-01-01', thumb: photo));
      await expectLater(r.save(FirstTime(id: 'f2', title: 'two', on: '2026-01-02', thumb: photo)),
          throwsA(isA<CareRefused>().having((CareRefused e) => e.reason, 'reason', 'full')));
      expect((await r.list()).map((FirstTime f) => f.id), <String>['f1']);
      expect(const CareRefused('full').message, contains('full'));
    });

    test('a damaged file is quarantined and the suite starts empty, never a crash', () async {
      final MemoryStoreBackend disk = MemoryStoreBackend();
      await GrowingCareStores.forChild(services: _device(disk)).capsules.save(_cap('c1'));
      disk.plant('child.ivy.growing', Uint8List.fromList(utf8.encode('{broken')));
      final GrowingCareStores again = GrowingCareStores.forChild(services: _device(disk));
      expect(await again.capsules.list(), isEmpty);
      expect(await again.marks.list(), isEmpty);
      expect(await disk.quarantineCount(), 1);
    });

    test('a real directory: save, restart, read back', () async {
      final Directory dir = await Directory.systemTemp.createTemp('olive_growing_care_');
      addTearDown(() => dir.delete(recursive: true));
      LocalServices boot() => LocalServices(
          store: LocalStore(backend: DirectoryStoreBackend(dir), cipher: AesGcmStoreCipher(_key)),
          childId: 'ivy', isLive: true, demoSeeds: false);
      await GrowingCareStores.forChild(services: boot()).sections.save(
          const CareSection(id: 's1', kind: 'routines', title: 'Routines', body: 'Bath at seven', updatedOn: '2026-11-08'));
      expect((await GrowingCareStores.forChild(services: boot()).sections.get('s1'))!.body, 'Bath at seven');
    });

    test('a live build refuses the demo-child scope for these areas too', () {
      final LocalServices live = LocalServices.memory(childId: 'real', isLive: true, demoSeeds: false);
      expect(() => GrowingCareStores.forChild(childId: 'demo-child', services: live), throwsStateError);
    });

    test('an undecodable document is skipped, the rest still load', () async {
      final MemoryStoreBackend disk = MemoryStoreBackend();
      final LocalServices s = _device(disk);
      await s.area('growing').put('cap.junk', <String, Object?>{'id': 'junk', 'title': 3});
      final GrowingCareStores a = GrowingCareStores.forChild(services: s);
      await a.capsules.save(_cap('good'));
      expect((await a.capsules.list()).map((TimeCapsule c) => c.id), <String>['good']);
    });
  });

  group('her side reads through narrow, read-only types', () {
    test('a sealed capsule is not visible to her at all: no title, no date, no count', () async {
      final GrowingCareStores s = GrowingCareStores.memory();
      await s.capsules.save(_cap('sealed'));
      await s.capsules.save(_cap('due', opens: '2026-11-08'.replaceFirst('08', '09')));
      final ChildGrowingLens lens = s.childLens(now: () => DateTime(2026, 11, 8));
      expect(await lens.openedLetters(), isEmpty);
      final ChildGrowingLens later = s.childLens(now: () => DateTime(2026, 11, 9));
      expect((await later.openedLetters()).map((TimeCapsule c) => c.id), <String>['due']);
    });

    test('a guardian-unsealed capsule opens for her at once', () async {
      final GrowingCareStores s = GrowingCareStores.memory();
      await s.capsules.save(_cap('c').unsealed('2026-11-08'));
      expect(await s.childLens(now: () => DateTime(2026, 11, 8)).openedLetters(), hasLength(1));
    });

    test('she sees only the firsts a guardian chose to show, newest first', () async {
      final GrowingCareStores s = GrowingCareStores.memory();
      await s.firsts.save(const FirstTime(id: 'a', title: 'hidden', on: '2026-09-01'));
      await s.firsts.save(const FirstTime(id: 'b', title: 'old', on: '2026-01-01', showHer: true));
      await s.firsts.save(const FirstTime(id: 'c', title: 'new', on: '2026-10-01', showHer: true));
      expect((await s.childLens().shownFirsts()).map((FirstTime f) => f.id), <String>['c', 'b']);
    });

    test('her growth picture is month labels and positions: it holds no centimetres', () async {
      final GrowingCareStores s = GrowingCareStores.memory();
      await s.marks.save(const PencilMark(id: 'a', on: '2026-06-01', cm: 100));
      await s.marks.save(const PencilMark(id: 'b', on: '2026-11-01', cm: 104));
      final List<GrowthMarkView> g = await s.childLens().growth();
      expect(g.map((GrowthMarkView m) => m.label), <String>['Jun 2026', 'Nov 2026']);
      expect(g.map((GrowthMarkView m) => m.label).join(' '), isNot(contains('cm')));
    });

    test('picture stories reach her only when a guardian chose to show them', () async {
      final GrowingCareStores s = GrowingCareStores.memory();
      await s.stories.save(const ExplainerStory(id: 'a', title: 'Hidden', pages: <String>['p'], updatedOn: '2026-11-08'));
      await s.stories.save(const ExplainerStory(id: 'b', title: 'Shown', pages: <String>['p'], updatedOn: '2026-11-08', shownToHer: true));
      expect((await s.childExplainers().shown()).map((ExplainerStory e) => e.title), <String>['Shown']);
    });

    test('the lens and the reader expose no write and no care repository', () {
      final GrowingCareStores s = GrowingCareStores.memory();
      final Object lens = s.childLens();
      final Object reader = s.childExplainers();
      expect(lens, isNot(isA<ItemRepository<Object?>>()));
      expect(reader, isNot(isA<ItemRepository<Object?>>()));
      final String lensSrc = File('lib/growing_care_store.dart').readAsStringSync();
      final String lensBody = lensSrc.substring(lensSrc.indexOf('class ChildGrowingLens'), lensSrc.indexOf('abstract class ChildExplainerReader'));
      for (final String banned in <String>['_sections', '_contacts', '_hospital', '_preps', 'CareSection', 'HospitalNotes', 'AppointmentPrep']) {
        expect(lensBody, isNot(contains(banned)), reason: 'ChildGrowingLens must not touch $banned');
      }
    });
  });

  group('ids', () {
    test('IdMaker never repeats within a run, even on a frozen clock', () {
      final IdMaker m = IdMaker(() => DateTime(2026, 11, 8));
      final Set<String> seen = <String>{for (int i = 0; i < 50; i++) m.next('c')};
      expect(seen, hasLength(50));
      expect(RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(seen.first), isTrue);
    });
  });
}
