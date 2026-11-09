// OLIVE BRANCH — the on-device pairing protocol: an ADULT-OPENED window on the adult device, a PIN (or a
// one-time QR secret) as the PAKE password, mutual key confirmation, a confirmation word and picture shown on
// both screens, a one-tap approval on the adult device, then a signed per-device certificate. UNVERIFIED on a
// device; runs headless in CI. Spec: docs/superpowers/specs/2026-11-08-adult-gate-and-simple-pairing-design.md
// sections 3, 6, 10. The PAKE is cpace.dart (custom crypto: read its header).
//
// WHY A PIN NEVER SELECTS WHO YOU CONNECT TO. The peer is chosen FIRST: by the adult naming their own open
// window (session id) or by scanning that window's QR. The PIN then only proves "I am the adult who opened THAT
// window". The channel identifier mixed into the PAKE holds the session id, the family id, the adult device's
// key fingerprint, the adult's name and the child device's key, so a device of another family, another
// session, or a rogue advertiser derives a different key even if it knows (or guesses) the PIN, and cannot
// pass key confirmation. Nothing is paired unless the adult then taps "Yes, that is Ivy's tablet".
//
// WHERE THE COUNTERS LIVE. On the ADULT device ([AdultWindow]): five failed confirmations kill the window; a
// window lasts minutes; a session id works once. The child device keeps no counter that matters here.
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import 'cpace.dart';
import 'device_keys.dart';
import 'local_pin.dart' show LocalPinRecord, constantTimeEquals, kLocalPinIterations;

const Duration kWindowTtl = Duration(minutes: 10);
const int kWindowMaxAttempts = 5;
const int _kMaxPake1PerWindow = 20;

/// The child's confirmation pictures and words: 16 of each, picked by two bytes of the shared key.
const List<String> kSasPictures = <String>[
  'sun', 'moon', 'star', 'cloud', 'tree', 'fish', 'bird', 'cat',
  'dog', 'boat', 'house', 'flower', 'apple', 'ball', 'kite', 'bell',
];
const List<String> kSasWords = <String>[
  'red', 'blue', 'green', 'gold', 'pink', 'brave', 'calm', 'happy',
  'quick', 'soft', 'warm', 'kind', 'bright', 'wise', 'cosy', 'merry',
];

class Sas {
  const Sas(this.picture, this.word);
  final String picture, word;
  factory Sas.fromBytes(List<int> b) => Sas(kSasPictures[b[0] & 15], kSasWords[b[1] & 15]);
  @override
  String toString() => '$word $picture';
}

/// A way to deliver one message to the adult device's window and get its answer. Null = no answer (a closed,
/// unknown or wrong-session window never answers, so it cannot be told from nobody listening).
abstract class PairingTransport {
  Future<Map<String, dynamic>?> send(Map<String, dynamic> message);
}

/// In-process transport for tests and for the same-process path: routes to one window.
class LoopbackPairingTransport implements PairingTransport {
  LoopbackPairingTransport(this.target, {this.log});
  final AdultWindow target;
  final List<Map<String, dynamic>>? log;
  @override
  Future<Map<String, dynamic>?> send(Map<String, dynamic> message) {
    log?.add(Map<String, dynamic>.of(message));
    return target.handle(message);
  }
}

enum WindowState { open, awaitingApproval, approved, declined, closed }

class _Pending {
  _Pending(this.party, this.cpk, this.deviceName, this.qr, this.yc);
  final PakeParty party;
  final Uint8List cpk;
  final String deviceName;
  final bool qr;
  final Uint8List yc;
}

/// What the adult device remembers about a child device it certified (and can later forget).
class PairedKid {
  const PairedKid({required this.certId, required this.childDeviceKey, required this.childId, required this.deviceName, required this.issuedAtMs});
  final String certId, childId, deviceName;
  final Uint8List childDeviceKey;
  final int issuedAtMs;
}

