// OLIVE BRANCH — sharing a screen from one grown-up to another, INSIDE the app. Verified by CI headless
// (client/test/screen_share_test.dart). Spec: docs/planning/QR-VETTING-BRAINSTORM.md ("Sharing a screen with another
// grown-up, inside the app"); owner decisions in docs/planning/DECISIONS.md. Android only.
//
// THE RULES, each enforced here in the data and tested, not only hidden on a screen.
//  1. ONLY A GROWN-UP SENDS AND ONLY A GROWN-UP RECEIVES. A recipient is a device the family ledger lists as an active
//     grown-up device whose person is a grown-up (not a carer, not a child's tablet), with an agreement key, not this
//     device, and not still settling in ([eligibleShareRecipients]). [sealShare] refuses anyone else. [openShare] refuses
//     to open unless THIS device is an active grown-up device, so a child device can never receive one even if the bytes
//     were pushed at it. A child device builds a service with [ScreenShareService.guardianDevice] false, which has no
//     recipients, cannot send, and refuses everything it is handed.
//  2. SEALED TO ONE PHONE. The picture is encrypted to the recipient grown-up phone's certified agreement key (an ephemeral
//     X25519 exchange, HKDF, ChaCha20-Poly1305) and signed by the sender's device key. Only that phone opens it; nothing
//     else on the road, and no server, can read it. A flipped bit, another recipient, another sender or a changed expiry
//     opens nothing. This composition has had no outside review (the same stance as family_keys.dart, decision D2).
//  3. IT EXPIRES (1 to 30 days, 7 by default) and the sender can TAKE IT BACK at any time. A take-back is a signed notice;
//     a notice that arrives before the picture leaves a mark so the picture is dropped when it does arrive.
//  4. IT CANNOT BE FORWARDED IN THE APP. A received picture is shown on a screen that blocks capture and has no send
//     action; the sender's API takes freshly captured bytes only. There is NO use of the phone's share sheet anywhere
//     (a test reads the library and the manifest and fails if one appears).
//  5. THE FAMILY HISTORY KEEPS A QUIET NOTE ("Sam shared a screen with Alex"), never the picture. This is a convenience
//     between two parents, not an evidence chain.
//
// HONEST LIMITS. A grown-up who receives a picture could photograph it with another device; the app cannot prevent that.
// There is NO road to the other phone yet: [NoShareTransport] delivers nothing, so a picture waits sealed in the outbox
// ("Alex isn't nearby. It will go when your phones meet.") until a transport exists (family sync, FAMILY-SYNC-DESIGN.md).
// Until a family ledger with a second grown-up exists on the phone there is nobody to send to, so the action is hidden.
// UNVERIFIED on a device: the headless tests are the only proof so far; it needs a hardware pass before it is relied on.
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'cpace.dart' show cat, lv;
import 'device_keys.dart' show DeviceKey, b64, unb64;
import 'family_ledger.dart' show AgreementKey, hexOf;
import 'family_ledger_state.dart';
import 'local_store.dart';

const String kShareLabel = 'olive-share-v1';
const String kShareRetractLabel = 'olive-share-retract-v1';
const String _shareInfo = 'olive/share/v1';

/// The largest picture, in bytes of PNG. The capture is made smaller until it fits.
const int kShareMaxImageBytes = 1024 * 1024;
const int kShareMaxNoteChars = 200;
const int kShareDefaultExpiryDays = 7;
const int kShareMinExpiryDays = 1;
const int kShareMaxExpiryDays = 30;
const int kShareMaxHeld = 3;
const int kShareMaxSealedBytes = 2 * 1024 * 1024;
const int _skewMs = 5 * 60 * 1000;
const int _dayMs = 24 * 60 * 60 * 1000;
const int _maxSide = 4096;

/// Why a send was refused. The reason is for tests and logs; the screens use their own words.
class ShareRefused implements Exception {
  const ShareRefused(this.reason);
  final String reason;
  @override
  String toString() => 'ShareRefused($reason)';
}

/// A grown-up this device may send to.
class ShareRecipient {
  const ShareRecipient({required this.deviceKey, required this.agree, required this.name});
  final Uint8List deviceKey, agree;
  final String name;
  String get keyHex => hexOf(deviceKey);
}

