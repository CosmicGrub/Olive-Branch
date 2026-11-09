// OLIVE BRANCH — admission for ad-hoc PLAY sessions: who may post a turn to this device, and what a stranger on
// the same Wi-Fi can and cannot do. UNVERIFIED on a device (the mDNS half needs two real devices); the logic and
// the HTTP half run headless in CI (client/test/play_admission_test.dart).
// Research: docs/superpowers/research/gamesuite-multiplayer-for-play-together.md section 5.2 (adoption 2).
//
// WHAT WAS WRONG. local_session.dart accepted a turn from ANY device on the LAN, read an unbounded body, and
// local_discovery.dart broadcast the CHILD'S NAME to the whole network. A shared Wi-Fi (a grandparent's block, a
// hotel, a school) is a normal setting for this app.
//
// WHAT THIS LAYER DOES (admission and auth only; message formats belong to the play envelope):
//  - A neutral mDNS label (`olive-<4 hex>`), no name, no device model (play_admission + local_discovery.dart).
//  - Only a device that holds the pairing credential from the adult gate work (device_keys.dart: the adult
//    device's key pinned on the child device, the child device's key listed on the adult device) can open a
//    session. `POST /hello` carries an ephemeral X25519 key signed with that device key; the answer is signed with
//    the other pinned key; both derive a per-session key (HKDF over the shared secret). A stranger holds neither
//    pinned key, so cannot sign, so cannot open a session.
//  - The session is open only while a "lobby" window is open ([PlayAdmission.openWindow]) and holds one peer.
//  - On the GROWN-UP's device the FIRST connection of a peer waits for a plain-words confirmation showing the same
//    word and picture on both screens; the child's device never asks (the pinned adult is its authority). A
//    confirmed peer is remembered ([PlayAdmission.confirmedFingerprints]) so later sessions skip the tap.
//  - Every turn carries a counter and an HMAC under the session key over the raw body; the server checks it in
//    constant time, requires a strictly higher counter (replay), pins the sender's address to the one that said
//    hello, and caps the body ([kMaxTurnBytes], 413).
//  - Any peer-supplied text shown to a person goes through [sanitizePeerText].
//
// HONEST LIMITS. The turns themselves are still cleartext on the LAN (authenticated, not encrypted): a passive
// listener on the same Wi-Fi can read a game move but cannot forge or replay one. A device that was never paired
// (two unrelated families meeting) cannot play through this layer; that needs the pairing of the adult gate work
// first. The grown-up confirmation card ([PlayConfirmCard]) is built and tested but is NOT wired into the pairing
// controller here, to leave local_pairing.dart to the play-envelope work; until it is wired a first connection
// from an unconfirmed peer is held, never silently admitted.
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import 'cpace.dart' show cat, lv;
import 'device_keys.dart';
import 'local_pin.dart' show constantTimeEquals;
import 'pairing_protocol.dart' show PairedKid, Sas;

/// The most a turn body may be. Games send tiny JSON; this stops memory exhaustion from a hostile or broken peer.
const int kMaxTurnBytes = 64 * 1024;

const String kNeutralPeerName = 'Someone nearby';

/// A random neutral mDNS label: `olive-` and four hex characters. Carries no name and no model.
String neutralServiceName([Random? random]) {
  final Random r = random ?? Random.secure();
  return 'olive-${List<int>.generate(2, (_) => r.nextInt(256)).map((int b) => b.toRadixString(16).padLeft(2, '0')).join()}';
}

/// Makes text from a peer safe to show: strips control characters, bidirectional and zero-width marks, collapses
/// whitespace, limits length (by characters, not bytes). Empty after cleaning becomes [kNeutralPeerName].
String sanitizePeerText(String? raw, {int max = 24}) {
  if (raw == null) return kNeutralPeerName;
  final StringBuffer b = StringBuffer();
  for (final int c in raw.runes) {
    final bool control = c < 0x20 || (c >= 0x7f && c <= 0x9f);
    final bool bidi = (c >= 0x202a && c <= 0x202e) || (c >= 0x2066 && c <= 0x2069) || c == 0x200e || c == 0x200f || c == 0x061c;
    final bool invisible = (c >= 0x200b && c <= 0x200d) || c == 0x2060 || c == 0xfeff || c == 0x2028 || c == 0x2029;
    if (control || bidi || invisible) {
      b.write(' ');
    } else {
      b.writeCharCode(c);
    }
  }
  final String cleaned = b.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  if (cleaned.isEmpty) return kNeutralPeerName;
  final List<int> runes = cleaned.runes.toList();
  return runes.length <= max ? cleaned : String.fromCharCodes(runes.take(max)).trimRight();
}

enum PlayState { none, awaitingConfirm, admitted }

Uint8List _helloBytes(List<int> sid, List<int> epk, List<int> fp) =>
    cat(<List<int>>[lv(utf8.encode('olive-play-hello-v1')), lv(sid), lv(epk), lv(fp)]);

