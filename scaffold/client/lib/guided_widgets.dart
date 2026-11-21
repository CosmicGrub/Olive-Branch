// OLIVE BRANCH — the guided first run's building blocks: the progress strip, the large calm card, the five controls,
// the icon-label row, the coach-mark anchors and the coach-mark overlay. MASTERFILE §8.5.13.
//
// ANCHORS, NOT PIXELS. A tour stop names an anchor ("home.medsCare"); the real icon is wrapped in a [CoachAnchor] with
// that name; the overlay measures it at draw time, so the same stop points at the right place on a phone, a folding
// phone's cover and inner screens, and a tablet, in portrait and landscape. No GlobalKey is used (the same screen can
// be pushed twice, and a duplicate GlobalKey asserts); an anchor registers its own context while it is mounted.
// When an anchor is not on the screen, the overlay shows the card in the middle with a calm line and never points at
// nothing.
import 'package:flutter/material.dart';

import 'guided_engine.dart';
import 'guided_registry.dart' show guidedStrip;
import 'guided_script.dart';

class CoachAnchors {
  CoachAnchors._();
  static final Map<String, List<BuildContext>> _live = <String, List<BuildContext>>{};

  static void _add(String id, BuildContext c) => (_live[id] ??= <BuildContext>[]).add(c);
  static void _remove(String id, BuildContext c) {
    _live[id]?.remove(c);
    if (_live[id]?.isEmpty ?? false) _live.remove(id);
  }

  /// The newest mounted anchor with this id (the top-most screen's), or null.
  static BuildContext? contextOf(String id) {
    final List<BuildContext>? l = _live[id];
    if (l == null) return null;
    for (final BuildContext c in l.reversed) {
      if (c.mounted) return c;
    }
    return null;
  }

  /// The anchor's rectangle in global coordinates, or null when it is not mounted, not laid out or not on screen.
  static Rect? rectOf(String id) {
    final BuildContext? c = contextOf(id);
    if (c == null) return null;
    final RenderObject? ro = c.findRenderObject();
    if (ro is! RenderBox || !ro.attached || !ro.hasSize) return null;
    return ro.localToGlobal(Offset.zero) & ro.size;
  }

  /// Scrolls the anchor into view when it sits inside a scrollable.
  static void reveal(String id) {
    final BuildContext? c = contextOf(id);
    if (c != null) Scrollable.ensureVisible(c, alignment: 0.5, duration: Duration.zero);
  }

  static int get count => _live.length;
}

/// Wrap the real icon a tour stop points at. Costs nothing when no tour is running.
class CoachAnchor extends StatefulWidget {
  const CoachAnchor({super.key, required this.id, required this.child});
  final String id;
  final Widget child;
  @override
  State<CoachAnchor> createState() => _CoachAnchorState();
}

class _CoachAnchorState extends State<CoachAnchor> {
  late String _id = widget.id;
  @override
  void initState() {
    super.initState();
    CoachAnchors._add(_id, context);
  }

  @override
  void didUpdateWidget(CoachAnchor old) {
    super.didUpdateWidget(old);
    if (old.id != widget.id) {
      CoachAnchors._remove(_id, context);
      _id = widget.id;
      CoachAnchors._add(_id, context);
    }
  }

  @override
  void dispose() {
    CoachAnchors._remove(_id, context);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// "Step 3 of 9". The words are what a screen reader says; the bar is decoration.
class GuidedProgressStrip extends StatelessWidget {
  const GuidedProgressStrip({super.key, required this.step, required this.of, this.prefix = 'Step'});
  final int step, of;
  final String prefix;

  @override
  Widget build(BuildContext context) {
    final ColorScheme s = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      label: '$prefix $step of $of',
      child: ExcludeSemantics(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text('$prefix $step of $of',
              key: const Key('guidedStripText'),
              style: Theme.of(context).textTheme.labelLarge?.copyWith(color: s.onSurfaceVariant)),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: of == 0 ? 0 : step / of, minHeight: 6),
          ),
        ]),
      ),
    );
  }
}

