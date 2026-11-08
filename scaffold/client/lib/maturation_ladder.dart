// OLIVE BRANCH — the maturation ladder. No longer UNVERIFIED — verified by CI (a Flutter toolchain
// now runs for real in tools/verify.sh's automated pipeline — also manually
// built and run via `flutter analyze` / `flutter test` this session;
// CHANGELOG v0.49.61). MASTERFILE §21. Renders MARKUP screen 'ladder'.
//
// A close port of the ladder/grant-record half of
// packages/maturation/src/maturation.ts: LADDER, MaturationGrant,
// recordGrants(), holds(), canGuardianRevoke(), adjustRung(), and
// guardianAnnouncement(). The QUIETING table and letters-to-self — the other
// two halves of that same TS file — already have their own screens
// (quieting_note.dart, letters_screen.dart), so they are deliberately not
// re-ported here; two files independently claiming to be the source of the
// same data is worse than one file not covering it. Rung 15's inversion
// mechanics (packages/maturation/src/rungs.ts's publishWindow /
// resolveAvailability) and family.ts's sibling staggering / teach-me are
// likewise out of scope: MARKUP has exactly one 'ladder' entry, and it is
// the overview ledger of all seven rungs, not a management UI for any one
// of them.
//
// §21.1's two rules are the reason this file exists, and both are enforced
// structurally, not just in copy:
//   1. A rung is irreversible. canGuardianRevoke() always returns false and
//      there is no inverse of recordGrants() anywhere below — nothing in
//      this file ever removes an entry from a grants list. A reached rung's
//      tile carries no button, switch, or menu of any kind; the widget tree
//      simply never builds one, the same construction handover_notes.dart
//      uses for P8's append-only log.
//   2. The sequence is not reorderable, even though a jurisdiction may move
//      an age (§16.2 #9). adjustRung() only ever pushes one named rung's
//      age later, never earlier, never alone, and never touches order.
//      "Move this later" is therefore the only mutation this screen offers,
//      and it is offered only for a rung that has not happened yet.
//
// DURABLE NOW (it was "disclosed-not-durable"). [LadderRepository] keeps, in
// LocalStore area `ladder`: the grants recorded so far (append-only, exactly
// like the in-memory list), any rung moved later, which reveals she has already
// been shown, and which guardian announcements were already dismissed. That
// makes "told once, warmly, never again" (§21.9 C) true across a restart. No
// grant is ever removed from it: there is no inverse of the save.
import 'dart:async';
import 'package:flutter/material.dart';
import 'form_factors.dart' as ff;
import 'local_services.dart';
import 'local_store.dart';

// ============ ported from packages/maturation/src/maturation.ts (§21) ======
enum Grant {
  ownList, journalAbsolute, ownCalendar, publishAvailability,
  curateArchive, ownExport, everything,
}

class Rung {
  const Rung({
    required this.age,
    required this.grant,
    required this.ceremony,
    required this.guardianNote,
    required this.notifiesGuardian,
    this.requiresTier,
  });

  final int age;
  final Grant grant;
  final String ceremony;
  /// May contain the literal token '{name}', substituted at render time by
  /// [withName]. The TS source hardcodes a demo name ('Maya') here instead;
  /// templating it is this port's one intentional adaptation — the same
  /// kind of note lock_controller.dart's header gives for its own file.
  final String guardianNote;
  /// §21.9 answer B: only a rung that changes what a guardian can SEE
  /// notifies them. True for exactly two of the seven rungs below.
  final bool notifiesGuardian;
  final int? requiresTier;

  Rung withAge(int newAge) => Rung(
    age: newAge,
    grant: grant,
    ceremony: ceremony,
    guardianNote: guardianNote,
    notifiesGuardian: notifiesGuardian,
    requiresTier: requiresTier,
  );
}

