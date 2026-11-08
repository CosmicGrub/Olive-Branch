// OLIVE BRANCH — the guardian's Compass screens: two gentle questions, the
// suggestions, the suites shelf and the two profiles. Nothing is switched on
// without a guardian's tap, "not sure" and "not now" remember nothing, the shelf
// shows on/off and never use, and a child principal is refused at every screen.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/access_settings.dart';
import 'package:olive_client/compass_logic.dart';
import 'package:olive_client/compass_repositories.dart';
import 'package:olive_client/compass_screens.dart';
import 'package:olive_client/family_structure_logic.dart';
import 'package:olive_client/growing_care_store.dart';
import 'package:olive_client/guardian_more.dart';
import 'package:olive_client/rhythm_voice_repositories.dart';
import 'package:olive_client/village_repositories.dart';

import 'village_support.dart';

class _Rig {
  _Rig() {
    rhythm = RhythmVoiceService.memory(childId: 'ivy');
    village = freshVillage();
    growing = GrowingCareStores.memory();
    access = MemoryAccessRepository();
    repo = MemoryCompassRepository();
  }
  late final MemoryCompassRepository repo;
  late final RhythmVoiceService rhythm;
  late final VillageService village;
  late final GrowingCareStores growing;
  late final MemoryAccessRepository access;

  CompassService service({FamilyPrincipal? principal}) => CompassService(
      childId: 'ivy', repo: repo, access: access,
      ports: suitePortsFor(rhythmVoice: rhythm, village: village, growingCare: growing, principal: principal ?? guardian));
}

Future<void> big(WidgetTester t) => phone(t, w: 700, h: 3000);

Future<void> show(WidgetTester t, Widget w) async {
  await t.pumpWidget(app(const SizedBox()));
  await t.pumpWidget(app(w));
  await t.pumpAndSettle();
}

Future<void> tapKey(WidgetTester t, String key) async {
  await t.ensureVisible(find.byKey(Key(key)));
  await t.tap(find.byKey(Key(key)));
  await t.pumpAndSettle();
}

