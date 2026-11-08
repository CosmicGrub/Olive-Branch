// OLIVE BRANCH — suite F (Care) screens, plus the two small hubs that gather the
// Growing and Care suites. No longer UNVERIFIED — verified by CI
// (client/test/care_screens_test.dart). MASTERFILE section 8.17.
//
// GUARDIAN-ONLY, and LOCAL ONLY. The care binder, hospital mode and appointment
// prep are guardian-to-guardian: they are reached from the guardian shell only
// (the Settings hub, guardian_more.dart) and no type her side holds can read
// them (growing_care_store.dart). The only care-shaped thing her app can show
// is a picture story a guardian wrote AND chose to show her, read-only.
//
// THE APP ADDS NO MEDICAL CONTENT. Every field is empty until a guardian types
// into it. The labels the app supplies are neutral ("Routines", "Allergies
// (written by a guardian)", "School", "Notes"). There are no suggested
// questions, no pre-written explainers, no condition text, no dosing, no
// advice. Hospital mode is a calm re-arrangement of what a guardian already
// wrote plus a door to the existing emergency card (emergency_card.dart).
//
// NOTHING IS SCHEDULED. Appointment prep is a checklist and a question list.
// There is no reminder, no calendar entry and no message; the date is only
// something a guardian wants to see written down.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'emergency_card.dart';
import 'emergency_card_editor_screen.dart';
import 'emergency_card_local.dart';
import 'family_structure_logic.dart' show FamilyPrincipal, maxStoryPageChars, maxStoryPages;
import 'growing_care_logic.dart';
import 'growing_care_store.dart';
import 'growing_care_widgets.dart';
import 'child_explainer_screens.dart';
import 'growing_screens.dart';
import 'hub_widgets.dart';

// ================================================================== the hubs ==
/// One hub, two faces: [care] false lists the Growing suites, true the Care ones.
class GrowingCareHubScreen extends StatefulWidget {
  const GrowingCareHubScreen({
    super.key, required this.care, this.childName = 'Ivy', this.stores, this.guardianId = 'local-guardian',
    this.fromName = '', this.emergency, this.openEmergencyCard,
  });
  final bool care;
  final String childName;
  final GrowingCareStores? stores;

  /// The guardian using this hub (the principal for the guardian-only editors) and the name that
  /// marks what they leave in her memory box.
  final String guardianId;
  final String fromName;

  /// The local emergency card (hospital mode reads it), and how to open the emergency card screen
  /// (the app supplies one that keeps using a live session's server card; null opens the local one).
  final EmergencyCardService? emergency;
  final void Function(BuildContext context)? openEmergencyCard;

  @override
  State<GrowingCareHubScreen> createState() => _GrowingCareHubScreenState();
}

class _GrowingCareHubScreenState extends State<GrowingCareHubScreen> {
  late final GrowingCareStores _s = widget.stores ?? GrowingCareStores.forChild();
  SuiteSwitches _sw = const SuiteSwitches();
  bool _loaded = false;

