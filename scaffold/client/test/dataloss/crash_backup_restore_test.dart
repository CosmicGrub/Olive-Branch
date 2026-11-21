// OLIVE BRANCH — data-loss harness, a backup and a restore killed at every step, plus the restore-equivalence check
// (a digest of every area before and after). A backup only reads, so a kill changes nothing. A restore adds what the phone
// does not hold, one whole area at a time, and never deletes or overwrites: after any kill each area is as it was or
// complete, and running the restore again finishes the job.
@Tags(<String>['dataloss'])
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/local_services.dart';
import 'package:olive_client/local_snapshot.dart';
import 'package:olive_client/local_store.dart';
import 'package:olive_client/store_cipher.dart';

import 'crash_harness.dart';

final Uint8List _oldKey = Uint8List.fromList(List<int>.generate(32, (int i) => 3 + i));
final Uint8List _newKey = Uint8List.fromList(List<int>.generate(32, (int i) => 111 + i));

NamespaceSpec specOf(String area, {String? owner}) {
  final LocalDataEntry e = localDataEntry(area);
  final String name = switch (e.scope) {
    LocalScope.child => 'child.${owner ?? 'ivy'}.$area',
    LocalScope.guardian => 'guardian.${owner ?? 'local-guardian'}.$area',
    LocalScope.device => 'device.$area',
  };
  return NamespaceSpec(name: name, schema: e.schema, encrypted: e.encrypted, maxBytes: e.maxBytes);
}

Map<String, Object?> rich(String t, {int pad = 0}) => <String, Object?>{
      'a': 'A-$t', 'b': 'B-$t', 'pad': 'z' * pad, 'strokes': <Object?>[<Object?>[1, 2], <Object?>[3, 4]], 'when': '2026-11-20', 'n': null,
    };

/// A phone full of things from every class: family, the child's private ones and the device's own.
Future<void> fillPhone(LocalStore s, {String tag = ''}) async {
  Future<void> p(String area, String key, Object? v, {String? owner}) => s.open(specOf(area, owner: owner)).put(key, v);
  await p('pictures', 'doodle:1', rich('doodle$tag', pad: 4000));
  await p('pictures', 'doodle:2', rich('doodle2$tag'));
  await p('lists', 'want:1', rich('bike$tag'));
  await p('growing', 'capsule:1', rich('capsule$tag', pad: 2000));
  await p('care', 'section:allergy', rich('care$tag'));
  await p('emergencycard', 'card', rich('card$tag'));
  await p('coordination', 'dose:1', rich('dose$tag'));
  await p('familysync', 'doc', rich('syncdoc$tag', pad: 5000));
  await p('familyledger', 'ledger', rich('ledger$tag'));
  await p('outbox', 'items', <Object?>[rich('o1$tag'), rich('o2$tag')]);
  // Hers. Must never ride in the family backup.
  await p('journal', 'entry:1', rich('private-journal$tag'));
  await p('worries', 'w:1', rich('private-worry$tag'));
  await p('memorybox', 'm:1', rich('her-memory$tag'));
  // This device's own. Must never be copied to another phone.
  await p('devicekey', 'key', rich('device-secret$tag'));
  await p('localpin', 'pin', rich('pin-hash$tag'));
  await p('role', 'role', 'mom');
}

LocalStore sourceStore() => LocalStore(backend: MemoryStoreBackend(), cipher: AesGcmStoreCipher(_oldKey));

class W {
  W(this.disk, this.clock) : store = LocalStore(backend: disk.open(clock), cipher: AesGcmStoreCipher(_newKey));
  final Disk disk;
  final CrashClock clock;
  final LocalStore store;
}

