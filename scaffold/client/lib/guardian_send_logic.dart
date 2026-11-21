// OLIVE BRANCH — the guardian side of sending: the pure-logic half. UNVERIFIED on a real
// device and against a live server; its logic is run by CI (client/test/guardian_send_logic_test.dart,
// guardian_send_contract_test.dart). MASTERFILE §8.2.3, §8.2.4, §8.2.8, §8.31.
//
// WHAT THIS IS. Everything a grown-up needs to compose a message to her child and
// to edit the child's day, with no widget and no network in it, so the rules can
// be tested without a device:
//
//   - the child's DAY-PARTS as the server stores them (GET/PUT .../day-parts) and
//     the validation the server will apply, mirrored here so a grown-up is told in
//     plain words BEFORE a save is refused;
//   - the DELIVERY CHOICE a message can carry through the real route
//     (POST .../messages takes `delivery`: now, a day-part kind, or a day-part kind and a night);
//   - the plain words for every state a sent message can be in (waiting, delivered,
//     opened, expired, taken back) and for every refusal the server can give;
//   - the shape of one message waiting in the offline outbox on this phone.
//
// WHAT THE REAL ROUTE CAN AND CANNOT DO (read from server/routes.mjs, not assumed):
//   - A message is ALWAYS a recorded media file (the route needs a storage key
//     and a duration above zero). There is no text message on the wire. The
//     composer therefore sends a video, and says so.
//   - The route has three delivery choices, named by its `delivery` field: `now` (the
//     engine's `immediate` policy: due the moment it is sent, delivered on the worker's
//     next pass), `daypart` (`at_daypart`: the next time that part of her day starts) and
//     `date` (`on_local_date`: that night, at that part's start, or 8:30 PM her time if
//     the part does not run that weekday). "Right away" needs a server that knows the
//     field; a server that does not would quietly schedule it for bedtime, so the answer
//     is checked (the 201 body carries `delivery`) and a message is never called "right
//     away" unless the server said so.
//   - The route never asks the time zone of the grown-up. Every time shown here is
//     HER wall clock (§8.2.3); a grown-up's own clock is never subtracted from it.
//
// CHILD SAFETY (P1-P11). This file is grown-up only. Nothing here is drawn in her
// app. No count, streak or score is produced; a status is a sentence, not a tally.
library;

import 'dart:convert';

import 'offline_outbox.dart' show backoffMs, maxAttempts;

// ============================================================ day-parts ====

/// The ten kinds the server accepts (routes.mjs DAY_PART_KINDS). Anything else is
/// refused by the server with `bad_day_part_kind`.
const List<String> kDayPartKinds = <String>[
  'wake', 'before_school', 'school', 'after_school', 'activity',
  'dinner', 'wind_down', 'bedtime', 'asleep', 'free',
];

/// The most parts one child's day may hold (routes.mjs MAX_DAY_PARTS).
const int kMaxDayParts = 24;

/// A grown-up's name for a part of her day, as a title.
String dayPartTitle(String kind) => switch (kind) {
      'wake' => 'Waking up',
      'before_school' => 'Before school',
      'school' => 'School',
      'after_school' => 'After school',
      'activity' => 'Activity',
      'dinner' => 'Dinner',
      'wind_down' => 'Winding down',
      'bedtime' => 'Bedtime',
      'asleep' => 'Asleep',
      'free' => 'Free time',
      _ => kind.replaceAll('_', ' '),
    };

/// The same part, as the end of "arrives ...": "at bedtime", "after school".
String dayPartWhen(String kind) => switch (kind) {
      'wake' => 'when she wakes up',
      'before_school' => 'before school',
      'school' => 'during school',
      'after_school' => 'after school',
      'activity' => 'at activity time',
      'dinner' => 'at dinner',
      'wind_down' => 'when she winds down',
      'bedtime' => 'at bedtime',
      'asleep' => 'while she is asleep',
      'free' => 'in her free time',
      _ => 'at ${kind.replaceAll('_', ' ')}',
    };

/// Minutes after midnight for a strict 24-hour "HH:MM", or null.
int? parseHm(Object? s) {
  if (s is! String) return null;
  final RegExpMatch? m = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$').firstMatch(s);
  if (m == null) return null;
  return int.parse(m.group(1)!) * 60 + int.parse(m.group(2)!);
}

/// "HH:MM" from minutes after midnight (0 to 1439).
String formatHm(int minutes) {
  final int m = minutes % 1440;
  return '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
}

/// "8:30 PM" for a valid "HH:MM"; the input unchanged for anything else, so a
/// strange value from a server is shown rather than hidden or turned into a crash.
String hmTo12h(String hm) {
  final int? m = parseHm(hm);
  if (m == null) return hm;
  final int h = m ~/ 60, mm = m % 60;
  final int h12 = h % 12 == 0 ? 12 : h % 12;
  return '$h12:${mm.toString().padLeft(2, '0')} ${h < 12 ? 'AM' : 'PM'}';
}

