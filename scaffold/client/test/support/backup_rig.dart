// Shared scaffolding for the backup and restore tests: a "phone" whose bytes outlive the app (so a kill and a fresh
// start can be staged), data that fills every area a backup kind holds, and targets that stand for a kill.
import 'dart:math';
import 'dart:typed_data';

import 'package:olive_client/backup_classes.dart';
import 'package:olive_client/backup_targets.dart';
import 'package:olive_client/local_services.dart';
import 'package:olive_client/local_store.dart';
import 'package:olive_client/store_cipher.dart';

/// Stands for the app being killed. An Error, not an Exception, so no `catch (Exception)` cleanup runs.
class SimulatedKill extends Error {
  SimulatedKill(this.where);
  final String where;
  @override
  String toString() => 'SimulatedKill($where)';
}

/// A device's storage: the bytes and the store key survive an "app restart"; [open] is a fresh app run.
class Phone {
  Phone({this.childId = 'mia', this.guardianId = 'gid-one', MemoryStoreBackend? backend, List<int>? key})
      : backend = backend ?? MemoryStoreBackend(),
        key = key ?? AesGcmStoreCipher.newKey();
  final String childId;
  final String guardianId;
  final MemoryStoreBackend backend;
  final List<int> key;

  LocalServices open() => LocalServices(
        store: LocalStore(backend: backend, cipher: AesGcmStoreCipher(key)),
        childId: childId,
        guardianId: guardianId,
        isLive: false,
        demoSeeds: false,
      );
}

/// Realistic, deterministic content for every area of [kind], so every area has something to lose.
Future<void> populate(LocalServices s, BackupKind kind, {int seed = 1, int bigPictures = 0}) async {
  final Random r = Random(seed);
  for (final String area in areasOfBackup(kind)) {
    final LocalNamespace ns = s.area(area);
    for (int i = 0; i < 3; i++) {
      await ns.put('k$i', <String, Object?>{
        'text': 'note ${r.nextInt(100000)} for $area',
        'n': r.nextInt(1000),
        'list': <Object?>[for (int j = 0; j < 4; j++) 'item-${r.nextInt(50)}'],
        'nested': <String, Object?>{'a': r.nextBool(), 'b': 'é ü 日本 ${r.nextInt(9)}'},
      });
    }
  }
  if (bigPictures > 0 && areaInBackup('pictures', kind)) {
    // A few hundred KB of strokes: enough to need more than one 128 KiB chunk.
    await s.area('pictures').put('big', <String, Object?>{
      'strokes': <Object?>[for (int i = 0; i < bigPictures; i++) <Object?>[r.nextDouble(), r.nextDouble(), r.nextInt(7), 'p$i']],
    });
  }
}

/// A target that counts chunk sends and stands for a kill at a chosen one.
class KillingTarget implements BackupTarget {
  KillingTarget(this.inner, {this.killOnPut, this.killOnCommit = false});
  final BackupTarget inner;
  int? killOnPut;
  bool killOnCommit;
  int puts = 0;

  @override
  String get kindWord => inner.kindWord;
  @override
  Future<Set<String>> chunkIds(BackupKind k, String s) => inner.chunkIds(k, s);
  @override
  Future<void> putChunk(BackupKind k, String s, String c, Uint8List b) async {
    puts++;
    if (killOnPut != null && puts == killOnPut) throw SimulatedKill('put $puts');
    await inner.putChunk(k, s, c, b);
  }

  @override
  Future<Uint8List?> getChunk(BackupKind k, String s, String c) => inner.getChunk(k, s, c);
  @override
  Future<void> commit(BackupKind k, String s, Uint8List h, Uint8List m) async {
    if (killOnCommit) throw SimulatedKill('commit');
    await inner.commit(k, s, h, m);
  }

  @override
  Future<List<CommittedSet>> committed(BackupKind k) => inner.committed(k);
  @override
  Future<void> remove(BackupKind k, String s) => inner.remove(k, s);
}

/// A destination whose target is [KillingTarget]-wrappable and whose spool is separate and in memory.
BackupDestinationParts memoryParts() => BackupDestinationParts(MemoryBackupTarget(), MemoryBackupTarget());

class BackupDestinationParts {
  BackupDestinationParts(this.target, this.spool);
  final MemoryBackupTarget target;
  final MemoryBackupTarget spool;
}

/// A store backend that changes what it saves for one namespace, to stand for a disk that does not keep what it was given.
class RottingBackend extends MemoryStoreBackend {
  RottingBackend(this.rotName);
  final String rotName;
  bool rot = false;

  @override
  Future<void> writeAtomic(String name, Uint8List bytes) {
    if (rot && name == rotName) {
      final Uint8List bad = Uint8List.fromList(bytes);
      bad[bad.length ~/ 2] ^= 0x01;
      return super.writeAtomic(name, bad);
    }
    return super.writeAtomic(name, bytes);
  }
}

/// A store backend that refuses writes to one namespace (a full disk).
class FailingBackend extends MemoryStoreBackend {
  FailingBackend(this.failName);
  final String failName;
  bool fail = false;

  @override
  Future<void> writeAtomic(String name, Uint8List bytes) {
    if (fail && name == failName) throw const LocalStoreFull('x', 1);
    return super.writeAtomic(name, bytes);
  }
}
