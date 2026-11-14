// OLIVE BRANCH — suite B RHYTHM, pure logic: one routine, first-then, packing
// buddy, new place, sensory profile. No longer UNVERIFIED — verified by CI
// (client/test/rhythm_logic_test.dart).
//
// OFFLINE AND ON-DEVICE ONLY. Nothing here opens a socket. Everything below is
// kept on THIS device and says so; sharing a routine or a bag between a child's
// two homes is parked (it needs the sync the owner has put off), so no type here
// has a "shared with" or "agreed by" field.
//
// WHO WRITES WHAT.
//  - A GUARDIAN authors the routine, the first-then cards, the packing list, the
//    place plan and the sensory profile. The child never edits any of them (the
//    child shell has no settings, §8.1).
//  - The CHILD ticks. She ticks the step she is on, the first-then "Done", and
//    what she has put in her bag. A tick is a private bit for TODAY: it is
//    dropped when the day changes (the routine) or after a few days (the bag),
//    and nothing counts it. No score, streak, counter, reward or "3 of 8" exists
//    anywhere in these types (P2); the tests assert the stored shape.
//
// NO LOCATION (P3). A place plan is rooms and a few plain lines. A caption or a
// line that looks like a street address or a coordinate pair is refused; this
// is a guard, not a guarantee, and the editor says "rooms only".
library;

import 'dart:convert';

import 'picture_library.dart';

/// Every refusal in suites B and C. [reason] is a short stable code (tests pin
/// it); the screens turn it into a gentle sentence.
class RvRefused implements Exception {
  const RvRefused(this.reason);
  final String reason;
  @override
  String toString() => 'RvRefused($reason)';
}

// ---------------------------------------------------------------- limits ----
const int maxTitleChars = 30;
const int maxLineChars = 60;
const int maxRoutineSteps = 8;
const int maxPackItems = 16;
const int maxSameItems = 6;
const int maxPlaceStops = 8;
const int maxPlanLines = 4;
const int maxPhotoBytes = 150 * 1024;
const int packTicksKeptDays = 3;

final RegExp _ctrl = RegExp('[\u0000-\u001f\u007f]');
final RegExp _coords = RegExp(r'-?\d{1,3}\.\d{3,}\s*[,;]?\s*-?\d{1,3}\.\d{3,}');
final RegExp _street = RegExp(
    r'\b\d{1,5}\s+(?:[A-Za-z]+\s+){1,2}(?:street|st|road|rd|avenue|ave|lane|ln|drive|dr|way|court|ct|boulevard|blvd|close|crescent)\b',
    caseSensitive: false);
final RegExp _phone = RegExp(r'(?:\d[\s().-]?){7,}');

/// True for text that looks like coordinates or a street address (P3).
bool looksLikeLocation(String s) => _coords.hasMatch(s) || _street.hasMatch(s);

/// True for text that looks like a phone number. The app is not a dialler, and a
/// number stored in plain words would be contact data it has no reason to hold.
bool looksLikePhoneNumber(String s) => _phone.hasMatch(s);

/// A trimmed, single-spaced label of 1..[max] characters, or [RvRefused].
String cleanText(Object? raw, {int max = maxTitleChars, bool allowEmpty = false, bool plainOnly = true}) {
  if (raw is! String) throw const RvRefused('bad_text');
  final String t = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (_ctrl.hasMatch(raw.replaceAll(RegExp(r'\s'), ' '))) throw const RvRefused('bad_text');
  if (t.isEmpty) {
    if (allowEmpty) return '';
    throw const RvRefused('empty_text');
  }
  if (t.runes.length > max) throw const RvRefused('too_long');
  if (plainOnly && looksLikeLocation(t)) throw const RvRefused('looks_like_location');
  return t;
}

// ------------------------------------------------------------------ days ----
final RegExp _isoDay = RegExp(r'^\d{4}-\d{2}-\d{2}$');

