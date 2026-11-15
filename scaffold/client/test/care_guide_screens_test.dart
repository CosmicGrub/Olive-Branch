// The guardian-shell care guide screens (G1-G5) over the loader, with synthetic guides. UNVERIFIED until CI runs it.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/care_guide_gate.dart';
import 'package:olive_client/care_guide_loader.dart';
import 'package:olive_client/care_guide_models.dart';
import 'package:olive_client/care_guide_plan.dart';
import 'package:olive_client/care_guide_screens.dart';
import 'package:olive_client/hub_widgets.dart';

import 'care_guide_fixtures.dart';

class _MiaPlan implements ChildPlanSource {
  const _MiaPlan();
  @override
  Future<ChildPlanForGuide?> forGuide(String guideId) async => const ChildPlanForGuide(
        childName: 'Mia', pronoun: 'her', notes: <ChildPlanNote>[ChildPlanNote(label: 'Sample', text: 'plan line')]);
}

Widget _host(Widget child) => MaterialApp(home: child);

CareGuideLoader _reviewedLoader() => CareGuideLoader(
      bundle: bundleOf(<Map<String, Object?>>[
        fixtureGuide(id: 'who-to-call'),
        fixtureGuide(id: 'other-guide'),
      ]),
      policy: const CareGuidePolicy(releaseMode: true),
    );

CareGuideLoader _draftLoader() => CareGuideLoader(
      bundle: bundleOf(<Map<String, Object?>>[
        fixtureGuide(id: 'who-to-call', status: 'DRAFT_UNREVIEWED'),
        fixtureGuide(id: 'other-guide', status: 'DRAFT_UNREVIEWED'),
      ]),
      policy: const CareGuidePolicy(draftPreview: true),
    );

Iterable<String> _texts(WidgetTester t) => t.widgetList<Text>(find.byType(Text)).map((Text w) => w.data ?? w.textSpan?.toPlainText() ?? '');

