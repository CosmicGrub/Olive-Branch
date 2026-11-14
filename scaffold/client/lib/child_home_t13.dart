// OLIVE BRANCH — the 13 to 17 home, as a shell: which screen each of its tiles opens, what its 'More' page adds, the
// Today card above the tiles and the 18 handover card. UNVERIFIED until CI runs it (client/test/child_home_t13_test.dart,
// client/test/teen_postures_test.dart). Prototype: mod-child.js homeT1317; round-3 mockups r3a-13-home, r3a-13-me.
//
// WHAT IS DRAWN COMES FROM THE TABLE. child_home_bands.dart holds the tile registry, the band set and the layout, one
// table asserted equal to the prototype's own render (test/parity/vectors/child_home_bands.json). This file adds no
// tile to a band and removes none: it only says where a tile goes ([tile]) and what sits above the tiles ([today]).
// A tile whose destination is null is not drawn (child_home_bands.dart's kTilesWithDestination).
//
// THE BAND SPLIT. The client keeps one 't13' (13 and up) in the family structure so nothing stored changes. The home
// splits it by AGE, as the prototype does: 13 to 17 is the t1317 home; from 18 the same home carries one more card,
// 'Your own space', which opens her choices (handover18_screens.dart). In the months before 18 that card is the
// heads-up. Her age no longer stops at 17 (child_home_growth.dart).
//
// QUIETING (§21.5): no sleeps countdown here, no prompt deck, no send-time guard on her side, and Play moves to More at
// 14 ('Downtime', a row, not a tile). Nothing is added in their place.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'child_home_bands_ui.dart' show BandMoreExtra;
import 'family_structure_store.dart' show ChildBirthday;
import 'handover18_screens.dart';
import 'journal_screen.dart' show JournalRepository;
import 'local_services.dart';
import 'maturation_ladder.dart' show Grant, LadderViewer, MaturationLadderScreen;
import 'own_copy.dart' show ownCopyForm;
import 'teen_logic.dart';
import 'teen_screens.dart';
import 'teen_store.dart';
import 'wants_needs.dart' show WantsNeedsScreen;

/// Everything the 13 to 17 home needs to know to route a tap, and nothing it could use to look at her.
class TeenShell {
  const TeenShell({
    required this.childName,
    required this.age,
    this.birthday,
    this.repository,
    this.journal,
    this.clock,
    this.childId,
    this.documentsDirectory,
    this.services,
  });
  final String childName;
  final int age;
  final ChildBirthday? birthday;
  final TeenRepository? repository;
  final JournalRepository? journal;
  final DateTime Function()? clock;
  final String? childId;
  final Future<Directory> Function()? documentsDirectory;
  final LocalServices? services;

  TeenRepository get _repo => repository ?? TeenRepository.forChild(childId);

  /// The destination of a t1317 tile that is not one of the shell's older ones, or null for a tile it does not own.
  Widget? tile(BuildContext context, String id) {
    switch (id) {
      case 'cal':
        return TeenCalendarScreen(age: age, repository: _repo, clock: clock);
      case 'privacy':
        return Builder(builder: privacyWithRows);
      case 'journal':
        return TeenJournalScreen(childName: childName, childId: childId, repository: journal, clock: clock);
      case 'ladder':
        return _ladder();
    }
    return null;
  }

  /// The privacy page with its two honest rows wired (the consent log and her free times).
  Widget privacyWithRows(BuildContext context) => TeenPrivacyScreen(
        age: age,
        onConsentLog: () => _open(context, ConsentLogScreen(age: age, repository: _repo, clock: clock)),
        onFreeTimes: () => _open(context, TeenFreeTimesScreen(age: age, repository: _repo)),
      );

