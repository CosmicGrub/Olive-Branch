// OLIVE BRANCH — the persistent "pairing picture": a PUBLIC, revocable identity and rendezvous label for ONE device
// (an adult's or a child's). UNVERIFIED on a device; the logic here is pure and headless in CI
// (client/test/pairing_picture_test.dart). Design: docs/planning/PERSISTENT-QR-PAIRING.md.
//
// WHAT IT IS NOT. It is not a PIN, not a PAKE password, not a bearer token and not a credential. Scanning it only
// CHOOSES and PINS the other device (its Ed25519 key) and lets the two recognise each other's open window on the
// network. Nothing is paired because a picture was scanned: the adult still has to open a window by typing their
// own PIN, the PIN-PAKE (cpace.dart, unchanged) still has to succeed, and the adult still has to tap "Yes".
// Photographing the picture therefore gains nothing but a (mild, rotatable) handle for recognising windows.
//
// PAYLOAD  olive://id/1?r=<a|c>&k=<32-byte device public key>&s=<16-byte rendezvous salt>&e=<epoch 0..65535>
// Never present: a PIN or any secret, a session id, a one-time secret, an address, a name, a family or child id,
// a location, a counter. The key fingerprint is recomputed by the scanner. This scheme is NOT the one-shot
// olive://pair/1 of pairing_qr.dart; each parser rejects the other's strings, and neither is an OS deep link.
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'device_keys.dart';
import 'local_store.dart';
import 'pairing_protocol.dart' show kSasPictures;

const int kPictureMaxLength = 200;
const int kPictureTagBytes = 8;

enum PictureRole { adult, child }

/// A parsed or freshly built pairing picture.
class PairingPicture {
  const PairingPicture({required this.role, required this.publicKey, required this.salt, required this.epoch});
  final PictureRole role;
  final Uint8List publicKey, salt;
  final int epoch;

  /// First 16 bytes of SHA-256 of the key: what a window's `hello-ok` must also report.
  Future<Uint8List> fingerprint() => fingerprintOf(publicKey);

  /// The string that goes into the QR. About 100 characters.
  String get payload => Uri(scheme: 'olive', host: 'id', path: '/1', queryParameters: <String, String>{
        'r': role == PictureRole.adult ? 'a' : 'c',
        'k': b64(publicKey),
        's': b64(salt),
        'e': '$epoch',
      }).toString();
}

final RegExp _b64urlRe = RegExp(r'^[A-Za-z0-9_-]+$');

/// A canonical, unpadded base64url string of exactly [bytes] bytes, or null.
Uint8List? _exactBytes(String? s, int bytes) {
  if (s == null || !_b64urlRe.hasMatch(s)) return null;
  try {
    final Uint8List raw = unb64(s);
    if (raw.length != bytes || b64(raw) != s) return null; // rejects non-canonical trailing bits
    return raw;
  } catch (_) {
    return null;
  }
}

/// Null for anything that is not exactly a well-formed pairing picture. Fails closed: exactly the four keys, each
/// once, no extras, no whitespace, no fragment, no userinfo, no port, length at most [kPictureMaxLength].
PairingPicture? parsePairingPicture(String raw) {
  try {
    if (raw.isEmpty || raw.length > kPictureMaxLength) return null;
    if (!RegExp(r'^[\x21-\x7e]+$').hasMatch(raw)) return null;
    if (!raw.startsWith('olive://id/1?')) return null; // Uri lowercases the scheme and host; the format does not
    final Uri u = Uri.parse(raw);
    if (u.scheme != 'olive' || u.host != 'id' || u.path != '/1') return null;
    if (u.hasFragment || u.userInfo.isNotEmpty || u.hasPort || !u.hasQuery) return null;
    // Exactly four non-empty key=value segments: Uri silently drops an empty one ("&&", a trailing "&").
    final List<String> parts = u.query.split('&');
    if (parts.length != 4 || parts.any((String p) => p.split('=').length != 2 || p.startsWith('='))) return null;
    final Map<String, List<String>> q = u.queryParametersAll;
    if (q.length != 4 || !<String>['r', 'k', 's', 'e'].every(q.containsKey)) return null;
    if (q.values.any((List<String> v) => v.length != 1)) return null;
    final String r = q['r']!.single, e = q['e']!.single;
    if (r != 'a' && r != 'c') return null;
    if (!RegExp(r'^(0|[1-9][0-9]{0,4})$').hasMatch(e)) return null;
    final int epoch = int.parse(e);
    if (epoch > 65535) return null;
    final Uint8List? k = _exactBytes(q['k']!.single, 32), s = _exactBytes(q['s']!.single, 16);
    if (k == null || s == null) return null;
    return PairingPicture(role: r == 'a' ? PictureRole.adult : PictureRole.child, publicKey: k, salt: s, epoch: epoch);
  } catch (_) {
    return null;
  }
}

