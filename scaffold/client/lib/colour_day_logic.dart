// OLIVE BRANCH — colour of the day: the sync rule, art-style settings and the
// play window. No longer UNVERIFIED — verified by CI (a Flutter toolchain runs
// for real in tools/verify.sh's automated pipeline). MASTERFILE §8.6.5, §8.6.6.
//
// A 1:1 semantic port of packages/palette/src/colour_day.ts, kept close to the
// TS original (same names, same shapes, same ordering of checks) and held to
// it by packages/palette/test/colour_day_vectors.json, which
// tools/gen-colour-vectors.mjs generates from the TS module. The server calls
// the TS module before every write; this port is what the phone uses to decide
// what to show and to merge its own offline answer, so the two can never
// disagree about which of two answers is the later one.
//
// There is no field here for a reason, a mood or a note: a colour is a fact
// (§8.6.4, P2).
import 'palette_logic.dart';

// ============================================================ art styles ====
const List<String> artStyles = ['paper', 'sticker', 'crayon', 'watercolour', 'felt', 'line', 'pixel'];

/// Pixel pairs with the coding activities and unlocks at 8 (§21).
const int pixelMinAge = 8;
const String defaultArtStyle = 'paper';

bool isArtStyle(Object? s) => s is String && artStyles.contains(s);

/// Styles a child of this age may be given. Unknown age is treated as young.
List<String> stylesForAge(int? ageYears) {
  final grown = ageYears != null && ageYears >= pixelMinAge;
  return [for (final s in artStyles) if (s != 'pixel' || grown) s];
}

class ArtSettings {
  const ArtSettings({
    required this.artStyle, required this.allowedStyles,
    required this.dailyQuestion, required this.codeActivities,
  });

  /// The style drawings default to. Always one of [allowedStyles].
  final String artStyle;
  /// The styles she may pick between while colouring.
  final List<String> allowedStyles;
  /// Whether the daily "which do you like more?" question is asked at all.
  final bool dailyQuestion;
  /// Path code and Pixel garden (the two coding activities).
  final bool codeActivities;

  Map<String, dynamic> toJson() => {
    'artStyle': artStyle, 'allowedStyles': allowedStyles,
    'dailyQuestion': dailyQuestion, 'codeActivities': codeActivities,
  };

  static ArtSettings? fromJson(Object? j) {
    if (j is! Map) return null;
    final a = j['allowedStyles'];
    if (!isArtStyle(j['artStyle']) || a is! List || !a.every(isArtStyle)
        || j['dailyQuestion'] is! bool || j['codeActivities'] is! bool) {
      return null;
    }
    return ArtSettings(
      artStyle: j['artStyle'] as String, allowedStyles: a.cast<String>().toList(),
      dailyQuestion: j['dailyQuestion'] as bool, codeActivities: j['codeActivities'] as bool);
  }

  ArtSettings copyWith({String? artStyle, List<String>? allowedStyles,
      bool? dailyQuestion, bool? codeActivities}) => ArtSettings(
    artStyle: artStyle ?? this.artStyle,
    allowedStyles: allowedStyles ?? this.allowedStyles,
    dailyQuestion: dailyQuestion ?? this.dailyQuestion,
    codeActivities: codeActivities ?? this.codeActivities);
}

const ArtSettings defaultArtSettings = ArtSettings(
  artStyle: defaultArtStyle,
  allowedStyles: ['paper', 'sticker', 'crayon', 'watercolour', 'felt', 'line'],
  dailyQuestion: true,
  codeActivities: true,
);

class ArtPatchResult {
  const ArtPatchResult.ok(this.settings) : ok = true, reason = null;
  const ArtPatchResult.err(this.reason) : ok = false, settings = null;
  final bool ok;
  final ArtSettings? settings;
  final String? reason;
}

const List<String> _artKeys = ['artStyle', 'allowedStyles', 'dailyQuestion', 'codeActivities'];

