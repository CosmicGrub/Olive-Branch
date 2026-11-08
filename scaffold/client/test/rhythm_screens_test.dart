// OLIVE BRANCH — the child's Rhythm screens: one routine, first-then, packing
// buddy, a new place. Picture-first, 64dp targets, no scores or counters, and
// "how the app feels" applied. Runs at the 344dp cover-screen width.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/rhythm_logic.dart';
import 'package:olive_client/rhythm_screens.dart';
import 'package:olive_client/rhythm_voice_repositories.dart';

import 'rv_support.dart';

Future<RhythmVoiceService> seeded() async {
  final RhythmVoiceService s = freshService();
  await s.saveRoutine(guardian, bedtime());
  await s.saveBoard(guardian, makeBoard(boardCard('bath'), boardCard('book', label: 'Story')));
  PackingList l = addPackItem(const PackingList(), newPackItem('o', 'owl'));
  l = addPackItem(l, newPackItem('b', 'boots'));
  l = addPackItem(l, newPackItem('n', 'night-light', same: true));
  await s.savePacking(guardian, l);
  await s.savePlace(guardian, makePlan('Dad\'s new place', <PlaceStop>[
    newStop('s1', 'door', 'This is the door'),
    newStop('s2', 'my-room', 'This is your room', photoBytes: tinyPng),
  ], <String>['We arrive', 'The owl goes on the bed']));
  return s;
}

