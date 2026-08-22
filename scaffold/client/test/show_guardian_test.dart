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

    testWidgets('nothing pending renders a real icon+message empty state, not bare text',
        (t) async {
      await pump(t, const ShowGuardianScreen(initialAsks: []));
      expect(find.text('0 of 3 waiting'), findsOneWidget);
      expect(find.text('Nothing waiting right now.'), findsOneWidget);
      // A real empty-state treatment, not a lone Text node: a calm icon
      // sits with the message rather than the message standing alone.
      expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
      expect(find.textContaining('error'), findsNothing);
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

  group('responsive — Fold5 cover/main, phone, tablet/desktop', () {
    // Fold5 cover (344 CSS px), Fold5 main (~673x841, nearly square), a
    // standard phone (390), and a desktop-scale short-and-wide width (1100)
    // — the four widths this repo's responsive audit requires. Unlike the
    // other files in this batch, this screen uses tester.binding's own
    // surface size (see `pump` above) rather than tester.view — the two
    // control different layers (root surface vs. FlutterView), so the width
    // sweep below drives tester.view directly instead of routing through
    // `pump`, then restores the tall canvas the rest of this file relies on.
    const widths = <String, Size>{
      'fold5 cover': Size(344, 820),
      'fold5 main': Size(673, 841),
      'phone': Size(390, 844),
      'tablet/desktop': Size(1100, 800),
    };

    for (final entry in widths.entries) {
      testWidgets('renders composer, shelf, and the cap dialog without overflow '
          'at ${entry.key}', (t) async {
        t.view.physicalSize = entry.value;
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);

        await t.pumpWidget(wrap(const ShowGuardianScreen(childName: 'Maya')));
        expect(t.takeException(), isNull);

        // Fill the cap and trigger the retirement confirmation dialog — the
        // most content-dense surface this screen can show.
        await t.enterText(find.byType(TextField).first, 'Show me your shoes');
        await t.tap(find.widgetWithText(FilledButton, 'Send the ask'));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);

        await t.enterText(find.byType(TextField).first, 'One more ask');
        await t.tap(find.widgetWithText(FilledButton, 'Send the ask'));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(find.text('Three are already waiting'), findsOneWidget);

        await t.tap(find.text('Cancel'));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      });
    }
  });

  group('guardian showcase — responsive two-pane split (§8.11.1, form_factors.dart)', () {
    testWidgets('a genuinely wide viewport (tablet/desktop, >=660px effective) renders the '
        'ask composer and the activity feed as two side-by-side panes', (t) async {
      await t.binding.setSurfaceSize(const Size(1100, 900));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(const ShowGuardianScreen(childName: 'Maya')));
      await t.pumpAndSettle();

      expect(find.byKey(const Key('showGuardianTwoPaneRow')), findsOneWidget);
      // Pane A content (the composer) and Pane B content (a pending ask)
      // are both genuinely present at once.
      expect(find.text('Ask her to show you something'), findsOneWidget);
      expect(find.text("Show me the biggest dinosaur you've got"), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('the Fold5 cover width (344px) keeps the exact stacked single column '
        'unchanged — no two-pane Row at all', (t) async {
      await t.binding.setSurfaceSize(const Size(344, 900));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(const ShowGuardianScreen(childName: 'Maya')));
      await t.pumpAndSettle();

      expect(find.byKey(const Key('showGuardianTwoPaneRow')), findsNothing);
      expect(find.text('Ask her to show you something'), findsOneWidget);
      expect(find.text("Show me the biggest dinosaur you've got"), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('a standard phone width (390px) also keeps the stacked single column, '
        'not the two-pane Row', (t) async {
      await t.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(const ShowGuardianScreen(childName: 'Maya')));
      await t.pumpAndSettle();

      expect(find.byKey(const Key('showGuardianTwoPaneRow')), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('sending an ask still works correctly inside the wide two-pane layout',
        (t) async {
      await t.binding.setSurfaceSize(const Size(1100, 900));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(const ShowGuardianScreen()));
      await t.pumpAndSettle();

      expect(find.byKey(const Key('showGuardianTwoPaneRow')), findsOneWidget);
      await t.enterText(find.byType(TextField).first, 'Show me your shoes');
      await t.tap(find.widgetWithText(FilledButton, 'Send the ask'));
      await t.pumpAndSettle();

      expect(find.byKey(const Key('showGuardianTwoPaneRow')), findsOneWidget);
      expect(find.text('3 of 3 waiting'), findsOneWidget);
      expect(find.text('Show me your shoes'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });
}
