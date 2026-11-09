// OLIVE BRANCH — Family structure and age bands: screens (suites J and K).
// No longer UNVERIFIED — verified by CI (client/test/family_structure_screens_test.dart).
// Mockups: docs/superpowers/mockups/overhaul2 (r2AgeBands, r2FamilyBuilder, r2FamilyHomes,
// r2ChangePreview, r2ChangeHistory, r2ChangeStory, r2MyPeople, r2AgeHome34, r2Birthday).
//
// LOCAL-FIRST: every screen reads and writes through [FamilyService] (family_structure_store
// .dart) and never a socket. "Release to her" means visible on THIS device's child shell; the
// guardian screens say so plainly: syncing between devices comes later.
//
// Guardian screens (F1): each refuses a non-guardian principal and shows nothing.
// Child screens (F2/F5): get only the derived [ChildView] (no role words, only labels a guardian
// chose). No scores, no streaks, no counters at her (P2): the birthday is information, not a task.
import 'package:flutter/material.dart';

import 'access_scope.dart' show childTargetOf;
import 'contact_labels.dart';
import 'design_tokens.dart';
import 'family_structure_logic.dart';
import 'family_structure_store.dart';
import 'my_people_screen.dart' show NicknamePick, NicknameSheet;

const String syncLaterNote =
    'These choices live on this device. Syncing between devices comes later.';

String bandLabel(String b) => bandDef(b).label;

String roleWords(String r) => switch (r) {
      'guardian' => 'Guardian',
      'parent' => 'Parent',
      'step_parent' => "A parent's partner",
      'relative' => 'Relative',
      'trusted_adult' => 'Trusted adult',
      'sitter' => 'Sitter',
      'foster_parent' => 'Foster parent',
      'caseworker' => 'Caseworker',
      'therapist' => 'Therapist',
      _ => r,
    };

String contactWords(String c) => switch (c) {
      'live_call' => 'Live calls',
      'message' => 'Messages',
      'postcard' => 'Postcards',
      'voice_line' => 'A voice line',
      'supervised_visit' => 'Supervised visits',
      _ => c,
    };

String patternWords(String p) => switch (p) {
      'none' => 'No rhythm set',
      '2-2-3' => '2-2-3',
      '2-2-5-5' => '2-2-5-5',
      'alternating_weeks' => 'Alternating weeks',
      'week_on_week_off' => 'Week on, week off',
      'custom' => 'Something else',
      _ => p,
    };

String areaWords(String a) => switch (a) {
      'reading' => 'Reading and words',
      'games' => 'Games',
      'chat' => 'Messages',
      'calendar' => 'Calendar and weeks',
      'people' => 'My people',
      _ => a,
    };

/// One plain sentence for a history row.
String describeOp(Map<String, Object?> op, String actor) {
  switch (op['op']) {
    case 'put_person':
      final Map<String, Object?> p = (op['person']! as Map).cast<String, Object?>();
      final String name = (p['label']! as String).isEmpty ? roleWords(p['role']! as String) : p['label']! as String;
      return op['before'] == null ? '$actor added $name to the family' : '$actor changed $name';
    case 'remove_person':
      final Map<String, Object?>? b = (op['before'] as Map?)?.cast<String, Object?>();
      return '$actor removed ${b == null || (b['label']! as String).isEmpty ? 'someone' : b['label']}';
    case 'put_home':
      final Map<String, Object?> h = (op['home']! as Map).cast<String, Object?>();
      return op['before'] == null ? '$actor added ${h['name']}' : '$actor changed ${h['name']}';
    case 'remove_home':
      final Map<String, Object?>? b = (op['before'] as Map?)?.cast<String, Object?>();
      return '$actor removed ${b?['name'] ?? 'a home'}';
    case 'set_rhythm':
      return '$actor changed the rhythm to ${patternWords((op['rhythm']! as Map)['pattern']! as String)}';
    case 'set_area_band':
      return op['band'] == null
          ? '$actor set ${areaWords(op['area']! as String)} to follow her band'
          : '$actor set ${areaWords(op['area']! as String)} to ${bandLabel(op['band']! as String)}';
    case 'set_birthday_visible':
      return op['visible'] == true ? '$actor showed her birthday line' : '$actor hid her birthday line';
    case 'set_band_hold':
      return op['hold'] == true ? '$actor held band moves until told' : '$actor let her band follow her age';
    case 'release_band':
      return '$actor released her to ${bandLabel(op['band']! as String)}';
  }
  return '$actor made a change';
}

String opCategory(Map<String, Object?> op) => switch (op['op']) {
      'put_person' || 'remove_person' => 'People',
      'set_rhythm' => 'Rhythm',
      'put_home' || 'remove_home' => 'Homes',
      _ => 'Bands',
    };

String stateWords(String s) => switch (s) {
      'applied' => 'Applied',
      'held' => 'Held until told',
      'scheduled' => 'Scheduled',
      'told' => 'Told her',
      _ => s,
    };

class _GuardiansOnly extends StatelessWidget {
  const _GuardiansOnly();
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Family')),
        body: const Center(
            child: Padding(padding: EdgeInsets.all(24), child: Text('This area is for guardians.', key: Key('familyGuardiansOnly')))),
      );
}

/// Shared by every guardian screen: who is editing, as whom, and for a child of what age.
class FamilyContext {
  const FamilyContext({
    required this.service, required this.principal, this.actorName = 'A guardian',
    this.childName = 'Ivy', this.yearsOld = 7, this.order,
  });
  final FamilyService service;
  final FamilyPrincipal principal;
  final String actorName;
  final String childName;
  final int yearsOld;
  /// A court-ordered rhythm, when one is known on this device (shown locked).
  final Rhythm? order;

  Future<FamilyOverview> overview() => service.overview(principal, yearsOld: yearsOld, order: order);
}

void _push(BuildContext context, Widget w, VoidCallback reload) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => w)).then((_) => reload());

Widget _note(BuildContext context, String text, {Key? key, IconData icon = Icons.info_outline}) {
  final ColorScheme c = Theme.of(context).colorScheme;
  return Container(
    key: key,
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(color: c.surfaceContainerHighest, borderRadius: BorderRadius.circular(AppRadius.md)),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
      Icon(icon, size: 18, color: c.onSurfaceVariant),
      const SizedBox(width: AppSpacing.sm),
      Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
    ]),
  );
}

Widget _gap([double h = AppSpacing.md]) => SizedBox(height: h);

// ============================================================ guardian hub ===
class FamilyStructureScreen extends StatefulWidget {
  const FamilyStructureScreen({super.key, required this.ctx});
  final FamilyContext ctx;
  @override
  State<FamilyStructureScreen> createState() => _FamilyStructureState();
}

class _FamilyStructureState extends State<FamilyStructureScreen> {
  FamilyOverview? _ov;

  @override
  void initState() {
    super.initState();
    if (canEditStructure(widget.ctx.principal)) _load();
  }

  Future<void> _load() async {
    final FamilyOverview o = await widget.ctx.overview();
    if (mounted) setState(() => _ov = o);
  }

