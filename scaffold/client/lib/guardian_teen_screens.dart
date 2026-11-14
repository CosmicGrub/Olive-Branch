// OLIVE BRANCH — what a grown-up sees of a teen, and the grown-up's half of the 18 handover. UNVERIFIED until CI runs it
// (client/test/guardian_teen_test.dart). Mockups r3a-13-guardian, r3a-18-heads-g, r3a-18-after-g. MASTERFILE §21, P7.
//
// NOT WIRED INTO guardian_home.dart or the settings hub: those belong to the settings-hub work (#166). These are
// complete screens with a typed constructor, ready to be one row there. Until that row exists they are reachable only
// from tests.
//
// What a grown-up sees here is exactly what teen_logic.dart hands them: the free times she published, the events she
// shared WITH THIS grown-up ([eventsSharedWith]), and what she agreed to in answer to an ask. The things that stay with
// her are listed next to the things that are shown, with locks, in the same words as her own privacy page.
//
// Honest about the network: asks and notes are kept on this device. They reach her tablet when the two are connected,
// and that transport is not built yet, so the screens say "waiting" and never "sent".
import 'dart:async';

import 'package:flutter/material.dart';

import 'teen_logic.dart';
import 'teen_screens.dart';
import 'teen_store.dart';
import 'ui/olive_base.dart';
import 'ui/olive_controls.dart';
import 'ui/olive_feedback.dart';
import 'ui/olive_palette.dart';
import 'ui/olive_surfaces.dart';

// ================================================================= at 13-17 ===
/// "{name} at 15: what you see", with the contract on the page, and the one way to ask for more.
class GuardianTeenSeesScreen extends StatefulWidget {
  const GuardianTeenSeesScreen({
    super.key, required this.childName, required this.age, required this.guardianId, this.repository, this.clock,
  });
  final String childName;
  final int age;

  /// Which grown-up is looking (the contact id her events were shared with).
  final String guardianId;
  final TeenRepository? repository;
  final DateTime Function()? clock;

  @override
  State<GuardianTeenSeesScreen> createState() => _GuardianTeenSeesState();
}

class _GuardianTeenSeesState extends State<GuardianTeenSeesScreen> {
  late final TeenRepository _repo = widget.repository ?? TeenRepository.forChild();
  List<TeenEvent> _events = const <TeenEvent>[];
  FreeTimes _free = const FreeTimes();
  AskLedger _ledger = const AskLedger();

