// OLIVE BRANCH — the calendar primitive, and her birthday. UNVERIFIED (no
// Flutter toolchain in tools/verify.sh's automated pipeline). MASTERFILE
// §8.7, §9.4.
//
// A 1:1 semantic port of packages/calendar/src/calendar.ts, kept close to the
// TS original (same names, same shapes, same ordering) so the two stay
// auditable side by side — the same discipline lock_controller.dart already
// applies to lock.ts.
//
// `monthGrid()` is meant to be the ONE month renderer in the product — the
// child's calendar (§9.4), the guardian's, and this birthday picker all read
// it. Only the pieces this group's three birthday screens actually need are
// ported (the grid, the year-deriving picker, and the permanent marker);
// whichever group builds the full My day / Weeks calendars should read this
// same file rather than re-deriving the grid.

// ================================================== the shared month grid ===
class MonthMeta {
  const MonthMeta({required this.index, required this.name, required this.short, required this.days});
  final int index;
  final String name;
  final String short;
  final int days;
}

/// Names, not numbers. A child reads "March", not "03".
const List<MonthMeta> months = [
  MonthMeta(index: 1,  name: 'January',   short: 'Jan', days: 31),
  MonthMeta(index: 2,  name: 'February',  short: 'Feb', days: 28),
  MonthMeta(index: 3,  name: 'March',     short: 'Mar', days: 31),
  MonthMeta(index: 4,  name: 'April',     short: 'Apr', days: 30),
  MonthMeta(index: 5,  name: 'May',       short: 'May', days: 31),
  MonthMeta(index: 6,  name: 'June',      short: 'Jun', days: 30),
  MonthMeta(index: 7,  name: 'July',      short: 'Jul', days: 31),
  MonthMeta(index: 8,  name: 'August',    short: 'Aug', days: 31),
  MonthMeta(index: 9,  name: 'September', short: 'Sep', days: 30),
  MonthMeta(index: 10, name: 'October',   short: 'Oct', days: 31),
  MonthMeta(index: 11, name: 'November',  short: 'Nov', days: 30),
  MonthMeta(index: 12, name: 'December',  short: 'Dec', days: 31),
];

/// US market scope (§1), so weeks begin on Sunday.
const int weekStartsOn = 0;
const List<String> dowShort = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

bool isLeap(int y) => (y % 4 == 0 && y % 100 != 0) || y % 400 == 0;

int daysInMonth(int year, int month) {
  if (month == 2) return isLeap(year) ? 29 : 28;
  return months[month - 1].days;
}

class Cell {
  const Cell({required this.day, required this.iso, required this.dow,
    required this.isToday, required this.markers});
  /// null for the leading and trailing blanks.
  final int? day;
  final String? iso;
  final int dow;
  final bool isToday;
  final List<String> markers;
}

class MonthGridResult {
  const MonthGridResult({required this.year, required this.month, required this.name,
    required this.cells, required this.weeks});
  final int year;
  final int month;
  final String name;
  final List<Cell> cells;
  final int weeks;
}

String _pad2(int n) => n.toString().padLeft(2, '0');

/// One month, aligned to the week. Blanks are real cells, so every consumer
/// gets a stable 7-column grid and nobody has to compute offsets.
MonthGridResult monthGrid(int year, int month, {DateTime? today, Map<String, List<String>>? markers}) {
  final total = daysInMonth(year, month);
  final firstDow = DateTime.utc(year, month, 1).weekday % 7; // Dart: Mon=1..Sun=7 -> Sun=0
  final lead = (firstDow - weekStartsOn + 7) % 7;
  final todayIso = today != null
      ? '${today.year}-${_pad2(today.month)}-${_pad2(today.day)}' : null;

  final cells = <Cell>[];
  for (var i = 0; i < lead; i++) {
    cells.add(Cell(day: null, iso: null, dow: (weekStartsOn + i) % 7, isToday: false, markers: const []));
  }
  for (var d = 1; d <= total; d++) {
    final iso = '$year-${_pad2(month)}-${_pad2(d)}';
    final dow = DateTime.utc(year, month, d).weekday % 7;
    cells.add(Cell(day: d, iso: iso, dow: dow, isToday: iso == todayIso, markers: markers?[iso] ?? const []));
  }
  while (cells.length % 7 != 0) {
    cells.add(Cell(day: null, iso: null, dow: cells.length % 7, isToday: false, markers: const []));
  }
  return MonthGridResult(year: year, month: month, name: months[month - 1].name,
    cells: cells, weeks: cells.length ~/ 7);
}