Uint8List _ackBytes(List<int> sid, List<int> epk, List<int> epk2, List<int> fp) =>
    cat(<List<int>>[lv(utf8.encode('olive-play-ack-v1')), lv(sid), lv(epk), lv(epk2), lv(fp)]);

Future<Uint8List> _sessionKey(SimpleKeyPair mine, List<int> theirPublic, List<int> sid) async {
  final SecretKey shared = await X25519().sharedSecretKey(
      keyPair: mine, remotePublicKey: SimplePublicKey(theirPublic, type: KeyPairType.x25519));
  final SecretKey k = await Hkdf(hmac: Hmac.sha256(), outputLength: 32)
      .deriveKey(secretKey: shared, nonce: sid, info: utf8.encode('olive-play-session-v1'));
  return Uint8List.fromList(await k.extractBytes());
}

Future<Uint8List> _mac(List<int> key, List<int> sid, int seq, List<int> body) async {
  final Mac m = await Hmac.sha256().calculateMac(
      cat(<List<int>>[lv(utf8.encode('olive-play-turn-v1')), lv(sid), lv(utf8.encode('$seq')), body]),
      secretKey: SecretKey(key));
  return Uint8List.fromList(m.bytes);
}

/// The receiving side. One per device that runs a [LocalSessionServer] for play.
class PlayAdmission extends ChangeNotifier {
  PlayAdmission({
    required this.own,
    required this.peerKeys,
    required this.requireConfirm,
    Set<String>? confirmedFingerprints,
    this.onConfirmed,
  }) : confirmedFingerprints = confirmedFingerprints ?? <String>{};

  /// The adult device: its pinned peers are the child devices it paired ([PairedKid.childDeviceKey]).
  static PlayAdmission forAdult(DeviceKey own, List<PairedKid> kids, {void Function(String fp)? onConfirmed, Set<String>? confirmed}) =>
      PlayAdmission(
          own: own, peerKeys: <Uint8List>[for (final PairedKid k in kids) k.childDeviceKey],
          requireConfirm: true, confirmedFingerprints: confirmed, onConfirmed: onConfirmed);

  /// The child device: its one pinned peer is the adult key it was paired with. It never asks for a confirmation.
  static PlayAdmission forChild(DeviceKey own, Uint8List adultKey) =>
      PlayAdmission(own: own, peerKeys: <Uint8List>[adultKey], requireConfirm: false);

  final DeviceKey own;
  final List<Uint8List> peerKeys;
  final bool requireConfirm;
  final Set<String> confirmedFingerprints;
  final void Function(String fingerprint)? onConfirmed;

  bool _windowOpen = false;
  PlayState _state = PlayState.none;
  Uint8List? _sid, _key, _peerKey;
  String? _remote;
  int _lastSeq = 0;
  Sas? sas;
  final List<String> _seenSids = <String>[];

  bool get windowOpen => _windowOpen;
  PlayState get state => _state;
  bool get admitted => _state == PlayState.admitted;

  /// The lobby is open: a paired peer may say hello. Closed: every hello gets silence.
  void openWindow() {
    _windowOpen = true;
    notifyListeners();
  }

  void closeWindow() {
    _windowOpen = false;
    _reset();
    notifyListeners();
  }

  void _reset() {
    _state = PlayState.none;
    _sid = _key = _peerKey = null;
    _remote = null;
    _lastSeq = 0;
    sas = null;
  }

  /// `POST /hello`. Null = no answer (a stranger, a closed lobby, a taken seat and a replay are all silence).
  Future<Map<String, dynamic>?> handleHello(Map<String, dynamic> m, String? remote) async {
    try {
      if (!_windowOpen) return null;
      final Uint8List sid = unb64(m['sid'] as String), epk = unb64(m['epk'] as String);
      final Uint8List fp = unb64(m['fp'] as String), sig = unb64(m['sig'] as String);
      if (sid.length != 16 || epk.length != 32 || fp.length != 16) return null;
      Uint8List? peer;
      for (final Uint8List k in peerKeys) {
        if (constantTimeEquals(await fingerprintOf(k), fp)) peer = k;
      }
      if (peer == null) return null;
      if (!await DeviceKey.verify(peer, _helloBytes(sid, epk, fp), sig)) return null;
      final String sidText = b64(sid);
      if (_seenSids.contains(sidText)) return null; // a replayed hello
      // One seat: a different peer cannot displace the one we hold; the same peer may start again.
      if (_peerKey != null && !constantTimeEquals(_peerKey!, peer)) return null;
      _seenSids.add(sidText);
      if (_seenSids.length > 64) _seenSids.removeAt(0);

      final SimpleKeyPair eph = await X25519().newKeyPair();
      final Uint8List epk2 = Uint8List.fromList((await eph.extractPublicKey()).bytes);
      final Uint8List key = await _sessionKey(eph, epk, sid);
      final String peerFp = b64(fp);
      _sid = sid;
      _key = key;
      _peerKey = peer;
      _remote = remote;
      _lastSeq = 0;
      final Mac s = await Hmac.sha256().calculateMac(utf8.encode('olive-play-sas'), secretKey: SecretKey(key));
      sas = Sas.fromBytes(s.bytes);
      _state = (!requireConfirm || confirmedFingerprints.contains(peerFp)) ? PlayState.admitted : PlayState.awaitingConfirm;
      notifyListeners();
      final Uint8List ownFp = own.fingerprint;
      return <String, dynamic>{
        't': 'hello-ok', 'epk': b64(epk2), 'fp': b64(ownFp),
        'sig': b64(await own.sign(_ackBytes(sid, epk, epk2, ownFp))),
      };
    } catch (_) {
      return null;
    }
  }