const List<String> _dayShort = <String>['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const List<String> _dayLong = <String>[
  'Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

/// 0 = Sunday .. 6 = Saturday, the server's numbering.
String weekdayShort(int d) => _dayShort[d.clamp(0, 6)];
String weekdayLong(int d) => _dayLong[d.clamp(0, 6)];

/// "every day", "weekdays", "weekends", or the short names in week order.
String describeDays(Iterable<int> days) {
  final List<int> d = (days.toSet().toList()..sort());
  if (d.length == 7) return 'every day';
  if (_sameDays(d, const <int>[1, 2, 3, 4, 5])) return 'weekdays';
  if (_sameDays(d, const <int>[0, 6])) return 'weekends';
  return d.map(weekdayShort).join(', ');
}

bool _sameDays(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// One part of the child's day, in the shape the server stores and returns.
class DayPartEntry {
  const DayPartEntry({
    required this.kind,
    required this.startsLocal,
    required this.endsLocal,
    this.days = const <int>[0, 1, 2, 3, 4, 5, 6],
    required this.reachable,
  });

  final String kind;
  /// Wall-clock "HH:MM" in HER time zone. Bedtime is 20:30 whatever daylight saving does.
  final String startsLocal;
  final String endsLocal;
  /// 0 = Sunday .. 6 = Saturday.
  final List<int> days;
  /// Whether she can be reached during this part (a message does not wake her).
  final bool reachable;

  DayPartEntry copyWith({
    String? kind, String? startsLocal, String? endsLocal, List<int>? days, bool? reachable,
  }) =>
      DayPartEntry(
        kind: kind ?? this.kind,
        startsLocal: startsLocal ?? this.startsLocal,
        endsLocal: endsLocal ?? this.endsLocal,
        days: days ?? this.days,
        reachable: reachable ?? this.reachable,
      );

  /// True when the part runs past midnight (ends at or before it starts is the server's
  /// rule; equal times are refused as empty, so here it is simply "ends before it starts").
  bool get wrapsMidnight {
    final int? s = parseHm(startsLocal), e = parseHm(endsLocal);
    return s != null && e != null && e < s;
  }

  /// The wire form PUT .../day-parts takes. Days are sorted so equal schedules compare equal.
  Map<String, Object?> toWire() => <String, Object?>{
        'kind': kind,
        'startsLocal': startsLocal,
        'endsLocal': endsLocal,
        'daysOfWeek': (days.toSet().toList()..sort()),
        'reachable': reachable,
      };

  /// Reads one part from a server body. A part that is not usable (wrong types, a time
  /// that is not HH:MM, a day outside 0..6) is null: a bad row from a server must never
  /// crash the editor, and must never be silently rewritten into something else.
  static DayPartEntry? fromWire(Object? raw) {
    if (raw is! Map) return null;
    final Object? kind = raw['kind'], s = raw['startsLocal'], e = raw['endsLocal'];
    final Object? days = raw['daysOfWeek'], reachable = raw['reachable'];
    if (kind is! String || kind.isEmpty || kind.length > 40) return null;
    if (parseHm(s) == null || parseHm(e) == null) return null;
    if (reachable is! bool) return null;
    final List<int> d;
    if (days == null) {
      d = const <int>[0, 1, 2, 3, 4, 5, 6];
    } else if (days is List && days.every((Object? x) => x is int && x >= 0 && x <= 6)) {
      d = (days.cast<int>().toSet().toList()..sort());
    } else {
      return null;
    }
    if (d.isEmpty) return null;
    return DayPartEntry(
        kind: kind, startsLocal: s! as String, endsLocal: e! as String, days: d, reachable: reachable);
  }

  @override
  bool operator ==(Object other) =>
      other is DayPartEntry &&
      other.kind == kind &&
      other.startsLocal == startsLocal &&
      other.endsLocal == endsLocal &&
      other.reachable == reachable &&
      _sameDays(days.toSet().toList()..sort(), other.days.toSet().toList()..sort());

  @override
  int get hashCode => Object.hash(kind, startsLocal, endsLocal, reachable, days.length);
}

/// A whole day as the server holds it: the parts and whether a bedtime exists.
class DayPartsView {
  const DayPartsView(this.parts, {required this.hasBedtime, this.skipped = 0});
  final List<DayPartEntry> parts;
  final bool hasBedtime;
  /// How many rows the server sent that this client could not read. Shown to the grown-up
  /// so a save is never a silent loss of a row she cannot see.
  final int skipped;

  /// Reads GET/PUT .../day-parts. Never throws on a strange body.
  static DayPartsView parse(Object? body) {
    final List<DayPartEntry> out = <DayPartEntry>[];
    int skipped = 0;
    final Object? list = body is Map ? body['dayParts'] : null;
    if (list is List) {
      for (final Object? p in list) {
        final DayPartEntry? e = DayPartEntry.fromWire(p);
        if (e == null) {
          skipped++;
        } else {
          out.add(e);
        }
      }
    }
    return DayPartsView(out, hasBedtime: out.any((DayPartEntry p) => p.kind == 'bedtime'), skipped: skipped);
  }
}

/// Two schedules are the same schedule: same parts, in any order.
bool sameSchedule(List<DayPartEntry> a, List<DayPartEntry> b) {
  if (a.length != b.length) return false;
  String key(DayPartEntry e) => jsonEncode(e.toWire());
  final List<String> x = a.map(key).toList()..sort();
  final List<String> y = b.map(key).toList()..sort();
  for (int i = 0; i < x.length; i++) {
    if (x[i] != y[i]) return false;
  }
  return true;
}

/// One thing wrong with a schedule, in a grown-up's words. [index] is the part, or null for
/// the schedule as a whole.
class DayPartProblem {
  const DayPartProblem(this.index, this.code, this.text);
  final int? index;
  final String code;
  final String text;
  @override
  String toString() => 'DayPartProblem($index, $code)';
}

class DayPartsCheck {
  const DayPartsCheck(this.errors, this.warnings);
  /// Things the server would refuse. A save is not attempted while any exist.
  final List<DayPartProblem> errors;
  /// Things the server allows but a grown-up should know before saving.
  final List<String> warnings;
  bool get canSave => errors.isEmpty;
}

/// The half-open range a part occupies on its starting day, the way the server's overlap
/// constraint (migration 0042, `day_part_no_overlap`) models it: a part that ends before it
/// starts runs to the same clock time the NEXT day.
({int start, int end}) _range(DayPartEntry e) {
  final int s = parseHm(e.startsLocal)!, en = parseHm(e.endsLocal)!;
  return (start: s, end: en < s ? en + 1440 : en);
}

/// Mirrors the server's validation (routes.mjs PUT .../day-parts and migration 0042) so a
/// refusal is explained before the save, not after. The server stays the authority: this
/// only ever refuses what the server would also refuse.
DayPartsCheck checkDayParts(List<DayPartEntry> parts) {
  final List<DayPartProblem> errors = <DayPartProblem>[];
  final List<String> warnings = <String>[];
  if (parts.isEmpty) {
    errors.add(const DayPartProblem(null, 'day_parts_required',
        'Her day needs at least one part. To change it, edit the parts that are there rather than clearing them: '
        'with no bedtime nothing you send could ever be delivered.'));
    return DayPartsCheck(errors, warnings);
  }
  if (parts.length > kMaxDayParts) {
    errors.add(const DayPartProblem(null, 'too_many', 'A day can have at most $kMaxDayParts parts.'));
  }
  final Set<int> structurallyOk = <int>{};
  for (int i = 0; i < parts.length; i++) {
    final DayPartEntry p = parts[i];
    final String name = dayPartTitle(p.kind);
    bool ok = true;
    if (!kDayPartKinds.contains(p.kind)) {
      errors.add(DayPartProblem(i, 'bad_day_part_kind', '"$name" is not a part of the day Olive knows.'));
      ok = false;
    }
    final int? s = parseHm(p.startsLocal), e = parseHm(p.endsLocal);
    if (s == null || e == null) {
      errors.add(DayPartProblem(i, 'bad_day_part_time', '$name: the start and end need to be times of day.'));
      ok = false;
    } else if (s == e) {
      errors.add(DayPartProblem(i, 'empty_day_part',
          '$name starts and ends at the same time, so it would last no time at all. '
          'To run overnight, make the end earlier than the start.'));
      ok = false;
    }
    final Set<int> ds = p.days.toSet();
    if (p.days.isEmpty || ds.length != p.days.length || p.days.length > 7 ||
        !p.days.every((int d) => d >= 0 && d <= 6)) {
      errors.add(DayPartProblem(i, 'bad_days_of_week', '$name: pick at least one day it runs on.'));
      ok = false;
    }
    if (ok) structurallyOk.add(i);
  }
  for (int i = 0; i < parts.length; i++) {
    for (int j = i + 1; j < parts.length; j++) {
      if (!structurallyOk.contains(i) || !structurallyOk.contains(j)) continue;
      final DayPartEntry a = parts[i], b = parts[j];
      if (a.kind != b.kind) continue;
      if (!a.days.toSet().intersection(b.days.toSet()).isNotEmpty) continue;
      final ({int start, int end}) ra = _range(a), rb = _range(b);
      if (ra.start < rb.end && rb.start < ra.end) {
        errors.add(DayPartProblem(j, 'day_parts_overlap',
            '${dayPartTitle(a.kind)} appears twice at overlapping times on the same day '
            '(${hmTo12h(a.startsLocal)} to ${hmTo12h(a.endsLocal)} and '
            '${hmTo12h(b.startsLocal)} to ${hmTo12h(b.endsLocal)}). Change one of them.'));
      }
    }
  }
  if (!parts.any((DayPartEntry p) => p.kind == 'bedtime')) {
    warnings.add('There is no Bedtime in her day. A message set for her bedtime could not be sent until you add one.');
  }
  return DayPartsCheck(errors, warnings);
}

/// One line for a part: "Bedtime: 8:30 PM to 7:00 AM the next morning, every day. She can be reached."
String describeDayPart(DayPartEntry e) {
  final String until = e.wrapsMidnight ? '${hmTo12h(e.endsLocal)} the next morning' : hmTo12h(e.endsLocal);
  return '${dayPartTitle(e.kind)}: ${hmTo12h(e.startsLocal)} to $until, ${describeDays(e.days)}. '
      '${e.reachable ? 'She can be reached.' : 'She cannot be reached.'}';
}

/// A server refusal to a day-parts save, in plain words. Unknown codes get a general line
/// rather than the raw code.
String dayPartsErrorWords(String code) => switch (code) {
      'day_parts_required' => 'Her day needs at least one part.',
      'bad_day_part_kind' => 'One of the parts is not a kind of part Olive knows.',
      'bad_day_part_time' => 'One of the times is not a time of day.',
      'empty_day_part' => 'A part starts and ends at the same time.',
      'bad_days_of_week' => 'A part needs at least one day it runs on.',
      'reachable_required' => 'A part is missing whether she can be reached.',
      'day_parts_overlap' => 'Two parts of the same kind overlap on the same day. Nothing was changed.',
      'bad_day_part' => 'The server could not accept one of the parts. Nothing was changed.',
      'not_a_child_surface' => 'This is for grown-ups only.',
      'forbidden' || 'not_authorized' =>
        'You do not have permission to change her day. Only a guardian who can change settings may.',
      _ => 'The change could not be saved. Nothing was changed.',
    };

// ============================================================ delivery ====

enum DeliveryKind { atDayPart, onNight, now }

/// What the grown-up chose for when a message arrives. This is exactly what the real route
/// can express: right away, a part of her day (its next start) or one named night (at that
/// part's start).
class DeliveryChoice {
  const DeliveryChoice.now()
      : kind = DeliveryKind.now,
        dayPart = 'bedtime',
        night = null;
  const DeliveryChoice.atDayPart(this.dayPart)
      : kind = DeliveryKind.atDayPart,
        night = null;
  const DeliveryChoice.onNight(this.night, {this.dayPart = 'bedtime'}) : kind = DeliveryKind.onNight;

  final DeliveryKind kind;
  /// A day-part kind from [kDayPartKinds].
  final String dayPart;
  /// "YYYY-MM-DD" in HER calendar, for [DeliveryKind.onNight].
  final String? night;

  /// The body fields POST .../messages reads. A part or a night sends exactly the two fields an
  /// older server reads; "right away" sends `delivery: now` and names no night.
  Map<String, Object?> toWire() => kind == DeliveryKind.now
      ? <String, Object?>{'delivery': 'now', 'daypart': dayPart}
      : <String, Object?>{
          'daypart': dayPart,
          if (kind == DeliveryKind.onNight) 'targetLocalDate': night,
        };

  Map<String, Object?> toJson() => <String, Object?>{
        'k': switch (kind) { DeliveryKind.onNight => 'night', DeliveryKind.now => 'now', _ => 'part' },
        'p': dayPart,
        if (night != null) 'n': night,
      };

  static DeliveryChoice? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final Object? k = raw['k'], p = raw['p'], n = raw['n'];
    if (p is! String || !kDayPartKinds.contains(p)) return null;
    if (k == 'now') return const DeliveryChoice.now();
    if (k == 'part') return DeliveryChoice.atDayPart(p);
    if (k == 'night' && n is String && parseNight(n) != null) return DeliveryChoice.onNight(n, dayPart: p);
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is DeliveryChoice && other.kind == kind && other.dayPart == dayPart && other.night == night;
  @override
  int get hashCode => Object.hash(kind, dayPart, night);
}

/// A real calendar date from "YYYY-MM-DD", or null (so "2026-02-30" is not accepted).
DateTime? parseNight(String s) {
  final RegExpMatch? m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(s);
  if (m == null) return null;
  final int y = int.parse(m.group(1)!), mo = int.parse(m.group(2)!), d = int.parse(m.group(3)!);
  final DateTime t = DateTime.utc(y, mo, d);
  return t.year == y && t.month == mo && t.day == d ? t : null;
}

String formatNight(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// "Fri 21 Nov" for a night.
String nightWords(String night) {
  final DateTime? t = parseNight(night);
  if (t == null) return night;
  const List<String> months = <String>[
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${weekdayShort(t.weekday % 7)} ${t.day} ${months[t.month - 1]}';
}

/// The most nights ahead a message may be set for here. The server has no limit of its own;
/// a year is a generous bound that still catches a mistyped year.
const int kMaxNightsAhead = 366;

class DeliveryCheck {
  const DeliveryCheck(this.blockers, this.notes, this.arrival);
  /// Reasons the message cannot go as chosen. Nothing is sent while any exist.
  final List<String> blockers;
  /// Things worth knowing that do not stop the send. The guard is advisory: the grown-up decides.
  final List<String> notes;
  /// "Arrives at bedtime, 8:30 PM her time." or null when it cannot be worked out.
  final String? arrival;
  bool get ok => blockers.isEmpty;
}

/// Checks a choice against her day. [today] is the grown-up's own calendar date, used only to
/// refuse a night that is plainly over or plainly too far away; the server settles the rest in
/// her time zone (it allows a two-hour grace, so a night that is "today" there may still go).
DeliveryCheck checkDelivery(DeliveryChoice choice, List<DayPartEntry> parts, {required DateTime today}) {
  final List<String> blockers = <String>[];
  final List<String> notes = <String>[];
  String? arrival;
  if (choice.kind == DeliveryKind.now) {
    // Right away needs nothing from her day: it is the way out for a family whose day is not set up yet.
    return const DeliveryCheck(<String>[], <String>[],
        'Goes out as soon as Olive has it. It lands on her tablet within about a minute.');
  }
  final List<DayPartEntry> ofKind = parts.where((DayPartEntry p) => p.kind == choice.dayPart).toList();
  if (parts.isNotEmpty && ofKind.isEmpty) {
    blockers.add("Her day has no ${dayPartTitle(choice.dayPart)} part yet. Choose another time, or add it to her day.");
  }
  if (choice.kind == DeliveryKind.atDayPart) {
    if (ofKind.isNotEmpty) {
      final DayPartEntry first = ofKind.first;
      arrival = 'Arrives ${dayPartWhen(choice.dayPart)}, from ${hmTo12h(first.startsLocal)} her time'
          '${ofKind.length > 1 ? ' (the next time it starts)' : ''}.';
      if (!first.reachable) notes.add(_unreachableNote(choice.dayPart));
    }
  } else {
    final DateTime? n = choice.night == null ? null : parseNight(choice.night!);
    if (n == null) {
      blockers.add('Choose the night it should arrive.');
    } else {
      final DateTime t0 = DateTime.utc(today.year, today.month, today.day);
      if (n.isBefore(t0.subtract(const Duration(days: 1)))) {
        blockers.add('${nightWords(choice.night!)} has already gone by. Choose tonight or a later night.');
      } else if (n.difference(t0).inDays > kMaxNightsAhead) {
        blockers.add('That is more than a year away. Choose a nearer night.');
      } else if (ofKind.isNotEmpty) {
        final int wd = n.weekday % 7;
        final List<DayPartEntry> runs = ofKind.where((DayPartEntry p) => p.days.contains(wd)).toList();
        if (runs.isEmpty) {
          arrival = 'Arrives the night of ${nightWords(choice.night!)}, at 8:30 PM her time.';
          notes.add("Her ${dayPartTitle(choice.dayPart)} part does not run on ${weekdayLong(wd)}s, so Olive uses "
              '8:30 PM her time that night. Choose another part, or add that day to it.');
        } else {
          arrival = 'Arrives the night of ${nightWords(choice.night!)}, at ${hmTo12h(runs.first.startsLocal)} her time.';
          if (!runs.first.reachable) notes.add(_unreachableNote(choice.dayPart));
        }
      }
    }
  }
  return DeliveryCheck(blockers, notes, arrival);
}

String _unreachableNote(String kind) =>
    'Her day is set so that she cannot be reached ${dayPartWhen(kind)}. It will go out then anyway, '
    'but she may not see it until later. Choose another time if you want her to see it as it arrives.';

/// The send-time guard for "right away": [dayPart] and [reachable] are what the server's own
/// `GET .../now` said about her right now. It only ever warns (the grown-up decides: the server
/// delivers a right-away message whatever her day says). Her clock and her words, never his.
String? rightAwayGuardNote(String childName, {String? localTime, String? dayPart, bool? reachable}) {
  if (reachable != false) return null;
  final String clock = localTime == null ? '' : ' It is $localTime for $childName right now.';
  final String part = dayPart == null
      ? 'is set as not reachable'
      : 'is set as not reachable (${dayPartTitle(dayPart).toLowerCase()})';
  return 'Her day $part at the moment.$clock If you send this now it will land on her tablet straight away, '
      'but she may not see it until later. You can instead choose a time she can be reached.';
}

/// A short phrase kept with a sent message so the status list can say what it was set for.
String deliveryPhrase(DeliveryChoice c) => switch (c.kind) {
      DeliveryKind.now => 'right away',
      DeliveryKind.onNight => 'the night of ${nightWords(c.night ?? '')}',
      DeliveryKind.atDayPart => dayPartWhen(c.dayPart),
    };

// ================================================================ words ====

/// How a refusal or a failure is told to a grown-up, and what to do about it.
enum FailureClass {
  /// No answer, a busy server or an expired sign-in: nothing is wrong with the message.
  /// It stays on this phone and goes by itself later.
  retryLater,
  /// The server looked and said no. Retrying the same thing will not help; the grown-up
  /// has to change something. The recording is kept.
  needsAttention,
}

class SendFailure {
  const SendFailure(this.cls, this.code, this.words);
  final FailureClass cls;
  /// A fixed word kept on the item (never a URL, address or body text).
  final String code;
  final String words;
}

/// Said for a "right away" message that waited too long on this phone to still be right away.
const String staleNowWords =
    'This was meant to go right away, but it has been waiting on this phone for a while. Choose when it '
    'should arrive instead (or choose Right away again).';

/// A "right away" that has waited this long on the phone is no longer right away: a grown-up who
/// said "now" at 4 p.m. does not want it appearing at 11 p.m. (offline.ts: some things are
/// meaningless late). A part or a night is still right later and goes as chosen.
const Duration kStaleNowAfter = Duration(minutes: 30);

/// Maps a thrown error to a class and a sentence. [statusCode] and [error] come from the
/// server's JSON; anything that is not an HTTP answer (no network, a timeout) is
/// "retry later". [error] is only ever looked up here, never shown.
SendFailure classifyFailure({int? statusCode, String? error}) {
  if (statusCode == null) {
    return const SendFailure(FailureClass.retryLater, 'no_answer',
        'Olive could not reach the server. Your message is saved on this phone and will go by itself.');
  }
  switch (error) {
    case 'daypart_undefined':
      return const SendFailure(FailureClass.needsAttention, 'daypart_undefined',
          'Her day has no bedtime (or that part) set yet, so Olive cannot work out when to deliver this. '
          "Set her day first, then try again.");
    case 'target_date_in_past':
      return const SendFailure(FailureClass.needsAttention, 'target_date_in_past',
          'That night has already passed in her time. Choose a later night.');
    case 'already_expired':
      return const SendFailure(FailureClass.needsAttention, 'already_expired',
          'That time is too far past to deliver. Choose a new time.');
    case 'delivery_unresolvable':
      return const SendFailure(FailureClass.needsAttention, 'delivery_unresolvable',
          'Olive could not work out when that would arrive. Choose another time.');
    case 'empty_recording':
    case 'bytes_required':
    case 'bad_bytes':
      return const SendFailure(FailureClass.needsAttention, 'empty_recording',
          'The recording was empty. Record it again.');
    case 'unsupported_media_type':
      return const SendFailure(FailureClass.needsAttention, 'unsupported_media_type',
          'Olive cannot send a video in that format. Record it again with the camera.');
    case 'image_too_large':
      return const SendFailure(FailureClass.needsAttention, 'too_large', 'That file is too large to send.');
    case 'media_quota_exceeded':
      return const SendFailure(FailureClass.needsAttention, 'media_quota_exceeded',
          "Her message storage on the server is full, so this one cannot be added. It is still saved on this phone.");
    case 'not_authorized':
    case 'child_sender_mismatch':
    case 'wrong_child':
      return const SendFailure(FailureClass.needsAttention, 'not_authorized',
          'You are not allowed to send to her from this account.');
    case 'child_not_found':
      return const SendFailure(FailureClass.needsAttention, 'child_not_found',
          'The server does not know this child. Check that this phone is connected to the right family.');
    case 'storage_key_not_yours':
      return const SendFailure(FailureClass.needsAttention, 'storage_key_not_yours',
          'This upload belongs to a different account.');
    case 'child_cannot_send_now':
      return const SendFailure(FailureClass.needsAttention, 'child_cannot_send_now',
          'A message from her cannot go right away. Choose a time for it.');
    case 'bad_delivery':
    case 'now_has_no_date':
    case 'date_required':
    case 'daypart_has_no_date':
    case 'invalid_daypart':
      return const SendFailure(FailureClass.needsAttention, 'bad_choice',
          'The server could not understand when this should arrive. Choose when it should arrive again.');
    case 'stale_now':
      return const SendFailure(FailureClass.needsAttention, 'stale_now', staleNowWords);
  }
  if (statusCode == 401) {
    return const SendFailure(FailureClass.retryLater, 'sign_in',
        'This phone needs to sign in again. Your message is saved and will go once it has.');
  }
  if (statusCode == 408 || statusCode == 429 || statusCode >= 500) {
    return const SendFailure(FailureClass.retryLater, 'busy',
        'The server is busy or not answering. Your message is saved and will go by itself.');
  }
  if (statusCode == 403) {
    return const SendFailure(FailureClass.needsAttention, 'forbidden',
        'You do not have permission to send to her. Ask the guardian who set this up.');
  }
  return const SendFailure(FailureClass.needsAttention, 'refused',
      'Olive could not send this. It is still saved on this phone.');
}

/// One row of "what you have sent", as the server reports it (GET .../sent).
class SentRow {
  const SentRow({required this.id, required this.state, this.sentAt, this.deliveredAt, this.openedAt,
      this.receipt});
  final String id;
  /// waiting | delivered | opened | expired | revoked, or whatever a newer server says.
  final String state;
  final DateTime? sentAt, deliveredAt, openedAt;
  /// The server's sentence in HER frame, for example "Watched at 7:42 PM her time — at bedtime."
  final String? receipt;

  static SentRow? parse(Object? raw) {
    if (raw is! Map) return null;
    final Object? id = raw['id'], state = raw['state'];
    if (id is! String || id.isEmpty || id.length > 128 || state is! String) return null;
    DateTime? t(Object? v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;
    String? phrase;
    final Object? r = raw['receipt'];
    if (r is Map && r['phrase'] is String) {
      // Control characters out, length bounded: the phrase is drawn verbatim.
      final String cleaned = (r['phrase'] as String).replaceAll(RegExp(r'[\u0000-\u001f\u007f]'), ' ').trim();
      if (cleaned.isNotEmpty) phrase = cleaned.length > 200 ? cleaned.substring(0, 200) : cleaned;
    }
    return SentRow(
      id: id, state: state, sentAt: t(raw['sentAt']), deliveredAt: t(raw['deliveredAt']),
      openedAt: t(raw['openedAt']), receipt: phrase);
  }
}

/// Reads GET .../sent. Rows that cannot be read are counted, not hidden, so the screen can say so.
({List<SentRow> rows, int skipped}) parseSent(Object? body) {
  final Object? list = body is Map ? body['messages'] : null;
  final List<SentRow> rows = <SentRow>[];
  int skipped = 0;
  if (list is List) {
    for (final Object? m in list) {
      final SentRow? r = SentRow.parse(m);
      if (r == null) {
        skipped++;
      } else {
        rows.add(r);
      }
    }
  }
  return (rows: rows, skipped: skipped);
}

/// "Tue 18 Nov" from a moment, in the grown-up's own calendar: only a day, never a clock
/// time, so no time zone arithmetic is ever implied (§8.2.3).
String dayWords(DateTime t) {
  const List<String> months = <String>[
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${weekdayShort(t.weekday % 7)} ${t.day} ${months[t.month - 1]}';
}

/// A status as a sentence. [setFor] is what this phone remembers the message was set for.
String sentStatusWords(SentRow r, {String? setFor}) {
  final String when = setFor == null ? '' : ' $setFor';
  switch (r.state) {
    case 'waiting':
      return 'Waiting to arrive$when. It has not reached her tablet yet.';
    case 'delivered':
      final String day = r.deliveredAt == null ? '' : ' on ${dayWords(r.deliveredAt!)}';
      return 'Delivered to her tablet$day. She has not opened it yet.';
    case 'opened':
      return r.receipt ?? 'She opened it.';
    case 'expired':
      return 'It was not delivered in time, so it did not reach her.';
    case 'revoked':
      return 'This one was taken back before it arrived.';
    default:
      return 'Olive cannot tell where this one is right now.';
  }
}

// ============================================================== outbox ====

/// Largest recording Olive holds on this phone while it waits (raw bytes). The server accepts
/// about 30 MB in one request; the phone keeps its copy sealed, so it holds less.
const int kMaxHeldBytes = 12 * 1024 * 1024;

enum SendPhase {
  /// Waiting for a connection or a quiet moment. Goes by itself.
  waiting,
  /// The server refused it; the grown-up must change something. Never retried automatically.
  needsAttention,
}

/// One message waiting on this phone. The recording is held sealed, in the guardian's own
/// on-device store (`sendoutbox`), until the server has it.
class QueuedSend {
  const QueuedSend({
    required this.id,
    required this.childId,
    required this.createdAtMs,
    required this.delivery,
    required this.mediaB64,
    required this.durationMs,
    this.storageKey,
    this.attempts = 0,
    this.lastAttemptMs = 0,
    this.phase = SendPhase.waiting,
    this.failureCode,
  });

  final String id;
  final String childId;
  final int createdAtMs;
  final DeliveryChoice delivery;
  final String mediaB64;
  final int durationMs;
  /// Set once the upload succeeded, so a retry sends only the second half and never uploads twice.
  final String? storageKey;
  final int attempts;
  final int lastAttemptMs;
  final SendPhase phase;
  /// A fixed word from [classifyFailure], never free text from a server.
  final String? failureCode;

  QueuedSend copyWith({
    DeliveryChoice? delivery, String? storageKey, bool clearStorageKey = false, int? attempts,
    int? lastAttemptMs, SendPhase? phase, String? failureCode, bool clearFailure = false, int? createdAtMs,
  }) =>
      QueuedSend(
        id: id, childId: childId, createdAtMs: createdAtMs ?? this.createdAtMs, mediaB64: mediaB64,
        durationMs: durationMs,
        delivery: delivery ?? this.delivery,
        storageKey: clearStorageKey ? null : (storageKey ?? this.storageKey),
        attempts: attempts ?? this.attempts,
        lastAttemptMs: lastAttemptMs ?? this.lastAttemptMs,
        phase: phase ?? this.phase,
        failureCode: clearFailure ? null : (failureCode ?? this.failureCode),
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id, 'child': childId, 'at': createdAtMs, 'delivery': delivery.toJson(),
        'media': mediaB64, 'ms': durationMs,
        if (storageKey != null) 'key': storageKey,
        'tries': attempts, 'last': lastAttemptMs, 'phase': phase.name,
        if (failureCode != null) 'fail': failureCode,
      };

  /// Strict: any field that is the wrong type makes the whole item unreadable (null) rather
  /// than guessed at.
  static QueuedSend? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final Object? id = raw['id'], child = raw['child'], at = raw['at'], media = raw['media'];
    final Object? ms = raw['ms'], key = raw['key'], tries = raw['tries'], last = raw['last'];
    final Object? phase = raw['phase'], fail = raw['fail'];
    final DeliveryChoice? d = DeliveryChoice.fromJson(raw['delivery']);
    if (id is! String || !isPlainSendId(id) || child is! String || child.isEmpty || child.length > 128) return null;
    if (at is! int || ms is! int || ms <= 0 || media is! String || media.isEmpty || d == null) return null;
    if (key != null && (key is! String || key.length > 300)) return null;
    if (tries is! int || tries < 0 || last is! int || last < 0) return null;
    if (fail != null && (fail is! String || fail.length > 40)) return null;
    final SendPhase? p = SendPhase.values.where((SendPhase v) => v.name == phase).firstOrNull;
    if (p == null) return null;
    return QueuedSend(
      id: id, childId: child, createdAtMs: at, delivery: d, mediaB64: media, durationMs: ms,
      storageKey: key as String?, attempts: tries, lastAttemptMs: last, phase: p, failureCode: fail as String?);
  }

  /// Whether an automatic pass may try this now: waiting, under the attempt ceiling, and past
  /// the doubling wait since the last try (offline_outbox.dart's own schedule).
  bool dueAt(int nowMs) {
    if (phase != SendPhase.waiting) return false;
    if (attempts >= maxAttempts) return false;
    if (attempts == 0) return true;
    return nowMs - lastAttemptMs >= backoffMs(attempts - 1);
  }

  /// True once automatic tries have stopped and only "Try again" will move it.
  bool get gaveUpAutomatically => phase == SendPhase.waiting && attempts >= maxAttempts;
}

final RegExp _sendId = RegExp(r'^[a-z0-9][a-z0-9-]{5,63}$');

/// An id this phone made for an outbox item: lower-case, digits and dashes only, so it is a
/// legal key in the on-device store.
bool isPlainSendId(String s) => _sendId.hasMatch(s);

/// What a waiting message says about itself, in a grown-up's words.
String queuedStatusWords(QueuedSend q) {
  if (q.phase == SendPhase.needsAttention) {
    return classifyFailureByCode(q.failureCode).words;
  }
  if (q.gaveUpAutomatically) {
    return 'Olive has tried several times and could not reach the server. Your message is still saved on this phone. '
        'Tap Try again when you are back online.';
  }
  if (q.attempts == 0) return 'Saved on this phone, about to send.';
  return 'Waiting for a connection. Saved on this phone; it will go by itself.';
}

/// The words for a failure code kept on an item.
SendFailure classifyFailureByCode(String? code) => switch (code) {
      'daypart_undefined' => classifyFailure(statusCode: 400, error: 'daypart_undefined'),
      'target_date_in_past' => classifyFailure(statusCode: 400, error: 'target_date_in_past'),
      'already_expired' => classifyFailure(statusCode: 400, error: 'already_expired'),
      'delivery_unresolvable' => classifyFailure(statusCode: 400, error: 'delivery_unresolvable'),
      'empty_recording' => classifyFailure(statusCode: 400, error: 'empty_recording'),
      'unsupported_media_type' => classifyFailure(statusCode: 415, error: 'unsupported_media_type'),
      'too_large' => classifyFailure(statusCode: 413, error: 'image_too_large'),
      'media_quota_exceeded' => classifyFailure(statusCode: 413, error: 'media_quota_exceeded'),
      'not_authorized' => classifyFailure(statusCode: 403, error: 'not_authorized'),
      'child_not_found' => classifyFailure(statusCode: 404, error: 'child_not_found'),
      'storage_key_not_yours' => classifyFailure(statusCode: 403, error: 'storage_key_not_yours'),
      'child_cannot_send_now' => classifyFailure(statusCode: 403, error: 'child_cannot_send_now'),
      'bad_choice' => classifyFailure(statusCode: 400, error: 'bad_delivery'),
      'stale_now' => classifyFailure(statusCode: 400, error: 'stale_now'),
      'forbidden' => classifyFailure(statusCode: 403, error: 'forbidden'),
      _ => classifyFailure(statusCode: 400, error: 'refused'),
    };

/// Encodes raw recording bytes for the outbox.
String encodeMedia(List<int> bytes) => base64Encode(bytes);
