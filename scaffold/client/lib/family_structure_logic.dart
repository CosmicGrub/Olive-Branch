// OLIVE BRANCH — Family structure and age bands, pure logic (suites J and K).
// No longer UNVERIFIED — verified by CI against the TypeScript module's golden vectors.
// A 1:1 semantic port of packages/family-structure/src/family.ts, kept close to the TS
// original (same names, same shapes, same ordering) so the two stay auditable side by
// side. Design: docs/superpowers/specs/2026-11-07-age-bands-and-family-structure-design.md.
//
// Nothing here touches a socket, a clock, storage or a widget; every function that needs
// "today" takes it as a child-local yyyy-mm-dd string.
// client/test/family_structure_logic_test.dart runs this file against
// packages/family-structure/test/vectors.json, which the TypeScript module generates.
//
//  F1  The guardian ALONE edits the structure.
//  F2  She reads only what has been RELEASED (now / a date reached / a release entry).
//  F3  "Hold until I've told her" is a real timing choice; settings cannot be held.
//  F4  Ladder rungs are permanent; every other age default is a proposal.
//  F5  She sees only labels a guardian chose; background roles are never in her people.
//  F6  A court order wins: a locked rhythm is not editable.
//  F7  A story is guardian-authored text, bounded. Nothing here writes one.

// ================================================================ constants ==
const List<String> ageBands = <String>['t34', 't57', 't812', 't13'];
const List<String> areas = <String>['reading', 'games', 'chat', 'calendar', 'people'];
const List<String> roles = <String>[
  'guardian', 'parent', 'step_parent', 'relative', 'trusted_adult', 'sitter',
  'foster_parent', 'caseworker', 'therapist',
];
const List<String> backgroundRoles = <String>['sitter', 'therapist', 'caseworker'];
const List<String> contactModes = <String>['live_call', 'message', 'postcard', 'voice_line', 'supervised_visit'];
const List<String> patterns = <String>['none', '2-2-3', '2-2-5-5', 'alternating_weeks', 'week_on_week_off', 'custom'];
const List<String> tileKeys = <String>[
  'call', 'stories', 'colour', 'myDay', 'play', 'messages', 'showTell', 'homework', 'myList', 'myPeople', 'more',
];
const List<String> suiteKeys = <String>[
  'calls', 'messages', 'stories', 'games', 'showTell', 'homework', 'myList', 'myPeople', 'myDay',
  'birthday', 'twoSkies', 'postcards', 'weeks',
];
const int maxHomes = 4;
const int maxPeople = 24;
const int maxLabel = 30;
const int maxHomeName = 40;
const int maxStoryPages = 6;
const int maxStoryPageChars = 240;
const int maxDateAheadDays = 730;
const int storyShownDays = 14;
const String farPlaceName = 'Near and far';

// ============================================================ band table ====
class BandDef {
  const BandDef(this.id, this.minYears, this.maxYears, this.label, this.name, this.home, this.tiles,
      this.areaModes, this.summary);
  final String id;
  final int minYears;
  final int? maxYears;
  final String label;
  final String name;
  final String home;
  final List<String> tiles;
  final Map<String, String> areaModes;
  final List<String> summary;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id, 'minYears': minYears, 'maxYears': maxYears, 'label': label, 'name': name, 'home': home,
        'tiles': tiles, 'areaModes': areaModes, 'summary': summary,
      };
}

const List<String> _fullTiles = <String>[
  'myDay', 'play', 'messages', 'stories', 'showTell', 'homework', 'myList', 'myPeople', 'more',
];

const List<BandDef> bandTable = <BandDef>[
  BandDef('t34', 0, 4, '3 to 4', 'Three big pictures', 'icons3', <String>['call', 'stories', 'colour'],
      <String, String>{'reading': 'pictures', 'games': 'none', 'chat': 'none', 'calendar': 'none', 'people': 'call_only'},
      <String>['Three big pictures, no words to read', 'Every picture speaks its own name',
        'The call is the biggest thing, with the face of the person she calls',
        'Nothing moves and nothing is a setting']),
  BandDef('t57', 5, 7, '5 to 7', 'Pictures lead', 'pictures', _fullTiles,
      <String, String>{'reading': 'pictures_spoken', 'games': 'pairs', 'chat': 'pictures', 'calendar': 'my_day', 'people': 'my_people'},
      <String>['Pictures lead and every word can be heard', 'Her colour of the day and favourite things',
        'Games for two, played in turns', 'No settings of her own yet']),
  BandDef('t812', 8, 12, '8 to 12', 'Words and her own list', 'words', _fullTiles,
      <String, String>{'reading': 'words_beside', 'games': 'more', 'chat': 'short', 'calendar': 'weeks', 'people': 'my_people'},
      <String>['Words sit beside the pictures', 'A calendar of her weeks', 'More games, in a quiet grid',
        'Her own list arrives at 10, and stays hers']),
  BandDef('t13', 13, null, '13 and up', 'Mostly hers', 'words', _fullTiles,
      <String, String>{'reading': 'words', 'games': 'more', 'chat': 'full', 'calendar': 'own', 'people': 'my_people'},
      <String>['Quiet: calendar, availability, a private journal', 'Her choices come first',
        'Each step up is hers, and permanent']),
];

BandDef bandDef(String b) => bandTable.firstWhere((BandDef d) => d.id == b);
bool isAgeBand(Object? x) => x is String && ageBands.contains(x);
bool isArea(Object? x) => x is String && areas.contains(x);

/// Whole years to her natural band. Fails closed to the YOUNGEST band on junk.
String bandForYears(Object? years) {
  if (years is! num || years.isNaN || years.isInfinite || years < 0) return 't34';
  final int y = years.floor();
  if (y <= 4) return 't34';
  if (y <= 7) return 't57';
  if (y <= 12) return 't812';
  return 't13';
}

