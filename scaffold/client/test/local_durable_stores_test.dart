// OLIVE BRANCH — the two follow-up stores backed by LocalStore: colour of the
// day / art style / play window (her_colour_store.dart's two interfaces) and the
// family structure (family_structure_store.dart's FamilyStore). Each survives a
// restart; the real rules still run; nothing older than the kept window stays.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/colour_day_logic.dart';
import 'package:olive_client/family_structure_store.dart';
import 'package:olive_client/her_colour_store.dart';
import 'package:olive_client/local_services.dart';
import 'package:olive_client/local_store.dart';
import 'package:olive_client/store_cipher.dart';

final Uint8List _key = Uint8List.fromList(List<int>.filled(32, 5));

LocalServices _device(MemoryStoreBackend b, {String child = 'ivy'}) => LocalServices(
    store: LocalStore(backend: b, cipher: AesGcmStoreCipher(_key)), childId: child, isLive: true, demoSeeds: false);

void main() {
  DateTime clock = DateTime(2026, 11, 7, 8, 0);
  LocalColourStore colour(LocalServices s, {int age = 9}) =>
      LocalColourStore(s.area('colour'), ageYears: age, now: () => clock);

  group('LocalColourStore', () {
    test('her answer, a guardian colour day, the art style and the play window all survive a restart', () async {
      clock = DateTime(2026, 11, 7, 8, 0);
      final MemoryStoreBackend disk = MemoryStoreBackend();
      final LocalColourStore a = colour(_device(disk));
      await a.answer('sea');
      expect((await a.saveArt(<String, dynamic>{'dailyQuestion': false})).ok, isTrue);
      expect((await a.savePlayWindow(const PlayWindow(opensMin: 420, restsMin: 1140, windDownMin: 15))).ok, isTrue);

      final LocalColourStore b = colour(_device(disk)); // the phone restarted
      final TodayColour t = await b.today();
      expect(t.colourId, 'sea');
      expect((await b.art()).dailyQuestion, isFalse);
      expect((await b.playWindow()).window!.restsMin, 1140);
    });

    test('the real rules still run: a colour day holds against her tap, even after a restart', () async {
      clock = DateTime(2026, 11, 7, 8, 0);
      final MemoryStoreBackend disk = MemoryStoreBackend();
      await colour(_device(disk)).setColourDay('mint');
      final LocalColourStore b = colour(_device(disk));
      await b.saveArt(<String, dynamic>{'dailyQuestion': true});
      await b.answer('sea');
      expect((await b.today()).colourId, 'mint');
      expect(await b.clearColourDay(), isTrue);
    });

    test('yesterday carries over after a restart; days older than two weeks are not kept (no tally of picks)', () async {
      final MemoryStoreBackend disk = MemoryStoreBackend();
      final LocalServices s = _device(disk);
      LocalColourStore store() => colour(_device(disk));
      for (int d = 0; d < 20; d++) {
        clock = DateTime(2026, 10, 1 + d, 8, 0);
        await store().answer(d.isEven ? 'sea' : 'sunny');
      }
      final Object? days = await s.area('colour').get('days');
      expect((days! as List).length, keptColourDays);
      clock = DateTime(2026, 10, 21, 8, 0);
      final TodayColour t = await store().today();
      expect(t.carriedOver, isTrue);
      expect(t.colourId, isNotNull);
    });

    test('a refused write (bad art style) changes nothing on disk; an unreadable file starts fresh', () async {
      clock = DateTime(2026, 11, 7, 8, 0);
      final MemoryStoreBackend disk = MemoryStoreBackend();
      final LocalColourStore a = colour(_device(disk));
      expect((await a.saveArt(<String, dynamic>{'mood': 'x'})).ok, isFalse);
      disk.plant('child.ivy.colour', Uint8List.fromList(utf8.encode('{broken')));
      final LocalColourStore b = colour(_device(disk));
      expect((await b.today()).colourId, isNull, reason: 'quarantined, not a crash');
    });

    test('the shared store follows LocalServices.current and rebinds when the child changes', () async {
      clock = DateTime(2026, 11, 7, 8, 0);
      final MemoryStoreBackend disk = MemoryStoreBackend();
      final LocalColourStore shared = LocalColourStore.shared();
      LocalServices.install(_device(disk, child: 'ivy'));
      await shared.answer('sea');
      LocalServices.install(_device(disk, child: 'wren'));
      expect((await shared.today()).colourId, isNull, reason: 'wren does not inherit ivy\'s colour');
      LocalServices.install(_device(disk, child: 'ivy'));
      expect((await shared.today()).colourId, 'sea');
      expect(sharedColourStore, isA<ChildColourStore>());
      expect(sharedColourStore, isA<GuardianColourStore>());
    });
  });

  group('LocalStoreFamilyStore', () {
    test('an empty device loads an empty snapshot', () async {
      final LocalStoreFamilyStore s = LocalStoreFamilyStore(_device(MemoryStoreBackend()).area('family'));
      expect((await s.load()).records, isEmpty);
    });

    test('a saved snapshot round-trips, survives a restart, and is sealed on disk', () async {
      final MemoryStoreBackend disk = MemoryStoreBackend();
      final FamilySnapshot snap = _snap('Marigold Q.');
      await LocalStoreFamilyStore(_device(disk).area('family')).save(snap);
      final FamilySnapshot back = await LocalStoreFamilyStore(_device(disk).area('family')).load();
      expect(back.records.single.actorName, 'Marigold Q.');
      expect(utf8.decode(disk.rawFor('child.ivy.family')!, allowMalformed: true), isNot(contains('Marigold')));
    });

    test('a save that cannot be written THROWS: a change is never reported recorded when it was not', () async {
      final LocalServices s = _device(MemoryStoreBackend());
      final LocalNamespace tiny = s.store.open(const NamespaceSpec(name: 'child.tiny.family', encrypted: true, maxBytes: 20));
      final FamilySnapshot snap = _snap('x' * 100);
      await expectLater(LocalStoreFamilyStore(tiny).save(snap), throwsA(isA<LocalStoreFull>()));
    });

    test('an unreadable document loads as empty (quarantined)', () async {
      final MemoryStoreBackend disk = MemoryStoreBackend()
        ..plant('child.ivy.family', Uint8List.fromList(utf8.encode('garbage')));
      expect((await LocalStoreFamilyStore(_device(disk).area('family')).load()).records, isEmpty);
    });

    test('the shared service is durable and per child', () async {
      final MemoryStoreBackend disk = MemoryStoreBackend();
      LocalServices.install(_device(disk, child: 'ivy'));
      final FamilySnapshot snap = _snap('G');
      await LocalStoreFamilyStore.shared().save(snap);
      LocalServices.install(_device(disk, child: 'wren'));
      expect((await LocalStoreFamilyStore.shared().load()).records, isEmpty);
      LocalServices.install(_device(disk, child: 'ivy'));
      expect((await LocalStoreFamilyStore.shared().load()).records, hasLength(1));
    });
  });
}

FamilySnapshot _snap(String actor) => FamilySnapshot.fromJson(<String, Object?>{
      'records': <Object?>[
        <String, Object?>{
          'entry': <String, Object?>{'entry': 'release', 'id': 'h1', 'seq': 1, 'ref': 'c0'},
          'actorName': actor, 'createdOn': '2026-11-07',
        },
      ],
    });
