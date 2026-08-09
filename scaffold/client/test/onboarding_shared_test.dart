// OLIVE BRANCH — onboarding_shared.dart tests. Shared chrome for the child's
// first-run flow — not itself a MARKUP screen, but every screen built on it
// (onboarding_name.dart / onboarding_age.dart / onboarding_who.dart /
// colour_pick.dart / birthday_month.dart / birthday_day.dart /
// birthday_marked.dart) inherits its invariants for free, so a break here is
// a break in all seven.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/onboarding_shared.dart';

void main() {
  Widget scaffold({
    String title = 'A title',
    String? subtitle,
    Widget body = const SizedBox.shrink(),
    VoidCallback? onContinue = _noop,
    VoidCallback? onSkip,
    bool continueEnabled = true,
    bool showContinueButton = true,
  }) => MaterialApp(home: ChildOnboardingScaffold(
    title: title, subtitle: subtitle, body: body, onContinue: onContinue,
    onSkip: onSkip, continueEnabled: continueEnabled, showContinueButton: showContinueButton));

  testWidgets('renders the title, subtitle, and body', (tester) async {
    await tester.pumpWidget(scaffold(
      title: 'Pick one', subtitle: 'Any one is fine', body: const Text('BODY MARKER')));
    expect(find.text('Pick one'), findsOneWidget);
    expect(find.text('Any one is fine'), findsOneWidget);
    expect(find.text('BODY MARKER'), findsOneWidget);
  });

  testWidgets('no settings affordance exists anywhere — every inheriting screen gets this for free',
      (tester) async {
    await tester.pumpWidget(scaffold(onSkip: () {}));
    expect(find.byIcon(Icons.settings), findsNothing);
    expect(find.byIcon(Icons.settings_outlined), findsNothing);
    expect(find.textContaining('Settings'), findsNothing);
  });

  testWidgets('the continue button is disabled when continueEnabled is false', (tester) async {
    await tester.pumpWidget(scaffold(continueEnabled: false));
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
  });

  testWidgets('the continue button is hidden entirely when showContinueButton is false',
      (tester) async {
    await tester.pumpWidget(scaffold(showContinueButton: false, onContinue: null));
    expect(find.byType(FilledButton), findsNothing);
    expect(find.text('Next'), findsNothing);
  });

  testWidgets('the skip link only appears when onSkip is supplied', (tester) async {
    await tester.pumpWidget(scaffold());
    expect(find.text('Skip for now'), findsNothing);

    await tester.pumpWidget(scaffold(onSkip: () {}));
    expect(find.text('Skip for now'), findsOneWidget);
  });

  testWidgets('§8.4 — the continue button and the skip link both clear 48dp', (tester) async {
    await tester.pumpWidget(scaffold(onSkip: () {}));
    final continueSize = tester.getSize(find.byType(FilledButton));
    expect(continueSize.height, greaterThanOrEqualTo(48.0));
    final skipSize = tester.getSize(find.ancestor(
      of: find.text('Skip for now'), matching: find.byType(TextButton)));
    expect(skipSize.height, greaterThanOrEqualTo(48.0));
  });

  group('TapChoice', () {
    testWidgets('clears the minSide minimum on both axes and reports taps', (tester) async {
      var tapped = false;
      await tester.pumpWidget(MaterialApp(home: Material(child: TapChoice(
        label: 'Pick me', selected: false, minSide: 64, onTap: () => tapped = true))));
      final size = tester.getSize(find.byType(InkWell));
      expect(size.width, greaterThanOrEqualTo(64));
      expect(size.height, greaterThanOrEqualTo(64));
      await tester.tap(find.text('Pick me'));
      expect(tapped, isTrue);
    });

    testWidgets('a dim tile is shown, not hidden, and never nudges', (tester) async {
      await tester.pumpWidget(MaterialApp(home: Material(child: TapChoice(
        label: 'Pending', selected: false, dim: true, onTap: () {}))));
      expect(find.text('Pending'), findsOneWidget);
      final opacity = tester.widget<Opacity>(find.byType(Opacity));
      expect(opacity.opacity, lessThan(1.0));
    });
  });

  group('responsive — required audit viewports', () {
    // Fold5 cover screen, Fold5 unfolded main screen, a standard phone, and a
    // desktop/tablet-scale width. Long title/subtitle copy plus a Wrap of
    // eight TapChoice tiles is the layout every real screen built on this
    // scaffold actually stresses it with.
    const viewports = {
      'Fold5 cover (344x882)': Size(344, 882),
      'Fold5 main (673x841)': Size(673, 841),
      'phone (390x844)': Size(390, 844),
      'tablet/desktop (1200x800)': Size(1200, 800),
    };

    Widget stressed() => scaffold(
      title: 'A reasonably long title to test wrapping behaviour',
      subtitle: 'A subtitle that is also fairly long, to see how it behaves across widths',
      onSkip: () {},
      body: Wrap(spacing: 10, runSpacing: 10, children: [
        for (var i = 0; i < 8; i++) TapChoice(label: 'Option $i', selected: i == 0, onTap: () {}),
      ]),
    );

    for (final entry in viewports.entries) {
      testWidgets('renders without overflow at ${entry.key}', (tester) async {
        await tester.binding.setSurfaceSize(entry.value);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(stressed());
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }
  });
}

void _noop() {}