  @override
  Widget build(BuildContext context) {
    final FamilyContext c = widget.ctx;
    if (!canEditStructure(c.principal)) return const _GuardiansOnly();
    final FamilyOverview? o = _ov;
    return Scaffold(
      appBar: AppBar(title: const Text('Family structure')),
      body: o == null
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: ListView(padding: const EdgeInsets.all(AppSpacing.lg), children: <Widget>[
                Text('Who is in ${c.childName}’s life, where she sleeps, and how her home grows.',
                    style: Theme.of(context).textTheme.bodyMedium),
                _gap(AppSpacing.sm),
                _note(context, 'Any guardian can change this alone. The other guardian sees every change. '
                    '${c.childName} sees only what you release. $syncLaterNote', key: const Key('familySyncNote')),
                _gap(),
                if (o.pending.isNotEmpty) ..._pendingCards(o),
                Card(child: Column(children: <Widget>[
                  ListTile(
                    key: const Key('familyOpenPeople'), leading: const Icon(Icons.people_outline),
                    title: const Text('People'), subtitle: Text('${o.intended.people.length} in her life'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _push(context, FamilyPeopleScreen(ctx: c), _load)),
                  ListTile(
                    key: const Key('familyOpenHomes'), leading: const Icon(Icons.home_outlined),
                    title: const Text('Homes and rhythm'),
                    subtitle: Text('${o.intended.homes.length} ${o.intended.homes.length == 1 ? 'home' : 'homes'} · ${patternWords(o.intended.rhythm.pattern)}'
                        '${o.rhythmLocked ? ' · set by order' : ''}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _push(context, FamilyHomesScreen(ctx: c), _load)),
                  ListTile(
                    key: const Key('familyOpenBands'), leading: const Icon(Icons.stairs_outlined),
                    title: const Text('Age bands'), subtitle: Text('Her home is at ${bandLabel(o.effectiveBand)}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _push(context, AgeBandsScreen(ctx: c), _load)),
                  ListTile(
                    key: const Key('familyOpenHistory'), leading: const Icon(Icons.history),
                    title: const Text('Change history'), subtitle: Text('${o.history.length} entries, never edited'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _push(context, FamilyHistoryScreen(ctx: c), _load)),
                ])),
              ])),
    );
  }

  List<Widget> _pendingCards(FamilyOverview o) => <Widget>[
        for (final HistoryRow r in o.history.where((HistoryRow h) => o.pending.contains(h.entry.id)))
          Card(
            key: Key('pending_${r.entry.id}'),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Text(describeOp(r.entry.op!, r.record.actorName), style: Theme.of(context).textTheme.titleSmall),
                Text(r.entry.timing!.kind == 'hold' ? 'Held. ${widget.ctx.childName} sees nothing yet.' : 'Scheduled for ${r.entry.timing!.on}.',
                    style: Theme.of(context).textTheme.bodySmall),
                if (r.entry.timing!.kind == 'hold')
                  Align(alignment: Alignment.centerRight, child: TextButton(
                    key: Key('release_${r.entry.id}'),
                    onPressed: () async {
                      await widget.ctx.service.release(widget.ctx.principal,
                          actorName: widget.ctx.actorName, yearsOld: widget.ctx.yearsOld, changeId: r.entry.id);
                      await _load();
                    },
                    child: const Text('I have told her'))),
              ]),
            ),
          ),
        _gap(AppSpacing.sm),
      ];
}

// ================================================================== people ===
class FamilyPeopleScreen extends StatefulWidget {
  const FamilyPeopleScreen({super.key, required this.ctx});
  final FamilyContext ctx;
  @override
  State<FamilyPeopleScreen> createState() => _FamilyPeopleState();
}

class _FamilyPeopleState extends State<FamilyPeopleScreen> {
  FamilyOverview? _ov;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final FamilyOverview o = await widget.ctx.overview();
    if (mounted) setState(() => _ov = o);
  }

  @override
  Widget build(BuildContext context) {
    final FamilyOverview? o = _ov;
    return Scaffold(
      appBar: AppBar(title: const Text('Who is in her life')),
      body: o == null
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(child: ListView(padding: const EdgeInsets.all(AppSpacing.lg), children: <Widget>[
              _note(context, 'Each person shows the name ${widget.ctx.childName} uses, never a role word. '
                  'Roles stay in the background. Nothing reaches her until you choose when.'),
              _gap(),
              for (final Person p in o.intended.people)
                Card(child: ListTile(
                  key: Key('person_${p.id}'),
                  leading: CircleAvatar(child: Text(p.label.isEmpty ? '?' : p.label.characters.first.toUpperCase())),
                  title: Text(p.label.isEmpty ? '(not shown to her)' : p.label),
                  subtitle: Text('${roleWords(p.role)}${p.homeId == null ? '' : ' · ${o.intended.homes.firstWhere((Home h) => h.id == p.homeId).name}'}'
                      '${p.contact.isEmpty ? '' : ' · ${p.contact.map(contactWords).join(', ')}'}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _push(context, PersonEditorScreen(ctx: widget.ctx, intended: o.intended, existing: p), _load))),
              _gap(AppSpacing.sm),
              FilledButton.tonalIcon(
                key: const Key('familyAddPerson'), icon: const Icon(Icons.add), label: const Text('Add someone'),
                onPressed: () => _push(context, PersonEditorScreen(ctx: widget.ctx, intended: o.intended), _load)),
            ])),
    );
  }
}

class PersonEditorScreen extends StatefulWidget {
  const PersonEditorScreen({super.key, required this.ctx, required this.intended, this.existing});
  final FamilyContext ctx;
  final FamilyStructure intended;
  final Person? existing;
  @override
  State<PersonEditorScreen> createState() => _PersonEditorState();
}

class _PersonEditorState extends State<PersonEditorScreen> {
  late final TextEditingController _label = TextEditingController(text: widget.existing?.label ?? '');
  late String _role = widget.existing?.role ?? 'relative';
  late String? _home = widget.existing?.homeId;
  late final Set<String> _contact = <String>{...?widget.existing?.contact};
  late bool _away = widget.existing?.isAwayFlag ?? false;
  late String? _awayUntil = widget.existing?.awayUntil;
  late final String _id = widget.existing?.id ?? widget.ctx.service.newId('p');

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  Map<String, Object?> _op() => <String, Object?>{
        'op': 'put_person',
        'person': Person(
          id: _id, label: _label.text.trim(), role: _role, homeId: _home,
          contact: <String>[for (final String m in contactModes) if (_contact.contains(m)) m],
          away: _away ? true : null, awayUntil: _away ? _awayUntil : null,
        ).toJson(),
      };

  @override
  Widget build(BuildContext context) {
    final bool isNew = widget.existing == null;
    return Scaffold(
      appBar: AppBar(title: Text(isNew ? 'Add someone' : 'Editing ${widget.existing!.label.isEmpty ? 'someone' : widget.existing!.label}')),
      body: SafeArea(child: ListView(padding: const EdgeInsets.all(AppSpacing.lg), children: <Widget>[
        TextField(
          key: const Key('personLabel'), controller: _label, maxLength: maxLabel,
          decoration: InputDecoration(labelText: 'The name ${widget.ctx.childName} uses',
              helperText: 'Leave empty to keep them out of her people.')),
        _gap(),
        DropdownButtonFormField<String>(
          key: const Key('personRole'), initialValue: _role,
          decoration: const InputDecoration(labelText: 'Role (only you see this)'),
          items: <DropdownMenuItem<String>>[
            for (final String r in roles) DropdownMenuItem<String>(value: r, child: Text(roleWords(r))),
          ],
          onChanged: (String? v) => setState(() => _role = v ?? _role)),
        _gap(),
        DropdownButtonFormField<String?>(
          key: const Key('personHome'), initialValue: _home,
          decoration: const InputDecoration(labelText: 'Home'),
          items: <DropdownMenuItem<String?>>[
            const DropdownMenuItem<String?>(value: null, child: Text('No home (near and far)')),
            for (final Home h in widget.intended.homes) DropdownMenuItem<String?>(value: h.id, child: Text(h.name)),
          ],
          onChanged: (String? v) => setState(() => _home = v)),
        _gap(),
        Text('How they reach her', style: Theme.of(context).textTheme.titleSmall),
        Wrap(spacing: AppSpacing.sm, children: <Widget>[
          for (final String m in contactModes)
            FilterChip(
              key: Key('contact_$m'), label: Text(contactWords(m)), selected: _contact.contains(m),
              onSelected: (bool on) => setState(() => on ? _contact.add(m) : _contact.remove(m))),
        ]),
        SwitchListTile(
          key: const Key('personAway'), contentPadding: EdgeInsets.zero, title: const Text('Away for a while'),
          subtitle: Text(_away ? (_awayUntil == null ? 'No end date' : 'Until $_awayUntil') : 'Not away'),
          value: _away, onChanged: (bool v) => setState(() => _away = v)),
        if (_away)
          Align(alignment: Alignment.centerLeft, child: TextButton(
            key: const Key('personAwayDate'),
            onPressed: () async {
              final DateTime now = DateTime.parse('${widget.ctx.service.today()}T12:00:00');
              final DateTime? d = await showDatePicker(
                  context: context, initialDate: now.add(const Duration(days: 7)), firstDate: now, lastDate: now.add(const Duration(days: 730)));
              if (d != null) setState(() => _awayUntil = localIsoDate(d));
            },
            child: const Text('Set an end date'))),
        _gap(),
        FilledButton(
          key: const Key('personContinue'),
          onPressed: () => _push(context, ChangePreviewScreen(ctx: widget.ctx, intended: widget.intended, op: _op()), () {
            if (mounted) Navigator.of(context).maybePop();
          }),
          child: const Text('Next: preview')),
        if (!isNew)
          TextButton(
            key: const Key('personRemove'),
            onPressed: () => _push(context, ChangePreviewScreen(ctx: widget.ctx, intended: widget.intended,
                op: <String, Object?>{'op': 'remove_person', 'personId': _id}), () {
              if (mounted) Navigator.of(context).maybePop();
            }),
            child: const Text('Remove from her people')),
      ])),
    );
  }
}

// ============================================================ homes, rhythm ===
class FamilyHomesScreen extends StatefulWidget {
  const FamilyHomesScreen({super.key, required this.ctx});
  final FamilyContext ctx;
  @override
  State<FamilyHomesScreen> createState() => _FamilyHomesState();
}

class _FamilyHomesState extends State<FamilyHomesScreen> {
  FamilyOverview? _ov;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final FamilyOverview o = await widget.ctx.overview();
    if (mounted) setState(() => _ov = o);
  }

  Future<void> _editHome(FamilyStructure s, Home? existing) async {
    final TextEditingController name = TextEditingController(text: existing?.name ?? '');
    bool sleeps = existing?.childSleeps ?? true;
    final bool? go = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(builder: (BuildContext ctx, StateSetter set) => AlertDialog(
        title: Text(existing == null ? 'Add a home' : 'Edit home'),
        content: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          TextField(key: const Key('homeName'), controller: name, maxLength: maxHomeName, decoration: const InputDecoration(labelText: 'Name')),
          SwitchListTile(
            key: const Key('homeSleeps'), contentPadding: EdgeInsets.zero, title: Text('${widget.ctx.childName} sleeps here'),
            value: sleeps, onChanged: (bool v) => set(() => sleeps = v)),
        ]),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(key: const Key('homeDialogNext'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Next: preview')),
        ],
      )),
    );
    final String text = name.text;
    name.dispose();
    if (go != true || !mounted) return;
    final Map<String, Object?> op = <String, Object?>{
      'op': 'put_home',
      'home': Home(id: existing?.id ?? widget.ctx.service.newId('h'), name: text.trim(), childSleeps: sleeps).toJson(),
    };
    _push(context, ChangePreviewScreen(ctx: widget.ctx, intended: s, op: op), _load);
  }

  @override
  Widget build(BuildContext context) {
    final FamilyOverview? o = _ov;
    return Scaffold(
      appBar: AppBar(title: const Text('Homes and rhythm')),
      body: o == null
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(child: ListView(padding: const EdgeInsets.all(AppSpacing.lg), children: <Widget>[
              _note(context, 'One to four homes. Her weeks and packing follow them.'),
              _gap(),
              for (final Home h in o.intended.homes)
                Card(child: ListTile(
                  key: Key('home_${h.id}'), leading: const Icon(Icons.home_outlined), title: Text(h.name),
                  subtitle: Text('${o.intended.people.where((Person p) => p.homeId == h.id).map((Person p) => p.label.isEmpty ? roleWords(p.role) : p.label).join(', ')}'
                      '${h.childSleeps ? '${o.intended.people.any((Person p) => p.homeId == h.id) ? ' · ' : ''}${widget.ctx.childName} sleeps here' : ''}'),
                  trailing: const Icon(Icons.chevron_right), onTap: () => _editHome(o.intended, h))),
              if (o.intended.homes.length < maxHomes)
                FilledButton.tonalIcon(
                  key: const Key('familyAddHome'), icon: const Icon(Icons.add), label: const Text('Add a home'),
                  onPressed: () => _editHome(o.intended, null)),
              _gap(),
              Card(child: Padding(padding: const EdgeInsets.all(AppSpacing.lg), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Text('Weekly rhythm', style: Theme.of(context).textTheme.titleMedium),
                _gap(AppSpacing.sm),
                Text(patternWords(o.intended.rhythm.pattern), key: const Key('rhythmSummary')),
                if (o.intended.rhythm.exchangeTime != null) Text('Exchange at ${o.intended.rhythm.exchangeTime}'),
                _gap(AppSpacing.sm),
                if (o.rhythmLocked)
                  _note(context, 'Set by a court order. It is shown here and cannot be changed in this app.',
                      key: const Key('rhythmLocked'), icon: Icons.lock_outline)
                else
                  OutlinedButton(
                    key: const Key('rhythmEdit'), child: const Text('Edit the rhythm'),
                    onPressed: () => _push(context, RhythmEditorScreen(ctx: widget.ctx, intended: o.intended), _load)),
              ]))),
            ])),
    );
  }
}

