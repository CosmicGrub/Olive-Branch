// OLIVE BRANCH — the backup engine: gathers what must survive, seals it on the phone, and sends it. UNVERIFIED on a
// device; pure Dart, runs headless in CI. See docs/planning/BACKUP-RESTORE-CLIENT.md.
//
// WHAT IT DOES, in order.
//   1. GATHER. Every document the store holds whose area a backup of this kind takes (backup_classes.dart), each read
//      in one step (LocalNamespace.snapshot) so an area is one consistent picture. A family backup never takes a
//      private area (the journal, worry box, feelings, teen areas, or anything of hers); a keepsake backup never
//      takes a grown-up's records.
//   2. SEAL. Each area becomes canonical JSON, is cut into chunks and each chunk is sealed under a fresh data key; the
//      data key is sealed to the PUBLIC half of the recovery key (backup_crypto.dart); a manifest lists every area with
//      a content hash and its chunks, and is sealed too. The header is signed by this phone's own device key.
//   3. SEND. To every destination given, chunks first (skipping any the destination already has), the manifest LAST.
//      The sealed backup is kept in staging until every destination has it, so a run that is cut off carries on with
//      the same chunks (a resumable transfer) instead of sealing again.
//   4. CHECK. The manifest is read back and every chunk is confirmed present (a folder is also re-read and its chunks
//      re-hashed) before the backup counts as made.
//   5. TIDY. Only after a verified commit, generations older than [keepGenerations] from THIS phone are removed along
//      with the chunks nothing else uses. Nothing is deleted before the newer backup is whole.
//
// KILL ANYWHERE. A kill while gathering or sealing changes nothing on disk. A kill while sending leaves chunks with no
// manifest (waste the next run reuses) and the previous backup still the newest. A kill between the manifest and the
// tidy leaves one extra old backup. In every case the previous backup opens exactly as it did.
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'backup_classes.dart';
import 'backup_crypto.dart';
import 'backup_sink.dart';
import 'backup_state.dart';
import 'device_keys.dart' show DeviceKey, b64, unb64;
import 'local_services.dart';
import 'local_store.dart';

const int kBackupChunkBytes = 256 * 1024;
const int kKeepGenerations = 3;

/// The small signed, plain part of one backup: everything needed to find the sealed manifest and the chunks, and
/// nothing that says what is inside.
class BackupHeader {
  BackupHeader({
    required this.kind,
    required this.setId,
    required this.seq,
    required this.wrap,
    required this.mbox,
    required this.chunks,
    required this.writer,
    required this.sig,
  });
  final BackupKind kind;
  final String setId;
  final int seq;
  final Uint8List wrap, mbox, writer, sig;
  final List<String> chunks;

  /// `<10-digit seq>-<8 hex of the writing phone's public key>`: the manifest's name on every destination.
  String get name => '${seq.toString().padLeft(10, '0')}-${writerTag(writer)}';

  Uint8List toBytes() => Uint8List.fromList(utf8.encode(jsonEncode(<String, Object?>{
        kBackupFormat: kBackupFormatVersion,
        'kind': kind.name,
        'set': setId,
        'seq': seq,
        'wrap': b64(wrap),
        'mbox': b64(mbox),
        'chunks': chunks,
        'writer': b64(writer),
        'sig': b64(sig),
      })));

  /// Null for anything that is not a well-formed header; never throws.
  static BackupHeader? parse(Uint8List bytes) {
    try {
      final Object? j = jsonDecode(utf8.decode(bytes));
      if (j is! Map || j[kBackupFormat] != kBackupFormatVersion) return null;
      final Object? kind = j['kind'], set = j['set'], seq = j['seq'], wrap = j['wrap'], mbox = j['mbox'];
      final Object? chunks = j['chunks'], writer = j['writer'], sig = j['sig'];
      if (kind is! String || set is! String || seq is! int || seq < 1 || wrap is! String || mbox is! String) return null;
      if (chunks is! List || writer is! String || sig is! String || !isSetId(set)) return null;
      final BackupKind? k = BackupKind.values.where((BackupKind v) => v.name == kind).firstOrNull;
      if (k == null) return null;
      final List<String> ids = <String>[];
      for (final Object? c in chunks) {
        if (c is! String || !isChunkId(c)) return null;
        ids.add(c);
      }
      final Uint8List w = unb64(writer), s = unb64(sig);
      if (w.length != 32 || s.length != 64) return null;
      return BackupHeader(
          kind: k, setId: set, seq: seq, wrap: unb64(wrap), mbox: unb64(mbox), chunks: ids, writer: w, sig: s);
    } catch (_) {
      return null;
    }
  }

