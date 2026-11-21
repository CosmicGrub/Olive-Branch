// OLIVE BRANCH — adding a second grown-up's phone to the family, over the same Wi-Fi, with a short code typed on one
// phone. UNVERIFIED on a device: the headless tests (client/test/family_join_test.dart) are the only proof so far, and
// the composition has had no outside review (decision D2: the custom key exchange and the ledger need one before real
// families rely on it). Spec: docs/planning/FAMILY-IDENTITY-DESIGN.md (second grown-up joins) and
// docs/planning/FAMILY-SYNC-DESIGN.md (first slice). Android only.
//
// WHY THIS FILE EXISTS. The first family-sync slice and the screen-sharing feature both need a family record with TWO
// grown-up phones in it, and nothing in the app made one. Founding is local (family_state.dart); this is the other half:
// the founding phone welcomes a second phone, hands it the family record and the two family keys, and the second phone
// answers "yes". It does NOT touch the child pairing protocol (pairing_protocol.dart) or channel v2.
//
// HOW IT IS KEPT SAFE.
//  * One-time code. The founding grown-up taps "Add another grown-up's phone"; the phone shows six digits and a two-word
//    label. The other grown-up picks the window with the same label and types the digits. The digits are the PASSWORD of
//    the same password-authenticated key exchange the child pairing uses (cpace.dart, PakeParty), so a person on the
//    Wi-Fi who does not know the digits can neither join nor learn the keys, and a wrong guess cannot be checked offline.
//  * Five tries. A window allows [kJoinMaxStarts] starts and [kJoinMaxWrong] wrong codes, lives five minutes, serves one
//    phone and is used once. After that it is closed; the grown-up opens a new one. (A person on the same Wi-Fi who
//    spams starts can burn a window: a denial of service the grown-up cures by opening another. They cannot join.)
//  * Both screens show the same word and picture from the finished exchange (Sas). The founding grown-up approves only
//    if they match and the name is the person they expect.
//  * Authority. The founder signs a `member.add` for the new phone and the new phone signs its own `yes`: the ledger's
//    own rules (family_ledger_state.dart) apply, so the new phone stays "settling in" for the family's settle hours
//    (24 by default) and a hostile welcome cannot make the joiner believe in another family: the joiner checks that the
//    keys it was handed are the ones the signed genesis commits to, that the family reduces to a valid ledger, and that
//    its own entry is in it. A phone that already belongs to a family REFUSES to join another (it would lose its own).
//  * Only a family with exactly ONE grown-up can add the second this way. Adding a third needs everyone's approval and the
//    ledger gossip between phones, which are not built.
//  * Nothing here is shown to or reachable by a child device: the founder side needs a family record whose keyring is a
//    grown-up's, and the joiner side is the grown-up app's "Join" screen. A child device never builds either.
//
// WHAT THE WIRE SHOWS. After the exchange everything is ChaCha20-Poly1305 under a key from the exchange. The welcome
// holds the family keys, so it is only ever sent after the founding grown-up approved and only to the phone that proved
// the code.
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart' show ChangeNotifier;

import 'cpace.dart' show PakeKey, PakeParty, PakeException, cat, lv;
import 'device_keys.dart' show DeviceKey, b64, unb64;
import 'family_keys.dart';
import 'family_ledger.dart';
import 'family_ledger_state.dart';
import 'family_profiles.dart';
import 'family_state.dart';
import 'pairing_protocol.dart' show PairingTransport, Sas;

const String kJoinLabel = 'olive-join-v1';
const int kJoinCodeDigits = 6;
const int kJoinWindowMs = 5 * 60 * 1000;
const int kJoinMaxStarts = 5;
const int kJoinMaxWrong = 3;
const int kJoinMaxBody = 256 * 1024;
const int kJoinMaxName = 40;

enum JoinState { open, waitingForYou, sending, done, closed }

/// Why a join stopped, in words a grown-up can read. Never a technical term.
String joinRefusalText(String reason) => switch (reason) {
  'has_family' => 'This phone is already part of a family record, so it cannot join another one.',
  'no_window' => "The other phone's window was not found. Ask them to open it again.",
  'code' => 'That code did not match. Check the six digits on the other phone.',
  'declined' => 'The other grown-up said no, so nothing was shared.',
  'timeout' => 'The other phone did not answer in time. Nothing was shared.',
  'finish_later' =>
    'The other phone has what it needs. It finishes the next time the two phones are on the same Wi-Fi.',
  'unreadable' => 'What the other phone sent could not be read, so nothing was changed.',
  'not_alone' => 'Only a family with one grown-up can add another this way for now.',
  'settling' => 'This phone is still settling in, so it cannot add a grown-up yet.',
  _ => 'That did not work. Nothing was changed.',
};

