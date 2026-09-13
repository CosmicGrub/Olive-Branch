// OLIVE BRANCH — war_deck.dart tests. Network resilience & ad-hoc mode
// roadmap, Track B Option 2, ad-hoc games expansion. Pure-logic tests, no
// Flutter/widget/network involved — same posture as live_games_test.dart.
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/war_deck.dart';

void main() {
  group('standardDeck', () {
    test('is a real, complete 52-card deck — 13 ranks x 4 suits, no duplicates', () {
      final deck = standardDeck();
      expect(deck.length, 52);
      expect(deck.toSet().length, 52, reason: 'every card must be unique');
      for (final suit in Suit.values) {
        final ranksForSuit = deck.where((c) => c.suit == suit).map((c) => c.rank).toSet();
        expect(ranksForSuit, {2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14});
      }
    });
  });

  group('shuffledCopy', () {
    test('preserves every element — same multiset in, same multiset out', () {
      final deck = standardDeck();
      final shuffled = shuffledCopy(deck, Random(7));
      expect(shuffled.toSet(), deck.toSet());
      expect(shuffled.length, deck.length);
    });

    test('does not mutate the input list', () {
      final deck = standardDeck();
      final before = List<PlayingCard>.from(deck);
      shuffledCopy(deck, Random(1));
      expect(deck, before);
    });

    test('is deterministic for a given seed — same seed, same order', () {
      final a = shuffledCopy(standardDeck(), Random(42));
      final b = shuffledCopy(standardDeck(), Random(42));
      expect(a, b);
    });

    test('actually reorders (not just a coincidental no-op) for a real seed', () {
      final deck = standardDeck();
      final shuffled = shuffledCopy(deck, Random(123));
      expect(shuffled, isNot(deck));
    });
  });

  group('PlayingCard.code / fromCode round-trip', () {
    test('every real card round-trips through its own code', () {
      for (final card in standardDeck()) {
        final roundTripped = PlayingCard.fromCode(card.code);
        expect(roundTripped, card, reason: 'code was ${card.code}');
      }
    });

    test('face cards and ten use the expected single/double-char codes', () {
      expect(const PlayingCard(rank: 14, suit: Suit.spades).code, 'AS');
      expect(const PlayingCard(rank: 13, suit: Suit.hearts).code, 'KH');
      expect(const PlayingCard(rank: 12, suit: Suit.diamonds).code, 'QD');
      expect(const PlayingCard(rank: 11, suit: Suit.clubs).code, 'JC');
      expect(const PlayingCard(rank: 10, suit: Suit.spades).code, 'TS');
      expect(const PlayingCard(rank: 2, suit: Suit.hearts).code, '2H');
    });

    test('a malformed or foreign code returns null, never throws', () {
      expect(PlayingCard.fromCode(null), isNull);
      expect(PlayingCard.fromCode(''), isNull);
      expect(PlayingCard.fromCode('X'), isNull);
      expect(PlayingCard.fromCode('1S'), isNull); // rank 1 doesn't exist
      expect(PlayingCard.fromCode('15S'), isNull); // rank 15 doesn't exist
      expect(PlayingCard.fromCode('7Z'), isNull); // no such suit
      expect(PlayingCard.fromCode('not-a-card'), isNull);
    });
  });
}