/// The only people a screen can go to: other grown-ups' phones in this family. Never a child's device, never a carer,
/// never this phone, never someone still settling in, never a device with no agreement key. An empty list means the
/// "Share this screen" action stays hidden (a family with one grown-up has no one to share with).
List<ShareRecipient> eligibleShareRecipients(LedgerState s, List<int> ownDeviceKey, int nowMs) {
  if (!s.ok || !s.isActiveGuardianDevice(ownDeviceKey)) return const <ShareRecipient>[];
  final String own = hexOf(ownDeviceKey);
  final Map<String, String> grownUps = <String, String>{
    for (final LedgerMember m in s.members) if (m.isGuardian) m.gidHex: m.name,
  };
  final List<ShareRecipient> out = <ShareRecipient>[];
  for (final LedgerDevice d in s.devices) {
    final Uint8List? agree = d.agree;
    final String? name = grownUps[d.gidHex ?? ''];
    if (d.kind != 'guardian' || agree == null || name == null || d.keyHex == own || d.settlingAt(nowMs)) continue;
    out.add(ShareRecipient(deviceKey: d.key, agree: agree, name: name));
  }
  return out;
}

/// The name the ledger gives a grown-up device, or null when it is not one.
String? _grownUpName(LedgerState s, List<int> deviceKey) {
  final LedgerDevice? d = s.deviceFor(deviceKey);
  if (d == null || d.kind != 'guardian') return null;
  for (final LedgerMember m in s.members) {
    if (m.isGuardian && m.gidHex == d.gidHex) return m.name;
  }
  return null;
}

/// True for bytes that are a real PNG of a sane size: the signature, an IHDR first, and a width and height that cannot
/// be used to make the other phone allocate a huge image.
bool looksLikePng(List<int> b) {
  if (b.length < 33 || b.length > kShareMaxImageBytes) return false;
  const List<int> sig = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  for (int i = 0; i < 8; i++) {
    if (b[i] != sig[i]) return false;
  }
  if (b[12] != 0x49 || b[13] != 0x48 || b[14] != 0x44 || b[15] != 0x52) return false;
  final int w = (b[16] << 24) | (b[17] << 16) | (b[18] << 8) | b[19];
  final int h = (b[20] << 24) | (b[21] << 16) | (b[22] << 8) | b[23];
  return w > 0 && h > 0 && w <= _maxSide && h <= _maxSide;
}

Uint8List _randomBytes(Random r, int n) => Uint8List.fromList(List<int>.generate(n, (_) => r.nextInt(256)));

Uint8List _header(List<int> id, List<int> from, List<int> to, int iat, int exp, List<int> eph) => cat(<List<int>>[
      lv(utf8.encode(kShareLabel)), lv(id), lv(from), lv(to), lv(ascii.encode('$iat')), lv(ascii.encode('$exp')), lv(eph),
    ]);

Future<SecretKey> _shareKey(List<int> shared, List<int> eph, List<int> recipientAgree) =>
    Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
        secretKey: SecretKey(shared), nonce: cat(<List<int>>[lv(eph), lv(recipientAgree)]), info: utf8.encode(_shareInfo));

