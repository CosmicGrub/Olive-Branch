// OLIVE BRANCH — the care and coordination screens, on THIS device: the hub, medicines,
// shared expenses, the handover log, her time and your time, and the honest "later" card for
// swapping a night. No longer UNVERIFIED — verified by CI (client/test/care_local_screens_test.dart).
// MASTERFILE section 8.24.7. Reference: the live prototype's g-care, g-meds, g-med, g-handover,
// g-expenses, g-overlap and g-swap.
//
// WHAT IS REAL HERE. Everything is read from and written to [CareService], the sealed on-device
// record (care_local.dart), by a grown-up. The rules (one dose per slot, the expense transitions,
// the hash chain) live in that file; these screens only ask and show the answer.
//
// WHAT IS NOT, AND SAYS SO. Two grown-ups answering each other's expenses, one shared log, and
// swapping a night all need a connected family, which is parked. Where a screen would need that it
// shows a plain "later" card and saves nothing. Nothing here pretends to be sent.
//
// WORDS. Plain for an adult. The text of a medicine, an expense or a note is whatever the guardian
// typed; the app adds none. None of this is ever shown in her app (P6), and no screen here
// says anything to a child: a non-guardian principal gets one neutral line and nothing is read.
import 'dart:async';

import 'package:flutter/material.dart';

import 'calendar_day_logic.dart' show formatTimeOfDay;
import 'care_local.dart';
import 'family_structure_logic.dart' show FamilyPrincipal, canEditStructure;
import 'guardian_local_scope.dart' show GuardianLocalController, GuardianLocalScope;
import 'hub_widgets.dart';

// ----------------------------------------------------------------- helpers ---
String careTime(DateTime t) =>
    formatTimeOfDay('${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}');

const List<String> _months = <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
String careDay(DateTime t) => '${_months[t.month - 1]} ${t.day}';

String _who(String byId, String byName, String me) => byId == me ? 'you' : byName;

/// The neutral line anyone who is not a grown-up gets. No figure, no name, no record.
class CareNotForYou extends StatelessWidget {
  const CareNotForYou({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(),
    body: const SafeArea(
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text("There's nothing on this screen for you.", key: Key('careNotForYou')),
        ),
      ),
    ),
  );
}

Widget _banner(BuildContext context, String text, {Key? key, IconData icon = Icons.info_outline, bool warn = false}) {
  final ColorScheme c = Theme.of(context).colorScheme;
  return Container(
    key: key,
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: warn ? c.tertiaryContainer : c.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(icon, size: 18, color: warn ? c.onTertiaryContainer : c.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: warn ? c.onTertiaryContainer : c.onSurfaceVariant),
          ),
        ),
      ],
    ),
  );
}

Widget _section(BuildContext context, String t) => Padding(
  padding: const EdgeInsets.only(top: 16, bottom: 6),
  child: Text(
    t.toUpperCase(),
    style: Theme.of(context).textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: 0.5,
      color: Theme.of(context).colorScheme.primary,
    ),
  ),
);

Widget _chip(BuildContext context, String t, {bool good = false, bool bad = false, bool warn = false}) {
  final ColorScheme c = Theme.of(context).colorScheme;
  final Color bg = bad
      ? c.errorContainer
      : warn
      ? c.tertiaryContainer
      : good
      ? c.primaryContainer
      : c.secondaryContainer;
  final Color fg = bad
      ? c.onErrorContainer
      : warn
      ? c.onTertiaryContainer
      : good
      ? c.onPrimaryContainer
      : c.onSecondaryContainer;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
    child: Text(
      t,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(color: fg, fontWeight: FontWeight.w700),
    ),
  );
}

void _snack(BuildContext context, String t) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t), duration: const Duration(seconds: 3)));

/// Loads the document once and again after each change. Subclasses draw [doc].
mixin _CareLoad<T extends StatefulWidget> on State<T> {
  CareDoc? doc;
  bool refused = false;
  CareService get careService;
  FamilyPrincipal? get careWho;

  String get me => (careWho?.userId as String?) ?? '';

  Future<void> reload() async {
    if (!canEditStructure(careWho)) {
      if (mounted) setState(() => refused = true);
      return;
    }
    try {
      final CareDoc d = await careService.read(careWho);
      if (mounted) setState(() => doc = d);
    } on CareLocalRefused {
      if (mounted) setState(() => refused = true);
    }
  }
}

// ================================================================ the hub ===
/// Where each part of the hub that lives in another file opens. A null builder shows its row as "later".
class CareHubLinks {
  const CareHubLinks({this.emergencyCard, this.hospital, this.exchange, this.binder, this.appointments, this.schedule});
  final WidgetBuilder? emergencyCard, hospital, exchange, binder, appointments, schedule;
}

class CareHubScreen extends StatefulWidget {
  const CareHubScreen({
    super.key,
    required this.service,
    required this.principal,
    this.childName = 'her',
    this.byName,
    this.links = const CareHubLinks(),
    this.emergencyVersion,
    this.clock,
    this.guardianCount = 1,
  });
  final CareService service;
  final FamilyPrincipal? principal;
  final String childName;
  final String? byName;
  final CareHubLinks links;

  /// Version of the on-device emergency card, shown on its row; null shows no version.
  final Future<int> Function()? emergencyVersion;
  final DateTime Function()? clock;
  final int guardianCount;

  @override
  State<CareHubScreen> createState() => _CareHubState();
}

class _CareHubState extends State<CareHubScreen> with _CareLoad<CareHubScreen> {
  int? _cardVersion;
  @override
  CareService get careService => widget.service;
  @override
  FamilyPrincipal? get careWho => widget.principal;

