// OLIVE BRANCH — recovering a FORGOTTEN local guardian PIN from a SECOND grown-up's phone, with no server and no
// network. UNVERIFIED on a device; the protocol runs headless in CI (client/test/local_pin_recovery_test.dart).
// MASTERFILE section 7.12 (security follow-ups).
//
// THE PROBLEM. The local PIN (local_pin.dart) is a salted slow hash on this phone. Forget it and nothing on the phone can
// say what it was. The old only way out was to clear the app's storage, which erases the family set up on the phone.
//
// THE DESIGN. Two grown-up phones that have been LINKED once, side by side, while both PINs were known, each remember
// the other's public device key (the Ed25519 key device_keys.dart already gives every Olive device). A phone whose PIN
// is forgotten then shows a one-time CHALLENGE picture (a random nonce, its own key fingerprint, a 5 minute expiry);
// the other grown-up's phone checks it names a phone it was linked to, asks for ITS OWN PIN (the local PIN service:
// constant-time compare, five tries then 15 minutes), says in plain words what it is about to allow, and signs exactly
// those fields. The forgetful phone checks the signature against the key it pinned at linking, that the nonce is the
// single outstanding one and unexpired, consumes it, and only then lets the grown-up CHOOSE a new PIN (4 to 8 digits,
// easy-guess refused, same rules as ever). Same shape as unlock_challenge.dart (the tablet unlock), for the same reasons:
// a recording of either picture is useless afterwards, and neither picture contains a PIN.
//
// WHAT THIS PROVES, AND WHAT IT DOES NOT. Whoever holds the other phone AND knows its PIN can reset this one: that is the
// point (it is the second grown-up). Holding the other phone without its PIN cannot, and neither can holding this one
// without the other. Linking is trust on first use, done in person (each phone shows its key as a picture, the other
// scans it, each after its own PIN); a link made by a stranger needs the stranger to hold an unlocked, PIN-checked
// phone next to this one. A link names no child, no family and no account and grants nothing but this one thing.
//
// NO SECOND GROWN-UP, NO RECOVERY. With no linked phone there is nothing to ask, and nothing here pretends otherwise:
// [kNoRecoveryWords] says plainly that clearing the app's storage is the only reset and that it erases the family on
// this phone. Nothing is queued, mailed or "sent to a server": the server PIN (POST /v1/me/pin) is a separate secret.
//
// The links live in the sealed `localpin` area next to the PIN record, so wiping that area (a data wipe, clearing the app)
// removes them with the PIN. Setting a new PIN here never touches them.
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'cpace.dart' show cat, lv;
import 'device_keys.dart';
import 'local_pin.dart' show constantTimeEquals;
import 'local_store.dart';

/// How many linked phones a device keeps (one is the real case; a few allows a second parent plus a partner).
const int kMaxGuardianPeers = 4;

/// How long a challenge picture lives. Longer than the tablet unlock's two minutes: the other grown-up may be in
/// the next room, and the cost of a stale picture is nothing (it is single use and needs their PIN).
const Duration kPinResetTtl = Duration(minutes: 5);

/// What the forgetful phone says when it has no linked phone to ask. Plain adult words, no softening.
const String kNoRecoveryWords =
    "This phone isn't linked to another grown-up's phone, so there is nothing to ask. "
    "Clearing Olive's storage on this phone (Settings, Apps, Olive, Storage, Clear) is the only way to reset the PIN, "
    'and it erases the family you set up on this phone, including anything kept only here. '
    'Link a second grown-up now, while you still know your PIN, and next time they can reset it for you.';

/// A grown-up phone this one trusts to approve a PIN reset.
class GuardianPeer {
  GuardianPeer({required this.publicKey, required this.label, required this.linkedAtMs});
  final Uint8List publicKey;
  final String label;
  final int linkedAtMs;

  Map<String, Object?> toJson() => <String, Object?>{'k': b64(publicKey), 'l': label, 't': linkedAtMs};

