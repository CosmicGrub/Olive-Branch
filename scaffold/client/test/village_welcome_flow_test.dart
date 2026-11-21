// OLIVE BRANCH — widget tests for the village welcome in the guardian app (village_welcome_flow.dart and
// village_welcome_host.dart), driven over an in-memory Wi-Fi with real family records, the real service and the real
// meeting. UNVERIFIED on a device. Spec: docs/planning/VILLAGE-WELCOME-DESIGN.md sections 3 and 12.
// What these prove: nothing runs until a grown-up chooses it; every step asks for the PIN; the meeting and the offer;
// the new person's own yes; sharing between phones; and that a child file never reaches any of it.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/contact_labels.dart' show GrownupKind;
import 'package:olive_client/family_ledger.dart';
import 'package:olive_client/family_profiles.dart';
import 'package:olive_client/family_ledger_state.dart';
import 'package:olive_client/family_state.dart';
import 'package:olive_client/guardian_local_scope.dart';
import 'package:olive_client/guardian_more.dart';
import 'package:olive_client/adults_helpers_screen.dart';
import 'package:olive_client/local_family.dart';
import 'package:olive_client/pairing_protocol.dart' show PairingTransport;
import 'package:olive_client/village_lan.dart' show NearbyVillage;
import 'package:olive_client/village_link.dart';
import 'package:olive_client/village_meet.dart';
import 'package:olive_client/village_welcome_flow.dart';
import 'package:olive_client/village_welcome_host.dart';
import 'package:olive_client/welcome_logic.dart';

import 'family_test_support.dart';
import 'village_test_support.dart';

Future<void> _size(WidgetTester t, {double w = 420, double h = 4000}) async {
  await t.binding.setSurfaceSize(Size(w, h));
  addTearDown(() => t.binding.setSurfaceSize(null));
}

Future<void> _show(WidgetTester t, Widget screen) async {
  await t.pumpWidget(const SizedBox.shrink());
  await t.pumpWidget(MaterialApp(home: screen));
  await t.pump(const Duration(milliseconds: 50));
}

/// Pumps until [f] is on screen (the work behind a tap is a chain of small async steps).
Future<void> _until(WidgetTester t, Finder f, {int max = 400}) async {
  for (int i = 0; i < max && f.evaluate().isEmpty; i++) {
    // The screens do real cryptography, which finishes in real time: let some pass between frames.
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
    await t.pump(const Duration(milliseconds: 25));
  }
  expect(f, findsOneWidget);
}

Future<void> _settle(WidgetTester t, [int n = 12]) async {
  for (int i = 0; i < n; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 15)));
    await t.pump(const Duration(milliseconds: 25));
  }
}

/// Every piece of text on screen, joined, lower-cased.
String _allText(WidgetTester t) => <String>[
      for (final Element e in find.byType(Text).evaluate()) ((e.widget as Text).data ?? '').toLowerCase(),
    ].join(' | ');

void _plainWords(WidgetTester t) {
  final String all = _allText(t);
  for (final String banned in kBannedWelcomeWords) {
    expect(all, isNot(contains(banned)), reason: 'screen text contains "$banned"');
  }
  for (final String tech in <String>['ledger', 'epoch', 'sync', ' key ', 'pake', 'handshake']) {
    expect(all, isNot(contains(tech)), reason: 'a technical word on a grown-up screen: $tech');
  }
  expect(all, isNot(matches(RegExp(r'\b\d+ (times|tries|answers)\b'))));
}

/// A page change finished, without waiting for "no more frames": these screens hold spinners and a polling timer, so
/// pumpAndSettle never settles on them and runs the whole ten minutes of its own clock.
Future<void> _nav(WidgetTester t) async {
  await t.pump();
  await t.pump(const Duration(milliseconds: 500));
}

Future<void> _leave(WidgetTester t) async {
  await t.pumpWidget(const SizedBox.shrink());
  await t.pump(const Duration(seconds: 1));
}

NearbyVillage _first(Air air) => NearbyVillage(handle: air.handles.first, host: 'air', port: 0);