void main() {
  late LocalStore source;
  late LocalSnapshot snap;
  late Map<String, String> sourceFamilyDigests;

  setUpAll(() async {
    source = sourceStore();
    await fillPhone(source);
    snap = (LocalSnapshot.fromBytes((await takeSnapshot(source)).toBytes()))!;
    sourceFamilyDigests = await areaDigests(source);
  });

  group('a backup', () {
    test('carries every family area, lists what it left out and why, and holds none of her private areas or the device\'s own', () async {
      final LocalSnapshot s = await takeSnapshot(source);
      expect(s.areas.keys, containsAll(<String>[
        'child.ivy.pictures', 'child.ivy.lists', 'child.ivy.growing', 'child.ivy.care', 'child.ivy.emergencycard',
        'child.ivy.coordination', 'guardian.local-guardian.familysync', 'guardian.local-guardian.familyledger', 'child.ivy.outbox',
      ]));
      expect(s.leftOut, <String, String>{
        'child.ivy.journal': 'child_private',
        'child.ivy.worries': 'child_private',
        'child.ivy.memorybox': 'child_private',
        'device.devicekey': 'device_bound',
        'guardian.local-guardian.localpin': 'device_bound',
        'device.role': 'device_bound',
      });
      final String text = utf8.decode(s.toBytes());
      for (final String secret in <String>['private-journal', 'private-worry', 'her-memory', 'device-secret', 'pin-hash']) {
        expect(text.contains(secret), isFalse, reason: '$secret must not be in the family backup');
      }
    });

    test('killed at every step it changes nothing, and the next backup is the same one', () async {
      final Map<String, String> allBefore = <String, String>{};
      final int n = await sweepCrashPoints<W>(
        makeDisk: () async => MemDisk(),
        build: (Disk d, CrashClock c) => W(d, c),
        beforeEachRun: (Disk d) async {
          final LocalStore pre = LocalStore(backend: d.open(CrashClock()), cipher: AesGcmStoreCipher(_newKey));
          await fillPhone(pre);
          if (allBefore.isEmpty) {
            allBefore.addAll(await areaDigests(pre, classes: BackupClass.values.toSet()));
          }
        },
        run: (W w, Oracle o) async {
          await takeSnapshot(w.store);
        },
        verify: (W w, Oracle o, CrashClock c) async {
          expect(await areaDigests(w.store, classes: BackupClass.values.toSet()), allBefore, reason: 'a backup changed the phone');
          expect(await w.store.quarantined(), 0);
          expect((await takeSnapshot(w.store)).digest, (await takeSnapshot(w.store)).digest);
        },
      );
      expect(n, greaterThan(10), reason: 'the sweep must be wide');
    });

    test('a write that lands while the backup runs is wholly in or wholly out of each area, never half', () async {
      final LocalStore s = sourceStore();
      final LocalNamespace ns = s.open(specOf('pictures'));
      final List<Future<void>> writes = <Future<void>>[
        for (int i = 1; i <= 25; i++) ns.put('doodle:1', rich('v$i', pad: 800)),
      ];
      final List<LocalSnapshot> snaps = <LocalSnapshot>[];
      for (int i = 0; i < 6; i++) {
        snaps.add(await takeSnapshot(s));
        await Future<void>.delayed(Duration.zero);
      }
      await Future.wait(writes);
      for (final LocalSnapshot x in snaps) {
        final Object? v = x.areas['child.ivy.pictures']?.data['doodle:1'];
        if (v == null) continue;
        final Map<String, Object?> m = v as Map<String, Object?>;
        expect((m['a']! as String).substring(2), (m['b']! as String).substring(2), reason: 'a half-written value reached the backup');
      }
    });
  });

  group('a restore onto a new, empty phone, killed at every step', () {
    for (final bool real in <bool>[false, true]) {
      test('on ${real ? 'real files (torn temp files too)' : 'the in-memory disk'}: each area is absent or complete, and running it again finishes the job', () async {
        final int n = await sweepCrashPoints<W>(
          makeDisk: () => real ? DirDisk.make(tear: true) : Future<Disk>.value(MemDisk()),
          build: (Disk d, CrashClock c) => W(d, c),
          run: (W w, Oracle o) async {
            await restoreSnapshot(w.store, snap);
          },
          verify: (W w, Oracle o, CrashClock c) async {
            // Each family area on the new phone is either absent or exactly the source's, never part of it.
            final Map<String, String> got = await areaDigests(w.store);
            for (final MapEntry<String, String> e in got.entries) {
              expect(sourceFamilyDigests[e.key], e.value, reason: '${e.key} is only partly restored');
            }
            expect(await w.disk.quarantinedBlobs(), isEmpty);
            // Run it again (the app was restarted): the phone now matches the source in every family area.
            final RestoreReport r = await restoreSnapshot(w.store, snap);
            expect(r.refused, isEmpty);
            final Equivalence eq = compareDigests(sourceFamilyDigests, await areaDigests(w.store));
            expect(eq.ok, isTrue, reason: '$eq');
            // And again: nothing more to add, nothing disturbed.
            final RestoreReport again = await restoreSnapshot(w.store, snap);
            expect(again.keysAdded, 0);
            expect(again.valuesKept, 0);
            expect(await w.disk.quarantinedBlobs(), isEmpty);
            // Hers and the device's own did not ride along.
            final Map<String, String> everything = await areaDigests(w.store, classes: BackupClass.values.toSet());
            expect(everything.keys.toSet(), sourceFamilyDigests.keys.toSet());
          },
        );
        expect(n, greaterThan(real ? 25 : 30));
      }, timeout: const Timeout(Duration(minutes: 4)));
    }
  });

  group('a restore onto a phone that already holds some of the same things', () {
    // The new phone was used a little before the restore: it already wrote a doodle with the same name (a different
    // picture), a new one of its own, and a card of its own.
    Future<void> seedNewPhone(Disk d) async {
      final LocalStore s = LocalStore(backend: d.open(CrashClock()), cipher: AesGcmStoreCipher(_newKey));
      await s.open(specOf('pictures')).put('doodle:1', rich('NEW-PHONE-doodle1'));
      await s.open(specOf('pictures')).put('doodle:99', rich('only-on-new-phone'));
      await s.open(specOf('emergencycard')).put('card', rich('NEW-PHONE-card'));
      await s.open(specOf('lists')).put('want:1', snap.areas['child.ivy.lists']!.data['want:1']); // identical to the backup's
    }

    test('nothing it held is changed or lost, and every value the backup held is either live or kept in quarantine', () async {
      final int n = await sweepCrashPoints<W>(
        makeDisk: () async => MemDisk(),
        build: (Disk d, CrashClock c) => W(d, c),
        beforeEachRun: seedNewPhone,
        run: (W w, Oracle o) async {
          await restoreSnapshot(w.store, snap);
        },
        verify: (W w, Oracle o, CrashClock c) async {
          // The restart finishes the job.
          await restoreSnapshot(w.store, snap);
          Future<Object?> live(String area, String key) async => w.store.open(specOf(area)).get(key);
          expect(await live('pictures', 'doodle:1'), rich('NEW-PHONE-doodle1'), reason: 'the new phone\'s own picture was overwritten');
          expect(await live('pictures', 'doodle:99'), rich('only-on-new-phone'));
          expect(await live('emergencycard', 'card'), rich('NEW-PHONE-card'));
          // The backup's doodle:1 and card did not displace them; they are kept, whole, in quarantine.
          final String kept = (await w.disk.quarantinedBlobs()).map((Uint8List b) => utf8.decode(b)).join('\n');
          expect(kept, contains(canonicalJson(rich('doodle', pad: 4000))), reason: 'the backup\'s doodle:1 was dropped');
          expect(kept, contains(canonicalJson(rich('card'))), reason: 'the backup\'s emergency card was dropped');
          // Everything else from the backup is live.
          expect(await live('pictures', 'doodle:2'), rich('doodle2'));
          expect(await live('growing', 'capsule:1'), rich('capsule', pad: 2000));
          expect(await live('lists', 'want:1'), rich('bike'));
        },
      );
      expect(n, greaterThan(20), reason: 'the sweep must be wide');
    });
  });

  group('a restore onto a phone that already caught up joins the two whole records, killed at every step', () {
    // The sealed family record and the waiting-to-send list each keep everything under ONE key. A phone that has
    // already caught up from the other grown-up holds a different value under that key than the backup does; keeping
    // one and parking the other would lose the other's events and items from the live record.
    final NamespaceSpec syncSpec = specOf('familysync');
    final NamespaceSpec boxSpec = specOf('outbox');
    Map<String, Object?> doc(List<String> events, Map<String, Object?> peers, List<Object?> notes) =>
        <String, Object?>{'v': 1, 'e': events, 'p': peers, 'q': notes};
    final Map<String, Object?> heldDoc = doc(<String>['w2', 'w3'], <String, Object?>{'peerB': <String, Object?>{'s': 2}}, <Object?>[<Object?>['s1', 'a1', 1]]);
    final Map<String, Object?> backupDoc = doc(<String>['w1', 'w2'], <String, Object?>{'peerA': <String, Object?>{'s': 1}, 'peerB': <String, Object?>{'s': 9}}, <Object?>[<Object?>['s1', 'a1', 1], <Object?>['s2', 'a2', 4]]);
    Map<String, Object?> item(String id) => <String, Object?>{'id': id, 'kind': 'drawing', 'payload': <String, Object?>{'x': id}};
    final LocalSnapshot backup = LocalSnapshot(<String, AreaImage>{
      syncSpec.name: AreaImage(syncSpec.name, syncSpec.schema, <String, Object?>{'doc': backupDoc}),
      boxSpec.name: AreaImage(boxSpec.name, boxSpec.schema, <String, Object?>{'items': <Object?>[item('a'), item('b')]}),
    });

    for (final bool real in <bool>[false, true]) {
    test('on ${real ? 'real files' : 'the in-memory disk'}: the record is wholly the held one or wholly the join, the join keeps both sides, nothing is parked, and a repeat adds nothing', () async {
      final String heldJson = canonicalJson(heldDoc);
      final int n = await sweepCrashPoints<W>(
        makeDisk: () => real ? DirDisk.make(tear: true) : Future<Disk>.value(MemDisk()),
        build: (Disk d, CrashClock c) => W(d, c),
        beforeEachRun: (Disk d) async {
          final LocalStore s = LocalStore(backend: d.open(CrashClock()), cipher: AesGcmStoreCipher(_newKey));
          await s.open(syncSpec).put('doc', heldDoc);
          await s.open(boxSpec).put('items', <Object?>[item('x'), item('b')]);
        },
        run: (W w, Oracle o) async {
          await restoreSnapshot(w.store, backup);
        },
        verify: (W w, Oracle o, CrashClock c) async {
          final Object? mid = await w.store.open(syncSpec).get('doc');
          final Map<String, Object?> m = (mid! as Map<dynamic, dynamic>).cast<String, Object?>();
          if (canonicalJson(m) != heldJson) {
            expect((m['e']! as List<dynamic>).cast<String>(), <String>['w2', 'w3', 'w1'], reason: 'a half-joined record');
          }
          expect(await w.store.quarantined(), 0);
          final RestoreReport r = await restoreSnapshot(w.store, backup); // the restart finishes the job
          expect(r.refused, isEmpty);
          final Map<String, Object?> done = ((await w.store.open(syncSpec).get('doc'))! as Map<dynamic, dynamic>).cast<String, Object?>();
          expect((done['e']! as List<dynamic>).cast<String>(), <String>['w2', 'w3', 'w1'], reason: 'an event from one side is missing');
          final Map<String, Object?> peers = (done['p']! as Map<dynamic, dynamic>).cast<String, Object?>();
          expect(peers.keys.toSet(), <String>{'peerA', 'peerB'});
          expect(canonicalJson(peers['peerB']), canonicalJson(<String, Object?>{'s': 2}), reason: 'the held summary must win');
          expect((done['q']! as List<dynamic>).length, 2);
          final List<dynamic> items = (await w.store.open(boxSpec).get('items'))! as List<dynamic>;
          expect(items.map((dynamic i) => (i as Map<dynamic, dynamic>)['id']).toList(), <String>['x', 'b', 'a'], reason: 'an item is missing or doubled');
          expect(await w.store.quarantined(), 0, reason: 'a join must leave nothing parked');
          final RestoreReport again = await restoreSnapshot(w.store, backup);
          expect(again.keysAdded + again.keysJoined, 0, reason: 'a repeat changed something');
        },
      );
      expect(n, greaterThan(5), reason: 'the sweep must be wide');
    });
    }

    test('a record or list that cannot be read as one is kept whole in quarantine, never merged by guesswork', () async {
      final W w = W(MemDisk(), CrashClock());
      await w.store.open(syncSpec).put('doc', heldDoc);
      final LocalSnapshot odd = LocalSnapshot(<String, AreaImage>{
        syncSpec.name: AreaImage(syncSpec.name, syncSpec.schema, <String, Object?>{'doc': <String, Object?>{'v': 2, 'e': <Object?>[]}}),
      });
      final RestoreReport r = await restoreSnapshot(w.store, odd);
      expect(r.keysJoined, 0);
      expect(r.valuesKept, 1);
      expect(canonicalJson(await w.store.open(syncSpec).get('doc')), canonicalJson(heldDoc));
      expect((await w.disk.quarantinedBlobs()).map((Uint8List b) => utf8.decode(b)).join(), contains('"v":2'));
    });
  });

  group('the restore-equivalence check', () {
    test('equal when nothing changed; a changed byte, a missing area and a surprise area are each named', () async {
      final Map<String, String> a = await areaDigests(source);
      expect(compareDigests(a, a).ok, isTrue);
      final LocalStore other = sourceStore();
      await restoreSnapshot(other, snap);
      expect(compareDigests(a, await areaDigests(other)).ok, isTrue);

      // one byte different
      await other.open(specOf('pictures')).put('doodle:2', rich('doodle2-changed'));
      final Equivalence changed = compareDigests(a, await areaDigests(other));
      expect(changed.changed, <String>['child.ivy.pictures']);
      expect(changed.ok, isFalse);

      // an area missing
      final LocalStore partial = sourceStore();
      await partial.open(specOf('lists')).put('want:1', rich('bike'));
      final Equivalence miss = compareDigests(a, await areaDigests(partial));
      expect(miss.missing, contains('child.ivy.pictures'));
      expect(miss.changed, isEmpty);

      // a surprise area
      final Map<String, String> plus = <String, String>{...a, 'child.ivy.voice': 'abc'};
      expect(compareDigests(a, plus).unexpected, <String>['child.ivy.voice']);
    });

    test('the digest does not depend on the order keys were written, and a sealed area gives the same digest under another phone\'s key', () async {
      final LocalStore x = sourceStore(), y = LocalStore(backend: MemoryStoreBackend(), cipher: AesGcmStoreCipher(_newKey));
      await x.open(specOf('growing')).put('a', rich('1'));
      await x.open(specOf('growing')).put('b', rich('2'));
      await y.open(specOf('growing')).put('b', <String, Object?>{'n': null, 'when': '2026-11-20', 'strokes': <Object?>[<Object?>[1, 2], <Object?>[3, 4]], 'pad': '', 'b': 'B-2', 'a': 'A-2'});
      await y.open(specOf('growing')).put('a', rich('1'));
      expect(compareDigests(await areaDigests(x), await areaDigests(y)).ok, isTrue);
    });
  });
}
