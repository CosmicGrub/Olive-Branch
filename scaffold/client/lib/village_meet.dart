// OLIVE BRANCH — the in-person meeting that comes before a welcome: a grown-up's phone opens a short window, the new
// person's phone types the code on it, both phones show the same word and picture, and the new person's phone is
// introduced. UNVERIFIED on a device (the same-Wi-Fi half needs two real phones); the protocol runs headless in CI
// (client/test/village_meet_test.dart). Spec: docs/planning/VILLAGE-WELCOME-DESIGN.md section 3.2 ("Meet": a scan or a
// code is an introduction, never a key; the role is chosen only by the proposer).
//
// WHAT A MEETING GIVES, AND WHAT IT DOES NOT. It gives the grown-up's phone one fact: "the phone I am talking to was
// held by someone who read the code off MY screen, and holds the keys it showed me" (a password-authenticated key
// exchange, CPace, cpace.dart, with five tries; the same primitive the child pairing uses, in the `join-member` mode of
// family_channel_v2.dart so a transcript from one mode cannot be replayed into another). It gives the new phone one
// fact: "the phone I am talking to knew the code". It grants NOTHING. The new phone says only its own name for itself
// and its keys; it never says what it will be (a parent or a carer, what it may do): that is chosen on the grown-up's
// screen afterwards, and an extra field in the introduction is ignored. Nothing is welcomed until the right
// grown-ups have said yes, and the new person has said yes on their own phone.
//
// THE CODE. Six digits shown on the grown-up's screen, valid for 15 minutes, five wrong tries end the window, a key
// exchange that fails is counted like a wrong try. It is an input to the exchange, never sent: what crosses the
// Wi-Fi is the exchange's public shares, confirmation tags and sealed bodies. A bystander learns nothing they can use
// without the code, and learns the code is wrong only by guessing against the five tries.
//
// THEN, ON THE GROWN-UP SIDE: after the pictures match and the proposer has chosen what the person may do, the window
// holds the signed record (sealed under the exchange's own key) for the new phone to fetch. The new phone fetches it,
// shows the person exactly what they are being offered, and says yes with a signed vote of its own, which travels the
// ordinary road (village_link.dart).
//
// NOT HERE: the other grown-ups (they get the request through village_link.dart), a meeting with someone far away
// (that needs the server and is parked), and any change to child pairing (pairing_protocol.dart is untouched).
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import 'cpace.dart';
import 'device_keys.dart';
import 'family_channel_v2.dart' show PairMode;
import 'family_ledger.dart';
import 'family_ledger_state.dart';
import 'local_pin.dart' show constantTimeEquals;
import 'pairing_limits.dart' show SourceBucket;
import 'pairing_protocol.dart' show PairingTransport, Sas;

const int kMeetCodeDigits = 6;
const Duration kMeetTtl = Duration(minutes: 15);
const int kMeetMaxAttempts = 5;
const int _kMaxKeyExchanges = 20;
const int kMeetMaxCredentialBytes = 900 * 1024;
const String _kMeetLabel = 'olive-village-meet-v1';
final List<int> _aadIntro = utf8.encode('olive-village-intro/1');
final List<int> _aadCred = utf8.encode('olive-village-cred/1');

/// The channel identifier of the exchange: the label, the mode (so a pairing transcript cannot be replayed here) and the
/// new phone's own key. The grown-up's side contributes nothing a bystander could swap in.
Uint8List meetChannelId(List<int> joinerKey) =>
    lvCat(<List<int>>[utf8.encode(_kMeetLabel), utf8.encode(PairMode.joinMember.wire), joinerKey]);

Uint8List _rb(Random r, int n) => Uint8List.fromList(List<int>.generate(n, (_) => r.nextInt(256)));

