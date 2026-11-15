// OLIVE BRANCH — the signed, append-only family ledger: canonical encoding, entries, votes and the shape of every
// entry body. UNVERIFIED on a device; pure Dart, runs headless in CI. Spec: docs/planning/FAMILY-IDENTITY-DESIGN.md
// sections 3.1, 3.2, 4 and 7, and docs/planning/VILLAGE-WELCOME-DESIGN.md sections 9 and 10 (the fields PR 1's schema
// must already carry). The rules that read these entries live in family_ledger_state.dart.
//
// WHAT THIS IS. A family is (FID, genesisHash). Who is a grown-up, which devices belong, and what changed is a list of
// entries, each signed by an Ed25519 device key, each naming the entries it follows (`prev`), so it is a hash-linked
// graph and not a roster that goes stale. An approval is a separate signed vote that names one entry by its hash. The
// entry hash covers `prev`, so a yes given to one entry can never be replayed onto another entry or another position.
//
// WHAT THIS IS NOT (read before trusting it). It is NOT wired into pairing, onboarding or any screen. Nothing in the
// app calls it yet. A child device never signs a ledger entry (the reducer refuses a child key as a signer). The
// composition (canonical bytes, domain strings, the reduce rule) is new custom code over vetted primitives and has had
// no outside cryptographic review; decision D2 of the pairing spec already requires one before real families rely on it.
//
// CANONICAL BYTES. Every field is length-prefixed with `lv` (the same helper PairingCert uses), and a body is a typed
// tree (string, non-negative integer, bytes, list, map with keys in byte order, bool, null). It is NOT JSON: signing
// JSON is fragile. [LedgerEntry.parse] re-encodes what it read and refuses anything that is not byte-identical, so
// there is exactly one encoding of each entry. tools/family_ledger.mjs is an independent Node implementation of the
// encoder and the hash; test/vectors/family_ledger_vectors.json is agreed by both languages.
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'cpace.dart' show cat, lv;
import 'device_keys.dart' show DeviceKey, b64, unb64;
import 'family_profiles.dart';

/// The domain string at the front of every signed entry. It differs from `olive-cert-v1` (PairingCert), the unlock
/// grants and the PAKE labels, so a signature made for one of those can never verify as a ledger entry.
const String kLedgerDomain = 'olive-ledger-v1';
const String kVoteDomain = 'olive-ledger-vote-v1';
const String kAgreeCertDomain = 'olive-agree-cert-v1';

/// A clock this far wrong (either way) is tolerated before an entry or a vote is "from the future".
const int kClockSkewMs = 5 * 60 * 1000;

/// Revoking ANOTHER grown-up's phone takes effect only after this notice (identity design 4.4); the target can cancel.
const int kRevokeNoticeMs = 72 * 60 * 60 * 1000;

/// How long a loosening or a removal waits for its approvals before silence ends it.
const int kApprovalLifetimeMs = 14 * kMsPerDay;

/// Sizes (identity design question 11, "recommend"; owner decision pending). Carers: village design 13.10, pending.
const int kMaxGuardians = 6;
const int kMaxChildDevices = 12;
const int kMaxCarers = 8;
const int kMaxDevicesPerGuardian = 4;

/// Hard bounds so a hostile peer cannot make a device do unbounded work.
const int kMaxEntryBytes = 24 * 1024;
const int kMaxLedgerEntries = 1500;
const int kMaxLedgerVotes = 6000;
const int kMaxPrev = 8;

String hexOf(List<int> b) {
  final StringBuffer s = StringBuffer();
  for (final int v in b) {
    s.write(v.toRadixString(16).padLeft(2, '0'));
  }
  return s.toString();
}

Uint8List fromHex(String s) {
  if (s.length.isOdd) throw const FormatException('odd hex');
  return Uint8List.fromList(<int>[for (int i = 0; i < s.length; i += 2) int.parse(s.substring(i, i + 2), radix: 16)]);
}

/// Constant-time-ish byte equality (lengths are public).
bool bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  int d = 0;
  for (int i = 0; i < a.length; i++) {
    d |= a[i] ^ b[i];
  }
  return d == 0;
}

