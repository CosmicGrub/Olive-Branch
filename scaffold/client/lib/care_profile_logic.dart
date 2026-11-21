// OLIVE BRANCH — the care profile ("About <child>"), the pure half: what it holds, the rules of who may see
// which part, the tone guard, the review prompts and the one-page doctor sheet. UNVERIFIED until CI runs
// client/test/care_profile_logic_test.dart and client/test/care_profile_store_test.dart. MASTERFILE section 8.24.8.
//
// WHAT IT IS. The existing guardian-only care binder, emergency card and medicines log, gathered into one
// profile that a grown-up writes about the child. It GROWS those three and loses nothing from them: the binder
// sections are copied in once (the binder keeps its own copy), the emergency card and the medicines log are
// read where they are (never copied, so they cannot drift).
//
// WHAT IT NEVER DOES.
//  - It writes NO medical advice and computes NO doses. Every word is a grown-up's, labelled "written by
//    <name>, <date>". The only words the app adds are section names and plain instructions.
//  - The CHILD NEVER SEES ANY OF IT (MASTERFILE 2.1, P1 to P11 and 5.23.2). [careProfileVisibleToChild] is false
//    for every part and stays false, the same shape as care_note.dart's careNoteVisibleTo. No child-side file
//    imports the care_profile_* files (care_profile_structure_test.dart reads the real sources to prove it).
//  - It does not pretend phones talk to each other. Sharing is stored and enforced ON THIS DEVICE (what the
//    "show as" screen and the printed sheet will show). Sharing between phones is not built.
//  - The edit history is NOT an evidence log: it is short (the last [cpMaxRevisions] changes of each entry), it
//    is not hash-chained, and it is in no export. It exists so two parents can see each other's changes.
//  - Today's heads-up is never logged: one note, replaced when rewritten, and gone for good at local midnight.
import 'dart:convert';
import 'dart:typed_data';

import 'allergy_field.dart';
import 'care_local.dart' show CareDoc, CareMedication, CareResult, MedKind;
import 'care_note.dart' show careNoteBanned;
import 'emergency_card_local.dart' show LocalEmergencyCard;
import 'sha256.dart';

// ================================================================== limits ===
const int cpMaxEntries = 200;
const int cpMaxTitleChars = 60;
const int cpMaxTextChars = 4000;
const int cpMaxHeadsChars = 280;
const int cpMaxRevisions = 8;
const int cpMaxPeople = 12;
const int cpMaxNameChars = 40;
const int cpMaxPlanPhotos = 6;
const int cpMaxPlanPhotoBytes = 600 * 1024;
const int cpMaxLabelChars = 60;

/// How often the "is this still right?" prompt comes back on its own.
const int cpReviewEveryDays = 90;

/// How long the locked parts stay open after the PIN, with no further use.
const Duration cpUnlockWindow = Duration(minutes: 5);

/// The hour (local) the "just tonight" time box ends: a visit's access ends the next morning.
const int cpTonightEndsAtHour = 6;

const String cpUnnamedGuardian = 'a guardian';

final RegExp _ctrl = RegExp('[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]');

/// Keeps line breaks (a grown-up writes paragraphs), drops other control characters, trims the ends.
String cpText(Object? v) => v is String ? v.replaceAll(_ctrl, ' ').trim() : '';
String _line(Object? v) => cpText(v).replaceAll(RegExp(r'\s+'), ' ');

// ================================================================== the parts ===
/// The seven parts of the profile. [health] and [moods] are parents only and never shareable.
enum CareProfilePart {
  safe(shareable: true, locked: false, entries: true, tone: false),
  everyday(shareable: true, locked: false, entries: true, tone: true),
  helps(shareable: true, locked: false, entries: true, tone: true),
  heads(shareable: true, locked: false, entries: false, tone: true),
  meds(shareable: true, locked: false, entries: false, tone: false),
  health(shareable: false, locked: true, entries: true, tone: false),
  moods(shareable: false, locked: true, entries: true, tone: true);

  const CareProfilePart({required this.shareable, required this.locked, required this.entries, required this.tone});

  /// May a person other than a parent be given this part? false = parents only, always.
  final bool shareable;

  /// Behind the guardian PIN for reading and writing.
  final bool locked;

  /// Holds written entries (today's heads-up and medicines have their own shape).
  final bool entries;

  /// The tone guard runs on what is written here.
  final bool tone;

  static CareProfilePart? byName(Object? n) {
    for (final CareProfilePart p in values) {
      if (p.name == n) return p;
    }
    return null;
  }
}

/// The plain name of a part, for a grown-up's screen. [child] is her first name (or 'her').
String careProfilePartTitle(CareProfilePart p, String child) => switch (p) {
  CareProfilePart.safe => 'Keep $child safe',
  CareProfilePart.everyday => child == 'her' ? 'Her everyday' : "$child's everyday",
  CareProfilePart.helps => 'What helps',
  CareProfilePart.heads => "Today's heads-up",
  CareProfilePart.meds => 'Medicines',
  CareProfilePart.health => 'Health history',
  CareProfilePart.moods => 'Moods and habits',
};

