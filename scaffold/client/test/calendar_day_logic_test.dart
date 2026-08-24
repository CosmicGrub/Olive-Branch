// OLIVE BRANCH — calendar_day_logic.dart tests. §8.2, §8.2.4, §8.2.5, §8.4.
//
// Mirrors the TS suites' coverage of the slices this file ports:
// packages/phase3/src/phase3.ts (scheduleStrip), packages/messaging/src/
// pipeline.ts (openReceipt's phrase half), packages/calendar/src/calendar.ts
// (the whole-days date arithmetic behind sleepsUntilBirthday).
import 'package:flutter_test/flutter_test.dart';
import 'package:olive_client/calendar_day_logic.dart';

void main() {
  group('scheduleStrip — §8.2.2', () {
    const List<DayPartLite> parts = <DayPartLite>[
      DayPartLite(kind: 'asleep', startsLocal: '20:00', endsLocal: '06:30'),
      DayPartLite(kind: 'before_school', startsLocal: '07:00', endsLocal: '08:00'),
      DayPartLite(kind: 'school', startsLocal: '08:00', endsLocal: '15:00'),
    ];

    test('finds the segment containing "now" and flags the very next one', () {
      final List<StripSegment> segs = scheduleStrip(parts, '07:15');
      final StripSegment current = segs.firstWhere((StripSegment s) => s.current);
      expect(current.kind, 'before_school');
      final StripSegment next = segs.firstWhere((StripSegment s) => s.next);
      expect(next.kind, 'school');
    });

    test('an overnight span (asleep 20:00→06:30) is still detected as current', () {
      final List<StripSegment> segs = scheduleStrip(parts, '23:45');
      expect(segs.firstWhere((StripSegment s) => s.current).kind, 'asleep');
      final List<StripSegment> segsAfterMidnight = scheduleStrip(parts, '02:00');
      expect(segsAfterMidnight.firstWhere((StripSegment s) => s.current).kind, 'asleep');
    });

    test('"next" wraps from the last sorted segment back to the first', () {
      // Sorted by start time this list is [before_school, school, asleep] —
      // 21:00 sits inside 'asleep', the LAST sorted segment, so its "next"
      // must wrap around (mod length) back to the first: before_school.
      final List<StripSegment> segs = scheduleStrip(parts, '21:00');
      expect(segs.firstWhere((StripSegment s) => s.current).kind, 'asleep');
      final StripSegment next = segs.firstWhere((StripSegment s) => s.next);
      expect(next.kind, 'before_school');
    });

    test('label and glyph never drift apart for a known kind', () {
      final List<StripSegment> segs = scheduleStrip(parts, '07:15');
      final StripSegment school = segs.firstWhere((StripSegment s) => s.kind == 'school');
      expect(school.label, 'school');
      expect(school.icon, isNot(fallbackGlyph));
    });

    test('an unrecognised kind falls back honestly instead of guessing', () {
      expect(dayPartLabel('made_up_kind'), 'made up kind');
      expect(dayPartGlyph('made_up_kind'), fallbackGlyph);
    });

    // §8.4 gap-fallback — this `parts` list does NOT cover the full 24h
    // (asleep ends 06:30, before_school starts 07:00: a real gap sits
    // between them, same again 15:00→20:00). `nowLocal` landing in one of
    // those gaps is not a hypothetical: an edited or partial real family
    // schedule can leave a stretch of the day with no day-part at all.
    test('a "now" that falls in a genuine gap between parts is nobody\'s current segment', () {
      final List<StripSegment> segs = scheduleStrip(parts, '06:45');
      expect(segs.where((StripSegment s) => s.current), isEmpty,
        reason: '06:45 sits after asleep ends (06:30) and before before_school '
                'starts (07:00) — a real gap, not covered by any part');
      expect(segs.where((StripSegment s) => s.next), isEmpty,
        reason: 'nothing is "next" either when nothing is "current"');
    });

    test('currentSegment() is honestly null in a gap, never a fabricated pick', () {
      final List<StripSegment> gapSegs = scheduleStrip(parts, '16:00');
      expect(currentSegment(gapSegs), isNull);

      final List<StripSegment> coveredSegs = scheduleStrip(parts, '07:15');
      expect(currentSegment(coveredSegs)?.kind, 'before_school');
    });
  });

  group('formatTimeOfDay / minutesSinceMidnight', () {
    test('formats midnight, noon, and an afternoon time correctly', () {
      expect(formatTimeOfDay('00:00'), '12:00 AM');
      expect(formatTimeOfDay('12:00'), '12:00 PM');
      expect(formatTimeOfDay('07:04'), '7:04 AM');
      expect(formatTimeOfDay('19:30'), '7:30 PM');
    });

    test('round-trips through minutesSinceMidnight', () {
      expect(minutesSinceMidnight('07:04'), 424);
      expect(minutesSinceMidnight('00:00'), 0);
      expect(minutesSinceMidnight('23:59'), 1439);
    });
  });

  group('watchedReceiptPhrase — §8.2.4, her frame first', () {
    test('matches the exact MARKUP-quoted phrase shape with a day-part suffix', () {
      final String phrase = watchedReceiptPhrase(
        timeLabel: '7:04 AM', possessive: "Ivy's", dayPartKind: 'before_school');
      expect(phrase, "Watched at 7:04 AM Ivy's time — before school.");
    });

    test('drops the suffix cleanly when the day-part carries no context phrase', () {
      final String phrase = watchedReceiptPhrase(
        timeLabel: '2:00 PM', possessive: "Ivy's", dayPartKind: 'free');
      expect(phrase, "Watched at 2:00 PM Ivy's time.");
      expect(phrase, isNot(contains('—')));
    });

    test('drops the suffix cleanly when no day-part is known at all', () {
      final String phrase = watchedReceiptPhrase(timeLabel: '2:00 PM', possessive: "Ivy's");
      expect(phrase, "Watched at 2:00 PM Ivy's time.");
    });

    test('never mentions a zone abbreviation or a raw offset — her frame only', () {
      final String phrase = watchedReceiptPhrase(
        timeLabel: '7:04 AM', possessive: "Ivy's", dayPartKind: 'dinner');
      expect(phrase, isNot(contains('UTC')));
      expect(phrase, isNot(matches(RegExp(r'[+-]\d'))));
    });
  });

  group('sleepsBetween / isoDateOnly — §8.2.5, sleeps not dates', () {
    test('counts whole days between two ISO dates', () {
      expect(sleepsBetween('2026-08-04', '2026-08-07'), 3);
      expect(sleepsBetween('2026-08-04', '2026-08-04'), 0);
    });

    test('is stable across a month boundary', () {
      expect(sleepsBetween('2026-08-30', '2026-09-02'), 3);
    });

    test('isoDateOnly is the exact inverse used to build demo fixtures', () {
      expect(isoDateOnly(DateTime.utc(2026, 8, 4)), '2026-08-04');
      expect(isoDateOnly(DateTime.utc(2026, 1, 5)), '2026-01-05');
    });
  });

  group('demoDayParts — the one shared schedule primitive', () {
    test('covers all 24 hours with no gaps and no overlaps', () {
      // Every minute of the day resolves to exactly one current segment.
      for (int m = 0; m < 24 * 60; m += 15) {
        final String hhmm =
            '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
        final List<StripSegment> segs = scheduleStrip(demoDayParts, hhmm);
        expect(segs.where((StripSegment s) => s.current).length, 1,
          reason: 'exactly one current segment at $hhmm');
      }
    });
  });
}