// ============================================== deriving the birth year =====
/// She just told us how old she is (§8.5.2). That plus one yes/no question
/// resolves the year, so she is never asked to reason about a number she has
/// no way to know.
int deriveBirthYear(int age, bool hadBirthdayThisYear, DateTime now) =>
    now.year - age - (hadBirthdayThisYear ? 0 : 1);

/// When a guardian has already entered a birth date it is AUTHORITATIVE
/// (§8.5.2), and the picker's job changes: she is not entering data, she is
/// placing her own birthday on a calendar. Highlighting the right month makes
/// the hunt short and successful without doing it for her.
int? hintMonth(String? birthDate) {
  if (birthDate == null) return null;
  final m = int.tryParse(birthDate.substring(5, 7));
  return (m != null && m >= 1 && m <= 12) ? m : null;
}

const int hintFadesAtAge = 9;

/// Scaffolding that withdraws, exactly as §21.5 requires — no hint at all
/// from age nine.
bool shouldHint(String? birthDate, int? age) =>
    birthDate != null && (age == null || age < hintFadesAtAge);

// ================================================== the birthday picker =====
enum PickerStep { month, day, yearCheck, done }

class BirthdayPicker {
  const BirthdayPicker({required this.step, this.month, this.day, this.year,
    required this.authoritative, required this.age});

  final PickerStep step;
  final int? month;
  final int? day;
  final int? year;
  /// Guardian-entered, if any. Authoritative for the record.
  final String? authoritative;
  /// Her age, used to derive the year.
  final int? age;

  BirthdayPicker copyWith({PickerStep? step, int? month, bool clearMonth = false,
      int? day, bool clearDay = false, int? year}) => BirthdayPicker(
    step: step ?? this.step,
    month: clearMonth ? null : (month ?? this.month),
    day: clearDay ? null : (day ?? this.day),
    year: year ?? this.year,
    authoritative: authoritative, age: age,
  );
}

BirthdayPicker beginPicker(String? authoritative, int? age) =>
    BirthdayPicker(step: PickerStep.month, authoritative: authoritative, age: age);

/// 'no_such_day' | 'in_the_future' | 'no_age'
enum PickerError { noSuchDay, inTheFuture, noAge }

BirthdayPicker pickMonth(BirthdayPicker p, int month) {
  if (month < 1 || month > 12) return p;
  return p.copyWith(month: month, clearDay: true, step: PickerStep.day);
}

class PickDayOutcome {
  const PickDayOutcome.ok(this.picker) : ok = true, reason = null;
  const PickDayOutcome.err(this.reason) : ok = false, picker = null;
  final bool ok;
  final BirthdayPicker? picker;
  final PickerError? reason;
}

PickDayOutcome pickDay(BirthdayPicker p, int day, DateTime now) {
  if (p.month == null) return const PickDayOutcome.err(PickerError.noSuchDay);
  // A leap year as the ceiling so 29 February is selectable before the year
  // is known. The year check that follows resolves whether it exists.
  if (day < 1 || day > daysInMonth(2024, p.month!)) {
    return const PickDayOutcome.err(PickerError.noSuchDay);
  }
  if (p.authoritative != null) {
    final y = int.parse(p.authoritative!.substring(0, 4));
    return PickDayOutcome.ok(p.copyWith(day: day, year: y, step: PickerStep.done));
  }
  if (p.age == null) return const PickDayOutcome.err(PickerError.noAge);
  return PickDayOutcome.ok(p.copyWith(day: day, step: PickerStep.yearCheck));
}

class AnswerYearCheckOutcome {
  const AnswerYearCheckOutcome.ok(this.picker) : ok = true, reason = null;
  const AnswerYearCheckOutcome.err(this.reason) : ok = false, picker = null;
  final bool ok;
  final BirthdayPicker? picker;
  final PickerError? reason;
}

