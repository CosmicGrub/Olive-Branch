// OLIVE BRANCH — suite G (Growing) screens: the grown-up side (time capsule,
// first times, growing marks) and her side (memory box, doorframe, firsts she
// was shown, opened letters), plus the age-band gate on her "Keep and grow"
// section and the guardian hub. Local only: no network anywhere.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/care_screens.dart';
import 'package:olive_client/child_more.dart';
import 'package:olive_client/family_structure_logic.dart';
import 'package:olive_client/family_structure_store.dart';
import 'package:olive_client/growing_care_logic.dart';
import 'package:olive_client/growing_care_store.dart';
import 'package:olive_client/growing_screens.dart';
import 'package:olive_client/snapshot_button.dart';

final DateTime _today = DateTime(2026, 11, 8, 9);
DateTime _now() => _today;

Uint8List _bytes(int n) => Uint8List.fromList(List<int>.filled(n, 3));

Future<void> _show(WidgetTester t, Widget w, {Size size = const Size(700, 2600)}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(MaterialApp(home: w));
  await t.pumpAndSettle();
}

Future<void> _type(WidgetTester t, String key, String text) async {
  await t.enterText(find.byKey(Key(key)), text);
  await t.pump();
}

Future<void> _tap(WidgetTester t, String key) async {
  await t.ensureVisible(find.byKey(Key(key)));
  await t.tap(find.byKey(Key(key)));
  await t.pumpAndSettle();
}

TimeCapsule _cap(String id, {String opens = '2039-06-01', String note = 'You were so brave.', bool unseal = false}) {
  final TimeCapsule c = TimeCapsule(id: id, title: 'For thirteen', note: note, sealedOn: '2026-11-01', opensOn: opens);
  return unseal ? c.unsealed('2026-11-08') : c;
}

