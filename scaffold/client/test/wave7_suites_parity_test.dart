// OLIVE BRANCH — Wave 7 (local suites parity): the "Her suites" page (g-suites), the Voice feelings check-in switch,
// the Rhythm "things that may need a quiet warning" flags, and Compass's two free-text answers. No longer
// UNVERIFIED — verified by CI (this file).
//
// Every privacy rule the new pieces touch is a real assertion: a child principal cannot change any of it, the
// guardian never gains a way to read her weather, the free text never shapes a suggestion, and nothing a child
// can read carries a count, a label of her or a diagnosis.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/access_settings.dart';
import 'package:olive_client/compass_logic.dart';
import 'package:olive_client/compass_repositories.dart';
import 'package:olive_client/compass_screens.dart';
import 'package:olive_client/growing_care_store.dart';
import 'package:olive_client/her_suites_screen.dart';
import 'package:olive_client/rhythm_logic.dart';
import 'package:olive_client/rhythm_screens.dart';
import 'package:olive_client/rhythm_voice_gate.dart';
import 'package:olive_client/rhythm_voice_guardian_screens.dart';
import 'package:olive_client/rhythm_voice_repositories.dart';
import 'package:olive_client/voice_logic.dart';

import 'rv_support.dart';
import 'village_support.dart' show freshVillage;

Future<void> big(WidgetTester t) => phone(t, w: 700, h: 3600);

Future<void> show(WidgetTester t, Widget w, {double scale = 1.0}) async {
  await t.pumpWidget(app(const SizedBox()));
  await t.pumpWidget(app(w, textScale: scale));
  await t.pumpAndSettle();
}

CompassService _compass(RhythmVoiceService rv, {bool asChild = false}) => CompassService(
    childId: 'ivy', repo: MemoryCompassRepository(), access: MemoryAccessRepository(),
    ports: suitePortsFor(
        rhythmVoice: rv, village: freshVillage(), growingCare: GrowingCareStores.memory(), principal: asChild ? ivy : guardian));

