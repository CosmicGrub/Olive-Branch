// OLIVE BRANCH — game_guess_doodle.dart tests. MASTERFILE §9.2, §9.12.4,
// §8.11.1, P2.
//
// Two properties matter most: only ONE actor's strokes are ever live at a
// time (the guesser never draws), and undo stays scoped to whoever is
// CURRENTLY the artist — the same annotation_canvas.dart guarantee
// game_draw_together_test.dart already proves, exercised here through the
// solo-drawer shape instead of the shared-canvas one. `_visibleStrokes()`
// reads the CustomPainter's strokes through `InkPainterStrokes` — see
// game_draw_together_test.dart's header for why that's a typed seam, not a
// `dynamic` cast.
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/annotation_canvas.dart';
import 'package:olive_client/child_home.dart';
import 'package:olive_client/game_draw_together.dart' show InkPainterStrokes;
import 'package:olive_client/game_guess_doodle.dart';
import 'package:olive_client/game_picker.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

List<Stroke> _visibleStrokes(WidgetTester t) {
  // Scoped to a descendant of the canvas itself — see
  // game_draw_together_test.dart's identical helper for why a bare
  // find.byType(CustomPaint) is fragile (other Material widgets, e.g. a
  // Scrollbar in the wide side panel, can legitimately add their own).
  final CustomPaint cp = t.widget<CustomPaint>(
    find.descendant(of: find.byKey(const Key('guessDoodleCanvas')), matching: find.byType(CustomPaint)),
  );
  final InkPainterStrokes painter = cp.painter! as InkPainterStrokes;
  return painter.strokes;
}

