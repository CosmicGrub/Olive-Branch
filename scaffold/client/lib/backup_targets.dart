// OLIVE BRANCH — where a sealed backup is kept: a folder on the phone, one file to carry, or the family's own server.
// UNVERIFIED on a device; pure Dart, runs headless in CI (client/test/backup_targets_test.dart).
// Design: docs/planning/BACKUP-AND-RESTORE.md.
//
// A target stores opaque bytes and never needs a key: chunks under their SHA-256 names, then ONE commit that carries the
// plain header and the sealed manifest. The commit is the only thing that makes a set count, and it refuses unless every
// chunk the header names is already there with the right size, so a half-sent set is invisible to a restore and the
// previous set stays the newest. Chunks are content-named and idempotent, so a transfer that stopped can be run again and
// sends only what is missing (resumable at chunk size).
//
//  DirectoryBackupTarget  a folder (the app's own, or a drive's): `<root>/<kind>/<set>/chunks/<name>` and a `commit.bin`,
//                         every file written to a temporary name and renamed, so a kill leaves whole files or none.
//  MemoryBackupTarget     for tests and the offline preview.
//  ServerBackupTarget     the family's own server over a small JSON wire ([BackupWire]); the routes it expects are in
//                         docs/planning/BACKUP-AND-RESTORE.md. The server stores sealed bytes under random ids and cannot read them.
//  BackupBundle           one file holding a whole set (header, manifest, chunks) to carry on a stick or send to the
//                         other grown-up's phone: opaque to whoever carries it.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'backup_classes.dart';
import 'backup_format.dart';
import 'device_keys.dart' show b64, unb64;

class BackupTargetException implements Exception {
  const BackupTargetException(this.code, this.message);

  /// 'missing' (a chunk the header names is not there), 'offline', 'refused', 'full', 'io'.
  final String code;
  final String message;
  @override
  String toString() => 'BackupTargetException($code: $message)';
}

/// A set that was committed: its plain header and sealed manifest.
class CommittedSet {
  CommittedSet(this.kind, this.setId, this.header, this.manifest, this.atMs);
  final BackupKind kind;
  final String setId;
  final Uint8List header;
  final Uint8List manifest;
  final int atMs;
}

abstract class BackupTarget {
  /// 'folder', 'server' or 'memory': the word the status line uses.
  String get kindWord;

  /// The chunk names already held for [setId] (committed or not).
  Future<Set<String>> chunkIds(BackupKind kind, String setId);

  /// Idempotent: storing the same chunk twice is the same as once.
  Future<void> putChunk(BackupKind kind, String setId, String chunkId, Uint8List bytes);
  Future<Uint8List?> getChunk(BackupKind kind, String setId, String chunkId);

  /// Makes the set count. Throws [BackupTargetException] 'missing' unless every chunk in [header] is held.
  Future<void> commit(BackupKind kind, String setId, Uint8List header, Uint8List manifest);

  /// Committed sets, newest first by the header's time.
  Future<List<CommittedSet>> committed(BackupKind kind);

  /// Removes a set. Only ever called by retention, after a newer set has been checked.
  Future<void> remove(BackupKind kind, String setId);
}

final RegExp _setIdRe = RegExp(r'^[0-9a-f]{32}$');
final RegExp _chunkIdRe = RegExp(r'^[0-9a-f]{64}$');

void _checkIds(String setId, [String? chunkId]) {
  if (!_setIdRe.hasMatch(setId) || (chunkId != null && !_chunkIdRe.hasMatch(chunkId))) {
    throw const BackupTargetException('refused', 'bad name');
  }
}

Future<void> _checkCommit(BackupTarget t, BackupKind kind, String setId, Uint8List header) async {
  final BackupHeader h = BackupHeader.parse(header);
  if (h.setId != setId || h.kind != kind) throw const BackupTargetException('refused', 'header is for another set');
  final Set<String> have = await t.chunkIds(kind, setId);
  for (final MapEntry<String, int> c in h.chunks) {
    if (!have.contains(c.key)) throw const BackupTargetException('missing', 'a piece is not there yet');
  }
}

int _atOf(Uint8List header) => BackupHeader.parse(header).atMs;

// ------------------------------------------------------------------ memory

class MemoryBackupTarget implements BackupTarget {
  final Map<String, Map<String, Uint8List>> _chunks = <String, Map<String, Uint8List>>{};
  final Map<String, CommittedSet> _commits = <String, CommittedSet>{};
  String _k(BackupKind k, String s) => '${k.word}/$s';

  @override
  String get kindWord => 'memory';

