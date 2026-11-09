// OLIVE BRANCH — LocalServices tests: scoping per child and guardian, the
// 'demo-child' refusal in live builds, the data catalogue as the single source
// of truth, and a real restart on a real directory.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/device_identity.dart';
import 'package:olive_client/local_services.dart';
import 'package:olive_client/local_store.dart';
import 'package:olive_client/store_cipher.dart';

class _MemorySecure implements SecureKeyValueStore {
  final Map<String, String> data = <String, String>{};
  @override
  Future<String?> read(String key) async => data[key];
  @override
  Future<void> write(String key, String value) async => data[key] = value;
  @override
  Future<void> delete(String key) async => data.remove(key);
}

void main() {
  group('scopeId', () {
    test('uuids and the app\'s own ids pass through untouched', () {
      expect(scopeId('aaaaaaaa-0000-4000-8000-000000000001'), 'aaaaaaaa-0000-4000-8000-000000000001');
      expect(scopeId('ivy'), 'ivy');
    });

    test('anything unsafe is made safe AND stays distinct from every other id', () {
      final String a = scopeId('Ivy/../x');
      final String b = scopeId('ivy-..-x');
      final String c = scopeId('IVY');
      for (final String s in <String>[a, b, c]) {
        expect(isValidNamespaceName('child.$s.journal'), isTrue, reason: s);
      }
      expect(<String>{a, b, c}.length, 3, reason: 'a hash suffix keeps different ids apart');
      expect(scopeId(''), isNot(isEmpty));
    });
  });

  group('scoping', () {
    test('two children on one device never see each other\'s data', () async {
      final LocalServices s = LocalServices.memory(childId: 'ivy');
      await s.area('lists', ownerId: 'ivy').put('wants', <Object?>['bike']);
      await s.area('lists', ownerId: 'wren').put('wants', <Object?>['kite']);
      expect(await s.area('lists', ownerId: 'ivy').get('wants'), <Object?>['bike']);
      expect(await s.area('lists', ownerId: 'wren').get('wants'), <Object?>['kite']);
      expect(s.namespaceName(localDataEntry('lists'), ownerId: 'wren'), 'child.wren.lists');
    });

    test('child, guardian and device areas are named for their owner', () {
      final LocalServices s = LocalServices.memory(childId: 'ivy', guardianId: 'mom');
      expect(s.namespaceName(localDataEntry('journal')), 'child.ivy.journal');
      expect(s.namespaceName(localDataEntry('learn')), 'guardian.mom.learn');
      expect(s.namespaceName(localDataEntry('learn'), ownerId: 'dad'), 'guardian.dad.learn');
    });

    test('forgetting one child profile leaves the other', () async {
      final LocalServices s = LocalServices.memory(childId: 'ivy');
      await s.area('lists', ownerId: 'ivy').put('wants', <Object?>['a']);
      await s.area('journal', ownerId: 'ivy').put('e', 'x');
      await s.area('lists', ownerId: 'wren').put('wants', <Object?>['b']);
      await s.forgetChild('ivy');
      expect(await s.area('lists', ownerId: 'ivy').get('wants'), isNull);
      expect(await s.area('journal', ownerId: 'ivy').get('e'), isNull);
      expect(await s.area('lists', ownerId: 'wren').get('wants'), <Object?>['b']);
    });

    test('a LIVE build refuses the literal demo-child scope, everywhere', () {
      expect(() => LocalServices.memory(childId: 'demo-child', isLive: true), throwsStateError);
      final LocalServices live = LocalServices.memory(childId: 'real-child', isLive: true, demoSeeds: false);
      expect(() => live.area('lists', ownerId: 'demo-child'), throwsStateError);
      expect(() => live.scopeChild('demo-child'), throwsStateError);
      // The preview (not live) may still use it.
      expect(LocalServices.memory(childId: 'demo-child').scopeChild(), 'demo-child');
    });

    test('an area that is not in the catalogue cannot be opened', () {
      expect(() => LocalServices.memory().area('secret-stash'), throwsArgumentError);
    });
  });

  group('the data catalogue is the single source of truth', () {
    test('every area opens as a valid namespace with its declared encryption and ceiling', () {
      final LocalServices s = LocalServices.memory(childId: 'ivy', guardianId: 'mom');
      for (final LocalDataEntry e in localDataCatalogue) {
        final LocalNamespace ns = s.area(e.area);
        expect(isValidNamespaceName(ns.spec.name), isTrue, reason: e.area);
        expect(ns.spec.encrypted, e.encrypted, reason: e.area);
        expect(ns.spec.maxBytes, e.maxBytes, reason: e.area);
      }
    });

    test('areas are unique and every one says in words what it keeps', () {
      final List<String> areas = localDataCatalogue.map((LocalDataEntry e) => e.area).toList();
      expect(areas.toSet().length, areas.length);
      for (final LocalDataEntry e in localDataCatalogue) {
        expect(e.what.length, greaterThan(20), reason: e.area);
      }
    });

    test('the private areas are encrypted: the journal (P7) and all of Parent Learn', () {
      expect(localDataEntry('journal').encrypted, isTrue);
      expect(localDataEntry('learn').encrypted, isTrue);
    });

    test('no area stores a score, streak, count, rank or price (P2/P4)', () {
      final String all = describeLocalData().toLowerCase();
      // Each area's text may only mention these to say they are NOT stored.
      for (final LocalDataEntry e in localDataCatalogue) {
        final String t = e.what.toLowerCase();
        for (final String bad in <String>['streak', 'score', 'ranking', 'leaderboard', 'badge', 'price']) {
          if (t.contains(bad)) {
            expect(t, contains('no '),
                reason: '${e.area} mentions "$bad" without saying it is not stored');
          }
        }
      }
      expect(all, contains('journal'));
    });

    test('the only device-wide areas are the role and the three device pairing records; coordinates are never a field (P3)', () {
      // Owner requirement 2026-11-08: the role is kept once per device and holds one word. The pairing records
      // (2026-11-08, section 8.5.11) are the only other areas not owned by a child or a grown-up: a signing
      // key, the certificate a grown-up's device signed, and a PIN verifier. All sealed, all small, no PIN.
      final List<LocalDataEntry> device =
          localDataCatalogue.where((LocalDataEntry e) => e.scope == LocalScope.device).toList();
      expect(device.map((LocalDataEntry e) => e.area).toList(),
          <String>['role', 'devicekey', 'childpairing', 'adultunlock']);
      for (final LocalDataEntry e in device) {
        expect(e.maxBytes, lessThanOrEqualTo(8 * 1024));
        if (e.area != 'role') expect(e.encrypted, isTrue, reason: '${e.area} is sealed');
      }
      expect(device.first.what.toLowerCase(), contains('not a name'));
      expect(describeLocalData().toLowerCase(), isNot(contains('location')));
    });

    test('the role, the local family and the local PIN are catalogued; the family and PIN are sealed', () {
      expect(localDataEntry('role').scope, LocalScope.device);
      expect(localDataEntry('localfamily').scope, LocalScope.guardian);
      expect(localDataEntry('localfamily').encrypted, isTrue);
      expect(localDataEntry('localpin').scope, LocalScope.guardian);
      expect(localDataEntry('localpin').encrypted, isTrue);
      final LocalServices s = LocalServices.memory(childId: 'ivy', guardianId: 'mom');
      expect(s.namespaceName(localDataEntry('role')), 'device.role');
      expect(s.namespaceName(localDataEntry('localfamily'), ownerId: 'local-guardian'),
          'guardian.local-guardian.localfamily');
    });
  });

  group('boot on a real directory: a genuine restart', () {
    test('data, sealed data and the key all survive; a wipe removes data AND key', () async {
      final Directory dir = await Directory.systemTemp.createTemp('olive_services_test_');
      addTearDown(() => dir.delete(recursive: true));
      final _MemorySecure secure = _MemorySecure();

      final LocalServices first =
          await LocalServices.boot(childId: 'ivy', guardianId: 'mom', isLive: true, secure: secure, rootOverride: dir);
      expect(LocalServices.current, same(first));
      expect(first.demoSeeds, isFalse, reason: 'a live build starts with no invented content');
      await first.area('lists').put('wants', <Object?>['bike']);
      await first.area('journal').put('e1', <String, Object?>{'body': 'private words'});
      await first.area('learn').put('settings', <String, Object?>{'reflection': 'saved'});
      expect(secure.data.keys, contains(StoreCipherKeyring.keyName));

      // The "restart": a brand-new LocalServices over the same files and the same keystore.
      final LocalServices second =
          await LocalServices.boot(childId: 'ivy', guardianId: 'mom', isLive: true, secure: secure, rootOverride: dir);
      expect(await second.area('lists').get('wants'), <Object?>['bike']);
      expect(await second.area('journal').get('e1'), <String, Object?>{'body': 'private words'});
      expect(await second.area('learn').get('settings'), <String, Object?>{'reflection': 'saved'});

      // The files really are sealed on disk.
      final String raw = File('${dir.path}${Platform.pathSeparator}child.ivy.journal.json').readAsStringSync();
      expect(raw, isNot(contains('private words')));

      await second.wipeAll();
      expect(dir.existsSync(), isFalse, reason: 'every document is gone');
      expect(secure.data, isEmpty, reason: 'and so is the key');
      expect(await second.area('journal').get('e1'), isNull);
      // And it is usable again afterwards, under a brand-new key.
      await second.area('lists').put('wants', <Object?>['fresh']);
      expect(await second.area('lists').get('wants'), <Object?>['fresh']);
    });

    test('boot refuses a live demo-child scope before touching the disk', () async {
      final Directory dir = await Directory.systemTemp.createTemp('olive_services_test_');
      addTearDown(() => dir.delete(recursive: true));
      await expectLater(
          LocalServices.boot(childId: 'demo-child', isLive: true, secure: _MemorySecure(), rootOverride: dir),
          throwsStateError);
    });
  });

  test('resetForTest installs a fresh in-memory instance', () async {
    await LocalServices.current.area('lists').put('k', 1);
    LocalServices.resetForTest();
    expect(await LocalServices.current.area('lists').get('k'), isNull);
    expect(LocalServices.current.childId, 'demo-child');
    expect(LocalServices.current.isLive, isFalse);
  });
}
