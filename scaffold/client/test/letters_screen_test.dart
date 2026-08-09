// OLIVE BRANCH — letters-to-future-self tests. §21.4, §21.8.
//
// The invariant that matters most: a sealed letter's content never renders
// anywhere until it is both due AND explicitly opened — not early, and not
// merely because the current age caught up to the open age.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/letters_screen.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

void main() {
  group('letters — pure port of maturation.ts seal/open/delete', () {
    test('sealing at nine to open at eighteen succeeds', () {
      final result = sealLetter(id: 'l1', childId: 'maya', writtenAtAge: 9,
        openAtAge: 18, body: 'hello future me', at: DateTime(2026));
      expect(result.ok, isTrue);
      expect(result.letter!.preserved, isTrue);
    });

    test('sealing less than a year out is refused as too_soon', () {
      final result = sealLetter(id: 'l1', childId: 'maya', writtenAtAge: 17,
        openAtAge: 17, body: 'x', at: DateTime(2026));
      expect(result.ok, isFalse);
      expect(result.reason, SealError.tooSoon);
    });

    test('sealing past the ceiling age is refused as too_far', () {
      final result = sealLetter(id: 'l1', childId: 'maya', writtenAtAge: 20,
        openAtAge: 26, body: 'x', at: DateTime(2026));
      expect(result.ok, isFalse);
      expect(result.reason, SealError.tooFar);
    });

    test('opening before the open age is refused, and says how long is left', () {
      final sealed = sealLetter(id: 'l1', childId: 'maya', writtenAtAge: 9,
        openAtAge: 18, body: 'x', at: DateTime(2026)).letter!;
      final result = openLetter(sealed, 15, DateTime(2032));
      expect(result.ok, isFalse);
      expect(result.reason, SealError.notYet);
      expect(result.yearsLeft, 3);
    });

    test('opening at or after the open age succeeds', () {
      final sealed = sealLetter(id: 'l1', childId: 'maya', writtenAtAge: 9,
        openAtAge: 18, body: 'x', at: DateTime(2026)).letter!;
      final result = openLetter(sealed, 18, DateTime(2035));
      expect(result.ok, isTrue);
      expect(result.letter!.openedAt, DateTime(2035));
    });

    test('opening an already-open letter again is refused', () {
      final sealed = sealLetter(id: 'l1', childId: 'maya', writtenAtAge: 9,
        openAtAge: 18, body: 'x', at: DateTime(2026)).letter!;
      final opened = openLetter(sealed, 18, DateTime(2035)).letter!;
      final again = openLetter(opened, 20, DateTime(2037));
      expect(again.ok, isFalse);
      expect(again.reason, SealError.alreadyOpen);
    });

    test('deleteLetter removes only the matching id', () {
      final a = sealLetter(id: 'a', childId: 'x', writtenAtAge: 9, openAtAge: 18, body: '1', at: DateTime(2026)).letter!;
      final b = sealLetter(id: 'b', childId: 'x', writtenAtAge: 9, openAtAge: 18, body: '2', at: DateTime(2026)).letter!;
      final remaining = deleteLetter([a, b], 'a');
      expect(remaining.map((l) => l.id), ['b']);
    });
  });

  group('letters screen — child-facing', () {
    testWidgets('the empty state carries a calm icon, and it clears once one is sealed',
        (t) async {
      await t.pumpWidget(wrap(const LettersScreen(childName: 'Maya', currentAge: 11)));
      expect(find.byIcon(Icons.mail_outline), findsOneWidget);

      await t.enterText(find.byType(TextField), 'Dear future me, hello.');
      await t.pump();
      await t.ensureVisible(find.widgetWithText(FilledButton, 'Seal it'));
      await t.tap(find.widgetWithText(FilledButton, 'Seal it'));
      await t.pump();
      expect(find.byIcon(Icons.mail_outline), findsNothing);
    });

    testWidgets('the age picker only offers ages at least a year out', (t) async {
      await t.pumpWidget(wrap(const LettersScreen(childName: 'Maya', currentAge: 17)));
      expect(find.widgetWithText(ChoiceChip, '18'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, '21'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, '25'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, '12'), findsNothing);
      expect(find.widgetWithText(ChoiceChip, '14'), findsNothing);
      expect(find.widgetWithText(ChoiceChip, '16'), findsNothing);
    });

    testWidgets('sealing a letter adds a locked entry and clears the field', (t) async {
      await t.pumpWidget(wrap(const LettersScreen(childName: 'Maya', currentAge: 11)));
      await t.enterText(find.byType(TextField), 'Dear future me, I hope you still love dogs.');
      await t.pump(); // let the listener-driven setState enable the button first
      // The compose card is taller than the default test viewport — scroll
      // the button into view before tapping, same as a real finger would.
      await t.ensureVisible(find.widgetWithText(FilledButton, 'Seal it'));
      await t.tap(find.widgetWithText(FilledButton, 'Seal it'));
      await t.pump();

      expect(find.textContaining("Sealed until you're 18"), findsOneWidget);
      final field = t.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, isEmpty);
      // The content itself must never render while sealed.
      expect(find.text('Dear future me, I hope you still love dogs.'), findsNothing);
    });

    testWidgets('a sealed, not-yet-due letter exposes no open affordance or content', (t) async {
      await t.pumpWidget(wrap(LettersScreen(childName: 'Maya', currentAge: 11, initialLetters: [
        Letter(id: 'l1', childId: 'demo-child', writtenAtAge: 9, openAtAge: 18,
          writtenAt: DateTime(2024, 1, 1), body: 'a secret only future me should read'),
      ])));
      expect(find.text("Sealed until you're 18"), findsOneWidget);
      expect(find.text('Open it'), findsNothing);
      expect(find.text('a secret only future me should read'), findsNothing);
    });

    testWidgets('a due letter offers Open it, and reveals its body once opened', (t) async {
      await t.pumpWidget(wrap(LettersScreen(childName: 'Maya', currentAge: 11, initialLetters: [
        Letter(id: 'l2', childId: 'demo-child', writtenAtAge: 9, openAtAge: 11,
          writtenAt: DateTime(2024, 1, 1), body: 'now you are old enough'),
      ])));
      expect(find.text('Ready whenever you want'), findsOneWidget);
      expect(find.text('now you are old enough'), findsNothing);

      await t.ensureVisible(find.widgetWithText(FilledButton, 'Open it'));
      await t.tap(find.widgetWithText(FilledButton, 'Open it'));
      await t.pumpAndSettle();

      expect(find.text('Opened'), findsOneWidget);
      expect(find.text('now you are old enough'), findsOneWidget);
    });

    testWidgets('deleting asks for confirmation, and only removes on confirm', (t) async {
      await t.pumpWidget(wrap(LettersScreen(childName: 'Maya', currentAge: 11, initialLetters: [
        Letter(id: 'l1', childId: 'demo-child', writtenAtAge: 9, openAtAge: 18,
          writtenAt: DateTime(2024, 1, 1), body: 'keep or toss'),
      ])));

      await t.ensureVisible(find.byIcon(Icons.delete_outline));
      await t.tap(find.byIcon(Icons.delete_outline));
      await t.pumpAndSettle();
      expect(find.text('Delete this letter?'), findsOneWidget);

      await t.tap(find.text('Keep it'));
      await t.pumpAndSettle();
      expect(find.textContaining("Sealed until you're 18"), findsOneWidget);

      await t.ensureVisible(find.byIcon(Icons.delete_outline));
      await t.tap(find.byIcon(Icons.delete_outline));
      await t.pumpAndSettle();
      await t.tap(find.text('Delete it'));
      await t.pumpAndSettle();
      expect(find.textContaining("Sealed until you're 18"), findsNothing);
    });

    group('responsive — no overflow at any required viewport width', () {
      // Fold5 cover, Fold5 main, phone, and tablet/desktop widths. Seeds one
      // opened letter (so its body actually renders and wraps) and one
      // sealed letter (so the chip row and sealed-tile copy both render).
      Widget buildScreen() => wrap(LettersScreen(childName: 'Ivy', currentAge: 11, initialLetters: [
        Letter(id: 'l1', childId: 'demo-child', writtenAtAge: 9, openAtAge: 11,
          writtenAt: DateTime(2024, 1, 1), openedAt: DateTime(2026, 1, 1),
          body: 'now you are old enough, and this body text is somewhat long so it '
                'actually wraps and stresses the layout on a narrow screen'),
        Letter(id: 'l2', childId: 'demo-child', writtenAtAge: 9, openAtAge: 18,
          writtenAt: DateTime(2024, 1, 1), body: 'sealed body'),
      ]));

      Future<void> pumpAt(WidgetTester t, Size size) async {
        await t.binding.setSurfaceSize(size);
        addTearDown(() => t.binding.setSurfaceSize(null));
        await t.pumpWidget(buildScreen());
        await t.pump();
      }

      testWidgets('Fold5 cover screen (344 CSS px wide)', (t) async {
        await pumpAt(t, const Size(344, 900));
        expect(t.takeException(), isNull);
      });

      testWidgets('Fold5 unfolded main screen (~673x841, nearly square)', (t) async {
        await pumpAt(t, const Size(673, 841));
        expect(t.takeException(), isNull);
      });

      testWidgets('standard phone width (~390px)', (t) async {
        await pumpAt(t, const Size(390, 844));
        expect(t.takeException(), isNull);
      });

      testWidgets('tablet/desktop width (~1100px, short and wide)', (t) async {
        await pumpAt(t, const Size(1100, 800));
        expect(t.takeException(), isNull);
      });
    });

    testWidgets('NO settings affordance and no absence-guilt language', (t) async {
      await t.pumpWidget(wrap(const LettersScreen(childName: 'Maya', currentAge: 11)));
      expect(find.byIcon(Icons.settings), findsNothing);
      expect(find.textContaining("haven't"), findsNothing);
      expect(find.textContaining('streak'), findsNothing);
    });

    testWidgets('privacy banner uses the house 12-radius compact-banner shape '
        'shared with expenses_screen/meds_care/morning_briefing/care_note/'
        'guardian_setup', (t) async {
      await t.pumpWidget(wrap(const LettersScreen(childName: 'Maya', currentAge: 11)));
      final container = t.widget<Container>(find.ancestor(
        of: find.byIcon(Icons.mail_lock_outlined),
        matching: find.byType(Container),
      ).first);
      final decoration = container.decoration! as BoxDecoration;
      expect((decoration.borderRadius! as BorderRadius).topLeft, const Radius.circular(12));
      expect(container.padding, const EdgeInsets.all(12));
    });
  });
}
