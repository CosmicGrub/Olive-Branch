// OLIVE BRANCH — LocalStore: the on-device, offline-first durable store.
// No longer UNVERIFIED — verified by CI (client/test/local_store_test.dart).
//
// WHY THIS EXISTS. Until this file, the client had no durable storage at all
// (pubspec carried only flutter_secure_storage for the device credential and
// path_provider for one export). Sixteen shipped screens kept their data in
// memory and lost it on exit. The owner's direction (2026-11-07) is to move
// AWAY from online features for now and build the offline-first, on-device
// foundation. This is that foundation: small, dependency-light, atomic,
// versioned, and honest about what it holds.
//
// SHAPE.
//  - A LocalStore holds NAMESPACES. A namespace is ONE JSON document file
//    (`<name>.json` under the app's private documents directory) holding a map
//    of string key -> JSON value. get/put/delete/list work within one
//    namespace. Namespaces are named `child.<childId>.<area>`,
//    `guardian.<guardianId>.<area>` or `device.<area>` (local_services.dart
//    builds the names), so one device can hold several child profiles later
//    and one child's data is never reachable through another's name.
//  - ATOMIC WRITES. A write goes to `<name>.json.tmp`, is flushed, then
//    renamed over `<name>.json`. A crash mid-write leaves the previous
//    complete file in place; a stale `.tmp` is never read.
//  - VERSIONED. Every file records the schema version it was written at. A
//    namespace declares its current schema and a `migrations` map (version N
//    -> a function turning an N-shaped document into an N+1-shaped one); older
//    files are migrated on load and rewritten at the new version.
//  - CORRUPTION IS SAFE, NEVER FATAL. A file that is unreadable (bad JSON,
//    wrong shape, failed authentication, written by a NEWER app, or a missing
//    migration step) is copied to `quarantine/` (kept, never deleted, so it can
//    be recovered by hand) and the namespace starts empty. The app keeps
//    running; [LocalNamespace.recovery] says what happened so a screen can
//    be gentle about it. Nothing here ever throws on a damaged file.
//  - BOUNDED. Each namespace has a byte ceiling; a write that would exceed it
//    is refused with [LocalStoreFull] and leaves the stored data untouched.
//    Nothing is ever silently evicted.
//  - PRIVATE NAMESPACES ARE ENCRYPTED. A namespace declared `encrypted` is
//    sealed with AES-256-GCM (store_cipher.dart) before it touches disk, with
//    the namespace name bound in as associated data so a file cannot be moved
//    between namespaces. The key lives in flutter_secure_storage
//    (Keystore/Keychain), never on disk beside the data. The journal (P7) and
//    everything in Parent Learn use this option.
//  - PLUGGABLE BACKEND. [StoreBackend] is the only thing that touches a disk:
//    [DirectoryStoreBackend] for the app, [MemoryStoreBackend] for tests (and
//    for the offline preview before a documents directory exists).
//
// WHAT IT IS NOT. It is not synced, not part of court export, and not read by
// any other surface. It stores no scores, streaks, counters or rankings (P2) —
// each repository (local_repositories.dart) decides what to keep and that rule
// is asserted in its tests. It never stores coordinates (P3).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'store_cipher.dart';

/// Base class for everything this store refuses on purpose.
class LocalStoreException implements Exception {
  const LocalStoreException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => 'LocalStoreException($code: $message)';
}

/// The namespace would pass its byte ceiling. The stored data is untouched.
class LocalStoreFull extends LocalStoreException {
  const LocalStoreFull(String namespace, int limit)
      : super('full', 'namespace $namespace is at its $limit byte limit');
}

/// A name or key that is not allowed (see [isValidNamespaceName]/[isValidKey]).
class LocalStoreBadName extends LocalStoreException {
  const LocalStoreBadName(String what) : super('bad_name', what);
}

/// A value that is not plain JSON (a Dart object, NaN, a cycle, ...).
class LocalStoreNotJson extends LocalStoreException {
  const LocalStoreNotJson(String key) : super('not_json', 'value for $key is not plain JSON');
}

