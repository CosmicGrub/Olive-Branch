// OLIVE BRANCH — the repositories behind suites B and C: in-memory and
// LocalStore-backed, restart survival, encryption, size bounds, per-child
// namespacing, and the catalogue entries (so the wipe screen and docs list them).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/local_services.dart';
import 'package:olive_client/local_store.dart';
import 'package:olive_client/rhythm_logic.dart';
import 'package:olive_client/rhythm_voice_repositories.dart';
import 'package:olive_client/store_cipher.dart';
import 'package:olive_client/voice_logic.dart';

const String day = '2026-11-08';

RhythmDoc sampleRhythm() => RhythmDoc(
      routine: addStep(addStep(const Routine(title: 'Bedtime'), newStep('a', 'bath')), newStep('b', 'book')),
      board: makeBoard(boardCard('bath'), boardCard('play')),
      packing: addPackItem(const PackingList(), newPackItem('o', 'owl')),
      sensory: const SensoryProfile(sound: SoundLevel.low, reduceMotion: true, brightnessCeiling: 60),
    );

PlacePlan samplePlace() => makePlan('Dad\'s', <PlaceStop>[newStop('s', 'door', 'The door')], <String>['We arrive']);

void main() {
  group('in-memory repositories', () {
    test('each one starts empty and returns what it was given, without aliasing', () async {
      final MemoryRhythmRepository r = MemoryRhythmRepository();
      expect((await r.load()).routine, isNull);
      await r.save(sampleRhythm());
      expect((await r.load()).routine!.title, 'Bedtime');
      expect((await r.load()).sensory.brightnessCeiling, 60);

      final MemoryNewPlaceRepository p = MemoryNewPlaceRepository();
      expect(await p.load(), isNull);
      await p.save(samplePlace());
      expect((await p.load())!.name, 'Dad\'s');
      await p.save(null);
      expect(await p.load(), isNull);

      final MemoryVoiceRepository v = MemoryVoiceRepository();
      expect((await v.load()).helpers, isEmpty);
      await v.save(VoiceDoc(helpers: <Helper>[makeHelper(id: 'h', name: 'Nana', picture: 'grandparent', saidYes: true)]));
      expect((await v.load()).helpers.single.name, 'Nana');

      final MemoryFeelingsRepository f = MemoryFeelingsRepository();
      expect(await f.load(), isNull);
      await f.save(pickWeather('sunny', day));
      expect((await f.load())!.weather, 'sunny');
      await f.save(null);
      expect(await f.load(), isNull);

      final MemoryWorryRepository w = MemoryWorryRepository();
      expect(await w.load(), isEmpty);
      await w.save(<Worry>[Worry.picture(id: 'a', picture: 'worry-dark', madeOn: day)]);
      expect((await w.load()).single.id, 'a');
    });
  });

  group('LocalStore-backed repositories: survive a restart', () {
    test('everything written is there after a brand-new LocalServices over the same files', () async {
      final MemoryStoreBackend backend = MemoryStoreBackend();
      final AesGcmKeyHolder key = AesGcmKeyHolder();
      LocalServices boot() => key.services(backend);

      final RhythmVoiceService first = RhythmVoiceService.local(boot());
      await first.rhythm.save(sampleRhythm());
      await first.place.save(samplePlace());
      await first.voice.save(VoiceDoc(
          helpers: <Helper>[makeHelper(id: 'h', name: 'Nana', picture: 'grandparent', saidYes: true)],
          personalSymbols: const <String>['sym-owl']));
      await first.feelings.save(pickWeather('stormy', day));
      await first.worries.save(<Worry>[
        Worry.picture(id: 'a', picture: 'worry-dark', madeOn: day, shown: true),
        Worry.drawing(id: 'b', strokes: <List<double>>[<double>[0.1, 0.2, 0.3, 0.4]], madeOn: day),
      ]);

      final RhythmVoiceService second = RhythmVoiceService.local(boot());
      final RhythmDoc r = await second.rhythm.load();
      expect(r.routine!.steps.map((RoutineStep s) => s.id), <String>['a', 'b']);
      expect(r.board!.then.picture, 'play');
      expect(r.packing.items.single.id, 'o');
      expect(r.sensory.sound, SoundLevel.low);
      expect(r.sensory.reduceMotion, isTrue);
      expect((await second.place.load())!.plan, <String>['We arrive']);
      final VoiceDoc v = await second.voice.load();
      expect(v.helpers.single.saidYes, isTrue);
      expect(v.personalSymbols, <String>['sym-owl']);
      expect((await second.feelings.load())!.weather, 'stormy');
      final List<Worry> box = await second.worries.load();
      expect(box.map((Worry w) => w.id), <String>['a', 'b']);
      expect(box.first.shown, isTrue);
      expect(box.last.strokes, <List<double>>[<double>[0.1, 0.2, 0.3, 0.4]]);
    });

    test('a real directory backend keeps it across a restart too', () async {
      final Directory dir = await Directory.systemTemp.createTemp('olive_rv_test_');
      addTearDown(() => dir.delete(recursive: true));
      final AesGcmKeyHolder key = AesGcmKeyHolder();
      LocalServices boot() => LocalServices(
          store: LocalStore(backend: DirectoryStoreBackend(dir), cipher: key.cipher), childId: 'ivy');
      await RhythmVoiceService.local(boot()).rhythm.save(sampleRhythm());
      await RhythmVoiceService.local(boot()).feelings.save(pickWeather('foggy', day));
      expect((await RhythmVoiceService.local(boot()).rhythm.load()).routine!.title, 'Bedtime');
      expect((await RhythmVoiceService.local(boot()).feelings.load())!.weather, 'foggy');
      expect(File('${dir.path}${Platform.pathSeparator}child.ivy.feelings.json').readAsStringSync(), isNot(contains('foggy')));
    });

    test('removing a place or clearing the weather really deletes the key', () async {
      final LocalServices s = LocalServices.memory(childId: 'ivy');
      final RhythmVoiceService svc = RhythmVoiceService.local(s);
      await svc.place.save(samplePlace());
      await svc.feelings.save(pickWeather('sunny', day));
      await svc.worries.save(<Worry>[Worry.picture(id: 'a', picture: 'worry-dark', madeOn: day)]);
      await svc.place.save(null);
      await svc.feelings.save(null);
      await svc.worries.save(const <Worry>[]);
      expect(await s.area('newplace').list(), isEmpty);
      expect(await s.area('feelings').list(), isEmpty);
      expect(await s.area('worries').list(), isEmpty);
    });
  });

  group('private data is encrypted at rest', () {
    test('feelings and worries are sealed; plaintext never reaches the disk', () async {
      final MemoryStoreBackend backend = MemoryStoreBackend();
      final LocalServices s = LocalServices.memory(childId: 'ivy', backend: backend);
      final RhythmVoiceService svc = RhythmVoiceService.local(s);
      await svc.feelings.save(pickWeather('stormy', day));
      await svc.worries.save(<Worry>[
        Worry.picture(id: 'a', picture: 'worry-dark', madeOn: day, shown: true),
        Worry.drawing(id: 'b', strokes: <List<double>>[<double>[0.123, 0.456, 0.789, 0.321]], madeOn: day),
      ]);
      for (final String area in <String>['feelings', 'worries']) {
        final Uint8List raw = backend.rawFor('child.ivy.$area')!;
        final String text = utf8.decode(raw);
        expect(text, contains('"enc":true'), reason: area);
        for (final String leak in <String>['stormy', 'worry-dark', '0.123', '0.456', 'shown', 'strokes']) {
          expect(text, isNot(contains(leak)), reason: '$area leaked $leak');
        }
      }
      expect(localDataEntry('feelings').encrypted, isTrue);
      expect(localDataEntry('worries').encrypted, isTrue);
    });

    test('a plaintext file planted in a private area is never read as data', () async {
      final MemoryStoreBackend backend = MemoryStoreBackend();
      final LocalServices s = LocalServices.memory(childId: 'ivy', backend: backend);
      backend.plant(
          'child.ivy.worries',
          Uint8List.fromList(utf8.encode(jsonEncode(<String, Object?>{
            'olive_store': 1, 'schema': 1, 'enc': false,
            'data': <String, Object?>{'box': <Object?>[<String, Object?>{'id': 'x', 'kind': 'picture', 'picture': 'worry-dark', 'madeOn': day, 'shown': true}]},
          }))));
      expect(await RhythmVoiceService.local(s).worries.load(), isEmpty);
      expect(await s.store.quarantined(), 1);
    });

    test('the guardian-authored areas are not encrypted, and say so in the catalogue', () {
      for (final String a in <String>['rhythm', 'newplace', 'voice']) {
        expect(localDataEntry(a).encrypted, isFalse, reason: a);
      }
    });
  });

  group('per-child namespacing', () {
    test('one child\'s data is never reachable through another\'s', () async {
      final LocalServices s = LocalServices.memory(childId: 'ivy');
      final RhythmVoiceService ivy = RhythmVoiceService.local(s, childId: 'ivy');
      final RhythmVoiceService leo = RhythmVoiceService.local(s, childId: 'leo');
      await ivy.rhythm.save(sampleRhythm());
      await ivy.worries.save(<Worry>[Worry.picture(id: 'a', picture: 'worry-dark', madeOn: day)]);
      expect((await leo.rhythm.load()).routine, isNull);
      expect(await leo.worries.load(), isEmpty);
      expect(await s.store.namespaces(), containsAll(<String>['child.ivy.rhythm', 'child.ivy.worries']));
      expect((await s.store.namespaces()).any((String n) => n.contains('leo')), isFalse);
      expect(leo.childId, 'leo');
    });

    test('forgetting a child removes every Rhythm and Voice area for her', () async {
      final LocalServices s = LocalServices.memory(childId: 'ivy');
      final RhythmVoiceService svc = RhythmVoiceService.local(s);
      await svc.rhythm.save(sampleRhythm());
      await svc.place.save(samplePlace());
      await svc.voice.save(const VoiceDoc(personalSymbols: <String>['sym-owl']));
      await svc.feelings.save(pickWeather('sunny', day));
      await svc.worries.save(<Worry>[Worry.picture(id: 'a', picture: 'worry-dark', madeOn: day)]);
      expect((await s.store.namespaces()).length, 5);
      await s.forgetChild('ivy');
      expect(await s.store.namespaces(), isEmpty);
    });

    test('a live build cannot scope these areas to the demo child', () {
      final LocalServices live = LocalServices.memory(childId: 'ivy', isLive: true);
      expect(() => RhythmVoiceService.local(live, childId: 'demo-child'), throwsStateError);
    });

    test('the shared service rebinds when the installed store or child changes', () {
      LocalServices.install(LocalServices.memory(childId: 'ivy'));
      addTearDown(() {
        RhythmVoiceService.resetShared();
        LocalServices.resetForTest();
      });
      final RhythmVoiceService a = RhythmVoiceService.forChild(null);
      expect(a.childId, 'ivy');
      expect(identical(RhythmVoiceService.forChild(null), a), isTrue);
      expect(identical(RhythmVoiceService.forChild('leo'), a), isFalse);
      expect(RhythmVoiceService.forChild('leo').childId, 'leo');
      LocalServices.install(LocalServices.memory(childId: 'ivy'));
      expect(identical(RhythmVoiceService.forChild('ivy'), a), isFalse, reason: 'a new store needs a new service');
    });
  });

  group('size bounds', () {
    test('a place too big for its area is refused and leaves what was there untouched', () async {
      final LocalServices s = LocalServices.memory(childId: 'ivy');
      final RhythmVoiceService svc = RhythmVoiceService.local(s);
      await svc.place.save(samplePlace());
      // Eight stops, each with the largest allowed photo: a real plan CAN fit...
      final List<int> jpeg = <int>[0xFF, 0xD8, ...List<int>.filled(maxPhotoBytes - 2, 7)];
      final PlacePlan big = makePlan('Big', <PlaceStop>[for (int i = 0; i < maxPlaceStops; i++) newStop('s$i', 'door', 'door', photoBytes: jpeg)], const <String>[]);
      final int bytes = utf8.encode(jsonEncode(big.toJson())).length;
      expect(bytes, lessThan(localDataEntry('newplace').maxBytes), reason: 'the area is sized for the largest legal plan');
    });

    test('a tiny ceiling refuses the write with LocalStoreFull and keeps the old data', () async {
      final LocalStore store = LocalStore(backend: MemoryStoreBackend());
      final LocalNamespace ns = store.open(const NamespaceSpec(name: 'child.ivy.newplace', maxBytes: 600));
      final LocalStoreNewPlaceRepository repo = LocalStoreNewPlaceRepository(ns);
      await repo.save(samplePlace());
      final PlacePlan huge = makePlan('Huge', <PlaceStop>[
        for (int i = 0; i < maxPlaceStops; i++) newStop('s$i', 'door', 'x' * 50),
      ], <String>['y' * 60, 'y' * 60]);
      await expectLater(repo.save(huge), throwsA(isA<LocalStoreFull>()));
      expect((await repo.load())!.name, 'Dad\'s', reason: 'the stored plan is untouched');
    });

    test('the worry box area holds the largest legal box (24 worries, every drawing at every limit)', () async {
      final List<Worry> box = <Worry>[
        for (int i = 0; i < maxWorries; i++)
          Worry.drawing(id: 'w$i', madeOn: day, strokes: <List<double>>[
            for (int s = 0; s < maxStrokes; s++) List<double>.filled(maxPointsPerStroke * 2, 0.999),
          ]),
      ];
      final int bytes = utf8.encode(jsonEncode(<Object?>[for (final Worry w in box) w.toJson()])).length;
      expect(bytes, lessThan(localDataEntry('worries').maxBytes));
      final RhythmVoiceService svc = RhythmVoiceService.local(LocalServices.memory(childId: 'ivy'));
      await svc.worries.save(box);
      expect((await svc.worries.load()).length, maxWorries);
    });

    test('limits agree with the catalogue: nothing here can silently grow without bound', () {
      for (final String a in <String>['rhythm', 'newplace', 'voice', 'feelings', 'worries']) {
        final LocalDataEntry e = localDataEntry(a);
        expect(e.maxBytes, greaterThan(0));
        expect(e.maxBytes, lessThanOrEqualTo(4 * 1024 * 1024), reason: a);
      }
    });
  });

  group('damage is safe, never fatal', () {
    test('a corrupt document is quarantined and every repository loads as empty', () async {
      final MemoryStoreBackend backend = MemoryStoreBackend();
      final LocalServices s = LocalServices.memory(childId: 'ivy', backend: backend);
      for (final String a in <String>['rhythm', 'newplace', 'voice', 'feelings', 'worries']) {
        backend.plant('child.ivy.$a', Uint8List.fromList(utf8.encode('not json at all')));
      }
      final RhythmVoiceService svc = RhythmVoiceService.local(s);
      expect((await svc.rhythm.load()).routine, isNull);
      expect(await svc.place.load(), isNull);
      expect((await svc.voice.load()).helpers, isEmpty);
      expect(await svc.feelings.load(), isNull);
      expect(await svc.worries.load(), isEmpty);
      expect(await s.store.quarantined(), 5, reason: 'kept for recovery, not deleted');
    });

    test('wrong-shaped stored values load as empty, not as a crash', () async {
      final LocalServices s = LocalServices.memory(childId: 'ivy');
      await s.area('rhythm').put('doc', 'a string');
      await s.area('worries').put('box', <String, Object?>{'not': 'a list'});
      await s.area('feelings').put('today', <String, Object?>{'weather': 'ecstatic', 'day': day});
      final RhythmVoiceService svc = RhythmVoiceService.local(s);
      expect((await svc.rhythm.load()).routine, isNull);
      expect(await svc.worries.load(), isEmpty);
      expect(await svc.feelings.load(), isNull);
    });
  });

  group('what is stored is documented, and lists no score, streak or count (P2)', () {
    test('all five areas are in the catalogue, in plain words, with the right scope', () {
      for (final String a in <String>['rhythm', 'newplace', 'voice', 'feelings', 'worries']) {
        final LocalDataEntry e = localDataEntry(a);
        expect(e.scope, LocalScope.child, reason: a);
        expect(e.what.length, greaterThan(60), reason: a);
        expect(describeLocalData(), contains(a));
      }
      expect(localDataCatalogue.map((LocalDataEntry e) => e.area).toSet().length, localDataCatalogue.length);
    });

    test('the catalogue text says what is NOT kept, and nothing is shared', () {
      expect(localDataEntry('rhythm').what.toLowerCase(), contains('no score, streak or count'));
      expect(localDataEntry('rhythm').what.toLowerCase(), contains('nothing is shared'));
      expect(localDataEntry('newplace').what.toLowerCase(), contains('no address'));
      expect(localDataEntry('voice').what.toLowerCase(), contains('never kept'));
      expect(localDataEntry('feelings').what.toLowerCase(), contains('no history'));
      expect(localDataEntry('worries').what.toLowerCase(), contains('never read'));
      expect(localDataEntry('worries').what.toLowerCase(), contains('no score'));
    });

    test('MASTERFILE documents every one of these areas (no drift)', () {
      final String doc = File('../../MASTERFILE.md').readAsStringSync();
      for (final String a in <String>['rhythm', 'newplace', 'voice', 'feelings', 'worries']) {
        expect(doc, contains('`child.<id>.$a`'), reason: 'MASTERFILE is missing the $a area');
      }
    });

    test('the stored documents never contain a counter, score, streak or rank', () async {
      final LocalServices s = LocalServices.memory(childId: 'ivy');
      final RhythmVoiceService svc = RhythmVoiceService.local(s);
      await svc.rhythm.save(sampleRhythm().copyWith(routineTicks: const DayTicks(day: day, done: <String>['a'])));
      await svc.voice.save(const VoiceDoc(personalSymbols: <String>['sym-owl']));
      await svc.feelings.save(pickWeather('sunny', day));
      await svc.worries.save(<Worry>[Worry.picture(id: 'a', picture: 'worry-dark', madeOn: day)]);
      for (final String a in <String>['rhythm', 'voice', 'feelings', 'worries']) {
        final LocalNamespace ns = s.area(a);
        for (final String k in await ns.list()) {
          final String j = jsonEncode(await ns.get(k)).toLowerCase();
          for (final String bad in <String>['count', 'score', 'streak', 'total', 'points', 'rank', 'level', 'reward']) {
            expect(j.contains('"$bad'), isFalse, reason: '$a/$k has a "$bad" field');
          }
        }
      }
    });
  });
}

/// Builds LocalServices that share one backend AND one encryption key, which is
/// what a restart looks like (the key lives in the keystore, not the files).
class AesGcmKeyHolder {
  AesGcmKeyHolder() : cipher = AesGcmStoreCipher(AesGcmStoreCipher.newKey());
  final StoreCipher cipher;
  LocalServices services(MemoryStoreBackend backend, {String childId = 'ivy'}) =>
      LocalServices(store: LocalStore(backend: backend, cipher: cipher), childId: childId);
}
