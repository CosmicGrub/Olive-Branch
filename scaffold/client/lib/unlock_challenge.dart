// OLIVE BRANCH — "use my phone to unlock": a fresh signed challenge-response between a paired child device and
// the grown-up's phone. UNVERIFIED on a device; the protocol runs headless in CI. Spec
// 2026-11-08-adult-gate-and-simple-pairing-design.md section 7.2.
//
// WHY NOT A STATIC QR. A picture the grown-up's phone shows for ever could be photographed once and held up to
// the tablet any time. Here the TABLET shows a one-time challenge (a random nonce, its own key fingerprint, the
// purpose, a 2 minute expiry); the grown-up's phone checks it names a tablet THIS phone paired, asks for the
// grown-up's PIN, and signs exactly those fields with the device key; the tablet checks the signature against
// the grown-up key it pinned at pairing, that the nonce is the single outstanding one, that it has not expired,
// and consumes it. A recording of either picture is useless afterwards. Neither picture contains a PIN.
//
// PHONE-ONLY. A grown-up may choose that a tablet never accepts a typed code. Since the pairing hardening this is the
// DEFAULT: a newly paired tablet is never given a PIN verifier at all. For a tablet paired earlier, the signed grant
// carries the flag and the tablet deletes its verifier. Turning it off again needs the tablet to be connected afresh.
//
// THIS MEETING IS ALSO THE ONE PLACE THE TABLET AND THE PHONE TOUCH, SO IT DOES THREE MORE THINGS (all server-less,
// all signed, none shown to a child):
//  - PROOF. The tablet signs its challenge with its own device key (a "proof" the phone checks against the key it
//    pinned for that tablet). The phone then calls TrustBook.observe: the same key refreshes "last contact" (which is
//    what the 60-day "still yours?" prompt measures), a different key pauses the connection and the phone refuses to
//    unlock it. A tablet from before this build sends no proof and is answered as before, without observe.
//  - RENEWAL. A pairing certificate has a signed end date. When it is within 90 days of the end (or has none), the grant
//    carries the same certificate re-signed with a new end date and the tablet keeps it.
//  - REVOCATION. If this phone stopped or forgot the tablet, the answer is a signed "you are disconnected" notice
//    instead of an unlock; the tablet then drops its pairing and no longer honours it. A tablet that never meets this
//    phone again is never told: there is no server and no push (offline-first).
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'cpace.dart' show cat, lv;
import 'device_keys.dart';
import 'local_pin.dart' show constantTimeEquals;
import 'pairing_protocol.dart' show PairedKid;
import 'pairing_trust.dart' show TrustBook, TrustStatus;

/// What a successful grown-up proof looks like to the adult gate: no keypad digit string can equal it.
const String kPhoneProof = '\u0000phone';

const Duration kChallengeTtl = Duration(minutes: 2);

enum UnlockPurpose { unlock, forget }

extension on UnlockPurpose {
  String get wire => name;
}

UnlockPurpose? _purpose(String? s) {
  for (final UnlockPurpose p in UnlockPurpose.values) {
    if (p.wire == s) return p;
  }
  return null;
}

Uint8List _signed(List<int> nonce, List<int> childFp, UnlockPurpose p, int expMs, bool phoneOnly) => cat(<List<int>>[
      lv(utf8.encode('olive-unlock-v1')), lv(nonce), lv(childFp), lv(utf8.encode(p.wire)),
      lv(utf8.encode('$expMs')), lv(<int>[phoneOnly ? 1 : 0]),
    ]);

/// What the tablet signs to show the phone it holds the key it claims (bound to this challenge, so it cannot be
/// replayed into another one).
Uint8List _proofBytes(List<int> nonce, List<int> childFp, UnlockPurpose p, int expMs, List<int> childKey, String certId, int? certExp) =>
    cat(<List<int>>[
      lv(utf8.encode('olive-unlock-proof-v1')), lv(nonce), lv(childFp), lv(utf8.encode(p.wire)), lv(utf8.encode('$expMs')),
      lv(childKey), lv(utf8.encode(certId)), lv(utf8.encode(certExp == null ? '-' : '$certExp')),
    ]);

