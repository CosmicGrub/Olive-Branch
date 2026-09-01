// OLIVE BRANCH — copy the pattern. Verified by CI (a Flutter toolchain now
// runs for real in tools/verify.sh's automated pipeline — also manually
// built and run via `flutter analyze` / `flutter test` this session;
// CHANGELOG v0.49.61). MASTERFILE §9.2, §8.11.1, §8.13, §8.4, P2. Renders
// MARKUP screen 'gamePicker' catalogue entry 'copyPattern'.
//
// Play Together Phase 1, Batch C (docs/superpowers/specs/
// 2026-08-20-play-together-phase1-design.md) — first of two younger-age,
// icon/color/shape-based activities, minAge 2. This is the youngest-facing
// screen this codebase has ever shipped, so its two governing constraints
// are stricter than any other activity's:
//
// ZERO-TEXT GAMEPLAY, not just a claim. `patternTiles` below is four
// color+icon pairs; nothing about completing a round requires reading a
// word. `PatternTile.name` exists only for a screen reader `Semantics`
// label and a parent-facing `Tooltip` — never rendered as on-screen static
// label text (see game_copy_pattern_test.dart's own assertion that no
// tile's `name` ever appears as visible text). The captions this screen
// DOES show ("Watch closely!", "Your turn...") are for the PARENT, who is
// narrating out loud per the spec's own "solo-with-parent-prompting"
// framing for this activity — a pre-reader completes every round using
// only the tap-grid's icons and colors, never the words around them.
//
// SELF-SCALING DIFFICULTY IS THE PATTERN LENGTH, NOTHING ELSE. A correct
// full round grows the pattern by exactly one tile and plays again — no
// parent-set difficulty dial, matching the spec's own reasoning: this is
// co-op with nothing to be behind at, so §9.2's handicap machinery (which
// exists specifically for competitive games) does not apply here —
// `competitive: false, handicaps: []`, `story`'s own catalogue shape.
//
// P2 — no score, streak, or "best pattern length" is EVER shown or
// persisted across rounds or sessions. The CURRENT pattern length is fine
// to show WHILE actively playing — that is live gameplay state, the same
// category as `20 Questions`'s live yes/no tally, not a record — and it is
// never framed as "your best" or compared to any prior round.
//
// MOTION (§8.13): pattern playback is a chain of CONSEQUENCE animations,
// never a loop. It plays exactly once per round, and every trigger for a
// new playback run is itself a consequence of something she just did (a
// correct full round, or a wrong tap's gentle retry) — the ONE exception
// being the very first playback of the very first round, triggered by the
// screen opening, which is the same "opens straight into the thing" posture
// `game_would_you_rather.dart`'s first prompt already takes. Every
// individual highlight transition (`_transitionDuration`, 180ms) is
// comfortably under the 400ms consequence-motion budget, and only ONE tile
// animates at a time during playback — well inside §8.13.6's "two moving
// things at once" ceiling.
//
// WRONG-TAP HANDLING — an open design decision, made conservatively per
// this run's overnight-autonomous instructions (the spec does not say what
// a wrong tap should do). A wrong tap does NOT shrink the pattern and does
// NOT restart it at length 1 — it resets INPUT PROGRESS ONLY, and the exact
// same pattern replays from its first tile. This is the safest reading
// available: it never frames a mistake as a setback ("you lost your
// progress"), matching this codebase's house style for handling a child's
// mistakes gently (word search's eight lives, checkers' no punishment,
// `game_dotsboxes.dart`'s "a competitive game closes with a plain factual
// line, never a verdict") — even more conservatively here, since this
// activity is co-op AND minAge 2. There is deliberately no red "wrong!"
// color anywhere on this screen; the only feedback is a calm caption
// ("Let's watch that again!") and the pattern playing again.
//
// Device-adaptive layout (§8.11.1, real posture logic via
// `form_factors.dart`'s `columnsAt()`, never a hand-rolled width check),
// per the spec's own words for this activity specifically: "single column
// → pattern display and tap-grid stacked vertically; 2+ columns →
// side-by-side, so a parent narrating 'what comes next' and the child's tap
// target are both visible without scrolling." Unlike Find It (the other
// Batch C activity), device posture here changes LAYOUT only — the pattern
// length is what makes the game harder, not the device it runs on.
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'form_factors.dart' as ff;

// ================================================================ engine ===

/// One tap-grid target. Colour AND icon differ across every tile,
/// deliberately redundant, so the game also works for a child who cannot
/// yet reliably distinguish the colors alone. [name] is never rendered as
/// static on-screen label text — see this file's own header.
class PatternTile {
  const PatternTile(this.icon, this.color, this.name);
  final IconData icon;
  final Color color;
  final String name;
}

