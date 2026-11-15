// OLIVE BRANCH — the family's two keys, kept apart on purpose, and the way a key reaches exactly one device.
// UNVERIFIED on a device; pure Dart, runs headless in CI. Spec: docs/planning/FAMILY-IDENTITY-DESIGN.md sections
// 3.1, 3.3 and 3.5.
//
//  FK, the FAMILY key, is held by every member device INCLUDING a child's tablet. It is for binding and for proving
//  "I already belong to this family". Anything FK can open, a child device can open, so it must never guard
//  anything a child must not read.
//  GK, the GUARDIAN key, is held by grown-up devices ONLY. It exists so that the first feature that shares
//  grown-up-only data between two grown-ups (care notes, expenses; P6, P7) does not have to invent a key. A child
//  device is never given GK: [FamilyKeyring] has no way to store one on a child device, and the key-rotation builder
//  never wraps one to a device that the ledger does not list as a grown-up's.
//  Neither key is a signing authority. Authority is only ever an Ed25519 signature by a guardian device.
//
// A new epoch is fresh random bytes, never a ratchet of the old one: a removed grown-up knows the old key and a
// ratchet would let them compute forward.
//
// A key reaches one device as a "wrap": an ephemeral X25519 key agreement with that device's certified agreement
// key, HKDF-SHA256, and ChaCha20-Poly1305 with the family id, epoch, key kind and recipient bound in as associated
// data, so a wrap cannot be lifted to another family, epoch, kind or device. This is a composition of vetted
// primitives and has had no outside review (decision D2).
import 'dart:math';
import 'dart:typed_data';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import 'cpace.dart' show cat, lv;
import 'device_keys.dart' show DeviceKey;
import 'family_ledger.dart';
import 'family_ledger_state.dart';

const String kFkBind = 'olive/fk/bind/v1';
const String kFkMember = 'olive/fk/member/v1';
const String kFkDiscovery = 'olive/fk/discovery/v1';
const String kGkSeal = 'olive/gk/seal/v1';
const String _wrapInfo = 'olive/wrap/v1';

Uint8List _randomBytes(Random r, int n) => Uint8List.fromList(List<int>.generate(n, (_) => r.nextInt(256)));

/// SHA-256 over a domain, the family id, the epoch and the key: published in the ledger so a device that unwrapped a
/// key can check it got the right one, without the commitment revealing the key (it is 256 random bits).
Future<Uint8List> keyCommit(String kind, List<int> fid, int epoch, List<int> key) async =>
    Uint8List.fromList((await Sha256().hash(cat(<List<int>>[
      lv(utf8.encode('olive-key-commit-v1')), lv(utf8.encode(kind)), lv(fid), lv(ascii.encode('$epoch')), lv(key),
    ])))
        .bytes);

Future<Uint8List> deriveFamilySubkey(List<int> key, String purpose, {List<int> salt = const <int>[]}) async {
  final SecretKey k = await Hkdf(hmac: Hmac.sha256(), outputLength: 32)
      .deriveKey(secretKey: SecretKey(key), nonce: salt, info: utf8.encode(purpose));
  return Uint8List.fromList(await k.extractBytes());
}

Uint8List _wrapAad(List<int> fid, int epoch, String kind, List<int> recipientDeviceKey) => cat(<List<int>>[
      lv(utf8.encode('olive-wrap-aad-v1')), lv(fid), lv(ascii.encode('$epoch')), lv(utf8.encode(kind)),
      lv(recipientDeviceKey),
    ]);

Future<SecretKey> _wrapKey(List<int> shared, List<int> ephPub, List<int> recipientAgree) async =>
    Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
        secretKey: SecretKey(shared), nonce: cat(<List<int>>[lv(ephPub), lv(recipientAgree)]), info: utf8.encode(_wrapInfo));

