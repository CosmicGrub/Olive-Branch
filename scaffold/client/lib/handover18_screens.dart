// OLIVE BRANCH — the 18 handover, her side: the heads-up, her choices, what she gets, staying in touch and the
// last page. UNVERIFIED until CI runs it (client/test/handover18_test.dart and client/test/teen_postures_test.dart).
// Prototype: mod-child.js k.handover / k.copy / kid.handover; round-3 mockups r3a-18-heads-c, -paths, -whatyouget,
// -stay, -goodbye. MASTERFILE §21.6, §21.7, §9.8.4.
//
// ALL OF THIS WORKS WITH NO NETWORK, AND NOTHING NETWORK-DEPENDENT IS FAKED:
//   - Her choice is recorded on this tablet ([TeenRepository.saveHandover]). Take and go and 'both' make her copy
//     FOR REAL: one plain file in the documents folder, read back and checked (own_copy.dart). The app's own copy
//     on this tablet is kept 30 days after take and go and then removed, but only once her copy is saved and checked.
//   - Closing her grown-ups' access and removing the server's copy are ONLINE steps. This tablet says so, plainly,
//     and offers the real connected take-and-go (take_and_go_screen.dart) behind a button that fails honestly with
//     no connection. A recorded choice is never shown as if it had closed anything.
//   - Staying in touch needs BOTH sides, channel by channel. What she offers and what a grown-up asked for are kept
//     here; 'Ready' means both said yes. Messages and calls themselves start when this tablet is online: that is
//     said on the page, not implied.
//
// The tone is the mockups': a dignified goodbye, not a sale. No default, no nudge, none of the three paths marked as
// better (§21.6), no summary of what she did here and no number anywhere (P1-P11, MASTERFILE §2.1).
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'grownup_labels.dart';
import 'local_services.dart';
import 'own_copy.dart';
import 'take_and_go_screen.dart' show TakeAndGoScreen;
import 'teen_logic.dart';
import 'teen_screens.dart';
import 'teen_store.dart';
import 'ui/olive_art.dart';
import 'ui/olive_base.dart';
import 'ui/olive_controls.dart';
import 'ui/olive_feedback.dart';
import 'ui/olive_palette.dart';
import 'ui/olive_surfaces.dart';

void _go(BuildContext context, Widget screen) =>
    unawaited(Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen)));

// ============================================================== heads-up ===
/// Shown in the months before she is 18: a quiet page that says what will be hers and that nothing has to be decided
/// now. No one is told whether she opened it. [monthDay] is the ChildBirthday's 'MM-DD'.
class HandoverHeadsUpScreen extends StatelessWidget {
  const HandoverHeadsUpScreen({super.key, this.monthDay, this.onChoices, this.onWhatYouGet, this.onStayInTouch});
  final String? monthDay;
  final VoidCallback? onChoices;
  final VoidCallback? onWhatYouGet;
  final VoidCallback? onStayInTouch;

  @override
  Widget build(BuildContext context) {
    final String? date = teenMonthDay(monthDay);
    return TeenPage(title: 'Turning 18', bodyKey: const Key('handoverHeadsUp'), children: <Widget>[
      Text(date == null ? 'Soon, this is all yours.' : 'On $date, this is all yours.',
          key: const Key('headsUpLead'), style: OliveText.title(context)),
      Text('Your messages, photos, archive and journal. You decide what happens to them. Nobody else.', style: OliveText.body(context)),
      OliveRowGroup(children: <Widget>[
        OliveRow(key: const Key('headsUpTake'), title: HandoverChoice.take.title, sub: HandoverChoice.take.sub, icon: 'download', onTap: onChoices),
        OliveRow(key: const Key('headsUpKeep'), title: HandoverChoice.keep.title, sub: HandoverChoice.keep.sub, icon: 'leaf', onTap: onChoices),
        OliveRow(key: const Key('headsUpStay'), title: 'Stay in touch', sub: 'Only if you and they both choose', icon: 'users', onTap: onStayInTouch),
      ]),
      if (onWhatYouGet != null)
        OliveRowGroup(children: <Widget>[
          OliveRow(key: const Key('headsUpWhatYouGet'), title: 'What you get, in plain words', sub: 'What is in it and what is not', icon: 'receipt', onTap: onWhatYouGet),
        ]),
      const OliveNotice(key: Key('headsUpNobodyTold'), text: 'No one is told whether you read this.'),
    ]);
  }
}

