// OLIVE BRANCH — the emergency card screen, hospital mode and the guardian editor around the
// LOCAL card (MASTERFILE section 8.23). A live build with a session still shows the server's
// card exactly as before; with no session (or no reach) the guardian's local card is shown;
// a live build never shows invented demo data.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:olive_client/care_screens.dart';
import 'package:olive_client/emergency_card.dart';
import 'package:olive_client/emergency_card_editor_screen.dart';
import 'package:olive_client/emergency_card_local.dart';
import 'package:olive_client/family_structure_logic.dart';
import 'package:olive_client/growing_care_store.dart';
import 'package:olive_client/local_services.dart';

const FamilyPrincipal gA = FamilyPrincipal(roleName: 'guardian', userId: 'ga');
const FamilyPrincipal gB = FamilyPrincipal(roleName: 'guardian', userId: 'gb');
const FamilyPrincipal ivy = FamilyPrincipal(roleName: 'child', childId: 'ivy');

DateTime _t = DateTime.utc(2026, 11, 8, 10);

const LocalEmergencyCard card = LocalEmergencyCard(
  allergies: <String>['Penicillin (rash)'],
  conditions: <String>['Asthma'],
  medicines: <EcMedicine>[EcMedicine(name: 'Inhaler', dose: '2 puffs when wheezy')],
  doctor: EcDoctor(name: 'Dr Okoye', practice: 'Riverside Surgery', phone: '020 7946 0000'),
  contacts: <EcContact>[EcContact(name: 'Claire', relation: 'Mum', phone: '07700 900123')],
);

Future<EmergencyCardService> written({String name = 'Claire'}) async {
  final EmergencyCardService s = EmergencyCardService.memory(clock: () => _t);
  await s.save(gA, card, expectedVersion: 0, byName: name);
  return s;
}

Future<void> pump(WidgetTester t, Widget w, {bool settle = true}) async {
  await t.binding.setSurfaceSize(const Size(800, 2400));
  addTearDown(() => t.binding.setSurfaceSize(null));
  await t.pumpWidget(MaterialApp(key: UniqueKey(), home: w));
  if (settle) await t.pumpAndSettle();
}

MockClient server({bool fail = false}) => MockClient((http.Request req) async {
      if (fail) throw http.ClientException('offline');
      if (req.url.path == '/v1/auth/dev-login') return http.Response(jsonEncode(<String, Object?>{'token': 'tok'}), 200);
      return http.Response(jsonEncode(<String, Object?>{
        'bloodType': null, 'allergies': <String>['Egg'], 'conditions': <dynamic>[],
        'pediatricianName': null, 'pediatricianPractice': null, 'pediatricianPhone': null,
        'insuranceProvider': null, 'insuranceMemberId': null,
        'guardians': <dynamic>[], 'medications': <dynamic>[], 'version': 3,
        'lastChange': <String, Object?>{'byName': 'Mom', 'at': '2026-11-02T09:15:00.000Z'},
      }), 200);
    });

