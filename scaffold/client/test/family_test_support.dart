// Shared helpers for the family ledger tests: deterministic people, a clock, and a small builder that signs entries and
// votes the way the real devices would. Not a test file.
import 'dart:typed_data';

import 'package:olive_client/device_keys.dart';
import 'package:olive_client/family_ledger.dart';
import 'package:olive_client/family_ledger_state.dart';
import 'package:olive_client/family_profiles.dart';

const int t0 = 1800000000000;
const int hour = 3600000;
const int day = 24 * hour;

/// One device with its person id. Two [P]s made with the same [person] are two phones of one grown-up.
class P {
  P._(this.key, this.agree, this.cert, this.n, this.person);
  final DeviceKey key;
  final AgreementKey agree;
  final Uint8List cert;
  final int n, person;

  static Future<P> make(int n, {int? person}) async {
    final DeviceKey k = await DeviceKey.loadOrCreate(MemoryDeviceKeyRepository(), seedForTest: List<int>.filled(32, n));
    final AgreementKey a = await AgreementKey.fromSeed(List<int>.filled(32, 100 + n));
    return P._(k, a, await a.certify(k), n, person ?? n);
  }

  Uint8List get gid => Uint8List.fromList(List<int>.filled(16, person));
  String get gidHex => hexOf(gid);
  String get keyHex => hexOf(key.publicKey);
  DeviceRecord get rec => DeviceRecord(key: key.publicKey, agree: agree.publicKey, cert: cert);
  Map<String, Object?> get recValue => rec.toValue();

  /// A device record with no agreement key (a legacy tablet).
  Map<String, Object?> get bareValue => DeviceRecord(key: key.publicKey).toValue();
}

List<Uint8List> sortedGids(Iterable<P> ps) {
  final List<Uint8List> out = <Uint8List>[for (final P p in ps) p.gid];
  out.sort((Uint8List a, Uint8List b) => hexOf(a).compareTo(hexOf(b)));
  final Set<String> seen = <String>{};
  return <Uint8List>[for (final Uint8List g in out) if (seen.add(hexOf(g))) g];
}

/// A family under test: the entries and votes so far, a clock that only moves forward, and the pin.
class Fam {
  Fam._(this.entries, this.pin, this.founder);
  final List<LedgerEntry> entries;
  final List<LedgerVote> votes = <LedgerVote>[];
  final FamilyPin pin;
  final P founder;
  int clock = t0;

  LedgerEntry get genesis => entries.first;

  static Future<Fam> found(P founder, {FamilyPolicy policy = const FamilyPolicy(), List<String> legacyFids = const <String>[]}) async {
    final LedgerEntry g = await LedgerEntry.sign(founder.key,
        type: EntryType.genesis,
        prev: const <List<int>>[],
        issuedAtMs: t0,
        body: <String, Object?>{
          'v': 1,
          'fid': Uint8List.fromList(List<int>.filled(16, 9)),
          'gid': founder.gid,
          'name': 'Mom',
          'dev': founder.recValue,
          'policy': policy.toValue(),
          'legacyFids': legacyFids,
          'fkc': Uint8List(32),
          'gkc': Uint8List(32),
        });
    return Fam._(<LedgerEntry>[g], FamilyPin(<int>[...List<int>.filled(16, 9)], g.hash), founder);
  }

  Future<LedgerState> state([int? now]) =>
      reduceLedger(entries: entries, votes: votes, nowMs: now ?? clock + hour, pin: pin);

  /// Signs and records an entry. [prev] defaults to the current heads. The clock moves one minute first unless [at] is given.
  Future<LedgerEntry> add(P by, String type, Map<String, Object?> body, {List<List<int>>? prev, int? at}) async {
    if (at == null) clock += 60000;
    final int when = at ?? clock;
    final List<List<int>> p = prev ?? (await state(when + hour)).heads;
    final LedgerEntry e = await LedgerEntry.sign(by.key, type: type, prev: p, body: body, issuedAtMs: when);
    entries.add(e);
    return e;
  }

