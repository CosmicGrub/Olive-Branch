// OLIVE BRANCH — the password-authenticated key exchange the pairing protocol uses: a CPace-style
// balanced PAKE over X25519 (generator derived from the password by a hash and the Elligator2 map, one
// Diffie-Hellman each way, then explicit key confirmation). Docs: spec 2026-11-08-adult-gate-and-simple-
// pairing-design.md section 6. UNVERIFIED on a device; the maths runs headless in CI.
//
// HONEST STATUS. This is CUSTOM cryptographic code (the Elligator2 map and the transcript layout). It
// follows the STRUCTURE of draft-irtf-cfrg-cpace (CPace255 with SHA-512) but is NOT byte-compatible with
// the draft and has NOT been checked against the draft's official vectors: no maintained Dart PAKE library
// exists (pub.dev `spake2plus` is desktop-only FFI to OpenSSL). Its cross-check is the independent Node
// implementation tools/pake_cpace.mjs: both must give identical bytes on test/vectors/pake_vectors.json.
// It needs an external cryptographic review before real families rely on it (decision D2). Everything
// above this file talks to the small [PakeParty]/[PakeKey] surface so a vetted library can replace it.
//
// WHAT IT GIVES. Both sides hold the same low-entropy secret (the adult's PIN, or the one-time QR secret).
// The secret is never sent. A recording of the exchange cannot be used to guess it offline: each guess needs
// one live exchange with the adult's device, which counts it. The session id and a channel identifier
// (family id, key fingerprints, names) are mixed into the generator, so a peer from another session or
// family derives a different key even with the same PIN.
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'local_pin.dart' show constantTimeEquals;

const String kPakeDsi = 'OliveCPace255';

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

/// Length-prefixed (LEB128) bytes.
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

Future<Uint8List> sha512(List<int> data) async => Uint8List.fromList((await Sha512().hash(data)).bytes);

/// The Elligator2 map for Curve25519: 32 bytes to the u-coordinate of a curve point.
Uint8List elligator2(List<int> u32) {
  final Uint8List masked = Uint8List.fromList(u32);
  masked[31] &= 0x7f;
  final BigInt u = _mod(_leToBig(masked));
  final BigInt den = _mod(BigInt.one + BigInt.two * u * u);
  final BigInt w = den == BigInt.zero ? _mod(-_a) : _mod(-_a * den.modInverse(_p));
  final BigInt v = _mod(w * w * w + _a * w * w + w);
  final bool square = v == BigInt.zero || v.modPow((_p - BigInt.one) >> 1, _p) == BigInt.one;
  return _bigToLe32(square ? w : _mod(-_a - w));
}

Future<Uint8List> cpaceGenerator(List<int> prs, List<int> sid, List<int> ci) async {
  final Uint8List dsi = lv(kPakeDsi.codeUnits), p = lv(prs);
  final int zpad = (128 - 1 - p.length - dsi.length).clamp(0, 1 << 20);
  final Uint8List gs = cat(<List<int>>[dsi, p, Uint8List(zpad), lv(ci), lv(sid)]);
  return elligator2((await sha512(gs)).sublist(0, 32));
}

class PakeException implements Exception {
  const PakeException(this.message);
  final String message;
  @override
  String toString() => 'PakeException($message)';
}

Future<Uint8List> _x25519(List<int> seed32, List<int> u32) async {
  final X25519 algo = X25519();
  final SimpleKeyPair kp = await algo.newKeyPairFromSeed(seed32);
  final SecretKey k = await algo.sharedSecretKey(
      keyPair: kp, remotePublicKey: SimplePublicKey(u32, type: KeyPairType.x25519));
  final Uint8List out = Uint8List.fromList(await k.extractBytes());
  if (out.every((int b) => b == 0)) throw const PakeException('low order point');
  return out;
}

Future<Uint8List> _kdf(List<int> key, String label) async =>
    (await sha512(cat(<List<int>>[lv(label.codeUnits), lv(key)]))).sublist(0, 32);

Uint8List pakeTranscript(List<int> yc, List<int> ya, List<int> ci, List<int> sid) =>
    cat(<List<int>>[lv(yc), lv(ya), lv(ci), lv(sid)]);

/// The result of a finished exchange: the shared secret and what is derived from it.
class PakeKey {
  PakeKey._(this.isk, this._transcript);
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

  /// A 32 byte key for sealing the credential message.
  Future<Uint8List> channelKey() => _kdf(isk, 'channel');
}

/// One side of an exchange. The child device is [isChild] true.
class PakeParty {
  PakeParty._(this.isChild, this._seed, this._sid, this._ci, this.share);
  final bool isChild;
  final Uint8List _seed;
  final Uint8List _sid, _ci;

  /// The public share to send to the peer.
  final Uint8List share;

  /// [seed] is for golden vectors only; a real run leaves it null (32 CSPRNG bytes).
  static Future<PakeParty> start({
    required bool isChild,
    required List<int> password,
    required List<int> sid,
    required List<int> ci,
    List<int>? seed,
  }) async {
    final List<int> s =
        seed ?? await X25519().newKeyPair().then((SimpleKeyPair k) => k.extractPrivateKeyBytes());
    final Uint8List g = await cpaceGenerator(password, sid, ci);
    final Uint8List y = await _x25519(s, g);
    return PakeParty._(isChild, Uint8List.fromList(s), Uint8List.fromList(sid), Uint8List.fromList(ci), y);
  }

  /// Finishes with the peer's share. Throws [PakeException] for a malformed or low-order share.
  Future<PakeKey> finish(List<int> peerShare) async {
    if (peerShare.length != 32) throw const PakeException('bad share');
    final Uint8List k = await _x25519(_seed, peerShare);
    final Uint8List yc = isChild ? share : Uint8List.fromList(peerShare);
    final Uint8List ya = isChild ? Uint8List.fromList(peerShare) : share;
    final Uint8List isk = await sha512(
        cat(<List<int>>[lv('${kPakeDsi}_ISK'.codeUnits), lv(_sid), lv(k), lv(yc), lv(ya)]));
    return PakeKey._(isk, pakeTranscript(yc, ya, _ci, _sid));
  }
}
