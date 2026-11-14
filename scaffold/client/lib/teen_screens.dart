// OLIVE BRANCH — the 13 to 17 shell's screens: Today, her calendar, free times, the privacy contract, the consent
// log, the journal, what is yours (the ladder) and Me. UNVERIFIED until CI runs it (client/test/teen_screens_test.dart
// and client/test/teen_postures_test.dart). Prototype: mod-child.js homeT1317 / k.cal / k.free / k.privacy / k.ladder;
// round-3 mockups r3a-13-home, -cal, -journal, -me, -ladder. MASTERFILE §21, §8.1.
//
// The tone is the mockups': a calm page for a person with a life. Plain words, no mascot, no voice-over, no
// praise, no streak. The rules are in teen_logic.dart; this file only draws them and writes through
// [TeenRepository] (teen_store.dart).
//
// Invariants kept here (each one has a test):
//   - No count, score, streak, reward or trophy anywhere (P1-P11). The only numbers are dates and her own age.
//   - The journal is hers from the first page: there is no reader, no export route and no grown-up path (P7).
//     JournalRepository is reached only by her screen, and every list passes through readJournal() as role 'child'.
//   - Nothing she makes is shown to anyone until she picks who. The default for an event is only her.
//   - A grown-up's ask can be answered no, and a no is final for seven days. Her consent log is derived from the asks.
//   - Nothing here asks a server anything: offline is the normal state, not a fault.
//   - Layout: every row sizes to its content, so 2.0x text grows the page instead of overflowing it.
import 'dart:async';

import 'package:flutter/material.dart';

import 'contact_labels.dart' show GrownupContact;
import 'grownup_labels.dart';
import 'journal_screen.dart';
import 'local_services.dart';
import 'maturation_ladder.dart';
import 'teen_logic.dart';
import 'teen_store.dart';
import 'ui/olive_art.dart';
import 'ui/olive_base.dart';
import 'ui/olive_controls.dart';
import 'ui/olive_feedback.dart';
import 'ui/olive_flow.dart';
import 'ui/olive_palette.dart';
import 'ui/olive_surfaces.dart';

const List<String> _months = <String>[
  'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
const List<String> _weekdays = <String>['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

String teenLongDate(DateTime d) => '${_weekdays[d.weekday - 1]}, ${_months[d.month - 1]} ${d.day}';
String teenShortDate(DateTime d) => '${_months[d.month - 1].substring(0, 3)} ${d.day}';

/// "December 9" from the ChildBirthday's 'MM-DD'. Null on anything else.
String? teenMonthDay(String? mmdd) {
  if (mmdd == null) return null;
  final List<String> p = mmdd.split('-');
  if (p.length != 2) return null;
  final int? m = int.tryParse(p[0]), d = int.tryParse(p[1]);
  if (m == null || d == null || m < 1 || m > 12 || d < 1 || d > 31) return null;
  return '${_months[m - 1]} $d';
}

/// The grown-ups she knows, as she names them. Empty when none are known.
List<(String, String)> teenGrownUps(BuildContext context) {
  final GrownupLabels l = GrownupLabelScope.of(context);
  return <(String, String)>[for (final GrownupContact c in l.contacts) (c.id, l.nameFor(c.id))];
}

/// "Mom", "Mom and Dad", "Mom, Dad and Gran".
String teenJoinNames(List<String> names) {
  if (names.isEmpty) return 'your grown-ups';
  if (names.length == 1) return names.first;
  return '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
}

/// The one page shape every teen screen uses: a title bar, a centred column no wider than 640, a scroll.
class TeenPage extends StatelessWidget {
  const TeenPage({super.key, required this.title, required this.children, this.bodyKey});
  final String title;
  final List<Widget> children;
  final Key? bodyKey;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: SingleChildScrollView(
                key: bodyKey,
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
                  for (int i = 0; i < children.length; i++) ...<Widget>[
                    if (i > 0) const SizedBox(height: 12),
                    children[i],
                  ],
                ]),
              ),
            ),
          ),
        ),
      );
}

void _push(BuildContext context, Widget screen) =>
    unawaited(Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen)));

Widget _fine(BuildContext context, String text, {Key? key}) =>
    Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Text(text, key: key, style: OliveText.cap(context)));

Widget _h(BuildContext context, String text) => Text(text, style: OliveText.head(context));

