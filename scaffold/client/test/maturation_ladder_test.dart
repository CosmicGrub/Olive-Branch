// OLIVE BRANCH — maturation ladder tests. MASTERFILE §21.
//
// Same posture as invariants_test.dart: assert the properties the TS suite
// (packages/maturation/test/maturation.test.mjs) asserts against the ported
// pure functions, PLUS what actually renders in the widget tree a child or
// a guardian sees — irreversibility has to be true on screen, not just in
// the function that never got an inverse.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/maturation_ladder.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

// Stable across rebuilds (unlike widget instances, which get recreated on
// every setState) — tapping by this fixed title text is the robust way to
// expand every rung tile in a loop.
const List<String> allRungTitles = <String>[
  'Her own list',
  'Her journal locks for good',
  'Her own calendar',
  'She sets her own free time',
  'She curates her archive',
  'She can take her own export',
  'Everything — guardianship closes',
];

Future<void> expandEveryTile(WidgetTester tester) async {
  for (final String title in allRungTitles) {
    await tester.tap(find.text(title));
    await tester.pump();
  }
}

void main() {
  group('ported pure logic — §21.1, §21.9', () {
    test('canGuardianRevoke always returns false', () {
      expect(canGuardianRevoke(), isFalse);
    });

    test('recordGrants is append-only and reflects exactly the rungs '
        'already reached by age', () {
      final DateTime now = DateTime(2026, 1, 1);
      final RecordGrantsResult at9 =
          recordGrants(const <MaturationGrant>[], 'c1', 9, now);
      expect(at9.grants, isEmpty);

      final RecordGrantsResult at12 =
          recordGrants(const <MaturationGrant>[], 'c1', 12, now);
      expect(holds(at12.grants, Grant.ownList), isTrue);
      expect(holds(at12.grants, Grant.journalAbsolute), isFalse);

      final RecordGrantsResult at15 =
          recordGrants(const <MaturationGrant>[], 'c1', 15, now);
      expect(holds(at15.grants, Grant.ownList), isTrue);
      expect(holds(at15.grants, Grant.journalAbsolute), isTrue);
      expect(holds(at15.grants, Grant.ownCalendar), isTrue);
      expect(holds(at15.grants, Grant.publishAvailability), isTrue);
      expect(holds(at15.grants, Grant.curateArchive), isFalse);
      expect(holds(at15.grants, Grant.ownExport), isFalse);
      expect(holds(at15.grants, Grant.everything), isFalse);
    });

    test('recordGrants never removes an existing grant, only adds', () {
      final DateTime now = DateTime(2026, 1, 1);
      final List<MaturationGrant> existing = <MaturationGrant>[
        MaturationGrant(childId: 'c1', grant: Grant.ownList, age: 10,
          reachedAt: now, rungAge: 10),
      ];
      // Re-run at a LOWER age than before (simulating a re-sync with stale
      // input) — the already-held grant must still be present, and nothing
      // new should appear.
      final RecordGrantsResult result = recordGrants(existing, 'c1', 5, now);
      expect(holds(result.grants, Grant.ownList), isTrue);
      expect(result.newly, isEmpty);
    });

    test('adjustRung refuses moving a rung earlier', () {
      final AdjustResult result = adjustRung(kLadder, Grant.ownCalendar, 13, <String>['a', 'b']);
      expect(result.ok, isFalse);
      expect(result.reason, AdjustError.earlierNotPermitted);
    });

    test('adjustRung refuses a single consenting guardian', () {
      final AdjustResult result = adjustRung(kLadder, Grant.ownCalendar, 15, <String>['a']);
      expect(result.ok, isFalse);
      expect(result.reason, AdjustError.needsBothGuardians);
    });

    test('adjustRung allows moving later once both guardians consent', () {
      final AdjustResult result =
          adjustRung(kLadder, Grant.ownCalendar, 16, <String>['a', 'b']);
      expect(result.ok, isTrue);
      final Rung moved = result.ladder!.firstWhere((Rung r) => r.grant == Grant.ownCalendar);
      expect(moved.age, 16);
      // Every other rung is untouched.
      final Rung untouched = result.ladder!.firstWhere((Rung r) => r.grant == Grant.ownList);
      expect(untouched.age, 10);
    });

    test('adjustRung refuses an unknown grant', () {
      final AdjustResult result = adjustRung(const <Rung>[], Grant.ownCalendar, 20, <String>['a', 'b']);
      expect(result.ok, isFalse);
      expect(result.reason, AdjustError.unknownRung);
    });

    test('guardianAnnouncement fires only for a notifying grant', () {
      final DateTime now = DateTime(2026, 1, 1);
      final MaturationGrant quiet =
          MaturationGrant(childId: 'c1', grant: Grant.ownList, age: 10, reachedAt: now, rungAge: 10);
      expect(guardianAnnouncement(<MaturationGrant>[quiet]), isNull);

      final MaturationGrant loud = MaturationGrant(
        childId: 'c1', grant: Grant.publishAvailability, age: 15, reachedAt: now, rungAge: 15);
      final String? note = guardianAnnouncement(<MaturationGrant>[loud]);
      expect(note, isNotNull);
      expect(note, contains('{name}'));
    });

    test('the ladder sequence itself is fixed — seven rungs, ages ascending', () {
      expect(kLadder.length, 7);
      for (int i = 1; i < kLadder.length; i++) {
        expect(kLadder[i].age, greaterThan(kLadder[i - 1].age));
      }
      expect(kLadder.map((Rung r) => r.age), <int>[10, 13, 14, 15, 16, 17, 18]);
    });
  });

  group('child viewer — P2, no settings, no undo affordance', () {
    // Tall enough that all seven rung tiles, fully expanded, are built by
    // the ListView's sliver rather than left outside its cache extent —
    // otherwise "not found" would be indistinguishable from "not rendered".
    Future<void> pump(WidgetTester tester, {int age = 12}) async {
      await tester.binding.setSurfaceSize(const Size(400, 4000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(wrap(MaturationLadderScreen(
        childName: 'Ivy', childAgeYears: age, viewer: LadderViewer.child,
        now: DateTime(2026, 1, 1))));
    }

    testWidgets('renders the child by her own name, not an id', (tester) async {
      await pump(tester);
      expect(find.textContaining('Ivy'), findsWidgets);
    });

    testWidgets('no settings affordance exists anywhere', (tester) async {
      await pump(tester);
      expect(find.byIcon(Icons.settings), findsNothing);
      expect(find.byIcon(Icons.settings_outlined), findsNothing);
      expect(find.textContaining('Settings'), findsNothing);
    });

    testWidgets('P2 — no streak, score, or badge language appears', (tester) async {
      await pump(tester);
      for (final String word in <String>['streak', 'score', 'badge', 'level up', 'points']) {
        expect(find.textContaining(word), findsNothing, reason: 'found forbidden word "$word"');
      }
    });

    testWidgets('the child never sees the "move this later" control at all', (tester) async {
      await pump(tester);
      // Expand every tile; even so, no move-later control should appear —
      // it is never wired up for the child viewer regardless of state.
      await expandEveryTile(tester);
      expect(find.text('Move this later'), findsNothing);
      expect(find.byIcon(Icons.update), findsNothing);
      expect(find.textContaining('Why is there no undo'), findsNothing);
    });

    testWidgets('no undo/delete/edit/reorder affordance exists anywhere', (tester) async {
      await pump(tester);
      expect(find.byType(Switch), findsNothing);
      expect(find.byType(Dismissible), findsNothing);
      expect(find.byType(ReorderableListView), findsNothing);
      expect(find.byIcon(Icons.undo), findsNothing);
      expect(find.byIcon(Icons.restore), findsNothing);
      expect(find.byIcon(Icons.delete), findsNothing);
      expect(find.byIcon(Icons.delete_outline), findsNothing);
    });

    testWidgets('tapping a reached rung reveals its own ceremony line', (tester) async {
      await pump(tester, age: 12); // rung at 10 (ownList) is reached
      await tester.tap(find.text('Her own list'));
      await tester.pumpAndSettle();
      expect(find.text('Your list is yours now. Nobody else can change what you put on it.'),
          findsOneWidget);
    });

    testWidgets('a future rung shows a gentle placeholder, never its ceremony early',
        (tester) async {
      await pump(tester, age: 12); // rung at 13 (journal) is NOT yet reached
      expect(find.text('Your journal was always private. Now it is private forever.'),
          findsNothing);
      await tester.tap(find.text('Her journal locks for good'));
      await tester.pumpAndSettle();
      expect(find.text("You'll see this when you get there."), findsOneWidget);
      expect(find.text('Your journal was always private. Now it is private forever.'),
          findsNothing);
    });

    testWidgets('the {name} template placeholder never leaks to the child', (tester) async {
      await pump(tester, age: 20); // every rung reached
      await expandEveryTile(tester);
      expect(find.textContaining('{name}'), findsNothing);
    });

    testWidgets('renders without overflow on the Fold5 cover-screen width', (tester) async {
      await tester.binding.setSurfaceSize(const Size(344, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(wrap(const MaturationLadderScreen(
        childName: 'Ivy', childAgeYears: 12, viewer: LadderViewer.child)));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('guardian viewer — irreversibility is structural, not just copy', () {
    Future<void> pump(WidgetTester tester, {int age = 12}) async {
      await tester.binding.setSurfaceSize(const Size(500, 4000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(wrap(MaturationLadderScreen(
        childName: 'Ivy', childAgeYears: age, viewer: LadderViewer.guardian,
        now: DateTime(2026, 1, 1))));
    }

    testWidgets('a reached rung offers no move-later control', (tester) async {
      await pump(tester, age: 12); // rung 10 reached, rungs 13-18 future
      await tester.tap(find.text('Her own list')); // reached rung
      await tester.pumpAndSettle();
      expect(find.text("Already happened. It can't be moved or undone from here."),
          findsOneWidget);
      expect(find.text('Move this later'), findsNothing);
    });

    testWidgets('a future rung DOES offer a move-later control', (tester) async {
      await pump(tester, age: 12);
      await tester.tap(find.text('Her journal locks for good')); // future rung
      await tester.pumpAndSettle();
      expect(find.text('Move this later'), findsOneWidget);
    });

    testWidgets('the note substitutes the real name, never the raw template', (tester) async {
      await pump(tester, age: 14); // ownCalendar (age 14) reached
      await tester.tap(find.text('Her own calendar'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Ivy can now add and edit her own'), findsOneWidget);
      expect(find.textContaining('{name}'), findsNothing);
    });

    testWidgets('only the two notifying rungs (15, 18) tell the guardian anything', (tester) async {
      await pump(tester, age: 20); // every rung reached
      expect(find.text('You were told, once'), findsNWidgets(2));
      expect(find.text('Hers, quietly'), findsNWidgets(5));
    });

    testWidgets('the no-undo explanation names the real function and its answer', (tester) async {
      await pump(tester);
      await tester.tap(find.text('Why is there no undo?'));
      await tester.pumpAndSettle();
      expect(find.textContaining('canGuardianRevoke() always returns'), findsOneWidget);
      expect(find.textContaining('false'), findsOneWidget);
      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();
    });

    testWidgets(
        'move-later dialog blocks a single-guardian request, then succeeds once both consent',
        (tester) async {
      await pump(tester, age: 12);
      await tester.tap(find.text('Her journal locks for good')); // future rung, age 13
      await tester.pumpAndSettle();
      await tester.tap(find.text('Move this later'));
      await tester.pumpAndSettle();

      // Bump the age by one (13 -> 14) without checking the consent box.
      await tester.tap(find.byIcon(Icons.add_circle_outline));
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('This needs both guardians to agree — not just you.'), findsOneWidget);
      // Dialog is still open — the change was refused, not silently applied.
      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.tap(find.text('The other guardian has also agreed (demo)'));
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.textContaining('Moved to age 14'), findsOneWidget);
    });

    testWidgets('the age stepper cannot be pushed below the rung\'s own age', (tester) async {
      await pump(tester, age: 12);
      await tester.tap(find.text('Her journal locks for good'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Move this later'));
      await tester.pumpAndSettle();
      final IconButton minus =
          tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.remove_circle_outline));
      expect(minus.onPressed, isNull,
          reason: 'the decrement control must already be disabled at the rung\'s own age');
    });

    testWidgets('no undo/delete/reorder affordance exists anywhere, including reached rungs',
        (tester) async {
      await pump(tester, age: 20); // every rung reached
      await expandEveryTile(tester);
      expect(find.byType(Switch), findsNothing);
      expect(find.byType(Dismissible), findsNothing);
      expect(find.byType(ReorderableListView), findsNothing);
      expect(find.byIcon(Icons.undo), findsNothing);
      expect(find.byIcon(Icons.restore), findsNothing);
      expect(find.byIcon(Icons.delete), findsNothing);
      expect(find.text('Move this later'), findsNothing);
    });

    testWidgets('the journal rung never exposes a path to its content', (tester) async {
      await pump(tester, age: 20);
      await tester.tap(find.text('Her journal locks for good'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Open journal'), findsNothing);
      expect(find.textContaining('Read her journal'), findsNothing);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('the one-time announcement can be dismissed and does not block the ladder',
        (tester) async {
      await pump(tester, age: 15); // rung 15 just reached — the notifying one
      expect(find.byIcon(Icons.favorite_outline), findsOneWidget);
      await tester.tap(find.byTooltip('Dismiss'));
      await tester.pump();
      expect(find.byIcon(Icons.favorite_outline), findsNothing);
    });

    testWidgets('renders without overflow on the Fold5 main-screen size', (tester) async {
      await tester.binding.setSurfaceSize(const Size(673, 841));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(wrap(const MaturationLadderScreen(
        childName: 'Ivy', childAgeYears: 15, viewer: LadderViewer.guardian)));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}
