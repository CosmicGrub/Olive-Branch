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
// PROVISIONAL. The design (section 11) says the merge rule of 3.2 is the piece most likely to need revision once it
// is fuzzed, and this is a first model of it, tested on the hostile cases listed in the test file. Read the residual
// risks in the PR description before relying on it. Not built here: any storage, the gossip, the settle-in screens,
// the fork "accept" tap, rate limits and cooldown, the 72-hour hold for a family of one, and the pause/limits/standing
// behaviours (those entry types are reserved: valid, recorded, no effect).
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
  });
  final String gidHex, name;

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
  PendingItem(this.hashHex, this.type, this.status, this.subjectGidHex, this.name, this.expMs);
  final String hashHex, type, status;
  final String? subjectGidHex, name;
  final int? expMs;
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
    return d != null && d.kind == 'guardian' && !d.settlingAt(atMs);
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
  });
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
  _Mem(this.gidHex, this.name, this.kind, this.profile, this.activatedAt);
  final String gidHex, name, kind;
  final MemberProfile? profile;
  final int activatedAt;
}

class _St {
  final Map<String, _Mem> members = <String, _Mem>{};
  final Map<String, LedgerDevice> devices = <String, LedgerDevice>{};
  final Set<String> knownKeys = <String>{}, knownGids = <String>{}, deadKeys = <String>{}, deadGids = <String>{};
  FamilyPolicy policy = const FamilyPolicy();
  int epoch = 0;

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
    switch (e.type) {
      case EntryType.memberAdd:
        bad = settling ? 'signer-settling' : await _memberAdd(n, s, d);
        break;
      case EntryType.deviceAdd:
        bad = settling ? 'signer-settling' : await _deviceAdd(n, s, d);
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
        bad = settling ? 'signer-settling' : _policySet(n, s, d);
        break;
      case EntryType.keyRotate:
        bad = settling ? 'signer-settling' : _keyRotate(n, s);
        break;
      default: // the reserved types
        if (settling) {
          bad = 'signer-settling';
        } else if (!s.members.containsKey(hexOf(b['gid']! as Uint8List))) {
          bad = 'unknown-subject';
        }
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
    n.gate = _gateFor(s, proposerGid: proposerGid, required: given.where((String x) => x != proposerGid).toSet(),
        acceptKey: keyHex, exp: exp, includeSettlingVoters: false, asOf: n.e.issuedAtMs);
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

  _St _fold(Set<String>? include, int asOf, {required bool useVoid}) {
    final _St st = _St();
    final List<_Node> policyNodes = <_Node>[];
    final List<_Node> revokes = <_Node>[];
    final Set<String> cancelled = <String>{};
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
          st.members[gid] = _Mem(gid, b['name']! as String, kind, MemberProfile.fromValue(b['profile']), act);
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
        default:
          break; // reserved types change nothing
      }
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
    for (final _Node n in good) {
      if (n.type == EntryType.genesis) continue;
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
    );
  }
}