const List<Rung> kLadder = <Rung>[
  Rung(age: 10, grant: Grant.ownList, notifiesGuardian: false,
    ceremony: 'Your list is yours now. Nobody else can change what you put on it.',
    guardianNote: '{name} now controls her own wants and needs list.'),
  Rung(age: 13, grant: Grant.journalAbsolute, notifiesGuardian: false, requiresTier: 2,
    ceremony: 'Your journal was always private. Now it is private forever.',
    guardianNote: 'Standard privacy tier change at 13. Nothing is required of you.'),
  Rung(age: 14, grant: Grant.ownCalendar, notifiesGuardian: false, requiresTier: 2,
    ceremony: 'You can add your own things to the calendar now.',
    guardianNote: '{name} can now add and edit her own school and activity events.'),
  Rung(age: 15, grant: Grant.publishAvailability, notifiesGuardian: true, requiresTier: 2,
    ceremony: 'You decide when you are free. They will see what you set.',
    guardianNote: '{name} now sets her own availability. The ribbon shows what she '
        'publishes rather than what was inferred.'),
  Rung(age: 16, grant: Grant.curateArchive, notifiesGuardian: false, requiresTier: 3,
    ceremony: 'You can decide what stays in your archive, and what gets put away.',
    guardianNote: ''),
  Rung(age: 17, grant: Grant.ownExport, notifiesGuardian: false, requiresTier: 3,
    ceremony: 'You can take a copy of everything, any time, without asking.',
    guardianNote: ''),
  Rung(age: 18, grant: Grant.everything, notifiesGuardian: true, requiresTier: 3,
    ceremony: 'This is yours now.',
    guardianNote: 'Guardianship has closed. The archive has transferred.'),
];

/// An append-only record. A rung reached is a fact about a date, not a
/// setting — there is [recordGrants] and there is no revoke(), and the
/// absence is the mechanism. Same construction as P7 and P8.
class MaturationGrant {
  const MaturationGrant({
    required this.childId,
    required this.grant,
    required this.age,
    required this.reachedAt,
    required this.rungAge,
  });

  final String childId;
  final Grant grant;
  final int age;
  final DateTime reachedAt;
  /// Which rung produced it, for the audit trail.
  final int rungAge;
}

class RecordGrantsResult {
  const RecordGrantsResult(this.grants, this.newly);
  final List<MaturationGrant> grants;
  final List<MaturationGrant> newly;
}

RecordGrantsResult recordGrants(
  List<MaturationGrant> existing, String childId, int age, DateTime at,
  {List<Rung> ladder = kLadder}
) {
  final Set<Grant> have = existing.map((MaturationGrant g) => g.grant).toSet();
  final List<MaturationGrant> newly = <MaturationGrant>[
    for (final Rung r in ladder)
      if (age >= r.age && !have.contains(r.grant))
        MaturationGrant(childId: childId, grant: r.grant, age: age, reachedAt: at, rungAge: r.age),
  ];
  return RecordGrantsResult(<MaturationGrant>[...existing, ...newly], newly);
}

bool holds(List<MaturationGrant> grants, Grant g) =>
    grants.any((MaturationGrant x) => x.grant == g);

/// There is no inverse. §21.1.
bool canGuardianRevoke() => false;

/// §21.9 answer A, settled: ages move later only, and only by both
/// guardians. Shifting a rung later is kind to an unusually vulnerable
/// child; shifting it earlier, or unilaterally, is the obvious lever for a
/// controlling parent — so this refuses both, and refuses a single-guardian
/// request even when the direction is legitimate.
enum AdjustError { earlierNotPermitted, needsBothGuardians, unknownRung }

class AdjustResult {
  const AdjustResult.ok(this.ladder) : reason = null;
  const AdjustResult.err(this.reason) : ladder = null;

  final List<Rung>? ladder;
  final AdjustError? reason;
  bool get ok => reason == null;
}

AdjustResult adjustRung(
  List<Rung> ladder, Grant grant, int newAge, List<String> consentingGuardians,
) {
  final int idx = ladder.indexWhere((Rung r) => r.grant == grant);
  if (idx == -1) return const AdjustResult.err(AdjustError.unknownRung);
  final Rung rung = ladder[idx];
  if (newAge < rung.age) return const AdjustResult.err(AdjustError.earlierNotPermitted);
  if (consentingGuardians.length < 2) {
    return const AdjustResult.err(AdjustError.needsBothGuardians);
  }
  return AdjustResult.ok(<Rung>[
    for (final Rung r in ladder) r.grant == grant ? r.withAge(newAge) : r,
  ]);
}

/// §21.9 answer C: the day after a notifying rung is reached, announce
/// **once, warmly**, then never again. A permanent banner would itself be a
/// daily reminder that she once needed the earlier state.
String? guardianAnnouncement(List<MaturationGrant> newly, {List<Rung> ladder = kLadder}) {
  final Iterable<MaturationGrant> notifying = newly.where((MaturationGrant g) =>
      ladder.firstWhere((Rung r) => r.grant == g.grant).notifiesGuardian);
  if (notifying.isEmpty) return null;
  final String note = ladder.firstWhere((Rung r) => r.grant == notifying.first.grant).guardianNote;
  return note.isEmpty ? null : note;
}

