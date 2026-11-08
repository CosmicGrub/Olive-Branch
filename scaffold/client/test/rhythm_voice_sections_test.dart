// OLIVE BRANCH — the Rhythm and Voice tiles in the child's More hub: they follow
// the family-structure model (age band, More hub, two homes), the guardian's
// switches and what has been authored, use the shared TieredTile, and the child
// shell still reaches nothing guardian-side.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/child_home.dart';
import 'package:olive_client/child_more.dart';
import 'package:olive_client/family_structure_logic.dart';
import 'package:olive_client/family_structure_store.dart';
import 'package:olive_client/rhythm_logic.dart';
import 'package:olive_client/rhythm_screens.dart';
import 'package:olive_client/rhythm_voice_repositories.dart';
import 'package:olive_client/tiered_tile.dart';
import 'package:olive_client/voice_logic.dart';
import 'package:olive_client/voice_screens.dart';

import 'rv_support.dart';

const FamilyStructure twoHomes = FamilyStructure(homes: <Home>[
  Home(id: 'h1', name: 'Mom', childSleeps: true),
  Home(id: 'h2', name: 'Dad', childSleeps: true),
]);
const FamilyStructure oneHome = FamilyStructure(homes: <Home>[Home(id: 'h1', name: 'Mom', childSleeps: true)]);

FamilyChildSnapshot snap(FamilyStructure s, String band) =>
    FamilyChildSnapshot(view: deriveChildView(s, band, null, null, today: '2026-11-08'));

Future<RhythmVoiceService> authored() async {
  final RhythmVoiceService s = freshService();
  await s.saveRoutine(guardian, bedtime());
  await s.saveBoard(guardian, makeBoard(boardCard('bath'), boardCard('book')));
  await s.savePacking(guardian, addPackItem(const PackingList(), newPackItem('o', 'owl')));
  await s.savePlace(guardian, makePlan('Dad\'s new place', <PlaceStop>[newStop('s', 'door', 'The door')], const <String>[]));
  await s.saveHelpers(guardian, <Helper>[makeHelper(id: 'h', name: 'Nana', picture: 'grandparent', saidYes: true)]);
  await s.setVoiceSuite(guardian, true); // Voice starts OFF until a guardian turns it on
  return s;
}

const List<String> rhythmKeys = <String>['rvTile_routine', 'rvTile_firstThen', 'rvTile_packing', 'rvTile_newPlace'];
const List<String> voiceKeys = <String>['rvTile_weather', 'rvTile_worry', 'rvTile_helpers', 'rvTile_symbols'];

Future<void> more(WidgetTester t, RhythmVoiceService s, {FamilyChildSnapshot? family, int age = 6, double scale = 1.0, double w = 700}) async {
  await phone(t, w: w, h: 3200);
  await t.pumpWidget(app(ChildMoreScreen(childName: 'Ivy', childAge: age, rhythmVoice: s, family: family), textScale: scale));
  await t.pumpAndSettle();
}

void expectOn(List<String> keys) {
  for (final String k in keys) {
    expect(find.byKey(Key(k)), findsOneWidget, reason: k);
  }
}

void expectOff(List<String> keys) {
  for (final String k in keys) {
    expect(find.byKey(Key(k)), findsNothing, reason: k);
  }
}