Uint8List _rb(Random r, int n) => Uint8List.fromList(List<int>.generate(n, (_) => r.nextInt(256)));

/// Six digits, uniformly, never starting a pattern the caller must avoid: all digits are drawn independently.
String newJoinCode(Random r) => List<String>.generate(kJoinCodeDigits, (_) => '${r.nextInt(10)}').join();

Uint8List _channelId() => lv(utf8.encode(kJoinLabel));

String _clean(String s, int max) {
  final StringBuffer b = StringBuffer();
  for (final int c in s.runes) {
    if (c >= 32 && c != 127) b.writeCharCode(c);
  }
  final String t = b.toString().trim();
  return t.length <= max ? t : t.substring(0, max);
}

Future<Uint8List> _seal(Uint8List key, String label, List<int> plain, Random r) async {
  final Uint8List nonce = _rb(r, 12);
  final SecretBox box = await Chacha20.poly1305Aead().encrypt(
    plain,
    secretKey: SecretKey(key),
    nonce: nonce,
    aad: utf8.encode('$kJoinLabel/$label'),
  );
  return cat(<List<int>>[nonce, box.cipherText, box.mac.bytes]);
}

Future<Uint8List?> _open(Uint8List key, String label, List<int> sealed) async {
  if (sealed.length < 12 + 16 || sealed.length > kJoinMaxBody) return null;
  try {
    final List<int> plain = await Chacha20.poly1305Aead().decrypt(
      SecretBox(
        sealed.sublist(12, sealed.length - 16),
        nonce: sealed.sublist(0, 12),
        mac: Mac(sealed.sublist(sealed.length - 16)),
      ),
      secretKey: SecretKey(key),
      aad: utf8.encode('$kJoinLabel/$label'),
    );
    return Uint8List.fromList(plain);
  } catch (_) {
    return null;
  }
}

Map<String, Object?>? _jsonMap(List<int> b) {
  try {
    final Object? v = jsonDecode(utf8.decode(b));
    return v is Map<String, Object?> ? v : null;
  } catch (_) {
    return null;
  }
}

Uint8List? _b64(Object? v, int len) {
  if (v is! String || v.length > 4 * len) return null;
  try {
    final Uint8List b = unb64(v);
    return b.length == len ? b : null;
  } catch (_) {
    return null;
  }
}

/// Two words and a picture drawn from a window's random handle. The founding phone shows it beside the code and the
/// joining phone lists nearby windows by it, so a grown-up can pick the right one without a name travelling.
String joinWindowLabel(List<int> handle) => Sas.fromBytes(<int>[handle[0], handle[1]]).toString();

// ============================================================================================ the founding side ===

/// The founding grown-up's open window. In memory only; closes by itself.
class FamilyJoinWindow extends ChangeNotifier {
  FamilyJoinWindow({
    required this.context,
    required this.repo,
    required this.nowMs,
    Random? random,
    String? codeForTest,
  }) : _r = random ?? Random.secure(),
       code = codeForTest ?? newJoinCode(random ?? Random.secure()) {
    handle = _rb(_r, 16);
    openedAt = nowMs();
  }

  final FamilyContext context;
  final FamilyRepository repo;
  final int Function() nowMs;
  final Random _r;

  /// The six digits the grown-up reads out. Never sent on the wire, never logged.
  final String code;
  late final Uint8List handle;
  late final int openedAt;

  JoinState _state = JoinState.open;
  JoinState get state => _state;

  /// The name the other phone gave, once it proved the code. Shown to the founding grown-up to approve.
  String? guestName;
  Sas? sas;

  /// Set when the window ended without a join, in words ([joinRefusalText] keys).
  String? endedBecause;

  int _starts = 0, _wrong = 0;
  Uint8List? _sid;
  PakeKey? _key;
  Uint8List? _chan;
  _Offer? _offer;
  Uint8List? _welcome;
  LedgerEntry? _entry;
  bool _declined = false;
  Timer? _timer;

