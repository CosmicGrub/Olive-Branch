// OLIVE BRANCH — suites G (Growing) and F (Care): pure logic and models.
// No longer UNVERIFIED — verified by CI (client/test/growing_care_logic_test.dart).
// MASTERFILE section 8.17.
//
// LOCAL ONLY. Everything here lives on THIS device and says so in plain words
// wherever it is shown. Nothing in this file (or growing_care_store.dart or the
// two screen files) touches a socket, a server route, a credential or a
// scheduler. Sharing between homes is parked, not built.
//
// WHAT THE APP WRITES AND WHAT IT DOES NOT.
//  - Every word of the care binder, hospital notes, appointment lists and
//    explainer stories is typed by a guardian. The app ships NO medical advice,
//    no condition text, no pre-written explainer, no suggested question. The
//    only app-written strings are neutral labels ("Allergies (written by a
//    guardian)") and honest notes about where things are kept.
//  - Care information is guardian-to-guardian. Nothing in this file gives the
//    child's side a way to read it: the child's lens ([ChildGrowingLens],
//    [ChildExplainerReader]) is built from different, narrower types.
//  - No score, streak, counter, reward, ranking or comparison is modelled (P2).
//    There is no "N firsts", no height percentile or average, no "most".
//    Heights are a guardian's private record; her own picture shows month and
//    year only, never a number.
//  - No coordinates (P3), no price (P4). Nothing is generated about a new
//    partner or a family change.
//
// DATES are child-local yyyy-mm-dd strings and "today" is always passed in, so
// every rule is testable. A time capsule opens by THIS DEVICE'S CLOCK, which is
// said out loud ([capsuleClockNote]): changing the clock opens it early.
import 'dart:convert';
import 'dart:typed_data';

import 'family_structure_logic.dart'
    show ChildView, bandForYears, daysBetween, isIsoDate, maxStoryPageChars, maxStoryPages;

// ================================================================== limits ===
const int maxTitleChars = 60;
const int maxCapsuleNoteChars = 2000;
const int maxFirstNoteChars = 500;
const int maxCaptionChars = 80;
const int maxSectionChars = 4000;
const int maxHospitalFieldChars = 1000;
const int maxPrepLineChars = 200;
const int maxPrepLines = 30;
const int maxCmAllowed = 220;
const int minCmAllowed = 30;
const int maxCapsuleYearsAhead = 18;

const int maxCapsules = 40;
const int maxFirsts = 200;
const int maxPencilMarks = 60;
const int maxMemoryItems = 60;
const int maxCareSections = 12;
const int maxCareContacts = 20;
const int maxPreps = 20;
const int maxExplainers = 12;

/// One small photo, as bytes: a thumbnail, not a camera original.
const int maxThumbBytes = 48 * 1024;

/// Largest single stored item (JSON) - one huge item cannot crowd out the rest.
const int maxItemBytes = 192 * 1024;

/// A picture she copies into her memory box (a doodle's or colouring's strokes).
const int maxMemoryPictureBytes = 160 * 1024;

const String capsuleClockNote =
    "A capsule opens by this device's clock. Changing the clock would open it early, "
    'so keep that in mind. It is kept on this device only.';

const String localOnlyNote = 'Kept on this device only. Nothing here is sent anywhere.';

// ============================================================ suite names ====
const List<String> growingSuiteKeys = <String>['timeCapsule', 'firstTimes', 'memoryBox', 'pencilMarks'];
const List<String> careSuiteKeys = <String>['careBinder', 'hospitalMode', 'explainerCards', 'appointmentPrep'];
const List<String> allGrowingCareSuites = <String>[...growingSuiteKeys, ...careSuiteKeys];

const Map<String, String> suiteTitles = <String, String>{
  'timeCapsule': 'Time capsule',
  'firstTimes': 'First times',
  'memoryBox': 'Memory box',
  'pencilMarks': 'Growing marks',
  'careBinder': 'Care binder',
  'hospitalMode': 'Hospital mode',
  'explainerCards': 'Picture stories',
  'appointmentPrep': 'Appointment prep',
};