/// The adult-opened pairing window. One per "Connect a child's device" screen; in memory only.
class AdultWindow extends ChangeNotifier {
  AdultWindow._({
    required this.adultKey,
    required this.adultName,
    required this.familyId,
    required this.childId,
    required this.childName,
    required String? pin,
    required this.sid,
    required this.qrSecret,
    required this.expiresAt,
    required this.maxAttempts,
    required DateTime Function() now,
    required this.makeUnlockVerifier,
    required this.onPaired,
  })  : _pin = pin, // ignore: prefer_initializing_formals
        _now = now, // ignore: prefer_initializing_formals
        attemptsLeft = maxAttempts;

  final DeviceKey adultKey;
  final String adultName, familyId, childId, childName;
  final Uint8List sid;

  /// The one-time QR secret, or null when the adult did not offer the QR shortcut (or it was used).
  Uint8List? qrSecret;
  final DateTime expiresAt;
  final int maxAttempts;
  final DateTime Function() _now;

  /// Makes the salted slow verifier of the PIN that goes to the child device (for adult unlock there).
  final Future<LocalPinRecord> Function(String pin) makeUnlockVerifier;
  final void Function(PairedKid kid)? onPaired;

  String? _pin;
  int attemptsLeft;
  WindowState state = WindowState.open;
  int _pake1Count = 0;
  _Pending? _pending;
  PakeKey? _key;
  Uint8List? _cpk;
  String _deviceName = '';
  Uint8List? _tagC;
  Uint8List? _sealed;

  /// Set once a child device passed key confirmation: what the adult is asked to approve.
  String? get pendingDeviceName => state == WindowState.awaitingApproval ? _deviceName : null;
  Sas? sas;

  static Future<AdultWindow> open({
    required DeviceKey adultKey,
    required String adultName,
    required String familyId,
    required String childId,
    required String childName,
    required String pin,
    bool offerQr = false,
    Duration ttl = kWindowTtl,
    int maxAttempts = kWindowMaxAttempts,
    DateTime Function()? now,
    Random? random,
    Future<LocalPinRecord> Function(String pin)? makeUnlockVerifier,
    void Function(PairedKid kid)? onPaired,
  }) async {
    final Random r = random ?? Random.secure();
    Uint8List bytes(int n) => Uint8List.fromList(List<int>.generate(n, (_) => r.nextInt(256)));
    final DateTime Function() clock = now ?? DateTime.now;
    return AdultWindow._(
      adultKey: adultKey, adultName: adultName, familyId: familyId, childId: childId, childName: childName,
      pin: pin, sid: bytes(16), qrSecret: offerQr ? bytes(16) : null, expiresAt: clock().add(ttl),
      maxAttempts: maxAttempts, now: clock, onPaired: onPaired,
      makeUnlockVerifier: makeUnlockVerifier ?? (String p) => _defaultVerifier(p, r),
    );
  }