  Future<bool> signatureOk() => DeviceKey.verify(
      writer,
      headerSigMessage(kind: kind, setId: setId, seq: seq, wrap: wrap, mbox: mbox, chunks: chunks, writer: writer),
      sig);
}

String writerTag(List<int> writerPublicKey) => hexString(writerPublicKey.sublist(0, 4));

/// One area as it was read.
class AreaDoc {
  AreaDoc(this.name, this.schema, this.data, this.hash, this.bytes);
  final AreaName name;
  final int schema;
  final Map<String, Object?> data;

  /// SHA-256 of the canonical JSON of [data]: the "content hash" a restore must reproduce.
  final String hash;
  final int bytes;
}

/// How one destination did.
class SinkReport {
  const SinkReport({
    required this.label,
    required this.kindWord,
    required this.ok,
    this.code,
    this.uploaded = 0,
    this.skipped = 0,
  });
  final String label, kindWord;
  final bool ok;

  /// Why it did not finish: a [BackupSinkException.code].
  final String? code;

  /// Chunks sent this run, and chunks the destination already had (a resumed run skips what is done).
  final int uploaded, skipped;
}

class BackupReport {
  const BackupReport({required this.sinks, required this.seq, required this.areas, required this.bytes, required this.resumed});
  final List<SinkReport> sinks;
  final int seq, areas, bytes;

  /// True when a cut-off run was carried on instead of sealing again.
  final bool resumed;

  /// At least one destination holds a verified, committed backup.
  bool get ok => sinks.any((SinkReport s) => s.ok);
  bool get allOk => sinks.isNotEmpty && sinks.every((SinkReport s) => s.ok);
}

/// Thrown when there is nothing to seal to yet: no public key was set up for this kind of backup.
class BackupNotSetUp implements Exception {
  const BackupNotSetUp(this.kind);
  final BackupKind kind;
  @override
  String toString() => 'BackupNotSetUp(${kind.name})';
}

/// A grown-up's phone makes the family backup; a child's tablet makes only the keepsake. The engine refuses the other
/// combination so a tablet can never be asked to read grown-up records into a backup.
enum BackupRole { guardian, child }

class BackupEngine {
  BackupEngine({
    required this.services,
    required this.state,
    required this.staging,
    required this.writer,
    required this.role,
    DateTime Function()? clock,
    Random? random,
    this.chunkBytes = kBackupChunkBytes,
    this.keepGenerations = kKeepGenerations,
  })  : _clock = clock ?? DateTime.now,
        _random = random;

  final LocalServices services;
  final BackupStateStore state;
  final BackupStaging staging;
  final DeviceKey writer;
  final BackupRole role;
  final DateTime Function() _clock;
  final Random? _random;
  final int chunkBytes;
  final int keepGenerations;

  int get _nowMs => _clock().millisecondsSinceEpoch;

  void _roleCheck(BackupKind kind) {
    final bool ok = role == BackupRole.guardian ? kind == BackupKind.family : kind == BackupKind.keepsake;
    if (!ok) throw StateError('this device role cannot make a ${kind.name} backup');
  }

  /// Every area of [kind] this phone holds, read as one picture each. Empty and damaged documents are left out.
  Future<List<AreaDoc>> gather(BackupKind kind) async {
    _roleCheck(kind);
    final List<AreaDoc> out = <AreaDoc>[];
    for (final String n in await services.store.namespaces()) {
      final AreaName? an = parseAreaName(n);
      if (an == null || !backupTakes(kind, an.area)) continue;
      final LocalDataEntry e = localDataEntry(an.area);
      final LocalNamespace ns = services.store
          .open(NamespaceSpec(name: n, schema: e.schema, encrypted: e.encrypted, maxBytes: e.maxBytes));
      final Map<String, Object?> data = await ns.snapshot();
      if (ns.recovery != RecoveryKind.none || data.isEmpty) continue;
      final List<int> bytes = utf8.encode(canonicalJson(data));
      out.add(AreaDoc(an, e.schema, data, await sha256HexOf(bytes), bytes.length));
    }
    out.sort((AreaDoc a, AreaDoc b) => a.name.namespace.compareTo(b.name.namespace));
    return out;
  }

