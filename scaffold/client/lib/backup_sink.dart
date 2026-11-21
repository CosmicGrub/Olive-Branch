// OLIVE BRANCH — where a backup is kept: a folder (a file the family owns), the family's own server, or memory for
// tests. UNVERIFIED on a device; pure Dart, runs headless in CI. See docs/planning/BACKUP-RESTORE-CLIENT.md.
//
// A destination holds only SEALED things and never learns what is in them: opaque chunks named by a hash of their own
// bytes, and one small signed header per backup (a "manifest"). The order a backup is written in is what makes a
// kill at any moment harmless: every chunk first, the manifest LAST. A manifest is the commit; until it exists the
// previous backup is still the newest one, and a chunk with no manifest is just waste that the next run reuses.
//
//   folder  `<root>/<set>/chunks/<id>.chunk` and `<root>/<set>/manifests/<name>.manifest`; each file is written to a
//           `.tmp`, flushed and renamed, so a half-written file is never read as a whole one.
//   server  the contract in docs/planning/BACKUP-RESTORE-CLIENT.md (`/v1/backup/<set>/...`). The SERVER HALF IS NOT
//           BUILT; this client speaks the contract and the tests run it against a stand-in.
//
// The server destination is compiled out of a release build ([kBackupInternetEnabled]) until the outside review of
// the sealing has reported: nothing that crosses the internet ships before then. A folder never needs it.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// False in a release build unless it was made with `--dart-define=OLIVE_BACKUP_INTERNET_REVIEWED=true`. A debug or
/// preview build may use the server destination (and says "not yet reviewed" on the adult screen).
const bool kBackupInternetEnabled =
    !bool.fromEnvironment('dart.vm.product') || bool.fromEnvironment('OLIVE_BACKUP_INTERNET_REVIEWED');

final RegExp _setRe = RegExp(r'^[0-9a-f]{32}$');
final RegExp _chunkRe = RegExp(r'^[0-9a-f]{64}$');
final RegExp _manifestRe = RegExp(r'^[0-9]{10}-[0-9a-f]{8}$');

bool isSetId(String s) => _setRe.hasMatch(s);
bool isChunkId(String s) => _chunkRe.hasMatch(s);
bool isManifestName(String s) => _manifestRe.hasMatch(s);

/// Why a destination refused or failed; [code] is for logic, never shown as is.
class BackupSinkException implements Exception {
  const BackupSinkException(this.code, [this.detail = '']);

  /// 'unreachable' (could not be asked, try again), 'refused' (asked and said no), 'full', 'bad_name',
  /// 'not_enabled' (the internet destination is compiled out), 'damaged'.
  final String code;
  final String detail;

  /// Worth trying again later without anyone changing anything.
  bool get transient => code == 'unreachable';

  @override
  String toString() => 'BackupSinkException($code)';
}

abstract class BackupSink {
  /// What a grown-up calls it: "a folder on this phone", "your family's server".
  String get label;

  /// Stable word for the status record: 'folder' | 'server' | 'memory'.
  String get kindWord;

  Future<bool> hasChunk(String set, String id);
  Future<void> putChunk(String set, String id, Uint8List bytes);
  Future<Uint8List?> getChunk(String set, String id);
  Future<void> deleteChunk(String set, String id);

  /// The commit. Written last.
  Future<void> putManifest(String set, String name, Uint8List bytes);
  Future<List<String>> listManifests(String set);
  Future<Uint8List?> getManifest(String set, String name);
  Future<void> deleteManifest(String set, String name);
}

void _check(String set, {String? chunk, String? manifest}) {
  if (!isSetId(set) || (chunk != null && !isChunkId(chunk)) || (manifest != null && !isManifestName(manifest))) {
    throw const BackupSinkException('bad_name');
  }
}

/// Everything in memory. For tests, and the stand-in for a destination.
class MemoryBackupSink implements BackupSink {
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
class DirectoryBackupSink implements BackupSink {
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
  Future<bool> hasChunk(String set, String id) {
    _check(set, chunk: id);
    return _io(() => _chunk(set, id).exists());
  }

  @override
  Future<void> putChunk(String set, String id, Uint8List bytes) {
    _check(set, chunk: id);
    return _io(() => _writeAtomic(_chunk(set, id), bytes));
  }

  @override
  Future<Uint8List?> getChunk(String set, String id) {
    _check(set, chunk: id);
    return _io(() async {
      final File f = _chunk(set, id);
      return await f.exists() ? f.readAsBytes() : null;
    });
  }

  @override
  Future<void> deleteChunk(String set, String id) {
    _check(set, chunk: id);
    return _io(() async {
      final File f = _chunk(set, id);
      if (await f.exists()) await f.delete();
    });
  }

  @override
  Future<void> putManifest(String set, String name, Uint8List bytes) {
    _check(set, manifest: name);
    return _io(() => _writeAtomic(_manifest(set, name), bytes));
  }

