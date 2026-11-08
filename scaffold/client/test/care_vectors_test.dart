// OLIVE BRANCH — medication safety rules, parity with the TypeScript engine.
// Verified by CI. UNVERIFIED on a device; this file runs headless.
//
// Every case below comes from packages/care/test/vectors.json, which
// tools/gen-care-vectors.mjs generates from packages/care/src/care.ts (the care
// suite fails CI if the engine and the file disagree). The Dart port in
// lib/meds_care.dart must give the same answers, so the server's refusal and
// the offline client's refusal of a dose can never differ (S-D6). `atLocal`, a
// zone-abbreviated clock string, is not asserted: the client has no timezone
// database. Each vector is its own test, so a failure names the case.
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/meds_care.dart';

final Map<String, dynamic> v =
    jsonDecode(File('../packages/care/test/vectors.json').readAsStringSync()) as Map<String, dynamic>;

DoseStatus _status(String s) => DoseStatus.values.firstWhere((DoseStatus x) => x.name == s);

DoseRecord _record(Map<String, dynamic> m) => DoseRecord(
  medicationId: m['medicationId'] as String, localDate: m['localDate'] as String,
  slot: m['slot'] as String, administeredAt: DateTime.parse(m['administeredAt'] as String),
  byUserName: m['byUserName'] as String, status: _status(m['status'] as String));

MedicationRule _rule(Map<String, dynamic> m) => MedicationRule(
  slots: (m['slots'] as List<dynamic>).cast<String>(), isPrn: m['isPrn'] as bool,
  minGapHours: (m['minGapHours'] as num?)?.toDouble(), maxPer24h: m['maxPer24h'] as int?);

String _reasonName(DoseRefusal r) => switch (r) {
      DoseRefusal.unknownSlot => 'unknown_slot',
      DoseRefusal.alreadyAdministered => 'already_administered',
      DoseRefusal.tooSoon => 'too_soon',
      DoseRefusal.dailyMax => 'daily_max',
    };

void main() {
  group('checkDose — slot validation, double-dose guard, PRN gap and daily cap (S-D6)', () {
    final List<Map<String, dynamic>> cases =
        (v['checkDose'] as List<dynamic>).cast<Map<String, dynamic>>();
    for (int i = 0; i < cases.length; i++) {
      final Map<String, dynamic> c = cases[i];
      test('#$i ${c['label']}', () {
        final DoseCheck r = checkDose(
          _rule(c['med'] as Map<String, dynamic>), c['slot'] as String, _status(c['status'] as String),
          DateTime.parse(c['at'] as String), c['localDate'] as String,
          (c['history'] as List<dynamic>).map((dynamic h) => _record(h as Map<String, dynamic>)).toList());
        final Map<String, dynamic> e = c['expect'] as Map<String, dynamic>;
        expect(r.ok, e['ok']);
        if (r.ok) {
          expect(r.slot, e['slot']);
        } else {
          expect(_reasonName(r.refusal!), e['reason']);
          if (e['allowed'] != null) expect(r.allowed, (e['allowed'] as List<dynamic>).cast<String>());
          if (e['by'] != null) expect(r.by, e['by']);
          if (e['max'] != null) expect(r.max, e['max']);
          if (e['minGapHours'] != null) expect(r.minGapHours, (e['minGapHours'] as num).toDouble());
          if (e['nextAllowedAt'] != null) {
            expect(r.nextAllowedAt!.toUtc().toIso8601String(), e['nextAllowedAt']);
          }
        }
      });
    }
  });

  group('prnAllowed — only given doses start the clock, gap checked both sides', () {
    final List<Map<String, dynamic>> cases =
        (v['prnAllowed'] as List<dynamic>).cast<Map<String, dynamic>>();
    for (int i = 0; i < cases.length; i++) {
      final Map<String, dynamic> c = cases[i];
      test('#$i at ${c['at']} gap ${c['minGapHours']}h', () {
        final bool r = prnAllowed(
          (c['existing'] as List<dynamic>).map((dynamic h) => _record(h as Map<String, dynamic>)).toList(),
          c['medicationId'] as String, DateTime.parse(c['at'] as String),
          (c['minGapHours'] as num).toDouble());
        expect(r, c['expect']);
      });
    }
  });
}
