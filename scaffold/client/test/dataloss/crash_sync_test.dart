// OLIVE BRANCH — data-loss harness, crash injection over family sync. The phone is killed at every step of a sync merge
// (events taken in, held out of order, released, a refused duplicate counter, a note of what the other phone holds, an
// own write), on an in-memory disk and on real files, and the app restarts over the same disk. (A backup and a restore
// are swept in crash_backup_restore_test.dart.)
@Tags(<String>['dataloss'])
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/family_ledger.dart' show hexOf;
import 'package:olive_client/family_sync_engine.dart';
import 'package:olive_client/family_sync_event.dart';
import 'package:olive_client/local_services.dart';
import 'package:olive_client/local_store.dart';
import 'package:olive_client/store_cipher.dart';

import '../family_sync_test_support.dart';
import '../family_test_support.dart';
import 'crash_harness.dart';

final Uint8List _momKey = Uint8List.fromList(List<int>.generate(32, (int i) => 10 + i));
const String kSyncNs = 'guardian.local-guardian.familysync';

NamespaceSpec syncSpec() {
  final LocalDataEntry e = localDataEntry('familysync');
  return NamespaceSpec(name: kSyncNs, schema: e.schema, encrypted: true, maxBytes: e.maxBytes);
}

class Snap {
  Snap(this.count, this.held, this.applied, this.equiv, this.peers);
  final int count, held, equiv, peers;
  final Set<String> applied;

  static Snap of(SyncEngine e) => Snap(
        e.eventCount,
        e.heldCount,
        <String>{for (final String s in e.streamHexes) for (final SyncEvent x in e.events(s)) x.idHex},
        e.equivocations.length,
        e.peers.length,
      );
}

class World {
  World(this.disk, this.clock, this.rig, {Uint8List? key})
      : store = LocalStore(backend: disk.open(clock), cipher: AesGcmStoreCipher(key ?? _momKey)) {
    engine = rig.engine(rig.mom, clock: Clock(t0 + 10 * day), repo: LocalStoreSyncRepository(store.open(syncSpec())));
  }
  final Disk disk;
  final CrashClock clock;
  final SyncRig rig;
  final LocalStore store;
  late final SyncEngine engine;
}

