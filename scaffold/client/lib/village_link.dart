// OLIVE BRANCH — the road between two grown-up phones for the village welcome: how a phone folds a signed update from
// another phone into its own family record, how an update is sealed to ONE phone, and the "door" a phone answers on
// the same Wi-Fi. UNVERIFIED on a device; pure Dart, runs headless in CI (client/test/village_link_test.dart).
// Spec: docs/planning/VILLAGE-WELCOME-DESIGN.md sections 3.2 and 3.3 (a request travels as signed entries and votes,
// with no server) and docs/planning/FAMILY-IDENTITY-DESIGN.md section 3.2 (gossip). The reduce rule that decides what
// any of it MEANS is family_ledger_state.dart; nothing here decides who is welcomed.
//
// WHAT TRAVELS. Signed ledger entries and signed votes, nothing else. Each is verified by its own signature on arrival,
// so a phone that carries them (a stranger's, a replay, a phone that left) cannot make one up. An update is sealed
// (ephemeral X25519 to the receiving phone's certified agreement key, HKDF, ChaCha20-Poly1305) and signed by the
// sending device, so a bystander on the Wi-Fi sees ciphertext only, and the receiver knows which phone sent it.
//
// WHO MAY SEND AND RECEIVE. A phone sends to the devices the family record lists as a grown-up's or a carer's phone, and
// to a person who has been introduced and has a request waiting (the candidate named inside a pending `member.add`).
// A phone ACCEPTS an update only from one of those. A child's tablet is never a peer. A stranger's phone is not.
//
// FOLDING IT IN ([mergeLedger]). All or nothing. The incoming entries and votes are checked one by one (a canonical
// parse, a good signature, a known kind, a voter this family knows), the combined record is reduced WITH the family
// pin, and if it no longer reduces to this family nothing is kept. Votes and entries already held are skipped, so an
// update delivered twice, or a year later, changes nothing. The record is bounded (entries, votes, bytes).
//
// HONEST LIMITS. A phone listed as a peer can hand over junk that fills the bounded record (it cannot make a yes: the
// reduce rule counts only the right people, and every item is signed). A welcomed carer's phone receives the signed
// record too (it shows the carer only their own status); whether a carer should hold the whole record is an owner
// question. Keys: a newly welcomed phone gets the signed record here but NOT the family keys (no `key.rotate` is
// signed by this wave), so it cannot open sealed family sync yet. This composition has had no outside review (the same
// stance as screen_share.dart and family_keys.dart, decision D2).
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'cpace.dart' show cat, lv;
import 'device_keys.dart' show DeviceKey, b64, unb64;
import 'family_keys.dart' show FamilyKeyring;
import 'family_ledger.dart';
import 'family_ledger_state.dart';
import 'family_profiles.dart' show kMsPerDay;
import 'family_state.dart';

const String kVillageUpdateLabel = 'olive-village-update-v1';
const String _updateInfo = 'olive/village/update/v1';

/// The largest sealed update a phone will open, and the most it will hold in one request body.
const int kVillageMaxUpdateBytes = 1024 * 1024;
const int kVillageMaxDoorBytes = 2 * 1024 * 1024;

/// An update older than this, or from further ahead than clock skew, is not opened (a replay of a very old one).
const int kVillageUpdateMaxAgeMs = 30 * kMsPerDay;
const int _skewMs = 5 * 60 * 1000;

/// The kinds of phone that can be sent to: a grown-up's, a carer's, or a person whose request is waiting.
class VillagePeer {
  const VillagePeer({required this.deviceKey, required this.agree, required this.name, required this.kind});
  final Uint8List deviceKey, agree;
  final String name;

  /// 'guardian', 'carer' or 'candidate'.
  final String kind;
  String get keyHex => hexOf(deviceKey);
}

DeviceRecord? _devOf(LedgerEntry e) => DeviceRecord.fromValue(e.body['dev']);

