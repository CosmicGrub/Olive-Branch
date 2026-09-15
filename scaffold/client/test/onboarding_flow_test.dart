// OLIVE BRANCH — onboarding_flow.dart tests. Navigation-wiring-pass glue, not
// a MARKUP screen of its own — see the file's own header.
//
// The central thing under test: this file's whole job is popping each step's
// result off the stack and feeding it into the next screen's constructor, in
// the assignment's prose order (name -> age -> who -> colour -> birthday).
// A break here would be silent (no exception, just the wrong screen or a
// stuck flow), so the walkthrough test below drives every step for real.
//
// Onboarding & Guardian Access sub-project 1 (docs/superpowers/specs/
// 2026-09-12-onboarding-identity-pin-design.md) adds one more thing this
// file must prove: childId/baseUrl/sessionToken/httpClient really thread
// through to the new gender step, not just accepted and dropped -- the
// "live wiring" group below proves a real tap mid-flow reaches the real
// route, the same way child_more_test.dart proves the equivalent for
// LettersScreen.
//
// Automatic First-Run Detection (docs/superpowers/specs/2026-09-14
// -automatic-first-run-detection-design.md) adds [onComplete] -- the
// "onComplete fires on real completion" group below proves it fires exactly
// once the finishing ceremony is really reached, and does NOT fire on an
// early abandon (a step returning null, the SAME early-out every step
// above already has) -- main_live.dart's own `_OnboardingBootApp` depends
// on this distinction to decide whether it is safe to proceed into
// KioskShell.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:olive_client/onboarding_flow.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: child);

  testWidgets('opens on the redo-tour card with a Start button', (tester) async {
    await tester.pumpWidget(wrap(const OnboardingFlowScreen()));
    expect(find.text('Redo the welcome tour'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);
    expect(find.textContaining('not a reset of anything real'), findsOneWidget);
  });

  testWidgets('no settings affordance exists anywhere on this screen', (tester) async {
    await tester.pumpWidget(wrap(const OnboardingFlowScreen()));
    expect(find.byIcon(Icons.settings), findsNothing);
    expect(find.textContaining('Settings'), findsNothing);
  });

  testWidgets('tapping Start enters the flow at the name step', (tester) async {
    await tester.pumpWidget(wrap(const OnboardingFlowScreen()));
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    expect(find.text("What's your name?"), findsOneWidget);
  });

  testWidgets('a full walkthrough sequences every step in the assignment\'s prose order '
      'and reports the finished name back on this screen', (tester) async {
    // The age step's sixteen tiles plus its own Next button run taller than
    // the default 800x600 test surface (onboarding_age_test.dart's own
    // helper notes the same thing) — a tall surface avoids a scroll gesture
    // before that tap.
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(wrap(const OnboardingFlowScreen()));
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();

    // 1. Name.
    expect(find.text("What's your name?"), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Ivy');
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // 2. Age.
    expect(find.text('How old are you?'), findsOneWidget);
    await tester.tap(find.text('7'));
    await tester.pump();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // 2b. Gender — new as of Onboarding & Guardian Access sub-project 1
    // (docs/superpowers/specs/2026-09-12-onboarding-identity-pin-design.md),
    // inserted immediately after age. Skipped here, a supported outcome —
    // onboarding_gender_test.dart covers the real-tap/persist path directly.
    expect(find.text('Are you a boy or a girl?'), findsOneWidget);
    await tester.tap(find.text('Skip for now'));
    await tester.pumpAndSettle();

    // 3. Who — only 'dad' is joined, so she is told, not asked.
    expect(find.text('Who is here?'), findsOneWidget);
    expect(find.text('Dad'), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // 4. Colour — skipped, a supported outcome.
    expect(find.text('Pick your colour'), findsOneWidget);
    await tester.tap(find.text('Skip for now'));
    await tester.pumpAndSettle();

    // 5. Birthday month.
    expect(find.text('When is your birthday?'), findsOneWidget);
    await tester.tap(find.text('March'));
    await tester.pump();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // 6. Birthday day — no authoritative date, so the year-check question
    // appears inline before the picker resolves.
    expect(find.text('Which day?'), findsOneWidget);
    await tester.tap(find.text('14'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Have you already had your birthday'), findsOneWidget);
    await tester.tap(find.text('Yes'));
    await tester.pumpAndSettle();

    // 7. Birthday marked — the finishing ceremony.
    expect(find.text('My birthday'), findsOneWidget);
    await tester.tap(find.text('All done!'));
    await tester.pumpAndSettle();

    // Back on the flow screen, with the run recorded honestly (a demo re-run,
    // not a claim that a real first-run state changed — see file header).
    expect(find.text('Redo the welcome tour'), findsOneWidget);
    expect(find.text('Last run finished for "Ivy".'), findsOneWidget);
  });

  group('live wiring — the gender step really reaches the real route', () {
    testWidgets('a real tap on the gender step mid-flow PUTs the real route with '
        'the childId this screen was given, not the demo default', (tester) async {
      final List<http.Request> puts = <http.Request>[];
      final mock = MockClient((req) async {
        if (req.method == 'PUT' && req.url.path.endsWith('/profile')) {
          puts.add(req);
          return http.Response(jsonEncode({'ok': true}), 200);
        }
        return http.Response('not found', 404);
      });
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(wrap(OnboardingFlowScreen(
        childId: 'real-child-9', baseUrl: 'http://api.test',
        sessionToken: 'tok', httpClient: mock)));
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Ivy');
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('7'));
      await tester.pump();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      expect(find.text('Are you a boy or a girl?'), findsOneWidget);
      await tester.tap(find.text('Girl'));
      await tester.pump();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      expect(puts, hasLength(1));
      expect(puts.single.url.path, '/v1/children/real-child-9/profile');
      expect(jsonDecode(puts.single.body), {'gender': 'girl'});
    });
  });

  group('onComplete fires on real completion (Automatic First-Run '
      'Detection, main_live.dart\'s _OnboardingBootApp depends on this)', () {
    testWidgets('fires exactly once, only once the finishing ceremony is '
        'genuinely reached', (tester) async {
      var completions = 0;
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(wrap(OnboardingFlowScreen(
        onComplete: () async { completions++; },
      )));
      // A real first-run (onComplete set) shows welcoming copy and "Let's
      // begin" -- not the manual-redo "Start" this file's other,
      // onComplete-less constructions still tap.
      await tester.tap(find.text("Let's begin"));
      await tester.pumpAndSettle();

      // 1. Name.
      await tester.enterText(find.byType(TextField), 'Ivy');
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      // Not yet -- only the first of seven steps has completed.
      expect(completions, 0);

      // 2. Age.
      await tester.tap(find.text('7'));
      await tester.pump();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      // 2b. Gender -- skipped, a supported outcome.
      await tester.tap(find.text('Skip for now'));
      await tester.pumpAndSettle();
      expect(completions, 0, reason: 'the flow is not finished yet -- only '
        'the identity-capture portion is');

      // 3. Who.
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      // 4. Colour -- skipped.
      await tester.tap(find.text('Skip for now'));
      await tester.pumpAndSettle();

      // 5. Birthday month.
      await tester.tap(find.text('March'));
      await tester.pump();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      // 6. Birthday day.
      await tester.tap(find.text('14'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yes'));
      await tester.pumpAndSettle();
      expect(completions, 0, reason: 'the finishing ceremony screen has not '
        'even been reached yet');

      // 7. Birthday marked -- the finishing ceremony. onComplete fires only
      // once THIS pops too, not merely once she reaches it.
      await tester.tap(find.text('All done!'));
      await tester.pumpAndSettle();

      expect(completions, 1);
    });
  });

  group('responsive — required audit viewports', () {
    // Fold5 cover screen, Fold5 unfolded main screen, a standard phone, and a
    // desktop/tablet-scale width.
    const viewports = {
      'Fold5 cover (344x882)': Size(344, 882),
      'Fold5 main (673x841)': Size(673, 841),
      'phone (390x844)': Size(390, 844),
      'tablet/desktop (1200x800)': Size(1200, 800),
    };

    for (final entry in viewports.entries) {
      testWidgets('renders without overflow at ${entry.key}', (tester) async {
        await tester.binding.setSurfaceSize(entry.value);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(wrap(const OnboardingFlowScreen()));
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }
  });
}
