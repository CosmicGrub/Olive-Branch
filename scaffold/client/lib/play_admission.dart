// OLIVE BRANCH — admission for ad-hoc PLAY sessions: who may send a turn to this device, and what a stranger on the
// same Wi-Fi can and cannot learn or do. UNVERIFIED on a device (the mDNS half needs two real devices); the logic and
// the HTTP half run headless in CI (client/test/play_admission_test.dart, play_frame_test.dart).
// Research: docs/superpowers/research/gamesuite-multiplayer-for-play-together.md section 5.2.
//
// OWNER REQUIREMENTS (2026-11-08): "the mdns names [display] only as player one and player two so that nothing at all
// identifying is displayed", and "security against those that may try to peek into the games".
//
// WHAT A STRANGER CAN SEE (and nothing else): that some app advertises a service of a generic type; a seat label
// ("Player one" or "Player two"); a random per-lobby key that changes every time a lobby opens; that two devices
// exchange fixed-size-bucket, encrypted blobs. No child or grown-up name, no device model or name, no family, child or
// device id, no stable fingerprint (the hello is sealed, so device keys do not cross the wire in the clear), and no
// game content (every turn is encrypted and padded, so not even which card or move is guessable from its size).
//
// HOW IT WORKS.
//  - Opening a lobby makes a fresh X25519 "lobby key" (random, not derived from any identity). Its public half is
//    the per-session token in the mDNS TXT record; it is what tells two nearby lobbies apart, never a name.
//  - A device that holds the pairing credential from the adult gate work (device_keys.dart) says hello: a fresh
//    ephemeral key plus a sealed blob (ChaCha20-Poly1305 under a key from DH(ephemeral, lobby key)) holding the
//    session id, its device fingerprint and a signature with its device key. The lobby opens it with its lobby secret,
//    checks the fingerprint is a pinned peer and the signature verifies, and answers sealed with ITS ephemeral key, its
//    fingerprint and its signature. The client checks that against the key it pinned. A stranger holds neither pinned
//    key, so cannot sign, and a passive listener sees only ephemeral keys and ciphertext.
//  - Session keys (one per direction, one for the confirmation picture) come from HKDF over both Diffie-Hellman
//    results (play_frame.dart). Every turn is one encrypted, padded, counter-numbered frame; the receiver requires a
//    strictly rising counter (replay and reorder fail), pins the sender's address to the one that said hello, and caps
//    the body ([kMaxTurnBytes], 413).
//  - The lobby is open for a short window, holds one peer, and on the GROWN-UP's device the first connection of a peer
//    waits for a plain-words confirmation ("Player two wants to join", the same word and picture on both screens). The
//    child's device never asks. A confirmed peer is remembered so later sessions skip the tap.
//
// HONEST LIMITS. That a Olive-family app is advertising on the network is unavoidably observable (any mDNS service is).
// Seat labels are random per lobby and settled by a tie-break, so a label says nothing about who holds it. A device
// that was never paired cannot play through this layer. Traffic analysis can still see that two devices exchange
// messages of the padded sizes and roughly when. This is a composition of standard primitives (X25519, Ed25519,
// HKDF, ChaCha20-Poly1305), not a new primitive, but the composition itself has not had outside review. The
// confirm card is built and tested but not yet wired into the pairing controller (that file belongs to the play-envelope
// work). Not run on two real devices.
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import 'cpace.dart' show cat, lv;
import 'device_keys.dart';
import 'local_pin.dart' show constantTimeEquals;
import 'pairing_protocol.dart' show PairedKid, Sas;
import 'play_frame.dart';

/// The most a request body may be (413 above it, even when no admission is configured).
const int kMaxTurnBytes = 64 * 1024;

/// How long a lobby accepts a hello.
const Duration kLobbyWindow = Duration(minutes: 10);

/// Seat labels are the ONLY text a peer is ever shown or sent.
String seatLabel(int seat) => switch (seat) { 1 => 'Player one', 2 => 'Player two', _ => 'Player $seat' };

/// A seat number read from an untrusted TXT value; null unless it is a plain digit 1 to 8.
int? parseSeat(String? raw) {
  final int? n = raw == null ? null : int.tryParse(raw);
  return (n != null && n >= 1 && n <= 8 && '$n' == raw) ? n : null;
}

const String kNeutralPeerName = 'Player';

