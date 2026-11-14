// OLIVE BRANCH — Family structure logic, parity with the TypeScript module.
//
// Every case below comes from packages/family-structure/test/vectors.json, which
// tools/gen-family-vectors.mjs generates from packages/family-structure/src/family.ts.
// The Dart port (lib/family_structure_logic.dart) must give the same answers, value
// for value, so what a guardian builds and what the child sees can never differ
// between the demo/server and the phone.
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/family_structure_logic.dart';

final Map<String, dynamic> v =
    jsonDecode(File('../packages/family-structure/test/vectors.json').readAsStringSync()) as Map<String, dynamic>;

FamilyStructure st(Object? j) => FamilyStructure.fromJson(j! as Map<String, Object?>);
Object? years(Object? y) => y == '__null__' ? null : y == '__nan__' ? double.nan : y;
Map<String, Object?> m(Object? o) => (o! as Map).cast<String, Object?>();
List<Object?> l(Object? o) => (o! as List).cast<Object?>();

void main() {
  group('band table and constants', () {
    test('the band table equals the TypeScript table, field for field', () {
      final List<Object?> expected = l(v['bandTable']);
      expect(bandTable.length, expected.length);
      for (int i = 0; i < expected.length; i++) {
        expect(bandTable[i].toJson(), expected[i], reason: 'band $i');
      }
    });
    test('constants equal the TypeScript constants', () {
      final Map<String, Object?> c = m(v['constants']);
      expect(<Object?>[maxHomes, maxPeople, maxLabel, maxHomeName, maxStoryPages, maxStoryPageChars, maxDateAheadDays, storyShownDays, farPlaceName],
          <Object?>[c['maxHomes'], c['maxPeople'], c['maxLabel'], c['maxHomeName'], c['maxStoryPages'], c['maxStoryPageChars'], c['maxDateAheadDays'], c['storyShownDays'], c['farPlaceName']]);
      expect(roles, c['roles']);
      expect(backgroundRoles, c['backgroundRoles']);
      expect(contactModes, c['contactModes']);
      expect(patterns, c['patterns']);
      expect(areas, c['areas']);
      expect(ageBands, c['bands']);
      expect(tileKeys, c['tileKeys']);
      expect(suiteKeys, c['suiteKeys']);
      expect(<Object?>[for (final (int, String) r in rungAges) <Object?>[r.$1, r.$2]],
          <Object?>[for (final Object? r in l(c['rungAges'])) <Object?>[m(r)['age'], m(r)['grant']]]);
    });
    test('bandForYears', () {
      for (final Object? c in l(v['bandForYears'])) {
        expect(bandForYears(years(m(c)['years'])), m(c)['out'], reason: '${m(c)['years']}');
      }
    });
    test('effectiveBand over every combination', () {
      for (final Object? c in l(v['effectiveBand'])) {
        final Map<String, Object?> k = m(c);
        expect(effectiveBand(k['natural']! as String, k['hold']! as bool, k['released'] as String?), k['out'], reason: '$k');
      }
    });
    test('rungsAt', () {
      for (final Object? c in l(v['rungsAt'])) {
        expect(rungsAt(years(m(c)['years'])), m(c)['out'], reason: '${m(c)['years']}');
      }
    });
    test('diffBands', () {
      for (final Object? c in l(v['diffs'])) {
        expect(diffBands(m(c)['from']! as String, m(c)['to']! as String), m(c)['out']);
      }
    });
  });

  group('deriveChildView', () {
    for (final Object? c in l(v['views'])) {
      final Map<String, Object?> k = m(c);
      test(k['name']! as String, () {
        final Map<String, Object?> opts = m(k['opts']);
        final Map<String, bool> suites = <String, bool>{
          for (final MapEntry<String, Object?> e in m(k['suites']).entries) e.key: e.value! as bool
        };
        final ChildView out = deriveChildView(st(k['structure']), k['band']! as String, suites,
            <String>[for (final Object? r in l(k['rungs'])) r! as String], today: opts['today'] as String?);
        expect(out.toJson(), k['out']);
      });
    }
  });

  group('who', () {
    for (final Object? c in l(v['canEdit'])) {
      final Map<String, Object?> k = m(c);
      test(k['name']! as String, () {
        final Map<String, Object?> p = m(k['principal']);
        final FamilyPrincipal pr = FamilyPrincipal(roleName: p['roleName'], userId: p['userId'], childId: p['childId']);
        expect(canEditStructure(pr), k['edit']);
        expect(canReadReleased(pr, 'c1'), k['read']);
        expect(canReadReleased(pr, 'c2'), k['readOther']);
      });
    }
    test('a null principal edits and reads nothing', () {
      expect(canEditStructure(null), isFalse);
      expect(canReadReleased(null, 'c1'), isFalse);
    });
  });

  group('ops: validation, bigness, apply, inverse', () {
    for (final Object? c in l(v['ops'])) {
      final Map<String, Object?> k = m(c);
      test(k['name']! as String, () {
        final FamilyStructure s = st(k['structure']);
        final Map<String, Object?> op = m(k['op']);
        final Verdict verdict = validateOp(s, op);
        final Map<String, Object?> ev = m(k['verdict']);
        expect(verdict.ok, ev['ok']);
        if (!verdict.ok) {
          expect(verdict.reason, ev['reason']);
          return;
        }
        final Map<String, Object?> full = withBefore(s, op);
        expect(isBigChange(full), k['big']);
        expect(defaultTiming(full).toJson(), k['recommended']);
        final FamilyStructure applied = applyOp(s, full);
        expect(applied.toJson(), k['applied']);
        expect(invertOp(full, applied), k['inverse']);
      });
    }
    for (final Object? c in l(v['persons'])) {
      final Map<String, Object?> k = m(c);
      test('person: ${k['name']}', () {
        final List<Home> homes = <Home>[for (final Object? h in l(k['homes'])) Home.fromJson(m(h))];
        final Verdict got = validatePerson(k['person'], homes);
        final Map<String, Object?> ev = m(k['verdict']);
        expect(got.ok, ev['ok']);
        if (!got.ok) expect(got.reason, ev['reason']);
      });
    }
  });

  group('timing', () {
    for (final Object? c in l(v['timing'])) {
      final Map<String, Object?> k = m(c);
      test('parseTiming ${jsonEncode(k['raw'])}', () {
        final TimingResult r = parseTiming(k['raw'], k['today']! as String);
        final Map<String, Object?> e = m(k['out']);
        expect(r.ok, e['ok']);
        if (r.ok) {
          expect(r.timing!.toJson(), e['timing']);
        } else {
          expect(r.reason, e['reason']);
        }
      });
    }
  });

  group('released versus intended (the fold)', () {
    for (final Object? c in l(v['folds'])) {
      final Map<String, Object?> k = m(c);
      test('today ${k['today']}, ${l(k['entries']).length} entries', () {
        final List<HistoryEntry> entries = <HistoryEntry>[for (final Object? e in l(k['entries'])) HistoryEntry.fromJson(m(e))];
        final String today = k['today']! as String;
        final FamilyStructure base = st(m(v['structures'])['family']);
        expect(foldReleased(base, entries, today).toJson(), k['released']);
        expect(foldIntended(base, entries).toJson(), k['intended']);
        expect(releasedIds(entries, today).toList()..sort(), k['releasedIds']);
        expect(<String>[for (final HistoryEntry e in pendingChanges(entries, today)) e.id], k['pending']);
      });
    }
  });

  group('stories, birthdays, preview', () {
    for (final Object? c in l(v['stories'])) {
      final Map<String, Object?> k = m(c);
      test('story: ${k['name']}', () {
        final Verdict got = validateStory(k['story']);
        expect(got.ok, m(k['verdict'])['ok']);
        if (!got.ok) expect(got.reason, m(k['verdict'])['reason']);
      });
    }
    for (final Object? c in l(v['birthdays'])) {
      final Map<String, Object?> k = m(c);
      test('birthday ${k['birthDate']} on ${k['today']}', () {
        final BirthdayInfo? info = birthdayInfo(k['birthDate'], k['today']);
        if (k['info'] == null) {
          expect(info, isNull);
          return;
        }
        expect(info!.toJson(), k['info']);
        expect(birthdayLineShown(info.sleepsUntil, true), k['line']);
        expect(birthdayLineShown(info.sleepsUntil, false), k['lineHidden']);
        expect(birthdayPreview(info, true, info.bandNow), k['preview']);
        expect(birthdayPreview(info, false, info.bandNow), k['previewNoHold']);
      });
    }
    test('previewChange', () {
      final Map<String, Object?> k = m(v['preview']);
      final Map<String, Object?> out = previewChange(st(m(v['structures'])['family']), m(k['op']),
          Timing.fromJson(m(k['timing'])), k['band']! as String, <String, bool>{}, <String>[], k['today']! as String);
      expect(out, k['out']);
    });
  });

  group('next exchange (Wave 5): a fact about the weekly shape, never about whose home (the rhythm has no anchor week)', () {
    // 2026-11-09 is a Monday.
    NextExchange? next(Rhythm r, [String today = '2026-11-09']) => nextExchange(r, today);
    test('the first date on or after today that is the exchange day', () {
      final NextExchange n = next(const Rhythm(pattern: 'alternating_weeks', exchangeDay: 5, exchangeTime: '18:00'))!;
      expect([n.date, n.dayIndex, n.time, n.daysAway], ['2026-11-13', 5, '18:00', 4]);
    });
    test('today counts when today is the exchange day', () {
      final NextExchange n = next(const Rhythm(pattern: '2-2-3', exchangeDay: 1))!;
      expect([n.date, n.daysAway, n.time], ['2026-11-09', 0, null]);
    });
    test('Sunday is 0, and a week can roll over a month and a year end', () {
      expect(next(const Rhythm(pattern: '2-2-3', exchangeDay: 0))!.date, '2026-11-15');
      expect(nextExchange(const Rhythm(pattern: '2-2-3', exchangeDay: 3), '2026-12-30')!.date, '2026-12-30');
      expect(nextExchange(const Rhythm(pattern: '2-2-3', exchangeDay: 2), '2026-12-30')!.date, '2027-01-05');
    });
    test('no pattern, no exchange day or a bad date gives nothing, never a guess', () {
      expect(next(const Rhythm()), isNull);
      expect(next(const Rhythm(pattern: '2-2-3')), isNull);
      expect(next(const Rhythm(pattern: '2-2-3', exchangeDay: 2), 'soon'), isNull);
    });
  });
}
