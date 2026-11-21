// OLIVE BRANCH — the grown-up's half of the guided first run, from the connect step onward, and the "What's new" mini
// tour. MASTERFILE §8.5.13. Words: docs/planning/ONBOARDING-SCRIPT.md (guided_script.dart is the same table).
//
// [GuidedAdultHost] wraps the grown-up's HOME. It draws NOTHING unless one of these is true, so an install that already
// finished first run and has nothing new is exactly as it was:
//   * first run is under way: the PIN was saved (by guardian_onboarding.dart) and the saved step is the connect step or
//     later: resume there, including at a tour stop after the app was killed;
//   * "Show me around again" (Settings > Help) or the developer simulation seam (guided_sim.dart): the full tour from
//     the welcome, without asking for her name, age or PIN again;
//   * a "What's new" mini-tour: this install finished first run earlier, and a feature registered entries newer than the
//     script version it last saw (guided_registry.dart). Shown once; Skip marks it seen; "Do this later" leaves it for
//     the next launch.
// The tour points at real icons through [CoachAnchor]; nothing here changes the home or its data.
import 'dart:async';

import 'package:flutter/material.dart';

import 'connect_child_screen.dart';
import 'device_keys.dart';
import 'guardian_local_scope.dart';
import 'guided_engine.dart';
import 'guided_progress.dart';
import 'guided_registry.dart';
import 'guided_script.dart';
import 'guided_sim.dart';
import 'guided_widgets.dart';
import 'local_pin.dart' show kLocalGuardianScope;
import 'local_services.dart';
import 'pairing_picture.dart';
import 'pairing_records.dart';
import 'pairing_trust.dart';

/// "Show me around again": Settings raises this; the host (if mounted) starts the tour.
class GuidedReplay {
  GuidedReplay._();
  static final ValueNotifier<int> request = ValueNotifier<int>(0);
  static void ask() => request.value++;
}

const Map<String, String> _kPartNames = <String, String>{
  'tablet': 'Connect her tablet',
  'tour': 'The tour of your home',
};

enum _Mode { none, firstRun, replay, mini }

/// Builds the screen the connect step opens. Tests and the simulation seam replace it.
typedef GuidedConnectBuilder = Widget Function(
    BuildContext context, {required String childName, required VoidCallback onConnected});

class GuidedAdultHost extends StatefulWidget {
  const GuidedAdultHost({
    super.key,
    required this.child,
    this.store,
    this.features = kGuidedFeaturesOn,
    this.registered = kRegisteredGuidedEntries,
    this.scriptVersion = kGuidedScriptVersion,
    this.simulate = kSimOnboarding,
    this.childName,
    this.connectBuilder,
  });

  final Widget child;
  final GuidedProgressStore? store;
  final Set<String> features;
  final List<GuidedEntry> registered;
  final int scriptVersion;

  /// The developer seam: start the tour on an install that already finished first run.
  final bool simulate;

  /// Her first name; null reads it from the local family.
  final String? childName;
  final GuidedConnectBuilder? connectBuilder;

  @override
  State<GuidedAdultHost> createState() => _GuidedAdultHostState();
}

