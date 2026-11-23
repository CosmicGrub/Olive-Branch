// OLIVE BRANCH — sending to the child from the grown-up's phone, and her day-parts: the rules, in plain Dart.
// Verified headless (client/test/guardian_send_logic_test.dart, guardian_send_contract_test.dart).
// MASTERFILE section 8.31.
//
// UNVERIFIED on a real device: covered by flutter test only (MASTERFILE 8.31).
//
// Everything here is pure: no network, no clock, no widget. The screens
// (guardian_send_screen.dart, day_parts_editor_screen.dart) and the service (guardian_send_service.dart) call it;
// the contract test holds it to server/routes.mjs, so a route that changes shape or a new answer from the server
// fails a test instead of reaching a grown-up as a bare code.
//
// ADULT WORDS. Every sentence here is for a grown-up (this is the guardian side; she never sees any of it).
// Nothing on this page is a count, a score, a streak, a place or a diagnosis, and no sentence gives medical
// advice. A time that belongs to HER day is always said in HER clock ("tomorrow at 8:30 PM her time"), never
// as arithmetic against the sender's (MASTERFILE 8.2.3); the server works the moment out and this file only
// words it.
library;

import 'api_client.dart' show ApiException;

// ================================================================= day-parts ==

/// The ten kinds the server accepts, in the order they are offered. server/routes.mjs `DAY_PART_KINDS`; the
/// contract test fails if the two differ.
const List<String> kDayPartKinds = <String>[
  'wake', 'before_school', 'school', 'after_school', 'activity',
  'dinner', 'wind_down', 'bedtime', 'asleep', 'free',
];

/// server/routes.mjs `MAX_DAY_PARTS`.
const int kMaxDayParts = 24;

/// The grown-up's name for a part of her day. An unknown kind (a newer server) is never shown raw.
String adultDayPartName(String kind) => switch (kind) {
      'wake' => 'Waking up',
      'before_school' => 'Getting ready for school',
      'school' => 'School',
      'after_school' => 'After school',
      'activity' => 'An activity',
      'dinner' => 'Dinner',
      'wind_down' => 'Winding down',
      'bedtime' => 'Bedtime',
      'asleep' => 'Asleep',
      'free' => 'Free time',
      _ => 'Another part of her day',
    };

/// The same, lower-cased for the middle of a sentence ("at her bedtime").
String adultDayPartPhrase(String kind) => switch (kind) {
      'wake' => 'waking-up time',
      'before_school' => 'getting-ready time',
      'school' => 'school time',
      'after_school' => 'after-school time',
      'activity' => 'activity time',
      'dinner' => 'dinner time',
      'wind_down' => 'winding-down time',
      'bedtime' => 'bedtime',
      'asleep' => 'sleeping time',
      'free' => 'free time',
      _ => 'that part of her day',
    };

final RegExp _hhmm = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');

/// Minutes after midnight for a strict "HH:MM", or null. server/routes.mjs `HHMM`.
int? parseHhmm(String? s) {
  if (s == null || !_hhmm.hasMatch(s)) return null;
  return int.parse(s.substring(0, 2)) * 60 + int.parse(s.substring(3, 5));
}

String formatHhmm(int minutes) {
  final int m = minutes % (24 * 60);
  return '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
}

/// "8:30 PM" for "20:30". An invalid time comes back as the empty string, never a guess.
String clock12(String? hhmm) {
  final int? m = parseHhmm(hhmm);
  if (m == null) return '';
  final int h = m ~/ 60;
  final int h12 = h % 12 == 0 ? 12 : h % 12;
  return '$h12:${(m % 60).toString().padLeft(2, '0')} ${h < 12 ? 'AM' : 'PM'}';
}