void main() {
  group('time capsule (grown-up side)', () {
    testWidgets('says it is on this device and that the clock decides', (t) async {
      await _show(t, TimeCapsuleScreen(stores: GrowingCareStores.memory(), now: _now));
      expect(find.textContaining("device's clock"), findsOneWidget);
      expect(find.textContaining('Changing the clock would open it early'), findsOneWidget);
      expect(find.byKey(const Key('capsuleEmpty')), findsOneWidget);
    });

    testWidgets('sealing keeps it, and the words are hidden from the guardian until it opens', (t) async {
      final GrowingCareStores s = GrowingCareStores.memory();
      await _show(t, TimeCapsuleScreen(stores: s, now: _now));
      await _tap(t, 'sealSomething');
      await _type(t, 'capsuleTitle', 'For thirteen');
      await _type(t, 'capsuleNoteField', 'You were so brave.');
      await t.enterText(find.descendant(of: find.byKey(const Key('capsuleOpens')), matching: find.byType(TextField)), '2039-06-01');
      await _tap(t, 'sealIt');
      expect(find.text('For thirteen'), findsOneWidget);
      expect(find.textContaining('Sealed. Opens on 1 Jun 2039.'), findsOneWidget);
      expect(find.byKey(const Key('sealedHidden')), findsOneWidget);
      expect(find.text('You were so brave.'), findsNothing);
      expect(await s.capsules.list(), hasLength(1));
    });

    testWidgets('a date that is not after today is refused and nothing is kept', (t) async {
      final GrowingCareStores s = GrowingCareStores.memory();
      await _show(t, TimeCapsuleScreen(stores: s, now: _now));
      await _tap(t, 'sealSomething');
      await _type(t, 'capsuleTitle', 'Too soon');
      await _type(t, 'capsuleNoteField', 'hello');
      final Finder date = find.descendant(of: find.byKey(const Key('capsuleOpens')), matching: find.byType(TextField));
      await t.enterText(date, '2026-11-08');
      await _tap(t, 'sealIt');
      expect(find.text('A capsule needs a day after today to open on.'), findsOneWidget);
      await t.enterText(date, 'next year');
      await _tap(t, 'sealIt');
      expect(find.textContaining('not a real date'), findsOneWidget);
      await t.enterText(date, '2070-01-01');
      await _tap(t, 'sealIt');
      expect(find.textContaining('too far ahead'), findsOneWidget);
      expect(await s.capsules.list(), isEmpty);
    });

    testWidgets('an empty capsule (no words and no photo) is refused', (t) async {
      final GrowingCareStores s = GrowingCareStores.memory();
      await _show(t, TimeCapsuleScreen(stores: s, now: _now));
      await _tap(t, 'sealSomething');
      await _type(t, 'capsuleTitle', 'Nothing in it');
      await t.enterText(find.descendant(of: find.byKey(const Key('capsuleOpens')), matching: find.byType(TextField)), '2030-01-01');
      await _tap(t, 'sealIt');
      expect(find.text('There is nothing written yet.'), findsOneWidget);
      expect(await s.capsules.list(), isEmpty);
    });

    testWidgets('a photo is kept small: one over the cap is refused with an honest message', (t) async {
      final GrowingCareStores s = GrowingCareStores.memory();
      await _show(t, TimeCapsuleScreen(stores: s, now: _now, photoSource: () async => _bytes(maxThumbBytes + 1)));
      await _tap(t, 'sealSomething');
      await _tap(t, 'pickPhoto');
      expect(find.text('That photo is too big to keep here. Try a smaller one.'), findsOneWidget);
      expect(find.byKey(const Key('clearPhoto')), findsNothing);
    });

    testWidgets('a small photo is kept with the capsule', (t) async {
      final GrowingCareStores s = GrowingCareStores.memory();
      await _show(t, TimeCapsuleScreen(stores: s, now: _now, photoSource: () async => _bytes(500)));
      await _tap(t, 'sealSomething');
      await _tap(t, 'pickPhoto');
      await _type(t, 'capsuleTitle', 'A photo');
      await t.enterText(find.descendant(of: find.byKey(const Key('capsuleOpens')), matching: find.byType(TextField)), '2030-01-01');
      await _tap(t, 'sealIt');
      expect((await s.capsules.list()).single.thumb, hasLength(500));
    });

    testWidgets('it opens by the clock: the same capsule shows its words once its day has come', (t) async {
      final GrowingCareStores s = GrowingCareStores.memory();
      await s.capsules.save(_cap('c1', opens: '2026-12-01'));
      await _show(t, TimeCapsuleScreen(stores: s, now: _now));
      expect(find.text('You were so brave.'), findsNothing);
      await t.pumpWidget(const SizedBox());
      await _show(t, TimeCapsuleScreen(stores: s, now: () => DateTime(2026, 12, 1)));
      expect(find.byKey(const Key('capsuleNote')), findsOneWidget);
      expect(find.text('You were so brave.'), findsOneWidget);
    });

    testWidgets('a guardian can open one early, after being asked; keeping it sealed changes nothing', (t) async {
      final GrowingCareStores s = GrowingCareStores.memory();
      await s.capsules.save(_cap('c1'));
      await _show(t, TimeCapsuleScreen(stores: s, now: _now));
      await _tap(t, 'unseal');
      expect(find.text('Open this early?'), findsOneWidget);
      await _tap(t, 'keepSealed');
      expect(find.text('You were so brave.'), findsNothing);
      expect((await s.capsules.list()).single.unsealedOn, isNull);
      await _tap(t, 'unseal');
      await _tap(t, 'openNow');
      expect(find.text('You were so brave.'), findsOneWidget);
      expect((await s.capsules.list()).single.unsealedOn, '2026-11-08');
    });

    testWidgets('removing asks first', (t) async {
      final GrowingCareStores s = GrowingCareStores.memory();
      await s.capsules.save(_cap('c1'));
      await _show(t, TimeCapsuleScreen(stores: s, now: _now));
      await _tap(t, 'removeCapsule');
      await _tap(t, 'confirmKeep');
      expect(await s.capsules.list(), hasLength(1));
      await _tap(t, 'removeCapsule');
      await _tap(t, 'confirmGo');
      expect(await s.capsules.list(), isEmpty);
    });
  });

  group('first times (grown-up side)', () {
    testWidgets('adding one keeps it, without any count, streak or list of firsts to come', (t) async {
      final GrowingCareStores s = GrowingCareStores.memory();
      await _show(t, FirstTimesScreen(stores: s, now: _now));
      expect(find.byKey(const Key('firstsEmpty')), findsOneWidget);
      await _tap(t, 'addFirst');
      await _type(t, 'firstTitle', 'First lost tooth');
      await _tap(t, 'saveFirst');
      expect(find.text('First lost tooth'), findsOneWidget);
      expect(find.text('8 Nov 2026'), findsOneWidget);
      expect(find.textContaining(RegExp(r'\d+ (firsts|of|so far)', caseSensitive: false)), findsNothing);
      expect(find.textContaining(RegExp('streak|score|still to|next up', caseSensitive: false)), findsNothing);
      expect((await s.firsts.list()).single.showHer, isFalse, reason: 'hidden from her until a guardian says so');
    });

    testWidgets('refused: no title, and a day that has not happened yet', (t) async {
      final GrowingCareStores s = GrowingCareStores.memory();
      await _show(t, FirstTimesScreen(stores: s, now: _now));
      await _tap(t, 'addFirst');
      await _tap(t, 'saveFirst');
      expect(find.text('There is nothing written yet.'), findsOneWidget);
      await _type(t, 'firstTitle', 'Tomorrow thing');
      await t.enterText(find.descendant(of: find.byKey(const Key('firstDate')), matching: find.byType(TextField)), '2026-12-25');
      await _tap(t, 'saveFirst');
      expect(find.text('That date has not happened yet.'), findsOneWidget);
      expect(await s.firsts.list(), isEmpty);
    });

    testWidgets('"Show her this one" is a per-item choice that is saved', (t) async {
      final GrowingCareStores s = GrowingCareStores.memory();
      await s.firsts.save(const FirstTime(id: 'f1', title: 'Bike', on: '2026-08-03'));
      await _show(t, FirstTimesScreen(stores: s, now: _now));
      await _tap(t, 'showHer-f1');
      expect((await s.firsts.get('f1'))!.showHer, isTrue);
      await _tap(t, 'showHer-f1');
      expect((await s.firsts.get('f1'))!.showHer, isFalse);
    });

    testWidgets('newest first; remove asks first', (t) async {
      final GrowingCareStores s = GrowingCareStores.memory();
      await s.firsts.save(const FirstTime(id: 'a', title: 'Older', on: '2026-01-01'));
      await s.firsts.save(const FirstTime(id: 'b', title: 'Newer', on: '2026-10-01'));
      await _show(t, FirstTimesScreen(stores: s, now: _now));
      expect(t.getTopLeft(find.text('Newer')).dy, lessThan(t.getTopLeft(find.text('Older')).dy));
      await _tap(t, 'removeFirst-a');
      await _tap(t, 'confirmGo');
      expect((await s.firsts.list()).map((FirstTime f) => f.id), <String>['b']);
    });

    testWidgets('a photo is kept small', (t) async {
      final GrowingCareStores s = GrowingCareStores.memory();
      await _show(t, FirstTimesScreen(stores: s, now: _now, photoSource: () async => _bytes(400)));
      await _tap(t, 'addFirst');
      await _tap(t, 'pickPhoto');
      await _type(t, 'firstTitle', 'Swim');
      await _tap(t, 'saveFirst');
      expect((await s.firsts.list()).single.thumb, hasLength(400));
    });
  });

  group('growing marks (grown-up side) and her doorframe', () {
    testWidgets('a mark is a record in centimetres for the guardian, with a doorframe picture beside it', (t) async {
      final GrowingCareStores s = GrowingCareStores.memory();
      await _show(t, PencilMarksScreen(stores: s, now: _now));
      expect(find.byKey(const Key('doorframe')), findsOneWidget);
      await _type(t, 'markCm', '111');
      await _tap(t, 'addMark');
      expect(find.text('111 cm'), findsOneWidget);
      expect((await s.marks.list()).single.on, '2026-11-08');
      expect(find.textContaining(RegExp('percentile|average|centile|normal', caseSensitive: false)), findsNothing);
    });

    testWidgets('refused: a height that is not a height, and a day not yet come', (t) async {
      final GrowingCareStores s = GrowingCareStores.memory();
      await _show(t, PencilMarksScreen(stores: s, now: _now));
      await _type(t, 'markCm', 'tall');
      await _tap(t, 'addMark');
      expect(find.textContaining('Heights run from'), findsOneWidget);
      await _type(t, 'markCm', '900');
      await _tap(t, 'addMark');
      expect(find.textContaining('Heights run from'), findsOneWidget);
      await _type(t, 'markCm', '110');
      await t.enterText(find.descendant(of: find.byKey(const Key('markDate')), matching: find.byType(TextField)), '2027-01-01');
      await _tap(t, 'addMark');
      expect(find.text('That date has not happened yet.'), findsOneWidget);
      expect(await s.marks.list(), isEmpty);
    });

    testWidgets('a mark can be removed after asking', (t) async {
      final GrowingCareStores s = GrowingCareStores.memory();
      await s.marks.save(const PencilMark(id: 'm1', on: '2026-06-01', cm: 100));
      await _show(t, PencilMarksScreen(stores: s, now: _now));
      await _tap(t, 'removeMark-m1');
      await _tap(t, 'confirmGo');
      expect(await s.marks.list(), isEmpty);
    });

    testWidgets("her doorframe shows a line and a month for each mark, and no number or comparison at all", (t) async {
      final GrowingCareStores s = GrowingCareStores.memory();
      await s.marks.save(const PencilMark(id: 'a', on: '2026-06-01', cm: 108));
      await s.marks.save(const PencilMark(id: 'b', on: '2026-11-01', cm: 113));
      await _show(t, GrowthPictureScreen(childName: 'Ivy', lens: s.childLens(now: _now)));
      expect(find.text('Jun 2026'), findsOneWidget);
      expect(find.text('Nov 2026'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('doormark-a')), findsOneWidget);
      expect(find.textContaining(RegExp(r'cm|percentile|average|taller than|shorter|\b1[01]\d\b', caseSensitive: false)), findsNothing);
    });

    testWidgets('an empty doorframe waits gently', (t) async {
      await _show(t, GrowthPictureScreen(childName: 'Ivy', lens: GrowingCareStores.memory().childLens(now: _now)));
      expect(find.textContaining('waiting for its first mark'), findsOneWidget);
    });
  });

  group("her side: firsts she was shown and letters that have opened", () {
    testWidgets('only the firsts a guardian chose to show, picture first, with a month and no count', (t) async {
      final GrowingCareStores s = GrowingCareStores.memory();
      await s.firsts.save(const FirstTime(id: 'a', title: 'Hidden one', on: '2026-09-01'));
      await s.firsts.save(const FirstTime(id: 'b', title: 'Shown one', on: '2026-09-12', showHer: true));
      await _show(t, MyFirstsScreen(lens: s.childLens(now: _now)));
      expect(find.text('Shown one'), findsOneWidget);
      expect(find.text('Hidden one'), findsNothing);
      expect(find.text('Sep 2026'), findsOneWidget);
      expect(find.textContaining(RegExp(r'\d+ (of|firsts)')), findsNothing);
      expect(find.byType(TextField), findsNothing, reason: 'read-only');
    });

    testWidgets('a sealed capsule is simply not there', (t) async {
      final GrowingCareStores s = GrowingCareStores.memory();
      await s.capsules.save(_cap('c1'));
      await _show(t, LettersOpenedScreen(lens: s.childLens(now: _now)));
      expect(find.text('For thirteen'), findsNothing);
      expect(find.text('You were so brave.'), findsNothing);
      expect(find.text('Nothing here yet.'), findsOneWidget);
    });

    testWidgets('a letter whose day has come can be read', (t) async {
      final GrowingCareStores s = GrowingCareStores.memory();
      await s.capsules.save(_cap('c1', opens: '2026-11-08'.replaceFirst('-08', '-07')).unsealed('2026-11-08'));
      await _show(t, LettersOpenedScreen(lens: s.childLens(now: _now)));
      expect(find.text('You were so brave.'), findsOneWidget);
    });
  });

  group('her memory box', () {
    AppGallery galleryWith(List<AppPhoto> photos) {
      final AppGallery g = AppGallery();
      for (final AppPhoto p in photos) {
        g.add(p);
      }
      return g;
    }

    final AppPhoto doodle = AppPhoto(
        id: 'd1', surface: 'doodle', savedAt: DateTime(2026, 11, 1), kind: 'doodle',
        data: const <String, Object?>{'w': 100, 'h': 100, 'strokes': <Object?>[]});

    testWidgets('starts empty and gentle, says it is on this device, and has 64dp buttons', (t) async {
      await _show(t, MemoryBoxScreen(stores: GrowingCareStores.memory(), gallery: AppGallery(), now: _now));
      expect(find.byKey(const Key('memoryEmpty')), findsOneWidget);
      expect(find.textContaining('stay on this device'), findsOneWidget);
      expect(t.getSize(find.byKey(const Key('keepPicture'))).height, greaterThanOrEqualTo(64));
      expect(t.getSize(find.byKey(const Key('keepPhoto'))).height, greaterThanOrEqualTo(64));
    });

    testWidgets('she can keep a copy of a picture she made', (t) async {
      final GrowingCareStores s = GrowingCareStores.memory();
      await _show(t, MemoryBoxScreen(stores: s, gallery: galleryWith(<AppPhoto>[doodle]), now: _now));
      await _tap(t, 'keepPicture');
      await t.tap(find.byKey(const ValueKey<String>('choose-d1')));
      await t.pumpAndSettle();
      final List<MemoryItem> kept = await s.memories.list();
      expect(kept.single.kind, 'doodle');
      expect(kept.single.pictureData, isNotNull);
      expect(find.byKey(const Key('memoryEmpty')), findsNothing);
    });

    testWidgets('with nothing made yet she is told so, and nothing is added', (t) async {
      final GrowingCareStores s = GrowingCareStores.memory();
      await _show(t, MemoryBoxScreen(stores: s, gallery: AppGallery(), now: _now));
      await _tap(t, 'keepPicture');
      expect(find.byKey(const Key('noPicturesYet')), findsOneWidget);
    });

    testWidgets('she can keep a photo', (t) async {
      final GrowingCareStores s = GrowingCareStores.memory();
      await _show(t, MemoryBoxScreen(stores: s, gallery: AppGallery(), now: _now, photoSource: () async => _bytes(300)));
      await _tap(t, 'keepPhoto');
      expect((await s.memories.list()).single.kind, 'photo');
    });

    testWidgets('a cancelled photo adds nothing; a photo over the cap says so gently and adds nothing', (t) async {
      final GrowingCareStores s = GrowingCareStores.memory();
      await _show(t, MemoryBoxScreen(stores: s, gallery: AppGallery(), now: _now, photoSource: () async => null));
      await _tap(t, 'keepPhoto');
      expect(await s.memories.list(), isEmpty);
      await t.pumpWidget(const SizedBox());
      await _show(t, MemoryBoxScreen(stores: s, gallery: AppGallery(), now: _now, photoSource: () async => _bytes(maxThumbBytes + 1)));
      await _tap(t, 'keepPhoto');
      expect(find.text('That photo is too big to keep here. Try a smaller one.'), findsOneWidget);
      expect(await s.memories.list(), isEmpty);
    });

    testWidgets('a full memory box says so and keeps what it has', (t) async {
      final GrowingCareStores s = GrowingCareStores.memory();
      for (int i = 0; i < maxMemoryItems; i++) {
        await s.memories.save(MemoryItem(id: 'x$i', kind: 'photo', addedOn: '2026-11-0${1 + i % 8}', thumb: _bytes(8)));
      }
      await _show(t, MemoryBoxScreen(stores: s, gallery: AppGallery(), now: _now, photoSource: () async => _bytes(8)));
      await _tap(t, 'keepPhoto');
      expect(find.textContaining('no more room'), findsOneWidget);
      expect(await s.memories.list(), hasLength(maxMemoryItems));
    });

    testWidgets('she puts one away only after being asked', (t) async {
      final GrowingCareStores s = GrowingCareStores.memory();
      await s.memories.save(MemoryItem(id: 'x1', kind: 'photo', addedOn: '2026-11-08', thumb: _bytes(8)));
      await _show(t, MemoryBoxScreen(stores: s, gallery: AppGallery(), now: _now));
      await t.longPress(find.byKey(const ValueKey<String>('memory-x1')));
      await t.pumpAndSettle();
      await _tap(t, 'confirmKeep');
      expect(await s.memories.list(), hasLength(1));
      await t.longPress(find.byKey(const ValueKey<String>('memory-x1')));
      await t.pumpAndSettle();
      await _tap(t, 'confirmGo');
      expect(await s.memories.list(), isEmpty);
    });

    testWidgets('no audio: it offers pictures and photos only, and nothing counts or resurfaces', (t) async {
      await _show(t, MemoryBoxScreen(stores: GrowingCareStores.memory(), gallery: AppGallery(), now: _now));
      expect(find.byIcon(Icons.mic), findsNothing);
      expect(find.byIcon(Icons.mic_none), findsNothing);
      expect(find.textContaining(RegExp(r'on this day|remember when|streak|\d+ (things|items)', caseSensitive: false)), findsNothing);
    });
  });

  group('her "Keep and grow" section follows the age band and the guardian switches', () {
    FamilyChildSnapshot snap(String band) =>
        FamilyChildSnapshot(view: deriveChildView(const FamilyStructure(), band, null, const <String>[]));

    Future<void> openMore(WidgetTester t, GrowingCareStores s, {FamilyChildSnapshot? family, int age = 6}) =>
        _show(t, ChildMoreScreen(childName: 'Ivy', childAge: age, family: family, growingCare: s),
            size: const Size(700, 3200));

    testWidgets('the youngest band has no section at all', (t) async {
      await openMore(t, GrowingCareStores.memory(), family: snap('t34'), age: 4);
      expect(find.text('KEEP AND GROW'), findsNothing);
      expect(find.byKey(const Key('childMemoryBox')), findsNothing);
    });

    testWidgets('from the next band up, her memory box is there and opens', (t) async {
      await openMore(t, GrowingCareStores.memory(), family: snap('t57'));
      expect(find.text('KEEP AND GROW'), findsOneWidget);
      await _tap(t, 'childMemoryBox');
      expect(find.byType(MemoryBoxScreen), findsOneWidget);
    });

    testWidgets('with no derived view, age decides, and an unknown age fails closed to five', (t) async {
      await openMore(t, GrowingCareStores.memory(), age: 8);
      expect(find.byKey(const Key('childMemoryBox')), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await openMore(t, GrowingCareStores.memory(), age: 3);
      expect(find.byKey(const Key('childMemoryBox')), findsNothing);
    });

    testWidgets('a guardian switch removes it', (t) async {
      final GrowingCareStores s = GrowingCareStores.memory();
      await s.switches.setSuite('memoryBox', false);
      await openMore(t, s, family: snap('t57'));
      expect(find.byKey(const Key('childMemoryBox')), findsNothing);
    });

    testWidgets('doorframe, firsts, letters and stories each appear only when there is something to see', (t) async {
      final GrowingCareStores s = GrowingCareStores.memory();
      await openMore(t, s, family: snap('t57'));
      for (final String k in <String>['childDoorframe', 'childFirsts', 'childLetters', 'childStories']) {
        expect(find.byKey(Key(k)), findsNothing, reason: k);
      }
      await t.pumpWidget(const SizedBox());
      await s.marks.save(const PencilMark(id: 'm', on: '2026-06-01', cm: 100));
      await s.firsts.save(const FirstTime(id: 'f', title: 'Tooth', on: '2026-09-01', showHer: true));
      await s.capsules.save(_cap('c').unsealed('2026-11-08'));
      await s.stories.save(const ExplainerStory(id: 'e', title: 'A story', pages: <String>['p'], updatedOn: '2026-11-08', shownToHer: true));
      await openMore(t, s, family: snap('t57'));
      for (final String k in <String>['childDoorframe', 'childFirsts', 'childLetters', 'childStories']) {
        expect(find.byKey(Key(k)), findsOneWidget, reason: k);
      }
    });

    testWidgets('a hidden first, a sealed capsule and an unshown story do not make a tile', (t) async {
      final GrowingCareStores s = GrowingCareStores.memory();
      await s.firsts.save(const FirstTime(id: 'f', title: 'Tooth', on: '2026-09-01'));
      await s.capsules.save(_cap('c'));
      await s.stories.save(const ExplainerStory(id: 'e', title: 'A story', pages: <String>['p'], updatedOn: '2026-11-08'));
      await openMore(t, s, family: snap('t57'));
      for (final String k in <String>['childFirsts', 'childLetters', 'childStories']) {
        expect(find.byKey(Key(k)), findsNothing, reason: k);
      }
    });

    testWidgets('a switched-off suite hides its tile even when there is content', (t) async {
      final GrowingCareStores s = GrowingCareStores.memory();
      await s.marks.save(const PencilMark(id: 'm', on: '2026-06-01', cm: 100));
      await s.switches.setSuite('pencilMarks', false);
      await openMore(t, s, family: snap('t57'));
      expect(find.byKey(const Key('childDoorframe')), findsNothing);
    });

    testWidgets('care information is never on her side: no binder, hospital, prep or emergency words', (t) async {
      final GrowingCareStores s = GrowingCareStores.memory();
      await s.sections.save(const CareSection(id: 's', kind: 'allergies', title: 'Allergies (written by a guardian)', body: 'x', updatedOn: '2026-11-08'));
      await s.hospital.save(const HospitalNotes(happeningToday: 'x'));
      await s.preps.save(const AppointmentPrep(id: 'a', title: 'Check-up', createdOn: '2026-11-08'));
      await openMore(t, s, family: snap('t57'));
      expect(find.textContaining(RegExp('binder|hospital|appointment|allerg|emergency|medicine', caseSensitive: false)), findsNothing);
    });
  });

  group('the Growing hub (grown-up side)', () {
    testWidgets('lists the three grown-up editors, says it is local, and is explicit that memory box is hers', (t) async {
      await _show(t, GrowingCareHubScreen(care: false, stores: GrowingCareStores.memory()));
      for (final String k in <String>['hubTimeCapsule', 'hubFirstTimes', 'hubPencilMarks']) {
        expect(find.byKey(Key(k)), findsOneWidget, reason: k);
      }
      expect(find.byKey(const Key('localOnlyNote')), findsOneWidget);
      expect(find.textContaining('Hers to fill'), findsOneWidget);
      expect(find.byKey(const Key('hubMemoryBox')), findsOneWidget, reason: 'a grown-up may only leave a marked note');
    });

    testWidgets('switching a suite off removes its entry and the choice is kept', (t) async {
      final GrowingCareStores s = GrowingCareStores.memory();
      await _show(t, GrowingCareHubScreen(care: false, stores: s));
      await _tap(t, 'switch_firstTimes');
      expect(find.byKey(const Key('hubFirstTimes')), findsNothing);
      expect(find.byKey(const Key('hubTimeCapsule')), findsOneWidget);
      expect((await s.switches.load()).on('firstTimes'), isFalse);
      await t.pumpWidget(const SizedBox());
      await _show(t, GrowingCareHubScreen(care: false, stores: s));
      expect(find.byKey(const Key('hubFirstTimes')), findsNothing, reason: 'it stays off after a restart of the screen');
    });

    testWidgets('with everything off it says so', (t) async {
      final GrowingCareStores s = GrowingCareStores.memory();
      for (final String k in growingSuiteKeys) {
        await s.switches.setSuite(k, false);
      }
      await _show(t, GrowingCareHubScreen(care: false, stores: s));
      expect(find.byKey(const Key('hubAllOff')), findsOneWidget);
    });

    testWidgets('each entry opens its real screen', (t) async {
      final GrowingCareStores s = GrowingCareStores.memory();
      await _show(t, GrowingCareHubScreen(care: false, stores: s));
      await _tap(t, 'hubTimeCapsule');
      expect(find.byType(TimeCapsuleScreen), findsOneWidget);
      await t.pageBack();
      await t.pumpAndSettle();
      await _tap(t, 'hubFirstTimes');
      expect(find.byType(FirstTimesScreen), findsOneWidget);
      await t.pageBack();
      await t.pumpAndSettle();
      await _tap(t, 'hubPencilMarks');
      expect(find.byType(PencilMarksScreen), findsOneWidget);
    });
  });
}
