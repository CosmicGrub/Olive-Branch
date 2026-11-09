// No longer UNVERIFIED — verified by CI (client/test/uno_play_test.dart, a two-device test over the in-memory transport).
// OLIVE BRANCH — Uno for two devices, as a [PlayGame] (play_game.dart). The deck, the rules and the bots stay in
// uno_session.dart / uno_bot.dart / uno_deck.dart; the table with 1-3 computer seats stays on one device in
// game_uno.dart. This file is the two-device conversation, moved here from the screen so it can be tested.
//
// DECK AUTHORITY (unchanged, see game_uno.dart's header): the dealing device (Side.b) holds the ONE full
// [UnoSession]; the other device holds only a redacted view, its own hand and the opponent's hand COUNT. The state sent
// across is built by [stateFor] and the controller refuses to send one that carries `hands`, `drawPile` or a seed
// (spec.hiddenKeys + alwaysHiddenKeys; checked in the registry sweep test).
//
// WHAT THE CONTROLLER NOW GUARANTEES (the report's Uno defects): the old code fired several `unawaited` full-state
// POSTs in a row with no sequence number, so a late packet could overwrite a newer one; the envelope numbers every state
// and a stale one is dropped. A peer's request is always answered with the state (the stranded-on-"Sending" bug)
// by the controller, not by a remark in a comment. And the dealer's game survives the OS killing the app: see
// [unoSessionToJson] / [unoSessionFromJson], validated hard because a save is read back after a crash.
//
// P2: the wire and the save carry the cards, the turn and the colour. The save never carries a winner (a finished game is
// cleared, not kept), and nothing here is a score.
import 'dart:math';

import 'play_game.dart';
import 'game_logic.dart' show localPlayMinAge;
import 'uno_deck.dart';
import 'uno_session.dart';

String encodeUnoColor(UnoColor c) => switch (c) {
      UnoColor.red => 'red', UnoColor.yellow => 'yellow', UnoColor.green => 'green', UnoColor.blue => 'blue',
    };
UnoColor? decodeUnoColor(Object? v) => switch (v) {
      'red' => UnoColor.red, 'yellow' => UnoColor.yellow, 'green' => UnoColor.green, 'blue' => UnoColor.blue,
      _ => null,
    };

List<UnoCard>? _cards(Object? raw) {
  if (raw is! List) return null;
  final out = <UnoCard>[];
  for (final c in raw) {
    final card = UnoCard.fromCode(c is String ? c : null);
    if (card == null) return null;
    out.add(card);
  }
  return out;
}

/// A game in progress as plain JSON: every pile, every hand, whose turn it is. NO winner (a finished game is never saved).
Map<String, dynamic> unoSessionToJson(UnoSession s) => <String, dynamic>{
      'seats': s.seatOrder,
      'draw': [for (final c in s.drawPile) c.code],
      'discard': [for (final c in s.discardPile) c.code],
      'hands': {for (final e in s.hands.entries) e.key: [for (final c in e.value) c.code]},
      'turn': s.turnSeatId,
      'clockwise': s.clockwise,
      'color': encodeUnoColor(s.currentColor),
      if (s.unoVulnerableSeatId != null) 'vulnerable': s.unoVulnerableSeatId,
      if (s.pendingWildDrawFour != null)
        'pendingWd4': {
          'player': s.pendingWildDrawFour!.playerSeatId,
          'victim': s.pendingWildDrawFour!.victimSeatId,
          'before': [for (final c in s.pendingWildDrawFour!.handBeforePlay) c.code],
          'color': encodeUnoColor(s.pendingWildDrawFour!.colorBeforePlay),
        },
    };

