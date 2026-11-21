// OLIVE BRANCH — the small record a phone keeps about its own backups (the `backupstate` area), and the place a sealed
// backup waits while it is being sent. UNVERIFIED on a device; pure Dart, runs headless in CI.
// See docs/planning/BACKUP-RESTORE-CLIENT.md.
//
// WHAT IS KEPT HERE: when the last backup finished and where it went, the public half of each backup key, the last
// backup number this phone wrote or restored, the date a recovery sheet was made and checked, the wrong tries toward a
// 15 minute rest, and the two things that must survive a crash: a restore in progress (the journal) and a restore
// that is waiting out its days (the clearance).
// WHAT IS NEVER KEPT HERE: the words of a recovery sheet, the secret half of any key, a seed. A test scans this
// area after a full set-up and finds none.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'backup_crypto.dart';
import 'device_keys.dart' show b64, unb64;
import 'local_store.dart';

/// Names for the things stored. Public so tests can read what is on disk.
const String kStatePublicKeyPrefix = 'pk.';
const String kStateRestoreJournal = 'restore_journal';
const String kStateClearance = 'clearance';

class BackupRecord {
  const BackupRecord({
    required this.atMs,
    required this.seq,
    required this.destination,
    required this.destinationKind,
    required this.areas,
    required this.bytes,
  });
  final int atMs, seq, areas, bytes;

  /// "a folder on this phone" / "your family's server": what a grown-up reads.
  final String destination;

  /// 'folder' | 'server' | 'memory'.
  final String destinationKind;

  Map<String, Object?> toJson() => <String, Object?>{
        'at': atMs, 'seq': seq, 'dest': destination, 'kind': destinationKind, 'areas': areas, 'bytes': bytes,
      };

  static BackupRecord? fromJson(Object? j) {
    if (j is! Map) return null;
    final Object? at = j['at'], seq = j['seq'], dest = j['dest'], kind = j['kind'], areas = j['areas'], bytes = j['bytes'];
    if (at is! int || seq is! int || dest is! String || kind is! String || areas is! int || bytes is! int) return null;
    return BackupRecord(atMs: at, seq: seq, destination: dest, destinationKind: kind, areas: areas, bytes: bytes);
  }
}

/// How the last try went when it did not finish.
class BackupAttempt {
  const BackupAttempt(this.atMs, this.code);
  final int atMs;

  /// 'unreachable' | 'refused' | 'full' | 'damaged' | 'not_enabled'.
  final String code;
}

class BackupStateStore {
  BackupStateStore(this._ns);
  final LocalNamespace _ns;

  Future<Uint8List?> publicKey(BackupKind kind) async {
    final Object? v = await _ns.get('$kStatePublicKeyPrefix${kind.name}');
    if (v is! String) return null;
    try {
      final Uint8List b = unb64(v);
      return b.length == 32 ? b : null;
    } catch (_) {
      return null;
    }
  }

  /// Only the PUBLIC half is ever stored.
  Future<void> setPublicKey(BackupKind kind, List<int> publicKey) {
    if (publicKey.length != 32) throw ArgumentError('a public key is 32 bytes');
    return _ns.put('$kStatePublicKeyPrefix${kind.name}', b64(publicKey));
  }

  Future<int> lastSeq(BackupKind kind) async {
    final Object? v = await _ns.get('seq.${kind.name}');
    return v is int ? v : 0;
  }

  Future<void> setLastSeq(BackupKind kind, int seq) async {
    if (seq > await lastSeq(kind)) await _ns.put('seq.${kind.name}', seq);
  }

  Future<BackupRecord?> lastSuccess(BackupKind kind) async => BackupRecord.fromJson(await _ns.get('ok.${kind.name}'));

  Future<void> recordSuccess(BackupKind kind, BackupRecord r) async {
    await _ns.put('ok.${kind.name}', r.toJson());
    await _ns.delete('fail.${kind.name}');
  }

  Future<BackupAttempt?> lastFailure(BackupKind kind) async {
    final Object? v = await _ns.get('fail.${kind.name}');
    if (v is Map && v['at'] is int && v['code'] is String) return BackupAttempt(v['at'] as int, v['code'] as String);
    return null;
  }

  Future<void> recordFailure(BackupKind kind, int atMs, String code) =>
      _ns.put('fail.${kind.name}', <String, Object?>{'at': atMs, 'code': code});

  /// When the sheet was made and when its owner confirmed they had written it down (null until they did).
  Future<({int? madeMs, int? checkedMs})> sheet(BackupKind kind) async {
    final Object? v = await _ns.get('sheet.${kind.name}');
    if (v is! Map) return (madeMs: null, checkedMs: null);
    return (madeMs: v['made'] is int ? v['made'] as int : null, checkedMs: v['checked'] is int ? v['checked'] as int : null);
  }

  Future<void> markSheetMade(BackupKind kind, int nowMs) =>
      _ns.put('sheet.${kind.name}', <String, Object?>{'made': nowMs});

  Future<void> markSheetChecked(BackupKind kind, int nowMs) async {
    final Object? v = await _ns.get('sheet.${kind.name}');
    final Map<String, Object?> m = v is Map ? Map<String, Object?>.from(v) : <String, Object?>{};
    m['checked'] = nowMs;
    await _ns.put('sheet.${kind.name}', m);
  }

  // --- wrong tries on a typed sheet ------------------------------------------------------------------------------
  static const int kTriesBeforeRest = 5;
  static const int kRestMs = 15 * 60 * 1000;

