// OLIVE BRANCH — a real, standard 108-card Uno deck. Network resilience &
// ad-hoc mode roadmap, Track B Option 2, ad-hoc games expansion. Hand-
// rolled, not a TS port — same reasoning as war_deck.dart/
// connect4_engine.dart/together_puzzle.dart's own headers: no
// packages/games/src counterpart exists for this, and every game in this
// expansion exists specifically because it never touches a server.
//
// Real composition (108 cards): 4 colors x (one 0, two each of 1-9, two
// Skip, two Reverse, two Draw Two) = 4x25=100, plus 4 Wild + 4 Wild Draw
// Four = 108. Reuses war_deck.dart's own shuffledCopy() algorithm
// directly — not its types (a playing-card Suit/rank has nothing to do
// with an Uno color/type), just the same Fisher-Yates mechanics.
library;

import 'dart:math';
import 'war_deck.dart' show shuffledCopy;

enum UnoColor { red, yellow, green, blue }

enum UnoCardType { number, skip, reverse, drawTwo, wild, wildDrawFour }

class UnoCard {
  const UnoCard({required this.type, this.color, this.number});
  final UnoCardType type;
  /// Null only for wild/wildDrawFour BEFORE a color is chosen for them on
  /// play — the deck/hand itself always carries color:null for those two
  /// types; [UnoSession] tracks the chosen color separately as
  /// [UnoSession.currentColor], never by mutating the card.
  final UnoColor? color;
  /// Only meaningful for [UnoCardType.number] (0-9).
  final int? number;

  /// A compact wire code: "R7" / "Y-Skip" / "WD4" / "W". Kept small on
  /// purpose — even a large post-stacking hand stays a short JSON array.
  String get code {
    switch (type) {
      case UnoCardType.wild: return 'W';
      case UnoCardType.wildDrawFour: return 'WD4';
      case UnoCardType.number: return '${_colorChar(color!)}$number';
      case UnoCardType.skip: return '${_colorChar(color!)}-Skip';
      case UnoCardType.reverse: return '${_colorChar(color!)}-Reverse';
      case UnoCardType.drawTwo: return '${_colorChar(color!)}-Draw2';
    }
  }

  static String _colorChar(UnoColor c) => switch (c) {
    UnoColor.red => 'R', UnoColor.yellow => 'Y', UnoColor.green => 'G', UnoColor.blue => 'B',
  };

  static UnoColor? _colorFromChar(String c) => switch (c) {
    'R' => UnoColor.red, 'Y' => UnoColor.yellow, 'G' => UnoColor.green, 'B' => UnoColor.blue,
    _ => null,
  };

  static UnoCard? fromCode(String? code) {
    if (code == null || code.isEmpty) return null;
    if (code == 'W') return const UnoCard(type: UnoCardType.wild);
    if (code == 'WD4') return const UnoCard(type: UnoCardType.wildDrawFour);
    if (code.length < 2) return null;
    final color = _colorFromChar(code[0]);
    if (color == null) return null;
    final rest = code.substring(1);
    if (rest == '-Skip') return UnoCard(type: UnoCardType.skip, color: color);
    if (rest == '-Reverse') return UnoCard(type: UnoCardType.reverse, color: color);
    if (rest == '-Draw2') return UnoCard(type: UnoCardType.drawTwo, color: color);
    final n = int.tryParse(rest);
    if (n == null || n < 0 || n > 9) return null;
    return UnoCard(type: UnoCardType.number, color: color, number: n);
  }

  @override
  String toString() => code;
  @override
  bool operator ==(Object other) => other is UnoCard && other.code == code;
  @override
  int get hashCode => code.hashCode;
}

/// The real, complete 108-card deck — see this file's own header for the
/// composition breakdown.
List<UnoCard> standardUnoDeck() {
  final cards = <UnoCard>[];
  for (final color in UnoColor.values) {
    cards.add(UnoCard(type: UnoCardType.number, color: color, number: 0));
    for (var n = 1; n <= 9; n++) {
      cards.add(UnoCard(type: UnoCardType.number, color: color, number: n));
      cards.add(UnoCard(type: UnoCardType.number, color: color, number: n));
    }
    for (var i = 0; i < 2; i++) {
      cards.add(UnoCard(type: UnoCardType.skip, color: color));
      cards.add(UnoCard(type: UnoCardType.reverse, color: color));
      cards.add(UnoCard(type: UnoCardType.drawTwo, color: color));
    }
  }
  for (var i = 0; i < 4; i++) {
    cards.add(const UnoCard(type: UnoCardType.wild));
    cards.add(const UnoCard(type: UnoCardType.wildDrawFour));
  }
  return cards;
}

List<UnoCard> shuffledUnoDeck(Random rand) => shuffledCopy(standardUnoDeck(), rand);