// ================================================================== Today ===
/// The calm card at the top of her home: today's date, her own events today and, if she published them, the free
/// times a grown-up sees. No count, no badge. Reads her own store; a store that cannot be read shows an empty day.
class TeenToday extends StatefulWidget {
  const TeenToday({super.key, required this.age, required this.now, this.repository});
  final int age;
  final DateTime now;
  final TeenRepository? repository;

  @override
  State<TeenToday> createState() => _TeenTodayState();
}

class _TeenTodayState extends State<TeenToday> {
  late final TeenRepository _repo = widget.repository ?? TeenRepository.forChild();
  List<TeenEvent> _today = const <TeenEvent>[];
  FreeTimes _free = const FreeTimes();

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final List<TeenEvent> all = await _repo.events();
      final FreeTimes f = await _repo.freeTimes();
      if (!mounted) return;
      final DateTime n = widget.now;
      setState(() {
        _today = eventsOn(all, n.year, n.month, n.day);
        _free = f;
      });
    } catch (_) {
      // An unreadable store shows an empty day. Nothing to explain.
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool showFree = widget.age >= kFreeTimesAge && _free.published;
    return OliveCard(
      key: const Key('teenToday'),
      variant: OliveCardVariant.tint,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Text('TODAY', style: OliveText.label(context)),
        const SizedBox(height: 6),
        if (_today.isEmpty && !showFree)
          Text('Nothing on your calendar today.', key: const Key('teenTodayEmpty'), style: OliveText.body(context)),
        for (final TeenEvent e in _today)
          Padding(padding: const EdgeInsets.only(top: 4), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            const OliveIcon('calendar', size: 18, strokeWidth: 2),
            const SizedBox(width: 10),
            Expanded(child: Text(e.title, key: Key('teenTodayEvent.${e.id}'), style: OliveText.body(context))),
          ])),
        if (showFree)
          Padding(padding: const EdgeInsets.only(top: 6), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            const OliveIcon('clock', size: 18, strokeWidth: 2),
            const SizedBox(width: 10),
            Expanded(child: Text(_free.describe(), key: const Key('teenTodayFree'), style: OliveText.body(context))),
          ])),
      ]),
    );
  }
}

// =============================================================== calendar ===
class TeenCalendarScreen extends StatefulWidget {
  const TeenCalendarScreen({super.key, required this.age, this.repository, this.clock});
  final int age;
  final TeenRepository? repository;
  final DateTime Function()? clock;

  @override
  State<TeenCalendarScreen> createState() => _TeenCalendarState();
}

class _TeenCalendarState extends State<TeenCalendarScreen> {
  late final TeenRepository _repo = widget.repository ?? TeenRepository.forChild();
  late int _y, _m, _d;
  List<TeenEvent> _events = const <TeenEvent>[];

  /// The grown-ups she said yes to sharing her calendar with: new events start shared with them (she can still pick
  /// only herself on each one).
  Set<String> _defaultTo = const <String>{};

