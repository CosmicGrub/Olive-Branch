// OLIVE BRANCH — the guided first run's setup half, inside the existing GuardianOnboardingFlow: a welcome, then About you,
// About her (with her age band in words), Her clock and the PIN step, each with the strip and the five controls, and a
// PIN step that is a slot another lane can fill. Verified by CI, headless. MASTERFILE §8.5.13.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/device_role.dart';
import 'package:olive_client/guardian_local_scope.dart';
import 'package:olive_client/guardian_onboarding.dart';
import 'package:olive_client/guided_progress.dart';
import 'package:olive_client/guided_script.dart';
import 'package:olive_client/local_family.dart';

void main() {
  late GuardianLocalServices services;
  late MemoryGuidedProgressStore store;
  late List<LocalFamily> finished;

  setUp(() {
    services = GuardianLocalServices.memory(pinIterations: 500);
    store = MemoryGuidedProgressStore();
    finished = <LocalFamily>[];
  });

  /// A stand-in for the PIN screen the normal-keypad lane supplies: it stores a PIN for real, then calls back.
  Widget fakePinStep(BuildContext c, service, Future<void> Function() onSaved) => FilledButton(
        key: const Key('fakePinSave'),
        onPressed: () async {
          await service.setPin('4821');
          await onSaved();
        },
        child: const Text('Save the fake PIN'),
      );

  Future<void> pump(WidgetTester t, {Size size = const Size(412, 1400), double text = 1.0, GuidedPinStepBuilder? pin}) async {
    await t.binding.setSurfaceSize(size);
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(MaterialApp(
      builder: (BuildContext c, Widget? w) =>
          MediaQuery(data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(text)), child: w!),
      home: GuardianOnboardingFlow(
        role: DeviceRole.mom,
        services: services,
        guided: true,
        guideStore: store,
        pinStepBuilder: pin ?? fakePinStep,
        onFinished: finished.add,
      ),
    ));
    await t.pumpAndSettle();
  }

  String title(WidgetTester t) => t.widget<Text>(find.byKey(const Key('guidedTitle'))).data!;

  Future<void> tap(WidgetTester t, Key k) async {
    await t.ensureVisible(find.byKey(k));
    await t.tap(find.byKey(k));
    await t.pumpAndSettle();
  }

  Future<void> toPin(WidgetTester t) async {
    await tap(t, const Key('guidedNext')); // welcome
    await t.enterText(find.byKey(const Key('goName')), 'Sam');
    await tap(t, const Key('guidedNext'));
    await t.enterText(find.byKey(const Key('goChild')), 'Ivy');
    await tap(t, const Key('goAge_7'));
    await tap(t, const Key('guidedNext'));
    await tap(t, const Key('guidedNext')); // zone
  }

  testWidgets('it opens on the welcome: two sentences, two labelled pictures, "Step 1 of 9", nothing moving by itself', (t) async {
    await pump(t);
    expect(title(t), 'Welcome to Olive');
    expect(find.text('Step 1 of 9'), findsOneWidget);
    expect(find.text('Your phone'), findsOneWidget);
    expect(find.text('Her tablet'), findsOneWidget);
    expect(find.text("Let's begin"), findsOneWidget);
    await t.pump(const Duration(minutes: 20));
    expect(title(t), 'Welcome to Olive');
    expect(find.byKey(const Key('guidedBack')), findsOneWidget);
    expect(t.widget<TextButton>(find.byKey(const Key('guidedBack'))).onPressed, isNull, reason: 'nothing is behind the first step');
  });

  testWidgets('the steps in order, with the strip, the labels, and her age band in words', (t) async {
    await pump(t);
    await tap(t, const Key('guidedNext'));
    expect(title(t), 'About you');
    expect(find.text('Step 2 of 9'), findsOneWidget);
    expect(find.text('What she calls you'), findsOneWidget);
    await t.enterText(find.byKey(const Key('goName')), 'Sam');
    await tap(t, const Key('guidedNext'));
    expect(title(t), 'About her');
    expect(find.text('Step 3 of 9'), findsOneWidget);
    expect(find.text('Her age band'), findsOneWidget);
    await t.enterText(find.byKey(const Key('goChild')), 'Ivy');
    await tap(t, const Key('goAge_7'));
    expect(t.widget<Text>(find.byKey(const Key('goBand'))).data, contains('ages 5 to 7'));
    await tap(t, const Key('goAge_4'));
    expect(t.widget<Text>(find.byKey(const Key('goBand'))).data, contains('ages 3 to 4'));
    await tap(t, const Key('goAge_13'));
    expect(t.widget<Text>(find.byKey(const Key('goBand'))).data, contains('ages 13 to 17'));
    await tap(t, const Key('goAge_9'));
    expect(t.widget<Text>(find.byKey(const Key('goBand'))).data, contains('ages 8 to 12'));
    await tap(t, const Key('guidedNext'));
    expect(title(t), 'Her clock');
    expect(find.text('Step 4 of 9'), findsOneWidget);
    expect(find.byKey(const Key('guidedSkip')), findsOneWidget, reason: 'the default is fine: it can be skipped');
    await tap(t, const Key('guidedNext'));
    expect(title(t), 'Choose your PIN');
    expect(find.text('Step 5 of 9'), findsOneWidget);
    expect(find.text('PIN keypad'), findsOneWidget);
    expect(find.text('Never leaves this phone'), findsOneWidget);
  });

  testWidgets('a form step has no Skip and says why, calmly; "Do this later" is "I need a minute"', (t) async {
    await pump(t);
    await tap(t, const Key('guidedNext'));
    expect(find.byKey(const Key('guidedSkip')), findsNothing);
    expect(find.byKey(const Key('guidedNeededNote')), findsOneWidget);
    expect(find.textContaining('no skip'), findsOneWidget);
    await tap(t, const Key('guidedLater'));
    expect(find.text(GuidedWords.pauseTitle), findsOneWidget);
    await tap(t, const Key('guidedResume'));
    expect(title(t), 'About you');
  });

  testWidgets('Back at every step, and what was typed stays', (t) async {
    await pump(t);
    await tap(t, const Key('guidedNext'));
    await t.enterText(find.byKey(const Key('goName')), 'Sam');
    await tap(t, const Key('guidedNext'));
    await t.enterText(find.byKey(const Key('goChild')), 'Ivy');
    await tap(t, const Key('guidedBack'));
    expect(title(t), 'About you');
    expect(t.widget<TextField>(find.byKey(const Key('goName'))).controller!.text, 'Sam');
    await tap(t, const Key('guidedNext'));
    expect(t.widget<TextField>(find.byKey(const Key('goChild'))).controller!.text, 'Ivy');
    await tap(t, const Key('guidedBack'));
    await tap(t, const Key('guidedBack'));
    expect(title(t), 'Welcome to Olive');
  });

  testWidgets('a missing answer is said kindly and keeps the person where they are (never blaming)', (t) async {
    await pump(t);
    await tap(t, const Key('guidedNext'));
    await tap(t, const Key('guidedNext')); // no name
    expect(title(t), 'About you');
    expect(find.byKey(const Key('goError')), findsOneWidget);
    expect(find.text('Please add your name.'), findsOneWidget);
  });

  testWidgets('saving the PIN keeps the family, saves "Connect her tablet" as the next step and hands over to her home', (t) async {
    await pump(t);
    await toPin(t);
    expect(finished, isEmpty);
    expect(await services.families.load(), isNull, reason: 'nothing personal is kept before the PIN');
    await t.runAsync(() async {
      await t.tap(find.byKey(const Key('fakePinSave')));
      await Future<void>.delayed(const Duration(milliseconds: 600));
    });
    await t.pump(); // the hand-over shows a spinner for a moment, which never settles
    await t.pump(const Duration(milliseconds: 100));
    expect(finished, hasLength(1));
    expect(finished.single.childName, 'Ivy');
    expect(finished.single.age, 7);
    expect(await services.pin.isSet(), isTrue);
    expect((await store.load()).adultStep, 'a.tablet', reason: 'her home resumes the guided run at the connect step');
  });

  testWidgets('a PIN that could not be kept is said plainly and nothing moves on', (t) async {
    await pump(t, pin: (BuildContext c, service, Future<void> Function() onSaved) => const Text('no pin form here'));
    await toPin(t);
    expect(find.text('no pin form here'), findsOneWidget);
    expect(finished, isEmpty);
  });

  testWidgets('killed and relaunched before the PIN: it starts again at About you (the welcome was seen); nothing personal was kept', (t) async {
    await store.save(const GuidedProgress(adultStep: 'a.her'));
    await pump(t);
    expect(title(t), 'About you');
    expect(find.text('Step 2 of 9'), findsOneWidget);
    expect(t.widget<TextField>(find.byKey(const Key('goName'))).controller!.text, isEmpty);
  });

  testWidgets('killed on the welcome: relaunch opens on the welcome', (t) async {
    await store.save(const GuidedProgress(adultStep: 'a.welcome'));
    await pump(t);
    expect(title(t), 'Welcome to Olive');
  });

  testWidgets('each step the person reaches is written down as they arrive', (t) async {
    await pump(t);
    expect((await store.load()).adultStep, 'a.welcome');
    await tap(t, const Key('guidedNext'));
    expect((await store.load()).adultStep, 'a.you');
  });

  testWidgets('without the guided flag the first run is exactly the plain five steps (an older caller is unaffected)', (t) async {
    await t.binding.setSurfaceSize(const Size(800, 3200));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(MaterialApp(
        home: GuardianOnboardingFlow(role: DeviceRole.mom, services: services, onFinished: finished.add)));
    await t.pumpAndSettle();
    expect(find.text('About you'), findsOneWidget);
    expect(find.byKey(const Key('guidedNext')), findsNothing);
    expect(find.byKey(const Key('goYouNext')), findsOneWidget);
  });

  for (final Size size in const <Size>[Size(344, 700), Size(904, 800)]) {
    testWidgets('${size.width.toInt()} wide at 2x text: every setup step fits, scrolls, and keeps its controls', (t) async {
      await pump(t, size: size, text: 2.0);
      void ok(String where) {
        expect(t.takeException(), isNull, reason: where);
        expect(find.byKey(const Key('guidedNext')), findsOneWidget, reason: where);
      }

      ok('welcome');
      await tap(t, const Key('guidedNext'));
      ok('about you');
      await t.enterText(find.byKey(const Key('goName')), 'Sam');
      await tap(t, const Key('guidedNext'));
      ok('about her');
      await t.enterText(find.byKey(const Key('goChild')), 'Ivy');
      await tap(t, const Key('goAge_7'));
      await tap(t, const Key('guidedNext'));
      ok('her clock');
      await tap(t, const Key('guidedNext'));
      expect(t.takeException(), isNull, reason: 'the PIN step');
      expect(find.byKey(const Key('fakePinSave')), findsOneWidget);
      await t.ensureVisible(find.byKey(const Key('guidedPause')));
      expect(t.takeException(), isNull);
    });
  }

  testWidgets('a11y: the strip is read as one phrase, the title is a header, every control has a spoken name', (t) async {
    final SemanticsHandle h = t.ensureSemantics();
    await pump(t);
    expect(find.bySemanticsLabel('Step 1 of 9'), findsOneWidget);
    expect(find.bySemanticsLabel('I need a minute'), findsWidgets);
    expect(find.bySemanticsLabel('Do this later'), findsWidgets);
    h.dispose();
  });
}
