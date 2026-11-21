// OLIVE BRANCH — backup_service.dart: a backup is read-only on the family's data, resumable, checked before older ones
// go, and honest in its status words. The phone keeps only the PUBLIC key.
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

import 'support/backup_rig.dart';

class _Clock {
  int ms = 1700000000000;
  DateTime call() => DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  void advance(Duration d) => ms += d.inMilliseconds;
}

BackupDestination _dest(BackupTarget t, BackupTarget spool, {String id = 'folder'}) =>
    BackupDestination(id: id, target: t, spool: spool, verifyEveryChunk: true);

void main() {
  late RecoverySheet sheet;
  late BackupKeyPair key;
  setUpAll(() async {
    sheet = await RecoverySheet.make(BackupPurpose.family, random: Random(5));
    key = await BackupKeyPair.fromSecret(sheet.secret, BackupPurpose.family);
  });

  BackupService svc(LocalServices s, _Clock c) => BackupService(services: s, clock: c.call, random: Random(9));

  test('a backup writes nothing to the family\'s data: only the backup area changes', () async {
    final Phone p = Phone();
    final LocalServices s = p.open();
    await populate(s, BackupKind.family);
    final Map<String, String> before = <String, String>{
      for (final String n in await s.store.namespaces()) n: base64Encode(p.backend.rawFor(n)!)
    };
    final MemoryBackupTarget target = MemoryBackupTarget(), spool = MemoryBackupTarget();
    final BackupOutcome o = await svc(s, _Clock()).run(BackupKind.family, _dest(target, spool), sheet.publicKey);
    expect(o.ok, isTrue);
    for (final MapEntry<String, String> e in before.entries) {
      expect(base64Encode(p.backend.rawFor(e.key)!), e.value, reason: '${e.key} must be byte-for-byte unchanged');
    }
    final Set<String> added = (await s.store.namespaces()).toSet().difference(before.keys.toSet());
    expect(added, <String>{'device.backup'});
    expect((await target.committed(BackupKind.family)).length, 1);
    expect(await spool.committed(BackupKind.family), isEmpty, reason: 'the staging copy is cleared after the check');
  });

  test('the backup holds the family areas and none of her private ones', () async {
    final Phone p = Phone();
    final LocalServices s = p.open();
    await populate(s, BackupKind.family);
    await populate(s, BackupKind.hersPrivate);
    await populate(s, BackupKind.hersKeep);
    final MemoryBackupTarget target = MemoryBackupTarget();
    await svc(s, _Clock()).run(BackupKind.family, _dest(target, MemoryBackupTarget()), sheet.publicKey);
    final CommittedSet c = (await target.committed(BackupKind.family)).single;
    final OpenedManifest m = await openManifest(c.header, c.manifest, key);
    final Set<String> areas = m.areas.map((ManifestArea a) => a.area).toSet();
    for (final String a in <String>['journal', 'worries', 'feelings', 'teen', 'mymarks', 'pictures', 'memorybox']) {
      expect(areas, isNot(contains(a)), reason: a);
    }
    expect(areas, containsAll(<String>['care', 'emergencycard', 'coordination', 'familyledger', 'access']));
  });

  test('the phone keeps only the public key: no secret, no private seed, in any stored byte', () async {
    final Phone p = Phone();
    final LocalServices s = p.open();
    await populate(s, BackupKind.family);
    final BackupService b = svc(s, _Clock());
    await b.rememberFamilySheet(sheet);
    await b.confirmFamilySheet();
    await b.run(BackupKind.family, _dest(MemoryBackupTarget(), MemoryBackupTarget()), sheet.publicKey);
    // Read the backup area through the store (it is sealed on disk) and scan everything for the secret and the seed.
    final Map<String, Object?> all = await s.area('backup').snapshot();
    final String dump = jsonEncode(all);
    String hex(List<int> x) => x.map((int v) => v.toRadixString(16).padLeft(2, '0')).join();
    for (final List<int> secretBytes in <List<int>>[sheet.secret, key.privateSeed]) {
      expect(dump.contains(base64Encode(secretBytes)), isFalse);
      expect(dump.contains(hex(secretBytes)), isFalse);
    }
    for (final String w in sheet.words) {
      expect(dump.contains(w), isFalse, reason: 'a word of the sheet must not be stored: $w');
    }
    final SheetRecord rec = (await b.journal.familySheet())!;
    expect(rec.publicKey, sheet.publicKey);
    expect(rec.confirmedMs, isNotNull);
    // And the other stored areas never held it either.
    for (final String n in await s.store.namespaces()) {
      final String raw = utf8.decode(p.backend.rawFor(n)!, allowMalformed: true);
      expect(raw.contains(base64Encode(key.privateSeed)), isFalse);
    }
  });

  test('a stolen phone that is unlocked can make a backup but cannot open any it made', () async {
    final Phone p = Phone();
    final LocalServices s = p.open();
    await populate(s, BackupKind.family);
    final MemoryBackupTarget target = MemoryBackupTarget();
    await svc(s, _Clock()).run(BackupKind.family, _dest(target, MemoryBackupTarget()), sheet.publicKey);
    // Everything the phone holds, as a thief would have it: the public key and the sealed set. Any key it can make is wrong.
    final CommittedSet c = (await target.committed(BackupKind.family)).single;
    final BackupKeyPair guessFromPublic = await BackupKeyPair.fromSecret(Uint8List.fromList(sheet.publicKey.sublist(0, kSecretBytes)), BackupPurpose.family);
    await expectLater(openManifest(c.header, c.manifest, guessFromPublic), throwsA(isA<BackupFormatException>()));
  });

  test('an empty phone says there is nothing to back up and makes no set', () async {
    final LocalServices s = Phone().open();
    final MemoryBackupTarget t = MemoryBackupTarget();
    final BackupOutcome o = await svc(s, _Clock()).run(BackupKind.family, _dest(t, MemoryBackupTarget()), sheet.publicKey);
    expect(o.ok, isTrue);
    expect(o.nothingToBackUp, isTrue);
    expect(await t.committed(BackupKind.family), isEmpty);
  });

  test('a folder on disk works end to end, with a real staging folder', () async {
    final Directory root = await Directory.systemTemp.createTemp('olive_backup_run_');
    addTearDown(() => root.delete(recursive: true));
    final Phone p = Phone();
    final LocalServices s = p.open();
    await populate(s, BackupKind.family, bigPictures: 0);
    final DirectoryBackupTarget t = DirectoryBackupTarget(Directory('${root.path}/kept'));
    final DirectoryBackupTarget spool = DirectoryBackupTarget(Directory('${root.path}/spool'));
    final BackupOutcome o = await svc(s, _Clock()).run(BackupKind.family, _dest(t, spool), sheet.publicKey);
    expect(o.ok, isTrue);
    expect((await t.committed(BackupKind.family)).length, 1);
    expect(await spool.committed(BackupKind.family), isEmpty);
    expect(await Directory('${root.path}/spool/family').exists() ? await Directory('${root.path}/spool/family').list().isEmpty : true, isTrue);
  });

  test('retention keeps the newest three and never removes the set just made', () async {
    final Phone p = Phone();
    final LocalServices s = p.open();
    await populate(s, BackupKind.family);
    final _Clock c = _Clock();
    final MemoryBackupTarget t = MemoryBackupTarget();
    final List<String> ids = <String>[];
    for (int i = 0; i < 5; i++) {
      c.advance(const Duration(hours: 25));
      final BackupOutcome o = await svc(s, c).run(BackupKind.family, _dest(t, MemoryBackupTarget()), sheet.publicKey);
      ids.add(o.setId!);
    }
    final List<String> kept = (await t.committed(BackupKind.family)).map((CommittedSet x) => x.setId).toList();
    expect(kept, <String>[ids[4], ids[3], ids[2]]);
    expect(await t.chunkIds(BackupKind.family, ids[0]), isEmpty, reason: 'its pieces went with it');
  });

  test('an older set is never removed when the new one could not be checked', () async {
    final Phone p = Phone();
    final LocalServices s = p.open();
    await populate(s, BackupKind.family);
    final _Clock c = _Clock();
    final MemoryBackupTarget t = MemoryBackupTarget();
    final List<String> ids = <String>[];
    for (int i = 0; i < 3; i++) {
      c.advance(const Duration(hours: 25));
      ids.add((await svc(s, c).run(BackupKind.family, _dest(t, MemoryBackupTarget()), sheet.publicKey)).setId!);
    }
    // A destination that loses the new set's chunk right after the commit (damage in transit).
    final _LossyTarget lossy = _LossyTarget(t);
    c.advance(const Duration(hours: 25));
    final BackupOutcome o = await svc(s, c).run(BackupKind.family, _dest(lossy, MemoryBackupTarget()), sheet.publicKey);
    expect(o.ok, isFalse);
    expect(o.code, 'verify');
    final List<String> still = (await t.committed(BackupKind.family)).map((CommittedSet x) => x.setId).toSet().toList();
    for (final String id in ids) {
      expect(still, contains(id), reason: 'a good older backup must survive an unchecked newer one');
    }
    final BackupLast? last = await svc(s, c).journal.newestSuccess(BackupKind.family);
    expect(last!.setId, ids.last, reason: 'the failed one is not recorded as a success');
  });

  test('the sequence number only goes up, so a replayed older set is recognisable', () async {
    final Phone p = Phone();
    final LocalServices s = p.open();
    await populate(s, BackupKind.family);
    final _Clock c = _Clock();
    final MemoryBackupTarget t = MemoryBackupTarget();
    for (int i = 0; i < 3; i++) {
      c.advance(const Duration(hours: 25));
      await svc(s, c).run(BackupKind.family, _dest(t, MemoryBackupTarget()), sheet.publicKey);
    }
    final List<int> seqs = <int>[];
    for (final CommittedSet x in await t.committed(BackupKind.family)) {
      seqs.add((await openManifest(x.header, x.manifest, key)).seq);
    }
    expect(seqs, <int>[3, 2, 1]);
  });

  group('automatic backup', () {
    test('runs when none exists, not again within a day, again after a day', () async {
      final Phone p = Phone();
      final LocalServices s = p.open();
      await populate(s, BackupKind.family);
      final _Clock c = _Clock();
      final BackupService b = svc(s, c);
      final MemoryBackupTarget t = MemoryBackupTarget();
      final Map<String, BackupDestination> d = <String, BackupDestination>{'folder': _dest(t, MemoryBackupTarget())};
      expect((await b.runIfDue(BackupKind.family, d, sheet.publicKey)).keys, <String>['folder']);
      c.advance(const Duration(hours: 3));
      expect(await b.runIfDue(BackupKind.family, d, sheet.publicKey), isEmpty);
      c.advance(const Duration(hours: 22));
      expect((await b.runIfDue(BackupKind.family, d, sheet.publicKey)).keys, <String>['folder']);
      expect((await t.committed(BackupKind.family)).length, 2);
    });

    test('off means off, and a destination switched off is skipped', () async {
      final Phone p = Phone();
      final LocalServices s = p.open();
      await populate(s, BackupKind.family);
      final BackupService b = svc(s, _Clock());
      final MemoryBackupTarget t = MemoryBackupTarget();
      final Map<String, BackupDestination> d = <String, BackupDestination>{'folder': _dest(t, MemoryBackupTarget())};
      await b.journal.saveSettings(const BackupSettings(auto: false));
      expect(await b.runIfDue(BackupKind.family, d, sheet.publicKey), isEmpty);
      await b.journal.saveSettings(const BackupSettings(folderOn: false));
      expect(await b.runIfDue(BackupKind.family, d, sheet.publicKey), isEmpty);
      expect(await t.committed(BackupKind.family), isEmpty);
    });

    test('a failed try waits half an hour before the next automatic one, and keeps the earlier success', () async {
      final Phone p = Phone();
      final LocalServices s = p.open();
      await populate(s, BackupKind.family);
      final _Clock c = _Clock();
      final BackupService b = svc(s, c);
      final MemoryBackupTarget t = MemoryBackupTarget();
      await b.run(BackupKind.family, _dest(t, MemoryBackupTarget()), sheet.publicKey);
      c.advance(const Duration(hours: 25));
      final _OfflineTarget off = _OfflineTarget();
      final Map<String, BackupDestination> d = <String, BackupDestination>{'folder': _dest(off, MemoryBackupTarget())};
      expect((await b.runIfDue(BackupKind.family, d, sheet.publicKey))['folder']!.code, 'offline');
      expect(off.attempts, 1);
      c.advance(const Duration(minutes: 10));
      expect(await b.runIfDue(BackupKind.family, d, sheet.publicKey), isEmpty);
      c.advance(const Duration(minutes: 30));
      expect((await b.runIfDue(BackupKind.family, d, sheet.publicKey)).isNotEmpty, isTrue);
      expect((await b.journal.newestSuccess(BackupKind.family))!.ok, isTrue, reason: 'the earlier success is still the last success');
    });
  });

  group('her tablet\'s two secrets', () {
    test('are made once, kept, and never appear in a backup of any kind', () async {
      final Phone p = Phone();
      final LocalServices s = p.open();
      final ChildKeyKeeper keeper = ChildKeyKeeper(s.area('childkeys'));
      final ChildSecrets a = await keeper.ensure(random: Random(1));
      final ChildSecrets b = await keeper.ensure(random: Random(2));
      expect(b.keep, a.keep);
      expect(b.private, a.private);
      await populate(s, BackupKind.hersKeep);
      await populate(s, BackupKind.hersPrivate);
      for (final BackupKind k in <BackupKind>[BackupKind.hersKeep, BackupKind.hersPrivate]) {
        final MemoryBackupTarget t = MemoryBackupTarget();
        final BackupKeyPair kp = await BackupKeyPair.fromSecret(k == BackupKind.hersKeep ? a.keep : a.private,
            k == BackupKind.hersKeep ? BackupPurpose.keep : BackupPurpose.private);
        final BackupOutcome o = await svc(s, _Clock()).run(k, _dest(t, MemoryBackupTarget()), kp.publicKey);
        expect(o.ok, isTrue);
        final CommittedSet c = (await t.committed(k)).single;
        final OpenedManifest m = await openManifest(c.header, c.manifest, kp);
        expect(m.areas.map((ManifestArea x) => x.area), isNot(contains('childkeys')));
      }
    });

    test('adopting a hand-over replaces them, so old and new tablets share keys', () async {
      final ChildKeyKeeper k = ChildKeyKeeper(Phone().open().area('childkeys'));
      final ChildSecrets mine = await k.ensure(random: Random(1));
      final ChildSecrets theirs = ChildSecrets.make(Random(2));
      await k.adopt(theirs);
      expect((await k.read())!.keep, theirs.keep);
      expect((await k.read())!.keep, isNot(mine.keep));
    });
  });

  group('the words for a grown-up', () {
    const BackupSettings on = BackupSettings();
    BackupLast ok(int at, {String dest = 'folder', int unreadable = 0}) =>
        BackupLast(kind: BackupKind.family, ok: true, atMs: at, dest: dest, unreadable: unreadable);
    final int now = 1700000000000;

    test('no place chosen, no backup yet, fresh, old, failed since', () {
      expect(describeBackupStatus(settings: const BackupSettings(folderOn: false), last: null, lastTry: null, sheet: null, nowMs: now).mood,
          BackupMood.paused);
      final BackupStatusView none = describeBackupStatus(settings: on, last: null, lastTry: null, sheet: null, nowMs: now);
      expect(none.mood, BackupMood.none);
      expect(none.headline, 'No backup yet');
      final BackupStatusView fresh = describeBackupStatus(settings: on, last: ok(now - 3 * 3600000), lastTry: null, sheet: null, nowMs: now);
      expect(fresh.mood, BackupMood.ok);
      expect(fresh.headline, 'Backed up 3 hours ago');
      final BackupStatusView old = describeBackupStatus(settings: on, last: ok(now - 9 * 86400000), lastTry: null, sheet: null, nowMs: now);
      expect(old.mood, BackupMood.behind);
      expect(old.headline, 'Your backup is a little old');
      expect(old.detail, contains('9 days ago'));
      final BackupStatusView failed = describeBackupStatus(
          settings: on,
          last: ok(now - 2 * 86400000),
          lastTry: BackupLast(kind: BackupKind.family, ok: false, atMs: now - 1000, code: 'offline'),
          sheet: null,
          nowMs: now);
      expect(failed.mood, BackupMood.failed);
      expect(failed.detail, contains('2 days ago'));
      expect(failed.detail, contains('could not reach the server'));
    });

    test('says plainly when something was left out, and when the sheet was never checked', () {
      final BackupStatusView v = describeBackupStatus(
          settings: on, last: ok(now - 60000, unreadable: 2), lastTry: null,
          sheet: SheetRecord(sheetId: 'AB12', publicKey: Uint8List(32), madeMs: now - 86400000), nowMs: now);
      expect(v.detail, contains('2 things on this phone could not be read'));
      expect(v.detail, contains('recovery sheet'));
    });

    test('no status line uses a raw area id, a code, a path or a number of chunks', () {
      for (final String code in <String>['offline', 'refused', 'full', 'io', 'verify', 'busy', 'weird']) {
        final BackupStatusView v = describeBackupStatus(
            settings: on,
            last: null,
            lastTry: BackupLast(kind: BackupKind.family, ok: false, atMs: now, code: code),
            sheet: null,
            nowMs: now);
        for (final String bad in <String>['chunk', 'manifest', 'namespace', 'child.', 'guardian.', '/', 'Exception']) {
          expect(v.detail.contains(bad), isFalse, reason: '$code: $bad');
        }
      }
    });

    test('the six-month reminder for the paper is due only after six months', () {
      final SheetRecord r = SheetRecord(sheetId: 'AB12', publicKey: Uint8List(32), madeMs: now, confirmedMs: now);
      expect(sheetReminderDue(r, now + 100 * 86400000), isFalse);
      expect(sheetReminderDue(r, now + 200 * 86400000), isTrue);
      expect(sheetReminderDue(null, now), isFalse);
    });
  });
}

