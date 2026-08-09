// OLIVE BRANCH — the co-op story game. UNVERIFIED (no Flutter toolchain in
// tools/verify.sh's automated pipeline — manually built and run via
// `flutter analyze` / `flutter test` this session). MASTERFILE §9.2, P2.
// Renders MARKUP screen 'story'.
//
// A 1:1 semantic port of the 'story' branch of packages/games/src/games.ts's
// generic game engine (CATALOGUE's story entry, newGame()'s story base,
// play()'s story branch, childView()'s story branch, storyArtifact()) —
// narrowed to just this one game kind rather than the full multi-game
// GameState union, since that union's other branches (tic-tac-toe, dots and
// boxes, memory) belong to whichever screens implement THOSE games.
//
// One intentional adaptation, matching game_chain.dart's and game_hunt.dart's
// note: the TS `Side = 'A' | 'B'` union is ported here as `StorySide`, not
// the bare name `Side`, so a screen that imports more than one of these game
// files never hits an ambiguous top-level `Side`.
//
// §9.2: "Co-op. No handicap, because there is nothing to be behind at." This
// is the one game in the catalogue with `competitive: false` — so unlike the
// others, `childView()`'s story branch never carries a `boxesEach` tally, and
// there is no handicap offer, no takeback (there is nothing to take back —
// a contributed line is simply the next thing in the story). P2's "no
// winner, ever" is structural here, not a UI choice: `addLine()` has no
// concept of an outcome besides 'finished'.
import 'package:flutter/material.dart';

// =========================================================== ported logic ===
// packages/games/src/games.ts — the story branch of the generic game engine.

enum StorySide { a, b } // a = child, b = parent (TS: 'A' | 'B')

enum StoryError { notYourTurn, gameOver, emptyContribution }

class StoryLine {
  const StoryLine({required this.side, required this.text});
  final StorySide side;
  final String text;
}

/// TS's generic `GameState.outcome` is `Side | 'draw' | 'done' | null`; for
/// the story branch specifically it only ever becomes the literal 'done' or
/// stays null, so it is represented here as a plain bool.
class StoryGame {
  const StoryGame({required this.lines, required this.turn, required this.finished});
  final List<StoryLine> lines;
  final StorySide turn;
  final bool finished;

  StoryGame copyWith({List<StoryLine>? lines, StorySide? turn, bool? finished}) => StoryGame(
    lines: lines ?? this.lines,
    turn: turn ?? this.turn,
    finished: finished ?? this.finished,
  );
}

/// A story stays a good length for one sitting past this many lines — mirrors
/// games.ts's `lines.length >= 20` cutoff exactly.
const int storyLineCap = 20;

/// TS: `newGame()`'s shared base sets `turn: 'A'` — the CHILD starts the
/// story, unlike the word chain (game_chain.dart), where the parent does.
StoryGame newStory() => const StoryGame(lines: <StoryLine>[], turn: StorySide.a, finished: false);

class AddLineResult {
  const AddLineResult.ok(this.state) : ok = true, reason = null;
  const AddLineResult.err(this.reason) : ok = false, state = null;
  final bool ok;
  final StoryGame? state;
  final StoryError? reason;
}

/// One line each, alternating strictly every turn (no "building/recalling"
/// phase here — that shape belongs to the chain game, not this one).
AddLineResult addLine(StoryGame g, StorySide side, String text) {
  if (g.finished) return const AddLineResult.err(StoryError.gameOver);
  if (side != g.turn) return const AddLineResult.err(StoryError.notYourTurn);
  final String trimmed = text.trim();
  if (trimmed.isEmpty) return const AddLineResult.err(StoryError.emptyContribution);
  final List<StoryLine> lines = <StoryLine>[...g.lines, StoryLine(side: side, text: trimmed)];
  return AddLineResult.ok(g.copyWith(
    lines: lines,
    turn: side == StorySide.a ? StorySide.b : StorySide.a,
    finished: lines.length >= storyLineCap,
  ));
}

class StoryChildView {
  const StoryChildView({required this.yourTurn, required this.finished, this.closing});
  final bool yourTurn;
  final bool finished;
  /// "What a story." — never "you lost", because there is no losing this one.
  final String? closing;
}

StoryChildView storyChildView(StoryGame g) => StoryChildView(
  yourTurn: g.turn == StorySide.a && !g.finished,
  finished: g.finished,
  closing: g.finished ? 'What a story.' : null,
);

class StoryArtifact {
  const StoryArtifact({required this.title, required this.body});
  final String title;
  final String body;
}

/// §9.8 — a finished story is worth keeping.
StoryArtifact? storyArtifact(StoryGame g) {
  if (g.lines.isEmpty) return null;
  return StoryArtifact(title: 'A story we made up',
    body: g.lines.map((StoryLine l) => l.text).join(' '));
}

// ================================================================= widget ===

class GameStoryScreen extends StatefulWidget {
  const GameStoryScreen({super.key, this.childName = 'Ivy', this.parentName = 'Dad'});
  final String childName;
  final String parentName;

  @override
  State<GameStoryScreen> createState() => _GameStoryScreenState();
}