/// One neutral line under each part. Not advice: it says what the part is for and who can see it by default.
String careProfilePartHint(CareProfilePart p) => switch (p) {
  CareProfilePart.safe => 'Allergies, what must never be missed, who to call. Reaches furthest when you share.',
  CareProfilePart.everyday => 'Food, sleep, routines, school, what she likes.',
  CareProfilePart.helps => 'What calms, what overwhelms, how a break is asked for. Describe needs, not judgements.',
  CareProfilePart.heads => 'One short note for today only. It is not shown after midnight, is removed the next time this profile is opened or changed, and is never kept.',
  CareProfilePart.meds => 'The medicines list and its dose log, as you wrote them in Medications.',
  CareProfilePart.health => 'Parents only, behind your PIN.',
  CareProfilePart.moods => 'Parents only, behind your PIN. Patterns you have noticed.',
};

/// The child sees none of it. This is a function (not a constant) so a test can walk every part, and so the
/// shape matches care_note.dart's careNoteVisibleTo. It must stay false.
bool careProfileVisibleToChild(CareProfilePart part) => false;

// ================================================================== results ===
String cpRefusalText(String reason) => switch (reason) {
  'guardian_only' => 'Only a grown-up can use this.',
  'locked' => 'Enter your PIN to open this part.',
  'text_needed' => 'Write something first.',
  'name_needed' => 'A name is needed.',
  'too_long' => 'One of those is longer than fits here. Please shorten it.',
  'too_many' => 'There is no room for more here.',
  'not_found' => 'That could not be found.',
  'not_yours' => 'You can only change what you wrote. Use "Write my version" to add yours beside it.',
  'tone' => 'Please describe what is needed or what helps, rather than a judgement.',
  'not_shareable' => 'This part is for parents only and cannot be shared.',
  'not_allowed' => 'That person can be shown only the Keep-safe part.',
  'bad_time' => 'That time is not valid.',
  'bad_date' => 'That date is not valid.',
  'not_an_image' => 'That is not a photo this phone can keep (a JPEG or PNG).',
  'photo_too_big' => 'That photo is too big to keep here. Try a smaller one.',
  'full' => "This device's box for the profile is full.",
  'not_saved' => 'That did not save. Please try again.',
  _ => 'That could not be saved.',
};

// ================================================================== tone guard ===
/// Words about the child as a judgement, in addition to the accusatory phrases the care note already refuses.
/// Small on purpose: this is a guard against labels, not a style checker. A refused note says which phrase.
const List<String> careProfileLabelWords = <String>[
  'bad mood',
  'naughty',
  'spoiled',
  'attention seeking',
  'attention-seeking',
  'manipulative',
  'a brat',
  'bad girl',
  'bad boy',
];

/// The banned phrases found in [text] (lower-cased match), empty when it is fine.
List<String> careProfileToneFound(String text) {
  final String t = text.toLowerCase();
  return <String>[
    for (final String w in <String>[...careNoteBanned, ...careProfileLabelWords])
      if (RegExp('(^|[^a-z0-9])${RegExp.escape(w)}(\$|[^a-z0-9])').hasMatch(t)) w,
  ];
}

const String careProfileToneGuidance =
    'Try describing what is needed or what helps instead, for example "needs quiet after school". '
    'The same guard the care notes use keeps accusations and labels out of this profile.';

// ================================================================== entries ===
/// What an entry said before an edit, and who changed it and when. A plain note, not evidence.
class CpRevision {
  const CpRevision({required this.at, required this.byId, required this.byName, required this.title, required this.text});
  final DateTime at;
  final String byId;
  final String byName;
  final String title;
  final String text;

  Map<String, Object?> toJson() => <String, Object?>{
    'at': at.toUtc().toIso8601String(),
    'byId': byId,
    'byName': byName,
    'title': title,
    'text': text,
  };

  static CpRevision? tryFromJson(Object? j) {
    if (j is! Map || j['at'] is! String) return null;
    final DateTime? t = DateTime.tryParse(j['at']! as String);
    if (t == null) return null;
    return CpRevision(
      at: t.toUtc(),
      byId: _line(j['byId']),
      byName: _line(j['byName']).isEmpty ? cpUnnamedGuardian : _line(j['byName']),
      title: _line(j['title']),
      text: cpText(j['text']),
    );
  }
}

class CpEntry {
  const CpEntry({
    required this.id,
    required this.part,
    required this.text,
    required this.at,
    this.title = '',
    this.byId = '',
    this.byName = '',
    this.revisions = const <CpRevision>[],
    this.retired = false,
    this.retiredBy = '',
    this.fromBinderId,
  });
  final String id;
  final CareProfilePart part;

  /// A short name for the thing described ("Bedtime"). Two entries with the same title by different writers that
  /// say different things are shown side by side.
  final String title;
  final String text;

