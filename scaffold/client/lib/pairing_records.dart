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

import 'package:flutter/foundation.dart' show ChangeNotifier;

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
  LocalStoreChildPairingRepository(this._ns, this._unlock, {DateTime Function()? now}) : _now = now ?? DateTime.now;
  final LocalNamespace _ns;
  final DateTime Function() _now;

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
    final bool phoneOnly = raw['po'] == true;
    if (cert == null || apk is! String || an is! String || cn is! String || (v == null && !phoneOnly)) return null;
    try {
      final Uint8List key = unb64(apk);
      // Fail closed: a certificate that does not verify under the stored adult key is "not paired".
      if (!await cert.verifiedBy(key)) return null;
      final Object? fk = raw['fk'];
      Uint8List? familyKey;
      if (fk is String) {
        final Uint8List f = unb64(fk);
        if (f.length == 16) familyKey = f;
      }
      // MIGRATION of a pairing made before certificates expired: it has no signed end date, so the first time this
      // build looks at it the tablet is given a fixed grace (kLegacyCertGrace) to meet the grown-up's phone once,
      // which renews it. The grace is remembered, so it cannot be extended by restarting the app.
      int? grace = raw['lg'] is int ? raw['lg'] as int : null;
      if (cert.expiresAtMs == null && grace == null) {
        grace = _now().add(kLegacyCertGrace).millisecondsSinceEpoch;
        try {
          await _ns.put(_key, <String, Object?>{...raw.cast<String, Object?>(), 'lg': grace});
        } catch (_) {
          // Held for this run only; the next run starts the grace again (a failed write must not strand the tablet).
        }
      }
      final Object? ca = raw['ca'];
      final int? childAge = (ca is int && ca >= 3 && ca <= 17) ? ca : null;
      return ChildPairing(
          cert: cert, adultKey: key, adultName: an, childName: cn, unlockVerifier: v, familyKey: familyKey, graceUntilMs: grace, childAge: childAge);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(ChildPairing p) async {
    if (p.unlockVerifier != null) {
      await _unlock.save(p.unlockVerifier!);
    } else {
      await _unlock.clear();
    }
    await _ns.put(_key, <String, Object?>{
      'cert': p.cert.toJson(), 'apk': b64(p.adultKey), 'an': p.adultName, 'cn': p.childName,
      if (p.childAge != null) 'ca': p.childAge,
      if (p.unlockVerifier == null) 'po': true,
      if (p.familyKey != null) 'fk': b64(p.familyKey!),
      if (p.graceUntilMs != null && p.cert.expiresAtMs == null) 'lg': p.graceUntilMs,
    });
  }

  /// A verified renewal: keep the pairing, swap in the certificate the grown-up's phone re-signed. The caller has
  /// already checked it verifies under the pinned adult key. The legacy grace ends, because the certificate now has
  /// a signed end date of its own.
  Future<void> replaceCert(PairingCert renewed) async {
    final Object? raw = await _ns.get(_key);
    if (raw is! Map) return;
    final Map<String, Object?> next = <String, Object?>{...raw.cast<String, Object?>(), 'cert': renewed.toJson()}..remove('lg');
    await _ns.put(_key, next);
  }

  /// A verified phone-only grant: keep the pairing, delete the PIN verifier. A typed code can never work again.
  Future<void> makePhoneOnly() async {
    final Object? raw = await _ns.get(_key);
    if (raw is! Map) return;
    await _unlock.clear();
    await _ns.put(_key, <String, Object?>{...raw.cast<String, Object?>(), 'po': true});
  }

  @override
  Future<void> clear() async {
    await _ns.delete(_key);
    await _unlock.clear();
  }
}

/// What a read of the grown-up's list of paired tablets found. A list that merely came back short is not the same as
/// an empty one: [skipped] counts entries that were stored but could not be read, and [unreadable] says the store
/// itself could not be read (or held something that is not a list). Callers that would say "no tablet" must check
/// [verifiablyEmpty], never `kids.isEmpty`.
class PairedKidsLoad {
  const PairedKidsLoad(this.kids, {this.skipped = 0, this.unreadable = false});

  /// Every entry that read cleanly.
  final List<PairedKid> kids;

  /// Stored entries that could not be read. They are left exactly as they were on disk.
  final int skipped;

  /// The store could not be read at all, so nothing is known.
  final bool unreadable;

  /// True only when the list was read in full and holds nothing: safe to say "no tablet is connected".
  bool get verifiablyEmpty => !unreadable && skipped == 0 && kids.isEmpty;

  /// Some of what is stored could not be shown (a skipped entry or an unreadable store).
  bool get incomplete => unreadable || skipped > 0;
}

/// Raised when a tablet cannot be recorded because the list could not be read first. Writing over a list that was
/// not read could erase tablets already recorded, so nothing is written.
class PairedKidsUnreadable implements Exception {
  const PairedKidsUnreadable();
  @override
  String toString() => 'PairedKidsUnreadable';
}

/// Bumped after every successful change to a paired-tablet list, so a screen that shows it (the guardian home's one
/// sentence) can read it again without being rebuilt.
final ChangeNotifier kPairedKidsChanged = _PairedKidsChanged();

class _PairedKidsChanged extends ChangeNotifier {
  void bump() => notifyListeners();
}