AnswerYearCheckOutcome answerYearCheck(BirthdayPicker p, bool hadBirthdayThisYear, DateTime now) {
  if (p.age == null) return const AnswerYearCheckOutcome.err(PickerError.noAge);
  final year = deriveBirthYear(p.age!, hadBirthdayThisYear, now);
  final iso = DateTime.utc(year, p.month!, p.day!);
  if (iso.isAfter(now)) return const AnswerYearCheckOutcome.err(PickerError.inTheFuture);
  return AnswerYearCheckOutcome.ok(p.copyWith(year: year, step: PickerStep.done));
}

String? pickedDate(BirthdayPicker p) {
  if (p.month == null || p.day == null || p.year == null) return null;
  return '${p.year}-${_pad2(p.month!)}-${_pad2(p.day!)}';
}

class ResolvedBirthday {
  const ResolvedBirthday({required this.ofRecord, required this.asShePlacedIt, required this.disagrees});
  final String? ofRecord;
  final String? asShePlacedIt;
  final bool disagrees;
}

/// She is not corrected about her own birthday. If she places it a day out,
/// the guardian's date remains of record and nobody mentions it (§8.7.4).
ResolvedBirthday resolveBirthday(BirthdayPicker p) {
  final hers = pickedDate(p);
  final ofRecord = p.authoritative ?? hers;
  return ResolvedBirthday(ofRecord: ofRecord, asShePlacedIt: hers,
    disagrees: p.authoritative != null && hers != null && p.authoritative != hers);
}

// ================================================ the permanent marker ======
/// 29 February needs an explicit rule or the event silently vanishes three
/// years out of four. Observed on 28 February in a common year, which keeps
/// the birthday inside the correct month.
const int leapDayObservedMonth = 2, leapDayObservedDay = 28;

class BirthdayEvent {
  const BirthdayEvent({required this.childId, required this.month, required this.day,
    required this.colourId, required this.placedByChild, required this.markedAt});

  final String childId;
  /// Month and day. The year lives on the child record, not the event.
  final int month;
  final int day;
  /// §8.6 — her colour, on an allowed placement.
  final String? colourId;
  /// Annual, forever.
  static const String recurrence = 'yearly';
  /// A birthday is a fact, so a guardian cannot delete it.
  static const bool deletableByGuardian = false;
  /// She placed it herself. Recorded because it mattered to her.
  final bool placedByChild;
  final String markedAt;
}

class MarkBirthdayOutcome {
  const MarkBirthdayOutcome.ok(this.event) : ok = true;
  const MarkBirthdayOutcome.err() : ok = false, event = null;
  final bool ok;
  final BirthdayEvent? event;
}

MarkBirthdayOutcome markBirthday(String childId, BirthdayPicker p, String? colourId, String at) {
  final r = resolveBirthday(p);
  if (r.ofRecord == null) return const MarkBirthdayOutcome.err();
  return MarkBirthdayOutcome.ok(BirthdayEvent(
    childId: childId,
    month: int.parse(r.ofRecord!.substring(5, 7)),
    day: int.parse(r.ofRecord!.substring(8, 10)),
    colourId: colourId,
    placedByChild: r.asShePlacedIt != null,
    markedAt: at,
  ));
}

/// The ISO date this birthday falls on in a given year.
String occurrenceIn(BirthdayEvent e, int year) {
  if (e.month == 2 && e.day == 29 && !isLeap(year)) {
    return '$year-${_pad2(leapDayObservedMonth)}-${_pad2(leapDayObservedDay)}';
  }
  return '$year-${_pad2(e.month)}-${_pad2(e.day)}';
}

int sleepsUntilBirthday(BirthdayEvent e, String todayIso) {
  final y = int.parse(todayIso.substring(0, 4));
  var next = occurrenceIn(e, y);
  if (next.compareTo(todayIso) < 0) next = occurrenceIn(e, y + 1);
  final d0 = DateTime.parse(todayIso), d1 = DateTime.parse(next);
  return d1.difference(d0).inDays;
}

/// §9.4 — her calendar begins with her own birthday, not a custody exchange.
/// The first entry a child ever sees in a co-parenting product should be a
/// thing she is looking forward to.
class FirstCalendarEntry {
  const FirstCalendarEntry({required this.label, required this.markers});
  final String label;
  final List<String> markers;
}

FirstCalendarEntry firstCalendarEntry(BirthdayEvent e) =>
    const FirstCalendarEntry(label: 'My birthday', markers: ['birthday']);
