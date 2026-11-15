// OLIVE BRANCH — widget tests for the village welcome screens (welcome_screens.dart), on a real family ledger and
// the real service. UNVERIFIED until CI runs it. Spec: docs/planning/VILLAGE-WELCOME-DESIGN.md sections 3, 5 and 12.
// Every yes, every request and every cancel asks for the PIN first; a wrong PIN changes nothing.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/adults_helpers_screen.dart';
import 'package:olive_client/family_ledger.dart';
import 'package:olive_client/family_profiles.dart';
import 'package:olive_client/welcome_logic.dart';
import 'package:olive_client/welcome_screens.dart';

import 'family_test_support.dart';
import 'welcome_test_support.dart';

Future<void> _size(WidgetTester t, {double w = 420, double h = 4000}) async {
  await t.binding.setSurfaceSize(Size(w, h));
  addTearDown(() => t.binding.setSurfaceSize(null));
}

Future<void> _show(WidgetTester t, Widget screen) async {
  await t.pumpWidget(const SizedBox.shrink());
  await t.pumpWidget(MaterialApp(home: screen));
  await t.pump(const Duration(milliseconds: 50));
}

/// Every piece of text on screen, joined, lower-cased.
String _allText(WidgetTester t) => <String>[
      for (final Element e in find.byType(Text).evaluate()) ((e.widget as Text).data ?? '').toLowerCase(),
    ].join(' | ');

void _noLoadedWords(WidgetTester t) {
  final String all = _allText(t);
  for (final String banned in kBannedWelcomeWords) {
    expect(all, isNot(contains(banned)), reason: 'screen text contains "$banned"');
  }
  expect(all, isNot(matches(RegExp(r'\b\d+ (times|tries|answers)\b'))), reason: 'no counts of how often');
}