abstract class PairedKidsRepository {
  Future<List<PairedKid>> load();

  /// Like [load] but says what could not be read. Never throws for a damaged store.
  Future<PairedKidsLoad> loadChecked();
  Future<void> add(PairedKid kid);
  Future<void> forget(String certId);
  Future<void> setPhoneOnly(String certId, bool value);
}

class MemoryPairedKidsRepository implements PairedKidsRepository {
  final List<PairedKid> _l = <PairedKid>[];
  @override
  Future<List<PairedKid>> load() async => List<PairedKid>.of(_l);
  @override
  Future<PairedKidsLoad> loadChecked() async => PairedKidsLoad(List<PairedKid>.of(_l));
  @override
  Future<void> add(PairedKid kid) async {
    _l.add(kid);
    (kPairedKidsChanged as _PairedKidsChanged).bump();
  }

  @override
  Future<void> forget(String certId) async {
    _l.removeWhere((PairedKid k) => k.certId == certId);
    (kPairedKidsChanged as _PairedKidsChanged).bump();
  }

  @override
  Future<void> setPhoneOnly(String certId, bool value) async {
    for (int i = 0; i < _l.length; i++) {
      if (_l[i].certId == certId) _l[i] = _withPhoneOnly(_l[i], value);
    }
    (kPairedKidsChanged as _PairedKidsChanged).bump();
  }
}

PairedKid _withPhoneOnly(PairedKid k, bool v) => PairedKid(
    certId: k.certId, childDeviceKey: k.childDeviceKey, childId: k.childId, deviceName: k.deviceName,
    issuedAtMs: k.issuedAtMs, phoneOnly: v);

class LocalStorePairedKidsRepository implements PairedKidsRepository {
  LocalStorePairedKidsRepository(this._ns);
  final LocalNamespace _ns;
  static const String _key = 'kids';

  PairedKid? _parse(Object? e) {
    if (e is! Map) return null;
    try {
      return PairedKid(
          certId: e['certId'] as String, childDeviceKey: unb64(e['cpk'] as String), childId: e['cid'] as String,
          deviceName: e['dn'] as String, issuedAtMs: e['iat'] as int, phoneOnly: e['po'] == true);
    } catch (_) {
      return null;
    }
  }

  /// The stored list in order: each slot is the parsed tablet, or null with the raw value kept for the entries that
  /// could not be read. Null overall when the store could not be read, or holds something that is not a list.
  Future<List<({PairedKid? kid, Object? raw})>?> _slots() async {
    final Object? raw;
    try {
      raw = await _ns.get(_key);
    } catch (_) {
      return null;
    }
    if (raw == null) return <({PairedKid? kid, Object? raw})>[];
    if (raw is! List) return null;
    return <({PairedKid? kid, Object? raw})>[for (final Object? e in raw) (kid: _parse(e), raw: e)];
  }

  @override
  Future<PairedKidsLoad> loadChecked() async {
    final List<({PairedKid? kid, Object? raw})>? slots = await _slots();
    if (slots == null) return const PairedKidsLoad(<PairedKid>[], unreadable: true);
    return PairedKidsLoad(
      <PairedKid>[for (final s in slots) if (s.kid != null) s.kid!],
      skipped: slots.where((s) => s.kid == null).length,
    );
  }

  @override
  Future<List<PairedKid>> load() async => (await loadChecked()).kids;

  static Object? _json(PairedKid k) =>
      <String, Object?>{'certId': k.certId, 'cpk': b64(k.childDeviceKey), 'cid': k.childId, 'dn': k.deviceName, 'iat': k.issuedAtMs, if (k.phoneOnly) 'po': true};

  /// Applies [change] to the readable tablets and writes the list back. Entries that could not be read are written
  /// back exactly as they were, in place, never dropped: a bad entry is never erased by a change to a good one. When the
  /// list itself cannot be read nothing is written and [PairedKidsUnreadable] is thrown.
  Future<void> _mutate(List<PairedKid> Function(List<PairedKid> current) change, {PairedKid? append}) async {
    final List<({PairedKid? kid, Object? raw})>? slots = await _slots();
    if (slots == null) throw const PairedKidsUnreadable();
    final List<PairedKid> next = change(<PairedKid>[for (final s in slots) if (s.kid != null) s.kid!]);
    final Map<String, PairedKid> byId = <String, PairedKid>{for (final PairedKid k in next) k.certId: k};
    final List<Object?> out = <Object?>[];
    for (final s in slots) {
      if (s.kid == null) {
        out.add(s.raw);
      } else if (byId.containsKey(s.kid!.certId)) {
        out.add(_json(byId[s.kid!.certId]!));
      }
    }
    if (append != null) out.add(_json(append));
    await _ns.put(_key, out);
    (kPairedKidsChanged as _PairedKidsChanged).bump();
  }

  @override
  Future<void> add(PairedKid kid) => _mutate((List<PairedKid> l) => l, append: kid);

  @override
  Future<void> forget(String certId) => _mutate((List<PairedKid> l) => l.where((PairedKid k) => k.certId != certId).toList());

  @override
  Future<void> setPhoneOnly(String certId, bool value) =>
      _mutate((List<PairedKid> l) => <PairedKid>[for (final PairedKid k in l) k.certId == certId ? _withPhoneOnly(k, value) : k]);
}
