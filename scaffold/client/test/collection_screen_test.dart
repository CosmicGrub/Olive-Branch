// OLIVE BRANCH — collection screen widget tests. §9.10, P2.
//
// The load-bearing property: nothing on this screen may ever render a
// denominator, percentage, streak, or score — see showcaseForbiddenWords
// in showcase_logic.dart, ported from showcase.ts's SHOWCASE_FORBIDDEN.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/collection_screen.dart';
import 'package:olive_client/showcase_logic.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

void main() {
  group('collection screen — §9.10, P2', () {
    testWidgets('seeds with realistic collections, not empty', (t) async {
      await t.pumpWidget(wrap(const CollectionScreen()));
      expect(find.text('Dinosaurs'), findsOneWidget);
      expect(find.text('Rocks'), findsOneWidget);
      expect(find.text('Stegosaurus'), findsOneWidget);
      expect(find.text('Triceratops'), findsOneWidget);
      expect(find.text('T. Rex'), findsOneWidget);
      expect(find.text('The sparkly one'), findsOneWidget);
    });

    testWidgets('plural collection reads as a count, singular reads as "one so far"', (t) async {
      await t.pumpWidget(wrap(const CollectionScreen()));
      expect(find.text('You have shown me 3 of them.'), findsOneWidget);
      expect(find.text('You have shown me one so far.'), findsOneWidget);
    });

    testWidgets('the most recently shown item in a collection is tagged new', (t) async {
      await t.pumpWidget(wrap(const CollectionScreen()));
      expect(find.text('new!'), findsNWidgets(2)); // one per collection
    });

    testWidgets('NO denominator, percent, streak, or score anywhere on screen', (t) async {
      await t.pumpWidget(wrap(const CollectionScreen()));
      for (final forbidden in showcaseForbiddenWords) {
        expect(find.textContaining(forbidden, findRichText: true), findsNothing,
          reason: '"$forbidden" must never reach this screen');
      }
      expect(find.textContaining('%'), findsNothing);
      expect(find.textContaining(' of 1'), findsNothing); // no "3 of 151"-style total
    });

    testWidgets('NO settings affordance exists at any depth', (t) async {
      await t.pumpWidget(wrap(const CollectionScreen()));
      expect(find.byIcon(Icons.settings), findsNothing);
      expect(find.textContaining('Settings'), findsNothing);
    });

    testWidgets('adding a new specimen updates the count and appears newest', (t) async {
      await t.pumpWidget(wrap(const CollectionScreen()));
      await t.tap(find.widgetWithText(OutlinedButton, 'Show another dinosaurs'));
      await t.pumpAndSettle();

      await t.enterText(find.byType(TextField).first, 'Brachiosaurus');
      await t.pump();
      await t.tap(find.widgetWithText(FilledButton, 'Add it'));
      await t.pumpAndSettle();

      expect(find.text('Brachiosaurus'), findsOneWidget);
      expect(find.text('You have shown me 4 of them.'), findsOneWidget);
      // The newest tag now sits on the just-added specimen, not the old one.
      final newestChip = find.ancestor(of: find.text('Brachiosaurus'), matching: find.byType(Container)).first;
      expect(find.descendant(of: newestChip, matching: find.text('new!')), findsOneWidget);
    });

    testWidgets('showing the same thing twice is met with warmth, not an error', (t) async {
      await t.pumpWidget(wrap(const CollectionScreen()));
      await t.tap(find.widgetWithText(OutlinedButton, 'Show another dinosaurs'));
      await t.pumpAndSettle();

      await t.enterText(find.byType(TextField).first, 'Stegosaurus');
      await t.pump();
      await t.tap(find.widgetWithText(FilledButton, 'Add it'));
      await t.pumpAndSettle();

      expect(find.textContaining('You already showed me a Stegosaurus!'), findsOneWidget);
      expect(find.textContaining('error'), findsNothing);
      expect(find.textContaining('Error'), findsNothing);
      expect(find.textContaining('failed'), findsNothing);
      // Still exactly 3 dinosaur entries — no duplicate was appended.
      expect(find.text('You have shown me 3 of them.'), findsOneWidget);
    });

    testWidgets('blank input does not add an entry', (t) async {
      await t.pumpWidget(wrap(const CollectionScreen()));
      await t.tap(find.widgetWithText(OutlinedButton, 'Show another rocks'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, 'Add it'));
      await t.pumpAndSettle();
      expect(find.text('You have shown me one so far.'), findsOneWidget);
    });

    testWidgets('the add button meets the 48dp touch-target floor', (t) async {
      await t.pumpWidget(wrap(const CollectionScreen()));
      final Size size = t.getSize(find.widgetWithText(OutlinedButton, 'Show another dinosaurs'));
      expect(size.height, greaterThanOrEqualTo(48.0));
    });
  });

  group('responsive — Fold5 cover/main, phone, tablet/desktop', () {
    // Fold5 cover (344 CSS px), Fold5 main (~673x841, nearly square), a
    // standard phone (390), and a desktop-scale short-and-wide width (1100)
    // — the four widths this repo's responsive audit requires.
    const widths = <String, Size>{
      'fold5 cover': Size(344, 820),
      'fold5 main': Size(673, 841),
      'phone': Size(390, 844),
      'tablet/desktop': Size(1100, 800),
    };

    for (final entry in widths.entries) {
      testWidgets('renders every collection card and the add sheet without overflow '
          'at ${entry.key}', (t) async {
        t.view.physicalSize = entry.value;
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);

        await t.pumpWidget(wrap(const CollectionScreen()));
        expect(t.takeException(), isNull);

        // The "Show another dinosaurs" OutlinedButton.icon has no explicit
        // width — the label is the widest unwrapped text on the card at the
        // Fold5 cover's 344px, so it is the one most likely to overflow.
        final addButton = find.widgetWithText(OutlinedButton, 'Show another dinosaurs');
        await t.ensureVisible(addButton);
        await t.pumpAndSettle();
        await t.tap(addButton);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      });
    }
  });
}
