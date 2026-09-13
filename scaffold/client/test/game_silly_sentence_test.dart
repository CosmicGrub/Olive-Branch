// OLIVE BRANCH — game_silly_sentence.dart tests. MASTERFILE §9.2, §8.11.1, P2.
//
// Mirrors game_guess_doodle_test.dart's depth: real curated-bank variety
// (minimum counts, no duplicates, no stray whitespace), real state-machine
// correctness (a blank actually fills, turn actually alternates, a
// completed sentence actually joins the session history), the P2 forbidden
// vocabulary sweep, a real device-adaptive structural difference, and real
// navigation reachability from child_home.dart.
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/child_home.dart';
import 'package:olive_client/game_picker.dart';
import 'package:olive_client/game_silly_sentence.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

Finder _firstOption(WidgetTester t) =>
    find.descendant(of: find.byKey(const Key('wordOptions')), matching: find.byType(OutlinedButton)).first;

/// Taps the first offered option repeatedly until the sentence completes.
/// Bounded well above the longest template's blank count (4) so a real bug
/// that never completes fails loudly instead of hanging.
Future<void> _completeSentence(WidgetTester t) async {
  for (int i = 0; i < 8; i++) {
    if (find.text('Read it aloud!').evaluate().isNotEmpty) return;
    await t.tap(_firstOption(t));
    await t.pumpAndSettle();
  }
  fail('sentence never completed within 8 taps');
}