final RegExp _nameRe = RegExp(r'^[a-z0-9][a-z0-9._-]{0,119}$');
final RegExp _keyRe = RegExp(r'^[A-Za-z0-9][A-Za-z0-9:._-]{0,127}$');

/// Lower-case letters, digits, dot, dash and underscore; starts with a letter
/// or digit; at most 120 characters. No separators, so a name can never walk
/// out of the store directory.
bool isValidNamespaceName(String name) => _nameRe.hasMatch(name) && !name.contains('..');

bool isValidKey(String key) => _keyRe.hasMatch(key);

/// What the store did about a damaged file the last time a namespace loaded.
enum RecoveryKind {
  /// Nothing went wrong (including "no file yet").
  none,
  /// The file could not be parsed or authenticated; a copy was quarantined.
  corrupt,
  /// The file was written by a NEWER schema than this app understands; a copy
  /// was quarantined and the namespace started empty.
  newerSchema,
  /// An older file needed a migration step this app does not have.
  missingMigration,
}

typedef Migration = Map<String, Object?> Function(Map<String, Object?> data);

/// Everything a namespace needs to be opened: its name, how its documents are
/// shaped over time, and how big it may grow.
class NamespaceSpec {
  const NamespaceSpec({
    required this.name,
    this.schema = 1,
    this.migrations = const <int, Migration>{},
    this.encrypted = false,
    this.maxBytes = 1024 * 1024,
  });

  final String name;

  /// The CURRENT schema version. Bump it and add a [migrations] entry when a
  /// document's shape changes.
  final int schema;

  /// `migrations[n]` upgrades a version-n document to version n+1.
  final Map<int, Migration> migrations;
  final bool encrypted;

  /// Ceiling for the serialized document (before encryption overhead).
  final int maxBytes;
}

/// The only layer that touches a disk. Every method works on whole documents.
abstract class StoreBackend {
  Future<Uint8List?> read(String name);
  Future<void> writeAtomic(String name, Uint8List bytes);
  Future<void> delete(String name);
  Future<List<String>> names();
  Future<void> quarantine(String name, Uint8List bytes, String reason);
  Future<int> quarantineCount();
  /// Removes EVERY document, including quarantined copies.
  Future<void> deleteEverything();
}

/// Holds everything in a map. For tests and for the offline preview build.
class MemoryStoreBackend implements StoreBackend {
  final Map<String, Uint8List> _files = <String, Uint8List>{};
  final List<Uint8List> _quarantine = <Uint8List>[];

  /// Test hook: what is actually "on disk" for [name] (for ciphertext checks).
  Uint8List? rawFor(String name) => _files[name];

  /// Test hook: plants raw bytes, e.g. a damaged file.
  void plant(String name, Uint8List bytes) => _files[name] = bytes;

  @override
  Future<Uint8List?> read(String name) async => _files[name];
  @override
  Future<void> writeAtomic(String name, Uint8List bytes) async =>
      _files[name] = Uint8List.fromList(bytes);
  @override
  Future<void> delete(String name) async => _files.remove(name);
  @override
  Future<List<String>> names() async => _files.keys.toList()..sort();
  @override
  Future<void> quarantine(String name, Uint8List bytes, String reason) async =>
      _quarantine.add(Uint8List.fromList(bytes));
  @override
  Future<int> quarantineCount() async => _quarantine.length;
  @override
  Future<void> deleteEverything() async {
    _files.clear();
    _quarantine.clear();
  }
}

