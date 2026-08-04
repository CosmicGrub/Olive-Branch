// OLIVE BRANCH — word chain tests. MASTERFILE §9.2, P2.
//
// The property that matters most here: the chain must NOT start empty (it
// "grows across custody weeks", §9.2) and a dropped recall must end the game
// cooperatively, with no score, streak, badge, or blame ever surfaced (P2).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/game_chain.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

Future<void> settleTimers(WidgetTester tester) =>
    tester.pump(const Duration(milliseconds: 400));

void main() {
  group('ported logic — games3.ts chain section', () {
    test('newChain starts empty with the parent to move first', () {
      final ChainGame g = newChain();
      expect(g.steps, isEmpty);
      expect(g.turn, ChainSide.b);
      expect(g.phase, ChainPhase.building);
    });

    test('addStep refuses the wrong side and empty labels', () {
      final ChainGame g = newChain();
      expect(addStep(g, ChainSide.a, 'nope').ok, isFalse);
      expect(addStep(g, ChainSide.b, '   ').ok, isFalse);
      final StepResult ok = addStep(g, ChainSide.b, 'a banana');
      expect(ok.ok, isTrue);
      expect(ok.state!.phase, ChainPhase.recalling);
      expect(ok.state!.turn, ChainSide.a);
    });

    test('a correct full recall hands the turn to add, without changing side', () {
      ChainGame g = addStep(newChain(), ChainSide.b, 'a banana').state!;
      final RecallResult r = recallStep(g, ChainSide.a, 'a banana');
      expect(r.ok, isTrue);
      expect(r.correct, isTrue);
      g = r.state!;
      expect(g.phase, ChainPhase.building);
      expect(g.turn, ChainSide.a, reason: 'the recaller now adds the next item');
    });

    test('a wrong recall ends the game cooperatively, never as a loss', () {
      final ChainGame g = addStep(newChain(), ChainSide.b, 'a banana').state!;
      final RecallResult r = recallStep(g, ChainSide.a, 'a spaceship');
      expect(r.ok, isTrue);
      expect(r.correct, isFalse);
      expect(r.state!.ended, isNotNull);
      expect(chainView(r.state!).closing, 'You two got to 0 together.');
    });

    test('chainArtifact is null below five steps', () {
      final ChainGame g = addStep(newChain(), ChainSide.b, 'a banana').state!;
      expect(chainArtifact(g), isNull);
    });
  });

  group('GameChainScreen widget — MARKUP "chain"', () {
    testWidgets('seeds with a chain already in progress, not an empty one', (tester) async {
      await tester.pumpWidget(wrap(const GameChainScreen()));
      expect(find.textContaining('6 things so far'), findsOneWidget);
      expect(find.textContaining('Say them back — 1 of 6'), findsOneWidget);
      expect(find.textContaining("Dad's turn"), findsOneWidget);
    });

    testWidgets('the chain is hidden during recall — that is the whole game', (tester) async {
      await tester.pumpWidget(wrap(const GameChainScreen()));
      expect(find.text('a banana'), findsNothing);
      expect(find.text('my blue kite'), findsNothing);
    });

    testWidgets('recalling all six correctly hands the turn to add a new item', (tester) async {
      await tester.pumpWidget(wrap(const GameChainScreen()));
      const List<String> answers = <String>[
        'a banana', 'my blue kite', "grandma's biscuits",
        'a squeaky toy for the dog', 'some stripy socks', 'a jar of honey',
      ];
      for (final String answer in answers) {
        await tester.enterText(find.byType(TextField), answer);
        await tester.tap(find.widgetWithText(FilledButton, "That's it!"));
        await settleTimers(tester);
      }
      expect(find.textContaining("Dad's turn to add"), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Add it'), findsOneWidget);
      // Now in the building phase, the whole chain is visible again.
      for (final String answer in answers) {
        expect(find.text(answer), findsOneWidget);
      }
    });

    testWidgets('adding a new item after recall grows the chain and flips the turn', (tester) async {
      await tester.pumpWidget(wrap(const GameChainScreen()));
      const List<String> answers = <String>[
        'a banana', 'my blue kite', "grandma's biscuits",
        'a squeaky toy for the dog', 'some stripy socks', 'a jar of honey',
      ];
      for (final String answer in answers) {
        await tester.enterText(find.byType(TextField), answer);
        await tester.tap(find.widgetWithText(FilledButton, "That's it!"));
        await settleTimers(tester);
      }
      await tester.enterText(find.byType(TextField), 'a rainbow sticker');
      await tester.tap(find.widgetWithText(FilledButton, 'Add it'));
      await settleTimers(tester);

      expect(find.textContaining('7 things so far'), findsOneWidget);
      expect(find.textContaining("Ivy's turn to remember"), findsOneWidget);
      // Back to recalling — hidden again.
      expect(find.text('a rainbow sticker'), findsNothing);
    });

    testWidgets('a wrong recall ends the chain cooperatively, blaming nobody', (tester) async {
      await tester.pumpWidget(wrap(const GameChainScreen()));
      await tester.enterText(find.byType(TextField), 'a spaceship');
      await tester.tap(find.widgetWithText(FilledButton, "That's it!"));
      await settleTimers(tester);

      expect(find.textContaining('The chain stopped there'), findsOneWidget);
      expect(find.textContaining('You two got to 0 together'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Start a new chain'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);

      for (final String bad in <String>['wrong', 'Wrong', 'Incorrect', 'fail', 'lost']) {
        expect(find.textContaining(bad), findsNothing);
      }
    });

    testWidgets('P2 — no streak, score, badge, rank, or record ever appears', (tester) async {
      await tester.pumpWidget(wrap(const GameChainScreen()));
      for (final String forbidden in <String>[
        'streak', 'Streak', 'score', 'Score', 'badge', 'Badge', 'rank', 'Rank', 'record', 'Record',
      ]) {
        expect(find.textContaining(forbidden), findsNothing);
      }
      // Also check the cooperative-ended state, reached via a wrong recall.
      await tester.enterText(find.byType(TextField), 'a spaceship');
      await tester.tap(find.widgetWithText(FilledButton, "That's it!"));
      await settleTimers(tester);
      for (final String forbidden in <String>['streak', 'score', 'badge', 'rank']) {
        expect(find.textContaining(forbidden), findsNothing);
      }
    });

    testWidgets('no settings affordance exists anywhere', (tester) async {
      await tester.pumpWidget(wrap(const GameChainScreen()));
      expect(find.byIcon(Icons.settings), findsNothing);
      expect(find.byIcon(Icons.settings_outlined), findsNothing);
      expect(find.textContaining('Settings'), findsNothing);
    });

    testWidgets('the submit button meets the 48dp minimum touch target', (tester) async {
      await tester.pumpWidget(wrap(const GameChainScreen()));
      final Size size = tester.getSize(find.widgetWithText(FilledButton, "That's it!"));
      expect(size.height, greaterThanOrEqualTo(48.0));
    });
  });
}
