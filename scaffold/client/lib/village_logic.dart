// OLIVE BRANCH — suite D VILLAGE, pure logic: grandparent corner, her people in
// pictures, a welcome story, a sibling shelf, the sitter pass and the school
// bridge. No longer UNVERIFIED — verified by CI (client/test/village_logic_test.dart).
//
// OFFLINE AND ON-DEVICE ONLY. Nothing here opens a socket or contacts a person,
// a school or another home. Everything is kept on THIS device and says so;
// sharing between homes (and a link a sitter opens on their own phone, and a
// teacher's note arriving) is parked, so no type below has a "shared with",
// "sent to", "opened by" or "expires" field. A page only ever leaves the device
// because a grown-up holds the screen up and shows it.
//
// WHO WRITES WHAT. A GUARDIAN writes every word here. The child reads what a
// guardian chose to show her, and (for the sibling shelf only) leaves and takes
// down a picture. Nothing is generated: no text about a new partner, a family
// change or a person's role. Every name and every relationship word on a page
// is a string a guardian typed; her people, in pictures, take their NAMES only
// from the family-structure model (what a guardian chose in the family builder).
//
// NO LOCATION (P3): a school name, a caption or a line that looks like a street
// address or coordinates is refused (rhythm_logic.dart's guard). NO SCORES (P2):
// nothing here counts, ranks or streaks anything; the shelf never shows how many
// pictures it holds. NO CALLING: a phone number is text a guardian wrote, shown
// large; the app never dials it.
library;

import 'dart:convert';

import 'family_structure_logic.dart' show ChildView, bandForYears;
import 'picture_library.dart';
import 'rhythm_logic.dart';

// ---------------------------------------------------------------- limits ----
const int maxGrandCards = 4;
const int maxGrandTextChars = 200;
const int maxWelcomeStories = 3;
const int maxWelcomePages = 6;
const int maxWelcomePageChars = 160;
const int maxSiblings = 4;
const int maxNotesPerSibling = 6;
const int maxFaces = 24;
const int maxPassLines = 8;
const int maxPassContacts = 5;
const int maxSchoolContacts = 4;
const int maxPassLineChars = 80;
const int maxNameChars = 30;
const int maxSchoolNameChars = 40;

/// The pictures a card, a story page or a face may use (never a worry picture:
/// those are hers alone, and never a symbol).
const Set<PictureGroup> villagePictures = <PictureGroup>{
  PictureGroup.routine, PictureGroup.thing, PictureGroup.room, PictureGroup.person,
};
const Set<PictureGroup> facePictures = <PictureGroup>{PictureGroup.person};

/// What a sibling may leave on a shelf: a thing, a sky or a small word-picture.
const Set<PictureGroup> shelfPictures = <PictureGroup>{
  PictureGroup.thing, PictureGroup.weather, PictureGroup.symbolExtra,
};

final RegExp _phoneChars = RegExp(r'^[0-9+\-() .]+$');

/// A phone number a guardian typed: digits, spaces, + - ( ) . only, 7 to 15
/// digits. Returned tidied (single spaces). The app never dials it.
String cleanPhone(Object? raw) {
  if (raw is! String) throw const RvRefused('bad_number');
  final String t = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (t.isEmpty || t.length > 24 || !_phoneChars.hasMatch(t)) throw const RvRefused('bad_number');
  final int digits = t.replaceAll(RegExp(r'[^0-9]'), '').length;
  if (digits < 7 || digits > 15) throw const RvRefused('bad_number');
  return t;
}

/// 0..[maxLines] short lines a guardian typed. Blank lines are dropped; one
/// line too long, or too many lines, is refused (never silently cut).
List<String> cleanLines(Object? raw, {required int maxLines, int maxChars = maxPassLineChars}) {
  if (raw is! List) throw const RvRefused('bad_text');
  final List<String> out = <String>[];
  for (final Object? l in raw) {
    if (l is! String) throw const RvRefused('bad_text');
    if (l.trim().isEmpty) continue;
    out.add(cleanText(l, max: maxChars));
  }
  if (out.length > maxLines) throw const RvRefused('too_many_lines');
  return out;
}