// ================================================================ refusals ===
/// Why a write was refused. A code, plus plain words for a screen.
class CareRefused implements Exception {
  const CareRefused(this.reason);
  final String reason;
  String get message => refusalMessage(reason);
  @override
  String toString() => 'CareRefused($reason)';
}

String refusalMessage(String reason) => switch (reason) {
      'empty' => 'There is nothing written yet.',
      'too_long' => 'That is longer than fits here. Please shorten it.',
      'bad_date' => 'That date is not a real date. Use year-month-day, like 2027-03-14.',
      'date_not_future' => 'A capsule needs a day after today to open on.',
      'date_too_far' => 'That is too far ahead. Pick a date within $maxCapsuleYearsAhead years.',
      'date_in_future' => 'That date has not happened yet.',
      'bad_height' => 'Heights run from $minCmAllowed to $maxCmAllowed centimetres.',
      'photo_too_big' => 'That photo is too big to keep here. Try a smaller one.',
      'too_many' => 'There is no more room for these. Remove one to make space.',
      'too_big' => 'That one is too big to keep. Make it a little smaller.',
      'full' => "This device's box for these is full. Remove something to make room.",
      'bad_page_count' => 'A story needs between 1 and $maxStoryPages pages.',
      'invalid' => 'That could not be kept.',
      _ => 'That could not be kept.',
    };

// ================================================================== helpers ==
String? _text(Object? v, {int max = 100000}) => v is String && v.length <= max ? v : null;

Map<String, Object?>? _map(Object? v) => v is Map ? Map<String, Object?>.from(v) : null;

String _clean(String s) => s.trim();

/// A thumbnail's bytes as JSON-safe text, or null for no photo.
String? encodeThumb(Uint8List? bytes) => bytes == null ? null : base64Encode(bytes);

Uint8List? decodeThumb(Object? v) {
  if (v is! String || v.isEmpty) return null;
  try {
    return base64Decode(v);
  } catch (_) {
    return null;
  }
}

/// null when fine; 'photo_too_big' otherwise.
String? thumbRefusal(Uint8List? bytes) => bytes != null && bytes.length > maxThumbBytes ? 'photo_too_big' : null;

const List<String> _months = <String>[
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// 'Nov 2026'. A bad date is returned unchanged rather than guessed at.
String monthYear(String iso) {
  if (!isIsoDate(iso)) return iso;
  return '${_months[int.parse(iso.substring(5, 7)) - 1]} ${iso.substring(0, 4)}';
}

/// '7 Nov 2026'.
String dayMonthYear(String iso) {
  if (!isIsoDate(iso)) return iso;
  return '${int.parse(iso.substring(8, 10))} ${monthYear(iso)}';
}

/// yyyy-mm-dd of a local DateTime.
String isoOf(DateTime t) =>
    '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

// ================================================================ the item ===
/// Anything stored as one document: has an id and plain-JSON form.
abstract class StoredItem {
  const StoredItem();
  String get id;
  Map<String, Object?> toJson();

  /// null when this item may be stored; otherwise a refusal reason code.
  String? check();
}

// ============================================================ time capsule ===
/// A note (and maybe a small photo) a guardian sealed for a future date.
class TimeCapsule extends StoredItem {
  const TimeCapsule({
    required this.id, required this.title, required this.note, required this.sealedOn,
    required this.opensOn, this.unsealedOn, this.thumb,
  });
  @override
  final String id;
  final String title;
  final String note;
  final String sealedOn;
  final String opensOn;

  /// Set when a guardian unsealed it early. Never set by the clock alone.
  final String? unsealedOn;
  final Uint8List? thumb;

  /// Open on or after its date by this device's clock, or once unsealed.
  bool isOpen(String today) => unsealedOn != null || today.compareTo(opensOn) >= 0;

  TimeCapsule unsealed(String today) => TimeCapsule(
      id: id, title: title, note: note, sealedOn: sealedOn, opensOn: opensOn, unsealedOn: today, thumb: thumb);

  /// What a guardian may SEE of it on [today]: while sealed, only the title
  /// and dates. The body and photo are withheld until it opens.
  GuardianCapsuleView forGuardian(String today) {
    final bool open = isOpen(today);
    return GuardianCapsuleView(
        id: id, title: title, sealedOn: sealedOn, opensOn: opensOn, open: open,
        note: open ? note : null, thumb: open ? thumb : null);
  }

  @override
  String? check() {
    if (_clean(title).isEmpty) return 'empty';
    if (title.length > maxTitleChars || note.length > maxCapsuleNoteChars) return 'too_long';
    if (_clean(note).isEmpty && thumb == null) return 'empty';
    if (!isIsoDate(sealedOn) || !isIsoDate(opensOn)) return 'bad_date';
    if (unsealedOn != null && !isIsoDate(unsealedOn)) return 'bad_date';
    final int ahead = daysBetween(sealedOn, opensOn);
    if (ahead < 1) return 'date_not_future';
    if (ahead > maxCapsuleYearsAhead * 366) return 'date_too_far';
    return thumbRefusal(thumb);
  }

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'id': id, 'title': title, 'note': note, 'sealedOn': sealedOn, 'opensOn': opensOn,
        if (unsealedOn != null) 'unsealedOn': unsealedOn,
        if (thumb != null) 'thumb': encodeThumb(thumb),
      };

  static TimeCapsule? fromJson(Map<String, Object?> j) {
    final String? id = _text(j['id'], max: 80), title = _text(j['title']), note = _text(j['note']);
    final String? sealed = _text(j['sealedOn']), opens = _text(j['opensOn']);
    if (id == null || title == null || note == null || sealed == null || opens == null) return null;
    final Object? un = j['unsealedOn'];
    return TimeCapsule(
        id: id, title: title, note: note, sealedOn: sealed, opensOn: opens,
        unsealedOn: un is String ? un : null, thumb: decodeThumb(j['thumb']));
  }
}