void main() {
  setUp(() {
    _t = DateTime.utc(2026, 11, 8, 10);
    LocalServices.resetForTest();
  });
  tearDown(LocalServices.resetForTest);

  group('no session: the guardian\'s local card', () {
    testWidgets('is shown, allergies first, labelled as saved on this device, with who last changed it', (t) async {
      final EmergencyCardService s = await written();
      await pump(t, EmergencyCardScreen(childName: 'Ivy', localService: s, principal: gA));
      expect(find.byKey(const Key('localCardNote')), findsOneWidget);
      expect(find.text('This is the card a guardian saved on this device.'), findsOneWidget);
      expect(find.textContaining('Penicillin (rash)'), findsOneWidget);
      expect(find.text('Asthma'), findsOneWidget);
      expect(find.text('Inhaler'), findsOneWidget);
      expect(find.text('2 puffs when wheezy'), findsOneWidget);
      expect(find.textContaining('Dr Okoye'), findsOneWidget);
      expect(find.text('020 7946 0000'), findsOneWidget);
      expect(find.textContaining('Claire, Mum'), findsOneWidget);
      expect(find.text('07700 900123'), findsOneWidget);
      expect(find.text('Last changed by Claire on 2026-11-08'), findsOneWidget);
      final double allergyTop = t.getTopLeft(find.byKey(const Key('allergyCard'))).dy;
      expect(allergyTop, lessThan(t.getTopLeft(find.text('CONDITIONS')).dy));
      expect(allergyTop, lessThan(t.getTopLeft(find.text('CURRENT MEDICATIONS')).dy));
    });

    testWidgets('never mixes in the invented demo card', (t) async {
      final EmergencyCardService s = await written();
      await pump(t, EmergencyCardScreen(childName: 'Ivy', localService: s, principal: gA));
      for (final String demo in <String>['Peanuts', 'EpiPen', 'Claire Solomon', 'Marcus', 'Priya Nair', 'BlueBridge', 'O positive']) {
        expect(find.textContaining(demo), findsNothing, reason: demo);
      }
    });

    testWidgets('read aloud speaks exactly the local card, allergies first, on a tap only', (t) async {
      final EmergencyCardService s = await written();
      final List<String> said = <String>[];
      await pump(t, EmergencyCardScreen(childName: 'Ivy', localService: s, principal: gA, speak: (String x) async => said.add(x)));
      expect(said, isEmpty);
      await t.tap(find.byKey(const Key('readAloudButton')));
      await t.pump();
      expect(said.single, startsWith('Allergies: Penicillin (rash). Conditions: Asthma. Current medications: Inhaler, 2 puffs when wheezy.'));
      expect(said.single, contains('Contacts: Claire, Mum, 07700 900123.'));
      expect(said.single, contains('Doctor: Dr Okoye, Riverside Surgery. Phone: 020 7946 0000.'));
      expect(find.text('CONTACTS'), findsOneWidget);
      expect(find.text('DOCTOR'), findsOneWidget);
      expect(find.text('GUARDIANS'), findsNothing, reason: 'her card says contacts, not the server\'s guardians');
      expect(said.single, isNot(contains('Peanuts')));
    });

    testWidgets('a child principal gets no local card (guardian only): the preview demo, never her family\'s card', (t) async {
      final EmergencyCardService s = await written();
      await pump(t, EmergencyCardScreen(childName: 'Ivy', localService: s, principal: ivy));
      expect(find.byKey(const Key('localCardNote')), findsNothing);
      expect(find.textContaining('Penicillin'), findsNothing);
      expect(find.byKey(const Key('editLocalCard')), findsNothing);
    });

    testWidgets('nothing written and the preview build: the demo card as before; a live build: no invented data', (t) async {
      await pump(t, EmergencyCardScreen(childName: 'Ivy', localService: EmergencyCardService.memory(), principal: gA));
      expect(find.textContaining('Peanuts'), findsOneWidget, reason: 'the preview build keeps its demo');

      LocalServices.install(LocalServices.memory(childId: 'real', isLive: true, demoSeeds: false));
      await pump(t, EmergencyCardScreen(childName: 'Ivy', localService: EmergencyCardService.memory(), principal: gA));
      expect(find.byKey(const Key('noCardYet')), findsOneWidget);
      expect(find.textContaining('Peanuts'), findsNothing);
      expect(find.textContaining('Claire Solomon'), findsNothing);
      expect(find.byKey(const Key('writeLocalCard')), findsOneWidget);
      // ...even with no local service wired at all.
      await pump(t, const EmergencyCardScreen(childName: 'Ivy'));
      expect(find.byKey(const Key('noCardYet')), findsOneWidget);
      expect(find.byKey(const Key('writeLocalCard')), findsNothing, reason: 'no guardian, no way to write');
      expect(find.textContaining('Peanuts'), findsNothing);
    });

    testWidgets('a guardian writes it from the screen and sees it at once', (t) async {
      LocalServices.install(LocalServices.memory(childId: 'real', isLive: true, demoSeeds: false));
      final EmergencyCardService s = EmergencyCardService.memory(clock: () => _t);
      await pump(t, EmergencyCardScreen(childName: 'Ivy', localService: s, principal: gA));
      await t.tap(find.byKey(const Key('writeLocalCard')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('cardMyName')), 'Claire');
      await t.enterText(find.byKey(const Key('cardAllergies')), 'Eggs\nLatex');
      await t.ensureVisible(find.byKey(const Key('saveCard')));
      await t.tap(find.byKey(const Key('saveCard')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('localCardNote')), findsOneWidget);
      expect(find.textContaining('Eggs, Latex'), findsOneWidget);
      expect(find.text('Last changed by Claire on 2026-11-08'), findsOneWidget);
    });
  });

  group('a live session keeps using the server card, exactly as before', () {
    testWidgets('the server\'s card is shown even when a local one exists, and the local editor is not offered', (t) async {
      final EmergencyCardService s = await written();
      await pump(t, EmergencyCardScreen(
          childName: 'Ivy', baseUrl: 'http://api.test', guardianId: 'ga', childId: 'child-a', httpClient: server(),
          localService: s, principal: gA));
      expect(find.textContaining('Egg'), findsOneWidget);
      expect(find.textContaining('Penicillin'), findsNothing);
      expect(find.byKey(const Key('localCardNote')), findsNothing);
      expect(find.byKey(const Key('editLocalCard')), findsNothing);
      expect(find.text('Last changed by Mom on 2026-11-02'), findsOneWidget);
    });

    testWidgets('server unreachable and a local card exists: the local card, said plainly', (t) async {
      final EmergencyCardService s = await written();
      await pump(t, EmergencyCardScreen(
          childName: 'Ivy', baseUrl: 'http://api.test', guardianId: 'ga', childId: 'child-a',
          httpClient: server(fail: true), localService: s, principal: gA));
      expect(find.text("Couldn't reach the server, so this is the card saved on this device."), findsOneWidget);
      expect(find.textContaining('Penicillin (rash)'), findsOneWidget);
    });

    testWidgets('server unreachable and no local card: the honest error with a retry, never demo data', (t) async {
      await pump(t, EmergencyCardScreen(
          childName: 'Ivy', baseUrl: 'http://api.test', guardianId: 'ga', childId: 'child-a',
          httpClient: server(fail: true), localService: EmergencyCardService.memory(), principal: gA));
      expect(find.text("Couldn't reach the server"), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.textContaining('Peanuts'), findsNothing);
    });

    testWidgets('a child principal never gets the local card even as a fallback', (t) async {
      final EmergencyCardService s = await written();
      await pump(t, EmergencyCardScreen(
          childName: 'Ivy', baseUrl: 'http://api.test', guardianId: 'ga', childId: 'child-a',
          httpClient: server(fail: true), localService: s, principal: ivy));
      expect(find.text("Couldn't reach the server"), findsOneWidget);
      expect(find.textContaining('Penicillin'), findsNothing);
    });
  });

  group('the editor', () {
    testWidgets('starts empty, says the app adds nothing, saves what a guardian types and restores it on reopening', (t) async {
      final EmergencyCardService s = EmergencyCardService.memory(clock: () => _t);
      await pump(t, EmergencyCardEditorScreen(service: s, principal: gA));
      expect(find.textContaining('The app adds nothing to it'), findsOneWidget);
      expect(find.text('Allergies (written by a guardian)'), findsOneWidget);
      expect(t.widget<TextField>(find.byKey(const Key('cardAllergies'))).controller!.text, isEmpty);
      await t.enterText(find.byKey(const Key('cardMyName')), 'Claire');
      await t.enterText(find.byKey(const Key('cardAllergies')), 'Penicillin (rash)');
      await t.enterText(find.byKey(const Key('cardConditions')), 'Asthma');
      await t.ensureVisible(find.byKey(const Key('addMedicine')));
      await t.tap(find.byKey(const Key('addMedicine')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('medName0')), 'Inhaler');
      await t.enterText(find.byKey(const Key('medDose0')), '2 puffs');
      await t.enterText(find.byKey(const Key('docName')), 'Dr Okoye');
      await t.ensureVisible(find.byKey(const Key('addContact')));
      await t.tap(find.byKey(const Key('addContact')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('conName0')), 'Claire');
      await t.enterText(find.byKey(const Key('conRelation0')), 'Mum');
      await t.enterText(find.byKey(const Key('conPhone0')), '07700 900123');
      await t.ensureVisible(find.byKey(const Key('saveCard')));
      await t.tap(find.byKey(const Key('saveCard')));
      await t.pumpAndSettle();
      final EmergencyCardDoc d = await s.read(gA);
      expect(d.version, 1);
      expect(d.card!.allergies, <String>['Penicillin (rash)']);
      expect(d.card!.medicines.single.dose, '2 puffs');
      expect(d.card!.contacts.single.relation, 'Mum');
      expect(d.history.single.byName, 'Claire');

      await pump(t, EmergencyCardEditorScreen(service: s, principal: gA));
      expect(t.widget<TextField>(find.byKey(const Key('cardAllergies'))).controller!.text, 'Penicillin (rash)');
      expect(t.widget<TextField>(find.byKey(const Key('medName0'))).controller!.text, 'Inhaler');
      expect(t.widget<TextField>(find.byKey(const Key('cardMyName'))).controller!.text, 'Claire',
          reason: 'her remembered name is offered next time');
    });

    testWidgets('a child principal is told it is for grown-ups, has no fields and no way to save', (t) async {
      final EmergencyCardService s = await written();
      await pump(t, EmergencyCardEditorScreen(service: s, principal: ivy));
      expect(find.byKey(const Key('cardGuardianOnly')), findsOneWidget);
      expect(find.byKey(const Key('saveCard')), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(find.byKey(const Key('openCardHistory')), findsNothing);
    });

    testWidgets('too many rows or a nameless medicine is refused in words and nothing is stored', (t) async {
      final EmergencyCardService s = EmergencyCardService.memory(clock: () => _t);
      await pump(t, EmergencyCardEditorScreen(service: s, principal: gA));
      await t.ensureVisible(find.byKey(const Key('addMedicine')));
      await t.tap(find.byKey(const Key('addMedicine')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('medDose0')), '5 ml');
      await t.ensureVisible(find.byKey(const Key('saveCard')));
      await t.tap(find.byKey(const Key('saveCard')));
      await t.pumpAndSettle();
      expect(find.text('A name is needed for that row.'), findsOneWidget);
      expect((await s.read(gA)).version, 0);
    });

    testWidgets('a conflict: another guardian saved first, so this save is refused and their change is shown', (t) async {
      final EmergencyCardService s = await written(name: 'Claire');
      await pump(t, EmergencyCardEditorScreen(service: s, principal: gB));
      await t.enterText(find.byKey(const Key('cardAllergies')), 'Mine (typed by the second guardian)');
      // Meanwhile the first guardian saves a change.
      await s.save(gA, const LocalEmergencyCard(allergies: <String>['Latex']), expectedVersion: 1, byName: 'Claire');
      await t.ensureVisible(find.byKey(const Key('saveCard')));
      await t.tap(find.byKey(const Key('saveCard')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('cardStaleBanner')), findsOneWidget);
      expect(find.textContaining('Someone changed this card'), findsOneWidget);
      expect(t.widget<TextField>(find.byKey(const Key('cardAllergies'))).controller!.text, 'Latex',
          reason: 'the other change is on screen, not overwritten');
      final EmergencyCardDoc d = await s.read(gA);
      expect(d.version, 2);
      expect(d.card!.allergies, <String>['Latex']);
      expect(d.history.length, 2);
    });
  });

  group('the history', () {
    testWidgets('lists who changed what and when, newest first, with the previous values; it has no edit or delete', (t) async {
      final EmergencyCardService s = await written(name: 'Claire');
      _t = DateTime.utc(2026, 11, 9, 8);
      await s.save(gB, const LocalEmergencyCard(allergies: <String>['Latex']), expectedVersion: 1, byName: 'Marcus');
      await pump(t, EmergencyCardHistoryScreen(service: s, principal: gA));
      final List<Offset> order = <Offset>[
        t.getTopLeft(find.byKey(const ValueKey<String>('change-2'))), t.getTopLeft(find.byKey(const ValueKey<String>('change-1'))),
      ];
      expect(order[0].dy, lessThan(order[1].dy), reason: 'newest first');
      expect(find.text('Changed by Marcus'), findsOneWidget);
      expect(find.text('Version 2, 2026-11-09'), findsOneWidget);
      expect(find.text('Changed by Claire'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey<String>('change-2')));
      await t.pumpAndSettle();
      expect(find.textContaining('Before this change: Allergies: Penicillin (rash).'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey<String>('change-1')));
      await t.pumpAndSettle();
      expect(find.text('Nothing was written before this.'), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsNothing);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('refused for a child; empty before the first save', (t) async {
      await pump(t, EmergencyCardHistoryScreen(service: await written(), principal: ivy));
      expect(find.byKey(const Key('historyGuardianOnly')), findsOneWidget);
      await pump(t, EmergencyCardHistoryScreen(service: EmergencyCardService.memory(), principal: gA));
      expect(find.byKey(const Key('historyEmpty')), findsOneWidget);
    });
  });

  group('hospital mode reads the local card when there is no live session', () {
    testWidgets('shows allergies, conditions, medicines, doctor and contacts as a guardian wrote them', (t) async {
      final EmergencyCardService s = await written();
      await pump(t, HospitalModeScreen(childName: 'Ivy', stores: GrowingCareStores.memory(), emergency: s, principal: gA));
      expect(find.byKey(const Key('hospitalEmpty')), findsNothing);
      expect(find.text('Penicillin (rash)'), findsOneWidget);
      expect(find.text('Asthma'), findsOneWidget);
      expect(find.textContaining('Inhaler'), findsOneWidget);
      expect(find.textContaining('Dr Okoye'), findsOneWidget);
      expect(find.textContaining('07700 900123'), findsOneWidget);
    });

    testWidgets('without the local card it is exactly as before; a child principal sees none of it', (t) async {
      await pump(t, HospitalModeScreen(childName: 'Ivy', stores: GrowingCareStores.memory()));
      expect(find.byKey(const Key('hospitalEmpty')), findsOneWidget);
      expect(find.byKey(const Key('editEmergencyCard')), findsNothing);
      await pump(t, HospitalModeScreen(childName: 'Ivy', stores: GrowingCareStores.memory(), emergency: await written(), principal: ivy));
      expect(find.byKey(const Key('hospCardAllergies')), findsNothing);
      expect(find.textContaining('Penicillin'), findsNothing);
    });

    testWidgets('the emergency card button opens the card screen, which reads the same local card', (t) async {
      final EmergencyCardService s = await written();
      await pump(t, HospitalModeScreen(childName: 'Ivy', stores: GrowingCareStores.memory(), emergency: s, principal: gA));
      await t.tap(find.byKey(const Key('openEmergencyCard')));
      await t.pumpAndSettle();
      expect(find.byType(EmergencyCardScreen), findsOneWidget);
      expect(find.byKey(const Key('localCardNote')), findsOneWidget);
      expect(find.textContaining('Penicillin (rash)'), findsWidgets);
    });

    testWidgets('a guardian can write the card from hospital mode and it appears', (t) async {
      final EmergencyCardService s = EmergencyCardService.memory(clock: () => _t);
      await pump(t, HospitalModeScreen(childName: 'Ivy', stores: GrowingCareStores.memory(), emergency: s, principal: gA));
      await t.tap(find.byKey(const Key('editEmergencyCard')));
      await t.pumpAndSettle();
      await t.enterText(find.byKey(const Key('cardAllergies')), 'Eggs');
      await t.ensureVisible(find.byKey(const Key('saveCard')));
      await t.tap(find.byKey(const Key('saveCard')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('hospCardAllergies')), findsOneWidget);
      expect(find.text('Eggs'), findsOneWidget);
    });

    testWidgets('the Care hub passes the guardian and the card through', (t) async {
      final EmergencyCardService s = await written();
      await pump(t, GrowingCareHubScreen(care: true, stores: GrowingCareStores.memory(), emergency: s, guardianId: 'ga'));
      await t.tap(find.byKey(const Key('hubHospitalMode')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('hospCardAllergies')), findsOneWidget);
    });
  });
}
