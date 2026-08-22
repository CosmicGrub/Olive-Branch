// OLIVE BRANCH — guardian shell, siblings. UNVERIFIED (no Flutter toolchain
// in tools/verify.sh's automated pipeline — manually built and run via
// `flutter analyze` / `flutter test` this session). MASTERFILE §21.7, §5.17.
// Renders MARKUP screen 'siblings'.
//
// Ported from packages/maturation/src/family.ts's siblings section: Child,
// SiblingSet, ageOf(), openChildren(), closedChildren(), closeFor(),
// staggerNotice(), STAGGER_FORBIDDEN, auditStagger(), siblingsOf(),
// shellTabs(). (The `guardian/pending.ts` module named in this group's brief
// is numbered §12.8-12.11 and covers group calls / the therapist view / the
// preservation prompt / the ping limit — no sibling logic lives there. The
// real source of truth for a family's sibling model is family.ts, so that is
// what this screen ports; MASTERFILE's own authorization notes confirm this
// is the intended split: "`actor_has_edge()` deliberately does not traverse
// `sibling_link` — being guardian of one sibling must never confer access to
// another".)
//
// THE INVARIANT THIS SCREEN EXISTS TO ENFORCE, stated in the group brief:
// sibling links must never WIDEN guardian authority across children. This
// widget does not derive "which children can I see" from `siblingsOf()` or
// from the sibling set at all — `siblingsOf()` is a family-tree fact, not an
// authorization decision. Instead the constructor takes
// `authorizedChildIds`, an explicit allowlist standing in for the real
// family-graph edges this guardian actually holds (§5.1), and every tab is
// filtered against that allowlist before anything is built. A child present
// in the sibling set but absent from it never appears anywhere in this tree
// — see siblings_screen_test.dart, which proves exactly that with a sibling
// the demo viewer is NOT authorized for.
import 'package:flutter/material.dart';
import 'form_factors.dart' as ff;

// =========================================================== family.ts ====
class Child {
  const Child({required this.id, required this.displayName, required this.birthDate,
    this.guardianshipClosedAt, this.colourId});
  final String id;
  final String displayName;
  final DateTime birthDate;
  /// Null while guardianship is open.
  final DateTime? guardianshipClosedAt;
  final Color? colourId;
}

class SiblingSet {
  /// Ordered oldest first — the order they will leave in.
  const SiblingSet(this.children);
  final List<Child> children;
}

int ageOf(Child c, DateTime now) {
  int a = now.year - c.birthDate.year;
  final int m = now.month - c.birthDate.month;
  if (m < 0 || (m == 0 && now.day < c.birthDate.day)) a--;
  return a;
}

List<Child> openChildren(SiblingSet s) =>
  s.children.where((Child c) => c.guardianshipClosedAt == null).toList();

List<Child> closedChildren(SiblingSet s) =>
  s.children.where((Child c) => c.guardianshipClosedAt != null).toList();

Child? _find(SiblingSet s, String childId) {
  for (final Child c in s.children) {
    if (c.id == childId) return c;
  }
  return null;
}

sealed class CloseForResult {}
class CloseForOk extends CloseForResult {
  CloseForOk(this.set, this.remaining);
  final SiblingSet set;
  final int remaining;
}
class CloseForError extends CloseForResult {
  CloseForError(this.reason);
  final String reason; // 'unknown_child' | 'already_closed'
}

/// Guardianship closes PER CHILD, never per family — the sentence the whole
/// feature turns on.
CloseForResult closeFor(SiblingSet s, String childId, DateTime at) {
  final Child? c = _find(s, childId);
  if (c == null) return CloseForError('unknown_child');
  if (c.guardianshipClosedAt != null) return CloseForError('already_closed');
  final SiblingSet set = SiblingSet(s.children.map((Child x) =>
    x.id == childId ? Child(id: x.id, displayName: x.displayName, birthDate: x.birthDate,
      guardianshipClosedAt: at, colourId: x.colourId) : x).toList());
  return CloseForOk(set, openChildren(set).length);
}

