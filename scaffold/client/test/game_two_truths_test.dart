// OLIVE BRANCH — game_two_truths.dart tests. MASTERFILE §9.2, §8.11.1, P2.
//
// The property that matters most for THIS activity specifically (see the
// file's own header on the safe-content mechanism): every statement, in
// every round, is drawn from the fixed, in-repo `tallTaleRoundSets` bank —
// there is no code path anywhere on this screen that accepts typed input.
// Beyond that: real curated-bank variety, real state-machine correctness (a
// guess is scored against the ACTUAL shuffled tall-tale index, never a
// fixed position), the P2 forbidden vocabulary sweep, a real device-
// adaptive structural difference, and real navigation reachability from
// child_home.dart.
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/child_home.dart';
import 'package:olive_client/game_picker.dart';
import 'package:olive_client/game_two_truths.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

Finder _statementButton(int index) =>
    find.descendant(of: find.byKey(const Key('statementList')), matching: find.byType(OutlinedButton)).at(index);

/// Reads the ("statement #N is the tall tale") hint only the presenter is
/// meant to see, and returns N as a zero-based index — the same information
/// the presenter has, used here to deliberately guess right or wrong.
int _tallTaleIndexFromHint(WidgetTester t) {
  final Text hint = t.widget<Text>(
    find.descendant(of: find.byKey(const Key('tallTaleHint')), matching: find.byType(Text)),
  );
  final match = RegExp(r'#(\d+)').firstMatch(hint.data!);
  return int.parse(match!.group(1)!) - 1;
}

