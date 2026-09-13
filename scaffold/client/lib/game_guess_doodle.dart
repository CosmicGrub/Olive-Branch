// OLIVE BRANCH — guess the doodle. No longer UNVERIFIED — verified by CI (a Flutter toolchain now
// runs for real in tools/verify.sh's automated pipeline — also manually
// built and run via `flutter analyze` / `flutter test` this session;
// CHANGELOG v0.49.61). MASTERFILE §9.2, §9.12.4, §8.11.1, §8.13, P2. Renders
// MARKUP screen 'gamePicker' catalogue entry 'guessDoodle'.
//
// The second real consumer of annotation_canvas.dart's AnnotationCanvas
// outside doodle_desk.dart, alongside game_draw_together.dart (built in the
// same pass — see that file's own header for the shared engine/painter
// reasoning, which applies here unchanged). The difference from Draw
// Together is structural, not cosmetic: only ONE actor's strokes are ever
// live here. Whoever is currently 'the artist' (child or parent — swappable
// any time between rounds via the same small switch Draw Together uses,
// still not a turn lock) draws; the other person is the guesser and never
// touches the canvas at all — there is only one GestureDetector on this
// whole screen, and it is always attributed to the current artist's actorId.
//
// Co-op-FRAMED, minAge 5 (game_logic.dart's catalogue) — competitive: false,
// no handicaps, no score, exactly like Draw Together. The one thing that
// could look like an outcome here — "did you get it?" — is deliberately
// soft and NEVER counted: `_revealed`/`_gotIt` below are per-round UI state
// only, reset the moment a new word is picked, the same "transient, not
// tallied" shape game_story.dart's own `_readingAsOne` toggle already uses.
// There is no round counter, no correct/incorrect tally, nothing that could
// grow into a scoreboard without being obvious in review — matching
// doodle_desk.dart's own explicit precedent for this whole family of
// screens.
//
// Content source (the actual safety mechanism, per the Play Together spec):
// every word below is a fixed, in-repo, curated constant — never user-
// generated, never fetched, never free text. `guessDoodleWords` is real,
// drafted content: animals, food, everyday objects, nature, places/vehicles,
// simple actions, and a small dash of gentle fantasy — the kind of thing a
// five-year-old both recognizes and enjoys drawing or guessing. Reviewed for
// tone: silly and warm, never a values judgment, nothing frightening.
//
// A "new word"/"pass" button swaps the word freely, no penalty — matching
// this codebase's established "free, no penalty" ethos for takebacks
// elsewhere in §9.2 (game_logic.dart's own header: "Takebacks are free and
// unlimited"). Passing also starts a fresh AnnotationCanvas for the new
// round: nothing about a shared local pass-and-play word game implies
// carrying last round's drawing into the next one, and the engine has no
// "clear" operation by design (see annotation_canvas.dart's header on why
// undo/erase are scoped, not a bulk wipe) — a new round simply gets a new
// canvas instance instead.
import 'dart:math';

import 'package:flutter/material.dart';
import 'annotation_canvas.dart';
import 'annotation_canvas_view.dart';
import 'form_factors.dart' as ff;
import 'game_draw_together.dart' show InkPainterStrokes;

// ============================================================ word bank ====
// Real, drafted content — not a placeholder. Grouped for readability and
// review; guessDoodleWords below flattens them into the one list the screen
// actually draws from.

const List<String> _animalWords = <String>[
  'Dog', 'Cat', 'Elephant', 'Giraffe', 'Penguin', 'Butterfly', 'Octopus',
  'Kangaroo', 'Owl', 'Turtle', 'Dinosaur', 'Bumblebee', 'Goldfish', 'Frog',
  'Lion', 'Spider',
];

const List<String> _foodWords = <String>[
  'Pizza', 'Ice cream cone', 'Banana', 'Watermelon', 'Birthday cake',
  'Popcorn', 'Pancakes', 'Taco', 'Donut', 'Lemonade', 'Cookie', 'Sandwich',
];

const List<String> _objectWords = <String>[
  'Umbrella', 'Backpack', 'Balloon', 'Camera', 'Guitar', 'Clock', 'Glasses',
  'Key', 'Kite', 'Lamp', 'Book', 'Telephone', 'Toothbrush', 'Scissors',
];

const List<String> _natureWords = <String>[
  'Rainbow', 'Sun', 'Snowman', 'Volcano', 'Waterfall', 'Cloud', 'Campfire',
  'Thunderstorm', 'Flower', 'Tree',
];