const List<String> _dayShort = <String>['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

/// Weekdays are 0 = Sunday .. 6 = Saturday, the server's own numbering.
String dayShortName(int d) => d >= 0 && d <= 6 ? _dayShort[d] : '';

/// "every day", "weekdays", "weekends" or "Mon, Wed, Fri" (Monday first).
String describeDays(Iterable<int> days) {
  final Set<int> s = days.where((int d) => d >= 0 && d <= 6).toSet();
  if (s.length == 7) return 'every day';
  if (s.length == 5 && <int>[1, 2, 3, 4, 5].every(s.contains)) return 'weekdays';
  if (s.length == 2 && s.contains(0) && s.contains(6)) return 'weekends';
  if (s.isEmpty) return 'no days';
  return <int>[1, 2, 3, 4, 5, 6, 0].where(s.contains).map(dayShortName).join(', ');
}

/// One part of her day, as the server holds it.
class DayPartSpan {
  const DayPartSpan({
    required this.kind,
    required this.startsLocal,
    required this.endsLocal,
    this.daysOfWeek = const <int>[0, 1, 2, 3, 4, 5, 6],
    required this.reachable,
  });

  final String kind;

  /// Wall-clock "HH:MM" in HER clock; bedtime is 20:30 whatever daylight saving does.
  final String startsLocal;
  final String endsLocal;
  final List<int> daysOfWeek;

  /// Whether she can be reached during this part (calls and alerts reach her). A quiet part is `false`.
  final bool reachable;

  /// A part that ends at or before it starts runs past midnight into the next morning.
  bool get wraps {
    final int? s = parseHhmm(startsLocal), e = parseHhmm(endsLocal);
    return s != null && e != null && e <= s && s != e;
  }

  DayPartSpan copyWith({
    String? kind,
    String? startsLocal,
    String? endsLocal,
    List<int>? daysOfWeek,
    bool? reachable,
  }) =>
      DayPartSpan(
        kind: kind ?? this.kind,
        startsLocal: startsLocal ?? this.startsLocal,
        endsLocal: endsLocal ?? this.endsLocal,
        daysOfWeek: daysOfWeek ?? this.daysOfWeek,
        reachable: reachable ?? this.reachable,
      );

  /// The body the PUT route takes.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'kind': kind,
        'startsLocal': startsLocal,
        'endsLocal': endsLocal,
        'daysOfWeek': <int>[...daysOfWeek]..sort(),
        'reachable': reachable,
      };

  /// Reads one entry of the server's `dayParts`. Returns null for anything that is not an object with the
  /// four plain fields: a reply this client cannot read is dropped, never half-drawn. `daysOfWeek` defaults to
  /// every day only when the server leaves it out; a malformed one drops the part.
  static DayPartSpan? fromJson(Object? j) {
    if (j is! Map) return null;
    final Object? kind = j['kind'], s = j['startsLocal'], e = j['endsLocal'], r = j['reachable'];
    if (kind is! String || kind.isEmpty || kind.length > 40) return null;
    if (s is! String || e is! String || parseHhmm(s) == null || parseHhmm(e) == null) return null;
    if (r is! bool) return null;
    final Object? d = j['daysOfWeek'];
    List<int> days = const <int>[0, 1, 2, 3, 4, 5, 6];
    if (d != null) {
      if (d is! List || d.isEmpty || d.length > 7 || !d.every((Object? x) => x is int && x >= 0 && x <= 6)) {
        return null;
      }
      days = <int>[for (final Object? x in d) x! as int]..sort();
    }
    return DayPartSpan(kind: kind, startsLocal: s, endsLocal: e, daysOfWeek: days, reachable: r);
  }

  @override
  bool operator ==(Object other) =>
      other is DayPartSpan &&
      other.kind == kind &&
      other.startsLocal == startsLocal &&
      other.endsLocal == endsLocal &&
      other.reachable == reachable &&
      _sameDays(other.daysOfWeek, daysOfWeek);

  @override
  int get hashCode => Object.hash(kind, startsLocal, endsLocal, reachable, (<int>[...daysOfWeek]..sort()).join());
}

bool _sameDays(List<int> a, List<int> b) {
  final List<int> x = <int>[...a]..sort(), y = <int>[...b]..sort();
  if (x.length != y.length) return false;
  for (int i = 0; i < x.length; i++) {
    if (x[i] != y[i]) return false;
  }
  return true;
}

bool sameSchedule(List<DayPartSpan> a, List<DayPartSpan> b) {
  if (a.length != b.length) return false;
  final List<String> ka = <String>[for (final DayPartSpan p in a) p.toJson().toString()]..sort();
  final List<String> kb = <String>[for (final DayPartSpan p in b) p.toJson().toString()]..sort();
  for (int i = 0; i < ka.length; i++) {
    if (ka[i] != kb[i]) return false;
  }
  return true;
}

/// The server's `{dayParts, hasBedtime}` answer. A reply that is not that shape throws [FormatException] so the
/// caller shows "could not read her day" instead of an empty, editable, wrong schedule.
List<DayPartSpan> parseDayParts(Map<String, dynamic> body) {
  final Object? raw = body['dayParts'];
  if (raw is! List) throw const FormatException('dayParts is not a list');
  final List<DayPartSpan> out = <DayPartSpan>[];
  for (final Object? j in raw) {
    final DayPartSpan? p = DayPartSpan.fromJson(j);
    if (p == null) throw const FormatException('a day part could not be read');
    out.add(p);
  }
  return out;
}

/// One sentence describing a part: "Bedtime, 8:30 PM to 9:00 PM, every day".
String describeSpan(DayPartSpan p) {
  final String when = '${clock12(p.startsLocal)} to ${clock12(p.endsLocal)}${p.wraps ? ' the next morning' : ''}';
  return '${adultDayPartName(p.kind)}, $when, ${describeDays(p.daysOfWeek)}';
}