  /// When this was first written (UTC). For an entry copied from the binder, the binder section's date.
  final DateTime at;
  final String byId;
  final String byName;

  /// What it said before each edit, newest last, at most [cpMaxRevisions].
  final List<CpRevision> revisions;

  /// Put away: out of every view and sheet, kept here so it can be brought back.
  final bool retired;
  final String retiredBy;

  /// The care binder section this was copied from, if any (its writer was not recorded).
  final String? fromBinderId;

  CpEntry copyWith({
    String? title,
    String? text,
    List<CpRevision>? revisions,
    bool? retired,
    String? retiredBy,
  }) => CpEntry(
    id: id,
    part: part,
    title: title ?? this.title,
    text: text ?? this.text,
    at: at,
    byId: byId,
    byName: byName,
    revisions: revisions ?? this.revisions,
    retired: retired ?? this.retired,
    retiredBy: retiredBy ?? this.retiredBy,
    fromBinderId: fromBinderId,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'part': part.name,
    if (title.isNotEmpty) 'title': title,
    'text': text,
    'at': at.toUtc().toIso8601String(),
    'byId': byId,
    'byName': byName,
    if (revisions.isNotEmpty) 'revs': <Object?>[for (final CpRevision r in revisions) r.toJson()],
    if (retired) 'retired': true,
    if (retiredBy.isNotEmpty) 'retiredBy': retiredBy,
    if (fromBinderId != null) 'binder': fromBinderId,
  };

  static CpEntry? tryFromJson(Object? j) {
    if (j is! Map) return null;
    final String id = _line(j['id']);
    final CareProfilePart? part = CareProfilePart.byName(j['part']);
    final DateTime? at = j['at'] is String ? DateTime.tryParse(j['at']! as String) : null;
    if (id.isEmpty || part == null || !part.entries || at == null) return null;
    final String text = cpText(j['text']);
    if (text.isEmpty) return null;
    return CpEntry(
      id: id,
      part: part,
      title: _line(j['title']),
      text: text,
      at: at.toUtc(),
      byId: _line(j['byId']),
      byName: _line(j['byName']),
      revisions: <CpRevision>[
        if (j['revs'] is List)
          for (final Object? r in (j['revs']! as List).take(cpMaxRevisions)) ?CpRevision.tryFromJson(r),
      ],
      retired: j['retired'] == true,
      retiredBy: _line(j['retiredBy']),
      fromBinderId: j['binder'] is String && (j['binder']! as String).isNotEmpty ? j['binder']! as String : null,
    );
  }
}

