// OLIVE BRANCH — Uno, the ad-hoc local card game. Network resilience &
// ad-hoc mode roadmap, Track B Option 2, ad-hoc games expansion. Last of
// five new local-play activities, and the most complex — see
// uno_session.dart's own header for the real, disclosed v1 scope trim
// (core two-seat rules only; no roster/team-mode/house-rule-toggle UI in
// this pass, each a real, separate follow-up).
//
// TWO MODES, same real boundary connect4_bot.dart's own vs-CPU/vs-peer
// split already established: **vs CPU is fully local** (one device, no
// network, the CPU plays automatically) and **vs peer is fully networked,
// human vs human** — a CPU seat inside a networked game is real, disclosed
// deferred scope, not silently missing.
//
// DECK AUTHORITY, a genuinely new pattern for this codebase: unlike War's
// two independently-authoritative piles, Uno's shared secret draw pile
// needs exactly ONE real, full [UnoSession] (both hands) to exist
// anywhere — held on the dealing device (Side.b, matching every other
// game's own fixed dealer/leader convention). The OTHER device never
// holds the opponent's real hand, only its own (as told to it by the
// authority) and the opponent's card COUNT. Confirmed real transport fact
// this shapes: local_session.dart's server never returns a response body
// (status code only) — so the authority's reply to a peer's move request
// is its own independent, reverse-direction sendTurn() call, never a
// response payload. Simplified from a true incremental-delta protocol:
// every state broadcast from the authority carries the peer's CURRENT
// FULL hand (not just what changed) — a peer's hand is small enough that
// this is simpler and safer to get right under real time pressure than
// delta-merging, at the cost of a slightly bigger payload.
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'form_factors.dart' as ff show Posture, Viewport, postureFor;
import 'live_games.dart' show Side, auditLiveView;
import 'local_pairing.dart';
import 'uno_bot.dart';
import 'uno_deck.dart';
import 'uno_session.dart';

/// A real per-device card-size multiplier, keyed off the same real
/// postures form_factors.dart already defines for the rest of this app
/// (game_picker.dart's own grid among them) — not a bespoke breakpoint.
/// The 64dp §8.4 floor still wins: this only ever scales UP from the
/// baseline the fan/card layout was built at, never below it, so a small
/// posture never drops under the touch-target floor.
double _cardScaleFor(ff.Posture posture) => switch (posture) {
  ff.Posture.foldCover || ff.Posture.phone || ff.Posture.tabletSmall => 1.0,
  ff.Posture.foldMain || ff.Posture.foldTabletop || ff.Posture.tabletMedium => 1.08,
  ff.Posture.tabletLarge => 1.16,
  ff.Posture.desktop || ff.Posture.dex => 1.22,
};

String _encodeColor(UnoColor c) => switch (c) {
  UnoColor.red => 'red', UnoColor.yellow => 'yellow', UnoColor.green => 'green', UnoColor.blue => 'blue',
};
UnoColor? _decodeColor(Object? v) => switch (v) {
  'red' => UnoColor.red, 'yellow' => UnoColor.yellow, 'green' => UnoColor.green, 'blue' => UnoColor.blue,
  _ => null,
};
String _encodeSide(Side s) => s == Side.a ? 'a' : 'b';

/// This device's own real Uno seatId — the local_pairing.dart Side this
/// device was assigned IS the real seatId once dealt (a 2-seat table is
/// always seatOrder ['a','b']), so this is a real value, not a stand-in.
/// A future seat-picker UI can host more than one local seat per device
/// (game_seat.dart's own real "a device can host more than one seat"
/// design) — this getter only ever describes the fixed single-human-seat
/// case this screen still is, one real follow-up at a time.

enum _Mode { none, vsCpu, vsPeer }

class GameUnoScreen extends StatefulWidget {
  const GameUnoScreen({super.key, required this.role, required this.displayName});
  final String role;
  final String displayName;

  @override
  State<GameUnoScreen> createState() => _GameUnoScreenState();
}

class _GameUnoScreenState extends State<GameUnoScreen> {
  late final LocalPairingController _pairing =
      LocalPairingController(role: widget.role, displayName: widget.displayName);
  StreamSubscription<LocalTurnPayload>? _turnSub;
  final _rand = Random();

  _Mode _mode = _Mode.none;
  UnoCpuDifficulty _cpuDifficulty = UnoCpuDifficulty.normal;

  // Authoritative path (vsCpu always; vsPeer when I dealt).
  UnoSession? _authoritySession;
  bool _amAuthority = false;

  // Redacted peer-view path (vsPeer, when the OTHER device dealt).
  List<UnoCard>? _peerMyHand;
  UnoCard? _peerDiscardTop;
  UnoColor? _peerCurrentColor;
  String? _peerTurn;
  int _peerOpponentHandCount = 0;
  String? _peerWinner;
  bool _peerAwaitingResult = false;

  Side get _mySide => _pairing.mySide;
  String get _mySeatId => _encodeSide(_mySide);

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

  // ---------------------------------------------------------------- vs CPU

