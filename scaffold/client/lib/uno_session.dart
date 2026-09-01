// OLIVE BRANCH — Uno, the ad-hoc local card game engine. Network
// resilience & ad-hoc mode roadmap, Track B Option 2, ad-hoc games
// expansion. Fifth and last of five new local-play activities, and the
// most complex — see the "Ad-Hoc Play Expansion" plan for the full
// account of why it's sequenced last (every simpler pattern underneath it
// — pairing, a card deck, CPU strategy, turn transport — is already
// proven by War/Connect 4 first).
//
// GENERALIZED OFF THE BINARY Side TYPE onto game_seat.dart's real
// seatId/SeatRoster model — this file's own original v1 pass was hardcoded
// to exactly two live_games.dart Side{a,b} seats, a real, disclosed
// limitation that was later found to still be true even after
// game_seat.dart existed (that roster type was built but never actually
// wired into this engine — see the Ad-Hoc Play Expansion memory for the
// full account of catching that stale claim). This pass makes every turn
// a real seatId (String) walking a real [UnoSession.seatOrder] — 2-4
// seats — rather than a hardcoded two-value toggle.
//
// REAL SCOPE TRIM, still true after this pass, disclosed rather than
// silently shipped thin: this file implements Uno's core rules (color/
// number matching, Skip, Reverse, Draw Two, Wild, Wild Draw Four, win on
// an empty hand) for 2-4 seats. Deliberately NOT in this pass, each a
// real, separate follow-up: the four optional house rules (stacking,
// jump-in, 7-0, Wild Draw Four challenge), calling "Uno" at one card, and
// team-victory framing (this file only ever reports the seatId that
// emptied its hand as [UnoSession.winner] — recognizing that as a whole
// team's win, for a 2v2 table, is the caller's job via
// game_seat.dart's own SeatRoster.byId(winner).teamId, not this file's).
//
// TURN ORDER is a real, generalized rotation through [UnoSession.
// seatOrder] — the fixed table order for the whole game, pre-resolved
// (including any team interleaving) by whoever deals via
// game_seat.dart's SeatRoster.turnOrder(). [UnoSession.clockwise] tracks
// the current direction; only Reverse ever flips it. Every action card's
// real rule is expressed as real seat-order arithmetic now, verified to
// reduce to this file's own previously-tested exact 2-seat behavior:
// - Skip: the very next seat is skipped entirely, turn lands on the seat
//   after that. With exactly 2 seats that's "turn stays with the player
//   who played it" (skip the only other seat, land back on yourself).
// - Reverse: flips [clockwise] and passes turn normally under the new
//   direction — a real direction change, not a skip, whenever 3+ seats
//   are at the table. With exactly 2 seats, reversing direction between
//   only two seats is a mathematical no-op (there's only ever one "other"
//   seat either way) — official Uno rules special-case this by having a
//   2-player Reverse act exactly like Skip instead, since otherwise it
//   would be a dead card (a plain turn pass, indistinguishable from any
//   other card). This file matches that real rule explicitly, not by
//   accident.
// - Draw Two / Wild Draw Four: the victim is always the very next seat in
//   the CURRENT direction (not "the other side"); after they draw, the
//   victim's own turn is skipped too — turn lands on the seat after the
//   victim. With exactly 2 seats, the seat after the victim IS the player
//   who played the card, matching this file's own prior 2-seat-only
//   behavior exactly.
library;

import 'dart:math';
import 'uno_deck.dart';

class UnoSession {
  const UnoSession({
    required this.seatOrder, required this.drawPile, required this.discardPile,
    required this.hands, required this.turnSeatId, required this.clockwise,
    required this.currentColor, required this.winner,
  });

  /// Fixed for the whole game — the real seatIds (game_seat.dart's own
  /// Seat.seatId), in real table/turn order, already resolved (including
  /// any team interleaving) before dealing. 2-4 entries.
  final List<String> seatOrder;
  final List<UnoCard> drawPile;
  /// Top of the discard pile is the LAST element.
  final List<UnoCard> discardPile;
  final Map<String, List<UnoCard>> hands;
  final String turnSeatId;
  /// True = play advances forward through [seatOrder]; false = backward.
  /// Only Reverse ever flips this — see this file's own header for why it
  /// only has an observable effect with 3+ seats.
  final bool clockwise;
  /// The color in play — always set even after a numbered/non-wild card
  /// (matches that card's own color); only a Wild/Wild Draw Four changes
  /// it to something other than the top discard's own color.
  final UnoColor currentColor;
  /// The seatId that emptied its hand, or null while the game continues.
  /// Whether that's a solo win or a whole team's win (2v2) is the
  /// caller's call via game_seat.dart's own SeatRoster — this file only
  /// ever reports the real seat that actually went out.
  final String? winner;

  UnoCard get topDiscard => discardPile.last;
}

UnoColor _colorOf(UnoCard c) => c.color ?? UnoColor.red; // wild cards' real color is chosen separately; never read for wilds