  @override
  void initState() {
    super.initState();
    unawaited(reload());
    widget.emergencyVersion
        ?.call()
        .then((int v) {
          if (mounted) setState(() => _cardVersion = v);
        })
        .catchError((Object _) {});
  }

  Future<void> _go(Widget w) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => w));
    await reload();
  }

  void _open(WidgetBuilder? b, String later) {
    if (b == null) {
      _snack(context, later);
      return;
    }
    unawaited(_go(Builder(builder: b)));
  }

  @override
  Widget build(BuildContext context) {
    if (refused || !canEditStructure(widget.principal)) return const CareNotForYou();
    final DateTime now = (widget.clock ?? DateTime.now)();
    final CareDoc? d = doc;
    final int due = d == null
        ? 0
        : d.meds.where((CareMedication m) => !m.retired && m.kind == MedKind.scheduled && medState(m, now).due).length;
    final int waiting = d == null
        ? 0
        : d.expenses
              .where(
                (CareExpense e) =>
                    (e.status == ExpenseStatus.proposed) && (e.paidById != me || widget.guardianCount == 1),
              )
              .length;
    final int notes = d?.notes.length ?? 0;
    return Scaffold(
      appBar: AppBar(title: const Text('Care and coordination')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _banner(
                context,
                "Records for the grown-ups. Nothing here is ever shown on ${widget.childName}'s device. "
                'Kept on this device only until it is connected.',
                key: const Key('careHubBanner'),
                icon: Icons.shield_outlined,
              ),
              HubTile(
                key: const Key('careRowCard'),
                icon: Icons.medical_information_outlined,
                title: 'Emergency card',
                subtitle: _cardVersion == null || _cardVersion == 0
                    ? 'Shown on your screen only'
                    : 'Version $_cardVersion. Shown on your screen only',
                onTap: () => _open(widget.links.emergencyCard, 'The emergency card is not available here.'),
              ),
              HubTile(
                key: const Key('careRowHospital'),
                icon: Icons.local_hospital_outlined,
                title: 'Hospital mode',
                subtitle: 'Large, plain text for a doctor',
                onTap: () => _open(widget.links.hospital, 'Hospital mode is not available here.'),
              ),
              HubTile(
                key: const Key('careRowMeds'),
                icon: Icons.medication_outlined,
                title: 'Medications',
                subtitle: due > 0 ? '$due due now' : 'Dose log and double-dose guard',
                trailing: due > 0 ? _chip(context, '$due due', warn: true) : null,
                onTap: () => _go(
                  LocalMedsScreen(
                    service: widget.service,
                    principal: widget.principal,
                    byName: widget.byName,
                    childName: widget.childName,
                    clock: widget.clock,
                  ),
                ),
              ),
              HubTile(
                key: const Key('careRowBag'),
                icon: Icons.luggage_outlined,
                title: 'Exchange bag',
                subtitle: 'What travels between homes',
                onTap: () => _open(widget.links.exchange, 'The exchange bag is not available here.'),
              ),
              HubTile(
                key: const Key('careRowBinder'),
                icon: Icons.menu_book_outlined,
                title: 'Care binder',
                subtitle: 'Pages for you and a sitter',
                onTap: () => _open(widget.links.binder, 'The care binder is not available here.'),
              ),
              HubTile(
                key: const Key('careRowAppt'),
                icon: Icons.event_note_outlined,
                title: 'Appointment prep',
                subtitle: 'Questions and things to bring',
                onTap: () => _open(widget.links.appointments, 'Appointment prep is not available here.'),
              ),
              const SizedBox(height: 8),
              HubTile(
                key: const Key('careRowHandover'),
                icon: Icons.mail_outline,
                title: 'Handover notes',
                subtitle: notes > 0 ? '$notes in the log. Never deletable' : 'Append-only, never deletable',
                onTap: () => _go(
                  LocalHandoverScreen(
                    service: widget.service,
                    principal: widget.principal,
                    byName: widget.byName,
                    childName: widget.childName,
                  ),
                ),
              ),
              HubTile(
                key: const Key('careRowSchedule'),
                icon: Icons.calendar_month_outlined,
                title: 'Custody schedule',
                subtitle: 'Weekly rhythm and exchange days',
                onTap: () => _open(widget.links.schedule, 'The weekly rhythm is under Family in Settings.'),
              ),
              HubTile(
                key: const Key('careRowSwap'),
                icon: Icons.swap_horiz,
                title: 'Swap a night',
                subtitle: 'Needs both grown-ups connected. Later',
                onTap: () => _go(const SwapLaterScreen()),
              ),
              HubTile(
                key: const Key('careRowExpenses'),
                icon: Icons.receipt_long_outlined,
                title: 'Shared expenses',
                subtitle: waiting > 0 ? '$waiting waiting for you' : 'Propose, accept, dispute, reimburse',
                trailing: waiting > 0 ? _chip(context, '$waiting') : null,
                onTap: () => _go(
                  LocalExpensesScreen(
                    service: widget.service,
                    principal: widget.principal,
                    byName: widget.byName,
                    childName: widget.childName,
                    guardianCount: widget.guardianCount,
                  ),
                ),
              ),
              HubTile(
                key: const Key('careRowOverlap'),
                icon: Icons.schedule_outlined,
                title: 'Her time, your time',
                subtitle: 'Overlap window',
                onTap: () => _go(OverlapScreen(childName: widget.childName)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================ swap (later) ===
/// "Swap a night" needs two connected grown-ups: one asks, the other answers. Nothing is saved here.
class SwapLaterScreen extends StatelessWidget {
  const SwapLaterScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Swap a night')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          _banner(
            context,
            'Swapping a night needs the other grown-up connected: one of you asks, the other answers. '
            'That is not available yet, so nothing can be asked or saved here.',
            key: const Key('swapLaterBanner'),
            icon: Icons.schedule_outlined,
            warn: true,
          ),
          Text('How it will work', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(
            'Pick a night in the future, within a year, and optionally a night to give back. '
            'Only one request can be open for a night. The other grown-up accepts or declines; you cannot '
            'answer your own request. An accepted swap shows on the schedule.',
          ),
        ],
      ),
    ),
  );
}

// ============================================================== medicines ===
class LocalMedsScreen extends StatefulWidget {
  const LocalMedsScreen({
    super.key,
    required this.service,
    required this.principal,
    this.byName,
    this.childName = 'her',
    this.clock,
  });
  final CareService service;
  final FamilyPrincipal? principal;
  final String? byName;
  final String childName;
  final DateTime Function()? clock;

  @override
  State<LocalMedsScreen> createState() => _LocalMedsState();
}

class _LocalMedsState extends State<LocalMedsScreen> with _CareLoad<LocalMedsScreen> {
  @override
  CareService get careService => widget.service;
  @override
  FamilyPrincipal? get careWho => widget.principal;

  @override
  void initState() {
    super.initState();
    unawaited(reload());
  }

  DateTime get _now => (widget.clock ?? DateTime.now)();

  Future<void> _open(CareMedication? m) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LocalMedScreen(
          service: widget.service,
          principal: widget.principal,
          medicationId: m?.id,
          byName: widget.byName,
          clock: widget.clock,
        ),
      ),
    );
    await reload();
  }

  String _line(CareMedication m) {
    final MedState st = medState(m, _now);
    if (m.kind == MedKind.prn) {
      if (st.last == null) return 'As needed. Not given yet';
      final String by = _who(st.last!.byId, st.last!.byName, me);
      return 'Last: ${careDay(st.last!.at.toLocal())}, ${careTime(st.last!.at.toLocal())} by $by'
          '${st.given ? '. Next allowed ${careTime(st.next!)}' : '. Can be given'}';
    }
    if (st.given && st.last != null) {
      return 'Given ${careTime(st.last!.at.toLocal())} by ${_who(st.last!.byId, st.last!.byName, me)}';
    }
    if (st.due && st.slot != null) return 'Due since ${careTime(st.slot!)}';
    return st.next == null ? 'No time set' : 'Next ${careTime(st.next!)}';
  }

  @override
  Widget build(BuildContext context) {
    if (refused || !canEditStructure(widget.principal)) return const CareNotForYou();
    final CareDoc? d = doc;
    final List<CareMedication> act = <CareMedication>[
      for (final CareMedication m in d?.meds ?? const <CareMedication>[])
        if (!m.retired) m,
    ];
    final List<CareMedication> ret = <CareMedication>[
      for (final CareMedication m in d?.meds ?? const <CareMedication>[])
        if (m.retired) m,
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Medications')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _banner(
                context,
                'A record of what a guardian wrote and logged. It is not medical advice.',
                key: const Key('medsBanner'),
                icon: Icons.medication_outlined,
                warn: true,
              ),
              if (d == null)
                const SizedBox.shrink()
              else if (act.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text('No medicines. Add one to start a dose log.', key: Key('medsEmpty'))),
                )
              else
                for (final CareMedication m in act)
                  Card(
                    child: ListTile(
                      key: ValueKey<String>('med-${m.id}'),
                      title: Text(m.dose.isEmpty ? m.name : '${m.name}, ${m.dose}'),
                      subtitle: Text(_line(m)),
                      trailing: medState(m, _now).due
                          ? _chip(context, 'Due', warn: true)
                          : medState(m, _now).given
                          ? _chip(context, 'Given', good: true)
                          : const Icon(Icons.chevron_right),
                      onTap: () => _open(m),
                    ),
                  ),
              const SizedBox(height: 8),
              SizedBox(
                height: 48,
                child: FilledButton.tonalIcon(
                  key: const Key('addMedicineLocal'),
                  icon: const Icon(Icons.add),
                  label: const Text('Add a medicine'),
                  onPressed: () => _open(null),
                ),
              ),
              if (ret.isNotEmpty) ...<Widget>[
                _section(context, 'Retired'),
                for (final CareMedication m in ret)
                  Card(
                    child: ListTile(
                      key: ValueKey<String>('med-${m.id}'),
                      title: Text(m.name),
                      subtitle: Text('Retired. ${m.doses.length} dose${m.doses.length == 1 ? '' : 's'} kept'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _open(m),
                    ),
                  ),
              ],
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: Text("Times are on this phone's clock.", key: Key('medsClockNote')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A medicine: the form (new or edit), "log a dose I just gave", and the dose log. [medicationId] null is a new one.
class LocalMedScreen extends StatefulWidget {
  const LocalMedScreen({
    super.key,
    required this.service,
    required this.principal,
    this.medicationId,
    this.byName,
    this.clock,
  });
  final CareService service;
  final FamilyPrincipal? principal;
  final String? medicationId;
  final String? byName;
  final DateTime Function()? clock;

  @override
  State<LocalMedScreen> createState() => _LocalMedState();
}

class _LocalMedState extends State<LocalMedScreen> with _CareLoad<LocalMedScreen> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _dose = TextEditingController();
  final TextEditingController _t1 = TextEditingController();
  final TextEditingController _t2 = TextEditingController();
  final TextEditingController _gap = TextEditingController(text: '4');
  final TextEditingController _note = TextEditingController();
  MedKind _kind = MedKind.scheduled;
  bool _filled = false;
  String? _error;

  @override
  CareService get careService => widget.service;
  @override
  FamilyPrincipal? get careWho => widget.principal;

  bool get _isNew => widget.medicationId == null;

  @override
  void initState() {
    super.initState();
    unawaited(_init());
  }

  Future<void> _init() async {
    await reload();
    final CareMedication? m = _med;
    if (m != null && !_filled) {
      _name.text = m.name;
      _dose.text = m.dose;
      _t1.text = m.slots.isNotEmpty ? m.slots[0] : '';
      _t2.text = m.slots.length > 1 ? m.slots[1] : '';
      _gap.text = '${m.gapHours}';
      _note.text = m.note;
      _kind = m.kind;
    }
    if (mounted) setState(() => _filled = true);
  }

  @override
  void dispose() {
    for (final TextEditingController c in <TextEditingController>[_name, _dose, _t1, _t2, _gap, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  CareMedication? get _med {
    for (final CareMedication m in doc?.meds ?? const <CareMedication>[]) {
      if (m.id == widget.medicationId) return m;
    }
    return null;
  }

  CareMedication _draft() => CareMedication(
    id: _med?.id ?? '',
    name: _name.text,
    dose: _dose.text,
    kind: _kind,
    slots: <String>[
      for (final String s in <String>[_t1.text, _t2.text])
        if (s.trim().isNotEmpty) s.trim(),
    ],
    gapHours: int.tryParse(_gap.text.trim()) ?? 4,
    note: _note.text,
  );

  Future<void> _save() async {
    final CareResult<Object?> r = _isNew
        ? await widget.service.addMedication(widget.principal, _draft(), byName: widget.byName)
        : await widget.service.editMedication(widget.principal, widget.medicationId!, _draft(), byName: widget.byName);
    if (!mounted) return;
    if (r.ok) {
      _snack(context, _isNew ? 'Added.' : 'Saved. Past doses are unchanged.');
      Navigator.of(context).pop();
    } else {
      setState(() => _error = careRefusalText(r.reason));
    }
  }

  Future<void> _retire() async {
    final bool? yes = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        title: const Text('Retire this medicine?'),
        content: const Text('It leaves the list. Its dose log stays and can still be read.'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Keep it')),
          FilledButton(
            key: const Key('confirmRetire'),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Retire'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    final CareResult<void> r = await widget.service.retireMedication(
      widget.principal,
      widget.medicationId!,
      byName: widget.byName,
    );
    if (!mounted) return;
    if (r.ok) {
      _snack(context, 'Retired. Its dose log stays.');
      Navigator.of(context).pop();
    } else {
      setState(() => _error = careRefusalText(r.reason));
    }
  }

  Future<void> _logDose() async {
    final CareResult<DateTime> r = await widget.service.logDose(
      widget.principal,
      widget.medicationId!,
      byName: widget.byName,
    );
    if (!mounted) return;
    if (r.ok) {
      _snack(context, 'Logged.');
      await reload();
      return;
    }
    if (r.reason == 'already_given') {
      final Map<String, Object?> x = r.detail ?? const <String, Object?>{};
      final DateTime at = (x['at'] as DateTime).toLocal();
      final DateTime? next = (x['next'] as DateTime?);
      final String by = _who(x['byId'] as String, x['byName'] as String, me);
      await showDialog<void>(
        context: context,
        builder: (BuildContext c) => AlertDialog(
          key: const Key('alreadyGiven'),
          title: const Text('Already given'),
          content: Text(
            '${x['name']} was given at ${careTime(at)} on ${careDay(at)} by $by.'
            '${next == null ? '' : ' The next dose is allowed from ${careTime(next)}.'}'
            ' Nothing was logged. If you think it was a mistake, add a note to the handover log.',
          ),
          actions: <Widget>[
            FilledButton(
              key: const Key('alreadyGivenOk'),
              onPressed: () => Navigator.pop(c),
              child: const Text('Understood'),
            ),
          ],
        ),
      );
      return;
    }
    setState(() => _error = careRefusalText(r.reason));
  }

  Widget _f(Key k, TextEditingController c, String label, {TextInputType? type, String? hint}) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextField(
      key: k,
      controller: c,
      keyboardType: type,
      decoration: InputDecoration(labelText: label, hintText: hint, border: const OutlineInputBorder()),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (refused || !canEditStructure(widget.principal)) return const CareNotForYou();
    if (!_filled) return Scaffold(appBar: AppBar(), body: const SizedBox.shrink());
    final CareMedication? m = _med;
    if (!_isNew && m == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Medicine')),
        body: const Center(child: Text('Nothing open.')),
      );
    }
    final DateTime now = (widget.clock ?? DateTime.now)();
    final MedState? st = m == null || m.retired ? null : medState(m, now);
    return Scaffold(
      appBar: AppBar(title: Text(_isNew ? 'New medicine' : (m!.retired ? 'Retired' : m.name))),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (st != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          st.given && st.last != null
                              ? (m!.kind == MedKind.prn
                                    ? 'Given at ${careTime(st.last!.at.toLocal())}. Next allowed ${careTime(st.next!)}'
                                    : 'Given ${careTime(st.last!.at.toLocal())} by ${_who(st.last!.byId, st.last!.byName, me)}')
                              : st.due && st.slot != null
                              ? 'Due since ${careTime(st.slot!)}'
                              : 'Can be given',
                          key: const Key('medStatus'),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          m!.kind == MedKind.prn
                              ? 'At least ${m.gapHours} h between doses.'
                              : 'Daily at ${m.slots.map(formatTimeOfDay).join(', ')}.',
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 48,
                          width: double.infinity,
                          child: FilledButton.icon(
                            key: const Key('logDose'),
                            icon: const Icon(Icons.check),
                            label: const Text('Log a dose I just gave'),
                            onPressed: _logDose,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'If someone already logged it, you will be told who and when. There is no override.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    _error!,
                    key: const Key('medError'),
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              Text(
                _isNew ? 'New medicine' : (m!.retired ? 'Retired' : 'Details'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              _f(const Key('medFormName'), _name, 'Name'),
              _f(const Key('medFormDose'), _dose, 'Dose', hint: '2 puffs'),
              if (_isNew)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SegmentedButton<MedKind>(
                    key: const Key('medKind'),
                    segments: const <ButtonSegment<MedKind>>[
                      ButtonSegment<MedKind>(value: MedKind.scheduled, label: Text('Every day')),
                      ButtonSegment<MedKind>(value: MedKind.prn, label: Text('Only when needed')),
                    ],
                    selected: <MedKind>{_kind},
                    onSelectionChanged: (Set<MedKind> s) => setState(() => _kind = s.first),
                  ),
                ),
              if (_kind == MedKind.scheduled) ...<Widget>[
                _f(const Key('medFormT1'), _t1, 'Time (24 hour, for example 08:00)', type: TextInputType.datetime),
                _f(const Key('medFormT2'), _t2, 'Second time (optional)', type: TextInputType.datetime),
              ] else
                _f(const Key('medFormGap'), _gap, 'Hours between doses', type: TextInputType.number),
              _f(const Key('medFormNote'), _note, 'Note', hint: 'With breakfast'),
              if (m == null || !m.retired)
                SizedBox(
                  height: 48,
                  width: double.infinity,
                  child: FilledButton(
                    key: const Key('saveMedicine'),
                    onPressed: _save,
                    child: Text(_isNew ? 'Add this medicine' : 'Save changes'),
                  ),
                ),
              if (m != null && !m.retired)
                SizedBox(
                  height: 48,
                  width: double.infinity,
                  child: TextButton(
                    key: const Key('retireMedicine'),
                    onPressed: _retire,
                    child: const Text('Retire this medicine'),
                  ),
                ),
              if (m != null) ...<Widget>[
                _section(context, 'Dose log'),
                if (m.doses.isEmpty)
                  const Text('Nothing logged yet.', key: Key('doseLogEmpty'))
                else
                  for (final CareDose x in m.doses.reversed)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text('${careTime(x.at.toLocal())} on ${careDay(x.at.toLocal())}'),
                      subtitle: Text('Given by ${_who(x.byId, x.byName, me)}'),
                    ),
                const SizedBox(height: 8),
                const Text('The dose log is never edited or deleted. A mistake is explained in a handover note.'),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================== expenses ===
class LocalExpensesScreen extends StatefulWidget {
  const LocalExpensesScreen({
    super.key,
    required this.service,
    required this.principal,
    this.byName,
    this.childName = 'her',
    this.guardianCount = 1,
  });
  final CareService service;
  final FamilyPrincipal? principal;
  final String? byName;
  final String childName;
  final int guardianCount;

  @override
  State<LocalExpensesScreen> createState() => _LocalExpensesState();
}

class _LocalExpensesState extends State<LocalExpensesScreen> with _CareLoad<LocalExpensesScreen> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _reason = TextEditingController();
  String? _disputing;
  String? _error;

  @override
  CareService get careService => widget.service;
  @override
  FamilyPrincipal? get careWho => widget.principal;

  @override
  void initState() {
    super.initState();
    unawaited(reload());
  }

  @override
  void dispose() {
    _title.dispose();
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _propose() async {
    final CareResult<String> r = await widget.service.proposeExpense(
      widget.principal,
      _title.text,
      _amount.text,
      byName: widget.byName,
    );
    if (!mounted) return;
    if (r.ok) {
      _title.clear();
      _amount.clear();
      setState(() => _error = null);
      _snack(
        context,
        widget.guardianCount == 1 ? 'Recorded. You can accept it below.' : 'Proposed. The other grown-up decides.',
      );
      await reload();
    } else {
      setState(() => _error = careRefusalText(r.reason));
    }
  }

  Future<void> _act(CareExpense e, ExpenseAction a, {String reason = ''}) async {
    final CareResult<ExpenseStatus> r = await widget.service.resolveExpense(
      widget.principal,
      e.id,
      a,
      reason: reason,
      byName: widget.byName,
    );
    if (!mounted) return;
    if (r.ok) {
      setState(() {
        _error = null;
        _disputing = null;
        _reason.clear();
      });
      await reload();
    } else {
      setState(() => _error = careRefusalText(r.reason));
    }
  }

  String _statusLine(CareExpense e) {
    final bool mine = e.paidById == me;
    switch (e.status) {
      case ExpenseStatus.proposed:
        if (widget.guardianCount == 1) return 'Waiting for you to accept it';
        return 'Waiting for ${mine ? 'the other grown-up' : 'you'}';
      case ExpenseStatus.accepted:
        final bool self = e.events.any((ExpenseEvent x) => x.selfAccept);
        return self ? 'Accepted by you, as the only grown-up here' : 'Accepted';
      case ExpenseStatus.disputed:
        return 'Disputed${e.reason.isEmpty ? '' : ': ${e.reason}'}';
      case ExpenseStatus.reimbursed:
        return 'Reimbursed';
    }
  }

  @override
  Widget build(BuildContext context) {
    // P6: nothing financial is even built for anyone who is not a grown-up.
    if (refused || !canEditStructure(widget.principal)) return const CareNotForYou();
    final CareDoc? d = doc;
    final List<CareExpense> list = d == null ? const <CareExpense>[] : d.expenses.reversed.toList();
    final bool sole = widget.guardianCount == 1;
    final bal = expenseBalance(d?.expenses ?? const <CareExpense>[], me);
    return Scaffold(
      appBar: AppBar(title: const Text('Shared expenses')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _banner(
                context,
                "Olive Branch keeps the record only. It never moves money, and ${widget.childName} can't see any of this.",
                key: const Key('expensesBanner'),
                icon: Icons.receipt_long_outlined,
              ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        sole ? 'Accepted, not yet reimbursed (recorded)' : 'Accepted, not yet reimbursed',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        sole
                            ? formatCents(bal.recordedTotal)
                            : bal.owedToMe == 0
                            ? 'Even'
                            : bal.owedToMe > 0
                            ? 'The other grown-up owes you ${formatCents(bal.owedToMe)}'
                            : 'You owe the other grown-up ${formatCents(-bal.owedToMe)}',
                        key: const Key('expenseBalance'),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        sole
                            ? "Kept on this device. It reaches the other grown-up's phone when the family is connected. Later."
                            : 'Half each. A record, not a bill.',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('Propose an expense', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      TextField(
                        key: const Key('expenseTitle'),
                        controller: _title,
                        decoration: const InputDecoration(
                          labelText: 'What it was for',
                          hintText: 'School shoes',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        key: const Key('expenseAmount'),
                        controller: _amount,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Amount',
                          hintText: '48.00',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            _error!,
                            key: const Key('expenseError'),
                            style: TextStyle(color: Theme.of(context).colorScheme.error),
                          ),
                        ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 48,
                        width: double.infinity,
                        child: FilledButton.tonalIcon(
                          key: const Key('proposeExpense'),
                          icon: const Icon(Icons.add),
                          label: const Text('Propose it'),
                          onPressed: _propose,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        sole
                            ? 'You are the only grown-up on this device, so you can accept your own. It is marked as such.'
                            : "The other grown-up decides. You can't accept your own.",
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
              _section(context, 'Expenses'),
              if (d != null && list.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('No expenses yet.', key: Key('expensesEmpty')),
                ),
              for (final CareExpense e in list) _expenseCard(context, e, sole),
            ],
          ),
        ),
      ),
    );
  }

  Widget _expenseCard(BuildContext context, CareExpense e, bool sole) {
    final bool mine = e.paidById == me;
    final bool canAccept = expenseRefusal(e, ExpenseAction.accept, me, widget.guardianCount) == null;
    final bool canDispute = e.status == ExpenseStatus.proposed && !mine;
    final bool canReimburse = e.status == ExpenseStatus.accepted;
    return Card(
      key: ValueKey<String>('expense-${e.id}'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(e.description, style: Theme.of(context).textTheme.titleSmall),
                      Text(
                        '${formatCents(e.cents)}. Proposed by ${mine ? 'you' : e.paidByName}, ${careDay(e.createdAt.toLocal())}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                _chip(
                  context,
                  switch (e.status) {
                    ExpenseStatus.proposed => 'Proposed',
                    ExpenseStatus.accepted => 'Accepted',
                    ExpenseStatus.disputed => 'Disputed',
                    ExpenseStatus.reimbursed => 'Reimbursed',
                  },
                  good: e.status == ExpenseStatus.accepted || e.status == ExpenseStatus.reimbursed,
                  bad: e.status == ExpenseStatus.disputed,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(_statusLine(e), key: ValueKey<String>('expenseStatus-${e.id}')),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                if (canAccept)
                  SizedBox(
                    height: 48,
                    child: FilledButton.icon(
                      key: ValueKey<String>('accept-${e.id}'),
                      icon: const Icon(Icons.check),
                      label: Text(
                        e.status == ExpenseStatus.disputed
                            ? 'Accept after all'
                            : (sole && mine ? 'Accept (mine)' : 'Accept'),
                      ),
                      onPressed: () => _act(e, ExpenseAction.accept),
                    ),
                  ),
                if (canDispute)
                  SizedBox(
                    height: 48,
                    child: OutlinedButton.icon(
                      key: ValueKey<String>('dispute-${e.id}'),
                      icon: const Icon(Icons.flag_outlined),
                      label: const Text('Dispute'),
                      onPressed: () => setState(() => _disputing = _disputing == e.id ? null : e.id),
                    ),
                  ),
                if (canReimburse)
                  SizedBox(
                    height: 48,
                    child: FilledButton.tonalIcon(
                      key: ValueKey<String>('reimburse-${e.id}'),
                      icon: const Icon(Icons.check),
                      label: const Text('Mark reimbursed'),
                      onPressed: () => _act(e, ExpenseAction.reimburse),
                    ),
                  ),
              ],
            ),
            if (_disputing == e.id) ...<Widget>[
              const SizedBox(height: 8),
              TextField(
                key: const Key('disputeReason'),
                controller: _reason,
                maxLength: careMaxReasonChars,
                decoration: const InputDecoration(labelText: 'Why? (brief and factual)', border: OutlineInputBorder()),
              ),
              SizedBox(
                height: 48,
                width: double.infinity,
                child: FilledButton(
                  key: ValueKey<String>('sendDispute-${e.id}'),
                  onPressed: () => _act(e, ExpenseAction.dispute, reason: _reason.text),
                  child: const Text('Send dispute'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ========================================================== handover log ===
class LocalHandoverScreen extends StatefulWidget {
  const LocalHandoverScreen({
    super.key,
    required this.service,
    required this.principal,
    this.byName,
    this.childName = 'her',
  });
  final CareService service;
  final FamilyPrincipal? principal;
  final String? byName;
  final String childName;

  @override
  State<LocalHandoverScreen> createState() => _LocalHandoverState();
}

class _LocalHandoverState extends State<LocalHandoverScreen> with _CareLoad<LocalHandoverScreen> {
  final TextEditingController _note = TextEditingController();
  String? _error;

  @override
  CareService get careService => widget.service;
  @override
  FamilyPrincipal? get careWho => widget.principal;

  @override
  void initState() {
    super.initState();
    unawaited(reload());
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _ask() async {
    final String t = _note.text.trim();
    if (t.isEmpty) {
      setState(() => _error = careRefusalText('text_needed'));
      return;
    }
    if (t.length > careHandoverMaxChars) {
      setState(() => _error = careRefusalText('too_long'));
      return;
    }
    final bool? go = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        key: const Key('noteConfirm'),
        title: const Text('This can never be changed'),
        content: const Text('A handover note cannot be edited or deleted by anyone, including you. Add it to the log?'),
        actions: <Widget>[
          TextButton(
            key: const Key('noteKeepEditing'),
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            key: const Key('noteSendForGood'),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Add, for good'),
          ),
        ],
      ),
    );
    if (go != true) return;
    final CareResult<int> r = await widget.service.appendNote(widget.principal, t, byName: widget.byName);
    if (!mounted) return;
    if (r.ok) {
      _note.clear();
      setState(() => _error = null);
      _snack(context, 'Added as note #${r.value}.');
      await reload();
    } else {
      setState(() => _error = careRefusalText(r.reason));
    }
  }

  void _correct(int n) {
    _note.text = correctionStarter(n);
    _note.selection = TextSelection.collapsed(offset: _note.text.length);
    _snack(context, 'A correction is a new note. Finish it above.');
  }

  @override
  Widget build(BuildContext context) {
    if (refused || !canEditStructure(widget.principal)) return const CareNotForYou();
    final CareDoc? d = doc;
    final List<HandoverNoteView> notes = <HandoverNoteView>[
      for (final entry in (d?.notes ?? const []).reversed)
        HandoverNoteView(entry: entry, byName: d!.noteAuthors[entry.seq] ?? careUnnamedGuardian),
    ];
    final ChainStatus ch = chainStatus(d?.notes ?? const []);
    return Scaffold(
      appBar: AppBar(title: const Text('Handover notes')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _banner(
                context,
                'Notes can never be edited or deleted. To fix a mistake, add a correction.',
                key: const Key('handoverBanner'),
                icon: Icons.lock_outline,
                warn: true,
              ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('Chain', style: Theme.of(context).textTheme.labelMedium),
                      const SizedBox(height: 4),
                      Row(
                        children: <Widget>[
                          Icon(ch.intact ? Icons.check_circle_outline : Icons.warning_amber_outlined, size: 18),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              ch.intact
                                  ? 'Intact, ${ch.count} note${ch.count == 1 ? '' : 's'}'
                                  : 'Broken at note ${ch.brokenAtNumber}',
                              key: const Key('chainStatus'),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Each note carries a fingerprint of the one before it, so a change anywhere would show.',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const Key('noteField'),
                controller: _note,
                minLines: 3,
                maxLines: 6,
                maxLength: careHandoverMaxChars,
                decoration: InputDecoration(
                  labelText: 'A note for the other grown-up',
                  border: const OutlineInputBorder(),
                  hintText: '${widget.childName} had a late snack. Blue bunny is in her bag.',
                ),
              ),
              if (_error != null)
                Text(
                  _error!,
                  key: const Key('noteError'),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              const SizedBox(height: 8),
              SizedBox(
                height: 48,
                width: double.infinity,
                child: FilledButton.icon(
                  key: const Key('noteReview'),
                  icon: const Icon(Icons.send_outlined),
                  label: const Text('Review and add'),
                  onPressed: _ask,
                ),
              ),
              const SizedBox(height: 8),
              const Card(
                key: Key('noteSyncLater'),
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Text(
                    'Kept on this phone. It is added to the shared log, in order, when this phone is '
                    'connected to the family. Later.',
                  ),
                ),
              ),
              _section(context, 'The log'),
              if (d != null && notes.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('No notes yet.', key: Key('handoverEmpty')),
                ),
              for (final HandoverNoteView n in notes)
                Card(
                  key: ValueKey<String>('note-${n.number}'),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text('#${n.number}. ${n.text}', style: Theme.of(context).textTheme.bodyLarge),
                        const SizedBox(height: 4),
                        Text(
                          '${_who(n.byId, n.byName, me) == 'you' ? 'You' : n.byName}. ${careDay(n.at.toLocal())}, ${careTime(n.at.toLocal())}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: <Widget>[
                            const Icon(Icons.link, size: 12),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                '${n.hash.substring(0, 12)} after ${n.prevHash.substring(0, 8)}',
                                key: ValueKey<String>('fingerprint-${n.number}'),
                                style: Theme.of(context).textTheme.labelSmall?.copyWith(fontFamily: 'monospace'),
                              ),
                            ),
                          ],
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            key: ValueKey<String>('correct-${n.number}'),
                            icon: const Icon(Icons.edit_outlined, size: 16),
                            label: const Text('Add a correction'),
                            onPressed: () => _correct(n.number),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// =========================================================== her time ======
/// The window both grown-ups and she are awake, 7 AM to 9 PM each, as minutes from midnight on MY clock, or null
/// when there is no shared time. [herOffsetMin] and [myOffsetMin] are UTC offsets in minutes.
({int from, int to})? awakeOverlap(int herOffsetMin, int myOffsetMin, {int wakeMin = 7 * 60, int sleepMin = 21 * 60}) {
  // Her awake window on my clock.
  final int shift = myOffsetMin - herOffsetMin;
  final int a = wakeMin + shift, b = sleepMin + shift;
  // Intersect with my own awake window [wake, sleep], trying the day before and after.
  ({int from, int to})? best;
  for (final int dd in <int>[-1440, 0, 1440]) {
    final int lo = (a + dd) > wakeMin ? (a + dd) : wakeMin;
    final int hi = (b + dd) < sleepMin ? (b + dd) : sleepMin;
    if (hi > lo && (best == null || (hi - lo) > (best.to - best.from))) best = (from: lo, to: hi);
  }
  return best;
}

String overlapText(({int from, int to})? w) {
  if (w == null) return 'No shared waking hours.';
  String hm(int m) {
    final int h = m ~/ 60, mi = m % 60;
    return '${h % 12 == 0 ? 12 : h % 12}${mi == 0 ? '' : ':${mi.toString().padLeft(2, '0')}'} ${h < 12 ? 'AM' : 'PM'}';
  }

  return 'Both awake, 7 AM to 9 PM each, from ${hm(w.from)} to ${hm(w.to)} your time.';
}

class OverlapScreen extends StatelessWidget {
  const OverlapScreen({super.key, this.childName = 'her', this.sameZone = true, this.herZoneLabel = '', this.clock});
  final String childName;

  /// True when her home zone is "same as this phone". Another zone cannot be converted offline (no zone
  /// database on the phone), so the screen says so instead of guessing.
  final bool sameZone;
  final String herZoneLabel;
  final DateTime Function()? clock;

  @override
  Widget build(BuildContext context) {
    final DateTime now = (clock ?? DateTime.now)();
    final int off = now.timeZoneOffset.inMinutes;
    final ({int from, int to})? w = sameZone ? awakeOverlap(off, off) : null;
    final double nowPct = (now.hour * 60 + now.minute) / 1440;
    final ColorScheme c = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Her time, your time')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: _clockCard(
                      context,
                      "$childName, her time",
                      sameZone ? careTime(now) : '--',
                      sameZone ? now.timeZoneName : herZoneLabel,
                      key: const Key('herClock'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _clockCard(
                      context,
                      'You, your time',
                      careTime(now),
                      now.timeZoneName,
                      key: const Key('myClock'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('When you can both talk (your time)', style: Theme.of(context).textTheme.labelMedium),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: SizedBox(
                          key: const Key('overlapRibbon'),
                          height: 14,
                          width: double.infinity,
                          child: LayoutBuilder(
                            builder: (BuildContext _, BoxConstraints bc) {
                              final double wd = bc.maxWidth;
                              return Stack(
                                children: <Widget>[
                                  Positioned.fill(child: ColoredBox(color: c.surfaceContainerHighest)),
                                  if (w != null)
                                    Positioned(
                                      left: wd * w.from / 1440,
                                      width: wd * (w.to - w.from) / 1440,
                                      top: 0,
                                      bottom: 0,
                                      child: ColoredBox(color: c.primary),
                                    ),
                                  Positioned(
                                    left: wd * nowPct - 1,
                                    width: 2,
                                    top: 0,
                                    bottom: 0,
                                    child: ColoredBox(color: c.onSurface),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        sameZone
                            ? overlapText(w)
                            : "Her clock is in a different zone. This phone has no zone clock to convert with, so the window is not shown until the device is connected. Later.",
                        key: const Key('overlapText'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _clockCard(BuildContext context, String label, String time, String zone, {Key? key}) => Card(
    key: key,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          Text(time, style: Theme.of(context).textTheme.titleLarge),
          Text(zone, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    ),
  );
}

/// Which care screen a home tile asks for.
enum CareDestination { meds, handover, expenses }

/// The on-device care screen for [which] when this tree is the offline guardian shell (a local scope above it,
/// no live session); null otherwise, so the preview build keeps its demo screens and a live session keeps the
/// server-backed ones.
Widget? localCareScreen(BuildContext context, CareDestination which,
    {required bool live, required String childName, String? childId, String? guardianId}) {
  final GuardianLocalController? local = GuardianLocalScope.maybeOf(context);
  if (live || local == null) return null;
  final CareService svc = CareService.forChild(childId);
  final FamilyPrincipal me = FamilyPrincipal(roleName: 'guardian', userId: guardianId ?? 'local-guardian');
  final String? by = local.family?.guardianName;
  return switch (which) {
    CareDestination.meds =>
      LocalMedsScreen(service: svc, principal: me, childName: childName, byName: by),
    CareDestination.handover =>
      LocalHandoverScreen(service: svc, principal: me, childName: childName, byName: by),
    CareDestination.expenses =>
      LocalExpensesScreen(service: svc, principal: me, childName: childName, byName: by),
  };
}
