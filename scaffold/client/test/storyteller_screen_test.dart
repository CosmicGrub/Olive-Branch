// OLIVE BRANCH — storyteller screen widget tests. MASTERFILE §9.11.
//
// Same posture as invariants_test.dart: assert against the actual widget
// tree a child sees. The load-bearing property is P1 — nothing on this
// screen ever attributes a story to a parent — plus the general child-shell
// invariants (no settings affordance, 48dp touch targets).
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/contact_labels.dart';
import 'package:olive_client/grownup_labels.dart';
import 'package:olive_client/library_logic.dart';
import 'package:olive_client/storyteller_screen.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

/// Which story every non-sweep test reads. The screen used to pick one at random, so a run that landed on a long
/// story had its buttons below the 900 px test surface and a bare tap missed (a flake with no name). The same story
/// every run makes a failure reproducible; the sweep at the end of this file covers the variety.
const int kStoryTestSeed = 7;

/// Scrolls [finder] into view, then taps it. A tap at a position the viewport does not show lands on nothing.
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
}

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
      await tester.pumpWidget(wrap(StorytellerScreen(childName: 'Ivy', random: Random(kStoryTestSeed))));
      expect(find.text('Want a story, Ivy?'), findsOneWidget);
      expect(find.text('Tell me a story!'), findsOneWidget);
    });

    testWidgets('NO settings affordance exists at any depth', (tester) async {
      await useNarrowSurface(tester);
      await tester.pumpWidget(wrap(StorytellerScreen(childName: 'Ivy', random: Random(kStoryTestSeed))));
      await askForAStory(tester);
      expect(find.byIcon(Icons.settings), findsNothing);
      expect(find.byIcon(Icons.settings_outlined), findsNothing);
      expect(find.textContaining('Settings'), findsNothing);
    });

    testWidgets('asking for a story shows a reading card attributed to the storyteller',
        (tester) async {
      await useNarrowSurface(tester);
      await tester.pumpWidget(wrap(StorytellerScreen(childName: 'Ivy', random: Random(kStoryTestSeed))));
      await askForAStory(tester);
      expect(find.byKey(const Key('readingCard')), findsOneWidget);
      expect(find.text('told by the storyteller'), findsOneWidget);
    });

    testWidgets('P1 — the attribution never names a parent as the author', (tester) async {
      await useNarrowSurface(tester);
      await tester.pumpWidget(wrap(StorytellerScreen(childName: 'Ivy', random: Random(kStoryTestSeed))));
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
      await tester.pumpWidget(wrap(StorytellerScreen(childName: 'Ivy', random: Random(kStoryTestSeed))));
      await askForAStory(tester);
      await tapVisible(tester, find.text('told by the storyteller'));
      await tester.pumpAndSettle();
      expect(find.text('Who tells these stories?'), findsOneWidget);
      expect(find.textContaining("Not a grown-up — it's the storyteller"), findsOneWidget);
      await tapVisible(tester, find.text('Okay!'));
      await tester.pumpAndSettle();
    });

    testWidgets('the same reassurance names her grown-ups in HER words when a family is known', (tester) async {
      await useNarrowSurface(tester);
      const GrownupLabels labels = GrownupLabels(
        contacts: <GrownupContact>[
          GrownupContact(id: 'a', guardianLabel: 'Dad', kind: GrownupKind.dad),
          GrownupContact(id: 'b', guardianLabel: 'Mom', kind: GrownupKind.mom),
        ],
        age: AgeLockState(age: 9, locked: true),
        nicknames: <String, String>{'a': 'Dada'},
      );
      await tester.pumpWidget(wrap(GrownupLabelScope(labels: labels, child: StorytellerScreen(childName: 'Ivy', random: Random(kStoryTestSeed)))));
      await askForAStory(tester);
      await tapVisible(tester, find.text('told by the storyteller'));
      await tester.pumpAndSettle();
      expect(find.textContaining("Not Dada, not Mommy — it's the storyteller"), findsOneWidget);
    });

    testWidgets('her line (the refrain) is visually marked as HER line', (tester) async {
      await useNarrowSurface(tester);
      await tester.pumpWidget(wrap(StorytellerScreen(childName: 'Ivy', random: Random(kStoryTestSeed))));
      await askForAStory(tester);
      // The grammar always places the first refrain at block index 4 —
      // storyteller_logic_test.dart pins this exact structural fact.
      for (int i = 0; i < 4; i++) {
        await tapVisible(tester, find.text('Next'));
        await tester.pumpAndSettle();
      }
      expect(find.text('YOUR LINE!'), findsOneWidget);
    });

    testWidgets('Back is disabled on the first line; Next reaches "The end" after 11 taps',
        (tester) async {
      await useNarrowSurface(tester);
      await tester.pumpWidget(wrap(StorytellerScreen(childName: 'Ivy', random: Random(kStoryTestSeed))));
      await askForAStory(tester);

      final back = tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Back'));
      expect(back.onPressed, isNull);

      // The grammar always emits exactly 12 lines regardless of seed.
      for (int i = 0; i < 11; i++) {
        await tapVisible(tester, find.text('Next'));
        await tester.pumpAndSettle();
      }
      expect(find.text('The end'), findsOneWidget);
      expect(find.text('Another story!'), findsOneWidget);
      // The bookmark affordance is structurally gone on the last line — a
      // bookmark there is refused by library_logic.dart, so the UI never
      // offers it in the first place.
      expect(find.text('Stop here for tonight'), findsNothing);
    });

    testWidgets('the turn-row/"The end" swap is a real completion moment, not an instant cut',
        (tester) async {
      await useNarrowSurface(tester);
      await tester.pumpWidget(wrap(StorytellerScreen(childName: 'Ivy', random: Random(kStoryTestSeed))));
      await askForAStory(tester);

      expect(find.byKey(const ValueKey('turnRow')), findsOneWidget);
      expect(find.byKey(const ValueKey('theEnd')), findsNothing);

      for (int i = 0; i < 11; i++) {
        await tapVisible(tester, find.text('Next'));
        await tester.pumpAndSettle();
      }
      // Reached the end: the turn controls are gone, "The end" is in, and
      // pumpAndSettle above already proves the crossfade settles cleanly
      // rather than hanging mid-animation.
      expect(find.byKey(const ValueKey('turnRow')), findsNothing);
      expect(find.byKey(const ValueKey('theEnd')), findsOneWidget);
    });

    testWidgets('starring toggles the icon and adds a chip to the shelf', (tester) async {
      await useNarrowSurface(tester);
      await tester.pumpWidget(wrap(StorytellerScreen(childName: 'Ivy', random: Random(kStoryTestSeed))));
      await askForAStory(tester);

      final readingCard = find.byKey(const Key('readingCard'));
      expect(find.descendant(of: readingCard, matching: find.byIcon(Icons.star_border_rounded)),
        findsOneWidget);
      await tapVisible(tester, find.descendant(of: readingCard, matching: find.byIcon(Icons.star_border_rounded)));
      await tester.pump();
      expect(find.descendant(of: readingCard, matching: find.byIcon(Icons.star_rounded)),
        findsOneWidget);
      expect(find.text('Your starred stories'), findsOneWidget);

      // Unstar removes it again.
      await tapVisible(tester, find.descendant(of: readingCard, matching: find.byIcon(Icons.star_rounded)));
      await tester.pump();
      expect(find.text('Your starred stories'), findsNothing);
    });

    testWidgets('a starred-story chip never overflows, even for the longest '
        'shapeTitles entry, on the narrowest required width — regression '
        'for the flaky RenderFlex overflow freshStory\'s random title length '
        'could intermittently trigger here', (tester) async {
      await useNarrowSurface(tester);
      await tester.pumpWidget(wrap(StorytellerScreen(childName: 'Ivy', random: Random(kStoryTestSeed),
        initialFavourites: [
          const Favourite(code: 'the_thing_that_was_lost', title: 'The Thing That Was Lost',
            starredAt: '2026-01-01T00:00:00.000Z', timesRead: 1),
        ])));
      await tester.pump();
      expect(find.text('Your starred stories'), findsOneWidget);
      expect(find.textContaining('The Thing That Was Lost'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('bookmarking mid-story adds an entry under "Left off partway"',
        (tester) async {
      await useNarrowSurface(tester);
      await tester.pumpWidget(wrap(StorytellerScreen(childName: 'Ivy', random: Random(kStoryTestSeed))));
      await askForAStory(tester);
      await tapVisible(tester, find.text('Stop here for tonight'));
      await tester.pump();
      expect(find.text('Left off partway'), findsOneWidget);
      expect(find.text('Pick up right where you stopped'), findsOneWidget);
    });

    testWidgets('resuming a bookmark recaps her line and lands back on that story',
        (tester) async {
      await useNarrowSurface(tester);
      await tester.pumpWidget(wrap(StorytellerScreen(childName: 'Ivy', random: Random(kStoryTestSeed))));
      await askForAStory(tester);
      // Get past the first refrain (index 4) so the resume has something to
      // recap, then stop for the night at index 5.
      for (int i = 0; i < 5; i++) {
        await tapVisible(tester, find.text('Next'));
        await tester.pumpAndSettle();
      }
      await tapVisible(tester, find.text('Stop here for tonight'));
      await tester.pump();

      await tapVisible(tester, find.text('Pick up right where you stopped'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Last time, her line was'), findsOneWidget);
      expect(find.text('YOUR LINE!'), findsNothing); // resumed AFTER the refrain, not on it
    });

    // Design spec: docs/superpowers/specs/2026-09-15-design-tokens-named-
    // migration-design.md, Fix #4 — the bookmark row migrated from a bare
    // Card+ListTile onto HubTile (hub_widgets.dart), which needed a new
    // optional [trailing] slot (see that widget's own header) to carry the
    // "remove bookmark" action HubTile's plain icon/title/subtitle/onTap
    // shape has no room for. Chrome-only migration — this proves that real
    // action still works, not just the tap-to-resume destination the test
    // above already covers.
    testWidgets('the trailing "Remove bookmark" button still clears the '
        'bookmark after the HubTile migration', (tester) async {
      await useNarrowSurface(tester);
      await tester.pumpWidget(wrap(StorytellerScreen(childName: 'Ivy', random: Random(kStoryTestSeed))));
      await askForAStory(tester);
      await tapVisible(tester, find.text('Stop here for tonight'));
      await tester.pump();
      expect(find.text('Left off partway'), findsOneWidget);

      await tapVisible(tester, find.byTooltip('Remove bookmark'));
      await tester.pump();
      expect(find.text('Left off partway'), findsNothing);
    });

    testWidgets('rereading an unstarred story twice nudges her to star it — once, not '
        'on every reread after', (tester) async {
      await useNarrowSurface(tester);
      await tester.pumpWidget(wrap(StorytellerScreen(childName: 'Ivy', random: Random(kStoryTestSeed))));
      await askForAStory(tester);
      await tapVisible(tester, find.text('Stop here for tonight'));
      await tester.pump();

      // Never starred — confirm before relying on that below.
      expect(find.byIcon(Icons.star_rounded), findsNothing);

      // First reread (count=1): storyArtifact()'s own timesRead>=2 threshold
      // isn't met yet, so no nudge.
      await tapVisible(tester, find.text('Pick up right where you stopped'));
      await tester.pumpAndSettle();
      expect(find.textContaining('star it to keep it close'), findsNothing);

      // Bookmark isn't cleared by resuming — tap it again for a second
      // reread (count=2), which crosses the threshold.
      await tapVisible(tester, find.text('Pick up right where you stopped'));
      await tester.pumpAndSettle();
      expect(find.textContaining('star it to keep it close'), findsOneWidget);
      // Let the 4-second SnackBar actually finish dismissing (pumpAndSettle
      // alone doesn't wait out a real-time auto-dismiss Timer with no
      // animation frame scheduled in between) before the next check.
      await tester.pump(const Duration(seconds: 5));

      // A third reread of the SAME story must not nudge again.
      await tapVisible(tester, find.text('Pick up right where you stopped'));
      await tester.pumpAndSettle();
      expect(find.textContaining('star it to keep it close'), findsNothing);
    });

    testWidgets('an already-starred story is never nudged — she already said it\'s a keeper',
        (tester) async {
      await useNarrowSurface(tester);
      await tester.pumpWidget(wrap(StorytellerScreen(childName: 'Ivy', random: Random(kStoryTestSeed))));
      await askForAStory(tester);
      await tapVisible(tester, find.text('Stop here for tonight'));
      await tester.pump();
      await tapVisible(tester, find.byIcon(Icons.star_border_rounded)); // star it
      await tester.pump();

      await tapVisible(tester, find.text('Pick up right where you stopped'));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Pick up right where you stopped'));
      await tester.pumpAndSettle();
      expect(find.textContaining('star it to keep it close'), findsNothing);
    });

    testWidgets('§8.4 the ask button and the star control are at least 48dp', (tester) async {
      await useNarrowSurface(tester);
      await tester.pumpWidget(wrap(StorytellerScreen(childName: 'Ivy', random: Random(kStoryTestSeed))));
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
      await tester.pumpWidget(wrap(StorytellerScreen(childName: 'Ivy', random: Random(kStoryTestSeed))));
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
        await tester.pumpWidget(wrap(StorytellerScreen(childName: 'Ivy', random: Random(kStoryTestSeed))));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });

      testWidgets('the reading card renders without overflow at $label', (tester) async {
        await useSurface(tester, size);
        await tester.pumpWidget(wrap(StorytellerScreen(childName: 'Ivy', random: Random(kStoryTestSeed))));
        await askForAStory(tester);
        expect(tester.takeException(), isNull);
      });
    }
  });

  // ISS-027. Every control a child needs must be reachable on every story the screen can pick, at the narrowest
  // required width (390 x 900) and at the largest text scale (2.0): scrolling brings it fully inside the surface,
  // it is at least 48 dp, and nothing overflows. 50 seeds, each walked from the first page to "The end".
  group('reachability sweep — 50 seeds at 390x900 and 2.0x text', () {
    const Size surface = Size(390, 900);
    Widget scaled(Widget child) => MaterialApp(
          builder: (context, c) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2.0)), child: c!),
          home: child,
        );

    Future<void> reach(WidgetTester t, Finder f, String what, int seed) async {
      expect(f, findsOneWidget, reason: 'seed $seed: $what is on the page');
      await t.ensureVisible(f);
      await t.pump();
      final Rect r = t.getRect(f);
      expect(r.top >= 0 && r.bottom <= surface.height && r.left >= 0 && r.right <= surface.width, isTrue,
          reason: 'seed $seed: $what after scrolling is inside the surface, got $r');
      expect(r.height, greaterThanOrEqualTo(48.0 - 0.01), reason: 'seed $seed: $what is a 48 dp target');
    }

    testWidgets('every control is reachable on the first page, every middle page and the last, for 50 seeds',
        (t) async {
      t.view.physicalSize = surface;
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      for (int seed = 0; seed < 50; seed++) {
        await t.pumpWidget(scaled(StorytellerScreen(key: ValueKey(seed), childName: 'Ivy', random: Random(seed))));
        await t.pumpAndSettle();
        await t.tap(find.text('Tell me a story!'));
        await t.pumpAndSettle();
        int pages = 0;
        while (find.text('Another story!').evaluate().isEmpty) {
          pages++;
          expect(pages, lessThan(40), reason: 'seed $seed: the story ends');
          await reach(t, find.widgetWithText(FilledButton, 'Next'), 'Next', seed);
          await reach(t, find.widgetWithText(TextButton, 'Stop here for tonight'), 'Stop here for tonight', seed);
          await t.tap(find.widgetWithText(FilledButton, 'Next'));
          await t.pumpAndSettle();
          expect(t.takeException(), isNull, reason: 'seed $seed page $pages: no overflow');
        }
        await reach(t, find.widgetWithText(FilledButton, 'Another story!'), 'Another story!', seed);
        expect(t.takeException(), isNull, reason: 'seed $seed: the last page does not overflow');
      }
    });

    testWidgets('a story code opens exactly that story, so a layout can be reproduced', (t) async {
      t.view.physicalSize = surface;
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      await t.pumpWidget(wrap(StorytellerScreen(childName: 'Ivy', random: Random(1))));
      await t.tap(find.text('Tell me a story!'));
      await t.pumpAndSettle();
      final String code = RegExp(r'Story code · (\w+)')
          .firstMatch(t.widgetList<Text>(find.textContaining('Story code')).first.data!)!.group(1)!;
      await t.pumpWidget(wrap(StorytellerScreen(key: UniqueKey(), childName: 'Ivy', storyCode: code, random: Random(99))));
      await t.tap(find.text('Tell me a story!'));
      await t.pumpAndSettle();
      expect(find.text('Story code · $code'), findsOneWidget);
    });
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