/// Files under [root]: `<name>.json`, `<name>.json.tmp` while writing, and
/// `quarantine/<name>.<millis>.<reason>`.
class DirectoryStoreBackend implements StoreBackend {
  DirectoryStoreBackend(this.root, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;
  final Directory root;
  final DateTime Function() _clock;

  File _file(String name) => File('${root.path}${Platform.pathSeparator}$name.json');
  Directory get _quarantineDir => Directory('${root.path}${Platform.pathSeparator}quarantine');

  @override
  Future<Uint8List?> read(String name) async {
    final File f = _file(name);
    if (!await f.exists()) return null;
    return f.readAsBytes();
  }

  @override
  Future<void> writeAtomic(String name, Uint8List bytes) async {
    await root.create(recursive: true);
    final File tmp = File('${_file(name).path}.tmp');
    final RandomAccessFile h = await tmp.open(mode: FileMode.write);
    try {
      await h.writeFrom(bytes);
      await h.flush();
    } finally {
      await h.close();
    }
    // Rename over the live file: the old complete document stays in place
    // until the new complete one replaces it. A leftover .tmp is never read.
    await tmp.rename(_file(name).path);
  }

  @override
  Future<void> delete(String name) async {
    final File f = _file(name);
    if (await f.exists()) await f.delete();
    final File tmp = File('${f.path}.tmp');
    if (await tmp.exists()) await tmp.delete();
  }

  @override
  Future<List<String>> names() async {
    if (!await root.exists()) return <String>[];
    final List<String> out = <String>[];
    await for (final FileSystemEntity e in root.list()) {
      if (e is! File) continue;
      final String base = e.uri.pathSegments.last;
      if (base.endsWith('.json')) out.add(base.substring(0, base.length - '.json'.length));
    }
    out.sort();
    return out;
  }

  @override
  Future<void> quarantine(String name, Uint8List bytes, String reason) async {
    await _quarantineDir.create(recursive: true);
    final int t = _clock().millisecondsSinceEpoch;
    await File('${_quarantineDir.path}${Platform.pathSeparator}$name.$t.$reason').writeAsBytes(bytes);
  }

  @override
  Future<int> quarantineCount() async {
    if (!await _quarantineDir.exists()) return 0;
    int n = 0;
    await for (final FileSystemEntity e in _quarantineDir.list()) {
      if (e is File) n++;
    }
    return n;
  }

  @override
  Future<void> deleteEverything() async {
    if (await root.exists()) await root.delete(recursive: true);
  }
}

/// A converter between a typed value and plain JSON.
class StoreCodec<T> {
  const StoreCodec({required this.encode, required this.decode});
  final Object? Function(T value) encode;

  /// May throw on a value it cannot read; [LocalNamespace.getTyped] treats a
  /// throw as "absent", never as a crash.
  final T Function(Object? json) decode;
}

/// One open namespace. Obtain it from [LocalStore.open]; do not construct it.
class LocalNamespace {
  LocalNamespace._(this._store, this.spec);
  final LocalStore _store;
  final NamespaceSpec spec;

  Map<String, Object?>? _cache;
  Future<void> _chain = Future<void>.value();
  RecoveryKind _recovery = RecoveryKind.none;

  /// What happened to a damaged file the last time this namespace loaded.
  RecoveryKind get recovery => _recovery;

  Future<T> _locked<T>(Future<T> Function() body) {
    final Completer<T> done = Completer<T>();
    _chain = _chain.then((_) async {
      try {
        done.complete(await body());
      } catch (e, s) {
        done.completeError(e, s);
      }
    });
    return done.future;
  }

  Future<Map<String, Object?>> _load() async {
    final Map<String, Object?>? cached = _cache;
    if (cached != null) return cached;
    final Uint8List? raw = await _store.backend.read(spec.name);
    if (raw == null) return _cache = <String, Object?>{};
    final _Loaded loaded = await _store._decode(spec, raw);
    _recovery = loaded.recovery;
    if (loaded.recovery != RecoveryKind.none) {
      await _store.backend.quarantine(spec.name, raw, loaded.recovery.name);
    }
    _cache = loaded.data;
    if (loaded.rewrite) await _flush(loaded.data);
    return _cache!;
  }

  /// [json] is [data] already serialised, when the caller has just done it (a
  /// put measures the document against its ceiling, and must not serialise a
  /// multi-hundred-KB document a second time to write it).
  Future<void> _flush(Map<String, Object?> data, {String? json}) async {
    final Uint8List bytes = await _store._encode(spec, data, json: json);
    await _store.backend.writeAtomic(spec.name, bytes);
  }