/// Builds the sealed, signed bytes for one screen to one grown-up. Throws [ShareRefused] for anything the rules forbid.
Future<Uint8List> sealShare({
  required DeviceKey sender,
  required LedgerState state,
  required ShareRecipient to,
  required Uint8List png,
  required bool namesHidden,
  required int nowMs,
  int expiryDays = kShareDefaultExpiryDays,
  String note = '',
  Random? random,
  Uint8List? idForTest,
}) async {
  if (!state.ok || !state.isActiveGuardianDevice(sender.publicKey)) throw const ShareRefused('sender-not-a-grown-up');
  final bool eligible = eligibleShareRecipients(state, sender.publicKey, nowMs)
      .any((ShareRecipient r) => r.keyHex == to.keyHex && hexOf(r.agree) == hexOf(to.agree));
  if (!eligible) throw const ShareRefused('recipient-not-a-grown-up');
  if (!looksLikePng(png)) throw const ShareRefused('not-a-picture');
  if (note.length > kShareMaxNoteChars) throw const ShareRefused('note-too-long');
  if (expiryDays < kShareMinExpiryDays || expiryDays > kShareMaxExpiryDays) throw const ShareRefused('bad-expiry');
  final Random r = random ?? Random.secure();
  final Uint8List id = idForTest ?? _randomBytes(r, 16);
  final int exp = nowMs + expiryDays * _dayMs;
  final SimpleKeyPair eph = await X25519().newKeyPairFromSeed(_randomBytes(r, 32));
  final Uint8List ephPub = Uint8List.fromList((await eph.extractPublicKey()).bytes);
  final Uint8List shared = Uint8List.fromList(await (await X25519().sharedSecretKey(
          keyPair: eph, remotePublicKey: SimplePublicKey(to.agree, type: KeyPairType.x25519)))
      .extractBytes());
  final Uint8List header = _header(id, sender.publicKey, to.deviceKey, nowMs, exp, ephPub);
  final SecretBox box = await Chacha20.poly1305Aead().encrypt(
      utf8.encode(jsonEncode(<String, Object?>{'v': 1, 'png': b64(png), 'note': note, 'hid': namesHidden})),
      secretKey: await _shareKey(shared, ephPub, to.agree),
      nonce: Uint8List(12), // the key is unique to this one ephemeral, so a fixed nonce is safe
      aad: header);
  final Uint8List ct = cat(<List<int>>[box.cipherText, box.mac.bytes]);
  final Uint8List sig = await sender.sign(cat(<List<int>>[header, lv(ct)]));
  return Uint8List.fromList(utf8.encode(jsonEncode(<String, Object?>{
    'v': 1, 't': 'share', 'id': b64(id), 'from': b64(sender.publicKey), 'to': b64(to.deviceKey),
    'iat': nowMs, 'exp': exp, 'eph': b64(ephPub), 'ct': b64(ct), 'sig': b64(sig),
  })));
}

/// A share this device opened.
class ReceivedShare {
  const ReceivedShare({
    required this.idHex,
    required this.fromKeyHex,
    required this.fromName,
    required this.createdAtMs,
    required this.expiresAtMs,
    required this.note,
    required this.namesHidden,
    required this.png,
  });
  final String idHex, fromKeyHex, fromName, note;
  final int createdAtMs, expiresAtMs;
  final bool namesHidden;
  final Uint8List png;
}

Map<String, Object?>? _json(List<int> bytes) {
  if (bytes.isEmpty || bytes.length > kShareMaxSealedBytes) return null;
  try {
    final Object? v = jsonDecode(utf8.decode(bytes));
    return v is Map<String, Object?> ? v : null;
  } catch (_) {
    return null;
  }
}

Uint8List? _field(Map<String, Object?> m, String k, int len) {
  final Object? v = m[k];
  if (v is! String || v.length > 4 * len) return null;
  try {
    final Uint8List b = unb64(v);
    return b.length == len ? b : null;
  } catch (_) {
    return null;
  }
}

/// Opens a share addressed to this device. Null for ANYTHING wrong, and always null on a device that is not an active
/// grown-up device in the ledger (a child device can never receive one).
Future<ReceivedShare?> openShare({
  required Uint8List sealed,
  required DeviceKey own,
  required AgreementKey agreement,
  required LedgerState state,
  required int nowMs,
  bool guardianDevice = true,
}) async {
  if (!guardianDevice || !state.ok || !state.isActiveGuardianDevice(own.publicKey)) return null;
  final Map<String, Object?>? m = _json(sealed);
  if (m == null || m['v'] != 1 || m['t'] != 'share') return null;
  final Uint8List? id = _field(m, 'id', 16), from = _field(m, 'from', 32), to = _field(m, 'to', 32);
  final Uint8List? eph = _field(m, 'eph', 32), sig = _field(m, 'sig', 64);
  final Object? iatV = m['iat'], expV = m['exp'], ctV = m['ct'];
  if (id == null || from == null || to == null || eph == null || sig == null) return null;
  if (iatV is! int || expV is! int || ctV is! String || ctV.length > 3 * kShareMaxSealedBytes ~/ 2) return null;
  if (hexOf(to) != hexOf(own.publicKey) || hexOf(from) == hexOf(own.publicKey)) return null;
  final String? fromName = _grownUpName(state, from);
  if (fromName == null) return null;
  if (iatV > nowMs + _skewMs || expV <= nowMs || expV <= iatV || expV - iatV > kShareMaxExpiryDays * _dayMs + _skewMs) {
    return null;
  }
  final Uint8List ct;
  try {
    ct = unb64(ctV);
  } catch (_) {
    return null;
  }
  if (ct.length < 17) return null;
  final Uint8List header = _header(id, from, to, iatV, expV, eph);
  if (!await DeviceKey.verify(from, cat(<List<int>>[header, lv(ct)]), sig)) return null;
  try {
    final Uint8List shared = await agreement.sharedSecret(eph);
    final List<int> plain = await Chacha20.poly1305Aead().decrypt(
        SecretBox(ct.sublist(0, ct.length - 16), nonce: Uint8List(12), mac: Mac(ct.sublist(ct.length - 16))),
        secretKey: await _shareKey(shared, eph, agreement.publicKey),
        aad: header);
    final Map<String, Object?>? body = _json(plain);
    if (body == null || body['v'] != 1) return null;
    final Object? png = body['png'], note = body['note'], hid = body['hid'];
    if (png is! String || note is! String || hid is! bool || note.length > kShareMaxNoteChars) return null;
    final Uint8List bytes = unb64(png);
    if (!looksLikePng(bytes)) return null;
    return ReceivedShare(
        idHex: hexOf(id), fromKeyHex: hexOf(from), fromName: fromName, createdAtMs: iatV, expiresAtMs: expV,
        note: note, namesHidden: hid, png: bytes);
  } catch (_) {
    return null;
  }
}

