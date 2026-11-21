// OLIVE BRANCH — the family's own server as a place to keep a backup, and to bring one back from. UNVERIFIED on a
// device; pure Dart over an injected [BackupServerApi], so it runs headless in CI. See
// docs/planning/BACKUP-RESTORE-CLIENT.md and MASTERFILE 7.22 (the server half, migration 0054).
//
// WHAT THE SERVER SEES. One sealed file per backup (a "blob": the signed header and every sealed chunk, packed), its
// hash and size, a tiny plain manifest (which set, which number, which phone wrote it) and a signature. It never sees a
// key or a word of the recovery sheet, and nothing inside the blob.
//
// WHAT THE PHONE CHECKS. Every version the server lists carries a chain value that binds the vault, the number, the
// version before it, the blob's hash and size and the manifest, and a signature by the writing phone. The phone
// recomputes the whole chain, checks every signature and remembers the newest (number, chain) it has seen, so a server
// that drops, reorders, edits or rolls back a family's backups is noticed here and never trusted.
//
// THE RESTORE SIDE is the server's gate: a request signed with the recovery key, a second grown-up's yes (or a longer
// wait with nobody to ask), a waiting period, and anyone in the family can cancel. Only after that does the server
// release bytes, and only to the phone that asked.
import 'dart:convert';
import 'dart:typed_data';

import 'api_client.dart' show ApiException, OliveApi;
import 'backup_crypto.dart';
import 'backup_header.dart';
import 'backup_sink.dart';
import 'backup_state.dart';
import 'cpace.dart' show cat, lv;
import 'device_keys.dart' show DeviceKey, b64, unb64;
import 'sha256.dart';

// --- the wire ----------------------------------------------------------------------------------------------------

/// How the backup code talks to the family's server. [OliveBackupServerApi] is the real one; tests pass a fake.
/// Throws [ApiException] for an answer of 400 or more, anything else for a connection that failed.
abstract class BackupServerApi {
  Future<Map<String, dynamic>> send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    Map<String, String>? headers,
  });
}

/// Fills `:name` holes in a route template.
String backupPath(String template, Map<String, Object> params) {
  String out = template;
  params.forEach((String k, Object v) {
    final String s = '$v';
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(s)) throw ArgumentError('not a safe path part');
    out = out.replaceAll(':$k', s);
  });
  return out;
}

/// The route templates. They match api_client.dart's OliveApi.backup* constants (and so the server's own routes).
class BackupRoutes {
  static const String limits = '/v1/backup/limits';
  static const String vaults = '/v1/backup/vaults';
  static const String vaultJoin = '/v1/backup/vaults/:vaultId/join';
  static const String uploads = '/v1/backup/vaults/:vaultId/uploads';
  static const String upload = '/v1/backup/vaults/:vaultId/uploads/:uploadId';
  static const String uploadChunk = '/v1/backup/vaults/:vaultId/uploads/:uploadId/chunks/:index';
  static const String uploadCommit = '/v1/backup/vaults/:vaultId/uploads/:uploadId/commit';
  static const String versions = '/v1/backup/vaults/:vaultId/versions';
  static const String restoreChallenge = '/v1/backup/vaults/:vaultId/restores/challenge';
  static const String restores = '/v1/backup/vaults/:vaultId/restores';
  static const String restoreCancel = '/v1/backup/vaults/:vaultId/restores/:restoreId/cancel';
  static const String restoreToken = '/v1/backup/vaults/:vaultId/restores/:restoreId/token';
  static const String restoreChunk = '/v1/backup/vaults/:vaultId/restores/:restoreId/versions/:seq/chunks/:index';
  static const String restoreComplete = '/v1/backup/vaults/:vaultId/restores/:restoreId/complete';
}

