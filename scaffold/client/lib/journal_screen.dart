// OLIVE BRANCH — child shell, private journal. No longer UNVERIFIED — verified
// by CI (`flutter analyze` and `flutter test` run for real in tools/verify.sh
// and .github/workflows/verify.yml). MASTERFILE §5.12, §9.9.2, P7. Renders
// MARKUP screen 'journal'.
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
// nothing loops, ever. The only animation in this file is the entry she just
// saved appearing, timed via motion_rules.dart's durationFor(quietnessOf
// ('journal'), ...) — which resolves to an instant (0ms) appearance, same
// still-surface treatment as homework_screen.dart, not a timed fade.
//
// DURABLE, AND SEALED. Entries are kept on this device in LocalStore's
// ENCRYPTED `child.<childId>.journal` namespace (AES-256-GCM, key in secure
// storage), so a restart no longer loses them and a copy of the app's files
// is not a readable journal. They are never uploaded, never part of any
// export, and there is still no guardian read path (P7): the repository below
// has no reader argument at all and the screen still goes through
// readJournal() as role 'child'.
import 'dart:async';
import 'package:flutter/material.dart';
import 'access_scope.dart' show motionDuration;
import 'form_factors.dart' as ff;
import 'local_services.dart';
import 'local_store.dart';
import 'access_settings.dart' show kChildTarget;
import 'motion_rules.dart';
import 'picture_bank.dart';

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

/// The journal's on-device store: one sealed document key per entry. There is
/// no method that takes a reader, a role or a guardian — the only way to get
/// entries out is to hold the child's own namespace, which only her screen
/// opens (P7).
class JournalRepository {
  JournalRepository(this._ns);

  /// The app's repository for [childId] (default: this device's child).
  factory JournalRepository.forChild([String? childId]) =>
      JournalRepository(LocalServices.current.area('journal', ownerId: childId));

  final LocalNamespace _ns;

  static String _key(String id) => 'e.${id.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '-')}';