  String get label => joinWindowLabel(handle);
  bool get expired => nowMs() - openedAt > kJoinWindowMs;

  void _set(JoinState s) {
    _state = s;
    notifyListeners();
  }

  /// Ends the window. Whatever was not yet agreed is dropped; an agreed join is not undone.
  void close([String? because]) {
    if (_state == JoinState.closed) return;
    if (_state != JoinState.done) endedBecause = because ?? endedBecause;
    _key = null;
    _chan = null;
    _welcome = null;
    _timer?.cancel();
    _set(JoinState.closed);
  }

  bool get _live => _state != JoinState.closed && _state != JoinState.done && (_welcome != null || !expired);

  /// One message from the other phone. Null means "no answer" (a closed or foreign window answers nothing).
  Future<Map<String, dynamic>?> onMessage(Map<String, dynamic> m) async {
    if (!_live) {
      if (_state != JoinState.closed && _state != JoinState.done) close('timeout');
      return null;
    }
    try {
      switch (m['t']) {
        case 'j0':
          return _j0();
        case 'j1':
          return await _j1(m);
        case 'j2':
          return await _j2(m);
        case 'j3':
          return _j3();
        case 'j4':
          return await _j4(m);
      }
    } on PakeException {
      return null;
    } catch (_) {
      return null;
    }
    return null;
  }

  Map<String, dynamic>? _j0() {
    if (_state != JoinState.open) return null;
    if (++_starts > kJoinMaxStarts) {
      close('code');
      return null;
    }
    _sid = _rb(_r, 16);
    _key = null;
    return <String, dynamic>{'t': 'j0', 'sid': b64(_sid!)};
  }

  Future<Map<String, dynamic>?> _j1(Map<String, dynamic> m) async {
    final Uint8List? sid = _sid, y = _b64(m['y'], 32);
    if (_state != JoinState.open || sid == null || y == null) return null;
    final PakeParty me = await PakeParty.start(isChild: false, password: utf8.encode(code), sid: sid, ci: _channelId());
    _key = await me.finish(y);
    _sid = null; // one share per start
    return <String, dynamic>{'t': 'j1', 'y': b64(me.share), 'a': b64(await _key!.tag('A'))};
  }

  Future<Map<String, dynamic>?> _j2(Map<String, dynamic> m) async {
    final PakeKey? k = _key;
    final Uint8List? c = _b64(m['c'], 32);
    final Object? o = m['o'];
    if (_state != JoinState.open || k == null || c == null || o is! String || o.length > kJoinMaxBody) return null;
    if (!await k.checkTag('C', c)) {
      _key = null;
      if (++_wrong >= kJoinMaxWrong) close('code');
      return null;
    }
    final Uint8List chan = await k.channelKey();
    final Uint8List? plain = await _open(chan, 'offer', unb64(o));
    final _Offer? offer = plain == null ? null : await _Offer.parse(plain);
    if (offer == null) {
      close('unreadable');
      return null;
    }
    _chan = chan;
    _offer = offer;
    guestName = offer.name;
    sas = Sas.fromBytes(await k.sas());
    _set(JoinState.waitingForYou);
    return <String, dynamic>{'t': 'j2', 'w': 1};
  }

  Map<String, dynamic>? _j3() {
    if (_declined) {
      close('declined');
      return <String, dynamic>{'t': 'j3', 'd': 1};
    }
    final Uint8List? w = _welcome;
    if (w != null) return <String, dynamic>{'t': 'j3', 'w': b64(w)};
    if (_state == JoinState.waitingForYou || _state == JoinState.sending) return <String, dynamic>{'t': 'j3', 'p': 1};
    return null;
  }

