// OLIVE BRANCH — guardian availability. UNVERIFIED (no Flutter toolchain in
// tools/verify.sh's automated pipeline — manually built and run via
// `flutter analyze` / `flutter test` this session). MASTERFILE §9, MARKUP
// screen 'availability' — "when he can actually be reached, honestly
// rendered." Renders MARKUP screen 'availability'.
//
// Replaces guardian_more.dart's HubSection 'Not yet built' Availability tile
// (previously calling _notBuiltYet with nothing behind it). Backed by real
// endpoints: server/routes.mjs's GET /v1/children/:childId/availability and
// PUT /v1/me/availability, packages/db/src/pool.mjs's
// setAvailabilityWindows()/availabilityFor(), db/migrations/0009_availability.sql's
// RLS. This is a DIFFERENT feature from MASTERFILE §21.3's "she publishes
// her own availability" (the age-15 ladder rung, child-authored) — that one
// remains unbuilt and untouched here. This is the guardian-to-guardian one:
// each guardian's own weekly reachability windows, visible to any live
// co-guardian and to their shared child.
//
// Real network calls, real loading/error states, no fake delay — follows
// child_home_live.dart's LiveChildHomeScreen shape (baseUrl + id, an
// internal dev-login, a real OliveApi, a real loading/error/ready state
// machine), not guardian_setup.dart's shape — this screen has real data to
// fetch and save, which is the entire thing guardian_setup.dart doesn't
// have yet.
//
// Weekday convention: 0=Sunday..6=Saturday, matching the server's own
// (packages/delivery-engine's `weekday % 7 // Sun=0`, carried through
// db/migrations/0009_availability.sql and pool.mjs) — NOT Dart
// DateTime.weekday's native 1=Monday..7=Sunday.
//
// UI simplification, stated honestly: this screen shows and edits ONE
// start/end range per day for the signed-in guardian, matching the task's
// own "each day showing a start/end time range" shape. The database and API
// both allow MULTIPLE windows per day (a morning window and a separate
// evening window). If the signed-in guardian already has more than one
// window on some day (set some other way — there is no other way today,
// but the schema allows it), this screen keeps the extra ones verbatim in
// `_extraMineByDay` and re-sends them unchanged on Save, rather than
// silently deleting whatever it cannot display. It still cannot let the
// guardian EDIT them — a real multi-window-per-day editor is a follow-up,
// not silently glossed over.
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'api_client.dart';

const List<String> _weekdayNames = <String>[
  'Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday',
];

class _MyWindow {
  _MyWindow({required this.startLocal, required this.endLocal, this.note});
  TimeOfDay startLocal;
  TimeOfDay endLocal;
  String? note;
}

class _CoGuardianWindow {
  const _CoGuardianWindow({
    required this.guardianName,
    required this.weekday,
    required this.startLocal,
    required this.endLocal,
    this.note,
  });
  final String guardianName;
  final int weekday;
  final String startLocal; // 'HH:mm' — display-only, never re-parsed
  final String endLocal;
  final String? note;
}

enum _LoadState { loading, error, ready }

class AvailabilityScreen extends StatefulWidget {
  const AvailabilityScreen({
    super.key,
    required this.baseUrl,
    required this.guardianId,
    required this.childId,
    this.httpClient,
  });

  final String baseUrl;
  /// The signed-in guardian's own id — her windows are the ones this screen
  /// lets her edit. Never taken from anywhere the server could be tricked
  /// into trusting a body value instead; the server independently re-derives
  /// this from the session token on every write regardless of what this
  /// screen sends (server/routes.mjs's PUT /v1/me/availability).
  final String guardianId;
  /// A child shared with the co-guardians whose windows this screen also
  /// shows, read-only.
  final String childId;
  /// Injectable for tests (e.g. package:http/testing.dart's MockClient).
  final http.Client? httpClient;

  @override
  State<AvailabilityScreen> createState() => _AvailabilityScreenState();
}

