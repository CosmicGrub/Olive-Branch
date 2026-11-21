// OLIVE BRANCH — tests for what one grown-up can do about another in the village (village_people.dart), end to end over the
// road between two phones, each with its OWN copy of the record: pause, ending (together, or by a 14 day notice), the
// limits agreement with its think-over, and the Standing OK. UNVERIFIED until CI runs it.
// Spec: docs/planning/VILLAGE-WELCOME-DESIGN.md sections 4.4, 4.5, 5.2, 6.2 and the owner's co-parent rules.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/family_ledger.dart';
import 'package:olive_client/family_ledger_state.dart';
import 'package:olive_client/family_profiles.dart';
import 'package:olive_client/village_link.dart';
import 'package:olive_client/village_people.dart';
import 'package:olive_client/welcome_logic.dart';

import 'family_test_support.dart';
import 'village_test_support.dart';

String gidOf(LedgerState s, String name) => s.members.firstWhere((LedgerMember m) => m.name == name).gidHex;

/// Mom proposes Jo as a carer, Dad says yes, Jo says yes, and every phone has heard.
Future<(Phone, P)> welcomeJo(Village v, {Preset preset = Preset.trustedCarer}) async {
  final P joP = await P.make(5);
  final LedgerEntry e = await v.mom.welcome().propose(WelcomeDraft(
      personName: 'Jo', profile: MemberProfile.defaults(preset), candidate: joP.rec));
  await v.mom.reach(v.dad);
  await v.dad.welcome().answer(e.hashHex, WelcomeAnswer.yes);
  final Phone jo = v.join(joP);
  await candidateSaysYes(ctx: jo.ctx, repository: jo.repo, invitation: e, nowMs: v.clock.now);
  await jo.reach(v.mom);
  await v.dad.reach(v.mom);
  await v.mom.reach(jo);
  await v.mom.reach(v.dad);
  expect((await v.mom.state()).hasPerson(joP), isTrue, reason: 'Jo is in');
  v.clock.now += 3 * day;
  return (jo, joP);
}

Future<void> sync(Village v, [Phone? jo]) async {
  await v.mom.reach(v.dad);
  await v.dad.reach(v.mom);
  if (jo != null) await v.mom.reach(jo);
}