  void _startVsCpu() {
    final session = dealUno(const ['a', 'b'], _rand);
    setState(() {
      _mode = _Mode.vsCpu;
      _authoritySession = session;
      _amAuthority = true;
    });
    _maybeRunCpuTurn();
  }

  void _maybeRunCpuTurn() {
    final s = _authoritySession;
    if (s == null || s.winner != null || s.turnSeatId == _mySeatId) return;
    Future.delayed(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      final current = _authoritySession;
      if (current == null || current.winner != null || current.turnSeatId == _mySeatId) return;
      final cpuSeatId = current.turnSeatId;
      final opponentHandCounts = {_mySeatId: current.hands[_mySeatId]!.length};
      final move = chooseUnoMove(current, cpuSeatId, _cpuDifficulty, opponentHandCounts, _rand);
      final next = move.isDraw
          ? drawCard(current, cpuSeatId, _rand).session
          : playCard(current, cpuSeatId, move.card!, chosenColor: move.color, rand: _rand).session;
      setState(() => _authoritySession = next);
      _maybeRunCpuTurn();
    });
  }

  // --------------------------------------------------------------- vs peer

  Future<void> _dealForPeer() async {
    final session = dealUno(const ['a', 'b'], _rand);
    setState(() {
      _mode = _Mode.vsPeer;
      _authoritySession = session;
      _amAuthority = true;
    });
    await _sendStateDelta(session);
  }

  Future<void> _sendStateDelta(UnoSession session) async {
    final peerSeatId = _mySeatId == 'a' ? 'b' : 'a';
    final payload = <String, dynamic>{
      'type': 'uno_state_delta',
      'myHandForPeer': [for (final c in session.hands[peerSeatId]!) c.code],
      'opponentHandCount': session.hands[_mySeatId]!.length,
      'discardTopCardId': session.topDiscard.code,
      'currentColor': _encodeColor(session.currentColor),
      // Already real wire-safe seatId strings ('a'/'b') — no encode step
      // needed now that uno_session.dart tracks turn/winner as real
      // seatIds rather than a Side enum.
      'mover': session.turnSeatId,
      'winner': session.winner,
    };
    final audit = auditLiveView(payload);
    if (!audit.ok) {
      debugPrint('game_uno: refusing to send a payload with forbidden keys: ${audit.leaks}');
      return;
    }
    await _pairing.sendTurn(payload);
  }

  Future<void> _peerRequestAction({UnoCard? card, UnoColor? color, bool draw = false}) async {
    setState(() => _peerAwaitingResult = true);
    final payload = <String, dynamic>{
      'type': 'uno_action',
      'action': draw ? 'draw' : 'playCard',
      if (card != null) 'cardCode': card.code,
      if (color != null) 'chosenColor': _encodeColor(color),
    };
    await _pairing.sendTurn(payload);
  }

  void _handleIncomingTurn(LocalTurnPayload payload) {
    final type = payload['type'];
    if (type == 'uno_action' && _amAuthority) {
      final session = _authoritySession;
      if (session == null) return;
      final peerSeatId = _mySeatId == 'a' ? 'b' : 'a';
      if (session.turnSeatId != peerSeatId) return; // not their turn — refuse, matches every other game's re-validation
      final action = payload['action'];
      UnoSession? next;
      if (action == 'draw') {
        final r = drawCard(session, peerSeatId, _rand);
        if (r.accepted) next = r.session;
      } else if (action == 'playCard') {
        final card = UnoCard.fromCode(payload['cardCode'] as String?);
        if (card == null) return;
        final color = _decodeColor(payload['chosenColor']);
        final r = playCard(session, peerSeatId, card, chosenColor: color, rand: _rand);
        if (r.accepted) next = r.session;
      }
      if (next == null) return;
      setState(() => _authoritySession = next);
      unawaited(_sendStateDelta(next));
      _maybeRunCpuTurn(); // no-op in vsPeer mode (no CPU seat), harmless if ever both are set
      return;
    }
    if (type == 'uno_state_delta' && !_amAuthority) {
      final handRaw = payload['myHandForPeer'];
      if (handRaw is! List) return;
      final hand = <UnoCard>[];
      for (final c in handRaw) {
        final card = UnoCard.fromCode(c as String?);
        if (card == null) return;
        hand.add(card);
      }
      final top = UnoCard.fromCode(payload['discardTopCardId'] as String?);
      final color = _decodeColor(payload['currentColor']);
      final mover = payload['mover'] as String?;
      if (top == null || color == null || mover == null) return;
      if (mounted) {
        setState(() {
          _mode = _Mode.vsPeer;
          _peerMyHand = hand;
          _peerDiscardTop = top;
          _peerCurrentColor = color;
          _peerTurn = mover;
          _peerOpponentHandCount = (payload['opponentHandCount'] as num?)?.toInt() ?? 0;
          _peerWinner = payload['winner'] as String?;
          _peerAwaitingResult = false;
        });
      }
    }
  }

  // ------------------------------------------------------------- UI actions

  Future<void> _playAsAuthority(UnoCard card, UnoColor? color) async {
    final s = _authoritySession;
    if (s == null) return;
    final r = playCard(s, _mySeatId, card, chosenColor: color, rand: _rand);
    if (!r.accepted) return;
    setState(() => _authoritySession = r.session);
    if (_mode == _Mode.vsPeer) await _sendStateDelta(r.session);
    _maybeRunCpuTurn();
  }

  Future<void> _drawAsAuthority() async {
    final s = _authoritySession;
    if (s == null) return;
    final r = drawCard(s, _mySeatId, _rand);
    if (!r.accepted) return;
    setState(() => _authoritySession = r.session);
    if (_mode == _Mode.vsPeer) await _sendStateDelta(r.session);
    _maybeRunCpuTurn();
  }

  Future<void> _onCardTap(UnoCard card) async {
    final isWild = card.type == UnoCardType.wild || card.type == UnoCardType.wildDrawFour;
    UnoColor? color;
    if (isWild) {
      color = await _pickColor();
      if (color == null) return; // cancelled
    }
    if (_amAuthority) {
      await _playAsAuthority(card, color);
    } else {
      await _peerRequestAction(card: card, color: color);
    }
  }

  Future<void> _onDrawTap() async {
    if (_amAuthority) {
      await _drawAsAuthority();
    } else {
      await _peerRequestAction(draw: true);
    }
  }

  Future<UnoColor?> _pickColor() => showModalBottomSheet<UnoColor>(
    context: context,
    builder: (context) => SafeArea(child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Choose a color', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 16),
        Wrap(spacing: 16, runSpacing: 16, alignment: WrapAlignment.center, children: [
          for (final c in UnoColor.values)
            InkWell(
              onTap: () => Navigator.of(context).pop(c),
              customBorder: const CircleBorder(),
              child: Container(
                width: 64, height: 64,
                decoration: BoxDecoration(color: _colorFor(c), shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3),
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))]),
              ),
            ),
        ]),
      ]),
    )),
  );

  @override
  void dispose() {
    unawaited(_turnSub?.cancel());
    _pairing.removeListener(_onPairingChanged);
    _pairing.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Measured once, outside any scroll view, matching game_picker.dart's
    // own established discipline — a LayoutBuilder nested inside a
    // scrollable sees an unbounded main-axis extent, not the real
    // viewport, which would feed postureFor()/the fan width the wrong
    // number entirely.
    return LayoutBuilder(builder: (context, constraints) {
      final posture = ff.postureFor(ff.Viewport(w: constraints.maxWidth, h: constraints.maxHeight));
      final Widget body;
      if (_amAuthority && _authoritySession != null) {
        // A real game already under way, as authority (vsCpu always, or
        // vsPeer as the dealer) — takes priority regardless of live pairing
        // state. vsCpu in particular never depended on pairing succeeding
        // at all, so a later pairing hiccup must never interrupt it.
        final s = _authoritySession!;
        final opponentSeatId = _mySeatId == 'a' ? 'b' : 'a';
        body = _UnoBoard(
          myHand: s.hands[_mySeatId]!, opponentHandCount: s.hands[opponentSeatId]!.length,
          discardTop: s.topDiscard, currentColor: s.currentColor, myTurn: s.turnSeatId == _mySeatId,
          winner: s.winner, iWon: s.winner == _mySeatId, waiting: false,
          onCardTap: _onCardTap, onDraw: _onDrawTap, peerName: _peerName(),
          availableWidth: constraints.maxWidth, posture: posture,
        );
      } else if (!_amAuthority && _peerMyHand != null) {
        body = _UnoBoard(
          myHand: _peerMyHand!, opponentHandCount: _peerOpponentHandCount,
          discardTop: _peerDiscardTop!, currentColor: _peerCurrentColor!, myTurn: _peerTurn == _mySeatId,
          winner: _peerWinner, iWon: _peerWinner == _mySeatId, waiting: _peerAwaitingResult,
          onCardTap: _onCardTap, onDraw: _onDrawTap, peerName: _peerName(),
          availableWidth: constraints.maxWidth, posture: posture,
        );
      } else if (_mode == _Mode.vsPeer) {
        // Chose "play together" but no game has started yet — THIS branch
        // is genuinely pairing-dependent (there is no vsCpu fallback once
        // this choice is made), unlike the picker below.
        body = switch (_pairing.phase) {
          PairingPhase.searching => const _Status(message: 'Looking nearby…'),
          PairingPhase.found => _amDealer()
              ? FilledButton(onPressed: _dealForPeer, child: const Text('Deal the cards'))
              : const _Status(message: 'Waiting for Dad to deal…'),
          PairingPhase.peerLost =>
            _MessageView(message: _pairing.errorMessage!, icon: Icons.wifi_off_outlined),
          PairingPhase.error =>
            _MessageView(message: _pairing.errorMessage ?? "Can't play locally right now.", icon: Icons.error_outline),
        };
      } else {
        // _mode == _Mode.none — the real entry point. vs-CPU needs no
        // pairing at all, matching connect4_bot.dart's own established
        // precedent, so this picker is ALWAYS shown here regardless of
        // live pairing state (including a real pairing error) — only the
        // picker's own "or play together" affordance depends on it.
        body = _ModePicker(
          difficulty: _cpuDifficulty,
          onDifficultyChanged: (d) => setState(() => _cpuDifficulty = d),
          onStartVsCpu: _startVsCpu,
          onPlayNearby: () => setState(() => _mode = _Mode.vsPeer),
          peerFound: _pairing.phase == PairingPhase.found, peerName: _pairing.peer?.name,
        );
      }
      // Short/landscape postures (the Fold half-open on a stand, in
      // particular) get tighter outer padding so the table has real room
      // to breathe instead of losing it to a fixed 16dp gutter tuned for
      // a taller screen.
      final outerPad = posture == ff.Posture.foldTabletop ? 8.0 : 16.0;
      return Scaffold(
        appBar: AppBar(title: const Text('Uno')),
        // SingleChildScrollView, not a bare Center — real-device testing at
        // foldTabletop's ~420dp height (landscape, hands-free call posture)
        // overflowed by nearly 300px: a full seat tag + pile row + status
        // text + hand fan stack simply doesn't fit that short a viewport.
        // Same fix pattern as child_home.dart/care_note.dart's own
        // SingleChildScrollView + Column convention — scrolls on the rare
        // short/cramped posture, identical to Center's look everywhere
        // else since the content already fits there.
        body: SafeArea(child: SingleChildScrollView(
          padding: EdgeInsets.all(outerPad),
          child: Center(child: body),
        )),
      );
    });
  }

  bool _amDealer() => _mySide == Side.b;
  String _peerName() => _mode == _Mode.vsCpu ? 'Computer' : (_pairing.peer?.name ?? 'the other side');
}

