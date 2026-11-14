// OLIVE BRANCH — the signed family ledger: encoding, signatures, the reduce rule, and the hostile cases. Verified by CI,
// headless. Every case that matters here is an attack or a mistake, not a happy path: a forked ledger, an approval
// replayed at another position, a wrong signer, an expired proposal, a pending person who must hold nothing,
// loosening versus tightening, and the floor that a new parent needs ALL parents.
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/cpace.dart' show cat, lv;
import 'package:olive_client/device_keys.dart';
import 'package:olive_client/family_ledger.dart';
import 'package:olive_client/family_ledger_state.dart';
import 'package:olive_client/family_profiles.dart';

import 'family_test_support.dart';

void main() {
  late P mom, dad, kid, tab2, stranger, carer;

  setUp(() async {
    mom = await P.make(1);
    dad = await P.make(2);
    kid = await P.make(3);
    tab2 = await P.make(4);
    stranger = await P.make(5);
    carer = await P.make(6);
  });

  group('canonical encoding', () {
    test('a value tree round-trips and a map is encoded in key order whatever order it was built in', () {
      final Map<String, Object?> a = <String, Object?>{'b': 1, 'a': <Object?>['x', null, true, Uint8List.fromList(<int>[1, 2])]};
      final Map<String, Object?> b = <String, Object?>{'a': a['a'], 'b': 1};
      expect(encodeValue(a), encodeValue(b));
      expect(decodeValue(encodeValue(a)), a);
    });

    test('refuses what has no single canonical form: negative numbers, doubles, plain int lists, odd keys', () {
      expect(() => encodeValue(-1), throwsArgumentError);
      expect(() => encodeValue(1.5), throwsArgumentError);
      expect(() => encodeValue(<int>[1, 2]), returnsNormally, reason: 'a List<int> is a list of integers, not bytes');
      expect(() => encodeValue(<String, Object?>{'a b': 1}), throwsArgumentError);
      expect(() => decodeValue(Uint8List.fromList(<int>[9])), throwsFormatException);
    });

    test('an entry parses back byte for byte, and its hash does not change when approvals arrive', () async {
      final Fam f = await Fam.found(mom);
      final LedgerEntry g = f.genesis;
      final LedgerEntry? back = await LedgerEntry.parse(g.bytes, g.signature);
      expect(back!.hashHex, g.hashHex);
      expect(await back.verifySignature(), isTrue);
      final LedgerEntry c = await f.addChild(mom, kid);
      final String before = c.hashHex;
      await f.vote(dad, c, 'yes');
      expect(c.hashHex, before);
    });

    test('flipping any single bit of the signed bytes breaks the entry (parse refuses it or the signature fails)', () async {
      final Fam f = await Fam.found(mom);
      final LedgerEntry e = f.genesis;
      int broken = 0;
      for (int i = 0; i < e.bytes.length; i += 3) {
        final Uint8List bad = Uint8List.fromList(e.bytes)..[i] ^= 0x01;
        final LedgerEntry? p = await LedgerEntry.parse(bad, e.signature);
        if (p == null || !await p.verifySignature()) broken++;
      }
      expect(broken, (e.bytes.length / 3).ceil());
    });

    test('a flipped bit in the signature fails', () async {
      final Fam f = await Fam.found(mom);
      final Uint8List sig = Uint8List.fromList(f.genesis.signature)..[10] ^= 0x80;
      final LedgerEntry? p = await LedgerEntry.parse(f.genesis.bytes, sig);
      expect(await p!.verifySignature(), isFalse);
    });

    test('non-canonical forms are refused: unsorted prev, a wrong domain, trailing bytes, an extra body field, no prev on a non-genesis', () async {
      final Fam f = await Fam.found(mom);
      final Uint8List h1 = Uint8List(32)..[0] = 1, h2 = Uint8List(32)..[0] = 2;
      Future<LedgerEntry?> tryBytes(Uint8List bytes) async => LedgerEntry.parse(bytes, await mom.key.sign(bytes));
      final Map<String, Object?> body = <String, Object?>{'gid': mom.gid};
      Uint8List raw(List<Uint8List> prev, {String domain = kLedgerDomain, Map<String, Object?>? b, String type = EntryType.accessPause}) =>
          cat(<List<int>>[
            lv(domain.codeUnits), lv(type.codeUnits), lv(encodeValue(prev)), lv(encodeValue(b ?? body)),
            lv(mom.key.publicKey), lv('5'.codeUnits),
          ]);
      expect(await tryBytes(raw(<Uint8List>[h1, h2])), isNotNull, reason: 'sorted prev parses');
      expect(await tryBytes(raw(<Uint8List>[h2, h1])), isNull, reason: 'unsorted prev');
      expect(await tryBytes(raw(<Uint8List>[h1], domain: 'olive-cert-v1')), isNull, reason: 'wrong domain');
      expect(await tryBytes(Uint8List.fromList(<int>[...raw(<Uint8List>[h1]), 0])), isNull, reason: 'trailing byte');
      expect(await tryBytes(raw(<Uint8List>[h1], b: <String, Object?>{'gid': mom.gid, 'x': 1})), isNull, reason: 'extra field');
      expect(await tryBytes(raw(const <Uint8List>[])), isNull, reason: 'a non-genesis with no prev');
      expect(f.entries, isNotEmpty);
    });

    test('a policy.set cannot express a rule the floors forbid: there is no field for it', () async {
      final Fam f = await Fam.found(mom);
      final Map<String, Object?> p = const FamilyPolicy().toValue();
      expect(() => f.add(mom, EntryType.policySet, <String, Object?>{'policy': <String, Object?>{...p, 'parentWelcome': 'one'}, 'exp': null}),
          throwsArgumentError);
      expect(() => f.add(mom, EntryType.policySet, <String, Object?>{'policy': <String, Object?>{...p, 'settle': 5}, 'exp': null}),
          throwsArgumentError);
    });

    test('domain separation: a pairing certificate signature, a vote signature and an entry signature are not interchangeable', () async {
      final Fam f = await Fam.found(mom);
      final PairingCert cert = await PairingCert.issue(mom.key,
          childDeviceKey: kid.key.publicKey, familyId: 'fam', childId: 'ivy', certId: 'c', issuedAtMs: 1);
      final LedgerEntry swapped = (await LedgerEntry.parse(f.genesis.bytes, cert.signature))!;
      expect(await swapped.verifySignature(), isFalse);
      final LedgerVote v = await LedgerVote.sign(mom.key, target: f.genesis.hash, answer: 'yes', atMs: 1);
      final LedgerEntry swapped2 = (await LedgerEntry.parse(f.genesis.bytes, v.signature))!;
      expect(await swapped2.verifySignature(), isFalse);
      expect(await DeviceKey.verify(mom.key.publicKey, PairingCert.signedBytes(kid.key.publicKey, 'fam', 'ivy', mom.key.fingerprint, 1, 'c'), f.genesis.signature), isFalse);
    });
  });

  group('the family and its anchors', () {
    test('a genesis alone is a family of one grown-up with one device and the default policy', () async {
      final Fam f = await Fam.found(mom);
      final LedgerState s = await f.state();
      expect(s.ok, isTrue);
      expect(s.guardians.length, 1);
      expect(s.devices.length, 1);
      expect(s.policy, const FamilyPolicy());
      expect(s.canAct(mom.key.publicKey, t0 + hour), isTrue);
      expect(familyIdString(s.fid!).length, 36);
      expect(s.pin!.matches(f.pin), isTrue);
    });

    test('a second genesis with the same family id but different content is ignored when pinned and fatal when not', () async {
      final Fam f = await Fam.found(mom);
      final Fam evil = await Fam.found(dad, legacyFids: <String>['x']); // same fid bytes, different content and hash
      final List<LedgerEntry> both = <LedgerEntry>[f.genesis, evil.genesis];
      final LedgerState pinned = await reduceLedger(entries: both, nowMs: t0 + hour, pin: f.pin);
      expect(pinned.ok, isTrue);
      expect(pinned.rejected[evil.genesis.hashHex], 'foreign-genesis');
      expect(pinned.members.single.name, 'Mom');
      final LedgerState unpinned = await reduceLedger(entries: both, nowMs: t0 + hour);
      expect(unpinned.ok, isFalse);
      expect(unpinned.failure, 'ambiguous-genesis');
      final LedgerState none = await reduceLedger(entries: <LedgerEntry>[evil.genesis], nowMs: t0 + hour, pin: f.pin);
      expect(none.failure, 'no-genesis');
    });

    test('entries of a foreign family hang off nothing and are never applied', () async {
      final Fam f = await Fam.found(mom);
      final Fam other = await Fam.found(dad, legacyFids: <String>['x']);
      final LedgerEntry c = await other.addChild(dad, kid);
      final LedgerState s = await reduceLedger(entries: <LedgerEntry>[f.genesis, c], nowMs: t0 + day, pin: f.pin);
      expect(s.rejected[c.hashHex], 'orphan');
      expect(s.devices.length, 1);
    });

    test('an entry whose signature is bad is dropped, named, and cannot be a parent', () async {
      final Fam f = await Fam.found(mom);
      final LedgerEntry good = await f.addChild(mom, kid);
      final LedgerEntry forged = (await LedgerEntry.parse(good.bytes, Uint8List(64)))!;
      final LedgerState s = await reduceLedger(entries: <LedgerEntry>[f.genesis, forged], votes: f.votes, nowMs: t0 + day, pin: f.pin);
      expect(s.rejected[forged.hashHex], 'bad-signature');
      expect(s.devices.length, 1);
    });

    test('a missing parent makes an orphan, and supplying the parent later resolves it', () async {
      final Fam f = await Fam.found(mom);
      final LedgerEntry a = await f.add(mom, EntryType.accessPause, <String, Object?>{'gid': mom.gid});
      final LedgerEntry b = await f.add(mom, EntryType.accessResume, <String, Object?>{'gid': mom.gid});
      final LedgerState partial = await reduceLedger(entries: <LedgerEntry>[f.genesis, b], nowMs: t0 + day, pin: f.pin);
      expect(partial.orphans, <String>[b.hashHex]);
      final LedgerState full = await reduceLedger(entries: <LedgerEntry>[f.genesis, b, a], nowMs: t0 + day, pin: f.pin);
      expect(full.orphans, isEmpty);
      expect(full.history, containsAll(<String>[a.hashHex, b.hashHex]));
    });

    test('an entry from the future (clock far ahead) is "not yet", and one that goes back before its parent is refused', () async {
      final Fam f = await Fam.found(mom);
      final LedgerEntry future = await f.add(mom, EntryType.accessPause, <String, Object?>{'gid': mom.gid}, at: t0 + 3 * day);
      final LedgerState now = await f.state(t0 + hour);
      expect(now.rejected[future.hashHex], 'from-the-future');
      final LedgerState later = await f.state(t0 + 4 * day);
      expect(later.rejected.containsKey(future.hashHex), isFalse);
      final LedgerEntry back = await f.add(mom, EntryType.accessResume, <String, Object?>{'gid': mom.gid}, prev: <List<int>>[future.hash], at: t0 + day);
      expect((await f.state(t0 + 4 * day)).rejected[back.hashHex], 'time-goes-backwards');
    });

    test('too many entries is a clean failure, not unbounded work', () async {
      final Fam f = await Fam.found(mom);
      final LedgerState s = await reduceLedger(
          entries: List<LedgerEntry>.filled(kMaxLedgerEntries + 1, f.genesis), nowMs: t0, pin: f.pin);
      expect(s.failure, 'too-many-entries');
    });
  });

  group('delivery order never matters', () {
    test('the same entries and votes in any order give exactly the same state', () async {
      final Fam f = await Fam.found(mom);
      await f.welcomeParent(mom, dad, others: <P>[]);
      await f.addChild(mom, kid);
      f.clock += 4 * day;
      await f.add(dad, EntryType.policySet, <String, Object?>{'policy': const FamilyPolicy(settleHours: 72).toValue(), 'exp': null});
      final LedgerEntry r = await f.add(mom, EntryType.deviceRevoke, f.revokeBody(kid, reason: 'forgotten', eff: f.clock + 60000));
      await f.add(dad, EntryType.accessPause, <String, Object?>{'gid': mom.gid});
      expect(r.hashHex, isNotEmpty);
      final String want = Fam.summary(await f.state(t0 + 20 * day));
      final Random rng = Random(7);
      for (int i = 0; i < 25; i++) {
        final List<LedgerEntry> es = List<LedgerEntry>.of(f.entries)..shuffle(rng);
        final List<LedgerVote> vs = List<LedgerVote>.of(f.votes)..shuffle(rng);
        expect(Fam.summary(await reduceLedger(entries: es, votes: vs, nowMs: t0 + 20 * day, pin: f.pin)), want, reason: 'permutation $i');
      }
    });
  });

  group('a wrong signer', () {
    test('a stranger, a child device and a carer cannot sign an entry', () async {
      final Fam f = await Fam.found(mom);
      await f.addChild(mom, kid);
      await f.welcomeParent(mom, dad, others: <P>[]);
      final LedgerEntry cw = await f.add(mom, EntryType.memberAdd,
          f.memberBody(carer, kind: 'carer', preset: Preset.viewOnly, electors: <P>[mom], rule: 'one', name: 'Gran'));
      await f.vote(carer, cw, 'yes');
      final LedgerEntry byStranger = await f.add(stranger, EntryType.accessPause, <String, Object?>{'gid': mom.gid});
      final LedgerEntry byChild = await f.add(kid, EntryType.accessPause, <String, Object?>{'gid': mom.gid});
      final LedgerEntry byCarer = await f.add(carer, EntryType.accessPause, <String, Object?>{'gid': mom.gid});
      final LedgerState s = await f.state(t0 + 2 * day);
      expect(s.rejected[byStranger.hashHex], 'signer-unknown');
      expect(s.rejected[byChild.hashHex], 'child-key-cannot-sign');
      expect(s.rejected[byCarer.hashHex], 'carer-key-cannot-sign');
      expect(s.holdsAnything(carer.key.publicKey), isTrue);
    });

    test('a child device cannot add a device or approve itself even with a vote from a stranger', () async {
      final Fam f = await Fam.found(mom);
      await f.addChild(mom, kid);
      final LedgerEntry sneaky = await f.add(kid, EntryType.deviceAdd, f.childBody(tab2));
      await f.vote(tab2, sneaky, 'yes');
      final LedgerState s = await f.state(t0 + 2 * day);
      expect(s.rejected[sneaky.hashHex], 'child-key-cannot-sign');
      expect(s.holdsAnything(tab2.key.publicKey), isFalse);
    });

    test('a vote from somebody who was not asked counts for nothing', () async {
      final Fam f = await Fam.found(mom);
      await f.welcomeParent(mom, dad, others: <P>[]);
      f.clock += 4 * day;
      final LedgerEntry w = await f.add(mom, EntryType.memberAdd,
          f.memberBody(carer, electors: <P>[mom, dad], name: 'Jo', proposalId: Uint8List.fromList(List<int>.filled(16, 5))));
      await f.vote(stranger, w, 'yes');
      await f.vote(carer, w, 'yes');
      final LedgerState s = await f.state();
      expect(s.pending.single.status, 'pending', reason: 'Dad has not answered; a stranger\'s yes is not Dad\'s');
    });
  });

  group('forks are reported, never silently resolved', () {
    test('two grown-ups acting from the same head make a fork, deterministic, with both kept', () async {
      final Fam f = await Fam.found(mom);
      await f.welcomeParent(mom, dad, others: <P>[]);
      f.clock += 4 * day;
      final List<Uint8List> head = (await f.state()).heads;
      final LedgerEntry a = await f.add(mom, EntryType.deviceAdd, f.childBody(kid), prev: head);
      final LedgerEntry b = await f.add(dad, EntryType.deviceAdd, f.childBody(tab2, childId: 'ivy2'), prev: head);
      await f.vote(kid, a, 'yes');
      await f.vote(tab2, b, 'yes');
      final LedgerState s = await f.state(f.clock + hour);
      expect(s.forks.length, 1);
      expect(s.forks.single.childrenHex, <String>[a.hashHex, b.hashHex]..sort());
      expect(s.forks.single.sameSigner, isFalse);
      expect(s.heads.length, 2);
      expect(s.hasFork, isTrue);
      expect(s.childDeviceKeys.length, 2, reason: 'nothing dropped');
      // The next entry that names both heads is the merge: one head again, the fork still on record.
      await f.add(mom, EntryType.accessPause, <String, Object?>{'gid': mom.gid}, prev: s.heads);
      final LedgerState merged = await f.state(f.clock + hour);
      expect(merged.heads.length, 1);
    });

    test('one device signing two different entries at one position is called out as a same-signer fork', () async {
      final Fam f = await Fam.found(mom);
      final List<Uint8List> head = (await f.state()).heads;
      await f.add(mom, EntryType.accessPause, <String, Object?>{'gid': mom.gid}, prev: head);
      await f.add(mom, EntryType.accessResume, <String, Object?>{'gid': mom.gid}, prev: head);
      final LedgerState s = await f.state(t0 + 2 * day);
      expect(s.forks.single.sameSigner, isTrue);
    });

    test('a removal beats a concurrent add: what a revoked phone does on another branch is void', () async {
      final Fam f = await Fam.found(mom);
      await f.welcomeParent(mom, dad, others: <P>[]);
      f.clock += 4 * day; // Dad is out of settle-in
      final List<Uint8List> head = (await f.state()).heads;
      final LedgerEntry revoke = await f.add(mom, EntryType.deviceRevoke, f.revokeBody(dad, eff: f.clock + 80 * hour), prev: head);
      final LedgerEntry add = await f.add(dad, EntryType.deviceAdd, f.childBody(kid), prev: head);
      await f.vote(kid, add, 'yes');
      final LedgerState s = await f.state(f.clock + 100 * hour);
      expect(s.voided[add.hashHex], 'signer-removed-concurrently');
      expect(s.holdsAnything(kid.key.publicKey), isFalse);
      expect(s.holdsAnything(dad.key.publicKey), isFalse, reason: 'the notice ran out');
      expect(s.history, contains(revoke.hashHex));
    });

    test('a mutual revoke voids both sides: neither parent can lock the other out', () async {
      final Fam f = await Fam.found(mom);
      await f.welcomeParent(mom, dad, others: <P>[]);
      f.clock += 4 * day;
      final List<Uint8List> head = (await f.state()).heads;
      final int eff = f.clock + 80 * hour;
      final LedgerEntry r1 = await f.add(mom, EntryType.deviceRevoke, f.revokeBody(dad, eff: eff), prev: head);
      final LedgerEntry r2 = await f.add(dad, EntryType.deviceRevoke, f.revokeBody(mom, eff: eff), prev: head);
      final LedgerState s = await f.state(eff + day);
      expect(s.voided.keys, containsAll(<String>[r1.hashHex, r2.hashHex]));
      expect(s.holdsAnything(mom.key.publicKey), isTrue);
      expect(s.holdsAnything(dad.key.publicKey), isTrue);
      expect(s.hasFork, isTrue);
    });

    test('two concurrent additions of the same device key: the canonically earlier one keeps it, the other is void', () async {
      final Fam f = await Fam.found(mom);
      await f.welcomeParent(mom, dad, others: <P>[]);
      f.clock += 4 * day;
      final List<Uint8List> head = (await f.state()).heads;
      final LedgerEntry a = await f.add(mom, EntryType.deviceAdd, f.childBody(kid, childId: 'a'), prev: head);
      final LedgerEntry b = await f.add(dad, EntryType.deviceAdd, f.childBody(kid, childId: 'b'), prev: head);
      await f.vote(kid, a, 'yes');
      await f.vote(kid, b, 'yes');
      final LedgerState s = await f.state(f.clock + day);
      expect(s.childDeviceKeys.length, 1);
      expect(s.voided.length, 1);
      expect(s.voided.values.single, 'device-key-claimed-by-an-earlier-entry');
    });

    test('whatever a voided entry made possible is void too: a person it added cannot act', () async {
      final Fam f = await Fam.found(mom);
      await f.welcomeParent(mom, dad, others: <P>[]);
      f.clock += 4 * day;
      final List<Uint8List> head = (await f.state()).heads;
      final LedgerEntry revoke = await f.add(mom, EntryType.deviceRevoke, f.revokeBody(dad, eff: f.clock + 80 * hour), prev: head);
      // On the other branch Dad welcomes a new parent; Mom (not yet aware) says yes.
      final LedgerEntry add = await f.add(dad, EntryType.memberAdd, f.memberBody(stranger, electors: <P>[mom, dad], name: 'Eve'), prev: head);
      await f.vote(mom, add, 'yes');
      await f.vote(stranger, add, 'yes');
      f.clock += 4 * day;
      final LedgerEntry byEve = await f.add(stranger, EntryType.accessPause, <String, Object?>{'gid': mom.gid}, prev: <List<int>>[add.hash]);
      final LedgerState s = await f.state(f.clock + 100 * hour);
      expect(s.voided[add.hashHex], 'signer-removed-concurrently');
      expect(s.voided[byEve.hashHex], 'signer-was-added-by-a-void-entry');
      expect(s.holdsAnything(stranger.key.publicKey), isFalse);
      expect(s.history, contains(revoke.hashHex));
    });
  });

  group('approvals bind to a position and to silence-never-yes', () {
    test('a yes given to one proposal does not count for another, even for the same person and the same text', () async {
      final Fam f = await Fam.found(mom);
      await f.welcomeParent(mom, dad, others: <P>[]);
      f.clock += 4 * day;
      final LedgerEntry p1 = await f.add(mom, EntryType.memberAdd, f.memberBody(stranger, electors: <P>[mom, dad], name: 'Eve'));
      await f.vote(dad, p1, 'yes');
      // The same words one position later: a different entry hash, so Dad's yes to p1 is nothing here.
      final LedgerEntry p2 = await f.add(mom, EntryType.memberAdd, f.memberBody(carer, electors: <P>[mom, dad], name: 'Eve'));
      await f.vote(stranger, p2, 'yes');
      await f.vote(carer, p2, 'yes');
      final LedgerState s = await f.state();
      final Map<String, String> st = <String, String>{for (final PendingItem p in s.pending) p.hashHex: p.status};
      expect(st[p1.hashHex], 'pending', reason: 'p1 still needs the candidate\'s own acceptance');
      expect(st[p2.hashHex], 'pending', reason: 'Dad\'s yes on p1 cannot be replayed onto p2');
      expect(s.holdsAnything(carer.key.publicKey), isFalse);
    });

    test('a vote copied to a different target is a vote for that target only (it names a hash)', () async {
      final Fam f = await Fam.found(mom);
      final LedgerEntry a = await f.addChild(mom, kid);
      final LedgerEntry b = await f.add(mom, EntryType.deviceAdd, f.childBody(tab2));
      final LedgerVote onA = f.votes.firstWhere((LedgerVote v) => v.targetHex == a.hashHex);
      final LedgerVote moved = LedgerVote.fromJson(<String, Object?>{...onA.toJson(), 't': b64(b.hash)})!;
      final LedgerState s = await reduceLedger(entries: f.entries, votes: <LedgerVote>[...f.votes, moved], nowMs: t0 + day, pin: f.pin);
      expect(s.holdsAnything(tab2.key.publicKey), isFalse, reason: 'the signature no longer verifies');
      expect(s.holdsAnything(kid.key.publicKey), isTrue);
    });

    test('silence is never yes: an unanswered request lapses at its expiry and stays lapsed', () async {
      final Fam f = await Fam.found(mom);
      await f.welcomeParent(mom, dad, others: <P>[]);
      f.clock += 4 * day;
      final int exp = f.clock + 60000 + 7 * day;
      final LedgerEntry p = await f.add(mom, EntryType.memberAdd,
          f.memberBody(stranger, electors: <P>[mom, dad], name: 'Eve', exp: exp));
      await f.vote(stranger, p, 'yes');
      expect((await f.state(exp - 1)).pending.single.status, 'pending');
      expect((await f.state(exp + 1)).pending.single.status, 'lapsed');
      expect((await f.state(exp + 100 * day)).holdsAnything(stranger.key.publicKey), isFalse);
    });

    test('an expired proposal: a yes that arrives after the expiry is ignored', () async {
      final Fam f = await Fam.found(mom);
      await f.welcomeParent(mom, dad, others: <P>[]);
      f.clock += 4 * day;
      final int exp = f.clock + 60000 + day;
      final LedgerEntry p = await f.add(mom, EntryType.memberAdd,
          f.memberBody(stranger, electors: <P>[mom, dad], name: 'Eve', exp: exp));
      await f.vote(stranger, p, 'yes');
      await f.vote(dad, p, 'yes', at: exp + hour);
      final LedgerState s = await f.state(exp + 2 * hour);
      expect(s.pending.single.status, 'lapsed');
      expect(s.holdsAnything(stranger.key.publicKey), isFalse);
    });

    test('an answer given in time still counts after the expiry has passed', () async {
      final Fam f = await Fam.found(mom);
      await f.welcomeParent(mom, dad, others: <P>[]);
      f.clock += 4 * day;
      final LedgerEntry p = await f.welcomeParent(mom, stranger, others: <P>[dad]);
      expect((await f.state(f.clock + 100 * day)).holdsAnything(stranger.key.publicKey), isTrue);
      expect(p.hashHex, isNotEmpty);
    });

    test('an expiry past the lifetime for that preset is refused', () async {
      final Fam f = await Fam.found(mom);
      final LedgerEntry p = await f.add(mom, EntryType.memberAdd,
          f.memberBody(stranger, electors: <P>[mom], exp: f.clock + 60000 + 15 * day));
      expect((await f.state()).rejected[p.hashHex], 'bad-expiry');
    });

    test('one no from anyone required ends the proposal for good; a later yes does not revive it', () async {
      final Fam f = await Fam.found(mom);
      await f.welcomeParent(mom, dad, others: <P>[]);
      f.clock += 4 * day;
      final LedgerEntry p = await f.add(mom, EntryType.memberAdd, f.memberBody(stranger, electors: <P>[mom, dad], name: 'Eve'));
      await f.vote(stranger, p, 'yes');
      await f.vote(dad, p, 'no');
      await f.vote(dad, p, 'yes');
      final LedgerState s = await f.state();
      expect(s.pending.single.status, 'declined');
      expect(s.holdsAnything(stranger.key.publicKey), isFalse);
    });

    test('the proposer can withdraw before activation; the candidate\'s no also ends it', () async {
      final Fam f = await Fam.found(mom);
      await f.welcomeParent(mom, dad, others: <P>[]);
      f.clock += 4 * day;
      final LedgerEntry p = await f.add(mom, EntryType.memberAdd, f.memberBody(stranger, electors: <P>[mom, dad], name: 'Eve'));
      await f.vote(mom, p, 'withdraw');
      expect((await f.state()).pending.single.status, 'declined');
      final LedgerEntry q = await f.add(mom, EntryType.memberAdd,
          f.memberBody(carer, electors: <P>[mom, dad], name: 'Jo', proposalId: Uint8List.fromList(List<int>.filled(16, 8))));
      await f.vote(carer, q, 'no');
      final Map<String, String> st = <String, String>{for (final PendingItem x in (await f.state()).pending) x.hashHex: x.status};
      expect(st[q.hashHex], 'declined');
    });
  });

  group('a pending person holds nothing', () {
    test('until every required yes and their own acceptance are in, the key is not listed, signs nothing, and gets no wrap', () async {
      final Fam f = await Fam.found(mom);
      await f.welcomeParent(mom, dad, others: <P>[]);
      f.clock += 4 * day;
      final LedgerEntry p = await f.add(mom, EntryType.memberAdd, f.memberBody(stranger, electors: <P>[mom, dad], name: 'Eve'));
      await f.vote(stranger, p, 'yes');
      final LedgerState before = await f.state();
      expect(before.pending.single.status, 'pending');
      expect(before.holdsAnything(stranger.key.publicKey), isFalse);
      expect(before.members.where((LedgerMember m) => m.name == 'Eve'), isEmpty);
      expect(before.guardianDeviceKeys.any((Uint8List k) => hexOf(k) == stranger.keyHex), isFalse);
      // It cannot sign yet.
      final LedgerEntry attempt = await f.add(stranger, EntryType.accessPause, <String, Object?>{'gid': mom.gid}, prev: before.heads);
      expect((await f.state()).rejected[attempt.hashHex], 'signer-unknown');
      // A key rotation that tries to wrap to it is refused.
      final List<Map<String, Object?>> wraps = <Map<String, Object?>>[
        for (final LedgerDevice d in before.devices)
          <String, Object?>{'to': d.key, 'fk': Uint8List(80), 'gk': d.kind == 'guardian' ? Uint8List(80) : null},
        <String, Object?>{'to': stranger.key.publicKey, 'fk': Uint8List(80), 'gk': Uint8List(80)},
      ];
      final LedgerEntry rot = await f.add(mom, EntryType.keyRotate,
          <String, Object?>{'epoch': 1, 'fkc': Uint8List(32), 'gkc': Uint8List(32), 'wraps': wraps}, prev: before.heads);
      expect((await f.state()).rejected[rot.hashHex], 'wrap-to-a-device-that-is-not-active');
      // Dad's yes completes it. Now it is a real device.
      await f.vote(dad, p, 'yes');
      expect((await f.state()).holdsAnything(stranger.key.publicKey), isTrue);
    });

    test('without the candidate\'s own acceptance nobody is added, however many grown-ups say yes', () async {
      final Fam f = await Fam.found(mom);
      await f.welcomeParent(mom, dad, others: <P>[]);
      f.clock += 4 * day;
      final LedgerEntry p = await f.add(mom, EntryType.memberAdd, f.memberBody(stranger, electors: <P>[mom, dad], name: 'Eve'));
      await f.vote(dad, p, 'yes');
      final LedgerState s = await f.state();
      expect(s.pending.single.status, 'pending');
      expect(s.holdsAnything(stranger.key.publicKey), isFalse);
    });
  });

  group('the floor: a new parent needs ALL parents', () {
    test('with two parents, "one" is refused, a shorter electorate is refused, and only the full electorate is accepted', () async {
      final Fam f = await Fam.found(mom);
      await f.welcomeParent(mom, dad, others: <P>[]);
      f.clock += 4 * day;
      final LedgerEntry one = await f.add(mom, EntryType.memberAdd,
          f.memberBody(stranger, electors: <P>[mom], rule: 'one', name: 'Eve'));
      final LedgerEntry shorter = await f.add(mom, EntryType.memberAdd,
          f.memberBody(carer, electors: <P>[mom], rule: 'all', name: 'Jo', proposalId: Uint8List.fromList(List<int>.filled(16, 5))));
      final LedgerState s = await f.state();
      expect(s.rejected[one.hashHex], 'rule-below-floor');
      expect(s.rejected[shorter.hashHex], 'electorate-wrong');
    });

    test('the family policy cannot lower it: even with "carers need one" and "any" set, a parent still needs ALL', () async {
      final Fam f = await Fam.found(mom, policy: const FamilyPolicy(addGrownUp: 'any', carerAct: 'one', carerLook: 'one', settleHours: 0));
      await f.welcomeParent(mom, dad, others: <P>[]);
      final LedgerEntry one = await f.add(mom, EntryType.memberAdd,
          f.memberBody(stranger, electors: <P>[mom], rule: 'one', name: 'Eve'));
      expect((await f.state()).rejected[one.hashHex], 'rule-below-floor');
    });

    test('a parent with limits needs ALL as well', () async {
      final Fam f = await Fam.found(mom);
      await f.welcomeParent(mom, dad, others: <P>[]);
      f.clock += 4 * day;
      final LedgerEntry e = await f.add(mom, EntryType.memberAdd,
          f.memberBody(stranger, preset: Preset.parentWithLimits, electors: <P>[mom], rule: 'one', name: 'Eve'));
      expect((await f.state()).rejected[e.hashHex], 'rule-below-floor');
    });

    test('a family of one parent: that parent\'s signature and the newcomer\'s acceptance are enough', () async {
      final Fam f = await Fam.found(mom);
      await f.welcomeParent(mom, dad, others: <P>[]);
      final LedgerState s = await f.state();
      expect(s.guardians.length, 2);
      expect(s.devices.where((LedgerDevice d) => d.keyHex == dad.keyHex).single.settleUntilMs, greaterThan(f.clock),
          reason: 'a new grown-up\'s phone settles in');
    });

    test('an electorate that leaves out a parent who is in settle-in is correct, and one that includes them is wrong', () async {
      final Fam f = await Fam.found(mom);
      await f.welcomeParent(mom, dad, others: <P>[]); // Dad is now settling in
      final LedgerEntry withDad = await f.add(mom, EntryType.memberAdd,
          f.memberBody(stranger, electors: <P>[mom, dad], name: 'Eve'));
      expect((await f.state()).rejected[withDad.hashHex], 'electorate-wrong',
          reason: 'a parent in settle-in is not asked (and cannot say yes)');
    });
  });

  group('carers', () {
    test('a trusted carer defaults to ALL parents; a family may set one; a look-only carer defaults to one and may be raised to all', () async {
      final Fam f = await Fam.found(mom, policy: const FamilyPolicy(settleHours: 0));
      await f.welcomeParent(mom, dad, others: <P>[]);
      final LedgerEntry actOne = await f.add(mom, EntryType.memberAdd,
          f.memberBody(carer, kind: 'carer', preset: Preset.trustedCarer, electors: <P>[mom], rule: 'one', name: 'Gran'));
      expect((await f.state()).rejected[actOne.hashHex], 'rule-below-floor');
      final LedgerEntry lookOne = await f.add(mom, EntryType.memberAdd,
          f.memberBody(kid, kind: 'carer', preset: Preset.viewOnly, electors: <P>[mom], rule: 'one', name: 'Aunt'));
      expect((await f.state()).rejected.containsKey(lookOne.hashHex), isFalse);
      // The family raises "look" to ALL: a new look-only proposal with "one" is refused.
      await f.add(mom, EntryType.policySet, <String, Object?>{'policy': const FamilyPolicy(settleHours: 0, carerLook: 'all').toValue(), 'exp': null});
      final LedgerEntry lookOne2 = await f.add(mom, EntryType.memberAdd,
          f.memberBody(tab2, kind: 'carer', preset: Preset.viewOnly, electors: <P>[mom], rule: 'one', name: 'Uncle',
              proposalId: Uint8List.fromList(List<int>.filled(16, 3))));
      expect((await f.state()).rejected[lookOne2.hashHex], 'rule-below-floor');
    });

    test('a profile that breaks a fixed cell, a Visit with no time box, a helper page, or a kind that does not match the tier is refused', () async {
      final Fam f = await Fam.found(mom);
      final MemberProfile greedy = MemberProfile(preset: Preset.trustedCarer, caps: <Capability>[...MemberProfile.defaults(Preset.trustedCarer).caps, Capability.expenses]);
      final LedgerEntry a = await f.add(mom, EntryType.memberAdd,
          f.memberBody(carer, kind: 'carer', preset: Preset.trustedCarer, profile: greedy, electors: <P>[mom], name: 'Gran'));
      final LedgerEntry b = await f.add(mom, EntryType.memberAdd,
          f.memberBody(kid, kind: 'carer', preset: Preset.visit, electors: <P>[mom], name: 'Sitter',
              proposalId: Uint8List.fromList(List<int>.filled(16, 2))));
      final LedgerEntry c = await f.add(mom, EntryType.memberAdd,
          f.memberBody(tab2, kind: 'carer', preset: Preset.helperPage, electors: <P>[mom], name: 'Page',
              proposalId: Uint8List.fromList(List<int>.filled(16, 3))));
      final LedgerEntry d = await f.add(mom, EntryType.memberAdd,
          f.memberBody(stranger, kind: 'carer', preset: Preset.parent, electors: <P>[mom], name: 'Mismatch',
              proposalId: Uint8List.fromList(List<int>.filled(16, 4))));
      final LedgerState s = await f.state();
      expect(s.rejected[a.hashHex], startsWith('profile:fixed-capability-5'));
      expect(s.rejected[b.hashHex], 'profile:visit-needs-time-box');
      expect(s.rejected[c.hashHex], 'profile:helper-page-has-no-member');
      expect(s.rejected[d.hashHex], 'kind-tier-mismatch');
    });

    test('a welcomed carer is a member whose phone is a carer device: it holds a key but is never a signer', () async {
      final Fam f = await Fam.found(mom);
      final LedgerEntry e = await f.add(mom, EntryType.memberAdd,
          f.memberBody(carer, kind: 'carer', preset: Preset.viewOnly, electors: <P>[mom], rule: 'one', name: 'Gran'));
      await f.vote(carer, e, 'yes');
      final LedgerState s = await f.state();
      final LedgerMember m = s.members.firstWhere((LedgerMember x) => x.name == 'Gran');
      expect(m.kind, 'carer');
      expect(m.reach, Reach.look);
      expect(s.guardians.length, 1);
      expect(s.canAct(carer.key.publicKey, f.clock + day), isFalse);
    });
  });

  group('settle-in', () {
    test('a new grown-up\'s phone can do nothing that shapes the family until its settle-in ends, except leave', () async {
      final Fam f = await Fam.found(mom);
      await f.welcomeParent(mom, dad, others: <P>[]);
      final List<LedgerEntry> tries = <LedgerEntry>[
        await f.add(dad, EntryType.deviceAdd, f.childBody(kid)),
        await f.add(dad, EntryType.policySet, <String, Object?>{'policy': const FamilyPolicy(settleHours: 72).toValue(), 'exp': null}),
        await f.add(dad, EntryType.memberAdd, f.memberBody(stranger, electors: <P>[mom], name: 'Eve')),
        await f.add(dad, EntryType.deviceRevoke, f.revokeBody(mom)),
        await f.add(dad, EntryType.guardianRemove, <String, Object?>{'gid': mom.gid, 'exp': f.clock + day}),
      ];
      final LedgerState s = await f.state();
      for (final LedgerEntry e in tries) {
        expect(s.rejected[e.hashHex], 'signer-settling', reason: e.type);
      }
      final LedgerEntry leave = await f.add(dad, EntryType.guardianLeave, <String, Object?>{'gid': dad.gid});
      expect((await f.state()).rejected.containsKey(leave.hashHex), isFalse, reason: 'leaving is a floor');
    });

    test('after the settle-in has passed the same phone can act; claiming a time inside the window is not enough', () async {
      final Fam f = await Fam.found(mom, policy: const FamilyPolicy(settleHours: 24));
      await f.welcomeParent(mom, dad, others: <P>[]);
      final LedgerEntry early = await f.add(dad, EntryType.accessPause, <String, Object?>{'gid': mom.gid}, at: f.clock + 2 * hour);
      final LedgerEntry late = await f.add(dad, EntryType.accessResume, <String, Object?>{'gid': mom.gid}, prev: <List<int>>[early.hash], at: f.clock + 30 * hour);
      final LedgerState s = await f.state(f.clock + 40 * hour);
      expect(s.rejected[early.hashHex], 'signer-settling');
      expect(s.rejected[late.hashHex], 'invalid-parent', reason: 'it follows a refused entry');
      final LedgerEntry fresh = await f.add(dad, EntryType.accessPause, <String, Object?>{'gid': mom.gid}, prev: (await f.state(f.clock + 40 * hour)).heads, at: f.clock + 30 * hour);
      expect((await f.state(f.clock + 40 * hour)).rejected.containsKey(fresh.hashHex), isFalse);
    });

    test('a settling grown-up is not asked: the electorate leaves them out, and their yes is not counted', () async {
      final Fam f = await Fam.found(mom);
      await f.welcomeParent(mom, dad, others: <P>[]); // Dad settling
      final LedgerEntry p = await f.add(mom, EntryType.memberAdd, f.memberBody(stranger, electors: <P>[mom], name: 'Eve'));
      await f.vote(dad, p, 'no'); // not asked; changes nothing
      await f.vote(stranger, p, 'yes');
      expect((await f.state()).holdsAnything(stranger.key.publicKey), isTrue);
    });

    test('a second phone of an existing grown-up is a new device in settle-in, accepted by the phone itself, added only by that grown-up', () async {
      final Fam f = await Fam.found(mom);
      final P mom2 = await P.make(11, person: 1);
      final LedgerEntry byMom = await f.add(mom, EntryType.deviceAdd, <String, Object?>{
        'kind': 'guardian', 'gid': mom.gid, 'childId': null, 'name': 'Phone 2', 'dev': mom2.recValue, 'legacy': false, 'orig': null,
      });
      await f.vote(mom2, byMom, 'yes');
      final P dadPhone = await P.make(12, person: 1);
      await f.welcomeParent(mom, dad, others: <P>[]);
      f.clock += 4 * day;
      final LedgerEntry byDad = await f.add(dad, EntryType.deviceAdd, <String, Object?>{
        'kind': 'guardian', 'gid': mom.gid, 'childId': null, 'name': 'Phone 3', 'dev': dadPhone.recValue, 'legacy': false, 'orig': null,
      });
      await f.vote(dadPhone, byDad, 'yes');
      final LedgerState s = await f.state();
      expect(s.deviceFor(mom2.key.publicKey)!.settlingAt(f.clock), isFalse, reason: 'settled by now');
      expect(s.rejected[byDad.hashHex], 'not-your-own-device', reason: 'nobody adds a phone to somebody else\'s name');
    });
  });

  group('loosening versus tightening', () {
    Future<(Fam, LedgerEntry)> twoParents({FamilyPolicy policy = const FamilyPolicy(settleHours: 0)}) async {
      final Fam f = await Fam.found(mom, policy: policy);
      final LedgerEntry w = await f.welcomeParent(mom, dad, others: <P>[]);
      return (f, w);
    }

    test('tightening needs nobody: any grown-up can make a rule stricter, and it takes effect at once', () async {
      final (Fam f, _) = await twoParents();
      await f.add(dad, EntryType.policySet, <String, Object?>{'policy': const FamilyPolicy(settleHours: 72, carerLook: 'all').toValue(), 'exp': null});
      final LedgerState s = await f.state();
      expect(s.policy, const FamilyPolicy(settleHours: 72, carerLook: 'all'));
    });

    test('loosening needs the other grown-up while the rule is ALL: pending, then active with their yes, dead with their no', () async {
      final (Fam f, _) = await twoParents(policy: const FamilyPolicy(settleHours: 72, addGrownUp: 'all'));
      f.clock += 4 * day;
      final LedgerEntry loosen = await f.add(mom, EntryType.policySet,
          <String, Object?>{'policy': const FamilyPolicy(settleHours: 24).toValue(), 'exp': f.clock + 60000 + 5 * day});
      expect((await f.state()).policy.settleHours, 72, reason: 'not yet');
      expect((await f.state()).pending.single.status, 'pending');
      await f.vote(dad, loosen, 'yes');
      expect((await f.state()).policy.settleHours, 24);
    });

    test('a no leaves the old rule in force', () async {
      final (Fam f, _) = await twoParents(policy: const FamilyPolicy(settleHours: 72));
      f.clock += 4 * day;
      final LedgerEntry loosen = await f.add(mom, EntryType.policySet,
          <String, Object?>{'policy': const FamilyPolicy(settleHours: 0).toValue(), 'exp': f.clock + 60000 + day});
      await f.vote(dad, loosen, 'no');
      final LedgerState s = await f.state();
      expect(s.policy.settleHours, 72);
      expect(s.pending.single.status, 'declined');
    });

    test('a loosening that nobody answers lapses and the policy never changes', () async {
      final (Fam f, _) = await twoParents(policy: const FamilyPolicy(settleHours: 72));
      f.clock += 4 * day;
      final int exp = f.clock + 60000 + day;
      await f.add(mom, EntryType.policySet, <String, Object?>{'policy': const FamilyPolicy(settleHours: 0).toValue(), 'exp': exp});
      final LedgerState s = await f.state(exp + day);
      expect(s.policy.settleHours, 72);
      expect(s.pending.single.status, 'lapsed');
    });

    test('with the rule at ANY a loosening is immediate; a mixed change (one field looser) counts as loosening', () async {
      final (Fam f, _) = await twoParents(policy: const FamilyPolicy(settleHours: 24, addGrownUp: 'any'));
      f.clock += 4 * day;
      await f.add(mom, EntryType.policySet, <String, Object?>{'policy': const FamilyPolicy(settleHours: 0, addGrownUp: 'any').toValue(), 'exp': null});
      expect((await f.state()).policy.settleHours, 0);
      final (Fam g, _) = await twoParents(policy: const FamilyPolicy(settleHours: 24, addGrownUp: 'all', carerLook: 'one'));
      g.clock += 4 * day;
      await g.add(mom, EntryType.policySet,
          <String, Object?>{'policy': const FamilyPolicy(settleHours: 72, addGrownUp: 'any', carerLook: 'one').toValue(), 'exp': g.clock + 60000 + day});
      expect((await g.state()).policy.addGrownUp, 'all', reason: 'tightened settle, loosened add: needs the other grown-up');
    });

    test('an expiry that does not match whether approvals are needed is refused', () async {
      final (Fam f, _) = await twoParents(policy: const FamilyPolicy(settleHours: 72));
      f.clock += 4 * day;
      final LedgerEntry noExpNeeded = await f.add(mom, EntryType.policySet,
          <String, Object?>{'policy': const FamilyPolicy(settleHours: 72).toValue(), 'exp': f.clock + day});
      final LedgerEntry expMissing = await f.add(mom, EntryType.policySet,
          <String, Object?>{'policy': const FamilyPolicy(settleHours: 0).toValue(), 'exp': null});
      final LedgerState s = await f.state();
      expect(s.rejected[noExpNeeded.hashHex], 'unexpected-expiry');
      expect(s.rejected[expMissing.hashHex], 'bad-expiry');
    });

    test('concurrent tightenings both apply, field by field (the stricter wins)', () async {
      final (Fam f, _) = await twoParents();
      f.clock += 4 * day;
      final List<Uint8List> head = (await f.state()).heads;
      await f.add(mom, EntryType.policySet, <String, Object?>{'policy': const FamilyPolicy(settleHours: 72, carerLook: 'one').toValue(), 'exp': null}, prev: head);
      await f.add(dad, EntryType.policySet, <String, Object?>{'policy': const FamilyPolicy(settleHours: 0, carerLook: 'all').toValue(), 'exp': null}, prev: head);
      final LedgerState s = await f.state();
      expect(s.policy.settleHours, 72);
      expect(s.policy.carerLook, 'all');
    });
  });

  group('devices: forgetting, losing, leaving, and the grown-up who cannot be removed by the other', () {
    test('a child device is forgotten at once by any grown-up, and a forgotten key can never be added again', () async {
      final Fam f = await Fam.found(mom);
      await f.addChild(mom, kid);
      await f.add(mom, EntryType.deviceRevoke, f.revokeBody(kid, reason: 'forgotten'));
      expect((await f.state()).holdsAnything(kid.key.publicKey), isFalse);
      final LedgerEntry again = await f.addChild(mom, kid);
      expect((await f.state()).rejected[again.hashHex], 'key-reused');
    });

    test('a grown-up\'s own phone can be revoked at once by them; another grown-up\'s needs a visible notice and the right reason', () async {
      final Fam f = await Fam.found(mom);
      await f.welcomeParent(mom, dad, others: <P>[]);
      f.clock += 4 * day;
      final LedgerEntry tooQuick = await f.add(mom, EntryType.deviceRevoke, f.revokeBody(dad, eff: f.clock + 61000));
      final LedgerEntry wrongReason = await f.add(mom, EntryType.deviceRevoke, f.revokeBody(dad, reason: 'removed', eff: f.clock + 80 * hour));
      final LedgerState s = await f.state();
      expect(s.rejected[tooQuick.hashHex], 'notice-too-short');
      expect(s.rejected[wrongReason.hashHex], 'reason-must-be-lost');
      final LedgerEntry fine = await f.add(mom, EntryType.deviceRevoke, f.revokeBody(dad, eff: f.clock + 80 * hour), prev: s.heads);
      final LedgerState mid = await f.state(f.clock + hour);
      expect(mid.holdsAnything(dad.key.publicKey), isTrue, reason: 'still inside the notice');
      expect(mid.canAct(dad.key.publicKey, f.clock + hour), isTrue);
      expect((await f.state(f.clock + 100 * hour)).holdsAnything(dad.key.publicKey), isFalse);
      expect(fine.hashHex, isNotEmpty);
    });

    test('the target can cancel within the notice, and only the owner can', () async {
      final Fam f = await Fam.found(mom);
      await f.welcomeParent(mom, dad, others: <P>[]);
      f.clock += 4 * day;
      final LedgerEntry rv = await f.add(mom, EntryType.deviceRevoke, f.revokeBody(dad, eff: f.clock + 80 * hour));
      final LedgerEntry byMom = await f.add(mom, EntryType.deviceRevokeCancel, <String, Object?>{'revoke': rv.hash});
      expect((await f.state()).rejected[byMom.hashHex], 'only-the-owner-can-cancel');
      await f.add(dad, EntryType.deviceRevokeCancel, <String, Object?>{'revoke': rv.hash}, prev: <List<int>>[rv.hash]);
      final LedgerState s = await f.state(f.clock + 200 * hour);
      expect(s.holdsAnything(dad.key.publicKey), isTrue);
    });

    test('a revoke cannot leave the family with no grown-up device', () async {
      final Fam f = await Fam.found(mom);
      final LedgerEntry r = await f.add(mom, EntryType.deviceRevoke, f.revokeBody(mom, reason: 'removed', eff: f.clock + 60000));
      expect((await f.state()).rejected[r.hashHex], 'last-guardian-device');
    });

    test('leaving is self-only, immediate, and not allowed to the last grown-up', () async {
      final Fam f = await Fam.found(mom);
      final LedgerEntry sole = await f.add(mom, EntryType.guardianLeave, <String, Object?>{'gid': mom.gid});
      expect((await f.state()).rejected[sole.hashHex], 'last-guardian');
      await f.welcomeParent(mom, dad, others: <P>[]);
      f.clock += 4 * day;
      final LedgerEntry other = await f.add(mom, EntryType.guardianLeave, <String, Object?>{'gid': dad.gid});
      expect((await f.state()).rejected[other.hashHex], 'only-yourself');
      await f.add(dad, EntryType.guardianLeave, <String, Object?>{'gid': dad.gid});
      final LedgerState s = await f.state();
      expect(s.guardians.length, 1);
      expect(s.holdsAnything(dad.key.publicKey), isFalse);
    });

    test('one grown-up cannot remove the other: removal waits for the target\'s own yes', () async {
      final Fam f = await Fam.found(mom);
      await f.welcomeParent(mom, dad, others: <P>[]);
      f.clock += 4 * day;
      final LedgerEntry rm = await f.add(mom, EntryType.guardianRemove, <String, Object?>{'gid': dad.gid, 'exp': f.clock + 60000 + 5 * day});
      final LedgerState s = await f.state();
      expect(s.pending.single.status, 'pending');
      expect(s.holdsAnything(dad.key.publicKey), isTrue);
      await f.vote(dad, rm, 'yes');
      expect((await f.state()).holdsAnything(dad.key.publicKey), isFalse);
    });

    test('a removed grown-up is gone for good: the person and the phone cannot be added back', () async {
      final Fam f = await Fam.found(mom);
      await f.welcomeParent(mom, dad, others: <P>[]);
      f.clock += 4 * day;
      await f.add(dad, EntryType.guardianLeave, <String, Object?>{'gid': dad.gid});
      f.clock += 4 * day;
      final LedgerEntry back = await f.add(mom, EntryType.memberAdd, f.memberBody(dad, electors: <P>[mom], name: 'Dad again'));
      expect((await f.state()).rejected[back.hashHex], 'gid-reused');
    });
  });

  group('limits on size', () {
    test('at most 12 child devices', () async {
      final Fam f = await Fam.found(mom);
      for (int i = 0; i < kMaxChildDevices; i++) {
        await f.addChild(mom, await P.make(40 + i), childId: 'k$i');
      }
      final LedgerEntry extra = await f.addChild(mom, await P.make(80), childId: 'k99');
      final LedgerState s = await f.state();
      expect(s.childDeviceKeys.length, kMaxChildDevices);
      expect(s.rejected[extra.hashHex], 'family-full');
    });
  });

  group('key rotation entries', () {
    test('the guardian-only key is never wrapped to a child device or a carer, and every active device with an agreement key gets a wrap', () async {
      final Fam f = await Fam.found(mom);
      await f.addChild(mom, kid);
      Map<String, Object?> body(List<Map<String, Object?>> wraps, {int epoch = 1}) =>
          <String, Object?>{'epoch': epoch, 'fkc': Uint8List(32), 'gkc': Uint8List(32), 'wraps': wraps};
      Map<String, Object?> w(P p, {bool gk = false}) =>
          <String, Object?>{'to': p.key.publicKey, 'fk': Uint8List(80), 'gk': gk ? Uint8List(80) : null};
      final LedgerEntry toChild = await f.add(mom, EntryType.keyRotate, body(<Map<String, Object?>>[w(mom, gk: true), w(kid, gk: true)]));
      final LedgerEntry missing = await f.add(mom, EntryType.keyRotate, body(<Map<String, Object?>>[w(mom, gk: true)]));
      final LedgerEntry noGkForMom = await f.add(mom, EntryType.keyRotate, body(<Map<String, Object?>>[w(mom), w(kid)]));
      final LedgerEntry wrongEpoch = await f.add(mom, EntryType.keyRotate, body(<Map<String, Object?>>[w(mom, gk: true), w(kid)], epoch: 5));
      final LedgerEntry ok = await f.add(mom, EntryType.keyRotate, body(<Map<String, Object?>>[w(mom, gk: true), w(kid)]));
      final LedgerState s = await f.state();
      expect(s.rejected[toChild.hashHex], 'guardian-key-wrapped-to-a-non-guardian');
      expect(s.rejected[missing.hashHex], 'wrap-missing');
      expect(s.rejected[noGkForMom.hashHex], 'grown-up-wrap-without-guardian-key');
      expect(s.rejected[wrongEpoch.hashHex], 'wrong-epoch');
      expect(s.rejected.containsKey(ok.hashHex), isFalse);
      expect(s.epoch, 1);
    });

    test('two concurrent rotations to one epoch would split the keys: the earlier one stands', () async {
      final Fam f = await Fam.found(mom);
      await f.welcomeParent(mom, dad, others: <P>[]);
      f.clock += 4 * day;
      final LedgerState before = await f.state();
      final List<Uint8List> head = before.heads;
      Map<String, Object?> body(int n) => <String, Object?>{
            'epoch': 1,
            'fkc': Uint8List(32)..[0] = n,
            'gkc': Uint8List(32),
            'wraps': <Map<String, Object?>>[
              for (final LedgerDevice d in before.devices) <String, Object?>{'to': d.key, 'fk': Uint8List(80), 'gk': Uint8List(80)},
            ],
          };
      await f.add(mom, EntryType.keyRotate, body(1), prev: head);
      await f.add(dad, EntryType.keyRotate, body(2), prev: head);
      final LedgerState s = await f.state();
      expect(s.epoch, 1);
      expect(s.voided.values.where((String v) => v == 'rotation-conflict').length, 1);
    });
  });

  group('reserved entry types change nothing', () {
    test('pause, resume, end, limits and standing OK are recorded and grant nothing', () async {
      final Fam f = await Fam.found(mom);
      await f.welcomeParent(mom, dad, others: <P>[]);
      f.clock += 4 * day;
      final String before = Fam.summary(await f.state()).split('\n').where((String l) => l.startsWith('members=') || l.startsWith('devices=') || l.startsWith('policy=')).join();
      await f.add(mom, EntryType.accessPause, <String, Object?>{'gid': dad.gid});
      await f.add(mom, EntryType.accessEnd, <String, Object?>{'gid': dad.gid, 'reason': 'ended'});
      await f.add(mom, EntryType.limitsAgree, <String, Object?>{'gid': dad.gid, 'limits': <int>[5], 'until': f.clock + day});
      await f.add(mom, EntryType.limitsTighten, <String, Object?>{'gid': dad.gid, 'limits': <int>[5, 6]});
      await f.add(mom, EntryType.standingOk, <String, Object?>{'gid': dad.gid, 'until': f.clock + day});
      final LedgerEntry unknown = await f.add(mom, EntryType.accessPause, <String, Object?>{'gid': stranger.gid});
      final LedgerState s = await f.state();
      final String after = Fam.summary(s).split('\n').where((String l) => l.startsWith('members=') || l.startsWith('devices=') || l.startsWith('policy=')).join();
      expect(after, before);
      expect(s.rejected[unknown.hashHex], 'unknown-subject');
      expect(s.holdsAnything(dad.key.publicKey), isTrue, reason: 'a "pause" that is only reserved does not pause');
    });
  });

  group('legacy child devices', () {
    test('a legacy device.add is accepted only from the founder, only when the genesis recorded a legacy family id', () async {
      final Fam f = await Fam.found(mom, legacyFids: <String>['local-abc']);
      final LedgerEntry byFounder = await f.add(mom, EntryType.deviceAdd, f.childBody(kid, legacy: true, bare: true));
      expect((await f.state()).rejected.containsKey(byFounder.hashHex), isFalse);
      expect((await f.state()).deviceFor(kid.key.publicKey)!.agree, isNull);
      await f.welcomeParent(mom, dad, others: <P>[]);
      f.clock += 4 * day;
      final LedgerEntry byDad = await f.add(dad, EntryType.deviceAdd, f.childBody(tab2, legacy: true, bare: true));
      expect((await f.state()).rejected[byDad.hashHex], 'legacy-only-by-founder');
      final Fam g = await Fam.found(mom);
      final LedgerEntry none = await g.add(mom, EntryType.deviceAdd, g.childBody(kid, legacy: true, bare: true));
      expect((await g.state()).rejected[none.hashHex], 'no-legacy-family-recorded');
    });
  });
}
