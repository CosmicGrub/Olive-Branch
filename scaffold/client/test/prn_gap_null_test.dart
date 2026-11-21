// OLIVE BRANCH - a PRN (as-needed) medicine with NO minimum gap keeps no gap (ISS-095). The client used to invent a
// 4-hour gap whenever the server's value was null, and quoted "at least 4 hours" back to a parent as if somebody had set
// it. A gap is a clinical number: it comes from the person who set it, or it is absent, and when it is absent nothing
// checks it, nothing quotes it, and nothing defaults to it.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:olive_client/care_local.dart';
import 'package:olive_client/care_profile_logic.dart';
import 'package:olive_client/meds_care.dart';

Future<void> pump(WidgetTester t, Widget w) async {
  await t.binding.setSurfaceSize(const Size(800, 2400));
  addTearDown(() => t.binding.setSurfaceSize(null));
  await t.pumpWidget(MaterialApp(home: w));
  await t.pumpAndSettle();
}

MockClient server({required Object? gap, Map<String, Object?>? doseReply, int doseStatus = 201, List<http.Request>? posts}) =>
    MockClient((http.Request req) async {
      if (req.url.path == '/v1/auth/dev-login') return http.Response(jsonEncode(<String, Object?>{'token': 'tok'}), 200);
      if (req.method == 'POST') {
        posts?.add(req);
        return http.Response(jsonEncode(doseReply ?? <String, Object?>{
          'id': 'd1', 'medicationId': 'm1', 'localDate': '2026-08-04', 'slot': 'prn',
          'administeredAt': '2026-08-04T12:00:00.000Z', 'status': 'given',
        }), doseStatus);
      }
      if (req.url.path.endsWith('/medications')) {
        return http.Response(jsonEncode(<String, Object?>{
          'localDate': '2026-08-04',
          'medications': <Object?>[
            <String, Object?>{'id': 'm1', 'name': 'Reliever', 'dose': 'as written', 'slots': <String>['prn'], 'isPrn': true, 'minGapHours': gap},
          ],
          'doses': <dynamic>[],
        }), 200);
      }
      return http.Response(jsonEncode(<String, Object?>{'allergies': <String>[], 'conditions': <String>[]}), 200);
    });