void main() {
  group('which tiles she gets', () {
    testWidgets('a six-year-old with two homes and everything authored gets all eight, as TieredTiles', (WidgetTester t) async {
      await more(t, await authored(), family: snap(twoHomes, 't57'));
      expectOn(<String>[...rhythmKeys, ...voiceKeys]);
      expect(find.text('MY DAY'), findsOneWidget);
      expect(find.text('MY VOICE'), findsOneWidget);
      expect(find.text('Bedtime'), findsOneWidget, reason: 'the routine tile carries the routine\'s own name');
      for (final String k in <String>[...rhythmKeys, ...voiceKeys]) {
        expect(find.byKey(Key(k)).evaluate().single.widget, isA<TieredTile>(), reason: k);
        expect(heightOf(t, find.byKey(Key(k))), greaterThanOrEqualTo(64), reason: k);
      }
    });

    testWidgets('with nothing authored only the picture tiles she owns appear: weather, worry, symbols', (WidgetTester t) async {
      final RhythmVoiceService s = freshService();
      await s.setVoiceSuite(guardian, true);
      await more(t, s, family: snap(twoHomes, 't57'));
      expectOn(<String>['rvTile_weather', 'rvTile_worry', 'rvTile_symbols']);
      expectOff(<String>[...rhythmKeys, 'rvTile_helpers']);
      expect(find.text('MY DAY'), findsNothing, reason: 'no empty section');
    });

    testWidgets('Voice starts OFF: with nothing set up and no switch turned on, no My voice section for any age', (WidgetTester t) async {
      final RhythmVoiceService s = freshService();
      for (final FamilyChildSnapshot? f in <FamilyChildSnapshot?>[snap(twoHomes, 't57'), snap(oneHome, 't812'), null]) {
        await more(t, s, family: f, age: 9);
        expectOff(voiceKeys);
        expect(find.text('MY VOICE'), findsNothing);
      }
    });

    testWidgets('Voice off stays off even with helpers written; turning it on shows the picture tiles', (WidgetTester t) async {
      final RhythmVoiceService s = freshService();
      await s.saveHelpers(guardian, <Helper>[makeHelper(id: 'h', name: 'Nana', picture: 'grandparent', saidYes: true)]);
      await more(t, s, family: snap(twoHomes, 't57'));
      expectOff(voiceKeys);
      await s.setVoiceSuite(guardian, true);
      await more(t, s, family: snap(twoHomes, 't57'));
      expectOn(voiceKeys);
    });

    testWidgets('with no family snapshot the guardian\'s local "two homes" setting brings the bag; off by default', (WidgetTester t) async {
      final RhythmVoiceService s = await authored();
      await more(t, s);
      expectOff(<String>['rvTile_packing']);
      await s.setTwoHomes(guardian, true);
      await more(t, s);
      expectOn(<String>['rvTile_packing']);
      await more(t, s, family: snap(oneHome, 't57'));
      expectOff(<String>['rvTile_packing']);
      await s.setTwoHomes(guardian, false);
      await more(t, s);
      expectOff(<String>['rvTile_packing']);
    });

    testWidgets('the youngest band gets nothing, whatever a guardian wrote', (WidgetTester t) async {
      await more(t, await authored(), family: snap(twoHomes, 't34'), age: 4);
      expectOff(<String>[...rhythmKeys, ...voiceKeys]);
      expect(find.text('MY DAY'), findsNothing);
      expect(find.text('MY VOICE'), findsNothing);
    });

    testWidgets('with no family model, age four gets nothing and an unknown age is treated as five', (WidgetTester t) async {
      await more(t, await authored(), age: 4);
      expectOff(<String>[...rhythmKeys, ...voiceKeys]);
      await more(t, await authored(), age: -1);
      expectOn(<String>['rvTile_weather', 'rvTile_routine']);
      expectOff(<String>['rvTile_packing']);
    });

    testWidgets('the packing buddy needs two sleeping homes in the model; one home leaves it off', (WidgetTester t) async {
      await more(t, await authored(), family: snap(oneHome, 't57'));
      expectOff(<String>['rvTile_packing']);
      expectOn(<String>['rvTile_routine']);
      await more(t, await authored(), family: snap(twoHomes, 't57'));
      expectOn(<String>['rvTile_packing']);
      await more(t, await authored());
      expectOff(<String>['rvTile_packing']);
    });

    testWidgets('the guardian\'s switches: rhythm off hides My day, voice off hides My voice', (WidgetTester t) async {
      final RhythmVoiceService s = await authored();
      await s.setRhythmSuite(guardian, false);
      await more(t, s, family: snap(twoHomes, 't57'));
      expectOff(rhythmKeys);
      expectOn(voiceKeys);
      expect(find.text('MY DAY'), findsNothing);
      await s.setRhythmSuite(guardian, true);
      await s.setVoiceSuite(guardian, false);
      await more(t, s, family: snap(twoHomes, 't57'));
      expectOn(rhythmKeys);
      expectOff(voiceKeys);
      expect(find.text('MY VOICE'), findsNothing);
    });

    testWidgets('a helper who has not said yes does not bring the tile', (WidgetTester t) async {
      final RhythmVoiceService s = freshService();
      await s.saveHelpers(guardian, <Helper>[makeHelper(id: 'h', name: 'Nana', picture: 'grandparent')]);
      await more(t, s, family: snap(twoHomes, 't57'));
      expectOff(<String>['rvTile_helpers']);
    });

    testWidgets('an older child keeps them; the existing hub is untouched', (WidgetTester t) async {
      await more(t, await authored(), family: snap(twoHomes, 't812'), age: 9);
      expectOn(<String>[...rhythmKeys, ...voiceKeys]);
      expect(find.text('My journal'), findsOneWidget);
      expect(find.text('Letters to me'), findsOneWidget);
    });
  });

  group('the tiles open the real screens', () {
    testWidgets('each tile pushes its own screen and coming back keeps the hub', (WidgetTester t) async {
      final RhythmVoiceService s = await authored();
      final Map<String, Type> map = <String, Type>{
        'rvTile_routine': MyRoutineScreen, 'rvTile_firstThen': FirstThenScreen, 'rvTile_packing': PackingBuddyScreen,
        'rvTile_newPlace': NewPlaceScreen, 'rvTile_weather': FeelingsWeatherScreen, 'rvTile_worry': WorryBoxScreen,
        'rvTile_helpers': MyHelpersScreen, 'rvTile_symbols': SymbolBoardScreen,
      };
      await more(t, s, family: snap(twoHomes, 't57'));
      for (final MapEntry<String, Type> e in map.entries) {
        await t.ensureVisible(find.byKey(Key(e.key)));
        await t.tap(find.byKey(Key(e.key)));
        await t.pumpAndSettle();
        expect(find.byType(e.value), findsOneWidget, reason: e.key);
        await t.pageBack();
        await t.pumpAndSettle();
        expect(find.byType(ChildMoreScreen), findsOneWidget);
      }
    });

    testWidgets('the speaker given to the hub reaches the screens', (WidgetTester t) async {
      final List<String> said = <String>[];
      await phone(t, w: 700, h: 3200);
      final RhythmVoiceService on = freshService();
      await on.setVoiceSuite(guardian, true);
      await t.pumpWidget(app(ChildMoreScreen(
          childName: 'Ivy', childAge: 6, rhythmVoice: on, family: snap(twoHomes, 't57'),
          speak: (String x) async => said.add(x))));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const Key('rvTile_weather')));
      await t.tap(find.byKey(const Key('rvTile_weather')));
      await t.pumpAndSettle();
      await t.tap(find.byIcon(Icons.volume_up_outlined).first);
      expect(said, <String>['Sunny']);
    });

    testWidgets('from the child home: More for you carries the family model through to the tiles', (WidgetTester t) async {
      await phone(t, w: 700, h: 3200);
      RhythmVoiceService.resetShared();
      await RhythmVoiceService.forChild(null).setVoiceSuite(guardian, true);
      await t.pumpWidget(app(ChildHome(
          childName: 'Ivy', presence: null, sleepsUntilHandover: 3, unreadCount: 0, childAge: 6,
          family: snap(twoHomes, 't57'))));
      await t.pumpAndSettle();
      await t.tap(find.text('More for you'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('rvTile_weather')), findsOneWidget);
      expect(find.byKey(const Key('rvTile_packing')), findsNothing, reason: 'nothing authored yet');
      RhythmVoiceService.resetShared();
    });
  });

  group('every width', () {
    testWidgets('no overflow at the 344dp cover screen, with all eight tiles and 2.0x text', (WidgetTester t) async {
      await more(t, await authored(), family: snap(twoHomes, 't57'), scale: 2.0, w: 344);
      expect(t.takeException(), isNull);
      expectOn(<String>[...rhythmKeys, ...voiceKeys]);
      for (final String k in <String>[...rhythmKeys, ...voiceKeys]) {
        expect(heightOf(t, find.byKey(Key(k))), greaterThanOrEqualTo(64), reason: '$k keeps its 64dp target');
      }
    });

    testWidgets('two tiles to a row, and one per row once the text is large', (WidgetTester t) async {
      await more(t, await authored(), family: snap(twoHomes, 't57'), w: 700);
      expect(t.getTopLeft(find.byKey(const Key('rvTile_weather'))).dy, t.getTopLeft(find.byKey(const Key('rvTile_worry'))).dy);
      await more(t, await authored(), family: snap(twoHomes, 't57'), w: 344);
      expect(t.takeException(), isNull);
      expect(t.getTopLeft(find.byKey(const Key('rvTile_weather'))).dy, t.getTopLeft(find.byKey(const Key('rvTile_worry'))).dy,
          reason: 'two fit across the 344dp cover screen at normal text');
      await more(t, await authored(), family: snap(twoHomes, 't57'), w: 344, scale: 1.6);
      expect(t.getTopLeft(find.byKey(const Key('rvTile_weather'))).dx, t.getTopLeft(find.byKey(const Key('rvTile_worry'))).dx,
          reason: 'at large text they stack so a label has the width it needs');
    });
  });

  group('the child shell has no way into the guardian side (§8.1)', () {
    String stripped(String path) => File(path).readAsStringSync().replaceAll(RegExp(r'//.*'), '');

    test('no child-facing Rhythm or Voice file mentions settings, or imports a guardian editor', () {
      for (final String f in <String>[
        'lib/rhythm_screens.dart', 'lib/voice_screens.dart', 'lib/rhythm_voice_sections.dart', 'lib/picture_icons.dart',
        'lib/rhythm_voice_gate.dart', 'lib/child_more.dart',
      ]) {
        final String src = stripped(f);
        expect(RegExp('Settings|settings').hasMatch(src), isFalse, reason: '$f must not mention settings');
        expect(src.contains('rhythm_voice_guardian_screens'), isFalse, reason: '$f must not reach the guardian editors');
        expect(src.contains('guardian_more.dart'), isFalse, reason: f);
        expect(src.contains('guardian_settings_hub'), isFalse, reason: f);
      }
    });

    test('the child screens call no guardian write on the service', () {
      const List<String> guardianWrites = <String>[
        'saveRoutine', 'clearRoutine', 'saveBoard', 'clearBoard', 'savePacking', 'newBag', 'saveSensory', 'savePlace',
        'setRhythmSuite', 'setVoiceSuite', 'saveHelpers', 'savePersonalSymbols', 'worriesShownToGrownUp',
      ];
      for (final String f in <String>['lib/rhythm_screens.dart', 'lib/voice_screens.dart', 'lib/rhythm_voice_sections.dart']) {
        final String src = stripped(f);
        for (final String w in guardianWrites) {
          expect(src.contains('.$w('), isFalse, reason: '$f calls $w');
        }
      }
    });

    test('nothing in these suites talks to a network, a clock server or a location', () {
      for (final String f in <String>[
        'lib/picture_library.dart', 'lib/picture_icons.dart', 'lib/rhythm_logic.dart', 'lib/voice_logic.dart',
        'lib/rhythm_voice_gate.dart', 'lib/rhythm_voice_repositories.dart', 'lib/rhythm_screens.dart', 'lib/voice_screens.dart',
        'lib/rhythm_voice_sections.dart', 'lib/rhythm_voice_guardian_screens.dart',
      ]) {
        final String src = stripped(f);
        for (final String banned in <String>['package:http', 'dart:io', 'HttpClient', 'WebSocket', 'geolocator', 'Geolocator', 'latitude', 'longitude']) {
          expect(src.contains(banned), isFalse, reason: '$f uses $banned');
        }
      }
    });

    test('every new client file carries the UNVERIFIED header line', () {
      for (final String f in <String>[
        'lib/picture_library.dart', 'lib/picture_icons.dart', 'lib/rhythm_logic.dart', 'lib/voice_logic.dart',
        'lib/rhythm_voice_gate.dart', 'lib/rhythm_voice_repositories.dart', 'lib/rhythm_screens.dart', 'lib/voice_screens.dart',
        'lib/rhythm_voice_sections.dart', 'lib/rhythm_voice_guardian_screens.dart',
      ]) {
        final String head = File(f).readAsLinesSync().take(8).join('\n');
        expect(head.contains('UNVERIFIED'), isTrue, reason: f);
      }
    });
  });
}

