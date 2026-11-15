// OLIVE BRANCH — family sync, the hand-carried update: copy on one phone, paste on the other; and every way damaged
// or hostile pasted text is refused. Verified by CI, headless.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/device_keys.dart';
import 'package:olive_client/family_ledger.dart';
import 'package:olive_client/family_sync_bundle.dart';
import 'package:olive_client/family_sync_engine.dart';
import 'package:olive_client/family_sync_event.dart';

import 'family_sync_event_test.dart' show containsBytes;
import 'family_sync_test_support.dart';
import 'family_test_support.dart';

void main() {
  late SyncRig rig;
  late Uint8List sid;
  late Clock clock;
  late SyncEngine m, d;

  setUp(() async {
    rig = await SyncRig.make();
    sid = await syncStreamId(rig.fid, 'emergencycard', 'ivy');
    clock = Clock(t0 + 10 * day);
    m = rig.engine(rig.mom, clock: clock);
    d = rig.engine(rig.dad, clock: clock);
  });

  Future<SyncAppend> write(SyncEngine e, String text) =>
      e.append(kind: 'emergency.set', streamId: sid, payload: <String, Object?>{'t': text}, state: rig.state);

  group('copy and paste', () {
    test('an update copied on one phone and pasted on the other brings the events across', () async {
      await write(m, 'one');
      await write(m, 'two');
      final SyncBundleOut out = await exportBundle(m);
      expect(out.count, 2);
      expect(out.more, isFalse);
      expect(out.text.startsWith(kBundlePrefix), isTrue);
      final SyncBundleIn r = await importBundle(d, out.text, state: rig.state);
      expect(r.reason, isNull);
      expect(r.ingest!.added, 2);
      expect(r.fromHex, hexOf(rig.mom.key.publicKey));
      expect(d.heads(hexOf(sid)).single.payload['t'], 'two');
    });

    test('line breaks and spaces added by a messenger do not matter', () async {
      await write(m, 'one');
      final String text = (await exportBundle(m)).text;
      final String wrapped = <String>[for (int i = 0; i < text.length; i += 40) text.substring(i, i + 40 > text.length ? text.length : i + 40)].join('\r\n  ');
      expect((await importBundle(d, '  $wrapped \n', state: rig.state)).ingest!.added, 1);
    });

    test('after hearing from the other phone, the next update carries only what it lacks, and says nothing when there is nothing', () async {
      await write(m, 'one');
      await importBundle(d, (await exportBundle(m)).text, state: rig.state);
      await write(d, 'two');
      final SyncBundleIn back = await importBundle(m, (await exportBundle(d)).text, state: rig.state);
      expect(back.ingest!.added, 1);
      // Mom now knows what dad holds: nothing new for him.
      final SyncBundleOut none = await exportBundle(m);
      expect(none.text, isEmpty);
      expect(none.count, 0);
      await write(m, 'three');
      final SyncBundleOut one = await exportBundle(m);
      expect(one.count, 1, reason: 'only the new event, not the whole history');
    });

    test('pasting the same update again changes nothing', () async {
      await write(m, 'one');
      final String text = (await exportBundle(m)).text;
      await importBundle(d, text, state: rig.state);
      final SyncBundleIn again = await importBundle(d, text, state: rig.state);
      expect(again.ingest!.added, 0);
      expect(again.ingest!.known, 1);
      expect(d.eventCount, 1);
    });
  });

  group('what an observer of the text sees', () {
    test('the text names nothing: not the family, the writers, the stream, the kind or the words', () async {
      await write(m, 'peanutbutter');
      final String text = (await exportBundle(m)).text;
      final Uint8List raw = unb64(text.substring(kBundlePrefix.length));
      for (final List<int> secret in <List<int>>[
        rig.fid, rig.mom.key.publicKey, sid, utf8.encode('emergency.set'), utf8.encode('peanutbutter'), utf8.encode('emergencycard'),
      ]) {
        expect(containsBytes(raw, secret), isFalse);
      }
      expect(text.contains('peanut'), isFalse);
    });

    test('a child device cannot make or read one', () async {
      await write(m, 'one');
      final String text = (await exportBundle(m)).text;
      final SyncEngine kid = rig.engine(rig.kid, ring: childRing());
      expect((await exportBundle(kid)).text, isEmpty);
      expect((await importBundle(kid, text, state: rig.state)).reason, 'no_key');
    });
  });

  group('hostile and damaged text', () {
    test('text that is not an update, empty text, and text that is too long are refused without changing anything', () async {
      for (final String t in <String>['', 'hello', 'OLIVE-UPDATE-1.', 'OLIVE-UPDATE-1.%%%%', 'x' * 50]) {
        final SyncBundleIn r = await importBundle(d, t, state: rig.state);
        expect(r.ingest, isNull, reason: t);
        expect(r.reason, isNotNull);
      }
      expect((await importBundle(d, kBundlePrefix + 'A' * (kBundleMaxTextChars + 1), state: rig.state)).reason, 'size');
      expect(d.eventCount, 0);
    });

    test('a flipped character anywhere in an update is refused', () async {
      await write(m, 'one');
      final String text = (await exportBundle(m)).text;
      for (int i = kBundlePrefix.length; i < text.length; i += 37) {
        final String bad = text.substring(0, i) + (text[i] == 'A' ? 'B' : 'A') + text.substring(i + 1);
        final SyncBundleIn r = await importBundle(d, bad, state: rig.state);
        expect(r.ingest, isNull, reason: 'char $i');
      }
      expect(d.eventCount, 0);
    });

    test('a truncated update is refused', () async {
      await write(m, 'one');
      final String text = (await exportBundle(m)).text;
      expect((await importBundle(d, text.substring(0, text.length ~/ 2), state: rig.state)).ingest, isNull);
      expect((await importBundle(d, text.substring(0, kBundlePrefix.length + 5), state: rig.state)).ingest, isNull);
    });

    test('an update sealed under another family\'s key is refused', () async {
      final SyncEngine stranger = SyncEngine(
          fid: rig.fid, device: rig.mom.key, ring: guardianRing(gk: Uint8List(32)..[0] = 1), nowMs: () => clock.ms);
      await stranger.append(kind: 'emergency.set', streamId: sid, payload: <String, Object?>{'t': 'x'}, state: rig.state);
      final String text = (await exportBundle(stranger)).text;
      expect((await importBundle(d, text, state: rig.state)).reason, 'seal');
    });

    test('an update from a phone the family record does not list is read, but its events are refused and it is not remembered as a peer', () async {
      final P stranger = await P.make(9);
      final SyncEngine s = rig.engine(stranger, clock: clock);
      // The stranger holds the guardian key (a removed grown-up would) but is not in the record: it cannot even write.
      expect((await write(s, 'x')).reason, 'not_member');
      // It can still hand-build an update from an event it signed itself (here: loaded straight into its own store).
      final SyncEvent e = await SyncEvent.create(
        device: stranger.key, ring: guardianRing(), epoch: 0, fid: rig.fid, streamId: sid, seq: 1, hlcMs: clock.ms, hlcC: 0,
        prev: const <List<int>>[], kind: 'emergency.set', payload: <String, Object?>{'t': 'x'},
      );
      final MemorySyncRepository repo = MemorySyncRepository();
      await repo.save(SyncDoc(wires: <Uint8List>[e.wire], peers: <String, SyncSummary>{}));
      final SyncEngine feeder = SyncEngine(fid: rig.fid, device: stranger.key, ring: guardianRing(), nowMs: () => clock.ms, repo: repo);
      await feeder.restore();
      expect(feeder.eventCount, 1);
      final SyncBundleIn r = await importBundle(d, (await exportBundle(feeder, force: true)).text, state: rig.state);
      expect(r.ingest!.added, 0);
      expect(r.ingest!.reasons['not_member'], 1);
      expect(r.fromHex, isNull);
      expect(d.peers, isEmpty);
    });

    test('an update with events that do not belong (a damaged one in the middle) still lands the good ones', () async {
      await write(m, 'a');
      await write(m, 'b');
      final List<Uint8List> wires = m.eventsFor(null).wires;
      final Uint8List broken = Uint8List.fromList(wires[0])..[60] ^= 1;
      // Rebuild an update by hand with one broken event and one good one.
      final SyncEngine relay = rig.engine(rig.mom, clock: clock);
      await relay.ingest(wires, state: rig.state);
      final SyncIngest r = await d.ingest(<Uint8List>[broken, wires[0], wires[1]], state: rig.state);
      expect(r.added, 2);
      expect(r.refused, 1);
    });

    test('a pasted update never throws, whatever it holds', () async {
      for (final String t in <String>[
        kBundlePrefix + base64Url.encode(List<int>.generate(300, (int i) => i & 255)),
        kBundlePrefix + base64Url.encode(<int>[]),
        '$kBundlePrefix====',
        '\u0000\u0001',
      ]) {
        final SyncBundleIn r = await importBundle(d, t, state: rig.state);
        expect(r.ingest, isNull);
      }
    });
  });
}