  DateTime _now() => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    final DateTime n = _now();
    _y = n.year;
    _m = n.month;
    _d = n.day;
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final List<TeenEvent> e = await _repo.events();
      final AskLedger l = await _repo.asks();
      if (mounted) {
        setState(() {
          _events = e;
          _defaultTo = l.sharingWith(ShareKind.calendar);
        });
      }
    } catch (_) {}
  }

  void _shift(int by) => setState(() {
        final DateTime t = DateTime(_y, _m + by, 1);
        _y = t.year;
        _m = t.month;
        _d = 1;
      });

  Future<void> _add() async {
    final List<(String, String)> people = teenGrownUps(context);
    final ({String title, Set<String> to})? r = await showModalBottomSheet<({String title, Set<String> to})>(
      context: context, isScrollControlled: true, showDragHandle: true,
      builder: (BuildContext c) => _AddEventSheet(people: people, dayLabel: '${_months[_m - 1]} $_d', initial: _defaultTo),
    );
    if (r == null || !mounted) return;
    final String? title = cleanEventTitle(r.title);
    if (title == null) return;
    final TeenEvent e = TeenEvent(
      id: 'e${_now().microsecondsSinceEpoch}', year: _y, month: _m, day: _d, title: title,
      share: r.to.isEmpty ? EventShare.onlyMe : EventShare.with_(r.to),
    );
    setState(() => _events = <TeenEvent>[..._events, e]);
    try {
      await _repo.addEvent(e);
    } catch (_) {
      if (!mounted) return;
      setState(() => _events = <TeenEvent>[for (final TeenEvent x in _events) if (x.id != e.id) x]);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("That couldn't be kept just now.")));
    }
  }

  Future<void> _remove(TeenEvent e) async {
    setState(() => _events = <TeenEvent>[for (final TeenEvent x in _events) if (x.id != e.id) x]);
    try {
      await _repo.removeEvent(e.id);
    } catch (_) {
      if (mounted) unawaited(_load());
    }
  }

  String _shareWords(TeenEvent e, List<(String, String)> people) {
    if (e.share.isPrivate) return 'Only me';
    final List<String> names = <String>[for (final (String id, String n) in people) if (e.share.sees(id)) n];
    return names.isEmpty ? 'Only me' : 'Shown to ${teenJoinNames(names)}';
  }

  @override
  Widget build(BuildContext context) {
    final bool edit = canEditOwnCalendar(widget.age);
    final List<(String, String)> people = teenGrownUps(context);
    final DateTime n = _now();
    final Map<int, DayMark> marks = <int, DayMark>{
      for (final TeenEvent e in _events) if (e.year == _y && e.month == _m) e.day: DayMark.event,
    };
    final List<TeenEvent> day = eventsOn(_events, _y, _m, _d);
    return TeenPage(title: 'My calendar', bodyKey: const Key('teenCalendar'), children: <Widget>[
      if (!edit)
        const OliveBanner('You can look at the calendar now. You can add your own things from 14.',
            icon: 'calendar', key: Key('teenCalendarLookOnly')),
      OliveCard(child: MonthCalendar(
        year: _y, month: _m, today: n.year == _y && n.month == _m ? n.day : null, selected: _d, marks: marks,
        showLegend: false, onSelect: (int d) => setState(() => _d = d), onPrevious: () => _shift(-1), onNext: () => _shift(1),
      )),
      _h(context, '${_months[_m - 1]} $_d'),
      if (day.isEmpty)
        Text('Nothing on ${_months[_m - 1]} $_d.', key: const Key('teenCalendarEmptyDay'), style: OliveText.body(context))
      else
        OliveRowGroup(children: <Widget>[
          for (final TeenEvent e in day)
            OliveRow(
              key: Key('teenEvent.${e.id}'),
              title: e.title, sub: _shareWords(e, people), icon: e.share.isPrivate ? 'lock' : 'calendar',
              trailing: edit
                  ? OliveIconButton('trash', label: 'Remove ${e.title}', kind: OliveButtonKind.ghost, small: true,
                      onPressed: () => unawaited(_remove(e)))
                  : null,
            ),
        ]),
      if (edit) OliveButton('Add something', key: const Key('teenCalendarAdd'), icon: 'plus', full: true, onPressed: _add),
      _fine(context, 'Nothing here is shown to anyone until you pick who.'),
    ]);
  }
}

class _AddEventSheet extends StatefulWidget {
  const _AddEventSheet({required this.people, required this.dayLabel, this.initial = const <String>{}});
  final List<(String, String)> people;
  final String dayLabel;
  final Set<String> initial;

  @override
  State<_AddEventSheet> createState() => _AddEventSheetState();
}

class _AddEventSheetState extends State<_AddEventSheet> {
  final TextEditingController _title = TextEditingController();

  /// Empty = only me; otherwise the ids chosen ('both' is every id).
  late Set<String> _to = <String>{
    for (final (String id, String _) in widget.people)
      if (widget.initial.contains(id)) id,
  };

  @override
  void initState() {
    super.initState();
    _title.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  bool _is(Set<String> s) => _to.length == s.length && _to.containsAll(s);

  @override
  Widget build(BuildContext context) {
    final List<(String, String)> p = widget.people;
    final Set<String> every = <String>{for (final (String id, String _) in p) id};
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
          _h(context, 'Add to ${widget.dayLabel}'),
          const SizedBox(height: 8),
          OliveFormField(label: 'What is it?', controller: _title, placeholder: 'Study group', hint: 'Up to $kEventTitleMax letters.'),
          const SizedBox(height: 8),
          Text('Who else sees it?', style: OliveText.strong(context)),
          RadioRow(key: const Key('shareOnlyMe'), title: 'Only me', selected: _to.isEmpty, onSelected: () => setState(() => _to = <String>{})),
          for (final (String id, String name) in p)
            RadioRow(key: Key('share.$id'), title: name, selected: _is(<String>{id}),
                onSelected: () => setState(() => _to = <String>{id})),
          if (p.length > 1)
            RadioRow(key: const Key('shareBoth'), title: 'Both', selected: _is(every), onSelected: () => setState(() => _to = <String>{...every})),
          const SizedBox(height: 12),
          OliveButton('Add it', key: const Key('teenEventSave'), icon: 'check', full: true,
              onPressed: cleanEventTitle(_title.text) == null
                  ? null
                  : () => Navigator.of(context).pop((title: _title.text, to: _to))),
        ]),
      ),
    );
  }
}