/// Seals [key] (32 bytes) to ONE device. Output: ephemeral public key (32) | ciphertext (32) | tag (16) = 80 bytes.
Future<Uint8List> wrapKey({
  required List<int> fid,
  required int epoch,
  required String kind, // 'fk' | 'gk'
  required DeviceRecord recipient,
  required List<int> key,
  Random? random,
}) async {
  final Uint8List? agree = recipient.agree;
  if ((kind != 'fk' && kind != 'gk') || key.length != 32 || agree == null) throw ArgumentError('cannot wrap');
  final SimpleKeyPair eph = await X25519().newKeyPairFromSeed(_randomBytes(random ?? Random.secure(), 32));
  final Uint8List ephPub = Uint8List.fromList((await eph.extractPublicKey()).bytes);
  final Uint8List shared = Uint8List.fromList(await (await X25519().sharedSecretKey(
          keyPair: eph, remotePublicKey: SimplePublicKey(agree, type: KeyPairType.x25519)))
      .extractBytes());
  final SecretBox box = await Chacha20.poly1305Aead().encrypt(key,
      secretKey: await _wrapKey(shared, ephPub, agree),
      nonce: Uint8List(12), // the key is unique to this one ephemeral, so a fixed nonce is safe
      aad: _wrapAad(fid, epoch, kind, recipient.key));
  return cat(<List<int>>[ephPub, box.cipherText, box.mac.bytes]);
}

/// Opens a wrap addressed to this device. Null on anything wrong: a wrap for another device, family, epoch or kind
/// does not open.
Future<Uint8List?> unwrapKey({
  required List<int> fid,
  required int epoch,
  required String kind,
  required List<int> ownDeviceKey,
  required AgreementKey agreement,
  required List<int> wrapped,
}) async {
  if (wrapped.length != 80) return null;
  try {
    final Uint8List ephPub = Uint8List.fromList(wrapped.sublist(0, 32));
    final Uint8List shared = await agreement.sharedSecret(ephPub);
    final List<int> plain = await Chacha20.poly1305Aead().decrypt(
        SecretBox(wrapped.sublist(32, 64), nonce: Uint8List(12), mac: Mac(wrapped.sublist(64, 80))),
        secretKey: await _wrapKey(shared, ephPub, agreement.publicKey),
        aad: _wrapAad(fid, epoch, kind, ownDeviceKey));
    return plain.length == 32 ? Uint8List.fromList(plain) : null;
  } catch (_) {
    return null;
  }
}

/// What one device holds. A child device's keyring can never hold a GK.
class FamilyKeyring {
  FamilyKeyring({required this.guardianDevice});

  /// True on a grown-up's device. This is chosen when the keyring is made and never changes.
  final bool guardianDevice;
  final Map<int, Uint8List> _fk = <int, Uint8List>{}, _gk = <int, Uint8List>{};

  List<int> get fkEpochs => (_fk.keys.toList()..sort());
  List<int> get gkEpochs => (_gk.keys.toList()..sort());
  Uint8List? fk(int epoch) => _fk[epoch];
  Uint8List? gk(int epoch) => _gk[epoch];
  int get newestEpoch => _fk.isEmpty ? -1 : fkEpochs.last;

  void putFk(int epoch, List<int> key) {
    if (key.length != 32) throw ArgumentError('family key must be 32 bytes');
    _fk[epoch] = Uint8List.fromList(key);
  }

  /// Throws on a child device. This is the one place the rule "a child device never holds the guardian-only key" lives.
  void putGk(int epoch, List<int> key) {
    if (!guardianDevice) throw StateError('a child device never holds the guardian-only key');
    if (key.length != 32) throw ArgumentError('guardian key must be 32 bytes');
    _gk[epoch] = Uint8List.fromList(key);
  }

  /// The key for sealing grown-up-only data. Throws on a child device.
  Future<Uint8List> guardianSealKey(int epoch) async {
    final Uint8List? k = _gk[epoch];
    if (!guardianDevice || k == null) throw StateError('no guardian key on this device');
    return deriveFamilySubkey(k, kGkSeal);
  }

  Future<Uint8List> familySubkey(int epoch, String purpose, {List<int> salt = const <int>[]}) async {
    final Uint8List? k = _fk[epoch];
    if (k == null) throw StateError('no family key for that epoch');
    return deriveFamilySubkey(k, purpose, salt: salt);
  }
}

/// Seals grown-up-only data. Only a grown-up's device can build the key. Nothing in the app uses this yet.
Future<Uint8List> guardianSeal(FamilyKeyring ring, int epoch, List<int> plain, {List<int> aad = const <int>[], Random? random}) async {
  final Uint8List nonce = _randomBytes(random ?? Random.secure(), 12);
  final SecretBox box = await Chacha20.poly1305Aead()
      .encrypt(plain, secretKey: SecretKey(await ring.guardianSealKey(epoch)), nonce: nonce, aad: aad);
  return cat(<List<int>>[nonce, box.cipherText, box.mac.bytes]);
}

