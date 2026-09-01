// OLIVE BRANCH — War, the ad-hoc local card game. Network resilience &
// ad-hoc mode roadmap, Track B Option 2, ad-hoc games expansion. Builds on
// local_pairing.dart (the shared foundation) and war_deck.dart (the deck
// primitive). First of five new local-play activities, deliberately the
// smallest: no CPU seat, no roster, no decisions at all beyond when to
// flip — its whole job is to prove local_pairing.dart works for a SECOND
// game and to give this codebase its first real card-game data model.
//
// P2 (MASTERFILE §2.1) governs the whole screen: no score, no streak, no
// running tally, no "you lost" framing. A finished game closes with a
// plain factual line, the same convention game_tictactoe.dart already
// established ("Good game." / a plain fact, never a verdict).
//
// A real design problem this file had to solve, not hand-waved: this
// transport (local_session.dart) has no shared/secret state — each device
// is authoritative only for its own pile, the same way local_play_screen
// .dart's two devices each keep their own independently-shuffled Twenty
// Questions deck. That works fine when the two piles don't need to add up
// to anything. War's two 26-card piles DO need to stay exact complements
// of one real 52-card deck at every moment, including through a multi-step
// "war" (a tie, resolved by each side wagering a card face-down and
// flipping a fresh comparator) — so every card that ever leaves a device's
// hand, wagered or not, is sent over the wire with its real identity, not
// just a count. "Face-down" is a UI/rendering choice (the receiving
// screen simply doesn't show that card's face), never a data-hiding one —
// there is no secret to keep between two devices on the same trusted local
// network in the first place (local_session.dart's own "no auth beyond
// you're on the LAN" posture), and hiding the wagered card's identity from
// the wire would make it impossible for the winner's device to correctly
// know what it just won.
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'form_factors.dart' as ff show Posture, Viewport, postureFor;
import 'live_games.dart' show Side, auditLiveView;
import 'local_pairing.dart';
import 'war_deck.dart';

/// Same real per-device scale this app's other games now use, keyed off
/// form_factors.dart's own postures rather than a bespoke breakpoint —
/// see game_uno.dart's own _cardScaleFor for the identical reasoning.
double _cardScaleFor(ff.Posture posture) => switch (posture) {
  ff.Posture.foldCover || ff.Posture.phone || ff.Posture.tabletSmall => 1.0,
  ff.Posture.foldMain || ff.Posture.foldTabletop || ff.Posture.tabletMedium => 1.08,
  ff.Posture.tabletLarge => 1.16,
  ff.Posture.desktop || ff.Posture.dex => 1.22,
};

// ==================================================================
// ==== engine — pure logic, no Flutter import ====
// ==================================================================

enum WarPhase { playing, won, lost, drawnOut }

/// A real, correctness-sensitive constraint: War as physically played can
/// run a very long time (a shuffled deck can cycle for hundreds of rounds
/// before someone runs out). A fixed cap ending in a warm, honest "let's
/// call it a tie" is the same discipline nextRound()'s own reshuffle-
/// rather-than-end choice reflects elsewhere in this codebase: never leave
/// a child staring at a game that structurally cannot end.
const int warRoundCap = 200;

/// This device's own local view of the game. Only [myPile] is ever
/// authoritative here — the opponent's pile size is inferred for display
/// (52 - myPile.length, when nothing is mid-exchange) rather than tracked
/// directly, since this device never needs to validate it.
class WarState {
  const WarState({
    required this.myPile,
    required this.roundNumber,
    required this.pot,
    required this.myPending,
    required this.theirPending,
    required this.phase,
    required this.lastRoundNote,
  });

  final List<PlayingCard> myPile;
  final int roundNumber;

  /// Every card either side has played in the CURRENT unresolved exchange,
  /// accumulating across war continuations — whoever wins this exchange
  /// takes the entire pot, which is what makes a multi-step war correct:
  /// nothing here is ever lost or double-counted.
  final List<PlayingCard> pot;

  /// My own play(s) for the current step, once I've flipped but before the
  /// opponent's matching play has arrived (or vice versa for [theirPending]).
  final List<PlayingCard>? myPending;
  final List<PlayingCard>? theirPending;

  final WarPhase phase;

  /// Brief, real-time UI text for what just happened ("It's a tie! War —
  /// flip again.") — never persisted, never a running record of outcomes.
  final String? lastRoundNote;
}