class RhythmEditorScreen extends StatefulWidget {
  const RhythmEditorScreen({super.key, required this.ctx, required this.intended});
  final FamilyContext ctx;
  final FamilyStructure intended;
  @override
  State<RhythmEditorScreen> createState() => _RhythmEditorState();
}

class _RhythmEditorState extends State<RhythmEditorScreen> {
  late String _pattern = widget.intended.rhythm.pattern;
  late int? _day = widget.intended.rhythm.exchangeDay;
  late final TextEditingController _time = TextEditingController(text: widget.intended.rhythm.exchangeTime ?? '');
  String? _error;
  static const List<String> _days = <String>['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

  @override
  void dispose() {
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Edit the rhythm')),
        body: SafeArea(child: ListView(padding: const EdgeInsets.all(AppSpacing.lg), children: <Widget>[
          DropdownButtonFormField<String>(
            key: const Key('rhythmPattern'), initialValue: _pattern, decoration: const InputDecoration(labelText: 'Pattern'),
            items: <DropdownMenuItem<String>>[for (final String p in patterns) DropdownMenuItem<String>(value: p, child: Text(patternWords(p)))],
            onChanged: (String? v) => setState(() => _pattern = v ?? _pattern)),
          _gap(),
          DropdownButtonFormField<int?>(
            key: const Key('rhythmDay'), initialValue: _day, decoration: const InputDecoration(labelText: 'Exchange day'),
            items: <DropdownMenuItem<int?>>[
              const DropdownMenuItem<int?>(value: null, child: Text('Not set')),
              for (int i = 0; i < 7; i++) DropdownMenuItem<int?>(value: i, child: Text(_days[i])),
            ],
            onChanged: (int? v) => setState(() => _day = v)),
          _gap(),
          TextField(key: const Key('rhythmTime'), controller: _time, decoration: InputDecoration(labelText: 'Exchange time (24h, like 18:00)', errorText: _error)),
          _gap(),
          FilledButton(
            key: const Key('rhythmContinue'),
            onPressed: () {
              final String t = _time.text.trim();
              if (t.isNotEmpty && !RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(t)) {
                setState(() => _error = 'Use 24-hour time, like 18:00');
                return;
              }
              _push(context, ChangePreviewScreen(ctx: widget.ctx, intended: widget.intended, op: <String, Object?>{
                'op': 'set_rhythm',
                'rhythm': Rhythm(pattern: _pattern, exchangeDay: _day, exchangeTime: t.isEmpty ? null : t).toJson(),
              }), () {
                if (mounted) Navigator.of(context).maybePop();
              });
            },
            child: const Text('Next: preview')),
        ])),
      );
}

// ======================================================= preview and timing ===
class ChangePreviewScreen extends StatefulWidget {
  const ChangePreviewScreen({super.key, required this.ctx, required this.intended, required this.op});
  final FamilyContext ctx;
  final FamilyStructure intended;
  final Map<String, Object?> op;
  @override
  State<ChangePreviewScreen> createState() => _ChangePreviewState();
}

class _ChangePreviewState extends State<ChangePreviewScreen> {
  FamilyOverview? _ov;
  late String _kind;
  String? _date;
  bool _story = false;
  final TextEditingController _pages = TextEditingController();
  String? _error;
  bool _saving = false;

