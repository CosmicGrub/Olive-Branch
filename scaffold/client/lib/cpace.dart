// OLIVE BRANCH — the password-authenticated key exchange the pairing protocol uses: CPace as specified in
// draft-irtf-cfrg-cpace-21 for the suite CPACE-X25519-SHA512 (generator derived from the password by a hash and
// the Elligator2 map of RFC 9380, one X25519 each way), run in the initiator/responder setting, followed by
// Olive's own explicit key confirmation. Docs: spec 2026-11-08-adult-gate-and-simple-pairing-design.md section 6
// and docs/planning/EXTERNAL-CRYPTO-REVIEW-BRIEF.md. UNVERIFIED on a device; the maths runs headless in CI.
//
// CONFORMANCE. Everything down to [PakeKey.isk] is the draft: DSI "CPace255", the length-prefixed zero pad,
// the generator, the two shares, K, ISK = H(lv_cat(DSI_ISK, sid, K) || transcript_ir) with the shares and the
// associated data, and the abort on a neutral K. The draft's appendix B.1 vectors (B.1.1 to B.1.7 and the
// low-order and non-canonical points of B.1.10) are checked byte for byte by test/cpace_draft21_test.dart against
// test/vectors/cpace_draft21_vectors.json, and the independent Node implementation (tools/pake_cpace.mjs) is
// checked against the same file. In the pairing protocol the CHILD device is the initiator ("A" in the draft)
// and the ADULT device is the responder ("B"). The channel identifier (CI) follows draft section 10.1.1:
// the initiator's identity first, the responder's second, see [pairingChannelId]. ADa and ADb are empty.
//
// NOT THE DRAFT. [PakeKey.tag], [PakeKey.sas], [PakeKey.match] and [PakeKey.channelKey] are Olive's own layer on
// top of ISK (a labelled SHA-512 as KDF, an HMAC-SHA256 confirmation over the shares, the channel identifier
// and the session id). CPace does not define them; they are the part an outside reviewer must still read as
// custom. They are kept apart from the CPace functions below on purpose.
//
// No maintained Dart CPace library exists (pub.dev `spake2plus` is desktop-only FFI to OpenSSL), so this is
// still our own code even though it now matches the draft's vectors. It needs the external cryptographic review
// before real families rely on it (decision D2). Everything above this file talks to the small
// [PakeParty]/[PakeKey] surface so a vetted library can replace it.
//
// CONSTANT TIME (draft section 10.10 asks for it). Not achieved, mitigated:
//   * Dart [BigInt] arithmetic is not constant time. The one place it touches a value derived from the
//     password is [elligator2] (its modular inverse and its square-root test). Those two operations run on
//     BLINDED operands (multiplied by a fresh random non-zero field element, which changes neither the
//     inverse's correctness nor the Legendre symbol), so their timing no longer depends on the password-derived
//     value. The surrounding additions and multiplications and the byte-to-integer conversion are still
//     variable time; a local attacker measuring them on the device is the residual risk (brief Q9).
//   * The hash of the generator string (SHA-512 over the PIN) runs in the `cryptography` package, whose timing
//     behaviour is not reviewed here. The zero padding of the draft fills the first block independent of the PIN length.
//   * X25519 is the `cryptography` package's, pure Dart on every platform (cryptography_flutter is not a
//     dependency, so what the tests run is what ships); we neither inspect nor claim anything about its timing.
//     It does handle the draft's low-order and non-canonical points, see test/cpace_draft21_test.dart.
//
// WHAT IT GIVES. Both sides hold the same low-entropy secret (the adult's PIN, or the one-time QR secret).
// The secret is never sent. A recording of the exchange cannot be used to guess it offline: each guess needs
// one live exchange with the adult's device, which counts it. The session id and a channel identifier
// (family id, key fingerprints, names) are mixed into the generator, so a peer from another session or
// family derives a different key even with the same PIN.
import 'dart:convert' show utf8;
import 'dart:math' show Random;
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'local_pin.dart' show constantTimeEquals;

/// G_X25519.DSI of the draft. (Earlier builds used "OliveCPace255" and an unprefixed zero pad: not compatible.)
const String kPakeDsi = 'CPace255';

/// H.s_in_bytes for SHA-512: the input block size the zero padding fills.
const int kPakeHashBlockBytes = 128;

final BigInt _p = (BigInt.one << 255) - BigInt.from(19);
final BigInt _a = BigInt.from(486662);