void main() {
  group('Her suites (g-suites)', () {
    test('lists the prototype\'s six suites in its order, Compass last and without a shelf switch', () {
      expect(herSuites.map((HerSuite s) => s.key).toList(), <String>['rhythm', 'voice', 'growing', 'care', 'village', 'compass']);
      expect(herSuites.where((HerSuite s) => !s.hasSwitch).map((HerSuite s) => s.key).toList(), <String>['compass']);
    });

    testWidgets('each row shows On her shelf or Off, and a switch is the suite\'s own switch', (WidgetTester t) async {
      await big(t);
      final RhythmVoiceService rv = freshService();
      final CompassService c = _compass(rv);
      await show(t, HerSuitesScreen(childName: 'Ivy', service: c, principal: guardian, open: (_) {}));
      expect(find.textContaining('Kept on this device'), findsWidgets);
      expect(find.textContaining('nothing here is sent'), findsOneWidget);
      // Voice is off until a guardian switches it on; Rhythm starts on.
      expect(find.descendant(of: find.byKey(const Key('suiteChip_voice')), matching: find.text('Off')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('suiteChip_rhythm')), matching: find.text('On her shelf')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('suiteChip_compass')), matching: find.text('For you')), findsOneWidget);
      expect(find.byKey(const Key('suiteSwitch_compass')), findsNothing);

      await t.ensureVisible(find.byKey(const Key('suiteSwitch_voice')));
      await t.tap(find.byKey(const Key('suiteSwitch_voice')));
      await t.pumpAndSettle();
      expect((await rv.loadVoice(guardian)).suiteOn, isTrue, reason: 'the suite\'s own switch changed');
      expect(find.descendant(of: find.byKey(const Key('suiteChip_voice')), matching: find.text('On her shelf')), findsOneWidget);
    });

    testWidgets('a row opens its own page', (WidgetTester t) async {
      await big(t);
      final List<String> opened = <String>[];
      await show(t, HerSuitesScreen(childName: 'Ivy', service: _compass(freshService()), principal: guardian, open: opened.add));
      for (final HerSuite s in herSuites) {
        await t.ensureVisible(find.byKey(Key('suiteOpen_${s.key}')));
        await t.tap(find.byKey(Key('suiteOpen_${s.key}')));
        await t.pump();
      }
      expect(opened, herSuites.map((HerSuite s) => s.key).toList());
    });

    testWidgets('a child principal is refused and sees only the quiet note', (WidgetTester t) async {
      await big(t);
      await show(t, HerSuitesScreen(
          childName: 'Ivy', service: _compass(freshService(), asChild: true), principal: ivy, open: (_) {}));
      expect(find.text('Only a grown-up can change this.'), findsOneWidget);
      expect(find.byType(Switch), findsNothing);
    });

    testWidgets('the summary counts suites that are on, never use', (WidgetTester t) async {
      await big(t);
      final RhythmVoiceService rv = freshService();
      final CompassService c = _compass(rv);
      Future<void> check() async {
        final int on = (await c.shelf(guardian)).where((ShelfRow r) => r.on).length;
        await show(t, HerSuitesScreen(childName: 'Ivy', service: c, principal: guardian, open: (_) {}));
        expect(find.text(on == 0 ? 'None on her shelf yet' : '$on of 5 on her shelf'), findsOneWidget);
      }

      await check();
      await rv.setVoiceSuite(guardian, true);
      await check();
      await rv.setRhythmSuite(guardian, false);
      await check();
    });

    for (final double w in <double>[344, 390, 600, 800]) {
      testWidgets('posture at ${w.toInt()} dp and 2.0x text: no overflow', (WidgetTester t) async {
        await phone(t, w: w, h: 4200);
        await show(t, HerSuitesScreen(childName: 'Ivy', service: _compass(freshService()), principal: guardian, open: (_) {}),
            scale: 2.0);
        expect(t.takeException(), isNull);
        expect(find.byKey(const Key('suiteRow_compass')), findsOneWidget);
      });
    }
  });

  group('Voice feelings check-in', () {
    test('defaults on, only an explicit false turns it off, and it round-trips', () {
      expect(const VoiceDoc().feelingsOn, isTrue);
      expect(VoiceDoc.fromJson(<String, Object?>{'suiteOn': true}).feelingsOn, isTrue);
      expect(VoiceDoc.fromJson(<String, Object?>{'feelingsOn': 'no'}).feelingsOn, isTrue);
      expect(VoiceDoc.fromJson(jsonDecode(jsonEncode(const VoiceDoc(feelingsOn: false).toJson()))).feelingsOn, isFalse);
    });

    test('off removes only "The sky in me"; the worry box, helpers and symbols stay; Voice off removes all', () {
      final RhythmVoiceTiles on = tilesFor(yearsOld: 8, voiceOn: true);
      final RhythmVoiceTiles off = tilesFor(yearsOld: 8, voiceOn: true, feelingsOn: false);
      expect(on.weather, isTrue);
      expect(off.weather, isFalse);
      expect(off.worryBox && off.symbols, isTrue);
      expect(tilesFor(yearsOld: 8, voiceOn: false).anyVoice, isFalse);
    });

    test('only a guardian can switch it; a child principal is refused', () async {
      final RhythmVoiceService s = freshService();
      expect((await s.setFeelingsCheckIn(ivy, false)).ok, isFalse);
      expect((await s.loadVoice(guardian)).feelingsOn, isTrue);
      expect((await s.setFeelingsCheckIn(guardian, false)).ok, isTrue);
      expect((await s.loadVoice(guardian)).feelingsOn, isFalse);
    });

    testWidgets('the Voice hub shows the switch and says her answers are hers', (WidgetTester t) async {
      await big(t);
      final RhythmVoiceService s = freshService();
      await show(t, VoiceGuardianHubScreen(childName: 'Ivy', service: s, principal: guardian, yearsOld: 8));
      expect(find.textContaining('You will never see them'), findsOneWidget);
      await t.ensureVisible(find.byKey(const Key('voiceFeelings')));
      await t.tap(find.byKey(const Key('voiceFeelings')));
      await t.pumpAndSettle();
      expect((await s.loadVoice(guardian)).feelingsOn, isFalse);
    });
  });

  group('Rhythm: things worth a quiet warning', () {
    test('the five flags match the prototype and survive a round trip; unknown ids and damage are dropped', () {
      expect(headsUps.map((HeadsUp h) => h.id).toList(), <String>['loud', 'bright', 'scratchy', 'crowds', 'surprises']);
      final SensoryProfile p = const SensoryProfile().withHeadsUp('loud', true).withHeadsUp('crowds', true).withHeadsUp('nope', true);
      expect(p.headsUp, <String>{'loud', 'crowds'});
      expect(SensoryProfile.fromJson(jsonDecode(jsonEncode(p.toJson()))).headsUp, <String>{'loud', 'crowds'});
      expect(SensoryProfile.fromJson(<String, Object?>{'headsUp': 'loud'}).headsUp, isEmpty);
      expect(SensoryProfile.fromJson(<String, Object?>{'headsUp': <Object?>[3, 'bright', 'x']}).headsUp, <String>{'bright'});
      expect(SensoryProfile.fromJson(<String, Object?>{'sound': 'low'}).headsUp, isEmpty, reason: 'an older document has none');
    });

    test('what she reads is soft: no digits, no label of her, no diagnosis words', () {
      for (final HeadsUp h in headsUps) {
        expect(h.line, isNot(matches(RegExp(r'\d'))));
        expect(h.line.toLowerCase(), isNot(contains('you have')));
        expect(h.line.toLowerCase(), isNot(matches(RegExp(r'autis|sensitiv|disorder|need'))));
      }
      expect(headsUpLines(const SensoryProfile()), isEmpty);
      expect(headsUpLines(const SensoryProfile().withHeadsUp('bright', true)), <String>[headsUps[1].line]);
    });

    testWidgets('the editor saves a flag as a guardian, and the new-place walk shows the line to her', (WidgetTester t) async {
      await big(t);
      final RhythmVoiceService s = freshService();
      await show(t, SensoryEditorScreen(childName: 'Ivy', service: s, principal: guardian));
      expect(find.byKey(const Key('headsUpNote')), findsOneWidget);
      await t.ensureVisible(find.byKey(const Key('headsUp_loud')));
      await t.tap(find.byKey(const Key('headsUp_loud')));
      await t.pumpAndSettle();
      expect((await s.loadRhythm(guardian)).sensory.headsUp, <String>{'loud'});

      await s.savePlace(guardian, makePlan('Dad\'s new place', <PlaceStop>[newStop('s1', 'door', 'This is the door')], <String>[]));
      await phone(t);
      await show(t, NewPlaceScreen(service: s));
      expect(find.byKey(const Key('placeHeadsUp')), findsOneWidget);
      expect(find.text(headsUps.first.line), findsOneWidget);
    });

    testWidgets('with no flag on, nothing extra appears on the walk', (WidgetTester t) async {
      await phone(t);
      final RhythmVoiceService s = freshService();
      await s.savePlace(guardian, makePlan('Dad\'s new place', <PlaceStop>[newStop('s1', 'door', 'This is the door')], <String>[]));
      await show(t, NewPlaceScreen(service: s));
      expect(find.byKey(const Key('placeHeadsUp')), findsNothing);
    });

    test('a child principal cannot change the profile', () async {
      final RhythmVoiceService s = freshService();
      expect((await s.saveSensory(ivy, const SensoryProfile().withHeadsUp('loud', true))).ok, isFalse);
      expect((await s.loadRhythm(guardian)).sensory.headsUp, isEmpty);
    });
  });

  group('Compass: two free-text answers', () {
    test('cleaned, capped, round-tripped, and never read by the suggestions', () {
      expect(cleanCompassWords('  two   spaces\nand a\u0001 break  '), 'two spaces and a break');
      expect(cleanCompassWords('x' * 400).length, maxCompassWords);
      const CompassAnswers a = CompassAnswers(who: <String>{'siblings'}, whoWords: 'Nana lives next door', needsWords: 'a night-light');
      final CompassAnswers back = CompassAnswers.fromJson(jsonDecode(jsonEncode(a.toJson())));
      expect(back, a);
      expect(back.whoWords, 'Nana lives next door');
      expect(suggest(a).map((Suggestion s) => s.key).toList(),
          suggest(const CompassAnswers(who: <String>{'siblings'})).map((Suggestion s) => s.key).toList());
      expect(CompassAnswers.fromJson(<String, Object?>{'whoWords': 7, 'needsWords': null}).isEmpty, isTrue);
      expect(const CompassAnswers(whoWords: 'only words').isEmpty, isFalse);
    });

    testWidgets('typing an answer saves it on this device and it comes back next time', (WidgetTester t) async {
      await big(t);
      final RhythmVoiceService rv = freshService();
      final CompassService c = _compass(rv);
      await show(t, CompassQuestionScreen(step: CompassStep.who, childName: 'Ivy', service: c, principal: guardian));
      expect(find.textContaining('Only you see this'), findsOneWidget);
      await t.enterText(find.byKey(const Key('compassWords')), 'Nana lives next door');
      await t.ensureVisible(find.byKey(const Key('compassSave')));
      await t.tap(find.byKey(const Key('compassSave')));
      await t.pumpAndSettle();
      expect((await c.load(guardian)).answers.whoWords, 'Nana lives next door');

      await show(t, CompassQuestionScreen(step: CompassStep.who, childName: 'Ivy', service: c, principal: guardian));
      expect(find.text('Nana lives next door'), findsOneWidget);
      // The second question keeps its own words.
      await show(t, CompassQuestionScreen(step: CompassStep.needs, childName: 'Ivy', service: c, principal: guardian));
      expect(find.text('Nana lives next door'), findsNothing);
    });

    testWidgets('"Not sure" clears this step\'s words and leaves the other step alone', (WidgetTester t) async {
      await big(t);
      final CompassService c = _compass(freshService());
      await c.saveAnswers(guardian, const CompassAnswers(whoWords: 'a', needsWords: 'b'));
      await show(t, CompassQuestionScreen(step: CompassStep.who, childName: 'Ivy', service: c, principal: guardian));
      await t.ensureVisible(find.byKey(const Key('compassNotSure')));
      await t.tap(find.byKey(const Key('compassNotSure')));
      await t.pumpAndSettle();
      final CompassAnswers a = (await c.load(guardian)).answers;
      expect(a.whoWords, '');
      expect(a.needsWords, 'b');
    });

    test('a child principal can neither read nor write them', () async {
      final CompassService c = _compass(freshService(), asChild: true);
      expect((await c.saveAnswers(ivy, const CompassAnswers(whoWords: 'x'))).ok, isFalse);
      expect(() => c.load(ivy), throwsA(isA<CompassRefused>()));
    });
  });
}