  /// Namespace -> content hash for every area of [kind]. The round trip claim is "this map is equal before and after".
  Future<Map<String, String>> areaHashes(BackupKind kind) async =>
      <String, String>{for (final AreaDoc d in await gather(kind)) d.name.namespace: d.hash};

  Future<String> _rootHash(List<int> publicKey, List<AreaDoc> docs) => sha256HexOf(utf8.encode(<String>[
        hexString(publicKey),
        for (final AreaDoc d in docs) '${d.name.namespace}|${d.hash}',
      ].join('\n')));

  /// Makes (or carries on) a backup of [kind] to every sink. Never throws for a destination problem: each sink's
  /// outcome is in the report. Throws [BackupNotSetUp] when no public key exists yet.
  Future<BackupReport> backUp({required BackupKind kind, required List<BackupSink> sinks}) async {
    _roleCheck(kind);
    final Uint8List? pk = await state.publicKey(kind);
    if (pk == null) throw BackupNotSetUp(kind);
    final String setId = await backupSetId(pk, kind);
    final List<AreaDoc> docs = await gather(kind);
    final String root = await _rootHash(pk, docs);

    StagedBackup? staged = await staging.load(kind);
    bool resumed = false;
    if (staged != null && staged.rootHash == root && staged.setId == setId) {
      resumed = true;
    } else {
      final int seq = await _nextSeq(kind, setId, sinks);
      staged = await _seal(kind: kind, pk: pk, setId: setId, docs: docs, seq: seq, root: root);
      await staging.save(staged);
    }

    final BackupHeader header = BackupHeader.parse(staged.header)!;
    final List<SinkReport> reports = <SinkReport>[];
    for (final BackupSink sink in sinks) {
      reports.add(await _push(sink, staged, header));
    }
    final int bytes = staged.chunks.values.fold<int>(0, (int a, Uint8List c) => a + c.length);
    for (final SinkReport r in reports) {
      if (r.ok) {
        await state.recordSuccess(
            kind,
            BackupRecord(
                atMs: _nowMs, seq: staged.seq, destination: r.label, destinationKind: r.kindWord,
                areas: docs.length, bytes: bytes));
      } else {
        await state.recordFailure(kind, _nowMs, r.code ?? 'unreachable');
      }
    }
    if (reports.any((SinkReport r) => r.ok)) await state.setLastSeq(kind, staged.seq);
    // Staging is dropped only when EVERY destination has the backup; otherwise the next run resumes with it.
    if (reports.isNotEmpty && reports.every((SinkReport r) => r.ok)) await staging.clear(kind);
    return BackupReport(sinks: reports, seq: staged.seq, areas: docs.length, bytes: bytes, resumed: resumed);
  }

  Future<int> _nextSeq(BackupKind kind, String setId, List<BackupSink> sinks) async {
    int top = await state.lastSeq(kind);
    for (final BackupSink s in sinks) {
      try {
        for (final String n in await s.listManifests(setId)) {
          final int? q = int.tryParse(n.substring(0, 10));
          if (q != null && q > top) top = q;
        }
      } catch (_) {
        // an unreachable destination just does not raise the number; its own numbering is checked when it is reached
      }
    }
    return top + 1;
  }

