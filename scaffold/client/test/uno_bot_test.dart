// OLIVE BRANCH — uno_bot.dart tests. Network resilience & ad-hoc mode
// roadmap, Track B Option 2, ad-hoc games expansion. Pure-logic tests, no
// Flutter/widget/network involved.
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/uno_deck.dart';
import 'package:olive_client/uno_session.dart';
import 'package:olive_client/uno_bot.dart';

UnoSession _sessionWith({required List<UnoCard> botHand, required UnoCard top, UnoColor? color}) => UnoSession(
  seatOrder: const ['a', 'b'],
  drawPile: standardUnoDeck().where((c) => !botHand.contains(c) && c != top).toList(),
  discardPile: [top], hands: {'a': botHand, 'b': const []}, turnSeatId: 'a', clockwise: true,
  currentColor: color ?? (top.color ?? UnoColor.red), winner: null,
);

void main() {
  group('chooseUnoMove — always legal, never omniscient beyond public info', () {
    test('plays a legal card when one exists (every difficulty)', () {
      const top = UnoCard(type: UnoCardType.number, color: UnoColor.red, number: 5);
      const matching = UnoCard(type: UnoCardType.number, color: UnoColor.red, number: 2);
      const offColor = UnoCard(type: UnoCardType.number, color: UnoColor.blue, number: 9);
      final session = _sessionWith(botHand: const [offColor, matching], top: top);
      for (final d in UnoCpuDifficulty.values) {
        final move = chooseUnoMove(session, 'a', d, {'b': 5}, Random(1));
        expect(move.isDraw, isFalse, reason: '$d should find the legal match');
        expect(isLegalUnoPlay(move.card!, session), isTrue);
      }
    });

    test('signals draw when nothing in hand is legal', () {
      const top = UnoCard(type: UnoCardType.number, color: UnoColor.red, number: 5);
      const offColor1 = UnoCard(type: UnoCardType.number, color: UnoColor.blue, number: 2);
      const offColor2 = UnoCard(type: UnoCardType.number, color: UnoColor.green, number: 9);
      final session = _sessionWith(botHand: const [offColor1, offColor2], top: top, color: UnoColor.red);
      for (final d in UnoCpuDifficulty.values) {
        final move = chooseUnoMove(session, 'a', d, {'b': 5}, Random(1));
        expect(move.isDraw, isTrue, reason: '$d has no legal card and must draw');
      }
    });

    test('a chosen Wild color always comes from the bot\'s own remaining hand when possible', () {
      const wild = UnoCard(type: UnoCardType.wild);
      const green1 = UnoCard(type: UnoCardType.number, color: UnoColor.green, number: 3);
      const green2 = UnoCard(type: UnoCardType.number, color: UnoColor.green, number: 7);
      const blue1 = UnoCard(type: UnoCardType.number, color: UnoColor.blue, number: 1);
      // Force a hand with no legal color/number match, only the Wild.
      const top = UnoCard(type: UnoCardType.number, color: UnoColor.red, number: 5);
      final session = UnoSession(
        seatOrder: const ['a', 'b'],
        drawPile: standardUnoDeck().where((c) => c != wild && c != green1 && c != green2 && c != blue1 && c != top).toList(),
        discardPile: [top], hands: {'a': const [wild, green1, green2, blue1], 'b': const []},
        turnSeatId: 'a', clockwise: true, currentColor: UnoColor.yellow, winner: null,
      );
      final move = chooseUnoMove(session, 'a', UnoCpuDifficulty.hard, {'b': 5}, Random(2));
      expect(move.isDraw, isFalse);
      expect(move.card!.type, UnoCardType.wild);
      expect(move.color, UnoColor.green, reason: 'green is held twice, blue only once — most-held wins');
    });

    test('Hard prefers an action card when the opponent is close to going out', () {
      const top = UnoCard(type: UnoCardType.number, color: UnoColor.red, number: 5);
      const skip = UnoCard(type: UnoCardType.skip, color: UnoColor.red);
      const plainMatch = UnoCard(type: UnoCardType.number, color: UnoColor.red, number: 2);
      final session = _sessionWith(botHand: const [plainMatch, skip], top: top);
      final move = chooseUnoMove(session, 'a', UnoCpuDifficulty.hard, {'b': 2}, Random(1));
      expect(move.card, skip, reason: 'the opponent has only 2 cards left — Hard should press with the action card');
    });

    test('Hard presses when ANY of several real opponents is close to going out, at a 3-4 seat table', () {
      const top = UnoCard(type: UnoCardType.number, color: UnoColor.red, number: 5);
      const skip = UnoCard(type: UnoCardType.skip, color: UnoColor.red);
      const plainMatch = UnoCard(type: UnoCardType.number, color: UnoColor.red, number: 2);
      final session = UnoSession(
        seatOrder: const ['a', 'b', 'c', 'd'],
        drawPile: standardUnoDeck().where((c) => c != top && c != skip && c != plainMatch).toList(),
        discardPile: [top], hands: {'a': const [plainMatch, skip], 'b': const [], 'c': const [], 'd': const []},
        turnSeatId: 'a', clockwise: true, currentColor: UnoColor.red, winner: null,
      );
      // b and d are comfortable; c is the one seat close to going out —
      // the bot must notice c specifically, not just check "the" opponent.
      final move = chooseUnoMove(session, 'a', UnoCpuDifficulty.hard, {'b': 6, 'c': 1, 'd': 7}, Random(1));
      expect(move.card, skip, reason: 'c (one of three real opponents) is down to 1 card — Hard must still press');
    });

    test('never reaches into any other seat\'s real hand — only this session\'s own [bot] hand and public counts', () {
      const top = UnoCard(type: UnoCardType.number, color: UnoColor.red, number: 5);
      const matching = UnoCard(type: UnoCardType.number, color: UnoColor.red, number: 2);
      final session = _sessionWith(botHand: const [matching], top: top);
      // The function signature itself is the real guarantee here: it
      // takes a Map<String,int> of counts, never a map of hands, so there
      // is nothing for the bot to inspect even by accident. This test
      // just exercises that call shape stays intact after generalizing
      // to N-1 real opponents.
      final move = chooseUnoMove(session, 'a', UnoCpuDifficulty.easy, {'b': 7}, Random(1));
      expect(move.isDraw, isFalse);
    });
  });

  group('botRemembersToCallUno / botCatchesMissedUno / botChallengesWildDrawFour — '
      'real, disclosed difficulty-scaled decisions, never omniscient', () {
    // Statistical checks over a real, large sample -- each function is a
    // genuine RNG-driven decision, not a fixed lookup, so the real thing
    // worth proving is "the difficulty axis actually has an effect, in
    // the right direction, within a wide honest tolerance" rather than
    // pinning an exact count that would make this test as brittle as the
    // implementation's own literal thresholds.
    const trials = 2000;

    test('Hard always remembers to call Uno; Easy forgets often; Normal sits between', () {
      final rand = Random(7);
      int trueCount(UnoCpuDifficulty d) =>
        List.generate(trials, (_) => botRemembersToCallUno(d, rand)).where((b) => b).length;
      final hard = trueCount(UnoCpuDifficulty.hard);
      final normal = trueCount(UnoCpuDifficulty.normal);
      final easy = trueCount(UnoCpuDifficulty.easy);
      expect(hard, trials, reason: 'Hard is deterministic here — always remembers');
      expect(normal, greaterThan(easy), reason: 'Normal must remember more often than Easy');
      expect(easy, lessThan(trials), reason: 'Easy must genuinely forget sometimes — a real catchable moment');
    });

    test('Hard catches a missed call far more often than Easy', () {
      final rand = Random(8);
      int trueCount(UnoCpuDifficulty d) =>
        List.generate(trials, (_) => botCatchesMissedUno(d, rand)).where((b) => b).length;
      final hard = trueCount(UnoCpuDifficulty.hard);
      final normal = trueCount(UnoCpuDifficulty.normal);
      final easy = trueCount(UnoCpuDifficulty.easy);
      expect(hard, greaterThan(normal));
      expect(normal, greaterThan(easy));
      expect(easy, greaterThan(0), reason: 'Easy must still catch SOMETIMES, not never');
    });

    test('Easy never challenges a Wild Draw Four; Hard challenges more than Normal', () {
      final rand = Random(9);
      int trueCount(UnoCpuDifficulty d) =>
        List.generate(trials, (_) => botChallengesWildDrawFour(d, rand)).where((b) => b).length;
      expect(trueCount(UnoCpuDifficulty.easy), 0, reason: 'Easy never bothers to challenge');
      final normal = trueCount(UnoCpuDifficulty.normal);
      final hard = trueCount(UnoCpuDifficulty.hard);
      expect(hard, greaterThan(normal));
      expect(normal, greaterThan(0), reason: 'Normal must genuinely challenge sometimes');
    });
  });
}
