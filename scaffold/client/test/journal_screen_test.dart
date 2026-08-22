// OLIVE BRANCH — journal tests. P7, §5.12, §8.13.5.
//
// The invariant that matters most: nothing here is reachable by, or shaped
// for, a guardian reader. Everything else — compose, list, privacy copy — is
// secondary to that holding.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/form_factors.dart' as ff;
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

    testWidgets('the empty state carries a calm icon, and it clears once she writes',
        (t) async {
      await t.pumpWidget(wrap(const JournalScreen(childName: 'Maya')));
      expect(find.byIcon(Icons.edit_note_outlined), findsOneWidget);

      await t.enterText(find.byType(TextField), 'Today was a good day.');
      await t.pump();
      await t.tap(find.widgetWithText(FilledButton, 'Keep it, just for me'));
      await t.pump();
      expect(find.byIcon(Icons.edit_note_outlined), findsNothing);
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

    group('responsive — no overflow at any required viewport width', () {
      // Fold5 cover screen, Fold5 unfolded main screen, a standard phone, and
      // a short-and-wide tablet/desktop width — MASTERFILE's own mandated
      // minimums, plus the desktop-scale width now that Windows is a real
      // target. A couple of longer entries are seeded so wrapping text is
      // actually exercised, not just short demo copy.
      Widget buildScreen() => wrap(JournalScreen(childName: 'Ivy', initialEntries: [
        JournalEntry(id: 'j1', childId: 'demo-child',
          body: 'A longer entry with quite a lot of text in it, enough that it '
                'might wrap across several lines and stress the layout on a '
                'narrow screen.',
          createdAt: DateTime(2026, 1, 1)),
        JournalEntry(id: 'j2', childId: 'demo-child', body: 'A short one.',
          createdAt: DateTime(2026, 1, 2)),
      ]));

      Future<void> pumpAt(WidgetTester t, Size size) async {
        await t.binding.setSurfaceSize(size);
        addTearDown(() => t.binding.setSurfaceSize(null));
        await t.pumpWidget(buildScreen());
        await t.pump();
      }

      testWidgets('Fold5 cover screen (344 CSS px wide)', (t) async {
        await pumpAt(t, const Size(344, 900));
        expect(t.takeException(), isNull);
      });

      testWidgets('Fold5 unfolded main screen (~673x841, nearly square)', (t) async {
        await pumpAt(t, const Size(673, 841));
        expect(t.takeException(), isNull);
      });

      testWidgets('standard phone width (~390px)', (t) async {
        await pumpAt(t, const Size(390, 844));
        expect(t.takeException(), isNull);
      });

      testWidgets('tablet/desktop width (~1100px, short and wide)', (t) async {
        await pumpAt(t, const Size(1100, 800));
        expect(t.takeException(), isNull);
      });
    });

    testWidgets('privacy banner uses the house 12-radius compact-banner shape '
        'shared with expenses_screen/meds_care/morning_briefing/care_note/'
        'guardian_setup', (t) async {
      await t.pumpWidget(wrap(const JournalScreen(childName: 'Maya')));
      final container = t.widget<Container>(find.ancestor(
        of: find.byIcon(Icons.shield_outlined),
        matching: find.byType(Container),
      ).first);
      final decoration = container.decoration! as BoxDecoration;
      expect((decoration.borderRadius! as BorderRadius).topLeft, const Radius.circular(12));
      expect(container.padding, const EdgeInsets.all(12));
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

    group('responsive — comfortable reading width cap (form_factors.dart)', () {
      // §8.13.5: this is a permanently STILL surface — never a two-pane
      // split (see file header). On a wide tablet/desktop viewport the
      // single column is only ever capped to a comfortable reading width and
      // centered; the Fold5 cover and phone widths are completely untouched
      // by this cap.
      testWidgets('the cap engages only on a wide tablet/desktop viewport — '
          'never at the Fold5 cover or phone width', (t) async {
        Future<void> pumpAt(Size size) async {
          await t.binding.setSurfaceSize(size);
          await t.pumpWidget(wrap(const JournalScreen(childName: 'Maya')));
          await t.pump();
        }

        addTearDown(() => t.binding.setSurfaceSize(null));

        await pumpAt(const Size(1100, 900));
        expect(t.getSize(find.byType(SingleChildScrollView)).width, ff.comfortableReadingWidth);

        await pumpAt(const Size(344, 820)); // Fold5 cover
        expect(t.getSize(find.byType(SingleChildScrollView)).width, 344);

        await pumpAt(const Size(390, 844)); // standard phone
        expect(t.getSize(find.byType(SingleChildScrollView)).width, 390);
      });
    });
  });
}
