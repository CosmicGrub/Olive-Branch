// OLIVE BRANCH — the on-device pairing protocol: an ADULT-OPENED window on the adult device, a PIN (or a
// one-time QR secret) as the PAKE password, mutual key confirmation, a confirmation word and picture shown on
// both screens, a one-tap approval on the adult device, then a signed per-device certificate. UNVERIFIED on a
// device; runs headless in CI. Spec: docs/superpowers/specs/2026-11-08-adult-gate-and-simple-pairing-design.md
// sections 3, 6, 10. The PAKE is cpace.dart (custom crypto: read its header).
//
// WHY A PIN NEVER SELECTS WHO YOU CONNECT TO. The peer is chosen FIRST: by the adult naming their own open
// window (session id) or by scanning that window's QR. The PIN then only proves "I am the adult who opened THAT
// window". The channel identifier mixed into the PAKE holds the session id and the child device's key (and the
// adult device's key fingerprint when the child already knows it, from a QR or a scanned picture), so another
// session, or a rogue advertiser, derives a different key even if it knows (or guesses) the PIN, and cannot pass
// key confirmation. Nothing is paired unless the adult then taps "Yes, that is Ivy's tablet".
//
// PROTOCOL VERSION 2: WHO THE ADULT IS TRAVELS ONLY INSIDE THE KEY. The answer to the first message ("hello-ok")
// is bare: the session id, the protocol version and (for a claimed child) a blinded family hint. The adult's name,
// family id and public key arrive in the answer to the key CONFIRMATION, sealed under the exchange's own key
// (AES-GCM, its own associated data), so a device on the same network that merely holds the public window handle
// learns nothing about the grown-up. The child checks them (key fingerprint, expected fingerprint, expected family)
// BEFORE it shows the match step and before it ever polls. A build that speaks only version 1 gets silence from a
// version 2 window and fails calmly; a version 2 child that meets a version 1 window fails calmly too
// (PairingFailure.versionMismatch).
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
import 'pairing_match.dart';
import 'pairing_picture.dart';

/// The pairing protocol version this build speaks, and the oldest it still accepts. Version 1 returned the adult's
/// name, family id and key in the clear in hello-ok and is NOT accepted any more.
const int kPairingProtocolVersion = 2;
const int kMinPairingProtocolVersion = 2;

const Duration kWindowTtl = Duration(minutes: 10);
const int kWindowMaxAttempts = 5;
const int _kMaxPake1PerWindow = 20;

/// One request in flight at a time: a second device that starts while one is mid-handshake is dropped silently,
/// and an abandoned claim frees the window again after this long.
const Duration kClaimTtl = Duration(minutes: 5);

/// The quiet per-source budget on the adult window (one source = one LAN address, see sourceKey).
/// A device on the same Wi-Fi that merely sees the window can burn at most [kSourceMaxFailures] of the window's
/// [kWindowMaxAttempts] confirmations; past its budget it gets the same silence as a closed window. The failure
/// limit is kept BELOW HALF the window cap on purpose: a dual-stack host has an IPv4 and an IPv6 address that this
/// layer cannot tie together, so two budgets must still sum under the cap and leave the real child a try
/// (a test pins this). A source's first-message and key-exchange tries are capped too, so one address cannot use
/// up the window's 20 key exchanges or keep overwriting the real child's half-finished one.
/// The table of sources is bounded and NEVER refuses a new source: it is least-recently-used, so a flood of free
/// hellos (which need only the public handle) just evicts idle entries. A source that has FAILED a confirmation
/// (at most [kWindowMaxAttempts] of them per window) is never evicted, so a flood cannot wash a block away.
/// None of this is ever shown to a child.
const int kSourceMaxHello = 12;
const int kSourceMaxPake1 = 6;
const int kSourceMaxFailures = 2;
const int kMaxTrackedSources = 256;

/// The neutral seat name a window shows ("Player one" or "Player two"). It is derived from the random discovery
/// handle (one bit of it), never from the adult, the family, the device or the session id, so it identifies nobody.
String windowSeatLabel(List<int> discoveryHandle) => (discoveryHandle[2] & 1) == 0 ? 'Player one' : 'Player two';

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

/// The channel identifier mixed into the key exchange (version 2). [adultFingerprint] is included only when the
/// child device already knows it from outside the network (a QR or a scanned picture) and says so with `fb`.
Uint8List pairingChannelId(List<int> sid, List<int> childKey, List<int>? adultFingerprint) => cat(<List<int>>[
      lv(utf8.encode('olive-pair-ci/2')), lv(sid), lv(childKey), lv(adultFingerprint ?? const <int>[]),
    ]);

final List<int> _aadIdentity = utf8.encode('olive-pair-id/2');
final List<int> _aadCredential = utf8.encode('olive-pair-cred/2');