  @override
  Future<List<String>> listManifests(String set) {
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
  Future<Uint8List?> getManifest(String set, String name) {
    _check(set, manifest: name);
    return _io(() async {
      final File f = _manifest(set, name);
      return await f.exists() ? f.readAsBytes() : null;
    });
  }

  @override
  Future<void> deleteManifest(String set, String name) {
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

/// The family's server, over the contract in docs/planning/BACKUP-RESTORE-CLIENT.md. [token] gives the bearer for the
/// signed-in account (production passes the session's current token). Transient failures (no answer, 5xx, 429) are
/// retried [retries] times with a doubling pause, then raised as 'unreachable' so the run can carry on later; a 4xx is
/// 'refused' and never retried.
class ServerBackupSink implements BackupSink {
  ServerBackupSink({
    required this.baseUrl,
    required this.client,
    required this.token,
    this.label = "your family's server",
    this.retries = 2,
    this.pause = const Duration(milliseconds: 200),
  }) {
    if (!kBackupInternetEnabled) throw const BackupSinkException('not_enabled');
  }

  final String baseUrl;
  final http.Client client;
  final Future<String> Function() token;
  @override
  final String label;
  @override
  String get kindWord => 'server';
  final int retries;
  final Duration pause;

  Uri _u(String path) => Uri.parse('${baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl}$path');

  Future<http.Response> _send(String method, String path, {Uint8List? body, String? contentType}) async {
    Object? last;
    for (int attempt = 0; attempt <= retries; attempt++) {
      try {
        final http.Request req = http.Request(method, _u(path));
        req.headers['Authorization'] = 'Bearer ${await token()}';
        if (contentType != null) req.headers['Content-Type'] = contentType;
        if (body != null) req.bodyBytes = body;
        final http.Response res = await http.Response.fromStream(await client.send(req));
        if (res.statusCode == 429 || res.statusCode >= 500) {
          last = res.statusCode;
        } else {
          return res;
        }
      } on BackupSinkException {
        rethrow;
      } catch (e) {
        last = e;
      }
      if (attempt < retries) await Future<void>.delayed(pause * (1 << attempt));
    }
    throw BackupSinkException('unreachable', '$last');
  }

  Never _fail(http.Response r) {
    String err = '';
    try {
      final Object? j = jsonDecode(r.body);
      if (j is Map && j['error'] is String) err = j['error'] as String;
    } catch (_) {}
    if (r.statusCode == 507 || err == 'storage_full') throw const BackupSinkException('full');
    throw BackupSinkException('refused', '${r.statusCode}');
  }

  @override
  Future<bool> hasChunk(String set, String id) async {
    _check(set, chunk: id);
    final http.Response r = await _send('HEAD', '/v1/backup/$set/chunks/$id');
    if (r.statusCode == 200) return true;
    if (r.statusCode == 404) return false;
    _fail(r);
  }

  @override
  Future<void> putChunk(String set, String id, Uint8List bytes) async {
    _check(set, chunk: id);
    final http.Response r =
        await _send('PUT', '/v1/backup/$set/chunks/$id', body: bytes, contentType: 'application/octet-stream');
    if (r.statusCode != 200 && r.statusCode != 201 && r.statusCode != 204) _fail(r);
  }

  @override
  Future<Uint8List?> getChunk(String set, String id) async {
    _check(set, chunk: id);
    final http.Response r = await _send('GET', '/v1/backup/$set/chunks/$id');
    if (r.statusCode == 200) return r.bodyBytes;
    if (r.statusCode == 404) return null;
    _fail(r);
  }

  @override
  Future<void> deleteChunk(String set, String id) async {
    _check(set, chunk: id);
    final http.Response r = await _send('DELETE', '/v1/backup/$set/chunks/$id');
    if (r.statusCode != 200 && r.statusCode != 204 && r.statusCode != 404) _fail(r);
  }

  @override
  Future<void> putManifest(String set, String name, Uint8List bytes) async {
    _check(set, manifest: name);
    final http.Response r = await _send('PUT', '/v1/backup/$set/manifests/$name',
        body: bytes, contentType: 'application/octet-stream');
    if (r.statusCode != 200 && r.statusCode != 201 && r.statusCode != 204) _fail(r);
  }

  @override
  Future<List<String>> listManifests(String set) async {
    _check(set);
    final http.Response r = await _send('GET', '/v1/backup/$set/manifests');
    if (r.statusCode == 404) return <String>[];
    if (r.statusCode != 200) _fail(r);
    try {
      final Object? j = jsonDecode(r.body);
      final Object? names = j is Map ? j['manifests'] : null;
      if (names is! List) throw const BackupSinkException('damaged');
      return <String>[
        for (final Object? n in names)
          if (n is String && isManifestName(n)) n,
      ]..sort();
    } on BackupSinkException {
      rethrow;
    } catch (_) {
      throw const BackupSinkException('damaged');
    }
  }

  @override
  Future<Uint8List?> getManifest(String set, String name) async {
    _check(set, manifest: name);
    final http.Response r = await _send('GET', '/v1/backup/$set/manifests/$name');
    if (r.statusCode == 200) return r.bodyBytes;
    if (r.statusCode == 404) return null;
    _fail(r);
  }

  @override
  Future<void> deleteManifest(String set, String name) async {
    _check(set, manifest: name);
    final http.Response r = await _send('DELETE', '/v1/backup/$set/manifests/$name');
    if (r.statusCode != 200 && r.statusCode != 204 && r.statusCode != 404) _fail(r);
  }
}
