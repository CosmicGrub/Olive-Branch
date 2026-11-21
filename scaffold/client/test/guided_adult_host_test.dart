// OLIVE BRANCH — the grown-up's half of the guided first run, on the home: coach marks that find real anchors, the five
// controls on every step, the progress strip, the pause, resume after a kill, the connect step with its helper strip,
// "Show me around again", the "What's new" mini-tour, the simulation seam, large text, and the guarantee that an install
// that already finished first run is not shown any of it. Verified by CI, headless. MASTERFILE §8.5.14.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/connect_child_screen.dart';
import 'package:olive_client/device_keys.dart';
import 'package:olive_client/local_pin.dart';
import 'package:olive_client/pairing_protocol.dart';
import 'package:olive_client/pairing_records.dart';
import 'package:olive_client/guardian_home.dart';
import 'package:olive_client/guided_adult.dart';
import 'package:olive_client/guided_progress.dart';
import 'package:olive_client/guided_script.dart';
import 'package:olive_client/guided_sim.dart';
import 'package:olive_client/guided_widgets.dart';

const List<String> _kStops = <String>[
  'home.messageBanking', 'home.availability', 'home.sendTimeGuard', 'home.medsCare', 'home.emergencyCard', 'home.call', 'home.more',
];

/// A home with the named anchors laid out in a column (every id by default).
Widget _homeWith(Iterable<String> anchors) => Scaffold(
      body: SingleChildScrollView(
        child: Column(children: <Widget>[
          for (final String a in anchors)
            CoachAnchor(id: a, child: SizedBox(height: 64, width: double.infinity, child: Center(child: Text('tile $a')))),
        ]),
      ),
    );

class _FakeHost implements WindowHost {
  @override
  int? get port => 4242;
  @override
  Future<void> stop() async {}
  @override
  Future<void> readvertise() async {}
}

GuidedEntry _newStop(String id, {String slot = 'adult.tour.features'}) => GuidedEntry(
      id: id, half: GuidedHalf.adult, slot: slot, kind: GuidedKind.coach, phase: 'tour', since: 2, whatsNew: true,
      anchor: 'home.$id', title: 'The $id', words: 'About the $id.',
      labels: <GuidedLabel>[GuidedLabel(Icons.star, 'The $id', 'a line')],
    );

