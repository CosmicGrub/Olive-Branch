// OLIVE BRANCH — shared reading, around the call. UNVERIFIED (no Flutter
// toolchain in tools/verify.sh's automated pipeline — manually built and run
// via `flutter analyze` / `flutter test` this session). MASTERFILE §9.13.2.
// Renders MARKUP screen 'sharedReading'.
//
// "She turns the pages. He reads, but the pacing is hers." This is a
// two-device feature — her tablet and his call screen — and there is no live
// pairing signal yet (see call_screen.dart's own dev-room-server note for the
// same honest gap on the call side). Rather than fake a socket, this screen
// shows BOTH sides of one shared session in a single build, flipped with a
// visible, clearly-labelled preview toggle — an honest stand-in for "two
// screens," not a claim that live sync exists.
//
// Two invariants this file is responsible for, straight from §9.13.2:
//   - Page turning belongs to HER screen. His screen never gets an arrow.
//   - "No page count and no percentage reach her" — her screen has no digits
//     about progress anywhere; a small non-numeric dot row is the only
//     positional cue, same device-agnostic pattern storyteller_screen.dart
//     already uses. His screen, which she never sees, may say "line 3 of 11"
//     plainly, because he is not the one this rule protects.
import 'package:flutter/material.dart';
import 'form_factors.dart' as ff;
import 'storyteller_logic.dart' as story;

enum _Perspective { her, him }

class SharedReadingScreen extends StatefulWidget {
  const SharedReadingScreen({super.key, required this.childName, required this.readerName});

  final String childName;
  /// The guardian voicing the book tonight, e.g. "Dad". Never used to
  /// synthesise anything — a real person reads aloud on a real call. P1
  /// concerns synthetic voice/likeness generation, which nothing here does.
  final String readerName;

  @override
  State<SharedReadingScreen> createState() => _SharedReadingScreenState();
}

class _SharedReadingScreenState extends State<SharedReadingScreen> {
  late story.Story _storyValue = story.freshStory(story.Personal(childName: widget.childName));
  int _index = 0;
  _Perspective _view = _Perspective.her;
  bool _sheIsReading = false;

  story.ReadAloud get _read => story.forReadingAloud(_storyValue);
  int get _lastIndex => _read.blocks.length - 1;

  void _next() { if (_index < _lastIndex) setState(() => _index++); }
  void _prev() { if (_index > 0) setState(() => _index--); }

  void _swapReader() => setState(() => _sheIsReading = !_sheIsReading);

  void _newBook() => setState(() {
        _storyValue = story.freshStory(story.Personal(childName: widget.childName));
        _index = 0;
      });

  @override
  Widget build(BuildContext context) {
    final block = _read.blocks[_index];
    final readerLabel = _sheIsReading ? widget.childName : widget.readerName;

    return Scaffold(
      appBar: AppBar(title: Text(_read.title)),
      // CRITICAL — child-reachable (see file header). This wrapper only
      // constrains width around the WHOLE existing toggle-driven body below,
      // unchanged: exactly one of _HerScreen/_HisScreen is ever built, gated
      // by _view, at every viewport width — a two-pane split was
      // deliberately rejected for this exact screen precisely because it
      // would put both on screen at once on a wide viewport (see file
      // header), so this cap centers a single column instead of splitting
      // it. Same real columnsAt() gate every other width decision in the
      // app uses.
      body: SafeArea(child: LayoutBuilder(builder: (BuildContext context, BoxConstraints constraints) {
        final double textScale = MediaQuery.textScalerOf(context).scale(1);
        final bool capWidth = ff.columnsAt(
            ff.Viewport(w: constraints.maxWidth, h: constraints.maxHeight), textScale) >= 2;
        final Widget content = Column(key: const Key('sharedReadingBody'), children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const _PreviewBanner(),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: Text('$readerLabel is reading tonight',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
                TextButton(
                  onPressed: _swapReader,
                  child: Text(_sheIsReading
                    ? 'Swap: let ${widget.readerName} read'
                    : 'Swap: let ${widget.childName} read')),
              ]),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<_Perspective>(
                  segments: const [
                    ButtonSegment(value: _Perspective.her, label: Text('Her screen'),
                      icon: Icon(Icons.child_care_rounded)),
                    ButtonSegment(value: _Perspective.him, label: Text('His screen'),
                      icon: Icon(Icons.person_rounded)),
                  ],
                  selected: {_view},
                  onSelectionChanged: (s) => setState(() => _view = s.first),
                ),
              ),
            ]),
          ),
          const Divider(height: 1),
          Expanded(
            child: _view == _Perspective.her
                ? _HerScreen(
                    key: const Key('herScreen'), block: block, total: _lastIndex + 1,
                    index: _index, canGoBack: _index > 0, canGoForward: _index < _lastIndex,
                    onNext: _next, onPrev: _prev, finished: _index == _lastIndex, onNewBook: _newBook,
                  )
                : _HisScreen(
                    key: const Key('hisScreen'), block: block, index: _index, total: _lastIndex + 1,
                    readerLabel: readerLabel,
                  ),
          ),
        ]);
        return capWidth
            ? Center(
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: ff.comfortableReadingWidth),
                    child: content))
            : content;
      })),
    );
  }
}

