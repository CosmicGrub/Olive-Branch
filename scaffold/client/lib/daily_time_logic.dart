// OLIVE BRANCH — daily time on HER device: the pure rules. No longer UNVERIFIED —
// verified by CI (client/test/daily_time_test.dart). MASTERFILE §8.6.6, §8.1, §2.1 (P1-P11).
//
// The guardian chose a daily total for reading and watching (off, 1, 2 or 3 hours;
// home_plan_store.dart). This file is only the arithmetic and the words:
//
//   * what counts as one local day (her device clock; the day turns over at
//     local midnight, so a new day always starts from nothing);
//   * the state for a given total and a given amount used: open, winding down
//     (the last few minutes) or done;
//   * the one calm line she may read, and the plain line a grown-up reads.
//
// WHAT SHE NEVER SEES (P1-P11): a number, a clock, a countdown, a bar, a streak, a score or a
// reward. Her words say nothing about minutes. "Done" is a rest, not a punishment: nothing is
// taken away, there is more tomorrow, and calls and family messages are never touched.
import 'package:flutter/foundation.dart';

/// The soft notice comes this long before the total runs out.
const int kDailyWindDownSeconds = 5 * 60;

/// A grown-up can add time to TODAY in steps of this size.
const int kDailyBonusStepMinutes = 30;

/// …and never more than this much in one day.
const int kDailyBonusMaxMinutes = 180;

/// What one day has used on this device, and what a grown-up added to it.
@immutable
class DayUse {
  const DayUse({required this.day, this.seconds = 0, this.bonusMinutes = 0});

  /// Her local calendar day, `yyyy-mm-dd`.
  final String day;

  /// Time spent on reading and watching, in whole seconds, on this device today.
  final int seconds;

  /// Time a grown-up allowed on top of the total for today only.
  final int bonusMinutes;

  DayUse copyWith({int? seconds, int? bonusMinutes}) =>
      DayUse(day: day, seconds: seconds ?? this.seconds, bonusMinutes: bonusMinutes ?? this.bonusMinutes);

  Map<String, Object?> toJson() =>
      <String, Object?>{'day': day, 'seconds': seconds, 'bonusMinutes': bonusMinutes};

  /// Tolerant: junk, a wrong type or a negative value becomes a fresh, empty [today].
  factory DayUse.fromJson(Object? raw, String today) {
    if (raw is! Map) return DayUse(day: today);
    final Object? d = raw['day'];
    if (d is! String || d != today) return DayUse(day: today);
    final Object? s = raw['seconds'], b = raw['bonusMinutes'];
    return DayUse(
      day: today,
      seconds: s is int && s >= 0 ? s : 0,
      bonusMinutes: b is int && b >= 0 && b <= kDailyBonusMaxMinutes ? b : 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DayUse && other.day == day && other.seconds == seconds && other.bonusMinutes == bonusMinutes;

  @override
  int get hashCode => Object.hash(day, seconds, bonusMinutes);
}

/// `2026-11-14` for a LOCAL time. Pass the device's local clock, never UTC: the day turns over at her midnight.
String localDayKey(DateTime local) =>
    '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';

enum DailyTimeState { open, windingDown, done }

/// The state for a chosen total of [hours] (0 = off, never limits) and what [use] holds.
DailyTimeState dailyTimeState(int hours, DayUse use) {
  if (hours <= 0) return DailyTimeState.open;
  final int limit = hours * 3600 + use.bonusMinutes * 60;
  if (use.seconds >= limit) return DailyTimeState.done;
  if (limit - use.seconds <= kDailyWindDownSeconds) return DailyTimeState.windingDown;
  return DailyTimeState.open;
}

/// The one line she may read. No number and no clock, ever.
String? dailyKidLine(DailyTimeState s) => switch (s) {
      DailyTimeState.open => null,
      DailyTimeState.windingDown => 'Almost time to rest our eyes. One more, then we are done for today.',
      DailyTimeState.done => 'All done for today. Your eyes can rest now, and there is more tomorrow.',
    };

/// Plain words for a grown-up who proved they are one, on the child's device.
String dailyAdultLine(String childName) =>
    'Reading and watching time for $childName is used up for today on this device. '
    'It starts again at midnight. Calls and family messages are not affected.';

/// What the grown-up's own settings screen says about today on THIS device.
/// Minutes are fine for a grown-up; they are never shown to her.
String dailyUsedToday(DayUse use) {
  final int m = (use.seconds / 60).floor();
  final String used = m < 1 ? 'less than a minute' : m < 60 ? '$m min' : '${m ~/ 60} h ${m % 60} min';
  final String extra = use.bonusMinutes > 0 ? ' You allowed ${use.bonusMinutes} more minutes today.' : '';
  return 'Used today on this device: $used.$extra';
}

/// The next bonus after a grown-up allows [kDailyBonusStepMinutes] more: capped for the day.
int nextBonusMinutes(int current) => (current + kDailyBonusStepMinutes).clamp(0, kDailyBonusMaxMinutes);

/// True when another step still fits under today's cap.
bool canAllowMore(int current) => current + kDailyBonusStepMinutes <= kDailyBonusMaxMinutes;
