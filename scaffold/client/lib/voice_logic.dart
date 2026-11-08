// OLIVE BRANCH — suite C VOICE, pure logic: feelings weather, worry box, my
// helpers, symbols. No longer UNVERIFIED — verified by CI
// (client/test/voice_logic_test.dart).
//
// OFFLINE AND ON-DEVICE ONLY, and PRIVATE FIRST. Nothing here opens a socket and
// nothing is shared between a child's homes (parked). What she puts in the
// weather picker or the worry box lives on this device, sealed, and is shown to
// nobody automatically.
//
// RULES HELD IN THE TYPES (each has a test):
//  - FEELINGS WEATHER is a picture of weather for how today feels. It is a sky,
//    not a mood: no label is "good" or "bad", and her colour stays a fact. Only
//    TODAY's pick is kept (older ones are dropped on the next write and ignored
//    on read), so there is no history to chart. [FeelingToday] has no
//    "shared with" field at all.
//  - THE WORRY BOX holds a tapped picture or a drawing, never text. A worry is
//    shown to a grown-up ONLY if she chooses "show my grown-up", and she can take
//    that back. "Let it float away" removes it for real. Nothing here reads,
//    interprets, tags, scores or counts a worry, and a grown-up's view is the
//    picture or drawing exactly as she made it (P7).
//  - MY HELPERS are the grown-ups she can go to, authored by a guardian, with a
//    picture each. A helper appears to her only after a guardian records that the
//    person has said yes. Nothing here dials, messages or locates anyone.
//  - SYMBOLS are an AAC-style board she taps to build a short strip. The strip is
//    read as a plain word-for-word sentence (never rewritten) and is NOT kept.
library;

import 'picture_library.dart';
import 'rhythm_logic.dart' show RvRefused, cleanText, isIdLike, isIsoDay, looksLikePhoneNumber, maxLineChars;

// ======================================================= FEELINGS WEATHER ====
/// The six skies she can pick, in a fixed order. Order is not a scale.
const List<String> weatherIds = <String>['sunny', 'cloudy', 'rainy', 'stormy', 'windy', 'foggy'];

bool isWeather(Object? id) => id is String && weatherIds.contains(id);

/// Today's pick. Two fields: which sky, and which day. Nothing else exists to be
/// stored, shared, counted or charted.
class FeelingToday {
  const FeelingToday({required this.weather, required this.day});
  final String weather;
  final String day;
  Map<String, Object?> toJson() => <String, Object?>{'weather': weather, 'day': day};
  static FeelingToday? tryFromJson(Object? j) {
    if (j is! Map || !isWeather(j['weather']) || !isIsoDay(j['day'])) return null;
    return FeelingToday(weather: j['weather']! as String, day: j['day']! as String);
  }
}

FeelingToday pickWeather(String id, String day) {
  if (!isWeather(id)) throw const RvRefused('bad_weather');
  if (!isIsoDay(day)) throw const RvRefused('bad_day');
  return FeelingToday(weather: id, day: day);
}

/// A pick from an earlier day is not "yesterday's feeling": it is gone.
FeelingToday? feelingForToday(FeelingToday? f, String today) => f != null && f.day == today ? f : null;

// ============================================================== WORRY BOX ====
const int maxWorries = 24;
const int maxStrokes = 40;
const int maxPointsPerStroke = 120;

enum WorryKind { picture, drawing }

class Worry {
  const Worry._({required this.id, required this.kind, required this.madeOn, required this.shown,
      this.picture, this.strokes});

  /// A worry she made by tapping a picture.
  factory Worry.picture({required String id, required String picture, required String madeOn, bool shown = false}) {
    if (!isIdLike(id)) throw const RvRefused('bad_id');
    if (!isPictureIn(picture, const <PictureGroup>{PictureGroup.worry})) throw const RvRefused('bad_picture');
    if (!isIsoDay(madeOn)) throw const RvRefused('bad_day');
    return Worry._(id: id, kind: WorryKind.picture, madeOn: madeOn, shown: shown, picture: picture);
  }

  /// A worry she drew. [strokes] are lists of points normalised to 0..1, each
  /// stroke flattened as [x0, y0, x1, y1, ...].
  factory Worry.drawing({required String id, required List<List<double>> strokes, required String madeOn,
      bool shown = false}) {
    if (!isIdLike(id)) throw const RvRefused('bad_id');
    if (!isIsoDay(madeOn)) throw const RvRefused('bad_day');
    return Worry._(id: id, kind: WorryKind.drawing, madeOn: madeOn, shown: shown, strokes: checkedStrokes(strokes));
  }

