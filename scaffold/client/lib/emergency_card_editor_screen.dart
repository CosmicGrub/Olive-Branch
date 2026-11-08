// OLIVE BRANCH — the guardian-only editor and history for the LOCAL emergency card.
// No longer UNVERIFIED — verified by CI (client/test/emergency_card_editor_screen_test.dart).
// MASTERFILE section 8.24.
//
// Every field starts EMPTY and every word in it is typed by a guardian: the app
// supplies only neutral labels ("Allergies (written by a guardian)"), never a
// suggestion, an example condition, a dose or advice. The screen refuses a
// non-guardian principal up front, and the service refuses it again (a second lock
// inside the service, emergency_card_local.dart).
//
// Saving carries the version this screen loaded. If another guardian saved first,
// the service answers 'stale_version'; this screen then reloads the card so the
// guardian sees the other change instead of overwriting it.
import 'dart:async';

import 'package:flutter/material.dart';

import 'emergency_card_local.dart';
import 'family_structure_logic.dart' show FamilyPrincipal, canEditStructure;

String _day(String iso) => iso.length >= 10 ? iso.substring(0, 10) : iso;

class EmergencyCardEditorScreen extends StatefulWidget {
  const EmergencyCardEditorScreen({
    super.key, required this.service, required this.principal, this.childName = 'Ivy',
  });
  final EmergencyCardService service;
  final FamilyPrincipal? principal;
  final String childName;

  @override
  State<EmergencyCardEditorScreen> createState() => _EmergencyCardEditorState();
}

class _Row {
  _Row(List<String> v) : c = <TextEditingController>[for (final String s in v) TextEditingController(text: s)];
  final List<TextEditingController> c;
  void dispose() {
    for (final TextEditingController x in c) {
      x.dispose();
    }
  }
}