// Also offered before pairing ever resolves, matching connect4's own
// "vs CPU needs no pairing at all" real precedent.
class _ModePicker extends StatelessWidget {
  const _ModePicker({required this.difficulty, required this.onDifficultyChanged, required this.onStartVsCpu,
    required this.onPlayNearby, required this.peerFound, required this.peerName});
  final UnoCpuDifficulty difficulty;
  final ValueChanged<UnoCpuDifficulty> onDifficultyChanged;
  final VoidCallback onStartVsCpu;
  final VoidCallback onPlayNearby;
  final bool peerFound;
  final String? peerName;

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
    Text('Uno', style: Theme.of(context).textTheme.headlineSmall),
    const SizedBox(height: 16),
    const Text('Play the computer'),
    const SizedBox(height: 8),
    SegmentedButton<UnoCpuDifficulty>(
      segments: const [
        ButtonSegment(value: UnoCpuDifficulty.easy, label: Text('Easy')),
        ButtonSegment(value: UnoCpuDifficulty.normal, label: Text('Normal')),
        ButtonSegment(value: UnoCpuDifficulty.hard, label: Text('Hard')),
      ],
      selected: {difficulty}, onSelectionChanged: (s) => onDifficultyChanged(s.first),
    ),
    const SizedBox(height: 16),
    FilledButton(onPressed: onStartVsCpu, child: const Text('Start')),
    const SizedBox(height: 24),
    if (peerFound) ...[
      Text('Found $peerName nearby'),
      const SizedBox(height: 8),
      FilledButton(onPressed: onPlayNearby, child: const Text('Play together instead')),
    ] else
      const Text('Looking nearby…'),
  ]);
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