/// The card on her home that opens the heads-up (in the months before 18) or her choices (from 18). A quiet row, no badge.
class HandoverCard extends StatelessWidget {
  const HandoverCard({super.key, required this.atHandover, required this.onTap});
  final bool atHandover;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => OliveCard(
        key: const Key('handoverCard'), variant: OliveCardVariant.interactive, onTap: onTap,
        semanticLabel: atHandover ? 'Your own space' : 'Turning 18',
        child: Row(children: <Widget>[
          const OliveIcon('key', size: 24, strokeWidth: 2),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: <Widget>[
            Text(atHandover ? 'Your own space' : 'Turning 18', style: OliveText.strong(context, size: 16)),
            Text(atHandover ? 'Your choices, whenever you want them.' : 'A page for when you want it. Nothing to decide today.',
                style: OliveText.cap(context)),
          ])),
        ]),
      );
}

// ================================================================== paths ===
/// Her choices at 18. Four equal rows and no default: take and go, keep as an archive, both, or someday for her own
/// family. Tapping one records it on this tablet; the page then says exactly what that did and did not do.
/// [preview] (before she is 18) shows the same page and records nothing.
class HandoverPathsScreen extends StatefulWidget {
  const HandoverPathsScreen({
    super.key, required this.childName, this.preview = false, this.repository, this.clock,
    this.services, this.documentsDirectory, this.childId,
  });
  final String childName;
  final bool preview;
  final TeenRepository? repository;
  final DateTime Function()? clock;
  final LocalServices? services;
  final Future<Directory> Function()? documentsDirectory;
  final String? childId;

  @override
  State<HandoverPathsScreen> createState() => _HandoverPathsState();
}

class _HandoverPathsState extends State<HandoverPathsScreen> {
  late final TeenRepository _repo = widget.repository ?? TeenRepository.forChild();
  HandoverRecord _rec = const HandoverRecord();

  DateTime _now() => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final HandoverRecord r = await _repo.handover();
      if (mounted) setState(() => _rec = r);
    } catch (_) {}
  }

  Future<void> _choose(HandoverChoice c) async {
    if (widget.preview) return;
    final HandoverRecord r = _rec.chose(c, _now());
    setState(() => _rec = r);
    try {
      await _repo.saveHandover(r);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("That couldn't be kept just now.")));
      return;
    }
    if (!mounted || !c.makesCopy) return;
    _go(context, WhatYouGetScreen(
      childName: widget.childName, repository: _repo, clock: widget.clock, services: widget.services,
      documentsDirectory: widget.documentsDirectory, childId: widget.childId, afterCopyToGoodbye: true));
  }

  String _state() {
    final HandoverChoice? c = _rec.choice;
    if (c == null) return '';
    return switch (c) {
      HandoverChoice.take => _rec.copyMadeAt == null
          ? 'You chose to take your data and go. Your copy is not made yet.'
          : 'You chose to take your data and go. Your copy is saved on this tablet.',
      HandoverChoice.keep => 'Kept. It is yours to look after.',
      HandoverChoice.both => _rec.copyMadeAt == null
          ? 'You chose both. Your copy is not made yet.'
          : 'You chose both. Your copy is saved and the archive goes on.',
      HandoverChoice.later => 'Noted. Nothing is needed from you.',
    };
  }

  @override
  Widget build(BuildContext context) {
    final bool locked = !widget.preview && !_rec.canChange(_now());
    return TeenPage(title: 'Your choices', bodyKey: const Key('handoverPaths'), children: <Widget>[
      if (widget.preview) const OliveBanner('A preview of what you will see at 18.', icon: 'info', key: Key('handoverPreviewBanner')),
      Text('Thank you for growing up here. These are your choices. None of them has a deadline you have to meet today.',
          style: OliveText.body(context)),
      OliveCard(child: Column(children: <Widget>[
        for (final HandoverChoice c in HandoverChoice.values)
          RadioRow(
            key: Key('path.${c.name}'), title: c.title, sub: c.sub,
            icon: switch (c) { HandoverChoice.take => 'download', HandoverChoice.keep => 'leaf', HandoverChoice.both => 'layers', HandoverChoice.later => 'heart' },
            selected: _rec.choice == c,
            onSelected: widget.preview || locked ? null : () => unawaited(_choose(c)),
          ),
      ])),
      const OliveNotice(key: Key('pathsNoBetter'), text: 'None of these is marked as better. Moving between them is fine for 30 days.'),
      if (_rec.chosen && !widget.preview)
        OliveBanner(_state(), tone: OliveTone.ok, icon: 'check', key: const Key('pathsState')),
      if (locked) const OliveBanner('This was done. Your copy is yours.', key: Key('pathsLocked')),
      OliveRowGroup(children: <Widget>[
        OliveRow(
          key: const Key('pathsStayInTouch'), title: 'Staying in touch', sub: 'Separate. Needs both sides.', icon: 'users',
          onTap: () => _go(context, StayInTouchScreen(repository: _repo, preview: widget.preview)),
        ),
      ]),
    ]);
  }
}

