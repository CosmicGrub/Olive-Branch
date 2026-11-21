// OLIVE BRANCH — kill the app at every step of a backup and of a restore: the old state must be intact, and a second
// try must finish the job. A "kill" is an Error thrown from inside the step, so no cleanup code gets to run, followed by
// a brand-new app run over the same bytes.
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/backup_classes.dart';
import 'package:olive_client/backup_format.dart';
import 'package:olive_client/backup_keys.dart';
import 'package:olive_client/backup_service.dart';
import 'package:olive_client/backup_targets.dart';
import 'package:olive_client/local_services.dart';
import 'package:olive_client/local_store.dart';
import 'package:olive_client/restore_engine.dart';
import 'package:olive_client/store_cipher.dart';

import 'support/backup_rig.dart';

class _Clock {
  int ms = 1700000000000;
  DateTime call() => DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  void advance(Duration d) => ms += d.inMilliseconds;
}

/// Writes half of a document to the temporary name and then "dies" before the rename.
class _DiesMidWrite extends DirectoryStoreBackend {
  _DiesMidWrite(super.root, this.dieOn);
  final String dieOn;
  bool armed = false;

  @override
  Future<void> writeAtomic(String name, Uint8List bytes) async {
    if (armed && name == dieOn) {
      await root.create(recursive: true);
      await File('${root.path}${Platform.pathSeparator}$name.json.tmp').writeAsBytes(bytes.sublist(0, bytes.length ~/ 2));
      throw SimulatedKill('mid-write $name');
    }
    return super.writeAtomic(name, bytes);
  }
}

Future<Map<String, String>> _raw(LocalStore s) async {
  final Map<String, String> out = <String, String>{};
  for (final String n in await s.namespaces()) {
    final Uint8List? b = await s.backend.read(n);
    if (b != null) out[n] = base64Encode(b);
  }
  return out;
}