/// What the server seeds for a brand-new child (packages/db/src/pool.ts DEFAULT_DAY_PARTS): a guess, not her
/// day. The contract test holds this list to the server's.
const List<DayPartSpan> kPlaceholderDayParts = <DayPartSpan>[
  DayPartSpan(kind: 'wake', startsLocal: '06:30', endsLocal: '08:00', reachable: true),
  DayPartSpan(kind: 'free', startsLocal: '08:00', endsLocal: '19:30', reachable: true),
  DayPartSpan(kind: 'bedtime', startsLocal: '19:30', endsLocal: '20:30', reachable: true),
  DayPartSpan(kind: 'asleep', startsLocal: '20:30', endsLocal: '06:30', reachable: false),
];

/// True while her schedule is still exactly the seeded guess.
bool isPlaceholderSchedule(List<DayPartSpan> parts) => sameSchedule(parts, kPlaceholderDayParts);

/// One thing wrong with a schedule, in plain words. [index] is the part it is about, when it is about one.
class DayPartProblem {
  const DayPartProblem(this.text, {this.index});
  final String text;
  final int? index;
}

/// The result of checking a schedule: [problems] stop a save (the server would refuse them too);
/// [notes] are worth knowing but do not.
class ScheduleCheck {
  const ScheduleCheck(this.problems, this.notes);
  final List<DayPartProblem> problems;
  final List<DayPartProblem> notes;
  bool get canSave => problems.isEmpty;
}

/// The part's time of day as a half-open range on one dummy day, a wrapping part running on into the next day:
/// the same range migration 0042's `day_part_no_overlap` builds with `tsrange`.
(int, int)? _timeRange(DayPartSpan p) {
  final int? s = parseHhmm(p.startsLocal), e = parseHhmm(p.endsLocal);
  if (s == null || e == null || s == e) return null;
  return (s, e < s ? e + 24 * 60 : e);
}

/// Mirrors the server's EXCLUDE constraint: the same kind, a weekday in common, and overlapping times of day.
bool sameKindOverlap(DayPartSpan a, DayPartSpan b) {
  if (a.kind != b.kind) return false;
  if (!a.daysOfWeek.any(b.daysOfWeek.contains)) return false;
  final (int, int)? x = _timeRange(a), y = _timeRange(b);
  if (x == null || y == null) return false;
  return x.$1 < y.$2 && y.$1 < x.$2;
}

/// The (weekday, from, to) minutes a part covers: a wrapping one spills its morning onto the next weekday.
List<(int, int, int)> _coverage(DayPartSpan p) {
  final (int, int)? r = _timeRange(p);
  if (r == null) return const <(int, int, int)>[];
  final List<(int, int, int)> out = <(int, int, int)>[];
  for (final int d in p.daysOfWeek) {
    if (r.$2 <= 24 * 60) {
      out.add((d, r.$1, r.$2));
    } else {
      out.add((d, r.$1, 24 * 60));
      out.add(((d + 1) % 7, 0, r.$2 - 24 * 60));
    }
  }
  return out;
}

bool _coversTogether(DayPartSpan a, DayPartSpan b) {
  for (final (int, int, int) x in _coverage(a)) {
    for (final (int, int, int) y in _coverage(b)) {
      if (x.$1 == y.$1 && x.$2 < y.$3 && y.$2 < x.$3) return true;
    }
  }
  return false;
}

