// OLIVE BRANCH — the journal list is lazy (on-device performance pass).
//
// A journal can hold thousands of entries (its namespace is capped at 4 MiB).
// It used to be a SingleChildScrollView + Column that built every entry, and
// rebuilt every one of them on each keystroke (the text box calls setState).
// It is now a CustomScrollView whose entries are a SliverList.builder: only
// the entries near the viewport exist, and a keystroke rebuilds only those.
//
// The old comment warned that sliver virtualisation drops below-the-fold
// widgets from the tree. That is the intended effect for real use; these tests
// are written for it (scrollUntilVisible, not "find everything at once").
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/journal_screen.dart';

import 'perf_support.dart';

List<JournalEntry> manyEntries(int n) => <JournalEntry>[
      for (int i = 0; i < n; i++)
        JournalEntry(
            id: 'j$i',
            childId: 'demo-child',
            body: 'Entry number $i. Some words about the day.',
            createdAt: DateTime(2026, 1, 1).add(Duration(hours: i))),
    ];

void main() {
  const int n = 300;

  Future<void> pumpJournal(WidgetTester t, {int count = n}) async {
    t.view.physicalSize = const Size(800, 1200);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(MaterialApp(
        home: JournalScreen(childName: 'Maya', initialEntries: manyEntries(count))));
    await t.pump();
  }

  testWidgets('only the entries near the viewport are built, not all $n', (WidgetTester t) async {
    await pumpJournal(t);
    // Entry cards plus the compose card. Before the change this was n + 1.
    final int built = t.widgetList(find.byType(Card)).length;
    debugPrint('MEASURED journal $n entries: Card widgets built = $built');
    expect(built, lessThan(40), reason: 'a lazy list builds a screenful, not all $n');
    expect(find.text('Entry number 0. Some words about the day.'), findsNothing,
        reason: 'the oldest entry is far below the fold and is not built');
  });

  testWidgets('typing in the box rebuilds only the visible entries', (WidgetTester t) async {
    await pumpJournal(t);
    final RebuildCounter counter = RebuildCounter('_JournalTile')..start();
    addTearDown(counter.stop);
    await t.enterText(find.byType(TextField), 'a');
    await t.pump();
    debugPrint('MEASURED journal $n entries: _JournalTile rebuilds per keystroke = ${counter.rebuilds}');
    expect(counter.rebuilds, lessThan(40));
    counter.stop();
  });

  testWidgets('scrolling reaches the oldest entry, newest first, and scrolls back', (WidgetTester t) async {
    await pumpJournal(t);
    expect(find.text('Entry number 299. Some words about the day.'), findsOneWidget,
        reason: 'newest first');
    await t.scrollUntilVisible(
        find.text('Entry number 0. Some words about the day.'), 400,
        scrollable: find.byType(Scrollable).first, maxScrolls: 500);
    expect(find.text('Entry number 0. Some words about the day.'), findsOneWidget);
    expect(find.text('Entry number 299. Some words about the day.'), findsNothing,
        reason: 'the newest entry has scrolled out and been released');
    await t.scrollUntilVisible(
        find.text('Entry number 299. Some words about the day.'), -400,
        scrollable: find.byType(Scrollable).first, maxScrolls: 500);
    expect(find.text('Entry number 299. Some words about the day.'), findsOneWidget);
  });

  testWidgets('the empty state still shows and a saved entry still appears at the top', (WidgetTester t) async {
    await pumpJournal(t, count: 0);
    expect(find.text('Nothing written yet. Whenever you feel like it.'), findsOneWidget);
    await t.enterText(find.byType(TextField), 'First page.');
    await t.pump();
    await t.ensureVisible(find.widgetWithText(FilledButton, 'Keep it, just for me'));
    await t.tap(find.widgetWithText(FilledButton, 'Keep it, just for me'));
    await t.pump();
    expect(find.text('First page.'), findsOneWidget);
    expect(find.text('Nothing written yet. Whenever you feel like it.'), findsNothing);
  });
}
