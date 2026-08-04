// Boot + navigation smoke tests for the unified app. Previously two separate
// entry points (main.dart / main_guardian.dart) built into two APKs sharing
// one applicationId — this file now proves both halves are genuinely
// reachable through the single real entry gate a family would see, not just
// that each widget renders in isolation (see test/invariants_test.dart for
// the per-widget behavioral checks, §8.1/§8.2/§8.3).
import 'package:flutter_test/flutter_test.dart';

import 'package:olive_client/main.dart';

void main() {
  testWidgets('boots to the entry gate, not directly to either home',
      (WidgetTester tester) async {
    await tester.pumpWidget(const OliveDemo());
    expect(find.text('Welcome'), findsOneWidget);
    expect(find.text("My child's device"), findsOneWidget);
    expect(find.text("The grown-up's device"), findsOneWidget);
    expect(find.text('Hi Ivy'), findsNothing);
  });

  testWidgets("choosing the child's device reaches ChildHome",
      (WidgetTester tester) async {
    await tester.pumpWidget(const OliveDemo());
    await tester.tap(find.text("My child's device"));
    await tester.pumpAndSettle();
    expect(find.text('Hi Ivy'), findsOneWidget);
    expect(find.text('Homework'), findsOneWidget);
  });

  testWidgets("choosing the grown-up's device reaches GuardianHome",
      (WidgetTester tester) async {
    await tester.pumpWidget(const OliveDemo());
    await tester.tap(find.text("The grown-up's device"));
    await tester.pumpAndSettle();
    expect(find.text('Ivy'), findsOneWidget);
    expect(find.text('Winding down for bed'), findsOneWidget);
  });

  // Parity coverage: every real (non-stub) tile on both sides is reachable
  // end to end from app boot, not just importable in isolation.
  testWidgets("ChildHome's My list tile reaches the real WantsNeedsScreen",
      (WidgetTester tester) async {
    await tester.pumpWidget(const OliveDemo());
    await tester.tap(find.text("My child's device"));
    await tester.pumpAndSettle();
    await tester.tap(find.text('My list'));
    await tester.pumpAndSettle();
    expect(find.text('Things I want'), findsOneWidget);
    expect(find.text('Things I need'), findsOneWidget);
  });

  Future<void> expectGuardianTileReaches(
      WidgetTester tester, String tile, String expectedText) async {
    await tester.pumpWidget(const OliveDemo());
    await tester.tap(find.text("The grown-up's device"));
    await tester.pumpAndSettle();
    await tester.tap(find.text(tile));
    await tester.pumpAndSettle();
    expect(find.textContaining(expectedText), findsOneWidget,
      reason: '$tile tile should reach a screen containing "$expectedText"');
  }

  testWidgets('GuardianHome Message banking tile reaches the real screen',
      (WidgetTester tester) =>
        expectGuardianTileReaches(tester, 'Message banking', 'Bank this message'));

  testWidgets('GuardianHome Emergency card tile reaches the real screen',
      (WidgetTester tester) =>
        expectGuardianTileReaches(tester, 'Emergency card', 'ALLERGIES'));

  testWidgets('GuardianHome Handover notes tile reaches the real screen',
      (WidgetTester tester) => expectGuardianTileReaches(
        tester, 'Handover notes', "can't be edited or removed"));

  testWidgets('GuardianHome stub tiles show honest not-built-yet feedback',
      (WidgetTester tester) async {
    await tester.pumpWidget(const OliveDemo());
    await tester.tap(find.text("The grown-up's device"));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Exchange'));
    await tester.pump();
    expect(find.textContaining('not built yet'), findsOneWidget);
  });
}
