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
import 'package:http/http.dart' as http;
import 'availability_screen.dart';
import 'call_screen.dart';
import 'care_note.dart';
import 'emergency_card.dart';
import 'exchange_screen.dart';
import 'expenses_screen.dart';
import 'form_factors.dart' as ff;
import 'guardian_more.dart';
import 'handover_notes.dart';
import 'meds_care.dart';
import 'message_banking.dart';
import 'morning_briefing.dart';
import 'send_time_guard.dart';

/// Opens the real AvailabilityScreen when this home screen has actually been
/// given a live session (baseUrl/guardianId/childId — see GuardianHome's own
/// field doc comment); otherwise gives honest feedback rather than a silent
/// no-op or a screen built on data it doesn't have. Shared by GuardianHome's
/// own quick-access tile and guardian_more.dart's GuardianMoreScreen — same
/// helper, so the two entry points can never say different things about the
/// same real screen.
void _openAvailability(BuildContext context, {
  required String? baseUrl, required String? guardianId, required String? childId,
  http.Client? httpClient,
}) {
  if (baseUrl != null && guardianId != null && childId != null) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => AvailabilityScreen(
      baseUrl: baseUrl, guardianId: guardianId, childId: childId, httpClient: httpClient)));
    return;
  }
  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
    content: Text("Availability needs a live session — not connected in this preview build."),
    duration: Duration(seconds: 3)));
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
    required this.childBands, required this.actorBands, this.overlapLabel,
    this.baseUrl, this.guardianId, this.childId, this.availabilityHttpClient});

  final String childName, childLocalTime, childZoneAbbr, actorLocalTime;
  final String childStateSentence;
  final List<RibbonBand> childBands, actorBands;
  final String? overlapLabel;

  /// Live-session wiring for the real AvailabilityScreen (both this
  /// screen's own quick-access tile and the one nested in
  /// guardian_more.dart's GuardianMoreScreen) — see guardian_more.dart's own
  /// field doc comment for why these are optional and null in every current
  /// call site (main.dart's static demo data carries none of them yet).
  final String? baseUrl;
  final String? guardianId;
  final String? childId;
  /// Injectable for tests only — matches GuardianMoreScreen's own field.
  final http.Client? availabilityHttpClient;

  @override
  Widget build(BuildContext context) => Scaffold(
    // SingleChildScrollView + Column, NOT ListView: see child_home.dart's own
    // comment on the same fix — a sliver-backed list drops children scrolled
    // below the fold from the element tree, and this wiring pass's grid
    // expansion (six new guardian tiles) pushed real content well past the
    // default test viewport.
    body: SafeArea(child: SingleChildScrollView(child: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic, children: [
                Text(childName, style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(width: 4),
                // The CHILD's clock is dominant — same titleMedium weight as
                // her name, well above the actor line below (§8.2.3).
                Text(childLocalTime, style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()])),
                const SizedBox(width: 4),
                Text(childZoneAbbr, style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ]),
            // Actor time is subordinate, always.
            Text('you · $actorLocalTime', style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 4),
            Text(childStateSentence, style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 12),
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
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(overlapLabel!, style: Theme.of(context).textTheme.labelSmall
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant))),
        const SizedBox(height: 20),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
          // LayoutBuilder-driven breakpoint, not a single fixed extent: at the
          // Fold5 cover-screen width (344px logical, ~151px per column here)
          // the longer two-word labels ('Send-time guard', 'Morning
          // briefing') wrap to three lines and a flat mainAxisExtent: 108
          // overflowed the tile by 4px -- caught by widget tests pinned to
          // that exact width, not by inspection. Wider layouts keep the
          // original, more compact extent.
          child: LayoutBuilder(builder: (context, constraints) {
            final textScale = MediaQuery.textScalerOf(context).scale(1);
            // Floor of 2, not columnsAt()'s raw output: columnsAt() returns 1
            // below 660px effective width, which would collapse BOTH real
            // test devices (Fold5 cover screen, ~312px inside this grid's
            // padding, and the 7-inch tabletSmall posture, 600px min) from
            // the deliberately-tuned 2-column layout down to a single
            // stacked column. Only scale UP on genuinely wide guardian
            // surfaces (desktop/dex/wide tabletLarge), never down.
            final crossAxisCount = ff.columnsAt(
              ff.Viewport(w: constraints.maxWidth, h: constraints.maxHeight), textScale,
            ).clamp(2, 3);
            final gapTotal = 10.0 * (crossAxisCount - 1);
            final effectiveColumnWidth =
                (constraints.maxWidth / textScale - gapTotal) / crossAxisCount;
            final mainAxisExtent = effectiveColumnWidth < 165.0 ? 128.0 : 108.0;
            return GridView(shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount, mainAxisSpacing: 10, crossAxisSpacing: 10,
              mainAxisExtent: mainAxisExtent),
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
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => ExchangeScreen(childName: childName)))),
              _GTile(icon: Icons.account_balance_wallet, label: 'Expenses',
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => ExpensesScreen(childName: childName)))),
              _GTile(icon: Icons.event_available, label: 'Availability',
                onTap: () => _openAvailability(context,
                  baseUrl: baseUrl, guardianId: guardianId, childId: childId,
                  httpClient: availabilityHttpClient)),
              _GTile(icon: Icons.schedule, label: 'Send-time guard',
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => SendTimeGuardScreen(childName: childName)))),
              _GTile(icon: Icons.medical_services_outlined, label: 'Meds & care',
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => MedsCareScreen(childName: childName)))),
              _GTile(icon: Icons.wb_twilight, label: 'Morning briefing',
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const MorningBriefingScreen()))),
              _GTile(icon: Icons.favorite_border, label: 'Care note',
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => CareNoteScreen(childName: childName,
                    baseUrl: baseUrl, guardianId: guardianId, childId: childId,
                    httpClient: availabilityHttpClient)))),
              _GTile(icon: Icons.more_horiz, label: 'More',
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => GuardianMoreScreen(childName: childName,
                    baseUrl: baseUrl, guardianId: guardianId,
                    // GuardianMoreScreen.childId is non-nullable (it also
                    // keys the family-agreement fetch, which needs SOME
                    // concrete child even pre-live-session) — same
                    // seed-dev.mjs 'Ivy' fallback main_live.dart's own
                    // defaultValue uses, not a fabricated placeholder.
                    childId: childId ?? 'aaaaaaaa-0000-4000-8000-000000000001',
                    availabilityHttpClient: availabilityHttpClient)))),
            ]);
          })),
        const SizedBox(height: 16),
      ]))),
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
        Text(label, style: Theme.of(context).textTheme.titleSmall
          ?.copyWith(fontWeight: FontWeight.w600)),
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
      Text(label.toUpperCase(), style: Theme.of(context).textTheme.labelSmall
        ?.copyWith(letterSpacing: 0.7, color: Theme.of(context).colorScheme.onSurfaceVariant)),
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