  DateTime _now() => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final List<TeenEvent> e = await _repo.events();
      final FreeTimes f = await _repo.freeTimes();
      final AskLedger l = await _repo.asks();
      if (mounted) {
        setState(() {
          _events = e;
          _free = f;
          _ledger = l;
        });
      }
    } catch (_) {}
  }

  Future<void> _ask(ShareKind k) async {
    final AskLedger? next = _ledger.ask('a${_now().microsecondsSinceEpoch}', widget.guardianId, k.name, _now(), herAge: widget.age);
    if (next == null) return;
    setState(() => _ledger = next);
    try {
      await _repo.saveAsks(next);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("That couldn't be kept just now.")));
    }
  }

  String _askState(ShareKind k) {
    final AskCheck c = _ledger.canAsk(widget.guardianId, k.name, _now(), herAge: widget.age);
    if (c.ok) return '';
    return switch (c.reason) {
      'pending' => 'Asked. Waiting for ${widget.childName}.',
      'already_sharing' => '${widget.childName} shares this with you.',
      'waiting' => '${widget.childName} said no. You can ask again on ${teenShortDate(c.waitUntil!)}.',
      _ => '',
    };
  }

  @override
  Widget build(BuildContext context) {
    final List<(String, String)> people = teenGrownUps(context);
    final List<String> others = <String>[for (final (String id, String n) in people) if (id != widget.guardianId) n];
    final List<TeenEvent> mine = eventsSharedWith(_events, widget.guardianId);
    final bool showFree = widget.age >= kFreeTimesAge && _free.published;
    final List<ShareKind> askable = <ShareKind>[
      for (final ShareKind k in ShareKind.values)
        if (widget.age >= k.minAge && !(k == ShareKind.freeTimes && showFree)) k,
    ];
    return TeenPage(title: '${widget.childName} at ${widget.age}', bodyKey: const Key('guardianTeenSees'), children: <Widget>[
      if (showFree)
        OliveCard(key: const Key('guardianFree'), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          Text('${widget.childName} published this', style: OliveText.cap(context)),
          const SizedBox(height: 4),
          Text(_free.describe(), style: OliveText.body(context)),
        ])),
      OliveCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Text('Shared with you', style: OliveText.head(context)),
        const SizedBox(height: 6),
        if (mine.isEmpty)
          Text('Nothing yet. ${widget.childName} chooses what to show you.', key: const Key('guardianNoEvents'), style: OliveText.body(context))
        else
          for (final TeenEvent e in mine)
            Padding(padding: const EdgeInsets.only(top: 4), child: Text('${e.title} · ${teenShortDate(DateTime(e.year, e.month, e.day))}',
                key: Key('guardianEvent.${e.id}'), style: OliveText.body(context))),
      ])),
      OliveCard(key: const Key('guardianStays'), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Text('What stays with ${widget.childName}', style: OliveText.head(context)),
        const OliveRow(title: 'Her journal', sub: 'Nobody can open it', icon: 'lock', tone: OliveTone.quiet),
        if (others.isNotEmpty)
          OliveRow(title: 'Her messages with ${teenJoinNames(others)}', sub: 'Only the two of them', icon: 'lock', tone: OliveTone.quiet),
        const OliveRow(title: 'Where she is', sub: 'Never', icon: 'lock', tone: OliveTone.quiet),
      ])),
      OliveCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Text('Ask ${widget.childName} to share something', style: OliveText.head(context)),
        const SizedBox(height: 4),
        Text('You can ask. ${widget.childName} can say no, and the answer is final for a week.', style: OliveText.cap(context)),
        for (final ShareKind k in askable)
          Builder(builder: (BuildContext c) {
            final String st = _askState(k);
            return OliveRow(
              key: Key('askRow.${k.name}'), title: 'Ask to see ${k.askWords}', sub: st.isEmpty ? null : st, icon: 'hand',
              trailing: st.isEmpty ? OliveButton('Ask', key: Key('ask.${k.name}'), size: OliveButtonSize.sm, onPressed: () => unawaited(_ask(k))) : null,
            );
          }),
        const SizedBox(height: 6),
        Text('Asks wait here until the two tablets are connected. They are not sent yet.', key: const Key('askParked'), style: OliveText.cap(context)),
      ])),
      Text('Nothing here shows where ${widget.childName} is.', style: OliveText.cap(context)),
    ]);
  }
}

// ===================================================== the 18 handover, theirs ===
/// "{name} turns 18 in 90 days", for the grown-up: what will close, what stays, what is hers to decide, a note to her in
/// the grown-up's own words, and what they would like if she chooses to stay in touch. Nothing here asks them to do
/// anything except, if they want, write that note.
class GuardianHandoverScreen extends StatefulWidget {
  const GuardianHandoverScreen({
    super.key, required this.childName, required this.guardianId, this.monthDay, this.after = false, this.repository,
  });
  final String childName;
  final String guardianId;
  final String? monthDay;

  /// The day after: the account is hers, the guardian tools have closed.
  final bool after;
  final TeenRepository? repository;

  @override
  State<GuardianHandoverScreen> createState() => _GuardianHandoverState();
}

class _GuardianHandoverState extends State<GuardianHandoverScreen> {
  late final TeenRepository _repo = widget.repository ?? TeenRepository.forChild();
  final TextEditingController _note = TextEditingController();
  StayInTouch _touch = const StayInTouch();
  bool _noteKept = false;

  @override
  void initState() {
    super.initState();
    unawaited(() async {
      try {
        final Map<String, String> n = await _repo.notes();
        final StayInTouch t = await _repo.touch();
        if (!mounted) return;
        setState(() {
          _note.text = n[widget.guardianId] ?? '';
          _touch = t;
        });
      } catch (_) {}
    }());
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _keepNote() async {
    try {
      await _repo.saveNote(widget.guardianId, _note.text);
      if (mounted) setState(() => _noteKept = true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("That couldn't be kept just now.")));
    }
  }

