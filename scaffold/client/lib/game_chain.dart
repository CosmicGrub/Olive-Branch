// OLIVE BRANCH — word chain ("I went to the market..."). UNVERIFIED (no
// Flutter toolchain in tools/verify.sh's automated pipeline — manually built
// and run via `flutter analyze` / `flutter test` this session). MASTERFILE
// §9.2 (Shipped v0.19.0), P2. Renders MARKUP screen 'chain'.
//
// A 1:1 semantic port of the chain section of packages/games/src/games3.ts
// (Side, ChainStep, ChainGame, ChainError, newChain, addStep, recallStep,
// chainView, chainArtifact) — same shapes, same function names, kept close
// enough to audit side by side, the same discipline lock_controller.dart
// already applies to packages/child-lock/src/lock.ts.
//
// One intentional adaptation: the TS `Side = 'A' | 'B'` union is ported here
// as `ChainSide`, not the bare name `Side`. game_story.dart and game_hunt.dart
// each port their own two-sided union from the same TS package; giving each
// its own name keeps a future screen that imports more than one of these
// files from hitting an ambiguous top-level `Side` — a problem the TS source
// never faces because each file there is its own module with its own export.
//
// §9.2's whole point for this game is that it GROWS ACROSS CUSTODY WEEKS
// rather than resetting per session — the opposite of every other game in
// the catalogue. A real backend would persist `ChainGame` server-side and
// replay it into whichever device opens the screen next, days or weeks
// apart (see api_client.dart — no such backend exists yet). `_seedAcrossWeeks`
// below builds a starting chain by calling the SAME ported addStep() /
// recallStep() functions a server-backed history would have accumulated —
// an honest stand-in for persistence, not a hand-authored fake state.
//
// P2 applies throughout: no streak, no score, no "you lost". A dropped
// recall ends the chain COOPERATIVELY — chainView().closing reads "You two
// got to N together," never who broke it.
import 'dart:async';
import 'package:flutter/material.dart';

// =========================================================== ported logic ===
// packages/games/src/games3.ts — the Simon/chain section.

enum ChainSide { a, b } // a = child, b = parent (TS: 'A' | 'B')

enum ChainPhase { building, recalling }

enum ChainError { notYourTurn, gameOver, wrongPhase, emptyStep }

class ChainStep {
  const ChainStep({required this.side, required this.label, this.voiceArtifactId});
  final ChainSide side;
  final String label;
  /// media_artifact id of the parent's voice, when present (§9.2 — "the
  /// memory game is made out of the parent"). No recording pipeline exists in
  /// this preview build, so nothing here ever sets it; kept for shape
  /// fidelity with the TS type.
  final String? voiceArtifactId;
}

class ChainEnded {
  const ChainEnded({required this.atStep, required this.by});
  final int atStep;
  final ChainSide by;
}

class ChainGame {
  const ChainGame({required this.steps, required this.turn, required this.phase,
    required this.recallIndex, this.ended});
  final List<ChainStep> steps;
  final ChainSide turn;
  final ChainPhase phase;
  final int recallIndex;
  final ChainEnded? ended;

  ChainGame copyWith({List<ChainStep>? steps, ChainSide? turn, ChainPhase? phase,
      int? recallIndex, ChainEnded? ended}) => ChainGame(
    steps: steps ?? this.steps,
    turn: turn ?? this.turn,
    phase: phase ?? this.phase,
    recallIndex: recallIndex ?? this.recallIndex,
    ended: ended ?? this.ended,
  );
}

ChainGame newChain() => const ChainGame(
  steps: <ChainStep>[], turn: ChainSide.b, phase: ChainPhase.building, recallIndex: 0);

class StepResult {
  const StepResult.ok(this.state) : ok = true, reason = null;
  const StepResult.err(this.reason) : ok = false, state = null;
  final bool ok;
  final ChainGame? state;
  final ChainError? reason;
}

/// Add a step. The chain is built one item per turn — a day apart in
/// production, exactly the cadence the async model wants.
StepResult addStep(ChainGame g, ChainSide side, String label, {String? voiceArtifactId}) {
  if (g.ended != null) return const StepResult.err(ChainError.gameOver);
  if (side != g.turn) return const StepResult.err(ChainError.notYourTurn);
  if (g.phase != ChainPhase.building) return const StepResult.err(ChainError.wrongPhase);
  final String trimmed = label.trim();
  if (trimmed.isEmpty) return const StepResult.err(ChainError.emptyStep);
  return StepResult.ok(g.copyWith(
    steps: <ChainStep>[...g.steps, ChainStep(side: side, label: trimmed, voiceArtifactId: voiceArtifactId)],
    turn: side == ChainSide.a ? ChainSide.b : ChainSide.a,
    phase: ChainPhase.recalling,
    recallIndex: 0,
  ));
}

class RecallResult {
  const RecallResult.ok(this.state, this.correct) : ok = true, reason = null;
  const RecallResult.err(this.reason) : ok = false, state = null, correct = null;
  final bool ok;
  final ChainGame? state;
  final bool? correct;
  final ChainError? reason;
}

