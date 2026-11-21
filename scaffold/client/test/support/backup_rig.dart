// Test support for the backup client: phones and tablets built over in-memory stores, and a fake family server that
// speaks the real route shapes (a stand-in for server/family_backup_routes.mjs, checked against golden vectors made by
// the real server code in backup_server_test.dart).
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:olive_client/api_client.dart' show ApiException;
import 'package:olive_client/backup_crypto.dart';
import 'package:olive_client/backup_engine.dart';
import 'package:olive_client/backup_server.dart';
import 'package:olive_client/backup_service.dart';
import 'package:olive_client/backup_state.dart';
import 'package:olive_client/device_keys.dart';
import 'package:olive_client/local_services.dart';
import 'package:olive_client/local_store.dart';
import 'package:olive_client/sha256.dart';
import 'package:olive_client/store_cipher.dart';

/// One phone or tablet: its own store, its own writing key, its own staging.
class Rig {
  Rig._(this.services, this.writer, this.svc, this.backend, this.clock);
  final LocalServices services;
  final DeviceKey writer;
  final BackupService svc;
  final MemoryStoreBackend backend;
  final TestClock clock;

  BackupStateStore get state => svc.state;
  BackupKind get kind => svc.kind;

  static Future<Rig> make({
    BackupRole role = BackupRole.guardian,
    String child = 'ivy',
    String guardian = 'mom',
    int seed = 1,
    BackupServerApi? api,
    MemoryStoreBackend? backend,
    TestClock? clock,
  }) async {
    final MemoryStoreBackend be = backend ?? MemoryStoreBackend();
    final LocalServices s = LocalServices(
      store: LocalStore(backend: be, cipher: AesGcmStoreCipher(AesGcmStoreCipher.newKey())),
      childId: child,
      guardianId: guardian,
    );
    final DeviceKey key = await DeviceKey.loadOrCreate(MemoryDeviceKeyRepository(),
        seedForTest: List<int>.generate(32, (int i) => (seed * 7 + i) & 0xff));
    final TestClock c = clock ?? TestClock();
    final BackupService svc = BackupService(
        services: s, writer: key, role: role, clock: c.now, random: Random(seed), serverApi: () => api);
    return Rig._(s, key, svc, be, c);
  }

  /// Writes a document into a catalogued area (as the guardian or the child this rig is).
  Future<void> put(String area, Map<String, Object?> data, {String? owner}) async {
    final LocalNamespace ns = services.area(area, ownerId: owner);
    for (final MapEntry<String, Object?> e in data.entries) {
      await ns.put(e.key, e.value);
    }
  }

  /// Namespace -> content hash for what a backup of this rig's kind takes.
  Future<Map<String, String>> hashes() => svc.engine.areaHashes(kind);

  /// Every stored document, as the raw bytes on disk (to prove nothing readable is there).
  Future<Map<String, Uint8List>> rawDocs() async => <String, Uint8List>{
        for (final String n in await services.store.namespaces()) n: (await services.store.readRaw(n))!,
      };
}

class TestClock {
  DateTime t = DateTime.utc(2026, 11, 21, 12);
  DateTime now() => t;
  void advance(Duration d) => t = t.add(d);
}

/// A store backend that can be told to start failing, to stand in for a process killed mid write.
class FlakyBackend extends MemoryStoreBackend {
  int writes = 0;

  /// The write number (1-based, counting from [arm]) at which every write from then on throws.
  int? dieAtWrite;
  int _armedFrom = 0;
  void arm(int n) {
    dieAtWrite = n;
    _armedFrom = writes;
  }

  void heal() => dieAtWrite = null;

  @override
  Future<void> writeAtomic(String name, Uint8List bytes) async {
    writes++;
    if (dieAtWrite != null && writes - _armedFrom >= dieAtWrite!) throw const LocalStoreException('write', 'killed');
    return super.writeAtomic(name, bytes);
  }

  @override
  Future<void> delete(String name) async {
    if (dieAtWrite != null && writes - _armedFrom >= dieAtWrite!) throw const LocalStoreException('write', 'killed');
    return super.delete(name);
  }
}

String hex(List<int> b) => hexString(b);

// ----------------------------------------------------------------------------------------------------------------------
// the fake family server

class FakeVersion {
  FakeVersion(this.seq, this.prev, this.chain, this.blobSha, this.size, this.chunkSize, this.chunkCount, this.manifest,
      this.signature, this.blob);
  final int seq, size, chunkSize, chunkCount;
  final String prev, chain, blobSha;
  final Uint8List manifest, signature;
  Uint8List blob;
  String state = 'live';
}

