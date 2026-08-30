// OLIVE BRANCH — shared calendar / day-part / receipt logic. UNVERIFIED (no
// Flutter toolchain in tools/verify.sh's automated pipeline). MASTERFILE
// §8.2, §8.2.4, §8.4, §9.4, §9.5.
//
// Pure-Dart logic shared by the five screens in this group (my_day.dart,
// weeks_screen.dart, receipt_screen.dart, inbox_screen.dart,
// guardian_home_live.dart) — a 1:1 port of
// the RELEVANT slices of three TS modules, not the whole of any of them:
//   - packages/phase3/src/phase3.ts       -> DAY_PART_META + scheduleStrip()
//   - packages/messaging/src/pipeline.ts  -> the openReceipt() phrase builder
//   - packages/calendar/src/calendar.ts   -> the whole-days date arithmetic
//     that also backs sleepsUntilBirthday()
//
// Kept close to the TS originals in name and shape (same reasoning as
// lock_controller.dart's header: it keeps the two auditable side by side),
// with one deliberate omission: anywhere the TS resolves a *timezone*
// (pipeline.ts's ctxZone, ChildCtx.tzIntervals) is left out on purpose. Zone
// resolution is a server concern — guardian_home.dart's header already
// establishes "All times arrive pre-rendered from /now and /ribbon so the
// client does no zone maths" — so every function below takes an
// already-local time string/label and classifies or formats it; none of them
// ever compute a zone offset.
//
// `dayPartColor()` below is this file's one deliberate exception to staying
// Flutter-free: `dart:ui`'s `Color` (not `package:flutter/material.dart` —
// the lightest real dependency that has it) is the shared kind->color
// lookup my_day.dart's own `_DayRibbon` already used privately. Extracted
// here, not left duplicated, so guardian_home_live.dart's own new ribbon
// (§20.2b) can render the SAME kind in the SAME color a child's own My Day
// screen already does, without a second, driftable copy of ten hex values.
// This does NOT reach into my_day.dart's own `_DayRibbon`/`_DayPartCard`
// widgets at all — those stay exactly as self-contained as that file's own
// header already documents; only the literal color VALUES move to one
// source of truth, sourced by my_day.dart the same way dayPartLabel()/
// dayPartGlyph() already are.
import 'dart:ui' show Color;

// ===================================================== day-part schedule ===
// Mirrors phase3.ts's DayPartLite / StripSegment / DAY_PART_META /
// scheduleStrip().
class DayPartLite {
  const DayPartLite({
    required this.kind,
    required this.startsLocal, // "HH:mm", 24h, zero-padded — matches the TS shape.
    required this.endsLocal,
    this.reachable = true,
  });
  final String kind;
  final String startsLocal;
  final String endsLocal;
  final bool reachable;
}

class StripSegment {
  const StripSegment({
    required this.kind,
    required this.label,
    required this.icon,
    required this.startsLocal,
    required this.endsLocal,
    required this.current,
    required this.next,
  });
  final String kind;
  final String label;
  final String icon;
  final String startsLocal;
  final String endsLocal;
  final bool current;
  final bool next;
}

class _DayPartMeta {
  const _DayPartMeta(this.label, this.glyph);
  final String label;
  final String glyph;
}

// Label and glyph share one row, same anti-drift reasoning as phase3.ts
// §8.2.2: the Day Ribbon's text and icon can never fall out of sync because
// there is no second lookup table for either to drift against.
const Map<String, _DayPartMeta> _dayPartMeta = <String, _DayPartMeta>{
  'wake': _DayPartMeta('wake up', '🌅'),
  'before_school': _DayPartMeta('get ready', '☀️'),
  'school': _DayPartMeta('school', '📚'),
  'after_school': _DayPartMeta('home time', '🏡'),
  'activity': _DayPartMeta('activity', '⚽'),
  'dinner': _DayPartMeta('dinner', '🌆'),
  'wind_down': _DayPartMeta('quiet time', '🌆'),
  'bedtime': _DayPartMeta('bedtime', '🌙'),
  'asleep': _DayPartMeta('sleep', '🌙'),
  'free': _DayPartMeta('free time', '☀️'),
};

const String fallbackGlyph = '•';

String dayPartLabel(String kind) =>
    _dayPartMeta[kind]?.label ?? kind.replaceAll('_', ' ');