class GuardianCapsuleView {
  const GuardianCapsuleView({
    required this.id, required this.title, required this.sealedOn, required this.opensOn,
    required this.open, this.note, this.thumb,
  });
  final String id;
  final String title;
  final String sealedOn;
  final String opensOn;
  final bool open;

  /// Null while sealed.
  final String? note;
  final Uint8List? thumb;
}

// =============================================================== first times =
/// One thing that happened for the first time. A record of what happened,
/// never a list of things still to do, and never counted.
class FirstTime extends StoredItem {
  const FirstTime({
    required this.id, required this.title, required this.on, this.note = '', this.thumb,
    this.showHer = false,
  });
  @override
  final String id;
  final String title;
  final String on;
  final String note;
  final Uint8List? thumb;

  /// A guardian's explicit choice to let her see this one. Off by default.
  final bool showHer;

  @override
  String? check() {
    if (_clean(title).isEmpty) return 'empty';
    if (title.length > maxTitleChars || note.length > maxFirstNoteChars) return 'too_long';
    if (!isIsoDate(on)) return 'bad_date';
    return thumbRefusal(thumb);
  }

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'id': id, 'title': title, 'on': on, 'note': note, 'showHer': showHer,
        if (thumb != null) 'thumb': encodeThumb(thumb),
      };

  static FirstTime? fromJson(Map<String, Object?> j) {
    final String? id = _text(j['id'], max: 80), title = _text(j['title']), on = _text(j['on']);
    if (id == null || title == null || on == null) return null;
    return FirstTime(
        id: id, title: title, on: on, note: j['note'] is String ? j['note']! as String : '',
        thumb: decodeThumb(j['thumb']), showHer: j['showHer'] == true);
  }
}

/// Newest first. No grouping totals, no "n of m".
List<FirstTime> firstsNewestFirst(List<FirstTime> all) =>
    List<FirstTime>.of(all)..sort((FirstTime a, FirstTime b) => b.on.compareTo(a.on));

// ============================================================== pencil marks =
/// A height marked on the doorframe, recorded by a guardian.
class PencilMark extends StoredItem {
  const PencilMark({required this.id, required this.on, required this.cm, this.note = '', this.thumb});
  @override
  final String id;
  final String on;
  final int cm;
  final String note;
  final Uint8List? thumb;

  @override
  String? check() {
    if (!isIsoDate(on)) return 'bad_date';
    if (cm < minCmAllowed || cm > maxCmAllowed) return 'bad_height';
    if (note.length > maxCaptionChars) return 'too_long';
    return thumbRefusal(thumb);
  }

