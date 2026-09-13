// OLIVE BRANCH — onboarding_who.dart / onboarding_logic.dart tests. §8.5.3.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/onboarding_logic.dart';
import 'package:olive_client/onboarding_who.dart';

const dad = Grownup(userId: 'dad', label: 'Dad', joined: true);
const mom = Grownup(userId: 'mom', label: 'Mom', joined: true);
const stepdad = Grownup(userId: 'stepdad', label: 'Steve', joined: false);

void main() {
  Future<void> pump(WidgetTester tester, List<Grownup> grownups, ValueChanged<WhoStep> onContinue) =>
      tester.pumpWidget(MaterialApp(home: ObWhoScreen(grownups: grownups, onContinue: onContinue)));

  group('whoStep / toggleWho — pure logic', () {
    test('one joined guardian: no choice at all, just told', () {
      final step = whoStep(const [dad]);
      expect(step.kind, WhoKind.noChoice);
      expect(step.only!.label, 'Dad');
      expect(step.line, "You're here to talk to Dad.");
    });

    test('two joined guardians: both selected by default', () {
      final step = whoStep(const [dad, mom]);
      expect(step.kind, WhoKind.choose);
      expect(step.selected, containsAll(['dad', 'mom']));
    });

    test('the last selection can never be turned off — she may not end up with nobody', () {
      var step = whoStep(const [dad, mom]);
      step = toggleWho(step, 'dad');
      expect(step.selected, ['mom']);
      step = toggleWho(step, 'mom'); // would empty it
      expect(step.selected, ['mom'], reason: 'no-op: the last one cannot be deselected');
    });

    test('nobody joined yet is a supported, neutral state', () {
      final step = whoStep(const []);
      expect(step.kind, WhoKind.nobodyYet);
      expect(step.line, contains('Nobody is here yet'));
    });
  });

  testWidgets('a single guardian is told, not asked — no toggle UI appears', (tester) async {
    await pump(tester, const [dad], (_) {});
    expect(find.text('Dad'), findsOneWidget);
    expect(find.text("You're here to talk to Dad."), findsOneWidget);
  });

  testWidgets('two guardians render as toggleable choices, both selected to start', (tester) async {
    WhoStep? got;
    await pump(tester, const [dad, mom], (s) => got = s);
    await tester.tap(find.text('Next'));
    await tester.pump();
    expect(got!.kind, WhoKind.choose);
    expect(got!.selected, containsAll(['dad', 'mom']));
  });

  testWidgets('deselecting one of two leaves the other, and the last cannot be removed', (tester) async {
    WhoStep? got;
    await pump(tester, const [dad, mom], (s) => got = s);
    await tester.tap(find.text('Dad'));
    await tester.pump();
    await tester.tap(find.text('Mom')); // attempt to deselect the last one
    await tester.pump();
    await tester.tap(find.text('Next'));
    await tester.pump();
    expect(got!.selected, ['mom']);
  });

  testWidgets('a not-yet-joined grownup appears greyed, with no nudge copy', (tester) async {
    await pump(tester, const [dad, stepdad], (_) {});
    expect(find.text('Steve'), findsOneWidget);
    expect(find.textContaining('invite'), findsNothing);
    expect(find.textContaining('Invite'), findsNothing);
    expect(find.textContaining('waiting'), findsNothing);
  });

  testWidgets('nobody-here-yet state renders neutral copy, no error framing', (tester) async {
    await pump(tester, const [], (_) {});
    expect(find.textContaining('Nobody is here yet'), findsWidgets);
    expect(find.textContaining('error'), findsNothing);
  });

  testWidgets('no settings affordance exists on this screen', (tester) async {
    await pump(tester, const [dad, mom], (_) {});
    expect(find.byIcon(Icons.settings), findsNothing);
    expect(find.textContaining('Settings'), findsNothing);
  });

  group('responsive — required audit viewports', () {
    // Fold5 cover screen, Fold5 unfolded main screen, a standard phone, and a
    // desktop/tablet-scale width. The "choose" state plus a not-yet-joined
    // grownup exercises both Wrap sections at once.
    const viewports = {
      'Fold5 cover (344x882)': Size(344, 882),
      'Fold5 main (673x841)': Size(673, 841),
      'phone (390x844)': Size(390, 844),
      'tablet/desktop (1200x800)': Size(1200, 800),
    };

    for (final entry in viewports.entries) {
      testWidgets('renders without overflow at ${entry.key}', (tester) async {
        await tester.binding.setSurfaceSize(entry.value);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await pump(tester, const [dad, mom, stepdad], (_) {});
        expect(tester.takeException(), isNull);
      });
    }
  });
}
