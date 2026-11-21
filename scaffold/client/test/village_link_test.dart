// OLIVE BRANCH — tests for the road between two grown-up phones (village_link.dart): an update sealed to one phone, the
// door that folds it in, and the hostile cases (a carer who tries to approve a parent, a new parent who needs ALL the
// parents, replays, strangers, forged and foreign records). Every phone has its OWN copy of the record, so what one
// knows reaches another only through the road under test. UNVERIFIED until CI runs it.
// Spec: docs/planning/VILLAGE-WELCOME-DESIGN.md sections 3, 5 and 7.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/device_keys.dart';
import 'package:olive_client/family_ledger.dart';
import 'package:olive_client/family_ledger_state.dart';
import 'package:olive_client/family_profiles.dart';
import 'package:olive_client/village_link.dart';
import 'package:olive_client/welcome_logic.dart';

import 'family_test_support.dart';
import 'village_test_support.dart';

VillagePeer peerOf(Phone ph) => VillagePeer(
    deviceKey: ph.p.key.publicKey, agree: ph.p.agree.publicKey, name: 'x', kind: 'guardian');

Future<LedgerEntry> proposeCarer(Village v, P cand, {String name = 'Jo'}) =>
    v.mom.welcome().propose(WelcomeDraft(personName: name, profile: carerProfile(), candidate: cand.rec));

Future<LedgerEntry> proposeParent(Village v, P cand, {String name = 'Eve', Phone? by}) =>
    (by ?? v.mom).welcome().propose(
        WelcomeDraft(personName: name, profile: MemberProfile.defaults(Preset.parent), candidate: cand.rec));

