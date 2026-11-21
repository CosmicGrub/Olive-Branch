// OLIVE BRANCH — the recordings she sends back ("Send one back"), kept on the device until the server has them.
// MASTERFILE section 7.19 and 5.22. Verified by client/test/send_back_outbox_test.dart and receipt_screen_test.dart.
//
// She records a short video for a grown-up. The recording is copied into the app's own storage the moment she
// finishes, and one row for it (local path, length, and the storage key once the upload has happened) is written to
// her on-device outbox (area 'outbox', the same one the "she opened it" receipts use, one lock between them). Only
// after that write has really succeeded is she told it is kept safe. From then on the work belongs to this queue and
// to whoever drains it (her home when it loads and when the app comes back, the Messages screen when it asks again),
// never to the screen she recorded it on: closing that screen, or the app, loses nothing.
//
// The bytes are never put in the JSON store (the store refuses raw media on purpose): the row points at the copy.
//
// What she sees is one picture and one calm line, whatever went wrong. Detail goes to debugPrint only.
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:path_provider/path_provider.dart';

import 'api_client.dart';
import 'child_receive.dart';
import 'local_repositories.dart';
import 'local_services.dart';
import 'offline_outbox.dart';

/// The one line she is shown when a recording could not be kept or could not be sent. No status, no cause, no server.
const String kSendBackTryAgainLine = "That didn't go. Let's try again.";

/// Runtime self-check for [kSendBackTryAgainLine], on the exact string about to be drawn to her: none of the offline
/// outbox's banned words, none of the global child-payload sweep's, and no digit.
bool auditSendBackCopy(String line) {
  if (!auditChildOfflineCopy(line) || RegExp(r'\d').hasMatch(line)) return false;
  for (final String w in line.toLowerCase().split(RegExp(r'[^a-z0-9_]+'))) {
    if (w.isNotEmpty && kChildForbiddenWords.contains(w)) return false;
  }
  return true;
}

/// Why a recording was not kept. Only ever logged.
class SendBackNotKept implements Exception {
  const SendBackNotKept(this.reason);
  final Object reason;
  @override
  String toString() => 'SendBackNotKept($reason)';
}

enum SendBackStatus { waiting, sent, refused }

class SendBackReport {
  const SendBackReport(this.status, this.attempts);
  final SendBackStatus status;
  final int attempts;
}

/// How the bytes reach the server: [upload] returns the storage key the server assigned; [send] records the message.
class SendBackTransport {
  const SendBackTransport({required this.upload, required this.send});
  final Future<String> Function(List<int> bytes) upload;
  final Future<void> Function(String storageKey, int durationMs) send;
}

/// Where a recording's copy lives. A seam so tests do not need the platform's directories.
abstract class RecordingStore {
  /// Copies [source] into app storage as [id] and returns where it is. Throws when the copy is not complete.
  Future<String> keep(XFile source, String id);

  /// The copy's bytes, or null when the copy is gone.
  Future<List<int>?> read(String path);

  Future<void> delete(String path);
}

/// The real thing: files under the app's documents directory, one folder per child.
class DirectoryRecordingStore implements RecordingStore {
  DirectoryRecordingStore(this.childId, {Future<Directory> Function()? documentsDirectory})
      : _documents = documentsDirectory ?? getApplicationDocumentsDirectory;
  final String childId;
  final Future<Directory> Function() _documents;

  Future<Directory> _dir() async {
    final Directory docs = await _documents();
    final String safe = LocalServices.recordingsFolderFor(childId);
    final Directory d =
        Directory('${docs.path}${Platform.pathSeparator}$kRecordingsFolderName${Platform.pathSeparator}$safe');
    await d.create(recursive: true);
    return d;
  }

  @override
  Future<String> keep(XFile source, String id) async {
    final Directory d = await _dir();
    final String safeId = id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final String path = '${d.path}${Platform.pathSeparator}$safeId.mp4';
    await source.saveTo(path);
    final File f = File(path);
    // Never trust a copy that was not read back at the length it should have.
    if (!await f.exists() || await f.length() != await source.length()) {
      try {
        await f.delete();
      } catch (_) {}
      throw const FileSystemException('copy is not complete');
    }
    return path;
  }

  @override
  Future<List<int>?> read(String path) async {
    final File f = File(path);
    return await f.exists() ? await f.readAsBytes() : null;
  }

  @override
  Future<void> delete(String path) async {
    final File f = File(path);
    if (await f.exists()) await f.delete();
  }
}

