// OLIVE BRANCH - the three-state allergy field (ISS-094): unknown by default, "none" only when a named guardian confirmed it
// on a date, entries as written. Screen, read-aloud and export tests for EACH state, on every surface that shows allergies:
// the emergency card (local and server), the meds screen, the local card's spoken text and the doctor sheet.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:olive_client/allergy_field.dart';
import 'package:olive_client/care_profile_logic.dart';
import 'package:olive_client/care_screens.dart' show HospitalModeScreen;
import 'package:olive_client/emergency_card.dart';
import 'package:olive_client/emergency_card_editor_screen.dart';
import 'package:olive_client/emergency_card_local.dart';
import 'package:olive_client/family_structure_logic.dart';
import 'package:olive_client/growing_care_store.dart';
import 'package:olive_client/local_services.dart';
import 'package:olive_client/meds_care.dart';

const FamilyPrincipal gA = FamilyPrincipal(roleName: 'guardian', userId: 'ga');
const AllergyNone none = AllergyNone(by: 'Claire', on: '2026-11-20');

Future<void> pump(WidgetTester t, Widget w) async {
  await t.binding.setSurfaceSize(const Size(800, 2400));
  addTearDown(() => t.binding.setSurfaceSize(null));
  await t.pumpWidget(MaterialApp(key: UniqueKey(), home: w));
  await t.pumpAndSettle();
}

/// A server card: [allergies] and optionally a confirmed-none block.
MockClient server(List<String> allergies, {Map<String, Object?>? confirmed}) => MockClient((http.Request req) async {
      if (req.url.path == '/v1/auth/dev-login') return http.Response(jsonEncode(<String, Object?>{'token': 'tok'}), 200);
      if (req.url.path.endsWith('/medications')) {
        return http.Response(jsonEncode(<String, Object?>{'medications': <dynamic>[], 'doses': <dynamic>[], 'localDate': '2026-11-20'}), 200);
      }
      return http.Response(jsonEncode(<String, Object?>{
        'bloodType': null, 'allergies': allergies, 'conditions': <dynamic>[],
        'pediatricianName': null, 'pediatricianPractice': null, 'pediatricianPhone': null,
        'insuranceProvider': null, 'insuranceMemberId': null,
        'guardians': <dynamic>[], 'medications': <dynamic>[], 'version': 1,
        'allergyNoneConfirmed': ?confirmed,
      }), 200);
    });

Future<EmergencyCardService> serviceWith(LocalEmergencyCard c) async {
  final EmergencyCardService s = EmergencyCardService.memory(clock: () => DateTime.utc(2026, 11, 20, 10));
  await s.save(gA, c, expectedVersion: 0, byName: 'Claire');
  return s;
}

String allergyCardText(WidgetTester t) {
  final Finder texts = find.descendant(of: find.byKey(const Key('allergyCard')), matching: find.byType(Text));
  return texts.evaluate().map((Element e) => (e.widget as Text).data ?? '').join(' | ');
}