bool isIsoDay(Object? s) {
  if (s is! String || !_isoDay.hasMatch(s)) return false;
  final DateTime? d = DateTime.tryParse(s);
  return d != null && d.toIso8601String().substring(0, 10) == s;
}

/// Whole days from [a] to [b] (both yyyy-mm-dd); both must be valid.
int daysApart(String a, String b) {
  if (!isIsoDay(a) || !isIsoDay(b)) throw const RvRefused('bad_day');
  final DateTime x = DateTime.utc(int.parse(a.substring(0, 4)), int.parse(a.substring(5, 7)), int.parse(a.substring(8, 10)));
  final DateTime y = DateTime.utc(int.parse(b.substring(0, 4)), int.parse(b.substring(5, 7)), int.parse(b.substring(8, 10)));
  return y.difference(x).inDays;
}

String isoDayOf(DateTime t) =>
    '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

// =========================================================== ONE ROUTINE =====
const Set<PictureGroup> _routinePics = <PictureGroup>{PictureGroup.routine};

class RoutineStep {
  const RoutineStep({required this.id, required this.picture, required this.label});
  final String id;
  final String picture;
  final String label;

  Map<String, Object?> toJson() => <String, Object?>{'id': id, 'picture': picture, 'label': label};

  /// Tolerant: null for a row that is not a valid step.
  static RoutineStep? tryFromJson(Object? j) {
    if (j is! Map) return null;
    final Object? id = j['id'], pic = j['picture'], label = j['label'];
    if (id is! String || !isIdLike(id) || !isPictureIn(pic, _routinePics) || label is! String) return null;
    try {
      return RoutineStep(id: id, picture: pic! as String, label: cleanText(label));
    } on RvRefused {
      return null;
    }
  }
}

final RegExp _idRe = RegExp(r'^[A-Za-z0-9_-]{1,64}$');
bool isIdLike(Object? s) => s is String && _idRe.hasMatch(s);

class Routine {
  const Routine({this.title = 'My routine', this.steps = const <RoutineStep>[]});
  final String title;
  final List<RoutineStep> steps;

  Map<String, Object?> toJson() => <String, Object?>{
        'title': title,
        'steps': <Object?>[for (final RoutineStep s in steps) s.toJson()],
      };

  static Routine? tryFromJson(Object? j) {
    if (j is! Map) return null;
    final Object? t = j['title'], s = j['steps'];
    if (t is! String || s is! List) return null;
    String title;
    try {
      title = cleanText(t);
    } on RvRefused {
      return null;
    }
    final List<RoutineStep> steps = <RoutineStep>[];
    final Set<String> seen = <String>{};
    for (final Object? row in s) {
      final RoutineStep? st = RoutineStep.tryFromJson(row);
      if (st != null && seen.add(st.id) && steps.length < maxRoutineSteps) steps.add(st);
    }
    return Routine(title: title, steps: steps);
  }
}

/// A new step from a library picture. The label defaults to the picture's name.
RoutineStep newStep(String id, String picture, {String? label}) {
  if (!isIdLike(id)) throw const RvRefused('bad_id');
  if (!isPictureIn(picture, _routinePics)) throw const RvRefused('bad_picture');
  return RoutineStep(id: id, picture: picture, label: cleanText(label ?? pictureLabel(picture)));
}

Routine renameRoutine(Routine r, String title) => Routine(title: cleanText(title), steps: r.steps);

Routine addStep(Routine r, RoutineStep s) {
  if (r.steps.length >= maxRoutineSteps) throw const RvRefused('too_many_steps');
  if (r.steps.any((RoutineStep x) => x.id == s.id)) throw const RvRefused('duplicate_id');
  return Routine(title: r.title, steps: <RoutineStep>[...r.steps, s]);
}

Routine removeStep(Routine r, String id) {
  if (!r.steps.any((RoutineStep x) => x.id == id)) throw const RvRefused('unknown_step');
  return Routine(title: r.title, steps: <RoutineStep>[for (final RoutineStep x in r.steps) if (x.id != id) x]);
}