const List<String> _placeAndVehicleWords = <String>[
  'Airplane', 'Sailboat', 'Rocket ship', 'Bicycle', 'School bus', 'Train',
  'Submarine', 'Castle', 'Lighthouse', 'Treehouse', 'Playground', 'Farm',
];

const List<String> _actionWords = <String>[
  'Sleeping', 'Dancing', 'Swimming', 'Jumping rope', 'Brushing teeth',
  'Flying', 'Laughing', 'Hiding', 'Painting', 'Singing', 'Tiptoeing',
  'Sneezing',
];

const List<String> _funWords = <String>[
  'Dragon', 'Superhero', 'Mermaid', 'Robot', 'Pirate', 'Unicorn', 'Wizard',
  'Fairy', 'Snowball fight', 'Treasure map',
];

/// The full curated bank — 86 words across seven categories, enough that
/// repeated play doesn't feel stale. See test coverage for the "real
/// variety" assertions (minimum count, no duplicates) this list must satisfy.
const List<String> guessDoodleWords = <String>[
  ..._animalWords, ..._foodWords, ..._objectWords, ..._natureWords,
  ..._placeAndVehicleWords, ..._actionWords, ..._funWords,
];

// ================================================================ widget ===

class GuessDoodleScreen extends StatefulWidget {
  const GuessDoodleScreen({super.key, this.childName = 'Ivy', this.parentName = 'Dad', this.random});
  final String childName;
  final String parentName;

  /// Injectable for tests only (mirrors api_client.dart callers' own
  /// `httpClient`-injection convention elsewhere in this codebase) —
  /// production always uses a real, unseeded Random().
  final Random? random;

  @override
  State<GuessDoodleScreen> createState() => _GuessDoodleScreenState();
}

class _GuessDoodleScreenState extends State<GuessDoodleScreen> {
  late final Random _random = widget.random ?? Random();

  AnnotationCanvas _canvas = AnnotationCanvas();
  int _idCounter = 0;
  late String _word = _pickWord();

  /// 'child' or 'parent' — whoever is currently the artist. Swappable any
  /// time; not a turn lock, and never counted across rounds.
  String _artistId = 'child';

  /// Per-round UI state only, reset by every _newWord() — see file header.
  bool _revealed = false;
  bool _gotIt = false;

  List<StrokePoint> _liveStroke = <StrokePoint>[];

  ActorKind get _artistKind => _artistId == 'child' ? ActorKind.child : ActorKind.guardian;
  String get _artistName => _artistId == 'child' ? widget.childName : widget.parentName;

  // `excluding` is only ever supplied by _newWord() (the CURRENT word, so a
  // pass never re-picks the same one back-to-back) — never by the `_word`
  // field's own initializer, which would read `_word` before it exists.
  String _pickWord({String? excluding}) {
    if (guessDoodleWords.length <= 1) return guessDoodleWords.first;
    String next;
    do {
      next = guessDoodleWords[_random.nextInt(guessDoodleWords.length)];
    } while (next == excluding);
    return next;
  }

  String _nextId() => '$_artistId-${_idCounter++}';

  void _newWord() => setState(() {
        _word = _pickWord(excluding: _word);
        _canvas = AnnotationCanvas();
        _liveStroke = <StrokePoint>[];
        _revealed = false;
        _gotIt = false;
      });

  void _reveal({required bool gotIt}) => setState(() {
        _revealed = true;
        _gotIt = gotIt;
      });

  void _onPanStart(DragStartDetails d) =>
      setState(() => _liveStroke = <StrokePoint>[StrokePoint(d.localPosition.dx, d.localPosition.dy)]);

  // In-place `.add()`, not a rebuilt list — see game_draw_together.dart's
  // identical note (`_onPanStart` already reassigns `_liveStroke` to a
  // fresh list at the start of every stroke, and `_onPanEnd` below still
  // reassigns it to a NEW empty list rather than `.clear()`ing this one).
  void _onPanUpdate(DragUpdateDetails d) => setState(() {
        _liveStroke.add(StrokePoint(d.localPosition.dx, d.localPosition.dy));
      });

  void _onPanEnd(DragEndDetails d) {
    if (_liveStroke.isEmpty || _revealed) return;
    _canvas.add(
      id: _nextId(),
      actorId: _artistId,
      actorKind: _artistKind,
      points: _liveStroke,
      color: '#2d2a32',
      widthPx: 8,
    );
    setState(() => _liveStroke = <StrokePoint>[]);
  }

  void _undo() {
    if (_canvas.undo(_artistId, DateTime.now().millisecondsSinceEpoch) != null) {
      setState(() {});
    }
  }

