// OLIVE BRANCH — custody schedule, parity with the TypeScript engine.
// Verified by CI. UNVERIFIED on a device; this file runs headless.
//
// Every case below comes from packages/custody/test/vectors.json, which
// tools/gen-custody-vectors.mjs generates from packages/custody/src/schedule.ts
// (the TS suite fails CI if the engine and the file disagree). The Dart port in
// lib/exchange_screen.dart must give the same answers value for value, so the
// guardian's phone and the server cannot disagree about whose day it is — the
// S-D7 (new-year holiday window), S-D8 (side at a wall-clock moment) and S-D9
// (sleeps stop at effectiveTo) rules in particular. Each vector is its own
// test, so a failure names the case.
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/exchange_screen.dart';

final Map<String, dynamic> v =
    jsonDecode(File('../packages/custody/test/vectors.json').readAsStringSync()) as Map<String, dynamic>;

Side _side(String s) => s == 'A' ? Side.a : Side.b;
String _sideName(Side s) => s == Side.a ? 'A' : 'B';
DateTime _date(String iso) => DateTime.parse('${iso}T00:00:00Z');
String _iso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

Order _order(String name) {
  final Map<String, dynamic> o = (v['orders'] as Map<String, dynamic>)[name] as Map<String, dynamic>;
  return Order(
    pattern: (o['cycle'] as List<dynamic>).map((dynamic s) => _side(s as String)).toList(),
    anchorLocalDate: _date(o['anchorLocalDate'] as String),
    holidays: (o['holidays'] as List<dynamic>).map((dynamic h) {
      final Map<String, dynamic> m = h as Map<String, dynamic>;
      return HolidayRule(
        name: m['name'] as String, startMonthDay: m['startMonthDay'] as String,
        endMonthDay: m['endMonthDay'] as String, evenYearSide: _side(m['evenYearSide'] as String),
        priority: m['priority'] as int);
    }).toList(),
    orderTimeLabel: '',
    exchangeTime: o['exchangeTime'] as String,
    effectiveFrom: o['effectiveFrom'] as String?,
    effectiveTo: o['effectiveTo'] as String?,
  );
}

void main() {
  group('sideOn — pattern + holiday override, incl. the new-year window (S-D7)', () {
    final List<Map<String, dynamic>> cases =
        (v['sideOn'] as List<dynamic>).cast<Map<String, dynamic>>();
    for (final Map<String, dynamic> c in cases) {
      test('${c['order']} ${c['date']}', () {
        final ({Side side, String source, String? holidayName}) r =
            sideOn(_order(c['order'] as String), _date(c['date'] as String));
        final Map<String, dynamic> e = c['expect'] as Map<String, dynamic>;
        expect(_sideName(r.side), e['side']);
        expect(r.source, e['source']);
        expect(r.holidayName, e['holidayName']);
      });
    }
  });

  group('blocks — contiguous runs, clipped to the effective range', () {
    final List<Map<String, dynamic>> cases =
        (v['blocks'] as List<dynamic>).cast<Map<String, dynamic>>();
    for (int i = 0; i < cases.length; i++) {
      final Map<String, dynamic> c = cases[i];
      test('#$i ${c['order']} ${c['from']}..${c['to']}', () {
        final List<Block> got =
            blocks(_order(c['order'] as String), _date(c['from'] as String), _date(c['to'] as String));
        final List<dynamic> want = c['expect'] as List<dynamic>;
        expect(got.length, want.length);
        for (int j = 0; j < want.length; j++) {
          final Map<String, dynamic> w = want[j] as Map<String, dynamic>;
          expect(_sideName(got[j].side), w['side'], reason: 'block $j side');
          expect(_iso(got[j].startLocalDate), w['start'], reason: 'block $j start');
          expect(_iso(got[j].endLocalDate), w['end'], reason: 'block $j end');
          expect(got[j].source, w['source'], reason: 'block $j source');
          expect(got[j].holidayName, w['holidayName'], reason: 'block $j holiday');
        }
      });
    }
  });

  group('sleepsUntilSideChange — stops at effectiveTo, or answers from the successor (S-D9)', () {
    final List<Map<String, dynamic>> cases =
        (v['sleeps'] as List<dynamic>).cast<Map<String, dynamic>>();
    for (int i = 0; i < cases.length; i++) {
      final Map<String, dynamic> c = cases[i];
      test('#$i ${c['order']} from ${c['today']} successor=${c['successor']}', () {
        final String? succ = c['successor'] as String?;
        final ({int sleeps, Side nextSide, DateTime onLocalDate})? r = sleepsUntilSideChange(
          _order(c['order'] as String), _date(c['today'] as String),
          successor: succ == null ? null : _order(succ));
        final Map<String, dynamic>? e = c['expect'] as Map<String, dynamic>?;
        if (e == null) {
          expect(r, isNull);
        } else {
          expect(r, isNotNull);
          expect(r!.sleeps, e['sleeps']);
          expect(_sideName(r.nextSide), e['nextSide']);
          expect(_iso(r.onLocalDate), e['onLocalDate']);
        }
      });
    }
  });

  group('sideAtOrderLocal — who holds her at a wall-clock moment (S-D8)', () {
    final List<Map<String, dynamic>> cases =
        (v['sideAtOrderLocal'] as List<dynamic>).cast<Map<String, dynamic>>();
    for (final Map<String, dynamic> c in cases) {
      test('${c['order']} ${c['date']} ${c['hhmm']}', () {
        final ({Side side, String source, String? holidayName})? r =
            sideAtOrderLocal(_order(c['order'] as String), _date(c['date'] as String), c['hhmm'] as String);
        final Map<String, dynamic>? e = c['expect'] as Map<String, dynamic>?;
        if (e == null) {
          expect(r, isNull);
        } else {
          expect(r, isNotNull);
          expect(_sideName(r!.side), e['side']);
          expect(r.source, e['source']);
          expect(r.holidayName, e['holidayName']);
        }
      });
    }
  });
}