  static GuardianPeer? fromJson(Object? raw) {
    if (raw is! Map) return null;
    try {
      final Object? k = raw['k'], l = raw['l'], t = raw['t'];
      if (k is! String || l is! String || t is! int) return null;
      final Uint8List pk = unb64(k);
      return pk.length == 32 ? GuardianPeer(publicKey: pk, label: l, linkedAtMs: t) : null;
    } catch (_) {
      return null;
    }
  }
}

abstract class GuardianPeerRepository {
  Future<List<GuardianPeer>> load();
  Future<void> save(List<GuardianPeer> peers);
}

class MemoryGuardianPeerRepository implements GuardianPeerRepository {
  List<GuardianPeer> _p = <GuardianPeer>[];
  @override
  Future<List<GuardianPeer>> load() async => List<GuardianPeer>.of(_p);
  @override
  Future<void> save(List<GuardianPeer> peers) async => _p = List<GuardianPeer>.of(peers);
}

/// Over the sealed `localpin` area, under its own key so [LocalStoreLocalPinRepository] never sees it.
class LocalStoreGuardianPeerRepository implements GuardianPeerRepository {
  LocalStoreGuardianPeerRepository(this._ns);
  final LocalNamespace _ns;
  static const String _key = 'peers';
  @override
  Future<List<GuardianPeer>> load() async {
    final Object? raw = await _ns.get(_key);
    if (raw is! List) return <GuardianPeer>[];
    return <GuardianPeer>[
      for (final Object? e in raw) ...<GuardianPeer>[if (GuardianPeer.fromJson(e) case final GuardianPeer p) p],
    ];
  }

  @override
  Future<void> save(List<GuardianPeer> peers) =>
      _ns.put(_key, <Object?>[for (final GuardianPeer p in peers) p.toJson()]);
}

// --------------------------------------------------------------------------------------------- linking

Uint8List _linkSigned(List<int> publicKey, String label) =>
    cat(<List<int>>[lv(utf8.encode('olive-guardian-link-v1')), lv(publicKey), lv(utf8.encode(label))]);

/// The picture one grown-up phone shows for the other to scan: its public key and the name it goes by, signed with
/// that key (proof the sender holds it, not a copy of someone else's).
class GuardianLinkOffer {
  const GuardianLinkOffer({required this.publicKey, required this.label, required this.signature});
  final Uint8List publicKey, signature;
  final String label;

  String toQr() => Uri(scheme: 'olive', host: 'guardian-link', path: '/1', queryParameters: <String, String>{
        'k': b64(publicKey), 'l': label, 's': b64(signature),
      }).toString();

  /// Null unless well formed AND signed by the key it carries.
  static Future<GuardianLinkOffer?> parse(String raw) async {
    try {
      final Uri u = Uri.parse(raw.trim());
      if (u.scheme != 'olive' || u.host != 'guardian-link' || u.path != '/1') return null;
      final Uint8List k = unb64(u.queryParameters['k'] ?? ''), s = unb64(u.queryParameters['s'] ?? '');
      final String label = (u.queryParameters['l'] ?? '').trim();
      if (k.length != 32 || label.isEmpty || label.length > 40) return null;
      if (!await DeviceKey.verify(k, _linkSigned(k, label), s)) return null;
      return GuardianLinkOffer(publicKey: k, label: label, signature: s);
    } catch (_) {
      return null;
    }
  }
}

enum LinkResult { linked, alreadyLinked, ownKey, notAnOffer, full }

/// One phone's side of linking and of the list it keeps. The caller asks for the PIN BEFORE [accept] (the screen does).
class GuardianLinker {
  GuardianLinker({required this.key, required this.repo, DateTime Function()? now}) : _now = now ?? DateTime.now;
  final DeviceKey key;
  final GuardianPeerRepository repo;
  final DateTime Function() _now;

