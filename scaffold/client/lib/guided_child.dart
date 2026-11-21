// OLIVE BRANCH — her half of the guided first run, on her tablet: a short, joyful, picture-led welcome that is STARTED BY A
// GROWN-UP. MASTERFILE §8.5.13. Words: docs/planning/ONBOARDING-SCRIPT.md ("Her half").
//
// [ChildWelcomeHost] wraps her home (inside the kiosk shell, so the grown-up gate is in scope). It shows nothing unless a
// grown-up paired this tablet just now, or the welcome was left half-way, or a newer feature added an icon (the "What's
// new" delta), or the developer seam asks for it. Then:
//   1. the calm card "A grown-up does this" (the same words and picture as the grown-up gate). Nothing to type, nothing
//      to read aloud wrongly. "Go to my home" is always there, so she can never be stuck;
//   2. a grown-up taps "I'm the grown-up" and proves it through the shell's gate ([GrownUpProofScope], the same PIN check
//      and phone unlock as every other grown-up step; this file holds no PIN and imports no keypad);
//   3. one card for the grown-up ("Ready to show her around?"), then hers: hello, her icons with their labels, two
//      try-its (Messages shows a calm empty box, Colour paints the card a colour she taps), and "All done. Let's go!".
// Her half has NO numbers: no step count, no score, no streak, no timer, no error. Nothing she taps is saved.
// Read-aloud is the speaker the app already has: tap only, never by itself.
import 'dart:async';

import 'package:flutter/material.dart';

import 'daily_time_gate.dart' show GrownUpProofScope;
import 'guided_engine.dart';
import 'guided_progress.dart';
import 'guided_registry.dart';
import 'guided_script.dart';
import 'guided_sim.dart';
import 'local_services.dart';
import 'read_aloud.dart' show SpeakerButton;

enum _Stage { off, offer, forGrownUp, welcome }

class ChildWelcomeHost extends StatefulWidget {
  const ChildWelcomeHost({
    super.key,
    required this.child,
    required this.name,
    this.enabled = true,
    this.store,
    this.features = kGuidedFeaturesOn,
    this.registered = kRegisteredGuidedEntries,
    this.simulate = kSimOnboarding,
    this.prove,
  });

  final Widget child;
  final String? name;

  /// False for a tablet that is not locally paired (the connected build): nothing is ever shown.
  final bool enabled;
  final GuidedProgressStore? store;
  final Set<String> features;
  final List<GuidedEntry> registered;
  final bool simulate;

  /// How a grown-up proves they are one. Null reads the kiosk shell's [GrownUpProofScope].
  final Future<bool> Function(BuildContext context)? prove;

  @override
  State<ChildWelcomeHost> createState() => _ChildWelcomeHostState();
}

class _ChildWelcomeHostState extends State<ChildWelcomeHost> {
  _Stage _stage = _Stage.off;
  GuidedController? _ctl;
  late final GuidedProgressStore _store;
  List<GuidedEntry> _cards = const <GuidedEntry>[];
  GuidedProgress _p = const GuidedProgress();
  bool _delta = false;

  @override
  void initState() {
    super.initState();
    _store = widget.store ?? LocalGuidedProgressStore(LocalServices.current.area('guidedtour'));
    if (widget.enabled) unawaited(_decide());
  }

  @override
  void dispose() {
    _ctl?.dispose();
    super.dispose();
  }

  List<GuidedEntry> _resolve({int? seen}) =>
      resolveGuidedEntries(half: GuidedHalf.child, seenVersion: seen, features: widget.features, registered: widget.registered);

  Future<void> _decide() async {
    GuidedProgress p;
    try {
      p = await _store.load();
    } catch (_) {
      p = const GuidedProgress();
    }
    if (!mounted) return;
    _p = p;
    bool offer = false;
    if (widget.simulate) {
      offer = true;
    } else if (p.child == ChildWelcomeState.offered || p.child == ChildWelcomeState.inProgress) {
      offer = true;
    } else if (_resolve(seen: p.seenVersion).isNotEmpty) {
      // A newer feature added something to her home: the delta only, offered the same calm way.
      offer = true;
      _delta = true;
    }
    if (offer) setState(() => _stage = _Stage.offer);
  }

  /// Her cards: everything after the grown-up's two (the offer and the "ready" card).
  List<GuidedEntry> _herCards({required bool delta}) {
    final List<GuidedEntry> all = _resolve(seen: delta ? _p.seenVersion : null);
    return all.where((GuidedEntry e) => e.id != 'c.offer' && e.id != 'c.start').toList();
  }