  /// Newest first.
  Future<List<JournalEntry>> load() async {
    final List<JournalEntry> out = <JournalEntry>[];
    for (final String k in await _ns.list()) {
      final Object? raw = await _ns.get(k);
      if (raw is! Map) continue;
      final Object? id = raw['id'], childId = raw['childId'], body = raw['body'], at = raw['createdAt'];
      if (id is! String || childId is! String || body is! String || at is! String) continue;
      final DateTime? created = DateTime.tryParse(at);
      if (created == null) continue;
      out.add(JournalEntry(id: id, childId: childId, body: body, createdAt: created));
    }
    out.sort((JournalEntry a, JournalEntry b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }

  /// Throws [LocalStoreFull] (nothing written) when the journal is at its limit.
  Future<void> add(JournalEntry e) => _ns.put(_key(e.id), <String, Object?>{
        'id': e.id,
        'childId': e.childId,
        'body': e.body,
        'createdAt': e.createdAt.toIso8601String(),
      });
}

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
    this.childId,
    this.initialEntries = const [],
    this.repository,
  });

  final String childName;

  /// Null means this device's child ([LocalServices.childId]) — never a
  /// hard-coded demo id in a live build.
  final String? childId;
  final List<JournalEntry> initialEntries;

  /// Null means the app's sealed on-device journal for [childId].
  final JournalRepository? repository;

  @override
  State<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends State<JournalScreen> {
  late List<JournalEntry> _entries;
  final _controller = TextEditingController();
  String? _justAddedId;
  late final String _childId = widget.childId ?? LocalServices.current.childId;
  late final JournalRepository _repo =
      widget.repository ?? JournalRepository.forChild(widget.childId);

  @override
  void initState() {
    super.initState();
    // Structural P7 exercise (see file header): always role 'child', always
    // her own id. This line means the refusal path is real code, not merely
    // a claim in a comment.
    final result = readJournal(widget.initialEntries, 'child', _childId, _childId);
    _entries = List.of(result.entries ?? const <JournalEntry>[]);
    _controller.addListener(_onTextChanged);
    unawaited(_hydrate());
  }

  /// Reads what was kept on this device. Anything this session already added
  /// stays; stored entries fill in around it, newest first.
  Future<void> _hydrate() async {
    try {
      final stored = await _repo.load();
      if (!mounted) return;
      // Same structural P7 gate as above, applied to what came off disk.
      final mine = readJournal(stored, 'child', _childId, _childId).entries ?? const <JournalEntry>[];
      final have = _entries.map((e) => e.id).toSet();
      setState(() {
        _entries = [..._entries, for (final e in mine) if (!have.contains(e.id)) e]
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      });
    } catch (_) {
      // An unreadable journal file was quarantined by the store; she simply
      // starts a fresh page. Nothing to show, nothing to fear.
    }
  }

  void _onTextChanged() => setState(() {});

  /// A picture writes its plain sentence into the page (after anything already
  /// there), so a child who cannot type yet can still say how she feels. She can
  /// keep the page as it is or add to it; typing works exactly as before.
  void _addPicture(PictureChoice c) {
    final String have = _controller.text.trim();
    final String text = have.isEmpty ? wordsFor(c) : '$have ${wordsFor(c)}';
    _controller.value = TextEditingValue(
        text: text, selection: TextSelection.collapsed(offset: text.length));
  }

  @override
  void dispose() {
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final now = DateTime.now();
    final entry = JournalEntry(
      id: 'j-${now.microsecondsSinceEpoch}', childId: _childId, body: text, createdAt: now);
    setState(() {
      _entries.insert(0, entry);
      _justAddedId = entry.id;
      _controller.clear();
    });
    unawaited(_persist(entry, text));
  }

  /// The entry shows at once (her finger never waits on a disk). If the disk
  /// refuses it, it comes back out of the list and into the box, with a gentle
  /// line — never a silent loss.
  Future<void> _persist(JournalEntry entry, String text) async {
    try {
      await _repo.add(entry);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _entries.removeWhere((e) => e.id == entry.id);
        if (_controller.text.isEmpty) _controller.text = text;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("This page couldn't be kept just now. Your words are still in the box."),
        duration: Duration(seconds: 4)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('My journal')),
      // §8.13.5: this is a permanently STILL surface — no ambient motion,
      // ever (see file header). On a wide tablet/desktop viewport the single
      // column is only ever capped to a comfortable reading width and
      // centered, never split, and nothing below is animated by this cap
      // itself — a pure width-constraint wrapper around the same unchanged
      // content. Same real columnsAt() gate every other width decision in
      // the app uses.
      body: SafeArea(child: LayoutBuilder(builder: (BuildContext context, BoxConstraints constraints) {
        final double textScale = MediaQuery.textScalerOf(context).scale(1);
        final bool capWidth = ff.columnsAt(
            ff.Viewport(w: constraints.maxWidth, h: constraints.maxHeight), textScale) >= 2;
        // A CustomScrollView: the compose area is one box sliver and the
        // entries are a lazy SliverList.builder. This used to be a
        // SingleChildScrollView + Column (so every entry was always built, and
        // every keystroke in the text box rebuilt all of them); the note
        // about sliver lists only realising children near the viewport is the
        // point now, not a pitfall. A journal can hold thousands of entries
        // (see test/perf_journal_lazy_test.dart for the measured difference).
        final Widget content = CustomScrollView(slivers: <Widget>[
          SliverPadding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, _entries.isEmpty ? 16 : 0),
            sliver: SliverToBoxAdapter(child:
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _PrivacyBanner(childName: widget.childName, scheme: scheme),
            const SizedBox(height: 16),
            Card(child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Write something', style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700, color: scheme.primary)),
                const SizedBox(height: 12),
                PictureBank(choices: journalFeelingsBank, onPick: _addPicture, heading: 'How do you feel?'),
                const SizedBox(height: 10),
                PictureBank(choices: journalMomentsBank, onPick: _addPicture, heading: 'What happened today?'),
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
                SizedBox(width: double.infinity, height: kChildTarget,
                  child: FilledButton.icon(
                    onPressed: _controller.text.trim().isEmpty ? null : _save,
                    icon: const Icon(Icons.lock_outline),
                    label: const Text('Keep it, just for me'))),
              ]),
            )),
            const SizedBox(height: 24),
            if (_entries.isEmpty)
              Padding(padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Column(children: [
                  Icon(Icons.edit_note_outlined, size: 40, color: scheme.onSurfaceVariant),
                  const SizedBox(height: 12),
                  Text('Nothing written yet. Whenever you feel like it.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant)),
                ]))),
          ]),
            ),
          ),
          if (_entries.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              sliver: SliverList.builder(
                itemCount: _entries.length,
                findChildIndexCallback: (Key key) {
                  final int i = _entries.indexWhere((JournalEntry e) => ValueKey<String>(e.id) == key);
                  return i < 0 ? null : i;
                },
                itemBuilder: (BuildContext context, int i) {
                  final JournalEntry e = _entries[i];
                  // Align, so a tile still hugs its text (loose width) exactly
                  // as it did inside the old Column, instead of being forced to
                  // the full width a sliver gives its children.
                  return Align(
                    key: ValueKey<String>(e.id),
                    alignment: AlignmentDirectional.centerStart,
                    child: _JournalTile(entry: e, justAdded: e.id == _justAddedId),
                  );
                },
              ),
            ),
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
  const _JournalTile({required this.entry, required this.justAdded});
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
    // Real bug, found by review: this was hardcoded to 350ms and justified
    // against §8.13.1's 400ms *consequence* budget — the wrong, looser rule.
    // The journal is one of §8.13.5's four permanently "still" surfaces
    // (bedtime/homework/journal/emergency-card), which governs it instead:
    // motion_rules.dart now carries 'journal' in _quietSurfaces, and this
    // mirrors homework_screen.dart's own established durationFor() call —
    // resolving to an instant (0ms) appearance, not a timed fade.
    final int fadeMs = durationFor(quietnessOf('journal'), crossfadeMs);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1), duration: motionDuration(context, fadeMs),
      builder: (context, v, child) => Opacity(opacity: v, child: child),
      child: card,
    );
  }
}