  Future<void> _want(Channel c, bool on) async {
    final Set<Channel> w = <Channel>{...(_touch.wanted[widget.guardianId] ?? const <Channel>{})};
    on ? w.add(c) : w.remove(c);
    final StayInTouch t = _touch.want(widget.guardianId, w);
    setState(() => _touch = t);
    try {
      await _repo.saveTouch(t);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final String? date = teenMonthDay(widget.monthDay);
    final String name = widget.childName;
    final List<(String, String)> people = teenGrownUps(context);
    final List<String> others = <String>[for (final (String id, String n) in people) if (id != widget.guardianId) n];
    final TouchState st = _touch.stateWith(widget.guardianId);
    if (widget.after) {
      return TeenPage(title: 'Today', bodyKey: const Key('guardianAfter18'), children: <Widget>[
        OliveNotice(tone: OliveTone.accent, title: '$name is 18', text: 'Her account is hers now. Guardian tools for $name have closed.'),
        OliveRowGroup(children: <Widget>[
          const OliveRow(title: 'Your record stays', sub: 'What you agreed and logged is unchanged.', icon: 'check'),
          const OliveRow(title: 'Your own account stays', sub: 'So do the messages you sent, as you sent them.', icon: 'check'),
          OliveRow(title: '$name’s calendar, devices and free times', sub: 'No longer in your hands.', icon: 'lock', tone: OliveTone.quiet),
        ]),
        if (st == TouchState.ready)
          OliveRow(key: const Key('afterStayReady'), title: name, sub: 'Messages and calls, by her choice', icon: 'users'),
      ]);
    }
    return TeenPage(title: '$name turns 18', bodyKey: const Key('guardianHandover'), children: <Widget>[
      OliveNotice(
        key: const Key('guardianHeadsUp'), tone: OliveTone.accent,
        title: date == null ? '$name turns 18 soon' : '$name turns 18 on $date',
        text: 'Guardianship closes that day.${others.isEmpty ? '' : ' ${teenJoinNames(others)} has the same note.'}'),
      OliveCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Text('On the day', style: OliveText.head(context)),
        const OliveRow(title: 'Everything becomes hers', sub: 'Her messages, photos, archive and journal.', icon: 'lock'),
        const OliveRow(title: 'Guardian tools close', sub: 'Her calendar, her devices and her availability are no longer yours to manage.', icon: 'eyeoff'),
        const OliveRow(title: 'Your account stays', sub: 'So do your own messages, as you sent them.', icon: 'check'),
      ])),
      OliveCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Text('Write $name a note', style: OliveText.head(context)),
        const SizedBox(height: 6),
        TextField(
          key: const Key('guardianNoteField'), controller: _note, minLines: 3, maxLines: 8, maxLength: kHandoverNoteMax,
          decoration: const InputDecoration(labelText: 'For the day she is 18', hintText: 'In your own words', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 6),
        Text('She can read it, or not. It is kept with what is hers. The app writes none of it.', style: OliveText.cap(context)),
        const SizedBox(height: 8),
        OliveButton('Keep my note', key: const Key('guardianNoteKeep'), kind: OliveButtonKind.tonal, full: true, onPressed: () => unawaited(_keepNote())),
        if (_noteKept) const Padding(padding: EdgeInsets.only(top: 8), child: OliveBanner('Kept for the day.', tone: OliveTone.ok, icon: 'check', key: Key('guardianNoteKept'))),
      ])),
      OliveCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Text('If she chooses to stay in touch', style: OliveText.head(context)),
        const SizedBox(height: 4),
        Text('Only what you both choose goes live. She goes first; you say what you would like.', style: OliveText.cap(context)),
        for (final Channel c in Channel.values)
          CheckRow(key: Key('want.${c.name}'), title: c.title, sub: c.sub, value: (_touch.wanted[widget.guardianId] ?? const <Channel>{}).contains(c),
              onChanged: (bool v) => unawaited(_want(c, v))),
        const SizedBox(height: 4),
        Text('Messages and calls start when the tablets are connected. Nothing is sent from here yet.', key: const Key('guardianTouchParked'), style: OliveText.cap(context)),
      ])),
    ]);
  }
}
