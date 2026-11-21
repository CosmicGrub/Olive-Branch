// OLIVE BRANCH — the reduce rule for the family ledger: which entries are valid, who is a grown-up or a carer or a
// child device right now, who is only pending (and so holds nothing), what a fork looks like. UNVERIFIED on a device;
// pure Dart, runs headless in CI. Spec: docs/planning/FAMILY-IDENTITY-DESIGN.md sections 3.2 and 4, and
// docs/planning/VILLAGE-WELCOME-DESIGN.md sections 5 and 10. The entry formats are in family_ledger.dart.
//
// THE RULES, in the order the code applies them.
//  1. Every entry is checked AT ITS OWN POSITION: against the state built from its ancestors only, as of its own
//     `issuedAt`. So a validity decision never depends on the order entries arrive in. Delivery order does not
//     matter at all; a test shuffles the same entries and gets the same state.
//  2. The signer must be an active GUARDIAN device at that position. A child device key and a carer key are never
//     valid signers for an entry (a child key only ever signs a vote that accepts its own addition).
//  3. Some entries are gated: they need yes-votes (see LedgerVote) before they take effect. Until then they are
//     PENDING and change nothing; a pending person holds no key and no authority. Silence is never yes: a request
//     that nobody answers lapses at its expiry, and a vote that arrives after the expiry is ignored.
//  4. Votes bind to a ledger position because they name the entry hash, and the hash covers `prev` and the whole body.
//  5. REMOVAL BEATS A CONCURRENT ADD. If the same signer is removed on one branch while it acts on another, the
//     concurrent action is void (it is listed under `voided`), a mutual revoke voids both sides, and a key that is
//     claimed by two concurrent additions belongs to the canonically earlier one. A revoked or departed key or
//     person can never come back: the tombstone is permanent. Every fork is REPORTED, never silently resolved.
//
//  6. NOBODY REMOVES A PARENT ALONE (the owner's co-parent rules). Either parent may PAUSE the other at once; a pause is
//     visible to everyone, reversible by any OTHER parent (never by the paused one, and a paused parent cannot pause back),
//     and it takes away only the power to start things, never what they can see, their say on welcomes, or leaving.
//     Ending a parent needs both parents (`guardian.remove`: the person agrees) or a 14 day notice that every device
//     shows and only the one who gave it can take back (`access.end` with reason `notice`). A carer is ended at once by
//     the parent who welcomed them, or with that parent's yes. Two parents who pause each other at the same time both
//     lose (neither pause stands), so nobody is ever locked out of both.
//  7. LIMITS ON A PARENT ARE AN AGREEMENT. `limits.agree` takes effect only with the limited parent's own signed yes,
//     counted only after a 24 hour think-over, and may switch off only settings, connecting a child's device and
//     welcoming others. A parent may tighten their own limits at once; loosening or ending them needs the other
//     parents' yes. `standing.ok` is a parent's advance yes to Look-only welcomes (never a parent, never one who can
//     act), at most 90 days, taken back by writing a newer one.
//
// PROVISIONAL. The design (section 11) says the merge rule of 3.2 is the piece most likely to need revision once it
// is fuzzed, and this is a first model of it, tested on the hostile cases listed in the test file. Read the residual
// risks in the PR description before relying on it. Not built here: any storage, the gossip, the settle-in screens,
// the fork "accept" tap, rate limits and cooldown, the 72-hour hold for a family of one, and key rotation after
// someone is removed (a removed phone still holds the family keys it already had).
import 'dart:typed_data';

import 'family_ledger.dart';
import 'family_profiles.dart';

class LedgerMember {
  LedgerMember({
    required this.gidHex,
    required this.name,
    required this.kind,
    required this.profile,
    required this.activatedAtMs,
    required this.deviceKeysHex,
    this.welcomedByGidHex,
  });
  final String gidHex, name;

  /// The parent whose request brought this person in; null for the founder.
  final String? welcomedByGidHex;

  /// 'guardian' or 'carer'.
  final String kind;

  /// The profile the person was welcomed with; null for the founding grown-up (a full Parent).
  final MemberProfile? profile;
  final int activatedAtMs;
  final List<String> deviceKeysHex;

  bool get isGuardian => kind == 'guardian';
  Reach get reach => profile?.reach ?? Reach.parent;
}

class LedgerDevice {
  LedgerDevice({
    required this.key,
    required this.kind,
    required this.gidHex,
    required this.childId,
    required this.name,
    required this.agree,
    required this.activatedAtMs,
    required this.settleUntilMs,
    required this.legacy,
    required this.addedByHex,
  });
  final Uint8List key;

  /// 'guardian' | 'carer' | 'child'.
  final String kind;
  final String? gidHex, childId;
  final String name;

  /// Null only for a legacy child device that has not upgraded yet (it can hold no wrapped key).
  final Uint8List? agree;
  final int activatedAtMs, settleUntilMs;
  final bool legacy;
  final String addedByHex;

  String get keyHex => hexOf(key);
  bool settlingAt(int atMs) => settleUntilMs > atMs;
}

/// A gated entry that has not taken effect. [status] is 'pending', 'lapsed' (silence ran out) or 'declined'.
class PendingItem {
  PendingItem(this.hashHex, this.type, this.status, this.subjectGidHex, this.name, this.expMs,
      {this.proposerGidHex, this.requiredGidsHex = const <String>[], this.yesGidsHex = const <String>[], this.notBeforeMs});
  final String hashHex, type, status;
  final String? subjectGidHex, name;
  final int? expMs;

  /// Who asked, which people must say yes, which of them already have, and (for a limits agreement) the time before
  /// which a yes is not counted. A person's own phone is not a "person" here: the new person's own yes is separate.
  final String? proposerGidHex;
  final List<String> requiredGidsHex, yesGidsHex;
  final int? notBeforeMs;
}

/// A parent or carer whose access is paused: who paused it, when, and the entry that did.
class PauseInfo {
  PauseInfo(this.gidHex, this.byGidHex, this.atMs, this.hashHex);
  final String gidHex, byGidHex, hashHex;
  final int atMs;
}

/// A notice that someone's place in the village will end: given [atMs], takes effect at [effMs] unless the one who gave it
/// takes it back. Every device shows it for the whole wait.
class EndNotice {
  EndNotice(this.gidHex, this.byGidHex, this.atMs, this.effMs, this.hashHex);
  final String gidHex, byGidHex, hashHex;
  final int atMs, effMs;
}

/// Two or more entries that follow the same entry. The family is told in one plain sentence; nothing is dropped.
class LedgerFork {
  LedgerFork(this.parentHex, this.childrenHex, this.sameSigner);
  final String parentHex;
  final List<String> childrenHex;

  /// One device signed two different entries at the same position (a bug, a restore from a backup, or an attack).
  final bool sameSigner;
}

class LedgerState {
  LedgerState._failed(this.failure, this.rejected, this.nowMs)
      : ok = false,
        fid = null,
        genesisHash = null,
        policy = const FamilyPolicy(),
        epoch = 0,
        members = const <LedgerMember>[],
        devices = const <LedgerDevice>[],
        pending = const <PendingItem>[],
        voided = const <String, String>{},
        orphans = const <String>[],
        forks = const <LedgerFork>[],
        heads = const <Uint8List>[],
        legacyFids = const <String>[],
        history = const <String>[],
        paused = const <PauseInfo>[],
        endNotices = const <EndNotice>[],
        limits = const <String, List<int>>{},
        standing = const <String, int>{},
        genesisDeviceKey = null;

  LedgerState._ok({
    required this.fid,
    required this.genesisHash,
    required this.policy,
    required this.epoch,
    required this.members,
    required this.devices,
    required this.pending,
    required this.rejected,
    required this.voided,
    required this.orphans,
    required this.forks,
    required this.heads,
    required this.legacyFids,
    required this.history,
    required this.genesisDeviceKey,
    required this.nowMs,
    required this.paused,
    required this.endNotices,
    required this.limits,
    required this.standing,
  })  : ok = true,
        failure = null;

  final bool ok;

  /// Why nothing could be built: 'no-genesis', 'ambiguous-genesis', 'bad-genesis', 'too-many-entries'.
  final String? failure;
  final int nowMs;
  final Uint8List? fid, genesisHash, genesisDeviceKey;
  final FamilyPolicy policy;

  /// The newest key epoch named by a valid `key.rotate` (0 = the genesis keys).
  final int epoch;
  final List<LedgerMember> members;
  final List<LedgerDevice> devices;
  final List<PendingItem> pending;

  /// Entries that were refused, by hash, with a short reason. Some are only "not yet" ('from-the-future', 'orphan').
  final Map<String, String> rejected;