/// Rebuilds a game from [unoSessionToJson]. Null (and nothing else happens) for anything that is not a whole, consistent
/// game: wrong seat count, a card that does not parse, a deck that does not add up to 108 cards, a turn that is not a seat.
UnoSession? unoSessionFromJson(Map<String, dynamic> j) {
  final seatsRaw = j['seats'];
  if (seatsRaw is! List || seatsRaw.length < 2 || seatsRaw.length > 4 || seatsRaw.any((s) => s is! String || s.isEmpty || s.length > 8)) {
    return null;
  }
  final seats = seatsRaw.cast<String>();
  if (seats.toSet().length != seats.length) return null;
  final draw = _cards(j['draw']), discard = _cards(j['discard']);
  final handsRaw = j['hands'];
  if (draw == null || discard == null || discard.isEmpty || handsRaw is! Map || handsRaw.length != seats.length) return null;
  final hands = <String, List<UnoCard>>{};
  for (final seat in seats) {
    final h = _cards(handsRaw[seat]);
    if (h == null) return null;
    hands[seat] = h;
  }
  final turn = j['turn'];
  final color = decodeUnoColor(j['color']);
  final clockwise = j['clockwise'];
  if (turn is! String || !seats.contains(turn) || color == null || clockwise is! bool) return null;
  final vulnerable = j['vulnerable'];
  if (vulnerable != null && (vulnerable is! String || !seats.contains(vulnerable))) return null;
  PendingWildDrawFour? pending;
  final pw = j['pendingWd4'];
  if (pw != null) {
    if (pw is! Map) return null;
    final before = _cards(pw['before']), pcolor = decodeUnoColor(pw['color']);
    final player = pw['player'], victim = pw['victim'];
    if (before == null || pcolor == null || player is! String || victim is! String || !seats.contains(player) || !seats.contains(victim)) return null;
    pending = PendingWildDrawFour(playerSeatId: player, victimSeatId: victim, handBeforePlay: before, colorBeforePlay: pcolor);
  }
  // A real game has exactly the 108 cards of the deck, wherever they are. A short or padded one is damaged.
  final total = draw.length + discard.length + hands.values.fold<int>(0, (n, h) => n + h.length);
  if (total != standardUnoDeck().length) return null;
  // And exactly the right number of each card.
  final all = [...draw, ...discard, for (final h in hands.values) ...h];
  final want = <String, int>{};
  for (final c in standardUnoDeck()) {
    want[c.code] = (want[c.code] ?? 0) + 1;
  }
  for (final c in all) {
    want[c.code] = (want[c.code] ?? 0) - 1;
  }
  if (want.values.any((n) => n != 0)) return null;
  return UnoSession(
    seatOrder: seats, drawPile: draw, discardPile: discard, hands: hands, turnSeatId: turn, clockwise: clockwise,
    currentColor: color, winner: null, unoVulnerableSeatId: vulnerable as String?, pendingWildDrawFour: pending,
  );
}

/// What the non-dealing device knows: its own hand and the table, never the other hand or the pile.
class UnoPeerView {
  const UnoPeerView({
    required this.myHand, required this.discardTop, required this.discardTrail, required this.currentColor,
    required this.turn, required this.opponentHandCount, required this.winner, required this.unoVulnerableSeatId,
    required this.pendingWildDrawFour,
  });
  final List<UnoCard> myHand;
  final UnoCard discardTop;
  final List<UnoCard> discardTrail;
  final UnoColor currentColor;
  final String turn;
  final int opponentHandCount;
  final String? winner;
  final String? unoVulnerableSeatId;
  final bool pendingWildDrawFour;
}

/// The last up-to-2 previous discards, purely decorative.
List<UnoCard> unoTrailFor(List<UnoCard> discardPile) {
  final withoutTop = discardPile.length > 1 ? discardPile.sublist(0, discardPile.length - 1) : const <UnoCard>[];
  final start = withoutTop.length > 2 ? withoutTop.length - 2 : 0;
  return withoutTop.sublist(start);
}

class UnoPlayGame extends PlayGame {
  UnoPlayGame(super.ctx);

  /// The dealing device only.
  UnoSession? session;

  /// The other device only.
  UnoPeerView? view;

  /// The other device has sent a request and is waiting for the table to come back.
  bool awaiting = false;

  Random get _rand => ctx.rng;
  String get mySeat => ctx.localSeatId;
  String get peerSeat => ctx.peerSeatId;

  @override
  bool get started => ctx.isAuthority ? session != null : view != null;
  @override
  bool get finished => ctx.isAuthority ? session?.winner != null : view?.winner != null;

  // ------------------------------------------------- dealing device actions --
  void deal() {
    if (!ctx.isAuthority) return;
    session = dealUno(ctx.seatIds, _rand);
    notifyListeners();
    link?.broadcastState();
  }

  /// Take a new table (from the screen's own rules code), save it and send the other device its view.
  void commit(UnoSession next) {
    session = next;
    notifyListeners();
    link?.broadcastState();
  }

