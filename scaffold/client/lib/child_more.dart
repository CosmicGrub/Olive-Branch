// OLIVE BRANCH — child shell, "more for you" hub. UNVERIFIED (no Flutter
// toolchain in tools/verify.sh's automated pipeline). Navigation-wiring-pass
// addition, not a MARKUP screen of its own.
//
// child_home.dart's own grid stays at a size a young child can scan; this
// hub is where the wiring pass hangs every remaining child-facing screen
// that doesn't have (and doesn't need) its own top-level tile, so that
// "every new screen must be reachable" holds without crowding her home
// screen. No settings affordance lives here either — every entry below
// pushes a real, named destination, matching child_home.dart's own rule.
//
// baseUrl/childId/sessionToken/httpClient (optional and additive): reused
// unchanged from child_home.dart's own already-authenticated session
// (child_home_live.dart's own `_load()`), threaded through to
// LettersScreen — the first live-wiring this hub has ever carried. See
// letters_screen.dart's own file header for why that screen reuses this
// session directly rather than minting its own via devLoginFor().
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'activity_overrides.dart';
import 'child_explainer_screens.dart';
import 'collection_screen.dart';
import 'her_colour_accent.dart';
import 'her_colour_home.dart';
import 'her_colour_store.dart';
import 'colouring_screen.dart';
import 'doodle_desk.dart';
import 'family_structure_store.dart' show FamilyChildSnapshot;
import 'growing_care_logic.dart';
import 'growing_care_store.dart';
import 'growing_screens.dart';
import 'game_logic.dart' show neutralGrownUp;
import 'hub_widgets.dart';
import 'journal_screen.dart';
import 'letters_screen.dart';
import 'maturation_ladder.dart';
import 'picture_icons.dart' show Speak;
import 'quieting_note.dart';
import 'rhythm_voice_repositories.dart';
import 'rhythm_voice_sections.dart';
import 'shared_gallery.dart';
import 'shared_reading.dart';
import 'snapshot_button.dart' show AppGalleryScreen;
import 'story_library.dart';
import 'take_and_go_screen.dart';
import 'teach_me.dart';
import 'weeks_screen.dart';

class ChildMoreScreen extends StatelessWidget {
  const ChildMoreScreen({
    super.key,
    this.childName = 'Ivy',
    this.childAge = 9,
    this.baseUrl,
    this.childId,
    this.sessionToken,
    this.httpClient,
    this.overrides,
    this.guardianName,
    this.colourStore,
    this.family,
    this.growingCare,
    this.speak,
    this.rhythmVoice,
  });
  final String childName;
  final int childAge;
  final String? baseUrl;
  final String? childId;
  final String? sessionToken;
  final http.Client? httpClient;

  /// Parental controls, visibility & pacing (docs/superpowers/specs/2026-
  /// 09-13-parental-controls-pacing-design.md) — visibility-only for the
  /// two "Make things" activities below (neither has ever had a minAge
  /// concept anywhere in this client or server, confirmed by grep — the
  /// design spec's own "this pass does not invent a minAge for surfaces
  /// that have never had one" line). Null means no live session; both tiles
  /// render exactly as before this feature existed.
  final Map<String, ActivityOverride>? overrides;

  /// The real display name of the grown-up she talks to (C-13). Null falls
  /// back to [neutralGrownUp] — never a hard-coded "Dad".
  final String? guardianName;
  String get _grownUp => guardianName ?? neutralGrownUp;

  /// Where today's colour comes from; null uses the process-wide in-memory store.
  final ChildColourStore? colourStore;

  /// Her derived view (age bands and family structure). It decides whether the
  /// "Keep and grow" section exists at all: the youngest band has no More hub,
  /// and a guardian can switch each suite off. Null falls back to [childAge]
  /// (an unknown age fails closed to 5, see childSuitesFor).
  final FamilyChildSnapshot? family;

  /// Where the "Keep and grow" things are kept; null uses this device's own
  /// sealed store for the current child.
  final GrowingCareStores? growingCare;

  /// Read-aloud seam for the Rhythm and Voice tiles (null: no spoken names).
  final Speak? speak;

  /// Where Rhythm and Voice keep what they hold. Null: the device's own store.
  final RhythmVoiceService? rhythmVoice;

  /// C-15: the maturation ladder's first rung is her tenth birthday
  /// (maturation_ladder.dart's [kLadder]); "Growing up", "The quiet corner"
  /// and "Taking your things with you" are all about that ladder and what
  /// fades or unlocks on it, so a younger child never sees them.
  bool get _showGrowingUp => childAge >= kLadder.first.age;