  /// Entries that were valid at their position but lose to a concurrent removal or claim.
  final Map<String, String> voided;
  final List<String> orphans;
  final List<LedgerFork> forks;

  /// The valid entries nothing follows yet: what the next entry must name as `prev`.
  final List<Uint8List> heads;
  final List<String> legacyFids;

  /// Hashes of the entries that took effect, in the one canonical order.
  final List<String> history;

  /// Whose access is paused right now. Pausing is visible to every parent and never a removal.
  final List<PauseInfo> paused;

  /// Notices of an end that are still running (the 14 day wait).
  final List<EndNotice> endNotices;

  /// The capabilities switched off for a parent by an agreement they signed, by person id. Empty list = none.
  final Map<String, List<int>> limits;

  /// Standing OK: the end time of each parent's advance yes to Look-only welcomes (active while it is after now).
  final Map<String, int> standing;

  bool isPaused(String gidHex) => paused.any((PauseInfo p) => p.gidHex == gidHex);
  PauseInfo? pauseOf(String gidHex) {
    for (final PauseInfo p in paused) {
      if (p.gidHex == gidHex) return p;
    }
    return null;
  }

  EndNotice? noticeFor(String gidHex) {
    for (final EndNotice n in endNotices) {
      if (n.gidHex == gidHex) return n;
    }
    return null;
  }

  List<int> limitsOf(String gidHex) => limits[gidHex] ?? const <int>[];
  bool standingActive(String gidHex) => (standing[gidHex] ?? 0) > nowMs;

  FamilyPin? get pin => ok ? FamilyPin(fid!, genesisHash!) : null;

  LedgerDevice? deviceFor(List<int> key) {
    final String k = hexOf(key);
    for (final LedgerDevice d in devices) {
      if (d.keyHex == k) return d;
    }
    return null;
  }

  /// True only for a key the ledger lists as an active device. A pending person's key is NOT listed, so
  /// [holdsAnything] is false for it: it has no wrapped key, no authority, nothing.
  bool holdsAnything(List<int> key) => deviceFor(key) != null;

  bool isActiveGuardianDevice(List<int> key) => deviceFor(key)?.kind == 'guardian';

  /// May this key sign a ledger entry that needs a full grown-up (not settling in) at [atMs]?
  bool canAct(List<int> key, int atMs) {
    final LedgerDevice? d = deviceFor(key);
    return d != null && d.kind == 'guardian' && !d.settlingAt(atMs) && !isPaused(d.gidHex ?? '');
  }

  bool isSettling(List<int> key, int atMs) => deviceFor(key)?.settlingAt(atMs) ?? false;

  List<Uint8List> get guardianDeviceKeys =>
      <Uint8List>[for (final LedgerDevice d in devices) if (d.kind == 'guardian') d.key];
  List<Uint8List> get childDeviceKeys =>
      <Uint8List>[for (final LedgerDevice d in devices) if (d.kind == 'child') d.key];
  List<LedgerMember> get guardians => <LedgerMember>[for (final LedgerMember m in members) if (m.isGuardian) m];

  bool get hasFork => forks.isNotEmpty || heads.length > 1;

  /// A legacy v1 pairing certificate names a family id string; it is valid for this family only when that string was
  /// recorded in the genesis. (The check that the certificate itself verifies lives in family_state.dart.)
  bool recognisesLegacyFid(String fid) => legacyFids.contains(fid);
}

class _Gate {
  _Gate({
    required this.proposerGid,
    required this.required,
    required this.acceptKey,
    required this.exp,
    required this.voterKeys,
    required this.proposerKeys,
    this.yesNotBefore,
  });
  final int? yesNotBefore; // a yes dated before this is not counted (the think-over)
  final String proposerGid;
  final Set<String> required; // gids whose yes is needed (the proposer's own signature is its yes)
  final String? acceptKey; // the candidate device that must accept its own addition
  final int? exp;
  final Map<String, String> voterKeys; // key hex -> gid, for required voters
  final Set<String> proposerKeys;
  final Map<String, int> yesAt = <String, int>{}; // gid or '*' for the candidate -> time of the latest yes
  bool declined = false;
}

class _Node {
  _Node(this.e) : h = e.hashHex;
  final LedgerEntry e;
  final String h;
  int topo = -1;
  Set<String> anc = <String>{};
  String? reject;
  bool transient = false;
  bool voided = false;
  String? voidReason;
  _Gate? gate;
  int settleHours = 0;

  String get type => e.type;
  String get signerHex => e.signerHex;
}

class _Mem {
  _Mem(this.gidHex, this.name, this.kind, this.profile, this.activatedAt, [this.welcomedBy]);
  final String gidHex, name, kind;
  final String? welcomedBy;
  final MemberProfile? profile;
  final int activatedAt;
}

class _St {
  final Map<String, _Mem> members = <String, _Mem>{};
  final Map<String, LedgerDevice> devices = <String, LedgerDevice>{};
  final Set<String> knownKeys = <String>{}, knownGids = <String>{}, deadKeys = <String>{}, deadGids = <String>{};
  FamilyPolicy policy = const FamilyPolicy();
  int epoch = 0;
  final Map<String, PauseInfo> paused = <String, PauseInfo>{};
  final Map<String, EndNotice> pendingEnds = <String, EndNotice>{};
  final Map<String, List<int>> limits = <String, List<int>>{};
  final Map<String, int> standing = <String, int>{};

  List<LedgerDevice> devicesOf(String gid) =>
      <LedgerDevice>[for (final LedgerDevice d in devices.values) if (d.gidHex == gid) d];

  /// Guardian members with at least one active device that is out of settle-in at [asOf]: the people who are asked.
  List<String> electors(int asOf) {
    final List<String> out = <String>[
      for (final _Mem m in members.values)
        if (m.kind == 'guardian' && devicesOf(m.gidHex).any((LedgerDevice d) => !d.settlingAt(asOf))) m.gidHex,
    ]..sort();
    return out;
  }

  int count(String kind) => members.values.where((_Mem m) => m.kind == kind).length;
}

/// Reduce [entries] and [votes] to the family's state as of [nowMs]. Pass [pin] once a device has pinned a family:
/// then only the genesis with that FID and hash is accepted, and a ledger of any other family is ignored.
Future<LedgerState> reduceLedger({
  required Iterable<LedgerEntry> entries,
  Iterable<LedgerVote> votes = const <LedgerVote>[],
  required int nowMs,
  FamilyPin? pin,
}) =>
    _Reducer(nowMs, pin).run(entries.toList(), votes.toList());

class _Reducer {
  _Reducer(this.now, this.pin);
  final int now;
  final FamilyPin? pin;

  final Map<String, _Node> nodes = <String, _Node>{};
  final List<_Node> order = <_Node>[];
  final Map<String, String> rejected = <String, String>{};
  final Map<String, List<LedgerVote>> votesByTarget = <String, List<LedgerVote>>{};
  _Node? genesis;