/// Turns anything a call threw into a [BackupSinkException] a screen can word plainly.
BackupSinkException backupErrorFrom(Object e) {
  if (e is BackupSinkException) return e;
  if (e is ApiException) {
    final String code = e.error;
    if (e.statusCode == 401) return const BackupSinkException('signed_out');
    if (code == 'backup_not_enabled') return const BackupSinkException('not_enabled');
    if (code == 'reach_paused') return const BackupSinkException('paused');
    if (code == 'vault_not_found') return const BackupSinkException('no_vault');
    if (e.statusCode == 507 || code == 'quota_exceeded' || code == 'backup_too_large') {
      return BackupSinkException('full', code);
    }
    if (e.statusCode == 429 || e.statusCode >= 500) return BackupSinkException('unreachable', code);
    if (e.statusCode == 403 || e.statusCode == 404) return BackupSinkException('refused', code);
    return BackupSinkException('refused', code);
  }
  return const BackupSinkException('unreachable');
}

// --- the chain ---------------------------------------------------------------------------------------------------

/// 32 zero bytes: the chain value before the first version exists.
final Uint8List kGenesisChain = Uint8List(32);

Uint8List _uuidBytes(String id) {
  final String h = id.replaceAll('-', '');
  if (!RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(h)) throw ArgumentError('not a uuid');
  return Uint8List.fromList(<int>[for (int i = 0; i < 32; i += 2) int.parse(h.substring(i, i + 2), radix: 16)]);
}

Uint8List _u64(int n) {
  final ByteData d = ByteData(8)..setUint64(0, n, Endian.big);
  return d.buffer.asUint8List();
}

Uint8List _hexBytes(String h) {
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(h)) throw ArgumentError('not a 32 byte hash');
  return Uint8List.fromList(<int>[for (int i = 0; i < 64; i += 2) int.parse(h.substring(i, i + 2), radix: 16)]);
}

Uint8List _sha(List<int> data) => sha256Bytes(Uint8List.fromList(data));

/// The server's chain value for one version (a port of server/backup_chain.mjs `chainHash`).
Uint8List backupChainHash({
  required String vaultId,
  required int seq,
  required List<int> prevChain,
  required List<int> blobSha256,
  required int size,
  required List<int> manifest,
}) =>
    _sha(<int>[
      ...utf8.encode('olive-backup-chain-v1'),
      0,
      ..._uuidBytes(vaultId),
      ..._u64(seq),
      ...prevChain,
      ...blobSha256,
      ..._u64(size),
      ..._sha(manifest),
    ]);

/// What a writing phone signs for a version: its chain value, with a label so the signature means one thing only.
Uint8List chainSigMessage(List<int> chain) =>
    cat(<List<int>>[lv(utf8.encode('olive-backup-chain-sig-v1')), lv(chain)]);

/// What the recovery key signs to ask for a restore (a port of `restoreChallengeMessage`).
Uint8List restoreChallengeMessage({
  required String vaultId,
  required String userId,
  required String deviceId,
  required List<int> nonce,
}) =>
    Uint8List.fromList(<int>[
      ...utf8.encode('olive-backup-restore-v1'),
      0,
      ..._uuidBytes(vaultId),
      ..._uuidBytes(userId),
      ..._uuidBytes(deviceId),
      ...nonce,
    ]);

/// The small plain manifest the chain covers: which set and number, and which phone wrote it (with the sheet's
/// certificate for that phone, so a reader can check the writer without opening anything).
Uint8List publicManifest(BackupHeader h) => Uint8List.fromList(utf8.encode(jsonEncode(<String, Object?>{
      'v': 1,
      'set': h.setId,
      'kind': h.kind.name,
      'seq': h.seq,
      'writer': b64(h.writer),
      'cert': b64(h.cert),
    })));

class PublicManifest {
  PublicManifest(this.setId, this.kind, this.seq, this.writer, this.cert);
  final String setId;
  final BackupKind kind;
  final int seq;
  final Uint8List writer, cert;

  static PublicManifest? parse(List<int> bytes) {
    try {
      final Object? j = jsonDecode(utf8.decode(bytes));
      if (j is! Map || j['v'] != 1) return null;
      final Object? set = j['set'], kind = j['kind'], seq = j['seq'], w = j['writer'], c = j['cert'];
      if (set is! String || kind is! String || seq is! int || w is! String || c is! String) return null;
      final BackupKind? k = BackupKind.values.where((BackupKind v) => v.name == kind).firstOrNull;
      if (k == null) return null;
      final Uint8List wb = unb64(w), cb = unb64(c);
      if (wb.length != 32 || cb.length != 64) return null;
      return PublicManifest(set, k, seq, wb, cb);
    } catch (_) {
      return null;
    }
  }
}