/// Loses every chunk of the newest set right after a commit, standing for damage between sending and reading back.
class _LossyTarget implements BackupTarget {
  _LossyTarget(this.inner);
  final MemoryBackupTarget inner;
  @override
  String get kindWord => 'memory';
  @override
  Future<Set<String>> chunkIds(BackupKind k, String s) => inner.chunkIds(k, s);
  @override
  Future<void> putChunk(BackupKind k, String s, String c, Uint8List b) => inner.putChunk(k, s, c, b);
  @override
  Future<Uint8List?> getChunk(BackupKind k, String s, String c) => inner.getChunk(k, s, c);
  @override
  Future<void> commit(BackupKind k, String s, Uint8List h, Uint8List m) async {
    await inner.commit(k, s, h, m);
    for (final String id in await inner.chunkIds(k, s)) {
      inner.corruptChunk(k, s, id);
    }
  }

  @override
  Future<List<CommittedSet>> committed(BackupKind k) => inner.committed(k);
  @override
  Future<void> remove(BackupKind k, String s) => inner.remove(k, s);
}

class _OfflineTarget implements BackupTarget {
  int attempts = 0;
  @override
  String get kindWord => 'server';
  @override
  Future<Set<String>> chunkIds(BackupKind k, String s) async {
    attempts++;
    throw const BackupTargetException('offline', 'no connection');
  }

  @override
  Future<void> putChunk(BackupKind k, String s, String c, Uint8List b) async =>
      throw const BackupTargetException('offline', 'no connection');
  @override
  Future<Uint8List?> getChunk(BackupKind k, String s, String c) async => null;
  @override
  Future<void> commit(BackupKind k, String s, Uint8List h, Uint8List m) async =>
      throw const BackupTargetException('offline', 'no connection');
  @override
  Future<List<CommittedSet>> committed(BackupKind k) async => <CommittedSet>[];
  @override
  Future<void> remove(BackupKind k, String s) async {}
}
