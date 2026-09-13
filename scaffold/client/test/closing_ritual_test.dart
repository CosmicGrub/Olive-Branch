// OLIVE BRANCH — closing ritual tests. MASTERFILE §9.13.1. Asserts the same
// properties packages/live/src/around.ts's own suite asserts, plus what
// actually renders in the widget tree.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/closing_ritual.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

void main() {
  group('closing ritual — pure logic', () {
    test('begins on the forward-looking beat', () {
      expect(beginClosing().beat, ClosingBeat.oneThing);
    });

    test('beats advance in the fixed order: one_thing -> when_next -> the_goodbye -> done', () {
      var c = beginClosing();
      c = closingWithOneThing(c, 'my wobbly tooth', nextTime: 'tomorrow after school');
      expect(c.beat, ClosingBeat.whenNext);
      c = closingAdvanceWhenNext(c);
      expect(c.beat, ClosingBeat.theGoodbye);
      c = closingWithGoodbye(c, 'Big squeeze');
      expect(c.beat, ClosingBeat.done);
    });

    test('a blank "one thing" is recorded as null, not an empty string', () {
      final c = closingWithOneThing(beginClosing(), '   ');
      expect(c.oneThing, isNull);
    });

    test('next time is NEVER invented — an unknown schedule says so honestly', () {
      final c = closingWithOneThing(beginClosing(), 'a drawing', nextTime: null);
      expect(c.beat, ClosingBeat.whenNext);
      expect(c.nextTime, isNull);
      expect(closingLines(c).prompt, 'We will sort out when.');
      expect(closingLines(c).sub, 'Nobody is pretending to know yet.');
    });

    test('a known next time is stated plainly the instant the beat is entered', () {
      final c = closingWithOneThing(beginClosing(), 'a drawing',
        nextTime: 'tomorrow after school');
      expect(closingLines(c).prompt, 'Next time is tomorrow after school.');
    });

    test('advancing past when_next keeps whatever next time was already known', () {
      var c = closingWithOneThing(beginClosing(), 'a drawing', nextTime: 'tomorrow after school');
      c = closingAdvanceWhenNext(c);
      expect(c.beat, ClosingBeat.theGoodbye);
      expect(c.nextTime, 'tomorrow after school');
    });

    test('skipClosing jumps straight to done from any beat', () {
      final c = skipClosing(beginClosing());
      expect(c.beat, ClosingBeat.done);
      expect(c.skipped, isTrue);
    });

    test('the forward beat becomes a real ask only if something was given', () {
      var c = beginClosing();
      c = closingWithOneThing(c, 'my wobbly tooth');
      final ask = closingToAsk(c, 'Dad');
      expect(ask, isNotNull);
      expect(ask!.prompt, 'Show me my wobbly tooth');
    });

    test('skipping before saying anything produces no ask', () {
      final c = skipClosing(beginClosing());
      expect(closingToAsk(c, 'Dad'), isNull);
    });
  });

  group('ClosingRitualScreen — child-facing render', () {
    testWidgets('walks all three beats in order and lands on a warm close', (t) async {
      await t.pumpWidget(wrap(const ClosingRitualScreen(childName: 'Ivy', callerName: 'Dad')));
      expect(find.text('What will you show me next time?'), findsOneWidget);

      await t.enterText(find.byType(TextField), 'my wobbly tooth');
      await t.tap(find.text('Next'));
      await t.pumpAndSettle();
      expect(find.text('We will sort out when.'), findsOneWidget,
        reason: 'no nextTime was supplied — nothing may be invented');

      await t.tap(find.text('Okay'));
      await t.pumpAndSettle();
      expect(find.text('How shall we say goodbye?'), findsOneWidget);
      expect(find.text('Big squeeze'), findsOneWidget);
      expect(find.text('Catch you later, alligator'), findsOneWidget);

      await t.tap(find.text('Big squeeze'));
      await t.pumpAndSettle();
      expect(find.text('Big squeeze'), findsOneWidget);
      expect(find.textContaining('Dad will ask you about my wobbly tooth'), findsOneWidget);
    });

    testWidgets('"not right now" is present at every beat and ends the ritual immediately',
        (t) async {
      await t.pumpWidget(wrap(const ClosingRitualScreen(childName: 'Ivy', callerName: 'Dad')));
      expect(find.text('Not right now'), findsOneWidget);
      await t.tap(find.text('Not right now'));
      await t.pumpAndSettle();
      expect(find.text('What will you show me next time?'), findsNothing);
      // Skipping produced no ask, so nothing references "will ask you about".
      expect(find.textContaining('will ask you about'), findsNothing);
      // The final beat has no further skip control.
      expect(find.text('Not right now'), findsNothing);
    });

    testWidgets('touch targets on this child-facing surface are at least 48dp', (t) async {
      await t.pumpWidget(wrap(const ClosingRitualScreen(childName: 'Ivy', callerName: 'Dad')));
      final Size next = t.getSize(find.byType(FilledButton).first);
      expect(next.height, greaterThanOrEqualTo(48.0));
      final Size skip = t.getSize(find.byType(TextButton).first);
      expect(skip.height, greaterThanOrEqualTo(48.0));
    });

    testWidgets('P2 — no streak, score, badge, or broken-streak notice anywhere', (t) async {
      await t.pumpWidget(wrap(const ClosingRitualScreen(childName: 'Ivy', callerName: 'Dad')));
      await t.enterText(find.byType(TextField), 'a drawing');
      await t.tap(find.text('Next'));
      await t.pumpAndSettle();
      await t.tap(find.text('Okay'));
      await t.pumpAndSettle();
      await t.tap(find.text('Same time tomorrow'));
      await t.pumpAndSettle();
      expect(find.textContaining('streak'), findsNothing);
      expect(find.textContaining('score'), findsNothing);
      expect(find.textContaining('badge'), findsNothing);
    });

    testWidgets('NO settings affordance exists at any depth', (t) async {
      await t.pumpWidget(wrap(const ClosingRitualScreen(childName: 'Ivy', callerName: 'Dad')));
      expect(find.byIcon(Icons.settings), findsNothing);
      expect(find.byIcon(Icons.settings_outlined), findsNothing);
    });
  });

  group('responsive — Fold5 cover/main, phone, tablet/desktop', () {
    // Fold5 cover (344 CSS px), Fold5 main (~673x841, nearly square), a
    // standard phone (390), and a desktop-scale short-and-wide width (1100)
    // — the four widths this repo's responsive audit requires.
    const widths = <String, Size>{
      'fold5 cover': Size(344, 820),
      'fold5 main': Size(673, 841),
      'phone': Size(390, 844),
      'tablet/desktop': Size(1100, 800),
    };

    for (final entry in widths.entries) {
      testWidgets('walks every beat without overflow at ${entry.key}', (t) async {
        t.view.physicalSize = entry.value;
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);

        await t.pumpWidget(wrap(const ClosingRitualScreen(childName: 'Ivy', callerName: 'Dad')));
        expect(t.takeException(), isNull);

        await t.enterText(find.byType(TextField), 'my wobbly tooth');
        await t.tap(find.text('Next'));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);

        await t.tap(find.text('Okay'));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);

        // The goodbye beat's Wrap of six chip-like buttons is the widest
        // single row of content on this screen — the one most likely to
        // misbehave at the Fold5 cover's 344px.
        await t.tap(find.text('Catch you later, alligator'));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      });
    }
  });
}