// ============================================================ what you get ===
/// What is in her copy and what is not, in plain words with no numbers, and the button that makes it. 'Make my
/// copy' writes the file for real. Nobody is told. [afterCopyToGoodbye] (the take-and-go path) offers the last page
/// once the copy is saved.
class WhatYouGetScreen extends StatefulWidget {
  const WhatYouGetScreen({
    super.key, required this.childName, this.repository, this.clock, this.services, this.documentsDirectory,
    this.childId, this.afterCopyToGoodbye = false,
  });
  final String childName;
  final TeenRepository? repository;
  final DateTime Function()? clock;
  final LocalServices? services;
  final Future<Directory> Function()? documentsDirectory;
  final String? childId;
  final bool afterCopyToGoodbye;

  @override
  State<WhatYouGetScreen> createState() => _WhatYouGetState();
}

class _WhatYouGetState extends State<WhatYouGetScreen> {
  late final TeenRepository _repo = widget.repository ?? TeenRepository.forChild();
  HandoverRecord _rec = const HandoverRecord();
  OwnCopyResult? _result;
  bool _working = false;
  bool _failed = false;

  DateTime _now() => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    unawaited(() async {
      try {
        final HandoverRecord r = await _repo.handover();
        if (mounted) setState(() => _rec = r);
      } catch (_) {}
    }());
  }

  Future<void> _make() async {
    if (_working) return;
    setState(() {
      _working = true;
      _failed = false;
    });
    try {
      final OwnCopyResult res = await saveOwnCopy(
        widget.services ?? LocalServices.current, childName: widget.childName, now: _now(),
        childId: widget.childId, documentsDirectory: widget.documentsDirectory);
      if (!mounted) return;
      // Recorded only when the file was read back and matches. A copy that did not check is not a saved copy.
      if (res.verified && _rec.chosen && _rec.choice!.makesCopy) {
        final HandoverRecord r = _rec.copyMade(_now(), res.path);
        await _repo.saveHandover(r);
        if (!mounted) return;
        _rec = r;
      }
      setState(() {
        _working = false;
        _result = res;
        _failed = !res.verified;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _working = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool saved = _result != null && _result!.verified;
    return TeenPage(title: 'What you get', bodyKey: const Key('whatYouGet'), children: <Widget>[
      OliveCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        _head(context, 'What is in it'),
        for (final (String t, String s) in ownCopyIncludes)
          Padding(padding: const EdgeInsets.only(top: 8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            Text(t, style: OliveText.strong(context, size: 15)),
            Text(s, style: OliveText.cap(context)),
          ])),
      ])),
      OliveCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        _head(context, 'The shape of it'),
        const SizedBox(height: 6),
        Text(ownCopyForm, key: const Key('copyForm'), style: OliveText.body(context)),
        const SizedBox(height: 4),
        Text('It goes to this tablet, not to any grown-up.', style: OliveText.cap(context)),
      ])),
      OliveCard(variant: OliveCardVariant.flat, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        _head(context, 'What is not'),
        const SizedBox(height: 6),
        Text(ownCopyExcludes, key: const Key('copyExcludes'), style: OliveText.cap(context)),
      ])),
      const OliveNotice(key: Key('copyNotHere'), text: ownCopyNotHere),
      OliveButton(saved ? 'Make it again' : 'Make my copy', key: const Key('makeCopy'), icon: 'download', size: OliveButtonSize.lg, full: true,
          onPressed: _working ? null : () => unawaited(_make())),
      Text('Nobody is told.', key: const Key('copyNobodyTold'), style: OliveText.cap(context)),
      if (saved)
        OliveBanner('Saved to this tablet: ${_result!.path}', tone: OliveTone.ok, icon: 'check', key: const Key('copySaved')),
      if (_failed)
        const OliveBanner('That could not be saved just now. Nothing was changed.', tone: OliveTone.warn, icon: 'warn', key: Key('copyFailed')),
      if (saved && _rec.chosen && _rec.choice == HandoverChoice.take) ...<Widget>[
        OliveCard(key: const Key('copyServerSteps'), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          _head(context, 'Closing your grown-ups’ access'),
          const SizedBox(height: 6),
          Text('That part is done online, and this tablet cannot do it with no connection. '
              'The button below tries it for real and tells you plainly if it cannot. '
              'On this tablet, our copy is kept for 30 days and then removed.',
              style: OliveText.body(context)),
          const SizedBox(height: 10),
          OliveButton('Close it now', key: const Key('copyCloseAccess'), kind: OliveButtonKind.tonal, full: true,
              onPressed: () => _go(context, TakeAndGoScreen(childName: widget.childName, childId: widget.childId ?? LocalServices.current.childId))),
        ])),
      ],
      if (saved && widget.afterCopyToGoodbye)
        OliveButton('Your last page here', key: const Key('copyToGoodbye'), kind: OliveButtonKind.ghost, full: true,
            onPressed: () => _go(context, HandoverGoodbyeScreen(childName: widget.childName, repository: _repo))),
    ]);
  }
}