/// Her recordings waiting to go, for one child on this device.
class SendBackQueue {
  SendBackQueue._(this._load, this._save, this._now, this._files, this._lock, this.durable);

  /// A queue over explicit load/save functions and a recording store (tests).
  factory SendBackQueue.over({
    required Future<List<OutboxItem>> Function() load,
    required Future<void> Function(List<OutboxItem>) save,
    required RecordingStore files,
    DateTime Function()? now,
    OutboxLock? lock,
  }) =>
      SendBackQueue._(load, save, now ?? DateTime.now, files, lock ?? OutboxLock(), true);

  static final Expando<Map<String, SendBackQueue>> _byServices = Expando<Map<String, SendBackQueue>>('sendBackQueues');

  /// The queue for [childId] on this device, backed by the catalogued 'outbox' area. One per device store. If the
  /// store refuses the area (a demo scope in a live build) nothing can be kept durably, and [keep] says so.
  factory SendBackQueue.forChild(String childId, {RecordingStore? files}) {
    final LocalServices services = LocalServices.current;
    final Map<String, SendBackQueue> cache = _byServices[services] ??= <String, SendBackQueue>{};
    return cache[childId] ??= () {
      try {
        final OutboxRepository repo = OutboxRepository(services.area('outbox', ownerId: childId));
        return SendBackQueue._(repo.load, (List<OutboxItem> items) async {
          final int skipped = await repo.save(items);
          if (skipped > 0) throw const FormatException('a row could not be written down');
        }, DateTime.now, files ?? DirectoryRecordingStore(childId), OutboxLock.forChild(childId), true);
      } catch (e) {
        debugPrint('[olive.sendBack] on-device outbox unavailable, nothing can be kept: $e');
        return SendBackQueue._(() async => <OutboxItem>[], (List<OutboxItem> items) async {},
            DateTime.now, files ?? DirectoryRecordingStore(childId), OutboxLock(), false);
      }
    }();
  }

  final Future<List<OutboxItem>> Function() _load;
  final Future<void> Function(List<OutboxItem>) _save;
  final DateTime Function() _now;
  final RecordingStore _files;
  final OutboxLock _lock;

  /// False when the store refused the area: a recording cannot be kept for later, so it is never promised.
  final bool durable;

  int _counter = 0;
  final Map<String, SendBackStatus> _settled = <String, SendBackStatus>{};

  static bool _isSendBack(OutboxItem i) {
    if (i.kind != OutboxKind.message) return false;
    final Object? p = i.payload;
    return p is Map && p['localPath'] is String;
  }

  /// Copies [file] into app storage and writes its row. Returns only after both are on disk and the row reads back;
  /// throws [SendBackNotKept] (after removing the copy) when either could not be done.
  Future<OutboxItem> keep(XFile file, int durationMs) async {
    if (!durable) throw const SendBackNotKept('no on-device outbox');
    final DateTime at = _now().toUtc();
    final String id = 'sendback-${at.microsecondsSinceEpoch}-${_counter++}';
    String? path;
    try {
      path = await _files.keep(file, id);
      final OutboxItem item = OutboxItem(
          id: id,
          kind: OutboxKind.message,
          createdAt: at,
          payload: <String, Object?>{'localPath': path, 'durationMs': durationMs});
      await _lock.run(() async {
        final List<OutboxItem> items = await _load();
        await _save(enqueue(items, item).outbox);
        if (!(await _load()).any((OutboxItem i) => i.id == id)) {
          throw const FormatException('the row did not read back');
        }
      });
      return item;
    } catch (e) {
      if (path != null) {
        try {
          await _files.delete(path);
        } catch (_) {}
      }
      throw SendBackNotKept(e);
    }
  }

  /// How the recording [id] stands: still waiting (with how many real tries it has had), sent, or refused.
  Future<SendBackReport> report(String id) async {
    try {
      return await _lock.run(() async {
        final SendBackStatus? settled = _settled[id];
        if (settled != null) return SendBackReport(settled, 0);
        for (final OutboxItem i in await _load()) {
          if (i.id == id) return SendBackReport(SendBackStatus.waiting, i.attempts);
        }
        // Gone without an answer this run: never claim it was sent.
        return const SendBackReport(SendBackStatus.refused, 0);
      });
    } catch (e) {
      debugPrint('[olive.sendBack] could not read the outbox: $e');
      return const SendBackReport(SendBackStatus.refused, 0);
    }
  }

