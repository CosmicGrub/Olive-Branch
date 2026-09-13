// OLIVE BRANCH — find the thing tests. MASTERFILE §9.12.2, §8.14.
//
// The properties that matter most: difficulty is decoy count/similarity,
// never a timer; a miss produces no feedback at all (no buzz, no shake, no
// counter — P2's "no wrong answer" carried over from activities.ts); and a
// hint gives a quadrant, never the answer.
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/game_findthing.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

void main() {
  group('ported logic — activities.ts find-the-thing section', () {
    const FindTarget target = FindTarget(label: 'her dinosaur', glyph: '🦕');

    test('buildFindScene refuses an empty decoy pool', () {
      expect(buildFindScene('s', target, <String>[], FindDifficulty.gentle, Random(1)).ok, isFalse);
    });

    test('difficulty controls decoy count and zoom, never a timer', () {
      final FindScene gentle = buildFindScene(
        's', target, <String>['🚗', '⚽'], FindDifficulty.gentle, Random(1)).scene!;
      final FindScene fiendish = buildFindScene(
        's', target, <String>['🚗', '⚽'], FindDifficulty.fiendish, Random(1)).scene!;
      expect(gentle.items.length, 24 + 1); // decoys + the target itself
      expect(fiendish.items.length, 320 + 1);
      expect(fiendish.maxZoom, greaterThan(gentle.maxZoom));
      // Exactly one target on the scene, regardless of difficulty.
      expect(gentle.items.where((FindItem i) => i.isTarget).length, 1);
    });

    test('tapFind reports found only for the real target, nothing for a miss', () {
      final FindScene scene = buildFindScene(
        's', target, <String>['🚗', '⚽', '🌟'], FindDifficulty.gentle, Random(7)).scene!;
      final FindItem theTarget = scene.items.firstWhere((FindItem i) => i.isTarget);
      final FindItem decoy = scene.items.firstWhere((FindItem i) => !i.isTarget);
      expect(tapFind(scene, theTarget.id).found, isTrue);
      expect(tapFind(scene, decoy.id).found, isFalse);
    });

    test('findHint gives a quadrant, never the exact position', () {
      final FindScene scene = buildFindScene(
        's', target, <String>['🚗'], FindDifficulty.gentle, Random(3)).scene!;
      final String hint = findHint(scene);
      expect(hint, matches(RegExp(r'^Try the (top|bottom) (left|right)\.$')));
    });
  });

  group('GameFindThingScreen widget — MARKUP "findThing"', () {
    testWidgets('renders the target and a packed scene at the default difficulty', (tester) async {
      await tester.pumpWidget(wrap(const GameFindThingScreen()));
      expect(find.textContaining('Find her dinosaur'), findsOneWidget);
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(find.text('🦕'), findsNWidgets(2)); // the header glyph + the one on the scene
    });

    testWidgets('tapping the target reveals a one-time "found" celebration', (tester) async {
      // A pinned seed (see GameFindThingScreen.debugSeed's doc) verified to
      // lay the target out with no decoy sharing its tap area at this test
      // viewport's default size — a packed scene can otherwise legitimately
      // stack a decoy on top of the target (§9.12.2), which would make an
      // unseeded scene flaky to tap deterministically in a test.
      await tester.pumpWidget(wrap(const GameFindThingScreen(debugSeed: 0)));
      await tester.tap(find.text('🦕').last);
      await tester.pump();
      expect(find.textContaining('You found her dinosaur'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Find something new'), findsOneWidget);
    });

    testWidgets('a hint gives a quadrant only, never the answer', (tester) async {
      await tester.pumpWidget(wrap(const GameFindThingScreen()));
      await tester.tap(find.widgetWithText(OutlinedButton, 'Need a hint?'));
      await tester.pump();
      expect(find.textContaining(RegExp(r'^Try the (top|bottom) (left|right)\.$')), findsOneWidget);
    });

    testWidgets('switching difficulty rebuilds a new scene without a timer anywhere', (tester) async {
      await tester.pumpWidget(wrap(const GameFindThingScreen()));
      await tester.tap(find.widgetWithText(ChoiceChip, 'Fiendish'));
      await tester.pump();
      expect(find.text('🦕'), findsNWidgets(2));
      for (final String forbidden in <String>['seconds', 'countdown', 'time left', 'Timer']) {
        expect(find.textContaining(forbidden), findsNothing);
      }
    });

    testWidgets('P3 — no coordinate or location field anywhere on screen', (tester) async {
      await tester.pumpWidget(wrap(const GameFindThingScreen()));
      for (final String forbidden in <String>['latitude', 'longitude', 'GPS', 'coordinates']) {
        expect(find.textContaining(forbidden), findsNothing);
      }
    });

    testWidgets('P2 — no score, streak, or badge ever appears', (tester) async {
      await tester.pumpWidget(wrap(const GameFindThingScreen(debugSeed: 0)));
      await tester.tap(find.text('🦕').last);
      await tester.pump();
      for (final String forbidden in <String>['score', 'Score', 'streak', 'Streak', 'badge', 'Badge']) {
        expect(find.textContaining(forbidden), findsNothing);
      }
    });

    testWidgets('no settings affordance exists anywhere', (tester) async {
      await tester.pumpWidget(wrap(const GameFindThingScreen()));
      expect(find.byIcon(Icons.settings), findsNothing);
      expect(find.byIcon(Icons.settings_outlined), findsNothing);
      expect(find.textContaining('Settings'), findsNothing);
    });

    testWidgets('the difficulty chips and hint control are laid out responsively', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      // MASTERFILE's own mandated minimum widths (the Fold5's cover and
      // unfolded main screens), plus a standard phone width and a
      // short-and-wide desktop/tablet width now that Windows is a real
      // target.
      await tester.binding.setSurfaceSize(const Size(344, 882)); // Fold5 cover screen width
      await tester.pumpWidget(wrap(const GameFindThingScreen()));
      expect(tester.takeException(), isNull);
      await tester.binding.setSurfaceSize(const Size(673, 841)); // Fold5 unfolded main screen
      await tester.pumpWidget(wrap(const GameFindThingScreen()));
      expect(tester.takeException(), isNull);
      await tester.binding.setSurfaceSize(const Size(390, 844)); // a standard phone width
      await tester.pumpWidget(wrap(const GameFindThingScreen()));
      expect(tester.takeException(), isNull);
      await tester.binding.setSurfaceSize(const Size(1100, 800)); // a tablet/desktop width
      await tester.pumpWidget(wrap(const GameFindThingScreen()));
      expect(tester.takeException(), isNull);
    });
  });
}