/// The blinded family hint a window with a family key puts in hello-ok: HMAC(family key, session, child key),
/// first 8 bytes. Without the family key it looks random and says nothing about which family the window is.
Future<Uint8List> familyHelloTag(List<int> familyKey, List<int> sid, List<int> childKey) async {
  final Mac m = await Hmac.sha256().calculateMac(
      cat(<List<int>>[lv(utf8.encode('olive-fam-hello/2')), lv(sid), lv(childKey)]),
      secretKey: SecretKey(familyKey));
  return Uint8List.fromList(m.bytes.sublist(0, 8));
}

/// A blinded "I am the adult whose fingerprint you hold" hint: HMAC keyed with the adult device's fingerprint over the
/// session and the child's key, first 8 bytes. A device that does not already hold that fingerprint (from a QR or a
/// scanned picture) cannot check it and learns nothing from it; a child that does hold it can stop BEFORE any key
/// exchange when the window is not that adult, costing the real adult nothing.
Future<Uint8List> adultHelloTag(List<int> adultFingerprint, List<int> sid, List<int> childKey) async {
  final Mac m = await Hmac.sha256().calculateMac(
      cat(<List<int>>[lv(utf8.encode('olive-adult-hello/2')), lv(sid), lv(childKey)]),
      secretKey: SecretKey(adultFingerprint));
  return Uint8List.fromList(m.bytes.sublist(0, 8));
}

/// A way to deliver one message to the adult device's window and get its answer. Null = no answer (a closed,
/// unknown or wrong-session window never answers, so it cannot be told from nobody listening).
abstract class PairingTransport {
  Future<Map<String, dynamic>?> send(Map<String, dynamic> message);
}

/// In-process transport for tests and for the same-process path: routes to one window.
class LoopbackPairingTransport implements PairingTransport {
  LoopbackPairingTransport(this.target, {this.log, this.source});
  final AdultWindow target;
  final List<Map<String, dynamic>>? log;

  /// Pretend source address (tests); null = unlimited, as an in-process caller is.
  final String? source;
  @override
  Future<Map<String, dynamic>?> send(Map<String, dynamic> message) {
    log?.add(Map<String, dynamic>.of(message));
    return target.handle(message, source: source);
  }
}

enum WindowState { open, awaitingApproval, approved, declined, closed }