void main() {
  group('my routine', () {
    testWidgets('with nothing set up she is told gently, with no setup affordance', (WidgetTester t) async {
      await phone(t);
      await t.pumpWidget(app(MyRoutineScreen(service: freshService())));
      await t.pumpAndSettle();
      expect(find.text('Your grown-up has not made one yet.'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.byIcon(Icons.edit), findsNothing);
    });

    testWidgets('First and Then are shown big; Done moves to the next, calmly', (WidgetTester t) async {
      await phone(t);
      final RhythmVoiceService s = await seeded();
      await t.pumpWidget(app(MyRoutineScreen(service: s)));
      await t.pumpAndSettle();
      expect(find.text('Bedtime'), findsOneWidget, reason: 'the routine\'s own name is the title');
      expect(find.descendant(of: find.byKey(const Key('routineFirst')), matching: find.text('Bath')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('routineThen')), matching: find.text('Pyjamas')), findsOneWidget);
      expect(heightOf(t, find.byKey(const Key('routineDone'))), greaterThanOrEqualTo(64));

      await t.tap(find.byKey(const Key('routineDone')));
      await t.pumpAndSettle();
      expect(find.descendant(of: find.byKey(const Key('routineFirst')), matching: find.text('Pyjamas')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('routineThen')), matching: find.text('A book')), findsOneWidget);
      expect((await s.routineToday(ivy)).ticks.done, <String>['a'], reason: 'her tick is kept on the device');
    });

    testWidgets('finishing is a calm resting state; Again starts over; no counter or score appears at any point', (WidgetTester t) async {
      await phone(t);
      final RhythmVoiceService s = await seeded();
      await t.pumpWidget(app(MyRoutineScreen(service: s)));
      await t.pumpAndSettle();
      for (int i = 0; i < 3; i++) {
        expect(find.textContaining(RegExp(r'\d')), findsNothing, reason: 'no number on screen at step $i');
        expect(find.textContaining(RegExp('of |left|score|streak|star|points|well done', caseSensitive: false)), findsNothing);
        await t.tap(find.byKey(const Key('routineDone')));
        await t.pumpAndSettle();
      }
      expect(find.byKey(const Key('routineAllDone')), findsOneWidget);
      expect(find.text('All done'), findsOneWidget);
      expect(find.byKey(const Key('routineDone')), findsNothing);
      expect(find.textContaining(RegExp(r'\d')), findsNothing);
      expect(heightOf(t, find.byKey(const Key('routineAgain'))), greaterThanOrEqualTo(64));
      await t.tap(find.byKey(const Key('routineAgain')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('routineDone')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('routineFirst')), matching: find.text('Bath')), findsOneWidget);
    });

    testWidgets('what she ticked is still ticked after she leaves and comes back', (WidgetTester t) async {
      await phone(t);
      final RhythmVoiceService s = await seeded();
      await t.pumpWidget(app(MyRoutineScreen(service: s)));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('routineDone')));
      await t.pumpAndSettle();
      await t.pumpWidget(app(const SizedBox()));
      await t.pumpWidget(app(MyRoutineScreen(service: s)));
      await t.pumpAndSettle();
      expect(find.descendant(of: find.byKey(const Key('routineFirst')), matching: find.text('Pyjamas')), findsOneWidget);
    });

    testWidgets('holds up at the cover-screen width with large text (no overflow)', (WidgetTester t) async {
      await phone(t, w: 344, h: 700);
      final RhythmVoiceService s = await seeded();
      await t.pumpWidget(app(MyRoutineScreen(service: s), textScale: 1.8));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.byKey(const Key('routineDone')), findsOneWidget);
    });

    testWidgets('a wide screen puts First and Then side by side', (WidgetTester t) async {
      await phone(t, w: 900, h: 700);
      await t.pumpWidget(app(MyRoutineScreen(service: await seeded())));
      await t.pumpAndSettle();
      final double a = t.getTopLeft(find.byKey(const Key('routineFirst'))).dy;
      final double b = t.getTopLeft(find.byKey(const Key('routineThen'))).dy;
      expect(a, b);
    });

    testWidgets('read-aloud seam: no speaker without a speak callback; with one, the tile reads its name', (WidgetTester t) async {
      await phone(t);
      final RhythmVoiceService s = await seeded();
      await t.pumpWidget(app(MyRoutineScreen(service: s)));
      await t.pumpAndSettle();
      expect(find.byIcon(Icons.volume_up_outlined), findsNothing);

      final List<String> said = <String>[];
      await t.pumpWidget(app(MyRoutineScreen(service: s, speak: (String x) async => said.add(x))));
      await t.pumpAndSettle();
      expect(said, isEmpty, reason: 'it never speaks on its own');
      await t.tap(find.byIcon(Icons.volume_up_outlined).first);
      expect(said, <String>['Bath']);
    });

    testWidgets('how the app feels: sound off silences the seam; no motion turns animation off; brightness ceiling dims', (WidgetTester t) async {
      await phone(t);
      final RhythmVoiceService s = await seeded();
      await s.saveSensory(guardian, const SensoryProfile(sound: SoundLevel.off, reduceMotion: true, brightnessCeiling: 50));
      await t.pumpWidget(app(MyRoutineScreen(service: s, speak: (String x) async {})));
      await t.pumpAndSettle();
      expect(find.byIcon(Icons.volume_up_outlined), findsNothing, reason: 'sound is off, so nothing can be spoken');
      expect(MediaQuery.of(t.element(find.byKey(const Key('routineDone')))).disableAnimations, isTrue);
      final ColoredBox dim = t.widget<ColoredBox>(find.byKey(const Key('brightnessCeiling')));
      expect(dim.color.a, closeTo(0.5, 0.01));
    });

    testWidgets('by default there is no dim layer and animation is on', (WidgetTester t) async {
      await phone(t);
      await t.pumpWidget(app(MyRoutineScreen(service: await seeded())));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('brightnessCeiling')), findsNothing);
      expect(MediaQuery.of(t.element(find.byKey(const Key('routineDone')))).disableAnimations, isFalse);
    });
  });

  group('first, then', () {
    testWidgets('nothing set up: a gentle line', (WidgetTester t) async {
      await phone(t);
      await t.pumpWidget(app(FirstThenScreen(service: freshService())));
      await t.pumpAndSettle();
      expect(find.text('Your grown-up has not set this up yet.'), findsOneWidget);
    });

    testWidgets('two cards; Done makes Then become Now, and it stays so on this day', (WidgetTester t) async {
      await phone(t);
      final RhythmVoiceService s = await seeded();
      await t.pumpWidget(app(FirstThenScreen(service: s)));
      await t.pumpAndSettle();
      expect(find.descendant(of: find.byKey(const Key('boardFirst')), matching: find.text('Bath')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('boardThen')), matching: find.text('Story')), findsOneWidget);
      expect(find.text('Then'), findsOneWidget);
      expect(heightOf(t, find.byKey(const Key('boardDone'))), greaterThanOrEqualTo(64));
      await t.tap(find.byKey(const Key('boardDone')));
      await t.pumpAndSettle();
      expect(find.text('Now'), findsOneWidget);
      expect(find.byKey(const Key('boardDone')), findsNothing);
      expect(find.textContaining(RegExp(r'\d')), findsNothing);

      await t.pumpWidget(app(const SizedBox()));
      await t.pumpWidget(app(FirstThenScreen(service: s)));
      await t.pumpAndSettle();
      expect(find.text('Now'), findsOneWidget, reason: 'kept on the device');
    });
  });

  group('packing buddy', () {
    testWidgets('nothing set up: a gentle line', (WidgetTester t) async {
      await phone(t);
      await t.pumpWidget(app(PackingBuddyScreen(service: freshService())));
      await t.pumpAndSettle();
      expect(find.text('Your grown-up has not made a bag list yet.'), findsOneWidget);
    });

    testWidgets('her things are tickable tiles; always-the-same things are calm chips that cannot be ticked', (WidgetTester t) async {
      await phone(t);
      final RhythmVoiceService s = await seeded();
      await t.pumpWidget(app(PackingBuddyScreen(service: s)));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('pack_o')), findsOneWidget);
      expect(find.byKey(const Key('pack_b')), findsOneWidget);
      expect(find.byKey(const Key('pack_n')), findsNothing, reason: 'the same-in-both item is not a thing to pack');
      expect(find.byKey(const Key('same_n')), findsOneWidget);
      expect(find.text('Always the same'), findsOneWidget);

      await t.tap(find.byKey(const Key('pack_o')));
      await t.pumpAndSettle();
      expect((await s.packedToday(ivy)).packed, <String>['o']);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      await t.tap(find.byKey(const Key('pack_o')));
      await t.pumpAndSettle();
      expect((await s.packedToday(ivy)).packed, isEmpty, reason: 'she can un-pack');
      expect(find.byIcon(Icons.check_circle), findsNothing);

      await t.tap(find.byKey(const Key('same_n')));
      await t.pumpAndSettle();
      expect((await s.packedToday(ivy)).packed, isEmpty, reason: 'tapping a same-at-both chip does nothing');
    });

    testWidgets('no pressure: nothing says forgotten, missing, left or how many', (WidgetTester t) async {
      await phone(t);
      await t.pumpWidget(app(PackingBuddyScreen(service: await seeded())));
      await t.pumpAndSettle();
      expect(find.textContaining(RegExp('forgot|missing|left|remaining|don.t forget|still need', caseSensitive: false)), findsNothing);
      expect(find.textContaining(RegExp(r'\d')), findsNothing);
    });

    testWidgets('her ticks survive leaving the screen', (WidgetTester t) async {
      await phone(t);
      final RhythmVoiceService s = await seeded();
      await t.pumpWidget(app(PackingBuddyScreen(service: s)));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('pack_b')));
      await t.pumpAndSettle();
      await t.pumpWidget(app(const SizedBox()));
      await t.pumpWidget(app(PackingBuddyScreen(service: s)));
      await t.pumpAndSettle();
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });

    testWidgets('tiles are at least 64dp and the screen has no overflow at 344dp with large text', (WidgetTester t) async {
      await phone(t, w: 344, h: 800);
      await t.pumpWidget(app(PackingBuddyScreen(service: await seeded()), textScale: 1.8));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(heightOf(t, find.byKey(const Key('pack_o'))), greaterThanOrEqualTo(64));
      expect(t.getSize(find.byKey(const Key('pack_o'))).width, greaterThanOrEqualTo(64));
    });
  });

  group('a new place', () {
    testWidgets('nothing prepared: a gentle line', (WidgetTester t) async {
      await phone(t);
      await t.pumpWidget(app(NewPlaceScreen(service: freshService())));
      await t.pumpAndSettle();
      expect(find.text('Your grown-up has not got this ready yet.'), findsOneWidget);
    });

    testWidgets('a walk, room by room, then the plan; Back works; no map, no address, no counter', (WidgetTester t) async {
      await phone(t);
      await t.pumpWidget(app(NewPlaceScreen(service: await seeded())));
      await t.pumpAndSettle();
      expect(find.text('Dad\'s new place'), findsOneWidget);
      expect(find.text('This is the door'), findsOneWidget);
      expect(find.byKey(const Key('placeBack')), findsNothing, reason: 'nothing before the first room');
      expect(heightOf(t, find.byKey(const Key('placeNext'))), greaterThanOrEqualTo(64));

      await t.tap(find.byKey(const Key('placeNext')));
      await t.pumpAndSettle();
      expect(find.text('This is your room'), findsOneWidget);
      expect(find.byKey(const Key('placePhoto_s2')), findsOneWidget, reason: 'the room photo is shown');

      await t.tap(find.byKey(const Key('placeNext')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('placePlan')), findsOneWidget);
      expect(find.text('We arrive'), findsOneWidget);
      expect(find.text('The owl goes on the bed'), findsOneWidget);
      expect(find.byKey(const Key('placeNext')), findsNothing);
      expect(find.byKey(const Key('placeFinish')), findsOneWidget);

      await t.tap(find.byKey(const Key('placeBack')));
      await t.pumpAndSettle();
      expect(find.text('This is your room'), findsOneWidget);
      expect(find.byIcon(Icons.map_outlined), findsNothing);
      expect(find.byIcon(Icons.location_on_outlined), findsNothing);
      expect(find.textContaining(RegExp(r'\d')), findsNothing);
    });

    testWidgets('the last room with no plan finishes the walk', (WidgetTester t) async {
      await phone(t);
      final RhythmVoiceService s = freshService();
      await s.savePlace(guardian, makePlan('Gran\'s', <PlaceStop>[newStop('s1', 'kitchen', 'The kitchen')], const <String>[]));
      await t.pumpWidget(app(Builder(builder: (BuildContext c) => Scaffold(
            body: TextButton(
                key: const Key('go'),
                onPressed: () => Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => NewPlaceScreen(service: s))),
                child: const Text('go'))))));
      await t.tap(find.byKey(const Key('go')));
      await t.pumpAndSettle();
      expect(find.text('The kitchen'), findsOneWidget);
      await t.tap(find.byKey(const Key('placeNext')));
      await t.pumpAndSettle();
      expect(find.byType(NewPlaceScreen), findsNothing, reason: 'the walk ended and she is back where she started');
    });

    testWidgets('read-aloud seam reads a caption and a plan line when given a speaker', (WidgetTester t) async {
      await phone(t);
      final List<String> said = <String>[];
      await t.pumpWidget(app(NewPlaceScreen(service: await seeded(), speak: (String x) async => said.add(x))));
      await t.pumpAndSettle();
      await t.tap(find.byIcon(Icons.volume_up_outlined));
      expect(said, <String>['This is the door']);
    });
  });

  group('the child shell has no way to edit any of this', () {
    testWidgets('none of the four screens carries a text field, a switch, a slider or an edit control', (WidgetTester t) async {
      await phone(t);
      final RhythmVoiceService s = await seeded();
      for (final Widget w in <Widget>[
        MyRoutineScreen(service: s), FirstThenScreen(service: s), PackingBuddyScreen(service: s), NewPlaceScreen(service: s),
      ]) {
        await t.pumpWidget(app(w));
        await t.pumpAndSettle();
        expect(find.byType(TextField), findsNothing);
        expect(find.byType(Switch), findsNothing);
        expect(find.byType(Slider), findsNothing);
        expect(find.byIcon(Icons.edit), findsNothing);
        expect(find.byIcon(Icons.delete_outline), findsNothing);
        expect(find.byIcon(Icons.add), findsNothing);
      }
    });
  });
}