String effectiveBand(String natural, bool hold, String? released) {
  if (!hold || released == null || !isAgeBand(released)) return natural;
  return ageBands.indexOf(released) > ageBands.indexOf(natural) ? natural : released;
}

String areaBand(FamilyStructure s, String area, String band) {
  final String? o = s.areaBands[area];
  return isAgeBand(o) ? o! : band;
}

List<Map<String, Object?>> diffBands(String from, String to) {
  final BandDef a = bandDef(from), b = bandDef(to);
  return <Map<String, Object?>>[
    for (final String r in areas)
      if (a.areaModes[r] != b.areaModes[r]) <String, Object?>{'area': r, 'from': a.areaModes[r], 'to': b.areaModes[r]},
  ];
}

// ================================================================== rungs ===
const List<(int, String)> rungAges = <(int, String)>[
  (10, 'own_list'), (13, 'journal_absolute'), (14, 'own_calendar'), (15, 'publish_availability'),
  (16, 'curate_archive'), (17, 'own_export'), (18, 'everything'),
];

List<String> rungsAt(Object? years) {
  if (years is! num || years.isNaN || years.isInfinite) return <String>[];
  return <String>[for (final (int, String) r in rungAges) if (years >= r.$1) r.$2];
}

// ================================================================== shapes ===
class Home {
  const Home({required this.id, required this.name, required this.childSleeps});
  final String id;
  final String name;
  final bool childSleeps;
  Map<String, Object?> toJson() => <String, Object?>{'id': id, 'name': name, 'childSleeps': childSleeps};
  static Home fromJson(Map<String, Object?> j) =>
      Home(id: j['id']! as String, name: j['name']! as String, childSleeps: j['childSleeps']! as bool);
}

class Person {
  const Person({
    required this.id, required this.label, required this.role, this.homeId,
    this.contact = const <String>[], this.away, this.awayUntil,
  });
  final String id;
  final String label;
  final String role;
  final String? homeId;
  final List<String> contact;
  /// A person is "away" when [away] is true; [awayUntil] is the optional end date.
  final bool? away;
  final String? awayUntil;

  bool get isAwayFlag => away == true;

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id, 'label': label, 'role': role, 'homeId': homeId, 'contact': contact,
        'away': isAwayFlag ? <String, Object?>{'until': awayUntil} : null,
      };

  static Person fromJson(Map<String, Object?> j) {
    final Object? a = j['away'];
    return Person(
      id: j['id']! as String, label: j['label']! as String, role: j['role']! as String,
      homeId: j['homeId'] as String?,
      contact: <String>[for (final Object? c in (j['contact']! as List<Object?>)) c! as String],
      away: a == null ? null : true,
      awayUntil: a == null ? null : (a as Map<String, Object?>)['until'] as String?,
    );
  }

  Person copyWith({String? label, String? role, String? homeId, bool clearHome = false,
      List<String>? contact, bool? away, String? awayUntil, bool clearAway = false}) =>
      Person(
        id: id, label: label ?? this.label, role: role ?? this.role,
        homeId: clearHome ? null : (homeId ?? this.homeId), contact: contact ?? this.contact,
        away: clearAway ? null : (away ?? this.away), awayUntil: clearAway ? null : (awayUntil ?? this.awayUntil),
      );
}

class Rhythm {
  const Rhythm({this.pattern = 'none', this.exchangeDay, this.exchangeTime, this.source = 'guardian'});
  final String pattern;
  final int? exchangeDay;
  final String? exchangeTime;
  final String source;
  Map<String, Object?> toJson() => <String, Object?>{
        'pattern': pattern, 'exchangeDay': exchangeDay, 'exchangeTime': exchangeTime, 'source': source,
      };
  static Rhythm fromJson(Map<String, Object?> j) => Rhythm(
      pattern: j['pattern']! as String, exchangeDay: (j['exchangeDay'] as num?)?.toInt(),
      exchangeTime: j['exchangeTime'] as String?, source: j['source']! as String);
}

class FamilyStructure {
  const FamilyStructure({
    this.homes = const <Home>[], this.people = const <Person>[], this.rhythm = const Rhythm(),
    this.areaBands = const <String, String>{}, this.birthdayVisible = true,
    this.holdBandChange = true, this.releasedBand,
  });
  final List<Home> homes;
  final List<Person> people;
  final Rhythm rhythm;
  final Map<String, String> areaBands;
  final bool birthdayVisible;
  final bool holdBandChange;
  final String? releasedBand;

  FamilyStructure copyWith({List<Home>? homes, List<Person>? people, Rhythm? rhythm, Map<String, String>? areaBands,
      bool? birthdayVisible, bool? holdBandChange, String? releasedBand, bool clearReleased = false}) =>
      FamilyStructure(
        homes: homes ?? this.homes, people: people ?? this.people, rhythm: rhythm ?? this.rhythm,
        areaBands: areaBands ?? this.areaBands, birthdayVisible: birthdayVisible ?? this.birthdayVisible,
        holdBandChange: holdBandChange ?? this.holdBandChange,
        releasedBand: clearReleased ? null : (releasedBand ?? this.releasedBand),
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'homes': <Object?>[for (final Home h in homes) h.toJson()],
        'people': <Object?>[for (final Person p in people) p.toJson()],
        'rhythm': rhythm.toJson(),
        'areaBands': areaBands,
        'birthdayVisible': birthdayVisible,
        'holdBandChange': holdBandChange,
        'releasedBand': releasedBand,
      };