  Future<Map<String, dynamic>?> _j4(Map<String, dynamic> m) async {
    final Uint8List? chan = _chan, e = _entry?.hash;
    final Object? v = m['v'];
    if (chan == null || e == null || v is! String || v.length > kJoinMaxBody) return null;
    final Uint8List? plain = await _open(chan, 'yes', unb64(v));
    final Map<String, Object?>? j = plain == null ? null : _jsonMap(plain);
    final LedgerVote? vote = j == null ? null : LedgerVote.fromJson(j['vote']);
    if (vote == null || !await vote.verifySignature() || vote.answer != 'yes' || !bytesEqual(vote.target, e)) {
      return null;
    }
    if (!bytesEqual(vote.voter, _offer!.dev.key)) return null;
    // The record as it is stored NOW: approve() added the welcome entry after this window was opened.
    final FamilyContext? fresh = await FamilyContext.load(repo, context.device, nowMs: nowMs());
    if (fresh == null) return null;
    final FamilyContext? c = await mergeLedger(
      context: fresh,
      repo: repo,
      entries: const <LedgerEntry>[],
      votes: <LedgerVote>[vote],
      nowMs: nowMs(),
    );
    if (c == null) return null;
    // The other phone's clock may be a moment ahead of this one: a yes dated after this phone's "now" only counts once
    // this phone's clock reaches it, so the answer is judged as of the vote's own time (the record itself is unchanged).
    final LedgerState after = await c.state(nowMs: max(nowMs(), vote.atMs));
    if (!after.isActiveGuardianDevice(_offer!.dev.key)) return null; // the vote did not take: say nothing
    _set(JoinState.done);
    _timer?.cancel();
    return <String, dynamic>{'t': 'j4', 'ok': 1};
  }

  /// The founding grown-up compared the pictures and said yes. Signs the welcome and stores it, ready for the other
  /// phone to collect. Returns null on success or a [joinRefusalText] key.
  Future<String?> approve() async {
    final _Offer? offer = _offer;
    final Uint8List? chan = _chan;
    if (_state != JoinState.waitingForYou || offer == null || chan == null) return 'timeout';
    _set(JoinState.sending);
    try {
      final int now = nowMs();
      final LedgerState st = await context.state(nowMs: now);
      if (!st.ok || !st.isActiveGuardianDevice(context.device.publicKey)) {
        close('unreadable');
        return 'unreadable';
      }
      if (st.isSettling(context.device.publicKey, now)) {
        close('settling');
        return 'settling';
      }
      if (st.members.where((LedgerMember m) => m.isGuardian).length != 1) {
        close('not_alone');
        return 'not_alone';
      }
      final LedgerDevice me = st.deviceFor(context.device.publicKey)!;
      final MemberProfile profile = MemberProfile.defaults(Preset.parent);
      final LedgerEntry entry = await LedgerEntry.sign(
        context.device,
        type: EntryType.memberAdd,
        prev: st.heads,
        issuedAtMs: now,
        body: <String, Object?>{
          'gid': offer.gid,
          'name': offer.name,
          'kind': 'guardian',
          'profile': profile.toValue(),
          'dev': offer.dev.toValue(),
          'proposal': <String, Object?>{
            'id': _rb(_r, 16),
            'exp': now + proposalLifetimeMs(Preset.parent),
            'electorate': <Uint8List>[fromHex(me.gidHex!)],
            'rule': 'all',
          },
        },
      );
      final List<LedgerEntry> entries = <LedgerEntry>[...context.entries, entry];
      final LedgerState after = await reduceLedger(
        entries: entries,
        votes: context.votes,
        nowMs: now,
        pin: context.pin,
      );
      if (!after.ok || after.rejected.containsKey(entry.hashHex)) {
        close('unreadable');
        return 'unreadable';
      }
      final FamilySnapshot snap = FamilySnapshot(
        entries: entries,
        votes: List<LedgerVote>.of(context.votes),
        agreementSeed: context.agreement.seed,
        guardianDevice: true,
        fk: <int, Uint8List>{for (final int e in context.keyring.fkEpochs) e: context.keyring.fk(e)!},
        gk: <int, Uint8List>{for (final int e in context.keyring.gkEpochs) e: context.keyring.gk(e)!},
      );
      if (context.keyring.fkEpochs.length != 1 ||
          context.keyring.fkEpochs.first != 0 ||
          context.keyring.gkEpochs.length != 1) {
        close('unreadable'); // a rotated family needs the rotation flow, which is not built
        return 'unreadable';
      }
      await repo.save(snap);
      _entry = entry;
      _welcome = await _seal(
        chan,
        'welcome',
        utf8.encode(
          jsonEncode(<String, Object?>{
            'v': 1,
            'entries': <Object?>[for (final LedgerEntry e in snap.entries) e.toJson()],
            'votes': <Object?>[for (final LedgerVote v in snap.votes) v.toJson()],
            'fk0': b64(snap.fk[0]!),
            'gk0': b64(snap.gk[0]!),
          }),
        ),
        _r,
      );
      _timer = Timer(const Duration(minutes: 2), () => close('finish_later'));
      _set(JoinState.sending);
      return null;
    } catch (_) {
      close('unreadable');
      return 'unreadable';
    }
  }