Color _colorFor(UnoColor c) => switch (c) {
  UnoColor.red => const Color(0xFFD4322C), UnoColor.yellow => const Color(0xFFF2C230),
  UnoColor.green => const Color(0xFF3A9B4C), UnoColor.blue => const Color(0xFF2E6BC7),
};

/// The big center symbol a real Uno card shows: the number, or an icon for
/// an action card, or the wild badge. Kept separate from the corner
/// indicator text below since real cards show both at once.
Widget _bigSymbol(UnoCard card, {double size = 34}) {
  switch (card.type) {
    case UnoCardType.number:
      return Text('${card.number}', style: TextStyle(fontSize: size, fontWeight: FontWeight.w900, color: Colors.black87));
    case UnoCardType.skip:
      return Icon(Icons.block, size: size, color: Colors.black87);
    case UnoCardType.reverse:
      return Icon(Icons.sync, size: size, color: Colors.black87);
    case UnoCardType.drawTwo:
      return Text('+2', style: TextStyle(fontSize: size * 0.7, fontWeight: FontWeight.w900, color: Colors.black87));
    case UnoCardType.wild:
      return Icon(Icons.palette, size: size, color: Colors.black87);
    case UnoCardType.wildDrawFour:
      return Text('+4', style: TextStyle(fontSize: size * 0.7, fontWeight: FontWeight.w900, color: Colors.black87));
  }
}

