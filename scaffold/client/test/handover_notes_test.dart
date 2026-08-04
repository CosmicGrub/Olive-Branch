// OLIVE BRANCH — handover log tests. P8, §21.7.
//
// The one invariant that matters most here: there is no way, anywhere in
// this tree, to delete or edit an entry. Everything else is secondary to
// that assertion holding across the WHOLE rendered widget tree, not just
// the entries visible at first paint.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/handover_notes.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

void main() {
  group('handover notes — P8, §21.7', () {
    testWidgets('seeds with pre-existing entries, not empty', (t) async {
      await t.pumpWidget(wrap(const HandoverNotesScreen()));
      expect(find.byType(Card), findsNWidgets(4));
      expect(find.textContaining('Running about 15 minutes late'), findsOneWidget);
    });

    testWidgets('adding a note appends a new, correctly-attributed entry',
        (t) async {
      await t.pumpWidget(wrap(const HandoverNotesScreen()));
      final int before = find.byType(Card).evaluate().length;

      await t.enterText(find.byType(TextField),
          "Forgot her library book on the counter, it's due back Friday.");
      await t.tap(find.text('Add note'));
      await t.pump();

      expect(find.textContaining('Forgot her library book on the counter'),
          findsOneWidget);
      expect(find.byType(Card).evaluate().length, before + 1);

      // The new entry sits in a Card alongside the 'You' author label.
      final Finder newCard = find.ancestor(
        of: find.textContaining('Forgot her library book on the counter'),
        matching: find.byType(Card));
      expect(find.descendant(of: newCard, matching: find.text('You')),
          findsOneWidget);
    });

    testWidgets('the text field clears after a successful add', (t) async {
      await t.pumpWidget(wrap(const HandoverNotesScreen()));
      await t.enterText(find.byType(TextField), 'Swim lessons moved to Saturday.');
      await t.tap(find.text('Add note'));
      await t.pump();
      final TextField field = t.widget(find.byType(TextField));
      expect(field.controller!.text, isEmpty);
    });

    testWidgets('blank input does not append a new entry', (t) async {
      await t.pumpWidget(wrap(const HandoverNotesScreen()));
      final int before = find.byType(Card).evaluate().length;
      await t.enterText(find.byType(TextField), '   ');
      await t.tap(find.text('Add note'));
      await t.pump();
      expect(find.byType(Card).evaluate().length, before);
    });

    testWidgets('NO delete or edit affordance exists anywhere in the tree',
        (t) async {
      await t.pumpWidget(wrap(const HandoverNotesScreen()));
      // Add one more entry first so the check covers freshly-appended state too.
      await t.enterText(find.byType(TextField), 'Checking the invariant after an append.');
      await t.tap(find.text('Add note'));
      await t.pump();

      expect(find.byIcon(Icons.delete), findsNothing);
      expect(find.byIcon(Icons.delete_outline), findsNothing);
      expect(find.byIcon(Icons.delete_forever), findsNothing);
      expect(find.byIcon(Icons.edit), findsNothing);
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
      expect(find.byIcon(Icons.more_vert), findsNothing);
      expect(find.byIcon(Icons.more_horiz), findsNothing);
      expect(find.byIcon(Icons.close), findsNothing);
      expect(find.byType(Dismissible), findsNothing);
      expect(find.byType(IconButton), findsNothing);
      expect(find.textContaining('Delete'), findsNothing);
      expect(find.textContaining('Edit'), findsNothing);
    });

    testWidgets('append-only disclosure copy is genuinely present and visible',
        (t) async {
      await t.pumpWidget(wrap(const HandoverNotesScreen()));
      final Finder disclosure = find.textContaining("can't be edited or removed");
      expect(disclosure, findsOneWidget);
      // Actually laid out on screen, not an offstage/zero-size artifact.
      final Size size = t.getSize(disclosure);
      expect(size.width, greaterThan(0));
      expect(size.height, greaterThan(0));
    });
  });
}
