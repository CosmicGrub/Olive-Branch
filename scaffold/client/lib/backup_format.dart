// OLIVE BRANCH — what a backup IS: a snapshot of the on-device areas, sealed on the phone before it goes anywhere.
// UNVERIFIED on a device; pure Dart, runs headless in CI (client/test/backup_format_test.dart).
// Design: docs/planning/BACKUP-AND-RESTORE.md.
//
// THE SHAPE. Every catalogued area that belongs in this backup kind (backup_classes.dart) is read whole, written as
// canonical JSON (sorted keys, so the same data always has the same bytes), and the areas are laid end to end as one
// stream. The stream is cut into fixed 128 KiB pieces ("chunks"), the last padded up to a 32 KiB step so a size does
// not say how much she drew. Each chunk is sealed with AES-256-GCM under a key made for THIS backup:
//     key = HKDF( X25519(throwaway key, recipient PUBLIC key), set id, throwaway public key, backup kind )
// so the phone needs only the recipient's public half and keeps nothing that opens what it made. The chunk's name is the
// SHA-256 of its sealed bytes, which is how a half-sent or damaged chunk is noticed and how a transfer resumes.
//
// TWO PARTS BESIDE THE CHUNKS.
//   header    plain, small: format version, set id, kind, a coarse time, the throwaway public key, and the ordered list
//             of chunk names and sizes. Whoever keeps the backup (a folder, a drive, the family's server) needs only
//             this to store, count and resume it. It names no area, no child and no family.
//   manifest  sealed under the same key: which areas, how big, a SHA-256 of each area's canonical content, a sequence
//             number that only goes up, a plain label for the device that made it, and any area that could not be read.
//             Its associated data includes a hash of the header, so a header edited after the fact fails to open.
// A chunk's associated data names its set, kind and place in the order, so a chunk cannot be moved to another backup,
// another kind, or another position.
//
// WHAT THIS IS NOT. It is not signed by a device: a backup proves "someone holding the public key made this", which a
// phone that is stolen unlocked can do. It is never what grants authority; a restore brings records back and puts no
// device into the family (that is the recovery flow, not this file). Composition of vetted primitives, no outside
// review (decision D2).
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'backup_classes.dart';
import 'backup_keys.dart';
import 'device_keys.dart' show b64, unb64;
import 'local_services.dart';
import 'local_store.dart';

const int kBackupFormat = 1;
const int kChunkBytes = 128 * 1024;
const int kChunkPadStep = 32 * 1024;

/// Raised for anything wrong with a backup's bytes: the wrong key, damage, a different backup's pieces.
class BackupFormatException implements Exception {
  const BackupFormatException(this.code, this.message);

  /// 'header', 'key' (does not open with this key), 'chunk' (missing or damaged piece), 'manifest', 'area'.
  final String code;
  final String message;
  @override
  String toString() => 'BackupFormatException($code: $message)';
}

// ------------------------------------------------------------------ canonical JSON and hashes

/// JSON with every map's keys sorted, so equal data is equal bytes. Only plain JSON values are allowed.
String canonicalJson(Object? v) {
  final StringBuffer b = StringBuffer();
  void w(Object? x) {
    if (x is Map) {
      final List<String> keys = x.keys.cast<String>().toList()..sort();
      b.write('{');
      for (int i = 0; i < keys.length; i++) {
        if (i > 0) b.write(',');
        b.write(jsonEncode(keys[i]));
        b.write(':');
        w(x[keys[i]]);
      }
      b.write('}');
    } else if (x is List) {
      b.write('[');
      for (int i = 0; i < x.length; i++) {
        if (i > 0) b.write(',');
        w(x[i]);
      }
      b.write(']');
    } else {
      b.write(jsonEncode(x));
    }
  }

  w(v);
  return b.toString();
}

String _hex(List<int> b) => b.map((int x) => x.toRadixString(16).padLeft(2, '0')).join();

Future<String> sha256Hex(List<int> bytes) async => _hex((await Sha256().hash(bytes)).bytes);

/// The fingerprint of one area's content, the number a round trip must keep equal.
Future<String> areaContentHash(String namespace, Map<String, Object?> data) =>
    sha256Hex(utf8.encode('olive-area-v1\n$namespace\n${canonicalJson(data)}'));

/// One hash for a whole set of areas.
Future<String> setContentHash(Map<String, String> hashByNamespace) {
  final List<String> keys = hashByNamespace.keys.toList()..sort();
  return sha256Hex(utf8.encode('olive-set-v1\n${keys.map((String k) => '$k:${hashByNamespace[k]}').join('\n')}'));
}

// ------------------------------------------------------------------ naming

