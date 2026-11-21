// OLIVE BRANCH — backup client, the core: the sheet's words, which areas a backup may take, the sealing, a whole
// backup and restore round trip (phone to new phone, tablet to replacement tablet) with a verified hash for every
// area, a kill at every step of sending and of restoring, and the hostile cases.
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/backup_classes.dart';
import 'package:olive_client/backup_crypto.dart';
import 'package:olive_client/backup_engine.dart';
import 'package:olive_client/backup_header.dart';
import 'package:olive_client/backup_merge.dart';
import 'package:olive_client/backup_restore.dart';
import 'package:olive_client/backup_service.dart';
import 'package:olive_client/backup_sink.dart';
import 'package:olive_client/backup_words.dart';
import 'package:olive_client/local_services.dart';
import 'package:olive_client/local_store.dart';

import 'support/backup_rig.dart';

/// A family phone with some real records on it, and a sheet.
Future<({Rig phone, RecoveryKey key})> _family({int seed = 1, TestClock? clock}) async {
  final Rig p = await Rig.make(seed: seed, clock: clock);
  await p.put('care', <String, Object?>{'n1': <String, Object?>{'id': 'n1', 'text': 'allergy note'}, 'n2': 'second'}, owner: 'ivy');
  await p.put('emergencycard', <String, Object?>{'card': <String, Object?>{'v': 3, 'who': 'Mom', 'list': <Object?>['a', 'b']}}, owner: 'ivy');
  await p.put('coordination', <String, Object?>{'doses': <Object?>[<String, Object?>{'id': 'd1', 'at': 5}]}, owner: 'ivy');
  await p.put('learn', <String, Object?>{'read': <Object?>['x', 'y']});
  await p.put('familyledger', <String, Object?>{'family': <String, Object?>{'e': <Object?>['founding']}});
  await p.put('plan', <String, Object?>{'blocks': <Object?>['wake', 'eat']}, owner: 'ivy');
  final RecoveryKey key = await p.svc.setUp();
  return (phone: p, key: key);
}

String _all(Iterable<List<int>> parts) => parts.map(latin1.decode).join();