void main() {
  late MemoryGuidedProgressStore store;
  setUp(() => store = MemoryGuidedProgressStore());

  Future<void> pump(
    WidgetTester t, {
    GuidedProgress? progress,
    Iterable<String> anchors = _kStops,
    bool simulate = false,
    Size size = const Size(412, 900),
    double text = 1.0,
    List<GuidedEntry> registered = const <GuidedEntry>[],
    int version = kGuidedScriptVersion,
    GuidedConnectBuilder? connect,
    Widget? home,
  }) async {
    if (progress != null) await store.save(progress);
    await t.binding.setSurfaceSize(size);
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(MaterialApp(
      builder: (BuildContext c, Widget? w) =>
          MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(text)), child: w!),
      home: GuidedAdultHost(
        store: store,
        simulate: simulate,
        childName: 'Ivy',
        registered: registered,
        scriptVersion: version,
        connectBuilder: connect,
        child: home ?? _homeWith(anchors),
      ),
    ));
    await t.pumpAndSettle();
  }

  String title(WidgetTester t) => t.widget<Text>(find.byKey(const Key('guidedTitle'))).data!;

  group('an install that already finished first run', () {
    testWidgets('with no record at all: nothing is drawn over the home (the 0.51 installs)', (t) async {
      await pump(t);
      expect(find.byKey(const Key('guidedTitle')), findsNothing);
      expect(find.byKey(const Key('guidedNext')), findsNothing);
      expect(find.text('tile home.call'), findsOneWidget);
    });

    testWidgets('that finished the guided run and has seen this version: nothing is drawn', (t) async {
      await pump(t, progress: const GuidedProgress(seenVersion: kGuidedScriptVersion, adultDone: true, adultStep: 'a.done'));
      expect(find.byKey(const Key('guidedTitle')), findsNothing);
    });

    testWidgets('a record whose text is garbage is no record: nothing is drawn', (t) async {
      await pump(t, progress: GuidedProgress.fromJson(<String, Object?>{'aStep': 7, 'aDone': 'yes', 'seen': 'x'}));
      expect(find.byKey(const Key('guidedTitle')), findsNothing);
    });
  });

  group('resuming a first run after the app was killed', () {
    testWidgets('after the PIN: opens on "Connect her tablet" as "Step 6 of 9", with the labels spelled out', (t) async {
      await pump(t, progress: const GuidedProgress(seenVersion: 0, adultStep: 'a.tablet'));
      expect(title(t), 'Connect her tablet');
      expect(find.text('Step 6 of 9'), findsOneWidget);
      for (final String l in <String>['Open the window', 'Her tablet', 'Same picture', 'Match', 'Yes']) {
        expect(find.text(l), findsOneWidget, reason: l);
      }
      expect(find.byKey(const Key('guidedBack')), findsOneWidget);
      expect(find.byKey(const Key('guidedSkip')), findsOneWidget);
      expect(find.byKey(const Key('guidedLater')), findsOneWidget);
      expect(find.byKey(const Key('guidedPause')), findsOneWidget);
      expect(find.text('Open the connect screen'), findsOneWidget);
    });

    testWidgets('a saved step inside the questions means "start at the connect step" (the PIN is already saved)', (t) async {
      await pump(t, progress: const GuidedProgress(adultStep: 'a.her'));
      expect(title(t), 'Connect her tablet');
    });

    testWidgets('mid-tour: opens on the saved stop, pointing at the real icon, with the strip and the label', (t) async {
      await pump(t, progress: const GuidedProgress(adultStep: 'a.tour.care'));
      expect(title(t), 'Meds & care');
      expect(find.byKey(const Key('guidedLit')), findsOneWidget, reason: 'the lit hole is round a real anchor');
      expect(find.byKey(const Key('guidedNoFind')), findsNothing);
      expect(find.text('Step 7 of 9'), findsOneWidget);
      expect(find.text('Medicines, expenses, handover notes'), findsOneWidget);
      await t.tap(find.byKey(const Key('guidedBack')));
      await t.pumpAndSettle();
      expect(title(t), 'Send-time guard');
    });
  });

  group('the tour', () {
    testWidgets('every stop finds its anchor on a layout that has them, and the lit hole is on the anchor', (t) async {
      await pump(t, progress: const GuidedProgress(adultStep: 'a.tour.bank'));
      final List<String> seen = <String>[];
      for (int i = 0; i < 8; i++) {
        seen.add(title(t));
        expect(find.byKey(const Key('guidedLit')), findsOneWidget, reason: '${title(t)} is not lit');
        final Rect lit = t.getRect(find.byKey(const Key('guidedLit')));
        final String anchor = (<String, String>{
          'Message banking': 'home.messageBanking', 'Availability': 'home.availability', 'Send-time guard': 'home.sendTimeGuard',
          'Meds & care': 'home.medsCare', 'Emergency card': 'home.emergencyCard', 'Call': 'home.call',
          'More': 'home.more', 'Her: what she sees': 'home.more',
        })[title(t)]!;
        final Rect real = CoachAnchors.rectOf(anchor)!;
        expect(lit.overlaps(real), isTrue, reason: anchor);
        expect(lit.contains(real.center), isTrue, reason: anchor);
        await t.tap(find.byKey(const Key('guidedNext')));
        await t.pumpAndSettle();
      }
      expect(seen, <String>[
        'Message banking', 'Availability', 'Send-time guard', 'Meds & care', 'Emergency card', 'Call', 'More', 'Her: what she sees',
      ]);
      expect(title(t), 'Help is close by');
      expect(find.text('Step 8 of 9'), findsOneWidget);
    });

    testWidgets('a stop whose icon is not on this screen shows its card in the middle with a calm line, never pointing at nothing', (t) async {
      await pump(t, anchors: <String>['home.messageBanking', 'home.more'], progress: const GuidedProgress(adultStep: 'a.tour.care'));
      expect(title(t), 'Meds & care');
      expect(find.byKey(const Key('guidedLit')), findsNothing);
      expect(find.byKey(const Key('guidedNoFind')), findsOneWidget);
      expect(find.text(GuidedWords.tourNoFind), findsOneWidget);
      expect(find.byKey(const Key('guidedNext')), findsOneWidget, reason: 'never stuck');
    });

    testWidgets('Skip this part jumps past the tour; "Do this later" remembers it and the last screen says so, calmly', (t) async {
      await pump(t, progress: const GuidedProgress(adultStep: 'a.tablet'));
      await t.tap(find.byKey(const Key('guidedLater')));
      await t.pumpAndSettle();
      expect(title(t), 'Message banking');
      await t.tap(find.byKey(const Key('guidedSkip')));
      await t.pumpAndSettle();
      expect(title(t), 'Help is close by');
      await t.tap(find.byKey(const Key('guidedNext')));
      await t.pumpAndSettle();
      expect(title(t), 'You are all set');
      expect(find.text('Step 9 of 9'), findsOneWidget);
      expect(find.byKey(const Key('guidedSkip')), findsNothing, reason: 'the last screen cannot be skipped');
      expect(find.byKey(const Key('guidedLater')), findsNothing);
      expect(find.byKey(const Key('guidedLaterNote')), findsOneWidget);
      expect(t.widget<Text>(find.byKey(const Key('guidedLaterNote'))).data, contains('Connect her tablet'));
      await t.tap(find.text('Go to my home'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('guidedTitle')), findsNothing, reason: 'it ends on her home');
      final GuidedProgress p = await store.load();
      expect(p.adultDone, isTrue);
      expect(p.seenVersion, kGuidedScriptVersion);
    });

    testWidgets('"I need a minute" opens a calm card, saves the place, and "I am ready" comes back to the same step', (t) async {
      await pump(t, progress: const GuidedProgress(adultStep: 'a.tour.avail'));
      await t.tap(find.byKey(const Key('guidedPause')));
      await t.pumpAndSettle();
      expect(find.text(GuidedWords.pauseTitle), findsOneWidget);
      expect(find.text(GuidedWords.pauseBody), findsOneWidget);
      expect((await store.load()).adultStep, 'a.tour.avail');
      await t.tap(find.byKey(const Key('guidedResume')));
      await t.pumpAndSettle();
      expect(title(t), 'Availability');
    });

    testWidgets('nothing advances by itself: a long wait leaves the step where it was', (t) async {
      await pump(t, progress: const GuidedProgress(adultStep: 'a.tour.guard'));
      await t.pump(const Duration(minutes: 30));
      expect(title(t), 'Send-time guard');
    });

    testWidgets('taps behind a tour stop do not reach the home', (t) async {
      int taps = 0;
      await pump(t,
          progress: const GuidedProgress(adultStep: 'a.tour.bank'),
          home: Scaffold(body: Center(child: CoachAnchor(id: 'home.messageBanking', child: ElevatedButton(onPressed: () => taps++, child: const Text('Behind'))))));
      await t.tapAt(t.getCenter(find.byKey(const Key('guidedLit'))));
      await t.pump();
      expect(taps, 0);
    });
  });

  group('connect her tablet, hand-held', () {
    Widget fake(BuildContext c, {required String childName, required VoidCallback onConnected}) => Scaffold(
          body: Column(children: <Widget>[
            Text('connect for $childName'),
            ElevatedButton(
                key: const Key('fakeConnected'),
                onPressed: () {
                  onConnected();
                  Navigator.of(c).pop();
                },
                child: const Text('connected')),
          ]),
        );

    testWidgets('Open the connect screen opens the real screen; when it really connected, the tour carries on', (t) async {
      await pump(t, progress: const GuidedProgress(adultStep: 'a.tablet', deferred: <String>['tablet']), connect: fake);
      await t.tap(find.byKey(const Key('guidedNext')));
      await t.pumpAndSettle();
      expect(find.text('connect for Ivy'), findsOneWidget);
      await t.tap(find.byKey(const Key('fakeConnected')));
      await t.pumpAndSettle();
      expect(title(t), 'Message banking');
      expect((await store.load()).deferred, isEmpty, reason: 'a part that really got done is no longer waiting');
    });

    testWidgets('leaving the connect screen without connecting stays on the card: nothing is forced, nothing is lost', (t) async {
      await pump(t, progress: const GuidedProgress(adultStep: 'a.tablet'), connect: fake);
      await t.tap(find.byKey(const Key('guidedNext')));
      await t.pumpAndSettle();
      Navigator.of(t.element(find.text('connect for Ivy'))).pop();
      await t.pumpAndSettle();
      expect(title(t), 'Connect her tablet');
    });

    testWidgets('the helper strip: five numbered steps, which device to touch, a live waiting state, calm recovery, then well done', (t) async {
      Future<void> banner(ConnectGuideStage s, {bool message = false}) async {
        await t.pumpWidget(MaterialApp(home: Scaffold(body: GuidedConnectBanner(stage: s, hasMessage: message, childName: 'Ivy'))));
      }

      await banner(ConnectGuideStage.intro);
      expect(find.byKey(const Key('guidedTabletStep1')), findsOneWidget);
      expect(find.textContaining('Open the window'), findsOneWidget);
      await banner(ConnectGuideStage.waiting);
      for (final int n in <int>[2, 3, 4]) {
        expect(find.byKey(Key('guidedTabletStep$n')), findsOneWidget);
      }
      expect(find.textContaining('On her tablet, tap A grown-up does this'), findsOneWidget);
      expect(find.byKey(const Key('guidedTabletWait')), findsOneWidget);
      expect(find.textContaining("Waiting for Ivy's tablet"), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget, reason: 'live: it is still looking');
      expect(find.byKey(const Key('guidedTabletRecover')), findsNothing);
      await banner(ConnectGuideStage.intro, message: true);
      expect(find.byKey(const Key('guidedTabletRecover')), findsOneWidget);
      expect(find.textContaining('that is okay'), findsOneWidget);
      expect(find.textContaining('Nothing was shared'), findsOneWidget);
      await banner(ConnectGuideStage.approve);
      expect(find.byKey(const Key('guidedTabletStep5')), findsOneWidget);
      await banner(ConnectGuideStage.done);
      expect(find.byKey(const Key('guidedTabletDone')), findsOneWidget);
      expect(find.textContaining('Well done'), findsOneWidget);
      for (final ConnectGuideStage s in ConnectGuideStage.values) {
        final int n = guidedTabletStepFor(s);
        expect(n, inInclusiveRange(1, 5));
      }
    });

    testWidgets('the real connect screen draws the helper strip above its own content, and its own steps still work', (t) async {
      await t.binding.setSurfaceSize(const Size(800, 1800));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final LocalPinService pin = LocalPinService(MemoryLocalPinRepository(), iterations: 1);
      await t.runAsync(() => pin.setPin('4829'));
      int connected = 0;
      await t.pumpWidget(MaterialApp(
          home: ConnectChildScreen(
        pin: pin,
        deviceKeys: MemoryDeviceKeyRepository(),
        kids: MemoryPairedKidsRepository(),
        adultName: 'Mom',
        childName: 'Ivy',
        makeUnlockVerifier: (String p) async => LocalPinRecord(iterations: 1, salt: Uint8List(16), hash: Uint8List(32)),
        localAddress: () async => '127.0.0.1',
        startHost: (AdultWindow w) async => _FakeHost(),
        onConnected: () => connected++,
        guideBanner: (BuildContext c, ConnectGuideStage s, bool m) => GuidedConnectBanner(stage: s, hasMessage: m, childName: 'Ivy'),
      )));
      expect(find.byKey(const Key('guidedConnectBanner')), findsOneWidget);
      expect(find.byKey(const Key('guidedTabletStep1')), findsOneWidget);
      expect(find.byKey(const Key('connectPinField')), findsOneWidget, reason: 'all of the screen own content is still there');
      // A wrong PIN: the screen says so in its own words, and the strip adds the calm way on.
      await t.enterText(find.byKey(const Key('connectPinField')), '1111');
      await t.runAsync(() async {
        await t.tap(find.byKey(const Key('connectOpen')));
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await t.pump();
      expect(find.byKey(const Key('connectMessage')), findsOneWidget);
      expect(find.byKey(const Key('guidedTabletRecover')), findsOneWidget);
      // The right PIN: the window opens and the strip shows the live waiting state.
      await t.enterText(find.byKey(const Key('connectPinField')), '4829');
      await t.runAsync(() async {
        await t.tap(find.byKey(const Key('connectOpen')));
        await Future<void>.delayed(const Duration(milliseconds: 400));
      });
      await t.pump();
      expect(find.byKey(const Key('connectWaiting')), findsOneWidget);
      expect(find.byKey(const Key('guidedTabletWait')), findsOneWidget);
      expect(find.byKey(const Key('guidedTabletStep3')), findsOneWidget);
      expect(connected, 0, reason: 'nothing is connected until the tablet really is');
    });
  });

  group('"Show me around again"', () {
    testWidgets('starts from the welcome, without asking for her name, age or PIN again, and the strip counts what is left', (t) async {
      await pump(t, progress: const GuidedProgress(seenVersion: 1, adultDone: true, adultStep: 'a.done'));
      expect(find.byKey(const Key('guidedTitle')), findsNothing);
      GuidedReplay.ask();
      await t.pumpAndSettle();
      expect(title(t), 'Welcome to Olive');
      expect(find.text('Step 1 of 5'), findsOneWidget);
      await t.tap(find.byKey(const Key('guidedNext')));
      await t.pumpAndSettle();
      expect(title(t), 'Connect her tablet', reason: 'About you, About her, Her clock and the PIN are not asked again');
      expect(find.byKey(const Key('guidedBack')), findsOneWidget);
    });

    testWidgets('replaying is skippable all the way out and leaves the home as it was', (t) async {
      await pump(t, progress: const GuidedProgress(seenVersion: 1, adultDone: true, adultStep: 'a.done'));
      GuidedReplay.ask();
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('guidedSkip'))); // past the welcome part
      await t.pumpAndSettle();
      expect(title(t), 'Connect her tablet');
      await t.tap(find.byKey(const Key('guidedSkip')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('guidedSkip')));
      await t.pumpAndSettle();
      expect(title(t), 'Help is close by');
      await t.tap(find.byKey(const Key('guidedNext')));
      await t.pumpAndSettle();
      await t.tap(find.text('Go to my home'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('guidedTitle')), findsNothing);
      expect(find.text('tile home.call'), findsOneWidget);
    });
  });

  group('what is new, for an install that already finished first run', () {
    final List<GuidedEntry> reg = <GuidedEntry>[_newStop('diary'), _newStop('garden')];

    testWidgets('an older install sees only the new stops, labelled What\'s new, once; Skip marks them seen', (t) async {
      await pump(t,
          anchors: <String>[..._kStops, 'home.diary', 'home.garden'],
          progress: const GuidedProgress(seenVersion: 1, adultDone: true, adultStep: 'a.done'),
          registered: reg, version: 2);
      expect(title(t), 'The diary');
      expect(find.byKey(const Key('guidedEyebrow')), findsOneWidget);
      expect(find.text("What's new"), findsOneWidget);
      expect(find.text('Step 1 of 2'), findsOneWidget);
      await t.tap(find.byKey(const Key('guidedNext')));
      await t.pumpAndSettle();
      expect(title(t), 'The garden');
      await t.tap(find.byKey(const Key('guidedBack')));
      await t.pumpAndSettle();
      expect(title(t), 'The diary');
      await t.tap(find.byKey(const Key('guidedSkip')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('guidedTitle')), findsNothing);
      final GuidedProgress p = await store.load();
      expect(p.seenVersion, 2);
      expect(p.adultStep, 'a.done', reason: 'a mini-tour never moves the first-run step');
    });

    testWidgets('"Do this later" hides it for now and leaves it for the next launch (not marked seen)', (t) async {
      await pump(t,
          anchors: <String>[..._kStops, 'home.diary'],
          progress: const GuidedProgress(seenVersion: 1, adultDone: true, adultStep: 'a.done'),
          registered: <GuidedEntry>[_newStop('diary')], version: 2);
      await t.tap(find.byKey(const Key('guidedLater')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('guidedTitle')), findsNothing);
      expect((await store.load()).seenVersion, 1);
    });

    testWidgets('an install that has seen the newest version sees nothing', (t) async {
      await pump(t, progress: const GuidedProgress(seenVersion: 2, adultDone: true, adultStep: 'a.done'), registered: reg, version: 2);
      expect(find.byKey(const Key('guidedTitle')), findsNothing);
    });

    testWidgets('a new install that is part-way through first run is not given the mini-tour on top', (t) async {
      await pump(t, progress: const GuidedProgress(adultStep: 'a.tablet'), registered: reg, version: 2);
      expect(title(t), 'Connect her tablet');
    });

    testWidgets('a stop for a feature that is off is skipped without a gap', (t) async {
      await pump(t,
          anchors: <String>[..._kStops, 'home.garden'],
          progress: const GuidedProgress(seenVersion: 1, adultDone: true, adultStep: 'a.done'),
          registered: <GuidedEntry>[
            const GuidedEntry(
                id: 'diary', half: GuidedHalf.adult, slot: 'adult.tour.features', kind: GuidedKind.coach, phase: 'tour', since: 2,
                whatsNew: true, needsFeature: 'diaryFeature', anchor: 'home.diary', title: 'The diary', words: 'x'),
            _newStop('garden'),
          ],
          version: 2);
      expect(title(t), 'The garden');
      expect(find.text('Step 1 of 1'), findsOneWidget);
    });
  });

  group('the developer simulation seam', () {
    testWidgets('on an install that already finished: starts the tour from the welcome, marked SIMULATED, with no data erased', (t) async {
      await pump(t, simulate: true, progress: const GuidedProgress(seenVersion: 1, adultDone: true, adultStep: 'a.done'));
      expect(title(t), 'Welcome to Olive');
      expect(find.byKey(const Key('simBand')), findsOneWidget);
      expect(find.text('SIMULATED (developer build)'), findsOneWidget);
    });

    testWidgets('the connect step is a stand-in that completes after one tap, and says it is simulated', (t) async {
      await pump(t, simulate: true, progress: const GuidedProgress(seenVersion: 1, adultDone: true));
      await t.tap(find.byKey(const Key('guidedNext'))); // welcome
      await t.pumpAndSettle();
      expect(title(t), 'Connect her tablet');
      await t.tap(find.byKey(const Key('guidedNext')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('simBand')), findsOneWidget);
      expect(find.byKey(const Key('simWaiting')), findsOneWidget);
      expect(find.text('Simulate: her tablet connected'), findsOneWidget);
      await t.tap(find.byKey(const Key('simConnect')));
      await t.pumpAndSettle();
      expect(title(t), 'Message banking', reason: 'it carried on exactly as a real connection would');
    });

    test('the define is off unless it is exactly the string true', () {
      expect(kSimOnboarding, isFalse, reason: 'tests and every normal build run without the define');
    });
  });

  group('large text and every width: nothing overflows', () {
    for (final Size size in const <Size>[Size(344, 700), Size(904, 800)]) {
      for (final String step in <String>['a.tablet', 'a.tour.care', 'a.done', 'a.help']) {
        testWidgets('${size.width.toInt()} wide at 2x text: $step', (t) async {
          await pump(t,
              size: size,
              text: 2.0,
              progress: GuidedProgress(adultStep: step, deferred: const <String>['tablet', 'tour']));
          expect(t.takeException(), isNull);
          expect(find.byKey(const Key('guidedNext')), findsOneWidget);
          await t.ensureVisible(find.byKey(const Key('guidedNext')));
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
        });
      }
    }
  });

  group('a11y', () {
    testWidgets('the strip is read as "Step 6 of 9", the title is a header, controls have spoken names', (t) async {
      final SemanticsHandle h = t.ensureSemantics();
      await pump(t, progress: const GuidedProgress(adultStep: 'a.tablet'));
      expect(find.bySemanticsLabel('Step 6 of 9'), findsOneWidget);
      expect(find.bySemanticsLabel('Back'), findsWidgets);
      expect(find.bySemanticsLabel('Skip this part'), findsWidgets);
      expect(find.bySemanticsLabel('Do this later'), findsWidgets);
      expect(find.bySemanticsLabel('I need a minute'), findsWidgets);
      expect(find.bySemanticsLabel(RegExp('Open the window.*')), findsWidgets);
      h.dispose();
    });
  });

  group('the real GuardianHome carries the anchors the tour points at', () {
    const List<RibbonBand> bands = <RibbonBand>[RibbonBand(0, 0.5, Colors.blue, 'school')];
    const GuardianHome home = GuardianHome(
        childName: 'Ivy', childLocalTime: '4:12 PM', childZoneAbbr: 'EDT', actorLocalTime: '3:12 PM CDT',
        childBands: bands, actorBands: bands);

    testWidgets('on a wide screen every stop finds its anchor', (t) async {
      await pump(t, size: const Size(900, 1800), home: home, progress: const GuidedProgress(adultStep: 'a.tour.bank'));
      for (final String a in _kStops) {
        expect(CoachAnchors.rectOf(a), isNotNull, reason: a);
      }
    });

    testWidgets('on the 344 cover screen only the icons that are there are lit; the rest say where to look, and nothing breaks', (t) async {
      await pump(t, size: const Size(344, 1700), home: home, progress: const GuidedProgress(adultStep: 'a.tour.care'));
      expect(t.takeException(), isNull);
      expect(CoachAnchors.rectOf('home.messageBanking'), isNotNull);
      expect(CoachAnchors.rectOf('home.more'), isNotNull);
      expect(CoachAnchors.rectOf('home.medsCare'), isNull, reason: 'the cover screen collapses these under More');
      expect(find.byKey(const Key('guidedNoFind')), findsOneWidget);
    });
  });
}