BigInt _mod(BigInt x) => ((x % _p) + _p) % _p;

BigInt _leToBig(List<int> b) {
  BigInt r = BigInt.zero;
  for (int i = b.length - 1; i >= 0; i--) {
    r = (r << 8) | BigInt.from(b[i]);
  }
  return r;
}

Uint8List _bigToLe32(BigInt n) {
  final Uint8List o = Uint8List(32);
  for (int i = 0; i < 32; i++) {
    o[i] = (n & BigInt.from(255)).toInt();
    n >>= 8;
  }
  return o;
}

/// prepend_len: the length as LEB128, then the bytes.
Uint8List lv(List<int> b) {
  final List<int> len = <int>[];
  int n = b.length;
  do {
    int byte = n & 0x7f;
    n >>= 7;
    if (n != 0) byte |= 0x80;
    len.add(byte);
  } while (n != 0);
  return Uint8List.fromList(<int>[...len, ...b]);
}

Uint8List cat(Iterable<List<int>> parts) => Uint8List.fromList(<int>[for (final List<int> p in parts) ...p]);

/// lv_cat(a0, a1, ...): every part length-prefixed, then concatenated.
Uint8List lvCat(Iterable<List<int>> parts) => cat(<List<int>>[for (final List<int> p in parts) lv(p)]);

Future<Uint8List> sha512(List<int> data) async => Uint8List.fromList((await Sha512().hash(data)).bytes);

// ------------------------------------------------------------------------------ CPace (draft-21) ----------

/// decodeUCoordinate of RFC 7748 for 255-bit fields: the 32 bytes with bit 255 cleared (still little endian).
Uint8List decodeUCoordinate(List<int> u32) {
  final Uint8List masked = Uint8List.fromList(u32);
  masked[31] &= 0x7f;
  return masked;
}

final Random _blindRandom = Random.secure();

BigInt _blind() {
  while (true) {
    final BigInt r = _mod(_leToBig(<int>[for (int i = 0; i < 32; i++) _blindRandom.nextInt(256)]));
    if (r != BigInt.zero) return r;
  }
}

/// map_to_curve_elligator2 of RFC 9380 for curve25519 (Z = 2), u-coordinate only (the draft discards v):
/// 32 bytes to the u-coordinate of a curve point. The modular inverse and the square test run on blinded
/// operands (see the header); the result is the same as [elligator2Unblinded].
Uint8List elligator2(List<int> u32) => _elligator2(u32, blind: true);

/// The same map without blinding. Only for the test that proves blinding does not change a single output.
Uint8List elligator2Unblinded(List<int> u32) => _elligator2(u32, blind: false);

Uint8List _elligator2(List<int> u32, {required bool blind}) {
  final BigInt u = _mod(_leToBig(decodeUCoordinate(u32)));
  final BigInt den = _mod(BigInt.one + BigInt.two * u * u);
  final BigInt w;
  if (den == BigInt.zero) {
    // 1 + 2u^2 = 0 has no solution (-1/2 is a non-residue mod p), so this branch is unreachable; RFC 9380 still defines it.
    w = _mod(-_a);
  } else if (blind) {
    final BigInt r = _blind();
    w = _mod(-_a * r * (_mod(den * r)).modInverse(_p)); // r * (den * r)^-1 = den^-1
  } else {
    w = _mod(-_a * den.modInverse(_p));
  }
  final BigInt v = _mod(w * w * w + _a * w * w + w);
  final bool square;
  if (v == BigInt.zero) {
    square = true;
  } else if (blind) {
    final BigInt s = _blind(); // (v s^2) is a square iff v is, and its magnitude is random
    square = _mod(v * s * s).modPow((_p - BigInt.one) >> 1, _p) == BigInt.one;
  } else {
    square = v.modPow((_p - BigInt.one) >> 1, _p) == BigInt.one;
  }
  return _bigToLe32(square ? w : _mod(-_a - w));
}

/// generator_string(DSI, PRS, CI, sid, s_in_bytes) = lv_cat(DSI, PRS, zero_bytes(len_zpad), CI, sid) with
/// len_zpad = MAX(0, s_in_bytes - len(prepend_len(PRS)) - len(prepend_len(DSI)) - 1).
Uint8List cpaceGeneratorString(List<int> prs, List<int> sid, List<int> ci) {
  final int zpad = (kPakeHashBlockBytes - lv(prs).length - lv(kPakeDsi.codeUnits).length - 1).clamp(0, 1 << 20);
  return lvCat(<List<int>>[kPakeDsi.codeUnits, prs, Uint8List(zpad), ci, sid]);
}

