// OLIVE BRANCH — care guide screens, guardian shell only (mockups G1-G5). UNVERIFIED — not yet checked by CI's Flutter run.
//
// G1 library (the emergency button is always first), G2 one guide (emergency signs first, then age tabs), G3 who to call
// (the same guide with its phone numbers up top), G4 a new carer's first screen (links), G5 helper-page selection.
//
// CHILD-FIRST RULE: nothing in this file is reachable from a child screen. The only importer outside the care_guide_*
// files is guardian_more.dart (the guardian hub). test/care_guide_structure_test.dart holds that line. Every screen also
// refuses a non-guardian role and shows nothing from the content.
//
// GATE: every screen is built over a [CareGuideLibrary] that has already passed care_guide_gate.dart, so a guide that is
// not REVIEWED never gets here in a release build. In a debug preview the draft banner is permanent. The headings below
// are structural labels, not advice, and they only ever appear around a guide that is allowed to be shown.
//
// Phone numbers: this file contains no number. Every number on a screen is a [Helpline.number] from guide data.
import 'package:flutter/material.dart';

import 'care_guide_gate.dart';
import 'care_guide_loader.dart';
import 'care_guide_models.dart';
import 'care_guide_plan.dart';
import 'hub_widgets.dart';

const String _guardianRole = 'guardian';

/// Headings per block kind. Labels only.
const Map<String, String> kBlockHeadings = <String, String>{
  'emergency': 'Emergency signs',
  'urgent': 'Urgent',
  'poison': 'Poison',
  'nurseLine': 'Doctor or nurse line',
  'sameDay': 'Same-day doctor',
  'afterEpisode': 'After the episode',
  'firstSteps': 'First steps',
  'doNow': 'What to do',
  'dispatcherScript': 'What to tell the dispatcher',
  'haveReady': 'Have ready',
  'recognition': 'Quick recognition',
  'coolDown': 'If it is hard to bring down',
  'howToMeasure': 'How to measure',
  'doNot': 'What not to do',
  'watchFor': 'What to watch for',
  'note': 'Note',
  'consent': 'Consent',
  'topHazards': 'Top hazards',
  'room': 'By room',
  'arrivalChecklist': 'Arrival checklist',
  'prevention': 'Prevention',
};

/// One row of the library, in display order. The emergency entry is ALWAYS first, even when no guide is available.
class LibraryEntry {
  const LibraryEntry.emergency() : guide = null, isEmergency = true;
  const LibraryEntry.guide(CareGuide this.guide) : isEmergency = false;
  final CareGuide? guide;
  final bool isEmergency;
}

List<LibraryEntry> libraryEntries(CareGuideLibrary lib) => <LibraryEntry>[
      const LibraryEntry.emergency(),
      for (final CareGuide g in lib.guides) LibraryEntry.guide(g),
    ];

class _GuardiansOnly extends StatelessWidget {
  const _GuardiansOnly();
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Care guides')),
        body: const Center(
            child: Padding(padding: EdgeInsets.all(24), child: Text('This area is for guardians.', key: Key('careGuidesGuardiansOnly')))),
      );
}

/// The permanent banner on a previewed draft. Shape, icon and words, never colour alone.
class DraftBanner extends StatelessWidget {
  const DraftBanner({super.key});
  @override
  Widget build(BuildContext context) {
    final ColorScheme c = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      label: kDraftBannerText,
      child: ExcludeSemantics(
        child: Container(
          key: const Key('careDraftBanner'),
          width: double.infinity,
          color: c.errorContainer,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(children: <Widget>[
            Icon(Icons.edit_note, color: c.onErrorContainer),
            const SizedBox(width: 8),
            Text(kDraftBannerText, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: c.onErrorContainer, fontWeight: FontWeight.w800)),
          ]),
        ),
      ),
    );
  }
}

String _reviewLine(CareGuide g, {required bool draft}) {
  if (draft || !g.isReviewed) return 'Last reviewed: not reviewed';
  return 'Last reviewed: ${g.review.reviewedOn}';
}