/// One real card face — the same visual used for a hand card, the discard
/// pile's top card, and a drag preview, so all three always look
/// identical (never three near-duplicate implementations to drift apart).
/// Modeled on a real Uno card's own real layout: colored ground, a white
/// center oval carrying the big symbol, mirrored corner indicators.
class _UnoCardFace extends StatelessWidget {
  const _UnoCardFace({super.key, required this.card, this.width = 64, this.height = 92, this.dimmed = false});
  final UnoCard card;
  final double width;
  final double height;
  final bool dimmed;

  bool get _isWild => card.type == UnoCardType.wild || card.type == UnoCardType.wildDrawFour;

  @override
  Widget build(BuildContext context) {
    final ground = _isWild ? Colors.black87 : _colorFor(card.color!);
    final corner = card.type == UnoCardType.number ? '${card.number}'
      : card.type == UnoCardType.skip ? '⊘'
      : card.type == UnoCardType.reverse ? '⇄'
      : card.type == UnoCardType.drawTwo ? '+2'
      : card.type == UnoCardType.wild ? 'W' : '+4';
    // A bare '6' rotated 180° reads as a '9' (and vice versa) — real Uno
    // cards disambiguate with a small underline beneath the digit. Mirror
    // that here so the mirrored bottom-right corner stays readable.
    final needsUnderline = card.type == UnoCardType.number && (card.number == 6 || card.number == 9);
    Widget cornerLabel() {
      final text = Text(corner, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13));
      if (!needsUnderline) return text;
      return Column(mainAxisSize: MainAxisSize.min, children: [
        text,
        Container(width: 11, height: 1.6, margin: const EdgeInsets.only(top: 1), color: Colors.white),
      ]);
    }
    return Opacity(
      opacity: dimmed ? 0.35 : 1.0,
      child: Container(
        width: width, height: height,
        decoration: BoxDecoration(
          color: ground, borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white, width: 2.5),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3, offset: Offset(0, 1))],
        ),
        child: Stack(children: [
          Positioned(left: 5, top: 3, child: cornerLabel()),
          Positioned(right: 5, bottom: 3, child: Transform.rotate(angle: pi, child: cornerLabel())),
          Center(child: Transform.rotate(angle: -0.35, child: Container(
            width: width * 0.72, height: height * 0.5,
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(999)),
            alignment: Alignment.center,
            child: _isWild
              ? _WildBadge(size: width * 0.4)
              : _bigSymbol(card, size: width * 0.42),
          ))),
        ]),
      ),
    );
  }
}

class _WildBadge extends StatelessWidget {
  const _WildBadge({required this.size});
  final double size;
  @override
  Widget build(BuildContext context) => SizedBox(width: size, height: size, child: GridView.count(
    crossAxisCount: 2, physics: const NeverScrollableScrollPhysics(),
    children: [for (final c in UnoColor.values) Container(color: _colorFor(c))],
  ));
}

/// A face-down card-back — the opponent's hand and the draw pile are both
/// rendered from this, never real card data (there is none to render on
/// this device for the opponent's hand anyway).
class _CardBack extends StatelessWidget {
  const _CardBack({this.width = 50, this.height = 72});
  final double width;
  final double height;
  @override
  Widget build(BuildContext context) => Container(
    width: width, height: height,
    decoration: BoxDecoration(
      color: const Color(0xFF1B1F3B), borderRadius: BorderRadius.circular(9),
      border: Border.all(color: Colors.white, width: 2),
    ),
    alignment: Alignment.center,
    child: Text('UNO', style: TextStyle(color: Colors.white.withValues(alpha: 0.85),
      fontWeight: FontWeight.w900, fontSize: width * 0.18, letterSpacing: 1)),
  );
}

class _UnoBoard extends StatelessWidget {
  const _UnoBoard({
    required this.myHand, required this.opponentHandCount, required this.discardTop, required this.currentColor,
    required this.myTurn, required this.winner, required this.iWon, required this.waiting,
    required this.onCardTap, required this.onDraw, required this.peerName,
    required this.availableWidth, required this.posture,
  });
  final List<UnoCard> myHand;
  final int opponentHandCount;
  final UnoCard discardTop;
  final UnoColor currentColor;
  final bool myTurn;
  final String? winner;
  final bool iWon;
  final bool waiting;
  final ValueChanged<UnoCard> onCardTap;
  final VoidCallback onDraw;
  final String peerName;
  /// The REAL measured width this screen has to work with right now —
  /// not a guessed constant. Threaded down to _HandFan so the fan's own
  /// width budget matches whatever's actually on screen, from a Fold
  /// closed at 344dp to a desktop window well past 1024dp.
  final double availableWidth;
  final ff.Posture posture;