/// A parsed namespace name: whose it is and which catalogued area.
class NsRef {
  const NsRef(this.scope, this.ownerId, this.area);
  final LocalScope scope;
  final String ownerId;
  final String area;

  String get name => switch (scope) {
        LocalScope.child => 'child.$ownerId.$area',
        LocalScope.guardian => 'guardian.$ownerId.$area',
        LocalScope.device => 'device.$area',
      };

  NsRef withOwner(String id) => NsRef(scope, scope == LocalScope.device ? '' : id, area);

  /// Null for anything that is not a catalogued area's namespace (a restore's own undo copies, a stray file).
  static NsRef? parse(String name) {
    final List<String> p = name.split('.');
    if (p.length < 2) return null;
    final String area = p.last;
    final LocalDataEntry? e = localDataCatalogue.cast<LocalDataEntry?>().firstWhere(
        (LocalDataEntry? x) => x!.area == area,
        orElse: () => null);
    if (e == null) return null;
    switch (p.first) {
      case 'device':
        return p.length == 2 && e.scope == LocalScope.device ? NsRef(LocalScope.device, '', area) : null;
      case 'child':
        if (p.length < 3 || e.scope != LocalScope.child) return null;
        return NsRef(LocalScope.child, p.sublist(1, p.length - 1).join('.'), area);
      case 'guardian':
        if (p.length < 3 || e.scope != LocalScope.guardian) return null;
        return NsRef(LocalScope.guardian, p.sublist(1, p.length - 1).join('.'), area);
    }
    return null;
  }
}

NamespaceSpec specFor(NsRef r) {
  final LocalDataEntry e = localDataEntry(r.area);
  return NamespaceSpec(name: r.name, schema: e.schema, encrypted: e.encrypted, maxBytes: e.maxBytes);
}

// ------------------------------------------------------------------ the snapshot

class AreaSnapshot {
  AreaSnapshot(this.ref, this.schema, this.encrypted, this.data, this.hash, this.bytes);
  final NsRef ref;
  final int schema;
  final bool encrypted;
  final Map<String, Object?> data;
  final String hash;
  final Uint8List bytes;
  String get namespace => ref.name;
}

class BackupSnapshot {
  BackupSnapshot(this.kind, this.areas, this.unreadable, this.contentHash);
  final BackupKind kind;
  final List<AreaSnapshot> areas;

  /// Areas that exist but could not be read (damaged, or newer than this app). Never silently dropped: the manifest and
  /// the status line say so.
  final List<String> unreadable;
  final String contentHash;
  int get totalBytes => areas.fold(0, (int n, AreaSnapshot a) => n + a.bytes.length);
  bool get isEmpty => areas.isEmpty;
}

/// Reads every area of [kind] that has something in it. READ-ONLY: nothing here writes to the store.
Future<BackupSnapshot> captureSnapshot(LocalStore store, BackupKind kind) async {
  final List<AreaSnapshot> out = <AreaSnapshot>[];
  final List<String> unreadable = <String>[];
  for (final String name in await store.namespaces()) {
    final NsRef? ref = NsRef.parse(name);
    if (ref == null || !areaInBackup(ref.area, kind)) continue;
    try {
      final LocalNamespace ns = store.open(specFor(ref));
      final Map<String, Object?> data = await ns.snapshot();
      if (ns.recovery != RecoveryKind.none) {
        unreadable.add(name);
        continue;
      }
      if (data.isEmpty) continue;
      final Uint8List bytes = Uint8List.fromList(utf8.encode(canonicalJson(data)));
      final LocalDataEntry e = localDataEntry(ref.area);
      out.add(AreaSnapshot(ref, e.schema, e.encrypted, data, await areaContentHash(name, data), bytes));
    } on LocalStoreException {
      unreadable.add(name);
    }
  }
  out.sort((AreaSnapshot a, AreaSnapshot b) => a.namespace.compareTo(b.namespace));
  unreadable.sort();
  return BackupSnapshot(kind, out, unreadable,
      await setContentHash(<String, String>{for (final AreaSnapshot a in out) a.namespace: a.hash}));
}

// ------------------------------------------------------------------ sealing

Uint8List _u32(int v) => Uint8List.fromList(<int>[(v >> 24) & 255, (v >> 16) & 255, (v >> 8) & 255, v & 255]);
int _readU32(List<int> b, int i) => (b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3];

Uint8List _lv(List<List<int>> parts) {
  final BytesBuilder b = BytesBuilder();
  for (final List<int> p in parts) {
    b.add(_u32(p.length));
    b.add(p);
  }
  return b.toBytes();
}