// ------------------------------------------------------------------ G1 library

class CareGuideLibraryScreen extends StatefulWidget {
  const CareGuideLibraryScreen({super.key, required this.principalRole, required this.loader, this.plan = const NoChildPlan()});
  final String principalRole;
  final CareGuideLoader loader;
  final ChildPlanSource plan;
  @override
  State<CareGuideLibraryScreen> createState() => _LibraryState();
}

class _LibraryState extends State<CareGuideLibraryScreen> {
  CareGuideLibrary? _lib;
  @override
  void initState() {
    super.initState();
    if (widget.principalRole == _guardianRole) {
      widget.loader.load().then((CareGuideLibrary l) {
        if (mounted) setState(() => _lib = l);
      });
    }
  }

  void _push(Widget w) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => w));

  @override
  Widget build(BuildContext context) {
    if (widget.principalRole != _guardianRole) return const _GuardiansOnly();
    final CareGuideLibrary? lib = _lib;
    if (lib == null) return Scaffold(appBar: AppBar(title: const Text('Care guides')), body: const SizedBox.shrink());
    final bool anyDraft = lib.draftIds.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Care guides'),
        bottom: anyDraft ? const PreferredSize(preferredSize: Size.fromHeight(44), child: DraftBanner()) : null,
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: <Widget>[
        for (final LibraryEntry e in libraryEntries(lib))
          if (e.isEmergency)
            _EmergencyButton(onTap: () => _push(_emergencyTarget(lib)))
          else
            _GuideTile(guide: e.guide!, draft: lib.isDraft(e.guide!), onTap: () => _push(CareGuideScreen(
                  principalRole: widget.principalRole, guide: e.guide!, draft: lib.isDraft(e.guide!), plan: widget.plan))),
        if (lib.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 24),
            child: Text('The guides are not available yet.', key: Key('careGuidesNone')),
          ),
        const SizedBox(height: 12),
        if (!lib.isEmpty) ...<Widget>[
          HubTile(key: const Key('careNewCarer'), icon: Icons.waving_hand_outlined, title: 'For a new carer',
              subtitle: 'The first screen to hand over',
              onTap: () => _push(NewCarerStartScreen(principalRole: widget.principalRole, library: lib, plan: widget.plan))),
          HubTile(key: const Key('careHelperPage'), icon: Icons.checklist_outlined, title: 'Pick the helper page',
              subtitle: 'Choose which guides a helper sees first',
              onTap: () => _push(HelperPageSelectionScreen(principalRole: widget.principalRole, library: lib))),
        ],
      ]),
    );
  }

  Widget _emergencyTarget(CareGuideLibrary lib) {
    final CareGuide? w = lib.whoToCall;
    return w == null
        ? _EmergencyUnavailableScreen(principalRole: widget.principalRole)
        : WhoToCallScreen(principalRole: widget.principalRole, guide: w, draft: lib.isDraft(w), plan: widget.plan);
  }
}

