// OLIVE BRANCH — where a backup is kept: a folder (a file the family owns), the family's own server
// (backup_server.dart), or memory for tests. UNVERIFIED on a device; pure Dart, runs headless in CI.
// See docs/planning/BACKUP-RESTORE-CLIENT.md.
//
// A destination holds only SEALED things and never learns what is in them. A folder keeps opaque chunks named by a hash
// of their own bytes and one small signed header per backup (a "manifest"). The order a backup is written in is what
// makes a kill at any moment harmless: every chunk first, the manifest LAST. A manifest is the commit; until it exists
// the previous backup is still the newest one, and a chunk with no manifest is just waste that the next run reuses.
//
//   folder  `<root>/<set>/chunks/<id>.chunk` and `<root>/<set>/manifests/<name>.manifest`; each file is written to a
//           `.tmp`, flushed and renamed, so a half-written file is never read as a whole one.
//   server  one sealed file per backup, sent in pieces over the server's own routes (backup_server.dart).
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'backup_crypto.dart' show sha256HexOf;
import 'backup_header.dart';
import 'backup_names.dart';
import 'backup_state.dart' show StagedBackup;

export 'backup_names.dart';

/// Why a destination refused or failed; [code] is for logic, never shown as is.
class BackupSinkException implements Exception {
  const BackupSinkException(this.code, [this.detail = '']);

  /// 'unreachable' (could not be asked, try again), 'refused' (asked and said no), 'full', 'bad_name',
  /// 'not_enabled' (the internet destination is compiled out), 'damaged', 'signed_out', 'no_vault', 'paused'.
  final String code;
  final String detail;

  /// Worth trying again later without anyone changing anything.
  bool get transient => code == 'unreachable';

  @override
  String toString() => 'BackupSinkException($code)';
}

/// Read-only: what a restore needs from wherever a backup is kept.
abstract class BackupSource {
  Future<List<String>> listManifests(String set);
  Future<Uint8List?> getManifest(String set, String name);
  Future<Uint8List?> getChunk(String set, String id);
}

/// How much of a backup a destination already had, and how much it was sent this run.
class SendCounts {
  int uploaded = 0, skipped = 0;
}

abstract class BackupSink implements BackupSource {
  /// What a grown-up calls it: "a folder on this phone", "your family's server".
  String get label;

  /// Stable word for the status record: 'folder' | 'server' | 'memory'.
  String get kindWord;

  /// The highest backup number this destination already holds for [set] (0 when none or when it cannot be asked).
  Future<int> highestSeq(String set);

  /// Sends [staged] and makes it count, then checks it is really there. Throws [BackupSinkException] on any problem.
  /// A kill at any point leaves the previous backup the newest. [keep] is how many of this phone's own backups stay.
  Future<void> store(StagedBackup staged, BackupHeader header, SendCounts counts, {int keep = 3});
}

void _check(String set, {String? chunk, String? manifest}) {
  if (!isSetId(set) || (chunk != null && !isChunkId(chunk)) || (manifest != null && !isManifestName(manifest))) {
    throw const BackupSinkException('bad_name');
  }
}

/// A destination that keeps chunks and manifests as separate named things (a folder, memory).
abstract class ChunkedBackupSink implements BackupSink {
  Future<bool> hasChunk(String set, String id);
  Future<void> putChunk(String set, String id, Uint8List bytes);
  @override
  Future<Uint8List?> getChunk(String set, String id);
  Future<void> deleteChunk(String set, String id);
  Future<void> putManifest(String set, String name, Uint8List bytes);
  Future<void> deleteManifest(String set, String name);

  @override
  Future<int> highestSeq(String set) async {
    int top = 0;
    try {
      for (final String n in await listManifests(set)) {
        final int? q = int.tryParse(n.substring(0, 10));
        if (q != null && q > top) top = q;
      }
    } on BackupSinkException {
      // an unreachable destination just does not raise the number
    }
    return top;
  }

