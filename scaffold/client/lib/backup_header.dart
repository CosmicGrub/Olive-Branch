// OLIVE BRANCH — the small plain, signed part of one backup. UNVERIFIED on a device; pure Dart, runs headless in CI.
// See docs/planning/BACKUP-RESTORE-CLIENT.md.
import 'dart:convert';
import 'dart:typed_data';

import 'backup_crypto.dart';
import 'backup_names.dart';
import 'device_keys.dart' show DeviceKey, b64, unb64;

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
    required this.cert,
    required this.sig,
  });
  final BackupKind kind;
  final String setId;
  final int seq;
  final Uint8List wrap, mbox, writer, cert, sig;
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
        'cert': b64(cert),
        'sig': b64(sig),
      })));

  /// Null for anything that is not a well-formed header; never throws.
  static BackupHeader? parse(Uint8List bytes) {
    try {
      final Object? j = jsonDecode(utf8.decode(bytes));
      if (j is! Map || j[kBackupFormat] != kBackupFormatVersion) return null;
      final Object? kind = j['kind'], set = j['set'], seq = j['seq'], wrap = j['wrap'], mbox = j['mbox'];
      final Object? chunks = j['chunks'], writer = j['writer'], sig = j['sig'], cert = j['cert'];
      if (kind is! String || set is! String || seq is! int || seq < 1 || wrap is! String || mbox is! String) return null;
      if (chunks is! List || writer is! String || sig is! String || cert is! String || !isSetId(set)) return null;
      final BackupKind? k = BackupKind.values.where((BackupKind v) => v.name == kind).firstOrNull;
      if (k == null) return null;
      final List<String> ids = <String>[];
      for (final Object? c in chunks) {
        if (c is! String || !isChunkId(c)) return null;
        ids.add(c);
      }
      final Uint8List w = unb64(writer), s = unb64(sig), c = unb64(cert);
      if (w.length != 32 || s.length != 64 || c.length != 64) return null;
      return BackupHeader(
          kind: k, setId: set, seq: seq, wrap: unb64(wrap), mbox: unb64(mbox), chunks: ids, writer: w, cert: c, sig: s);
    } catch (_) {
      return null;
    }
  }

  Future<bool> signatureOk() => DeviceKey.verify(
      writer,
      headerSigMessage(
          kind: kind, setId: setId, seq: seq, wrap: wrap, mbox: mbox, chunks: chunks, writer: writer, cert: cert),
      sig);

  /// True when the sheet's own key certified the phone that wrote this: the only kind of backup a restore accepts.
  Future<bool> certifiedBy(List<int> authorityPublic) => BackupAuthority.verifyWriter(authorityPublic, kind, writer, cert);
}

String writerTag(List<int> writerPublicKey) => hexString(writerPublicKey.sublist(0, 4));
