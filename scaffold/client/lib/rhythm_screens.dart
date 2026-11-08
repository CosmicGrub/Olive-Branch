// OLIVE BRANCH — suite B RHYTHM, the child's screens: one routine, first-then,
// packing buddy, a new place. No longer UNVERIFIED — verified by CI
// (client/test/rhythm_screens_test.dart).
//
// Picture-first (she is five going on six), every target at least 64dp, calm.
// OFFLINE AND ON-DEVICE: these screens read and tick what a guardian wrote on
// THIS device. There is no editor here (the child shell has no settings, §8.1);
// the guardian side lives in rhythm_voice_guardian_screens.dart and this file
// never imports it.
//
// No scores, streaks, rewards or counters (P2): no screen shows "3 of 8", a
// bar, a star or a streak, and finishing is a calm resting state, not a result.
// "How the app feels" (the sensory profile) is applied here through
// [SensoryScope]: motion, haptics and a brightness ceiling, on this subtree
// only. Read-aloud is the optional `speak` seam (see picture_icons.dart).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'family_structure_logic.dart' show FamilyPrincipal;
import 'picture_icons.dart';
import 'read_aloud.dart' show ReadAloudScope;
import 'rhythm_logic.dart';
import 'rhythm_voice_repositories.dart';

/// The principal a child screen acts as: this child, on this device.
FamilyPrincipal childPrincipalFor(RhythmVoiceService s) => FamilyPrincipal(roleName: 'child', childId: s.childId);

// ------------------------------------------------------------ SensoryScope ---
/// Applies a guardian's "how the app feels" settings to one subtree: reduced
/// motion (the subtree's MediaQuery says animations are off), a brightness
/// ceiling (a soft dim layer; no platform call), and whether a tap may buzz or a
/// word may be spoken. The profile loads from the device; until it has, the
/// defaults (the app as it always was) apply.
class SensoryScope extends StatefulWidget {
  const SensoryScope({super.key, required this.service, required this.child});
  final RhythmVoiceService service;
  final Widget child;

  static SensoryDefaults of(BuildContext context) {
    final _SensoryInherited? i = context.dependOnInheritedWidgetOfExactType<_SensoryInherited>();
    return i?.defaults ?? sensoryDefaults(const SensoryProfile());
  }

  /// A tap's buzz, only if it is allowed.
  static void tap(BuildContext context) {
    if (of(context).haptics) HapticFeedback.selectionClick();
  }

  /// [speak] wrapped so that nothing is spoken when the sound is off.
  static Speak? speakFor(BuildContext context, Speak? speak) {
    // The screen's own seam if given, else the app's read-aloud (when it is on for her).
    final Speak? s = speak ?? ReadAloudScope.speakFnIfEnabled(context);
    if (s == null || of(context).silent) return null;
    return s;
  }

  @override
  State<SensoryScope> createState() => _SensoryScopeState();
}

class _SensoryScopeState extends State<SensoryScope> {
  SensoryProfile _profile = const SensoryProfile();

  @override
  void initState() {
    super.initState();
    widget.service.loadRhythm(childPrincipalFor(widget.service)).then((RhythmDoc d) {
      if (mounted) setState(() => _profile = d.sensory);
    }).catchError((Object _) {});
  }

  @override
  Widget build(BuildContext context) {
    final MediaQueryData mq = MediaQuery.of(context);
    final SensoryDefaults d = sensoryDefaults(_profile, osReduceMotion: mq.disableAnimations);
    Widget body = widget.child;
    if (!d.animate && !mq.disableAnimations) {
      body = MediaQuery(data: mq.copyWith(disableAnimations: true), child: body);
    }
    final double dim = 1 - d.maxBrightness;
    if (dim > 0) {
      body = Stack(fit: StackFit.expand, children: <Widget>[
        body,
        Positioned.fill(
            child: IgnorePointer(
                child: ColoredBox(key: const Key('brightnessCeiling'), color: Colors.black.withValues(alpha: dim)))),
      ]);
    }
    return _SensoryInherited(defaults: d, child: body);
  }
}