// ============================================================= free times ===
class TeenFreeTimesScreen extends StatefulWidget {
  const TeenFreeTimesScreen({super.key, required this.age, this.repository});
  final int age;
  final TeenRepository? repository;

  @override
  State<TeenFreeTimesScreen> createState() => _TeenFreeTimesState();
}

class _TeenFreeTimesState extends State<TeenFreeTimesScreen> {
  late final TeenRepository _repo = widget.repository ?? TeenRepository.forChild();
  FreeTimes _f = const FreeTimes();
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    unawaited(() async {
      try {
        final FreeTimes f = await _repo.freeTimes();
        if (mounted) setState(() => _f = f);
      } catch (_) {}
    }());
  }

  Future<void> _save() async {
    final FreeTimes p = _f.asPublished();
    setState(() {
      _f = p;
      _saved = true;
    });
    try {
      await _repo.saveFreeTimes(p);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saved = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("That couldn't be kept just now.")));
    }
  }

  Widget _group(String title, bool weekend) => OliveCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          _h(context, title),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: <Widget>[
            for (final (String id, String label) in kFreeParts)
              OliveFilterChip(label, key: Key('free.${weekend ? 'we' : 'wd'}.$id'), icon: null,
                  selected: (weekend ? _f.weekends : _f.schoolDays).contains(id),
                  onTap: () => setState(() {
                        _f = _f.toggled(weekend, id);
                        _saved = false;
                      })),
          ]),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    if (widget.age < kFreeTimesAge) {
      return const TeenPage(title: 'Your free times', children: <Widget>[
        OliveBanner('This opens at 15.', icon: 'clock', key: Key('freeTimesLocked')),
      ]);
    }
    final String who = teenJoinNames(<String>[for (final (String _, String n) in teenGrownUps(context)) n]);
    return TeenPage(title: 'Your free times', bodyKey: const Key('teenFreeTimes'), children: <Widget>[
      Text('You decide when you are free.', style: OliveText.body(context)),
      _group('School days', false),
      _group('Weekends', true),
      OliveCard(variant: OliveCardVariant.flat, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        _h(context, 'What they see'),
        const SizedBox(height: 6),
        Text('$who see: ${_f.describe()}', key: const Key('freeTimesPreview'), style: OliveText.body(context)),
        const SizedBox(height: 6),
        Text('They do not see why you are busy.', style: OliveText.cap(context)),
      ])),
      OliveButton('Save my times', key: const Key('freeTimesSave'), full: true, onPressed: () => unawaited(_save())),
      if (_saved) const OliveBanner('Saved. You can change it any minute.', tone: OliveTone.ok, icon: 'check', key: Key('freeTimesSaved')),
    ]);
  }
}

// ============================================================ privacy page ===
/// "What your grown-ups can see": one plain table, the same rules the other way, and the two honest rows next to it
/// (the consent log and her free times). Nothing here is a count; nothing is hidden in an 'other'.
class TeenPrivacyScreen extends StatelessWidget {
  const TeenPrivacyScreen({super.key, required this.age, this.onConsentLog, this.onFreeTimes});
  final int age;
  final VoidCallback? onConsentLog;
  final VoidCallback? onFreeTimes;

