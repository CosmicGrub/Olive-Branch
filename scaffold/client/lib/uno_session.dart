// OLIVE BRANCH — Uno, the ad-hoc local card game engine. UNVERIFIED (no
// Flutter toolchain in tools/verify.sh's automated pipeline). Network
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
// REAL RULES SCOPE, as of this pass — modeled after a real reference
// (the 2006 Xbox Live Arcade UNO, Carbonated Games): color/number
// matching, Skip, Reverse, Draw Two, Wild, Wild Draw Four, win on an
// empty hand, calling "Uno!" at one card (with a real out-of-turn catch
// penalty for forgetting), and the real Wild Draw Four challenge. Still
// deliberately NOT in this pass, each a real, separate follow-up: the
// four genuinely-optional house rules (stacking, jump-in, 7-0 rule, and
// this challenge is NOT one of them — official Uno rules include the
// Wild Draw Four challenge as a base rule, not a house-rule toggle, and
// this file now implements it as one), and team-victory framing (this
// file only ever reports the seatId that emptied its hand as
// [UnoSession.winner] — recognizing that as a whole team's win, for a
// 2v2 table, is the caller's job via game_seat.dart's own
// SeatRoster.byId(winner).teamId, not this file's). A real, deliberate
// DIVERGENCE from that reference, not an omission: its own round/game
// scoring table (racing to a target point total across rounds) is
// exactly the pattern MASTERFILE P2 permanently bans ("no scores,
// streaks, or ranks shown to the child") — this file reports only
// [UnoSession.winner], never a point tally, and nothing upstream of it
// should ever compute one for a child-visible surface.
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
// - Draw Two: the victim is always the very next seat in the CURRENT
//   direction (not "the other side"); after they draw, the victim's own
//   turn is skipped too — turn lands on the seat after the victim. With
//   exactly 2 seats, the seat after the victim IS the player who played
//   the card, matching this file's own prior 2-seat-only behavior
//   exactly. Draw Two auto-resolves immediately, same as before this
//   pass — there is no challenge for Draw Two in real Uno rules, only
//   Wild Draw Four.
// - Wild Draw Four is NO LONGER auto-resolved by [playCard] alone. Real
//   official rule: the victim may challenge whether the player genuinely
//   had no legal, non-wild, current-color card and was forced to play
//   it. Playing a Wild Draw Four now sets [UnoSession.
//   pendingWildDrawFour] (turn moves to the victim, but their only real
//   actions are [acceptWildDrawFour]/[challengeWildDrawFour] — a normal
//   [playCard]/[drawCard] is refused with reason 'pending_wild_draw_four'
//   while it's set). Accepting draws 4 and skips the victim's turn,
//   identical to the pre-challenge behavior. Challenging checks the
//   real snapshot taken at play time ([PendingWildDrawFour.
//   handBeforePlay]/[colorBeforePlay]): if the player DID have a legal
//   alternative, the challenge succeeds — THEY draw 4 instead, and it
//   becomes the victim's own real (un-skipped) turn; if the play was
//   genuinely forced, the challenge fails — the victim draws 4+2=6 and
//   is still skipped, same as accepting but worse.
//
// CALLING "UNO!" is a real, separate mechanic from winning: the instant
// any seat's hand drops to exactly one card, that seat becomes
// vulnerable ([UnoSession.unoVulnerableSeatId]) until it calls
// [declareUno] for itself. Any OTHER seat may [catchMissedUno] it while
// vulnerable, for a real 2-card penalty — a genuine, out-of-turn action,
// not gated by whose turn it currently is (matches the real tabletop
// rule: anyone can call it out the instant they notice). Real, disclosed
// simplification for 3-4 seat tables: the official rule closes the catch
// window only once "the next player" specifically has taken their turn;
// this implementation closes it the instant ANY other seat completes a
// real play or draw, a simple, honest approximation rather than the
// stricter per-seat reading — see [_settleUnoVulnerability]'s own doc
// comment.
library;

import 'dart:math';
import 'uno_deck.dart';

/// The real snapshot taken the instant a Wild Draw Four is played — what
/// the player's hand looked like immediately after removing the card
/// (i.e. every OTHER card they held) and what color was actually in play
/// at that moment, before their own color choice took effect. This is
/// the one real fact [challengeWildDrawFour] needs and nothing else —
/// deliberately not the mover's identity-revealing full hand history,
/// just the one snapshot the real rule is decided from.
class PendingWildDrawFour {
  const PendingWildDrawFour({
    required this.playerSeatId, required this.victimSeatId,
    required this.handBeforePlay, required this.colorBeforePlay,
  });
  final String playerSeatId;
  final String victimSeatId;
  final List<UnoCard> handBeforePlay;
  final UnoColor colorBeforePlay;
}