Future<String> _sealUnder(PakeKey key, List<int> aad, List<int> plain, Random r) async {
  final Uint8List nonce = _rb(r, 12);
  final SecretBox box =
      await Chacha20.poly1305Aead().encrypt(plain, secretKey: SecretKey(await key.channelKey()), nonce: nonce, aad: aad);
  return b64(cat(<List<int>>[nonce, box.cipherText, box.mac.bytes]));
}

Future<Uint8List?> _openUnder(PakeKey key, List<int> aad, String sealed, {int maxBytes = 64 * 1024}) async {
  try {
    if (sealed.length > 2 * maxBytes) return null;
    final Uint8List b = unb64(sealed);
    if (b.length < 12 + 16 || b.length > maxBytes) return null;
    return Uint8List.fromList(await Chacha20.poly1305Aead().decrypt(
        SecretBox(b.sublist(12, b.length - 16), nonce: b.sublist(0, 12), mac: Mac(b.sublist(b.length - 16))),
        secretKey: SecretKey(await key.channelKey()),
        aad: aad));
  } catch (_) {
    return null;
  }
}

/// What the new phone said about itself: its name for itself and its keys. Never what it will be.
class MeetIntro {
  const MeetIntro({required this.record, required this.deviceName});
  final DeviceRecord record;
  final String deviceName;
}

String _cleanDeviceName(String s) {
  final StringBuffer b = StringBuffer();
  for (final int c in s.runes) {
    if (c >= 32 && c != 127) b.writeCharCode(c);
  }
  final String t = b.toString().trim();
  return t.isEmpty ? 'A phone' : (t.length <= 40 ? t : t.substring(0, 40));
}

enum MeetState { open, introduced, matched, offered, declined, closed }

/// The grown-up phone's side. A window is opened by a grown-up, lives 15 minutes, and serves one new phone.
class VillageMeetWindow extends ChangeNotifier {
  VillageMeetWindow._(this.code, this.sid, this.discoveryHandle, this._now, this._random, this._bucket) : expiresAt = _now().add(kMeetTtl);

  /// Opens a window. [code] is for tests; a real run leaves it null (six random digits).
  static VillageMeetWindow open({String? code, Random? random, DateTime Function()? now, SourceBucket? bucket}) {
    final Random r = random ?? Random.secure();
    final DateTime Function() n = now ?? DateTime.now;
    final String c = code ?? List<String>.generate(kMeetCodeDigits, (_) => '${r.nextInt(10)}').join();
    return VillageMeetWindow._(c, _rb(r, 16), _rb(r, 16), n, r, bucket ?? SourceBucket(limit: 6));
  }

  final String code;
  final Uint8List sid, discoveryHandle;
  final DateTime Function() _now;
  final Random _random;
  final SourceBucket _bucket;
  final DateTime expiresAt;

  MeetState _state = MeetState.open;
  MeetState get state => _state;
  int _failures = 0;
  int _exchanges = 0;
  Uint8List? _joinerKey, _tagC;
  PakeKey? _key;
  MeetIntro? _intro;
  Sas? _sas;
  String? _credential;

  /// The new phone's introduction, once it has passed the code. Null before.
  MeetIntro? get intro => _intro;

  /// The word and picture both phones show. Null before the introduction.
  Sas? get sas => _sas;
  int get failures => _failures;

  bool get isOpen => _state != MeetState.closed && _state != MeetState.declined && _now().isBefore(expiresAt);

  void _set(MeetState s) {
    if (_state == s) return;
    _state = s;
    notifyListeners();
  }

  /// The grown-up saw the same word and picture on both phones.
  void confirmMatch() {
    if (_state == MeetState.introduced) _set(MeetState.matched);
  }

  /// The pictures did not match, or the grown-up changed their mind: nothing is sent, the window ends.
  void decline() {
    _credential = null;
    _set(MeetState.declined);
  }

  void close() {
    _credential = null;
    _set(MeetState.closed);
  }

