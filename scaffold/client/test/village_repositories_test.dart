// OLIVE BRANCH — the repositories and the guarded service behind suite D:
// in-memory and LocalStore-backed, restart survival, sealed at rest, size bounds,
// per-child namespaces, the catalogue entries, and WHO may do WHAT (every deny
// path is a real assertion).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/family_structure_logic.dart';
import 'package:olive_client/local_services.dart';
import 'package:olive_client/local_store.dart';
import 'package:olive_client/rhythm_logic.dart';
import 'package:olive_client/store_cipher.dart';
import 'package:olive_client/village_logic.dart';
import 'package:olive_client/village_repositories.dart';

import 'village_support.dart';

/// Services that share one backend AND one key: what a restart looks like.
class _Keep {
  _Keep() : cipher = AesGcmStoreCipher(AesGcmStoreCipher.newKey());
  final StoreCipher cipher;
  LocalServices boot(MemoryStoreBackend b, {String childId = 'ivy'}) =>
      LocalServices(store: LocalStore(backend: b, cipher: cipher), childId: childId);
}

const FamilyPrincipal sib = FamilyPrincipal(roleName: 'child', childId: 'leo');
const FamilyPrincipal anon = FamilyPrincipal();
const FamilyPrincipal emptyGuardian = FamilyPrincipal(roleName: 'guardian', userId: '');

Future<VillageService> authored() async {
  final VillageService s = freshVillage();
  expect((await s.saveGrandCorner(guardian, sampleGrand())).ok, isTrue);
  expect((await s.saveStory(guardian, sampleStory(id: 'held'))).ok, isTrue);
  expect((await s.saveStory(guardian, sampleStory(id: 'out'))).ok, isTrue);
  expect((await s.releaseStory(guardian, 'out')).ok, isTrue);
  expect((await s.saveSiblings(guardian, sampleSiblings())).ok, isTrue);
  expect((await s.setFace(guardian, 'p1', 'grandparent')).ok, isTrue);
  expect((await s.saveSitterPass(guardian, sampleSitter())).ok, isTrue);
  expect((await s.saveSchoolBridge(guardian, sampleSchool())).ok, isTrue);
  return s;
}

