// OLIVE BRANCH — Kim's game tests. MASTERFILE §9.2, P2.
//
// There is no packages/games source for this title (see the header comment
// in lib/game_kim.dart), so unlike the other three screens in this group
// there is no ported pure-function engine to test in isolation — the
// round logic lives in the widget's State. These tests exercise it there,
// with an injected Random for determinism.
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/game_kim.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

void main() {
  group("Kim's game — §9.2, P2", () {
    testWidgets('is self-paced: the reduced table only appears after "I\'m ready"', (t) async {
      await t.pumpWidget(wrap(GameKim(random: Random(1))));
      // Studying phase shows every item from the scene, no missing one yet.
      for (final item in kimDemoScenes.first.items) {
        expect(find.byKey(Key('kimTable_${item.id}')), findsOneWidget);
      }
      expect(find.text("Which one's missing?"), findsNothing);

      await t.tap(find.byKey(const Key('kimReady')));
      await t.pump();
      expect(find.text("Which one's missing?"), findsOneWidget);
    });

    testWidgets('there is no countdown or timer anywhere on the screen', (t) async {
      await t.pumpWidget(wrap(GameKim(random: Random(1))));
      expect(find.textContaining('seconds'), findsNothing);
      expect(find.textContaining('Time'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('a wrong guess is gentle, ungraded, and allows another try', (t) async {
      await t.pumpWidget(wrap(GameKim(random: Random(1))));
      await t.tap(find.byKey(const Key('kimReady')));
      await t.pump();

      // The missing item is whatever's on the table's own children set minus
      // what remains visible in the reduced table.
      final scene = kimDemoScenes.first;
      final stillOnTable = scene.items
          .where((i) => find.byKey(Key('kimTable_${i.id}')).evaluate().isNotEmpty)
          .map((i) => i.id)
          .toSet();
      final missing = scene.items.firstWhere((i) => !stillOnTable.contains(i.id));
      final wrongChoice = scene.items.firstWhere((i) => i.id != missing.id);

      await t.tap(find.byKey(Key('kimChoice_${wrongChoice.id}')));
      await t.pump();

      expect(find.byKey(const Key('kimSolved')), findsNothing);
      expect(find.textContaining('Not quite'), findsOneWidget);
      expect(find.textContaining('lives'), findsNothing);
      expect(find.textContaining('attempts'), findsNothing);
      // Still guessable — the choice grid must still be interactive, and
      // tapping the actually-correct one now should solve it.
      await t.tap(find.byKey(Key('kimChoice_${missing.id}')));
      await t.pump();
      expect(find.byKey(const Key('kimSolved')), findsOneWidget);
    });

    testWidgets('a correct guess names the missing item without a score', (t) async {
      await t.pumpWidget(wrap(GameKim(random: Random(7))));
      await t.tap(find.byKey(const Key('kimReady')));
      await t.pump();

      // Find the correct answer by reading which item is absent from the
      // reduced table but present as a choice tile.
      final scene = kimDemoScenes.first;
      final onTable = scene.items.where((i) => find.byKey(Key('kimTable_${i.id}')).evaluate().isNotEmpty);
      final missing = scene.items.firstWhere((i) => !onTable.map((x) => x.id).contains(i.id));

      await t.tap(find.byKey(Key('kimChoice_${missing.id}')));
      await t.pump();

      expect(find.byKey(const Key('kimSolved')), findsOneWidget);
      expect(find.textContaining(missing.label.toLowerCase()), findsOneWidget);
      for (final banned in ['score', 'points', 'streak', 'level']) {
        expect(find.textContaining(banned), findsNothing);
      }
    });

    testWidgets('the honest placeholder disclosure is genuinely on screen', (t) async {
      await t.pumpWidget(wrap(GameKim(random: Random(1))));
      expect(find.textContaining('stand-in'), findsOneWidget);
    });

    testWidgets('no settings affordance exists anywhere', (t) async {
      await t.pumpWidget(wrap(GameKim(random: Random(1))));
      expect(find.byIcon(Icons.settings), findsNothing);
      expect(find.byIcon(Icons.settings_outlined), findsNothing);
    });
  });
}
