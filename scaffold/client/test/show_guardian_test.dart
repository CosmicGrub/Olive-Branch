// OLIVE BRANCH — guardian showcase screen widget tests. §9.10, §9.10.7–9.
//
// The property this group was specifically asked to make felt: the
// three-ask cap must be visible and, at the moment it bites, explicit —
// never a silent truncation on the one side of the app capable of noticing.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/show_guardian.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

// Tall surface, same rationale as emergency_card_test.dart: this screen has
// four stacked sections (composer, pending asks, shelf, received shows), and
// a viewport too short leaves the later ones off the default test canvas's
// cache extent entirely — "not found" would then be indistinguishable from
// "not rendered".
Future<void> pump(WidgetTester tester, Widget child) async {
  await tester.binding.setSurfaceSize(const Size(800, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(wrap(child));
}

void main() {
  group('guardian showcase — §9.10', () {
    testWidgets('renders her name and the seeded pending asks', (t) async {
      await pump(t, const ShowGuardianScreen(childName: 'Maya'));
      expect(find.textContaining("Maya's show"), findsOneWidget);
      expect(find.text("Show me the biggest dinosaur you've got"), findsOneWidget);
      expect(find.text('Show me one thing that made you laugh today'), findsOneWidget);
    });

    testWidgets('the cap badge shows how many of three are waiting, always', (t) async {
      await pump(t, const ShowGuardianScreen());
      expect(find.text('2 of 3 waiting'), findsOneWidget);
    });

    testWidgets('sending a third ask fills the cap with no confirmation needed', (t) async {
      await pump(t, const ShowGuardianScreen());
      await t.enterText(find.byType(TextField).first, 'Show me your shoes');
      await t.tap(find.widgetWithText(FilledButton, 'Send the ask'));
      await t.pumpAndSettle();

      expect(find.text('3 of 3 waiting'), findsOneWidget);
      expect(find.text('Show me your shoes'), findsOneWidget);
      expect(find.text('Three are already waiting'), findsNothing);
    });

    testWidgets('a fourth ask is never silently dropped — the guardian is asked first', (t) async {
      await pump(t, const ShowGuardianScreen());
      await t.enterText(find.byType(TextField).first, 'Show me your shoes');
      await t.tap(find.widgetWithText(FilledButton, 'Send the ask'));
      await t.pumpAndSettle();

      await t.enterText(find.byType(TextField).first, 'One more ask');
      await t.tap(find.widgetWithText(FilledButton, 'Send the ask'));
      await t.pumpAndSettle();

      expect(find.text('Three are already waiting'), findsOneWidget);
      // Names the exact ask that is about to be retired — not a vague count.
      expect(find.textContaining("Show me the biggest dinosaur you've got"), findsWidgets);
      // Cancelling leaves the cap and every existing ask untouched — the
      // dinosaur ask is still there, not retired.
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(find.text('3 of 3 waiting'), findsOneWidget);
      expect(find.text("Show me the biggest dinosaur you've got"), findsOneWidget);
    });

    testWidgets('confirming the swap retires the oldest and says so out loud', (t) async {
      await pump(t, const ShowGuardianScreen());
      await t.enterText(find.byType(TextField).first, 'Show me your shoes');
      await t.tap(find.widgetWithText(FilledButton, 'Send the ask'));
      await t.pumpAndSettle();

      await t.enterText(find.byType(TextField).first, 'One more ask');
      await t.tap(find.widgetWithText(FilledButton, 'Send the ask'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(FilledButton, 'Send anyway'));
      await t.pumpAndSettle();

      // The cap holds at three; the oldest ask is gone, the new one is in.
      expect(find.text('3 of 3 waiting'), findsOneWidget);
      expect(find.text("Show me the biggest dinosaur you've got"), findsNothing);
      expect(find.text('One more ask'), findsOneWidget);
      expect(find.textContaining('Retired:'), findsOneWidget);
    });

    testWidgets('the shelf shows real counts — this is the guardian side, P2 permits it here', (t) async {
      await pump(t, const ShowGuardianScreen());
      expect(find.text('Dinosaurs'), findsOneWidget);
      expect(find.text('3 shown'), findsOneWidget);
      expect(find.text('Rocks'), findsOneWidget);
      expect(find.text('1 shown'), findsOneWidget);
    });

    testWidgets('a plain-text reply to a creation show is nudged toward replying in kind', (t) async {
      await pump(t, const ShowGuardianScreen());
      final creationCard = find.ancestor(
        of: find.text('A drawing of a Stegosaurus'), matching: find.byType(Card)).first;
      await t.enterText(find.descendant(of: creationCard, matching: find.byType(TextField)), 'Nice!');
      await t.pump();
      await t.tap(find.descendant(of: creationCard, matching: find.widgetWithText(FilledButton, 'Send')));
      await t.pumpAndSettle();

      expect(find.text('Reply in kind?'), findsOneWidget);
      expect(find.textContaining('not a sentence'), findsOneWidget);

      await t.tap(find.text('Send the words anyway'));
      await t.pumpAndSettle();
      expect(find.descendant(of: creationCard, matching: find.text('Replied')), findsOneWidget);
    });

    testWidgets('choosing to attach something instead leaves the show unreplied', (t) async {
      await pump(t, const ShowGuardianScreen());
      final creationCard = find.ancestor(
        of: find.text('A drawing of a Stegosaurus'), matching: find.byType(Card)).first;
      await t.enterText(find.descendant(of: creationCard, matching: find.byType(TextField)), 'Nice!');
      await t.pump();
      await t.tap(find.descendant(of: creationCard, matching: find.widgetWithText(FilledButton, 'Send')));
      await t.pumpAndSettle();

      await t.tap(find.text('Attach something instead'));
      await t.pumpAndSettle();
      expect(find.descendant(of: creationCard, matching: find.text('Replied')), findsNothing);
    });

    testWidgets('NO settings affordance exists at any depth', (t) async {
      await pump(t, const ShowGuardianScreen());
      expect(find.byIcon(Icons.settings), findsNothing);
      expect(find.textContaining('Settings'), findsNothing);
    });

    testWidgets('send-ask control meets an ample touch-target size', (t) async {
      await pump(t, const ShowGuardianScreen());
      final Size size = t.getSize(find.widgetWithText(FilledButton, 'Send the ask'));
      expect(size.height, greaterThanOrEqualTo(48.0));
    });
  });
}