void main() {
  setUp(LocalServices.resetForTest);
  tearDown(LocalServices.resetForTest);

  group('the pure field', () {
    test('no entries and no confirmation is UNKNOWN, and says Not recorded', () {
      expect(allergyState(const <String>[], null), AllergyState.unknown);
      expect(allergyDisplay(const <String>[], null), 'Not recorded');
      expect(allergySpoken(const <String>[], null), 'Allergies: not recorded. ');
      expect(allergyExportLine(const <String>[], null), 'Allergies: Not recorded');
    });

    test('blank entries are still unknown (whitespace is not an answer)', () {
      expect(allergyState(const <String>['', '   '], null), AllergyState.unknown);
      expect(allergyDisplay(const <String>[' '], null), 'Not recorded');
    });

    test('a complete confirmation by a named guardian on a date is CONFIRMED NONE and names both', () {
      expect(allergyState(const <String>[], none), AllergyState.confirmedNone);
      expect(allergyDisplay(const <String>[], none), 'None. Confirmed by Claire on 2026-11-20');
      expect(allergySpoken(const <String>[], none), 'Allergies: none. Confirmed by Claire on 2026-11-20. ');
      expect(allergyExportLine(const <String>[], none), 'Allergies: None. Confirmed by Claire on 2026-11-20');
    });

    test('an incomplete confirmation (no name, or no real date) is NOT a confirmation', () {
      expect(allergyState(const <String>[], const AllergyNone(by: '', on: '2026-11-20')), AllergyState.unknown);
      expect(allergyState(const <String>[], const AllergyNone(by: 'Claire', on: 'yesterday')), AllergyState.unknown);
      expect(allergyDisplay(const <String>[], const AllergyNone(by: ' ', on: '2026-11-20')), 'Not recorded');
    });

    test('entries win over a confirmation: the two never contradict', () {
      expect(allergyState(const <String>['Peanuts'], none), AllergyState.entries);
      expect(allergyDisplay(const <String>['Peanuts', 'Egg'], none), 'Peanuts, Egg');
      expect(allergySpoken(const <String>['Peanuts', 'Egg'], none), 'Allergies: Peanuts. Egg. ');
      expect(allergyExportLine(const <String>['Peanuts', 'Egg'], none), 'Allergies: Peanuts; Egg');
    });

    test('the confirmation reads back tolerantly: junk is no confirmation, never "none"', () {
      expect(AllergyNone.tryFromJson(null), isNull);
      expect(AllergyNone.tryFromJson('none'), isNull);
      expect(AllergyNone.tryFromJson(<String, Object?>{'by': 'Claire'}), isNull);
      expect(AllergyNone.tryFromJson(<String, Object?>{'by': 'Claire', 'on': '2026-11-20'}), none);
      expect(allergyNoneFromServer(<String, dynamic>{'allergies': <String>[]}), isNull);
      expect(allergyNoneFromServer(<String, dynamic>{'allergyNoneConfirmed': <String, Object?>{'by': 'Claire', 'on': '2026-11-20'}}), none);
    });

    test('"Not recorded" says neither "none" nor "no known" nor "clear"', () {
      expect(kAllergiesNotRecorded.toLowerCase().contains(RegExp(r'\bnone\b|\bno known\b|\bclear\b|\bno allergies\b')), isFalse);
    });
  });

  group('the local card model', () {
    test('a new card is unknown; spokenText starts "Allergies: not recorded."', () {
      const LocalEmergencyCard c = LocalEmergencyCard(conditions: <String>['Asthma']);
      expect(c.allergyKind, AllergyState.unknown);
      expect(c.spokenText(), startsWith('Allergies: not recorded. '));
      expect(c.spokenText(), isNot(contains('No allergies')));
    });

    test('confirmed none is spoken with the name and the date', () {
      const LocalEmergencyCard c = LocalEmergencyCard(allergyNone: none, conditions: <String>['Asthma']);
      expect(c.allergyKind, AllergyState.confirmedNone);
      expect(c.spokenText(), startsWith('Allergies: none. Confirmed by Claire on 2026-11-20. '));
    });

    test('entries are spoken as written', () {
      const LocalEmergencyCard c = LocalEmergencyCard(allergies: <String>['Penicillin (rash)']);
      expect(c.spokenText(), startsWith('Allergies: Penicillin (rash).'));
    });

    test('a card holding only a confirmation is not "empty" (it says something)', () {
      expect(const LocalEmergencyCard(allergyNone: none).isEmpty, isFalse);
      expect(const LocalEmergencyCard().isEmpty, isTrue);
    });

    test('JSON: a card with no confirmation is byte for byte what it always was; one with it round-trips', () {
      expect(const LocalEmergencyCard(allergies: <String>['Egg']).toJson().containsKey('allergyNone'), isFalse);
      final LocalEmergencyCard back = LocalEmergencyCard.fromJson(jsonDecode(jsonEncode(const LocalEmergencyCard(allergyNone: none).toJson())));
      expect(back.allergyNone, none);
      expect(back.allergyKind, AllergyState.confirmedNone);
    });

    test('JSON: a stored confirmation beside entries is dropped on read (entries win)', () {
      final LocalEmergencyCard c = LocalEmergencyCard.fromJson(<String, Object?>{
        'allergies': <String>['Egg'], 'allergyNone': <String, Object?>{'by': 'Claire', 'on': '2026-11-20'}});
      expect(c.allergyNone, isNull);
      expect(c.allergyKind, AllergyState.entries);
    });

    test('checkedCard: none without a name is refused; none beside entries is dropped; a good one is kept', () {
      expect(() => checkedCard(const LocalEmergencyCard(allergyNone: AllergyNone(by: '', on: '2026-11-20'))), throwsA(isA<EcRefused>()));
      expect(checkedCard(const LocalEmergencyCard(allergies: <String>['Egg'], allergyNone: none)).allergyNone, isNull);
      expect(checkedCard(const LocalEmergencyCard(allergyNone: none)).allergyNone, none);
      expect(ecRefusalText('none_needs_name'), contains('add your name'));
    });
  });

  group('the emergency card screen shows each state', () {
    testWidgets('UNKNOWN (a local card with no allergy line): "Not recorded", never "None"', (t) async {
      final EmergencyCardService s = await serviceWith(const LocalEmergencyCard(conditions: <String>['Asthma']));
      await pump(t, EmergencyCardScreen(childName: 'Ivy', localService: s, principal: gA));
      expect(allergyCardText(t), contains('Not recorded'));
      expect(find.textContaining('None on file'), findsNothing);
      expect(find.textContaining('None.'), findsNothing);
    });

    testWidgets('CONFIRMED NONE: says none, who confirmed it and when', (t) async {
      final EmergencyCardService s = await serviceWith(const LocalEmergencyCard(allergyNone: none, conditions: <String>['Asthma']));
      await pump(t, EmergencyCardScreen(childName: 'Ivy', localService: s, principal: gA));
      expect(allergyCardText(t), contains('None. Confirmed by Claire on 2026-11-20'));
      expect(allergyCardText(t), isNot(contains('Not recorded')));
    });

    testWidgets('ENTRIES: the guardian\'s own words', (t) async {
      final EmergencyCardService s = await serviceWith(const LocalEmergencyCard(allergies: <String>['Penicillin (rash)']));
      await pump(t, EmergencyCardScreen(childName: 'Ivy', localService: s, principal: gA));
      expect(allergyCardText(t), contains('Penicillin (rash)'));
      expect(allergyCardText(t), isNot(contains('Not recorded')));
    });

    testWidgets('SERVER card with an empty list reads "Not recorded" (the old "None on file" is gone)', (t) async {
      await pump(t, EmergencyCardScreen(childName: 'Ivy', baseUrl: 'https://example.test', guardianId: 'g', childId: 'c', httpClient: server(<String>[])));
      expect(allergyCardText(t), contains('Not recorded'));
      expect(find.textContaining('None on file'), findsNothing);
    });

    testWidgets('SERVER card with a confirmed-none block shows who and when', (t) async {
      await pump(t, EmergencyCardScreen(childName: 'Ivy', baseUrl: 'https://example.test', guardianId: 'g', childId: 'c',
          httpClient: server(<String>[], confirmed: <String, Object?>{'by': 'Claire', 'on': '2026-11-20'})));
      expect(allergyCardText(t), contains('None. Confirmed by Claire on 2026-11-20'));
    });

    testWidgets('SERVER card with entries shows them', (t) async {
      await pump(t, EmergencyCardScreen(childName: 'Ivy', baseUrl: 'https://example.test', guardianId: 'g', childId: 'c', httpClient: server(<String>['Egg'])));
      expect(allergyCardText(t), contains('Egg'));
    });
  });

  group('read aloud, for each state', () {
    Future<String> spokenFor(WidgetTester t, Widget Function(Future<void> Function(String)) build) async {
      final List<String> spoken = <String>[];
      await pump(t, build((String s) async => spoken.add(s)));
      await t.tap(find.byKey(const Key('readAloudButton')));
      await t.pump();
      expect(spoken, hasLength(1));
      return spoken.single;
    }

    testWidgets('UNKNOWN is spoken as "not recorded", first', (t) async {
      final EmergencyCardService s = await serviceWith(const LocalEmergencyCard(conditions: <String>['Asthma']));
      final String text = await spokenFor(t, (speak) => EmergencyCardScreen(localService: s, principal: gA, speak: speak));
      expect(text, startsWith('Allergies: not recorded.'));
      expect(text, isNot(contains('No allergies')));
      expect(text, isNot(contains('none')));
    });

    testWidgets('CONFIRMED NONE is spoken with the name and the date', (t) async {
      final EmergencyCardService s = await serviceWith(const LocalEmergencyCard(allergyNone: none, conditions: <String>['Asthma']));
      final String text = await spokenFor(t, (speak) => EmergencyCardScreen(localService: s, principal: gA, speak: speak));
      expect(text, startsWith('Allergies: none. Confirmed by Claire on 2026-11-20.'));
    });

    testWidgets('ENTRIES are spoken as written', (t) async {
      final EmergencyCardService s = await serviceWith(const LocalEmergencyCard(allergies: <String>['Egg', 'Penicillin']));
      final String text = await spokenFor(t, (speak) => EmergencyCardScreen(localService: s, principal: gA, speak: speak));
      expect(text, startsWith('Allergies: Egg. Penicillin.'));
    });

    testWidgets('SERVER card, empty list: "not recorded" (never "No allergies on file")', (t) async {
      final String text = await spokenFor(t, (speak) => EmergencyCardScreen(baseUrl: 'https://example.test', guardianId: 'g', childId: 'c',
          httpClient: server(<String>[]), speak: speak));
      expect(text, startsWith('Allergies: not recorded.'));
      expect(text, isNot(contains('No allergies')));
    });
  });

  group('the meds screen shows each state', () {
    testWidgets('UNKNOWN: Not recorded', (t) async {
      await pump(t, MedsCareScreen(baseUrl: 'https://example.test', guardianId: 'g', childId: 'c', httpClient: server(<String>[])));
      expect(find.byKey(const Key('medsAllergies')), findsOneWidget);
      expect((t.widget(find.byKey(const Key('medsAllergies'))) as Text).data, 'Not recorded');
    });

    testWidgets('CONFIRMED NONE: names who and when', (t) async {
      await pump(t, MedsCareScreen(baseUrl: 'https://example.test', guardianId: 'g', childId: 'c',
          httpClient: server(<String>[], confirmed: <String, Object?>{'by': 'Claire', 'on': '2026-11-20'})));
      expect((t.widget(find.byKey(const Key('medsAllergies'))) as Text).data, 'None. Confirmed by Claire on 2026-11-20');
    });

    testWidgets('ENTRIES: as written', (t) async {
      await pump(t, MedsCareScreen(baseUrl: 'https://example.test', guardianId: 'g', childId: 'c', httpClient: server(<String>['Egg', 'Soy'])));
      expect((t.widget(find.byKey(const Key('medsAllergies'))) as Text).data, 'Egg\nSoy');
    });

    testWidgets('a screen with nothing loaded (no demo content) says Not recorded, not nothing', (t) async {
      await pump(t, const MedsCareScreen());
      expect((t.widget(find.byKey(const Key('medsAllergies'))) as Text).data, 'Not recorded');
    });
  });

  group('the export (doctor sheet)', () {
    final DateTime now = DateTime.utc(2026, 11, 20, 12);
    String sheet(LocalEmergencyCard? card) => cpDoctorSheetText(childName: 'Mia', doc: const CareProfileDoc(), card: card, now: now);

    test('UNKNOWN: an allergy line is still there, and says Not recorded', () {
      expect(sheet(const LocalEmergencyCard(conditions: <String>['Asthma'])), contains('Allergies: Not recorded'));
    });

    test('NO CARD AT ALL: the sheet still has the line (leaving it out would read as "none")', () {
      expect(sheet(null), contains('Allergies: Not recorded'));
      expect(sheet(const LocalEmergencyCard()), contains('Allergies: Not recorded'));
    });

    test('CONFIRMED NONE: names who and when', () {
      expect(sheet(const LocalEmergencyCard(allergyNone: none)), contains('Allergies: None. Confirmed by Claire on 2026-11-20'));
    });

    test('ENTRIES: as written, joined', () {
      expect(sheet(const LocalEmergencyCard(allergies: <String>['Egg', 'Soy'])), contains('Allergies: Egg; Soy'));
    });
  });

  group('hospital mode (the card block)', () {
    testWidgets('UNKNOWN: shows Not recorded', (t) async {
      final EmergencyCardService s = await serviceWith(const LocalEmergencyCard(conditions: <String>['Asthma']));
      await pump(t, HospitalModeScreen(childName: 'Ivy', stores: GrowingCareStores.memory(), emergency: s, principal: gA));
      expect(find.text('Not recorded'), findsOneWidget);
      expect(find.byKey(const Key('hospCardAllergies')), findsOneWidget);
    });

    testWidgets('CONFIRMED NONE: shows who and when', (t) async {
      final EmergencyCardService s = await serviceWith(const LocalEmergencyCard(allergyNone: none, conditions: <String>['Asthma']));
      await pump(t, HospitalModeScreen(childName: 'Ivy', stores: GrowingCareStores.memory(), emergency: s, principal: gA));
      expect(find.text('None. Confirmed by Claire on 2026-11-20'), findsOneWidget);
    });
  });

  group('the editor', () {
    testWidgets('ticking "No known allergies" saves a confirmation with the name and today\'s date; unticked stays Not recorded', (t) async {
      final EmergencyCardService s = EmergencyCardService.memory();
      await pump(t, EmergencyCardEditorScreen(service: s, principal: gA));
      await t.enterText(find.byKey(const Key('cardMyName')), 'Claire');
      await t.enterText(find.byKey(const Key('docName')), 'Dr Okoye'); // something else on the card, so it is not blank
      expect(find.byKey(const Key('cardAllergyNoneNote')), findsOneWidget);
      expect((t.widget(find.byKey(const Key('cardAllergyNoneNote'))) as Text).data, contains('Not recorded'));
      await t.tap(find.byKey(const Key('cardAllergyNone')));
      await t.pump();
      await t.tap(find.byKey(const Key('saveCard')));
      await t.pumpAndSettle();
      final LocalEmergencyCard c = (await s.read(gA)).card!;
      expect(c.allergyKind, AllergyState.confirmedNone);
      expect(c.allergyNone!.by, 'Claire');
      expect(RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(c.allergyNone!.on), isTrue);
    });

    testWidgets('left unticked the saved card is unknown (never "none" by default)', (t) async {
      final EmergencyCardService s = EmergencyCardService.memory();
      await pump(t, EmergencyCardEditorScreen(service: s, principal: gA));
      await t.enterText(find.byKey(const Key('cardMyName')), 'Claire');
      await t.enterText(find.byKey(const Key('docName')), 'Dr Okoye');
      await t.tap(find.byKey(const Key('saveCard')));
      await t.pumpAndSettle();
      final LocalEmergencyCard c = (await s.read(gA)).card!;
      expect(c.allergyKind, AllergyState.unknown);
      expect(c.allergyNone, isNull);
    });

    testWidgets('ticking it with no name is refused, and nothing is saved', (t) async {
      final EmergencyCardService s = EmergencyCardService.memory();
      await pump(t, EmergencyCardEditorScreen(service: s, principal: gA));
      await t.tap(find.byKey(const Key('cardAllergyNone')));
      await t.pump();
      await t.tap(find.byKey(const Key('saveCard')));
      await t.pumpAndSettle();
      expect(find.textContaining('add your name'), findsOneWidget);
      expect((await s.read(gA)).card, isNull);
    });

    testWidgets('typing an allergy disables the box and the saved card has entries and no confirmation', (t) async {
      final EmergencyCardService s = await serviceWith(const LocalEmergencyCard(allergyNone: none));
      await pump(t, EmergencyCardEditorScreen(service: s, principal: gA));
      expect(t.widget<CheckboxListTile>(find.byKey(const Key('cardAllergyNone'))).value, isTrue);
      await t.enterText(find.byKey(const Key('cardAllergies')), 'Egg');
      await t.pump();
      expect(t.widget<CheckboxListTile>(find.byKey(const Key('cardAllergyNone'))).onChanged, isNull);
      await t.tap(find.byKey(const Key('saveCard')));
      await t.pumpAndSettle();
      final LocalEmergencyCard c = (await s.read(gA)).card!;
      expect(c.allergies, <String>['Egg']);
      expect(c.allergyNone, isNull);
    });

    testWidgets('typing an allergy and erasing it again leaves the box unticked and the card saved without a confirmation', (t) async {
      final EmergencyCardService s = await serviceWith(const LocalEmergencyCard(allergyNone: none, conditions: <String>['Asthma']));
      await pump(t, EmergencyCardEditorScreen(service: s, principal: gA));
      await t.enterText(find.byKey(const Key('cardAllergies')), 'Penicillin');
      await t.pump();
      await t.enterText(find.byKey(const Key('cardAllergies')), '');
      await t.pump();
      final CheckboxListTile box = t.widget<CheckboxListTile>(find.byKey(const Key('cardAllergyNone')));
      expect(box.value, isFalse, reason: 'an unreviewed empty list must not turn back into "confirmed none"');
      expect(box.onChanged, isNotNull);
      await t.tap(find.byKey(const Key('saveCard')));
      await t.pumpAndSettle();
      final LocalEmergencyCard c = (await s.read(gA)).card!;
      expect(c.allergies, isEmpty);
      expect(c.allergyNone, isNull);
    });

    testWidgets('an existing confirmation is kept as it was (name and date) when the box stays ticked', (t) async {
      final EmergencyCardService s = await serviceWith(const LocalEmergencyCard(allergyNone: none, conditions: <String>['Asthma']));
      await pump(t, EmergencyCardEditorScreen(service: s, principal: gA));
      await t.enterText(find.byKey(const Key('cardMyName')), 'Someone Else');
      await t.enterText(find.byKey(const Key('docName')), 'Dr Okoye');
      await t.tap(find.byKey(const Key('saveCard')));
      await t.pumpAndSettle();
      expect((await s.read(gA)).card!.allergyNone, none);
    });
  });
}
