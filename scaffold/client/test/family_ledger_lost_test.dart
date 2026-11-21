// OLIVE BRANCH — a lost or stolen phone, and ending a grown-up, in the signed family ledger. Verified by CI, headless.
// Every case that matters is a hostile or awkward one: a thief holding an unlocked phone, a pause racing the thief's
// own entries, a replayed answer, a pause used to silence the grown-up it is about, an end that waits out the notice.
// The rules are in family_ledger_state.dart (read its header); the entry bodies are in family_ledger.dart.
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/family_keys.dart';
import 'package:olive_client/family_ledger.dart';
import 'package:olive_client/family_ledger_state.dart';

import 'family_test_support.dart';

void main() {
  late P mom, mom2, thief, dad, carol, kid, stranger;

  setUp(() async {
    mom = await P.make(1);
    dad = await P.make(2);
    kid = await P.make(3);
    stranger = await P.make(5);
    mom2 = await P.make(11, person: 1); // mom's other phone, in her hand
    thief = await P.make(12, person: 1); // mom's phone that gets stolen while unlocked
    carol = await P.make(7);
  });

  Future<void> addPhone(Fam f, P by, P dev) async {
    final LedgerEntry e = await f.add(by, EntryType.deviceAdd, <String, Object?>{
      'kind': 'guardian', 'gid': by.gid, 'childId': null, 'name': 'Phone', 'dev': dev.recValue, 'legacy': false, 'orig': null,
    });
    await f.vote(dev, e, 'yes');
  }

  /// Mom (phones: mom, mom2, thief) and Dad, everyone past settle-in, one child tablet.
  Future<Fam> family({bool withTablet = true}) async {
    final Fam f = await Fam.found(mom);
    await f.welcomeParent(mom, dad, others: <P>[]);
    await addPhone(f, mom, mom2);
    await addPhone(f, mom, thief);
    if (withTablet) await f.addChild(mom, kid);
    f.clock += 4 * day;
    return f;
  }

  Map<String, Object?> pauseBody(P target) => <String, Object?>{'key': target.key.publicKey};
  Map<String, Object?> resumeBody(P target, LedgerEntry pause) =>
      <String, Object?>{'key': target.key.publicKey, 'pause': pause.hash};

  group('pause: marked as lost', () {
    test('another grown-up pauses a phone at once; it can no longer act, is listed as paused, and the others are unaffected', () async {
      final Fam f = await family();
      final LedgerEntry p = await f.add(dad, EntryType.devicePause, pauseBody(thief));
      final LedgerState s = await f.state();
      expect(s.rejected.containsKey(p.hashHex), isFalse);
      expect(s.isPaused(thief.key.publicKey), isTrue);
      expect(s.standingOf(thief.key.publicKey), 'paused');
      expect(s.canAct(thief.key.publicKey, f.clock + hour), isFalse);
      expect(s.canAct(mom2.key.publicKey, f.clock + hour), isTrue);
      expect(s.canAct(dad.key.publicKey, f.clock + hour), isTrue);
      expect(s.paused.single.byGidHex, dad.gidHex);
      expect(s.holdsAnything(thief.key.publicKey), isTrue, reason: 'a pause is not a removal: nothing is forgotten');
    });

    test('a paused phone signs nothing (not even a harmless-looking policy change), but the person can always leave', () async {
      final Fam f = await family();
      await f.add(dad, EntryType.devicePause, pauseBody(thief));
      final LedgerEntry tighten = await f.add(thief, EntryType.policySet, <String, Object?>{'policy': const FamilyPolicy(settleHours: 72).toValue(), 'exp': null});
      final LedgerEntry revokeOther = await f.add(thief, EntryType.deviceRevoke, f.revokeBody(mom2, eff: f.clock + 60000));
      final LedgerState s = await f.state();
      expect(s.rejected[tighten.hashHex], 'signer-paused');
      expect(s.rejected[revokeOther.hashHex], 'signer-paused');
      expect(s.holdsAnything(mom2.key.publicKey), isTrue);
    });

    test('a paused phone gets no new key: a rotation that wraps to it is refused, and the planned rotation leaves it out', () async {
      final Fam f = await family();
      await f.add(dad, EntryType.devicePause, pauseBody(thief));
      final LedgerState s = await f.state();
      final RotationPlan plan = await planKeyRotation(s, random: Random(8));
      final List<Object?> wraps = plan.body['wraps']! as List<Object?>;
      expect(wraps.map((Object? w) => hexOf((w! as Map<String, Object?>)['to']! as Uint8List)), isNot(contains(thief.keyHex)));
      expect(wraps.length, 4, reason: 'mom, mom2, dad and the tablet; not the paused phone');
      final LedgerEntry good = await f.add(mom2, EntryType.keyRotate, plan.body);
      expect((await f.state()).rejected.containsKey(good.hashHex), isFalse);
      expect((await f.state()).epoch, 1);
      // a hostile or stale rotation that still wraps to the paused phone is refused
      final RotationPlan withThief = await planKeyRotation(
          (await reduceLedger(entries: f.entries.where((LedgerEntry e) => e.type != EntryType.devicePause), votes: f.votes, nowMs: f.clock + hour, pin: f.pin)),
          random: Random(9));
      final LedgerEntry bad = await f.add(mom2, EntryType.keyRotate, <String, Object?>{...withThief.body, 'epoch': 2});
      expect((await f.state()).rejected[bad.hashHex], 'wrap-to-a-device-that-is-not-active');
      // and the paused phone can open nothing from the good rotation
      final FamilyKeyring ring = FamilyKeyring(guardianDevice: true);
      expect(await openKeyRotation(fid: s.fid!, body: plan.body, device: thief.key, agreement: thief.agree, ring: ring), isFalse);
      expect(ring.fkEpochs, isEmpty);
    });

    test('the safety lever has limits: not twice, not a stranger\'s phone, never the last grown-up phone that can act', () async {
      final Fam f = await Fam.found(mom);
      await addPhone(f, mom, mom2);
      f.clock += 2 * day;
      final LedgerEntry first = await f.add(mom2, EntryType.devicePause, pauseBody(mom));
      final LedgerEntry again = await f.add(mom2, EntryType.devicePause, pauseBody(mom), prev: <List<int>>[first.hash]);
      final LedgerEntry last = await f.add(mom2, EntryType.devicePause, pauseBody(mom2), prev: <List<int>>[first.hash]);
      final LedgerEntry unknown = await f.add(mom2, EntryType.devicePause, pauseBody(stranger), prev: <List<int>>[first.hash]);
      final LedgerState s = await f.state();
      expect(s.rejected.containsKey(first.hashHex), isFalse);
      expect(s.rejected[again.hashHex], 'already-paused');
      expect(s.rejected[last.hashHex], 'last-active-guardian-device', reason: 'someone must always be able to lift a pause');
      expect(s.rejected[unknown.hashHex], 'unknown-device');
    });

    test('a child device and a stranger cannot pause anything; a grown-up can pause a child\'s tablet', () async {
      final Fam f = await family();
      final LedgerEntry byKid = await f.add(kid, EntryType.devicePause, pauseBody(mom));
      final LedgerEntry byStranger = await f.add(stranger, EntryType.devicePause, pauseBody(mom));
      final LedgerEntry tablet = await f.add(mom2, EntryType.devicePause, pauseBody(kid));
      final LedgerState s = await f.state();
      expect(s.rejected[byKid.hashHex], 'child-key-cannot-sign');
      expect(s.rejected[byStranger.hashHex], 'signer-unknown');
      expect(s.rejected.containsKey(tablet.hashHex), isFalse);
      expect(s.isPaused(kid.key.publicKey), isTrue);
    });

    test('a pending (not yet welcomed) person and a settling phone cannot pause anyone', () async {
      final Fam f = await Fam.found(mom);
      await f.add(mom, EntryType.memberAdd, f.memberBody(dad, electors: <P>[mom]));
      final LedgerEntry byPending = await f.add(dad, EntryType.devicePause, pauseBody(mom));
      expect((await f.state()).rejected[byPending.hashHex], 'signer-unknown');
      await addPhone(f, mom, mom2);
      final LedgerEntry bySettling = await f.add(mom2, EntryType.devicePause, pauseBody(mom));
      expect((await f.state()).rejected[bySettling.hashHex], 'signer-settling');
    });
  });

  group('resume: "I have it"', () {
    test('the owner lifts a pause another grown-up made, from her other phone; the phone can act again but needs a new rotation to read on', () async {
      final Fam f = await family();
      final LedgerEntry p = await f.add(dad, EntryType.devicePause, pauseBody(thief));
      final LedgerEntry r = await f.add(mom2, EntryType.deviceResume, resumeBody(thief, p));
      final LedgerState s = await f.state();
      expect(s.rejected.containsKey(r.hashHex), isFalse);
      expect(s.isPaused(thief.key.publicKey), isFalse);
      expect(s.standingOf(thief.key.publicKey), 'active');
      final LedgerEntry acts = await f.add(thief, EntryType.policySet, <String, Object?>{'policy': const FamilyPolicy(settleHours: 72).toValue(), 'exp': null});
      expect((await f.state()).rejected.containsKey(acts.hashHex), isFalse);
    });

    test('a pause the owner made herself cannot be undone by the other grown-up while the phone she paused from is active', () async {
      final Fam f = await family();
      final LedgerEntry p = await f.add(mom2, EntryType.devicePause, pauseBody(thief));
      final LedgerEntry byDad = await f.add(dad, EntryType.deviceResume, resumeBody(thief, p));
      expect((await f.state()).rejected[byDad.hashHex], 'only-the-owner-resumes');
      expect((await f.state()).isPaused(thief.key.publicKey), isTrue);
    });

    test('...but once that phone is itself paused (a thief who knew the PIN paused her real phone from the stolen one), the other grown-up can bring hers back', () async {
      final Fam f = await family();
      final LedgerEntry theirs = await f.add(thief, EntryType.devicePause, pauseBody(mom2)); // thief pauses mom's REAL phone
      final LedgerEntry stuck = await f.add(dad, EntryType.deviceResume, resumeBody(mom2, theirs));
      expect((await f.state()).rejected[stuck.hashHex], 'only-the-owner-resumes', reason: 'the thief\'s phone is still active');
      await f.add(dad, EntryType.devicePause, pauseBody(thief));
      final LedgerEntry back = await f.add(dad, EntryType.deviceResume, resumeBody(mom2, theirs));
      final LedgerState s = await f.state();
      expect(s.rejected.containsKey(back.hashHex), isFalse);
      expect(s.isPaused(mom2.key.publicKey), isFalse);
      expect(s.isPaused(thief.key.publicKey), isTrue, reason: 'and the thief stays cut off');
    });

    test('a device cannot lift its own pause, an unpaused device cannot be resumed, and a resume must name the pause it answers', () async {
      final Fam f = await family();
      final LedgerEntry p = await f.add(dad, EntryType.devicePause, pauseBody(thief));
      final LedgerEntry self = await f.add(thief, EntryType.deviceResume, resumeBody(thief, p));
      final LedgerEntry notPaused = await f.add(mom2, EntryType.deviceResume, <String, Object?>{'key': dad.key.publicKey, 'pause': p.hash});
      final LedgerEntry unseen = await f.add(mom2, EntryType.deviceResume, <String, Object?>{'key': thief.key.publicKey, 'pause': Uint8List(32)});
      final LedgerState s = await f.state();
      expect(s.rejected[self.hashHex], 'signer-paused');
      expect(s.rejected[notPaused.hashHex], 'not-paused');
      expect(s.rejected[unseen.hashHex], 'pause-not-seen');
      expect(s.isPaused(thief.key.publicKey), isTrue);
    });

    test('REPLAY: an old resume cannot lift a newer pause, and an old pause cannot re-pause what was resumed', () async {
      final Fam f = await family();
      final LedgerEntry p1 = await f.add(dad, EntryType.devicePause, pauseBody(thief));
      final LedgerEntry r1 = await f.add(mom2, EntryType.deviceResume, resumeBody(thief, p1));
      final LedgerEntry p2 = await f.add(dad, EntryType.devicePause, pauseBody(thief));
      expect((await f.state()).isPaused(thief.key.publicKey), isTrue);
      // the attacker (or a flaky network) delivers everything again, in another order, and the old resume once more
      f.entries..add(r1)..add(p1)..add(r1)..add(p2);
      f.entries.shuffle(Random(3));
      final LedgerState s = await f.state();
      expect(s.isPaused(thief.key.publicKey), isTrue, reason: 'p2 is still unanswered');
      expect(s.paused.single.pauseHashHex, p2.hashHex);
      // an old resume re-signed fresh for the same pause is not valid either: that pause is already answered
      final LedgerEntry again = await f.add(mom2, EntryType.deviceResume, resumeBody(thief, p1), prev: <List<int>>[p2.hash]);
      expect((await f.state()).rejected[again.hashHex], 'wrong-pause');
      // answering the real one works
      await f.add(mom2, EntryType.deviceResume, resumeBody(thief, p2), prev: <List<int>>[p2.hash]);
      expect((await f.state()).isPaused(thief.key.publicKey), isFalse);
    });
  });

  group('the stolen unlocked phone', () {
    test('RACE: the thief\'s entry written on a branch the pause did not see is void; the pause wins', () async {
      final Fam f = await family();
      final List<List<int>> before = (await f.state()).heads;
      // the thief, holding an unlocked phone, revokes mom's real phone (her OWN phone: immediate)...
      final LedgerEntry theft = await f.add(thief, EntryType.deviceRevoke, f.revokeBody(mom2, eff: f.clock + 60000), prev: before);
      // ...at the same time dad pauses the thief's phone, having seen nothing of it
      await f.add(dad, EntryType.devicePause, pauseBody(thief), prev: before);
      final LedgerState s = await f.state(f.clock + 3 * hour);
      expect(s.voided[theft.hashHex], 'signer-paused-concurrently');
      expect(s.holdsAnything(mom2.key.publicKey), isTrue, reason: 'her real phone survives');
      expect(s.standingOf(mom2.key.publicKey), 'active');
      expect(s.hasFork, isTrue, reason: 'and the family is told it forked');
    });

    test('...but what the thief had already signed, on a branch the pause DID see, stands: a pause cannot un-sign (the honest limit)', () async {
      final Fam f = await family();
      final LedgerEntry theft = await f.add(thief, EntryType.deviceRevoke, f.revokeBody(mom2, eff: f.clock + 60000));
      await f.add(dad, EntryType.devicePause, pauseBody(thief), prev: <List<int>>[theft.hash]);
      final LedgerState s = await f.state(f.clock + 3 * hour);
      expect(s.voided.containsKey(theft.hashHex), isFalse);
      expect(s.standingOf(mom2.key.publicKey), 'revoked');
    });

    test('a yes voted from the stolen phone AFTER the pause approves nothing, a yes from mom\'s other phone does, and a no from the paused phone still counts', () async {
      final Fam f = await family();
      final LedgerEntry add = await f.add(dad, EntryType.memberAdd, f.memberBody(stranger, electors: <P>[dad, mom], name: 'Eve'));
      await f.add(dad, EntryType.devicePause, pauseBody(thief), prev: <List<int>>[add.hash]);
      await f.vote(thief, add, 'yes');
      await f.vote(stranger, add, 'yes'); // the candidate's own acceptance
      expect((await f.state()).holdsAnything(stranger.key.publicKey), isFalse, reason: 'the stolen phone\'s yes is ignored');
      expect((await f.state()).pending.single.status, 'pending');
      await f.vote(mom2, add, 'yes');
      expect((await f.state()).holdsAnything(stranger.key.publicKey), isTrue, reason: 'mom\'s real phone said yes');

      // a no from a paused phone is never silenced
      final Fam g = await family();
      final LedgerEntry add2 = await g.add(dad, EntryType.memberAdd, g.memberBody(stranger, electors: <P>[dad, mom], name: 'Eve'));
      await g.add(dad, EntryType.devicePause, pauseBody(thief), prev: <List<int>>[add2.hash]);
      await g.vote(thief, add2, 'no');
      await g.vote(mom2, add2, 'yes');
      await g.vote(stranger, add2, 'yes');
      expect((await g.state()).holdsAnything(stranger.key.publicKey), isFalse, reason: 'a pause is not a way to silence an objection');
      expect((await g.state()).pending.single.status, 'declined');
    });

    test('a vote from a phone BEFORE it was paused still counts (the pause is not retroactive)', () async {
      final Fam f = await family();
      final LedgerEntry add = await f.add(dad, EntryType.memberAdd, f.memberBody(stranger, electors: <P>[dad, mom], name: 'Eve'));
      await f.vote(thief, add, 'yes');
      await f.add(dad, EntryType.devicePause, pauseBody(thief), prev: <List<int>>[add.hash]);
      await f.vote(stranger, add, 'yes');
      expect((await f.state()).holdsAnything(stranger.key.publicKey), isTrue);
    });

    test('the same ledger reduces to the same state in any delivery order, with a pause in it', () async {
      final Fam f = await family();
      final LedgerEntry add = await f.add(dad, EntryType.memberAdd, f.memberBody(stranger, electors: <P>[dad, mom], name: 'Eve'));
      final LedgerEntry p = await f.add(dad, EntryType.devicePause, pauseBody(thief), prev: <List<int>>[add.hash]);
      await f.vote(thief, add, 'yes');
      await f.vote(mom2, add, 'yes');
      await f.vote(stranger, add, 'yes');
      await f.add(mom2, EntryType.deviceResume, resumeBody(thief, p));
      final String want = Fam.summary(await f.state());
      for (int seed = 0; seed < 6; seed++) {
        final List<LedgerEntry> es = <LedgerEntry>[...f.entries]..shuffle(Random(seed));
        final List<LedgerVote> vs = <LedgerVote>[...f.votes]..shuffle(Random(seed + 10));
        expect(Fam.summary(await reduceLedger(entries: es, votes: vs, nowMs: f.clock + hour, pin: f.pin)), want, reason: 'seed $seed');
      }
    });
  });

  group('cut off for good: revoke with the notice', () {
    test('another grown-up\'s phone is revoked only after 72 hours, the owner can cancel, and a revoked phone cannot come back', () async {
      final Fam f = await family();
      final LedgerEntry p = await f.add(dad, EntryType.devicePause, pauseBody(thief));
      final LedgerEntry rv = await f.add(dad, EntryType.deviceRevoke, f.revokeBody(thief, eff: f.clock + 60000 + kRevokeNoticeMs));
      LedgerState s = await f.state();
      expect(s.rejected.containsKey(rv.hashHex), isFalse);
      expect(s.pendingRevokes.single.keyHex, thief.keyHex);
      expect(s.standingOf(thief.key.publicKey), 'paused');
      s = await f.state(f.clock + kRevokeNoticeMs + hour);
      expect(s.standingOf(thief.key.publicKey), 'revoked');
      expect(s.pendingRevokes, isEmpty);
      final LedgerEntry late = await f.add(mom2, EntryType.deviceResume, resumeBody(thief, p), at: f.clock + kRevokeNoticeMs + 2 * hour);
      expect((await f.state(f.clock + kRevokeNoticeMs + 3 * hour)).rejected[late.hashHex], 'not-paused');
    });

    test('the owner says "I have it" inside the notice: cancel the revoke and lift the pause; both are visible and nothing is lost', () async {
      final Fam f = await family();
      final LedgerEntry p = await f.add(dad, EntryType.devicePause, pauseBody(thief));
      final LedgerEntry rv = await f.add(dad, EntryType.deviceRevoke, f.revokeBody(thief, eff: f.clock + 60000 + kRevokeNoticeMs));
      await f.add(mom2, EntryType.deviceRevokeCancel, <String, Object?>{'revoke': rv.hash});
      await f.add(mom2, EntryType.deviceResume, resumeBody(thief, p));
      final LedgerState s = await f.state(f.clock + 2 * kRevokeNoticeMs);
      expect(s.standingOf(thief.key.publicKey), 'active');
      expect(s.pendingRevokes, isEmpty);
      expect(s.history, containsAll(<String>[p.hashHex, rv.hashHex]), reason: 'the whole story stays in the record');
    });

    test('a phone that was never listed has no standing at all', () async {
      final Fam f = await family();
      expect((await f.state()).standingOf(stranger.key.publicKey), 'unknown');
    });
  });

  group('ending a grown-up: both, or fourteen days of notice with no refusal', () {
    Future<Fam> three() async {
      final Fam f = await Fam.found(mom);
      await f.welcomeParent(mom, dad, others: <P>[]);
      await f.welcomeParent(mom, carol, others: <P>[dad]);
      f.clock += 4 * day;
      return f;
    }

    test('the grown-up\'s own yes ends it at once; the notice shows on the way', () async {
      final Fam f = await three();
      final LedgerEntry end = await f.add(mom, EntryType.guardianEnd, <String, Object?>{'gid': dad.gid});
      LedgerState s = await f.state();
      expect(s.members.any((LedgerMember m) => m.gidHex == dad.gidHex), isTrue, reason: 'nothing happens on the proposer\'s word alone');
      expect(s.pending.single.type, EntryType.guardianEnd);
      expect(s.pending.single.status, 'pending');
      expect(s.pending.single.subjectGidHex, dad.gidHex);
      await f.vote(dad, end, 'yes');
      s = await f.state();
      expect(s.members.any((LedgerMember m) => m.gidHex == dad.gidHex), isFalse);
      expect(s.standingOf(dad.key.publicKey), 'revoked');
    });

    test('with no answer at all it ends only when the full 14 days have passed, not a minute before', () async {
      final Fam f = await three();
      final LedgerEntry end = await f.add(mom, EntryType.guardianEnd, <String, Object?>{'gid': dad.gid});
      final int at = end.issuedAtMs;
      expect((await f.state(at + kEndWaitMs - 60000)).members.any((LedgerMember m) => m.gidHex == dad.gidHex), isTrue);
      expect((await f.state(at + kEndWaitMs - 60000)).pending.single.status, 'pending');
      final LedgerState done = await f.state(at + kEndWaitMs);
      expect(done.members.any((LedgerMember m) => m.gidHex == dad.gidHex), isFalse);
      expect(done.pending, isEmpty);
    });

    test('NO PARENT CAN END ANOTHER ALONE: a refusal from the grown-up, or from a third grown-up, stops it for good', () async {
      final Fam f = await three();
      final LedgerEntry end = await f.add(mom, EntryType.guardianEnd, <String, Object?>{'gid': dad.gid});
      await f.vote(dad, end, 'no');
      final LedgerState s = await f.state(end.issuedAtMs + 2 * kEndWaitMs);
      expect(s.members.any((LedgerMember m) => m.gidHex == dad.gidHex), isTrue);
      expect(s.pending.single.status, 'declined');

      final Fam g = await three();
      final LedgerEntry end2 = await g.add(mom, EntryType.guardianEnd, <String, Object?>{'gid': dad.gid});
      await g.vote(carol, end2, 'no'); // the other grown-up objects on behalf of the family
      expect((await g.state(end2.issuedAtMs + 2 * kEndWaitMs)).members.any((LedgerMember m) => m.gidHex == dad.gidHex), isTrue);
    });

    test('a refusal that arrives after the wait is over is not a refusal (silence for the whole wait is what ends it)', () async {
      final Fam f = await three();
      final LedgerEntry end = await f.add(mom, EntryType.guardianEnd, <String, Object?>{'gid': dad.gid});
      await f.vote(dad, end, 'no', at: end.issuedAtMs + kEndWaitMs + 1000);
      expect((await f.state(end.issuedAtMs + kEndWaitMs + 2000)).members.any((LedgerMember m) => m.gidHex == dad.gidHex), isFalse);
    });

    test('PAUSING THE PARENT FIRST DOES NOT SILENCE THEM: a paused phone can still refuse, and the end is stopped', () async {
      final Fam f = await three();
      await f.add(mom, EntryType.devicePause, pauseBody(dad));
      final LedgerEntry end = await f.add(mom, EntryType.guardianEnd, <String, Object?>{'gid': dad.gid});
      await f.vote(dad, end, 'no');
      final LedgerState s = await f.state(end.issuedAtMs + 2 * kEndWaitMs);
      expect(s.members.any((LedgerMember m) => m.gidHex == dad.gidHex), isTrue);
      expect(s.pending.single.status, 'declined');
    });

    test('a paused phone\'s YES does not end its own grown-up (a thief on that phone cannot end the owner)', () async {
      final Fam f = await three();
      final LedgerEntry end = await f.add(mom, EntryType.guardianEnd, <String, Object?>{'gid': dad.gid});
      await f.add(mom, EntryType.devicePause, pauseBody(dad), prev: <List<int>>[end.hash]);
      await f.vote(dad, end, 'yes');
      expect((await f.state()).members.any((LedgerMember m) => m.gidHex == dad.gidHex), isTrue, reason: 'still pending: the notice runs, the other grown-ups see it');
    });

    test('hostile shapes: yourself, a stranger, a carer, a child device, a settling phone', () async {
      final Fam f = await three();
      final LedgerEntry self = await f.add(mom, EntryType.guardianEnd, <String, Object?>{'gid': mom.gid});
      final LedgerEntry unknown = await f.add(mom, EntryType.guardianEnd, <String, Object?>{'gid': stranger.gid});
      final LedgerEntry byKid = await f.add(kid, EntryType.guardianEnd, <String, Object?>{'gid': dad.gid});
      final LedgerEntry byStranger = await f.add(stranger, EntryType.guardianEnd, <String, Object?>{'gid': dad.gid});
      final LedgerState s = await f.state();
      expect(s.rejected[self.hashHex], 'use-leave');
      expect(s.rejected[unknown.hashHex], 'unknown-subject');
      expect(s.rejected[byKid.hashHex], 'signer-unknown');
      expect(s.rejected[byStranger.hashHex], 'signer-unknown');
      final Fam g = await Fam.found(mom);
      await g.welcomeParent(mom, dad, others: <P>[]); // dad is settling
      final LedgerEntry bySettling = await g.add(dad, EntryType.guardianEnd, <String, Object?>{'gid': mom.gid});
      expect((await g.state()).rejected[bySettling.hashHex], 'signer-settling');
    });

    test('an ended grown-up is gone for good: the person and the phone cannot be added back, and their phones are cut off', () async {
      final Fam f = await three();
      final LedgerEntry end = await f.add(mom, EntryType.guardianEnd, <String, Object?>{'gid': dad.gid});
      await f.vote(dad, end, 'yes');
      final LedgerEntry back = await f.add(mom, EntryType.memberAdd, f.memberBody(dad, electors: <P>[mom, carol], name: 'Dad again'));
      final LedgerState s = await f.state();
      expect(s.rejected[back.hashHex], 'gid-reused');
      final LedgerEntry byOld = await f.add(dad, EntryType.policySet, <String, Object?>{'policy': const FamilyPolicy(settleHours: 72).toValue(), 'exp': null});
      expect((await f.state()).rejected[byOld.hashHex], 'signer-not-active');
    });

    test('a family of two keeps working after the end; and the one grown-up left cannot be ended (only leave)', () async {
      final Fam f = await Fam.found(mom);
      await f.welcomeParent(mom, dad, others: <P>[]);
      f.clock += 4 * day;
      final LedgerEntry end = await f.add(mom, EntryType.guardianEnd, <String, Object?>{'gid': dad.gid});
      await f.vote(dad, end, 'yes');
      final LedgerState s = await f.state();
      expect(s.guardians.length, 1);
      final LedgerEntry last = await f.add(mom, EntryType.guardianEnd, <String, Object?>{'gid': mom.gid});
      expect((await f.state()).rejected[last.hashHex], 'use-leave');
    });
  });
}
