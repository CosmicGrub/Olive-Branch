// OLIVE BRANCH — showcase screen widget tests. §9.10.
//
// Same posture as invariants_test.dart: assert against the actual widget
// tree a child sees, not the intent behind it.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/showcase_logic.dart';
import 'package:olive_client/showcase_screen.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

void main() {
  group('showcase screen — §9.10', () {
    testWidgets('renders her by name, and both seeded asks', (t) async {
      await t.pumpWidget(wrap(const ShowcaseScreen(childName: 'Maya')));
      expect(find.textContaining('Hi Maya!'), findsOneWidget);
      expect(find.text("Show me the biggest dinosaur you've got"), findsOneWidget);
      expect(find.text('Show me one thing that made you laugh today'), findsOneWidget);
    });

    testWidgets('NO settings affordance exists at any depth', (t) async {
      await t.pumpWidget(wrap(const ShowcaseScreen()));
      expect(find.byIcon(Icons.settings), findsNothing);
      expect(find.byIcon(Icons.settings_outlined), findsNothing);
      expect(find.textContaining('Settings'), findsNothing);
    });

    testWidgets('an ask never shows a count, age, or the word pending', (t) async {
      await t.pumpWidget(wrap(const ShowcaseScreen()));
      for (final forbidden in askForbiddenWords) {
        expect(find.textContaining(forbidden, findRichText: true), findsNothing,
          reason: '"$forbidden" must never reach the child screen');
      }
      // The generic framing line is exactly "<name> asked you something" —
      // never "2 unanswered" or similar.
      expect(find.textContaining('unanswered'), findsNothing);
      expect(find.text('Daddy asked you something'), findsNWidgets(2));
    });

    testWidgets('no error copy, no streak or score language anywhere', (t) async {
      await t.pumpWidget(wrap(const ShowcaseScreen()));
      expect(find.textContaining('error'), findsNothing);
      expect(find.textContaining('Error'), findsNothing);
      expect(find.textContaining('streak'), findsNothing);
      expect(find.textContaining('score'), findsNothing);
    });

    testWidgets('the spontaneous "Look what happened" button is always present', (t) async {
      await t.pumpWidget(wrap(const ShowcaseScreen()));
      expect(find.text('Look what happened!'), findsOneWidget);
    });

    testWidgets('the primary show buttons meet the 48dp touch-target floor', (t) async {
      await t.pumpWidget(wrap(const ShowcaseScreen()));
      final Finder spontaneousTap = find.ancestor(
        of: find.text('Look what happened!'), matching: find.byType(InkWell)).first;
      final Size spontaneous = t.getSize(spontaneousTap);
      expect(spontaneous.height, greaterThanOrEqualTo(48.0));
      final Size showThemButton = t.getSize(find.widgetWithText(FilledButton, 'Show them').first);
      expect(showThemButton.height, greaterThanOrEqualTo(48.0));
    });

    testWidgets('answering an ask removes exactly that ask, keeps the other', (t) async {
      await t.pumpWidget(wrap(const ShowcaseScreen()));
      expect(find.text("Show me the biggest dinosaur you've got"), findsOneWidget);
      expect(find.text('Show me one thing that made you laugh today'), findsOneWidget);

      await t.tap(find.widgetWithText(FilledButton, 'Show them').first);
      await t.pumpAndSettle();

      // Pick an artifact so the "Send it" button becomes enabled.
      await t.tap(find.text('🦖').first);
      await t.pump();
      await t.tap(find.widgetWithText(FilledButton, 'Send it'));
      await t.pumpAndSettle();

      expect(find.text("Show me the biggest dinosaur you've got"), findsNothing);
      expect(find.text('Show me one thing that made you laugh today'), findsOneWidget);
      expect(find.textContaining('Sent to Daddy!'), findsOneWidget);
    });

    testWidgets('the send button stays disabled until something is picked or typed', (t) async {
      await t.pumpWidget(wrap(const ShowcaseScreen()));
      await t.tap(find.text('Look what happened!'));
      await t.pumpAndSettle();

      final sendButton = t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Send it'));
      expect(sendButton.onPressed, isNull);

      await t.enterText(find.byType(TextField), 'A wobbly tooth fell out!');
      await t.pump();
      final enabledSend = t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Send it'));
      expect(enabledSend.onPressed, isNotNull);
    });

    testWidgets('spontaneous shows never require or reference an ask', (t) async {
      await t.pumpWidget(wrap(const ShowcaseScreen()));
      await t.tap(find.text('Look what happened!'));
      await t.pumpAndSettle();
      // No prompt heading appears for a spontaneous show — it starts with her.
      expect(find.text('Pick what you are showing'), findsOneWidget);
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
      testWidgets('renders the ask cards and the capture sheet without overflow '
          'at ${entry.key}', (t) async {
        t.view.physicalSize = entry.value;
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);

        await t.pumpWidget(wrap(const ShowcaseScreen(childName: 'Ivy')));
        expect(t.takeException(), isNull);

        // The capture sheet's Wrap of six artifact tiles plus its own
        // bottom-inset padding is the most layout-heavy surface this screen
        // owns — open it at every width.
        await t.tap(find.text('Look what happened!'));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(find.text('Pick what you are showing'), findsOneWidget);
      });
    }
  });
}
