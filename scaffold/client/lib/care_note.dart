// OLIVE BRANCH — guardian shell, care note. Verified by CI (a Flutter
// toolchain now runs for real in tools/verify.sh's automated pipeline —
// also manually built and run via `flutter analyze` / `flutter test` this
// session; CHANGELOG v0.49.61). MASTERFILE §12.5 (guardian.ts). Renders
// MARKUP screen 'careNote'.
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
//
// LIVE WIRING (baseUrl/guardianId/childId/httpClient, all optional and
// additive — same convention expenses_screen.dart/meds_care.dart already
// establish for a guardian_more.dart screen): when supplied, this screen
// fetches the real, not-yet-expired care notes via
// OliveApi.fetchCareNotes() on init and writes a real one via
// OliveApi.writeCareNote(), minting a fresh devLoginFor() session per call.
// The real tone guard (packages/guardian/src/guardian.ts's
// CARE_NOTE_BANNED) runs server-side, before the row is ever written — a
// 400 `accusatory` response is decoded into the same guidance banner the
// demo path's own pure writeCareNote() already produces, so the two paths
// read identically to a guardian even though the guard is now genuinely
// enforced by the server, not just this screen's own local check.
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'api_client.dart';
import 'form_factors.dart' as ff;

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

enum _LoadState { ready, loading, error }

class CareNoteScreen extends StatefulWidget {
  const CareNoteScreen({
    super.key,
    this.childName = 'Ivy',
    this.baseUrl,
    this.guardianId,
    this.childId,
    this.httpClient,
  });
  final String childName;
  final String? baseUrl;
  final String? guardianId;
  final String? childId;
  final http.Client? httpClient;

  bool get _isLive => baseUrl != null && guardianId != null && childId != null;

  @override
  State<CareNoteScreen> createState() => _CareNoteScreenState();
}

class _CareNoteScreenState extends State<CareNoteScreen> {
  CareKind _kind = CareKind.mood;
  final TextEditingController _controller = TextEditingController();
  String? _guidance;
  int _nextId = 1;
  final DateTime _now = DateTime.utc(2026, 8, 4, 8, 0);
  _LoadState _loadState = _LoadState.ready;
  bool _sending = false;

  final List<CareNote> _sent = <CareNote>[];