  static FamilyStructure fromJson(Map<String, Object?> j) => FamilyStructure(
        homes: <Home>[for (final Object? h in (j['homes']! as List<Object?>)) Home.fromJson(h! as Map<String, Object?>)],
        people: <Person>[for (final Object? p in (j['people']! as List<Object?>)) Person.fromJson(p! as Map<String, Object?>)],
        rhythm: Rhythm.fromJson(j['rhythm']! as Map<String, Object?>),
        areaBands: <String, String>{
          for (final MapEntry<String, Object?> e in (j['areaBands']! as Map<String, Object?>).entries) e.key: e.value! as String
        },
        birthdayVisible: j['birthdayVisible']! as bool,
        holdBandChange: j['holdBandChange']! as bool,
        releasedBand: j['releasedBand'] as String?,
      );
}

const FamilyStructure emptyStructure = FamilyStructure();

// ============================================================ derive view ====
class ChildPerson {
  const ChildPerson(this.id, this.name, this.buttons, this.apart);
  final String id;
  final String name;
  final List<String> buttons;
  final bool apart;
  Map<String, Object?> toJson() => <String, Object?>{'id': id, 'name': name, 'buttons': buttons, 'apart': apart};
}

class ChildPlace {
  const ChildPlace(this.id, this.name, this.kind, this.people);
  final String id;
  final String name;
  final String kind;
  final List<ChildPerson> people;
  Map<String, Object?> toJson() => <String, Object?>{
        'id': id, 'name': name, 'kind': kind, 'people': <Object?>[for (final ChildPerson p in people) p.toJson()],
      };
}

class ChildView {
  const ChildView({
    required this.band, required this.homeVariant, required this.tiles, required this.heroPersonId,
    required this.wordsBesidePictures, required this.speakEveryWord, required this.plainGreeting,
    required this.places, required this.features, required this.areas, required this.ladder,
    required this.birthdayVisible,
  });
  final String band;
  final String homeVariant;
  final List<String> tiles;
  final String? heroPersonId;
  final bool wordsBesidePictures;
  final bool speakEveryWord;
  final bool plainGreeting;
  final List<ChildPlace> places;
  final Map<String, bool> features;
  final Map<String, ({String band, String mode})> areas;
  final Map<String, bool> ladder;
  final bool birthdayVisible;

  bool hasTile(String k) => tiles.contains(k);

  Map<String, Object?> toJson() => <String, Object?>{
        'band': band,
        'home': <String, Object?>{
          'variant': homeVariant, 'tiles': tiles, 'heroPersonId': heroPersonId,
          'wordsBesidePictures': wordsBesidePictures, 'speakEveryWord': speakEveryWord, 'plainGreeting': plainGreeting,
        },
        'places': <Object?>[for (final ChildPlace p in places) p.toJson()],
        'features': features,
        'areas': <String, Object?>{
          for (final MapEntry<String, ({String band, String mode})> e in areas.entries)
            e.key: <String, Object?>{'band': e.value.band, 'mode': e.value.mode}
        },
        'ladder': ladder,
        'birthday': <String, Object?>{'visible': birthdayVisible},
      };
}

bool _suiteOn(Map<String, bool>? s, String k) => s == null || s[k] != false;
bool _hasGrant(List<String>? rungs, String g) => rungs != null && rungs.contains(g);

bool _isAway(Person p, String? today) {
  if (!p.isAwayFlag) return false;
  if (p.awayUntil != null && today != null && p.awayUntil!.compareTo(today) < 0) return false;
  return true;
}

List<String> childButtons(Person p) {
  final Set<String> c = p.contact.toSet();
  final List<String> out = <String>[];
  if (c.contains('supervised_visit')) {
    out.add('visit');
  } else if (c.contains('live_call')) {
    out.add('call');
  }
  if (c.contains('message')) out.add('chat');
  if (c.contains('postcard')) out.add('postcard');
  if (c.contains('voice_line')) out.add('voice');
  return out;
}

bool shownToChild(Person p) => p.label.trim().isNotEmpty && !backgroundRoles.contains(p.role);