/// Checks a schedule before it is sent, the way the server will: the same limits, the same time format, the
/// same overlap rule. Problems stop a save; notes do not.
ScheduleCheck checkDayParts(List<DayPartSpan> parts) {
  final List<DayPartProblem> problems = <DayPartProblem>[];
  final List<DayPartProblem> notes = <DayPartProblem>[];
  if (parts.isEmpty) {
    problems.add(const DayPartProblem('Her day needs at least one part. Add one, or leave things as they were.'));
    return ScheduleCheck(problems, notes);
  }
  if (parts.length > kMaxDayParts) {
    problems.add(const DayPartProblem('A day can have up to $kMaxDayParts parts. Remove one to add another.'));
  }
  for (int i = 0; i < parts.length; i++) {
    final DayPartSpan p = parts[i];
    final String name = adultDayPartName(p.kind);
    if (!kDayPartKinds.contains(p.kind)) {
      problems.add(DayPartProblem('"$name" is not a part this version of Olive can save. Pick one from the list.',
          index: i));
    }
    if (parseHhmm(p.startsLocal) == null || parseHhmm(p.endsLocal) == null) {
      problems.add(DayPartProblem('$name needs a start time and an end time.', index: i));
    } else if (p.startsLocal == p.endsLocal) {
      problems.add(DayPartProblem('$name starts and ends at the same time, so it covers none of her day.',
          index: i));
    }
    final List<int> d = p.daysOfWeek;
    if (d.isEmpty) {
      problems.add(DayPartProblem('$name needs at least one day.', index: i));
    } else if (d.length > 7 || d.toSet().length != d.length || !d.every((int x) => x >= 0 && x <= 6)) {
      problems.add(DayPartProblem('The days for $name are not valid. Pick them again.', index: i));
    }
  }
  for (int i = 0; i < parts.length; i++) {
    for (int j = i + 1; j < parts.length; j++) {
      if (sameKindOverlap(parts[i], parts[j])) {
        final String n = adultDayPartName(parts[i].kind);
        problems.add(DayPartProblem(
            '$n is set twice at overlapping times (${clock12(parts[i].startsLocal)} to ${clock12(parts[i].endsLocal)} '
            'and ${clock12(parts[j].startsLocal)} to ${clock12(parts[j].endsLocal)}). '
            'Keep one, or change a day or a time.',
            index: j));
      }
    }
  }
  if (problems.isEmpty) {
    if (!parts.any((DayPartSpan p) => p.kind == 'bedtime')) {
      notes.add(const DayPartProblem(
          'There is no bedtime in her day. Goodnight messages arrive at the start of her bedtime, so without one '
          'a message set for bedtime has nowhere to land. You can still send one right away.'));
    }
    final Set<String> said = <String>{};
    for (int i = 0; i < parts.length; i++) {
      for (int j = i + 1; j < parts.length; j++) {
        if (parts[i].kind == parts[j].kind) continue;
        final String key = <String>[parts[i].kind, parts[j].kind].toList().join('|');
        if (said.contains(key)) continue;
        if (_coversTogether(parts[i], parts[j])) {
          said.add(key);
          notes.add(DayPartProblem(
              '${adultDayPartName(parts[i].kind)} and ${adultDayPartName(parts[j].kind)} overlap on some days. '
              'Where parts overlap, the quieter one (where she cannot be reached) is the one that counts.',
              index: j));
        }
      }
    }
  }
  return ScheduleCheck(problems, notes);
}

/// Why a save of her schedule failed, in words. The server's own reason codes (server/routes.mjs PUT day-parts).
String dayPartSaveFailure(Object e) {
  if (e is ApiException) {
    switch (e.error) {
      case 'day_parts_overlap':
        return 'Two parts of the same kind overlap at the same time. Change a time or a day, then save again.';
      case 'day_parts_required':
        return 'Her day needs between 1 and $kMaxDayParts parts. Nothing was changed.';
      case 'bad_day_part_kind':
        return 'One of the parts is not a kind Olive can save. Nothing was changed.';
      case 'bad_day_part_time':
        return 'One of the times is not a valid time. Nothing was changed.';
      case 'empty_day_part':
        return 'A part starts and ends at the same time. Nothing was changed.';
      case 'bad_days_of_week':
        return 'One of the parts has days that are not valid. Nothing was changed.';
      case 'reachable_required':
      case 'bad_day_part':
        return 'One of the parts could not be saved. Nothing was changed.';
    }
    if (e.statusCode == 401) return 'This phone needs to sign in again before it can change her day.';
    if (e.statusCode == 403) return 'Your account is not allowed to change her day. Nothing was changed.';
    if (e.statusCode == 404) return 'Olive cannot find her on the server. Nothing was changed.';
    if (e.statusCode >= 500 || e.statusCode == 429 || e.statusCode == 408) {
      return 'The server could not take the change just now. Nothing was changed. Try again in a moment.';
    }
    return 'The server did not accept the change. Nothing was changed.';
  }
  return 'Olive could not reach the server, so her day was not changed. Try again when you are connected.';
}

// ================================================================ what is sent ==

/// What was made.
enum MediaKind { video, photo, voice }

String mediaKindWord(MediaKind k) => switch (k) {
      MediaKind.video => 'video',
      MediaKind.photo => 'photo',
      MediaKind.voice => 'voice recording',
    };

