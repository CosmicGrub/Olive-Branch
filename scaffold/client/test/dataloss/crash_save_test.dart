// OLIVE BRANCH — data-loss harness, crash injection over the local store: the phone is killed at EVERY step of a save,
// a delete, an outbox write and a delivery, on an in-memory disk (every storage call is a step) and on real files (every
// step inside a write: temp opened, written, flushed, renamed; also with the temp file torn). After each kill the app
// restarts over the same disk and the checks say: nothing the screen was told is saved is gone, the write the kill
// interrupted is wholly there or wholly absent (never half), and nothing was left that has to be quarantined.
@Tags(<String>['dataloss'])
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/local_repositories.dart';
import 'package:olive_client/local_store.dart';
import 'package:olive_client/offline_outbox.dart';
import 'package:olive_client/store_cipher.dart';

import 'crash_harness.dart';

final Uint8List _key = Uint8List.fromList(List<int>.generate(32, (int i) => 90 + i));

class Env {
  Env(this.disk, this.clock) : store = LocalStore(backend: disk.open(clock), cipher: AesGcmStoreCipher(_key));
  final Disk disk;
  final CrashClock clock;
  final LocalStore store;
}

Env build(Disk d, CrashClock c) => Env(d, c);

const NamespaceSpec kPlain = NamespaceSpec(name: 'child.kid.lists');
const NamespaceSpec kSealed = NamespaceSpec(name: 'child.kid.memorybox', encrypted: true);
const NamespaceSpec kDevice = NamespaceSpec(name: 'device.role');
const List<NamespaceSpec> kAll = <NamespaceSpec>[kPlain, kSealed, kDevice];

/// A value with two halves that must always travel together: if a reader ever sees them differ, a write was half-seen.
Map<String, Object?> pair(String token, {int pad = 0}) =>
    <String, Object?>{'a': 'A-$token', 'b': 'B-$token', 'pad': 'x' * pad, 'n': <Object?>[1, 2, token]};

/// Every acknowledged write is there; the interrupted one is wholly old or wholly new; no stray keys; nothing quarantined.
Future<void> verifyAgainstOracle(Env e, Oracle o, {List<NamespaceSpec> specs = kAll}) async {
  for (final NamespaceSpec spec in specs) {
    final LocalNamespace ns = e.store.open(spec);
    final Map<String, Object?> have = await ns.readAll();
    expect(ns.recovery, RecoveryKind.none, reason: '${spec.name}: a kill must never leave a document that has to be quarantined');
    final Map<String, Object?> acked = o.acked[spec.name] ?? <String, Object?>{};
    final ({String ns, String key, Object? value})? inf = o.inflight;
    final bool hasInflight = inf != null && inf.ns == spec.name;
    for (final MapEntry<String, Object?> a in acked.entries) {
      final Object? got = have[a.key];
      if (hasInflight && inf.key == a.key) {
        expect(<Object?>[a.value, inf.value].map(jsonEncode), contains(jsonEncode(got)),
            reason: '${spec.name}/${a.key}: neither the old nor the new value (a half-seen write)');
      } else {
        expect(jsonEncode(got), jsonEncode(a.value), reason: '${spec.name}/${a.key}: an acknowledged write was lost or altered');
      }
    }
    for (final String k in have.keys) {
      if (acked.containsKey(k)) continue;
      expect(hasInflight && inf.key == k && jsonEncode(have[k]) == jsonEncode(inf.value), isTrue,
          reason: '${spec.name}/$k appeared that nobody wrote, or half of a write is visible');
    }
  }
  expect(await e.disk.quarantinedBlobs(), isEmpty, reason: 'a kill produced a damaged document');
  expect(await e.store.quarantined(), 0);
}

/// After a restart the interrupted write is whatever it turned out to be: if the new value landed, it is now just data
/// the phone holds (so a later check must expect it); if not, the old value stands. Never anything in between.
Future<void> adoptObservedInflight(Env e, Oracle o) async {
  final ({String ns, String key, Object? value})? inf = o.inflight;
  if (inf == null) return;
  final NamespaceSpec spec = kAll.firstWhere((NamespaceSpec s) => s.name == inf.ns);
  final Object? got = await e.store.open(spec).get(inf.key);
  if (jsonEncode(got) == jsonEncode(inf.value)) {
    o.ack(inf.ns, inf.key, inf.value);
  } else {
    o.inflight = null;
  }
}