  @override
  Map<String, Object?> toJson() =>
      <String, Object?>{'id': id, 'on': on, 'cm': cm, 'note': note, if (thumb != null) 'thumb': encodeThumb(thumb)};

  static PencilMark? fromJson(Map<String, Object?> j) {
    final String? id = _text(j['id'], max: 80), on = _text(j['on']);
    final Object? cm = j['cm'];
    if (id == null || on == null || cm is! int) return null;
    return PencilMark(
        id: id, on: on, cm: cm, note: j['note'] is String ? j['note']! as String : '', thumb: decodeThumb(j['thumb']));
  }
}

/// One line on her doorframe picture: a month label and how high up it sits.
/// There is deliberately no number, no percentile and no comparison here.
class GrowthMarkView {
  const GrowthMarkView({required this.id, required this.label, required this.fraction});
  final String id;
  final String label;

  /// 0.25 (lowest mark she has) to 1.0 (highest): her own marks against each other, nothing else.
  final double fraction;
}

/// Her marks, oldest to newest, shown on the doorframe. Only her own marks
/// are compared with each other, to place the lines; no outside reference.
List<GrowthMarkView> growthPicture(List<PencilMark> marks, {int maxShown = 12}) {
  final List<PencilMark> sorted = List<PencilMark>.of(marks)..sort((PencilMark a, PencilMark b) => a.on.compareTo(b.on));
  final List<PencilMark> shown = sorted.length > maxShown ? sorted.sublist(sorted.length - maxShown) : sorted;
  if (shown.isEmpty) return const <GrowthMarkView>[];
  int lo = shown.first.cm, hi = shown.first.cm;
  for (final PencilMark m in shown) {
    if (m.cm < lo) lo = m.cm;
    if (m.cm > hi) hi = m.cm;
  }
  return <GrowthMarkView>[
    for (final PencilMark m in shown)
      GrowthMarkView(
          id: m.id, label: monthYear(m.on),
          fraction: hi == lo ? 1.0 : 0.25 + 0.75 * (m.cm - lo) / (hi - lo)),
  ];
}

// ================================================================ memory box ===
/// Something she chose to keep: a copy of a doodle or colouring, or a small photo.
class MemoryItem extends StoredItem {
  const MemoryItem({
    required this.id, required this.kind, required this.addedOn, this.caption = '',
    this.pictureData, this.thumb,
  });
  @override
  final String id;

  /// 'doodle' | 'colouring' (a copy of what makes it) | 'photo'.
  final String kind;
  final String addedOn;
  final String caption;
  final Map<String, Object?>? pictureData;
  final Uint8List? thumb;

  @override
  String? check() {
    if (kind == 'photo') {
      if (thumb == null) return 'empty';
    } else if (kind == 'doodle' || kind == 'colouring') {
      if (pictureData == null) return 'empty';
      if (utf8.encode(jsonEncode(pictureData)).length > maxMemoryPictureBytes) return 'too_big';
    } else {
      return 'invalid';
    }
    if (!isIsoDate(addedOn)) return 'bad_date';
    if (caption.length > maxCaptionChars) return 'too_long';
    return thumbRefusal(thumb);
  }

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'id': id, 'kind': kind, 'addedOn': addedOn, 'caption': caption,
        if (pictureData != null) 'data': pictureData,
        if (thumb != null) 'thumb': encodeThumb(thumb),
      };

  static MemoryItem? fromJson(Map<String, Object?> j) {
    final String? id = _text(j['id'], max: 80), kind = _text(j['kind']), on = _text(j['addedOn']);
    if (id == null || kind == null || on == null) return null;
    return MemoryItem(
        id: id, kind: kind, addedOn: on, caption: j['caption'] is String ? j['caption']! as String : '',
        pictureData: _map(j['data']), thumb: decodeThumb(j['thumb']));
  }
}

// ================================================================ care binder ==
const List<String> careSectionKinds = <String>['routines', 'allergies', 'school', 'other'];

/// Neutral labels only. The app writes no content under any of them.
const Map<String, String> careSectionLabels = <String, String>{
  'routines': 'Routines',
  'allergies': 'Allergies (written by a guardian)',
  'school': 'School',
  'other': 'Notes',
};