  Future<void> _homeNow() async {
    _p = _p.copyWith(child: ChildWelcomeState.done, seenVersion: kGuidedScriptVersion);
    await _store.save(_p);
    if (mounted) setState(() => _stage = _Stage.off);
  }

  Future<void> _grownUp() async {
    final Future<bool> Function(BuildContext)? prove = widget.prove ?? GrownUpProofScope.maybeOf(context)?.verify;
    final bool ok = widget.simulate && prove == null ? true : (prove == null ? false : await prove(context));
    if (!ok || !mounted) return;
    final bool resume = _p.child == ChildWelcomeState.inProgress && _p.childStep != null;
    _cards = _herCards(delta: _delta);
    if (_cards.isEmpty) return _homeNow();
    if (resume) return _begin(from: _p.childStep);
    setState(() => _stage = _Stage.forGrownUp);
  }

  Future<void> _begin({String? from}) async {
    final GuidedController c = GuidedController(
      half: GuidedHalf.child,
      steps: _cards,
      store: _store,
      progress: _p,
      startIndex: GuidedController.resumeIndex(_cards, from),
    );
    c.addListener(() {
      if (!mounted) return;
      _p = c.progress;
      if (c.finished) {
        setState(() => _stage = _Stage.off);
      } else {
        setState(() {});
      }
    });
    _ctl = c;
    setState(() => _stage = _Stage.welcome);
    await c.start();
  }

  @override
  Widget build(BuildContext context) {
    final Widget? over = switch (_stage) {
      _Stage.off => null,
      _Stage.offer => _OfferCard(
          simulated: widget.simulate,
          onGrownUp: widget.simulate || widget.prove != null || GrownUpProofScope.maybeOf(context) != null ? _grownUp : null,
          onHome: _homeNow),
      _Stage.forGrownUp => _ReadyCard(
          entry: kBaseGuidedEntries.firstWhere((GuidedEntry e) => e.id == 'c.start'),
          name: widget.name,
          onStart: _begin,
          onHome: _homeNow),
      _Stage.welcome => _ctl == null
          ? null
          : ListenableBuilder(
              listenable: _ctl!,
              builder: (BuildContext c, Widget? _) => _ctl!.finished
                  ? const SizedBox.shrink()
                  : ChildWelcomeCard(
                      key: ValueKey<String>('child-${_ctl!.current.id}'),
                      controller: _ctl!,
                      entry: _ctl!.current,
                      name: widget.name,
                      onHome: () => unawaited(_ctl!.finish()),
                    ),
            ),
    };
    return Stack(children: <Widget>[
      widget.child,
      if (over != null) Positioned.fill(child: Material(color: Theme.of(context).colorScheme.surface, child: over)),
    ]);
  }
}

/// The calm card a child can see: a grown-up and a tablet, "A grown-up does this", and a way home. No keypad, no number.
class _OfferCard extends StatelessWidget {
  const _OfferCard({required this.onGrownUp, required this.onHome, required this.simulated});
  final Future<void> Function()? onGrownUp;
  final Future<void> Function() onHome;
  final bool simulated;