List<String>? _tryLines(Object? raw, int maxLines, [int maxChars = maxPassLineChars]) {
  try {
    return cleanLines(raw, maxLines: maxLines, maxChars: maxChars);
  } on RvRefused {
    return null;
  }
}

// ============================================================ GRANDPARENT ====
/// One huge button on the grandparent corner: a picture, a title and a short
/// text, all of it written by a guardian.
class GrandCard {
  const GrandCard({required this.id, required this.picture, required this.title, this.text = ''});
  final String id;
  final String picture;
  final String title;
  final String text;

  Map<String, Object?> toJson() => <String, Object?>{'id': id, 'picture': picture, 'title': title, 'text': text};

  static GrandCard? tryFromJson(Object? j) {
    if (j is! Map) return null;
    final Object? id = j['id'], pic = j['picture'], title = j['title'], text = j['text'];
    if (!isIdLike(id) || !isPictureIn(pic, villagePictures) || title is! String || text is! String) return null;
    try {
      return GrandCard(
          id: id! as String, picture: pic! as String, title: cleanText(title),
          text: cleanText(text, max: maxGrandTextChars, allowEmpty: true));
    } on RvRefused {
      return null;
    }
  }
}

/// A phone line written down for a grandparent: who it is, the number (as text)
/// and a short note. Shown large; never dialled.
class PhoneLine {
  const PhoneLine({required this.who, required this.number, this.note = ''});
  final String who;
  final String number;
  final String note;

  Map<String, Object?> toJson() => <String, Object?>{'who': who, 'number': number, 'note': note};

  static PhoneLine? tryFromJson(Object? j) {
    if (j is! Map) return null;
    try {
      return PhoneLine(
          who: cleanText(j['who']), number: cleanPhone(j['number']),
          note: cleanText(j['note'], max: maxLineChars, allowEmpty: true));
    } on RvRefused {
      return null;
    }
  }
}

/// What to call the grown-up the page is for ("Nana"), up to four big cards and
/// a phone line. Large print is a presentation of THIS, not a second copy.
class GrandCorner {
  const GrandCorner({this.name = '', this.cards = const <GrandCard>[], this.phone});
  final String name;
  final List<GrandCard> cards;
  final PhoneLine? phone;

  bool get isEmpty => cards.isEmpty && phone == null;

  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'cards': <Object?>[for (final GrandCard c in cards) c.toJson()],
        'phone': phone?.toJson(),
      };

  static GrandCorner? tryFromJson(Object? j) {
    if (j is! Map) return null;
    String name;
    try {
      name = cleanText(j['name'], allowEmpty: true);
    } on RvRefused {
      return null;
    }
    final List<GrandCard> cards = <GrandCard>[];
    final Set<String> seen = <String>{};
    final Object? raw = j['cards'];
    if (raw is List) {
      for (final Object? r in raw) {
        final GrandCard? c = GrandCard.tryFromJson(r);
        if (c != null && seen.add(c.id) && cards.length < maxGrandCards) cards.add(c);
      }
    }
    return GrandCorner(name: name, cards: cards, phone: PhoneLine.tryFromJson(j['phone']));
  }
}

/// Builds a checked corner, or throws [RvRefused].
GrandCorner makeGrandCorner({String name = '', List<GrandCard> cards = const <GrandCard>[], PhoneLine? phone}) {
  if (cards.length > maxGrandCards) throw const RvRefused('too_many_cards');
  final Set<String> ids = <String>{};
  final List<GrandCard> clean = <GrandCard>[];
  for (final GrandCard c in cards) {
    final GrandCard? k = GrandCard.tryFromJson(c.toJson());
    if (k == null) throw const RvRefused('bad_card');
    if (!ids.add(k.id)) throw const RvRefused('duplicate_id');
    clean.add(k);
  }
  PhoneLine? p;
  if (phone != null) {
    p = PhoneLine(
        who: cleanText(phone.who), number: cleanPhone(phone.number),
        note: cleanText(phone.note, max: maxLineChars, allowEmpty: true));
  }
  return GrandCorner(name: cleanText(name, allowEmpty: true), cards: clean, phone: p);
}

