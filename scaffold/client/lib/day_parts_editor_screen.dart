// OLIVE BRANCH — "Her day": a grown-up views and edits the child's day-parts in plain words. Verified headless
// (client/test/day_parts_editor_screen_test.dart). MASTERFILE section 8.31.
//
// UNVERIFIED on a real device or against a live server from the phone: covered by flutter test only.
//
// The server seeds four PLACEHOLDER parts for a new child (wake, free time, bedtime, asleep) so a first message
// can land somewhere; they are a guess, and this screen says so until they are changed. Every message that is
// set for "when bedtime starts", every quiet time and the send-time guard read this schedule, so it is worth
// getting right and worth checking before it is saved.
//
// The editing rules live in guardian_send_logic.dart (checkDayParts mirrors the server's own refusals and its
// overlap constraint); the save discipline (one save at a time, no blind overwrite of someone else's newer
// schedule, never retried on its own, the server's answer taken as the truth) lives in day_parts_service.dart.
// This file is only the screen.
//
// Times are her wall clock. The screen does no time-zone arithmetic: bedtime is 8:30 PM in her day whatever
// daylight saving does, and it says "her time" where it matters.
import 'package:flutter/material.dart';

import 'day_parts_service.dart';
import 'guardian_send_logic.dart';

class DayPartsEditorScreen extends StatefulWidget {
  const DayPartsEditorScreen({super.key, required this.childName, required this.service});

  final String childName;
  final DayPartsService service;

  @override
  State<DayPartsEditorScreen> createState() => _DayPartsEditorScreenState();
}

enum _Load { loading, failed, ready }

class _DayPartsEditorScreenState extends State<DayPartsEditorScreen> {
  _Load _load = _Load.loading;
  String _loadError = '';

  /// What the server held when the editor opened (or after the last save): the baseline for "changed" and for the
  /// no-blind-overwrite check.
  List<DayPartSpan> _baseline = const <DayPartSpan>[];
  List<DayPartSpan> _edited = const <DayPartSpan>[];