/// Apply a guardian's partial update to the stored settings. Unknown keys are
/// refused, not ignored, and the result is only ever a state the table's CHECKs
/// also admit — so a bad body is a specific reason, never a database error.
ArtPatchResult mergeArtSettings(ArtSettings current, Object? patch, int? ageYears) {
  if (patch is! Map) return const ArtPatchResult.err('body_must_be_object');
  final keys = patch.keys.toList();
  if (keys.any((k) => !_artKeys.contains(k))) return const ArtPatchResult.err('unknown_field');
  if (keys.isEmpty) return const ArtPatchResult.err('empty_body');
  var artStyle = current.artStyle;
  var allowed = List<String>.of(current.allowedStyles);
  var dailyQuestion = current.dailyQuestion;
  var codeActivities = current.codeActivities;
  if (patch.containsKey('artStyle')) {
    final s = patch['artStyle'];
    if (!isArtStyle(s)) return const ArtPatchResult.err('bad_artStyle');
    artStyle = s as String;
  }
  if (patch.containsKey('allowedStyles')) {
    final a = patch['allowedStyles'];
    if (a is! List || a.isEmpty || a.length > artStyles.length || !a.every(isArtStyle)
        || a.toSet().length != a.length) {
      return const ArtPatchResult.err('bad_allowedStyles');
    }
    // Canonical order, so two guardians saving the same set agree exactly.
    allowed = [for (final s in artStyles) if (a.contains(s)) s];
  }
  if (patch.containsKey('dailyQuestion')) {
    final b = patch['dailyQuestion'];
    if (b is! bool) return const ArtPatchResult.err('bad_dailyQuestion');
    dailyQuestion = b;
  }
  if (patch.containsKey('codeActivities')) {
    final b = patch['codeActivities'];
    if (b is! bool) return const ArtPatchResult.err('bad_codeActivities');
    codeActivities = b;
  }
  final ok = stylesForAge(ageYears);
  if (allowed.any((s) => !ok.contains(s)) || !ok.contains(artStyle)) {
    return const ArtPatchResult.err('style_not_for_age');
  }
  if (!allowed.contains(artStyle)) return const ArtPatchResult.err('style_not_allowed');
  return ArtPatchResult.ok(ArtSettings(
    artStyle: artStyle, allowedStyles: allowed,
    dailyQuestion: dailyQuestion, codeActivities: codeActivities));
}

// ============================================================ the day row ===
class DayColour {
  const DayColour({
    required this.localDate, required this.colourId, required this.chosenBy,
    required this.override, required this.chosenAtMs,
  });

  /// yyyy-mm-dd in HER home zone at the moment of choosing.
  final String localDate;
  final String colourId;
  /// 'child' | 'guardian'
  final String chosenBy;
  /// A guardian's colour day. Her own taps do not replace it.
  final bool override;
  /// Epoch ms. For a child's answer this is the clamped time she answered.
  final num chosenAtMs;

  Map<String, dynamic> toJson() => {
    'localDate': localDate, 'colourId': colourId, 'chosenBy': chosenBy,
    'override': override, 'chosenAtMs': chosenAtMs,
  };

  static DayColour fromJson(Map<dynamic, dynamic> j) => DayColour(
    localDate: j['localDate'] as String, colourId: j['colourId'] as String,
    chosenBy: j['chosenBy'] as String, override: j['override'] as bool,
    chosenAtMs: j['chosenAtMs'] is String ? double.nan : j['chosenAtMs'] as num);
}

/// A device may report an answer it made offline, but not an old or future one.
const int maxAnswerAgeMs = 12 * 3600 * 1000;
const int maxClockSkewMs = 5 * 60 * 1000;

/// The time a child's answer counts as having been given. A device clock is
/// not trusted: a missing, non-numeric, future or very old time collapses to
/// "now", and an offline answer keeps its own time only within the last 12
/// hours.
int clampAnsweredAt(Object? answeredAtMs, int nowMs) {
  if (answeredAtMs is! num || !answeredAtMs.isFinite) return nowMs;
  if (answeredAtMs > nowMs + maxClockSkewMs) return nowMs;
  if (answeredAtMs > nowMs) return nowMs;
  if (answeredAtMs < nowMs - maxAnswerAgeMs) return nowMs;
  return answeredAtMs.floor();
}

bool isLocalDate(Object? s) {
  if (s is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) return false;
  final d = DateTime.tryParse('${s}T00:00:00Z');
  if (d == null) return false;
  String p(int n, int w) => n.toString().padLeft(w, '0');
  return '${p(d.year, 4)}-${p(d.month, 2)}-${p(d.day, 2)}' == s;
}