int _cmp(List<int> a, List<int> b) {
  final int n = a.length < b.length ? a.length : b.length;
  for (int i = 0; i < n; i++) {
    if (a[i] != b[i]) return a[i] - b[i];
  }
  return a.length - b.length;
}

// ---------------------------------------------------------------------------------------------------------------
// Canonical value codec
// ---------------------------------------------------------------------------------------------------------------

const int _tString = 1, _tInt = 2, _tBytes = 3, _tList = 4, _tMap = 5, _tBool = 6, _tNull = 7;
const int _maxDepth = 8;

/// Encodes a value tree. Accepts null, bool, non-negative int, String, Uint8List, List and `Map<String, Object?>`.
/// Throws [ArgumentError] on anything else (a negative number, a double, a non-ASCII map key, a plain `List<int>`).
Uint8List encodeValue(Object? v) {
  final List<int> out = <int>[];
  _enc(v, out, 0);
  return Uint8List.fromList(out);
}

void _enc(Object? v, List<int> out, int depth) {
  if (depth > _maxDepth) throw ArgumentError('too deep');
  if (v == null) {
    out.add(_tNull);
  } else if (v is bool) {
    out..add(_tBool)..add(v ? 1 : 0);
  } else if (v is int) {
    if (v < 0) throw ArgumentError('negative integer');
    out.add(_tInt);
    out.addAll(lv(ascii.encode('$v')));
  } else if (v is String) {
    out.add(_tString);
    out.addAll(lv(utf8.encode(v)));
  } else if (v is Uint8List) {
    out.add(_tBytes);
    out.addAll(lv(v));
  } else if (v is List) {
    final List<int> inner = <int>[];
    for (final Object? x in v) {
      _enc(x, inner, depth + 1);
    }
    out.add(_tList);
    out.addAll(lv(inner));
  } else if (v is Map) {
    final List<MapEntry<List<int>, Object?>> items = <MapEntry<List<int>, Object?>>[];
    for (final MapEntry<dynamic, dynamic> e in v.entries) {
      final Object? k = e.key;
      if (k is! String || !_keyRe.hasMatch(k)) throw ArgumentError('bad map key');
      items.add(MapEntry<List<int>, Object?>(ascii.encode(k), e.value));
    }
    items.sort((MapEntry<List<int>, Object?> a, MapEntry<List<int>, Object?> b) => _cmp(a.key, b.key));
    final List<int> inner = <int>[];
    for (final MapEntry<List<int>, Object?> e in items) {
      inner.addAll(lv(e.key));
      _enc(e.value, inner, depth + 1);
    }
    out.add(_tMap);
    out.addAll(lv(inner));
  } else {
    throw ArgumentError('unsupported value ${v.runtimeType}');
  }
}

final RegExp _keyRe = RegExp(r'^[A-Za-z0-9_.-]{1,24}$');
final RegExp _intRe = RegExp(r'^(0|[1-9][0-9]{0,14})$');

class _Reader {
  _Reader(this.b);
  final Uint8List b;
  int i = 0;
  bool get done => i == b.length;

  int u8() {
    if (i >= b.length) throw const FormatException('eof');
    return b[i++];
  }

  int varint() {
    int n = 0;
    for (int k = 0; k < 4; k++) {
      final int x = u8();
      n |= (x & 0x7f) << (7 * k);
      if ((x & 0x80) == 0) return n;
    }
    throw const FormatException('varint too long');
  }

  Uint8List take(int n) {
    if (n < 0 || i + n > b.length) throw const FormatException('short');
    final Uint8List out = Uint8List.sublistView(b, i, i + n);
    i += n;
    return Uint8List.fromList(out);
  }

  Uint8List lvBytes() => take(varint());
}

/// Strict decode of exactly one value. Throws [FormatException] on any malformed or non-canonical input that the
/// reader itself can see (the caller still re-encodes and compares for the rest).
Object? decodeValue(Uint8List bytes) {
  final _Reader r = _Reader(bytes);
  final Object? v = _dec(r, 0);
  if (!r.done) throw const FormatException('trailing bytes');
  return v;
}