/// The next seat in [order] from [from], walking forward if [clockwise]
/// else backward — the one real primitive every action card's real rule
/// is built from.
String _seatAfter(List<String> order, String from, bool clockwise) {
  final i = order.indexOf(from);
  final step = clockwise ? 1 : -1;
  return order[(i + step + order.length) % order.length];
}

/// Deals a real, fresh 108-card game: 7 cards to each seat in
/// [seatOrder] (2-4 seats), an opening discard drawn until a plain
/// number card appears (a common, honest simplification of the real,
/// genuinely more complex special-case rules for starting on an action
/// or Wild card — not a hidden bug).
UnoSession dealUno(List<String> seatOrder, Random rand) {
  assert(seatOrder.length >= 2 && seatOrder.length <= 4, 'Uno seats 2-4 players, got ${seatOrder.length}');
  assert(seatOrder.toSet().length == seatOrder.length, 'seatOrder must not repeat a seatId');
  final deck = shuffledUnoDeck(rand);
  final hands = <String, List<UnoCard>>{};
  var cursor = 0;
  for (final seatId in seatOrder) {
    hands[seatId] = deck.sublist(cursor, cursor + 7);
    cursor += 7;
  }
  var rest = deck.sublist(cursor);
  var openingIndex = rest.indexWhere((c) => c.type == UnoCardType.number);
  if (openingIndex < 0) openingIndex = 0; // pathological all-action shuffle; fall back rather than loop forever
  final opening = rest[openingIndex];
  rest = [...rest.sublist(0, openingIndex), ...rest.sublist(openingIndex + 1)];
  return UnoSession(
    seatOrder: seatOrder, drawPile: rest, discardPile: [opening], hands: hands,
    turnSeatId: seatOrder.first, clockwise: true, currentColor: _colorOf(opening), winner: null,
  );
}

/// Reshuffles everything but the top discard back into the draw pile when
/// it runs dry — the same "never let the game stall for want of cards"
/// discipline live_games.dart's own draw() already holds itself to for
/// Twenty Questions' prompt deck.
UnoSession _ensureDrawable(UnoSession s, Random rand) {
  if (s.drawPile.isNotEmpty) return s;
  if (s.discardPile.length <= 1) return s; // genuinely nothing left to reshuffle; caller handles the empty case
  final top = s.discardPile.last;
  final reshuffled = shuffledCopyOf(s.discardPile.sublist(0, s.discardPile.length - 1), rand);
  return UnoSession(seatOrder: s.seatOrder, drawPile: reshuffled, discardPile: [top], hands: s.hands,
    turnSeatId: s.turnSeatId, clockwise: s.clockwise, currentColor: s.currentColor, winner: s.winner);
}

class PlayResult {
  const PlayResult({required this.session, required this.accepted, this.reason});
  final UnoSession session;
  final bool accepted;
  final String? reason;
}

/// Public — uno_bot.dart's own strategy layer reuses this exact check to
/// filter which of its hand's cards are worth considering, rather than
/// keeping a second, driftable copy of Uno's real matching rules. The
/// authoritative check still happens inside [playCard] regardless; this
/// is the single real source of truth both places call.
bool isLegalUnoPlay(UnoCard card, UnoSession s) => _isLegalPlay(card, s);

bool _isLegalPlay(UnoCard card, UnoSession s) {
  if (card.type == UnoCardType.wild || card.type == UnoCardType.wildDrawFour) return true;
  final top = s.topDiscard;
  if (card.color == s.currentColor) return true;
  if (card.type == UnoCardType.number && top.type == UnoCardType.number && card.number == top.number) return true;
  if (card.type != UnoCardType.number && card.type == top.type) return true;
  return false;
}