/// Moves the step at [from] so it sits at [to] (both indexes into the current list).
Routine moveStep(Routine r, int from, int to) {
  final int n = r.steps.length;
  if (from < 0 || from >= n || to < 0 || to >= n) throw const RvRefused('bad_index');
  final List<RoutineStep> l = <RoutineStep>[...r.steps];
  l.insert(to, l.removeAt(from));
  return Routine(title: r.title, steps: l);
}

/// A tick is a private bit for ONE day. Holds only which step ids are done today.
class DayTicks {
  const DayTicks({this.day, this.done = const <String>[]});
  final String? day;
  final List<String> done;

  Map<String, Object?> toJson() => <String, Object?>{'day': day, 'done': done};

  static DayTicks fromJson(Object? j) {
    if (j is! Map) return const DayTicks();
    final Object? d = j['day'], l = j['done'];
    if (!isIsoDay(d) || l is! List) return const DayTicks();
    return DayTicks(day: d as String, done: <String>[for (final Object? x in l) if (isIdLike(x)) x! as String]);
  }
}

/// [t] as it stands on [today] for [r]: stale days start fresh, and ids of steps
/// a guardian has since removed are dropped.
DayTicks ticksFor(Routine r, DayTicks t, String today) {
  if (!isIsoDay(today)) throw const RvRefused('bad_day');
  if (t.day != today) return DayTicks(day: today);
  final Set<String> ids = r.steps.map((RoutineStep s) => s.id).toSet();
  return DayTicks(day: today, done: <String>[for (final String d in t.done) if (ids.contains(d)) d]);
}

/// What the child is looking at: the step she is on and the one after, as a
/// first-then pair. [allDone] is a calm resting state, not a result.
class FirstThen {
  const FirstThen({this.first, this.then, this.allDone = false});
  final RoutineStep? first;
  final RoutineStep? then;
  final bool allDone;
}

FirstThen firstThenOf(Routine r, DayTicks ticks) {
  final Set<String> done = ticks.done.toSet();
  final List<RoutineStep> rest = <RoutineStep>[for (final RoutineStep s in r.steps) if (!done.contains(s.id)) s];
  if (r.steps.isEmpty) return const FirstThen();
  if (rest.isEmpty) return const FirstThen(allDone: true);
  return FirstThen(first: rest.first, then: rest.length > 1 ? rest[1] : null);
}

/// She ticks the step she is ON. There is no way to tick one out of order, and
/// nothing to say how many are left.
DayTicks tickCurrent(Routine r, DayTicks ticks, String today) {
  final DayTicks t = ticksFor(r, ticks, today);
  final FirstThen ft = firstThenOf(r, t);
  if (ft.first == null) return t;
  return DayTicks(day: today, done: <String>[...t.done, ft.first!.id]);
}

/// "Again": a fresh start for today.
DayTicks startAgain(String today) {
  if (!isIsoDay(today)) throw const RvRefused('bad_day');
  return DayTicks(day: today);
}

// ============================================================ FIRST, THEN ====
class BoardCard {
  const BoardCard({required this.picture, required this.label});
  final String picture;
  final String label;
  Map<String, Object?> toJson() => <String, Object?>{'picture': picture, 'label': label};
  static BoardCard? tryFromJson(Object? j) {
    if (j is! Map || !isPictureIn(j['picture'], _routinePics) || j['label'] is! String) return null;
    try {
      return BoardCard(picture: j['picture']! as String, label: cleanText(j['label']));
    } on RvRefused {
      return null;
    }
  }
}

BoardCard boardCard(String picture, {String? label}) {
  if (!isPictureIn(picture, _routinePics)) throw const RvRefused('bad_picture');
  return BoardCard(picture: picture, label: cleanText(label ?? pictureLabel(picture)));
}