/// Shuffles one real 52-card deck and splits it into two 26-card halves.
/// Called once, by whichever device deals (see game_war.dart's own fixed
/// "Side.b deals" convention, matching Twenty Questions' existing
/// Side.b-leads pattern — a deterministic rule avoids two devices racing
/// to deal competing decks).
({List<PlayingCard> forMe, List<PlayingCard> forPeer}) dealWar(Random rand) {
  final deck = shuffledCopy(standardDeck(), rand);
  return (forMe: deck.sublist(0, 26), forPeer: deck.sublist(26));
}

WarState newWarFromDeal(List<PlayingCard> myHalf) => WarState(
  myPile: myHalf, roundNumber: 1, pot: const [],
  myPending: null, theirPending: null, phase: WarPhase.playing, lastRoundNote: null,
);

/// I flip my own next card(s): one card for a fresh round, or a
/// [wager, comparator] pair to continue an active war — a deliberate
/// simplification from classic play (which often wagers three face-down
/// cards) so a war resolves in fewer taps, more appropriate for a young
/// child. Down to my last card mid-war, I play just that one card as an
/// all-in comparator rather than being blocked for want of a wager.
/// Returns both the new state AND exactly what I played, so the caller can
/// send that real play over the wire — never re-derive it separately,
/// which would risk the sent cards drifting from the ones actually removed
/// from my pile.
({WarState state, List<PlayingCard> played}) playMyNext(WarState s) {
  if (s.phase != WarPhase.playing || s.myPending != null) return (state: s, played: const []);
  if (s.myPile.isEmpty) {
    return (
      state: WarState(myPile: s.myPile, roundNumber: s.roundNumber, pot: s.pot,
        myPending: null, theirPending: s.theirPending, phase: WarPhase.lost, lastRoundNote: null),
      played: const [],
    );
  }
  final continuingWar = s.pot.isNotEmpty;
  final take = (continuingWar && s.myPile.length >= 2) ? 2 : 1;
  final played = s.myPile.sublist(0, take);
  final rest = s.myPile.sublist(take);
  final withMine = WarState(myPile: rest, roundNumber: s.roundNumber, pot: s.pot,
    myPending: played, theirPending: s.theirPending, phase: s.phase, lastRoundNote: s.lastRoundNote);
  return (state: _resolveIfReady(withMine), played: played);
}

/// The opponent's play arrives over the wire — real card identities, same
/// reasoning as this file's own header on why "face-down" never means
/// "hidden from the other device."
WarState receiveTheirs(WarState s, List<PlayingCard> cards) {
  if (s.theirPending != null || cards.isEmpty || s.phase != WarPhase.playing) return s;
  final withTheirs = WarState(myPile: s.myPile, roundNumber: s.roundNumber, pot: s.pot,
    myPending: s.myPending, theirPending: cards, phase: s.phase, lastRoundNote: s.lastRoundNote);
  return _resolveIfReady(withTheirs);
}

WarState _resolveIfReady(WarState s) {
  final mine = s.myPending;
  final theirs = s.theirPending;
  if (mine == null || theirs == null) return s;

  // Every card either side has played this whole exchange, war
  // continuations included — see [WarState.pot]'s own doc comment.
  final stake = [...s.pot, ...mine, ...theirs];
  final myCard = mine.last;
  final theirCard = theirs.last;

  if (myCard.rank == theirCard.rank) {
    return WarState(myPile: s.myPile, roundNumber: s.roundNumber, pot: stake,
      myPending: null, theirPending: null, phase: WarPhase.playing,
      lastRoundNote: "It's a tie! War — flip again.");
  }

  final nextRound = s.roundNumber + 1;
  if (nextRound > warRoundCap) {
    return WarState(myPile: s.myPile, roundNumber: s.roundNumber, pot: const [],
      myPending: null, theirPending: null, phase: WarPhase.drawnOut, lastRoundNote: null);
  }

  final iWon = myCard.rank > theirCard.rank;
  final newPile = iWon ? [...s.myPile, ...stake] : s.myPile;
  final phase = newPile.length == 52
      ? WarPhase.won
      : newPile.isEmpty
          ? WarPhase.lost
          : WarPhase.playing;
  return WarState(myPile: newPile, roundNumber: nextRound, pot: const [],
    myPending: null, theirPending: null, phase: phase,
    lastRoundNote: iWon ? 'You win this round.' : null);
}

// ==================================================================
// ==== widget ====
// ==================================================================

class GameWarScreen extends StatefulWidget {
  const GameWarScreen({super.key, required this.role, required this.displayName});
  final String role;
  final String displayName;

  @override
  State<GameWarScreen> createState() => _GameWarScreenState();
}