class _EmergencyCardEditorState extends State<EmergencyCardEditorScreen> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _allergies = TextEditingController();
  final TextEditingController _conditions = TextEditingController();
  final TextEditingController _docName = TextEditingController();
  final TextEditingController _docPractice = TextEditingController();
  final TextEditingController _docPhone = TextEditingController();
  final List<_Row> _meds = <_Row>[];
  final List<_Row> _contacts = <_Row>[];
  int _version = 0;
  bool _loaded = false;
  bool _refused = false;
  String? _banner;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    for (final TextEditingController c in <TextEditingController>[
      _name, _allergies, _conditions, _docName, _docPractice, _docPhone,
    ]) {
      c.dispose();
    }
    for (final _Row r in <_Row>[..._meds, ..._contacts]) {
      r.dispose();
    }
    super.dispose();
  }

  Future<void> _load({String? banner}) async {
    if (!canEditStructure(widget.principal)) {
      setState(() { _refused = true; _loaded = true; });
      return;
    }
    try {
      final EmergencyCardDoc d = await widget.service.read(widget.principal);
      final String who = d.names[widget.principal!.userId! as String] ?? '';
      if (!mounted) return;
      setState(() {
        _apply(d.card ?? const LocalEmergencyCard());
        _version = d.version;
        if (_name.text.isEmpty) _name.text = who;
        _banner = banner;
        _loaded = true;
      });
    } on EcRefused {
      if (mounted) setState(() { _refused = true; _loaded = true; });
    }
  }

  void _apply(LocalEmergencyCard c) {
    _allergies.text = c.allergies.join('\n');
    _conditions.text = c.conditions.join('\n');
    _docName.text = c.doctor.name;
    _docPractice.text = c.doctor.practice;
    _docPhone.text = c.doctor.phone;
    _disposeLater(<_Row>[..._meds, ..._contacts]);
    _meds
      ..clear()
      ..addAll(<_Row>[for (final EcMedicine m in c.medicines) _Row(<String>[m.name, m.dose])]);
    _contacts
      ..clear()
      ..addAll(<_Row>[for (final EcContact x in c.contacts) _Row(<String>[x.name, x.relation, x.phone])]);
  }

  /// Controllers still bound to the widgets of this frame are let go after it.
  void _disposeLater(List<_Row> rows) => WidgetsBinding.instance.addPostFrameCallback((Duration _) {
        for (final _Row r in rows) {
          r.dispose();
        }
      });

  List<String> _lines(TextEditingController c) =>
      <String>[for (final String s in c.text.split('\n')) if (s.trim().isNotEmpty) s.trim()];

  LocalEmergencyCard _card() => LocalEmergencyCard(
        allergies: _lines(_allergies), conditions: _lines(_conditions),
        medicines: <EcMedicine>[
          for (final _Row r in _meds) EcMedicine(name: r.c[0].text, dose: r.c[1].text),
        ],
        doctor: EcDoctor(name: _docName.text, practice: _docPractice.text, phone: _docPhone.text),
        contacts: <EcContact>[
          for (final _Row r in _contacts) EcContact(name: r.c[0].text, relation: r.c[1].text, phone: r.c[2].text),
        ],
      );

  Future<void> _save() async {
    final EcResult r = await widget.service.save(widget.principal, _card(),
        expectedVersion: _version, byName: _name.text);
    if (!mounted) return;
    if (r.ok) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved on this device.')));
      Navigator.of(context).pop(true);
    } else if (r.reason == 'stale_version') {
      // Show the other guardian's change rather than overwrite it.
      await _load(banner: ecRefusalText('stale_version'));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ecRefusalText(r.reason))));
    }
  }

  Widget _field(Key key, TextEditingController c, String label, {int? maxLines = 1, int? maxLength}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextField(key: key, controller: c, maxLines: maxLines, maxLength: maxLength,
            minLines: maxLines == null ? 2 : null,
            decoration: InputDecoration(labelText: label, border: const OutlineInputBorder())),
      );

  Widget _head(String t) => Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 6),
      child: Text(t, style: Theme.of(context).textTheme.titleMedium));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("${widget.childName}'s emergency card"), actions: <Widget>[
        if (_loaded && !_refused)
          IconButton(
              key: const Key('openCardHistory'), tooltip: 'History of changes', icon: const Icon(Icons.history),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => EmergencyCardHistoryScreen(service: widget.service, principal: widget.principal)))),
      ]),
      body: SafeArea(child: !_loaded
          ? const SizedBox.shrink()
          : _refused
              ? const Center(child: Padding(padding: EdgeInsets.all(24), child: Text(
                  'Only a grown-up can change the emergency card.', key: Key('cardGuardianOnly'))))
              : ListView(padding: const EdgeInsets.all(16), children: <Widget>[
                  const Text('Written by a guardian, in your own words. The app adds nothing to it. '
                      'Kept on this device only, sealed. Every change is kept in a history.',
                      key: Key('cardEditorNote')),
                  if (_banner != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_banner!,
                      key: const Key('cardStaleBanner'),
                      style: TextStyle(color: Theme.of(context).colorScheme.error))),
                  _head('Your name (shown in the history)'),
                  _field(const Key('cardMyName'), _name, 'Your name', maxLength: 40),
                  _head('Allergies (written by a guardian)'),
                  _field(const Key('cardAllergies'), _allergies, 'One per line', maxLines: null),
                  _head('Conditions'),
                  _field(const Key('cardConditions'), _conditions, 'One per line', maxLines: null),
                  _head('Medicines'),
                  for (int i = 0; i < _meds.length; i++)
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                      Expanded(child: _field(ValueKey<String>('medName$i'), _meds[i].c[0], 'Name')),
                      const SizedBox(width: 8),
                      Expanded(child: _field(ValueKey<String>('medDose$i'), _meds[i].c[1], 'How much and when')),
                      IconButton(key: ValueKey<String>('removeMed$i'), tooltip: 'Remove this medicine',
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(() => _disposeLater(<_Row>[_meds.removeAt(i)]))),
                    ]),
                  Align(alignment: Alignment.centerLeft, child: TextButton.icon(
                      key: const Key('addMedicine'), icon: const Icon(Icons.add), label: const Text('Add a medicine'),
                      onPressed: _meds.length >= ecMaxMedicines
                          ? null : () => setState(() => _meds.add(_Row(<String>['', ''])))) ),
                  _head('Her doctor'),
                  _field(const Key('docName'), _docName, 'Name'),
                  _field(const Key('docPractice'), _docPractice, 'Practice'),
                  _field(const Key('docPhone'), _docPhone, 'Phone'),
                  _head('Contacts'),
                  for (int i = 0; i < _contacts.length; i++)
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                      Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                        Expanded(child: _field(ValueKey<String>('conName$i'), _contacts[i].c[0], 'Name')),
                        const SizedBox(width: 8),
                        Expanded(child: _field(ValueKey<String>('conRelation$i'), _contacts[i].c[1], 'Who they are')),
                        IconButton(key: ValueKey<String>('removeContact$i'), tooltip: 'Remove this contact',
                            icon: const Icon(Icons.close),
                            onPressed: () => setState(() => _disposeLater(<_Row>[_contacts.removeAt(i)]))),
                      ]),
                      _field(ValueKey<String>('conPhone$i'), _contacts[i].c[2], 'Phone'),
                    ]),
                  Align(alignment: Alignment.centerLeft, child: TextButton.icon(
                      key: const Key('addContact'), icon: const Icon(Icons.add), label: const Text('Add a contact'),
                      onPressed: _contacts.length >= ecMaxContacts
                          ? null : () => setState(() => _contacts.add(_Row(<String>['', '', ''])))) ),
                  const SizedBox(height: 16),
                  FilledButton(
                      key: const Key('saveCard'), onPressed: _save,
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                      child: const Text('Save on this device')),
                  const SizedBox(height: 24),
                ])),
    );
  }
}

