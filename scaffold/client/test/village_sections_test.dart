// OLIVE BRANCH — the Village tiles in the child's More hub: they follow the
// family-structure model (age band, More hub, her people), the guardian's switch
// and what has been authored AND released, use the shared TieredTile, and the child
// shell still reaches nothing guardian-side.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/child_more.dart';
import 'package:olive_client/family_structure_logic.dart';
import 'package:olive_client/family_structure_store.dart';
import 'package:olive_client/tiered_tile.dart';
import 'package:olive_client/village_repositories.dart';
import 'package:olive_client/village_screens.dart';

import 'village_support.dart';

const FamilyStructure twoHomes = FamilyStructure(
  homes: <Home>[Home(id: 'h1', name: 'Mom\'s', childSleeps: true), Home(id: 'h2', name: 'Dad\'s', childSleeps: true)],
  people: <Person>[
    Person(id: 'p1', label: 'Mom', role: 'parent', homeId: 'h1'),
    Person(id: 'p2', label: 'Dad', role: 'parent', homeId: 'h2'),
  ],
);

FamilyChildSnapshot snap(FamilyStructure s, String band, {Map<String, bool>? suites}) =>
    FamilyChildSnapshot(view: deriveChildView(s, band, suites, null, today: day));

Future<VillageService> authored() async {
  final VillageService s = freshVillage();
  await s.saveStory(guardian, sampleStory(id: 'held', title: 'Held one'));
  await s.saveStory(guardian, sampleStory(id: 'out', title: 'A story for me'));
  await s.releaseStory(guardian, 'out');
  await s.saveSiblings(guardian, sampleSiblings());
  await s.saveSitterPass(guardian, sampleSitter());
  await s.saveGrandCorner(guardian, sampleGrand());
  return s;
}

Future<void> more(WidgetTester t, VillageService s, {FamilyChildSnapshot? family, int age = 6, double scale = 1.0, double w = 700}) async {
  await phone(t, w: w, h: 3200);
  await t.pumpWidget(app(ChildMoreScreen(childName: 'Ivy', childAge: age, village: s, family: family), textScale: scale));
  await t.pumpAndSettle();
}