Widget _head(BuildContext context, String t) => Text(t, style: OliveText.head(context));

// ============================================================ stay in touch ===
/// Staying in touch, by choice on BOTH sides. She goes first: what she offers, channel by channel. Beside it, what each
/// grown-up asked for. Only the overlap is live. Either side ends it with one tap and no reason.
class StayInTouchScreen extends StatefulWidget {
  const StayInTouchScreen({super.key, this.repository, this.preview = false});
  final TeenRepository? repository;
  final bool preview;

  @override
  State<StayInTouchScreen> createState() => _StayInTouchState();
}

class _StayInTouchState extends State<StayInTouchScreen> {
  late final TeenRepository _repo = widget.repository ?? TeenRepository.forChild();
  StayInTouch _t = const StayInTouch();

  @override
  void initState() {
    super.initState();
    unawaited(() async {
      try {
        final StayInTouch t = await _repo.touch();
        if (mounted) setState(() => _t = t);
      } catch (_) {}
    }());
  }

  Future<void> _set(StayInTouch t) async {
    if (widget.preview) return;
    setState(() => _t = t);
    try {
      await _repo.saveTouch(t);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("That couldn't be kept just now.")));
    }
  }

  (String, OliveTone) _words(TouchState s) => switch (s) {
        TouchState.ready => ('Ready', OliveTone.ok),
        TouchState.waitingForThem => ('Waiting for them', OliveTone.quiet),
        TouchState.waitingForHer => ('Waiting for you', OliveTone.quiet),
        TouchState.ended => ('Ended', OliveTone.quiet),
        TouchState.notAsked => ('Not asked', OliveTone.quiet),
      };

  @override
  Widget build(BuildContext context) {
    final List<(String, String)> people = teenGrownUps(context);
    return TeenPage(title: 'Staying in touch', bodyKey: const Key('stayInTouch'), children: <Widget>[
      Text('If you both choose it. You offer what you are willing to share, they ask for what they would like, and only the overlap happens.',
          style: OliveText.body(context)),
      OliveCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        _head(context, 'What you offer'),
        for (final Channel c in Channel.values)
          CheckRow(key: Key('offer.${c.name}'), title: c.title, sub: c.sub, value: _t.offered.contains(c),
              onChanged: widget.preview ? null : (bool v) => unawaited(_set(_t.offer(c, v)))),
      ])),
      OliveCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        _head(context, 'What they asked for'),
        if (people.isEmpty)
          Padding(padding: const EdgeInsets.only(top: 6), child: Text('No grown-ups are connected to this tablet yet.', style: OliveText.cap(context))),
        for (final (String id, String name) in people)
          Builder(builder: (BuildContext c) {
            final TouchState s = _t.stateWith(id);
            final (String word, OliveTone tone) = _words(s);
            final Set<Channel> want = _t.wanted[id] ?? const <Channel>{};
            return OliveRow(
              key: Key('touch.$id'), title: name,
              sub: want.isEmpty ? 'Has not asked for anything' : <String>[for (final Channel ch in Channel.values) if (want.contains(ch)) ch.title].join(', '),
              leading: OliveAvatar(name),
              trailing: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: <Widget>[
                OliveChip(word, tone: tone, small: true, key: Key('touchState.$id')),
                if (s != TouchState.ended && s != TouchState.notAsked && !widget.preview)
                  Padding(padding: const EdgeInsets.only(top: 4), child: OliveButton('End this', key: Key('touchEnd.$id'),
                      size: OliveButtonSize.sm, kind: OliveButtonKind.ghost, onPressed: () => unawaited(_set(_t.end(id))))),
              ]),
            );
          }),
      ])),
      const OliveNotice(key: Key('touchBothSides'), text: 'Only what you both choose goes live. Messages and calls start when this tablet is online.'),
      const Text('Either of you can end this with one tap, with no reason asked and no notice.', key: Key('touchEndAnyTime')),
    ]);
  }
}