  /// Milliseconds still to wait before another sheet may be tried, or 0.
  Future<int> restLeftMs(int nowMs) async {
    final Object? v = await _ns.get('tries');
    if (v is Map && v['until'] is int) {
      final int left = (v['until'] as int) - nowMs;
      return left > 0 ? left : 0;
    }
    return 0;
  }

  /// Counts one wrong sheet; the fifth in a row starts a 15 minute rest (and the count starts again).
  Future<void> recordWrongSheet(int nowMs) async {
    final Object? v = await _ns.get('tries');
    int n = v is Map && v['n'] is int ? v['n'] as int : 0;
    n++;
    if (n >= kTriesBeforeRest) {
      await _ns.put('tries', <String, Object?>{'n': 0, 'until': nowMs + kRestMs});
    } else {
      await _ns.put('tries', <String, Object?>{'n': n});
    }
  }

  Future<void> clearWrongSheets() => _ns.delete('tries');

  // --- the two records that must survive a crash -----------------------------------------------------------------
  Future<Map<String, Object?>?> journal() async {
    final Object? v = await _ns.get(kStateRestoreJournal);
    return v is Map ? Map<String, Object?>.from(v) : null;
  }

  Future<void> putJournal(Map<String, Object?> j) => _ns.put(kStateRestoreJournal, j);
  Future<void> clearJournal() => _ns.delete(kStateRestoreJournal);

  Future<Map<String, Object?>?> clearanceRecord() async {
    final Object? v = await _ns.get(kStateClearance);
    return v is Map ? Map<String, Object?>.from(v) : null;
  }

  Future<void> putClearanceRecord(Map<String, Object?> j) => _ns.put(kStateClearance, j);
  Future<void> clearClearanceRecord() => _ns.delete(kStateClearance);

  Future<void> recordRestored(int nowMs, int seqMax) =>
      _ns.put('restored', <String, Object?>{'at': nowMs, 'seq': seqMax});

  Future<int?> lastRestoredMs() async {
    final Object? v = await _ns.get('restored');
    return v is Map && v['at'] is int ? v['at'] as int : null;
  }
}

/// A sealed backup waiting to be sent: what a run produced, kept so a run that was cut off carries on with the SAME
/// chunks instead of sealing everything again.
class StagedBackup {
  StagedBackup({
    required this.kind,
    required this.rootHash,
    required this.setId,
    required this.seq,
    required this.header,
    required this.chunkIds,
    required this.chunks,
  });
  final BackupKind kind;

  /// A hash of the public key and of every area's content hash: a staged backup is reused only for the same data.
  final String rootHash;
  final String setId;
  final int seq;
  final Uint8List header;
  final List<String> chunkIds;
  final Map<String, Uint8List> chunks;
}

abstract class BackupStaging {
  Future<StagedBackup?> load(BackupKind kind);
  Future<void> save(StagedBackup staged);
  Future<void> clear(BackupKind kind);
}

class MemoryBackupStaging implements BackupStaging {
  final Map<BackupKind, StagedBackup> _m = <BackupKind, StagedBackup>{};
  @override
  Future<StagedBackup?> load(BackupKind kind) async => _m[kind];
  @override
  Future<void> save(StagedBackup staged) async => _m[staged.kind] = staged;
  @override
  Future<void> clear(BackupKind kind) async => _m.remove(kind);
}

/// Files under [root]: `<kind>/header.json` (written last, so it is the commit) and `<kind>/chunks/<id>`.
class DirectoryBackupStaging implements BackupStaging {
  DirectoryBackupStaging(this.root);
  final Directory root;
  String get _sep => Platform.pathSeparator;
  Directory _dir(BackupKind k) => Directory('${root.path}$_sep${k.name}');
  File _head(BackupKind k) => File('${_dir(k).path}${_sep}header.json');
  File _chunk(BackupKind k, String id) => File('${_dir(k).path}${_sep}chunks$_sep$id');

  @override
  Future<StagedBackup?> load(BackupKind kind) async {
    try {
      final File h = _head(kind);
      if (!await h.exists()) return null;
      final Object? j = jsonDecode(await h.readAsString());
      if (j is! Map) return null;
      final Object? root = j['root'], set = j['set'], seq = j['seq'], header = j['header'], ids = j['ids'];
      if (root is! String || set is! String || seq is! int || header is! String || ids is! List) return null;
      final Map<String, Uint8List> chunks = <String, Uint8List>{};
      for (final Object? id in ids) {
        if (id is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(id)) return null;
        final File c = _chunk(kind, id);
        if (!await c.exists()) return null;
        chunks[id] = await c.readAsBytes();
      }
      return StagedBackup(
          kind: kind, rootHash: root, setId: set, seq: seq, header: unb64(header),
          chunkIds: <String>[for (final Object? id in ids) id as String], chunks: chunks);
    } catch (_) {
      return null; // an unreadable staging is the same as none: the run seals again
    }
  }

  @override
  Future<void> save(StagedBackup s) async {
    await clear(s.kind);
    await Directory('${_dir(s.kind).path}${_sep}chunks').create(recursive: true);
    for (final MapEntry<String, Uint8List> e in s.chunks.entries) {
      await _chunk(s.kind, e.key).writeAsBytes(e.value, flush: true);
    }
    final File tmp = File('${_head(s.kind).path}.tmp');
    await tmp.writeAsString(
        jsonEncode(<String, Object?>{
          'root': s.rootHash, 'set': s.setId, 'seq': s.seq, 'header': b64(s.header), 'ids': s.chunkIds,
        }),
        flush: true);
    await tmp.rename(_head(s.kind).path);
  }

  @override
  Future<void> clear(BackupKind kind) async {
    final Directory d = _dir(kind);
    if (await d.exists()) await d.delete(recursive: true);
  }
}