void main() {
  testWidgets('renders by name', (t) async {
    await t.pumpWidget(wrap(TwoTruthsScreen(random: Random(1))));
    expect(find.text('Two truths and a tall tale'), findsOneWidget);
  });

  group('the curated content bank — real trivia, never personal, real variety', () {
    test('at least 20 round sets (dozens of statements) across five categories', () {
      expect(tallTaleRoundSets.length, greaterThanOrEqualTo(20));
      expect(tallTaleCategories.length, 5);
    });

    test('every round set belongs to one of the five fixed categories — never an open one', () {
      for (final s in tallTaleRoundSets) {
        expect(tallTaleCategories, contains(s.category));
      }
    });

    test('round set ids are unique', () {
      final ids = tallTaleRoundSets.map((s) => s.id).toSet();
      expect(ids.length, tallTaleRoundSets.length);
    });

    test('every category has real variety — at least three round sets each', () {
      for (final cat in tallTaleCategories) {
        final count = tallTaleRoundSets.where((s) => s.category == cat).length;
        expect(count, greaterThanOrEqualTo(3), reason: '$cat has too few round sets for real replay variety');
      }
    });

    test('the three statements in every round set are distinct, real content', () {
      for (final s in tallTaleRoundSets) {
        expect(s.truthA.trim(), isNotEmpty);
        expect(s.truthB.trim(), isNotEmpty);
        expect(s.tallTale.trim(), isNotEmpty);
        expect(<String>{s.truthA, s.truthB, s.tallTale}.length, 3, reason: 'duplicate statement in ${s.id}');
      }
    });

    test('no exact duplicate statement text across the entire bank', () {
      final all = <String>[
        for (final s in tallTaleRoundSets) ...<String>[s.truthA, s.truthB, s.tallTale],
      ];
      expect(all.toSet().length, all.length);
    });
  });

  group('pure engine — the guess is scored against the real shuffled position', () {
    test('a new round has exactly one tall tale among three statements', () {
      final round = newRound(catAnimals, Random(1));
      expect(round.statements.length, 3);
      expect(round.statements.where((s) => s.isTallTale).length, 1);
      expect(round.category, catAnimals);
    });

    test('guessing the actual tall-tale index is recorded as correct', () {
      final round = newRound(catAnimals, Random(1));
      final guessed = round.withGuess(round.tallTaleIndex);
      expect(guessed.revealed, isTrue);
      expect(guessed.guessedCorrectly, isTrue);
    });

    test('guessing any other index is recorded as incorrect', () {
      final round = newRound(catAnimals, Random(1));
      final wrongIndex = (round.tallTaleIndex + 1) % 3;
      final guessed = round.withGuess(wrongIndex);
      expect(guessed.guessedCorrectly, isFalse);
    });

    test('newRound(excludingSetId:) never immediately repeats the same set within a category', () {
      final random = Random(2);
      var round = newRound(catAnimals, random);
      for (var i = 0; i < 10; i++) {
        final next = newRound(catAnimals, random, excludingSetId: round.setId);
        expect(next.setId, isNot(round.setId));
        round = next;
      }
    });
  });

  group('the widget — a curated category picker, never a text field', () {
    testWidgets('starts on the category picker, showing all five fixed categories', (t) async {
      await t.pumpWidget(wrap(TwoTruthsScreen(random: Random(1))));
      for (final cat in tallTaleCategories) {
        expect(find.text(cat), findsOneWidget);
      }
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('picking a category deals a round with a hidden-to-the-guesser hint', (t) async {
      await t.pumpWidget(wrap(TwoTruthsScreen(random: Random(1))));
      await t.tap(find.text(tallTaleCategories.first));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('tallTaleHint')), findsOneWidget);
      expect(find.byKey(const Key('statementList')), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('guessing the actual tall tale reveals "spotted"', (t) async {
      await t.pumpWidget(wrap(TwoTruthsScreen(random: Random(1))));
      await t.tap(find.text(tallTaleCategories.first));
      await t.pumpAndSettle();
      final correctIndex = _tallTaleIndexFromHint(t);
      await t.tap(_statementButton(correctIndex));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('tallTaleResult')), findsOneWidget);
      // Scoped to the result banner itself, not a bare textContaining sweep
      // — at a wide posture (this test's default surface size) the SAME
      // outcome word also appears in the session history entry the reveal
      // just added, and a bare sweep would find both.
      final resultText = t.widget<Text>(find.byKey(const Key('tallTaleResult'))).data!;
      expect(resultText, contains('spotted'));
    });

    testWidgets('guessing a truth reveals the tall tale got past them', (t) async {
      await t.pumpWidget(wrap(TwoTruthsScreen(random: Random(1))));
      await t.tap(find.text(tallTaleCategories.first));
      await t.pumpAndSettle();
      final correctIndex = _tallTaleIndexFromHint(t);
      final wrongIndex = (correctIndex + 1) % 3;
      await t.tap(_statementButton(wrongIndex));
      await t.pumpAndSettle();
      final resultText = t.widget<Text>(find.byKey(const Key('tallTaleResult'))).data!;
      expect(resultText, contains('got past them'));
    });

    testWidgets('once revealed, the statement buttons stop accepting new guesses', (t) async {
      await t.pumpWidget(wrap(TwoTruthsScreen(random: Random(1))));
      await t.tap(find.text(tallTaleCategories.first));
      await t.pumpAndSettle();
      final correctIndex = _tallTaleIndexFromHint(t);
      await t.tap(_statementButton(correctIndex));
      await t.pumpAndSettle();
      final button = t.widget<OutlinedButton>(_statementButton(0));
      expect(button.onPressed, isNull);
    });

    testWidgets('"New round" returns to the category picker', (t) async {
      await t.pumpWidget(wrap(TwoTruthsScreen(random: Random(1))));
      await t.tap(find.text(tallTaleCategories.first));
      await t.pumpAndSettle();
      final correctIndex = _tallTaleIndexFromHint(t);
      await t.tap(_statementButton(correctIndex));
      await t.pumpAndSettle();
      await t.tap(find.text('New round'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('categoryList')), findsOneWidget);
    });

    testWidgets('a solved round joins the session history, shown at a wide posture', (t) async {
      await t.binding.setSurfaceSize(const Size(900, 700));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(TwoTruthsScreen(random: Random(1))));
      await t.pumpAndSettle();
      expect(find.text('Your first solved round will show up here.'), findsOneWidget);
      await t.tap(find.text(tallTaleCategories.first));
      await t.pumpAndSettle();
      final correctIndex = _tallTaleIndexFromHint(t);
      await t.tap(_statementButton(correctIndex));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('sessionHistoryList')), findsOneWidget);
    });
  });

  group('P2 — nothing here counts anything', () {
    testWidgets('none of the forbidden score vocabulary ever appears', (t) async {
      await t.pumpWidget(wrap(TwoTruthsScreen(random: Random(1))));
      await t.tap(find.text(tallTaleCategories.first));
      await t.pumpAndSettle();
      final correctIndex = _tallTaleIndexFromHint(t);
      await t.tap(_statementButton(correctIndex));
      await t.pumpAndSettle();
      for (final word in <String>['score', 'streak', 'rank', 'elo', 'leaderboard', 'win rate', 'points']) {
        expect(find.textContaining(RegExp(word, caseSensitive: false)), findsNothing, reason: word);
      }
    });
  });

  group('device-adaptive layout — a genuine structural difference, not a resize', () {
    testWidgets('at foldCover width (344px) there is no history panel at all', (t) async {
      await t.binding.setSurfaceSize(const Size(344, 882));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(TwoTruthsScreen(random: Random(1))));
      await t.pumpAndSettle();
      expect(t.widget(find.byKey(const Key('layoutRoot'))), isA<Column>());
      expect(find.byKey(const Key('historySidePanel')), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('at a wide posture (900px) a persistent history side panel appears alongside the round', (t) async {
      await t.binding.setSurfaceSize(const Size(900, 700));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(TwoTruthsScreen(random: Random(1))));
      await t.pumpAndSettle();
      expect(t.widget(find.byKey(const Key('layoutRoot'))), isA<Row>());
      expect(find.byKey(const Key('historySidePanel')), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });

  group('real navigation reachability — child_home.dart\'s onPlay actually reaches this screen', () {
    testWidgets('Play together -> Two truths and a tall tale -> the real TwoTruthsScreen', (t) async {
      await t.binding.setSurfaceSize(const Size(900, 2000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(const ChildHome(
        childName: 'Ivy', presence: null, sleepsUntilHandover: 3, unreadCount: 0)));
      await t.tap(find.text('Play together'));
      await t.pumpAndSettle();
      expect(find.byType(GamePickerScreen), findsOneWidget);

      await t.scrollUntilVisible(find.text('Two truths and a tall tale'), 200,
          scrollable: find.byType(Scrollable).first);
      await t.tap(find.text('Two truths and a tall tale'));
      await t.pumpAndSettle();
      expect(find.byType(TwoTruthsScreen), findsOneWidget);
    });
  });
}