String withName(String template, String name) => template.replaceAll('{name}', name);
// =============================================================================

// ---- presentation only: friendly labels for the ported Grant enum ---------
String grantTitle(Grant g) => switch (g) {
  Grant.ownList => 'Her own list',
  Grant.journalAbsolute => 'Her journal locks for good',
  Grant.ownCalendar => 'Her own calendar',
  Grant.publishAvailability => 'She sets her own free time',
  Grant.curateArchive => 'She curates her archive',
  Grant.ownExport => 'She can take her own export',
  Grant.everything => 'Everything — guardianship closes',
};

IconData grantIcon(Grant g) => switch (g) {
  Grant.ownList => Icons.star_outline,
  Grant.journalAbsolute => Icons.lock_outline,
  Grant.ownCalendar => Icons.edit_calendar_outlined,
  Grant.publishAvailability => Icons.campaign_outlined,
  Grant.curateArchive => Icons.collections_bookmark_outlined,
  Grant.ownExport => Icons.download_outlined,
  Grant.everything => Icons.celebration_outlined,
};

/// App-wide, in-memory (same disclosed-not-durable posture as
/// `_announcement` below, and the same "real app-wide singleton, not a
/// per-screen-instance one" fix shared_gallery.dart's `demoAppGallery`
/// already established): which grants she has already been proactively
/// shown the reveal for, this app run. Without this at module level (not a
/// State field), navigating away and back to this screen would re-show the
/// exact same "just reached" reveal every time, since `recordGrants()` has
/// no real backend to remember against — see this file's own header on
/// [_MaturationLadderScreenState.initState].
final Set<Grant> childSeenRungReveals = <Grant>{};

/// Everything the ladder remembers on this device.
class LadderState {
  const LadderState({
    this.grants = const <MaturationGrant>[],
    this.agesLater = const <Grant, int>{},
    this.revealsSeen = const <Grant>{},
    this.announced = const <Grant>{},
  });
  final List<MaturationGrant> grants;

  /// Rungs a guardian moved later: grant -> the new age.
  final Map<Grant, int> agesLater;

  /// Grants whose child-facing reveal she has already seen.
  final Set<Grant> revealsSeen;

  /// Grants whose guardian announcement was already dismissed.
  final Set<Grant> announced;
}

class LadderRepository {
  LadderRepository(this._ns);
  factory LadderRepository.forChild([String? childId]) =>
      LadderRepository(LocalServices.current.area('ladder', ownerId: childId));
  final LocalNamespace _ns;
  static const String _key = 'state';

  static Grant? _grant(Object? name) {
    for (final Grant g in Grant.values) {
      if (g.name == name) return g;
    }
    return null;
  }

  /// Null means nothing was ever saved.
  Future<LadderState?> load() async {
    final Object? raw = await _ns.get(_key);
    if (raw is! Map) return null;
    final List<MaturationGrant> grants = <MaturationGrant>[];
    final Object? gs = raw['grants'];
    if (gs is List) {
      for (final Object? o in gs) {
        if (o is! Map) continue;
        final Grant? g = _grant(o['grant']);
        final Object? child = o['childId'], age = o['age'], at = o['reachedAt'], rung = o['rungAge'];
        final DateTime? when = at is String ? DateTime.tryParse(at) : null;
        if (g == null || child is! String || age is! int || when == null || rung is! int) continue;
        grants.add(MaturationGrant(childId: child, grant: g, age: age, reachedAt: when, rungAge: rung));
      }
    }
    final Map<Grant, int> later = <Grant, int>{};
    final Object? ls = raw['agesLater'];
    if (ls is Map) {
      for (final MapEntry<dynamic, dynamic> e in ls.entries) {
        final Grant? g = _grant(e.key);
        if (g != null && e.value is int) later[g] = e.value as int;
      }
    }
    Set<Grant> set(Object? v) => <Grant>{
          if (v is List)
            for (final Object? n in v)
              if (_grant(n) != null) _grant(n)!,
        };
    return LadderState(
        grants: grants, agesLater: later, revealsSeen: set(raw['revealsSeen']),
        announced: set(raw['announced']));
  }