  /// The picture this phone shows. [myLabel] is how the other phone will name this one ("Dad's phone").
  Future<String> offer(String myLabel) async {
    final String label = myLabel.trim().isEmpty ? 'A grown-up' : myLabel.trim();
    final String l = label.length > 40 ? label.substring(0, 40) : label;
    final Uint8List sig = await key.sign(_linkSigned(key.publicKey, l));
    return GuardianLinkOffer(publicKey: key.publicKey, label: l, signature: sig).toQr();
  }

  Future<List<GuardianPeer>> peers() => repo.load();

  /// Stores the phone [raw] names. Never stores anything for a picture that is not a genuine offer.
  Future<LinkResult> accept(String raw) async {
    final GuardianLinkOffer? o = await GuardianLinkOffer.parse(raw);
    if (o == null) return LinkResult.notAnOffer;
    if (constantTimeEquals(o.publicKey, key.publicKey)) return LinkResult.ownKey;
    final List<GuardianPeer> now = await repo.load();
    for (final GuardianPeer p in now) {
      if (constantTimeEquals(p.publicKey, o.publicKey)) return LinkResult.alreadyLinked;
    }
    if (now.length >= kMaxGuardianPeers) return LinkResult.full;
    await repo.save(<GuardianPeer>[
      ...now,
      GuardianPeer(publicKey: o.publicKey, label: o.label, linkedAtMs: _now().millisecondsSinceEpoch),
    ]);
    return LinkResult.linked;
  }

  /// Forgets one linked phone (by index in [peers]). That phone can no longer reset this one.
  Future<void> remove(int index) async {
    final List<GuardianPeer> now = await repo.load();
    if (index < 0 || index >= now.length) return;
    now.removeAt(index);
    await repo.save(now);
  }
}

// --------------------------------------------------------------------------------------------- the reset

Uint8List _resetSigned(List<int> nonce, List<int> requesterFp, List<int> signerFp, int expMs) => cat(<List<int>>[
      lv(utf8.encode('olive-pinreset-v1')), lv(nonce), lv(requesterFp), lv(signerFp), lv(utf8.encode('$expMs')),
    ]);

class PinResetChallenge {
  const PinResetChallenge({required this.nonce, required this.requesterFingerprint, required this.expiresMs});
  final Uint8List nonce, requesterFingerprint;
  final int expiresMs;

  String toQr() => Uri(scheme: 'olive', host: 'pin-reset', path: '/1', queryParameters: <String, String>{
        'n': b64(nonce), 'c': b64(requesterFingerprint), 'e': '$expiresMs',
      }).toString();

  static PinResetChallenge? parse(String raw) {
    try {
      final Uri u = Uri.parse(raw.trim());
      if (u.scheme != 'olive' || u.host != 'pin-reset' || u.path != '/1') return null;
      final int? e = int.tryParse(u.queryParameters['e'] ?? '');
      final Uint8List n = unb64(u.queryParameters['n'] ?? ''), c = unb64(u.queryParameters['c'] ?? '');
      if (e == null || n.length != 16 || c.length != 16) return null;
      return PinResetChallenge(nonce: n, requesterFingerprint: c, expiresMs: e);
    } catch (_) {
      return null;
    }
  }
}

/// The forgetful phone's side. A true from [accept] is the ONLY thing that lets the screen offer "choose a new PIN".
class PinResetRequester {
  PinResetRequester({required this.key, required this.repo, DateTime Function()? now, Random? random, this.ttl = kPinResetTtl})
      : _now = now ?? DateTime.now,
        _random = random ?? Random.secure();
  final DeviceKey key;
  final GuardianPeerRepository repo;
  final DateTime Function() _now;
  final Random _random;
  final Duration ttl;
  PinResetChallenge? _outstanding;

  /// Whether any linked phone exists to ask. False means [kNoRecoveryWords].
  Future<bool> canAsk() async => (await repo.load()).isNotEmpty;

  /// Null when there is no linked phone. Otherwise issues THE outstanding challenge (a newer one replaces an older).
  Future<PinResetChallenge?> issue() async {
    if (!await canAsk()) return null;
    final PinResetChallenge c = PinResetChallenge(
      nonce: Uint8List.fromList(List<int>.generate(16, (_) => _random.nextInt(256))),
      requesterFingerprint: key.fingerprint,
      expiresMs: _now().add(ttl).millisecondsSinceEpoch,
    );
    _outstanding = c;
    return c;
  }