/// What the phone signs to tell a tablet it is disconnected (bound to the tablet's one outstanding challenge).
Uint8List _revokeBytes(List<int> nonce, List<int> childFp) =>
    cat(<List<int>>[lv(utf8.encode('olive-unlock-revoke-v1')), lv(nonce), lv(childFp)]);

class UnlockChallenge {
  const UnlockChallenge({
    required this.nonce,
    required this.childFingerprint,
    required this.purpose,
    required this.expiresMs,
    this.childKey,
    this.certId,
    this.certExpiresMs,
    this.proof,
  });
  final Uint8List nonce, childFingerprint;
  final UnlockPurpose purpose;
  final int expiresMs;

  /// The tablet's public key, its certificate id, the certificate's end date (null = none) and the tablet's signature
  /// over all of it. All null on a challenge from a tablet that predates the proof.
  final Uint8List? childKey, proof;
  final String? certId;
  final int? certExpiresMs;

  bool get hasProof => childKey != null && certId != null && proof != null;

  /// True only when the proof is a valid signature by [childKey] over exactly this challenge, and [childKey] is the
  /// key whose fingerprint the challenge names.
  Future<bool> proofValid() async {
    if (!hasProof) return false;
    if (!constantTimeEquals(await fingerprintOf(childKey!), childFingerprint)) return false;
    return DeviceKey.verify(childKey!, _proofBytes(nonce, childFingerprint, purpose, expiresMs, childKey!, certId!, certExpiresMs), proof!);
  }

  UnlockChallenge withProof({required Uint8List childKey, required String certId, int? certExpiresMs, required Uint8List proof}) =>
      UnlockChallenge(
          nonce: nonce, childFingerprint: childFingerprint, purpose: purpose, expiresMs: expiresMs,
          childKey: childKey, certId: certId, certExpiresMs: certExpiresMs, proof: proof);

  String toQr() => Uri(scheme: 'olive', host: 'unlock', path: '/1', queryParameters: <String, String>{
        'n': b64(nonce), 'c': b64(childFingerprint), 'p': purpose.wire, 'e': '$expiresMs',
        if (hasProof) ...<String, String>{
          'k': b64(childKey!), 'i': certId!, if (certExpiresMs != null) 'x': '$certExpiresMs', 'cs': b64(proof!),
        },
      }).toString();

  static UnlockChallenge? parse(String raw) {
    try {
      final Uri u = Uri.parse(raw.trim());
      if (u.scheme != 'olive' || u.host != 'unlock' || u.path != '/1') return null;
      final UnlockPurpose? p = _purpose(u.queryParameters['p']);
      final int? e = int.tryParse(u.queryParameters['e'] ?? '');
      final Uint8List n = unb64(u.queryParameters['n'] ?? ''), c = unb64(u.queryParameters['c'] ?? '');
      if (p == null || e == null || n.length != 16 || c.length != 16) return null;
      final Map<String, String> q = u.queryParameters;
      // A proof is all of key, certificate id and signature, or none: a half-proof is a damaged picture.
      final int proofParts = <String>['k', 'i', 'cs'].where(q.containsKey).length;
      if (proofParts == 0) return UnlockChallenge(nonce: n, childFingerprint: c, purpose: p, expiresMs: e);
      if (proofParts != 3) return null;
      final Uint8List k = unb64(q['k']!), s = unb64(q['cs']!);
      final String id = q['i']!;
      final int? x = q.containsKey('x') ? int.tryParse(q['x']!) : null;
      if (k.length != 32 || s.length != 64 || id.isEmpty || id.length > 64 || (q.containsKey('x') && x == null)) return null;
      return UnlockChallenge(
          nonce: n, childFingerprint: c, purpose: p, expiresMs: e, childKey: k, certId: id, certExpiresMs: x, proof: s);
    } catch (_) {
      return null;
    }
  }
}