  @override
  Widget build(BuildContext context) {
    final GuidedEntry e = kBaseGuidedEntries.firstWhere((GuidedEntry x) => x.id == 'c.offer');
    final ColorScheme s = Theme.of(context).colorScheme;
    return SafeArea(
      child: Column(children: <Widget>[
        if (simulated) const SimBand(),
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                  Semantics(
                    label: 'A grown-up does this',
                    excludeSemantics: true,
                    child: Row(mainAxisAlignment: MainAxisAlignment.center, children: <Widget>[
                      Icon(Icons.escalator_warning_rounded, size: 96, color: s.primary),
                      const SizedBox(width: 16),
                      Icon(Icons.tablet_android, size: 72, color: s.onSurfaceVariant),
                    ]),
                  ),
                  const SizedBox(height: 20),
                  Text(e.title,
                      key: const Key('childOfferTitle'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 8),
                  Text(e.words, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 28),
                  if (onGrownUp != null)
                    SizedBox(
                      height: 56,
                      child: FilledButton(
                        key: const Key('childOfferGrownUp'),
                        onPressed: () => unawaited(onGrownUp!()),
                        child: Text(e.action, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 64,
                    child: TextButton(
                      key: const Key('childOfferHome'),
                      onPressed: () => unawaited(onHome()),
                      child: const Text('Go to my home', style: TextStyle(fontSize: 20)),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

/// The grown-up's one card, after the gate.
class _ReadyCard extends StatelessWidget {
  const _ReadyCard({required this.entry, required this.name, required this.onStart, required this.onHome});
  final GuidedEntry entry;
  final String? name;
  final Future<void> Function({String? from}) onStart;
  final Future<void> Function() onHome;

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
                Text(entry.fill(entry.title, name),
                    key: const Key('childReadyTitle'), style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 12),
                Text(entry.fill(entry.words, name), style: Theme.of(context).textTheme.bodyLarge),
                const SizedBox(height: 24),
                SizedBox(
                  height: 56,
                  child: FilledButton(
                    key: const Key('childReadyStart'),
                    onPressed: () => unawaited(onStart()),
                    child: Text(entry.action, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  key: const Key('childReadyLater'),
                  onPressed: () => unawaited(onHome()),
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  child: const Text('Not now'),
                ),
              ]),
            ),
          ),
        ),
      );
}

const List<Color> _kColours = <Color>[Color(0xFFF4A6A6), Color(0xFFA6D8F4), Color(0xFFB7E4A6)];
const List<String> _kColourNames = <String>['Red', 'Blue', 'Green'];

/// One of her cards. Picture first (big icons with their labels), then a few big words, a speaker, one big arrow.
class ChildWelcomeCard extends StatefulWidget {
  const ChildWelcomeCard({
    super.key,
    required this.controller,
    required this.entry,
    required this.name,
    required this.onHome,
  });
  final GuidedController controller;
  final GuidedEntry entry;
  final String? name;

  /// "Later" and the last card: her home.
  final VoidCallback onHome;

  @override
  State<ChildWelcomeCard> createState() => _ChildWelcomeCardState();
}

class _ChildWelcomeCardState extends State<ChildWelcomeCard> {
  bool _messagesOpen = false;
  int? _colour;

  @override
  Widget build(BuildContext context) {
    final GuidedEntry e = widget.entry;
    final GuidedController c = widget.controller;
    final ColorScheme s = Theme.of(context).colorScheme;
    final TextTheme t = Theme.of(context).textTheme;
    final String title = e.fill(e.title, widget.name);
    final String words = e.fill(e.words, widget.name);
    final Color? tint = _colour == null ? null : _kColours[_colour!];
    final bool isMessages = e.id == 'c.messages';
    final bool isColour = e.id == 'c.colour';

    Widget label(GuidedLabel l) {
      final Widget tile = _BigLabel(l, tint: tint);
      if (!isMessages) return tile;
      return Semantics(
        button: true,
        label: 'Messages. Tap to look',
        excludeSemantics: true,
        child: InkWell(
          key: const Key('childTryMessages'),
          borderRadius: BorderRadius.circular(24),
          onTap: () => setState(() => _messagesOpen = !_messagesOpen),
          child: tile,
        ),
      );
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      color: tint ?? s.surface,
      child: SafeArea(
        child: Column(children: <Widget>[
          Align(
            alignment: Alignment.centerLeft,
            child: c.canBack
                ? IconButton(
                    key: const Key('childBack'),
                    tooltip: 'Back',
                    iconSize: 36,
                    constraints: const BoxConstraints(minWidth: 64, minHeight: 64),
                    onPressed: () => unawaited(c.back()),
                    icon: const Icon(Icons.arrow_back_rounded),
                  )
                : const SizedBox(height: 64),
          ),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                    Wrap(alignment: WrapAlignment.center, spacing: 16, runSpacing: 16, children: <Widget>[
                      for (final GuidedLabel l in e.labels) label(l),
                    ]),
                    if (isMessages && _messagesOpen)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Container(
                          key: const Key('childMessagesBox'),
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                              color: s.surfaceContainerHighest, borderRadius: BorderRadius.circular(24)),
                          child: Column(children: <Widget>[
                            Icon(Icons.inbox_outlined, size: 48, color: s.onSurfaceVariant),
                            const SizedBox(height: 8),
                            Text(GuidedWords.tryMessages, textAlign: TextAlign.center, style: t.titleLarge),
                          ]),
                        ),
                      ),
                    if (isColour)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Wrap(alignment: WrapAlignment.center, spacing: 20, children: <Widget>[
                          for (int i = 0; i < _kColours.length; i++)
                            Semantics(
                              button: true,
                              label: '${_kColourNames[i]} colour',
                              excludeSemantics: true,
                              child: InkWell(
                                key: Key('childColour$i'),
                                customBorder: const CircleBorder(),
                                onTap: () => setState(() => _colour = i),
                                child: Container(
                                  width: 72,
                                  height: 72,
                                  decoration: BoxDecoration(
                                    color: _kColours[i],
                                    shape: BoxShape.circle,
                                    border: Border.all(color: _colour == i ? s.onSurface : s.outline, width: _colour == i ? 4 : 2),
                                  ),
                                ),
                              ),
                            ),
                        ]),
                      ),
                    const SizedBox(height: 20),
                    Semantics(
                      header: true,
                      focusable: true,
                      child: Text(title, key: const Key('childTitle'), textAlign: TextAlign.center, style: t.headlineMedium),
                    ),
                    const SizedBox(height: 8),
                    Text(isColour && _colour != null ? GuidedWords.tryColour : words,
                        key: const Key('childWords'), textAlign: TextAlign.center, style: t.titleLarge),
                    const SizedBox(height: 8),
                    SpeakerButton(text: '$title. $words', label: 'Read this out loud'),
                  ]),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
            child: SizedBox(
              width: double.infinity,
              height: 72,
              child: FilledButton.icon(
                key: const Key('childNext'),
                onPressed: () => unawaited(c.next()),
                icon: const Icon(Icons.arrow_forward_rounded, size: 32),
                label: Text(e.action, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              ),
            ),
          ),
          Wrap(alignment: WrapAlignment.center, spacing: 12, children: <Widget>[
            if (c.canSkip)
              TextButton(
                key: const Key('childSkip'),
                onPressed: () => unawaited(c.skip()),
                style: TextButton.styleFrom(minimumSize: const Size(64, 56)),
                child: Semantics(label: 'Skip this part', excludeSemantics: true, child: const Text('Skip')),
              ),
            if (c.canLater)
              TextButton(
                key: const Key('childLater'),
                onPressed: widget.onHome,
                style: TextButton.styleFrom(minimumSize: const Size(64, 56)),
                child: Semantics(label: 'Do this later', excludeSemantics: true, child: const Text('Later')),
              ),
          ]),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }
}

/// A big icon with its label spelled out under it. The label is the one on her home.
class _BigLabel extends StatelessWidget {
  const _BigLabel(this.l, {this.tint});
  final GuidedLabel l;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final ColorScheme s = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      label: l.line.isEmpty ? l.label : '${l.label}. ${l.line}',
      child: ExcludeSemantics(
        child: Container(
          width: 168,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: s.primaryContainer, borderRadius: BorderRadius.circular(24)),
          child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            Icon(l.icon, size: 72, color: s.onPrimaryContainer),
            const SizedBox(height: 8),
            Text(l.label,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: s.onPrimaryContainer)),
            if (l.line.isNotEmpty)
              Text(l.line,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: s.onPrimaryContainer)),
          ]),
        ),
      ),
    );
  }
}