  Future<void> save(LadderState s) => _ns.put(_key, <String, Object?>{
        'grants': <Object?>[
          for (final MaturationGrant g in s.grants)
            <String, Object?>{
              'grant': g.grant.name, 'childId': g.childId, 'age': g.age,
              'reachedAt': g.reachedAt.toIso8601String(), 'rungAge': g.rungAge,
            },
        ],
        'agesLater': <String, Object?>{for (final MapEntry<Grant, int> e in s.agesLater.entries) e.key.name: e.value},
        'revealsSeen': <Object?>[for (final Grant g in s.revealsSeen) g.name],
        'announced': <Object?>[for (final Grant g in s.announced) g.name],
      });
}

enum LadderViewer { child, guardian }

/// MARKUP screen 'ladder'. One widget, two tones: [LadderViewer.child] is
/// warm and forward-looking; [LadderViewer.guardian] is calmer and carries
/// the irreversibility explanation plus the (future-rung-only) "move later"
/// control. Wire ChildHome's and GuardianHome's own navigation to this same
/// class with different [viewer] values rather than building two screens
/// that could drift apart on the one fact that matters here.
class MaturationLadderScreen extends StatefulWidget {
  const MaturationLadderScreen({
    super.key,
    required this.childName,
    required this.childAgeYears,
    required this.viewer,
    this.now,
    this.repository,
    this.childId,
  });

  final String childName;
  final int childAgeYears;
  final LadderViewer viewer;

  /// Null means the app's on-device ladder for [childId].
  final LadderRepository? repository;

  /// Null means this device's child ([LocalServices.childId]) — never a
  /// hard-coded demo id in a live build.
  final String? childId;
  /// Testing hook only — production call sites should omit this and let it
  /// default to the real clock.
  final DateTime? now;

  @override
  State<MaturationLadderScreen> createState() => _MaturationLadderScreenState();
}

class _MaturationLadderScreenState extends State<MaturationLadderScreen> {
  late DateTime _now;
  late List<Rung> _ladder;
  late List<MaturationGrant> _grants;
  String? _announcement;
  final Set<Grant> _expanded = <Grant>{};
  // Grants whose guardian announcement was already dismissed (persisted).
  Set<Grant> _announced = <Grant>{};
  late final String _childId = widget.childId ?? LocalServices.current.childId;
  late final LadderRepository _repo =
      widget.repository ?? LadderRepository.forChild(widget.childId);

  @override
  void initState() {
    super.initState();
    _now = widget.now ?? DateTime.now();
    _ladder = List<Rung>.of(kLadder);
    // What she has reached is a pure function of her age and the ladder, so it
    // is shown at once; what was REMEMBERED (moved-later rungs, announcements
    // already dismissed, reveals already seen) is applied by _hydrate() as soon
    // as it is read from the device — and only then does anything proactive
    // (the reveal, the guardian banner) happen, so a restart can never repeat
    // something she was already told.
    _grants = recordGrants(
      const <MaturationGrant>[], _childId, widget.childAgeYears, _now, ladder: _ladder).grants;
    unawaited(_hydrate());
  }

  LadderState _state() => LadderState(
        grants: _grants,
        agesLater: <Grant, int>{
          for (final Rung r in _ladder)
            if (r.age != kLadder.firstWhere((Rung k) => k.grant == r.grant).age) r.grant: r.age,
        },
        revealsSeen: <Grant>{...childSeenRungReveals},
        announced: _announced,
      );

  void _persist() {
    unawaited(() async {
      try {
        await _repo.save(_state());
      } catch (_) {
        // Leaves this visit as-is; the next visit recomputes from age.
      }
    }());
  }

