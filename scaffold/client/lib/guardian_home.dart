// OLIVE BRANCH — guardian shell, home. No longer UNVERIFIED — verified by CI (a Flutter toolchain
// now runs for real in tools/verify.sh's automated pipeline — CHANGELOG
// v0.49.61). §8.2.
//
// Renders MARKUP screen 05. The dual clock is persistent and the CHILD's time is
// dominant; the parent never performs a timezone calculation (§8.2.3). All times
// arrive pre-rendered from /now and /ribbon so the client does no zone maths.
// Both are real routes as of v0.49.57 (server/routes.mjs) — this widget
// itself stays a pure StatelessWidget taking plain values either way, same
// as it always has; see guardian_home_live.dart (new this pass) for the
// wrapper that actually fetches them. This screen's own STILL-static
// callers (main.dart's offline demo, invariants_test.dart) are unaffected —
// nothing here changed except `childStateSentence` becoming nullable (see
// its own field doc comment).
//
// Action grid below mirrors child_home.dart's tile pattern — parity of
// structure, not just of read-only status. Three tiles are real, genuinely
// functional screens (§9.5 message banking, §9.6.3 emergency card, P8
// handover notes); the rest are honest not-built-yet stubs, same posture
// child_home.dart already takes for its own unbuilt tiles.
//
// TILE HIERARCHY — intuitivism pass, sub-project 3b (docs/superpowers/
// specs/2026-09-12-intuitivism-guardianhome-tiering-design.md). The 11
// tiles above used to render as one flat, equal-weight grid (`_GTile`) —
// the same symptom sub-project 2 named for ChildHome's own pre-hierarchy
// grid. Now a real Hero/Featured/Standard hierarchy, sharing ChildHome's
// own TieredTile (tiered_tile.dart) instead of a second, drifting tile
// class: Hero (Message banking, full-width, outside the grid — same
// structural position as ChildHome's own Hero tile), Featured (Availability,
// Send-time guard, Meds & care, Emergency card — secondaryContainer fill,
// larger icon/type-scale), Standard (Handover notes, Exchange, Expenses,
// Morning briefing, Care note, More — primaryContainer, unchanged from
// before this pass). Every placement traces to the user's own stated
// answer about which tiles feel most urgent/frequent as a real guardian —
// see the spec for the full account. The ribbon above (Ivy's day bars, the
// Call Ivy button) is real, live data, not a tile, and is untouched by this
// pass. The existing crossAxisCount/effectiveColumnWidth/mainAxisExtent
// computation below is ALSO unchanged — only which tiles land in which
// grid, and each grid's fill color, changes.
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'availability_screen.dart';
import 'call_screen.dart';
import 'care_note.dart';
import 'cover_collapse.dart';
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
import 'tiered_tile.dart';

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
    required this.actorLocalTime, this.childStateSentence,
    required this.childBands, required this.actorBands, this.overlapLabel,
    this.baseUrl, this.guardianId, this.childId, this.availabilityHttpClient,
    this.dayPart, this.reachable});

  final String childName, childLocalTime, childZoneAbbr, actorLocalTime;
  /// Real as of the same /now route send_time_guard.dart's live path now
  /// reads — see that file's own header for why it takes these as plain
  /// constructor params (reusing this screen's ALREADY-fetched /now data)
  /// rather than doing its own second live fetch. Null in every demo/test
  /// call site, same honest-absence posture as [childStateSentence]/
  /// [overlapLabel] above; [reachable] genuinely tri-state (true/false/
  /// unknown), not defaulted to either bool.
  final String? dayPart;
  final bool? reachable;
  /// Nullable since v0.49.57 (was required) — no live route exists yet that
  /// derives a real one-sentence status ("Winding down for bed") the way
  /// /now and /ribbon derive every other field on this widget. Null renders
  /// as nothing, the same honest-absence posture ChildHome's own
  /// `sleepsUntilHandover`/`presence` fields already established for
  /// exactly this class of gap — see guardian_home_live.dart's own header
  /// for the fuller account. Every existing demo/test call site still
  /// passes a real literal string here; this change is purely additive.
  final String? childStateSentence;
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
    // LayoutBuilder sits ABOVE the scrollable, the same structural position
    // child_home.dart's own LayoutBuilder already establishes (that file's
    // own comment: "inside it, `constraints` are the Scaffold body's real
    // bounded size, not the scrollable's own unbounded scroll-axis extent")
    // — added here, new, specifically so CoverCollapse's own internal
    // posture detection below has a genuinely bounded height to read.
    // `postureFor()` is height-sensitive (foldCover/foldTabletop both key
    // off it); the grid's own pre-existing LayoutBuilder further down stays
    // exactly where it was, nested inside the scrollable, because
    // `columnsAt()` only ever reads width.
    body: SafeArea(child: LayoutBuilder(builder: (context, outerConstraints) {
      // Shared between `full` and the foldCover `collapsed` layout below —
      // the ribbon is unchanged either way (per the design spec's own Part
      // 1 principle for this screen), so it is built once and reused, not
      // duplicated.
      final Widget ribbonBlock = Column(children: [
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
            // The state sentence is HER frame, dominant — §8.2.1's own
            // worked example bakes it into the headline ("Maya · 4:12 PM
            // EDT — just got home from school"), not the subordinate
            // footer. Used to sit after the actor line at the identical
            // bodySmall/onSurfaceVariant weight (confirmed, at the time,
            // by invariants_test.dart's own "design-token audit finding
            // #1") — moved above it and given the same bodyMedium/w600
            // dominant-frame treatment exchange_screen.dart's own handoff
            // card uses, while the actor line and zone abbreviation stay
            // exactly as subordinate as they were.
            if (childStateSentence != null) ...[
              Text(childStateSentence!, style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
            ],
            // Actor time is subordinate, always.
            Text('you · $actorLocalTime', style: Theme.of(context).textTheme.bodySmall
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
      ]);

      // SingleChildScrollView + Column, NOT ListView: see child_home.dart's
      // own comment on the same fix — a sliver-backed list drops children
      // scrolled below the fold from the element tree, and this wiring
      // pass's grid expansion (six new guardian tiles) pushed real content
      // well past the default test viewport.
      final Widget full = SingleChildScrollView(child: Column(children: [
        ribbonBlock,
        const SizedBox(height: 20),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
          // LayoutBuilder-driven breakpoint, not a single fixed extent: at the
          // Fold5 cover-screen width (344px logical, ~151px per column here)
          // the longer two-word labels ('Send-time guard', 'Morning
          // briefing') wrap to three lines and a flat mainAxisExtent: 108
          // overflowed the tile by 4px -- caught by widget tests pinned to
          // that exact width, not by inspection. Wider layouts keep the
          // original, more compact extent.
          //
          // Both breakpoint values grew again in sub-project 3b (136/170,
          // was 128/165) for the SAME reason, one tier later: this grid's
          // own mainAxisExtent is shared unchanged across the Featured and
          // Standard grids below (only fill/icon/type-scale differ per
          // tier), and TieredTile's `featured` bump (36px icon, titleMedium)
          // needs a taller cell than the 28px/titleSmall styling 128/165
          // were tuned for. Confirmed by the same discipline as the
          // original fix -- real widget tests pinned to exact widths, not
          // inspection: 'Send-time guard' (the longest Featured label)
          // overflowed by as much as 24px at effectiveColumnWidth 165-169
          // -- a real, common phone-width band (e.g. 372-380px screens) the
          // OLD 165 threshold routed into the too-short 108 extent. 136
          // clears every Featured label with margin at every width below
          // the new 170 threshold; 108 above it was already proven safe
          // (Featured labels wrap to fewer lines once genuinely more width
          // exists) and is untouched.
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
            final mainAxisExtent = effectiveColumnWidth < 170.0 ? 136.0 : 108.0;

            // The same 11 destinations as before, now tagged by tier
            // (_kGuardianTiles, in this spec's own §Tier assignment order)
            // instead of one hand-written GridView.children literal — a
            // partition-from-one-list approach makes a tile silently
            // appearing in two tiers, or dropped entirely, structurally
            // unlikely, where three independent literals would not.
            final tiles = _kGuardianTiles(
              childName: childName, childLocalTime: childLocalTime,
              childZoneAbbr: childZoneAbbr, dayPart: dayPart, reachable: reachable,
              baseUrl: baseUrl, guardianId: guardianId, childId: childId,
              availabilityHttpClient: availabilityHttpClient,
            );
            final heroTile = tiles.firstWhere((t) => t.tier == _Tier.hero);
            final featuredTiles = tiles.where((t) => t.tier == _Tier.featured).toList();
            final standardTiles = tiles.where((t) => t.tier == _Tier.standard).toList();

            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // ============================================ Hero — Message
              // banking. A plain full-width band OUTSIDE the GridView below,
              // same structural position as child_home.dart's own Hero tile
              // relative to its Featured grid — no hero-cell/variable-span
              // grid mechanism exists in this codebase
              // (SliverGridDelegateWithFixedCrossAxisCount is the only
              // delegate ever used, uniform-cell by construction). A fixed
              // height derived from this screen's own existing mainAxisExtent
              // breakpoint (+20, so Hero reads taller than Featured/Standard
              // at every width) rather than child_home.dart's own continuous
              // text-scale heightScale — that mechanism is a narrower,
              // disclosed choice of that screen; this file has never scaled
              // tile height with text at all, and this pass doesn't start
              // now. See guardian_home_test.dart's own 344px-width coverage
              // for proof this clears the Fold5 cover-screen floor even at
              // the longest Hero label ("Message banking").
              TieredTile(key: const Key('guardianHomeHero'),
                icon: heroTile.icon, label: heroTile.label,
                featured: true, hero: true,
                height: mainAxisExtent + 20, onTap: heroTile.onTap),
              const SizedBox(height: 10),

              // ================================================== Featured
              // — larger icon/type-scale via TieredTile's own `featured`
              // flag, secondaryContainer fill. SAME cell height as Standard
              // below (this screen's mainAxisExtent is one shared
              // breakpoint, not per-tier like child_home.dart's own two
              // differently-sized grids) — hierarchy here reads through
              // color and icon/type-scale alone, not cell size.
              GridView(key: const Key('guardianHomeFeaturedGrid'), shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount, mainAxisSpacing: 10, crossAxisSpacing: 10,
                  mainAxisExtent: mainAxisExtent),
                children: [for (final t in featuredTiles)
                  TieredTile(icon: t.icon, label: t.label, featured: true, onTap: t.onTap)]),
              const SizedBox(height: 10),

              // ================================================== Standard
              // — unchanged size and fill (primaryContainer) from before
              // this pass.
              GridView(key: const Key('guardianHomeStandardGrid'), shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount, mainAxisSpacing: 10, crossAxisSpacing: 10,
                  mainAxisExtent: mainAxisExtent),
                children: [for (final t in standardTiles)
                  TieredTile(icon: t.icon, label: t.label, onTap: t.onTap)]),
            ]);
          })),
        const SizedBox(height: 16),
      ]));

      // ==================================================== foldCover only
      // Intuitivism pass, sub-project 3c, Part 1 — at the Fold5's 344px
      // cover screen, this screen shows the ribbon (unchanged) and the Hero
      // tile (Message banking) only. Featured/Standard collapse into a
      // single "More" tile — the exact same icon/label/push-a-full-screen
      // shape this screen's own pre-existing "More" _GTile above already
      // uses, except this "More" opens `full` itself (this screen's own
      // complete, otherwise-unchanged layout) rather than GuardianMoreScreen
      // — the literal "full list" collapsed away from, not a second hub.
      // 128.0, not 108.0: the same mainAxisExtent the grid above already
      // computes for this exact narrow width (see that LayoutBuilder's own
      // comment on the 4px overflow this value fixes).
      final Widget collapsed = SingleChildScrollView(child: Column(children: [
        ribbonBlock,
        const SizedBox(height: 20),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(children: [
            SizedBox(width: double.infinity, height: 128, child: _GTile(
              icon: Icons.schedule_send, label: 'Message banking',
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => const MessageBankingScreen())))),
            const SizedBox(height: 10),
            SizedBox(width: double.infinity, height: 128, child: _GTile(
              icon: Icons.more_horiz, label: 'More',
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => Scaffold(
                  appBar: AppBar(title: const Text('More')),
                  body: SafeArea(child: full),
                ))))),
          ])),
        const SizedBox(height: 16),
      ]));

      return CoverCollapse(full: full, collapsed: collapsed);
    })),
  );
}

