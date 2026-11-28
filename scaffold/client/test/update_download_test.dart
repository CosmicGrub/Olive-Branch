// The resumable, chunk-verified download and its safe place on disk, against a fake network that lies in every way a
// network can: drops, truncation, corruption, a mirror that is wrong, a server that ignores Range, a server that says
// too much, an endless stream. Whatever happens, nothing installable is ever left behind unless it is exactly what was
// signed. MASTERFILE 7.24.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/update_download.dart';
import 'package:olive_client/update_manifest.dart';
import 'package:olive_client/update_transport.dart';

import 'update_support.dart';

void main() {
  late TestSigner s;
  late Directory dir;
  late FakeTransport net;
  late Uint8List apkBytes;
  late ApkEntry apk;
  late UpdateStaging staging;
  const int kChunk = 65536;

  Future<ApkEntry> infoFor(Uint8List bytes, {Map<String, Object?> Function(Map<String, Object?>)? tweak}) async {
    Map<String, Object?> d = await draftFor(bytes);
    if (tweak != null) d = tweak(d);
    return (await verifyManifestDocument(encodeDoc(await s.sign(d)), s.trust)).manifest.apks.first;
  }

  UpdateDownloader downloader({int retries = 3}) => UpdateDownloader(
        transport: net,
        staging: staging,
        retriesPerUrl: retries,
        sleep: (Duration d) async {},
      );

  Future<UpdateRefusalCode?> failure(Future<Object?> Function() f) async {
    try {
      await f();
      return null;
    } on UpdateRefusal catch (e) {
      return e.code;
    }
  }

  setUp(() async {
    s = await TestSigner.create();
    dir = await Directory.systemTemp.createTemp('olive_dl_test_');
    staging = UpdateStaging(Directory('${dir.path}${Platform.pathSeparator}u'));
    net = FakeTransport();
    apkBytes = fakeApk(kChunk * 3 + 12345); // four chunks, the last one short
    apk = await infoFor(apkBytes);
    net.files[kPrimary] = FileBehavior(apkBytes);
    net.files[kMirror] = FileBehavior(apkBytes);
  });

  tearDown(() async {
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  test('a clean download is verified chunk by chunk and ends as <sha256>.apk, with no part file left', () async {
    final List<DownloadProgress> seen = <DownloadProgress>[];
    final File f = await downloader().download(apk, onProgress: seen.add);
    expect(f.path.endsWith('${apk.sha256}.apk'), isTrue);
    expect(await f.readAsBytes(), apkBytes);
    expect(staging.dir.listSync().map((FileSystemEntity e) => e.path.split(Platform.pathSeparator).last).toList(), <String>['${apk.sha256}.apk']);
    expect(seen.last.doneBytes, apk.size);
    expect(seen.map((DownloadProgress p) => p.doneBytes), orderedEquals(seen.map((DownloadProgress p) => p.doneBytes).toList()..sort()));
    expect(net.openLog.single.$1, kPrimary, reason: 'the mirror is not touched when the primary works');
  });

  test('a file that is already complete and still right is returned without any request', () async {
    await downloader().download(apk);
    net.openLog.clear();
    final File f = await downloader().download(apk);
    expect(f.existsSync(), isTrue);
    expect(net.openLog, isEmpty);
  });

  group('weak links', () {
    test('a dropped connection resumes from the last verified chunk (a Range request), not from the start', () async {
      net.files[kPrimary] = FileBehavior(apkBytes, dropAfter: kChunk * 2 + 1000);
      final File f = await downloader().download(apk);
      expect(await f.readAsBytes(), apkBytes);
      expect(net.openLog.length, greaterThanOrEqualTo(2));
      expect(net.openLog.first.$2, anyOf(isNull, 0));
      expect(net.openLog[1].$2, kChunk * 2, reason: 'two whole chunks were verified before the drop');
    });

    test('a part file left by a crash is re-checked; its good chunks are kept and the rest is fetched', () async {
      await staging.ensure();
      await staging.partFor(apk).writeAsBytes(apkBytes.sublist(0, kChunk * 2 + 500)); // two chunks and half of a third
      final File f = await downloader().download(apk);
      expect(await f.readAsBytes(), apkBytes);
      expect(net.openLog.first.$2, kChunk * 2);
    });

    test('a part file whose first chunk is damaged is cut back and fetched again from the start', () async {
      await staging.ensure();
      final Uint8List damaged = Uint8List.fromList(apkBytes.sublist(0, kChunk * 2));
      damaged[10] ^= 0xff;
      await staging.partFor(apk).writeAsBytes(damaged);
      final File f = await downloader().download(apk);
      expect(await f.readAsBytes(), apkBytes);
      expect(net.openLog.first.$2, anyOf(isNull, 0));
    });

    test('a server that ignores Range and sends the whole file is tolerated: the bytes we have are skipped', () async {
      net.files[kPrimary] = FileBehavior(apkBytes, honorRange: false, dropAfter: kChunk + 100);
      final File f = await downloader().download(apk);
      expect(await f.readAsBytes(), apkBytes);
    });

    test('a connection that ends early is a drop, never a finished file; after the retries are used up it fails honestly', () async {
      net.files[kPrimary] = FileBehavior(apkBytes.sublist(0, kChunk * 2 + 10));
      net.files.remove(kMirror);
      expect(await failure(() => downloader(retries: 2).download(apk)), anyOf(UpdateRefusalCode.truncated, UpdateRefusalCode.httpError));
      expect(staging.finalFor(apk).existsSync(), isFalse);
      // What was good is kept, ready to continue.
      expect(await staging.partFor(apk).length(), kChunk * 2);
    });
  });

  group('lies and attacks', () {
    test('a corrupt chunk is refused before it is written; the mirror is tried and finishes the job', () async {
      net.files[kPrimary] = FileBehavior(apkBytes, corrupt: kChunk + 7);
      final File f = await downloader().download(apk);
      expect(await f.readAsBytes(), apkBytes);
      expect(net.openLog.map((e) => e.$1), containsAllInOrder(<String>[kPrimary, kMirror]));
      expect(net.openLog.last.$2, kChunk, reason: 'the mirror continues from the first chunk that was not yet good');
    });

    test('every address wrong: a hash mismatch, and nothing installable is left', () async {
      net.files[kPrimary] = FileBehavior(apkBytes, corrupt: 5);
      net.files[kMirror] = FileBehavior(apkBytes, corrupt: 5);
      expect(await failure(() => downloader().download(apk)), UpdateRefusalCode.hashMismatch);
      expect(staging.finalFor(apk).existsSync(), isFalse);
      expect(await staging.partFor(apk).length(), 0);
    });

    test('a MITM on the mirror (a different file of the right size) never passes the chunk check', () async {
      net.files[kPrimary] = FileBehavior(apkBytes.sublist(0, kChunk), dropAfter: 100, dropTimes: 99);
      net.files[kMirror] = FileBehavior(fakeApk(apkBytes.length, 99));
      final UpdateRefusalCode? c = await failure(() => downloader(retries: 1).download(apk));
      expect(c, UpdateRefusalCode.hashMismatch);
      expect(staging.finalFor(apk).existsSync(), isFalse);
    });

    test('chunk hashes right but the whole-file hash wrong (a manifest that contradicts itself): deleted, never kept', () async {
      final ApkEntry bad = await infoFor(apkBytes, tweak: (Map<String, Object?> d) {
        apk0(d)['sha256'] = '0' * 64;
        return d;
      });
      expect(await failure(() => downloader().download(bad)), UpdateRefusalCode.hashMismatch);
      expect(staging.finalFor(bad).existsSync(), isFalse);
      expect(staging.partFor(bad).existsSync(), isFalse);
    });

    test('a server that says it has more than the file is refused up front (a zip-bomb style claim)', () async {
      net.files[kPrimary] = FileBehavior(apkBytes, declaredLength: apkBytes.length * 100);
      net.files[kMirror] = FileBehavior(apkBytes, declaredLength: apkBytes.length * 100);
      expect(await failure(() => downloader().download(apk)), UpdateRefusalCode.tooMuchData);
      expect(staging.finalFor(apk).existsSync(), isFalse);
    });

    test('an endless stream is cut off once the file is complete, and the extra is never read into the file', () async {
      net.files[kPrimary] = FileBehavior(apkBytes, endless: true);
      final File f = await downloader().download(apk);
      expect(await f.length(), apk.size);
      expect(await f.readAsBytes(), apkBytes);
    });

    test('an endless stream of the WRONG bytes is refused chunk by chunk and never grows the disk', () async {
      net.files[kPrimary] = FileBehavior(Uint8List(kChunk * 40), endless: true);
      net.files.remove(kMirror);
      expect(await failure(() => downloader().download(apk)), anyOf(UpdateRefusalCode.hashMismatch, UpdateRefusalCode.httpError));
      expect(await staging.partFor(apk).length(), 0);
    });

    test('a 404 or a refused redirect on one address moves on to the next', () async {
      net.files[kPrimary] = FileBehavior(apkBytes, error: const UpdateRefusal(UpdateRefusalCode.badRedirect, 'to http'));
      final File f = await downloader().download(apk);
      expect(await f.readAsBytes(), apkBytes);
    });

    test('a file that changes on disk after it was verified is not returned as verified', () async {
      final File f = await downloader().download(apk);
      final RandomAccessFile r = await f.open(mode: FileMode.append);
      await r.writeByte(1);
      await r.close();
      expect(await staging.verifiedFile(apk), isNull);
      expect(f.existsSync(), isFalse, reason: 'a changed file is deleted, not trusted');
    });
  });

  group('pauses', () {
    test('a guard that refuses (low battery, no Wi-Fi, no space) pauses between chunks and keeps what is good', () async {
      int calls = 0;
      final UpdateRefusalCode? c = await failure(() => downloader().download(apk, guard: () async {
            if (++calls == 3) throw const UpdateRefusal(UpdateRefusalCode.lowBattery);
          }));
      expect(c, UpdateRefusalCode.lowBattery);
      expect(await staging.partFor(apk).length(), kChunk * 2);
      // ... and carries on from there.
      net.openLog.clear();
      final File f = await downloader().download(apk);
      expect(await f.readAsBytes(), apkBytes);
      expect(net.openLog.first.$2, kChunk * 2);
    });

    test('cancel stops the download and keeps the good chunks', () async {
      final UpdateCancel cancel = UpdateCancel();
      final UpdateRefusalCode? c = await failure(() => downloader().download(apk, cancel: cancel, onProgress: (DownloadProgress p) {
            if (p.doneBytes >= kChunk) cancel.cancel();
          }));
      expect(c, UpdateRefusalCode.cancelled);
      expect(staging.finalFor(apk).existsSync(), isFalse);
    });

    test('a new manifest sweeps the old version\'s files away', () async {
      final Uint8List old = fakeApk(kChunk + 5, 3);
      final ApkEntry oldInfo = await infoFor(old);
      await staging.ensure();
      await staging.partFor(oldInfo).writeAsBytes(old);
      await staging.finalFor(oldInfo).writeAsBytes(old);
      await File('${staging.dir.path}${Platform.pathSeparator}stray.bin').writeAsBytes(<int>[1]);
      await downloader().download(apk);
      expect(staging.dir.listSync().map((FileSystemEntity e) => e.path.split(Platform.pathSeparator).last).toList(), <String>['${apk.sha256}.apk']);
    });
  });

  group('over the family link', () {
    test('a good stream is verified chunk by chunk and kept', () async {
      final File f = await downloader().stageFromStream(apk, Stream<List<int>>.fromIterable(<List<int>>[
        apkBytes.sublist(0, 1000),
        apkBytes.sublist(1000, kChunk * 2 + 17),
        apkBytes.sublist(kChunk * 2 + 17),
      ]));
      expect(await f.readAsBytes(), apkBytes);
    });

    test('a changed byte, a short stream and a long stream are each refused and leave nothing', () async {
      final Uint8List flipped = Uint8List.fromList(apkBytes)..[kChunk + 3] ^= 1;
      expect(await failure(() => downloader().stageFromStream(apk, Stream<List<int>>.value(flipped))), UpdateRefusalCode.hashMismatch);
      expect(await failure(() => downloader().stageFromStream(apk, Stream<List<int>>.value(apkBytes.sublist(0, apkBytes.length - 1)))),
          UpdateRefusalCode.truncated);
      expect(await failure(() => downloader().stageFromStream(apk, Stream<List<int>>.value(Uint8List.fromList(<int>[...apkBytes, 9])))),
          UpdateRefusalCode.tooMuchData);
      expect(staging.dir.listSync(), isEmpty);
    });
  });
}
