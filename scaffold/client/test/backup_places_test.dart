// OLIVE BRANCH — backup_places.dart: the folder, the carried file, and what the app runs by itself.
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/backup_classes.dart';
import 'package:olive_client/backup_format.dart';
import 'package:olive_client/backup_keys.dart';
import 'package:olive_client/backup_places.dart';
import 'package:olive_client/backup_service.dart';
import 'package:olive_client/backup_targets.dart';
import 'package:olive_client/local_services.dart';
import 'package:olive_client/restore_engine.dart';

import 'support/backup_rig.dart';

void main() {
  test('the family backup waits for a recovery sheet that was made AND checked', () async {
    final LocalServices s = Phone().open();
    await populate(s, BackupKind.family);
    final MemoryBackupPlaces places = MemoryBackupPlaces();
    expect(await runFamilyBackupIfDue(s, places), isEmpty, reason: 'no sheet yet: nothing is locked to nobody');
    final RecoverySheet sheet = await RecoverySheet.make(BackupPurpose.family, random: Random(1));
    final BackupService b = BackupService(services: s);
    await b.rememberFamilySheet(sheet);
    expect(await runFamilyBackupIfDue(s, places), isEmpty, reason: 'made but not checked');
    await b.confirmFamilySheet();
    final Map<String, BackupOutcome> ran = await runFamilyBackupIfDue(s, places);
    expect(ran.keys, <String>['folder']);
    expect(ran['folder']!.ok, isTrue);
    expect((await places.folder.committed(BackupKind.family)).length, 1);
    expect(await runFamilyBackupIfDue(s, places), isEmpty, reason: 'not due again so soon');
  });

  test('her tablet backs up her keepsakes and her private areas, each under its own key, and says nothing', () async {
    final Phone p = Phone();
    final LocalServices s = p.open();
    await populate(s, BackupKind.hersKeep);
    await populate(s, BackupKind.hersPrivate);
    final MemoryBackupPlaces places = MemoryBackupPlaces();
    await runChildBackupsIfDue(s, places);
    final ChildSecrets secrets = (await ChildKeyKeeper(s.area('childkeys')).read())!;
    final BackupKeyPair keep = await BackupKeyPair.fromSecret(secrets.keep, BackupPurpose.keep);
    final BackupKeyPair priv = await BackupKeyPair.fromSecret(secrets.private, BackupPurpose.private);
    final CommittedSet ck = (await places.folder.committed(BackupKind.hersKeep)).single;
    final CommittedSet cp = (await places.folder.committed(BackupKind.hersPrivate)).single;
    expect((await openManifest(ck.header, ck.manifest, keep)).kind, BackupKind.hersKeep);
    expect((await openManifest(cp.header, cp.manifest, priv)).kind, BackupKind.hersPrivate);
    await expectLater(openManifest(cp.header, cp.manifest, keep), throwsA(isA<BackupFormatException>()));
    await expectLater(openManifest(ck.header, ck.manifest, priv), throwsA(isA<BackupFormatException>()));
  });

  test('a backup that cannot run never throws and never touches what is there', () async {
    final LocalServices s = Phone().open();
    await populate(s, BackupKind.family);
    expect(await runFamilyBackupIfDue(s, _ExplodingPlaces()), isEmpty);
    await runChildBackupsIfDue(s, _ExplodingPlaces());
    expect(await recoverRestoreAtStart(s), RecoverResult.nothingToDo);
  });

  group('the real folder', () {
    late Directory root;
    setUp(() async => root = await Directory.systemTemp.createTemp('olive_places_'));
    tearDown(() => root.delete(recursive: true));

    test('a folder destination backs up and restores; with no server wire there is no server place', () async {
      final DeviceBackupPlaces places = DeviceBackupPlaces(root: Directory('${root.path}/olive_backups'));
      expect(places.serverAvailable, isFalse);
      expect(places.destinations(const BackupSettings()).keys, <String>['folder']);
      expect(places.sourceFor('server', const BackupSettings()), isNull);

      final RecoverySheet sheet = await RecoverySheet.make(BackupPurpose.family, random: Random(2));
      final LocalServices s = Phone().open();
      await populate(s, BackupKind.family);
      final BackupOutcome o = await BackupService(services: s)
          .run(BackupKind.family, places.destinations(const BackupSettings())['folder']!, sheet.publicKey);
      expect(o.ok, isTrue);
      final BackupKeyPair key = await BackupKeyPair.fromSecret(sheet.secret, BackupPurpose.family);
      final LocalServices fresh = Phone().open();
      final RestoreEngine e = RestoreEngine(services: fresh);
      final RestoreReport r = await e.apply(await e.plan(await e.inspect(places.sourceFor('folder', const BackupSettings())!, BackupKind.family, key)));
      expect(r.roundTripOk, isTrue);
    });

    test('one file to carry: saved, found again by its path, restored; a missing or damaged file is refused', () async {
      final DeviceBackupPlaces places = DeviceBackupPlaces(root: Directory('${root.path}/olive_backups'));
      expect(await places.saveCopyFile(BackupKind.family, const BackupSettings()), isNull, reason: 'nothing to save yet');
      final RecoverySheet sheet = await RecoverySheet.make(BackupPurpose.family, random: Random(3));
      final LocalServices s = Phone().open();
      await populate(s, BackupKind.family);
      await BackupService(services: s).run(BackupKind.family, places.destinations(const BackupSettings())['folder']!, sheet.publicKey);
      final String name = (await places.saveCopyFile(BackupKind.family, const BackupSettings()))!;
      expect(name, endsWith('.olivebackup'));
      final String path = '${root.path}/olive_backups/$name';
      expect(File(path).existsSync(), isTrue);
      expect(File('$path.tmp').existsSync(), isFalse);
      final BackupTarget carried = await places.targetFromFile(path);
      final BackupKeyPair key = await BackupKeyPair.fromSecret(sheet.secret, BackupPurpose.family);
      final LocalServices fresh = Phone().open();
      final RestoreEngine e = RestoreEngine(services: fresh);
      expect((await e.apply(await e.plan(await e.inspect(carried, BackupKind.family, key)))).roundTripOk, isTrue);

      await expectLater(places.targetFromFile('${root.path}/nope.olivebackup'), throwsA(isA<BackupTargetException>()));
      final File bad = File('${root.path}/bad.olivebackup')..writeAsBytesSync(<int>[1, 2, 3]);
      await expectLater(places.targetFromFile(bad.path), throwsA(isA<BackupTargetException>()));
    });
  });
}

class _ExplodingPlaces implements BackupPlaces {
  @override
  bool get serverAvailable => throw StateError('boom');
  @override
  Map<String, BackupDestination> destinations(BackupSettings settings) => throw StateError('boom');
  @override
  BackupTarget? sourceFor(String id, BackupSettings settings) => throw StateError('boom');
  @override
  Future<BackupTarget> targetFromFile(String path) => throw StateError('boom');
  @override
  Future<String?> saveCopyFile(BackupKind kind, BackupSettings settings) => throw StateError('boom');
}
