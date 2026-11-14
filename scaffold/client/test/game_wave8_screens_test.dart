// OLIVE BRANCH — wave 8 child games, screen tests: the tic-tac-toe setup panel (levels and same-screen
// two-player), Memory pairs, War against the game, Guess the word on her own, and where they sit in the hub.
// Every screen is also held to MASTERFILE §2.1 P1-P3 (no count, score, streak or reward on a child's screen)
// and to the posture rule (344 / 390 / 600 / 800 dp, 2.0x text, no overflow).
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/game_hangman.dart';
import 'package:olive_client/game_logic.dart';
import 'package:olive_client/game_memory.dart';
import 'package:olive_client/game_solo_logic.dart';
import 'package:olive_client/game_tictactoe.dart';
import 'package:olive_client/game_war_solo.dart';
import 'package:olive_client/games_hub.dart';

Widget wrap(Widget child, {double textScale = 1.0}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
    child: child,
  ),
);

/// Nothing a child could read as a score: no digit outside a title, no 'score', 'streak', 'points', 'level up',
/// 'best', trophy or star.
void expectNoScoreLanguage(WidgetTester t) {
  final Iterable<String> texts = t.widgetList<Text>(find.byType(Text)).map((Text w) => (w.data ?? '').toLowerCase());
  for (final String x in texts) {
    for (final String bad in <String>['score', 'streak', 'points', 'best', 'winner', 'loser', 'you lost', 'trophy', 'reward']) {
      expect(x.contains(bad), isFalse, reason: '"$x" contains "$bad"');
    }
  }
  expect(find.byIcon(Icons.emoji_events), findsNothing);
  expect(find.byIcon(Icons.emoji_events_outlined), findsNothing);
  expect(find.byIcon(Icons.star), findsNothing);
}

const List<Size> postures = <Size>[Size(344, 700), Size(390, 780), Size(600, 900), Size(800, 1000)];

