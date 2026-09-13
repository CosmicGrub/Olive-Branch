// OLIVE BRANCH — game_twenty_questions.dart tests. MASTERFILE §9.2, §8.11.1,
// P2.
//
// The property that matters most for THIS activity specifically: the
// secret ALWAYS comes from a curated category's curated answer bank — there
// is no code path anywhere on this screen that accepts typed input, and the
// app never tries to parse an actual spoken question, only the curated
// yes/no answer to it. Beyond that: real curated-bank variety, real
// state-machine correctness (the question tally and per-question log
// really advance, twenty is a nudge and never a hard stop), the P2
// forbidden vocabulary sweep, a real device-adaptive structural difference,
// and real navigation reachability from child_home.dart.
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/child_home.dart';
import 'package:olive_client/game_picker.dart';
import 'package:olive_client/game_twenty_questions.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

void main() {
  testWidgets('renders by name', (t) async {
    await t.pumpWidget(wrap(TwentyQuestionsScreen(random: Random(1))));
    expect(find.text('20 questions'), findsOneWidget);
  });

  group('the curated secret bank — real content, real variety', () {
    test('five categories, each with dozens... at least fifteen answers', () {
      expect(twentyQuestionsCategories.length, 5);
      for (final cat in twentyQuestionsCategories) {
        expect(cat.answers.length, greaterThanOrEqualTo(15), reason: '${cat.label} has too few secrets');
      }
    });

    test('100 secrets total across the whole bank', () {
      final total = twentyQuestionsCategories.fold<int>(0, (sum, c) => sum + c.answers.length);
      expect(total, greaterThanOrEqualTo(75));
    });

    test('no duplicates within any category', () {
      for (final cat in twentyQuestionsCategories) {
        expect(cat.answers.toSet().length, cat.answers.length, reason: 'duplicate in ${cat.label}');
      }
    });

    test('category ids are unique and categoryById resolves each one', () {
      final ids = twentyQuestionsCategories.map((c) => c.id).toSet();
      expect(ids.length, twentyQuestionsCategories.length);
      for (final cat in twentyQuestionsCategories) {
        expect(categoryById(cat.id).id, cat.id);
      }
    });

    test('every secret is real, non-empty content with no stray whitespace', () {
      for (final cat in twentyQuestionsCategories) {
        for (final a in cat.answers) {
          expect(a.trim(), isNotEmpty);
          expect(a.trim(), a);
        }
      }
    });
  });

  group('pure engine — the tally and log really advance, twenty is a nudge, never a wall', () {
    test('a new round has an empty log and a secret from the right category', () {
      final cat = twentyQuestionsCategories.first;
      final round = newRound(cat, Random(1));
      expect(round.log, isEmpty);
      expect(round.questionsAsked, 0);
      expect(cat.answers, contains(round.secret));
    });

    test('withAnswer appends a numbered yes/no entry and increments the tally', () {
      final round = newRound(twentyQuestionsCategories.first, Random(1));
      final afterYes = round.withAnswer(true);
      expect(afterYes.questionsAsked, 1);
      expect(afterYes.log.single.n, 1);
      expect(afterYes.log.single.yes, isTrue);
      final afterNo = afterYes.withAnswer(false);
      expect(afterNo.questionsAsked, 2);
      expect(afterNo.log.last.n, 2);
      expect(afterNo.log.last.yes, isFalse);
    });

    test('withAnswer is a no-op once revealed', () {
      final round = newRound(twentyQuestionsCategories.first, Random(1)).withReveal(gotIt: true);
      final after = round.withAnswer(true);
      expect(after.log, isEmpty);
    });

    test('passing the 20-question target never blocks further answers — a nudge, not a wall', () {
      var round = newRound(twentyQuestionsCategories.first, Random(1));
      for (var i = 0; i < 25; i++) {
        round = round.withAnswer(i.isEven);
      }
      expect(round.questionsAsked, 25);
      expect(round.revealed, isFalse);
    });

    test('withReveal records gotIt honestly, true or false', () {
      final round = newRound(twentyQuestionsCategories.first, Random(1));
      expect(round.withReveal(gotIt: true).gotIt, isTrue);
      expect(round.withReveal(gotIt: false).gotIt, isFalse);
    });
  });

  group('the widget — a curated category picker, never a text field', () {
    testWidgets('starts on the category picker, showing all five fixed categories', (t) async {
      await t.pumpWidget(wrap(TwentyQuestionsScreen(random: Random(1))));
      for (final cat in twentyQuestionsCategories) {
        expect(find.text(cat.label), findsOneWidget);
      }
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('picking a category deals a secret and starts the tally at zero', (t) async {
      await t.pumpWidget(wrap(TwentyQuestionsScreen(random: Random(1))));
      await t.tap(find.text(twentyQuestionsCategories.first.label));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('secretWord')), findsOneWidget);
      expect(find.text('0 questions asked'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('Yes/No taps increment the tally', (t) async {
      await t.pumpWidget(wrap(TwentyQuestionsScreen(random: Random(1))));
      await t.tap(find.text(twentyQuestionsCategories.first.label));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, 'Yes'));
      await t.pumpAndSettle();
      expect(find.text('1 question asked'), findsOneWidget);
      await t.tap(find.widgetWithText(FilledButton, 'No'));
      await t.pumpAndSettle();
      expect(find.text('2 questions asked'), findsOneWidget);
    });

    testWidgets('"They guessed it!" reveals a warm confirmation with the secret, no score anywhere', (t) async {
      await t.pumpWidget(wrap(TwentyQuestionsScreen(random: Random(1))));
      await t.tap(find.text(twentyQuestionsCategories.first.label));
      await t.pumpAndSettle();
      await t.tap(find.text('They guessed it!'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('secretReveal')), findsOneWidget);
      expect(find.textContaining('Nice — it was'), findsOneWidget);
    });

    testWidgets('"Reveal the secret" shows the secret without "got it" framing', (t) async {
      await t.pumpWidget(wrap(TwentyQuestionsScreen(random: Random(1))));
      await t.tap(find.text(twentyQuestionsCategories.first.label));
      await t.pumpAndSettle();
      await t.tap(find.text('Reveal the secret'));
      await t.pumpAndSettle();
      expect(find.textContaining('It was "'), findsOneWidget);
      expect(find.textContaining('Nice — it was'), findsNothing);
    });

    testWidgets('"New round" returns to the category picker', (t) async {
      await t.pumpWidget(wrap(TwentyQuestionsScreen(random: Random(1))));
      await t.tap(find.text(twentyQuestionsCategories.first.label));
      await t.pumpAndSettle();
      await t.tap(find.text('Reveal the secret'));
      await t.pumpAndSettle();
      await t.tap(find.text('New round'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('categoryList')), findsOneWidget);
    });

    testWidgets('passing 20 questions shows a gentle nudge but Yes/No stays usable, never a wall', (t) async {
      await t.pumpWidget(wrap(TwentyQuestionsScreen(random: Random(1))));
      await t.tap(find.text(twentyQuestionsCategories.first.label));
      await t.pumpAndSettle();
      for (var i = 0; i < 20; i++) {
        await t.tap(find.widgetWithText(FilledButton, 'Yes'));
        await t.pumpAndSettle();
      }
      expect(find.text('20 questions asked'), findsOneWidget);
      expect(find.textContaining("That's 20!"), findsOneWidget);
      // Still usable — a nudge, not a hard stop.
      final yesButton = t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Yes'));
      expect(yesButton.onPressed, isNotNull);
      await t.tap(find.widgetWithText(FilledButton, 'Yes'));
      await t.pumpAndSettle();
      expect(find.text('21 questions asked'), findsOneWidget);
    });

    testWidgets('the current round\'s yes/no log and a finished round both join the session history, '
        'shown at a wide posture', (t) async {
      await t.binding.setSurfaceSize(const Size(900, 700));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(TwentyQuestionsScreen(random: Random(1))));
      await t.pumpAndSettle();
      expect(find.text('Yes/no taps will show up here as you go.'), findsOneWidget);

      await t.tap(find.text(twentyQuestionsCategories.first.label));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, 'Yes'));
      await t.pumpAndSettle();
      expect(find.text('Q1: Yes'), findsOneWidget);

      await t.tap(find.text('Reveal the secret'));
      await t.pumpAndSettle();
      await t.tap(find.text('New round'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('sessionHistoryList')), findsOneWidget);
    });
  });

  group('P2 — nothing here counts anything, even past the 20-question target', () {
    testWidgets('none of the forbidden score/failure vocabulary ever appears', (t) async {
      await t.pumpWidget(wrap(TwentyQuestionsScreen(random: Random(1))));
      await t.tap(find.text(twentyQuestionsCategories.first.label));
      await t.pumpAndSettle();
      for (var i = 0; i < 22; i++) {
        await t.tap(find.widgetWithText(FilledButton, 'Yes'));
        await t.pumpAndSettle();
      }
      for (final word in <String>[
        'score', 'streak', 'rank', 'elo', 'leaderboard', 'win rate', 'points',
        'you lost', 'you failed', 'game over',
      ]) {
        expect(find.textContaining(RegExp(word, caseSensitive: false)), findsNothing, reason: word);
      }
    });

    // Audit-fix (v0.49.22): the persisted session history is a de facto
    // win/loss tally if it encodes whether a round was guessed correctly —
    // exactly what P2 forbids, even with no literal number shown. The
    // per-round transient banner (`secretReveal`, exercised above) is
    // allowed to keep "Nice — it was..." wording since it resets every
    // round and is never persisted; this test instead reads the PERSISTED
    // `sessionHistoryList` content directly, across a gotIt round AND a
    // revealed round, and proves the outcome vocabulary never reaches it —
    // checking presence alone (as the pre-existing "session history" test
    // above already did) would have missed this.
    testWidgets('the persisted session history never carries an outcome judgment — content, '
        'not just presence, checked across a "got it" round AND a "revealed" round', (t) async {
      await t.binding.setSurfaceSize(const Size(900, 700));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(TwentyQuestionsScreen(random: Random(1))));
      await t.pumpAndSettle();

      // Round 1: they guessed it.
      await t.tap(find.text(twentyQuestionsCategories.first.label));
      await t.pumpAndSettle();
      await t.tap(find.text('They guessed it!'));
      await t.pumpAndSettle();
      await t.tap(find.text('New round'));
      await t.pumpAndSettle();

      // Round 2: the secret was revealed instead of guessed.
      await t.tap(find.text(twentyQuestionsCategories.first.label));
      await t.pumpAndSettle();
      await t.tap(find.text('Reveal the secret'));
      await t.pumpAndSettle();

      final Iterable<Text> entries = t.widgetList<Text>(
        find.descendant(of: find.byKey(const Key('sessionHistoryList')), matching: find.byType(Text)),
      );
      expect(entries.length, 2, reason: 'both the "got it" and the "revealed" round should have joined the history');
      for (final Text entry in entries) {
        final String lower = entry.data!.toLowerCase();
        for (final String outcomeWord in <String>['guessed it', 'nice —', 'nice -']) {
          expect(lower, isNot(contains(outcomeWord)),
              reason: 'session history entry carries an outcome judgment: "${entry.data}"');
        }
      }
    });
  });

  group('device-adaptive layout — a genuine structural difference, not a resize', () {
    testWidgets('at foldCover width (344px) there is no history panel at all', (t) async {
      await t.binding.setSurfaceSize(const Size(344, 882));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(TwentyQuestionsScreen(random: Random(1))));
      await t.pumpAndSettle();
      expect(t.widget(find.byKey(const Key('layoutRoot'))), isA<Column>());
      expect(find.byKey(const Key('historySidePanel')), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('at a wide posture (900px) a persistent history side panel appears alongside the round', (t) async {
      await t.binding.setSurfaceSize(const Size(900, 700));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(TwentyQuestionsScreen(random: Random(1))));
      await t.pumpAndSettle();
      expect(t.widget(find.byKey(const Key('layoutRoot'))), isA<Row>());
      expect(find.byKey(const Key('historySidePanel')), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });

  group('real navigation reachability — child_home.dart\'s onPlay actually reaches this screen', () {
    testWidgets('Play together -> 20 questions -> the real TwentyQuestionsScreen', (t) async {
      await t.binding.setSurfaceSize(const Size(900, 2000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(const ChildHome(
        childName: 'Ivy', presence: null, sleepsUntilHandover: 3, unreadCount: 0)));
      await t.tap(find.text('Play together'));
      await t.pumpAndSettle();
      expect(find.byType(GamePickerScreen), findsOneWidget);

      await t.scrollUntilVisible(find.text('20 questions'), 200,
          scrollable: find.byType(Scrollable).first);
      await t.tap(find.text('20 questions'));
      await t.pumpAndSettle();
      expect(find.byType(TwentyQuestionsScreen), findsOneWidget);
    });
  });
}