void main() {
  group('Your village, on a phone with no village yet', () {
    testWidgets('opening it only reads: nothing is founded, opened or advertised, and it says what the two choices are', (t) async {
      await _size(t);
      final Air air = Air();
      final AppPhone m = await AppPhone.make(1, air);
      await _show(t, VillageHomeScreen(services: m.services));
      await _until(t, find.byKey(const Key('villageWelcome')));
      expect(find.byKey(const Key('villageJoin')), findsOneWidget);
      expect(air.started, 0, reason: 'no port was opened');
      expect(await m.repo.hasRecord(), isFalse, reason: 'no family was founded');
      expect(m.pinAsked, 0);
      _plainWords(t);
      await _leave(t);
    });

    testWidgets('Welcome someone with a wrong PIN founds nothing and opens nothing', (t) async {
      await _size(t);
      final Air air = Air();
      final AppPhone m = await AppPhone.make(1, air)..pinOk = false;
      await _show(t, VillageHomeScreen(services: m.services));
      await _until(t, find.byKey(const Key('villageWelcome')));
      await t.tap(find.byKey(const Key('villageWelcome')));
      await _settle(t);
      expect(m.pinAsked, 1);
      expect(await m.repo.hasRecord(), isFalse);
      expect(air.started, 0);
      expect(find.byKey(const Key('meetCode')), findsNothing);
      await _leave(t);
    });

    testWidgets('with the PIN right, the family is founded, a code is shown, and leaving closes the road', (t) async {
      await _size(t);
      final Air air = Air();
      final AppPhone m = await AppPhone.make(1, air);
      await _show(t, VillageHomeScreen(services: m.services));
      await _until(t, find.byKey(const Key('villageWelcome')));
      await t.tap(find.byKey(const Key('villageWelcome')));
      await _until(t, find.byKey(const Key('meetCode')));
      expect(RegExp(r'^\d{6}$').hasMatch((t.widget<Text>(find.byKey(const Key('meetCode')))).data!), isTrue);
      expect(await m.repo.hasRecord(), isTrue);
      expect(air.live, 1);
      _plainWords(t);
      await _leave(t);
      expect(air.live, 0, reason: 'the road is stopped when the screen goes');
    });

    testWidgets('the whole welcome of a carer: meet, match, choose, offer, the new person says yes', (t) async {
      await _size(t);
      final Air air = Air();
      final AppPhone m = await AppPhone.make(1, air);
      final P joP = await P.make(5);
      await _show(t, VillageHomeScreen(services: m.services));
      await _until(t, find.byKey(const Key('villageWelcome')));
      await t.tap(find.byKey(const Key('villageWelcome')));
      await _until(t, find.byKey(const Key('meetCode')));
      final String code = (t.widget<Text>(find.byKey(const Key('meetCode')))).data!;
      // Jo's phone types the code.
      final JoinMeeting? meeting = await t.runAsync<JoinMeeting?>(() => VillageJoiner(device: joP.key, agreement: joP.agree, deviceName: 'Jo\'s phone')
          .meet(transport: air.phone().open(_first(air)), handle: air.handles.first, code: code));
      expect(meeting, isNotNull);
      await _until(t, find.byKey(const Key('meetIntroduced')));
      expect(find.textContaining('Jo\'s phone'), findsOneWidget);
      expect((t.widget<Text>(find.byKey(const Key('meetSas')))).data, meeting!.sas.toString());
      _plainWords(t);
      await t.tap(find.byKey(const Key('meetMatch')));
      await _until(t, find.byKey(const Key('welcomeWhoCarer')));
      await t.tap(find.byKey(const Key('welcomeWhoCarer')));
      await _until(t, find.byKey(const Key('welcomeName')));
      await t.enterText(find.byKey(const Key('welcomeName')), 'Jo');
      await t.tap(find.byKey(const Key('welcomeSend')));
      await _until(t, find.byKey(const Key('meetOffered')));
      expect(m.pinAsked, greaterThanOrEqualTo(2), reason: 'starting and sending each asked for the PIN');
      // Jo's phone takes the offer.
      final JoinPoll poll = (await t.runAsync(() => meeting.poll(nowMs: m.clock.now)))!;
      expect(poll.kind, JoinPollKind.offered);
      final FamilyContext ctx = (await m.services.load())!;
      final LedgerEntry req = ctx.entries.firstWhere((LedgerEntry e) => e.type == EntryType.memberAdd);
      expect(req.body['name'], 'Jo');
      // Jo says yes on their own phone and it travels by the door; Mom is the only parent, so that completes it.
      final AppPhone jo = await AppPhone.make(5, Air(), clock: m.clock);
      final LedgerState before = await ctx.state(nowMs: m.clock.now);
      expect(before.members.any((LedgerMember x) => x.name == 'Jo'), isFalse, reason: 'not in until the new person has said yes');
      await t.runAsync(() async {
        final FamilyContext jc = await adoptOfferedRecord(
            device: joP.key, agreement: joP.agree, entries: poll.entries, votes: poll.votes, repository: jo.repo, nowMs: m.clock.now);
        await candidateSaysYes(ctx: jc, repository: jo.repo, invitation: req, nowMs: m.clock.now);
        await jo.services.door(jc).exchange(air.phone().open(_first(air)).send);
      });
      await _settle(t);
      expect(find.byKey(const Key('meetStatus')), findsOneWidget);
      expect(find.textContaining('Jo is welcomed'), findsOneWidget);
      final LedgerState after = await ctx.state(nowMs: m.clock.now);
      expect(after.members.any((LedgerMember x) => x.name == 'Jo' && x.kind == 'carer'), isTrue);
      _plainWords(t);
      await _leave(t);
    });

    testWidgets('pictures that do not match end it: nothing is proposed and nothing is offered', (t) async {
      await _size(t);
      final Air air = Air();
      final AppPhone m = await AppPhone.make(1, air);
      final P joP = await P.make(5);
      await _show(t, VillageHomeScreen(services: m.services));
      await _until(t, find.byKey(const Key('villageWelcome')));
      await t.tap(find.byKey(const Key('villageWelcome')));
      await _until(t, find.byKey(const Key('meetCode')));
      final String code = (t.widget<Text>(find.byKey(const Key('meetCode')))).data!;
      final JoinMeeting meeting = (await t.runAsync<JoinMeeting?>(() => VillageJoiner(device: joP.key, agreement: joP.agree, deviceName: 'x')
          .meet(transport: air.phone().open(_first(air)), handle: air.handles.first, code: code)))!;
      await _until(t, find.byKey(const Key('meetNoMatch')));
      await t.tap(find.byKey(const Key('meetNoMatch')));
      await _until(t, find.byKey(const Key('meetEnded')));
      final FamilyContext ctx = (await m.services.load())!;
      expect(ctx.entries.where((LedgerEntry e) => e.type == EntryType.memberAdd), isEmpty);
      expect((await t.runAsync(() => meeting.poll(nowMs: m.clock.now)))!.kind, JoinPollKind.failed);
      await _leave(t);
    });

    testWidgets('"A helper (no app needed)" opens the helper pages and ends the meeting without adding anyone', (t) async {
      await _size(t);
      final Air air = Air();
      final AppPhone m = await AppPhone.make(1, air);
      final P joP = await P.make(5);
      await _show(t, VillageHomeScreen(services: m.services));
      await _until(t, find.byKey(const Key('villageWelcome')));
      await t.tap(find.byKey(const Key('villageWelcome')));
      await _until(t, find.byKey(const Key('meetCode')));
      final String code = (t.widget<Text>(find.byKey(const Key('meetCode')))).data!;
      await t.runAsync(() => VillageJoiner(device: joP.key, agreement: joP.agree, deviceName: 'x')
          .meet(transport: air.phone().open(_first(air)), handle: air.handles.first, code: code));
      await _until(t, find.byKey(const Key('meetMatch')));
      await t.tap(find.byKey(const Key('meetMatch')));
      await _until(t, find.byKey(const Key('welcomeWhoHelper')));
      await t.tap(find.byKey(const Key('welcomeWhoHelper')));
      await _settle(t);
      expect(m.helpersOpened, 1);
      final FamilyContext ctx = (await m.services.load())!;
      expect(ctx.entries.where((LedgerEntry e) => e.type == EntryType.memberAdd), isEmpty);
      await _leave(t);
    });
  });

  group('the new person\'s phone', () {
    /// A grown-up's phone with a meeting window on the air, ready to be joined.
    Future<(AppPhone, VillageMeetWindow, Village)> hostReady(WidgetTester t, Air air) async {
      final Village v = await Village.make();
      final AppPhone mom = await AppPhone.make(1, air, clock: v.clock);
      final VillageMeetWindow w = VillageMeetWindow.open(code: '246810');
      await air.phone().serve(meet: w, door: v.mom.door);
      return (mom, w, v);
    }

    testWidgets('code, matching pictures, the offer in plain words, a PIN, a yes that is saved and sent', (t) async {
      await _size(t);
      final Air air = Air();
      final (AppPhone _, VillageMeetWindow w, Village v) = await hostReady(t, air);
      final AppPhone jo = await AppPhone.make(5, air, name: 'Jo', clock: v.clock);
      await _show(t, VillageJoinScreen(services: jo.services));
      await _until(t, find.byKey(const Key('joinCode')));
      expect(find.byKey(const Key('joinFind')), findsOneWidget);
      await t.enterText(find.byKey(const Key('joinCode')), '246810');
      await t.pump();
      await t.tap(find.byKey(const Key('joinFind')));
      await _until(t, find.byKey(const Key('joinSas')));
      expect((t.widget<Text>(find.byKey(const Key('joinSas')))).data, w.sas.toString());
      expect(await jo.repo.hasRecord(), isFalse, reason: 'nothing is kept before the person has said yes');
      await t.tap(find.byKey(const Key('joinSame')));
      await _until(t, find.byKey(const Key('joinWaiting')));
      // The grown-up confirms the match, chooses and offers.
      await t.runAsync(() async {
        w.confirmMatch();
        await v.mom.welcome().propose(WelcomeDraft(personName: 'Jo', profile: carerProfile(), candidate: w.intro!.record));
        await w.offer(entries: v.mom.ctx.entries, votes: v.mom.ctx.votes);
      });
      await _until(t, find.byKey(const Key('joinInvitation')));
      expect(find.byKey(const Key('invitationSentence')), findsOneWidget);
      expect(find.textContaining('would like to welcome you'), findsOneWidget);
      expect(find.byKey(const Key('invitationNoPressure')), findsOneWidget);
      expect(find.textContaining('Nothing changes if you do'), findsOneWidget);
      _plainWords(t);
      // A wrong PIN signs nothing.
      jo.pinOk = false;
      await t.tap(find.byKey(const Key('invitationYes')));
      await _settle(t);
      expect(find.byKey(const Key('invitationMessage')), findsOneWidget);
      expect(await jo.repo.hasRecord(), isFalse);
      // The right PIN keeps the record, signs the yes and sends it.
      jo.pinOk = true;
      await t.tap(find.byKey(const Key('invitationYes')));
      await _until(t, find.byKey(const Key('joinSent')));
      expect(await jo.repo.hasRecord(), isTrue);
      expect(v.mom.ctx.votes.any((LedgerVote x) => x.voterHex == jo.p.keyHex && x.answer == 'yes'), isTrue,
          reason: 'the yes reached the grown-up\'s phone');
      _plainWords(t);
      await _leave(t);
    });

    testWidgets('"Not now" keeps nothing on the new phone', (t) async {
      await _size(t);
      final Air air = Air();
      final (AppPhone _, VillageMeetWindow w, Village v) = await hostReady(t, air);
      final AppPhone jo = await AppPhone.make(5, air, name: 'Jo', clock: v.clock);
      await t.pumpWidget(MaterialApp(home: Builder(builder: (BuildContext c) => Scaffold(
          body: TextButton(onPressed: () => Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => VillageJoinScreen(services: jo.services))), child: const Text('open'))))));
      await t.tap(find.text('open'));
      await _nav(t);
      await t.enterText(find.byKey(const Key('joinCode')), '246810');
      await t.pump();
      await t.tap(find.byKey(const Key('joinFind')));
      await _until(t, find.byKey(const Key('joinSame')));
      await t.tap(find.byKey(const Key('joinSame')));
      await t.runAsync(() async {
        w.confirmMatch();
        await v.mom.welcome().propose(WelcomeDraft(personName: 'Jo', profile: carerProfile(), candidate: w.intro!.record));
        await w.offer(entries: v.mom.ctx.entries, votes: v.mom.ctx.votes);
      });
      await _until(t, find.byKey(const Key('invitationNotNow')));
      await t.tap(find.byKey(const Key('invitationNotNow')));
      await _nav(t);
      expect(await jo.repo.hasRecord(), isFalse);
      expect(v.mom.ctx.votes.any((LedgerVote x) => x.voterHex == jo.p.keyHex), isFalse, reason: 'no yes was sent');
      await _leave(t);
    });

    testWidgets('a parent offer with limits says so, says no is fine, and lists every limit', (t) async {
      await _size(t);
      final Air air = Air();
      final (AppPhone _, VillageMeetWindow w, Village v) = await hostReady(t, air);
      final AppPhone jo = await AppPhone.make(5, air, name: 'Jo', clock: v.clock);
      await _show(t, VillageJoinScreen(services: jo.services));
      await t.enterText(find.byKey(const Key('joinCode')), '246810');
      await t.pump();
      await t.tap(find.byKey(const Key('joinFind')));
      await _until(t, find.byKey(const Key('joinSame')));
      await t.tap(find.byKey(const Key('joinSame')));
      await t.runAsync(() async {
        w.confirmMatch();
        await v.mom.welcome().propose(WelcomeDraft(
            personName: 'Jo', profile: MemberProfile.defaults(Preset.parentWithLimits), candidate: w.intro!.record));
        await w.offer(entries: v.mom.ctx.entries, votes: v.mom.ctx.votes);
      });
      await _until(t, find.byKey(const Key('invitationSentence')));
      expect(find.textContaining('with these limits'), findsOneWidget);
      expect(find.textContaining('You can say no. Nothing changes if you do'), findsOneWidget);
      expect(find.byKey(const Key('invitationLine_0')), findsOneWidget);
      _plainWords(t);
      await _leave(t);
    });

    testWidgets('a wrong code is "that did not work" and says nothing about which part', (t) async {
      await _size(t);
      final Air air = Air();
      final (AppPhone _, VillageMeetWindow w, Village v) = await hostReady(t, air);
      final AppPhone jo = await AppPhone.make(5, air, name: 'Jo', clock: v.clock);
      await _show(t, VillageJoinScreen(services: jo.services));
      await t.enterText(find.byKey(const Key('joinCode')), '000000');
      await t.pump();
      await t.tap(find.byKey(const Key('joinFind')));
      await _settle(t, 4);
      await t.pump(const Duration(seconds: 26));
      await _until(t, find.byKey(const Key('joinFailed')));
      expect(find.textContaining('That did not work'), findsOneWidget);
      expect(find.textContaining('wrong'), findsNothing);
      expect(w.intro, isNull);
      await _leave(t);
    });

    testWidgets('a phone that already has a village of its own cannot join another', (t) async {
      await _size(t);
      final Air air = Air();
      final AppPhone jo = await AppPhone.make(5, air, name: 'Jo');
      await t.runAsync(() async => jo.services.found());
      await _show(t, VillageJoinScreen(services: jo.services));
      await _until(t, find.byKey(const Key('joinHasFamily')));
      expect(find.byKey(const Key('joinFind')), findsNothing);
      await _leave(t);
    });
  });

  group('sharing between the grown-ups\' phones', () {
    testWidgets('Dad\'s phone finds Mom\'s, takes the request, and says so in one plain line', (t) async {
      await _size(t);
      final Air air = Air();
      final Village v = await Village.make();
      await air.phone().serve(door: v.mom.door);
      final P joP = await P.make(5);
      await t.runAsync(() => v.mom.welcome().propose(WelcomeDraft(personName: 'Jo', profile: carerProfile(), candidate: joP.rec)));
      final AppPhone dad = await AppPhone.make(2, air, name: 'Sam', repo: v.dad.repo, clock: v.clock);
      await t.runAsync(() => dad.repo.save(v.dad.ctx.snapshot()));
      await _show(t, VillageShareScreen(services: dad.services));
      await _until(t, find.byKey(const Key('shareLine_0')));
      expect(find.textContaining('Updated from Mom'), findsOneWidget);
      final FamilyContext ctx = (await dad.services.load())!;
      expect((await dad.services.welcome(ctx).overview()).forMe.single.personName, 'Jo');
      _plainWords(t);
      await _leave(t);
      expect(air.live, 1, reason: 'only Mom\'s own endpoint is left: Dad\'s stopped with his screen');
    });

    testWidgets('a phone with no village has nothing to share', (t) async {
      await _size(t);
      final Air air = Air();
      final AppPhone m = await AppPhone.make(1, air);
      await _show(t, VillageShareScreen(services: m.services));
      await _until(t, find.byKey(const Key('shareNobody')));
      expect(air.started, 0);
      await _leave(t);
    });
  });

  group('what the home screen says in each state', () {
    testWidgets('a welcomed carer sees that they are welcomed, and nothing a parent sees', (t) async {
      await _size(t);
      final Air air = Air();
      final Village v = await Village.make();
      final P joP = await P.make(5);
      final LedgerEntry e = await v.mom.welcome().propose(WelcomeDraft(personName: 'Jo', profile: carerProfile(), candidate: joP.rec));
      await v.dad.door.absorb(await v.mom.door.outgoing());
      await v.dad.welcome().answer(e.hashHex, WelcomeAnswer.yes);
      final Phone jo = v.join(joP);
      await candidateSaysYes(ctx: jo.ctx, repository: jo.repo, invitation: e, nowMs: v.clock.now);
      await jo.reach(v.mom);
      await v.dad.reach(v.mom);
      await v.mom.reach(jo);
      final AppPhone app = await AppPhone.make(5, air, name: 'Jo', repo: jo.repo, clock: v.clock);
      await t.runAsync(() => app.repo.save(jo.ctx.snapshot()));
      await _show(t, VillageHomeScreen(services: app.services));
      await _until(t, find.byKey(const Key('villageWelcomed')));
      expect(find.byKey(const Key('villageRequests')), findsNothing);
      expect(find.byKey(const Key('villageWelcome')), findsNothing, reason: 'a carer cannot start a welcome');
      _plainWords(t);
      await _leave(t);
    });

    testWidgets('a person with a request waiting sees it in words, and a yes needs the PIN', (t) async {
      await _size(t);
      final Air air = Air();
      final Village v = await Village.make();
      final P joP = await P.make(5);
      final LedgerEntry e = await v.mom.welcome().propose(WelcomeDraft(personName: 'Jo', profile: carerProfile(), candidate: joP.rec));
      final Phone jo = v.join(joP);
      final AppPhone app = await AppPhone.make(5, air, name: 'Jo', repo: jo.repo, clock: v.clock)..pinOk = false;
      await t.runAsync(() => app.repo.save(jo.ctx.snapshot()));
      await _show(t, VillageHomeScreen(services: app.services));
      await _until(t, find.byKey(const Key('villageInvitation')));
      await t.tap(find.byKey(const Key('invitationYes')));
      await _settle(t);
      final FamilyContext ctx = (await app.services.load())!;
      expect(ctx.votes.any((LedgerVote x) => x.voterHex == joP.keyHex), isFalse, reason: 'a wrong PIN signs nothing');
      app.pinOk = true;
      await t.tap(find.byKey(const Key('invitationYes')));
      await _until(t, find.byKey(const Key('invitationSaid')));
      expect(ctx.votes.where((LedgerVote x) => x.voterHex == joP.keyHex).single.targetHex, e.hashHex);
      await _leave(t);
    });

    testWidgets('a record that cannot be read is left alone and said so', (t) async {
      await _size(t);
      final Air air = Air();
      final AppPhone m = await AppPhone.make(1, air, repo: BrokenRepository());
      await _show(t, VillageHomeScreen(services: m.services));
      await _until(t, find.byKey(const Key('villageUnreadable')));
      expect(find.byKey(const Key('villageWelcome')), findsNothing, reason: 'it never starts a new village over an unreadable one');
      await _leave(t);
    });

    testWidgets('a parent sees the three things they can do, and Requests lists what is waiting', (t) async {
      await _size(t);
      final Air air = Air();
      final Village v = await Village.make();
      final P joP = await P.make(5);
      await v.mom.welcome().propose(WelcomeDraft(personName: 'Jo', profile: carerProfile(), candidate: joP.rec));
      await v.dad.door.absorb(await v.mom.door.outgoing());
      final AppPhone dad = await AppPhone.make(2, air, name: 'Sam', repo: v.dad.repo, clock: v.clock);
      await t.runAsync(() => dad.repo.save(v.dad.ctx.snapshot()));
      await _show(t, VillageHomeScreen(services: dad.services));
      await _until(t, find.byKey(const Key('villageRequests')));
      expect(find.byKey(const Key('villageWelcome')), findsOneWidget);
      expect(find.byKey(const Key('villageShare')), findsOneWidget);
      expect(find.byKey(const Key('villageMembers')), findsOneWidget);
      await t.tap(find.byKey(const Key('villageRequests')));
      await _until(t, find.textContaining('would like to welcome Jo'));
      _plainWords(t);
      await _leave(t);
    });
  });

  group('wiring and child safety', () {
    testWidgets('Settings, Adults and helpers shows "Welcome someone" only where this phone has its local services', (t) async {
      await _size(t, w: 800, h: 3000);
      Future<void> toAdults(Widget app) async {
        await t.pumpWidget(const SizedBox.shrink()); // a fresh navigator: the last pass left its pages on it
        await t.pumpWidget(app);
        await _nav(t);
        await t.ensureVisible(find.byKey(const Key('moreSettings')));
        await t.tap(find.byKey(const Key('moreSettings')));
        await _nav(t);
        await t.ensureVisible(find.byKey(const Key('settingsRow_adults')));
        await t.tap(find.byKey(const Key('settingsRow_adults')));
        await _nav(t);
      }

      await toAdults(const MaterialApp(home: GuardianMoreScreen(childName: 'Ivy', childAge: 9)));
      expect(find.byType(AdultsHelpersScreen), findsOneWidget);
      expect(find.byKey(const Key('adultsWelcome')), findsNothing, reason: 'a preview build has no PIN to ask');
      expect(find.byKey(const Key('adultsInvite')), findsOneWidget);

      final GuardianLocalServices services = GuardianLocalServices.memory(pinIterations: 500);
      final GuardianLocalController ctl = GuardianLocalController(services,
          family: const LocalFamily(guardianName: 'Jess', guardianLabel: 'Mom', guardianKind: GrownupKind.mom, childName: 'Ivy', age: 9));
      await toAdults(MaterialApp(
        builder: (BuildContext c, Widget? child) => GuardianLocalScope(controller: ctl, child: child!),
        home: const GuardianMoreScreen(childName: 'Ivy', childAge: 9),
      ));
      expect(find.byKey(const Key('adultsWelcome')), findsOneWidget);
      expect(find.text('Welcome someone'), findsOneWidget);
      expect(find.byKey(const Key('adultsInvite')), findsOneWidget, reason: 'the preview row is unchanged');
      await t.tap(find.byKey(const Key('adultsWelcome')));
      await _nav(t);
      expect(find.byType(VillageHomeScreen), findsOneWidget);
      await _until(t, find.byKey(const Key('villageWelcome')));
      await _leave(t);
    });

    test('no child file imports the village road or screens', () {
      final List<String> bad = <String>[];
      for (final FileSystemEntity f in Directory('lib').listSync()) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final String name = f.uri.pathSegments.last;
        final bool childFile = name.startsWith('child_') || name.startsWith('kiosk_') || name.startsWith('play_') ||
            name.startsWith('game_') || name.startsWith('colour_') || name.startsWith('her_colour_home');
        if (!childFile) continue;
        final String src = f.readAsStringSync();
        for (final String m in <String>[
          'village_welcome_flow', 'village_welcome_host', 'village_link', 'village_meet', 'village_lan', 'welcome_screens', 'welcome_logic',
        ]) {
          if (src.contains("'$m.dart'")) bad.add('$name imports $m');
        }
      }
      expect(bad, isEmpty);
    });

    test('the road is the only place that opens a port for the village, and nothing opens one at start-up', () {
      final String lan = File('lib/village_lan.dart').readAsStringSync();
      expect(RegExp(r'HttpServer\.bind').allMatches(lan).length, 1);
      for (final FileSystemEntity f in Directory('lib').listSync()) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final String name = f.uri.pathSegments.last;
        if (name == 'village_lan.dart') continue;
        final String src = f.readAsStringSync();
        expect(src.contains('VillageLanHost('), name == 'village_welcome_host.dart', reason: name);
      }
      for (final String boot in <String>['main.dart', 'main_live.dart', 'main_live_guardian.dart', 'guardian_boot.dart']) {
        final String src = File('lib/$boot').readAsStringSync();
        expect(src.contains('village_welcome'), isFalse, reason: '$boot must not start the village');
      }
    });
  });
}

/// A family record that is stored but cannot be read.
class BrokenRepository implements FamilyRepository {
  @override
  Future<bool> hasRecord() async => true;
  @override
  Future<FamilySnapshot?> load() async => null;
  @override
  Future<void> save(FamilySnapshot snapshot) async => throw StateError('must not be written');
  @override
  Future<void> clear() async {}
}