const List<String> _months = <String>['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "14 Nov 2026" in the phone's local time.
String cpDate(DateTime t) {
  final DateTime l = t.toLocal();
  return '${l.day} ${_months[l.month - 1]} ${l.year}';
}

/// "written by Sam, 14 Nov 2026", or "from the care binder, 3 Nov 2026" for a copied binder section.
String cpWrittenBy(CpEntry e) {
  if (e.fromBinderId != null && e.byName.isEmpty) return 'from the care binder, ${cpDate(e.at)}';
  return 'written by ${e.byName.isEmpty ? cpUnnamedGuardian : e.byName}, ${cpDate(e.at)}';
}

String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

/// The active entries of [part], oldest first within a title.
List<CpEntry> cpEntriesOf(CareProfileDoc d, CareProfilePart part, {bool retired = false}) {
  final List<CpEntry> l = <CpEntry>[
    for (final CpEntry e in d.entries)
      if (e.part == part && e.retired == retired) e,
  ];
  l.sort((CpEntry a, CpEntry b) {
    final int t = _norm(a.title).compareTo(_norm(b.title));
    return t != 0 ? t : a.at.compareTo(b.at);
  });
  return l;
}

/// Groups of entries that disagree: the same part and title, written by different people, saying different
/// things. Each group lists every version; nothing is hidden or merged. Entries with no title never group.
List<List<CpEntry>> cpDisagreements(CareProfileDoc d, CareProfilePart part) {
  final Map<String, List<CpEntry>> byTitle = <String, List<CpEntry>>{};
  for (final CpEntry e in cpEntriesOf(d, part)) {
    final String k = _norm(e.title);
    if (k.isEmpty) continue;
    byTitle.putIfAbsent(k, () => <CpEntry>[]).add(e);
  }
  final List<List<CpEntry>> out = <List<CpEntry>>[];
  for (final List<CpEntry> g in byTitle.values) {
    final bool differ = g.any(
      (CpEntry a) => g.any((CpEntry b) => a.id != b.id && a.byId != b.byId && _norm(a.text) != _norm(b.text)),
    );
    if (differ) out.add(g);
  }
  return out;
}

// ================================================================== heads-up ===
/// Today's heads-up: one note, for one local day. Never revised, never logged.
class CpHeads {
  const CpHeads({required this.text, required this.day, required this.at, this.byId = '', this.byName = ''});
  final String text;

  /// The local calendar day it is for, "yyyy-mm-dd". It is shown only on that day.
  final String day;
  final DateTime at;
  final String byId;
  final String byName;

  Map<String, Object?> toJson() => <String, Object?>{
    'text': text,
    'day': day,
    'at': at.toUtc().toIso8601String(),
    'byId': byId,
    'byName': byName,
  };

  static CpHeads? tryFromJson(Object? j) {
    if (j is! Map) return null;
    final String text = cpText(j['text']);
    final DateTime? at = j['at'] is String ? DateTime.tryParse(j['at']! as String) : null;
    if (text.isEmpty || at == null || j['day'] is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(j['day']! as String)) {
      return null;
    }
    return CpHeads(text: text, day: j['day']! as String, at: at.toUtc(), byId: _line(j['byId']), byName: _line(j['byName']));
  }
}

/// The local calendar day of [t], "yyyy-mm-dd".
String cpDay(DateTime t) {
  final DateTime l = t.toLocal();
  return '${l.year.toString().padLeft(4, '0')}-${l.month.toString().padLeft(2, '0')}-${l.day.toString().padLeft(2, '0')}';
}

/// The heads-up if it is for today (local time), else null: at local midnight it simply stops being today.
CpHeads? cpHeadsToday(CareProfileDoc d, DateTime now) {
  final CpHeads? h = d.heads;
  return h != null && h.day == cpDay(now) ? h : null;
}

// ================================================================== people and sharing ===
enum CpPersonKind { carer, visit, viewOnly, helperPage }

String cpPersonKindTitle(CpPersonKind k) => switch (k) {
  CpPersonKind.carer => 'Trusted carer',
  CpPersonKind.visit => 'Visit (time-boxed)',
  CpPersonKind.viewOnly => 'View only',
  CpPersonKind.helperPage => 'Helper page',
};

/// One grant: a part shown to a person, until [until] (UTC) or, with null, until you take it back.
class CpGrant {
  const CpGrant({this.until});
  final DateTime? until;
  bool activeAt(DateTime now) => until == null || now.toUtc().isBefore(until!.toUtc());
}

class CpPerson {
  const CpPerson({required this.id, required this.name, required this.kind, this.grants = const <CareProfilePart, CpGrant>{}});
  final String id;
  final String name;
  final CpPersonKind kind;
  final Map<CareProfilePart, CpGrant> grants;

  CpPerson copyWith({Map<CareProfilePart, CpGrant>? grants}) =>
      CpPerson(id: id, name: name, kind: kind, grants: grants ?? this.grants);

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'kind': kind.name,
    'grants': <String, Object?>{
      for (final MapEntry<CareProfilePart, CpGrant> g in grants.entries)
        g.key.name: g.value.until?.toUtc().toIso8601String() ?? '',
    },
  };

  static CpPerson? tryFromJson(Object? j) {
    if (j is! Map) return null;
    final String id = _line(j['id']), name = _line(j['name']);
    CpPersonKind? kind;
    for (final CpPersonKind k in CpPersonKind.values) {
      if (k.name == j['kind']) kind = k;
    }
    if (id.isEmpty || name.isEmpty || kind == null) return null;
    final Map<CareProfilePart, CpGrant> grants = <CareProfilePart, CpGrant>{};
    if (j['grants'] is Map) {
      for (final MapEntry<Object?, Object?> e in (j['grants']! as Map).entries) {
        final CareProfilePart? p = CareProfilePart.byName(e.key);
        // A grant for a part that cannot be shared is dropped on read, so an edited file cannot open it.
        if (p == null || !cpMayGrant(kind, p)) continue;
        if (e.value == '' || e.value == null) {
          grants[p] = const CpGrant();
        } else if (e.value is String) {
          final DateTime? t = DateTime.tryParse(e.value! as String);
          if (t != null) grants[p] = CpGrant(until: t.toUtc());
        }
      }
    }
    return CpPerson(id: id, name: name.length > cpMaxNameChars ? name.substring(0, cpMaxNameChars) : name, kind: kind, grants: grants);
  }
}

/// May a person of [kind] ever be given [part]? Health history and moods: never. View only: Keep-safe only.
bool cpMayGrant(CpPersonKind kind, CareProfilePart part) {
  if (!part.shareable) return false;
  if (kind == CpPersonKind.viewOnly) return part == CareProfilePart.safe;
  return true;
}

/// Whether [person] may be shown [part] at [now]. The one rule every "show as" screen and sheet asks.
bool cpCanSee(CpPerson person, CareProfilePart part, DateTime now) {
  if (!cpMayGrant(person.kind, part)) return false;
  final CpGrant? g = person.grants[part];
  return g != null && g.activeAt(now);
}