class MergeOutcome {
  const MergeOutcome.ok(DayColour this.row, bool this.changed, String this.kept)
      : ok = true, reason = null;
  const MergeOutcome.err(this.reason) : ok = false, row = null, changed = null, kept = null;
  final bool ok;
  final DayColour? row;
  final bool? changed;
  /// 'incoming' | 'existing'
  final String? kept;
  /// 'unknown_colour' | 'bad_shape' | 'wrong_day' | 'override_holds'
  final String? reason;
}

/// The whole rule, for one (child, date). [existing] is the stored row for the
/// incoming write's date, or null when nobody has answered that day yet.
///
///  - A child's answer never replaces a guardian's colour day.
///  - A guardian's colour day replaces her answer, whichever is later (it is a
///    deliberate act made online), but only the later of two colour days wins.
///  - Otherwise the later answer wins; an older answer that arrives late is
///    acknowledged, not applied (kept: existing) so a slow device converges.
MergeOutcome mergeDay(DayColour? existing, DayColour incoming) {
  if (swatchFor(incoming.colourId) == null) return const MergeOutcome.err('unknown_colour');
  if (!isLocalDate(incoming.localDate) || !incoming.chosenAtMs.isFinite) {
    return const MergeOutcome.err('bad_shape');
  }
  if ((incoming.chosenBy == 'guardian') != incoming.override) return const MergeOutcome.err('bad_shape');
  if (incoming.chosenBy != 'child' && incoming.chosenBy != 'guardian') {
    return const MergeOutcome.err('bad_shape');
  }
  if (existing == null) return MergeOutcome.ok(incoming, true, 'incoming');
  if (existing.localDate != incoming.localDate) return const MergeOutcome.err('wrong_day');
  if (incoming.chosenBy == 'child' && existing.override) return const MergeOutcome.err('override_holds');
  final replaces = incoming.chosenBy == 'guardian' && !existing.override
      ? true
      : incoming.chosenAtMs >= existing.chosenAtMs;
  if (!replaces) return MergeOutcome.ok(existing, false, 'existing');
  final changed = existing.colourId != incoming.colourId || existing.override != incoming.override
      || existing.chosenBy != incoming.chosenBy;
  return MergeOutcome.ok(incoming, changed, 'incoming');
}

/// The most recent day's row, or null if she has never answered.
DayColour? currentDay(List<DayColour> days) {
  DayColour? best;
  for (final d in days) {
    if (best == null || d.localDate.compareTo(best.localDate) > 0
        || (d.localDate == best.localDate && d.chosenAtMs > best.chosenAtMs)) {
      best = d;
    }
  }
  return best;
}

/// The colour she is wearing today: today's row, else the last one she had.
DayColour? colourToday(List<DayColour> days, String localDate) {
  final today = currentDay(days.where((d) => d.localDate == localDate).toList());
  return today ?? currentDay(days.where((d) => d.localDate.compareTo(localDate) < 0).toList());
}

/// One question a day. Asked only if the guardian has not switched it off and
/// no row exists for today (so an answer on any of her devices ends the
/// question on all of them, and so does a colour day).
bool needsQuestion(List<DayColour> days, String localDate, bool dailyQuestion) {
  if (!dailyQuestion) return false;
  return !days.any((d) => d.localDate == localDate);
}

/// Does this device already show today's answer? Drives the "Matches" chip.
bool deviceMatches(List<DayColour> days, String localDate, {String? seenColourId}) {
  final today = colourToday(days, localDate);
  if (today == null || seenColourId == null) return false;
  return seenColourId == today.colourId;
}

/// The guardian's view, via parentView(): one neutral sentence. Each day
/// becomes one ColourChoice dated at local noon UTC, so the date part
/// parentView() compares is her LOCAL date, not a UTC accident.
List<ColourChoice> toChoices(List<DayColour> days) {
  final sorted = List<DayColour>.of(days)
    ..sort((a, b) {
      final c = a.localDate.compareTo(b.localDate);
      return c != 0 ? c : a.chosenAtMs.compareTo(b.chosenAtMs);
    });
  return [for (final d in sorted)
    ColourChoice(colourId: d.colourId, chosenAt: '${d.localDate}T12:00:00.000Z', via: 'daily')];
}