class CareSection extends StoredItem {
  const CareSection({required this.id, required this.kind, required this.title, required this.body, required this.updatedOn});
  @override
  final String id;
  final String kind;
  final String title;
  final String body;
  final String updatedOn;

  @override
  String? check() {
    if (!careSectionKinds.contains(kind)) return 'invalid';
    if (_clean(title).isEmpty) return 'empty';
    if (title.length > maxTitleChars || body.length > maxSectionChars) return 'too_long';
    return isIsoDate(updatedOn) ? null : 'bad_date';
  }

  @override
  Map<String, Object?> toJson() =>
      <String, Object?>{'id': id, 'kind': kind, 'title': title, 'body': body, 'updatedOn': updatedOn};

  static CareSection? fromJson(Map<String, Object?> j) {
    final String? id = _text(j['id'], max: 80), kind = _text(j['kind']), title = _text(j['title']);
    final String? body = _text(j['body']), at = _text(j['updatedOn']);
    if (id == null || kind == null || title == null || body == null || at == null) return null;
    return CareSection(id: id, kind: kind, title: title, body: body, updatedOn: at);
  }
}

class CareContact extends StoredItem {
  const CareContact({required this.id, required this.name, this.relation = '', this.phone = ''});
  @override
  final String id;
  final String name;
  final String relation;
  final String phone;

  @override
  String? check() {
    if (_clean(name).isEmpty) return 'empty';
    if (name.length > maxTitleChars || relation.length > 40 || phone.length > 40) return 'too_long';
    return null;
  }

  @override
  Map<String, Object?> toJson() => <String, Object?>{'id': id, 'name': name, 'relation': relation, 'phone': phone};

  static CareContact? fromJson(Map<String, Object?> j) {
    final String? id = _text(j['id'], max: 80), name = _text(j['name']);
    if (id == null || name == null) return null;
    return CareContact(
        id: id, name: name,
        relation: j['relation'] is String ? j['relation']! as String : '',
        phone: j['phone'] is String ? j['phone']! as String : '');
  }
}

/// The binder as plain text, for the print-style view and its copy button.
String binderAsText(String childName, List<CareSection> sections, List<CareContact> contacts) {
  final StringBuffer b = StringBuffer()
    ..writeln('$childName: care binder')
    ..writeln('Written by a guardian. Kept on this device only.')
    ..writeln();
  for (final CareSection s in sections) {
    b
      ..writeln(s.title.toUpperCase())
      ..writeln(s.body.trim().isEmpty ? '(nothing written yet)' : s.body.trim())
      ..writeln();
  }
  if (contacts.isNotEmpty) {
    b.writeln('CONTACTS');
    for (final CareContact c in contacts) {
      final List<String> bits = <String>[c.name, if (c.relation.isNotEmpty) c.relation, if (c.phone.isNotEmpty) c.phone];
      b.writeln(bits.join(' - '));
    }
  }
  return b.toString().trimRight();
}

// ============================================================ hospital mode ==
/// Four guardian-written fields for a stressed adult. The app adds no words.
class HospitalNotes extends StoredItem {
  const HospitalNotes({
    this.happeningToday = '', this.toBring = '', this.whatHelpsHer = '', this.staffShouldKnow = '',
  });
  static const String itemId = 'hospital';
  @override
  String get id => itemId;
  final String happeningToday;
  final String toBring;
  final String whatHelpsHer;
  final String staffShouldKnow;

  bool get isBlank =>
      happeningToday.trim().isEmpty && toBring.trim().isEmpty &&
      whatHelpsHer.trim().isEmpty && staffShouldKnow.trim().isEmpty;

  @override
  String? check() {
    for (final String f in <String>[happeningToday, toBring, whatHelpsHer, staffShouldKnow]) {
      if (f.length > maxHospitalFieldChars) return 'too_long';
    }
    return null;
  }

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'id': id, 'today': happeningToday, 'bring': toBring, 'helps': whatHelpsHer, 'staff': staffShouldKnow,
      };

  static HospitalNotes? fromJson(Map<String, Object?> j) => HospitalNotes(
      happeningToday: j['today'] is String ? j['today']! as String : '',
      toBring: j['bring'] is String ? j['bring']! as String : '',
      whatHelpsHer: j['helps'] is String ? j['helps']! as String : '',
      staffShouldKnow: j['staff'] is String ? j['staff']! as String : '');
}

