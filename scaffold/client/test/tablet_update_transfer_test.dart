// OLIVE BRANCH — the tablet update transfer, over the in-memory transport twin: the happy path, awkward sizes, a lost
// link and resume, a restarted app resuming from the partial file, and the phone refusing to start. Headless.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/play_loopback.dart';
import 'package:olive_client/tablet_update_hash.dart';
import 'package:olive_client/tablet_update_port.dart';
import 'package:olive_client/tablet_update_receiver.dart';
import 'package:olive_client/tablet_update_sender.dart';
import 'package:olive_client/tablet_update_store.dart';

import 'tablet_update_harness.dart';

Future<void> waitFor(bool Function() cond, {String what = 'condition', Duration timeout = const Duration(seconds: 20)}) async {
  final Stopwatch sw = Stopwatch()..start();
  while (!cond()) {
    if (sw.elapsed > timeout) throw StateError('timed out waiting for $what');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

class Rig {
  Rig._(this.phoneDir, this.tabletDir, this.phoneEngine, this.tabletEngine, this.phoneT, this.tabletT, this.store);
  final Directory phoneDir, tabletDir;
  final ReferenceEngine phoneEngine, tabletEngine;
  final LoopbackPlayTransport phoneT, tabletT;
  final MemoryStagedUpdateStore store;
  bool adult = true;
  TabletUpdateSender? sender;
  late TabletUpdateReceiver receiver;

  static Future<Rig> make({int tabletVersion = 5100}) async {
    final Directory root = await Directory.systemTemp.createTemp('olive_tablet_update_');
    addTearDown(() async {
      try {
        await root.delete(recursive: true);
      } catch (_) {}
    });
    final Directory pd = await Directory('${root.path}/phone').create();
    final Directory td = await Directory('${root.path}/tablet').create();
    final (LoopbackPlayTransport a, LoopbackPlayTransport b) = LoopbackPlayTransport.pair(seatA: 'a', seatB: 'b');
    final Rig r = Rig._(pd, td, ReferenceEngine(dir: pd, installedVersionCode: 5100), ReferenceEngine(dir: td, installedVersionCode: tabletVersion), a, b,
        MemoryStagedUpdateStore());
    r.receiver = r.newReceiver();
    return r;
  }

  TabletUpdateReceiver newReceiver({Duration timeout = const Duration(milliseconds: 400)}) =>
      TabletUpdateReceiver(engine: tabletEngine, store: store, adultPresent: () => adult, pieceTimeout: timeout, maxRetries: 3);

  Future<TabletUpdateSender> startSender(Fixture f, {bool grownUp = true}) async {
    final HeldUpdate h = await heldFrom(f, phoneEngine, phoneDir);
    final TabletUpdateSender s = TabletUpdateSender(
        transport: phoneT, held: h, grownUpDevice: grownUp, adultPresent: () => true, offerEvery: const Duration(milliseconds: 50));
    sender = s;
    await s.start();
    return s;
  }
}

void main() {
  test('the whole path: offer, notice checked, accepted, file arrives chunk by chunk, staged, phone told done', () async {
    final Rig r = await Rig.make();
    final Fixture f = await makeFixture(size: 200 * 1024 + 123, chunkSize: 64 * 1024);
    await r.receiver.listen(r.tabletT);
    final TabletUpdateSender s = await r.startSender(f);
    await waitFor(() => r.receiver.phase == ReceivePhase.offered, what: 'offered');
    expect(r.receiver.offered!.versionName, '0.52.0');
    expect(r.receiver.offered!.notes, isNotEmpty);
    expect(r.tabletEngine.verifyCalls, 1);
    // Nothing of the file has been asked for until a grown-up says so.
    expect(s.sentApkBytes, 0);
    await r.receiver.accept();
    await waitFor(() => r.receiver.phase == ReceivePhase.ready, what: 'ready');
    final StagedUpdate? st = await r.store.loadStaged();
    expect(st, isNotNull);
    expect(st!.stage, StageState.ready);
    expect(st.versionCode, 5200);
    final File staged = File('${r.tabletDir.path}/${st.fileName}');
    expect(await staged.readAsBytes(), f.apk);
    expect(Directory(r.tabletDir.path).listSync().whereType<File>().where((File x) => x.path.endsWith('.part')), isEmpty,
        reason: 'no partial file is left beside the staged one');
    await waitFor(() => s.phase == SenderPhase.delivered, what: 'phone told done');
    expect(r.receiver.doneBytes, f.apk.length);
  });

  test('chunk sizes that are not a multiple of the piece size, and a size that is not a multiple of the chunk', () async {
    for (final (int size, int chunk) in <(int, int)>[(70001, 20000), (16384, 16384), (16385, 16384), (131072 * 2 + 1, 131072), (50000, 16384 * 3)]) {
      final Rig r = await Rig.make();
      final Fixture f = await makeFixture(size: size, chunkSize: chunk);
      await r.receiver.listen(r.tabletT);
      await r.startSender(f);
      await waitFor(() => r.receiver.phase == ReceivePhase.offered, what: 'offered $size/$chunk');
      await r.receiver.accept();
      await waitFor(() => r.receiver.phase == ReceivePhase.ready, what: 'ready $size/$chunk');
      final StagedUpdate st = (await r.store.loadStaged())!;
      expect(await File('${r.tabletDir.path}/${st.fileName}').readAsBytes(), f.apk, reason: '$size/$chunk');
    }
  });

  test('a lost link mid-transfer pauses calmly and the transfer resumes from the last byte when the link returns', () async {
    final Rig r = await Rig.make();
    final Fixture f = await makeFixture(size: 600 * 1024, chunkSize: 64 * 1024);
    await r.receiver.listen(r.tabletT);
    await r.startSender(f);
    await waitFor(() => r.receiver.phase == ReceivePhase.offered, what: 'offered');
    r.phoneT.hold = true;
    await r.receiver.accept();
    // The network eats the rest of the window, then the link goes away.
    r.phoneT.hold = false;
    r.phoneT.dropNext = 1000;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    r.phoneT.setLinked(false);
    await waitFor(() => r.receiver.phase == ReceivePhase.paused, what: 'paused');
    expect(r.receiver.refusal, isNull, reason: 'a lost link is not a refusal');
    r.phoneT.dropNext = 0;
    r.phoneT.setLinked(true);
    await waitFor(() => r.receiver.phase == ReceivePhase.ready, what: 'resumed and ready');
    final StagedUpdate st = (await r.store.loadStaged())!;
    expect(await File('${r.tabletDir.path}/${st.fileName}').readAsBytes(), f.apk);
  });

  test('messages lost in transit are asked for again after a pause, never skipped over', () async {
    final Rig r = await Rig.make();
    final Fixture f = await makeFixture(size: 300 * 1024, chunkSize: 64 * 1024);
    await r.receiver.listen(r.tabletT);
    await r.startSender(f);
    await waitFor(() => r.receiver.phase == ReceivePhase.offered, what: 'offered');
    r.phoneT.dropNext = 3;
    await r.receiver.accept();
    await waitFor(() => r.receiver.phase == ReceivePhase.ready, what: 'ready after loss');
    final StagedUpdate st = (await r.store.loadStaged())!;
    expect(await File('${r.tabletDir.path}/${st.fileName}').readAsBytes(), f.apk);
  });

  test('duplicated and out-of-order pieces change nothing', () async {
    final Rig r = await Rig.make();
    final Fixture f = await makeFixture(size: 300 * 1024, chunkSize: 64 * 1024);
    await r.receiver.listen(r.tabletT);
    await r.startSender(f);
    await waitFor(() => r.receiver.phase == ReceivePhase.offered, what: 'offered');
    r.phoneT.duplicateNext = 5;
    await r.receiver.accept();
    await waitFor(() => r.receiver.phase == ReceivePhase.ready, what: 'ready');
    final StagedUpdate st = (await r.store.loadStaged())!;
    expect(await File('${r.tabletDir.path}/${st.fileName}').readAsBytes(), f.apk);
  });

  test('an interrupted transfer in a RESTARTED app resumes from the verified chunks left on disk', () async {
    final Rig r = await Rig.make();
    final Fixture f = await makeFixture(size: 400 * 1024, chunkSize: 64 * 1024);
    await r.receiver.listen(r.tabletT);
    await r.startSender(f);
    await waitFor(() => r.receiver.phase == ReceivePhase.offered, what: 'offered');
    await r.receiver.accept();
    await waitFor(() => r.receiver.doneBytes >= 150 * 1024, what: 'some bytes');
    // The app is killed here: nothing is told, the receiver and the sender simply vanish.
    r.phoneT.setLinked(false);
    r.receiver.dispose();
    await r.sender!.stop();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final List<File> parts = Directory(r.tabletDir.path).listSync().whereType<File>().where((File x) => x.path.endsWith('.part')).toList();
    expect(parts, hasLength(1));
    final int onDisk = await parts.single.length();
    expect(onDisk, greaterThanOrEqualTo(64 * 1024));
    // A brand new app process: a new receiver, a new session on the phone.
    r.phoneT.setLinked(true);
    r.receiver = r.newReceiver();
    await r.receiver.listen(r.tabletT);
    await r.startSender(f);
    await waitFor(() => r.receiver.phase == ReceivePhase.offered, what: 'offered again');
    await r.receiver.accept();
    // It did not start from zero: it kept the verified chunks (a whole number of them) from the first attempt.
    expect(r.receiver.doneBytes, greaterThanOrEqualTo(64 * 1024));
    expect(r.receiver.doneBytes % (64 * 1024), 0);
    expect(r.receiver.doneBytes, lessThanOrEqualTo(onDisk));
    await waitFor(() => r.receiver.phase == ReceivePhase.ready, what: 'ready');
    final StagedUpdate st = (await r.store.loadStaged())!;
    expect(await File('${r.tabletDir.path}/${st.fileName}').readAsBytes(), f.apk);
  });

  test('a leftover partial file keeps only its verified chunks: a half-written or corrupted tail is thrown away', () async {
    for (final bool corruptFirst in <bool>[false, true]) {
      final Rig r = await Rig.make();
      final Fixture f = await makeFixture(size: 200 * 1024, chunkSize: 64 * 1024);
      final String sha16 = (await sha256HexOf(f.document)).substring(0, 16);
      final BytesBuilder left = BytesBuilder()
        ..add(corruptFirst ? Uint8List(64 * 1024) : f.apk.sublist(0, 64 * 1024))
        ..add(Uint8List(30000)..fillRange(0, 30000, 9));
      await File('${r.tabletDir.path}/u$sha16.part').writeAsBytes(left.toBytes());
      await r.receiver.listen(r.tabletT);
      await r.startSender(f);
      await waitFor(() => r.receiver.phase == ReceivePhase.offered, what: 'offered');
      await r.receiver.accept();
      expect(r.receiver.doneBytes, corruptFirst ? 0 : 64 * 1024, reason: 'only a verified whole chunk is kept');
      await waitFor(() => r.receiver.phase == ReceivePhase.ready, what: 'ready');
      final StagedUpdate st = (await r.store.loadStaged())!;
      expect(await File('${r.tabletDir.path}/${st.fileName}').readAsBytes(), f.apk);
    }
  });

  test('the phone refuses to start unless it is a grown-up phone with a grown-up proved just now', () async {
    final Rig r = await Rig.make();
    final Fixture f = await makeFixture();
    final HeldUpdate h = await heldFrom(f, r.phoneEngine, r.phoneDir);
    final TabletUpdateSender childSide =
        TabletUpdateSender(transport: r.phoneT, held: h, grownUpDevice: false, adultPresent: () => true);
    await expectLater(childSide.start(), throwsA(isA<TabletUpdateRefused>().having((TabletUpdateRefused e) => e.code, 'code', TabletUpdateCode.notAllowed)));
    final TabletUpdateSender noProof =
        TabletUpdateSender(transport: r.phoneT, held: h, grownUpDevice: true, adultPresent: () => false);
    await expectLater(noProof.start(), throwsA(isA<TabletUpdateRefused>().having((TabletUpdateRefused e) => e.code, 'code', TabletUpdateCode.notAllowed)));
    expect(r.phoneT.sent, isEmpty, reason: 'nothing at all was put on the wire');
  });

  test('the phone refuses to offer a file whose size is not the size its signed notice says', () async {
    final Rig r = await Rig.make();
    final Fixture f = await makeFixture(size: 100 * 1024);
    final HeldUpdate h = await heldFrom(f, r.phoneEngine, r.phoneDir);
    await h.apk.writeAsBytes(f.apk.sublist(0, f.apk.length - 1));
    final TabletUpdateSender s = TabletUpdateSender(transport: r.phoneT, held: h, grownUpDevice: true, adultPresent: () => true);
    await expectLater(s.start(), throwsA(isA<TabletUpdateRefused>().having((TabletUpdateRefused e) => e.code, 'code', TabletUpdateCode.changedOnDisk)));
  });

  test('a tablet with no update machinery, or with no grown-up, does not listen at all', () async {
    final Rig r = await Rig.make();
    r.tabletEngine.hasKey = false;
    await expectLater(r.receiver.listen(r.tabletT), throwsA(isA<TabletUpdateRefused>().having((TabletUpdateRefused e) => e.code, 'code', TabletUpdateCode.noEngine)));
    r.tabletEngine.hasKey = true;
    r.adult = false;
    await expectLater(r.receiver.listen(r.tabletT), throwsA(isA<TabletUpdateRefused>().having((TabletUpdateRefused e) => e.code, 'code', TabletUpdateCode.notAllowed)));
    expect(r.receiver.phase, ReceivePhase.idle);
  });
}