  bool _saving = false;
  String? _message;
  bool _messageIsGood = false;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _load = _Load.loading;
      _message = null;
    });
    try {
      final List<DayPartSpan> parts = await widget.service.load();
      if (!mounted) return;
      setState(() {
        _baseline = parts;
        _edited = <DayPartSpan>[...parts];
        _load = _Load.ready;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _load = _Load.failed;
        _loadError = e is FormatException
            ? "The server's answer about her day could not be read."
            : "Couldn't reach the server to read ${widget.childName}'s day. Nothing has been changed.";
      });
    }
  }

  bool get _changed => !sameSchedule(_edited, _baseline);

  List<DayPartSpan> get _sorted {
    final List<DayPartSpan> s = <DayPartSpan>[..._edited];
    s.sort((DayPartSpan a, DayPartSpan b) {
      final int c = a.startsLocal.compareTo(b.startsLocal);
      return c != 0 ? c : a.kind.compareTo(b.kind);
    });
    return s;
  }

  Future<void> _editPart(int? index) async {
    final DayPartSpan start = index == null
        ? const DayPartSpan(kind: 'free', startsLocal: '09:00', endsLocal: '10:00', reachable: true)
        : _edited[index];
    final DayPartSpan? result = await showDialog<DayPartSpan>(
      context: context,
      builder: (_) => _PartDialog(initial: start, isNew: index == null, childName: widget.childName),
    );
    if (result == null || !mounted) return;
    setState(() {
      final List<DayPartSpan> next = <DayPartSpan>[..._edited];
      if (index == null) {
        next.add(result);
      } else {
        next[index] = result;
      }
      _edited = next;
      _message = null;
    });
  }

  void _remove(int index) {
    setState(() {
      final List<DayPartSpan> next = <DayPartSpan>[..._edited]..removeAt(index);
      _edited = next;
      _message = null;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _message = null;
    });
    final SaveResult r = await widget.service.save(edited: _edited, baseline: _baseline);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _message = r.text;
      _messageIsGood = r.kind == SaveKind.saved;
      if ((r.kind == SaveKind.saved || r.kind == SaveKind.changedElsewhere) && r.parts != null) {
        _baseline = r.parts!;
        _edited = <DayPartSpan>[...r.parts!];
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final String name = widget.childName;
    return Scaffold(
      appBar: AppBar(title: Text("$name's day")),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: switch (_load) {
              _Load.loading => const Center(child: CircularProgressIndicator()),
              _Load.failed => Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
                    Text(_loadError, key: const Key('dayLoadError'), style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 12),
                    FilledButton(key: const Key('dayRetry'), onPressed: _fetch, child: const Text('Try again')),
                  ])),
              _Load.ready => _body(theme, scheme, name),
            },
          ),
        ),
      ),
    );
  }

  Widget _body(ThemeData theme, ColorScheme scheme, String name) {
    final ScheduleCheck check = checkDayParts(_edited);
    final List<DayPartSpan> sorted = _sorted;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Text(
            "These are the parts of $name's day, in her time. Messages set for \"when bedtime starts\" arrive at the "
            'start of her bedtime, and her tablet stays quiet during the parts you mark as quiet.',
            style: theme.textTheme.bodyMedium),
        if (isPlaceholderSchedule(_baseline))
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Container(
              key: const Key('dayPlaceholder'),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: scheme.tertiaryContainer, borderRadius: BorderRadius.circular(12)),
              child: Text(
                  "These times were filled in as a starting guess when $name was added. They are not her real day yet. "
                  'Change them to match your home, then save.',
                  style: theme.textTheme.bodyMedium),
            ),
          ),
        const SizedBox(height: 16),
        for (final DayPartSpan p in sorted) _partCard(p, theme, scheme),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
              key: const Key('dayAdd'),
              onPressed: _saving || _edited.length >= kMaxDayParts ? null : () => _editPart(null),
              icon: const Icon(Icons.add),
              label: const Text('Add a part')),
        ),
        const SizedBox(height: 12),
        for (final DayPartProblem p in check.problems)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Icon(Icons.error_outline, size: 18, color: scheme.error),
              const SizedBox(width: 8),
              Expanded(child: Text(p.text, key: const Key('dayProblem'), style: theme.textTheme.bodyMedium)),
            ]),
          ),
        for (final DayPartProblem p in check.notes)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Icon(Icons.info_outline, size: 18, color: scheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(child: Text(p.text, key: const Key('dayNote'), style: theme.textTheme.bodySmall)),
            ]),
          ),
        const SizedBox(height: 8),
        Row(children: <Widget>[
          Expanded(
            child: FilledButton(
                key: const Key('daySave'),
                onPressed: (_changed && check.canSave && !_saving) ? _save : null,
                child: _saving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Save her day')),
          ),
          const SizedBox(width: 8),
          TextButton(
              key: const Key('dayUndo'),
              onPressed: (_changed && !_saving) ? () => setState(() => _edited = <DayPartSpan>[..._baseline]) : null,
              child: const Text('Undo changes')),
        ]),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Container(
              key: const Key('daySaveResult'),
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: _messageIsGood ? scheme.primaryContainer : scheme.errorContainer,
                  borderRadius: BorderRadius.circular(12)),
              child: Text(_message!, style: theme.textTheme.bodyMedium),
            ),
          ),
      ]),
    );
  }

  Widget _partCard(DayPartSpan p, ThemeData theme, ColorScheme scheme) {
    final int index = _edited.indexOf(p);
    return Card(
      key: Key('dayPart_${p.kind}_${p.startsLocal}'),
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: _saving ? null : () => _editPart(index),
        title: Text(adultDayPartName(p.kind)),
        subtitle: Text(
            '${clock12(p.startsLocal)} to ${clock12(p.endsLocal)}${p.wraps ? ' the next morning' : ''}\n'
            '${describeDays(p.daysOfWeek)} · ${p.reachable ? 'she can be reached' : 'quiet: no buzzing'}'),
        isThreeLine: true,
        trailing: IconButton(
            key: Key('dayRemove_${p.kind}_${p.startsLocal}'),
            tooltip: 'Remove this part',
            onPressed: _saving ? null : () => _remove(index),
            icon: const Icon(Icons.delete_outline)),
      ),
    );
  }
}

// ----------------------------------------------------------------- one part ==

class _PartDialog extends StatefulWidget {
  const _PartDialog({required this.initial, required this.isNew, required this.childName});
  final DayPartSpan initial;
  final bool isNew;
  final String childName;

  @override
  State<_PartDialog> createState() => _PartDialogState();
}

class _PartDialogState extends State<_PartDialog> {
  late String _kind = widget.initial.kind;
  late String _start = widget.initial.startsLocal;
  late String _end = widget.initial.endsLocal;
  late final Set<int> _days = <int>{...widget.initial.daysOfWeek};
  late bool _reachable = widget.initial.reachable;