Object? _dec(_Reader r, int depth) {
  if (depth > _maxDepth) throw const FormatException('too deep');
  final int tag = r.u8();
  switch (tag) {
    case _tNull:
      return null;
    case _tBool:
      final int x = r.u8();
      if (x > 1) throw const FormatException('bool');
      return x == 1;
    case _tInt:
      final String s = ascii.decode(r.lvBytes());
      if (!_intRe.hasMatch(s)) throw const FormatException('int');
      return int.parse(s);
    case _tString:
      return utf8.decode(r.lvBytes());
    case _tBytes:
      return r.lvBytes();
    case _tList:
      final _Reader inner = _Reader(r.lvBytes());
      final List<Object?> out = <Object?>[];
      while (!inner.done) {
        out.add(_dec(inner, depth + 1));
        if (out.length > 4096) throw const FormatException('list too long');
      }
      return out;
    case _tMap:
      final _Reader inner = _Reader(r.lvBytes());
      final Map<String, Object?> out = <String, Object?>{};
      Uint8List? last;
      while (!inner.done) {
        final Uint8List kb = inner.lvBytes();
        if (last != null && _cmp(last, kb) >= 0) throw const FormatException('map keys not ascending');
        last = kb;
        final String k = ascii.decode(kb);
        if (!_keyRe.hasMatch(k)) throw const FormatException('map key');
        out[k] = _dec(inner, depth + 1);
      }
      return out;
  }
  throw const FormatException('tag');
}

// ---------------------------------------------------------------------------------------------------------------
// Family policy
// ---------------------------------------------------------------------------------------------------------------

/// The family's own rules for who must agree. The floors of the village design are NOT fields here, so no
/// `policy.set` can express them: a new Parent always needs ALL parents when there are two or more.
class FamilyPolicy {
  const FamilyPolicy({this.addGrownUp = 'all', this.settleHours = 24, this.carerAct = 'all', this.carerLook = 'one'});

  /// 'any' or 'all': what a loosening of this policy needs from the other grown-ups (identity design 4.2 step 4).
  final String addGrownUp;

  /// 0, 24 or 72: how long a newly added grown-up's phone stays in settle-in.
  final int settleHours;

  /// 'all' or 'one': how many parents must say yes to a carer who can act (village design 5.2).
  final String carerAct;

  /// 'one' or 'all': how many parents must say yes to a carer who can only look.
  final String carerLook;

  static const List<int> allowedSettle = <int>[0, 24, 72];

  bool get valid =>
      (addGrownUp == 'any' || addGrownUp == 'all') &&
      allowedSettle.contains(settleHours) &&
      (carerAct == 'all' || carerAct == 'one') &&
      (carerLook == 'all' || carerLook == 'one');

  /// True when any field of this policy is looser than [cur]. Tightening is free for any grown-up; loosening needs
  /// the approvals the CURRENT rule demands (identity design 3.2, `policy.set`).
  bool loosensFrom(FamilyPolicy cur) =>
      _rank(addGrownUp) < _rank(cur.addGrownUp) ||
      settleHours < cur.settleHours ||
      _rank(carerAct) < _rank(cur.carerAct) ||
      _rank(carerLook) < _rank(cur.carerLook);

  static int _rank(String s) => s == 'all' ? 1 : 0;

  /// Field-wise strictest of two policies: what concurrent `policy.set` entries resolve to.
  static FamilyPolicy strictest(FamilyPolicy a, FamilyPolicy b) => FamilyPolicy(
        addGrownUp: _rank(a.addGrownUp) >= _rank(b.addGrownUp) ? a.addGrownUp : b.addGrownUp,
        settleHours: a.settleHours >= b.settleHours ? a.settleHours : b.settleHours,
        carerAct: _rank(a.carerAct) >= _rank(b.carerAct) ? a.carerAct : b.carerAct,
        carerLook: _rank(a.carerLook) >= _rank(b.carerLook) ? a.carerLook : b.carerLook,
      );