class StaggerNotice {
  const StaggerNotice({required this.leavingName, required this.remaining, required this.line});
  final String leavingName;
  final List<String> remaining;
  final String line;
  bool get showOnce => true;
}

StaggerNotice? staggerNotice(SiblingSet s, String childId) {
  final Child? c = _find(s, childId);
  if (c == null || c.guardianshipClosedAt == null) return null;
  final List<String> rest = openChildren(s).map((Child x) => x.displayName).toList();
  final String line = rest.isEmpty
    ? "${c.displayName}'s archive has transferred to her. That is all of them."
    : rest.length == 1
      ? "${c.displayName}'s archive has transferred to her. ${rest[0]} is still here."
      : "${c.displayName}'s archive has transferred to her. "
        '${rest.sublist(0, rest.length - 1).join(', ')} and ${rest.last} are still here.';
  return StaggerNotice(leavingName: c.displayName, remaining: rest, line: line);
}

const List<String> staggerForbidden = <String>[
  'no longer', 'lost access', 'removed', 'terminated', 'expired', 'downgrade',
  'you have lost', 'goodbye', 'sorry to see', 'ended',
];

({bool ok, List<String> found}) auditStagger(StaggerNotice n) {
  final String t = n.line.toLowerCase();
  final List<String> found = staggerForbidden.where((String w) => t.contains(w)).toList();
  return (ok: found.isEmpty, found: found);
}

/// A sibling link SURVIVES closure — a family-tree fact, never an
/// authorization decision. See the file header for why this screen never
/// calls this to decide what to render.
List<Child> siblingsOf(SiblingSet s, String childId) =>
  s.children.where((Child c) => c.id != childId).toList();

class ShellTab {
  const ShellTab({required this.id, required this.name, required this.age,
    required this.colourId, required this.open});
  final String id;
  final String name;
  final int age;
  final Color? colourId;
  final bool open;
}

List<ShellTab> shellTabs(SiblingSet s, DateTime now) => s.children.map((Child c) =>
  ShellTab(id: c.id, name: c.displayName, age: ageOf(c, now), colourId: c.colourId,
    open: c.guardianshipClosedAt == null)).toList();

// ============================================================== the demo ===
// Three children in the family record — one of whom (Sam) this particular
// guardian is deliberately NOT authorized for below, so the filtering that
// keeps sibling links from widening authority can be demonstrated and
// tested honestly, rather than only against a trivial case where every
// sibling happens to also be authorized.
final SiblingSet _familyRecord = SiblingSet(<Child>[
  Child(id: 'ivy', displayName: 'Ivy', birthDate: DateTime.utc(2017, 3, 12),
    colourId: const Color(0xFF43A047)),
  Child(id: 'wren', displayName: 'Wren', birthDate: DateTime.utc(2014, 11, 2),
    colourId: const Color(0xFF7B61FF)),
  Child(id: 'sam', displayName: 'Sam', birthDate: DateTime.utc(2009, 6, 20),
    guardianshipClosedAt: DateTime.utc(2027, 6, 20)),
]);

class SiblingsScreen extends StatefulWidget {
  // Not const: the fallback defaults below resolve against module-level
  // `final` demo data (built from `DateTime.utc(...)`), which is not a
  // compile-time constant. Callers pass explicit values in real use; the
  // wiring pass can call `SiblingsScreen()` (non-const) as-is.
  SiblingsScreen({super.key, SiblingSet? siblingSet,
    this.authorizedChildIds = const <String>{'ivy', 'wren'}, DateTime? now})
    : siblingSet = siblingSet ?? _familyRecord, now = now ?? _now;

  final SiblingSet siblingSet;
  /// The guardian's ACTUAL edges (§5.1) — never derived from the sibling
  /// relationship itself. See the file header.
  final Set<String> authorizedChildIds;
  final DateTime now;