/// Sub-project 3b's own tier tag (docs/superpowers/specs/2026-09-12-
/// intuitivism-guardianhome-tiering-design.md) — the same three tiers
/// tiered_tile.dart's own TieredTile already renders, now driving which
/// grid (or, for Hero, which full-width band) a _TileSpec below lands in.
/// A fixed, designed hierarchy from the spec's own tier table — never
/// computed from usage (P2 is not triggered by construction).
enum _Tier { hero, featured, standard }

/// One row of the declarative tile list below: icon, label, destination,
/// and its designed tier. Kept separate from TieredTile itself — TieredTile
/// renders one tile; a _TileSpec describes one, everything build() needs to
/// place it in the right band/grid with the right fill.
class _TileSpec {
  const _TileSpec(
      {required this.icon, required this.label, required this.tier, required this.onTap});
  final IconData icon;
  final String label;
  final _Tier tier;
  final void Function(BuildContext context) onTap;
}

/// The same 11 real destinations guardian_home.dart has always had, now one
/// list instead of a hand-tiered GridView.children literal — re-tiering
/// later (if real guardian usage turns out to differ from this spec's own
/// answer) is a one-line `tier:` change here instead of moving a _TileSpec
/// between three independent lists. In this spec's own §Tier assignment
/// order (Hero, then Featured, then Standard).
///
/// Not a top-level `const` despite the `_k` name: every onTap here closes
/// over this screen's own live-session fields (baseUrl/guardianId/childId/
/// availabilityHttpClient) and the child's own already-fetched clock state
/// (childLocalTime/childZoneAbbr/dayPart/reachable) — none of which exist
/// at compile time — plus the real BuildContext each tap eventually runs
/// against, which no top-level constant can close over either. A function
/// taking exactly those as parameters, called once per build(), is the
/// closest a single real declarative list can get here; the same reason
/// none of this screen's (or child_home.dart's) per-tile onTap closures
/// were ever const either.
List<_TileSpec> _kGuardianTiles({
  required String childName,
  required String childLocalTime,
  required String childZoneAbbr,
  required String? dayPart,
  required bool? reachable,
  required String? baseUrl,
  required String? guardianId,
  required String? childId,
  required http.Client? availabilityHttpClient,
}) => <_TileSpec>[
  _TileSpec(icon: Icons.schedule_send, label: 'Message banking', tier: _Tier.hero,
    onTap: (context) => Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => const MessageBankingScreen()))),
  _TileSpec(icon: Icons.event_available, label: 'Availability', tier: _Tier.featured,
    onTap: (context) => _openAvailability(context,
      baseUrl: baseUrl, guardianId: guardianId, childId: childId,
      httpClient: availabilityHttpClient)),
  _TileSpec(icon: Icons.schedule, label: 'Send-time guard', tier: _Tier.featured,
    onTap: (context) => Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => SendTimeGuardScreen(childName: childName,
        childLocalTime: childLocalTime, zoneAbbr: childZoneAbbr,
        dayPart: dayPart, reachable: reachable)))),
  _TileSpec(icon: Icons.medical_services_outlined, label: 'Meds & care', tier: _Tier.featured,
    onTap: (context) => Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => MedsCareScreen(childName: childName)))),
  _TileSpec(icon: Icons.medical_information, label: 'Emergency card', tier: _Tier.featured,
    onTap: (context) => Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => const EmergencyCardScreen()))),
  _TileSpec(icon: Icons.receipt_long, label: 'Handover notes', tier: _Tier.standard,
    onTap: (context) => Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => const HandoverNotesScreen()))),
  _TileSpec(icon: Icons.swap_horiz, label: 'Exchange', tier: _Tier.standard,
    onTap: (context) => Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ExchangeScreen(childName: childName)))),
  _TileSpec(icon: Icons.account_balance_wallet, label: 'Expenses', tier: _Tier.standard,
    onTap: (context) => Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ExpensesScreen(childName: childName)))),
  _TileSpec(icon: Icons.wb_twilight, label: 'Morning briefing', tier: _Tier.standard,
    onTap: (context) => Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => const MorningBriefingScreen()))),
  _TileSpec(icon: Icons.favorite_border, label: 'Care note', tier: _Tier.standard,
    onTap: (context) => Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => CareNoteScreen(childName: childName,
        baseUrl: baseUrl, guardianId: guardianId, childId: childId,
        httpClient: availabilityHttpClient)))),
  _TileSpec(icon: Icons.more_horiz, label: 'More', tier: _Tier.standard,
    onTap: (context) => Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => GuardianMoreScreen(childName: childName,
        baseUrl: baseUrl, guardianId: guardianId,
        // GuardianMoreScreen.childId is non-nullable (it also keys the
        // family-agreement fetch, which needs SOME concrete child even
        // pre-live-session) — same seed-dev.mjs 'Ivy' fallback
        // main_live.dart's own defaultValue uses, not a fabricated
        // placeholder.
        childId: childId ?? 'aaaaaaaa-0000-4000-8000-000000000001',
        availabilityHttpClient: availabilityHttpClient)))),
];

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
