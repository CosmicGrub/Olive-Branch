// No longer UNVERIFIED — verified by CI (this file). OLIVE BRANCH — the
// accessibility settings model, its repository (memory and LocalStore) and the
// controller. MASTERFILE §8.4, §8.8.5, §8.21.
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/access_settings.dart';
import 'package:olive_client/local_services.dart';
import 'package:olive_client/local_store.dart';

void main() {
  group('AccessSettings', () {
    test('defaults: everything off, read-aloud follows her age', () {
      const AccessSettings s = AccessSettings.defaults;
      expect(s.readAloud, isNull);
      expect(s.reduceMotion, isFalse);
      expect(s.roomierReading, isFalse);
      expect(s.largerTargets, isFalse);
      expect(s.captions, isFalse);
    });

    test('read-aloud with no guardian choice is on below 8 and off from 8 (and on if age unknown)', () {
      const AccessSettings s = AccessSettings.defaults;
      expect(s.readAloudFor(5), isTrue);
      expect(s.readAloudFor(7), isTrue);
      expect(s.readAloudFor(8), isFalse);
      expect(s.readAloudFor(11), isFalse);
      expect(s.readAloudFor(null), isTrue);
    });

    test('an explicit guardian choice beats her age, both ways', () {
      expect(const AccessSettings(readAloud: false).readAloudFor(5), isFalse);
      expect(const AccessSettings(readAloud: true).readAloudFor(11), isTrue);
    });

    test('clearReadAloud hands the choice back to her age', () {
      final AccessSettings s = const AccessSettings(readAloud: false).copyWith(clearReadAloud: true);
      expect(s.readAloud, isNull);
      expect(s.readAloudFor(5), isTrue);
    });

    test('captions are not built: the wish is recorded but nothing is active', () {
      expect(captionsBuilt, isFalse);
      const AccessSettings s = AccessSettings(captions: true);
      expect(s.captions, isTrue);
      expect(s.captionsActive, isFalse);
    });

    test('JSON round-trips every field, including an absent read-aloud choice', () {
      const AccessSettings a = AccessSettings(
          readAloud: true, reduceMotion: true, roomierReading: true, largerTargets: true, captions: true);
      expect(AccessSettings.fromJson(a.toJson()), a);
      const AccessSettings b = AccessSettings(reduceMotion: true);
      expect(b.toJson().containsKey('readAloud'), isFalse);
      expect(AccessSettings.fromJson(b.toJson()), b);
    });

    test('fromJson is tolerant: junk becomes defaults, wrong-typed fields become defaults', () {
      expect(AccessSettings.fromJson(null), AccessSettings.defaults);
      expect(AccessSettings.fromJson('x'), AccessSettings.defaults);
      expect(AccessSettings.fromJson(<String, Object?>{'reduceMotion': 'yes', 'readAloud': 3}),
          AccessSettings.defaults);
    });

    test('stores only booleans: no score, streak or counter can be in the document (P2)', () {
      final Map<String, Object?> j = const AccessSettings(
              readAloud: true, reduceMotion: true, roomierReading: true, largerTargets: true, captions: true)
          .toJson();
      expect(j.values.every((Object? v) => v is bool), isTrue);
      expect(j.length, 5);
    });
  });

  group('target floors', () {
    test('child 64 (80 larger), guardian 48 (64 larger)', () {
      expect(childTargetFor(AccessSettings.defaults), 64);
      expect(childTargetFor(const AccessSettings(largerTargets: true)), 80);
      expect(guardianTargetFor(AccessSettings.defaults), 48);
      expect(guardianTargetFor(const AccessSettings(largerTargets: true)), 64);
    });
  });

  group('MemoryAccessRepository', () {
    test('saves and loads', () async {
      final MemoryAccessRepository r = MemoryAccessRepository();
      await r.save(const AccessSettings(reduceMotion: true));
      expect((await r.load()).reduceMotion, isTrue);
    });
  });

  group('LocalStoreAccessRepository', () {
    late LocalServices services;
    setUp(() => services = LocalServices.memory(childId: 'kid-1'));
    tearDown(LocalServices.resetForTest);

    test('survives a restart: a second repository over the same store reads it', () async {
      final MemoryStoreBackend backend = MemoryStoreBackend();
      final LocalServices a = LocalServices.memory(childId: 'kid-1', backend: backend);
      await LocalStoreAccessRepository(a.area('access'))
          .save(const AccessSettings(roomierReading: true, readAloud: false));
      final LocalServices b = LocalServices.memory(childId: 'kid-1', backend: backend);
      final AccessSettings got = await LocalStoreAccessRepository(b.area('access')).load();
      expect(got.roomierReading, isTrue);
      expect(got.readAloud, isFalse);
    });

    test('is namespaced per child: one child\'s choices never reach another', () async {
      await LocalStoreAccessRepository(services.area('access', ownerId: 'kid-1'))
          .save(const AccessSettings(largerTargets: true));
      final AccessSettings other =
          await LocalStoreAccessRepository(services.area('access', ownerId: 'kid-2')).load();
      expect(other, AccessSettings.defaults);
      expect(services.namespaceName(localDataEntry('access')), 'child.kid-1.access');
    });

    test('is in the data catalogue, per child, and not encrypted (five booleans, nothing private)', () {
      final LocalDataEntry e = localDataEntry('access');
      expect(e.scope, LocalScope.child);
      expect(e.encrypted, isFalse);
      expect(e.maxBytes, lessThanOrEqualTo(64 * 1024));
    });

    test('an unreadable document falls back to defaults instead of failing', () async {
      final LocalNamespace ns = services.area('access');
      await ns.put('settings', 'not a map');
      expect(await LocalStoreAccessRepository(ns).load(), AccessSettings.defaults);
    });

    test('shared() follows LocalServices.current', () async {
      LocalServices.install(services);
      final LocalStoreAccessRepository r = LocalStoreAccessRepository.shared();
      await r.save(const AccessSettings(reduceMotion: true));
      expect((await LocalStoreAccessRepository(services.area('access')).load()).reduceMotion, isTrue);
    });
  });

  group('AccessController', () {
    test('load publishes what was kept, and notifies', () async {
      final AccessController c = AccessController(
          repository: MemoryAccessRepository(const AccessSettings(reduceMotion: true)));
      int notified = 0;
      c.addListener(() => notified++);
      expect(c.loaded, isFalse);
      await c.load();
      expect(c.loaded, isTrue);
      expect(c.value.reduceMotion, isTrue);
      expect(notified, 1);
    });

    test('update applies at once, notifies, and keeps it', () async {
      final MemoryAccessRepository r = MemoryAccessRepository();
      final AccessController c = AccessController(repository: r);
      await c.load();
      int notified = 0;
      c.addListener(() => notified++);
      final bool kept = await c.update((AccessSettings s) => s.copyWith(largerTargets: true));
      expect(kept, isTrue);
      expect(c.value.largerTargets, isTrue);
      expect(notified, 1);
      expect((await r.load()).largerTargets, isTrue);
    });

    test('an unchanged update does not notify or save', () async {
      final MemoryAccessRepository r = MemoryAccessRepository();
      final AccessController c = AccessController(repository: r);
      await c.load();
      int notified = 0;
      c.addListener(() => notified++);
      expect(await c.update((AccessSettings s) => s), isTrue);
      expect(notified, 0);
      expect(r.saves, 0);
    });

    test('a save that fails still takes effect for this run, and says it was not kept', () async {
      final MemoryAccessRepository r = MemoryAccessRepository()..failSaves = true;
      final AccessController c = AccessController(repository: r);
      await c.load();
      final bool kept = await c.update((AccessSettings s) => s.copyWith(reduceMotion: true));
      expect(kept, isFalse);
      expect(c.value.reduceMotion, isTrue);
    });
  });
}