  /// Tries each waiting recording once, oldest first. One that failed less than its backoff ago is not tried and no
  /// attempt is spent (the time is stored with the row, so a fresh start waits too); [ignoreBackoff] is for the caller
  /// that has itself just waited out the backoff. Stops at the first failure so a server that is down is not asked for
  /// everything. Never throws.
  Future<void> drain(SendBackTransport transport,
      {Duration Function(int attempts)? backoff, bool ignoreBackoff = false}) async {
    try {
      await _lock.run(() async {
        List<OutboxItem> items = await _load();
        final DateTime now = _now();
        final List<OutboxItem> due = items.where(_isSendBack).toList()
          ..sort((OutboxItem a, OutboxItem b) => a.createdAt.compareTo(b.createdAt));
        bool changed = false;
        for (final OutboxItem item in due) {
          if (item.attempts >= maxAttempts) continue;
          if (!ignoreBackoff &&
              insideBackoff(item, now, backoff: backoff == null ? null : (int a) => backoff(a).inMilliseconds)) {
            continue;
          }
          final Map<Object?, Object?> payload = item.payload! as Map<Object?, Object?>;
          final String path = payload['localPath']! as String;
          final Object? dm = payload['durationMs'];
          if (dm is! int) {
            // Nothing can be said to the server about it: let it go, never claim it was sent.
            items = sent(items, item.id);
            _settled[item.id] = SendBackStatus.refused;
            changed = true;
            continue;
          }
          try {
            String? key = payload['uploadedStorageKey'] is String ? payload['uploadedStorageKey'] as String : null;
            if (key == null) {
              final List<int>? bytes = await _files.read(path);
              if (bytes == null) {
                debugPrint('[olive.sendBack] a recording is no longer on the device: ${item.id}');
                items = sent(items, item.id);
                _settled[item.id] = SendBackStatus.refused;
                changed = true;
                continue;
              }
              key = await transport.upload(bytes);
              // Written down at once, so a stop between the two calls never uploads the same recording twice.
              items = <OutboxItem>[
                for (final OutboxItem i in items)
                  i.id == item.id ? i.withPayload(<Object?, Object?>{...payload, 'uploadedStorageKey': key}) : i,
              ];
              await _save(items);
            }
            await transport.send(key, dm);
            items = sent(items, item.id);
            _settled[item.id] = SendBackStatus.sent;
            changed = true;
            await _deleteQuietly(path);
          } on ApiException catch (e) {
            changed = true;
            debugPrint('[olive.sendBack] server answered ${e.statusCode} ${e.error}');
            if (isFinalServerAnswer(e)) {
              items = sent(items, item.id);
              _settled[item.id] = SendBackStatus.refused;
              await _deleteQuietly(path);
              continue;
            }
            items = recordFailure(items, item.id, 'server', at: now.toUtc());
            break;
          } catch (e) {
            debugPrint('[olive.sendBack] no answer: $e');
            items = recordFailure(items, item.id, 'network', at: now.toUtc());
            changed = true;
            break;
          }
        }
        if (changed) await _save(items);
      });
    } catch (e) {
      debugPrint('[olive.sendBack] drain skipped: $e');
    }
  }

  Future<void> _deleteQuietly(String path) async {
    try {
      await _files.delete(path);
    } catch (e) {
      debugPrint('[olive.sendBack] could not remove a sent recording: $e');
    }
  }
}

/// Sends what is waiting for [childId]: builds a session, runs one drain, closes it. Best effort and silent.
Future<void> drainSendBacks({
  required String baseUrl,
  required String childId,
  required String sessionToken,
  http.Client? httpClient,
  SendBackQueue? queue,
  Duration Function(int attempts)? backoff,
  bool ignoreBackoff = false,
}) async {
  try {
    await withChildApi<void>(
      baseUrl: baseUrl,
      sessionToken: sessionToken,
      httpClient: httpClient,
      body: (OliveApi api) => (queue ?? SendBackQueue.forChild(childId)).drain(
          SendBackTransport(
            upload: (List<int> bytes) => api.uploadMedia(childId, bytes),
            send: (String key, int ms) async {
              await api.sendMessage(childId, storageKey: key, durationMs: ms);
            },
          ),
          backoff: backoff,
          ignoreBackoff: ignoreBackoff),
    );
  } catch (e) {
    debugPrint('[olive.sendBack] not sent this run: $e');
  }
}