  bool get _nowOnly => nowOnlyOps.contains(widget.op['op']);

  @override
  void initState() {
    super.initState();
    _kind = defaultTiming(withBefore(widget.intended, widget.op)).kind;
    _load();
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final FamilyOverview o = await widget.ctx.overview();
    if (mounted) setState(() => _ov = o);
  }

  Timing _timing() => _kind == 'date' ? Timing('date', _date) : Timing(_kind);

  Map<String, Object?>? _storyOrNull() {
    if (!_story) return null;
    final List<String> pages = _pages.text.split(RegExp(r'\n\s*\n')).map((String s) => s.trim()).where((String s) => s.isNotEmpty).toList();
    return <String, Object?>{'pages': pages};
  }

  Future<void> _save() async {
    setState(() { _saving = true; _error = null; });
    final FamilyWrite w = await widget.ctx.service.addChange(widget.ctx.principal,
        actorName: widget.ctx.actorName, yearsOld: widget.ctx.yearsOld, op: widget.op,
        timing: _timing().toJson(), story: _storyOrNull(), order: widget.ctx.order);
    if (!mounted) return;
    if (!w.ok) {
      setState(() { _saving = false; _error = _reasonWords(w.reason!); });
      return;
    }
    Navigator.of(context).pop();
  }

  String _reasonWords(String r) => switch (r) {
        'date_not_future' => 'Pick a day after today. For today, choose Now.',
        'bad_date' => 'Pick a date for this change.',
        'date_too_far' => 'That date is too far away. Pick one within two years.',
        'locked_by_order' => 'This is set by a court order and cannot be changed here.',
        'bad_story' => 'The story needs 1 to $maxStoryPages pages, each under $maxStoryPageChars characters.',
        'bad_label' => 'The name is too long or has odd characters.',
        'too_many_homes' => 'Up to $maxHomes homes.',
        'too_many_people' => 'That is as many people as fit.',
        _ => 'That change could not be saved ($r).',
      };