/// Two cards, never more. A guardian sets both from the picture library.
class FirstThenBoard {
  const FirstThenBoard({required this.first, required this.then});
  final BoardCard first;
  final BoardCard then;
  Map<String, Object?> toJson() => <String, Object?>{'first': first.toJson(), 'then': then.toJson()};
  static FirstThenBoard? tryFromJson(Object? j) {
    if (j is! Map) return null;
    final BoardCard? a = BoardCard.tryFromJson(j['first']), b = BoardCard.tryFromJson(j['then']);
    return a == null || b == null ? null : FirstThenBoard(first: a, then: b);
  }
}

FirstThenBoard makeBoard(BoardCard first, BoardCard then) {
  if (first.picture == then.picture) throw const RvRefused('same_card');
  return FirstThenBoard(first: first, then: then);
}

/// Whether "First" is done today. One bit, for one day.
class BoardState {
  const BoardState({this.day, this.firstDone = false});
  final String? day;
  final bool firstDone;
  Map<String, Object?> toJson() => <String, Object?>{'day': day, 'firstDone': firstDone};
  static BoardState fromJson(Object? j) {
    if (j is! Map || !isIsoDay(j['day'])) return const BoardState();
    return BoardState(day: j['day'] as String, firstDone: j['firstDone'] == true);
  }
}

BoardState boardStateFor(BoardState s, String today) {
  if (!isIsoDay(today)) throw const RvRefused('bad_day');
  return s.day == today ? s : BoardState(day: today);
}

BoardState markFirstDone(BoardState s, String today) => BoardState(day: today, firstDone: true);

// ============================================================ PACKING BUDDY ==
const Set<PictureGroup> _thingPics = <PictureGroup>{PictureGroup.thing};

class PackItem {
  const PackItem({required this.id, required this.picture, required this.label, this.same = false});
  final String id;
  final String picture;
  final String label;

  /// A comfort thing that is the same in both homes. It is shown as a calm
  /// "always the same" row and is never ticked, so it can never be "forgotten".
  final bool same;

  Map<String, Object?> toJson() => <String, Object?>{'id': id, 'picture': picture, 'label': label, 'same': same};
  static PackItem? tryFromJson(Object? j) {
    if (j is! Map) return null;
    if (!isIdLike(j['id']) || !isPictureIn(j['picture'], _thingPics) || j['label'] is! String) return null;
    try {
      return PackItem(id: j['id']! as String, picture: j['picture']! as String,
          label: cleanText(j['label']), same: j['same'] == true);
    } on RvRefused {
      return null;
    }
  }
}

class PackingList {
  const PackingList({this.items = const <PackItem>[]});
  final List<PackItem> items;
  List<PackItem> get toBring => <PackItem>[for (final PackItem i in items) if (!i.same) i];
  List<PackItem> get alwaysSame => <PackItem>[for (final PackItem i in items) if (i.same) i];
  Map<String, Object?> toJson() => <String, Object?>{'items': <Object?>[for (final PackItem i in items) i.toJson()]};
  static PackingList tryFromJson(Object? j) {
    if (j is! Map || j['items'] is! List) return const PackingList();
    final List<PackItem> out = <PackItem>[];
    final Set<String> seen = <String>{};
    for (final Object? r in j['items']! as List) {
      final PackItem? i = PackItem.tryFromJson(r);
      if (i != null && seen.add(i.id) && out.length < maxPackItems) out.add(i);
    }
    return PackingList(items: out);
  }
}

PackItem newPackItem(String id, String picture, {String? label, bool same = false}) {
  if (!isIdLike(id)) throw const RvRefused('bad_id');
  if (!isPictureIn(picture, _thingPics)) throw const RvRefused('bad_picture');
  return PackItem(id: id, picture: picture, label: cleanText(label ?? pictureLabel(picture)), same: same);
}