class _SensoryInherited extends InheritedWidget {
  const _SensoryInherited({required this.defaults, required super.child});
  final SensoryDefaults defaults;
  @override
  bool updateShouldNotify(_SensoryInherited old) =>
      old.defaults.volume != defaults.volume || old.defaults.animate != defaults.animate ||
      old.defaults.haptics != defaults.haptics || old.defaults.maxBrightness != defaults.maxBrightness;
}

/// Page chrome every child screen of B and C shares. The screens wrap
/// themselves in a [SensoryScope] ABOVE their State, so everything below (and
/// every handler) sees the guardian's "how the app feels" settings.
class RvChildPage extends StatelessWidget {
  const RvChildPage({super.key, required this.service, required this.title, required this.body});
  final RhythmVoiceService service;
  final String title;
  final Widget body;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: body)),
      );
}

// ================================================================ ROUTINE ====
class MyRoutineScreen extends StatelessWidget {
  const MyRoutineScreen({super.key, required this.service, this.speak});
  final RhythmVoiceService service;
  final Speak? speak;
  @override
  Widget build(BuildContext context) =>
      SensoryScope(service: service, child: _MyRoutineScreenView(service: service, speak: speak));
}

class _MyRoutineScreenView extends StatefulWidget {
  const _MyRoutineScreenView({required this.service, this.speak});
  final RhythmVoiceService service;
  final Speak? speak;
  @override
  State<_MyRoutineScreenView> createState() => _MyRoutineScreenState();
}

class _MyRoutineScreenState extends State<_MyRoutineScreenView> {
  Routine? _routine;
  DayTicks _ticks = const DayTicks();
  bool _loaded = false;

  FamilyPrincipal get _me => childPrincipalFor(widget.service);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ({Routine? routine, DayTicks ticks}) r = await widget.service.routineToday(_me);
    if (mounted) setState(() { _routine = r.routine; _ticks = r.ticks; _loaded = true; });
  }

  Future<void> _done() async {
    SensoryScope.tap(context);
    await widget.service.tickRoutine(_me);
    await _load();
  }

  Future<void> _again() async {
    await widget.service.routineAgain(_me);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final Routine? r = _routine;
    return RvChildPage(
      service: widget.service,
      title: r?.title ?? 'My routine',
      body: !_loaded
          ? const SizedBox.shrink()
          : (r == null || r.steps.isEmpty)
              ? const QuietNote('Your grown-up has not made one yet.', icon: Icons.checklist_outlined)
              : _body(context, r),
    );
  }

  Widget _body(BuildContext context, Routine r) {
    final FirstThen ft = firstThenOf(r, _ticks);
    final Speak? speak = SensoryScope.speakFor(context, widget.speak);
    final bool reduce = reduceMotionOf(context);
    final Set<String> done = _ticks.done.toSet();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
      AnimatedSwitcher(
        duration: reduce ? Duration.zero : const Duration(milliseconds: 250),
        child: KeyedSubtree(
          key: ValueKey<String>(ft.allDone ? 'done' : ft.first!.id),
          child: ft.allDone
              ? Column(children: <Widget>[
                  const Icon(Icons.check_circle_outline, size: 72),
                  const SizedBox(height: 8),
                  Text('All done', key: const Key('routineAllDone'), style: Theme.of(context).textTheme.headlineSmall),
                ])
              : LayoutBuilder(builder: (BuildContext c, BoxConstraints box) {
                  final Widget first = _BigCard(key: const Key('routineFirst'), heading: 'First',
                      picture: ft.first!.picture, label: ft.first!.label, strong: true, speak: speak);
                  final Widget? then = ft.then == null
                      ? null
                      : _BigCard(key: const Key('routineThen'), heading: 'Then',
                          picture: ft.then!.picture, label: ft.then!.label, strong: false, speak: speak);
                  if (box.maxWidth >= 520 && then != null) {
                    return Row(crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[Expanded(child: first), const SizedBox(width: 12), Expanded(child: then)]);
                  }
                  return Column(children: <Widget>[first, if (then != null) ...<Widget>[const SizedBox(height: 12), then]]);
                }),
        ),
      ),
      const SizedBox(height: 16),
      if (ft.allDone)
        SizedBox(height: 72, child: FilledButton.tonalIcon(
            key: const Key('routineAgain'), onPressed: _again, icon: const Icon(Icons.replay), label: const Text('Again')))
      else
        SizedBox(height: 72, child: FilledButton.icon(
            key: const Key('routineDone'), onPressed: _done, icon: const Icon(Icons.check), label: const Text('Done'))),
      const SizedBox(height: 20),
      // The whole routine as a quiet picture strip. A ticked step is paler with a
      // tick on it. There is no number, bar or count anywhere.
      Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: <Widget>[
        for (final RoutineStep s in r.steps)
          Semantics(
            label: done.contains(s.id) ? '${s.label}, done' : s.label,
            child: Stack(children: <Widget>[
              PictureGlyph(s.picture, size: 28, soft: done.contains(s.id)),
              if (done.contains(s.id)) const Positioned(right: 2, bottom: 2, child: Icon(Icons.check_circle, size: 18)),
            ]),
          ),
      ]),
    ]);
  }
}

