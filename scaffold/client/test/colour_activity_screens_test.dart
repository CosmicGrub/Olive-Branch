// OLIVE BRANCH — the four colour activities as real screens (P2: no scores,
// streaks, timers or counters; nothing fails).
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/colour_activities_logic.dart';
import 'package:olive_client/colour_critter_screen.dart';
import 'package:olive_client/colour_foods.dart';
import 'package:olive_client/colour_sort_screen.dart';
import 'package:olive_client/palette_logic.dart';
import 'package:olive_client/path_code_screen.dart';
import 'package:olive_client/pixel_garden_screen.dart';

final Swatch sea = swatchFor('sea')!;

Future<void> big(WidgetTester t) async {
  t.view.physicalSize = const Size(900, 2200);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

Widget app(Widget home) => MaterialApp(home: home);

void main() {
  group('Colour sort', () {
    testWidgets('states the task in her colour, with its pictures and three baskets', (t) async {
      await big(t);
      await t.pumpWidget(app(ColourSortScreen(swatch: sea, style: 'paper')));
      expect(find.text('Let’s find things that are sea blue.'), findsOneWidget);
      expect(find.byKey(const Key('sortItem0')), findsOneWidget);
      expect(find.byKey(const Key('sortItem6')), findsOneWidget);
      expect(find.byKey(const Key('basket_fruit')), findsOneWidget);
      expect(find.byKey(const Key('basket_veg')), findsOneWidget);
      expect(find.byKey(const Key('basket_animals')), findsOneWidget);
    });

    testWidgets('a miss wobbles back with no buzzer words; the right basket then takes it', (t) async {
      await big(t);
      await t.pumpWidget(app(ColourSortScreen(swatch: sea, style: 'sticker')));
      await t.tap(find.byKey(const Key('sortItem0')));
      await t.pump();
      expect(find.text('Now tap a basket.'), findsOneWidget);
      await t.tap(find.byKey(const Key('basket_animals')));
      await t.pump();
      final msg = t.widget<Text>(find.byKey(const Key('sortMessage'))).data!;
      expect(msg, startsWith('Not quite'));
      expect(msg.toLowerCase(), isNot(contains('wrong')));
      expect(find.byKey(const Key('sortItem0')), findsOneWidget, reason: 'it is still there');
      await t.tap(find.byKey(const Key('basket_fruit')));
      await t.pump();
      expect(t.widget<Text>(find.byKey(const Key('sortMessage'))).data, startsWith('Yes!'));
      expect(find.byKey(const Key('sortItem0')), findsNothing, reason: 'it hopped into the basket');
    });

    testWidgets('sorting everything ends quietly with "All sorted." and no tally', (t) async {
      await big(t);
      await t.pumpWidget(app(ColourSortScreen(swatch: sea, style: 'crayon')));
      final pool = sortPool('sea');
      for (var i = 0; i < pool.length; i++) {
        await t.tap(find.byKey(Key('sortItem$i')));
        await t.pump();
        await t.tap(find.byKey(Key('basket_${pool[i].group}')));
        await t.pump();
      }
      expect(find.text('All sorted.'), findsOneWidget);
      expect(find.textContaining(RegExp(r'\d+ of \d+|score|points', caseSensitive: false)), findsNothing);
    });

    testWidgets('"All done" is always there and leaves', (t) async {
      await big(t);
      await t.pumpWidget(app(Builder(builder: (c) => TextButton(
        onPressed: () => Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => ColourSortScreen(swatch: sea, style: 'line'))),
        child: const Text('go')))));
      await t.tap(find.text('go'));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('sortDone')), findsOneWidget);
      await t.tap(find.byKey(const Key('sortDone')));
      await t.pumpAndSettle();
      expect(find.text('go'), findsOneWidget);
    });

    testWidgets('a storybook thing is labelled pretend', (t) async {
      await big(t);
      await t.pumpWidget(app(ColourSortScreen(swatch: swatchFor('grape')!, style: 'paper')));
      expect(find.text('a pretend purple elephant'), findsOneWidget);
    });

    testWidgets('a guardian can leave a group out', (t) async {
      await big(t);
      await t.pumpWidget(app(ColourSortScreen(swatch: sea, style: 'paper', groups: const ['animals'])));
      expect(find.byKey(const Key('basket_fruit')), findsNothing);
      expect(find.byKey(const Key('basket_animals')), findsOneWidget);
    });
  });

  group('Path code', () {
    Future<void> tapAdd(WidgetTester t, Dir d) async {
      await t.tap(find.byKey(Key('add_${d.name}')));
      await t.pump();
    }

    Widget screen({int age = 6}) => app(PathCodeScreen(swatch: sea, style: 'paper', age: age, stepDuration: Duration.zero));

    testWidgets('three arrows to the right reach the food, and the program is shown back as arrows', (t) async {
      await big(t);
      await t.pumpWidget(screen());
      for (var i = 0; i < 3; i++) {
        await tapAdd(t, Dir.right);
      }
      await t.tap(find.byKey(const Key('runPath')));
      await t.pumpAndSettle();
      expect(t.widget<Text>(find.byKey(const Key('pathMessage'))).data, contains('reached'));
      expect(find.text('Your program: → → →'), findsOneWidget);
      expect(find.byKey(const Key('nextPath')), findsOneWidget);
    });

    testWidgets('an unfinished program is just short: nothing fails, the blocks stay', (t) async {
      await big(t);
      await t.pumpWidget(screen());
      await tapAdd(t, Dir.right);
      await t.tap(find.byKey(const Key('runPath')));
      await t.pumpAndSettle();
      expect(t.widget<Text>(find.byKey(const Key('pathMessage'))).data, 'Not there yet. Add another arrow.');
      expect(find.byType(Chip), findsOneWidget);
      expect(find.byKey(const Key('nextPath')), findsNothing);
    });

    testWidgets('the edge is gentle', (t) async {
      await big(t);
      await t.pumpWidget(screen());
      await tapAdd(t, Dir.left);
      await t.tap(find.byKey(const Key('runPath')));
      await t.pumpAndSettle();
      expect(t.widget<Text>(find.byKey(const Key('pathMessage'))).data, contains('stays on the path'));
    });

    testWidgets('the repeat block opens at 8, not before', (t) async {
      await big(t);
      await t.pumpWidget(screen(age: 7));
      expect(find.byKey(const Key('repeatBlock')), findsNothing);
      await t.pumpWidget(screen(age: 8));
      expect(find.byKey(const Key('repeatBlock')), findsOneWidget);
    });

    testWidgets('at 8 the repeat block runs an arrow several times', (t) async {
      await big(t);
      await t.pumpWidget(screen(age: 8));
      await tapAdd(t, Dir.right);
      await t.tap(find.byKey(const Key('repeatBlock'))); // x2
      await t.tap(find.byKey(const Key('repeatBlock'))); // x3
      await t.pump();
      expect(find.text('→×3'), findsOneWidget);
      await t.tap(find.byKey(const Key('runPath')));
      await t.pumpAndSettle();
      expect(t.widget<Text>(find.byKey(const Key('pathMessage'))).data, contains('reached'));
    });

    testWidgets('clear empties the program; another path moves on without a level number', (t) async {
      await big(t);
      await t.pumpWidget(screen());
      for (var i = 0; i < 3; i++) {
        await tapAdd(t, Dir.right);
      }
      await t.tap(find.byKey(const Key('clearPath')));
      await t.pump();
      expect(find.text('No arrows yet.'), findsOneWidget);
      for (var i = 0; i < 3; i++) {
        await tapAdd(t, Dir.right);
      }
      await t.tap(find.byKey(const Key('runPath')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('nextPath')));
      await t.pump();
      expect(find.textContaining(RegExp('level', caseSensitive: false)), findsNothing);
      expect(find.byKey(const Key('cell_0_3')), findsOneWidget, reason: 'the next, taller path');
    });

    testWidgets('the program has a bounded length', (t) async {
      await big(t);
      await t.pumpWidget(screen());
      for (var i = 0; i < 12; i++) {
        await tapAdd(t, Dir.up);
      }
      expect(find.byType(Chip), findsNWidgets(pathLevels[0].maxBlocks));
    });
  });

  group('Colour critter', () {
    Widget screen({List<String>? allowed}) => app(ColourCritterScreen(
      swatch: sea, allowedStyles: allowed ?? const ['paper', 'sticker', 'line'], initialStyle: 'sticker'));

    testWidgets('tapping a part fills it, and undo is one tap', (t) async {
      await big(t);
      await t.pumpWidget(screen());
      OutlinedButton undo() => t.widget<OutlinedButton>(find.byKey(const Key('critterUndo')));
      expect(undo().onPressed, isNull);
      await t.tapAt(t.getCenter(find.byKey(const Key('critterCanvas'))));
      await t.pump();
      expect(undo().onPressed, isNotNull);
      await t.tap(find.byKey(const Key('critterUndo')));
      await t.pump();
      expect(undo().onPressed, isNull);
    });

    testWidgets('she can pick an animal from today’s list', (t) async {
      await big(t);
      await t.pumpWidget(screen());
      expect(find.byKey(const Key('animal0')), findsOneWidget);
      expect(find.byKey(const Key('animal2')), findsOneWidget);
      await t.tap(find.byKey(const Key('animal1')));
      await t.pump();
      expect(t.widget<ChoiceChip>(find.byKey(const Key('animal1'))).selected, isTrue);
    });

    testWidgets('only the styles her guardian allows are offered', (t) async {
      await big(t);
      await t.pumpWidget(screen());
      expect(find.byKey(const Key('style_paper')), findsOneWidget);
      expect(find.byKey(const Key('style_sticker')), findsOneWidget);
      expect(find.byKey(const Key('style_pixel')), findsNothing);
      expect(find.byKey(const Key('style_felt')), findsNothing);
      expect(t.widget<ChoiceChip>(find.byKey(const Key('style_sticker'))).selected, isTrue);
      await t.tap(find.byKey(const Key('style_line')));
      await t.pump();
      expect(t.widget<ChoiceChip>(find.byKey(const Key('style_line'))).selected, isTrue);
    });

    testWidgets('three tints: lighter, today’s colour, darker', (t) async {
      await big(t);
      await t.pumpWidget(screen());
      await t.tap(find.byKey(const Key('tint2')));
      await t.pump();
      expect(find.byKey(const Key('tint0')), findsOneWidget);
      expect(find.byKey(const Key('tint1')), findsOneWidget);
    });

    testWidgets('a colour with no animals still gets one to colour', (t) async {
      await big(t);
      await t.pumpWidget(app(ColourCritterScreen(swatch: swatchFor('mint')!, allowedStyles: const ['paper'], initialStyle: 'paper')));
      expect(find.byKey(const Key('critterCanvas')), findsOneWidget);
    });
  });

  group('Pixel garden', () {
    Color? cell(WidgetTester t, int x, int y) =>
        t.widget<Container>(find.descendant(of: find.byKey(Key('px_${x}_$y')), matching: find.byType(Container))).color;

    testWidgets('closed under 8, in kind words', (t) async {
      await big(t);
      await t.pumpWidget(app(PixelGardenScreen(swatch: sea, age: 7, codeActivities: true)));
      expect(find.text('The pixel garden opens at 8.'), findsOneWidget);
      expect(find.byKey(const Key('px_0_0')), findsNothing);
    });

    testWidgets('resting when the guardian has coding activities off', (t) async {
      await big(t);
      await t.pumpWidget(app(PixelGardenScreen(swatch: sea, age: 9, codeActivities: false)));
      expect(find.text('The pixel garden is resting for now.'), findsOneWidget);
    });

    testWidgets('at 8 a tap plants, a second tap lifts it again', (t) async {
      await big(t);
      await t.pumpWidget(app(PixelGardenScreen(swatch: sea, age: 8, codeActivities: true)));
      final empty = cell(t, 2, 2);
      await t.tap(find.byKey(const Key('px_2_2')));
      await t.pump();
      expect(cell(t, 2, 2), sea.color);
      await t.tap(find.byKey(const Key('px_2_2')));
      await t.pump();
      expect(cell(t, 2, 2), empty);
    });

    testWidgets('the mirror switch copies across the middle', (t) async {
      await big(t);
      await t.pumpWidget(app(PixelGardenScreen(swatch: sea, age: 9, codeActivities: true)));
      await t.tap(find.byKey(const Key('mirrorSwitch')));
      await t.pump();
      await t.tap(find.byKey(const Key('px_1_3')));
      await t.pump();
      expect(cell(t, 6, 3), sea.color);
    });

    testWidgets('the repeat stamp copies the pattern along the row', (t) async {
      await big(t);
      await t.pumpWidget(app(PixelGardenScreen(swatch: sea, age: 9, codeActivities: true)));
      await t.tap(find.byKey(const Key('px_0_0')));
      await t.pump();
      await t.tap(find.byKey(const Key('ptint3')));
      await t.tap(find.byKey(const Key('px_1_0')));
      await t.pump();
      await t.tap(find.byKey(const Key('stampChip')));
      await t.pump();
      expect(find.text('Tap where your pattern ends.'), findsOneWidget);
      await t.tap(find.byKey(const Key('px_1_0')));
      await t.pump();
      expect(cell(t, 2, 0), sea.color);
      expect(cell(t, 3, 0), isNot(sea.color));
      expect(cell(t, 7, 0), isNot(sea.color));
      expect(find.text('Tap squares to plant.'), findsOneWidget);
    });

    testWidgets('clear empties the garden', (t) async {
      await big(t);
      await t.pumpWidget(app(PixelGardenScreen(swatch: sea, age: 10, codeActivities: true)));
      final empty = cell(t, 4, 4);
      await t.tap(find.byKey(const Key('px_4_4')));
      await t.pump();
      await t.tap(find.byKey(const Key('pixelClear')));
      await t.pump();
      expect(cell(t, 4, 4), empty);
    });
  });

  group('P2: nothing on these screens can be added up', () {
    final files = ['colour_sort_screen', 'path_code_screen', 'colour_critter_screen', 'pixel_garden_screen', 'her_colour_home'];
    final banned = RegExp(r'\b(score|streak|points?|stars?|badge|reward|level|timer|wrong|incorrect|try again|you failed|well done|good job)\b',
        caseSensitive: false);
    for (final f in files) {
      test('$f has no scoring, timer or correction words in anything she can read', () {
        final src = File('lib/$f.dart').readAsStringSync();
        final literals = RegExp(r"'([^'\\]|\\.)*'").allMatches(src.replaceAll(RegExp(r'//.*'), '')).map((m) => m[0]!);
        final bad = [for (final l in literals) if (!l.startsWith("'Key") && banned.hasMatch(l)) l];
        expect(bad, isEmpty);
      });
    }
  });
}