/// The child device's side. [onPhoneOnly] and [onForget] are how a verified grant changes the tablet; [onRenewed]
/// keeps a renewed certificate; [onRevoked] is called when the phone proved this tablet was disconnected (the caller
/// drops the pairing). [cert] is the pairing certificate this tablet holds (null = none, so no proof is sent).
class ChildUnlockHost {
  ChildUnlockHost({
    required this.childKey,
    required this.adultKey,
    this.cert,
    this.onPhoneOnly,
    this.onForget,
    this.onRenewed,
    this.onRevoked,
    DateTime Function()? now,
    Random? random,
    this.ttl = kChallengeTtl,
  })  : _now = now ?? DateTime.now,
        _random = random ?? Random.secure(),
        _cert = cert;

  final DeviceKey childKey;
  final Uint8List adultKey;
  final PairingCert? cert;
  PairingCert? _cert;
  final Future<void> Function()? onPhoneOnly;
  final Future<void> Function()? onForget;
  final Future<void> Function(PairingCert renewed)? onRenewed;
  final Future<void> Function()? onRevoked;
  final DateTime Function() _now;
  final Random _random;
  final Duration ttl;
  UnlockChallenge? _outstanding;

  /// Issues the one outstanding challenge (a newer one replaces an older one).
  UnlockChallenge issue(UnlockPurpose purpose) {
    final UnlockChallenge c = UnlockChallenge(
      nonce: Uint8List.fromList(List<int>.generate(16, (_) => _random.nextInt(256))),
      childFingerprint: childKey.fingerprint,
      purpose: purpose,
      expiresMs: _now().add(ttl).millisecondsSinceEpoch,
    );
    _outstanding = c;
    return c;
  }

  /// Signs the outstanding challenge with this tablet's key and returns it with the proof attached (same nonce, so the
  /// grant for it still matches). Returns the plain challenge when this tablet holds no certificate, and null when
  /// nothing is outstanding. The caller shows the returned one.
  Future<UnlockChallenge?> proveOutstanding() async {
    final UnlockChallenge? o = _outstanding;
    final PairingCert? c = _cert;
    if (o == null) return null;
    if (c == null) return o;
    final Uint8List sig =
        await childKey.sign(_proofBytes(o.nonce, o.childFingerprint, o.purpose, o.expiresMs, childKey.publicKey, c.certId, c.expiresAtMs));
    final UnlockChallenge proved =
        o.withProof(childKey: childKey.publicKey, certId: c.certId, certExpiresMs: c.expiresAtMs, proof: sig);
    if (!identical(_outstanding, o)) return _outstanding; // a newer challenge replaced it while signing
    _outstanding = proved;
    return proved;
  }

