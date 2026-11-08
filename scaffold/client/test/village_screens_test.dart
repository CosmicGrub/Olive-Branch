// OLIVE BRANCH — suite D's child screens: her people in pictures, a released
// story and the sibling shelf. Picture-first, 64dp targets, read-aloud through the
// seam, no counts, no role words of its own, nothing guardian-side reachable.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/access_scope.dart';
import 'package:olive_client/access_settings.dart';
import 'package:olive_client/family_structure_logic.dart';
import 'package:olive_client/family_structure_store.dart';
import 'package:olive_client/village_repositories.dart';
import 'package:olive_client/village_screens.dart';

import 'village_support.dart';

const FamilyStructure family = FamilyStructure(
  homes: <Home>[Home(id: 'h1', name: 'Mom\'s house', childSleeps: true), Home(id: 'h2', name: 'Dad\'s house', childSleeps: true)],
  people: <Person>[
    Person(id: 'p1', label: 'Mom', role: 'parent', homeId: 'h1', contact: <String>['live_call']),
    Person(id: 'p2', label: 'Jordan', role: 'step_parent', homeId: 'h1'),
    Person(id: 'p3', label: 'Dad', role: 'parent', homeId: 'h2'),
    Person(id: 'p4', label: 'Sitter Sam', role: 'sitter', homeId: 'h1'),
    Person(id: 'p5', label: 'Nana', role: 'relative', away: true),
  ],
);

FamilyChildSnapshot snap([FamilyStructure s = family]) =>
    FamilyChildSnapshot(view: deriveChildView(s, 't57', null, null, today: day));

Future<void> show(WidgetTester t, Widget w) async {
  await phone(t, w: 700, h: 2400);
  await t.pumpWidget(app(w));
  await t.pumpAndSettle();
}