PackingList addPackItem(PackingList l, PackItem i) {
  if (l.items.length >= maxPackItems) throw const RvRefused('too_many_items');
  if (l.items.any((PackItem x) => x.id == i.id)) throw const RvRefused('duplicate_id');
  if (i.same && l.alwaysSame.length >= maxSameItems) throw const RvRefused('too_many_same');
  return PackingList(items: <PackItem>[...l.items, i]);
}

PackingList removePackItem(PackingList l, String id) {
  if (!l.items.any((PackItem x) => x.id == id)) throw const RvRefused('unknown_item');
  return PackingList(items: <PackItem>[for (final PackItem x in l.items) if (x.id != id) x]);
}

/// Which items she has put in her bag. Kept for [packTicksKeptDays] days (the
/// bag is packed the night before and carried the next day), then dropped.
class PackTicks {
  const PackTicks({this.startedOn, this.packed = const <String>[]});
  final String? startedOn;
  final List<String> packed;
  Map<String, Object?> toJson() => <String, Object?>{'startedOn': startedOn, 'packed': packed};
  static PackTicks fromJson(Object? j) {
    if (j is! Map || !isIsoDay(j['startedOn']) || j['packed'] is! List) return const PackTicks();
    return PackTicks(
        startedOn: j['startedOn'] as String,
        packed: <String>[for (final Object? x in j['packed']! as List) if (isIdLike(x)) x! as String]);
  }
}

PackTicks packTicksFor(PackingList l, PackTicks t, String today) {
  if (!isIsoDay(today)) throw const RvRefused('bad_day');
  final String? s = t.startedOn;
  if (s == null || daysApart(s, today) < 0 || daysApart(s, today) >= packTicksKeptDays) return const PackTicks();
  final Set<String> ids = l.toBring.map((PackItem i) => i.id).toSet();
  return PackTicks(startedOn: s, packed: <String>[for (final String p in t.packed) if (ids.contains(p)) p]);
}

/// She can pack and un-pack any item to bring. An "always the same" item cannot
/// be ticked at all (so nothing is ever left undone about it).
PackTicks togglePacked(PackingList l, PackTicks t, String today, String id) {
  final PackItem? item = l.items.cast<PackItem?>().firstWhere((PackItem? x) => x!.id == id, orElse: () => null);
  if (item == null) throw const RvRefused('unknown_item');
  if (item.same) throw const RvRefused('same_at_both');
  final PackTicks cur = packTicksFor(l, t, today);
  final List<String> p = cur.packed.contains(id)
      ? <String>[for (final String x in cur.packed) if (x != id) x]
      : <String>[...cur.packed, id];
  return PackTicks(startedOn: cur.startedOn ?? today, packed: p);
}

// ================================================================ NEW PLACE ==
const Set<PictureGroup> _roomPics = <PictureGroup>{PictureGroup.room};

class PlaceStop {
  const PlaceStop({required this.id, required this.room, required this.caption, this.photoB64});
  final String id;
  final String room;
  final String caption;

  /// A small JPEG or PNG of a ROOM, base64, at most [maxPhotoBytes] decoded.
  final String? photoB64;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id, 'room': room, 'caption': caption, if (photoB64 != null) 'photo': photoB64,
      };

  static PlaceStop? tryFromJson(Object? j) {
    if (j is! Map || !isIdLike(j['id']) || !isPictureIn(j['room'], _roomPics) || j['caption'] is! String) return null;
    try {
      final Object? p = j['photo'];
      return PlaceStop(
          id: j['id']! as String, room: j['room']! as String,
          caption: cleanText(j['caption'], max: maxLineChars),
          photoB64: p is String ? checkedPhoto(p) : null);
    } on RvRefused {
      return null;
    }
  }
}

/// Decodes [b64] and checks it is a bounded JPEG or PNG; returns it unchanged.
String checkedPhoto(String b64) {
  final List<int> bytes;
  try {
    bytes = base64Decode(b64);
  } on FormatException {
    throw const RvRefused('bad_photo');
  }
  if (bytes.length > maxPhotoBytes) throw const RvRefused('photo_too_big');
  final bool jpeg = bytes.length > 3 && bytes[0] == 0xFF && bytes[1] == 0xD8;
  final bool png = bytes.length > 4 && bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47;
  if (!jpeg && !png) throw const RvRefused('bad_photo');
  return b64;
}