  void decline() {
    _declined = true;
    notifyListeners();
    // The other phone learns this on its next poll; the window then closes.
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 20), () => close('declined'));
  }
}

class _Offer {
  _Offer(this.name, this.gid, this.dev);
  final String name;
  final Uint8List gid;
  final DeviceRecord dev;

  static Future<_Offer?> parse(Uint8List plain) async {
    final Map<String, Object?>? j = _jsonMap(plain);
    if (j == null || j['v'] != 1) return null;
    final Object? name = j['name'], dev = j['dev'];
    final Uint8List? gid = _b64(j['gid'], 16);
    if (name is! String || gid == null || dev is! Map) return null;
    final Uint8List? key = _b64(dev['key'], 32), agree = _b64(dev['agree'], 32), cert = _b64(dev['cert'], 64);
    if (key == null || agree == null || cert == null) return null;
    final String clean = _clean(name, kJoinMaxName);
    if (clean.isEmpty) return null;
    final DeviceRecord rec = DeviceRecord(key: key, agree: agree, cert: cert);
    if (!await verifyAgreementCert(rec)) return null;
    return _Offer(clean, gid, rec);
  }
}

// ============================================================================================ the joining side ===

class JoinOutcome {
  const JoinOutcome.ok(this.context) : reason = null, sas = null;
  const JoinOutcome.no(this.reason) : context = null, sas = null;
  final FamilyContext? context;

  /// A [joinRefusalText] key when it did not work.
  final String? reason;
  final Sas? sas;
  bool get ok => context != null;
}

/// The joining phone. [transport] reaches one founding window.
class FamilyJoinGuest {
  FamilyJoinGuest({
    required this.transport,
    required this.device,
    required this.repo,
    required this.nowMs,
    Random? random,
    this.pollEvery = const Duration(seconds: 1),
    this.waitFor = const Duration(minutes: 3),
  }) : _r = random ?? Random.secure();

  final PairingTransport transport;
  final DeviceKey device;
  final FamilyRepository repo;
  final int Function() nowMs;
  final Random _r;
  final Duration pollEvery, waitFor;

  /// Runs the whole join. [onWords] is told the word and picture to compare with the other screen, as soon as they are
  /// known (the other grown-up approves only if they match). Never throws.
  Future<JoinOutcome> join({required String code, required String name, void Function(Sas words)? onWords}) async {
    try {
      if (await repo.hasRecord()) return const JoinOutcome.no('has_family');
      final String clean = _clean(name, kJoinMaxName);
      if (clean.isEmpty || !RegExp(r'^\d{6}$').hasMatch(code)) return const JoinOutcome.no('code');
      final Map<String, dynamic>? a0 = await transport.send(<String, dynamic>{'t': 'j0'});
      final Uint8List? sid = a0 == null ? null : _b64(a0['sid'], 16);
      if (sid == null) return const JoinOutcome.no('no_window');
      final PakeParty me = await PakeParty.start(
        isChild: true,
        password: utf8.encode(code),
        sid: sid,
        ci: _channelId(),
      );
      final Map<String, dynamic>? a1 = await transport.send(<String, dynamic>{'t': 'j1', 'y': b64(me.share)});
      final Uint8List? yb = a1 == null ? null : _b64(a1['y'], 32), tagA = a1 == null ? null : _b64(a1['a'], 32);
      if (yb == null || tagA == null) return const JoinOutcome.no('no_window');
      final PakeKey key = await me.finish(yb);
      if (!await key.checkTag('A', tagA)) return const JoinOutcome.no('code');
      final Uint8List chan = await key.channelKey();
      final Sas words = Sas.fromBytes(await key.sas());
      onWords?.call(words);
      // The agreement key this phone will keep for the family. Made now, kept only if the join finishes.
      final AgreementKey agree = await AgreementKey.fromSeed(_rb(_r, 32));
      final Uint8List cert = await agree.certify(device);
      final Uint8List gid = _rb(_r, 16);
      final Uint8List offer = await _seal(
        chan,
        'offer',
        utf8.encode(
          jsonEncode(<String, Object?>{
            'v': 1,
            'name': clean,
            'gid': b64(gid),
            'dev': <String, Object?>{'key': b64(device.publicKey), 'agree': b64(agree.publicKey), 'cert': b64(cert)},
          }),
        ),
        _r,
      );
      final Map<String, dynamic>? a2 = await transport.send(<String, dynamic>{
        't': 'j2',
        'c': b64(await key.tag('C')),
        'o': b64(offer),
      });
      if (a2 == null) return const JoinOutcome.no('code');
      final DateTime stop = DateTime.now().add(waitFor);
      Uint8List? welcome;
      while (DateTime.now().isBefore(stop)) {
        final Map<String, dynamic>? a3 = await transport.send(<String, dynamic>{'t': 'j3'});
        if (a3 == null) return const JoinOutcome.no('timeout');
        if (a3['d'] == 1) return const JoinOutcome.no('declined');
        final Object? w = a3['w'];
        if (w is String && w.length <= 2 * kJoinMaxBody) {
          welcome = unb64(w);
          break;
        }
        await Future<void>.delayed(pollEvery);
      }
      if (welcome == null) return const JoinOutcome.no('timeout');
      final Uint8List? plain = await _open(chan, 'welcome', welcome);
      final FamilyContext? ctx = plain == null ? null : await _accept(plain, agree);
      if (ctx == null) return const JoinOutcome.no('unreadable');
      // Tell the founding phone at once; if this is lost, the next time the phones meet carries the answer.
      final LedgerVote mine = ctx.votes.firstWhere((LedgerVote v) => bytesEqual(v.voter, device.publicKey));
      final Uint8List yes = await _seal(
        chan,
        'yes',
        utf8.encode(jsonEncode(<String, Object?>{'vote': mine.toJson()})),
        _r,
      );
      try {
        await transport.send(<String, dynamic>{'t': 'j4', 'v': b64(yes)});
      } catch (_) {}
      return JoinOutcome.ok(ctx);
    } catch (_) {
      return const JoinOutcome.no('unreadable');
    }
  }