/// The people whose requests are still open, from the record: the candidate's phone as the `member.add` named it.
List<VillagePeer> pendingCandidates(LedgerState s, Iterable<LedgerEntry> entries) {
  if (!s.ok) return const <VillagePeer>[];
  final Set<String> open = <String>{for (final PendingItem p in s.pending) if (p.type == EntryType.memberAdd && p.status == 'pending') p.hashHex};
  final List<VillagePeer> out = <VillagePeer>[];
  for (final LedgerEntry e in entries) {
    if (e.type != EntryType.memberAdd || !open.contains(e.hashHex)) continue;
    final DeviceRecord? d = _devOf(e);
    final Object? name = e.body['name'];
    if (d == null || d.agree == null || name is! String) continue;
    out.add(VillagePeer(deviceKey: d.key, agree: d.agree!, name: name, kind: 'candidate'));
  }
  return out;
}

/// Everyone this phone may send an update to: the listed grown-up and carer phones (not this one, not a tablet) and the
/// waiting candidates. A device with no agreement key cannot be sealed to and is left out.
List<VillagePeer> villagePeers(LedgerState s, Iterable<LedgerEntry> entries, List<int> ownKey) {
  if (!s.ok) return const <VillagePeer>[];
  final String own = hexOf(ownKey);
  final Map<String, String> names = <String, String>{for (final LedgerMember m in s.members) m.gidHex: m.name};
  final List<VillagePeer> out = <VillagePeer>[];
  for (final LedgerDevice d in s.devices) {
    if ((d.kind != 'guardian' && d.kind != 'carer') || d.agree == null || d.keyHex == own) continue;
    out.add(VillagePeer(deviceKey: d.key, agree: d.agree!, name: names[d.gidHex ?? ''] ?? d.name, kind: d.kind));
  }
  for (final VillagePeer c in pendingCandidates(s, entries)) {
    if (c.keyHex != own && !out.any((VillagePeer p) => p.keyHex == c.keyHex)) out.add(c);
  }
  return out;
}

/// True when [key] is a phone the record lists as a grown-up's or carer's, or a waiting candidate.
bool senderAllowed(LedgerState s, Iterable<LedgerEntry> entries, List<int> key) {
  if (!s.ok) return false;
  final LedgerDevice? d = s.deviceFor(key);
  if (d != null) return d.kind == 'guardian' || d.kind == 'carer';
  final String k = hexOf(key);
  return pendingCandidates(s, entries).any((VillagePeer p) => p.keyHex == k);
}

// ---------------------------------------------------------------------------------------------------------------
// Folding an update in
// ---------------------------------------------------------------------------------------------------------------

class MergeResult {
  const MergeResult(this.newEntries, this.newVotes, [this.refused]);
  final int newEntries, newVotes;

  /// Null when it was folded in. Otherwise a short code: 'not-this-family', 'too-many'.
  final String? refused;
  bool get ok => refused == null;
  bool get changed => ok && (newEntries > 0 || newVotes > 0);
}

String _voteId(LedgerVote v) => '${v.targetHex}|${v.voterHex}|${v.answer}|${v.atMs}';

/// Rejections that are only "not yet" (a clock a little ahead), so the entry is kept. Every other rejection is final and
/// the entry is not kept. An orphan (its parent is not held) is dropped too: a phone always sends its whole record, so a
/// parent that is missing from the batch is missing for good (another family's entries, or junk).
const Set<String> _transientRejects = <String>{'from-the-future'};