  /// Gives the new phone the signed record to look at (sealed under the exchange's key). Only after the match is
  /// confirmed, and only once.
  Future<void> offer({required Iterable<LedgerEntry> entries, required Iterable<LedgerVote> votes}) async {
    if (_state != MeetState.matched || _key == null) throw StateError('not ready to offer');
    final String body = jsonEncode(<String, Object?>{
      'v': 1,
      'e': <Object?>[for (final LedgerEntry e in entries) e.toJson()],
      'o': <Object?>[for (final LedgerVote v in votes) v.toJson()],
    });
    _credential = await _sealUnder(_key!, _aadCred, utf8.encode(body), _random);
    _set(MeetState.offered);
  }

  /// One wire message. Null means silence (the same as no window): a closed window, a wrong handle, a bad tag.
  Future<Map<String, dynamic>?> handle(Map<String, dynamic> m, {String? source}) async {
    if (!isOpen) {
      if (_state != MeetState.closed && _state != MeetState.declined) close();
      return null;
    }
    final Object? t = m['t'];
    try {
      switch (t) {
        case 'm0':
          return _m0(m, source);
        case 'm1':
          return await _m1(m, source);
        case 'm3':
          return await _m3(m);
        case 'm5':
          return await _m5(m);
      }
    } catch (_) {}
    return null;
  }

  Uint8List? _b(Map<String, dynamic> m, String k, int len) {
    final Object? v = m[k];
    if (v is! String || v.length > 4 * len) return null;
    try {
      final Uint8List b = unb64(v);
      return b.length == len ? b : null;
    } catch (_) {
      return null;
    }
  }

  /// The first message names the window by its random handle and gets the session id back. A handle that is not this
  /// window’s gets silence.
  Map<String, dynamic>? _m0(Map<String, dynamic> m, String? source) {
    if (_state != MeetState.open) return null;
    if (source != null && !_bucket.allow(source)) return null;
    final Uint8List? h = _b(m, 'h', 16);
    if (h == null || !constantTimeEquals(h, discoveryHandle)) return null;
    return <String, dynamic>{'t': 'm0-ok', 'sid': b64(sid)};
  }

  Future<Map<String, dynamic>?> _m1(Map<String, dynamic> m, String? source) async {
    if (_state != MeetState.open) return null; // one new phone per window
    if (source != null && !_bucket.allow(source)) return null;
    final Uint8List? h = _b(m, 'h', 16), cpk = _b(m, 'cpk', 32), yc = _b(m, 'Yc', 32);
    if (h == null || cpk == null || yc == null || !constantTimeEquals(h, discoveryHandle)) return null;
    if (++_exchanges > _kMaxKeyExchanges) {
      close();
      return null;
    }
    final PakeParty party = await PakeParty.start(
        isChild: false, password: utf8.encode(code), sid: sid, ci: meetChannelId(cpk));
    _key = await party.finish(yc);
    _joinerKey = cpk;
    return <String, dynamic>{'t': 'm2', 'sid': b64(sid), 'Ya': b64(party.share)};
  }

  /// A wrong tag is a wrong code: it is counted, and five end the window.
  Future<Map<String, dynamic>?> _m3(Map<String, dynamic> m) async {
    final PakeKey? key = _key;
    final Uint8List? tagC = _b(m, 'tagC', 32), sidIn = _b(m, 'sid', 16);
    if (key == null || _state != MeetState.open || tagC == null || sidIn == null || !constantTimeEquals(sidIn, sid)) return null;
    if (!await key.checkTag('C', tagC)) {
      _key = null;
      _joinerKey = null;
      if (++_failures >= kMeetMaxAttempts) close();
      return null;
    }
    final Object? introV = m['intro'];
    final Uint8List? plain = introV is String ? await _openUnder(key, _aadIntro, introV) : null;
    MeetIntro? intro;
    if (plain != null) {
      try {
        final Object? j = jsonDecode(utf8.decode(plain));
        if (j is Map) {
          final Object? ak = j['ak'], ac = j['ac'], dn = j['dn'];
          if (ak is String && ac is String && dn is String) {
            final DeviceRecord rec = DeviceRecord(key: _joinerKey!, agree: unb64(ak), cert: unb64(ac));
            // Any other field the new phone sent (a role, a limit) is not read: only the keys and its own name.
            if (await verifyAgreementCert(rec)) intro = MeetIntro(record: rec, deviceName: _cleanDeviceName(dn));
          }
        }
      } catch (_) {}
    }
    if (intro == null) {
      _key = null;
      _joinerKey = null;
      if (++_failures >= kMeetMaxAttempts) close();
      return null;
    }
    _tagC = tagC;
    _intro = intro;
    _sas = Sas.fromBytes(await key.sas());
    _set(MeetState.introduced);
    return <String, dynamic>{'t': 'm4', 'tagA': b64(await key.tag('A'))};
  }