Uint8List _chunkAad(String setId, BackupKind kind, int index) =>
    _lv(<List<int>>[utf8.encode('olive-chunk-v1'), utf8.encode(setId), utf8.encode(kind.word), _u32(index)]);

Uint8List _manifestAad(String setId, BackupKind kind, List<int> headerHash) =>
    _lv(<List<int>>[utf8.encode('olive-manifest-v1'), utf8.encode(setId), utf8.encode(kind.word), headerHash]);

Future<SecretKey> _contentKey(List<int> shared, String setId, List<int> ephPub, List<int> recipientPub, BackupKind kind) =>
    Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
        secretKey: SecretKey(shared),
        nonce: _lv(<List<int>>[utf8.encode(setId), ephPub, recipientPub]),
        info: utf8.encode('olive/backup/content/v1/${kind.word}'));

final AesGcm _aes = AesGcm.with256bits();

Future<Uint8List> _seal(SecretKey key, List<int> plain, List<int> aad, Random r) async {
  final List<int> nonce = List<int>.generate(12, (_) => r.nextInt(256));
  final SecretBox box = await _aes.encrypt(plain, secretKey: key, nonce: nonce, aad: aad);
  return Uint8List.fromList(box.concatenation());
}

Future<Uint8List> _open(SecretKey key, List<int> box, List<int> aad) async {
  final SecretBox parsed = SecretBox.fromConcatenation(box, nonceLength: 12, macLength: 16);
  return Uint8List.fromList(await _aes.decrypt(parsed, secretKey: key, aad: aad));
}

/// What a finished seal hands back besides the chunks (which went to [SealedSink.putChunk] one at a time).
class SealedSet {
  SealedSet(this.kind, this.setId, this.header, this.manifest, this.chunkIds, this.seq, this.createdMs, this.contentHash,
      this.areaCount, this.bytes);
  final BackupKind kind;
  final String setId;
  final Uint8List header;
  final Uint8List manifest;
  final List<String> chunkIds;
  final int seq;
  final int createdMs;
  final String contentHash;
  final int areaCount;
  final int bytes;
}

typedef ChunkSink = Future<void> Function(String chunkId, Uint8List bytes);

/// Seals [snapshot] to [recipientPublicKey]. Each sealed chunk goes to [onChunk] as soon as it exists, so a large
/// backup is never held whole in memory.
Future<SealedSet> sealSnapshot(
  BackupSnapshot snapshot,
  List<int> recipientPublicKey, {
  required ChunkSink onChunk,
  required int createdMs,
  required int seq,
  String from = 'A grown-up\'s phone',
  String? setId,
  Random? random,
}) async {
  final Random r = random ?? Random.secure();
  final String set = setId ?? _hex(List<int>.generate(16, (_) => r.nextInt(256)));
  final SimpleKeyPair eph = await X25519().newKeyPair();
  final SimplePublicKey ephPub = await eph.extractPublicKey();
  final SecretKey shared = await X25519()
      .sharedSecretKey(keyPair: eph, remotePublicKey: SimplePublicKey(recipientPublicKey, type: KeyPairType.x25519));
  final SecretKey cek = await _contentKey(await shared.extractBytes(), set, ephPub.bytes, recipientPublicKey, snapshot.kind);

  // The areas end to end, with where each one sits.
  final BytesBuilder stream = BytesBuilder();
  final List<Map<String, Object?>> areaRows = <Map<String, Object?>>[];
  for (final AreaSnapshot a in snapshot.areas) {
    areaRows.add(<String, Object?>{
      'ns': a.namespace,
      'area': a.ref.area,
      'schema': a.schema,
      'enc': a.encrypted,
      'keys': a.data.length,
      'off': stream.length,
      'len': a.bytes.length,
      'hash': a.hash,
    });
    stream.add(a.bytes);
  }
  final Uint8List all = stream.toBytes();

  final List<String> ids = <String>[];
  final List<List<Object>> headerChunks = <List<Object>>[];
  int index = 0;
  for (int off = 0; off < all.length || (off == 0 && index == 0); off += kChunkBytes) {
    final int end = min(off + kChunkBytes, all.length);
    final Uint8List piece = Uint8List.sublistView(all, off, end);
    final bool last = end >= all.length;
    final int framed = 4 + piece.length;
    final int padded = last ? ((framed + kChunkPadStep - 1) ~/ kChunkPadStep) * kChunkPadStep : framed;
    final Uint8List plain = Uint8List(padded)
      ..setRange(0, 4, _u32(piece.length))
      ..setRange(4, 4 + piece.length, piece);
    final Uint8List box = await _seal(cek, plain, _chunkAad(set, snapshot.kind, index), r);
    final String id = await sha256Hex(box);
    await onChunk(id, box);
    ids.add(id);
    headerChunks.add(<Object>[id, box.length]);
    index++;
    if (all.isEmpty) break;
  }

  final int coarse = (createdMs ~/ 60000) * 60000;
  final Uint8List header = Uint8List.fromList(utf8.encode(canonicalJson(<String, Object?>{
    'v': kBackupFormat,
    'set': set,
    'kind': snapshot.kind.word,
    'at': coarse,
    'eph': b64(ephPub.bytes),
    'chunks': headerChunks,
  })));
  final Uint8List headerHash = Uint8List.fromList((await Sha256().hash(header)).bytes);
  final String contentHash = snapshot.contentHash;
  final Uint8List manifestPlain = Uint8List.fromList(utf8.encode(canonicalJson(<String, Object?>{
    'v': kBackupFormat,
    'set': set,
    'kind': snapshot.kind.word,
    'at': createdMs,
    'seq': seq,
    'from': from,
    'areas': areaRows,
    'unreadable': snapshot.unreadable,
    'hash': contentHash,
    'bytes': all.length,
  })));
  final Uint8List manifest = await _seal(cek, manifestPlain, _manifestAad(set, snapshot.kind, headerHash), r);
  return SealedSet(snapshot.kind, set, header, manifest, ids, seq, createdMs, contentHash, snapshot.areas.length, all.length);
}