class _PreviewBanner extends StatelessWidget {
  const _PreviewBanner();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(12)),
    child: Row(children: [
      const Icon(Icons.info_outline_rounded, size: 16),
      const SizedBox(width: 8),
      Expanded(child: Text(
        'Previewing one shared book on two screens — live pairing between '
        'her device and the call is not built yet, so flip the toggle below '
        'to see each side.',
        style: Theme.of(context).textTheme.bodySmall
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant))),
    ]),
  );
}

// ================================================================ her side ==
/// The only side with a page-turn control — "she turns the pages" (§9.13.2).
/// No digit about position anywhere in this subtree: the dot row is the only
/// positional cue, matching storyteller_screen.dart's reading pane.
class _HerScreen extends StatelessWidget {
  const _HerScreen({
    super.key, required this.block, required this.total, required this.index,
    required this.canGoBack, required this.canGoForward, required this.onNext,
    required this.onPrev, required this.finished, required this.onNewBook,
  });
  final story.ReadAloudBlock block;
  final int total, index;
  final bool canGoBack, canGoForward, finished;
  final VoidCallback onNext, onPrev, onNewBook;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(20),
    child: Column(children: [
      Expanded(
        child: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 240),
            transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
            child: block.herLine
                ? _HerLineCard(key: ValueKey('her-$index'), text: block.text)
                : Text(block.text, key: ValueKey('narr-$index'),
                    textAlign: TextAlign.center, style: const TextStyle(fontSize: 21, height: 1.4)),
          ),
        ),
      ),
      const SizedBox(height: 12),
      _Dots(total: total, current: index),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(child: SizedBox(height: 56, child: OutlinedButton.icon(
          // Turning back is allowed and is not an error (§9.13.2) — never
          // disabled with a warning, only disabled at the true start.
          onPressed: canGoBack ? onPrev : null,
          icon: const Icon(Icons.arrow_back_rounded),
          label: const Text('Back')))),
        const SizedBox(width: 12),
        Expanded(child: SizedBox(height: 56, child: FilledButton.icon(
          onPressed: canGoForward ? onNext : null,
          icon: const Icon(Icons.arrow_forward_rounded),
          label: const Text('Turn the page')))),
      ]),
      // Reaching the last page is a genuine completion moment — grown in
      // with AnimatedSize rather than popping in instantly, the same
      // restraint storyteller_screen.dart's own "The end" transition uses.
      AnimatedSize(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
        child: finished
          ? Padding(
              padding: const EdgeInsets.only(top: 16),
              child: SizedBox(width: double.infinity, height: 52, child: FilledButton.tonalIcon(
                onPressed: onNewBook,
                icon: const Icon(Icons.autorenew_rounded),
                label: const Text('Read another one together'))))
          : const SizedBox.shrink(),
      ),
    ]),
  );
}

class _HerLineCard extends StatelessWidget {
  const _HerLineCard({super.key, required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.amber.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Colors.amber.shade400, width: 1.4)),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.campaign_rounded, size: 16, color: Colors.amber.shade800),
        const SizedBox(width: 4),
        Text('YOUR LINE!', style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w800, letterSpacing: 0.6, color: Colors.amber.shade900)),
      ]),
      const SizedBox(height: 8),
      Text(text, textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, height: 1.3)),
    ]),
  );
}

class _Dots extends StatelessWidget {
  const _Dots({required this.total, required this.current});
  final int total, current;
  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.center, spacing: 4,
    children: [for (int i = 0; i < total; i++) Container(
      width: i == current ? 9 : 6, height: i == current ? 9 : 6,
      decoration: BoxDecoration(shape: BoxShape.circle,
        color: i <= current
          ? Theme.of(context).colorScheme.primary
          : Theme.of(context).colorScheme.primary.withValues(alpha: 0.2)),
    )],
  );
}

// ================================================================ his side ==
/// Read-only: no page-turn control here at all — not disabled, structurally
/// absent, because the pacing is never his to set (§9.13.2).
class _HisScreen extends StatelessWidget {
  const _HisScreen({super.key, required this.block, required this.index,
    required this.total, required this.readerLabel});
  final story.ReadAloudBlock block;
  final int index, total;
  final String readerLabel;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(20),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('line ${index + 1} of $total', style: Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      const SizedBox(height: 4),
      Text('$readerLabel reads aloud; she turns the page when she is ready.',
        style: Theme.of(context).textTheme.bodySmall
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      const SizedBox(height: 16),
      Expanded(child: Center(child: block.herLine
        ? Column(mainAxisSize: MainAxisSize.min, children: [
            Text('(pause here — it is her line)',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontStyle: FontStyle.italic, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            Text(block.text, textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          ])
        : Text(block.text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 19, height: 1.4)))),
    ]),
  );
}