class _GuidedAdultHostState extends State<GuidedAdultHost> {
  GuidedController? _ctl;
  _Mode _mode = _Mode.none;
  List<GuidedEntry> _full = const <GuidedEntry>[];
  late final GuidedProgressStore _store;
  bool _connected = false;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _store = widget.store ?? LocalGuidedProgressStore(LocalServices.current.area('guidedtour'));
    GuidedReplay.request.addListener(_replay);
    unawaited(_decide());
  }

  @override
  void dispose() {
    GuidedReplay.request.removeListener(_replay);
    _ctl?.dispose();
    super.dispose();
  }

  List<GuidedEntry> _resolve({int? seen}) =>
      resolveGuidedEntries(half: GuidedHalf.adult, seenVersion: seen, features: widget.features, registered: widget.registered, scriptVersion: widget.scriptVersion);

  bool _isSetup(GuidedEntry e) => e.slot == 'adult.setup' || e.id == 'a.welcome';

  Future<void> _decide() async {
    GuidedProgress p;
    try {
      p = await _store.load();
    } catch (_) {
      p = const GuidedProgress();
    }
    if (!mounted) return;
    _full = _resolve();
    if (widget.simulate) return _start(_Mode.replay, p, _full.where((GuidedEntry e) => e.slot != 'adult.setup').toList());
    if (p.exists && !p.adultDone && p.adultStep != null) {
      // First run is under way. The PIN is saved (this home exists only after it), so the steps before the connect
      // step are over; a saved step inside them means "start at the connect step".
      final List<GuidedEntry> after = _full.where((GuidedEntry e) => !_isSetup(e)).toList();
      final int at = GuidedController.resumeIndex(after, p.adultStep);
      return _start(_Mode.firstRun, p, after, startIndex: at);
    }
    final List<GuidedEntry> delta = _resolve(seen: p.seenVersion);
    if (delta.isNotEmpty) _start(_Mode.mini, p, delta);
  }

  void _replay() {
    unawaited(() async {
      final GuidedProgress p = await _store.load();
      if (!mounted) return;
      _full = _resolve();
      _start(_Mode.replay, p, _full.where((GuidedEntry e) => e.slot != 'adult.setup').toList());
    }());
  }

  void _start(_Mode mode, GuidedProgress p, List<GuidedEntry> steps, {int startIndex = 0}) {
    if (steps.isEmpty) return;
    _ctl?.dispose();
    final GuidedController c = GuidedController(
      half: GuidedHalf.adult,
      steps: steps,
      store: _store,
      progress: mode == _Mode.replay ? p.copyWith(adultDone: false, deferred: const <String>[]) : p,
      startIndex: startIndex,
      mini: mode == _Mode.mini,
      scriptVersion: widget.scriptVersion,
    );
    c.addListener(() {
      if (mounted) setState(() {});
    });
    setState(() {
      _ctl = c;
      _mode = mode;
      _connected = false;
      _dismissed = false;
    });
    // A mini-tour and a replay do not move the first-run step; a first run saves where it is.
    if (mode == _Mode.firstRun) unawaited(c.start());
  }

  String? get _name {
    if (widget.childName != null) return widget.childName;
    final String? n = GuardianLocalScope.maybeOf(context)?.family?.childName;
    return n;
  }

  ({int step, int of}) _strip(GuidedController c) {
    // A mini-tour counts its own stops one by one; a replay counts the parts it has (the setup is not asked again).
    if (_mode == _Mode.mini) return (step: c.index + 1, of: c.steps.length);
    if (_mode == _Mode.replay) return guidedStrip(c.steps, c.index);
    final int i = _full.indexWhere((GuidedEntry e) => e.id == c.current.id);
    return i < 0 ? guidedStrip(c.steps, c.index) : guidedStrip(_full, i);
  }

  Widget _connectScreen(BuildContext context) {
    void done() {
      _connected = true;
      unawaited(_ctl?.partDone('tablet'));
    }

    final String childName = _name ?? '';
    final GuidedConnectBuilder? b = widget.connectBuilder;
    if (b != null) return b(context, childName: childName, onConnected: done);
    if (widget.simulate) {
      return SimulatedTabletScreen(childName: childName, onConnected: () {
        done();
        Navigator.of(context).maybePop();
      });
    }
    return defaultGuidedConnectScreen(context, childName: childName, onConnected: done);
  }

  Future<void> _openConnect(BuildContext context) async {
    _connected = false;
    await Navigator.of(context).push<void>(MaterialPageRoute<void>(builder: (BuildContext c) => _connectScreen(c)));
    if (!mounted) return;
    if (_connected) await _ctl?.next();
  }

  Widget _overlay(BuildContext context, GuidedController c) {
    if (c.paused) return GuidedPauseCard(controller: c);
    final GuidedEntry e = c.current;
    final bool mini = _mode == _Mode.mini;
    final String? eyebrow = mini ? "What's new" : null;
    final ({int step, int of}) strip = _strip(c);
    if (e.kind == GuidedKind.coach) {
      return CoachOverlay(
        controller: c, entry: e, name: _name, stripOverride: strip, eyebrow: eyebrow,
        onSkip: mini ? () => unawaited(c.finish()) : null,
        onLater: mini ? () => setState(() => _dismissed = true) : null,
      );
    }
    final List<Widget> footer = <Widget>[];
    if (e.kind == GuidedKind.end && c.deferredParts.isNotEmpty) {
      footer.add(Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Text('${GuidedWords.later} ${c.deferredParts.map((String p) => _kPartNames[p] ?? p).join(', ')}.',
            key: const Key('guidedLaterNote'), style: Theme.of(context).textTheme.bodyMedium),
      ));
    }
    final bool tablet = e.id == 'a.tablet';
    return Column(children: <Widget>[
      if (widget.simulate && _mode == _Mode.replay) const Material(child: SimBand()),
      Expanded(
        child: GuidedStepCard(
          controller: c, entry: e, name: _name, stripOverride: strip, eyebrow: eyebrow, footer: footer,
          onNext: tablet ? () => unawaited(_openConnect(context)) : () => unawaited(c.next()),
          onSkip: mini ? () => unawaited(c.finish()) : null,
          onLater: mini ? () => setState(() => _dismissed = true) : null,
        ),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final GuidedController? c = _ctl;
    final bool show = c != null && !c.finished && !_dismissed;
    return Stack(children: <Widget>[
      widget.child,
      if (show) Positioned.fill(child: KeyedSubtree(key: ValueKey<String>('guided-${c.current.id}-${c.paused}'), child: _overlay(context, c))),
    ]);
  }
}

/// The real connect screen with the helper strip: five numbered steps, which device to touch, a live waiting state and
/// a calm way back. The pairing logic is the existing screen's, unchanged.
Widget defaultGuidedConnectScreen(BuildContext context, {required String childName, required VoidCallback onConnected}) {
  final GuardianLocalController? local = GuardianLocalScope.maybeOf(context);
  if (local == null) {
    return Scaffold(
        appBar: AppBar(title: const Text("Connect a child's device")),
        body: const Center(child: Text('Connecting a device needs a PIN on this device. Set one up first.')));
  }
  final LocalServices services = LocalServices.current;
  return ConnectChildScreen(
    pin: local.services.pin,
    deviceKeys: LocalStoreDeviceKeyRepository(services.area('devicekey')),
    kids: LocalStorePairedKidsRepository(services.area('pairedkids', ownerId: kLocalGuardianScope)),
    adultName: local.family?.guardianName ?? 'A grown-up',
    childName: childName,
    childAge: local.family?.age,
    pictures: LocalStorePairingPictureRepository(services.area('devicekey')),
    trust: TrustBook(LocalStoreTrustRepository(services.area('trust', ownerId: kLocalGuardianScope))),
    onConnected: onConnected,
    guideBanner: (BuildContext c, ConnectGuideStage stage, bool hasMessage) =>
        GuidedConnectBanner(stage: stage, hasMessage: hasMessage, childName: childName),
  );
}

/// Which of the five hand-held steps to show for a stage of the connect screen.
int guidedTabletStepFor(ConnectGuideStage s) => switch (s) {
      ConnectGuideStage.intro => 1,
      ConnectGuideStage.waiting => 2,
      ConnectGuideStage.scanning => 4,
      ConnectGuideStage.approve => 5,
      ConnectGuideStage.sending => 5,
      ConnectGuideStage.done => 5,
    };

class GuidedConnectBanner extends StatelessWidget {
  const GuidedConnectBanner({super.key, required this.stage, required this.hasMessage, required this.childName});
  final ConnectGuideStage stage;
  final bool hasMessage;
  final String childName;

  @override
  Widget build(BuildContext context) {
    final ColorScheme s = Theme.of(context).colorScheme;
    final TextTheme t = Theme.of(context).textTheme;
    final bool done = stage == ConnectGuideStage.done;
    final bool waiting = stage == ConnectGuideStage.waiting;
    final int at = guidedTabletStepFor(stage);
    String fill(String x) => x.replaceAll('{name}', childName.isEmpty ? 'her' : childName);
    // While waiting, her tablet is where the next three steps happen: show 2 to 4 together so nobody is lost.
    final List<int> shown = done ? const <int>[] : waiting ? const <int>[2, 3, 4] : <int>[at];
    return Container(
      key: const Key('guidedConnectBanner'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: s.secondaryContainer, borderRadius: BorderRadius.circular(16)),
      child: Semantics(
        container: true,
        liveRegion: true,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: <Widget>[
          if (done)
            Text(fill(GuidedWords.tabletDone), key: const Key('guidedTabletDone'), style: t.titleMedium)
          else ...<Widget>[
            for (final int n in shown)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('Step $n of 5. ${GuidedWords.tabletSteps[n - 1]}',
                    key: Key('guidedTabletStep$n'), style: t.titleSmall),
              ),
            if (waiting)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(children: <Widget>[
                  const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 10),
                  Expanded(child: Text(fill(GuidedWords.tabletWait), key: const Key('guidedTabletWait'), style: t.bodyMedium)),
                ]),
              ),
            if (hasMessage)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(GuidedWords.tabletRecover, key: const Key('guidedTabletRecover'), style: t.bodyMedium),
              ),
          ],
        ]),
      ),
    );
  }
}