  Map<String, Object?> toValue() =>
      <String, Object?>{'add': addGrownUp, 'settle': settleHours, 'carerAct': carerAct, 'carerLook': carerLook};

  static FamilyPolicy? fromValue(Object? v) {
    if (v is! Map<String, Object?> || v.length != 4) return null;
    final Object? a = v['add'], s = v['settle'], ca = v['carerAct'], cl = v['carerLook'];
    if (a is! String || s is! int || ca is! String || cl is! String) return null;
    final FamilyPolicy p = FamilyPolicy(addGrownUp: a, settleHours: s, carerAct: ca, carerLook: cl);
    return p.valid ? p : null;
  }

  @override
  bool operator ==(Object other) =>
      other is FamilyPolicy &&
      other.addGrownUp == addGrownUp &&
      other.settleHours == settleHours &&
      other.carerAct == carerAct &&
      other.carerLook == carerLook;

  @override
  int get hashCode => Object.hash(addGrownUp, settleHours, carerAct, carerLook);
}

// ---------------------------------------------------------------------------------------------------------------
// Device record, agreement-key certificate
// ---------------------------------------------------------------------------------------------------------------

/// What an entry says about one device: its Ed25519 key, its X25519 agreement key, and the device's own signature
/// that the agreement key is its own. Without the certificate, a signer could write someone else's device into an
/// entry with the SIGNER's agreement key and receive the family key meant for that device.
class DeviceRecord {
  const DeviceRecord({required this.key, this.agree, this.cert});
  final Uint8List key;
  final Uint8List? agree, cert;

  Map<String, Object?> toValue() => <String, Object?>{'key': key, 'agree': agree, 'cert': cert};

  static DeviceRecord? fromValue(Object? v) {
    if (v is! Map<String, Object?> || v.length != 3) return null;
    final Object? k = v['key'], a = v['agree'], c = v['cert'];
    if (k is! Uint8List || k.length != 32) return null;
    if ((a == null) != (c == null)) return null;
    if (a != null && (a is! Uint8List || a.length != 32 || c is! Uint8List || c.length != 64)) return null;
    return DeviceRecord(key: k, agree: a as Uint8List?, cert: c as Uint8List?);
  }
}

Uint8List agreementCertBytes(List<int> agreePub, List<int> devicePub) =>
    cat(<List<int>>[lv(utf8.encode(kAgreeCertDomain)), lv(agreePub), lv(devicePub)]);

/// The device signs "this X25519 key is mine".
Future<Uint8List> certifyAgreementKey(DeviceKey device, List<int> agreePub) =>
    device.sign(agreementCertBytes(agreePub, device.publicKey));

Future<bool> verifyAgreementCert(DeviceRecord r) async {
  final Uint8List? a = r.agree, c = r.cert;
  if (a == null || c == null) return false;
  return DeviceKey.verify(r.key, agreementCertBytes(a, r.key), c);
}

/// A device's X25519 agreement key. Its public half is certified by the device's Ed25519 key inside a ledger entry.
class AgreementKey {
  AgreementKey._(this._pair, this.seed, this.publicKey);
  final SimpleKeyPair _pair;

  /// The 32-byte secret seed, to be kept sealed (see family_state.dart); never sent.
  final Uint8List seed;
  final Uint8List publicKey;

  static Future<AgreementKey> fromSeed(List<int> seed) async {
    final Uint8List s = Uint8List.fromList(seed);
    final SimpleKeyPair pair = await X25519().newKeyPairFromSeed(s);
    return AgreementKey._(pair, s, Uint8List.fromList((await pair.extractPublicKey()).bytes));
  }

  static Future<AgreementKey> generate({Random? random}) {
    final Random r = random ?? Random.secure();
    return fromSeed(List<int>.generate(32, (_) => r.nextInt(256)));
  }

  Future<Uint8List> certify(DeviceKey device) => certifyAgreementKey(device, publicKey);

  Future<Uint8List> sharedSecret(List<int> peerPublic) async => Uint8List.fromList(await (await X25519().sharedSecretKey(
          keyPair: _pair, remotePublicKey: SimplePublicKey(peerPublic, type: KeyPairType.x25519)))
      .extractBytes());
}