void main() {
  testWidgets('renders by name', (t) async {
    await t.pumpWidget(wrap(GuessDoodleScreen(random: Random(1))));
    expect(find.text('Guess the doodle'), findsOneWidget);
  });

  group('the curated word list — real content, real variety', () {
    test('at least 50 words (dozens, not a handful) — actually 86', () {
      expect(guessDoodleWords.length, greaterThanOrEqualTo(50));
    });

    test('no duplicates', () {
      expect(guessDoodleWords.toSet().length, guessDoodleWords.length);
    });

    test('every word is real, non-empty content, not a placeholder', () {
      for (final String w in guessDoodleWords) {
        expect(w.trim(), isNotEmpty);
        expect(w.trim(), w, reason: 'no stray leading/trailing whitespace: "$w"');
      }
    });
  });

  group('only ONE actor draws — mirrors annotation_canvas_test.dart', () {
    testWidgets('the default artist ("child") draws the live stroke', (t) async {
      await t.pumpWidget(wrap(GuessDoodleScreen(random: Random(1))));
      await t.drag(find.byKey(const Key('guessDoodleCanvas')), const Offset(60, 40));
      await t.pumpAndSettle();
      final strokes = _visibleStrokes(t);
      expect(strokes, hasLength(1));
      expect(strokes.single.actorId, 'child');
    });

    testWidgets('switching who is drawing attributes the next stroke to "parent", without '
        'erasing what the previous artist already drew', (t) async {
      await t.pumpWidget(wrap(GuessDoodleScreen(childName: 'Ivy', parentName: 'Dad', random: Random(1))));
      await t.drag(find.byKey(const Key('guessDoodleCanvas')), const Offset(60, 40));
      await t.pumpAndSettle();

      await t.tap(find.text('Dad'));
      await t.pumpAndSettle();
      await t.drag(find.byKey(const Key('guessDoodleCanvas')), const Offset(20, 20));
      await t.pumpAndSettle();

      final strokes = _visibleStrokes(t);
      expect(strokes, hasLength(2));
      expect(strokes[0].actorId, 'child');
      expect(strokes[1].actorId, 'parent');
    });

    testWidgets('undo removes only the CURRENT artist\'s own last stroke', (t) async {
      await t.pumpWidget(wrap(GuessDoodleScreen(childName: 'Ivy', parentName: 'Dad', random: Random(1))));
      await t.drag(find.byKey(const Key('guessDoodleCanvas')), const Offset(60, 40));
      await t.pumpAndSettle();
      await t.tap(find.text('Dad'));
      await t.pumpAndSettle();
      await t.drag(find.byKey(const Key('guessDoodleCanvas')), const Offset(20, 20));
      await t.pumpAndSettle();
      expect(_visibleStrokes(t), hasLength(2));

      await t.tap(find.widgetWithText(OutlinedButton, 'Undo'));
      await t.pumpAndSettle();
      final afterUndo = _visibleStrokes(t);
      expect(afterUndo, hasLength(1));
      expect(afterUndo.single.actorId, 'child');
    });

    testWidgets('once the word is revealed, the canvas stops accepting new strokes', (t) async {
      await t.pumpWidget(wrap(GuessDoodleScreen(random: Random(1))));
      await t.drag(find.byKey(const Key('guessDoodleCanvas')), const Offset(60, 40));
      await t.pumpAndSettle();
      expect(_visibleStrokes(t), hasLength(1));

      await t.tap(find.text('Reveal the word'));
      await t.pumpAndSettle();
      await t.drag(find.byKey(const Key('guessDoodleCanvas')), const Offset(20, 20));
      await t.pumpAndSettle();
      expect(_visibleStrokes(t), hasLength(1), reason: 'drawing is disabled once revealed');
    });
  });

  group('the soft "did you get it?" outcome — never a score, never tallied', () {
    testWidgets('"I got it!" reveals a warm confirmation, no score anywhere', (t) async {
      await t.pumpWidget(wrap(GuessDoodleScreen(random: Random(1))));
      expect(find.byKey(const Key('secretWord')), findsOneWidget);
      await t.tap(find.text('I got it!'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('revealText')), findsOneWidget);
      expect(find.textContaining('Nice — it was'), findsOneWidget);
    });

    testWidgets('"Reveal the word" shows the word without "got it" framing', (t) async {
      await t.pumpWidget(wrap(GuessDoodleScreen(random: Random(1))));
      await t.tap(find.text('Reveal the word'));
      await t.pumpAndSettle();
      expect(find.textContaining('It was "'), findsOneWidget);
      expect(find.textContaining('Nice — it was'), findsNothing);
    });

    testWidgets('"New word — no penalty" picks a genuinely different word, resets the round, '
        'and clears the canvas', (t) async {
      await t.pumpWidget(wrap(GuessDoodleScreen(random: Random(1))));
      final String firstWord = t.widget<Text>(find.byKey(const Key('secretWord'))).data!;
      await t.drag(find.byKey(const Key('guessDoodleCanvas')), const Offset(60, 40));
      await t.pumpAndSettle();
      await t.tap(find.text('Reveal the word'));
      await t.pumpAndSettle();

      await t.tap(find.text('New word — no penalty'));
      await t.pumpAndSettle();

      expect(find.byKey(const Key('revealText')), findsNothing, reason: 'a fresh round is not pre-revealed');
      final String secondWord = t.widget<Text>(find.byKey(const Key('secretWord'))).data!;
      expect(secondWord, isNot(firstWord));
      expect(_visibleStrokes(t), isEmpty, reason: 'a new round starts with a blank canvas');
    });

    testWidgets('none of the forbidden score vocabulary ever appears', (t) async {
      await t.pumpWidget(wrap(GuessDoodleScreen(random: Random(1))));
      await t.tap(find.text('I got it!'));
      await t.pumpAndSettle();
      for (final String word in <String>['score', 'streak', 'rank', 'elo', 'leaderboard', 'win rate', 'points']) {
        expect(find.textContaining(RegExp(word, caseSensitive: false)), findsNothing, reason: word);
      }
    });
  });

  group('device-adaptive layout — a genuine structural difference, not a resize', () {
    testWidgets('at foldCover width (344px) the round panel is a bottom bar', (t) async {
      await t.binding.setSurfaceSize(const Size(344, 882));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(GuessDoodleScreen(random: Random(1))));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('roundBottomBar')), findsOneWidget);
      expect(find.byKey(const Key('roundSidePanel')), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('at a wide posture (900px) the round panel becomes a persistent side panel', (t) async {
      await t.binding.setSurfaceSize(const Size(900, 700));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(GuessDoodleScreen(random: Random(1))));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('roundSidePanel')), findsOneWidget);
      expect(find.byKey(const Key('roundBottomBar')), findsNothing);
      expect(t.takeException(), isNull);
    });
  });

  group('real navigation reachability — child_home.dart\'s onPlay actually reaches this screen', () {
    testWidgets('Play together -> Guess the doodle -> the real GuessDoodleScreen', (t) async {
      // Tall enough that the picker's 6-card grid needs no scrolling to tap
      // a card — the reachability property under test, not scroll mechanics.
      await t.binding.setSurfaceSize(const Size(900, 1600));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(const ChildHome(
        childName: 'Ivy', presence: null, sleepsUntilHandover: 3, unreadCount: 0)));
      await t.tap(find.text('Play together'));
      await t.pumpAndSettle();
      expect(find.byType(GamePickerScreen), findsOneWidget);

      await t.tap(find.text('Guess the doodle'));
      await t.pumpAndSettle();
      expect(find.byType(GuessDoodleScreen), findsOneWidget);
    });
  });
}
