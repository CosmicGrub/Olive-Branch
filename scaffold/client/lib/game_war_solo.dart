// OLIVE BRANCH — War against the game, on her own. No longer UNVERIFIED — verified by CI
// (test/game_war_solo_test.dart). Prototype k.g.war (mod-child.js). MASTERFILE §2.1 P1-P3.
//
// The two-device War (game_war.dart GameWarScreen) needs a second device on the table. This is the same game
// with a CPU seat on one screen: she flips, the game flips back, the higher card takes both, a tie takes the
// next flip. It reuses WarView from game_war.dart, so the cards, the flip reveal and the "pile is a picture,
// not a number" rule are the same ones. Nothing here keeps or shows a tally; the end line is "Good game."
// A game is level after warSoloFlipCap flips, so a child is never left in a game that cannot end.
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'access_scope.dart' show reduceMotionOf;
import 'form_factors.dart' as ff;
import 'game_logic.dart' show neutralGrownUp, asSubject;
import 'live_games.dart' show Side;
import 'game_solo_logic.dart';
import 'game_war.dart' show WarPhase, WarState, WarView;

class GameWarVsGame extends StatefulWidget {
  const GameWarVsGame({super.key, this.peerName = neutralGrownUp, this.seed, this.revealMs = 700});

  /// What the other seat is called on the table. The game itself, not a grown-up, is playing, so the default is
  /// the neutral line; the picker passes 'the game'.
  final String peerName;
  final int? seed;

  /// How long both cards stay face up before the winner takes them.
  final int revealMs;

  @override
  State<GameWarVsGame> createState() => _GameWarVsGameState();
}

class _GameWarVsGameState extends State<GameWarVsGame> {
  late final Random _rng = Random(widget.seed);
  late WarSolo _s = newWarSolo(_rng);
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _flip() {
    if (_s.phase != WarSoloPhase.ready) return;
    setState(() => _s = warSoloFlip(_s));
    if (_s.phase == WarSoloPhase.revealed) {
      _timer?.cancel();
      final int ms = reduceMotionOf(context) ? widget.revealMs + 500 : widget.revealMs;
      _timer = Timer(Duration(milliseconds: ms), () {
        if (!mounted) return;
        setState(() => _s = warSoloResolve(_s));
      });
    }
  }

  void _again() {
    _timer?.cancel();
    setState(() => _s = newWarSolo(_rng));
  }

  /// The shared two-device view model, filled from both piles. Both cards stay face up while [WarSoloPhase.revealed].
  WarState _view() {
    final bool done = _s.phase == WarSoloPhase.done;
    return WarState(
      myPile: _s.mine,
      roundNumber: _s.round,
      pot: _s.pot,
      myPending: _s.myTable.isEmpty ? null : _s.myTable,
      // While the cards wait to be resolved WarView must show both as revealed and offer no flip; once
      // resolved the tables are empty and the view offers the flip again.
      theirPending: _s.theirTable.isEmpty ? null : _s.theirTable,
      phase: done ? (_s.ended == 'won' ? WarPhase.won : _s.ended == 'lost' ? WarPhase.lost : WarPhase.drawnOut) : WarPhase.playing,
      lastRoundNote: _s.note,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool done = _s.phase == WarSoloPhase.done;
    return Scaffold(
      appBar: AppBar(title: const Text('War')),
      body: SafeArea(child: LayoutBuilder(builder: (BuildContext context, BoxConstraints c) {
        final double textScale = MediaQuery.textScalerOf(context).scale(1);
        final bool wide = ff.columnsAt(ff.Viewport(w: c.maxWidth, h: c.maxHeight), textScale) >= 2;
        final Widget content = Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          Text('You against ${widget.peerName == neutralGrownUp ? 'the game' : widget.peerName}',
            key: const Key('warSoloLine'), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          WarView(
            key: const Key('warSoloView'),
            state: _view(), mySide: Side.a,
            peerName: widget.peerName == neutralGrownUp ? 'The game' : asSubject(widget.peerName),
            onFlip: _flip, cardScale: wide ? 1.16 : 1.0,
          ),
          if (done) ...<Widget>[
            const SizedBox(height: 20),
            SizedBox(height: 48, child: FilledButton.icon(
              key: const Key('warSoloAgain'), onPressed: _again,
              icon: const Icon(Icons.refresh), label: const Text('Play again'))),
          ],
        ]);
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: ff.comfortableReadingWidth), child: content)),
        );
      })),
    );
  }
}