// ============================================================ WELCOME STORY ===
class StoryPage {
  const StoryPage({required this.picture, required this.text});
  final String picture;
  final String text;
  Map<String, Object?> toJson() => <String, Object?>{'picture': picture, 'text': text};

  static StoryPage? tryFromJson(Object? j) {
    if (j is! Map) return null;
    final Object? pic = j['picture'], text = j['text'];
    if (!isPictureIn(pic, villagePictures) || text is! String) return null;
    try {
      return StoryPage(picture: pic! as String, text: cleanText(text, max: maxWelcomePageChars));
    } on RvRefused {
      return null;
    }
  }
}

/// A picture story a guardian wrote. It stays HELD until the guardian releases
/// it ([releasedOn] set); a held story is never read by the child side.
class WelcomeStory {
  const WelcomeStory({required this.id, required this.title, required this.pages, this.releasedOn});
  final String id;
  final String title;
  final List<StoryPage> pages;

  /// yyyy-mm-dd the guardian released it, or null while it is held.
  final String? releasedOn;

  bool get released => releasedOn != null;

  WelcomeStory copyWith({String? title, List<StoryPage>? pages, String? releasedOn, bool hold = false}) =>
      WelcomeStory(
          id: id, title: title ?? this.title, pages: pages ?? this.pages,
          releasedOn: hold ? null : (releasedOn ?? this.releasedOn));

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id, 'title': title, 'pages': <Object?>[for (final StoryPage p in pages) p.toJson()],
        'releasedOn': releasedOn,
      };

  static WelcomeStory? tryFromJson(Object? j) {
    if (j is! Map) return null;
    final Object? id = j['id'], title = j['title'], pages = j['pages'], on = j['releasedOn'];
    if (!isIdLike(id) || title is! String || pages is! List || pages.isEmpty || pages.length > maxWelcomePages) return null;
    if (on != null && !isIsoDay(on)) return null;
    final List<StoryPage> out = <StoryPage>[];
    for (final Object? p in pages) {
      final StoryPage? sp = StoryPage.tryFromJson(p);
      if (sp == null) return null;
      out.add(sp);
    }
    try {
      return WelcomeStory(id: id! as String, title: cleanText(title), pages: out, releasedOn: on as String?);
    } on RvRefused {
      return null;
    }
  }
}

/// Builds a checked story (held), or throws [RvRefused].
WelcomeStory makeStory({required String id, required String title, required List<StoryPage> pages}) {
  if (!isIdLike(id)) throw const RvRefused('bad_id');
  if (pages.isEmpty) throw const RvRefused('no_pages');
  if (pages.length > maxWelcomePages) throw const RvRefused('too_many_pages');
  final List<StoryPage> clean = <StoryPage>[];
  for (final StoryPage p in pages) {
    final StoryPage? k = StoryPage.tryFromJson(p.toJson());
    if (k == null) throw const RvRefused('bad_page');
    clean.add(k);
  }
  return WelcomeStory(id: id, title: cleanText(title), pages: clean);
}

// ============================================================ SIBLING SHELF ===
class SiblingSlot {
  const SiblingSlot({required this.id, required this.name, required this.picture});
  final String id;
  final String name;
  final String picture;
  Map<String, Object?> toJson() => <String, Object?>{'id': id, 'name': name, 'picture': picture};

  static SiblingSlot? tryFromJson(Object? j) {
    if (j is! Map) return null;
    final Object? id = j['id'], name = j['name'], pic = j['picture'];
    if (!isIdLike(id) || name is! String || !isPictureIn(pic, facePictures)) return null;
    try {
      return SiblingSlot(id: id! as String, name: cleanText(name), picture: pic! as String);
    } on RvRefused {
      return null;
    }
  }
}

/// One picture left for a sibling. No author, no time of day, no read mark: it
/// is just there until someone takes it down.
class ShelfNote {
  const ShelfNote({required this.id, required this.toId, required this.picture});
  final String id;
  final String toId;
  final String picture;
  Map<String, Object?> toJson() => <String, Object?>{'id': id, 'toId': toId, 'picture': picture};