  Widget _cell(BuildContext context, String who, Seen v) {
    final OlivePalette p = OlivePalette.of(context);
    final (String icon, String words) = switch (v) {
      Seen.see => ('eye', '$who can see this'),
      Seen.choose => ('hand', '$who sees it only if you choose'),
      Seen.no => ('eyeoff', '$who cannot see this'),
    };
    final String short = switch (v) { Seen.see => 'See', Seen.choose => 'You choose', Seen.no => 'No' };
    return Semantics(
      label: words,
      child: ExcludeSemantics(child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
        OliveIcon(icon, size: 16, strokeWidth: 2, color: v == Seen.no ? p.ink3 : p.ink),
        const SizedBox(width: 6),
        Flexible(child: Text('$who: $short', style: OliveText.strong(context, size: 13, color: v == Seen.no ? p.ink3 : p.ink))),
      ])),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<(String, String)> people = teenGrownUps(context);
    final List<String> names = <String>[for (final (String _, String n) in people) n];
    final List<String> cols = names.isEmpty ? <String>['Your grown-up'] : names;
    final List<ContractRow> rows = privacyContract(cols, age: age);
    return TeenPage(title: 'Privacy', bodyKey: const Key('teenPrivacy'), children: <Widget>[
      OliveCard(variant: OliveCardVariant.tint, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Row(children: <Widget>[
          const OliveIcon('lock', size: 14, strokeWidth: 2.2),
          const SizedBox(width: 6),
          Text('ONLY YOU', style: OliveText.label(context)),
        ]),
        const SizedBox(height: 6),
        Text('Your journal is yours. Where you are is yours.', style: OliveText.title(context)),
        const SizedBox(height: 6),
        Text('No one can open your journal: not ${teenJoinNames(names.isEmpty ? <String>['your grown-up'] : names).replaceAll(' and ', ', not ')}, '
            'not us, and not through a court order. We never ask your device where you are.',
            key: const Key('privacyJournalLine'), style: OliveText.body(context)),
      ])),
      OliveCard(child: Column(key: const Key('privacyTable'), crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        _h(context, 'Who can see what'),
        for (final ContractRow r in rows)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Text(r.title, style: OliveText.strong(context, size: 15)),
              Text(r.sub, style: OliveText.cap(context)),
              const SizedBox(height: 4),
              Wrap(spacing: 14, runSpacing: 4, children: <Widget>[
                for (int i = 0; i < cols.length; i++) _cell(context, cols[i], r.values[i]),
              ]),
            ]),
          ),
      ])),
      OliveCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        _h(context, 'What you can see of them'),
        const SizedBox(height: 6),
        Text(privacyReverse(people.length), key: const Key('privacyReverse'), style: OliveText.body(context)),
      ])),
      if (onConsentLog != null || onFreeTimes != null)
        OliveRowGroup(children: <Widget>[
          if (onConsentLog != null)
            OliveRow(key: const Key('privacyConsentLog'), title: 'Consent log', sub: 'Every ask and every answer', icon: 'receipt', onTap: onConsentLog),
          if (onFreeTimes != null)
            OliveRow(key: const Key('privacyFreeTimes'), title: 'Free times', sub: age >= kFreeTimesAge ? 'You decide' : 'Opens at 15', icon: 'clock',
                onTap: age >= kFreeTimesAge ? onFreeTimes : null),
        ]),
      OliveCard(variant: OliveCardVariant.flat, child: Text(
          'Some things the grown-ups set up for the whole family, such as handovers, school and appointments. '
          'They can see those, and so can you. Nothing here changes without you seeing it.',
          style: OliveText.cap(context))),
    ]);
  }
}

// ============================================================= consent log ===
String consentWords(ConsentLine l, String asker) => switch (l.event) {
      'asked' => '$asker asked to see ${l.kind.askWords}.',
      'yes' => 'You said yes to $asker: ${l.kind.askWords}.',
      'no' => 'You said no to $asker: ${l.kind.askWords}.',
      _ => 'You stopped sharing ${l.kind.askWords} with $asker.',
    };

/// Every ask and every answer, and the one place she answers an open ask or stops sharing. Offline by construction:
/// the asks live on this device ([TeenRepository]).
class ConsentLogScreen extends StatefulWidget {
  const ConsentLogScreen({super.key, required this.age, this.repository, this.clock});
  final int age;
  final TeenRepository? repository;
  final DateTime Function()? clock;

  @override
  State<ConsentLogScreen> createState() => _ConsentLogState();
}

class _ConsentLogState extends State<ConsentLogScreen> {
  late final TeenRepository _repo = widget.repository ?? TeenRepository.forChild();
  AskLedger _ledger = const AskLedger();