// ---------------------------------------------------------------------------------------------------------------
// Entries
// ---------------------------------------------------------------------------------------------------------------

/// Every entry type in v1. The last six are RESERVED: their bodies are checked and they are recorded, but they change
/// nothing in the reduced state (the pause, limits and standing-OK behaviour is a later wave, W5 to W9).
class EntryType {
  static const String genesis = 'genesis';
  static const String memberAdd = 'member.add';
  static const String deviceAdd = 'device.add';
  static const String deviceRevoke = 'device.revoke';
  static const String deviceRevokeCancel = 'device.revoke.cancel';
  static const String guardianLeave = 'guardian.leave';
  static const String guardianRemove = 'guardian.remove';
  static const String policySet = 'policy.set';
  static const String keyRotate = 'key.rotate';
  static const String accessPause = 'access.pause';
  static const String accessResume = 'access.resume';
  static const String accessEnd = 'access.end';
  static const String limitsAgree = 'limits.agree';
  static const String limitsTighten = 'limits.tighten';
  static const String standingOk = 'standing.ok';

  static const List<String> reserved = <String>[
    accessPause, accessResume, accessEnd, limitsAgree, limitsTighten, standingOk,
  ];
  static const List<String> all = <String>[
    genesis, memberAdd, deviceAdd, deviceRevoke, deviceRevokeCancel, guardianLeave, guardianRemove, policySet,
    keyRotate, accessPause, accessResume, accessEnd, limitsAgree, limitsTighten, standingOk,
  ];
}

class LedgerEntry {
  LedgerEntry._(this.type, this.prev, this.body, this.signer, this.issuedAtMs, this.signature, this.bytes, this.hash);

  final String type;

  /// The hashes of the entries this one follows: strictly ascending, 32 bytes each. Empty only for a genesis.
  final List<Uint8List> prev;
  final Map<String, Object?> body;

  /// The signing device's FULL Ed25519 public key (the design says fingerprint; a 128-bit fingerprint can be ground
  /// to a collision with enough work, and a full key cannot).
  final Uint8List signer;
  final int issuedAtMs;
  final Uint8List signature;

  /// The exact signed bytes.
  final Uint8List bytes;

  /// SHA-256 of `lv(bytes) | lv(signature)`. Votes are NOT in it, so it does not change as approvals arrive.
  final Uint8List hash;

  String get hashHex => hexOf(hash);
  String get signerHex => hexOf(signer);

  static Uint8List signedBytes({
    required String type,
    required List<Uint8List> prev,
    required Map<String, Object?> body,
    required List<int> signer,
    required int issuedAtMs,
  }) =>
      cat(<List<int>>[
        lv(utf8.encode(kLedgerDomain)),
        lv(utf8.encode(type)),
        lv(encodeValue(prev)),
        lv(encodeValue(body)),
        lv(signer),
        lv(ascii.encode('$issuedAtMs')),
      ]);

  static Future<Uint8List> hashOf(List<int> bytes, List<int> signature) async =>
      Uint8List.fromList((await Sha256().hash(cat(<List<int>>[lv(bytes), lv(signature)]))).bytes);

  /// Signs a new entry with [key]. [prev] is sorted and de-duplicated here.
  static Future<LedgerEntry> sign(
    DeviceKey key, {
    required String type,
    required Iterable<List<int>> prev,
    required Map<String, Object?> body,
    required int issuedAtMs,
  }) async {
    final Map<String, Uint8List> uniq = <String, Uint8List>{
      for (final List<int> p in prev) hexOf(p): Uint8List.fromList(p),
    };
    final List<Uint8List> ps = uniq.values.toList()..sort(_cmp);
    final Uint8List bytes =
        signedBytes(type: type, prev: ps, body: body, signer: key.publicKey, issuedAtMs: issuedAtMs);
    final Uint8List sig = await key.sign(bytes);
    // Round-trip through the strict parser so a body the schema would refuse never leaves the signer.
    final LedgerEntry? e = await parse(bytes, sig);
    if (e == null) throw ArgumentError('entry does not survive canonical parsing');
    return e;
  }