  bool playAsAuthority(UnoCard card, UnoColor? color) {
    final s = session;
    if (s == null) return false;
    final r = playCard(s, mySeat, card, chosenColor: color, rand: _rand);
    if (!r.accepted) return false;
    commit(r.session);
    return true;
  }

  bool drawAsAuthority() {
    final s = session;
    if (s == null) return false;
    final r = drawCard(s, mySeat, _rand);
    if (!r.accepted) return false;
    commit(r.session);
    return true;
  }

  void declareAsAuthority() {
    final s = session;
    if (s == null) return;
    commit(declareUno(s, mySeat));
  }

  bool catchAsAuthority() {
    final s = session;
    if (s == null) return false;
    final r = catchMissedUno(s, mySeat, _rand);
    if (!r.accepted) return false;
    commit(r.session);
    return true;
  }

  bool acceptWd4AsAuthority() {
    final s = session;
    if (s == null) return false;
    final r = acceptWildDrawFour(s, mySeat, _rand);
    if (!r.accepted) return false;
    commit(r.session);
    return true;
  }

  bool challengeWd4AsAuthority() {
    final s = session;
    if (s == null) return false;
    final r = challengeWildDrawFour(s, mySeat, _rand);
    if (!r.accepted) return false;
    commit(r.session);
    return true;
  }

  // ------------------------------------------------- other device requests --
  /// Ask the dealing device to do something. The table changes only when its answer comes back.
  void request({UnoCard? card, UnoColor? color, bool draw = false, String? special}) {
    awaiting = true;
    notifyListeners();
    link?.sendMove(<String, dynamic>{
      'action': special ?? (draw ? 'draw' : 'playCard'),
      if (card != null) 'cardCode': card.code,
      if (color != null) 'chosenColor': encodeUnoColor(color),
    });
  }

  @override
  PlayMoveOutcome onMove(String senderSeat, Map<String, dynamic> payload) {
    final s = session;
    if (!ctx.isAuthority || s == null) return PlayMoveOutcome.ignored;
    // The acting seat is the one the transport says sent this, never a name inside the message.
    if (senderSeat == mySeat || !s.seatOrder.contains(senderSeat)) return PlayMoveOutcome.refused;
    final action = payload['action'];

    // declareUno / catchMissedUno / the Wild Draw Four answers are deliberately OUT-OF-TURN actions
    // (see uno_session.dart's header): gating them on the turn would refuse exactly what they are for.
    switch (action) {
      case 'declareUno':
        session = declareUno(s, senderSeat);
        notifyListeners();
        return PlayMoveOutcome.applied;
      case 'catchUno':
        final r = catchMissedUno(s, senderSeat, _rand);
        if (r.accepted) session = r.session;
        notifyListeners();
        return r.accepted ? PlayMoveOutcome.applied : PlayMoveOutcome.refused;
      case 'acceptWD4':
        final r = acceptWildDrawFour(s, senderSeat, _rand);
        if (r.accepted) session = r.session;
        notifyListeners();
        return r.accepted ? PlayMoveOutcome.applied : PlayMoveOutcome.refused;
      case 'challengeWD4':
        final r = challengeWildDrawFour(s, senderSeat, _rand);
        if (r.accepted) session = r.session;
        notifyListeners();
        return r.accepted ? PlayMoveOutcome.applied : PlayMoveOutcome.refused;
    }
    if (s.turnSeatId != senderSeat) return PlayMoveOutcome.refused;
    UnoSession? next;
    if (action == 'draw') {
      final r = drawCard(s, senderSeat, _rand);
      if (r.accepted) next = r.session;
    } else if (action == 'playCard') {
      final card = UnoCard.fromCode(payload['cardCode'] is String ? payload['cardCode'] as String : null);
      if (card != null) {
        final r = playCard(s, senderSeat, card, chosenColor: decodeUnoColor(payload['chosenColor']), rand: _rand);
        if (r.accepted) next = r.session;
      }
    }
    if (next == null) return PlayMoveOutcome.refused;
    session = next;
    notifyListeners();
    return PlayMoveOutcome.applied;
  }