  static ShelfNote? tryFromJson(Object? j) {
    if (j is! Map) return null;
    final Object? id = j['id'], to = j['toId'], pic = j['picture'];
    if (!isIdLike(id) || !isIdLike(to) || !isPictureIn(pic, shelfPictures)) return null;
    return ShelfNote(id: id! as String, toId: to! as String, picture: pic! as String);
  }
}

class SiblingShelf {
  const SiblingShelf({this.siblings = const <SiblingSlot>[], this.notes = const <ShelfNote>[]});
  final List<SiblingSlot> siblings;
  final List<ShelfNote> notes;

  bool get isEmpty => siblings.isEmpty;

  List<ShelfNote> notesFor(String siblingId) =>
      <ShelfNote>[for (final ShelfNote n in notes) if (n.toId == siblingId) n];

  Map<String, Object?> toJson() => <String, Object?>{
        'siblings': <Object?>[for (final SiblingSlot s in siblings) s.toJson()],
        'notes': <Object?>[for (final ShelfNote n in notes) n.toJson()],
      };

  /// Tolerant. A note for a sibling who is no longer on the shelf is dropped,
  /// and each sibling keeps at most [maxNotesPerSibling] notes.
  static SiblingShelf fromJson(Object? j) {
    if (j is! Map) return const SiblingShelf();
    final List<SiblingSlot> sibs = <SiblingSlot>[];
    final Set<String> ids = <String>{};
    final Object? rawS = j['siblings'];
    if (rawS is List) {
      for (final Object? r in rawS) {
        final SiblingSlot? s = SiblingSlot.tryFromJson(r);
        if (s != null && ids.add(s.id) && sibs.length < maxSiblings) sibs.add(s);
      }
    }
    final List<ShelfNote> notes = <ShelfNote>[];
    final Set<String> noteIds = <String>{};
    final Map<String, int> per = <String, int>{};
    final Object? rawN = j['notes'];
    if (rawN is List) {
      for (final Object? r in rawN) {
        final ShelfNote? n = ShelfNote.tryFromJson(r);
        if (n == null || !ids.contains(n.toId) || !noteIds.add(n.id)) continue;
        if ((per[n.toId] ?? 0) >= maxNotesPerSibling) continue;
        per[n.toId] = (per[n.toId] ?? 0) + 1;
        notes.add(n);
      }
    }
    return SiblingShelf(siblings: sibs, notes: notes);
  }
}

/// A checked list of siblings (guardian editor); notes for anyone removed go too.
SiblingShelf withSiblings(SiblingShelf current, List<SiblingSlot> siblings) {
  if (siblings.length > maxSiblings) throw const RvRefused('too_many_siblings');
  final Set<String> ids = <String>{};
  final List<SiblingSlot> clean = <SiblingSlot>[];
  for (final SiblingSlot s in siblings) {
    final SiblingSlot? k = SiblingSlot.tryFromJson(s.toJson());
    if (k == null) throw const RvRefused('bad_sibling');
    if (!ids.add(k.id)) throw const RvRefused('duplicate_id');
    clean.add(k);
  }
  return SiblingShelf(siblings: clean, notes: <ShelfNote>[for (final ShelfNote n in current.notes) if (ids.contains(n.toId)) n]);
}

/// Leaves a picture for [toId]. The shelf for one sibling holds
/// [maxNotesPerSibling]; a new one makes the oldest drop off, so it never says "full".
SiblingShelf leaveNote(SiblingShelf s, ShelfNote note) {
  if (!s.siblings.any((SiblingSlot x) => x.id == note.toId)) throw const RvRefused('unknown_sibling');
  if (ShelfNote.tryFromJson(note.toJson()) == null) throw const RvRefused('bad_picture');
  if (s.notes.any((ShelfNote n) => n.id == note.id)) throw const RvRefused('duplicate_id');
  final List<ShelfNote> mine = s.notesFor(note.toId);
  final List<ShelfNote> rest = <ShelfNote>[for (final ShelfNote n in s.notes) if (n.toId != note.toId) n];
  final List<ShelfNote> kept = mine.length >= maxNotesPerSibling ? mine.sublist(mine.length - maxNotesPerSibling + 1) : mine;
  return SiblingShelf(siblings: s.siblings, notes: <ShelfNote>[...rest, ...kept, note]);
}