  Future<void> _hydrate() async {
    LadderState? stored;
    try {
      stored = await _repo.load();
    } catch (_) {
      stored = null; // quarantined by the store: start from age alone
    }
    if (!mounted) return;
    List<Rung> ladder = List<Rung>.of(kLadder);
    List<MaturationGrant> existing = const <MaturationGrant>[];
    if (stored != null) {
      // A rung only ever moves LATER (adjustRung's rule): an earlier stored
      // age is ignored rather than trusted.
      ladder = <Rung>[
        for (final Rung r in kLadder)
          if ((stored.agesLater[r.grant] ?? r.age) > r.age) r.withAge(stored.agesLater[r.grant]!) else r,
      ];
      existing = stored.grants;
      childSeenRungReveals.addAll(stored.revealsSeen);
      _announced = <Grant>{...stored.announced};
    }
    final RecordGrantsResult result =
        recordGrants(existing, _childId, widget.childAgeYears, _now, ladder: ladder);
    // The guardian's "told once": every notifying grant she has reached that
    // was not yet dismissed. (Stored grants are append-only, so a rung moved
    // later after being reached stays reached.)
    final List<MaturationGrant> unannounced = <MaturationGrant>[
      for (final MaturationGrant g in result.grants)
        if (!_announced.contains(g.grant)) g,
    ];
    final String? note = guardianAnnouncement(unannounced, ladder: ladder);

    // The child-facing counterpart to the guardian banner above — before
    // this pass, a rung she'd just reached was invisible to her unless she
    // navigated here herself and tapped the right tile open (three real
    // taps deep: More → Growing-up ladder → the tile). Proactive now,
    // mirroring the guardian's own one-time-announcement contract, not a
    // second, drifting mechanism — filtered against the `seen` set (the
    // module-level app-run set, seeded from what the device remembers) so it
    // never resurfaces, in this run or after a restart.
    List<Rung> toReveal = const <Rung>[];
    if (widget.viewer == LadderViewer.child) {
      toReveal = <Rung>[
        for (final MaturationGrant g in result.grants)
          if (!childSeenRungReveals.contains(g.grant))
            ladder.firstWhere((Rung r) => r.grant == g.grant),
      ];
      for (final Rung r in toReveal) {
        childSeenRungReveals.add(r.grant);
      }
    }
    setState(() {
      _ladder = ladder;
      _grants = result.grants;
      if (widget.viewer == LadderViewer.guardian) {
        _announcement = note == null ? null : withName(note, widget.childName);
      }
    });
    _persist();
    if (toReveal.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => _RungRevealScreen(rung: toReveal.first, childName: widget.childName)));
      });
    }
  }

  Future<void> _openMoveLater(Rung rung) async {
    final int? newAge = await showDialog<int>(
      context: context,
      builder: (BuildContext context) => _MoveLaterDialog(rung: rung),
    );
    if (newAge == null || !mounted) return;
    setState(() {
      _ladder = <Rung>[for (final Rung r in _ladder) r.grant == rung.grant ? r.withAge(newAge) : r];
      // recordGrants() only ever adds — a rung's age moving later can never
      // un-grant something already recorded in _grants, which is exactly
      // the append-only guarantee §21.1 requires.
      _grants = recordGrants(_grants, _childId, widget.childAgeYears, _now, ladder: _ladder).grants;
    });
    _persist();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(
      'Moved to age $newAge. ${widget.childName} does not need to do anything.')));
  }

  Future<void> _showNoUndoInfo() => showDialog<void>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: const Text("Why can't a rung be undone?"),
      content: const Text(
        'It is built that way on purpose. canGuardianRevoke() always returns '
        'false, and there is no function anywhere in this app that reverses '
        'a grant once it is recorded. The only adjustment a guardian can '
        'ever make is moving a rung that has not happened yet later — never '
        'earlier, and never alone.'),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Got it')),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final bool isChild = widget.viewer == LadderViewer.child;
    final int reachedCount = _ladder.where((Rung r) => holds(_grants, r.grant)).length;
    return Scaffold(
      appBar: AppBar(title: Text(isChild
        ? 'Growing up, ${widget.childName}'
        : "${widget.childName}'s ladder")),
      body: SafeArea(child: LayoutBuilder(builder: (BuildContext context, BoxConstraints constraints) {
        final double textScale = MediaQuery.textScalerOf(context).scale(1);
        final bool narrow = ff.columnsAt(
            ff.Viewport(w: constraints.maxWidth, h: constraints.maxHeight), textScale) < 2;
        return ListView(
          padding: EdgeInsets.all(narrow ? 12 : 20),
          children: <Widget>[
            if (!isChild && _announcement != null)
              Padding(padding: const EdgeInsets.only(bottom: 16),
                child: _AnnouncementBanner(
                  text: _announcement!,
                  onDismiss: () {
                    // Dismissed = told once, never again, across restarts.
                    setState(() {
                      _announcement = null;
                      _announced = <Grant>{..._announced, for (final MaturationGrant g in _grants) g.grant};
                    });
                    _persist();
                  })),
            _PrincipleBanner(
              isChild: isChild,
              childName: widget.childName,
              reachedCount: reachedCount,
              totalCount: _ladder.length,
              onWhyNoUndo: isChild ? null : _showNoUndoInfo,
            ),
            const SizedBox(height: 16),
            for (int i = 0; i < _ladder.length; i++)
              _RungTile(
                rung: _ladder[i],
                childName: widget.childName,
                isChild: isChild,
                reached: holds(_grants, _ladder[i].grant),
                isLast: i == _ladder.length - 1,
                expanded: _expanded.contains(_ladder[i].grant),
                onToggleExpand: () => setState(() {
                  final Grant g = _ladder[i].grant;
                  if (!_expanded.add(g)) _expanded.remove(g);
                }),
                onMoveLater: isChild ? null : () => _openMoveLater(_ladder[i]),
              ),
          ],
        );
      })),
    );
  }
}