/// Four tiles — the whole of this game's fixed, curated vocabulary.
const List<PatternTile> patternTiles = <PatternTile>[
  PatternTile(Icons.circle, Color(0xFFE53935), 'red circle'),
  PatternTile(Icons.square_rounded, Color(0xFF1E88E5), 'blue square'),
  PatternTile(Icons.star_rounded, Color(0xFFF9A825), 'yellow star'),
  PatternTile(Icons.favorite, Color(0xFF43A047), 'green heart'),
];

/// Appends exactly one new random tile index to [pattern] — the whole of
/// this game's difficulty curve. `Random` is always caller-supplied so
/// tests are fully deterministic; production always uses a real, unseeded
/// `Random()`.
List<int> growPattern(List<int> pattern, Random random) =>
    List<int>.of(pattern)..add(random.nextInt(patternTiles.length));

/// The very first round: a pattern of length exactly 1.
List<int> firstPattern(Random random) => growPattern(const <int>[], random);

enum TapOutcome { correctContinue, correctRoundComplete, wrong }

/// Pure, testable — no widget, no timer. [inputCount] is how many taps in
/// THIS round have already matched; [tappedIndex] is the tile just tapped.
TapOutcome checkTap({required List<int> pattern, required int inputCount, required int tappedIndex}) {
  if (pattern[inputCount] != tappedIndex) return TapOutcome.wrong;
  return inputCount + 1 == pattern.length ? TapOutcome.correctRoundComplete : TapOutcome.correctContinue;
}

// ================================================================ widget ===

/// Every individual highlight/press transition — comfortably under §8.13's
/// 400ms consequence-motion budget.
const Duration _transitionDuration = Duration(milliseconds: 180);

enum _Phase { playback, input, wrongPause }

class CopyPatternScreen extends StatefulWidget {
  const CopyPatternScreen({
    super.key,
    this.childName = 'Ivy',
    this.random,
    this.highlightDuration = const Duration(milliseconds: 480),
    this.stepGap = const Duration(milliseconds: 260),
    this.wrongPauseDuration = const Duration(milliseconds: 700),
  });

  /// Used only in the "your turn" caption's warm, personal framing.
  final String childName;

  /// Injectable for tests only, matching `game_guess_doodle.dart`'s own
  /// convention — production always uses a real, unseeded `Random()`.
  final Random? random;

  /// How long each tile stays visually shown during playback before the
  /// next one takes its turn. Tests pass `Duration.zero` for instant,
  /// deterministic playback — the same injectable-delay convention
  /// `game_tictactoe.dart`'s `botThinkDelay` already established.
  final Duration highlightDuration;

  /// The calm, tile-off gap between one playback step and the next.
  final Duration stepGap;

  /// How long the gentle "let's try that again" pause lasts before the
  /// SAME pattern replays after a wrong tap.
  final Duration wrongPauseDuration;

  @override
  State<CopyPatternScreen> createState() => _CopyPatternScreenState();
}