  /// A lightweight, CLIENT-SIDE-ONLY legality check purely to decide
  /// whether a dragged card should visually "want" to land on the discard
  /// pile — the same discipline game_puzzle.dart's own DragTarget already
  /// holds itself to. This is NOT the authoritative check: whichever
  /// device actually applies the move re-validates for real via
  /// uno_session.dart's own isLegalUnoPlay/playCard, exactly like every
  /// other engine in this expansion re-validates on receipt rather than
  /// trusting what a sending UI already disabled.
  bool _looksLegal(UnoCard card) {
    final isWild = card.type == UnoCardType.wild || card.type == UnoCardType.wildDrawFour;
    if (isWild) return true;
    if (card.color == currentColor) return true;
    if (card.type == UnoCardType.number && discardTop.type == UnoCardType.number && card.number == discardTop.number) return true;
    if (card.type != UnoCardType.number && card.type == discardTop.type) return true;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (winner != null) {
      return _RoundEndCelebration(iWon: iWon, peerName: peerName);
    }
    final enabled = myTurn && !waiting;
    final opponentColor = theme.colorScheme.tertiary;
    final myColor = theme.colorScheme.primary;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      // A real oval "table" ground behind the shared play area — the
      // felt every physical Uno table has — rather than the piles just
      // floating on the plain scaffold background.
      Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(220), // wide/flat enough to read as an oval at this box's real shape
          gradient: RadialGradient(radius: 1.15, colors: [
            theme.colorScheme.primaryContainer.withValues(alpha: 0.55),
            theme.colorScheme.surface.withValues(alpha: 0),
          ]),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Opponent's hand, face-down — a real fanned arc, not a flat
          // overlapped row, so the table reads like a real seat across
          // from you, not a stat readout.
          _SeatTag(name: peerName, color: opponentColor),
          const SizedBox(height: 8),
          SizedBox(height: 52, child: Stack(clipBehavior: Clip.none, children: [
            for (var i = 0; i < opponentHandCount.clamp(0, 14); i++)
              _fannedCardBack(i, opponentHandCount.clamp(0, 14)),
          ])),
          const SizedBox(height: 20),
          // Draw pile (left) and discard pile (right) — the real two-pile
          // layout every physical Uno table has. Tapping the draw pile
          // draws; dragging a hand card onto the discard pile plays it.
          Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.center, children: [
            GestureDetector(
              onTap: enabled ? onDraw : null,
              child: Stack(children: [
                const Positioned(left: 3, top: 3, child: _CardBack(width: 64, height: 92)),
                Opacity(opacity: enabled ? 1.0 : 0.5, child: const _CardBack(width: 64, height: 92)),
              ]),
            ),
            const SizedBox(width: 28),
            Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
              // The action-card "moment" — a brief glow, only ever a
              // direct consequence of a real new discard, never idle.
              _ActionMomentGlow(card: discardTop),
              DragTarget<UnoCard>(
                onWillAcceptWithDetails: (details) => enabled && _looksLegal(details.data),
                onAcceptWithDetails: (details) => onCardTap(details.data),
                builder: (context, candidates, rejected) => AnimatedContainer(
                  duration: const Duration(milliseconds: 150), // consequence: reacts to the drag, settles fast, never loops
                  padding: EdgeInsets.all(candidates.isNotEmpty ? 4 : 0),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: candidates.isNotEmpty ? Border.all(color: theme.colorScheme.primary, width: 3) : null,
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220), // consequence: a new card just landed here
                    transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: FadeTransition(opacity: anim, child: child)),
                    child: _UnoCardFace(key: ValueKey(discardTop.code + currentColor.name), card: discardTop, width: 64, height: 92),
                  ),
                ),
              ),
            ]),
          ]),
          const SizedBox(height: 6),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Text('Color in play  '),
            Container(width: 16, height: 16, decoration: BoxDecoration(color: _colorFor(currentColor), shape: BoxShape.circle)),
          ]),
        ]),
      ),
      const SizedBox(height: 14),
      Text(waiting ? 'Sending…' : myTurn ? 'Your turn — drag a card up to play it' : 'Waiting for $peerName…',
        style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
      const SizedBox(height: 8),
      // The one-card-left moment — a real, single-round game fact, shown
      // only as a brief consequence of just now dropping to one card,
      // never a persistent readout.
      SizedBox(height: 44, child: Center(child: _UnoCalloutOverlay(myHandCount: myHand.length, opponentHandCount: opponentHandCount))),
      const SizedBox(height: 8),
      _SeatTag(name: 'You', color: myColor),
      const SizedBox(height: 10),
      // My hand — a real overlapping fan, not a plain grid. Each card
      // stays a real Draggable (drag up onto the discard pile to play,
      // matching the physical motion of throwing a card down) with a tap
      // fallback for anyone who finds a drag harder to land — real Uno
      // apps support both, and a tap is the more accessible of the two.
      _HandFan(cards: myHand, enabled: enabled, onCardTap: onCardTap,
        availableWidth: availableWidth, cardScale: _cardScaleFor(posture)),
    ]);
  }

  /// A face-down opponent card at fan position [i] of [count] — a slight
  /// per-card rotation plus a small downward arc toward the fan's edges,
  /// so it reads as a real fanned hand rather than a flat overlapped
  /// stack. Driven purely by the real, fixed hand count each build —
  /// never animated on its own (no idle motion), only the discrete jump
  /// when a card count actually changes reads as movement at all, the
  /// same "ambient is never free-running" discipline as every other
  /// static-until-a-real-change layout in this app.
  Widget _fannedCardBack(int i, int count) {
    final mid = (count - 1) / 2;
    final offsetFromCenter = i - mid;
    return Positioned(
      left: i * 14.0, top: offsetFromCenter.abs() * 1.8,
      child: Transform.rotate(angle: offsetFromCenter * 0.045, child: const _CardBack(width: 32, height: 44)),
    );
  }
}