  DayPartSpan get _span => DayPartSpan(
      kind: _kind, startsLocal: _start, endsLocal: _end, daysOfWeek: (<int>[..._days]..sort()), reachable: _reachable);

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String? problem = checkDayParts(<DayPartSpan>[_span]).problems.map((DayPartProblem p) => p.text).firstOrNull;
    final List<String> kinds = kDayPartKinds.contains(_kind) ? kDayPartKinds : <String>[...kDayPartKinds, _kind];
    return AlertDialog(
      title: Text(widget.isNew ? 'Add a part of her day' : 'Change this part'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          DropdownButtonFormField<String>(
            key: const Key('partKind'),
            initialValue: _kind,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'What part of her day', border: OutlineInputBorder()),
            items: <DropdownMenuItem<String>>[
              for (final String k in kinds) DropdownMenuItem<String>(value: k, child: Text(adultDayPartName(k))),
            ],
            onChanged: (String? v) => setState(() => _kind = v ?? _kind),
          ),
          const SizedBox(height: 12),
          _TimeField(
              keyPrefix: 'partStart',
              label: 'Starts',
              value: _start,
              onChanged: (String v) => setState(() => _start = v)),
          const SizedBox(height: 8),
          _TimeField(
              keyPrefix: 'partEnd',
              label: 'Ends',
              value: _end,
              onChanged: (String v) => setState(() => _end = v)),
          const SizedBox(height: 4),
          if (_span.wraps)
            Text('It runs on past midnight, into the next morning.', style: theme.textTheme.bodySmall),
          const SizedBox(height: 12),
          Text('Days', style: theme.textTheme.titleSmall),
          Wrap(spacing: 6, children: <Widget>[
            for (final int d in <int>[1, 2, 3, 4, 5, 6, 0])
              FilterChip(
                key: Key('partDay_$d'),
                label: Text(dayShortName(d)),
                selected: _days.contains(d),
                onSelected: (bool on) => setState(() => on ? _days.add(d) : _days.remove(d)),
              ),
          ]),
          SwitchListTile(
            key: const Key('partReachable'),
            contentPadding: EdgeInsets.zero,
            value: _reachable,
            onChanged: (bool v) => setState(() => _reachable = v),
            title: const Text('She can be reached'),
            subtitle: const Text('Turn this off for a quiet part such as sleep or school. Alerts and messages do not buzz her tablet during it.'),
          ),
          if (problem != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(problem, key: const Key('partProblem'), style: TextStyle(color: theme.colorScheme.error)),
            ),
        ]),
      ),
      actions: <Widget>[
        TextButton(key: const Key('partCancel'), onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
            key: const Key('partDone'),
            onPressed: problem == null ? () => Navigator.of(context).pop(_span) : null,
            child: Text(widget.isNew ? 'Add' : 'Done')),
      ],
    );
  }
}

/// Hour, minute and AM/PM for one wall-clock time, as "HH:MM".
class _TimeField extends StatelessWidget {
  const _TimeField({required this.keyPrefix, required this.label, required this.value, required this.onChanged});
  final String keyPrefix;
  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final int minutes = parseHhmm(value) ?? 0;
    final int h24 = minutes ~/ 60;
    final int h12 = h24 % 12 == 0 ? 12 : h24 % 12;
    final int minute = minutes % 60;
    final bool pm = h24 >= 12;
    final List<int> minuteOptions = <int>{for (int m = 0; m < 60; m += 5) m, minute}.toList()..sort();

    void emit({int? hour12, int? min, bool? isPm}) {
      final int hh = (hour12 ?? h12) % 12;
      final bool p = isPm ?? pm;
      onChanged(formatHhmm(((p ? hh + 12 : hh) * 60) + (min ?? minute)));
    }

    return Row(children: <Widget>[
      SizedBox(width: 64, child: Text(label)),
      Expanded(
        child: DropdownButton<int>(
          key: Key('${keyPrefix}Hour'),
          isExpanded: true,
          value: h12,
          items: <DropdownMenuItem<int>>[
            for (int h = 1; h <= 12; h++) DropdownMenuItem<int>(value: h, child: Text('$h')),
          ],
          onChanged: (int? v) => emit(hour12: v),
        ),
      ),
      const SizedBox(width: 6),
      Expanded(
        child: DropdownButton<int>(
          key: Key('${keyPrefix}Minute'),
          isExpanded: true,
          value: minute,
          items: <DropdownMenuItem<int>>[
            for (final int m in minuteOptions) DropdownMenuItem<int>(value: m, child: Text(m.toString().padLeft(2, '0'))),
          ],
          onChanged: (int? v) => emit(min: v),
        ),
      ),
      const SizedBox(width: 6),
      Expanded(
        child: DropdownButton<bool>(
          key: Key('${keyPrefix}Ampm'),
          isExpanded: true,
          value: pm,
          items: const <DropdownMenuItem<bool>>[
            DropdownMenuItem<bool>(value: false, child: Text('AM')),
            DropdownMenuItem<bool>(value: true, child: Text('PM')),
          ],
          onChanged: (bool? v) => emit(isPm: v),
        ),
      ),
    ]);
  }
}