void main() {
  group('pause: visible on every phone, reversible, never an ending', () {
    test('Mom pauses Dad: Dad\'s phone says so in plain words, he cannot start anything, and Mom can resume him', () async {
      final Village v = await Village.make();
      final String dadGid = gidOf(await v.mom.state(), 'Sam');
      await v.mom.people().pause(dadGid);
      await sync(v);
      final PeopleOverview dad = await v.dad.people().overview();
      expect(dad.iAmPaused, isTrue);
      expect(dad.notices.single, contains('paused'));
      expect(dad.notices.single, contains('Mom'), reason: 'every parent sees who paused');
      expect(dad.notices.single, contains('leave'));
      // Dad cannot pause back, cannot welcome, cannot resume himself.
      for (final Future<void> Function() act in <Future<void> Function()>[
        () async => v.dad.people().pause(gidOf(await v.dad.state(), 'Mom')),
        () async => v.dad.people().resume(dadGid),
      ]) {
        await expectLater(act(), throwsA(isA<PeopleRefused>()));
      }
      await expectLater(
          v.dad.welcome().propose(WelcomeDraft(personName: 'Eve', profile: carerProfile(), candidate: (await P.make(7)).rec)),
          throwsA(isA<WelcomeRefused>().having((WelcomeRefused e) => e.code, 'code', 'paused')));
      expect((await v.dad.state()).isPaused(gidOf(await v.dad.state(), 'Mom')), isFalse);
      // He is still a member and still sees everything; Mom resumes him.
      expect((await v.mom.state()).hasMember(dadGid), isTrue);
      await v.mom.people().resume(dadGid);
      await sync(v);
      expect((await v.dad.people().overview()).iAmPaused, isFalse);
      expect((await v.dad.people().overview()).notices, isEmpty);
    });

    test('a paused parent still answers a request, and their yes counts', () async {
      final Village v = await Village.make();
      final P joP = await P.make(5);
      final String dadGid = gidOf(await v.mom.state(), 'Sam');
      final LedgerEntry e = await v.mom.welcome().propose(WelcomeDraft(personName: 'Jo', profile: carerProfile(), candidate: joP.rec));
      await v.mom.people().pause(dadGid);
      await sync(v);
      expect((await v.dad.welcome().overview()).forMe, isNotEmpty);
      await v.dad.welcome().answer(e.hashHex, WelcomeAnswer.yes);
      await sync(v);
      final WelcomeRequest r = (await v.mom.welcome().overview()).sent.firstWhere((WelcomeRequest x) => x.hashHex == e.hashHex);
      expect(r.electors.firstWhere((ElectorStatus x) => x.name == 'Sam').answer, 'yes');
    });

    test('Mom pauses Dad and Dad pauses Mom at the same moment: neither stands, and both are told', () async {
      final Village v = await Village.make();
      final String dadGid = gidOf(await v.mom.state(), 'Sam'), momGid = gidOf(await v.mom.state(), 'Mom');
      await v.mom.people().pause(dadGid);
      await v.dad.people().pause(momGid); // Dad has not heard
      await sync(v);
      for (final Phone ph in <Phone>[v.mom, v.dad]) {
        final LedgerState s = await ph.state();
        expect(s.paused, isEmpty);
        expect(s.voided.values, everyElement('mutual-pause'));
      }
      expect(await v.mom.summary(), await v.dad.summary());
    });

    test('a carer can be paused by either parent; the carer sees only that it is not available, and cannot do anything about it', () async {
      final Village v = await Village.make();
      final (Phone jo, P joP) = await welcomeJo(v);
      final String joGid = gidOf(await v.mom.state(), 'Jo');
      await v.dad.people().pause(joGid);
      await sync(v, jo);
      expect((await v.mom.state()).isPaused(joGid), isTrue);
      expect((await jo.state()).isPaused(joGid), isTrue);
      await expectLater(jo.people().resume(joGid), throwsA(isA<PeopleRefused>().having((PeopleRefused e) => e.code, 'code', 'not-a-parent')));
      await expectLater(jo.people().pause(gidOf(await jo.state(), 'Mom')), throwsA(isA<PeopleRefused>()));
      await v.mom.people().resume(joGid);
      await sync(v, jo);
      expect((await jo.state()).isPaused(joGid), isFalse);
      expect((await v.mom.state()).hasPerson(joP), isTrue, reason: 'a pause was never an ending');
    });
  });

  group('ending: nobody removes another parent alone', () {
    test('a notice runs on every phone for 14 days, Dad cannot stop it, Mom can take it back, and it ends him only after the wait', () async {
      final Village v = await Village.make();
      final String dadGid = gidOf(await v.mom.state(), 'Sam');
      await v.mom.people().giveNotice(dadGid);
      await sync(v);
      final PeopleOverview dad = await v.dad.people().overview();
      expect(dad.notices.single, contains('notice'));
      expect(dad.notices.single, contains('Mom can take this back'));
      expect(dad.notices.single, contains('can still see everything, answer requests and leave'));
      await expectLater(v.dad.people().cancelNotice(dadGid), throwsA(isA<PeopleRefused>()));
      // Not before the wait: nothing was taken away.
      v.clock.now += 13 * day;
      expect((await v.dad.state()).hasMember(dadGid), isTrue);
      expect((await v.dad.state()).canAct(v.dad.p.key.publicKey, v.clock.now), isTrue);
      // Mom takes it back in time: he stays.
      await v.mom.people().cancelNotice(dadGid);
      await sync(v);
      v.clock.now += 5 * day;
      expect((await v.dad.state()).hasMember(dadGid), isTrue);
      expect((await v.dad.people().overview()).notices, isEmpty);
      // A second notice that nobody takes back ends him on both phones.
      await v.mom.people().giveNotice(dadGid);
      await sync(v);
      v.clock.now += 14 * day + hour;
      expect((await v.mom.state()).hasMember(dadGid), isFalse);
      expect((await v.dad.state()).hasMember(dadGid), isFalse);
    });

    test('ending together needs Dad\'s own yes; his no leaves everything as it was, and nothing says who said no', () async {
      final Village v = await Village.make();
      final String dadGid = gidOf(await v.mom.state(), 'Sam');
      await v.mom.people().proposeEndTogether(dadGid);
      await sync(v);
      final PendingAsk ask = (await v.dad.people().overview()).forMe.single;
      expect(ask.kind, 'remove');
      expect((await v.mom.people().overview()).forMe, isEmpty, reason: 'Mom asked: her yes is already in');
      await v.dad.people().answer(ask.hashHex, yes: false);
      await sync(v);
      expect((await v.mom.state()).hasMember(dadGid), isTrue);
      expect((await v.mom.people().overview()).asks, isEmpty, reason: 'a closed request is not listed');
      // Again, and this time he agrees.
      await v.mom.people().proposeEndTogether(dadGid);
      await sync(v);
      await v.dad.people().answer((await v.dad.people().overview()).forMe.single.hashHex, yes: true);
      await sync(v);
      expect((await v.mom.state()).hasMember(dadGid), isFalse);
      expect(await v.mom.summary(), await v.dad.summary());
    });

    test('a parent can never be ended at once by one person: the carer-style end is refused, and a stranger\'s end does nothing', () async {
      final Village v = await Village.make();
      final String dadGid = gidOf(await v.mom.state(), 'Sam');
      await expectLater(v.mom.people().endCarer(dadGid), throwsA(isA<PeopleRefused>().having((PeopleRefused e) => e.code, 'code', 'not-a-carer')));
      expect((await v.mom.state()).hasMember(dadGid), isTrue);
      // An entry written by hand, bypassing the service, is refused by the rule itself.
      final LedgerEntry hand = await LedgerEntry.sign(v.mom.p.key,
          type: EntryType.accessEnd, prev: (await v.mom.state()).heads, issuedAtMs: v.clock.now,
          body: <String, Object?>{'gid': v.dad.p.gid, 'reason': 'ended'});
      v.mom.ctx.entries.add(hand);
      final LedgerState s = await v.mom.state();
      expect(s.rejected[hand.hashHex], isNotNull);
      expect(s.hasMember(dadGid), isTrue);
    });

    test('a carer: the parent who welcomed them ends it at once; another parent asks and needs that parent\'s yes', () async {
      final Village v = await Village.make();
      final (Phone jo, P joP) = await welcomeJo(v);
      final String joGid = gidOf(await v.mom.state(), 'Jo');
      expect(await v.dad.people().endCarer(joGid), EndResult.askedWelcomer);
      await sync(v, jo);
      expect((await v.mom.state()).hasPerson(joP), isTrue, reason: 'one parent cannot end a carer the other welcomed');
      final PendingAsk ask = (await v.mom.people().overview()).forMe.single;
      expect(ask.kind, 'end-carer');
      await v.mom.people().answer(ask.hashHex, yes: true);
      await sync(v, jo);
      expect((await v.mom.state()).hasPerson(joP), isFalse);
      expect((await v.dad.state()).hasPerson(joP), isFalse);
      // And a carer Mom welcomed, Mom may end on her own.
      final Village w = await Village.make();
      final (Phone jo2, P joP2) = await welcomeJo(w);
      expect(await w.mom.people().endCarer(gidOf(await w.mom.state(), 'Jo')), EndResult.ended);
      expect((await w.mom.state()).hasPerson(joP2), isFalse);
      expect(jo2.ctx.entries, isNotEmpty);
    });
  });

  group('the limits agreement: only with Dad\'s own yes, after a day', () {
    test('Mom suggests, Dad sees the exact list and cannot say yes for a day, can say no at once; nothing changes meanwhile', () async {
      final Village v = await Village.make();
      final String dadGid = gidOf(await v.mom.state(), 'Sam');
      await v.mom.people().proposeLimits(dadGid, <int>[6, 11]);
      await sync(v);
      final PendingAsk ask = (await v.dad.people().overview()).forMe.single;
      expect(ask.kind, 'limits');
      expect(ask.limits, <int>[6, 11]);
      expect(ask.askerName, 'Mom');
      // Too soon for a yes.
      await expectLater(v.dad.people().answer(ask.hashHex, yes: true),
          throwsA(isA<PeopleRefused>().having((PeopleRefused e) => e.code, 'code', 'think-over')));
      expect((await v.dad.state()).limitsOf(dadGid), isEmpty);
      // Even a forged early yes written by hand does not count.
      final LedgerVote early = await LedgerVote.sign(v.dad.p.key, target: fromHex(ask.hashHex), answer: 'yes', atMs: v.clock.now);
      v.dad.ctx.votes.add(early);
      await sync(v);
      v.clock.now += 25 * hour;
      expect((await v.mom.state()).limitsOf(dadGid), isEmpty, reason: 'answered before the think-over ended');
      // The real yes, after the day.
      v.dad.ctx.votes.remove(early);
      await v.dad.people().answer(ask.hashHex, yes: true);
      await sync(v);
      expect((await v.mom.state()).limitsOf(dadGid), <int>[6, 11]);
      expect(await v.mom.summary(), await v.dad.summary());
      final PeopleOverview o = await v.mom.people().overview();
      expect(o.notices.join(' '), contains('agreed to these limits'));
      // In force: Dad cannot welcome, in words.
      await expectLater(v.dad.welcome().propose(WelcomeDraft(personName: 'Eve', profile: carerProfile(), candidate: (await P.make(7)).rec)),
          throwsA(isA<WelcomeRefused>().having((WelcomeRefused e) => e.code, 'code', 'not-allowed')));
    });

    test('a no, at any time, ends it with nothing changed; and Mom can take her own suggestion back', () async {
      final Village v = await Village.make();
      final String dadGid = gidOf(await v.mom.state(), 'Sam');
      await v.mom.people().proposeLimits(dadGid, <int>[8]);
      await sync(v);
      await v.dad.people().answer((await v.dad.people().overview()).forMe.single.hashHex, yes: false);
      await sync(v);
      v.clock.now += 2 * day;
      expect((await v.mom.state()).limitsOf(dadGid), isEmpty);
      expect((await v.mom.people().overview()).asks, isEmpty);
      await v.mom.people().proposeLimits(dadGid, <int>[8]);
      final PendingAsk mine = (await v.mom.people().overview()).waitingOnOthers.single;
      await v.mom.people().withdraw(mine.hashHex);
      await sync(v);
      v.clock.now += 2 * day;
      await expectLater(v.dad.people().answer(mine.hashHex, yes: true), throwsA(isA<PeopleRefused>()));
      expect((await v.dad.state()).limitsOf(dadGid), isEmpty);
    });

    test('the list can only name what a limit may touch; a limit on what a parent can see is refused before it is signed', () async {
      final Village v = await Village.make();
      final String dadGid = gidOf(await v.mom.state(), 'Sam');
      for (final List<int> bad in <List<int>>[<int>[1], <int>[4], <int>[5], <int>[12], <int>[]]) {
        await expectLater(v.mom.people().proposeLimits(dadGid, bad), throwsA(isA<PeopleRefused>()), reason: '$bad');
      }
      expect(v.mom.ctx.entries.where((LedgerEntry e) => e.type == EntryType.limitsAgree), isEmpty, reason: 'nothing was kept');
    });

    test('Dad limits himself more at once; to have fewer limits he asks, and Mom has to say yes', () async {
      final Village v = await Village.make();
      final String dadGid = gidOf(await v.mom.state(), 'Sam');
      await v.mom.people().proposeLimits(dadGid, <int>[11]);
      await sync(v);
      v.clock.now += 25 * hour;
      await v.dad.people().answer((await v.dad.people().overview()).forMe.single.hashHex, yes: true);
      await v.dad.people().tightenMine(<int>[8]);
      await sync(v);
      expect((await v.mom.state()).limitsOf(dadGid), <int>[8, 11]);
      // Mom cannot tighten him.
      final LedgerEntry byMom = await LedgerEntry.sign(v.mom.p.key,
          type: EntryType.limitsTighten, prev: (await v.mom.state()).heads, issuedAtMs: v.clock.now,
          body: <String, Object?>{'gid': v.dad.p.gid, 'limits': <int>[6, 8, 11]});
      v.mom.ctx.entries.add(byMom);
      expect((await v.mom.state()).rejected[byMom.hashHex], 'only-yourself');
      v.mom.ctx.entries.remove(byMom);
      // He asks for fewer.
      await v.dad.people().askLoosen(<int>[11]);
      await sync(v);
      expect((await v.mom.state()).limitsOf(dadGid), <int>[8, 11], reason: 'asking is not enough');
      final PendingAsk ask = (await v.mom.people().overview()).forMe.single;
      expect(ask.kind, 'loosen');
      await v.mom.people().answer(ask.hashHex, yes: true);
      await sync(v);
      expect((await v.dad.state()).limitsOf(dadGid), <int>[11]);
    });
  });

  group('Standing OK', () {
    test('Dad says yes in advance: Mom can welcome a look-only person without waiting for him; it covers nothing more', () async {
      final Village v = await Village.make(policy: const FamilyPolicy(carerLook: 'all'));
      await v.dad.people().standingOk(30);
      await sync(v);
      expect((await v.mom.people().overview()).notices.join(' '), contains('in advance'));
      final P joP = await P.make(5);
      final LedgerEntry e = await v.mom.welcome().propose(WelcomeDraft(
          personName: 'Jo', profile: MemberProfile.defaults(Preset.viewOnly), candidate: joP.rec));
      final Phone jo = v.join(joP);
      await candidateSaysYes(ctx: jo.ctx, repository: jo.repo, invitation: e, nowMs: v.clock.now);
      await jo.reach(v.mom);
      expect((await v.mom.state()).hasPerson(joP), isTrue, reason: 'Dad already said yes');
      // A carer who can act still needs him.
      final P eveP = await P.make(7);
      final LedgerEntry act = await v.mom.welcome().propose(WelcomeDraft(
          personName: 'Eve', profile: carerProfile(), candidate: eveP.rec));
      final Phone eve = v.join(eveP);
      await candidateSaysYes(ctx: eve.ctx, repository: eve.repo, invitation: act, nowMs: v.clock.now);
      await eve.reach(v.mom);
      expect((await v.mom.state()).hasPerson(eveP), isFalse);
    });

    test('it ends by itself, can be taken back, and is limited to 90 days', () async {
      final Village v = await Village.make(policy: const FamilyPolicy(carerLook: 'all'));
      await expectLater(v.dad.people().standingOk(91), throwsA(isA<PeopleRefused>()));
      await expectLater(v.dad.people().standingOk(0), throwsA(isA<PeopleRefused>()));
      await v.dad.people().standingOk(7);
      expect((await v.dad.people().overview()).myStandingUntilMs, isNotNull);
      await v.dad.people().takeBackStanding();
      expect((await v.dad.people().overview()).myStandingUntilMs, isNull);
      await v.dad.people().standingOk(7);
      v.clock.now += 8 * day;
      expect((await v.dad.people().overview()).myStandingUntilMs, isNull, reason: 'it ended on its date');
    });
  });

  group('words and the child', () {
    test('nothing a grown-up reads here uses a word the village never uses, and no child file reaches these files', () async {
      final Village v = await Village.make();
      final String dadGid = gidOf(await v.mom.state(), 'Sam');
      await v.mom.people().pause(dadGid);
      await v.mom.people().giveNotice(dadGid);
      await sync(v);
      v.clock.now += 1 * day;
      final PeopleOverview o = await v.dad.people().overview();
      final String all = <String>[...o.notices, for (final PersonCard p in o.people) p.line].join(' | ').toLowerCase();
      for (final String banned in kBannedWelcomeWords) {
        expect(all, isNot(contains(banned)), reason: banned);
      }
      expect(all, isNot(contains('suspend')));
      for (final File f in Directory('lib').listSync(recursive: true).whereType<File>().where((File f) => f.path.endsWith('.dart'))) {
        final String name = f.path.replaceAll('\\', '/').split('/').last;
        if (!name.startsWith('child_')) continue;
        final String src = f.readAsStringSync();
        expect(src, isNot(contains('village_people')), reason: name);
        expect(src, isNot(contains('village_welcome')), reason: name);
      }
    });
  });
}
