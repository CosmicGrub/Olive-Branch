// OLIVE BRANCH — suite F (Care) screens: care binder, hospital mode, picture
// stories (grown-up editor and her read-only side) and appointment prep. All
// guardian-written, all on this device. The deny paths: the app writes nothing
// of its own, her side holds no care type, nothing is scheduled.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/care_screens.dart';
import 'package:olive_client/child_explainer_screens.dart';
import 'package:olive_client/emergency_card.dart';
import 'package:olive_client/growing_care_logic.dart';
import 'package:olive_client/growing_care_store.dart';
import 'package:olive_client/guardian_more.dart';

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

String _strip(String path) => File(path).readAsStringSync().replaceAll(RegExp(r'//.*'), '');

void main() {
  group('care binder: every word is a guardian\'s', () {
    testWidgets('starts empty. The app writes no section, no suggestion and no medical text', (t) async {
      await _show(t, CareBinderScreen(stores: GrowingCareStores.memory(), now: _now));
      expect(find.byKey(const Key('binderEmpty')), findsOneWidget);
      expect(find.textContaining('adds no medical content'), findsOneWidget);
      expect(find.textContaining('never on her device'), findsOneWidget);
      expect(find.textContaining(RegExp('dose|mg|treat|diagnos|symptom|should take|call a doctor', caseSensitive: false)), findsNothing);
    });

    testWidgets('adding an allergy section keeps exactly what the guardian typed, under a neutral label', (t) async {
      final GrowingCareStores s = GrowingCareStores.memory();
      await _show(t, CareBinderScreen(stores: s, now: _now));
      await _tap(t, 'addSection');
      await _tap(t, 'addKind_allergies');
      expect(t.widget<TextField>(find.byKey(const Key('sectionTitle'))).controller!.text, 'Allergies (written by a guardian)');
      expect(t.widget<TextField>(find.byKey(const Key('sectionBody'))).controller!.text, isEmpty, reason: 'the body starts blank');
      await _type(t, 'sectionBody', 'Peanuts, as Mom told the school.');
      await _tap(t, 'sectionSave');
      expect(find.text('Peanuts, as Mom told the school.'), findsOneWidget);
      final CareSection saved = (await s.sections.list()).single;
      expect(saved.kind, 'allergies');
      expect(saved.body, 'Peanuts, as Mom told the school.');
      expect(saved.updatedOn, '2026-11-08');
    });

    testWidgets('a section can be edited and removed (after asking)', (t) async {
      final GrowingCareStores s = GrowingCareStores.memory();
      await s.sections.save(const CareSection(id: 's1', kind: 'routines', title: 'Routines', body: 'Bath at 7', updatedOn: '2026-11-01'));
      await _show(t, CareBinderScreen(stores: s, now: _now));
      await _tap(t, 'editSection-s1');
      await _type(t, 'sectionBody', 'Bath at 7, then a story');
      await _tap(t, 'sectionSave');
      expect((await s.sections.get('s1'))!.body, 'Bath at 7, then a story');
      await _tap(t, 'removeSection-s1');
      await _tap(t, 'confirmKeep');
      expect(await s.sections.list(), hasLength(1));
      await _tap(t, 'removeSection-s1');
      await _tap(t, 'confirmGo');
      expect(await s.sections.list(), isEmpty);
    });

    testWidgets('refused: a section with no title, and one that is too long; nothing is kept', (t) async {
      final GrowingCareStores s = GrowingCareStores.memory();
      await _show(t, CareBinderScreen(stores: s, now: _now));
      await _tap(t, 'addSection');
      await _tap(t, 'addKind_school');
      await _type(t, 'sectionTitle', '');
      await _tap(t, 'sectionSave');
      expect(find.text('There is nothing written yet.'), findsOneWidget);
      expect(await s.sections.list(), isEmpty);
    });

    testWidgets('there is room for twelve sections and no more', (t) async {
      final GrowingCareStores s = GrowingCareStores.memory();
      for (int i = 0; i < maxCareSections; i++) {
        await s.sections.save(CareSection(id: 's$i', kind: 'other', title: 'Notes', body: '', updatedOn: '2026-11-08'));
      }
      await _show(t, CareBinderScreen(stores: s, now: _now));
      await _tap(t, 'addSection');
      await _tap(t, 'addKind_other');
      await _tap(t, 'sectionSave');
      expect(find.textContaining('no more room'), findsOneWidget);
      expect(await s.sections.list(), hasLength(maxCareSections));
    });

    testWidgets('contacts: add, show and remove', (t) async {
      final GrowingCareStores s = GrowingCareStores.memory();
      await _show(t, CareBinderScreen(stores: s, now: _now));
      await _tap(t, 'addContact');
      await _type(t, 'contactName', 'Nana');
      await _type(t, 'contactRelation', 'grandmother');
      await _type(t, 'contactPhone', '555-0101');
      await _tap(t, 'contactSave');
      expect(find.text('Nana'), findsOneWidget);
      expect(find.text('grandmother - 555-0101'), findsOneWidget);
      final String id = (await s.contacts.list()).single.id;
      await _tap(t, 'removeContact-$id');
      await _tap(t, 'confirmGo');
      expect(await s.contacts.list(), isEmpty);
    });

    testWidgets('a contact needs a name', (t) async {
      final GrowingCareStores s = GrowingCareStores.memory();
      await _show(t, CareBinderScreen(stores: s, now: _now));
      await _tap(t, 'addContact');
      await _tap(t, 'contactSave');
      expect(find.text('There is nothing written yet.'), findsOneWidget);
      expect(await s.contacts.list(), isEmpty);
    });

    testWidgets('the print view is one plain page of what was written, with a copy button', (t) async {
      final GrowingCareStores s = GrowingCareStores.memory();
      await s.sections.save(const CareSection(id: 's1', kind: 'school', title: 'School', body: 'Pick-up at 3:15', updatedOn: '2026-11-08'));
      await s.contacts.save(const CareContact(id: 'p1', name: 'Nana', phone: '555-0101'));
      await _show(t, CareBinderScreen(childName: 'Ivy', stores: s, now: _now));
      await _tap(t, 'printView');
      expect(find.byType(BinderPrintScreen), findsOneWidget);
      final SelectableText sheet = t.widget<SelectableText>(find.descendant(of: find.byKey(const Key('printSheet')), matching: find.byType(SelectableText)));
      expect(sheet.data, contains('Pick-up at 3:15'));
      expect(sheet.data, contains('Nana - 555-0101'));
      expect(sheet.data, contains('Kept on this device only.'));
    });

    testWidgets('copy puts the text on the clipboard and says so', (t) async {
      String? copied;
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (MethodCall c) async {
        if (c.method == 'Clipboard.setData') copied = (c.arguments as Map<Object?, Object?>)['text'] as String?;
        return null;
      });
      addTearDown(() => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await _show(t, const BinderPrintScreen(text: 'Ivy: care binder\nline'));
      await _tap(t, 'copyBinder');
      expect(copied, 'Ivy: care binder\nline');
      expect(find.textContaining('clipboard'), findsOneWidget);
    });
  });

  group('hospital mode: one calm page from what a guardian wrote', () {
    testWidgets('empty: it says nothing is written and invents nothing', (t) async {
      await _show(t, HospitalModeScreen(stores: GrowingCareStores.memory(), openEmergencyCard: (_) {}));
      expect(find.byKey(const Key('hospitalEmpty')), findsOneWidget);
      expect(find.byKey(const Key('hospToday')), findsNothing);
      expect(find.byKey(const Key('hospContacts')), findsNothing);
    });

    testWidgets('it pulls allergies and contacts from the binder and the notes from the guardian, in plain big text', (t) async {
      final GrowingCareStores s = GrowingCareStores.memory();
      await s.sections.save(const CareSection(id: 'a', kind: 'allergies', title: 'Allergies (written by a guardian)', body: 'Peanuts', updatedOn: '2026-11-08'));
      await s.sections.save(const CareSection(id: 'r', kind: 'routines', title: 'Routines', body: 'Bath at 7', updatedOn: '2026-11-08'));
      await s.contacts.save(const CareContact(id: 'p', name: 'Nana', relation: 'grandmother', phone: '555-0101'));
      await s.hospital.save(const HospitalNotes(happeningToday: 'Scan at two', toBring: 'The owl', whatHelpsHer: 'A song', staffShouldKnow: 'She is shy'));
      await _show(t, HospitalModeScreen(stores: s, openEmergencyCard: (_) {}));
      expect(find.text('Scan at two'), findsOneWidget);
      expect(find.text('The owl'), findsOneWidget);
      expect(find.text('A song'), findsOneWidget);
      expect(find.text('She is shy'), findsOneWidget);
      expect(find.text('Peanuts'), findsOneWidget);
      expect(find.text('Allergies (written by a guardian)'), findsOneWidget);
      expect(find.text('Nana  -  grandmother  -  555-0101'), findsOneWidget);
      expect(find.text('Bath at 7'), findsNothing, reason: 'routines are not hospital content');
      expect(find.byKey(const Key('hospitalEmpty')), findsNothing);
    });

    testWidgets('the existing emergency card is one big tap away', (t) async {
      bool opened = false;
      await _show(t, HospitalModeScreen(stores: GrowingCareStores.memory(), openEmergencyCard: (_) => opened = true));
      expect(t.getSize(find.byKey(const Key('openEmergencyCard'))).height, greaterThanOrEqualTo(64));
      await _tap(t, 'openEmergencyCard');
      expect(opened, isTrue);
    });

    testWidgets('by default the button opens the real emergency card screen', (t) async {
      await _show(t, HospitalModeScreen(stores: GrowingCareStores.memory()));
      await _tap(t, 'openEmergencyCard');
      expect(find.byType(EmergencyCardScreen), findsOneWidget);
    });

    testWidgets('notes can be written, kept and read back', (t) async {
      final GrowingCareStores s = GrowingCareStores.memory();
      await _show(t, HospitalModeScreen(stores: s, openEmergencyCard: (_) {}));
      await _tap(t, 'editHospital');
      await _type(t, 'fieldToday', 'Surgery at nine');
      await _type(t, 'fieldBring', 'Slippers');
      await _tap(t, 'saveHospital');
      expect(find.text('Surgery at nine'), findsOneWidget);
      expect(find.text('Slippers'), findsOneWidget);
      expect((await s.hospital.get(HospitalNotes.itemId))!.happeningToday, 'Surgery at nine');
    });

    testWidgets('says where it is kept and that a guardian wrote it', (t) async {
      await _show(t, HospitalModeScreen(stores: GrowingCareStores.memory(), openEmergencyCard: (_) {}));
      expect(find.textContaining('Kept on this device only.'), findsOneWidget);
      expect(find.textContaining('Written by a guardian.'), findsOneWidget);
    });
  });

  group('picture stories: grown-up editor', () {
    testWidgets('empty, local, and says the app writes none', (t) async {
      await _show(t, ExplainerAuthoringScreen(stores: GrowingCareStores.memory(), now: _now));
      expect(find.byKey(const Key('storiesEmpty')), findsOneWidget);
      expect(find.textContaining('The app writes none and adds no advice'), findsOneWidget);
    });

    testWidgets('writing one keeps it hidden from her until the guardian turns it on', (t) async {
      final GrowingCareStores s = GrowingCareStores.memory();
      await _show(t, ExplainerAuthoringScreen(stores: s, now: _now));
      await _tap(t, 'addStory');
      expect(t.widget<TextField>(find.byKey(const Key('storyTitle'))).controller!.text, isEmpty, reason: 'no pre-written title');
      expect(t.widget<TextField>(find.byKey(const ValueKey<String>('storyPage-0'))).controller!.text, isEmpty, reason: 'no pre-written page');
      await _type(t, 'storyTitle', 'Mom is in the hospital');
      await _type(t, 'storyPage-0', 'Mom is at the hospital so the doctors can help her.');
      await _tap(t, 'addPage');
      await _type(t, 'storyPage-1', 'We can call her tonight.');
      await _tap(t, 'saveStory');
      final ExplainerStory st = (await s.stories.list()).single;
      expect(st.pages, hasLength(2));
      expect(st.shownToHer, isFalse);
      expect(find.text('Mom is in the hospital'), findsOneWidget);
      await _tap(t, 'showStory-${st.id}');
      expect((await s.stories.get(st.id))!.shownToHer, isTrue);
    });

    testWidgets('refused: no title, an empty page, and more pages than the model allows', (t) async {
      final GrowingCareStores s = GrowingCareStores.memory();
      await _show(t, ExplainerAuthoringScreen(stores: s, now: _now));
      await _tap(t, 'addStory');
      await _tap(t, 'saveStory');
      expect(find.text('There is nothing written yet.'), findsOneWidget);
      await _type(t, 'storyTitle', 'T');
      await _tap(t, 'saveStory');
      expect(find.text('There is nothing written yet.'), findsOneWidget, reason: 'the page is still empty');
      for (int i = 1; i < 6; i++) {
        await _tap(t, 'addPage');
      }
      expect(find.byKey(const Key('addPage')), findsNothing, reason: 'six pages is the most');
      expect(await s.stories.list(), isEmpty);
    });

    testWidgets('a page can be removed while at least one remains', (t) async {
      await _show(t, ExplainerAuthoringScreen(stores: GrowingCareStores.memory(), now: _now));
      await _tap(t, 'addStory');
      expect(find.byKey(const ValueKey<String>('removePage-0')), findsNothing);
      await _tap(t, 'addPage');
      await _tap(t, 'removePage-0');
      expect(find.byKey(const ValueKey<String>('storyPage-1')), findsNothing);
    });

    testWidgets('editing keeps the id; the guardian can read it as she would; remove asks first', (t) async {
      final GrowingCareStores s = GrowingCareStores.memory();
      await s.stories.save(const ExplainerStory(id: 'e1', title: 'Old title', pages: <String>['One', 'Two'], updatedOn: '2026-11-01'));
      await _show(t, ExplainerAuthoringScreen(stores: s, now: _now));
      await _tap(t, 'editStory-e1');
      await _type(t, 'storyTitle', 'New title');
      await _tap(t, 'saveStory');
      expect((await s.stories.list()), hasLength(1));
      expect((await s.stories.get('e1'))!.title, 'New title');
      expect((await s.stories.get('e1'))!.updatedOn, '2026-11-08');
      await _tap(t, 'previewStory-e1');
      expect(find.byType(ExplainerPagerScreen), findsOneWidget);
      await t.pageBack();
      await t.pumpAndSettle();
      await _tap(t, 'removeStory-e1');
      await _tap(t, 'confirmGo');
      expect(await s.stories.list(), isEmpty);
    });

    testWidgets('a photo over the cap is refused with an honest message', (t) async {
      await _show(t, ExplainerAuthoringScreen(stores: GrowingCareStores.memory(), now: _now, photoSource: () async => _bytes(maxThumbBytes + 1)));
      await _tap(t, 'addStory');
      await _tap(t, 'pickPhoto');
      expect(find.text('That photo is too big to keep here. Try a smaller one.'), findsOneWidget);
    });
  });

  group('picture stories: her side is read-only', () {
    testWidgets('she sees only stories a guardian chose to show; there is nothing to type or change', (t) async {
      final GrowingCareStores s = GrowingCareStores.memory();
      await s.stories.save(const ExplainerStory(id: 'a', title: 'Hidden story', pages: <String>['p'], updatedOn: '2026-11-08'));
      await s.stories.save(const ExplainerStory(id: 'b', title: 'Shown story', pages: <String>['p'], updatedOn: '2026-11-08', shownToHer: true));
      await _show(t, ExplainerStoriesScreen(reader: s.childExplainers()));
      expect(find.text('Shown story'), findsOneWidget);
      expect(find.text('Hidden story'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(Switch), findsNothing);
    });

    testWidgets('a story is read a page at a time with big Back and Next buttons and no "page n of m"', (t) async {
      const ExplainerStory st = ExplainerStory(id: 'a', title: 'The hospital', pages: <String>['First page.', 'Second page.'], updatedOn: '2026-11-08', shownToHer: true);
      await _show(t, const ExplainerPagerScreen(story: st));
      expect(find.text('First page.'), findsOneWidget);
      expect(t.getSize(find.byKey(const Key('storyNext'))).height, greaterThanOrEqualTo(64));
      expect(t.getSize(find.byKey(const Key('storyBack'))).height, greaterThanOrEqualTo(64));
      expect(t.widget<OutlinedButton>(find.byKey(const Key('storyBack'))).onPressed, isNull, reason: 'nothing before page one');
      await _tap(t, 'storyNext');
      expect(find.text('Second page.'), findsOneWidget);
      expect(find.textContaining(RegExp(r'\d+ of \d+|page \d', caseSensitive: false)), findsNothing);
      expect(find.text('All done'), findsOneWidget);
      await _tap(t, 'storyBack');
      expect(find.text('First page.'), findsOneWidget);
    });

    testWidgets('"All done" closes it; read-aloud is offered only when speech is wired, and speaks only the guardian\'s words', (t) async {
      final List<String> spoken = <String>[];
      const ExplainerStory st = ExplainerStory(id: 'a', title: 'T', pages: <String>['Only page.'], updatedOn: '2026-11-08', shownToHer: true);
      await _show(t, const ExplainerPagerScreen(story: st));
      expect(find.byKey(const Key('readAloud')), findsNothing);
      await t.pumpWidget(const SizedBox());
      await _show(t, ExplainerPagerScreen(story: st, speak: (String s) async => spoken.add(s)));
      await _tap(t, 'readAloud');
      expect(spoken, <String>['Only page.']);
    });

    test('her side imports no care screen and no care repository, and its source holds no care type', () {
      final String src = _strip('lib/child_explainer_screens.dart');
      for (final String banned in <String>[
        'care_screens.dart', 'CareBinder', 'HospitalNotes', 'AppointmentPrep', 'CareSection', 'CareContact', '.sections', '.hospital', '.preps',
      ]) {
        expect(src, isNot(contains(banned)), reason: 'child_explainer_screens.dart must not reach $banned');
      }
    });

    test('her shell files import no care screen, and name no care type', () {
      for (final String f in <String>['lib/child_home.dart', 'lib/child_more.dart', 'lib/child_explainer_screens.dart']) {
        final String src = _strip(f);
        for (final String banned in <String>[
          'care_screens.dart', 'CareBinderScreen', 'HospitalModeScreen', 'AppointmentPrepScreen', 'ExplainerAuthoringScreen',
          'HospitalNotes', 'AppointmentPrep(', 'CareSection', 'CareContact', 'GrowingCareHubScreen',
        ]) {
          expect(src, isNot(contains(banned)), reason: '$f must not reach $banned');
        }
      }
    });

    test('nothing in her screens says "settings" (the child shell has none)', () {
      for (final String f in <String>['lib/child_explainer_screens.dart', 'lib/growing_screens.dart']) {
        expect(RegExp('Settings|settings').hasMatch(_strip(f)), isFalse, reason: f);
      }
    });
  });

  group('appointment prep: a checklist and questions, nothing scheduled', () {
    testWidgets('empty, local, and says it sets no reminder', (t) async {
      await _show(t, AppointmentPrepScreen(stores: GrowingCareStores.memory(), now: _now));
      expect(find.byKey(const Key('prepEmpty')), findsOneWidget);
      expect(find.textContaining('sets no reminder and sends nothing'), findsOneWidget);
    });

    testWidgets('a list is written, ticked and kept; typed lines that were not yet added are kept on save', (t) async {
      final GrowingCareStores s = GrowingCareStores.memory();
      await _show(t, AppointmentPrepScreen(stores: s, now: _now));
      await _tap(t, 'addPrep');
      await _type(t, 'prepTitle', 'Check-up');
      await _type(t, 'newItem', 'Insurance card');
      await _tap(t, 'addItem');
      await t.tap(find.byType(CheckboxListTile).first);
      await t.pump();
      await _type(t, 'newQuestion', 'How long will it take?');
      await _tap(t, 'savePrep');
      final AppointmentPrep p = (await s.preps.list()).single;
      expect(p.title, 'Check-up');
      expect(p.checklist.single.text, 'Insurance card');
      expect(p.checklist.single.done, isTrue);
      expect(p.questions, <String>['How long will it take?']);
      expect(p.createdOn, '2026-11-08');
      expect(find.text('Check-up'), findsOneWidget);
    });

    testWidgets('refused: no title, a date that is not a date; nothing is kept', (t) async {
      final GrowingCareStores s = GrowingCareStores.memory();
      await _show(t, AppointmentPrepScreen(stores: s, now: _now));
      await _tap(t, 'addPrep');
      await _tap(t, 'savePrep');
      expect(find.text('There is nothing written yet.'), findsOneWidget);
      await _type(t, 'prepTitle', 'Visit');
      await t.enterText(find.descendant(of: find.byKey(const Key('prepDate')), matching: find.byType(TextField)), 'tuesday');
      await _tap(t, 'savePrep');
      expect(find.textContaining('not a real date'), findsOneWidget);
      expect(await s.preps.list(), isEmpty);
    });

    testWidgets('a list can be reopened and changed; lines and questions can be removed', (t) async {
      final GrowingCareStores s = GrowingCareStores.memory();
      await s.preps.save(const AppointmentPrep(
          id: 'a1', title: 'Dentist', createdOn: '2026-11-01', on: '2026-12-02',
          checklist: <PrepLine>[PrepLine('Card'), PrepLine('Drawing')], questions: <String>['Q one', 'Q two']));
      await _show(t, AppointmentPrepScreen(stores: s, now: _now));
      expect(find.text('2 Dec 2026'), findsOneWidget);
      await t.tap(find.text('Dentist'));
      await t.pumpAndSettle();
      await _tap(t, 'removeItem-0');
      await _tap(t, 'removeQuestion-1');
      await _tap(t, 'savePrep');
      final AppointmentPrep p = (await s.preps.get('a1'))!;
      expect(p.checklist.map((PrepLine l) => l.text), <String>['Drawing']);
      expect(p.questions, <String>['Q one']);
      expect(p.createdOn, '2026-11-01', reason: 'editing never rewrites when it was started');
    });

    testWidgets('removing a list asks first', (t) async {
      final GrowingCareStores s = GrowingCareStores.memory();
      await s.preps.save(const AppointmentPrep(id: 'a1', title: 'Dentist', createdOn: '2026-11-01'));
      await _show(t, AppointmentPrepScreen(stores: s, now: _now));
      await _tap(t, 'removePrep-a1');
      await _tap(t, 'confirmKeep');
      expect(await s.preps.list(), hasLength(1));
      await _tap(t, 'removePrep-a1');
      await _tap(t, 'confirmGo');
      expect(await s.preps.list(), isEmpty);
    });

    test('no scheduling, notification or network code exists in these suites', () {
      for (final String f in <String>[
        'lib/growing_care_logic.dart', 'lib/growing_care_store.dart', 'lib/growing_care_widgets.dart',
        'lib/growing_screens.dart', 'lib/care_screens.dart', 'lib/child_explainer_screens.dart',
      ]) {
        final String src = _strip(f);
        for (final String banned in <String>[
          "package:http", 'dart:io', 'WebSocket', 'firebase', 'flutter_local_notifications', 'scheduleNotification',
          'Timer.periodic', 'api_client', 'baseUrl', 'sessionToken', 'geolocator', 'latitude',
        ]) {
          expect(src, isNot(contains(banned)), reason: '$f must stay offline and local: found $banned');
        }
      }
    });
  });

  group('the Care hub and the Settings hub entry points', () {
    testWidgets('lists the four care entries, says only grown-ups see them, and opens each', (t) async {
      final GrowingCareStores s = GrowingCareStores.memory();
      await _show(t, GrowingCareHubScreen(care: true, stores: s));
      expect(find.textContaining('Only grown-ups see these'), findsOneWidget);
      for (final String k in <String>['hubCareBinder', 'hubHospitalMode', 'hubExplainers', 'hubAppointmentPrep']) {
        expect(find.byKey(Key(k)), findsOneWidget, reason: k);
      }
      await _tap(t, 'hubCareBinder');
      expect(find.byType(CareBinderScreen), findsOneWidget);
      await t.pageBack();
      await t.pumpAndSettle();
      await _tap(t, 'hubHospitalMode');
      expect(find.byType(HospitalModeScreen), findsOneWidget);
      await t.pageBack();
      await t.pumpAndSettle();
      await _tap(t, 'hubExplainers');
      expect(find.byType(ExplainerAuthoringScreen), findsOneWidget);
      await t.pageBack();
      await t.pumpAndSettle();
      await _tap(t, 'hubAppointmentPrep');
      expect(find.byType(AppointmentPrepScreen), findsOneWidget);
    });

    testWidgets('a suite switched off is not offered at all', (t) async {
      final GrowingCareStores s = GrowingCareStores.memory();
      await s.switches.setSuite('hospitalMode', false);
      await _show(t, GrowingCareHubScreen(care: true, stores: s));
      expect(find.byKey(const Key('hubHospitalMode')), findsNothing);
      expect(find.byKey(const Key('hubCareBinder')), findsOneWidget);
    });

    Future<void> openSettings(WidgetTester t) async {
      await _show(t, const GuardianMoreScreen(childName: 'Ivy', childAge: 6), size: const Size(800, 3200));
      await t.ensureVisible(find.byKey(const Key('moreSettings')));
      await t.tap(find.byKey(const Key('moreSettings')));
      await t.pumpAndSettle();
    }

    testWidgets('Settings, Her: "Growing" opens the Growing hub', (t) async {
      await openSettings(t);
      await _tap(t, 'settingsRow_growing');
      expect(find.byType(GrowingCareHubScreen), findsOneWidget);
      expect(find.byKey(const Key('hubTimeCapsule')), findsOneWidget);
    });

    testWidgets('Settings, Family: "Care" opens the Care hub', (t) async {
      await openSettings(t);
      await _tap(t, 'settingsRow_care');
      expect(find.byType(GrowingCareHubScreen), findsOneWidget);
      expect(find.byKey(const Key('hubCareBinder')), findsOneWidget);
    });

    testWidgets('the five Settings groups are unchanged', (t) async {
      await openSettings(t);
      for (final String g in <String>['HER', 'FAMILY', 'SAFETY', 'LEARN', 'ACCOUNT']) {
        expect(find.text(g), findsOneWidget, reason: g);
      }
    });
  });
}