/// What the hospital-mode screen shows: only what a guardian wrote.
class HospitalSummary {
  const HospitalSummary({required this.allergies, required this.contacts, required this.notes});
  final List<CareSection> allergies;
  final List<CareContact> contacts;
  final HospitalNotes notes;
  bool get hasAnything => allergies.isNotEmpty || contacts.isNotEmpty || !notes.isBlank;
}

HospitalSummary hospitalSummary(List<CareSection> sections, List<CareContact> contacts, HospitalNotes? notes) =>
    HospitalSummary(
        allergies: <CareSection>[
          for (final CareSection s in sections) if (s.kind == 'allergies' && s.body.trim().isNotEmpty) s,
        ],
        contacts: contacts,
        notes: notes ?? const HospitalNotes());

// ============================================================ explainer story ==
/// A picture story a guardian wrote. The app writes none and generates none.
class ExplainerStory extends StoredItem {
  const ExplainerStory({
    required this.id, required this.title, required this.pages, required this.updatedOn,
    this.shownToHer = false, this.thumb,
  });
  @override
  final String id;
  final String title;
  final List<String> pages;
  final String updatedOn;

  /// A guardian's explicit choice; off until they turn it on.
  final bool shownToHer;
  final Uint8List? thumb;

  @override
  String? check() {
    if (_clean(title).isEmpty) return 'empty';
    if (title.length > maxTitleChars) return 'too_long';
    if (pages.isEmpty || pages.length > maxStoryPages) return 'bad_page_count';
    for (final String p in pages) {
      if (_clean(p).isEmpty) return 'empty';
      if (p.length > maxStoryPageChars) return 'too_long';
    }
    if (!isIsoDate(updatedOn)) return 'bad_date';
    return thumbRefusal(thumb);
  }

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'id': id, 'title': title, 'pages': pages, 'updatedOn': updatedOn, 'shown': shownToHer,
        if (thumb != null) 'thumb': encodeThumb(thumb),
      };

  static ExplainerStory? fromJson(Map<String, Object?> j) {
    final String? id = _text(j['id'], max: 80), title = _text(j['title']), at = _text(j['updatedOn']);
    final Object? pages = j['pages'];
    if (id == null || title == null || at == null || pages is! List) return null;
    return ExplainerStory(
        id: id, title: title, pages: <String>[for (final Object? p in pages) if (p is String) p], updatedOn: at,
        shownToHer: j['shown'] == true, thumb: decodeThumb(j['thumb']));
  }
}

// =========================================================== appointment prep ==
class PrepLine {
  const PrepLine(this.text, {this.done = false});
  final String text;
  final bool done;
  Map<String, Object?> toJson() => <String, Object?>{'t': text, 'd': done};
}

/// A guardian's checklist and question list before a visit. No scheduling and
/// no reminders: [on] is only a date the guardian wants to see written down.
class AppointmentPrep extends StoredItem {
  const AppointmentPrep({
    required this.id, required this.title, required this.createdOn, this.on,
    this.checklist = const <PrepLine>[], this.questions = const <String>[],
  });
  @override
  final String id;
  final String title;
  final String createdOn;
  final String? on;
  final List<PrepLine> checklist;
  final List<String> questions;

  @override
  String? check() {
    if (_clean(title).isEmpty) return 'empty';
    if (title.length > maxTitleChars) return 'too_long';
    if (!isIsoDate(createdOn) || (on != null && !isIsoDate(on))) return 'bad_date';
    if (checklist.length > maxPrepLines || questions.length > maxPrepLines) return 'too_many';
    for (final PrepLine l in checklist) {
      if (l.text.length > maxPrepLineChars) return 'too_long';
    }
    for (final String q in questions) {
      if (q.length > maxPrepLineChars) return 'too_long';
    }
    return null;
  }