  /// Test hook: damages one stored chunk in place.
  void corruptChunk(BackupKind kind, String setId, String chunkId) {
    final Uint8List? b = _chunks[_k(kind, setId)]?[chunkId];
    if (b != null && b.isNotEmpty) b[b.length ~/ 2] ^= 0xff;
  }

  /// Test hook: forgets one stored chunk.
  void dropChunk(BackupKind kind, String setId, String chunkId) => _chunks[_k(kind, setId)]?.remove(chunkId);

  @override
  Future<Set<String>> chunkIds(BackupKind kind, String setId) async =>
      (_chunks[_k(kind, setId)] ?? <String, Uint8List>{}).keys.toSet();

  @override
  Future<void> putChunk(BackupKind kind, String setId, String chunkId, Uint8List bytes) async {
    _checkIds(setId, chunkId);
    (_chunks[_k(kind, setId)] ??= <String, Uint8List>{})[chunkId] = Uint8List.fromList(bytes);
  }

  @override
  Future<Uint8List?> getChunk(BackupKind kind, String setId, String chunkId) async {
    final Uint8List? b = _chunks[_k(kind, setId)]?[chunkId];
    return b == null ? null : Uint8List.fromList(b);
  }

  @override
  Future<void> commit(BackupKind kind, String setId, Uint8List header, Uint8List manifest) async {
    _checkIds(setId);
    await _checkCommit(this, kind, setId, header);
    _commits[_k(kind, setId)] = CommittedSet(kind, setId, Uint8List.fromList(header), Uint8List.fromList(manifest), _atOf(header));
  }

  @override
  Future<List<CommittedSet>> committed(BackupKind kind) async => _commits.values
      .where((CommittedSet c) => c.kind == kind)
      .toList()
    ..sort((CommittedSet a, CommittedSet b) => b.atMs != a.atMs ? b.atMs.compareTo(a.atMs) : b.setId.compareTo(a.setId));

  @override
  Future<void> remove(BackupKind kind, String setId) async {
    _commits.remove(_k(kind, setId));
    _chunks.remove(_k(kind, setId));
  }
}

// ------------------------------------------------------------------ folder

class DirectoryBackupTarget implements BackupTarget {
  DirectoryBackupTarget(this.root);
  final Directory root;
  static final String _s = Platform.pathSeparator;

  @override
  String get kindWord => 'folder';

  Directory _set(BackupKind k, String id) => Directory('${root.path}$_s${k.word}$_s$id');
  Directory _chunksDir(BackupKind k, String id) => Directory('${_set(k, id).path}${_s}chunks');
  File _commitFile(BackupKind k, String id) => File('${_set(k, id).path}${_s}commit.bin');