/// What the bytes prove they are, by their first bytes, exactly as the server decides (server/media_sniff.mjs):
/// JPEG, PNG, WebM, or an MP4 container (an M4A brand is a voice recording). Null for anything else, which the
/// server would refuse with 415, so the phone says so before uploading a large file for nothing.
MediaKind? sniffSendKind(List<int> b) {
  if (b.length >= 3 && b[0] == 0xff && b[1] == 0xd8 && b[2] == 0xff) return MediaKind.photo;
  if (b.length >= 8 &&
      b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4e && b[3] == 0x47 &&
      b[4] == 0x0d && b[5] == 0x0a && b[6] == 0x1a && b[7] == 0x0a) {
    return MediaKind.photo;
  }
  if (b.length >= 4 && b[0] == 0x1a && b[1] == 0x45 && b[2] == 0xdf && b[3] == 0xa3) return MediaKind.video;
  if (b.length >= 12 && String.fromCharCodes(b.sublist(4, 8)) == 'ftyp') {
    final String brand = String.fromCharCodes(b.sublist(8, 12));
    return const <String>['M4A ', 'M4B ', 'M4P '].contains(brand) ? MediaKind.voice : MediaKind.video;
  }
  return null;
}

// ============================================================ delivery choice ==

/// When the grown-up wants it to arrive.
enum SendMode { now, atDayPart, onNight }

/// The delivery choice for one message. Exactly the three things the server's `delivery` field takes.
class DeliveryChoice {
  const DeliveryChoice.now()
      : mode = SendMode.now,
        daypartKind = 'bedtime',
        localDate = null;
  const DeliveryChoice.atDayPart([this.daypartKind = 'bedtime'])
      : mode = SendMode.atDayPart,
        localDate = null;
  const DeliveryChoice.onNight(String this.localDate)
      : mode = SendMode.onNight,
        daypartKind = 'bedtime';

  final SendMode mode;

  /// The part of her day it lands at the start of. 'bedtime' for "now" and for a night (the server ignores it
  /// for "now" and uses the bedtime start for a night).
  final String daypartKind;

  /// "YYYY-MM-DD" in HER calendar, for [SendMode.onNight] only.
  final String? localDate;

  /// The fields POST .../messages takes: `delivery`, `daypart`, and `targetLocalDate` for a night only.
  Map<String, Object?> toWire() => switch (mode) {
        SendMode.now => <String, Object?>{'delivery': 'now', 'daypart': 'bedtime'},
        SendMode.atDayPart => <String, Object?>{'delivery': 'daypart', 'daypart': daypartKind},
        SendMode.onNight => <String, Object?>{
            'delivery': 'date', 'daypart': 'bedtime', 'targetLocalDate': localDate},
      };

  static DeliveryChoice? fromWire(Map<String, Object?> w) {
    switch (w['delivery']) {
      case 'now':
        return const DeliveryChoice.now();
      case 'daypart':
        final Object? k = w['daypart'];
        return k is String && k.isNotEmpty ? DeliveryChoice.atDayPart(k) : null;
      case 'date':
        final Object? d = w['targetLocalDate'];
        return d is String && parseLocalDate(d) != null ? DeliveryChoice.onNight(d) : null;
    }
    return null;
  }

  /// "Right away", "At her bedtime", "On Sat, Nov 21 at her bedtime".
  String describe() => switch (mode) {
        SendMode.now => 'Right away',
        SendMode.atDayPart => 'At her ${adultDayPartPhrase(daypartKind)}',
        SendMode.onNight => 'On ${describeLocalDate(localDate ?? '')} at her bedtime',
      };
}

/// A real calendar date from "YYYY-MM-DD", or null. `DateTime.parse` quietly turns 2026-02-30 into March 2, so
/// the round trip is checked.
DateTime? parseLocalDate(String? s) {
  if (s == null || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) return null;
  final DateTime? d = DateTime.tryParse('${s}T00:00:00Z');
  if (d == null) return null;
  final String back = '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
  return back == s ? d : null;
}