class _EmergencyButton extends StatelessWidget {
  const _EmergencyButton({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final ColorScheme c = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Semantics(
        button: true,
        label: 'Emergency: who to call',
        child: ExcludeSemantics(
          child: FilledButton.icon(
            key: const Key('careEmergencyButton'),
            style: FilledButton.styleFrom(
                backgroundColor: c.error, foregroundColor: c.onError, minimumSize: const Size.fromHeight(64),
                textStyle: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            onPressed: onTap,
            icon: const Icon(Icons.emergency_outlined),
            label: const Text('Emergency: who to call'),
          ),
        ),
      ),
    );
  }
}

class _EmergencyUnavailableScreen extends StatelessWidget {
  const _EmergencyUnavailableScreen({required this.principalRole});
  final String principalRole;
  @override
  Widget build(BuildContext context) => principalRole != _guardianRole
      ? const _GuardiansOnly()
      : Scaffold(
          appBar: AppBar(title: const Text('Who to call')),
          body: const Center(
              child: Padding(padding: EdgeInsets.all(24), child: Text('This guide is not available yet.', key: Key('careEmergencyUnavailable')))),
        );
}

class _GuideTile extends StatelessWidget {
  const _GuideTile({required this.guide, required this.draft, required this.onTap});
  final CareGuide guide;
  final bool draft;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => HubTile(
      key: Key('careGuide_${guide.id}'), icon: Icons.menu_book_outlined, title: guide.title,
      subtitle: draft ? kDraftBannerText : _reviewLine(guide, draft: false), onTap: onTap);
}

// ------------------------------------------------------------------ G2 one guide

class CareGuideScreen extends StatefulWidget {
  const CareGuideScreen({
    super.key, required this.principalRole, required this.guide, this.draft = false,
    this.plan = const NoChildPlan(), this.helplinesFirst = false,
  });
  final String principalRole;
  final CareGuide guide;
  final bool draft;
  final ChildPlanSource plan;

  /// G3: show the phone numbers right after the emergency signs.
  final bool helplinesFirst;
  @override
  State<CareGuideScreen> createState() => _GuideState();
}

class _GuideState extends State<CareGuideScreen> {
  int _band = 0;

  @override
  Widget build(BuildContext context) {
    if (widget.principalRole != _guardianRole) return const _GuardiansOnly();
    final CareGuide g = widget.guide;
    final List<CareBlock> ordered = g.orderedBlocks;
    final List<CareBlock> top = ordered.where((CareBlock b) => const <String>['emergency', 'urgent'].contains(b.kind)).toList();
    final List<CareBlock> rest = ordered.where((CareBlock b) => !top.contains(b)).toList();
    final TextTheme t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(g.title), bottom: widget.draft ? const PreferredSize(preferredSize: Size.fromHeight(44), child: DraftBanner()) : null),
      body: ListView(key: const Key('careGuideBody'), padding: const EdgeInsets.all(16), children: <Widget>[
        if (g.disclaimer != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(g.disclaimer!, style: t.bodySmall)),
        if (g.emergencyFirstLine != null) _FirstLine(g, g.emergencyFirstLine!),
        for (final CareBlock b in top) _BlockView(guide: g, block: b),
        if (widget.helplinesFirst) _HelplinesView(guide: g, draft: widget.draft),
        ForChildStrip(guideId: g.id, plan: widget.plan, reviewed: g.isReviewed && !widget.draft && !g.isEmergencyTier),
        if (g.ageBands.isNotEmpty) _AgeTabs(bands: g.ageBands, guide: g, index: _band, onSelect: (int i) => setState(() => _band = i)),
        for (final CareBlock b in rest) _BlockView(guide: g, block: b),
        if (!widget.helplinesFirst && g.helplines.isNotEmpty) _HelplinesView(guide: g, draft: widget.draft),
        for (final GuideNote n in g.notes) Padding(padding: const EdgeInsets.only(top: 12), child: Text(n.text, style: t.bodySmall)),
        const SizedBox(height: 24),
      ]),
      bottomNavigationBar: _ReviewFooter(guide: g, draft: widget.draft),
    );
  }
}

class WhoToCallScreen extends StatelessWidget {
  const WhoToCallScreen({super.key, required this.principalRole, required this.guide, this.draft = false, this.plan = const NoChildPlan()});
  final String principalRole;
  final CareGuide guide;
  final bool draft;
  final ChildPlanSource plan;
  @override
  Widget build(BuildContext context) =>
      CareGuideScreen(principalRole: principalRole, guide: guide, draft: draft, plan: plan, helplinesFirst: true);
}

class _FirstLine extends StatelessWidget {
  const _FirstLine(this.guide, this.line);
  final CareGuide guide;
  final CareItem line;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(line.text, key: const Key('careFirstLine'), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
      );
}

