// OLIVE BRANCH — the sealing for backups: what is locked on the phone before anything leaves it. UNVERIFIED on a
// device and has had no outside review (decision D2, composed from vetted primitives); pure Dart, runs headless in CI.
// See docs/planning/BACKUP-RESTORE-CLIENT.md.
//
// WRITE-ONLY BACKUPS. The recovery sheet's words are a seed. From it two things are derived with HKDF-SHA256, once,
// for each kind of backup (the family's and a child's keepsake): an X25519 key pair. The PUBLIC half is all a phone
// keeps. Every backup gets a fresh random data key (DK); DK is sealed to the public half (an ephemeral X25519
// agreement, HKDF, ChaCha20-Poly1305, the set and kind bound in as associated data); every chunk and the manifest
// are sealed under DK with AES-256-GCM. So a phone can make backups all day and hold nothing that opens one, and
// neither a server nor a file on a drive can read one.
//
// WHAT THE SEAL DOES NOT DO. Anyone who holds the public half can make a backup that opens (it is not secret from
// the phones that use it). The header is therefore signed by the writing device's own key, so a backup says which
// phone wrote it; a restore uses the writer to pick the newest backup of each phone. A person who holds both the
// words and a copy of the backup can read it: the sheet is a house key to a safe.
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'backup_words.dart';
import 'cpace.dart' show cat, lv;

/// The two kinds of backup, each under its own key pair so one sheet can never open the other.
enum BackupKind {
  /// What a grown-up's phone holds that the family needs back. Opened with the family's recovery sheet.
  family,

  /// What a child's tablet holds (her home, and the things that are hers). Opened only with the keepsake sheet,
  /// which no grown-up's backup key is.
  keepsake,
}

const String kBackupFormat = 'olive_backup';
const int kBackupFormatVersion = 1;

String hexString(List<int> bytes) {
  final StringBuffer s = StringBuffer();
  for (final int b in bytes) {
    s.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return s.toString();
}

Future<Uint8List> sha256Of(List<int> data) async => Uint8List.fromList((await Sha256().hash(data)).bytes);

Future<String> sha256HexOf(List<int> data) async => hexString(await sha256Of(data));

/// The key pair derived from a sheet. [publicKey] is what phones keep; the secret half exists only inside this object
/// for the length of a restore.
class BackupKeyPair {
  BackupKeyPair._(this.publicKey, this._pair);
  final Uint8List publicKey;
  final SimpleKeyPair _pair;
}

Future<BackupKeyPair> deriveBackupKeyPair(RecoveryKey key, BackupKind kind) async {
  final SecretKey seed32 = await Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
      secretKey: SecretKey(key.seed),
      nonce: utf8.encode('olive/backup/salt/v1'),
      info: utf8.encode('olive/backup/x25519/v1/${kind.name}'));
  final SimpleKeyPair pair = await X25519().newKeyPairFromSeed(await seed32.extractBytes());
  return BackupKeyPair._(Uint8List.fromList((await pair.extractPublicKey()).bytes), pair);
}

/// The opaque name of one family's (or tablet's) backups on any destination: a hash of the PUBLIC half, so the
/// words are enough to find it again and a destination learns nothing it could reverse.
Future<String> backupSetId(List<int> publicKey, BackupKind kind) async => hexString(
    (await sha256Of(cat(<List<int>>[lv(utf8.encode('olive/backup/set/v1')), lv(utf8.encode(kind.name)), lv(publicKey)])))
        .sublist(0, 16));

Uint8List _wrapAad(String setId, BackupKind kind) =>
    cat(<List<int>>[lv(utf8.encode('olive-backup-wrap-aad-v1')), lv(utf8.encode(setId)), lv(utf8.encode(kind.name))]);

Future<SecretKey> _wrapKey(List<int> shared, List<int> ephPub, List<int> recipientPub) =>
    Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
        secretKey: SecretKey(shared),
        nonce: cat(<List<int>>[lv(ephPub), lv(recipientPub)]),
        info: utf8.encode('olive/backup/wrap/v1'));

Uint8List newDataKey({Random? random}) {
  final Random r = random ?? Random.secure();
  return Uint8List.fromList(List<int>.generate(32, (_) => r.nextInt(256)));
}