class _AvailabilityScreenState extends State<AvailabilityScreen> {
  _LoadState _state = _LoadState.loading;
  String _errorMessage = '';
  OliveApi? _api;

  final List<_MyWindow?> _mine = List<_MyWindow?>.filled(7, null);
  final Map<int, List<Map<String, dynamic>>> _extraMineByDay = <int, List<Map<String, dynamic>>>{};
  List<_CoGuardianWindow> _others = <_CoGuardianWindow>[];

  bool _saving = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  static TimeOfDay _parseHHmm(String s) {
    final parts = s.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  static String _formatHHmm(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _load() async {
    setState(() => _state = _LoadState.loading);
    try {
      final token = await devLoginFor(widget.baseUrl,
          userId: widget.guardianId, client: widget.httpClient);
      final api = OliveApi(widget.baseUrl, token, client: widget.httpClient);
      final res = await api.getAvailability(widget.childId);
      final windows = (res['windows'] as List).cast<Map<String, dynamic>>();

      final List<_MyWindow?> mine = List<_MyWindow?>.filled(7, null);
      final Map<int, List<Map<String, dynamic>>> extraByDay = <int, List<Map<String, dynamic>>>{};
      final others = <_CoGuardianWindow>[];

      for (final w in windows) {
        final weekday = w['weekday'] as int;
        if (weekday < 0 || weekday > 6) continue; // defensive — server already validates this
        if (w['guardianId'] == widget.guardianId) {
          if (mine[weekday] == null) {
            mine[weekday] = _MyWindow(
              startLocal: _parseHHmm(w['startLocal'] as String),
              endLocal: _parseHHmm(w['endLocal'] as String),
              note: w['note'] as String?,
            );
          } else {
            // A second window on a day this simplified editor already filled
            // for — see file header. Kept, not dropped.
            (extraByDay[weekday] ??= <Map<String, dynamic>>[]).add(w);
          }
        } else {
          others.add(_CoGuardianWindow(
            guardianName: (w['guardianName'] as String?) ?? 'A co-guardian',
            weekday: weekday,
            startLocal: w['startLocal'] as String,
            endLocal: w['endLocal'] as String,
            note: w['note'] as String?,
          ));
        }
      }

      if (!mounted) return;
      setState(() {
        for (var i = 0; i < 7; i++) { _mine[i] = mine[i]; }
        _extraMineByDay
          ..clear()
          ..addAll(extraByDay);
        _others = others;
        _api = api;
        _state = _LoadState.ready;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e is ApiException ? '${e.statusCode}: ${e.error}' : '$e';
        _state = _LoadState.error;
      });
    }
  }

  Future<void> _pickStart(int weekday) async {
    final existing = _mine[weekday];
    final picked = await showTimePicker(
      context: context,
      initialTime: existing?.startLocal ?? const TimeOfDay(hour: 9, minute: 0),
    );
    if (picked == null) return;
    setState(() {
      if (existing != null) {
        existing.startLocal = picked;
      } else {
        _mine[weekday] = _MyWindow(
          startLocal: picked,
          endLocal: TimeOfDay(hour: (picked.hour + 1) % 24, minute: picked.minute),
        );
      }
    });
  }

  Future<void> _pickEnd(int weekday) async {
    final existing = _mine[weekday];
    if (existing == null) return; // set a start first
    final picked = await showTimePicker(context: context, initialTime: existing.endLocal);
    if (picked == null) return;
    setState(() => existing.endLocal = picked);
  }

  void _clearDay(int weekday) => setState(() => _mine[weekday] = null);

  Future<void> _save() async {
    final api = _api;
    if (api == null) return;

    // Client-side ordering check too — a round trip just to learn the same
    // thing the server already validates is a worse experience, not a
    // safer one; the server (server/routes.mjs's invalidAvailabilityBody)
    // still re-checks independently regardless of what this screen sends.
    for (var i = 0; i < 7; i++) {
      final w = _mine[i];
      if (w == null) continue;
      final startMin = w.startLocal.hour * 60 + w.startLocal.minute;
      final endMin = w.endLocal.hour * 60 + w.endLocal.minute;
      if (endMin <= startMin) {
        setState(() => _saveError = '${_weekdayNames[i]}: end time must be after start time.');
        return;
      }
    }

    setState(() { _saving = true; _saveError = null; });
    try {
      final payload = <Map<String, dynamic>>[
        for (var i = 0; i < 7; i++)
          if (_mine[i] != null)
            <String, dynamic>{
              'weekday': i,
              'startLocal': _formatHHmm(_mine[i]!.startLocal),
              'endLocal': _formatHHmm(_mine[i]!.endLocal),
              if (_mine[i]!.note != null) 'note': _mine[i]!.note,
            },
        // Windows this simplified editor cannot display but must not
        // silently delete — see file header.
        for (final extras in _extraMineByDay.values)
          for (final w in extras)
            <String, dynamic>{
              'weekday': w['weekday'],
              'startLocal': w['startLocal'],
              'endLocal': w['endLocal'],
              if (w['note'] != null) 'note': w['note'],
            },
      ];
      await api.setAvailability(payload);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Availability saved.'), duration: Duration(seconds: 2)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saveError = e is ApiException ? '${e.statusCode}: ${e.error}' : '$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_state) {
      case _LoadState.loading:
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      case _LoadState.error:
        return Scaffold(body: Center(child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.cloud_off, size: 40,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text("Couldn't reach the server",
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(_errorMessage, textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 16),
            FilledButton(onPressed: _load, child: const Text('Try again')),
          ]),
        )));
      case _LoadState.ready:
        return _buildReady(context);
    }
  }

