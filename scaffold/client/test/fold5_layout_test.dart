// OLIVE BRANCH — the six screens this pass actually touches. Intuitivism
// pass, sub-project 3c (docs/superpowers/specs/2026-09-12-intuitivism-
// fold5-layout-design.md, Testing section). TabletopSplit/CoverCollapse's
// own contracts are proven independently in tabletop_split_test.dart /
// cover_collapse_test.dart — this file proves each real screen actually
// wires the shared widget in at the right posture, using real widget
// content, plus a regression pass confirming every OTHER posture on all
// six screens is unchanged from before this pass.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/call_modes.dart';
import 'package:olive_client/call_screen.dart';
import 'package:olive_client/child_home.dart';
import 'package:olive_client/guardian_home.dart';
import 'package:olive_client/homework_screen.dart';
import 'package:olive_client/library_logic.dart';
import 'package:olive_client/showcase_screen.dart';
import 'package:olive_client/storyteller_screen.dart';
import 'package:olive_client/tabletop_split.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

/// The exact Fold5 cover-screen test dimensions the design spec's own
/// Testing section names — the same 344x841 coordinates
/// form_factors_test.dart's own postureFor() suite pins against.
const foldCoverSize = Size(344, 841);

/// The FORM_FACTORS floor for Posture.foldTabletop (form_factors.dart's own
/// `min: Viewport(w: 673, h: 420)`) — short, wide, landscape.
const foldTabletopSize = Size(673, 420);

