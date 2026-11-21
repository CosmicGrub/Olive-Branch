// OLIVE BRANCH — backup_targets.dart: a folder, one file, and the family's server all keep the same sealed bytes, refuse a
// half-sent set, and resume.
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/backup_classes.dart';
import 'package:olive_client/backup_format.dart';
import 'package:olive_client/backup_keys.dart';
import 'package:olive_client/backup_targets.dart';
import 'package:olive_client/device_keys.dart' show b64, unb64;
import 'package:olive_client/local_services.dart';

import 'support/backup_rig.dart';

/// A pretend server speaking the JSON wire, keeping sealed bytes in memory and checking the same things a real one must.
class FakeBackupWire implements BackupWire {
  final MemoryBackupTarget store = MemoryBackupTarget();
  int calls = 0;
  bool offline = false;
  final List<String> paths = <String>[];

  @override
  Future<Map<String, Object?>> call(String method, String path, {Map<String, Object?>? body}) async {
    calls++;
    paths.add('$method $path');
    if (offline) throw const BackupTargetException('offline', 'no connection');
    final List<String> p = path.split('/').where((String s) => s.isNotEmpty).toList(); // v1 backup <kind> sets [<set> [chunks <id>|commit]]
    final BackupKind kind = BackupKind.fromWord(p[2])!;
    if (p.length == 4 && method == 'GET') {
      final List<CommittedSet> sets = await store.committed(kind);
      return <String, Object?>{
        'sets': <Object?>[
          for (final CommittedSet s in sets) <String, Object?>{'header': b64(s.header), 'manifest': b64(s.manifest)}
        ]
      };
    }
    final String set = p[4];
    if (p.length == 5 && method == 'GET') return <String, Object?>{'chunks': (await store.chunkIds(kind, set)).toList()};
    if (p.length == 5 && method == 'DELETE') {
      await store.remove(kind, set);
      return <String, Object?>{};
    }
    if (p.length == 7 && p[5] == 'chunks' && method == 'PUT') {
      await store.putChunk(kind, set, p[6], unb64(body!['b64'] as String));
      return <String, Object?>{};
    }
    if (p.length == 7 && p[5] == 'chunks' && method == 'GET') {
      final Uint8List? b = await store.getChunk(kind, set, p[6]);
      if (b == null) throw const BackupWireNotFound();
      return <String, Object?>{'b64': b64(b)};
    }
    if (p.length == 6 && p[5] == 'commit' && method == 'PUT') {
      await store.commit(kind, set, unb64(body!['header'] as String), unb64(body['manifest'] as String));
      return <String, Object?>{};
    }
    throw StateError('unexpected $method $path');
  }
}

Future<MapEntry<SealedSet, Map<String, Uint8List>>> _seal(BackupKey key, {int big = 9000, int seq = 1}) async {
  final Phone p = Phone();
  final LocalServices s = p.open();
  await populate(s, BackupKind.hersKeep, bigPictures: big);
  final BackupSnapshot snap = await captureSnapshot(s.store, BackupKind.hersKeep);
  final Map<String, Uint8List> chunks = <String, Uint8List>{};
  final SealedSet sealed = await sealSnapshot(snap, key.pair.publicKey,
      onChunk: (String id, Uint8List b) async => chunks[id] = b, createdMs: 1700000000000 + seq * 60000, seq: seq);
  return MapEntry<SealedSet, Map<String, Uint8List>>(sealed, chunks);
}

class BackupKey {
  BackupKey(this.pair);
  final BackupKeyPair pair;
}