void main() {
  late RecoverySheet sheet;
  late BackupKeyPair key;
  setUpAll(() async {
    sheet = await RecoverySheet.make(BackupPurpose.family, random: Random(5));
    key = await BackupKeyPair.fromSecret(sheet.secret, BackupPurpose.family);
  });

  BackupService svc(LocalServices s, _Clock c) => BackupService(services: s, clock: c.call, random: Random(3));
  BackupDestination dest(BackupTarget t, BackupTarget spool) => BackupDestination(id: 'folder', target: t, spool: spool, verifyEveryChunk: true);

  group('kill during a backup', () {
    Future<(Phone, MemoryBackupTarget, String)> withOneGoodBackup(_Clock c) async {
      final Phone p = Phone();
      final LocalServices s = p.open();
      await populate(s, BackupKind.family, bigPictures: 0);
      await s.area('care').put('long', List<String>.filled(30000, 'a binder page ').join());
      final MemoryBackupTarget t = MemoryBackupTarget();
      c.advance(const Duration(hours: 1));
      final BackupOutcome o = await svc(s, c).run(BackupKind.family, dest(t, MemoryBackupTarget()), sheet.publicKey);
      expect(o.ok, isTrue);
      return (p, t, o.setId!);
    }

    test('killed while sending: the older backup is untouched, the data is untouched, and the next run RESUMES and sends only what is missing', () async {
      final _Clock c = _Clock();
      final (Phone p, MemoryBackupTarget t, String firstId) = await withOneGoodBackup(c);
      final LocalServices s = p.open();
      await s.area('care').put('later', 'written after the first backup');
      final Map<String, String> dataBefore = await _raw(s.store)
        ..remove('device.backup');
      final MemoryBackupTarget spool = MemoryBackupTarget();
      final KillingTarget dying = KillingTarget(t, killOnPut: 2);
      c.advance(const Duration(hours: 25));
      await expectLater(svc(s, c).run(BackupKind.family, dest(dying, spool), sheet.publicKey), throwsA(isA<SimulatedKill>()));

      // The old backup is still the newest, whole, and opens.
      final List<CommittedSet> sets = await t.committed(BackupKind.family);
      expect(sets.single.setId, firstId);
      final OpenedManifest m = await openManifest(sets.single.header, sets.single.manifest, key);
      expect((await readAreas(m, (String id) => t.getChunk(BackupKind.family, firstId, id))).isNotEmpty, isTrue);
      // The family's data is exactly as it was.
      expect((await _raw(p.open().store))..remove('device.backup'), dataBefore);

      // A new run of the app: resume.
      final LocalServices again = p.open();
      final KillingTarget healthy = KillingTarget(t);
      final BackupOutcome o = await svc(again, c).run(BackupKind.family, dest(healthy, spool), sheet.publicKey);
      expect(o.ok, isTrue);
      expect(o.resumed, isTrue, reason: 'it picked up the staged set instead of starting over');
      expect(healthy.puts, o.totalChunks - 1, reason: 'only the chunks the destination lacked were sent (one had arrived)');
      final List<CommittedSet> after = await t.committed(BackupKind.family);
      expect(after.length, 2);
      expect(after.first.setId, o.setId);
      final OpenedManifest m2 = await openManifest(after.first.header, after.first.manifest, key);
      final List<RestoredArea> areas = await readAreas(m2, (String id) => t.getChunk(BackupKind.family, o.setId!, id));
      expect(areas.any((RestoredArea a) => a.entry.area == 'care' && a.data.containsKey('later')), isTrue);
      expect(await spool.committed(BackupKind.family), isEmpty);
    });

    test('killed at the very commit: all pieces are there, nothing counts yet, and the next run only commits', () async {
      final _Clock c = _Clock();
      final (Phone p, MemoryBackupTarget t, String firstId) = await withOneGoodBackup(c);
      final MemoryBackupTarget spool = MemoryBackupTarget();
      final KillingTarget dying = KillingTarget(t, killOnCommit: true);
      c.advance(const Duration(hours: 25));
      await expectLater(svc(p.open(), c).run(BackupKind.family, dest(dying, spool), sheet.publicKey), throwsA(isA<SimulatedKill>()));
      expect((await t.committed(BackupKind.family)).single.setId, firstId, reason: 'the half-finished set is invisible to a restore');
      final KillingTarget healthy = KillingTarget(t);
      final BackupOutcome o = await svc(p.open(), c).run(BackupKind.family, dest(healthy, spool), sheet.publicKey);
      expect(o.ok, isTrue);
      expect(o.resumed, isTrue);
      expect(healthy.puts, 0, reason: 'every piece had already arrived');
      expect((await t.committed(BackupKind.family)).length, 2);
    });

    test('killed while still sealing: the half-sealed staging is cleared and a fresh set is made from fresh data', () async {
      final _Clock c = _Clock();
      final (Phone p, MemoryBackupTarget t, String firstId) = await withOneGoodBackup(c);
      final MemoryBackupTarget innerSpool = MemoryBackupTarget();
      final KillingTarget dyingSpool = KillingTarget(innerSpool, killOnPut: 2);
      c.advance(const Duration(hours: 25));
      await expectLater(svc(p.open(), c).run(BackupKind.family, dest(t, dyingSpool), sheet.publicKey), throwsA(isA<SimulatedKill>()));
      expect((await t.committed(BackupKind.family)).single.setId, firstId);
      expect(await innerSpool.committed(BackupKind.family), isEmpty, reason: 'never prepared, so never resumed');

      final LocalServices s = p.open();
      await s.area('care').put('newer', 'changed while the app was dead');
      final BackupOutcome o = await svc(s, c).run(BackupKind.family, dest(t, innerSpool), sheet.publicKey);
      expect(o.ok, isTrue);
      expect(o.resumed, isFalse);
      final CommittedSet newest = (await t.committed(BackupKind.family)).first;
      final List<RestoredArea> areas = await readAreas(
          await openManifest(newest.header, newest.manifest, key), (String id) => t.getChunk(BackupKind.family, newest.setId, id));
      expect(areas.any((RestoredArea a) => a.entry.area == 'care' && a.data.containsKey('newer')), isTrue);
    });

    test('a staged set older than a day is thrown away rather than finished, so a stale snapshot never becomes "latest"', () async {
      final _Clock c = _Clock();
      final (Phone p, MemoryBackupTarget t, _) = await withOneGoodBackup(c);
      final MemoryBackupTarget spool = MemoryBackupTarget();
      final KillingTarget dying = KillingTarget(t, killOnPut: 1);
      c.advance(const Duration(hours: 25));
      await expectLater(svc(p.open(), c).run(BackupKind.family, dest(dying, spool), sheet.publicKey), throwsA(isA<SimulatedKill>()));
      c.advance(const Duration(hours: 30));
      final BackupOutcome o = await svc(p.open(), c).run(BackupKind.family, dest(t, spool), sheet.publicKey);
      expect(o.ok, isTrue);
      expect(o.resumed, isFalse);
      expect(await spool.committed(BackupKind.family), isEmpty);
    });
  });

  group('kill during a restore', () {
    late MemoryBackupTarget t;
    setUp(() async {
      final LocalServices s = Phone().open();
      await populate(s, BackupKind.family, seed: 1);
      t = MemoryBackupTarget();
      await svc(s, _Clock()).run(BackupKind.family, dest(t, MemoryBackupTarget()), sheet.publicKey);
    });

    Future<List<String>> stepsOf(Phone phone) async {
      final List<String> steps = <String>[];
      final RestoreEngine e = RestoreEngine(services: phone.open(), random: Random(1), testHook: (String s) async => steps.add(s));
      await e.apply(await e.plan(await e.inspect(t, BackupKind.family, key)));
      return steps;
    }

    for (final bool populated in <bool>[false, true]) {
      test('${populated ? 'a half-used phone' : 'an empty phone'}: killed at EVERY step, a restart puts the phone back exactly as it was, and a retry then succeeds', () async {
        Phone make() {
          return Phone();
        }
        Future<Phone> prepared() async {
          final Phone p = make();
          if (populated) {
            final LocalServices s = p.open();
            await populate(s, BackupKind.family, seed: 2);
            await s.area('care').put('only-here', 'mine');
          }
          return p;
        }

        final List<String> steps = await stepsOf(await prepared());
        expect(steps.length, greaterThan(5));
        expect(steps.first, 'undo');
        expect(steps, contains('noted'));
        expect(steps.last, 'checked');

        for (int k = 0; k < steps.length; k++) {
          final Phone p = await prepared();
          final Map<String, String> before = await _raw(p.open().store);
          int seen = 0;
          final RestoreEngine e = RestoreEngine(
              services: p.open(),
              random: Random(1),
              testHook: (String s) async {
                if (seen++ == k) throw SimulatedKill(s);
              });
          await expectLater(e.apply(await e.plan(await e.inspect(t, BackupKind.family, key))), throwsA(isA<SimulatedKill>()),
              reason: 'kill at step $k (${steps[k]})');

          // A brand-new app run over the same bytes, before anything reads the store.
          final LocalServices restarted = p.open();
          final RestoreEngine r = RestoreEngine(services: restarted);
          final RecoverResult rec = await r.recoverInterrupted();
          final Map<String, String> after = await _raw(restarted.store);
          // Everything but the restore's own note is byte-for-byte what it was.
          for (final String n in <String>{...before.keys, ...after.keys}) {
            if (n == 'device.backup') continue;
            expect(after[n], before[n], reason: 'step $k (${steps[k]}): $n');
          }
          expect(after.keys.where((String n) => n.startsWith('restoreundo.')), isEmpty);
          expect(rec, steps[k] == 'undo' ? RecoverResult.cleanedUp : RecoverResult.rolledBack,
              reason: 'before the note is written there is nothing to roll back, only leftovers to clear');

          // Retry: the backup was never touched, so it still restores, and proves itself.
          final RestoreEngine again = RestoreEngine(services: restarted, random: Random(2));
          final RestoreReport rep = await again.apply(await again.plan(await again.inspect(t, BackupKind.family, key)));
          expect(rep.roundTripOk, isTrue, reason: 'retry after kill at step $k');
        }
      });
    }

    test('a real directory: killed half way through writing a document, the old complete document is still there', () async {
      final Directory dir = await Directory.systemTemp.createTemp('olive_kill_restore_');
      addTearDown(() => dir.delete(recursive: true));
      final List<int> k = AesGcmStoreCipher.newKey();
      LocalServices open({String? dieOn}) {
        final _DiesMidWrite b = _DiesMidWrite(dir, dieOn ?? '')..armed = dieOn != null;
        return LocalServices(
            store: LocalStore(backend: b, cipher: AesGcmStoreCipher(k)), childId: 'mia', guardianId: 'gid-one', isLive: false, demoSeeds: false);
      }

      final LocalServices s = open();
      await s.area('care').put('mine', 'before');
      await s.area('access').put('mine', 'before');
      final Map<String, String> before = await _raw(open().store);

      final LocalServices dying = open(dieOn: 'child.mia.coordination');
      final RestoreEngine e = RestoreEngine(services: dying, random: Random(1));
      await expectLater(e.apply(await e.plan(await e.inspect(t, BackupKind.family, key))), throwsA(isA<SimulatedKill>()));
      // Some documents were already replaced, the one being written has only a stray half file.
      expect(File('${dir.path}${Platform.pathSeparator}child.mia.coordination.json.tmp').existsSync(), isTrue);

      final LocalServices restarted = open();
      expect(await RestoreEngine(services: restarted).recoverInterrupted(), RecoverResult.rolledBack);
      final Map<String, String> after = await _raw(restarted.store);
      for (final String n in <String>{...before.keys, ...after.keys}) {
        if (n == 'device.backup') continue;
        expect(after[n], before[n], reason: n);
      }
      expect(await restarted.area('care').get('mine'), 'before');
      expect(await restarted.area('access').get('mine'), 'before');
      expect(await restarted.area('coordination').list(), isEmpty, reason: 'a stray half file is never read as data');
    });

    test('with nothing interrupted, start-up recovery does nothing', () async {
      final LocalServices s = Phone().open();
      await populate(s, BackupKind.family, seed: 3);
      final Map<String, String> before = await _raw(s.store);
      expect(await RestoreEngine(services: s).recoverInterrupted(), RecoverResult.nothingToDo);
      expect(await _raw(s.store), before);
    });

    test('a finished restore leaves no undo copies and a note that says done', () async {
      final Phone p = Phone();
      final LocalServices s = p.open();
      final RestoreEngine e = RestoreEngine(services: s, random: Random(1));
      await e.apply(await e.plan(await e.inspect(t, BackupKind.family, key)));
      expect((await s.store.namespaces()).where((String n) => n.startsWith('restoreundo.')), isEmpty);
      expect(((await s.area('backup').get('restore')) as Map)['phase'], 'done');
      expect(await RestoreEngine(services: p.open()).recoverInterrupted(), RecoverResult.nothingToDo);
    });
  });
}