  Future<Map<String, dynamic>?> _m5(Map<String, dynamic> m) async {
    final Uint8List? tagC = _b(m, 'tagC', 32), sidIn = _b(m, 'sid', 16);
    if (_tagC == null || tagC == null || sidIn == null || !constantTimeEquals(sidIn, sid) || !constantTimeEquals(tagC, _tagC!)) {
      return null;
    }
    if (_state == MeetState.offered && _credential != null) return <String, dynamic>{'t': 'cred', 'sealed': _credential};
    return <String, dynamic>{'t': 'wait'};
  }
}

// ---------------------------------------------------------------------------------------------------------------
// The new person's phone
// ---------------------------------------------------------------------------------------------------------------

enum JoinPollKind { waiting, offered, failed }

class JoinPoll {
  const JoinPoll(this.kind, {this.entries = const <LedgerEntry>[], this.votes = const <LedgerVote>[]});
  final JoinPollKind kind;
  final List<LedgerEntry> entries;
  final List<LedgerVote> votes;
}

/// A meeting from the new phone's side. [sas] is shown for the person to compare with the grown-up's screen.
class JoinMeeting {
  JoinMeeting._(this._transport, this._key, this._sid, this._tagC, this.sas, this._device);
  final PairingTransport _transport;
  final PakeKey _key;
  final Uint8List _sid, _tagC;
  final DeviceKey _device;
  final Sas sas;

  /// Asks whether the grown-up has chosen. On an offer, the record is opened and checked: it must reduce to a family
  /// and hold a request that names THIS phone, signed by a grown-up's phone it lists. Anything else is `failed`.
  Future<JoinPoll> poll({required int nowMs}) async {
    final Map<String, dynamic>? r =
        await _transport.send(<String, dynamic>{'t': 'm5', 'sid': b64(_sid), 'tagC': b64(_tagC)});
    if (r == null) return const JoinPoll(JoinPollKind.failed);
    if (r['t'] == 'wait') return const JoinPoll(JoinPollKind.waiting);
    if (r['t'] != 'cred' || r['sealed'] is! String) return const JoinPoll(JoinPollKind.failed);
    final Uint8List? plain = await _openUnder(_key, _aadCred, r['sealed'] as String, maxBytes: kMeetMaxCredentialBytes);
    if (plain == null) return const JoinPoll(JoinPollKind.failed);
    try {
      final Object? j = jsonDecode(utf8.decode(plain));
      if (j is! Map || j['v'] != 1 || j['e'] is! List || j['o'] is! List) return const JoinPoll(JoinPollKind.failed);
      final List<LedgerEntry> es = <LedgerEntry>[];
      for (final Object? x in j['e'] as List) {
        final LedgerEntry? e = await LedgerEntry.fromJson(x);
        if (e == null || !await e.verifySignature()) return const JoinPoll(JoinPollKind.failed);
        es.add(e);
      }
      final List<LedgerVote> vs = <LedgerVote>[
        for (final Object? x in j['o'] as List)
          if (LedgerVote.fromJson(x) != null) LedgerVote.fromJson(x)!,
      ];
      if (es.length > kMaxLedgerEntries || vs.length > kMaxLedgerVotes) return const JoinPoll(JoinPollKind.failed);
      final LedgerState s = await reduceLedger(entries: es, votes: vs, nowMs: nowMs);
      if (!s.ok || findInvitation(s, es, _device.publicKey) == null) return const JoinPoll(JoinPollKind.failed);
      return JoinPoll(JoinPollKind.offered, entries: es, votes: vs);
    } catch (_) {
      return const JoinPoll(JoinPollKind.failed);
    }
  }
}