  @override
  Future<void> store(StagedBackup s, BackupHeader header, SendCounts counts, {int keep = 3}) async {
    for (final String id in s.chunkIds) {
      if (await hasChunk(s.setId, id)) {
        counts.skipped++;
        continue;
      }
      await putChunk(s.setId, id, s.chunks[id]!);
      counts.uploaded++;
    }
    // The commit. Everything above is invisible to a restore until this lands.
    await putManifest(s.setId, header.name, s.header);
    await _verify(s, header);
    try {
      await _tidy(s.setId, header, keep);
    } catch (_) {
      // Tidying is a courtesy; a failure leaves an extra old backup, never a missing new one.
    }
  }

  Future<void> _verify(StagedBackup s, BackupHeader header) async {
    final Uint8List? back = await getManifest(s.setId, header.name);
    if (back == null || !_same(back, s.header)) throw const BackupSinkException('damaged', 'manifest');
    for (final String id in s.chunkIds) {
      final Uint8List? c = await getChunk(s.setId, id);
      if (c == null || await sha256HexOf(c) != id) throw const BackupSinkException('damaged', 'chunk');
    }
  }

  static bool _same(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Removes this phone's backups beyond the newest [keep], and the chunks no remaining backup uses.
  Future<void> _tidy(String setId, BackupHeader newest, int keep) async {
    final String mine = writerTag(newest.writer);
    final List<String> all = await listManifests(setId);
    final List<String> ours = <String>[for (final String n in all) if (n.endsWith('-$mine')) n]..sort();
    if (ours.length <= keep) return;
    final List<String> drop = ours.sublist(0, ours.length - keep);
    final Set<String> keepIds = <String>{};
    for (final String n in all) {
      if (drop.contains(n)) continue;
      final Uint8List? b = await getManifest(setId, n);
      final BackupHeader? h = b == null ? null : BackupHeader.parse(b);
      if (h != null) keepIds.addAll(h.chunks);
    }
    for (final String n in drop) {
      final Uint8List? b = await getManifest(setId, n);
      final BackupHeader? h = b == null ? null : BackupHeader.parse(b);
      await deleteManifest(setId, n);
      if (h != null) {
        for (final String id in h.chunks) {
          if (!keepIds.contains(id)) await deleteChunk(setId, id);
        }
      }
    }
  }
}

/// Everything in memory. For tests, and the stand-in for a destination.
class MemoryBackupSink extends ChunkedBackupSink {
  MemoryBackupSink({this.label = 'memory'});
  @override
  final String label;
  @override
  String get kindWord => 'memory';

  final Map<String, Uint8List> chunks = <String, Uint8List>{};
  final Map<String, Uint8List> manifests = <String, Uint8List>{};

  /// Test hook: called before every operation; throw to simulate a kill or an outage at that moment.
  void Function(String op)? onOp;

  void _op(String op) => onOp?.call(op);

  @override
  Future<bool> hasChunk(String set, String id) async {
    _check(set, chunk: id);
    _op('has');
    return chunks.containsKey('$set/$id');
  }

  @override
  Future<void> putChunk(String set, String id, Uint8List bytes) async {
    _check(set, chunk: id);
    _op('putChunk');
    chunks['$set/$id'] = Uint8List.fromList(bytes);
  }

  @override
  Future<Uint8List?> getChunk(String set, String id) async {
    _check(set, chunk: id);
    _op('getChunk');
    return chunks['$set/$id'];
  }

  @override
  Future<void> deleteChunk(String set, String id) async {
    _check(set, chunk: id);
    _op('deleteChunk');
    chunks.remove('$set/$id');
  }

  @override
  Future<void> putManifest(String set, String name, Uint8List bytes) async {
    _check(set, manifest: name);
    _op('putManifest');
    manifests['$set/$name'] = Uint8List.fromList(bytes);
  }

  @override
  Future<List<String>> listManifests(String set) async {
    _check(set);
    _op('listManifests');
    return <String>[
      for (final String k in manifests.keys)
        if (k.startsWith('$set/')) k.substring(set.length + 1),
    ]..sort();
  }

  @override
  Future<Uint8List?> getManifest(String set, String name) async {
    _check(set, manifest: name);
    _op('getManifest');
    return manifests['$set/$name'];
  }