class _SourceUse {
  int hello = 0, pake1 = 0, failures = 0;
}

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
  const PairedKid({required this.certId, required this.childDeviceKey, required this.childId, required this.deviceName, required this.issuedAtMs, this.phoneOnly = false});
  final String certId, childId, deviceName;
  final Uint8List childDeviceKey;
  final int issuedAtMs;

  /// This tablet never accepts a typed code; only the grown-up's phone unlocks it.
  final bool phoneOnly;
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
    required this.discoveryHandle,
    required this.qrSecret,
    required this.expiresAt,
    required this.maxAttempts,
    required DateTime Function() now,
    required this.makeUnlockVerifier,
    required this.onPaired,
    required this.phoneOnly,
    required this.familyKey,
    required this.requireMatch,
    required Random random,
    required this.refuseKey,
  })  : _random = random, // ignore: prefer_initializing_formals
        _pin = pin, // ignore: prefer_initializing_formals
        _now = now, // ignore: prefer_initializing_formals
        attemptsLeft = maxAttempts;

  final DeviceKey adultKey;
  final String adultName, familyId, childId, childName;
  final Uint8List sid;

  /// What a nearby device finds the window by in the (neutral) advertisement: random per window, 16 bytes, and NOT
  /// the session id. It works only for the first message (hello); the session id then comes back in the answer.
  final Uint8List discoveryHandle;

  /// The neutral seat name ("Player one" / "Player two") the advertisement shows: derived only from the random
  /// handle, so it names nobody. The picture on the tile is what a person actually matches.
  String get label => windowSeatLabel(discoveryHandle);

  /// The one-time QR secret, or null when the adult did not offer the QR shortcut (or it was used).
  Uint8List? qrSecret;
  final DateTime expiresAt;
  final int maxAttempts;
  final DateTime Function() _now;

  /// Makes the salted slow verifier of the PIN that goes to the child device (for adult unlock there).
  final Future<LocalPinRecord> Function(String pin) makeUnlockVerifier;
  final void Function(PairedKid kid)? onPaired;
  final Random _random;

  /// The family key (16 bytes) that goes to the child inside the sealed credential, so a claimed child can later
  /// tell its own family's pictures from a stranger's. Null = none (older callers).
  final Uint8List? familyKey;

  /// Asked with a child device's public key on hello and pake1: true = the grown-up stopped that device earlier, so
  /// the window stays silent to it (no answer, no attempt counted).
  final Future<bool> Function(List<int> deviceKey)? refuseKey;

  /// When true, [approve] refuses until the adult picked the matching set ([pickMatch]).
  final bool requireMatch;

  /// Do not give the tablet a PIN verifier at all: only the grown-up's phone will ever unlock it.
  final bool phoneOnly;

  String? _pin;
  int attemptsLeft;
  WindowState state = WindowState.open;
  int _pake1Count = 0;
  final Map<String, _SourceUse> _sources = <String, _SourceUse>{};
  _Pending? _pending;
  DateTime? _pendingAt;
  PakeKey? _key;
  Uint8List? _cpk;
  String _deviceName = '';
  Uint8List? _tagC;
  Uint8List? _sealed;
  Uint8List? _pollNonce;
  final List<Uint8List> _helloNonces = <Uint8List>[];

  Uint8List _freshNonce() {
    final Random r = Random.secure();
    return Uint8List.fromList(List<int>.generate(16, (_) => r.nextInt(256)));
  }

  // The pairing picture (docs/planning/PERSISTENT-QR-PAIRING.md). None of this authorizes anything: it only decides
  // which devices this window recognises and answers. The PIN-PAKE and the adult's "Yes" are unchanged.
  Uint8List? _allowedChildKey, _childSalt, _adultSalt;
  Uint8List? _helloCpk;
  late final Uint8List _randomTag = Uint8List.fromList(List<int>.generate(kPictureTagBytes, (_) => Random.secure().nextInt(256)));

  /// The child device whose picture the adult scanned (Mode B). Null = any child may try (the PIN path).
  Uint8List? get allowedChildKey => _allowedChildKey;

  /// Mode B: the adult scanned the child's picture. From now on only a hello that carries that device's key AND a
  /// valid proof-of-possession signature is answered, and anything else is dropped BEFORE an attempt is counted.
  /// The window's tag is then made from the child's salt, which only that child can recognise.
  void allowChild({required Uint8List childKey, required Uint8List childSalt}) {
    if (state != WindowState.open) return;
    _allowedChildKey = Uint8List.fromList(childKey);
    _childSalt = Uint8List.fromList(childSalt);
    notifyListeners();
  }

  /// "Make a new code": drop a claim that is mid-handshake (its exchange was tied to the old picture) and address the
  /// window to the new salt. Connected devices are not affected; only an open window is.
  void refreshAdultPicture(Uint8List newAdultSalt) {
    if (state != WindowState.open) return;
    _pending = null;
    _pendingAt = null;
    _adultSalt = Uint8List.fromList(newAdultSalt);
    notifyListeners();
  }

  /// Mode A: the adult is showing their own picture, so a child that scanned it can recognise this window.
  void showAdultPicture(Uint8List adultSalt) {
    if (state != WindowState.open) return;
    _adultSalt = Uint8List.fromList(adultSalt);
    notifyListeners();
  }

  /// True once a picture (the child's, or this adult's own) addresses this window; false = Mode N, random tag.
  bool get hasPicture => _childSalt != null || _adultSalt != null;

  /// The 8-byte recognition tag for the mDNS TXT record. The child's salt wins over the adult's when both are
  /// known (Mode A+B). Random per window when no picture addresses it, so a nameless window cannot be told apart
  /// from a picture-addressed one by anyone without the salt.
  Future<Uint8List> windowTag() async {
    final Uint8List? salt = _childSalt ?? _adultSalt;
    return salt == null ? _randomTag : rendezvousTag(salt, discoveryHandle);
  }

  /// Set once a child device passed key confirmation: what the adult is asked to approve.
  String? get pendingDeviceName => state == WindowState.awaitingApproval ? _deviceName : null;
  Sas? sas;

  /// The Match step: four candidate sets for the adult to choose from, the real one among them. Set once the child
  /// device passed key confirmation.
  MatchChoices? matchChoices;
  MatchSet? _matchReal;
  bool matchConfirmed = false;

  /// True after the adult picked a wrong set, or "None of these". The window is then closed to this device.
  bool matchRefused = false;

  /// The adult chose [index] (0..3), or null for "None of these". A right pick unlocks [approve]; a wrong one, or
  /// null, refuses the pairing (the window closes, nothing is issued). Returns true only for the right pick.
  bool pickMatch(int? index) {
    if (state != WindowState.awaitingApproval || matchChoices == null || matchConfirmed) return false;
    if (index != null && index == matchChoices!.correct) {
      matchConfirmed = true;
      notifyListeners();
      return true;
    }
    matchRefused = true;
    decline();
    return false;
  }

  /// What the child device must show for the Match step (the real set). Exposed for tests; the adult screen never
  /// reads it.
  @visibleForTesting
  MatchSet? get debugRealMatch => _matchReal;

  static Future<AdultWindow> open({
    required DeviceKey adultKey,
    required String adultName,
    required String familyId,
    required String childId,
    required String childName,
    required String pin,
    bool offerQr = false,
    // DEFAULT (since the pairing hardening): the tablet is given NO typed-code verifier, so a tablet that is lost or
    // copied holds nothing an attacker can try millions of PINs against offline. Passing false is the grown-up's
    // explicit opt-in to a keypad on that tablet (MASTERFILE 8.5.9; the honest limit is in local_pin.dart).
    bool phoneOnly = true,
    Uint8List? familyKey,
    bool requireMatch = false,
    Future<bool> Function(List<int> deviceKey)? refuseKey,
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
      pin: pin, sid: bytes(16), discoveryHandle: bytes(16), qrSecret: offerQr ? bytes(16) : null, expiresAt: clock().add(ttl),
      maxAttempts: maxAttempts, now: clock, onPaired: onPaired, phoneOnly: phoneOnly,
      familyKey: familyKey, requireMatch: requireMatch, random: r, refuseKey: refuseKey,
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

  Uint8List _channelId(List<int> cpk, {required bool bindAdult}) =>
      pairingChannelId(sid, cpk, bindAdult ? adultKey.fingerprint : null);

  /// Who this adult is, sealed for the child under the exchange's own key (only a device that passed key
  /// confirmation can open it).
  Future<Uint8List> _sealedIdentity(PakeKey key) async {
    final Map<String, Object?> body = <String, Object?>{'apk': b64(adultKey.publicKey), 'an': adultName, 'fid': familyId};
    final SecretBox box = await AesGcm.with256bits()
        .encrypt(utf8.encode(jsonEncode(body)), secretKey: SecretKey(await key.channelKey()), aad: _aadIdentity);
    return Uint8List.fromList(box.concatenation());
  }

  void close() {
    if (state == WindowState.closed) return;
    state = WindowState.closed;
    _pin = null; // the PIN is held only while the window lives
    qrSecret = null;
    _pending = null;
    _pendingAt = null;
    _key = null;
    _pollNonce = null;
    _helloNonces.clear();
    _allowedChildKey = null;
    _childSalt = null;
    _adultSalt = null;
    _helloCpk = null;
    notifyListeners();
  }

  void _fail(String? source) {
    if (source != null) {
      // The failure is charged to the source that sent the bad confirmation.
      _use(source).failures += 1;
    }
    attemptsLeft -= 1;
    _pending = null;
    _pendingAt = null;
    if (attemptsLeft <= 0) {
      close();
    } else {
      notifyListeners();
    }
  }

  /// One incoming message. Null means "no answer". Never throws on a malformed message. [source] names where it
  /// came from (a LAN address as the transport sees it); null (the in-process path) is never limited.
  Future<Map<String, dynamic>?> handle(Map<String, dynamic> m, {String? source}) async {
    try {
      return await _handle(m, source);
    } catch (_) {
      return null;
    }
  }

  /// The record for [source], marked most recently used. A new source is always admitted: when the table is full
  /// the least-recently-used entry WITHOUT a failure is dropped (failed sources are at most kWindowMaxAttempts,
  /// far below the table size, so one is always found).
  _SourceUse _use(String source) {
    _SourceUse? u = _sources.remove(source);
    if (u == null) {
      u = _SourceUse();
      if (_sources.length >= kMaxTrackedSources) {
        String? victim;
        for (final MapEntry<String, _SourceUse> e in _sources.entries) {
          if (e.value.failures == 0) {
            victim = e.key;
            break;
          }
        }
        _sources.remove(victim ?? _sources.keys.first);
      }
    }
    _sources[source] = u;
    return u;
  }

  /// Test hook: how many sources the window is tracking right now.
  int get trackedSourceCount => _sources.length;

  /// Takes one unit of [source]'s budget. False = over budget: stay silent.
  bool _spend(String? source, int Function(_SourceUse u) bump, int limit) {
    if (source == null) return true;
    return bump(_use(source)) <= limit;
  }

  bool _blocked(String? source) => source != null && (_sources[source]?.failures ?? 0) >= kSourceMaxFailures;

  Future<Map<String, dynamic>?> _handle(Map<String, dynamic> m, String? source) async {
    if (state == WindowState.closed || state == WindowState.declined) return null;
    if (_expired) {
      close();
      return null;
    }
    if (_blocked(source)) return null;
    final Object? sidRaw = m['sid'];
    final bool sidOk = sidRaw is String && constantTimeEquals(unb64(sidRaw), sid);
    // The advertisement carries a handle, not the session id: a nearby device opens with the handle and learns the
    // session id from the answer. Only the hello may use it.
    final Object? handleRaw = m['h'];
    final bool handleOk = m['t'] == 'hello' && handleRaw is String && constantTimeEquals(unb64(handleRaw), discoveryHandle);
    if (!sidOk && !handleOk) return null;
    switch (m['t']) {
      case 'hello':
        if (state != WindowState.open || !_spend(source, (_SourceUse u) => ++u.hello, kSourceMaxHello)) return null;
        // Version negotiation: the child says the highest version it speaks; this window answers with the highest
        // both speak, or stays silent (an older build then fails calmly: it never receives a version it cannot read).
        final Object? pvRaw = m['pv'];
        if (pvRaw is! int || pvRaw < kMinPairingProtocolVersion) return null;
        final int agreed = pvRaw < kPairingProtocolVersion ? pvRaw : kPairingProtocolVersion;
        if (refuseKey != null && m['cpk'] is String && await refuseKey!(unb64(m['cpk'] as String))) return null;
        // The window id this hello was addressed by: the session id (a QR) or the discovery handle (nearby).
        final Uint8List helloId = sidOk ? sid : discoveryHandle;
        if (_allowedChildKey != null) {
          // Mode B: only the scanned child, and only with proof it holds that key for THIS window. Silent drop.
          final Object? cpkRaw = m['cpk'], hsRaw = m['hs'];
          if (cpkRaw is! String || hsRaw is! String) return null;
          final Uint8List cpk = unb64(cpkRaw);
          if (!constantTimeEquals(cpk, _allowedChildKey!) || !await verifyHello(cpk, helloId, unb64(hsRaw))) return null;
          _helloCpk = cpk;
        }
        Uint8List? hn;
        if (_allowedChildKey != null) {
          // Mode B: hand out a fresh nonce the child must sign in its pake1 (a replayed hello gets one too, but
          // cannot sign it). A few are kept so one stray hello cannot invalidate the real child's.
          hn = _freshNonce();
          _helloNonces.add(hn);
          if (_helloNonces.length > 8) _helloNonces.removeAt(0);
        }
        // Bare on purpose: nothing about the grown-up (no name, family id, key or fingerprint) before the key exchange.
        final Object? helloCpk = m['cpk'];
        Uint8List? ft, fa;
        if (helloCpk is String) {
          final Uint8List c = unb64(helloCpk);
          if (c.length == 32) {
            if (familyKey != null) ft = await familyHelloTag(familyKey!, sid, c);
            fa = await adultHelloTag(adultKey.fingerprint, sid, c);
          }
        }
        return <String, dynamic>{
          't': 'hello-ok', 'pv': agreed, 'sid': b64(sid),
          if (ft != null) 'ft': b64(ft),
          if (fa != null) 'fa': b64(fa),
          if (hn != null) 'hn': b64(hn),
        };
      case 'pake1':
        if (state != WindowState.open) return null;
        if (m['pv'] is! int || (m['pv'] as int) < kMinPairingProtocolVersion) return null; // uncounted, like any junk
        if (refuseKey != null && m['cpk'] is String && await refuseKey!(unb64(m['cpk'] as String))) return null;
        // Mode B: a pake1 from anyone but the scanned, hello-verified child is dropped WITHOUT being counted, so a
        // device that merely photographed the child's picture cannot use up the window's budget.
        if (_allowedChildKey != null) {
          final Object? c = m['cpk'];
          if (c is! String || _helloCpk == null) return null;
          final Uint8List got = unb64(c);
          if (!constantTimeEquals(got, _allowedChildKey!) || !constantTimeEquals(got, _helloCpk!)) return null;
          // ...and it must prove it holds the key NOW: a signature over one of the nonces this window issued.
          final Object? hnRaw = m['hn'], psRaw = m['ps'], ycRaw0 = m['Yc'];
          if (hnRaw is! String || psRaw is! String || ycRaw0 is! String) return null;
          final Uint8List hn = unb64(hnRaw);
          final int at = _helloNonces.indexWhere((Uint8List n) => constantTimeEquals(n, hn));
          if (at < 0 || !await verifyPake1(got, sid, hn, unb64(ycRaw0), unb64(psRaw))) return null;
          _helloNonces.removeAt(at);
        }
        // One claim at a time: a second pake1 while one is mid-handshake is dropped silently and NOT counted, so it
        // can neither replace the first device's exchange nor use up the window's tries. An abandoned claim frees
        // the window after [kClaimTtl].
        if (_pending != null) {
          if (_pendingAt != null && _now().difference(_pendingAt!) < kClaimTtl) return null;
          _pending = null;
          _pendingAt = null;
        }
        // The source's own key-exchange budget (a stranger spends only its own).
        if (!_spend(source, (_SourceUse u) => ++u.pake1, kSourceMaxPake1)) return null;
        // Only a well-formed share counts toward the cap, so junk cannot silently use the window up.
        final Object? cpkRaw = m['cpk'], ycRaw = m['Yc'];
        if (cpkRaw is! String || ycRaw is! String) return null;
        final Uint8List cpk = unb64(cpkRaw), yc = unb64(ycRaw);
        if (cpk.length != 32 || yc.length != 32) return null;
        if (++_pake1Count > _kMaxPake1PerWindow) return null;
        final bool qr = m['m'] == 'qr';
        final List<int>? password = qr
            ? (qrSecret == null ? null : utf8.encode(b64(qrSecret!)))
            : (_pin == null ? null : utf8.encode(_pin!));
        if (password == null) return null;
        final PakeParty party =
            await PakeParty.start(isChild: false, password: password, sid: sid, ci: _channelId(cpk, bindAdult: m['fb'] == 1));
        _pending = _Pending(party, cpk, _clip(m['dn']), qr, yc);
        _pendingAt = _now();
        return <String, dynamic>{'t': 'pake2', 'Ya': b64(party.share)};
      case 'confirm':
        final _Pending? p = _pending;
        if (state != WindowState.open || p == null) return null;
        _pending = null;
        _pendingAt = null;
        final bool wasQr = p.qr;
        PakeKey? key;
        try {
          key = await p.party.finish(p.yc);
        } on PakeException {
          key = null;
        }
        final Uint8List tagC = unb64(m['tagC'] as String);
        if (key == null || !await key.checkTag('C', tagC)) {
          _fail(source);
          return <String, dynamic>{'t': 'confirm-no'};
        }
        if (wasQr) qrSecret = null; // one use: spent only by a CONFIRMED exchange (a wrong guess costs an attempt)
        _key = key;
        _cpk = p.cpk;
        _deviceName = p.deviceName;
        _tagC = tagC;
        sas = Sas.fromBytes(await key.sas());
        _matchReal = MatchSet.fromBytes(await key.match());
        matchChoices = buildMatchChoices(_matchReal!, _random);
        state = WindowState.awaitingApproval;
        notifyListeners();
        _pollNonce = _freshNonce();
        return <String, dynamic>{
          't': 'confirm-ok', 'tagA': b64(await key.tag('A')), 'n': b64(_pollNonce!), 'id': b64(await _sealedIdentity(key)),
        };
      case 'poll':
        final Object? tc = m['tagC'], tp = m['tagP'];
        if (_tagC == null || _key == null || _pollNonce == null || tc is! String || tp is! String) return null;
        if (!constantTimeEquals(unb64(tc), _tagC!)) return null;
        // tagC crosses the LAN in the clear, so it is not proof. The poll must also carry a MAC over a one-use nonce
        // only the real child can compute; the nonce is replaced on every good poll, so a sniffed poll cannot be replayed.
        if (!await _key!.checkTag(pollRole(_pollNonce!), unb64(tp))) return null;
        _pollNonce = _freshNonce();
        if (state == WindowState.awaitingApproval) return <String, dynamic>{'t': 'wait', 'n': b64(_pollNonce!)};
        if (state == WindowState.approved) {
          final Uint8List sealed = _sealed!;
          close(); // a credential is handed over once, and only to a device that proved it holds the key
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
    if (requireMatch && !matchConfirmed) return false;
    final Random r = Random.secure();
    final String certId = b64(List<int>.generate(12, (_) => r.nextInt(256)));
    final int iat = _now().millisecondsSinceEpoch;
    final PairingCert cert = await PairingCert.issue(adultKey,
        childDeviceKey: _cpk!, familyId: familyId, childId: childId, certId: certId, issuedAtMs: iat,
        expiresAtMs: iat + kCertLifetime.inMilliseconds);
    final LocalPinRecord? verifier = phoneOnly ? null : await makeUnlockVerifier(_pin ?? '');
    final Map<String, Object?> body = <String, Object?>{
      'cert': cert.toJson(), 'apk': b64(adultKey.publicKey), 'an': adultName, 'childName': childName,
      if (verifier != null) 'verifier': <String, Object?>{'iter': verifier.iterations, 'salt': b64(verifier.salt), 'hash': b64(verifier.hash)},
      if (phoneOnly) 'po': true,
      if (familyKey != null) 'fk': b64(familyKey!),
    };
    final AesGcm aes = AesGcm.with256bits();
    final SecretBox box =
        await aes.encrypt(utf8.encode(jsonEncode(body)), secretKey: SecretKey(await _key!.channelKey()), aad: _aadCredential);
    _sealed = Uint8List.fromList(box.concatenation());
    state = WindowState.approved;
    onPaired?.call(PairedKid(certId: certId, childDeviceKey: _cpk!, childId: childId, deviceName: _deviceName, issuedAtMs: iat, phoneOnly: phoneOnly));
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
    this.familyKey, this.graceUntilMs,
  });
  final PairingCert cert;
  final Uint8List adultKey;
  final String adultName, childName;

  /// Null on a phone-only tablet: it holds no PIN verifier at all.
  final LocalPinRecord? unlockVerifier;

  /// The family key from the sealed credential (null for a credential issued before pairing pictures existed).
  final Uint8List? familyKey;

  /// Only the grown-up's phone unlocks this tablet.
  bool get phoneOnly => unlockVerifier == null;

  /// For a certificate with no signed end date (issued before expiry existed): the time, on this tablet's clock, by
  /// which it must meet the grown-up's phone once. Set by the store the first time the new build loads the record.
  final int? graceUntilMs;

  /// When this pairing stops being honoured: the signed end date, or the legacy grace for an old certificate.
  int? get effectiveExpiryMs => cert.expiresAtMs ?? graceUntilMs;

  /// True once the end date has passed on [nowMs] (this tablet's clock; a tablet whose clock is set back is "good" for
  /// longer, which is the honest limit). A lapsed pairing stops admitting play and stops accepting a typed code; the
  /// grown-up's phone still unlocks it, and meeting the phone renews it. Nothing is erased and a child sees nothing.
  bool isLapsed(int nowMs) {
    final int? e = effectiveExpiryMs;
    return e != null && nowMs >= e;
  }

  ChildPairing withCert(PairingCert c) => ChildPairing(
      cert: c, adultKey: adultKey, adultName: adultName, childName: childName, unlockVerifier: unlockVerifier,
      familyKey: familyKey, graceUntilMs: graceUntilMs);
}

enum PairingFailure { unreachable, notMatched, declined, timedOut, malformed, versionMismatch }

class PairingResult {
  const PairingResult.ok(ChildPairing this.pairing) : failure = null;
  const PairingResult.failed(PairingFailure this.failure) : pairing = null;
  final ChildPairing? pairing;
  final PairingFailure? failure;
  bool get ok => pairing != null;
}

/// What the child's screen shows (picture first) once the adult device passed confirmation.
class PairingMatch {
  const PairingMatch(this.adultName, this.sas, [this.match]);
  final String adultName;
  final Sas sas;

  /// The three pictures and the colour the child's screen shows for the adult to pick (no words).
  final MatchSet? match;
}

/// The role string a poll proof is made under: binds the tag to the adult's current one-use nonce.
String pollRole(List<int> nonce) => 'P${b64(nonce)}';

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

  /// Runs the whole exchange. The window is named by exactly one of [sid] (from the QR) or [handle] (from the
  /// neutral advertisement: the session id then comes back in the hello answer);
  /// [password] is the typed PIN or the QR secret ([viaQr]); [expectedAdultFingerprint] comes from the QR.
  /// [onMatched] fires when the adult device proved it knows the secret: show the name and the pair.
  /// A foreign family is stopped BEFORE any key exchange only when [expectedFamilyKey] is given (the blinded hint needs
  /// it); [expectedFamilyId] alone is checked after key confirmation, so a caller that holds an id must pass the key too.
  Future<PairingResult> pair({
    Uint8List? sid,
    Uint8List? handle,
    required String password,
    bool viaQr = false,
    Uint8List? expectedAdultFingerprint,
    String? expectedFamilyId,
    Uint8List? expectedFamilyKey,
    void Function(PairingMatch match)? onMatched,
  }) async {
    if ((sid == null) == (handle == null)) {
      throw ArgumentError('pair() needs exactly one of sid (from a QR) or handle (from discovery)');
    }
    try {
      final Map<String, dynamic>? hello = await transport.send(<String, dynamic>{
        't': 'hello', 'pv': kPairingProtocolVersion,
        if (sid != null) 'sid': b64(sid) else 'h': b64(handle!), 'cpk': b64(childKey.publicKey), 'dn': deviceName,
        // Proof this device holds the key it presents, for this window only (checked by a window that scanned
        // this device's picture; ignored by every other). Signed over whichever window id the hello carries.
        'hs': b64(await signHello(childKey, sid ?? handle!)),
      });
      if (hello == null || hello['t'] != 'hello-ok') return const PairingResult.failed(PairingFailure.unreachable);
      // A version 1 window answers with no version at all (and with the grown-up's details in the clear, which are
      // ignored here): stop calmly.
      final Object? pv = hello['pv'];
      if (pv is! int || pv < kMinPairingProtocolVersion || pv > kPairingProtocolVersion) {
        return const PairingResult.failed(PairingFailure.versionMismatch);
      }
      if (sid == null) {
        // Found by handle: the session id is whatever the window that answered says it is. It is a nonce, not a
        // secret; the channel identifier below binds it into the key exchange either way.
        final Uint8List got = unb64(hello['sid'] as String);
        if (got.length != 16) return const PairingResult.failed(PairingFailure.malformed);
        sid = got;
      }
      // A device that already belongs to a family (it holds the family key) never starts an exchange with a window that
      // cannot show it is the same family, and it does not accept a window with the hint removed: it stops here,
      // before any key-exchange message is sent, and says nothing.
      if (expectedFamilyKey != null) {
        final Object? ft = hello['ft'];
        final Uint8List want = await familyHelloTag(expectedFamilyKey, sid, childKey.publicKey);
        if (ft is! String || !constantTimeEquals(unb64(ft), want)) return const PairingResult.failed(PairingFailure.notMatched);
      }
      // A child that already knows which grown-up it is looking for (a QR or a scanned picture) stops here if this
      // window is not that grown-up, before any key exchange, and the real grown-up is never involved.
      if (expectedAdultFingerprint != null) {
        final Object? fa = hello['fa'];
        final Uint8List want = await adultHelloTag(expectedAdultFingerprint, sid, childKey.publicKey);
        if (fa is! String || !constantTimeEquals(unb64(fa), want)) return const PairingResult.failed(PairingFailure.notMatched);
      }
      final Object? hnRaw = hello['hn'];
      // The adult's fingerprint is bound into the exchange only when this device already knows it from outside the
      // network (a QR or a scanned picture); otherwise the adult is identified after key confirmation, below.
      final Uint8List ci = pairingChannelId(sid, childKey.publicKey, expectedAdultFingerprint);
      final PakeParty party = await PakeParty.start(isChild: true, password: utf8.encode(password), sid: sid, ci: ci);
      final Map<String, dynamic>? p2 = await transport.send(<String, dynamic>{
        't': 'pake1', 'pv': kPairingProtocolVersion, 'sid': b64(sid), 'cpk': b64(childKey.publicKey), 'dn': deviceName,
        'm': viaQr ? 'qr' : 'pin', 'Yc': b64(party.share), 'fb': expectedAdultFingerprint != null ? 1 : 0,
        // Only a window that scanned this device's picture issues a nonce; the signature proves the key is held now.
        if (hnRaw is String) ...<String, dynamic>{
          'hn': hnRaw, 'ps': b64(await signPake1(childKey, sid, unb64(hnRaw), party.share)),
        },
      });
      if (p2 == null || p2['t'] != 'pake2') return const PairingResult.failed(PairingFailure.notMatched);
      final PakeKey key = await party.finish(unb64(p2['Ya'] as String));
      final Uint8List tagC = await key.tag('C');
      final Map<String, dynamic>? c = await transport.send(<String, dynamic>{'t': 'confirm', 'sid': b64(sid), 'tagC': b64(tagC)});
      if (c == null || c['t'] != 'confirm-ok') return const PairingResult.failed(PairingFailure.notMatched);
      if (!await key.checkTag('A', unb64(c['tagA'] as String))) return const PairingResult.failed(PairingFailure.notMatched);
      // Who the adult is: opened only with the key just confirmed, and checked before anything is shown or polled.
      final Map<String, dynamic> who = await _openIdentity(key, c['id'] as String);
      final Uint8List apk = unb64(who['apk'] as String), afp = await fingerprintOf(apk);
      final String an = who['an'] as String, fid = who['fid'] as String;
      if (expectedAdultFingerprint != null && !constantTimeEquals(expectedAdultFingerprint, afp)) {
        return const PairingResult.failed(PairingFailure.notMatched);
      }
      if (expectedFamilyId != null && fid != expectedFamilyId) return const PairingResult.failed(PairingFailure.notMatched);
      onMatched?.call(PairingMatch(an, Sas.fromBytes(await key.sas()), MatchSet.fromBytes(await key.match())));
      Duration waited = Duration.zero;
      Uint8List nonce = unb64(c['n'] as String);
      while (waited <= giveUpAfter) {
        final Map<String, dynamic>? r = await transport.send(<String, dynamic>{
          't': 'poll', 'sid': b64(sid), 'tagC': b64(tagC), 'tagP': b64(await key.tag(pollRole(nonce))),
        });
        if (r == null) return const PairingResult.failed(PairingFailure.declined);
        if (r['t'] == 'approved') return _open(await _decrypt(key, r['sealed'] as String), apk, afp, fid);
        nonce = unb64(r['n'] as String);
        await _delay(pollEvery);
        waited += pollEvery;
      }
      return const PairingResult.failed(PairingFailure.timedOut);
    } catch (_) {
      return const PairingResult.failed(PairingFailure.malformed);
    }
  }

  Future<Map<String, dynamic>> _decrypt(PakeKey key, String sealed) => _open2(key, sealed, _aadCredential);

  Future<Map<String, dynamic>> _openIdentity(PakeKey key, String sealed) => _open2(key, sealed, _aadIdentity);

  Future<Map<String, dynamic>> _open2(PakeKey key, String sealed, List<int> aad) async {
    final SecretBox box = SecretBox.fromConcatenation(unb64(sealed), nonceLength: 12, macLength: 16);
    final List<int> plain = await AesGcm.with256bits().decrypt(box, secretKey: SecretKey(await key.channelKey()), aad: aad);
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
    // A tablet is either given a verifier or told it is phone-only; a credential with neither is refused.
    if (verifier == null && body['po'] != true) return const PairingResult.failed(PairingFailure.malformed);
    final Object? fk = body['fk'];
    Uint8List? familyKey;
    if (fk is String) {
      final Uint8List raw = unb64(fk);
      if (raw.length == kFamilyKeyBytes) familyKey = raw;
    }
    return PairingResult.ok(ChildPairing(
        cert: cert, adultKey: apk, adultName: body['an'] as String, childName: body['childName'] as String,
        unlockVerifier: verifier, familyKey: familyKey));
  }
}