/// One version as the server lists it.
class ServerVersion {
  ServerVersion({
    required this.seq,
    required this.prevChain,
    required this.chain,
    required this.blobSha256,
    required this.size,
    required this.chunkSize,
    required this.chunkCount,
    required this.manifest,
    required this.signature,
    required this.live,
  });
  final int seq, size, chunkSize, chunkCount;
  final String prevChain, chain, blobSha256;
  final Uint8List manifest, signature;
  final bool live;

  static ServerVersion? fromJson(Object? j) {
    if (j is! Map) return null;
    try {
      final Object? seq = j['seq'], size = j['sizeBytes'], cs = j['chunkSize'], cc = j['chunkCount'];
      final Object? prev = j['prevChainHash'], chain = j['chainHash'], blob = j['blobSha256'];
      final Object? man = j['manifest'], sig = j['signature'], state = j['state'];
      if (seq is! int || size is! int || cs is! int || cc is! int) return null;
      if (prev is! String || chain is! String || blob is! String || man is! String || sig is! String) return null;
      return ServerVersion(
          seq: seq, size: size, chunkSize: cs, chunkCount: cc, prevChain: prev, chain: chain, blobSha256: blob,
          manifest: base64.decode(man), signature: base64.decode(sig), live: state == 'live');
    } catch (_) {
      return null;
    }
  }
}

enum HistoryProblem { gap, chainBroken, chainValueWrong, badSignature, notOurs, rollback, highWaterChanged }

class HistoryVerdict {
  const HistoryVerdict.ok(this.headSeq, this.headChain)
      : problem = null,
        atSeq = null;
  const HistoryVerdict.bad(HistoryProblem this.problem, {this.atSeq})
      : headSeq = 0,
        headChain = '';
  final HistoryProblem? problem;
  final int? atSeq;
  final int headSeq;
  final String headChain;
  bool get ok => problem == null;
}

/// The phone's check of a whole listed history (oldest first): every chain value recomputed, every link unbroken,
/// every signature good, every writer certified by the sheet, nothing older than what this phone has already seen.
Future<HistoryVerdict> verifyServerHistory({
  required String vaultId,
  required List<ServerVersion> versions,
  required BackupAuthority authority,
  required BackupKind kind,
  int highSeq = 0,
  String? highChain,
}) async {
  Uint8List prev = kGenesisChain;
  int? expect = versions.isEmpty ? null : versions.first.seq;
  for (final ServerVersion v in versions) {
    if (v.seq != expect) return HistoryVerdict.bad(HistoryProblem.gap, atSeq: v.seq);
    if (!_eq(_hexBytes(v.prevChain), prev)) return HistoryVerdict.bad(HistoryProblem.chainBroken, atSeq: v.seq);
    final Uint8List want = backupChainHash(
        vaultId: vaultId, seq: v.seq, prevChain: prev, blobSha256: _hexBytes(v.blobSha256), size: v.size,
        manifest: v.manifest);
    if (hexString(want) != v.chain) return HistoryVerdict.bad(HistoryProblem.chainValueWrong, atSeq: v.seq);
    final PublicManifest? m = PublicManifest.parse(v.manifest);
    if (m == null ||
        m.kind != kind ||
        !await BackupAuthority.verifyWriter(authority.publicKey, kind, m.writer, m.cert) ||
        !await DeviceKey.verify(m.writer, chainSigMessage(want), v.signature)) {
      return HistoryVerdict.bad(m == null || m.kind != kind ? HistoryProblem.notOurs : HistoryProblem.badSignature,
          atSeq: v.seq);
    }
    prev = want;
    expect = v.seq + 1;
  }
  final ServerVersion? head = versions.isEmpty ? null : versions.last;
  if (highSeq > 0) {
    if (head == null || head.seq < highSeq) return const HistoryVerdict.bad(HistoryProblem.rollback);
    final ServerVersion? at = versions.where((ServerVersion v) => v.seq == highSeq).firstOrNull;
    if (at != null && highChain != null && at.chain != highChain) {
      return HistoryVerdict.bad(HistoryProblem.highWaterChanged, atSeq: highSeq);
    }
  }
  return HistoryVerdict.ok(head?.seq ?? 0, head?.chain ?? hexString(kGenesisChain));
}

