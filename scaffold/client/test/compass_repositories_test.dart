// OLIVE BRANCH — the Compass repository and service: restart survival, sealed at
// rest, per-child, size, guardian-only (every child and stranger call refused),
// the suites shelf reading each suite's OWN switch, and the profiles writing the
// existing accessibility settings and nothing else.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/access_settings.dart';
import 'package:olive_client/compass_logic.dart';
import 'package:olive_client/compass_repositories.dart';
import 'package:olive_client/family_structure_logic.dart';
import 'package:olive_client/growing_care_logic.dart';
import 'package:olive_client/growing_care_store.dart';
import 'package:olive_client/local_services.dart';
import 'package:olive_client/local_store.dart';
import 'package:olive_client/rhythm_voice_repositories.dart';
import 'package:olive_client/store_cipher.dart';
import 'package:olive_client/village_repositories.dart';

import 'village_support.dart';

const FamilyPrincipal stranger = FamilyPrincipal(roleName: 'sitter', userId: 'x');

class SuiteRig {
  SuiteRig() {
    rhythm = RhythmVoiceService.memory(childId: 'ivy');
    village = freshVillage();
    growing = GrowingCareStores.memory();
    ports = suitePortsFor(rhythmVoice: rhythm, village: village, growingCare: growing, principal: guardian);
  }
  late final RhythmVoiceService rhythm;
  late final VillageService village;
  late final GrowingCareStores growing;
  late final Map<String, SuitePort> ports;
}

CompassService service({SuiteRig? suites, MemoryAccessRepository? access}) => CompassService.memory(
    childId: 'ivy', access: access ?? MemoryAccessRepository(), ports: (suites ?? SuiteRig()).ports);