  /// Strict parse. Null on anything not exactly canonical. Does NOT verify the signature (see [verifySignature]).
  static Future<LedgerEntry?> parse(List<int> bytesIn, List<int> sigIn) async {
    if (bytesIn.length > kMaxEntryBytes || sigIn.length != 64) return null;
    try {
      final Uint8List bytes = Uint8List.fromList(bytesIn);
      final _Reader r = _Reader(bytes);
      final Uint8List domain = r.lvBytes(), type = r.lvBytes(), prevEnc = r.lvBytes(), bodyEnc = r.lvBytes();
      final Uint8List signer = r.lvBytes(), issued = r.lvBytes();
      if (!r.done) return null;
      if (utf8.decode(domain) != kLedgerDomain || signer.length != 32) return null;
      final String t = utf8.decode(type);
      if (!EntryType.all.contains(t)) return null;
      final Object? pv = decodeValue(prevEnc);
      if (pv is! List || pv.length > kMaxPrev) return null;
      final List<Uint8List> prev = <Uint8List>[];
      for (final Object? p in pv) {
        if (p is! Uint8List || p.length != 32) return null;
        if (prev.isNotEmpty && _cmp(prev.last, p) >= 0) return null;
        prev.add(p);
      }
      final Object? bv = decodeValue(bodyEnc);
      if (bv is! Map<String, Object?>) return null;
      final String is_ = ascii.decode(issued);
      if (!_intRe.hasMatch(is_)) return null;
      final int at = int.parse(is_);
      // One encoding only: what we read must be exactly what we would write.
      final Uint8List again = signedBytes(type: t, prev: prev, body: bv, signer: signer, issuedAtMs: at);
      if (!bytesEqual(again, bytes)) return null;
      if ((t == EntryType.genesis) != prev.isEmpty) return null;
      if (!_bodyShapeOk(t, bv)) return null;
      final Uint8List sig = Uint8List.fromList(sigIn);
      return LedgerEntry._(t, prev, bv, signer, at, sig, bytes, await hashOf(bytes, sig));
    } catch (_) {
      return null;
    }
  }

  Future<bool> verifySignature() => DeviceKey.verify(signer, bytes, signature);

  Map<String, Object?> toJson() => <String, Object?>{'b': b64(bytes), 's': b64(signature)};

  static Future<LedgerEntry?> fromJson(Object? raw) async {
    if (raw is! Map) return null;
    final Object? b = raw['b'], s = raw['s'];
    if (b is! String || s is! String) return null;
    try {
      return await parse(unb64(b), unb64(s));
    } catch (_) {
      return null;
    }
  }
}

// ---------------------------------------------------------------------------------------------------------------
// Votes (detached approvals)
// ---------------------------------------------------------------------------------------------------------------

/// A signed yes, no or withdraw about ONE entry, named by its hash. Because the entry hash covers `prev` and the
/// whole body, a vote binds to a ledger position: it cannot be replayed onto another entry, another position, or
/// another proposal. A vote is not part of the entry graph, so approvals can arrive later and by any route.
class LedgerVote {
  LedgerVote._(this.target, this.answer, this.voter, this.atMs, this.signature);
  final Uint8List target, voter, signature;
  final String answer; // 'yes' | 'no' | 'withdraw'
  final int atMs;

  static const List<String> answers = <String>['yes', 'no', 'withdraw'];

  static Uint8List signedBytes(List<int> target, String answer, List<int> voter, int atMs) => cat(<List<int>>[
        lv(utf8.encode(kVoteDomain)), lv(target), lv(utf8.encode(answer)), lv(voter), lv(ascii.encode('$atMs')),
      ]);

  static Future<LedgerVote> sign(
    DeviceKey voter, {
    required List<int> target,
    required String answer,
    required int atMs,
  }) async {
    if (!answers.contains(answer) || target.length != 32) throw ArgumentError('bad vote');
    final Uint8List sig = await voter.sign(signedBytes(target, answer, voter.publicKey, atMs));
    return LedgerVote._(Uint8List.fromList(target), answer, voter.publicKey, atMs, sig);
  }

