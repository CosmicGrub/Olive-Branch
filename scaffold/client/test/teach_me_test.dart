// OLIVE BRANCH — "teach me something" tests. §9.9.3, §9.14.
//
// The invariant that matters most: nothing here ever grades, scores, or
// levels her teaching — asking again is the only signal the feature is
// allowed to react to, and it must stay binary and warm, never a number.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/teach_me.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

void main() {
  group('teach me — pure port of family.ts teach/askAgain/whoTeachesWhom', () {
    test('teaching with a real title succeeds', () {
      final result = teach('l1', 'demo-child', 'How to whistle', TeachMedium.demonstrate, DateTime(2026));
      expect(result.ok, isTrue);
      expect(result.lesson!.askedAgain, 0);
    });

    test('an empty title is refused', () {
      final result = teach('l1', 'demo-child', '   ', TeachMedium.draw, DateTime(2026));
      expect(result.ok, isFalse);
      expect(result.reason, 'no_title');
    });

    test('a lesson is not preserved until asked for again', () {
      final lesson = teach('l1', 'demo-child', 'A card trick', TeachMedium.record, DateTime(2026)).lesson!;
      expect(lessonBecamePreserved(lesson), isFalse);
      final asked = askAgain([lesson], 'l1');
      expect(lessonBecamePreserved(asked.first), isTrue);
    });

    test('askAgain only touches the matching lesson', () {
      final a = teach('a', 'x', 'One', TeachMedium.draw, DateTime(2026)).lesson!;
      final b = teach('b', 'x', 'Two', TeachMedium.draw, DateTime(2026)).lesson!;
      final result = askAgain([a, b], 'a');
      expect(result.firstWhere((l) => l.id == 'a').askedAgain, 1);
      expect(result.firstWhere((l) => l.id == 'b').askedAgain, 0);
    });

    test('under six, mostly the grown-up teaches', () {
      expect(whoTeachesWhom(4).childTeaches, isFalse);
    });

    test('from six, she teaches too', () {
      expect(whoTeachesWhom(6).childTeaches, isTrue);
      expect(whoTeachesWhom(9).childTeaches, isTrue);
    });

    test('auditLesson passes a clean lesson', () {
      expect(auditLesson({'title': 'A card trick', 'askedAgain': 1}).ok, isTrue);
    });

    test('auditLesson catches a grading field, even nested', () {
      expect(auditLesson({'title': 'x', 'level': 3}).ok, isFalse);
      expect(auditLesson({'a': [{'mastery': 0.8}]}).ok, isFalse);
    });
  });

  group('teach me screen — child-facing', () {
    testWidgets('at nine, she is invited to teach and offered seed ideas', (t) async {
      await t.pumpWidget(wrap(const TeachMeScreen(childName: 'Maya', childAge: 9)));
      expect(find.textContaining('Your turn to be the teacher'), findsOneWidget);
      expect(find.text('A card trick'), findsOneWidget);
      expect(find.text('Show them'), findsOneWidget);
      expect(find.text('Draw it'), findsOneWidget);
      expect(find.text('Record it'), findsOneWidget);
      expect(find.text('Do it together'), findsOneWidget);
    });

    testWidgets('at four, the compose form is not offered at all', (t) async {
      await t.pumpWidget(wrap(const TeachMeScreen(childName: 'Maya', childAge: 4)));
      expect(find.textContaining("they're the one teaching"), findsOneWidget);
      expect(find.text('Need an idea?'), findsNothing);
      expect(find.text('Nothing taught yet — pick an idea above whenever you feel like it.'), findsNothing);
    });

    testWidgets('tapping a seed idea fills the text field', (t) async {
      await t.pumpWidget(wrap(const TeachMeScreen(childName: 'Maya', childAge: 9)));
      await t.tap(find.text('A card trick'));
      await t.pump();
      final field = t.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, 'A card trick');
    });

    testWidgets('teaching a lesson adds it to the taught list and clears the field', (t) async {
      await t.pumpWidget(wrap(const TeachMeScreen(childName: 'Maya', childAge: 9, parentName: 'Dad')));
      await t.enterText(find.byType(TextField), 'How a lock works');
      await t.pump(); // let the listener-driven setState enable the button first
      // The compose card can run taller than the default test viewport —
      // scroll the button into view before tapping.
      await t.ensureVisible(find.widgetWithText(FilledButton, 'Teach Dad'));
      await t.tap(find.widgetWithText(FilledButton, 'Teach Dad'));
      await t.pump();

      expect(find.text('How a lock works'), findsOneWidget);
      final field = t.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, isEmpty);
    });

    testWidgets('the teach button is disabled until there is a title', (t) async {
      await t.pumpWidget(wrap(const TeachMeScreen(childName: 'Maya', childAge: 9, parentName: 'Dad')));
      final button = t.widget<FilledButton>(find.widgetWithText(FilledButton, 'Teach Dad'));
      expect(button.onPressed, isNull);
    });

    testWidgets('asking again shows a warm, binary note — never a number', (t) async {
      await t.pumpWidget(wrap(TeachMeScreen(childName: 'Maya', childAge: 9, parentName: 'Dad', initialLessons: [
        teach('l1', 'demo-child', 'A card trick', TeachMedium.demonstrate, DateTime(2026)).lesson!,
      ])));
      expect(find.text('Dad asked for this again'), findsOneWidget);
      await t.ensureVisible(find.text('Dad asked for this again'));
      await t.tap(find.text('Dad asked for this again'));
      await t.pumpAndSettle();

      expect(find.textContaining('kept forever now'), findsOneWidget);
      expect(find.text('Dad asked for this again'), findsNothing);
      // Binary, not numeric — no "1 time" / count anywhere on the tile.
      expect(find.textContaining('1 time'), findsNothing);
    });

    testWidgets('NO grading, scoring, or streak language ever appears', (t) async {
      await t.pumpWidget(wrap(TeachMeScreen(childName: 'Maya', childAge: 9, parentName: 'Dad', initialLessons: [
        teach('l1', 'demo-child', 'A card trick', TeachMedium.demonstrate, DateTime(2026)).lesson!,
      ])));
      for (final word in teachForbidden) {
        expect(find.textContaining(word), findsNothing, reason: 'forbidden word leaked: $word');
      }
    });

    testWidgets('NO settings affordance exists anywhere', (t) async {
      await t.pumpWidget(wrap(const TeachMeScreen(childName: 'Maya', childAge: 9)));
      expect(find.byIcon(Icons.settings), findsNothing);
      expect(find.byIcon(Icons.settings_outlined), findsNothing);
    });

    group('responsive — no overflow at any required viewport width', () {
      // childAge 9 renders the full compose form (seed chips + medium chips)
      // plus a taught lesson with "asked again" copy showing — the busiest
      // layout this screen has.
      Widget buildScreen() => wrap(TeachMeScreen(childName: 'Maya', childAge: 9, parentName: 'Dad',
        initialLessons: [
          Lesson(id: 'l1', fromUserId: 'demo-child', title: 'How to whistle with two fingers',
            medium: TeachMedium.demonstrate, taughtAt: DateTime(2026, 1, 1), askedAgain: 1),
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
  });
}