PlaceStop newStop(String id, String room, String caption, {List<int>? photoBytes}) {
  if (!isIdLike(id)) throw const RvRefused('bad_id');
  if (!isPictureIn(room, _roomPics)) throw const RvRefused('bad_picture');
  return PlaceStop(
      id: id, room: room, caption: cleanText(caption, max: maxLineChars),
      photoB64: photoBytes == null ? null : checkedPhoto(base64Encode(photoBytes)));
}

/// A gentle preview of a place a guardian prepares: a few rooms in a fixed
/// order, and a short plan. No address, no map, no coordinates (P3).
class PlacePlan {
  const PlacePlan({this.name = 'A new place', this.stops = const <PlaceStop>[], this.plan = const <String>[]});
  final String name;
  final List<PlaceStop> stops;
  final List<String> plan;

  bool get isEmpty => stops.isEmpty && plan.isEmpty;

  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'stops': <Object?>[for (final PlaceStop s in stops) s.toJson()],
        'plan': plan,
      };

  static PlacePlan? tryFromJson(Object? j) {
    if (j is! Map || j['name'] is! String || j['stops'] is! List || j['plan'] is! List) return null;
    try {
      final List<PlaceStop> stops = <PlaceStop>[];
      final Set<String> seen = <String>{};
      for (final Object? r in j['stops']! as List) {
        final PlaceStop? s = PlaceStop.tryFromJson(r);
        if (s != null && seen.add(s.id) && stops.length < maxPlaceStops) stops.add(s);
      }
      final List<String> plan = <String>[];
      for (final Object? l in j['plan']! as List) {
        if (l is String && plan.length < maxPlanLines) {
          try {
            plan.add(cleanText(l, max: maxLineChars));
          } on RvRefused {
            // a damaged line is skipped, never shown
          }
        }
      }
      return PlacePlan(name: cleanText(j['name']), stops: stops, plan: plan);
    } on RvRefused {
      return null;
    }
  }
}

PlacePlan makePlan(String name, List<PlaceStop> stops, List<String> plan) {
  if (stops.length > maxPlaceStops) throw const RvRefused('too_many_stops');
  if (plan.length > maxPlanLines) throw const RvRefused('too_many_lines');
  if (stops.map((PlaceStop s) => s.id).toSet().length != stops.length) throw const RvRefused('duplicate_id');
  return PlacePlan(
      name: cleanText(name),
      stops: stops,
      plan: <String>[for (final String l in plan) cleanText(l, max: maxLineChars)]);
}

// ========================================================= SENSORY PROFILE ===
enum SoundLevel { off, low, medium, full }

const int minBrightnessPercent = 30;

/// "How the app feels." A guardian sets it for her device. It describes the APP,
/// never the child: there is no label, no diagnosis and no free text here, and
/// nothing she can see calls it anything but "how the app feels".
class SensoryProfile {
  const SensoryProfile({
    this.sound = SoundLevel.full,
    this.reduceMotion = false,
    this.hapticsOff = false,
    this.brightnessCeiling = 100,
    this.headsUp = const <String>{},
  });
  final SoundLevel sound;
  final bool reduceMotion;
  final bool hapticsOff;

  /// Things worth a quiet warning (ids from [headsUpIds]): the prototype's
  /// five sensory flags. A guardian's gentle planning aid, not a label: her tablet
  /// adds a plain heads-up line on the "new place" walk-through and nothing else.
  final Set<String> headsUp;

  /// 30..100, in steps of 10: the brightest the app may ask the screen to be.
  final int brightnessCeiling;

  /// Flashing is never on, for anyone; it is a fact, not a setting.
  bool get neverFlashes => true;