  Future<LedgerState> run(List<LedgerEntry> entriesIn, List<LedgerVote> votesIn) async {
    if (entriesIn.length > kMaxLedgerEntries || votesIn.length > kMaxLedgerVotes) {
      return LedgerState._failed('too-many-entries', rejected, now);
    }
    // 1. Signatures. A bad one is dropped and named; it can never be a parent.
    final Map<String, LedgerEntry> uniq = <String, LedgerEntry>{};
    for (final LedgerEntry e in entriesIn) {
      uniq.putIfAbsent(e.hashHex, () => e);
    }
    final List<_Node> all = <_Node>[];
    for (final LedgerEntry e in uniq.values) {
      if (!await e.verifySignature()) {
        rejected[e.hashHex] = 'bad-signature';
        continue;
      }
      all.add(_Node(e));
    }
    // 2. The genesis.
    final List<_Node> geneses = <_Node>[for (final _Node n in all) if (n.type == EntryType.genesis) n];
    List<_Node> usable = geneses;
    final FamilyPin? p = pin;
    if (p != null) {
      usable = <_Node>[];
      for (final _Node g in geneses) {
        if (bytesEqual(g.e.body['fid']! as Uint8List, p.fid) && bytesEqual(g.e.hash, p.genesisHash)) {
          usable.add(g);
        } else {
          rejected[g.h] = 'foreign-genesis';
        }
      }
    }
    if (usable.isEmpty) return LedgerState._failed('no-genesis', rejected, now);
    if (usable.length > 1) {
      for (final _Node g in usable) {
        rejected[g.h] = 'ambiguous-genesis';
      }
      return LedgerState._failed('ambiguous-genesis', rejected, now);
    }
    final _Node g = usable.single;
    final String? gErr = await _checkGenesis(g.e);
    if (gErr != null) {
      rejected[g.h] = gErr;
      return LedgerState._failed('bad-genesis', rejected, now);
    }
    genesis = g;
    nodes[g.h] = g;
    order.add(g);
    g.topo = 0;
    g.anc = <String>{};
    // 3. The graph, in one canonical order: the smallest hash among the entries whose parents are all placed.
    final List<_Node> remaining = <_Node>[for (final _Node n in all) if (n.type != EntryType.genesis) n]
      ..sort((_Node a, _Node b) => a.h.compareTo(b.h));
    for (final _Node n in remaining) {
      nodes[n.h] = n;
    }
    final Set<String> placed = <String>{g.h};
    while (remaining.isNotEmpty) {
      int idx = -1;
      for (int i = 0; i < remaining.length; i++) {
        if (remaining[i].e.prev.every((Uint8List q) => placed.contains(hexOf(q)))) {
          idx = i;
          break;
        }
      }
      if (idx < 0) break;
      final _Node n = remaining.removeAt(idx);
      n.topo = order.length;
      order.add(n);
      placed.add(n.h);
    }
    final List<String> orphans = <String>[for (final _Node n in remaining) n.h]..sort();
    for (final _Node n in remaining) {
      rejected[n.h] = 'orphan';
      nodes.remove(n.h);
    }
    // 4. Votes: signature first, then grouped by the entry they name.
    for (final LedgerVote v in votesIn) {
      if (!await v.verifySignature()) continue;
      (votesByTarget[v.targetHex] ??= <LedgerVote>[]).add(v);
    }
    // 5. Ancestors and position validity, in canonical order.
    for (int i = 1; i < order.length; i++) {
      final _Node n = order[i];
      final Set<String> anc = <String>{};
      for (final Uint8List q in n.e.prev) {
        final String qh = hexOf(q);
        anc.add(qh);
        anc.addAll(nodes[qh]!.anc);
      }
      n.anc = anc;
      await _validate(n);
      if (n.reject != null) rejected[n.h] = n.reject!;
    }
    // 6. Removal beats a concurrent add.
    _markVoids();
    // 7. The state as of now.
    final _St st = _fold(null, now, useVoid: true);
    return _finish(st, orphans);
  }

  // ------------------------------------------------------------------------------------------------------------
  // Genesis
  // ------------------------------------------------------------------------------------------------------------

  Future<String?> _checkGenesis(LedgerEntry e) async {
    final DeviceRecord dev = DeviceRecord.fromValue(e.body['dev'])!;
    if (!bytesEqual(dev.key, e.signer)) return 'genesis-signer-is-not-founder';
    if (!await verifyAgreementCert(dev)) return 'agreement-cert';
    return null;
  }

  // ------------------------------------------------------------------------------------------------------------
  // Position validity
  // ------------------------------------------------------------------------------------------------------------

  Future<void> _validate(_Node n) async {
    final LedgerEntry e = n.e;
    for (final Uint8List q in e.prev) {
      final _Node pn = nodes[hexOf(q)]!;
      if (pn.reject != null) {
        n.reject = 'invalid-parent';
        n.transient = pn.transient;
        return;
      }
      if (e.issuedAtMs < pn.e.issuedAtMs) {
        n.reject = 'time-goes-backwards';
        return;
      }
    }
    if (e.issuedAtMs > now + kClockSkewMs) {
      n.reject = 'from-the-future';
      n.transient = true;
      return;
    }
    final _St s = _fold(n.anc, e.issuedAtMs, useVoid: false);
    final LedgerDevice? d = s.devices[n.signerHex];
    if (d == null) {
      n.reject = s.deadKeys.contains(n.signerHex)
          ? 'signer-revoked'
          : (s.knownKeys.contains(n.signerHex) ? 'signer-not-active' : 'signer-unknown');
      return;
    }
    if (d.kind == 'child') {
      n.reject = 'child-key-cannot-sign';
      return;
    }
    if (d.kind != 'guardian') {
      n.reject = 'carer-key-cannot-sign';
      return;
    }
    final bool settling = d.settlingAt(e.issuedAtMs);
    final Map<String, Object?> b = e.body;
    String? bad;
    // A paused parent can leave, defend their own phone and take back their own notice, and can still SAY yes or no (a
    // vote is not an entry); they cannot start anything else until another parent resumes them.
    final String myGid = d.gidHex ?? '';
    if (s.paused.containsKey(myGid) &&
        e.type != EntryType.guardianLeave &&
        e.type != EntryType.deviceRevokeCancel &&
        e.type != EntryType.accessEndCancel) {
      n.reject = 'signer-paused';
      return;
    }
    final List<int> myLimits = s.limits[myGid] ?? const <int>[];
    switch (e.type) {
      case EntryType.memberAdd:
        bad = settling ? 'signer-settling' : (myLimits.contains(11) ? 'welcome-limited' : await _memberAdd(n, s, d));
        break;
      case EntryType.deviceAdd:
        bad = settling
            ? 'signer-settling'
            : ((b['kind'] == 'child' && myLimits.contains(8)) ? 'connect-limited' : await _deviceAdd(n, s, d));
        break;
      case EntryType.deviceRevoke:
        bad = settling ? 'signer-settling' : _deviceRevoke(n, s, d);
        break;
      case EntryType.deviceRevokeCancel:
        bad = _revokeCancel(n, s, d); // a person defending their own device is never blocked by settle-in
        break;
      case EntryType.guardianLeave:
        bad = _leave(n, s, d); // leaving is a floor: always allowed to the person themselves
        break;
      case EntryType.guardianRemove:
        bad = settling ? 'signer-settling' : _remove(n, s, d);
        break;
      case EntryType.policySet:
        bad = settling ? 'signer-settling' : (myLimits.contains(6) ? 'settings-limited' : _policySet(n, s, d));
        break;
      case EntryType.keyRotate:
        bad = settling ? 'signer-settling' : _keyRotate(n, s);
        break;
      case EntryType.accessPause:
        bad = settling ? 'signer-settling' : _pause(n, s, d);
        break;
      case EntryType.accessResume:
        bad = settling ? 'signer-settling' : _resume(n, s, d);
        break;
      case EntryType.accessEnd:
        bad = settling ? 'signer-settling' : _accessEnd(n, s, d);
        break;
      case EntryType.accessEndCancel:
        bad = _endCancel(n, s, d);
        break;
      case EntryType.limitsAgree:
        bad = settling ? 'signer-settling' : _limitsAgree(n, s, d);
        break;
      case EntryType.limitsTighten:
        bad = settling ? 'signer-settling' : _limitsTighten(n, s, d);
        break;
      case EntryType.standingOk:
        bad = settling ? 'signer-settling' : _standingOk(n, s, d);
        break;
      default:
        bad = 'unknown-type';
    }
    if (bad != null) {
      n.reject = bad;
      return;
    }
    final _Gate? g = n.gate;
    if (g != null) _applyVotes(n, g);
  }

  Uint8List _gidOf(Map<String, Object?> body, [String key = 'gid']) => body[key]! as Uint8List;