/// H.hash(generator_string, field_size_bytes): the first 32 bytes of SHA-512 of the generator string.
Future<Uint8List> cpaceGeneratorHash(List<int> prs, List<int> sid, List<int> ci) async =>
    (await sha512(cpaceGeneratorString(prs, sid, ci))).sublist(0, 32);

/// G.calculate_generator(H, PRS, CI, sid).
Future<Uint8List> cpaceGenerator(List<int> prs, List<int> sid, List<int> ci) async =>
    elligator2(await cpaceGeneratorHash(prs, sid, ci));

class PakeException implements Exception {
  const PakeException(this.message);
  final String message;
  @override
  String toString() => 'PakeException($message)';
}

/// G_X25519.scalar_mult_vfy: X25519(scalar, u). Returns 32 zero bytes (G.I, the neutral element) when the result is
/// neutral; a library that throws instead of returning zeros for a low-order input is mapped to that too.
Future<Uint8List> cpaceScalarMultVfy(List<int> scalar32, List<int> u32) async {
  final X25519 algo = X25519();
  final SimpleKeyPair kp = await algo.newKeyPairFromSeed(scalar32);
  try {
    final SecretKey k = await algo.sharedSecretKey(
        keyPair: kp, remotePublicKey: SimplePublicKey(u32, type: KeyPairType.x25519));
    return Uint8List.fromList(await k.extractBytes());
  } on ArgumentError {
    return Uint8List(32);
  } on StateError {
    return Uint8List(32);
  }
}

bool _isNeutral(List<int> b) => b.every((int v) => v == 0);

/// The protocol's X25519: the draft's "MUST abort if K = G.I" as an exception.
Future<Uint8List> _x25519(List<int> seed32, List<int> u32) async {
  if (u32.length != 32) throw const PakeException('bad share');
  final Uint8List out = await cpaceScalarMultVfy(seed32, u32);
  if (_isNeutral(out)) throw const PakeException('low order point');
  return out;
}

/// transcript_ir(Ya, ADa, Yb, ADb) = lv_cat(Ya, ADa) || lv_cat(Yb, ADb): the initiator's share first.
Uint8List cpaceTranscriptIr(List<int> ya, List<int> ada, List<int> yb, List<int> adb) =>
    lvCat(<List<int>>[ya, ada, yb, adb]);

/// o_cat: the lexicographically larger string first, prefixed with b"oc".
Uint8List cpaceOCat(List<int> a, List<int> b) {
  int c = 0;
  for (int i = 0; i < a.length && i < b.length && c == 0; i++) {
    c = a[i].compareTo(b[i]);
  }
  if (c == 0) c = a.length.compareTo(b.length);
  return cat(<List<int>>[<int>[0x6f, 0x63], c >= 0 ? a : b, c >= 0 ? b : a]);
}

/// transcript_oc(Ya, ADa, Yb, ADb): the symmetric (no initiator) mode. Olive's pairing does not use it; it is here so
/// the whole of appendix B.1 is covered by tests.
Uint8List cpaceTranscriptOc(List<int> ya, List<int> ada, List<int> yb, List<int> adb) =>
    cpaceOCat(lvCat(<List<int>>[ya, ada]), lvCat(<List<int>>[yb, adb]));

/// ISK = H.hash(lv_cat(DSI || b"_ISK", sid, K) || transcript).
Future<Uint8List> cpaceIskFromTranscript(List<int> sid, List<int> k, List<int> transcript) =>
    sha512(cat(<List<int>>[lvCat(<List<int>>['${kPakeDsi}_ISK'.codeUnits, sid, k]), transcript]));

/// The optional session id output of the draft: H.hash(b"CPaceSidOutput" + transcript).
Future<Uint8List> cpaceSidOutput(List<int> transcript) => sha512(cat(<List<int>>['CPaceSidOutput'.codeUnits, transcript]));

/// The channel identifier the pairing protocol passes as CI (draft 10.1.1: the initiator's identity first, the
/// responder's second, each length-prefixed). The initiator is the child device (its public key); the responder
/// is the adult device (key fingerprint, family id, display name). The session id is not in here: it is its own
/// CPace input. Shared by both sides and the tests so the layout exists once.
Uint8List pairingChannelId({
  required List<int> childPublicKey,
  required List<int> adultFingerprint,
  required String familyId,
  required String adultName,
}) =>
    lvCat(<List<int>>[
      childPublicKey,
      lvCat(<List<int>>[adultFingerprint, utf8.encode(familyId), utf8.encode(adultName)]),
    ]);