ChildView deriveChildView(FamilyStructure structure, String ageBand, Map<String, bool>? suites,
    List<String>? rungs, {String? today}) {
  final String band = isAgeBand(ageBand) ? ageBand : 't34';
  final BandDef def = bandDef(band);
  final FamilyStructure s = structure;
  final Map<String, ({String band, String mode})> ar = <String, ({String band, String mode})>{};
  for (final String a in areas) {
    final String b = areaBand(s, a, band);
    ar[a] = (band: b, mode: bandDef(b).areaModes[a]!);
  }

  final List<Person> visible = s.people.where(shownToChild).toList();
  ChildPerson mk(Person p) => ChildPerson(p.id, p.label.trim(), childButtons(p), _isAway(p, today));
  final Set<String> homeIds = s.homes.map((Home h) => h.id).toSet();
  final List<ChildPlace> places = <ChildPlace>[];
  for (final Home h in s.homes) {
    final List<ChildPerson> ppl =
        visible.where((Person p) => p.homeId == h.id && !_isAway(p, today)).map(mk).toList();
    if (ppl.isNotEmpty) places.add(ChildPlace(h.id, h.name.trim(), 'home', ppl));
  }
  final List<ChildPerson> far = visible
      .where((Person p) => _isAway(p, today) || p.homeId == null || !homeIds.contains(p.homeId))
      .map(mk)
      .toList();
  if (far.isNotEmpty) places.add(ChildPlace('far', farPlaceName, 'far', far));

  ChildPerson? callable;
  for (final Person p in visible) {
    final ChildPerson c = mk(p);
    if (c.buttons.contains('call') || c.buttons.contains('visit')) {
      callable = c;
      break;
    }
  }
  final String? heroPersonId = _suiteOn(suites, 'calls') && callable != null ? callable.id : null;

  bool tileOk(String t) {
    switch (t) {
      case 'call': return heroPersonId != null;
      case 'stories': return _suiteOn(suites, 'stories');
      case 'colour': return true;
      case 'myDay': return ar['calendar']!.mode != 'none' && _suiteOn(suites, 'myDay');
      case 'play': return ar['games']!.mode != 'none' && _suiteOn(suites, 'games');
      case 'messages': return ar['chat']!.mode != 'none' && _suiteOn(suites, 'messages');
      case 'showTell': return _suiteOn(suites, 'showTell');
      case 'homework': return _suiteOn(suites, 'homework');
      case 'myList': return _hasGrant(rungs, 'own_list') || _suiteOn(suites, 'myList');
      case 'myPeople': return ar['people']!.mode == 'my_people' && places.isNotEmpty && _suiteOn(suites, 'myPeople');
      case 'more': return true;
    }
    return false;
  }

  final List<String> tiles = def.tiles.where(tileOk).toList();
  if (_hasGrant(rungs, 'own_list') && band != 't34' && !tiles.contains('myList')) {
    final int at = tiles.indexOf('homework') + 1;
    tiles.insert(at < tiles.length ? at : tiles.length, 'myList');
  }

  final bool young = band == 't34';
  final int sleepingHomes = s.homes.where((Home h) => h.childSleeps).length;
  final bool anyApart = visible.any((Person p) => _isAway(p, today));
  bool anyContact(String m) => visible.any((Person p) => p.contact.contains(m));
  final bool helpers = s.people.any((Person p) => p.role == 'foster_parent' || p.role == 'caseworker');
  final String readingBand = ar['reading']!.band;
  final Map<String, bool> features = <String, bool>{
    'twoSkies': !young && anyApart && _suiteOn(suites, 'twoSkies'),
    'pathHome': !young && anyApart && _suiteOn(suites, 'twoSkies'),
    'postcards': !young && (anyApart || anyContact('postcard')) && _suiteOn(suites, 'postcards'),
    'weeks': !young && sleepingHomes > 1 && _suiteOn(suites, 'weeks'),
    'packingBuddy': !young && sleepingHomes > 1 && _suiteOn(suites, 'weeks'),
    'myHelpers': !young && helpers,
    'voiceLine': !young && anyContact('voice_line'),
    'scheduledVisits': !young && s.people.any((Person p) => shownToChild(p) && p.contact.contains('supervised_visit')),
  };

  return ChildView(
    band: band,
    homeVariant: def.home,
    tiles: tiles,
    heroPersonId: young ? heroPersonId : null,
    wordsBesidePictures: readingBand == 't812' || readingBand == 't13',
    speakEveryWord: readingBand == 't34' || readingBand == 't57',
    plainGreeting: band == 't812' || band == 't13',
    places: young ? <ChildPlace>[] : places,
    features: features,
    areas: ar,
    ladder: <String, bool>{
      'ownList': _hasGrant(rungs, 'own_list'),
      'privateJournal': _hasGrant(rungs, 'journal_absolute'),
      'ownCalendar': _hasGrant(rungs, 'own_calendar'),
      'publishAvailability': _hasGrant(rungs, 'publish_availability'),
      'curateArchive': _hasGrant(rungs, 'curate_archive'),
      'ownExport': _hasGrant(rungs, 'own_export'),
      'everything': _hasGrant(rungs, 'everything'),
    },
    birthdayVisible: s.birthdayVisible && _suiteOn(suites, 'birthday'),
  );
}

// ================================================================= who =======
class FamilyPrincipal {
  const FamilyPrincipal({this.roleName, this.userId, this.childId});
  final Object? roleName;
  final Object? userId;
  final Object? childId;
}

bool canEditStructure(FamilyPrincipal? p) =>
    p != null && p.roleName == 'guardian' && p.userId is String && (p.userId! as String).isNotEmpty;

bool canReadReleased(FamilyPrincipal? p, Object? childId) =>
    p != null && p.roleName == 'child' && p.childId is String && (p.childId! as String).isNotEmpty && p.childId == childId;

// ============================================================== validation ===
final RegExp _idRe = RegExp(r'^[A-Za-z0-9_-]{1,64}$');
final RegExp _ctrlRe = RegExp('[\u0000-\u001f\u007f  ]');

bool isIsoDate(Object? x) {
  if (x is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(x)) return false;
  final List<int> p = x.split('-').map(int.parse).toList();
  final DateTime t = DateTime.utc(p[0], p[1], p[2]);
  return t.year == p[0] && t.month == p[1] && t.day == p[2];
}

int _dayNum(String iso) {
  final List<int> p = iso.split('-').map(int.parse).toList();
  return DateTime.utc(p[0], p[1], p[2]).millisecondsSinceEpoch ~/ 86400000;
}

int daysBetween(String a, String b) => _dayNum(b) - _dayNum(a);

/// The next day the rhythm hands her over (Wave 5, prototype g-schedule "Next exchange"): the first date on or
/// after [todayIso] that falls on the rhythm's exchange day, with the exchange time when one is set. This is a
/// fact about the weekly shape only. The rhythm carries no anchor week (who has her this week is not recorded), so
/// it never claims whose home she goes to, and it is null while there is no pattern or no exchange day.
class NextExchange {
  const NextExchange(this.date, this.dayIndex, this.time, this.daysAway);
  final String date;
  /// 0 = Sunday .. 6 = Saturday, the same numbering as [Rhythm.exchangeDay].
  final int dayIndex;
  final String? time;
  /// 0 means today. Guardian-side only: her own screens say "sleeps", never this.
  final int daysAway;
}

NextExchange? nextExchange(Rhythm r, String todayIso) {
  final int? d = r.exchangeDay;
  if (r.pattern == 'none' || d == null || !isIsoDate(todayIso)) return null;
  final List<int> p = todayIso.split('-').map(int.parse).toList();
  final DateTime t = DateTime.utc(p[0], p[1], p[2]);
  final int add = (d - (t.weekday % 7) + 7) % 7;
  final DateTime on = t.add(Duration(days: add));
  String two(int v) => v.toString().padLeft(2, '0');
  return NextExchange('${on.year.toString().padLeft(4, '0')}-${two(on.month)}-${two(on.day)}', d, r.exchangeTime, add);
}

