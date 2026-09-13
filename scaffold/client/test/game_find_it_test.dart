// OLIVE BRANCH — game_find_it.dart tests. MASTERFILE §9.2, §8.11.1, §8.13,
// §8.4, P2.
//
// The property that matters most, and the reason this test file exists at
// all beyond the usual per-screen suite: device posture must change the
// ACTUAL NUMBER of objects rendered, not just their layout — the one
// activity in the whole Phase 1 spec where that's true. Also covers real
// found/not-found state-machine correctness, the curated-scene variety
// (three genuinely distinct scenes, not one re-skinned three times), the
// zero-text-gameplay claim, P2, and real navigation reachability.
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/child_home.dart';
import 'package:olive_client/game_find_it.dart';
import 'package:olive_client/game_picker.dart';

Widget wrap(Widget child) => MaterialApp(home: child);

/// A fully deterministic stand-in for `Random`, matching
/// game_copy_pattern_test.dart's own helper of the same shape — cycles a
/// fixed sequence of indices rather than replaying a seeded `Random`'s call
/// order. `findScenes.length == 3` throughout, so a sequence of `[0, 1, 2]`
/// picks `yardScene` first and always has a next candidate that differs
/// from whatever `nextScene()` is asked to exclude.
class _SequenceRandom implements Random {
  _SequenceRandom(this._sequence);
  final List<int> _sequence;
  int _i = 0;
  @override
  int nextInt(int max) => _sequence[_i++ % _sequence.length];
  @override
  double nextDouble() => 0;
  @override
  bool nextBool() => false;
}

/// Every object tile's root widget is a `Tooltip` (see
/// `_ObjectTile.build()`) and nothing else inside the scene renders one —
/// a generic, content-agnostic way to count how many objects are actually
/// on screen without needing per-scene keys.
int _objectCount(WidgetTester t) => find
    .descendant(of: find.byKey(const Key('findItScene')), matching: find.byType(Tooltip))
    .evaluate()
    .length;