void main() {
  group('the document', () {
    test('answers and profiles round-trip; damage falls back on its own', () {
      final CompassDoc d = const CompassDoc(
          answers: CompassAnswers(who: <String>{'twoHomes'}, needs: <String>{'quiet'}), profiles: <String>{profileDeaf});
      final CompassDoc b = CompassDoc.fromJson(jsonDecode(jsonEncode(d.toJson())));
      expect(b.answers.who, <String>{'twoHomes'});
      expect(b.answers.needs, <String>{'quiet'});
      expect(b.profiles, <String>{profileDeaf});
      expect(CompassDoc.fromJson(null).profiles, isEmpty);
      expect(CompassDoc.fromJson(<String, Object?>{'profiles': <Object?>['nope', 5, 'awayFromHome']}).profiles, <String>{profileAway});
      expect(CompassDoc.fromJson(<String, Object?>{'profiles': 'x'}).profiles, isEmpty);
    });

    test('the stored shape is only ids: no score, no label about her, no free text', () {
      final String j = jsonEncode(CompassDoc(answers: all(), profiles: <String>{profileAway, profileDeaf}).toJson());
      expect(CompassDoc.fromJson(jsonDecode(j)).answers, all());
      for (final String banned in <String>['score', 'rank', 'level', 'diagnos', 'label', 'type', 'risk', 'count']) {
        expect(j.toLowerCase(), isNot(contains(banned)));
      }
      expect((jsonDecode(j) as Map<String, Object?>).keys.toSet(), <String>{'who', 'needs', 'profiles'});
    });
  });

  group('LocalStore-backed', () {
    test('survives a restart, sealed on the device, in its own per-child namespace', () async {
      final MemoryStoreBackend backend = MemoryStoreBackend();
      final StoreCipher cipher = AesGcmStoreCipher(AesGcmStoreCipher.newKey());
      LocalServices boot({String child = 'ivy'}) => LocalServices(store: LocalStore(backend: backend, cipher: cipher), childId: child);
      final CompassService first = CompassService.local(boot());
      await first.saveAnswers(guardian, const CompassAnswers(who: <String>{'twoHomes', 'loss'}, needs: <String>{'medical'}));
      await first.setProfile(guardian, profileDeaf, true);

      final CompassDoc d = await CompassService.local(boot()).load(guardian);
      expect(d.answers.who, <String>{'twoHomes', 'loss'});
      expect(d.answers.needs, <String>{'medical'});
      expect(d.profiles, <String>{profileDeaf});

      final String raw = utf8.decode(backend.rawFor('child.ivy.compass')!);
      expect(raw, contains('"enc":true'));
      for (final String leak in <String>['twoHomes', 'loss', 'medical', 'deafHoh']) {
        expect(raw, isNot(contains(leak)), reason: leak);
      }
      expect((await CompassService.local(boot(), childId: 'noah').load(guardian)).answers.isEmpty, isTrue, reason: 'another child has none of it');
    });

    test('a tiny ceiling refuses the write as "full" and keeps what was there', () async {
      final LocalStore store = LocalStore(backend: MemoryStoreBackend(), cipher: AesGcmStoreCipher(AesGcmStoreCipher.newKey()));
      final LocalStoreCompassRepository repo = LocalStoreCompassRepository(
          store.open(const NamespaceSpec(name: 'child.ivy.compass', encrypted: true, maxBytes: 120)));
      final CompassService svc = CompassService(childId: 'ivy', repo: repo, access: MemoryAccessRepository());
      expect((await svc.saveAnswers(guardian, const CompassAnswers(who: <String>{'twoHomes'}))).ok, isTrue);
      final CompassResult r = await svc.saveAnswers(guardian, all());
      expect(r.ok, isFalse);
      expect(r.reason, 'full');
      expect((await svc.load(guardian)).answers.who, <String>{'twoHomes'});
    });

    test('the largest legal document fits the catalogue ceiling by a wide margin', () {
      final int bytes = utf8.encode(jsonEncode(CompassDoc(answers: all(), profiles: <String>{profileAway, profileDeaf}).toJson())).length;
      expect(bytes, lessThan(localDataEntry('compass').maxBytes ~/ 8));
    });

    test('a damaged file loads as empty rather than stopping anything', () async {
      final MemoryStoreBackend backend = MemoryStoreBackend();
      final LocalServices s = LocalServices.memory(childId: 'ivy', backend: backend);
      final CompassService svc = CompassService.local(s);
      await svc.saveAnswers(guardian, all());
      await s.area('compass').put('doc', 'not a map');
      expect((await svc.load(guardian)).answers.isEmpty, isTrue);
    });

    test('"forget this child" removes it', () async {
      final LocalServices s = LocalServices.memory(childId: 'ivy');
      await CompassService.local(s).saveAnswers(guardian, all());
      await s.forgetChild('ivy');
      expect(await s.area('compass').list(), isEmpty);
    });
  });

  group('guardian only: every call by a child, a stranger or nobody is refused', () {
    test('reads throw and writes return guardian_only; nothing is stored', () async {
      final SuiteRig su = SuiteRig();
      final MemoryAccessRepository access = MemoryAccessRepository();
      final CompassService svc = service(suites: su, access: access);
      for (final FamilyPrincipal? p in <FamilyPrincipal?>[ivy, null, stranger, const FamilyPrincipal(), const FamilyPrincipal(roleName: 'guardian', userId: '')]) {
        await expectLater(svc.load(p), throwsA(isA<CompassRefused>()));
        await expectLater(svc.shelf(p), throwsA(isA<CompassRefused>()));
        await expectLater(svc.suggestions(p), throwsA(isA<CompassRefused>()));
        await expectLater(svc.profileOn(p, profileAway), throwsA(isA<CompassRefused>()));
        expect((await svc.saveAnswers(p, all())).reason, 'guardian_only');
        expect((await svc.forgetAnswers(p)).reason, 'guardian_only');
        expect((await svc.setSuite(p, 'rhythm', false)).reason, 'guardian_only');
        expect((await svc.setProfile(p, profileDeaf, true)).reason, 'guardian_only');
      }
      expect((await svc.load(guardian)).answers.isEmpty, isTrue);
      expect((await svc.load(guardian)).profiles, isEmpty);
      expect(access.saves, 0, reason: 'no accessibility setting was touched');
      expect((await su.rhythm.loadRhythm(guardian)).suiteOn, isTrue, reason: 'no suite switch was touched');
    });

    test('there is no child-side reader: no Compass type is reachable from the child shell', () {
      for (final String f in <String>['child_home', 'child_more', 'village_screens', 'village_sections', 'rhythm_screens', 'voice_screens']) {
        final String src = File('lib/$f.dart').readAsStringSync().replaceAll(RegExp(r'//.*'), '');
        for (final String banned in <String>['CompassService', 'CompassDoc', 'compass_repositories', 'compass_screens', 'CompassAnswers']) {
          expect(src.contains(banned), isFalse, reason: '$f must not reference $banned');
        }
      }
      expect(const CompassRefused('x').toString(), contains('x'));
    });
  });

  group('answers and suggestions through the service', () {
    test('save, read back, suggest from what is saved, forget', () async {
      final CompassService svc = service();
      expect((await svc.saveAnswers(guardian, const CompassAnswers(who: <String>{'twoHomes'}))).ok, isTrue);
      expect((await svc.suggestions(guardian)).map((Suggestion s) => s.key), <String>['rhythm']);
      expect((await svc.forgetAnswers(guardian)).ok, isTrue);
      expect(await svc.suggestions(guardian), isEmpty);
    });

    test('forgetting the answers leaves the profiles and the suites exactly as they were', () async {
      final SuiteRig su = SuiteRig();
      final CompassService svc = service(suites: su);
      await svc.saveAnswers(guardian, all());
      await svc.setProfile(guardian, profileAway, true);
      await svc.setSuite(guardian, 'voice', false);
      await svc.forgetAnswers(guardian);
      expect((await svc.load(guardian)).profiles, <String>{profileAway});
      expect((await su.rhythm.loadVoice(guardian)).suiteOn, isFalse);
    });

    test('saving the answers is just the ids: an unknown id sneaked in is dropped', () async {
      final CompassService svc = service();
      await svc.saveAnswers(guardian, const CompassAnswers(who: <String>{'twoHomes', 'made-up'}));
      expect((await svc.load(guardian)).answers.who, <String>{'twoHomes'});
    });

    test('a suggestion changes NOTHING by itself: no suite switch moves until a guardian sets it', () async {
      final SuiteRig su = SuiteRig();
      final CompassService svc = service(suites: su);
      await su.rhythm.setVoiceSuite(guardian, false);
      await svc.saveAnswers(guardian, all());
      await svc.suggestions(guardian);
      expect((await su.rhythm.loadVoice(guardian)).suiteOn, isFalse);
      expect((await svc.shelf(guardian)).firstWhere((ShelfRow r) => r.suite.key == 'voice').on, isFalse);
    });
  });

  group('the suites shelf', () {
    test('five rows in a fixed order, each with what it adds; on by default as each suite already is', () async {
      final List<ShelfRow> rows = await service().shelf(guardian);
      expect(rows.map((ShelfRow r) => r.suite.key), suiteKeysOnShelf);
      expect(rows.every((ShelfRow r) => r.on), isTrue);
      for (final ShelfRow r in rows) {
        expect(r.suite.adds.length, greaterThan(20));
      }
    });

    test('it carries no usage: a row is a suite and an on/off, never a count, a date or a score', () {
      for (final ShelfSuite s in shelfSuites) {
        expect('${s.title} ${s.adds}', isNot(matches(RegExp(r'\d'))), reason: s.key);
        expect('${s.title} ${s.adds}'.toLowerCase(), isNot(matches(RegExp(r'\bused\b|\buse\b|streak|score|\blast\b|how often|how many|opened'))), reason: s.key);
      }
    });

    test('switching a row flips the SUITE\'S OWN switch, and a change made on the suite shows on the shelf', () async {
      final SuiteRig su = SuiteRig();
      final CompassService svc = service(suites: su);
      expect((await svc.setSuite(guardian, 'rhythm', false)).ok, isTrue);
      expect((await su.rhythm.loadRhythm(guardian)).suiteOn, isFalse);
      expect((await svc.setSuite(guardian, 'voice', false)).ok, isTrue);
      expect((await su.rhythm.loadVoice(guardian)).suiteOn, isFalse);
      expect((await svc.setSuite(guardian, 'village', false)).ok, isTrue);
      expect((await su.village.loadForGuardian(guardian)).suiteOn, isFalse);
      // and the other way round: the suite's own page changes it, the shelf agrees
      await su.rhythm.setRhythmSuite(guardian, true);
      await su.village.setSuite(guardian, true);
      final Map<String, bool> on = <String, bool>{for (final ShelfRow r in await svc.shelf(guardian)) r.suite.key: r.on};
      expect(on['rhythm'], isTrue);
      expect(on['village'], isTrue);
      expect(on['voice'], isFalse);
    });

    test('Growing and Care are groups of four: off turns all four off, and the row is on while any one is on', () async {
      final SuiteRig su = SuiteRig();
      final CompassService svc = service(suites: su);
      await svc.setSuite(guardian, 'growing', false);
      final SuiteSwitches sw = await su.growing.switches.load();
      for (final String k in growingSuiteKeys) {
        expect(sw.on(k), isFalse, reason: k);
      }
      for (final String k in careSuiteKeys) {
        expect(sw.on(k), isTrue, reason: k);
      }
      expect((await svc.shelf(guardian)).firstWhere((ShelfRow r) => r.suite.key == 'growing').on, isFalse);
      await su.growing.switches.setSuite('memoryBox', true);
      expect((await svc.shelf(guardian)).firstWhere((ShelfRow r) => r.suite.key == 'growing').on, isTrue);
      await svc.setSuite(guardian, 'growing', true);
      expect((await su.growing.switches.load()).on('timeCapsule'), isTrue);
      await svc.setSuite(guardian, 'care', false);
      for (final String k in careSuiteKeys) {
        expect((await su.growing.switches.load()).on(k), isFalse, reason: k);
      }
    });

    test('an unknown suite, or one with no port, is refused', () async {
      final CompassService svc = service();
      expect((await svc.setSuite(guardian, 'nope', true)).reason, 'unknown_suite');
      expect((await CompassService.memory(childId: 'ivy').setSuite(guardian, 'rhythm', true)).reason, 'unknown_suite');
    });

    test('a shelf wired for the wrong principal refuses to read rather than guess "on"', () async {
      final Map<String, SuitePort> ports = suitePortsFor(
          rhythmVoice: RhythmVoiceService.memory(childId: 'ivy'), village: freshVillage(), growingCare: GrowingCareStores.memory(), principal: ivy);
      await expectLater(CompassService.memory(childId: 'ivy', ports: ports).shelf(guardian), throwsA(isA<CompassRefused>()));
    });

    test('with no ports wired the shelf still lists the suites (on, as they start)', () async {
      final List<ShelfRow> rows = await CompassService.memory(childId: 'ivy').shelf(guardian);
      expect(rows.length, 5);
    });

    test('a suite switch that cannot be saved is reported, not hidden', () async {
      final FamilyPrincipal wrong = ivy; // a port built for a child principal is refused by the suite itself
      final Map<String, SuitePort> ports = suitePortsFor(
          rhythmVoice: RhythmVoiceService.memory(childId: 'ivy'), village: freshVillage(), growingCare: GrowingCareStores.memory(), principal: wrong);
      final CompassService svc = CompassService.memory(childId: 'ivy', ports: ports);
      expect((await svc.setSuite(guardian, 'rhythm', false)).reason, 'guardian_only');
      expect((await svc.setSuite(guardian, 'village', false)).reason, 'guardian_only');
    });
  });

  group('the profiles', () {
    test('on writes the profile\'s defaults over the accessibility settings and records the flag', () async {
      final MemoryAccessRepository access = MemoryAccessRepository(const AccessSettings(largerTargets: true));
      final CompassService svc = service(access: access);
      expect((await svc.setProfile(guardian, profileDeaf, true)).ok, isTrue);
      final AccessSettings a = await access.load();
      expect(a.readAloud, isFalse);
      expect(a.roomierReading, isTrue);
      expect(a.captions, isTrue);
      expect(a.visualAlerts, isTrue);
      expect(a.largerTargets, isTrue, reason: 'her other choice is kept');
      expect(await svc.profileOn(guardian, profileDeaf), isTrue);
      expect(await svc.profileOn(guardian, profileAway), isFalse);
    });

    test('off clears the flag and leaves the settings exactly where they are', () async {
      final MemoryAccessRepository access = MemoryAccessRepository();
      final CompassService svc = service(access: access);
      await svc.setProfile(guardian, profileAway, true);
      final AccessSettings atOn = await access.load();
      final int saves = access.saves;
      expect((await svc.setProfile(guardian, profileAway, false)).ok, isTrue);
      expect(await access.load(), atOn);
      expect(access.saves, saves, reason: 'turning it off writes no setting');
      expect(await svc.profileOn(guardian, profileAway), isFalse);
    });

    test('both together compose, and the guardian can still change one setting afterwards', () async {
      final MemoryAccessRepository access = MemoryAccessRepository();
      final CompassService svc = service(access: access);
      await svc.setProfile(guardian, profileAway, true);
      await svc.setProfile(guardian, profileDeaf, true);
      final AccessSettings a = await access.load();
      expect(a.reduceMotion, isTrue);
      expect(a.visualAlerts, isTrue);
      expect(a.readAloud, isFalse, reason: 'the later profile wins on the one setting they share');
      await access.save(a.copyWith(readAloud: true));
      expect((await access.load()).readAloud, isTrue);
      expect(await svc.profileOn(guardian, profileDeaf), isTrue);
    });

    test('an unknown profile is refused and changes nothing', () async {
      final MemoryAccessRepository access = MemoryAccessRepository();
      final CompassService svc = service(access: access);
      expect((await svc.setProfile(guardian, 'nope', true)).reason, 'unknown_profile');
      expect(access.saves, 0);
      expect((await svc.load(guardian)).profiles, isEmpty);
    });

    test('if the accessibility setting cannot be saved the flag is not set either, and it says why', () async {
      final MemoryAccessRepository access = MemoryAccessRepository()..failSaves = true;
      final CompassService svc = service(access: access);
      final CompassResult r = await svc.setProfile(guardian, profileDeaf, true);
      expect(r.ok, isFalse);
      expect(r.reason, 'full');
      expect(await svc.profileOn(guardian, profileDeaf), isFalse);
    });

    test('a profile touches ONLY the accessibility settings: the shelf, the answers and every suite are as they were', () async {
      final SuiteRig su = SuiteRig();
      final CompassService svc = service(suites: su);
      await svc.saveAnswers(guardian, all());
      final List<bool> before = <bool>[for (final ShelfRow r in await svc.shelf(guardian)) r.on];
      await su.rhythm.savePersonalSymbols(guardian, <String>['sym-owl']);
      await svc.setProfile(guardian, profileDeaf, true);
      await svc.setProfile(guardian, profileAway, true);
      expect(<bool>[for (final ShelfRow r in await svc.shelf(guardian)) r.on], before);
      expect((await svc.load(guardian)).answers, all());
      expect((await su.rhythm.loadVoice(guardian)).personalSymbols, <String>['sym-owl']);
      expect((await su.village.loadForGuardian(guardian)).stories, isEmpty);
    });

    test('through the real store the visible-alerts flag reaches her readable settings', () async {
      final LocalServices s = LocalServices.memory(childId: 'ivy');
      final CompassService svc = CompassService.local(s);
      await svc.setProfile(guardian, profileDeaf, true);
      final AccessSettings read = await LocalStoreAccessRepository(s.area('access')).load();
      expect(read.visualAlerts, isTrue);
      expect(read.readAloud, isFalse);
    });
  });

  group('what the family builder already shows', () {
    tearDown(LocalServices.resetForTest);

    test('an empty builder gives no hints, and the read is guardian-only', () async {
      LocalServices.install(LocalServices.memory(childId: 'ivy'));
      expect(await builderHintsFor(guardian, 6), isEmpty);
      await expectLater(builderHintsFor(ivy, 6), throwsA(anything));
    });
  });
}

CompassAnswers all() => CompassAnswers(
    who: <String>{for (final CompassOption o in compassWhoOptions) o.id},
    needs: <String>{for (final CompassOption o in compassNeedsOptions) o.id});
