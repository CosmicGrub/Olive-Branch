// OLIVE BRANCH — Local Pictionary, the ad-hoc drawing game. Network
// resilience & ad-hoc mode roadmap, Track B Option 2, ad-hoc games
// expansion. Third of five new local-play activities — reuses far more
// than it builds new: live_games.dart's own Pictionary/PictionaryGuess/
// guessDrawing()/newPictionary() (already real, already tested, built for
// the video-call context but never wired to local play) and
// annotation_canvas.dart's AnnotationCanvas (same engine three other
// screens already use). Builds on local_pairing.dart for the transport,
// same pattern as game_war.dart/game_connect4.dart.
//
// THE ONE REAL DEVIATION FROM THE CALL-CONTEXT VERSION: LiveKind.pictionary
// (live_games.dart) describes real-time per-stroke sync ("he watches the
// line appear," minViableLatencyMs: 400) — this transport is explicitly
// one POST per turn, never streaming (local_session.dart's own header).
// So the drawer draws entirely offline, then sends the FINISHED picture as
// one snapshot on an explicit "Show them" tap. The guesser sees the whole
// drawing appear at once, not stroke by stroke. Deliberate, disclosed —
// not an oversight.
//
// FIXED CANVAS SIZE, not runtime coordinate normalization: the design this
// was scoped from called for sending stroke points as a 0..1 fraction of
// the sender's own canvas (since a Fold5 and a tablet render at different
// physical sizes). The simpler, equally correct fix used here: the canvas
// is a fixed 300x300 LOGICAL (dp) box on every device, via a hard
// SizedBox, not a responsive one. Flutter's logical pixels are already
// density-independent, so once both sides render the identical fixed dp
// size, raw stroke coordinates are already portable between devices with
// no normalization math needed — the cross-device-size problem the
// original design worried about doesn't arise in the first place. Chosen
// under real time pressure over building + testing runtime normalization
// tonight; revisit if this game ever needs a responsive canvas.
//
// WORD SECRECY is a payload-shape discipline, not something the type
// system enforces on its own: `word` must be non-null on the wire only on
// a solved guessResult turn — see encodeGuessResult's own doc comment and
// its dedicated test (game_pictionary_wire_test.dart) for the real
// guardrail, not just this comment.
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'annotation_canvas.dart';
import 'form_factors.dart' as ff show Posture, Viewport, postureFor;
import 'live_games.dart' show Side, LiveKind, DeckState, newDeck, draw, auditLiveView,
  Pictionary, newPictionary, guessDrawing;
import 'local_pairing.dart';

// ==================================================================
// ==== wire — pure functions, no Flutter import, independently testable ===
// ==================================================================

// REAL BUG FIXED HERE: this field used to be named 'points', which
// collides with live_games.dart's liveForbidden guardrail — a P2
// safety net that blocks 'score'/'points'/'streak'/etc. from ever
// reaching a live view. That list means "score points"; this field
// means "the x/y coordinates making up a stroke" — an innocent name
// collision, but auditLiveView() walks every key at every depth and
// can't tell the two apart, so it silently refused to send EVERY
// drawing, always, no matter what — found live on real 2-device
// hardware (the guesser's screen never received anything), not by
// `flutter analyze`/unit tests. Renamed to 'coords' to resolve the
// collision at its root without weakening the real P2 guardrail.
Map<String, dynamic> encodeStroke(Stroke s) => {
  'id': s.id, 'actorId': s.actorId, 'seq': s.seq,
  'coords': [for (final p in s.points) {'x': p.x, 'y': p.y}],
  'color': s.color, 'widthPx': s.widthPx,
};

Stroke? decodeStroke(Object? raw) {
  if (raw is! Map) return null;
  final id = raw['id'];
  final actorId = raw['actorId'];
  final seq = raw['seq'];
  final pointsRaw = raw['coords'];
  final color = raw['color'];
  final widthPx = raw['widthPx'];
  if (id is! String || actorId is! String || seq is! int || pointsRaw is! List ||
      color is! String || widthPx is! num) {
    return null;
  }
  final points = <StrokePoint>[];
  for (final p in pointsRaw) {
    if (p is! Map || p['x'] is! num || p['y'] is! num) return null;
    points.add(StrokePoint((p['x'] as num).toDouble(), (p['y'] as num).toDouble()));
  }
  return Stroke(id: id, actorId: actorId, actorKind: ActorKind.child, seq: seq,
    points: points, color: color, widthPx: widthPx.toDouble());
}