void main() {
  group('the dose check', () {
    final DateTime now = DateTime.utc(2026, 11, 20, 12);
    final List<DoseRecord> justGiven = <DoseRecord>[
      DoseRecord(medicationId: 'm1', localDate: '2026-11-20', slot: 'prn', administeredAt: now.subtract(const Duration(minutes: 5)),
          byUserName: 'Mum', status: DoseStatus.given),
    ];

    test('with NO minimum gap, a dose five minutes after another is not refused', () {
      final DoseCheck c = checkDose(const MedicationRule(slots: <String>['prn'], isPrn: true), 'prn', DoseStatus.given, now, '2026-11-20', justGiven);
      expect(c.ok, true);
      expect(c.refusal, isNull);
    });

    test('with an explicit minimum gap, the same dose IS refused (the rule still works when somebody set it)', () {
      final DoseCheck c = checkDose(const MedicationRule(slots: <String>['prn'], isPrn: true, minGapHours: 4), 'prn', DoseStatus.given, now, '2026-11-20', justGiven);
      expect(c.refusal, DoseRefusal.tooSoon);
    });

    test('a gap of zero is "no gap" too, not a refusal', () {
      expect(checkDose(const MedicationRule(slots: <String>['prn'], isPrn: true, minGapHours: 0), 'prn', DoseStatus.given, now, '2026-11-20', justGiven).ok, true);
    });
  });

  group('the meds screen (server path)', () {
    testWidgets('a PRN medicine with a null gap: logging twice in a row raises no "too soon" and quotes no hours', (t) async {
      final List<http.Request> posts = <http.Request>[];
      await pump(t, MedsCareScreen(baseUrl: 'http://api.test', guardianId: 'g', childId: 'c', httpClient: server(gap: null, posts: posts)));
      await t.tap(find.widgetWithText(OutlinedButton, 'Log PRN dose'));
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(OutlinedButton, 'Log PRN dose'));
      await t.pumpAndSettle();
      expect(posts.length, 2, reason: 'the client does not hold the second dose back');
      expect(find.textContaining('Too soon'), findsNothing);
      expect(find.textContaining('hours'), findsNothing);
      expect(find.textContaining('4'), findsNothing, reason: 'no invented 4-hour default anywhere on screen');
    });

    testWidgets('a server refusal for a medicine with no gap quotes no invented number', (t) async {
      await pump(t, MedsCareScreen(baseUrl: 'http://api.test', guardianId: 'g', childId: 'c',
          httpClient: server(gap: null, doseStatus: 409, doseReply: <String, Object?>{'error': 'too_soon'})));
      await t.tap(find.widgetWithText(OutlinedButton, 'Log PRN dose'));
      await t.pumpAndSettle();
      expect(find.text('Too soon for another Reliever dose.'), findsOneWidget);
      expect(find.textContaining('hours'), findsNothing);
      expect(find.textContaining('a few'), findsNothing);
    });

    testWidgets('a server refusal that DOES carry a gap quotes the server\'s number', (t) async {
      await pump(t, MedsCareScreen(baseUrl: 'http://api.test', guardianId: 'g', childId: 'c',
          httpClient: server(gap: 6, doseStatus: 409, doseReply: <String, Object?>{'error': 'too_soon', 'minGapHours': 6})));
      await t.tap(find.widgetWithText(OutlinedButton, 'Log PRN dose'));
      await t.pumpAndSettle();
      expect(find.textContaining('wait at least 6 hours'), findsOneWidget);
    });
  });

  group('the local medicine list', () {
    test('a new as-needed medicine has no gap', () {
      const CareMedication m = CareMedication(id: 'm1', name: 'Reliever', kind: MedKind.prn);
      expect(m.gapHours, isNull);
      expect(m.toJson()['gap'], isNull);
    });

    test('stored data with no gap (or junk) reads back as no gap, never 4', () {
      expect(CareMedication.tryFromJson(<String, Object?>{'id': 'm1', 'name': 'Reliever', 'kind': 'prn'})!.gapHours, isNull);
      expect(CareMedication.tryFromJson(<String, Object?>{'id': 'm1', 'name': 'Reliever', 'kind': 'prn', 'gap': 'soon'})!.gapHours, isNull);
      expect(CareMedication.tryFromJson(<String, Object?>{'id': 'm1', 'name': 'Reliever', 'kind': 'prn', 'gap': 99})!.gapHours, isNull);
    });

    test('a gap somebody set is kept exactly', () {
      expect(CareMedication.tryFromJson(<String, Object?>{'id': 'm1', 'name': 'Reliever', 'kind': 'prn', 'gap': 6})!.gapHours, 6);
    });

    test('medState with no gap: a recent dose does not start a gap clock', () {
      final DateTime now = DateTime.utc(2026, 11, 20, 12);
      final CareMedication m = CareMedication(
        id: 'm1', name: 'Reliever', kind: MedKind.prn,
        doses: <CareDose>[CareDose(at: now.subtract(const Duration(minutes: 1)), byId: 'g', byName: 'Mum')],
      );
      final MedState s = medState(m, now);
      expect(s.given, false);
      expect(s.next, isNull);
      expect(s.last, isNotNull);
    });

    test('medState with a gap set still holds the gap', () {
      final DateTime now = DateTime.utc(2026, 11, 20, 12);
      final CareMedication m = CareMedication(
        id: 'm1', name: 'Reliever', kind: MedKind.prn, gapHours: 4,
        doses: <CareDose>[CareDose(at: now.subtract(const Duration(minutes: 1)), byId: 'g', byName: 'Mum')],
      );
      expect(medState(m, now).given, true);
      expect(medState(m, now).next, isNotNull);
    });

    test('the care-profile line says "when needed" and quotes no gap when none is set', () {
      const CareDoc doc = CareDoc(meds: <CareMedication>[CareMedication(id: 'm1', name: 'Reliever', kind: MedKind.prn)]);
      final String schedule = cpMedicineLines(doc).single.schedule;
      expect(schedule, 'when needed');
      expect(cpMedicineLines(const CareDoc(meds: <CareMedication>[CareMedication(id: 'm1', name: 'Reliever', kind: MedKind.prn, gapHours: 6)])).single.schedule,
          contains('6 hour gap'));
    });
  });
}
