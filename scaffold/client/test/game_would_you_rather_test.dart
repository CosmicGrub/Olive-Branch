// OLIVE BRANCH — game_would_you_rather.dart tests. MASTERFILE §9.2, §8.11.1,
// P2.
//
// Mirrors game_guess_doodle_test.dart's depth: real curated-bank variety,
// real state-machine correctness (both people really answer the SAME
// prompt independently, nobody's answer overwrites the other's), the P2
// forbidden vocabulary sweep (crucially including that neither answer is
// ever framed as "better"), a real device-adaptive structural difference,
// and real navigation reachability from child_home.dart.
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/child_home.dart';
import 'package:olive_client/game_picker.dart';
import 'package:olive_client/game_would_you_rather.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

void main() {
  testWidgets('renders by name', (t) async {
    await t.pumpWidget(wrap(WouldYouRatherScreen(random: Random(1))));
    expect(find.text('Would you rather'), findsOneWidget);
  });

  group('the curated prompt bank — real content, real variety', () {
    test('at least 40 prompts (dozens, not a handful)', () {
      expect(wouldYouRatherPrompts.length, greaterThanOrEqualTo(40));
    });

    test('prompt ids are unique', () {
      final ids = wouldYouRatherPrompts.map((p) => p.id).toSet();
      expect(ids.length, wouldYouRatherPrompts.length);
    });

    test('every prompt has two real, distinct, non-empty options', () {
      for (final p in wouldYouRatherPrompts) {
        expect(p.optionA.trim(), isNotEmpty);
        expect(p.optionB.trim(), isNotEmpty);
        expect(p.optionA, isNot(p.optionB));
      }
    });

    test('no exact duplicate prompt pair', () {
      final pairs = wouldYouRatherPrompts.map((p) => '${p.optionA}|${p.optionB}').toSet();
      expect(pairs.length, wouldYouRatherPrompts.length);
    });
  });

  group('pure engine — both people answer the SAME prompt independently', () {
    test('a new round has no answers yet', () {
      final round = newRound(Random(1));
      expect(round.childPick, isNull);
      expect(round.parentPick, isNull);
      expect(round.bothAnswered, isFalse);
    });

    test("recording the child's answer never touches the parent's", () {
      final round = newRound(Random(1));
      final afterChild = round.answeredBy('child', 'A');
      expect(afterChild.childPick, 'A');
      expect(afterChild.parentPick, isNull);
      expect(afterChild.bothAnswered, isFalse);
    });

    test('once both have answered, bothAnswered is true and each pick is preserved', () {
      final round = newRound(Random(1));
      final done = round.answeredBy('child', 'A').answeredBy('parent', 'B');
      expect(done.childPick, 'A');
      expect(done.parentPick, 'B');
      expect(done.bothAnswered, isTrue);
    });

    test('newRound(excludingId:) never immediately repeats the same prompt', () {
      final random = Random(2);
      var round = newRound(random);
      for (var i = 0; i < 20; i++) {
        final next = newRound(random, excludingId: round.prompt.id);
        expect(next.prompt.id, isNot(round.prompt.id));
        round = next;
      }
    });
  });

  group('the widget — an actor switch, never a text field, records each answer', () {
    testWidgets('tapping an option for the child records it and hands the turn to the parent', (t) async {
      await t.pumpWidget(wrap(WouldYouRatherScreen(childName: 'Ivy', parentName: 'Dad', random: Random(1))));
      expect(find.textContaining("Ivy's turn"), findsOneWidget);
      await t.tap(find.byKey(const Key('optionA')));
      await t.pumpAndSettle();
      expect(find.textContaining("Dad's turn"), findsOneWidget);
      // Nobody's answer is revealed until BOTH have answered.
      expect(find.byKey(const Key('revealCard')), findsNothing);
    });

    testWidgets('once both have answered, both picks reveal together', (t) async {
      await t.pumpWidget(wrap(WouldYouRatherScreen(childName: 'Ivy', parentName: 'Dad', random: Random(1))));
      await t.tap(find.byKey(const Key('optionA')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('optionB')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('revealCard')), findsOneWidget);
      expect(find.textContaining('Ivy picked:'), findsOneWidget);
      expect(find.textContaining('Dad picked:'), findsOneWidget);
    });

    testWidgets('"Next question" resets to a fresh, unanswered round on child\'s turn', (t) async {
      await t.pumpWidget(wrap(WouldYouRatherScreen(childName: 'Ivy', parentName: 'Dad', random: Random(1))));
      await t.tap(find.byKey(const Key('optionA')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('optionB')));
      await t.pumpAndSettle();
      await t.tap(find.text('Next question'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('revealCard')), findsNothing);
      expect(find.textContaining("Ivy's turn"), findsOneWidget);
    });

    testWidgets('an answered pair joins the session history, shown at a wide posture', (t) async {
      await t.binding.setSurfaceSize(const Size(900, 700));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(WouldYouRatherScreen(random: Random(1))));
      await t.pumpAndSettle();
      expect(find.text('Your first answered pair will show up here.'), findsOneWidget);
      await t.tap(find.byKey(const Key('optionA')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('optionB')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('sessionHistoryList')), findsOneWidget);
    });
  });

  group('P2 — no winner, no "better" answer, ever', () {
    testWidgets('none of the forbidden score/judgment vocabulary ever appears', (t) async {
      await t.pumpWidget(wrap(WouldYouRatherScreen(random: Random(1))));
      await t.tap(find.byKey(const Key('optionA')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('optionB')));
      await t.pumpAndSettle();
      for (final word in <String>[
        'score', 'streak', 'rank', 'elo', 'leaderboard', 'win rate', 'points',
        'better answer', 'you won', 'you lost',
      ]) {
        expect(find.textContaining(RegExp(word, caseSensitive: false)), findsNothing, reason: word);
      }
    });
  });

  group('device-adaptive layout — a genuine structural difference, not a resize', () {
    testWidgets('at foldCover width (344px) there is no history panel at all', (t) async {
      await t.binding.setSurfaceSize(const Size(344, 882));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(WouldYouRatherScreen(random: Random(1))));
      await t.pumpAndSettle();
      expect(t.widget(find.byKey(const Key('layoutRoot'))), isA<Column>());
      expect(find.byKey(const Key('historySidePanel')), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('at a wide posture (900px) a persistent history side panel appears alongside the prompt', (t) async {
      await t.binding.setSurfaceSize(const Size(900, 700));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(WouldYouRatherScreen(random: Random(1))));
      await t.pumpAndSettle();
      expect(t.widget(find.byKey(const Key('layoutRoot'))), isA<Row>());
      expect(find.byKey(const Key('historySidePanel')), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });

  group('real navigation reachability — child_home.dart\'s onPlay actually reaches this screen', () {
    testWidgets('Play together -> Would you rather -> the real WouldYouRatherScreen', (t) async {
      await t.binding.setSurfaceSize(const Size(900, 2000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(const ChildHome(
        childName: 'Ivy', presence: null, sleepsUntilHandover: 3, unreadCount: 0)));
      await t.tap(find.text('Play together'));
      await t.pumpAndSettle();
      expect(find.byType(GamePickerScreen), findsOneWidget);

      await t.scrollUntilVisible(find.text('Would you rather'), 200,
          scrollable: find.byType(Scrollable).first);
      await t.tap(find.text('Would you rather'));
      await t.pumpAndSettle();
      expect(find.byType(WouldYouRatherScreen), findsOneWidget);
    });
  });
}