bool _eq(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

// --- the blob ----------------------------------------------------------------------------------------------------

const String _blobMagic = 'OLVBLOB1';

/// Packs a staged backup into the one sealed file the server keeps: magic, the header, then every chunk in order.
Uint8List packBackupBlob(StagedBackup s) {
  final BytesBuilder b = BytesBuilder(copy: false);
  void u32(int n) => b.add((ByteData(4)..setUint32(0, n, Endian.big)).buffer.asUint8List());
  b.add(utf8.encode(_blobMagic));
  u32(s.header.length);
  b.add(s.header);
  u32(s.chunkIds.length);
  for (final String id in s.chunkIds) {
    final Uint8List c = s.chunks[id]!;
    u32(c.length);
    b.add(c);
  }
  return b.toBytes();
}

class UnpackedBlob {
  UnpackedBlob(this.headerBytes, this.header, this.chunks);
  final Uint8List headerBytes;
  final BackupHeader header;
  final Map<String, Uint8List> chunks;
}

/// Reads a blob. Null for anything that is not exactly what [packBackupBlob] makes: wrong magic, cut short, trailing
/// bytes, a chunk whose hash is not its name, or chunks that are not the header's. Never throws.
UnpackedBlob? unpackBackupBlob(Uint8List blob) {
  try {
    final ByteData d = ByteData.sublistView(blob);
    int at = 0;
    int u32() {
      if (at + 4 > blob.length) throw const FormatException();
      final int n = d.getUint32(at, Endian.big);
      at += 4;
      return n;
    }

    Uint8List take(int n) {
      if (n < 0 || at + n > blob.length) throw const FormatException();
      final Uint8List out = Uint8List.sublistView(blob, at, at + n);
      at += n;
      return out;
    }

    if (utf8.decode(take(8)) != _blobMagic) return null;
    final Uint8List headerBytes = Uint8List.fromList(take(u32()));
    final BackupHeader? h = BackupHeader.parse(headerBytes);
    if (h == null) return null;
    final int n = u32();
    if (n != h.chunks.length) return null;
    final Map<String, Uint8List> chunks = <String, Uint8List>{};
    for (int i = 0; i < n; i++) {
      final Uint8List c = Uint8List.fromList(take(u32()));
      if (hexString(_sha(c)) != h.chunks[i]) return null;
      chunks[h.chunks[i]] = c;
    }
    if (at != blob.length) return null;
    return UnpackedBlob(headerBytes, h, chunks);
  } catch (_) {
    return null;
  }
}

String _stdB64(List<int> b) => base64.encode(b);

// --- backing up to the server --------------------------------------------------------------------------------------

class ServerBackupSink implements BackupSink {
  ServerBackupSink({required this.api, required this.state, required this.writer, this.label = "your family's server"});
  final BackupServerApi api;
  final BackupStateStore state;
  final DeviceKey writer;
  @override
  final String label;
  @override
  String get kindWord => 'server';

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } catch (e) {
      throw backupErrorFrom(e);
    }
  }

  // A restore goes through [ServerRestore], never through the sink: the server releases bytes only after its own gate.
  @override
  Future<List<String>> listManifests(String set) async => const <String>[];
  @override
  Future<Uint8List?> getManifest(String set, String name) async => null;
  @override
  Future<Uint8List?> getChunk(String set, String id) async => null;

  Future<({int seq, String chain})?> _head(String vaultId) async {
    final Map<String, dynamic> r = await api.send('GET', backupPath(BackupRoutes.versions, <String, Object>{'vaultId': vaultId}),
        query: <String, String>{'after': '2000000000', 'limit': '1'});
    final Object? h = r['head'];
    if (h is Map && h['seq'] is int && h['chainHash'] is String) {
      return (seq: h['seq'] as int, chain: h['chainHash'] as String);
    }
    return null;
  }

  /// The backup number of the newest version this server holds (0 when none or when it cannot be asked).
  @override
  Future<int> highestSeq(String set) async {
    try {
      final String? vaultId = (await state.vault()).vaultId;
      if (vaultId == null) return 0;
      final head = await _head(vaultId);
      if (head == null) return 0;
      final Map<String, dynamic> r = await api.send('GET', backupPath(BackupRoutes.versions, <String, Object>{'vaultId': vaultId}),
          query: <String, String>{'after': '${head.seq - 1}', 'limit': '1'});
      final Object? vs = r['versions'];
      if (vs is List && vs.isNotEmpty) {
        final ServerVersion? v = ServerVersion.fromJson(vs.last);
        final PublicManifest? m = v == null ? null : PublicManifest.parse(v.manifest);
        if (m != null && m.setId == set) return m.seq;
      }
    } catch (_) {
      // an unreachable destination just does not raise the number
    }
    return 0;
  }

  @override
  Future<void> store(StagedBackup s, BackupHeader header, SendCounts counts, {int keep = 3}) => _guard(() async {
        final String? vaultId = (await state.vault()).vaultId;
        if (vaultId == null) throw const BackupSinkException('no_vault');
        final Map<String, dynamic> limits = await api.send('GET', BackupRoutes.limits);
        final int maxChunk = limits['maxChunkBytes'] is int ? limits['maxChunkBytes'] as int : 1024 * 1024;
        final int chunkSize = maxChunk > 4 * 1024 * 1024 ? 4 * 1024 * 1024 : maxChunk;
        final Uint8List blob = packBackupBlob(s);
        if (limits['maxVersionBytes'] is int && blob.length > (limits['maxVersionBytes'] as int)) {
          throw const BackupSinkException('full', 'backup_too_large');
        }
        final Uint8List blobSha = _sha(blob);
        final Uint8List manifest = publicManifest(header);

        for (int attempt = 0; attempt < 4; attempt++) {
          final head = await _head(vaultId);
          final int baseSeq = head?.seq ?? 0;
          final Uint8List prev = head == null ? kGenesisChain : _hexBytes(head.chain);
          final int seq = baseSeq + 1;
          final Uint8List chain = backupChainHash(
              vaultId: vaultId, seq: seq, prevChain: prev, blobSha256: blobSha, size: blob.length, manifest: manifest);
          // The phone's own name for this attempt: the same backup on the same history is the same attempt, so a run
          // that was cut off is carried on, and one that raced another phone starts a new one.
          final String clientRef = 'b${hexString(_sha(<int>[...blobSha, ...chain])).substring(0, 40)}';
          final Map<String, dynamic> begun;
          try {
            begun = await api.send('POST', backupPath(BackupRoutes.uploads, <String, Object>{'vaultId': vaultId}), body: <String, dynamic>{
              'clientRef': clientRef,
              'baseSeq': baseSeq,
              'prevChainHash': hexString(prev),
              'chainHash': hexString(chain),
              'blobSha256': hexString(blobSha),
              'sizeBytes': blob.length,
              'chunkSize': chunkSize,
              'manifest': _stdB64(manifest),
              'signature': _stdB64(await writer.sign(chainSigMessage(chain))),
            });
          } on ApiException catch (e) {
            if (e.error == 'head_moved' && attempt < 3) continue;
            rethrow;
          }
          final String uploadId = begun['uploadId'] as String;
          final int chunkCount = begun['chunkCount'] as int;
          final Set<int> have = <int>{};
          if (begun['resumed'] == true) {
            final Map<String, dynamic> st = await api.send('GET',
                backupPath(BackupRoutes.upload, <String, Object>{'vaultId': vaultId, 'uploadId': uploadId}));
            final Object? got = st['received'];
            if (got is List) have.addAll(got.whereType<int>());
          }
          for (int i = 0; i < chunkCount; i++) {
            if (have.contains(i)) {
              counts.skipped++;
              continue;
            }
            final Uint8List part = Uint8List.sublistView(blob, i * chunkSize, (i + 1) * chunkSize > blob.length ? blob.length : (i + 1) * chunkSize);
            await api.send('PUT',
                backupPath(BackupRoutes.uploadChunk, <String, Object>{'vaultId': vaultId, 'uploadId': uploadId, 'index': i}),
                body: <String, dynamic>{'data': _stdB64(part), 'sha256': hexString(_sha(part))});
            counts.uploaded++;
          }
          final Map<String, dynamic> done;
          try {
            done = await api.send('POST',
                backupPath(BackupRoutes.uploadCommit, <String, Object>{'vaultId': vaultId, 'uploadId': uploadId}),
                body: <String, dynamic>{});
          } on ApiException catch (e) {
            if (e.error == 'head_moved' && attempt < 3) {
              counts.uploaded = 0;
              counts.skipped = 0;
              continue;
            }
            rethrow;
          }
          // The commit is only believed when the server's own answer is the version we signed.
          final ServerVersion? v = ServerVersion.fromJson(done['version']);
          if (v == null || v.chain != hexString(chain) || v.blobSha256 != hexString(blobSha) || v.size != blob.length) {
            throw const BackupSinkException('damaged', 'commit');
          }
          await state.raiseHighWater(seq, hexString(chain));
          return;
        }
        throw const BackupSinkException('unreachable', 'head_moved');
      });
}