  Widget _miniHome(BuildContext context, String title, ChildView v, {Key? key}) => Expanded(
        child: Column(key: key, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text(title, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          Text('${bandLabel(v.band)} home', style: Theme.of(context).textTheme.bodySmall),
          for (final ChildPlace p in v.places)
            Text('${p.name}: ${p.people.map((ChildPerson x) => x.name).join(', ')}', style: Theme.of(context).textTheme.bodySmall),
          if (v.places.isEmpty) Text('No one listed yet', style: Theme.of(context).textTheme.bodySmall),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final FamilyOverview? o = _ov;
    final String child = widget.ctx.childName;
    final Map<String, Object?> full = withBefore(widget.intended, widget.op);
    final bool big = isBigChange(full);
    return Scaffold(
      appBar: AppBar(title: Text('What $child will see')),
      body: o == null
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(child: ListView(padding: const EdgeInsets.all(AppSpacing.lg), children: <Widget>[
              Text(describeOp(widget.op, 'You'), key: const Key('previewSummary'), style: Theme.of(context).textTheme.titleMedium),
              _gap(),
              Builder(builder: (BuildContext context) {
                final Map<String, Object?> pv = previewChange(o.released, widget.op, _timing(), o.effectiveBand, null, o.rungs, widget.ctx.service.today());
                final bool differs = pv['differs']! as bool;
                final ChildView before = deriveChildView(o.released, o.effectiveBand, null, o.rungs);
                final ChildView after = deriveChildView(applyOp(o.released, full), o.effectiveBand, null, o.rungs);
                return Card(child: Padding(padding: const EdgeInsets.all(AppSpacing.lg), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                    _miniHome(context, 'Now', before, key: const Key('previewBefore')),
                    const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Icon(Icons.arrow_forward)),
                    _miniHome(context, 'After', after, key: const Key('previewAfter')),
                  ]),
                  _gap(AppSpacing.sm),
                  Text(differs ? '$child’s screens change.' : '$child’s screens do not change.', key: const Key('previewDiffers')),
                ])));
              }),
              _gap(),
              if (_nowOnly)
                _note(context, 'This is about her settings, so it applies now.', key: const Key('timingNowOnly'))
              else ...<Widget>[
                Text('When does she see it?', style: Theme.of(context).textTheme.titleSmall),
                RadioGroup<String>(
                  groupValue: _kind,
                  onChanged: (String? v) => setState(() => _kind = v ?? _kind),
                  child: Column(children: <Widget>[
                    const RadioListTile<String>(key: Key('timingNow'), value: 'now', title: Text('Now'), subtitle: Text('Her screens change as soon as you save.')),
                    RadioListTile<String>(
                      key: const Key('timingHold'), value: 'hold', title: const Text('Hold until I have told her'),
                      subtitle: Text('Her view stays the same. You release it when you have talked.${big ? ' Recommended for big changes.' : ''}')),
                    const RadioListTile<String>(key: Key('timingDate'), value: 'date', title: Text('On a date'), subtitle: Text('Her screens change on the day you pick.')),
                  ]),
                ),
                if (_kind == 'date')
                  Align(alignment: Alignment.centerLeft, child: OutlinedButton.icon(
                    key: const Key('timingPickDate'), icon: const Icon(Icons.calendar_today_outlined),
                    label: Text(_date ?? 'Pick a day'),
                    onPressed: () async {
                      final DateTime now = DateTime.parse('${widget.ctx.service.today()}T12:00:00');
                      final DateTime? d = await showDatePicker(
                          context: context, initialDate: now.add(const Duration(days: 1)),
                          firstDate: now.add(const Duration(days: 1)), lastDate: now.add(const Duration(days: maxDateAheadDays)));
                      if (d != null) setState(() => _date = localIsoDate(d));
                    })),
                SwitchListTile(
                  key: const Key('storyToggle'), contentPadding: EdgeInsets.zero, title: const Text('Add a picture story'),
                  subtitle: const Text('You write it, a few short pages. Nothing is written for you.'),
                  value: _story, onChanged: (bool v) => setState(() => _story = v)),
                if (_story)
                  TextField(
                    key: const Key('storyPages'), controller: _pages, minLines: 4, maxLines: 10,
                    decoration: const InputDecoration(labelText: 'Pages (leave a blank line between pages)', border: OutlineInputBorder())),
              ],
              if (_error != null) ...<Widget>[
                _gap(AppSpacing.sm),
                Text(_error!, key: const Key('previewError'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              _gap(),
              FilledButton(
                key: const Key('previewSave'),
                onPressed: _saving ? null : _save,
                child: Text(_nowOnly || _kind == 'now' ? 'Save and apply' : _kind == 'hold' ? 'Save and hold' : 'Save for a date')),
              _gap(AppSpacing.sm),
              _note(context, 'The other guardian sees this change when you save, whichever timing you pick. '
                  'Nothing reaches $child until it is released. $syncLaterNote'),
            ])),
    );
  }
}

// ================================================================== history ===
class FamilyHistoryScreen extends StatefulWidget {
  const FamilyHistoryScreen({super.key, required this.ctx});
  final FamilyContext ctx;
  @override
  State<FamilyHistoryScreen> createState() => _FamilyHistoryState();
}

class _FamilyHistoryState extends State<FamilyHistoryScreen> {
  FamilyOverview? _ov;
  String _filter = 'All';
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final FamilyOverview o = await widget.ctx.overview();
    if (mounted) setState(() => _ov = o);
  }

  @override
  Widget build(BuildContext context) {
    final FamilyOverview? o = _ov;
    return Scaffold(
      appBar: AppBar(title: const Text('Family history')),
      body: o == null
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(child: ListView(padding: const EdgeInsets.all(AppSpacing.lg), children: <Widget>[
              _note(context, 'This list can’t be edited or deleted. Every entry stays, and an undo is a new entry.',
                  key: const Key('historyRule'), icon: Icons.lock_outline),
              _gap(),
              SegmentedButton<String>(
                key: const Key('historyFilter'), showSelectedIcon: false,
                segments: <ButtonSegment<String>>[
                  for (final String f in <String>['All', 'People', 'Rhythm', 'Homes']) ButtonSegment<String>(value: f, label: Text(f)),
                ],
                selected: <String>{_filter}, onSelectionChanged: (Set<String> s) => setState(() => _filter = s.first)),
              _gap(),
              if (o.history.isEmpty)
                const Padding(padding: EdgeInsets.all(AppSpacing.lg), child: Text(
                    'No changes yet. Every change to her people, homes and rhythm will appear here, with who made it and when she was told.',
                    key: Key('historyEmpty'))),
              for (final HistoryRow r in o.history.where((HistoryRow r) => _filter == 'All' || (r.entry.entry == 'change' && opCategory(r.entry.op!) == _filter)))
                _row(context, o, r),
            ])),
    );
  }

  Widget _row(BuildContext context, FamilyOverview o, HistoryRow r) {
    final FamilyRecord rec = r.record;
    final bool isRelease = r.entry.entry == 'release';
    String text;
    if (isRelease) {
      final HistoryEntry? target = o.history.map((HistoryRow h) => h.entry).where((HistoryEntry e) => e.id == r.entry.ref).firstOrNull;
      text = '${rec.actorName} told ${widget.ctx.childName}: ${target?.op == null ? 'a change' : describeOp(target!.op!, '').trim()}';
    } else {
      text = describeOp(r.entry.op!, rec.actorName);
    }
    final bool undone = o.history.any((HistoryRow h) => h.record.undoes == r.entry.id);
    return Card(
      key: Key('hist_${r.entry.id}'),
      child: Padding(padding: const EdgeInsets.all(AppSpacing.md), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Text(text, style: Theme.of(context).textTheme.titleSmall),
        Text('${rec.createdOn} · ${stateWords(r.state)}'
            '${isRelease ? ' on ${rec.toldOn}' : ''}${rec.undoes != null ? ' · puts a change back; the first stays' : ''}${undone ? ' · undone by a later entry' : ''}',
            style: Theme.of(context).textTheme.bodySmall),
        if (rec.story != null) Text('A story from you travels with this change.', style: Theme.of(context).textTheme.bodySmall),
        if (!isRelease && !undone)
          Align(alignment: Alignment.centerRight, child: TextButton(
            key: Key('undo_${r.entry.id}'),
            onPressed: () async {
              final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
              final FamilyWrite w = await widget.ctx.service.undo(widget.ctx.principal,
                  actorName: widget.ctx.actorName, yearsOld: widget.ctx.yearsOld, changeId: r.entry.id, order: widget.ctx.order);
              if (!w.ok && mounted) {
                messenger.showSnackBar(SnackBar(content: Text(w.reason == 'locked_by_order' ? 'That is set by a court order.' : 'Could not undo that.')));
              }
              await _load();
            },
            child: const Text('Undo (as a new entry)'))),
        if (!isRelease && r.state == 'held')
          Align(alignment: Alignment.centerRight, child: TextButton(
            key: Key('histRelease_${r.entry.id}'),
            onPressed: () async {
              await widget.ctx.service.release(widget.ctx.principal,
                  actorName: widget.ctx.actorName, yearsOld: widget.ctx.yearsOld, changeId: r.entry.id);
              await _load();
            },
            child: const Text('I have told her'))),
      ])),
    );
  }
}

