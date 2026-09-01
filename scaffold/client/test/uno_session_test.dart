// OLIVE BRANCH — uno_session.dart tests. Network resilience & ad-hoc mode
// roadmap, Track B Option 2, ad-hoc games expansion. Pure-logic tests, no
// Flutter/widget/network involved. Covers the real 2-4 seat scope this
// file's own header states, generalized off the old binary Side type.
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/uno_deck.dart';
import 'package:olive_client/uno_session.dart';

void main() {
  group('dealUno', () {
    test('deals 7 real cards to each of 2 seats and a plain-number opening discard', () {
      final s = dealUno(['a', 'b'], Random(1));
      expect(s.hands['a']!.length, 7);
      expect(s.hands['b']!.length, 7);
      expect(s.discardPile.length, 1);
      expect(s.topDiscard.type, UnoCardType.number);
      expect(s.turnSeatId, 'a');
      expect(s.clockwise, isTrue);
      expect(s.winner, isNull);
    });

    test('deals 7 real cards to each of 3 and 4 seats too', () {
      for (final seatOrder in [
        ['a', 'b', 'c'],
        ['a', 'b', 'c', 'd'],
      ]) {
        final s = dealUno(seatOrder, Random(2));
        for (final seatId in seatOrder) {
          expect(s.hands[seatId]!.length, 7, reason: '$seatId should have 7 cards');
        }
        expect(s.turnSeatId, seatOrder.first);
      }
    });

    test('every one of the real 108 cards is accounted for exactly once, at any table size', () {
      for (final seatOrder in [
        ['a', 'b'],
        ['a', 'b', 'c'],
        ['a', 'b', 'c', 'd'],
      ]) {
        final s = dealUno(seatOrder, Random(5));
        final all = [for (final seatId in seatOrder) ...s.hands[seatId]!, ...s.discardPile, ...s.drawPile];
        expect(all.length, 108, reason: '${seatOrder.length}-seat deal must still account for all 108 cards');
        final codes = all.map((c) => c.code).toList()..sort();
        final expected = standardUnoDeck().map((c) => c.code).toList()..sort();
        expect(codes, expected);
      }
    });
  });

  group('playCard — legality and turn re-validation', () {
    test('rejects a play from the wrong seat, state unchanged', () {
      final s = dealUno(['a', 'b'], Random(1)); // turn is 'a'
      final card = s.hands['b']!.first;
      final r = playCard(s, 'b', card, rand: Random(1));
      expect(r.accepted, isFalse);
      expect(r.reason, 'not_your_turn');
    });

    test('rejects a card not actually in the player\'s hand', () {
      final s = dealUno(['a', 'b'], Random(1));
      final foreignCard = standardUnoDeck().firstWhere((c) => !s.hands['a']!.contains(c) && c.type == UnoCardType.number);
      final r = playCard(s, 'a', foreignCard, rand: Random(1));
      expect(r.accepted, isFalse);
      expect(r.reason, 'not_in_hand');
    });

    test('a color/number match plays legally and advances the turn', () {
      final top = const UnoCard(type: UnoCardType.number, color: UnoColor.red, number: 5);
      final matching = const UnoCard(type: UnoCardType.number, color: UnoColor.red, number: 2);
      const spare = UnoCard(type: UnoCardType.number, color: UnoColor.green, number: 9);
      final s = UnoSession(seatOrder: const ['a', 'b'],
        drawPile: standardUnoDeck().where((c) => c != top && c != matching && c != spare).toList(),
        discardPile: [top], hands: {'a': [matching, spare], 'b': const []}, turnSeatId: 'a', clockwise: true,
        currentColor: UnoColor.red, winner: null);
      final r = playCard(s, 'a', matching, rand: Random(1));
      expect(r.accepted, isTrue);
      expect(r.session.turnSeatId, 'b');
      expect(r.session.currentColor, UnoColor.red);
    });

    test('a mismatched color and number is illegal', () {
      final top = const UnoCard(type: UnoCardType.number, color: UnoColor.red, number: 5);
      final mismatch = const UnoCard(type: UnoCardType.number, color: UnoColor.blue, number: 2);
      final s = UnoSession(seatOrder: const ['a', 'b'],
        drawPile: standardUnoDeck().where((c) => c != top && c != mismatch).toList(),
        discardPile: [top], hands: {'a': [mismatch], 'b': const []}, turnSeatId: 'a', clockwise: true,
        currentColor: UnoColor.red, winner: null);
      final r = playCard(s, 'a', mismatch, rand: Random(1));
      expect(r.accepted, isFalse);
      expect(r.reason, 'illegal_play');
    });

    test('a Wild is always legal but requires a chosen color', () {
      final top = const UnoCard(type: UnoCardType.number, color: UnoColor.red, number: 5);
      const wild = UnoCard(type: UnoCardType.wild);
      final s = UnoSession(seatOrder: const ['a', 'b'],
        drawPile: standardUnoDeck().where((c) => c != top).toList(),
        discardPile: [top], hands: {'a': [wild], 'b': const []}, turnSeatId: 'a', clockwise: true,
        currentColor: UnoColor.red, winner: null);
      final withoutColor = playCard(s, 'a', wild, rand: Random(1));
      expect(withoutColor.accepted, isFalse);
      expect(withoutColor.reason, 'color_required');
      final withColor = playCard(s, 'a', wild, chosenColor: UnoColor.green, rand: Random(1));
      expect(withColor.accepted, isTrue);
      expect(withColor.session.currentColor, UnoColor.green);
    });

    test('playing the last card in hand wins immediately', () {
      final top = const UnoCard(type: UnoCardType.number, color: UnoColor.red, number: 5);
      final last = const UnoCard(type: UnoCardType.number, color: UnoColor.red, number: 2);
      final s = UnoSession(seatOrder: const ['a', 'b'],
        drawPile: standardUnoDeck().where((c) => c != top && c != last).toList(),
        discardPile: [top], hands: {'a': [last], 'b': const []}, turnSeatId: 'a', clockwise: true,
        currentColor: UnoColor.red, winner: null);
      final r = playCard(s, 'a', last, rand: Random(1));
      expect(r.accepted, isTrue);
      expect(r.session.winner, 'a');
      expect(r.session.hands['a'], isEmpty);
    });
  });

  group('two-seat Skip/Reverse real-rule special case', () {
    test('Skip gives the player who played it another turn', () {
      final top = const UnoCard(type: UnoCardType.number, color: UnoColor.red, number: 5);
      final skip = const UnoCard(type: UnoCardType.skip, color: UnoColor.red);
      final s = UnoSession(seatOrder: const ['a', 'b'],
        drawPile: standardUnoDeck().where((c) => c != top && c != skip).toList(),
        discardPile: [top], hands: {'a': [skip, const UnoCard(type: UnoCardType.number, color: UnoColor.red, number: 1)], 'b': const []},
        turnSeatId: 'a', clockwise: true, currentColor: UnoColor.red, winner: null);
      final r = playCard(s, 'a', skip, rand: Random(1));
      expect(r.accepted, isTrue);
      expect(r.session.turnSeatId, 'a', reason: 'with 2 seats, Skip sends the turn right back to whoever played it');
    });

    test('Reverse behaves identically to Skip with 2 seats — the real official-rule special case', () {
      final top = const UnoCard(type: UnoCardType.number, color: UnoColor.red, number: 5);
      final reverse = const UnoCard(type: UnoCardType.reverse, color: UnoColor.red);
      final s = UnoSession(seatOrder: const ['a', 'b'],
        drawPile: standardUnoDeck().where((c) => c != top && c != reverse).toList(),
        discardPile: [top], hands: {'a': [reverse, const UnoCard(type: UnoCardType.number, color: UnoColor.red, number: 1)], 'b': const []},
        turnSeatId: 'a', clockwise: true, currentColor: UnoColor.red, winner: null);
      final r = playCard(s, 'a', reverse, rand: Random(1));
      expect(r.accepted, isTrue);
      expect(r.session.turnSeatId, 'a');
      expect(r.session.clockwise, isTrue, reason: 'direction bookkeeping is irrelevant with only 2 seats, but must not silently flip');
    });
  });

  group('3-4 seat Skip/Reverse — the real generalized rule, not the 2-seat special case', () {
    test('Skip at a 3-seat table skips exactly the next seat, lands on the one after', () {
      final top = const UnoCard(type: UnoCardType.number, color: UnoColor.red, number: 5);
      final skip = const UnoCard(type: UnoCardType.skip, color: UnoColor.red);
      // A spare card matters here — a hand of just [skip] would empty out
      // on this very play and trip the immediate-win branch instead of
      // the turn-order logic actually under test (the real "test the
      // test" lesson this engine's own tests hit once already this
      // session; caught again here by a real failing assertion, not
      // guessed).
      const spare = UnoCard(type: UnoCardType.number, color: UnoColor.blue, number: 3);
      final s = UnoSession(seatOrder: const ['a', 'b', 'c'],
        drawPile: standardUnoDeck().where((c) => c != top && c != skip && c != spare).toList(),
        discardPile: [top], hands: {'a': [skip, spare], 'b': const [], 'c': const []},
        turnSeatId: 'a', clockwise: true, currentColor: UnoColor.red, winner: null);
      final r = playCard(s, 'a', skip, rand: Random(1));
      expect(r.accepted, isTrue);
      expect(r.session.turnSeatId, 'c', reason: 'b is skipped entirely, turn lands on c');
    });

    test('Reverse at a 3-seat table actually flips direction and passes turn normally', () {
      final top = const UnoCard(type: UnoCardType.number, color: UnoColor.red, number: 5);
      final reverse = const UnoCard(type: UnoCardType.reverse, color: UnoColor.red);
      const spare = UnoCard(type: UnoCardType.number, color: UnoColor.blue, number: 3);
      final s = UnoSession(seatOrder: const ['a', 'b', 'c'],
        drawPile: standardUnoDeck().where((c) => c != top && c != reverse && c != spare).toList(),
        discardPile: [top], hands: {'a': [reverse, spare], 'b': const [], 'c': const []},
        turnSeatId: 'a', clockwise: true, currentColor: UnoColor.red, winner: null);
      final r = playCard(s, 'a', reverse, rand: Random(1));
      expect(r.accepted, isTrue);
      expect(r.session.clockwise, isFalse, reason: 'direction really flips with 3+ seats');
      expect(r.session.turnSeatId, 'c', reason: 'c is "before" a in the original order — the new-direction neighbor');
    });

    test('a second Reverse at a 4-seat table flips direction back and turn passes accordingly', () {
      final top = const UnoCard(type: UnoCardType.number, color: UnoColor.red, number: 5);
      final reverse = const UnoCard(type: UnoCardType.reverse, color: UnoColor.red);
      const spare = UnoCard(type: UnoCardType.number, color: UnoColor.blue, number: 3);
      // Direction already reversed once (clockwise: false), c's turn.
      final s = UnoSession(seatOrder: const ['a', 'b', 'c', 'd'],
        drawPile: standardUnoDeck().where((c) => c != top && c != reverse && c != spare).toList(),
        discardPile: [top], hands: {'a': const [], 'b': const [], 'c': [reverse, spare], 'd': const []},
        turnSeatId: 'c', clockwise: false, currentColor: UnoColor.red, winner: null);
      final r = playCard(s, 'c', reverse, rand: Random(1));
      expect(r.accepted, isTrue);
      expect(r.session.clockwise, isTrue, reason: 'a second Reverse flips direction back to forward');
      expect(r.session.turnSeatId, 'd', reason: 'd is the real forward neighbor of c once direction flips back');
    });
  });

  group('Draw Two / Wild Draw Four', () {
    test('Draw Two forces the next seat to draw 2 real cards and skips their turn too (2 seats)', () {
      final top = const UnoCard(type: UnoCardType.number, color: UnoColor.red, number: 5);
      final drawTwo = const UnoCard(type: UnoCardType.drawTwo, color: UnoColor.red);
      final s = UnoSession(seatOrder: const ['a', 'b'],
        drawPile: standardUnoDeck().where((c) => c != top && c != drawTwo).toList(),
        discardPile: [top],
        hands: {'a': [drawTwo, const UnoCard(type: UnoCardType.number, color: UnoColor.red, number: 1)], 'b': const []},
        turnSeatId: 'a', clockwise: true, currentColor: UnoColor.red, winner: null,
      );
      final beforeDrawPileLen = s.drawPile.length;
      final r = playCard(s, 'a', drawTwo, rand: Random(1));
      expect(r.accepted, isTrue);
      expect(r.session.hands['b']!.length, 2, reason: 'the victim drew 2 real cards');
      expect(r.session.drawPile.length, beforeDrawPileLen - 2);
      expect(r.session.turnSeatId, 'a', reason: 'the victim is skipped, turn returns to whoever played Draw Two');
    });

    test('Draw Two at a 3-seat table skips only the immediate next seat, not back to the player', () {
      final top = const UnoCard(type: UnoCardType.number, color: UnoColor.red, number: 5);
      final drawTwo = const UnoCard(type: UnoCardType.drawTwo, color: UnoColor.red);
      const spare = UnoCard(type: UnoCardType.number, color: UnoColor.blue, number: 3);
      final s = UnoSession(seatOrder: const ['a', 'b', 'c'],
        drawPile: standardUnoDeck().where((c) => c != top && c != drawTwo && c != spare).toList(),
        discardPile: [top], hands: {'a': [drawTwo, spare], 'b': const [], 'c': const []},
        turnSeatId: 'a', clockwise: true, currentColor: UnoColor.red, winner: null,
      );
      final r = playCard(s, 'a', drawTwo, rand: Random(1));
      expect(r.accepted, isTrue);
      expect(r.session.hands['b']!.length, 2, reason: 'b (the next seat) is the real victim, not c');
      expect(r.session.turnSeatId, 'c', reason: 'b is skipped after drawing — turn lands on c, NOT back on a');
    });

    test('Wild Draw Four forces the opponent to draw 4 and requires a chosen color', () {
      final top = const UnoCard(type: UnoCardType.number, color: UnoColor.red, number: 5);
      const wd4 = UnoCard(type: UnoCardType.wildDrawFour);
      const spare = UnoCard(type: UnoCardType.number, color: UnoColor.green, number: 9);
      final s = UnoSession(seatOrder: const ['a', 'b'],
        drawPile: standardUnoDeck().where((c) => c != top && c != spare).toList(),
        discardPile: [top], hands: {'a': [wd4, spare], 'b': const []}, turnSeatId: 'a', clockwise: true,
        currentColor: UnoColor.red, winner: null,
      );
      final r = playCard(s, 'a', wd4, chosenColor: UnoColor.blue, rand: Random(1));
      expect(r.accepted, isTrue);
      expect(r.session.hands['b']!.length, 4);
      expect(r.session.currentColor, UnoColor.blue);
      expect(r.session.turnSeatId, 'a');
    });

    test('a forced draw that outlasts the draw pile reshuffles the discard (minus the top) rather than crashing', () {
      final top = const UnoCard(type: UnoCardType.number, color: UnoColor.red, number: 5);
      final drawTwo = const UnoCard(type: UnoCardType.drawTwo, color: UnoColor.red);
      final filler = [const UnoCard(type: UnoCardType.number, color: UnoColor.green, number: 3)];
      // Only 1 card in the draw pile, but 2 are owed -- forces a mid-draw reshuffle.
      const spare = UnoCard(type: UnoCardType.number, color: UnoColor.blue, number: 8);
      final s = UnoSession(seatOrder: const ['a', 'b'],
        drawPile: [const UnoCard(type: UnoCardType.number, color: UnoColor.yellow, number: 4)],
        discardPile: [...filler, top],
        hands: {'a': [drawTwo, spare], 'b': const []}, turnSeatId: 'a', clockwise: true, currentColor: UnoColor.red, winner: null,
      );
      final r = playCard(s, 'a', drawTwo, rand: Random(3));
      expect(r.accepted, isTrue);
      expect(r.session.hands['b']!.length, 2);
    });
  });

  group('drawCard', () {
    test('a real draw adds one card to the hand and passes the turn', () {
      final s = dealUno(['a', 'b'], Random(2));
      final beforeLen = s.hands['a']!.length;
      final r = drawCard(s, 'a', Random(2));
      expect(r.accepted, isTrue);
      expect(r.session.hands['a']!.length, beforeLen + 1);
      expect(r.session.turnSeatId, 'b');
    });

    test('rejects a draw from the wrong seat', () {
      final s = dealUno(['a', 'b'], Random(2));
      final r = drawCard(s, 'b', Random(2));
      expect(r.accepted, isFalse);
      expect(r.reason, 'not_your_turn');
    });

    test('draw at a 3-seat table passes to the real next seat', () {
      final s = dealUno(['a', 'b', 'c'], Random(2));
      final r = drawCard(s, 'a', Random(2));
      expect(r.accepted, isTrue);
      expect(r.session.turnSeatId, 'b');
    });

    test('an exhausted draw pile with nothing to reshuffle is an honest refusal, not a crash', () {
      const s = UnoSession(seatOrder: ['a', 'b'], drawPile: [], discardPile: [UnoCard(type: UnoCardType.number, color: UnoColor.red, number: 5)],
        hands: {'a': [], 'b': []}, turnSeatId: 'a', clockwise: true, currentColor: UnoColor.red, winner: null);
      final r = drawCard(s, 'a', Random(1));
      expect(r.accepted, isFalse);
      expect(r.reason, 'no_cards_left');
    });
  });

  group('real end-to-end simulation, at every real table size', () {
    for (final seatOrder in [
      ['a', 'b'],
      ['a', 'b', 'c'],
      ['a', 'b', 'c', 'd'],
    ]) {
      test('a full randomized ${seatOrder.length}-seat game always terminates with a real winner or an honest stall, never a crash', () {
        var s = dealUno(seatOrder, Random(11));
        final rand = Random(11);
        var guard = 0;
        while (s.winner == null && guard < 20000) {
          guard++;
          final hand = s.hands[s.turnSeatId]!;
          UnoCard? legal;
          for (final c in hand) {
            if (c.type == UnoCardType.wild || c.type == UnoCardType.wildDrawFour) continue;
            if (_wouldBeLegal(c, s)) { legal = c; break; }
          }
          UnoCard? wildFallback;
          if (legal == null) {
            for (final c in hand) {
              if (c.type == UnoCardType.wild || c.type == UnoCardType.wildDrawFour) { wildFallback = c; break; }
            }
          }
          if (legal != null) {
            final r = playCard(s, s.turnSeatId, legal, rand: rand);
            expect(r.accepted, isTrue);
            s = r.session;
          } else if (wildFallback != null) {
            final chosen = _mostHeldColor(hand) ?? UnoColor.red;
            final r = playCard(s, s.turnSeatId, wildFallback, chosenColor: chosen, rand: rand);
            expect(r.accepted, isTrue);
            s = r.session;
          } else {
            final r = drawCard(s, s.turnSeatId, rand);
            if (!r.accepted) break; // genuinely out of cards on both piles -- an honest stall, not a bug
            s = r.session;
          }
        }
        expect(guard < 20000, isTrue, reason: 'a real game must not spin forever');
        // Real conservation check, every round of the simulation: every
        // seat's hand plus both piles always adds back up to 108 —
        // catches a card silently duplicated or lost by the turn-order
        // generalization, not just a crash.
        final total = [for (final seatId in seatOrder) ...s.hands[seatId]!, ...s.discardPile, ...s.drawPile].length;
        expect(total, 108);
      });
    }
  });
}

bool _wouldBeLegal(UnoCard card, UnoSession s) {
  final top = s.topDiscard;
  if (card.color == s.currentColor) return true;
  if (card.type == UnoCardType.number && top.type == UnoCardType.number && card.number == top.number) return true;
  if (card.type != UnoCardType.number && card.type == top.type) return true;
  return false;
}

UnoColor? _mostHeldColor(List<UnoCard> hand) {
  final counts = <UnoColor, int>{};
  for (final c in hand) {
    if (c.color == null) continue;
    counts[c.color!] = (counts[c.color!] ?? 0) + 1;
  }
  if (counts.isEmpty) return null;
  return counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
}
