// OLIVE BRANCH — the verified round trip the owner asked for: back up a phone and a tablet, restore onto a NEW phone and
// a REPLACEMENT tablet, and prove (a content hash of every area, before and after, equal) that nothing was lost.
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
import 'package:olive_client/restore_engine.dart';

import 'support/backup_rig.dart';

Future<Map<String, String>> _hashes(LocalServices s, BackupKind kind) async {
  final BackupSnapshot snap = await captureSnapshot(s.store, kind);
  return <String, String>{for (final AreaSnapshot a in snap.areas) a.namespace: a.hash};
}

void main() {
  late Directory root;
  setUp(() async => root = await Directory.systemTemp.createTemp('olive_roundtrip_'));
  tearDown(() => root.delete(recursive: true));

  test('NEW PHONE: every family area, from a real folder, comes back with an identical content hash', () async {
    final RecoverySheet sheet = await RecoverySheet.make(BackupPurpose.family, random: Random(1));
    final BackupKeyPair key = await BackupKeyPair.fromSecret(sheet.secret, BackupPurpose.family);

    // The old phone, with something in every area a family backup holds, including a multi-chunk one.
    final Phone oldPhone = Phone();
    final LocalServices old = oldPhone.open();
    await populate(old, BackupKind.family, bigPictures: 0);
    await old.area('care').put('long', <String, Object?>{'text': List<String>.filled(30000, 'a binder page ').join()});
    final Map<String, String> before = await _hashes(old, BackupKind.family);
    expect(before.length, areasOfBackup(BackupKind.family).length, reason: 'every area has something in it');

    final DirectoryBackupTarget folder = DirectoryBackupTarget(Directory('${root.path}/olive_backups'));
    final BackupService bs = BackupService(services: old, random: Random(2));
    final BackupOutcome out = await bs.run(BackupKind.family,
        BackupDestination(id: 'folder', target: folder, spool: DirectoryBackupTarget(Directory('${root.path}/spool')), verifyEveryChunk: true),
        sheet.publicKey);
    expect(out.ok, isTrue, reason: out.code);
    expect(out.totalChunks, greaterThan(1), reason: 'the round trip crosses chunk boundaries');

    // The old phone is gone. A new phone, nothing on it, the sheet typed back from the words.
    final WordsResult typed = wordsToSecret(sheet.words.join(' '));
    final BackupKeyPair typedKey = await BackupKeyPair.fromSecret(typed.bytes!, BackupPurpose.family);
    final Phone newPhone = Phone();
    final LocalServices fresh = newPhone.open();
    final RestoreEngine e = RestoreEngine(services: fresh);
    final RestoreInspection i = await e.inspect(folder, BackupKind.family, typedKey);
    final RestoreReport r = await e.apply(await e.plan(i));

    expect(r.roundTripOk, isTrue);
    final Map<String, String> after = await _hashes(fresh, BackupKind.family);
    expect(after, before, reason: 'the content hash of every area is equal before and after');
    expect(await setContentHash(after), await setContentHash(before));
    expect(i.manifest.contentHash, await setContentHash(before), reason: 'and equals what the backup recorded');
    // Value by value, not just by hash.
    for (final String area in areasOfBackup(BackupKind.family)) {
      expect(await fresh.area(area).snapshot(), await old.area(area).snapshot(), reason: area);
    }
  });

  test('REPLACEMENT TABLET with the old tablet to hand: the hand-over code brings drawings, memories, her home AND her private areas', () async {
    final Phone oldTab = Phone();
    final LocalServices tab = oldTab.open();
    final ChildKeyKeeper keeper = ChildKeyKeeper(tab.area('childkeys'));
    final ChildSecrets secrets = await keeper.ensure(random: Random(3));
    await populate(tab, BackupKind.hersKeep, bigPictures: 9000);
    await populate(tab, BackupKind.hersPrivate);
    final Map<String, String> keepBefore = await _hashes(tab, BackupKind.hersKeep);
    final Map<String, String> privBefore = await _hashes(tab, BackupKind.hersPrivate);
    expect(keepBefore.keys.any((String n) => n.endsWith('.pictures')), isTrue);
    expect(keepBefore.keys.any((String n) => n.endsWith('.access')), isTrue, reason: 'her home settings travel too');
    expect(privBefore.keys.any((String n) => n.endsWith('.journal')), isTrue);

    final MemoryBackupTarget keepT = MemoryBackupTarget(), privT = MemoryBackupTarget();
    final BackupKeyPair keepKey = await BackupKeyPair.fromSecret(secrets.keep, BackupPurpose.keep);
    final BackupKeyPair privKey = await BackupKeyPair.fromSecret(secrets.private, BackupPurpose.private);
    final BackupService bs = BackupService(services: tab, random: Random(4), deviceLabel: 'Her tablet');
    expect((await bs.run(BackupKind.hersKeep, BackupDestination(id: 'folder', target: keepT, spool: MemoryBackupTarget()), keepKey.publicKey)).ok, isTrue);
    expect((await bs.run(BackupKind.hersPrivate, BackupDestination(id: 'folder', target: privT, spool: MemoryBackupTarget()), privKey.publicKey)).ok, isTrue);

    // A grown-up phone CARRIES the sealed sets (as files) but holds neither tablet secret. It cannot open them.
    final Uint8List keepFile = await BackupBundle.pack(keepT, BackupKind.hersKeep, (await keepT.committed(BackupKind.hersKeep)).single.setId);
    final Uint8List privFile = await BackupBundle.pack(privT, BackupKind.hersPrivate, (await privT.committed(BackupKind.hersPrivate)).single.setId);
    final BackupKeyPair familyKey = await BackupKeyPair.fromSecret(newBackupSecret(Random(5)), BackupPurpose.family);
    for (final MapEntry<BackupKind, Uint8List> f in <MapEntry<BackupKind, Uint8List>>[
      MapEntry<BackupKind, Uint8List>(BackupKind.hersKeep, keepFile),
      MapEntry<BackupKind, Uint8List>(BackupKind.hersPrivate, privFile),
    ]) {
      final MemoryBackupTarget parent = MemoryBackupTarget();
      final CommittedSet c = await BackupBundle.unpackInto(parent, f.value);
      await expectLater(openManifest(c.header, c.manifest, familyKey), throwsA(isA<BackupFormatException>()),
          reason: 'a grown-up key opens nothing of hers');
    }

    // The new tablet: the adult types the hand-over words from the old tablet.
    final WordsResult typed = ChildSecrets.readHandover(secrets.handoverWords.join(' '));
    final ChildSecrets got = ChildSecrets.fromHandover(typed.bytes!);
    final Phone newTab = Phone();
    final LocalServices fresh = newTab.open();
    final MemoryBackupTarget carriedKeep = MemoryBackupTarget(), carriedPriv = MemoryBackupTarget();
    await BackupBundle.unpackInto(carriedKeep, keepFile);
    await BackupBundle.unpackInto(carriedPriv, privFile);
    final RestoreEngine e = RestoreEngine(services: fresh);
    final RestoreReport rk = await e.apply(await e.plan(await e.inspect(carriedKeep, BackupKind.hersKeep, await BackupKeyPair.fromSecret(got.keep, BackupPurpose.keep))));
    final RestoreReport rp = await e.apply(await e.plan(await e.inspect(carriedPriv, BackupKind.hersPrivate, await BackupKeyPair.fromSecret(got.private, BackupPurpose.private))));
    await ChildKeyKeeper(fresh.area('childkeys')).adopt(got);

    expect(rk.roundTripOk && rp.roundTripOk, isTrue);
    expect(await _hashes(fresh, BackupKind.hersKeep), keepBefore);
    expect(await _hashes(fresh, BackupKind.hersPrivate), privBefore);
    expect((await ChildKeyKeeper(fresh.area('childkeys')).read())!.keep, secrets.keep, reason: 'later backups share the keys');
  });

  test('REPLACEMENT TABLET with the old one gone: only a keepsake sheet (if the family made one) brings back the keepsakes; her private areas are not recoverable by anyone', () async {
    final Phone oldTab = Phone();
    final LocalServices tab = oldTab.open();
    final ChildSecrets secrets = await ChildKeyKeeper(tab.area('childkeys')).ensure(random: Random(6));
    await populate(tab, BackupKind.hersKeep);
    await populate(tab, BackupKind.hersPrivate);
    final Map<String, String> keepBefore = await _hashes(tab, BackupKind.hersKeep);
    final MemoryBackupTarget keepT = MemoryBackupTarget(), privT = MemoryBackupTarget();
    final BackupKeyPair keepKey = await BackupKeyPair.fromSecret(secrets.keep, BackupPurpose.keep);
    final BackupKeyPair privKey = await BackupKeyPair.fromSecret(secrets.private, BackupPurpose.private);
    final BackupService bs = BackupService(services: tab, random: Random(7));
    await bs.run(BackupKind.hersKeep, BackupDestination(id: 'folder', target: keepT, spool: MemoryBackupTarget()), keepKey.publicKey);
    await bs.run(BackupKind.hersPrivate, BackupDestination(id: 'folder', target: privT, spool: MemoryBackupTarget()), privKey.publicKey);

    // The family had written the keepsake secret on a sheet (14 words). The private secret was never written anywhere.
    final KeepsakeSheetDouble sheet = KeepsakeSheetDouble(secrets.keep);
    final BackupKeyPair fromSheet = await BackupKeyPair.fromSecret(sheet.typedBack(), BackupPurpose.keep);
    final Phone newTab = Phone();
    final LocalServices fresh = newTab.open();
    final RestoreEngine e = RestoreEngine(services: fresh);
    final RestoreReport rk = await e.apply(await e.plan(await e.inspect(keepT, BackupKind.hersKeep, fromSheet)));
    expect(rk.roundTripOk, isTrue);
    expect(await _hashes(fresh, BackupKind.hersKeep), keepBefore);

    // The sheet's words do NOT open the private backup: the key for it is a different one.
    await expectLater(e.inspect(privT, BackupKind.hersPrivate, await BackupKeyPair.fromSecret(secrets.keep, BackupPurpose.private)),
        throwsA(isA<RestoreProblem>().having((RestoreProblem p) => p.code, 'code', 'key')));
    expect(fresh.store.namespaces().then((List<String> n) => n.any((String x) => x.endsWith('.journal'))), completion(isFalse));
  });

  test('a phone that is restored over a half-used one merges, and the round trip is still exact for what came from the backup', () async {
    final RecoverySheet sheet = await RecoverySheet.make(BackupPurpose.family, random: Random(8));
    final BackupKeyPair key = await BackupKeyPair.fromSecret(sheet.secret, BackupPurpose.family);
    final LocalServices old = Phone().open();
    await populate(old, BackupKind.family, seed: 1);
    final MemoryBackupTarget t = MemoryBackupTarget();
    await BackupService(services: old, random: Random(9))
        .run(BackupKind.family, BackupDestination(id: 'folder', target: t, spool: MemoryBackupTarget()), sheet.publicKey);

    final LocalServices used = Phone().open();
    await populate(used, BackupKind.family, seed: 2); // different content under the same keys
    await used.area('care').put('only-here', 'written since the old phone was lost');

    final RestoreEngine e = RestoreEngine(services: used);
    final RestorePlan plan = await e.plan(await e.inspect(t, BackupKind.family, key));
    expect(plan.setAsideCount, greaterThan(0));
    final RestoreReport r = await e.apply(plan);
    expect(r.roundTripOk, isTrue, reason: 'every area ends with exactly the fingerprint the merge computed');
    // Nothing the phone held is gone, and nothing the backup held is gone (kept, or set aside).
    expect(await used.area('care').get('only-here'), 'written since the old phone was lost');
    for (final String k in <String>['k0', 'k1', 'k2']) {
      expect(await used.area('care').get(k), isNotNull);
    }
    final Map<String, Object?> kept = await used.area('backupkept').snapshot();
    expect(kept, isNotEmpty);
  });
}

/// Stands for the paper: a secret turned into words and typed back.
class KeepsakeSheetDouble {
  KeepsakeSheetDouble(this.secret);
  final Uint8List secret;
  Uint8List typedBack() => wordsToSecret(secretToWords(secret).join(' ')).bytes!;
}
