// OLIVE BRANCH — data-loss harness, part 1: kill the app at every step. Not a test file.
//
// A "crash" here is a [SimulatedCrash] thrown from the storage layer at the Nth step of a run, and then EVERYTHING in
// memory is thrown away (new LocalStore, new engine, new queue) over the same disk, which is exactly what a killed app
// followed by a restart looks like. After the throw the clock stays dead: any zombie future that tries another storage
// step throws too, so nothing can write after the "kill".
//
// Two disks are swept the same way:
//  - [MemDisk]: the store's own [StoreBackend] calls are the steps (before and after every read, write, delete,
//    quarantine). Fast, and every step of every caller is covered.
//  - [DirDisk]: real files under a temporary directory, with [DirectoryStoreBackend.onStep] naming the steps INSIDE a
//    write (temp file opened, written, flushed, renamed). A torn temp file (the tail never reached the disk) is one of the
//    variants. This is the real write path, not a model of it.
//
// What a sweep proves is written in the tests; the vocabulary is the same everywhere: an ACKNOWLEDGED write is one whose
// future completed (the screen was told it is saved); an IN-FLIGHT write is the one a crash interrupted, which may be
// wholly there or wholly absent and never half.
import 'dart:io';
import 'dart:typed_data';

import 'package:olive_client/local_store.dart';

/// The process died here.
class SimulatedCrash extends Error {
  SimulatedCrash(this.step, this.where);
  final int step;
  final String where;
  @override
  String toString() => 'SimulatedCrash(step $step at $where)';
}

/// Counts every storage step of a run and kills the run at [crashAt] (1-based). Dead stays dead.
class CrashClock {
  CrashClock([this.crashAt]);
  int? crashAt;
  int steps = 0;
  bool dead = false;

  /// Called by a disk before and after each storage step.
  void tick(String where) {
    if (dead) throw SimulatedCrash(steps, 'zombie:$where');
    steps++;
    if (crashAt == steps) {
      dead = true;
      throw SimulatedCrash(steps, where);
    }
  }

  /// True when the NEXT tick is the one that will kill the run.
  bool get nextIsCrash => !dead && crashAt == steps + 1;
}

/// A disk that survives "restarts": [open] makes a backend bound to one run's clock over the same storage.
abstract class Disk {
  StoreBackend open(CrashClock clock);

  /// Every quarantined blob, as bytes (what a damaged or conflicting document was kept as).
  Future<List<Uint8List>> quarantinedBlobs();

  /// How many leftover temp files a killed write left behind.
  Future<int> strayTemps();
  Future<void> dispose();
}

class _TickingBackend implements StoreBackend {
  _TickingBackend(this._inner, this._clock, this._disk);
  final MemoryStoreBackend _inner;
  final CrashClock _clock;
  final MemDisk _disk;

  @override
  Future<Uint8List?> read(String name) async {
    _clock.tick('before:read');
    final Uint8List? r = await _inner.read(name);
    _clock.tick('after:read');
    return r;
  }

  @override
  Future<void> writeAtomic(String name, Uint8List bytes) async {
    _clock.tick('before:write');
    await _inner.writeAtomic(name, bytes);
    _clock.tick('after:write');
  }

  @override
  Future<void> delete(String name) async {
    _clock.tick('before:delete');
    await _inner.delete(name);
    _clock.tick('after:delete');
  }

  @override
  Future<List<String>> names() async {
    _clock.tick('before:names');
    final List<String> r = await _inner.names();
    _clock.tick('after:names');
    return r;
  }

  @override
  Future<void> quarantine(String name, Uint8List bytes, String reason) async {
    _clock.tick('before:quarantine');
    await _inner.quarantine(name, bytes, reason);
    _disk._blobs.add(Uint8List.fromList(bytes));
    _clock.tick('after:quarantine');
  }

  @override
  Future<int> quarantineCount() async => _inner.quarantineCount();

  @override
  Future<void> deleteEverything() async {
    _clock.tick('before:wipe');
    await _inner.deleteEverything();
    _disk._blobs.clear();
    _clock.tick('after:wipe');
  }
}

class MemDisk implements Disk {
  final MemoryStoreBackend inner = MemoryStoreBackend();
  final List<Uint8List> _blobs = <Uint8List>[];

