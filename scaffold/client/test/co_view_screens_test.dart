// OLIVE BRANCH — "Read together" screens. Drives the real widgets against a real
// leader and follower over a loopback transport, so a tap on the guardian's
// phone turns the page on the child's, exactly as it will in the app.
//
// The standing rule for the child's side: no clock, no counter, no meter, and
// none of the machinery's words. That is asserted on every phase, not hoped for.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/co_view_logic.dart';
import 'package:olive_client/co_view_screens.dart';
import 'package:olive_client/co_view_session.dart';
import 'package:olive_client/theme.dart';
import 'package:olive_client/theme_data.dart';

const guardian = Principal(kind: 'guardian', role: 'guardian');
const child = Principal(kind: 'child');
const story = CoViewStory(id: 'owl-1', title: 'The owl and the moon', pages: [
  CoViewStoryPage('Far above the olive grove, a small owl asked the moon a big question.'),
  CoViewStoryPage('The moon smiled and glowed a little brighter.'),
  CoViewStoryPage('Down in the valley one small window glowed.'),
]);

Widget wrap(Widget child) => MaterialApp(theme: buildThemeData(defaultAppTheme), home: child);

class Rig {
  Rig({int limitMin = 120, int usedS = 0}) {
    final (g, c) = LoopbackTransport.pair(guardian, child);
    leader = CoViewLeader(transport: g, me: guardian, story: story, limitMin: limitMin, usedSeconds: usedS, nowMs: () => 0);
    follower = CoViewFollower(transport: c, me: child, story: story, budget: () => leader.budget);
  }
  late final CoViewLeader leader;
  late final CoViewFollower follower;
}

/// Every string a child can read on screen, except the story itself.
List<String> chromeText(WidgetTester t) => [
      for (final w in t.widgetList<Text>(find.byType(Text)))
        if ((w.data ?? '').isNotEmpty && w.key != const Key('coViewPageText')) w.data!,
    ];

final RegExp forbidden = RegExp(r'allowance|limit|budget|session|synced|sync|minutes?|timer|countdown|\d', caseSensitive: false);