Uint8List _retractSigned(List<int> id, List<int> from, List<int> to, int iat) => cat(<List<int>>[
      lv(utf8.encode(kShareRetractLabel)), lv(id), lv(from), lv(to), lv(ascii.encode('$iat')),
    ]);

/// A signed "I take that back" for one share.
Future<Uint8List> sealRetract({
  required DeviceKey sender,
  required List<int> id,
  required List<int> toDeviceKey,
  required int nowMs,
}) async =>
    Uint8List.fromList(utf8.encode(jsonEncode(<String, Object?>{
      'v': 1, 't': 'retract', 'id': b64(id), 'from': b64(sender.publicKey), 'to': b64(toDeviceKey), 'iat': nowMs,
      'sig': b64(await sender.sign(_retractSigned(id, sender.publicKey, toDeviceKey, nowMs))),
    })));

class RetractNotice {
  const RetractNotice(this.idHex, this.fromKeyHex);
  final String idHex, fromKeyHex;
}

/// Opens a take-back addressed to this device, from a grown-up device of this family. Null for anything else.
Future<RetractNotice?> openRetract({
  required Uint8List bytes,
  required DeviceKey own,
  required LedgerState state,
  required int nowMs,
  bool guardianDevice = true,
}) async {
  if (!guardianDevice || !state.ok || !state.isActiveGuardianDevice(own.publicKey)) return null;
  final Map<String, Object?>? m = _json(bytes);
  if (m == null || m['v'] != 1 || m['t'] != 'retract') return null;
  final Uint8List? id = _field(m, 'id', 16), from = _field(m, 'from', 32), to = _field(m, 'to', 32), sig = _field(m, 'sig', 64);
  final Object? iat = m['iat'];
  if (id == null || from == null || to == null || sig == null || iat is! int) return null;
  if (hexOf(to) != hexOf(own.publicKey) || hexOf(from) == hexOf(own.publicKey)) return null;
  if (_grownUpName(state, from) == null || iat > nowMs + _skewMs) return null;
  if (!await DeviceKey.verify(from, _retractSigned(id, from, to, iat), sig)) return null;
  return RetractNotice(hexOf(id), hexOf(from));
}

/// The road to another grown-up's phone. [deliver] answers true only when the other phone has taken the bytes.
abstract class ShareTransport {
  Future<bool> deliver(String recipientKeyHex, Uint8List bytes);
}

/// No road exists yet (family sync is a design, not code). Everything waits sealed in the outbox.
class NoShareTransport implements ShareTransport {
  const NoShareTransport();
  @override
  Future<bool> deliver(String recipientKeyHex, Uint8List bytes) async => false;
}

/// What this device needs to send and open: its keys and the family as the ledger says it is right now.
class ShareIdentity {
  const ShareIdentity({required this.device, required this.agreement, required this.state});
  final DeviceKey device;
  final AgreementKey agreement;
  final LedgerState state;
}

class OutgoingShare {
  OutgoingShare({
    required this.idHex,
    required this.toKeyHex,
    required this.toName,
    required this.createdAtMs,
    required this.expiresAtMs,
    required this.status,
    this.sealed,
    this.retract,
  });
  final String idHex, toKeyHex, toName;
  final int createdAtMs, expiresAtMs;