class _BigCard extends StatelessWidget {
  const _BigCard({super.key, required this.heading, required this.picture, required this.label,
      required this.strong, this.speak});
  final String heading;
  final String picture;
  final String label;
  final bool strong;
  final Speak? speak;
  @override
  Widget build(BuildContext context) {
    final ColorScheme c = Theme.of(context).colorScheme;
    return Semantics(
      container: true, label: '$heading: $label',
      child: Container(
        constraints: const BoxConstraints(minHeight: 150),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: strong ? c.surface : c.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(22),
          border: strong ? Border.all(color: c.primary, width: 3) : null,
        ),
        child: Stack(children: <Widget>[
          Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
              PictureGlyph(picture, size: strong ? 56 : 40, soft: !strong),
              const SizedBox(height: 8),
              Text(heading, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              Text(label, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
            ]),
          ),
          if (speak != null)
            Positioned(right: 0, top: 0, child: SizedBox(width: 48, height: 48, child: IconButton(
                tooltip: 'Hear $label', icon: const Icon(Icons.volume_up_outlined), onPressed: () => speak!(label)))),
        ]),
      ),
    );
  }
}

// ============================================================== FIRST, THEN ==
class FirstThenScreen extends StatelessWidget {
  const FirstThenScreen({super.key, required this.service, this.speak});
  final RhythmVoiceService service;
  final Speak? speak;
  @override
  Widget build(BuildContext context) =>
      SensoryScope(service: service, child: _FirstThenScreenView(service: service, speak: speak));
}

class _FirstThenScreenView extends StatefulWidget {
  const _FirstThenScreenView({required this.service, this.speak});
  final RhythmVoiceService service;
  final Speak? speak;
  @override
  State<_FirstThenScreenView> createState() => _FirstThenScreenState();
}

class _FirstThenScreenState extends State<_FirstThenScreenView> {
  FirstThenBoard? _board;
  BoardState _state = const BoardState();
  bool _loaded = false;
  FamilyPrincipal get _me => childPrincipalFor(widget.service);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final RhythmDoc d = await widget.service.loadRhythm(_me);
    final BoardState s = await widget.service.boardToday(_me);
    if (mounted) setState(() { _board = d.board; _state = s; _loaded = true; });
  }

  Future<void> _done() async {
    SensoryScope.tap(context);
    await widget.service.markBoardFirstDone(_me);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final FirstThenBoard? b = _board;
    return RvChildPage(
      service: widget.service,
      title: 'First, then',
      body: !_loaded
          ? const SizedBox.shrink()
          : b == null
              ? const QuietNote('Your grown-up has not set this up yet.', icon: Icons.swap_horiz)
              : _body(context, b),
    );
  }

  Widget _body(BuildContext context, FirstThenBoard b) {
    final Speak? speak = SensoryScope.speakFor(context, widget.speak);
    final bool firstDone = _state.firstDone;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
      Stack(children: <Widget>[
        _BigCard(key: const Key('boardFirst'), heading: 'First', picture: b.first.picture, label: b.first.label,
            strong: !firstDone, speak: speak),
        if (firstDone) const Positioned(left: 14, top: 14, child: Icon(Icons.check_circle, size: 28)),
      ]),
      const SizedBox(height: 12),
      _BigCard(key: const Key('boardThen'), heading: firstDone ? 'Now' : 'Then', picture: b.then.picture,
          label: b.then.label, strong: firstDone, speak: speak),
      const SizedBox(height: 16),
      if (!firstDone)
        SizedBox(height: 72, child: FilledButton.icon(
            key: const Key('boardDone'), onPressed: _done, icon: const Icon(Icons.check), label: const Text('Done'))),
    ]);
  }
}