// ================================================================= goodbye ===
/// Her last page, a dignified goodbye and not a sale: one scene she knows, the notes her grown-ups wrote in their own
/// words (if they wrote any), and the two clear choices. No confetti, no mascot, no numbers, no summary of what she did.
class HandoverGoodbyeScreen extends StatefulWidget {
  const HandoverGoodbyeScreen({super.key, required this.childName, this.repository, this.onTake, this.onKeep});
  final String childName;
  final TeenRepository? repository;

  /// Take my data and go. Null opens What you get (the real copy).
  final VoidCallback? onTake;
  final VoidCallback? onKeep;

  @override
  State<HandoverGoodbyeScreen> createState() => _GoodbyeState();
}

class _GoodbyeState extends State<HandoverGoodbyeScreen> {
  late final TeenRepository _repo = widget.repository ?? TeenRepository.forChild();
  Map<String, String> _notes = const <String, String>{};

  @override
  void initState() {
    super.initState();
    unawaited(() async {
      try {
        final Map<String, String> n = await _repo.notes();
        if (mounted) setState(() => _notes = n);
      } catch (_) {}
    }());
  }

  /// Records her choice on this tablet (keeping any copy already made), then carries on.
  Future<void> _choose(HandoverChoice c) async {
    try {
      final HandoverRecord now = await _repo.handover();
      if (now.choice != c) await _repo.saveHandover(now.chose(c, DateTime.now()));
    } catch (_) {
      // Not kept: the page that follows says what is true, so nothing is claimed here.
    }
  }

  @override
  Widget build(BuildContext context) {
    final GrownupLabels labels = GrownupLabelScope.of(context);
    final List<(String, String)> from = <(String, String)>[
      for (final MapEntry<String, String> e in _notes.entries) (labels.nameFor(e.key), e.value),
    ];
    return TeenPage(title: '', bodyKey: const Key('handoverGoodbye'), children: <Widget>[
      const ClipRRect(borderRadius: BorderRadius.all(Radius.circular(24)), child: OliveScene('day')),
      Text('You grew up here. It is yours now.', key: const Key('goodbyeLead'), style: OliveText.title(context)),
      if (from.isNotEmpty)
        OliveCard(key: const Key('goodbyeNotes'), variant: OliveCardVariant.tint, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          for (final (String who, String text) in from) ...<Widget>[
            Text('FROM ${who.toUpperCase()}', style: OliveText.label(context)),
            const SizedBox(height: 4),
            Text('“$text”', style: OliveText.body(context)),
            const SizedBox(height: 10),
          ],
          Text('Written by ${teenJoinNames(<String>[for (final (String n, String _) in from) n])}. Olive Branch did not write this.',
              style: OliveText.cap(context)),
        ])),
      OliveButton('Take my data and go', key: const Key('goodbyeTake'), icon: 'download', size: OliveButtonSize.lg, full: true,
          onPressed: widget.onTake ??
              () async {
                await _choose(HandoverChoice.take);
                if (context.mounted) _go(context, WhatYouGetScreen(childName: widget.childName, repository: _repo));
              }),
      OliveButton('Keep it as my archive', key: const Key('goodbyeKeep'), icon: 'leaf', kind: OliveButtonKind.tonal, full: true,
          onPressed: widget.onKeep ??
              () async {
                await _choose(HandoverChoice.keep);
                if (context.mounted) unawaited(Navigator.of(context).maybePop());
              }),
      Text('Nothing is counted or summarised.', key: const Key('goodbyeNothingCounted'), style: OliveText.cap(context)),
    ]);
  }
}