/// The proactive, full-screen counterpart to the per-rung tile's own
/// ceremony text (below, in _RungTile) — same words, shown once, without
/// requiring her to have already found and expanded the right tile
/// herself. §8.13 motion budget: one entrance fade, nothing loops, no
/// celebrate()-style repeat. No settings affordance (§8.1) — a single
/// dismiss action and nothing else.
class _RungRevealScreen extends StatelessWidget {
  const _RungRevealScreen({required this.rung, required this.childName});
  final Rung rung;
  final String childName;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(child: Center(child: Padding(
        padding: const EdgeInsets.all(24),
        child: AnimatedOpacity(
          opacity: 1, duration: const Duration(milliseconds: 260),
          child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            Icon(grantIcon(rung.grant), size: 56, color: scheme.primary),
            const SizedBox(height: 20),
            Text(grantTitle(rung.grant), textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Text(rung.ceremony, textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.4)),
            const SizedBox(height: 28),
            SizedBox(height: 52, width: 200, child: FilledButton(
              key: const Key('rungRevealDismiss'),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Got it!'))),
          ]),
        ),
      ))),
    );
  }
}

class _AnnouncementBanner extends StatelessWidget {
  const _AnnouncementBanner({required this.text, required this.onDismiss});
  final String text;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer, borderRadius: BorderRadius.circular(16)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: <Widget>[
        Icon(Icons.favorite_outline, color: scheme.onTertiaryContainer, size: 20),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          height: 1.35, color: scheme.onTertiaryContainer))),
        IconButton(
          onPressed: onDismiss,
          tooltip: 'Dismiss',
          icon: Icon(Icons.close, size: 18, color: scheme.onTertiaryContainer)),
      ]),
    );
  }
}

class _PrincipleBanner extends StatelessWidget {
  const _PrincipleBanner({
    required this.isChild,
    required this.childName,
    required this.reachedCount,
    required this.totalCount,
    required this.onWhyNoUndo,
  });

  final bool isChild;
  final String childName;
  final int reachedCount;
  final int totalCount;
  /// Null for the child viewer — this explanation is guardian copy about a
  /// guardian-facing constraint; she never needs to be told what a grown-up
  /// cannot undo to her.
  final Future<void> Function()? onWhyNoUndo;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[scheme.primaryContainer, scheme.secondaryContainer],
          begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Text(isChild ? 'This app grows up with you' : "$childName's ladder",
          style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Text(
          isChild
            ? "Every so often, something new becomes yours, $childName — and "
              "once it's yours, it stays yours."
            : 'Each rung below hands something to $childName, permanently. '
              'There is no setting anywhere that moves one backward.',
          style: textTheme.bodyMedium?.copyWith(height: 1.35)),
        if (!isChild) ...<Widget>[
          const SizedBox(height: 4),
          Text('$reachedCount of $totalCount reached so far.',
            style: textTheme.bodySmall?.copyWith(color: scheme.onSecondaryContainer)),
        ],
        if (onWhyNoUndo != null) ...<Widget>[
          const SizedBox(height: 8),
          Align(alignment: Alignment.centerLeft, child: TextButton.icon(
            onPressed: onWhyNoUndo,
            icon: const Icon(Icons.info_outline, size: 18),
            label: const Text('Why is there no undo?'))),
        ],
      ]),
    );
  }
}

enum _PillTone { neutral, positive, muted }