  /// Checks a scanned grant. True only for a fresh, correctly signed answer to the outstanding challenge. The
  /// challenge is consumed as soon as a grant NAMING it arrives, whether or not it verifies. A signed "disconnected"
  /// notice is never an unlock: it calls [onRevoked] and returns false.
  Future<bool> accept(String raw) async {
    final UnlockChallenge? o = _outstanding;
    if (o == null) return false;
    try {
      final Uri u = Uri.parse(raw.trim());
      if (u.scheme != 'olive' || u.host != 'grant' || u.path != '/1') return false;
      final Uint8List n = unb64(u.queryParameters['n'] ?? '');
      if (!constantTimeEquals(n, o.nonce)) return false;
      _outstanding = null;
      if (!_now().isBefore(DateTime.fromMillisecondsSinceEpoch(o.expiresMs))) return false;
      if (u.queryParameters['rv'] == '1') {
        final Uint8List xs = unb64(u.queryParameters['xs'] ?? '');
        if (await DeviceKey.verify(adultKey, _revokeBytes(o.nonce, o.childFingerprint), xs)) await onRevoked?.call();
        return false;
      }
      final bool po = u.queryParameters['po'] == '1';
      final Uint8List sig = unb64(u.queryParameters['s'] ?? '');
      if (!await DeviceKey.verify(adultKey, _signed(o.nonce, o.childFingerprint, o.purpose, o.expiresMs, po), sig)) {
        return false;
      }
      if (po) await onPhoneOnly?.call();
      if (o.purpose == UnlockPurpose.forget) await onForget?.call();
      await _maybeRenew(u.queryParameters);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// A renewal rides only on a grant that already verified. It is kept only when the re-signed certificate verifies
  /// under the adult key this tablet pinned AND moves the end date forward (a replay of an older one changes nothing).
  Future<void> _maybeRenew(Map<String, String> q) async {
    final PairingCert? c = _cert;
    final String? xs = q['x'], cs = q['cs'];
    if (c == null || xs == null || cs == null) return;
    final int? x = int.tryParse(xs);
    if (x == null) return;
    final int? have = c.expiresAtMs;
    if (have != null && x <= have) return;
    final PairingCert next = c.withRenewal(x, unb64(cs));
    if (!await next.verifiedBy(adultKey)) return;
    _cert = next;
    await onRenewed?.call(next);
  }
}

/// What the phone decided about a scanned challenge.
enum UnlockVerdict {
  /// A tablet this phone connected: the grown-up may unlock it (and it may be renewed).
  ok,

  /// A tablet this phone stopped or forgot: the only answer is the signed "you are disconnected" notice.
  revoked,

  /// The tablet proved a DIFFERENT key from the one pinned for that certificate: nothing is granted.
  paused,
}

/// What the grown-up's phone understood of a scanned challenge. [kid] is null for [UnlockVerdict.revoked] (the phone
/// has already forgotten it). [renewToMs] is the new certificate end date to hand over, if one is due.
class ChallengeView {
  const ChallengeView(this.challenge, this.kid, {this.verdict = UnlockVerdict.ok, this.renewToMs, this.pausedName});
  final UnlockChallenge challenge;
  final PairedKid? kid;
  final UnlockVerdict verdict;
  final int? renewToMs;

  /// For [UnlockVerdict.paused]: the name the grown-up gave the connection that now looks different.
  final String? pausedName;
}

/// The grown-up's phone. The caller asks for the PIN BEFORE [grant]. With a [trust] book, every meeting with a tablet
/// that proves its key refreshes its last-contact time (or pauses it if the key changed), and a stopped or forgotten
/// tablet is told so. With a [familyId] (the same one the certificates were issued under) it renews certificates.
class UnlockResponder {
  UnlockResponder({required this.adultKey, required this.kids, DateTime Function()? now, this.trust, this.familyId, this.onDisconnected})
      : _now = now ?? DateTime.now;
  final DeviceKey adultKey;
  final Future<List<PairedKid>> Function() kids;
  final DateTime Function() _now;
  final TrustBook? trust;
  final String? familyId;

  /// Called after the grown-up approved "Disconnect this tablet" (a tablet that asked to be disconnected showed its picture and
  /// this phone signed the answer): the phone ends ITS side at once, so its list does not keep a tablet that has left. Null = nothing.
  final Future<void> Function(PairedKid kid)? onDisconnected;

  /// Null unless the challenge is well formed, unexpired and names a tablet THIS phone paired (or one it must tell it
  /// is disconnected). Meeting a tablet that proves its key is what keeps the watch rules alive.
  Future<ChallengeView?> inspect(String raw) async {
    final UnlockChallenge? c = UnlockChallenge.parse(raw);
    if (c == null || !_now().isBefore(DateTime.fromMillisecondsSinceEpoch(c.expiresMs))) return null;
    final bool proved = await c.proofValid();
    // A proof that does not verify is not "no proof": it is a forgery or damage, and it gets nothing.
    if (c.hasProof && !proved) return null;
    final TrustBook? t = trust;
    if (t != null) {
      for (final Uint8List k in await t.revokedKeyList()) {
        final bool same = proved ? constantTimeEquals(k, c.childKey!) : constantTimeEquals(await fingerprintOf(k), c.childFingerprint);
        if (same) return ChallengeView(c, null, verdict: UnlockVerdict.revoked);
      }
    }
    final List<PairedKid> all = await kids();
    PairedKid? kid;
    if (proved) {
      for (final PairedKid k in all) {
        if (k.certId == c.certId) kid = k;
      }
    }
    if (kid == null) {
      for (final PairedKid k in all) {
        if (constantTimeEquals(await fingerprintOf(k.childDeviceKey), c.childFingerprint)) kid = k;
      }
    }
    if (kid == null) return null;
    int? renewTo;
    if (proved) {
      // The tablet proved this key for this certificate id. The same key refreshes contact. A DIFFERENT key under this
      // id is refused for this scan only and writes nothing: the certificate id is printed in the clear on the real
      // tablet's own picture, so anyone can make a self-signed picture with a stranger's key and that id, and a scan
      // must not be able to pause the real tablet. (A pause already in the book still refuses, below.)
      final bool sameKey = constantTimeEquals(kid.childDeviceKey, c.childKey!);
      if (!sameKey) return ChallengeView(c, kid, verdict: UnlockVerdict.paused, pausedName: kid.deviceName);
      final TrustStatus? st = t == null ? null : await t.observe(kid.certId, c.childKey!);
      if (st == TrustStatus.paused) {
        return ChallengeView(c, kid, verdict: UnlockVerdict.paused, pausedName: kid.deviceName);
      }
    }
    if (proved && familyId != null) {
      final int now = _now().millisecondsSinceEpoch;
      final int? ends = c.certExpiresMs;
      if (ends == null || ends - now < kCertRenewWithin.inMilliseconds) renewTo = now + kCertLifetime.inMilliseconds;
    }
    return ChallengeView(c, kid, renewToMs: renewTo);
  }

  Future<String> grant(ChallengeView v) async {
    final UnlockChallenge c = v.challenge;
    if (v.verdict == UnlockVerdict.paused) throw StateError('a paused connection is never granted');
    if (v.verdict == UnlockVerdict.revoked) {
      final Uint8List xs = await adultKey.sign(_revokeBytes(c.nonce, c.childFingerprint));
      return Uri(scheme: 'olive', host: 'grant', path: '/1', queryParameters: <String, String>{
        'n': b64(c.nonce), 'rv': '1', 'xs': b64(xs),
      }).toString();
    }
    final PairedKid kid = v.kid!;
    if (c.purpose == UnlockPurpose.forget) await onDisconnected?.call(kid);
    final bool po = kid.phoneOnly;
    final Uint8List sig = await adultKey.sign(_signed(c.nonce, c.childFingerprint, c.purpose, c.expiresMs, po));
    String? x, cs;
    final int? renewTo = v.renewToMs;
    if (renewTo != null && familyId != null && c.purpose == UnlockPurpose.unlock) {
      final PairingCert renewed = await PairingCert.issue(adultKey,
          childDeviceKey: kid.childDeviceKey, familyId: familyId!, childId: kid.childId, certId: kid.certId,
          issuedAtMs: kid.issuedAtMs, expiresAtMs: renewTo);
      x = '$renewTo';
      cs = b64(renewed.signature);
    }
    return Uri(scheme: 'olive', host: 'grant', path: '/1', queryParameters: <String, String>{
      'n': b64(c.nonce), 's': b64(sig), if (po) 'po': '1', 'x': ?x, 'cs': ?cs,
    }).toString();
  }
}