/// What a new person starts with (a parent can change every one): a trusted carer sees Keep-safe, everyday and
/// today's heads-up; a visit sees Keep-safe and today's heads-up until the next 6 in the morning; the other two
/// start with nothing.
Map<CareProfilePart, CpGrant> cpDefaultGrants(CpPersonKind kind, DateTime now) => switch (kind) {
  CpPersonKind.carer => <CareProfilePart, CpGrant>{
    CareProfilePart.safe: const CpGrant(),
    CareProfilePart.everyday: const CpGrant(),
    CareProfilePart.heads: const CpGrant(),
  },
  CpPersonKind.visit => <CareProfilePart, CpGrant>{
    CareProfilePart.safe: CpGrant(until: cpTonightEnds(now)),
    CareProfilePart.heads: CpGrant(until: cpTonightEnds(now)),
  },
  CpPersonKind.viewOnly || CpPersonKind.helperPage => const <CareProfilePart, CpGrant>{},
};

/// The next [cpTonightEndsAtHour] o'clock in the phone's local time, as a UTC instant: "just tonight".
DateTime cpTonightEnds(DateTime now) {
  final DateTime l = now.toLocal();
  DateTime t = DateTime(l.year, l.month, l.day, cpTonightEndsAtHour);
  if (!t.isAfter(l)) t = DateTime(l.year, l.month, l.day + 1, cpTonightEndsAtHour);
  return t.toUtc();
}

// ================================================================== medicines (read from the log) ===
/// One medicine as the grown-up wrote it in Medications, for a sheet or a "show as" view. The app adds no text
/// and works out no amount: the dose and the gap are the grown-up's own entries.
class CpMedLine {
  const CpMedLine({required this.name, required this.dose, required this.schedule, required this.note, this.lastGiven});
  final String name;
  final String dose;
  final String schedule;
  final String note;

  /// "by Sam, 14 Nov 2026 08:05", or null when none is logged.
  final String? lastGiven;

  String get text {
    final List<String> bits = <String>[
      name,
      if (dose.isNotEmpty) dose,
      schedule,
      if (note.isNotEmpty) note,
      if (lastGiven != null) 'last given $lastGiven',
    ];
    return bits.join(' | ');
  }
}

String _hm(DateTime t) =>
    '${t.toLocal().hour.toString().padLeft(2, '0')}:${t.toLocal().minute.toString().padLeft(2, '0')}';

/// The active medicines of the existing log, as written.
List<CpMedLine> cpMedicineLines(CareDoc? meds) {
  if (meds == null) return const <CpMedLine>[];
  return <CpMedLine>[
    for (final CareMedication m in meds.meds)
      if (!m.retired)
        CpMedLine(
          name: m.name,
          dose: m.dose,
          schedule: m.kind == MedKind.scheduled
              ? 'at ${m.slots.join(', ')}'
              : (m.gapHours == null ? 'when needed' : 'when needed, with the ${m.gapHours} hour gap set in Medications'),
          note: m.note,
          lastGiven: m.doses.isEmpty
              ? null
              : 'by ${m.doses.last.byName}, ${cpDate(m.doses.last.at)} ${_hm(m.doses.last.at)}',
        ),
  ];
}

/// A short fingerprint of the medicine LIST (names, doses, times, notes and whether each is retired), not of the
/// dose log: giving a dose is not a change, adding, editing or retiring a medicine is.
String cpMedicineFingerprint(CareDoc? meds) {
  if (meds == null || meds.meds.isEmpty) return sha256Hex('none');
  final List<CareMedication> l = <CareMedication>[...meds.meds]..sort((CareMedication a, CareMedication b) => a.id.compareTo(b.id));
  return sha256Hex(
    l
        .map(
          (CareMedication m) =>
              '${m.id}|${m.name}|${m.dose}|${m.kind.name}|${m.slots.join(',')}|${m.gapHours}|${m.note}|${m.retired}',
        )
        .join('\n'),
  );
}

// ================================================================== review prompts ===
enum CpReviewKind { birthday, ninetyDays, medicineChange }

class CpReviewReason {
  const CpReviewReason(this.kind, this.text);
  final CpReviewKind kind;
  final String text;
}

DateTime _dayOnly(DateTime t) {
  final DateTime l = t.toLocal();
  return DateTime(l.year, l.month, l.day);
}

/// Calendar days from [a] to [b] (both local days), unaffected by a clock change in between.
int _wholeDaysBetween(DateTime a, DateTime b) =>
    DateTime.utc(b.year, b.month, b.day).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

bool _leap(int y) => (y % 4 == 0 && y % 100 != 0) || y % 400 == 0;

DateTime _birthdayIn(int year, int month, int day) =>
    (month == 2 && day == 29 && !_leap(year)) ? DateTime(year, 3, 1) : DateTime(year, month, day);

/// The most recent birthday on or before [today] (local day). A Feb 29 birthday is Mar 1 in a common year, the
/// same rule her home uses.
DateTime cpLastBirthday(int month, int day, DateTime today) {
  final DateTime t = _dayOnly(today);
  final DateTime thisYear = _birthdayIn(t.year, month, day);
  return thisYear.isAfter(t) ? _birthdayIn(t.year - 1, month, day) : thisYear;
}

