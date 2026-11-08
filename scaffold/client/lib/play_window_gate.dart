// OLIVE BRANCH — the games-door gate on HER device. No longer UNVERIFIED —
// verified by CI (a Flutter toolchain runs for real in tools/verify.sh's
// automated pipeline). MASTERFILE §8.6.6, §8.1.
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
// until the window opens again. No number, no timer, no red, no lock.
import 'package:flutter/material.dart';
import 'her_colour_store.dart';

/// Stands at the games door on her device. Shows [child] unless the window is
/// resting; during the wind-down it adds the one calm line.
class PlayWindowGate extends StatefulWidget {
  const PlayWindowGate({super.key, required this.child, this.store});
  final Widget child;
  /// Null uses the process-wide in-memory store.
  final ChildColourStore? store;

  @override
  State<PlayWindowGate> createState() => _PlayWindowGateState();
}

class _PlayWindowGateState extends State<PlayWindowGate> {
  late final ChildColourStore _store = widget.store ?? sharedColourStore;
  PlayWindowInfo? _info;

  @override
  void initState() {
    super.initState();
    _store.playWindow().then((i) {
      if (mounted) setState(() => _info = i);
    });
  }

  @override
  Widget build(BuildContext context) {
    final info = _info;
    if (info == null || info.state == 'open') return widget.child;
    if (info.state == 'resting') {
      return Scaffold(
        appBar: AppBar(title: const Text('Goodnight')),
        body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.nightlight_round, size: 56),
          const SizedBox(height: 12),
          Text(info.line ?? '', key: const Key('goodnightLine'), textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge),
        ]))));
    }
    return Stack(children: [
      widget.child,
      Positioned(left: 12, right: 12, bottom: 12, child: SafeArea(child: Material(
        key: const Key('windDownBanner'),
        elevation: 3, borderRadius: BorderRadius.circular(16),
        color: Theme.of(context).colorScheme.secondaryContainer,
        child: Padding(padding: const EdgeInsets.all(14),
          child: Text(info.line ?? '', textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium))))),
    ]);
  }
}
