// OLIVE BRANCH — game_solo_logic.dart tests (wave 8). Per-game rule vectors for the child games parity:
// tic-tac-toe CPU levels, Memory pairs, the Guess-the-word banks and War against the game. The rules are the
// prototype's (mod-child.js k.g.ttt / k.g.mem / k.g.word / k.g.war).
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/game_logic.dart' show Side;
import 'package:olive_client/game_solo_logic.dart';
import 'package:olive_client/game_tictactoe.dart';
import 'package:olive_client/war_deck.dart';

TttState play(TttState s, Side side, int at) => tttPlay(s, side, at).state!;

TttState withBoard(List<Side?> b, {Side turn = Side.b, String? handicap}) =>
    TttState(board: b, turn: turn, moves: const <TttMove>[], outcome: null, handicap: handicap);

void main() {
  group('tic-tac-toe CPU levels', () {
    final Side? o = null;
    test('Easy: always a legal square, and not always the same one', () {
      final Set<int> seen = <int>{};
      for (int seed = 0; seed < 40; seed++) {
        final TttState s = play(newTicTacToe(), Side.a, 0);
        final int? pick = tttCpuPick(s, TttLevel.easy, Random(seed));
        expect(pick, isNotNull);
        expect(tttLegalMoves(s, Side.b), contains(pick));
        seen.add(pick!);
      }
      expect(seen.length, greaterThan(3));
    });

    test('Normal: takes a win when it has one', () {
      // b b _ / a a _ / a _ _ and it is the game (b) to move: the win is square 2.
      final TttState s = withBoard(<Side?>[Side.b, Side.b, o, Side.a, Side.a, o, Side.a, o, o]);
      expect(tttCpuPick(s, TttLevel.normal, Random(1)), 2);
    });

    test('Normal: blocks her line when it cannot win itself', () {
      // She has 0 and 1; the game must take 2.
      final TttState s = withBoard(<Side?>[Side.a, Side.a, o, o, Side.b, o, o, o, o]);
      expect(tttCpuPick(s, TttLevel.normal, Random(1)), 2);
    });

    test('Normal: takes the centre when nothing is forced', () {
      final TttState s = play(newTicTacToe(), Side.a, 0);
      expect(tttCpuPick(s, TttLevel.normal, Random(1)), 4);
    });

    test('Normal honours no_centre: the game never plays the middle square', () {
      final TttState s = withBoard(<Side?>[Side.a, o, o, o, o, o, o, o, o], handicap: 'no_centre');
      for (int seed = 0; seed < 20; seed++) {
        expect(tttCpuPick(s, TttLevel.normal, Random(seed)), isNot(4));
        expect(tttCpuPick(s, TttLevel.hard, Random(seed)), isNot(4));
        expect(tttCpuPick(s, TttLevel.easy, Random(seed)), isNot(4));
      }
    });

    test('Hard never loses: every possible sequence of her moves ends in a draw or a game win', () {
      // Exhaustive: she tries every legal square at every turn; Hard answers.
      int games = 0;
      void walk(TttState s) {
        if (s.outcome != null) {
          games++;
          expect(s.outcome, isNot(TttOutcome.childWin), reason: 'Hard lost: ${s.moves.map((m) => m.at).toList()}');
          return;
        }
        if (s.turn == Side.a) {
          for (final int i in tttLegalMoves(s, Side.a)) {
            walk(play(s, Side.a, i));
          }
        } else {
          walk(play(s, Side.b, tttCpuPick(s, TttLevel.hard, Random(7))!));
        }
      }

      walk(newTicTacToe());
      expect(games, greaterThan(100));
    });

    test('Hard wins an open game it can win', () {
      // She wastes her moves; the game must find the line.
      final TttState s = withBoard(<Side?>[Side.b, o, o, Side.a, Side.b, o, Side.a, o, o]);
      expect(tttCpuPick(s, TttLevel.hard, Random(1)), 8);
    });

    test('a full board has no pick', () {
      final TttState s = withBoard(<Side?>[
        Side.a, Side.b, Side.a, Side.a, Side.b, Side.b, Side.b, Side.a, Side.a]);
      expect(tttCpuPick(s, TttLevel.hard, Random(1)), isNull);
    });
  });

  group('Memory pairs', () {
    test('the number of pairs grows with age: 3 for the youngest, then 4 / 6 / 8 by band', () {
      expect(<int>[3, 4].map(memoryPairsForAge), <int>[3, 3]);
      expect(<int>[5, 6, 7].map(memoryPairsForAge), <int>[4, 4, 4]);
      expect(<int>[8, 12].map(memoryPairsForAge), <int>[6, 6]);
      expect(<int>[13, 17].map(memoryPairsForAge), <int>[8, 8]);
    });

    test('every symbol appears exactly twice', () {
      for (final int pairs in <int>[3, 4, 6, 8]) {
        final MemoryState s = newMemory(pairs, Random(pairs));
        expect(s.cards.length, pairs * 2);
        for (int sym = 0; sym < pairs; sym++) {
          expect(s.cards.where((int c) => c == sym).length, 2);
        }
      }
    });

    test('a match stays together, a miss turns back over', () {
      MemoryState s = const MemoryState(cards: <int>[0, 1, 0, 1], matched: <int>{}, faceUp: <int>[]);
      s = memoryFlip(memoryFlip(s, 0), 2);
      expect(s.needsResolve, isTrue);
      s = memoryResolve(s);
      expect(s.matched, <int>{0, 2});
      expect(s.faceUp, isEmpty);

      s = memoryFlip(memoryFlip(s, 1), 1); // the same card twice does nothing
      expect(s.faceUp, <int>[1]);
      MemoryState miss = const MemoryState(cards: <int>[0, 1, 0, 1], matched: <int>{}, faceUp: <int>[]);
      miss = memoryResolve(memoryFlip(memoryFlip(miss, 0), 1));
      expect(miss.matched, isEmpty);
      expect(miss.faceUp, isEmpty);
    });

    test('a third card is ignored while two wait; matched cards cannot be flipped; out of range is ignored', () {
      MemoryState s = const MemoryState(cards: <int>[0, 1, 0, 1], matched: <int>{}, faceUp: <int>[]);
      s = memoryFlip(memoryFlip(s, 0), 1);
      expect(memoryFlip(s, 2).faceUp, <int>[0, 1]);
      expect(memoryFlip(s, 9), same(s));
      expect(memoryFlip(s, -1), same(s));
      final MemoryState done = memoryResolve(memoryFlip(memoryFlip(
          const MemoryState(cards: <int>[0, 0], matched: <int>{}, faceUp: <int>[]), 0), 1));
      expect(done.complete, isTrue);
      expect(memoryFlip(done, 0), same(done));
    });

    test('a whole game can be finished, and resolving with fewer than two up does nothing', () {
      MemoryState s = newMemory(4, Random(3));
      expect(memoryResolve(s), same(s));
      for (int a = 0; a < s.cards.length; a++) {
        if (s.matched.contains(a)) continue;
        final int b = List<int>.generate(s.cards.length, (int i) => i)
            .firstWhere((int i) => i != a && s.cards[i] == s.cards[a]);
        s = memoryResolve(memoryFlip(memoryFlip(s, a), b));
      }
      expect(s.complete, isTrue);
    });
  });

  group('Guess the word banks', () {
    test('one bank per band, and a bank is never empty', () {
      expect(wordBankForAge(5), same(wordsYoung));
      expect(wordBankForAge(7), same(wordsYoung));
      expect(wordBankForAge(8), same(wordsMiddle));
      expect(wordBankForAge(12), same(wordsMiddle));
      expect(wordBankForAge(13), same(wordsOlder));
      for (final List<WordEntry> bank in <List<WordEntry>>[wordsYoung, wordsMiddle, wordsOlder]) {
        expect(bank.length, greaterThanOrEqualTo(6));
        for (final WordEntry w in bank) {
          expect(RegExp(r'^[A-Z]+$').hasMatch(w.word), isTrue, reason: w.word);
          expect(w.hint, isNotEmpty);
        }
      }
    });

    test('words get longer with the band', () {
      double avg(List<WordEntry> b) => b.map((WordEntry w) => w.word.length).reduce((a, c) => a + c) / b.length;
      expect(avg(wordsYoung), lessThan(avg(wordsMiddle)));
      expect(avg(wordsMiddle), lessThan(avg(wordsOlder)));
    });

    test('pickWord never repeats the previous word', () {
      final Random rng = Random(5);
      String? last;
      for (int i = 0; i < 60; i++) {
        final WordEntry w = pickWord(9, rng, not: last);
        expect(w.word, isNot(last));
        last = w.word;
      }
    });
  });

  group('War against the game', () {
    test('a fresh game: 26 cards each, nothing on the table, the same 52 cards', () {
      final WarSolo s = newWarSolo(Random(1));
      expect(s.mine.length, 26);
      expect(s.theirs.length, 26);
      expect(<PlayingCard>{...s.mine, ...s.theirs}.length, 52);
      expect(s.phase, WarSoloPhase.ready);
    });

    test('the higher card takes both cards', () {
      WarSolo s = WarSolo(
        mine: const <PlayingCard>[PlayingCard(rank: 9, suit: Suit.hearts)],
        theirs: const <PlayingCard>[PlayingCard(rank: 4, suit: Suit.clubs), PlayingCard(rank: 2, suit: Suit.clubs)],
        myTable: const <PlayingCard>[], theirTable: const <PlayingCard>[], pot: const <PlayingCard>[],
        round: 1, phase: WarSoloPhase.ready, note: null, ended: null);
      s = warSoloFlip(s);
      expect(s.phase, WarSoloPhase.revealed);
      s = warSoloResolve(s);
      expect(s.mine.length, 2);
      expect(s.theirs.length, 1);
      expect(s.note, isNotNull);
    });

    test('a tie keeps every card in the pot and the next flip settles it', () {
      WarSolo s = WarSolo(
        mine: const <PlayingCard>[
          PlayingCard(rank: 7, suit: Suit.hearts), PlayingCard(rank: 3, suit: Suit.hearts), PlayingCard(rank: 12, suit: Suit.hearts)],
        theirs: const <PlayingCard>[
          PlayingCard(rank: 7, suit: Suit.clubs), PlayingCard(rank: 3, suit: Suit.clubs), PlayingCard(rank: 2, suit: Suit.clubs)],
        myTable: const <PlayingCard>[], theirTable: const <PlayingCard>[], pot: const <PlayingCard>[],
        round: 1, phase: WarSoloPhase.ready, note: null, ended: null);
      s = warSoloResolve(warSoloFlip(s));
      expect(s.pot.length, 2);
      expect(s.phase, WarSoloPhase.ready);
      s = warSoloFlip(s);
      expect(s.myTable.length, 2); // a wager plus the one that counts
      s = warSoloResolve(s);
      expect(s.pot, isEmpty);
      expect(s.mine.length + s.theirs.length, 6);
    });

    test('52 cards are never lost or invented over many whole games, and every game ends', () {
      for (int seed = 0; seed < 25; seed++) {
        WarSolo s = newWarSolo(Random(seed));
        int guard = 0;
        while (s.ended == null && guard++ < 1000) {
          s = warSoloResolve(warSoloFlip(s));
          expect(s.mine.length + s.theirs.length + s.pot.length + s.myTable.length + s.theirTable.length, 52);
        }
        expect(s.ended, isNotNull, reason: 'seed $seed never ended');
        expect(<String>['won', 'lost', 'tie'], contains(s.ended));
        expect(s.phase, WarSoloPhase.done);
      }
    });

    test('flip does nothing mid-reveal or after the end; resolve does nothing with nothing to resolve', () {
      final WarSolo s = newWarSolo(Random(2));
      expect(warSoloResolve(s), same(s));
      final WarSolo up = warSoloFlip(s);
      expect(warSoloFlip(up), same(up));
    });
  });
}