/// Drawer → guesser, once per round, sent on "Show them." [word] is never
/// carried on this shape.
Map<String, dynamic> encodeDrawingRevealed({required int rounds, required String drawerCode, required List<Stroke> strokes}) => {
  'kind': 'pictionary', 'turnKind': 'drawingRevealed', 'rounds': rounds, 'drawer': drawerCode,
  'word': null, 'strokes': [for (final s in strokes) encodeStroke(s)],
  'guessText': null, 'solved': false, 'lastGuessCorrect': null,
};

/// Guesser → drawer, one guess per turn.
Map<String, dynamic> encodeGuessSubmitted({required int rounds, required String drawerCode, required String guessText}) => {
  'kind': 'pictionary', 'turnKind': 'guessSubmitted', 'rounds': rounds, 'drawer': drawerCode,
  'word': null, 'strokes': const <Map<String, dynamic>>[], 'guessText': guessText, 'solved': false, 'lastGuessCorrect': null,
};

/// Drawer → guesser, after the drawer's own device evaluates the guess
/// locally. `word` is non-null ONLY when [solved] is true — the real
/// guardrail this file's own header calls out. A future edit that always
/// includes the word here would leak the answer to the guesser's device
/// before they've earned it; game_pictionary_wire_test.dart asserts this
/// directly, not just by comment.
Map<String, dynamic> encodeGuessResult({required int rounds, required String drawerCode, required bool solved, required bool correct, required String word}) => {
  'kind': 'pictionary', 'turnKind': 'guessResult', 'rounds': rounds, 'drawer': drawerCode,
  'word': solved ? word : null, 'strokes': const <Map<String, dynamic>>[], 'guessText': null,
  'solved': solved, 'lastGuessCorrect': correct,
};

Side? decodeSide(Object? code) => switch (code) { 'a' => Side.a, 'b' => Side.b, _ => null };
String encodeSide(Side s) => s == Side.a ? 'a' : 'b';

// ==================================================================
// ==== widget ====
// ==================================================================

class GamePictionaryScreen extends StatefulWidget {
  const GamePictionaryScreen({super.key, required this.role, required this.displayName});
  final String role;
  final String displayName;

  @override
  State<GamePictionaryScreen> createState() => _GamePictionaryScreenState();
}

enum _PicPhase { drawing, waitingForGuess, waitingForDrawing, viewing, waitingForResult }

class _GamePictionaryScreenState extends State<GamePictionaryScreen> {
  late final LocalPairingController _pairing =
      LocalPairingController(role: widget.role, displayName: widget.displayName);
  StreamSubscription<LocalTurnPayload>? _turnSub;
  final _rand = Random();
  final _guessController = TextEditingController();

  Side get _mySide => _pairing.mySide;

  Side _drawer = Side.b; // dad draws first, matching every other fixed convention in this expansion
  int _rounds = 0;
  DeckState _deck = newDeck(LiveKind.pictionary);
  String? _myWord; // only ever set on the drawer's own device
  Pictionary? _pictionary; // only meaningful on the drawer's device, for guessDrawing()
  AnnotationCanvas? _canvas; // only live while I'm the drawer
  List<Stroke> _revealedStrokes = const [];
  String? _lastGuessText;
  bool _lastGuessWasWrong = false;
  bool _celebrated = false;
  List<StrokePoint> _liveStroke = const [];
  bool _hasStarted = false;

  _PicPhase get _phase {
    if (_mySide == _drawer) {
      // Simple and total: I've either sent my finished picture this turn,
      // or I haven't. A wrong guess doesn't change this — I stay in
      // waitingForGuess, ready for another, until a correct one advances
      // the round via _drawNewWord().
      return _hasStartedDrawingThisTurn ? _PicPhase.waitingForGuess : _PicPhase.drawing;
    }
    if (_revealedStrokes.isEmpty) return _PicPhase.waitingForDrawing;
    return _awaitingResult ? _PicPhase.waitingForResult : _PicPhase.viewing;
  }

  bool _hasStartedDrawingThisTurn = false;
  bool _awaitingResult = false;

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

  void _startIfNeeded() {
    if (_hasStarted) return;
    _hasStarted = true;
    if (_mySide == _drawer) _drawNewWord();
  }

  void _drawNewWord() {
    final result = draw(_deck, _rand);
    if (result == null) return;
    setState(() {
      _deck = result.deck;
      _myWord = result.prompt;
      _pictionary = newPictionary(result.prompt, _drawer);
      _canvas = AnnotationCanvas();
      _liveStroke = const [];
      _hasStartedDrawingThisTurn = false;
      _celebrated = false;
      _lastGuessText = null;
      _lastGuessWasWrong = false;
    });
  }

  void _onPanStart(DragStartDetails d) =>
      setState(() => _liveStroke = [StrokePoint(d.localPosition.dx, d.localPosition.dy)]);