  Future<String?> _memberAdd(_Node n, _St s, LedgerDevice signer) async {
    final Map<String, Object?> b = n.e.body;
    final String gid = hexOf(_gidOf(b));
    final String kind = b['kind']! as String;
    final MemberProfile profile = MemberProfile.fromValue(b['profile'])!;
    final String? why = profile.violation();
    if (why != null) return 'profile:$why';
    if ((tierOf(profile.preset) == MemberTier.parent) != (kind == 'guardian')) return 'kind-tier-mismatch';
    final DeviceRecord dev = DeviceRecord.fromValue(b['dev'])!;
    if (!await verifyAgreementCert(dev)) return 'agreement-cert';
    final String keyHex = hexOf(dev.key);
    if (s.knownGids.contains(gid)) return 'gid-reused';
    if (s.knownKeys.contains(keyHex)) return 'key-reused';
    if (kind == 'guardian' && s.count('guardian') >= kMaxGuardians) return 'family-full';
    if (kind == 'carer' && s.count('carer') >= kMaxCarers) return 'family-full';
    final Map<String, Object?> pr = b['proposal']! as Map<String, Object?>;
    final int exp = pr['exp']! as int;
    if (exp <= n.e.issuedAtMs || exp > n.e.issuedAtMs + proposalLifetimeMs(profile.preset)) return 'bad-expiry';
    final String rule = pr['rule']! as String;
    // The floors. A new Parent (with or without limits) needs ALL parents, whatever the family's own policy says. A
    // carer who can act follows the family's switch (default ALL), one who can only look follows the other (default ONE).
    final String floor = kind == 'guardian'
        ? 'all'
        : (profile.reach == Reach.look ? s.policy.carerLook : s.policy.carerAct);
    if (floor == 'all' && rule != 'all') return 'rule-below-floor';
    final String proposerGid = signer.gidHex!;
    final List<String> expected = rule == 'all' ? s.electors(n.e.issuedAtMs) : <String>[proposerGid];
    final List<String> given = <String>[for (final Object? x in pr['electorate']! as List) hexOf(x! as Uint8List)];
    if (expected.length != given.length || !_sameList(expected, given)) return 'electorate-wrong';
    if (!given.contains(proposerGid)) return 'proposer-not-in-electorate';
    n.settleHours = kind == 'guardian' ? s.policy.settleHours : defaultSettleHours(profile.preset);
    // A Standing OK is a parent's advance yes, and it covers ONLY a person who can look and nothing else (never a parent,
    // never someone who can act) in a family that asks every parent about those. Their name stays on the list; their yes
    // is already in, so nobody waits for them.
    final bool covered = kind == 'carer' && profile.reach == Reach.look && rule == 'all';
    final Set<String> needed = <String>{
      for (final String x in given)
        if (x != proposerGid && !(covered && (s.standing[x] ?? 0) > n.e.issuedAtMs)) x,
    };
    n.gate = _gateFor(s, proposerGid: proposerGid, required: needed,
        acceptKey: keyHex, exp: exp, includeSettlingVoters: false, asOf: n.e.issuedAtMs);
    return null;
  }

  // ------------------------------------------------------------------------------------------------------------
  // Pause, end, limits, Standing OK
  // ------------------------------------------------------------------------------------------------------------

  String? _subjectMember(_St s, Map<String, Object?> b) => s.members.containsKey(hexOf(_gidOf(b))) ? null : 'unknown-subject';

  String? _pause(_Node n, _St s, LedgerDevice signer) {
    final String? bad = _subjectMember(s, n.e.body);
    if (bad != null) return bad;
    final String gid = hexOf(_gidOf(n.e.body));
    if (gid == signer.gidHex) return 'cannot-pause-yourself';
    if (s.paused.containsKey(gid)) return 'already-paused';
    return null;
  }

  String? _resume(_Node n, _St s, LedgerDevice signer) {
    final String? bad = _subjectMember(s, n.e.body);
    if (bad != null) return bad;
    final String gid = hexOf(_gidOf(n.e.body));
    if (gid == signer.gidHex) return 'cannot-resume-yourself';
    if (!s.paused.containsKey(gid)) return 'not-paused';
    return null;
  }

  String? _accessEnd(_Node n, _St s, LedgerDevice signer) {
    final String? bad = _subjectMember(s, n.e.body);
    if (bad != null) return bad;
    final String gid = hexOf(_gidOf(n.e.body));
    final _Mem m = s.members[gid]!;
    if (gid == signer.gidHex) return 'use-leave';
    final String reason = n.e.body['reason']! as String;
    final int at = n.e.issuedAtMs;
    if (reason == 'notice') {
      // The long way: any parent, for anyone, with a wait every device can see. One notice at a time per person.
      if (s.pendingEnds.containsKey(gid)) return 'notice-already-running';
      return null;
    }
    if (reason != 'ended') return 'reason-not-supported';
    // The short way is for a carer. A parent is ended together (guardian.remove, the parent agrees) or by notice.
    if (m.kind != 'carer') return 'parents-end-together-or-by-notice';
    final String? welcomer = m.welcomedBy;
    if (welcomer == signer.gidHex) return null; // the parent who welcomed them may end it at once
    // Anyone else needs the welcoming parent's yes; if that parent is no longer here, every other parent's.
    final bool welcomerHere = welcomer != null && s.members[welcomer]?.kind == 'guardian';
    final Set<String> required = welcomerHere
        ? <String>{welcomer}
        : <String>{for (final String x in s.electors(at)) if (x != signer.gidHex) x};
    if (required.isEmpty) return null;
    n.gate = _gateFor(s, proposerGid: signer.gidHex!, required: required, acceptKey: null, exp: at + kApprovalLifetimeMs,
        includeSettlingVoters: true, asOf: at);
    return null;
  }

  String? _endCancel(_Node n, _St s, LedgerDevice signer) {
    final String h = hexOf(n.e.body['end']! as Uint8List);
    if (!n.anc.contains(h)) return 'end-not-seen';
    final _Node? en = nodes[h];
    if (en == null || en.reject != null || en.type != EntryType.accessEnd || en.e.body['reason'] != 'notice') return 'not-a-notice';
    if (en.signerHex != n.signerHex && s.devices[en.signerHex]?.gidHex != signer.gidHex) return 'only-the-one-who-gave-notice';
    if (en.e.issuedAtMs + kEndNoticeMs <= n.e.issuedAtMs) return 'too-late-to-cancel';
    return null;
  }

  /// A list of capability numbers in the one canonical form: strictly ascending, only ones a limit may touch.
  static bool _limitList(Object? v) {
    if (v is! List) return false;
    int last = 0;
    for (final Object? x in v) {
      if (x is! int || x <= last || !kLimitableCapabilities.contains(x)) return false;
      last = x;
    }
    return true;
  }

  String? _limitsAgree(_Node n, _St s, LedgerDevice signer) {
    final Map<String, Object?> b = n.e.body;
    final String gid = hexOf(_gidOf(b));
    final _Mem? m = s.members[gid];
    if (m == null) return 'unknown-subject';
    if (m.kind != 'guardian') return 'limits-are-for-a-parent';
    if (!_limitList(b['limits'])) return 'limits-not-allowed';
    final List<int> list = <int>[for (final Object? x in b['limits']! as List) x! as int];
    final int at = n.e.issuedAtMs, until = b['until']! as int;
    final List<int> current = s.limits[gid] ?? const <int>[];
    if (gid == signer.gidHex) {
      // A request to loosen or end the limits: fewer than now, and every other parent must say yes.
      if (current.isEmpty || !list.every(current.contains) || list.length >= current.length) return 'not-a-loosening';
      if (until < at || until > at + kApprovalLifetimeMs) return 'bad-think-over';
      final Set<String> others = <String>{for (final String x in s.electors(at)) if (x != gid) x};
      if (others.isEmpty) return 'nobody-to-agree';
      n.gate = _gateFor(s, proposerGid: gid, required: others, acceptKey: null, exp: at + kApprovalLifetimeMs,
          includeSettlingVoters: false, asOf: at, yesNotBefore: until);
      return null;
    }
    // Limits on another parent: only with that parent's own yes, after the think-over. Nothing changes before then.
    if (list.isEmpty) return 'limits-empty';
    if (until < at + kThinkOverMs || until > at + kApprovalLifetimeMs) return 'bad-think-over';
    n.gate = _gateFor(s, proposerGid: signer.gidHex!, required: <String>{gid}, acceptKey: null, exp: at + kApprovalLifetimeMs,
        includeSettlingVoters: true, asOf: at, yesNotBefore: until);
    return null;
  }

  String? _limitsTighten(_Node n, _St s, LedgerDevice signer) {
    final Map<String, Object?> b = n.e.body;
    final String gid = hexOf(_gidOf(b));
    if (gid != signer.gidHex) return 'only-yourself';
    if (!_limitList(b['limits'])) return 'limits-not-allowed';
    final List<int> list = <int>[for (final Object? x in b['limits']! as List) x! as int];
    final List<int> current = s.limits[gid] ?? const <int>[];
    if (!current.every(list.contains) || list.length <= current.length) return 'not-tighter';
    return null;
  }

  String? _standingOk(_Node n, _St s, LedgerDevice signer) {
    final Map<String, Object?> b = n.e.body;
    if (hexOf(_gidOf(b)) != signer.gidHex) return 'only-yourself';
    final int until = b['until']! as int;
    if (until < 0 || until > n.e.issuedAtMs + kStandingMaxMs) return 'bad-until';
    return null;
  }