String _sourceNames(CareGuide g, List<int> ids) {
  final List<String> orgs = <String>[];
  for (final int id in ids) {
    final GuideSource? s = g.sourceById(id);
    if (s != null && !orgs.contains(s.org)) orgs.add(s.org);
  }
  return orgs.join(', ');
}

class _ItemView extends StatelessWidget {
  const _ItemView({required this.guide, required this.item, this.numbered = false});
  final CareGuide guide;
  final CareItem item;
  final bool numbered;
  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final String from = _sourceNames(guide, item.sources);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        SizedBox(width: 28, child: Text(numbered && item.n != null ? '${item.n}.' : '•', style: t.bodyLarge)),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            if (item.group != null) Text(item.group!, style: t.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
            Text(item.text, style: t.bodyLarge),
            for (final String s in item.signs) Padding(padding: const EdgeInsets.only(left: 8, top: 2), child: Text('• $s', style: t.bodyMedium)),
            if (item.detail != null) Text(item.detail!, style: t.bodyMedium),
            if (item.ages != null) Text('Ages: ${item.ages}', style: t.labelSmall),
            if (from.isNotEmpty) Text('From: $from', style: t.labelSmall),
          ]),
        ),
      ]),
    );
  }
}

class _BlockView extends StatelessWidget {
  const _BlockView({required this.guide, required this.block});
  final CareGuide guide;
  final CareBlock block;
  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final String heading = block.title ?? kBlockHeadings[block.kind] ?? '';
    final bool numbered = block.kind == 'doNow' || block.kind == 'firstSteps';
    return Padding(
      key: Key('careBlock_${block.kind}'),
      padding: const EdgeInsets.only(top: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Semantics(header: true, child: Text(heading, style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
        for (final CareItem i in block.items) _ItemView(guide: guide, item: i, numbered: numbered),
      ]),
    );
  }
}

class _AgeTabs extends StatelessWidget {
  const _AgeTabs({required this.bands, required this.guide, required this.index, required this.onSelect});
  final List<AgeBand> bands;
  final CareGuide guide;
  final int index;
  final ValueChanged<int> onSelect;
  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    final AgeBand b = bands[index.clamp(0, bands.length - 1)];
    return Padding(
      key: const Key('careAgeTabs'),
      padding: const EdgeInsets.only(top: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Semantics(header: true, child: Text('By age', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
          for (int i = 0; i < bands.length; i++)
            Semantics(
              selected: i == index,
              inMutuallyExclusiveGroup: true,
              child: ChoiceChip(
                key: Key('careAge_${bands[i].key}'), label: Text(bands[i].display), selected: i == index, onSelected: (_) => onSelect(i)),
            ),
        ]),
        const SizedBox(height: 8),
        if (b.text != null) Text(b.text!, style: t.bodyLarge),
        for (final CareItem i in b.items) _ItemView(guide: guide, item: i),
        if (b.note != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(b.note!, style: t.bodySmall)),
      ]),
    );
  }
}

class _HelplinesView extends StatelessWidget {
  const _HelplinesView({required this.guide, required this.draft});
  final CareGuide guide;
  final bool draft;
  @override
  Widget build(BuildContext context) {
    // Only regions the review covers (a previewed draft: its own region). Nothing else is shown.
    final List<Helpline> shown = helplinesToShow(guide, draft: draft);
    if (shown.isEmpty) return const SizedBox.shrink();
    final TextTheme t = Theme.of(context).textTheme;
    // The guide's own region first, then the others the review covers, each group in the guide's order.
    final List<Helpline> mine = shown.where((Helpline h) => h.region == guide.region).toList();
    final List<Helpline> other = shown.where((Helpline h) => h.region != guide.region).toList();
    Widget row(Helpline h) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text(h.name, style: t.bodyMedium),
            SelectableText(h.number, key: Key('careNumber_${h.region}_${h.number}'), style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
            Text('From: ${_sourceNames(guide, h.sources)}', style: t.labelSmall),
          ]),
        );
    return Padding(
      key: const Key('careHelplines'),
      padding: const EdgeInsets.only(top: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Semantics(header: true, child: Text('Phone numbers', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
        for (final Helpline h in mine) row(h),
        if (other.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          Text('Other places', style: t.labelLarge),
          for (final Helpline h in other) row(h),
        ],
      ]),
    );
  }
}