String localDateString(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

const List<String> _monthShort = <String>[
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// "Sat, Nov 21". A date that is not a real date is "that night".
String describeLocalDate(String s) {
  final DateTime? d = parseLocalDate(s);
  if (d == null) return 'that night';
  return '${_dayShort[d.weekday % 7]}, ${_monthShort[d.month - 1]} ${d.day}';
}

/// How far ahead a night may be picked.
const int kMaxNightsAhead = 365;

/// Why [date] cannot be the night, or null if it can. [phoneToday] is the sender's own date; her calendar can
/// be a day either side, so one day behind is allowed here and the server has the last word.
String? checkNight(String? date, DateTime phoneToday) {
  final DateTime? d = parseLocalDate(date);
  if (d == null) return 'Pick a night from the calendar.';
  final DateTime today = DateTime.utc(phoneToday.year, phoneToday.month, phoneToday.day);
  final int days = d.difference(today).inDays;
  if (days < -1) return 'That night has already passed. Pick a night from today on.';
  if (days > kMaxNightsAhead) return 'That is more than a year away. Pick a nearer night.';
  return null;
}

// ============================================================ the send-time guard ==

/// What the guard says about a choice, before it is sent.
enum GuardLevel { clear, quiet, blocked }

class SendGuard {
  const SendGuard(this.level, {this.headline = '', this.detail = ''});
  final GuardLevel level;
  final String headline;
  final String detail;
  bool get blocks => level == GuardLevel.blocked;
  bool get warns => level == GuardLevel.quiet;
}

const SendGuard kGuardClear = SendGuard(GuardLevel.clear);

String _quietNow(String? kind, String name) => switch (kind) {
      'asleep' => '$name is asleep right now',
      'school' => '$name is at school right now',
      _ => "$name's tablet is set to stay quiet right now",
    };

/// The send-time guard (MASTERFILE 6.4, sender side), now fed by her real schedule and the real clock check.
///
/// * [parts] is her schedule, or null when it could not be read: the guard then does not invent a block.
/// * [nowDayPart] and [reachable] are what GET .../now says about this moment in her day; either may be null.
///
/// "Right away" is never blocked by the server (an owner decision: an explicit send means send); the guard is
/// the grown-up's honest warning that it will not buzz her, with the choice left to them. A choice that
/// cannot land anywhere (no bedtime, or a part she does not have) is blocked, because the server would refuse
/// it or leave it waiting for ever.
SendGuard sendGuard({
  required DeliveryChoice choice,
  required String childName,
  required List<DayPartSpan>? parts,
  String? nowDayPart,
  bool? reachable,
}) {
  switch (choice.mode) {
    case SendMode.now:
      if (reachable == false) {
        return SendGuard(GuardLevel.quiet,
            headline: '${_quietNow(nowDayPart, childName)}.',
            detail: "If you send it now it goes into her inbox straight away, but her tablet stays quiet, so it "
                "won't buzz her. She'll find it the next time she opens her inbox. To have it arrive when she is "
                'up and about, choose another time.');
      }
      return kGuardClear;
    case SendMode.atDayPart:
    case SendMode.onNight:
      final String kind = choice.mode == SendMode.onNight ? 'bedtime' : choice.daypartKind;
      if (parts != null) {
        final Iterable<DayPartSpan> mine = parts.where((DayPartSpan p) => p.kind == kind);
        if (mine.isEmpty) {
          final String what = adultDayPartPhrase(kind);
          return SendGuard(GuardLevel.blocked,
              headline: "$childName's day has no $what yet.",
              detail: 'A message set for $what arrives when it starts, so it has nowhere to land. Add it in '
                  "$childName's day, or choose another time.");
        }
        if (mine.every((DayPartSpan p) => !p.reachable)) {
          return SendGuard(GuardLevel.quiet,
              headline: 'Her tablet is set to stay quiet then.',
              detail: 'It will be in her inbox when ${adultDayPartPhrase(kind)} starts, but it will not buzz her.');
        }
      }
      return kGuardClear;
  }
}

// ======================================================= what was sent, in words ==

/// A moment in HER clock as the server words it: `{day: today|tomorrow|yesterday|"Sat, Nov 21", time: "8:30 PM"}`.
class HerMoment {
  const HerMoment(this.day, this.time);
  final String day;
  final String time;

  static HerMoment? fromJson(Object? j) {
    if (j is! Map) return null;
    final Object? d = j['day'], t = j['time'];
    if (d is! String || t is! String || d.isEmpty || t.isEmpty || d.length > 24 || t.length > 12) return null;
    return HerMoment(_plain(d), _plain(t));
  }

  /// "today at 8:30 PM", "tomorrow at 8:30 PM", "on Sat, Nov 21 at 8:30 PM".
  String get phrase {
    final bool relative = day == 'today' || day == 'tomorrow' || day == 'yesterday';
    return relative ? '$day at $time' : 'on $day at $time';
  }
}

final RegExp _unsafeText = RegExp(r'[ -​-‏‪-‮⁦-⁩<>]');

/// A short string from the wire, drawn as text: control and direction characters and angle brackets removed.
String _plain(String s) => s.replaceAll(_unsafeText, '').trim();

/// The states the server reports for one of the caller's own sends.
enum SentState { waiting, delivered, opened, expired, revoked }

/// One row of GET .../sent, kept to what the page draws. Anything else the server adds is dropped.
class SentEntry {
  const SentEntry({
    required this.id,
    required this.state,
    required this.sentAt,
    required this.delivery,
    this.daypart,
    this.targetLocalDate,
    this.deliversHer,
    this.deliveredHer,
    this.receiptPhrase,
    this.deliversAt,
  });

  final String id;
  final SentState state;
  final DateTime? sentAt;
  final DeliveryChoice? delivery;
  final String? daypart;
  final String? targetLocalDate;
  final HerMoment? deliversHer;
  final HerMoment? deliveredHer;

  /// The server's own sentence in her frame: "Watched at 7:42 PM her time — at bedtime."
  final String? receiptPhrase;
  final DateTime? deliversAt;

  static final RegExp _id = RegExp(r'^[0-9a-fA-F-]{8,40}$');

  /// Null for a row that cannot be drawn honestly (a bad id, a state this client has no words for).
  static SentEntry? fromJson(Object? j) {
    if (j is! Map) return null;
    final Object? id = j['id'], st = j['state'];
    if (id is! String || !_id.hasMatch(id) || st is! String) return null;
    final SentState? state = switch (st) {
      'waiting' => SentState.waiting,
      'delivered' => SentState.delivered,
      'opened' => SentState.opened,
      'expired' => SentState.expired,
      'revoked' => SentState.revoked,
      _ => null,
    };
    if (state == null) return null;
    DateTime? when(Object? v) => v is String ? DateTime.tryParse(v) : null;
    DeliveryChoice? choice;
    final Object? dl = j['delivery'];
    if (dl == 'now') {
      choice = const DeliveryChoice.now();
    } else if (dl == 'daypart' && j['daypart'] is String) {
      choice = DeliveryChoice.atDayPart(_plain(j['daypart'] as String));
    } else if (dl == 'date' && j['targetLocalDate'] is String && parseLocalDate(j['targetLocalDate'] as String) != null) {
      choice = DeliveryChoice.onNight(j['targetLocalDate'] as String);
    }
    String? phrase;
    final Object? rc = j['receipt'];
    if (rc is Map && rc['phrase'] is String) {
      final String p = _plain(rc['phrase'] as String);
      if (p.isNotEmpty && p.length <= 160) phrase = p;
    }
    return SentEntry(
      id: id,
      state: state,
      sentAt: when(j['sentAt']),
      delivery: choice,
      daypart: choice?.mode == SendMode.atDayPart ? choice!.daypartKind : null,
      targetLocalDate: choice?.mode == SendMode.onNight ? choice!.localDate : null,
      deliversHer: HerMoment.fromJson(j['deliversHer']),
      deliveredHer: HerMoment.fromJson(j['deliveredHer']),
      receiptPhrase: phrase,
      deliversAt: when(j['deliversAt']),
    );
  }

  /// The short label on the row: Waiting, Delivered, Opened, Not delivered.
  String get stateLabel => switch (state) {
        SentState.waiting => 'Waiting',
        SentState.delivered => 'Delivered',
        SentState.opened => 'Opened',
        SentState.expired => 'Not delivered',
        SentState.revoked => 'Taken back',
      };

  /// What it means, in a sentence a worried grown-up can rely on.
  String statusLine(String childName) {
    switch (state) {
      case SentState.waiting:
        final DeliveryChoice? c = delivery;
        if (c != null && c.mode == SendMode.now) {
          return "On its way. It should reach $childName's inbox shortly.";
        }
        final HerMoment? at = deliversHer;
        final String what = switch (c?.mode) {
          SendMode.atDayPart => "$childName's ${adultDayPartPhrase(c!.daypartKind)}",
          SendMode.onNight => describeLocalDate(c!.localDate!),
          _ => 'the time you chose',
        };
        if (at != null) return 'Waiting for $what. It will arrive ${at.phrase}, her time.';
        if (c?.mode == SendMode.atDayPart || c?.mode == SendMode.onNight) {
          return "Waiting, but there is no time for it yet. $childName's day has no "
              '${adultDayPartPhrase(c!.mode == SendMode.onNight ? 'bedtime' : c.daypartKind)} to send it at. '
              'Add one in her day and it will be timed.';
        }
        return 'Waiting to be sent.';
      case SentState.delivered:
        final HerMoment? at = deliveredHer;
        return at != null
            ? "Delivered to $childName's inbox ${at.phrase}, her time. She has not opened it yet."
            : "Delivered to $childName's inbox. She has not opened it yet.";
      case SentState.opened:
        return receiptPhrase ?? 'Opened by $childName.';
      case SentState.expired:
        return 'This ran out before it could be delivered, so $childName never received it.';
      case SentState.revoked:
        return 'This was taken back before it was delivered.';
    }
  }
}

/// The server's `{messages: [...]}` answer: the rows that can be drawn, in the server's order (newest first).
List<SentEntry> parseSent(Map<String, dynamic> body) {
  final Object? raw = body['messages'];
  if (raw is! List) throw const FormatException('messages is not a list');
  return <SentEntry>[
    for (final Object? j in raw)
      if (SentEntry.fromJson(j) case final SentEntry e) e,
  ];
}

// ============================================================ when a send fails ==

/// How a failed send should be treated.
enum FailureKind {
  /// No answer from the server at all, or one that says "not now" (busy, restarting, sign in again): keep it,
  /// try again later. It is never lost and never reported as sent.
  keep,

  /// The server answered and said no: it will not work as it stands. Say why; do not retry blindly.
  refuse,
}

class SendFailure {
  const SendFailure(this.kind, this.text, {this.code});
  final FailureKind kind;

  /// A sentence for a grown-up. Never a status code or a server reason.
  final String text;

  /// A fixed, content-free word kept on a queued item (never a URL, an address or message text).
  final String? code;
}

/// Turns what a send threw into a decision and a sentence. Anything that is not the server's own answer (no
/// network, a timeout, a captive page that is not JSON) is "no answer": keep it.
SendFailure explainSendFailure(Object e, String childName) {
  if (e is! ApiException) {
    return const SendFailure(FailureKind.keep, "Couldn't reach the server, so it is saved on this phone.",
        code: 'offline');
  }
  final int s = e.statusCode;
  if (s == 401) {
    return const SendFailure(FailureKind.keep,
        'This phone needs to sign in again before it can send. It is saved here until then.',
        code: 'sign_in');
  }
  if (s == 408 || s == 429 || s >= 500) {
    return const SendFailure(FailureKind.keep, 'The server is busy right now, so it is saved on this phone to try again.',
        code: 'busy');
  }
  switch (e.error) {
    case 'unsupported_media_type':
      return const SendFailure(FailureKind.refuse,
          "That kind of file can't be sent. Use a photo (JPEG or PNG), a video (MP4 or WebM) or a voice recording (M4A).");
    case 'bad_bytes':
    case 'bytes_required':
    case 'empty_recording':
      return const SendFailure(FailureKind.refuse, 'That file looks empty or damaged. Pick it again.');
    case 'image_too_large':
      return const SendFailure(FailureKind.refuse, 'That picture is too big to send. Pick a smaller one.');
    case 'media_quota_exceeded':
      return SendFailure(FailureKind.refuse,
          "There is no room left for more messages for $childName right now, so this wasn't sent.");
    case 'daypart_undefined':
      return SendFailure(FailureKind.refuse,
          "$childName's day has no bedtime (or the part you chose) to send it at. Add one in her day, then send "
          'it again.');
    case 'target_date_in_past':
      return const SendFailure(FailureKind.refuse, 'That night has already passed, so it was not sent. Pick another night.');
    case 'already_expired':
      return const SendFailure(FailureKind.refuse, 'This has already run out of time, so it was not sent.');
    case 'delivery_unresolvable':
    case 'retention_shorter_than_delivery':
      return const SendFailure(FailureKind.refuse,
          "Olive couldn't work out when to deliver this. Try a different time.");
    case 'not_authorized':
    case 'storage_key_not_yours':
      return SendFailure(FailureKind.refuse,
          "Your account isn't allowed to send to $childName. Ask her other grown-up to check your access.");
    case 'child_not_found':
      return const SendFailure(FailureKind.refuse,
          "Olive can't find her on the server. Check that this phone is signed in to the right family.");
    case 'bad_delivery':
    case 'now_has_no_date':
    case 'date_required':
    case 'daypart_has_no_date':
    case 'child_cannot_send_now':
    case 'bad_storage_key':
    case 'storage_key_and_duration_ms_required':
      return const SendFailure(FailureKind.refuse,
          'Something about this message was set up wrong. Make it again from the start.');
  }
  if (s == 403) {
    return SendFailure(FailureKind.refuse, "Your account isn't allowed to send to $childName.");
  }
  return const SendFailure(FailureKind.refuse, 'The server did not accept this message.');
}

/// Every reason the send routes can answer with that [explainSendFailure] words (the contract test checks the
/// real routes against this list, so a new server reason cannot reach a grown-up as nothing).
const Set<String> kWordedSendReasons = <String>{
  'unsupported_media_type', 'bad_bytes', 'bytes_required', 'empty_recording', 'image_too_large',
  'media_quota_exceeded', 'daypart_undefined', 'target_date_in_past', 'already_expired',
  'delivery_unresolvable', 'retention_shorter_than_delivery', 'not_authorized', 'storage_key_not_yours',
  'child_not_found', 'bad_delivery', 'now_has_no_date', 'date_required', 'daypart_has_no_date',
  'child_cannot_send_now', 'bad_storage_key', 'storage_key_and_duration_ms_required',
  // Handled by the sender rather than worded: the upload's blob is gone (re-uploaded), the key is already
  // attached (the send had gone through), the busy-uploads answer (kept and retried).
  'storage_key_unknown', 'storage_key_in_use', 'too_many_uploads_in_flight',
  // Answered by the shared gateway before the handler runs.
  'child_sender_mismatch', 'child_cannot_preserve',
};
