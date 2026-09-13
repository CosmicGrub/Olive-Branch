// OLIVE BRANCH — birthday_month.dart / calendar_logic.dart tests. §8.7.2, §8.7.3.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/birthday_month.dart';
import 'package:olive_client/calendar_logic.dart';

void main() {
  // Twelve month tiles plus the continue button run taller than the default
  // 800x600 test surface — a tall surface avoids simulating a scroll gesture
  // before every tap, the same approach emergency_card_test.dart already uses.
  Future<void> pump(WidgetTester tester, {String? birthDate, int? age,
      required ValueChanged<int> onMonthPicked}) async {
    await tester.binding.setSurfaceSize(const Size(800, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: BirthdayMonthScreen(birthDate: birthDate, age: age, onMonthPicked: onMonthPicked)));
  }

  group('hintMonth / shouldHint — pure logic', () {
    test('hintMonth reads the month straight off the guardian birth date', () {
      expect(hintMonth('2019-03-14'), 3);
      expect(hintMonth(null), isNull);
    });

    test('the hint withdraws from age nine — scaffolding that fades (§21.5)', () {
      expect(shouldHint('2019-03-14', 8), isTrue);
      expect(shouldHint('2019-03-14', 9), isFalse);
      expect(shouldHint('2019-03-14', null), isTrue, reason: 'unknown age still hints');
      expect(shouldHint(null, 5), isFalse, reason: 'no birth date, nothing to hint');
    });
  });

  testWidgets('renders all twelve months by name, not by number', (tester) async {
    await pump(tester, onMonthPicked: (_) {});
    for (final m in months) {
      expect(find.text(m.name), findsOneWidget);
    }
    expect(find.text('03'), findsNothing);
  });

  testWidgets('continue is disabled until a month is tapped', (tester) async {
    int? got;
    await pump(tester, onMonthPicked: (m) => got = m);
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
    await tester.tap(find.text('March'));
    await tester.pump();
    final afterTap = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(afterTap.onPressed, isNotNull);
    await tester.tap(find.text('Next'));
    await tester.pump();
    expect(got, 3);
  });

  testWidgets('a young child with a birth date on file sees March highlighted', (tester) async {
    await pump(tester, birthDate: '2020-03-05', age: 6, onMonthPicked: (_) {});
    final marchTile = tester.widget<Container>(find.descendant(
      of: find.ancestor(of: find.text('March'), matching: find.byType(Material)),
      matching: find.byType(Container)).first);
    expect(marchTile.decoration, isNotNull);
  });

  testWidgets('a nine-year-old gets no hint at all, even with a birth date on file', (tester) async {
    await pump(tester, birthDate: '2017-03-05', age: 9, onMonthPicked: (_) {});
    final marchTile = tester.widget<Container>(find.descendant(
      of: find.ancestor(of: find.text('March'), matching: find.byType(Material)),
      matching: find.byType(Container)).first);
    expect(marchTile.decoration, isNull);
  });

  testWidgets('no settings affordance and every tile clears 48dp', (tester) async {
    await pump(tester, onMonthPicked: (_) {});
    expect(find.byIcon(Icons.settings), findsNothing);
    final size = tester.getSize(find.ancestor(
      of: find.text('January'), matching: find.byType(Material)).first);
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));
  });

  group('responsive — required audit viewports', () {
    // Fold5 cover screen, Fold5 unfolded main screen, a standard phone, and a
    // desktop/tablet-scale width. A birth date on file exercises the hinted
    // tile's extra border decoration alongside the base grid.
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
        await tester.pumpWidget(MaterialApp(home: BirthdayMonthScreen(
          birthDate: '2020-03-05', age: 6, onMonthPicked: (_) {})));
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }
  });
}