/// Re-validated fully here, not just trusted because a sending UI disabled
/// a card — the same "only the real mover acts" discipline every other
/// engine in this expansion holds itself to, for the same real reason
/// (this transport has no auth beyond same-LAN presence).
PlayResult playCard(UnoSession s, String seatId, UnoCard card, {UnoColor? chosenColor, required Random rand}) {
  if (s.winner != null) return PlayResult(session: s, accepted: false, reason: 'game_over');
  if (seatId != s.turnSeatId) return PlayResult(session: s, accepted: false, reason: 'not_your_turn');
  final hand = s.hands[seatId];
  if (hand == null) return PlayResult(session: s, accepted: false, reason: 'unknown_seat');
  if (!hand.contains(card)) return PlayResult(session: s, accepted: false, reason: 'not_in_hand');
  if (!_isLegalPlay(card, s)) return PlayResult(session: s, accepted: false, reason: 'illegal_play');
  final isWild = card.type == UnoCardType.wild || card.type == UnoCardType.wildDrawFour;
  if (isWild && chosenColor == null) return PlayResult(session: s, accepted: false, reason: 'color_required');

  final newHand = [...hand]..remove(card);
  final newHands = {...s.hands, seatId: newHand};
  final newColor = isWild ? chosenColor! : _colorOf(card);
  var next = UnoSession(seatOrder: s.seatOrder, drawPile: s.drawPile, discardPile: [...s.discardPile, card],
    hands: newHands, turnSeatId: seatId, clockwise: s.clockwise, currentColor: newColor, winner: null);

  if (newHand.isEmpty) {
    return PlayResult(session: UnoSession(seatOrder: next.seatOrder, drawPile: next.drawPile, discardPile: next.discardPile,
      hands: next.hands, turnSeatId: next.turnSeatId, clockwise: next.clockwise, currentColor: next.currentColor, winner: seatId), accepted: true);
  }

  var afterClockwise = next.clockwise;
  String afterTurn;

  if (card.type == UnoCardType.skip) {
    afterTurn = _seatAfter(s.seatOrder, _seatAfter(s.seatOrder, seatId, s.clockwise), s.clockwise);
  } else if (card.type == UnoCardType.reverse) {
    if (s.seatOrder.length <= 2) {
      // Real official-rule special case — see this file's own header.
      afterTurn = _seatAfter(s.seatOrder, _seatAfter(s.seatOrder, seatId, s.clockwise), s.clockwise);
    } else {
      afterClockwise = !s.clockwise;
      afterTurn = _seatAfter(s.seatOrder, seatId, afterClockwise);
    }
  } else if (card.type == UnoCardType.drawTwo || card.type == UnoCardType.wildDrawFour) {
    final drawCount = card.type == UnoCardType.drawTwo ? 2 : 4;
    final victim = _seatAfter(s.seatOrder, seatId, s.clockwise);
    final drawn = <UnoCard>[];
    var draining = next;
    for (var i = 0; i < drawCount; i++) {
      draining = _ensureDrawable(draining, rand);
      if (draining.drawPile.isEmpty) break;
      drawn.add(draining.drawPile.first);
      draining = UnoSession(seatOrder: draining.seatOrder, drawPile: draining.drawPile.sublist(1), discardPile: draining.discardPile,
        hands: draining.hands, turnSeatId: draining.turnSeatId, clockwise: draining.clockwise, currentColor: draining.currentColor, winner: draining.winner);
    }
    final victimHand = [...draining.hands[victim]!, ...drawn];
    next = UnoSession(seatOrder: draining.seatOrder, drawPile: draining.drawPile, discardPile: draining.discardPile,
      hands: {...draining.hands, victim: victimHand}, turnSeatId: seatId, clockwise: draining.clockwise, currentColor: draining.currentColor, winner: null);
    // The victim also loses their turn after being forced to draw — real
    // Uno rule, at any table size: turn lands on the seat after the
    // victim (2 seats: that's the player who played the card).
    afterTurn = _seatAfter(s.seatOrder, victim, next.clockwise);
    afterClockwise = next.clockwise;
  } else {
    afterTurn = _seatAfter(s.seatOrder, seatId, s.clockwise);
  }

  return PlayResult(session: UnoSession(seatOrder: next.seatOrder, drawPile: next.drawPile, discardPile: next.discardPile,
    hands: next.hands, turnSeatId: afterTurn, clockwise: afterClockwise, currentColor: next.currentColor, winner: null), accepted: true);
}

class DrawResult {
  const DrawResult({required this.session, required this.accepted, this.reason});
  final UnoSession session;
  final bool accepted;
  final String? reason;
}

/// Drawing always ends the turn in this pass — real Uno lets a player play
/// the card they just drew if it's legal; deferred here as a real,
/// disclosed simplification alongside this file's other ones.
DrawResult drawCard(UnoSession s, String seatId, Random rand) {
  if (s.winner != null) return DrawResult(session: s, accepted: false, reason: 'game_over');
  if (seatId != s.turnSeatId) return DrawResult(session: s, accepted: false, reason: 'not_your_turn');
  final ready = _ensureDrawable(s, rand);
  if (ready.drawPile.isEmpty) return DrawResult(session: ready, accepted: false, reason: 'no_cards_left');
  final card = ready.drawPile.first;
  final newHand = [...ready.hands[seatId]!, card];
  final next = UnoSession(seatOrder: ready.seatOrder, drawPile: ready.drawPile.sublist(1), discardPile: ready.discardPile,
    hands: {...ready.hands, seatId: newHand}, turnSeatId: _seatAfter(ready.seatOrder, seatId, ready.clockwise),
    clockwise: ready.clockwise, currentColor: ready.currentColor, winner: null);
  return DrawResult(session: next, accepted: true);
}

/// Exposed so uno_deck.dart's shuffle isn't duplicated here — same
/// Fisher-Yates mechanics, reused directly (see this file's and
/// uno_deck.dart's own headers on reusing war_deck.dart's algorithm).
List<T> shuffledCopyOf<T>(List<T> items, Random rand) {
  final list = List<T>.from(items);
  for (var i = list.length - 1; i > 0; i--) {
    final j = rand.nextInt(i + 1);
    final tmp = list[i];
    list[i] = list[j];
    list[j] = tmp;
  }
  return list;
}