void main() {
  group('the child — invitation', () {
    testWidgets('nothing shows until she is invited', (t) async {
      final r = Rig();
      await t.pumpWidget(wrap(CoViewChildScreen(follower: r.follower)));
      expect(find.byKey(const Key('coViewJoin')), findsNothing);
    });

    testWidgets('an invitation has one big yes and one quiet no, both at least 64 high', (t) async {
      final r = Rig();
      await t.pumpWidget(wrap(CoViewChildScreen(follower: r.follower)));
      r.leader.start();
      await t.pump();
      expect(find.text('Your grown-up wants to read a story with you'), findsOneWidget);
      expect(t.getSize(find.byKey(const Key('coViewJoin'))).height, greaterThanOrEqualTo(64));
      expect(t.getSize(find.byKey(const Key('coViewNotNow'))).height, greaterThanOrEqualTo(64));
    });

    testWidgets('the guardian is named the way she names him', (t) async {
      final r = Rig();
      await t.pumpWidget(wrap(CoViewChildScreen(follower: r.follower, guardianName: 'Nana')));
      r.leader.start();
      await t.pump();
      expect(find.text('Nana wants to read a story with you'), findsOneWidget);
    });

    testWidgets('Not now tells the guardian she is not ready and shows a kind goodbye', (t) async {
      final r = Rig();
      await t.pumpWidget(wrap(CoViewChildScreen(follower: r.follower)));
      r.leader.start();
      await t.pump();
      await t.tap(find.byKey(const Key('coViewNotNow')));
      await t.pump();
      expect(r.leader.ending, CoViewEnding.declined);
      expect(find.text('Okay!'), findsOneWidget);
      expect(find.text("Your grown-up will be here when you're ready."), findsOneWidget);
    });
  });

  group('the child — reading', () {
    testWidgets('Join shows the first page and the always-there All done button', (t) async {
      final r = Rig();
      await t.pumpWidget(wrap(CoViewChildScreen(follower: r.follower)));
      r.leader.start();
      await t.pump();
      await t.tap(find.byKey(const Key('coViewJoin')));
      await t.pump();
      expect(find.byKey(const Key('coViewPageText')), findsOneWidget);
      expect(find.text(story.pages[0].text), findsOneWidget);
      expect(find.byKey(const Key('coViewAllDone')), findsOneWidget);
      expect(t.getSize(find.byKey(const Key('coViewAllDone'))).height, greaterThanOrEqualTo(64));
    });

    testWidgets("the guardian's page turn changes her page, and nothing she does can change his", (t) async {
      final r = Rig();
      await t.pumpWidget(wrap(CoViewChildScreen(follower: r.follower)));
      r.leader.start();
      await t.pump();
      await t.tap(find.byKey(const Key('coViewJoin')));
      await t.pump();
      r.leader.nextPage();
      await t.pump();
      expect(find.text(story.pages[1].text), findsOneWidget);
      expect(r.leader.page, 1);
    });

    testWidgets('All done ends it and the guardian is told, calmly', (t) async {
      final r = Rig();
      await t.pumpWidget(wrap(CoViewChildScreen(follower: r.follower)));
      r.leader.start();
      await t.pump();
      await t.tap(find.byKey(const Key('coViewJoin')));
      await t.pump();
      await t.tap(find.byKey(const Key('coViewAllDone')));
      await t.pump();
      expect(find.text('All done!'), findsOneWidget);
      expect(r.leader.ending, CoViewEnding.child);
    });

    testWidgets('"Last one for today" appears near the end with no number', (t) async {
      final r = Rig(limitMin: 120, usedS: 120 * 60 - 9 * 60);
      await t.pumpWidget(wrap(CoViewChildScreen(follower: r.follower)));
      r.leader.start();
      await t.pump();
      await t.tap(find.byKey(const Key('coViewJoin')));
      await t.pump();
      expect(find.byKey(const Key('coViewLastOne')), findsOneWidget);
      expect(find.text('Last one for today'), findsOneWidget);
    });

    testWidgets('no cue when there is plenty of time', (t) async {
      final r = Rig();
      await t.pumpWidget(wrap(CoViewChildScreen(follower: r.follower)));
      r.leader.start();
      await t.pump();
      await t.tap(find.byKey(const Key('coViewJoin')));
      await t.pump();
      expect(find.byKey(const Key('coViewLastOne')), findsNothing);
    });
  });

  group('the child — the three kind endings', () {
    for (final c in [
      (CoViewEnding.child, 'All done!', 'See you soon.'),
      (CoViewEnding.guardian, 'All done', 'Your grown-up says goodnight.'),
      (CoViewEnding.budget, "That's all for today", 'You did a great job. See you tomorrow!'),
    ]) {
      testWidgets('${c.$1.name}: "${c.$2}"', (t) async {
        final r = Rig(limitMin: 1);
        await t.pumpWidget(wrap(CoViewChildScreen(follower: r.follower)));
        r.leader.start();
        await t.pump();
        await t.tap(find.byKey(const Key('coViewJoin')));
        await t.pump();
        switch (c.$1) {
          case CoViewEnding.child:
            await t.tap(find.byKey(const Key('coViewAllDone')));
          case CoViewEnding.guardian:
            r.leader.end();
          case _:
            r.leader.spend(60);
        }
        await t.pump();
        expect(find.byKey(const Key('coViewEndTitle')), findsOneWidget);
        expect((t.widget<Text>(find.byKey(const Key('coViewEndTitle')))).data, c.$2);
        expect((t.widget<Text>(find.byKey(const Key('coViewEndSub')))).data, c.$3);
      });
    }

    testWidgets('Back to my home calls onClose', (t) async {
      final r = Rig();
      var closed = 0;
      await t.pumpWidget(wrap(CoViewChildScreen(follower: r.follower, onClose: () => closed++)));
      r.leader.start();
      await t.pump();
      r.follower.decline();
      await t.pump();
      await t.tap(find.byKey(const Key('coViewBackHome')));
      expect(closed, 1);
    });
  });

  group('the child never sees the machinery', () {
    testWidgets('no number and none of the system words in any phase', (t) async {
      final r = Rig(limitMin: 120, usedS: 120 * 60 - 9 * 60);
      await t.pumpWidget(wrap(CoViewChildScreen(follower: r.follower)));
      final seen = <String>[];
      r.leader.start();
      await t.pump();
      seen.addAll(chromeText(t)); // invitation
      await t.tap(find.byKey(const Key('coViewJoin')));
      await t.pump();
      seen.addAll(chromeText(t)); // reading, with the "last one" cue
      r.leader.spend(9 * 60);
      await t.pump();
      seen.addAll(chromeText(t)); // the time-is-up ending
      expect(seen, isNotEmpty);
      for (final s in seen) {
        expect(forbidden.hasMatch(s), isFalse, reason: 'the child can read "$s"');
      }
    });
  });

  group('the guardian', () {
    testWidgets('idle: time left and a Read with Ivy button', (t) async {
      final r = Rig();
      await t.pumpWidget(wrap(CoViewLeaderScreen(leader: r.leader)));
      expect(find.text('2 h left'), findsOneWidget);
      expect(find.text('Read with Ivy'), findsOneWidget);
    });

    testWidgets('start moves to waiting, then Join takes it live with an in-step chip', (t) async {
      final r = Rig();
      await t.pumpWidget(wrap(CoViewLeaderScreen(leader: r.leader)));
      await t.tap(find.byKey(const Key('coViewStart')));
      await t.pump();
      expect(find.text('Waiting for Ivy'), findsOneWidget);
      r.follower.join();
      await t.pump();
      expect(find.byKey(const Key('coViewInStep')), findsOneWidget);
      expect(find.text('Page 1 of 3'), findsOneWidget);
    });

    testWidgets('Next and Back drive both screens; Back is off on page one and Next on the last', (t) async {
      final r = Rig()..leader.start();
      r.follower.join();
      await t.pumpWidget(wrap(CoViewLeaderScreen(leader: r.leader)));
      expect(t.widget<OutlinedButton>(find.byKey(const Key('coViewBack'))).onPressed, isNull);
      await t.tap(find.byKey(const Key('coViewNext')));
      await t.pump();
      expect(find.text('Page 2 of 3'), findsOneWidget);
      expect(r.follower.page, 1);
      await t.tap(find.byKey(const Key('coViewNext')));
      await t.pump();
      expect(t.widget<FilledButton>(find.byKey(const Key('coViewNext'))).onPressed, isNull);
    });

    testWidgets('amber time chip in the last ten minutes', (t) async {
      final r = Rig(usedS: 120 * 60 - 9 * 60)..leader.start();
      r.follower.join();
      await t.pumpWidget(wrap(CoViewLeaderScreen(leader: r.leader)));
      expect(find.text('9 min left'), findsOneWidget);
    });

    testWidgets('a start while off or used up says why and sends nothing', (t) async {
      final off = Rig(limitMin: 0);
      await t.pumpWidget(wrap(CoViewLeaderScreen(leader: off.leader)));
      await t.tap(find.byKey(const Key('coViewStart')));
      await t.pump();
      expect(find.text('Reading together is switched off for Ivy.'), findsOneWidget);
      final done = Rig(usedS: 7200);
      await t.pumpWidget(wrap(CoViewLeaderScreen(leader: done.leader)));
      await t.tap(find.byKey(const Key('coViewStart')));
      await t.pump();
      expect(find.text("Today's time is used up."), findsOneWidget);
    });

    testWidgets('an ending never blames her', (t) async {
      final r = Rig()..leader.start();
      r.follower.join();
      await t.pumpWidget(wrap(CoViewLeaderScreen(leader: r.leader)));
      r.follower.allDone();
      await t.pump();
      expect(find.text('Ivy is all done'), findsOneWidget);
      expect(find.text('She ended it herself. That is always fine.'), findsOneWidget);
    });

    testWidgets('declining reads as not ready yet', (t) async {
      final r = Rig()..leader.start();
      await t.pumpWidget(wrap(CoViewLeaderScreen(leader: r.leader)));
      r.follower.decline();
      await t.pump();
      expect(find.text("Ivy isn't ready yet"), findsOneWidget);
    });

    testWidgets('when time runs out the guardian is offered Change daily time', (t) async {
      final r = Rig(limitMin: 1)..leader.start();
      r.follower.join();
      var opened = 0;
      await t.pumpWidget(wrap(CoViewLeaderScreen(leader: r.leader, onChangeTime: () => opened++)));
      r.leader.spend(60);
      await t.pump();
      expect(find.text("Today's time is used up"), findsOneWidget);
      await t.tap(find.byKey(const Key('coViewChangeTimeCta')));
      expect(opened, 1);
    });

    testWidgets('End for now ends it for both', (t) async {
      final r = Rig()..leader.start();
      r.follower.join();
      await t.pumpWidget(wrap(CoViewLeaderScreen(leader: r.leader)));
      await t.tap(find.byKey(const Key('coViewEnd')));
      await t.pump();
      expect(r.follower.ending, CoViewEnding.guardian);
      expect(find.text('Finished'), findsOneWidget);
    });
  });

  group('the daily-time sheet', () {
    testWidgets('starts on the current value with Save off and "No change."', (t) async {
      final r = Rig();
      await t.pumpWidget(wrap(Scaffold(body: CoViewAllowanceSheet(currentMin: 120, onSave: r.leader.setAllowance))));
      expect(find.byKey(const Key('coViewValue')), findsOneWidget);
      expect((t.widget<Text>(find.byKey(const Key('coViewValue')))).data, '2 h');
      expect(t.widget<FilledButton>(find.byKey(const Key('coViewSave'))).onPressed, isNull);
      expect((t.widget<Text>(find.byKey(const Key('coViewLine')))).data, 'No change.');
    });

    testWidgets('lowering says it is free and immediate', (t) async {
      final r = Rig();
      await t.pumpWidget(wrap(Scaffold(body: CoViewAllowanceSheet(currentMin: 120, onSave: r.leader.setAllowance))));
      await t.tap(find.byKey(const Key('coViewChip60')));
      await t.pump();
      expect((t.widget<Text>(find.byKey(const Key('coViewLine')))).data, 'Takes effect right away. The other guardian is not asked.');
    });

    testWidgets('raising says the other guardian will be told', (t) async {
      final r = Rig();
      await t.pumpWidget(wrap(Scaffold(body: CoViewAllowanceSheet(currentMin: 120, onSave: r.leader.setAllowance))));
      await t.tap(find.byKey(const Key('coViewChip180')));
      await t.pump();
      expect((t.widget<Text>(find.byKey(const Key('coViewLine')))).data, 'The other guardian will be told about this change.');
    });

    testWidgets('the stepper moves 15 minutes and Save applies it through the engine', (t) async {
      final r = Rig();
      await t.pumpWidget(wrap(Scaffold(body: CoViewAllowanceSheet(currentMin: 120, onSave: r.leader.setAllowance))));
      await t.tap(find.byKey(const Key('coViewMore')));
      await t.pump();
      expect((t.widget<Text>(find.byKey(const Key('coViewValue')))).data, '2 h 15 min');
      await t.tap(find.byKey(const Key('coViewSave')));
      await t.pump();
      expect(r.leader.limitMin, 135);
      expect((t.widget<Text>(find.byKey(const Key('coViewLine')))).data, 'Saved.');
    });

    testWidgets('Off is a real choice and reads as Off', (t) async {
      final r = Rig();
      await t.pumpWidget(wrap(Scaffold(body: CoViewAllowanceSheet(currentMin: 120, onSave: r.leader.setAllowance))));
      await t.tap(find.byKey(const Key('coViewChip0')));
      await t.pump();
      expect((t.widget<Text>(find.byKey(const Key('coViewValue')))).data, 'Off');
    });

    testWidgets('the stepper stops at the floor and at the ceiling', (t) async {
      final r = Rig();
      await t.pumpWidget(wrap(Scaffold(body: CoViewAllowanceSheet(currentMin: 0, onSave: r.leader.setAllowance))));
      expect(t.widget<IconButton>(find.byKey(const Key('coViewLess'))).onPressed, isNull);
      await t.pumpWidget(wrap(Scaffold(body: CoViewAllowanceSheet(key: const ValueKey('max'), currentMin: maxAllowanceMin, onSave: r.leader.setAllowance))));
      expect(t.widget<IconButton>(find.byKey(const Key('coViewMore'))).onPressed, isNull);
    });

    testWidgets('a change the engine refuses says so and changes nothing', (t) async {
      final r = Rig();
      await t.pumpWidget(wrap(Scaffold(body: CoViewAllowanceSheet(currentMin: 120, onSave: (_) => const AllowanceChange(ok: false, limitMin: 120, direction: AllowanceDirection.rejected, notifyCoGuardian: false, reason: AllowanceRejection.notAGuardian)))));
      await t.tap(find.byKey(const Key('coViewChip60')));
      await t.pump();
      await t.tap(find.byKey(const Key('coViewSave')));
      await t.pump();
      expect((t.widget<Text>(find.byKey(const Key('coViewLine')))).data, 'That change was not allowed.');
      expect(r.leader.limitMin, 120);
    });
  });
}
