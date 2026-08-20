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
import 'package:flutter/material.dart';
import 'collection_screen.dart';
import 'colour_daily.dart';
import 'colouring_screen.dart';
import 'doodle_desk.dart';
import 'hub_widgets.dart';
import 'journal_screen.dart';
import 'letters_screen.dart';
import 'maturation_ladder.dart';
import 'onboarding_flow.dart';
import 'quieting_note.dart';
import 'shared_gallery.dart';
import 'shared_reading.dart';
import 'snapshot_button.dart' show AppGalleryScreen;
import 'story_library.dart';
import 'take_and_go_screen.dart';
import 'teach_me.dart';
import 'weeks_screen.dart';

class ChildMoreScreen extends StatelessWidget {
  const ChildMoreScreen({super.key, this.childName = 'Ivy', this.childAge = 9});
  final String childName;
  final int childAge;

  void _open(BuildContext context, Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('More for you')),
    body: SafeArea(child: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        HubSection(title: 'Just yours', children: [
          HubTile(icon: Icons.menu_book_outlined, title: 'My journal',
            subtitle: 'Private. Nobody else can read it — ever.',
            onTap: () => _open(context, JournalScreen(childName: childName))),
          HubTile(icon: Icons.markunread_mailbox_outlined, title: 'Letters to me',
            subtitle: 'Write one now, open it when you are older',
            onTap: () => _open(context, LettersScreen(childName: childName, currentAge: childAge))),
          HubTile(icon: Icons.timeline_outlined, title: 'Growing up',
            subtitle: 'What you get to do next, and when',
            onTap: () => _open(context, MaturationLadderScreen(
              childName: childName, childAgeYears: childAge, viewer: LadderViewer.child))),
          HubTile(icon: Icons.spa_outlined, title: 'The quiet corner',
            subtitle: 'A few things fade as you get older — here is why',
            onTap: () => _open(context, QuietingScreen(childName: childName, age: childAge))),
        ]),
        HubSection(title: 'Together', children: [
          HubTile(icon: Icons.nights_stay_outlined, title: 'My weeks',
            subtitle: 'Who tonight is with, in sleeps',
            onTap: () => _open(context, WeeksScreen(
              childName: childName, nights: demoCustodyNights(), guardianColors: demoGuardianColors))),
          HubTile(icon: Icons.school_outlined, title: 'Teach Dad something',
            subtitle: 'You be the teacher this time',
            onTap: () => _open(context, TeachMeScreen(childName: childName, childAge: childAge))),
          HubTile(icon: Icons.auto_stories, title: 'Read together',
            subtitle: 'One book, two screens, his voice',
            onTap: () => _open(context, SharedReadingScreen(childName: childName, readerName: 'Dad'))),
        ]),
        HubSection(title: 'Make things', children: [
          HubTile(icon: Icons.brush_outlined, title: 'Doodle desk',
            subtitle: 'Free strokes and stamps',
            onTap: () => _open(context, DoodleDesk(childName: childName))),
          HubTile(icon: Icons.palette_outlined, title: 'Colouring',
            subtitle: 'A scene, coloured your way',
            onTap: () => _open(context, const ColouringScreen())),
          HubTile(icon: Icons.photo_library_outlined, title: 'My saved pictures',
            subtitle: 'Everything you have saved here',
            onTap: () => _open(context, AppGalleryScreen(gallery: demoAppGallery))),
        ]),
        HubSection(title: 'Show & tell', children: [
          HubTile(icon: Icons.collections_bookmark_outlined, title: 'My collections',
            subtitle: 'What you have shown, kept',
            onTap: () => _open(context, CollectionScreen(childName: childName))),
        ]),
        HubSection(title: 'Stories', children: [
          HubTile(icon: Icons.local_library_outlined, title: 'Story library',
            subtitle: 'Every story you have kept',
            onTap: () => _open(context, StoryLibraryScreen.demo(childName: childName))),
        ]),
        HubSection(title: 'Colour', children: [
          HubTile(icon: Icons.color_lens_outlined, title: "Today's colour",
            subtitle: 'A daily pick, all yours',
            onTap: () => _open(context, ColourDailyScreen(currentColourId: 'sea', onChoose: (_) {}))),
        ]),
        HubSection(title: 'Demo', children: [
          HubTile(icon: Icons.replay_circle_filled_outlined, title: 'Redo the welcome tour',
            subtitle: 'The first-run screens, walked through again',
            onTap: () => _open(context, OnboardingFlowScreen(fallbackName: childName))),
        ]),
        // §9.8.4, §21.2 rung 17, §21.7 — always reachable, same posture every
        // other tile here takes: the SCREEN states the real, honest outcome
        // (including "not yet" for an under-age tap), never this hub deciding
        // in advance whether she is "allowed to see the button". See
        // take_and_go_screen.dart's own header for why hiding this behind a
        // client-side age check would be the wrong kind of gate.
        HubSection(title: 'When you are ready', children: [
          HubTile(icon: Icons.outbox_outlined, title: 'Take your data and go',
            subtitle: 'At eighteen: a full copy of everything, and guardian access closes',
            onTap: () => _open(context, TakeAndGoScreen(childName: childName))),
        ]),
      ]),
    )),
  );
}
