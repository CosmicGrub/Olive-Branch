// OLIVE BRANCH — child shell, private journal. UNVERIFIED (no Flutter
// toolchain in tools/verify.sh's automated pipeline). MASTERFILE §5.12,
// §9.9.2, P7. Renders MARKUP screen 'journal'.
//
// P7 (permanent prohibition): no parent-facing path to this screen or its
// contents exists at any tier, including guardian escalation and court order
// response — MASTERFILE §2.1. This file keeps that structural, not just
// conventional:
//   - This file imports nothing from guardian_home.dart, entry_gate.dart, or
//     any other guardian-reachable surface, and JournalScreen takes only a
//     child's own name/id — there is no "readerRole" parameter to misuse.
//   - `readJournal()` below is a 1:1 port of readJournal() in
//     packages/agency/src/agency.ts, kept here as a standing, unit-tested
//     assertion that any reader other than the owning child is refused. It is
//     never called from this widget with anything but role 'child'.
//
// §8.13.5 — the journal is a permanently STILL surface: no ambient motion,
// nothing loops, ever. The only animation in this file is a single sub-400ms
// fade-in on the entry she just saved — consequence motion, not autonomous.
import 'package:flutter/material.dart';
import 'form_factors.dart' as ff;

// ================= ported from packages/agency/src/agency.ts (readJournal) =
class JournalEntry {
  const JournalEntry({
    required this.id,
    required this.childId,
    required this.body,
    required this.createdAt,
  });
  final String id;
  final String childId;
  final String body;
  final DateTime createdAt;
}

/// P7 — there is no guardian read path, at any tier, including escalation.
/// Mirrors the TS function's `{ ok: false, reason: 'P7_journal_never' }` shape
/// so the refusal is explicit in the type rather than implied by an absent
/// route.
class JournalReadResult {
  const JournalReadResult.ok(this.entries) : reason = null;
  const JournalReadResult.refused()
      : entries = null,
        reason = 'P7_journal_never';
  final List<JournalEntry>? entries;
  final String? reason;
  bool get isOk => entries != null;
}

JournalReadResult readJournal(
  List<JournalEntry> entries,
  String readerRole,
  String? readerChildId,
  String childId,
) {
  if (readerRole != 'child' || readerChildId != childId) {
    return const JournalReadResult.refused();
  }
  return JournalReadResult.ok(entries.where((e) => e.childId == childId).toList());
}
// =============================================================================