Future<Uint8List?> guardianOpen(FamilyKeyring ring, int epoch, List<int> sealed, {List<int> aad = const <int>[]}) async {
  if (sealed.length < 28) return null;
  try {
    final List<int> plain = await Chacha20.poly1305Aead().decrypt(
        SecretBox(sealed.sublist(12, sealed.length - 16), nonce: sealed.sublist(0, 12), mac: Mac(sealed.sublist(sealed.length - 16))),
        secretKey: SecretKey(await ring.guardianSealKey(epoch)),
        aad: aad);
    return Uint8List.fromList(plain);
  } catch (_) {
    return null;
  }
}

/// A new epoch ready to be signed into a `key.rotate` entry.
class RotationPlan {
  RotationPlan(this.epoch, this.fk, this.gk, this.body);
  final int epoch;
  final Uint8List fk, gk;

  /// The `key.rotate` body: epoch, the two commitments, and one wrap per device the ledger lists with an agreement key.
  /// The guardian-only key is wrapped to a grown-up's device only.
  final Map<String, Object?> body;
}

/// Builds the next epoch for every device [state] lists. A device the ledger does not list (a removed grown-up, a
/// revoked tablet, a pending person) gets no wrap and so learns nothing. A legacy tablet with no agreement key yet
/// gets none either (it receives its keys when it upgrades).
Future<RotationPlan> planKeyRotation(LedgerState state, {Random? random}) async {
  if (!state.ok) throw StateError('no ledger');
  final Random r = random ?? Random.secure();
  final int epoch = state.epoch + 1;
  final Uint8List fk = _randomBytes(r, 32), gk = _randomBytes(r, 32);
  final List<Map<String, Object?>> wraps = <Map<String, Object?>>[];
  for (final LedgerDevice d in state.devices) {
    final Uint8List? agree = d.agree;
    if (agree == null) continue;
    final DeviceRecord rec = DeviceRecord(key: d.key, agree: agree);
    wraps.add(<String, Object?>{
      'to': d.key,
      'fk': await wrapKey(fid: state.fid!, epoch: epoch, kind: 'fk', recipient: rec, key: fk, random: r),
      'gk': d.kind == 'guardian'
          ? await wrapKey(fid: state.fid!, epoch: epoch, kind: 'gk', recipient: rec, key: gk, random: r)
          : null,
    });
  }
  return RotationPlan(epoch, fk, gk, <String, Object?>{
    'epoch': epoch,
    'fkc': await keyCommit('fk', state.fid!, epoch, fk),
    'gkc': await keyCommit('gk', state.fid!, epoch, gk),
    'wraps': wraps,
  });
}

/// Opens this device's wraps from a `key.rotate` body and puts what it can open into [ring], checking each key
/// against the published commitment. A child device's keyring takes the FK wrap only.
Future<bool> openKeyRotation({
  required List<int> fid,
  required Map<String, Object?> body,
  required DeviceKey device,
  required AgreementKey agreement,
  required FamilyKeyring ring,
}) async {
  final int epoch = body['epoch']! as int;
  for (final Object? w in body['wraps']! as List) {
    final Map<String, Object?> m = w! as Map<String, Object?>;
    if (!bytesEqual(m['to']! as Uint8List, device.publicKey)) continue;
    final Uint8List? fk = await unwrapKey(
        fid: fid, epoch: epoch, kind: 'fk', ownDeviceKey: device.publicKey, agreement: agreement, wrapped: m['fk']! as Uint8List);
    if (fk == null || !bytesEqual(await keyCommit('fk', fid, epoch, fk), body['fkc']! as Uint8List)) return false;
    ring.putFk(epoch, fk);
    final Object? gw = m['gk'];
    if (gw != null && ring.guardianDevice) {
      final Uint8List? gk = await unwrapKey(
          fid: fid, epoch: epoch, kind: 'gk', ownDeviceKey: device.publicKey, agreement: agreement, wrapped: gw as Uint8List);
      if (gk == null || !bytesEqual(await keyCommit('gk', fid, epoch, gk), body['gkc']! as Uint8List)) return false;
      ring.putGk(epoch, gk);
    }
    return true;
  }
  return false; // nothing was addressed to this device: it gets nothing
}