  static Future<LocalPinRecord> _defaultVerifier(String pin, Random r) async {
    final Uint8List salt = Uint8List.fromList(List<int>.generate(16, (_) => r.nextInt(256)));
    final SecretKey k = await Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: kLocalPinIterations, bits: 256)
        .deriveKeyFromPassword(password: pin, nonce: salt);
    return LocalPinRecord(iterations: kLocalPinIterations, salt: salt, hash: Uint8List.fromList(await k.extractBytes()));
  }

  /// The QR payload, only while the window is open and the secret unused. Proximity: the address hints are
  /// LAN addresses supplied by the transport; this layer never puts anything reusable in it.
  String? qrPayload({List<String> hints = const <String>[]}) {
    if (state != WindowState.open || qrSecret == null || _expired) return null;
    final Uri u = Uri(scheme: 'olive', host: 'pair', path: '/1', queryParameters: <String, String>{
      's': b64(sid), 'k': b64(adultKey.fingerprint), 'q': b64(qrSecret!),
      if (hints.isNotEmpty) 'a': hints.join(','),
    });
    return u.toString();
  }

  bool get _expired => !_now().isBefore(expiresAt);

  bool get isOpen => state == WindowState.open || state == WindowState.awaitingApproval;

  Uint8List _channelId(List<int> cpk) => cat(<List<int>>[
        lv(sid), lv(utf8.encode(familyId)), lv(adultKey.fingerprint), lv(cpk), lv(utf8.encode(adultName)),
      ]);

  void close() {
    if (state == WindowState.closed) return;
    state = WindowState.closed;
    _pin = null; // the PIN is held only while the window lives
    qrSecret = null;
    _pending = null;
    _key = null;
    notifyListeners();
  }

  void _fail() {
    attemptsLeft -= 1;
    _pending = null;
    if (attemptsLeft <= 0) {
      close();
    } else {
      notifyListeners();
    }
  }

  /// One incoming message. Null means "no answer". Never throws on a malformed message.
  Future<Map<String, dynamic>?> handle(Map<String, dynamic> m) async {
    try {
      return await _handle(m);
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _handle(Map<String, dynamic> m) async {
    if (state == WindowState.closed || state == WindowState.declined) return null;
    if (_expired) {
      close();
      return null;
    }
    final Object? sidRaw = m['sid'];
    if (sidRaw is! String || !constantTimeEquals(unb64(sidRaw), sid)) return null;
    switch (m['t']) {
      case 'hello':
        if (state != WindowState.open) return null;
        return <String, dynamic>{
          't': 'hello-ok', 'afp': b64(adultKey.fingerprint), 'apk': b64(adultKey.publicKey),
          'an': adultName, 'fid': familyId,
        };
      case 'pake1':
        if (state != WindowState.open || ++_pake1Count > _kMaxPake1PerWindow) return null;
        final Uint8List cpk = unb64(m['cpk'] as String), yc = unb64(m['Yc'] as String);
        if (cpk.length != 32 || yc.length != 32) return null;
        final bool qr = m['m'] == 'qr';
        final List<int>? password = qr
            ? (qrSecret == null ? null : utf8.encode(b64(qrSecret!)))
            : (_pin == null ? null : utf8.encode(_pin!));
        if (password == null) return null;
        final PakeParty party = await PakeParty.start(isChild: false, password: password, sid: sid, ci: _channelId(cpk));
        _pending = _Pending(party, cpk, _clip(m['dn']), qr, yc);
        return <String, dynamic>{'t': 'pake2', 'Ya': b64(party.share)};
      case 'confirm':
        final _Pending? p = _pending;
        if (state != WindowState.open || p == null) return null;
        _pending = null;
        if (p.qr) qrSecret = null; // one use, success or not
        PakeKey? key;
        try {
          key = await p.party.finish(p.yc);
        } on PakeException {
          key = null;
        }
        final Uint8List tagC = unb64(m['tagC'] as String);
        if (key == null || !await key.checkTag('C', tagC)) {
          _fail();
          return <String, dynamic>{'t': 'confirm-no'};
        }
        _key = key;
        _cpk = p.cpk;
        _deviceName = p.deviceName;
        _tagC = tagC;
        sas = Sas.fromBytes(await key.sas());
        state = WindowState.awaitingApproval;
        notifyListeners();
        return <String, dynamic>{'t': 'confirm-ok', 'tagA': b64(await key.tag('A'))};
      case 'poll':
        if (_tagC == null || !constantTimeEquals(unb64(m['tagC'] as String), _tagC!)) return null;
        if (state == WindowState.awaitingApproval) return <String, dynamic>{'t': 'wait'};
        if (state == WindowState.approved) {
          final Uint8List sealed = _sealed!;
          close(); // a credential is handed over once
          return <String, dynamic>{'t': 'approved', 'sealed': b64(sealed)};
        }
        return null;
    }
    return null;
  }

  String _clip(Object? v) {
    final String s = v is String ? v.trim() : '';
    return s.isEmpty ? 'A tablet' : (s.length > 32 ? s.substring(0, 32) : s);
  }

  /// The adult tapped "Yes, that is her tablet". Issues the certificate and seals it for the child device.
  Future<bool> approve() async {
    if (state != WindowState.awaitingApproval || _key == null || _cpk == null || _expired) return false;
    final Random r = Random.secure();
    final String certId = b64(List<int>.generate(12, (_) => r.nextInt(256)));
    final int iat = _now().millisecondsSinceEpoch;
    final PairingCert cert = await PairingCert.issue(adultKey,
        childDeviceKey: _cpk!, familyId: familyId, childId: childId, certId: certId, issuedAtMs: iat);
    final LocalPinRecord verifier = await makeUnlockVerifier(_pin ?? '');
    final Map<String, Object?> body = <String, Object?>{
      'cert': cert.toJson(), 'apk': b64(adultKey.publicKey), 'an': adultName, 'childName': childName,
      'verifier': <String, Object?>{'iter': verifier.iterations, 'salt': b64(verifier.salt), 'hash': b64(verifier.hash)},
    };
    final AesGcm aes = AesGcm.with256bits();
    final SecretBox box = await aes.encrypt(utf8.encode(jsonEncode(body)), secretKey: SecretKey(await _key!.channelKey()));
    _sealed = Uint8List.fromList(box.concatenation());
    state = WindowState.approved;
    onPaired?.call(PairedKid(certId: certId, childDeviceKey: _cpk!, childId: childId, deviceName: _deviceName, issuedAtMs: iat));
    notifyListeners();
    return true;
  }

  void decline() {
    if (state != WindowState.awaitingApproval) return;
    state = WindowState.declined;
    _pin = null;
    notifyListeners();
  }
}

/// What a child device keeps after a successful pairing.
class ChildPairing {
  const ChildPairing({
    required this.cert, required this.adultKey, required this.adultName, required this.childName, required this.unlockVerifier,
  });
  final PairingCert cert;
  final Uint8List adultKey;
  final String adultName, childName;
  final LocalPinRecord unlockVerifier;
}

enum PairingFailure { unreachable, notMatched, declined, timedOut, malformed }

class PairingResult {
  const PairingResult.ok(ChildPairing this.pairing) : failure = null;
  const PairingResult.failed(PairingFailure this.failure) : pairing = null;
  final ChildPairing? pairing;
  final PairingFailure? failure;
  bool get ok => pairing != null;
}

/// What the child's screen shows (picture first) once the adult device passed confirmation.
class PairingMatch {
  const PairingMatch(this.adultName, this.sas);
  final String adultName;
  final Sas sas;
}

class ChildPairingClient {
  ChildPairingClient({
    required this.childKey,
    required this.transport,
    this.deviceName = 'A tablet',
    this.pollEvery = const Duration(seconds: 2),
    this.giveUpAfter = const Duration(minutes: 10),
    Future<void> Function(Duration)? delay,
  }) : _delay = delay ?? Future<void>.delayed;

  final DeviceKey childKey;
  final PairingTransport transport;
  final String deviceName;
  final Duration pollEvery, giveUpAfter;
  final Future<void> Function(Duration) _delay;

  /// Runs the whole exchange. [sid] names the adult's open window (picked by name, or from the QR);
  /// [password] is the typed PIN or the QR secret ([viaQr]); [expectedAdultFingerprint] comes from the QR.
  /// [onMatched] fires when the adult device proved it knows the secret: show the name and the pair.
  Future<PairingResult> pair({
    required Uint8List sid,
    required String password,
    bool viaQr = false,
    Uint8List? expectedAdultFingerprint,
    void Function(PairingMatch match)? onMatched,
  }) async {
    try {
      final Map<String, dynamic>? hello = await transport.send(<String, dynamic>{
        't': 'hello', 'sid': b64(sid), 'cpk': b64(childKey.publicKey), 'dn': deviceName,
      });
      if (hello == null || hello['t'] != 'hello-ok') return const PairingResult.failed(PairingFailure.unreachable);
      final Uint8List apk = unb64(hello['apk'] as String), afp = unb64(hello['afp'] as String);
      final String an = hello['an'] as String, fid = hello['fid'] as String;
      if (!constantTimeEquals(await fingerprintOf(apk), afp)) return const PairingResult.failed(PairingFailure.notMatched);
      if (expectedAdultFingerprint != null && !constantTimeEquals(expectedAdultFingerprint, afp)) {
        return const PairingResult.failed(PairingFailure.notMatched);
      }
      final Uint8List ci = cat(<List<int>>[
        lv(sid), lv(utf8.encode(fid)), lv(afp), lv(childKey.publicKey), lv(utf8.encode(an)),
      ]);
      final PakeParty party = await PakeParty.start(isChild: true, password: utf8.encode(password), sid: sid, ci: ci);
      final Map<String, dynamic>? p2 = await transport.send(<String, dynamic>{
        't': 'pake1', 'sid': b64(sid), 'cpk': b64(childKey.publicKey), 'dn': deviceName,
        'm': viaQr ? 'qr' : 'pin', 'Yc': b64(party.share),
      });
      if (p2 == null || p2['t'] != 'pake2') return const PairingResult.failed(PairingFailure.notMatched);
      final PakeKey key = await party.finish(unb64(p2['Ya'] as String));
      final Uint8List tagC = await key.tag('C');
      final Map<String, dynamic>? c = await transport.send(<String, dynamic>{'t': 'confirm', 'sid': b64(sid), 'tagC': b64(tagC)});
      if (c == null || c['t'] != 'confirm-ok') return const PairingResult.failed(PairingFailure.notMatched);
      if (!await key.checkTag('A', unb64(c['tagA'] as String))) return const PairingResult.failed(PairingFailure.notMatched);
      onMatched?.call(PairingMatch(an, Sas.fromBytes(await key.sas())));
      Duration waited = Duration.zero;
      while (waited <= giveUpAfter) {
        final Map<String, dynamic>? r = await transport.send(<String, dynamic>{'t': 'poll', 'sid': b64(sid), 'tagC': b64(tagC)});
        if (r == null) return const PairingResult.failed(PairingFailure.declined);
        if (r['t'] == 'approved') return _open(await _decrypt(key, r['sealed'] as String), apk, afp, fid);
        await _delay(pollEvery);
        waited += pollEvery;
      }
      return const PairingResult.failed(PairingFailure.timedOut);
    } catch (_) {
      return const PairingResult.failed(PairingFailure.malformed);
    }
  }

  Future<Map<String, dynamic>> _decrypt(PakeKey key, String sealed) async {
    final SecretBox box = SecretBox.fromConcatenation(unb64(sealed), nonceLength: 12, macLength: 16);
    final List<int> plain = await AesGcm.with256bits().decrypt(box, secretKey: SecretKey(await key.channelKey()));
    return jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
  }

  Future<PairingResult> _open(Map<String, dynamic> body, Uint8List apk, Uint8List afp, String fid) async {
    final PairingCert? cert = PairingCert.fromJson(body['cert']);
    if (cert == null || !await cert.verifiedBy(apk)) return const PairingResult.failed(PairingFailure.malformed);
    if (!constantTimeEquals(cert.childDeviceKey, childKey.publicKey) || cert.familyId != fid) {
      return const PairingResult.failed(PairingFailure.malformed);
    }
    final Object? v = body['verifier'];
    final LocalPinRecord? verifier = v is Map
        ? LocalPinRecord(
            iterations: v['iter'] as int, salt: unb64(v['salt'] as String), hash: unb64(v['hash'] as String))
        : null;
    if (verifier == null) return const PairingResult.failed(PairingFailure.malformed);
    return PairingResult.ok(ChildPairing(
        cert: cert, adultKey: apk, adultName: body['an'] as String, childName: body['childName'] as String,
        unlockVerifier: verifier));
  }
}
