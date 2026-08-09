// OLIVE BRANCH -- PRIVATE BUILD ONLY, DO NOT SHIP. Tests for
// lib/private_storybooks/private_storybook_shelf.dart -- see that
// directory's README.md before this branch goes anywhere near a release.
//
// This imports and pumps PrivateStorybookShelfScreen directly, bypassing
// the compile-time kPrivateStorybooksEnabled gate entirely -- on purpose.
// That gate only controls whether child_more.dart's tile is reachable in a
// real build; it says nothing about whether the screen itself works, and a
// compile-time const can't be flipped per-test anyway. See
// child_more_test.dart for the assertion that the gate itself holds.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/private_storybooks/private_storybook_shelf.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

/// MASTERFILE's own mandated minimum widths for a responsive audit: the
/// Fold5's cover screen and its unfolded main screen, plus a standard phone
/// width and a desktop-scale width (§5.20).
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
  // Each test constructs a fresh PrivateStorybookShelfScreen, which calls
  // rootBundle.loadString() on the same manifest key every time.
  // CachingAssetBundle caches that Future for the whole process, and a
  // known flutter_test interaction between that process-lifetime cache and
  // AutomatedTestWidgetsFlutterBinding's per-test zones means a *second*
  // testWidgets case awaiting the same cached key can hang forever even
  // though the value is already resolved. Clearing the bundle between
  // tests forces a fresh (still real, still asset-backed) load each time.
  tearDown(() => rootBundle.clear());

  group('PrivateStorybookShelfScreen', () {
    testWidgets('renders the sample manifest entry as a card', (tester) async {
      await tester.pumpWidget(wrap(const PrivateStorybookShelfScreen()));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('privateStorybookShelfGrid')), findsOneWidget);
      expect(find.textContaining('The Sample Story'), findsOneWidget);
      expect(find.textContaining('placeholder tale'), findsOneWidget);
    });

    testWidgets('no settings affordance on this child-facing screen', (tester) async {
      await tester.pumpWidget(wrap(const PrivateStorybookShelfScreen()));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.settings), findsNothing);
      expect(find.byIcon(Icons.settings_outlined), findsNothing);
      expect(find.textContaining('Settings'), findsNothing);
    });

    testWidgets('tapping the card opens the reader on the same entry', (tester) async {
      await tester.pumpWidget(wrap(const PrivateStorybookShelfScreen()));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(InkWell).first);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('privateStorybookShelfGrid')), findsNothing);
      expect(find.byKey(const Key('privateStorybookReaderScroll')), findsOneWidget);
    });

    for (final size in kResponsiveSizes) {
      testWidgets('renders without overflow at ${size.width.toInt()}x${size.height.toInt()}',
          (tester) async {
        await useSurface(tester, size);
        await tester.pumpWidget(wrap(const PrivateStorybookShelfScreen()));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });
}
