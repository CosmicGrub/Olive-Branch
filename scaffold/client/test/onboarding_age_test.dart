// OLIVE BRANCH — onboarding_age.dart / onboarding_logic.dart tests. §8.5.2.
//
// The central invariant under test: nothing she taps can raise a gate. A
// guardian-entered birth date always wins, and the disagreement is recorded,
// never surfaced to her.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/onboarding_age.dart';
import 'package:olive_client/onboarding_logic.dart';

void main() {
  final fixedNow = DateTime(2026, 8, 4);

  // Sixteen age tiles plus the continue button run taller than the default
  // 800x600 test surface, which leaves "Next" (and the last few tiles)
  // off-screen and un-hit-testable inside the scaffold's scroll view — a
  // real device just scrolls; the test gets a tall surface instead so every
  // tap resolves without needing to simulate a scroll gesture first.
  Future<void> pump(WidgetTester tester, ValueChanged<AgeStep> onContinue, {String? birthDate}) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: ObAgeScreen(
      birthDate: birthDate, onContinue: onContinue, now: fixedNow)));
  }

  group('acceptAge — pure logic', () {
    test('a self-reported tap is kept but never authoritative when no birth date exists', () {
      final step = acceptAge(10, null, fixedNow);
      expect(step.selfReported, 10);
      expect(step.authoritative, isNull);
      expect(step.disagrees, isFalse);
      expect(effectiveAge(step), 10);
    });

    test('the guardian birth date always wins over her tap, and the gap is recorded', () {
      // Six years old, but taps 17 hoping for a privacy tier she has not earned.
      final step = acceptAge(17, '2020-01-01', fixedNow);
      expect(step.selfReported, 17);
      expect(step.authoritative, 6);
      expect(step.disagrees, isTrue);
      expect(effectiveAge(step), 6, reason: 'authoritative must win — nothing she taps can raise a gate');
    });

    test('taps are clamped to the supported range', () {
      expect(acceptAge(99, null, fixedNow).selfReported, maxAge);
      expect(acceptAge(0, null, fixedNow).selfReported, minAge);
    });

    test('skipping (no tap) is a supported, non-trapping outcome', () {
      final step = acceptAge(null, null, fixedNow);
      expect(step.skipped, isTrue);
      expect(effectiveAge(step), isNull);
    });
  });

  testWidgets('tapping a number and continuing reports that self-reported age', (tester) async {
    AgeStep? got;
    await pump(tester, (s) => got = s);
    await tester.tap(find.text('10'));
    await tester.pump();
    await tester.tap(find.text('Next'));
    await tester.pump();
    expect(got!.selfReported, 10);
    expect(got!.skipped, isFalse);
  });

  testWidgets('skip button reports a skipped step, never trapping her here', (tester) async {
    AgeStep? got;
    await pump(tester, (s) => got = s);
    await tester.tap(find.text('Skip for now'));
    await tester.pump();
    expect(got!.skipped, isTrue);
  });

  testWidgets('a guardian birth date on record silently overrides her tap in the outcome', (tester) async {
    AgeStep? got;
    await pump(tester, (s) => got = s, birthDate: '2020-01-01');
    await tester.tap(find.text('17'));
    await tester.pump();
    await tester.tap(find.text('Next'));
    await tester.pump();
    expect(got!.selfReported, 17);
    expect(got!.authoritative, 6);
    expect(effectiveAge(got!), 6);
    // The disagreement must never be shown to her on this screen.
    expect(find.textContaining('disagree'), findsNothing);
    expect(find.textContaining('wrong'), findsNothing);
  });

  testWidgets('renders one tile per supported age, minAge through maxAge', (tester) async {
    await pump(tester, (_) {});
    for (var a = minAge; a <= maxAge; a++) {
      expect(find.text('$a'), findsOneWidget);
    }
  });

  testWidgets('no settings affordance and no guardian-authority path exists here', (tester) async {
    await pump(tester, (_) {});
    expect(find.byIcon(Icons.settings), findsNothing);
    expect(find.textContaining('Settings'), findsNothing);
    expect(find.textContaining('guardian'), findsNothing);
    expect(find.textContaining('grown-up'), findsNothing);
  });

  testWidgets('every tappable age tile is at least 48dp on its shortest side', (tester) async {
    await pump(tester, (_) {});
    final size = tester.getSize(find.text('10').hitTestable());
    // The tile itself (ancestor) is what must clear 48dp; find the Material
    // ancestor's rendered size via the ink well ancestor ancestor size.
    expect(size.width, greaterThan(0));
    final tileFinder = find.ancestor(of: find.text('10'), matching: find.byType(InkWell)).first;
    final tileSize = tester.getSize(tileFinder);
    expect(tileSize.width, greaterThanOrEqualTo(48));
    expect(tileSize.height, greaterThanOrEqualTo(48));
  });
}
