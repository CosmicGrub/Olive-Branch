// OLIVE BRANCH — send_back_outbox.dart tests. MASTERFILE section 7.19, 5.22.
// The recordings she sends back are kept on the device and sent by a queue that outlives any screen.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:olive_client/api_client.dart';
import 'package:olive_client/child_receive.dart';
import 'package:olive_client/local_services.dart';
import 'package:olive_client/offline_outbox.dart';
import 'package:olive_client/send_back_outbox.dart';

import 'send_back_fakes.dart';

XFile _clip([List<int> bytes = const <int>[1, 2, 3, 4]]) => XFile.fromData(Uint8List.fromList(bytes), name: 'clip.mp4');

class _Server {
  final List<String> calls = <String>[];
  Object? uploadFails;
  Object? sendFails;
  SendBackTransport get transport => SendBackTransport(
        upload: (List<int> bytes) async {
          calls.add('upload:${bytes.length}');
          if (uploadFails != null) throw uploadFails!;
          return 'children/c/messages/key-${calls.length}';
        },
        send: (String key, int ms) async {
          calls.add('send:$key:$ms');
          if (sendFails != null) throw sendFails!;
        },
      );
}

void main() {
  late FakeOutboxDisk disk;
  late FakeRecordings files;
  late FakeClock clock;
  late _Server server;
  late SendBackQueue queue;

  setUp(() {
    disk = FakeOutboxDisk();
    files = FakeRecordings();
    clock = FakeClock(DateTime.utc(2026, 11, 21, 9));
    server = _Server();
    queue = queueOver(disk, files, clock);
  });

  group('keep — the durable write', () {
    test('copies the recording and writes a row with localPath and durationMs, nothing else yet', () async {
      final OutboxItem item = await queue.keep(_clip(), 4200);
      expect(item.kind, OutboxKind.message);
      expect(files.files.keys, <String>['/app/outbox/${item.id}.mp4']);
      expect(files.files.values.single, <int>[1, 2, 3, 4]);
      expect(disk.rows, hasLength(1));
      final Map<String, Object?> row = disk.rows.single! as Map<String, Object?>;
      expect(row['payload'], <String, Object?>{'localPath': '/app/outbox/${item.id}.mp4', 'durationMs': 4200});
      expect((row['payload']! as Map).containsKey('uploadedStorageKey'), isFalse);
    });

    test('the bytes are never written into the JSON store', () async {
      await queue.keep(_clip(List<int>.filled(5000, 7)), 1);
      expect(disk.rows.toString().length, lessThan(600));
    });

    test('a copy that fails leaves no row and throws, so nothing is promised', () async {
      files.failKeep = true;
      await expectLater(queue.keep(_clip(), 1), throwsA(isA<SendBackNotKept>()));
      expect(disk.rows, isEmpty);
    });

    test('a row that cannot be written removes the copy again and throws', () async {
      disk.failSave = true;
      await expectLater(queue.keep(_clip(), 1), throwsA(isA<SendBackNotKept>()));
      expect(files.files, isEmpty);
    });

  });

  group('drain', () {
    test('upload, then send; the row and the copy are gone afterwards, and the row carried the key meanwhile',
        () async {
      final OutboxItem item = await queue.keep(_clip(), 900);
      await queue.drain(server.transport);
      expect(server.calls, <String>['upload:4', 'send:children/c/messages/key-1:900']);
      expect(disk.rows, isEmpty);
      expect(files.files, isEmpty);
      expect((await queue.report(item.id)).status, SendBackStatus.sent);
    });

    test('a connectivity failure keeps the recording, counts one attempt and stores when it failed', () async {
      final OutboxItem item = await queue.keep(_clip(), 900);
      server.uploadFails = const SocketException('unreachable');
      await queue.drain(server.transport);
      final OutboxItem stored = (await disk.load()).single;
      expect(stored.attempts, 1);
      expect(stored.lastFailedAt, clock.t);
      expect(files.files, hasLength(1));
      final SendBackReport r = await queue.report(item.id);
      expect(r.status, SendBackStatus.waiting);
      expect(r.attempts, 1);
    });

    test('an upload that worked is not repeated when only the send failed: the key is stored with the row', () async {
      await queue.keep(_clip(), 900);
      server.sendFails = const SocketException('unreachable');
      await queue.drain(server.transport);
      expect(server.calls, <String>['upload:4', 'send:children/c/messages/key-1:900']);
      final Map<Object?, Object?> payload = (await disk.load()).single.payload! as Map<Object?, Object?>;
      expect(payload['uploadedStorageKey'], 'children/c/messages/key-1');
      expect(payload['localPath'], isA<String>());

      clock.advance(const Duration(minutes: 3));
      server.sendFails = null;
      server.calls.clear();
      await queue.drain(server.transport);
      expect(server.calls, <String>['send:children/c/messages/key-1:900'], reason: 'no second upload');
      expect(disk.rows, isEmpty);
    });

    test('a queue rebuilt over the same store makes no send inside the backoff window and spends no attempt',
        () async {
      await queue.keep(_clip(), 900);
      server.uploadFails = const SocketException('unreachable');
      await queue.drain(server.transport);
      server.calls.clear();

      // Cold start 30 seconds later: new queue, same rows, same copy.
      clock.advance(const Duration(seconds: 30));
      final SendBackQueue cold = queueOver(disk, files, clock);
      server.uploadFails = null;
      await cold.drain(server.transport);
      expect(server.calls, isEmpty);
      expect((await disk.load()).single.attempts, 1);

      // Past backoffMs(1) it goes.
      clock.advance(Duration(milliseconds: backoffMs(1)));
      await cold.drain(server.transport);
      expect(server.calls, hasLength(2));
      expect(disk.rows, isEmpty);
    });

    test('rows stored before lastFailedAt existed are due at once', () async {
      final OutboxItem item = await queue.keep(_clip(), 900);
      disk.rows = <Object?>[
        <String, Object?>{
          ...(disk.rows.single! as Map<String, Object?>),
          'attempts': 3,
        },
      ];
      expect((await disk.load()).single.lastFailedAt, isNull);
      await queue.drain(server.transport);
      expect(server.calls, hasLength(2));
      expect((await queue.report(item.id)).status, SendBackStatus.sent);
    });

    test('a refusal never deletes the only copy: 400, 403, 404, 410, 413, 422 all keep it for a later try', () async {
      for (final int code in <int>[400, 403, 404, 410, 413, 422]) {
        final FakeOutboxDisk d = FakeOutboxDisk();
        final FakeRecordings f = FakeRecordings();
        final SendBackQueue q = queueOver(d, f, clock);
        final OutboxItem item = await q.keep(_clip(), 900);
        server.uploadFails = ApiException.fromStatus(code, 'media_quota_exceeded');
        await q.drain(server.transport);
        expect(d.rows, hasLength(1), reason: 'status $code');
        expect(f.files, hasLength(1), reason: 'status $code');
        expect((await q.report(item.id)).status, SendBackStatus.waiting, reason: 'status $code');
      }
    });

    test('a full quota clears: the same copy goes once the server has room', () async {
      final OutboxItem item = await queue.keep(_clip(), 900);
      server.uploadFails = ApiException.fromStatus(413, 'media_quota_exceeded');
      await queue.drain(server.transport);
      server.uploadFails = null;
      clock.advance(const Duration(hours: 1));
      await queue.drain(server.transport);
      expect(disk.rows, isEmpty);
      expect(files.files, isEmpty);
      expect((await queue.report(item.id)).status, SendBackStatus.sent);
    });

    test('storage_key_unknown after the key was stored: the key is dropped and the copy is uploaded afresh', () async {
      await queue.keep(_clip(), 900);
      server.sendFails = ApiException.fromStatus(400, 'storage_key_unknown');
      await queue.drain(server.transport);
      final Map<Object?, Object?> payload = (await disk.load()).single.payload! as Map<Object?, Object?>;
      expect(payload.containsKey('uploadedStorageKey'), isFalse);
      expect(files.files, hasLength(1));
      server.sendFails = null;
      server.calls.clear();
      clock.advance(const Duration(hours: 1));
      await queue.drain(server.transport);
      expect(server.calls.first, startsWith('upload:'), reason: 'uploaded again, not sent with the dead key');
      expect(disk.rows, isEmpty);
      expect(files.files, isEmpty);
    });

    test('409 storage_key_in_use means an earlier send got there: counted as sent, copy removed', () async {
      final OutboxItem item = await queue.keep(_clip(), 900);
      server.sendFails = ApiException.fromStatus(409, 'storage_key_in_use');
      await queue.drain(server.transport);
      expect(disk.rows, isEmpty);
      expect(files.files, isEmpty);
      expect((await queue.report(item.id)).status, SendBackStatus.sent);
    });

    test('a recording is never stranded: a long outage does not use up tries, and it goes when the signal is back', () async {
      final OutboxItem item = await queue.keep(_clip(), 900);
      server.uploadFails = const SocketException('unreachable');
      for (int i = 0; i < 40; i++) {
        clock.advance(const Duration(hours: 1));
        await queue.drain(server.transport);
      }
      expect((await disk.load()).single.attempts, 40);
      expect((await queue.report(item.id)).status, SendBackStatus.waiting);
      server.uploadFails = null;
      server.calls.clear();
      clock.advance(const Duration(minutes: 31));
      await queue.drain(server.transport);
      expect(server.calls, hasLength(2));
      expect(disk.rows, isEmpty);
    });

    test('the wait between tries never passes half an hour', () {
      for (int a = 0; a < 60; a++) {
        expect(sendBackBackoff(a), lessThanOrEqualTo(const Duration(minutes: 30)));
      }
      expect(sendBackBackoff(0), const Duration(minutes: 1));
    });

    test('a failure time in the future (a wrong clock) does not park the recording', () async {
      await queue.keep(_clip(), 900);
      server.uploadFails = const SocketException('unreachable');
      clock.t = DateTime.utc(2030, 1, 1);
      await queue.drain(server.transport);
      clock.t = DateTime.utc(2026, 11, 21, 12);
      server.uploadFails = null;
      server.calls.clear();
      await queue.drain(server.transport);
      expect(server.calls, hasLength(2));
      expect(disk.rows, isEmpty);
    });

    test('a 5xx answer is not final: the recording stays for a later try', () async {
      final OutboxItem item = await queue.keep(_clip(), 900);
      server.uploadFails = ApiException.fromStatus(503, 'unavailable');
      await queue.drain(server.transport);
      expect(disk.rows, hasLength(1));
      expect((await queue.report(item.id)).status, SendBackStatus.waiting);
    });

    test('stops at the first failure, oldest first, so a dead server is asked once', () async {
      await queue.keep(_clip(), 1);
      clock.advance(const Duration(seconds: 1));
      await queue.keep(_clip(), 2);
      server.uploadFails = const SocketException('unreachable');
      await queue.drain(server.transport);
      expect(server.calls, <String>['upload:4']);
      expect((await disk.load()).map((OutboxItem i) => i.attempts), <int>[1, 0]);
    });

    test('ignoreBackoff is for a caller that already waited; a shorter injected backoff is honoured', () async {
      await queue.keep(_clip(), 1);
      server.uploadFails = const SocketException('unreachable');
      await queue.drain(server.transport);
      server.uploadFails = null;
      server.calls.clear();
      clock.advance(const Duration(seconds: 5));
      await queue.drain(server.transport, backoff: (_) => const Duration(minutes: 10));
      expect(server.calls, isEmpty);
      await queue.drain(server.transport, backoff: (_) => const Duration(seconds: 1));
      expect(server.calls, hasLength(2));
    });

    test('a recording whose copy has gone is let go without claiming it was sent', () async {
      final OutboxItem item = await queue.keep(_clip(), 1);
      files.files.clear();
      await queue.drain(server.transport);
      expect(server.calls, isEmpty);
      expect(disk.rows, isEmpty);
      expect((await queue.report(item.id)).status, SendBackStatus.refused);
    });

    test('rows that are not send-backs (receipts, other kinds) are left exactly as they were', () async {
      await queue.keep(_clip(), 1);
      final List<OutboxItem> rows = await disk.load();
      await disk.save(<OutboxItem>[
        OutboxItem(
            id: 'receipt:m1', kind: OutboxKind.receipt, createdAt: DateTime.utc(2026, 11, 20),
            payload: <String, Object?>{'messageId': 'm1'}, attempts: 2, lastFailedAt: DateTime.utc(2026, 11, 20)),
        ...rows,
      ]);
      await queue.drain(server.transport);
      final List<OutboxItem> left = await disk.load();
      expect(left.map((OutboxItem i) => i.id), <String>['receipt:m1']);
      expect(left.single.attempts, 2);
    });
  });

  group('one lock for the receipts and the recordings', () {
    test('a receipt being recorded while a recording is being kept loses neither row', () async {
      final OutboxLock lock = OutboxLock();
      final SendBackQueue sb = SendBackQueue.over(load: disk.load, save: disk.save, files: files, now: clock.now, lock: lock);
      final ReceiptQueue rq = ReceiptQueue.over(load: disk.load, save: disk.save, now: clock.now, lock: lock);
      final Future<void> a = sb.keep(_clip(), 1).then((_) {});
      final Future<void> b = rq.record('m1', (String id) async => throw const SocketException('x'));
      await Future.wait(<Future<void>>[a, b]);
      final List<String> ids = (await disk.load()).map((OutboxItem i) => i.id).toList();
      expect(ids, hasLength(2));
      expect(ids.any((String i) => i.startsWith('sendback-')), isTrue);
      expect(ids, contains('receipt:m1'));
    });

    test('forChild hands the receipts and the recordings the same lock for the same child', () {
      LocalServices.install(LocalServices.memory(childId: 'ivy'));
      addTearDown(LocalServices.resetForTest);
      expect(identical(OutboxLock.forChild('ivy'), OutboxLock.forChild('ivy')), isTrue);
      expect(identical(OutboxLock.forChild('ivy'), OutboxLock.forChild('zed')), isFalse);
    });
  });

  group('a wipe or "forget this child" takes the recordings with it', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('olive_outbox_wipe'));
    tearDown(() => tmp.deleteSync(recursive: true));

    Future<String> plant(LocalServices s, String child) async {
      final DirectoryRecordingStore store = DirectoryRecordingStore(child, documentsDirectory: () async => tmp);
      final File src = File('${tmp.path}${Platform.pathSeparator}src-$child.mp4')..writeAsBytesSync(<int>[1]);
      return store.keep(XFile(src.path), 'sendback-$child');
    }

    test('the recordings folder the store writes to is the one the services remove', () async {
      final LocalServices s = LocalServices.memory(
          childId: 'ivy', recordingsRoot: Directory('${tmp.path}${Platform.pathSeparator}$kRecordingsFolderName'));
      final String ivy = await plant(s, 'ivy');
      final String zed = await plant(s, 'zed');
      expect(File(ivy).existsSync() && File(zed).existsSync(), isTrue);
      await s.forgetChild('ivy');
      expect(File(ivy).existsSync(), isFalse);
      expect(File(zed).existsSync(), isTrue, reason: 'another child on the device is untouched');
      await s.wipeAll();
      expect(File(zed).existsSync(), isFalse);
      expect(Directory('${tmp.path}${Platform.pathSeparator}$kRecordingsFolderName').existsSync(), isFalse);
    });

    test('with no recordings folder at all, forgetting and wiping still work', () async {
      final LocalServices s = LocalServices.memory(childId: 'ivy');
      await s.forgetChild('ivy');
      await s.wipeAll();
    });
  });

  group('DirectoryRecordingStore — real files', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('olive_outbox_test'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('keeps a copy under the child folder, reads it back, deletes it', () async {
      final File source = File('${tmp.path}${Platform.pathSeparator}picked.mp4')..writeAsBytesSync(<int>[9, 8, 7]);
      final DirectoryRecordingStore store = DirectoryRecordingStore('child/../a', documentsDirectory: () async => tmp);
      final String path = await store.keep(XFile(source.path), 'sendback-1');
      expect(path.startsWith(tmp.path), isTrue);
      expect(path, isNot(contains('..')));
      expect(await store.read(path), <int>[9, 8, 7]);
      source.deleteSync();
      expect(await store.read(path), <int>[9, 8, 7], reason: 'the copy does not depend on the picker\'s temp file');
      await store.delete(path);
      expect(await store.read(path), isNull);
      await store.delete(path);
    });
  });

  group('Android backup', () {
    test('the manifest keeps the unsent recordings and the on-device store out of the platform backup', () {
      final String manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      expect(manifest, contains('android:dataExtractionRules="@xml/data_extraction_rules"'));
      expect(manifest, contains('android:fullBackupContent="@xml/backup_rules"'));
      for (final String f in <String>['backup_rules.xml', 'data_extraction_rules.xml']) {
        final String xml = File('android/app/src/main/res/xml/$f').readAsStringSync();
        expect(xml, contains(kRecordingsFolderName), reason: f);
        expect(xml, contains('olive_store'), reason: f);
        expect(RegExp(r'<exclude\s').allMatches(xml).length, greaterThanOrEqualTo(2), reason: f);
      }
      final String ext = File('android/app/src/main/res/xml/data_extraction_rules.xml').readAsStringSync();
      expect(ext, contains('<cloud-backup'));
      expect(ext, contains('<device-transfer'));
    });
  });
}