/// Repeat the chain back, one step at a time.
///
/// A wrong step ends the game COOPERATIVELY. There is no "you failed" — the
/// chain simply stops, and what is recorded is how far the two of them got
/// together. `ChainEnded.by` exists for the transcript, never for a scoreboard.
RecallResult recallStep(ChainGame g, ChainSide side, String label) {
  if (g.ended != null) return const RecallResult.err(ChainError.gameOver);
  if (side != g.turn) return const RecallResult.err(ChainError.notYourTurn);
  if (g.phase != ChainPhase.recalling) return const RecallResult.err(ChainError.wrongPhase);

  final ChainStep? want = g.recallIndex < g.steps.length ? g.steps[g.recallIndex] : null;
  if (want == null || want.label.toLowerCase() != label.trim().toLowerCase()) {
    return RecallResult.ok(
      g.copyWith(ended: ChainEnded(atStep: g.recallIndex, by: side)), false);
  }
  final int next = g.recallIndex + 1;
  if (next < g.steps.length) {
    return RecallResult.ok(g.copyWith(recallIndex: next), true);
  }
  // Whole chain repeated — now this player adds one. Turn deliberately
  // unchanged: the player who just finished recalling is the one who adds.
  return RecallResult.ok(g.copyWith(phase: ChainPhase.building, recallIndex: 0), true);
}

class ChainView {
  const ChainView({required this.length, required this.whoseTurn, required this.phase,
    required this.prompt, required this.visibleSteps, this.closing});
  final int length;
  final ChainSide whoseTurn;
  final ChainPhase phase;
  final String prompt;
  final List<String> visibleSteps;
  final String? closing;
}

/// What the child sees. Cooperative language throughout.
ChainView chainView(ChainGame g) => ChainView(
  length: g.steps.length,
  whoseTurn: g.turn,
  phase: g.phase,
  prompt: g.ended != null ? 'The chain stopped there.'
    : g.phase == ChainPhase.building ? 'Add one more thing.'
    : 'Say them back — ${g.recallIndex + 1} of ${g.steps.length}.',
  // During recall the list is hidden; that IS the game.
  visibleSteps: g.phase == ChainPhase.building || g.ended != null
    ? g.steps.map((ChainStep s) => s.label).toList()
    : const <String>[],
  closing: g.ended == null ? null
    // Shared, never comparative. "You got to eleven" — not who dropped it.
    : 'You two got to ${g.ended!.atStep} together.',
);

class ChainArtifact {
  const ChainArtifact({required this.title, required this.body});
  final String title;
  final String body;
}

/// §9.8 — a long chain is worth keeping.
ChainArtifact? chainArtifact(ChainGame g) {
  if (g.steps.length < 5) return null;
  return ChainArtifact(title: 'A chain of ${g.steps.length}',
    body: g.steps.map((ChainStep s) => s.label).join(', '));
}

// ================================================================= widget ===

class GameChainScreen extends StatefulWidget {
  const GameChainScreen({super.key, this.childName = 'Ivy', this.parentName = 'Dad'});
  final String childName;
  final String parentName;

  @override
  State<GameChainScreen> createState() => _GameChainScreenState();
}

class _GameChainScreenState extends State<GameChainScreen> {
  late ChainGame _game;
  final TextEditingController _controller = TextEditingController();
  // Drives a single, short "consequence" highlight after a move — never
  // looping, never autonomous (§8.13.1, §8.13.6).
  bool _justMoved = false;
  Timer? _pulseTimer;

  @override
  void initState() {
    super.initState();
    _game = _seedAcrossWeeks();
  }

  String _name(ChainSide s) => s == ChainSide.a ? widget.childName : widget.parentName;

  /// Builds a chain that already spans several turns, using ONLY the ported
  /// addStep()/recallStep() functions above — see the file header for why
  /// this stands in for cross-device persistence rather than a backend call.
  ChainGame _seedAcrossWeeks() {
    const List<(ChainSide, String)> turns = <(ChainSide, String)>[
      (ChainSide.b, 'a banana'),
      (ChainSide.a, 'my blue kite'),
      (ChainSide.b, "grandma's biscuits"),
      (ChainSide.a, 'a squeaky toy for the dog'),
      (ChainSide.b, 'some stripy socks'),
      (ChainSide.a, 'a jar of honey'),
    ];
    ChainGame g = newChain();
    for (final (ChainSide side, String label) in turns) {
      // Replay the recall the current turn-holder owes before they may add —
      // exactly what really playing it, turn by turn, would have produced.
      while (g.phase == ChainPhase.recalling) {
        final ChainStep step = g.steps[g.recallIndex];
        final RecallResult r = recallStep(g, g.turn, step.label);
        g = r.state!;
      }
      final StepResult r = addStep(g, side, label);
      g = r.state!;
    }
    return g;
  }