  Future<StagedBackup> _seal({
    required BackupKind kind,
    required Uint8List pk,
    required String setId,
    required List<AreaDoc> docs,
    required int seq,
    required String root,
  }) async {
    for (final AreaDoc d in docs) {
      // A last line of defence: whatever the caller did, a private area never enters a family backup.
      if (!backupTakes(kind, d.name.area)) throw StateError('${d.name.area} is not part of a ${kind.name} backup');
    }
    final Uint8List dk = newDataKey(random: _random);
    final Uint8List wrap = await wrapDataKey(recipientPublic: pk, dk: dk, setId: setId, kind: kind, random: _random);
    final Map<String, Uint8List> chunks = <String, Uint8List>{};
    final List<String> order = <String>[];
    final List<Map<String, Object?>> areas = <Map<String, Object?>>[];
    for (final AreaDoc d in docs) {
      final Uint8List bytes = Uint8List.fromList(utf8.encode(canonicalJson(d.data)));
      final List<String> ids = <String>[];
      for (int off = 0; off < bytes.length; off += chunkBytes) {
        final Uint8List sealed = await sealUnder(dk, bytes.sublist(off, min(off + chunkBytes, bytes.length)), chunkAad(setId));
        final String id = await sha256HexOf(sealed);
        if (chunks.putIfAbsent(id, () => sealed) == sealed) order.add(id);
        ids.add(id);
      }
      areas.add(<String, Object?>{
        'ns': d.name.namespace,
        'scope': d.name.scope.name,
        'owner': d.name.owner,
        'area': d.name.area,
        'schema': d.schema,
        'hash': d.hash,
        'bytes': d.bytes,
        'chunks': ids,
      });
    }
    final Map<String, Object?> manifest = <String, Object?>{
      'v': 1,
      'kind': kind.name,
      'createdAtMs': _nowMs,
      'root': root,
      'areas': areas,
    };
    final Uint8List mbox = await sealUnder(dk, utf8.encode(jsonEncode(manifest)), manifestAad(setId, seq));
    final Uint8List wpk = writer.publicKey;
    final Uint8List sig = await writer.sign(headerSigMessage(
        kind: kind, setId: setId, seq: seq, wrap: wrap, mbox: mbox, chunks: order, writer: wpk));
    final BackupHeader header =
        BackupHeader(kind: kind, setId: setId, seq: seq, wrap: wrap, mbox: mbox, chunks: order, writer: wpk, sig: sig);
    return StagedBackup(
        kind: kind, rootHash: root, setId: setId, seq: seq, header: header.toBytes(), chunkIds: order, chunks: chunks);
  }

  Future<SinkReport> _push(BackupSink sink, StagedBackup s, BackupHeader header) async {
    int uploaded = 0, skipped = 0;
    try {
      for (final String id in s.chunkIds) {
        if (await sink.hasChunk(s.setId, id)) {
          skipped++;
          continue;
        }
        await sink.putChunk(s.setId, id, s.chunks[id]!);
        uploaded++;
      }
      // The commit. Everything above is invisible to a restore until this lands.
      await sink.putManifest(s.setId, header.name, s.header);
      await _verify(sink, s, header);
      try {
        await _tidy(sink, s.setId, header);
      } catch (_) {
        // Tidying is a courtesy; a failure leaves an extra old backup, never a missing new one.
      }
      return SinkReport(label: sink.label, kindWord: sink.kindWord, ok: true, uploaded: uploaded, skipped: skipped);
    } on BackupSinkException catch (e) {
      return SinkReport(label: sink.label, kindWord: sink.kindWord, ok: false, code: e.code, uploaded: uploaded, skipped: skipped);
    }
  }

  Future<void> _verify(BackupSink sink, StagedBackup s, BackupHeader header) async {
    final Uint8List? back = await sink.getManifest(s.setId, header.name);
    if (back == null || !_same(back, s.header)) throw const BackupSinkException('damaged', 'manifest');
    for (final String id in s.chunkIds) {
      if (sink.kindWord == 'server') {
        if (!await sink.hasChunk(s.setId, id)) throw const BackupSinkException('damaged', 'chunk');
      } else {
        final Uint8List? c = await sink.getChunk(s.setId, id);
        if (c == null || await sha256HexOf(c) != id) throw const BackupSinkException('damaged', 'chunk');
      }
    }
  }

  static bool _same(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Removes this phone's backups beyond the newest [keepGenerations], and the chunks no remaining backup uses.
  Future<void> _tidy(BackupSink sink, String setId, BackupHeader newest) async {
    final String mine = writerTag(newest.writer);
    final List<String> all = await sink.listManifests(setId);
    final List<String> ours = <String>[for (final String n in all) if (n.endsWith('-$mine')) n]..sort();
    if (ours.length <= keepGenerations) return;
    final List<String> drop = ours.sublist(0, ours.length - keepGenerations);
    final Set<String> keepIds = <String>{};
    for (final String n in all) {
      if (drop.contains(n)) continue;
      final Uint8List? b = await sink.getManifest(setId, n);
      final BackupHeader? h = b == null ? null : BackupHeader.parse(b);
      if (h != null) keepIds.addAll(h.chunks);
    }
    for (final String n in drop) {
      final Uint8List? b = await sink.getManifest(setId, n);
      final BackupHeader? h = b == null ? null : BackupHeader.parse(b);
      await sink.deleteManifest(setId, n);
      if (h != null) {
        for (final String id in h.chunks) {
          if (!keepIds.contains(id)) await sink.deleteChunk(setId, id);
        }
      }
    }
  }
}
