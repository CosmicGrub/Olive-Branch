// OLIVE BRANCH — storyteller screen widget tests. MASTERFILE §9.11.
//
// Same posture as invariants_test.dart: assert against the actual widget
// tree a child sees. The load-bearing property is P1 — nothing on this
// screen ever attributes a story to a parent — plus the general child-shell
// invariants (no settings affordance, 48dp touch targets).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/storyteller_screen.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

/// The narrow branch (single scrolling column) is the one every assertion
/// below relies on — it also happens to be the Fold5 cover-screen width this
/// screen is required to support (§ visual license).
Future<void> useNarrowSurface(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> askForAStory(WidgetTester tester) async {
  await tester.tap(find.text('Tell me a story!'));
  await tester.pumpAndSettle();
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
  group('storyteller — §9.11, §8.1', () {
    testWidgets('opens on the ask card, named for her', (tester) async {
      await useNarrowSurface(tester);
      await tester.pumpWidget(wrap(const StorytellerScreen(childName: 'Ivy')));
      expect(find.text('Want a story, Ivy?'), findsOneWidget);
      expect(find.text('Tell me a story!'), findsOneWidget);
    });

    testWidgets('NO settings affordance exists at any depth', (tester) async {
      await useNarrowSurface(tester);
      await tester.pumpWidget(wrap(const StorytellerScreen(childName: 'Ivy')));
      await askForAStory(tester);
      expect(find.byIcon(Icons.settings), findsNothing);
      expect(find.byIcon(Icons.settings_outlined), findsNothing);
      expect(find.textContaining('Settings'), findsNothing);
    });

    testWidgets('asking for a story shows a reading card attributed to the storyteller',
        (tester) async {
      await useNarrowSurface(tester);
      await tester.pumpWidget(wrap(const StorytellerScreen(childName: 'Ivy')));
      await askForAStory(tester);
      expect(find.byKey(const Key('readingCard')), findsOneWidget);
      expect(find.text('told by the storyteller'), findsOneWidget);
    });

    testWidgets('P1 — the attribution never names a parent as the author', (tester) async {
      await useNarrowSurface(tester);
      await tester.pumpWidget(wrap(const StorytellerScreen(childName: 'Ivy')));
      await askForAStory(tester);
      // Nothing on the reading surface itself claims "Dad" or "Mom" wrote or
      // is speaking this story — the only place those words may appear at
      // all is inside the reassurance dialog explicitly denying it.
      expect(find.text('Dad'), findsNothing);
      expect(find.text('Mom'), findsNothing);
      expect(find.textContaining("Dad's story"), findsNothing);
    });

    testWidgets('tapping the attribution explains the storyteller is not a parent',
        (tester) async {
      await useNarrowSurface(tester);
      await tester.pumpWidget(wrap(const StorytellerScreen(childName: 'Ivy')));
      await askForAStory(tester);
      await tester.tap(find.text('told by the storyteller'));
      await tester.pumpAndSettle();
      expect(find.text('Who tells these stories?'), findsOneWidget);
      expect(find.textContaining('Not Mum, not Dad'), findsOneWidget);
      await tester.tap(find.text('Okay!'));
      await tester.pumpAndSettle();
    });

    testWidgets('her line (the refrain) is visually marked as HER line', (tester) async {
      await useNarrowSurface(tester);
      await tester.pumpWidget(wrap(const StorytellerScreen(childName: 'Ivy')));
      await askForAStory(tester);
      // The grammar always places the first refrain at block index 4 —
      // storyteller_logic_test.dart pins this exact structural fact.
      for (int i = 0; i < 4; i++) {
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
      }
      expect(find.text('YOUR LINE!'), findsOneWidget);
    });

    testWidgets('Back is disabled on the first line; Next reaches "The end" after 11 taps',
        (tester) async {
      await useNarrowSurface(tester);
      await tester.pumpWidget(wrap(const StorytellerScreen(childName: 'Ivy')));
      await askForAStory(tester);

      final back = tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Back'));
      expect(back.onPressed, isNull);

      // The grammar always emits exactly 12 lines regardless of seed.
      for (int i = 0; i < 11; i++) {
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
      }
      expect(find.text('The end'), findsOneWidget);
      expect(find.text('Another story!'), findsOneWidget);
      // The bookmark affordance is structurally gone on the last line — a
      // bookmark there is refused by library_logic.dart, so the UI never
      // offers it in the first place.
      expect(find.text('Stop here for tonight'), findsNothing);
    });

    testWidgets('starring toggles the icon and adds a chip to the shelf', (tester) async {
      await useNarrowSurface(tester);
      await tester.pumpWidget(wrap(const StorytellerScreen(childName: 'Ivy')));
      await askForAStory(tester);

      final readingCard = find.byKey(const Key('readingCard'));
      expect(find.descendant(of: readingCard, matching: find.byIcon(Icons.star_border_rounded)),
        findsOneWidget);
      await tester.tap(find.descendant(of: readingCard, matching: find.byIcon(Icons.star_border_rounded)));
      await tester.pump();
      expect(find.descendant(of: readingCard, matching: find.byIcon(Icons.star_rounded)),
        findsOneWidget);
      expect(find.text('Your starred stories'), findsOneWidget);

      // Unstar removes it again.
      await tester.tap(find.descendant(of: readingCard, matching: find.byIcon(Icons.star_rounded)));
      await tester.pump();
      expect(find.text('Your starred stories'), findsNothing);
    });

    testWidgets('bookmarking mid-story adds an entry under "Left off partway"',
        (tester) async {
      await useNarrowSurface(tester);
      await tester.pumpWidget(wrap(const StorytellerScreen(childName: 'Ivy')));
      await askForAStory(tester);
      await tester.tap(find.text('Stop here for tonight'));
      await tester.pump();
      expect(find.text('Left off partway'), findsOneWidget);
      expect(find.text('Pick up right where you stopped'), findsOneWidget);
    });

    testWidgets('resuming a bookmark recaps her line and lands back on that story',
        (tester) async {
      await useNarrowSurface(tester);
      await tester.pumpWidget(wrap(const StorytellerScreen(childName: 'Ivy')));
      await askForAStory(tester);
      // Get past the first refrain (index 4) so the resume has something to
      // recap, then stop for the night at index 5.
      for (int i = 0; i < 5; i++) {
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Stop here for tonight'));
      await tester.pump();

      await tester.tap(find.text('Pick up right where you stopped'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Last time, her line was'), findsOneWidget);
      expect(find.text('YOUR LINE!'), findsNothing); // resumed AFTER the refrain, not on it
    });

    testWidgets('§8.4 the ask button and the star control are at least 48dp', (tester) async {
      await useNarrowSurface(tester);
      await tester.pumpWidget(wrap(const StorytellerScreen(childName: 'Ivy')));
      final askSize = tester.getSize(find.widgetWithText(FilledButton, 'Tell me a story!'));
      expect(askSize.height, greaterThanOrEqualTo(48.0));

      await askForAStory(tester);
      final starSize = tester.getSize(find.byType(IconButton).first);
      expect(starSize.height, greaterThanOrEqualTo(48.0));
      expect(starSize.width, greaterThanOrEqualTo(48.0));

      final attributionSize = tester.getSize(find.text('told by the storyteller'));
      // The pill's own hit area (its InkWell ancestor) is what must clear
      // 48dp, not the label glyph itself.
      final hitArea = tester.getSize(find.ancestor(
        of: find.text('told by the storyteller'), matching: find.byType(InkWell)).first);
      expect(hitArea.height, greaterThanOrEqualTo(48.0));
      expect(attributionSize.height, lessThanOrEqualTo(hitArea.height));
    });

    testWidgets('no error copy is ever shown on this surface', (tester) async {
      await useNarrowSurface(tester);
      await tester.pumpWidget(wrap(const StorytellerScreen(childName: 'Ivy')));
      await askForAStory(tester);
      expect(find.textContaining('Error'), findsNothing);
      expect(find.textContaining('error'), findsNothing);
      expect(find.textContaining('failed'), findsNothing);
    });
  });

  group('responsive — Fold5 cover/main, phone, and desktop-scale widths', () {
    for (final size in kResponsiveSizes) {
      final String label = '${size.width.toInt()}x${size.height.toInt()}';
      testWidgets('the ask card renders without overflow at $label', (tester) async {
        await useSurface(tester, size);
        await tester.pumpWidget(wrap(const StorytellerScreen(childName: 'Ivy')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });

      testWidgets('the reading card renders without overflow at $label', (tester) async {
        await useSurface(tester, size);
        await tester.pumpWidget(wrap(const StorytellerScreen(childName: 'Ivy')));
        await askForAStory(tester);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('storyteller safety — §15, P1', () {
    testWidgets('states plainly that no synthetic parent voice is ever used', (tester) async {
      await tester.pumpWidget(wrap(const StorytellerSafetyScreen()));
      expect(find.text('About the storyteller'), findsOneWidget);
      expect(find.textContaining('It never sounds like you'), findsOneWidget);
      expect(find.textContaining('will not generate audio or video of a'), findsOneWidget);
    });

    testWidgets('states the never-about-her-parents guarantee', (tester) async {
      await tester.pumpWidget(wrap(const StorytellerSafetyScreen()));
      expect(find.textContaining('It stays away from the two of you'), findsOneWidget);
    });
  });
}