void main() {
  group('in-memory repositories', () {
    test('start empty, return what they were given, never alias', () async {
      final MemoryVillageRepository v = MemoryVillageRepository();
      expect((await v.load()).grand, isNull);
      expect((await v.load()).suiteOn, isTrue);
      await v.save(VillageDoc(grand: sampleGrand(), stories: <WelcomeStory>[sampleStory()]));
      final VillageDoc a = await v.load();
      expect(a.grand!.name, 'Nana');
      expect(identical(a, await v.load()), isFalse);

      final MemoryPassesRepository p = MemoryPassesRepository();
      expect((await p.load()).sitter, isNull);
      await p.save(PassesDoc(sitter: sampleSitter(), school: sampleSchool()));
      expect((await p.load()).school!.school, 'Oak Primary');
    });
  });

  group('LocalStore-backed: survive a restart', () {
    test('everything written is there after a brand-new LocalServices over the same files', () async {
      final MemoryStoreBackend backend = MemoryStoreBackend();
      final _Keep keep = _Keep();
      final VillageService first = VillageService.local(keep.boot(backend), clock: () => DateTime(2026, 11, 8));
      await first.saveGrandCorner(guardian, sampleGrand());
      await first.saveStory(guardian, sampleStory());
      await first.releaseStory(guardian, 's1');
      await first.saveSiblings(guardian, sampleSiblings());
      await first.setFace(guardian, 'p1', 'friend');
      await first.leavePicture(ivy, 'b1', 'teddy');
      await first.saveSitterPass(guardian, sampleSitter());
      await first.saveSchoolBridge(guardian, sampleSchool());
      await first.setSuite(guardian, false);

      final VillageService second = VillageService.local(keep.boot(backend));
      final VillageDoc d = await second.loadForGuardian(guardian);
      expect(d.suiteOn, isFalse);
      expect(d.grand!.cards.map((GrandCard c) => c.id), <String>['g1', 'g2']);
      expect(d.stories.single.releasedOn, '2026-11-08');
      expect(d.shelf.siblings.length, 2);
      expect(d.shelf.notesFor('b1').single.picture, 'teddy');
      expect(d.faces, <String, String>{'p1': 'friend'});
      final PassesDoc p = await second.loadPasses(guardian);
      expect(p.sitter!.allergies, <String>['Cashews (written by Mom)']);
      expect(p.sitter!.writtenOn, '2026-11-08');
      expect(p.school!.pickup, <String>['Mom or Nana']);
    });

    test('a real directory backend keeps it across a restart too', () async {
      final Directory dir = await Directory.systemTemp.createTemp('olive_village_test_');
      addTearDown(() => dir.delete(recursive: true));
      final _Keep keep = _Keep();
      LocalServices boot() => LocalServices(store: LocalStore(backend: DirectoryStoreBackend(dir), cipher: keep.cipher), childId: 'ivy');
      await VillageService.local(boot()).saveSitterPass(guardian, sampleSitter());
      await VillageService.local(boot()).saveStory(guardian, sampleStory());
      expect((await VillageService.local(boot()).loadPasses(guardian)).sitter!.title, 'Friday evening');
      expect((await VillageService.local(boot()).loadForGuardian(guardian)).stories.single.title, 'A new day');
      final String raw = File('${dir.path}${Platform.pathSeparator}child.ivy.passes.json').readAsStringSync();
      expect(raw, isNot(contains('Cashews')));
      expect(raw, isNot(contains('555')));
    });

    test('clearing a pass really removes it', () async {
      final VillageService s = VillageService.local(LocalServices.memory(childId: 'ivy'));
      await s.saveSitterPass(guardian, sampleSitter());
      await s.saveSitterPass(guardian, null);
      expect((await s.loadPasses(guardian)).sitter, isNull);
      await s.saveGrandCorner(guardian, sampleGrand());
      await s.saveGrandCorner(guardian, null);
      expect((await s.loadForGuardian(guardian)).grand, isNull);
    });
  });

  group('sealed at rest', () {
    test('plaintext of a story, an allergy or a number never reaches the disk', () async {
      final MemoryStoreBackend backend = MemoryStoreBackend();
      final LocalServices s = LocalServices.memory(childId: 'ivy', backend: backend);
      final VillageService svc = VillageService.local(s);
      await svc.saveStory(guardian, sampleStory());
      await svc.saveGrandCorner(guardian, sampleGrand());
      await svc.saveSitterPass(guardian, sampleSitter());
      await svc.saveSchoolBridge(guardian, sampleSchool());
      for (final String area in <String>['village', 'passes']) {
        final String text = utf8.decode(backend.rawFor('child.ivy.$area')!);
        expect(text, contains('"enc":true'), reason: area);
        for (final String leak in <String>['We open the door', 'Cashews', '555 0142', '555 0199', 'Oak Primary', 'Nana', 'Aunt Mia']) {
          expect(text, isNot(contains(leak)), reason: '$area leaks $leak');
        }
      }
    });
  });

  group('per-child namespaces', () {
    test('one child\'s village is never reachable through another\'s name', () async {
      final MemoryStoreBackend backend = MemoryStoreBackend();
      final _Keep keep = _Keep();
      final LocalServices ivySvc = keep.boot(backend);
      await VillageService.local(ivySvc).saveStory(guardian, sampleStory());
      await VillageService.local(ivySvc).saveSitterPass(guardian, sampleSitter());
      final VillageService other = VillageService.local(ivySvc, childId: 'noah');
      expect((await other.loadForGuardian(guardian)).stories, isEmpty);
      expect((await other.loadPasses(guardian)).sitter, isNull);
      expect(ivySvc.namespaceName(localDataEntry('village'), ownerId: 'ivy'), 'child.ivy.village');
      expect(ivySvc.namespaceName(localDataEntry('passes'), ownerId: 'noah'), 'child.noah.passes');
    });

    test('"forget this child" removes both areas', () async {
      final LocalServices s = LocalServices.memory(childId: 'ivy');
      final VillageService svc = VillageService.local(s);
      await svc.saveStory(guardian, sampleStory());
      await svc.saveSitterPass(guardian, sampleSitter());
      await s.forgetChild('ivy');
      expect(await s.area('village').list(), isEmpty);
      expect(await s.area('passes').list(), isEmpty);
    });
  });

  group('size bounds', () {
    test('a tiny ceiling refuses the write with LocalStoreFull and keeps the old data', () async {
      final LocalStore store = LocalStore(backend: MemoryStoreBackend(), cipher: AesGcmStoreCipher(AesGcmStoreCipher.newKey()));
      final LocalNamespace ns = store.open(const NamespaceSpec(name: 'child.ivy.passes', encrypted: true, maxBytes: 700));
      final LocalStorePassesRepository repo = LocalStorePassesRepository(ns);
      await repo.save(PassesDoc(sitter: makeSitterPass(allergies: const <String>['Peanuts'])));
      final PassesDoc huge = PassesDoc(sitter: makeSitterPass(
          routine: List<String>.filled(maxPassLines, 'r' * maxPassLineChars), notes: List<String>.filled(maxPassLines, 'n' * maxPassLineChars)));
      await expectLater(repo.save(huge), throwsA(isA<LocalStoreFull>()));
      expect((await repo.load()).sitter!.allergies, <String>['Peanuts'], reason: 'the old document is untouched');
    });

    test('the service words a full box as "full" and never says saved', () async {
      final LocalStore store = LocalStore(backend: MemoryStoreBackend(), cipher: AesGcmStoreCipher(AesGcmStoreCipher.newKey()));
      final VillageService svc = VillageService(
          childId: 'ivy',
          village: LocalStoreVillageRepository(store.open(const NamespaceSpec(name: 'child.ivy.village', encrypted: true, maxBytes: 120))),
          passes: LocalStorePassesRepository(store.open(const NamespaceSpec(name: 'child.ivy.passes', encrypted: true, maxBytes: 120))));
      final VillageResult r = await svc.saveStory(guardian, sampleStory());
      expect(r.ok, isFalse);
      expect(r.reason, 'full');
      final VillageResult p = await svc.saveSitterPass(guardian, sampleSitter());
      expect(p.reason, 'full');
    });

    test('the catalogue ceilings are the ones the maximal documents were sized for', () {
      expect(localDataEntry('village').maxBytes, 128 * 1024);
      expect(localDataEntry('passes').maxBytes, 64 * 1024);
      expect(localDataEntry('village').encrypted, isTrue);
      expect(localDataEntry('passes').encrypted, isTrue);
    });
  });

  group('the catalogue and the docs', () {
    test('village, passes and compass are catalogued, sealed, child-scoped and in plain words', () {
      for (final String a in <String>['village', 'passes', 'compass']) {
        final LocalDataEntry e = localDataEntry(a);
        expect(e.scope, LocalScope.child, reason: a);
        expect(e.encrypted, isTrue, reason: a);
        expect(e.what.length, greaterThan(60), reason: a);
        expect(describeLocalData(), contains(a));
      }
      expect(localDataEntry('village').what.toLowerCase(), contains('nothing is sent'));
      expect(localDataEntry('village').what.toLowerCase(), contains('no count or score'));
      expect(localDataEntry('passes').what.toLowerCase(), contains('never in her app'));
      expect(localDataEntry('passes').what.toLowerCase(), contains('no school or sitter is ever contacted'));
      expect(localDataEntry('compass').what.toLowerCase(), contains('no score'));
      expect(localDataCatalogue.map((LocalDataEntry e) => e.area).toSet().length, localDataCatalogue.length);
    });

    test('MASTERFILE documents every one of these areas (no drift)', () {
      final String doc = File('../../MASTERFILE.md').readAsStringSync();
      for (final String a in <String>['village', 'passes', 'compass']) {
        expect(doc, contains('`child.<id>.$a`'), reason: 'MASTERFILE is missing the $a area');
      }
    });

    test('the stored documents never contain a counter, score, streak or rank', () async {
      final LocalServices s = LocalServices.memory(childId: 'ivy');
      final VillageService svc = VillageService.local(s, clock: () => DateTime(2026, 11, 8));
      await svc.saveGrandCorner(guardian, sampleGrand());
      await svc.saveStory(guardian, sampleStory());
      await svc.saveSiblings(guardian, sampleSiblings());
      await svc.leavePicture(ivy, 'b1', 'teddy');
      await svc.saveSitterPass(guardian, sampleSitter());
      await svc.saveSchoolBridge(guardian, sampleSchool());
      for (final String a in <String>['village', 'passes']) {
        final LocalNamespace ns = s.area(a);
        for (final String k in await ns.list()) {
          final String j = jsonEncode(await ns.get(k)).toLowerCase();
          for (final String banned in <String>['score', 'streak', 'rank', 'points', 'stars', 'count', 'total', 'badge', 'reward', 'level']) {
            expect(j, isNot(contains('"$banned')), reason: '$a/$k has $banned');
          }
        }
      }
    });

    test('a damaged file is quarantined and loads as empty rather than stopping the shell', () async {
      final MemoryStoreBackend backend = MemoryStoreBackend();
      final _Keep keep = _Keep();
      await VillageService.local(keep.boot(backend)).saveStory(guardian, sampleStory());
      await backend.writeAtomic('child.ivy.village', Uint8List.fromList(utf8.encode('not json at all')));
      final VillageService again = VillageService.local(keep.boot(backend));
      expect((await again.loadForGuardian(guardian)).stories, isEmpty);
      expect((await again.saveStory(guardian, sampleStory())).ok, isTrue, reason: 'and it can be written again');
      expect(await backend.quarantineCount(), greaterThan(0), reason: 'the damaged copy was kept aside, not lost');
    });
  });

  group('who may do what: guardian-only writes', () {
    test('a child principal cannot write anything guardian-authored (guardian_only), and nothing is stored', () async {
      final VillageService s = freshVillage();
      final List<VillageResult> all = <VillageResult>[
        await s.setSuite(ivy, false),
        await s.saveGrandCorner(ivy, sampleGrand()),
        await s.saveStory(ivy, sampleStory()),
        await s.releaseStory(ivy, 's1'),
        await s.holdStory(ivy, 's1'),
        await s.removeStory(ivy, 's1'),
        await s.saveSiblings(ivy, sampleSiblings()),
        await s.clearShelfPictures(ivy),
        await s.setFace(ivy, 'p1', 'friend'),
        await s.saveSitterPass(ivy, sampleSitter()),
        await s.saveSchoolBridge(ivy, sampleSchool()),
      ];
      for (final VillageResult r in all) {
        expect(r.ok, isFalse);
        expect(r.reason, 'guardian_only');
      }
      expect((await s.loadForGuardian(guardian)).grand, isNull);
      expect((await s.loadForGuardian(guardian)).stories, isEmpty);
      expect((await s.loadPasses(guardian)).sitter, isNull);
    });

    test('no principal, an unnamed guardian and a guardian-less role are refused too', () async {
      final VillageService s = freshVillage();
      for (final FamilyPrincipal? p in <FamilyPrincipal?>[null, anon, emptyGuardian, const FamilyPrincipal(roleName: 'sitter', userId: 'x')]) {
        expect((await s.saveSitterPass(p, sampleSitter())).reason, 'guardian_only');
        expect((await s.saveStory(p, sampleStory())).reason, 'guardian_only');
      }
    });

    test('the sitter pass and school summary have NO child reader: every child and stranger read is refused', () async {
      final VillageService s = await authored();
      for (final FamilyPrincipal? p in <FamilyPrincipal?>[ivy, sib, null, anon]) {
        await expectLater(s.loadPasses(p), throwsA(isA<RvRefused>().having((RvRefused e) => e.reason, 'reason', 'guardian_only')));
        await expectLater(s.loadForGuardian(p), throwsA(isA<RvRefused>()));
      }
      expect((await s.loadPasses(guardian)).sitter!.title, 'Friday evening');
    });

    test('the child lens exposes no pass, grandparent page or held story', () async {
      final VillageService s = await authored();
      final List<WelcomeStory> shown = await s.releasedStories(ivy);
      expect(shown.map((WelcomeStory x) => x.id), <String>['out']);
      final String everything = jsonEncode(<Object?>[
        shown.map((WelcomeStory x) => x.toJson()).toList(), (await s.shelf(ivy)).siblings.map((SiblingSlot x) => x.toJson()).toList(), await s.faces(ivy),
      ]);
      for (final String secret in <String>['Cashews', '555', 'Oak Primary', 'Nana', 'held', 'Aunt Mia']) {
        expect(everything, isNot(contains(secret)), reason: secret);
      }
    });

    test('a guardian cannot use the child-side actions', () async {
      final VillageService s = await authored();
      expect((await s.leavePicture(guardian, 'b1', 'teddy')).reason, 'child_only');
      expect((await s.takeDownPicture(guardian, 'x')).reason, 'child_only');
      await expectLater(s.releasedStories(guardian), throwsA(isA<RvRefused>()));
      await expectLater(s.faces(guardian), throwsA(isA<RvRefused>()));
      await expectLater(s.shelf(guardian), throwsA(isA<RvRefused>()));
    });

    test('another child\'s principal cannot read or write this child\'s village', () async {
      final VillageService s = await authored();
      await expectLater(s.releasedStories(sib), throwsA(isA<RvRefused>()));
      expect((await s.leavePicture(sib, 'b1', 'teddy')).reason, 'child_only');
      expect((await s.takeDownPicture(sib, 'x')).reason, 'child_only');
    });
  });

  group('story release', () {
    test('held until a guardian releases it; the child side never sees a held story', () async {
      final VillageService s = freshVillage();
      await s.saveStory(guardian, sampleStory());
      expect(await s.releasedStories(ivy), isEmpty);
      expect((await s.releaseStory(guardian, 's1')).ok, isTrue);
      expect((await s.releasedStories(ivy)).single.releasedOn, day);
      expect((await s.holdStory(guardian, 's1')).ok, isTrue);
      expect(await s.releasedStories(ivy), isEmpty);
    });

    test('editing a released story holds it again', () async {
      final VillageService s = freshVillage();
      await s.saveStory(guardian, sampleStory());
      await s.releaseStory(guardian, 's1');
      await s.saveStory(guardian, sampleStory(title: 'A new day, edited'));
      final VillageDoc d = await s.loadForGuardian(guardian);
      expect(d.stories.single.title, 'A new day, edited');
      expect(d.stories.single.released, isFalse);
      expect(await s.releasedStories(ivy), isEmpty);
    });

    test('an edit keeps its place in the list', () async {
      final VillageService s = freshVillage();
      await s.saveStory(guardian, sampleStory(id: 'a', title: 'A'));
      await s.saveStory(guardian, sampleStory(id: 'b', title: 'B'));
      await s.saveStory(guardian, sampleStory(id: 'a', title: 'A2'));
      expect((await s.loadForGuardian(guardian)).stories.map((WelcomeStory x) => x.title), <String>['A2', 'B']);
    });

    test('releasing or holding a story that is not there is refused; at most three stories', () async {
      final VillageService s = freshVillage();
      expect((await s.releaseStory(guardian, 'nope')).reason, 'unknown_story');
      expect((await s.holdStory(guardian, 'nope')).reason, 'unknown_story');
      for (int i = 0; i < 3; i++) {
        expect((await s.saveStory(guardian, sampleStory(id: 's$i'))).ok, isTrue);
      }
      expect((await s.saveStory(guardian, sampleStory(id: 's9'))).reason, 'too_many_stories');
      expect((await s.saveStory(guardian, sampleStory(id: 's1', title: 'again'))).ok, isTrue, reason: 'replacing is not adding');
      expect((await s.removeStory(guardian, 's0')).ok, isTrue);
      expect((await s.saveStory(guardian, sampleStory(id: 's9'))).ok, isTrue);
    });

    test('a story with a bad page is refused and nothing is stored', () async {
      final VillageService s = freshVillage();
      final VillageResult r = await s.saveStory(guardian,
          const WelcomeStory(id: 'x', title: 'T', pages: <StoryPage>[StoryPage(picture: 'worry-dark', text: 'No')]));
      expect(r.reason, 'bad_page');
      expect((await s.loadForGuardian(guardian)).stories, isEmpty);
    });

    test('with the suite off, her side reads nothing at all', () async {
      final VillageService s = await authored();
      await s.setSuite(guardian, false);
      expect(await s.releasedStories(ivy), isEmpty);
      expect(await s.faces(ivy), isEmpty);
      expect((await s.shelf(ivy)).siblings, isEmpty);
      expect((await s.leavePicture(ivy, 'b1', 'teddy')).reason, 'suite_off');
      expect((await s.takeDownPicture(ivy, 'x')).reason, 'suite_off');
      expect(await s.suiteOn(ivy), isFalse);
      expect((await s.loadPasses(guardian)).sitter, isNotNull, reason: 'the grown-up pages are not switched off by her switch');
    });
  });

  group('the sibling shelf through the service', () {
    test('she leaves a picture and takes it down; nobody else can', () async {
      final VillageService s = freshVillage();
      await s.saveSiblings(guardian, sampleSiblings());
      expect((await s.leavePicture(ivy, 'b1', 'teddy')).ok, isTrue);
      final ShelfNote n = (await s.shelf(ivy)).notesFor('b1').single;
      expect(n.picture, 'teddy');
      expect((await s.takeDownPicture(ivy, n.id)).ok, isTrue);
      expect((await s.shelf(ivy)).notes, isEmpty);
    });

    test('a picture outside the kit, or for nobody, is refused and stores nothing', () async {
      final VillageService s = freshVillage();
      await s.saveSiblings(guardian, sampleSiblings());
      expect((await s.leavePicture(ivy, 'b1', 'worry-dark')).reason, 'bad_picture');
      expect((await s.leavePicture(ivy, 'zz', 'teddy')).reason, 'unknown_sibling');
      expect((await s.shelf(ivy)).notes, isEmpty);
    });

    test('ids are fresh each time, so two pictures never collide', () async {
      final VillageService s = freshVillage();
      await s.saveSiblings(guardian, sampleSiblings());
      await s.leavePicture(ivy, 'b1', 'teddy');
      await s.leavePicture(ivy, 'b1', 'owl');
      final List<ShelfNote> ns = (await s.shelf(ivy)).notesFor('b1');
      expect(ns.length, 2);
      expect(ns.map((ShelfNote x) => x.id).toSet().length, 2);
    });

    test('a guardian can take every picture down, and removing a sibling removes theirs', () async {
      final VillageService s = freshVillage();
      await s.saveSiblings(guardian, sampleSiblings());
      await s.leavePicture(ivy, 'b1', 'teddy');
      await s.leavePicture(ivy, 'b2', 'owl');
      await s.saveSiblings(guardian, <SiblingSlot>[sampleSiblings().first]);
      expect((await s.shelf(ivy)).notes.map((ShelfNote n) => n.toId), <String>['b1']);
      expect((await s.clearShelfPictures(guardian)).ok, isTrue);
      expect((await s.shelf(ivy)).notes, isEmpty);
      expect((await s.shelf(ivy)).siblings.length, 1);
    });
  });

  group('faces', () {
    test('a face is a person-group picture; clearing puts back the plain initial; at most 24', () async {
      final VillageService s = freshVillage();
      expect((await s.setFace(guardian, 'p1', 'bath')).reason, 'bad_picture');
      expect((await s.setFace(guardian, 'p 1', 'friend')).reason, 'bad_id');
      expect((await s.setFace(guardian, 'p1', 'friend')).ok, isTrue);
      expect((await s.faces(ivy))['p1'], 'friend');
      expect((await s.setFace(guardian, 'p1', null)).ok, isTrue);
      expect(await s.faces(ivy), isEmpty);
      for (int i = 0; i < maxFaces; i++) {
        expect((await s.setFace(guardian, 'q$i', 'friend')).ok, isTrue);
      }
      expect((await s.setFace(guardian, 'extra', 'friend')).reason, 'too_many_faces');
      expect((await s.setFace(guardian, 'q0', 'grandparent')).ok, isTrue, reason: 'changing one is not adding one');
    });
  });

  group('passes through the service', () {
    test('saving stamps the day the guardian wrote it, from the clock', () async {
      final VillageService s = freshVillage();
      await s.saveSitterPass(guardian, sampleSitter().copyWith(writtenOn: '1999-01-01'));
      expect((await s.loadPasses(guardian)).sitter!.writtenOn, day, reason: 'the clock, not the caller, says when');
      await s.saveSchoolBridge(guardian, sampleSchool());
      expect((await s.loadPasses(guardian)).school!.writtenOn, day);
    });

    test('a bad pass is refused with a stable reason and the old one is kept', () async {
      final VillageService s = freshVillage();
      await s.saveSitterPass(guardian, sampleSitter());
      final VillageResult r = await s.saveSitterPass(guardian, const SitterPass(contacts: <PassContact>[PassContact(id: 'c', name: 'A', number: 'soon')]));
      expect(r.reason, 'bad_contact');
      expect((await s.loadPasses(guardian)).sitter!.title, 'Friday evening');
      expect((await s.saveSchoolBridge(guardian, const SchoolBridge(school: '9 Oak Road'))).reason, 'looks_like_location');
      expect((await s.loadPasses(guardian)).school, isNull);
    });

    test('saving one pass leaves the other alone', () async {
      final VillageService s = await authored();
      await s.saveSitterPass(guardian, null);
      expect((await s.loadPasses(guardian)).school!.school, 'Oak Primary');
      await s.saveSchoolBridge(guardian, null);
      expect((await s.loadPasses(guardian)).school, isNull);
    });
  });

  group('the grandparent page through the service', () {
    test('a bad corner is refused; a good one saves and clears', () async {
      final VillageService s = freshVillage();
      expect((await s.saveGrandCorner(guardian, const GrandCorner(phone: PhoneLine(who: 'Mom', number: 'x')))).reason, 'bad_number');
      expect((await s.loadForGuardian(guardian)).grand, isNull);
      expect((await s.saveGrandCorner(guardian, sampleGrand())).ok, isTrue);
      expect((await s.loadForGuardian(guardian)).grand!.phone!.who, 'Mom');
    });
  });

  group('the shared instance', () {
    tearDown(() {
      VillageService.resetShared();
      LocalServices.resetForTest();
    });

    test('forChild follows LocalServices.current and re-binds when the child changes', () {
      final LocalServices a = LocalServices.memory(childId: 'ivy');
      LocalServices.install(a);
      final VillageService one = VillageService.forChild('ivy');
      expect(identical(one, VillageService.forChild('ivy')), isTrue);
      expect(identical(one, VillageService.forChild('noah')), isFalse);
      expect(VillageService.forChild('noah').childId, 'noah');
    });
  });
}