  /// The JSON value stored under [key], or null. The result is a private copy.
  Future<Object?> get(String key) => _locked(() async {
        _checkKey(key);
        final Object? v = (await _load())[key];
        return v == null ? null : jsonDecode(jsonEncode(v));
      });

  /// Stores [value] (plain JSON only) under [key]. Refused with
  /// [LocalStoreFull] — leaving the stored data untouched — past the ceiling.
  Future<void> put(String key, Object? value) => _locked(() async {
        _checkKey(key);
        final Object? plain = _plainJson(key, value);
        final Map<String, Object?> data = await _load();
        final Map<String, Object?> next = <String, Object?>{...data, key: plain};
        final String json = jsonEncode(next);
        if (utf8.encode(json).length > spec.maxBytes) {
          throw LocalStoreFull(spec.name, spec.maxBytes);
        }
        await _flush(next, json: json);
        _cache = next;
      });

  /// Removes [key]. Deleting an absent key is a no-op.
  Future<void> delete(String key) => _locked(() async {
        _checkKey(key);
        final Map<String, Object?> data = await _load();
        if (!data.containsKey(key)) return;
        final Map<String, Object?> next = <String, Object?>{...data}..remove(key);
        await _flush(next);
        _cache = next;
      });

  /// Every key, sorted.
  Future<List<String>> list() => _locked(() async => (await _load()).keys.toList()..sort());

  /// Removes every key (the namespace file itself is deleted).
  Future<void> clear() => _locked(() async {
        await _store.backend.delete(spec.name);
        _cache = <String, Object?>{};
        _recovery = RecoveryKind.none;
      });

  /// Typed read. A value this codec cannot decode is treated as absent.
  Future<T?> getTyped<T>(String key, StoreCodec<T> codec) async {
    final Object? json = await get(key);
    if (json == null) return null;
    try {
      return codec.decode(json);
    } catch (_) {
      return null;
    }
  }

  Future<void> putTyped<T>(String key, T value, StoreCodec<T> codec) =>
      put(key, codec.encode(value));

  /// Every value that decodes, keyed in key order. Undecodable ones are skipped.
  Future<List<T>> listTyped<T>(StoreCodec<T> codec) async {
    final List<T> out = <T>[];
    for (final String k in await list()) {
      final T? v = await getTyped<T>(k, codec);
      if (v != null) out.add(v);
    }
    return out;
  }

  void _forget() => _cache = null;

  static void _checkKey(String key) {
    if (!isValidKey(key)) throw LocalStoreBadName('bad key "$key"');
  }

  static Object? _plainJson(String key, Object? value) {
    try {
      return jsonDecode(jsonEncode(value));
    } catch (_) {
      throw LocalStoreNotJson(key);
    }
  }
}

class _Loaded {
  const _Loaded(this.data, this.recovery, {this.rewrite = false});
  final Map<String, Object?> data;
  final RecoveryKind recovery;
  final bool rewrite;
}

/// The store. One per app; namespaces are opened on demand and cached.
class LocalStore {
  LocalStore({required this.backend, this.cipher});
  final StoreBackend backend;

  /// Required to open an `encrypted` namespace. Null means private namespaces
  /// cannot be opened (opening one throws), never that they fall back to
  /// plaintext.
  final StoreCipher? cipher;

  final Map<String, LocalNamespace> _open = <String, LocalNamespace>{};

  static const int _envelopeVersion = 1;

  /// Opens (or returns the already-open) namespace for [spec]. The same name
  /// must always be opened with the same encryption setting.
  LocalNamespace open(NamespaceSpec spec) {
    if (!isValidNamespaceName(spec.name)) throw LocalStoreBadName('bad namespace "${spec.name}"');
    if (spec.encrypted && cipher == null) {
      throw const LocalStoreException(
          'no_cipher', 'an encrypted namespace needs a StoreCipher; refusing to fall back to plaintext');
    }
    final LocalNamespace? existing = _open[spec.name];
    if (existing != null) {
      if (existing.spec.encrypted != spec.encrypted) {
        throw LocalStoreBadName('namespace ${spec.name} reopened with a different encryption setting');
      }
      return existing;
    }
    return _open[spec.name] = LocalNamespace._(this, spec);
  }