// ============================================================ PACKING BUDDY ==
class PackingBuddyScreen extends StatelessWidget {
  const PackingBuddyScreen({super.key, required this.service, this.speak});
  final RhythmVoiceService service;
  final Speak? speak;
  @override
  Widget build(BuildContext context) =>
      SensoryScope(service: service, child: _PackingBuddyScreenView(service: service, speak: speak));
}

class _PackingBuddyScreenView extends StatefulWidget {
  const _PackingBuddyScreenView({required this.service, this.speak});
  final RhythmVoiceService service;
  final Speak? speak;
  @override
  State<_PackingBuddyScreenView> createState() => _PackingBuddyScreenState();
}

class _PackingBuddyScreenState extends State<_PackingBuddyScreenView> {
  PackingList _list = const PackingList();
  PackTicks _ticks = const PackTicks();
  bool _loaded = false;
  FamilyPrincipal get _me => childPrincipalFor(widget.service);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final RhythmDoc d = await widget.service.loadRhythm(_me);
    final PackTicks t = await widget.service.packedToday(_me);
    if (mounted) setState(() { _list = d.packing; _ticks = t; _loaded = true; });
  }

  Future<void> _toggle(String id) async {
    SensoryScope.tap(context);
    await widget.service.togglePack(_me, id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final Speak? speak = SensoryScope.speakFor(context, widget.speak);
    return RvChildPage(
      service: widget.service,
      title: 'My bag',
      body: !_loaded
          ? const SizedBox.shrink()
          : _list.items.isEmpty
              ? const QuietNote('Your grown-up has not made a bag list yet.', icon: Icons.backpack_outlined)
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  Text('My things', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  PictureGrid(children: <Widget>[
                    for (final PackItem i in _list.toBring)
                      Stack(children: <Widget>[
                        PictureTile(
                          key: Key('pack_${i.id}'), picture: i.picture, label: i.label, speak: speak,
                          selected: _ticks.packed.contains(i.id), onTap: () => _toggle(i.id)),
                        if (_ticks.packed.contains(i.id))
                          const Positioned(left: 8, top: 8, child: Icon(Icons.check_circle, size: 22)),
                      ]),
                  ]),
                  if (_list.alwaysSame.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 20),
                    Text('Always the same', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
                      for (final PackItem i in _list.alwaysSame)
                        Chip(
                          key: Key('same_${i.id}'),
                          avatar: Icon(pictureIcon(i.picture), size: 20),
                          label: Text(i.label),
                          materialTapTargetSize: MaterialTapTargetSize.padded,
                        ),
                    ]),
                    const SizedBox(height: 6),
                    Text('These stay the same wherever you sleep.',
                        style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ]),
    );
  }
}

// ================================================================ NEW PLACE ==
class NewPlaceScreen extends StatelessWidget {
  const NewPlaceScreen({super.key, required this.service, this.speak});
  final RhythmVoiceService service;
  final Speak? speak;
  @override
  Widget build(BuildContext context) =>
      SensoryScope(service: service, child: _NewPlaceScreenView(service: service, speak: speak));
}

class _NewPlaceScreenView extends StatefulWidget {
  const _NewPlaceScreenView({required this.service, this.speak});
  final RhythmVoiceService service;
  final Speak? speak;
  @override
  State<_NewPlaceScreenView> createState() => _NewPlaceScreenState();
}

