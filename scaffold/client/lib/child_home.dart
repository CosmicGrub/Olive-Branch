// OLIVE BRANCH — child shell, home. UNVERIFIED (no Flutter toolchain in
// tools/verify.sh's automated pipeline — manually built and run this
// session, see HANDOFF notes, but verify.sh itself still can't find it). §8.1.
//
// Renders MARKUP screen 01. Three invariants the widget tree must preserve:
//   - Availability is stated in HER frame; his time is the aside. (§4.1)
//   - Countdown is in sleeps, computed on her local day boundary. (§8.2.5)
//   - No settings affordance exists at any depth. (§8.1)
import 'package:flutter/material.dart';
import 'pin_gate.dart';

/// Honest acknowledgment for a feature this preview build doesn't implement
/// yet, rather than a silent no-op — the same "recorded, not glossed over"
/// posture the rest of this project already takes for unbuilt surfaces.
void _notBuiltYet(BuildContext context, String what) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('$what — not built yet.'), duration: const Duration(seconds: 2)));
}

class ChildHome extends StatelessWidget {
  const ChildHome({super.key, required this.childName, required this.presence,
    required this.sleepsUntilHandover, required this.unreadCount});

  final String childName;
  final ParentPresence? presence;
  final int sleepsUntilHandover;
  final int unreadCount;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: [
      Text('Hi $childName', style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 12),
      if (presence != null) _PresenceCard(presence!),
      const SizedBox(height: 12),
      // 64dp minimum targets for pre-readers (§8.4), but a FIXED tile height.
      //
      // This was `GridView.count` with the default aspect ratio of 1, which
      // makes tile height scale with device WIDTH. On a tablet — the actual
      // target device for a child — two rows of square tiles consumed the whole
      // viewport and pushed the "sleeps until" counter below the fold, where a
      // child would never scroll to find it. Caught the first time these
      // widgets were rendered rather than contract-checked.
      GridView(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2, mainAxisSpacing: 10, crossAxisSpacing: 10,
          mainAxisExtent: 108),
        children: const [
          _Tile(icon: Icons.edit, label: 'Homework'),
          _Tile(icon: Icons.extension, label: 'Play together'),
          _Tile(icon: Icons.star_border, label: 'My list'),
          _Tile(icon: Icons.mail_outline, label: 'Messages'),
        ]),
      const SizedBox(height: 12),
      _Sleeps(sleepsUntilHandover),
      const SizedBox(height: 24),
      // Kiosk lock (§5.20) isn't implemented in this build — the native
      // bridge (see kiosk_channel.dart, MASTERFILE §20.2) has never been
      // compiled, so there is no real "kiosk defeat" event to trigger this
      // from. Reachable here only as a clearly-labeled dev preview so the
      // widget itself can be seen and exercised on a real device.
      Center(child: TextButton(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => PinGate(digits: 4, onComplete: (code) {
            Navigator.of(context).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('PIN entered — dev preview only.')));
          }),
        )),
        child: const Text('Preview: PIN gate (dev only)',
          style: TextStyle(fontSize: 11, color: Colors.black45)),
      )),
    ])),
  );
}

class ParentPresence {
  const ParentPresence(this.name, this.theirLocalTime, this.freeUntilHerTime);
  final String name, theirLocalTime, freeUntilHerTime;
}

class _PresenceCard extends StatelessWidget {
  const _PresenceCard(this.p);
  final ParentPresence p;
  @override
  Widget build(BuildContext context) => Card(child: Padding(
    padding: const EdgeInsets.all(14),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${p.name} is free right now',
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
      // HER frame first; his time is the aside.
      Text("It's ${p.theirLocalTime} where ${p.name} is · "
           'until ${p.freeUntilHerTime}',
        style: const TextStyle(fontSize: 12.5)),
      const SizedBox(height: 10),
      SizedBox(width: double.infinity, height: 48,
        child: FilledButton(
          onPressed: () => _notBuiltYet(context, 'Calling ${p.name}'),
          child: Text('Call ${p.name}'))),
    ]),
  ));
}

class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.label});
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => _notBuiltYet(context, label),
    child: Container(constraints: const BoxConstraints(minHeight: 64),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(14),
        color: Theme.of(context).colorScheme.primaryContainer),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 28), const Spacer(),
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      ])));
}

class _Sleeps extends StatelessWidget {
  const _Sleeps(this.n);
  final int n;
  @override
  Widget build(BuildContext context) => Row(children: [
    Text('$n', style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700)),
    const SizedBox(width: 10),
    // "sleeps", never hours. Children do not think in hours (§8.2.5).
    Text(n == 1 ? 'sleep until\nthe handover' : 'sleeps until\nthe handover',
      style: const TextStyle(fontSize: 12.5)),
  ]);
}