  Future<String?> _deviceAdd(_Node n, _St s, LedgerDevice signer) async {
    final Map<String, Object?> b = n.e.body;
    final String kind = b['kind']! as String;
    final DeviceRecord dev = DeviceRecord.fromValue(b['dev'])!;
    final String keyHex = hexOf(dev.key);
    final bool legacy = b['legacy']! as bool;
    if (s.knownKeys.contains(keyHex)) return 'key-reused';
    if (dev.agree != null && !await verifyAgreementCert(dev)) return 'agreement-cert';
    if (kind == 'guardian') {
      final Object? gid = b['gid'];
      if (gid is! Uint8List || b['childId'] != null || legacy || b['orig'] != null) return 'bad-guardian-device';
      if (dev.agree == null) return 'agreement-key-required';
      // A grown-up adds their OWN phones. Adding a device to somebody else's name is a new person (member.add).
      if (hexOf(gid) != signer.gidHex) return 'not-your-own-device';
      if (s.devicesOf(signer.gidHex!).length >= kMaxDevicesPerGuardian) return 'too-many-devices';
      n.settleHours = s.policy.settleHours;
      n.gate = _gateFor(s, proposerGid: signer.gidHex!, required: <String>{}, acceptKey: keyHex, exp: null,
          includeSettlingVoters: false, asOf: n.e.issuedAtMs);
      return null;
    }
    // A child device.
    if (b['gid'] != null || b['childId'] == null) return 'bad-child-device';
    if (s.devices.values.where((LedgerDevice x) => x.kind == 'child').length >= kMaxChildDevices) return 'family-full';
    if (legacy) {
      // Founding a ledger from an existing family: only the founder may vouch, only if the genesis recorded a legacy
      // family id, only with the original issue time. It adds no new trust: the same grown-up key certified it before.
      if (!bytesEqual(n.e.signer, genesis!.e.signer)) return 'legacy-only-by-founder';
      if ((genesis!.e.body['legacyFids']! as List).isEmpty) return 'no-legacy-family-recorded';
      if (b['orig'] == null) return 'legacy-needs-original-time';
      n.settleHours = 0;
      return null;
    }
    if (b['orig'] != null) return 'bad-child-device';
    if (dev.agree == null) return 'agreement-key-required';
    n.gate = _gateFor(s, proposerGid: signer.gidHex!, required: <String>{}, acceptKey: keyHex, exp: null,
        includeSettlingVoters: false, asOf: n.e.issuedAtMs);
    return null;
  }

  String? _deviceRevoke(_Node n, _St s, LedgerDevice signer) {
    final Map<String, Object?> b = n.e.body;
    final String keyHex = hexOf(b['key']! as Uint8List);
    final LedgerDevice? t = s.devices[keyHex];
    if (t == null) return 'unknown-device';
    final int eff = b['eff']! as int;
    final int at = n.e.issuedAtMs;
    // Never leave a family with no grown-up device.
    final bool lastGuardianDevice = t.kind == 'guardian' &&
        s.devices.values.where((LedgerDevice x) => x.kind == 'guardian' && x.keyHex != keyHex).isEmpty;
    if (lastGuardianDevice) return 'last-guardian-device';
    final bool own = t.gidHex != null && t.gidHex == signer.gidHex;
    final bool otherGuardian = t.kind == 'guardian' && !own;
    if (otherGuardian) {
      // Another grown-up's phone: a visible notice they can cancel.
      if (b['reason'] != 'lost') return 'reason-must-be-lost';
      if (eff < at + kRevokeNoticeMs) return 'notice-too-short';
    } else if (eff != at) {
      return 'must-be-immediate';
    }
    return null;
  }

  String? _revokeCancel(_Node n, _St s, LedgerDevice signer) {
    final String rh = hexOf(n.e.body['revoke']! as Uint8List);
    if (!n.anc.contains(rh)) return 'revoke-not-seen';
    final _Node r = nodes[rh]!;
    if (r.reject != null || r.type != EntryType.deviceRevoke) return 'not-a-revoke';
    final int eff = r.e.body['eff']! as int;
    if (eff <= n.e.issuedAtMs) return 'too-late-to-cancel';
    final String targetKey = hexOf(r.e.body['key']! as Uint8List);
    final LedgerDevice? t = s.devices[targetKey];
    if (t == null || t.gidHex == null || t.gidHex != signer.gidHex) return 'only-the-owner-can-cancel';
    return null;
  }

  String? _leave(_Node n, _St s, LedgerDevice signer) {
    final String gid = hexOf(_gidOf(n.e.body));
    if (gid != signer.gidHex) return 'only-yourself';
    final int others = s.members.values.where((_Mem m) => m.kind == 'guardian' && m.gidHex != gid).length;
    if (others < 1) return 'last-guardian';
    return null;
  }

  String? _remove(_Node n, _St s, LedgerDevice signer) {
    final Map<String, Object?> b = n.e.body;
    final String gid = hexOf(_gidOf(b));
    final _Mem? m = s.members.containsKey(gid) ? s.members[gid] : null;
    if (m == null || m.kind != 'guardian') return 'unknown-subject';
    if (gid == signer.gidHex) return 'use-leave';
    final int exp = b['exp']! as int;
    if (exp <= n.e.issuedAtMs || exp > n.e.issuedAtMs + kApprovalLifetimeMs) return 'bad-expiry';
    // Never one grown-up's lever against the other: the person being removed must agree.
    n.gate = _gateFor(s, proposerGid: signer.gidHex!, required: <String>{gid}, acceptKey: null, exp: exp,
        includeSettlingVoters: true, asOf: n.e.issuedAtMs);
    return null;
  }

  String? _policySet(_Node n, _St s, LedgerDevice signer) {
    final Map<String, Object?> b = n.e.body;
    final FamilyPolicy np = FamilyPolicy.fromValue(b['policy'])!;
    final bool loosens = np.loosensFrom(s.policy);
    final List<String> others = <String>[for (final String x in s.electors(n.e.issuedAtMs)) if (x != signer.gidHex) x];
    final bool needVotes = loosens && s.policy.addGrownUp == 'all' && others.isNotEmpty;
    final Object? exp = b['exp'];
    if (needVotes) {
      if (exp is! int || exp <= n.e.issuedAtMs || exp > n.e.issuedAtMs + kApprovalLifetimeMs) return 'bad-expiry';
      n.gate = _gateFor(s, proposerGid: signer.gidHex!, required: others.toSet(), acceptKey: null, exp: exp,
          includeSettlingVoters: false, asOf: n.e.issuedAtMs);
    } else if (exp != null) {
      return 'unexpected-expiry';
    }
    return null;
  }

  String? _keyRotate(_Node n, _St s) {
    final Map<String, Object?> b = n.e.body;
    if ((b['epoch']! as int) != s.epoch + 1) return 'wrong-epoch';
    final Map<String, bool> want = <String, bool>{
      for (final LedgerDevice d in s.devices.values)
        if (d.agree != null) d.keyHex: d.kind == 'guardian',
    };
    final Set<String> seen = <String>{};
    for (final Object? w in b['wraps']! as List) {
      final Map<String, Object?> m = w! as Map<String, Object?>;
      final String to = hexOf(m['to']! as Uint8List);
      if (!want.containsKey(to)) return 'wrap-to-a-device-that-is-not-active';
      if (!seen.add(to)) return 'duplicate-wrap';
      final bool needsGk = want[to]!;
      // The guardian-only key is only ever wrapped to a grown-up's device. A child device or a carer gets none.
      if (needsGk && m['gk'] == null) return 'grown-up-wrap-without-guardian-key';
      if (!needsGk && m['gk'] != null) return 'guardian-key-wrapped-to-a-non-guardian';
    }
    if (seen.length != want.length) return 'wrap-missing';
    return null;
  }