/// The window-recognition tag: the first 8 bytes of HMAC-SHA256(key = the addressed device's salt,
/// message = "olive-rdv/1" || sid). Only a device that holds (scanned or owns) the salt can tell it is for it.
Future<Uint8List> rendezvousTag(List<int> salt, List<int> sid) async {
  final Mac m = await Hmac.sha256().calculateMac(<int>[...utf8.encode('olive-rdv/1'), ...sid], secretKey: SecretKey(salt));
  return Uint8List.fromList(m.bytes.sublist(0, kPictureTagBytes));
}

/// True when [tag] is the tag [salt] would make for [sid]. Constant time.
Future<bool> tagMatches(List<int> salt, List<int> sid, List<int> tag) async {
  if (tag.length != kPictureTagBytes) return false;
  final Uint8List want = await rendezvousTag(salt, sid);
  int diff = 0;
  for (int i = 0; i < kPictureTagBytes; i++) {
    diff |= want[i] ^ tag[i];
  }
  return diff == 0;
}

/// What a child's `hello` signs to prove it holds the key it presents: "olive-hello/1" || sid || cpk.
Uint8List helloSignedBytes(List<int> sid, List<int> cpk) =>
    Uint8List.fromList(<int>[...utf8.encode('olive-hello/1'), ...sid, ...cpk]);

Future<Uint8List> signHello(DeviceKey key, List<int> sid) => key.sign(helloSignedBytes(sid, key.publicKey));

Future<bool> verifyHello(List<int> cpk, List<int> sid, List<int> signature) =>
    DeviceKey.verify(cpk, helloSignedBytes(sid, cpk), signature);

/// The nameless picture a child shows for a window in "no picture scanned" mode: derived from the window's
/// session id, so the adult's open-window screen and the child's tile agree without any name.
class WindowGlyph {
  const WindowGlyph(this.picture, this.colour);
  final String picture;

  /// 0..5, an index into a fixed palette the screens own.
  final int colour;
  @override
  bool operator ==(Object other) => other is WindowGlyph && other.picture == picture && other.colour == colour;
  @override
  int get hashCode => Object.hash(picture, colour);
  @override
  String toString() => '$colour:$picture';
}

WindowGlyph windowGlyph(List<int> sid) => WindowGlyph(kSasPictures[sid[0] & 15], sid[1] % 6);

// ---------------------------------------------------------------------------------------------------------------
// Local state: the salt and the epoch. Same storage tier as the device key (the 'devicekey' area).

class PairingPictureState {
  const PairingPictureState(this.salt, this.epoch);
  final Uint8List salt;
  final int epoch;
}

abstract class PairingPictureRepository {
  Future<PairingPictureState?> load();
  Future<void> save(PairingPictureState state);
}

class MemoryPairingPictureRepository implements PairingPictureRepository {
  PairingPictureState? _s;
  @override
  Future<PairingPictureState?> load() async => _s;
  @override
  Future<void> save(PairingPictureState state) async => _s = state;
}

class LocalStorePairingPictureRepository implements PairingPictureRepository {
  LocalStorePairingPictureRepository(this._ns);
  final LocalNamespace _ns;
  static const String _key = 'picture';

  @override
  Future<PairingPictureState?> load() async {
    final Object? raw = await _ns.get(_key);
    if (raw is! Map) return null;
    final Object? s = raw['s'], e = raw['e'];
    if (s is! String || e is! int || e < 0 || e > 65535) return null;
    final Uint8List? salt = _exactBytes(s, 16);
    return salt == null ? null : PairingPictureState(salt, e);
  }

  @override
  Future<void> save(PairingPictureState state) => _ns.put(_key, <String, Object?>{'s': b64(state.salt), 'e': state.epoch});
}

/// Builds this device's picture and rotates it. The DEVICE KEY is never rotated here: refreshing only changes the
/// salt and the epoch, so old copies stop finding windows while connected devices stay connected.
class PairingPictureService {
  PairingPictureService(this.repo, {Random? random}) : _random = random ?? Random.secure();
  final PairingPictureRepository repo;
  final Random _random;

  Uint8List _newSalt() => Uint8List.fromList(List<int>.generate(16, (_) => _random.nextInt(256)));

  /// Loads the state, or makes the first one. A store that cannot be written still returns a working state for
  /// this run (the cost is a different picture next run).
  Future<PairingPictureState> state() async {
    PairingPictureState? s;
    try {
      s = await repo.load();
    } catch (_) {
      s = null;
    }
    if (s != null) return s;
    final PairingPictureState fresh = PairingPictureState(_newSalt(), 0);
    try {
      await repo.save(fresh);
    } catch (_) {}
    return fresh;
  }

  Future<PairingPicture> own(DeviceKey key, PictureRole role) async {
    final PairingPictureState s = await state();
    return PairingPicture(role: role, publicKey: key.publicKey, salt: s.salt, epoch: s.epoch);
  }

  /// "Refresh picture": a new salt and the next epoch (wrapping at 65535).
  Future<PairingPictureState> refresh() async {
    final PairingPictureState old = await state();
    final PairingPictureState next = PairingPictureState(_newSalt(), (old.epoch + 1) & 0xffff);
    await repo.save(next);
    return next;
  }
}