String dayPartGlyph(String kind) => _dayPartMeta[kind]?.glyph ?? fallbackGlyph;

// Same ten values my_day.dart's own private `_dayPartColor` already used —
// copied here verbatim, not recomputed, so this extraction changes zero
// pixels on the screen that's had them since before this map existed here.
const Map<String, Color> _dayPartColor = <String, Color>{
  'wake': Color(0xFFFFB74D),
  'before_school': Color(0xFFFFD54F),
  'school': Color(0xFF64B5F6),
  'after_school': Color(0xFF81C784),
  'activity': Color(0xFFFF8A65),
  'dinner': Color(0xFFE57373),
  'wind_down': Color(0xFF9575CD),
  'bedtime': Color(0xFF7986CB),
  'asleep': Color(0xFF3949AB),
  'free': Color(0xFF4DD0E1),
};

const Color fallbackDayPartColor = Color(0xFFBDBDBD);

Color dayPartColor(String kind) => _dayPartColor[kind] ?? fallbackDayPartColor;

/// A 1:1 port of phase3.ts's `scheduleStrip()`: sort by start time, find the
/// segment containing `nowLocal` (wrap-aware, so an overnight span like
/// asleep 20:00→06:30 is handled the same way the TS handles it), and flag
/// the segment right after it as "next". The glyph is static — no pulse, no
/// spin — same "§8.13 gets no icon exception" rule the TS docstring states.
List<StripSegment> scheduleStrip(List<DayPartLite> parts, String nowLocal) {
  final List<DayPartLite> sorted = List<DayPartLite>.of(parts)
    ..sort((DayPartLite a, DayPartLite b) => a.startsLocal.compareTo(b.startsLocal));
  final int curIdx = sorted.indexWhere((DayPartLite p) =>
      p.startsLocal.compareTo(p.endsLocal) <= 0
          ? nowLocal.compareTo(p.startsLocal) >= 0 && nowLocal.compareTo(p.endsLocal) < 0
          : nowLocal.compareTo(p.startsLocal) >= 0 || nowLocal.compareTo(p.endsLocal) < 0);
  return <StripSegment>[
    for (int i = 0; i < sorted.length; i++)
      StripSegment(
        kind: sorted[i].kind,
        label: dayPartLabel(sorted[i].kind),
        icon: dayPartGlyph(sorted[i].kind),
        startsLocal: sorted[i].startsLocal,
        endsLocal: sorted[i].endsLocal,
        current: i == curIdx,
        next: curIdx != -1 && i == (curIdx + 1) % sorted.length,
      ),
  ];
}

/// The one currently-active segment out of `scheduleStrip`'s result, honestly.
///
/// A `parts` list that does not cover the full 24h leaves a genuine gap: a
/// stretch of the day no `DayPartLite` claims. When `nowLocal` falls inside
/// that gap, EVERY segment's `current` is false (see `scheduleStrip` above) —
/// there is no right answer to "what's happening now" to give. Returning
/// `null` here, instead of guessing (e.g. `segments.first`, the
/// chronologically-earliest part regardless of whether it's anywhere near
/// "now"), is what lets callers render an honest "nothing scheduled" state
/// rather than silently mislabelling the gap as whatever part sorts first.
StripSegment? currentSegment(List<StripSegment> segments) {
  for (final StripSegment s in segments) {
    if (s.current) return s;
  }
  return null;
}

/// Minutes since local midnight — the shape scheduleStrip's "HH:mm" strings
/// already assume, made explicit so the Day Ribbon can lay them out on a
/// 0..1 fraction of a day.
int minutesSinceMidnight(String hhmm) {
  final List<String> parts = hhmm.split(':');
  return int.parse(parts[0]) * 60 + int.parse(parts[1]);
}

/// "07:00" -> "7:00 AM". No intl dependency, same hand-rolled-formatter
/// posture as handover_notes.dart's `_nowLabel()`.
String formatTimeOfDay(String hhmm) {
  final int minsTotal = minutesSinceMidnight(hhmm);
  final int hour24 = (minsTotal ~/ 60) % 24;
  final int minute = minsTotal % 60;
  final int hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
  final String ampm = hour24 >= 12 ? 'PM' : 'AM';
  return '$hour12:${minute.toString().padLeft(2, '0')} $ampm';
}

