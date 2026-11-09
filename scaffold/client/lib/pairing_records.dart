// OLIVE BRANCH — what each side keeps after an on-device pairing. UNVERIFIED on a device; headless in CI.
// Spec 2026-11-08-adult-gate-and-simple-pairing-design.md sections 3, 7.3, 8.
//
// CHILD device: the adult-signed certificate, the adult device's public key and names ('childpairing'), and
// the unlock verifier ('adultunlock', a salted slow hash of the adult's PIN, held in the same record shape and
// with the same 5-tries/15-minutes lockout as local_pin.dart). The child device never holds a PIN, never lets
// a child create or change one, and shows nothing of this to her.
//
// ADULT device: the list of child devices it certified ('pairedkids'), so "Forget this tablet" can revoke one.
import 'dart:typed_data';

import 'device_keys.dart';
import 'local_pin.dart';
import 'local_store.dart';
import 'pairing_protocol.dart';

abstract class ChildPairingRepository {
  Future<ChildPairing?> load();
  Future<void> save(ChildPairing pairing);
  Future<void> clear();
}

class MemoryChildPairingRepository implements ChildPairingRepository {
  ChildPairing? _p;
  @override
  Future<ChildPairing?> load() async => _p;
  @override
  Future<void> save(ChildPairing pairing) async => _p = pairing;
  @override
  Future<void> clear() async => _p = null;
}

class LocalStoreChildPairingRepository implements ChildPairingRepository {
  LocalStoreChildPairingRepository(this._ns, this._unlock);
  final LocalNamespace _ns;

  /// Where the unlock verifier (and its lockout counters) live.
  final LocalPinRepository _unlock;
  static const String _key = 'pairing';

  @override
  Future<ChildPairing?> load() async {
    final Object? raw = await _ns.get(_key);
    if (raw is! Map) return null;
    final PairingCert? cert = PairingCert.fromJson(raw['cert']);
    final Object? apk = raw['apk'], an = raw['an'], cn = raw['cn'];
    final LocalPinRecord? v = await _unlock.load();
    if (cert == null || apk is! String || an is! String || cn is! String || v == null) return null;
    try {
      final Uint8List key = unb64(apk);
      // Fail closed: a certificate that does not verify under the stored adult key is "not paired".
      if (!await cert.verifiedBy(key)) return null;
      return ChildPairing(cert: cert, adultKey: key, adultName: an, childName: cn, unlockVerifier: v);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(ChildPairing p) async {
    await _unlock.save(p.unlockVerifier);
    await _ns.put(_key, <String, Object?>{
      'cert': p.cert.toJson(), 'apk': b64(p.adultKey), 'an': p.adultName, 'cn': p.childName,
    });
  }

  @override
  Future<void> clear() async {
    await _ns.delete(_key);
    await _unlock.clear();
  }
}

abstract class PairedKidsRepository {
  Future<List<PairedKid>> load();
  Future<void> add(PairedKid kid);
  Future<void> forget(String certId);
}

class MemoryPairedKidsRepository implements PairedKidsRepository {
  final List<PairedKid> _l = <PairedKid>[];
  @override
  Future<List<PairedKid>> load() async => List<PairedKid>.of(_l);
  @override
  Future<void> add(PairedKid kid) async => _l.add(kid);
  @override
  Future<void> forget(String certId) async => _l.removeWhere((PairedKid k) => k.certId == certId);
}

class LocalStorePairedKidsRepository implements PairedKidsRepository {
  LocalStorePairedKidsRepository(this._ns);
  final LocalNamespace _ns;
  static const String _key = 'kids';

  @override
  Future<List<PairedKid>> load() async {
    final Object? raw = await _ns.get(_key);
    if (raw is! List) return <PairedKid>[];
    final List<PairedKid> out = <PairedKid>[];
    for (final Object? e in raw) {
      if (e is! Map) continue;
      try {
        out.add(PairedKid(
            certId: e['certId'] as String, childDeviceKey: unb64(e['cpk'] as String), childId: e['cid'] as String,
            deviceName: e['dn'] as String, issuedAtMs: e['iat'] as int));
      } catch (_) {}
    }
    return out;
  }

  Future<void> _write(List<PairedKid> l) => _ns.put(_key, <Object?>[
        for (final PairedKid k in l)
          <String, Object?>{'certId': k.certId, 'cpk': b64(k.childDeviceKey), 'cid': k.childId, 'dn': k.deviceName, 'iat': k.issuedAtMs},
      ]);

  @override
  Future<void> add(PairedKid kid) async => _write(<PairedKid>[...await load(), kid]);

  @override
  Future<void> forget(String certId) async =>
      _write((await load()).where((PairedKid k) => k.certId != certId).toList());
}