  Future<bool> verifySignature() => DeviceKey.verify(voter, signedBytes(target, answer, voter, atMs), signature);

  String get targetHex => hexOf(target);
  String get voterHex => hexOf(voter);

  Map<String, Object?> toJson() =>
      <String, Object?>{'t': b64(target), 'a': answer, 'v': b64(voter), 'at': atMs, 's': b64(signature)};

  static LedgerVote? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final Object? t = raw['t'], a = raw['a'], v = raw['v'], at = raw['at'], s = raw['s'];
    if (t is! String || a is! String || v is! String || at is! int || s is! String) return null;
    try {
      final Uint8List tb = unb64(t), vb = unb64(v), sb = unb64(s);
      if (tb.length != 32 || vb.length != 32 || sb.length != 64 || at < 0 || !answers.contains(a)) return null;
      return LedgerVote._(tb, a, vb, at, sb);
    } catch (_) {
      return null;
    }
  }
}

// ---------------------------------------------------------------------------------------------------------------
// Body shapes: exact keys, exact types, no extras. A body that is not exactly one of these is not an entry.
// ---------------------------------------------------------------------------------------------------------------

typedef _Chk = bool Function(Object? v);

bool _b(Object? v, int n) => v is Uint8List && v.length == n;
bool _bOpt(Object? v, int n) => v == null || _b(v, n);
bool _int(Object? v) => v is int && v >= 0;
bool _intOpt(Object? v) => v == null || _int(v);
bool _text(Object? v, {int min = 1, int max = 40}) {
  if (v is! String || v.length < min || v.length > max) return false;
  for (final int c in v.runes) {
    if (c < 32 || c == 127) return false;
  }
  return true;
}

bool _textOpt(Object? v) => v == null || _text(v, max: 64);
bool _oneOf(Object? v, List<String> options) => v is String && options.contains(v);

bool _sortedIds(Object? v, {int max = 32}) {
  if (v is! List || v.length > max) return false;
  Uint8List? last;
  for (final Object? x in v) {
    if (x is! Uint8List || x.length != 16) return false;
    if (last != null && _cmp(last, x) >= 0) return false;
    last = x;
  }
  return true;
}

bool _shape(Object? v, Map<String, _Chk> spec) {
  if (v is! Map<String, Object?> || v.length != spec.length) return false;
  for (final MapEntry<String, _Chk> e in spec.entries) {
    if (!v.containsKey(e.key) || !e.value(v[e.key])) return false;
  }
  return true;
}

bool _devFull(Object? v) {
  final DeviceRecord? r = DeviceRecord.fromValue(v);
  return r != null && r.agree != null;
}

bool _devAny(Object? v) => DeviceRecord.fromValue(v) != null;

bool _proposal(Object? v) => _shape(v, <String, _Chk>{
      'id': (Object? x) => _b(x, 16),
      'exp': _int,
      'electorate': (Object? x) => _sortedIds(x, max: 16),
      'rule': (Object? x) => _oneOf(x, const <String>['all', 'one']),
    });

bool _wraps(Object? v) {
  if (v is! List || v.length > 32) return false;
  for (final Object? w in v) {
    if (!_shape(w, <String, _Chk>{
      'to': (Object? x) => _b(x, 32),
      'fk': (Object? x) => x is Uint8List && x.length >= 48 && x.length <= 256,
      'gk': (Object? x) => x == null || (x is Uint8List && x.length >= 48 && x.length <= 256),
    })) {
      return false;
    }
  }
  return true;
}

