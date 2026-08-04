// OLIVE BRANCH — guardian shell, home. UNVERIFIED (no Flutter toolchain in
// tools/verify.sh's automated pipeline). §8.2.
//
// Renders MARKUP screen 05. The dual clock is persistent and the CHILD's time is
// dominant; the parent never performs a timezone calculation (§8.2.3). All times
// arrive pre-rendered from /now and /ribbon so the client does no zone maths.
//
// Action grid below mirrors child_home.dart's tile pattern — parity of
// structure, not just of read-only status. Three tiles are real, genuinely
// functional screens (§9.5 message banking, §9.6.3 emergency card, P8
// handover notes); the rest are honest not-built-yet stubs, same posture
// child_home.dart already takes for its own unbuilt tiles.
import 'package:flutter/material.dart';
import 'call_screen.dart';
import 'emergency_card.dart';
import 'handover_notes.dart';
import 'message_banking.dart';

void _notBuiltYet(BuildContext context, String what) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('$what — not built yet.'), duration: const Duration(seconds: 2)));
}

class RibbonBand {
  const RibbonBand(this.startFraction, this.widthFraction, this.color, this.label);
  final double startFraction, widthFraction;
  final Color color;
  final String label;
}

class GuardianHome extends StatelessWidget {
  const GuardianHome({super.key, required this.childName,
    required this.childLocalTime, required this.childZoneAbbr,
    required this.actorLocalTime, required this.childStateSentence,
    required this.childBands, required this.actorBands, this.overlapLabel});

  final String childName, childLocalTime, childZoneAbbr, actorLocalTime;
  final String childStateSentence;
  final List<RibbonBand> childBands, actorBands;
  final String? overlapLabel;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: ListView(children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic, children: [
                Text(childName, style: const TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w600)),
                const SizedBox(width: 7),
                Text(childLocalTime, style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w600,
                  fontFeatures: [FontFeature.tabularFigures()])),
                const SizedBox(width: 4),
                Text(childZoneAbbr, style: const TextStyle(fontSize: 10)),
              ]),
            // Actor time is subordinate, always.
            Text('you · $actorLocalTime', style: const TextStyle(fontSize: 11)),
            const SizedBox(height: 5),
            Text(childStateSentence, style: const TextStyle(fontSize: 12.5)),
            const SizedBox(height: 10),
            SizedBox(width: double.infinity, height: 48,
              child: FilledButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const CallScreen(who: 'dad', displayName: 'Dad'))),
                child: Text('Call $childName'))),
          ])),
        _Ribbon(label: "$childName's day", bands: childBands, height: 20),
        const SizedBox(height: 8),
        _Ribbon(label: 'you', bands: actorBands, height: 13),
        if (overlapLabel != null) Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
          child: Text(overlapLabel!, style: const TextStyle(fontSize: 11))),
        const SizedBox(height: 20),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GridView(shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2, mainAxisSpacing: 10, crossAxisSpacing: 10,
              mainAxisExtent: 108),
            children: [
              _GTile(icon: Icons.schedule_send, label: 'Message banking',
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const MessageBankingScreen()))),
              _GTile(icon: Icons.medical_information, label: 'Emergency card',
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const EmergencyCardScreen()))),
              _GTile(icon: Icons.receipt_long, label: 'Handover notes',
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const HandoverNotesScreen()))),
              _GTile(icon: Icons.swap_horiz, label: 'Exchange',
                onTap: () => _notBuiltYet(context, 'Exchange')),
              _GTile(icon: Icons.account_balance_wallet, label: 'Expenses',
                onTap: () => _notBuiltYet(context, 'Expenses')),
              _GTile(icon: Icons.event_available, label: 'Availability',
                onTap: () => _notBuiltYet(context, 'Availability')),
            ])),
        const SizedBox(height: 16),
      ])),
  );
}

class _GTile extends StatelessWidget {
  const _GTile({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(constraints: const BoxConstraints(minHeight: 64),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(14),
        color: Theme.of(context).colorScheme.primaryContainer),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 28), const Spacer(),
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      ])));
}

class _Ribbon extends StatelessWidget {
  const _Ribbon({required this.label, required this.bands, required this.height});
  final String label;
  final List<RibbonBand> bands;
  final double height;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label.toUpperCase(), style: const TextStyle(fontSize: 9, letterSpacing: 0.7)),
      const SizedBox(height: 4),
      // Explicit-width Positioned segments, NOT Row+Expanded/flex: on this engine
      // build (Flutter 3.44.8 stable, Impeller/Vulkan), Expanded children inside a
      // Row silently paint nothing -- no exception, no layout error, confirmed by
      // bisection (fixed-width Container siblings in the same Row render fine;
      // swapping only the width source to Expanded/flex reproduces the blank
      // ribbon). Root cause is upstream of this widget, so the fix routes around
      // Expanded entirely rather than trying to unblock it.
      //
      // As a side benefit this uses `startFraction` (previously computed but
      // discarded -- Expanded flex only ever consumed widthFraction), so gaps
      // between non-contiguous bands now render as gaps instead of being folded
      // into the neighbouring band's width.
      ClipRRect(borderRadius: BorderRadius.circular(2),
        child: SizedBox(height: height, width: double.infinity,
          child: LayoutBuilder(builder: (context, constraints) {
            final w = constraints.maxWidth;
            return Stack(children: [for (final b in bands) Positioned(
              left: w * b.startFraction, width: w * b.widthFraction,
              top: 0, bottom: 0,
              child: Tooltip(message: b.label, child: ColoredBox(color: b.color)),
            )]);
          }))),
    ]));
}
