// OLIVE BRANCH — the Ed25519 device key every Olive device that takes part in pairing holds, and the
// pairing certificate an adult device signs for a child device. UNVERIFIED on a device; runs headless in CI.
// Spec: docs/superpowers/specs/2026-11-08-adult-gate-and-simple-pairing-design.md sections 3 and 6.
//
// The private seed is kept only in a sealed LocalStore area ('devicekey') and never leaves the device. The
// fingerprint (first 16 bytes of SHA-256 of the public key) names a device in a pairing session; the
// certificate binds ONE child device key to ONE family and ONE child, so a credential can never be used for a
// different child or family (scope stays exactly as the server path's per-device credential).
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'cpace.dart' show cat, lv;
import 'local_store.dart';

String b64(List<int> b) => base64Url.encode(b).replaceAll('=', '');
Uint8List unb64(String s) => Uint8List.fromList(base64Url.decode(base64Url.normalize(s)));

Future<Uint8List> fingerprintOf(List<int> publicKey) async =>
    Uint8List.fromList((await Sha256().hash(publicKey)).bytes.sublist(0, 16));

abstract class DeviceKeyRepository {
  Future<Uint8List?> loadSeed();
  Future<void> saveSeed(Uint8List seed);
  Future<void> clear();
}

class MemoryDeviceKeyRepository implements DeviceKeyRepository {
  Uint8List? _s;
  @override
  Future<Uint8List?> loadSeed() async => _s;
  @override
  Future<void> saveSeed(Uint8List seed) async => _s = seed;
  @override
  Future<void> clear() async => _s = null;
}

class LocalStoreDeviceKeyRepository implements DeviceKeyRepository {
  LocalStoreDeviceKeyRepository(this._ns);
  final LocalNamespace _ns;
  static const String _key = 'seed';
  @override
  Future<Uint8List?> loadSeed() async {
    final Object? raw = await _ns.get(_key);
    if (raw is! String) return null;
    try {
      final Uint8List s = unb64(raw);
      return s.length == 32 ? s : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveSeed(Uint8List seed) => _ns.put(_key, b64(seed));
  @override
  Future<void> clear() => _ns.delete(_key);
}

class DeviceKey {
  DeviceKey._(this._pair, this.publicKey, this.fingerprint);
  final SimpleKeyPair _pair;
  final Uint8List publicKey;
  final Uint8List fingerprint;

  /// Loads the key, or makes one on first use. A store that cannot be written still returns a working
  /// key for this run (the caller learns on the next run that it was not kept: pairing again is the cost).
  static Future<DeviceKey> loadOrCreate(DeviceKeyRepository repo, {List<int>? seedForTest}) async {
    Uint8List? seed;
    try {
      seed = await repo.loadSeed();
    } catch (_) {
      seed = null;
    }
    if (seed == null) {
      seed = Uint8List.fromList(seedForTest ?? await Ed25519().newKeyPair().then((SimpleKeyPair k) => k.extractPrivateKeyBytes()));
      try {
        await repo.saveSeed(seed);
      } catch (_) {
        // Held for this run only.
      }
    }
    final SimpleKeyPair pair = await Ed25519().newKeyPairFromSeed(seed);
    final Uint8List pub = Uint8List.fromList((await pair.extractPublicKey()).bytes);
    return DeviceKey._(pair, pub, await fingerprintOf(pub));
  }

  Future<Uint8List> sign(List<int> message) async =>
      Uint8List.fromList((await Ed25519().sign(message, keyPair: _pair)).bytes);

  static Future<bool> verify(List<int> publicKey, List<int> message, List<int> signature) async {
    if (publicKey.length != 32 || signature.length != 64) return false;
    try {
      return await Ed25519().verify(message,
          signature: Signature(signature, publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519)));
    } catch (_) {
      return false;
    }
  }
}

/// What an adult device signs for ONE child device in ONE family.
class PairingCert {
  const PairingCert({
    required this.childDeviceKey,
    required this.familyId,
    required this.childId,
    required this.adultFingerprint,
    required this.issuedAtMs,
    required this.certId,
    required this.signature,
  });
  final Uint8List childDeviceKey, adultFingerprint, signature;
  final String familyId, childId, certId;
  final int issuedAtMs;

  static Uint8List signedBytes(List<int> cpk, String fid, String cid, List<int> afp, int iat, String certId) =>
      cat(<List<int>>[
        lv(utf8.encode('olive-cert-v1')), lv(cpk), lv(utf8.encode(fid)), lv(utf8.encode(cid)),
        lv(afp), lv(utf8.encode('$iat')), lv(utf8.encode(certId)),
      ]);

  static Future<PairingCert> issue(DeviceKey adult, {
    required List<int> childDeviceKey,
    required String familyId,
    required String childId,
    required String certId,
    required int issuedAtMs,
  }) async {
    final Uint8List sig = await adult.sign(signedBytes(childDeviceKey, familyId, childId, adult.fingerprint, issuedAtMs, certId));
    return PairingCert(
        childDeviceKey: Uint8List.fromList(childDeviceKey), familyId: familyId, childId: childId,
        adultFingerprint: adult.fingerprint, issuedAtMs: issuedAtMs, certId: certId, signature: sig);
  }

  /// True only when [adultKey] really signed exactly these fields AND its fingerprint is the one named.
  Future<bool> verifiedBy(List<int> adultKey) async {
    final Uint8List fp = await fingerprintOf(adultKey);
    if (!_eq(fp, adultFingerprint)) return false;
    return DeviceKey.verify(adultKey, signedBytes(childDeviceKey, familyId, childId, adultFingerprint, issuedAtMs, certId), signature);
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'cpk': b64(childDeviceKey), 'fid': familyId, 'cid': childId, 'afp': b64(adultFingerprint),
        'iat': issuedAtMs, 'certId': certId, 'sig': b64(signature),
      };

  static PairingCert? fromJson(Object? raw) {
    if (raw is! Map) return null;
    try {
      final Object? cpk = raw['cpk'], fid = raw['fid'], cid = raw['cid'], afp = raw['afp'], iat = raw['iat'], id = raw['certId'], sig = raw['sig'];
      if (cpk is! String || fid is! String || cid is! String || afp is! String || iat is! int || id is! String || sig is! String) return null;
      return PairingCert(
          childDeviceKey: unb64(cpk), familyId: fid, childId: cid, adultFingerprint: unb64(afp),
          issuedAtMs: iat, certId: id, signature: unb64(sig));
    } catch (_) {
      return null;
    }
  }
}

bool _eq(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  int d = 0;
  for (int i = 0; i < a.length; i++) {
    d |= a[i] ^ b[i];
  }
  return d == 0;
}