  /// 'waiting' (not yet taken by the other phone), 'sent', or 'retracting' (a take-back is still to be delivered).
  String status;
  Uint8List? sealed, retract;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': idHex, 'to': toKeyHex, 'name': toName, 'iat': createdAtMs, 'exp': expiresAtMs, 'st': status,
        'sealed': sealed == null ? null : b64(sealed!), 'retract': retract == null ? null : b64(retract!),
      };

  static OutgoingShare? fromJson(Object? v) {
    if (v is! Map) return null;
    final Object? id = v['id'], to = v['to'], name = v['name'], iat = v['iat'], exp = v['exp'], st = v['st'];
    if (id is! String || to is! String || name is! String || iat is! int || exp is! int) return null;
    if (st != 'waiting' && st != 'sent' && st != 'retracting') return null;
    try {
      return OutgoingShare(
        idHex: id, toKeyHex: to, toName: name, createdAtMs: iat, expiresAtMs: exp, status: st as String,
        sealed: v['sealed'] is String ? unb64(v['sealed'] as String) : null,
        retract: v['retract'] is String ? unb64(v['retract'] as String) : null,
      );
    } catch (_) {
      return null;
    }
  }
}

class HeldShare {
  HeldShare({required this.share, this.seen = false});
  final ReceivedShare share;
  bool seen;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': share.idHex, 'from': share.fromKeyHex, 'name': share.fromName, 'iat': share.createdAtMs,
        'exp': share.expiresAtMs, 'note': share.note, 'hid': share.namesHidden, 'png': b64(share.png), 'seen': seen,
      };

  static HeldShare? fromJson(Object? v) {
    if (v is! Map) return null;
    final Object? id = v['id'], from = v['from'], name = v['name'], iat = v['iat'], exp = v['exp'];
    final Object? note = v['note'], hid = v['hid'], png = v['png'];
    if (id is! String || from is! String || name is! String || iat is! int || exp is! int) return null;
    if (note is! String || hid is! bool || png is! String) return null;
    try {
      final Uint8List bytes = unb64(png);
      if (!looksLikePng(bytes)) return null;
      return HeldShare(
        share: ReceivedShare(
            idHex: id, fromKeyHex: from, fromName: name, createdAtMs: iat, expiresAtMs: exp, note: note,
            namesHidden: hid, png: bytes),
        seen: v['seen'] == true,
      );
    } catch (_) {
      return null;
    }
  }
}

/// One quiet line of family history. No picture, no note.
class ShareLogLine {
  const ShareLogLine(this.atMs, this.fromName, this.toName);
  final int atMs;
  final String fromName, toName;
  String get text => '$fromName shared a screen with $toName';
}

class ShareBoxState {
  ShareBoxState({
    List<OutgoingShare>? out,
    List<HeldShare>? held,
    List<String>? gone,
    List<ShareLogLine>? log,
  })  : out = out ?? <OutgoingShare>[],
        held = held ?? <HeldShare>[],
        gone = gone ?? <String>[],
        log = log ?? <ShareLogLine>[];
  final List<OutgoingShare> out;
  final List<HeldShare> held;

  /// `<sender key>:<share id>` of a share that was taken back or put away, so a late copy is dropped.
  final List<String> gone;
  final List<ShareLogLine> log;

  Map<String, Object?> toJson() => <String, Object?>{
        'v': 1,
        'out': <Object?>[for (final OutgoingShare o in out) o.toJson()],
        'in': <Object?>[for (final HeldShare h in held) h.toJson()],
        'gone': gone,
        'log': <Object?>[for (final ShareLogLine l in log) <String, Object?>{'at': l.atMs, 'by': l.fromName, 'to': l.toName}],
      };

  /// Anything unreadable is an empty box, never a half-trusted one.
  static ShareBoxState fromJson(Object? raw) {
    if (raw is! Map || raw['v'] != 1) return ShareBoxState();
    List<T> list<T>(Object? v, T? Function(Object?) f) =>
        v is List ? <T>[for (final Object? e in v) if (f(e) != null) f(e) as T] : <T>[];
    return ShareBoxState(
      out: list<OutgoingShare>(raw['out'], OutgoingShare.fromJson),
      held: list<HeldShare>(raw['in'], HeldShare.fromJson),
      gone: raw['gone'] is List ? <String>[for (final Object? e in raw['gone'] as List) if (e is String) e] : <String>[],
      log: list<ShareLogLine>(raw['log'], (Object? e) {
        if (e is! Map) return null;
        final Object? at = e['at'], by = e['by'], to = e['to'];
        return at is int && by is String && to is String ? ShareLogLine(at, by, to) : null;
      }),
    );
  }
}