  SensoryProfile copyWith({
    SoundLevel? sound, bool? reduceMotion, bool? hapticsOff, int? brightnessCeiling, Set<String>? headsUp,
  }) =>
      SensoryProfile(
          sound: sound ?? this.sound, reduceMotion: reduceMotion ?? this.reduceMotion,
          hapticsOff: hapticsOff ?? this.hapticsOff, brightnessCeiling: brightnessCeiling ?? this.brightnessCeiling,
          headsUp: headsUp ?? this.headsUp);

  /// The heads-up ids with [id] switched on or off (an unknown id changes nothing).
  SensoryProfile withHeadsUp(String id, bool on) => !headsUpIds.contains(id)
      ? this
      : copyWith(headsUp: on ? <String>{...headsUp, id} : (<String>{...headsUp}..remove(id)));

  Map<String, Object?> toJson() => <String, Object?>{
        'sound': sound.name, 'reduceMotion': reduceMotion, 'hapticsOff': hapticsOff,
        'brightnessCeiling': brightnessCeiling,
        'headsUp': <String>[for (final String k in headsUpIds) if (headsUp.contains(k)) k],
      };

  /// Each field falls back to its default on its own; a damaged value never
  /// turns anything louder or brighter than the default.
  static SensoryProfile fromJson(Object? j) {
    if (j is! Map) return const SensoryProfile();
    SoundLevel s = SoundLevel.full;
    for (final SoundLevel v in SoundLevel.values) {
      if (v.name == j['sound']) s = v;
    }
    final Object? b = j['brightnessCeiling'];
    return SensoryProfile(
        sound: s, reduceMotion: j['reduceMotion'] == true, hapticsOff: j['hapticsOff'] == true,
        brightnessCeiling: b is int && isValidBrightness(b) ? b : 100,
        headsUp: j['headsUp'] is List
            ? <String>{for (final Object? x in j['headsUp']! as List) if (x is String && headsUpIds.contains(x)) x}
            : <String>{});
  }
}

/// One thing that may need a quiet warning: the guardian's label (about the
/// situation, never about her), what her tablet then says, and the guardian-side
/// sentence on what it does.
class HeadsUp {
  const HeadsUp(this.id, this.label, this.does, this.line);
  final String id;
  final String label;
  final String does;

  /// The soft line a child may read: no count, no "needs", no label of her.
  final String line;
}

const List<HeadsUp> headsUps = <HeadsUp>[
  HeadsUp('loud', 'Loud places', 'Warns her first', 'It might be loud. You can cover your ears or take a break.'),
  HeadsUp('bright', 'Bright lights', 'Warns her first', 'It might be very bright. You can look away.'),
  HeadsUp('scratchy', 'Scratchy or tight clothes', 'Offers a choice', 'You can choose what feels good to wear.'),
  HeadsUp('crowds', 'Crowds', 'Gives her an exit picture', 'There might be lots of people. You can ask for a quiet spot.'),
  HeadsUp('surprises', 'Surprises', 'Says what is coming', 'Here is what is going to happen, so nothing is a surprise.'),
];

final Set<String> headsUpIds = <String>{for (final HeadsUp h in headsUps) h.id};

/// The soft lines for the flags that are on, in the table's own order.
List<String> headsUpLines(SensoryProfile p) => <String>[for (final HeadsUp h in headsUps) if (p.headsUp.contains(h.id)) h.line];

bool isValidBrightness(int b) => b >= minBrightnessPercent && b <= 100 && b % 10 == 0;

SensoryProfile validateSensory(SensoryProfile p) {
  if (!isValidBrightness(p.brightnessCeiling)) throw const RvRefused('bad_brightness');
  return p;
}

/// What the profile means for the code that plays sound, animates and buzzes.
class SensoryDefaults {
  const SensoryDefaults({
    required this.volume, required this.animate, required this.haptics, required this.maxBrightness,
    this.headsUp = const <String>[],
  });