// ================================================================ age bands ===
class AgeBandsScreen extends StatefulWidget {
  const AgeBandsScreen({super.key, required this.ctx});
  final FamilyContext ctx;
  @override
  State<AgeBandsScreen> createState() => _AgeBandsState();
}

class _AgeBandsState extends State<AgeBandsScreen> {
  FamilyOverview? _ov;
  final TextEditingController _birth = TextEditingController();
  String? _birthError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _birth.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final FamilyOverview o = await widget.ctx.overview();
    if (mounted) {
      setState(() => _ov = o);
      if (_birth.text.isEmpty && o.birthDate != null) _birth.text = o.birthDate!;
    }
  }

  Future<void> _apply(Map<String, Object?> op) async {
    await widget.ctx.service.addChange(widget.ctx.principal,
        actorName: widget.ctx.actorName, yearsOld: widget.ctx.yearsOld, op: op, timing: Timing.now.toJson(), order: widget.ctx.order);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final FamilyOverview? o = _ov;
    final String child = widget.ctx.childName;
    return Scaffold(
      appBar: AppBar(title: const Text('Age bands')),
      body: o == null
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(child: ListView(padding: const EdgeInsets.all(AppSpacing.lg), children: <Widget>[
              _note(context, 'Bands are proposals. You can hold or change any of them. '
                  'The steps on her ladder (her own list, her journal, her calendar and so on) are permanent and no band or hold can take one back. $syncLaterNote',
                  key: const Key('bandsNote')),
              _gap(),
              for (final BandDef b in bandTable)
                Card(
                  key: Key('band_${b.id}'),
                  color: b.id == o.effectiveBand ? Theme.of(context).colorScheme.primaryContainer : null,
                  child: Padding(padding: const EdgeInsets.all(AppSpacing.md), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                    Text('${b.label}${b.id == o.effectiveBand ? ' · $child is here' : ''}', style: Theme.of(context).textTheme.titleSmall),
                    Text(b.name, style: Theme.of(context).textTheme.bodyMedium),
                    for (final String line in b.summary) Text('• $line', style: Theme.of(context).textTheme.bodySmall),
                  ])),
                ),
              if (o.bandHeld)
                Card(
                  key: const Key('bandHeldCard'),
                  child: Padding(padding: const EdgeInsets.all(AppSpacing.md), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                    Text('$child is ready for ${bandLabel(o.naturalBand)}, but her home is still ${bandLabel(o.effectiveBand)}.', style: Theme.of(context).textTheme.titleSmall),
                    const Text('Nothing changes on her side until you release it.'),
                    Align(alignment: Alignment.centerRight, child: FilledButton(
                      key: const Key('bandRelease'), onPressed: () => _apply(<String, Object?>{'op': 'release_band', 'band': o.naturalBand}),
                      child: const Text('I have told her: release'))),
                  ])),
                ),
              _gap(),
              Text('Next birthday', style: Theme.of(context).textTheme.titleMedium),
              TextField(
                key: const Key('birthDateField'), controller: _birth,
                decoration: InputDecoration(labelText: '$child’s birth date (yyyy-mm-dd, kept on this device)', errorText: _birthError),
                onSubmitted: (String v) async {
                  final bool ok = await widget.ctx.service.setBirthDate(widget.ctx.principal, v.trim().isEmpty ? null : v.trim(), yearsOld: widget.ctx.yearsOld);
                  setState(() => _birthError = ok ? null : 'Use a real past date like 2019-04-02');
                  if (ok) await _load();
                }),
              if (o.birthday != null) _birthdayCard(context, o),
              if (o.birthday == null) const Text('Add her birth date to see a preview of her next birthday.', key: Key('noBirthDate')),
              SwitchListTile(
                key: const Key('birthdayVisible'), contentPadding: EdgeInsets.zero, title: Text('Show $child a quiet line in her birthday week'),
                subtitle: const Text('One calm sentence in her last week. No counter, no tasks. You can hide it for the family, or in a hard year.'),
                value: o.released.birthdayVisible,
                onChanged: (bool v) => _apply(<String, Object?>{'op': 'set_birthday_visible', 'visible': v})),
              _gap(),
              Text('By area', style: Theme.of(context).textTheme.titleMedium),
              const Text('Each area follows her band unless you set it. A child can be ahead in reading and behind in other things.'),
              for (final String a in areas)
                ListTile(
                  key: Key('area_$a'), contentPadding: EdgeInsets.zero, title: Text(areaWords(a)),
                  trailing: DropdownButton<String?>(
                    key: Key('areaDrop_$a'),
                    value: o.released.areaBands[a],
                    hint: const Text('Follows her band'),
                    items: <DropdownMenuItem<String?>>[
                      const DropdownMenuItem<String?>(value: null, child: Text('Follows her band')),
                      for (final String b in ageBands) DropdownMenuItem<String?>(value: b, child: Text(bandLabel(b))),
                    ],
                    onChanged: (String? v) => _apply(<String, Object?>{'op': 'set_area_band', 'area': a, 'band': v})),
                ),
              SwitchListTile(
                key: const Key('bandHold'), contentPadding: EdgeInsets.zero, title: const Text('Hold until I have told her'),
                subtitle: const Text('When she moves to a new band, nothing changes on her side until you release it.'),
                value: o.released.holdBandChange,
                onChanged: (bool v) => _apply(<String, Object?>{'op': 'set_band_hold', 'hold': v})),
            ])),
    );
  }

  Widget _birthdayCard(BuildContext context, FamilyOverview o) {
    final BirthdayInfo b = o.birthday!;
    final Map<String, Object?> pv = o.birthdayPreview!;
    final String child = widget.ctx.childName;
    return Card(
      key: const Key('birthdayCard'),
      child: Padding(padding: const EdgeInsets.all(AppSpacing.md), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Text('$child turns ${b.turnsYears} on ${b.nextOn}. That is ${b.sleepsUntil} ${b.sleepsUntil == 1 ? 'sleep' : 'sleeps'} away.', style: Theme.of(context).textTheme.titleSmall),
        if (pv['bandChanges'] == true)
          Text('She moves to ${bandLabel(b.bandAtBirthday)}. '
              '${pv['heldAtBirthday'] == true ? 'You are holding it: her home stays at ${bandLabel(pv['herHomeAfter']! as String)} until you release it.' : 'Her home will change that day.'}',
              key: const Key('birthdayBandMove'))
        else
          Text('Her band stays ${bandLabel(b.bandNow)}, so her home does not change.', key: const Key('birthdayNoMove')),
      ])),
    );
  }
}

