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

  group('kiosk PIN section — §8.3, §7.1', () {
    testWidgets('with no setGuardianPin wired, shows an honest stub and no PIN fields',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(home: GuardianSetupScreen()));
      expect(find.textContaining('Kiosk PIN setup has no backend wired'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('a matching valid PIN calls setGuardianPin and shows confirmation',
        (tester) async {
      String? sent;
      await tester.pumpWidget(MaterialApp(home: GuardianSetupScreen(
        setGuardianPin: (pin) async { sent = pin; },
      )));
      // The PIN section's own stub message must be gone now that it's wired
      // -- the unrelated passkey stub above it (registerPasskey is still
      // null in this test) is expected to remain, so this checks the
      // PIN-specific text only, not the broader "isn't connected" phrase
      // both stubs would otherwise share.
      expect(find.textContaining('Kiosk PIN setup has no backend wired'), findsNothing);
      await tester.enterText(find.byType(TextField).at(0), '5193');
      await tester.enterText(find.byType(TextField).at(1), '5193');
      await tester.ensureVisible(find.text('Save PIN'));
      await tester.tap(find.text('Save PIN'));
      await tester.pumpAndSettle();
      expect(sent, '5193');
      expect(find.text('PIN updated.'), findsOneWidget);
    });

    testWidgets('mismatched PINs are refused locally — setGuardianPin is never called',
        (tester) async {
      var called = false;
      await tester.pumpWidget(MaterialApp(home: GuardianSetupScreen(
        setGuardianPin: (pin) async { called = true; },
      )));
      await tester.enterText(find.byType(TextField).at(0), '5193');
      await tester.enterText(find.byType(TextField).at(1), '9999');
      await tester.ensureVisible(find.text('Save PIN'));
      await tester.tap(find.text('Save PIN'));
      await tester.pump();
      expect(called, isFalse);
      expect(find.textContaining("don't match"), findsOneWidget);
    });

    testWidgets('a too-short PIN is refused locally — setGuardianPin is never called',
        (tester) async {
      var called = false;
      await tester.pumpWidget(MaterialApp(home: GuardianSetupScreen(
        setGuardianPin: (pin) async { called = true; },
      )));
      await tester.enterText(find.byType(TextField).at(0), '12');
      await tester.enterText(find.byType(TextField).at(1), '12');
      await tester.ensureVisible(find.text('Save PIN'));
      await tester.tap(find.text('Save PIN'));
      await tester.pump();
      expect(called, isFalse);
      expect(find.text('Enter a 4-8 digit PIN.'), findsOneWidget);
    });

    testWidgets('a server-side rejection surfaces the real reason, not a guess',
        (tester) async {
      await tester.pumpWidget(MaterialApp(home: GuardianSetupScreen(
        setGuardianPin: (pin) async { throw Exception('boom'); },
      )));
      await tester.enterText(find.byType(TextField).at(0), '5193');
      await tester.enterText(find.byType(TextField).at(1), '5193');
      await tester.ensureVisible(find.text('Save PIN'));
      await tester.tap(find.text('Save PIN'));
      await tester.pumpAndSettle();
      expect(find.text('Could not set your PIN.'), findsOneWidget);
    });
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