/// Random seat for a new lobby (1 or 2). Two devices may pick the same one; [seatAfterClash] settles it.
int randomSeat([Random? random]) => 1 + (random ?? Random.secure()).nextInt(2);

/// If a nearby lobby shows the same seat as ours, exactly one of the two devices flips: the one with the smaller lobby
/// token. Neither learns anything about the other.
int seatAfterClash({required int mySeat, required String myToken, required int peerSeat, required String peerToken}) {
  if (mySeat != peerSeat) return mySeat;
  return myToken.compareTo(peerToken) < 0 ? (mySeat == 1 ? 2 : 1) : mySeat;
}

/// Makes any text from a peer safe to show: strips control, bidi and zero-width characters, collapses whitespace,
/// limits length by characters. Peer text is not shown at all in play (only [seatLabel]); this stays as a guard.
String sanitizePeerText(String? raw, {int max = 24}) {
  if (raw == null) return kNeutralPeerName;
  final StringBuffer b = StringBuffer();
  for (final int c in raw.runes) {
    final bool control = c < 0x20 || (c >= 0x7f && c <= 0x9f);
    final bool bidi = (c >= 0x202a && c <= 0x202e) || (c >= 0x2066 && c <= 0x2069) || c == 0x200e || c == 0x200f || c == 0x061c;
    final bool invisible = (c >= 0x200b && c <= 0x200d) || c == 0x2060 || c == 0xfeff || c == 0x2028 || c == 0x2029;
    b.write(control || bidi || invisible ? ' ' : String.fromCharCode(c));
  }
  final String cleaned = b.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  if (cleaned.isEmpty) return kNeutralPeerName;
  final List<int> runes = cleaned.runes.toList();
  return runes.length <= max ? cleaned : String.fromCharCodes(runes.take(max)).trimRight();
}

enum PlayState { none, awaitingConfirm, admitted }

Uint8List _helloSig(List<int> sid, List<int> epk, List<int> lobbyKey, List<int> fp) =>
    cat(<List<int>>[lv('olive-play-hello-v2'.codeUnits), lv(sid), lv(epk), lv(lobbyKey), lv(fp)]);

Uint8List _ackSig(List<int> sid, List<int> epk, List<int> lobbyKey, List<int> epk2, List<int> fp) =>
    cat(<List<int>>[lv('olive-play-ack-v2'.codeUnits), lv(sid), lv(epk), lv(lobbyKey), lv(epk2), lv(fp)]);

Uint8List _helloAad(List<int> lobbyKey, List<int> epk) => cat(<List<int>>[lv(lobbyKey), lv(epk)]);

Future<Uint8List> _dh(SimpleKeyPair mine, List<int> theirs) async {
  final SecretKey s = await X25519().sharedSecretKey(
      keyPair: mine, remotePublicKey: SimplePublicKey(theirs, type: KeyPairType.x25519));
  return Uint8List.fromList(await s.extractBytes());
}

Sas _sasFrom(List<int> sasKey) => Sas.fromBytes(sasKey);

/// The receiving side. One per device that runs a [LocalSessionServer] for play.
class PlayAdmission extends ChangeNotifier {
  PlayAdmission({
    required this.own,
    required this.peerKeys,
    required this.requireConfirm,
    Set<String>? confirmedFingerprints,
    this.onConfirmed,
    DateTime Function()? now,
  })  : confirmedFingerprints = confirmedFingerprints ?? <String>{},
        _now = now ?? DateTime.now;

  /// The adult device: its pinned peers are the child devices it paired ([PairedKid.childDeviceKey]).
  static PlayAdmission forAdult(DeviceKey own, List<PairedKid> kids,
          {void Function(String fp)? onConfirmed, Set<String>? confirmed, DateTime Function()? now}) =>
      PlayAdmission(
          own: own, peerKeys: <Uint8List>[for (final PairedKid k in kids) k.childDeviceKey],
          requireConfirm: true, confirmedFingerprints: confirmed, onConfirmed: onConfirmed, now: now);

  /// The child device: its one pinned peer is the adult key it was paired with. It never asks for a confirmation.
  static PlayAdmission forChild(DeviceKey own, Uint8List adultKey, {DateTime Function()? now}) =>
      PlayAdmission(own: own, peerKeys: <Uint8List>[adultKey], requireConfirm: false, now: now);

