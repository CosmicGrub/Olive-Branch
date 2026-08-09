// OLIVE BRANCH — onboarding_name.dart / onboarding_logic.dart tests. §8.5.1.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/onboarding_logic.dart';
import 'package:olive_client/onboarding_name.dart';

void main() {
  Future<void> pump(WidgetTester tester, ValueChanged<NameStep> onContinue) =>
      tester.pumpWidget(MaterialApp(home: ObNameScreen(
        fallbackName: 'you', onContinue: onContinue)));

  group('acceptName / resolveNameStep — pure logic', () {
    test('her spelling stands, uncorrected', () {
      final r = acceptName('OLIVEE', 'Olive');
      expect(r.ok, isTrue);
      expect(r.step!.spelled, 'OLIVEE');
      expect(r.step!.skipped, isFalse);
    });

    test('empty input falls back and is marked skipped', () {
      final r = acceptName('   ', 'Olive');
      expect(r.ok, isTrue);
      expect(r.step!.spelled, 'Olive');
      expect(r.step!.skipped, isTrue);
    });

    test('a paste past MAX_NAME_LENGTH truncates rather than failing the flow', () {
      final tooLong = 'a' * 40;
      final outcome = acceptName(tooLong, 'you');
      expect(outcome.ok, isFalse);
      final resolved = resolveNameStep(tooLong, 'you');
      expect(resolved.spelled.length, maxNameLength);
      expect(resolved.skipped, isFalse);
    });

    test('renameSelf lets her change it later without validation', () {
      const step = NameStep(spelled: 'Ivy', fallback: 'you', skipped: false);
      final renamed = renameSelf(step, 'Ivyyyy');
      expect(renamed.spelled, 'Ivyyyy');
    });
  });

  testWidgets('typing her name and continuing reports exactly what she typed', (tester) async {
    NameStep? got;
    await pump(tester, (s) => got = s);
    await tester.enterText(find.byType(TextField), 'Olivee');
    await tester.tap(find.text('Next'));
    await tester.pump();
    expect(got!.spelled, 'Olivee');
    expect(got!.skipped, isFalse);
  });

  testWidgets('skipping reports the fallback name, marked skipped', (tester) async {
    NameStep? got;
    await pump(tester, (s) => got = s);
    await tester.tap(find.text('Skip for now'));
    await tester.pump();
    expect(got!.spelled, 'you');
    expect(got!.skipped, isTrue);
  });

  testWidgets('continuing with a blank field behaves exactly like skip', (tester) async {
    NameStep? got;
    await pump(tester, (s) => got = s);
    await tester.tap(find.text('Next'));
    await tester.pump();
    expect(got!.skipped, isTrue);
    expect(got!.spelled, 'you');
  });

  testWidgets('the mic button is an honest stub, never a fake success', (tester) async {
    NameStep? got;
    await pump(tester, (s) => got = s);
    await tester.tap(find.byIcon(Icons.mic_none_rounded));
    await tester.pump();
    expect(find.textContaining("isn't ready"), findsOneWidget);
    expect(got, isNull);
  });

  testWidgets('no settings affordance exists anywhere on this screen', (tester) async {
    await pump(tester, (_) {});
    expect(find.byIcon(Icons.settings), findsNothing);
    expect(find.byIcon(Icons.settings_outlined), findsNothing);
    expect(find.textContaining('Settings'), findsNothing);
  });

  testWidgets('none of the audited-forbidden onboarding copy appears on screen', (tester) async {
    await pump(tester, (_) {});
    await tester.enterText(find.byType(TextField), 'Zz');
    await tester.pump();
    for (final word in onboardingForbidden) {
      expect(find.textContaining(word, findRichText: true), findsNothing,
        reason: '"$word" must never appear in the first-run flow');
    }
  });

  test('auditOnboardingCopy flags every forbidden phrase and nothing else', () {
    expect(auditOnboardingCopy("What's your name?").ok, isTrue);
    expect(auditOnboardingCopy('Try again!').ok, isFalse);
    expect(auditOnboardingCopy('Good job!').ok, isFalse);
  });

  group('responsive — required audit viewports', () {
    // Fold5 cover screen, Fold5 unfolded main screen, a standard phone, and a
    // desktop/tablet-scale width. A maxed-out, unbroken (space-free) name is
    // typed at each width — the single case with real width pressure, since
    // the live preview (fontSize 44) has no spaces to wrap on.
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
        await pump(tester, (_) {});
        await tester.enterText(find.byType(TextField), 'X' * maxNameLength);
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }
  });
}
