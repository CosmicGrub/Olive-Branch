// OLIVE BRANCH — the guardian's editors for suites B and C, the one window onto
// worries she chose to show, and the Settings hub entry points. Every deny path
// is a real assertion: the child principal cannot save, a guardian cannot read
// her weather or her private worries, and bad content is refused in words.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/guardian_more.dart';
import 'package:olive_client/picture_library.dart';
import 'package:olive_client/rhythm_logic.dart';
import 'package:olive_client/rhythm_voice_guardian_screens.dart';
import 'package:olive_client/rhythm_voice_repositories.dart';
import 'package:olive_client/voice_logic.dart';
import 'package:olive_client/voice_screens.dart' show WorryThumb;

import 'rv_support.dart';

Future<void> big(WidgetTester t) => phone(t, w: 700, h: 2400);

Future<void> show(WidgetTester t, Widget w) async {
  // A fresh tree each time, so no State or pushed route from an earlier pump lingers.
  await t.pumpWidget(app(const SizedBox()));
  await t.pumpWidget(app(w));
  await t.pumpAndSettle();
}

Future<void> pick(WidgetTester t, String id) async {
  await t.tap(find.byKey(Key('pick_$id')));
  await t.pumpAndSettle();
}

Future<void> typeAndOk(WidgetTester t, String text) async {
  await t.enterText(find.byKey(const Key('askText')), text);
  await t.tap(find.byKey(const Key('askTextOk')));
  await t.pumpAndSettle();
}

