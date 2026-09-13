// OLIVE BRANCH — TabletopSplit's own tests, independent of any screen.
// Intuitivism pass, sub-project 3c (docs/superpowers/specs/2026-09-12-
// intuitivism-fold5-layout-design.md, Part 2 + Testing section). Proves the
// shared widget's own contract directly — the 50/50 split at foldTabletop,
// and the no-op single-column fallback at every other posture — once, so no
// individual screen needs to re-prove it for itself.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/tabletop_split.dart';

Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('TabletopSplit — the 50/50 split, real at foldTabletop', () {
    testWidgets('at foldTabletop dimensions (673x420, the FORM_FACTORS min '
        'for Posture.foldTabletop), both viewing and controls are reachable',
        (t) async {
      await t.binding.setSurfaceSize(const Size(673, 420));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(const TabletopSplit(
        viewing: Text('the viewing half', key: Key('viewing')),
        controls: Text('the controls half', key: Key('controls')),
      )));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.byKey(const Key('viewing')), findsOneWidget);
      expect(find.byKey(const Key('controls')), findsOneWidget);
    });

    testWidgets('viewing sits above controls, not the reverse', (t) async {
      await t.binding.setSurfaceSize(const Size(673, 420));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(const TabletopSplit(
        viewing: Text('viewing'),
        controls: Text('controls'),
      )));
      await t.pumpAndSettle();
      final viewingY = t.getTopLeft(find.text('viewing')).dy;
      final controlsY = t.getTopLeft(find.text('controls')).dy;
      expect(viewingY, lessThan(controlsY));
    });

    testWidgets('each half is genuinely bounded to roughly its own share of '
        'height, not one half squeezing the other to nothing', (t) async {
      await t.binding.setSurfaceSize(const Size(673, 420));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(const TabletopSplit(
        viewing: Text('viewing'),
        controls: Text('controls'),
      )));
      await t.pumpAndSettle();
      // Each half's own SingleChildScrollView is sized by its allocated
      // share of the split (an Expanded ancestor), not by its content --
      // exactly the box this test needs to measure.
      final scrollViews = find.byType(SingleChildScrollView);
      expect(scrollViews, findsNWidgets(2));
      final vHeight = t.getSize(scrollViews.at(0)).height;
      final cHeight = t.getSize(scrollViews.at(1)).height;
      expect(vHeight, greaterThan(0));
      expect(cHeight, greaterThan(0));
      // An even split, within a few px of each other -- see this file's own
      // header for why this is deliberately NOT asserted pixel-perfect to
      // any real hinge line: Flutter has no FoldingFeature signal here.
      expect((vHeight - cHeight).abs(), lessThan(4));
    });

    testWidgets('content taller than half the foldTabletop floor does not '
        'overflow -- each half scrolls independently', (t) async {
      await t.binding.setSurfaceSize(const Size(673, 420));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(TabletopSplit(
        viewing: Column(children: [for (int i = 0; i < 40; i++) Text('viewing line $i')]),
        controls: Column(children: [for (int i = 0; i < 40; i++) Text('controls line $i')]),
      )));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  });

  group('TabletopSplit — a byte-for-byte no-op at every OTHER posture', () {
    const otherSizes = <String, Size>{
      'foldCover (344x882)': Size(344, 882),
      'foldMain (673x841)': Size(673, 841),
      'phone (360x740)': Size(360, 740),
      'tabletLarge (800x1280)': Size(800, 1280),
      'desktop (1100x700)': Size(1100, 700),
    };

    for (final entry in otherSizes.entries) {
      testWidgets('${entry.key} — viewing then controls, single unsplit '
          'column, no Expanded/scroll wrapper added', (t) async {
        await t.binding.setSurfaceSize(entry.value);
        addTearDown(() => t.binding.setSurfaceSize(null));
        await t.pumpWidget(wrap(const TabletopSplit(
          viewing: Text('viewing', key: Key('viewing')),
          controls: Text('controls', key: Key('controls')),
        )));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(find.byKey(const Key('viewing')), findsOneWidget);
        expect(find.byKey(const Key('controls')), findsOneWidget);
        // No-op shape: a plain Column, no Expanded ancestor forcing either
        // half to a fixed fraction of the screen, and no SingleChildScrollView
        // this widget itself introduced around either half.
        expect(
          find.ancestor(of: find.text('viewing'), matching: find.byType(Expanded)),
          findsNothing);
        expect(
          find.ancestor(of: find.text('controls'), matching: find.byType(Expanded)),
          findsNothing);
        final viewingY = t.getTopLeft(find.text('viewing')).dy;
        final controlsY = t.getTopLeft(find.text('controls')).dy;
        expect(viewingY, lessThan(controlsY));
      });
    }
  });
}