  /// The grown-up said yes ("same word and picture"). Remembers the peer so the next session skips this.
  void confirm() {
    if (_state != PlayState.awaitingConfirm || _peerKey == null) return;
    // Computed lazily: the fingerprint of the peer we hold.
    unawaited(fingerprintOf(_peerKey!).then((Uint8List fp) {
      final String t = b64(fp);
      confirmedFingerprints.add(t);
      onConfirmed?.call(t);
    }));
    _state = PlayState.admitted;
    notifyListeners();
  }

  void decline() {
    if (_state == PlayState.none) return;
    _reset();
    notifyListeners();
  }

  /// Checks one `POST /turn`. True only for an admitted session, the pinned address, a strictly higher counter and a
  /// correct MAC over exactly these body bytes.
  Future<bool> authorizeTurn({
    required String? sid,
    required String? seq,
    required String? mac,
    required List<int> body,
    required String? remote,
  }) async {
    try {
      if (_state != PlayState.admitted || _key == null || _sid == null) return false;
      if (sid == null || seq == null || mac == null) return false;
      if (remote == null || remote != _remote) return false;
      if (!constantTimeEquals(unb64(sid), _sid!)) return false;
      final int? n = int.tryParse(seq);
      if (n == null || n <= _lastSeq) return false;
      final Uint8List want = await _mac(_key!, _sid!, n, body);
      if (!constantTimeEquals(unb64(mac), want)) return false;
      _lastSeq = n;
      return true;
    } catch (_) {
      return false;
    }
  }
}

/// The sending side's session, once a hello succeeded.
class PlaySession {
  PlaySession._(this._sid, this._key, this.sas);
  final Uint8List _sid, _key;

  /// The same word and picture the receiving grown-up's screen shows.
  final Sas sas;
  int _seq = 0;

  /// Headers to send with a turn whose raw body is [body]. A new counter each time.
  Future<Map<String, String>> headersFor(List<int> body) async {
    final int n = ++_seq;
    return <String, String>{
      'x-olive-sid': b64(_sid), 'x-olive-seq': '$n', 'x-olive-mac': b64(await _mac(_key, _sid, n, body)),
    };
  }

  /// Opens a session with the peer holding [peerKey] by exchanging hello through [post] (one POST of JSON, answer
  /// or null). Null if the peer does not answer, or answers with anything not signed by [peerKey].
  static Future<PlaySession?> hello({
    required DeviceKey own,
    required Uint8List peerKey,
    required Future<Map<String, dynamic>?> Function(Map<String, dynamic> body) post,
    Random? random,
  }) async {
    try {
      final Random r = random ?? Random.secure();
      final Uint8List sid = Uint8List.fromList(List<int>.generate(16, (_) => r.nextInt(256)));
      final SimpleKeyPair eph = await X25519().newKeyPair();
      final Uint8List epk = Uint8List.fromList((await eph.extractPublicKey()).bytes);
      final Map<String, dynamic>? a = await post(<String, dynamic>{
        't': 'hello', 'sid': b64(sid), 'epk': b64(epk), 'fp': b64(own.fingerprint),
        'sig': b64(await own.sign(_helloBytes(sid, epk, own.fingerprint))),
      });
      if (a == null || a['t'] != 'hello-ok') return null;
      final Uint8List epk2 = unb64(a['epk'] as String), fp = unb64(a['fp'] as String), sig = unb64(a['sig'] as String);
      if (epk2.length != 32 || !constantTimeEquals(fp, await fingerprintOf(peerKey))) return null;
      if (!await DeviceKey.verify(peerKey, _ackBytes(sid, epk, epk2, fp), sig)) return null;
      final Uint8List key = await _sessionKey(eph, epk2, sid);
      final Mac s = await Hmac.sha256().calculateMac(utf8.encode('olive-play-sas'), secretKey: SecretKey(key));
      return PlaySession._(sid, key, Sas.fromBytes(s.bytes));
    } catch (_) {
      return null;
    }
  }
}
