// OLIVE BRANCH — tests for the village welcome service (welcome_logic.dart): the approval rule against the real
// reduce rule, the requests a parent sees, yes / not this time / ask me later / yes to something smaller, and the
// hostile cases (a phone that cannot ask, a double answer, a flood of requests, a forged device, a wrong clock).
// UNVERIFIED until CI runs it. Spec: docs/planning/VILLAGE-WELCOME-DESIGN.md sections 3, 5, 7.3 and 7.9.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/family_ledger.dart';
import 'package:olive_client/family_ledger_state.dart';
import 'package:olive_client/family_profiles.dart';
import 'package:olive_client/family_state.dart' show LocalStoreFamilyRepository;
import 'package:olive_client/local_pin.dart' show kLocalGuardianScope;
import 'package:olive_client/local_services.dart';
import 'package:olive_client/local_store.dart' show LocalNamespace;
import 'package:olive_client/welcome_logic.dart';

import 'family_test_support.dart';
import 'welcome_test_support.dart';

Future<void> expectRefused(Future<Object?> f, String code) async {
  try {
    await f;
    fail('expected the request to be turned down with $code');
  } on WelcomeRefused catch (r) {
    expect(r.code, code);
    expect(r.words.trim(), isNotEmpty);
  }
}

void main() {
  group('the approval rule agrees with the real reduce rule', () {
    final List<FamilyPolicy> policies = <FamilyPolicy>[
      const FamilyPolicy(),
      const FamilyPolicy(carerAct: 'one', carerLook: 'one'),
      const FamilyPolicy(carerAct: 'all', carerLook: 'all'),
    ];
    for (final FamilyPolicy pol in policies) {
      for (final Preset preset in const <Preset>[
        Preset.parent, Preset.parentWithLimits, Preset.trustedCarer, Preset.visit, Preset.viewOnly,
      ]) {
        test('${preset.name} with carerAct=${pol.carerAct} carerLook=${pol.carerLook}', () async {
          final World w = await World.make(policy: pol);
          final MemberProfile prof = preset == Preset.visit ? visit(w.now) : MemberProfile.defaults(preset);
          final WelcomeService s = w.svc(w.mom);
          final LedgerEntry e = await s.propose(w.draft(prof));
          final LedgerState st = await w.state();
          expect(st.rejected.containsKey(e.hashHex), isFalse, reason: 'the reduce rule accepts what the service signs');
          expect(st.pending.where((PendingItem p) => p.hashHex == e.hashHex).single.status, 'pending');
          final ApprovalNeed need = approvalNeed(profile: prof, policy: pol, parentCount: 2);
          final Map<String, Object?> pr = e.body['proposal']! as Map<String, Object?>;
          expect(pr['rule'], need.rule);
          expect((pr['electorate']! as List).length, need.everyParent ? 2 : 1);
          expect(need.lifetimeMs, proposalLifetimeMs(preset));
          expect(pr['exp'], w.now + need.lifetimeMs);
          if (tierOf(preset) == MemberTier.parent) {
            expect(need.rule, 'all', reason: 'a new parent always needs every parent');
            expect(need.hardFloor, isTrue);
          }
        });
      }
    }

    test('the floor holds on the ledger side too: a hand-made parent request with rule one is turned down', () async {
      final World w = await World.make();
      final LedgerEntry bad = await w.fam.add(w.mom, EntryType.memberAdd,
          w.fam.memberBody(w.cand, electors: <P>[w.mom], rule: 'one', exp: w.now + day, name: 'Eve'),
          at: w.now);
      expect((await w.state()).rejected[bad.hashHex], 'rule-below-floor');
    });
  });

  group('asking', () {
    test('two parents: the other parent is asked, the asker is told what is waiting, nothing is in yet', () async {
      final World w = await World.make();
      final LedgerEntry e = await w.svc(w.mom).propose(w.draft(trusted()));
      final WelcomeOverview forDad = await w.svc(w.dad!).overview();
      expect(forDad.forMe.single.hashHex, e.hashHex);
      expect(forDad.forMe.single.personName, 'Jo');
      expect(forDad.forMe.single.askerName, 'Mom');
      final WelcomeOverview forMom = await w.svc(w.mom).overview();
      expect(forMom.forMe, isEmpty, reason: 'the asker is not asked their own question');
      expect(forMom.jo.electors.map((ElectorStatus x) => x.words).toList(),
          <String>['Mom asked', 'Alex has not answered yet']);
      final LedgerState st = await w.state();
      expect(st.members.any((LedgerMember m) => m.name == 'Jo'), isFalse);
      expect(st.holdsAnything(w.cand.key.publicKey), isFalse, reason: 'a pending person holds nothing');
    });

    test('a look-only carer needs one parent: the other is told but not asked', () async {
      final World w = await World.make();
      final LedgerEntry e = await w.svc(w.mom).propose(w.draft(lookOnly()));
      expect((e.body['proposal']! as Map<String, Object?>)['rule'], 'one');
      expect((await w.svc(w.dad!).overview()).forMe, isEmpty);
      expect((await w.svc(w.dad!).overview()).others.single.personName, 'Jo',
          reason: 'every parent is told at once, even when they are not asked');
      await w.candidateAccepts(e);
      expect((await w.state()).members.any((LedgerMember m) => m.name == 'Jo'), isTrue);
    });

    test('a family of one parent: the only parent decides, nothing nags', () async {
      final World w = await World.make(twoParents: false);
      final LedgerEntry e = await w.svc(w.mom).propose(w.draft(MemberProfile.defaults(Preset.parent)));
      expect((e.body['proposal']! as Map<String, Object?>)['electorate'] as List, hasLength(1));
      expect((await w.svc(w.mom).overview()).forMe, isEmpty);
      final ApprovalNeed need = approvalNeed(profile: MemberProfile.defaults(Preset.parent), policy: const FamilyPolicy(), parentCount: 1);
      expect(need.sentences(newParent: true).first, contains('only parent'));
    });

    test('all the parents say yes and the new person says yes: they are in, with a settle-in', () async {
      final World w = await World.make();
      final LedgerEntry e = await w.svc(w.mom).propose(w.draft(trusted()));
      await w.svc(w.dad!).answer(e.hashHex, WelcomeAnswer.yes);
      expect((await w.state()).members.any((LedgerMember m) => m.name == 'Jo'), isFalse, reason: 'the new person has not said yes yet');
      await w.candidateAccepts(e);
      final LedgerState st = await w.state();
      final LedgerMember jo = st.members.singleWhere((LedgerMember m) => m.name == 'Jo');
      expect(jo.kind, 'carer');
      expect(st.isSettling(w.cand.key.publicKey, w.now + 2000), isTrue, reason: 'a carer who can act settles in for 24 hours');
      expect((await w.svc(w.mom).overview()).jo.status, 'welcomed');
    });

    test('silence is never yes: the request ends at its time and a late yes does nothing', () async {
      final World w = await World.make();
      final LedgerEntry e = await w.svc(w.mom).propose(w.draft(trusted()));
      w.now += 8 * day;
      final WelcomeOverview o = await w.svc(w.mom).overview();
      expect(o.jo.status, 'lapsed');
      expect(o.history.last, contains('ended without an answer'));
      await expectRefused(w.svc(w.dad!).answer(e.hashHex, WelcomeAnswer.yes), 'gone');
      await w.fam.vote(w.dad!, e, 'yes', at: w.now);
      await w.candidateAccepts(e);
      expect((await w.state()).members.any((LedgerMember m) => m.name == 'Jo'), isFalse);
    });

    test('a no from a required parent ends it for good, and later yeses change nothing', () async {
      final World w = await World.make();
      final LedgerEntry e = await w.svc(w.mom).propose(w.draft(trusted()));
      await w.svc(w.dad!).answer(e.hashHex, WelcomeAnswer.no);
      final WelcomeRequest r = (await w.svc(w.mom).overview()).jo;
      expect(r.status, 'declined');
      expect(r.electors.last.words, 'Alex said not this time');
      await w.candidateAccepts(e);
      expect((await w.state()).members.any((LedgerMember m) => m.name == 'Jo'), isFalse);
      expect((await w.svc(w.mom).overview()).history, contains('Alex said not this time.'));
    });

    test('the asker can take it back; that ends it', () async {
      final World w = await World.make();
      await w.svc(w.mom).propose(w.draft(trusted()));
      final WelcomeService s = w.svc(w.mom);
      await s.cancel((await s.overview()).jo);
      expect((await s.overview()).jo.status, 'declined');
      await expectRefused(s.cancel((await s.overview()).jo), 'not-yours');
    });

    test('the other parent cannot cancel, and nobody answers their own request', () async {
      final World w = await World.make();
      final LedgerEntry e = await w.svc(w.mom).propose(w.draft(trusted()));
      final WelcomeService d = w.svc(w.dad!);
      await expectRefused(d.cancel((await d.overview()).forMe.single), 'not-yours');
      await expectRefused(w.svc(w.mom).answer(e.hashHex, WelcomeAnswer.yes), 'own-request');
    });

    test('a second answer is refused, an unknown request is refused, later and smaller are not plain answers', () async {
      final World w = await World.make();
      final LedgerEntry e = await w.svc(w.mom).propose(w.draft(trusted()));
      final WelcomeService d = w.svc(w.dad!);
      await d.answer(e.hashHex, WelcomeAnswer.yes);
      await expectRefused(d.answer(e.hashHex, WelcomeAnswer.no), 'answered');
      await expectRefused(d.answer('00' * 32, WelcomeAnswer.yes), 'gone');
      expect(() => d.answer(e.hashHex, WelcomeAnswer.later), throwsArgumentError);
    });

    test('a parent who joined after the request was made is not asked about it', () async {
      final World w = await World.make();
      final LedgerEntry e = await w.svc(w.mom).propose(w.draft(trusted()));
      final P eve = await P.make(7);
      final LedgerEntry add = await w.fam.add(w.mom, EntryType.memberAdd,
          w.fam.memberBody(eve, electors: <P>[w.mom, w.dad!], name: 'Eve', proposalId: Uint8List.fromList(List<int>.filled(16, 3))),
          at: w.now + 10);
      await w.fam.vote(w.dad!, add, 'yes', at: w.now + 20);
      await w.fam.vote(eve, add, 'yes', at: w.now + 30);
      w.now += 4 * day;
      final WelcomeService es = w.svc(eve);
      expect((await es.overview()).forMe, isEmpty);
      await expectRefused(es.answer(e.hashHex, WelcomeAnswer.yes), 'not-asked');
    });
  });

  group('who may ask', () {
    test('a carer, a child device and a stranger cannot start a welcome', () async {
      final World w = await World.make();
      final LedgerEntry e = await w.svc(w.mom).propose(w.draft(lookOnly()));
      await w.candidateAccepts(e);
      final P stranger = await P.make(9);
      await expectRefused(w.svc(w.cand).propose(w.draft(lookOnly(), who: await P.make(6))), 'not-a-parent');
      await expectRefused(w.svc(stranger).propose(w.draft(lookOnly(), who: await P.make(6))), 'not-a-parent');
    });

    test('a parent who is still settling in cannot ask or answer', () async {
      final World w = await World.make();
      w.now = w.fam.clock + hour; // dad was added a minute or so ago
      await expectRefused(w.svc(w.dad!).propose(w.draft(lookOnly())), 'settling');
    });

    test('a limited parent whose "welcome people" switch is off cannot ask, but can still answer', () async {
      final World w = await World.make(twoParents: false);
      final P limited = await P.make(3);
      final MemberProfile lim = MemberProfile.defaults(Preset.parentWithLimits);
      expect(lim.has(Capability.startWelcome), isFalse);
      final LedgerEntry add = await w.fam.add(w.mom, EntryType.memberAdd,
          w.fam.memberBody(limited, electors: <P>[w.mom], name: 'Lee', profile: lim, preset: Preset.parentWithLimits));
      await w.fam.vote(limited, add, 'yes');
      w.now = w.fam.clock + 4 * day;
      await expectRefused(w.svc(limited).propose(w.draft(lookOnly())), 'not-allowed');
      final LedgerEntry e = await w.svc(w.mom).propose(w.draft(trusted()));
      expect((await w.svc(limited).overview()).forMe.single.hashHex, e.hashHex, reason: 'their voice on a carer who can act stays');
      await w.svc(limited).answer(e.hashHex, WelcomeAnswer.yes);
    });

    test('a helper page needs no welcome and cannot be made one', () async {
      final World w = await World.make();
      await expectRefused(w.svc(w.mom).propose(w.draft(MemberProfile.defaults(Preset.helperPage))), 'helper-page');
    });

    test('choices that break the table are turned down in plain words (a carer cannot hold the expenses)', () async {
      final World w = await World.make();
      final MemberProfile bad = MemberProfile(preset: Preset.trustedCarer, caps: <Capability>[...trusted().caps, Capability.expenses]);
      await expectRefused(w.svc(w.mom).propose(w.draft(bad)), 'profile');
      await expectRefused(w.svc(w.mom).propose(w.draft(MemberProfile.defaults(Preset.visit))), 'profile'); // no time box
      await expectRefused(w.svc(w.mom).propose(w.draft(visit(w.now, days: 15))), 'profile');
    });

    test('a phone that did not introduce itself properly, and a phone already in the village, are turned down', () async {
      final World w = await World.make();
      final DeviceRecord forged = DeviceRecord(key: w.cand.key.publicKey, agree: w.dad!.agree.publicKey, cert: w.cand.cert);
      await expectRefused(w.svc(w.mom).propose(WelcomeDraft(personName: 'Jo', profile: lookOnly(), candidate: forged)), 'bad-device');
      await expectRefused(w.svc(w.mom).propose(WelcomeDraft(personName: 'Jo', profile: lookOnly(), candidate: DeviceRecord(key: w.cand.key.publicKey))), 'bad-device');
      await expectRefused(w.svc(w.mom).propose(w.draft(lookOnly(), who: w.dad)), 'already-in');
      await expectRefused(w.svc(w.mom).propose(w.draft(lookOnly(), name: '   ')), 'no-name');
    });

    test('control characters are stripped from a typed name and it is cut to a sane length', () async {
      final World w = await World.make();
      final LedgerEntry e = await w.svc(w.mom).propose(w.draft(lookOnly(), name: '  Jo\u0000\u0007 ${'x' * 80}'));
      expect((e.body['name']! as String).length, lessThanOrEqualTo(40));
      expect(e.body['name'], isNot(contains('\u0000')));
    });
  });

  group('limits on asking', () {
    test('one request at a time; a cancelled one frees the slot; three in 30 days, then a wait', () async {
      final World w = await World.make();
      w.now += 40 * day; // the family's own first welcome, long ago, is outside the 30 days
      final WelcomeService s = w.svc(w.mom);
      final List<P> people = <P>[for (int i = 0; i < 4; i++) await P.make(20 + i)];
      await s.propose(w.draft(trusted(), who: people[0]));
      await expectRefused(s.propose(w.draft(trusted(), who: people[1])), 'one-at-a-time');
      for (int i = 0; i < 2; i++) {
        await s.cancel((await s.overview()).sent.firstWhere((WelcomeRequest r) => r.open));
        w.now += 60000;
        await s.propose(w.draft(trusted(), who: people[i + 1]));
      }
      await s.cancel((await s.overview()).sent.firstWhere((WelcomeRequest r) => r.open));
      w.now += 60000;
      await expectRefused(s.propose(w.draft(trusted(), who: people[3])), 'too-many');
      w.now += 31 * day;
      await s.propose(w.draft(trusted(), who: people[3]));
    });

    test('after a no, the same phone at the same or a wider level waits a week; a smaller ask does not', () async {
      final World w = await World.make();
      w.now += 40 * day;
      final WelcomeService m = w.svc(w.mom);
      final LedgerEntry e = await m.propose(w.draft(trusted()));
      await w.svc(w.dad!).answer(e.hashHex, WelcomeAnswer.no);
      w.now += 60000;
      await expectRefused(m.propose(w.draft(trusted())), 'wait-a-week');
      await expectRefused(m.propose(w.draft(MemberProfile.defaults(Preset.parent))), 'wait-a-week');
      await m.propose(w.draft(lookOnly())); // smaller: allowed at once
      // and after the week, the same level is allowed again
      await m.cancel((await m.overview()).sent.firstWhere((WelcomeRequest r) => r.open));
      w.now += 8 * day;
      await m.propose(w.draft(trusted()));
    });

    test('the cooldown is about the phone, not the typed name', () async {
      final World w = await World.make();
      final WelcomeService m = w.svc(w.mom);
      final LedgerEntry e = await m.propose(w.draft(trusted(), name: 'Jo'));
      await w.svc(w.dad!).answer(e.hashHex, WelcomeAnswer.no);
      w.now += 60000;
      await expectRefused(m.propose(w.draft(trusted(), name: 'Joanna')), 'wait-a-week');
    });
  });

  group('ask me later', () {
    test('signs nothing, tells nobody, and is never a yes', () async {
      final World w = await World.make();
      final LedgerEntry e = await w.svc(w.mom).propose(w.draft(trusted()));
      final int votesBefore = w.fam.votes.length;
      final WelcomeService d = w.svc(w.dad!);
      await d.askLater(e.hashHex);
      expect(w.fam.votes.length, votesBefore);
      expect(w.fam.entries.where((LedgerEntry x) => x.type == EntryType.memberAdd).length, 2);
      final WelcomeRequest asker = (await w.svc(w.mom).overview()).jo;
      expect(asker.electors.last.answer, 'waiting', reason: 'the asker cannot tell it was put off');
      expect(asker.electors.last.words, 'Alex has not answered yet');
      await w.candidateAccepts(e);
      expect((await w.state()).members.any((LedgerMember m) => m.name == 'Jo'), isFalse);
    });

    test('three puts-off at most, each 24 hours; two quiet reminders at most; an answer clears it', () async {
      final World w = await World.make();
      final LedgerEntry e = await w.svc(w.mom).propose(w.draft(trusted()));
      final MemoryWelcomeReminders mem = MemoryWelcomeReminders();
      final WelcomeService d = w.svc(w.dad!, reminders: mem);
      for (int i = 0; i < 3; i++) {
        await d.askLater(e.hashHex);
        expect(await d.isPutOff(e.hashHex), isTrue);
        expect(await d.remindersDue(), isEmpty, reason: 'not before the day is up');
        w.now += kSnoozeMs + 1000;
      }
      await expectRefused(d.askLater(e.hashHex), 'no-more-later');
      expect((await d.remindersDue()).single.hashHex, e.hashHex);
      await d.reminderShown(e.hashHex);
      w.now += kSnoozeMs + 1000;
      expect(await d.remindersDue(), hasLength(1));
      await d.reminderShown(e.hashHex);
      w.now += kSnoozeMs + 1000;
      expect(await d.remindersDue(), isEmpty, reason: 'two reminders, never a third');
      await d.answer(e.hashHex, WelcomeAnswer.no);
      expect((await mem.load()).containsKey(e.hashHex), isFalse);
    });

    test('a damaged or hostile stored record is ignored, not trusted', () {
      expect(AskLater.fromJson(<String, Object?>{'s': 99, 'u': 1, 'r': 0}), isNull);
      expect(AskLater.fromJson(<String, Object?>{'s': 1, 'u': -1, 'r': 0}), isNull);
      expect(AskLater.fromJson(<String, Object?>{'s': 1, 'u': 1, 'r': 5}), isNull);
      expect(AskLater.fromJson('x'), isNull);
      expect(AskLater.fromJson(<String, Object?>{'s': 2, 'u': 5, 'r': 1})!.snoozes, 2);
    });

    test('it is kept in the existing sealed family area and survives a restart', () async {
      final LocalServices svc = LocalServices.memory(isLive: true, demoSeeds: false, childId: 'c1');
      final LocalNamespace ns = svc.area('familyledger', ownerId: kLocalGuardianScope);
      expect(ns.spec.encrypted, isTrue);
      final String h = '0a' * 32;
      await LocalStoreWelcomeReminders(ns).save(<String, AskLater>{h: const AskLater(snoozes: 2, untilMs: 5, reminders: 1)});
      final Map<String, AskLater> back = await LocalStoreWelcomeReminders(ns).load();
      expect(back[h]!.snoozes, 2);
      await ns.put(LocalStoreWelcomeReminders.key, <String, Object?>{'short': <String, Object?>{'s': 1, 'u': 1, 'r': 0}, h: 'junk'});
      expect(await LocalStoreWelcomeReminders(ns).load(), isEmpty);
    });
  });

  group('yes to something smaller', () {
    test('says not this time to the big one and asks every parent about a smaller one, including the first asker', () async {
      final World w = await World.make();
      final LedgerEntry e = await w.svc(w.mom).propose(w.draft(trusted()));
      final WelcomeService d = w.svc(w.dad!);
      final LedgerEntry small = await d.yesToSmaller(e.hashHex, lookOnly());
      final WelcomeOverview mo = await w.svc(w.mom).overview();
      final WelcomeRequest ask = mo.forMe.single;
      expect(ask.hashHex, small.hashHex, reason: 'the first asker has to accept the smaller one');
      expect(ask.askerName, 'Alex');
      expect(ask.profile.preset, Preset.viewOnly);
      expect((small.body['proposal']! as Map<String, Object?>)['rule'], 'all', reason: 'never one parent, whatever the setting');
      expect(mo.jo.status, 'declined');
      await w.svc(w.mom).answer(small.hashHex, WelcomeAnswer.yes);
      await w.candidateAccepts(small);
      final LedgerMember jo = (await w.state()).members.singleWhere((LedgerMember m) => m.name == 'Jo');
      expect(jo.profile!.preset, Preset.viewOnly, reason: 'they are in at the smaller level only');
    });

    test('the same or a wider choice is refused; so is answering something not asked of you', () async {
      final World w = await World.make();
      final LedgerEntry e = await w.svc(w.mom).propose(w.draft(trusted()));
      final WelcomeService d = w.svc(w.dad!);
      await expectRefused(d.yesToSmaller(e.hashHex, trusted()), 'not-smaller');
      await expectRefused(d.yesToSmaller(e.hashHex, MemberProfile.defaults(Preset.parent)), 'not-smaller');
      await expectRefused(w.svc(w.mom).yesToSmaller(e.hashHex, lookOnly()), 'not-yours-to-answer');
      expect((await d.overview()).forMe.single.hashHex, e.hashHex, reason: 'a refused offer left the request as it was');
    });

    test('every offered smaller choice fits the table, is genuinely smaller, and exists for every preset that can shrink', () {
      const int now = 1800000000000;
      for (final Preset p in const <Preset>[Preset.parent, Preset.parentWithLimits, Preset.trustedCarer, Preset.visit]) {
        final MemberProfile big = p == Preset.visit
            ? MemberProfile.defaults(p, fromMs: now, untilMs: now + 7 * day)
            : MemberProfile.defaults(p);
        final List<MapEntry<String, MemberProfile>> opts = smallerChoices(big, now);
        expect(opts, isNotEmpty, reason: p.name);
        for (final MapEntry<String, MemberProfile> o in opts) {
          expect(o.value.violation(), isNull, reason: '${p.name} -> ${o.key}');
          expect(smallerThan(o.value, big), isTrue, reason: '${p.name} -> ${o.key}');
        }
      }
      expect(smallerChoices(lookOnly(), now), isEmpty, reason: 'nothing is smaller than look only');
    });

    test('wider and smaller are about every count: switches, children, and time', () {
      final MemberProfile base = visit(1000, days: 7);
      final MemberProfile shorter = MemberProfile.defaults(Preset.visit, fromMs: 1000, untilMs: 1000 + 2 * day);
      expect(smallerThan(shorter, base), isTrue);
      expect(wider(base, shorter), isTrue);
      final MemberProfile oneKid = MemberProfile(preset: Preset.trustedCarer, caps: trusted().caps, children: <String>['a']);
      expect(smallerThan(oneKid, trusted()), isTrue);
      expect(wider(trusted(), oneKid), isTrue);
      expect(wider(MemberProfile(preset: Preset.trustedCarer, caps: trusted().caps, untilMs: 5000),
          MemberProfile(preset: Preset.trustedCarer, caps: trusted().caps, untilMs: 9000)), isFalse);
      expect(wider(trusted(), MemberProfile(preset: Preset.trustedCarer, caps: trusted().caps, untilMs: 9000)), isTrue,
          reason: 'ongoing is wider than a set end date');
      expect(smallerThan(trusted(), trusted()), isFalse);
    });
  });

  group('words', () {
    test('nothing the service or the screens say about people uses a loaded or technical word', () async {
      final World w = await World.make();
      final WelcomeService m = w.svc(w.mom);
      final LedgerEntry e = await m.propose(w.draft(trusted()));
      await w.svc(w.dad!).answer(e.hashHex, WelcomeAnswer.no);
      final List<String> said = <String>[
        ...(await m.overview()).history,
        for (final Preset p in Preset.values) ...<String>[presetTitle(p), presetBlurb(p, 'Ivy')],
        for (final Capability c in Capability.values) capabilityWords(c, 'Ivy'),
        for (final Reach r in Reach.values) reachLine(r),
        for (final bool np in <bool>[true, false])
          for (final String rule in <String>['all', 'one'])
            ...ApprovalNeed(rule: rule, hardFloor: np, lifetimeMs: 7 * day, settleHours: 24, parentCount: 2).sentences(newParent: np),
        for (final String a in <String>['yes', 'no', 'waiting'])
          ElectorStatus(gidHex: 'x', name: 'Alex', answer: a, isAsker: false).words,
        const ElectorStatus(gidHex: 'x', name: 'Mom', answer: 'yes', isAsker: true).words,
        const ElectorStatus(gidHex: 'x', name: 'Mom', answer: 'no', isAsker: true).words,
      ];
      for (final String line in said) {
        for (final String banned in kBannedWelcomeWords) {
          expect(line.toLowerCase(), isNot(contains(banned)), reason: line);
        }
      }
      // Each refusal's words, too.
      final List<WelcomeRefused> refusals = <WelcomeRefused>[];
      for (final Future<Object?> f in <Future<Object?>>[
        m.propose(w.draft(trusted())),
        m.propose(w.draft(lookOnly(), who: w.dad)),
      ]) {
        try {
          await f;
        } on WelcomeRefused catch (r) {
          refusals.add(r);
        }
      }
      expect(refusals, isNotEmpty);
      for (final WelcomeRefused r in refusals) {
        for (final String banned in kBannedWelcomeWords) {
          expect(r.words.toLowerCase(), isNot(contains(banned)), reason: r.words);
        }
      }
    });

    test('time words say a span or a date, never a number of uses', () {
      expect(timeBoxWords(MemberProfile.defaults(Preset.trustedCarer)), 'Ongoing');
      expect(timeBoxWords(visit(0, days: 3)), 'For 3 days');
      expect(timeBoxWords(MemberProfile(preset: Preset.trustedCarer, caps: trusted().caps, untilMs: 1800000000000)), startsWith('Until '));
      expect(daysWords(day), '1 day');
    });

    test('the checklist lists every switch that exists for the kind of person, on and off', () {
      final List<ChecklistLine> l = checklistFor(trusted(), 'Ivy');
      expect(l.length, 13, reason: 'a carer sees all thirteen switches, on or off (the Helper page has none)');
      expect(l.where((ChecklistLine x) => x.words.contains('expenses')).single.on, isFalse);
      expect(l.where((ChecklistLine x) => x.words.contains('Ivy’s tablet')).single.on, isTrue);
      expect(checklistFor(MemberProfile.defaults(Preset.helperPage), 'Ivy'), isEmpty);
    });
  });

  group('the child never reaches any of this', () {
    test('no file other than the welcome screens imports the welcome files, and no child file does', () {
      final List<File> libs = Directory('lib').listSync(recursive: true).whereType<File>().where((File f) => f.path.endsWith('.dart')).toList();
      final Set<String> importers = <String>{};
      for (final File f in libs) {
        final String src = f.readAsStringSync();
        if (src.contains("'welcome_logic.dart'") || src.contains("'welcome_screens.dart'") || src.contains('/welcome_logic.dart') || src.contains('/welcome_screens.dart')) {
          importers.add(f.path.replaceAll('\\', '/').split('/').last);
        }
      }
      expect(importers, <String>{'welcome_screens.dart'}, reason: 'only the welcome screens import the welcome logic; nothing else yet');
      for (final String name in importers) {
        expect(name.startsWith('child_'), isFalse);
      }
    });

    test('the welcome files do not import any child screen or child store', () {
      for (final String f in <String>['lib/welcome_logic.dart', 'lib/welcome_screens.dart']) {
        final String src = File(f).readAsStringSync();
        for (final Match m in RegExp(r"import '([a-z0-9_/.]+)'").allMatches(src)) {
          expect(m.group(1)!.startsWith('child_'), isFalse, reason: '$f imports ${m.group(1)}');
        }
      }
    });
  });

  group('review fixes: the wait after a no, a failed save, true wording, seeing, and tidy put-offs', () {
    test('a time-boxed ask repeated after a no still waits a week, and so does one moved later', () async {
      final World w = await World.make();
      w.now += 40 * day;
      final WelcomeService m = w.svc(w.mom);
      final LedgerEntry e = await m.propose(w.draft(visit(w.now)));
      await w.svc(w.dad!).answer(e.hashHex, WelcomeAnswer.no);
      w.now += 60000;
      await expectRefused(m.propose(w.draft(visit(w.now))), 'wait-a-week'); // identical 3 day visit, a minute later
      await expectRefused(m.propose(w.draft(visit(w.now + day))), 'wait-a-week'); // the same window moved later
      await expectRefused(m.propose(w.draft(visit(w.now, days: 7))), 'wait-a-week'); // longer
      await m.propose(w.draft(visit(w.now, days: 1))); // genuinely shorter is allowed at once
    });

    test('a carer with a set number of days, asked again after a no, waits; fewer days does not', () async {
      final World w = await World.make();
      w.now += 40 * day;
      final WelcomeService m = w.svc(w.mom);
      MemberProfile days(int n) =>
          MemberProfile(preset: Preset.trustedCarer, caps: trusted().caps, fromMs: w.now, untilMs: w.now + n * day);
      final LedgerEntry e = await m.propose(w.draft(days(30)));
      await w.svc(w.dad!).answer(e.hashHex, WelcomeAnswer.no);
      w.now += 60000;
      await expectRefused(m.propose(w.draft(days(30))), 'wait-a-week');
      await m.propose(w.draft(days(7)));
    });

    test('smaller means it gives less: the same rights with only the dates moved are not smaller', () {
      final MemberProfile a = visit(1000), later = visit(1000 + 60000), shifted = visit(1000 + day);
      expect(smallerThan(later, a), isFalse);
      expect(smallerThan(shifted, a), isFalse);
      expect(smallerThan(a, a), isFalse);
      expect(wider(later, a), isTrue, reason: 'a later end date is more time');
      expect(smallerThan(visit(1000, days: 1), a), isTrue);
      expect(smallerThan(lookOnly(), trusted()), isTrue);
    });

    test('yes to something smaller refuses a choice that grants the same rights on other dates', () async {
      final World w = await World.make();
      final LedgerEntry e = await w.svc(w.mom).propose(w.draft(visit(w.now)));
      w.now += 60000;
      await expectRefused(w.svc(w.dad!).yesToSmaller(e.hashHex, visit(w.now)), 'not-smaller');
    });

    group('a failed save leaves nothing half-done', () {
      test('asking', () async {
        final World w = await World.make();
        final FlakyFamilyRepository repo = FlakyFamilyRepository();
        final WelcomeService s = w.svc(w.mom, repository: repo);
        final int e0 = w.fam.entries.length, v0 = w.fam.votes.length;
        repo.failSaves = true;
        await expectRefused(s.propose(w.draft(trusted())), 'not-saved');
        expect(w.fam.entries.length, e0);
        expect(w.fam.votes.length, v0);
        repo.failSaves = false;
        await s.propose(w.draft(trusted())); // and it works once the disk does
      });

      test('answering and cancelling', () async {
        final World w = await World.make();
        final LedgerEntry e = await w.svc(w.mom).propose(w.draft(trusted()));
        final FlakyFamilyRepository repo = FlakyFamilyRepository();
        final WelcomeService d = w.svc(w.dad!, repository: repo);
        final int e0 = w.fam.entries.length, v0 = w.fam.votes.length;
        repo.failSaves = true;
        await expectRefused(d.answer(e.hashHex, WelcomeAnswer.yes), 'not-saved');
        expect(w.fam.entries.length, e0);
        expect(w.fam.votes.length, v0);
        expect((await d.overview()).forMe.single.myAnswer, isNull, reason: 'still waiting for this parent');
        final FlakyFamilyRepository repo2 = FlakyFamilyRepository()..failSaves = true;
        final WelcomeService m = w.svc(w.mom, repository: repo2);
        await expectRefused(m.cancel((await m.overview()).jo), 'not-saved');
        expect(w.fam.votes.length, v0);
        expect((await m.overview()).jo.open, isTrue);
      });

      test('yes to something smaller leaves one road, not two', () async {
        final World w = await World.make();
        final LedgerEntry e = await w.svc(w.mom).propose(w.draft(trusted()));
        final FlakyFamilyRepository repo = FlakyFamilyRepository();
        final WelcomeService d = w.svc(w.dad!, repository: repo);
        final int e0 = w.fam.entries.length, v0 = w.fam.votes.length;
        repo.failSaves = true;
        await expectRefused(d.yesToSmaller(e.hashHex, lookOnly()), 'not-saved');
        expect(w.fam.entries.length, e0, reason: 'no orphan smaller request');
        expect(w.fam.votes.length, v0, reason: 'no stray no');
        final WelcomeOverview o = await w.svc(w.mom).overview();
        expect(o.sent.where((WelcomeRequest r) => r.personName == 'Jo' && r.open).length, 1, reason: 'only the first request');
        expect((await d.overview()).forMe.single.hashHex, e.hashHex);
        // A later good save does not write an orphan.
        repo.failSaves = false;
        await d.answer(e.hashHex, WelcomeAnswer.yes);
        expect(w.fam.entries.length, e0);
      });

      test('a put-off that cannot be saved is said in words; an answer stands even if tidying the put-off fails', () async {
        final World w = await World.make();
        final LedgerEntry e = await w.svc(w.mom).propose(w.draft(trusted()));
        final MemoryWelcomeReminders mem = MemoryWelcomeReminders();
        final WelcomeService d = w.svc(w.dad!, reminders: mem);
        await d.askLater(e.hashHex);
        mem.failSaves = true;
        await expectRefused(d.askLater(e.hashHex), 'not-saved');
        await d.answer(e.hashHex, WelcomeAnswer.yes);
        expect((await w.svc(w.mom).overview()).jo.electors.last.answer, 'yes');
      });
    });

    test('the one-parent line says only what is built: no pause and no right-away notice', () {
      for (final bool np in <bool>[true, false]) {
        for (final String rule in <String>['all', 'one']) {
          for (final int n in <int>[1, 2]) {
            final String all = ApprovalNeed(rule: rule, hardFloor: np, lifetimeMs: 7 * day, settleHours: 24, parentCount: n)
                .sentences(newParent: np)
                .join(' ')
                .toLowerCase();
            expect(all.contains('pause'), isFalse);
            expect(all.contains('told right away'), isFalse);
          }
        }
      }
      expect(
          const ApprovalNeed(rule: 'one', hardFloor: false, lifetimeMs: 7 * day, settleHours: 24, parentCount: 2)
              .sentences(newParent: false)
              .first,
          'Your yes is enough. The other parents will see this on their Your village page.');
    });

    test('a parent with limits keeps the switches that let them see; the service turns the rest down', () async {
      final World w = await World.make();
      final MemberProfile hidden = MemberProfile(
          preset: Preset.parentWithLimits,
          caps: MemberProfile.defaults(Preset.parentWithLimits).caps.where((Capability c) => !kSeeingCaps.contains(c)));
      expect(hidesFromParent(hidden), isTrue);
      expect(hidesFromParent(MemberProfile.defaults(Preset.parentWithLimits)), isFalse);
      expect(hidesFromParent(trusted()), isFalse);
      await expectRefused(w.svc(w.mom).propose(w.draft(hidden)), 'hides-from-parent');
      // Doing can still be limited.
      final MemberProfile noPairing = MemberProfile(
          preset: Preset.parentWithLimits,
          caps: MemberProfile.defaults(Preset.parentWithLimits).caps.where((Capability c) => c != Capability.connectDevice));
      await w.svc(w.mom).propose(w.draft(noPairing));
      // No smaller choice offered for a parent takes seeing away.
      for (final MapEntry<String, MemberProfile> o in smallerChoices(MemberProfile.defaults(Preset.parentWithLimits), w.now)) {
        expect(hidesFromParent(o.value), isFalse, reason: o.key);
      }
    });

    test('put-offs are tidied: refused for a request that is not waiting on me, pruned when it ends', () async {
      final World w = await World.make();
      final LedgerEntry e = await w.svc(w.mom).propose(w.draft(trusted()));
      final MemoryWelcomeReminders mem = MemoryWelcomeReminders();
      final WelcomeService m = w.svc(w.mom, reminders: mem);
      await expectRefused(m.askLater(e.hashHex), 'not-yours-to-answer'); // my own request
      await expectRefused(m.askLater('ab' * 32), 'not-yours-to-answer'); // unknown request
      final WelcomeService d = w.svc(w.dad!, reminders: mem);
      await d.askLater(e.hashHex);
      expect(mem.snapshot.keys.toList(), <String>[e.hashHex]);
      await m.cancel((await m.overview()).jo);
      expect(await d.remindersDue(), isEmpty);
      expect(await mem.load(), isEmpty, reason: 'the request ended, so its put-off is dropped');
      await expectRefused(d.askLater(e.hashHex), 'not-yours-to-answer'); // already ended
      // A record for a request that never existed is dropped on load.
      await mem.save(<String, AskLater>{'cd' * 32: const AskLater(snoozes: 1, untilMs: 1)});
      await d.remindersDue();
      expect(await mem.load(), isEmpty);
    });

    test('clearing the family record also clears the put-offs kept beside it', () async {
      final LocalServices svc = LocalServices.memory(isLive: true, demoSeeds: false, childId: 'c1');
      final LocalNamespace ns = svc.area('familyledger', ownerId: kLocalGuardianScope);
      expect(LocalStoreWelcomeReminders.key, 'welcomeasks');
      await LocalStoreWelcomeReminders(ns).save(<String, AskLater>{'0a' * 32: const AskLater(snoozes: 1, untilMs: 5)});
      await ns.put('family', <String, Object?>{'x': 1});
      await LocalStoreFamilyRepository(ns).clear();
      expect(await ns.get('family'), isNull);
      expect(await LocalStoreWelcomeReminders(ns).load(), isEmpty);
    });
  });
}