  List<String> get _suites => widget.care ? careSuiteKeys : growingSuiteKeys;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final SuiteSwitches sw = await _s.switches.load();
    if (mounted) setState(() { _sw = sw; _loaded = true; });
  }

  Future<void> _set(String suite, bool on) async {
    try {
      final SuiteSwitches next = await _s.switches.setSuite(suite, on);
      if (mounted) setState(() => _sw = next);
    } on CareRefused catch (e) {
      if (mounted) showRefusal(context, e);
    }
  }

  void _open(Widget w) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => w));

  /// The only suite-to-screen map: a suite that is off is not offered at all.
  Widget? _tile(String suite) {
    final String n = widget.childName;
    switch (suite) {
      case 'timeCapsule':
        return HubTile(key: const Key('hubTimeCapsule'), icon: Icons.lock_clock_outlined, title: 'Time capsule',
            subtitle: 'Seal a note for a day to come',
            onTap: () => _open(TimeCapsuleScreen(childName: n, stores: _s)));
      case 'firstTimes':
        return HubTile(key: const Key('hubFirstTimes'), icon: Icons.star_outline, title: 'First times',
            subtitle: 'A record of what happened for the first time',
            onTap: () => _open(FirstTimesScreen(childName: n, stores: _s)));
      case 'pencilMarks':
        return HubTile(key: const Key('hubPencilMarks'), icon: Icons.straighten, title: 'Growing marks',
            subtitle: 'The doorframe, kept on a screen',
            onTap: () => _open(PencilMarksScreen(childName: n, stores: _s)));
      case 'memoryBox':
        // A grown-up may leave a marked note or photo in its own section; what she keeps herself
        // stays hers and has no editor here.
        return HubTile(key: const Key('hubMemoryBox'), icon: Icons.inventory_2_outlined, title: 'Leave something for her',
            subtitle: 'A note or photo marked as from you, in its own place in her memory box',
            onTap: () => _open(LeaveForHerScreen(childName: n, stores: _s,
                principal: FamilyPrincipal(roleName: 'guardian', userId: widget.guardianId),
                fromName: widget.fromName)));
      case 'careBinder':
        return HubTile(key: const Key('hubCareBinder'), icon: Icons.folder_shared_outlined, title: 'Care binder',
            subtitle: 'Routines, allergies, contacts, school: in your words',
            onTap: () => _open(CareBinderScreen(childName: n, stores: _s)));
      case 'hospitalMode':
        return HubTile(key: const Key('hubHospitalMode'), icon: Icons.local_hospital_outlined, title: 'Hospital mode',
            subtitle: 'One calm page for a stressed adult',
            onTap: () => _open(HospitalModeScreen(
                childName: n, stores: _s, emergency: widget.emergency,
                openEmergencyCard: widget.openEmergencyCard,
                principal: FamilyPrincipal(roleName: 'guardian', userId: widget.guardianId))));
      case 'explainerCards':
        return HubTile(key: const Key('hubExplainers'), icon: Icons.menu_book_outlined, title: 'Picture stories',
            subtitle: 'Short stories you write for her, shown only if you choose',
            onTap: () => _open(ExplainerAuthoringScreen(childName: n, stores: _s)));
      case 'appointmentPrep':
        return HubTile(key: const Key('hubAppointmentPrep'), icon: Icons.checklist_outlined, title: 'Appointment prep',
            subtitle: 'Your checklist and questions before a visit',
            onTap: () => _open(AppointmentPrepScreen(childName: n, stores: _s)));
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> tiles = <Widget>[
      for (final String k in _suites) ?(_sw.on(k) ? _tile(k) : null),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(widget.care ? 'Care' : 'Growing')),
      body: SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        LocalOnlyBanner(widget.care
            ? '$localOnlyNote Only grown-ups see these. ${widget.childName} never does, except a picture story you choose to show.'
            : '$localOnlyNote ${widget.childName} sees only what you choose to show.'),
        const SizedBox(height: 8),
        if (_loaded && tiles.isEmpty)
          const Padding(padding: EdgeInsets.all(16), child: Text('Everything here is switched off.', key: Key('hubAllOff'))),
        ...tiles,
        HubSection(title: 'Switch on or off', children: <Widget>[
          for (final String k in _suites)
            SwitchListTile(
                key: ValueKey<String>('switch_$k'), title: Text(suiteTitles[k]!), value: _sw.on(k),
                subtitle: k == 'memoryBox'
                    ? const Text('Hers to fill. You can only leave a marked note or photo in its own section.')
                    : null,
                onChanged: _loaded ? (bool v) => _set(k, v) : null),
        ]),
      ]))),
    );
  }
}

// ================================================================ care binder ==
class CareBinderScreen extends StatefulWidget {
  const CareBinderScreen({super.key, this.childName = 'Ivy', this.stores, this.now});
  final String childName;
  final GrowingCareStores? stores;
  final DateTime Function()? now;

  @override
  State<CareBinderScreen> createState() => _CareBinderScreenState();
}

