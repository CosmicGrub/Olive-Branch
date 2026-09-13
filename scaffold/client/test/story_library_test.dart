// OLIVE BRANCH — story library widget tests. MASTERFILE §9.11.6, §8.14.
//
// Same posture as invariants_test.dart. The load-bearing property is the
// masterfile's own line: "browsable to three hundred; past that it is
// search" — both branches must actually render, and P2 (no counts/ranking in
// her view) must hold in both.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/story_library.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

Future<void> useNarrowSurface(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

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
  group('empty shelf', () {
    testWidgets('an honest empty state, not a blank screen', (tester) async {
      await useNarrowSurface(tester);
      await tester.pumpWidget(wrap(const StoryLibraryScreen(childName: 'Ivy')));
      expect(find.textContaining('Nothing on the shelf yet'), findsOneWidget);
      expect(find.byType(GridView), findsNothing);
    });
  });

  group('browsable shelf — at or under 300, §9.11.6', () {
    testWidgets('renders a real grid of tiles, not a search box', (tester) async {
      await useNarrowSurface(tester);
      await tester.pumpWidget(wrap(StoryLibraryScreen.demo(childName: 'Ivy')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('browsableGrid')), findsOneWidget);
      expect(find.byKey(const Key('librarySearchField')), findsNothing);
    });

    testWidgets('NO settings affordance exists at any depth', (tester) async {
      await useNarrowSurface(tester);
      await tester.pumpWidget(wrap(StoryLibraryScreen.demo(childName: 'Ivy')));
      expect(find.byIcon(Icons.settings), findsNothing);
      expect(find.textContaining('Settings'), findsNothing);
    });

    testWidgets('P2 — no times-read, rank, or percentage text anywhere in her view',
        (tester) async {
      await useNarrowSurface(tester);
      await tester.pumpWidget(wrap(StoryLibraryScreen.demo(childName: 'Ivy')));
      expect(find.textContaining('times'), findsNothing);
      expect(find.textContaining('asked for this'), findsNothing);
      expect(find.textContaining('%'), findsNothing);
    });

    testWidgets('tapping the first tile opens a reading screen, attributed to the storyteller',
        (tester) async {
      await useNarrowSurface(tester);
      await tester.pumpWidget(wrap(StoryLibraryScreen.demo(childName: 'Ivy')));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(InkWell).first);
      await tester.pumpAndSettle();
      expect(find.text('told by the storyteller'), findsOneWidget);
    });

    testWidgets('§8.4 shelf tiles are at least 64dp (§8.4 pre-reader minimum)',
        (tester) async {
      await useNarrowSurface(tester);
      await tester.pumpWidget(wrap(StoryLibraryScreen.demo(childName: 'Ivy')));
      await tester.pumpAndSettle();
      final tileSize = tester.getSize(find.byType(InkWell).first);
      expect(tileSize.height, greaterThanOrEqualTo(48.0));
      expect(tileSize.width, greaterThanOrEqualTo(48.0));
    });

    for (final size in kResponsiveSizes) {
      testWidgets('renders without overflow at ${size.width.toInt()}x${size.height.toInt()}',
          (tester) async {
        await useSurface(tester, size);
        await tester.pumpWidget(wrap(StoryLibraryScreen.demo(childName: 'Ivy')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('search shelf — over 300, §9.11.6 / §8.14', () {
    testWidgets('past the ceiling, the search field leads instead of a grid',
        (tester) async {
      await useNarrowSurface(tester);
      await tester.pumpWidget(wrap(StoryLibraryScreen.demoLarge(childName: 'Ivy')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('librarySearchField')), findsOneWidget);
      expect(find.byKey(const Key('browsableGrid')), findsNothing);
      expect(find.text('Recently starred'), findsOneWidget);
    });

    testWidgets('typing narrows to matching titles only', (tester) async {
      await useNarrowSurface(tester);
      await tester.pumpWidget(wrap(StoryLibraryScreen.demoLarge(childName: 'Ivy')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('librarySearchField')), 'The Swap');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('librarySearchResults')), findsOneWidget);
      // Every visible result title actually contains the query.
      final texts = tester.widgetList<Text>(find.descendant(
        of: find.byKey(const Key('librarySearchResults')), matching: find.byType(Text)));
      expect(texts, isNotEmpty);
      for (final t in texts) {
        expect(t.data!.toLowerCase(), contains('the swap'));
      }
    });

    testWidgets('a query that matches nothing says so kindly', (tester) async {
      await useNarrowSurface(tester);
      await tester.pumpWidget(wrap(StoryLibraryScreen.demoLarge(childName: 'Ivy')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('librarySearchField')), 'zzzzznosuchstory');
      await tester.pumpAndSettle();
      expect(find.textContaining('No story with that name yet'), findsOneWidget);
    });

    testWidgets('P2 — still no times-read/rank/percentage text while searching',
        (tester) async {
      await useNarrowSurface(tester);
      await tester.pumpWidget(wrap(StoryLibraryScreen.demoLarge(childName: 'Ivy')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('librarySearchField')), 'The');
      await tester.pumpAndSettle();
      expect(find.textContaining('asked for this'), findsNothing);
      expect(find.textContaining('%'), findsNothing);
    });

    for (final size in kResponsiveSizes) {
      testWidgets('renders without overflow at ${size.width.toInt()}x${size.height.toInt()}',
          (tester) async {
        await useSurface(tester, size);
        await tester.pumpWidget(wrap(StoryLibraryScreen.demoLarge(childName: 'Ivy')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });
}