abstract class ShareBoxRepository {
  Future<ShareBoxState> load();
  Future<void> save(ShareBoxState s);
}

class MemoryShareBoxRepository implements ShareBoxRepository {
  ShareBoxState _s = ShareBoxState();
  @override
  Future<ShareBoxState> load() async => ShareBoxState.fromJson(_s.toJson());
  @override
  Future<void> save(ShareBoxState s) async => _s = ShareBoxState.fromJson(s.toJson());
}

/// Kept in the sealed `screenshares` area (see localDataCatalogue).
class LocalStoreShareBoxRepository implements ShareBoxRepository {
  LocalStoreShareBoxRepository(this._ns);
  final LocalNamespace _ns;
  static const String _key = 'box';
  @override
  Future<ShareBoxState> load() async => ShareBoxState.fromJson(await _ns.get(_key));
  @override
  Future<void> save(ShareBoxState s) => _ns.put(_key, s.toJson());
}

enum ShareSendOutcome { sent, waiting }

enum ShareReceiveOutcome { kept, takenBack, duplicate, putAway, full, refused }

/// A grown-up's screen-sharing, over a box, an identity and a road.
class ScreenShareService {
  ScreenShareService({
    required this.box,
    required this.identity,
    this.transport = const NoShareTransport(),
    this.guardianDevice = true,
    int Function()? nowMs,
  }) : _now = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  /// A service for a child's device: no recipients, cannot send, refuses everything it is handed.
  ScreenShareService.childDevice()
      : box = MemoryShareBoxRepository(),
        identity = (() async => null),
        transport = const NoShareTransport(),
        guardianDevice = false,
        _now = (() => DateTime.now().millisecondsSinceEpoch);

  final ShareBoxRepository box;
  final Future<ShareIdentity?> Function() identity;
  final ShareTransport transport;
  final bool guardianDevice;
  final int Function() _now;
  Future<void> _chain = Future<void>.value();

  Future<T> _locked<T>(Future<T> Function() body) {
    final Completer<T> done = Completer<T>();
    _chain = _chain.then((_) async {
      try {
        done.complete(await body());
      } catch (e, s) {
        done.completeError(e, s);
      }
    });
    return done.future;
  }

  Future<ShareIdentity?> _id() async => guardianDevice ? identity() : null;

  /// The grown-ups this phone can send to. Empty on a child's device and in a family with one grown-up.
  Future<List<ShareRecipient>> recipients() async {
    final ShareIdentity? id = await _id();
    if (id == null) return const <ShareRecipient>[];
    return eligibleShareRecipients(id.state, id.device.publicKey, _now());
  }

  bool _expired(int expMs) => expMs <= _now();

  ShareBoxState _sweep(ShareBoxState s) {
    s.out.removeWhere((OutgoingShare o) => _expired(o.expiresAtMs) && o.status != 'retracting');
    s.held.removeWhere((HeldShare h) => _expired(h.share.expiresAtMs));
    return s;
  }

  /// Seals [png] to [to] and puts it in the outbox; tries the road once.
  Future<ShareSendOutcome> send({
    required Uint8List png,
    required ShareRecipient to,
    required bool namesHidden,
    String note = '',
    int expiryDays = kShareDefaultExpiryDays,
  }) async {
    // The lock is NOT held across the network wait: two phones sending to each other at the same moment would each hold
    // their own lock while the other's delivery waited to be received behind it.
    final ({OutgoingShare o, Uint8List sealed}) made = await _locked(() async {
        final ShareIdentity? id = await _id();
        if (id == null) throw const ShareRefused('not-a-grown-up-device');
        final int now = _now();
        final ShareBoxState s = _sweep(await box.load());
        if (s.out.where((OutgoingShare o) => o.sealed != null).length >= kShareMaxHeld) throw const ShareRefused('outbox-full');
        final Uint8List sealed = await sealShare(
            sender: id.device, state: id.state, to: to, png: png, namesHidden: namesHidden, nowMs: now,
            expiryDays: expiryDays, note: note);
        final Map<String, Object?> hdr = jsonDecode(utf8.decode(sealed)) as Map<String, Object?>;
        final OutgoingShare o = OutgoingShare(
            idHex: hexOf(unb64(hdr['id'] as String)), toKeyHex: to.keyHex, toName: to.name, createdAtMs: now,
            expiresAtMs: hdr['exp'] as int, status: 'waiting', sealed: sealed);
        s.out.add(o);
        final String me = _grownUpName(id.state, id.device.publicKey) ?? 'A grown-up';
        s.log.add(ShareLogLine(now, me, to.name));
        if (s.log.length > 50) s.log.removeRange(0, s.log.length - 50);
        await box.save(s);
        return (o: o, sealed: sealed);
      });
    final bool taken = await _deliver(made.o, made.sealed);
    if (taken) {
      await _locked(() async {
        final ShareBoxState s = await box.load();
        final OutgoingShare? o = s.out.where((OutgoingShare e) => e.idHex == made.o.idHex).firstOrNull;
        if (o == null || o.status != 'waiting') return; // taken back meanwhile: leave it as it is
        o.status = 'sent';
        o.sealed = null; // the picture is no longer kept here once the other phone has it
        await box.save(s);
      });
    }
    return taken ? ShareSendOutcome.sent : ShareSendOutcome.waiting;
  }