class _CareBinderScreenState extends State<CareBinderScreen> {
  late final GrowingCareStores _s = widget.stores ?? GrowingCareStores.forChild();
  late final DateTime Function() _now = widget.now ?? DateTime.now;
  final IdMaker _ids = IdMaker();
  List<CareSection> _sections = <CareSection>[];
  List<CareContact> _contacts = <CareContact>[];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final List<CareSection> s = await _s.sections.list();
    final List<CareContact> c = await _s.contacts.list();
    if (mounted) setState(() { _sections = s; _contacts = c; _loaded = true; });
  }

  Future<void> _editSection({CareSection? existing, String? kind}) async {
    final bool? saved = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => _SectionDialog(
          stores: _s, existing: existing, kind: existing?.kind ?? kind!, now: _now, ids: _ids),
    );
    if (saved == true) await _load();
  }

  Future<void> _addSection() async {
    final String? kind = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => SimpleDialog(title: const Text('What kind of section?'), children: <Widget>[
        for (final String k in careSectionKinds)
          SimpleDialogOption(key: ValueKey<String>('addKind_$k'), onPressed: () => Navigator.of(ctx).pop(k),
              child: Text(careSectionLabels[k]!)),
      ]),
    );
    if (kind != null) await _editSection(kind: kind);
  }

  Future<void> _removeSection(CareSection s) async {
    if (!await confirmPutAway(context, 'Remove "${s.title}"?')) return;
    await _s.sections.remove(s.id);
    await _load();
  }

  Future<void> _addContact() async {
    final bool? saved = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => _ContactDialog(stores: _s, ids: _ids),
    );
    if (saved == true) await _load();
  }

  Future<void> _removeContact(CareContact c) async {
    if (!await confirmPutAway(context, 'Remove ${c.name}?')) return;
    await _s.contacts.remove(c.id);
    await _load();
  }

  void _print() => Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => BinderPrintScreen(text: binderAsText(widget.childName, _sections, _contacts))));

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Care binder'), actions: <Widget>[
          IconButton(key: const Key('printView'), tooltip: 'Print view', icon: const Icon(Icons.print_outlined), onPressed: _loaded ? _print : null),
        ]),
        body: SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: <Widget>[
          const LocalOnlyBanner('$localOnlyNote Written by a guardian. The app adds no medical content, and '
              "this is never on her device."),
          const SizedBox(height: 8),
          if (_loaded && _sections.isEmpty)
            const Padding(padding: EdgeInsets.all(16), child: Text('Nothing written yet. Add a section and write it in your own words.', key: Key('binderEmpty'))),
          for (final CareSection s in _sections) Card(
              key: ValueKey<String>('section-${s.id}'),
              child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Text(s.title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(s.body.trim().isEmpty ? '(nothing written yet)' : s.body),
                Wrap(spacing: 8, children: <Widget>[
                  TextButton(key: ValueKey<String>('editSection-${s.id}'), onPressed: () => _editSection(existing: s), child: const Text('Edit')),
                  TextButton(key: ValueKey<String>('removeSection-${s.id}'), onPressed: () => _removeSection(s), child: const Text('Remove')),
                ]),
              ]))),
          OutlinedButton.icon(key: const Key('addSection'), onPressed: _addSection, icon: const Icon(Icons.add), label: const Text('Add a section')),
          const Divider(height: 32),
          Text('Contacts', style: Theme.of(context).textTheme.titleMedium),
          for (final CareContact c in _contacts) ListTile(
              key: ValueKey<String>('contact-${c.id}'), contentPadding: EdgeInsets.zero,
              title: Text(c.name), subtitle: Text(<String>[if (c.relation.isNotEmpty) c.relation, if (c.phone.isNotEmpty) c.phone].join(' - ')),
              trailing: IconButton(key: ValueKey<String>('removeContact-${c.id}'), tooltip: 'Remove', icon: const Icon(Icons.delete_outline), onPressed: () => _removeContact(c))),
          OutlinedButton.icon(key: const Key('addContact'), onPressed: _addContact, icon: const Icon(Icons.person_add_alt_outlined), label: const Text('Add a contact')),
        ])),
      );
}

/// The section editor. A widget of its own so its text controllers live exactly
/// as long as the dialog does (disposing them in the caller races the closing
/// animation).
class _SectionDialog extends StatefulWidget {
  const _SectionDialog({required this.stores, required this.existing, required this.kind, required this.now, required this.ids});
  final GrowingCareStores stores;
  final CareSection? existing;
  final String kind;
  final DateTime Function() now;
  final IdMaker ids;

  @override
  State<_SectionDialog> createState() => _SectionDialogState();
}

class _SectionDialogState extends State<_SectionDialog> {
  late final TextEditingController _title = TextEditingController(text: widget.existing?.title ?? careSectionLabels[widget.kind]);
  late final TextEditingController _body = TextEditingController(text: widget.existing?.body ?? '');
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    try {
      await widget.stores.sections.save(CareSection(
          id: widget.existing?.id ?? widget.ids.next('s'), kind: widget.kind, title: _title.text.trim(),
          body: _body.text, updatedOn: isoOf(widget.now())));
      if (mounted) Navigator.of(context).pop(true);
    } on CareRefused catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.existing == null ? 'New section' : 'Edit section'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          TextField(key: const Key('sectionTitle'), controller: _title, maxLength: maxTitleChars,
              decoration: const InputDecoration(labelText: 'Title')),
          TextField(key: const Key('sectionBody'), controller: _body, maxLines: 8, maxLength: maxSectionChars,
              decoration: const InputDecoration(labelText: 'Write it in your own words', alignLabelWithHint: true)),
          if (_error != null) Text(_error!, key: const Key('formError'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ])),
        actions: <Widget>[
          TextButton(key: const Key('sectionCancel'), onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(key: const Key('sectionSave'), onPressed: _save, child: const Text('Save')),
        ],
      );
}

class _ContactDialog extends StatefulWidget {
  const _ContactDialog({required this.stores, required this.ids});
  final GrowingCareStores stores;
  final IdMaker ids;

  @override
  State<_ContactDialog> createState() => _ContactDialogState();
}