  /// Every namespace that currently has a document on disk.
  Future<List<String>> namespaces() => backend.names();

  /// How many damaged documents are held in quarantine.
  Future<int> quarantined() => backend.quarantineCount();

  /// Deletes every document whose name starts with [prefix] (for example
  /// `child.abc.` to forget one child profile). Quarantined copies are kept.
  Future<void> deleteWithPrefix(String prefix) async {
    for (final String n in await backend.names()) {
      if (n.startsWith(prefix)) await backend.delete(n);
    }
    for (final MapEntry<String, LocalNamespace> e in _open.entries) {
      if (e.key.startsWith(prefix)) e.value._forget();
    }
  }

  /// Deletes EVERYTHING this store holds — documents and quarantine — and
  /// forgets every in-memory cache. The encryption key is the caller's to drop
  /// (see [StoreCipherKeyring.erase]).
  Future<void> wipe() async {
    await backend.deleteEverything();
    for (final LocalNamespace n in _open.values) {
      n._forget();
      n._recovery = RecoveryKind.none;
    }
  }

  /// The file bytes for [data]. The document is serialised once (or not at all
  /// when the caller passes [json], its own serialisation of [data]) and the
  /// small envelope header is spliced around it as text; the result is the
  /// same JSON the old build wrote, key order included.
  Future<Uint8List> _encode(NamespaceSpec spec, Map<String, Object?> data, {String? json}) async {
    final String dataJson = json ?? jsonEncode(data);
    final String head =
        '{"olive_store":$_envelopeVersion,"schema":${spec.schema},"enc":${spec.encrypted},';
    if (spec.encrypted) {
      final Uint8List plain = Uint8List.fromList(utf8.encode(dataJson));
      final Uint8List box = await cipher!.seal(plain, utf8.encode(spec.name));
      return Uint8List.fromList(utf8.encode('$head"box":"${base64Encode(box)}"}'));
    }
    return Uint8List.fromList(utf8.encode('$head"data":$dataJson}'));
  }

  Future<_Loaded> _decode(NamespaceSpec spec, Uint8List raw) async {
    const _Loaded empty = _Loaded(<String, Object?>{}, RecoveryKind.corrupt);
    try {
      final Object? parsed = jsonDecode(utf8.decode(raw));
      if (parsed is! Map<String, dynamic>) return empty;
      if (parsed['olive_store'] != _envelopeVersion) return empty;
      final Object? schema = parsed['schema'];
      if (schema is! int || schema < 1) return empty;
      final bool enc = parsed['enc'] == true;
      // A file that disagrees about encryption is not trusted either way: a
      // plaintext file in a namespace declared private is never read as data.
      if (enc != spec.encrypted) return empty;
      Map<String, Object?> data;
      if (enc) {
        final Object? box = parsed['box'];
        if (box is! String) return empty;
        final Uint8List plain = await cipher!.open(
            Uint8List.fromList(base64Decode(box)), utf8.encode(spec.name));
        final Object? inner = jsonDecode(utf8.decode(plain));
        if (inner is! Map<String, dynamic>) return empty;
        data = Map<String, Object?>.from(inner);
      } else {
        final Object? inner = parsed['data'];
        if (inner is! Map<String, dynamic>) return empty;
        data = Map<String, Object?>.from(inner);
      }
      if (schema > spec.schema) {
        return const _Loaded(<String, Object?>{}, RecoveryKind.newerSchema);
      }
      bool migrated = false;
      for (int v = schema; v < spec.schema; v++) {
        final Migration? step = spec.migrations[v];
        if (step == null) {
          return const _Loaded(<String, Object?>{}, RecoveryKind.missingMigration);
        }
        data = step(data);
        migrated = true;
      }
      return _Loaded(data, RecoveryKind.none, rewrite: migrated);
    } catch (_) {
      return empty;
    }
  }
}