// ================================================================== child =====
IconData _buttonIcon(String b) => switch (b) {
      'call' => Icons.videocam_outlined,
      'chat' => Icons.chat_bubble_outline,
      'postcard' => Icons.mail_outline,
      'voice' => Icons.mic_none,
      'visit' => Icons.event_outlined,
      _ => Icons.circle_outlined,
    };

String _buttonLabel(String b, String name) => switch (b) {
      'call' => 'Call $name',
      'chat' => 'Message $name',
      'postcard' => 'Postcard for $name',
      'voice' => 'Voice line for $name',
      'visit' => 'Visit with $name',
      _ => name,
    };

/// Her family as she knows it: the names she uses, nothing else (no role words, F5).
///
/// Wave 2a ('My people', prototype k.people / kid.person): tap a face and a sheet offers Call, Message and
/// "Change what I call them". Every name goes through [ContactLabels.forChild] (her word, else the age
/// default, else the grown-up's label), so a kid nickname always wins. The sheet's buttons exist only when
/// the person can be reached that way (the family's own contact switches) and a callback is supplied; the
/// rename exists only when [nicknames] (hers, the only writer) is supplied. With neither, a face is just a face.
class MyPeopleScreen extends StatefulWidget {
  const MyPeopleScreen({
    super.key, required this.snapshot, this.childName = 'Ivy', this.nicknames,
    this.age = const AgeLockState(), this.onCall, this.onMessage,
  });
  final FamilyChildSnapshot snapshot;
  final String childName;

  /// Hers. Null = no rename.
  final NicknameRepository? nicknames;

  /// Her locked age (picks Mommy / Daddy for a Mom or a Dad).
  final AgeLockState age;
  final void Function(BuildContext context, String personId, String name)? onCall;
  final void Function(BuildContext context, String personId, String name)? onMessage;
  @override
  State<MyPeopleScreen> createState() => _MyPeopleState();
}

class _MyPeopleState extends State<MyPeopleScreen> {
  bool _storyClosed = false;
  int _page = 0;
  Map<String, String> _nicks = const <String, String>{};

  @override
  void initState() {
    super.initState();
    _loadNicks();
  }

  Future<void> _loadNicks() async {
    Map<String, String> m;
    try {
      m = await widget.nicknames?.load() ?? const <String, String>{};
    } catch (_) {
      m = const <String, String>{};
    }
    if (mounted) setState(() => _nicks = m);
  }

  /// A guardian label of exactly Mom or Dad takes her age's default word; any other label is kept as it is.
  static GrownupKind _kindOf(String label) {
    final String l = label.trim().toLowerCase();
    return l == 'mom' ? GrownupKind.mom : l == 'dad' ? GrownupKind.dad : GrownupKind.other;
  }

  String _nameOf(ChildPerson p) => ContactLabels.forChild(
      GrownupContact(id: p.id, guardianLabel: p.name, kind: _kindOf(p.name)), age: widget.age, nicknames: _nicks);

  Future<void> _openSheet(ChildPerson p) async {
    final bool canCall = widget.onCall != null && (p.buttons.contains('call') || p.buttons.contains('visit'));
    final bool canMsg = widget.onMessage != null && p.buttons.contains('chat');
    final bool canRename = widget.nicknames != null;
    if (!canCall && !canMsg && !canRename) return;
    final String name = _nameOf(p);
    final String? action = await showModalBottomSheet<String>(
      context: context, showDragHandle: true, isScrollControlled: true,
      builder: (BuildContext ctx) => SafeArea(child: SingleChildScrollView(child: Padding(
        key: const Key('personSheet'),
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
          Center(child: CircleAvatar(radius: 42, child: Text(name.characters.first.toUpperCase(), style: const TextStyle(fontSize: 32)))),
          _gap(AppSpacing.sm),
          Text(name, key: const Key('personSheetName'), textAlign: TextAlign.center, style: Theme.of(ctx).textTheme.headlineSmall),
          _gap(),
          if (canCall) FilledButton.icon(
            key: const Key('personCall'), style: _bigButton(ctx), onPressed: () => Navigator.of(ctx).pop('call'),
            icon: const Icon(Icons.videocam_outlined), label: const Text('Call')),
          if (canCall && canMsg) _gap(AppSpacing.sm),
          if (canMsg) FilledButton.tonalIcon(
            key: const Key('personMessage'), style: _bigButton(ctx), onPressed: () => Navigator.of(ctx).pop('message'),
            icon: const Icon(Icons.chat_bubble_outline), label: const Text('Message')),
          if (canRename) ...<Widget>[
            _gap(AppSpacing.sm),
            TextButton.icon(
              key: const Key('personRename'), style: _bigButton(ctx), onPressed: () => Navigator.of(ctx).pop('rename'),
              icon: const Icon(Icons.edit_outlined), label: const Text('Change what I call them')),
          ],
        ]),
      ))),
    );
    if (!mounted || action == null) return;
    if (action == 'call') {
      widget.onCall!(context, p.id, name);
    } else if (action == 'message') {
      widget.onMessage!(context, p.id, name);
    } else if (action == 'rename') {
      await _rename(p);
    }
  }

  static ButtonStyle _bigButton(BuildContext c) =>
      ButtonStyle(minimumSize: WidgetStatePropertyAll<Size>(Size.fromHeight(childTargetOf(c))));

  Future<void> _rename(ChildPerson p) async {
    final NicknamePick? picked = await showModalBottomSheet<NicknamePick>(
      context: context, isScrollControlled: true, showDragHandle: true,
      builder: (BuildContext ctx) => NicknameSheet(
          shown: _nameOf(p), hasNickname: ContactLabels.cleanNickname(_nicks[p.id]) != null),
    );
    if (picked == null) return;
    try {
      await widget.nicknames!.set(p.id, picked.name);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('That did not save. Try again.')));
      return;
    }
    await _loadNicks();
  }

  @override
  Widget build(BuildContext context) {
    final ChildView v = widget.snapshot.view;
    final ChildStory? story = _storyClosed ? null : widget.snapshot.story;
    return Scaffold(
      appBar: AppBar(title: const Text('My people')),
      body: SafeArea(child: ListView(padding: const EdgeInsets.all(AppSpacing.lg), children: <Widget>[
        if (story != null) _storyCard(context, story),
        if (v.places.isEmpty) const Padding(padding: EdgeInsets.all(AppSpacing.lg), child: Text('Nobody is here yet.', key: Key('myPeopleEmpty'))),
        for (final ChildPlace p in v.places)
          Card(
            key: Key('place_${p.id}'),
            child: Padding(padding: const EdgeInsets.all(AppSpacing.lg), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Row(children: <Widget>[
                Icon(p.kind == 'home' ? Icons.home_outlined : Icons.favorite_border),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text(p.name, style: Theme.of(context).textTheme.titleMedium)),
              ]),
              _gap(AppSpacing.sm),
              for (final ChildPerson person in p.people)
                InkWell(
                  key: Key('person_${person.id}'),
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  onTap: () => _openSheet(person),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: childTargetOf(context)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                      child: Row(children: <Widget>[
                        CircleAvatar(radius: 26, child: Text(_nameOf(person).characters.first.toUpperCase())),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(child: Text(_nameOf(person), key: Key('personName_${person.id}'), style: Theme.of(context).textTheme.titleMedium)),
                        for (final String b in person.buttons)
                          Semantics(container: true, label: _buttonLabel(b, _nameOf(person)), child: Padding(
                              padding: const EdgeInsets.only(left: 8), child: ExcludeSemantics(child: Icon(_buttonIcon(b), size: 24)))),
                      ])))),
            ])),
          ),
      ])),
    );
  }

  Widget _storyCard(BuildContext context, ChildStory story) => Card(
        key: const Key('childStory'),
        color: Theme.of(context).colorScheme.primaryContainer,
        child: Padding(padding: const EdgeInsets.all(AppSpacing.lg), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text('A story from ${story.from}', style: Theme.of(context).textTheme.labelLarge),
          _gap(AppSpacing.sm),
          Text(story.pages[_page], key: const Key('storyPageText'), style: Theme.of(context).textTheme.titleMedium),
          _gap(AppSpacing.sm),
          Row(children: <Widget>[
            TextButton(key: const Key('storyNotNow'), onPressed: () => setState(() => _storyClosed = true), child: const Text('Not now')),
            const Spacer(),
            if (_page < story.pages.length - 1)
              FilledButton(key: const Key('storyNext'), onPressed: () => setState(() => _page++), child: const Text('Next'))
            else
              FilledButton(key: const Key('storyDone'), onPressed: () => setState(() => _storyClosed = true), child: const Text('Done')),
          ]),
        ])),
      );
}