class _ContactDialogState extends State<_ContactDialog> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _rel = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _rel.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    try {
      await widget.stores.contacts.save(CareContact(
          id: widget.ids.next('p'), name: _name.text.trim(), relation: _rel.text.trim(), phone: _phone.text.trim()));
      if (mounted) Navigator.of(context).pop(true);
    } on CareRefused catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('New contact'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          TextField(key: const Key('contactName'), controller: _name, decoration: const InputDecoration(labelText: 'Name')),
          TextField(key: const Key('contactRelation'), controller: _rel, decoration: const InputDecoration(labelText: 'Who they are (optional)')),
          TextField(key: const Key('contactPhone'), controller: _phone, keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone (optional)')),
          if (_error != null) Text(_error!, key: const Key('formError'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ])),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(key: const Key('contactSave'), onPressed: _save, child: const Text('Save')),
        ],
      );
}

/// The binder as one plain page, for reading over or copying out.
class BinderPrintScreen extends StatelessWidget {
  const BinderPrintScreen({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Print view')),
        body: SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: <Widget>[
          Container(
            key: const Key('printSheet'), padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.black26)),
            child: SelectableText(text, style: const TextStyle(color: Colors.black87, height: 1.4)),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('copyBinder'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            icon: const Icon(Icons.copy_outlined), label: const Text('Copy this text'),
            onPressed: () async {
              final ScaffoldMessengerState m = ScaffoldMessenger.of(context);
              await Clipboard.setData(ClipboardData(text: text));
              m.showSnackBar(const SnackBar(content: Text('Copied to this phone\'s clipboard.')));
            },
          ),
        ])),
      );
}

// ============================================================== hospital mode ==
class HospitalModeScreen extends StatefulWidget {
  const HospitalModeScreen({
    super.key, this.childName = 'Ivy', this.stores, this.openEmergencyCard, this.emergency, this.principal,
  });
  final String childName;
  final GrowingCareStores? stores;

  /// The local emergency card a guardian wrote (read with [principal]); null reads none.
  final EmergencyCardService? emergency;
  final FamilyPrincipal? principal;

  /// Overridable so a test need not build the whole emergency card.
  final void Function(BuildContext context)? openEmergencyCard;

  @override
  State<HospitalModeScreen> createState() => _HospitalModeScreenState();
}