// --- bringing one back from the server -----------------------------------------------------------------------------

enum ServerRestorePhase { waiting, needsYes, ready, tokenIssued, cancelled, completed, expired, none }

class ServerRestoreStatus {
  ServerRestoreStatus({
    required this.phase,
    required this.restoreId,
    this.notBefore,
    this.waitHours,
    this.approvalRequired = false,
    this.approved = false,
  });
  final ServerRestorePhase phase;
  final String? restoreId;
  final DateTime? notBefore;
  final int? waitHours;
  final bool approvalRequired, approved;

  static ServerRestoreStatus fromJson(Object? j) {
    if (j is! Map) return ServerRestoreStatus(phase: ServerRestorePhase.none, restoreId: null);
    final String phase = '${j['phase']}';
    final ServerRestorePhase p = switch (phase) {
      'waiting' => ServerRestorePhase.waiting,
      'needs_yes' => ServerRestorePhase.needsYes,
      'ready' => ServerRestorePhase.ready,
      'token_issued' => ServerRestorePhase.tokenIssued,
      'cancelled' => ServerRestorePhase.cancelled,
      'completed' => ServerRestorePhase.completed,
      'expired' => ServerRestorePhase.expired,
      _ => ServerRestorePhase.none,
    };
    return ServerRestoreStatus(
      phase: p,
      restoreId: j['restoreId'] is String ? j['restoreId'] as String : null,
      notBefore: j['notBefore'] is String ? DateTime.tryParse(j['notBefore'] as String) : null,
      waitHours: j['waitHours'] is int ? j['waitHours'] as int : null,
      approvalRequired: j['approvalRequired'] == true,
      approved: j['approved'] == true,
    );
  }
}

