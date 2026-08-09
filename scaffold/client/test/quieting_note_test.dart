// OLIVE BRANCH — the quieting tests. P2, §21.5.
//
// The invariant that matters most: everything here is gated on AGE, never on
// how much or how little she has used the app — so there must be no
// last-opened date, no day-count, and no phrase that could read as scoring
// her absence, anywhere in this tree.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/quieting_note.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

void main() {
  group('quieting — pure port of maturation.ts QUIETING', () {
    test('at the exact fade age, a scaffold counts as faded, not showing', () {
      expect(scaffoldsFadedAt(11).map((s) => s.feature), contains('sleeps_countdown'));
      expect(scaffoldsShowingAt(11).map((s) => s.feature), isNot(contains('sleeps_countdown')));
    });

    test('one year younger, the same scaffold is still showing', () {
      expect(scaffoldsShowingAt(10).map((s) => s.feature), contains('sleeps_countdown'));
      expect(scaffoldsFadedAt(10).map((s) => s.feature), isNot(contains('sleeps_countdown')));
    });

    test('an unknown feature defaults to still showing', () {
      expect(showsScaffold('not_a_real_feature', 99), isTrue);
    });

    test('at seventeen, every scaffold has faded', () {
      expect(scaffoldsShowingAt(17), isEmpty);
      expect(scaffoldsFadedAt(17), hasLength(quieting.length));
    });
  });

  group('quieting screen — child-facing', () {
    testWidgets('a young child sees scaffolds still showing, none faded', (t) async {
      await t.pumpWidget(wrap(const QuietingScreen(childName: 'Maya', age: 8)));
      expect(find.text('Still here for now'), findsOneWidget);
      expect(find.text('Quieter now'), findsNothing);
      expect(find.text('Counting sleeps until visits'), findsOneWidget);
    });

    testWidgets('an older teen sees the faded section, not the showing one', (t) async {
      await t.pumpWidget(wrap(const QuietingScreen(childName: 'Maya', age: 17)));
      expect(find.text('Quieter now'), findsOneWidget);
      expect(find.text('Still here for now'), findsNothing);
    });

    testWidgets('permanent features are always present regardless of age', (t) async {
      await t.pumpWidget(wrap(const QuietingScreen(childName: 'Maya', age: 8)));
      expect(find.text('Your journal'), findsOneWidget);
      expect(find.text('Your calendar'), findsOneWidget);
      expect(find.text('Your calls'), findsOneWidget);
      expect(find.text('Your archive'), findsOneWidget);
    });

    testWidgets('the reassurance copy explicitly denies this is about her behaviour', (t) async {
      await t.pumpWidget(wrap(const QuietingScreen(childName: 'Maya', age: 12)));
      expect(find.textContaining("isn't about anything you did"), findsOneWidget);
    });

    testWidgets('NO absence-scoring, streak, or guilt language anywhere', (t) async {
      await t.pumpWidget(wrap(const QuietingScreen(childName: 'Maya', age: 12)));
      expect(find.textContaining("haven't"), findsNothing);
      expect(find.textContaining('streak'), findsNothing);
      expect(find.textContaining('score'), findsNothing);
      expect(find.textContaining(RegExp(r'\d+ days')), findsNothing);
      expect(find.textContaining(RegExp(r'last (opened|used|visited)')), findsNothing);
    });

    testWidgets('NO settings affordance exists anywhere', (t) async {
      await t.pumpWidget(wrap(const QuietingScreen(childName: 'Maya', age: 12)));
      expect(find.byIcon(Icons.settings), findsNothing);
      expect(find.byIcon(Icons.settings_outlined), findsNothing);
    });

    group('responsive — no overflow at any required viewport width', () {
      // Age 14 renders both the "faded" and "still here" sections plus the
      // permanent-features card, so this exercises the fullest layout.
      Widget buildScreen() => wrap(const QuietingScreen(childName: 'Maya', age: 14));

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

    testWidgets('a non-faded quieting tile pairs its caption text with '
        'onPrimaryContainer, not onSurfaceVariant, to match its '
        'primaryContainer background (same pairing bug exchange_screen.dart '
        "'s _HandoffCard was fixed for)", (t) async {
      await t.pumpWidget(wrap(const QuietingScreen(childName: 'Maya', age: 8)));
      const caption = "You can read a calendar now, so that's just there when you want it.";
      final BuildContext context = t.element(find.text(caption));
      final ColorScheme scheme = Theme.of(context).colorScheme;
      final Text captionWidget = t.widget(find.text(caption));
      expect(captionWidget.style!.color, scheme.onPrimaryContainer.withValues(alpha: 0.7));
    });

    testWidgets('a faded quieting tile keeps onSurfaceVariant, matching its '
        'neutral surfaceContainerHighest background', (t) async {
      await t.pumpWidget(wrap(const QuietingScreen(childName: 'Maya', age: 17)));
      const caption = "You can read a calendar now, so that's just there when you want it.";
      final BuildContext context = t.element(find.text(caption));
      final ColorScheme scheme = Theme.of(context).colorScheme;
      final Text captionWidget = t.widget(find.text(caption));
      expect(captionWidget.style!.color, scheme.onSurfaceVariant);
    });

    testWidgets('privacy banner uses the house 12-radius compact-banner shape '
        'shared with expenses_screen/meds_care/morning_briefing/care_note/'
        'guardian_setup', (t) async {
      await t.pumpWidget(wrap(const QuietingScreen(childName: 'Maya', age: 8)));
      final container = t.widget<Container>(find.ancestor(
        of: find.byIcon(Icons.spa_outlined),
        matching: find.byType(Container),
      ).first);
      final decoration = container.decoration! as BoxDecoration;
      expect((decoration.borderRadius! as BorderRadius).topLeft, const Radius.circular(12));
      expect(container.padding, const EdgeInsets.all(12));
    });
  });
}
