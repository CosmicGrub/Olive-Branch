// OLIVE BRANCH — the games-door gate on HER device. UNVERIFIED until CI runs the
// new tests (test/play_window_gate_test.dart). MASTERFILE §8.6.6, §8.1, P2.
//
// The child's half of the play window (play_window_screen.dart is the
// guardian's). Kept in its own file so nothing guardian-facing is imported by the
// child shell. It reads only [ChildColourStore.playWindow] — there is no way to
// change the window from here — and it gates GAMES only: calls and family
// messages never pass through it. A game already in progress is never cut off;
// the gate stands at the door, not inside the game.
//
// During the wind-down a calm line appears over the games list ("It's getting
// sleepy. One more, then goodnight."). After it, the door shows a goodnight card
// until the window opens again. No number, no timer, no countdown, no red, no
// lock, and no word that sounds like a punishment: games are resting, not taken.
//
// The gate LISTENS to the clock. It re-reads the window once a minute (and when
// the app comes back to the front), so a wind-down that begins while she is looking
// at the games list arrives on its own, softly (a cross-fade, none under reduced
// motion), and a game she started before the rest time simply finishes: the games
// door is only checked again when she comes back to the list.
import 'dart:async';

import 'package:flutter/material.dart';

import 'access_scope.dart' show motionDuration;
import 'her_colour_store.dart';

/// The one calm sentence on the goodnight card. Pure so it can be tested for
/// numbers (there must be none) without pumping a widget.
String goodnightCardLine(PlayWindowInfo info) =>
    info.beforeOpen ? 'Games are still asleep. They’ll wake up later today.' : (info.line ?? '');

/// How often the gate looks at the clock again. A minute is plenty: the wind-down is
/// a quarter hour at the shortest.
const Duration playWindowRecheck = Duration(minutes: 1);

/// Stands at the games door on her device. Shows [child] unless the window is
/// resting; during the wind-down it adds the one calm line.
class PlayWindowGate extends StatefulWidget {
  const PlayWindowGate({super.key, required this.child, this.store, this.recheck = playWindowRecheck});
  final Widget child;
  /// Null uses the process-wide in-memory store.
  final ChildColourStore? store;
  /// How often to re-read the window. Tests pass a short one.
  final Duration recheck;

  @override
  State<PlayWindowGate> createState() => _PlayWindowGateState();
}

class _PlayWindowGateState extends State<PlayWindowGate> with WidgetsBindingObserver {
  late final ChildColourStore _store = widget.store ?? sharedColourStore;
  PlayWindowInfo? _info;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _read();
    _timer = Timer.periodic(widget.recheck, (_) => _read());
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _read();
  }

  Future<void> _read() async {
    final i = await _store.playWindow();
    if (!mounted) return;
    final old = _info;
    if (old != null && old.state == i.state && old.beforeOpen == i.beforeOpen && old.line == i.line) return;
    setState(() => _info = i);
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    final Widget body;
    if (info == null || info.state == 'open') {
      body = KeyedSubtree(key: const ValueKey('gateOpen'), child: widget.child);
    } else if (info.state == 'resting') {
      body = KeyedSubtree(key: const ValueKey('gateResting'), child: _Goodnight(line: goodnightCardLine(info)));
    } else {
      body = KeyedSubtree(key: const ValueKey('gateWinding'), child: Stack(children: [
        widget.child,
        Positioned(left: 12, right: 12, bottom: 12, child: SafeArea(child: Material(
          key: const Key('windDownBanner'),
          elevation: 3, borderRadius: BorderRadius.circular(16),
          color: Theme.of(context).colorScheme.secondaryContainer,
          child: Padding(padding: const EdgeInsets.all(14),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.nightlight_round, size: 22, color: Theme.of(context).colorScheme.onSecondaryContainer),
              const SizedBox(width: 10),
              Flexible(child: Text(info.line ?? '', textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium)),
            ]))))),
      ]));
    }
    return AnimatedSwitcher(duration: motionDuration(context, 400), child: body);
  }
}

class _Goodnight extends StatelessWidget {
  const _Goodnight({required this.line});
  final String line;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Goodnight')),
    body: SafeArea(child: Center(child: SingleChildScrollView(child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.nightlight_round, size: 72, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 16),
        Text(line, key: const Key('goodnightLine'), textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge),
      ]))))));
}
