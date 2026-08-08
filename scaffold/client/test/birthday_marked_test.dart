// OLIVE BRANCH — birthday_marked.dart / calendar_logic.dart tests. §8.7.5,
// §8.7.6, MASTERFILE P2.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/birthday_marked.dart';
import 'package:olive_client/calendar_logic.dart';

void main() {
  final fixedNow = DateTime(2026, 8, 4);
  const resolvedPicker = BirthdayPicker(
    step: PickerStep.done, month: 3, day: 14, year: 2019,
    authoritative: '2019-03-14', age: 7);

  group('markBirthday / occurrenceIn — pure logic', () {
    test('produces a permanent, non-deletable-by-guardian marker', () {
      final outcome = markBirthday('child1', resolvedPicker, 'grape', '2026-08-04T00:00:00Z');
      expect(outcome.ok, isTrue);
      expect(outcome.event!.month, 3);
      expect(outcome.event!.day, 14);
      expect(BirthdayEvent.deletableByGuardian, isFalse);
      expect(BirthdayEvent.recurrence, 'yearly');
    });

    test('29 February is observed on 28 February in a common year', () {
      const event = BirthdayEvent(childId: 'c', month: 2, day: 29,
        colourId: null, placedByChild: true, markedAt: '2020-01-01');
      expect(occurrenceIn(event, 2025), '2025-02-28'); // common year
      expect(occurrenceIn(event, 2024), '2024-02-29'); // leap year
    });

    test('an unresolved picker is refused rather than faked', () {
      final incomplete = beginPicker(null, 7);
      final outcome = markBirthday('child1', incomplete, null, '2026-08-04');
      expect(outcome.ok, isFalse);
    });
  });

  Future<void> pump(WidgetTester tester, {String? colourId}) => tester.pumpWidget(MaterialApp(
    home: BirthdayMarkedScreen(childId: 'child1', childName: 'Ivy', picker: resolvedPicker,
      colourId: colourId, onDone: () {}, now: fixedNow)));

  testWidgets('shows the marked date and "My birthday", not a raw date string', (tester) async {
    await pump(tester);
    expect(find.text('My birthday'), findsOneWidget);
    expect(find.text('14'), findsOneWidget);
    expect(find.text('March'), findsOneWidget);
    expect(find.textContaining('2019'), findsNothing, reason: 'the year is not shown here');
  });

  testWidgets('no custody or exchange vocabulary appears near her birthday (§8.7.6)', (tester) async {
    await pump(tester);
    expect(find.textContaining('custody'), findsNothing);
    expect(find.textContaining('exchange'), findsNothing);
    expect(find.textContaining('handover'), findsNothing);
  });

  testWidgets('P2 — no streak, score, badge, or countdown appears on this screen', (tester) async {
    await pump(tester);
    expect(find.textContaining('streak'), findsNothing);
    expect(find.textContaining('score'), findsNothing);
    expect(find.textContaining('badge'), findsNothing);
    expect(find.textContaining('sleeps'), findsNothing);
    expect(find.textContaining(RegExp(r'day \d+ of \d+')), findsNothing);
  });

  testWidgets('the finishing action is a plain "All done!", not a fake success claim', (tester) async {
    var done = false;
    await tester.pumpWidget(MaterialApp(home: BirthdayMarkedScreen(
      childId: 'child1', childName: 'Ivy', picker: resolvedPicker, colourId: null,
      onDone: () => done = true, now: fixedNow)));
    // The 300ms pop-in is a finite, one-shot consequence animation (§8.13.1)
    // — let it finish so the button is actually at full scale to hit-test.
    await tester.pumpAndSettle();
    await tester.tap(find.text('All done!'));
    await tester.pump();
    expect(done, isTrue);
  });

  testWidgets('an unresolved picker shows an honest fallback, never a fabricated date', (tester) async {
    final incomplete = beginPicker(null, 7);
    await tester.pumpWidget(MaterialApp(home: BirthdayMarkedScreen(
      childId: 'child1', childName: 'Ivy', picker: incomplete, colourId: null,
      onDone: () {}, now: fixedNow)));
    expect(find.text('My birthday'), findsNothing);
    expect(find.textContaining("don't have"), findsOneWidget);
  });

  testWidgets('no settings affordance exists on this screen', (tester) async {
    await pump(tester);
    expect(find.byIcon(Icons.settings), findsNothing);
  });

  group('responsive — required audit viewports', () {
    // Fold5 cover screen, Fold5 unfolded main screen, a standard phone, and a
    // desktop/tablet-scale width.
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
        await pump(tester, colourId: 'grape');
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });
}