  void _onPanUpdate(DragUpdateDetails d) =>
      setState(() => _liveStroke = [..._liveStroke, StrokePoint(d.localPosition.dx, d.localPosition.dy)]);

  void _onPanEnd(DragEndDetails d) {
    final canvas = _canvas;
    if (canvas == null || _liveStroke.isEmpty) return;
    canvas.add(
      id: '${_mySide == Side.a ? 'a' : 'b'}-${DateTime.now().microsecondsSinceEpoch}',
      actorId: _mySide == Side.a ? 'ivy' : 'dad',
      actorKind: _mySide == Side.a ? ActorKind.child : ActorKind.guardian,
      points: _liveStroke,
      color: _mySide == Side.a ? '#3A7CA5' : '#B8863B',
      widthPx: 6.0,
    );
    // REAL BUG FIXED HERE: this used to also set _hasStartedDrawingThisTurn
    // = canvas.visible().isNotEmpty, which flips _phase to waitingForGuess
    // the instant the FIRST stroke ends — before "Show them" is ever
    // tapped and before _showThem() ever actually sends the picture. That
    // locked the canvas read-only after one stroke (multi-stroke drawings
    // were impossible) AND deadlocked the whole round, since the guesser's
    // device never received anything — found live on real 2-device
    // hardware, not by `flutter analyze`/unit tests. _hasStartedDrawingThisTurn
    // must only become true inside _showThem(), once the picture is
    // genuinely sent.
    setState(() => _liveStroke = const []);
  }

  Future<void> _showThem() async {
    final canvas = _canvas;
    if (canvas == null || canvas.visible().isEmpty) return;
    setState(() => _hasStartedDrawingThisTurn = true);
    await _send(encodeDrawingRevealed(rounds: _rounds, drawerCode: encodeSide(_drawer), strokes: canvas.visible()));
  }

  Future<void> _submitGuess(String text) async {
    if (text.trim().isEmpty) return;
    setState(() => _awaitingResult = true);
    await _send(encodeGuessSubmitted(rounds: _rounds, drawerCode: encodeSide(_drawer), guessText: text.trim()));
    _guessController.clear();
  }

  Future<void> _send(Map<String, dynamic> payload) async {
    final audit = auditLiveView(payload);
    if (!audit.ok) {
      debugPrint('game_pictionary: refusing to send a payload with forbidden keys: ${audit.leaks}');
      return;
    }
    await _pairing.sendTurn(payload);
  }

  void _handleIncomingTurn(LocalTurnPayload payload) {
    if (payload['kind'] != 'pictionary') return;
    final turnKind = payload['turnKind'];
    if (turnKind == 'drawingRevealed') {
      final strokesRaw = payload['strokes'];
      if (strokesRaw is! List) return;
      final strokes = <Stroke>[];
      for (final s in strokesRaw) {
        final decoded = decodeStroke(s);
        if (decoded == null) return;
        strokes.add(decoded);
      }
      if (mounted) {
        setState(() {
          _revealedStrokes = strokes;
          _lastGuessText = null;
          _lastGuessWasWrong = false;
        });
      }
      return;
    }
    if (turnKind == 'guessSubmitted') {
      final guessText = payload['guessText'];
      if (guessText is! String) return;
      final pictionary = _pictionary;
      if (pictionary == null) return;
      final result = guessDrawing(pictionary, _mySide == Side.a ? Side.b : Side.a, guessText);
      if (!result.ok || result.state == null) return;
      final newState = result.state!;
      final correct = result.correct ?? false;
      setState(() {
        _pictionary = newState;
        _lastGuessText = guessText;
        _lastGuessWasWrong = !correct;
      });
      unawaited(_send(encodeGuessResult(
        rounds: correct ? _rounds + 1 : _rounds, drawerCode: encodeSide(_drawer),
        solved: correct, correct: correct, word: _myWord ?? '')));
      if (correct) {
        // I was the drawer; I become the guesser next round.
        setState(() {
          _rounds += 1;
          _drawer = _mySide == Side.a ? Side.b : Side.a;
          _revealedStrokes = const [];
          _celebrated = false;
        });
      }
      return;
    }
    if (turnKind == 'guessResult') {
      final solved = payload['solved'] == true;
      final correct = payload['lastGuessCorrect'] == true;
      if (mounted) {
        setState(() {
          _awaitingResult = false;
          _lastGuessWasWrong = !correct;
          if (solved) {
            _rounds += 1;
            _drawer = _mySide; // I was the guesser and got it right; I draw next round.
            _revealedStrokes = const [];
            _celebrated = false;
          }
        });
        if (solved && _mySide == _drawer) _drawNewWord();
      }
    }
  }