  void _redo() {
    if (_canvas.redo(_artistId) != null) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Guess the doodle')),
      body: SafeArea(
        child: LayoutBuilder(builder: (context, constraints) {
          final double textScale = MediaQuery.textScalerOf(context).scale(1);
          final bool wide = ff.columnsAt(
                ff.Viewport(w: constraints.maxWidth, h: constraints.maxHeight), textScale) >=
              2;

          // Only the current artist ever draws, and only before the word is
          // revealed — the guesser never gets a live gesture at all, this
          // being the one and only GestureDetector on the whole screen.
          // `drawingEnabled: !_revealed` is what `AnnotationCanvasView`
          // gates its pan callbacks on.
          final Widget canvas = AnnotationCanvasView(
            canvasKey: const Key('guessDoodleCanvas'),
            committedPainter: _CommittedSoloInkPainter(strokes: _canvas.visible()),
            livePainter: _LiveSoloInkPainter(live: _liveStroke),
            drawingEnabled: !_revealed,
            onPanStart: _onPanStart,
            onPanUpdate: _onPanUpdate,
            onPanEnd: _onPanEnd,
          );

          final Widget panel = _RoundPanel(
            artistId: _artistId,
            artistName: _artistName,
            childName: widget.childName,
            parentName: widget.parentName,
            onArtistChanged: (id) => setState(() => _artistId = id),
            word: _word,
            revealed: _revealed,
            gotIt: _gotIt,
            onGotIt: () => _reveal(gotIt: true),
            onRevealWord: () => _reveal(gotIt: false),
            onNewWord: _newWord,
            onUndo: _undo,
            onRedo: _redo,
          );

          if (wide) {
            // Same real structural split as Draw Together: Row, canvas
            // Expanded, a fixed-width side panel on the crease gutter —
            // never a resized copy of the narrow layout.
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Row(key: const Key('layoutRoot'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(child: canvas),
                const SizedBox(width: 16), // the crease gutter
                SizedBox(
                  key: const Key('roundSidePanel'),
                  width: 280,
                  child: SingleChildScrollView(child: panel),
                ),
              ]),
            );
          }
          return Padding(
            padding: const EdgeInsets.all(8),
            child: Column(key: const Key('layoutRoot'), children: [
              Expanded(child: canvas),
              const SizedBox(height: 8),
              Container(key: const Key('roundBottomBar'), child: panel),
            ]),
          );
        }),
      ),
    );
  }
}

/// Shared by both painters below — follows doodle_desk.dart's own private
/// _InkPainter shape (see game_draw_together.dart's identical note) — one
/// fixed ink color/width here since this screen has no color picker, just a
/// drawer and a guesser.
void _paintPolyline(Canvas canvas, List<StrokePoint> pts, Color color, double width) {
  if (pts.isEmpty) return;
  final Paint paint = Paint()
    ..color = color
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..style = PaintingStyle.stroke;
  if (pts.length == 1) {
    canvas.drawCircle(Offset(pts.first.x, pts.first.y), width / 2, paint..style = PaintingStyle.fill);
    return;
  }
  final Path path = Path()..moveTo(pts.first.x, pts.first.y);
  for (final StrokePoint p in pts.skip(1)) {
    path.lineTo(p.x, p.y);
  }
  canvas.drawPath(path, paint);
}

const Color _soloInkColor = Color(0xFF2D2A32);
const double _soloLiveWidth = 8;

/// Paints only the committed strokes. Implements game_draw_together.dart's
/// `InkPainterStrokes` — the same small, typed, `dynamic`-free test seam,
/// reused rather than redeclared. See annotation_canvas_view.dart's own
/// header and game_draw_together.dart's `_CommittedInkPainter` (identical
/// split, applied here too) for why this is separated from the live layer
/// and wrapped in a RepaintBoundary: `strokes` comes from
/// `AnnotationCanvas.visible()`'s cache, so `shouldRepaint` can actually say
/// no between drag frames instead of repainting the whole stroke history
/// every pointer-move.
class _CommittedSoloInkPainter extends CustomPainter implements InkPainterStrokes {
  const _CommittedSoloInkPainter({required this.strokes});
  @override
  final List<Stroke> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    for (final Stroke s in strokes) {
      _paintPolyline(canvas, s.points, _soloInkColor, s.widthPx);
    }
  }

  @override
  bool shouldRepaint(covariant _CommittedSoloInkPainter oldDelegate) =>
      !identical(oldDelegate.strokes, strokes);
}

