// OLIVE BRANCH — guardian shell, care note. UNVERIFIED (no Flutter toolchain
// in tools/verify.sh's automated pipeline — manually built and run via
// `flutter analyze` / `flutter test` this session). MASTERFILE §12.5
// (guardian.ts). Renders MARKUP screen 'careNote'.
//
// 1:1 port of packages/guardian/src/guardian.ts's §12.5 section: CareKind,
// CareItem, CareNote, CARE_NOTE_TTL_DAYS, CARE_NOTE_BANNED, writeCareNote(),
// careNoteVisibleTo().
//
// Two decisions carried over verbatim from the source comment, because they
// are the whole point of the screen:
//   1. A care note is NOT evidence — it is deliberately outside the §13
//      tamper-evident log and expires in seven days, so an honest "she has a
//      cough" never turns into a court exhibit.
//   2. The child never sees it — `careNoteVisibleTo('child')` is false and
//      stays false; "Mum said you were in a bad mood" is poison.
// The tone guard (`writeCareNote` rejecting `CARE_NOTE_BANNED` phrases) is
// enforced before a note is ever created, not applied afterward as a filter
// on display — a rejected note never enters `_sent` at all.
import 'package:flutter/material.dart';

// =========================================================== guardian.ts ===
enum CareKind { sleep, appetite, mood, health, school, social, other }

class CareItem {
  const CareItem({required this.kind, required this.note});
  final CareKind kind;
  final String note;
}

class CareNote {
  const CareNote({required this.id, required this.childId, required this.fromUserId,
    required this.at, required this.items, required this.expiresAt});
  final String id;
  final String childId;
  final String fromUserId;
  final DateTime at;
  final List<CareItem> items;
  final DateTime expiresAt;
  bool get inCourtLog => false;
  bool get visibleToChild => false;
}

const int careNoteTtlDays = 7;

const List<String> careNoteBanned = <String>[
  'you never', 'you always', 'your fault', 'as usual', 'once again',
  'i told you', 'obviously', 'clearly you', 'if you had', 'you failed',
  'she says you', 'she told me you', 'unlike at', 'at your house she',
  'you need to start', 'this is why',
];

sealed class WriteCareNoteResult {}
class CareNoteWritten extends WriteCareNoteResult {
  CareNoteWritten(this.note);
  final CareNote note;
}
class CareNoteRejected extends WriteCareNoteResult {
  CareNoteRejected(this.reason, {this.found = const <String>[]});
  final String reason; // 'empty' | 'accusatory'
  final List<String> found;
}

WriteCareNoteResult writeCareNote(String id, String childId, String fromUserId,
  List<CareItem> items, DateTime at) {
  final List<CareItem> clean = items.where((CareItem i) => i.note.trim().isNotEmpty).toList();
  if (clean.isEmpty) return CareNoteRejected('empty');
  final String text = clean.map((CareItem i) => i.note).join(' ').toLowerCase();
  final List<String> found = careNoteBanned.where((String w) => text.contains(w)).toList();
  if (found.isNotEmpty) return CareNoteRejected('accusatory', found: found);
  return CareNoteWritten(CareNote(id: id, childId: childId, fromUserId: fromUserId, at: at,
    items: clean, expiresAt: at.add(const Duration(days: careNoteTtlDays))));
}

bool careNoteVisibleTo(String role) => role == 'guardian' || role == 'caregiver';

// ============================================================== the demo ===
String _kindLabel(CareKind k) => switch (k) {
  CareKind.sleep => 'Sleep', CareKind.appetite => 'Appetite', CareKind.mood => 'Mood',
  CareKind.health => 'Health', CareKind.school => 'School', CareKind.social => 'Social',
  CareKind.other => 'Other',
};

IconData _kindIcon(CareKind k) => switch (k) {
  CareKind.sleep => Icons.bedtime_outlined, CareKind.appetite => Icons.restaurant_outlined,
  CareKind.mood => Icons.mood_outlined, CareKind.health => Icons.healing_outlined,
  CareKind.school => Icons.school_outlined, CareKind.social => Icons.groups_outlined,
  CareKind.other => Icons.notes_outlined,
};

class CareNoteScreen extends StatefulWidget {
  const CareNoteScreen({super.key, this.childName = 'Ivy'});
  final String childName;
  @override
  State<CareNoteScreen> createState() => _CareNoteScreenState();
}

class _CareNoteScreenState extends State<CareNoteScreen> {
  CareKind _kind = CareKind.mood;
  final TextEditingController _controller = TextEditingController();
  String? _guidance;
  int _nextId = 1;
  final DateTime _now = DateTime.utc(2026, 8, 4, 8, 0);

  final List<CareNote> _sent = <CareNote>[];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    final String text = _controller.text.trim();
    if (text.isEmpty) return;
    final WriteCareNoteResult result = writeCareNote('note-${_nextId++}', 'ivy', 'you',
      <CareItem>[CareItem(kind: _kind, note: text)], _now);
    setState(() {
      switch (result) {
        case CareNoteWritten(:final CareNote note):
          _sent.insert(0, note);
          _controller.clear();
          _guidance = null;
        case CareNoteRejected(reason: 'accusatory', :final List<String> found):
          _guidance = 'That could read as a dig, not care — try rephrasing without '
            '"${found.first}".';
        case CareNoteRejected():
          _guidance = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Care note')),
    body: SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: [
      Text('A soft channel for the hard days — about ${widget.childName}, '
        'never seen by her.', style: const TextStyle(fontSize: 12.5, color: Colors.black54)),
      const SizedBox(height: 16),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final CareKind k in CareKind.values)
          ChoiceChip(label: Text(_kindLabel(k)), avatar: Icon(_kindIcon(k), size: 16),
            selected: _kind == k, onSelected: (_) => setState(() => _kind = k)),
      ]),
      const SizedBox(height: 12),
      TextField(controller: _controller, minLines: 2, maxLines: 5,
        decoration: const InputDecoration(border: OutlineInputBorder(),
          hintText: 'She had a rough night, or a cough, or...')),
      if (_guidance != null) Padding(padding: const EdgeInsets.only(top: 8),
        child: Container(padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Theme.of(context).colorScheme.errorContainer,
            borderRadius: BorderRadius.circular(8)),
          child: Text(_guidance!, style: const TextStyle(fontSize: 12.5)))),
      const SizedBox(height: 10),
      SizedBox(width: double.infinity, height: 48,
        child: FilledButton(onPressed: _send, child: const Text('Send note'))),
      const SizedBox(height: 8),
      const Text('Not evidence — outside the court-tier log, and clears itself in '
        '7 days.', style: TextStyle(fontSize: 11.5, color: Colors.black45)),
      const SizedBox(height: 20),
      const Divider(),
      const SizedBox(height: 8),
      for (final CareNote n in _sent) _NoteTile(note: n, now: _now),
    ])),
  );
}

class _NoteTile extends StatelessWidget {
  const _NoteTile({required this.note, required this.now});
  final CareNote note;
  final DateTime now;
  @override
  Widget build(BuildContext context) {
    final int daysLeft = note.expiresAt.difference(now).inDays;
    return Card(margin: const EdgeInsets.only(bottom: 8), child: ListTile(
      leading: Icon(_kindIcon(note.items.first.kind)),
      title: Text(note.items.first.note),
      subtitle: Text(daysLeft <= 0 ? 'Expires today' : 'Expires in $daysLeft days'),
    ));
  }
}