  void _open(BuildContext context, Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));

  // Child voice throughout (C-13/C-15): short second-person lines, no
  // spec language ("irreversible", "guardian access", "preserved").
  // Contract: nothing guardian-facing and no settings affordance is
  // reachable from here (§8.1) — child_no_settings_contract_test.dart reads
  // this file's source to hold that line, including that the demo section
  // and the first-run tour replay are gone (C-14).
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('More for you')),
    body: SafeArea(child: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        HubSection(title: 'Just yours', children: [
          HubTile(icon: Icons.menu_book_outlined, title: 'My journal',
            subtitle: 'Just for you',
            onTap: () => _open(context, JournalScreen(childName: childName))),
          HubTile(icon: Icons.markunread_mailbox_outlined, title: 'Letters to me',
            subtitle: 'Write now, open later',
            onTap: () => _open(context, LettersScreen(childName: childName, currentAge: childAge,
              childId: childId ?? 'demo-child',
              baseUrl: baseUrl, sessionToken: sessionToken, httpClient: httpClient))),
          if (_showGrowingUp) ...[
            HubTile(icon: Icons.timeline_outlined, title: 'Growing up',
              subtitle: 'What comes next',
              onTap: () => _open(context, MaturationLadderScreen(
                childName: childName, childAgeYears: childAge, viewer: LadderViewer.child))),
            HubTile(icon: Icons.spa_outlined, title: 'The quiet corner',
              subtitle: 'Things that fade as you grow',
              onTap: () => _open(context, QuietingScreen(childName: childName, age: childAge))),
          ],
        ]),
        HubSection(title: 'Together', children: [
          HubTile(icon: Icons.nights_stay_outlined, title: 'My weeks',
            subtitle: 'Where you sleep, night by night',
            onTap: () => _open(context, WeeksScreen(
              childName: childName, nights: demoCustodyNights(), guardianColors: demoGuardianColors))),
          HubTile(icon: Icons.school_outlined, title: 'Teach $_grownUp something',
            subtitle: 'You be the teacher',
            onTap: () => _open(context, TeachMeScreen(childName: childName, childAge: childAge,
              parentName: _grownUp))),
          HubTile(icon: Icons.auto_stories, title: 'Read together',
            subtitle: 'One book, two of you',
            onTap: () => _open(context, SharedReadingScreen(childName: childName, readerName: _grownUp))),
        ]),
        _KeepAndGrow(childName: childName, childAge: childAge, family: family, stores: growingCare),
        RhythmVoiceSections(
          service: rhythmVoice ?? RhythmVoiceService.forChild(childId),
          family: family, yearsOld: childAge, speak: speak),
        HubSection(title: 'Make things', children: [
          if (isTileVisible(overrides, 'activity:doodle'))
            HubTile(icon: Icons.brush_outlined, title: 'Doodle desk',
              subtitle: 'Draw anything',
              onTap: () => _open(context, DoodleDesk(childName: childName))),
          if (isTileVisible(overrides, 'activity:colouring'))
            HubTile(icon: Icons.palette_outlined, title: 'Colouring',
              subtitle: 'Colour a picture',
              onTap: () => _open(context, const ColouringScreen())),
          HubTile(icon: Icons.photo_library_outlined, title: 'My saved pictures',
            subtitle: 'Pictures you kept',
            onTap: () => _open(context, AppGalleryScreen(gallery: demoAppGallery))),
        ]),
        HubSection(title: 'Show & tell', children: [
          HubTile(icon: Icons.collections_bookmark_outlined, title: 'My collections',
            subtitle: 'Things you showed',
            onTap: () => _open(context, CollectionScreen(childName: childName))),
        ]),
        HubSection(title: 'Stories', children: [
          HubTile(icon: Icons.local_library_outlined, title: 'Story library',
            subtitle: 'Stories you kept',
            onTap: () => _open(context, StoryLibraryScreen.demo(childName: childName))),
        ]),
        HubSection(title: 'Colour', children: [
          _ColourTile(store: colourStore, childName: childName, childAge: childAge),
        ]),
        // §9.8.4, §21.2 rung 17, §21.7 — the SCREEN states the real, honest
        // outcome (including "not yet" for an under-age tap), never this hub
        // deciding in advance whether she is "allowed to see the button" for
        // a LEGAL reason; the age gate here (C-15) is only about relevance —
        // a five-year-old has no use for it — and uses the same ladder start
        // as the two tiles above.
        if (_showGrowingUp)
          HubSection(title: 'When you are ready', children: [
            HubTile(icon: Icons.outbox_outlined, title: 'Take your things with you',
              subtitle: 'For when you are grown up',
              onTap: () => _open(context, TakeAndGoScreen(childName: childName))),
          ]),
      ]),
    )),
  );
}