// ------------------------------------------------------------------ the plain header

/// A header read back and checked for shape (not yet opened: that needs the key).
class BackupHeader {
  BackupHeader._(this.bytes, this.kind, this.setId, this.atMs, this.ephemeral, this.chunks);
  final Uint8List bytes;
  final BackupKind kind;
  final String setId;
  final int atMs;
  final Uint8List ephemeral;
  final List<MapEntry<String, int>> chunks;

  List<String> get chunkIds => <String>[for (final MapEntry<String, int> c in chunks) c.key];

  static BackupHeader parse(Uint8List bytes) {
    try {
      final Object? j = jsonDecode(utf8.decode(bytes));
      if (j is! Map || j['v'] != kBackupFormat) throw const BackupFormatException('header', 'unknown format');
      final BackupKind? kind = BackupKind.fromWord(j['kind']);
      final Object? set = j['set'], at = j['at'], eph = j['eph'], chunks = j['chunks'];
      if (kind == null || set is! String || !RegExp(r'^[0-9a-f]{32}$').hasMatch(set)) {
        throw const BackupFormatException('header', 'bad identity');
      }
      if (at is! int || eph is! String || chunks is! List) throw const BackupFormatException('header', 'bad shape');
      final Uint8List e = unb64(eph);
      if (e.length != 32) throw const BackupFormatException('header', 'bad key');
      final List<MapEntry<String, int>> list = <MapEntry<String, int>>[];
      for (final Object? c in chunks) {
        if (c is! List || c.length != 2 || c[0] is! String || c[1] is! int) {
          throw const BackupFormatException('header', 'bad chunk list');
        }
        if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(c[0] as String)) throw const BackupFormatException('header', 'bad chunk name');
        list.add(MapEntry<String, int>(c[0] as String, c[1] as int));
      }
      if (list.isEmpty || list.length > 4096) throw const BackupFormatException('header', 'bad chunk count');
      return BackupHeader._(bytes, kind, set, at, e, list);
    } on BackupFormatException {
      rethrow;
    } catch (_) {
      throw const BackupFormatException('header', 'unreadable');
    }
  }
}

// ------------------------------------------------------------------ opening

class ManifestArea {
  ManifestArea(this.namespace, this.area, this.schema, this.encrypted, this.keys, this.offset, this.length, this.hash);
  final String namespace;
  final String area;
  final int schema;
  final bool encrypted;
  final int keys;
  final int offset;
  final int length;
  final String hash;
  NsRef? get ref => NsRef.parse(namespace);
}

class OpenedManifest {
  OpenedManifest(this.header, this.setId, this.kind, this.createdMs, this.seq, this.from, this.areas, this.unreadable,
      this.contentHash, this.streamBytes, this._cek);
  final BackupHeader header;
  final String setId;
  final BackupKind kind;
  final int createdMs;
  final int seq;
  final String from;
  final List<ManifestArea> areas;
  final List<String> unreadable;
  final String contentHash;
  final int streamBytes;
  final SecretKey _cek;
}