  static Future<void> _writeAtomic(File f, List<int> bytes) async {
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

  @override
  Future<Set<String>> chunkIds(BackupKind kind, String setId) async {
    _checkIds(setId);
    final Directory d = _chunksDir(kind, setId);
    if (!await d.exists()) return <String>{};
    final Set<String> out = <String>{};
    await for (final FileSystemEntity e in d.list()) {
      if (e is! File) continue;
      final String n = e.uri.pathSegments.last;
      if (_chunkIdRe.hasMatch(n)) out.add(n);
    }
    return out;
  }

  @override
  Future<void> putChunk(BackupKind kind, String setId, String chunkId, Uint8List bytes) async {
    _checkIds(setId, chunkId);
    try {
      await _writeAtomic(File('${_chunksDir(kind, setId).path}$_s$chunkId'), bytes);
    } on FileSystemException catch (e) {
      throw BackupTargetException('io', e.message);
    }
  }

  @override
  Future<Uint8List?> getChunk(BackupKind kind, String setId, String chunkId) async {
    _checkIds(setId, chunkId);
    final File f = File('${_chunksDir(kind, setId).path}$_s$chunkId');
    return await f.exists() ? f.readAsBytes() : null;
  }

  @override
  Future<void> commit(BackupKind kind, String setId, Uint8List header, Uint8List manifest) async {
    _checkIds(setId);
    await _checkCommit(this, kind, setId, header);
    final BytesBuilder b = BytesBuilder()
      ..add(_u32(header.length))
      ..add(header)
      ..add(manifest);
    try {
      await _writeAtomic(_commitFile(kind, setId), b.toBytes());
    } on FileSystemException catch (e) {
      throw BackupTargetException('io', e.message);
    }
  }

  @override
  Future<List<CommittedSet>> committed(BackupKind kind) async {
    final Directory d = Directory('${root.path}$_s${kind.word}');
    if (!await d.exists()) return <CommittedSet>[];
    final List<CommittedSet> out = <CommittedSet>[];
    await for (final FileSystemEntity e in d.list()) {
      if (e is! Directory) continue;
      final String id = e.uri.pathSegments.where((String s) => s.isNotEmpty).last;
      if (!_setIdRe.hasMatch(id)) continue;
      final File c = _commitFile(kind, id);
      if (!await c.exists()) continue;
      try {
        final Uint8List raw = await c.readAsBytes();
        final int hl = _readU32(raw, 0);
        final Uint8List header = Uint8List.fromList(raw.sublist(4, 4 + hl));
        out.add(CommittedSet(kind, id, header, Uint8List.fromList(raw.sublist(4 + hl)), _atOf(header)));
      } catch (_) {
        // A damaged commit is skipped, never fatal: the older sets are still there.
      }
    }
    out.sort((CommittedSet a, CommittedSet b) => b.atMs != a.atMs ? b.atMs.compareTo(a.atMs) : b.setId.compareTo(a.setId));
    return out;
  }

  @override
  Future<void> remove(BackupKind kind, String setId) async {
    _checkIds(setId);
    final Directory d = _set(kind, setId);
    // The commit goes first: from then on the set no longer counts, even if the rest is interrupted.
    final File c = _commitFile(kind, setId);
    if (await c.exists()) await c.delete();
    if (await d.exists()) await d.delete(recursive: true);
  }
}

Uint8List _u32(int v) => Uint8List.fromList(<int>[(v >> 24) & 255, (v >> 16) & 255, (v >> 8) & 255, v & 255]);
int _readU32(List<int> b, int i) => (b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3];

// ------------------------------------------------------------------ the family's server

/// The small JSON wire a server target speaks. The app's own client adapts this to its signed-in session.
abstract class BackupWire {
  /// Returns the decoded JSON body. A 404 is returned as a [BackupWireNotFound]; any other failure is thrown as
  /// [BackupTargetException] ('offline' for no connection, 'refused' for a "no", 'full' for no room).
  Future<Map<String, Object?>> call(String method, String path, {Map<String, Object?>? body});
}

class BackupWireNotFound implements Exception {
  const BackupWireNotFound();
}

class ServerBackupTarget implements BackupTarget {
  ServerBackupTarget(this.wire);
  final BackupWire wire;

  @override
  String get kindWord => 'server';

  String _p(BackupKind k, [String? set, String? tail]) =>
      '/v1/backup/${k.word}/sets${set == null ? '' : '/$set'}${tail == null ? '' : '/$tail'}';

  @override
  Future<Set<String>> chunkIds(BackupKind kind, String setId) async {
    _checkIds(setId);
    try {
      final Map<String, Object?> r = await wire.call('GET', _p(kind, setId));
      return <String>{for (final Object? c in (r['chunks'] as List? ?? const <Object?>[])) if (c is String && _chunkIdRe.hasMatch(c)) c};
    } on BackupWireNotFound {
      return <String>{};
    }
  }

  @override
  Future<void> putChunk(BackupKind kind, String setId, String chunkId, Uint8List bytes) async {
    _checkIds(setId, chunkId);
    await wire.call('PUT', _p(kind, setId, 'chunks/$chunkId'), body: <String, Object?>{'b64': b64(bytes)});
  }

  @override
  Future<Uint8List?> getChunk(BackupKind kind, String setId, String chunkId) async {
    _checkIds(setId, chunkId);
    try {
      final Map<String, Object?> r = await wire.call('GET', _p(kind, setId, 'chunks/$chunkId'));
      final Object? s = r['b64'];
      return s is String ? unb64(s) : null;
    } on BackupWireNotFound {
      return null;
    }
  }

  @override
  Future<void> commit(BackupKind kind, String setId, Uint8List header, Uint8List manifest) async {
    _checkIds(setId);
    await wire.call('PUT', _p(kind, setId, 'commit'),
        body: <String, Object?>{'header': b64(header), 'manifest': b64(manifest)});
  }

  @override
  Future<List<CommittedSet>> committed(BackupKind kind) async {
    final List<CommittedSet> out = <CommittedSet>[];
    try {
      final Map<String, Object?> r = await wire.call('GET', _p(kind));
      for (final Object? s in (r['sets'] as List? ?? const <Object?>[])) {
        if (s is! Map) continue;
        try {
          final Uint8List header = unb64(s['header'] as String);
          final BackupHeader h = BackupHeader.parse(header);
          if (h.kind != kind) continue;
          out.add(CommittedSet(kind, h.setId, header, unb64(s['manifest'] as String), h.atMs));
        } catch (_) {
          // one unreadable entry never hides the others
        }
      }
    } on BackupWireNotFound {
      return out;
    }
    out.sort((CommittedSet a, CommittedSet b) => b.atMs != a.atMs ? b.atMs.compareTo(a.atMs) : b.setId.compareTo(a.setId));
    return out;
  }