  final DeviceKey own;
  final List<Uint8List> peerKeys;
  final bool requireConfirm;
  final Set<String> confirmedFingerprints;
  final void Function(String fingerprint)? onConfirmed;
  final DateTime Function() _now;

  SimpleKeyPair? _lobby;
  Uint8List? _lobbyKey;
  DateTime? _lobbyUntil;
  PlayState _state = PlayState.none;
  Uint8List? _sid, _keyIn, _peerKey;
  String? _remote;
  int _lastSeq = 0;
  Sas? sas;
  final List<String> _seenSids = <String>[];

  /// The per-lobby token for the mDNS TXT record (the lobby's public key): random, rotates every lobby, derived from
  /// no identity. Null while the lobby is closed.
  String? get lobbyToken => _lobbyKey == null ? null : b64(_lobbyKey!);
  bool get windowOpen => _lobby != null && (_lobbyUntil?.isAfter(_now()) ?? false);
  PlayState get state => _state;
  bool get admitted => _state == PlayState.admitted;

  /// Opens a lobby: a fresh lobby key, accepted for [kLobbyWindow]. Reopening rotates the key and drops any session.
  Future<void> openWindow({Duration ttl = kLobbyWindow}) async {
    final SimpleKeyPair kp = await X25519().newKeyPair();
    _reset();
    _lobby = kp;
    _lobbyKey = Uint8List.fromList((await kp.extractPublicKey()).bytes);
    _lobbyUntil = _now().add(ttl);
    notifyListeners();
  }

  void closeWindow() {
    _lobby = null;
    _lobbyKey = null;
    _lobbyUntil = null;
    _reset();
    notifyListeners();
  }

  void _reset() {
    _state = PlayState.none;
    _sid = _keyIn = _peerKey = null;
    _remote = null;
    _lastSeq = 0;
    sas = null;
  }

  /// `POST /h`. [body] is `{e: ephemeral key, c: sealed hello}`. Null = silence (a stranger, a closed or expired lobby,
  /// a taken seat and a replay are all indistinguishable from nobody listening).
  Future<Map<String, dynamic>?> handleHello(Map<String, dynamic> body, String? remote) async {
    try {
      if (!windowOpen || _lobby == null || _lobbyKey == null) return null;
      final Uint8List epk = unb64(body['e'] as String), sealed = unb64(body['c'] as String);
      if (epk.length != 32) return null;
      final Uint8List dh = await _dh(_lobby!, epk);
      final hk = await deriveHelloKeys(dh, _lobbyKey!, epk);
      final Uint8List? plain = await openOnce(hk.clientToServer, _helloAad(_lobbyKey!, epk), sealed);
      if (plain == null) return null;
      final Map<String, dynamic> inner = jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
      final Uint8List sid = unb64(inner['i'] as String), fp = unb64(inner['f'] as String), sig = unb64(inner['s'] as String);
      if (sid.length != 16 || fp.length != 16) return null;
      Uint8List? peer;
      for (final Uint8List k in peerKeys) {
        if (constantTimeEquals(await fingerprintOf(k), fp)) peer = k;
      }
      if (peer == null) return null;
      if (!await DeviceKey.verify(peer, _helloSig(sid, epk, _lobbyKey!, fp), sig)) return null;
      final String sidText = b64(sid);
      if (_seenSids.contains(sidText)) return null; // a replayed hello
      if (_peerKey != null && !constantTimeEquals(_peerKey!, peer)) return null; // one seat
      _seenSids.add(sidText);
      if (_seenSids.length > 64) _seenSids.removeAt(0);

      final SimpleKeyPair eph = await X25519().newKeyPair();
      final Uint8List epk2 = Uint8List.fromList((await eph.extractPublicKey()).bytes);
      final PlayKeys keys = await deriveSessionKeys(await _dh(eph, epk), dh, sid);
      _sid = sid;
      _keyIn = keys.clientToServer;
      _peerKey = peer;
      _remote = remote;
      _lastSeq = 0;
      sas = _sasFrom(keys.sas);
      _state = (!requireConfirm || confirmedFingerprints.contains(b64(fp))) ? PlayState.admitted : PlayState.awaitingConfirm;
      notifyListeners();
      final Uint8List ownFp = own.fingerprint;
      final Uint8List reply = utf8.encode(jsonEncode(<String, String>{
        'e': b64(epk2), 'f': b64(ownFp), 's': b64(await own.sign(_ackSig(sid, epk, _lobbyKey!, epk2, ownFp))),
      }));
      return <String, dynamic>{'c': b64(await sealOnce(hk.serverToClient, _helloAad(_lobbyKey!, epk), reply))};
    } catch (_) {
      return null;
    }
  }