  DateTime _now() => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final AskLedger l = await _repo.asks();
      if (mounted) setState(() => _ledger = l);
    } catch (_) {}
  }

  Future<void> _set(AskLedger l) async {
    setState(() => _ledger = l);
    try {
      await _repo.saveAsks(l);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("That couldn't be kept just now.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final GrownupLabels labels = GrownupLabelScope.of(context);
    String name(String id) => labels.nameFor(id);
    final List<ShareAsk> open = _ledger.open;
    final List<ShareAsk> sharing = <ShareAsk>[for (final ShareAsk a in _ledger.asks) if (a.sharing) a];
    final List<ConsentLine> log = consentLog(_ledger);
    return TeenPage(title: 'Consent log', bodyKey: const Key('consentLog'), children: <Widget>[
      Text('Every time someone asks to see something, and every answer you gave, is here. Only you read this page.',
          style: OliveText.body(context)),
      if (open.isNotEmpty) ...<Widget>[
        const OliveSectionLabel('Waiting for you', key: Key('consentOpenLabel')),
        for (final ShareAsk a in open)
          OliveCard(key: Key('ask.${a.id}'), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            _h(context, '${name(a.askerId)} would like to see ${a.kind.askWords}.'),
            const SizedBox(height: 4),
            Text(a.kind.yesMeans, style: OliveText.body(context)),
            const SizedBox(height: 4),
            Text('If you say no, they cannot ask again for a week. You can stop sharing any time.', style: OliveText.cap(context)),
            const SizedBox(height: 10),
            Wrap(spacing: 10, runSpacing: 8, children: <Widget>[
              OliveButton('Yes, share', key: Key('askYes.${a.id}'), onPressed: () => unawaited(_set(_ledger.answer(a.id, AskAnswer.yes, _now())))),
              OliveButton('No', key: Key('askNo.${a.id}'), kind: OliveButtonKind.ghost,
                  onPressed: () => unawaited(_set(_ledger.answer(a.id, AskAnswer.no, _now())))),
            ]),
          ])),
      ],
      if (sharing.isNotEmpty) ...<Widget>[
        const OliveSectionLabel('Sharing now'),
        OliveRowGroup(children: <Widget>[
          for (final ShareAsk a in sharing)
            OliveRow(
              key: Key('sharing.${a.id}'), title: '${a.kind.title} with ${name(a.askerId)}', sub: a.kind.yesMeans, icon: 'eye',
              trailing: OliveButton('Stop', key: Key('stop.${a.id}'), size: OliveButtonSize.sm, kind: OliveButtonKind.ghost,
                  onPressed: () => unawaited(_set(_ledger.stop(a.id, _now())))),
            ),
        ]),
      ],
      const OliveSectionLabel('Every ask and every answer'),
      if (log.isEmpty)
        Text('Nobody has asked you for anything.', key: const Key('consentEmpty'), style: OliveText.body(context))
      else
        OliveRowGroup(children: <Widget>[
          for (final ConsentLine l in log)
            OliveRow(
              key: Key('log.${l.askId}.${l.event}'),
              title: consentWords(l, name(l.askerId)), sub: teenShortDate(l.at),
              icon: l.event == 'no' || l.event == 'stopped' ? 'eyeoff' : l.event == 'yes' ? 'eye' : 'hand',
            ),
        ]),
    ]);
  }
}

// =============================================================== journal ===
/// Her journal as a teen: locked from the first page, absolutely. No prompts, no moods, no streaks, nothing that
/// suggests what to write and nothing that reads it. It uses the same sealed on-device store as the younger
/// journal ([JournalRepository]), so entries she wrote earlier are here too.
class TeenJournalScreen extends StatefulWidget {
  const TeenJournalScreen({super.key, required this.childName, this.childId, this.repository, this.clock});
  final String childName;
  final String? childId;
  final JournalRepository? repository;
  final DateTime Function()? clock;

  @override
  State<TeenJournalScreen> createState() => _TeenJournalState();
}

