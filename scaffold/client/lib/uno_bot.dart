// OLIVE BRANCH — Uno CPU opponent. Network resilience & ad-hoc mode
// roadmap, Track B Option 2, ad-hoc games expansion.
//
// Every tier sees only public information — its own hand, the discard
// top/color, every OTHER seat's card COUNT — never another seat's real
// hand, at any difficulty. That's what keeps every tier legitimately
// beatable rather than winning by omniscience, the same discipline
// connect4_bot.dart already holds itself to. No bluffing at any tier
// (a bluffing Hard-tier bot is real, disclosed, deferred scope — see
// uno_session.dart's own header on this file's real v1 trim).
//
// GENERALIZED alongside uno_session.dart off the binary Side type onto
// real seatIds — this bot now takes a real Map<String,int> of every
// OTHER seat's hand count (2-4 seat tables can have more than one real
// opponent), not a single int. Hard's own "press with an action card
// when an opponent is close to going out" logic now presses when ANY
// other seat is close, not just "the" opponent — the real, natural
// generalization of the same instinct.
//
// The bot runs entirely on whichever device is authoritative for the
// session it's playing in (see game_uno.dart's own header for what
// "authoritative" means here) — only its resulting action ever needs to
// leave that device, identical treatment to a human's move.
library;

import 'dart:math';
import 'uno_deck.dart';
import 'uno_session.dart';

enum UnoCpuDifficulty { easy, normal, hard }

class UnoBotMove {
  const UnoBotMove.play(this.card, this.color) : isDraw = false;
  const UnoBotMove.draw() : card = null, color = null, isDraw = true;
  final UnoCard? card;
  final UnoColor? color;
  final bool isDraw;
}

/// The color the hand holds most of — used both for a Wild's own color
/// choice (maximizes the bot's own next-turn options) and, at Hard, to
/// prefer thinning whichever color is already scarce in hand.
UnoColor _mostHeldColor(List<UnoCard> hand, Random rand) {
  final counts = <UnoColor, int>{};
  for (final c in hand) {
    if (c.color == null) continue;
    counts[c.color!] = (counts[c.color!] ?? 0) + 1;
  }
  if (counts.isEmpty) {
    return UnoColor.values[rand.nextInt(UnoColor.values.length)];
  }
  var best = counts.entries.first;
  for (final e in counts.entries) {
    if (e.value > best.value) best = e;
  }
  return best.key;
}

/// Picks [botSeatId]'s move given the real, shared session state and its
/// own real hand. [opponentHandCounts] carries every OTHER seat's card
/// count (never a hand) — real public information available at any real
/// table. Returns [UnoBotMove.draw] when nothing in hand is legal.
UnoBotMove chooseUnoMove(UnoSession session, String botSeatId, UnoCpuDifficulty difficulty,
    Map<String, int> opponentHandCounts, Random rand) {
  final hand = session.hands[botSeatId]!;
  final legal = hand.where((c) => isLegalUnoPlay(c, session)).toList();
  if (legal.isEmpty) return const UnoBotMove.draw();

  final nonWild = legal.where((c) => c.type != UnoCardType.wild && c.type != UnoCardType.wildDrawFour).toList();

  if (difficulty == UnoCpuDifficulty.easy) {
    final choice = legal[rand.nextInt(legal.length)];
    return _asMove(choice, hand, rand);
  }

  if (difficulty == UnoCpuDifficulty.normal) {
    // Prefer spending a real, matching card over a Wild — Wilds held back
    // for flexibility, same real-Uno instinct a thoughtful human plays by.
    if (nonWild.isNotEmpty) return _asMove(nonWild[rand.nextInt(nonWild.length)], hand, rand);
    return _asMove(legal.first, hand, rand);
  }

  // Hard: play action cards more aggressively once ANY other seat is
  // close to going out, otherwise prefer thinning the color already
  // scarcest in hand (keeps the remaining hand flexible for longer).
  final closestOpponent = opponentHandCounts.values.isEmpty
      ? null
      : opponentHandCounts.values.reduce((a, b) => a < b ? a : b);
  final actionCards = nonWild.where((c) =>
    c.type == UnoCardType.skip || c.type == UnoCardType.reverse || c.type == UnoCardType.drawTwo).toList();
  if (closestOpponent != null && closestOpponent <= 3 && actionCards.isNotEmpty) {
    return _asMove(actionCards.first, hand, rand);
  }
  if (nonWild.isNotEmpty) {
    final counts = <UnoColor, int>{};
    for (final c in hand) {
      if (c.color != null) counts[c.color!] = (counts[c.color!] ?? 0) + 1;
    }
    nonWild.sort((a, b) => (counts[a.color] ?? 0).compareTo(counts[b.color] ?? 0));
    return _asMove(nonWild.first, hand, rand);
  }
  return _asMove(legal.first, hand, rand);
}

UnoBotMove _asMove(UnoCard card, List<UnoCard> hand, Random rand) {
  final isWild = card.type == UnoCardType.wild || card.type == UnoCardType.wildDrawFour;
  return UnoBotMove.play(card, isWild ? _mostHeldColor(hand.where((c) => c != card).toList(), rand) : null);
}