class _NewPlaceScreenState extends State<_NewPlaceScreenView> {
  PlacePlan? _plan;
  int _at = 0;
  bool _loaded = false;
  FamilyPrincipal get _me => childPrincipalFor(widget.service);

  @override
  void initState() {
    super.initState();
    widget.service.loadPlace(_me).then((PlacePlan? p) {
      if (mounted) setState(() { _plan = p; _loaded = true; });
    });
  }

  @override
  Widget build(BuildContext context) {
    final PlacePlan? p = _plan;
    return RvChildPage(
      service: widget.service,
      title: p?.name ?? 'A new place',
      body: !_loaded
          ? const SizedBox.shrink()
          : (p == null || p.isEmpty)
              ? const QuietNote('Your grown-up has not got this ready yet.', icon: Icons.home_outlined)
              : _walk(context, p),
    );
  }

  Widget _walk(BuildContext context, PlacePlan p) {
    final Speak? speak = SensoryScope.speakFor(context, widget.speak);
    final bool onPlan = _at >= p.stops.length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
      if (onPlan)
        Container(
          key: const Key('placePlan'),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(18)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text('What will happen', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            for (final String l in p.plan)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  const Icon(Icons.arrow_forward, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text(l, style: Theme.of(context).textTheme.titleMedium)),
                  if (speak != null)
                    SizedBox(width: 48, height: 48, child: IconButton(
                        tooltip: 'Hear this', icon: const Icon(Icons.volume_up_outlined), onPressed: () => speak(l))),
                ]),
              ),
          ]),
        )
      else
        _stop(context, p.stops[_at], speak),
      const SizedBox(height: 16),
      Row(children: <Widget>[
        if (_at > 0)
          Expanded(child: SizedBox(height: 64, child: OutlinedButton.icon(
              key: const Key('placeBack'), onPressed: () => setState(() => _at--),
              icon: const Icon(Icons.arrow_back), label: const Text('Back')))),
        if (_at > 0) const SizedBox(width: 12),
        if (!onPlan)
          Expanded(child: SizedBox(height: 64, child: FilledButton.icon(
              key: const Key('placeNext'),
              onPressed: () => setState(() {
                    // After the last room comes the plan, if there is one.
                    if (_at + 1 >= p.stops.length && p.plan.isEmpty) {
                      Navigator.of(context).maybePop();
                    } else {
                      _at++;
                    }
                  }),
              icon: const Icon(Icons.arrow_forward), label: const Text('Next')))),
        if (onPlan)
          Expanded(child: SizedBox(height: 64, child: FilledButton.icon(
              key: const Key('placeFinish'), onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.check), label: const Text('All done')))),
      ]),
    ]);
  }

  Widget _stop(BuildContext context, PlaceStop s, Speak? speak) {
    final ColorScheme c = Theme.of(context).colorScheme;
    Widget picture;
    if (s.photoB64 != null) {
      picture = ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Image.memory(base64Decode(s.photoB64!), key: Key('placePhoto_${s.id}'), height: 220, fit: BoxFit.cover,
            semanticLabel: s.caption, errorBuilder: (_, _, _) => PictureGlyph(s.room, size: 96)),
      );
    } else {
      picture = Container(
        height: 200, alignment: Alignment.center,
        decoration: BoxDecoration(color: c.primaryContainer, borderRadius: BorderRadius.circular(22)),
        child: Icon(pictureIcon(s.room), size: 96, color: c.onPrimaryContainer),
      );
    }
    return Column(key: Key('placeStop_${s.id}'), children: <Widget>[
      picture,
      const SizedBox(height: 12),
      Row(children: <Widget>[
        Expanded(child: Text(s.caption, style: Theme.of(context).textTheme.titleLarge)),
        if (speak != null)
          SizedBox(width: 48, height: 48, child: IconButton(
              tooltip: 'Hear this', icon: const Icon(Icons.volume_up_outlined), onPressed: () => speak(s.caption))),
      ]),
    ]);
  }
}