// ----------------------------------------------------------------------- Olive layer (not CPace) ----------

Future<Uint8List> _kdf(List<int> key, String label) async =>
    (await sha512(cat(<List<int>>[lv(label.codeUnits), lv(key)]))).sublist(0, 32);

/// What the confirmation tags are computed over: the shares, the channel identifier and the session id.
Uint8List pakeTranscript(List<int> yc, List<int> ya, List<int> ci, List<int> sid) =>
    cat(<List<int>>[lv(yc), lv(ya), lv(ci), lv(sid)]);

/// The result of a finished exchange: the shared secret and what is derived from it.
class PakeKey {
  PakeKey._(this.isk, this._transcript);

  /// CPace's ISK (draft-21, 64 bytes).
  final Uint8List isk;
  final Uint8List _transcript;

  /// The confirmation tag for [role] ('C' = child device, 'A' = adult device).
  Future<Uint8List> tag(String role) async {
    final Mac m = await Hmac.sha256().calculateMac(
        cat(<List<int>>[lv(role.codeUnits), _transcript]),
        secretKey: SecretKey(await _kdf(isk, 'confirm')));
    return Uint8List.fromList(m.bytes);
  }

  /// Checks the PEER's tag in constant time.
  Future<bool> checkTag(String peerRole, List<int> theirs) async =>
      constantTimeEquals(await tag(peerRole), theirs);

  /// Two bytes both screens turn into the confirmation word and picture.
  Future<Uint8List> sas() async => (await _kdf(isk, 'sas')).sublist(0, 2);

  /// Three bytes for the "Match" step of the pairing picture (three pictures and a colour, about 21 bits). A new
  /// KDF label only: the transcript and the messages are unchanged. Still inside the D2 external-review scope.
  Future<Uint8List> match() async => (await _kdf(isk, 'match')).sublist(0, 3);

  /// A 32 byte key for sealing the credential message.
  Future<Uint8List> channelKey() => _kdf(isk, 'channel');
}

/// One side of an exchange. The child device is [isChild] true, which makes it the CPace initiator.
class PakeParty {
  PakeParty._(this.isChild, this._seed, this._sid, this._ci, this._adInitiator, this._adResponder, this.share);
  final bool isChild;
  final Uint8List _seed;
  final Uint8List _sid, _ci, _adInitiator, _adResponder;

  /// The public share to send to the peer.
  final Uint8List share;

  /// [seed] is for golden vectors only; a real run leaves it null (32 CSPRNG bytes). [adInitiator] and
  /// [adResponder] are the draft's ADa and ADb (empty in the pairing protocol); both sides must use the same pair.
  static Future<PakeParty> start({
    required bool isChild,
    required List<int> password,
    required List<int> sid,
    required List<int> ci,
    List<int>? seed,
    List<int> adInitiator = const <int>[],
    List<int> adResponder = const <int>[],
  }) async {
    final List<int> s =
        seed ?? await X25519().newKeyPair().then((SimpleKeyPair k) => k.extractPrivateKeyBytes());
    final Uint8List g = await cpaceGenerator(password, sid, ci);
    final Uint8List y = await _x25519(s, g);
    return PakeParty._(isChild, Uint8List.fromList(s), Uint8List.fromList(sid), Uint8List.fromList(ci),
        Uint8List.fromList(adInitiator), Uint8List.fromList(adResponder), y);
  }

  /// Finishes with the peer's share. Throws [PakeException] for a malformed or low-order share (the draft's abort).
  Future<PakeKey> finish(List<int> peerShare) async {
    if (peerShare.length != 32) throw const PakeException('bad share');
    final Uint8List k = await _x25519(_seed, peerShare);
    final Uint8List yc = isChild ? share : Uint8List.fromList(peerShare);
    final Uint8List ya = isChild ? Uint8List.fromList(peerShare) : share;
    final Uint8List isk = await cpaceIskFromTranscript(_sid, k, cpaceTranscriptIr(yc, _adInitiator, ya, _adResponder));
    return PakeKey._(isk, pakeTranscript(yc, ya, _ci, _sid));
  }
}