  /// Checks the welcome and, only if every check passes, stores the family. Null otherwise; nothing is written.
  Future<FamilyContext?> _accept(Uint8List plain, AgreementKey agree) async {
    final Map<String, Object?>? j = _jsonMap(plain);
    if (j == null || j['v'] != 1) return null;
    final Object? es = j['entries'], vs = j['votes'];
    final Uint8List? fk = _b64(j['fk0'], 32), gk = _b64(j['gk0'], 32);
    if (es is! List || vs is! List || fk == null || gk == null || es.length > 64 || vs.length > 256) return null;
    final List<LedgerEntry> entries = <LedgerEntry>[];
    for (final Object? e in es) {
      final LedgerEntry? x = await LedgerEntry.fromJson(e);
      if (x == null) return null;
      entries.add(x);
    }
    final List<LedgerVote> votes = <LedgerVote>[];
    for (final Object? v in vs) {
      final LedgerVote? x = LedgerVote.fromJson(v);
      if (x == null) return null;
      votes.add(x);
    }
    final int now = nowMs();
    LedgerState st = await reduceLedger(entries: entries, votes: votes, nowMs: now);
    if (!st.ok || st.epoch != 0) return null;
    // The keys must be the ones the signed genesis commits to: a hostile welcome cannot hand over other keys.
    final LedgerEntry genesis = entries.firstWhere((LedgerEntry e) => e.type == EntryType.genesis);
    if (!bytesEqual(genesis.hash, st.genesisHash!)) return null;
    if (!bytesEqual(genesis.body['fkc'] as Uint8List, await keyCommit('fk', st.fid!, 0, fk))) return null;
    if (!bytesEqual(genesis.body['gkc'] as Uint8List, await keyCommit('gk', st.fid!, 0, gk))) return null;
    // Our own entry must be there, welcoming a grown-up with exactly the device this phone gave.
    LedgerEntry? mine;
    for (final LedgerEntry e in entries) {
      if (e.type != EntryType.memberAdd) continue;
      final DeviceRecord? d = DeviceRecord.fromValue(e.body['dev']);
      if (d != null && bytesEqual(d.key, device.publicKey) && bytesEqual(d.agree ?? const <int>[], agree.publicKey)) {
        mine = e;
      }
    }
    if (mine == null || st.rejected.containsKey(mine.hashHex)) return null;
    if (mine.body['kind'] != 'guardian') return null;
    if (!st.pending.any((PendingItem p) => p.hashHex == mine!.hashHex && p.status == 'pending')) return null;
    final int at = max(now, mine.issuedAtMs + 1);
    final LedgerVote yes = await LedgerVote.sign(device, target: mine.hash, answer: 'yes', atMs: at);
    final List<LedgerVote> all = <LedgerVote>[...votes, yes];
    st = await reduceLedger(entries: entries, votes: all, nowMs: max(now, at + 1));
    if (!st.ok || st.deviceFor(device.publicKey) == null) return null;
    final FamilySnapshot snap = FamilySnapshot(
      entries: entries,
      votes: all,
      agreementSeed: agree.seed,
      guardianDevice: true,
      fk: <int, Uint8List>{0: fk},
      gk: <int, Uint8List>{0: gk},
    );
    if (await repo.hasRecord()) return null; // raced with something else: never replace a record
    await repo.save(snap);
    return FamilyContext.load(repo, device, nowMs: max(now, at + 1));
  }
}

