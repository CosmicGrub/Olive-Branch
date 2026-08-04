// OLIVE BRANCH — doodle_desk.dart tests. MASTERFILE §9.12.4, §8.13, §8.1.
//
// "A blank canvas has no finish line" is the load-bearing sentence for this
// screen — the P2 checks below assert there is genuinely nothing in the
// widget tree that could be read as a score, timer, or completion state,
// the same style of negative-space assertion invariants_test.dart uses for
// the child home screen's settings affordance.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/doodle_desk.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

void main() {
  testWidgets('renders the doodle desk by name', (t) async {
    await t.pumpWidget(wrap(const DoodleDesk()));
    expect(find.text('Doodle desk'), findsOneWidget);
  });

  group('P2 — no score, timer, streak, or completion state anywhere', () {
    testWidgets('draw mode shows none of the forbidden vocabulary', (t) async {
      await t.pumpWidget(wrap(const DoodleDesk()));
      for (final String word in <String>['score', 'streak', 'timer', 'finished', 'complete', 'level up']) {
        expect(find.textContaining(RegExp(word, caseSensitive: false)), findsNothing, reason: word);
      }
    });

    testWidgets('stamp mode shows none of the forbidden vocabulary either', (t) async {
      await t.pumpWidget(wrap(const DoodleDesk()));
      await t.tap(find.text('Stamps'));
      await t.pumpAndSettle();
      for (final String word in <String>['score', 'streak', 'timer', 'finished', 'complete', 'level up']) {
        expect(find.textContaining(RegExp(word, caseSensitive: false)), findsNothing, reason: word);
      }
    });

    testWidgets('no settings affordance exists', (t) async {
      await t.pumpWidget(wrap(const DoodleDesk()));
      expect(find.byIcon(Icons.settings), findsNothing);
      expect(find.byIcon(Icons.settings_outlined), findsNothing);
    });

    testWidgets('no financial or purchase surface exists (P4/P6)', (t) async {
      await t.pumpWidget(wrap(const DoodleDesk()));
      expect(find.textContaining('\$'), findsNothing);
      expect(find.textContaining(RegExp('price|buy|purchase', caseSensitive: false)), findsNothing);
    });
  });

  group('six stamps, exactly', () {
    testWidgets('switching to Stamps reveals all six, and only six', (t) async {
      await t.pumpWidget(wrap(const DoodleDesk()));
      await t.tap(find.text('Stamps'));
      await t.pumpAndSettle();
      for (final String label in <String>['Heart', 'Star', 'Smiley', 'Rainbow', 'Sun', 'Moon']) {
        expect(find.byTooltip(label), findsOneWidget, reason: label);
      }
      expect(kStamps.length, 6);
    });
  });

  group('free strokes + unlimited undo', () {
    testWidgets('a drawn stroke does not throw, and the board is still there after', (t) async {
      await t.pumpWidget(wrap(const DoodleDesk()));
      await t.drag(find.byKey(const Key('doodleBoard')), const Offset(60, 40));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('doodleBoard')), findsOneWidget);
    });

    testWidgets('placing and undoing several stamps is genuinely unlimited', (t) async {
      await t.pumpWidget(wrap(const DoodleDesk()));
      await t.tap(find.text('Stamps'));
      await t.pumpAndSettle();

      // The tray itself always shows one heart icon (the chip); placing
      // stamps on the board adds more heart icons alongside it.
      expect(find.byIcon(Icons.favorite), findsOneWidget);

      final Finder board = find.byKey(const Key('doodleBoard'));
      for (int i = 0; i < 4; i++) {
        await t.tapAt(t.getCenter(board) + Offset(i * 12.0, i * 8.0));
        await t.pump(const Duration(milliseconds: 450)); // let the pop-in settle
      }
      expect(find.byIcon(Icons.favorite), findsNWidgets(5), reason: '1 tray chip + 4 placed stamps');

      for (int i = 0; i < 4; i++) {
        await t.tap(find.text('Undo'));
        await t.pumpAndSettle();
      }
      expect(find.byIcon(Icons.favorite), findsOneWidget, reason: 'back to just the tray chip');

      // One more undo past the bottom of history must not throw or show an
      // error — silence is the correct answer.
      await t.tap(find.text('Undo'));
      await t.pumpAndSettle();
      expect(find.byIcon(Icons.favorite), findsOneWidget);
    });
  });

  testWidgets('undo/redo touch targets are at least 48dp', (t) async {
    await t.pumpWidget(wrap(const DoodleDesk()));
    final Size undo = t.getSize(find.widgetWithText(OutlinedButton, 'Undo'));
    final Size redo = t.getSize(find.widgetWithText(OutlinedButton, 'Redo'));
    expect(undo.height, greaterThanOrEqualTo(48));
    expect(redo.height, greaterThanOrEqualTo(48));
  });
}