/// Always on screen: last reviewed, when the sources were retrieved, and the sources themselves.
class _ReviewFooter extends StatelessWidget {
  const _ReviewFooter({required this.guide, required this.draft});
  final CareGuide guide;
  final bool draft;
  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    return Material(
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: <Widget>[
            Expanded(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Text(_reviewLine(guide, draft: draft), key: const Key('careLastReviewed'), style: t.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
                Text('Sources retrieved: ${guide.latestRetrieved ?? guide.lastResearched}', key: const Key('careRetrieved'), style: t.labelSmall),
              ]),
            ),
            TextButton(
              key: const Key('careSourcesButton'),
              onPressed: () => showModalBottomSheet<void>(
                  context: context, isScrollControlled: true, builder: (_) => _SourcesSheet(guide: guide)),
              child: Text('Sources (${guide.sources.length})'),
            ),
          ]),
        ),
      ),
    );
  }
}

class _SourcesSheet extends StatelessWidget {
  const _SourcesSheet({required this.guide});
  final CareGuide guide;
  @override
  Widget build(BuildContext context) {
    final TextTheme t = Theme.of(context).textTheme;
    return SafeArea(
      child: ListView(padding: const EdgeInsets.all(16), children: <Widget>[
        Text('Sources', style: t.titleLarge),
        for (final GuideSource s in guide.sources)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Text('${s.org}: ${s.title}', style: t.bodyMedium),
              SelectableText(s.url, style: t.labelSmall),
              Text('Retrieved ${s.retrieved}', style: t.labelSmall),
            ]),
          ),
      ]),
    );
  }
}

// ------------------------------------------------------------------ the "For <child>" strip

class ForChildStrip extends StatelessWidget {
  const ForChildStrip({super.key, required this.guideId, required this.plan, required this.reviewed});
  final String guideId;
  final ChildPlanSource plan;

  /// The same flag that gates the guide. The rule line is advice, so it is withheld unless the guide is REVIEWED.
  final bool reviewed;
  @override
  Widget build(BuildContext context) => FutureBuilder<ChildPlanForGuide?>(
        future: plan.forGuide(guideId),
        builder: (BuildContext context, AsyncSnapshot<ChildPlanForGuide?> snap) {
          final ChildPlanForGuide? p = snap.data;
          if (p == null || p.notes.isEmpty) return const SizedBox.shrink();
          final TextTheme t = Theme.of(context).textTheme;
          return Padding(
            key: const Key('careForChild'),
            padding: const EdgeInsets.only(top: 16),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  Semantics(header: true, child: Text('For ${p.childName}', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
                  for (final ChildPlanNote n in p.notes) Padding(padding: const EdgeInsets.only(top: 4), child: Text('${n.label}: ${n.text}', style: t.bodyLarge)),
                  if (reviewed) Padding(padding: const EdgeInsets.only(top: 8), child: Text(childPlanRuleLine(p), key: const Key('careRuleLine'), style: t.bodyMedium)),
                ]),
              ),
            ),
          );
        },
      );
}

// ------------------------------------------------------------------ G4 a new carer's first screen

class NewCarerStartScreen extends StatelessWidget {
  const NewCarerStartScreen({super.key, required this.principalRole, required this.library, this.selectedIds, this.plan = const NoChildPlan()});
  final String principalRole;
  final CareGuideLibrary library;