ParentColourView? guardianView(List<DayColour> days, String localDate) =>
    parentView(toChoices(days), '${localDate}T12:00:00.000Z');

// ========================================================= the play window ==
/// A guardian sets when games are open on her device. The ending is a goodnight
/// in her own frame, not a limit she can run into: during the wind-down a game
/// in progress may finish; after it, games rest until the window opens again.
/// Calls and family messages are never gated here — this module has no input
/// that could gate them.
class PlayWindow {
  const PlayWindow({required this.opensMin, required this.restsMin, required this.windDownMin});
  /// Minutes after local midnight, 0..1439.
  final int opensMin;
  /// Minutes after local midnight, opensMin < restsMin <= 1439.
  final int restsMin;
  /// 0, 15 or 30: the gentle tail before [restsMin].
  final int windDownMin;

  Map<String, dynamic> toJson() => {'opensMin': opensMin, 'restsMin': restsMin, 'windDownMin': windDownMin};

  static PlayWindow? fromJson(Object? j) {
    if (j is! Map) return null;
    final o = j['opensMin'], r = j['restsMin'], w = j['windDownMin'];
    if (o is! int || r is! int || w is! int) return null;
    return PlayWindow(opensMin: o, restsMin: r, windDownMin: w);
  }

  @override
  bool operator ==(Object other) => other is PlayWindow
      && other.opensMin == opensMin && other.restsMin == restsMin && other.windDownMin == windDownMin;
  @override
  int get hashCode => Object.hash(opensMin, restsMin, windDownMin);
}

const List<int> windDownChoices = [0, 15, 30];

class PlayWindowCheck {
  const PlayWindowCheck.ok(this.window) : ok = true, reason = null;
  const PlayWindowCheck.err(this.reason) : ok = false, window = null;
  final bool ok;
  final PlayWindow? window;
  final String? reason;
}

bool _isMinute(Object? n) =>
    n is num && n.isFinite && n == n.roundToDouble() && n >= 0 && n <= 1439;

PlayWindowCheck checkPlayWindow(Object? input) {
  if (input is! Map) return const PlayWindowCheck.err('body_must_be_object');
  if (input.keys.any((k) => !const ['opensMin', 'restsMin', 'windDownMin'].contains(k))) {
    return const PlayWindowCheck.err('unknown_field');
  }
  final o = input['opensMin'], r = input['restsMin'], w = input['windDownMin'];
  if (!_isMinute(o)) return const PlayWindowCheck.err('bad_opensMin');
  if (!_isMinute(r) || (r as num) <= (o as num)) return const PlayWindowCheck.err('bad_restsMin');
  if (w is! num || !windDownChoices.contains(w)) return const PlayWindowCheck.err('bad_windDownMin');
  if (r - o < w + 15) return const PlayWindowCheck.err('window_too_short');
  return PlayWindowCheck.ok(PlayWindow(opensMin: o.toInt(), restsMin: r.toInt(), windDownMin: w.toInt()));
}

/// [minuteOfDay] is HER local minute, 0..1439. 'open' | 'winding_down' | 'resting'.
String playWindowState(PlayWindow? w, int minuteOfDay) {
  if (w == null) return 'open';
  if (minuteOfDay < w.opensMin || minuteOfDay >= w.restsMin) return 'resting';
  if (w.windDownMin > 0 && minuteOfDay >= w.restsMin - w.windDownMin) return 'winding_down';
  return 'open';
}

/// Minutes games stay open each day.
int windowLength(PlayWindow w) => w.restsMin - w.opensMin;

/// "If you make the window longer, the other guardian is told. Shorter is
/// never reported." A new window is longer if it opens earlier or rests later.
bool isLonger(PlayWindow? prev, PlayWindow next) {
  if (prev == null) return false;
  return next.opensMin < prev.opensMin || next.restsMin > prev.restsMin;
}

/// Copy for the three states. One calm sentence, no number, nothing taken away.
String? playWindowLine(String state) {
  if (state == 'winding_down') return 'It’s getting sleepy. One more, then goodnight.';
  if (state == 'resting') return 'Games are resting now. They’ll be back tomorrow.';
  return null;
}