  final String id;
  final WorryKind kind;
  final String madeOn;

  /// True only after she chose "show my grown-up".
  final bool shown;
  final String? picture;
  final List<List<double>>? strokes;

  Worry withShown(bool v) => Worry._(id: id, kind: kind, madeOn: madeOn, shown: v, picture: picture, strokes: strokes);

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id, 'kind': kind.name, 'madeOn': madeOn, 'shown': shown,
        if (picture != null) 'picture': picture,
        if (strokes != null) 'strokes': strokes,
      };

  static Worry? tryFromJson(Object? j) {
    if (j is! Map) return null;
    try {
      final bool shown = j['shown'] == true;
      if (j['kind'] == WorryKind.picture.name) {
        return Worry.picture(id: j['id']! as String, picture: j['picture']! as String,
            madeOn: j['madeOn']! as String, shown: shown);
      }
      if (j['kind'] == WorryKind.drawing.name) {
        return Worry.drawing(
            id: j['id']! as String, madeOn: j['madeOn']! as String, shown: shown,
            strokes: <List<double>>[
              for (final Object? s in j['strokes']! as List)
                <double>[for (final Object? n in s! as List) (n! as num).toDouble()],
            ]);
      }
    } on RvRefused {
      return null;
    } on Object {
      return null;
    }
    return null;
  }
}

/// Validates and quantises a drawing: at least one stroke with at least one
/// point, bounded, every number finite and inside 0..1. Rounds to 3 decimals.
List<List<double>> checkedStrokes(List<List<double>> strokes) {
  if (strokes.isEmpty) throw const RvRefused('empty_drawing');
  if (strokes.length > maxStrokes) throw const RvRefused('too_many_strokes');
  final List<List<double>> out = <List<double>>[];
  for (final List<double> s in strokes) {
    if (s.length < 2 || s.length.isOdd) throw const RvRefused('bad_stroke');
    if (s.length > maxPointsPerStroke * 2) throw const RvRefused('too_many_points');
    out.add(<double>[
      for (final double n in s)
        if (!n.isFinite || n < 0 || n > 1) throw const RvRefused('bad_point') else (n * 1000).roundToDouble() / 1000,
    ]);
  }
  return out;
}

/// The box is bounded and NEVER silently drops a worry to make room: when it is
/// full she is asked to let one float away, which is her choice, not ours.
List<Worry> addWorry(List<Worry> box, Worry w) {
  if (box.length >= maxWorries) throw const RvRefused('box_full');
  if (box.any((Worry x) => x.id == w.id)) throw const RvRefused('duplicate_id');
  return <Worry>[...box, w];
}

/// "Show my grown-up" (true) or "keep it just mine" (false).
List<Worry> setWorryShown(List<Worry> box, String id, bool shown) {
  if (!box.any((Worry x) => x.id == id)) throw const RvRefused('unknown_worry');
  return <Worry>[for (final Worry x in box) x.id == id ? x.withShown(shown) : x];
}

/// "Let it float away": the worry is gone, not hidden.
List<Worry> floatAway(List<Worry> box, String id) {
  if (!box.any((Worry x) => x.id == id)) throw const RvRefused('unknown_worry');
  return <Worry>[for (final Worry x in box) if (x.id != id) x];
}

/// What a grown-up may see: only the worries she chose to show, exactly as she
/// made them. No tag, no count, no reading of the contents.
List<Worry> shownToGrownUp(List<Worry> box) => <Worry>[for (final Worry w in box) if (w.shown) w];

// ================================================================ HELPERS ====
const int maxHelpers = 8;
const Set<PictureGroup> _personPics = <PictureGroup>{PictureGroup.person};

class Helper {
  const Helper({required this.id, required this.name, required this.picture, this.line = '', this.saidYes = false});
  final String id;
  final String name;
  final String picture;

  /// A short line a guardian writes for her, such as "Knock on the door at the
  /// end of the hall". Never an address or a phone number.
  final String line;

  /// A guardian records that this person has said yes. Until then she does not
  /// see them.
  final bool saidYes;

  Map<String, Object?> toJson() =>
      <String, Object?>{'id': id, 'name': name, 'picture': picture, 'line': line, 'saidYes': saidYes};

  static Helper? tryFromJson(Object? j) {
    if (j is! Map) return null;
    try {
      return makeHelper(
          id: j['id'], name: j['name'], picture: j['picture'], line: j['line'] is String ? j['line'] as String : '',
          saidYes: j['saidYes'] == true);
    } on RvRefused {
      return null;
    }
  }
}