  AppointmentPrep copyWith({String? title, String? on, List<PrepLine>? checklist, List<String>? questions}) =>
      AppointmentPrep(
          id: id, title: title ?? this.title, createdOn: createdOn, on: on ?? this.on,
          checklist: checklist ?? this.checklist, questions: questions ?? this.questions);

  @override
  Map<String, Object?> toJson() => <String, Object?>{
        'id': id, 'title': title, 'createdOn': createdOn, if (on != null) 'on': on,
        'checklist': <Object?>[for (final PrepLine l in checklist) l.toJson()],
        'questions': questions,
      };

  static AppointmentPrep? fromJson(Map<String, Object?> j) {
    final String? id = _text(j['id'], max: 80), title = _text(j['title']), at = _text(j['createdOn']);
    if (id == null || title == null || at == null) return null;
    final Object? cl = j['checklist'], qs = j['questions'];
    return AppointmentPrep(
        id: id, title: title, createdOn: at, on: j['on'] is String ? j['on']! as String : null,
        checklist: <PrepLine>[
          if (cl is List)
            for (final Object? o in cl)
              if (o is Map && o['t'] is String) PrepLine(o['t']! as String, done: o['d'] == true),
        ],
        questions: <String>[if (qs is List) for (final Object? q in qs) if (q is String) q]);
  }
}

// ================================================================= switches ===
/// Which of the eight suites a guardian has switched off. Absent means on.
class SuiteSwitches extends StoredItem {
  const SuiteSwitches([this.flags = const <String, bool>{}]);
  static const String itemId = 'switches';
  @override
  String get id => itemId;
  final Map<String, bool> flags;

  bool on(String suite) => flags[suite] != false;

  SuiteSwitches withSuite(String suite, bool value) {
    if (!allGrowingCareSuites.contains(suite)) throw ArgumentError('unknown suite $suite');
    return SuiteSwitches(<String, bool>{...flags, suite: value});
  }

  @override
  String? check() => null;

  @override
  Map<String, Object?> toJson() => <String, Object?>{'id': id, 'flags': flags};

  static SuiteSwitches? fromJson(Map<String, Object?> j) {
    final Object? f = j['flags'];
    return SuiteSwitches(<String, bool>{
      if (f is Map)
        for (final MapEntry<Object?, Object?> e in f.entries)
          if (e.key is String && allGrowingCareSuites.contains(e.key) && e.value is bool) e.key! as String: e.value! as bool,
    });
  }
}

// ==================================================================== gating ===
/// What her own app may offer, from the family-structure model.
///
/// She is shown these only when (a) her band has a "More" hub at all (the
/// youngest band's home is three big pictures and nothing else), and (b) a
/// guardian has not switched the suite off. Care information is NEVER here:
/// the care binder, hospital mode and appointment prep are guardian-only, and
/// picture stories reach her only when a guardian chose to show one.
class ChildSuites {
  const ChildSuites({
    required this.memoryBox, required this.pencilMarks, required this.firstTimes,
    required this.timeCapsule, required this.explainerCards,
  });
  static const ChildSuites none = ChildSuites(
      memoryBox: false, pencilMarks: false, firstTimes: false, timeCapsule: false, explainerCards: false);
  final bool memoryBox;
  final bool pencilMarks;
  final bool firstTimes;
  final bool timeCapsule;
  final bool explainerCards;
  bool get any => memoryBox || pencilMarks || firstTimes || timeCapsule || explainerCards;
}

/// [view] is her derived view when one exists; otherwise her age decides, and
/// an unknown age fails closed to [failClosedYears] (5), the same default the
/// live home uses.
ChildSuites childSuitesFor({ChildView? view, int? yearsOld, SuiteSwitches? switches}) {
  final String band = view?.band ?? bandForYears(yearsOld ?? failClosedYears);
  if (band == 't34') return ChildSuites.none;
  if (view != null && !view.hasTile('more')) return ChildSuites.none;
  final SuiteSwitches s = switches ?? const SuiteSwitches();
  return ChildSuites(
      memoryBox: s.on('memoryBox'), pencilMarks: s.on('pencilMarks'), firstTimes: s.on('firstTimes'),
      timeCapsule: s.on('timeCapsule'), explainerCards: s.on('explainerCards'));
}

const int failClosedYears = 5;
