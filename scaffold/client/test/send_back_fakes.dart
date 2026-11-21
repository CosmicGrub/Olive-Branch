// Shared fakes for the send-back tests: an in-memory recording store and an in-memory outbox that survives a
// "restart" (a new queue built over the same [FakeOutboxDisk]).
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:olive_client/offline_outbox.dart';
import 'package:olive_client/send_back_outbox.dart';

/// Recordings kept in a map instead of app storage. [failKeep] makes the copy fail, like a full disk.
class FakeRecordings implements RecordingStore {
  final Map<String, List<int>> files = <String, List<int>>{};
  bool failKeep = false;

  @override
  Future<String> keep(XFile source, String id) async {
    if (failKeep) throw StateError('disk full');
    final String path = '/app/outbox/$id.mp4';
    files[path] = await source.readAsBytes();
    return path;
  }

  @override
  Future<List<int>?> read(String path) async => files[path];

  @override
  Future<void> delete(String path) async {
    files.remove(path);
  }
}

/// The stored outbox rows, written down the way [OutboxRepository] writes them (so a field that does not survive
/// JSON does not survive here either), but in memory. [failSave] makes the write fail.
class FakeOutboxDisk {
  List<Object?> rows = <Object?>[];
  bool failSave = false;

  Future<List<OutboxItem>> load() async => <OutboxItem>[
        for (final Object? r in rows) _decode(r! as Map<String, Object?>),
      ];

  Future<void> save(List<OutboxItem> items) async {
    if (failSave) throw StateError('write refused');
    rows = <Object?>[
      for (final OutboxItem i in items)
        <String, Object?>{
          'id': i.id,
          'kind': i.kind.wireValue,
          'createdAt': i.createdAt.toIso8601String(),
          'payload': Map<String, Object?>.from(i.payload! as Map),
          'attempts': i.attempts,
          if (i.lastError != null) 'lastError': i.lastError,
          if (i.lastFailedAt != null) 'lastFailedAt': i.lastFailedAt!.toUtc().toIso8601String(),
        },
    ];
  }

  static OutboxItem _decode(Map<String, Object?> m) => OutboxItem(
        id: m['id']! as String,
        kind: OutboxKind.values.firstWhere((OutboxKind k) => k.wireValue == m['kind']),
        createdAt: DateTime.parse(m['createdAt']! as String),
        payload: m['payload'],
        attempts: m['attempts']! as int,
        lastError: m['lastError'] as String?,
        lastFailedAt: m['lastFailedAt'] == null ? null : DateTime.parse(m['lastFailedAt']! as String),
      );
}

/// A clock a test moves by hand.
class FakeClock {
  FakeClock(this.t);
  DateTime t;
  DateTime now() => t;
  void advance(Duration d) => t = t.add(d);
}

SendBackQueue queueOver(FakeOutboxDisk disk, FakeRecordings files, FakeClock clock) =>
    SendBackQueue.over(load: disk.load, save: disk.save, files: files, now: clock.now);
