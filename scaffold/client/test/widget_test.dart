// Boot + navigation smoke tests for the unified app. Previously two separate
// entry points (main.dart / main_guardian.dart) built into two APKs sharing
// one applicationId — this file now proves both halves are genuinely
// reachable through the single real entry gate a family would see, not just
// that each widget renders in isolation (see test/invariants_test.dart for
// the per-widget behavioral checks, §8.1/§8.2/§8.3).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:olive_client/exchange_screen.dart';
import 'package:olive_client/expenses_screen.dart';
import 'package:olive_client/game_checkers.dart';
import 'package:olive_client/game_dotsboxes.dart';
import 'package:olive_client/game_tictactoe.dart';
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
    // Standard tier, below Hero/Featured — intuitivism sub-project 2's
    // 3-tier hierarchy moved "My list" further down than the default
    // 800x600 test viewport shows without a scroll step.
    await tester.ensureVisible(find.text('My list'));
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
    await tester.ensureVisible(find.text(tile));
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

  testWidgets('GuardianHome Care note tile reaches the real screen',
      (WidgetTester tester) =>
        expectGuardianTileReaches(tester, 'Care note', 'Not evidence'));

  // CallScreen's initState kicks off a real (async) fetch to the room-
  // coordination server via dart:io HttpClient. flutter_test stubs every
  // HttpClient to return 400 rather than touching the network — so in this
  // suite the fetch really runs and really fails, landing on CallScreen's
  // real error branch. That still proves the button reaches real, executing
  // CallScreen code, not a stub; the network-reachable path is proven
  // separately by the on-device suite (see HANDOFF notes).
  testWidgets("ChildHome's Call button reaches the real CallScreen",
      (WidgetTester tester) async {
    await tester.pumpWidget(const OliveDemo());
    await tester.tap(find.text("My child's device"));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Call Dad'));
    await tester.pumpAndSettle();
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets("GuardianHome's Call button reaches the real CallScreen",
      (WidgetTester tester) async {
    await tester.pumpWidget(const OliveDemo());
    await tester.tap(find.text("The grown-up's device"));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Call Ivy'));
    await tester.pumpAndSettle();
    expect(find.text('Try again'), findsOneWidget);
  });

  // Exchange and Expenses used to be this suite's stub-feedback example, but
  // an earlier wiring pass gave both real destinations. Availability now has
  // a real implementing screen too (client/lib/availability_screen.dart,
  // backed by server/routes.mjs's real GET/PUT availability endpoints) — but
  // OliveDemo's own static demo data (main.dart) still doesn't thread a real
  // baseUrl/guardianId/childId into GuardianMoreScreen, so tapping it here
  // still shows honest feedback: not "not built yet" (false, now that a real
  // screen exists), but "not connected" — this specific demo entry point
  // has no live session to hand the real screen. See
  // guardian_more_test.dart's own "opens the REAL AvailabilityScreen once a
  // live session is threaded in" test for proof the real screen itself
  // opens once that wiring exists.
  testWidgets('GuardianHome Availability tile shows honest not-connected feedback',
      (WidgetTester tester) async {
    await tester.pumpWidget(const OliveDemo());
    await tester.tap(find.text("The grown-up's device"));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Availability'));
    await tester.pump();
    expect(find.textContaining('not connected'), findsOneWidget);
  });

  testWidgets('GuardianHome Exchange tile reaches the real screen',
      (WidgetTester tester) async {
    await tester.pumpWidget(const OliveDemo());
    await tester.tap(find.text("The grown-up's device"));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Exchange'));
    await tester.pumpAndSettle();
    expect(find.byType(ExchangeScreen), findsOneWidget);
  });

  testWidgets('GuardianHome Expenses tile reaches the real screen',
      (WidgetTester tester) async {
    await tester.pumpWidget(const OliveDemo());
    await tester.tap(find.text("The grown-up's device"));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Expenses'));
    await tester.pumpAndSettle();
    expect(find.byType(ExpensesScreen), findsOneWidget);
  });

  testWidgets("ChildHome's Homework tile reaches the real screen",
      (WidgetTester tester) async {
    await tester.pumpWidget(const OliveDemo());
    await tester.tap(find.text("My child's device"));
    await tester.pumpAndSettle();
    // Standard tier, below Hero/Featured — see the 'My list' test above.
    await tester.ensureVisible(find.text('Homework'));
    await tester.tap(find.text('Homework'));
    await tester.pumpAndSettle();
    expect(find.text('Take a photo'), findsOneWidget);
  });

  testWidgets("ChildHome's Play together tile reaches the game picker",
      (WidgetTester tester) async {
    await tester.pumpWidget(const OliveDemo());
    await tester.tap(find.text("My child's device"));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Play together'));
    await tester.pumpAndSettle();
    expect(find.text('Games'), findsOneWidget);
  });

  testWidgets(
      "the game picker's consolidated extraSections reach a real "
      "games_hub.dart screen from the SAME 'Play together' tile — no "
      "separate 'More games' door",
      (WidgetTester tester) async {
    // A tall surface so games_hub.dart's MoreGamesSections have somewhere
    // real to scroll to below the age-gated grid, matching
    // game_copy_pattern_test.dart's own established pattern for the same
    // "reach it via scrolling on the real consolidated screen" case.
    await tester.binding.setSurfaceSize(const Size(900, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const OliveDemo());
    await tester.tap(find.text("My child's device"));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Play together'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Checkers'), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Checkers'));
    await tester.pumpAndSettle();
    expect(find.byType(GameCheckers), findsOneWidget);
  });

  testWidgets("the game picker's Three in a row card reaches the real GameTicTacToe screen",
      (WidgetTester tester) async {
    await tester.pumpWidget(const OliveDemo());
    await tester.tap(find.text("My child's device"));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Play together'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Three in a row'));
    await tester.pumpAndSettle();
    expect(find.byType(GameTicTacToe), findsOneWidget);
    expect(find.textContaining('not built yet'), findsNothing);
  });

  testWidgets("the game picker's Dots and boxes card reaches the real GameDotsBoxes screen",
      (WidgetTester tester) async {
    await tester.pumpWidget(const OliveDemo());
    await tester.tap(find.text("My child's device"));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Play together'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dots and boxes'));
    await tester.pumpAndSettle();
    expect(find.byType(GameDotsBoxes), findsOneWidget);
    expect(find.textContaining('not built yet'), findsNothing);
  });

  testWidgets("ChildHome's Messages tile reaches the real inbox",
      (WidgetTester tester) async {
    await tester.pumpWidget(const OliveDemo());
    await tester.tap(find.text("My child's device"));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Messages'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Dad'), findsWidgets);
  });
}