void main() {
  late BackupKey key;
  setUpAll(() async {
    key = BackupKey(await BackupKeyPair.fromSecret(newBackupSecret(Random(1)), BackupPurpose.keep));
  });

  Future<void> contract(BackupTarget t) async {
    final MapEntry<SealedSet, Map<String, Uint8List>> e = await _seal(key);
    final SealedSet s = e.key;
    expect(await t.committed(s.kind), isEmpty);
    expect(await t.chunkIds(s.kind, s.setId), isEmpty);
    // Commit is refused until every chunk is there: a half-sent set is invisible.
    final List<String> ids = s.chunkIds;
    expect(ids.length, greaterThan(1));
    await t.putChunk(s.kind, s.setId, ids.first, e.value[ids.first]!);
    await expectLater(t.commit(s.kind, s.setId, s.header, s.manifest),
        throwsA(isA<BackupTargetException>().having((BackupTargetException x) => x.code, 'code', 'missing')));
    expect(await t.committed(s.kind), isEmpty, reason: 'nothing counts before the commit');
    // Resume: a second run sees what is held and sends only the rest.
    final Set<String> have = await t.chunkIds(s.kind, s.setId);
    expect(have, <String>{ids.first});
    for (final String id in ids.where((String x) => !have.contains(x))) {
      await t.putChunk(s.kind, s.setId, id, e.value[id]!);
    }
    await t.putChunk(s.kind, s.setId, ids.first, e.value[ids.first]!); // idempotent
    await t.commit(s.kind, s.setId, s.header, s.manifest);
    final List<CommittedSet> got = await t.committed(s.kind);
    expect(got.single.setId, s.setId);
    expect(got.single.header, s.header);
    expect(got.single.manifest, s.manifest);
    expect(await t.committed(BackupKind.family), isEmpty, reason: 'kinds are kept apart');
    for (final String id in ids) {
      expect(await t.getChunk(s.kind, s.setId, id), e.value[id]);
    }
    expect(await t.getChunk(s.kind, s.setId, 'f' * 64), isNull);
    // Bad names never reach storage.
    await expectLater(t.putChunk(s.kind, '../x', ids.first, Uint8List(1)), throwsA(isA<BackupTargetException>()));
    await expectLater(t.putChunk(s.kind, s.setId, '../../escape', Uint8List(1)), throwsA(isA<BackupTargetException>()));
    // A header for another set cannot be committed under this id.
    await expectLater(t.commit(s.kind, 'a' * 32, s.header, s.manifest), throwsA(isA<BackupTargetException>()));
    await t.remove(s.kind, s.setId);
    expect(await t.committed(s.kind), isEmpty);
    expect(await t.chunkIds(s.kind, s.setId), isEmpty);
  }

  test('memory target keeps the contract', () => contract(MemoryBackupTarget()));

  test('folder target keeps the contract, with real files and no leftover temporary files', () async {
    final Directory d = await Directory.systemTemp.createTemp('olive_backup_target_');
    addTearDown(() => d.delete(recursive: true));
    await contract(DirectoryBackupTarget(d));
    expect(await d.list(recursive: true).where((FileSystemEntity e) => e.path.endsWith('.tmp')).isEmpty, isTrue);
  });

  test('server target keeps the contract over the JSON wire', () async {
    final FakeBackupWire w = FakeBackupWire();
    await contract(ServerBackupTarget(w));
    expect(w.paths.every((String x) => x.contains('/v1/backup/')), isTrue);
    // The wire never sees plaintext: it carries sealed bytes only.
    expect(w.paths.any((String x) => x.contains('mia') || x.contains('care')), isFalse);
  });

  test('an offline server is reported as offline, never as success, and nothing is committed', () async {
    final FakeBackupWire w = FakeBackupWire()..offline = true;
    final ServerBackupTarget t = ServerBackupTarget(w);
    await expectLater(t.committed(BackupKind.family),
        throwsA(isA<BackupTargetException>().having((BackupTargetException x) => x.code, 'code', 'offline')));
  });

  test('the newest set is listed first, and a damaged commit file is skipped, not fatal', () async {
    final Directory d = await Directory.systemTemp.createTemp('olive_backup_target_');
    addTearDown(() => d.delete(recursive: true));
    final DirectoryBackupTarget t = DirectoryBackupTarget(d);
    final List<SealedSet> made = <SealedSet>[];
    for (final int seq in <int>[1, 2, 3]) {
      final MapEntry<SealedSet, Map<String, Uint8List>> e = await _seal(key, big: 10, seq: seq);
      for (final MapEntry<String, Uint8List> c in e.value.entries) {
        await t.putChunk(e.key.kind, e.key.setId, c.key, c.value);
      }
      await t.commit(e.key.kind, e.key.setId, e.key.header, e.key.manifest);
      made.add(e.key);
    }
    expect((await t.committed(BackupKind.hersKeep)).map((CommittedSet c) => c.setId).toList(),
        <String>[made[2].setId, made[1].setId, made[0].setId]);
    await File('${d.path}${Platform.pathSeparator}hers-keep${Platform.pathSeparator}${made[2].setId}${Platform.pathSeparator}commit.bin')
        .writeAsBytes(<int>[0, 0, 0, 9, 1]);
    expect((await t.committed(BackupKind.hersKeep)).map((CommittedSet c) => c.setId).toList(),
        <String>[made[1].setId, made[0].setId]);
  });

  group('the one-file bundle', () {
    test('a set packs to one file and unpacks into another place, byte for byte', () async {
      final MemoryBackupTarget a = MemoryBackupTarget();
      final MapEntry<SealedSet, Map<String, Uint8List>> e = await _seal(key);
      for (final MapEntry<String, Uint8List> c in e.value.entries) {
        await a.putChunk(e.key.kind, e.key.setId, c.key, c.value);
      }
      await a.commit(e.key.kind, e.key.setId, e.key.header, e.key.manifest);
      final Uint8List file = await BackupBundle.pack(a, e.key.kind, e.key.setId);
      final MemoryBackupTarget b = MemoryBackupTarget();
      final CommittedSet got = await BackupBundle.unpackInto(b, file);
      expect(got.setId, e.key.setId);
      expect((await b.committed(e.key.kind)).single.manifest, e.key.manifest);
      for (final MapEntry<String, Uint8List> c in e.value.entries) {
        expect(await b.getChunk(e.key.kind, e.key.setId, c.key), c.value);
      }
      expect(utf8.decode(file.sublist(0, 8)), 'OLIVEBK1');
    });

    test('a damaged, cut, altered or foreign file is refused whole and stores nothing', () async {
      final MemoryBackupTarget a = MemoryBackupTarget();
      final MapEntry<SealedSet, Map<String, Uint8List>> e = await _seal(key);
      for (final MapEntry<String, Uint8List> c in e.value.entries) {
        await a.putChunk(e.key.kind, e.key.setId, c.key, c.value);
      }
      await a.commit(e.key.kind, e.key.setId, e.key.header, e.key.manifest);
      final Uint8List file = await BackupBundle.pack(a, e.key.kind, e.key.setId);
      final List<Uint8List> bad = <Uint8List>[
        Uint8List.fromList(file)..[file.length - 50] ^= 1, // inside a chunk
        Uint8List.sublistView(file, 0, file.length - 5), // cut short
        Uint8List.fromList(<int>[...file, 0]), // extra byte
        Uint8List.fromList(utf8.encode('PK\x03\x04 not ours at all')),
        Uint8List(0),
        Uint8List.fromList(file)..[0] = 0x58, // wrong magic
      ];
      for (final Uint8List f in bad) {
        final MemoryBackupTarget t = MemoryBackupTarget();
        await expectLater(BackupBundle.unpackInto(t, f), throwsA(isA<BackupTargetException>()));
        expect(await t.committed(e.key.kind), isEmpty);
        expect(await t.chunkIds(e.key.kind, e.key.setId), isEmpty, reason: 'nothing stored for a bad file');
      }
    });

    test('a set that is not in the source cannot be packed', () async {
      await expectLater(BackupBundle.pack(MemoryBackupTarget(), BackupKind.family, 'a' * 32), throwsA(isA<BackupTargetException>()));
    });
  });
}