bool _bodyShapeOk(String type, Map<String, Object?> body) {
  switch (type) {
    case EntryType.genesis:
      return _shape(body, <String, _Chk>{
        'v': (Object? x) => x == 1,
        'fid': (Object? x) => _b(x, 16),
        'gid': (Object? x) => _b(x, 16),
        'name': _text,
        'dev': _devFull,
        'policy': (Object? x) => FamilyPolicy.fromValue(x) != null,
        'legacyFids': (Object? x) => x is List && x.length <= 4 && x.every((Object? s) => _text(s, max: 64)),
        'fkc': (Object? x) => _b(x, 32),
        'gkc': (Object? x) => _b(x, 32),
      });
    case EntryType.memberAdd:
      return _shape(body, <String, _Chk>{
        'gid': (Object? x) => _b(x, 16),
        'name': _text,
        'kind': (Object? x) => _oneOf(x, const <String>['guardian', 'carer']),
        'profile': (Object? x) => MemberProfile.fromValue(x) != null,
        'dev': _devFull,
        'proposal': _proposal,
      });
    case EntryType.deviceAdd:
      return _shape(body, <String, _Chk>{
        'kind': (Object? x) => _oneOf(x, const <String>['guardian', 'child']),
        'gid': (Object? x) => _bOpt(x, 16),
        'childId': _textOpt,
        'name': _text,
        'dev': _devAny,
        'legacy': (Object? x) => x is bool,
        'orig': _intOpt,
      });
    case EntryType.deviceRevoke:
      return _shape(body, <String, _Chk>{
        'key': (Object? x) => _b(x, 32),
        'reason': (Object? x) => _oneOf(x, const <String>['lost', 'replaced', 'removed', 'forgotten']),
        'eff': _int,
      });
    case EntryType.deviceRevokeCancel:
      return _shape(body, <String, _Chk>{'revoke': (Object? x) => _b(x, 32)});
    case EntryType.guardianLeave:
      return _shape(body, <String, _Chk>{'gid': (Object? x) => _b(x, 16)});
    case EntryType.guardianRemove:
      return _shape(body, <String, _Chk>{'gid': (Object? x) => _b(x, 16), 'exp': _int});
    case EntryType.policySet:
      return _shape(body, <String, _Chk>{
        'policy': (Object? x) => FamilyPolicy.fromValue(x) != null,
        'exp': _intOpt,
      });
    case EntryType.keyRotate:
      return _shape(body, <String, _Chk>{
        'epoch': (Object? x) => _int(x) && (x as int) >= 1,
        'fkc': (Object? x) => _b(x, 32),
        'gkc': (Object? x) => _b(x, 32),
        'wraps': _wraps,
      });
    case EntryType.accessPause:
    case EntryType.accessResume:
      return _shape(body, <String, _Chk>{'gid': (Object? x) => _b(x, 16)});
    case EntryType.accessEnd:
      return _shape(body, <String, _Chk>{
        'gid': (Object? x) => _b(x, 16),
        'reason': (Object? x) => _oneOf(x, const <String>['ended', 'left', 'time_box', 'court']),
      });
    case EntryType.limitsAgree:
      return _shape(body, <String, _Chk>{
        'gid': (Object? x) => _b(x, 16),
        'limits': (Object? x) => x is List && x.length <= 13 && x.every(_int),
        'until': _int,
      });
    case EntryType.limitsTighten:
      return _shape(body, <String, _Chk>{
        'gid': (Object? x) => _b(x, 16),
        'limits': (Object? x) => x is List && x.length <= 13 && x.every(_int),
      });
    case EntryType.standingOk:
      return _shape(body, <String, _Chk>{'gid': (Object? x) => _b(x, 16), 'until': _int});
  }
  return false;
}

/// The family id as a UUID-shaped string (8-4-4-4-12). It is 128 random bits; no version bits are forced, so a
/// Postgres `uuid` column takes it unchanged.
String familyIdString(List<int> fid) {
  final String h = hexOf(fid);
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

/// The two anchors a device pins: the random family id and the hash of the signed genesis entry. Two ledgers with the
/// same FID and a different genesis are two different families, and the second is ignored.
class FamilyPin {
  FamilyPin(List<int> fid, List<int> genesisHash)
      : fid = Uint8List.fromList(fid),
        genesisHash = Uint8List.fromList(genesisHash);
  final Uint8List fid, genesisHash;

  bool matches(FamilyPin o) => bytesEqual(fid, o.fid) && bytesEqual(genesisHash, o.genesisHash);
}