/// "Show her the welcome again", pushed from the grown-up screen on her tablet (the grown-up has already proved who they
/// are there). It runs her cards from the hello and closes itself at the end or on "Later".
class ChildWelcomeReplay extends StatefulWidget {
  const ChildWelcomeReplay({super.key, required this.name, this.store, this.features = kGuidedFeaturesOn});
  final String? name;
  final GuidedProgressStore? store;
  final Set<String> features;

  @override
  State<ChildWelcomeReplay> createState() => _ChildWelcomeReplayState();
}

class _ChildWelcomeReplayState extends State<ChildWelcomeReplay> {
  late final GuidedController _c;

  @override
  void initState() {
    super.initState();
    final List<GuidedEntry> cards = resolveGuidedEntries(half: GuidedHalf.child, features: widget.features)
        .where((GuidedEntry e) => e.id != 'c.offer' && e.id != 'c.start')
        .toList();
    _c = GuidedController(
        half: GuidedHalf.child,
        steps: cards,
        store: widget.store ?? LocalGuidedProgressStore(LocalServices.current.area('guidedtour')));
    _c.addListener(() {
      if (!mounted) return;
      if (_c.finished) {
        Navigator.of(context).maybePop();
      } else {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: ChildWelcomeCard(
          key: ValueKey<String>('replay-${_c.current.id}'),
          controller: _c,
          entry: _c.current,
          name: widget.name,
          onHome: () => unawaited(_c.finish()),
        ),
      );
}
