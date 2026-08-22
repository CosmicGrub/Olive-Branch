import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/wants_needs.dart';

void main() {
  Future<void> pump(WidgetTester tester) => tester.pumpWidget(
    const MaterialApp(home: WantsNeedsScreen()));

  int checkboxCountIn(WidgetTester tester, Key sectionKey) => tester.widgetList(
    find.descendant(of: find.byKey(sectionKey), matching: find.byType(Checkbox))).length;

  testWidgets('both lists render seeded with realistic demo items', (tester) async {
    await pump(tester);
    expect(find.text('Things I want'), findsOneWidget);
    expect(find.text('Things I need'), findsOneWidget);
    expect(find.text('LEGO set'), findsOneWidget);
    expect(find.text('New video game'), findsOneWidget);
    expect(find.text('New shoes'), findsOneWidget);
    expect(find.text('Winter coat'), findsOneWidget);
  });

  testWidgets('adding an item to wants only changes the wants list', (tester) async {
    await pump(tester);
    const wantsKey = Key('wantsSection');
    const needsKey = Key('needsSection');

    final beforeWants = checkboxCountIn(tester, wantsKey);
    final beforeNeeds = checkboxCountIn(tester, needsKey);

    await tester.enterText(find.byType(TextField).first, 'Bike');
    await tester.tap(find.widgetWithText(FilledButton, 'Add').first);
    await tester.pump();

    expect(checkboxCountIn(tester, wantsKey), beforeWants + 1);
    expect(checkboxCountIn(tester, needsKey), beforeNeeds);
    expect(find.text('Bike'), findsOneWidget);
    expect(find.descendant(of: find.byKey(needsKey), matching: find.text('Bike')), findsNothing);
  });

  testWidgets('adding an item to needs only changes the needs list', (tester) async {
    await pump(tester);
    const wantsKey = Key('wantsSection');
    const needsKey = Key('needsSection');

    final beforeWants = checkboxCountIn(tester, wantsKey);
    final beforeNeeds = checkboxCountIn(tester, needsKey);

    await tester.enterText(find.byType(TextField).last, 'Toothbrush');
    await tester.tap(find.widgetWithText(FilledButton, 'Add').last);
    await tester.pump();

    expect(checkboxCountIn(tester, needsKey), beforeNeeds + 1);
    expect(checkboxCountIn(tester, wantsKey), beforeWants);
    expect(find.text('Toothbrush'), findsOneWidget);
    expect(find.descendant(of: find.byKey(wantsKey), matching: find.text('Toothbrush')), findsNothing);
  });

  testWidgets('the text field clears after a successful add, blank entries are ignored', (tester) async {
    await pump(tester);
    const wantsKey = Key('wantsSection');
    final beforeWants = checkboxCountIn(tester, wantsKey);

    await tester.enterText(find.byType(TextField).first, '   ');
    await tester.tap(find.widgetWithText(FilledButton, 'Add').first);
    await tester.pump();
    expect(checkboxCountIn(tester, wantsKey), beforeWants);

    await tester.enterText(find.byType(TextField).first, 'Skateboard');
    await tester.tap(find.widgetWithText(FilledButton, 'Add').first);
    await tester.pump();

    final field = tester.widget<TextField>(find.byType(TextField).first);
    expect(field.controller!.text, isEmpty);
  });

  testWidgets('toggling done state changes rendering and the item persists in its list',
      (tester) async {
    await pump(tester);
    const wantsKey = Key('wantsSection');
    final beforeCount = checkboxCountIn(tester, wantsKey);

    final legoText = tester.widget<Text>(find.text('LEGO set'));
    expect(legoText.style?.decoration, isNot(TextDecoration.lineThrough));

    final legoCheckbox = tester.widget<Checkbox>(find.descendant(
      of: find.byKey(wantsKey), matching: find.byType(Checkbox)).first);
    expect(legoCheckbox.value, isFalse);

    await tester.tap(find.descendant(
      of: find.byKey(wantsKey), matching: find.byType(Checkbox)).first);
    await tester.pump();

    // still on the list — a record of what was asked for, not a vanishing to-do.
    expect(find.text('LEGO set'), findsOneWidget);
    expect(checkboxCountIn(tester, wantsKey), beforeCount);

    final toggledCheckbox = tester.widget<Checkbox>(find.descendant(
      of: find.byKey(wantsKey), matching: find.byType(Checkbox)).first);
    expect(toggledCheckbox.value, isTrue);

    final toggledText = tester.widget<Text>(find.text('LEGO set'));
    expect(toggledText.style?.decoration, TextDecoration.lineThrough);

    await tester.tap(find.descendant(
      of: find.byKey(wantsKey), matching: find.byType(Checkbox)).first);
    await tester.pump();
    final untoggledText = tester.widget<Text>(find.text('LEGO set'));
    expect(untoggledText.style?.decoration, isNot(TextDecoration.lineThrough));
  });

  testWidgets('no price, currency, or purchase affordance exists anywhere on this screen',
      (tester) async {
    await pump(tester);
    expect(find.textContaining(RegExp(r'\$')), findsNothing);
    expect(find.textContaining(RegExp(r'[0-9]')), findsNothing);
    expect(find.text('Buy'), findsNothing);
    expect(find.text('Purchase'), findsNothing);
    expect(find.textContaining('Buy', findRichText: true), findsNothing);
    expect(find.textContaining('Purchase', findRichText: true), findsNothing);
    expect(find.textContaining('gift', findRichText: true), findsNothing);
    expect(find.textContaining('http'), findsNothing);
  });

  group('wants & needs — responsive two-pane split (§8.11.1, form_factors.dart)', () {
    // Real columnsAt()-driven threshold (form_factors.dart), matching
    // message_banking.dart's own two-pane pattern — not an invented number.
    testWidgets(
        'a genuinely wide viewport (tablet/desktop, >=660px effective) renders '
        'wants and needs as two side-by-side panes', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1100, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pump(tester);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('wantsNeedsTwoPaneRow')), findsOneWidget);
      // Both panes' content is still genuinely present, just rearranged.
      expect(find.text('Things I want'), findsOneWidget);
      expect(find.text('Things I need'), findsOneWidget);
      expect(find.text('LEGO set'), findsOneWidget);
      expect(find.text('New shoes'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the Fold5 cover width (344px) keeps the exact stacked single '
        "column unchanged — no two-pane Row at all", (tester) async {
      await tester.binding.setSurfaceSize(const Size(344, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pump(tester);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('wantsNeedsTwoPaneRow')), findsNothing);
      expect(find.text('Things I want'), findsOneWidget);
      expect(find.text('Things I need'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a standard phone width (390px) also keeps the stacked single '
        'column, not the two-pane Row', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pump(tester);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('wantsNeedsTwoPaneRow')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('adding a want still works correctly inside the wide two-pane layout',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1100, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await pump(tester);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'Wide-pane wish');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Add').first);
      await tester.pump();

      expect(find.text('Wide-pane wish'), findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const Key('needsSection')),
              matching: find.text('Wide-pane wish')),
          findsNothing);
    });
  });
}