void main() {
  group('Who is it?', () {
    testWidgets('three choices in plain words, each one goes where it says', (t) async {
      await _size(t);
      final List<String> hit = <String>[];
      await _show(t, WelcomeWhoScreen(childName: 'Ivy', onParent: () => hit.add('p'), onCarer: () => hit.add('c'), onHelper: () => hit.add('h')));
      expect(find.text('Another parent'), findsOneWidget);
      expect(find.text('A carer'), findsOneWidget);
      expect(find.text('A helper (no app needed)'), findsOneWidget);
      for (final String k in <String>['welcomeWhoParent', 'welcomeWhoCarer', 'welcomeWhoHelper']) {
        await t.tap(find.byKey(Key(k)));
      }
      expect(hit, <String>['p', 'c', 'h']);
      _noLoadedWords(t);
    });
  });

  group('How much can they do?', () {
    Future<List<WelcomeChoices>> open(WidgetTester t, World w, {bool parent = false, bool pinOk = true}) async {
      final List<WelcomeChoices> got = <WelcomeChoices>[];
      await _show(
          t,
          WelcomeProfileScreen(
            childName: 'Ivy',
            parentTier: parent,
            policy: const FamilyPolicy(),
            parentCount: 2,
            children: const <WelcomeChild>[WelcomeChild('c1', 'Ivy'), WelcomeChild('c2', 'Ben')],
            nowMs: () => w.now,
            confirmPin: () async => pinOk,
            onChosen: (WelcomeChoices c) async => got.add(c),
          ));
      return got;
    }

    testWidgets('a carer: pick a visit, name them, send; the profile sent is the one shown', (t) async {
      await _size(t);
      final World w = await World.make();
      final List<WelcomeChoices> got = await open(t, w);
      await t.enterText(find.byKey(const Key('welcomeName')), 'Nana');
      await t.tap(find.byKey(const Key('welcomePreset_visit')));
      await t.pump();
      await t.tap(find.byKey(const Key('welcomeVisit_7')));
      await t.pump();
      expect(find.text('Can help'), findsOneWidget);
      await t.tap(find.byKey(const Key('welcomeSend')));
      await t.pump();
      expect(got.single.personName, 'Nana');
      expect(got.single.profile.preset, Preset.visit);
      expect(got.single.profile.untilMs! - got.single.profile.fromMs!, 7 * day);
      expect(got.single.profile.violation(), isNull);
      _noLoadedWords(t);
    });

    testWidgets('a wrong PIN sends nothing and says so', (t) async {
      await _size(t);
      final World w = await World.make();
      final List<WelcomeChoices> got = await open(t, w, pinOk: false);
      await t.enterText(find.byKey(const Key('welcomeName')), 'Nana');
      await t.tap(find.byKey(const Key('welcomeSend')));
      await t.pump();
      expect(got, isEmpty);
      expect(find.textContaining('did not match, so nothing was sent'), findsOneWidget);
    });

    testWidgets('no name, no children chosen: it says what is missing and sends nothing', (t) async {
      await _size(t);
      final World w = await World.make();
      final List<WelcomeChoices> got = await open(t, w);
      await t.tap(find.byKey(const Key('welcomeSend')));
      await t.pump();
      expect(find.textContaining('type the person’s name'), findsOneWidget);
      await t.enterText(find.byKey(const Key('welcomeName')), 'Nana');
      await t.tap(find.byKey(const Key('welcomeAllChildren')));
      await t.pump();
      await t.tap(find.byKey(const Key('welcomeSend')));
      await t.pump();
      expect(find.textContaining('do not fit together'), findsOneWidget);
      expect(got, isEmpty);
      await t.tap(find.byKey(const Key('welcomeChild_c2')));
      await t.pump();
      await t.tap(find.byKey(const Key('welcomeSend')));
      await t.pump();
      expect(got.single.profile.children, <String>['c2']);
    });

    testWidgets('the reach line follows the switches; a fixed switch cannot be flipped', (t) async {
      await _size(t);
      final World w = await World.make();
      final List<WelcomeChoices> got = await open(t, w);
      await t.tap(find.byKey(const Key('welcomePreset_viewOnly')));
      await t.pump();
      expect(find.text('Can look only'), findsOneWidget);
      await t.tap(find.byKey(const Key('welcomePreset_trustedCarer')));
      await t.pump();
      expect(find.text('Can help'), findsOneWidget);
      for (final int n in <int>[4, 9, 10]) {
        await t.tap(find.byKey(Key('welcomeCap_$n')));
        await t.pump();
      }
      expect(find.text('Can look only'), findsOneWidget);
      // C5 (expenses) is fixed off for a carer: tapping its row changes nothing.
      await t.tap(find.byKey(const Key('welcomeCap_5')));
      await t.pump();
      await t.enterText(find.byKey(const Key('welcomeName')), 'Nana');
      await t.tap(find.byKey(const Key('welcomeSend')));
      await t.pump();
      expect(got.single.profile.has(Capability.expenses), isFalse);
      expect(got.single.profile.violation(), isNull);
    });

    testWidgets('another parent: every parent has to say yes, said as a fixed fact; with limits is a second choice', (t) async {
      await _size(t);
      final World w = await World.make();
      final List<WelcomeChoices> got = await open(t, w, parent: true);
      expect(find.textContaining('Every parent has to say yes. This is always so'), findsOneWidget);
      expect(find.byKey(const Key('welcomeAllChildren')), findsNothing, reason: 'a parent is around all the children');
      await t.tap(find.byKey(const Key('welcomePreset_parentWithLimits')));
      await t.pump();
      // Care notes and expenses let a parent see, so they cannot be switched off; pairing a tablet (doing) can.
      await t.tap(find.byKey(const Key('welcomeCap_4')));
      await t.tap(find.byKey(const Key('welcomeCap_5')));
      await t.tap(find.byKey(const Key('welcomeCap_8')));
      await t.pump();
      await t.enterText(find.byKey(const Key('welcomeName')), 'Lee');
      await t.tap(find.byKey(const Key('welcomeSend')));
      await t.pump();
      expect(got.single.profile.preset, Preset.parentWithLimits);
      expect(got.single.profile.has(Capability.careNotes), isTrue, reason: 'a limit never hides what a parent sees');
      expect(got.single.profile.has(Capability.expenses), isTrue);
      expect(got.single.profile.has(Capability.connectDevice), isFalse, reason: 'doing can be limited');
      expect(hidesFromParent(got.single.profile), isFalse);
      expect(find.text('A parent can always see this, so it stays on'), findsNWidgets(2));
      expect(got.single.profile.has(Capability.voteWelcome), isTrue, reason: 'a limited parent keeps their voice');
      _noLoadedWords(t);
    });
  });

  group('Your village and the request', () {
    Future<void> openCentre(WidgetTester t, World w, P who, {bool Function()? pin, List<WelcomeRequest>? opened}) async {
      await _show(
          t,
          WelcomeCentreScreen(
            service: w.svc(who),
            childName: 'Ivy',
            confirmPin: () async => pin == null ? true : pin(),
            onWelcomeSomeone: () {},
            onOpenRequest: (WelcomeRequest r) => opened?.add(r),
          ));
      await t.pump(const Duration(milliseconds: 100));
    }

    testWidgets('the asker sees who has answered in plain words and can cancel (PIN first)', (t) async {
      await _size(t);
      final World w = await World.make();
      await w.svc(w.mom).propose(w.draft(trusted()));
      bool ok = false;
      await openCentre(t, w, w.mom, pin: () => ok);
      expect(find.textContaining('Alex has not answered yet'), findsOneWidget);
      expect(find.textContaining('Ends on'), findsOneWidget);
      expect(find.text('Waiting for your answer'), findsNothing);
      _noLoadedWords(t);
      await t.tap(find.textContaining('Cancel this request'));
      await t.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('did not match'), findsOneWidget);
      expect((await w.svc(w.mom).overview()).jo.open, isTrue, reason: 'a wrong PIN cancelled nothing');
      ok = true;
      await t.tap(find.textContaining('Cancel this request'));
      await t.pump(const Duration(milliseconds: 100));
      expect((await w.svc(w.mom).overview()).jo.status, 'declined');
      expect(find.textContaining('Not set up this time'), findsWidgets);
    });

    testWidgets('the other parent sees a request waiting for them and opens it', (t) async {
      await _size(t);
      final World w = await World.make();
      await w.svc(w.mom).propose(w.draft(trusted()));
      final List<WelcomeRequest> opened = <WelcomeRequest>[];
      await openCentre(t, w, w.dad!, opened: opened);
      expect(find.text('Waiting for your answer'), findsOneWidget);
      expect(find.textContaining('Mom would like to welcome Jo'), findsOneWidget);
      await t.tap(find.textContaining('Mom would like to welcome Jo'));
      expect(opened.single.personName, 'Jo');
    });

    Future<WelcomeService> openRequest(WidgetTester t, World w, {bool pinOk = true, void Function(WelcomeAnswer)? done}) async {
      await w.svc(w.mom).propose(w.draft(trusted()));
      final WelcomeService d = w.svc(w.dad!);
      final WelcomeRequest r = (await d.overview()).forMe.single;
      await _show(
          t,
          WelcomeRequestScreen(
              service: d, request: r, childName: 'Ivy', confirmPin: () async => pinOk, onDone: (WelcomeAnswer a) => done?.call(a)));
      return d;
    }

    testWidgets('the request says who, what, for how long and when it ends; four ways to answer', (t) async {
      await _size(t);
      final World w = await World.make();
      await openRequest(t, w);
      expect(find.textContaining('Mom asked to welcome Jo as a carer for Ivy'), findsOneWidget);
      expect(find.text('Jo'), findsOneWidget);
      expect(find.text('Ongoing'), findsOneWidget);
      expect(find.textContaining('Unlock Ivy’s tablet'), findsOneWidget);
      expect(find.textContaining('Alex has not answered yet'), findsOneWidget);
      for (final String k in <String>['welcomeYes', 'welcomeNo', 'welcomeLater', 'welcomeSmaller']) {
        expect(find.byKey(Key(k)), findsOneWidget);
      }
      expect(find.text('Not this time'), findsOneWidget);
      _noLoadedWords(t);
    });

    testWidgets('yes needs the PIN: a wrong one records nothing, a right one records a signed yes', (t) async {
      await _size(t);
      final World w = await World.make();
      final List<WelcomeAnswer> done = <WelcomeAnswer>[];
      await openRequest(t, w, pinOk: false, done: done.add);
      final int votes = w.fam.votes.length;
      await t.tap(find.byKey(const Key('welcomeYes')));
      await t.pump(const Duration(milliseconds: 100));
      expect(w.fam.votes.length, votes);
      expect(done, isEmpty);
      expect(find.textContaining('did not match, so nothing was sent'), findsOneWidget);

      final World w2 = await World.make();
      final List<WelcomeAnswer> done2 = <WelcomeAnswer>[];
      await openRequest(t, w2, done: done2.add);
      final int before = w2.fam.votes.length;
      await t.tap(find.byKey(const Key('welcomeYes')));
      await t.pump(const Duration(milliseconds: 100));
      expect(done2, <WelcomeAnswer>[WelcomeAnswer.yes]);
      expect(w2.fam.votes.length, before + 1);
      expect((await w2.svc(w2.mom).overview()).jo.electors.last.words, 'Alex said yes');
    });

    testWidgets('ask me later records nothing in the ledger and needs no PIN; not this time records a no', (t) async {
      await _size(t);
      final World w = await World.make();
      final List<WelcomeAnswer> done = <WelcomeAnswer>[];
      final WelcomeService d = await openRequest(t, w, pinOk: false, done: done.add);
      final int before = w.fam.votes.length;
      await t.tap(find.byKey(const Key('welcomeLater')));
      await t.pump(const Duration(milliseconds: 100));
      expect(done, <WelcomeAnswer>[WelcomeAnswer.later]);
      expect(w.fam.votes.length, before, reason: 'ask me later signs nothing');
      expect(await d.isPutOff((await d.overview()).forMe.single.hashHex), isTrue);

      final World w2 = await World.make();
      final List<WelcomeAnswer> done2 = <WelcomeAnswer>[];
      await openRequest(t, w2, done: done2.add);
      await t.tap(find.byKey(const Key('welcomeNo')));
      await t.pump(const Duration(milliseconds: 100));
      expect(done2, <WelcomeAnswer>[WelcomeAnswer.no]);
      expect((await w2.svc(w2.mom).overview()).jo.status, 'declined');
    });

    testWidgets('yes to something smaller lists only smaller choices and asks the first asker about the one you pick', (t) async {
      await _size(t);
      final World w = await World.make();
      final List<WelcomeAnswer> done = <WelcomeAnswer>[];
      await openRequest(t, w, done: done.add);
      await t.tap(find.byKey(const Key('welcomeSmaller')));
      await t.pump();
      expect(find.byKey(const Key('welcomeYes')), findsNothing);
      expect(find.text('Look only'), findsOneWidget);
      await t.tap(find.byKey(const Key('welcomeSmallerChoice_0')));
      await t.pump(const Duration(milliseconds: 100));
      expect(done, <WelcomeAnswer>[WelcomeAnswer.smaller]);
      final WelcomeOverview mom = await w.svc(w.mom).overview();
      expect(mom.forMe.single.profile.preset, Preset.viewOnly);
      expect(mom.forMe.single.askerName, 'Alex');
    });

    testWidgets('a request that is not yours to answer shows no buttons', (t) async {
      await _size(t);
      final World w = await World.make();
      await w.svc(w.mom).propose(w.draft(trusted()));
      final WelcomeService m = w.svc(w.mom);
      final WelcomeRequest mine = (await m.overview()).jo;
      await _show(t, WelcomeRequestScreen(service: m, request: mine, childName: 'Ivy', confirmPin: () async => true, onDone: (_) {}));
      expect(find.byKey(const Key('welcomeYes')), findsNothing);
      expect(find.byKey(const Key('welcomeNoAnswerNeeded')), findsOneWidget);
    });

    testWidgets('a request put off comes back as a quiet line a day later, and no count is shown', (t) async {
      await _size(t);
      final World w = await World.make();
      await w.svc(w.mom).propose(w.draft(trusted()));
      final MemoryWelcomeReminders mem = MemoryWelcomeReminders();
      final WelcomeService d = w.svc(w.dad!, reminders: mem);
      await d.askLater((await d.overview()).forMe.single.hashHex);
      await _show(t, WelcomeCentreScreen(service: d, childName: 'Ivy', confirmPin: () async => true, onWelcomeSomeone: () {}, onOpenRequest: (_) {}));
      await t.pump(const Duration(milliseconds: 100));
      expect(find.text('Put off for later'), findsOneWidget);
      expect(find.byKey(const Key('welcomeReminder')), findsNothing, reason: 'not before the day is up');
      w.now += 25 * 60 * 60 * 1000;
      await _show(t, WelcomeCentreScreen(service: d, childName: 'Ivy', confirmPin: () async => true, onWelcomeSomeone: () {}, onOpenRequest: (_) {}));
      await t.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const Key('welcomeReminder')), findsOneWidget);
      _noLoadedWords(t);
    });
  });

  group('Adults and helpers', () {
    testWidgets('"Welcome someone" shows only when a host passes it; the old preview row is unchanged', (t) async {
      await _size(t);
      await _show(t, AdultsHelpersScreen(childName: 'Ivy', grownupLines: const <String>[], onChangePeople: null, onHelpers: () {}, onInvitePreview: () {}));
      expect(find.byKey(const Key('adultsWelcome')), findsNothing);
      expect(find.byKey(const Key('adultsInvite')), findsOneWidget);
      expect(find.text('Invite a co-parent (preview)'), findsOneWidget);
      bool hit = false;
      await _show(t, AdultsHelpersScreen(childName: 'Ivy', grownupLines: const <String>[], onChangePeople: null, onHelpers: () {}, onInvitePreview: () {}, onWelcome: () => hit = true));
      await t.tap(find.byKey(const Key('adultsWelcome')));
      expect(hit, isTrue);
      expect(find.byKey(const Key('adultsInvite')), findsOneWidget);
    });
  });
}