SiblingShelf takeDownNote(SiblingShelf s, String noteId) =>
    SiblingShelf(siblings: s.siblings, notes: <ShelfNote>[for (final ShelfNote n in s.notes) if (n.id != noteId) n]);

SiblingShelf clearNotes(SiblingShelf s) => SiblingShelf(siblings: s.siblings);

// ===================================================== SITTER PASS & SCHOOL ===
/// Someone to reach, as a guardian wrote them: a name, whatever the guardian
/// calls them ("Mom", "Dr. Okafor"), a number as text and the best times.
class PassContact {
  const PassContact({required this.id, required this.name, this.relation = '', required this.number, this.bestTimes = ''});
  final String id;
  final String name;
  final String relation;
  final String number;
  final String bestTimes;

  Map<String, Object?> toJson() =>
      <String, Object?>{'id': id, 'name': name, 'relation': relation, 'number': number, 'bestTimes': bestTimes};

  static PassContact? tryFromJson(Object? j) {
    if (j is! Map) return null;
    if (!isIdLike(j['id'])) return null;
    try {
      return PassContact(
          id: j['id']! as String, name: cleanText(j['name']),
          relation: cleanText(j['relation'], allowEmpty: true), number: cleanPhone(j['number']),
          bestTimes: cleanText(j['bestTimes'], allowEmpty: true));
    } on RvRefused {
      return null;
    }
  }
}

List<PassContact> checkedContacts(List<PassContact> raw, int max) {
  if (raw.length > max) throw const RvRefused('too_many_contacts');
  final Set<String> ids = <String>{};
  final List<PassContact> out = <PassContact>[];
  for (final PassContact c in raw) {
    if (!isIdLike(c.id)) throw const RvRefused('bad_id');
    final PassContact? k = PassContact.tryFromJson(c.toJson());
    if (k == null) throw const RvRefused('bad_contact');
    if (!ids.add(k.id)) throw const RvRefused('duplicate_id');
    out.add(k);
  }
  return out;
}

List<PassContact> _contactsFrom(Object? raw, int max) {
  final List<PassContact> out = <PassContact>[];
  if (raw is List) {
    final Set<String> seen = <String>{};
    for (final Object? r in raw) {
      final PassContact? c = PassContact.tryFromJson(r);
      if (c != null && seen.add(c.id) && out.length < max) out.add(c);
    }
  }
  return out;
}

/// One heading and its plain lines, the shape both a pass and its printable
/// layout are built from.
class PassSection {
  const PassSection(this.heading, this.lines);
  final String heading;
  final List<String> lines;
}

/// A one-page summary a guardian wrote for a trusted adult for one evening.
/// Allergies are WORDS a guardian typed; the app adds nothing and checks nothing
/// medical.
class SitterPass {
  const SitterPass({
    this.title = 'Tonight', this.forWho = '', this.when = '',
    this.routine = const <String>[], this.allergies = const <String>[],
    this.notes = const <String>[], this.contacts = const <PassContact>[], this.writtenOn,
  });
  final String title;
  final String forWho;
  final String when;
  final List<String> routine;
  final List<String> allergies;
  final List<String> notes;
  final List<PassContact> contacts;

  /// yyyy-mm-dd the guardian last saved it (set by the service from the clock).
  final String? writtenOn;

  bool get isEmpty => routine.isEmpty && allergies.isEmpty && notes.isEmpty && contacts.isEmpty;

  SitterPass copyWith({String? writtenOn}) => SitterPass(
      title: title, forWho: forWho, when: when, routine: routine, allergies: allergies, notes: notes,
      contacts: contacts, writtenOn: writtenOn ?? this.writtenOn);