  Widget _buildReady(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Availability')),
      // SingleChildScrollView + Column, not ListView: this codebase already
      // hit and fixed the same ListView sliver-virtualization pitfall in
      // child_home.dart/guardian_home.dart (content below the fold silently
      // drops from the ELEMENT TREE, not just from view) — same convention
      // guardian_more.dart's own HubSection/HubTile pair already follows.
      body: SafeArea(child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('When you can be reached',
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            'Set a start and end time for each day your co-guardian should see '
            'you as reachable. Leave a day blank to say nothing about it.',
            style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          const SizedBox(height: 12),
          for (var i = 0; i < 7; i++) _dayRow(context, i),
          if (_saveError != null) Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_saveError!, style: TextStyle(color: scheme.error)),
          ),
          const SizedBox(height: 12),
          SizedBox(height: 48, child: FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
              ? const SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.4))
              : const Text('Save'),
          )),
          const Divider(height: 32),
          Text('Co-guardians', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          if (_others.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('No co-guardian has set their availability yet.',
                style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            )
          else
            for (final w in _others) _otherRow(context, w),
        ]),
      )),
    );
  }

  Widget _dayRow(BuildContext context, int weekday) {
    final w = _mine[weekday];
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(children: [
          SizedBox(width: 92, child: Text(_weekdayNames[weekday],
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
          Expanded(child: w == null
            ? TextButton(
                onPressed: () => _pickStart(weekday),
                child: const Text('Set a window'))
            : Row(children: [
                TextButton(
                  onPressed: () => _pickStart(weekday),
                  child: Text(w.startLocal.format(context))),
                const Text('–'),
                TextButton(
                  onPressed: () => _pickEnd(weekday),
                  child: Text(w.endLocal.format(context))),
              ])),
          if (w != null) IconButton(
            icon: Icon(Icons.close, size: 18, color: scheme.onSurfaceVariant),
            tooltip: 'Clear ${_weekdayNames[weekday]}',
            onPressed: () => _clearDay(weekday),
          ),
        ]),
      ),
    );
  }

  Widget _otherRow(BuildContext context, _CoGuardianWindow w) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(child: Text(
          '${w.guardianName} — ${_weekdayNames[w.weekday]} ${w.startLocal}–${w.endLocal}'
              '${w.note != null ? ' (${w.note})' : ''}',
          style: textTheme.bodyMedium?.copyWith(color: scheme.onSurface))),
      ]),
    );
  }
}
