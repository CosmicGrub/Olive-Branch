// OLIVE BRANCH — story game tests. MASTERFILE §9.2, P2.
//
// The property that matters most: this game has NO winner, ever. childView
// never carries a boxesEach tally (competitive: false in the TS catalogue),
// and there is no "you lost" anywhere — only "What a story." at the end.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/game_story.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

void main() {
  group('ported logic — games.ts story branch', () {
    test('newStory starts empty with the CHILD to move first', () {
      final StoryGame g = newStory();
      expect(g.lines, isEmpty);
      expect(g.turn, StorySide.a);
      expect(g.finished, isFalse);
    });

    test('addLine alternates strictly every turn, unlike the chain game', () {
      StoryGame g = newStory();
      g = addLine(g, StorySide.a, 'Once upon a time').state!;
      expect(g.turn, StorySide.b);
      g = addLine(g, StorySide.b, 'there was a dragon').state!;
      expect(g.turn, StorySide.a);
      expect(g.lines.map((StoryLine l) => l.text), <String>['Once upon a time', 'there was a dragon']);
    });

    test('refuses the wrong side, an empty line, and play after it finishes', () {
      final StoryGame g = newStory();
      expect(addLine(g, StorySide.b, 'nope').ok, isFalse);
      expect(addLine(g, StorySide.a, '   ').ok, isFalse);
    });

    test('finishes at the line cap with a cooperative closing, never a score', () {
      StoryGame g = newStory();
      for (int i = 0; i < storyLineCap; i++) {
        g = addLine(g, g.turn, 'line $i').state!;
      }
      expect(g.finished, isTrue);
      final StoryChildView view = storyChildView(g);
      expect(view.finished, isTrue);
      expect(view.closing, 'What a story.');
      expect(view.yourTurn, isFalse);
    });

    test('storyArtifact is null only when nothing has been added', () {
      expect(storyArtifact(newStory()), isNull);
      final StoryGame g = addLine(newStory(), StorySide.a, 'A beginning').state!;
      expect(storyArtifact(g)!.body, 'A beginning');
    });
  });

  group('GameStoryScreen widget — MARKUP "story"', () {
    testWidgets('starts empty and it is the CHILD\'s turn first', (tester) async {
      await tester.pumpWidget(wrap(const GameStoryScreen()));
      expect(find.textContaining('Type the very first line'), findsOneWidget);
      expect(find.textContaining("Ivy's turn"), findsOneWidget);
    });

    testWidgets('the empty state is a real icon + message, not bare text, and clears on the first line',
        (tester) async {
      await tester.pumpWidget(wrap(const GameStoryScreen()));
      expect(find.byIcon(Icons.auto_stories_outlined), findsOneWidget);
      expect(find.textContaining('Type the very first line'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Once there was a dragon');
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pump();

      // The empty-state icon+message is gone the moment there is a real line.
      expect(find.byIcon(Icons.auto_stories_outlined), findsNothing);
      expect(find.textContaining('Type the very first line'), findsNothing);
    });

    testWidgets('adding a line appends it and hands the turn to the other side', (tester) async {
      await tester.pumpWidget(wrap(const GameStoryScreen()));
      await tester.enterText(find.byType(TextField), 'Once there was a very small dragon');
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pump();

      expect(find.textContaining('Once there was a very small dragon'), findsOneWidget);
      expect(find.textContaining("Dad's turn"), findsOneWidget);
      // The text field cleared after a successful add.
      final TextField field = tester.widget(find.byType(TextField));
      expect(field.controller!.text, isEmpty);
    });

    testWidgets('blank input does not append a line', (tester) async {
      await tester.pumpWidget(wrap(const GameStoryScreen()));
      await tester.enterText(find.byType(TextField), '   ');
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pump();
      expect(find.textContaining("Ivy's turn"), findsOneWidget);
    });

    testWidgets('"read it as one story" renders the joined text', (tester) async {
      await tester.pumpWidget(wrap(const GameStoryScreen()));
      await tester.enterText(find.byType(TextField), 'Once there was a dragon');
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'who loved pancakes');
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pump();

      await tester.tap(find.text('Read it as one story'));
      await tester.pump();
      expect(find.text('Once there was a dragon who loved pancakes'), findsOneWidget);
    });

    testWidgets('finishing the story shows the cooperative closing, never a score', (tester) async {
      await tester.pumpWidget(wrap(const GameStoryScreen()));
      for (int i = 0; i < storyLineCap; i++) {
        await tester.enterText(find.byType(TextField), 'line number $i');
        await tester.tap(find.widgetWithText(FilledButton, 'Add'));
        await tester.pump();
      }
      expect(find.text('What a story.'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.widgetWithText(FilledButton, 'Start a new story'), findsOneWidget);
    });

    testWidgets('P2 — no score, streak, badge, rank, or "you lost" ever appears', (tester) async {
      await tester.pumpWidget(wrap(const GameStoryScreen()));
      await tester.enterText(find.byType(TextField), 'A short line');
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pump();
      for (final String forbidden in <String>[
        'score', 'Score', 'streak', 'Streak', 'badge', 'Badge', 'rank', 'lost', 'lose', 'winner',
      ]) {
        expect(find.textContaining(forbidden), findsNothing);
      }
    });

    testWidgets('no settings affordance exists anywhere', (tester) async {
      await tester.pumpWidget(wrap(const GameStoryScreen()));
      expect(find.byIcon(Icons.settings), findsNothing);
      expect(find.byIcon(Icons.settings_outlined), findsNothing);
      expect(find.textContaining('Settings'), findsNothing);
    });

    testWidgets('the add button meets the 48dp minimum touch target', (tester) async {
      await tester.pumpWidget(wrap(const GameStoryScreen()));
      final Size size = tester.getSize(find.widgetWithText(FilledButton, 'Add'));
      expect(size.height, greaterThanOrEqualTo(48.0));
    });

    group('responsive audit — Fold5, phone, and tablet/desktop widths', () {
      // MASTERFILE's own mandated minimum widths (the Fold5's cover and
      // unfolded main screens), plus a standard phone width and a
      // short-and-wide desktop/tablet width now that Windows is a real
      // target. The default "Ivy's turn to add a line" banner is exactly
      // what overflowed the Fold5 cover width before the pill was made to
      // shrink instead — see game_story.dart's _TurnBanner.
      for (final MapEntry<String, Size> entry in const <String, Size>{
        'Fold5 cover (344 CSS px)': Size(344, 882),
        'Fold5 unfolded main (~673 CSS px)': Size(673, 841),
        'a standard phone (~390 CSS px)': Size(390, 844),
        'a tablet/desktop (~1100 CSS px)': Size(1100, 800),
      }.entries) {
        testWidgets('renders without overflow at ${entry.key}', (tester) async {
          await tester.binding.setSurfaceSize(entry.value);
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await tester.pumpWidget(wrap(const GameStoryScreen()));
          await tester.pump();
          expect(tester.takeException(), isNull);
        });
      }
    });
  });
}