void main() {
  testWidgets('G1: the emergency button is first, above every guide, and opens the who-to-call guide', (WidgetTester t) async {
    await t.pumpWidget(_host(CareGuideLibraryScreen(principalRole: 'guardian', loader: _reviewedLoader())));
    await t.pumpAndSettle();
    final double button = t.getTopLeft(find.byKey(const Key('careEmergencyButton'))).dy;
    expect(button, lessThan(t.getTopLeft(find.byKey(const Key('careGuide_who-to-call'))).dy));
    expect(button, lessThan(t.getTopLeft(find.byKey(const Key('careGuide_other-guide'))).dy));
    await t.tap(find.byKey(const Key('careEmergencyButton')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('careHelplines')), findsOneWidget); // G3: the numbers are on the screen
  });

  testWidgets('G1: with nothing available the emergency button is still there and the draft banner is not', (WidgetTester t) async {
    await t.pumpWidget(_host(CareGuideLibraryScreen(
        principalRole: 'guardian', loader: CareGuideLoader(bundle: bundleOf(<Map<String, Object?>>[]), policy: const CareGuidePolicy(releaseMode: true)))));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('careEmergencyButton')), findsOneWidget);
    expect(find.byKey(const Key('careDraftBanner')), findsNothing);
    await t.tap(find.byKey(const Key('careEmergencyButton')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('careEmergencyUnavailable')), findsOneWidget);
  });

  testWidgets('a previewed draft carries the permanent banner on the library, the guide and who-to-call', (WidgetTester t) async {
    await t.pumpWidget(_host(CareGuideLibraryScreen(principalRole: 'guardian', loader: _draftLoader())));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('careDraftBanner')), findsOneWidget);
    expect(find.text(kDraftBannerText), findsWidgets);
    await t.tap(find.byKey(const Key('careGuide_other-guide')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('careDraftBanner')), findsOneWidget);
    expect(find.text('Last reviewed: not reviewed'), findsOneWidget);
    await t.pageBack();
    await t.pumpAndSettle();
    await t.tap(find.byKey(const Key('careEmergencyButton')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('careDraftBanner')), findsOneWidget);
  });

  testWidgets('a reviewed guide has no draft banner and shows its review date, retrieved date and sources, always', (WidgetTester t) async {
    await t.pumpWidget(_host(CareGuideScreen(principalRole: 'guardian', guide: fixtureCareGuide())));
    expect(find.byKey(const Key('careDraftBanner')), findsNothing);
    expect(find.text('Last reviewed: 2030-01-02'), findsOneWidget);
    expect(find.text('Sources retrieved: 2030-01-01'), findsOneWidget);
    await t.drag(find.byKey(const Key('careGuideBody')), const Offset(0, -2000)); // scroll the body: the footer stays
    await t.pump();
    expect(find.byKey(const Key('careLastReviewed')), findsOneWidget);
    await t.tap(find.byKey(const Key('careSourcesButton')));
    await t.pumpAndSettle();
    expect(find.text('Sample Org: Sample page'), findsOneWidget);
    expect(find.text('https://example.org/p'), findsOneWidget);
  });

  testWidgets('G2: emergency signs come before the steps and before the age tabs, whatever the stored order', (WidgetTester t) async {
    await t.pumpWidget(_host(CareGuideScreen(principalRole: 'guardian', guide: fixtureCareGuide())));
    final double emergency = t.getTopLeft(find.byKey(const Key('careBlock_emergency'))).dy;
    expect(emergency, lessThan(t.getTopLeft(find.byKey(const Key('careAgeTabs'))).dy));
    expect(emergency, lessThan(t.getTopLeft(find.byKey(const Key('careBlock_doNow'))).dy));
  });

  testWidgets('G2: age tabs switch the band', (WidgetTester t) async {
    await t.pumpWidget(_host(CareGuideScreen(principalRole: 'guardian', guide: fixtureCareGuide())));
    expect(find.text('Sample band text'), findsOneWidget);
    expect(find.text('Other band text'), findsNothing);
    await t.tap(find.byKey(const Key('careAge_b-band')));
    await t.pump();
    expect(find.text('Other band text'), findsOneWidget);
    expect(find.text('Second band'), findsOneWidget); // a draft label is used where there is one
    expect(find.text('a-band'), findsOneWidget); // and the key as written where there is none
  });

  testWidgets('G3: phone numbers on screen are the guide data, and a guide without any shows none', (WidgetTester t) async {
    await t.pumpWidget(_host(WhoToCallScreen(principalRole: 'guardian', guide: fixtureCareGuide())));
    expect(find.text('555-0100'), findsOneWidget);
    await t.pumpWidget(_host(WhoToCallScreen(principalRole: 'guardian', guide: fixtureCareGuide(helplines: <Map<String, Object?>>[]))));
    await t.pump();
    final RegExp iso = RegExp(r'\d{4}-\d{2}-\d{2}');
    for (final String s in _texts(t)) {
      expect(RegExp(r'\d{3}').hasMatch(s.replaceAll(iso, '')), false, reason: 'a number appeared that is not guide data: "$s"');
    }
  });

  testWidgets('G3: a helpline for a region the review does not cover is not drawn; a covered one is', (WidgetTester t) async {
    final List<Map<String, Object?>> lines = <Map<String, Object?>>[
      <String, Object?>{'region': 'XX', 'name': 'Own line', 'number': '555-0100', 'sources': <int>[1]},
      <String, Object?>{'region': 'YY', 'name': 'Other line', 'number': '555-0200', 'sources': <int>[1]},
    ];
    await t.pumpWidget(_host(WhoToCallScreen(principalRole: 'guardian', guide: fixtureCareGuide(helplines: lines))));
    expect(find.text('555-0100'), findsOneWidget);
    expect(find.text('555-0200'), findsNothing);
    expect(find.text('Other places'), findsNothing);
    await t.pumpWidget(_host(WhoToCallScreen(principalRole: 'guardian', guide: fixtureCareGuide(helplines: lines, regions: <String>['XX', 'YY']))));
    expect(find.text('555-0100'), findsOneWidget);
    expect(find.text('555-0200'), findsOneWidget);
    // a previewed draft shows only its own region even if the record (wrongly) lists more
    await t.pumpWidget(_host(WhoToCallScreen(
        principalRole: 'guardian', guide: fixtureCareGuide(status: 'DRAFT_UNREVIEWED', helplines: lines, regions: <String>['XX', 'YY']), draft: true)));
    expect(find.text('555-0200'), findsNothing);
  });

  testWidgets('a post-episode block is drawn under a neutral heading, not "Same-day doctor"', (WidgetTester t) async {
    final Map<String, Object?> m = fixtureGuide()
      ..['blocks'] = <Object?>[
        <String, Object?>{'kind': 'afterEpisode', 'items': <Object?>[<String, Object?>{'text': 'Sample follow-up line', 'sources': <int>[1]}]},
      ];
    await t.pumpWidget(_host(CareGuideScreen(principalRole: 'guardian', guide: CareGuide.fromJson(m))));
    expect(find.text('After the episode'), findsOneWidget);
    expect(find.text('Same-day doctor'), findsNothing);
    expect(find.text('Sample follow-up line'), findsOneWidget);
  });

  testWidgets('no text on a reviewed guide screen contains reviewer vocabulary', (WidgetTester t) async {
    await t.pumpWidget(_host(CareGuideScreen(principalRole: 'guardian', guide: fixtureCareGuide(), plan: const _MiaPlan())));
    await t.pumpAndSettle();
    for (final String s in _texts(t)) {
      expect(RegExp('clinician|source\\s*\\d|disagreement\\s*\\d', caseSensitive: false).hasMatch(s), false, reason: s);
    }
  });

  group('the For <child> strip', () {
    testWidgets('renders nothing until a plan exists (no plan source, no rule line)', (WidgetTester t) async {
      await t.pumpWidget(_host(CareGuideScreen(principalRole: 'guardian', guide: fixtureCareGuide())));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('careForChild')), findsNothing);
      expect(find.byKey(const Key('careRuleLine')), findsNothing);
    });

    testWidgets('with a plan on a reviewed guide it shows the plan and the rule line, word for word', (WidgetTester t) async {
      await t.pumpWidget(_host(CareGuideScreen(principalRole: 'guardian', guide: fixtureCareGuide(withEmergencyBlock: false), plan: const _MiaPlan())));
      await t.pumpAndSettle();
      expect(find.text('For Mia'), findsOneWidget);
      expect(find.text('Sample: plan line'), findsOneWidget);
      expect(find.text("If Mia's plan says something different from this guide, follow her plan and call her doctor."), findsOneWidget);
    });

    testWidgets('on an emergency-tier guide the rule line is withheld, so nothing can delay a call for help', (WidgetTester t) async {
      for (final CareGuide g in <CareGuide>[
        fixtureCareGuide(), // has an emergency block
        fixtureCareGuide(category: 'emergency', withEmergencyBlock: false), // emergency category alone
      ]) {
        expect(g.isEmergencyTier, true);
        await t.pumpWidget(_host(CareGuideScreen(principalRole: 'guardian', guide: g, plan: const _MiaPlan())));
        await t.pumpAndSettle();
        expect(find.text('For Mia'), findsOneWidget); // the guardian's own plan notes still show
        expect(find.byKey(const Key('careRuleLine')), findsNothing);
      }
      await t.pumpWidget(_host(WhoToCallScreen(principalRole: 'guardian', guide: fixtureCareGuide(id: 'who-to-call', category: 'emergency'), plan: const _MiaPlan())));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('careRuleLine')), findsNothing);
    });

    testWidgets('on a previewed draft the rule line is withheld (it is advice, so it follows the review flag)', (WidgetTester t) async {
      await t.pumpWidget(_host(CareGuideScreen(
          principalRole: 'guardian', guide: fixtureCareGuide(status: 'DRAFT_UNREVIEWED'), draft: true, plan: const _MiaPlan())));
      await t.pumpAndSettle();
      expect(find.text('For Mia'), findsOneWidget);
      expect(find.byKey(const Key('careRuleLine')), findsNothing);
    });

    test('a name ending in s gets a clean possessive', () {
      expect(childPlanRuleLine(const ChildPlanForGuide(childName: 'Jess', notes: <ChildPlanNote>[])),
          "If Jess' plan says something different from this guide, follow their plan and call their doctor.");
    });
  });

  testWidgets('G4: the new carer screen leads with the emergency button then the chosen guides', (WidgetTester t) async {
    final CareGuideLibrary lib = await _reviewedLoader().load();
    await t.pumpWidget(_host(NewCarerStartScreen(principalRole: 'guardian', library: lib, selectedIds: const <String>{'other-guide'})));
    final double button = t.getTopLeft(find.byKey(const Key('careEmergencyButton'))).dy;
    expect(button, lessThan(t.getTopLeft(find.byKey(const Key('careGuide_other-guide'))).dy));
    expect(find.byKey(const Key('careGuide_who-to-call')), findsNothing); // reached through the button, not listed twice
  });

  testWidgets('G5: helper-page selection toggles and reports the choice', (WidgetTester t) async {
    final CareGuideLibrary lib = await _reviewedLoader().load();
    Set<String>? last;
    await t.pumpWidget(_host(HelperPageSelectionScreen(principalRole: 'guardian', library: lib, onChanged: (Set<String> s) => last = s)));
    await t.tap(find.byKey(const Key('careHelperPick_other-guide')));
    await t.pump();
    expect(last, <String>{'who-to-call'});
  });

  group('guardians only', () {
    for (final String role in <String>['child', 'carer', '']) {
      testWidgets('role "$role" sees nothing from the content on any screen', (WidgetTester t) async {
        final CareGuideLibrary lib = await _reviewedLoader().load();
        for (final Widget w in <Widget>[
          CareGuideLibraryScreen(principalRole: role, loader: _reviewedLoader()),
          CareGuideScreen(principalRole: role, guide: fixtureCareGuide()),
          WhoToCallScreen(principalRole: role, guide: fixtureCareGuide()),
          NewCarerStartScreen(principalRole: role, library: lib),
          HelperPageSelectionScreen(principalRole: role, library: lib),
        ]) {
          await t.pumpWidget(_host(w));
          await t.pumpAndSettle();
          expect(find.byKey(const Key('careGuidesGuardiansOnly')), findsOneWidget);
          expect(find.textContaining('Sample'), findsNothing);
          expect(find.byKey(const Key('careEmergencyButton')), findsNothing);
        }
      });
    }
  });

  group('the guardian hub tile', () {
    testWidgets('in a default build (the real bundled assets hold no guide) it renders nothing', (WidgetTester t) async {
      await t.pumpWidget(_host(const Scaffold(body: CareGuidesHubTile())));
      await t.pumpAndSettle();
      expect(find.byType(HubTile), findsNothing);
    });

    testWidgets('it appears only once a guide has passed the gate', (WidgetTester t) async {
      await t.pumpWidget(_host(Scaffold(body: CareGuidesHubTile(loader: _reviewedLoader()))));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('moreCareGuides')), findsOneWidget);
      await t.tap(find.byKey(const Key('moreCareGuides')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('careEmergencyButton')), findsOneWidget);
    });
  });
}