class UnoSession {
  const UnoSession({
    required this.seatOrder, required this.drawPile, required this.discardPile,
    required this.hands, required this.turnSeatId, required this.clockwise,
    required this.currentColor, required this.winner,
    this.unoVulnerableSeatId, this.pendingWildDrawFour,
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
  /// See this file's own header, "CALLING 'UNO!'". Null when nobody is
  /// currently vulnerable.
  final String? unoVulnerableSeatId;
  /// See this file's own header, "Wild Draw Four is NO LONGER
  /// auto-resolved". Null except in the real window between a Wild Draw
  /// Four landing and its victim responding.
  final PendingWildDrawFour? pendingWildDrawFour;

  UnoCard get topDiscard => discardPile.last;

  /// The one real reconstruction path for the whole file — every other
  /// function below builds its result through this rather than a raw
  /// positional constructor call, so a field neither function explicitly
  /// touches is carried forward by default instead of silently reset to
  /// null. That safety net is why this was added in this exact pass: two
  /// new nullable fields land here, and a raw constructor call at any of
  /// this file's many intermediate reconstruction sites would have
  /// silently dropped whichever of them it didn't happen to mention.
  UnoSession copyWith({
    List<UnoCard>? drawPile, List<UnoCard>? discardPile, Map<String, List<UnoCard>>? hands,
    String? turnSeatId, bool? clockwise, UnoColor? currentColor,
    String? winner, bool clearWinner = false,
    String? unoVulnerableSeatId, bool clearUnoVulnerable = false,
    PendingWildDrawFour? pendingWildDrawFour, bool clearPendingWildDrawFour = false,
  }) => UnoSession(
    seatOrder: seatOrder, // fixed for the whole game — never reconstructed with a different one
    drawPile: drawPile ?? this.drawPile,
    discardPile: discardPile ?? this.discardPile,
    hands: hands ?? this.hands,
    turnSeatId: turnSeatId ?? this.turnSeatId,
    clockwise: clockwise ?? this.clockwise,
    currentColor: currentColor ?? this.currentColor,
    winner: clearWinner ? null : (winner ?? this.winner),
    unoVulnerableSeatId: clearUnoVulnerable ? null : (unoVulnerableSeatId ?? this.unoVulnerableSeatId),
    pendingWildDrawFour: clearPendingWildDrawFour ? null : (pendingWildDrawFour ?? this.pendingWildDrawFour),
  );
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
  return s.copyWith(drawPile: reshuffled, discardPile: [top]);
}

/// Draws [n] real cards (reshuffling mid-draw if needed) onto [seatId]'s
/// hand — the one shared primitive [playCard]'s Draw Two branch,
/// [acceptWildDrawFour], and [challengeWildDrawFour] (both of its own
/// outcomes) all reuse, rather than three drifting copies of the same
/// reshuffle-aware draw loop. May draw fewer than [n] if both piles
/// genuinely run out — callers of the public API this feeds never
/// surface that as an error; a real, honest partial draw is preferable
/// to a stalled game.
UnoSession _drawNCardsForSeat(UnoSession s, String seatId, int n, Random rand) {
  var draining = s;
  final drawn = <UnoCard>[];
  for (var i = 0; i < n; i++) {
    draining = _ensureDrawable(draining, rand);
    if (draining.drawPile.isEmpty) break;
    drawn.add(draining.drawPile.first);
    draining = draining.copyWith(drawPile: draining.drawPile.sublist(1));
  }
  if (drawn.isEmpty) return draining;
  final newHand = [...draining.hands[seatId]!, ...drawn];
  return draining.copyWith(hands: {...draining.hands, seatId: newHand});
}

/// The one place [UnoSession.unoVulnerableSeatId] is ever computed, so
/// its real rule lives in exactly one function. Called as the final step
/// of every action that can move the game forward
/// ([playCard]/[drawCard]/[acceptWildDrawFour]/both outcomes of
/// [challengeWildDrawFour]) — [declareUno]/[catchMissedUno] set it
/// directly instead, since resolving vulnerability IS the entire point
/// of those two, not a side effect of something else.
///
/// Real, disclosed simplification (see this file's own header): the
/// official rule closes the catch window only once the SPECIFIC next
/// player has taken their turn. This closes it the instant ANY other
/// seat completes a real action — simpler to reason about and test at a
/// 3-4 seat table, and still strictly enforces "you must call it before
/// the game moves on," just with a slightly wider (never narrower)
/// window than the strictest reading. [actingSeatId] is whichever seat
/// just genuinely acted (the mover of a play/draw, or the seat whose
/// forced draw just resolved via a challenge) — never the seat merely
/// affected by someone else's action.
UnoSession _settleUnoVulnerability(UnoSession next, String actingSeatId, {bool declareNow = false}) {
  String? vulnerable = next.unoVulnerableSeatId;
  if (vulnerable != null && vulnerable != actingSeatId) vulnerable = null;
  final myHandLen = next.hands[actingSeatId]?.length ?? 0;
  if (myHandLen == 1 && !declareNow) {
    vulnerable = actingSeatId;
  } else if (actingSeatId == vulnerable && myHandLen != 1) {
    vulnerable = null; // e.g. a Draw Two/Wild Draw Four penalty grew the hand back past one card
  }
  return next.copyWith(unoVulnerableSeatId: vulnerable, clearUnoVulnerable: vulnerable == null);
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
///
/// [declareUnoNow] — a real, optional combined action: playing the
/// second-to-last card AND calling "Uno!" for it in the same tap, for a
/// UI that offers that as one button. Omitted (the default), the seat
/// becomes vulnerable exactly as if it had said nothing, matching a
/// player who plays silently.
PlayResult playCard(UnoSession s, String seatId, UnoCard card,
    {UnoColor? chosenColor, required Random rand, bool declareUnoNow = false}) {
  if (s.winner != null) return PlayResult(session: s, accepted: false, reason: 'game_over');
  if (s.pendingWildDrawFour != null) {
    return PlayResult(session: s, accepted: false, reason: 'pending_wild_draw_four');
  }
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
  final played = s.copyWith(discardPile: [...s.discardPile, card], hands: newHands, currentColor: newColor);

  if (newHand.isEmpty) {
    final result = played.copyWith(turnSeatId: seatId, winner: seatId);
    return PlayResult(session: _settleUnoVulnerability(result, seatId, declareNow: declareUnoNow), accepted: true);
  }

  if (card.type == UnoCardType.wildDrawFour) {
    // The real official challenge rule — see this file's own header. The
    // snapshot is exactly newHand/s.currentColor: what the player held
    // AFTER removing this card, and what color was genuinely in play
    // before their own choice took effect.
    final victim = _seatAfter(s.seatOrder, seatId, s.clockwise);
    final pending = PendingWildDrawFour(
      playerSeatId: seatId, victimSeatId: victim, handBeforePlay: newHand, colorBeforePlay: s.currentColor);
    final result = played.copyWith(turnSeatId: victim, pendingWildDrawFour: pending);
    return PlayResult(session: _settleUnoVulnerability(result, seatId, declareNow: declareUnoNow), accepted: true);
  }

  bool afterClockwise = played.clockwise;
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
  } else if (card.type == UnoCardType.drawTwo) {
    final victim = _seatAfter(s.seatOrder, seatId, s.clockwise);
    final drained = _drawNCardsForSeat(played, victim, 2, rand);
    // The victim also loses their turn after being forced to draw — real
    // Uno rule, at any table size: turn lands on the seat after the
    // victim (2 seats: that's the player who played the card).
    afterTurn = _seatAfter(s.seatOrder, victim, drained.clockwise);
    final result = drained.copyWith(turnSeatId: afterTurn, clockwise: afterClockwise);
    return PlayResult(session: _settleUnoVulnerability(result, seatId, declareNow: declareUnoNow), accepted: true);
  } else {
    afterTurn = _seatAfter(s.seatOrder, seatId, s.clockwise);
  }

  final result = played.copyWith(turnSeatId: afterTurn, clockwise: afterClockwise);
  return PlayResult(session: _settleUnoVulnerability(result, seatId, declareNow: declareUnoNow), accepted: true);
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
  if (s.pendingWildDrawFour != null) {
    return DrawResult(session: s, accepted: false, reason: 'pending_wild_draw_four');
  }
  if (seatId != s.turnSeatId) return DrawResult(session: s, accepted: false, reason: 'not_your_turn');
  final ready = _ensureDrawable(s, rand);
  if (ready.drawPile.isEmpty) return DrawResult(session: ready, accepted: false, reason: 'no_cards_left');
  final card = ready.drawPile.first;
  final newHand = [...ready.hands[seatId]!, card];
  final next = ready.copyWith(drawPile: ready.drawPile.sublist(1), hands: {...ready.hands, seatId: newHand},
    turnSeatId: _seatAfter(ready.seatOrder, seatId, ready.clockwise));
  return DrawResult(session: _settleUnoVulnerability(next, seatId), accepted: true);
}

/// The victim accepts a pending Wild Draw Four without challenging —
/// draws 4, turn skips to the seat after them. Identical outcome to how
/// [playCard] used to resolve a Wild Draw Four automatically before this
/// pass added the real challenge option.
DrawResult acceptWildDrawFour(UnoSession s, String victimSeatId, Random rand) {
  final pending = s.pendingWildDrawFour;
  if (pending == null) return DrawResult(session: s, accepted: false, reason: 'no_pending_challenge');
  if (victimSeatId != pending.victimSeatId) return DrawResult(session: s, accepted: false, reason: 'not_the_victim');
  final drained = _drawNCardsForSeat(s, victimSeatId, 4, rand);
  final afterTurn = _seatAfter(s.seatOrder, victimSeatId, drained.clockwise);
  final next = drained.copyWith(turnSeatId: afterTurn, clearPendingWildDrawFour: true);
  return DrawResult(session: _settleUnoVulnerability(next, victimSeatId), accepted: true);
}

class ChallengeResult {
  const ChallengeResult({required this.session, required this.accepted, required this.challengeSucceeded, this.reason});
  final UnoSession session;
  final bool accepted;
  /// Only meaningful when [accepted] is true — whether the challenge
  /// actually proved the play illegal (the player DID have a legal
  /// alternative and should have played it instead).
  final bool challengeSucceeded;
  final String? reason;
}

/// The real Wild Draw Four challenge — see this file's own header for
/// the full account of both outcomes. [challengerSeatId] must be the
/// real victim named in [UnoSession.pendingWildDrawFour] (challenging on
/// someone else's behalf is not a real tabletop action).
ChallengeResult challengeWildDrawFour(UnoSession s, String challengerSeatId, Random rand) {
  final pending = s.pendingWildDrawFour;
  if (pending == null) {
    return ChallengeResult(session: s, accepted: false, challengeSucceeded: false, reason: 'no_pending_challenge');
  }
  if (challengerSeatId != pending.victimSeatId) {
    return ChallengeResult(session: s, accepted: false, challengeSucceeded: false, reason: 'not_the_victim');
  }
  final hadLegalAlternative = pending.handBeforePlay.any((c) =>
    c.type != UnoCardType.wild && c.type != UnoCardType.wildDrawFour && c.color == pending.colorBeforePlay);

  if (hadLegalAlternative) {
    // Challenge SUCCEEDS: the original player draws 4 instead, and it
    // becomes the victim's own real, un-skipped turn — they were never
    // legitimately forced to lose it.
    final drained = _drawNCardsForSeat(s, pending.playerSeatId, 4, rand);
    final next = drained.copyWith(turnSeatId: challengerSeatId, clearPendingWildDrawFour: true);
    return ChallengeResult(
      session: _settleUnoVulnerability(next, pending.playerSeatId), accepted: true, challengeSucceeded: true);
  } else {
    // Challenge FAILS: the play was genuinely forced. The victim draws
    // the original 4 plus a real 2-card penalty (6 total) and is still
    // skipped, same as accepting but worse — the real deterrent against
    // challenging blind.
    final drained = _drawNCardsForSeat(s, challengerSeatId, 6, rand);
    final afterTurn = _seatAfter(s.seatOrder, challengerSeatId, drained.clockwise);
    final next = drained.copyWith(turnSeatId: afterTurn, clearPendingWildDrawFour: true);
    return ChallengeResult(
      session: _settleUnoVulnerability(next, challengerSeatId), accepted: true, challengeSucceeded: false);
  }
}

/// A real, standalone declaration — marks [seatId] as having called
/// "Uno!" for its current one-card hand. A genuine no-op (never an
/// error) when [seatId] isn't actually vulnerable, so a UI can offer the
/// button speculatively (e.g. right after any play) without needing to
/// separately track eligibility itself.
UnoSession declareUno(UnoSession s, String seatId) {
  if (s.unoVulnerableSeatId != seatId) return s;
  return s.copyWith(clearUnoVulnerable: true);
}

class CatchResult {
  const CatchResult({required this.session, required this.accepted, this.reason});
  final UnoSession session;
  final bool accepted;
  final String? reason;
}

/// [catcherSeatId] catches [UnoSession.unoVulnerableSeatId]'s missed
/// "Uno!" call — a real out-of-turn action, not gated by whose turn it
/// currently is (matches the real tabletop rule: any player can call it
/// out the instant they notice). See this file's own header for the
/// real, disclosed simplification governing exactly how long the window
/// stays open.
CatchResult catchMissedUno(UnoSession s, String catcherSeatId, Random rand) {
  final target = s.unoVulnerableSeatId;
  if (target == null) return CatchResult(session: s, accepted: false, reason: 'nobody_vulnerable');
  if (catcherSeatId == target) return CatchResult(session: s, accepted: false, reason: 'cannot_catch_yourself');
  final drained = _drawNCardsForSeat(s, target, 2, rand);
  return CatchResult(session: drained.copyWith(clearUnoVulnerable: true), accepted: true);
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