void main() {
  testWidgets('renders by name', (t) async {
    await t.pumpWidget(wrap(FindItScreen(random: _SequenceRandom(<int>[0]))));
    expect(find.text('Find it'), findsOneWidget);
  });

  group('the curated scenes — real content, real variety', () {
    test('at least three distinct scenes', () {
      expect(findScenes.length, greaterThanOrEqualTo(3));
    });

    test('scene ids are unique', () {
      expect(findScenes.map((s) => s.id).toSet().length, findScenes.length);
    });

    test('every scene has real, non-empty content — enough objects to scale by posture', () {
      for (final scene in findScenes) {
        expect(scene.title.trim(), isNotEmpty);
        expect(scene.objects.length, greaterThan(narrowObjectCount),
            reason: '${scene.id} must have MORE objects than the narrow-posture count, or wide '
                'posture would show nothing extra');
      }
    });

    test('object ids are unique within each scene', () {
      for (final scene in findScenes) {
        expect(scene.objects.map((o) => o.id).toSet().length, scene.objects.length, reason: scene.id);
      }
    });

    test('every object has a real, non-empty reference name with no stray whitespace', () {
      for (final scene in findScenes) {
        for (final o in scene.objects) {
          expect(o.name.trim(), isNotEmpty, reason: o.id);
          expect(o.name.trim(), o.name, reason: 'no stray leading/trailing whitespace: "${o.name}"');
        }
      }
    });

    test('every object position is genuinely inside the scene (0..1 on both axes)', () {
      for (final scene in findScenes) {
        for (final o in scene.objects) {
          expect(o.x, inInclusiveRange(0.0, 1.0), reason: o.id);
          expect(o.y, inInclusiveRange(0.0, 1.0), reason: o.id);
        }
      }
    });

    test('scenes are genuinely distinct — no two scenes share the same icon SET', () {
      final iconSets = findScenes.map((s) => s.objects.map((o) => o.icon).toSet()).toList();
      for (var i = 0; i < iconSets.length; i++) {
        for (var j = i + 1; j < iconSets.length; j++) {
          expect(iconSets[i].intersection(iconSets[j]), isEmpty,
              reason: '${findScenes[i].id} and ${findScenes[j].id} must not share icons');
        }
      }
    });

    test('scenes are genuinely distinct — no two scenes place their objects at the same '
        'positions (not the same layout re-skinned with different icons)', () {
      for (var i = 0; i < findScenes.length; i++) {
        for (var j = i + 1; j < findScenes.length; j++) {
          final posA = findScenes[i].objects.map((o) => '${o.x},${o.y}').toSet();
          final posB = findScenes[j].objects.map((o) => '${o.x},${o.y}').toSet();
          expect(posA, isNot(equals(posB)),
              reason: '${findScenes[i].id} and ${findScenes[j].id} must not share a layout');
        }
      }
    });
  });

  group('pure engine — visible-object scaling, found tracking, scene switching', () {
    test('visibleObjectsFor: a single column returns exactly narrowObjectCount objects', () {
      expect(visibleObjectsFor(yardScene, 1).length, narrowObjectCount);
    });

    test('visibleObjectsFor: two-plus columns returns the FULL curated set', () {
      expect(visibleObjectsFor(yardScene, 2).length, yardScene.objects.length);
      expect(visibleObjectsFor(yardScene, 3).length, yardScene.objects.length);
    });

    test('the narrow subset is a real PREFIX of the full curated list, not a different set', () {
      final narrow = visibleObjectsFor(yardScene, 1);
      final wide = visibleObjectsFor(yardScene, 2);
      expect(wide.sublist(0, narrow.length).map((o) => o.id), narrow.map((o) => o.id));
    });

    test('markFound adds exactly one id without disturbing the rest', () {
      final before = <String>{'a'};
      final after = markFound(before, 'b');
      expect(after, <String>{'a', 'b'});
      expect(before, <String>{'a'}, reason: 'the original set must be untouched (pure function)');
    });

    test('allFound is true only once every VISIBLE object is found', () {
      final visible = visibleObjectsFor(yardScene, 1);
      final allButOne = visible.skip(1).map((o) => o.id).toSet();
      expect(allFound(visible, allButOne), isFalse);
      expect(allFound(visible, visible.map((o) => o.id).toSet()), isTrue);
    });

    test('nextScene never returns the excluded scene', () {
      final random = _SequenceRandom(<int>[0, 1, 2]);
      var current = findScenes[0];
      for (var i = 0; i < 10; i++) {
        final next = nextScene(random, excludingId: current.id);
        expect(next.id, isNot(current.id));
        current = next;
      }
    });
  });

  group('the widget — found/not-found tracking is real', () {
    // Every test in this group pins a narrow (single-column) surface size —
    // the default flutter_test viewport is wide enough to render the FULL
    // curated set (see the "device posture" group below), which would make
    // narrowObjectCount the wrong expected denominator here. The count
    // MECHANIC under test is posture-independent; pinning the posture just
    // keeps the numbers in this group predictable.
    testWidgets('tapping an object marks it found and updates the live count', (t) async {
      await t.binding.setSurfaceSize(const Size(344, 882));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(FindItScreen(random: _SequenceRandom(<int>[0]))));
      await t.pumpAndSettle();
      expect(find.text('0 of $narrowObjectCount found'), findsOneWidget);

      await t.tap(find.byKey(Key('findObject-${yardScene.objects[0].id}')));
      await t.pumpAndSettle();
      expect(find.text('1 of $narrowObjectCount found'), findsOneWidget);
    });

    testWidgets('tapping an already-found object is a no-op — the count never over-counts', (t) async {
      await t.binding.setSurfaceSize(const Size(344, 882));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(FindItScreen(random: _SequenceRandom(<int>[0]))));
      await t.pumpAndSettle();
      final key = Key('findObject-${yardScene.objects[0].id}');
      await t.tap(find.byKey(key));
      await t.pumpAndSettle();
      expect(find.text('1 of $narrowObjectCount found'), findsOneWidget);

      await t.tap(find.byKey(key));
      await t.pumpAndSettle();
      expect(find.text('1 of $narrowObjectCount found'), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('"New scene" swaps to a genuinely different scene and resets found back to zero', (t) async {
      await t.binding.setSurfaceSize(const Size(344, 882));
      addTearDown(() => t.binding.setSurfaceSize(null));
      // [0, 1] -> initial scene index 0 (yard); nextScene excludes 'yard'
      // and the next draw (index 1, kitchen) already differs, so it picks
      // immediately with no looping.
      await t.pumpWidget(wrap(FindItScreen(random: _SequenceRandom(<int>[0, 1]))));
      await t.pumpAndSettle();
      expect(find.text(yardScene.title), findsOneWidget);

      await t.tap(find.byKey(Key('findObject-${yardScene.objects[0].id}')));
      await t.pumpAndSettle();
      expect(find.text('1 of $narrowObjectCount found'), findsOneWidget);

      await t.tap(find.text('New scene'));
      await t.pumpAndSettle();
      expect(find.text(yardScene.title), findsNothing);
      expect(find.text(kitchenScene.title), findsOneWidget);
      expect(find.text('0 of $narrowObjectCount found'), findsOneWidget);
    });
  });

  group('device posture changes REAL CONTENT here, not just layout', () {
    testWidgets('at foldCover width (344px) exactly narrowObjectCount objects render', (t) async {
      await t.binding.setSurfaceSize(const Size(344, 882));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(FindItScreen(random: _SequenceRandom(<int>[0]))));
      await t.pumpAndSettle();
      expect(_objectCount(t), narrowObjectCount);
      expect(t.takeException(), isNull);
    });

    testWidgets('at a wide posture (900px, 2+ columns) the FULL curated object count renders — '
        'a genuinely different NUMBER, not a resized layout of the same objects', (t) async {
      await t.binding.setSurfaceSize(const Size(900, 700));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(FindItScreen(random: _SequenceRandom(<int>[0]))));
      await t.pumpAndSettle();
      expect(_objectCount(t), yardScene.objects.length);
      expect(_objectCount(t), isNot(narrowObjectCount));
      expect(t.takeException(), isNull);
    });

    testWidgets('a large accessibility text scale degrades a nominally-wide device back to the '
        'narrow object count, exactly like columnsAt()\'s own effective-width math (§8.8)', (t) async {
      await t.binding.setSurfaceSize(const Size(800, 1280));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
          child: FindItScreen(random: _SequenceRandom(<int>[0])),
        ),
      ));
      await t.pumpAndSettle();
      expect(_objectCount(t), narrowObjectCount);
    });

    testWidgets('renders on the Fold5 cover-screen width (344 CSS px) without overflow', (t) async {
      await t.binding.setSurfaceSize(const Size(344, 882));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(FindItScreen(random: _SequenceRandom(<int>[0]))));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  });

  group('zero-text gameplay — icon-forward, per this file\'s own header', () {
    testWidgets('no object\'s reference name is ever shown as static on-screen label text', (t) async {
      await t.pumpWidget(wrap(FindItScreen(random: _SequenceRandom(<int>[0]))));
      await t.pumpAndSettle();
      for (final o in yardScene.objects) {
        expect(find.text(o.name), findsNothing, reason: o.name);
      }
    });
  });

  group('P2 — nothing here counts, ranks, or scores anything across rounds', () {
    testWidgets('none of the forbidden score/streak vocabulary ever appears', (t) async {
      await t.pumpWidget(wrap(FindItScreen(random: _SequenceRandom(<int>[0]))));
      await t.pumpAndSettle();
      await t.tap(find.byKey(Key('findObject-${yardScene.objects[0].id}')));
      await t.pumpAndSettle();
      for (final String word in <String>['score', 'streak', 'rank', 'best', 'high score', 'level up']) {
        expect(find.textContaining(RegExp(word, caseSensitive: false)), findsNothing, reason: word);
      }
    });

    testWidgets('no settings, price, or purchase affordance exists', (t) async {
      await t.pumpWidget(wrap(FindItScreen(random: _SequenceRandom(<int>[0]))));
      expect(find.byIcon(Icons.settings), findsNothing);
      expect(find.textContaining('\$'), findsNothing);
      expect(find.textContaining(RegExp('buy|purchase', caseSensitive: false)), findsNothing);
    });
  });

  group('real navigation reachability — child_home.dart\'s onPlay actually reaches this screen', () {
    testWidgets('Play together -> Find it -> the real FindItScreen', (t) async {
      await t.binding.setSurfaceSize(const Size(900, 2400));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(wrap(const ChildHome(
        childName: 'Ivy', presence: null, sleepsUntilHandover: 3, unreadCount: 0)));
      await t.tap(find.text('Play together'));
      await t.pumpAndSettle();
      expect(find.byType(GamePickerScreen), findsOneWidget);

      await t.scrollUntilVisible(find.text('Find it'), 200, scrollable: find.byType(Scrollable).first);
      await t.tap(find.text('Find it'));
      await t.pumpAndSettle();
      expect(find.byType(FindItScreen), findsOneWidget);
    });
  });
}
