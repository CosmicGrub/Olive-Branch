// OLIVE BRANCH — the phone's side under a hostile or broken tablet: only the paired seat and this session are answered,
// only ranges inside what the phone holds are served, a flood ends the session, and the phone never says why. Headless.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/tablet_update_sender.dart';
import 'package:olive_client/tablet_update_wire.dart';

import 'tablet_update_harness.dart';

Future<void> settle([int ms = 30]) => Future<void>.delayed(Duration(milliseconds: ms));

class PhoneRig {
  PhoneRig(this.t, this.sender, this.fixture);
  final ScriptedTransport t;
  final TabletUpdateSender sender;
  final Fixture fixture;

  static Future<PhoneRig> make({int size = 200 * 1024}) async {
    final Directory dir = await Directory.systemTemp.createTemp('olive_sender_');
    addTearDown(() async {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    });
    final ScriptedTransport t = ScriptedTransport(mySeatId: 'a', peerSeatId: 'b');
    final ReferenceEngine e = ReferenceEngine(dir: dir);
    final Fixture f = await makeFixture(size: size, chunkSize: 64 * 1024);
    final TabletUpdateSender s = TabletUpdateSender(
        transport: t, held: await heldFrom(f, e, dir), grownUpDevice: true, adultPresent: () => true, offerEvery: const Duration(milliseconds: 40));
    await s.start();
    addTearDown(s.stop);
    return PhoneRig(t, s, f);
  }

  List<Map<String, dynamic>> pieces() => <Map<String, dynamic>>[for (final Map<String, dynamic> m in t.sent) if (m['k'] == 'piece') m];

  void need(UpdateObject o, int off, int len, {String? from, String? sid}) =>
      t.inject(NeedMsg(sid ?? sender.sid, obj: o, off: off, len: len).toWire(), from: from);
}

void main() {
  test('it offers the notice by length and hash only, then answers exactly the ranges asked for', () async {
    final PhoneRig r = await PhoneRig.make();
    final Map<String, dynamic> offer = r.t.sent.first;
    expect(offer['k'], 'offer');
    expect(offer.keys.toSet(), <String>{'u', 'k', 'sid', 'dl', 'ds'});
    r.need(UpdateObject.apk, 20000, 40000);
    await settle(80);
    final List<Map<String, dynamic>> got = r.pieces();
    expect(got.map((Map<String, dynamic> m) => m['off']).toList(), <int>[20000, 20000 + 16384, 20000 + 32768]);
    final Uint8List all = Uint8List.fromList(<int>[
      for (final Map<String, dynamic> m in got) ...decodeUpdateMsg(m)! is PieceMsg ? (decodeUpdateMsg(m)! as PieceMsg).data : <int>[]
    ]);
    expect(all, r.fixture.apk.sublist(20000, 60000));
  });

  test('it keeps offering while it waits (a tablet that opens later still finds it) and stops once asked', () async {
    final PhoneRig r = await PhoneRig.make();
    await settle(200);
    expect(r.t.sent.where((Map<String, dynamic> m) => m['k'] == 'offer').length, greaterThanOrEqualTo(3));
    final int before = r.t.sent.length;
    r.need(UpdateObject.doc, 0, 100);
    await settle(150);
    final int offersAfter = r.t.sent.skip(before).where((Map<String, dynamic> m) => m['k'] == 'offer').length;
    expect(offersAfter, 0, reason: 'a session that has started is not re-offered at');
  });

  test('a message from any seat but the paired tablet, or for any session but this one, is not answered', () async {
    final PhoneRig r = await PhoneRig.make();
    final int before = r.pieces().length;
    r.need(UpdateObject.apk, 0, 1000, from: 'zzz');
    r.need(UpdateObject.apk, 0, 1000, sid: newSessionId(List<int>.filled(16, 77)));
    await settle(100);
    expect(r.pieces().length, before);
  });

  test('a range outside the file, or past its end, is not served, and nothing is said about why', () async {
    final PhoneRig r = await PhoneRig.make(size: 100 * 1024);
    final int sentBefore = r.t.sent.length;
    r.need(UpdateObject.apk, 100 * 1024, 100); // starts at the end
    r.need(UpdateObject.apk, 100 * 1024 - 10, 100); // runs past the end
    r.need(UpdateObject.doc, r.fixture.document.length, 1);
    await settle(100);
    expect(r.pieces(), isEmpty);
    expect(r.t.sent.skip(sentBefore).where((Map<String, dynamic> m) => m['k'] != 'offer'), isEmpty);
  });

  test('a window longer than allowed never even decodes (it is dropped before the phone reads a byte)', () async {
    final PhoneRig r = await PhoneRig.make();
    r.t.inject(<String, Object?>{'u': 1, 'k': 'need', 'sid': r.sender.sid, 'o': 'apk', 'off': 0, 'len': 100 * 1024 * 1024});
    await settle(100);
    expect(r.pieces(), isEmpty);
  });

  test('a tablet never sends an offer or a piece to a phone: those count against it', () async {
    final PhoneRig r = await PhoneRig.make();
    for (int i = 0; i < kSenderBadBudget + 3; i++) {
      r.t.inject(OfferMsg(r.sender.sid, docLen: 10, docSha: 'a' * 64).toWire());
    }
    await settle(100);
    expect(r.sender.phase, SenderPhase.stopped);
    expect(r.t.sent.last['k'], 'end');
    expect(r.t.sent.last['why'], 'stop', reason: 'only "stop": no reason crosses the wire');
  });

  test('"done" from the tablet is a calm finish; "refused" says only that, with no detail', () async {
    for (final EndWhy why in <EndWhy>[EndWhy.done, EndWhy.refused, EndWhy.stop]) {
      final PhoneRig r = await PhoneRig.make();
      r.t.inject(EndMsg(r.sender.sid, why).toWire());
      await settle(40);
      expect(r.sender.phase, switch (why) {
        EndWhy.done => SenderPhase.delivered,
        EndWhy.refused => SenderPhase.refused,
        EndWhy.stop => SenderPhase.stopped,
      });
    }
  });

  test('after it has finished it answers nothing, and the file is let go', () async {
    final PhoneRig r = await PhoneRig.make();
    r.t.inject(EndMsg(r.sender.sid, EndWhy.done).toWire());
    await settle(40);
    final int n = r.t.sent.length;
    r.need(UpdateObject.apk, 0, 5000);
    await settle(80);
    expect(r.t.sent.length, n);
  });

  test('a link that goes down mid-answer stops the answer; the tablet asks again', () async {
    final PhoneRig r = await PhoneRig.make();
    r.t.accept = false;
    r.need(UpdateObject.apk, 0, 50000);
    await settle(80);
    expect(r.pieces(), isEmpty);
    r.t.accept = true;
    r.need(UpdateObject.apk, 0, 50000);
    await settle(120);
    expect(r.pieces(), isNotEmpty);
  });
}
