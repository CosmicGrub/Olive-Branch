// OLIVE BRANCH — uno_deck.dart tests. Network resilience & ad-hoc mode
// roadmap, Track B Option 2, ad-hoc games expansion. Pure-logic tests, no
// Flutter/widget/network involved.
import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/uno_deck.dart';

void main() {
  group('standardUnoDeck', () {
    test('is a real, complete 108-card deck', () {
      final deck = standardUnoDeck();
      expect(deck.length, 108);
    });

    test('each color has exactly 25 non-wild cards', () {
      final deck = standardUnoDeck();
      for (final color in UnoColor.values) {
        final count = deck.where((c) => c.color == color).length;
        expect(count, 25, reason: '$color should have 25 cards (one 0, two each 1-9, two Skip, two Reverse, two Draw Two)');
      }
    });

    test('exactly 4 Wild and 4 Wild Draw Four cards', () {
      final deck = standardUnoDeck();
      expect(deck.where((c) => c.type == UnoCardType.wild).length, 4);
      expect(deck.where((c) => c.type == UnoCardType.wildDrawFour).length, 4);
    });

    test('each color has exactly one 0 and two of each 1-9', () {
      final deck = standardUnoDeck();
      for (final color in UnoColor.values) {
        final numbered = deck.where((c) => c.color == color && c.type == UnoCardType.number);
        expect(numbered.where((c) => c.number == 0).length, 1);
        for (var n = 1; n <= 9; n++) {
          expect(numbered.where((c) => c.number == n).length, 2, reason: 'color $color number $n');
        }
      }
    });
  });

  group('shuffledUnoDeck', () {
    test('preserves the full 108-card multiset', () {
      final shuffled = shuffledUnoDeck(Random(7));
      expect(shuffled.length, 108);
      // Compare as codes since UnoCard has no natural multiset comparison beyond ==.
      final originalCodes = standardUnoDeck().map((c) => c.code).toList()..sort();
      final shuffledCodes = shuffled.map((c) => c.code).toList()..sort();
      expect(shuffledCodes, originalCodes);
    });

    test('is deterministic for a given seed', () {
      final a = shuffledUnoDeck(Random(42));
      final b = shuffledUnoDeck(Random(42));
      expect(a.map((c) => c.code).toList(), b.map((c) => c.code).toList());
    });
  });

  group('UnoCard.code / fromCode round-trip', () {
    test('every real card round-trips through its own code', () {
      for (final card in standardUnoDeck()) {
        final roundTripped = UnoCard.fromCode(card.code);
        expect(roundTripped, card, reason: 'code was ${card.code}');
      }
    });

    test('known codes match the expected shape', () {
      expect(const UnoCard(type: UnoCardType.number, color: UnoColor.red, number: 7).code, 'R7');
      expect(const UnoCard(type: UnoCardType.skip, color: UnoColor.yellow).code, 'Y-Skip');
      expect(const UnoCard(type: UnoCardType.reverse, color: UnoColor.green).code, 'G-Reverse');
      expect(const UnoCard(type: UnoCardType.drawTwo, color: UnoColor.blue).code, 'B-Draw2');
      expect(const UnoCard(type: UnoCardType.wild).code, 'W');
      expect(const UnoCard(type: UnoCardType.wildDrawFour).code, 'WD4');
    });

    test('a malformed or foreign code returns null, never throws', () {
      expect(UnoCard.fromCode(null), isNull);
      expect(UnoCard.fromCode(''), isNull);
      expect(UnoCard.fromCode('X'), isNull);
      expect(UnoCard.fromCode('Z7'), isNull);
      expect(UnoCard.fromCode('R99'), isNull);
      expect(UnoCard.fromCode('R-Bogus'), isNull);
      expect(UnoCard.fromCode('not-a-card'), isNull);
    });
  });
}