  Future<LedgerVote> vote(P by, LedgerEntry target, String answer, {int? at}) async {
    final LedgerVote v = await LedgerVote.sign(by.key, target: target.hash, answer: answer, atMs: at ?? (clock += 60000));
    votes.add(v);
    return v;
  }

  /// A member.add body. [electors] are the people asked (the proposer included).
  Map<String, Object?> memberBody(
    P cand, {
    String kind = 'guardian',
    Preset preset = Preset.parent,
    required Iterable<P> electors,
    String rule = 'all',
    int? exp,
    String name = 'Sam',
    MemberProfile? profile,
    Uint8List? proposalId,
  }) {
    final MemberProfile pr = profile ?? MemberProfile.defaults(preset);
    return <String, Object?>{
      'gid': cand.gid,
      'name': name,
      'kind': kind,
      'profile': pr.toValue(),
      'dev': cand.recValue,
      'proposal': <String, Object?>{
        'id': proposalId ?? Uint8List.fromList(List<int>.filled(16, 77)),
        'exp': exp ?? (clock + 60000 + proposalLifetimeMs(pr.preset)),
        'electorate': sortedGids(electors),
        'rule': rule,
      },
    };
  }

  /// Welcomes [cand] as a parent: the proposal, every other elector's yes, and the candidate's own acceptance.
  Future<LedgerEntry> welcomeParent(P by, P cand, {required List<P> others}) async {
    final LedgerEntry e = await add(by, EntryType.memberAdd, memberBody(cand, electors: <P>[by, ...others]));
    for (final P o in others) {
      await vote(o, e, 'yes');
    }
    await vote(cand, e, 'yes');
    return e;
  }

  Map<String, Object?> childBody(P dev, {String childId = 'ivy', String name = 'Tablet', bool legacy = false, bool bare = false}) =>
      <String, Object?>{
        'kind': 'child',
        'gid': null,
        'childId': childId,
        'name': name,
        'dev': bare ? dev.bareValue : dev.recValue,
        'legacy': legacy,
        'orig': legacy ? 1700000000000 : null,
      };

  /// A child device added by [by] and accepted by the child device itself.
  Future<LedgerEntry> addChild(P by, P dev, {String childId = 'ivy'}) async {
    final LedgerEntry e = await add(by, EntryType.deviceAdd, childBody(dev, childId: childId));
    await vote(dev, e, 'yes');
    return e;
  }

  Map<String, Object?> revokeBody(P target, {String reason = 'lost', int? eff}) =>
      <String, Object?>{'key': target.key.publicKey, 'reason': reason, 'eff': eff ?? (clock + 60000)};

  /// A compact, order-stable description of a state: used to prove two reductions agree.
  static String summary(LedgerState s) => <String>[
        'ok=${s.ok}',
        'epoch=${s.epoch}',
        'policy=${s.policy.toValue()}',
        'members=${<String>[for (final LedgerMember m in s.members) '${m.gidHex}/${m.kind}/${m.deviceKeysHex.join('+')}']}',
        'devices=${<String>[for (final LedgerDevice d in s.devices) '${d.keyHex}/${d.kind}/${d.settleUntilMs}']}',
        'pending=${<String>[for (final PendingItem p in s.pending) '${p.hashHex}/${p.status}']}',
        'voided=${(s.voided.keys.toList()..sort())}',
        'rejected=${(s.rejected.entries.map((MapEntry<String, String> e) => '${e.key}:${e.value}').toList()..sort())}',
        'forks=${<String>[for (final LedgerFork f in s.forks) '${f.parentHex}>${f.childrenHex.join(',')}']}',
        'heads=${(s.heads.map(hexOf).toList()..sort())}',
        'history=${s.history}',
      ].join('\n');
}