class _TeenJournalState extends State<TeenJournalScreen> {
  late final String _childId = widget.childId ?? LocalServices.current.childId;
  late final JournalRepository _repo = widget.repository ?? JournalRepository.forChild(widget.childId);
  final TextEditingController _text = TextEditingController();
  List<JournalEntry> _entries = const <JournalEntry>[];
  bool _writing = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final List<JournalEntry> stored = await _repo.load();
      // Same structural P7 gate as the younger journal: role 'child', her own id.
      final List<JournalEntry> mine = readJournal(stored, 'child', _childId, _childId).entries ?? const <JournalEntry>[];
      if (mounted) setState(() => _entries = mine);
    } catch (_) {
      // An unreadable journal file was quarantined by the store; she starts a fresh page.
    }
  }

  Future<void> _save() async {
    final String t = _text.text.trim();
    if (t.isEmpty) return;
    final DateTime now = (widget.clock ?? DateTime.now)();
    final JournalEntry e = JournalEntry(id: 'j-${now.microsecondsSinceEpoch}', childId: _childId, body: t, createdAt: now);
    setState(() {
      _entries = <JournalEntry>[e, ..._entries];
      _writing = false;
      _text.clear();
    });
    try {
      await _repo.add(e);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _entries = <JournalEntry>[for (final JournalEntry x in _entries) if (x.id != e.id) x];
        _text.text = t;
        _writing = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("This page couldn't be kept just now. Your words are still here.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return TeenPage(title: 'Journal', bodyKey: const Key('teenJournal'), children: <Widget>[
      Row(children: <Widget>[
        const OliveChip('Only you', icon: 'lock', key: Key('journalOnlyYou')),
        const SizedBox(width: 10),
        Expanded(child: Text('Nobody can open this. Not a grown-up, not the app.', style: OliveText.cap(context))),
      ]),
      if (_writing)
        OliveCard(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
          TextField(
            key: const Key('journalField'), controller: _text, autofocus: true, minLines: 4, maxLines: 12, maxLength: 2000,
            decoration: const InputDecoration(border: InputBorder.none, hintText: 'Write'),
          ),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: <Widget>[
            OliveButton('Not now', kind: OliveButtonKind.ghost, onPressed: () => setState(() {
                  _writing = false;
                  _text.clear();
                })),
            const SizedBox(width: 8),
            OliveButton('Keep it', key: const Key('journalKeep'), onPressed: () => unawaited(_save())),
          ]),
        ]))
      else
        OliveButton('New entry', key: const Key('journalNew'), icon: 'pencil', full: true, onPressed: () => setState(() => _writing = true)),
      if (_entries.isNotEmpty)
        OliveCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          for (int i = 0; i < _entries.length; i++) ...<Widget>[
            if (i > 0) const Divider(height: 20),
            Column(key: Key('journalEntry.${_entries[i].id}'), crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Text(friendlyDate(_entries[i].createdAt), style: OliveText.strong(context)),
              Text(_entries[i].body, maxLines: 4, overflow: TextOverflow.ellipsis, style: OliveText.body(context)),
            ]),
          ],
        ])),
      _fine(context, 'Nobody suggests what to write. Nothing here is read.'),
    ]);
  }
}

// ================================================================ ladder ===
const Map<Grant, (String, String, String)> _rungCopy = <Grant, (String, String, String)>{
  Grant.ownList: ('Your list', 'Nobody checks it first.', 'list'),
  Grant.journalAbsolute: ('Your journal', 'Only you can open it.', 'lock'),
  Grant.ownCalendar: ('Your calendar', 'You add and edit your own things.', 'calendar'),
  Grant.publishAvailability: ('Your free times', 'You publish when you are free.', 'clock'),
  Grant.curateArchive: ('Your archive', 'You choose what to hide.', 'image'),
  Grant.ownExport: ('Your own copy', 'Take a copy of your data.', 'download'),
  Grant.everything: ('Everything', 'Guardianship closes. It is all yours.', 'key'),
};

/// "What is yours": every step with what it gave her, opened by age, and honest about the next ones and about the one
/// that stays with her guardians (the send-time guard, on their side, always). A step opened is a tap into the
/// thing itself. Nobody is told when she opens one.
class TeenLadderScreen extends StatefulWidget {
  const TeenLadderScreen({super.key, required this.age, required this.destination, this.repository, this.onPreview, this.onFullLadder});
  final int age;

  /// The screen a step opens, or null when it has none here (the row is then a plain statement, not a button).
  final Widget? Function(BuildContext context, Grant grant) destination;
  final LadderRepository? repository;

  /// 'What happens at 18' before she is 18 (a read-only preview). Null = no row.
  final VoidCallback? onPreview;

  /// The older, fuller ladder with what was said when each step opened.
  final VoidCallback? onFullLadder;

  @override
  State<TeenLadderScreen> createState() => _TeenLadderState();
}

class _TeenLadderState extends State<TeenLadderScreen> {
  Map<Grant, int> _later = const <Grant, int>{};