  @override
  StoreBackend open(CrashClock clock) => _TickingBackend(inner, clock, this);
  @override
  Future<List<Uint8List>> quarantinedBlobs() async => List<Uint8List>.of(_blobs);
  @override
  Future<int> strayTemps() async => 0;
  @override
  Future<void> dispose() async {}
}

class DirDisk implements Disk {
  DirDisk._(this.root, this.tear);
  final Directory root;

  /// When true, the run that is killed at a 'tmp_written' step leaves a temp file with its tail missing.
  final bool tear;

  static Future<DirDisk> make({bool tear = false}) async =>
      DirDisk._(await Directory.systemTemp.createTemp('olive_dataloss_'), tear);

  @override
  StoreBackend open(CrashClock clock) => DirectoryStoreBackend(root, onStep: (String step) {
        if (tear && step == 'tmp_written' && clock.nextIsCrash) {
          for (final FileSystemEntity e in root.listSync()) {
            if (e is File && e.path.endsWith('.tmp')) {
              final Uint8List b = e.readAsBytesSync();
              e.writeAsBytesSync(b.sublist(0, b.length ~/ 2));
            }
          }
        }
        clock.tick(step);
      });

  @override
  Future<List<Uint8List>> quarantinedBlobs() async {
    final Directory q = Directory('${root.path}${Platform.pathSeparator}quarantine');
    if (!q.existsSync()) return <Uint8List>[];
    return <Uint8List>[for (final FileSystemEntity e in q.listSync()) if (e is File) e.readAsBytesSync()];
  }

  @override
  Future<int> strayTemps() async => root.listSync().where((FileSystemEntity e) => e.path.endsWith('.tmp')).length;

  @override
  Future<void> dispose() async {
    if (root.existsSync()) await root.delete(recursive: true);
  }
}

/// What the run has been TOLD is saved, so a check after a crash knows what must still be there.
class Oracle {
  /// Namespace to key to acknowledged value (absent key = acknowledged deleted or never written).
  final Map<String, Map<String, Object?>> acked = <String, Map<String, Object?>>{};

  /// The one write a crash may have interrupted: namespace, key, and the value it would have stored (null = delete).
  ({String ns, String key, Object? value})? inflight;

  void ack(String ns, String key, Object? value) {
    final Map<String, Object?> m = acked.putIfAbsent(ns, () => <String, Object?>{});
    if (value == null) {
      m.remove(key);
    } else {
      m[key] = value;
    }
    inflight = null;
  }
}

typedef Run<E> = Future<void> Function(E env, Oracle oracle);
typedef Verify<E> = Future<void> Function(E restarted, Oracle oracle, CrashClock crashed);

/// Runs [run] once to count its steps, then once per step, killing it there, rebuilding the world with [build] over the
/// same disk (a restart) and handing it to [verify]. Returns the number of kill points swept (so a test can assert the
/// sweep was not vacuous). A run that throws anything but the planned crash fails the test.
Future<int> sweepCrashPoints<E>({
  required Future<Disk> Function() makeDisk,
  required E Function(Disk disk, CrashClock clock) build,
  required Run<E> run,
  required Verify<E> verify,
  Future<void> Function(Disk disk)? beforeEachRun,
}) async {
  // Dry run: no crash, count the steps; the result must itself verify.
  final Disk dry = await makeDisk();
  int total;
  try {
    final CrashClock clock = CrashClock();
    final Oracle o = Oracle();
    if (beforeEachRun != null) await beforeEachRun(dry);
    clock.steps = 0;
    await run(build(dry, clock), o);
    total = clock.steps;
    await verify(build(dry, CrashClock()), o, clock);
  } finally {
    await dry.dispose();
  }
  if (total < 2) throw StateError('a sweep over $total steps proves nothing');
  for (int k = 1; k <= total; k++) {
    final Disk disk = await makeDisk();
    try {
      final CrashClock clock = CrashClock(k);
      final Oracle o = Oracle();
      if (beforeEachRun != null) await beforeEachRun(disk);
      clock.steps = 0;
      bool crashed = false;
      try {
        await run(build(disk, clock), o);
      } on SimulatedCrash {
        crashed = true;
      }
      if (!crashed && k < total) throw StateError('step $k of $total did not crash: the run is not deterministic');
      await verify(build(disk, CrashClock()), o, clock);
    } finally {
      await disk.dispose();
    }
  }
  return total;
}
