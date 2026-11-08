// ignore_for_file: avoid_dynamic_calls
// OLIVE BRANCH — colour of the day logic, parity with the TypeScript module.
//
// Every case below comes from packages/palette/test/colour_day_vectors.json,
// which tools/gen-colour-vectors.mjs generates from
// packages/palette/src/colour_day.ts. The Dart port (lib/colour_day_logic.dart)
// must give the same answers value for value, so the phone and the server can
// never disagree about which of two answers is the later one. Each vector is
// its own test, so a failure names the case.
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/colour_day_logic.dart';
import 'package:olive_client/palette_logic.dart';

final Map<String, dynamic> v = jsonDecode(
    File('../packages/palette/test/colour_day_vectors.json').readAsStringSync()) as Map<String, dynamic>;

void _same(Object? actual, Object? expected, String path) {
  if (expected is num && actual is num) {
    expect((actual - expected).abs() < 1e-9, isTrue, reason: '$path: $actual vs $expected');
  } else if (expected is Map<dynamic, dynamic>) {
    expect(actual, isA<Map<dynamic, dynamic>>(), reason: path);
    expect((actual as Map<dynamic, dynamic>).keys.toSet(), expected.keys.toSet(), reason: '$path keys');
    for (final k in expected.keys) {
      _same(actual[k], expected[k], '$path.$k');
    }
  } else if (expected is List<dynamic>) {
    expect(actual, isA<List<dynamic>>(), reason: path);
    expect((actual as List<dynamic>).length, expected.length, reason: '$path length');
    for (var i = 0; i < expected.length; i++) {
      _same(actual[i], expected[i], '$path[$i]');
    }
  } else {
    expect(actual, expected, reason: path);
  }
}

DayColour _day(Map<dynamic, dynamic> m) => DayColour.fromJson(m);
List<DayColour> _days(Object? l) => [for (final m in l as List<dynamic>) _day(m as Map<dynamic, dynamic>)];
Map<String, dynamic> _viewJson(ParentColourView? p) => {
  'label': p!.label, 'hex': p.hex, 'changedToday': p.changedToday, 'line': p.line};

Map<String, dynamic> _outcomeJson(MergeOutcome o) => o.ok
    ? {'ok': true, 'row': o.row!.toJson(), 'changed': o.changed, 'kept': o.kept}
    : {'ok': false, 'reason': o.reason};

