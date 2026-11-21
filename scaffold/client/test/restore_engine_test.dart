// OLIVE BRANCH — restore_engine.dart: opening, planning, merging, applying, proving. Hostile cases included.
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/backup_classes.dart';
import 'package:olive_client/backup_format.dart';
import 'package:olive_client/backup_keys.dart';
import 'package:olive_client/backup_service.dart';
import 'package:olive_client/backup_targets.dart';
import 'package:olive_client/local_services.dart';
import 'package:olive_client/restore_engine.dart';

import 'support/backup_rig.dart';

class _Clock {
  int ms = 1700000000000;
  DateTime call() => DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  void advance(Duration d) => ms += d.inMilliseconds;
}

void main() {
  late RecoverySheet sheet;
  late BackupKeyPair key;
  setUpAll(() async {
    sheet = await RecoverySheet.make(BackupPurpose.family, random: Random(5));
    key = await BackupKeyPair.fromSecret(sheet.secret, BackupPurpose.family);
  });

  Future<MemoryBackupTarget> backUp(LocalServices s, {BackupKind kind = BackupKind.family, _Clock? clock, BackupKeyPair? to, MemoryBackupTarget? into}) async {
    final MemoryBackupTarget t = into ?? MemoryBackupTarget();
    final BackupService b = BackupService(services: s, clock: (clock ?? _Clock()).call);
    final BackupOutcome o = await b.run(kind, BackupDestination(id: 'folder', target: t, spool: MemoryBackupTarget(), verifyEveryChunk: true),
        (to ?? key).publicKey);
    expect(o.ok, isTrue, reason: o.code);
    return t;
  }

  RestoreEngine engine(LocalServices s, {_Clock? clock, Future<void> Function(String)? hook}) =>
      RestoreEngine(services: s, clock: (clock ?? _Clock()).call, random: Random(4), testHook: hook);

  test('onto an empty phone every area is taken as it was, and the round trip proves it', () async {
    final Phone old = Phone();
    final LocalServices s = old.open();
    await populate(s, BackupKind.family);
    final MemoryBackupTarget t = await backUp(s);

    final Phone fresh = Phone();
    final LocalServices n = fresh.open();
    final RestoreEngine e = engine(n);
    final RestoreInspection i = await e.inspect(t, BackupKind.family, key);
    final RestorePlan plan = await e.plan(i);
    expect(plan.canApply, isTrue);
    expect(plan.writes.every((AreaPlan a) => a.action == AreaAction.take), isTrue);
    final RestoreReport r = await e.apply(plan);
    expect(r.roundTripOk, isTrue);
    expect(r.setAside, 0);
    final BackupSnapshot before = await captureSnapshot(s.store, BackupKind.family);
    final BackupSnapshot after = await captureSnapshot(n.store, BackupKind.family);
    expect(after.contentHash, before.contentHash);
    expect(after.areas.map((AreaSnapshot a) => a.hash).toList(), before.areas.map((AreaSnapshot a) => a.hash).toList());
  });

  test('restoring something that is already here changes nothing and writes nothing', () async {
    final Phone p = Phone();
    final LocalServices s = p.open();
    await populate(s, BackupKind.family);
    final MemoryBackupTarget t = await backUp(s);
    final Map<String, String> raw = <String, String>{
      for (final String n in await s.store.namespaces()) n: base64Encode(p.backend.rawFor(n)!)
    };
    final RestoreEngine e = engine(s);
    final RestorePlan plan = await e.plan(await e.inspect(t, BackupKind.family, key));
    expect(plan.writes, isEmpty);
    final RestoreReport r = await e.apply(plan);
    expect(r.same, greaterThan(0));
    expect(r.roundTripOk, isTrue);
    for (final String n in await s.store.namespaces()) {
      if (n == 'device.backup') continue;
      expect(base64Encode(p.backend.rawFor(n)!), raw[n], reason: n);
    }
  });

  test('newer data on the phone is never overwritten: the newer version is used and the other is kept', () async {
    final Phone old = Phone();
    final LocalServices s = old.open();
    await s.area('emergencycard').put('card', <String, Object?>{'version': 3, 'allergy': 'peanuts'});
    await s.area('coordination').put('doses', <Object?>['mon 8am', 'tue 8am']);
    await s.area('care').put('note', 'from the backup');
    final MemoryBackupTarget t = await backUp(s);

    // The new phone already moved on: a newer card, more doses, and a note of its own.
    final Phone fresh = Phone();
    final LocalServices n = fresh.open();
    await n.area('emergencycard').put('card', <String, Object?>{'version': 5, 'allergy': 'peanuts and eggs'});
    await n.area('coordination').put('doses', <Object?>['tue 8am', 'wed 8am']);
    await n.area('care').put('other', 'only here');
    final RestoreEngine e = engine(n);
    final RestorePlan plan = await e.plan(await e.inspect(t, BackupKind.family, key));
    expect(plan.setAsideCount, 1, reason: "the backup's older card is kept, nothing else conflicts");
    final RestoreReport r = await e.apply(plan);
    expect(r.roundTripOk, isTrue);

    expect(((await n.area('emergencycard').get('card')) as Map)['version'], 5, reason: 'newer local card stays');
    expect(await n.area('coordination').get('doses'), <Object?>['tue 8am', 'wed 8am', 'mon 8am'], reason: 'logs are joined, local order first');
    expect(await n.area('care').get('note'), 'from the backup');
    expect(await n.area('care').get('other'), 'only here');
    final Map<String, Object?> kept = await n.area('backupkept').snapshot();
    final Map<Object?, Object?> item = ((kept.values.single as Map<Object?, Object?>)['items']! as List<Object?>).single! as Map<Object?, Object?>;
    expect(item['key'], 'card');
    expect(item['side'], 'backup');
    expect((item['value'] as Map)['version'], 3, reason: 'the older version is still there to be read');
  });

  test('when the backup is newer, the phone\'s older version is the one kept', () async {
    final Phone old = Phone();
    final LocalServices s = old.open();
    await s.area('emergencycard').put('card', <String, Object?>{'version': 9, 'allergy': 'new'});
    final MemoryBackupTarget t = await backUp(s);
    final LocalServices n = Phone().open();
    await n.area('emergencycard').put('card', <String, Object?>{'version': 2, 'allergy': 'old'});
    final RestoreEngine e = engine(n);
    await e.apply(await e.plan(await e.inspect(t, BackupKind.family, key)));
    expect(((await n.area('emergencycard').get('card')) as Map)['allergy'], 'new');
    final Map<Object?, Object?> item = (((await n.area('backupkept').snapshot()).values.single as Map<Object?, Object?>)['items']! as List<Object?>).single! as Map<Object?, Object?>;
    expect(item['side'], 'phone');
    expect((item['value'] as Map)['allergy'], 'old');
  });

  test('a signed record is never rewritten from another copy: the phone\'s entry stays, the backup\'s is kept', () async {
    final LocalServices s = Phone().open();
    await s.area('familyledger', ownerId: 'gid-one').put('e1', 'entry-from-backup');
    await s.area('familyledger', ownerId: 'gid-one').put('e2', 'shared');
    final MemoryBackupTarget t = await backUp(s);
    final LocalServices n = Phone().open();
    await n.area('familyledger').put('e1', 'entry-on-phone');
    final RestoreEngine e = engine(n);
    await e.apply(await e.plan(await e.inspect(t, BackupKind.family, key)));
    expect(await n.area('familyledger').get('e1'), 'entry-on-phone');
    expect(await n.area('familyledger').get('e2'), 'shared');
  });

  test('the wrong words never open it, count toward a rest, and the right words still work after the rest', () async {
    final LocalServices s = Phone().open();
    await populate(s, BackupKind.family);
    final MemoryBackupTarget t = await backUp(s);
    final BackupKeyPair wrong = await BackupKeyPair.fromSecret(newBackupSecret(Random(77)), BackupPurpose.family);
    final _Clock c = _Clock();
    final LocalServices n = Phone().open();
    final RestoreEngine e = engine(n, clock: c);
    for (int i = 0; i < kRestoreTries; i++) {
      await expectLater(e.inspect(t, BackupKind.family, wrong),
          throwsA(isA<RestoreProblem>().having((RestoreProblem p) => p.code, 'code', 'key')));
    }
    // Now resting: even the right words wait.
    await expectLater(e.inspect(t, BackupKind.family, key),
        throwsA(isA<RestoreProblem>().having((RestoreProblem p) => p.code, 'code', 'limited')));
    c.advance(const Duration(minutes: 16));
    final RestoreInspection ok = await e.inspect(t, BackupKind.family, key);
    expect(ok.manifest.areas, isNotEmpty);
    // A good open clears the count.
    await expectLater(e.inspect(t, BackupKind.family, wrong), throwsA(isA<RestoreProblem>()));
    expect(((await n.area('backup').get('limiter')) as Map)['fails'], 1);
  });

  test('another family\'s backup does not open with this family\'s words, and nothing is changed', () async {
    final LocalServices theirs = Phone(childId: 'zed').open();
    await populate(theirs, BackupKind.family);
    final BackupKeyPair theirKey = await BackupKeyPair.fromSecret(newBackupSecret(Random(31)), BackupPurpose.family);
    final MemoryBackupTarget t = await backUp(theirs, to: theirKey);
    final Phone mine = Phone();
    final LocalServices n = mine.open();
    final List<String> before = await n.store.namespaces();
    final RestoreEngine e = engine(n);
    await expectLater(e.inspect(t, BackupKind.family, key),
        throwsA(isA<RestoreProblem>().having((RestoreProblem p) => p.code, 'code', 'key')));
    expect((await n.store.namespaces()).where((String x) => x != 'device.backup').toList(),
        before.where((String x) => x != 'device.backup').toList());
  });

  test('nothing there says so in plain words', () async {
    final RestoreEngine e = engine(Phone().open());
    await expectLater(e.inspect(MemoryBackupTarget(), BackupKind.family, key),
        throwsA(isA<RestoreProblem>().having((RestoreProblem p) => p.code, 'code', 'nothing')));
  });

  test('a damaged newest set is skipped and the one before is used; the skip is reported', () async {
    final Phone p = Phone();
    final LocalServices s = p.open();
    await populate(s, BackupKind.family);
    final _Clock c = _Clock();
    final MemoryBackupTarget t = MemoryBackupTarget();
    await backUp(s, clock: c, into: t);
    await s.area('care').put('later', 'added after the first backup');
    c.advance(const Duration(hours: 25));
    await backUp(s, clock: c, into: t);
    final CommittedSet newest = (await t.committed(BackupKind.family)).first;
    t.corruptChunk(BackupKind.family, newest.setId, BackupHeader.parse(newest.header).chunkIds.first);
    final RestoreEngine e = engine(Phone().open());
    final RestoreInspection i = await e.inspect(t, BackupKind.family, key);
    expect(i.skippedDamaged, 1);
    expect(i.manifest.setId, isNot(newest.setId));
    expect(i.areas.any((RestoredArea a) => a.entry.area == 'care' && a.data.containsKey('later')), isFalse);
  });

  test('every set damaged is a plain refusal that changes nothing', () async {
    final LocalServices s = Phone().open();
    await populate(s, BackupKind.family);
    final MemoryBackupTarget t = await backUp(s);
    final CommittedSet c = (await t.committed(BackupKind.family)).single;
    for (final String id in BackupHeader.parse(c.header).chunkIds) {
      t.dropChunk(BackupKind.family, c.setId, id);
    }
    final LocalServices n = Phone().open();
    await expectLater(engine(n).inspect(t, BackupKind.family, key),
        throwsA(isA<RestoreProblem>().having((RestoreProblem p) => p.code, 'code', 'damaged')));
    expect(await n.store.namespaces(), isNot(contains('child.mia.care')));
  });

  test('a replayed OLD backup is recognised: this phone has made a newer one than the one found', () async {
    final Phone p = Phone();
    final LocalServices s = p.open();
    await populate(s, BackupKind.family);
    final _Clock c = _Clock();
    final MemoryBackupTarget everything = MemoryBackupTarget();
    await backUp(s, clock: c, into: everything);
    c.advance(const Duration(hours: 25));
    await backUp(s, clock: c, into: everything);
    final CommittedSet newest = (await everything.committed(BackupKind.family)).first;
    // A hostile server shows only the oldest set.
    final MemoryBackupTarget withheld = MemoryBackupTarget();
    final CommittedSet oldest = (await everything.committed(BackupKind.family)).last;
    for (final String id in BackupHeader.parse(oldest.header).chunkIds) {
      await withheld.putChunk(BackupKind.family, oldest.setId, id, (await everything.getChunk(BackupKind.family, oldest.setId, id))!);
    }
    await withheld.commit(BackupKind.family, oldest.setId, oldest.header, oldest.manifest);
    expect(oldest.setId, isNot(newest.setId));
    final RestoreInspection i = await engine(s, clock: c).inspect(withheld, BackupKind.family, key);
    expect(i.olderThanKnown, isTrue);
    // A fresh phone has no memory of newer ones, so nothing is claimed.
    final RestoreInspection fresh = await engine(Phone().open()).inspect(withheld, BackupKind.family, key);
    expect(fresh.olderThanKnown, isFalse);
  });

  group('a forged or odd set is not trusted', () {
    test('a set that names device-bound or never-backed-up areas has those areas ignored, never written', () async {
      // Build a hostile family set by hand: sealed with the real key (the attacker has the public key) but naming areas
      // that no backup may hold.
      final Phone evil = Phone();
      final LocalServices s = evil.open();
      await s.area('devicekey').put('k', <String, Object?>{'secret': 'attacker-key'});
      await s.area('localpin').put('pin', <String, Object?>{'hash': 'attacker-pin'});
      await s.area('childkeys').put('secrets', <String, Object?>{'keep': 'AA=='});
      await s.area('care').put('ok', 'legit');
      final BackupSnapshot real = await captureSnapshot(s.store, BackupKind.family);
      // Capture the never-areas by hand by reading them as if they were family areas.
      final List<AreaSnapshot> sneaky = <AreaSnapshot>[...real.areas];
      for (final String ns in <String>['device.devicekey', 'guardian.gid-one.localpin', 'device.childkeys']) {
        final NsRef ref = NsRef.parse(ns)!;
        final Map<String, Object?> data = await s.store.open(specFor(ref)).snapshot();
        if (data.isEmpty) continue;
        sneaky.add(AreaSnapshot(ref, 1, true, data, await areaContentHash(ns, data),
            Uint8List.fromList(utf8.encode(canonicalJson(data)))));
      }
      final BackupSnapshot forged = BackupSnapshot(BackupKind.family, sneaky, const <String>[], 'x');
      final MemoryBackupTarget t = MemoryBackupTarget();
      final Map<String, Uint8List> chunks = <String, Uint8List>{};
      final SealedSet sealed = await sealSnapshot(forged, key.publicKey,
          onChunk: (String id, Uint8List b) async => chunks[id] = b, createdMs: 1, seq: 1);
      for (final MapEntry<String, Uint8List> c in chunks.entries) {
        await t.putChunk(BackupKind.family, sealed.setId, c.key, c.value);
      }
      await t.commit(BackupKind.family, sealed.setId, sealed.header, sealed.manifest);

      final LocalServices victim = Phone().open();
      await victim.area('devicekey').put('k', <String, Object?>{'secret': 'my-own-key'});
      final RestoreEngine e = engine(victim);
      final RestoreInspection i = await e.inspect(t, BackupKind.family, key);
      final RestorePlan plan = await e.plan(i);
      expect(plan.keptWords, contains('not recognised'));
      await e.apply(plan);
      expect(((await victim.area('devicekey').get('k')) as Map)['secret'], 'my-own-key', reason: 'the device key is untouched');
      expect(await victim.area('localpin').get('pin'), isNull);
      expect(await victim.area('childkeys').get('secrets'), isNull);
      expect(await victim.area('care').get('ok'), 'legit');
    });

    test('her private areas offered inside a family set are ignored', () async {
      final LocalServices s = Phone().open();
      await s.area('journal').put('e', <String, Object?>{'text': 'dear diary'});
      final NsRef ref = NsRef.parse('child.mia.journal')!;
      final Map<String, Object?> data = await s.store.open(specFor(ref)).snapshot();
      final BackupSnapshot forged = BackupSnapshot(BackupKind.family,
          <AreaSnapshot>[AreaSnapshot(ref, 1, true, data, await areaContentHash(ref.name, data), Uint8List.fromList(utf8.encode(canonicalJson(data))))],
          const <String>[], 'x');
      final MemoryBackupTarget t = MemoryBackupTarget();
      final Map<String, Uint8List> chunks = <String, Uint8List>{};
      final SealedSet sealed = await sealSnapshot(forged, key.publicKey,
          onChunk: (String id, Uint8List b) async => chunks[id] = b, createdMs: 1, seq: 1);
      for (final MapEntry<String, Uint8List> c in chunks.entries) {
        await t.putChunk(BackupKind.family, sealed.setId, c.key, c.value);
      }
      await t.commit(BackupKind.family, sealed.setId, sealed.header, sealed.manifest);
      final LocalServices n = Phone().open();
      final RestoreEngine e = engine(n);
      final RestorePlan plan = await e.plan(await e.inspect(t, BackupKind.family, key));
      expect(plan.writes, isEmpty);
      await e.apply(plan);
      expect(await n.area('journal').get('e'), isNull);
    });

    test('an owner id that could walk out of the store is refused at plan time', () async {
      final LocalServices s = Phone().open();
      await populate(s, BackupKind.family);
      final MemoryBackupTarget t = await backUp(s);
      final LocalServices n = Phone().open();
      final RestoreEngine e = engine(n);
      final RestoreInspection i = await e.inspect(t, BackupKind.family, key);
      final RestorePlan plan = await e.plan(i, ownerMap: <String, String>{'mia': '../escape', 'gid-one': 'Bad Name'});
      expect(plan.writes.where((AreaPlan a) => a.ref.ownerId.contains('.') || a.ref.ownerId.contains('/')), isEmpty);
      expect(plan.writes.where((AreaPlan a) => a.ref.scope != LocalScope.device && a.ref.ownerId == 'mia'), isEmpty);
    });
  });

  group('whose records they are', () {
    test('one child and one grown-up in the backup are mapped to this device\'s own ids', () async {
      final Phone old = Phone(childId: 'child-old', guardianId: 'guard-old');
      final LocalServices s = old.open();
      await populate(s, BackupKind.family);
      final MemoryBackupTarget t = await backUp(s);
      final Phone fresh = Phone(childId: 'child-new', guardianId: 'guard-new');
      final LocalServices n = fresh.open();
      final RestoreEngine e = engine(n);
      final RestoreInspection i = await e.inspect(t, BackupKind.family, key);
      final Map<String, String> map = e.suggestOwnerMap(i);
      expect(map, <String, String>{'child-old': 'child-new', 'guard-old': 'guard-new'});
      final RestoreReport r = await e.apply(await e.plan(i, ownerMap: map));
      expect(r.roundTripOk, isTrue);
      expect(await n.area('care').get('k0'), isNotNull, reason: 'it is where this device looks');
      expect(await n.store.namespaces(), isNot(contains('child.child-old.care')));
    });

    test('the same ids need no mapping', () async {
      final LocalServices s = Phone().open();
      await populate(s, BackupKind.family);
      final MemoryBackupTarget t = await backUp(s);
      final RestoreEngine e = engine(Phone().open());
      expect(e.suggestOwnerMap(await e.inspect(t, BackupKind.family, key)), isEmpty);
    });
  });

  group('does it fit, and does it prove itself', () {
    test('an area that would pass its ceiling blocks the whole restore before any write', () async {
      final LocalServices s = Phone().open();
      await s.area('care').put('big', 'x' * (3 * 1024 * 1024));
      final MemoryBackupTarget t = await backUp(s);
      final LocalServices n = Phone().open();
      await n.area('care').put('also-big', 'y' * (2 * 1024 * 1024));
      final List<String> before = await n.store.namespaces();
      final RestoreEngine e = engine(n);
      final RestorePlan plan = await e.plan(await e.inspect(t, BackupKind.family, key));
      expect(plan.canApply, isFalse);
      expect(plan.blocked.single, contains('not enough room'));
      await expectLater(e.apply(plan), throwsA(isA<RestoreProblem>().having((RestoreProblem p) => p.code, 'code', 'blocked')));
      expect(await n.store.namespaces(), before);
      expect(await n.area('care').get('also-big'), isNotNull);
    });

    test('a write that fails half way puts everything back at once', () async {
      final LocalServices s = Phone().open();
      await populate(s, BackupKind.family);
      final MemoryBackupTarget t = await backUp(s);
      final FailingBackend fb = FailingBackend('child.mia.emergencycard');
      final Phone fresh = Phone(backend: fb);
      final LocalServices n = fresh.open();
      await n.area('care').put('mine', 'before');
      final String rawBefore = base64Encode(fb.rawFor('child.mia.care')!);
      fb.fail = true;
      final RestoreEngine e = engine(n);
      final RestorePlan plan = await e.plan(await e.inspect(t, BackupKind.family, key));
      await expectLater(e.apply(plan), throwsA(isA<RestoreProblem>().having((RestoreProblem p) => p.code, 'code', 'io')));
      expect(base64Encode(fb.rawFor('child.mia.care')!), rawBefore, reason: 'an area written before the failure is put back');
      expect(fb.rawFor('child.mia.emergencycard'), isNull);
      expect(fb.rawFor('child.mia.coordination'), isNull);
      expect((await n.store.namespaces()).where((String x) => x.startsWith('restoreundo.')), isEmpty);
      expect(await n.area('care').get('mine'), 'before');
    });

    test('a disk that does not keep what it was given is caught by the read-back and undone', () async {
      final LocalServices s = Phone().open();
      await populate(s, BackupKind.family);
      final MemoryBackupTarget t = await backUp(s);
      final RottingBackend rb = RottingBackend('child.mia.care');
      final LocalServices n = Phone(backend: rb).open();
      await n.area('access').put('keep', 'me');
      rb.rot = true;
      final RestoreEngine e = engine(n);
      final RestorePlan plan = await e.plan(await e.inspect(t, BackupKind.family, key));
      await expectLater(e.apply(plan), throwsA(isA<RestoreProblem>().having((RestoreProblem p) => p.code, 'code', 'verify')));
      rb.rot = false;
      n.store.forgetCaches();
      expect(rb.rawFor('child.mia.care'), isNull, reason: 'it did not exist before, so it does not exist now');
      expect(await n.area('access').get('keep'), 'me');
      expect(await n.area('care').list(), isEmpty);
    });

    test('a second restore at the same time is refused', () async {
      final LocalServices s = Phone().open();
      await populate(s, BackupKind.family);
      final MemoryBackupTarget t = await backUp(s);
      final LocalServices n = Phone().open();
      bool started = false;
      late Future<RestoreReport> first;
      Object? second;
      final RestoreEngine e1 = engine(n, hook: (String step) async {
        if (step == 'noted' && !started) {
          started = true;
          try {
            final RestoreEngine e2 = engine(n);
            await e2.apply(await e2.plan(await e2.inspect(t, BackupKind.family, key)));
          } catch (x) {
            second = x;
          }
        }
      });
      first = e1.apply(await e1.plan(await e1.inspect(t, BackupKind.family, key)));
      await first;
      expect(second, isA<RestoreProblem>().having((RestoreProblem p) => p.code, 'code', 'busy'));
    });
  });

  test('plain words describe what a restore will do, with no raw ids', () async {
    final LocalServices s = Phone().open();
    await s.area('emergencycard').put('card', <String, Object?>{'version': 1});
    await s.area('care').put('n', 'x');
    final MemoryBackupTarget t = await backUp(s);
    final LocalServices n = Phone().open();
    await n.area('emergencycard').put('card', <String, Object?>{'version': 2});
    final RestoreEngine e = engine(n);
    final String words = describeRestorePlan(await e.plan(await e.inspect(t, BackupKind.family, key)));
    expect(words, contains('put back'));
    expect(words, contains('nothing is lost'));
    for (final String bad in <String>['child.', 'guardian.', 'emergencycard', 'namespace']) {
      expect(words.contains(bad), isFalse, reason: bad);
    }
  });
}