/// Seals the 32-byte data key [dk] to [recipientPublic]. Output: ephemeral public (32) | ciphertext (32) | tag (16).
Future<Uint8List> wrapDataKey({
  required List<int> recipientPublic,
  required List<int> dk,
  required String setId,
  required BackupKind kind,
  Random? random,
}) async {
  if (dk.length != 32 || recipientPublic.length != 32) throw ArgumentError('cannot wrap');
  final Random r = random ?? Random.secure();
  final SimpleKeyPair eph =
      await X25519().newKeyPairFromSeed(List<int>.generate(32, (_) => r.nextInt(256)));
  final Uint8List ephPub = Uint8List.fromList((await eph.extractPublicKey()).bytes);
  final List<int> shared = await (await X25519()
          .sharedSecretKey(keyPair: eph, remotePublicKey: SimplePublicKey(recipientPublic, type: KeyPairType.x25519)))
      .extractBytes();
  final SecretBox box = await Chacha20.poly1305Aead().encrypt(dk,
      secretKey: await _wrapKey(shared, ephPub, recipientPublic),
      nonce: Uint8List(12), // DK is wrapped under a one-time ephemeral key, so a fixed nonce is safe
      aad: _wrapAad(setId, kind));
  return cat(<List<int>>[ephPub, box.cipherText, box.mac.bytes]);
}

/// Opens a wrapped data key with the key pair derived from the sheet. Null on anything wrong (a different family's
/// sheet, the other kind, a different set, a damaged wrap): it never throws.
Future<Uint8List?> unwrapDataKey({
  required BackupKeyPair pair,
  required List<int> wrapped,
  required String setId,
  required BackupKind kind,
}) async {
  if (wrapped.length != 80) return null;
  try {
    final Uint8List ephPub = Uint8List.fromList(wrapped.sublist(0, 32));
    final List<int> shared = await (await X25519().sharedSecretKey(
            keyPair: pair._pair, remotePublicKey: SimplePublicKey(ephPub, type: KeyPairType.x25519)))
        .extractBytes();
    final List<int> plain = await Chacha20.poly1305Aead().decrypt(
        SecretBox(wrapped.sublist(32, 64), nonce: Uint8List(12), mac: Mac(wrapped.sublist(64, 80))),
        secretKey: await _wrapKey(shared, ephPub, pair.publicKey),
        aad: _wrapAad(setId, kind));
    return plain.length == 32 ? Uint8List.fromList(plain) : null;
  } catch (_) {
    return null;
  }
}

final AesGcm _aes = AesGcm.with256bits();

Uint8List chunkAad(String setId) => cat(<List<int>>[lv(utf8.encode('olive-backup-chunk-v1')), lv(utf8.encode(setId))]);

Uint8List manifestAad(String setId, int seq) => cat(<List<int>>[
      lv(utf8.encode('olive-backup-manifest-v1')), lv(utf8.encode(setId)), lv(utf8.encode('$seq')),
    ]);

/// nonce (12) | ciphertext | tag (16).
Future<Uint8List> sealUnder(List<int> dk, List<int> plain, List<int> aad) async {
  final SecretBox box = await _aes.encrypt(plain, secretKey: SecretKey(dk), aad: aad);
  return Uint8List.fromList(box.concatenation());
}

/// Null when the box does not authenticate (damaged, another key, other associated data).
Future<Uint8List?> openUnder(List<int> dk, List<int> box, List<int> aad) async {
  if (box.length < 12 + 16) return null;
  try {
    final SecretBox parsed = SecretBox.fromConcatenation(box, nonceLength: 12, macLength: 16);
    return Uint8List.fromList(await _aes.decrypt(parsed, secretKey: SecretKey(dk), aad: aad));
  } catch (_) {
    return null;
  }
}

/// Deterministic JSON: object keys sorted at every level, no spaces. The content hash of an area is the hash of THIS,
/// so two stores holding the same data hash the same whatever order their keys were written in.
String canonicalJson(Object? v) {
  final StringBuffer b = StringBuffer();
  void w(Object? x) {
    if (x is Map) {
      final List<String> keys = x.keys.map((Object? k) => '$k').toList()..sort();
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

/// The message a writing device signs over a backup's header (everything that is not the signature itself).
Uint8List headerSigMessage({
  required BackupKind kind,
  required String setId,
  required int seq,
  required List<int> wrap,
  required List<int> mbox,
  required List<String> chunks,
  required List<int> writer,
}) =>
    cat(<List<int>>[
      lv(utf8.encode('olive-backup-header-v1')),
      lv(utf8.encode(kind.name)),
      lv(utf8.encode(setId)),
      lv(utf8.encode('$seq')),
      lv(wrap),
      lv(mbox),
      lv(utf8.encode(chunks.join(','))),
      lv(writer),
    ]);
