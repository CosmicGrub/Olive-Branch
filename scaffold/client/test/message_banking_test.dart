// OLIVE BRANCH — message banking widget tests. §9.5.
//
// Same posture as test/invariants_test.dart: assert against the actual
// widget tree, not the intent behind it. The load-bearing property here is
// structural, not behavioral — a delivered entry must have no delete
// affordance anywhere in its subtree, full stop (§9.5: "delivered messages
// are the child's").
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/message_banking.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

const String _seedDelivered1 = 'Good night, sleep tight — love you to the moon.';
const String _seedDelivered2 = 'Sweet dreams, my brave girl. Proud of you today.';
const String _seedQueued = 'Missing you already. See you in your dreams tonight.';

void main() {
  group('message banking — §9.5', () {
    testWidgets('composing and banking adds a real queued entry', (t) async {
      await t.pumpWidget(wrap(const MessageBankingScreen()));
      expect(find.text('Love you to the stars and back'), findsNothing);

      await t.enterText(find.byType(TextField), 'Love you to the stars and back');
      await t.pump();
      await t.tap(find.widgetWithText(FilledButton, 'Bank this message'));
      await t.pump();

      expect(find.text('Love you to the stars and back'), findsOneWidget);
      // Seed had 1 queued; banking one more makes 2 — the field also clears.
      expect(find.textContaining('2 queued'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Love you to the stars and back'), findsNothing);
    });

    testWidgets('a delivered entry has no delete/revoke control at all', (t) async {
      await t.pumpWidget(wrap(const MessageBankingScreen()));

      final Finder deliveredCard =
          find.ancestor(of: find.text(_seedDelivered1), matching: find.byType(Card));
      expect(deliveredCard, findsOneWidget);
      expect(find.descendant(of: deliveredCard, matching: find.byType(IconButton)), findsNothing);
      expect(find.descendant(of: deliveredCard, matching: find.byIcon(Icons.delete_outline)),
          findsNothing);

      final Finder queuedCard =
          find.ancestor(of: find.text(_seedQueued), matching: find.byType(Card));
      expect(find.descendant(of: queuedCard, matching: find.byIcon(Icons.delete_outline)),
          findsOneWidget,
          reason: 'the queued seed entry must keep its own revoke control');
    });

    testWidgets('preserved badge is present on every entry, delivered or queued', (t) async {
      await t.pumpWidget(wrap(const MessageBankingScreen()));
      expect(find.byIcon(Icons.archive_outlined), findsNWidgets(3));
    });

    testWidgets('revoking removes only queued entries; delivered survive', (t) async {
      await t.pumpWidget(wrap(const MessageBankingScreen()));

      await t.tap(find.widgetWithText(TextButton, 'Revoke remaining (1)'));
      await t.pump();

      expect(find.text(_seedQueued), findsNothing);
      expect(find.text(_seedDelivered1), findsOneWidget);
      expect(find.text(_seedDelivered2), findsOneWidget);
      expect(find.textContaining('Revoke remaining'), findsNothing,
          reason: 'no queued entries remain, so the revoke row itself is gone');
    });

    testWidgets('per-entry revoke removes only that queued message', (t) async {
      await t.pumpWidget(wrap(const MessageBankingScreen()));

      final Finder queuedCard =
          find.ancestor(of: find.text(_seedQueued), matching: find.byType(Card));
      final Finder revokeIcon =
          find.descendant(of: queuedCard, matching: find.byIcon(Icons.delete_outline));
      await t.ensureVisible(revokeIcon);
      await t.pumpAndSettle();
      await t.tap(revokeIcon);
      await t.pump();

      expect(find.text(_seedQueued), findsNothing);
      expect(find.text(_seedDelivered1), findsOneWidget);
      expect(find.text(_seedDelivered2), findsOneWidget);
    });

    testWidgets('cycling disclosure is absent under the default window', (t) async {
      await t.pumpWidget(wrap(const MessageBankingScreen()));
      // Default window is 5 nights; the seed only has 1 message queued.
      expect(find.textContaining('This will repeat'), findsNothing);
    });

    testWidgets('cycling disclosure appears once queued count exceeds the window', (t) async {
      await t.pumpWidget(wrap(const MessageBankingScreen()));

      // Shrink the window from the default of 5 down to its floor of 1.
      for (int i = 0; i < 4; i++) {
        await t.tap(find.byIcon(Icons.remove_circle_outline));
        await t.pump();
      }
      expect(find.textContaining('1 nights'), findsOneWidget);
      // 1 queued vs a 1-night window is not yet OVER the threshold.
      expect(find.textContaining('This will repeat'), findsNothing);

      await t.enterText(find.byType(TextField), 'One more for the road');
      await t.pump();
      await t.tap(find.widgetWithText(FilledButton, 'Bank this message'));
      await t.pump();

      // 2 queued vs a 1-night window: the batch will now cycle.
      expect(find.textContaining('This will repeat'), findsOneWidget);
      expect(find.textContaining('2 messages queued for a 1-night window'), findsOneWidget);
    });
  });

  group('message banking — responsive two-pane split (§8.11.1, form_factors.dart)', () {
    // Real columnsAt()-driven threshold (form_factors.dart), matching
    // court_export.dart's own two-pane pattern — not an invented number.
    testWidgets('a genuinely wide viewport (tablet/desktop, >=660px effective) '
        'renders compose and the banked list as two side-by-side panes',
        (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1100, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(wrap(const MessageBankingScreen()));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('bankingTwoPaneRow')), findsOneWidget);
      // Both panes' content is still genuinely present, just rearranged.
      expect(find.text('Record tonight, deliver on her night'), findsOneWidget);
      expect(find.text(_seedQueued), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the Fold5 cover width (344px) keeps the exact stacked single '
        "column unchanged — no two-pane Row at all", (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(344, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(wrap(const MessageBankingScreen()));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('bankingTwoPaneRow')), findsNothing);
      expect(find.text('Record tonight, deliver on her night'), findsOneWidget);
      expect(find.text(_seedQueued), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a standard phone width (390px) also keeps the stacked single '
        'column, not the two-pane Row', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(wrap(const MessageBankingScreen()));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('bankingTwoPaneRow')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('composing and banking a message still works correctly inside '
        'the wide two-pane layout', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1100, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(wrap(const MessageBankingScreen()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Wide-pane goodnight');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Bank this message'));
      await tester.pump();

      expect(find.text('Wide-pane goodnight'), findsOneWidget);
      expect(find.textContaining('2 queued'), findsOneWidget);
    });
  });
}