/// Why the profile is due a "is this still right?", in the order a person would meet them. Empty when nothing is
/// due or the profile is empty. [medFingerprint] is [cpMedicineFingerprint] now. [childAge] and [child] only word
/// the birthday line.
List<CpReviewReason> cpReviewReasons(
  CareProfileDoc d,
  DateTime now, {
  required String medFingerprint,
  String child = 'she',
  int? childAge,
}) {
  if (!d.hasContent) return const <CpReviewReason>[];
  final DateTime today = _dayOnly(now);
  final DateTime baseline = _dayOnly(d.lastReviewedAt ?? d.createdAt ?? now);
  final List<CpReviewReason> out = <CpReviewReason>[];
  if (d.birthMonth != null && d.birthDay != null) {
    final DateTime b = cpLastBirthday(d.birthMonth!, d.birthDay!, today);
    if (b.isAfter(baseline)) {
      out.add(
        CpReviewReason(
          CpReviewKind.birthday,
          childAge == null
              ? 'It has been $child\'s birthday. Is what you wrote still right?'
              : '$child is $childAge now. Is what you wrote still right?',
        ),
      );
    }
  }
  if (d.reviewedMedFingerprint != null && d.reviewedMedFingerprint != medFingerprint) {
    out.add(const CpReviewReason(CpReviewKind.medicineChange, 'A medicine changed. Is what you wrote still right?'));
  }
  if (_wholeDaysBetween(baseline, today) >= cpReviewEveryDays) {
    out.add(const CpReviewReason(CpReviewKind.ninetyDays, 'It has been a while. Is what you wrote still right?'));
  }
  return out;
}

// ================================================================== the document ===
class CareProfileDoc {
  const CareProfileDoc({
    this.entries = const <CpEntry>[],
    this.heads,
    this.people = const <CpPerson>[],
    this.names = const <String, String>{},
    this.importedBinderIds = const <String>[],
    this.birthMonth,
    this.birthDay,
    this.createdAt,
    this.lastReviewedAt,
    this.reviewedMedFingerprint,
    this.teenPreview = false,
    this.seq = 0,
  });

  final List<CpEntry> entries;
  final CpHeads? heads;
  final List<CpPerson> people;
  final Map<String, String> names;

  /// Care binder sections already copied in, so a second open copies nothing twice.
  final List<String> importedBinderIds;
  final int? birthMonth;
  final int? birthDay;

  /// When the profile first held something (the 90 days count from here until the first "still right").
  final DateTime? createdAt;
  final DateTime? lastReviewedAt;
  final String? reviewedMedFingerprint;

  /// The "My health sheet" preview for a teen. Defaults OFF: the owner has not decided whether a teen sees one.
  final bool teenPreview;
  final int seq;

  bool get hasContent => entries.any((CpEntry e) => !e.retired) || heads != null;

  CareProfileDoc copyWith({
    List<CpEntry>? entries,
    CpHeads? heads,
    bool clearHeads = false,
    List<CpPerson>? people,
    Map<String, String>? names,
    List<String>? importedBinderIds,
    int? birthMonth,
    int? birthDay,
    bool clearBirthday = false,
    DateTime? createdAt,
    DateTime? lastReviewedAt,
    String? reviewedMedFingerprint,
    bool? teenPreview,
    int? seq,
  }) => CareProfileDoc(
    entries: entries ?? this.entries,
    heads: clearHeads ? null : (heads ?? this.heads),
    people: people ?? this.people,
    names: names ?? this.names,
    importedBinderIds: importedBinderIds ?? this.importedBinderIds,
    birthMonth: clearBirthday ? null : (birthMonth ?? this.birthMonth),
    birthDay: clearBirthday ? null : (birthDay ?? this.birthDay),
    createdAt: createdAt ?? this.createdAt,
    lastReviewedAt: lastReviewedAt ?? this.lastReviewedAt,
    reviewedMedFingerprint: reviewedMedFingerprint ?? this.reviewedMedFingerprint,
    teenPreview: teenPreview ?? this.teenPreview,
    seq: seq ?? this.seq,
  );

  /// The same document with the PIN-locked parts taken out. What a read returns while the PIN has not been given.
  CareProfileDoc withoutLocked() =>
      copyWith(entries: <CpEntry>[for (final CpEntry e in entries) if (!e.part.locked) e]);

  Map<String, Object?> toJson() => <String, Object?>{
    'v': 1,
    'entries': <Object?>[for (final CpEntry e in entries) e.toJson()],
    if (heads != null) 'heads': heads!.toJson(),
    'people': <Object?>[for (final CpPerson p in people) p.toJson()],
    'names': names,
    'binder': importedBinderIds,
    if (birthMonth != null) 'bm': birthMonth,
    if (birthDay != null) 'bd': birthDay,
    if (createdAt != null) 'created': createdAt!.toUtc().toIso8601String(),
    if (lastReviewedAt != null) 'reviewed': lastReviewedAt!.toUtc().toIso8601String(),
    if (reviewedMedFingerprint != null) 'medfp': reviewedMedFingerprint,
    'teen': teenPreview,
    'seq': seq,
  };