/// What a verified download from the server holds.
class ServerFetch {
  ServerFetch(this.source, this.versions, this.headSeq, this.headChain);

  /// Every downloaded backup, laid out for [RestoreEngine.open] exactly like a folder.
  final MemoryBackupSink source;
  final int versions;
  final int headSeq;
  final String headChain;
}

class ServerRestore {
  ServerRestore({required this.api, required this.state});
  final BackupServerApi api;
  final BackupStateStore state;
  String? _token;

  Future<T> _guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } catch (e) {
      throw backupErrorFrom(e);
    }
  }

  /// The vault this grown-up belongs to, or null when there is none.
  Future<String?> findVault() => _guard(() async {
        final Map<String, dynamic> r = await api.send('GET', BackupRoutes.vaults);
        final Object? vs = r['vaults'];
        if (vs is List && vs.isNotEmpty && vs.first is Map && (vs.first as Map)['vaultId'] is String) {
          return (vs.first as Map)['vaultId'] as String;
        }
        return null;
      });

  /// Asks the server for a restore: signs its one-time challenge with the recovery key (which proves the person holds
  /// the paper), with the grown-up's own PIN. The wait and any second grown-up's yes are the server's.
  Future<ServerRestoreStatus> request({
    required String vaultId,
    required BackupAuthority authority,
    required String userId,
    required String deviceId,
    required String pin,
  }) =>
      _guard(() async {
        final Map<String, dynamic> c = await api.send('POST',
            backupPath(BackupRoutes.restoreChallenge, <String, Object>{'vaultId': vaultId}), body: <String, dynamic>{});
        final String nonceHex = '${c['nonce']}';
        if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(nonceHex)) throw const BackupSinkException('damaged', 'nonce');
        final Uint8List sig = await authority.sign(restoreChallengeMessage(
            vaultId: vaultId, userId: userId, deviceId: deviceId, nonce: _hexBytes(nonceHex)));
        final Map<String, dynamic> r = await api.send('POST', backupPath(BackupRoutes.restores, <String, Object>{'vaultId': vaultId}),
            body: <String, dynamic>{'pin': pin, 'challengeId': c['challengeId'], 'signature': _stdB64(sig)});
        return ServerRestoreStatus.fromJson(r['restore']);
      });

  /// The newest restore asked for on this vault, or a status with phase none.
  Future<ServerRestoreStatus> status(String vaultId) => _guard(() async {
        final Map<String, dynamic> r =
            await api.send('GET', backupPath(BackupRoutes.restores, <String, Object>{'vaultId': vaultId}));
        final Object? rs = r['restores'];
        if (rs is List && rs.isNotEmpty) return ServerRestoreStatus.fromJson(rs.first);
        return ServerRestoreStatus(phase: ServerRestorePhase.none, restoreId: null);
      });

  /// Any grown-up in the family can stop a restore, with no PIN and no wait.
  Future<void> cancel(String vaultId, String restoreId) => _guard(() async {
        await api.send('POST',
            backupPath(BackupRoutes.restoreCancel, <String, Object>{'vaultId': vaultId, 'restoreId': restoreId}),
            body: <String, dynamic>{});
      });

  /// Once the server says ready: gets the download pass, checks the whole history, downloads the newest backups and
  /// verifies each against its chain value and its own hash. Nothing is written to the phone here.
  Future<ServerFetch> fetch({
    required String vaultId,
    required String restoreId,
    required BackupAuthority authority,
    required BackupKind kind,
    int maxVersions = 6,
  }) =>
      _guard(() async {
        final Map<String, dynamic> t = await api.send('POST',
            backupPath(BackupRoutes.restoreToken, <String, Object>{'vaultId': vaultId, 'restoreId': restoreId}),
            body: <String, dynamic>{});
        final Object? token = t['token'];
        if (token is! String) throw const BackupSinkException('refused', 'token');
        _token = token;

        final List<ServerVersion> all = <ServerVersion>[];
        int after = 0;
        for (int page = 0; page < 200; page++) {
          final Map<String, dynamic> r = await api.send('GET',
              backupPath(BackupRoutes.versions, <String, Object>{'vaultId': vaultId}),
              query: <String, String>{'after': '$after', 'limit': '200'});
          final Object? vs = r['versions'];
          if (vs is! List) throw const BackupSinkException('damaged', 'versions');
          for (final Object? o in vs) {
            final ServerVersion? v = ServerVersion.fromJson(o);
            if (v == null) throw const BackupSinkException('damaged', 'version');
            all.add(v);
            after = v.seq;
          }
          if (r['more'] != true) break;
        }
        final vault = await state.vault();
        final HistoryVerdict verdict = await verifyServerHistory(
            vaultId: vaultId, versions: all, authority: authority, kind: kind,
            highSeq: vault.vaultId == vaultId ? vault.highSeq : 0, highChain: vault.vaultId == vaultId ? vault.highChain : null);
        if (!verdict.ok) throw BackupSinkException('damaged', 'history_${verdict.problem!.name}');

        final MemoryBackupSink into = MemoryBackupSink(label: "your family's server");
        int got = 0;
        final Set<String> writers = <String>{};
        for (final ServerVersion v in all.reversed) {
          if (!v.live || got >= maxVersions) continue;
          final PublicManifest m = PublicManifest.parse(v.manifest)!;
          final String wtag = writerTag(m.writer);
          // One whole backup per writing phone is all a restore uses; a few extra guard against a damaged newest.
          if (writers.contains(wtag) && got >= 2 * writers.length) continue;
          final BytesBuilder blob = BytesBuilder(copy: false);
          for (int i = 0; i < v.chunkCount; i++) {
            final Map<String, dynamic> c = await api.send('GET',
                backupPath(BackupRoutes.restoreChunk,
                    <String, Object>{'vaultId': vaultId, 'restoreId': restoreId, 'seq': v.seq, 'index': i}),
                headers: <String, String>{'x-olive-restore-token': token});
            final Object? data = c['data'];
            if (data is! String) throw const BackupSinkException('damaged', 'chunk');
            blob.add(base64.decode(data));
          }
          final Uint8List bytes = blob.toBytes();
          if (bytes.length != v.size || hexString(_sha(bytes)) != v.blobSha256) {
            throw const BackupSinkException('damaged', 'blob');
          }
          final UnpackedBlob? u = unpackBackupBlob(bytes);
          if (u == null || u.header.seq != m.seq || u.header.setId != m.setId || u.header.name != '${m.seq.toString().padLeft(10, '0')}-$wtag') {
            throw const BackupSinkException('damaged', 'blob_shape');
          }
          for (final MapEntry<String, Uint8List> e in u.chunks.entries) {
            await into.putChunk(u.header.setId, e.key, e.value);
          }
          await into.putManifest(u.header.setId, u.header.name, u.headerBytes);
          writers.add(wtag);
          got++;
        }
        if (got == 0) throw const BackupSinkException('damaged', 'nothing');
        return ServerFetch(into, got, verdict.headSeq, verdict.headChain);
      });

  /// Tells the server this restore is finished (best effort: the phone already has everything). Remembers the
  /// newest history seen so a later rollback is noticed.
  Future<void> complete(String vaultId, String restoreId, ServerFetch f) async {
    await state.setVault(vaultId);
    await state.raiseHighWater(f.headSeq, f.headChain);
    final String? token = _token;
    if (token == null) return;
    try {
      await api.send('POST',
          backupPath(BackupRoutes.restoreComplete, <String, Object>{'vaultId': vaultId, 'restoreId': restoreId}),
          body: <String, dynamic>{}, headers: <String, String>{'x-olive-restore-token': token});
    } catch (_) {
      // The records are already here; the server learns on the next contact.
    }
    _token = null;
  }
}

