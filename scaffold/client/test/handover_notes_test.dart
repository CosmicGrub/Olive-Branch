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
  // Tall surface so every entry's Card is actually laid out by the
  // ListView.builder's sliver, not just whatever fits the default test
  // window — the read-aloud IconButton this pass adds to each row made
  // every Card slightly taller, which was enough to push a 5th entry (after
  // a test adds one) outside the previous default viewport's built range.
  // Same "off-screen leaves things unbuilt" fix emergency_card_test.dart's
  // own pump() helper already documents for the identical reason.
  Future<void> pumpTall(WidgetTester t, Widget child) async {
    await t.binding.setSurfaceSize(const Size(800, 1600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(child);
  }

  group('handover notes — P8, §21.7', () {
    testWidgets('seeds with pre-existing entries, not empty', (t) async {
      await pumpTall(t, wrap(const HandoverNotesScreen()));
      expect(find.byType(Card), findsNWidgets(4));
      expect(find.textContaining('Running about 15 minutes late'), findsOneWidget);
    });

    testWidgets('adding a note appends a new, correctly-attributed entry',
        (t) async {
      await pumpTall(t, wrap(const HandoverNotesScreen()));
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
      await pumpTall(t, wrap(const HandoverNotesScreen()));
      await t.enterText(find.byType(TextField), 'Swim lessons moved to Saturday.');
      await t.tap(find.text('Add note'));
      await t.pump();
      final TextField field = t.widget(find.byType(TextField));
      expect(field.controller!.text, isEmpty);
    });

    testWidgets('blank input does not append a new entry', (t) async {
      await pumpTall(t, wrap(const HandoverNotesScreen()));
      final int before = find.byType(Card).evaluate().length;
      await t.enterText(find.byType(TextField), '   ');
      await t.tap(find.text('Add note'));
      await t.pump();
      expect(find.byType(Card).evaluate().length, before);
    });

    testWidgets('NO delete or edit affordance exists anywhere in the tree',
        (t) async {
      await pumpTall(t, wrap(const HandoverNotesScreen()));
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
      expect(find.textContaining('Delete'), findsNothing);
      expect(find.textContaining('Edit'), findsNothing);
      // §8.8.5's read-aloud IconButton is real and expected here — the
      // invariant this test actually protects is "no delete/edit
      // affordance", not "no IconButton at all" (that broader check would
      // have quietly started failing the moment ANY legitimate, unrelated
      // IconButton was added anywhere on this screen). Every IconButton
      // present must be the read-aloud one and nothing else.
      final Iterable<IconButton> buttons =
          t.widgetList<IconButton>(find.byType(IconButton));
      expect(buttons, isNotEmpty, reason: 'the read-aloud buttons should be present');
      for (final IconButton b in buttons) {
        expect((b.icon as Icon).icon, Icons.volume_up_outlined);
        expect(b.tooltip, 'Read this entry aloud');
      }
    });

    testWidgets('append-only disclosure copy is genuinely present and visible',
        (t) async {
      await pumpTall(t, wrap(const HandoverNotesScreen()));
      final Finder disclosure = find.textContaining("can't be edited or removed");
      expect(disclosure, findsOneWidget);
      // Actually laid out on screen, not an offstage/zero-size artifact.
      final Size size = t.getSize(disclosure);
      expect(size.width, greaterThan(0));
      expect(size.height, greaterThan(0));
    });
  });

  group('read aloud — §8.8.5', () {
    testWidgets('one read-aloud button per entry, absent speak reports itself honestly',
        (t) async {
      await pumpTall(t, wrap(const HandoverNotesScreen()));
      expect(find.byIcon(Icons.volume_up_outlined), findsNWidgets(4));

      await t.tap(find.byKey(const Key('readAloudButton_0')));
      await t.pump();
      expect(find.textContaining('Read aloud — not built yet.'), findsOneWidget);
    });

    testWidgets('a real speak callback reads that entry only — author, when, and text',
        (t) async {
      final List<String> spoken = [];
      await pumpTall(t, wrap(HandoverNotesScreen(speak: (text) async => spoken.add(text))));

      // Index 0 is the newest-first entry — the Aug 1 peanut-free lunch note.
      await t.tap(find.byKey(const Key('readAloudButton_0')));
      await t.pump();

      expect(spoken, hasLength(1));
      expect(spoken.single, contains('You'));
      expect(spoken.single, contains('Aug 1'));
      expect(spoken.single, contains('peanut-free'));
      // Must not bleed into a different entry's content.
      expect(spoken.single, isNot(contains('Picture day')));
    });

    testWidgets('a newly-added entry gets its own working read-aloud button',
        (t) async {
      final List<String> spoken = [];
      await pumpTall(t, wrap(HandoverNotesScreen(speak: (text) async => spoken.add(text))));
      await t.enterText(find.byType(TextField), 'A brand new note to read back.');
      await t.tap(find.text('Add note'));
      await t.pump();

      // Newest-first: the just-added entry is index 0 now.
      await t.tap(find.byKey(const Key('readAloudButton_0')));
      await t.pump();
      expect(spoken.single, contains('A brand new note to read back.'));
    });
  });
}