void main() {
  late SyncRig rig;
  late Uint8List s1, s2;
  late SyncEngine dad;
  late List<SyncEvent> dadS1, dadS2;
  late SyncEvent equivocator;

  setUpAll(() async {
    rig = await SyncRig.make();
    s1 = await syncStreamId(rig.fid, 'emergencycard', 'ivy');
    s2 = await syncStreamId(rig.fid, 'emergencycard', 'mia');
    final Clock c = Clock(t0 + 10 * day);
    dad = rig.engine(rig.dad, clock: c);
    dadS1 = <SyncEvent>[];
    dadS2 = <SyncEvent>[];
    for (int i = 1; i <= 3; i++) {
      dadS1.add((await dad.append(kind: 'emergency.set', streamId: s1, payload: <String, Object?>{'t': 'ivy-$i'}, state: rig.state)).event!);
      dadS2.add((await dad.append(kind: 'emergency.set', streamId: s2, payload: <String, Object?>{'t': 'mia-$i'}, state: rig.state)).event!);
    }
    equivocator = await SyncEvent.create(
      device: rig.dad.key, ring: guardianRing(), epoch: 0, fid: rig.fid, streamId: s1, seq: 1, hlcMs: t0 + 10 * day, hlcC: 7,
      prev: const <List<int>>[], kind: 'emergency.set', payload: <String, Object?>{'t': 'a different seq-1'},
    );
  });

  group('a sync merge killed at every step', () {
    // The workload, one acknowledged operation at a time. pre/post are the engine's state around each one.
    late List<Snap> pre, post;
    late List<Snap> dryPost;
    int cur = -1;
    bool inOp = false;
    late Set<String> ackedApplied;

    Future<void> workload(World w, Oracle o) async {
      pre = <Snap>[];
      post = <Snap>[];
      ackedApplied = <String>{};
      cur = -1;
      inOp = false;
      final List<Future<void> Function()> ops = <Future<void> Function()>[
        () async => await w.engine.ingest(<Uint8List>[for (final SyncEvent e in dadS1) e.wire], state: rig.state),
        () async => await w.engine.append(kind: 'emergency.set', streamId: s1, payload: <String, Object?>{'t': 'mom-1'}, state: rig.state),
        // seq 2 and 3 arrive first: held, and still saved.
        () async => await w.engine.ingest(<Uint8List>[dadS2[1].wire, dadS2[2].wire], state: rig.state),
        // seq 1 arrives: releases both.
        () async => await w.engine.ingest(<Uint8List>[dadS2[0].wire], state: rig.state),
        // a refused duplicate counter is kept even though nothing else is added.
        () async => await w.engine.ingest(<Uint8List>[equivocator.wire], state: rig.state),
        () async => await w.engine.notePeer(hexOf(rig.dad.key.publicKey), dad.summary()),
      ];
      for (int i = 0; i < ops.length; i++) {
        cur = i;
        pre.add(Snap.of(w.engine));
        inOp = true;
        await ops[i]();
        inOp = false;
        final Snap s = Snap.of(w.engine);
        post.add(s);
        ackedApplied = s.applied;
      }
    }

    Future<void> verifySync(World w, Oracle o, CrashClock crashed, {required bool dry}) async {
      final SyncEngine again = w.engine;
      await again.restore();
      final Snap got = Snap.of(again);
      expect(w.store.open(syncSpec()).recovery, RecoveryKind.none);
      expect(await w.disk.quarantinedBlobs(), isEmpty, reason: 'a kill damaged the sealed sync document');
      expect(got.applied.containsAll(ackedApplied), isTrue, reason: 'an acknowledged event is gone after the restart');
      if (dry) {
        dryPost = post;
        expect(got.applied.length, post.last.applied.length);
      } else if (crashed.dead && inOp) {
        final Snap before = pre[cur], after = dryPost[cur];
        final bool wholeOld = got.count == before.count && got.applied.length == before.applied.length &&
            got.equiv == before.equiv && got.peers == before.peers;
        final bool wholeNew = got.count == after.count && got.applied.length == after.applied.length &&
            got.equiv == after.equiv && got.peers == after.peers;
        expect(wholeOld || wholeNew, isTrue,
            reason: 'op $cur: restored (${got.count} held+applied, ${got.applied.length} applied, ${got.equiv} refused) is neither the '
                'state before (${before.count}, ${before.applied.length}, ${before.equiv}) nor after (${after.count}, ${after.applied.length}, ${after.equiv})');
        if (wholeOld) expect(got.applied, before.applied, reason: 'old state must be exactly the old events');
      }
      // The restart carries on: the other phone shares again and both end with the same record, nothing doubled.
      final SyncIngest r = await again.ingest(dad.eventsFor(again.summary()).wires, state: rig.state);
      expect(r.refused - (r.reasons['equivocation'] ?? 0), 0, reason: '${r.reasons}');
      await dad.ingest(again.eventsFor(dad.summary()).wires, state: rig.state);
      for (final Uint8List sid in <Uint8List>[s1, s2]) {
        expect(again.events(hexOf(sid)).map((SyncEvent e) => e.idHex).toSet(),
            dad.events(hexOf(sid)).map((SyncEvent e) => e.idHex).toSet(),
            reason: 'after a restart and one more share the two phones disagree');
      }
      expect(again.heldCount, 0);
    }

    late Set<String> dadBefore;
    setUp(() {
      dadBefore = <String>{for (final Uint8List s in <Uint8List>[s1, s2]) for (final SyncEvent e in dad.events(hexOf(s))) e.idHex};
    });

    for (final bool real in <bool>[false, true]) {
      test('on ${real ? 'real files (every step inside a write, temp file torn)' : 'the in-memory disk'}', () async {
        bool first = true;
        final int n = await sweepCrashPoints<World>(
          makeDisk: () => real ? DirDisk.make(tear: true) : Future<Disk>.value(MemDisk()),
          build: (Disk d, CrashClock c) => World(d, c, rig),
          run: workload,
          verify: (World w, Oracle o, CrashClock crashed) async {
            final bool dry = first;
            first = false;
            // A restart builds a NEW engine over the same disk; the verify World's engine starts empty and restores.
            await verifySync(w, o, crashed, dry: dry);
            // Dad took mom's events in the check above; put dad back so every run starts from the same dad.
            dad = rig.engine(rig.dad, clock: Clock(t0 + 10 * day));
            for (final SyncEvent e in <SyncEvent>[...dadS1, ...dadS2]) {
              await dad.ingest(<Uint8List>[e.wire], state: rig.state);
            }
            expect(<String>{for (final Uint8List s in <Uint8List>[s1, s2]) for (final SyncEvent e in dad.events(hexOf(s))) e.idHex}, dadBefore);
          },
        );
        expect(n, greaterThan(real ? 15 : 10));
      }, timeout: const Timeout(Duration(minutes: 6)));
    }
  });
}