/// The open request in [entries] that names [deviceKey] as the person to welcome, signed by a listed grown-up phone;
/// the newest one when a smaller offer replaced an earlier one. Null when there is none.
LedgerEntry? findInvitation(LedgerState s, Iterable<LedgerEntry> entries, List<int> deviceKey) {
  final Set<String> open = <String>{for (final PendingItem p in s.pending) if (p.type == EntryType.memberAdd && p.status == 'pending') p.hashHex};
  LedgerEntry? best;
  for (final LedgerEntry e in entries) {
    if (e.type != EntryType.memberAdd || !open.contains(e.hashHex)) continue;
    final DeviceRecord? d = DeviceRecord.fromValue(e.body['dev']);
    if (d == null || !bytesEqual(d.key, deviceKey)) continue;
    if (!s.isActiveGuardianDevice(e.signer)) continue;
    if (best == null || e.issuedAtMs > best.issuedAtMs) best = e;
  }
  return best;
}

/// Starts a meeting from the new phone. [transport] reaches the grown-up’s window (the LAN transport, or a loopback in tests).
class VillageJoiner {
  VillageJoiner({required this.device, required this.agreement, required this.deviceName, Random? random})
      : _random = random ?? Random.secure();
  final DeviceKey device;
  final AgreementKey agreement;
  final String deviceName;
  final Random _random;

  /// Types the code on the grown-up’s window. Null when it did not work (wrong code, closed window, nothing there).
  /// The person is told only "that did not work": never which part.
  Future<JoinMeeting?> meet({required PairingTransport transport, required Uint8List handle, required String code}) async {
    try {
      // The session id is the grown-up’s, so it is asked for first.
      final Map<String, dynamic>? hi = await transport.send(<String, dynamic>{'t': 'm0', 'h': b64(handle)});
      if (hi == null || hi['t'] != 'm0-ok' || hi['sid'] is! String) return null;
      final Uint8List sid = unb64(hi['sid'] as String);
      if (sid.length != 16) return null;
      final PakeParty party = await PakeParty.start(
          isChild: true, password: utf8.encode(code), sid: sid, ci: meetChannelId(device.publicKey));
      final Map<String, dynamic>? m2 = await transport.send(<String, dynamic>{
        't': 'm1', 'h': b64(handle), 'cpk': b64(device.publicKey), 'Yc': b64(party.share),
      });
      if (m2 == null || m2['t'] != 'm2' || m2['Ya'] is! String) return null;
      final PakeKey key = await party.finish(unb64(m2['Ya'] as String));
      final Uint8List tagC = await key.tag('C');
      final String intro = await _sealUnder(
          key, _aadIntro,
          utf8.encode(jsonEncode(<String, Object?>{
            'dn': deviceName, 'ak': b64(agreement.publicKey), 'ac': b64(await agreement.certify(device)),
          })),
          _random);
      final Map<String, dynamic>? m4 =
          await transport.send(<String, dynamic>{'t': 'm3', 'sid': b64(sid), 'tagC': b64(tagC), 'intro': intro});
      if (m4 == null || m4['t'] != 'm4' || m4['tagA'] is! String) return null;
      if (!await key.checkTag('A', unb64(m4['tagA'] as String))) return null;
      return JoinMeeting._(transport, key, sid, tagC, Sas.fromBytes(await key.sas()), device);
    } catch (_) {
      return null;
    }
  }
}