class _GameStoryScreenState extends State<GameStoryScreen> {
  StoryGame _game = newStory();
  final TextEditingController _controller = TextEditingController();
  bool _readingAsOne = false;

  String _name(StorySide s) => s == StorySide.a ? widget.childName : widget.parentName;

  void _submit() {
    final String text = _controller.text.trim();
    if (text.isEmpty) return;
    final AddLineResult r = addLine(_game, _game.turn, text);
    if (!r.ok) return;
    setState(() { _game = r.state!; _controller.clear(); });
  }

  void _startNewStory() => setState(() { _game = newStory(); _readingAsOne = false; _controller.clear(); });

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final StoryChildView view = storyChildView(_game);
    final StoryArtifact? artifact = storyArtifact(_game);
    final ColorScheme scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Make up a story')),
      body: SafeArea(child: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text('One line each. Nobody wins — you just see where it goes.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant))),
        if (!view.finished) Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: _TurnBanner(name: _name(_game.turn))),
        if (view.finished) Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(children: [
            Icon(Icons.celebration_outlined, color: scheme.primary, size: 20),
            const SizedBox(width: 8),
            Text(view.closing!, style: TextStyle(fontWeight: FontWeight.w700, color: scheme.primary)),
          ])),
        Expanded(child: _game.lines.isEmpty
          ? const _EmptyStoryHint()
          : (_readingAsOne
            ? _StoryPage(text: artifact?.body ?? '')
            : _StoryFeed(lines: _game.lines, nameOf: _name))),
        const Divider(height: 1),
        Padding(padding: const EdgeInsets.all(12), child: Column(children: [
          if (_game.lines.isNotEmpty) Align(alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _readingAsOne = !_readingAsOne),
              icon: Icon(_readingAsOne ? Icons.view_agenda_outlined : Icons.menu_book_outlined),
              label: Text(_readingAsOne ? 'Show turn by turn' : 'Read it as one story'))),
          if (!view.finished) ...[
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(child: TextField(
                controller: _controller,
                minLines: 1, maxLines: 3,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _submit(),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'What happens next?…'))),
              const SizedBox(width: 8),
              SizedBox(height: 48, child: FilledButton(onPressed: _submit, child: const Text('Add'))),
            ]),
          ] else
            SizedBox(width: double.infinity, height: 48,
              child: FilledButton.tonal(onPressed: _startNewStory,
                child: const Text('Start a new story'))),
          if (artifact != null) Padding(padding: const EdgeInsets.only(top: 8),
            child: Text('Every story you make together is saved for keeps.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant))),
        ])),
      ])),
    );
  }
}

class _TurnBanner extends StatelessWidget {
  const _TurnBanner({required this.name});
  final String name;
  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: scheme.tertiaryContainer, borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.auto_stories, size: 18, color: scheme.onTertiaryContainer),
        const SizedBox(width: 8),
        // Flexible + ellipsis, not a bare Text: on the Fold5 cover screen
        // (344 CSS px) the pill is squeezed narrow enough that "$name's turn
        // to add a line" no longer fits on one line, and this must shrink
        // rather than overflow the RenderFlex.
        Flexible(child: Text("$name's turn to add a line",
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontWeight: FontWeight.w600, color: scheme.onTertiaryContainer))),
      ]),
    );
  }
}

class _EmptyStoryHint extends StatelessWidget {
  const _EmptyStoryHint();
  @override
  Widget build(BuildContext context) {
    final ColorScheme cs = Theme.of(context).colorScheme;
    return Center(child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.auto_stories_outlined, size: 40, color: cs.onSurfaceVariant),
        const SizedBox(height: 12),
        Text('Type the very first line to begin.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: cs.onSurfaceVariant)),
      ]),
    ));
  }
}

class _StoryFeed extends StatelessWidget {
  const _StoryFeed({required this.lines, required this.nameOf});
  final List<StoryLine> lines;
  final String Function(StorySide) nameOf;

  @override
  Widget build(BuildContext context) => ListView.builder(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    itemCount: lines.length,
    itemBuilder: (BuildContext context, int i) => _StoryBubble(
      // Only the newest bubble gets the entrance animation — a consequence
      // of just having been added, never an ambient or looping effect.
      animate: i == lines.length - 1,
      name: nameOf(lines[i].side),
      mine: lines[i].side == StorySide.a,
      text: lines[i].text,
    ),
  );
}

class _StoryBubble extends StatelessWidget {
  const _StoryBubble({required this.animate, required this.name, required this.mine, required this.text});
  final bool animate;
  final String name;
  final bool mine;
  final String text;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Widget bubble = Align(
      alignment: mine ? Alignment.centerLeft : Alignment.centerRight,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: mine ? scheme.secondaryContainer : scheme.primaryContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(text, style: Theme.of(context).textTheme.bodyMedium),
          ]),
        ),
      ),
    );
    if (!animate) return bubble;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      builder: (BuildContext context, double t, Widget? child) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, (1 - t) * 10), child: child)),
      child: bubble,
    );
  }
}

class _StoryPage extends StatelessWidget {
  const _StoryPage({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(20),
    child: Text(text, style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.5)),
  );
}
