// OLIVE BRANCH — the guided first run's extension point. MASTERFILE §8.5.13.
//
// A feature built later adds to the guided first run by adding ONE [GuidedEntry] to [kRegisteredGuidedEntries]:
// a tour stop at a named slot, a "What's new" mini-tour entry, or an icon label on her "And there is more" card. The
// engine (guided_engine.dart) and the screens are never edited. The three-step procedure is at the end of
// docs/planning/ONBOARDING-SCRIPT.md.
//
// [resolveGuidedEntries] is pure: the same inputs always give the same ordered list. It is where every rule lives:
//   * order: by slot (the order of [kGuidedSlots]), then the built-in entries before registered ones, then the order
//     of registration. A registered entry therefore appears exactly where its slot says, with no gap.
//   * a feature the build does not have, or that is switched off, skips its entry silently (no empty card, no gap, and
//     the strip renumbers: "Step 3 of 8", never "3 of 9" with a missing 4).
//   * an entry from a script version newer than this build knows ([kGuidedScriptVersion]) is ignored.
//   * [seenVersion] set (an install that already finished first run) keeps only the entries that are new since that
//     version and marked `whatsNew`: the delta, shown once as a mini-tour.
import 'guided_script.dart';

/// Registered by later features. Empty in script version 1: nothing has registered yet.
const List<GuidedEntry> kRegisteredGuidedEntries = <GuidedEntry>[];

/// Which features this build has switched on. A feature names itself here when it is built and reachable.
/// Entries with `needsFeature: null` need nothing.
const Set<String> kGuidedFeaturesOn = <String>{};

List<GuidedEntry> resolveGuidedEntries({
  required GuidedHalf half,
  int? seenVersion,
  Set<String> features = kGuidedFeaturesOn,
  List<GuidedEntry>? base,
  List<GuidedEntry> registered = kRegisteredGuidedEntries,
  int scriptVersion = kGuidedScriptVersion,
}) {
  final List<GuidedEntry> all = <GuidedEntry>[...(base ?? kBaseGuidedEntries), ...registered];
  bool keep(GuidedEntry e) =>
      e.half == half &&
      e.since <= scriptVersion &&
      (e.needsFeature == null || features.contains(e.needsFeature)) &&
      kGuidedSlots.contains(e.slot);
  final List<GuidedEntry> live = all.where(keep).toList();
  // A stable sort: Dart's List.sort is not guaranteed stable, so the original index breaks every tie.
  final Map<GuidedEntry, int> at = <GuidedEntry, int>{for (int i = 0; i < live.length; i++) live[i]: i};
  live.sort((GuidedEntry a, GuidedEntry b) {
    final int s = kGuidedSlots.indexOf(a.slot).compareTo(kGuidedSlots.indexOf(b.slot));
    return s != 0 ? s : at[a]!.compareTo(at[b]!);
  });

  // Icon labels registered for her "And there is more" card become that card's labels; no label, no card.
  final List<GuidedLabel> extra = <GuidedLabel>[
    for (final GuidedEntry e in live)
      if (e.kind == GuidedKind.childLabel && (seenVersion == null || (e.since > seenVersion && e.whatsNew))) ...e.labels,
  ];
  final List<GuidedEntry> steps = <GuidedEntry>[];
  for (final GuidedEntry e in live) {
    if (e.kind == GuidedKind.childLabel) continue;
    // The "And there is more" card is the container for the labels above: it shows exactly when there are any (in a
    // mini-tour, only the new ones), whatever its own version.
    if (e.id == 'c.extra') {
      if (extra.isNotEmpty) steps.add(e.withLabels(extra));
      continue;
    }
    if (seenVersion != null && !(e.since > seenVersion && e.whatsNew)) continue;
    steps.add(e);
  }
  return steps;
}

/// "Step 3 of 9": the strip position of step [index] in [steps], counting each phase once.
({int step, int of}) guidedStrip(List<GuidedEntry> steps, int index) {
  final List<String> phases = <String>[];
  for (final GuidedEntry e in steps) {
    if (e.phase.isNotEmpty && !phases.contains(e.phase)) phases.add(e.phase);
  }
  final String p = steps[index].phase;
  return (step: p.isEmpty ? 0 : phases.indexOf(p) + 1, of: phases.length);
}