class _GameWarScreenState extends State<GameWarScreen> {
  late final LocalPairingController _pairing =
      LocalPairingController(role: widget.role, displayName: widget.displayName);
  StreamSubscription<LocalTurnPayload>? _turnSub;

  WarState? _war;
  final _rand = Random();

  Side get _mySide => _pairing.mySide;
  /// Fixed dealer, matching local_play_screen.dart's own Side.b-leads
  /// convention — avoids two devices racing to deal competing decks.
  bool get _amDealer => _mySide == Side.b;

  @override
  void initState() {
    super.initState();
    _pairing.addListener(_onPairingChanged);
    _turnSub = _pairing.incomingTurns.listen(_handleIncomingTurn);
    unawaited(_pairing.start());
  }

  void _onPairingChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _deal() async {
    final dealt = dealWar(_rand);
    setState(() => _war = newWarFromDeal(dealt.forMe));
    await _send({
      'type': 'war_deal',
      'dealtCards': [for (final c in dealt.forPeer) c.code],
    });
  }

  Future<void> _flip() async {
    final current = _war;
    if (current == null) return;
    final result = playMyNext(current);
    if (result.played.isEmpty) return;
    setState(() => _war = result.state);
    await _send({
      'type': 'war_reveal',
      'roundNumber': current.roundNumber,
      'played': [for (final c in result.played) c.code],
    });
  }

  Future<void> _send(Map<String, dynamic> payload) async {
    final audit = auditLiveView(payload);
    if (!audit.ok) {
      // A real, wired safety net, not just a comment — see this codebase's
      // own liveForbidden/auditLiveView (live_games.dart). War's own
      // payload keys never should trip this; if a future edit ever adds a
      // field that does, this is the guard that catches it before it goes
      // out, not a promise that it never will.
      debugPrint('game_war: refusing to send a payload with forbidden keys: ${audit.leaks}');
      return;
    }
    await _pairing.sendTurn(payload);
  }

  void _handleIncomingTurn(LocalTurnPayload payload) {
    final type = payload['type'];
    if (type == 'war_deal') {
      final codes = payload['dealtCards'];
      if (codes is! List) return;
      final cards = <PlayingCard>[];
      for (final c in codes) {
        final card = PlayingCard.fromCode(c as String?);
        if (card == null) return; // malformed — never half-apply a bad deal
        cards.add(card);
      }
      if (cards.length != 26) return;
      if (mounted) setState(() => _war = newWarFromDeal(cards));
      return;
    }
    if (type == 'war_reveal') {
      final current = _war;
      if (current == null) return;
      final playedRaw = payload['played'];
      if (playedRaw is! List) return;
      final cards = <PlayingCard>[];
      for (final c in playedRaw) {
        final card = PlayingCard.fromCode(c as String?);
        if (card == null) return;
        cards.add(card);
      }
      if (mounted) setState(() => _war = receiveTheirs(current, cards));
    }
  }

  @override
  void dispose() {
    unawaited(_turnSub?.cancel());
    _pairing.removeListener(_onPairingChanged);
    _pairing.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Measured once, outside any scroll view — see game_uno.dart's own
    // build() for why this must happen above a LayoutBuilder, not inside
    // one nested in something scrollable.
    return LayoutBuilder(builder: (context, constraints) {
      final posture = ff.postureFor(ff.Viewport(w: constraints.maxWidth, h: constraints.maxHeight));
      final war = _war;
      final Widget body;
      if (_pairing.phase == PairingPhase.error) {
        body = _MessageView(
          message: _pairing.errorMessage ?? "Can't play locally right now.",
          icon: Icons.error_outline,
        );
      } else if (war != null) {
        body = _WarView(state: war, mySide: _mySide, peerName: _pairing.peer?.name ?? 'the other side',
          onFlip: _flip, cardScale: _cardScaleFor(posture));
      } else {
        body = switch (_pairing.phase) {
          PairingPhase.searching => const _Status(message: 'Looking nearby…'),
          PairingPhase.found => _FoundView(
              peerName: _pairing.peer!.name, amDealer: _amDealer, onDeal: _deal),
          PairingPhase.peerLost =>
            _MessageView(message: _pairing.errorMessage!, icon: Icons.wifi_off_outlined),
          PairingPhase.error => throw StateError('handled above'),
        };
      }
      final outerPad = posture == ff.Posture.foldTabletop ? 12.0 : 24.0;
      return Scaffold(
        appBar: AppBar(title: const Text('War')),
        // SingleChildScrollView, not a bare Center — see game_uno.dart's own
        // build() for why: real-device testing at foldTabletop's ~420dp
        // height overflowed there. Same child_home.dart/care_note.dart
        // scroll convention.
        body: SafeArea(child: SingleChildScrollView(
          padding: EdgeInsets.all(outerPad),
          child: Center(child: body),
        )),
      );
    });
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
    const CircularProgressIndicator(),
    const SizedBox(height: 16),
    Text(message, style: Theme.of(context).textTheme.bodyLarge),
  ]);
}