// ======================================================================================== the ledger gossip ===

const int kMergeMaxEntries = 400;
const int kMergeMaxVotes = 800;

/// Takes the ledger entries and votes another phone holds that this phone does not, keeps only what reduces to a valid
/// family under THIS phone's pinned genesis, and stores the result. Returns the new context, the same one when there was
/// nothing new, or null when this phone's own record is unusable. Entries the ledger rejects are not kept. Never lets a
/// peer remove an entry or change the genesis.
Future<FamilyContext?> mergeLedger({
  required FamilyContext context,
  required FamilyRepository repo,
  required Iterable<LedgerEntry> entries,
  required Iterable<LedgerVote> votes,
  required int nowMs,
}) async {
  final Set<String> have = <String>{for (final LedgerEntry e in context.entries) e.hashHex};
  // A peer can add to the family record, never replace its beginning: a second genesis is never taken.
  final List<LedgerEntry> fresh = <LedgerEntry>[
    for (final LedgerEntry e in entries)
      if (e.type != EntryType.genesis && have.add(e.hashHex)) e,
  ];
  final Set<String> haveV = <String>{
    for (final LedgerVote v in context.votes) '${v.targetHex}:${v.voterHex}:${v.answer}:${v.atMs}',
  };
  final List<LedgerVote> freshV = <LedgerVote>[
    for (final LedgerVote v in votes)
      if (haveV.add('${v.targetHex}:${v.voterHex}:${v.answer}:${v.atMs}')) v,
  ];
  if (fresh.isEmpty && freshV.isEmpty) return context;
  if (context.entries.length + fresh.length > kMergeMaxEntries ||
      context.votes.length + freshV.length > kMergeMaxVotes) {
    return context;
  }
  for (final LedgerVote v in freshV) {
    if (!await v.verifySignature()) return context;
  }
  final List<LedgerEntry> allE = <LedgerEntry>[...context.entries, ...fresh];
  final List<LedgerVote> allV = <LedgerVote>[...context.votes, ...freshV];
  final LedgerState st = await reduceLedger(entries: allE, votes: allV, nowMs: nowMs, pin: context.pin);
  if (!st.ok) return context;
  // Keep what the ledger accepted; a refused entry is dropped, never stored.
  final List<LedgerEntry> keepE = <LedgerEntry>[
    ...context.entries,
    for (final LedgerEntry e in fresh)
      if (!st.rejected.containsKey(e.hashHex)) e,
  ];
  final Set<String> known = <String>{for (final LedgerEntry e in keepE) e.hashHex};
  final List<LedgerVote> keepV = <LedgerVote>[
    ...context.votes,
    for (final LedgerVote v in freshV)
      if (known.contains(v.targetHex)) v,
  ];
  if (keepE.length == context.entries.length && keepV.length == context.votes.length) return context;
  final FamilySnapshot snap = FamilySnapshot(
    entries: keepE,
    votes: keepV,
    agreementSeed: context.agreement.seed,
    guardianDevice: context.keyring.guardianDevice,
    fk: <int, Uint8List>{for (final int e in context.keyring.fkEpochs) e: context.keyring.fk(e)!},
    gk: <int, Uint8List>{for (final int e in context.keyring.gkEpochs) e: context.keyring.gk(e)!},
  );
  await repo.save(snap);
  return FamilyContext.load(repo, context.device, nowMs: nowMs);
}