Helper makeHelper({required Object? id, required Object? name, required Object? picture, String line = '',
    bool saidYes = false}) {
  if (!isIdLike(id)) throw const RvRefused('bad_id');
  if (!isPictureIn(picture, _personPics)) throw const RvRefused('bad_picture');
  final String n = cleanText(name);
  final String l = cleanText(line, max: maxLineChars, allowEmpty: true);
  if (looksLikePhoneNumber(n) || looksLikePhoneNumber(l)) throw const RvRefused('looks_like_number');
  return Helper(id: id! as String, name: n, picture: picture! as String, line: l, saidYes: saidYes);
}

List<Helper> checkedHelpers(List<Helper> list) {
  if (list.length > maxHelpers) throw const RvRefused('too_many_helpers');
  if (list.map((Helper h) => h.id).toSet().length != list.length) throw const RvRefused('duplicate_id');
  return list;
}

/// Only people who have said yes, in the order a guardian set.
List<Helper> helpersForChild(List<Helper> list) => <Helper>[for (final Helper h in list) if (h.saidYes) h];

// ================================================================ SYMBOLS ====
const int maxPersonalSymbols = 8;
const int maxStripLength = 6;

final List<String> coreSymbolIds = <String>[for (final PictureDef p in picturesIn(PictureGroup.symbolCore)) p.id];

bool isSymbol(Object? id) => isPictureIn(id, const <PictureGroup>{PictureGroup.symbolCore, PictureGroup.symbolExtra});

List<String> checkedPersonalSymbols(List<String> ids) {
  if (ids.length > maxPersonalSymbols) throw const RvRefused('too_many_symbols');
  if (ids.toSet().length != ids.length) throw const RvRefused('duplicate_id');
  for (final String id in ids) {
    if (!isPictureIn(id, const <PictureGroup>{PictureGroup.symbolExtra})) throw const RvRefused('bad_picture');
  }
  return ids;
}

/// The whole board: core words, then her personal ones.
List<String> boardSymbols(List<String> personal) => <String>[...coreSymbolIds, ...personal];

/// The strip she is building. In memory only; never stored.
List<String> stripAdd(List<String> strip, String id) {
  if (!isSymbol(id)) throw const RvRefused('bad_picture');
  if (strip.length >= maxStripLength) throw const RvRefused('strip_full');
  return <String>[...strip, id];
}

List<String> stripBack(List<String> strip) => strip.isEmpty ? strip : strip.sublist(0, strip.length - 1);

/// The words, joined as they were tapped. Deterministic and word-for-word: no
/// grammar is added, no word is changed and nothing is rewritten.
String sentenceOf(List<String> strip) {
  final String s = strip.map(pictureLabel).where((String w) => w.isNotEmpty).join(' ');
  return s.isEmpty ? '' : s[0].toUpperCase() + s.substring(1);
}

// ============================================================ THE DOCUMENT ===
/// The guardian-authored half of suite C, kept in one small document.
class VoiceDoc {
  const VoiceDoc({this.helpers = const <Helper>[], this.personalSymbols = const <String>[], this.suiteOn = true});
  final List<Helper> helpers;
  final List<String> personalSymbols;
  final bool suiteOn;

  VoiceDoc copyWith({List<Helper>? helpers, List<String>? personalSymbols, bool? suiteOn}) => VoiceDoc(
      helpers: helpers ?? this.helpers, personalSymbols: personalSymbols ?? this.personalSymbols,
      suiteOn: suiteOn ?? this.suiteOn);

  Map<String, Object?> toJson() => <String, Object?>{
        'helpers': <Object?>[for (final Helper h in helpers) h.toJson()],
        'personalSymbols': personalSymbols, 'suiteOn': suiteOn,
      };

  static VoiceDoc fromJson(Object? j) {
    if (j is! Map) return const VoiceDoc();
    final List<Helper> helpers = <Helper>[];
    final Set<String> seen = <String>{};
    if (j['helpers'] is List) {
      for (final Object? r in j['helpers']! as List) {
        final Helper? h = Helper.tryFromJson(r);
        if (h != null && seen.add(h.id) && helpers.length < maxHelpers) helpers.add(h);
      }
    }
    final List<String> syms = <String>[];
    if (j['personalSymbols'] is List) {
      for (final Object? s in j['personalSymbols']! as List) {
        if (s is String && isPictureIn(s, const <PictureGroup>{PictureGroup.symbolExtra}) && !syms.contains(s) &&
            syms.length < maxPersonalSymbols) {
          syms.add(s);
        }
      }
    }
    return VoiceDoc(helpers: helpers, personalSymbols: syms, suiteOn: j['suiteOn'] != false);
  }
}