class _CopyPatternScreenState extends State<CopyPatternScreen> {
  late final Random _random = widget.random ?? Random();
  late List<int> _pattern = firstPattern(_random);
  _Phase _phase = _Phase.playback;
  int _playbackStep = -1;
  int _inputCount = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_startPlayback());
  }

  Future<void> _startPlayback() async {
    setState(() {
      _phase = _Phase.playback;
      _playbackStep = -1;
    });
    for (var i = 0; i < _pattern.length; i++) {
      if (!mounted) return;
      setState(() => _playbackStep = i);
      await Future<void>.delayed(widget.highlightDuration);
      if (!mounted) return;
      setState(() => _playbackStep = -1);
      await Future<void>.delayed(widget.stepGap);
    }
    if (!mounted) return;
    setState(() {
      _phase = _Phase.input;
      _inputCount = 0;
    });
  }

  Future<void> _onTileTap(int tileIndex) async {
    if (_phase != _Phase.input) return;
    final TapOutcome outcome =
        checkTap(pattern: _pattern, inputCount: _inputCount, tappedIndex: tileIndex);
    switch (outcome) {
      case TapOutcome.correctContinue:
        setState(() => _inputCount++);
      case TapOutcome.correctRoundComplete:
        setState(() => _pattern = growPattern(_pattern, _random));
        unawaited(_startPlayback());
      case TapOutcome.wrong:
        setState(() => _phase = _Phase.wrongPause);
        await Future<void>.delayed(widget.wrongPauseDuration);
        if (!mounted) return;
        // Same _pattern, unchanged — a genuine reset of INPUT PROGRESS
        // only, per this file's own header.
        unawaited(_startPlayback());
    }
  }

  String get _caption => switch (_phase) {
        _Phase.playback => 'Watch closely!',
        _Phase.input => 'Your turn, ${widget.childName} — tap it back!',
        _Phase.wrongPause => "Let's watch that again!",
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Copy the pattern')),
      body: SafeArea(
        child: LayoutBuilder(builder: (context, constraints) {
          final double textScale = MediaQuery.textScalerOf(context).scale(1);
          // Real §8.11.1 posture logic, not a raw width check — matches
          // every other Play Together screen's use of columnsAt().
          final bool wide = ff.columnsAt(
                ff.Viewport(w: constraints.maxWidth, h: constraints.maxHeight), textScale) >=
              2;

          final Widget display = _PatternDisplay(
            caption: _caption,
            patternLength: _pattern.length,
            shown: _phase == _Phase.playback && _playbackStep >= 0
                ? patternTiles[_pattern[_playbackStep]]
                : null,
          );
          final Widget grid = _TapGrid(
            interactive: _phase == _Phase.input,
            onTap: _onTileTap,
          );

          if (wide) {
            // A genuinely different widget tree, not a resized copy of the
            // narrow one — Row, both panels Expanded, the gutter on the
            // crease (`foldMain`'s own documented convention), so a parent
            // narrating "what comes next" from the display and the child's
            // tap target are both visible without scrolling, per this
            // activity's own line in the spec.
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Row(key: const Key('layoutRoot'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Expanded(key: const Key('patternDisplaySide'), child: display),
                const SizedBox(width: 16), // the crease gutter
                Expanded(key: const Key('tapGridSide'), child: grid),
              ]),
            );
          }
          return Padding(
            padding: const EdgeInsets.all(16),
            // stretch, not the Column default (center) — a Column's cross
            // axis (width, here) is otherwise LOOSE, and _PatternDisplay's
            // Container would shrink-wrap to its narrowest child (a line
            // of text) instead of filling the screen. Row above doesn't
            // need this reasoning stated twice — it already sets stretch.
            child: Column(
              key: const Key('layoutRoot'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: display),
                const SizedBox(height: 16),
                Expanded(flex: 2, child: grid),
              ],
            ),
          );
        }),
      ),
    );
  }
}

class _PatternDisplay extends StatelessWidget {
  const _PatternDisplay({required this.caption, required this.patternLength, required this.shown});

  final String caption;
  final int patternLength;

  /// The tile currently being demonstrated during playback, or null when
  /// nothing should be highlighted (input phase, wrong-pause, or the gap
  /// between two playback steps).
  final PatternTile? shown;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      key: const Key('patternDisplayPanel'),
      padding: const EdgeInsets.all(16),
      decoration:
          BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(20)),
      child: Column(children: <Widget>[
        Expanded(
          child: Center(
            // Consequence motion only, driven entirely by playback state —
            // never a loop (§8.13.1). Both transitions settle in 180ms.
            child: AnimatedScale(
              scale: shown != null ? 1.15 : 0.85,
              duration: _transitionDuration,
              curve: Curves.easeOut,
              child: AnimatedOpacity(
                opacity: shown != null ? 1.0 : 0.3,
                duration: _transitionDuration,
                child: Icon(shown?.icon ?? Icons.circle, size: 84, color: shown?.color ?? scheme.outlineVariant),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(caption,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        // Live gameplay state (P2) — the CURRENT length, never a "best"
        // and never persisted past this round. For the parent's reference,
        // not required reading for the child (see this file's header).
        Text('Pattern length: $patternLength',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
      ]),
    );
  }
}

class _TapGrid extends StatelessWidget {
  const _TapGrid({required this.interactive, required this.onTap});

  final bool interactive;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) => GridView.count(
        key: const Key('patternTapGrid'),
        crossAxisCount: 2,
        childAspectRatio: 1,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        children: <Widget>[
          for (var i = 0; i < patternTiles.length; i++)
            _Tile(
              index: i,
              tile: patternTiles[i],
              onTap: interactive ? () => onTap(i) : null,
            ),
        ],
      );
}

class _Tile extends StatelessWidget {
  const _Tile({required this.index, required this.tile, required this.onTap});

  final int index;
  final PatternTile tile;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tile.name,
        child: Semantics(
          button: true,
          label: tile.name,
          child: Material(
            key: Key('patternTile-$index'),
            // §8.4 — generously above the 64dp pre-reader floor; every
            // tile fills roughly half the available panel, comfortably
            // over a hundred logical px on any supported device.
            color: onTap != null ? tile.color : tile.color.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(24),
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: onTap,
              child: Center(child: Icon(tile.icon, size: 48, color: Colors.white)),
            ),
          ),
        ),
      );
}
