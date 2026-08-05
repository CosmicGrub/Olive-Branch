// OLIVE BRANCH — guardian_setup.dart tests. §8.5.0, §11.
//
// The central invariant under test: this screen never fakes a capability. No
// registerPasskey callback means it says so honestly and never calls
// onComplete, no matter how it's tapped.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/guardian_setup.dart';

void main() {
  testWidgets('with no real passkey service wired, tapping is honest and never completes', (tester) async {
    var completed = false;
    await tester.pumpWidget(MaterialApp(home: GuardianSetupScreen(onComplete: () => completed = true)));
    expect(find.textContaining("isn't connected in this preview build"), findsOneWidget);
    await tester.tap(find.text('Continue with passkey'));
    await tester.pump();
    expect(completed, isFalse, reason: 'must never fake a capability grant');
    expect(find.textContaining("isn't connected"), findsWidgets);
  });

  testWidgets('a successful registerPasskey calls onComplete', (tester) async {
    var completed = false;
    await tester.pumpWidget(MaterialApp(home: GuardianSetupScreen(
      registerPasskey: () async => PasskeyOutcome.success,
      onComplete: () => completed = true)));
    await tester.tap(find.text('Continue with passkey'));
    // Not pumpAndSettle(): on success the button's own CircularProgressIndicator
    // is left spinning (a real app navigates away via onComplete at this
    // point) — pumpAndSettle would wait forever for an animation with no
    // fixed end. A couple of frames is enough for the awaited Future to
    // resolve and onComplete to fire.
    await tester.pump();
    await tester.pump();
    expect(completed, isTrue);
  });

  testWidgets('a failed registerPasskey shows a plain message and never calls onComplete', (tester) async {
    var completed = false;
    await tester.pumpWidget(MaterialApp(home: GuardianSetupScreen(
      registerPasskey: () async => PasskeyOutcome.unavailable,
      onComplete: () => completed = true)));
    await tester.tap(find.text('Continue with passkey'));
    await tester.pumpAndSettle();
    expect(completed, isFalse);
    expect(find.textContaining('Could not complete'), findsOneWidget);
  });

  testWidgets('reviewing the family agreement is an honest stub when unwired', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: GuardianSetupScreen()));
    await tester.tap(find.text('Review the family agreement'));
    await tester.pump();
    expect(find.textContaining('not built yet'), findsOneWidget);
  });

  testWidgets('never presents a password field — passkey only, per §11', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: GuardianSetupScreen()));
    expect(find.byType(TextField), findsNothing);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.textContaining('Password'), findsNothing);
  });

  testWidgets('the continue action clears 48dp', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: GuardianSetupScreen()));
    // FilledButton.icon() returns a private subtype, so a predicate (which
    // checks `is FilledButton`) is used rather than byType (exact runtimeType).
    final size = tester.getSize(find.ancestor(
      of: find.text('Continue with passkey'),
      matching: find.byWidgetPredicate((w) => w is FilledButton)));
    expect(size.height, greaterThanOrEqualTo(48));
  });

  group('responsive — required audit viewports', () {
    // Fold5 cover screen, Fold5 unfolded main screen, a standard phone, and a
    // desktop/tablet-scale width. Unwired state (the info banner is on
    // screen) is the most content-heavy of this screen's states.
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
        await tester.pumpWidget(const MaterialApp(home: GuardianSetupScreen()));
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }
  });
}