  void _pulse() {
    _pulseTimer?.cancel();
    setState(() => _justMoved = true);
    _pulseTimer = Timer(const Duration(milliseconds: 320), () {
      if (mounted) setState(() => _justMoved = false);
    });
  }

  void _submit() {
    final String text = _controller.text.trim();
    if (text.isEmpty) return;
    if (_game.phase == ChainPhase.building) {
      final StepResult r = addStep(_game, _game.turn, text);
      if (!r.ok) return;
      setState(() { _game = r.state!; _controller.clear(); });
    } else {
      final RecallResult r = recallStep(_game, _game.turn, text);
      if (!r.ok) return;
      setState(() { _game = r.state!; _controller.clear(); });
    }
    _pulse();
  }

  void _startNewChain() => setState(() { _game = newChain(); _controller.clear(); });

  @override
  void dispose() {
    _pulseTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ChainView view = chainView(_game);
    final ChainArtifact? artifact = chainArtifact(_game);
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool ended = _game.ended != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Word chain')),
      body: SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('One thing each, and the list keeps going',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        const Text('Grown a little more every time you two play.',
          style: TextStyle(fontSize: 12.5, color: Colors.black54)),
        const SizedBox(height: 16),
        AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _justMoved ? scheme.primaryContainer : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${view.length} things so far',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: scheme.primary)),
            const SizedBox(height: 6),
            Text(view.prompt, style: const TextStyle(fontSize: 14.5)),
            // Shared, never comparative — shown alongside, not instead of,
            // the plain "it stopped" line above.
            if (view.closing != null) Padding(padding: const EdgeInsets.only(top: 4),
              child: Text(view.closing!,
                style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700))),
          ]),
        ),
        const SizedBox(height: 16),
        if (!ended) _TurnBanner(name: _name(view.whoseTurn), phase: view.phase),
        const SizedBox(height: 16),
        if (view.visibleSteps.isNotEmpty) _ChainList(steps: _game.steps.map((ChainStep s) =>
          (label: s.label, mine: s.side == ChainSide.a)).toList()),
        if (!ended) ...[
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            minLines: 1, maxLines: 2,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              hintText: view.phase == ChainPhase.building
                ? 'What comes next?…'
                : 'What was next in the chain?…',
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(width: double.infinity, height: 48,
            child: FilledButton(
              onPressed: _submit,
              child: Text(view.phase == ChainPhase.building ? 'Add it' : 'That\'s it!'),
            )),
        ] else
          Padding(padding: const EdgeInsets.only(top: 4),
            child: SizedBox(width: double.infinity, height: 48,
              child: FilledButton.tonal(onPressed: _startNewChain,
                child: const Text('Start a new chain')))),
        if (artifact != null) Padding(padding: const EdgeInsets.only(top: 16),
          child: Row(children: [
            Icon(Icons.auto_stories_outlined, size: 18, color: scheme.primary),
            const SizedBox(width: 6),
            Expanded(child: Text('Long enough to keep — this one is saved for your book.',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant))),
          ])),
      ])),
    );
  }
}

class _TurnBanner extends StatelessWidget {
  const _TurnBanner({required this.name, required this.phase});
  final String name;
  final ChainPhase phase;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final String verb = phase == ChainPhase.building ? 'to add something' : 'to remember';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.front_hand_outlined, size: 18, color: scheme.onTertiaryContainer),
        const SizedBox(width: 8),
        // Flexible + ellipsis, not a bare Text: on the Fold5 cover screen
        // (344 CSS px) the pill is squeezed narrow enough that "$name's turn
        // to add something" no longer fits on one line, and this must
        // shrink rather than overflow the RenderFlex.
        Flexible(child: Text("$name's turn $verb",
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontWeight: FontWeight.w600, color: scheme.onTertiaryContainer))),
      ]),
    );
  }
}

class _ChainList extends StatelessWidget {
  const _ChainList({required this.steps});
  final List<({String label, bool mine})> steps;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Wrap(spacing: 8, runSpacing: 8,
      children: [for (final (int i, ({String label, bool mine}) s) in steps.indexed)
        _ChainChip(index: i, label: s.label, mine: s.mine, scheme: scheme)]);
  }
}

class _ChainChip extends StatelessWidget {
  const _ChainChip({required this.index, required this.label, required this.mine, required this.scheme});
  final int index;
  final String label;
  final bool mine;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    // A one-shot entrance for whichever chip is newest — a consequence of the
    // move that added it, not an ambient or looping effect (§8.13.1).
    tween: Tween<double>(begin: 0, end: 1),
    duration: const Duration(milliseconds: 260),
    curve: Curves.easeOutBack,
    builder: (BuildContext context, double t, Widget? child) =>
      Opacity(opacity: t.clamp(0, 1), child: Transform.scale(scale: 0.85 + 0.15 * t, child: child)),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: mine ? scheme.secondaryContainer : scheme.primaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(label, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
    ),
  );
}