void main() {
  group('the sheet', () {
    test('256 words, all different, and a sheet reads back exactly as written', () {
      expect(kBackupWords.length, 256);
      expect(kBackupWords.toSet().length, 256);
      final RecoveryKey k = RecoveryKey.generate(random: Random(7));
      expect(k.words.length, kSheetWords);
      final SheetParse p = RecoveryKey.parse(k.words.join(' '));
      expect(p.ok, isTrue);
      expect(p.key, k);
      expect(RecoveryKey.parse(k.words.join(',\n').toUpperCase()).key, k, reason: 'case, commas and lines do not matter');
    });

    test('a mistyped, swapped or missing word is caught before anything is tried', () {
      final RecoveryKey k = RecoveryKey.generate(random: Random(8));
      final List<String> w = k.words;
      expect(RecoveryKey.parse(w.take(17).join(' ')).problem, SheetProblem.wrongCount);
      expect(RecoveryKey.parse('${w.take(17).join(' ')} zzzzqq').problem, SheetProblem.unknownWord);
      final List<String> swapped = List<String>.of(w);
      final String t = swapped[3];
      swapped[3] = swapped[4] == t ? kBackupWords[(kBackupWords.indexOf(t) + 1) % 256] : swapped[4];
      swapped[4] = t;
      expect(RecoveryKey.parse(swapped.join(' ')).problem, SheetProblem.checkFailed);
    });

    test('the key never shows its seed, even by accident', () {
      final RecoveryKey k = RecoveryKey.generate(random: Random(9));
      expect(k.toString(), 'RecoveryKey(hidden)');
      expect('$k', isNot(contains(k.words.first)));
    });

    test('the paper check wants the first and the last word', () {
      final RecoveryKey k = RecoveryKey.generate(random: Random(10));
      expect(k.paperMatches(k.firstWord, k.lastWord), isTrue);
      expect(k.paperMatches(k.lastWord, k.firstWord), isFalse);
      expect(k.paperMatches('', ''), isFalse);
    });
  });

  group('which areas a backup takes', () {
    test('every catalogued area is classed on purpose, and nothing is classed that does not exist', () {
      final Set<String> areas = <String>{for (final LocalDataEntry e in localDataCatalogue) e.area};
      expect(areas.difference(kBackupClass.keys.toSet()), isEmpty,
          reason: 'a new area must be classed: decide whether a backup keeps it');
      expect(kBackupClass.keys.toSet().difference(areas), isEmpty);
    });

    test('the child\'s private areas and every device-only area are in no family backup, and never in any backup', () {
      for (final String a in <String>['journal', 'worries', 'feelings', 'teen']) {
        expect(backupTakes(BackupKind.family, a), isFalse, reason: a);
        expect(backupTakes(BackupKind.keepsake, a), isFalse, reason: a);
      }
      for (final String a in <String>['devicekey', 'localpin', 'adultunlock', 'childpairing', 'role', 'account', 'outbox']) {
        expect(backupTakes(BackupKind.family, a), isFalse, reason: a);
        expect(backupTakes(BackupKind.keepsake, a), isFalse, reason: a);
      }
      for (final String a in <String>['pictures', 'memorybox', 'mymarks', 'lists', 'stories', 'jokes', 'collections', 'nicknames']) {
        expect(backupTakes(BackupKind.family, a), isFalse, reason: 'a grown-up backup never carries $a');
        expect(backupTakes(BackupKind.keepsake, a), isTrue);
      }
      for (final String a in <String>['care', 'emergencycard', 'coordination', 'aboutchild', 'passes', 'familyledger', 'learn']) {
        expect(backupTakes(BackupKind.keepsake, a), isFalse, reason: 'her tablet never carries $a');
        expect(backupTakes(BackupKind.family, a), isTrue);
      }
    });

    test('an unknown area is never taken', () {
      expect(backupTakes(BackupKind.family, 'brand-new-area'), isFalse);
      expect(backupTakes(BackupKind.keepsake, 'brand-new-area'), isFalse);
    });

    test('a namespace is read exactly or not at all', () {
      expect(parseAreaName('child.ivy.care')?.namespace, 'child.ivy.care');
      expect(parseAreaName('guardian.mom.learn')?.namespace, 'guardian.mom.learn');
      expect(parseAreaName('device.backupstate')?.area, 'backupstate');
      for (final String bad in <String>['child.ivy.nope', 'child..care', 'child.ivy.care.undo', 'guardian.mom', '../x', 'device.care', '']) {
        expect(parseAreaName(bad), isNull, reason: bad);
      }
    });
  });

  group('the sealing', () {
    test('a data key opens only for the family it was sealed to, the kind and the set', () async {
      final RecoveryKey a = RecoveryKey.generate(random: Random(1)), b = RecoveryKey.generate(random: Random(2));
      final BackupKeyPair pa = await deriveBackupKeyPair(a, BackupKind.family);
      final BackupKeyPair pb = await deriveBackupKeyPair(b, BackupKind.family);
      final BackupKeyPair pak = await deriveBackupKeyPair(a, BackupKind.keepsake);
      final Uint8List dk = newDataKey(random: Random(3));
      final String set = await backupSetId(pa.publicKey, BackupKind.family);
      final Uint8List wrap = await wrapDataKey(recipientPublic: pa.publicKey, dk: dk, setId: set, kind: BackupKind.family, random: Random(4));
      expect(await unwrapDataKey(pair: pa, wrapped: wrap, setId: set, kind: BackupKind.family), dk);
      expect(await unwrapDataKey(pair: pb, wrapped: wrap, setId: set, kind: BackupKind.family), isNull, reason: 'another family');
      expect(await unwrapDataKey(pair: pak, wrapped: wrap, setId: set, kind: BackupKind.family), isNull, reason: 'the other kind of key');
      expect(await unwrapDataKey(pair: pa, wrapped: wrap, setId: set, kind: BackupKind.keepsake), isNull);
      expect(await unwrapDataKey(pair: pa, wrapped: wrap, setId: '0' * 32, kind: BackupKind.family), isNull);
      final Uint8List cut = Uint8List.fromList(wrap)..[40] ^= 1;
      expect(await unwrapDataKey(pair: pa, wrapped: cut, setId: set, kind: BackupKind.family), isNull);
      expect(await unwrapDataKey(pair: pa, wrapped: wrap.sublist(0, 79), setId: set, kind: BackupKind.family), isNull);
    });

    test('a sealed chunk opens only with its key and its own associated data', () async {
      final Uint8List dk = newDataKey(random: Random(5));
      final Uint8List sealed = await sealUnder(dk, utf8.encode('hello'), chunkAad('a' * 32));
      expect(utf8.decode((await openUnder(dk, sealed, chunkAad('a' * 32)))!), 'hello');
      expect(await openUnder(dk, sealed, chunkAad('b' * 32)), isNull);
      expect(await openUnder(newDataKey(random: Random(6)), sealed, chunkAad('a' * 32)), isNull);
      expect(await openUnder(dk, sealed.sublist(0, 20), chunkAad('a' * 32)), isNull);
      expect(await openUnder(dk, Uint8List(0), chunkAad('a' * 32)), isNull);
    });

    test('a certificate is the sheet\'s, for one phone and one kind', () async {
      final RecoveryKey a = RecoveryKey.generate(random: Random(1)), b = RecoveryKey.generate(random: Random(2));
      final BackupAuthority aa = await deriveBackupAuthority(a, BackupKind.family);
      final BackupAuthority ab = await deriveBackupAuthority(b, BackupKind.family);
      final Rig p = await Rig.make(seed: 3), q = await Rig.make(seed: 4);
      final Uint8List cert = await aa.certifyWriter(p.writer.publicKey, BackupKind.family);
      expect(await BackupAuthority.verifyWriter(aa.publicKey, BackupKind.family, p.writer.publicKey, cert), isTrue);
      expect(await BackupAuthority.verifyWriter(ab.publicKey, BackupKind.family, p.writer.publicKey, cert), isFalse);
      expect(await BackupAuthority.verifyWriter(aa.publicKey, BackupKind.family, q.writer.publicKey, cert), isFalse);
      expect(await BackupAuthority.verifyWriter(aa.publicKey, BackupKind.keepsake, p.writer.publicKey, cert), isFalse);
    });

    test('the signing key and the sealing key are different keys', () async {
      final RecoveryKey a = RecoveryKey.generate(random: Random(1));
      expect((await deriveBackupAuthority(a, BackupKind.family)).publicKey,
          isNot((await deriveBackupKeyPair(a, BackupKind.family)).publicKey));
      expect((await deriveBackupAuthority(a, BackupKind.keepsake)).publicKey,
          isNot((await deriveBackupAuthority(a, BackupKind.family)).publicKey));
    });

    test('canonical JSON is the same however the keys were written', () {
      expect(canonicalJson(<String, Object?>{'b': 1, 'a': <String, Object?>{'y': 2, 'x': <Object?>[3, 1]}}),
          canonicalJson(<String, Object?>{'a': <String, Object?>{'x': <Object?>[3, 1], 'y': 2}, 'b': 1}));
    });
  });

  group('a phone\'s whole backup, to a new phone', () {
    test('every area comes back with the same content hash, written by a different phone', () async {
      final f = await _family();
      final MemoryBackupSink sink = MemoryBackupSink();
      final BackupReport r = await f.phone.svc.engine.backUp(kind: BackupKind.family, sinks: <BackupSink>[sink]);
      expect(r.ok, isTrue);
      expect(r.areas, 6);
      final Map<String, String> before = await f.phone.hashes();

      final Rig fresh = await Rig.make(seed: 2);
      final RestoreEngine re = fresh.svc.restoreEngine();
      final RestoreOpen o = await re.open(source: sink, key: f.key, kind: BackupKind.family);
      expect(o.areaCount, 6);
      final RestoreOutcome out = await re.apply(o);
      expect(out.restoredNamespaces.length, 6);
      expect(await fresh.hashes(), before, reason: 'every area reads back with the hash it had');
      expect(out.hashesAfter.values.toSet(), before.values.toSet());
      expect(await fresh.services.area('care', ownerId: 'ivy').get('n1'), <String, Object?>{'id': 'n1', 'text': 'allergy note'});
    });

    test('a phone that has the family\'s sheet typed in can back up for it and a third phone can restore that', () async {
      final f = await _family();
      final MemoryBackupSink sink = MemoryBackupSink();
      await f.phone.svc.engine.backUp(kind: BackupKind.family, sinks: <BackupSink>[sink]);
      final Rig second = await Rig.make(seed: 2);
      expect(await second.svc.joinWithSheet(f.key.words.join(' ')), SheetOutcome.ok);
      await second.put('learn', <String, Object?>{'read': <Object?>['z']});
      await second.svc.engine.backUp(kind: BackupKind.family, sinks: <BackupSink>[sink]);
      expect(sink.manifests.length, 2, reason: 'two phones, one backup each');
      final Rig third = await Rig.make(seed: 3);
      final RestoreEngine re = third.svc.restoreEngine();
      final RestoreOpen o = await re.open(source: sink, key: f.key, kind: BackupKind.family);
      expect(o.heads.length, 2);
      await re.apply(o);
      expect((await third.services.area('learn').get('read')) as List, containsAll(<String>['x', 'y', 'z']),
          reason: 'both phones\' notes are united');
    });

    test('a different grown-up id on the new phone still gets the grown-up\'s own areas', () async {
      final f = await _family();
      final MemoryBackupSink sink = MemoryBackupSink();
      await f.phone.svc.engine.backUp(kind: BackupKind.family, sinks: <BackupSink>[sink]);
      final Rig fresh = await Rig.make(seed: 2, guardian: 'mom-two');
      final RestoreEngine re = fresh.svc.restoreEngine();
      await re.apply(await re.open(source: sink, key: f.key, kind: BackupKind.family));
      expect(await fresh.services.area('learn').get('read'), <Object?>['x', 'y']);
    });

    test('the private areas, the journal and everything device-only stay out of a family backup even when present', () async {
      final f = await _family();
      await f.phone.put('journal', <String, Object?>{'e1': 'secret thoughts'}, owner: 'ivy');
      await f.phone.put('worries', <String, Object?>{'w': 'private worry'}, owner: 'ivy');
      await f.phone.put('feelings', <String, Object?>{'f': 'sad'}, owner: 'ivy');
      await f.phone.put('pictures', <String, Object?>{'p': 'my doodle'}, owner: 'ivy');
      await f.phone.put('localpin', <String, Object?>{'hash': 'abc'});
      await f.phone.put('devicekey', <String, Object?>{'seed': 'zzzz'});
      final MemoryBackupSink sink = MemoryBackupSink();
      await f.phone.svc.engine.backUp(kind: BackupKind.family, sinks: <BackupSink>[sink]);
      final Rig fresh = await Rig.make(seed: 2);
      final RestoreEngine re = fresh.svc.restoreEngine();
      await re.apply(await re.open(source: sink, key: f.key, kind: BackupKind.family));
      for (final String n in await fresh.services.store.namespaces()) {
        for (final String banned in <String>['journal', 'worries', 'feelings', 'pictures', 'localpin', 'devicekey']) {
          expect(n.endsWith('.$banned'), isFalse, reason: n);
        }
      }
      final String bytes = _all(<Uint8List>[...sink.chunks.values, ...sink.manifests.values]);
      for (final String s in <String>['secret thoughts', 'private worry', 'my doodle', 'allergy note', 'journal', 'emergencycard']) {
        expect(bytes.contains(s), isFalse, reason: 'nothing readable is at the destination: $s');
      }
    });

    test('the destination sees only sealed bytes and names that say nothing', () async {
      final f = await _family();
      final MemoryBackupSink sink = MemoryBackupSink();
      await f.phone.svc.engine.backUp(kind: BackupKind.family, sinks: <BackupSink>[sink]);
      for (final String k in sink.chunks.keys) {
        expect(RegExp(r'^[0-9a-f]{32}/[0-9a-f]{64}$').hasMatch(k), isTrue, reason: k);
      }
      for (final String k in sink.manifests.keys) {
        expect(RegExp(r'^[0-9a-f]{32}/[0-9]{10}-[0-9a-f]{8}$').hasMatch(k), isTrue, reason: k);
      }
    });

    test('a restore twice changes nothing the second time', () async {
      final f = await _family();
      final MemoryBackupSink sink = MemoryBackupSink();
      await f.phone.svc.engine.backUp(kind: BackupKind.family, sinks: <BackupSink>[sink]);
      final Rig fresh = await Rig.make(seed: 2);
      final RestoreEngine re = fresh.svc.restoreEngine();
      await re.apply(await re.open(source: sink, key: f.key, kind: BackupKind.family));
      final Map<String, String> once = await fresh.hashes();
      final RestoreOutcome again = await re.apply(await re.open(source: sink, key: f.key, kind: BackupKind.family));
      expect(again.restoredNamespaces, isEmpty);
      expect(await fresh.hashes(), once);
    });

    test('a restore onto a phone that holds other things keeps both: lists unite, a different value is set aside', () async {
      final f = await _family();
      final MemoryBackupSink sink = MemoryBackupSink();
      await f.phone.svc.engine.backUp(kind: BackupKind.family, sinks: <BackupSink>[sink]);
      final Rig other = await Rig.make(seed: 2);
      await other.put('learn', <String, Object?>{'read': <Object?>['x', 'new'], 'extra': 'mine'});
      await other.put('emergencycard', <String, Object?>{'card': <String, Object?>{'v': 9, 'who': 'Dad', 'list': <Object?>['c']}}, owner: 'ivy');
      final RestoreEngine re = other.svc.restoreEngine();
      final RestoreOpen o = await re.open(source: sink, key: f.key, kind: BackupKind.family);
      final RestorePlan plan = await re.plan(o);
      expect(plan.conflicts, isNotEmpty);
      final RestoreOutcome out = await re.apply(o);
      expect(out.setAside, greaterThan(0));
      expect((await other.services.area('learn').get('read')) as List, <Object?>['x', 'new', 'y'], reason: 'union, this phone first');
      expect(await other.services.area('learn').get('extra'), 'mine');
      final Map<String, Object?> card = (await other.services.area('emergencycard', ownerId: 'ivy').get('card')) as Map<String, Object?>;
      expect(card['v'], 9, reason: 'this phone\'s newer value is kept');
      final Map<String, Object?> aside = await other.services.area('backupaside').snapshot();
      expect(jsonEncode(aside), contains('"from":"backup"'));
    });

    test('"use the backup\'s" swaps the two and sets this phone\'s aside', () async {
      final f = await _family();
      final MemoryBackupSink sink = MemoryBackupSink();
      await f.phone.svc.engine.backUp(kind: BackupKind.family, sinks: <BackupSink>[sink]);
      final Rig other = await Rig.make(seed: 2);
      await other.put('emergencycard', <String, Object?>{'card': <String, Object?>{'v': 9, 'who': 'Dad', 'list': <Object?>['c']}}, owner: 'ivy');
      final RestoreEngine re = other.svc.restoreEngine();
      await re.apply(await re.open(source: sink, key: f.key, kind: BackupKind.family), choice: ConflictChoice.useBackup);
      final Map<String, Object?> card = (await other.services.area('emergencycard', ownerId: 'ivy').get('card')) as Map<String, Object?>;
      expect(card['who'], 'Mom');
      expect(jsonEncode(await other.services.area('backupaside').snapshot()), contains('"from":"phone"'));
    });

    test('an older backup than the phone\'s own is refused until a grown-up says it is meant', () async {
      final f = await _family();
      final MemoryBackupSink sink = MemoryBackupSink();
      await f.phone.svc.engine.backUp(kind: BackupKind.family, sinks: <BackupSink>[sink]);
      final Rig fresh = await Rig.make(seed: 2);
      await fresh.state.setLastSeq(BackupKind.family, 9);
      final RestoreEngine re = fresh.svc.restoreEngine();
      final RestoreOpen o = await re.open(source: sink, key: f.key, kind: BackupKind.family);
      await expectLater(re.apply(o), throwsA(isA<RestoreBlocked>().having((RestoreBlocked b) => b.problem, 'problem', RestoreProblem.older)));
      expect((await re.apply(o, acceptOlder: true)).restoredNamespaces, isNotEmpty);
    });
  });

  group('her tablet, and a replacement tablet', () {
    Future<Rig> tablet({int seed = 5, String child = 'ivy'}) async {
      final Rig t = await Rig.make(role: BackupRole.child, child: child, seed: seed);
      await t.put('pictures', <String, Object?>{'p1': 'doodle'}, owner: child);
      await t.put('memorybox', <String, Object?>{'m1': 'a day at the lake'}, owner: child);
      await t.put('mymarks', <String, Object?>{'door': <Object?>[1, 2]}, owner: child);
      await t.put('nicknames', <String, Object?>{'mom': 'Mama'}, owner: child);
      await t.put('plan', <String, Object?>{'blocks': <Object?>['wake', 'eat']}, owner: child);
      await t.put('colour', <String, Object?>{'today': 'green'}, owner: child);
      return t;
    }

    test('her things and her home come back on a replacement tablet, hash for hash; the journal, worries, feelings and a grown-up\'s records never travel', () async {
      final Rig t = await tablet();
      await t.put('journal', <String, Object?>{'e': 'my private day'}, owner: 'ivy');
      await t.put('worries', <String, Object?>{'w': 'a worry'}, owner: 'ivy');
      await t.put('feelings', <String, Object?>{'f': 'happy'}, owner: 'ivy');
      await t.put('teen', <String, Object?>{'t': 'x'}, owner: 'ivy');
      await t.put('care', <String, Object?>{'n': 'a care note that should never be on her tablet backup'}, owner: 'ivy');
      final RecoveryKey sheet = await t.svc.setUp();
      final MemoryBackupSink sink = MemoryBackupSink();
      final BackupReport r = await t.svc.engine.backUp(kind: BackupKind.keepsake, sinks: <BackupSink>[sink]);
      expect(r.areas, 6);
      final String bytes = _all(<Uint8List>[...sink.chunks.values, ...sink.manifests.values]);
      for (final String s in <String>['my private day', 'a worry', 'a care note', 'doodle', 'lake']) {
        expect(bytes.contains(s), isFalse, reason: s);
      }
      final Map<String, String> before = await t.hashes();

      final Rig replacement = await Rig.make(role: BackupRole.child, child: 'ivy', seed: 6);
      final RestoreEngine re = replacement.svc.restoreEngine();
      final RestoreOpen o = await re.open(source: sink, key: sheet, kind: BackupKind.keepsake);
      await re.apply(o);
      expect(await replacement.hashes(), before);
      for (final String n in await replacement.services.store.namespaces()) {
        for (final String banned in <String>['journal', 'worries', 'feelings', 'teen', 'care']) {
          expect(n.endsWith('.$banned'), isFalse, reason: n);
        }
      }
    });

    test('no grown-up\'s phone can open or restore a keepsake, and a family sheet opens nothing of hers', () async {
      final Rig t = await tablet();
      final RecoveryKey keepsake = await t.svc.setUp();
      final MemoryBackupSink sink = MemoryBackupSink();
      await t.svc.engine.backUp(kind: BackupKind.keepsake, sinks: <BackupSink>[sink]);
      final f = await _family(seed: 7);
      final RestoreEngine grownUp = f.phone.svc.restoreEngine();
      await expectLater(grownUp.open(source: sink, key: keepsake, kind: BackupKind.keepsake),
          throwsA(isA<RestoreBlocked>().having((RestoreBlocked b) => b.problem, 'problem', RestoreProblem.wrongDevice)));
      // The family's sheet, tried on a replacement tablet, finds nothing of hers.
      final Rig replacement = await Rig.make(role: BackupRole.child, child: 'ivy', seed: 6);
      await expectLater(replacement.svc.restoreEngine().open(source: sink, key: f.key, kind: BackupKind.keepsake),
          throwsA(isA<RestoreBlocked>().having((RestoreBlocked b) => b.problem, 'problem', RestoreProblem.nothingFound)));
      // A tablet cannot be asked to make a family backup, and a phone cannot be asked to make a keepsake.
      expect(() => t.svc.engine.gather(BackupKind.family), throwsStateError);
      expect(() => f.phone.svc.engine.gather(BackupKind.keepsake), throwsStateError);
    });

    test('a keepsake for another child is refused', () async {
      final Rig t = await tablet();
      final RecoveryKey sheet = await t.svc.setUp();
      final MemoryBackupSink sink = MemoryBackupSink();
      await t.svc.engine.backUp(kind: BackupKind.keepsake, sinks: <BackupSink>[sink]);
      final Rig other = await Rig.make(role: BackupRole.child, child: 'wren', seed: 6);
      final RestoreEngine re = other.svc.restoreEngine();
      final RestoreOpen o = await re.open(source: sink, key: sheet, kind: BackupKind.keepsake);
      await expectLater(re.apply(o), throwsA(isA<RestoreBlocked>().having((RestoreBlocked b) => b.problem, 'problem', RestoreProblem.wrongChild)));
      expect(await other.hashes(), isEmpty);
    });

    test('a restore onto an unpaired tablet can be held back until a grown-up has connected it', () async {
      final Rig t = await tablet();
      final RecoveryKey sheet = await t.svc.setUp();
      final MemoryBackupSink sink = MemoryBackupSink();
      await t.svc.engine.backUp(kind: BackupKind.keepsake, sinks: <BackupSink>[sink]);
      final Rig r = await Rig.make(role: BackupRole.child, child: 'ivy', seed: 6);
      final RestoreEngine re = r.svc.restoreEngine();
      final RestoreOpen o = await re.open(source: sink, key: sheet, kind: BackupKind.keepsake);
      await expectLater(re.apply(o, requirePaired: true),
          throwsA(isA<RestoreBlocked>().having((RestoreBlocked b) => b.problem, 'problem', RestoreProblem.notPaired)));
      await r.put('childpairing', <String, Object?>{'cert': 'x'});
      expect((await re.apply(o, requirePaired: true)).restoredNamespaces, isNotEmpty);
    });
  });

  group('kill anywhere while sending', () {
    test('a run cut off after some chunks carries on with the same chunks and sends only what is missing', () async {
      final f = await _family();
      final MemoryBackupSink sink = MemoryBackupSink();
      int chunkPuts = 0;
      sink.onOp = (String op) {
        if (op == 'putChunk' && ++chunkPuts == 2) throw StateError('killed');
      };
      await expectLater(f.phone.svc.engine.backUp(kind: BackupKind.family, sinks: <BackupSink>[sink]), throwsStateError);
      expect(sink.manifests, isEmpty, reason: 'no manifest, so no half backup is ever visible');
      sink.onOp = null;
      final BackupReport r = await f.phone.svc.engine.backUp(kind: BackupKind.family, sinks: <BackupSink>[sink]);
      expect(r.resumed, isTrue);
      expect(r.ok, isTrue);
      expect(r.sinks.single.skipped, 1, reason: 'the chunk that already arrived is not sent again');
      expect(sink.manifests.length, 1);
    });

    test('a kill at every single operation leaves a backup that opens whole, never a half one', () async {
      final f = await _family();
      final MemoryBackupSink sink = MemoryBackupSink();
      await f.phone.svc.engine.backUp(kind: BackupKind.family, sinks: <BackupSink>[sink]);
      final Map<String, String> first = await f.phone.hashes();
      await f.phone.put('learn', <String, Object?>{'read': <Object?>['x', 'y', 'later']});
      final Map<String, String> second = await f.phone.hashes();
      expect(second, isNot(first));
      final Map<String, Uint8List> chunks0 = Map<String, Uint8List>.of(sink.chunks);
      final Map<String, Uint8List> man0 = Map<String, Uint8List>.of(sink.manifests);
      int die = 1;
      for (; die < 80; die++) {
        sink.chunks
          ..clear()
          ..addAll(chunks0);
        sink.manifests
          ..clear()
          ..addAll(man0);
        final Rig phone = f.phone;
        await phone.svc.staging.clear(BackupKind.family);
        int n = 0;
        sink.onOp = (String op) {
          if (++n == die) throw StateError('killed');
        };
        bool killed = false;
        try {
          await phone.svc.engine.backUp(kind: BackupKind.family, sinks: <BackupSink>[sink]);
        } on StateError {
          killed = true;
        }
        sink.onOp = null;
        // Whatever happened, a new phone can restore, and gets the first or the second backup whole.
        final Rig fresh = await Rig.make(seed: 2);
        final RestoreEngine re = fresh.svc.restoreEngine();
        final RestoreOpen o = await re.open(source: sink, key: f.key, kind: BackupKind.family);
        await re.apply(o);
        final Map<String, String> got = await fresh.hashes();
        expect(<bool>[jsonEncode(got) == jsonEncode(first), jsonEncode(got) == jsonEncode(second)].contains(true), isTrue,
            reason: 'kill at op $die gave neither whole backup');
        if (!killed) break;
      }
      expect(die, lessThan(80), reason: 'the sweep reached a run with no kill');
    });

    test('a destination that is full or away does not lose the backup: it is kept to try again and the failure is recorded', () async {
      final f = await _family();
      final MemoryBackupSink good = MemoryBackupSink(label: 'good');
      final MemoryBackupSink bad = MemoryBackupSink(label: 'away');
      bad.onOp = (String op) {
        if (op == 'putChunk') throw const BackupSinkException('full');
      };
      final BackupReport r = await f.phone.svc.engine.backUp(kind: BackupKind.family, sinks: <BackupSink>[good, bad]);
      expect(r.ok, isTrue, reason: 'one place has it');
      expect(r.allOk, isFalse);
      expect(r.sinks.last.code, 'full');
      final BackupStatus st = await f.phone.svc.status();
      expect(st.lastOk, isNotNull);
      bad.onOp = null;
      final BackupReport r2 = await f.phone.svc.engine.backUp(kind: BackupKind.family, sinks: <BackupSink>[good, bad]);
      expect(r2.resumed, isTrue, reason: 'the staged backup is reused for the place that missed it');
      expect(r2.allOk, isTrue);
    });

    test('a real folder: chunks and manifests are written whole, and a leftover half-written file is never read', () async {
      final f = await _family();
      final Directory dir = await Directory.systemTemp.createTemp('olive_backup_test');
      try {
        final DirectoryBackupSink sink = DirectoryBackupSink(dir);
        final BackupReport r = await f.phone.svc.engine.backUp(kind: BackupKind.family, sinks: <BackupSink>[sink]);
        expect(r.ok, isTrue);
        final String set = (await sink.sets()).single;
        // A stray temp file where a manifest would be is not a manifest.
        await File('${dir.path}${Platform.pathSeparator}$set${Platform.pathSeparator}manifests${Platform.pathSeparator}0000000099-deadbeef.manifest.tmp')
            .writeAsBytes(<int>[1, 2, 3]);
        expect((await sink.listManifests(set)).length, 1);
        final Rig fresh = await Rig.make(seed: 2);
        final RestoreEngine re = fresh.svc.restoreEngine();
        await re.apply(await re.open(source: sink, key: f.key, kind: BackupKind.family));
        expect(await fresh.hashes(), await f.phone.hashes());
        // A name that is not a plain set or chunk name never reaches a path.
        await expectLater(sink.getChunk('../etc', 'a' * 64), throwsA(isA<BackupSinkException>()));
        await expectLater(sink.getManifest(set, '../../x'), throwsA(isA<BackupSinkException>()));
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('only the newest few of a phone\'s own backups stay, and only after a newer one is whole', () async {
      final f = await _family();
      final MemoryBackupSink sink = MemoryBackupSink();
      for (int i = 0; i < 6; i++) {
        await f.phone.put('learn', <String, Object?>{'k$i': i});
        await f.phone.svc.engine.backUp(kind: BackupKind.family, sinks: <BackupSink>[sink]);
      }
      expect(sink.manifests.length, kKeepGenerations);
      final Rig fresh = await Rig.make(seed: 2);
      final RestoreEngine re = fresh.svc.restoreEngine();
      await re.apply(await re.open(source: sink, key: f.key, kind: BackupKind.family));
      expect(await fresh.hashes(), await f.phone.hashes());
    });
  });

  group('hostile backups', () {
    test('a damaged newest backup falls back to the previous whole one, and says so', () async {
      final f = await _family();
      final MemoryBackupSink sink = MemoryBackupSink();
      await f.phone.svc.engine.backUp(kind: BackupKind.family, sinks: <BackupSink>[sink]);
      final Map<String, String> first = await f.phone.hashes();
      await f.phone.put('learn', <String, Object?>{'read': <Object?>['x', 'y', 'later']});
      await f.phone.svc.engine.backUp(kind: BackupKind.family, sinks: <BackupSink>[sink]);
      // Damage a chunk only the newest backup uses.
      final List<String> second = BackupHeader.parse(sink.manifests[sink.manifests.keys.last]!)!.chunks;
      final List<String> firstIds = BackupHeader.parse(sink.manifests[sink.manifests.keys.first]!)!.chunks;
      final String only = second.firstWhere((String c) => !firstIds.contains(c));
      final String key = sink.chunks.keys.firstWhere((String k) => k.endsWith(only));
      sink.chunks[key] = Uint8List.fromList(sink.chunks[key]!)..[20] ^= 0xff;
      final Rig fresh = await Rig.make(seed: 2);
      final RestoreEngine re = fresh.svc.restoreEngine();
      final RestoreOpen o = await re.open(source: sink, key: f.key, kind: BackupKind.family);
      expect(o.heads.single.usedOlder, isTrue);
      expect(o.skippedDamaged, greaterThan(0));
      await re.apply(o);
      expect(await fresh.hashes(), first);
    });

    test('a changed byte anywhere in a header, a chunk or a missing chunk is never accepted', () async {
      final f = await _family();
      final MemoryBackupSink sink = MemoryBackupSink();
      await f.phone.svc.engine.backUp(kind: BackupKind.family, sinks: <BackupSink>[sink]);
      final String mk = sink.manifests.keys.single;
      final Uint8List good = sink.manifests[mk]!;
      // header: flip bytes across its length; each one must make it not open (or open identically, never wrongly)
      for (int at = 0; at < good.length; at += 17) {
        sink.manifests[mk] = Uint8List.fromList(good)..[at] ^= 0x01;
        final Rig fresh = await Rig.make(seed: 2);
        try {
          final RestoreOpen o = await fresh.svc.restoreEngine().open(source: sink, key: f.key, kind: BackupKind.family);
          // If it opened, every area must still be exactly the original's.
          final RestoreOutcome out = await fresh.svc.restoreEngine().apply(o);
          expect(out.hashesAfter.values.toSet(), (await f.phone.hashes()).values.toSet(), reason: 'flip at $at');
        } on RestoreBlocked {
          // refused: the right answer
        }
      }
      sink.manifests[mk] = good;
      // a missing chunk
      final String ck = sink.chunks.keys.first;
      final Uint8List cv = sink.chunks.remove(ck)!;
      final Rig fresh = await Rig.make(seed: 2);
      await expectLater(fresh.svc.restoreEngine().open(source: sink, key: f.key, kind: BackupKind.family), throwsA(isA<RestoreBlocked>()));
      sink.chunks[ck] = cv;
    });

    test('the wrong sheet finds nothing, counts as a try, and five rest the phone for 15 minutes', () async {
      final f = await _family();
      final MemoryBackupSink sink = MemoryBackupSink();
      await f.phone.svc.engine.backUp(kind: BackupKind.family, sinks: <BackupSink>[sink]);
      final Rig fresh = await Rig.make(seed: 2);
      final RestoreEngine re = fresh.svc.restoreEngine();
      for (int i = 0; i < 5; i++) {
        await expectLater(re.open(source: sink, key: RecoveryKey.generate(random: Random(100 + i)), kind: BackupKind.family),
            throwsA(isA<RestoreBlocked>().having((RestoreBlocked b) => b.problem, 'problem', RestoreProblem.nothingFound)));
      }
      await expectLater(re.open(source: sink, key: f.key, kind: BackupKind.family),
          throwsA(isA<RestoreBlocked>().having((RestoreBlocked b) => b.problem, 'problem', RestoreProblem.resting)),
          reason: 'even the right sheet waits');
      fresh.clock.advance(const Duration(minutes: 16));
      expect((await re.open(source: sink, key: f.key, kind: BackupKind.family)).areaCount, 6);
      expect(await fresh.state.restLeftMs(fresh.clock.t.millisecondsSinceEpoch), 0);
    });

    test('a mistyped sheet is a typing mistake, not a guess: it never counts toward the rest', () async {
      final Rig p = await Rig.make();
      for (int i = 0; i < 8; i++) {
        expect(await p.svc.joinWithSheet('apple apple apple'), SheetOutcome.wrongCount);
      }
      expect(await p.state.restLeftMs(p.clock.t.millisecondsSinceEpoch), 0);
    });

    test('a backup from a phone the sheet never certified is refused, even though anyone with the public half could seal one', () async {
      final f = await _family();
      // The attacker knows the family's PUBLIC key (a phone of the family keeps it) but not the words.
      final Rig attacker = await Rig.make(seed: 9);
      await attacker.state.setPublicKey(BackupKind.family, (await f.phone.state.publicKey(BackupKind.family))!);
      final RecoveryKey theirs = RecoveryKey.generate(random: Random(77));
      final BackupAuthority theirAuth = await deriveBackupAuthority(theirs, BackupKind.family);
      await attacker.state.setWriterCert(BackupKind.family, attacker.writer.publicKey, await theirAuth.certifyWriter(attacker.writer.publicKey, BackupKind.family));
      await attacker.put('care', <String, Object?>{'n1': 'a forged care note'}, owner: 'ivy');
      final MemoryBackupSink sink = MemoryBackupSink();
      await attacker.svc.engine.backUp(kind: BackupKind.family, sinks: <BackupSink>[sink]);
      final Rig fresh = await Rig.make(seed: 2);
      await expectLater(fresh.svc.restoreEngine().open(source: sink, key: f.key, kind: BackupKind.family),
          throwsA(isA<RestoreBlocked>().having((RestoreBlocked b) => b.problem, 'problem', RestoreProblem.damaged)));
      expect(await fresh.hashes(), isEmpty);
    });

    test('a certified set that names a private or device-only area has that area refused and never written', () async {
      final f = await _family();
      final MemoryBackupSink sink = MemoryBackupSink();
      await _forge(f.phone, f.key, sink, <String, Map<String, Object?>>{
        'child.ivy.journal': <String, Object?>{'e': 'planted'},
        'device.devicekey': <String, Object?>{'seed': 'planted'},
        'guardian.mom.localpin': <String, Object?>{'x': 1},
        'child.ivy.care': <String, Object?>{'n': 'ok'},
      });
      final Rig fresh = await Rig.make(seed: 2);
      final RestoreEngine re = fresh.svc.restoreEngine();
      final RestoreOpen o = await re.open(source: sink, key: f.key, kind: BackupKind.family);
      expect(o.refusedAreas, containsAll(<String>['journal', 'devicekey', 'localpin']));
      await re.apply(o);
      expect((await fresh.services.store.namespaces()).where((String n) => n.contains('journal') || n.contains('devicekey')), isEmpty);
      expect(await fresh.services.area('care', ownerId: 'ivy').get('n'), 'ok');
    });

    test('a certified set that names an area that does not exist is not trusted at all', () async {
      final f = await _family();
      final MemoryBackupSink sink = MemoryBackupSink();
      await _forge(f.phone, f.key, sink, <String, Map<String, Object?>>{'child.ivy.madeup': <String, Object?>{'x': 1}});
      final Rig fresh = await Rig.make(seed: 2);
      await expectLater(fresh.svc.restoreEngine().open(source: sink, key: f.key, kind: BackupKind.family), throwsA(isA<RestoreBlocked>()));
    });

    test('a backup moved to another set name is not found by this family', () async {
      final f = await _family();
      final MemoryBackupSink sink = MemoryBackupSink();
      await f.phone.svc.engine.backUp(kind: BackupKind.family, sinks: <BackupSink>[sink]);
      final String other = 'f' * 32;
      final Map<String, Uint8List> moved = <String, Uint8List>{
        for (final MapEntry<String, Uint8List> e in sink.manifests.entries) '$other/${e.key.split('/').last}': e.value,
      };
      sink.manifests
        ..clear()
        ..addAll(moved);
      final Rig fresh = await Rig.make(seed: 2);
      await expectLater(fresh.svc.restoreEngine().open(source: sink, key: f.key, kind: BackupKind.family), throwsA(isA<RestoreBlocked>()));
    });
  });

  group('a restore that is stopped by anything leaves the phone exactly as it was', () {
    Future<({Rig target, MemoryBackupSink sink, RecoveryKey key, FlakyBackend be})> world() async {
      final f = await _family();
      final MemoryBackupSink sink = MemoryBackupSink();
      await f.phone.svc.engine.backUp(kind: BackupKind.family, sinks: <BackupSink>[sink]);
      final FlakyBackend be = FlakyBackend();
      final Rig target = await Rig.make(seed: 2, backend: be);
      await target.put('learn', <String, Object?>{'read': <Object?>['mine'], 'extra': 'mine'});
      await target.put('emergencycard', <String, Object?>{'card': <String, Object?>{'v': 9, 'who': 'Dad', 'list': <Object?>['c']}}, owner: 'ivy');
      await target.put('care', <String, Object?>{'n2': 'a different second note'}, owner: 'ivy');
      return (target: target, sink: sink, key: f.key, be: be);
    }

    Future<Map<String, Map<String, Object?>>> everything(Rig r) async => <String, Map<String, Object?>>{
          for (final String n in (await r.services.store.namespaces()).where((String n) => !n.startsWith('device.restoreundo.') && n != 'device.backupstate'))
            n: await r.services.store.open(NamespaceSpec(
                    name: n,
                    schema: localDataEntry(parseAreaName(n)!.area).schema,
                    encrypted: localDataEntry(parseAreaName(n)!.area).encrypted,
                    maxBytes: localDataEntry(parseAreaName(n)!.area).maxBytes))
                .snapshot(),
        };

    test('a kill at every write: the next start puts every area back, or every area is restored whole', () async {
      final w = await world();
      final RestoreEngine re = w.target.svc.restoreEngine();
      final RestoreOpen o = await re.open(source: w.sink, key: w.key, kind: BackupKind.family);
      final Map<String, Map<String, Object?>> before = await everything(w.target);
      int k = 1;
      for (; k < 60; k++) {
        w.be.arm(k);
        bool done = false;
        try {
          await re.apply(o);
          done = true;
        } on RestoreBlocked {
          // stopped, as meant
        }
        w.be.heal();
        // "the next start"
        final RecoveryReport rep = await w.target.svc.recoverOnStart();
        expect(rep.stuck, isFalse, reason: 'kill at write $k');
        final Map<String, Map<String, Object?>> after = await everything(w.target);
        if (done) {
          expect(await w.target.state.journal(), isNull);
          break;
        }
        // Either every area is as it was, or the restore had already committed and every area is restored whole:
        // never a mixture.
        final bool wholeAfter = (after['guardian.mom.learn']!['read'] as List).toSet().containsAll(<Object?>{'mine', 'x', 'y'}) &&
            after.containsKey('child.ivy.coordination') &&
            after.containsKey('guardian.mom.familyledger') &&
            (after['child.ivy.care'] as Map).containsKey('n1');
        expect(<bool>[after.toString() == before.toString(), wholeAfter].contains(true), isTrue,
            reason: 'a kill at write $k left a mixture');
        expect(await w.target.state.journal(), isNull, reason: 'journal cleared at write $k');
        expect((await w.target.services.store.namespaces()).where((String n) => n.startsWith('device.restoreundo.')), isEmpty);
      }
      expect(k, lessThan(60));
      // And a restore that completes is whole: every merged area read back with its hash.
      final Map<String, Map<String, Object?>> done = await everything(w.target);
      expect(done['guardian.mom.learn']!['extra'], 'mine');
      expect((done['guardian.mom.learn']!['read'] as List).toSet(), <Object?>{'mine', 'x', 'y'});
    });

    test('a kill that lands even on the undo itself is recovered on the next start, and a second recovery is harmless', () async {
      final w = await world();
      final RestoreEngine re = w.target.svc.restoreEngine();
      final RestoreOpen o = await re.open(source: w.sink, key: w.key, kind: BackupKind.family);
      final Map<String, Map<String, Object?>> before = await everything(w.target);
      // Let the writes of the restore start (copies and journal), then everything fails, undo included.
      w.be.arm(5);
      await expectLater(re.apply(o), throwsA(isA<RestoreBlocked>()));
      expect(await w.target.state.journal(), isNotNull, reason: 'the undo could not run: the journal waits for the next start');
      w.be.heal();
      expect((await w.target.svc.recoverOnStart()).rolledBack, isTrue);
      expect(await everything(w.target), before);
      final RecoveryReport again = await w.target.svc.recoverOnStart();
      expect(again.rolledBack, isFalse);
      expect(await everything(w.target), before);
    });

    test('a restore that finished its commit but was killed before the tidy is tidied, not undone', () async {
      final w = await world();
      final RestoreEngine re = w.target.svc.restoreEngine();
      final RestoreOpen o = await re.open(source: w.sink, key: w.key, kind: BackupKind.family);
      await re.apply(o);
      final Map<String, Map<String, Object?>> after = await everything(w.target);
      await w.target.state.putJournal(<String, Object?>{'id': 'x', 'state': 'applied', 'targets': <Object?>[]});
      await w.target.services.store.writeRaw('device.restoreundo.child.ivy.care', Uint8List.fromList(<int>[1, 2, 3]));
      final RecoveryReport rep = await w.target.svc.recoverOnStart();
      expect(rep.finished, isTrue);
      expect(await everything(w.target), after);
      expect((await w.target.services.store.namespaces()).where((String n) => n.startsWith('device.restoreundo.')), isEmpty);
    });

    test('a stop or a longer wait that arrives before the first write still wins', () async {
      final f = await _family();
      final MemoryBackupSink sink = MemoryBackupSink();
      await f.phone.svc.engine.backUp(kind: BackupKind.family, sinks: <BackupSink>[sink]);
      final Rig fresh = await Rig.make(seed: 2);
      final LocalWaitingClearance gate = LocalWaitingClearance(fresh.state, clock: fresh.clock.now);
      final RestoreEngine re = fresh.svc.restoreEngine(gate: gate);
      final RestoreOpen o = await re.open(source: sink, key: f.key, kind: BackupKind.family);
      await expectLater(re.apply(o), throwsA(isA<RestoreBlocked>().having((RestoreBlocked b) => b.problem, 'problem', RestoreProblem.notCleared)));
      await gate.begin(hasSecondGrownUp: true, hasHelper: false);
      await expectLater(re.apply(o), throwsA(isA<RestoreBlocked>()));
      expect(await gate.confirm(ConfirmedBy.grownUp), isTrue);
      fresh.clock.advance(const Duration(hours: 47));
      await expectLater(re.apply(o), throwsA(isA<RestoreBlocked>().having((RestoreBlocked b) => b.restLeftMs == null && b.clearance != null, 'has clearance', true)));
      expect(await gate.stop(ConfirmedBy.helper), isFalse, reason: 'a helper can only say yes');
      expect(await gate.stop(ConfirmedBy.grownUp), isTrue);
      fresh.clock.advance(const Duration(hours: 3));
      await expectLater(re.apply(o), throwsA(isA<RestoreBlocked>().having((RestoreBlocked b) => b.problem, 'problem', RestoreProblem.stopped)));
      expect(await fresh.hashes(), isEmpty, reason: 'nothing was written');
    });

    test('the wait is 48 hours with a yes and 72 alone; a helper\'s yes counts only if one was named; the clock going back never shortens it', () async {
      final Rig p = await Rig.make();
      final LocalWaitingClearance g = LocalWaitingClearance(p.state, clock: p.clock.now);
      await g.begin(hasSecondGrownUp: false, hasHelper: false);
      expect(await g.confirm(ConfirmedBy.helper), isFalse);
      expect(await g.confirm(ConfirmedBy.grownUp), isFalse);
      p.clock.advance(const Duration(hours: 71));
      expect((await g.check()).kind, ClearanceKind.waiting);
      p.clock.advance(const Duration(hours: 2));
      expect((await g.check()).cleared, isTrue);
      await g.consumed();
      await g.begin(hasSecondGrownUp: false, hasHelper: true);
      expect((await g.check()).kind, ClearanceKind.needsConfirmation);
      expect(await g.confirm(ConfirmedBy.helper), isTrue);
      p.clock.advance(const Duration(hours: 47));
      expect((await g.check()).kind, ClearanceKind.waiting);
      p.clock.t = p.clock.t.subtract(const Duration(days: 30));
      expect((await g.check()).cleared, isFalse, reason: 'a clock set back does not shorten the wait');
      // starting again never restarts or shortens a wait already running
      await g.begin(hasSecondGrownUp: true, hasHelper: false);
      final Map<String, Object?> rec = (await p.state.clearanceRecord())!;
      expect(rec['helper'], true);
    });
  });

  group('what a phone remembers, and what it never does', () {
    test('the words, the seed and the secret half are stored nowhere on the phone', () async {
      final Rig p = await Rig.make();
      final RecoveryKey key = await p.svc.setUp();
      final MemoryBackupSink sink = MemoryBackupSink();
      await p.put('learn', <String, Object?>{'read': <Object?>['x']});
      await p.svc.engine.backUp(kind: BackupKind.family, sinks: <BackupSink>[sink]);
      final String stateJson = jsonEncode(await p.services.area('backupstate').snapshot());
      expect(stateJson.contains('${key.words[0]} ${key.words[1]}'), isFalse);
      expect(stateJson.contains(base64Url.encode(key.seed).replaceAll('=', '')), isFalse);
      expect(stateJson.contains(hex(key.seed)), isFalse);
      expect(stateJson.contains('"seed"'), isFalse);
    });

    test('status says the most urgent thing first, and a sheet that was never checked is not "fine"', () async {
      final Rig p = await Rig.make();
      expect((await p.svc.status()).attention, BackupAttention.notSetUp);
      final RecoveryKey key = await p.svc.setUp();
      expect((await p.svc.status()).attention, BackupAttention.sheetNotChecked);
      expect(await p.svc.confirmSheet(key, 'wrong', 'words'), isFalse);
      expect((await p.svc.status()).attention, BackupAttention.sheetNotChecked);
      expect(await p.svc.confirmSheet(key, key.firstWord, key.lastWord), isTrue);
      expect((await p.svc.status()).attention, BackupAttention.overdue, reason: 'no backup has run');
      final MemoryBackupSink sink = MemoryBackupSink();
      await p.put('learn', <String, Object?>{'read': <Object?>['x']});
      await p.svc.engine.backUp(kind: BackupKind.family, sinks: <BackupSink>[sink]);
      expect((await p.svc.status()).attention, BackupAttention.fine);
      p.clock.advance(const Duration(hours: 40));
      expect((await p.svc.status()).attention, BackupAttention.overdue);
      sink.onOp = (String op) {
        if (op == 'putChunk') throw const BackupSinkException('unreachable');
      };
      await p.put('learn', <String, Object?>{'read': <Object?>['x', 'more']});
      await p.svc.engine.backUp(kind: BackupKind.family, sinks: <BackupSink>[sink]);
      expect((await p.svc.status()).attention, BackupAttention.lastTryFailed);
      sink.onOp = null;
      await p.svc.engine.backUp(kind: BackupKind.family, sinks: <BackupSink>[sink]);
      expect((await p.svc.status()).attention, BackupAttention.fine);
      p.clock.advance(const Duration(days: 200));
      await p.svc.engine.backUp(kind: BackupKind.family, sinks: <BackupSink>[sink]);
      expect((await p.svc.status()).attention, BackupAttention.sheetOld, reason: 'look at the paper again after about six months');
      await p.svc.sheetLookedAt();
      expect((await p.svc.status()).attention, BackupAttention.fine);
    });

    test('a backup is due when set up, a place is chosen and none ran in the last day', () async {
      final Rig p = await Rig.make();
      expect(await p.svc.due(), isFalse, reason: 'not set up');
      await p.svc.setUp();
      expect(await p.svc.due(), isFalse, reason: 'no place chosen');
      final Directory dir = await Directory.systemTemp.createTemp('olive_due_test');
      try {
        await p.svc.chooseFolder(dir.path);
        expect(await p.svc.due(), isTrue);
        await p.put('learn', <String, Object?>{'read': <Object?>['x']});
        await p.svc.backUpNow();
        expect(await p.svc.due(), isFalse);
        p.clock.advance(const Duration(hours: 25));
        expect(await p.svc.due(), isTrue);
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('with no place chosen there is a plain refusal and nothing is staged; with no sheet there is nothing to seal to', () async {
      final Rig p = await Rig.make();
      await expectLater(p.svc.backUpNow(), throwsStateError);
      await expectLater(p.svc.engine.backUp(kind: BackupKind.family, sinks: <BackupSink>[MemoryBackupSink()]), throwsA(isA<BackupNotSetUp>()));
    });

    test('a new sheet locks future backups only: the old backups still open with the old sheet', () async {
      final f = await _family();
      final MemoryBackupSink sink = MemoryBackupSink();
      await f.phone.svc.engine.backUp(kind: BackupKind.family, sinks: <BackupSink>[sink]);
      final RecoveryKey newer = await f.phone.svc.setUp();
      await f.phone.put('learn', <String, Object?>{'read': <Object?>['x', 'y', 'after']});
      await f.phone.svc.engine.backUp(kind: BackupKind.family, sinks: <BackupSink>[sink]);
      expect(sink.manifests.length, 2, reason: 'two sets, one per sheet');
      final Rig a = await Rig.make(seed: 2), b = await Rig.make(seed: 3);
      expect((await a.svc.restoreEngine().open(source: sink, key: f.key, kind: BackupKind.family)).areaCount, 6);
      expect((await b.svc.restoreEngine().open(source: sink, key: newer, kind: BackupKind.family)).areaCount, 6);
    });
  });

  group('merge, on its own', () {
    test('lists unite without losing or inventing anything, in this phone\'s order first', () {
      final MergeResult r = mergeDocuments(
          namespace: 'n',
          local: <String, Object?>{'l': <Object?>['a', 'b']},
          backup: <String, Object?>{'l': <Object?>['b', 'c']});
      expect(r.merged['l'], <Object?>['a', 'b', 'c']);
      expect(r.conflicts, isEmpty);
    });

    test('items with an id are matched by it, and the same field with two answers is a conflict that keeps both', () {
      final MergeResult r = mergeDocuments(
          namespace: 'n',
          local: <String, Object?>{'l': <Object?>[<String, Object?>{'id': 'a', 'v': 1}]},
          backup: <String, Object?>{'l': <Object?>[<String, Object?>{'id': 'a', 'v': 2}]});
      expect(((r.merged['l'] as List).single as Map)['v'], 1);
      expect(r.conflicts.single.setAside, 2);
      expect(r.conflicts.single.from, 'backup');
    });

    test('a key only one side has is kept, and neither input is changed', () {
      final Map<String, Object?> local = <String, Object?>{'a': 1};
      final Map<String, Object?> backup = <String, Object?>{'b': 2};
      final MergeResult r = mergeDocuments(namespace: 'n', local: local, backup: backup);
      expect(r.merged, <String, Object?>{'a': 1, 'b': 2});
      expect(local, <String, Object?>{'a': 1});
      expect(backup, <String, Object?>{'b': 2});
    });

    test('a different family record is never merged: this phone\'s stays and the other is set aside whole', () async {
      final MergeResult r = await mergeLedgerDocuments(
          namespace: 'guardian.mom.familyledger',
          local: <String, Object?>{'family': <String, Object?>{'e': <Object?>['founding-a']}},
          backup: <String, Object?>{'family': <String, Object?>{'e': <Object?>['founding-b']}},
          nowMs: 1);
      expect(r.merged['family'], <String, Object?>{'e': <Object?>['founding-a']});
      expect(r.conflicts.single.path, 'family');
    });
  });
}

/// Seals a backup the way a certified phone of the family would, but with whatever areas the test names, to prove a
/// restore trusts a set only for what this kind of backup may hold.
Future<void> _forge(Rig phone, RecoveryKey key, MemoryBackupSink sink, Map<String, Map<String, Object?>> areas) async {
  final Uint8List pk = (await phone.state.publicKey(BackupKind.family))!;
  final String setId = await backupSetId(pk, BackupKind.family);
  final Uint8List dk = newDataKey(random: Random(55));
  final Uint8List wrap = await wrapDataKey(recipientPublic: pk, dk: dk, setId: setId, kind: BackupKind.family, random: Random(56));
  final List<Map<String, Object?>> list = <Map<String, Object?>>[];
  final List<String> order = <String>[];
  for (final MapEntry<String, Map<String, Object?>> e in areas.entries) {
    final Uint8List plain = Uint8List.fromList(utf8.encode(canonicalJson(e.value)));
    final Uint8List sealed = await sealUnder(dk, plain, chunkAad(setId));
    final String id = await sha256HexOf(sealed);
    await sink.putChunk(setId, id, sealed);
    order.add(id);
    final List<String> parts = e.key.split('.');
    list.add(<String, Object?>{
      'ns': e.key,
      'scope': parts.first,
      'owner': parts.length == 3 ? parts[1] : '',
      'area': parts.last,
      'schema': 1,
      'hash': await sha256HexOf(plain),
      'bytes': plain.length,
      'chunks': <String>[id],
    });
  }
  const int seq = 1;
  final Uint8List mbox = await sealUnder(
      dk, utf8.encode(jsonEncode(<String, Object?>{'v': 1, 'kind': 'family', 'createdAtMs': 1, 'root': 'x', 'areas': list})), manifestAad(setId, seq));
  final Uint8List cert = (await phone.state.writerCert(BackupKind.family, phone.writer.publicKey))!;
  final Uint8List sig = await phone.writer.sign(headerSigMessage(
      kind: BackupKind.family, setId: setId, seq: seq, wrap: wrap, mbox: mbox, chunks: order, writer: phone.writer.publicKey, cert: cert));
  final BackupHeader h = BackupHeader(
      kind: BackupKind.family, setId: setId, seq: seq, wrap: wrap, mbox: mbox, chunks: order, writer: phone.writer.publicKey, cert: cert, sig: sig);
  await sink.putManifest(setId, h.name, h.toBytes());
}