  Map<String, Object?> toJson() => <String, Object?>{
        'title': title, 'forWho': forWho, 'when': when, 'routine': routine, 'allergies': allergies,
        'notes': notes, 'contacts': <Object?>[for (final PassContact c in contacts) c.toJson()],
        'writtenOn': writtenOn,
      };

  static SitterPass? tryFromJson(Object? j) {
    if (j is! Map) return null;
    final List<String>? routine = _tryLines(j['routine'], maxPassLines);
    final List<String>? allergies = _tryLines(j['allergies'], maxPassLines);
    final List<String>? notes = _tryLines(j['notes'], maxPassLines);
    final Object? on = j['writtenOn'];
    if (routine == null || allergies == null || notes == null || (on != null && !isIsoDay(on))) return null;
    try {
      return SitterPass(
          title: cleanText(j['title']), forWho: cleanText(j['forWho'], allowEmpty: true),
          when: cleanText(j['when'], allowEmpty: true), routine: routine, allergies: allergies, notes: notes,
          contacts: _contactsFrom(j['contacts'], maxPassContacts), writtenOn: on as String?);
    } on RvRefused {
      return null;
    }
  }
}

/// Builds a checked pass from what a guardian typed, or throws [RvRefused].
SitterPass makeSitterPass({
  String title = 'Tonight', String forWho = '', String when = '',
  List<String> routine = const <String>[], List<String> allergies = const <String>[],
  List<String> notes = const <String>[], List<PassContact> contacts = const <PassContact>[],
}) =>
    SitterPass(
        title: cleanText(title), forWho: cleanText(forWho, allowEmpty: true), when: cleanText(when, allowEmpty: true),
        routine: cleanLines(routine, maxLines: maxPassLines), allergies: cleanLines(allergies, maxLines: maxPassLines),
        notes: cleanLines(notes, maxLines: maxPassLines), contacts: checkedContacts(contacts, maxPassContacts));

/// What is on the page, in reading order, empty sections left out.
List<PassSection> sitterSections(SitterPass p) => <PassSection>[
      if (p.allergies.isNotEmpty) PassSection('Allergies', p.allergies),
      if (p.routine.isNotEmpty) PassSection('Routine', p.routine),
      if (p.notes.isNotEmpty) PassSection('Good to know', p.notes),
      if (p.contacts.isNotEmpty) PassSection('Who to reach', <String>[for (final PassContact c in p.contacts) contactLine(c)]),
    ];

String contactLine(PassContact c) {
  final StringBuffer b = StringBuffer(c.name);
  if (c.relation.isNotEmpty) b.write(' (${c.relation})');
  b.write(': ${c.number}');
  if (c.bestTimes.isNotEmpty) b.write(', best ${c.bestTimes}');
  return b.toString();
}

/// A guardian-written summary for a school, kept here. The school is never
/// contacted; a guardian shows or hands over the screen.
class SchoolBridge {
  const SchoolBridge({
    this.school = '', this.className = '', this.helps = const <String>[], this.allergies = const <String>[],
    this.pickup = const <String>[], this.notes = const <String>[], this.contacts = const <PassContact>[],
    this.writtenOn,
  });
  final String school;
  final String className;
  final List<String> helps;
  final List<String> allergies;
  final List<String> pickup;
  final List<String> notes;
  final List<PassContact> contacts;
  final String? writtenOn;

  bool get isEmpty =>
      school.isEmpty && helps.isEmpty && allergies.isEmpty && pickup.isEmpty && notes.isEmpty && contacts.isEmpty;

  SchoolBridge copyWith({String? writtenOn}) => SchoolBridge(
      school: school, className: className, helps: helps, allergies: allergies, pickup: pickup, notes: notes,
      contacts: contacts, writtenOn: writtenOn ?? this.writtenOn);

  Map<String, Object?> toJson() => <String, Object?>{
        'school': school, 'className': className, 'helps': helps, 'allergies': allergies, 'pickup': pickup,
        'notes': notes, 'contacts': <Object?>[for (final PassContact c in contacts) c.toJson()],
        'writtenOn': writtenOn,
      };