  static CareProfileDoc fromJson(Object? j) {
    if (j is! Map) return const CareProfileDoc();
    DateTime? d(Object? v) => v is String ? DateTime.tryParse(v)?.toUtc() : null;
    final Object? bm = j['bm'], bd = j['bd'], sq = j['seq'];
    final bool okBirth = bm is int && bd is int && bm >= 1 && bm <= 12 && bd >= 1 && bd <= 31;
    return CareProfileDoc(
      entries: <CpEntry>[
        if (j['entries'] is List)
          for (final Object? e in (j['entries']! as List).take(cpMaxEntries)) ?CpEntry.tryFromJson(e),
      ],
      heads: CpHeads.tryFromJson(j['heads']),
      people: <CpPerson>[
        if (j['people'] is List)
          for (final Object? p in (j['people']! as List).take(cpMaxPeople)) ?CpPerson.tryFromJson(p),
      ],
      names: <String, String>{
        if (j['names'] is Map)
          for (final MapEntry<Object?, Object?> e in (j['names']! as Map).entries)
            if (e.key is String && _line(e.value).isNotEmpty) e.key! as String: _line(e.value),
      },
      importedBinderIds: <String>[
        if (j['binder'] is List)
          for (final Object? b in j['binder']! as List)
            if (b is String && b.isNotEmpty) b,
      ],
      birthMonth: okBirth ? bm : null,
      birthDay: okBirth ? bd : null,
      createdAt: d(j['created']),
      lastReviewedAt: d(j['reviewed']),
      reviewedMedFingerprint: j['medfp'] is String && (j['medfp']! as String).isNotEmpty ? j['medfp']! as String : null,
      teenPreview: j['teen'] == true,
      seq: sq is int && sq >= 0 ? sq : 0,
    );
  }
}

// ================================================================== a person's view ===
/// What one part of a person's view holds.
class CpPartView {
  const CpPartView({required this.part, this.entries = const <CpEntry>[], this.heads, this.medicines = const <CpMedLine>[]});
  final CareProfilePart part;
  final List<CpEntry> entries;
  final CpHeads? heads;
  final List<CpMedLine> medicines;
}

/// Everything [person] may be shown right now, and nothing else: only the parts granted and not yet ended, never a
/// parents-only part, the heads-up only on its day, retired entries never. A pure function so a test can prove it.
List<CpPartView> cpViewFor(CareProfileDoc d, CpPerson person, DateTime now, {CareDoc? meds}) {
  final List<CpPartView> out = <CpPartView>[];
  for (final CareProfilePart p in CareProfilePart.values) {
    if (!cpCanSee(person, p, now)) continue;
    switch (p) {
      case CareProfilePart.heads:
        final CpHeads? h = cpHeadsToday(d, now);
        if (h != null) out.add(CpPartView(part: p, heads: h));
      case CareProfilePart.meds:
        out.add(CpPartView(part: p, medicines: cpMedicineLines(meds)));
      case CareProfilePart.safe || CareProfilePart.everyday || CareProfilePart.helps:
        out.add(CpPartView(part: p, entries: cpEntriesOf(d, p)));
      case CareProfilePart.health || CareProfilePart.moods:
        break;
    }
  }
  return out;
}

// ================================================================== the teen's own sheet ===
/// What a teen's "My health sheet" would hold: the Keep-safe entries and the medicines, nothing else. Null unless
/// the flag is on AND the age is 13 to 17. Today there is no child-side door to it (the owner has not decided);
/// this is only the rule, and a grown-up's preview of it.
({List<CpEntry> entries, List<CpMedLine> medicines})? cpTeenSheet(
  CareProfileDoc d,
  CareDoc? meds, {
  required int? age,
}) {
  if (!d.teenPreview || age == null || age < 13 || age > 17) return null;
  return (entries: cpEntriesOf(d, CareProfilePart.safe), medicines: cpMedicineLines(meds));
}

// ================================================================== the doctor sheet ===
/// Which optional parts go on the sheet. Keep-safe, the emergency card details and the medicines are always on it.
class CpSheetOptions {
  const CpSheetOptions({this.everyday = false, this.helps = false, this.health = false, this.moods = false});
  final bool everyday, helps, health, moods;
}

