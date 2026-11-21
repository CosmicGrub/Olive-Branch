// OLIVE BRANCH — data-loss harness: a phone is lost, a new one takes its place from a backup, the old one turns up again,
// a backup is put back twice, an old backup is put back on a phone that has moved on, and the whole family starts over
// from backups. Every scenario ends with the same record on every phone that is left, and the restore-equivalence
// check (a digest of every area before and after) naming anything that differs.
//
// What "nothing is lost" means here, exactly (see mesh_sim.dart): everything PROTECTED when the phone is lost (also on
// another device, or in a backup taken after it) must be in the end state, and everything a surviving device makes
// afterwards must be too. A thing made on a phone that was then lost before it reached any other device or any backup
// is on that phone only; the test counts those ("at risk"), and the second group of tests shows the family setting
// that closes the gap (back up as part of saving), after which the count is zero.
@Tags(<String>['dataloss'])
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/local_snapshot.dart';
import 'package:olive_client/local_store.dart';
import 'package:olive_client/offline_outbox.dart';

import 'mesh_sim.dart';

Uint8List _key(int n) => Uint8List.fromList(List<int>.generate(32, (int i) => n + i));

/// The item ids a backup holds (put into a scratch phone, so exactly what a restore would bring back).
Future<Set<String>> itemsInBackup(Sim s, Uint8List bytes) async {
  final PhoneNode scratch = PhoneNode('scratch', s.sam.who, s.rig, s.clock, _key(200), s.streams);
  await scratch.start();
  await restoreSnapshot(scratch.store, LocalSnapshot.fromBytes(bytes)!);
  await scratch.start();
  return scratch.itemIds();
}

class Lost {
  Lost(this.protected, this.atRisk, this.beforeLoss);
  final Set<String> protected, atRisk;

  /// Everything acknowledged up to the moment of the loss.
  final Set<String> beforeLoss;
}

/// Runs the family for [steps], then loses mom's phone (its disk is gone for good unless a test brings it back).
Future<Lost> runThenLoseMom(Sim s, int steps) async {
  s.sam.lost = true;
  for (int i = 0; i < steps; i++) {
    await s.step();
  }
  final Set<String> before = s.acked.keys.toSet();
  final Set<String> protected = <String>{
    ...s.dad.itemIds(),
    for (final OutboxItem i in await s.tablet.waiting()) i.id,
    if (s.backups['mom'] != null) ...await itemsInBackup(s, s.backups['mom']!),
  };
  s.mom.lost = true;
  return Lost(protected.intersection(before), before.difference(protected), before);
}

/// The new phone takes mom's place: restore her newest backup (when she had one), start again over it.
Future<RestoreReport?> bringUpSam(Sim s) async {
  s.sam.lost = false;
  await s.sam.start();
  final Uint8List? b = s.backups['mom'];
  if (b == null) return null;
  final RestoreReport r = await restoreSnapshot(s.sam.store, LocalSnapshot.fromBytes(b)!);
  await s.sam.start();
  return r;
}

