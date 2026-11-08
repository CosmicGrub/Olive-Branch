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
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'activity_overrides.dart';
import 'collection_screen.dart';
import 'her_colour_accent.dart';
import 'her_colour_home.dart';
import 'her_colour_store.dart';
import 'colouring_screen.dart';
import 'doodle_desk.dart';
import 'game_logic.dart' show neutralGrownUp;
import 'hub_widgets.dart';
import 'journal_screen.dart';
import 'letters_screen.dart';
import 'maturation_ladder.dart';
import 'quieting_note.dart';
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
