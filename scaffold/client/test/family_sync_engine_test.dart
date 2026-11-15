// OLIVE BRANCH — family sync, the engine: what a phone holds, waits on and sends; convergence under shuffled,
// duplicated and partitioned delivery; and every way a hostile or damaged peer is refused. Verified by CI, headless.
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/clear_local_data_screen.dart' show kLocalDataAreaNames;
import 'package:olive_client/family_keys.dart';
import 'package:olive_client/family_ledger.dart';
import 'package:olive_client/family_ledger_state.dart';
import 'package:olive_client/family_sync_engine.dart';
import 'package:olive_client/family_sync_event.dart';
import 'package:olive_client/local_pin.dart' show kLocalGuardianScope;
import 'package:olive_client/local_services.dart';
import 'package:olive_client/local_store.dart';

import 'family_sync_test_support.dart';
import 'family_test_support.dart';

void main() {
  late SyncRig rig;
  late Uint8List sid;
  late Clock clock;

  setUp(() async {
    rig = await SyncRig.make(third: true);
    sid = await syncStreamId(rig.fid, 'emergencycard', 'ivy');
    clock = Clock(t0 + 10 * day);
  });

  Future<SyncAppend> write(SyncEngine e, String text, {LedgerState? state}) =>
      e.append(kind: 'emergency.set', streamId: sid, payload: <String, Object?>{'t': text}, state: state ?? rig.state);

  Future<SyncIngest> send(SyncEngine from, SyncEngine to, {LedgerState? state}) =>
      to.ingest(from.eventsFor(to.summary()).wires, state: state ?? rig.state);

  String shape(SyncEngine e) {
    final String s = hexOf(sid);
    return '${e.events(s).map((SyncEvent x) => x.idHex).join(',')}|${e.heads(s).map((SyncEvent x) => x.idHex).join(',')}';
  }

  group('writing', () {
    test('a first event has no links; the next follows it; counters and the clock only rise, even if the phone\'s clock goes back', () async {
      final SyncEngine m = rig.engine(rig.mom, clock: clock);
      final SyncEvent a = (await write(m, 'a')).event!;
      expect(a.seq, 1);
      expect(a.prev, isEmpty);
      clock.ms -= 5 * day; // the phone's clock jumps backwards
      final SyncEvent b = (await write(m, 'b')).event!;
      expect(b.seq, 2);
      expect(hexOf(b.prev.single), a.idHex);
      expect(b.hlcMs > a.hlcMs || (b.hlcMs == a.hlcMs && b.hlcC > a.hlcC), isTrue);
      expect(m.heads(hexOf(sid)).single.idHex, b.idHex);
      expect(m.events(hexOf(sid)).map((SyncEvent e) => e.idHex), <String>[a.idHex, b.idHex]);
    });

    test('a phone that is not a listed grown-up\'s, or holds no guardian key, or names a kind outside the table, writes nothing', () async {
      expect((await write(rig.engine(rig.kid), 'x')).reason, 'not_member', reason: 'a child tablet is not a grown-up\'s phone');
      expect((await write(rig.engine(rig.mom, ring: childRing()), 'x')).reason, 'no_key');
      expect((await rig.engine(rig.mom).append(kind: 'journal.add', streamId: sid, payload: <String, Object?>{}, state: rig.state)).reason, 'kind');
      final P stranger = await P.make(9);
      expect((await write(rig.engine(stranger), 'x')).reason, 'not_member');
    });

    test('a payload past the size limit is refused, not thrown, and nothing is stored', () async {
      final SyncEngine m = rig.engine(rig.mom, clock: clock);
      final SyncAppend r = await m.append(
          kind: 'emergency.set', streamId: sid, payload: <String, Object?>{'t': 'x' * (kSyncMaxPayloadBytes + 1)}, state: rig.state);
      expect(r.reason, 'too_large');
      expect(m.eventCount, 0);
    });
  });

  group('two phones', () {
    test('what one writes the other receives, in the same order, with the same ends', () async {
      final SyncEngine m = rig.engine(rig.mom, clock: clock), d = rig.engine(rig.dad, clock: clock);
      await write(m, '1');
      await write(m, '2');
      final SyncIngest r = await send(m, d);
      expect(r.added, 2);
      expect(r.refused, 0);
      expect(shape(d), shape(m));
      expect(d.forked(hexOf(sid)), isFalse);
    });

    test('sending the same update twice, or an old one again, changes nothing', () async {
      final SyncEngine m = rig.engine(rig.mom, clock: clock), d = rig.engine(rig.dad, clock: clock);
      await write(m, '1');
      final List<Uint8List> wires = m.eventsFor(null).wires;
      expect((await d.ingest(wires, state: rig.state)).added, 1);
      final SyncIngest again = await d.ingest(wires, state: rig.state);
      expect(again.added, 0);
      expect(again.known, 1);
      expect(d.eventCount, 1);
    });

    test('two grown-ups who write at the same time produce two ends on both phones; neither is chosen; a choice names both and settles it everywhere', () async {
      final SyncEngine m = rig.engine(rig.mom, clock: clock), d = rig.engine(rig.dad, clock: clock);
      await write(m, 'base');
      await send(m, d);
      await write(m, 'mom version');
      clock.ms += 1000;
      await write(d, 'dad version');
      await send(m, d);
      await send(d, m);
      final String s = hexOf(sid);
      expect(m.forked(s), isTrue);
      expect(d.forked(s), isTrue);
      expect(shape(m), shape(d));
      expect(m.heads(s).map((SyncEvent e) => e.payload['t']).toSet(), <String>{'mom version', 'dad version'});
      // Dad resolves, naming both ends.
      final SyncEvent res = (await write(d, 'dad version')).event!;
      expect(res.prev.length, 2);
      expect(d.forked(s), isFalse);
      await send(d, m);
      expect(m.forked(s), isFalse);
      expect(shape(m), shape(d));
      expect(m.heads(s).single.idHex, res.idHex);
    });

    test('nothing is lost when the writes were not concurrent: a later write by the other phone simply follows', () async {
      final SyncEngine m = rig.engine(rig.mom, clock: clock), d = rig.engine(rig.dad, clock: clock);
      await write(m, '1');
      await send(m, d);
      await write(d, '2');
      await send(d, m);
      expect(m.heads(hexOf(sid)).single.payload['t'], '2');
      expect(m.events(hexOf(sid)).length, 2);
    });
  });

  group('convergence', () {
    test('many seeds: random writers, random delivery order, duplicates and drops; every phone that finally receives everything agrees exactly', () async {
      final List<P> people = <P>[rig.mom, rig.dad, rig.sam];
      for (int seed = 1; seed <= 25; seed++) {
        final Random rnd = Random(seed);
        final Clock c = Clock(t0 + 10 * day);
        final List<SyncEngine> phones = <SyncEngine>[for (final P p in people) rig.engine(p, clock: c)];
        // Writes and partial exchanges interleave.
        for (int step = 0; step < 14; step++) {
          c.ms += rnd.nextInt(5000);
          final int w = rnd.nextInt(3);
          final SyncAppend wr = await write(phones[w], 's$seed-$step');
          expect(wr.event, isNotNull, reason: 'writer $w: ${wr.reason}');
          if (rnd.nextInt(3) == 0) {
            final int a = rnd.nextInt(3), b = (a + 1 + rnd.nextInt(2)) % 3;
            final List<Uint8List> wires = phones[a].eventsFor(phones[b].summary()).wires..shuffle(rnd);
            await phones[b].ingest(wires, state: rig.state);
          }
        }
        // A fresh phone receives everything every other phone holds, shuffled and duplicated, in small batches.
        final SyncEngine fresh = rig.engine(rig.dad, clock: c);
        final Map<String, Uint8List> all = <String, Uint8List>{
          for (final SyncEngine p in phones)
            for (final Uint8List w in p.eventsFor(null, maxEvents: 1000, maxBytes: 4 * 1024 * 1024).wires) hexOf(w): w,
        };
        final List<Uint8List> deliver = <Uint8List>[...all.values, ...all.values.take(5)]..shuffle(rnd);
        for (int i = 0; i < deliver.length; i += 3) {
          await fresh.ingest(deliver.sublist(i, min(i + 3, deliver.length)), state: rig.state);
        }
        // Everybody exchanges with everybody until quiet.
        for (int round = 0; round < 3; round++) {
          for (final SyncEngine a in phones) {
            for (final SyncEngine b in phones) {
              if (!identical(a, b)) await send(a, b);
            }
          }
        }
        for (final SyncEngine p in phones) {
          expect(shape(p), shape(fresh), reason: 'seed $seed');
          expect(p.heldCount, 0, reason: 'seed $seed');
        }
        expect(fresh.heldCount, 0, reason: 'seed $seed');
      }
    });
  });

  group('gaps, withholding and order', () {
    test('an event that arrives before the one it follows waits (and is reported as missing), then appears when the gap is filled', () async {
      final SyncEngine m = rig.engine(rig.mom, clock: clock), d = rig.engine(rig.dad, clock: clock);
      final List<SyncEvent> es = <SyncEvent>[(await write(m, '1')).event!, (await write(m, '2')).event!, (await write(m, '3')).event!];
      final SyncIngest r = await d.ingest(<Uint8List>[es[0].wire, es[2].wire], state: rig.state);
      expect(r.added, 1);
      expect(r.held, 1);
      expect(d.heldCount, 1);
      expect(d.events(hexOf(sid)).length, 1);
      expect(d.summary().prefix(hexOf(sid), hexOf(rig.mom.key.publicKey)), 1);
      final SyncIngest r2 = await d.ingest(<Uint8List>[es[1].wire], state: rig.state);
      expect(r2.added, 2, reason: 'the filled gap releases the waiting event too');
      expect(d.heldCount, 0);
      expect(d.events(hexOf(sid)).length, 3);
    });

    test('an event that names another writer\'s event waits until that event arrives', () async {
      final SyncEngine m = rig.engine(rig.mom, clock: clock), d = rig.engine(rig.dad, clock: clock), s = rig.engine(rig.sam, clock: clock);
      final SyncEvent a = (await write(m, 'a')).event!;
      await send(m, d);
      clock.ms += 10;
      final SyncEvent b = (await write(d, 'b')).event!; // follows a
      await send(m, s);
      final SyncIngest r = await s.ingest(<Uint8List>[b.wire], state: rig.state);
      expect(r.added, 1, reason: 'a was already held by sam, so b applies');
      final SyncEngine fresh = rig.engine(rig.sam, clock: clock);
      final SyncIngest r2 = await fresh.ingest(<Uint8List>[b.wire], state: rig.state);
      expect(r2.held, 1);
      expect(fresh.events(hexOf(sid)), isEmpty);
      await fresh.ingest(<Uint8List>[a.wire], state: rig.state);
      expect(fresh.events(hexOf(sid)).length, 2);
    });

    test('a relay that drops one event is noticed (the summary stays short of it) and a later full update repairs it', () async {
      final SyncEngine m = rig.engine(rig.mom, clock: clock), d = rig.engine(rig.dad, clock: clock);
      final List<SyncEvent> es = <SyncEvent>[for (int i = 0; i < 4; i++) (await write(m, 'n$i')).event!];
      await d.ingest(<Uint8List>[es[0].wire, es[2].wire, es[3].wire], state: rig.state);
      expect(d.heldCount, 2);
      expect(d.summary().prefix(hexOf(sid), hexOf(rig.mom.key.publicKey)), 1);
      await send(m, d); // the sender answers the receiver's summary: everything after the gap
      expect(d.heldCount, 0);
      expect(shape(d), shape(m));
    });

    test('an event whose clock is not after the event it follows is refused for good, with whatever waited on it', () async {
      final SyncEngine m = rig.engine(rig.mom, clock: clock), d = rig.engine(rig.dad, clock: clock);
      final SyncEvent a = (await write(m, 'a')).event!;
      final SyncEvent bad = await SyncEvent.create(
        device: rig.mom.key, ring: guardianRing(), epoch: 0, fid: rig.fid, streamId: sid, seq: 2, hlcMs: a.hlcMs - 1000, hlcC: 0,
        prev: <List<int>>[a.id], kind: 'emergency.set', payload: <String, Object?>{'t': 'backdated'},
      );
      final SyncIngest r = await d.ingest(<Uint8List>[a.wire, bad.wire], state: rig.state);
      expect(r.reasons['order'], 1);
      expect(d.events(hexOf(sid)).length, 1);
      expect(d.heldCount, 0);
    });

    test('two different events from one phone with the same counter: the first stays, the second is refused and reported', () async {
      final SyncEngine d = rig.engine(rig.dad, clock: clock);
      Future<SyncEvent> one(String t) => SyncEvent.create(
            device: rig.mom.key, ring: guardianRing(), epoch: 0, fid: rig.fid, streamId: sid, seq: 1, hlcMs: t0 + 10 * day, hlcC: 0,
            prev: const <List<int>>[], kind: 'emergency.set', payload: <String, Object?>{'t': t},
          );
      final SyncEvent x = await one('x'), y = await one('y');
      final SyncIngest r = await d.ingest(<Uint8List>[x.wire, y.wire], state: rig.state);
      expect(r.added, 1);
      expect(r.reasons['equivocation'], 1);
      expect(d.equivocations.single.seq, 1);
      expect(d.events(hexOf(sid)).single.idHex, x.idHex);
    });
  });

  group('who is allowed in, and what is refused', () {
    test('an event from a phone the family record does not list (a stranger, or a grown-up who has left) is refused even though it opens', () async {
      final P stranger = await P.make(9);
      final SyncEngine s = rig.engine(stranger, clock: clock);
      final SyncEvent e = await SyncEvent.create(
        device: stranger.key, ring: guardianRing(), epoch: 0, fid: rig.fid, streamId: sid, seq: 1, hlcMs: t0 + 10 * day, hlcC: 0,
        prev: const <List<int>>[], kind: 'emergency.set', payload: <String, Object?>{'t': 'x'},
      );
      expect(s.eventCount, 0);
      final SyncEngine d = rig.engine(rig.dad, clock: clock);
      final SyncIngest r = await d.ingest(<Uint8List>[e.wire], state: rig.state);
      expect(r.reasons['not_member'], 1);
      expect(d.eventCount, 0);
    });

    test('a child tablet\'s device key is not a grown-up\'s: an event it signed is refused', () async {
      final SyncEvent e = await SyncEvent.create(
        device: rig.kid.key, ring: guardianRing(), epoch: 0, fid: rig.fid, streamId: sid, seq: 1, hlcMs: t0 + 10 * day, hlcC: 0,
        prev: const <List<int>>[], kind: 'emergency.set', payload: <String, Object?>{'t': 'x'},
      );
      final SyncIngest r = await rig.engine(rig.dad, clock: clock).ingest(<Uint8List>[e.wire], state: rig.state);
      expect(r.reasons['not_member'], 1);
    });

    test('a ledger that did not load (no family) lets nothing in', () async {
      final SyncEngine m = rig.engine(rig.mom, clock: clock);
      await write(m, 'a');
      final LedgerState none = await reduceLedger(entries: <LedgerEntry>[], votes: <LedgerVote>[], nowMs: t0);
      expect(none.ok, isFalse);
      final SyncIngest r = await rig.engine(rig.dad, clock: clock).ingest(m.eventsFor(null).wires, state: none);
      expect(r.reasons['not_member'], 1);
    });

    test('an event from another family, one sealed under another key, damaged bytes and a child tablet\'s keyring are each refused and the rest of the batch still lands', () async {
      final SyncEngine m = rig.engine(rig.mom, clock: clock), d = rig.engine(rig.dad, clock: clock);
      final SyncEvent good = (await write(m, 'good')).event!;
      final SyncEvent otherFam = await SyncEvent.create(
        device: rig.mom.key, ring: guardianRing(), epoch: 0, fid: Uint8List(16), streamId: sid, seq: 1, hlcMs: 1, hlcC: 0,
        prev: const <List<int>>[], kind: 'emergency.set', payload: <String, Object?>{},
      );
      final SyncEvent otherKey = await SyncEvent.create(
        device: rig.mom.key, ring: guardianRing(gk: Uint8List(32)), epoch: 0, fid: rig.fid, streamId: sid, seq: 9, hlcMs: 1, hlcC: 0,
        prev: const <List<int>>[], kind: 'emergency.set', payload: <String, Object?>{},
      );
      final Uint8List damaged = Uint8List.fromList(good.wire)..[40] ^= 4;
      final SyncIngest r = await d.ingest(<Uint8List>[otherFam.wire, otherKey.wire, damaged, Uint8List(3), good.wire], state: rig.state);
      expect(r.added, 1);
      expect(r.refused, 4);
      expect(r.reasons.keys.toSet(), <String>{'family', 'seal', 'size'});
      final SyncIngest kid = await rig.engine(rig.kid, ring: childRing()).ingest(<Uint8List>[good.wire], state: rig.state);
      expect(kid.reasons['no_key'], 1);
    });

    test('an event dated more than a day ahead is not taken now, and is taken once this phone\'s clock reaches it', () async {
      final Clock far = Clock(t0 + 10 * day + 3 * day);
      final SyncEngine m = rig.engine(rig.mom, clock: far), d = rig.engine(rig.dad, clock: clock);
      final SyncEvent e = (await write(m, 'future')).event!;
      final SyncIngest r = await d.ingest(<Uint8List>[e.wire], state: rig.state);
      expect(r.reasons['future'], 1);
      expect(d.eventCount, 0);
      clock.ms += 3 * day;
      expect((await d.ingest(<Uint8List>[e.wire], state: rig.state)).added, 1);
    });

    test('a phone that receives a far-future event cannot be dragged forward: its own clock for new writes stays honest', () async {
      final Clock far = Clock(t0 + 10 * day + 30 * day);
      final SyncEngine m = rig.engine(rig.mom, clock: far), d = rig.engine(rig.dad, clock: clock);
      await d.ingest(<Uint8List>[(await write(m, 'x')).event!.wire], state: rig.state);
      final SyncEvent mine = (await write(d, 'mine')).event!;
      expect(mine.hlcMs, clock.ms);
    });
  });

  group('bounds', () {
    test('events waiting for something that never comes are capped, and the cap does not stop other work', () async {
      final SyncEngine m = rig.engine(rig.mom, clock: clock), d = rig.engine(rig.dad, clock: clock);
      final SyncEvent first = (await write(m, 'first')).event!;
      final List<SyncEvent> rest = <SyncEvent>[for (int i = 0; i < kSyncMaxHeld + 5; i++) (await write(m, 'r$i')).event!];
      // Deliver everything except the first: all of it waits.
      final SyncIngest r = await d.ingest(<Uint8List>[for (final SyncEvent e in rest) e.wire], state: rig.state);
      expect(d.heldCount, kSyncMaxHeld);
      expect(r.reasons['held_full'], 5);
      await d.ingest(<Uint8List>[first.wire], state: rig.state);
      expect(d.events(hexOf(sid)).length, kSyncMaxHeld + 1);
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('a save that fails leaves the phone exactly as it was, for a write and for an update', () async {
      final MemorySyncRepository repo = MemorySyncRepository();
      final SyncEngine m = rig.engine(rig.mom, clock: clock, repo: repo);
      final SyncEngine other = rig.engine(rig.dad, clock: clock);
      await write(m, 'kept');
      repo.failSaves = true;
      expect((await write(m, 'lost')).reason, 'full');
      expect(m.eventCount, 1);
      final SyncEvent e = (await write(other, 'theirs')).event!;
      final SyncIngest r = await m.ingest(<Uint8List>[e.wire], state: rig.state);
      expect(r.added, 0);
      expect(m.eventCount, 1);
      repo.failSaves = false;
      expect((await write(m, 'again')).event, isNotNull);
      expect(m.eventCount, 2, reason: 'the failed write left no half-state behind');
    });
  });

  group('what to send a phone that is behind', () {
    test('only what the other phone lacks, causes before effects, bounded, with a flag when there is more', () async {
      final SyncEngine m = rig.engine(rig.mom, clock: clock), d = rig.engine(rig.dad, clock: clock);
      for (int i = 0; i < 6; i++) {
        await write(m, 'n$i');
      }
      await d.ingest(m.eventsFor(null, maxEvents: 2).wires, state: rig.state);
      expect(d.eventCount, 2);
      final ({List<Uint8List> wires, bool more}) part = m.eventsFor(d.summary(), maxEvents: 3);
      expect(part.wires.length, 3);
      expect(part.more, isTrue);
      final ({List<Uint8List> wires, bool more}) rest = m.eventsFor(d.summary());
      expect(rest.wires.length, 4);
      expect(rest.more, isFalse);
      await d.ingest(rest.wires, state: rig.state);
      expect(m.eventsFor(d.summary()).wires, isEmpty);
      expect(m.eventsFor(d.summary(), maxBytes: 1).more, isFalse);
    });

    test('a byte limit that is too small for even one event sends nothing and says there is more', () async {
      final SyncEngine m = rig.engine(rig.mom, clock: clock);
      await write(m, 'a');
      final ({List<Uint8List> wires, bool more}) r = m.eventsFor(null, maxBytes: 10);
      expect(r.wires, isEmpty);
      expect(r.more, isTrue);
    });

    test('a summary can be written and read back, and rejects nonsense', () {
      final SyncSummary s = SyncSummary(<String, Map<String, int>>{
        hexOf(Uint8List(16)): <String, int>{hexOf(Uint8List(32)..[0] = 1): 3},
      });
      final SyncSummary? back = SyncSummary.fromValue(s.toValue());
      expect(back!.prefix(hexOf(Uint8List(16)), hexOf(Uint8List(32)..[0] = 1)), 3);
      expect(SyncSummary.fromValue('x'), isNull);
      expect(SyncSummary.fromValue(<Object?>[<Object?>[Uint8List(3), <Object?>[]]]), isNull);
      expect(SyncSummary.fromValue(<Object?>[<Object?>[Uint8List(16), <Object?>[<Object?>[Uint8List(32), 'x']]]]), isNull);
      expect(SyncSummary.fromJson(<String, Object?>{'a': <String, Object?>{'b': -1}}), isNull);
      expect(SyncSummary.fromJson(s.toJson())!.prefix(hexOf(Uint8List(16)), hexOf(Uint8List(32)..[0] = 1)), 3);
    });

    test('what the other phone last said it held tells us it had an event', () async {
      final SyncEngine m = rig.engine(rig.mom, clock: clock), d = rig.engine(rig.dad, clock: clock);
      final SyncEvent e = (await write(m, 'a')).event!;
      await send(m, d);
      expect(m.peerHad(hexOf(rig.dad.key.publicKey), e), isFalse);
      expect(await m.notePeer(hexOf(rig.dad.key.publicKey), d.summary()), isTrue);
      expect(m.peerHad(hexOf(rig.dad.key.publicKey), e), isTrue);
    });
  });

  group('keeping it across restarts', () {
    test('a restart brings back the same events, ends and summary; a changed byte on disk is dropped, not trusted', () async {
      final MemorySyncRepository repo = MemorySyncRepository();
      final SyncEngine m = rig.engine(rig.mom, clock: clock, repo: repo);
      await write(m, 'a');
      await write(m, 'b');
      await m.notePeer(hexOf(rig.dad.key.publicKey), SyncSummary(<String, Map<String, int>>{}));
      final SyncEngine again = rig.engine(rig.mom, clock: clock, repo: repo);
      await again.restore();
      expect(shape(again), shape(m));
      expect(again.peers.keys, m.peers.keys);
      // A new write after a restart carries on the counters.
      expect((await write(again, 'c')).event!.seq, 3);
      // Damage one stored event.
      final SyncDoc doc = (await repo.load())!;
      doc.wires[0][50] ^= 1;
      await repo.save(doc);
      final SyncEngine hurt = rig.engine(rig.mom, clock: clock, repo: repo);
      await hurt.restore();
      expect(hurt.events(hexOf(sid)), isEmpty, reason: 'the damaged first event is gone, so what followed it waits');
      expect(hurt.heldCount, 2);
    });

    test('a grown-up who has since left the family record keeps what this phone already received', () async {
      final MemorySyncRepository repo = MemorySyncRepository();
      final SyncEngine d = rig.engine(rig.dad, clock: clock, repo: repo);
      final SyncEngine m = rig.engine(rig.mom, clock: clock);
      await write(m, 'old');
      await send(m, d);
      final SyncEngine again = rig.engine(rig.dad, clock: clock, repo: repo);
      await again.restore();
      expect(again.events(hexOf(sid)).length, 1);
    });

    test('forget empties the phone and the store', () async {
      final MemorySyncRepository repo = MemorySyncRepository();
      final SyncEngine m = rig.engine(rig.mom, clock: clock, repo: repo);
      await write(m, 'a');
      await m.forget();
      expect(m.eventCount, 0);
      expect(await repo.load(), isNull);
    });

    test('the sealed on-device store round-trips, is catalogued as sealed grown-up data, and its file shows no readable words', () async {
      final MemoryStoreBackend backend = MemoryStoreBackend();
      final LocalServices svc = LocalServices.memory(childId: 'ivy', backend: backend);
      final LocalDataEntry entry = localDataEntry('familysync');
      expect(entry.encrypted, isTrue);
      expect(entry.scope, LocalScope.guardian);
      expect(kLocalDataAreaNames['familysync'], 'Updates shared between your phones');
      final LocalStoreSyncRepository repo = LocalStoreSyncRepository.forServices(svc);
      final SyncEngine m = rig.engine(rig.mom, clock: clock, repo: repo);
      await m.append(kind: 'emergency.set', streamId: sid, payload: <String, Object?>{'t': 'peanutbutter'}, state: rig.state);
      final Uint8List? disk = await backend.read(svc.namespaceName(entry, ownerId: kLocalGuardianScope));
      expect(disk, isNotNull);
      expect(String.fromCharCodes(disk!).contains('peanutbutter'), isFalse);
      final SyncEngine back = rig.engine(rig.mom, clock: clock, repo: LocalStoreSyncRepository.forServices(svc));
      await back.restore();
      expect(shape(back), shape(m));
      // An unreadable stored document is "nothing stored", not a crash.
      await svc.area('familysync', ownerId: kLocalGuardianScope).put('doc', <String, Object?>{'v': 9});
      final SyncEngine hurt = rig.engine(rig.mom, clock: clock, repo: LocalStoreSyncRepository.forServices(svc));
      await hurt.restore();
      expect(hurt.eventCount, 0);
    });
  });

  group('child safety', () {
    test('only the sync files import the sync engine, so no child-side file can write or read it', () {
      // A source guard: any lib file that mentions the sync engine, event, bundle, emergency adapter or screen must itself
      // be one of the sync files (or the one test-only catalogue entry). Child shells import none of them.
      final RegExp use = RegExp(r"import\s+'(?:package:olive_client/)?family_sync_");
      final List<String> importers = <String>[
        for (final File f in Directory('lib').listSync(recursive: true).whereType<File>())
          if (f.path.endsWith('.dart') && use.hasMatch(f.readAsStringSync())) f.uri.pathSegments.last,
      ];
      expect(importers, isNotEmpty, reason: 'the scan found the sync files');
      for (final String name in importers) {
        expect(name.startsWith('family_sync_'), isTrue, reason: '$name imports the sync layer');
      }
    });

    test('a child device holds no guardian key, so it can neither read nor write any event', () async {
      final SyncEngine m = rig.engine(rig.mom, clock: clock);
      final SyncEvent e = (await write(m, 'a')).event!;
      final FamilyKeyring kid = childRing();
      expect(() => kid.putGk(0, kTestGk), throwsStateError);
      expect((await SyncEvent.open(e.wire, ring: kid, fid: rig.fid)).event, isNull);
      expect((await write(rig.engine(rig.kid, ring: kid), 'x')).event, isNull);
    });
  });
}