class _HospitalModeScreenState extends State<HospitalModeScreen> {
  late final GrowingCareStores _s = widget.stores ?? GrowingCareStores.forChild();
  HospitalSummary? _summary;
  EmergencyCardDoc? _local;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final HospitalSummary sum = hospitalSummary(
        await _s.sections.list(), await _s.contacts.list(), await _s.hospital.get(HospitalNotes.itemId));
    EmergencyCardDoc? local;
    if (widget.emergency != null) {
      try {
        final EmergencyCardDoc d = await widget.emergency!.read(widget.principal);
        if (d.card != null && !d.card!.isEmpty) local = d;
      } catch (_) {
        local = null; // not a guardian, or unreadable: no local card is shown
      }
    }
    if (mounted) setState(() { _summary = sum; _local = local; });
  }

  Future<void> _editCard() async {
    final bool? saved = await Navigator.of(context).push<bool>(MaterialPageRoute<bool>(
        builder: (_) => EmergencyCardEditorScreen(
            service: widget.emergency!, principal: widget.principal, childName: widget.childName)));
    if (saved == true) await _load();
  }

  Future<void> _edit() async {
    final bool? saved = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(builder: (_) => _HospitalNotesForm(stores: _s, current: _summary?.notes ?? const HospitalNotes())));
    if (saved == true) await _load();
  }

  void _card() {
    final void Function(BuildContext)? o = widget.openEmergencyCard;
    if (o != null) {
      o(context);
      return;
    }
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => EmergencyCardScreen(
        childName: widget.childName, localService: widget.emergency, principal: widget.principal)));
  }

  Widget _block(BuildContext context, String title, String text, {Key? key}) => Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Column(key: key, crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(text, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w500, height: 1.35)),
        ]),
      );

  /// The guardian's local emergency card, in the words they wrote, allergies first.
  List<Widget> _localCardBlocks(BuildContext context, LocalEmergencyCard c) => <Widget>[
        if (c.allergies.isNotEmpty)
          _block(context, 'Allergies (emergency card)', c.allergies.join('\n'), key: const Key('hospCardAllergies')),
        if (c.conditions.isNotEmpty)
          _block(context, 'Conditions', c.conditions.join('\n'), key: const Key('hospCardConditions')),
        if (c.medicines.isNotEmpty)
          _block(context, 'Medicines',
              c.medicines.map((EcMedicine m) => m.dose.isEmpty ? m.name : '${m.name}  -  ${m.dose}').join('\n'),
              key: const Key('hospCardMedicines')),
        if (!c.doctor.isEmpty)
          _block(context, 'Her doctor',
              <String>[
                if (c.doctor.name.isNotEmpty) c.doctor.name,
                if (c.doctor.practice.isNotEmpty) c.doctor.practice,
                if (c.doctor.phone.isNotEmpty) c.doctor.phone,
              ].join('  -  '),
              key: const Key('hospCardDoctor')),
        if (c.contacts.isNotEmpty)
          _block(context, 'Emergency card contacts',
              c.contacts.map((EcContact x) => <String>[
                    x.name, if (x.relation.isNotEmpty) x.relation, if (x.phone.isNotEmpty) x.phone,
                  ].join('  -  ')).join('\n'),
              key: const Key('hospCardContacts')),
      ];

  @override
  Widget build(BuildContext context) {
    final HospitalSummary? s = _summary;
    return Scaffold(
      appBar: AppBar(title: const Text('Hospital mode'), actions: <Widget>[
        if (widget.emergency != null)
          IconButton(key: const Key('editEmergencyCard'), tooltip: 'Write the emergency card', icon: const Icon(Icons.medical_information_outlined),
              onPressed: s == null ? null : _editCard),
        IconButton(key: const Key('editHospital'), tooltip: 'Write notes', icon: const Icon(Icons.edit_outlined), onPressed: s == null ? null : _edit),
      ]),
      body: SafeArea(child: s == null ? const SizedBox.shrink() : ListView(padding: const EdgeInsets.all(20), children: <Widget>[
        FilledButton.icon(
            key: const Key('openEmergencyCard'), onPressed: _card,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(72)),
            icon: const Icon(Icons.medical_information_outlined, size: 30),
            label: Text("${widget.childName}'s emergency card", style: const TextStyle(fontSize: 20))),
        const SizedBox(height: 20),
        if (!s.hasAnything && _local == null)
          const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text(
              'Nothing written yet. Tap the pencil to write what you would want at hand. '
              'Allergies and contacts come from your care binder.', key: Key('hospitalEmpty'))),
        if (s.notes.happeningToday.trim().isNotEmpty) _block(context, 'Happening today', s.notes.happeningToday, key: const Key('hospToday')),
        if (_local != null) ..._localCardBlocks(context, _local!.card!),
        for (final CareSection a in s.allergies) _block(context, a.title, a.body, key: ValueKey<String>('hospAllergy-${a.id}')),
        if (s.notes.staffShouldKnow.trim().isNotEmpty) _block(context, 'Staff should know', s.notes.staffShouldKnow, key: const Key('hospStaff')),
        if (s.notes.whatHelpsHer.trim().isNotEmpty) _block(context, 'What helps her', s.notes.whatHelpsHer, key: const Key('hospHelps')),
        if (s.notes.toBring.trim().isNotEmpty) _block(context, 'To bring', s.notes.toBring, key: const Key('hospBring')),
        if (s.contacts.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 18), child: Column(
            key: const Key('hospContacts'), crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text('Who to call', style: Theme.of(context).textTheme.titleMedium),
          for (final CareContact c in s.contacts) Padding(padding: const EdgeInsets.only(top: 6), child: Text(
              <String>[c.name, if (c.relation.isNotEmpty) c.relation, if (c.phone.isNotEmpty) c.phone].join('  -  '),
              style: Theme.of(context).textTheme.titleLarge)),
        ])),
        Text('$localOnlyNote Written by a guardian.', style: Theme.of(context).textTheme.bodySmall),
      ])),
    );
  }
}

class _HospitalNotesForm extends StatefulWidget {
  const _HospitalNotesForm({required this.stores, required this.current});
  final GrowingCareStores stores;
  final HospitalNotes current;

  @override
  State<_HospitalNotesForm> createState() => _HospitalNotesFormState();
}

class _HospitalNotesFormState extends State<_HospitalNotesForm> {
  late final TextEditingController _today = TextEditingController(text: widget.current.happeningToday);
  late final TextEditingController _bring = TextEditingController(text: widget.current.toBring);
  late final TextEditingController _helps = TextEditingController(text: widget.current.whatHelpsHer);
  late final TextEditingController _staff = TextEditingController(text: widget.current.staffShouldKnow);
  String? _error;

  @override
  void dispose() {
    _today.dispose();
    _bring.dispose();
    _helps.dispose();
    _staff.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    try {
      await widget.stores.hospital.save(HospitalNotes(
          happeningToday: _today.text, toBring: _bring.text, whatHelpsHer: _helps.text, staffShouldKnow: _staff.text));
      if (mounted) Navigator.of(context).pop(true);
    } on CareRefused catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Widget _field(Key k, TextEditingController c, String label) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(key: k, controller: c, maxLines: 4, maxLength: maxHospitalFieldChars,
          decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), alignLabelWithHint: true)));

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Write notes')),
        body: SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: <Widget>[
          const LocalOnlyBanner('Your words only. The app adds nothing. $localOnlyNote'),
          const SizedBox(height: 12),
          _field(const Key('fieldToday'), _today, 'Happening today'),
          _field(const Key('fieldStaff'), _staff, 'Staff should know'),
          _field(const Key('fieldHelps'), _helps, 'What helps her'),
          _field(const Key('fieldBring'), _bring, 'To bring'),
          if (_error != null) Text(_error!, key: const Key('formError'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
          FilledButton(key: const Key('saveHospital'), onPressed: _save,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)), child: const Text('Keep these')),
        ])),
      );
}