  /// True only for a fresh answer to the outstanding challenge, signed by a phone linked here. The challenge is consumed
  /// as soon as an answer NAMING it arrives, whether or not it verifies (one try per picture).
  Future<bool> accept(String raw) async {
    final PinResetChallenge? o = _outstanding;
    if (o == null) return false;
    try {
      final Uri u = Uri.parse(raw.trim());
      if (u.scheme != 'olive' || u.host != 'pin-reset-ok' || u.path != '/1') return false;
      final Uint8List n = unb64(u.queryParameters['n'] ?? '');
      if (!constantTimeEquals(n, o.nonce)) return false;
      _outstanding = null;
      if (!_now().isBefore(DateTime.fromMillisecondsSinceEpoch(o.expiresMs))) return false;
      final Uint8List signerFp = unb64(u.queryParameters['h'] ?? ''), sig = unb64(u.queryParameters['s'] ?? '');
      if (signerFp.length != 16) return false;
      for (final GuardianPeer p in await repo.load()) {
        if (!constantTimeEquals(await fingerprintOf(p.publicKey), signerFp)) continue;
        return DeviceKey.verify(p.publicKey, _resetSigned(o.nonce, o.requesterFingerprint, signerFp, o.expiresMs), sig);
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Drops the outstanding challenge (the screen was left).
  void cancel() => _outstanding = null;
}

/// What the helper phone understood of a scanned challenge.
class PinResetView {
  const PinResetView(this.challenge, this.peer);
  final PinResetChallenge challenge;
  final GuardianPeer peer;
}

/// The other grown-up's phone. The caller asks for ITS OWN PIN BEFORE [grant].
class PinResetHelper {
  PinResetHelper({required this.key, required this.repo, DateTime Function()? now}) : _now = now ?? DateTime.now;
  final DeviceKey key;
  final GuardianPeerRepository repo;
  final DateTime Function() _now;

  /// Null unless the challenge is well formed, unexpired and names a phone THIS phone was linked to.
  Future<PinResetView?> inspect(String raw) async {
    final PinResetChallenge? c = PinResetChallenge.parse(raw);
    if (c == null || !_now().isBefore(DateTime.fromMillisecondsSinceEpoch(c.expiresMs))) return null;
    for (final GuardianPeer p in await repo.load()) {
      if (constantTimeEquals(await fingerprintOf(p.publicKey), c.requesterFingerprint)) return PinResetView(c, p);
    }
    return null;
  }

  Future<String> grant(PinResetView v) async {
    final PinResetChallenge c = v.challenge;
    final Uint8List sig = await key.sign(_resetSigned(c.nonce, c.requesterFingerprint, key.fingerprint, c.expiresMs));
    return Uri(scheme: 'olive', host: 'pin-reset-ok', path: '/1', queryParameters: <String, String>{
      'n': b64(c.nonce), 'h': b64(key.fingerprint), 's': b64(sig),
    }).toString();
  }
}

/// The three roles above over ONE peer list and ONE device key, loaded lazily (the key is made on first use). What
/// the guardian shell hands the screens ([GuardianLocalServices.recovery]).
class GuardianRecovery {
  GuardianRecovery({required this.peers, required this.deviceKey, this.now});
  final GuardianPeerRepository peers;
  final Future<DeviceKey> Function() deviceKey;
  final DateTime Function()? now;
  DeviceKey? _key;

  Future<DeviceKey> _k() async => _key ??= await deviceKey();

  Future<GuardianLinker> linker() async => GuardianLinker(key: await _k(), repo: peers, now: now);
  Future<PinResetRequester> requester() async => PinResetRequester(key: await _k(), repo: peers, now: now);
  Future<PinResetHelper> helper() async => PinResetHelper(key: await _k(), repo: peers, now: now);
}