void main() {
  group('constants', () {
    final c = v['constants'] as Map<String, dynamic>;
    test('art styles, pixel age, defaults, the twelve ids and the clamp limits match', () {
      expect(artStyles, c['artStyles']);
      expect(pixelMinAge, c['pixelMinAge']);
      expect(defaultArtStyle, c['defaultArtStyle']);
      _same(defaultArtSettings.toJson(), c['defaultArtSettings'], 'defaultArtSettings');
      expect([for (final s in palette) s.id], c['colourIds']);
      expect(maxAnswerAgeMs, c['maxAnswerAgeMs']);
      expect(maxClockSkewMs, c['maxClockSkewMs']);
      expect(windDownChoices, c['windDownChoices']);
    });
  });

  group('stylesForAge', () {
    for (final m in v['stylesForAge'] as List<dynamic>) {
      test('age ${m['age']}', () => expect(stylesForAge(m['age'] as int?), m['styles']));
    }
  });

  group('mergeArtSettings', () {
    var i = 0;
    for (final m in v['artPatches'] as List<dynamic>) {
      final n = i++;
      test('patch #$n ${jsonEncode(m['patch'])} at age ${m['age']}', () {
        final r = mergeArtSettings(defaultArtSettings, m['patch'], m['age'] as int?);
        final e = m['expect'] as Map<String, dynamic>;
        expect(r.ok, e['ok']);
        if (r.ok) {
          _same(r.settings!.toJson(), e['settings'], 'settings');
        } else {
          expect(r.reason, e['reason']);
        }
      });
    }
    for (final m in v['artPatchesFromNarrow'] as List<dynamic>) {
      test('from a narrowed set: ${jsonEncode(m['patch'])}', () {
        final cur = ArtSettings.fromJson(m['current'])!;
        final r = mergeArtSettings(cur, m['patch'], m['age'] as int?);
        final e = m['expect'] as Map<String, dynamic>;
        expect(r.ok, e['ok']);
        if (r.ok) {
          _same(r.settings!.toJson(), e['settings'], 'settings');
        } else {
          expect(r.reason, e['reason']);
        }
      });
    }
  });

  group('clampAnsweredAt', () {
    for (final m in v['clamp'] as List<dynamic>) {
      test('answered ${m['answered']}', () {
        expect(clampAnsweredAt(m['answered'], (m['nowMs'] as num).toInt()), m['expect']);
      });
    }
  });

  group('isLocalDate', () {
    for (final m in v['localDates'] as List<dynamic>) {
      test(jsonEncode(m['s']), () => expect(isLocalDate(m['s']), m['expect']));
    }
  });

  group('mergeDay', () {
    for (final m in v['merge'] as List<dynamic>) {
      test(m['name'] as String, () {
        final ex = m['existing'] == null ? null : _day(m['existing'] as Map<dynamic, dynamic>);
        final r = mergeDay(ex, _day(m['incoming'] as Map<dynamic, dynamic>));
        _same(_outcomeJson(r), m['expect'], 'outcome');
      });
    }
  });

  group('reading the days', () {
    test('currentDay', () {
      for (final m in v['currentDay'] as List<dynamic>) {
        final r = currentDay(_days(m['days']));
        _same(r?.toJson(), m['expect'], 'currentDay');
      }
    });
    test('colourToday', () {
      for (final m in v['colourToday'] as List<dynamic>) {
        final r = colourToday(_days(m['days']), m['localDate'] as String);
        _same(r?.toJson(), m['expect'], 'colourToday ${m['localDate']}');
      }
    });
    test('needsQuestion', () {
      for (final m in v['needsQuestion'] as List<dynamic>) {
        expect(needsQuestion(_days(m['days']), m['localDate'] as String, m['dailyQuestion'] as bool), m['expect']);
      }
    });
    test('deviceMatches', () {
      for (final m in v['deviceMatches'] as List<dynamic>) {
        final seen = m['seen'] as Map<dynamic, dynamic>?;
        expect(deviceMatches(_days(m['days']), m['localDate'] as String,
          seenColourId: seen?['colourId'] as String?), m['expect']);
      }
    });
    test('toChoices', () {
      for (final m in v['toChoices'] as List<dynamic>) {
        final r = toChoices(_days(m['days']));
        _same([for (final c in r) {'colourId': c.colourId, 'chosenAt': c.chosenAt, 'via': c.via}], m['expect'], 'choices');
      }
    });
    test('guardianView', () {
      for (final m in v['guardianView'] as List<dynamic>) {
        final r = guardianView(_days(m['days']), m['localDate'] as String);
        if (m['expect'] == null) {
          expect(r, isNull);
        } else {
          _same(_viewJson(r), m['expect'], 'guardianView');
        }
      }
    });
  });

  group('the play window', () {
    var i = 0;
    for (final m in v['checkWindow'] as List<dynamic>) {
      final n = i++;
      test('check #$n ${jsonEncode(m['input'])}', () {
        final r = checkPlayWindow(m['input']);
        final e = m['expect'] as Map<String, dynamic>;
        expect(r.ok, e['ok']);
        if (r.ok) {
          _same(r.window!.toJson(), e['window'], 'window');
        } else {
          expect(r.reason, e['reason']);
        }
      });
    }
    for (final m in v['windowState'] as List<dynamic>) {
      test('minute ${m['minute']} of ${jsonEncode(m['window'])}', () {
        expect(playWindowState(PlayWindow.fromJson(m['window']), m['minute'] as int), m['expect']);
      });
    }
    for (final m in v['windowLength'] as List<dynamic>) {
      test('length of ${jsonEncode(m['window'])}', () => expect(windowLength(PlayWindow.fromJson(m['window'])!), m['expect']));
    }
    for (final m in v['isLonger'] as List<dynamic>) {
      test('isLonger ${jsonEncode(m['prev'])} -> ${jsonEncode(m['next'])}', () {
        expect(isLonger(PlayWindow.fromJson(m['prev']), PlayWindow.fromJson(m['next'])!), m['expect']);
      });
    }
    for (final m in v['lines'] as List<dynamic>) {
      test('line for ${m['state']}', () => expect(playWindowLine(m['state'] as String), m['expect']));
    }
  });
}