// ================================================================== history ===
/// Who changed the card, when, and what it said before. Newest first. Nothing on
/// this screen can edit or remove an entry.
class EmergencyCardHistoryScreen extends StatefulWidget {
  const EmergencyCardHistoryScreen({super.key, required this.service, required this.principal});
  final EmergencyCardService service;
  final FamilyPrincipal? principal;

  @override
  State<EmergencyCardHistoryScreen> createState() => _EmergencyCardHistoryState();
}

class _EmergencyCardHistoryState extends State<EmergencyCardHistoryScreen> {
  List<EcChange>? _h;
  bool _refused = false;

  @override
  void initState() {
    super.initState();
    widget.service.read(widget.principal).then((EmergencyCardDoc d) {
      if (mounted) setState(() => _h = d.history.reversed.toList());
    }).catchError((Object _) {
      if (mounted) setState(() => _refused = true);
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('History of changes')),
        body: SafeArea(child: _refused
            ? const Center(child: Text('Only a grown-up can see this.', key: Key('historyGuardianOnly')))
            : _h == null
                ? const SizedBox.shrink()
                : _h!.isEmpty
                    ? const Center(child: Text('Nothing has been saved yet.', key: Key('historyEmpty')))
                    : ListView(children: <Widget>[
                        for (final EcChange c in _h!)
                          ExpansionTile(
                            key: ValueKey<String>('change-${c.version}'),
                            title: Text('Changed by ${c.byName}'),
                            subtitle: Text('Version ${c.version}, ${_day(c.at)}'),
                            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            expandedCrossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(c.previous == null
                                  ? 'Nothing was written before this.'
                                  : c.previous!.isEmpty
                                      ? 'The card was empty before this.'
                                      : 'Before this change: ${c.previous!.spokenText()}',
                                  key: ValueKey<String>('previous-${c.version}')),
                            ],
                          ),
                      ])),
      );
}