class Verdict {
  const Verdict.ok() : reason = null;
  const Verdict.no(String this.reason);
  final String? reason;
  bool get ok => reason == null;
}

const Verdict _ok = Verdict.ok();
bool _isObj(Object? x) => x is Map<String, Object?>;

Verdict validatePerson(Object? p, List<Home> homes) {
  if (!_isObj(p)) return const Verdict.no('bad_person');
  final Map<String, Object?> m = p! as Map<String, Object?>;
  final Object? id = m['id'];
  if (id is! String || !_idRe.hasMatch(id)) return const Verdict.no('bad_id');
  final Object? label = m['label'];
  if (label is! String || label.length > maxLabel || _ctrlRe.hasMatch(label)) return const Verdict.no('bad_label');
  final Object? role = m['role'];
  if (role is! String || !roles.contains(role)) return const Verdict.no('bad_role');
  final Object? contact = m['contact'];
  if (contact is! List<Object?> ||
      contact.length > contactModes.length ||
      contact.any((Object? c) => c is! String || !contactModes.contains(c)) ||
      contact.toSet().length != contact.length) {
    return const Verdict.no('bad_contact');
  }
  final Object? homeId = m['homeId'];
  if (homeId != null && (homeId is! String || !homes.any((Home h) => h.id == homeId))) return const Verdict.no('unknown_home');
  final Object? away = m['away'];
  if (away != null) {
    if (!_isObj(away) || (away as Map<String, Object?>).keys.any((String k) => k != 'until')) return const Verdict.no('bad_away');
    final Object? until = away['until'];
    if (until != null && !isIsoDate(until)) return const Verdict.no('bad_away');
  }
  const Set<String> allowed = <String>{'id', 'label', 'role', 'homeId', 'contact', 'away'};
  if (m.keys.any((String k) => !allowed.contains(k))) return const Verdict.no('bad_person');
  return _ok;
}

Verdict validateHome(Object? h) {
  if (!_isObj(h)) return const Verdict.no('bad_home');
  final Map<String, Object?> m = h! as Map<String, Object?>;
  final Object? id = m['id'];
  if (id is! String || !_idRe.hasMatch(id)) return const Verdict.no('bad_id');
  final Object? name = m['name'];
  if (name is! String || name.trim().isEmpty || name.length > maxHomeName || _ctrlRe.hasMatch(name)) return const Verdict.no('bad_home');
  if (m['childSleeps'] is! bool) return const Verdict.no('bad_home');
  if (m.keys.any((String k) => k != 'id' && k != 'name' && k != 'childSleeps')) return const Verdict.no('bad_home');
  return _ok;
}

Verdict validateRhythm(Object? r) {
  if (!_isObj(r)) return const Verdict.no('bad_rhythm');
  final Map<String, Object?> m = r! as Map<String, Object?>;
  final Object? pat = m['pattern'];
  if (pat is! String || !patterns.contains(pat)) return const Verdict.no('bad_rhythm');
  final Object? d = m['exchangeDay'];
  if (d != null && !(d is int && d >= 0 && d <= 6)) return const Verdict.no('bad_rhythm');
  final Object? t = m['exchangeTime'];
  if (t != null && !(t is String && RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(t))) return const Verdict.no('bad_rhythm');
  if (m['source'] != 'guardian') return const Verdict.no('bad_rhythm');
  if (m.keys.any((String k) => !<String>{'pattern', 'exchangeDay', 'exchangeTime', 'source'}.contains(k))) {
    return const Verdict.no('bad_rhythm');
  }
  return _ok;
}

// ================================================================= changes ===
const List<String> opKinds = <String>[
  'put_person', 'remove_person', 'put_home', 'remove_home', 'set_rhythm', 'set_area_band',
  'set_birthday_visible', 'set_band_hold', 'release_band',
];
const List<String> nowOnlyOps = <String>['set_birthday_visible', 'set_band_hold', 'release_band'];
const Map<String, List<String>> _opFields = <String, List<String>>{
  'put_person': <String>['person'], 'remove_person': <String>['personId'], 'put_home': <String>['home'],
  'remove_home': <String>['homeId'], 'set_rhythm': <String>['rhythm'], 'set_area_band': <String>['area', 'band'],
  'set_birthday_visible': <String>['visible'], 'set_band_hold': <String>['hold'], 'release_band': <String>['band'],
};

class Timing {
  const Timing(this.kind, [this.on]);
  final String kind; // now | hold | date
  final String? on;
  static const Timing now = Timing('now');
  static const Timing hold = Timing('hold');
  Map<String, Object?> toJson() => on == null ? <String, Object?>{'kind': kind} : <String, Object?>{'kind': kind, 'on': on};
  static Timing fromJson(Map<String, Object?> j) => Timing(j['kind']! as String, j['on'] as String?);
}

class TimingResult {
  const TimingResult.ok(Timing this.timing) : reason = null;
  const TimingResult.no(String this.reason) : timing = null;
  final Timing? timing;
  final String? reason;
  bool get ok => timing != null;
}