void main() {
  group('hubs and entry points', () {
    testWidgets('the Rhythm hub says plainly it is on this device only and not shared with her other home', (WidgetTester t) async {
      await big(t);
      await show(t, RhythmGuardianHubScreen(childName: 'Ivy', service: freshService(), principal: guardian, yearsOld: 6));
      await t.pumpAndSettle();
      expect(find.textContaining('Kept on this device only'), findsOneWidget);
      expect(find.textContaining('not shared with Ivy\'s other home yet'), findsOneWidget);
      for (final String k in <String>['rowRoutine', 'rowBoard', 'rowPacking', 'rowPlace', 'rowSensory']) {
        expect(find.byKey(Key(k)), findsOneWidget, reason: k);
      }
    });

    testWidgets('the Voice hub says so too, and says the weather and worry box cannot be opened by a grown-up', (WidgetTester t) async {
      await big(t);
      await show(t, VoiceGuardianHubScreen(childName: 'Ivy', service: freshService(), principal: guardian, yearsOld: 6));
      await t.pumpAndSettle();
      expect(find.textContaining('not shared with Ivy\'s other home yet'), findsOneWidget);
      expect(find.textContaining('You cannot open them'), findsOneWidget);
      for (final String k in <String>['rowHelpers', 'rowSymbols', 'rowShown']) {
        expect(find.byKey(Key(k)), findsOneWidget, reason: k);
      }
    });

    testWidgets('a child under five is told none of this shows on her device yet', (WidgetTester t) async {
      await big(t);
      await show(t, RhythmGuardianHubScreen(childName: 'Ivy', service: freshService(), principal: guardian, yearsOld: 4));
      await t.pumpAndSettle();
      expect(find.textContaining('under five'), findsOneWidget);
      await show(t, VoiceGuardianHubScreen(childName: 'Ivy', service: freshService(), principal: guardian, yearsOld: null));
      await t.pumpAndSettle();
      expect(find.textContaining('from age five'), findsOneWidget, reason: 'unknown age fails closed to five');
    });

    testWidgets('the suite switches save through the service, and a child principal cannot flip them', (WidgetTester t) async {
      await big(t);
      final RhythmVoiceService s = freshService();
      await show(t, RhythmGuardianHubScreen(childName: 'Ivy', service: s, principal: guardian));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('rhythmSuite')));
      await t.pumpAndSettle();
      expect((await s.loadRhythm(guardian)).suiteOn, isFalse);
      await t.tap(find.byKey(const Key('rhythmSuite')));
      await t.pumpAndSettle();
      expect((await s.loadRhythm(guardian)).suiteOn, isTrue);

      final RhythmVoiceService s2 = freshService();
      await show(t, VoiceGuardianHubScreen(childName: 'Ivy', service: s2, principal: ivy));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('voiceSuite')));
      await t.pumpAndSettle();
      expect(find.text('Only a grown-up can change this.'), findsOneWidget);
      expect((await s2.voice.load()).suiteOn, isTrue, reason: 'nothing changed');
    });

    testWidgets('both are reachable from the guardian Settings hub, under Family', (WidgetTester t) async {
      await big(t);
      await show(t, const GuardianMoreScreen(childName: 'Ivy', childAge: 6));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const Key('moreSettings')));
      await t.tap(find.byKey(const Key('moreSettings')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('settingsRow_rhythm')), findsOneWidget);
      expect(find.byKey(const Key('settingsRow_voice')), findsOneWidget);
      await t.tap(find.byKey(const Key('settingsRow_rhythm')));
      await t.pumpAndSettle();
      expect(find.byType(RhythmGuardianHubScreen), findsOneWidget);
      await t.pageBack();
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('settingsRow_voice')));
      await t.pumpAndSettle();
      expect(find.byType(VoiceGuardianHubScreen), findsOneWidget);
    });

    testWidgets('the hubs link through to every editor', (WidgetTester t) async {
      await big(t);
      final RhythmVoiceService s = freshService();
      final Map<String, Type> rhythm = <String, Type>{
        'rowRoutine': RoutineEditorScreen, 'rowBoard': FirstThenEditorScreen, 'rowPacking': PackingEditorScreen,
        'rowPlace': NewPlaceEditorScreen, 'rowSensory': SensoryEditorScreen,
      };
      for (final MapEntry<String, Type> e in rhythm.entries) {
        await show(t, RhythmGuardianHubScreen(childName: 'Ivy', service: s, principal: guardian));
        await t.pumpAndSettle();
        await t.tap(find.byKey(Key(e.key)));
        await t.pumpAndSettle();
        expect(find.byType(e.value), findsOneWidget, reason: e.key);
      }
      final Map<String, Type> voice = <String, Type>{
        'rowHelpers': HelpersEditorScreen, 'rowSymbols': SymbolsEditorScreen, 'rowShown': SharedWorriesScreen,
      };
      for (final MapEntry<String, Type> e in voice.entries) {
        await show(t, VoiceGuardianHubScreen(childName: 'Ivy', service: s, principal: guardian));
        await t.pumpAndSettle();
        await t.tap(find.byKey(Key(e.key)));
        await t.pumpAndSettle();
        expect(find.byType(e.value), findsOneWidget, reason: e.key);
      }
    });
  });

  group('the routine editor', () {
    testWidgets('a guardian adds, renames, orders and saves steps; the child then reads them', (WidgetTester t) async {
      await big(t);
      final RhythmVoiceService s = freshService();
      await show(t, RoutineEditorScreen(childName: 'Ivy', service: s, principal: guardian));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('routineTitle')), 'Bedtime');
      await t.tap(find.byKey(const Key('stepAdd')));
      await t.pumpAndSettle();
      await pick(t, 'bath');
      await t.tap(find.byKey(const Key('stepAdd')));
      await t.pumpAndSettle();
      await pick(t, 'book');
      await t.tap(find.byKey(const Key('stepAdd')));
      await t.pumpAndSettle();
      await pick(t, 'lights-out');
      // move "Lights out" up one: book <-> lights-out
      await t.tap(find.byTooltip('Move up').last);
      await t.pumpAndSettle();
      // rename the first step
      await t.tap(find.text('Bath'));
      await t.pumpAndSettle();
      await typeAndOk(t, 'Splash time');
      await t.tap(find.byKey(const Key('routineSave')));
      await t.pumpAndSettle();
      expect(find.text('Saved on this device.'), findsOneWidget);
      final Routine r = (await s.loadRhythm(ivy)).routine!;
      expect(r.title, 'Bedtime');
      expect(r.steps.map((RoutineStep x) => x.label), <String>['Splash time', 'Lights out', 'A book']);
    });

    testWidgets('only routine pictures are on offer; the ninth step is refused in words', (WidgetTester t) async {
      await big(t);
      await show(t, RoutineEditorScreen(childName: 'Ivy', service: freshService(), principal: guardian));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('stepAdd')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('pick_bath')), findsOneWidget);
      expect(find.byKey(const Key('pick_sunny')), findsNothing);
      expect(find.byKey(const Key('pick_owl')), findsNothing);
      await pick(t, 'bath');
      for (int i = 1; i < maxRoutineSteps; i++) {
        await t.tap(find.byKey(const Key('stepAdd')));
        await t.pumpAndSettle();
        await pick(t, 'bath');
      }
      await t.tap(find.byKey(const Key('stepAdd')));
      await t.pumpAndSettle();
      await pick(t, 'book');
      expect(find.text('That is the most there is room for.'), findsOneWidget);
    });

    testWidgets('an address in a step name is refused in words and nothing is saved', (WidgetTester t) async {
      await big(t);
      final RhythmVoiceService s = freshService();
      await show(t, RoutineEditorScreen(childName: 'Ivy', service: s, principal: guardian));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('stepAdd')));
      await t.pumpAndSettle();
      await pick(t, 'bath');
      await t.tap(find.text('Bath'));
      await t.pumpAndSettle();
      await typeAndOk(t, '12 Oak Street');
      expect(find.text('Please leave out addresses and places. Rooms only.'), findsOneWidget);
      expect(find.text('Bath'), findsOneWidget, reason: 'the old name stands');
      expect((await s.loadRhythm(guardian)).routine, isNull);
    });

    testWidgets('an empty title is refused in words', (WidgetTester t) async {
      await big(t);
      final RhythmVoiceService s = freshService();
      await show(t, RoutineEditorScreen(childName: 'Ivy', service: s, principal: guardian));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('routineTitle')), '   ');
      await t.tap(find.byKey(const Key('routineSave')));
      await t.pumpAndSettle();
      expect(find.text('Please use a short name.'), findsOneWidget);
      expect((await s.loadRhythm(guardian)).routine, isNull);
    });

    testWidgets('the child principal cannot save: the service refuses and says so', (WidgetTester t) async {
      await big(t);
      final RhythmVoiceService s = freshService();
      await show(t, RoutineEditorScreen(childName: 'Ivy', service: s, principal: ivy));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('stepAdd')));
      await t.pumpAndSettle();
      await pick(t, 'bath');
      await t.tap(find.byKey(const Key('routineSave')));
      await t.pumpAndSettle();
      expect(find.text('Only a grown-up can change this.'), findsOneWidget);
      expect((await s.rhythm.load()).routine, isNull);
    });

    testWidgets('removing a step and removing the routine both work', (WidgetTester t) async {
      await big(t);
      final RhythmVoiceService s = freshService();
      await s.saveRoutine(guardian, bedtime());
      await show(t, RoutineEditorScreen(childName: 'Ivy', service: s, principal: guardian));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('stepRemove_b')));
      await t.pumpAndSettle();
      expect(find.text('Pyjamas'), findsNothing);
      await t.tap(find.byKey(const Key('routineSave')));
      await t.pumpAndSettle();
      expect((await s.loadRhythm(ivy)).routine!.steps.length, 2);
      await t.tap(find.byKey(const Key('routineClear')));
      await t.pumpAndSettle();
      expect((await s.loadRhythm(ivy)).routine, isNull);
    });
  });

  group('the first-then editor', () {
    testWidgets('two cards from the picture library, saved for her', (WidgetTester t) async {
      await big(t);
      final RhythmVoiceService s = freshService();
      await show(t, FirstThenEditorScreen(childName: 'Ivy', service: s, principal: guardian));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('boardSave')));
      await t.pumpAndSettle();
      expect(find.text('Choose both cards first.'), findsOneWidget);
      await t.tap(find.byKey(const Key('boardPickFirst')));
      await t.pumpAndSettle();
      await pick(t, 'bath');
      await t.tap(find.byKey(const Key('boardPickThen')));
      await t.pumpAndSettle();
      await pick(t, 'play');
      await t.tap(find.byKey(const Key('boardSave')));
      await t.pumpAndSettle();
      final FirstThenBoard b = (await s.loadRhythm(ivy)).board!;
      expect(<String>[b.first.picture, b.then.picture], <String>['bath', 'play']);
    });

    testWidgets('the same card twice is refused; clearing removes it', (WidgetTester t) async {
      await big(t);
      final RhythmVoiceService s = freshService();
      await show(t, FirstThenEditorScreen(childName: 'Ivy', service: s, principal: guardian));
      await t.pumpAndSettle();
      for (final String k in <String>['boardPickFirst', 'boardPickThen']) {
        await t.tap(find.byKey(Key(k)));
        await t.pumpAndSettle();
        await pick(t, 'bath');
      }
      await t.tap(find.byKey(const Key('boardSave')));
      await t.pumpAndSettle();
      expect(find.text('That one is already there.'), findsOneWidget);
      expect((await s.loadRhythm(guardian)).board, isNull);

      await s.saveBoard(guardian, makeBoard(boardCard('bath'), boardCard('play')));
      await show(t, FirstThenEditorScreen(childName: 'Ivy', service: s, principal: guardian));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('boardClear')));
      await t.pumpAndSettle();
      expect((await s.loadRhythm(guardian)).board, isNull);
    });

    testWidgets('the child principal cannot save a board', (WidgetTester t) async {
      await big(t);
      final RhythmVoiceService s = freshService();
      await show(t, FirstThenEditorScreen(childName: 'Ivy', service: s, principal: ivy));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('boardPickFirst')));
      await t.pumpAndSettle();
      await pick(t, 'bath');
      await t.tap(find.byKey(const Key('boardPickThen')));
      await t.pumpAndSettle();
      await pick(t, 'play');
      await t.tap(find.byKey(const Key('boardSave')));
      await t.pumpAndSettle();
      expect(find.text('Only a grown-up can change this.'), findsOneWidget);
      expect((await s.rhythm.load()).board, isNull);
    });
  });

  group('the packing editor', () {
    testWidgets('things to bring and things that are the same in both homes; saved; a new bag clears her ticks', (WidgetTester t) async {
      await big(t);
      final RhythmVoiceService s = freshService();
      await show(t, PackingEditorScreen(childName: 'Ivy', service: s, principal: guardian));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('itemAddBring')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('pick_owl')), findsOneWidget);
      expect(find.byKey(const Key('pick_bath')), findsNothing, reason: 'only bag things');
      await pick(t, 'owl');
      await t.tap(find.byKey(const Key('itemAddSame')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('pick_owl')), findsNothing, reason: 'a thing already on the list is not offered twice');
      await pick(t, 'night-light');
      expect(find.text('To bring'), findsOneWidget);
      expect(find.text('Same in both homes'), findsOneWidget);
      await t.tap(find.byKey(const Key('packingSave')));
      await t.pumpAndSettle();
      final PackingList l = (await s.loadRhythm(ivy)).packing;
      expect(l.toBring.single.picture, 'owl');
      expect(l.alwaysSame.single.picture, 'night-light');

      await s.togglePack(ivy, l.toBring.single.id);
      expect((await s.packedToday(ivy)).packed.length, 1);
      await t.tap(find.byKey(const Key('packingNewBag')));
      await t.pumpAndSettle();
      expect((await s.packedToday(ivy)).packed, isEmpty);
    });

    testWidgets('the seventh same-in-both item is refused in words', (WidgetTester t) async {
      await big(t);
      final RhythmVoiceService s = freshService();
      await show(t, PackingEditorScreen(childName: 'Ivy', service: s, principal: guardian));
      await t.pumpAndSettle();
      final List<String> things = picturesIn(PictureGroup.thing).map((PictureDef p) => p.id).toList();
      for (int i = 0; i < maxSameItems; i++) {
        await t.tap(find.byKey(const Key('itemAddSame')));
        await t.pumpAndSettle();
        await pick(t, things[i]);
      }
      await t.tap(find.byKey(const Key('itemAddSame')));
      await t.pumpAndSettle();
      await pick(t, things[maxSameItems]);
      expect(find.text('That is the most there is room for.'), findsOneWidget);
    });

    testWidgets('removing an item, and the child principal cannot save', (WidgetTester t) async {
      await big(t);
      final RhythmVoiceService s = freshService();
      await s.savePacking(guardian, addPackItem(const PackingList(), newPackItem('o', 'owl')));
      await show(t, PackingEditorScreen(childName: 'Ivy', service: s, principal: ivy));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('itemRemove_o')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('packingSave')));
      await t.pumpAndSettle();
      expect(find.text('Only a grown-up can change this.'), findsOneWidget);
      expect((await s.rhythm.load()).packing.items.length, 1, reason: 'the refused save changed nothing');
    });
  });

  group('the new place editor', () {
    testWidgets('rooms with a caption (and a photo through the injected picker), a short plan, saved', (WidgetTester t) async {
      await big(t);
      final RhythmVoiceService s = freshService();
      await show(t, NewPlaceEditorScreen(
          childName: 'Ivy', service: s, principal: guardian, pickPhoto: () async => tinyPng));
      await t.pumpAndSettle();
      expect(find.textContaining('no street address, no map, no coordinates'), findsOneWidget);
      await t.enterText(find.byKey(const Key('placeName')), 'Dad\'s new place');
      await t.tap(find.byKey(const Key('stopAdd')));
      await t.pumpAndSettle();
      await pick(t, 'door');
      await typeAndOk(t, 'This is the door');
      await t.tap(find.byKey(const Key('stopAddPhoto')));
      await t.pumpAndSettle();
      await pick(t, 'my-room');
      await typeAndOk(t, 'This is your room');
      await t.tap(find.byKey(const Key('lineAdd')));
      await t.pumpAndSettle();
      await typeAndOk(t, 'We arrive and say hello');
      await t.tap(find.byKey(const Key('placeSave')));
      await t.pumpAndSettle();
      expect(find.text('Saved on this device.'), findsOneWidget);
      final PlacePlan p = (await s.loadPlace(ivy))!;
      expect(p.name, 'Dad\'s new place');
      expect(p.stops.map((PlaceStop x) => x.caption), <String>['This is the door', 'This is your room']);
      expect(p.stops[0].photoB64, isNull);
      expect(p.stops[1].photoB64, isNotNull);
      expect(p.plan, <String>['We arrive and say hello']);
    });

    testWidgets('P3: an address in a caption or a plan line is refused in words; nothing is added', (WidgetTester t) async {
      await big(t);
      final RhythmVoiceService s = freshService();
      await show(t, NewPlaceEditorScreen(childName: 'Ivy', service: s, principal: guardian, pickPhoto: () async => tinyPng));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('stopAdd')));
      await t.pumpAndSettle();
      await pick(t, 'door');
      await typeAndOk(t, '12 Oak Street');
      expect(find.text('Please leave out addresses and places. Rooms only.'), findsOneWidget);
      expect(find.byType(Card), findsNothing);
      await t.tap(find.byKey(const Key('lineAdd')));
      await t.pumpAndSettle();
      await typeAndOk(t, 'Meet at 5 Main St');
      expect(find.byKey(const Key('line_0')), findsNothing);
    });

    testWidgets('a photo that is too big, or not a picture, is refused in words', (WidgetTester t) async {
      await big(t);
      for (final List<int> bad in <List<int>>[List<int>.filled(maxPhotoBytes + 1, 0xFF), <int>[1, 2, 3, 4, 5, 6]]) {
        await show(t, NewPlaceEditorScreen(childName: 'Ivy', service: freshService(), principal: guardian, pickPhoto: () async => bad));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('stopAddPhoto')));
        await t.pumpAndSettle();
        await pick(t, 'door');
        await typeAndOk(t, 'Door');
        expect(find.text('That photo would not work. Choose a smaller picture.'), findsOneWidget);
        expect(find.byKey(const Key('stopRemove_0')), findsNothing);
      }
    });

    testWidgets('cancelling the photo picker adds nothing; the ninth room and fifth line are refused', (WidgetTester t) async {
      await big(t);
      await show(t, NewPlaceEditorScreen(childName: 'Ivy', service: freshService(), principal: guardian, pickPhoto: () async => null));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('stopAddPhoto')));
      await t.pumpAndSettle();
      await pick(t, 'door');
      await typeAndOk(t, 'Door');
      expect(find.byType(Card), findsNothing);
      for (int i = 0; i < maxPlaceStops; i++) {
        await t.tap(find.byKey(const Key('stopAdd')));
        await t.pumpAndSettle();
        await pick(t, 'door');
        await typeAndOk(t, 'Room $i');
      }
      await t.tap(find.byKey(const Key('stopAdd')));
      await t.pumpAndSettle();
      expect(find.text('That is the most there is room for.'), findsOneWidget);
      for (int i = 0; i < maxPlanLines; i++) {
        await t.tap(find.byKey(const Key('lineAdd')));
        await t.pumpAndSettle();
        await typeAndOk(t, 'Line $i');
      }
      await t.tap(find.byKey(const Key('lineAdd')));
      await t.pumpAndSettle();
      expect(find.text('That is the most there is room for.'), findsWidgets);
    });

    testWidgets('removing it from her device deletes the place; the child principal cannot save', (WidgetTester t) async {
      await big(t);
      final RhythmVoiceService s = freshService();
      await s.savePlace(guardian, makePlan('Gran\'s', <PlaceStop>[newStop('s', 'kitchen', 'Kitchen')], const <String>[]));
      await show(t, NewPlaceEditorScreen(childName: 'Ivy', service: s, principal: ivy, pickPhoto: () async => null));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('placeSave')));
      await t.pumpAndSettle();
      expect(find.text('Only a grown-up can change this.'), findsOneWidget);
      await t.tap(find.byKey(const Key('placeClear')));
      await t.pumpAndSettle();
      expect((await s.loadPlace(guardian))!.name, 'Gran\'s', reason: 'the refused clear changed nothing');

      await show(t, NewPlaceEditorScreen(childName: 'Ivy', service: s, principal: guardian, pickPhoto: () async => null));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('placeClear')));
      await t.pumpAndSettle();
      expect(await s.loadPlace(guardian), isNull);
    });
  });

  group('how the app feels', () {
    testWidgets('the settings describe the app, not the child; each change is saved and a no-flash fact is shown', (WidgetTester t) async {
      await big(t);
      final RhythmVoiceService s = freshService();
      await show(t, SensoryEditorScreen(childName: 'Ivy', service: s, principal: guardian));
      await t.pumpAndSettle();
      expect(find.textContaining('describe the app on her device, not her'), findsOneWidget);
      expect(find.text('No flashing, ever'), findsOneWidget);
      expect(find.textContaining(RegExp('sensory|needs|diagnos|condition|disorder', caseSensitive: false)), findsNothing);

      await t.tap(find.text('Low'));
      await t.pumpAndSettle();
      expect((await s.loadRhythm(guardian)).sensory.sound, SoundLevel.low);
      await t.tap(find.byKey(const Key('sensoryMotion')));
      await t.pumpAndSettle();
      expect((await s.loadRhythm(guardian)).sensory.reduceMotion, isTrue);
      await t.tap(find.byKey(const Key('sensoryHaptics')));
      await t.pumpAndSettle();
      expect((await s.loadRhythm(guardian)).sensory.hapticsOff, isTrue);
      await t.drag(find.byKey(const Key('sensoryBrightness')), const Offset(-300, 0));
      await t.pumpAndSettle();
      final int b = (await s.loadRhythm(guardian)).sensory.brightnessCeiling;
      expect(b, lessThan(100));
      expect(b, greaterThanOrEqualTo(minBrightnessPercent));
      expect(b % 10, 0);
    });

    testWidgets('the child principal cannot change them', (WidgetTester t) async {
      await big(t);
      final RhythmVoiceService s = freshService();
      await show(t, SensoryEditorScreen(childName: 'Ivy', service: s, principal: ivy));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('sensoryMotion')));
      await t.pumpAndSettle();
      expect(find.text('Only a grown-up can change this.'), findsOneWidget);
      expect((await s.rhythm.load()).sensory.reduceMotion, isFalse);
      expect(t.widget<SwitchListTile>(find.byKey(const Key('sensoryMotion'))).value, isFalse, reason: 'the screen did not pretend it saved');
    });
  });

  group('helpers editor', () {
    testWidgets('a new helper has not said yes, so she cannot see them until a grown-up ticks the box', (WidgetTester t) async {
      await big(t);
      final RhythmVoiceService s = freshService();
      await show(t, HelpersEditorScreen(childName: 'Ivy', service: s, principal: guardian));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('helperAdd')));
      await t.pumpAndSettle();
      await pick(t, 'grandparent');
      await typeAndOk(t, 'Nana');
      await typeAndOk(t, 'Knock on the door at the end of the hall');
      expect(find.text('Nana'), findsOneWidget);
      expect(helpersForChild((await s.loadVoice(ivy)).helpers), isEmpty, reason: 'not yet said yes');
      final String id = (await s.loadVoice(guardian)).helpers.single.id;
      await t.tap(find.byKey(Key('helperYes_$id')));
      await t.pumpAndSettle();
      expect(helpersForChild((await s.loadVoice(ivy)).helpers).single.name, 'Nana');
      await t.tap(find.byKey(Key('helperYes_$id')));
      await t.pumpAndSettle();
      expect(helpersForChild((await s.loadVoice(ivy)).helpers), isEmpty, reason: 'taken back');
      await t.tap(find.byKey(Key('helperRemove_$id')));
      await t.pumpAndSettle();
      expect((await s.loadVoice(guardian)).helpers, isEmpty);
    });

    testWidgets('a phone number or an address in a name or line is refused in words', (WidgetTester t) async {
      await big(t);
      final RhythmVoiceService s = freshService();
      await show(t, HelpersEditorScreen(childName: 'Ivy', service: s, principal: guardian));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('helperAdd')));
      await t.pumpAndSettle();
      await pick(t, 'friend');
      await typeAndOk(t, 'Sam');
      await typeAndOk(t, 'Call 555 123 4567');
      expect(find.text('Please leave out phone numbers.'), findsOneWidget);
      expect((await s.loadVoice(guardian)).helpers, isEmpty);
      await t.tap(find.byKey(const Key('helperAdd')));
      await t.pumpAndSettle();
      await pick(t, 'friend');
      await typeAndOk(t, 'Sam');
      await typeAndOk(t, '12 Oak Street');
      expect(find.text('Please leave out addresses and places. Rooms only.'), findsOneWidget);
      expect((await s.loadVoice(guardian)).helpers, isEmpty);
    });

    testWidgets('the ninth helper is refused; the child principal cannot add or tick', (WidgetTester t) async {
      await big(t);
      final RhythmVoiceService s = freshService();
      await s.saveHelpers(guardian, <Helper>[for (int i = 0; i < maxHelpers; i++) makeHelper(id: 'h$i', name: 'N$i', picture: 'friend')]);
      await show(t, HelpersEditorScreen(childName: 'Ivy', service: s, principal: guardian));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('helperAdd')));
      await t.pumpAndSettle();
      expect(find.text('That is the most there is room for.'), findsOneWidget);

      await show(t, HelpersEditorScreen(childName: 'Ivy', service: s, principal: ivy));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('helperYes_h0')));
      await t.pumpAndSettle();
      expect(find.text('Only a grown-up can change this.'), findsOneWidget);
      expect((await s.loadVoice(guardian)).helpers.first.saidYes, isFalse);
    });
  });

  group('symbols editor', () {
    testWidgets('a guardian picks personal symbols; they persist; the child principal cannot', (WidgetTester t) async {
      await big(t);
      final RhythmVoiceService s = freshService();
      await show(t, SymbolsEditorScreen(childName: 'Ivy', service: s, principal: guardian));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('extra_sym-want')), findsNothing, reason: 'core words are always there, not optional');
      await t.tap(find.byKey(const Key('extra_sym-owl')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('extra_sym-bath')));
      await t.pumpAndSettle();
      expect((await s.loadVoice(ivy)).personalSymbols, <String>['sym-owl', 'sym-bath']);
      await t.tap(find.byKey(const Key('extra_sym-owl')));
      await t.pumpAndSettle();
      expect((await s.loadVoice(ivy)).personalSymbols, <String>['sym-bath']);

      await show(t, SymbolsEditorScreen(childName: 'Ivy', service: s, principal: ivy));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('extra_sym-home')));
      await t.pumpAndSettle();
      expect(find.text('Only a grown-up can change this.'), findsOneWidget);
      expect((await s.loadVoice(guardian)).personalSymbols, <String>['sym-bath']);
    });
  });

  group('worries she chose to show you', () {
    testWidgets('nothing is there unless she chose to show it; her private ones never appear', (WidgetTester t) async {
      await big(t);
      final RhythmVoiceService s = freshService();
      await s.putWorryPicture(ivy, 'worry-dark');
      await s.putWorryDrawing(ivy, <List<double>>[<double>[0.1, 0.1, 0.9, 0.9]]);
      await show(t, SharedWorriesScreen(childName: 'Ivy', service: s, principal: guardian));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('sharedEmpty')), findsOneWidget);
      expect(find.text('The dark'), findsNothing);
      expect(find.textContaining('That is her choice'), findsOneWidget);

      await s.putWorryPicture(ivy, 'worry-storm', showGrownUp: true);
      await s.putWorryDrawing(ivy, <List<double>>[<double>[0.2, 0.2, 0.7, 0.7]], showGrownUp: true);
      await show(t, SharedWorriesScreen(childName: 'Ivy', service: s, principal: guardian));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('sharedEmpty')), findsNothing);
      expect(find.text('A big storm'), findsOneWidget, reason: 'her picture, with its plain name');
      expect(find.text('The dark'), findsNothing, reason: 'the private one is still private');
      expect(find.byType(WorryThumb), findsNWidgets(2));
    });

    testWidgets('it is a window, not an inbox: nothing to delete, tag, rate, reply to or count', (WidgetTester t) async {
      await big(t);
      final RhythmVoiceService s = freshService();
      await s.putWorryPicture(ivy, 'worry-storm', showGrownUp: true);
      await show(t, SharedWorriesScreen(childName: 'Ivy', service: s, principal: guardian));
      await t.pumpAndSettle();
      expect(find.byType(IconButton), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(find.byIcon(Icons.delete_outline), findsNothing);
      expect(find.byIcon(Icons.flag), findsNothing);
      expect(find.textContaining(RegExp(r'serious|urgent|risk|flag|score|level|\bcount\b|\d')), findsNothing);
      expect(find.textContaining('Nothing here is read, tagged or counted'), findsOneWidget);
    });

    testWidgets('a child principal gets nothing through this window', (WidgetTester t) async {
      await big(t);
      final RhythmVoiceService s = freshService();
      await s.putWorryPicture(ivy, 'worry-storm', showGrownUp: true);
      await show(t, SharedWorriesScreen(childName: 'Ivy', service: s, principal: ivy));
      await t.pumpAndSettle();
      expect(find.text('A big storm'), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('the guardian side has no screen that reads her weather', (WidgetTester t) async {
      await big(t);
      final RhythmVoiceService s = freshService();
      await s.pickTodayWeather(ivy, 'stormy');
      await show(t, VoiceGuardianHubScreen(childName: 'Ivy', service: s, principal: guardian));
      await t.pumpAndSettle();
      expect(find.textContaining('Stormy'), findsNothing);
      expect(find.textContaining(RegExp('weather|sky', caseSensitive: false)), findsOneWidget, reason: 'only the note saying it is hers');
      await expectLater(s.weatherToday(guardian), throwsA(isA<RvRefused>()));
    });
  });

  group('refusal wording', () {
    test('every reason the editors can hit has plain words, and the unknown has a gentle default', () {
      for (final String r in <String>[
        'guardian_only', 'empty_text', 'too_long', 'bad_text', 'looks_like_location', 'looks_like_number', 'too_many_steps',
        'too_many_items', 'too_many_same', 'too_many_stops', 'too_many_lines', 'too_many_helpers', 'too_many_symbols',
        'duplicate_id', 'same_card', 'photo_too_big', 'bad_photo', 'full',
      ]) {
        expect(refusalText(r), isNot('That did not save.'), reason: r);
      }
      expect(refusalText('something_else'), 'That did not save.');
    });
  });
}

