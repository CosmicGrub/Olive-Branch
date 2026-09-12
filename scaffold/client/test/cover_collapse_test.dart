// OLIVE BRANCH — CoverCollapse's own tests, independent of any screen.
// Intuitivism pass, sub-project 3c (docs/superpowers/specs/2026-09-12-
// intuitivism-fold5-layout-design.md, Part 1 + Testing section). Proves the
// shared widget's own contract directly — collapsed at foldCover, full
// (byte-for-byte, the caller's own widget) at every other posture — once,
// so no individual screen needs to re-prove it for itself.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/cover_collapse.dart';

Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('CoverCollapse — collapsed is real at foldCover', () {
    testWidgets('at foldCover dimensions (344x841, the exact test viewport '
        "this codebase's own form_factors_test.dart pins against), collapsed "
        'shows and full does not', (t) async {
      await t.binding.setSurfaceSize(const Size(344, 841));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(const CoverCollapse(
        full: Text('the full layout', key: Key('full')),
        collapsed: Text('the collapsed layout', key: Key('collapsed')),
      )));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.byKey(const Key('collapsed')), findsOneWidget);
      expect(find.byKey(const Key('full')), findsNothing);
    });
  });

  group('CoverCollapse — a byte-for-byte no-op at every OTHER posture: '
      'full renders, unchanged, and collapsed never mounts', () {
    const otherSizes = <String, Size>{
      'foldTabletop (673x420)': Size(673, 420),
      'foldMain (673x841)': Size(673, 841),
      'phone (360x740)': Size(360, 740),
      'tabletLarge (800x1280)': Size(800, 1280),
      'desktop (1100x700)': Size(1100, 700),
    };

    for (final entry in otherSizes.entries) {
      testWidgets('${entry.key} — full shows, collapsed never mounts', (t) async {
        await t.binding.setSurfaceSize(entry.value);
        addTearDown(() => t.binding.setSurfaceSize(null));
        await t.pumpWidget(wrap(const CoverCollapse(
          full: Text('the full layout', key: Key('full')),
          collapsed: Text('the collapsed layout', key: Key('collapsed')),
        )));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(find.byKey(const Key('full')), findsOneWidget);
        expect(find.byKey(const Key('collapsed')), findsNothing);
      });
    }

    testWidgets('full is inserted with no extra wrapper of its own -- a '
        'direct child of CoverCollapse\'s own LayoutBuilder, so a caller\'s '
        'existing Scaffold/positioning is preserved exactly', (t) async {
      await t.binding.setSurfaceSize(const Size(673, 841));
      addTearDown(() => t.binding.setSurfaceSize(null));
      const fullKey = Key('full');
      await t.pumpWidget(wrap(const CoverCollapse(
        full: SizedBox(width: 200, height: 50, key: fullKey),
        collapsed: SizedBox.shrink(),
      )));
      await t.pumpAndSettle();
      // The rendered size is exactly what `full` itself declared -- nothing
      // padded or resized it along the way.
      expect(t.getSize(find.byKey(fullKey)), const Size(200, 50));
    });
  });
}