  @override
  void dispose() {
    unawaited(_turnSub?.cancel());
    _guessController.dispose();
    _pairing.removeListener(_onPairingChanged);
    _pairing.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Measured once, outside any scroll view, matching every other game
    // in this expansion's now-shared discipline. UNLIKE those games, the
    // canvas itself (_PictionaryView's own _canvasSize) deliberately does
    // NOT scale with posture here — see this file's own header on why: a
    // fixed LOGICAL size on both devices is what lets a raw stroke
    // coordinate drawn on one device land in the same place on the
    // other's canvas with zero normalization math. Only the chrome
    // around it (outer padding) is posture-aware.
    return LayoutBuilder(builder: (context, constraints) {
      final posture = ff.postureFor(ff.Viewport(w: constraints.maxWidth, h: constraints.maxHeight));
      final Widget body;
      if (_pairing.phase == PairingPhase.error) {
        body = _MessageView(message: _pairing.errorMessage ?? "Can't play locally right now.",
          icon: Icons.error_outline);
      } else if (_pairing.phase == PairingPhase.found || _hasStarted) {
        _startIfNeeded();
        body = _PictionaryView(
          phase: _phase, isDrawer: _mySide == _drawer, word: _myWord, canvas: _canvas, liveStroke: _liveStroke,
          revealedStrokes: _revealedStrokes, rounds: _rounds, peerName: _pairing.peer?.name ?? 'the other side',
          lastGuessWasWrong: _lastGuessWasWrong, lastGuessText: _lastGuessText, celebrated: _celebrated,
          guessController: _guessController,
          onPanStart: _onPanStart, onPanUpdate: _onPanUpdate, onPanEnd: _onPanEnd,
          onShowThem: _showThem, onSubmitGuess: _submitGuess,
          onCelebrate: () => setState(() => _celebrated = true),
        );
      } else {
        body = switch (_pairing.phase) {
          PairingPhase.searching => const _Status(message: 'Looking nearby…'),
          PairingPhase.peerLost =>
            _MessageView(message: _pairing.errorMessage!, icon: Icons.wifi_off_outlined),
          PairingPhase.found => throw StateError('handled above'),
          PairingPhase.error => throw StateError('handled above'),
        };
      }
      final outerPad = posture == ff.Posture.foldTabletop ? 10.0 : 16.0;
      return Scaffold(
        appBar: AppBar(title: const Text('Draw & guess')),
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

class _PictionaryView extends StatelessWidget {
  const _PictionaryView({
    required this.phase, required this.isDrawer, required this.word, required this.canvas, required this.liveStroke,
    required this.revealedStrokes, required this.rounds, required this.peerName,
    required this.lastGuessWasWrong, required this.lastGuessText, required this.celebrated, required this.guessController,
    required this.onPanStart, required this.onPanUpdate, required this.onPanEnd,
    required this.onShowThem, required this.onSubmitGuess, required this.onCelebrate,
  });
  final _PicPhase phase;
  final bool isDrawer;
  /// The drawer's own secret prompt — null on the guesser's device (never
  /// sent over the wire, see this file's own header on word secrecy).
  /// REAL BUG FIXED HERE: this used to be computed and stored in state but
  /// never actually threaded into this view or rendered anywhere, so a
  /// real drawer had no way to see what they were supposed to draw — found
  /// by live hardware testing, not by `flutter analyze`/unit tests.
  final String? word;
  final AnnotationCanvas? canvas;
  final List<StrokePoint> liveStroke;
  final List<Stroke> revealedStrokes;
  final int rounds;
  final String peerName;
  final bool lastGuessWasWrong;
  final String? lastGuessText;
  final bool celebrated;
  final TextEditingController guessController;
  final GestureDragStartCallback onPanStart;
  final GestureDragUpdateCallback onPanUpdate;
  final GestureDragEndCallback onPanEnd;
  final VoidCallback onShowThem;
  final ValueChanged<String> onSubmitGuess;
  final VoidCallback onCelebrate;

  static const double _canvasSize = 300;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text('Round ${rounds + 1}', style: theme.textTheme.bodyMedium),
      const SizedBox(height: 8),
      Text(_headline(), style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
      if (isDrawer && word != null) ...[
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer, borderRadius: BorderRadius.circular(999),
          ),
          child: Text(word!, style: theme.textTheme.headlineSmall?.copyWith(
            color: theme.colorScheme.onPrimaryContainer, fontWeight: FontWeight.bold)),
        ),
      ],
      const SizedBox(height: 12),
      SizedBox(
        width: _canvasSize, height: _canvasSize,
        child: phase == _PicPhase.drawing
            ? _LiveCanvas(canvas: canvas, liveStroke: liveStroke, onPanStart: onPanStart,
                onPanUpdate: onPanUpdate, onPanEnd: onPanEnd)
            : _StaticCanvas(strokes: phase == _PicPhase.waitingForGuess ? (canvas?.visible() ?? const []) : revealedStrokes),
      ),
      const SizedBox(height: 16),
      if (phase == _PicPhase.drawing)
        FilledButton(
          onPressed: (canvas?.visible().isNotEmpty ?? false) ? onShowThem : null,
          style: FilledButton.styleFrom(minimumSize: const Size(64, 64)),
          child: const Text('Show them'),
        )
      else if (phase == _PicPhase.viewing)
        _GuessField(controller: guessController, onSubmit: onSubmitGuess),
    ]);
  }

  String _headline() {
    if (isDrawer) {
      return switch (phase) {
        _PicPhase.drawing => 'Draw it — $peerName will guess',
        _PicPhase.waitingForGuess => lastGuessText == null
            ? "Waiting for $peerName's guess…"
            : lastGuessWasWrong
                ? '"$lastGuessText" — not quite. Waiting for another guess…'
                : "Waiting for $peerName's guess…",
        _ => '',
      };
    }
    return switch (phase) {
      _PicPhase.waitingForDrawing => 'Waiting for $peerName to draw…',
      _PicPhase.viewing => lastGuessWasWrong ? "Not quite — try again" : 'What is it?',
      _PicPhase.waitingForResult => 'Checking your guess…',
      _ => '',
    };
  }
}

class _LiveCanvas extends StatelessWidget {
  const _LiveCanvas({required this.canvas, required this.liveStroke, required this.onPanStart,
    required this.onPanUpdate, required this.onPanEnd});
  final AnnotationCanvas? canvas;
  final List<StrokePoint> liveStroke;
  final GestureDragStartCallback onPanStart;
  final GestureDragUpdateCallback onPanUpdate;
  final GestureDragEndCallback onPanEnd;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(color: const Color(0xFFFFFDF6), borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant, width: 1.5)),
    clipBehavior: Clip.antiAlias,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: onPanStart, onPanUpdate: onPanUpdate, onPanEnd: onPanEnd,
      child: CustomPaint(size: Size.infinite, painter: _InkPainter(strokes: canvas?.visible() ?? const [], live: liveStroke)),
    ),
  );
}

