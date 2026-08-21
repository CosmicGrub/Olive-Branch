// OLIVE BRANCH — game_curated_activity.dart tests. MASTERFILE §9.2, §8.11.1,
// P2.
//
// Audit-fix (v0.49.22): before this file existed, no test anywhere exercised
// `SessionHistoryPanel`'s "newest-first" ordering contract directly —
// `entries[entries.length - 1 - i]` in the widget's own `itemBuilder`. All
// four Batch B consumer tests (game_silly_sentence_test.dart,
// game_would_you_rather_test.dart, game_two_truths_test.dart,
// game_twenty_questions_test.dart) only checked the panel EXISTS after one
// round — never its content or order, since one entry can't distinguish
// "newest first" from "oldest first". This file pumps the shared widget
// directly with three known entries and asserts the RENDERED order, closing
// that gap at its source rather than relying on four indirect proofs.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/game_curated_activity.dart';

Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: SizedBox(height: 400, child: child)));

void main() {
  group('SessionHistoryPanel — newest-first ordering, proven directly', () {
    testWidgets('with entries added in first/second/third order, they render third/second/first '
        '— the newest round on top, not append order', (t) async {
      await t.pumpWidget(wrap(const SessionHistoryPanel(
        title: 'Test history',
        entries: <String>['first', 'second', 'third'],
        emptyHint: 'nothing yet',
      )));
      await t.pumpAndSettle();

      final List<Text> rendered = t
          .widgetList<Text>(find.descendant(of: find.byKey(const Key('sessionHistoryList')), matching: find.byType(Text)))
          .toList();
      expect(rendered.map((Text w) => w.data).toList(), <String>['third', 'second', 'first']);
    });

    testWidgets('a single entry renders alone, trivially "newest first"', (t) async {
      await t.pumpWidget(wrap(const SessionHistoryPanel(
        title: 'Test history',
        entries: <String>['only one'],
        emptyHint: 'nothing yet',
      )));
      await t.pumpAndSettle();
      expect(find.descendant(of: find.byKey(const Key('sessionHistoryList')), matching: find.text('only one')),
          findsOneWidget);
    });

    testWidgets('an empty list shows the empty hint, not the scrollable list', (t) async {
      await t.pumpWidget(wrap(const SessionHistoryPanel(
        title: 'Test history',
        entries: <String>[],
        emptyHint: 'nothing yet',
      )));
      await t.pumpAndSettle();
      expect(find.text('nothing yet'), findsOneWidget);
      expect(find.byKey(const Key('sessionHistoryList')), findsNothing);
    });

    testWidgets('the title renders as given', (t) async {
      await t.pumpWidget(wrap(const SessionHistoryPanel(
        title: 'A distinctive title',
        entries: <String>['x'],
        emptyHint: 'nothing yet',
      )));
      await t.pumpAndSettle();
      expect(find.text('A distinctive title'), findsOneWidget);
    });
  });
}