class _Pill extends StatelessWidget {
  const _Pill({required this.text, this.tone = _PillTone.neutral});
  final String text;
  final _PillTone tone;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Color bg = switch (tone) {
      _PillTone.positive => scheme.tertiaryContainer,
      _PillTone.muted => scheme.surfaceContainerHighest,
      _PillTone.neutral => scheme.surface,
    };
    final Color fg = switch (tone) {
      _PillTone.positive => scheme.onTertiaryContainer,
      _PillTone.muted => scheme.onSurfaceVariant,
      _PillTone.neutral => scheme.onSurfaceVariant,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.outlineVariant, width: 1)),
      child: Text(text,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w600, color: fg)),
    );
  }
}

class _RungTile extends StatelessWidget {
  const _RungTile({
    required this.rung,
    required this.childName,
    required this.isChild,
    required this.reached,
    required this.isLast,
    required this.expanded,
    required this.onToggleExpand,
    this.onMoveLater,
  });

  final Rung rung;
  final String childName;
  final bool isChild;
  final bool reached;
  final bool isLast;
  final bool expanded;
  final VoidCallback onToggleExpand;
  /// Null for the child viewer always, and for a guardian viewing a rung
  /// that has already been reached — there is nothing to move once it has
  /// happened. When non-null this is the ONLY mutation this tile ever
  /// offers, and it is never available on a reached rung.
  final Future<void> Function()? onMoveLater;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme textTheme = Theme.of(context).textTheme;
    final Color dotBorder = reached ? scheme.primary : scheme.outlineVariant;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          SizedBox(width: 34, child: Column(children: <Widget>[
            Container(
              width: 26, height: 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: reached ? scheme.primary : Colors.transparent,
                border: Border.all(color: dotBorder, width: 2)),
              child: reached ? Icon(Icons.check, size: 16, color: scheme.onPrimary) : null),
            if (!isLast) Expanded(child: Container(
              width: 3,
              margin: const EdgeInsets.symmetric(vertical: 4),
              color: reached
                ? scheme.primary.withValues(alpha: 0.35)
                : scheme.outlineVariant.withValues(alpha: 0.6))),
          ])),
          const SizedBox(width: 12),
          Expanded(child: Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Material(
              color: reached ? scheme.primaryContainer : scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: onToggleExpand,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                      Row(children: <Widget>[
                        Icon(grantIcon(rung.grant), size: 22),
                        const SizedBox(width: 8),
                        Expanded(child: Text(grantTitle(rung.grant),
                          style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
                        Icon(expanded ? Icons.expand_less : Icons.expand_more, size: 20),
                      ]),
                      const SizedBox(height: 8),
                      Wrap(spacing: 8, runSpacing: 6, children: <Widget>[
                        _Pill(text: 'Age ${rung.age}'),
                        _Pill(
                          text: reached
                            ? (isChild ? 'Yours now' : 'Reached')
                            : (isChild ? 'Still to come' : 'Not yet'),
                          tone: reached ? _PillTone.positive : _PillTone.muted),
                        if (reached) const _Pill(text: "Can't be undone", tone: _PillTone.muted),
                        if (!isChild)
                          _Pill(
                            text: rung.notifiesGuardian
                              ? (reached ? 'You were told, once' : "You'll be told, once")
                              : 'Hers, quietly',
                            tone: _PillTone.muted),
                        if (!isChild && rung.requiresTier != null)
                          _Pill(text: 'Tier ${rung.requiresTier} privacy', tone: _PillTone.muted),
                      ]),
                      // A plain conditional, not AnimatedCrossFade: that widget
                      // keeps BOTH branches mounted (only fading opacity) to
                      // interpolate the crossfade, which would leave every
                      // future rung's ceremony text — and every future rung's
                      // "Move this later" button — sitting in the tree even
                      // while collapsed. The whole point of a collapsed future
                      // rung is that there is nothing to find there yet.
                      if (expanded) Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                            Text(
                              isChild
                                ? (reached ? rung.ceremony : "You'll see this when you get there.")
                                : (rung.guardianNote.isEmpty
                                    ? 'Hers, quietly. You will not be notified about this one.'
                                    : withName(rung.guardianNote, childName)),
                              style: textTheme.bodyMedium?.copyWith(height: 1.4)),
                            if (rung.grant == Grant.publishAvailability)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: scheme.secondaryContainer.withValues(alpha: 0.7),
                                    borderRadius: BorderRadius.circular(12)),
                                  child: Text(
                                    isChild
                                      ? "The big one: you decide when you're free, and the "
                                        'ribbon shows what you say.'
                                      : 'The inversion: the schedule stops being a read on '
                                        'her and becomes hers.',
                                    style: textTheme.bodySmall))),
                            if (!isChild && reached)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  "Already happened. It can't be moved or undone from here.",
                                  style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant,
                                    fontStyle: FontStyle.italic))),
                            if (!isChild && !reached && onMoveLater != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Align(alignment: Alignment.centerLeft,
                                  child: OutlinedButton.icon(
                                    onPressed: onMoveLater,
                                    icon: const Icon(Icons.update, size: 18),
                                    label: const Text('Move this later')))),
                          ]),
                        ),
                    ]),
                  ),
                ),
              ),
            ),
          )),
        ]),
      ),
    );
  }
}