class _StaticCanvas extends StatelessWidget {
  const _StaticCanvas({required this.strokes});
  final List<Stroke> strokes;
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(color: const Color(0xFFFFFDF6), borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant, width: 1.5)),
    clipBehavior: Clip.antiAlias,
    child: CustomPaint(size: Size.infinite, painter: _InkPainter(strokes: strokes, live: const [])),
  );
}

class _InkPainter extends CustomPainter {
  const _InkPainter({required this.strokes, required this.live});
  final List<Stroke> strokes;
  final List<StrokePoint> live;

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in strokes) {
      _paintPoints(canvas, s.points, _colorFrom(s.color), s.widthPx);
    }
    if (live.isNotEmpty) _paintPoints(canvas, live, Colors.black87, 6.0);
  }

  void _paintPoints(Canvas canvas, List<StrokePoint> points, Color color, double width) {
    if (points.length < 2) return;
    final paint = Paint()..color = color..strokeWidth = width..strokeCap = StrokeCap.round..style = PaintingStyle.stroke;
    final path = Path()..moveTo(points.first.x, points.first.y);
    for (final p in points.skip(1)) {
      path.lineTo(p.x, p.y);
    }
    canvas.drawPath(path, paint);
  }

  Color _colorFrom(String hex) {
    final clean = hex.replaceFirst('#', '');
    final value = int.tryParse(clean, radix: 16) ?? 0x000000;
    return Color(0xFF000000 | value);
  }

  @override
  bool shouldRepaint(_InkPainter oldDelegate) =>
      !identical(oldDelegate.strokes, strokes) || !identical(oldDelegate.live, live);
}

class _GuessField extends StatelessWidget {
  const _GuessField({required this.controller, required this.onSubmit});
  final TextEditingController controller;
  final ValueChanged<String> onSubmit;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    SizedBox(width: 200, child: TextField(controller: controller, onSubmitted: onSubmit,
      decoration: const InputDecoration(hintText: 'Your guess', border: OutlineInputBorder()))),
    const SizedBox(width: 8),
    FilledButton(onPressed: () => onSubmit(controller.text), child: const Text('Guess')),
  ]);
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
