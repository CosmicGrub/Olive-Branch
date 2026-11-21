// OLIVE BRANCH — hostile tests for the co-parent rules in the family ledger (family_ledger_state.dart): pause, ending,
// the limits agreement with its 24 hour think-over, and the Standing OK. UNVERIFIED until CI runs it.
// Spec: docs/planning/VILLAGE-WELCOME-DESIGN.md sections 4.4, 4.5, 5.2, 6.2 and 10, and the owner's rule that one parent
// can never remove another alone (either parent may pause, reversible and visible to all; ending needs both parents, or
// a 14 day wait with a notice on every device).
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/family_ledger.dart';
import 'package:olive_client/family_ledger_state.dart';
import 'package:olive_client/family_profiles.dart';

import 'family_test_support.dart';
import 'village_test_support.dart' show PendingFor;

void main() {
  late P mom, dad, eve, jo, kid;

  setUp(() async {
    mom = await P.make(1);
    dad = await P.make(2);
    eve = await P.make(5);
    jo = await P.make(6);
    kid = await P.make(3);
  });

  /// Mom founded the family, Dad was welcomed and has finished settling in.
  Future<Fam> two({FamilyPolicy policy = const FamilyPolicy()}) async {
    final Fam f = await Fam.found(mom, policy: policy);
    await f.welcomeParent(mom, dad, others: <P>[]);
    f.clock += 4 * day;
    return f;
  }

  /// A carer proposed by [by], with every parent's yes and the carer's own.
  Future<LedgerEntry> carer(Fam f, P by, P cand, {Preset preset = Preset.trustedCarer, List<P> yes = const <P>[], String rule = 'all'}) async {
    final LedgerEntry e = await f.add(by, EntryType.memberAdd,
        f.memberBody(cand, kind: 'carer', preset: preset, electors: <P>[by, ...yes], rule: rule, name: 'Jo'));
    for (final P y in yes) {
      await f.vote(y, e, 'yes');
    }
    await f.vote(cand, e, 'yes');
    return e;
  }

  bool has(LedgerState s, P p) => s.deviceFor(p.key.publicKey) != null;

  group('pause: either parent, at once, visible to all, never a removal', () {
    test('one parent pauses the other: it is in force, everyone can see who did it, and the paused parent stays a member', () async {
      final Fam f = await two();
      final LedgerEntry p = await f.add(mom, EntryType.accessPause, <String, Object?>{'gid': dad.gid});
      final LedgerState s = await f.state();
      expect(s.rejected.containsKey(p.hashHex), isFalse);
      expect(s.isPaused(dad.gidHex), isTrue);
      expect(s.pauseOf(dad.gidHex)!.byGidHex, mom.gidHex);
      expect(has(s, dad), isTrue, reason: 'a pause is not a removal');
      expect(s.members.map((LedgerMember m) => m.gidHex), containsAll(<String>[mom.gidHex, dad.gidHex]));
      expect(s.canAct(dad.key.publicKey, f.clock), isFalse);
      expect(s.canAct(mom.key.publicKey, f.clock), isTrue);
    });

    test('a paused parent cannot start anything (welcome, policy, pause back, resume themselves), but can leave', () async {
      final Fam f = await two();
      await f.add(mom, EntryType.accessPause, <String, Object?>{'gid': dad.gid});
      final LedgerEntry welcome = await f.add(dad, EntryType.memberAdd, f.memberBody(eve, electors: <P>[dad, mom]));
      final LedgerEntry back = await f.add(dad, EntryType.accessPause, <String, Object?>{'gid': mom.gid});
      final LedgerEntry self = await f.add(dad, EntryType.accessResume, <String, Object?>{'gid': dad.gid});
      final LedgerEntry policy = await f.add(dad, EntryType.policySet, <String, Object?>{'policy': const FamilyPolicy(settleHours: 72).toValue(), 'exp': null});
      final LedgerState s = await f.state();
      for (final LedgerEntry e in <LedgerEntry>[welcome, back, self, policy]) {
        expect(s.rejected[e.hashHex], 'signer-paused', reason: e.type);
      }
      expect(s.isPaused(mom.gidHex), isFalse, reason: 'a paused parent cannot lock the other out in return');
      final LedgerEntry leave = await f.add(dad, EntryType.guardianLeave, <String, Object?>{'gid': dad.gid});
      expect((await f.state()).rejected.containsKey(leave.hashHex), isFalse, reason: 'leaving is always allowed');
    });

    test('a paused parent still has their say: their yes counts, so a pause cannot be used to add a parent alone', () async {
      final Fam f = await two();
      await f.add(mom, EntryType.accessPause, <String, Object?>{'gid': dad.gid});
      final LedgerEntry e = await f.add(mom, EntryType.memberAdd, f.memberBody(eve, electors: <P>[mom, dad]));
      await f.vote(eve, e, 'yes');
      LedgerState s = await f.state();
      expect(has(s, eve), isFalse, reason: 'Dad is paused, not removed: his yes is still needed');
      await f.vote(dad, e, 'yes');
      s = await f.state();
      expect(has(s, eve), isTrue, reason: 'and his yes still counts');
    });

    test('only another parent can resume, and then nothing is paused', () async {
      final Fam f = await two();
      await f.add(mom, EntryType.accessPause, <String, Object?>{'gid': dad.gid});
      final LedgerEntry r = await f.add(mom, EntryType.accessResume, <String, Object?>{'gid': dad.gid});
      final LedgerState s = await f.state();
      expect(s.rejected.containsKey(r.hashHex), isFalse);
      expect(s.isPaused(dad.gidHex), isFalse);
      expect(s.canAct(dad.key.publicKey, f.clock), isTrue);
    });

    test('nobody can pause themselves, pause twice, or resume someone who is not paused', () async {
      final Fam f = await two();
      final LedgerEntry self = await f.add(mom, EntryType.accessPause, <String, Object?>{'gid': mom.gid});
      final LedgerEntry noop = await f.add(mom, EntryType.accessResume, <String, Object?>{'gid': dad.gid});
      await f.add(mom, EntryType.accessPause, <String, Object?>{'gid': dad.gid});
      final LedgerEntry twice = await f.add(mom, EntryType.accessPause, <String, Object?>{'gid': dad.gid});
      final LedgerState s = await f.state();
      expect(s.rejected[self.hashHex], 'cannot-pause-yourself');
      expect(s.rejected[noop.hashHex], 'not-paused');
      expect(s.rejected[twice.hashHex], 'already-paused');
    });

    test('a grown-up who is still settling in, a child tablet and a carer cannot pause anyone', () async {
      final Fam f = await Fam.found(mom);
      await f.welcomeParent(mom, dad, others: <P>[]); // Dad is settling in
      await f.addChild(mom, kid);
      f.clock += 4 * day;
      final LedgerEntry c = await carer(f, mom, jo, yes: <P>[dad]);
      final LedgerEntry byKid = await f.add(kid, EntryType.accessPause, <String, Object?>{'gid': mom.gid});
      final LedgerEntry byCarer = await f.add(jo, EntryType.accessPause, <String, Object?>{'gid': mom.gid});
      expect(c.hashHex, isNotEmpty);
      final LedgerState s = await f.state();
      expect(s.rejected[byKid.hashHex], 'child-key-cannot-sign');
      expect(s.rejected[byCarer.hashHex], 'carer-key-cannot-sign');
      final Fam g = await Fam.found(mom);
      await g.welcomeParent(mom, dad, others: <P>[]);
      final LedgerEntry early = await g.add(dad, EntryType.accessPause, <String, Object?>{'gid': mom.gid});
      expect((await g.state()).rejected[early.hashHex], 'signer-settling');
    });

    test('two parents who pause each other without seeing each other: neither pause stands, so nobody is locked out of both', () async {
      final Fam f = await two();
      final List<List<int>> head = (await f.state()).heads;
      final LedgerEntry a = await f.add(mom, EntryType.accessPause, <String, Object?>{'gid': dad.gid}, prev: head);
      final LedgerEntry b = await f.add(dad, EntryType.accessPause, <String, Object?>{'gid': mom.gid}, prev: head);
      final LedgerState s = await f.state();
      expect(s.isPaused(mom.gidHex), isFalse);
      expect(s.isPaused(dad.gidHex), isFalse);
      expect(s.voided[a.hashHex], 'mutual-pause');
      expect(s.voided[b.hashHex], 'mutual-pause');
      expect(s.forks, isNotEmpty, reason: 'the family is shown that two things happened at once');
    });

    test('a pause beats a resume that never saw it, and beats a welcome the paused parent wrote without seeing it', () async {
      final Fam f = await two();
      final LedgerEntry c = await carer(f, mom, jo, yes: <P>[dad]);
      final List<List<int>> base = (await f.state()).heads;
      expect(c.hashHex, isNotEmpty);
      // Dad and Mom each pause Jo without seeing the other; Mom then resumes having seen only her own pause.
      final LedgerEntry p1 = await f.add(mom, EntryType.accessPause, <String, Object?>{'gid': jo.gid}, prev: base);
      final LedgerEntry p2 = await f.add(dad, EntryType.accessPause, <String, Object?>{'gid': jo.gid}, prev: base);
      await f.add(mom, EntryType.accessResume, <String, Object?>{'gid': jo.gid}, prev: <List<int>>[p1.hash]);
      LedgerState s = await f.state();
      expect(s.rejected.containsKey(p2.hashHex), isFalse);
      expect(s.isPaused(jo.gidHex), isTrue, reason: 'a resume cannot undo a pause it never saw');
      // Dad pauses Mom; Mom, not having seen it, welcomes Eve afterwards: that welcome does not survive.
      final Fam g = await two();
      final List<List<int>> head = (await g.state()).heads;
      await g.add(dad, EntryType.accessPause, <String, Object?>{'gid': mom.gid}, prev: head);
      final LedgerEntry blind = await g.add(mom, EntryType.memberAdd, g.memberBody(eve, electors: <P>[mom, dad]), prev: head);
      s = await g.state();
      expect(s.voided[blind.hashHex], 'signer-paused-concurrently');
    });

    test('delivery order never matters for any of it', () async {
      final Fam f = await two();
      final LedgerEntry c = await carer(f, mom, jo, yes: <P>[dad]);
      await f.add(mom, EntryType.accessPause, <String, Object?>{'gid': dad.gid});
      await f.add(dad, EntryType.accessEnd, <String, Object?>{'gid': mom.gid, 'reason': 'notice'});
      await f.add(mom, EntryType.standingOk, <String, Object?>{'gid': mom.gid, 'until': f.clock + day});
      expect(c.hashHex, isNotEmpty);
      final String want = Fam.summary(await f.state(f.clock + 20 * day));
      final Random rng = Random(11);
      for (int i = 0; i < 25; i++) {
        final List<LedgerEntry> es = List<LedgerEntry>.of(f.entries)..shuffle(rng);
        final List<LedgerVote> vs = List<LedgerVote>.of(f.votes)..shuffle(rng);
        final LedgerState s = await reduceLedger(entries: es, votes: vs, nowMs: f.clock + 20 * day, pin: f.pin);
        expect(Fam.summary(s), want);
      }
    });
  });

  group('ending: nobody removes another parent alone', () {
    test('a parent cannot end another parent at once: not as a carer-style end, and a remove waits for their own yes', () async {
      final Fam f = await two();
      final LedgerEntry end = await f.add(mom, EntryType.accessEnd, <String, Object?>{'gid': dad.gid, 'reason': 'ended'});
      final LedgerEntry rm = await f.add(mom, EntryType.guardianRemove, <String, Object?>{'gid': dad.gid, 'exp': f.clock + 2 * day});
      LedgerState s = await f.state();
      expect(s.rejected[end.hashHex], 'parents-end-together-or-by-notice');
      expect(has(s, dad), isTrue);
      expect(s.pendingFor(rm.hashHex)!.status, 'pending');
      await f.vote(mom, rm, 'yes'); // her own yes changes nothing: the person being removed must agree
      expect(has(await f.state(), dad), isTrue);
      await f.vote(dad, rm, 'no');
      s = await f.state();
      expect(has(s, dad), isTrue);
      expect(s.pendingFor(rm.hashHex)!.status, 'declined');
    });

    test('both parents agree: the parent is ended, and what they did earlier stays', () async {
      final Fam f = await two();
      final LedgerEntry rm = await f.add(mom, EntryType.guardianRemove, <String, Object?>{'gid': dad.gid, 'exp': f.clock + 2 * day});
      await f.vote(dad, rm, 'yes');
      final LedgerState s = await f.state();
      expect(has(s, dad), isFalse);
      expect(s.members.map((LedgerMember m) => m.gidHex), <String>[mom.gidHex]);
    });

    test('the 14 day wait: a notice is visible the whole time, changes nothing until then, then ends the parent', () async {
      final Fam f = await two();
      final LedgerEntry n = await f.add(mom, EntryType.accessEnd, <String, Object?>{'gid': dad.gid, 'reason': 'notice'});
      final int at = n.issuedAtMs;
      LedgerState s = await f.state(at + 13 * day);
      expect(s.rejected.containsKey(n.hashHex), isFalse);
      expect(has(s, dad), isTrue);
      expect(s.noticeFor(dad.gidHex)!.effMs, at + kEndNoticeMs);
      expect(s.noticeFor(dad.gidHex)!.byGidHex, mom.gidHex);
      expect(s.canAct(dad.key.publicKey, at + 13 * day), isTrue, reason: 'a notice does not take away anything while it runs');
      s = await f.state(at + 14 * day + hour);
      expect(has(s, dad), isFalse);
      expect(s.noticeFor(dad.gidHex), isNull);
    });

    test('only the one who gave the notice can take it back, and only before it takes effect; the person it is about cannot', () async {
      final Fam f = await two();
      final LedgerEntry n = await f.add(mom, EntryType.accessEnd, <String, Object?>{'gid': dad.gid, 'reason': 'notice'});
      final LedgerEntry byDad = await f.add(dad, EntryType.accessEndCancel, <String, Object?>{'end': n.hash});
      LedgerState s = await f.state();
      expect(s.rejected[byDad.hashHex], 'only-the-one-who-gave-notice');
      expect(s.noticeFor(dad.gidHex), isNotNull);
      final LedgerEntry byMom = await f.add(mom, EntryType.accessEndCancel, <String, Object?>{'end': n.hash}, prev: <List<int>>[n.hash]);
      s = await f.state(n.issuedAtMs + 20 * day);
      expect(s.rejected.containsKey(byMom.hashHex), isFalse);
      expect(has(s, dad), isTrue, reason: 'taken back in time');
      final LedgerEntry n2 = await f.add(mom, EntryType.accessEnd, <String, Object?>{'gid': dad.gid, 'reason': 'notice'}, at: n.issuedAtMs + 30 * day,
          prev: (await f.state(n.issuedAtMs + 30 * day)).heads);
      final LedgerEntry late = await f.add(mom, EntryType.accessEndCancel, <String, Object?>{'end': n2.hash}, at: n2.issuedAtMs + 15 * day,
          prev: <List<int>>[n2.hash]);
      s = await f.state(n2.issuedAtMs + 16 * day);
      expect(s.rejected[late.hashHex], 'too-late-to-cancel');
      expect(has(s, dad), isFalse);
    });

    test('a notice written on the very first entry with a time just after it cannot skip the wait', () async {
      final Fam f = await two();
      final LedgerEntry genesis = f.entries.first;
      f.clock += 20 * day;
      // Dad has been active since, so the ledger holds a recent entry of his that the old notice does not build on.
      final LedgerEntry active = await f.add(dad, EntryType.accessEnd, <String, Object?>{'gid': mom.gid, 'reason': 'notice'});
      final LedgerEntry backdated = await f.add(mom, EntryType.accessEnd, <String, Object?>{'gid': dad.gid, 'reason': 'notice'},
          prev: <List<int>>[genesis.hash], at: genesis.issuedAtMs + 1000);
      final LedgerState s = await f.state(active.issuedAtMs + day);
      expect(s.rejected.containsKey(backdated.hashHex), isFalse, reason: 'it is well formed; it just does not count');
      expect(has(s, dad), isTrue, reason: 'a backdated notice must not remove a parent with no wait');
      expect(s.noticeFor(dad.gidHex), isNull, reason: 'and it does not show as a running notice either');
      expect(s.noticeFor(mom.gidHex)!.effMs, active.issuedAtMs + kEndNoticeMs, reason: 'the honest notice runs its full wait');
    });

    test('a paused parent can take back their own notice, and a notice cannot be given twice for one person', () async {
      final Fam f = await two();
      final LedgerEntry n = await f.add(dad, EntryType.accessEnd, <String, Object?>{'gid': mom.gid, 'reason': 'notice'});
      await f.add(mom, EntryType.accessPause, <String, Object?>{'gid': dad.gid});
      final LedgerEntry again = await f.add(mom, EntryType.accessEnd, <String, Object?>{'gid': dad.gid, 'reason': 'notice'});
      final LedgerEntry dupe = await f.add(dad, EntryType.accessEnd, <String, Object?>{'gid': mom.gid, 'reason': 'notice'});
      final LedgerEntry cancel = await f.add(dad, EntryType.accessEndCancel, <String, Object?>{'end': n.hash});
      final LedgerState s = await f.state();
      expect(s.rejected[dupe.hashHex], 'signer-paused');
      expect(s.rejected.containsKey(again.hashHex), isFalse);
      expect(s.rejected.containsKey(cancel.hashHex), isFalse, reason: 'taking back your own notice is always allowed');
      expect(s.noticeFor(mom.gidHex), isNull);
    });

    test('two notices at once never remove everybody: the earlier one stands, the other is void by then', () async {
      final Fam f = await two();
      final List<List<int>> head = (await f.state()).heads;
      final LedgerEntry a = await f.add(mom, EntryType.accessEnd, <String, Object?>{'gid': dad.gid, 'reason': 'notice'}, prev: head);
      final LedgerEntry b = await f.add(dad, EntryType.accessEnd, <String, Object?>{'gid': mom.gid, 'reason': 'notice'}, prev: head);
      expect(a.issuedAtMs < b.issuedAtMs, isTrue);
      final LedgerState s = await f.state(a.issuedAtMs + 20 * day);
      expect(s.members.map((LedgerMember m) => m.gidHex), <String>[mom.gidHex], reason: 'one parent is always left');
    });

    test('a carer: the parent who welcomed them ends it at once; another parent needs that parent\'s yes; either can pause at once', () async {
      final Fam f = await two();
      await carer(f, mom, jo, yes: <P>[dad]);
      // Dad cannot end Mom's carer alone.
      final LedgerEntry byDad = await f.add(dad, EntryType.accessEnd, <String, Object?>{'gid': jo.gid, 'reason': 'ended'});
      LedgerState s = await f.state();
      expect(has(s, jo), isTrue);
      expect(s.pendingFor(byDad.hashHex)!.status, 'pending');
      // Dad can pause at once.
      await f.add(dad, EntryType.accessPause, <String, Object?>{'gid': jo.gid});
      s = await f.state();
      expect(s.isPaused(jo.gidHex), isTrue);
      expect(has(s, jo), isTrue);
      // Mom's yes ends it.
      await f.vote(mom, byDad, 'yes');
      s = await f.state();
      expect(has(s, jo), isFalse);
      expect(s.isPaused(jo.gidHex), isFalse);
      // And Mom may end one she welcomed on her own, at once.
      final Fam g = await two();
      await carer(g, mom, jo, yes: <P>[dad]);
      await g.add(mom, EntryType.accessEnd, <String, Object?>{'gid': jo.gid, 'reason': 'ended'});
      expect(has(await g.state(), jo), isFalse);
    });

    test('a refusal by the welcoming parent leaves the carer in, and a stranger cannot end or pause anyone', () async {
      final Fam f = await two();
      await carer(f, mom, jo, yes: <P>[dad]);
      final LedgerEntry byDad = await f.add(dad, EntryType.accessEnd, <String, Object?>{'gid': jo.gid, 'reason': 'ended'});
      await f.vote(mom, byDad, 'no');
      final LedgerEntry byEve = await f.add(eve, EntryType.accessEnd, <String, Object?>{'gid': jo.gid, 'reason': 'notice'});
      final LedgerEntry byCarer = await f.add(jo, EntryType.accessEnd, <String, Object?>{'gid': mom.gid, 'reason': 'notice'});
      final LedgerState s = await f.state();
      expect(has(s, jo), isTrue);
      expect(s.rejected[byEve.hashHex], 'signer-unknown');
      expect(s.rejected[byCarer.hashHex], 'carer-key-cannot-sign');
    });

    test('reasons only a person or the clock can have (left, time box, court) are not something a parent can write', () async {
      final Fam f = await two();
      await carer(f, mom, jo, yes: <P>[dad]);
      for (final String r in <String>['left', 'time_box', 'court']) {
        final LedgerEntry e = await f.add(mom, EntryType.accessEnd, <String, Object?>{'gid': jo.gid, 'reason': r});
        expect((await f.state()).rejected[e.hashHex], 'reason-not-supported', reason: r);
      }
    });
  });

  group('the limits agreement: only with the limited parent\'s own yes, after a 24 hour think-over', () {
    Future<(Fam, LedgerEntry, int)> proposed({List<int> limits = const <int>[11]}) async {
      final Fam f = await two();
      final int until = f.clock + 60000 + kThinkOverMs;
      final LedgerEntry e = await f.add(mom, EntryType.limitsAgree, <String, Object?>{'gid': dad.gid, 'limits': limits, 'until': until});
      return (f, e, until);
    }

    test('until the limited parent says yes, nothing changes', () async {
      final (Fam f, LedgerEntry e, int until) = await proposed();
      final LedgerState s = await f.state(until + hour);
      expect(s.rejected.containsKey(e.hashHex), isFalse);
      expect(s.limitsOf(dad.gidHex), isEmpty);
      expect(s.pendingFor(e.hashHex)!.status, 'pending');
      final LedgerEntry w = await f.add(dad, EntryType.memberAdd, f.memberBody(eve, electors: <P>[dad, mom]), at: until + hour, prev: s.heads);
      expect((await f.state(until + 2 * hour)).rejected.containsKey(w.hashHex), isFalse);
    });

    test('a yes before the think-over ended is not counted; one after it is, and it takes effect then', () async {
      final (Fam f, LedgerEntry e, int until) = await proposed();
      await f.vote(dad, e, 'yes', at: e.issuedAtMs + 2 * hour);
      expect((await f.state(until + hour)).limitsOf(dad.gidHex), isEmpty, reason: 'answered too soon');
      await f.vote(dad, e, 'yes', at: until + hour);
      final LedgerState s = await f.state(until + 2 * hour);
      expect(s.limitsOf(dad.gidHex), <int>[11]);
      expect(s.pendingFor(e.hashHex), isNull);
      expect((await f.state(until)).limitsOf(dad.gidHex), isEmpty, reason: 'not before the yes');
    });

    test('once in force the limit is enforced: no welcoming, and (for the others) no settings or no child devices', () async {
      final (Fam f, LedgerEntry e, int until) = await proposed(limits: <int>[6, 8, 11]);
      await f.vote(dad, e, 'yes', at: until + hour);
      final int t = until + 2 * hour;
      final List<List<int>> h = (await f.state(t)).heads;
      final LedgerEntry welcome = await f.add(dad, EntryType.memberAdd, f.memberBody(eve, electors: <P>[dad, mom]), at: t, prev: h);
      final LedgerEntry policy = await f.add(dad, EntryType.policySet, <String, Object?>{'policy': const FamilyPolicy(settleHours: 72).toValue(), 'exp': null}, at: t, prev: h);
      final LedgerEntry child = await f.add(dad, EntryType.deviceAdd, f.childBody(kid), at: t, prev: h);
      final LedgerState s = await f.state(t + hour);
      expect(s.rejected[welcome.hashHex], 'welcome-limited');
      expect(s.rejected[policy.hashHex], 'settings-limited');
      expect(s.rejected[child.hashHex], 'connect-limited');
    });

    test('a limit never takes away what a parent can see, their say on welcomes, their pause or leaving', () async {
      final (Fam f, LedgerEntry e, int until) = await proposed(limits: <int>[6, 8, 11]);
      await f.vote(dad, e, 'yes', at: until + hour);
      final int t = until + 2 * hour;
      // His yes on someone else's welcome still counts.
      final LedgerEntry w = await f.add(mom, EntryType.memberAdd, f.memberBody(eve, electors: <P>[mom, dad]), at: t, prev: (await f.state(t)).heads);
      await f.vote(eve, w, 'yes', at: t + 1000);
      expect(has(await f.state(t + hour), eve), isFalse);
      await f.vote(dad, w, 'yes', at: t + 2000);
      expect(has(await f.state(t + hour), eve), isTrue);
      // He can still pause and leave.
      final LedgerEntry p = await f.add(dad, EntryType.accessPause, <String, Object?>{'gid': mom.gid}, at: t + 3000, prev: (await f.state(t + hour)).heads);
      expect((await f.state(t + hour)).rejected.containsKey(p.hashHex), isFalse);
      // And the list can never name a capability that is a floor.
      for (final List<int> bad in <List<int>>[<int>[1], <int>[2], <int>[3], <int>[4], <int>[5], <int>[7], <int>[9], <int>[10], <int>[12], <int>[13], <int>[11, 6], <int>[6, 6], <int>[14], <int>[]]) {
        final Fam g = await two();
        final LedgerEntry x = await g.add(mom, EntryType.limitsAgree, <String, Object?>{'gid': dad.gid, 'limits': bad, 'until': g.clock + 2 * day});
        expect((await g.state()).rejected[x.hashHex], isIn(<String>['limits-not-allowed', 'limits-empty']), reason: '$bad');
      }
    });

    test('the proposer cannot say yes for the limited parent; a no, a withdrawal and silence all end it with nothing changed', () async {
      final (Fam f, LedgerEntry e, int until) = await proposed();
      await f.vote(mom, e, 'yes', at: until + hour);
      await f.vote(eve, e, 'yes', at: until + hour);
      expect((await f.state(until + 2 * hour)).limitsOf(dad.gidHex), isEmpty);
      await f.vote(dad, e, 'no', at: e.issuedAtMs + hour);
      LedgerState s = await f.state(until + 2 * hour);
      expect(s.pendingFor(e.hashHex)!.status, 'declined');
      expect(s.limitsOf(dad.gidHex), isEmpty);
      final (Fam g, LedgerEntry e2, int u2) = await proposed();
      await g.vote(mom, e2, 'withdraw', at: e2.issuedAtMs + hour);
      await g.vote(dad, e2, 'yes', at: u2 + hour);
      expect((await g.state(u2 + 2 * hour)).limitsOf(dad.gidHex), isEmpty, reason: 'withdrawn first');
      final (Fam h, LedgerEntry e3, int u3) = await proposed();
      s = await h.state(e3.issuedAtMs + 15 * day);
      expect(s.pendingFor(e3.hashHex)!.status, 'lapsed');
      await h.vote(dad, e3, 'yes', at: e3.issuedAtMs + 15 * day);
      expect((await h.state(e3.issuedAtMs + 16 * day)).limitsOf(dad.gidHex), isEmpty, reason: 'a late yes is not a yes');
      expect(u3, greaterThan(0));
    });

    test('a yes belongs to one agreement: it cannot be moved onto a different list or a different request', () async {
      final Fam f = await two();
      final int until = f.clock + 60000 + kThinkOverMs;
      final LedgerEntry small = await f.add(mom, EntryType.limitsAgree, <String, Object?>{'gid': dad.gid, 'limits': <int>[11], 'until': until});
      final LedgerEntry big = await f.add(mom, EntryType.limitsAgree, <String, Object?>{'gid': dad.gid, 'limits': <int>[6, 8, 11], 'until': f.clock + 60000 + kThinkOverMs},
          prev: <List<int>>[small.hash]);
      await f.vote(dad, small, 'yes', at: until + hour);
      final LedgerState s = await f.state(until + 2 * hour);
      expect(s.limitsOf(dad.gidHex), <int>[11], reason: 'the bigger list was never agreed to');
      expect(s.pendingFor(big.hashHex)!.status, 'pending');
    });

    test('a think-over shorter than a day, or one past the request\'s life, is refused; limits are for a parent only', () async {
      final Fam f = await two();
      final LedgerEntry quick = await f.add(mom, EntryType.limitsAgree, <String, Object?>{'gid': dad.gid, 'limits': <int>[11], 'until': f.clock + 2 * hour});
      final LedgerEntry far = await f.add(mom, EntryType.limitsAgree, <String, Object?>{'gid': dad.gid, 'limits': <int>[11], 'until': f.clock + 20 * day});
      await carer(f, mom, jo, yes: <P>[dad]);
      final LedgerEntry onCarer = await f.add(mom, EntryType.limitsAgree, <String, Object?>{'gid': jo.gid, 'limits': <int>[11], 'until': f.clock + 2 * day});
      final LedgerState s = await f.state();
      expect(s.rejected[quick.hashHex], 'bad-think-over');
      expect(s.rejected[far.hashHex], 'bad-think-over');
      expect(s.rejected[onCarer.hashHex], 'limits-are-for-a-parent');
    });

    test('a parent may tighten their own limits at once; nobody else may, and it must be tighter', () async {
      final (Fam f, LedgerEntry e, int until) = await proposed(limits: <int>[11]);
      await f.vote(dad, e, 'yes', at: until + hour);
      final int t = until + 2 * hour;
      final List<List<int>> h = (await f.state(t)).heads;
      final LedgerEntry byMom = await f.add(mom, EntryType.limitsTighten, <String, Object?>{'gid': dad.gid, 'limits': <int>[8, 11]}, at: t, prev: h);
      final LedgerEntry same = await f.add(dad, EntryType.limitsTighten, <String, Object?>{'gid': dad.gid, 'limits': <int>[11]}, at: t + 1000, prev: <List<int>>[byMom.hash]);
      final LedgerEntry fewer = await f.add(dad, EntryType.limitsTighten, <String, Object?>{'gid': dad.gid, 'limits': <int>[6]}, at: t + 2000, prev: <List<int>>[byMom.hash]);
      LedgerState s = await f.state(t + hour);
      expect(s.rejected[byMom.hashHex], 'only-yourself');
      expect(s.rejected[same.hashHex], isNotNull);
      expect(s.rejected[fewer.hashHex], isNotNull);
      final LedgerEntry ok = await f.add(dad, EntryType.limitsTighten, <String, Object?>{'gid': dad.gid, 'limits': <int>[8, 11]}, at: t + 3000, prev: h);
      s = await f.state(t + hour);
      expect(s.rejected.containsKey(ok.hashHex), isFalse);
      expect(s.limitsOf(dad.gidHex), <int>[8, 11]);
    });

    test('loosening or ending needs the other parent\'s yes; the limited parent alone changes nothing', () async {
      final (Fam f, LedgerEntry e, int until) = await proposed(limits: <int>[8, 11]);
      await f.vote(dad, e, 'yes', at: until + hour);
      final int t = until + 2 * hour;
      final LedgerEntry ask = await f.add(dad, EntryType.limitsAgree, <String, Object?>{'gid': dad.gid, 'limits': <int>[11], 'until': t}, at: t, prev: (await f.state(t)).heads);
      LedgerState s = await f.state(t + hour);
      expect(s.limitsOf(dad.gidHex), <int>[8, 11], reason: 'asking is not enough');
      expect(s.pendingFor(ask.hashHex)!.status, 'pending');
      await f.vote(mom, ask, 'yes', at: t + 2 * hour);
      s = await f.state(t + 3 * hour);
      expect(s.limitsOf(dad.gidHex), <int>[11]);
      // Not a loosening (the same or more) is refused outright; and a parent with no limits has nothing to ask about.
      final LedgerEntry more = await f.add(dad, EntryType.limitsAgree, <String, Object?>{'gid': dad.gid, 'limits': <int>[6, 11], 'until': t + 4 * hour}, at: t + 4 * hour, prev: s.heads);
      expect((await f.state(t + 5 * hour)).rejected[more.hashHex], 'not-a-loosening');
    });

    test('a parent\'s own earlier entries stay valid after limits take effect (position decides, not today)', () async {
      final Fam f = await two();
      final LedgerEntry w = await f.add(dad, EntryType.memberAdd, f.memberBody(eve, electors: <P>[dad, mom]));
      final int until = f.clock + 60000 + kThinkOverMs;
      final LedgerEntry e = await f.add(mom, EntryType.limitsAgree, <String, Object?>{'gid': dad.gid, 'limits': <int>[11], 'until': until});
      await f.vote(dad, e, 'yes', at: until + hour);
      final LedgerState s = await f.state(until + 2 * hour);
      expect(s.rejected.containsKey(w.hashHex), isFalse);
      expect(s.limitsOf(dad.gidHex), <int>[11]);
    });

    test('a carer or a settling grown-up cannot propose limits, and delivery order never matters', () async {
      final Fam f = await two();
      await carer(f, mom, jo, yes: <P>[dad]);
      final LedgerEntry byCarer = await f.add(jo, EntryType.limitsAgree, <String, Object?>{'gid': dad.gid, 'limits': <int>[11], 'until': f.clock + 2 * day});
      expect((await f.state()).rejected[byCarer.hashHex], 'carer-key-cannot-sign');
      final int until = f.clock + 60000 + kThinkOverMs;
      final LedgerEntry e = await f.add(mom, EntryType.limitsAgree, <String, Object?>{'gid': dad.gid, 'limits': <int>[6, 11], 'until': until});
      await f.vote(dad, e, 'yes', at: until + hour);
      final String want = Fam.summary(await f.state(until + 2 * hour));
      final Random rng = Random(3);
      for (int i = 0; i < 20; i++) {
        final List<LedgerEntry> es = List<LedgerEntry>.of(f.entries)..shuffle(rng);
        final List<LedgerVote> vs = List<LedgerVote>.of(f.votes)..shuffle(rng);
        expect(Fam.summary(await reduceLedger(entries: es, votes: vs, nowMs: until + 2 * hour, pin: f.pin)), want);
      }
    });
  });

  group('Standing OK: a parent\'s advance yes to Look-only welcomes, never more', () {
    Future<LedgerEntry> lookWelcome(Fam f, P by, {Preset preset = Preset.viewOnly, List<P>? asked}) => f.add(by, EntryType.memberAdd,
        f.memberBody(jo, kind: 'carer', preset: preset, electors: asked ?? <P>[mom, dad], rule: 'all', name: 'Jo'));

    test('with it, a Look-only welcome needs only the candidate and the asker; without it, the other parent is waited for', () async {
      final Fam f = await two(policy: const FamilyPolicy(carerLook: 'all'));
      final LedgerEntry without = await lookWelcome(f, mom);
      await f.vote(jo, without, 'yes');
      expect(has(await f.state(), jo), isFalse, reason: 'Dad has not said yes');
      final Fam g = await two(policy: const FamilyPolicy(carerLook: 'all'));
      await g.add(dad, EntryType.standingOk, <String, Object?>{'gid': dad.gid, 'until': g.clock + 30 * day});
      final LedgerEntry withIt = await lookWelcome(g, mom);
      await g.vote(jo, withIt, 'yes');
      expect(has(await g.state(), jo), isTrue, reason: 'Dad said yes in advance');
      expect((await g.state()).members.firstWhere((LedgerMember m) => m.name == 'Jo').welcomedByGidHex, mom.gidHex);
    });

    test('it covers nothing that can act and never a parent: those still wait for the giver\'s own yes', () async {
      final Fam f = await two(policy: const FamilyPolicy(carerLook: 'all'));
      await f.add(dad, EntryType.standingOk, <String, Object?>{'gid': dad.gid, 'until': f.clock + 30 * day});
      final LedgerEntry act = await f.add(mom, EntryType.memberAdd,
          f.memberBody(jo, kind: 'carer', preset: Preset.trustedCarer, electors: <P>[mom, dad], rule: 'all', name: 'Jo'));
      await f.vote(jo, act, 'yes');
      expect(has(await f.state(), jo), isFalse, reason: 'a carer who can act is not covered');
      final LedgerEntry parent = await f.add(mom, EntryType.memberAdd, f.memberBody(eve, electors: <P>[mom, dad], name: 'Eve'),
          prev: (await f.state()).heads);
      await f.vote(eve, parent, 'yes');
      expect(has(await f.state(), eve), isFalse, reason: 'a parent is never covered');
    });

    test('it ends on its date, can be taken back by writing a shorter one, and the strictest of two at once stands', () async {
      final Fam f = await two(policy: const FamilyPolicy(carerLook: 'all'));
      final LedgerEntry ok = await f.add(dad, EntryType.standingOk, <String, Object?>{'gid': dad.gid, 'until': f.clock + 2 * day});
      expect((await f.state()).standingActive(dad.gidHex), isTrue);
      expect((await f.state(f.clock + 3 * day)).standingActive(dad.gidHex), isFalse, reason: 'it ends on its date');
      final LedgerEntry back = await f.add(dad, EntryType.standingOk, <String, Object?>{'gid': dad.gid, 'until': 0}, prev: <List<int>>[ok.hash]);
      expect((await f.state()).standingActive(dad.gidHex), isFalse);
      expect(back.hashHex, isNotEmpty);
      final Fam g = await two(policy: const FamilyPolicy(carerLook: 'all'));
      final List<List<int>> h = (await g.state()).heads;
      await g.add(dad, EntryType.standingOk, <String, Object?>{'gid': dad.gid, 'until': g.clock + 30 * day}, prev: h);
      await g.add(dad, EntryType.standingOk, <String, Object?>{'gid': dad.gid, 'until': g.clock + 1 * day}, prev: h);
      expect((await g.state(g.clock + 5 * day)).standingActive(dad.gidHex), isFalse, reason: 'the shorter one stands');
    });

    test('an advance yes must be the giver\'s own, at most 90 days, and a carer or a settling grown-up cannot give one', () async {
      final Fam f = await two(policy: const FamilyPolicy(carerLook: 'all'));
      final LedgerEntry forOther = await f.add(mom, EntryType.standingOk, <String, Object?>{'gid': dad.gid, 'until': f.clock + 30 * day});
      final LedgerEntry tooLong = await f.add(mom, EntryType.standingOk, <String, Object?>{'gid': mom.gid, 'until': f.clock + 91 * day});
      final LedgerEntry ninety = await f.add(mom, EntryType.standingOk, <String, Object?>{'gid': mom.gid, 'until': f.clock + 89 * day});
      await carer(f, mom, jo, yes: <P>[dad]);
      final LedgerEntry byCarer = await f.add(jo, EntryType.standingOk, <String, Object?>{'gid': jo.gid, 'until': f.clock + day});
      final LedgerState s = await f.state();
      expect(s.rejected[forOther.hashHex], 'only-yourself');
      expect(s.rejected[tooLong.hashHex], 'bad-until');
      expect(s.rejected.containsKey(ninety.hashHex), isFalse);
      expect(s.rejected[byCarer.hashHex], 'carer-key-cannot-sign');
      expect(s.standing.keys, contains(mom.gidHex));
    });

    test('a standing yes from a parent who is no longer here covers nobody', () async {
      final Fam f = await two(policy: const FamilyPolicy(carerLook: 'all'));
      await f.add(dad, EntryType.standingOk, <String, Object?>{'gid': dad.gid, 'until': f.clock + 30 * day});
      await f.add(dad, EntryType.guardianLeave, <String, Object?>{'gid': dad.gid});
      final LedgerState s = await f.state();
      expect(s.standing.containsKey(dad.gidHex), isFalse);
      expect(Uint8List(0), isEmpty);
    });
  });
}