  @override
  State<SiblingsScreen> createState() => _SiblingsScreenState();
}

class _SiblingsScreenState extends State<SiblingsScreen> {
  late String _selected = _visibleTabs().isEmpty ? '' : _visibleTabs().first.id;

  List<ShellTab> _visibleTabs() => shellTabs(widget.siblingSet, widget.now)
    .where((ShellTab t) => widget.authorizedChildIds.contains(t.id)).toList();

  ShellTab? _currentTab(List<ShellTab> tabs) {
    for (final ShellTab t in tabs) {
      if (t.id == _selected) return t;
    }
    return tabs.isEmpty ? null : tabs.first;
  }

  @override
  Widget build(BuildContext context) {
    final List<ShellTab> tabs = _visibleTabs();
    final ShellTab? current = _currentTab(tabs);

    return Scaffold(
      appBar: AppBar(title: const Text('Siblings')),
      // Not child-facing (see file header). On a wide tablet/desktop
      // viewport the single column is only ever capped to a comfortable
      // reading width and centered, never split. Same real columnsAt() gate
      // every other width decision in the app uses.
      body: SafeArea(child: LayoutBuilder(builder: (BuildContext context, BoxConstraints constraints) {
        final double textScale = MediaQuery.textScalerOf(context).scale(1);
        final bool capWidth = ff.columnsAt(
            ff.Viewport(w: constraints.maxWidth, h: constraints.maxHeight), textScale) >= 2;
        final Widget content = ListView(padding: const EdgeInsets.all(16), children: [
          Text('Horizontal swipe between the children you actually have access to. '
            'A sibling link never grants access to a child you are not a guardian of.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 12),
          // 48dp minimum tap target — this row was capped at 44dp (finding #3).
          SizedBox(height: 48, child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: tabs.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (BuildContext context, int i) {
              final ShellTab t = tabs[i];
              return ChoiceChip(
                label: Text('${t.name} · ${t.age}'),
                avatar: CircleAvatar(radius: 8,
                  backgroundColor: t.colourId ?? Theme.of(context).colorScheme.surfaceContainerHighest),
                selected: t.id == _selected,
                onSelected: (_) => setState(() => _selected = t.id));
            })),
          const SizedBox(height: 20),
          if (current != null) _ChildCard(tab: current) else
            const Text('No children on this account.'),
          const SizedBox(height: 16),
          for (final Child c in closedChildren(widget.siblingSet))
            if (widget.authorizedChildIds.contains(c.id))
              _StaggerBanner(notice: staggerNotice(widget.siblingSet, c.id)!),
        ]);
        return capWidth
            ? Center(
                child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: ff.comfortableReadingWidth),
                    child: content))
            : content;
      })),
    );
  }
}

class _ChildCard extends StatelessWidget {
  const _ChildCard({required this.tab});
  final ShellTab tab;
  @override
  Widget build(BuildContext context) => Card(child: Padding(
    padding: const EdgeInsets.all(16),
    child: Row(children: [
      CircleAvatar(radius: 22,
        backgroundColor: tab.colourId ?? Theme.of(context).colorScheme.surfaceContainerHighest,
        foregroundColor: tab.colourId == null
          ? Theme.of(context).colorScheme.onSurfaceVariant : null,
        child: Text(tab.name.substring(0, 1))),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(tab.name, style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700)),
        Text('${tab.age} years old · ${tab.open ? 'guardianship open' : 'guardianship closed'}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ])),
    ])));
}

class _StaggerBanner extends StatelessWidget {
  const _StaggerBanner({required this.notice});
  final StaggerNotice notice;
  @override
  Widget build(BuildContext context) {
    final ({bool ok, List<String> found}) audit = auditStagger(notice);
    assert(audit.ok, 'stagger copy uses forbidden language: ${audit.found}');
    return Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12)),
      child: Text(notice.line, style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: Theme.of(context).colorScheme.onSecondaryContainer)));
  }
}

final DateTime _now = DateTime.utc(2028, 1, 10);