/// Folds [entries] and [votes] into [ctx] (in memory; the caller saves). Never throws for hostile input.
Future<MergeResult> mergeLedger({
  required FamilyContext ctx,
  required Iterable<LedgerEntry> entries,
  required Iterable<LedgerVote> votes,
  required int nowMs,
}) async {
  final Set<String> haveE = <String>{for (final LedgerEntry e in ctx.entries) e.hashHex};
  final Set<String> haveV = <String>{for (final LedgerVote v in ctx.votes) _voteId(v)};
  final List<LedgerEntry> fresh = <LedgerEntry>[];
  final Set<String> seenE = <String>{};
  for (final LedgerEntry e in entries) {
    if (haveE.contains(e.hashHex) || !seenE.add(e.hashHex)) continue;
    if (!EntryType.all.contains(e.type) || e.type == EntryType.genesis) continue; // the family's genesis is already pinned
    if (!await e.verifySignature()) continue;
    fresh.add(e);
  }
  if (ctx.entries.length + fresh.length > kMaxLedgerEntries) return const MergeResult(0, 0, 'too-many');
  final List<LedgerEntry> combined = <LedgerEntry>[...ctx.entries, ...fresh];
  // Voters this family could know: every device in the record, and every candidate a member.add in the batch names.
  final LedgerState probe = await reduceLedger(entries: combined, votes: ctx.votes, nowMs: nowMs, pin: ctx.pin);
  if (!probe.ok) return const MergeResult(0, 0, 'not-this-family');
  final Set<String> voters = <String>{
    for (final LedgerDevice d in probe.devices) d.keyHex,
    for (final LedgerEntry e in combined)
      if (e.type == EntryType.memberAdd && _devOf(e) != null) hexOf(_devOf(e)!.key),
  };
  final List<LedgerVote> candidateVotes = <LedgerVote>[];
  final Set<String> seenV = <String>{};
  for (final LedgerVote v in votes) {
    final String id = _voteId(v);
    if (haveV.contains(id) || !seenV.add(id)) continue;
    if (!voters.contains(v.voterHex) || v.atMs > nowMs + _skewMs) continue;
    if (!await v.verifySignature()) continue;
    candidateVotes.add(v);
  }
  // Which of the new entries does this family accept? (Reduced with the new votes too, so an entry signed by someone
  // who is only admitted by votes in this same batch is judged as it will be once they are in.)
  final LedgerState st = await reduceLedger(entries: combined, votes: <LedgerVote>[...ctx.votes, ...candidateVotes], nowMs: nowMs, pin: ctx.pin);
  if (!st.ok) return const MergeResult(0, 0, 'not-this-family');
  final List<LedgerEntry> keep = <LedgerEntry>[
    for (final LedgerEntry e in fresh)
      if (!st.rejected.containsKey(e.hashHex) || _transientRejects.contains(st.rejected[e.hashHex])) e,
  ];
  // A vote is kept only for a request this phone holds: a vote about another family's entry, or one that names nothing
  // here, is dropped.
  final Set<String> held = <String>{for (final LedgerEntry e in ctx.entries) e.hashHex, for (final LedgerEntry e in keep) e.hashHex};
  final List<LedgerVote> freshV = <LedgerVote>[for (final LedgerVote v in candidateVotes) if (held.contains(v.targetHex)) v];
  if (ctx.votes.length + freshV.length > kMaxLedgerVotes) return const MergeResult(0, 0, 'too-many');
  ctx.entries.addAll(keep);
  ctx.votes.addAll(freshV);
  return MergeResult(keep.length, freshV.length);
}

// ---------------------------------------------------------------------------------------------------------------
// An update, sealed to one phone
// ---------------------------------------------------------------------------------------------------------------

class OpenedUpdate {
  const OpenedUpdate(this.fromKey, this.entries, this.votes);
  final Uint8List fromKey;
  final List<LedgerEntry> entries;
  final List<LedgerVote> votes;
}

Uint8List _rb(Random r, int n) => Uint8List.fromList(List<int>.generate(n, (_) => r.nextInt(256)));

Uint8List _header(List<int> from, List<int> to, int iat, List<int> eph) =>
    cat(<List<int>>[lv(utf8.encode(kVillageUpdateLabel)), lv(from), lv(to), lv(ascii.encode('$iat')), lv(eph)]);

Future<SecretKey> _updateKey(List<int> shared, List<int> eph, List<int> recipientAgree) =>
    Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
        secretKey: SecretKey(shared), nonce: cat(<List<int>>[lv(eph), lv(recipientAgree)]), info: utf8.encode(_updateInfo));

