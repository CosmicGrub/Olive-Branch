// OLIVE BRANCH — game_draw_together.dart tests. MASTERFILE §9.2, §9.12.4,
// §8.11.1, P2.
//
// The property that matters most, mirrored from annotation_canvas_test.dart
// rather than re-derived: a stroke lands under the RIGHT actorId, and undo
// only ever touches the calling actor's OWN strokes. `_visibleStrokes()`
// below reads the CustomPainter's strokes through `InkPainterStrokes` — a
// small, typed, public seam game_draw_together.dart exposes for exactly
// this (its own painter class stays private) — rather than a `dynamic`
// cast, which this repo's analysis_options.yaml opts out of
// (`avoid_dynamic_calls`).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/annotation_canvas.dart';
import 'package:olive_client/child_home.dart';
import 'package:olive_client/game_draw_together.dart';
import 'package:olive_client/game_picker.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

List<Stroke> _visibleStrokes(WidgetTester t) {
  // Scoped to a descendant of the canvas itself, not a bare
  // find.byType(CustomPaint) — Material widgets elsewhere in the tree (e.g.
  // a Scrollbar painting its thumb inside the wide layout's side panel) can
  // legitimately add their own CustomPaint, and this must keep finding THE
  // canvas's painter regardless of how many others exist. Audit-fix
  // (compat-fix pass): AnnotationCanvasView now renders TWO CustomPaint
  // widgets under this key (a RepaintBoundary-wrapped committed layer plus
  // a live layer — see annotation_canvas_view.dart), so this filters down
  // to the one whose painter implements InkPainterStrokes (the committed
  // one) rather than assuming a single match.
  final Iterable<CustomPaint> candidates = t.widgetList<CustomPaint>(
    find.descendant(of: find.byKey(const Key('drawTogetherCanvas')), matching: find.byType(CustomPaint)),
  );
  final CustomPaint cp = candidates.singleWhere((CustomPaint c) => c.painter is InkPainterStrokes);
  final InkPainterStrokes painter = cp.painter! as InkPainterStrokes;
  return painter.strokes;
}