  bool _sameList(List<String> a, List<String> b) {
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  _Gate _gateFor(
    _St s, {
    required String proposerGid,
    required Set<String> required,
    required String? acceptKey,
    required int? exp,
    required bool includeSettlingVoters,
    required int asOf,
    int? yesNotBefore,
  }) {
    final Map<String, String> voterKeys = <String, String>{};
    for (final String r in required) {
      for (final LedgerDevice d in s.devicesOf(r)) {
        if (includeSettlingVoters || !d.settlingAt(asOf)) voterKeys[d.keyHex] = r;
      }
    }
    return _Gate(
      proposerGid: proposerGid,
      required: required,
      acceptKey: acceptKey,
      exp: exp,
      voterKeys: voterKeys,
      proposerKeys: <String>{for (final LedgerDevice d in s.devicesOf(proposerGid)) d.keyHex},
      yesNotBefore: yesNotBefore,
    );
  }

  // ------------------------------------------------------------------------------------------------------------
  // Votes
  // ------------------------------------------------------------------------------------------------------------

  /// Counts the votes on a gated entry. A required person's yes counts once (the earliest). ANY no from a required
  /// person, from the candidate, or a withdrawal by the proposer ends the proposal for good: there is no tie-break
  /// and no second vote on the same proposal (village design 5.1). A yes that arrives after the expiry is ignored.
  void _applyVotes(_Node n, _Gate g) {
    final List<LedgerVote> vs = votesByTarget[n.h] ?? const <LedgerVote>[];
    final List<LedgerVote> refusals = <LedgerVote>[];
    for (final LedgerVote v in vs) {
      final String? role = v.voterHex == g.acceptKey
          ? '*'
          : (g.voterKeys[v.voterHex] ?? (g.proposerKeys.contains(v.voterHex) ? g.proposerGid : null));
      if (role == null) continue; // not somebody who was asked
      if (v.atMs > now + kClockSkewMs) continue; // from the future
      if (v.atMs < n.e.issuedAtMs - kClockSkewMs) continue; // cannot answer a question not yet asked
      final int? exp = g.exp;
      if (exp != null && v.atMs >= exp) continue; // silence ran out: a late answer is not an answer
      if (role == g.proposerGid) {
        // The proposer's yes is implied by signing. Only a withdrawal (or a no) means anything.
        if (v.answer == 'withdraw' || v.answer == 'no') refusals.add(v);
        continue;
      }
      if (v.answer == 'withdraw') continue; // only the proposer withdraws
      final int? notBefore = g.yesNotBefore;
      if (v.answer == 'yes' && notBefore != null && v.atMs < notBefore) continue; // answered before the think-over ended
      if (v.answer == 'no') {
        refusals.add(v);
      } else {
        final int? cur = g.yesAt[role];
        if (cur == null || v.atMs < cur) g.yesAt[role] = v.atMs;
      }
    }
    // A completed approval is final. Once the last yes is in, a later no or withdrawal changes nothing: it is not a
    // way to undo a grown-up or a device that was already let in (that is guardian.remove or device.revoke, which
    // have their own rules). Only a refusal dated BEFORE the gate was satisfied ends the proposal.
    final int? done = _completedAt(n, g);
    for (final LedgerVote v in refusals) {
      if (done == null || v.atMs < done) g.declined = true;
    }
  }

  /// When every required yes (and the candidate's own) was in, ignoring refusals; null while one is missing.
  int? _completedAt(_Node n, _Gate g) {
    int t = n.e.issuedAtMs;
    for (final String r in g.required) {
      final int? at = g.yesAt[r];
      if (at == null) return null;
      if (at > t) t = at;
    }
    if (g.acceptKey != null) {
      final int? at = g.yesAt['*'];
      if (at == null) return null;
      if (at > t) t = at;
    }
    return t;
  }

  /// When a gated entry became effective, or null if it is not (yet) effective as of [asOf].
  int? _activation(_Node n, int asOf) {
    final _Gate? g = n.gate;
    if (g == null) return n.e.issuedAtMs;
    if (g.declined) return null;
    int t = n.e.issuedAtMs;
    for (final String r in g.required) {
      final int? at = g.yesAt[r];
      if (at == null || at > asOf) return null;
      if (at > t) t = at;
    }
    final String? a = g.acceptKey;
    if (a != null) {
      final int? at = g.yesAt['*'];
      if (at == null || at > asOf) return null;
      if (at > t) t = at;
    }
    return t;
  }

  // ------------------------------------------------------------------------------------------------------------
  // The fold
  // ------------------------------------------------------------------------------------------------------------

  /// The device keys whose revocation is in force at [asOf] (the same entries the fold itself accepts).
  Set<String> _revokedKeys(Set<String>? include, int asOf, bool useVoid) {
    final List<_Node> revokes = <_Node>[];
    final Set<String> cancelled = <String>{};
    for (final _Node n in order) {
      if (include != null && n.topo != 0 && !include.contains(n.h)) continue;
      if (n.reject != null || (useVoid && n.voided)) continue;
      if (n.type != EntryType.deviceRevoke && n.type != EntryType.deviceRevokeCancel) continue;
      if (_activation(n, asOf) == null) continue;
      if (n.type == EntryType.deviceRevoke) {
        revokes.add(n);
      } else {
        cancelled.add(hexOf(n.e.body['revoke']! as Uint8List));
      }
    }
    return <String>{
      for (final _Node r in revokes)
        if (!cancelled.contains(r.h) && (r.e.body['eff']! as int) <= asOf) hexOf(r.e.body['key']! as Uint8List),
    };
  }

  /// True when a notice's own clock cannot be trusted: some entry that does NOT build on the notice, written by a device of
  /// the parent who gave it or of the person it is about, is dated later than the notice by more than the clock skew. An
  /// honest notice is written on top of what its writer had seen, so such an entry shows the notice was backdated
  /// (a stale parent plus a stale time) to skip the wait. The notice then simply does not count and can be given again.
  bool _staleNotice(_Node notice, Set<String>? include, String by, String subject, _St st) {
    final int floor = notice.e.issuedAtMs + kClockSkewMs;
    for (final _Node x in order) {
      if (include != null && x.topo != 0 && !include.contains(x.h)) continue;
      if (x.reject != null || identical(x, notice) || x.e.issuedAtMs <= floor || x.anc.contains(notice.h)) continue;
      final String? g = st.devices[x.signerHex]?.gidHex;
      if (g != null && (g == by || g == subject)) return true;
    }
    return false;
  }

  _St _fold(Set<String>? include, int asOf, {required bool useVoid}) {
    final _St st = _St();
    final List<_Node> policyNodes = <_Node>[];
    final List<_Node> revokes = <_Node>[];
    final Set<String> cancelled = <String>{};
    final List<_Node> pauseNodes = <_Node>[], resumeNodes = <_Node>[], noticeEnds = <_Node>[], limitNodes = <_Node>[];
    final List<_Node> standingNodes = <_Node>[];
    final Set<String> endCancelled = <String>{};
    final Set<String> revokedByNow = _revokedKeys(include, asOf, useVoid);
    for (final _Node n in order) {
      if (include != null && n.topo != 0 && !include.contains(n.h)) continue; // the genesis is in every fold
      if (n.reject != null || (useVoid && n.voided)) continue;
      final int? act = _activation(n, asOf);
      if (act == null) continue;
      final Map<String, Object?> b = n.e.body;
      // The size limits are applied where an entry TAKES EFFECT, in the one canonical order, not where it was
      // written: a grown-up who proposes fifteen devices before any is accepted still ends with at most twelve.
      if (n.type == EntryType.memberAdd) {
        final String k = b['kind']! as String;
        final int have = st.members.values.where((_Mem m) => m.kind == k && !st.deadGids.contains(m.gidHex)).length;
        if (have >= (k == 'guardian' ? kMaxGuardians : kMaxCarers)) continue;
      } else if (n.type == EntryType.deviceAdd) {
        final Iterable<LedgerDevice> live = st.devices.values.where((LedgerDevice d) =>
            !revokedByNow.contains(d.keyHex) && !(d.gidHex != null && st.deadGids.contains(d.gidHex)));
        if (b['kind'] == 'guardian') {
          final String gid = hexOf(b['gid']! as Uint8List);
          if (live.where((LedgerDevice d) => d.gidHex == gid).length >= kMaxDevicesPerGuardian) continue;
        } else if (live.where((LedgerDevice d) => d.kind == 'child').length >= kMaxChildDevices) {
          continue;
        }
      }
      switch (n.type) {
        case EntryType.genesis:
          final DeviceRecord dev = DeviceRecord.fromValue(b['dev'])!;
          final String gid = hexOf(b['gid']! as Uint8List);
          st.members[gid] = _Mem(gid, b['name']! as String, 'guardian', null, act);
          st.devices[hexOf(dev.key)] = LedgerDevice(
              key: dev.key, kind: 'guardian', gidHex: gid, childId: null, name: b['name']! as String,
              agree: dev.agree, activatedAtMs: act, settleUntilMs: 0, legacy: false, addedByHex: n.h);
          st.knownGids.add(gid);
          st.knownKeys.add(hexOf(dev.key));
          policyNodes.add(n);
          break;
        case EntryType.memberAdd:
          final DeviceRecord dev = DeviceRecord.fromValue(b['dev'])!;
          final String gid = hexOf(b['gid']! as Uint8List);
          final String kind = b['kind']! as String;
          st.members[gid] = _Mem(gid, b['name']! as String, kind, MemberProfile.fromValue(b['profile']), act,
              st.devices[n.signerHex]?.gidHex);
          st.devices[hexOf(dev.key)] = LedgerDevice(
              key: dev.key, kind: kind, gidHex: gid, childId: null, name: b['name']! as String, agree: dev.agree,
              activatedAtMs: act, settleUntilMs: act + n.settleHours * 3600000, legacy: false, addedByHex: n.h);
          st.knownGids.add(gid);
          st.knownKeys.add(hexOf(dev.key));
          break;
        case EntryType.deviceAdd:
          final DeviceRecord dev = DeviceRecord.fromValue(b['dev'])!;
          final bool guardian = b['kind'] == 'guardian';
          st.devices[hexOf(dev.key)] = LedgerDevice(
              key: dev.key,
              kind: guardian ? 'guardian' : 'child',
              gidHex: guardian ? hexOf(b['gid']! as Uint8List) : null,
              childId: b['childId'] as String?,
              name: b['name']! as String,
              agree: dev.agree,
              activatedAtMs: act,
              settleUntilMs: guardian ? act + n.settleHours * 3600000 : 0,
              legacy: b['legacy']! as bool,
              addedByHex: n.h);
          st.knownKeys.add(hexOf(dev.key));
          break;
        case EntryType.deviceRevoke:
          revokes.add(n);
          break;
        case EntryType.deviceRevokeCancel:
          cancelled.add(hexOf(b['revoke']! as Uint8List));
          break;
        case EntryType.guardianLeave:
        case EntryType.guardianRemove:
          st.deadGids.add(hexOf(b['gid']! as Uint8List));
          break;
        case EntryType.policySet:
          policyNodes.add(n);
          break;
        case EntryType.keyRotate:
          if ((b['epoch']! as int) > st.epoch) st.epoch = b['epoch']! as int;
          break;
        case EntryType.accessPause:
          pauseNodes.add(n);
          break;
        case EntryType.accessResume:
          resumeNodes.add(n);
          break;
        case EntryType.accessEnd:
          if (b['reason'] == 'ended') {
            st.deadGids.add(hexOf(b['gid']! as Uint8List)); // a carer, ended by the parent who welcomed them (or with their yes)
          } else {
            noticeEnds.add(n);
          }
          break;
        case EntryType.accessEndCancel:
          endCancelled.add(hexOf(b['end']! as Uint8List));
          break;
        case EntryType.limitsAgree:
        case EntryType.limitsTighten:
          limitNodes.add(n);
          break;
        case EntryType.standingOk:
          standingNodes.add(n);
          break;
        default:
          break;
      }
    }
    // A notice ends someone only when its wait is over and the one who gave it has not taken it back. Taken in the order
    // the waits end, a parent who has already been removed cannot also remove, and the last parent is never removed.
    final List<_Node> orderedEnds = List<_Node>.of(noticeEnds)
      ..sort((_Node a, _Node b) {
        final int c = a.e.issuedAtMs.compareTo(b.e.issuedAtMs);
        return c != 0 ? c : a.h.compareTo(b.h);
      });
    for (final _Node e in orderedEnds) {
      if (endCancelled.contains(e.h)) continue;
      final String gid = hexOf(e.e.body['gid']! as Uint8List);
      final String by = st.devices[e.signerHex]?.gidHex ?? '';
      if (st.deadGids.contains(by) || st.deadGids.contains(gid) || !st.members.containsKey(gid)) continue;
      // A notice written against an old head with an old time would skip its own wait. It counts only if neither the one
      // who gave it nor the one it is about has written, off to the side of it, anything later than it (see _staleNotice).
      if (_staleNotice(e, include, by, gid, st)) continue;
      final int eff = e.e.issuedAtMs + kEndNoticeMs;
      if (eff > asOf) {
        st.pendingEnds.putIfAbsent(gid, () => EndNotice(gid, by, e.e.issuedAtMs, eff, e.h));
        continue;
      }
      if (st.members[gid]!.kind == 'guardian') {
        final bool another = st.members.values.any((_Mem m) => m.kind == 'guardian' && m.gidHex != gid && !st.deadGids.contains(m.gidHex));
        if (!another) continue;
      }
      st.deadGids.add(gid);
    }
    // Pauses: in force unless a resume that FOLLOWS the pause covers it. A resume that never saw it changes nothing, so a
    // pause always beats a concurrent resume.
    for (final _Node p in pauseNodes) {
      final String gid = hexOf(p.e.body['gid']! as Uint8List);
      if (st.deadGids.contains(gid) || st.paused.containsKey(gid)) continue;
      final bool covered = resumeNodes.any((_Node r) => hexOf(r.e.body['gid']! as Uint8List) == gid && r.anc.contains(p.h));
      if (covered) continue;
      st.paused[gid] = PauseInfo(gid, st.devices[p.signerHex]?.gidHex ?? '', p.e.issuedAtMs, p.h);
    }
    // Limits: an agreement replaces the list, a tightening adds to it. Both are only here if they took effect.
    for (final _Node n in limitNodes) {
      final String gid = hexOf(n.e.body['gid']! as Uint8List);
      final List<int> list = <int>[for (final Object? x in n.e.body['limits']! as List) x! as int];
      if (n.type == EntryType.limitsAgree) {
        st.limits[gid] = list;
      } else {
        st.limits[gid] = <int>{...(st.limits[gid] ?? const <int>[]), ...list}.toList()..sort();
      }
    }
    st.limits.removeWhere((String g, List<int> l) => l.isEmpty || st.deadGids.contains(g));
    // Standing OK: of a parent's newest entries (the ones no other of theirs follows) the strictest stands, so taking one
    // back by writing a shorter one always works, even beside a longer one written at the same time.
    final Map<String, List<_Node>> byGiver = <String, List<_Node>>{};
    for (final _Node n in standingNodes) {
      (byGiver[hexOf(n.e.body['gid']! as Uint8List)] ??= <_Node>[]).add(n);
    }
    for (final MapEntry<String, List<_Node>> g in byGiver.entries) {
      int? until;
      for (final _Node x in g.value) {
        if (g.value.any((_Node y) => !identical(x, y) && y.anc.contains(x.h))) continue;
        final int u = x.e.body['until']! as int;
        if (until == null || u < until) until = u;
      }
      if (until != null && !st.deadGids.contains(g.key)) st.standing[g.key] = until;
    }
    for (final _Node r in revokes) {
      if (cancelled.contains(r.h)) continue;
      if ((r.e.body['eff']! as int) <= asOf) st.deadKeys.add(hexOf(r.e.body['key']! as Uint8List));
    }
    st.knownKeys.addAll(st.deadKeys);
    st.devices.removeWhere((String k, LedgerDevice d) =>
        st.deadKeys.contains(k) || (d.gidHex != null && st.deadGids.contains(d.gidHex)));
    st.members.removeWhere((String g, _Mem m) => st.deadGids.contains(g));
    // The policy in force: the strictest of the entries nothing newer replaces.
    FamilyPolicy? pol;
    for (final _Node x in policyNodes) {
      if (policyNodes.any((_Node y) => !identical(x, y) && y.anc.contains(x.h))) continue;
      final FamilyPolicy xp = FamilyPolicy.fromValue(x.e.body['policy'])!;
      pol = pol == null ? xp : FamilyPolicy.strictest(pol, xp);
    }
    st.policy = pol ?? const FamilyPolicy();
    return st;
  }

  // ------------------------------------------------------------------------------------------------------------
  // Removal beats a concurrent add
  // ------------------------------------------------------------------------------------------------------------

  void _markVoids() {
    final List<_Node> good = <_Node>[for (final _Node n in order) if (n.reject == null) n];
    final Set<String> cancelled = <String>{
      for (final _Node n in good)
        if (n.type == EntryType.deviceRevokeCancel) hexOf(n.e.body['revoke']! as Uint8List),
    };
    final Map<_Node, Set<String>> tombKeys = <_Node, Set<String>>{}, tombGids = <_Node, Set<String>>{};
    final Map<String, String?> keyGid = <String, String?>{};
    final Map<String, List<_Node>> adders = <String, List<_Node>>{};
    for (final _Node n in good) {
      final Map<String, Object?> b = n.e.body;
      switch (n.type) {
        case EntryType.deviceRevoke:
          if (!cancelled.contains(n.h)) tombKeys[n] = <String>{hexOf(b['key']! as Uint8List)};
          break;
        case EntryType.guardianLeave:
          tombGids[n] = <String>{hexOf(b['gid']! as Uint8List)};
          break;
        case EntryType.guardianRemove:
          if (_activation(n, now) != null) tombGids[n] = <String>{hexOf(b['gid']! as Uint8List)};
          break;
        case EntryType.genesis:
        case EntryType.memberAdd:
        case EntryType.deviceAdd:
          final DeviceRecord dev = DeviceRecord.fromValue(b['dev'])!;
          final String kh = hexOf(dev.key);
          keyGid[kh] = b['gid'] is Uint8List ? hexOf(b['gid']! as Uint8List) : null;
          (adders[kh] ??= <_Node>[]).add(n);
          break;
        default:
          break;
      }
    }
    final List<_Node> rotations = <_Node>[for (final _Node n in good) if (n.type == EntryType.keyRotate) n];
    // Two parents who pause each other without having seen each other's pause: neither stands, so nobody is locked out of
    // both. The family is shown the fork and either can pause again knowing what the other did.
    final List<_Node> pauses = <_Node>[for (final _Node n in good) if (n.type == EntryType.accessPause) n];
    final Set<_Node> mutual = <_Node>{};
    for (final _Node a in pauses) {
      for (final _Node b in pauses) {
        if (identical(a, b) || a.anc.contains(b.h) || b.anc.contains(a.h)) continue;
        final String? ag = keyGid[a.signerHex], bg = keyGid[b.signerHex];
        if (ag != null && bg != null && ag == hexOf(b.e.body['gid']! as Uint8List) && bg == hexOf(a.e.body['gid']! as Uint8List)) {
          mutual..add(a)..add(b);
        }
      }
    }
    for (final _Node n in mutual) {
      n.voided = true;
      n.voidReason = 'mutual-pause';
    }
    for (final _Node n in good) {
      if (n.type == EntryType.genesis || n.voided) continue;
      final String sk = n.signerHex;
      final String? sg = keyGid[sk];
      // (a) The entry that made this signer a member is itself void: nothing the signer did survives.
      final List<_Node> mine = <_Node>[for (final _Node a in adders[sk] ?? const <_Node>[]) if (n.anc.contains(a.h)) a];
      if (mine.isNotEmpty && mine.every((_Node a) => a.voided)) {
        n.voided = true;
        n.voidReason = 'signer-was-added-by-a-void-entry';
        continue;
      }
      // (b) The signer is removed on a branch this entry is not part of.
      bool hit = false;
      for (final _Node t in <_Node>{...tombKeys.keys, ...tombGids.keys}) {
        if (identical(t, n)) continue;
        final bool hitsKey = (tombKeys[t]?.contains(sk) ?? false) || (sg != null && (tombGids[t]?.contains(sg) ?? false));
        if (!hitsKey) continue;
        if (n.anc.contains(t.h) || t.anc.contains(n.h)) continue; // ordered, not concurrent
        hit = true;
        break;
      }
      if (hit) {
        n.voided = true;
        n.voidReason = 'signer-removed-concurrently';
        continue;
      }
      // (b2) The signer was paused on a branch this entry is not part of, and this entry was written after that pause:
      // a pause beats a concurrent add. Leaving, defending their own phone and taking back their own notice still stand.
      if (n.type != EntryType.guardianLeave && n.type != EntryType.deviceRevokeCancel && n.type != EntryType.accessEndCancel) {
        for (final _Node p in pauses) {
          if (p.voided || sg == null || hexOf(p.e.body['gid']! as Uint8List) != sg) continue;
          if (n.anc.contains(p.h) || p.anc.contains(n.h) || n.e.issuedAtMs < p.e.issuedAtMs) continue;
          final bool covered = good.any((_Node r) =>
              r.type == EntryType.accessResume && r.anc.contains(p.h) && hexOf(r.e.body['gid']! as Uint8List) == sg);
          if (covered) continue;
          n.voided = true;
          n.voidReason = 'signer-paused-concurrently';
          break;
        }
        if (n.voided) continue;
      }
      // (c) Two concurrent additions of the same device key: the canonically earlier one keeps it.
      if (n.type == EntryType.memberAdd || n.type == EntryType.deviceAdd) {
        final String kh = hexOf(DeviceRecord.fromValue(n.e.body['dev'])!.key);
        for (final _Node o in adders[kh] ?? const <_Node>[]) {
          if (identical(o, n) || o.topo > n.topo || n.anc.contains(o.h) || o.anc.contains(n.h)) continue;
          n.voided = true;
          n.voidReason = 'device-key-claimed-by-an-earlier-entry';
          break;
        }
        if (n.voided) continue;
      }
      // (d) Two concurrent rotations to the same epoch would split the family's keys: the earlier one stands.
      if (n.type == EntryType.keyRotate) {
        for (final _Node o in rotations) {
          if (identical(o, n) || o.topo > n.topo || n.anc.contains(o.h) || o.anc.contains(n.h)) continue;
          if (o.e.body['epoch'] == n.e.body['epoch']) {
            n.voided = true;
            n.voidReason = 'rotation-conflict';
            break;
          }
        }
      }
    }
  }

  // ------------------------------------------------------------------------------------------------------------
  // Result
  // ------------------------------------------------------------------------------------------------------------

  LedgerState _finish(_St st, List<String> orphans) {
    final List<LedgerMember> members = <LedgerMember>[
      for (final _Mem m in st.members.values)
        LedgerMember(
          gidHex: m.gidHex, name: m.name, kind: m.kind, profile: m.profile, activatedAtMs: m.activatedAt,
          welcomedByGidHex: m.welcomedBy,
          deviceKeysHex: <String>[for (final LedgerDevice d in st.devicesOf(m.gidHex)) d.keyHex]..sort(),
        ),
    ]..sort((LedgerMember a, LedgerMember b) => a.gidHex.compareTo(b.gidHex));
    final List<LedgerDevice> devices = st.devices.values.toList()
      ..sort((LedgerDevice a, LedgerDevice b) => a.keyHex.compareTo(b.keyHex));
    final List<PendingItem> pending = <PendingItem>[];
    final Map<String, String> voided = <String, String>{};
    final List<String> history = <String>[];
    for (final _Node n in order) {
      if (n.reject != null) continue;
      if (n.voided) {
        voided[n.h] = n.voidReason ?? 'void';
        continue;
      }
      if (_activation(n, now) != null) {
        history.add(n.h);
        continue;
      }
      final _Gate g = n.gate!;
      final int? exp = g.exp;
      final String status = g.declined ? 'declined' : ((exp != null && now >= exp) ? 'lapsed' : 'pending');
      final Map<String, Object?> b = n.e.body;
      pending.add(PendingItem(
        n.h, n.type, status,
        b['gid'] is Uint8List ? hexOf(b['gid']! as Uint8List) : null,
        b['name'] as String?,
        exp,
        proposerGidHex: g.proposerGid,
        requiredGidsHex: g.required.toList()..sort(),
        yesGidsHex: g.yesAt.keys.where((String k) => k != '*').toList()..sort(),
        notBeforeMs: g.yesNotBefore,
      ));
    }
    // Forks and heads, over the entries that passed their own position check.
    final List<_Node> good = <_Node>[for (final _Node n in order) if (n.reject == null) n];
    final Map<String, List<_Node>> kids = <String, List<_Node>>{};
    final Set<String> hasKid = <String>{};
    for (final _Node n in good) {
      for (final Uint8List q in n.e.prev) {
        (kids[hexOf(q)] ??= <_Node>[]).add(n);
        hasKid.add(hexOf(q));
      }
    }
    final List<LedgerFork> forks = <LedgerFork>[];
    for (final MapEntry<String, List<_Node>> e in kids.entries) {
      if (e.value.length < 2) continue;
      final List<String> hs = <String>[for (final _Node k in e.value) k.h]..sort();
      final Set<String> signers = <String>{for (final _Node k in e.value) k.signerHex};
      forks.add(LedgerFork(e.key, hs, signers.length < e.value.length));
    }
    forks.sort((LedgerFork a, LedgerFork b) => a.parentHex.compareTo(b.parentHex));
    final List<Uint8List> heads = <Uint8List>[for (final _Node n in good) if (!hasKid.contains(n.h)) n.e.hash];
    final _Node g = genesis!;
    return LedgerState._ok(
      fid: g.e.body['fid']! as Uint8List,
      genesisHash: g.e.hash,
      policy: st.policy,
      epoch: st.epoch,
      members: members,
      devices: devices,
      pending: pending,
      rejected: rejected,
      voided: voided,
      orphans: orphans,
      forks: forks,
      heads: heads,
      legacyFids: <String>[for (final Object? s in g.e.body['legacyFids']! as List) s! as String],
      history: history,
      genesisDeviceKey: g.e.signer,
      nowMs: now,
      paused: <PauseInfo>[for (final PauseInfo p in st.paused.values) p]..sort((PauseInfo a, PauseInfo b) => a.hashHex.compareTo(b.hashHex)),
      endNotices: <EndNotice>[for (final EndNotice e in st.pendingEnds.values) e]..sort((EndNotice a, EndNotice b) => a.hashHex.compareTo(b.hashHex)),
      limits: <String, List<int>>{for (final MapEntry<String, List<int>> e in st.limits.entries) e.key: List<int>.unmodifiable(e.value)},
      standing: Map<String, int>.of(st.standing),
    );
  }
}