  // ------------------------------------------------------------------ state --
  @override
  Map<String, dynamic>? stateFor(String seatId) {
    final s = session;
    if (!ctx.isAuthority || s == null || !s.hands.containsKey(seatId)) return null;
    // The other seat's own hand, and only a COUNT of this one. Never `hands`, `drawPile` or a seed.
    return <String, dynamic>{
      'myHandForPeer': [for (final c in s.hands[seatId]!) c.code],
      'opponentHandCount': s.hands[mySeat]!.length,
      'discardTopCardId': s.topDiscard.code,
      'discardTrail': [for (final c in unoTrailFor(s.discardPile)) c.code],
      'currentColor': encodeUnoColor(s.currentColor),
      'mover': s.turnSeatId,
      'winner': s.winner,
      'unoVulnerableSeatId': s.unoVulnerableSeatId,
      'pendingWildDrawFour': s.pendingWildDrawFour != null,
    };
  }

  /// The public view, the same on both devices: the top card, the colour, the turn and how many cards each seat holds.
  @override
  Object? publicDigestInput() {
    final s = session, v = view;
    if (ctx.isAuthority && s != null) {
      return <String, dynamic>{
        'top': s.topDiscard.code, 'color': encodeUnoColor(s.currentColor), 'turn': s.turnSeatId,
        'counts': {for (final e in s.hands.entries) e.key: e.value.length},
        'winner': s.winner ?? '', 'vulnerable': s.unoVulnerableSeatId ?? '', 'wd4': s.pendingWildDrawFour != null,
      };
    }
    if (v != null) {
      return <String, dynamic>{
        'top': v.discardTop.code, 'color': encodeUnoColor(v.currentColor), 'turn': v.turn,
        'counts': {mySeat: v.myHand.length, peerSeat: v.opponentHandCount},
        'winner': v.winner ?? '', 'vulnerable': v.unoVulnerableSeatId ?? '', 'wd4': v.pendingWildDrawFour,
      };
    }
    return null;
  }

  @override
  bool applyState(Map<String, dynamic> payload) {
    if (ctx.isAuthority) return false;
    final hand = _cards(payload['myHandForPeer']);
    final top = UnoCard.fromCode(payload['discardTopCardId'] is String ? payload['discardTopCardId'] as String : null);
    final color = decodeUnoColor(payload['currentColor']);
    final mover = payload['mover'];
    final count = payload['opponentHandCount'];
    if (hand == null || top == null || color == null || mover is! String || count is! num || count < 0 || count > 108) return false;
    final trail = <UnoCard>[];
    final trailRaw = payload['discardTrail'];
    if (trailRaw is List) {
      for (final c in trailRaw) {
        final card = UnoCard.fromCode(c is String ? c : null);
        if (card != null) trail.add(card);
      }
    }
    final winner = payload['winner'], vuln = payload['unoVulnerableSeatId'];
    view = UnoPeerView(
      myHand: hand, discardTop: top, discardTrail: trail, currentColor: color, turn: mover,
      opponentHandCount: count.toInt(), winner: winner is String ? winner : null,
      unoVulnerableSeatId: vuln is String ? vuln : null, pendingWildDrawFour: payload['pendingWildDrawFour'] == true,
    );
    awaiting = false;
    notifyListeners();
    return true;
  }

  // ------------------------------------------------------------ save, rematch --
  @override
  Map<String, dynamic>? snapshot() {
    final s = session;
    if (!ctx.isAuthority || s == null || s.winner != null) return null;
    return unoSessionToJson(s);
  }

  @override
  bool restore(Map<String, dynamic> snapshot) {
    final s = unoSessionFromJson(snapshot);
    if (s == null || !ctx.isAuthority) return false;
    if (s.seatOrder.length != ctx.seatIds.length || !ctx.seatIds.every(s.seatOrder.contains)) return false;
    session = s;
    notifyListeners();
    return true;
  }

  @override
  void startRematch() {
    session = dealUno(ctx.seatIds, _rand);
    notifyListeners();
  }
}

final PlayGameSpec unoSpec = PlayGameSpec(
  id: 'uno', title: 'Uno', minAge: localPlayMinAge['uno']!, minSeats: 2, maxSeats: 4,
  modes: const {PlayMode.pair, PlayMode.vsCpu}, create: (ctx) => UnoPlayGame(ctx),
  hiddenInfo: true, hiddenKeys: const ['hands', 'handBeforePlay', 'pendingWd4'],
  saveable: true,
);