/// One icon with its label spelled out beside it. Never an icon alone.
class GuidedLabelTile extends StatelessWidget {
  const GuidedLabelTile(this.label, {super.key, this.big = false});
  final GuidedLabel label;
  final bool big;

  @override
  Widget build(BuildContext context) {
    final ColorScheme s = Theme.of(context).colorScheme;
    final TextTheme t = Theme.of(context).textTheme;
    return Semantics(
      container: true,
      label: label.line.isEmpty ? label.label : '${label.label}. ${label.line}',
      child: ExcludeSemantics(
        child: Container(
          padding: EdgeInsets.all(big ? 16 : 10),
          decoration: BoxDecoration(color: s.primaryContainer, borderRadius: BorderRadius.circular(16)),
          child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
            Icon(label.icon, size: big ? 44 : 28, color: s.onPrimaryContainer),
            const SizedBox(width: 10),
            Flexible(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: <Widget>[
                Text(label.label,
                    style: (big ? t.titleLarge : t.titleSmall)
                        ?.copyWith(fontWeight: FontWeight.w700, color: s.onPrimaryContainer)),
                if (label.line.isNotEmpty)
                  Text(label.line,
                      style: (big ? t.bodyMedium : t.bodySmall)?.copyWith(color: s.onPrimaryContainer)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// The five controls of a grown-up step. Each says what it does; the ones that cannot work say why, calmly.
class GuidedControls extends StatelessWidget {
  const GuidedControls({
    super.key,
    required this.controller,
    required this.entry,
    required this.onNext,
    this.nextLabel,
    this.showNext = true,
    this.onSkip,
    this.onLater,
  });
  final GuidedController controller;
  final GuidedEntry entry;
  final VoidCallback? onNext;
  final String? nextLabel;
  final bool showNext;

  /// Overrides (a mini-tour ends instead of moving on).
  final VoidCallback? onSkip, onLater;

  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final ColorScheme s = Theme.of(context).colorScheme;
    final bool needed = entry.kind == GuidedKind.form;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
      if (showNext)
        SizedBox(
          height: 56,
          child: FilledButton(
            key: const Key('guidedNext'),
            onPressed: onNext,
            child: Text(nextLabel ?? entry.action, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
        ),
      const SizedBox(height: 8),
      Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 4, children: <Widget>[
        TextButton(
          key: const Key('guidedBack'),
          onPressed: controller.canBack ? () => controller.back() : null,
          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
          child: const Text('Back'),
        ),
        if (controller.canSkip)
          TextButton(
            key: const Key('guidedSkip'),
            onPressed: onSkip ?? () => controller.skip(),
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            child: const Text('Skip this part'),
          ),
        if (controller.canLater)
          TextButton(
            key: const Key('guidedLater'),
            onPressed: onLater ?? () => controller.later(),
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            child: const Text('Do this later'),
          ),
        TextButton(
          key: const Key('guidedPause'),
          onPressed: () => controller.pause(),
          style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
          child: const Text('I need a minute'),
        ),
      ]),
      if (needed)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('This one is needed, so there is no skip. Take a minute if you like.',
              key: const Key('guidedNeededNote'),
              textAlign: TextAlign.center,
              style: t.bodySmall?.copyWith(color: s.onSurfaceVariant)),
        ),
    ]);
  }
}

/// The calm card "I need a minute" opens.
class GuidedPauseCard extends StatelessWidget {
  const GuidedPauseCard({super.key, required this.controller});
  final GuidedController controller;

  @override
  Widget build(BuildContext context) => Material(
        color: Theme.of(context).colorScheme.surface,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                  Icon(Icons.free_breakfast_outlined, size: 64, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(height: 16),
                  Semantics(
                    header: true,
                    child: Text(GuidedWords.pauseTitle,
                        key: const Key('guidedPauseTitle'),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall),
                  ),
                  const SizedBox(height: 8),
                  Text(GuidedWords.pauseBody, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 56,
                    child: FilledButton(
                      key: const Key('guidedResume'),
                      onPressed: () => controller.resume(),
                      child: const Text(GuidedWords.pauseButton),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      );
}

/// A large calm card for one step: strip, title, words, icon labels, then [body] (a form, say), then the controls.
class GuidedStepCard extends StatelessWidget {
  const GuidedStepCard({
    super.key,
    required this.controller,
    required this.entry,
    required this.name,
    this.body = const <Widget>[],
    this.onNext,
    this.showNext = true,
    this.stripPrefix = 'Step',
    this.stripOverride,
    this.eyebrow,
    this.footer = const <Widget>[],
    this.onSkip,
    this.onLater,
  });
  final GuidedController controller;
  final GuidedEntry entry;
  final String? name;
  final List<Widget> body;
  final VoidCallback? onNext;
  final bool showNext;
  final String stripPrefix;
  final ({int step, int of})? stripOverride;
  final String? eyebrow;
  final List<Widget> footer;
  final VoidCallback? onSkip, onLater;

  @override
  Widget build(BuildContext context) {
    final ({int step, int of}) strip = stripOverride ?? guidedStrip(controller.steps, controller.index);
    final TextTheme t = Theme.of(context).textTheme;
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
                if (strip.step > 0) GuidedProgressStrip(step: strip.step, of: strip.of, prefix: stripPrefix),
                if (strip.step > 0) const SizedBox(height: 20),
                if (eyebrow != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(eyebrow!, key: const Key('guidedEyebrow'), style: t.labelLarge),
                  ),
                Semantics(
                  header: true,
                  focusable: true,
                  child: Text(entry.fill(entry.title, name), key: const Key('guidedTitle'), style: t.headlineSmall),
                ),
                const SizedBox(height: 12),
                Text(entry.fill(entry.words, name), key: const Key('guidedWords'), style: t.bodyLarge),
                if (entry.labels.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 16),
                  Wrap(spacing: 10, runSpacing: 10, children: <Widget>[
                    for (final GuidedLabel l in entry.labels) GuidedLabelTile(l),
                  ]),
                ],
                if (body.isNotEmpty) ...<Widget>[const SizedBox(height: 20), ...body],
                const SizedBox(height: 24),
                GuidedControls(
                    controller: controller, entry: entry, onNext: onNext, showNext: showNext, onSkip: onSkip, onLater: onLater),
                ...footer,
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// The coach-mark overlay for a tour stop: a dimmed screen with a lit hole round the real icon, its label spelled
/// out beside it, and a card with the words and the five controls. Absorbs taps behind it.
class CoachOverlay extends StatefulWidget {
  const CoachOverlay({
    super.key,
    required this.controller,
    required this.entry,
    required this.name,
    this.stripOverride,
    this.stripPrefix = 'Step',
    this.eyebrow,
    this.onSkip,
    this.onLater,
  });
  final GuidedController controller;
  final GuidedEntry entry;
  final String? name;
  final ({int step, int of})? stripOverride;
  final String stripPrefix;
  final String? eyebrow;
  final VoidCallback? onSkip, onLater;

  @override
  State<CoachOverlay> createState() => _CoachOverlayState();
}

class _CoachOverlayState extends State<CoachOverlay> with WidgetsBindingObserver {
  Rect? _rect;
  bool _measured = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _measureSoon(reveal: true);
  }

  @override
  void didUpdateWidget(CoachOverlay old) {
    super.didUpdateWidget(old);
    if (old.entry.id != widget.entry.id) _measureSoon(reveal: true);
  }

  @override
  void didChangeMetrics() => _measureSoon();

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _measureSoon({bool reveal = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final String? a = widget.entry.anchor;
      if (a != null && reveal) CoachAnchors.reveal(a);
      final Rect? r = a == null ? null : CoachAnchors.rectOf(a);
      if (!_measured || r != _rect) {
        setState(() {
          _rect = r;
          _measured = true;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final Size screen = MediaQuery.sizeOf(context);
    final EdgeInsets pad = MediaQuery.paddingOf(context);
    final Rect? rect = _rect?.inflate(6);
    final GuidedEntry e = widget.entry;
    final ({int step, int of}) strip = widget.stripOverride ?? guidedStrip(widget.controller.steps, widget.controller.index);
    final TextTheme t = Theme.of(context).textTheme;
    final ColorScheme s = Theme.of(context).colorScheme;

    // The card goes on whichever side of the lit icon has more room; with no icon it is centred.
    double maxH = screen.height - pad.vertical - 24;
    Alignment align = Alignment.center;
    if (rect != null) {
      final double above = rect.top - pad.top;
      final double below = screen.height - pad.bottom - rect.bottom;
      if (below >= above) {
        align = Alignment.bottomCenter;
        maxH = below - 12;
      } else {
        align = Alignment.topCenter;
        maxH = above - 12;
      }
      if (maxH < 200) {
        // The icon is huge or the room tiny: the card covers the far end and scrolls; the lit icon stays visible.
        maxH = (screen.height - pad.vertical) * 0.5;
        align = rect.center.dy < screen.height / 2 ? Alignment.bottomCenter : Alignment.topCenter;
      }
    }

    final Widget card = Material(
      color: s.surface,
      elevation: 6,
      borderRadius: BorderRadius.circular(20),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH.clamp(160, double.infinity), maxWidth: 560),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: <Widget>[
            if (strip.step > 0) GuidedProgressStrip(step: strip.step, of: strip.of, prefix: widget.stripPrefix),
            const SizedBox(height: 10),
            if (widget.eyebrow != null) Text(widget.eyebrow!, key: const Key('guidedEyebrow'), style: t.labelLarge),
            if (e.labels.isNotEmpty) GuidedLabelTile(e.labels.first),
            const SizedBox(height: 10),
            Semantics(
              header: true,
              liveRegion: true,
              child: Text(e.fill(e.title, widget.name), key: const Key('guidedTitle'), style: t.titleLarge),
            ),
            const SizedBox(height: 6),
            Text(e.fill(e.words, widget.name), key: const Key('guidedWords'), style: t.bodyLarge),
            if (e.anchor != null && rect == null && _measured)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(GuidedWords.tourNoFind, key: const Key('guidedNoFind'), style: t.bodyMedium),
              ),
            const SizedBox(height: 14),
            GuidedControls(
                controller: widget.controller,
                entry: e,
                onNext: () => widget.controller.next(),
                onSkip: widget.onSkip,
                onLater: widget.onLater,
                nextLabel: widget.controller.isLast ? 'Finish' : e.action),
          ]),
        ),
      ),
    );

    return Stack(children: <Widget>[
      // The dimmed screen with a hole. It absorbs taps: nothing behind a tour stop can be pressed by accident.
      Positioned.fill(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {},
          child: CustomPaint(painter: _ScrimPainter(rect, Colors.black.withValues(alpha: 0.72))),
        ),
      ),
      if (rect != null)
        Positioned.fromRect(
          rect: rect,
          child: IgnorePointer(
            child: DecoratedBox(
              key: const Key('guidedLit'),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white, width: 3),
              ),
            ),
          ),
        ),
      Positioned.fill(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Align(alignment: align, child: card),
          ),
        ),
      ),
    ]);
  }
}

class _ScrimPainter extends CustomPainter {
  _ScrimPainter(this.hole, this.color);
  final Rect? hole;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Path p = Path()..addRect(Offset.zero & size);
    if (hole != null) p.addRRect(RRect.fromRectAndRadius(hole!, const Radius.circular(18)));
    p.fillType = PathFillType.evenOdd;
    canvas.drawPath(p, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_ScrimPainter old) => old.hole != hole || old.color != color;
}