/// Paints only the in-progress live stroke. Always repaints -- see
/// game_draw_together.dart's `_LiveInkPainter` for why a length/identical
/// check on `live` cannot work once `_onPanUpdate` mutates `_liveStroke` in
/// place (Fix 11): both the old and new painter end up aliasing the exact
/// same, already-mutated `List<StrokePoint>` object, so neither check can
/// ever observe a change mid-stroke. This layer is small and isolated by
/// the committed layer's own RepaintBoundary, so an unconditional repaint
/// here is the correct, cheap choice, not a missed optimization.
class _LiveSoloInkPainter extends CustomPainter {
  const _LiveSoloInkPainter({required this.live});
  final List<StrokePoint> live;

  @override
  void paint(Canvas canvas, Size size) {
    _paintPolyline(canvas, live, _soloInkColor, _soloLiveWidth);
  }

  @override
  bool shouldRepaint(covariant _LiveSoloInkPainter oldDelegate) => true;
}

class _RoundPanel extends StatelessWidget {
  const _RoundPanel({
    required this.artistId,
    required this.artistName,
    required this.childName,
    required this.parentName,
    required this.onArtistChanged,
    required this.word,
    required this.revealed,
    required this.gotIt,
    required this.onGotIt,
    required this.onRevealWord,
    required this.onNewWord,
    required this.onUndo,
    required this.onRedo,
  });

  final String artistId;
  final String artistName;
  final String childName;
  final String parentName;
  final ValueChanged<String> onArtistChanged;
  final String word;
  final bool revealed;
  final bool gotIt;
  final VoidCallback onGotIt;
  final VoidCallback onRevealWord;
  final VoidCallback onNewWord;
  final VoidCallback onUndo;
  final VoidCallback onRedo;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text("Who's drawing?", style: Theme.of(context).textTheme.labelMedium),
      const SizedBox(height: 4),
      SegmentedButton<String>(
        style: SegmentedButton.styleFrom(minimumSize: const Size(64, 48)),
        segments: <ButtonSegment<String>>[
          ButtonSegment<String>(value: 'child', label: Text(childName)),
          ButtonSegment<String>(value: 'parent', label: Text(parentName)),
        ],
        selected: <String>{artistId},
        onSelectionChanged: (s) => onArtistChanged(s.first),
      ),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: scheme.tertiaryContainer, borderRadius: BorderRadius.circular(12)),
        child: revealed
            ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(gotIt ? 'Nice — it was "$word"!' : 'It was "$word".',
                    key: const Key('revealText'),
                    style: TextStyle(fontWeight: FontWeight.w700, color: scheme.onTertiaryContainer)),
              ])
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('$artistName is drawing:',
                    style: TextStyle(fontSize: 12, color: scheme.onTertiaryContainer)),
                const SizedBox(height: 2),
                Text(word,
                    key: const Key('secretWord'),
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: scheme.onTertiaryContainer)),
                const SizedBox(height: 4),
                Text('Keep this part facing the artist!',
                    style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: scheme.onTertiaryContainer)),
              ]),
      ),
      const SizedBox(height: 12),
      if (!revealed) ...[
        SizedBox(
            width: double.infinity, height: 48,
            child: FilledButton.icon(onPressed: onGotIt, icon: const Icon(Icons.celebration_outlined), label: const Text('I got it!'))),
        const SizedBox(height: 8),
        SizedBox(
            width: double.infinity, height: 48,
            child: OutlinedButton(onPressed: onRevealWord, child: const Text('Reveal the word'))),
        const SizedBox(height: 8),
      ],
      SizedBox(
          width: double.infinity, height: 48,
          child: FilledButton.tonal(onPressed: onNewWord, child: const Text('New word — no penalty'))),
      const SizedBox(height: 8),
      // Expanded, not natural sizing — see game_draw_together.dart's
      // identical note: the same row must fit a full-width bottom bar AND a
      // ~260px side panel. Short "Undo"/"Redo" labels carry the WHO in a
      // tooltip; the artist switch just above already shows who is active.
      Row(children: [
        Expanded(
            child: _RoundIconButton(
                icon: Icons.undo, label: 'Undo',
                tooltip: "Undoes $artistName's own last stroke only", onTap: onUndo)),
        const SizedBox(width: 12),
        Expanded(
            child: _RoundIconButton(
                icon: Icons.redo, label: 'Redo',
                tooltip: "Redoes $artistName's own last undo", onTap: onRedo)),
      ]),
    ]);
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, required this.label, required this.tooltip, required this.onTap});
  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: SizedBox(
          height: 48,
          width: double.infinity,
          child: OutlinedButton.icon(onPressed: onTap, icon: Icon(icon), label: Text(label)),
        ),
      );
}