class _FoundView extends StatelessWidget {
  const _FoundView({required this.peerName, required this.amDealer, required this.onDeal});
  final String peerName;
  final bool amDealer;
  final VoidCallback onDeal;
  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
    Icon(Icons.people_alt_outlined, size: 40, color: Theme.of(context).colorScheme.primary),
    const SizedBox(height: 16),
    Text('Found $peerName nearby', style: Theme.of(context).textTheme.headlineSmall),
    const SizedBox(height: 24),
    if (amDealer)
      FilledButton(onPressed: onDeal, child: const Text('Deal the cards'))
    else
      Text('Waiting for $peerName to deal…', style: Theme.of(context).textTheme.bodyLarge
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
  ]);
}

/// Real playing-card colors — red for hearts/diamonds, black for
/// spades/clubs, the same convention every physical deck uses.
Color _suitColor(Suit s) => (s == Suit.hearts || s == Suit.diamonds) ? const Color(0xFFC62828) : Colors.black87;
String _suitSymbol(Suit s) => switch (s) {
  Suit.spades => '♠', Suit.hearts => '♥', Suit.diamonds => '♦', Suit.clubs => '♣',
};
String _rankText(int rank) => switch (rank) {
  14 => 'A', 13 => 'K', 12 => 'Q', 11 => 'J', _ => '$rank',
};

/// A real playing-card face — white ground, mirrored corner rank+suit,
/// a large center suit glyph — the same real layout as a physical card,
/// reused for both piles so the whole board reads consistently.
class _PlayingCardFace extends StatelessWidget {
  const _PlayingCardFace({super.key, required this.card, this.width = 70, this.height = 100});
  final PlayingCard card;
  final double width;
  final double height;
  @override
  Widget build(BuildContext context) {
    final color = _suitColor(card.suit);
    final rank = _rankText(card.rank);
    final suit = _suitSymbol(card.suit);
    return Container(
      width: width, height: height,
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black26, width: 1.5),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3, offset: Offset(0, 1))],
      ),
      child: Stack(children: [
        Positioned(left: 6, top: 4, child: Column(children: [
          Text(rank, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 15)),
          Text(suit, style: TextStyle(color: color, fontSize: 13)),
        ])),
        Positioned(right: 6, bottom: 4, child: Transform.rotate(angle: pi, child: Column(children: [
          Text(rank, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 15)),
          Text(suit, style: TextStyle(color: color, fontSize: 13)),
        ]))),
        Center(child: Text(suit, style: TextStyle(color: color, fontSize: width * 0.42))),
      ]),
    );
  }
}

class _PlayingCardBack extends StatelessWidget {
  const _PlayingCardBack({super.key, this.width = 70, this.height = 100});
  final double width;
  final double height;
  @override
  Widget build(BuildContext context) => Container(
    width: width, height: height,
    decoration: BoxDecoration(
      color: const Color(0xFF7A2828), borderRadius: BorderRadius.circular(10),
      border: Border.all(color: Colors.white, width: 2.5),
    ),
    alignment: Alignment.center,
    child: Icon(Icons.style, color: Colors.white.withValues(alpha: 0.7), size: width * 0.4),
  );
}

/// A genuine card-flip: rotates through its own edge (a real Y-axis
/// perspective transform) whenever [card] changes, rather than an instant
/// swap — the same physical motion turning a real card over makes.
/// Consequence motion only: it plays exactly when the state it's showing
/// actually changes (my tap, or the opponent's reveal arriving), settles
/// well under the §8.13 budget, and never loops or repeats on its own.
class _FlipReveal extends StatelessWidget {
  const _FlipReveal({required this.card, this.width = 70, this.height = 100});
  final PlayingCard? card;
  final double width;
  final double height;
  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: const Duration(milliseconds: 320),
    transitionBuilder: (child, animation) => AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final angle = (1 - animation.value) * (pi / 2);
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()..setEntry(3, 2, 0.001)..rotateY(angle),
          child: child,
        );
      },
      child: child,
    ),
    child: card == null
      ? _PlayingCardBack(key: const ValueKey('back'), width: width, height: height)
      : _PlayingCardFace(key: ValueKey(card!.code), card: card!, width: width, height: height),
  );
}