/// A print-style, one-page text for a doctor's visit, built only from what grown-ups wrote. [health] and [moods]
/// are included only if [options] asks AND [unlocked] (the PIN was given). It carries no advice and no dose the
/// grown-up did not write.
String cpDoctorSheetText({
  required String childName,
  required CareProfileDoc doc,
  CareDoc? meds,
  LocalEmergencyCard? card,
  List<String> planPhotoLabels = const <String>[],
  CpSheetOptions options = const CpSheetOptions(),
  bool unlocked = false,
  required DateTime now,
}) {
  final StringBuffer b = StringBuffer()
    ..writeln('$childName: sheet for the doctor, ${cpDate(now)}')
    ..writeln('Written by her grown-ups from the care profile on this phone. The app adds no medical advice.')
    ..writeln();

  void entries(String title, CareProfilePart part) {
    final List<CpEntry> l = cpEntriesOf(doc, part);
    b.writeln(title.toUpperCase());
    if (l.isEmpty) {
      b.writeln('(nothing written)');
    } else {
      final Set<String> disputed = <String>{
        for (final List<CpEntry> g in cpDisagreements(doc, part))
          for (final CpEntry e in g) e.id,
      };
      for (final CpEntry e in l) {
        final String head = e.title.isEmpty ? '' : '${e.title}: ';
        b.writeln('- $head${e.text.replaceAll('\n', ' ')} (${cpWrittenBy(e)}${disputed.contains(e.id) ? '; the grown-ups wrote this differently' : ''})');
      }
    }
    b.writeln();
  }

  entries(careProfilePartTitle(CareProfilePart.safe, childName), CareProfilePart.safe);

  // The allergy line is ALWAYS on the sheet, with or without a card: a sheet that left it out would read as "no
  // allergies" to a doctor. Three states (allergy_field.dart): an empty list is "Not recorded", never "none".
  if (card == null || card.isEmpty) {
    b.writeln('EMERGENCY CARD (as written by a guardian)');
    b.writeln(allergyExportLine(const <String>[], null));
    b.writeln();
  }
  if (card != null && !card.isEmpty) {
    b.writeln('EMERGENCY CARD (as written by a guardian)');
    b.writeln(allergyExportLine(card.allergies, card.allergyNone));
    if (card.conditions.isNotEmpty) b.writeln('Conditions: ${card.conditions.join('; ')}');
    if (!card.doctor.isEmpty) {
      b.writeln(
        'Doctor: ${<String>[
          if (card.doctor.name.isNotEmpty) card.doctor.name,
          if (card.doctor.practice.isNotEmpty) card.doctor.practice,
          if (card.doctor.phone.isNotEmpty) card.doctor.phone,
        ].join(', ')}',
      );
    }
    for (final c in card.contacts) {
      b.writeln('Contact: ${<String>[c.name, if (c.relation.isNotEmpty) c.relation, if (c.phone.isNotEmpty) c.phone].join(', ')}');
    }
    b.writeln();
  }

  b.writeln('MEDICINES (from the medicines log, as written)');
  final List<CpMedLine> lines = cpMedicineLines(meds);
  if (lines.isEmpty) {
    b.writeln('(none written)');
  } else {
    for (final CpMedLine m in lines) {
      b.writeln('- ${m.text}');
    }
  }
  b.writeln();

  if (planPhotoLabels.isNotEmpty) {
    b.writeln("DOCTOR'S PLANS KEPT AS PHOTOS ON THIS PHONE");
    for (final String l in planPhotoLabels) {
      b.writeln('- $l (show the photo from the phone)');
    }
    b.writeln();
  }
  if (options.everyday) entries(careProfilePartTitle(CareProfilePart.everyday, childName), CareProfilePart.everyday);
  if (options.helps) entries(careProfilePartTitle(CareProfilePart.helps, childName), CareProfilePart.helps);
  if (options.health && unlocked) entries(careProfilePartTitle(CareProfilePart.health, childName), CareProfilePart.health);
  if (options.moods && unlocked) entries(careProfilePartTitle(CareProfilePart.moods, childName), CareProfilePart.moods);
  return b.toString().trimRight();
}

// ================================================================== plan photos ===
/// A photo of a doctor's plan (an asthma or allergy action plan) that a grown-up chose. Never made by the app.
class CpPlanPhoto {
  const CpPlanPhoto({required this.id, required this.label, required this.bytes, required this.at, this.byId = '', this.byName = ''});
  final String id;
  final String label;
  final Uint8List bytes;
  final DateTime at;
  final String byId;
  final String byName;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'label': label,
    'img': base64Encode(bytes),
    'at': at.toUtc().toIso8601String(),
    'byId': byId,
    'byName': byName,
  };

  static CpPlanPhoto? tryFromJson(Object? j) {
    if (j is! Map || j['img'] is! String) return null;
    final String id = _line(j['id']), label = _line(j['label']);
    final DateTime? at = j['at'] is String ? DateTime.tryParse(j['at']! as String) : null;
    if (id.isEmpty || label.isEmpty || at == null) return null;
    try {
      final Uint8List b = base64Decode(j['img']! as String);
      if (!cpLooksLikeImage(b)) return null;
      return CpPlanPhoto(id: id, label: label, bytes: b, at: at.toUtc(), byId: _line(j['byId']), byName: _line(j['byName']));
    } catch (_) {
      return null;
    }
  }
}

/// A JPEG or a PNG by its first bytes. Anything else is not kept.
bool cpLooksLikeImage(Uint8List b) {
  if (b.length < 8) return false;
  final bool jpeg = b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF;
  final bool png = b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47;
  return jpeg || png;
}

/// A result type shared with the medicines log, so a screen words every refusal the same way.
typedef CpResult<T> = CareResult<T>;