// --- setting up the vault --------------------------------------------------------------------------------------------

/// Makes (or joins) the family's server vault. [recoveryVerifier] is the PUBLIC half of the recovery key's signing key,
/// never the words. A family keeps one vault: a second grown-up joins the one that exists.
Future<String> setUpServerVault({
  required BackupServerApi api,
  required BackupStateStore state,
  required BackupAuthority authority,
  required String pin,
}) async {
  try {
    String? vaultId;
    final Map<String, dynamic> mine = await api.send('GET', BackupRoutes.vaults);
    final Object? vs = mine['vaults'];
    if (vs is List && vs.isNotEmpty && vs.first is Map && (vs.first as Map)['vaultId'] is String) {
      vaultId = (vs.first as Map)['vaultId'] as String;
    }
    if (vaultId == null) {
      try {
        final Map<String, dynamic> r = await api.send('POST', BackupRoutes.vaults,
            body: <String, dynamic>{'pin': pin, 'recoveryVerifier': hexString(authority.publicKey)});
        vaultId = r['vaultId'] as String;
      } on ApiException catch (e) {
        if (e.error != 'join_existing_vault') rethrow;
        final Map<String, dynamic> j = await api.send('GET', BackupRoutes.vaults);
        final Object? jo = j['joinable'];
        if (jo is! List || jo.isEmpty || jo.first is! Map) rethrow;
        vaultId = (jo.first as Map)['vaultId'] as String;
        await api.send('POST', backupPath(BackupRoutes.vaultJoin, <String, Object>{'vaultId': vaultId}),
            body: <String, dynamic>{'pin': pin});
      }
    }
    await state.setVault(vaultId);
    return vaultId;
  } catch (e) {
    throw backupErrorFrom(e);
  }
}

/// The real thing: the app's own signed-in client, one request at a time.
class OliveBackupServerApi implements BackupServerApi {
  OliveBackupServerApi(this._api);
  final OliveApi _api;
  @override
  Future<Map<String, dynamic>> send(String method, String path,
          {Map<String, dynamic>? body, Map<String, String>? query, Map<String, String>? headers}) =>
      _api.backupSend(method, path, body: body, query: query, headers: headers);
}