  /// The grown-up said yes. Remembers the peer so the next session skips this.
  void confirm() {
    if (_state != PlayState.awaitingConfirm || _peerKey == null) return;
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

  /// Opens one `POST /t` frame. Returns the decrypted payload bytes, or null for anything wrong: not admitted, another
  /// address, a bad or flipped frame, a counter that does not strictly rise (replay, reorder), a different session.
  Future<Uint8List?> openTurn(List<int> frame, String? remote) async {
    try {
      if (_state != PlayState.admitted || _keyIn == null || _sid == null) return null;
      if (remote == null || remote != _remote) return null;
      final int? seq = frameSeq(frame);
      if (seq == null || seq <= _lastSeq) return null;
      final OpenedFrame? f = await openFrame(_keyIn!, _sid!, frame);
      if (f == null) return null;
      _lastSeq = f.seq;
      return f.payload;
    } catch (_) {
      return null;
    }
  }
}

/// The sending side's session, once a hello succeeded.
class PlaySession {
  PlaySession._(this._sid, this._key, this.sas);
  final Uint8List _sid, _key;
  int _seq = 0;

  /// The same word and picture the receiving grown-up's screen shows.
  final Sas sas;

  /// One encrypted, padded, numbered frame for [payload] (the game's own JSON bytes, untouched).
  Future<Uint8List> sealTurn(List<int> payload) => sealFrame(_key, _sid, ++_seq, payload);

  /// Opens a session with the lobby whose token is [lobbyToken] and whose device is pinned as [peerKey]. [post] sends
  /// one JSON body to `/h` and returns the answer or null. Null if the lobby is silent, or answers with anything not
  /// from [peerKey].
  static Future<PlaySession?> hello({
    required DeviceKey own,
    required Uint8List peerKey,
    required String lobbyToken,
    required Future<Map<String, dynamic>?> Function(Map<String, dynamic> body) post,
    Random? random,
  }) async {
    try {
      final Random r = random ?? Random.secure();
      final Uint8List lobbyKey = unb64(lobbyToken);
      if (lobbyKey.length != 32) return null;
      final Uint8List sid = Uint8List.fromList(List<int>.generate(16, (_) => r.nextInt(256)));
      final SimpleKeyPair eph = await X25519().newKeyPair();
      final Uint8List epk = Uint8List.fromList((await eph.extractPublicKey()).bytes);
      final Uint8List dh = await _dh(eph, lobbyKey);
      final hk = await deriveHelloKeys(dh, lobbyKey, epk);
      final Uint8List inner = utf8.encode(jsonEncode(<String, String>{
        'i': b64(sid), 'f': b64(own.fingerprint), 's': b64(await own.sign(_helloSig(sid, epk, lobbyKey, own.fingerprint))),
      }));
      final Map<String, dynamic>? a = await post(<String, dynamic>{
        'e': b64(epk), 'c': b64(await sealOnce(hk.clientToServer, _helloAad(lobbyKey, epk), inner)),
      });
      if (a == null) return null;
      final Uint8List? plain = await openOnce(hk.serverToClient, _helloAad(lobbyKey, epk), unb64(a['c'] as String));
      if (plain == null) return null;
      final Map<String, dynamic> m = jsonDecode(utf8.decode(plain)) as Map<String, dynamic>;
      final Uint8List epk2 = unb64(m['e'] as String), fp = unb64(m['f'] as String), sig = unb64(m['s'] as String);
      if (epk2.length != 32 || !constantTimeEquals(fp, await fingerprintOf(peerKey))) return null;
      if (!await DeviceKey.verify(peerKey, _ackSig(sid, epk, lobbyKey, epk2, fp), sig)) return null;
      final PlayKeys keys = await deriveSessionKeys(await _dh(eph, epk2), dh, sid);
      return PlaySession._(sid, keys.clientToServer, _sasFrom(keys.sas));
    } catch (_) {
      return null;
    }
  }
}