  /// The guardian's helper-page choice (G5). Null = every available guide.
  final Set<String>? selectedIds;
  final ChildPlanSource plan;
  @override
  Widget build(BuildContext context) {
    if (principalRole != _guardianRole) return const _GuardiansOnly();
    final List<CareGuide> shown = <CareGuide>[
      for (final CareGuide g in library.guides)
        if (selectedIds == null || selectedIds!.contains(g.id)) g,
    ];
    void push(Widget w) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => w));
    final CareGuide? w = library.whoToCall;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Start here'),
        bottom: library.draftIds.isNotEmpty ? const PreferredSize(preferredSize: Size.fromHeight(44), child: DraftBanner()) : null,
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: <Widget>[
        _EmergencyButton(
            onTap: () => push(w == null
                ? _EmergencyUnavailableScreen(principalRole: principalRole)
                : WhoToCallScreen(principalRole: principalRole, guide: w, draft: library.isDraft(w), plan: plan))),
        for (final CareGuide g in shown)
          if (g.id != 'who-to-call')
            _GuideTile(guide: g, draft: library.isDraft(g), onTap: () => push(CareGuideScreen(
                principalRole: principalRole, guide: g, draft: library.isDraft(g), plan: plan))),
      ]),
    );
  }
}

// ------------------------------------------------------------------ G5 helper-page selection

/// Which guides the helper page leads with. The choice is returned through [onChanged]; saving it, and sharing the page
/// with a helper, are not built yet (docs: MASTERFILE "not built").
class HelperPageSelectionScreen extends StatefulWidget {
  const HelperPageSelectionScreen({super.key, required this.principalRole, required this.library, this.initial, this.onChanged});
  final String principalRole;
  final CareGuideLibrary library;
  final Set<String>? initial;
  final ValueChanged<Set<String>>? onChanged;
  @override
  State<HelperPageSelectionScreen> createState() => _HelperSelState();
}

class _HelperSelState extends State<HelperPageSelectionScreen> {
  late Set<String> _sel = widget.initial ?? <String>{for (final CareGuide g in widget.library.guides) g.id};

  @override
  Widget build(BuildContext context) {
    if (widget.principalRole != _guardianRole) return const _GuardiansOnly();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Helper page'),
        bottom: widget.library.draftIds.isNotEmpty ? const PreferredSize(preferredSize: Size.fromHeight(44), child: DraftBanner()) : null,
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: <Widget>[
        for (final CareGuide g in widget.library.guides)
          CheckboxListTile(
            key: Key('careHelperPick_${g.id}'),
            title: Text(g.title),
            value: _sel.contains(g.id),
            onChanged: (bool? on) {
              setState(() => _sel = on == true ? <String>{..._sel, g.id} : (<String>{..._sel}..remove(g.id)));
              widget.onChanged?.call(_sel);
            },
          ),
      ]),
    );
  }
}

// ------------------------------------------------------------------ the entry in the guardian hub

/// A hub tile that appears only when at least one guide has passed the gate. In a default (release) build that is
/// never, so it renders nothing and the hub is exactly what it was.
class CareGuidesHubTile extends StatefulWidget {
  const CareGuidesHubTile({super.key, this.loader, this.plan = const NoChildPlan()});
  final CareGuideLoader? loader;
  final ChildPlanSource plan;
  @override
  State<CareGuidesHubTile> createState() => _HubTileState();
}

class _HubTileState extends State<CareGuidesHubTile> {
  late final CareGuideLoader _loader = widget.loader ?? CareGuideLoader(policy: CareGuidePolicy.current());
  bool _any = false;
  @override
  void initState() {
    super.initState();
    _loader.load().then((CareGuideLibrary l) {
      if (mounted && !l.isEmpty) setState(() => _any = true);
    });
  }

  @override
  Widget build(BuildContext context) => !_any
      ? const SizedBox.shrink()
      : HubTile(
          key: const Key('moreCareGuides'), icon: Icons.medical_information_outlined, title: 'Care guides',
          subtitle: 'Who to call, and what to do first',
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => CareGuideLibraryScreen(principalRole: _guardianRole, loader: _loader, plan: widget.plan))));
}
