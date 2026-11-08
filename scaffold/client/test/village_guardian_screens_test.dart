// OLIVE BRANCH — the guardian's side of suite D: the hub, every editor and the
// one-page views, and the Settings entry point. Every deny path is a real
// assertion: a child principal cannot save, nothing is written for a guardian, bad
// content is refused in words, and nothing here can reach the network.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/guardian_more.dart';
import 'package:olive_client/village_guardian_screens.dart';
import 'package:olive_client/village_logic.dart';
import 'package:olive_client/village_repositories.dart';

import 'village_support.dart';

Future<void> big(WidgetTester t) => phone(t, w: 700, h: 3000);

Future<void> show(WidgetTester t, Widget w) async {
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

Future<void> tapKey(WidgetTester t, String key) async {
  await t.ensureVisible(find.byKey(Key(key)));
  await t.tap(find.byKey(Key(key)));
  await t.pumpAndSettle();
}

Future<void> typeKey(WidgetTester t, String key, String text) async {
  await t.ensureVisible(find.byKey(Key(key)));
  await t.enterText(find.byKey(Key(key)), text);
  await t.pump();
}

void main() {
  group('the hub', () {
    testWidgets('says plainly it is on this device only, never shared, nobody contacted', (WidgetTester t) async {
      await big(t);
      await show(t, VillageGuardianHubScreen(childName: 'Ivy', service: freshVillage(), principal: guardian, yearsOld: 6));
      expect(find.textContaining('Kept on this device only'), findsOneWidget);
      expect(find.textContaining('not shared with Ivy\'s other home yet'), findsOneWidget);
      expect(find.textContaining('No school, sitter or relative is ever contacted'), findsOneWidget);
      for (final String k in <String>['rowGrand', 'rowFaces', 'rowStories', 'rowShelf', 'rowSitter', 'rowSchool']) {
        expect(find.byKey(Key(k)), findsOneWidget, reason: k);
      }
    });

    testWidgets('a child under five is told her side does not show yet; an unknown age fails closed to five', (WidgetTester t) async {
      await big(t);
      await show(t, VillageGuardianHubScreen(childName: 'Ivy', service: freshVillage(), principal: guardian, yearsOld: 4));
      expect(find.textContaining('under five'), findsOneWidget);
      expect(find.textContaining('work at any age'), findsOneWidget);
      await show(t, VillageGuardianHubScreen(childName: 'Ivy', service: freshVillage(), principal: guardian, yearsOld: null));
      expect(find.textContaining('from age five'), findsOneWidget);
    });

    testWidgets('the suite switch saves through the service; a child principal cannot flip it', (WidgetTester t) async {
      await big(t);
      final VillageService s = freshVillage();
      await show(t, VillageGuardianHubScreen(childName: 'Ivy', service: s, principal: guardian));
      await t.tap(find.byKey(const Key('villageSuite')));
      await t.pumpAndSettle();
      expect((await s.loadForGuardian(guardian)).suiteOn, isFalse);
      await t.tap(find.byKey(const Key('villageSuite')));
      await t.pumpAndSettle();
      expect((await s.loadForGuardian(guardian)).suiteOn, isTrue);

      await show(t, VillageGuardianHubScreen(childName: 'Ivy', service: s, principal: ivy));
      await t.tap(find.byKey(const Key('villageSuite')));
      await t.pumpAndSettle();
      expect(find.text('Only a grown-up can change this.'), findsOneWidget);
      expect((await s.loadForGuardian(guardian)).suiteOn, isTrue, reason: 'nothing changed');
    });

    testWidgets('the hub links through to every editor', (WidgetTester t) async {
      await big(t);
      final Map<String, Type> rows = <String, Type>{
        'rowGrand': GrandCornerEditorScreen, 'rowFaces': FacesEditorScreen, 'rowStories': StoriesScreen,
        'rowShelf': SiblingEditorScreen, 'rowSitter': SitterPassEditorScreen, 'rowSchool': SchoolBridgeEditorScreen,
      };
      for (final MapEntry<String, Type> e in rows.entries) {
        await show(t, VillageGuardianHubScreen(
            childName: 'Ivy', service: freshVillage(), principal: guardian,
            people: () async => <({String id, String label})>[]));
        await tapKey(t, e.key);
        expect(find.byType(e.value), findsOneWidget, reason: e.key);
      }
    });

    testWidgets('it is reachable from the guardian Settings hub, under Family, next to Rhythm and Voice', (WidgetTester t) async {
      await big(t);
      await show(t, const GuardianMoreScreen(childName: 'Ivy', childAge: 6));
      await t.ensureVisible(find.byKey(const Key('moreSettings')));
      await t.tap(find.byKey(const Key('moreSettings')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('settingsRow_village')), findsOneWidget);
      expect(find.byKey(const Key('settingsRow_compass')), findsOneWidget);
      await t.tap(find.byKey(const Key('settingsRow_village')));
      await t.pumpAndSettle();
      expect(find.byType(VillageGuardianHubScreen), findsOneWidget);
    });
  });

  group('grandparent corner', () {
    testWidgets('a guardian adds a big button, a phone line, saves, and it is kept sealed on the device', (WidgetTester t) async {
      await big(t);
      final VillageService s = freshVillage();
      await show(t, GrandCornerEditorScreen(childName: 'Ivy', service: s, principal: guardian));
      expect(find.textContaining('Calling and sending pictures are not built'), findsOneWidget);
      await typeKey(t, 'grandName', 'Nana');
      await tapKey(t, 'grandAdd');
      await pick(t, 'book');
      await typeAndOk(t, 'Read to Ivy');
      await typeAndOk(t, 'The blue book is on the shelf.');
      await typeKey(t, 'grandPhoneWho', 'Mom');
      await typeKey(t, 'grandPhoneNumber', '555 0199');
      await tapKey(t, 'grandSave');
      final GrandCorner g = (await s.loadForGuardian(guardian)).grand!;
      expect(g.name, 'Nana');
      expect(g.cards.single.title, 'Read to Ivy');
      expect(g.cards.single.text, 'The blue book is on the shelf.');
      expect(g.phone!.number, '555 0199');
      expect(find.text('Saved on this device.'), findsOneWidget);
    });

    testWidgets('a number that is not a number is refused in words and nothing is saved', (WidgetTester t) async {
      await big(t);
      final VillageService s = freshVillage();
      await show(t, GrandCornerEditorScreen(childName: 'Ivy', service: s, principal: guardian));
      await typeKey(t, 'grandPhoneWho', 'Mom');
      await typeKey(t, 'grandPhoneNumber', 'call me');
      await tapKey(t, 'grandSave');
      expect(find.textContaining('digits only'), findsOneWidget);
      expect((await s.loadForGuardian(guardian)).grand, isNull);
    });

    testWidgets('the fifth button is refused with a gentle sentence', (WidgetTester t) async {
      await big(t);
      final VillageService s = freshVillage();
      await s.saveGrandCorner(guardian, makeGrandCorner(cards: <GrandCard>[
        for (int i = 0; i < 4; i++) GrandCard(id: 'g$i', picture: 'book', title: 'T$i'),
      ]));
      await show(t, GrandCornerEditorScreen(childName: 'Ivy', service: s, principal: guardian));
      await tapKey(t, 'grandAdd');
      expect(find.text('Four cards is the most there is room for.'), findsOneWidget);
      expect(find.byKey(const Key('pick_book')), findsNothing);
    });

    testWidgets('an address in a button is refused, not saved', (WidgetTester t) async {
      await big(t);
      await show(t, GrandCornerEditorScreen(childName: 'Ivy', service: freshVillage(), principal: guardian));
      await tapKey(t, 'grandAdd');
      await pick(t, 'door');
      await typeAndOk(t, 'Come to 12 Oak Street');
      await typeAndOk(t, '');
      expect(find.text('Please leave out addresses and places. Rooms only.'), findsOneWidget);
      expect(find.byType(Card), findsNothing);
    });

    testWidgets('a child principal cannot save it', (WidgetTester t) async {
      await big(t);
      final VillageService s = freshVillage();
      await s.saveGrandCorner(guardian, sampleGrand());
      await show(t, GrandCornerEditorScreen(childName: 'Ivy', service: s, principal: ivy));
      expect(find.text('Only a grown-up can change this.'), findsOneWidget);
      expect(find.byKey(const Key('grandName')), findsNothing, reason: 'the editor never loads for a child principal');
      expect(find.text('Read to Ivy'), findsNothing);
      expect((await s.saveGrandCorner(ivy, const GrandCorner())).reason, 'guardian_only');
      expect((await s.loadForGuardian(guardian)).grand!.name, 'Nana', reason: 'nothing changed');
    });

    testWidgets('clear this page removes it', (WidgetTester t) async {
      await big(t);
      final VillageService s = freshVillage();
      await s.saveGrandCorner(guardian, sampleGrand());
      await show(t, GrandCornerEditorScreen(childName: 'Ivy', service: s, principal: guardian));
      expect(find.byKey(const Key('grandCard_g1')), findsOneWidget);
      await tapKey(t, 'grandClear');
      expect((await s.loadForGuardian(guardian)).grand, isNull);
      expect(find.byKey(const Key('grandCard_g1')), findsNothing);
    });

    testWidgets('the large page: huge type, big buttons, a phone line as TEXT that is never dialled', (WidgetTester t) async {
      await big(t);
      await show(t, GrandCornerScreen(corner: sampleGrand()));
      expect(find.text('Hello, Nana'), findsOneWidget);
      expect(find.text('Read to Ivy'), findsOneWidget);
      expect(t.getSize(find.byKey(const Key('grandBig_g1'))).height, greaterThanOrEqualTo(96));
      expect(t.widget<Text>(find.text('Read to Ivy')).style!.fontSize, greaterThanOrEqualTo(26));
      expect(find.text('Mom: 555 0199'), findsOneWidget);
      expect(t.widget<Text>(find.text('Mom: 555 0199')).style!.fontSize, greaterThanOrEqualTo(28));
      expect(find.byType(Link), findsNothing);
      await t.tap(find.byKey(const Key('grandPhone')));
      await t.pump();
      expect(find.byType(AlertDialog), findsNothing, reason: 'tapping the number does nothing: no dialler, no link');
      await t.tap(find.byKey(const Key('grandBig_g1')));
      await t.pumpAndSettle();
      expect(t.widget<Text>(find.byKey(const Key('grandBigText'))).style!.fontSize, greaterThanOrEqualTo(26));
      expect(find.text('Open the blue book on the shelf.'), findsOneWidget);
    });

    testWidgets('an empty page says so', (WidgetTester t) async {
      await show(t, const GrandCornerScreen(corner: GrandCorner()));
      expect(find.byKey(const Key('grandEmpty')), findsOneWidget);
      expect(find.text('Hello'), findsOneWidget);
    });
  });

  group('her people in pictures (faces)', () {
    Future<List<({String id, String label})>> people() async =>
        <({String id, String label})>[(id: 'p1', label: 'Mom'), (id: 'p2', label: 'Jordan')];

    testWidgets('names come from the family builder as chosen; a guardian only picks the face', (WidgetTester t) async {
      await big(t);
      final VillageService s = freshVillage();
      await show(t, FacesEditorScreen(childName: 'Ivy', service: s, principal: guardian, people: people));
      expect(find.textContaining('exactly as you chose them'), findsOneWidget);
      expect(find.text('Mom'), findsOneWidget);
      expect(find.text('Jordan'), findsOneWidget);
      expect(find.byType(TextField), findsNothing, reason: 'no name or role is typed or generated here');
      await tapKey(t, 'faceRow_p1');
      await pick(t, 'grandparent');
      expect((await s.loadForGuardian(guardian)).faces, <String, String>{'p1': 'grandparent'});
      expect(find.text('Grandparent'), findsOneWidget);
    });

    testWidgets('the picker offers only people pictures, and the first letter can be put back', (WidgetTester t) async {
      await big(t);
      final VillageService s = freshVillage();
      await s.setFace(guardian, 'p1', 'friend');
      await show(t, FacesEditorScreen(childName: 'Ivy', service: s, principal: guardian, people: people));
      await tapKey(t, 'faceRow_p2');
      expect(find.byKey(const Key('pick_friend')), findsOneWidget);
      expect(find.byKey(const Key('pick_bath')), findsNothing);
      expect(find.byKey(const Key('pick_worry-dark')), findsNothing);
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      await tapKey(t, 'facePlain_p1');
      expect((await s.loadForGuardian(guardian)).faces, isEmpty);
    });

    testWidgets('nobody in the family builder yet: a quiet sentence', (WidgetTester t) async {
      await big(t);
      await show(t, FacesEditorScreen(childName: 'Ivy', service: freshVillage(), principal: guardian, people: () async => <({String id, String label})>[]));
      expect(find.textContaining('Nobody is in the family builder yet'), findsOneWidget);
    });

    testWidgets('a child principal cannot choose a face', (WidgetTester t) async {
      await big(t);
      final VillageService s = freshVillage();
      await show(t, FacesEditorScreen(childName: 'Ivy', service: s, principal: ivy, people: people));
      // the editor cannot even load the guardian's document for a child principal
      expect(find.byKey(const Key('faceRow_p1')), findsNothing);
      expect(find.text('Only a grown-up can change this.'), findsOneWidget);
      expect((await s.setFace(ivy, 'p1', 'friend')).reason, 'guardian_only');
    });
  });

  group('a story for her', () {
    testWidgets('the editor starts EMPTY: no template, no suggested words', (WidgetTester t) async {
      await big(t);
      await show(t, StoryEditorScreen(childName: 'Ivy', service: freshVillage(), principal: guardian));
      expect(t.widget<TextField>(find.byKey(const Key('storyTitle'))).controller!.text, isEmpty);
      expect(find.byKey(const Key('storyPageRow_0')), findsNothing);
      await show(t, StoriesScreen(childName: 'Ivy', service: freshVillage(), principal: guardian));
      expect(find.textContaining('Nothing is suggested or filled in for you'), findsOneWidget);
      expect(find.text('No stories yet.'), findsOneWidget);
    });

    testWidgets('writing, saving and releasing: held by default, released only on a yes', (WidgetTester t) async {
      await big(t);
      final VillageService s = freshVillage();
      await show(t, StoriesScreen(childName: 'Ivy', service: s, principal: guardian));
      await tapKey(t, 'storyAdd');
      await typeKey(t, 'storyTitle', 'Our new week');
      await tapKey(t, 'storyPageAdd');
      await pick(t, 'door');
      await typeAndOk(t, 'We open the door.');
      await tapKey(t, 'storySave');
      expect(find.byType(StoryEditorScreen), findsNothing);
      final WelcomeStory st = (await s.loadForGuardian(guardian)).stories.single;
      expect(st.title, 'Our new week');
      expect(st.released, isFalse);
      expect(find.text('Held'), findsOneWidget);
      expect(await s.releasedStories(ivy), isEmpty);

      await tapKey(t, 'storyRelease_${st.id}');
      expect(find.textContaining('Release it when you are ready'), findsOneWidget);
      await t.tap(find.byKey(const Key('releaseNo')));
      await t.pumpAndSettle();
      expect(await s.releasedStories(ivy), isEmpty, reason: '"Not yet" releases nothing');

      await tapKey(t, 'storyRelease_${st.id}');
      await t.tap(find.byKey(const Key('releaseYes')));
      await t.pumpAndSettle();
      expect((await s.releasedStories(ivy)).single.title, 'Our new week');
      expect(find.text('Released'), findsOneWidget);

      await tapKey(t, 'storyHold_${st.id}');
      expect(await s.releasedStories(ivy), isEmpty);
      expect(find.text('Held'), findsOneWidget);
    });

    testWidgets('editing a released story holds it again, and says so', (WidgetTester t) async {
      await big(t);
      final VillageService s = freshVillage();
      await s.saveStory(guardian, sampleStory());
      await s.releaseStory(guardian, 's1');
      await show(t, StoriesScreen(childName: 'Ivy', service: s, principal: guardian));
      expect(find.textContaining('Changing a story holds it again'), findsOneWidget);
      await tapKey(t, 'storyEdit_s1');
      expect(find.byKey(const Key('storyPageRow_1')), findsOneWidget);
      await typeKey(t, 'storyTitle', 'A new day, again');
      await tapKey(t, 'storySave');
      expect((await s.loadForGuardian(guardian)).stories.single.released, isFalse);
    });

    testWidgets('remove deletes it; a seventh page and a no-page story are refused', (WidgetTester t) async {
      await big(t);
      final VillageService s = freshVillage();
      await show(t, StoryEditorScreen(childName: 'Ivy', service: s, principal: guardian));
      await typeKey(t, 'storyTitle', 'Empty');
      await tapKey(t, 'storySave');
      expect(find.text('A story needs at least one page.'), findsOneWidget);
      expect((await s.loadForGuardian(guardian)).stories, isEmpty);

      for (int i = 0; i < maxWelcomePages; i++) {
        await tapKey(t, 'storyPageAdd');
        await pick(t, 'door');
        await typeAndOk(t, 'Page $i');
      }
      await tapKey(t, 'storyPageAdd');
      expect(find.text('A story can have up to six pages.'), findsOneWidget);

      await s.saveStory(guardian, sampleStory());
      await show(t, StoriesScreen(childName: 'Ivy', service: s, principal: guardian));
      await tapKey(t, 'storyRemove_s1');
      expect((await s.loadForGuardian(guardian)).stories, isEmpty);
    });

    testWidgets('a child principal cannot save, release or hold', (WidgetTester t) async {
      await big(t);
      final VillageService s = freshVillage();
      await show(t, StoryEditorScreen(childName: 'Ivy', service: s, principal: ivy));
      await typeKey(t, 'storyTitle', 'Sneaky');
      await tapKey(t, 'storyPageAdd');
      await pick(t, 'door');
      await typeAndOk(t, 'Hello');
      await tapKey(t, 'storySave');
      expect(find.text('Only a grown-up can change this.'), findsOneWidget);
      expect((await s.loadForGuardian(guardian)).stories, isEmpty);
    });
  });

  group('sibling shelf editor', () {
    testWidgets('adds a brother or sister by the name typed, saves, and refuses a fifth', (WidgetTester t) async {
      await big(t);
      final VillageService s = freshVillage();
      await show(t, SiblingEditorScreen(childName: 'Ivy', service: s, principal: guardian));
      expect(find.textContaining('never shows how many pictures it holds'), findsOneWidget);
      for (final String n in <String>['Leo', 'Mia', 'Zed', 'Kit']) {
        await tapKey(t, 'sibAdd');
        await pick(t, 'sibling');
        await typeAndOk(t, n);
      }
      await tapKey(t, 'sibAdd');
      expect(find.text('Four is the most there is room for.'), findsOneWidget);
      await tapKey(t, 'sibSave');
      expect((await s.loadForGuardian(guardian)).shelf.siblings.map((SiblingSlot x) => x.name), <String>['Leo', 'Mia', 'Zed', 'Kit']);
    });

    testWidgets('a face outside the people group is not on offer; take every picture down works', (WidgetTester t) async {
      await big(t);
      final VillageService s = freshVillage();
      await s.saveSiblings(guardian, sampleSiblings());
      await s.leavePicture(ivy, 'b1', 'teddy');
      await show(t, SiblingEditorScreen(childName: 'Ivy', service: s, principal: guardian));
      await tapKey(t, 'sibAdd');
      expect(find.byKey(const Key('pick_sibling')), findsOneWidget);
      expect(find.byKey(const Key('pick_bath')), findsNothing);
      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      await tapKey(t, 'sibClearPictures');
      expect((await s.shelf(ivy)).notes, isEmpty);
      expect((await s.shelf(ivy)).siblings.length, 2);
    });

    testWidgets('a child principal cannot save the shelf', (WidgetTester t) async {
      await big(t);
      final VillageService s = freshVillage();
      await show(t, SiblingEditorScreen(childName: 'Ivy', service: s, principal: ivy));
      expect((await s.saveSiblings(ivy, sampleSiblings())).reason, 'guardian_only');
    });
  });

  group('the pass page', () {
    testWidgets('black on white, big type, says where it is kept, and an empty page says it is empty', (WidgetTester t) async {
      await big(t);
      await show(t, const PassPageScreen(heading: 'Tonight', header: <String>['For Aunt Mia'], sections: <PassSection>[], writtenOn: day));
      expect(find.byKey(const Key('passEmpty')), findsOneWidget);
      expect(find.textContaining('Kept on this device; shown only when it is held up'), findsOneWidget);
      expect(find.textContaining('Written by a grown-up on $day'), findsOneWidget);
      expect(t.widget<Scaffold>(find.byType(Scaffold)).backgroundColor, Colors.white);
      await show(t, PassPageScreen(heading: 'Tonight', header: const <String>[], sections: sitterSections(sampleSitter())));
      expect(t.widget<Text>(find.text('• Cashews (written by Mom)')).style!.color, Colors.black);
      expect(t.widget<Text>(find.text('• Cashews (written by Mom)')).style!.fontSize, greaterThanOrEqualTo(20));
    });

    testWidgets('it fits at 2x text without overflowing', (WidgetTester t) async {
      await phone(t, w: 344, h: 900);
      await t.pumpWidget(app(PassPageScreen(heading: 'Friday evening', header: const <String>['For Aunt Mia'], sections: sitterSections(sampleSitter())), textScale: 2.0));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  });

  group('sitter pass editor', () {
    testWidgets('a guardian writes the page, saves it sealed on the device, and shows exactly those words', (WidgetTester t) async {
      await big(t);
      final VillageService s = freshVillage();
      await show(t, SitterPassEditorScreen(childName: 'Ivy', service: s, principal: guardian));
      expect(find.textContaining('leaves this device only when you hold the screen up'), findsOneWidget);
      await typeKey(t, 'sitterTitle', 'Friday evening');
      await typeKey(t, 'sitterFor', 'Aunt Mia');
      await typeKey(t, 'sitterWhen', 'Friday 6 to 10');
      await typeKey(t, 'sitterAllergies', 'Cashews, written by Mom\nPollen');
      await typeKey(t, 'sitterRoutine', 'Bath at 7\n\nBooks');
      await typeKey(t, 'sitterNotes', 'Hall light stays on');
      await tapKey(t, 'sitterContactAdd');
      await t.enterText(find.byKey(const Key('contactName')), 'Mom');
      await t.enterText(find.byKey(const Key('contactRelation')), 'her mum');
      await t.enterText(find.byKey(const Key('contactNumber')), '555 0142');
      await t.enterText(find.byKey(const Key('contactBest')), 'after 9');
      await t.tap(find.byKey(const Key('contactOk')));
      await t.pumpAndSettle();
      expect(find.text('Mom (her mum): 555 0142, best after 9'), findsOneWidget);
      await tapKey(t, 'sitterSave');
      final SitterPass p = (await s.loadPasses(guardian)).sitter!;
      expect(p.allergies, <String>['Cashews, written by Mom', 'Pollen']);
      expect(p.routine, <String>['Bath at 7', 'Books']);
      expect(p.contacts.single.number, '555 0142');
      expect(p.writtenOn, day);

      await tapKey(t, 'sitterShow');
      expect(find.byKey(const Key('passPage')), findsOneWidget);
      expect(find.text('Friday evening'), findsWidgets);
      expect(find.text('For Aunt Mia'), findsOneWidget);
      expect(find.text('Friday 6 to 10'), findsOneWidget);
      expect(find.text('• Cashews, written by Mom'), findsOneWidget);
      expect(find.text('• Mom (her mum): 555 0142, best after 9'), findsOneWidget);
      expect(find.textContaining('Written by a grown-up on $day'), findsOneWidget);
    });

    testWidgets('an address in a note, and a number that is not a number, are refused in words and nothing is saved', (WidgetTester t) async {
      await big(t);
      final VillageService s = freshVillage();
      await show(t, SitterPassEditorScreen(childName: 'Ivy', service: s, principal: guardian));
      await typeKey(t, 'sitterNotes', 'We are at 44 Maple Avenue');
      await tapKey(t, 'sitterSave');
      expect(find.text('Please leave out addresses and places. Rooms only.'), findsOneWidget);
      expect((await s.loadPasses(guardian)).sitter, isNull);
      await typeKey(t, 'sitterNotes', 'fine');
      await tapKey(t, 'sitterContactAdd');
      await t.enterText(find.byKey(const Key('contactName')), 'Mom');
      await t.enterText(find.byKey(const Key('contactNumber')), 'soon');
      await t.tap(find.byKey(const Key('contactOk')));
      await t.pumpAndSettle();
      await tapKey(t, 'sitterSave');
      expect(find.textContaining('Something there did not work'), findsOneWidget);
      expect((await s.loadPasses(guardian)).sitter, isNull);
    });

    testWidgets('showing the page with bad content refuses rather than showing half of it', (WidgetTester t) async {
      await big(t);
      await show(t, SitterPassEditorScreen(childName: 'Ivy', service: freshVillage(), principal: guardian));
      await typeKey(t, 'sitterRoutine', List<String>.filled(9, 'x').join('\n'));
      await tapKey(t, 'sitterShow');
      expect(find.byKey(const Key('passPage')), findsNothing);
      expect(find.text('That is the most there is room for.'), findsOneWidget);
    });

    testWidgets('"copy the step names from her routine" fills the routine box from the guardian\'s own Rhythm routine; absent without a source', (WidgetTester t) async {
      await big(t);
      await show(t, SitterPassEditorScreen(childName: 'Ivy', service: freshVillage(), principal: guardian));
      expect(find.byKey(const Key('sitterCopyRoutine')), findsNothing);
      await show(t, SitterPassEditorScreen(
          childName: 'Ivy', service: freshVillage(), principal: guardian, routineLines: () async => <String>['Bath', 'Pyjamas', 'Book']));
      await tapKey(t, 'sitterCopyRoutine');
      expect(t.widget<TextField>(find.descendant(of: find.byKey(const Key('sitterRoutine')), matching: find.byType(TextField))).controller!.text, 'Bath\nPyjamas\nBook');
    });

    testWidgets('it re-opens with what was saved, and clearing removes it', (WidgetTester t) async {
      await big(t);
      final VillageService s = freshVillage();
      await s.saveSitterPass(guardian, sampleSitter());
      await show(t, SitterPassEditorScreen(childName: 'Ivy', service: s, principal: guardian));
      expect(t.widget<TextField>(find.byKey(const Key('sitterTitle'))).controller!.text, 'Friday evening');
      expect(find.byKey(const Key('sitterContact_c1')), findsOneWidget);
      await tapKey(t, 'sitterClear');
      expect((await s.loadPasses(guardian)).sitter, isNull);
      expect(find.byKey(const Key('sitterContact_c1')), findsNothing);
    });

    testWidgets('a child principal sees nothing of a saved pass and cannot save one', (WidgetTester t) async {
      await big(t);
      final VillageService s = freshVillage();
      await s.saveSitterPass(guardian, sampleSitter());
      await show(t, SitterPassEditorScreen(childName: 'Ivy', service: s, principal: ivy));
      expect(find.byKey(const Key('sitterTitle')), findsNothing, reason: 'the editor never loads for a child principal');
      expect(find.text('Only a grown-up can change this.'), findsOneWidget);
      expect(find.textContaining('Cashews'), findsNothing);
      expect((await s.saveSitterPass(ivy, sampleSitter())).reason, 'guardian_only');
    });
  });

  group('school summary editor', () {
    testWidgets('writes, saves, shows; says the school is not contacted and no grades or behaviour are carried', (WidgetTester t) async {
      await big(t);
      final VillageService s = freshVillage();
      await show(t, SchoolBridgeEditorScreen(childName: 'Ivy', service: s, principal: guardian));
      expect(find.textContaining('The school is not contacted'), findsOneWidget);
      expect(find.byKey(const Key('schoolNote')), findsOneWidget);
      await typeKey(t, 'schoolName', 'Oak Primary');
      await typeKey(t, 'schoolClass', 'Ms. Alvarez');
      await typeKey(t, 'schoolHelps', 'A warning before a change');
      await typeKey(t, 'schoolPickup', 'Mom or Nana');
      await tapKey(t, 'schoolSave');
      final SchoolBridge b = (await s.loadPasses(guardian)).school!;
      expect(b.school, 'Oak Primary');
      expect(b.helps, <String>['A warning before a change']);
      await tapKey(t, 'schoolShow');
      expect(find.text('Oak Primary'), findsWidgets);
      expect(find.text('Ms. Alvarez'), findsOneWidget);
      expect(find.text('What helps'), findsOneWidget);
      expect(find.text('Who collects her'), findsOneWidget);
    });

    testWidgets('an address as the school name is refused', (WidgetTester t) async {
      await big(t);
      final VillageService s = freshVillage();
      await show(t, SchoolBridgeEditorScreen(childName: 'Ivy', service: s, principal: guardian));
      await typeKey(t, 'schoolName', '12 Oak Street');
      await tapKey(t, 'schoolSave');
      expect(find.text('Please leave out addresses and places. Rooms only.'), findsOneWidget);
      expect((await s.loadPasses(guardian)).school, isNull);
    });

    testWidgets('five pickup lines are refused; clearing removes it', (WidgetTester t) async {
      await big(t);
      final VillageService s = freshVillage();
      await show(t, SchoolBridgeEditorScreen(childName: 'Ivy', service: s, principal: guardian));
      await typeKey(t, 'schoolPickup', List<String>.filled(5, 'x').join('\n'));
      await tapKey(t, 'schoolSave');
      expect(find.text('That is the most there is room for.'), findsOneWidget);
      await s.saveSchoolBridge(guardian, sampleSchool());
      await show(t, SchoolBridgeEditorScreen(childName: 'Ivy', service: s, principal: guardian));
      await tapKey(t, 'schoolClear');
      expect((await s.loadPasses(guardian)).school, isNull);
    });

    testWidgets('a child principal cannot save it', (WidgetTester t) async {
      final VillageService s = freshVillage();
      expect((await s.saveSchoolBridge(ivy, sampleSchool())).reason, 'guardian_only');
      expect((await s.loadPasses(guardian)).school, isNull);
    });
  });

  group('offline by construction', () {
    String stripped(String p) => File(p).readAsStringSync().replaceAll(RegExp(r'//.*'), '');

    test('no Village, Compass or alert file imports a network, link or launcher library, or opens a socket', () {
      for (final String f in <String>[
        'village_logic', 'village_repositories', 'village_screens', 'village_sections', 'village_guardian_screens',
        'compass_logic', 'compass_repositories', 'compass_screens', 'visual_alert',
      ]) {
        final String src = stripped('lib/$f.dart');
        for (final String banned in <String>[
          'package:http', 'dart:io', 'url_launcher', 'web_socket', 'api_client', 'livekit', 'Socket', 'HttpClient',
          'launchUrl', 'tel:', 'mailto:', 'sms:', 'share_plus', 'Clipboard', 'baseUrl', 'sessionToken',
        ]) {
          expect(src.contains(banned), isFalse, reason: '$f must not use $banned');
        }
      }
    });

    test('the guardian editors are imported by nothing in the child shell', () {
      for (final String f in <String>['child_home', 'child_more', 'village_screens', 'village_sections']) {
        final String src = stripped('lib/$f.dart');
        expect(src.contains('village_guardian_screens'), isFalse, reason: f);
        expect(src.contains('compass_screens'), isFalse, reason: f);
      }
    });
  });
}
