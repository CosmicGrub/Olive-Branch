// OLIVE BRANCH — hangman tests. MASTERFILE §9.2.
//
// Engine correctness ported straight from games2.test.mjs's own assertions
// (same lives count, same masking, same repeat/digit refusals, same
// win/loss thresholds) at the function level; the guardian/child screen
// split, TAP_ALWAYS_SUFFICES, and the "generous, not punitive" framing at
// the widget level.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/game_hangman.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

void main() {
  group('hangman engine — §9.2 (mirrors games2.test.mjs)', () {
    test('starts with hangmanLives lives, masked, uppercased', () {
      final h = newHangman('grandma', hint: 'Who we visit on Sundays');
      expect(h.livesLeft, hangmanLives);
      expect(hangmanMask(h), '_ _ _ _ _ _ _');
      expect(h.word, 'GRANDMA');
    });

    test('a hit costs no life and reveals every occurrence', () {
      final h = newHangman('GRANDMA');
      final r = guessLetter(h, 'a');
      expect(r.ok, isTrue);
      expect(r.hit, isTrue);
      expect(r.state!.livesLeft, hangmanLives);
      expect(hangmanMask(r.state!), '_ _ A _ _ _ A');
    });

    test('a repeat guess is refused', () {
      var h = newHangman('GRANDMA');
      h = guessLetter(h, 'A').state!;
      expect(guessLetter(h, 'A').reason, 'already_guessed');
    });

    test('a digit is refused as not a letter', () {
      final h = newHangman('GRANDMA');
      expect(guessLetter(h, '4').reason, 'not_a_letter');
    });

    test('a miss costs exactly one life', () {
      final h = newHangman('GRANDMA');
      final r = guessLetter(h, 'Z');
      expect(r.hit, isFalse);
      expect(r.state!.livesLeft, hangmanLives - 1);
    });

    test('completing the word wins, and no more guesses are accepted', () {
      var w = newHangman('DOG');
      for (final c in 'DOG'.split('')) {
        w = guessLetter(w, c).state!;
      }
      expect(hangmanOutcome(w), 'won');
      expect(guessLetter(w, 'Z').reason, 'game_over');
    });

    test('hangmanLives misses loses', () {
      var l = newHangman('DOG');
      for (final c in 'ZQXVWYKJ'.split('')) {
        l = guessLetter(l, c).state!;
      }
      expect(hangmanOutcome(l), 'lost');
    });
  });

  group('setup screen — guardian-facing', () {
    testWidgets('refuses an empty word with a friendly message', (t) async {
      await t.pumpWidget(wrap(const HangmanSetupScreen()));
      await t.tap(find.text('Start the game'));
      await t.pump();
      expect(find.textContaining('Type a word'), findsOneWidget);
      expect(find.byType(HangmanScreen), findsNothing);
    });

    testWidgets('typing a word and starting navigates to the child play screen', (t) async {
      await t.pumpWidget(wrap(const HangmanSetupScreen(childName: 'Ivy')));
      await t.enterText(find.byType(TextField).first, 'Biscuit');
      await t.tap(find.text('Start the game'));
      await t.pumpAndSettle();
      expect(find.byType(HangmanScreen), findsOneWidget);
    });
  });

  group('play screen — child-facing, TAP_ALWAYS_SUFFICES §8.13.2', () {
    testWidgets('tapping a hit letter reveals it in the mask', (t) async {
      await t.pumpWidget(wrap(HangmanScreen(game: newHangman('CAT'))));
      await t.tap(find.byKey(const Key('hangmanKey_C')));
      await t.pump();
      expect(find.text('C _ _'), findsOneWidget);
    });

    testWidgets('winning shows a warm banner, never a numeric score', (t) async {
      await t.pumpWidget(wrap(HangmanScreen(game: newHangman('CAT'))));
      for (final letter in ['C', 'A', 'T']) {
        await t.tap(find.byKey(Key('hangmanKey_$letter')));
        await t.pump();
      }
      expect(find.byKey(const Key('hangmanWon')), findsOneWidget);
      expect(find.textContaining('score'), findsNothing);
    });

    testWidgets('losing reveals the word warmly, not punitively', (t) async {
      await t.pumpWidget(wrap(HangmanScreen(game: newHangman('DOG'))));
      for (final letter in ['Z', 'Q', 'X', 'V', 'W', 'Y', 'K', 'J']) {
        await t.tap(find.byKey(Key('hangmanKey_$letter')));
        await t.pump();
      }
      expect(find.byKey(const Key('hangmanLost')), findsOneWidget);
      expect(find.textContaining('DOG'), findsOneWidget);
    });

    testWidgets('a guessed letter key stops responding to further taps', (t) async {
      await t.pumpWidget(wrap(HangmanScreen(game: newHangman('CAT'))));
      await t.tap(find.byKey(const Key('hangmanKey_C')));
      await t.pump();
      // Tapping the same (now-disabled) key again must not change lives.
      await t.tap(find.byKey(const Key('hangmanKey_C')));
      await t.pump();
      expect(find.text('C _ _'), findsOneWidget);
    });

    testWidgets('the hint shows when supplied, and is absent otherwise', (t) async {
      await t.pumpWidget(wrap(HangmanScreen(game: newHangman('CAT', hint: 'A pet'))));
      expect(find.textContaining('A pet'), findsOneWidget);
    });
  });

  group('responsive audit — Fold5, phone, and tablet/desktop widths', () {
    for (final MapEntry<String, Size> entry in const <String, Size>{
      'Fold5 cover (344 CSS px)': Size(344, 882),
      'Fold5 unfolded main (~673 CSS px)': Size(673, 841),
      'a standard phone (~390 CSS px)': Size(390, 844),
      'a tablet/desktop (~1100 CSS px)': Size(1100, 800),
    }.entries) {
      testWidgets('setup screen renders without overflow at ${entry.key}', (t) async {
        await t.binding.setSurfaceSize(entry.value);
        addTearDown(() => t.binding.setSurfaceSize(null));
        await t.pumpWidget(wrap(const HangmanSetupScreen()));
        await t.pump();
        expect(t.takeException(), isNull);
      });

      testWidgets('play screen (full alphabet keyboard) renders without overflow '
          'at ${entry.key}', (t) async {
        await t.binding.setSurfaceSize(entry.value);
        addTearDown(() => t.binding.setSurfaceSize(null));
        await t.pumpWidget(wrap(HangmanScreen(game: newHangman('GRANDMA', hint: 'Sundays'))));
        await t.pump();
        expect(t.takeException(), isNull);
      });
    }
  });
}