void main() {
  group('who a phone talks to', () {
    test('a grown-up phone sends to the other grown-up and to nobody else; a tablet and itself are not peers', () async {
      final Village v = await Village.make(tablet: true);
      final LedgerState s = await v.mom.state();
      final List<VillagePeer> peers = villagePeers(s, v.mom.ctx.entries, v.mom.p.key.publicKey);
      expect(peers.map((VillagePeer p) => p.keyHex), <String>[v.dad.p.keyHex]);
      expect(peers.any((VillagePeer p) => p.keyHex == v.tablet!.keyHex), isFalse, reason: 'a child tablet is never a peer');
    });

    test('a person with a request waiting becomes a peer, and stops being one when the request ends', () async {
      final Village v = await Village.make();
      final P jo = await P.make(5);
      await proposeCarer(v, jo);
      LedgerState s = await v.mom.state();
      expect(villagePeers(s, v.mom.ctx.entries, v.mom.p.key.publicKey).map((VillagePeer p) => p.name), containsAll(<String>['Jo']));
      v.clock.now += 8 * day; // a carer request lasts 7 days
      s = await v.mom.state();
      expect(villagePeers(s, v.mom.ctx.entries, v.mom.p.key.publicKey).any((VillagePeer p) => p.name == 'Jo'), isFalse);
    });
  });

  group('an update sealed to one phone', () {
    test('only the phone it is for can open it, and only if the sender is allowed', () async {
      final Village v = await Village.make();
      final String sealed = (await v.mom.door.outgoing()).single;
      final LedgerState dadState = await v.dad.state();
      bool allowed(Uint8List k) => senderAllowed(dadState, v.dad.ctx.entries, k);
      final OpenedUpdate? ok = await openVillageUpdate(
          sealed: sealed, own: v.dad.p.key, agreement: v.dad.p.agree, isAllowed: allowed, nowMs: v.clock.now);
      expect(ok, isNotNull);
      expect(ok!.entries.length, v.mom.ctx.entries.length);
      // The sender itself, and a phone it was not sealed to, get nothing.
      expect(await openVillageUpdate(sealed: sealed, own: v.mom.p.key, agreement: v.mom.p.agree, isAllowed: (_) => true, nowMs: v.clock.now), isNull);
      final P other = await P.make(6);
      expect(await openVillageUpdate(sealed: sealed, own: other.key, agreement: other.agree, isAllowed: (_) => true, nowMs: v.clock.now), isNull);
      // The right phone with the wrong agreement key cannot open the box.
      expect(await openVillageUpdate(sealed: sealed, own: v.dad.p.key, agreement: other.agree, isAllowed: allowed, nowMs: v.clock.now), isNull);
      // A sender the record does not allow is turned away before anything is opened.
      expect(await openVillageUpdate(sealed: sealed, own: v.dad.p.key, agreement: v.dad.p.agree, isAllowed: (_) => false, nowMs: v.clock.now), isNull);
    });

    test('a changed byte anywhere, an old update and one from the future open nothing', () async {
      final Village v = await Village.make();
      final String sealed = (await v.mom.door.outgoing()).single;
      final LedgerState s = await v.dad.state();
      Future<OpenedUpdate?> open(String x, {int? at}) => openVillageUpdate(
          sealed: x, own: v.dad.p.key, agreement: v.dad.p.agree,
          isAllowed: (Uint8List k) => senderAllowed(s, v.dad.ctx.entries, k), nowMs: at ?? v.clock.now);
      expect(await open(sealed), isNotNull);
      final Map<String, Object?> top = jsonDecode(utf8.decode(unb64(sealed))) as Map<String, Object?>;
      for (final String f in <String>['ct', 'sig', 'eph', 'from', 'to']) {
        final Map<String, Object?> t = Map<String, Object?>.of(top);
        final Uint8List raw = unb64(t[f]! as String);
        t[f] = b64(flip(raw, raw.length ~/ 2));
        expect(await open(b64(utf8.encode(jsonEncode(t)))), isNull, reason: 'a changed $f');
      }
      final Map<String, Object?> iat = Map<String, Object?>.of(top)..['iat'] = (top['iat']! as int) + 1;
      expect(await open(b64(utf8.encode(jsonEncode(iat)))), isNull, reason: 'a changed time breaks the signature');
      expect(await open(sealed, at: v.clock.now + 31 * day), isNull, reason: 'older than 30 days');
      expect(await open(sealed, at: v.clock.now - 10 * day), isNull, reason: 'from the future');
      expect(await open('not an update'), isNull);
      expect(await open(''), isNull);
    });
  });

  group('the door', () {
    test('a request, a yes, the new person\'s yes and the welcome all travel; every phone ends believing the same', () async {
      final Village v = await Village.make();
      final P joP = await P.make(5);
      final LedgerEntry e = await proposeCarer(v, joP);
      // Dad learns of it only through the road.
      expect((await v.dad.welcome().overview()).forMe, isEmpty);
      final DoorOutcome toDad = await v.mom.reach(v.dad);
      expect(v.dad.changes, greaterThan(0), reason: 'Dad\'s phone took the request in');
      expect(toDad.heardFrom, isNotEmpty);
      expect((await v.dad.welcome().overview()).forMe.single.personName, 'Jo');
      await v.dad.welcome().answer(e.hashHex, WelcomeAnswer.yes);
      // Jo's phone has the record (the meeting gave it) and says yes on its own phone.
      final Phone jo = v.join(joP);
      await candidateSaysYes(ctx: jo.ctx, repository: jo.repo, invitation: e, nowMs: v.clock.now);
      expect((await v.mom.state()).hasPerson(joP), isFalse, reason: 'not in until the right yeses are in');
      await jo.reach(v.mom); // Jo to Mom
      await v.dad.reach(v.mom); // Dad's yes to Mom
      LedgerState ms = await v.mom.state();
      expect(ms.hasPerson(joP), isTrue, reason: 'both parents and Jo said yes');
      await v.mom.reach(v.dad);
      await v.mom.reach(jo);
      expect(await v.dad.summary(), await v.mom.summary());
      expect(await jo.summary(), await v.mom.summary());
      ms = await jo.state();
      expect(ms.deviceFor(joP.key.publicKey)!.kind, 'carer');
    });

    test('a request carried to a phone with only Dad\'s old copy does not need Mom to be reachable again', () async {
      final Village v = await Village.make();
      final P joP = await P.make(5);
      final LedgerEntry e = await proposeCarer(v, joP);
      await v.mom.reach(v.dad);
      await v.dad.welcome().answer(e.hashHex, WelcomeAnswer.no);
      await v.dad.reach(v.mom);
      final WelcomeOverview o = await v.mom.welcome().overview();
      expect(o.sent.singleWhere((WelcomeRequest r) => r.personName == 'Jo').status, 'declined', reason: 'one no from a required parent ends it');
    });

    test('an update delivered again and again changes nothing (replay)', () async {
      final Village v = await Village.make();
      await proposeCarer(v, await P.make(5));
      final List<String> out = await v.mom.door.outgoing();
      final DoorOutcome first = await v.dad.door.absorb(out);
      expect(first.changed, isTrue);
      final String after = await v.dad.summary();
      final int entries = v.dad.ctx.entries.length, votes = v.dad.ctx.votes.length;
      for (int i = 0; i < 3; i++) {
        final DoorOutcome again = await v.dad.door.absorb(out);
        expect(again.changed, isFalse);
      }
      expect(v.dad.ctx.entries.length, entries);
      expect(v.dad.ctx.votes.length, votes);
      expect(await v.dad.summary(), after);
    });

    test('an OLD update replayed after the family moved on does not undo anything', () async {
      final Village v = await Village.make();
      final P joP = await P.make(5);
      final LedgerEntry e = await proposeCarer(v, joP);
      final List<String> early = await v.mom.door.outgoing(); // only the request
      await v.mom.reach(v.dad);
      await v.dad.welcome().answer(e.hashHex, WelcomeAnswer.yes);
      await v.dad.reach(v.mom);
      final String mom = await v.mom.summary();
      await v.mom.door.absorb(<String>[for (final String s in await v.dad.door.outgoing()) s]); // noise
      // Replay an update Mom made earlier, to Dad, long after: Dad's yes stays.
      await v.dad.door.absorb(early);
      final WelcomeOverview dadView = await v.dad.welcome().overview();
      expect(dadView.forMe, isEmpty, reason: 'Dad has answered; the old update does not ask him again');
      expect(dadView.others.where((WelcomeRequest r) => r.personName == 'Jo').length, 1);
      expect(v.dad.ctx.votes.where((LedgerVote x) => x.answer == 'yes' && x.targetHex == e.hashHex).length, 1);
      expect(await v.mom.summary(), mom);
    });

    test('a yes cannot be moved onto another request: a changed target breaks its signature', () async {
      final Village v = await Village.make();
      final LedgerEntry a = await proposeCarer(v, await P.make(5), name: 'Jo');
      await v.mom.reach(v.dad);
      final int baseline = v.mom.ctx.votes.length;
      final LedgerVote yes = await LedgerVote.sign(v.dad.p.key, target: a.hash, answer: 'yes', atMs: v.clock.now);
      final Map<String, Object?> j = yes.toJson();
      j['t'] = b64(flip(a.hash, 3)); // a different request
      final LedgerVote moved = LedgerVote.fromJson(j)!;
      expect(await moved.verifySignature(), isFalse);
      final MergeResult r = await mergeLedger(ctx: v.mom.ctx, entries: const <LedgerEntry>[], votes: <LedgerVote>[moved], nowMs: v.clock.now);
      expect(r.newVotes, 0);
      expect(v.mom.ctx.votes.length, baseline);
    });

    test('a stranger\'s phone, not in the record, is not heard: nothing changes and the door stays silent', () async {
      final Village v = await Village.make();
      final String before = await v.mom.summary();
      final P stranger = await P.make(9);
      // The stranger even knows Mom's agreement key (it is in the record she shares with the family).
      final String sealed = await sealVillageUpdate(
          sender: stranger.key, to: peerOf(v.mom), entries: v.mom.ctx.entries, votes: const <LedgerVote>[], nowMs: v.clock.now);
      expect(await v.mom.door.handle(<String, dynamic>{'t': 'door', 'u': <String>[sealed]}), isNull);
      expect((await v.mom.door.absorb(<String>[sealed])).heardFrom, isEmpty);
      expect(await v.mom.summary(), before);
      expect(v.mom.ctx.entries.length, v.dad.ctx.entries.length);
    });

    test('a hand-made request is answered with silence, not an error', () async {
      final Village v = await Village.make();
      for (final Map<String, dynamic> m in <Map<String, dynamic>>[
        <String, dynamic>{},
        <String, dynamic>{'t': 'door'},
        <String, dynamic>{'t': 'door', 'u': <String>[]},
        <String, dynamic>{'t': 'door', 'u': 'x'},
        <String, dynamic>{'t': 'door', 'u': List<String>.filled(40, 'a')},
        <String, dynamic>{'t': 'door', 'u': <Object?>[1, null, 'zz']},
        <String, dynamic>{'t': 'nope', 'u': <String>['a']},
      ]) {
        expect(await v.mom.door.handle(m), isNull);
      }
    });

    test('a record of ANOTHER family, even from a listed phone, is refused whole and nothing is kept', () async {
      final Village v = await Village.make();
      final P other = await P.make(7);
      final Fam foreign = await Fam.found(other);
      final P friend = await P.make(10);
      await foreign.welcomeParent(other, friend, others: <P>[]);
      final String before = await v.mom.summary();
      final int n = v.mom.ctx.entries.length;
      // Dad is a real, listed phone; the payload he carries is another family's chain.
      final String sealed = await sealVillageUpdate(
          sender: v.dad.p.key, to: peerOf(v.mom), entries: foreign.entries, votes: foreign.votes, nowMs: v.clock.now);
      final DoorOutcome o = await v.mom.door.absorb(<String>[sealed]);
      expect(o.changed, isFalse);
      expect(v.mom.ctx.entries.length, n, reason: 'orphans of another family are not kept');
      expect(await v.mom.summary(), before);
    });

    test('votes from a phone this family does not know are not kept, even with a good signature', () async {
      final Village v = await Village.make();
      final LedgerEntry e = await proposeCarer(v, await P.make(5));
      final P stranger = await P.make(11);
      final LedgerVote bad = await LedgerVote.sign(stranger.key, target: e.hash, answer: 'yes', atMs: v.clock.now);
      final MergeResult r = await mergeLedger(ctx: v.mom.ctx, entries: const <LedgerEntry>[], votes: <LedgerVote>[bad], nowMs: v.clock.now);
      expect(r.newVotes, 0);
    });

    test('a vote dated in the far future is not kept', () async {
      final Village v = await Village.make();
      final LedgerEntry e = await proposeCarer(v, await P.make(5));
      final LedgerVote late = await LedgerVote.sign(v.dad.p.key, target: e.hash, answer: 'yes', atMs: v.clock.now + 3 * day);
      final MergeResult r = await mergeLedger(ctx: v.mom.ctx, entries: const <LedgerEntry>[], votes: <LedgerVote>[late], nowMs: v.clock.now);
      expect(r.newVotes, 0);
    });

    test('a person whose request has ended is no longer heard', () async {
      final Village v = await Village.make();
      final P joP = await P.make(5);
      final LedgerEntry e = await proposeCarer(v, joP);
      final Phone jo = v.join(joP);
      await candidateSaysYes(ctx: jo.ctx, repository: jo.repo, invitation: e, nowMs: v.clock.now);
      final int baseline = v.mom.ctx.votes.length;
      v.clock.now += 8 * day; // lapsed
      final String before = await v.mom.summary();
      expect((await jo.reach(v.mom)).changed, isFalse);
      expect(await v.mom.summary(), before);
      expect(v.mom.ctx.votes.length, baseline, reason: 'the lapsed yes was not kept');
    });

    test('the person being welcomed cannot say yes for someone else\'s request, nor for a parent\'s', () async {
      final Village v = await Village.make();
      final P joP = await P.make(5), eveP = await P.make(6);
      final LedgerEntry forJo = await proposeCarer(v, joP);
      await v.mom.reach(v.dad);
      final Phone jo = v.join(joP);
      // Jo cannot make a vote for Eve's request through the helper...
      final LedgerEntry forEve = await v.dad.welcome().propose(
          WelcomeDraft(personName: 'Eve', profile: carerProfile(), candidate: eveP.rec));
      await expectLater(candidateSaysYes(ctx: jo.ctx, repository: jo.repo, invitation: forEve, nowMs: v.clock.now), throwsStateError);
      // ...and a vote Jo signs by hand for it, even if it reaches Mom, counts for nothing.
      final LedgerVote hand = await LedgerVote.sign(joP.key, target: forEve.hash, answer: 'yes', atMs: v.clock.now);
      jo.ctx.votes.add(hand);
      jo.ctx.entries.add(forEve);
      await v.dad.reach(v.mom);
      await jo.reach(v.mom);
      final LedgerState s = await v.mom.state();
      expect(s.pendingFor(forEve.hashHex)!.status, 'pending');
      expect(s.hasPerson(eveP), isFalse);
      expect(s.hasPerson(joP), isFalse);
      expect(forJo.hashHex, isNotEmpty);
    });
  });

  group('hostile: a carer cannot approve a parent, and a new parent needs ALL the parents', () {
    Future<(Village, Phone, P)> withCarer() async {
      final Village v = await Village.make();
      final P joP = await P.make(5);
      final LedgerEntry e = await proposeCarer(v, joP);
      await v.mom.reach(v.dad);
      await v.dad.welcome().answer(e.hashHex, WelcomeAnswer.yes);
      final Phone jo = v.join(joP);
      await v.dad.reach(jo);
      await candidateSaysYes(ctx: jo.ctx, repository: jo.repo, invitation: e, nowMs: v.clock.now);
      await jo.reach(v.mom);
      await v.dad.reach(v.mom);
      await v.mom.reach(jo);
      await v.mom.reach(v.dad);
      expect((await v.mom.state()).hasPerson(joP), isTrue, reason: 'Jo is welcomed as a carer');
      v.clock.now += 3 * day; // past Jo's settling in, so a refusal is not just "too early"
      return (v, jo, joP);
    }

    test('a carer\'s yes on a new parent is carried, kept, and counts for nothing', () async {
      final (Village v, Phone jo, P joP) = await withCarer();
      final P eveP = await P.make(6);
      final LedgerEntry e = await proposeParent(v, eveP);
      await v.mom.reach(jo);
      await v.mom.reach(v.dad);
      // Jo signs a yes by hand (the app offers a carer no such screen) and sends it by the ordinary road.
      jo.ctx.votes.add(await LedgerVote.sign(joP.key, target: e.hash, answer: 'yes', atMs: v.clock.now));
      expect((await jo.reach(v.mom)).heardFrom, isNotEmpty, reason: 'a carer is a listed phone, so the vote is carried');
      // Eve says yes on her own phone, Mom (the asker) has asked: only Dad has not.
      final Phone eve = v.join(eveP);
      await candidateSaysYes(ctx: eve.ctx, repository: eve.repo, invitation: e, nowMs: v.clock.now);
      await eve.reach(v.mom);
      LedgerState s = await v.mom.state();
      expect(s.pendingFor(e.hashHex)!.status, 'pending', reason: 'Dad has not said yes');
      expect(s.hasPerson(eveP), isFalse);
      final WelcomeRequest r = (await v.mom.welcome().overview()).sent.firstWhere((WelcomeRequest x) => x.personName == 'Eve');
      expect(r.electors.where((ElectorStatus x) => x.answer == 'waiting').map((ElectorStatus x) => x.name), <String>['Sam'], reason: 'Dad is the one still waited for');
      // Dad's yes completes it.
      await v.dad.welcome().answer(e.hashHex, WelcomeAnswer.yes);
      await v.dad.reach(v.mom);
      s = await v.mom.state();
      expect(s.hasPerson(eveP), isTrue);
      expect(s.deviceFor(eveP.key.publicKey)!.settlingAt(v.clock.now), isTrue, reason: 'a new parent settles in for 72 hours');
    });

    test('a carer\'s own request to bring in a parent is carried and refused by every phone', () async {
      final (Village v, Phone jo, P joP) = await withCarer();
      final P eveP = await P.make(6);
      // Jo signs a member.add as if a parent: the body is well formed and names both parents as electors.
      final LedgerState s0 = await jo.state();
      final LedgerEntry forged = await LedgerEntry.sign(joP.key,
          type: EntryType.memberAdd,
          prev: s0.heads,
          issuedAtMs: v.clock.now,
          body: v.fam.memberBody(eveP, electors: <P>[v.mom.p, v.dad.p], name: 'Eve', exp: v.clock.now + 14 * day));
      jo.ctx.entries.add(forged);
      final int momEntries = v.mom.ctx.entries.length;
      await jo.reach(v.mom);
      expect(v.mom.ctx.entries.length, momEntries, reason: 'refused entries are not kept');
      final LedgerState s = await v.mom.state();
      expect(s.pendingFor(forged.hashHex), isNull);
      expect(s.hasPerson(eveP), isFalse);
      expect((await v.mom.welcome().overview()).forMe, isEmpty);
    });

    test('with the asking parent\'s yes and the new person\'s yes only, a second parent is still waited for', () async {
      final Village v = await Village.make();
      final P eveP = await P.make(6);
      final LedgerEntry e = await proposeParent(v, eveP);
      final Phone eve = v.join(eveP);
      await candidateSaysYes(ctx: eve.ctx, repository: eve.repo, invitation: e, nowMs: v.clock.now);
      await eve.reach(v.mom);
      expect((await v.mom.state()).pendingFor(e.hashHex)!.status, 'pending');
      v.clock.now += 15 * day; // nobody else answered: it ends, nothing granted
      final LedgerState s = await v.mom.state();
      expect(s.hasPerson(eveP), isFalse);
      expect(s.pendingFor(e.hashHex)!.status, 'lapsed');
    });

    test('a yes from Dad that arrives after the request ended is carried and ignored', () async {
      final Village v = await Village.make();
      final P eveP = await P.make(6);
      final LedgerEntry e = await proposeParent(v, eveP);
      await v.mom.reach(v.dad);
      final Phone eve = v.join(eveP);
      await candidateSaysYes(ctx: eve.ctx, repository: eve.repo, invitation: e, nowMs: v.clock.now);
      await eve.reach(v.mom);
      final int yesAt = v.clock.now;
      v.clock.now += 15 * day;
      // Dad signs a yes dated after the request ended and it is carried to Mom.
      v.dad.ctx.votes.add(await LedgerVote.sign(v.dad.p.key, target: e.hash, answer: 'yes', atMs: v.clock.now));
      await v.dad.reach(v.mom);
      final LedgerState s = await v.mom.state();
      expect(s.hasPerson(eveP), isFalse);
      expect(s.pendingFor(e.hashHex)!.status, 'lapsed');
      expect(yesAt, lessThan(v.clock.now));
    });
  });
}
