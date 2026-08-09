// OLIVE BRANCH — birthday_day.dart / calendar_logic.dart tests. §8.7.2, §8.7.4.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/birthday_day.dart';
import 'package:olive_client/calendar_logic.dart';

void main() {
  final fixedNow = DateTime(2026, 8, 4);

  // A full day grid (up to six rows) plus the shared scaffold's skip link can
  // run taller than the default 800x600 test surface — a tall surface avoids
  // simulating a scroll gesture before every tap, the same approach
  // emergency_card_test.dart already uses.
  Future<void> pump(WidgetTester tester, BirthdayDayScreen screen) async {
    await tester.binding.setSurfaceSize(const Size(800, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(home: screen));
  }

  group('the picker state machine — pure logic', () {
    test('with an authoritative birth date, a day tap resolves immediately', () {
      final p = pickMonth(beginPicker('2019-03-14', 7), 3);
      final r = pickDay(p, 14, fixedNow);
      expect(r.ok, isTrue);
      expect(r.picker!.step, PickerStep.done);
      expect(pickedDate(r.picker!), '2019-03-14');
    });

    test('with only an age, a day tap asks the year-check question first', () {
      final p = pickMonth(beginPicker(null, 7), 3);
      final r = pickDay(p, 14, fixedNow);
      expect(r.ok, isTrue);
      expect(r.picker!.step, PickerStep.yearCheck);
    });

    test('answering the year check derives the year and resolves', () {
      var p = pickMonth(beginPicker(null, 7), 3);
      p = pickDay(p, 14, fixedNow).picker!;
      final r = answerYearCheck(p, true, fixedNow);
      expect(r.ok, isTrue);
      expect(pickedDate(r.picker!), '2019-03-14');
    });

    test('a day out of range for the month is refused, not silently accepted', () {
      final p = pickMonth(beginPicker(null, 7), 2); // February
      final r = pickDay(p, 30, fixedNow);
      expect(r.ok, isFalse);
      expect(r.reason, PickerError.noSuchDay);
    });

    test('answering into the future is refused', () {
      // age 0 is an authoritative-only edge case (ageFrom() is unclamped,
      // unlike acceptAge()'s tapped path) — "yes, already had it" this year
      // plus a December date after today's August is a genuine contradiction.
      var p = pickMonth(beginPicker(null, 0), 12);
      p = pickDay(p, 31, fixedNow).picker!;
      final r = answerYearCheck(p, true, fixedNow);
      expect(r.ok, isFalse);
      expect(r.reason, PickerError.inTheFuture);
    });
  });

  testWidgets('with an authoritative date, tapping a day completes immediately', (tester) async {
    BirthdayPicker? got;
    await pump(tester, BirthdayDayScreen(
      month: 3, authoritative: '2019-03-14', age: 7, now: fixedNow,
      onComplete: (p) => got = p));
    await tester.tap(find.text('14'));
    await tester.pump();
    expect(got, isNotNull);
    expect(pickedDate(got!), '2019-03-14');
  });

  testWidgets('with only an age, tapping a day shows the year-check question inline', (tester) async {
    BirthdayPicker? got;
    await pump(tester, BirthdayDayScreen(
      month: 3, authoritative: null, age: 7, now: fixedNow,
      onComplete: (p) => got = p));
    await tester.tap(find.text('14'));
    await tester.pump();
    expect(got, isNull, reason: 'not resolved yet — the year is still unknown');
    expect(find.textContaining('Have you already had your birthday'), findsOneWidget);

    await tester.tap(find.text('Yes'));
    await tester.pump();
    expect(got, isNotNull);
    expect(pickedDate(got!), '2019-03-14');
  });

  testWidgets('answering "not yet" derives the prior year instead', (tester) async {
    BirthdayPicker? got;
    await pump(tester, BirthdayDayScreen(
      month: 3, authoritative: null, age: 7, now: fixedNow,
      onComplete: (p) => got = p));
    await tester.tap(find.text('14'));
    await tester.pump();
    await tester.tap(find.text('Not yet'));
    await tester.pump();
    expect(pickedDate(got!), '2018-03-14');
  });

  testWidgets('renders a full counted grid for the month, blanks are not tappable', (tester) async {
    await pump(tester, BirthdayDayScreen(
      month: 4, authoritative: '2019-04-10', age: 7, now: fixedNow, onComplete: (_) {}));
    for (final d in [1, 15, 30]) {
      expect(find.text('$d'), findsOneWidget);
    }
    expect(find.text('31'), findsNothing); // April has 30 days
  });

  testWidgets('skip is always available and never blocked by an unresolved picker', (tester) async {
    var skipped = false;
    await pump(tester, BirthdayDayScreen(
      month: 3, authoritative: null, age: 7, now: fixedNow,
      onComplete: (_) {}, onSkip: () => skipped = true));
    await tester.tap(find.text('Skip for now'));
    await tester.pump();
    expect(skipped, isTrue);
  });

  testWidgets('no error copy is ever shown, even for an out-of-range tap', (tester) async {
    await pump(tester, BirthdayDayScreen(
      month: 2, authoritative: null, age: 7, now: fixedNow, onComplete: (_) {}));
    expect(find.text('30'), findsNothing); // February never renders a 30th cell at all
    expect(find.textContaining('error'), findsNothing);
    expect(find.textContaining('wrong'), findsNothing);
  });

  testWidgets('no settings affordance exists on this screen', (tester) async {
    await pump(tester, BirthdayDayScreen(
      month: 3, authoritative: '2019-03-14', age: 7, now: fixedNow, onComplete: (_) {}));
    expect(find.byIcon(Icons.settings), findsNothing);
  });

  testWidgets('a day cell declares the app-wide 48dp tap-target floor', (tester) async {
    // §8.4 discipline: the day cell's own declared minimum now matches the
    // rest of the app (48, not 40). On a 7-column GridView.count this floor
    // can only raise a cell already at/above 48 — SliverGridRegularTileLayout
    // hands every cell a *tight* BoxConstraints, so the grid's own per-cell
    // math (not this constraint) is what actually determines rendered size.
    // See the comment on _DayCell in birthday_day.dart for the full story.
    await pump(tester, BirthdayDayScreen(
      month: 3, authoritative: '2019-03-14', age: 7, now: fixedNow, onComplete: (_) {}));
    final cell = tester.widget<Container>(find.descendant(
      of: find.ancestor(of: find.text('14'), matching: find.byType(InkWell)),
      matching: find.byType(Container)).first);
    expect(cell.constraints, const BoxConstraints(minWidth: 48, minHeight: 48));
  });

  group('responsive — required audit viewports', () {
    // Fold5 cover screen, Fold5 unfolded main screen, a standard phone, and a
    // desktop/tablet-scale width. Checked both on the seven-column day grid
    // and on the year-check question (the two distinct layouts this screen
    // renders).
    const viewports = {
      'Fold5 cover (344x882)': Size(344, 882),
      'Fold5 main (673x841)': Size(673, 841),
      'phone (390x844)': Size(390, 844),
      'tablet/desktop (1200x800)': Size(1200, 800),
    };

    for (final entry in viewports.entries) {
      testWidgets('day grid renders without overflow at ${entry.key}', (tester) async {
        await tester.binding.setSurfaceSize(entry.value);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(MaterialApp(home: BirthdayDayScreen(
          month: 3, authoritative: '2019-03-14', age: 7, now: fixedNow, onComplete: (_) {})));
        await tester.pump();
        expect(tester.takeException(), isNull);
      });

      testWidgets('year-check question renders without overflow at ${entry.key}', (tester) async {
        await tester.binding.setSurfaceSize(entry.value);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(MaterialApp(home: BirthdayDayScreen(
          month: 3, authoritative: null, age: 7, now: fixedNow, onComplete: (_) {})));
        await tester.tap(find.text('14'));
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }
  });
}