  static SchoolBridge? tryFromJson(Object? j) {
    if (j is! Map) return null;
    final List<String>? helps = _tryLines(j['helps'], maxPassLines);
    final List<String>? allergies = _tryLines(j['allergies'], maxPassLines);
    final List<String>? pickup = _tryLines(j['pickup'], 4);
    final List<String>? notes = _tryLines(j['notes'], 4);
    final Object? on = j['writtenOn'];
    if (helps == null || allergies == null || pickup == null || notes == null || (on != null && !isIsoDay(on))) {
      return null;
    }
    try {
      return SchoolBridge(
          school: cleanText(j['school'], max: maxSchoolNameChars, allowEmpty: true),
          className: cleanText(j['className'], allowEmpty: true), helps: helps, allergies: allergies,
          pickup: pickup, notes: notes, contacts: _contactsFrom(j['contacts'], maxSchoolContacts),
          writtenOn: on as String?);
    } on RvRefused {
      return null;
    }
  }
}

SchoolBridge makeSchoolBridge({
  String school = '', String className = '', List<String> helps = const <String>[],
  List<String> allergies = const <String>[], List<String> pickup = const <String>[],
  List<String> notes = const <String>[], List<PassContact> contacts = const <PassContact>[],
}) =>
    SchoolBridge(
        school: cleanText(school, max: maxSchoolNameChars, allowEmpty: true),
        className: cleanText(className, allowEmpty: true), helps: cleanLines(helps, maxLines: maxPassLines),
        allergies: cleanLines(allergies, maxLines: maxPassLines), pickup: cleanLines(pickup, maxLines: 4),
        notes: cleanLines(notes, maxLines: 4), contacts: checkedContacts(contacts, maxSchoolContacts));

List<PassSection> schoolSections(SchoolBridge s) => <PassSection>[
      if (s.helps.isNotEmpty) PassSection('What helps', s.helps),
      if (s.allergies.isNotEmpty) PassSection('Allergies', s.allergies),
      if (s.pickup.isNotEmpty) PassSection('Who collects her', s.pickup),
      if (s.notes.isNotEmpty) PassSection('Good to know', s.notes),
      if (s.contacts.isNotEmpty) PassSection('Who to reach', <String>[for (final PassContact c in s.contacts) contactLine(c)]),
    ];

/// The page as plain text, for tests and for a guardian's own reading: the same
/// words the screen shows, no more.
String passText(String heading, List<String> header, List<PassSection> sections) {
  final StringBuffer b = StringBuffer(heading);
  for (final String h in header) {
    if (h.isNotEmpty) b.write('\n$h');
  }
  for (final PassSection s in sections) {
    b.write('\n\n${s.heading}');
    for (final String l in s.lines) {
      b.write('\n- $l');
    }
  }
  return b.toString();
}

// ===================================================================== DOC ====
/// Everything suite D keeps for one child, besides the two passes. Guardian
/// written; the child side reads a NARROW part of it (see the service).
class VillageDoc {
  const VillageDoc({
    this.suiteOn = true, this.grand, this.stories = const <WelcomeStory>[],
    this.shelf = const SiblingShelf(), this.faces = const <String, String>{},
  });
  final bool suiteOn;
  final GrandCorner? grand;
  final List<WelcomeStory> stories;
  final SiblingShelf shelf;

  /// personId (from the family builder) -> a person-group picture she sees as that face.
  final Map<String, String> faces;

  VillageDoc copyWith({
    bool? suiteOn, GrandCorner? grand, bool clearGrand = false, List<WelcomeStory>? stories,
    SiblingShelf? shelf, Map<String, String>? faces,
  }) =>
      VillageDoc(
          suiteOn: suiteOn ?? this.suiteOn, grand: clearGrand ? null : (grand ?? this.grand),
          stories: stories ?? this.stories, shelf: shelf ?? this.shelf, faces: faces ?? this.faces);

