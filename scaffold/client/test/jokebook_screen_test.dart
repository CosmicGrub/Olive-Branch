// OLIVE BRANCH — jokebook screen widget tests. MASTERFILE §9.2.
//
// Same posture as storyteller_screen_test.dart: assert against the actual
// widget tree a child sees. The load-bearing properties are the beat (the
// punchline is genuinely absent from the tree until she taps, not merely
// hidden), the age floor (a four-year-old's screen never shows a 5+ joke),
// P2 (no counts, no streaks, anywhere), and the general child-shell
// invariants (no settings affordance, 48dp touch targets).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/game_picker.dart';
import 'package:olive_client/joke_logic.dart';
import 'package:olive_client/jokebook_screen.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

Future<void> useNarrowSurface(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// MASTERFILE's own mandated minimum widths for a responsive audit.
const responsiveSizes = <Size>[
  Size(344, 820), // Fold5 cover screen
  Size(673, 841), // Fold5 main screen, unfolded
  Size(390, 844), // standard phone
  Size(1100, 900), // tablet / desktop-scale, short-and-wide
];

Future<void> tellMeOne(WidgetTester tester) async {
  await tester.tap(find.text('Tell me one!'));
  await tester.pumpAndSettle();
}

Future<void> reveal(WidgetTester tester) async {
  await tester.tap(find.text('Tap for the punchline'));
  await tester.pumpAndSettle();
}

/// The one joke on screen right now, looked up by the setup text rendered.
Joke currentJoke(WidgetTester tester) {
  final setup = tester.widget<Text>(find.byKey(const Key('jokeSetup'))).data!;
  return kJokeCatalogue.firstWhere((j) => j.setup == setup);
}

void main() {
  group('the beat', () {
    testWidgets('opens on an ask card with the real call to action', (tester) async {
      await useNarrowSurface(tester);
      await tester.pumpWidget(wrap(const JokebookScreen(childName: 'Ivy')));
      expect(find.text('Want a joke, Ivy?'), findsOneWidget);
      expect(find.text('Tell me one!'), findsOneWidget);
      expect(find.byKey(const Key('jokeCard')), findsNothing);
    });

    testWidgets('after asking, the setup shows and the punchline is genuinely absent from the tree',
        (tester) async {
      await useNarrowSurface(tester);
      await tester.pumpWidget(wrap(JokebookScreen(childName: 'Ivy', pick: () => 0)));
      await tellMeOne(tester);
      final joke = currentJoke(tester);
      expect(find.text(joke.setup), findsOneWidget);
      expect(find.text(joke.punchline), findsNothing);
      expect(find.byKey(const Key('jokePunchline')), findsNothing);
      expect(find.text('Tap for the punchline'), findsOneWidget);
      // Nothing to move on to until she has heard the ending.
      expect(find.text('Tell me another!'), findsNothing);
    });

    testWidgets('tapping reveals the punchline and only then offers another', (tester) async {
      await useNarrowSurface(tester);
      await tester.pumpWidget(wrap(JokebookScreen(childName: 'Ivy', pick: () => 0)));
      await tellMeOne(tester);
      final joke = currentJoke(tester);
      await reveal(tester);
      expect(find.text(joke.punchline), findsOneWidget);
      expect(find.text('Tap for the punchline'), findsNothing);
      expect(find.text('Tell me another!'), findsOneWidget);
    });

    testWidgets('"Tell me another!" never repeats the one she just heard', (tester) async {
      await useNarrowSurface(tester);
      // pick 0 always takes the first eligible joke — so the only way the
      // second draw differs is if the exclusion is real.
      await tester.pumpWidget(wrap(JokebookScreen(childName: 'Ivy', pick: () => 0)));
      await tellMeOne(tester);
      final first = currentJoke(tester);
      await reveal(tester);
      await tester.tap(find.text('Tell me another!'));
      await tester.pumpAndSettle();
      final second = currentJoke(tester);
      expect(second.id, isNot(first.id));
      // And the new one is hidden again — the beat resets every time.
      expect(find.text(second.punchline), findsNothing);
    });
  });

  group('the age floor — invisible, like game_picker.dart\'s', () {
    testWidgets('a four-year-old never sees a 5+ joke across many draws', (tester) async {
      await useNarrowSurface(tester);
      await tester.pumpWidget(wrap(const JokebookScreen(childName: 'Ivy', childAge: 4)));
      await tellMeOne(tester);
      for (var i = 0; i < 25; i++) {
        expect(currentJoke(tester).minAge, lessThanOrEqualTo(4), reason: 'draw $i');
        await reveal(tester);
        await tester.tap(find.text('Tell me another!'));
        await tester.pumpAndSettle();
      }
    });

    testWidgets('a twelve-year-old can reach the whole book', (tester) async {
      await useNarrowSurface(tester);
      // pick just under 1.0 lands on the LAST eligible joke — the 12+ one.
      await tester.pumpWidget(wrap(JokebookScreen(childName: 'Ivy', childAge: 12, pick: () => 0.999)));
      await tellMeOne(tester);
      expect(currentJoke(tester).minAge, 12);
    });
  });

  group('favourites — P2', () {
    testWidgets('starring shows the shelf; the chip reopens that joke already revealed', (tester) async {
      await useNarrowSurface(tester);
      await tester.pumpWidget(wrap(JokebookScreen(childName: 'Ivy', pick: () => 0)));
      await tellMeOne(tester);
      final joke = currentJoke(tester);
      expect(find.text('Your starred jokes'), findsNothing);
      await tester.tap(find.byTooltip('Star this joke'));
      await tester.pumpAndSettle();
      expect(find.text('Your starred jokes'), findsOneWidget);
      expect(find.byTooltip('Unstar this joke'), findsOneWidget);

      // Move on to a different joke, then come back via the shelf.
      await reveal(tester);
      await tester.tap(find.text('Tell me another!'));
      await tester.pumpAndSettle();
      expect(currentJoke(tester).id, isNot(joke.id));
      // The chip carries the setup; the card carries it too, so find the
      // one inside the shelf's Wrap.
      await tester.tap(find.descendant(of: find.byType(Wrap), matching: find.text(joke.setup)));
      await tester.pumpAndSettle();
      expect(currentJoke(tester).id, joke.id);
      expect(find.text(joke.punchline), findsOneWidget); // she knows this one
    });

    testWidgets('unstarring empties the shelf again', (tester) async {
      await useNarrowSurface(tester);
      await tester.pumpWidget(wrap(JokebookScreen(childName: 'Ivy', pick: () => 0)));
      await tellMeOne(tester);
      await tester.tap(find.byTooltip('Star this joke'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Unstar this joke'));
      await tester.pumpAndSettle();
      expect(find.text('Your starred jokes'), findsNothing);
    });

    testWidgets('no score, streak, rank, count or "most" vocabulary anywhere, at any stage', (tester) async {
      await useNarrowSurface(tester);
      await tester.pumpWidget(wrap(JokebookScreen(childName: 'Ivy', pick: () => 0)));
      final forbidden = RegExp(r'\b(score|streak|rank|most played|most read|times read|jokes told)\b',
          caseSensitive: false);
      void sweep(String stage) {
        for (final t in tester.widgetList<Text>(find.byType(Text))) {
          expect(t.data ?? '', isNot(matches(forbidden)), reason: '$stage: "${t.data}"');
        }
      }
      sweep('ask');
      await tellMeOne(tester);
      sweep('setup');
      await reveal(tester);
      sweep('revealed');
      await tester.tap(find.byTooltip('Star this joke'));
      await tester.pumpAndSettle();
      sweep('starred');
    });
  });

  group('tell a parent — honest about what it is', () {
    testWidgets('opens a sheet with the whole joke and the parent\'s name, and never claims to send',
        (tester) async {
      await useNarrowSurface(tester);
      await tester.pumpWidget(wrap(JokebookScreen(childName: 'Ivy', parentName: 'Dad', pick: () => 0)));
      await tellMeOne(tester);
      final joke = currentJoke(tester);
      // Not offered before the ending — there is nothing to tell yet.
      expect(find.text('Tell Dad this one'), findsNothing);
      await reveal(tester);
      await tester.tap(find.text('Tell Dad this one'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('tellParentTitle')), findsOneWidget);
      expect(find.text('Tell Dad this one!'), findsOneWidget);
      // Both lines, large, inside the sheet — plus the card's own copies behind it.
      expect(find.text(joke.setup), findsNWidgets(2));
      expect(find.text(joke.punchline), findsNWidgets(2));
      final sent = RegExp(r'\b(sent|sending|delivered|message)\b', caseSensitive: false);
      for (final t in tester.widgetList<Text>(find.byType(Text))) {
        expect(t.data ?? '', isNot(matches(sent)), reason: '"${t.data}"');
      }
      await tester.tap(find.text("Got it — I'll tell them!"));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('tellParentTitle')), findsNothing);
    });
  });

  group('child-shell invariants', () {
    testWidgets('no settings affordance anywhere (§8.1) and the star is a real 48dp target (§8.4)',
        (tester) async {
      await useNarrowSurface(tester);
      await tester.pumpWidget(wrap(JokebookScreen(childName: 'Ivy', pick: () => 0)));
      await tellMeOne(tester);
      expect(find.byIcon(Icons.settings), findsNothing);
      expect(find.byIcon(Icons.settings_outlined), findsNothing);
      final star = tester.getSize(find.byTooltip('Star this joke'));
      expect(star.width, greaterThanOrEqualTo(48));
      expect(star.height, greaterThanOrEqualTo(48));
    });

    testWidgets('the section block reaches this screen from "Play together"\'s own consolidated picker',
        (tester) async {
      await useNarrowSurface(tester);
      await tester.pumpWidget(wrap(const GamePickerScreen(
        childName: 'Ivy', extraSections: [JokebookSection(childName: 'Ivy')])));
      // GamePickerScreen is a lazy ListView (see its own doc comment): a
      // section below the 12-card grid is not built into the tree until it
      // is scrolled to, so scroll first, then assert — the same sliver-
      // virtualization pitfall hub_widgets.dart's header documents.
      await tester.scrollUntilVisible(find.text('Jokebook'), 300,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      expect(find.text('JUST FOR LAUGHS'), findsOneWidget);
      await tester.tap(find.text('Jokebook'));
      await tester.pumpAndSettle();
      expect(find.text('Want a joke, Ivy?'), findsOneWidget);
    });
  });

  group('responsive — Fold5 cover/main, phone, and desktop-scale widths', () {
    for (final size in responsiveSizes) {
      testWidgets('renders every stage with no overflow at ${size.width.toInt()}px', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(wrap(JokebookScreen(childName: 'Ivy', childAge: 12, pick: () => 0.999)));
        expect(tester.takeException(), isNull);
        await tellMeOne(tester);
        expect(tester.takeException(), isNull);
        await reveal(tester);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('Star this joke'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });
}