void main() {
  group('what shows', () {
    testWidgets('a released story, the shelf and her faces show; a held story does not', (WidgetTester t) async {
      await more(t, await authored(), family: snap(twoHomes, 't57'));
      expect(find.text('MY VILLAGE'), findsOneWidget);
      expect(find.byKey(const Key('vilTile_tree')), findsOneWidget);
      expect(find.byKey(const Key('vilTile_shelf')), findsOneWidget);
      expect(find.byKey(const Key('vilTile_story_out')), findsOneWidget);
      expect(find.byKey(const Key('vilTile_story_held')), findsNothing);
      expect(find.text('A story for me'), findsOneWidget);
      expect(find.text('Held one'), findsNothing);
    });

    testWidgets('the sitter pass, the school summary and the grandparent page have no tile at all', (WidgetTester t) async {
      await more(t, await authored(), family: snap(twoHomes, 't57'));
      expect(find.textContaining(RegExp('Sitter pass|School summary|Grandparent|Friday evening|Cashews|Read to Ivy|Oak Primary')), findsNothing);
    });

    testWidgets('nothing authored, nothing shown: no empty section', (WidgetTester t) async {
      await more(t, freshVillage(), family: snap(const FamilyStructure(), 't57'));
      expect(find.text('MY VILLAGE'), findsNothing);
    });

    testWidgets('with no family snapshot her people stay off but a released story and the shelf still show (fails closed to five)', (WidgetTester t) async {
      await more(t, await authored());
      expect(find.byKey(const Key('vilTile_tree')), findsNothing);
      expect(find.byKey(const Key('vilTile_shelf')), findsOneWidget);
      expect(find.byKey(const Key('vilTile_story_out')), findsOneWidget);
    });

    testWidgets('a child under five sees none of it, whatever is authored', (WidgetTester t) async {
      await more(t, await authored(), family: snap(twoHomes, 't34'), age: 4);
      expect(find.text('MY VILLAGE'), findsNothing);
      expect(find.byType(TieredTile), findsNothing);
    });

    testWidgets('the guardian\'s switch hides everything, and flipping it back shows it again', (WidgetTester t) async {
      final VillageService s = await authored();
      await s.setSuite(guardian, false);
      await more(t, s, family: snap(twoHomes, 't57'));
      expect(find.text('MY VILLAGE'), findsNothing);
      await s.setSuite(guardian, true);
      await more(t, s, family: snap(twoHomes, 't57'));
      expect(find.text('MY VILLAGE'), findsOneWidget);
    });

    testWidgets('the model\'s own people switch removes her faces and leaves the rest', (WidgetTester t) async {
      await more(t, await authored(), family: snap(twoHomes, 't57', suites: <String, bool>{'myPeople': false}));
      expect(find.byKey(const Key('vilTile_tree')), findsNothing);
      expect(find.byKey(const Key('vilTile_shelf')), findsOneWidget);
    });

    testWidgets('a released story un-released disappears the next time she opens More', (WidgetTester t) async {
      final VillageService s = await authored();
      await more(t, s, family: snap(twoHomes, 't57'));
      expect(find.byKey(const Key('vilTile_story_out')), findsOneWidget);
      await s.holdStory(guardian, 'out');
      await more(t, s, family: snap(twoHomes, 't57'));
      expect(find.byKey(const Key('vilTile_story_out')), findsNothing);
    });
  });

  group('the tiles', () {
    testWidgets('are TieredTiles of at least 64dp, and open their screens', (WidgetTester t) async {
      final VillageService s = await authored();
      await more(t, s, family: snap(twoHomes, 't57'));
      for (final String k in <String>['vilTile_tree', 'vilTile_shelf', 'vilTile_story_out']) {
        expect(find.byKey(Key(k)), findsOneWidget);
        expect(t.getSize(find.byKey(Key(k))).height, greaterThanOrEqualTo(64), reason: k);
      }
      expect(t.widget<Widget>(find.byKey(const Key('vilTile_shelf'))), isA<TieredTile>());
      await t.ensureVisible(find.byKey(const Key('vilTile_shelf')));
      await t.tap(find.byKey(const Key('vilTile_shelf')));
      await t.pumpAndSettle();
      expect(find.byType(SiblingSpaceScreen), findsOneWidget);
      await t.pageBack();
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const Key('vilTile_story_out')));
      await t.tap(find.byKey(const Key('vilTile_story_out')));
      await t.pumpAndSettle();
      expect(find.byType(WelcomeStoryScreen), findsOneWidget);
      await t.pageBack();
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const Key('vilTile_tree')));
      await t.tap(find.byKey(const Key('vilTile_tree')));
      await t.pumpAndSettle();
      expect(find.byType(FamilyTreeScreen), findsOneWidget);
    });

    testWidgets('at large text (1.6x) and a 344dp cover screen every label fits, one tile to a row', (WidgetTester t) async {
      await more(t, await authored(), family: snap(twoHomes, 't57'), scale: 2.0, w: 344);
      expect(t.takeException(), isNull);
      final double a = t.getTopLeft(find.byKey(const Key('vilTile_tree'))).dy;
      final double b = t.getTopLeft(find.byKey(const Key('vilTile_story_out'))).dy;
      expect(a == b, isFalse, reason: 'one to a row at large text');
    });

    testWidgets('a long story title wraps rather than overflows', (WidgetTester t) async {
      final VillageService s = freshVillage();
      await s.saveStory(guardian, sampleStory(title: 'A very long name for a story'));
      await s.releaseStory(guardian, 's1');
      await more(t, s, scale: 2.0, w: 344);
      expect(t.takeException(), isNull);
      expect(find.byKey(const Key('vilTile_story_s1')), findsOneWidget);
    });
  });

  test('the child shell wires Village in and still reaches nothing guardian-side', () {
    String stripped(String p) => File(p).readAsStringSync().replaceAll(RegExp(r'//.*'), '');
    final String more = stripped('lib/child_more.dart');
    expect(more.contains('VillageSections('), isTrue);
    for (final String banned in <String>['village_guardian_screens', 'compass_screens', 'SitterPassEditorScreen', 'PassPageScreen', 'GrandCornerScreen']) {
      expect(more.contains(banned), isFalse, reason: banned);
      expect(stripped('lib/child_home.dart').contains(banned), isFalse, reason: banned);
    }
  });

  test('every new client file says UNVERIFIED -> verified by CI in its header', () {
    for (final String f in <String>[
      'village_logic', 'village_repositories', 'village_screens', 'village_sections', 'village_guardian_screens',
      'compass_logic', 'compass_repositories', 'compass_screens', 'visual_alert',
    ]) {
      final String head = File('lib/$f.dart').readAsLinesSync().take(8).join('\n');
      expect(head, contains('UNVERIFIED'), reason: f);
      expect(head, contains('verified by CI'), reason: f);
    }
  });
}