  Future<bool> _deliver(OutgoingShare o, Uint8List bytes) async {
    try {
      return await transport.deliver(o.toKeyHex, bytes);
    } catch (_) {
      return false;
    }
  }

  /// Takes a share back. If the other phone never got it, it is simply deleted here. If it did, a signed notice is
  /// sent (now if the road is open, later if not) and the picture is no longer kept here either way.
  Future<void> takeBack(String idHex) async {
    final ({OutgoingShare o, Uint8List notice})? pending = await _locked(() async {
        final ShareIdentity? id = await _id();
        if (id == null) throw const ShareRefused('not-a-grown-up-device');
        final ShareBoxState s = await box.load();
        final OutgoingShare? o = s.out.where((OutgoingShare e) => e.idHex == idHex).firstOrNull;
        if (o == null) return null;
        // The picture is dropped here at once. A signed notice is kept even for one that never left, because the other
        // phone may have taken it in a delivery whose answer was lost; a notice for something it never had does nothing.
        o.sealed = null;
        o.retract = await sealRetract(sender: id.device, id: unhex(idHex), toDeviceKey: unhex(o.toKeyHex), nowMs: _now());
        o.status = 'retracting';
        await box.save(s);
        return (o: o, notice: o.retract!);
      });
    if (pending == null) return;
    if (await _deliver(pending.o, pending.notice)) {
      await _locked(() async {
        final ShareBoxState s = await box.load();
        s.out.removeWhere((OutgoingShare e) => e.idHex == idHex && e.status == 'retracting');
        await box.save(s);
      });
    }
  }

  /// Tries the road for everything waiting. Returns how many left this phone.
  Future<int> flush() async {
    final List<({String id, bool retract, Uint8List bytes, String to})> todo = await _locked(() async {
        if (await _id() == null) return const <({String id, bool retract, Uint8List bytes, String to})>[];
        final ShareBoxState s = _sweep(await box.load());
        await box.save(s);
        return <({String id, bool retract, Uint8List bytes, String to})>[
          for (final OutgoingShare o in s.out)
            if (o.status == 'retracting' && o.retract != null)
              (id: o.idHex, retract: true, bytes: o.retract!, to: o.toKeyHex)
            else if (o.status == 'waiting' && o.sealed != null)
              (id: o.idHex, retract: false, bytes: o.sealed!, to: o.toKeyHex),
        ];
      });
    if (todo.isEmpty) return 0;
    // The network wait is outside the lock (see [send]).
    final List<({String id, bool retract})> done = <({String id, bool retract})>[];
    for (final ({String id, bool retract, Uint8List bytes, String to}) t in todo) {
      try {
        if (await transport.deliver(t.to, t.bytes)) done.add((id: t.id, retract: t.retract));
      } catch (_) {}
    }
    if (done.isEmpty) return 0;
    return _locked(() async {
      final ShareBoxState s = await box.load();
      int n = 0;
      for (final ({String id, bool retract}) d in done) {
        final OutgoingShare? o = s.out.where((OutgoingShare e) => e.idHex == d.id).firstOrNull;
        if (o == null) continue;
        if (d.retract && o.status == 'retracting') {
          s.out.remove(o);
          n++;
        } else if (!d.retract && o.status == 'waiting') {
          o.status = 'sent';
          o.sealed = null;
          n++;
        }
      }
      await box.save(s);
      return n;
    });
  }

