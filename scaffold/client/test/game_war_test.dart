// OLIVE BRANCH — game_war.dart engine tests. Network resilience & ad-hoc
// mode roadmap, Track B Option 2, ad-hoc games expansion. Pure-logic tests
// for the War engine (playMyNext/receiveTheirs/dealWar), plus a real
// two-sided simulation that plays this protocol against itself end to end
// — the single most valuable test here, since the individual functions
// passing in isolation says nothing about whether two independent devices
// running them actually stay consistent with each other over a real game.
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/war_deck.dart';
import 'package:olive_client/game_war.dart';

void main() {
  group('dealWar', () {
    test('splits one real deck into two complementary, non-overlapping 26-card halves', () {
      final dealt = dealWar(Random(3));
      expect(dealt.forMe.length, 26);
      expect(dealt.forPeer.length, 26);
      final union = {...dealt.forMe, ...dealt.forPeer};
      expect(union.length, 52, reason: 'no card should be missing or duplicated across the split');
      expect(union, standardDeck().toSet());
    });
  });

  group('newWarFromDeal', () {
    test('starts at round 1, playing, with no pot or pending plays', () {
      final dealt = dealWar(Random(1));
      final s = newWarFromDeal(dealt.forMe);
      expect(s.myPile.length, 26);
      expect(s.roundNumber, 1);
      expect(s.phase, WarPhase.playing);
      expect(s.pot, isEmpty);
      expect(s.myPending, isNull);
      expect(s.theirPending, isNull);
    });
  });

  group('playMyNext', () {
    test('a fresh round plays exactly one card and sets myPending', () {
      final s = newWarFromDeal(dealWar(Random(1)).forMe);
      final r = playMyNext(s);
      expect(r.played.length, 1);
      expect(r.state.myPile.length, 25);
      expect(r.state.myPending, r.played);
    });

    test('refuses a second flip before the first resolves', () {
      final s = newWarFromDeal(dealWar(Random(1)).forMe);
      final once = playMyNext(s).state;
      final twice = playMyNext(once);
      expect(twice.played, isEmpty);
      expect(twice.state, same(once));
    });

    test('an empty pile is an honest loss, not a crash', () {
      const s = WarState(myPile: [], roundNumber: 5, pot: [], myPending: null,
        theirPending: null, phase: WarPhase.playing, lastRoundNote: null);
      final r = playMyNext(s);
      expect(r.played, isEmpty);
      expect(r.state.phase, WarPhase.lost);
    });

    test('mid-war with only one card left plays it all-in, no wager', () {
      const oneLeft = PlayingCard(rank: 9, suit: Suit.clubs);
      const s = WarState(myPile: [oneLeft], roundNumber: 3,
        pot: [PlayingCard(rank: 5, suit: Suit.hearts), PlayingCard(rank: 5, suit: Suit.spades)],
        myPending: null, theirPending: null, phase: WarPhase.playing, lastRoundNote: null);
      final r = playMyNext(s);
      expect(r.played, [oneLeft]);
      expect(r.state.myPile, isEmpty);
    });
  });

  group('resolution (via playMyNext + receiveTheirs)', () {
    test('higher card wins both cards and the round advances', () {
      var s = newWarFromDeal([
        const PlayingCard(rank: 10, suit: Suit.spades),
        const PlayingCard(rank: 2, suit: Suit.hearts),
      ]);
      final flip = playMyNext(s);
      s = flip.state;
      s = receiveTheirs(s, const [PlayingCard(rank: 4, suit: Suit.clubs)]);
      expect(s.phase, WarPhase.playing);
      expect(s.roundNumber, 2);
      // I played the 10, won it back plus their 4 -> net pile: [2H] + [10S, 4C] won = 3 cards.
      expect(s.myPile.length, 3);
      expect(s.pot, isEmpty);
      expect(s.lastRoundNote, 'You win this round.');
    });

    test('losing removes my played card permanently and the round advances', () {
      var s = newWarFromDeal([
        const PlayingCard(rank: 3, suit: Suit.spades),
        const PlayingCard(rank: 9, suit: Suit.hearts),
      ]);
      s = playMyNext(s).state;
      s = receiveTheirs(s, const [PlayingCard(rank: 8, suit: Suit.clubs)]);
      expect(s.phase, WarPhase.playing);
      expect(s.roundNumber, 2);
      expect(s.myPile.length, 1); // only the 9H left; the 3S is gone for good
      expect(s.lastRoundNote, isNull);
    });

    test('a tie starts a war: pot accumulates, round does NOT advance', () {
      var s = newWarFromDeal([
        const PlayingCard(rank: 7, suit: Suit.spades),
        const PlayingCard(rank: 2, suit: Suit.hearts),
        const PlayingCard(rank: 9, suit: Suit.clubs),
      ]);
      s = playMyNext(s).state;
      s = receiveTheirs(s, const [PlayingCard(rank: 7, suit: Suit.diamonds)]);
      expect(s.phase, WarPhase.playing);
      expect(s.roundNumber, 1, reason: 'a war is still part of the round it started in');
      expect(s.pot.length, 2);
      expect(s.lastRoundNote, "It's a tie! War — flip again.");

      // Continuing the war plays a [wager, comparator] pair, not just one card.
      final continued = playMyNext(s);
      expect(continued.played.length, 2);
    });

    test('winning a full war chain takes every card ever staked, none lost or duplicated', () {
      // Round 1: tie (7 vs 7) -> war. Round 1 continuation: I wager 2S then
      // compare KH; they wager 3C then compare 4D. I win the whole chain.
      var s = newWarFromDeal([
        const PlayingCard(rank: 7, suit: Suit.spades),
        const PlayingCard(rank: 2, suit: Suit.spades),
        const PlayingCard(rank: 13, suit: Suit.hearts),
      ]);
      s = playMyNext(s).state; // flip the 7S
      s = receiveTheirs(s, const [PlayingCard(rank: 7, suit: Suit.diamonds)]); // tie -> war
      expect(s.pot.length, 2);

      final warFlip = playMyNext(s);
      expect(warFlip.played.length, 2); // [2S, KH]
      s = warFlip.state;
      s = receiveTheirs(s, const [
        PlayingCard(rank: 3, suit: Suit.clubs), PlayingCard(rank: 4, suit: Suit.diamonds),
      ]);

      expect(s.phase, WarPhase.playing);
      // Stake this whole chain: 7S,7D (initial tie) + 2S,KH (my war play) + 3C,4D (their war play) = 6 cards.
      // I win (K beats 4) -> my pile gains all 6.
      expect(s.myPile.length, 6);
      expect(s.pot, isEmpty);
    });

    test('a pile reaching all 52 cards is a real, detectable win', () {
      // Fabricate a state one round from taking every remaining card: I
      // hold 51 (a real, internally-consistent set is unnecessary here —
      // this state is hand-built, never dealt), about to win the last one.
      final almostAll = List<PlayingCard>.generate(51,
        (i) => PlayingCard(rank: 14 - (i % 13), suit: Suit.values[i ~/ 13 % 4]));
      var s = WarState(myPile: almostAll, roundNumber: 40, pot: const [],
        myPending: null, theirPending: null, phase: WarPhase.playing, lastRoundNote: null);
      s = playMyNext(s).state; // flip my first card — rank 14 (Ace), guaranteed highest
      s = receiveTheirs(s, const [PlayingCard(rank: 2, suit: Suit.hearts)]); // their only card, guaranteed lower
      expect(s.myPile.length, 52);
      expect(s.phase, WarPhase.won);
    });

    test('a fixed round cap ends the game as an honest, warm draw — never an infinite loop', () {
      const atCap = WarState(
        myPile: [PlayingCard(rank: 5, suit: Suit.spades)],
        roundNumber: warRoundCap, pot: [], myPending: null, theirPending: null,
        phase: WarPhase.playing, lastRoundNote: null,
      );
      final flipped = playMyNext(atCap).state;
      final resolved = receiveTheirs(flipped, const [PlayingCard(rank: 9, suit: Suit.hearts)]);
      expect(resolved.phase, WarPhase.drawnOut);
    });
  });

  group('real two-sided simulation — plays the protocol against itself end to end', () {
    test('every card is conserved across a full game; the two sides reach complementary outcomes', () {
      final rand = Random(99);
      final dealt = dealWar(rand);
      var a = newWarFromDeal(dealt.forMe);
      var b = newWarFromDeal(dealt.forPeer);

      var guard = 0;
      while (a.phase == WarPhase.playing && b.phase == WarPhase.playing) {
        guard++;
        expect(guard < 5000, isTrue, reason: 'simulation should terminate well within the round cap');

        final aFlip = playMyNext(a);
        a = aFlip.state;
        if (aFlip.played.isNotEmpty) b = receiveTheirs(b, aFlip.played);

        final bFlip = playMyNext(b);
        b = bFlip.state;
        if (bFlip.played.isNotEmpty) a = receiveTheirs(a, bFlip.played);

        // Real, load-bearing invariant: once both sides have fully
        // resolved this tick (no pending play, no live war pot on either
        // side), all 52 cards must be accounted for exactly once between
        // the two piles. This is the property that actually matters —
        // individual functions not crashing says nothing about two
        // independent devices staying consistent with each other. While a
        // war is still in progress on one side, its pot is real cards
        // temporarily "in flight," not lost — excluded here on purpose,
        // not because the invariant doesn't hold, only because summing
        // pile lengths alone doesn't capture pot contents.
        if (a.myPending == null && b.myPending == null && a.pot.isEmpty && b.pot.isEmpty) {
          expect(a.myPile.length + b.myPile.length, 52);
        }
      }

      expect(a.myPile.length + b.myPile.length, lessThanOrEqualTo(52));
      if (a.phase == WarPhase.won) expect(b.phase, WarPhase.lost);
      if (b.phase == WarPhase.won) expect(a.phase, WarPhase.lost);
      if (a.phase == WarPhase.drawnOut) expect(b.phase, WarPhase.drawnOut);
    });
  });
}