const _weekdayNames = <String>[
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const _monthNames = <String>[
  'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August',
  'September', 'October', 'November', 'December'];

/// Her frame, always — a plain calendar date. Never "N days ago" (that is a
/// step from there to "you haven't written in N days", which is the exact
/// guilt copy this product refuses to build; see quieting_note.dart's header
/// for the same discipline applied to a different screen).
String friendlyDate(DateTime d) =>
    '${_weekdayNames[d.weekday - 1]}, ${_monthNames[d.month - 1]} ${d.day}';

class JournalScreen extends StatefulWidget {
  const JournalScreen({
    super.key,
    required this.childName,
    this.childId = 'demo-child',
    this.initialEntries = const [],
  });

  final String childName;
  final String childId;
  final List<JournalEntry> initialEntries;

  @override
  State<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends State<JournalScreen> {
  late List<JournalEntry> _entries;
  final _controller = TextEditingController();
  int _nextId = 1;
  String? _justAddedId;

  @override
  void initState() {
    super.initState();
    // Structural P7 exercise (see file header): always role 'child', always
    // her own id. This line means the refusal path is real code, not merely
    // a claim in a comment.
    final result = readJournal(widget.initialEntries, 'child', widget.childId, widget.childId);
    _entries = List.of(result.entries ?? const <JournalEntry>[]);
    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() => setState(() {});

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final entry = JournalEntry(
      id: 'local-${_nextId++}', childId: widget.childId, body: text, createdAt: DateTime.now());
    setState(() {
      _entries.insert(0, entry);
      _justAddedId = entry.id;
      _controller.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // Pane A — compose: the whole "Write something" Card, verbatim (field
    // and button together, unsplit). Only ever pulled into a named list so
    // the wide/narrow branches below can share it verbatim rather than
    // diverging — same discipline message_banking.dart/letters_screen.dart
    // use for their own panes.
    final List<Widget> composeChildren = <Widget>[
      Card(child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Write something', style: Theme.of(context).textTheme.titleMedium
            ?.copyWith(fontWeight: FontWeight.w700, color: scheme.primary)),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            minLines: 3,
            maxLines: 8,
            decoration: const InputDecoration(
              hintText: 'Whatever you want. Nobody sees this but you.',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, height: 48,
            child: FilledButton.icon(
              onPressed: _controller.text.trim().isEmpty ? null : _save,
              icon: const Icon(Icons.lock_outline),
              label: const Text('Keep it, just for me'))),
        ]),
      )),
    ];

    // Pane B — the entries region: either the empty state or every
    // _JournalTile, same widgets and same order as this screen always
    // rendered.
    final List<Widget> entryChildren = <Widget>[
      if (_entries.isEmpty)
        Padding(padding: const EdgeInsets.symmetric(vertical: 24),
          child: Center(child: Column(children: [
            Icon(Icons.edit_note_outlined, size: 40, color: scheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text('Nothing written yet. Whenever you feel like it.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: scheme.onSurfaceVariant)),
          ])))
      else
        for (final e in _entries)
          _JournalTile(key: ValueKey(e.id), entry: e, justAdded: e.id == _justAddedId),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('My journal')),
      // SingleChildScrollView + Column, NOT ListView: a ListView's sliver
      // list only realizes children near the current viewport, so entries
      // scrolled below the fold would not exist in the widget/element tree
      // at all — see message_banking.dart's identical note for the same
      // fix on the same class of bug.
      body: SafeArea(child: LayoutBuilder(builder: (BuildContext context, BoxConstraints constraints) {
        // Real §8.11.1 posture logic (form_factors.dart), not a made-up
        // number — same threshold message_banking.dart/letters_screen.dart
        // use for their own two-pane splits.
        final double textScale = MediaQuery.textScalerOf(context).scale(1);
        final bool wide = ff.columnsAt(
            ff.Viewport(w: constraints.maxWidth, h: constraints.maxHeight), textScale) >= 2;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _PrivacyBanner(childName: widget.childName, scheme: scheme),
            const SizedBox(height: 16),
            wide
              ? Row(key: const Key('journalTwoPaneRow'),
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start, children: composeChildren)),
                    const SizedBox(width: 24),
                    Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start, children: entryChildren)),
                  ])
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  ...composeChildren,
                  const SizedBox(height: 24),
                  ...entryChildren,
                ]),
          ]),
        );
      })),
    );
  }
}

class _PrivacyBanner extends StatelessWidget {
  const _PrivacyBanner({required this.childName, required this.scheme});
  final String childName;
  final ColorScheme scheme;
  @override
  Widget build(BuildContext context) => Container(
    // 12, matching the compact inline info-banner role used everywhere else
    // this shape appears (expenses_screen.dart, meds_care.dart,
    // morning_briefing.dart, care_note.dart, guardian_setup.dart) — this
    // banner previously used 16, a leftover from before the radius sweep.
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: scheme.secondaryContainer,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(Icons.shield_outlined, color: scheme.onSecondaryContainer),
      const SizedBox(width: 8),
      Expanded(child: Text(
        "This is yours, $childName. Nobody else can open it — not your mom, "
        'not your dad, not anyone.',
        style: Theme.of(context).textTheme.bodyMedium
          ?.copyWith(color: scheme.onSecondaryContainer))),
    ]),
  );
}

class _JournalTile extends StatelessWidget {
  const _JournalTile({super.key, required this.entry, required this.justAdded});
  final JournalEntry entry;
  final bool justAdded;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final card = Card(margin: const EdgeInsets.only(bottom: 12),
      child: Padding(padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(friendlyDate(entry.createdAt), style: Theme.of(context).textTheme.labelMedium
            ?.copyWith(fontWeight: FontWeight.w600, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          Text(entry.body, style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.35)),
        ]),
      ));
    if (!justAdded) return card;
    // Consequence motion only, and well under the 400ms budget (§8.13.1) —
    // fires once, on the entry she just wrote, then never again for it.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1), duration: const Duration(milliseconds: 350),
      builder: (context, v, child) => Opacity(opacity: v, child: child),
      child: card,
    );
  }
}