  @override
  Future<void> remove(BackupKind kind, String setId) async {
    _checkIds(setId);
    try {
      await wire.call('DELETE', _p(kind, setId));
    } on BackupWireNotFound {
      // already gone
    }
  }
}

// ------------------------------------------------------------------ one file to carry

/// A whole set in one file: `OLIVEBK1`, header, manifest, then each chunk (name, size, bytes). Opaque: the file holds
/// nothing a carrier can read, and a damaged or altered file is refused whole before it reaches any target.
class BackupBundle {
  static final Uint8List _magic = Uint8List.fromList(utf8.encode('OLIVEBK1'));

  static Future<Uint8List> pack(BackupTarget from, BackupKind kind, String setId) async {
    final CommittedSet? set = (await from.committed(kind)).cast<CommittedSet?>().firstWhere(
        (CommittedSet? s) => s!.setId == setId,
        orElse: () => null);
    if (set == null) throw const BackupTargetException('missing', 'that backup is not there');
    final BackupHeader h = BackupHeader.parse(set.header);
    final BytesBuilder b = BytesBuilder()
      ..add(_magic)
      ..add(_u32(set.header.length))
      ..add(set.header)
      ..add(_u32(set.manifest.length))
      ..add(set.manifest)
      ..add(_u32(h.chunks.length));
    for (final MapEntry<String, int> c in h.chunks) {
      final Uint8List? bytes = await from.getChunk(kind, setId, c.key);
      if (bytes == null || bytes.length != c.value) throw const BackupTargetException('missing', 'a piece is not there');
      b.add(_hexToBytes(c.key));
      b.add(_u32(bytes.length));
      b.add(bytes);
    }
    return b.toBytes();
  }

  /// Checks [file] whole, then stores it into [to] and commits. Nothing is stored for a bad file.
  static Future<CommittedSet> unpackInto(BackupTarget to, Uint8List file) async {
    try {
      int i = 0;
      if (file.length < 12 || !_eq(file.sublist(0, 8), _magic)) throw const BackupTargetException('refused', 'not an Olive backup file');
      i = 8;
      final int hl = _readU32(file, i);
      i += 4;
      final Uint8List header = Uint8List.fromList(file.sublist(i, i + hl));
      i += hl;
      final int ml = _readU32(file, i);
      i += 4;
      final Uint8List manifest = Uint8List.fromList(file.sublist(i, i + ml));
      i += ml;
      final int n = _readU32(file, i);
      i += 4;
      final BackupHeader h = BackupHeader.parse(header);
      if (n != h.chunks.length) throw const BackupTargetException('refused', 'the file does not add up');
      final List<MapEntry<String, Uint8List>> chunks = <MapEntry<String, Uint8List>>[];
      for (int k = 0; k < n; k++) {
        final String id = _bytesToHex(file.sublist(i, i + 32));
        i += 32;
        final int len = _readU32(file, i);
        i += 4;
        final Uint8List bytes = Uint8List.fromList(file.sublist(i, i + len));
        i += len;
        if (id != h.chunks[k].key || len != h.chunks[k].value || await sha256Hex(bytes) != id) {
          throw const BackupTargetException('refused', 'the file is damaged');
        }
        chunks.add(MapEntry<String, Uint8List>(id, bytes));
      }
      if (i != file.length) throw const BackupTargetException('refused', 'the file has extra bytes');
      for (final MapEntry<String, Uint8List> c in chunks) {
        await to.putChunk(h.kind, h.setId, c.key, c.value);
      }
      await to.commit(h.kind, h.setId, header, manifest);
      return CommittedSet(h.kind, h.setId, header, manifest, h.atMs);
    } on BackupTargetException {
      rethrow;
    } on BackupFormatException {
      throw const BackupTargetException('refused', 'not an Olive backup file');
    } on RangeError {
      throw const BackupTargetException('refused', 'the file is cut short');
    }
  }

  static bool _eq(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static Uint8List _hexToBytes(String h) =>
      Uint8List.fromList(<int>[for (int i = 0; i < h.length; i += 2) int.parse(h.substring(i, i + 2), radix: 16)]);
  static String _bytesToHex(List<int> b) => b.map((int x) => x.toRadixString(16).padLeft(2, '0')).join();
}