  /// Soft heads-up lines for her new-place walk-through (see [headsUpLines]).
  final List<String> headsUp;

  /// 0.0 (silent) .. 1.0, for a read-aloud or sound channel to apply.
  final double volume;
  final bool animate;
  final bool haptics;

  /// 0.3 .. 1.0.
  final double maxBrightness;

  /// She hears nothing when the sound is off, speech included.
  bool get silent => volume == 0;
}

/// [osReduceMotion] is the device's own setting: a profile can only reduce
/// motion further, never switch it back on.
SensoryDefaults sensoryDefaults(SensoryProfile p, {bool osReduceMotion = false}) => SensoryDefaults(
      volume: switch (p.sound) { SoundLevel.off => 0.0, SoundLevel.low => 0.3, SoundLevel.medium => 0.6, SoundLevel.full => 1.0 },
      animate: !(p.reduceMotion || osReduceMotion),
      haptics: !p.hapticsOff,
      maxBrightness: p.brightnessCeiling / 100,
      headsUp: headsUpLines(p),
    );

// ============================================================ THE DOCUMENT ===
/// Everything suite B keeps on a device for one child (one LocalStore document
/// each, see rhythm_voice_repositories.dart).
class RhythmDoc {
  const RhythmDoc({
    this.routine, this.routineTicks = const DayTicks(), this.board, this.boardState = const BoardState(),
    this.packing = const PackingList(), this.packTicks = const PackTicks(),
    this.sensory = const SensoryProfile(), this.suiteOn = true, this.twoHomes = false,
  });
  final Routine? routine;
  final DayTicks routineTicks;
  final FirstThenBoard? board;
  final BoardState boardState;
  final PackingList packing;
  final PackTicks packTicks;
  final SensoryProfile sensory;

  /// The guardian's switch for the whole suite on her device (default on).
  final bool suiteOn;

  /// A guardian-set, local-only "she sleeps in two homes" fallback for the packing
  /// buddy, used ONLY when the family snapshot is unavailable. Off by default;
  /// only an explicit `true` counts.
  final bool twoHomes;

  RhythmDoc copyWith({
    Routine? routine, bool clearRoutine = false, DayTicks? routineTicks, FirstThenBoard? board,
    bool clearBoard = false, BoardState? boardState, PackingList? packing, PackTicks? packTicks,
    SensoryProfile? sensory, bool? suiteOn, bool? twoHomes,
  }) =>
      RhythmDoc(
        routine: clearRoutine ? null : (routine ?? this.routine),
        routineTicks: routineTicks ?? this.routineTicks,
        board: clearBoard ? null : (board ?? this.board),
        boardState: boardState ?? this.boardState,
        packing: packing ?? this.packing, packTicks: packTicks ?? this.packTicks,
        sensory: sensory ?? this.sensory, suiteOn: suiteOn ?? this.suiteOn,
        twoHomes: twoHomes ?? this.twoHomes,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'routine': routine?.toJson(), 'routineTicks': routineTicks.toJson(),
        'board': board?.toJson(), 'boardState': boardState.toJson(),
        'packing': packing.toJson(), 'packTicks': packTicks.toJson(),
        'sensory': sensory.toJson(), 'suiteOn': suiteOn, 'twoHomes': twoHomes,
      };

  static RhythmDoc fromJson(Object? j) {
    if (j is! Map) return const RhythmDoc();
    return RhythmDoc(
      routine: Routine.tryFromJson(j['routine']), routineTicks: DayTicks.fromJson(j['routineTicks']),
      board: FirstThenBoard.tryFromJson(j['board']), boardState: BoardState.fromJson(j['boardState']),
      packing: PackingList.tryFromJson(j['packing']), packTicks: PackTicks.fromJson(j['packTicks']),
      sensory: SensoryProfile.fromJson(j['sensory']), suiteOn: j['suiteOn'] != false,
      twoHomes: j['twoHomes'] == true,
    );
  }
}