  /// Hands this phone bytes that arrived from the road. Takes a share or a take-back; anything else is refused.
  Future<ShareReceiveOutcome> receive(Uint8List bytes) => _locked(() async {
        final ShareIdentity? id = await _id();
        if (id == null) return ShareReceiveOutcome.refused;
        final int now = _now();
        final ShareBoxState s = _sweep(await box.load());
        final Map<String, Object?>? m = _json(bytes);
        if (m == null) return ShareReceiveOutcome.refused;
        if (m['t'] == 'retract') {
          final RetractNotice? r = await openRetract(bytes: bytes, own: id.device, state: id.state, nowMs: now);
          if (r == null) return ShareReceiveOutcome.refused;
          final String key = '${r.fromKeyHex}:${r.idHex}';
          final int before = s.held.length;
          s.held.removeWhere((HeldShare h) => h.share.idHex == r.idHex && h.share.fromKeyHex == r.fromKeyHex);
          if (!s.gone.contains(key)) s.gone.add(key);
          if (s.gone.length > 200) s.gone.removeRange(0, s.gone.length - 200);
          await box.save(s);
          return before != s.held.length ? ShareReceiveOutcome.takenBack : ShareReceiveOutcome.putAway;
        }
        final ReceivedShare? r = await openShare(
            sealed: bytes, own: id.device, agreement: id.agreement, state: id.state, nowMs: now);
        if (r == null) return ShareReceiveOutcome.refused;
        if (s.gone.contains('${r.fromKeyHex}:${r.idHex}')) return ShareReceiveOutcome.putAway;
        if (s.held.any((HeldShare h) => h.share.idHex == r.idHex && h.share.fromKeyHex == r.fromKeyHex)) {
          return ShareReceiveOutcome.duplicate;
        }
        if (s.held.length >= kShareMaxHeld) return ShareReceiveOutcome.full;
        s.held.add(HeldShare(share: r));
        final String me = _grownUpName(id.state, id.device.publicKey) ?? 'A grown-up';
        s.log.add(ShareLogLine(now, r.fromName, me));
        if (s.log.length > 50) s.log.removeRange(0, s.log.length - 50);
        try {
          await box.save(s);
        } on LocalStoreFull {
          return ShareReceiveOutcome.full; // nothing was written; the sender keeps it waiting
        }
        return ShareReceiveOutcome.kept;
      });

  /// What other grown-ups sent this phone, newest first. Empty on a child's device.
  Future<List<ReceivedShare>> inbox() => _locked(() async {
        if (!guardianDevice) return const <ReceivedShare>[];
        final ShareBoxState s = _sweep(await box.load());
        await box.save(s);
        return <ReceivedShare>[for (final HeldShare h in s.held.reversed) h.share];
      });

  /// What this phone sent that has not yet been taken back or expired, newest first.
  Future<List<OutgoingShare>> sent() => _locked(() async {
        if (!guardianDevice) return const <OutgoingShare>[];
        final ShareBoxState s = _sweep(await box.load());
        await box.save(s);
        return <OutgoingShare>[for (final OutgoingShare o in s.out.reversed) o];
      });

  /// Puts a received picture away for good. A late copy of it is dropped.
  Future<void> putAway(String idHex) => _locked(() async {
        final ShareBoxState s = await box.load();
        final HeldShare? h = s.held.where((HeldShare e) => e.share.idHex == idHex).firstOrNull;
        if (h == null) return;
        s.held.remove(h);
        s.gone.add('${h.share.fromKeyHex}:$idHex');
        await box.save(s);
      });

  Future<void> markSeen(String idHex) => _locked(() async {
        final ShareBoxState s = await box.load();
        for (final HeldShare h in s.held) {
          if (h.share.idHex == idHex) h.seen = true;
        }
        await box.save(s);
      });

  /// The quiet family-history lines, newest first. Never a picture.
  Future<List<ShareLogLine>> history() => _locked(() async {
        if (!guardianDevice) return const <ShareLogLine>[];
        return (await box.load()).log.reversed.toList();
      });
}

Uint8List unhex(String h) =>
    Uint8List.fromList(<int>[for (int i = 0; i + 1 < h.length; i += 2) int.parse(h.substring(i, i + 2), radix: 16)]);