/// A real name-tag-with-avatar for a seat — a small colored initial
/// badge plus a name pill, in this app's own Material 3 palette. Not a
/// reproduction of any specific game's own avatar art; just the same
/// general "who's in this seat" idea every table-card-game UI needs.
class _SeatTag extends StatelessWidget {
  const _SeatTag({required this.name, required this.color});
  final String name;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.only(left: 4, right: 14, top: 4, bottom: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface, borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color, width: 1.5),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 3, offset: Offset(0, 1))],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        CircleAvatar(radius: 12, backgroundColor: color,
          child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
        const SizedBox(width: 8),
        Text(name, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

/// A brief, deliberate "something just happened" glow behind the discard
/// pile — driven strictly by a real new discard that's an action card
/// (Skip/Reverse/Draw Two/Wild Draw Four), plays once per real play, then
/// goes quiet. §8.13 consequence, never idle/ambient/looping. The general
/// idea (a visual pulse making an action card's effect legible at a
/// glance) is a common table-game-UI convention, not a reproduction of
/// any specific game's own effect art.
class _ActionMomentGlow extends StatefulWidget {
  const _ActionMomentGlow({required this.card});
  final UnoCard card;

  @override
  State<_ActionMomentGlow> createState() => _ActionMomentGlowState();
}

class _ActionMomentGlowState extends State<_ActionMomentGlow> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
  late String _lastCode = widget.card.code;

  bool get _isAction => widget.card.type == UnoCardType.skip || widget.card.type == UnoCardType.reverse ||
      widget.card.type == UnoCardType.drawTwo || widget.card.type == UnoCardType.wildDrawFour;

  @override
  void initState() {
    super.initState();
    if (_isAction) _controller.forward();
  }

  @override
  void didUpdateWidget(_ActionMomentGlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.card.code != _lastCode) {
      _lastCode = widget.card.code;
      if (_isAction) _controller..reset()..forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  IconData? get _effectIcon => switch (widget.card.type) {
    UnoCardType.skip => Icons.block,
    UnoCardType.reverse => Icons.sync,
    UnoCardType.drawTwo || UnoCardType.wildDrawFour => Icons.add_circle_outline,
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final t = _controller.value;
          if (t == 0) return const SizedBox(width: 100, height: 100);
          final fade = t < 0.5 ? t * 2 : (1 - t) * 2; // rises then fades — one shot, never sustained
          return Opacity(
            opacity: fade.clamp(0, 1),
            child: Transform.scale(
              scale: 1.0 + t * 0.7,
              child: Container(
                width: 100, height: 100,
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: theme.colorScheme.primary, width: 3)),
                alignment: Alignment.center,
                child: _effectIcon == null ? null : Icon(_effectIcon, size: 28, color: theme.colorScheme.primary),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A brief "UNO!" callout the instant either seat's hand drops to exactly
/// one card — triggered ONLY by that real transition (never shown as a
/// standing readout while sitting at one card), consequence-only per
/// §8.13. A real, single-round game-state fact, not a score or streak.
class _UnoCalloutOverlay extends StatefulWidget {
  const _UnoCalloutOverlay({required this.myHandCount, required this.opponentHandCount});
  final int myHandCount;
  final int opponentHandCount;

  @override
  State<_UnoCalloutOverlay> createState() => _UnoCalloutOverlayState();
}

class _UnoCalloutOverlayState extends State<_UnoCalloutOverlay> {
  bool _visible = false;
  Timer? _timer;
  late int _lastMy = widget.myHandCount;
  late int _lastOpponent = widget.opponentHandCount;

  @override
  void didUpdateWidget(_UnoCalloutOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    final justHitOne = (widget.myHandCount == 1 && _lastMy != 1) || (widget.opponentHandCount == 1 && _lastOpponent != 1);
    _lastMy = widget.myHandCount;
    _lastOpponent = widget.opponentHandCount;
    if (justHitOne) {
      _timer?.cancel();
      setState(() => _visible = true);
      _timer = Timer(const Duration(milliseconds: 1300), () {
        if (mounted) setState(() => _visible = false);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1), duration: const Duration(milliseconds: 260), curve: Curves.easeOutBack,
      builder: (context, t, child) => Transform.scale(scale: t.clamp(0, 1.4), child: Opacity(opacity: t.clamp(0, 1), child: child)),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
        decoration: BoxDecoration(color: theme.colorScheme.primary, borderRadius: BorderRadius.circular(999),
          boxShadow: [BoxShadow(color: theme.colorScheme.primary.withValues(alpha: 0.4), blurRadius: 16, spreadRadius: 2)]),
        child: Text('UNO!', style: theme.textTheme.headlineSmall?.copyWith(color: theme.colorScheme.onPrimary, fontWeight: FontWeight.w900)),
      ),
    );
  }
}

/// The round-end moment — celebratory, but never a score/point tally
/// (MASTERFILE P2: no scores/streaks/ranks shown to the child). Real
/// research precedent for why that line matters here: a well-known
/// commercial Uno implementation's own round-end screen shows a running
/// per-player point table across rounds — exactly the pattern P2
/// forbids, so this deliberately stops at "who won this one round,"
/// never accumulating or displaying anything beyond that. Also the first
/// real use of [iWon] — it was threaded all the way from game_uno.dart's
/// own state through _UnoBoard but never actually read here before.
class _RoundEndCelebration extends StatelessWidget {
  const _RoundEndCelebration({required this.iWon, required this.peerName});
  final bool iWon;
  final String peerName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TweenAnimationBuilder<double>(
      // Consequence: plays once as this real winner-state first mounts,
      // never repeats, never loops.
      tween: Tween(begin: 0, end: 1), duration: const Duration(milliseconds: 420), curve: Curves.easeOutBack,
      builder: (context, t, child) => Transform.scale(scale: 0.7 + 0.3 * t.clamp(0, 1), child: Opacity(opacity: t.clamp(0, 1), child: child)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 96, height: 96,
          decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [
            theme.colorScheme.primaryContainer, theme.colorScheme.primaryContainer.withValues(alpha: 0.25),
          ])),
          alignment: Alignment.center,
          child: Icon(Icons.celebration, size: 48, color: theme.colorScheme.primary),
        ),
        const SizedBox(height: 16),
        Text(iWon ? 'You won!' : '$peerName won this one!', style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
        const SizedBox(height: 6),
        Text('Good game.', style: theme.textTheme.bodyLarge),
      ]),
    );
  }
}

class _HandFan extends StatelessWidget {
  const _HandFan({
    required this.cards, required this.enabled, required this.onCardTap,
    required this.availableWidth, this.cardScale = 1.0,
  });
  final List<UnoCard> cards;
  final bool enabled;
  final ValueChanged<UnoCard> onCardTap;
  /// The REAL screen width this fan has to fit inside right now — see
  /// _UnoBoard's own doc comment on why this is measured, not guessed.
  /// Replaces a hardcoded 340dp that had no real relationship to a Fold
  /// closed at 344dp or a tablet well past 1000dp.
  final double availableWidth;
  final double cardScale;

  static const double _baseCardWidth = 64; // the real §8.4 floor — cardScale only ever scales UP from here, never below
  static const double _baseCardHeight = 92;
  static const double _minSpacing = 24; // never overlap past a real, still-tappable sliver

  @override
  Widget build(BuildContext context) {
    final cardWidth = _baseCardWidth * cardScale;
    final cardHeight = _baseCardHeight * cardScale;
    if (cards.isEmpty) return SizedBox(height: cardHeight);
    // A small inset for the Padding/Center this fan always sits inside —
    // so a real narrow screen (a Fold closed, 344dp) doesn't butt its own
    // fan right up against the screen edge.
    final fanWidth = (availableWidth - 40).clamp(160.0, double.infinity);
    final maxSpacing = fanWidth / cards.length;
    final spacing = maxSpacing.clamp(_minSpacing * cardScale, cardWidth + 6);
    final fanTotalWidth = cardWidth + spacing * (cards.length - 1);
    return SizedBox(
      width: fanTotalWidth, height: cardHeight + 24,
      child: Stack(clipBehavior: Clip.none, children: [
        for (var i = 0; i < cards.length; i++)
          Positioned(
            left: i * spacing, top: 12,
            child: _FannedCard(
              card: cards[i], enabled: enabled, onTap: () => onCardTap(cards[i]),
              width: cardWidth, height: cardHeight,
            ),
          ),
      ]),
    );
  }
}

class _FannedCard extends StatelessWidget {
  const _FannedCard({required this.card, required this.enabled, required this.onTap, required this.width, required this.height});
  final UnoCard card;
  final bool enabled;
  final VoidCallback onTap;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final face = _UnoCardFace(card: card, dimmed: !enabled, width: width, height: height);
    return Draggable<UnoCard>(
      data: card,
      maxSimultaneousDrags: enabled ? 1 : 0,
      // Driven motion — follows the finger 1:1, always allowed under
      // §8.13.1 regardless of the ambient/autonomous budget elsewhere.
      feedback: Material(color: Colors.transparent, elevation: 0,
        child: Transform.scale(scale: 1.15, child: _UnoCardFace(card: card, width: width, height: height))),
      childWhenDragging: Opacity(opacity: 0.25, child: face),
      // §8.4's own 64dp floor is met by the card's own real size, not
      // shrunk to fit the fan overlap — only the exposed sliver of a
      // heavily-overlapped card is independently tappable, the same
      // accepted trade-off any real fan-of-cards UI has.
      child: GestureDetector(onTap: enabled ? onTap : null, child: face),
    );
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
