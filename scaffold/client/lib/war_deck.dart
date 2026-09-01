// OLIVE BRANCH — a real, standard 52-card deck. Network resilience & ad-hoc
// mode roadmap, Track B Option 2, ad-hoc games expansion (see the "Ad-Hoc
// Play Expansion" plan) — the first real card-deck primitive in this
// codebase, built for game_war.dart and later reused (its shuffle
// algorithm, not its types — Uno's cards are color+type, not rank+suit) by
// uno_deck.dart.
//
// Hand-rolled, not a TS port: there is no existing packages/games/src
// counterpart for a plain playing-card deck (games.ts/games2.ts/games3.ts
// cover tictactoe/dotsboxes/memory/story/checkers/battleship/wordsearch/
// hangman/chess/chain/kim — no card game), and this file's whole reason to
// exist is a game that never touches a server at all (that is the entire
// point of local ad-hoc play). game_chess.dart already establishes real
// precedent in this exact codebase for a hand-rolled, non-ported engine
// when no TS counterpart makes sense — same discipline applied here:
// engine code only, no Flutter import, every design choice explained.
library;

import 'dart:math';

enum Suit { spades, hearts, diamonds, clubs }

/// rank is 2-14 (11=J, 12=Q, 13=K, 14=A) — comparable directly as an int,
/// which is exactly what War's own "higher card wins" rule needs.
class PlayingCard {
  const PlayingCard({required this.rank, required this.suit});
  final int rank;
  final Suit suit;

  /// A compact wire code ("7D", "AS", "TC"... — using "T" for ten avoids a
  /// two-character rank colliding with a two-character card code) — keeps
  /// even a long war chain's payload small, matching this transport's own
  /// "one small POST per turn" discipline.
  String get code => '${_rankChar(rank)}${_suitChar(suit)}';

  static String _rankChar(int rank) => switch (rank) {
    14 => 'A', 13 => 'K', 12 => 'Q', 11 => 'J', 10 => 'T',
    _ => '$rank',
  };
  static String _suitChar(Suit s) => switch (s) {
    Suit.spades => 'S', Suit.hearts => 'H', Suit.diamonds => 'D', Suit.clubs => 'C',
  };

  /// Returns null for anything malformed — a foreign/garbled wire value
  /// must never crash the receiving device's own game state, same
  /// discipline local_session.dart's own server already holds itself to
  /// for a malformed payload.
  static PlayingCard? fromCode(String? code) {
    if (code == null || code.length < 2) return null;
    final suit = switch (code[code.length - 1]) {
      'S' => Suit.spades, 'H' => Suit.hearts, 'D' => Suit.diamonds, 'C' => Suit.clubs,
      _ => null,
    };
    if (suit == null) return null;
    final rankPart = code.substring(0, code.length - 1);
    final rank = switch (rankPart) {
      'A' => 14, 'K' => 13, 'Q' => 12, 'J' => 11, 'T' => 10,
      _ => int.tryParse(rankPart),
    };
    if (rank == null || rank < 2 || rank > 14) return null;
    return PlayingCard(rank: rank, suit: suit);
  }

  @override
  String toString() => code;
  @override
  bool operator ==(Object other) => other is PlayingCard && other.rank == rank && other.suit == suit;
  @override
  int get hashCode => Object.hash(rank, suit);
}

/// 13 ranks x 4 suits, no jokers — a real, complete standard deck.
List<PlayingCard> standardDeck() => [
  for (final suit in Suit.values)
    for (var rank = 2; rank <= 14; rank++) PlayingCard(rank: rank, suit: suit),
];

/// Fisher-Yates with an injectable [Random] — the same shuffle idiom
/// live_games.dart's own newDeck() already established in this codebase,
/// for the same testability reason (a seeded Random makes the result
/// reproducible in a test).
List<T> shuffledCopy<T>(List<T> items, Random rand) {
  final list = List<T>.from(items);
  for (var i = list.length - 1; i > 0; i--) {
    final j = rand.nextInt(i + 1);
    final tmp = list[i];
    list[i] = list[j];
    list[j] = tmp;
  }
  return list;
}