void main() {
  group('ChildHome — CoverCollapse, real at foldCover', () {
    const home = ChildHome(childName: 'Ivy', presence: null,
      sleepsUntilHandover: 3, unreadCount: 2);

    testWidgets('at foldCover (344x841): ribbon/presence, Hero, and More only '
        '— never the Featured/Standard grids', (t) async {
      await t.binding.setSurfaceSize(foldCoverSize);
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(home));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);

      expect(find.text('Hi Ivy'), findsOneWidget);
      expect(find.descendant(
        of: find.byKey(const Key('childHomeHero')), matching: find.text('My day')),
        findsOneWidget);
      expect(find.text('More'), findsOneWidget);

      expect(find.byKey(const Key('childHomeFeaturedGrid')), findsNothing);
      expect(find.byKey(const Key('childHomeStandardGrid')), findsNothing);
      for (final label in <String>[
        'Play together', 'Messages', 'Storyteller', 'Show & tell',
        'Homework', 'My list', 'More for you',
      ]) {
        expect(find.text(label), findsNothing, reason: label);
      }
    });

    testWidgets('the "More" tile opens the full, otherwise-unchanged layout '
        'on its own screen — the same shape guardian_home.dart\'s own '
        '"More" tile already uses, reused here', (t) async {
      await t.binding.setSurfaceSize(foldCoverSize);
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(home));
      await t.pumpAndSettle();
      await t.tap(find.text('More'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      // The full list, reachable now on its own screen.
      expect(find.text('Play together'), findsOneWidget);
      expect(find.text('Messages'), findsOneWidget);
      expect(find.text('Homework'), findsOneWidget);
      expect(find.text('More for you'), findsOneWidget);
      // Still real: Hero's own destination is reachable from this screen too.
      expect(find.descendant(
        of: find.byKey(const Key('childHomeHero')), matching: find.text('My day')),
        findsOneWidget);
    });

    group('regression — every OTHER posture is unchanged', () {
      const otherSizes = <String, Size>{
        'foldMain (673x841)': Size(673, 841),
        'foldTabletop (673x420)': Size(673, 420),
        'phone (360x740)': Size(360, 740),
        'desktop (1100x900)': Size(1100, 900),
      };
      for (final entry in otherSizes.entries) {
        testWidgets('${entry.key} — the full Featured/Standard grids still '
            'render, and the new foldCover-only "More" tile does not exist',
            (t) async {
          await t.binding.setSurfaceSize(entry.value);
          addTearDown(() => t.binding.setSurfaceSize(null));
          await t.pumpWidget(wrap(home));
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
          expect(find.byKey(const Key('childHomeFeaturedGrid')), findsOneWidget);
          expect(find.byKey(const Key('childHomeStandardGrid')), findsOneWidget);
          expect(find.text('Play together'), findsOneWidget);
          expect(find.text('More for you'), findsOneWidget);
          // The foldCover-only tile's exact label never appears outside
          // foldCover — "More for you" is a different, pre-existing tile.
          expect(find.text('More'), findsNothing);
        });
      }
    });
  });

  group('GuardianHome — CoverCollapse, real at foldCover', () {
    const bands = <RibbonBand>[
      RibbonBand(0, 0.5, Colors.blue, 'school'),
      RibbonBand(0.5, 0.5, Colors.green, 'home time'),
    ];
    const home = GuardianHome(childName: 'Ivy', childLocalTime: '4:12 PM',
      childZoneAbbr: 'EDT', actorLocalTime: '3:12 PM CDT', childBands: bands,
      actorBands: bands);

    testWidgets('at foldCover (344x841): the ribbon (unchanged) and the '
        'Hero tile (Message banking) only', (t) async {
      await t.binding.setSurfaceSize(foldCoverSize);
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(home));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);

      // Ribbon unchanged.
      expect(find.text('Ivy'), findsOneWidget);
      expect(find.text('4:12 PM'), findsOneWidget);
      expect(find.text('you · 3:12 PM CDT'), findsOneWidget);
      // Hero + More only.
      expect(find.text('Message banking'), findsOneWidget);
      expect(find.text('More'), findsOneWidget);
      // Never the rest of the grid.
      for (final label in <String>[
        'Emergency card', 'Handover notes', 'Exchange', 'Expenses',
        'Availability', 'Send-time guard', 'Meds & care', 'Morning briefing',
        'Care note',
      ]) {
        expect(find.text(label), findsNothing, reason: label);
      }
    });

    testWidgets('the "More" tile opens the full, otherwise-unchanged layout '
        'on its own screen', (t) async {
      await t.binding.setSurfaceSize(foldCoverSize);
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(home));
      await t.pumpAndSettle();
      await t.tap(find.text('More'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.text('Emergency card'), findsOneWidget);
      expect(find.text('Handover notes'), findsOneWidget);
      expect(find.text('Message banking'), findsOneWidget);
    });

    group('regression — every OTHER posture is unchanged', () {
      const otherSizes = <String, Size>{
        'foldMain (673x841)': Size(673, 841),
        'foldTabletop (673x420)': Size(673, 420),
        'phone (360x740)': Size(360, 740),
        'desktop (1100x900)': Size(1100, 900),
      };
      for (final entry in otherSizes.entries) {
        testWidgets('${entry.key} — the full grid still renders', (t) async {
          await t.binding.setSurfaceSize(entry.value);
          addTearDown(() => t.binding.setSurfaceSize(null));
          await t.pumpWidget(wrap(home));
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
          expect(find.text('Emergency card'), findsOneWidget);
          expect(find.text('Handover notes'), findsOneWidget);
          expect(find.text('Message banking'), findsOneWidget);
        });
      }
    });
  });

  group('storyteller_screen.dart — TabletopSplit, real at foldTabletop', () {
    testWidgets('at foldTabletop (673x420): the reading card and the shelf '
        'are both reachable', (t) async {
      await t.binding.setSurfaceSize(foldTabletopSize);
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(const StorytellerScreen(childName: 'Ivy',
        initialFavourites: [Favourite(code: 'oak-1', title: 'The Oak Who Waited',
          starredAt: '2026-01-01T00:00:00.000Z', timesRead: 1)])));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.byType(TabletopSplit), findsOneWidget);
      // Viewing half — the ask/reading card.
      expect(find.text('Want a story, Ivy?'), findsOneWidget);
      // Controls half — the shelf, reachable below the hinge.
      expect(find.text('Your starred stories'), findsOneWidget);
      expect(find.text('The Oak Who Waited'), findsOneWidget);
    });

    testWidgets('regression — foldMain (673x841) is unchanged: no '
        'TabletopSplit, the pre-existing wide two-pane Row still renders',
        (t) async {
      await t.binding.setSurfaceSize(const Size(673, 841));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(const StorytellerScreen(childName: 'Ivy')));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.byType(TabletopSplit), findsNothing);
      expect(find.byType(Row), findsWidgets);
    });
  });

  group('showcase_screen.dart — TabletopSplit, real at foldTabletop', () {
    testWidgets('at foldTabletop (673x420): the ask feed and the prompt '
        'chips are both reachable', (t) async {
      await t.binding.setSurfaceSize(foldTabletopSize);
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(const ShowcaseScreen(childName: 'Ivy')));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.byType(TabletopSplit), findsOneWidget);
      expect(find.text('Hi Ivy! What do you want to show today?'), findsOneWidget);
      expect(find.text('Or show something else'), findsOneWidget);
    });

    testWidgets('regression — foldMain (673x841) is unchanged: no '
        'TabletopSplit, the same single ListView still renders', (t) async {
      await t.binding.setSurfaceSize(const Size(673, 841));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(const ShowcaseScreen(childName: 'Ivy')));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.byType(TabletopSplit), findsNothing);
      expect(find.byType(ListView), findsOneWidget);
    });
  });

  group('homework_screen.dart — TabletopSplit, real at foldTabletop', () {
    testWidgets('at foldTabletop (673x420) before capture: the worksheet '
        'intro and the capture control are both reachable', (t) async {
      await t.binding.setSurfaceSize(foldTabletopSize);
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(const HomeworkScreen()));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.byType(TabletopSplit), findsOneWidget);
      expect(find.text("Let's get your worksheet"), findsOneWidget);
      expect(find.byKey(const Key('takePhotoButton')), findsOneWidget);
    });

    testWidgets('regression — foldMain (673x841) is unchanged: no '
        'TabletopSplit, the same single ListView still renders', (t) async {
      await t.binding.setSurfaceSize(const Size(673, 841));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(const HomeworkScreen()));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.byType(TabletopSplit), findsNothing);
      expect(find.byType(ListView), findsOneWidget);
    });
  });

  group('call_screen.dart — TabletopSplit, real at foldTabletop', () {
    // CallScreen itself can never reach _CallStatus.inCall in a test
    // sandbox (no live LiveKit connection) — see call_screen_test.dart's
    // own header. InCallView is public specifically so this pass's own
    // foldTabletop split can be exercised directly (the same reason
    // isGuardianWho is a top-level function, per that constant's own doc
    // comment) — the real CallScreen wiring itself (LayoutBuilder ->
    // `tabletop` -> InCallView) is exercised in call_screen_test.dart's own
    // "no live network" tests, which already confirm the screen never
    // throws building this new LayoutBuilder for the states it CAN reach.
    InCallView buildView({required bool tabletop}) => InCallView(
      tabletop: tabletop,
      localTrack: null, remoteTrack: null, remoteName: null, notice: null,
      isGuardian: true, onHangUp: () async {}, onToggleMic: () async {},
      onToggleCamera: () async {}, micEnabled: true, cameraEnabled: true,
      remoteMode: CallMode.video, awaitingResumeConsent: false,
      onResumeVideo: () {},
    );

    testWidgets('at foldTabletop: video area and call controls are both '
        'reachable via TabletopSplit', (t) async {
      await t.binding.setSurfaceSize(foldTabletopSize);
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(Scaffold(backgroundColor: Colors.black,
        body: buildView(tabletop: true))));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.byType(TabletopSplit), findsOneWidget);
      // Controls half — the three real call controls, all reachable. Each
      // is an icon-only button (_CallControlButton) whose label only ever
      // exists as a Tooltip message/semantic label, never a plain Text
      // widget — find.byTooltip is the real finder for it.
      expect(find.byTooltip('Mute'), findsOneWidget);
      expect(find.byTooltip('Hang up'), findsOneWidget);
      expect(find.byTooltip('Turn camera off'), findsOneWidget);
      // Viewing half — the listening/video surface (no remote track in this
      // test, so the honest "waiting" listening surface renders).
      expect(find.text('Waiting for the other side…'), findsOneWidget);
    });

    testWidgets('regression — tabletop:false (every other posture) is '
        'unchanged: the original Stack overlay, no TabletopSplit', (t) async {
      await t.pumpWidget(wrap(Scaffold(backgroundColor: Colors.black,
        body: buildView(tabletop: false))));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.byType(TabletopSplit), findsNothing);
      expect(find.byTooltip('Mute'), findsOneWidget);
      expect(find.byTooltip('Hang up'), findsOneWidget);
      expect(find.byTooltip('Turn camera off'), findsOneWidget);
      expect(find.text('Waiting for the other side…'), findsOneWidget);
      final stack = t.widgetList<Stack>(find.byType(Stack));
      expect(stack, isNotEmpty);
    });
  });
}