// ============================================================= explainer cards ==
class ExplainerAuthoringScreen extends StatefulWidget {
  const ExplainerAuthoringScreen({super.key, this.childName = 'Ivy', this.stores, this.now, this.photoSource});
  final String childName;
  final GrowingCareStores? stores;
  final DateTime Function()? now;
  final PhotoSource? photoSource;

  @override
  State<ExplainerAuthoringScreen> createState() => _ExplainerAuthoringScreenState();
}

class _ExplainerAuthoringScreenState extends State<ExplainerAuthoringScreen> {
  late final GrowingCareStores _s = widget.stores ?? GrowingCareStores.forChild();
  late final DateTime Function() _now = widget.now ?? DateTime.now;
  final IdMaker _ids = IdMaker();
  List<ExplainerStory> _all = <ExplainerStory>[];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final List<ExplainerStory> all = await _s.stories.list();
    all.sort((ExplainerStory a, ExplainerStory b) => a.title.compareTo(b.title));
    if (mounted) setState(() { _all = all; _loaded = true; });
  }

  Future<void> _edit([ExplainerStory? existing]) async {
    final bool? saved = await Navigator.of(context).push<bool>(MaterialPageRoute<bool>(
        builder: (_) => _StoryForm(
            stores: _s, existing: existing, now: _now, ids: _ids, photoSource: widget.photoSource ?? pickSmallPhoto)));
    if (saved == true) await _load();
  }

  Future<void> _toggle(ExplainerStory s, bool v) async {
    try {
      await _s.stories.save(ExplainerStory(
          id: s.id, title: s.title, pages: s.pages, updatedOn: s.updatedOn, shownToHer: v, thumb: s.thumb));
    } on CareRefused catch (e) {
      if (mounted) showRefusal(context, e);
    }
    await _load();
  }

  Future<void> _remove(ExplainerStory s) async {
    if (!await confirmPutAway(context, 'Remove "${s.title}"?')) return;
    await _s.stories.remove(s.id);
    await _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Picture stories')),
        body: SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: <Widget>[
          LocalOnlyBanner('$localOnlyNote You write every word. The app writes none and adds no advice. '
              '${widget.childName} sees a story only when you turn on "Show her".'),
          const SizedBox(height: 8),
          if (_loaded && _all.isEmpty)
            const Padding(padding: EdgeInsets.all(16), child: Text('No stories yet. Write one in your own words.', key: Key('storiesEmpty'))),
          for (final ExplainerStory s in _all) Card(
              key: ValueKey<String>('story-${s.id}'),
              child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Row(children: <Widget>[
                  if (s.thumb != null) ...<Widget>[ThumbImage(s.thumb!, size: 56), const SizedBox(width: 10)],
                  Expanded(child: Text(s.title, style: Theme.of(context).textTheme.titleMedium)),
                ]),
                SwitchListTile(
                    key: ValueKey<String>('showStory-${s.id}'), contentPadding: EdgeInsets.zero,
                    title: const Text('Show her'), value: s.shownToHer, onChanged: (bool v) => _toggle(s, v)),
                Wrap(spacing: 8, children: <Widget>[
                  TextButton(key: ValueKey<String>('previewStory-${s.id}'), child: const Text('Read it as she would'),
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ExplainerPagerScreen(story: s)))),
                  TextButton(key: ValueKey<String>('editStory-${s.id}'), onPressed: () => _edit(s), child: const Text('Edit')),
                  TextButton(key: ValueKey<String>('removeStory-${s.id}'), onPressed: () => _remove(s), child: const Text('Remove')),
                ]),
              ]))),
          const SizedBox(height: 8),
          FilledButton.icon(key: const Key('addStory'), onPressed: () => _edit(),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              icon: const Icon(Icons.add), label: const Text('Write a story')),
        ])),
      );
}

class _StoryForm extends StatefulWidget {
  const _StoryForm({required this.stores, required this.existing, required this.now, required this.ids, required this.photoSource});
  final GrowingCareStores stores;
  final ExplainerStory? existing;
  final DateTime Function() now;
  final IdMaker ids;
  final PhotoSource photoSource;

  @override
  State<_StoryForm> createState() => _StoryFormState();
}

class _StoryFormState extends State<_StoryForm> {
  late final TextEditingController _title = TextEditingController(text: widget.existing?.title ?? '');
  late final List<TextEditingController> _pages = <TextEditingController>[
    for (final String p in widget.existing?.pages ?? const <String>['']) TextEditingController(text: p),
  ];
  late bool _show = widget.existing?.shownToHer ?? false;
  late Uint8List? _thumb = widget.existing?.thumb;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    for (final TextEditingController c in _pages) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pick() async {
    final Uint8List? b = await widget.photoSource();
    if (b == null || !mounted) return;
    final String? why = thumbRefusal(b);
    setState(() { if (why != null) { _error = refusalMessage(why); } else { _thumb = b; _error = null; } });
  }