/// Seals the whole held record (or the part given) to [to], signed by [sender]. Returns base64url text for the wire.
Future<String> sealVillageUpdate({
  required DeviceKey sender,
  required VillagePeer to,
  required Iterable<LedgerEntry> entries,
  required Iterable<LedgerVote> votes,
  required int nowMs,
  Random? random,
}) async {
  final Random r = random ?? Random.secure();
  final SimpleKeyPair eph = await X25519().newKeyPairFromSeed(_rb(r, 32));
  final Uint8List ephPub = Uint8List.fromList((await eph.extractPublicKey()).bytes);
  final Uint8List shared = Uint8List.fromList(await (await X25519().sharedSecretKey(
          keyPair: eph, remotePublicKey: SimplePublicKey(to.agree, type: KeyPairType.x25519)))
      .extractBytes());
  final Uint8List header = _header(sender.publicKey, to.deviceKey, nowMs, ephPub);
  final SecretBox box = await Chacha20.poly1305Aead().encrypt(
      utf8.encode(jsonEncode(<String, Object?>{
        'v': 1,
        'e': <Object?>[for (final LedgerEntry e in entries) e.toJson()],
        'o': <Object?>[for (final LedgerVote v in votes) v.toJson()],
      })),
      secretKey: await _updateKey(shared, ephPub, to.agree),
      nonce: Uint8List(12), // the key is unique to this one ephemeral, so a fixed nonce is safe
      aad: header);
  final Uint8List ct = cat(<List<int>>[box.cipherText, box.mac.bytes]);
  final Uint8List sig = await sender.sign(cat(<List<int>>[header, lv(ct)]));
  return b64(utf8.encode(jsonEncode(<String, Object?>{
    'v': 1, 'from': b64(sender.publicKey), 'to': b64(to.deviceKey), 'iat': nowMs, 'eph': b64(ephPub), 'ct': b64(ct), 'sig': b64(sig),
  })));
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

/// Opens an update addressed to THIS phone. Null for anything wrong: not for this phone, from this phone, from a phone
/// the record does not allow ([isAllowed] decides), too old or from the future, a bad signature, a changed byte, or a
/// body that is not entries and votes in the closed shape. Signatures of the entries and votes inside are checked by
/// [mergeLedger], not here.
Future<OpenedUpdate?> openVillageUpdate({
  required String sealed,
  required DeviceKey own,
  required AgreementKey agreement,
  required bool Function(Uint8List from) isAllowed,
  required int nowMs,
}) async {
  if (sealed.length > 2 * kVillageMaxUpdateBytes) return null;
  try {
    final Object? top = jsonDecode(utf8.decode(unb64(sealed)));
    if (top is! Map<String, Object?> || top['v'] != 1) return null;
    final Uint8List? from = _field(top, 'from', 32), to = _field(top, 'to', 32), eph = _field(top, 'eph', 32), sig = _field(top, 'sig', 64);
    final Object? iat = top['iat'], ctV = top['ct'];
    if (from == null || to == null || eph == null || sig == null || iat is! int || ctV is! String) return null;
    if (!bytesEqual(to, own.publicKey) || bytesEqual(from, own.publicKey)) return null;
    if (iat > nowMs + _skewMs || nowMs - iat > kVillageUpdateMaxAgeMs) return null;
    if (!isAllowed(from)) return null;
    final Uint8List ct = unb64(ctV);
    if (ct.length < 17 || ct.length > kVillageMaxUpdateBytes) return null;
    final Uint8List header = _header(from, to, iat, eph);
    if (!await DeviceKey.verify(from, cat(<List<int>>[header, lv(ct)]), sig)) return null;
    final Uint8List shared = await agreement.sharedSecret(eph);
    final List<int> plain = await Chacha20.poly1305Aead().decrypt(
        SecretBox(ct.sublist(0, ct.length - 16), nonce: Uint8List(12), mac: Mac(ct.sublist(ct.length - 16))),
        secretKey: await _updateKey(shared, eph, agreement.publicKey),
        aad: header);
    final Object? body = jsonDecode(utf8.decode(plain));
    if (body is! Map<String, Object?> || body['v'] != 1) return null;
    final Object? es = body['e'], vs = body['o'];
    if (es is! List || vs is! List || es.length > kMaxLedgerEntries || vs.length > kMaxLedgerVotes) return null;
    final List<LedgerEntry> entries = <LedgerEntry>[];
    for (final Object? x in es) {
      final LedgerEntry? e = await LedgerEntry.fromJson(x);
      if (e != null) entries.add(e);
    }
    final List<LedgerVote> votes = <LedgerVote>[
      for (final Object? x in vs)
        if (LedgerVote.fromJson(x) != null) LedgerVote.fromJson(x)!,
    ];
    return OpenedUpdate(from, entries, votes);
  } catch (_) {
    return null;
  }
}

// ---------------------------------------------------------------------------------------------------------------
// The door
// ---------------------------------------------------------------------------------------------------------------

/// What one exchange changed on this phone, for the screen's one plain line.
class DoorOutcome {
  const DoorOutcome({required this.heardFrom, required this.newEntries, required this.newVotes});
  final List<String> heardFrom;
  final int newEntries, newVotes;
  bool get changed => newEntries > 0 || newVotes > 0;
}

/// One phone's side of the exchange. It holds nothing of its own: it reads and writes the shared [FamilyContext] and
/// saves through [repository] after every change. Every call is serialised, so a request that arrives while another is
/// being folded in waits its turn.
class VillageDoor {
  VillageDoor({required this.context, required this.repository, required this.nowMs, this.onChanged, Random? random})
      : _random = random; // ignore: prefer_initializing_formals

  final FamilyContext context;
  final FamilyRepository repository;
  final int Function() nowMs;

  /// Called after the record changed (a request arrived, a yes came in), so a screen can reload.
  final void Function()? onChanged;
  final Random? _random;
  Future<void>? _tail;

  /// Runs [body] after every call made before it has finished. The queue starts empty and each link is made by the call
  /// that waits on it, so a door built in one zone and used from another (a widget test that calls it from real async)
  /// never waits on a future that belongs to a zone that is not running.
  Future<T> _locked<T>(Future<T> Function() body) async {
    final Future<void>? before = _tail;
    final Completer<void> mine = Completer<void>();
    _tail = mine.future;
    try {
      if (before != null) await before;
      return await body();
    } finally {
      mine.complete();
    }
  }

  DeviceKey get _me => context.device;

  /// One sealed update per phone this one may send to. Empty when there is nobody (a family of one).
  Future<List<String>> outgoing() => _locked(() async {
        final int now = nowMs();
        final LedgerState s = await context.state(nowMs: now);
        final List<String> out = <String>[];
        for (final VillagePeer p in villagePeers(s, context.entries, _me.publicKey)) {
          out.add(await sealVillageUpdate(
              sender: _me, to: p, entries: context.entries, votes: context.votes, nowMs: now, random: _random));
        }
        return out;
      });

  /// Opens whatever in [sealed] is for this phone and folds it in. Used for both the request body and the answer.
  Future<DoorOutcome> absorb(Iterable<String> sealed) => _locked(() async {
        final int now = nowMs();
        final List<String> heard = <String>[];
        int ne = 0, nv = 0;
        for (final String one in sealed) {
          // The allowed-sender test is made against the record as it stands NOW, so an update that carries a person's
          // own admission is still judged by what this phone already believed.
          final LedgerState s = await context.state(nowMs: now);
          final OpenedUpdate? u = await openVillageUpdate(
              sealed: one,
              own: _me,
              agreement: context.agreement,
              isAllowed: (Uint8List k) => senderAllowed(s, context.entries, k),
              nowMs: now);
          if (u == null) continue;
          final MergeResult r = await mergeLedger(ctx: context, entries: u.entries, votes: u.votes, nowMs: now);
          if (!r.ok) continue;
          heard.add(hexOf(u.fromKey));
          ne += r.newEntries;
          nv += r.newVotes;
        }
        if (ne > 0 || nv > 0) {
          await repository.save(context.snapshot());
          onChanged?.call();
        }
        return DoorOutcome(heardFrom: heard, newEntries: ne, newVotes: nv);
      });

  /// The wire handler for `{'t':'door','u':[sealed...]}`. Answers `{'t':'door-ok','u':[one sealed update for the
  /// sender]}`, or null (silence) when nothing in the request was for this phone from a phone it allows. The answer
  /// is sealed to the phone that opened, so a bystander who replays a request gets ciphertext only they cannot open.
  Future<Map<String, dynamic>?> handle(Map<String, dynamic> m) async {
    if (m['t'] != 'door') return null;
    final Object? u = m['u'];
    if (u is! List || u.isEmpty || u.length > kMaxGuardians + kMaxCarers + 4) return null;
    final List<String> sealed = <String>[for (final Object? x in u) if (x is String) x];
    final DoorOutcome o = await absorb(sealed);
    if (o.heardFrom.isEmpty) return null;
    final String first = o.heardFrom.first;
    final int now = nowMs();
    final List<String> reply = await _locked(() async {
      final LedgerState s = await context.state(nowMs: now);
      for (final VillagePeer p in villagePeers(s, context.entries, _me.publicKey)) {
        if (p.keyHex == first) {
          return <String>[
            await sealVillageUpdate(sender: _me, to: p, entries: context.entries, votes: context.votes, nowMs: now, random: _random),
          ];
        }
      }
      return <String>[];
    });
    return <String, dynamic>{'t': 'door-ok', 'u': reply};
  }

  /// Sends this phone's update through [send] (the wire) and folds the answer in. [send] returns the decoded reply or
  /// null when nothing answered.
  Future<DoorOutcome> exchange(Future<Map<String, dynamic>?> Function(Map<String, dynamic>) send) async {
    final List<String> out = await outgoing();
    if (out.isEmpty) return const DoorOutcome(heardFrom: <String>[], newEntries: 0, newVotes: 0);
    final Map<String, dynamic>? r = await send(<String, dynamic>{'t': 'door', 'u': out});
    if (r == null || r['t'] != 'door-ok' || r['u'] is! List) return const DoorOutcome(heardFrom: <String>[], newEntries: 0, newVotes: 0);
    return absorb(<String>[for (final Object? x in r['u'] as List) if (x is String) x]);
  }
}

// ---------------------------------------------------------------------------------------------------------------
// The new person's side of the record
// ---------------------------------------------------------------------------------------------------------------

/// Keeps the record the grown-up offered, on the new person's phone, so it can answer and later be told. Refuses when
/// this phone already holds a family record of any kind (a family on a phone is never replaced by another). The
/// record is the one the grown-up's phone vouched for in the meeting; from here on it is pinned to that family.
Future<FamilyContext> adoptOfferedRecord({
  required DeviceKey device,
  required AgreementKey agreement,
  required List<LedgerEntry> entries,
  required List<LedgerVote> votes,
  required FamilyRepository repository,
  required int nowMs,
}) async {
  if (await repository.hasRecord()) throw FamilyRecordUnusable();
  final LedgerState s = await reduceLedger(entries: entries, votes: votes, nowMs: nowMs);
  if (!s.ok) throw StateError('the offered record does not make a family');
  final FamilyContext ctx = FamilyContext(
    device: device,
    agreement: agreement,
    keyring: FamilyKeyring(guardianDevice: true),
    entries: List<LedgerEntry>.of(entries),
    votes: List<LedgerVote>.of(votes),
    pin: s.pin!,
  );
  await repository.save(ctx.snapshot());
  return ctx;
}

/// The new person says yes, on their own phone, to ONE request that names this phone. Signed with this phone's key and
/// bound to that request\'s hash; it cannot be used for any other. Kept in the record; the road carries it.
Future<LedgerVote> candidateSaysYes({
  required FamilyContext ctx,
  required FamilyRepository repository,
  required LedgerEntry invitation,
  required int nowMs,
}) async {
  final DeviceRecord? d = DeviceRecord.fromValue(invitation.body['dev']);
  if (invitation.type != EntryType.memberAdd || d == null || !bytesEqual(d.key, ctx.device.publicKey)) {
    throw StateError('that request is not about this phone');
  }
  final LedgerVote v = await LedgerVote.sign(ctx.device, target: invitation.hash, answer: 'yes', atMs: nowMs);
  final List<LedgerVote> before = List<LedgerVote>.of(ctx.votes);
  ctx.votes.add(v);
  try {
    await repository.save(ctx.snapshot());
  } catch (_) {
    ctx.votes
      ..clear()
      ..addAll(before);
    rethrow;
  }
  return v;
}