TimingResult parseTiming(Object? raw, String today) {
  if (!_isObj(raw)) return const TimingResult.no('bad_timing');
  final Map<String, Object?> m = raw! as Map<String, Object?>;
  final Object? kind = m['kind'];
  if (kind == 'now' || kind == 'hold') {
    if (m.length != 1) return const TimingResult.no('bad_timing');
    return TimingResult.ok(Timing(kind! as String));
  }
  if (kind == 'date') {
    if (m.keys.any((String k) => k != 'kind' && k != 'on')) return const TimingResult.no('bad_timing');
    if (!isIsoDate(m['on']) || !isIsoDate(today)) return const TimingResult.no('bad_date');
    final int ahead = daysBetween(today, m['on']! as String);
    if (ahead < 1) return const TimingResult.no('date_not_future');
    if (ahead > maxDateAheadDays) return const TimingResult.no('date_too_far');
    return TimingResult.ok(Timing('date', m['on']! as String));
  }
  return const TimingResult.no('bad_timing');
}

String _opName(Map<String, Object?> op) => op['op']! as String;

bool isBigChange(Map<String, Object?> op) {
  switch (_opName(op)) {
    case 'set_rhythm':
    case 'remove_person':
    case 'remove_home':
      return true;
    case 'put_home':
      final Object? b = op['before'];
      return b == null ||
          (b as Map<String, Object?>)['childSleeps'] != (op['home']! as Map<String, Object?>)['childSleeps'];
    case 'put_person':
      final Object? b = op['before'];
      if (b == null) return true;
      final Map<String, Object?> bb = b as Map<String, Object?>;
      final Map<String, Object?> pp = op['person']! as Map<String, Object?>;
      return _jsonEq(bb['away'], pp['away']) == false || bb['homeId'] != pp['homeId'];
    default:
      return false;
  }
}