void main() {
  group('tic-tac-toe setup panel', () {
    testWidgets('opens on Easy / Normal / Hard and a friend, with no board yet', (t) async {
      await t.pumpWidget(wrap(const GameTicTacToe(showSetup: true)));
      expect(find.byKey(const Key('tttSetupTitle')), findsOneWidget);
      for (final String k in <String>['tttLevel_easy', 'tttLevel_normal', 'tttLevel_hard', 'tttFriend']) {
        expect(find.byKey(Key(k)), findsOneWidget, reason: k);
      }
      expect(find.byKey(const Key('tttCell_0')), findsNothing);
      expectNoScoreLanguage(t);
    });

    testWidgets('a level starts the board, and Normal answers her corner with the centre', (t) async {
      await t.pumpWidget(wrap(const GameTicTacToe(showSetup: true, botThinkDelay: Duration(milliseconds: 10), seed: 1)));
      await t.tap(find.byKey(const Key('tttLevel_normal')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('tttCell_0')), findsOneWidget);
      await t.tap(find.byKey(const Key('tttCell_0')));
      await t.pump(const Duration(milliseconds: 20));
      await t.pumpAndSettle();
      // The game's mark (a cross) sits in the middle; her ring is in the corner.
      expect(find.descendant(of: find.byKey(const Key('tttCell_4')), matching: find.byIcon(Icons.close_rounded)), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('tttCell_0')), matching: find.byIcon(Icons.circle_outlined)), findsOneWidget);
    });

    testWidgets('Hard blocks her row', (t) async {
      await t.pumpWidget(wrap(const GameTicTacToe(showSetup: true, botThinkDelay: Duration(milliseconds: 10), seed: 2)));
      await t.tap(find.byKey(const Key('tttLevel_hard')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('tttCell_0')));
      await t.pumpAndSettle(); // game takes the centre
      await t.tap(find.byKey(const Key('tttCell_1')));
      await t.pumpAndSettle(); // she threatens 2; the game must block it
      expect(find.descendant(of: find.byKey(const Key('tttCell_2')), matching: find.byIcon(Icons.close_rounded)), findsOneWidget);
    });

    testWidgets('a friend on the same screen: turns alternate, no thinking pause, no handicap or voice note', (t) async {
      await t.pumpWidget(wrap(const GameTicTacToe(showSetup: true, childName: 'Ivy')));
      await t.tap(find.byKey(const Key('tttFriend')));
      await t.pumpAndSettle();
      expect(find.text("Ivy's move"), findsOneWidget);
      await t.tap(find.byKey(const Key('tttCell_0')));
      await t.pump();
      expect(find.text("Your friend's move"), findsOneWidget);
      await t.tap(find.byKey(const Key('tttCell_4')));
      await t.pump();
      expect(find.text("Ivy's move"), findsOneWidget);
      expect(find.textContaining('thinking'), findsNothing);
      expect(find.byTooltip('Make it fair'), findsNothing);
      expect(find.byTooltip('Add a voice note'), findsNothing);
      // Finish: Ivy 0,1,2.
      await t.tap(find.byKey(const Key('tttCell_1')));
      await t.pump();
      await t.tap(find.byKey(const Key('tttCell_5')));
      await t.pump();
      await t.tap(find.byKey(const Key('tttCell_2')));
      await t.pump();
      expect(find.text('Good game.'), findsWidgets);
      expect(find.byKey(const Key('tttPlayAgain')), findsOneWidget);
      expectNoScoreLanguage(t);
    });

    testWidgets('without showSetup the board opens straight away (callers keep the old behaviour)', (t) async {
      await t.pumpWidget(wrap(const GameTicTacToe()));
      expect(find.byKey(const Key('tttCell_0')), findsOneWidget);
      expect(find.byKey(const Key('tttSetupTitle')), findsNothing);
    });

    for (final Size sz in postures) {
      testWidgets('setup and friend board fit at ${sz.width.toInt()} dp, 2.0x text', (t) async {
        await t.binding.setSurfaceSize(sz);
        addTearDown(() => t.binding.setSurfaceSize(null));
        await t.pumpWidget(wrap(const GameTicTacToe(showSetup: true), textScale: 2.0));
        expect(t.takeException(), isNull);
        await t.scrollUntilVisible(find.byKey(const Key('tttFriend')), 100);
        await t.tap(find.byKey(const Key('tttFriend')));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      });
    }
  });

  group('Memory pairs', () {
    int cards(WidgetTester t) => t.widgetList(find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('memoryCard_'))).length;

    testWidgets('three pairs for the youngest, eight for the oldest', (t) async {
      await t.pumpWidget(wrap(const GameMemoryPairs(childAge: 3, seed: 1)));
      expect(cards(t), 6);
      await t.pumpWidget(wrap(const GameMemoryPairs(key: ValueKey<int>(15), childAge: 15, seed: 1)));
      await t.pumpAndSettle();
      expect(cards(t), 16);
    });

    testWidgets('a miss turns back over after the pause; a match stays; finishing shows the calm line', (t) async {
      // The screen shuffles with Random(seed) first, so the test reproduces its layout exactly.
      final MemoryState ref = newMemory(3, Random(4));
      final List<int> cardsAt = ref.cards;
      final int partnerOf0 = List<int>.generate(6, (int i) => i).firstWhere((int i) => i != 0 && cardsAt[i] == cardsAt[0]);
      final int other = List<int>.generate(6, (int i) => i).firstWhere((int i) => cardsAt[i] != cardsAt[0]);
      await t.pumpWidget(wrap(const GameMemoryPairs(childAge: 3, seed: 4)));
      Finder down() => find.bySemanticsLabel('Card, face down');
      expect(down(), findsNWidgets(6));
      // A miss: both show, then after 900 ms both are face down again.
      await t.tap(find.byKey(Key('memoryCard_0')));
      await t.pump();
      await t.tap(find.byKey(Key('memoryCard_$other')));
      await t.pump();
      expect(down(), findsNWidgets(4));
      await t.pump(const Duration(milliseconds: 850));
      expect(down(), findsNWidgets(4));
      await t.pump(const Duration(milliseconds: 100));
      expect(down(), findsNWidgets(6));
      // A match: both stay up.
      await t.tap(find.byKey(Key('memoryCard_0')));
      await t.pump();
      await t.tap(find.byKey(Key('memoryCard_$partnerOf0')));
      await t.pump(const Duration(milliseconds: 1000));
      expect(down(), findsNWidgets(4));
      expect(find.bySemanticsLabel(RegExp('together')), findsNWidgets(2));
      // Finish the rest.
      final List<int> rest = <int>[for (int i = 0; i < 6; i++) if (i != 0 && i != partnerOf0) i];
      final int first = rest.first;
      final int second = rest.skip(1).firstWhere((int i) => cardsAt[i] == cardsAt[first]);
      final int third = rest.firstWhere((int i) => i != first && i != second);
      final int fourth = rest.firstWhere((int i) => i != first && i != second && i != third);
      for (final List<int> pair in <List<int>>[<int>[first, second], <int>[third, fourth]]) {
        await t.tap(find.byKey(Key('memoryCard_${pair[0]}')));
        await t.pump();
        await t.tap(find.byKey(Key('memoryCard_${pair[1]}')));
        await t.pump(const Duration(milliseconds: 1000));
      }
      expect(find.byKey(const Key('memoryDone')), findsOneWidget);
      expect(find.text('All the pairs are together.'), findsOneWidget);
      expectNoScoreLanguage(t);
      await t.tap(find.byKey(const Key('memoryAgain')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('memoryDone')), findsNothing);
    });

    testWidgets('no timer, move counter or number is ever on the screen', (t) async {
      await t.pumpWidget(wrap(const GameMemoryPairs(childAge: 9, seed: 2)));
      await t.tap(find.byKey(const Key('memoryCard_0')));
      await t.pump();
      await t.tap(find.byKey(const Key('memoryCard_1')));
      await t.pump();
      for (final Text w in t.widgetList<Text>(find.byType(Text))) {
        expect(RegExp(r'\d').hasMatch(w.data ?? ''), isFalse, reason: w.data);
      }
      await t.pump(const Duration(seconds: 2));
      expectNoScoreLanguage(t);
    });

    testWidgets('reduced motion leaves a miss face up longer (1200 ms, not 900 ms)', (t) async {
      final List<int> c = newMemory(3, Random(1)).cards;
      final int other = List<int>.generate(6, (int i) => i).firstWhere((int i) => c[i] != c[0]);
      await t.pumpWidget(MaterialApp(home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: const GameMemoryPairs(childAge: 3, seed: 1))));
      await t.tap(find.byKey(const Key('memoryCard_0')));
      await t.pump();
      await t.tap(find.byKey(Key('memoryCard_$other')));
      await t.pump(const Duration(milliseconds: 1000));
      expect(find.bySemanticsLabel('Card, face down'), findsNWidgets(4));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.bySemanticsLabel('Card, face down'), findsNWidgets(6));
    });

    for (final Size sz in postures) {
      testWidgets('fits at ${sz.width.toInt()} dp, 2.0x text, ages 3 and 15', (t) async {
        await t.binding.setSurfaceSize(sz);
        addTearDown(() => t.binding.setSurfaceSize(null));
        for (final int age in <int>[3, 15]) {
          await t.pumpWidget(wrap(GameMemoryPairs(childAge: age, seed: 1), textScale: 2.0));
          await t.pumpAndSettle();
          expect(t.takeException(), isNull, reason: 'age $age');
        }
      });
    }
  });

  group('War against the game', () {
    testWidgets('she flips, the game flips back, then the cards move on; no tally anywhere', (t) async {
      await t.pumpWidget(wrap(const GameWarVsGame(peerName: 'the game', seed: 3, revealMs: 50)));
      expect(find.byKey(const Key('warSoloLine')), findsOneWidget);
      expect(find.text('You against the game'), findsOneWidget);
      await t.tap(find.bySemanticsLabel('Turn over your top card'));
      await t.pump(const Duration(milliseconds: 10));
      expect(find.bySemanticsLabel('Turn over your top card'), findsNothing); // both cards are out
      await t.pump(const Duration(milliseconds: 600));
      await t.pumpAndSettle();
      expect(find.bySemanticsLabel('Turn over your top card'), findsOneWidget);
      expectNoScoreLanguage(t);
    });

    testWidgets('a whole game ends with "Good game." and one Play again', (t) async {
      await t.pumpWidget(wrap(const GameWarVsGame(peerName: 'the game', seed: 11, revealMs: 1)));
      int guard = 0;
      while (find.byKey(const Key('warSoloAgain')).evaluate().isEmpty && guard++ < 400) {
        final Finder flip = find.bySemanticsLabel('Turn over your top card');
        if (flip.evaluate().isNotEmpty) await t.tap(flip, warnIfMissed: false);
        await t.pump(const Duration(milliseconds: 20));
        await t.pump(const Duration(milliseconds: 600));
      }
      expect(find.byKey(const Key('warSoloAgain')), findsOneWidget);
      expect(find.textContaining('Good game'), findsOneWidget);
      await t.tap(find.byKey(const Key('warSoloAgain')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('warSoloAgain')), findsNothing);
    });

    for (final Size sz in postures) {
      testWidgets('fits at ${sz.width.toInt()} dp, 2.0x text', (t) async {
        await t.binding.setSurfaceSize(sz);
        addTearDown(() => t.binding.setSurfaceSize(null));
        await t.pumpWidget(wrap(const GameWarVsGame(peerName: 'the game', seed: 1), textScale: 2.0));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      });
    }
  });

  group('Guess the word on her own', () {
    testWidgets('a word from her band with its hint, a flower not a count, and Another word at the end', (t) async {
      final WordEntry entry = pickWord(6, Random(1));
      await t.pumpWidget(wrap(const GuessTheWordSolo(childAge: 6, seed: 1)));
      expect(find.text('Hint: ${entry.hint}'), findsOneWidget);
      expect(find.byKey(const Key('hangmanFlower')), findsOneWidget);
      expect(find.byIcon(Icons.favorite), findsNothing); // no row of hearts to count
      expect(wordsYoung.map((WordEntry w) => w.word), contains(entry.word));
      expect(t.widget<Text>(find.byKey(const Key('hangmanMask'))).data, List<String>.filled(entry.word.length, '_').join(' '));
      for (final String ch in entry.word.split('').toSet()) {
        await t.tap(find.byKey(Key('hangmanKey_$ch')));
        await t.pump();
      }
      expect(find.byKey(const Key('hangmanWon')), findsOneWidget);
      expect(find.text('You found it!'), findsOneWidget);
      expect(find.byKey(const Key('hangmanAnother')), findsOneWidget);
      await t.tap(find.byKey(const Key('hangmanAnother')));
      await t.pump();
      expect(find.byKey(const Key('hangmanAnother')), findsNothing);
      expect(find.byKey(const Key('hangmanWon')), findsNothing);
      expectNoScoreLanguage(t);
    });

    testWidgets('eight misses reveal the word warmly and still offer another', (t) async {
      final WordEntry entry = pickWord(6, Random(1));
      await t.pumpWidget(wrap(const GuessTheWordSolo(childAge: 6, seed: 1)));
      final List<String> misses = 'ZQXJKVWYBPFUHG'.split('').where((String ch) => !entry.word.contains(ch)).take(8).toList();
      for (final String ch in misses) {
        await t.tap(find.byKey(Key('hangmanKey_$ch')));
        await t.pump();
      }
      expect(find.byKey(const Key('hangmanLost')), findsOneWidget);
      expect(find.textContaining('So close'), findsOneWidget);
      expect(find.byKey(const Key('hangmanAnother')), findsOneWidget);
      expectNoScoreLanguage(t);
    });

    testWidgets('a grown-up typed word still shows the hearts and no Another word button', (t) async {
      await t.pumpWidget(wrap(HangmanScreen(game: newHangman('NANA', hint: 'a name'))));
      expect(find.byIcon(Icons.favorite), findsWidgets);
      expect(find.byKey(const Key('hangmanFlower')), findsNothing);
    });

    for (final Size sz in postures) {
      testWidgets('fits at ${sz.width.toInt()} dp, 2.0x text', (t) async {
        await t.binding.setSurfaceSize(sz);
        addTearDown(() => t.binding.setSurfaceSize(null));
        await t.pumpWidget(wrap(const GuessTheWordSolo(childAge: 14, seed: 1), textScale: 2.0));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
      });
    }
  });

  group('the child hub: ages and doors', () {
    Future<void> hub(WidgetTester t, int age, {bool guardian = false}) async {
      await t.binding.setSurfaceSize(const Size(900, 3000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(GamesHubScreen(childAge: age, guardianSide: guardian, parentName: neutralGrownUp)));
    }

    testWidgets('age 3: only Memory pairs of the three (early ages stay, nothing more is added)', (t) async {
      await hub(t, 3);
      expect(find.text('Memory pairs'), findsOneWidget);
      expect(find.text('War against the game'), findsNothing);
      expect(find.text('Guess the word'), findsNothing);
    });

    testWidgets('age 5: Memory pairs and War; the reading game waits', (t) async {
      await hub(t, 5);
      expect(find.text('Memory pairs'), findsOneWidget);
      expect(find.text('War against the game'), findsOneWidget);
      expect(find.text('Guess the word'), findsNothing);
    });

    testWidgets('age 7: all three', (t) async {
      await hub(t, 7);
      for (final String x in <String>['Memory pairs', 'War against the game', 'Guess the word']) {
        expect(find.text(x), findsOneWidget, reason: x);
      }
    });

    testWidgets("a grown-up's hub never offers her own solo games", (t) async {
      await hub(t, 9, guardian: true);
      expect(find.text('Memory pairs'), findsNothing);
      expect(find.text('War against the game'), findsNothing);
    });

    testWidgets('each tile opens its real screen', (t) async {
      await hub(t, 8);
      await t.tap(find.text('Memory pairs'));
      await t.pumpAndSettle();
      expect(find.byType(GameMemoryPairs), findsOneWidget);
      expect(t.widget<GameMemoryPairs>(find.byType(GameMemoryPairs)).childAge, 8);
      await t.pageBack();
      await t.pumpAndSettle();
      await t.tap(find.text('War against the game'));
      await t.pumpAndSettle();
      expect(find.byType(GameWarVsGame), findsOneWidget);
      await t.pageBack();
      await t.pumpAndSettle();
      await t.tap(find.text('Guess the word'));
      await t.pumpAndSettle();
      expect(find.byType(GuessTheWordSolo), findsOneWidget);
    });

    test('the solo ages are the three above and sit apart from the pinned hub eight', () {
      expect(soloGameMinAge, <String, int>{'memoryPairs': 3, 'warSolo': 5, 'wordGame': 6});
      expect(hubGameMinAge.length, 8);
    });
  });
}