void main() {
  group('the hub', () {
    testWidgets('promises it only shapes suggestions, is on this device only, and lists the five places', (WidgetTester t) async {
      await big(t);
      await show(t, CompassHubScreen(childName: 'Ivy', service: _Rig().service(), principal: guardian));
      expect(find.textContaining('This only shapes suggestions'), findsOneWidget);
      expect(find.textContaining('Kept on this device only'), findsOneWidget);
      expect(find.textContaining('nothing is switched on without you'), findsOneWidget);
      for (final String k in <String>['rowWho', 'rowNeeds', 'rowSuggest', 'rowShelf', 'rowProfiles']) {
        expect(find.byKey(Key(k)), findsOneWidget, reason: k);
      }
    });

    testWidgets('the hub links through to every screen', (WidgetTester t) async {
      await big(t);
      final Map<String, Type> rows = <String, Type>{
        'rowWho': CompassQuestionScreen, 'rowNeeds': CompassQuestionScreen, 'rowSuggest': CompassSuggestScreen,
        'rowShelf': SuitesShelfScreen, 'rowProfiles': ProfilesScreen,
      };
      for (final MapEntry<String, Type> e in rows.entries) {
        await show(t, CompassHubScreen(childName: 'Ivy', service: _Rig().service(), principal: guardian));
        await tapKey(t, e.key);
        expect(find.byType(e.value), findsOneWidget, reason: e.key);
      }
    });

    testWidgets('it is reachable from the guardian Settings hub, under Family', (WidgetTester t) async {
      await big(t);
      await show(t, const GuardianMoreScreen(childName: 'Ivy', childAge: 6));
      await t.ensureVisible(find.byKey(const Key('moreSettings')));
      await t.tap(find.byKey(const Key('moreSettings')));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const Key('settingsRow_compass')));
      await t.tap(find.byKey(const Key('settingsRow_compass')));
      await t.pumpAndSettle();
      expect(find.byType(CompassHubScreen), findsOneWidget);
    });
  });

  group('the questions', () {
    testWidgets('step 1 offers every way of looking, as chips, and says any or none is fine', (WidgetTester t) async {
      await big(t);
      await show(t, CompassQuestionScreen(step: CompassStep.who, childName: 'Ivy', service: _Rig().service(), principal: guardian));
      for (final CompassOption o in compassWhoOptions) {
        expect(find.byKey(Key('opt_${o.id}')), findsOneWidget, reason: o.id);
      }
      expect(find.byKey(const Key('opt_quiet')), findsNothing, reason: 'a need is not on the who screen');
      expect(find.textContaining('Choose any, or none'), findsOneWidget);
      expect(find.byKey(const Key('compassNotSure')), findsOneWidget);
      expect(find.byKey(const Key('compassSkip')), findsOneWidget);
    });

    testWidgets('ticking and saving stores the ids; the other step is untouched', (WidgetTester t) async {
      await big(t);
      final CompassService svc = _Rig().service();
      await svc.saveAnswers(guardian, const CompassAnswers(needs: <String>{'quiet'}));
      await show(t, CompassQuestionScreen(step: CompassStep.who, childName: 'Ivy', service: svc, principal: guardian));
      await tapKey(t, 'opt_twoHomes');
      await tapKey(t, 'opt_siblings');
      await tapKey(t, 'compassSave');
      final CompassAnswers a = (await svc.load(guardian)).answers;
      expect(a.who, <String>{'twoHomes', 'siblings'});
      expect(a.needs, <String>{'quiet'});
    });

    testWidgets('step 2 shows supports, never a diagnosis, and a re-opened step shows what was chosen', (WidgetTester t) async {
      await big(t);
      final CompassService svc = _Rig().service();
      await svc.saveAnswers(guardian, const CompassAnswers(needs: <String>{'knowNext', 'pictures'}));
      await show(t, CompassQuestionScreen(step: CompassStep.needs, childName: 'Ivy', service: svc, principal: guardian));
      expect(t.widget<FilterChip>(find.byKey(const Key('opt_knowNext'))).selected, isTrue);
      expect(t.widget<FilterChip>(find.byKey(const Key('opt_pictures'))).selected, isTrue);
      expect(t.widget<FilterChip>(find.byKey(const Key('opt_quiet'))).selected, isFalse);
      expect(find.textContaining(RegExp('diagnos|disorder|condition', caseSensitive: false)), findsNothing);
      expect(find.textContaining('Anything here that helps Ivy\'s day go well?'), findsOneWidget);
    });

    testWidgets('"Not sure" is a complete answer: it clears this step\'s ticks, keeps the other step, and saves', (WidgetTester t) async {
      await big(t);
      final CompassService svc = _Rig().service();
      await svc.saveAnswers(guardian, const CompassAnswers(who: <String>{'twoHomes'}, needs: <String>{'quiet'}));
      await show(t, CompassQuestionScreen(step: CompassStep.who, childName: 'Ivy', service: svc, principal: guardian));
      await tapKey(t, 'opt_siblings');
      await tapKey(t, 'compassNotSure');
      final CompassAnswers a = (await svc.load(guardian)).answers;
      expect(a.who, isEmpty);
      expect(a.needs, <String>{'quiet'});
    });

    testWidgets('"Skip for now" saves nothing', (WidgetTester t) async {
      await big(t);
      final CompassService svc = _Rig().service();
      await show(t, CompassQuestionScreen(step: CompassStep.who, childName: 'Ivy', service: svc, principal: guardian));
      await tapKey(t, 'opt_twoHomes');
      await tapKey(t, 'compassSkip');
      expect((await svc.load(guardian)).answers.isEmpty, isTrue);
    });

    testWidgets('the family builder\'s facts show as a quiet hint and are NOT ticked for her', (WidgetTester t) async {
      await big(t);
      await show(t, CompassQuestionScreen(
          step: CompassStep.who, childName: 'Ivy', service: _Rig().service(), principal: guardian,
          hints: () async => <String>['twoHomes']));
      expect(find.byKey(const Key('builderHint')), findsOneWidget);
      expect(find.textContaining('She sleeps in more than one home'), findsWidgets);
      expect(t.widget<FilterChip>(find.byKey(const Key('opt_twoHomes'))).selected, isFalse, reason: 'the guardian always chooses');
    });

    testWidgets('a builder that cannot be read just shows no hint', (WidgetTester t) async {
      await big(t);
      await show(t, CompassQuestionScreen(
          step: CompassStep.who, childName: 'Ivy', service: _Rig().service(), principal: guardian,
          hints: () async => throw StateError('no builder')));
      expect(find.byKey(const Key('builderHint')), findsNothing);
      expect(find.byKey(const Key('opt_twoHomes')), findsOneWidget);
    });

    testWidgets('a child principal sees a refusal and no questions; nothing is stored', (WidgetTester t) async {
      await big(t);
      final _Rig rig = _Rig();
      await show(t, CompassQuestionScreen(step: CompassStep.who, childName: 'Ivy', service: rig.service(), principal: ivy));
      expect(find.text('Only a grown-up can change this.'), findsOneWidget);
      expect(find.byKey(const Key('opt_twoHomes')), findsNothing);
      expect((await rig.service().load(guardian)).answers.isEmpty, isTrue);
    });
  });

  group('the suggestions', () {
    Future<_Rig> rigWith(CompassAnswers a) async {
      final _Rig rig = _Rig();
      await rig.service().saveAnswers(guardian, a);
      return rig;
    }

    testWidgets('each card says what it is, why, and which answers led to it; nothing is changed by looking', (WidgetTester t) async {
      await big(t);
      final _Rig rig = await rigWith(const CompassAnswers(who: <String>{'twoHomes', 'deviceTravels'}));
      await rig.rhythm.setRhythmSuite(guardian, false);
      await show(t, CompassSuggestScreen(childName: 'Ivy', service: rig.service(), principal: guardian));
      expect(find.byKey(const Key('sug_suite_rhythm')), findsOneWidget);
      expect(find.byKey(const Key('sug_profile_awayFromHome')), findsOneWidget);
      expect(find.text('Rhythm'), findsOneWidget);
      expect(find.text('Device used in another home'), findsOneWidget);
      expect(find.text(compassRules.first.reason), findsOneWidget);
      expect(find.textContaining('You chose: She sleeps in more than one home; This device goes with her to another home'), findsOneWidget);
      expect(t.widget<Switch>(find.byKey(const Key('sugSwitch_rhythm'))).value, isFalse, reason: 'it shows the suite\'s own state');
      expect((await rig.rhythm.loadRhythm(guardian)).suiteOn, isFalse, reason: 'nothing turned on by looking');
      expect((await rig.service().load(guardian)).profiles, isEmpty);
    });

    testWidgets('the switch is the guardian\'s yes: it flips the suite\'s own switch, and off flips it back', (WidgetTester t) async {
      await big(t);
      final _Rig rig = await rigWith(const CompassAnswers(who: <String>{'twoHomes'}));
      await rig.rhythm.setRhythmSuite(guardian, false);
      await show(t, CompassSuggestScreen(childName: 'Ivy', service: rig.service(), principal: guardian));
      await tapKey(t, 'sugSwitch_rhythm');
      expect((await rig.rhythm.loadRhythm(guardian)).suiteOn, isTrue);
      await tapKey(t, 'sugSwitch_rhythm');
      expect((await rig.rhythm.loadRhythm(guardian)).suiteOn, isFalse);
    });

    testWidgets('a profile suggestion\'s switch applies its defaults; and says nothing about her', (WidgetTester t) async {
      await big(t);
      final _Rig rig = await rigWith(const CompassAnswers(needs: <String>{'seeAlerts'}));
      await show(t, CompassSuggestScreen(childName: 'Ivy', service: rig.service(), principal: guardian));
      await tapKey(t, 'sugSwitch_deafHoh');
      expect((await rig.access.load()).visualAlerts, isTrue);
      expect(find.textContaining(RegExp('diagnos|disorder|she is ', caseSensitive: false)), findsNothing);
    });

    testWidgets('at most five cards, from the table\'s order', (WidgetTester t) async {
      await big(t);
      final _Rig rig = await rigWith(CompassAnswers(
          who: <String>{for (final CompassOption o in compassWhoOptions) o.id},
          needs: <String>{for (final CompassOption o in compassNeedsOptions) o.id}));
      await show(t, CompassSuggestScreen(childName: 'Ivy', service: rig.service(), principal: guardian));
      expect(find.byType(Card), findsNWidgets(5));
    });

    testWidgets('"Not now" remembers nothing and changes nothing', (WidgetTester t) async {
      await big(t);
      final _Rig rig = await rigWith(const CompassAnswers(who: <String>{'twoHomes'}));
      await rig.rhythm.setRhythmSuite(guardian, false);
      await t.pumpWidget(app(Builder(builder: (BuildContext c) => TextButton(
          key: const Key('go'), onPressed: () => Navigator.of(c).push(MaterialPageRoute<void>(
              builder: (_) => CompassSuggestScreen(childName: 'Ivy', service: rig.service(), principal: guardian))),
          child: const Text('go')))));
      await t.tap(find.byKey(const Key('go')));
      await t.pumpAndSettle();
      await tapKey(t, 'sugNotNow');
      expect(find.byKey(const Key('go')), findsOneWidget);
      expect((await rig.rhythm.loadRhythm(guardian)).suiteOn, isFalse);
      expect((await rig.service().load(guardian)).toJson().keys.toSet(), <String>{'who', 'needs', 'profiles'}, reason: 'no "dismissed" record exists');
    });

    testWidgets('no answers: a gentle sentence and a pointer to the shelf, not an empty screen', (WidgetTester t) async {
      await big(t);
      await show(t, CompassSuggestScreen(childName: 'Ivy', service: _Rig().service(), principal: guardian));
      expect(find.textContaining('Nothing to suggest'), findsOneWidget);
    });

    testWidgets('it never says "recommended for you" or claims to know: it says it is a short, plain list', (WidgetTester t) async {
      await big(t);
      final _Rig rig = await rigWith(const CompassAnswers(who: <String>{'twoHomes'}));
      await show(t, CompassSuggestScreen(childName: 'Ivy', service: rig.service(), principal: guardian));
      expect(find.textContaining('short, plain list'), findsOneWidget);
      expect(find.textContaining(RegExp(r'recommended for you|best for|we think|algorithm|AI', caseSensitive: false)), findsNothing);
    });

    testWidgets('a child principal sees a refusal and no suggestions', (WidgetTester t) async {
      await big(t);
      final _Rig rig = await rigWith(const CompassAnswers(who: <String>{'twoHomes'}));
      await show(t, CompassSuggestScreen(childName: 'Ivy', service: rig.service(), principal: ivy));
      expect(find.text('Only a grown-up can change this.'), findsOneWidget);
      expect(find.byKey(const Key('sug_suite_rhythm')), findsNothing);
    });
  });

  group('the suites shelf', () {
    testWidgets('one row per suite with a switch and what it adds; never a number or a use word', (WidgetTester t) async {
      await big(t);
      await show(t, SuitesShelfScreen(childName: 'Ivy', service: _Rig().service(), principal: guardian));
      for (final ShelfSuite s in shelfSuites) {
        expect(find.byKey(Key('shelfRow_${s.key}')), findsOneWidget, reason: s.key);
        expect(find.text(s.adds), findsOneWidget, reason: s.key);
        expect(t.widget<SwitchListTile>(find.byKey(Key('shelfSwitch_${s.key}'))).value, isTrue);
      }
      expect(find.textContaining(RegExp(r'\d')), findsNothing);
      expect(find.textContaining(RegExp(r'streak|score|last used|times used|have not used', caseSensitive: false)), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('each switch is the suite\'s own, and a change shows straight away', (WidgetTester t) async {
      await big(t);
      final _Rig rig = _Rig();
      await show(t, SuitesShelfScreen(childName: 'Ivy', service: rig.service(), principal: guardian));
      await tapKey(t, 'shelfSwitch_voice');
      expect((await rig.rhythm.loadVoice(guardian)).suiteOn, isFalse);
      expect(t.widget<SwitchListTile>(find.byKey(const Key('shelfSwitch_voice'))).value, isFalse);
      await tapKey(t, 'shelfSwitch_village');
      expect((await rig.village.loadForGuardian(guardian)).suiteOn, isFalse);
      await tapKey(t, 'shelfSwitch_care');
      expect((await rig.growing.switches.load()).on('careBinder'), isFalse);
      await tapKey(t, 'shelfSwitch_care');
      expect((await rig.growing.switches.load()).on('careBinder'), isTrue);
    });

    testWidgets('a shelf wired for the wrong principal says so rather than guessing "on"', (WidgetTester t) async {
      await big(t);
      final _Rig rig = _Rig();
      // ports built for a child principal: the suites refuse the read
      await show(t, SuitesShelfScreen(childName: 'Ivy', service: rig.service(principal: ivy), principal: guardian));
      expect(find.text('Only a grown-up can change this.'), findsOneWidget);
      expect(find.byKey(const Key('shelfRow_rhythm')), findsNothing);
      expect((await rig.rhythm.loadRhythm(guardian)).suiteOn, isTrue);
    });

    testWidgets('a child principal sees a refusal and no rows', (WidgetTester t) async {
      await big(t);
      await show(t, SuitesShelfScreen(childName: 'Ivy', service: _Rig().service(), principal: ivy));
      expect(find.text('Only a grown-up can change this.'), findsOneWidget);
      expect(find.byKey(const Key('shelfRow_rhythm')), findsNothing);
    });
  });

  group('the profiles', () {
    testWidgets('two cards, each listing exactly what it changes, with the plain promise', (WidgetTester t) async {
      await big(t);
      await show(t, ProfilesScreen(childName: 'Ivy', service: _Rig().service(), principal: guardian));
      expect(find.textContaining('only changes how this device looks and behaves'), findsOneWidget);
      expect(find.textContaining('never labels her'), findsOneWidget);
      for (final ProfileDefaults p in allProfiles) {
        expect(find.byKey(Key('profile_${p.id}')), findsOneWidget);
        for (final String c in p.changes) {
          expect(find.text('• $c'), findsOneWidget, reason: c);
        }
      }
    });

    testWidgets('switching on writes the existing accessibility settings; the off note says the settings stay', (WidgetTester t) async {
      await big(t);
      final _Rig rig = _Rig();
      await show(t, ProfilesScreen(childName: 'Ivy', service: rig.service(), principal: guardian));
      expect(find.byKey(const Key('profileOffNote_awayFromHome')), findsNothing);
      await tapKey(t, 'profileSwitch_awayFromHome');
      final AccessSettings a = await rig.access.load();
      expect(a.readAloud, isTrue);
      expect(a.reduceMotion, isTrue);
      expect(find.byKey(const Key('profileOffNote_awayFromHome')), findsOneWidget);
      expect(find.textContaining('leaves the settings as they are now'), findsOneWidget);
      await tapKey(t, 'profileSwitch_awayFromHome');
      expect(await rig.access.load(), a, reason: 'off leaves the settings alone');
      expect(find.byKey(const Key('profileOffNote_awayFromHome')), findsNothing);
    });

    testWidgets('the alerts profile shows what an alert looks like: words and a picture, steady, never flashing', (WidgetTester t) async {
      await big(t);
      await show(t, ProfilesScreen(childName: 'Ivy', service: _Rig().service(), principal: guardian));
      expect(find.byKey(const Key('alertPreview')), findsOneWidget);
      expect(find.textContaining('Never flashes'), findsOneWidget);
      expect(find.textContaining('Stays until she taps it'), findsOneWidget);
    });

    testWidgets('the captions wish is honest on the screen: live captions are not built', (WidgetTester t) async {
      await big(t);
      await show(t, ProfilesScreen(childName: 'Ivy', service: _Rig().service(), principal: guardian));
      expect(find.textContaining('live captions are not built yet'), findsOneWidget);
    });

    testWidgets('a child principal sees a refusal and no profile cards', (WidgetTester t) async {
      await big(t);
      await show(t, ProfilesScreen(childName: 'Ivy', service: _Rig().service(), principal: ivy));
      expect(find.text('Only a grown-up can change this.'), findsOneWidget);
      expect(find.byKey(const Key('profile_deafHoh')), findsNothing);
    });

    testWidgets('at 2x text on a 344dp screen nothing overflows', (WidgetTester t) async {
      await phone(t, w: 344, h: 3000);
      await t.pumpWidget(app(ProfilesScreen(childName: 'Ivy', service: _Rig().service(), principal: guardian), textScale: 2.0));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await t.pumpWidget(app(SuitesShelfScreen(childName: 'Ivy', service: _Rig().service(), principal: guardian), textScale: 2.0));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  });
}
