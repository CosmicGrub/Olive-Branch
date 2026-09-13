// OLIVE BRANCH — colouring_screen.dart tests. MASTERFILE §8.13.
//
// "The fill is a consequence — it spreads from the tap rather than
// cutting." This file mostly asserts the P2 negative space and the
// interaction surface; the actual per-pixel fill/animation is exercised
// indirectly (CustomPaint content isn't introspectable from a widget test
// without a golden image, which this project's tooling can't run either —
// see verify.sh's own "no Flutter toolchain" caveat repeated at the top of
// every UNVERIFIED file).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/colouring_screen.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

/// MASTERFILE's own mandated minimum widths for a responsive audit: the
/// Fold5's cover screen and its unfolded main screen, plus a standard phone
/// width and a desktop-scale width now that Windows is a real target (§5.20).
const List<Size> kResponsiveSizes = <Size>[
  Size(344, 820), // Fold5 cover screen
  Size(673, 841), // Fold5 main screen, unfolded
  Size(390, 844), // standard phone
  Size(1100, 900), // tablet / desktop-scale, short-and-wide
];

Future<void> useSurface(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets('renders the colouring page by name', (t) async {
    await t.pumpWidget(wrap(const ColouringScreen()));
    expect(find.text('Colouring'), findsOneWidget);
  });

  testWidgets('no settings affordance exists', (t) async {
    await t.pumpWidget(wrap(const ColouringScreen()));
    expect(find.byIcon(Icons.settings), findsNothing);
  });

  testWidgets('no score, timer, streak, or completion vocabulary anywhere', (t) async {
    await t.pumpWidget(wrap(const ColouringScreen()));
    for (final String word in <String>['score', 'streak', 'timer', 'finished', 'complete', 'you win']) {
      expect(find.textContaining(RegExp(word, caseSensitive: false)), findsNothing, reason: word);
    }
  });

  testWidgets('no financial or purchase surface exists (P4/P6)', (t) async {
    await t.pumpWidget(wrap(const ColouringScreen()));
    expect(find.textContaining('\$'), findsNothing);
    expect(find.textContaining(RegExp('price|buy|purchase', caseSensitive: false)), findsNothing);
  });

  testWidgets('a tap on the scene and "Start over" do not throw', (t) async {
    await t.pumpWidget(wrap(const ColouringScreen()));
    await t.tapAt(const Offset(200, 200));
    await t.pump(const Duration(milliseconds: 450));
    await t.pumpAndSettle();
    await t.tap(find.text('Start over'));
    await t.pumpAndSettle();
    expect(find.byType(ColouringScreen), findsOneWidget);
  });

  testWidgets('palette swatches meet the 48dp minimum touch target', (t) async {
    await t.pumpWidget(wrap(const ColouringScreen()));
    // Scoped to the circular palette swatches specifically — a plain
    // `find.byType(InkWell)` would also catch InkWells belonging to
    // ordinary Material buttons ("Start over"), which satisfy 48dp through
    // Flutter's own invisible tap-target padding rather than their own
    // render box, and would make this assertion measure the wrong thing.
    final List<Element> swatchInkWells = find
        .byWidgetPredicate((w) => w is InkWell && w.customBorder is CircleBorder)
        .evaluate()
        .toList();
    expect(swatchInkWells, isNotEmpty);
    for (final Element e in swatchInkWells) {
      final RenderBox box = e.renderObject! as RenderBox;
      expect(box.size.width, greaterThanOrEqualTo(48));
      expect(box.size.height, greaterThanOrEqualTo(48));
    }
  });

  group('responsive — Fold5 cover/main, phone, and desktop-scale widths', () {
    for (final size in kResponsiveSizes) {
      testWidgets('renders without overflow at ${size.width.toInt()}x${size.height.toInt()}',
          (t) async {
        await useSurface(t, size);
        await t.pumpWidget(wrap(const ColouringScreen()));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      });
    }
  });
}