  @override
  void initState() {
    super.initState();
    if (widget._isLive) _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// The ONLY place this screen calls the network to READ — mirrors
  /// expenses_screen.dart/meds_care.dart's own self-fetching pattern: a
  /// fresh devLoginFor() per load, `api.close()` only on the success path.
  Future<void> _load() async {
    setState(() => _loadState = _LoadState.loading);
    try {
      final String token = await devLoginFor(widget.baseUrl!,
          userId: widget.guardianId!, client: widget.httpClient);
      final OliveApi api = OliveApi(widget.baseUrl!, token, client: widget.httpClient);
      final Map<String, dynamic> result = await api.fetchCareNotes(widget.childId!);
      if (widget.httpClient == null) api.close();
      final List<dynamic> raw = result['entries'] as List<dynamic>? ?? <dynamic>[];
      final List<CareNote> notes = raw.map((dynamic e) {
        final Map<String, dynamic> row = e as Map<String, dynamic>;
        final List<dynamic> rawItems = row['items'] as List<dynamic>? ?? <dynamic>[];
        final List<CareItem> items = rawItems.map((dynamic i) {
          final Map<String, dynamic> item = i as Map<String, dynamic>;
          final CareKind kind = CareKind.values.firstWhere(
            (CareKind k) => k.name == item['kind'], orElse: () => CareKind.other);
          return CareItem(kind: kind, note: item['note'] as String? ?? '');
        }).toList();
        return CareNote(
          id: row['id'] as String, childId: widget.childId!,
          fromUserId: row['fromUserId'] as String? ?? '',
          at: DateTime.tryParse(row['createdAt'] as String? ?? '') ?? _now,
          items: items,
          expiresAt: DateTime.tryParse(row['expiresAt'] as String? ?? '') ?? _now);
      }).toList();
      if (!mounted) return;
      setState(() {
        _sent..clear()..addAll(notes);
        _loadState = _LoadState.ready;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadState = _LoadState.error);
    }
  }

  void _send() {
    final String text = _controller.text.trim();
    if (text.isEmpty) return;
    if (!widget._isLive) {
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
      return;
    }
    _sendLive(text);
  }

  /// Live path — the real tone guard is server-side
  /// (packages/guardian/src/guardian.ts's CARE_NOTE_BANNED, run inside
  /// writeCareNoteRow()), not this screen's own in-memory writeCareNote().
  /// A 400 `accusatory` response is decoded into the identical guidance
  /// text the demo path already renders (see this file's own LIVE WIRING
  /// header).
  Future<void> _sendLive(String text) async {
    setState(() => _sending = true);
    try {
      final String token = await devLoginFor(widget.baseUrl!,
          userId: widget.guardianId!, client: widget.httpClient);
      final OliveApi api = OliveApi(widget.baseUrl!, token, client: widget.httpClient);
      final Map<String, dynamic> row =
          await api.writeCareNote(widget.childId!, _kind.name, text);
      if (widget.httpClient == null) api.close();
      if (!mounted) return;
      if (row['error'] == 'accusatory') {
        final List<dynamic> found = row['found'] as List<dynamic>? ?? <dynamic>[];
        setState(() => _guidance = found.isEmpty ? null
          : 'That could read as a dig, not care — try rephrasing without "${found.first}".');
        return;
      }
      if (row['error'] == 'empty') { setState(() => _guidance = null); return; }
      setState(() {
        _sent.insert(0, CareNote(
          id: row['id'] as String, childId: widget.childId!, fromUserId: widget.guardianId!,
          at: DateTime.tryParse(row['createdAt'] as String? ?? '') ?? DateTime.now(),
          items: <CareItem>[CareItem(kind: _kind, note: text)],
          expiresAt: DateTime.tryParse(row['expiresAt'] as String? ?? '') ?? DateTime.now()));
        _controller.clear();
        _guidance = null;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Couldn't send that note — check your connection and try again.")));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Loading/error UI mirrors expenses_screen.dart/meds_care.dart's own
    // established shape — only ever reachable when this screen is
    // live-wired; the pure demo path never enters either state.
    if (_loadState == _LoadState.loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_loadState == _LoadState.error) {
      return Scaffold(
        appBar: AppBar(title: const Text('Care note')),
        body: Center(child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.cloud_off, size: 40,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text("Couldn't reach the server",
              style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            FilledButton(onPressed: _load, child: const Text('Try again')),
          ]),
        )),
      );
    }
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme textTheme = Theme.of(context).textTheme;

    // Pane A — compose: intro text, kind chips, the note field, the
    // conditional guidance banner, the Send button, and the "not evidence"
    // disclaimer — the whole compose card, verbatim, same as this screen
    // always rendered. Only ever pulled into a named list so the
    // wide/narrow branches below can share it rather than diverging — same
    // discipline message_banking.dart/letters_screen.dart use for their own
    // two panes.
    final List<Widget> composeChildren = <Widget>[
      Text('A soft channel for the hard days — about ${widget.childName}, '
        'never seen by her.', style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
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
        child: Container(padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: scheme.errorContainer,
            borderRadius: BorderRadius.circular(12)),
          child: Text(_guidance!, style: textTheme.bodySmall?.copyWith(
            color: scheme.onErrorContainer)))),
      const SizedBox(height: 8),
      SizedBox(width: double.infinity, height: 48,
        child: FilledButton(onPressed: _sending ? null : _send, child: const Text('Send note'))),
      const SizedBox(height: 8),
      Text('Not evidence — outside the court-tier log, and clears itself in '
        '7 days.', style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
    ];

    // Pane B — the sent-notes list: the divider and every _NoteTile, same
    // widgets and same order as this screen always rendered.
    final List<Widget> listChildren = <Widget>[
      const Divider(),
      const SizedBox(height: 8),
      for (final CareNote n in _sent) _NoteTile(note: n, now: _now),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Care note')),
      // SingleChildScrollView + Column, NOT ListView — a sliver list only
      // realizes children near the viewport, which would silently drop
      // sent notes scrolled below the fold from the widget tree. Same fix
      // message_banking.dart/letters_screen.dart already document for the
      // same bug class.
      body: SafeArea(child: LayoutBuilder(builder: (BuildContext context, BoxConstraints constraints) {
        // Real §8.11.1 posture logic (form_factors.dart), not a made-up
        // number — same threshold message_banking.dart/letters_screen.dart
        // use for their own two-pane splits.
        final double textScale = MediaQuery.textScalerOf(context).scale(1);
        final bool wide = ff.columnsAt(
            ff.Viewport(w: constraints.maxWidth, h: constraints.maxHeight), textScale) >= 2;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: wide
            ? Row(key: const Key('careNoteTwoPaneRow'),
                crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start, children: composeChildren)),
                  const SizedBox(width: 24),
                  Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start, children: listChildren)),
                ])
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                ...composeChildren,
                const SizedBox(height: 20),
                ...listChildren,
              ]),
        );
      })),
    );
  }
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