void main() {
  group('her people, in pictures', () {
    testWidgets('grouped by home, with the names a guardian chose and no role words', (WidgetTester t) async {
      final VillageService s = freshVillage();
      await show(t, FamilyTreeScreen(service: s, snapshot: snap()));
      expect(find.text('Mom\'s house'), findsOneWidget);
      expect(find.text('Dad\'s house'), findsOneWidget);
      expect(find.text('Near and far'), findsOneWidget);
      for (final String n in <String>['Mom', 'Jordan', 'Dad', 'Nana']) {
        expect(find.text(n), findsOneWidget, reason: n);
      }
      expect(find.text('Sitter Sam'), findsNothing, reason: 'a background role is never in her people (F5)');
      for (final String role in <String>['step', 'parent', 'relative', 'sitter', 'guardian']) {
        expect(find.textContaining(role, findRichText: true), findsNothing, reason: 'no role word "$role" on her screen');
      }
    });

    testWidgets('a guardian-chosen face shows as a picture; the rest show their first letter', (WidgetTester t) async {
      final VillageService s = freshVillage();
      await s.setFace(guardian, 'p1', 'grandparent');
      await show(t, FamilyTreeScreen(service: s, snapshot: snap()));
      expect(find.descendant(of: find.byKey(const Key('face_p1')), matching: find.byIcon(Icons.elderly_outlined)), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('face_p3')), matching: find.text('D')), findsOneWidget);
    });

    testWidgets('each face is a real target of at least 64dp', (WidgetTester t) async {
      await show(t, FamilyTreeScreen(service: freshVillage(), snapshot: snap()));
      for (final String id in <String>['p1', 'p2', 'p3', 'p5']) {
        final Size z = t.getSize(find.byKey(Key('face_$id')));
        expect(z.height, greaterThanOrEqualTo(64), reason: id);
        expect(z.width, greaterThanOrEqualTo(64), reason: id);
      }
    });

    testWidgets('tapping a face says the name through the read-aloud seam; with no seam nothing is spoken and no speaker shows', (WidgetTester t) async {
      final List<String> said = <String>[];
      await show(t, FamilyTreeScreen(service: freshVillage(), snapshot: snap(), speak: (String x) async => said.add(x)));
      await t.tap(find.byKey(const Key('face_p3')));
      await t.pump();
      expect(said, <String>['Dad']);
      expect(find.byIcon(Icons.volume_up_outlined), findsWidgets);
      await show(t, FamilyTreeScreen(service: freshVillage(), snapshot: snap()));
      expect(find.byIcon(Icons.volume_up_outlined), findsNothing);
      await t.tap(find.byKey(const Key('face_p3')));
      await t.pump();
      expect(said.length, 1);
    });

    testWidgets('nobody yet: a quiet sentence, not an empty screen', (WidgetTester t) async {
      await show(t, FamilyTreeScreen(service: freshVillage(), snapshot: snap(const FamilyStructure())));
      expect(find.text('Nobody is here yet.'), findsOneWidget);
    });

    testWidgets('a face for someone no longer in the family is simply ignored', (WidgetTester t) async {
      final VillageService s = freshVillage();
      await s.setFace(guardian, 'gone', 'friend');
      await show(t, FamilyTreeScreen(service: s, snapshot: snap()));
      expect(find.byKey(const Key('face_gone')), findsNothing);
    });

    testWidgets('at 2x text it still fits and nothing overflows', (WidgetTester t) async {
      await phone(t, w: 344, h: 1800);
      await t.pumpWidget(app(FamilyTreeScreen(service: freshVillage(), snapshot: snap()), textScale: 2.0));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  });

  group('a story a guardian released', () {
    Future<VillageService> withStory() async {
      final VillageService s = freshVillage();
      await s.saveStory(guardian, sampleStory());
      await s.releaseStory(guardian, 's1');
      return s;
    }

    testWidgets('one page at a time: picture, big text, Back and Next, and a calm All done', (WidgetTester t) async {
      final VillageService s = await withStory();
      await show(t, WelcomeStoryScreen(service: s, storyId: 's1'));
      expect(find.text('We open the door.'), findsOneWidget);
      expect(find.byKey(const Key('storyBack')), findsNothing);
      await t.tap(find.byKey(const Key('storyNext')));
      await t.pumpAndSettle();
      expect(find.text('We eat together.'), findsOneWidget);
      expect(find.byKey(const Key('storyNext')), findsNothing);
      expect(find.byKey(const Key('storyDone')), findsOneWidget);
      await t.tap(find.byKey(const Key('storyBack')));
      await t.pumpAndSettle();
      expect(find.text('We open the door.'), findsOneWidget);
    });

    testWidgets('no "page 2 of 6", no progress bar, no star: no counter of any kind (P2)', (WidgetTester t) async {
      final VillageService s = await withStory();
      await show(t, WelcomeStoryScreen(service: s, storyId: 's1'));
      expect(find.textContaining(RegExp(r'\d')), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byIcon(Icons.star), findsNothing);
    });

    testWidgets('Back, Next and All done are at least 64dp; the page text is read aloud', (WidgetTester t) async {
      final List<String> said = <String>[];
      final VillageService s = await withStory();
      await show(t, WelcomeStoryScreen(service: s, storyId: 's1', speak: (String x) async => said.add(x)));
      expect(heightOf(t, find.byKey(const Key('storyNext'))), greaterThanOrEqualTo(64));
      await t.tap(find.byIcon(Icons.volume_up_outlined).first);
      expect(said, <String>['We open the door.']);
      await t.tap(find.byKey(const Key('storyNext')));
      await t.pumpAndSettle();
      expect(heightOf(t, find.byKey(const Key('storyDone'))), greaterThanOrEqualTo(64));
      expect(heightOf(t, find.byKey(const Key('storyBack'))), greaterThanOrEqualTo(64));
    });

    testWidgets('All done leaves the story', (WidgetTester t) async {
      final VillageService s = await withStory();
      await t.pumpWidget(app(Builder(builder: (BuildContext c) => TextButton(
          key: const Key('open'), onPressed: () => Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => WelcomeStoryScreen(service: s, storyId: 's1'))),
          child: const Text('go')))));
      await t.tap(find.byKey(const Key('open')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('storyNext')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('storyDone')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('open')), findsOneWidget);
    });

    testWidgets('a HELD story, an unknown id, and a story with the suite off all say "not here" and show no content', (WidgetTester t) async {
      final VillageService s = freshVillage();
      await s.saveStory(guardian, sampleStory(id: 'held'));
      await show(t, WelcomeStoryScreen(service: s, storyId: 'held'));
      expect(find.text('This story is not here.'), findsOneWidget);
      expect(find.text('We open the door.'), findsNothing);
      await show(t, WelcomeStoryScreen(service: s, storyId: 'nope'));
      expect(find.text('This story is not here.'), findsOneWidget);
      final VillageService on = await withStory();
      await on.setSuite(guardian, false);
      await show(t, WelcomeStoryScreen(service: on, storyId: 's1'));
      expect(find.text('This story is not here.'), findsOneWidget);
    });

    testWidgets('a story a guardian holds again disappears from her screen', (WidgetTester t) async {
      final VillageService s = await withStory();
      await s.holdStory(guardian, 's1');
      await show(t, WelcomeStoryScreen(service: s, storyId: 's1'));
      expect(find.text('We open the door.'), findsNothing);
    });
  });

  group('the sibling shelf', () {
    Future<VillageService> withShelf() async {
      final VillageService s = freshVillage();
      await s.saveSiblings(guardian, sampleSiblings());
      return s;
    }

    testWidgets('shows each sibling by the name a guardian typed, with a big Leave a picture button', (WidgetTester t) async {
      await show(t, SiblingSpaceScreen(service: await withShelf()));
      expect(find.text('Leo'), findsOneWidget);
      expect(find.text('Mia'), findsOneWidget);
      expect(heightOf(t, find.byKey(const Key('shelfLeave_b1'))), greaterThanOrEqualTo(64));
    });

    testWidgets('she leaves a picture from the kit and it appears on that sibling\'s shelf only', (WidgetTester t) async {
      final VillageService s = await withShelf();
      await show(t, SiblingSpaceScreen(service: s));
      await t.tap(find.byKey(const Key('shelfLeave_b1')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('shelfPick_teddy')));
      await t.pumpAndSettle();
      expect((await s.shelf(ivy)).notesFor('b1').single.picture, 'teddy');
      expect((await s.shelf(ivy)).notesFor('b2'), isEmpty);
      expect(find.descendant(of: find.byKey(const Key('shelfSlot_b1')), matching: find.byIcon(Icons.smart_toy_outlined)), findsOneWidget);
    });

    testWidgets('the picker offers only the kit: no worry picture, no routine picture', (WidgetTester t) async {
      final VillageService s = await withShelf();
      await show(t, SiblingSpaceScreen(service: s));
      await t.tap(find.byKey(const Key('shelfLeave_b1')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('shelfPick_teddy')), findsOneWidget);
      expect(find.byKey(const Key('shelfPick_sunny')), findsOneWidget);
      expect(find.byKey(const Key('shelfPick_worry-dark')), findsNothing);
      expect(find.byKey(const Key('shelfPick_bath')), findsNothing);
      await t.tap(find.text('Not now'));
      await t.pumpAndSettle();
      expect((await s.shelf(ivy)).notes, isEmpty);
    });

    testWidgets('taking a picture down asks first; Keep it keeps it and Take it down removes it', (WidgetTester t) async {
      final VillageService s = await withShelf();
      await s.leavePicture(ivy, 'b1', 'teddy');
      await show(t, SiblingSpaceScreen(service: s));
      final String id = (await s.shelf(ivy)).notes.single.id;
      await t.tap(find.byKey(Key('shelfNote_$id')));
      await t.pumpAndSettle();
      expect(heightOf(t, find.byKey(const Key('shelfTakeDown'))), greaterThanOrEqualTo(64));
      await t.tap(find.byKey(const Key('shelfKeep')));
      await t.pumpAndSettle();
      expect((await s.shelf(ivy)).notes.length, 1);
      await t.tap(find.byKey(Key('shelfNote_$id')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('shelfTakeDown')));
      await t.pumpAndSettle();
      expect((await s.shelf(ivy)).notes, isEmpty);
    });

    testWidgets('it never says how many pictures it holds, who left one or when (P2)', (WidgetTester t) async {
      final VillageService s = await withShelf();
      for (int i = 0; i < 4; i++) {
        await s.leavePicture(ivy, 'b1', 'teddy');
      }
      await show(t, SiblingSpaceScreen(service: s));
      expect(find.textContaining(RegExp(r'\d')), findsNothing);
      expect(find.textContaining(RegExp('from|new|unread|ago', caseSensitive: false)), findsNothing);
    });

    testWidgets('not set up yet: a quiet sentence', (WidgetTester t) async {
      await show(t, SiblingSpaceScreen(service: freshVillage()));
      expect(find.text('Your grown-up has not set this up yet.'), findsOneWidget);
    });

    testWidgets('with the suite off the shelf shows nothing and a picture cannot be left', (WidgetTester t) async {
      final VillageService s = await withShelf();
      await s.setSuite(guardian, false);
      await show(t, SiblingSpaceScreen(service: s));
      expect(find.text('Leo'), findsNothing);
      expect(find.text('Your grown-up has not set this up yet.'), findsOneWidget);
    });

    testWidgets('leaving a picture gives a visual cue that fades by default', (WidgetTester t) async {
      await show(t, SiblingSpaceScreen(service: await withShelf()));
      await t.tap(find.byKey(const Key('shelfLeave_b1')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('shelfPick_owl')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('A picture is on the shelf'), findsOneWidget);
      expect(find.byType(MaterialBanner), findsNothing);
      await t.pump(const Duration(seconds: 5));
      await t.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('with "alerts she can see" on, the cue is a banner that stays until she taps OK', (WidgetTester t) async {
      final AccessController c = AccessController(repository: MemoryAccessRepository(const AccessSettings(visualAlerts: true)));
      await c.load();
      await phone(t, w: 700, h: 2400);
      await t.pumpWidget(AccessScope(controller: c, child: app(SiblingSpaceScreen(service: await withShelf()))));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('shelfLeave_b1')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('shelfPick_owl')));
      await t.pumpAndSettle();
      await t.pump(const Duration(seconds: 10));
      expect(find.byType(MaterialBanner), findsOneWidget, reason: 'still there after ten seconds');
      expect(find.text('A picture is on the shelf'), findsOneWidget);
      expect(heightOf(t, find.byKey(const Key('visualAlertOk'))), greaterThanOrEqualTo(64));
      await t.tap(find.byKey(const Key('visualAlertOk')));
      await t.pumpAndSettle();
      expect(find.byType(MaterialBanner), findsNothing);
    });
  });

  group('the child shell reaches no guardian side', () {
    String stripped(String p) => File(p).readAsStringSync().replaceAll(RegExp(r'//.*'), '');

    test('the child files never import the guardian editors, the passes or Compass', () {
      for (final String f in <String>['lib/village_screens.dart', 'lib/village_sections.dart', 'lib/visual_alert.dart']) {
        final String src = stripped(f);
        for (final String banned in <String>[
          'village_guardian_screens', 'compass_screens', 'compass_repositories', 'loadPasses', 'SitterPass', 'SchoolBridge',
          'GrandCorner', 'loadForGuardian', 'saveStory', 'releaseStory',
        ]) {
          expect(src.contains(banned), isFalse, reason: '$f must not reference $banned');
        }
      }
    });
  });
}