  @override
  void initState() {
    super.initState();
    unawaited(() async {
      try {
        final LadderState? s = await (widget.repository ?? LadderRepository.forChild()).load();
        if (s != null && mounted) setState(() => _later = s.agesLater);
      } catch (_) {}
    }());
  }

  int _ageOf(Rung r) => _later[r.grant] ?? r.age;

  @override
  Widget build(BuildContext context) {
    final List<Rung> rungs = <Rung>[for (final Rung r in kLadder) r.withAge(_ageOf(r))];
    return TeenPage(title: 'What is yours', bodyKey: const Key('teenLadder'), children: <Widget>[
      Text('This is what is yours at your age. The rest opens as you grow, and nothing here can be taken back.',
          style: OliveText.body(context)),
      OliveRowGroup(children: <Widget>[
        for (final Rung r in rungs)
          Builder(builder: (BuildContext c) {
            final (String title, String sub, String icon) = _rungCopy[r.grant]!;
            final bool open = widget.age >= r.age;
            final Widget? to = open ? widget.destination(c, r.grant) : null;
            return OliveRow(
              key: Key('rung.${r.grant.name}'),
              title: title, sub: open ? 'Yours now. $sub' : 'Opens at ${r.age}. $sub', icon: open ? icon : 'lock',
              tone: open ? OliveTone.pri : OliveTone.quiet,
              trailing: OliveChip(open ? 'Mine' : 'At ${r.age}', tone: open ? OliveTone.ok : OliveTone.quiet, small: true),
              onTap: to == null ? null : () => _push(c, to),
            );
          }),
      ]),
      const OliveNotice(
        key: Key('ladderNoLower'),
        text: 'Nobody can lower a step. Both of your guardians together can ask to move one later, never earlier.'),
      const OliveCard(variant: OliveCardVariant.flat, child: Row(children: <Widget>[
        OliveIcon('clock', size: 20, strokeWidth: 2),
        SizedBox(width: 12),
        Expanded(child: Text('The send-time guard stays on your guardians’ side, always.', key: Key('ladderGuard'))),
      ])),
      if (widget.age < kHandoverAge && widget.onPreview != null)
        OliveButton('Show me what happens at 18', key: const Key('ladderPreview18'), kind: OliveButtonKind.ghost, full: true, onPressed: widget.onPreview),
      if (widget.onFullLadder != null)
        OliveRowGroup(children: <Widget>[
          OliveRow(key: const Key('ladderFull'), title: 'The whole ladder', sub: 'What was said when each step opened', icon: 'layers', onTap: widget.onFullLadder),
        ]),
      _fine(context, 'Nobody is told when you open one of these.'),
    ]);
  }
}

// ==================================================================== Me ===
/// One row of Me: where the settings-like things live, because the child shell has none. A row whose builder is
/// null is not drawn; a row for a step she has not reached is shown plainly with its age and goes nowhere.
class TeenMeEntry {
  const TeenMeEntry(this.id, this.title, this.sub, this.icon, {this.opensAt = 0, this.build});
  final String id;
  final String title;
  final String sub;
  final String icon;
  final int opensAt;
  final Widget Function(BuildContext context)? build;
}

class TeenMeScreen extends StatelessWidget {
  const TeenMeScreen({super.key, required this.age, required this.entries});
  final int age;
  final List<TeenMeEntry> entries;

  @override
  Widget build(BuildContext context) {
    return TeenPage(title: 'Me', bodyKey: const Key('teenMe'), children: <Widget>[
      OliveRowGroup(children: <Widget>[
        for (final TeenMeEntry e in entries)
          Builder(builder: (BuildContext c) {
            final bool open = age >= e.opensAt && e.build != null;
            return OliveRow(
              key: Key('me.${e.id}'), title: e.title, sub: age >= e.opensAt ? e.sub : 'Opens at ${e.opensAt}', icon: age >= e.opensAt ? e.icon : 'lock',
              tone: age >= e.opensAt ? OliveTone.pri : OliveTone.quiet,
              trailing: e.opensAt > 0 ? OliveChip(age >= e.opensAt ? 'Mine' : 'At ${e.opensAt}', tone: age >= e.opensAt ? OliveTone.ok : OliveTone.quiet, small: true) : null,
              onTap: open ? () => _push(c, e.build!(c)) : null,
            );
          }),
      ]),
      _fine(context, 'These are yours. No one is told when you open one.'),
    ]);
  }
}
