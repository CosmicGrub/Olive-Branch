// OLIVE BRANCH — scavenger hunt tests. MASTERFILE §9.2, §9.7.2, P3.
//
// Two invariants matter most here: NO TIMER anywhere on the screen (a
// countdown would make wandering the house feel like a test), and NO
// coordinate/location field anywhere in the model or the UI (P3 — arrival
// events only, never a place).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/game_hunt.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

void main() {
  group('ported logic — games3.ts scavenger hunt section', () {
    test('newHunt refuses zero prompts and more than eight', () {
      expect(newHunt('h', <String>[], HuntSide.b, 'now').ok, isFalse);
      expect(newHunt('h', List<String>.filled(9, 'x'), HuntSide.b, 'now').ok, isFalse);
      final NewHuntResult ok = newHunt('h', <String>['Something round'], HuntSide.b, 'now');
      expect(ok.ok, isTrue);
      expect(ok.hunt!.prompts.single.artifactId, isNull);
    });

    test('submitFind marks a prompt found and refuses a repeat', () {
      final Hunt h = newHunt('h', <String>['Something round'], HuntSide.b, 'now').hunt!;
      final SubmitFindResult r = submitFind(h, 'h-0', 'art-1', 'later');
      expect(r.ok, isTrue);
      expect(r.hunt!.prompts.single.artifactId, 'art-1');
      expect(submitFind(r.hunt!, 'h-0', 'art-2', 'later').ok, isFalse);
      expect(submitFind(h, 'unknown-id', 'art-3', 'later').ok, isFalse);
    });

    test('huntProgress and huntComplete track found vs total', () {
      Hunt h = newHunt('h', <String>['a', 'b'], HuntSide.b, 'now').hunt!;
      expect(huntProgress(h).found, 0);
      expect(huntComplete(h), isFalse);
      h = submitFind(h, 'h-0', 'art-1', 'later').hunt!;
      expect(huntProgress(h).found, 1);
      h = submitFind(h, 'h-1', 'art-2', 'later').hunt!;
      expect(huntComplete(h), isTrue);
    });

    test('huntArtifacts are always preserved', () {
      Hunt h = newHunt('h', <String>['a'], HuntSide.b, 'now').hunt!;
      h = submitFind(h, 'h-0', 'art-1', 'later').hunt!;
      expect(huntArtifacts(h).single.preserved, isTrue);
    });
  });

  group('GameHuntScreen widget — MARKUP "hunt"', () {
    testWidgets('seeds with prompts already set by the parent', (tester) async {
      await tester.pumpWidget(wrap(const GameHuntScreen()));
      expect(find.textContaining('0 of 5 found'), findsOneWidget);
      expect(find.text('Something round'), findsOneWidget);
    });

    testWidgets('tapping "Found it!" marks a prompt found and updates progress', (tester) async {
      await tester.pumpWidget(wrap(const GameHuntScreen()));
      await tester.tap(find.widgetWithText(FilledButton, 'Found it!').first);
      await tester.pump();
      expect(find.textContaining('1 of 5 found'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });

    testWidgets('finding everything shows a one-time cooperative celebration', (tester) async {
      await tester.pumpWidget(wrap(const GameHuntScreen()));
      // Five prompts seeded; find each one in turn.
      for (int i = 0; i < 5; i++) {
        await tester.tap(find.widgetWithText(FilledButton, 'Found it!').first);
        await tester.pump();
      }
      expect(find.textContaining('5 of 5 found'), findsOneWidget);
      expect(find.textContaining('You found everything'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Found it!'), findsNothing);
    });

    testWidgets('NO TIMER anywhere — no countdown, seconds, minutes, or clock text', (tester) async {
      await tester.pumpWidget(wrap(const GameHuntScreen()));
      expect(find.byType(Stepper), findsNothing);
      for (final String forbidden in <String>[
        'seconds', 'minutes', 'countdown', 'time left', 'Time left', ':00', 'timer', 'Timer',
      ]) {
        expect(find.textContaining(forbidden), findsNothing);
      }
    });

    testWidgets('P3 — no coordinate or location field anywhere on screen', (tester) async {
      await tester.pumpWidget(wrap(const GameHuntScreen()));
      for (final String forbidden in <String>[
        'latitude', 'longitude', 'lat:', 'lng:', 'GPS', 'location', 'coordinates',
      ]) {
        expect(find.textContaining(forbidden), findsNothing);
      }
    });

    testWidgets('P2 — no score, streak, or badge ever appears', (tester) async {
      await tester.pumpWidget(wrap(const GameHuntScreen()));
      for (final String forbidden in <String>['score', 'Score', 'streak', 'Streak', 'badge', 'Badge']) {
        expect(find.textContaining(forbidden), findsNothing);
      }
    });

    testWidgets('no settings affordance exists anywhere', (tester) async {
      await tester.pumpWidget(wrap(const GameHuntScreen()));
      expect(find.byIcon(Icons.settings), findsNothing);
      expect(find.byIcon(Icons.settings_outlined), findsNothing);
      expect(find.textContaining('Settings'), findsNothing);
    });

    testWidgets('the "Found it!" buttons meet the 48dp minimum touch target', (tester) async {
      await tester.pumpWidget(wrap(const GameHuntScreen()));
      final Size size = tester.getSize(find.widgetWithText(FilledButton, 'Found it!').first);
      expect(size.height, greaterThanOrEqualTo(48.0));
    });

    group('responsive audit — Fold5, phone, and tablet/desktop widths', () {
      // MASTERFILE's own mandated minimum widths (the Fold5's cover and
      // unfolded main screens), plus a standard phone width and a
      // short-and-wide desktop/tablet width now that Windows is a real
      // target.
      for (final MapEntry<String, Size> entry in const <String, Size>{
        'Fold5 cover (344 CSS px)': Size(344, 882),
        'Fold5 unfolded main (~673 CSS px)': Size(673, 841),
        'a standard phone (~390 CSS px)': Size(390, 844),
        'a tablet/desktop (~1100 CSS px)': Size(1100, 800),
      }.entries) {
        testWidgets('renders without overflow at ${entry.key}', (tester) async {
          await tester.binding.setSurfaceSize(entry.value);
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await tester.pumpWidget(wrap(const GameHuntScreen()));
          await tester.pump();
          expect(tester.takeException(), isNull);
        });
      }
    });
  });
}