/// Opens a set's manifest with [key]. A wrong key, a header or manifest changed afterwards, or a set from another
/// family all end the same way: [BackupFormatException] with code 'key' or 'manifest'.
Future<OpenedManifest> openManifest(Uint8List headerBytes, Uint8List sealedManifest, BackupKeyPair key) async {
  final BackupHeader h = BackupHeader.parse(headerBytes);
  final SimpleKeyPair kp = await X25519().newKeyPairFromSeed(key.privateSeed);
  final SecretKey shared = await X25519().sharedSecretKey(
      keyPair: kp, remotePublicKey: SimplePublicKey(h.ephemeral, type: KeyPairType.x25519));
  final SecretKey cek = await _contentKey(await shared.extractBytes(), h.setId, h.ephemeral, key.publicKey, h.kind);
  final List<int> headerHash = (await Sha256().hash(headerBytes)).bytes;
  final Uint8List plain;
  try {
    plain = await _open(cek, sealedManifest, _manifestAad(h.setId, h.kind, headerHash));
  } catch (_) {
    throw const BackupFormatException('key', 'this key does not open this backup, or it was changed');
  }
  try {
    final Object? j = jsonDecode(utf8.decode(plain));
    if (j is! Map || j['v'] != kBackupFormat || j['set'] != h.setId || j['kind'] != h.kind.word) {
      throw const BackupFormatException('manifest', 'does not match its header');
    }
    final List<ManifestArea> areas = <ManifestArea>[];
    for (final Object? a in (j['areas'] as List)) {
      final Map<Object?, Object?> m = a as Map<Object?, Object?>;
      areas.add(ManifestArea(m['ns'] as String, m['area'] as String, m['schema'] as int, m['enc'] == true,
          m['keys'] as int, m['off'] as int, m['len'] as int, m['hash'] as String));
    }
    return OpenedManifest(h, h.setId, h.kind, j['at'] as int, j['seq'] as int, (j['from'] as String?) ?? '', areas,
        <String>[for (final Object? u in (j['unreadable'] as List)) u as String], j['hash'] as String,
        j['bytes'] as int, cek);
  } on BackupFormatException {
    rethrow;
  } catch (_) {
    throw const BackupFormatException('manifest', 'unreadable');
  }
}

typedef ChunkSource = Future<Uint8List?> Function(String chunkId);

/// One opened area's data, checked against the hash the manifest recorded.
class RestoredArea {
  RestoredArea(this.entry, this.data);
  final ManifestArea entry;
  final Map<String, Object?> data;
}

/// Fetches, checks and opens every chunk, then slices the stream back into areas and checks each area's hash. Any
/// missing or damaged chunk, or an area that does not hash to what the manifest recorded, is a [BackupFormatException]:
/// a set is whole or it is not used.
Future<List<RestoredArea>> readAreas(OpenedManifest m, ChunkSource fetch) async {
  final BytesBuilder stream = BytesBuilder();
  for (int i = 0; i < m.header.chunks.length; i++) {
    final MapEntry<String, int> c = m.header.chunks[i];
    final Uint8List? box = await fetch(c.key);
    if (box == null || box.length != c.value || await sha256Hex(box) != c.key) {
      throw BackupFormatException('chunk', 'piece ${i + 1} of ${m.header.chunks.length} is missing or damaged');
    }
    final Uint8List plain;
    try {
      plain = await _open(m._cek, box, _chunkAad(m.setId, m.kind, i));
    } catch (_) {
      throw BackupFormatException('chunk', 'piece ${i + 1} does not belong to this backup');
    }
    final int len = _readU32(plain, 0);
    if (len < 0 || 4 + len > plain.length) throw BackupFormatException('chunk', 'piece ${i + 1} is the wrong size');
    stream.add(Uint8List.sublistView(plain, 4, 4 + len));
  }
  final Uint8List all = stream.toBytes();
  if (all.length != m.streamBytes) throw const BackupFormatException('chunk', 'the pieces do not add up');
  final List<RestoredArea> out = <RestoredArea>[];
  for (final ManifestArea a in m.areas) {
    if (a.offset < 0 || a.length < 0 || a.offset + a.length > all.length) {
      throw const BackupFormatException('area', 'an area runs past the end');
    }
    final Uint8List bytes = Uint8List.sublistView(all, a.offset, a.offset + a.length);
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(bytes));
    } catch (_) {
      throw const BackupFormatException('area', 'an area is not readable');
    }
    if (json is! Map<String, dynamic>) throw const BackupFormatException('area', 'an area has the wrong shape');
    final Map<String, Object?> data = Map<String, Object?>.from(json);
    if (await areaContentHash(a.namespace, data) != a.hash) {
      throw const BackupFormatException('area', 'an area does not match its fingerprint');
    }
    out.add(RestoredArea(a, data));
  }
  return out;
}
