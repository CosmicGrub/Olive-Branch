// OLIVE BRANCH — the quieting tests. P2, §21.5.
//
// The invariant that matters most: everything here is gated on AGE, never on
// how much or how little she has used the app — so there must be no
// last-opened date, no day-count, and no phrase that could read as scoring
// her absence, anywhere in this tree.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/quieting_note.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

void main() {
  group('quieting — pure port of maturation.ts QUIETING', () {
    test('at the exact fade age, a scaffold counts as faded, not showing', () {
      expect(scaffoldsFadedAt(11).map((s) => s.feature), contains('sleeps_countdown'));
      expect(scaffoldsShowingAt(11).map((s) => s.feature), isNot(contains('sleeps_countdown')));
    });

    test('one year younger, the same scaffold is still showing', () {
      expect(scaffoldsShowingAt(10).map((s) => s.feature), contains('sleeps_countdown'));
      expect(scaffoldsFadedAt(10).map((s) => s.feature), isNot(contains('sleeps_countdown')));
    });

    test('an unknown feature defaults to still showing', () {
      expect(showsScaffold('not_a_real_feature', 99), isTrue);
    });

    test('at seventeen, every scaffold has faded', () {
      expect(scaffoldsShowingAt(17), isEmpty);
      expect(scaffoldsFadedAt(17), hasLength(quieting.length));
    });
  });

  group('quieting screen — child-facing', () {
    testWidgets('a young child sees scaffolds still showing, none faded', (t) async {
      await t.pumpWidget(wrap(const QuietingScreen(childName: 'Maya', age: 8)));
      expect(find.text('Still here for now'), findsOneWidget);
      expect(find.text('Quieter now'), findsNothing);
      expect(find.text('Counting sleeps until visits'), findsOneWidget);
    });

    testWidgets('an older teen sees the faded section, not the showing one', (t) async {
      await t.pumpWidget(wrap(const QuietingScreen(childName: 'Maya', age: 17)));
      expect(find.text('Quieter now'), findsOneWidget);
      expect(find.text('Still here for now'), findsNothing);
    });

    testWidgets('permanent features are always present regardless of age', (t) async {
      await t.pumpWidget(wrap(const QuietingScreen(childName: 'Maya', age: 8)));
      expect(find.text('Your journal'), findsOneWidget);
      expect(find.text('Your calendar'), findsOneWidget);
      expect(find.text('Your calls'), findsOneWidget);
      expect(find.text('Your archive'), findsOneWidget);
    });

    testWidgets('the reassurance copy explicitly denies this is about her behaviour', (t) async {
      await t.pumpWidget(wrap(const QuietingScreen(childName: 'Maya', age: 12)));
      expect(find.textContaining("isn't about anything you did"), findsOneWidget);
    });

    testWidgets('NO absence-scoring, streak, or guilt language anywhere', (t) async {
      await t.pumpWidget(wrap(const QuietingScreen(childName: 'Maya', age: 12)));
      expect(find.textContaining("haven't"), findsNothing);
      expect(find.textContaining('streak'), findsNothing);
      expect(find.textContaining('score'), findsNothing);
      expect(find.textContaining(RegExp(r'\d+ days')), findsNothing);
      expect(find.textContaining(RegExp(r'last (opened|used|visited)')), findsNothing);
    });

    testWidgets('NO settings affordance exists anywhere', (t) async {
      await t.pumpWidget(wrap(const QuietingScreen(childName: 'Maya', age: 12)));
      expect(find.byIcon(Icons.settings), findsNothing);
      expect(find.byIcon(Icons.settings_outlined), findsNothing);
    });
  });
}