  Future<void> _save() async {
    try {
      await widget.stores.stories.save(ExplainerStory(
          id: widget.existing?.id ?? widget.ids.next('e'), title: _title.text.trim(),
          pages: <String>[for (final TextEditingController c in _pages) c.text.trim()],
          updatedOn: isoOf(widget.now()), shownToHer: _show, thumb: _thumb));
      if (mounted) Navigator.of(context).pop(true);
    } on CareRefused catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.existing == null ? 'Write a story' : 'Edit story')),
        body: SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: <Widget>[
          TextField(key: const Key('storyTitle'), controller: _title, maxLength: maxTitleChars,
              decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          for (int i = 0; i < _pages.length; i++) Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(
              crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Expanded(child: TextField(key: ValueKey<String>('storyPage-$i'), controller: _pages[i], maxLines: 3, maxLength: maxStoryPageChars,
                decoration: InputDecoration(labelText: 'Page ${i + 1}', border: const OutlineInputBorder()))),
            if (_pages.length > 1) IconButton(key: ValueKey<String>('removePage-$i'), tooltip: 'Remove page', icon: const Icon(Icons.close),
                onPressed: () => setState(() => _pages.removeAt(i).dispose())),
          ])),
          if (_pages.length < maxStoryPages)
            Align(alignment: Alignment.centerLeft, child: TextButton.icon(
                key: const Key('addPage'), onPressed: () => setState(() => _pages.add(TextEditingController())),
                icon: const Icon(Icons.add), label: const Text('Add a page'))),
          PhotoPickerRow(bytes: _thumb, onPick: _pick, onClear: () => setState(() => _thumb = null), label: 'Add a picture'),
          SwitchListTile(key: const Key('storyShow'), contentPadding: EdgeInsets.zero,
              title: const Text('Show her'), value: _show, onChanged: (bool v) => setState(() => _show = v)),
          if (_error != null) Text(_error!, key: const Key('formError'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
          const SizedBox(height: 8),
          FilledButton(key: const Key('saveStory'), onPressed: _save,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)), child: const Text('Keep it')),
        ])),
      );
}

// ============================================================ appointment prep ==
class AppointmentPrepScreen extends StatefulWidget {
  const AppointmentPrepScreen({super.key, this.childName = 'Ivy', this.stores, this.now});
  final String childName;
  final GrowingCareStores? stores;
  final DateTime Function()? now;

  @override
  State<AppointmentPrepScreen> createState() => _AppointmentPrepScreenState();
}

class _AppointmentPrepScreenState extends State<AppointmentPrepScreen> {
  late final GrowingCareStores _s = widget.stores ?? GrowingCareStores.forChild();
  late final DateTime Function() _now = widget.now ?? DateTime.now;
  final IdMaker _ids = IdMaker();
  List<AppointmentPrep> _all = <AppointmentPrep>[];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final List<AppointmentPrep> all = await _s.preps.list();
    all.sort((AppointmentPrep a, AppointmentPrep b) => b.createdOn.compareTo(a.createdOn));
    if (mounted) setState(() { _all = all; _loaded = true; });
  }

  Future<void> _edit([AppointmentPrep? existing]) async {
    final bool? saved = await Navigator.of(context).push<bool>(MaterialPageRoute<bool>(
        builder: (_) => _PrepForm(stores: _s, existing: existing, now: _now, ids: _ids)));
    if (saved == true) await _load();
  }

  Future<void> _remove(AppointmentPrep p) async {
    if (!await confirmPutAway(context, 'Remove "${p.title}"?')) return;
    await _s.preps.remove(p.id);
    await _load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Appointment prep')),
        body: SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: <Widget>[
          const LocalOnlyBanner('$localOnlyNote Your checklist and questions, in your words. '
              'This sets no reminder and sends nothing.'),
          const SizedBox(height: 8),
          if (_loaded && _all.isEmpty)
            const Padding(padding: EdgeInsets.all(16), child: Text('Nothing here yet. Start a list for the next visit.', key: Key('prepEmpty'))),
          for (final AppointmentPrep p in _all) Card(
              key: ValueKey<String>('prep-${p.id}'),
              child: ListTile(
                title: Text(p.title), subtitle: p.on == null ? null : Text(dayMonthYear(p.on!)),
                onTap: () => _edit(p),
                trailing: IconButton(key: ValueKey<String>('removePrep-${p.id}'), tooltip: 'Remove', icon: const Icon(Icons.delete_outline), onPressed: () => _remove(p)),
              )),
          const SizedBox(height: 8),
          FilledButton.icon(key: const Key('addPrep'), onPressed: () => _edit(),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              icon: const Icon(Icons.add), label: const Text('Start a list')),
        ])),
      );
}

