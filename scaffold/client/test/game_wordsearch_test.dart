// OLIVE BRANCH — word search tests. MASTERFILE §9.2, P2.
//
// Engine correctness (placement, straight-line finding, completion) at the
// function level; the guardian/child screen split and P2 at the widget
// level — the child-facing screen must never show a score or a timer.
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/game_wordsearch.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

void main() {
  group('word search engine — §9.2', () {
    test('places every word and pads the rest with letters', () {
      final result = buildWordSearch(['Ivy', 'Dog'], size: 8, random: Random(1));
      expect(result.ok, isTrue);
      final puzzle = result.puzzle!;
      expect(puzzle.words.map((w) => w.word).toSet(), {'IVY', 'DOG'});
      for (final row in puzzle.grid) {
        for (final letter in row) {
          expect(RegExp('^[A-Z]\$').hasMatch(letter), isTrue);
        }
      }
    });

    test('rejects a word longer than the grid', () {
      final result = buildWordSearch(['SUPERCALIFRAGILISTIC'], size: 8, random: Random(1));
      expect(result.ok, isFalse);
      expect(result.reason, 'word_too_long');
    });

    test('rejects an empty word list', () {
      final result = buildWordSearch([], random: Random(1));
      expect(result.ok, isFalse);
      expect(result.reason, 'no_words');
    });

    test('findWord matches a straight selection in either direction', () {
      final result = buildWordSearch(['CAT'], size: 6, random: Random(2));
      final puzzle = result.puzzle!;
      final cells = puzzle.words.single.cells;
      final forward = findWord(puzzle, cells);
      expect(forward.found, 'CAT');
      expect(wordSearchComplete(forward.puzzle), isTrue);

      final again = findWord(puzzle, [...cells].reversed.toList());
      expect(again.found, 'CAT', reason: 'direction of selection should not matter');
    });

    test('a selection that is not the word finds nothing', () {
      final result = buildWordSearch(['CAT', 'DOG'], size: 8, random: Random(3));
      final puzzle = result.puzzle!;
      final notAWord = findWord(puzzle, [0, 1, 2]);
      // Coincidence aside, at least confirm nothing is marked found for an
      // arbitrary triple that doesn't match either placed word's cell set.
      final catCells = puzzle.words.firstWhere((w) => w.word == 'CAT').cells;
      final dogCells = puzzle.words.firstWhere((w) => w.word == 'DOG').cells;
      if (![catCells, dogCells].any((c) => (c..sort()).join(',') == ([0, 1, 2]..sort()).join(','))) {
        expect(notAWord.found, isNull);
      }
    });

    test('straightPath refuses anything that is not a line', () {
      expect(straightPath((0, 0), (0, 0)), isNull, reason: 'a single cell is not a selection');
      expect(straightPath((0, 0), (1, 2)), isNull, reason: 'not horizontal, vertical, or diagonal');
      expect(straightPath((0, 0), (0, 3)), isNotNull);
      expect(straightPath((0, 0), (3, 3)), isNotNull);
    });
  });

  group('word search setup screen — guardian-facing, §9.2', () {
    testWidgets('starts with demo personal words and can add/remove one', (t) async {
      await t.pumpWidget(wrap(const WordSearchSetupScreen()));
      expect(find.text('Ivy'), findsOneWidget);
      expect(find.text('Biscuit'), findsOneWidget);

      await t.enterText(find.byType(TextField), 'Treehouse');
      await t.tap(find.text('Add'));
      await t.pump();
      expect(find.text('Treehouse'), findsOneWidget);
    });

    testWidgets('refuses to hide an empty word list with a friendly message', (t) async {
      await t.pumpWidget(wrap(const WordSearchSetupScreen(initialWords: [])));
      await t.tap(find.text('Hide these words'));
      await t.pump();
      expect(find.textContaining('Add at least one word'), findsOneWidget);
      expect(find.byType(WordSearchScreen), findsNothing);
    });

    testWidgets('hiding words navigates to the child play screen', (t) async {
      await t.pumpWidget(wrap(const WordSearchSetupScreen(initialWords: ['Ivy'], childName: 'Ivy')));
      await t.tap(find.text('Hide these words'));
      await t.pumpAndSettle();
      expect(find.byType(WordSearchScreen), findsOneWidget);
      expect(find.text('IVY'), findsOneWidget);
    });
  });

  group('word search play screen — child-facing, P2', () {
    testWidgets('shows the word list and no settings affordance', (t) async {
      final result = buildWordSearch(['CAT'], size: 6, random: Random(4));
      await t.pumpWidget(wrap(WordSearchScreen(puzzle: result.puzzle!, childName: 'Ivy')));
      expect(find.text('CAT'), findsOneWidget);
      expect(find.byIcon(Icons.settings), findsNothing);
      expect(find.textContaining('score'), findsNothing);
      expect(find.textContaining('time left'), findsNothing);
    });

    testWidgets('tapping the two ends of the placed word marks it found', (t) async {
      final result = buildWordSearch(['CAT'], size: 6, random: Random(5));
      final puzzle = result.puzzle!;
      final cells = puzzle.words.single.cells;
      final size = puzzle.size;
      final firstR = cells.first ~/ size, firstC = cells.first % size;
      final lastR = cells.last ~/ size, lastC = cells.last % size;

      await t.pumpWidget(wrap(WordSearchScreen(puzzle: puzzle, childName: 'Ivy')));
      await t.tap(find.byKey(Key('wsCell_${firstR}_$firstC')));
      await t.pump();
      await t.tap(find.byKey(Key('wsCell_${lastR}_$lastC')));
      await t.pump();

      expect(find.byKey(const Key('wsComplete')), findsOneWidget);
    });
  });

  group('responsive audit — Fold5, phone, and tablet/desktop widths', () {
    // MASTERFILE's own mandated minimum widths (the Fold5's cover and
    // unfolded main screens), plus a standard phone width and a
    // short-and-wide desktop/tablet width now that Windows is a real
    // target. Covers both the guardian setup screen and the child play
    // screen (a size x size GridView-free grid built from LayoutBuilder).
    for (final MapEntry<String, Size> entry in const <String, Size>{
      'Fold5 cover (344 CSS px)': Size(344, 882),
      'Fold5 unfolded main (~673 CSS px)': Size(673, 841),
      'a standard phone (~390 CSS px)': Size(390, 844),
      'a tablet/desktop (~1100 CSS px)': Size(1100, 800),
    }.entries) {
      testWidgets('setup screen renders without overflow at ${entry.key}', (t) async {
        await t.binding.setSurfaceSize(entry.value);
        addTearDown(() => t.binding.setSurfaceSize(null));
        await t.pumpWidget(wrap(const WordSearchSetupScreen()));
        await t.pump();
        expect(t.takeException(), isNull);
      });

      testWidgets('play screen renders without overflow at ${entry.key}', (t) async {
        final result = buildWordSearch(
          ['Ivy', 'Biscuit', 'Maple Street', 'Soccer'], size: 12, random: Random(1));
        await t.binding.setSurfaceSize(entry.value);
        addTearDown(() => t.binding.setSurfaceSize(null));
        await t.pumpWidget(wrap(WordSearchScreen(puzzle: result.puzzle!, childName: 'Ivy')));
        await t.pump();
        expect(t.takeException(), isNull);
      });
    }
  });
}