bool _jsonEq(Object? a, Object? b) {
  if (a == null || b == null) return a == b;
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final Object? k in a.keys) {
      if (!b.containsKey(k) || !_jsonEq(a[k], b[k])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (!_jsonEq(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

Timing defaultTiming(Map<String, Object?> op) {
  if (nowOnlyOps.contains(_opName(op))) return Timing.now;
  return isBigChange(op) ? Timing.hold : Timing.now;
}

Map<String, Object?> withBefore(FamilyStructure s, Map<String, Object?> op) {
  final Map<String, Object?> out = Map<String, Object?>.of(op);
  switch (_opName(op)) {
    case 'put_person':
      final String id = (op['person']! as Map<String, Object?>)['id']! as String;
      out['before'] = _personJson(s, id);
    case 'remove_person':
      out['before'] = _personJson(s, op['personId']! as String);
    case 'put_home':
      out['before'] = _homeJson(s, (op['home']! as Map<String, Object?>)['id']! as String);
    case 'remove_home':
      out['before'] = _homeJson(s, op['homeId']! as String);
    case 'set_rhythm':
      out['before'] = s.rhythm.toJson();
    case 'set_area_band':
      out['before'] = s.areaBands[op['area']! as String];
    case 'set_birthday_visible':
      out['before'] = s.birthdayVisible;
    case 'set_band_hold':
      out['before'] = s.holdBandChange;
    case 'release_band':
      out['before'] = s.releasedBand;
  }
  return out;
}

Map<String, Object?>? _personJson(FamilyStructure s, String id) {
  for (final Person p in s.people) {
    if (p.id == id) return p.toJson();
  }
  return null;
}

Map<String, Object?>? _homeJson(FamilyStructure s, String id) {
  for (final Home h in s.homes) {
    if (h.id == id) return h.toJson();
  }
  return null;
}

Verdict validateOp(FamilyStructure s, Object? op) {
  if (!_isObj(op)) return const Verdict.no('bad_op');
  final Map<String, Object?> m = op! as Map<String, Object?>;
  final Object? kind = m['op'];
  if (kind is! String || !opKinds.contains(kind)) return const Verdict.no('bad_op');
  final List<String> allowed = _opFields[kind] ?? const <String>[];
  if (m.keys.any((String k) => k != 'op' && k != 'before' && !allowed.contains(k))) return const Verdict.no('bad_op');
  switch (kind) {
    case 'put_person':
      final Verdict v = validatePerson(m['person'], s.homes);
      if (!v.ok) return v;
      final String id = (m['person']! as Map<String, Object?>)['id']! as String;
      if (!s.people.any((Person p) => p.id == id) && s.people.length >= maxPeople) return const Verdict.no('too_many_people');
      return _ok;
    case 'remove_person':
      return m['personId'] is String && s.people.any((Person p) => p.id == m['personId']) ? _ok : const Verdict.no('unknown_person');
    case 'put_home':
      final Verdict v = validateHome(m['home']);
      if (!v.ok) return v;
      final String id = (m['home']! as Map<String, Object?>)['id']! as String;
      if (!s.homes.any((Home h) => h.id == id) && s.homes.length >= maxHomes) return const Verdict.no('too_many_homes');
      return _ok;
    case 'remove_home':
      return m['homeId'] is String && s.homes.any((Home h) => h.id == m['homeId']) ? _ok : const Verdict.no('unknown_home');
    case 'set_rhythm':
      if (s.rhythm.source == 'court_order') return const Verdict.no('locked_by_order');
      return validateRhythm(m['rhythm']);
    case 'set_area_band':
      if (!isArea(m['area'])) return const Verdict.no('bad_area');
      return m['band'] == null || isAgeBand(m['band']) ? _ok : const Verdict.no('bad_band');
    case 'set_birthday_visible':
      return m['visible'] is bool ? _ok : const Verdict.no('bad_op');
    case 'set_band_hold':
      return m['hold'] is bool ? _ok : const Verdict.no('bad_op');
    case 'release_band':
      return isAgeBand(m['band']) ? _ok : const Verdict.no('bad_band');
  }
  return const Verdict.no('bad_op');
}

TimingResult validateChange(FamilyStructure s, Object? op, Object? timing, String today) {
  final Verdict v = validateOp(s, op);
  if (!v.ok) return TimingResult.no(v.reason!);
  final TimingResult t = parseTiming(timing, today);
  if (!t.ok) return t;
  if (nowOnlyOps.contains((op! as Map<String, Object?>)['op']) && t.timing!.kind != 'now') {
    return const TimingResult.no('settings_now_only');
  }
  return t;
}

FamilyStructure applyOp(FamilyStructure s, Map<String, Object?> op) {
  List<Home> homes = List<Home>.of(s.homes);
  List<Person> people = List<Person>.of(s.people);
  Rhythm rhythm = s.rhythm;
  final Map<String, String> bands = Map<String, String>.of(s.areaBands);
  bool bv = s.birthdayVisible, hold = s.holdBandChange;
  String? released = s.releasedBand;
  switch (_opName(op)) {
    case 'put_person':
      final Person p = Person.fromJson(op['person']! as Map<String, Object?>);
      final int i = people.indexWhere((Person x) => x.id == p.id);
      if (i >= 0) {
        people[i] = p;
      } else {
        people.add(p);
      }
    case 'remove_person':
      people = people.where((Person p) => p.id != op['personId']).toList();
    case 'put_home':
      final Home h = Home.fromJson(op['home']! as Map<String, Object?>);
      final int i = homes.indexWhere((Home x) => x.id == h.id);
      if (i >= 0) {
        homes[i] = h;
      } else {
        homes.add(h);
      }
    case 'remove_home':
      homes = homes.where((Home h) => h.id != op['homeId']).toList();
      people = <Person>[
        for (final Person p in people) p.homeId == op['homeId'] ? p.copyWith(clearHome: true) : p
      ];
    case 'set_rhythm':
      if (rhythm.source != 'court_order') rhythm = Rhythm.fromJson(op['rhythm']! as Map<String, Object?>);
    case 'set_area_band':
      if (op['band'] == null) {
        bands.remove(op['area']);
      } else {
        bands[op['area']! as String] = op['band']! as String;
      }
    case 'set_birthday_visible':
      bv = op['visible']! as bool;
    case 'set_band_hold':
      hold = op['hold']! as bool;
    case 'release_band':
      released = op['band']! as String;
  }
  return FamilyStructure(
      homes: homes, people: people, rhythm: rhythm, areaBands: bands, birthdayVisible: bv,
      holdBandChange: hold, releasedBand: released);
}

Map<String, Object?> invertOp(Map<String, Object?> op, FamilyStructure current) {
  final Object? before = op['before'];
  Map<String, Object?> inv;
  switch (_opName(op)) {
    case 'put_person':
      inv = before != null
          ? <String, Object?>{'op': 'put_person', 'person': before, 'before': null}
          : <String, Object?>{'op': 'remove_person', 'personId': (op['person']! as Map<String, Object?>)['id'], 'before': null};
    case 'remove_person':
      inv = before != null
          ? <String, Object?>{'op': 'put_person', 'person': before, 'before': null}
          : <String, Object?>{'op': 'remove_person', 'personId': op['personId'], 'before': null};
    case 'put_home':
      inv = before != null
          ? <String, Object?>{'op': 'put_home', 'home': before, 'before': null}
          : <String, Object?>{'op': 'remove_home', 'homeId': (op['home']! as Map<String, Object?>)['id'], 'before': null};
    case 'remove_home':
      inv = before != null
          ? <String, Object?>{'op': 'put_home', 'home': before, 'before': null}
          : <String, Object?>{'op': 'remove_home', 'homeId': op['homeId'], 'before': null};
    case 'set_rhythm':
      inv = <String, Object?>{'op': 'set_rhythm', 'rhythm': before ?? const Rhythm().toJson(), 'before': null};
    case 'set_area_band':
      inv = <String, Object?>{'op': 'set_area_band', 'area': op['area'], 'band': before, 'before': null};
    case 'set_birthday_visible':
      inv = <String, Object?>{'op': 'set_birthday_visible', 'visible': before ?? true, 'before': null};
    case 'set_band_hold':
      inv = <String, Object?>{'op': 'set_band_hold', 'hold': before ?? true, 'before': null};
    default:
      inv = <String, Object?>{'op': 'release_band', 'band': before ?? op['band'], 'before': null};
  }
  return withBefore(current, inv);
}

// ============================================================= the history ===
class HistoryEntry {
  const HistoryEntry.change({required this.id, required this.seq, required Map<String, Object?> this.op, required Timing this.timing})
      : entry = 'change', ref = null;
  const HistoryEntry.release({required this.id, required this.seq, required String this.ref})
      : entry = 'release', op = null, timing = null;
  final String entry;
  final String id;
  final int seq;
  final Map<String, Object?>? op;
  final Timing? timing;
  final String? ref;

  static HistoryEntry fromJson(Map<String, Object?> j) => j['entry'] == 'release'
      ? HistoryEntry.release(id: j['id']! as String, seq: (j['seq']! as num).toInt(), ref: j['ref']! as String)
      : HistoryEntry.change(
          id: j['id']! as String, seq: (j['seq']! as num).toInt(), op: j['op']! as Map<String, Object?>,
          timing: Timing.fromJson(j['timing']! as Map<String, Object?>));

  Map<String, Object?> toJson() => entry == 'release'
      ? <String, Object?>{'entry': 'release', 'id': id, 'seq': seq, 'ref': ref}
      : <String, Object?>{'entry': 'change', 'id': id, 'seq': seq, 'op': op, 'timing': timing!.toJson()};
}

Set<String> releasedIds(List<HistoryEntry> entries, String today) {
  final Set<String> released = <String>{
    for (final HistoryEntry e in entries) if (e.entry == 'release') e.ref!
  };
  final Set<String> out = <String>{};
  for (final HistoryEntry e in entries) {
    if (e.entry != 'change') continue;
    final Timing t = e.timing!;
    if (t.kind == 'now') {
      out.add(e.id);
    } else if (t.kind == 'date') {
      if (isIsoDate(t.on) && isIsoDate(today) && t.on!.compareTo(today) <= 0) out.add(e.id);
    } else if (released.contains(e.id)) {
      out.add(e.id);
    }
  }
  return out;
}

List<HistoryEntry> _bySeq(List<HistoryEntry> es) => List<HistoryEntry>.of(es)..sort((HistoryEntry a, HistoryEntry b) => a.seq.compareTo(b.seq));

FamilyStructure foldIntended(FamilyStructure base, List<HistoryEntry> entries) {
  FamilyStructure s = base;
  for (final HistoryEntry e in _bySeq(entries)) {
    if (e.entry == 'change') s = applyOp(s, e.op!);
  }
  return s;
}

FamilyStructure foldReleased(FamilyStructure base, List<HistoryEntry> entries, String today) {
  final Set<String> ids = releasedIds(entries, today);
  FamilyStructure s = base;
  for (final HistoryEntry e in _bySeq(entries)) {
    if (e.entry == 'change' && ids.contains(e.id)) s = applyOp(s, e.op!);
  }
  return s;
}

List<HistoryEntry> pendingChanges(List<HistoryEntry> entries, String today) {
  final Set<String> ids = releasedIds(entries, today);
  return entries.where((HistoryEntry e) => e.entry == 'change' && !ids.contains(e.id)).toList();
}

Map<String, Object?> previewChange(FamilyStructure released, Map<String, Object?> op, Timing timing, String band,
    Map<String, bool>? suites, List<String> rungs, String today) {
  final ChildView before = deriveChildView(released, band, suites, rungs, today: today);
  final Map<String, Object?> full = withBefore(released, op);
  final ChildView after = deriveChildView(applyOp(released, full), band, suites, rungs, today: today);
  return <String, Object?>{
    'before': before.toJson(),
    'after': after.toJson(),
    'differs': !_jsonEq(before.toJson(), after.toJson()),
    'big': isBigChange(full),
    'recommended': defaultTiming(full).toJson(),
    'reaches': timing.kind == 'now' ? 'now' : timing.kind == 'hold' ? 'when_told' : 'on_date',
  };
}

// ================================================================= stories ===
Verdict validateStory(Object? story) {
  if (!_isObj(story) || (story! as Map<String, Object?>).keys.any((String k) => k != 'pages')) return const Verdict.no('bad_story');
  final Object? pages = (story as Map<String, Object?>)['pages'];
  if (pages is! List<Object?> || pages.isEmpty || pages.length > maxStoryPages) return const Verdict.no('bad_story');
  for (final Object? p in pages) {
    if (p is! String || p.trim().isEmpty || p.length > maxStoryPageChars || _ctrlRe.hasMatch(p.replaceAll('\n', ' '))) {
      return const Verdict.no('bad_story');
    }
  }
  return _ok;
}

// ================================================================ birthday ===
class BirthdayInfo {
  const BirthdayInfo({
    required this.yearsOld, required this.nextOn, required this.sleepsUntil, required this.turnsYears,
    required this.bandNow, required this.bandAtBirthday, required this.bandChanges,
  });
  final int yearsOld;
  final String nextOn;
  final int sleepsUntil;
  final int turnsYears;
  final String bandNow;
  final String bandAtBirthday;
  final bool bandChanges;
  Map<String, Object?> toJson() => <String, Object?>{
        'yearsOld': yearsOld, 'nextOn': nextOn, 'sleepsUntil': sleepsUntil, 'turnsYears': turnsYears,
        'bandNow': bandNow, 'bandAtBirthday': bandAtBirthday, 'bandChanges': bandChanges,
      };
}

String _birthdayIn(int year, int month, int day) {
  final bool leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;
  final bool shift = month == 2 && day == 29 && !leap;
  final int m = shift ? 3 : month;
  final int d = shift ? 1 : day;
  return '${year.toString().padLeft(4, '0')}-${m.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
}

BirthdayInfo? birthdayInfo(Object? birthDate, Object? today) {
  if (!isIsoDate(birthDate) || !isIsoDate(today) || (birthDate! as String).compareTo(today! as String) > 0) return null;
  final List<int> b = (birthDate as String).split('-').map(int.parse).toList();
  final String t = today as String;
  final int ty = int.parse(t.substring(0, 4));
  String next = _birthdayIn(ty, b[1], b[2]);
  if (next.compareTo(t) < 0) next = _birthdayIn(ty + 1, b[1], b[2]);
  final int nextYear = int.parse(next.substring(0, 4));
  final int sleeps = daysBetween(t, next);
  final int turns = nextYear - b[0];
  final int years = sleeps == 0 ? turns : turns - 1;
  final String bandNow = bandForYears(years);
  final String bandAt = bandForYears(turns);
  return BirthdayInfo(
      yearsOld: years, nextOn: next, sleepsUntil: sleeps, turnsYears: turns, bandNow: bandNow,
      bandAtBirthday: bandAt, bandChanges: bandNow != bandAt && sleeps > 0);
}

bool birthdayLineShown(int sleepsUntil, bool visible) => visible && sleepsUntil >= 0 && sleepsUntil <= 7;

Map<String, Object?> birthdayPreview(BirthdayInfo info, bool hold, String? released) {
  final String stays = effectiveBand(info.bandAtBirthday, hold, released ?? info.bandNow);
  return <String, Object?>{
    'sleepsUntil': info.sleepsUntil,
    'turnsYears': info.turnsYears,
    'bandChanges': info.bandChanges,
    'herBandAfter': info.bandAtBirthday,
    'herHomeAfter': stays,
    'heldAtBirthday': info.bandChanges && stays != info.bandAtBirthday,
    'changes': info.bandChanges ? diffBands(info.bandNow, info.bandAtBirthday) : <Object?>[],
  };
}