  @override
  Future<void> deleteManifest(String set, String name) async {
    _check(set, manifest: name);
    _op('deleteManifest');
    manifests.remove('$set/$name');
  }
}

/// A folder. [root] is wherever the family keeps backups (a folder they copy to a drive, a card, another computer).
class DirectoryBackupSink extends ChunkedBackupSink {
  DirectoryBackupSink(this.root, {this.label = 'a folder on this phone'});
  final Directory root;
  @override
  final String label;
  @override
  String get kindWord => 'folder';

  String get _sep => Platform.pathSeparator;
  File _chunk(String set, String id) => File('${root.path}$_sep$set${_sep}chunks$_sep$id.chunk');
  File _manifest(String set, String name) => File('${root.path}$_sep$set${_sep}manifests$_sep$name.manifest');

  Future<void> _writeAtomic(File f, Uint8List bytes) async {
    await f.parent.create(recursive: true);
    final File tmp = File('${f.path}.tmp');
    final RandomAccessFile h = await tmp.open(mode: FileMode.write);
    try {
      await h.writeFrom(bytes);
      await h.flush();
    } finally {
      await h.close();
    }
    await tmp.rename(f.path);
  }

  Future<T> _io<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on FileSystemException catch (e) {
      final String m = '${e.osError?.errorCode ?? ''}';
      // ENOSPC (28) and the Windows disk-full codes: say so plainly.
      if (m == '28' || m == '112' || m == '39') throw const BackupSinkException('full');
      throw BackupSinkException('unreachable', e.message);
    }
  }

  @override
  Future<bool> hasChunk(String set, String id) async {
    _check(set, chunk: id);
    return _io(() => _chunk(set, id).exists());
  }

  @override
  Future<void> putChunk(String set, String id, Uint8List bytes) async {
    _check(set, chunk: id);
    return _io(() => _writeAtomic(_chunk(set, id), bytes));
  }

  @override
  Future<Uint8List?> getChunk(String set, String id) async {
    _check(set, chunk: id);
    return _io(() async {
      final File f = _chunk(set, id);
      return await f.exists() ? f.readAsBytes() : null;
    });
  }

  @override
  Future<void> deleteChunk(String set, String id) async {
    _check(set, chunk: id);
    return _io(() async {
      final File f = _chunk(set, id);
      if (await f.exists()) await f.delete();
    });
  }

  @override
  Future<void> putManifest(String set, String name, Uint8List bytes) async {
    _check(set, manifest: name);
    return _io(() => _writeAtomic(_manifest(set, name), bytes));
  }

  @override
  Future<List<String>> listManifests(String set) async {
    _check(set);
    return _io(() async {
      final Directory d = Directory('${root.path}$_sep$set${_sep}manifests');
      if (!await d.exists()) return <String>[];
      final List<String> out = <String>[];
      await for (final FileSystemEntity e in d.list()) {
        if (e is! File) continue;
        final String base = e.uri.pathSegments.last;
        // A leftover `.tmp` is never a manifest.
        if (base.endsWith('.manifest')) {
          final String n = base.substring(0, base.length - '.manifest'.length);
          if (isManifestName(n)) out.add(n);
        }
      }
      return out..sort();
    });
  }

  @override
  Future<Uint8List?> getManifest(String set, String name) async {
    _check(set, manifest: name);
    return _io(() async {
      final File f = _manifest(set, name);
      return await f.exists() ? f.readAsBytes() : null;
    });
  }

  @override
  Future<void> deleteManifest(String set, String name) async {
    _check(set, manifest: name);
    return _io(() async {
      final File f = _manifest(set, name);
      if (await f.exists()) await f.delete();
    });
  }

  /// Every set id that has anything in this folder (so a restore can say "I found 1 backup here").
  Future<List<String>> sets() => _io(() async {
        if (!await root.exists()) return <String>[];
        final List<String> out = <String>[];
        await for (final FileSystemEntity e in root.list()) {
          if (e is Directory && isSetId(e.uri.pathSegments.where((String s) => s.isNotEmpty).last)) {
            out.add(e.uri.pathSegments.where((String s) => s.isNotEmpty).last);
          }
        }
        return out..sort();
      });
}

/// A folder as a place to read a backup from, or null when it is not a folder that exists.
Future<BackupSource?> openBackupFolder(String path) async {
  final Directory d = Directory(path);
  return await d.exists() ? DirectoryBackupSink(d) : null;
}