  static void _open(BuildContext context, Widget screen) =>
      unawaited(Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen)));

  Widget _ladder() => Builder(builder: (BuildContext context) => TeenLadderScreen(
        age: age,
        destination: (BuildContext c, Grant g) => grantDestination(c, g),
        onPreview: () => _open(context, handoverPaths(preview: true)),
        onFullLadder: () => _open(context, MaturationLadderScreen(childName: childName, childAgeYears: age, viewer: LadderViewer.child)),
      ));

  /// What opening a step of the ladder shows. Archive curation is not built (no child hide control exists yet).
  Widget? grantDestination(BuildContext context, Grant g) => switch (g) {
        Grant.ownList => const WantsNeedsScreen(),
        Grant.journalAbsolute => tile(context, 'journal'),
        Grant.ownCalendar => tile(context, 'cal'),
        Grant.publishAvailability => TeenFreeTimesScreen(age: age, repository: _repo),
        Grant.curateArchive => null,
        Grant.ownExport => whatYouGet(),
        Grant.everything => handoverPaths(),
      };

  Widget handoverPaths({bool preview = false}) => HandoverPathsScreen(
        childName: childName, preview: preview, repository: _repo, clock: clock, services: services,
        documentsDirectory: documentsDirectory, childId: childId);

  Widget whatYouGet() => WhatYouGetScreen(
        childName: childName, repository: _repo, clock: clock, services: services,
        documentsDirectory: documentsDirectory, childId: childId);

  /// The 'your home grows' page's own destinations that are not tiles: free times, her copy, her choices. 'k.archive'
  /// has none yet. Null = the page's button is a plain Okay (ChildGrowScreen.destinationExists).
  Widget? grow(BuildContext context, String dest) => switch (dest) {
        'k.privacy' => Builder(builder: privacyWithRows),
        'k.free' => TeenFreeTimesScreen(age: age, repository: _repo),
        'k.copy' => whatYouGet(),
        'k.handover' => handoverPaths(),
        _ => null,
      };

  /// Me: where the settings-like things live, because the child shell has none. A row for a step she has not reached
  /// says its age and goes nowhere.
  Widget me(BuildContext context) => TeenMeScreen(age: age, entries: <TeenMeEntry>[
        TeenMeEntry('privacy', 'Privacy', 'What your grown-ups can see', 'eye', build: privacyWithRows),
        TeenMeEntry('consent', 'Consent log', 'Every ask and every answer', 'receipt',
            build: (BuildContext c) => ConsentLogScreen(age: age, repository: _repo, clock: clock)),
        TeenMeEntry('free', 'Free times', 'You decide', 'clock', opensAt: kFreeTimesAge,
            build: (BuildContext c) => TeenFreeTimesScreen(age: age, repository: _repo)),
        TeenMeEntry('journal', 'Journal', 'Only you', 'book', build: (BuildContext c) => tile(c, 'journal')!),
        TeenMeEntry('cal', 'Calendar', age >= kOwnCalendarAge ? 'You edit it' : 'You can look at it', 'calendar',
            build: (BuildContext c) => tile(c, 'cal')!),
        TeenMeEntry('copy', 'Your own copy', ownCopyForm, 'download', opensAt: 17, build: (BuildContext c) => whatYouGet()),
        TeenMeEntry('ladder', 'What is yours, and when', 'The whole ladder', 'layers', build: (BuildContext c) => _ladder()),
        TeenMeEntry('handover', atHandover(age) ? 'Your own space' : 'What happens at 18', atHandover(age) ? 'Your choices' : 'A preview', 'key',
            build: (BuildContext c) => handoverPaths(preview: !atHandover(age))),
      ]);

  /// More page rows that are not in the prototype's table: Me.
  List<BandMoreExtra> moreExtras() => <BandMoreExtra>[
        BandMoreExtra(key: 'moreMe', icon: Icons.person_outline, label: 'Me', build: me),
      ];

  /// The card above the tiles: Today, and the handover card when it is time.
  Widget today({required DateTime now, Future<void> Function()? purge}) => TeenHomeTop(
        age: age, now: now, birthday: birthday, shell: this, purge: purge);

  /// True when the heads-up is due (the 90 days before the 18th birthday).
  bool get headsUpDue => birthday != null && handoverHeadsUp(turnsYears: birthday!.turnsYears, sleepsUntil: birthday!.sleepsUntil);
}

/// Today, the handover card, and (from 18, once she has taken and gone and her own copy is saved and checked) the removal
/// of this tablet's copy after 30 days. The removal runs only here, only when [purge] allows it.
class TeenHomeTop extends StatefulWidget {
  const TeenHomeTop({super.key, required this.age, required this.now, required this.shell, this.birthday, this.purge});
  final int age;
  final DateTime now;
  final TeenShell shell;
  final ChildBirthday? birthday;

  /// Removes this tablet's copy of her data. Null = never remove anything.
  final Future<void> Function()? purge;

  @override
  State<TeenHomeTop> createState() => _TeenHomeTopState();
}

class _TeenHomeTopState extends State<TeenHomeTop> {
  @override
  void initState() {
    super.initState();
    final Future<void> Function()? purge = widget.purge;
    if (purge != null && atHandover(widget.age)) {
      unawaited(() async {
        try {
          await purgeIfDue(widget.shell._repo, widget.now, purge);
        } catch (_) {
          // Not removed. It is tried again next time; nothing is said to her.
        }
      }());
    }
  }

  @override
  Widget build(BuildContext context) {
    final TeenShell s = widget.shell;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
      TeenToday(age: widget.age, now: widget.now, repository: s._repo),
      if (atHandover(widget.age))
        Padding(padding: const EdgeInsets.only(top: 10), child: HandoverCard(
            atHandover: true, onTap: () => TeenShell._open(context, s.handoverPaths())))
      else if (s.headsUpDue)
        Padding(padding: const EdgeInsets.only(top: 10), child: HandoverCard(
            atHandover: false,
            onTap: () => TeenShell._open(context, HandoverHeadsUpScreen(
                monthDay: s.birthday?.monthDay,
                onChoices: () => TeenShell._open(context, s.handoverPaths(preview: true)),
                onWhatYouGet: () => TeenShell._open(context, s.whatYouGet()),
                onStayInTouch: () => TeenShell._open(context, StayInTouchScreen(repository: s._repo, preview: true)))))),
    ]);
  }
}