/// "Today's colour": shows what today's colour is as a plain fact (or that the
/// question is waiting) and opens her colour screen. Her colour appears here as
/// ONE placement, the tile's border; nothing else on this hub is tinted.
class _ColourTile extends StatefulWidget {
  const _ColourTile({required this.store, required this.childName, required this.childAge});
  final ChildColourStore? store;
  final String childName;
  final int childAge;

  @override
  State<_ColourTile> createState() => _ColourTileState();
}

class _ColourTileState extends State<_ColourTile> {
  late final ChildColourStore _store = widget.store ?? sharedColourStore;
  TodayColour? _today;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final t = await _store.today();
    if (mounted) setState(() => _today = t);
  }

  @override
  Widget build(BuildContext context) {
    final t = _today;
    final accent = HerColourAccent.of(t?.swatch?.id, const ['collection_tile']);
    final subtitle = t == null || t.swatch == null
        ? 'Pick yours'
        : (t.ask ? 'Which do you like more today?' : 'Today: ${t.swatch!.label}');
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: accent.has('collection_tile')
          ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: accent.color!, width: 2))
          : null,
      child: ListTile(
        key: const Key('colourTile'),
        leading: const Icon(Icons.color_lens_outlined),
        title: const Text("Today's colour"),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          await Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => HerColourScreen(
                  childName: widget.childName, childAge: widget.childAge, store: widget.store)));
          await _refresh();
        },
      ),
    );
  }
}

/// "Keep and grow": her memory box, and the few things a guardian chose to show
/// her (a doorframe picture, firsts, an opened letter, picture stories). Each
/// guardian-authored tile exists only when there is something to see, and the
/// whole section only when the age-band model and the guardian's switches say
/// so. Care information is never here.
class _KeepAndGrow extends StatefulWidget {
  const _KeepAndGrow({required this.childName, required this.childAge, required this.family, required this.stores});
  final String childName;
  final int childAge;
  final FamilyChildSnapshot? family;
  final GrowingCareStores? stores;

  @override
  State<_KeepAndGrow> createState() => _KeepAndGrowState();
}

class _KeepAndGrowState extends State<_KeepAndGrow> {
  GrowingCareStores? _s;
  ChildGrowingLens? _lens;
  ChildSuites _suites = ChildSuites.none;
  bool _marks = false, _firsts = false, _letters = false, _stories = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final GrowingCareStores s = widget.stores ?? GrowingCareStores.forChild();
      final ChildSuites suites = childSuitesFor(
          view: widget.family?.view, yearsOld: widget.childAge, switches: await s.switches.load());
      final ChildGrowingLens lens = s.childLens();
      final bool marks = suites.pencilMarks && (await lens.growth()).isNotEmpty;
      final bool firsts = suites.firstTimes && (await lens.shownFirsts()).isNotEmpty;
      final bool letters = suites.timeCapsule && (await lens.openedLetters()).isNotEmpty;
      final bool stories = suites.explainerCards && (await s.childExplainers().shown()).isNotEmpty;
      if (!mounted) return;
      setState(() {
        _s = s; _lens = lens; _suites = suites;
        _marks = marks; _firsts = firsts; _letters = letters; _stories = stories;
      });
    } catch (_) {
      // Fail closed: if the device store cannot be read, the section is simply absent.
    }
  }

  void _open(Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    if (!_suites.any) return const SizedBox.shrink();
    return HubSection(title: 'Keep and grow', children: [
      if (_suites.memoryBox)
        HubTile(key: const Key('childMemoryBox'), icon: Icons.inventory_2_outlined, title: 'My memory box',
          subtitle: 'Things you chose to keep',
          onTap: () => _open(MemoryBoxScreen(childName: widget.childName, stores: _s))),
      if (_marks)
        HubTile(key: const Key('childDoorframe'), icon: Icons.straighten, title: 'My doorframe',
          subtitle: 'Look how you are growing',
          onTap: () => _open(GrowthPictureScreen(childName: widget.childName, lens: _lens))),
      if (_firsts)
        HubTile(key: const Key('childFirsts'), icon: Icons.star_outline, title: 'Something new',
          subtitle: 'Times you did something new',
          onTap: () => _open(MyFirstsScreen(lens: _lens))),
      if (_letters)
        HubTile(key: const Key('childLetters'), icon: Icons.mail_outline, title: 'A letter for you',
          subtitle: 'Ready to open',
          onTap: () => _open(LettersOpenedScreen(lens: _lens))),
      if (_stories)
        HubTile(key: const Key('childStories'), icon: Icons.menu_book_outlined, title: 'Stories for you',
          subtitle: 'Someone who loves you wrote these',
          onTap: () => _open(ExplainerStoriesScreen(reader: _s?.childExplainers()))),
    ]);
  }
}
