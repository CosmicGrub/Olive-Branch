// OLIVE BRANCH — her own pencil marks on the door, the Feelings corner and the Draw & colour saved-pictures row.
// Parity rows 271, 310, 321, 322, 273, 302. No longer UNVERIFIED (this file is the check).
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/child_home_bands_ui.dart';
import 'package:olive_client/feelings_corner_screen.dart';
import 'package:olive_client/growing_care_logic.dart';
import 'package:olive_client/local_services.dart';
import 'package:olive_client/local_store.dart';
import 'package:olive_client/my_marks.dart';
import 'package:olive_client/rhythm_voice_repositories.dart';
import 'package:olive_client/store_cipher.dart';
import 'package:olive_client/voice_logic.dart';

import 'rv_support.dart';

final Uint8List _key = Uint8List.fromList(List<int>.filled(32, 5));

LocalServices _device(MemoryStoreBackend b) => LocalServices(
    store: LocalStore(backend: b, cipher: AesGcmStoreCipher(_key)), childId: 'ivy', isLive: false, demoSeeds: false);

Future<void> _show(WidgetTester t, Widget w) async {
  t.view.physicalSize = const Size(700, 2400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(MaterialApp(home: w));
  await t.pumpAndSettle();
}

void main() {
  setUp(() => LocalServices.install(_device(MemoryStoreBackend())));

  group('her door', () {
    DateTime clock = DateTime(2026, 11, 13, 9);
    Widget door({Future<List<GrowthMarkView>> Function()? g}) => MyDoorScreen(
        childName: 'Ivy', fromGrownUp: g, now: () => clock = clock.add(const Duration(seconds: 1)));

    testWidgets('a bare door says so; a tap puts a pencil line and the month where she tapped', (WidgetTester t) async {
      await _show(t, door());
      expect(find.text('The door is waiting for its first mark.'), findsOneWidget);
      await t.tapAt(t.getTopLeft(find.byKey(const Key('myDoor'))) + const Offset(100, 100));
      await t.pumpAndSettle();
      expect(find.textContaining('Nov 2026'), findsOneWidget);
      expect(find.text('The door is waiting for its first mark.'), findsNothing);
      final List<MyMark> kept = await MyMarksRepository.forChild().load();
      expect(kept, hasLength(1));
      // 100 down a 320 door is 0.6875 of the way up.
      expect(kept.single.permille, inInclusiveRange(680, 695));
    });

    testWidgets('rub out takes away only the last mark she made, from the screen and the disk', (WidgetTester t) async {
      await _show(t, door());
      final Offset tl = t.getTopLeft(find.byKey(const Key('myDoor')));
      await t.tapAt(tl + const Offset(100, 250));
      await t.pump();
      await t.tapAt(tl + const Offset(100, 60));
      await t.pumpAndSettle();
      expect((await MyMarksRepository.forChild().load()), hasLength(2));
      await t.tap(find.byKey(const Key('myDoorRubOut')));
      await t.pumpAndSettle();
      final List<MyMark> left = await MyMarksRepository.forChild().load();
      expect(left, hasLength(1));
      expect(left.single.permille, lessThan(300), reason: 'the first (low) mark stays; the last (high) one went');
    });

    testWidgets('her marks survive a restart', (WidgetTester t) async {
      final MemoryStoreBackend disk = MemoryStoreBackend();
      LocalServices.install(_device(disk));
      await _show(t, door());
      await t.tapAt(t.getTopLeft(find.byKey(const Key('myDoor'))) + const Offset(100, 100));
      await t.pumpAndSettle();
      await t.pumpWidget(const SizedBox());
      LocalServices.install(_device(disk));
      await _show(t, door());
      expect(find.textContaining('Nov 2026'), findsOneWidget);
    });

    testWidgets('a grown-up\'s marks are listed by month only, below hers, with no number', (WidgetTester t) async {
      await _show(t, door(g: () async => const <GrowthMarkView>[GrowthMarkView(id: 'm', label: 'June 2026', fraction: 1)]));
      expect(find.text('From a grown-up'), findsOneWidget);
      expect(find.text('June 2026'), findsOneWidget);
      expect(find.textContaining(RegExp(r'\d+ ?cm')), findsNothing);
    });

    testWidgets('a full door says so gently and keeps nothing more', (WidgetTester t) async {
      final MyMarksRepository repo = MyMarksRepository.forChild();
      for (int i = 0; i < maxPencilMarks; i++) {
        await repo.add(MyMark(id: 'x$i', on: '2026-01-01', permille: 500, at: i));
      }
      await _show(t, door());
      await t.tapAt(t.getTopLeft(find.byKey(const Key('myDoor'))) + const Offset(100, 100));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('myDoorNote')), findsOneWidget);
      expect(await repo.load(), hasLength(maxPencilMarks));
    });

    test('the data wipe screen can name the area (catalogue has it, sealed, no total)', () {
      final LocalDataEntry e = localDataEntry('mymarks');
      expect(e.encrypted, isTrue);
      expect(e.what.toLowerCase(), contains('no centimetres'));
    });
  });

  group('the Feelings corner', () {
    Future<void> open(WidgetTester t, RhythmVoiceService s) async {
      await phone(t, w: 390, h: 1200);
      await t.pumpWidget(app(FeelingsCornerScreen(service: s, yearsOld: 9)));
      await t.pumpAndSettle();
    }

    testWidgets('with Voice off (the default) there is nothing in it and no tool is reachable', (WidgetTester t) async {
      await open(t, freshService());
      for (final String k in <String>['feelWeather', 'feelWorry', 'feelHelpers', 'feelSymbols']) {
        expect(find.byKey(Key(k)), findsNothing, reason: k);
      }
      expect((await feelingsToolsFor(service: freshService(), yearsOld: 9)).anyVoice, isFalse);
    });

    testWidgets('with Voice on it gathers the sky, the worry box and the pictures, and each opens', (WidgetTester t) async {
      final RhythmVoiceService s = freshService();
      await s.setVoiceSuite(guardian, true);
      await open(t, s);
      expect(find.byKey(const Key('feelWeather')), findsOneWidget);
      expect(find.byKey(const Key('feelWorry')), findsOneWidget);
      expect(find.byKey(const Key('feelSymbols')), findsOneWidget);
      expect(find.byKey(const Key('feelHelpers')), findsNothing, reason: 'no helper has been written yet');
      // No call button, count or score: calls are parked, and nothing here is a number.
      expect(find.textContaining(RegExp(r'call|score|streak|\d')), findsNothing);
      await t.tap(find.byKey(const Key('feelWorry')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('feelWorry')), findsNothing, reason: 'the worry box opened');
    });

    testWidgets('a written helper adds My helpers', (WidgetTester t) async {
      final RhythmVoiceService s = freshService();
      await s.setVoiceSuite(guardian, true);
      await s.saveHelpers(guardian, <Helper>[makeHelper(id: 'h', name: 'Nana', picture: 'grandparent', saidYes: true)]);
      await open(t, s);
      expect(find.byKey(const Key('feelHelpers')), findsOneWidget);
    });

    testWidgets('holds at 344 dp and 2.0x text with no overflow', (WidgetTester t) async {
      final RhythmVoiceService s = freshService();
      await s.setVoiceSuite(guardian, true);
      await phone(t, w: 344, h: 900);
      await t.pumpWidget(app(FeelingsCornerScreen(service: s, yearsOld: 9), textScale: 2.0));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  });

  group('Draw & colour', () {
    testWidgets('the third row, My saved pictures, opens what she kept', (WidgetTester t) async {
      await _show(t, DrawChoiceScreen(
          title: 'Draw & colour', doodle: const Text('doodle page'), colouring: const Text('colour page'),
          pictures: const Text('pictures page')));
      expect(find.byKey(const Key('drawPictures')), findsOneWidget);
      await t.tap(find.byKey(const Key('drawPictures')));
      await t.pumpAndSettle();
      expect(find.text('pictures page'), findsOneWidget);
    });

    testWidgets('without a pictures page the row is not drawn (older callers)', (WidgetTester t) async {
      await _show(t, const DrawChoiceScreen(title: 'Studio', doodle: Text('a'), colouring: Text('b')));
      expect(find.byKey(const Key('drawPictures')), findsNothing);
    });

    testWidgets('three rows fit at 344 dp and 2.0x text (it scrolls, never overflows)', (WidgetTester t) async {
      await phone(t, w: 344, h: 640);
      await t.pumpWidget(app(
          const DrawChoiceScreen(title: 'Draw & colour', doodle: Text('a'), colouring: Text('b'), pictures: Text('c')),
          textScale: 2.0));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  });
}