Future<void> put(Env e, Oracle o, NamespaceSpec spec, String key, Object? value) async {
  o.inflight = (ns: spec.name, key: key, value: value);
  await e.store.open(spec).put(key, value);
  o.ack(spec.name, key, value);
}

Future<void> del(Env e, Oracle o, NamespaceSpec spec, String key) async {
  o.inflight = (ns: spec.name, key: key, value: null);
  await e.store.open(spec).delete(key);
  o.ack(spec.name, key, null);
}

/// The save workload: first writes, overwrites, a delete, a large value, three namespaces, one of them sealed.
Future<void> saveWorkload(Env e, Oracle o) async {
  await put(e, o, kPlain, 'want:1', pair('one'));
  await put(e, o, kSealed, 'photo:1', pair('memory-one', pad: 3000));
  await put(e, o, kPlain, 'want:2', pair('two'));
  await put(e, o, kPlain, 'want:1', pair('one-edited'));
  await put(e, o, kDevice, 'role', 'mom');
  await put(e, o, kSealed, 'photo:2', pair('memory-two', pad: 9000));
  await del(e, o, kPlain, 'want:2');
  await put(e, o, kSealed, 'photo:1', pair('memory-one-edited'));
}

void main() {
  group('a save, a rewrite and a delete, killed at every step', () {
    test('on the in-memory disk (every storage call is a kill point)', () async {
      final int n = await sweepCrashPoints<Env>(
        makeDisk: () async => MemDisk(),
        build: build,
        run: saveWorkload,
        verify: (Env e, Oracle o, CrashClock c) => verifyAgainstOracle(e, o),
      );
      expect(n, greaterThan(15), reason: 'the sweep must be wide');
    });

    for (final bool tear in <bool>[false, true]) {
      test('on real files, every step inside a write${tear ? ', with the temp file torn' : ''}', () async {
        final int n = await sweepCrashPoints<Env>(
          makeDisk: () => DirDisk.make(tear: tear),
          build: build,
          run: saveWorkload,
          verify: (Env e, Oracle o, CrashClock c) async {
            await verifyAgainstOracle(e, o);
            await adoptObservedInflight(e, o);
            // Whatever the kill left behind never blocks the next save.
            await put(e, o, kPlain, 'after:restart', pair('after'));
            await verifyAgainstOracle(e, o);
          },
        );
        expect(n, greaterThan(20), reason: 'the sweep must be wide');
      });
    }

    test('a leftover temp file is never read as data and is replaced by the next save', () async {
      final DirDisk disk = await DirDisk.make();
      try {
        // Kill the very first write after the temp file is fully written but before the rename.
        final CrashClock c = CrashClock(3);
        final Env e = Env(disk, c);
        await expectLater(e.store.open(kPlain).put('k', pair('lost-with-the-kill')), throwsA(isA<SimulatedCrash>()));
        expect(await disk.strayTemps(), 1, reason: 'the kill left its temp file');
        final Env again = Env(disk, CrashClock());
        expect(await again.store.open(kPlain).readAll(), isEmpty);
        expect(again.store.open(kPlain).recovery, RecoveryKind.none);
        await again.store.open(kPlain).put('k', pair('kept'));
        expect(await disk.strayTemps(), 0, reason: 'the next save reuses and renames the temp file');
        expect(await Env(disk, CrashClock()).store.open(kPlain).get('k'), pair('kept'));
      } finally {
        await disk.dispose();
      }
    });
  });

  group('the offline outbox: what she made is never lost, and is delivered', () {
    const NamespaceSpec spec = NamespaceSpec(name: 'child.kid.outbox', maxBytes: 2 * 1024 * 1024);
    OutboxItem item(int i, OutboxKind k) => OutboxItem(
        id: 'it$i', kind: k, createdAt: DateTime.utc(2026, 11, 20, 8, i), payload: <String, Object?>{'doodle': 'strokes-$i', 'i': i});

    // The queue loop as a caller drives it: load, change, save (acknowledged when save completes); deliver oldest first
    // to a "server" that remembers what it received (it may receive twice); drop from the outbox only after delivery.
    Future<void> work(Env e, Oracle o, Set<String> enqueuedAcked, List<String> received) async {
      final OutboxRepository repo = OutboxRepository(e.store.open(spec));
      for (int i = 1; i <= 4; i++) {
        final List<OutboxItem> cur = await repo.load();
        final OutboxItem it = item(i, i.isEven ? OutboxKind.message : OutboxKind.drawing);
        await repo.save(enqueue(cur, it).outbox);
        enqueuedAcked.add(it.id);
      }
      while (true) {
        final List<OutboxItem> cur = await repo.load();
        final OutboxItem? next = nextToSend(cur);
        if (next == null) break;
        received.add(next.id); // the network delivered it...
        await repo.save(sent(cur, next.id)); // ...and only then is it dropped from the outbox
      }
    }

    test('kill at every step: every acknowledged item is still waiting or was delivered, the list is whole, and delivery finishes', () async {
      final Set<String> allDelivered = <String>{};
      for (final bool real in <bool>[false, true]) {
        final Set<String> acked = <String>{};
        final List<String> received = <String>[];
        final int n = await sweepCrashPoints<Env>(
          makeDisk: () => real ? DirDisk.make(tear: true) : Future<Disk>.value(MemDisk()),
          build: build,
          run: (Env e, Oracle o) async {
            acked.clear();
            received.clear();
            await work(e, o, acked, received);
          },
          verify: (Env e, Oracle o, CrashClock crashed) async {
            final OutboxRepository repo = OutboxRepository(e.store.open(spec));
            final List<OutboxItem> waiting = await repo.load();
            expect(e.store.open(spec).recovery, RecoveryKind.none);
            final Set<String> waitingIds = <String>{for (final OutboxItem i in waiting) i.id};
            for (final String id in acked) {
              expect(waitingIds.contains(id) || received.contains(id), isTrue,
                  reason: '$id was acknowledged as saved, but it is neither waiting nor delivered');
            }
            // Never half a list: every row that is there has its whole payload.
            for (final OutboxItem i in waiting) {
              expect((i.payload! as Map<String, Object?>)['doodle'], startsWith('strokes-'));
            }
            // The app restarts and carries on: whatever was waiting is delivered, nothing twice-dropped.
            final List<String> more = <String>[];
            while (true) {
              final List<OutboxItem> cur = await repo.load();
              final OutboxItem? next = nextToSend(cur);
              if (next == null) break;
              more.add(next.id);
              await repo.save(sent(cur, next.id));
            }
            final Set<String> everything = <String>{...received, ...more};
            for (final String id in acked) {
              expect(everything.contains(id), isTrue, reason: '$id was never delivered after the restart');
            }
            allDelivered.addAll(everything);
          },
        );
        expect(n, greaterThan(10), reason: 'the sweep must be wide');
      }
      expect(allDelivered, <String>{'it1', 'it2', 'it3', 'it4'});
    });

    test('an item whose payload is not plain JSON is reported as not saved, never silently treated as saved', () async {
      // KNOWN LIMIT, recorded here so it cannot be forgotten: raw recorded bytes are deliberately not written to the
      // store (local_repositories.dart). The caller is told how many were skipped; a restart loses them.
      final Env e = Env(MemDisk(), CrashClock());
      final OutboxRepository repo = OutboxRepository(e.store.open(spec));
      final int skipped = await repo.save(<OutboxItem>[
        item(1, OutboxKind.drawing),
        OutboxItem(id: 'voice1', kind: OutboxKind.voice, createdAt: DateTime.utc(2026, 11, 20), payload: Uint8List.fromList(<int>[1, 2, 3])),
      ]);
      expect(skipped, 1);
      expect((await repo.load()).map((OutboxItem i) => i.id), <String>['it1']);
    });
  });
}
