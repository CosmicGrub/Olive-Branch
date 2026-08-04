// OLIVE BRANCH — journal tests. P7, §5.12, §8.13.5.
//
// The invariant that matters most: nothing here is reachable by, or shaped
// for, a guardian reader. Everything else — compose, list, privacy copy — is
// secondary to that holding.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/journal_screen.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

void main() {
  group('journal — P7 read guard (pure port of agency.ts readJournal)', () {
    test('the owning child reading her own journal is allowed', () {
      final entries = [JournalEntry(id: 'j1', childId: 'maya', body: 'hi', createdAt: DateTime(2026))];
      final result = readJournal(entries, 'child', 'maya', 'maya');
      expect(result.isOk, isTrue);
      expect(result.entries, hasLength(1));
    });

    test('a guardian role is refused outright, regardless of id', () {
      final entries = [JournalEntry(id: 'j1', childId: 'maya', body: 'hi', createdAt: DateTime(2026))];
      final result = readJournal(entries, 'guardian', 'maya', 'maya');
      expect(result.isOk, isFalse);
      expect(result.reason, 'P7_journal_never');
    });

    test('a mismatched child id is refused even with role "child"', () {
      final entries = [JournalEntry(id: 'j1', childId: 'maya', body: 'hi', createdAt: DateTime(2026))];
      final result = readJournal(entries, 'child', 'someone-else', 'maya');
      expect(result.isOk, isFalse);
      expect(result.reason, 'P7_journal_never');
    });
  });

  group('journal screen — child-facing, §8.13.5 still surface', () {
    testWidgets('renders by her name and shows the privacy promise', (t) async {
      await t.pumpWidget(wrap(const JournalScreen(childName: 'Maya')));
      expect(find.textContaining('This is yours, Maya'), findsOneWidget);
      expect(find.textContaining('Nobody else can open it'), findsOneWidget);
    });

    testWidgets('writing and saving an entry adds it to the list and clears the field', (t) async {
      await t.pumpWidget(wrap(const JournalScreen(childName: 'Maya')));
      await t.enterText(find.byType(TextField), 'Today was a good day.');
      await t.pump(); // let the listener-driven setState enable the button first
      await t.tap(find.widgetWithText(FilledButton, 'Keep it, just for me'));
      await t.pump();

      expect(find.text('Today was a good day.'), findsOneWidget);
      final field = t.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, isEmpty);
    });

    testWidgets('blank input does not save anything, and the save button is disabled', (t) async {
      await t.pumpWidget(wrap(const JournalScreen(childName: 'Maya')));
      final button = t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Keep it, just for me'));
      expect(button.onPressed, isNull);

      await t.enterText(find.byType(TextField), '   ');
      await t.tap(find.widgetWithText(FilledButton, 'Keep it, just for me'));
      await t.pump();
      expect(find.text('Nothing written yet. Whenever you feel like it.'), findsOneWidget);
    });

    testWidgets('multiple entries all persist, most recent first', (t) async {
      await t.pumpWidget(wrap(const JournalScreen(childName: 'Maya')));
      await t.enterText(find.byType(TextField), 'First entry');
      await t.pump();
      await t.tap(find.widgetWithText(FilledButton, 'Keep it, just for me'));
      await t.pump();
      await t.enterText(find.byType(TextField), 'Second entry');
      await t.pump();
      await t.tap(find.widgetWithText(FilledButton, 'Keep it, just for me'));
      await t.pump();

      expect(find.text('First entry'), findsOneWidget);
      expect(find.text('Second entry'), findsOneWidget);
      final positionSecond = t.getTopLeft(find.text('Second entry')).dy;
      final positionFirst = t.getTopLeft(find.text('First entry')).dy;
      expect(positionSecond, lessThan(positionFirst));
    });

    testWidgets('NO settings affordance exists anywhere on this screen', (t) async {
      await t.pumpWidget(wrap(const JournalScreen(childName: 'Maya')));
      expect(find.byIcon(Icons.settings), findsNothing);
      expect(find.byIcon(Icons.settings_outlined), findsNothing);
      expect(find.textContaining('Settings'), findsNothing);
    });

    testWidgets('NO score, streak, or absence-guilt language ever appears', (t) async {
      await t.pumpWidget(wrap(const JournalScreen(childName: 'Maya')));
      expect(find.textContaining('streak'), findsNothing);
      expect(find.textContaining('score'), findsNothing);
      expect(find.textContaining("haven't"), findsNothing);
      expect(find.textContaining(RegExp(r'\d+ days')), findsNothing);
    });

    testWidgets('the save button meets the 48dp touch-target floor', (t) async {
      await t.pumpWidget(wrap(const JournalScreen(childName: 'Maya')));
      final size = t.getSize(find.widgetWithText(FilledButton, 'Keep it, just for me'));
      expect(size.height, greaterThanOrEqualTo(48.0));
    });

    testWidgets('seeded entries constructed for someone else never render', (t) async {
      // Defense in depth: even if a caller mis-wires initialEntries with a
      // foreign childId, the P7 port above must keep it off her screen.
      await t.pumpWidget(wrap(JournalScreen(
        childName: 'Maya',
        childId: 'maya',
        initialEntries: [
          JournalEntry(id: 'j1', childId: 'maya', body: 'mine', createdAt: DateTime(2026, 1, 1)),
          JournalEntry(id: 'j2', childId: 'someone-else', body: 'not mine', createdAt: DateTime(2026, 1, 1)),
        ],
      )));
      expect(find.text('mine'), findsOneWidget);
      expect(find.text('not mine'), findsNothing);
    });
  });
}