void main() {
  testWidgets('renders by name', (t) async {
    await t.pumpWidget(wrap(const DrawTogetherScreen()));
    expect(find.text('Draw together'), findsOneWidget);
  });

  group('two real actors share one canvas — mirrors annotation_canvas_test.dart', () {
    testWidgets('a stroke drawn by the default active actor lands as "child"', (t) async {
      await t.pumpWidget(wrap(const DrawTogetherScreen()));
      await t.drag(find.byKey(const Key('drawTogetherCanvas')), const Offset(60, 40));
      await t.pumpAndSettle();
      final strokes = _visibleStrokes(t);
      expect(strokes, hasLength(1));
      expect(strokes.single.actorId, 'child');
    });

    testWidgets('switching the active actor attributes the next stroke to "parent"', (t) async {
      await t.pumpWidget(wrap(const DrawTogetherScreen(childName: 'Ivy', parentName: 'Dad')));
      await t.drag(find.byKey(const Key('drawTogetherCanvas')), const Offset(60, 40));
      await t.pumpAndSettle();

      await t.tap(find.text('Dad'));
      await t.pumpAndSettle();
      await t.drag(find.byKey(const Key('drawTogetherCanvas')), const Offset(20, 20));
      await t.pumpAndSettle();

      final strokes = _visibleStrokes(t);
      expect(strokes, hasLength(2));
      expect(strokes[0].actorId, 'child');
      expect(strokes[1].actorId, 'parent');
    });

    testWidgets('undo only ever removes the ACTIVE actor\'s own last stroke — a parent\'s '
        'undo must never erase the child\'s drawing', (t) async {
      await t.pumpWidget(wrap(const DrawTogetherScreen(childName: 'Ivy', parentName: 'Dad')));
      // Child draws first.
      await t.drag(find.byKey(const Key('drawTogetherCanvas')), const Offset(60, 40));
      await t.pumpAndSettle();
      // Switch to parent and draw too.
      await t.tap(find.text('Dad'));
      await t.pumpAndSettle();
      await t.drag(find.byKey(const Key('drawTogetherCanvas')), const Offset(20, 20));
      await t.pumpAndSettle();
      expect(_visibleStrokes(t), hasLength(2));

      // Active actor is still "parent" — undo must remove ONLY the parent's
      // stroke, never the child's already-drawn one.
      await t.tap(find.widgetWithText(OutlinedButton, 'Undo'));
      await t.pumpAndSettle();
      final afterParentUndo = _visibleStrokes(t);
      expect(afterParentUndo, hasLength(1));
      expect(afterParentUndo.single.actorId, 'child');

      // Switching back to child and undoing now removes the child's own
      // stroke — each person's undo is scoped to themselves, not a shared stack.
      await t.tap(find.text('Ivy'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(OutlinedButton, 'Undo'));
      await t.pumpAndSettle();
      expect(_visibleStrokes(t), isEmpty);
    });

    testWidgets('redo restores the active actor\'s own most recently undone stroke', (t) async {
      await t.pumpWidget(wrap(const DrawTogetherScreen()));
      await t.drag(find.byKey(const Key('drawTogetherCanvas')), const Offset(60, 40));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(OutlinedButton, 'Undo'));
      await t.pumpAndSettle();
      expect(_visibleStrokes(t), isEmpty);

      await t.tap(find.widgetWithText(OutlinedButton, 'Redo'));
      await t.pumpAndSettle();
      expect(_visibleStrokes(t), hasLength(1));
    });

    testWidgets('undo past the bottom of history is silence, not an error', (t) async {
      await t.pumpWidget(wrap(const DrawTogetherScreen()));
      await t.tap(find.widgetWithText(OutlinedButton, 'Undo'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(_visibleStrokes(t), isEmpty);
    });
  });

  group('P2 — nothing here counts anything', () {
    testWidgets('none of the forbidden vocabulary appears', (t) async {
      await t.pumpWidget(wrap(const DrawTogetherScreen()));
      for (final String word in <String>['score', 'streak', 'timer', 'finished', 'complete', 'level up', 'win']) {
        expect(find.textContaining(RegExp(word, caseSensitive: false)), findsNothing, reason: word);
      }
    });

    testWidgets('no settings, price, or purchase affordance exists', (t) async {
      await t.pumpWidget(wrap(const DrawTogetherScreen()));
      expect(find.byIcon(Icons.settings), findsNothing);
      expect(find.textContaining('\$'), findsNothing);
      expect(find.textContaining(RegExp('buy|purchase', caseSensitive: false)), findsNothing);
    });
  });

  group('device-adaptive layout — a genuine structural difference, not a resize', () {
    testWidgets('at foldCover width (344px) the tool panel is a bottom bar, not a side panel', (t) async {
      await t.binding.setSurfaceSize(const Size(344, 882));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(const DrawTogetherScreen()));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('toolBottomBar')), findsOneWidget);
      expect(find.byKey(const Key('toolSidePanel')), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('at a wide posture (900px, 2+ columns) the tool panel becomes a persistent '
        'side panel next to the canvas, not the same layout scaled up', (t) async {
      await t.binding.setSurfaceSize(const Size(900, 700));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(const DrawTogetherScreen()));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('toolSidePanel')), findsOneWidget);
      expect(find.byKey(const Key('toolBottomBar')), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('the two layouts are genuinely different widget trees: the layout root is a '
        'Column when narrow and a Row when wide, not the same tree resized', (t) async {
      await t.binding.setSurfaceSize(const Size(344, 882));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(const DrawTogetherScreen()));
      await t.pumpAndSettle();
      expect(t.widget(find.byKey(const Key('layoutRoot'))), isA<Column>());

      await t.binding.setSurfaceSize(const Size(900, 700));
      await t.pumpAndSettle();
      expect(t.widget(find.byKey(const Key('layoutRoot'))), isA<Row>());
    });
  });

  group('real navigation reachability — child_home.dart\'s onPlay actually reaches this screen', () {
    testWidgets('Play together -> Draw together -> the real DrawTogetherScreen', (t) async {
      // Tall enough that the picker's 6-card grid needs no scrolling to tap
      // a card — the reachability property under test, not scroll mechanics.
      await t.binding.setSurfaceSize(const Size(900, 1600));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(const ChildHome(
        childName: 'Ivy', presence: null, sleepsUntilHandover: 3, unreadCount: 0)));
      await t.tap(find.text('Play together'));
      await t.pumpAndSettle();
      expect(find.byType(GamePickerScreen), findsOneWidget);

      await t.tap(find.text('Draw together'));
      await t.pumpAndSettle();
      expect(find.byType(DrawTogetherScreen), findsOneWidget);
    });
  });
}