class _PrepForm extends StatefulWidget {
  const _PrepForm({required this.stores, required this.existing, required this.now, required this.ids});
  final GrowingCareStores stores;
  final AppointmentPrep? existing;
  final DateTime Function() now;
  final IdMaker ids;

  @override
  State<_PrepForm> createState() => _PrepFormState();
}

class _PrepFormState extends State<_PrepForm> {
  late final TextEditingController _title = TextEditingController(text: widget.existing?.title ?? '');
  late final TextEditingController _on = TextEditingController(text: widget.existing?.on ?? '');
  final TextEditingController _newItem = TextEditingController();
  final TextEditingController _newQuestion = TextEditingController();
  late final List<PrepLine> _items = List<PrepLine>.of(widget.existing?.checklist ?? const <PrepLine>[]);
  late final List<String> _questions = List<String>.of(widget.existing?.questions ?? const <String>[]);
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _on.dispose();
    _newItem.dispose();
    _newQuestion.dispose();
    super.dispose();
  }

  void _addItem() {
    final String t = _newItem.text.trim();
    if (t.isEmpty) return;
    setState(() { _items.add(PrepLine(t)); _newItem.clear(); });
  }

  void _addQuestion() {
    final String t = _newQuestion.text.trim();
    if (t.isEmpty) return;
    setState(() { _questions.add(t); _newQuestion.clear(); });
  }

  Future<void> _save() async {
    _addItem();
    _addQuestion();
    final String on = _on.text.trim();
    try {
      await widget.stores.preps.save(AppointmentPrep(
          id: widget.existing?.id ?? widget.ids.next('a'), title: _title.text.trim(),
          createdOn: widget.existing?.createdOn ?? isoOf(widget.now()), on: on.isEmpty ? null : on,
          checklist: _items, questions: _questions));
      if (mounted) Navigator.of(context).pop(true);
    } on CareRefused catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Appointment prep')),
        body: SafeArea(child: ListView(padding: const EdgeInsets.all(16), children: <Widget>[
          TextField(key: const Key('prepTitle'), controller: _title, maxLength: maxTitleChars,
              decoration: const InputDecoration(labelText: 'What is the visit?', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          IsoDateField(key: const Key('prepDate'), controller: _on, label: 'Date (optional)', today: isoOf(widget.now())),
          const SizedBox(height: 16),
          Text('To bring or do', style: Theme.of(context).textTheme.titleMedium),
          for (int i = 0; i < _items.length; i++) CheckboxListTile(
              key: ValueKey<String>('item-$i'), contentPadding: EdgeInsets.zero, controlAffinity: ListTileControlAffinity.leading,
              title: Text(_items[i].text), value: _items[i].done,
              secondary: IconButton(key: ValueKey<String>('removeItem-$i'), tooltip: 'Remove', icon: const Icon(Icons.close), onPressed: () => setState(() => _items.removeAt(i))),
              onChanged: (bool? v) => setState(() => _items[i] = PrepLine(_items[i].text, done: v ?? false))),
          Row(children: <Widget>[
            Expanded(child: TextField(key: const Key('newItem'), controller: _newItem, maxLength: maxPrepLineChars, onSubmitted: (_) => _addItem(),
                decoration: const InputDecoration(labelText: 'Add to the list', counterText: ''))),
            IconButton(key: const Key('addItem'), tooltip: 'Add', icon: const Icon(Icons.add_circle_outline), onPressed: _addItem),
          ]),
          const SizedBox(height: 16),
          Text('My questions', style: Theme.of(context).textTheme.titleMedium),
          for (int i = 0; i < _questions.length; i++) ListTile(
              key: ValueKey<String>('question-$i'), contentPadding: EdgeInsets.zero, title: Text(_questions[i]),
              trailing: IconButton(key: ValueKey<String>('removeQuestion-$i'), tooltip: 'Remove', icon: const Icon(Icons.close), onPressed: () => setState(() => _questions.removeAt(i)))),
          Row(children: <Widget>[
            Expanded(child: TextField(key: const Key('newQuestion'), controller: _newQuestion, maxLength: maxPrepLineChars, onSubmitted: (_) => _addQuestion(),
                decoration: const InputDecoration(labelText: 'Write a question', counterText: ''))),
            IconButton(key: const Key('addQuestion'), tooltip: 'Add', icon: const Icon(Icons.add_circle_outline), onPressed: _addQuestion),
          ]),
          if (_error != null) Text(_error!, key: const Key('formError'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
          const SizedBox(height: 12),
          FilledButton(key: const Key('savePrep'), onPressed: _save,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)), child: const Text('Keep this list')),
        ])),
      );
}