class _WarView extends StatelessWidget {
  const _WarView({required this.state, required this.mySide, required this.peerName, required this.onFlip, this.cardScale = 1.0});
  final WarState state;
  final Side mySide;
  final String peerName;
  final VoidCallback onFlip;
  final double cardScale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (state.phase != WarPhase.playing) {
      final line = switch (state.phase) {
        WarPhase.won => 'Good game.',
        WarPhase.lost => 'Good game.',
        WarPhase.drawnOut => "Good game — let's call it a tie.",
        WarPhase.playing => '',
      };
      return Column(mainAxisSize: MainAxisSize.min, children: [
        Text(line, style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
      ]);
    }

    final theirCount = 52 - state.myPile.length - (state.myPending?.length ?? 0) - state.pot.length;
    final waitingOnMe = state.myPending == null;
    final justRevealed = state.myPending != null && state.theirPending == null;
    final myWager = (state.myPending?.length ?? 0) > 1;
    final theirWager = (state.theirPending?.length ?? 0) > 1;
    final myShown = state.myPending?.last;
    final theirShown = state.theirPending?.last;
    final battleW = 70 * cardScale, battleH = 100 * cardScale;

    return Column(mainAxisSize: MainAxisSize.min, children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, crossAxisAlignment: CrossAxisAlignment.center, children: [
        _PileWithCount(label: 'You', count: state.myPile.length + (state.myPending?.length ?? 0), scale: cardScale),
        Text('${state.roundNumber}', style: theme.textTheme.labelLarge
          ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        _PileWithCount(label: peerName, count: theirCount.clamp(0, 52), scale: cardScale),
      ]),
      const SizedBox(height: 20),
      // The battle zone — both sides' revealed cards, face down (wager)
      // behind face up (comparator) during a war, mirroring exactly what
      // two real piles look like laid out on a table mid-round.
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Stack(clipBehavior: Clip.none, children: [
          if (myWager) Positioned(left: -6, top: -6, child: _PlayingCardBack(width: battleW, height: battleH)),
          _FlipReveal(card: myShown, width: battleW, height: battleH),
        ]),
        const SizedBox(width: 28),
        Stack(clipBehavior: Clip.none, children: [
          if (theirWager) Positioned(left: -6, top: -6, child: _PlayingCardBack(width: battleW, height: battleH)),
          _FlipReveal(card: theirShown, width: battleW, height: battleH),
        ]),
      ]),
      const SizedBox(height: 20),
      if (state.lastRoundNote != null) ...[
        Text(state.lastRoundNote!, style: theme.textTheme.bodyLarge, textAlign: TextAlign.center),
        const SizedBox(height: 12),
      ],
      if (waitingOnMe)
        // A real tap-to-flip on your own pile, not a plain labeled button
        // — the same physical motion turning your top card over is.
        GestureDetector(
          onTap: onFlip,
          child: Stack(clipBehavior: Clip.none, children: [
            Positioned(left: -4, top: -4, child: _PlayingCardBack(width: battleW, height: battleH)),
            _PlayingCardBack(width: battleW, height: battleH),
            Positioned.fill(child: Center(child: Icon(Icons.touch_app_outlined,
              color: Colors.white.withValues(alpha: 0.9), size: 28 * cardScale))),
          ]),
        )
      else if (justRevealed)
        Text('Waiting for $peerName to flip…', style: theme.textTheme.bodyLarge
          ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
    ]);
  }
}

class _PileWithCount extends StatelessWidget {
  const _PileWithCount({required this.label, required this.count, this.scale = 1.0});
  final String label;
  final int count;
  final double scale;
  @override
  Widget build(BuildContext context) {
    final w = 44 * scale, h = 62 * scale;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Stack(clipBehavior: Clip.none, children: [
        if (count > 1) Positioned(left: 3, top: 3, child: _PlayingCardBack(width: w, height: h)),
        count > 0 ? _PlayingCardBack(width: w, height: h) : SizedBox(width: w, height: h),
      ]),
      const SizedBox(height: 6),
      Text('$count', style: Theme.of(context).textTheme.titleMedium),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ]);
  }
}

class _MessageView extends StatelessWidget {
  const _MessageView({required this.message, required this.icon});
  final String message;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
    Icon(icon, size: 40, color: Theme.of(context).colorScheme.onSurfaceVariant),
    const SizedBox(height: 16),
    Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
  ]);
}