class FakeUpload {
  FakeUpload(this.id, this.ref, this.baseSeq, this.prev, this.chain, this.blobSha, this.size, this.chunkSize,
      this.chunkCount, this.manifest, this.signature);
  final String id, ref, prev, chain, blobSha;
  final int baseSeq, size, chunkSize, chunkCount;
  final Uint8List manifest, signature;
  final Map<int, Uint8List> chunks = <int, Uint8List>{};
  String state = 'open';
}

ApiException _err(int status, String code) => ApiException(status, code);

/// A family server with one vault. Chain and proof are checked the way the real server checks them: the link and the
/// blob hash on commit, the recovery key's signature on a restore request. It cannot check a writer's signature (it has
/// no family key), exactly like the real one.
class FakeBackupServer implements BackupServerApi {
  FakeBackupServer({this.userId = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee', this.vaultId = '11111111-2222-4333-8444-555555555555'});
  final String userId;
  final String vaultId;
  DateTime clock = DateTime.utc(2026, 11, 21, 12);
  bool vaultExists = false;
  Uint8List? verifier;
  final List<FakeVersion> versions = <FakeVersion>[];
  final Map<String, FakeUpload> uploads = <String, FakeUpload>{};
  int maxChunk = 1024 * 1024;
  int keepLive = 3;
  int _n = 0;

  /// Test hooks: fail the Nth chunk PUT (1-based, counted over the whole run) with a dropped connection.
  int? failPutAt;
  int puts = 0;
  bool offline = false;

  /// Test hook: runs just before a commit is checked (to let another phone commit first).
  Future<void> Function()? beforeCommit;
  final List<String> log = <String>[];

  // restore
  final Map<String, Uint8List> _challenges = <String, Uint8List>{};
  Map<String, Object?>? restore; // id, state, notBefore, approvalRequired, approved, token, requestDevice
  int waitHours = 72;
  bool approvalRequired = false;
  String deviceOfRestore = '';

  String _id(String p) => '$p-${(_n++).toString().padLeft(8, '0')}';

  Map<String, dynamic> _versionOut(FakeVersion v) => <String, dynamic>{
        'seq': v.seq,
        'prevChainHash': v.prev,
        'chainHash': v.chain,
        'blobSha256': v.blobSha,
        'sizeBytes': v.size,
        'chunkSize': v.chunkSize,
        'chunkCount': v.chunkCount,
        'manifest': base64.encode(v.manifest),
        'signature': base64.encode(v.signature),
        'state': v.state,
      };

  Map<String, dynamic>? get _head => versions.isEmpty ? null : <String, dynamic>{'seq': versions.last.seq, 'chainHash': versions.last.chain};

  // --- tamper hooks -------------------------------------------------------------------------------------------------
  void flipBlobByte(int seq, int at) {
    final FakeVersion v = versions.firstWhere((FakeVersion x) => x.seq == seq);
    v.blob = Uint8List.fromList(v.blob)..[at] ^= 0x01;
  }

  void dropVersion(int seq) => versions.removeWhere((FakeVersion v) => v.seq == seq);
  void dropNewest() => versions.removeLast();
  Uint8List blobOf(int seq) => versions.firstWhere((FakeVersion x) => x.seq == seq).blob;
  List<int> get seqs => <int>[for (final FakeVersion v in versions) v.seq];

  /// A user-visible phase for the restore, the way the real server names it.
  void approve() => restore!['approved'] = true;
  void cancelRestore() => restore!['state'] = 'cancelled';

  Map<String, dynamic> _restoreOut() {
    final Map<String, Object?> r = restore!;
    String phase = r['state'] as String;
    if (phase == 'pending') {
      if (r['token'] != null) {
        phase = 'token_issued';
      } else if (clock.isBefore(r['notBefore'] as DateTime)) {
        phase = 'waiting';
      } else if (r['approvalRequired'] == true && r['approved'] != true) {
        phase = 'needs_yes';
      } else {
        phase = 'ready';
      }
    }
    return <String, dynamic>{
      'restoreId': r['id'],
      'phase': phase,
      'notBefore': (r['notBefore'] as DateTime).toIso8601String(),
      'waitHours': r['waitHours'],
      'approvalRequired': r['approvalRequired'],
      'approved': r['approved'],
    };
  }

  @override
  Future<Map<String, dynamic>> send(String method, String path,
      {Map<String, dynamic>? body, Map<String, String>? query, Map<String, String>? headers}) async {
    if (offline) throw StateError('connection refused');
    log.add('$method $path');
    final List<String> p = path.split('/').where((String s) => s.isNotEmpty).toList(); // v1 backup ...
    if (p.length < 3) throw _err(404, 'not_found');
    final List<String> r = p.sublist(2);
    if (method == 'GET' && r.length == 1 && r[0] == 'limits') {
      return <String, dynamic>{'maxChunkBytes': maxChunk, 'maxVersionBytes': 64 * 1024 * 1024, 'quotaBytes': 256 * 1024 * 1024};
    }
    if (r[0] == 'vaults' && r.length == 1) {
      if (method == 'GET') {
        return <String, dynamic>{
          'vaults': vaultExists ? <Object>[<String, dynamic>{'vaultId': vaultId, 'state': 'active'}] : <Object>[],
          'joinable': <Object>[],
          'helperFor': <Object>[],
        };
      }
      if (vaultExists) throw _err(409, 'join_existing_vault');
      final String? v = body?['recoveryVerifier'] as String?;
      if (v == null || !RegExp(r'^[0-9a-f]{64}$').hasMatch(v)) throw _err(400, 'recovery_verifier_invalid');
      if (body?['pin'] != '2468') throw _err(403, 'pin_invalid');
      vaultExists = true;
      verifier = Uint8List.fromList(<int>[for (int i = 0; i < 64; i += 2) int.parse(v.substring(i, i + 2), radix: 16)]);
      return <String, dynamic>{'vaultId': vaultId};
    }
    if (r.length < 3 || r[0] != 'vaults' || r[1] != vaultId) throw _err(404, 'vault_not_found');
    final String what = r[2];
    if (what == 'versions' && method == 'GET') {
      final int after = int.parse(query?['after'] ?? '0');
      final int limit = int.parse(query?['limit'] ?? '100');
      final List<FakeVersion> rows = <FakeVersion>[for (final FakeVersion v in versions) if (v.seq > after) v];
      return <String, dynamic>{
        'head': _head,
        'versions': <Object>[for (final FakeVersion v in rows.take(limit)) _versionOut(v)],
        'more': rows.length > limit,
      };
    }
    if (what == 'uploads') {
      if (method == 'POST' && r.length == 3) return _begin(body!);
      final String id = r[3];
      final FakeUpload? u = uploads[id];
      if (u == null) throw _err(404, 'upload_not_found');
      if (method == 'GET') {
        return <String, dynamic>{'uploadId': id, 'state': u.state, 'received': u.chunks.keys.toList()..sort()};
      }
      if (r[4] == 'chunks' && method == 'PUT') {
        puts++;
        if (failPutAt != null && puts == failPutAt) throw StateError('connection dropped');
        final Uint8List data = base64.decode(body!['data'] as String);
        if (hex(sha256Bytes(data)) != body['sha256']) throw _err(422, 'chunk_hash_mismatch');
        final int i = int.parse(r[5]);
        u.chunks[i] = data;
        return <String, dynamic>{'index': i, 'stored': true};
      }
      if (r[4] == 'commit') {
        await beforeCommit?.call();
        return _commit(u);
      }
    }
    if (what == 'restores') return _restores(method, r, body, headers);
    throw _err(404, 'not_found');
  }

  Map<String, dynamic> _begin(Map<String, dynamic> b) {
    final String ref = b['clientRef'] as String;
    final int base = b['baseSeq'] as int;
    final Uint8List prev = _unhex(b['prevChainHash'] as String);
    final Uint8List blob = _unhex(b['blobSha256'] as String);
    final int size = b['sizeBytes'] as int;
    final Uint8List manifest = base64.decode(b['manifest'] as String);
    final String claimed = b['chainHash'] as String;
    final String want = hex(backupChainHash(
        vaultId: vaultId, seq: base + 1, prevChain: prev, blobSha256: blob, size: size, manifest: manifest));
    if (want != claimed) throw _err(422, 'chain_mismatch');
    for (final FakeUpload u in uploads.values) {
      if (u.ref == ref) {
        return <String, dynamic>{'uploadId': u.id, 'state': u.state, 'seq': base + 1, 'chunkSize': u.chunkSize, 'chunkCount': u.chunkCount, 'resumed': true};
      }
    }
    final String headChain = versions.isEmpty ? hex(Uint8List(32)) : versions.last.chain;
    if ((versions.isEmpty ? 0 : versions.last.seq) != base || headChain != b['prevChainHash']) throw _err(409, 'head_moved');
    final int cs = b['chunkSize'] as int;
    final int count = (size / cs).ceil();
    final FakeUpload u = FakeUpload(_id('up'), ref, base, hex(prev), claimed, hex(blob), size, cs, count, manifest,
        base64.decode(b['signature'] as String));
    uploads[u.id] = u;
    return <String, dynamic>{'uploadId': u.id, 'state': 'open', 'seq': base + 1, 'chunkSize': cs, 'chunkCount': count, 'resumed': false};
  }

  Map<String, dynamic> _commit(FakeUpload u) {
    if (u.state == 'committed') return <String, dynamic>{'version': _versionOut(versions.firstWhere((FakeVersion v) => v.chain == u.chain))};
    final String headChain = versions.isEmpty ? hex(Uint8List(32)) : versions.last.chain;
    if ((versions.isEmpty ? 0 : versions.last.seq) != u.baseSeq || headChain != u.prev) throw _err(409, 'head_moved');
    if (u.chunks.length != u.chunkCount) throw _err(409, 'upload_incomplete');
    final BytesBuilder all = BytesBuilder(copy: false);
    for (int i = 0; i < u.chunkCount; i++) {
      all.add(u.chunks[i]!);
    }
    final Uint8List blob = all.toBytes();
    if (blob.length != u.size || hex(sha256Bytes(blob)) != u.blobSha) throw _err(422, 'blob_hash_mismatch');
    final FakeVersion v = FakeVersion(u.baseSeq + 1, u.prev, u.chain, u.blobSha, u.size, u.chunkSize, u.chunkCount, u.manifest, u.signature, blob);
    versions.add(v);
    u.state = 'committed';
    final List<FakeVersion> live = <FakeVersion>[for (final FakeVersion x in versions) if (x.state == 'live') x];
    for (int i = 0; i < live.length - keepLive; i++) {
      live[i].state = 'tombstone';
    }
    return <String, dynamic>{'version': _versionOut(v), 'tombstoned': <Object>[]};
  }

  Future<Map<String, dynamic>> _restores(String method, List<String> r, Map<String, dynamic>? body, Map<String, String>? headers) async {
    if (r.length == 4 && r[3] == 'challenge') {
      final Uint8List nonce = Uint8List.fromList(List<int>.generate(32, (int i) => (_n * 13 + i) & 0xff));
      final String id = _id('ch');
      _challenges[id] = nonce;
      return <String, dynamic>{'challengeId': id, 'nonce': hex(nonce)};
    }
    if (r.length == 3 && method == 'POST') {
      final Uint8List? nonce = _challenges.remove(body!['challengeId']);
      if (nonce == null) throw _err(403, 'challenge_invalid');
      final Uint8List msg = restoreChallengeMessage(
          vaultId: vaultId, userId: userId, deviceId: deviceOfRestore, nonce: nonce);
      final Uint8List sig = base64.decode(body['signature'] as String);
      if (!await BackupAuthority.verify(verifier!, msg, sig)) throw _err(403, 'recovery_key_proof_invalid');
      if (body['pin'] != '2468') throw _err(403, 'pin_invalid');
      restore = <String, Object?>{
        'id': _id('rs'),
        'state': 'pending',
        'notBefore': clock.add(Duration(hours: waitHours)),
        'waitHours': waitHours,
        'approvalRequired': approvalRequired,
        'approved': false,
        'token': null,
      };
      return <String, dynamic>{'restore': _restoreOut()};
    }
    if (r.length == 3 && method == 'GET') {
      return <String, dynamic>{'restores': restore == null ? <Object>[] : <Object>[_restoreOut()], 'role': 'member'};
    }
    final String rid = r[3];
    if (restore == null || restore!['id'] != rid) throw _err(404, 'restore_not_found');
    final String act = r[4];
    if (act == 'cancel') {
      restore!['state'] = 'cancelled';
      return <String, dynamic>{'ok': true};
    }
    if (act == 'token') {
      final String phase = _restoreOut()['phase'] as String;
      if (phase == 'waiting') throw _err(409, 'waiting_period');
      if (phase == 'needs_yes') throw _err(409, 'waiting_for_approval');
      if (restore!['state'] != 'pending') throw _err(409, 'restore_${restore!['state']}');
      restore!['token'] = 'tok-${_id('t')}-padding-padding';
      return <String, dynamic>{'restoreId': rid, 'token': restore!['token']};
    }
    if (headers?['x-olive-restore-token'] != restore!['token'] || restore!['token'] == null) {
      throw _err(403, 'restore_token_invalid');
    }
    if (act == 'complete') {
      restore!['state'] = 'completed';
      return <String, dynamic>{'restoreId': rid, 'state': 'completed'};
    }
    if (act == 'versions') {
      final int seq = int.parse(r[5]);
      final int idx = int.parse(r[7]);
      final FakeVersion v = versions.firstWhere((FakeVersion x) => x.seq == seq, orElse: () => throw _err(404, 'version_not_found'));
      final int a = idx * v.chunkSize;
      final int b = min(a + v.chunkSize, v.blob.length);
      final Uint8List part = Uint8List.sublistView(v.blob, a, b);
      return <String, dynamic>{'seq': seq, 'index': idx, 'sizeBytes': part.length, 'sha256': hex(sha256Bytes(part)), 'data': base64.encode(part)};
    }
    throw _err(404, 'not_found');
  }

  static Uint8List _unhex(String h) =>
      Uint8List.fromList(<int>[for (int i = 0; i < h.length; i += 2) int.parse(h.substring(i, i + 2), radix: 16)]);
}