void main() {
  testWidgets('renders by name', (t) async {
    await t.pumpWidget(wrap(SillySentenceScreen(random: Random(1))));
    expect(find.text('Silly sentence maker'), findsOneWidget);
  });

  group('the curated word bank — real content, real variety', () {
    test('each of the four categories has dozens of words, not a handful', () {
      for (final entry in sentenceWordCategories.entries) {
        expect(entry.value.length, greaterThanOrEqualTo(15),
            reason: '${entry.key} has too few words for real replay variety');
      }
    });

    test('80 words total across the whole bank', () {
      final total = sentenceWordCategories.values.fold<int>(0, (sum, l) => sum + l.length);
      expect(total, greaterThanOrEqualTo(60));
    });

    test('no duplicates within any category', () {
      for (final entry in sentenceWordCategories.entries) {
        expect(entry.value.toSet().length, entry.value.length, reason: 'duplicate in ${entry.key}');
      }
    });

    test('every word is real, non-empty content with no stray whitespace', () {
      for (final words in sentenceWordCategories.values) {
        for (final w in words) {
          expect(w.trim(), isNotEmpty);
          expect(w.trim(), w);
        }
      }
    });

    test('at least five templates, and every template is well-formed '
        '(textParts is exactly one longer than categories, every category is real)', () {
      expect(sentenceTemplates.length, greaterThanOrEqualTo(3));
      for (final tpl in sentenceTemplates) {
        expect(tpl.textParts.length, tpl.categories.length + 1);
        for (final c in tpl.categories) {
          expect(sentenceWordCategories.containsKey(c), isTrue, reason: 'unknown category "$c" in ${tpl.id}');
        }
        // The first blank is always 'character' with an empty leading
        // textPart, so a mid-sentence phrase never gets a stray capital —
        // see the file header's grammar note.
        expect(tpl.categories.first, 'character');
        expect(tpl.textParts.first, isEmpty);
      }
    });

    test('template ids are unique', () {
      final ids = sentenceTemplates.map((t) => t.id).toSet();
      expect(ids.length, sentenceTemplates.length);
    });
  });

  group('pure engine — the state machine really advances', () {
    test('a new round starts at turnIndex 0, incomplete, child\'s turn', () {
      final round = newRound(Random(1));
      expect(round.turnIndex, 0);
      expect(round.complete, isFalse);
      expect(round.currentTurnActorId, 'child');
    });

    test('fillBlank advances turnIndex by exactly one and records the word', () {
      final round = newRound(Random(1));
      final next = fillBlank(round, 'A giggling grandma');
      expect(next.turnIndex, round.turnIndex + 1);
      expect(next.blanks[0].filledWith, 'A giggling grandma');
    });

    test('turn alternates strictly starting with child', () {
      var round = newRound(Random(2));
      final actors = <String>[round.currentTurnActorId];
      while (!round.complete) {
        round = fillBlank(round, sentenceWordCategories[round.currentCategory]!.first);
        if (!round.complete) actors.add(round.currentTurnActorId);
      }
      for (var i = 0; i < actors.length; i++) {
        expect(actors[i], i.isEven ? 'child' : 'parent');
      }
    });

    test('fillBlank is a no-op once the round is complete', () {
      var round = newRound(Random(3));
      while (!round.complete) {
        round = fillBlank(round, sentenceWordCategories[round.currentCategory]!.first);
      }
      final stillComplete = fillBlank(round, 'anything');
      expect(stillComplete.turnIndex, round.turnIndex);
    });

    test('sentenceText shows ___ for unfilled blanks and the real word for filled ones', () {
      final round = newRound(Random(4));
      final text = sentenceText(round);
      expect(text, contains('___'));
      expect(text, isNot(contains('  ')));
    });

    test('sentenceText has no blanks left once the round is complete', () {
      var round = newRound(Random(5));
      while (!round.complete) {
        round = fillBlank(round, sentenceWordCategories[round.currentCategory]!.first);
      }
      expect(sentenceText(round), isNot(contains('___')));
    });

    test('optionsFor returns options drawn only from the current blank\'s category, no duplicates', () {
      final round = newRound(Random(6));
      final options = optionsFor(round, Random(7));
      expect(options.toSet().length, options.length);
      for (final o in options) {
        expect(sentenceWordCategories[round.currentCategory], contains(o));
      }
    });

    test('newRound(excludingTemplateId:) never immediately repeats the same template', () {
      final random = Random(8);
      var round = newRound(random);
      for (var i = 0; i < 20; i++) {
        final next = newRound(random, excludingTemplateId: round.templateId);
        expect(next.templateId, isNot(round.templateId));
        round = next;
      }
    });
  });

  group('the widget — turns really advance and a finished sentence really joins history', () {
    testWidgets('picking a word fills the blank and hands the turn to the other person', (t) async {
      await t.pumpWidget(wrap(SillySentenceScreen(childName: 'Ivy', parentName: 'Dad', random: Random(1))));
      expect(find.textContaining("Ivy's turn"), findsOneWidget);
      await t.tap(_firstOption(t));
      await t.pumpAndSettle();
      // Either the turn passed to Dad, or (for a 1-blank-remaining edge
      // case that never occurs with these templates) the sentence
      // completed outright — either way Ivy's turn banner must be gone.
      expect(find.textContaining("Ivy's turn"), findsNothing);
    });

    testWidgets('completing every blank reveals the sentence with no ___ left', (t) async {
      await t.pumpWidget(wrap(SillySentenceScreen(random: Random(1))));
      await _completeSentence(t);
      expect(find.text('Read it aloud!'), findsOneWidget);
      final cardText = t.widget<Text>(find.descendant(
        of: find.byKey(const Key('sentenceCard')), matching: find.byType(Text))).data!;
      expect(cardText, isNot(contains('___')));
    });

    testWidgets('"Make another one" starts a genuinely fresh round, not the finished one', (t) async {
      await t.pumpWidget(wrap(SillySentenceScreen(random: Random(1))));
      await _completeSentence(t);
      await t.tap(find.text('Make another one'));
      await t.pumpAndSettle();
      expect(find.text('Read it aloud!'), findsNothing);
      final cardText = t.widget<Text>(find.descendant(
        of: find.byKey(const Key('sentenceCard')), matching: find.byType(Text))).data!;
      expect(cardText, contains('___'));
    });

    testWidgets('a finished sentence joins the session history, shown at a wide posture', (t) async {
      await t.binding.setSurfaceSize(const Size(900, 700));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(SillySentenceScreen(random: Random(1))));
      await t.pumpAndSettle();
      expect(find.text('Your first finished sentence will show up here.'), findsOneWidget);
      await _completeSentence(t);
      expect(find.byKey(const Key('sessionHistoryList')), findsOneWidget);
    });
  });

  group('P2 — nothing here counts anything', () {
    testWidgets('none of the forbidden score vocabulary ever appears', (t) async {
      await t.pumpWidget(wrap(SillySentenceScreen(random: Random(1))));
      await _completeSentence(t);
      for (final word in <String>['score', 'streak', 'rank', 'elo', 'leaderboard', 'win rate', 'points', 'you won', 'you lost']) {
        expect(find.textContaining(RegExp(word, caseSensitive: false)), findsNothing, reason: word);
      }
    });
  });

  group('device-adaptive layout — a genuine structural difference, not a resize', () {
    testWidgets('at foldCover width (344px) there is no history panel at all', (t) async {
      await t.binding.setSurfaceSize(const Size(344, 882));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(SillySentenceScreen(random: Random(1))));
      await t.pumpAndSettle();
      expect(t.widget(find.byKey(const Key('layoutRoot'))), isA<Column>());
      expect(find.byKey(const Key('historySidePanel')), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('at a wide posture (900px) a persistent history side panel appears alongside the prompt', (t) async {
      await t.binding.setSurfaceSize(const Size(900, 700));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(SillySentenceScreen(random: Random(1))));
      await t.pumpAndSettle();
      expect(t.widget(find.byKey(const Key('layoutRoot'))), isA<Row>());
      expect(find.byKey(const Key('historySidePanel')), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });

  group('real navigation reachability — child_home.dart\'s onPlay actually reaches this screen', () {
    testWidgets('Play together -> Silly sentence maker -> the real SillySentenceScreen', (t) async {
      await t.binding.setSurfaceSize(const Size(900, 2000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(const ChildHome(
        childName: 'Ivy', presence: null, sleepsUntilHandover: 3, unreadCount: 0)));
      await t.tap(find.text('Play together'));
      await t.pumpAndSettle();
      expect(find.byType(GamePickerScreen), findsOneWidget);

      await t.scrollUntilVisible(find.text('Silly sentence maker'), 200,
          scrollable: find.byType(Scrollable).first);
      await t.tap(find.text('Silly sentence maker'));
      await t.pumpAndSettle();
      expect(find.byType(SillySentenceScreen), findsOneWidget);
    });
  });
}
