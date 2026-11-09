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
// PHONE-ONLY. A grown-up may choose that a tablet never accepts a typed code. Chosen at pairing, the tablet is
// never given a PIN verifier at all; chosen later, the signed grant carries the flag and the tablet deletes its
// verifier. Turning it off again needs the tablet to be connected afresh (the verifier needs the PIN).
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'cpace.dart' show cat, lv;
import 'device_keys.dart';
import 'local_pin.dart' show constantTimeEquals;
import 'pairing_protocol.dart' show PairedKid;

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

class UnlockChallenge {
  const UnlockChallenge({required this.nonce, required this.childFingerprint, required this.purpose, required this.expiresMs});
  final Uint8List nonce, childFingerprint;
  final UnlockPurpose purpose;
  final int expiresMs;

  String toQr() => Uri(scheme: 'olive', host: 'unlock', path: '/1', queryParameters: <String, String>{
        'n': b64(nonce), 'c': b64(childFingerprint), 'p': purpose.wire, 'e': '$expiresMs',
      }).toString();

  static UnlockChallenge? parse(String raw) {
    try {
      final Uri u = Uri.parse(raw.trim());
      if (u.scheme != 'olive' || u.host != 'unlock' || u.path != '/1') return null;
      final UnlockPurpose? p = _purpose(u.queryParameters['p']);
      final int? e = int.tryParse(u.queryParameters['e'] ?? '');
      final Uint8List n = unb64(u.queryParameters['n'] ?? ''), c = unb64(u.queryParameters['c'] ?? '');
      if (p == null || e == null || n.length != 16 || c.length != 16) return null;
      return UnlockChallenge(nonce: n, childFingerprint: c, purpose: p, expiresMs: e);
    } catch (_) {
      return null;
    }
  }
}

/// The child device's side. [onPhoneOnly] and [onForget] are how a verified grant changes the tablet.
class ChildUnlockHost {
  ChildUnlockHost({
    required this.childKey,
    required this.adultKey,
    this.onPhoneOnly,
    this.onForget,
    DateTime Function()? now,
    Random? random,
    this.ttl = kChallengeTtl,
  })  : _now = now ?? DateTime.now,
        _random = random ?? Random.secure();

  final DeviceKey childKey;
  final Uint8List adultKey;
  final Future<void> Function()? onPhoneOnly;
  final Future<void> Function()? onForget;
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

  /// Checks a scanned grant. True only for a fresh, correctly signed answer to the outstanding challenge. The
  /// challenge is consumed as soon as a grant NAMING it arrives, whether or not it verifies.
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
      final bool po = u.queryParameters['po'] == '1';
      final Uint8List sig = unb64(u.queryParameters['s'] ?? '');
      if (!await DeviceKey.verify(adultKey, _signed(o.nonce, o.childFingerprint, o.purpose, o.expiresMs, po), sig)) {
        return false;
      }
      if (po) await onPhoneOnly?.call();
      if (o.purpose == UnlockPurpose.forget) await onForget?.call();
      return true;
    } catch (_) {
      return false;
    }
  }
}

/// What the grown-up's phone understood of a scanned challenge.
class ChallengeView {
  const ChallengeView(this.challenge, this.kid);
  final UnlockChallenge challenge;
  final PairedKid kid;
}

/// The grown-up's phone. The caller asks for the PIN BEFORE [grant].
class UnlockResponder {
  UnlockResponder({required this.adultKey, required this.kids, DateTime Function()? now})
      : _now = now ?? DateTime.now;
  final DeviceKey adultKey;
  final Future<List<PairedKid>> Function() kids;
  final DateTime Function() _now;

  /// Null unless the challenge is well formed, unexpired and names a tablet THIS phone paired and has not forgotten.
  Future<ChallengeView?> inspect(String raw) async {
    final UnlockChallenge? c = UnlockChallenge.parse(raw);
    if (c == null || !_now().isBefore(DateTime.fromMillisecondsSinceEpoch(c.expiresMs))) return null;
    for (final PairedKid k in await kids()) {
      if (constantTimeEquals(await fingerprintOf(k.childDeviceKey), c.childFingerprint)) return ChallengeView(c, k);
    }
    return null;
  }

  Future<String> grant(ChallengeView v) async {
    final UnlockChallenge c = v.challenge;
    final bool po = v.kid.phoneOnly;
    final Uint8List sig = await adultKey.sign(_signed(c.nonce, c.childFingerprint, c.purpose, c.expiresMs, po));
    return Uri(scheme: 'olive', host: 'grant', path: '/1', queryParameters: <String, String>{
      'n': b64(c.nonce), 's': b64(sig), if (po) 'po': '1',
    }).toString();
  }
}