String monthName(int m) => const <String>[
      'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'
    ][m - 1];

/// Sleeps until her birthday, said once and softly. Information only (P2): nothing to do or earn.
class BirthdayScreen extends StatelessWidget {
  const BirthdayScreen({super.key, required this.birthday});
  final ChildBirthday birthday;
  @override
  Widget build(BuildContext context) {
    final int m = int.parse(birthday.monthDay.substring(0, 2)), d = int.parse(birthday.monthDay.substring(3));
    final int n = birthday.sleepsUntil;
    return Scaffold(
      appBar: AppBar(title: const Text('My birthday')),
      body: SafeArea(child: ListView(padding: const EdgeInsets.all(AppSpacing.lg), children: <Widget>[
        Card(child: Padding(padding: const EdgeInsets.all(AppSpacing.xl), child: Column(children: <Widget>[
          if (n == 0)
            Text('Today is your birthday', key: const Key('birthdayToday'), style: Theme.of(context).textTheme.headlineSmall)
          else ...<Widget>[
            Text('$n', key: const Key('birthdaySleeps'), style: Theme.of(context).textTheme.displayLarge),
            Text(n == 1 ? 'sleep until your birthday' : 'sleeps until your birthday', style: Theme.of(context).textTheme.titleMedium),
          ],
        ]))),
        _gap(),
        ListTile(leading: const Icon(Icons.calendar_today_outlined), title: Text('${monthName(m)} $d'), subtitle: Text('You will be ${birthday.turnsYears}', key: const Key('birthdayTurns'))),
        _gap(),
        const Text('There is nothing to do. It will just come.', key: Key('birthdayCalm')),
      ])),
    );
  }
}

/// The youngest band's home: three big pictures, no words to read. Each speaks its own name.
class AgeHome34 extends StatelessWidget {
  const AgeHome34({
    super.key, required this.snapshot, required this.childName, this.onCall, this.onStories, this.onColour, this.speak,
  });
  final FamilyChildSnapshot snapshot;
  final String childName;
  final void Function(BuildContext context, String personName)? onCall;
  final void Function(BuildContext context)? onStories;
  final void Function(BuildContext context)? onColour;
  final Future<void> Function(String)? speak;

  @override
  Widget build(BuildContext context) {
    final ChildView v = snapshot.view;
    ChildPerson? hero;
    for (final ChildPlace p in v.places) {
      for (final ChildPerson x in p.people) {
        if (x.id == v.heroPersonId) hero = x;
      }
    }
    // The hero person may sit in no place at the youngest band (places are empty there);
    // the view carries only the id, so the name comes from the snapshot's own people map.
    final String? heroName = hero?.name ?? snapshot.heroName;
    Widget tile(Key key, IconData icon, String label, VoidCallback? tap, {bool big = false, Widget? face}) => Semantics(
          button: true, label: label,
          child: ExcludeSemantics(child: InkWell(
            key: key, borderRadius: BorderRadius.circular(AppRadius.xl),
            onTap: () {
              speak?.call(label);
              tap?.call();
            },
            child: Container(
              constraints: BoxConstraints(minHeight: big ? 180 : 180, minWidth: 180),
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer, borderRadius: BorderRadius.circular(AppRadius.xl)),
              child: Center(child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                Icon(icon, size: big ? 64 : 56),
                if (face != null) ...<Widget>[const SizedBox(width: 16), face],
              ])),
            ),
          )),
        );
    return Scaffold(
      body: SafeArea(child: Padding(padding: const EdgeInsets.all(AppSpacing.lg), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
        Row(children: <Widget>[
          CircleAvatar(radius: 28, child: Text(childName.isEmpty ? '?' : childName.characters.first.toUpperCase())),
          const Spacer(),
          IconButton(
            key: const Key('age34Hear'), iconSize: 32, tooltip: 'Hear it',
            icon: const Icon(Icons.volume_up_outlined), onPressed: () => speak?.call(childName)),
        ]),
        _gap(),
        if (heroName != null) ...<Widget>[
          tile(const Key('age34Call'), Icons.videocam_outlined, 'Call $heroName', () => onCall?.call(context, heroName), big: true,
              face: CircleAvatar(radius: 32, child: Text(heroName.characters.first.toUpperCase()))),
          _gap(),
        ],
        Row(children: <Widget>[
          Expanded(child: tile(const Key('age34Stories'), Icons.menu_book_outlined, 'Stories', () => onStories?.call(context))),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: tile(const Key('age34Colour'), Icons.palette_outlined, 'Colour', () => onColour?.call(context))),
        ]),
        if (snapshot.birthday?.lineShown ?? false) ...<Widget>[
          _gap(),
          Text(birthdayLine(snapshot.birthday!), key: const Key('age34Birthday'), textAlign: TextAlign.center),
        ],
      ]))),
    );
  }
}

/// The quiet caption on her home in her birthday week. The prototype shows a caption and NO number
/// (live/mod-child.js: cap('Your birthday is this week.')); the count lives on the My birthday screen only.
String birthdayLine(ChildBirthday b) => b.sleepsUntil == 0 ? 'Today is your birthday' : 'Your birthday is this week.';