  Map<String, Object?> toJson() => <String, Object?>{
        'suiteOn': suiteOn, 'grand': grand?.toJson(),
        'stories': <Object?>[for (final WelcomeStory s in stories) s.toJson()],
        'shelf': shelf.toJson(), 'faces': faces,
      };

  /// Tolerant: every field falls back on its own.
  static VillageDoc fromJson(Object? j) {
    if (j is! Map) return const VillageDoc();
    final List<WelcomeStory> stories = <WelcomeStory>[];
    final Set<String> seen = <String>{};
    final Object? rs = j['stories'];
    if (rs is List) {
      for (final Object? r in rs) {
        final WelcomeStory? s = WelcomeStory.tryFromJson(r);
        if (s != null && seen.add(s.id) && stories.length < maxWelcomeStories) stories.add(s);
      }
    }
    final Map<String, String> faces = <String, String>{};
    final Object? rf = j['faces'];
    if (rf is Map) {
      for (final MapEntry<Object?, Object?> e in rf.entries) {
        if (isIdLike(e.key) && isPictureIn(e.value, facePictures) && faces.length < maxFaces) {
          faces[e.key! as String] = e.value! as String;
        }
      }
    }
    return VillageDoc(
        suiteOn: j['suiteOn'] is bool ? j['suiteOn'] as bool : true, grand: GrandCorner.tryFromJson(j['grand']),
        stories: stories, shelf: SiblingShelf.fromJson(j['shelf']), faces: faces);
  }
}

/// The two private passes, kept apart from the rest so a sitter page can never
/// be reached through a child lens (the child side has no reader for this doc).
class PassesDoc {
  const PassesDoc({this.sitter, this.school});
  final SitterPass? sitter;
  final SchoolBridge? school;

  PassesDoc copyWith({SitterPass? sitter, bool clearSitter = false, SchoolBridge? school, bool clearSchool = false}) =>
      PassesDoc(
          sitter: clearSitter ? null : (sitter ?? this.sitter), school: clearSchool ? null : (school ?? this.school));

  Map<String, Object?> toJson() => <String, Object?>{'sitter': sitter?.toJson(), 'school': school?.toJson()};

  static PassesDoc fromJson(Object? j) =>
      j is! Map ? const PassesDoc() : PassesDoc(sitter: SitterPass.tryFromJson(j['sitter']), school: SchoolBridge.tryFromJson(j['school']));
}

/// The stored size of a document, for the size-bound tests.
int jsonBytes(Object? j) => utf8.encode(jsonEncode(j)).length;

// ===================================================================== GATE ===
/// What suite D puts in front of the CHILD.
class VillageTiles {
  const VillageTiles({this.familyTree = false, this.siblings = false, this.stories = const <String>[]});
  final bool familyTree;
  final bool siblings;

  /// Ids of the released stories she may open (a held one is never listed).
  final List<String> stories;

  bool get any => familyTree || siblings || stories.isNotEmpty;
  static const VillageTiles none = VillageTiles();
}

/// Her age in whole years, failing closed to FIVE (never to older).
int villageAgeOrFive(Object? yearsOld) =>
    yearsOld is num && yearsOld.isFinite && yearsOld >= 0 ? yearsOld.floor() : 5;

/// Which Village tiles she sees. REUSES the family-structure model's answer (her
/// band, her More hub, her `myPeople` tile and her released people); computes
/// no band or feature of its own. With no snapshot the structure is unknown, so
/// her people in pictures stay off rather than guess; the age comes from
/// [yearsOld], failing closed to five. The youngest band gets nothing.
VillageTiles villageTilesFor({ChildView? view, Object? yearsOld, bool suiteOn = true, VillageDoc doc = const VillageDoc()}) {
  final String band = view?.band ?? bandForYears(villageAgeOrFive(yearsOld));
  if (band == 't34' || (view != null && !view.hasTile('more')) || !suiteOn) return VillageTiles.none;
  return VillageTiles(
    familyTree: view != null && view.hasTile('myPeople') && view.places.isNotEmpty,
    siblings: !doc.shelf.isEmpty,
    stories: <String>[for (final WelcomeStory s in doc.stories) if (s.released) s.id],
  );
}