/// The only mutation this whole screen offers, and it is reachable only for
/// a rung that has not happened yet (see _RungTile's onMoveLater doc). It
/// demonstrates adjustRung()'s two structural guards directly rather than
/// re-deriving them in the UI: the decrement control is disabled below the
/// rung's own age (a UI-level mirror of adjustRung()'s own refusal), and
/// Save calls the real ported function, which independently refuses a
/// single-guardian request regardless of what the UI allowed you to dial in.
class _MoveLaterDialog extends StatefulWidget {
  const _MoveLaterDialog({required this.rung});
  final Rung rung;

  @override
  State<_MoveLaterDialog> createState() => _MoveLaterDialogState();
}

class _MoveLaterDialogState extends State<_MoveLaterDialog> {
  // UI-only cap — adjustRung() itself has no upper bound. This just keeps a
  // demo stepper from spinning to an absurd age.
  static const int _maxYearsLater = 6;

  late int _newAge;
  bool _otherGuardianAgreed = false;
  AdjustError? _error;

  @override
  void initState() {
    super.initState();
    _newAge = widget.rung.age;
  }

  void _changeAge(int delta) => setState(() {
    _newAge = (_newAge + delta).clamp(widget.rung.age, widget.rung.age + _maxYearsLater);
    _error = null;
  });

  void _save() {
    final List<String> consenting = _otherGuardianAgreed
      ? const <String>['you', 'other-guardian']
      : const <String>['you'];
    final AdjustResult result =
        adjustRung(<Rung>[widget.rung], widget.rung.grant, _newAge, consenting);
    if (!result.ok) {
      setState(() => _error = result.reason);
      return;
    }
    Navigator.of(context).pop(_newAge);
  }

  String _errorMessage(AdjustError e) => switch (e) {
    AdjustError.earlierNotPermitted => 'Rungs can only move later, never earlier.',
    AdjustError.needsBothGuardians => 'This needs both guardians to agree — not just you.',
    AdjustError.unknownRung => 'Unknown rung.',
  };

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme textTheme = Theme.of(context).textTheme;
    return AlertDialog(
      title: Text('Move "${grantTitle(widget.rung.grant)}" later?'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Currently set for age ${widget.rung.age}. Ages can only move later, '
            'never earlier, and never by one guardian alone.',
            style: textTheme.bodyMedium),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: <Widget>[
            const Text('New age', style: TextStyle(fontWeight: FontWeight.w600)),
            Row(children: <Widget>[
              IconButton(
                onPressed: _newAge > widget.rung.age ? () => _changeAge(-1) : null,
                icon: const Icon(Icons.remove_circle_outline)),
              SizedBox(width: 32, child: Text('$_newAge', textAlign: TextAlign.center,
                style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700))),
              IconButton(
                onPressed: _newAge < widget.rung.age + _maxYearsLater
                  ? () => _changeAge(1) : null,
                icon: const Icon(Icons.add_circle_outline)),
            ]),
          ]),
          const SizedBox(height: 8),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _otherGuardianAgreed,
            onChanged: (bool? v) => setState(() {
              _otherGuardianAgreed = v ?? false;
              _error = null;
            }),
            title: Text('The other guardian has also agreed (demo)',
              style: textTheme.bodyMedium)),
          if (_error != null) Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(_errorMessage(_error!),
              style: textTheme.bodySmall?.copyWith(color: scheme.error))),
        ]),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