void main() {
  int totalAtRisk = 0, runsWithBackup = 0;

  group('a phone is lost and a new one takes its place', () {
    for (final int seed in <int>[11, 12, 13, 14, 15, 16]) {
      test('seed $seed: everything protected survives, the new phone matches the backup, both phones end the same', () async {
        final Sim s = await Sim.make(seed);
        final Lost lost = await runThenLoseMom(s, 60);
        final RestoreReport? report = await bringUpSam(s);
        if (report != null) {
          runsWithBackup++;
          expect(report.refused, isEmpty, reason: 'seed $seed: ${report.refused}');
          // Restore-equivalence: what the new phone holds is exactly what the backup held, area by area.
          final LocalSnapshot snap = LocalSnapshot.fromBytes(s.backups['mom']!)!;
          final Equivalence eq = compareDigests(snap.digests, await areaDigests(s.sam.store));
          expect(eq.ok, isTrue, reason: 'seed $seed: $eq');
        }
        // Life goes on without mom's old phone: the others keep making things, and sharing.
        for (int i = 0; i < 40; i++) {
          await s.step();
        }
        final Set<String> madeAfter = s.acked.keys.toSet().difference(lost.beforeLoss);
        await s.settle();
        for (final String id in <String>{...lost.protected, ...madeAfter}) {
          expect(s.dad.itemIds().contains(id), isTrue, reason: 'seed $seed: $id is missing on dad\'s phone');
          expect(s.sam.itemIds().contains(id), isTrue, reason: 'seed $seed: $id is missing on the new phone');
        }
        expect(s.sam.eventIds(), s.dad.eventIds(), reason: 'seed $seed: the new phone and dad\'s disagree');
        expect(s.sam.engine.heldCount, 0);
        expect(await s.tablet.waiting(), isEmpty);
        totalAtRisk += lost.atRisk.length;
      });
    }

    test('when the old phone turns up again nothing that was only on it is lost, and nothing is doubled on a screen', () async {
      for (final int seed in <int>[21, 22, 23, 24, 25, 26]) {
        final Sim s = await Sim.make(seed);
        await runThenLoseMom(s, 50);
        await bringUpSam(s);
        for (int i = 0; i < 25; i++) {
          await s.step();
        }
        await s.settle();
        // "Found it in the car": mom's old phone is switched on, its disk exactly as it was.
        s.mom.lost = false;
        await s.mom.start();
        await s.settle();
        for (final String id in s.acked.keys) {
          for (final PhoneNode p in <PhoneNode>[s.mom, s.dad, s.sam]) {
            expect(p.itemIds().contains(id), isTrue, reason: 'seed $seed: $id missing on ${p.name} after the old phone came back');
          }
        }
        expect(s.mom.eventIds(), s.dad.eventIds());
        expect(s.sam.eventIds(), s.dad.eventIds());
        expect(s.mom.engine.equivocations, isEmpty);
      }
    });
  });

  group('the family chooses to back up as part of saving: a lost phone then loses nothing at all', () {
    for (final int seed in <int>[31, 32, 33, 34, 35, 36]) {
      test('seed $seed: nothing acknowledged before the loss is at risk, and all of it is on the new phone', () async {
        final Sim s = await Sim.make(seed);
        s.backUpAfterEveryWrite = true;
        final Lost lost = await runThenLoseMom(s, 60);
        expect(lost.atRisk, isEmpty, reason: 'seed $seed: only on the lost phone: ${lost.atRisk}');
        await bringUpSam(s);
        for (int i = 0; i < 25; i++) {
          await s.step();
        }
        await s.settle();
        for (final String id in s.acked.keys) {
          expect(s.sam.itemIds().contains(id), isTrue, reason: 'seed $seed: $id missing on the new phone');
          expect(s.dad.itemIds().contains(id), isTrue, reason: 'seed $seed: $id missing on dad\'s phone');
        }
        expect(s.sam.eventIds(), s.dad.eventIds());
      });
    }
  });

  group('restoring is safe to repeat and safe on a phone that has moved on', () {
    test('a backup put back twice, then onto a phone that already caught up, joins and never overwrites', () async {
      final Sim s = await Sim.make(41, drop: 0); // the catch-up share must arrive: this test is about the join, not the wire
      s.backUpAfterEveryWrite = true;
      s.sam.lost = true;
      s.net.cut('mom', 'dad');
      for (int i = 0; i < 6; i++) {
        await s.authorAt(s.mom);
        await s.authorAt(s.dad);
      }
      final Uint8List momBackup = s.backups['mom']!;
      final Set<String> inBackup = await itemsInBackup(s, momBackup);
      expect(inBackup.length, 6);
      s.mom.lost = true;
      // The new phone catches up from dad FIRST (it holds dad's six), and only then is the backup put on it.
      s.sam.lost = false;
      await s.sam.start();
      s.net.mendAll();
      s.share(s.dad, s.sam);
      await s.tickNet(20);
      final Set<String> fromDad = s.sam.itemIds();
      expect(fromDad.length, greaterThanOrEqualTo(6));
      final RestoreReport r1 = await restoreSnapshot(s.sam.store, LocalSnapshot.fromBytes(momBackup)!);
      await s.sam.start();
      expect(r1.refused, isEmpty);
      expect(r1.keysJoined, greaterThan(0), reason: 'the sealed record must be joined, not kept-and-quarantined');
      expect(s.sam.itemIds(), <String>{...fromDad, ...inBackup}, reason: 'the join must hold everything from both');
      // The family record must be live, not parked in quarantine.
      final Map<String, String> after1 = await areaDigests(s.sam.store);
      final RestoreReport r2 = await restoreSnapshot(s.sam.store, LocalSnapshot.fromBytes(momBackup)!);
      expect(r2.keysAdded, 0);
      expect(r2.keysJoined, 0);
      expect(compareDigests(after1, await areaDigests(s.sam.store)).ok, isTrue, reason: 'the second restore changed something');
      await s.settle();
      expect(s.sam.eventIds(), s.dad.eventIds());
    });

    test('an old backup put back on the phone it came from does not take back anything newer', () async {
      final Sim s = await Sim.make(42);
      s.sam.lost = true;
      for (int i = 0; i < 4; i++) {
        await s.authorAt(s.mom);
      }
      final Uint8List old = await s.mom.backup();
      for (int i = 0; i < 5; i++) {
        await s.authorAt(s.mom);
      }
      final Set<String> before = s.mom.itemIds();
      expect(before.length, 9);
      final RestoreReport r = await restoreSnapshot(s.mom.store, LocalSnapshot.fromBytes(old)!);
      await s.mom.start();
      expect(r.refused, isEmpty);
      expect(s.mom.itemIds(), before, reason: 'an old backup rewound or altered the record');
      expect(await s.mom.store.backend.quarantineCount(), 0, reason: 'a join left a copy parked instead of live');
    });

    test('her waiting-to-send list is joined too: a restored tablet sends what the backup held and what it held itself', () async {
      final Sim s = await Sim.make(43);
      s.sam.lost = true;
      await s.tablet.make('sim.drawing', 'ivy-a');
      await s.tablet.make('sim.score', 'ivy-b');
      final Uint8List old = await s.tablet.backup();
      await s.tablet.make('sim.memory', 'ivy-c');
      await s.tablet.acked('ivy-a'); // delivered since the backup
      // A replacement tablet already holds one thing of its own when the backup is put on it.
      final TabletNode fresh = TabletNode(_key(90), s.clock);
      await fresh.start();
      await fresh.make('sim.message', 'ivy-d');
      final RestoreReport r = await restoreSnapshot(fresh.store, LocalSnapshot.fromBytes(old)!);
      expect(r.refused, isEmpty);
      expect(r.keysJoined, 1);
      expect(<String>{for (final OutboxItem i in await fresh.waiting()) i.id}, <String>{'ivy-a', 'ivy-b', 'ivy-d'});
      expect(await fresh.store.backend.quarantineCount(), 0);
    });
  });

  group('the whole family starts over from backups', () {
    test('every area on every new device matches what its old device held, her private areas are absent, no device key came over', () async {
      final Sim s = await Sim.make(51);
      s.sam.lost = true;
      // Things a phone holds that must NOT travel in a family backup.
      await s.mom.store.open(specOfArea('devicekey')).put('key', <String, Object?>{'secret': 'm'});
      await s.mom.store.open(specOfArea('role')).put('role', 'mom');
      await s.tablet.store.open(s.tablet.journalSpec).put('entry:1', <String, Object?>{'text': 'hers'});
      for (int i = 0; i < 60; i++) {
        await s.step();
      }
      await s.settle();
      expect(s.acked, isNotEmpty);

      final Map<String, Map<String, String>> before = <String, Map<String, String>>{
        'mom': await areaDigests(s.mom.store),
        'dad': await areaDigests(s.dad.store),
        'tablet': await areaDigests(s.tablet.store),
      };
      final Map<String, Uint8List> bk = <String, Uint8List>{
        'mom': await s.mom.backup(),
        'dad': await s.dad.backup(),
        'tablet': await s.tablet.backup(),
      };
      final Set<String> record = s.mom.itemIds();

      // Everything is gone. New devices, new keys, empty disks.
      final PhoneNode mom2 = PhoneNode('mom2', s.rig.mom, s.rig, s.clock, _key(130), s.streams);
      final PhoneNode dad2 = PhoneNode('dad2', s.rig.dad, s.rig, s.clock, _key(140), s.streams);
      final TabletNode tab2 = TabletNode(_key(150), s.clock);
      await mom2.start();
      await dad2.start();
      await tab2.start();
      for (final (String, LocalStore) d in <(String, LocalStore)>[('mom', mom2.store), ('dad', dad2.store), ('tablet', tab2.store)]) {
        final RestoreReport r = await restoreSnapshot(d.$2, LocalSnapshot.fromBytes(bk[d.$1]!)!);
        expect(r.refused, isEmpty, reason: '${d.$1}: ${r.refused}');
        final Equivalence eq = compareDigests(before[d.$1]!, await areaDigests(d.$2));
        expect(eq.ok, isTrue, reason: '${d.$1}: $eq');
        if (d.$1 != 'tablet') expect(eq.same, isNotEmpty); // a settled tablet has nothing waiting: no family area at all
      }
      await mom2.start();
      await dad2.start();
      expect(mom2.itemIds(), record);
      expect(dad2.itemIds(), record);
      // Not in a family backup, ever: the device's own key and role, and every one of her private areas.
      expect((await mom2.store.namespaces()).where((String n) => n.endsWith('.devicekey') || n.endsWith('.role')), isEmpty);
      expect((await tab2.store.namespaces()).where((String n) => n.endsWith('.journal')), isEmpty);
    });
  });

  test('at-risk is reported, not hidden: the periodic-backup runs counted what only the lost phone held', () {
    // Not an assertion about the number (it depends on the seeds); the first group's runs are the evidence, and the
    // second group proves the setting that makes it zero. The count is printed so a change in it is seen in the log.
    // ignore: avoid_print
    print('data-loss harness: items only on the lost phone with periodic backups: $totalAtRisk across the seeded runs '
        '($runsWithBackup runs had a backup to restore)');
    expect(totalAtRisk, greaterThanOrEqualTo(0));
  });
}