/// "HH:mm" for right now, on the device's own clock. Stands in for a live
/// `/ribbon` endpoint that does not exist yet (see api_client.dart) — this
/// preview build has no choice but to assume the device is set to her own
/// timezone, which is the same honest-stub posture main.dart's demo data
/// already takes for the rest of the client.
String hhmmNow() {
  final DateTime n = DateTime.now();
  return '${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}';
}

// ============================================== the async-message receipt ==
/// A 1:1 port of the phrase half of pipeline.ts's `openReceipt()` — the zone
/// resolution half (`ctxZone`) is the server concern described in the file
/// header above, so it is intentionally not ported here.
///
/// `possessive` is "her"/"his"/"their" for a guardian-facing reading, or the
/// child's own name possessive ("Ivy's") for the child-facing reading these
/// screens use. pipeline.ts always renders "her"; substituting the name here
/// does not change the rule it stands in for — the local time she opened it
/// at, in day-part context, rendered first and only in her frame — it just
/// lets the same sentence read naturally when she is the one on screen.
const Map<String, String> _receiptDayPartContext = <String, String>{
  'wake': 'before school',
  'before_school': 'before school',
  'after_school': 'after school',
  'dinner': 'at dinner',
  'wind_down': 'winding down',
  'bedtime': 'at bedtime',
  'free': '',
  'school': 'at school',
  'asleep': '',
};

String watchedReceiptPhrase({
  required String timeLabel, // already formatted, e.g. "7:04 AM"
  required String possessive, // e.g. "Ivy's"
  String? dayPartKind,
}) {
  final String suffix =
      dayPartKind == null ? '' : (_receiptDayPartContext[dayPartKind] ?? '');
  return suffix.isEmpty
      ? 'Watched at $timeLabel $possessive time.'
      : 'Watched at $timeLabel $possessive time — $suffix.';
}

// ======================================================== sleeps, not dates
/// A 1:1 port of calendar.ts's whole-days date arithmetic — the same math
/// that backs `sleepsUntilBirthday()`, generalised to any two local dates so
/// weeks_screen.dart can say "in 3 sleeps" without ever rendering the ISO
/// dates it was computed from.
int sleepsBetween(String fromIso, String toIso) {
  final DateTime from = _parseIsoDateUtc(fromIso);
  final DateTime to = _parseIsoDateUtc(toIso);
  return to.difference(from).inDays;
}

DateTime _parseIsoDateUtc(String iso) {
  final int y = int.parse(iso.substring(0, 4));
  final int m = int.parse(iso.substring(5, 7));
  final int d = int.parse(iso.substring(8, 10));
  return DateTime.utc(y, m, d);
}

/// yyyy-MM-dd for a UTC-midnight DateTime — the inverse of `_parseIsoDateUtc`.
String isoDateOnly(DateTime utc) =>
    '${utc.year.toString().padLeft(4, '0')}-'
    '${utc.month.toString().padLeft(2, '0')}-'
    '${utc.day.toString().padLeft(2, '0')}';

// ============================================================ demo data ===
/// Demo-only day-part schedule shared by my_day.dart (renders it) and
/// inbox_screen.dart (classifies "now" against it to build a fresh receipt)
/// — the same "one shared primitive" reasoning calendar.ts gives for
/// `monthGrid()` being the ONE month renderer in the product. No live
/// `/ribbon` endpoint exists yet (api_client.dart), so this stands in for it
/// in exactly one place, honestly, rather than being re-guessed per screen.
const List<DayPartLite> demoDayParts = <DayPartLite>[
  DayPartLite(kind: 'asleep', startsLocal: '20:00', endsLocal: '06:30'),
  DayPartLite(kind: 'wake', startsLocal: '06:30', endsLocal: '07:00'),
  DayPartLite(kind: 'before_school', startsLocal: '07:00', endsLocal: '08:00'),
  DayPartLite(kind: 'school', startsLocal: '08:00', endsLocal: '15:00'),
  DayPartLite(kind: 'after_school', startsLocal: '15:00', endsLocal: '17:00'),
  DayPartLite(kind: 'activity', startsLocal: '17:00', endsLocal: '18:00'),
  DayPartLite(kind: 'dinner', startsLocal: '18:00', endsLocal: '18:30'),
  DayPartLite(kind: 'wind_down', startsLocal: '18:30', endsLocal: '19:30'),
  DayPartLite(kind: 'bedtime', startsLocal: '19:30', endsLocal: '20:00'),
];
