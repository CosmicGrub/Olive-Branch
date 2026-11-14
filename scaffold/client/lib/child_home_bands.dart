// OLIVE BRANCH — the per-age child homes, as DATA. No longer UNVERIFIED — verified by CI
// (client/test/child_home_bands_test.dart, which asserts every table here equal to
// test/parity/vectors/child_home_bands.json, generated from the live prototype by
// tools/gen-child-home-vectors.mjs and drift-guarded by tools/test/child_home_vectors.test.mjs).
//
// This is the Flutter twin of mod-child.js's TL (tile registry), BANDSET (which tiles each band's home
// carries), MORE (the More page per band) and GROW ('your home grows' pages). Prototype tile ids are kept
// ('msgs', 'showtell', 'people', ...), so a row in docs/superpowers/parity/matrix.json names the same id here.
//
// Pure Dart, no widgets: child_home_bands_ui.dart draws it. Offline by construction: nothing here
// reads a server, a clock or a store.
//
// RULES in this file (all from the prototype, all tested):
//   - A band's home draws exactly its layout (kHomeLayout): a hero or a strip, a Featured grid, a Standard grid.
//   - A tile only appears if its destination exists in this client ([kTilesWithDestination]) and a
//     guardian has not hidden it. MESSAGES IS NEVER HIDEABLE ([tileHideable]).
//   - The renames per band come from the registry: Play together is Games at 8-12 and Downtime at 13-17;
//     Draw & colour and Colour are Studio at 13-17; My day is Today at 13-17.
//   - The More page lists the band's MORE ids, minus Play under 14, minus Birthday without a birthday on
//     file or from 11, then cut to [kMoreLimit].
//   - A child sees no counts, scores, streaks, rewards or trophies (P1-P11): nothing here can carry one.

/// One entry of the tile registry.
class BandTile {
  const BandTile(this.id, this.title, this.sub, this.icon, {this.alt = const <String, String>{}});
  final String id;

  /// The title for every band without an entry in [alt].
  final String title;

  /// The line under the title on a Featured tile (empty = none).
  final String sub;

  /// The prototype's icon name (child_home_bands_ui.dart maps it to an IconData).
  final String icon;

  /// Renamed per band: band id -> title.
  final Map<String, String> alt;
}

/// One line of a 'your home grows' page: kind is 'add' (new), 'keep' (still here) or 'hers' (hers alone).
class GrowItem {
  const GrowItem(this.kind, this.title, this.body);
  final String kind;
  final String title;
  final String body;
}

class GrowPage {
  const GrowPage({
    required this.eyebrow, required this.lead, required this.items, required this.dest, required this.cta,
    this.scene, this.say, this.teen = false, this.quiet = false,
  });
  final String eyebrow;
  final String lead;
  final List<GrowItem> items;

  /// The prototype screen the button opens ('k.day', 'k.weeks', 'k.list', ...).
  final String dest;
  final String cta;
  final String? scene;
  final String? say;

  /// 13 and over: plainer, and she is told nobody else is told she saw it.
  final bool teen;

  /// A quiet page (age 10): a sentence, no picture.
  final bool quiet;
}

// ============================================================== registry ===
// Generated from mod-child.js (see the header). Edit the prototype, regenerate the vector, then this.
const Map<String, BandTile> kBandTiles = <String, BandTile>{
  'people': BandTile('people', 'My people', 'Calls and messages', 'users'),
  'stories': BandTile('stories', 'Stories', 'Look and listen', 'book'),
  'colour': BandTile('colour', 'Colour', 'My colour today', 'palette', alt: <String, String>{'t1317': 'Studio'}),
  'day': BandTile('day', 'My day', 'What comes next', 'calendar', alt: <String, String>{'t1317': 'Today'}),
  'play': BandTile('play', 'Play together', 'Games', 'dice', alt: <String, String>{'t812': 'Games', 't1317': 'Downtime'}),
  'msgs': BandTile('msgs', 'Messages', '', 'chat'),
  'showtell': BandTile('showtell', 'Show & tell', 'Share a picture', 'camera'),
  'more': BandTile('more', 'More', '', 'more'),
  'list': BandTile('list', 'My list', 'Things I need and want', 'list'),
  'weeks': BandTile('weeks', 'My weeks', 'Where I sleep', 'calendar'),
  'journal': BandTile('journal', 'Journal', 'Just for me', 'pencil'),
  'feel': BandTile('feel', 'Feelings', 'When I need someone', 'smile'),
  'memory': BandTile('memory', 'Memory box', 'Things I keep', 'heart'),
  'capsule': BandTile('capsule', 'Time capsule', 'Opens later', 'hourglass'),
  'growth': BandTile('growth', 'Growing marks', 'On the door', 'leaf'),
  'jokes': BandTile('jokes', 'Jokebook', 'Make me laugh', 'smile'),
  'draw': BandTile('draw', 'Draw & colour', 'Pictures I make', 'brush', alt: <String, String>{'t1317': 'Studio'}),
  'storyteller': BandTile('storyteller', 'Storyteller', 'Stories read to me', 'mic'),
  'birthday': BandTile('birthday', 'My birthday', '', 'sparkle'),
  'cal': BandTile('cal', 'My calendar', 'Mine to fill in', 'calendar'),
  'privacy': BandTile('privacy', 'Privacy', 'What my parents can see', 'shield'),
  'ladder': BandTile('ladder', 'What is mine', 'As I grow', 'key'),
  'symbols': BandTile('symbols', 'Symbols', 'Tap to talk', 'hand'),
  'pictures': BandTile('pictures', 'My saved pictures', '', 'image'),
  'helpers': BandTile('helpers', 'My helpers', 'People who help', 'shield'),
  'routine': BandTile('routine', 'My routine', 'First, then', 'check'),
  'grownup': BandTile('grownup', 'Grown-up things', '', 'lock'),
  'shelf': BandTile('shelf', 'My things', 'From my grown-ups', 'layers'),
};

const Map<String, List<String>> kBandSet = <String, List<String>>{
  't34': <String>['people', 'stories', 'colour'],
  't57': <String>['day', 'play', 'msgs', 'stories', 'showtell', 'people', 'colour', 'more'],
  't812': <String>['msgs', 'play', 'list', 'storyteller', 'weeks', 'showtell', 'people', 'journal', 'more'],
  't1317': <String>['msgs', 'cal', 'journal', 'draw', 'people', 'play', 'ladder', 'privacy', 'more'],
};

const Map<String, List<String>> kMoreSet = <String, List<String>>{
  't57': <String>['draw', 'memory', 'feel', 'growth', 'birthday', 'shelf', 'jokes'],
  't812': <String>['journal', 'feel', 'memory', 'capsule', 'growth', 'birthday', 'shelf', 'jokes', 'draw'],
  't1317': <String>['play', 'draw', 'memory', 'capsule', 'shelf', 'jokes', 'privacy', 'ladder'],
};

const List<int> kGrowKeys = <int>[5, 8, 10, 13, 14, 15, 16, 17, 18];

const Map<int, GrowPage> kGrowPages = <int, GrowPage>{
  5: GrowPage(
      eyebrow: 'You are 5', lead: 'Your home is growing with you.', dest: 'k.day', cta: 'Show me', scene: 'day', say: 'You are five. Your home is growing with you.',
      items: <GrowItem>[GrowItem('add', 'Your day', 'See what comes next, in pictures.'), GrowItem('add', 'Words with your pictures', 'Every picture has a word too.'), GrowItem('keep', 'Calling, stories and colour', 'Right where they were.')]),
  8: GrowPage(
      eyebrow: 'You are 8', lead: 'Your home is growing with you.', dest: 'k.weeks', cta: 'Show me', scene: 'day', say: 'You are eight. Your home is growing with you.',
      items: <GrowItem>[GrowItem('add', 'Your weeks', 'See where you sleep, week by week.'), GrowItem('add', 'Your own list', 'Things you need and things you want.'), GrowItem('add', 'A quiet journal', 'Just for you.'), GrowItem('keep', 'Calling, stories, show and tell', 'Right where they were.')]),
  10: GrowPage(
      eyebrow: 'You are 10', lead: 'Your list is yours.', dest: 'k.list', cta: 'Open my list', say: 'Your list is yours now.', quiet: true,
      items: <GrowItem>[GrowItem('hers', 'Yours now', 'Nobody checks it first. Nobody changes it. You decide what goes on it.')]),
  13: GrowPage(
      eyebrow: 'You are 13', lead: 'You are 13. A few things are different now.', dest: 'k.privacy', cta: 'Take a look', teen: true,
      items: <GrowItem>[GrowItem('hers', 'Your journal is locked', 'Only you can open it.'), GrowItem('add', 'A different look', 'Calmer and plainer, with your own messages and calendar.'), GrowItem('add', 'What your parents can see', 'A short list. It is the same for them as it is for you.')]),
  14: GrowPage(
      eyebrow: 'You are 14', lead: 'This calendar is yours now.', dest: 'k.cal', cta: 'Open my calendar', teen: true,
      items: <GrowItem>[GrowItem('hers', 'Add anything', 'You choose whether anyone else sees it.'), GrowItem('keep', 'Games', 'They moved to More. Nothing was taken away.')]),
  15: GrowPage(
      eyebrow: 'You are 15', lead: 'You decide when you are free.', dest: 'k.free', cta: 'Set my times', teen: true,
      items: <GrowItem>[GrowItem('hers', 'Your free times', 'Set them. You see what Mom and Dad will see.'), GrowItem('keep', 'Calls', 'A call is always one tap.')]),
  16: GrowPage(
      eyebrow: 'You are 16', lead: 'The archive is yours to shape.', dest: 'k.archive', cta: 'Look at it', teen: true,
      items: <GrowItem>[GrowItem('hers', 'Hide what you want', 'Nothing is deleted. Nobody is told what you hide.')]),
  17: GrowPage(
      eyebrow: 'You are 17', lead: 'You can take a copy of your data.', dest: 'k.copy', cta: 'Make my copy', teen: true,
      items: <GrowItem>[GrowItem('hers', 'A copy that is yours', 'No one has to say yes. Nobody is told you made it.')]),
  18: GrowPage(
      eyebrow: 'You are 18', lead: 'This is your own space now.', dest: 'k.handover', cta: 'See my choices', teen: true,
      items: <GrowItem>[GrowItem('hers', 'Everything is yours', 'Guardianship has closed. You choose what happens next.')]),
};

// ================================================================ layout ===

/// Where the layout of each band's home puts each tile.
class HomeLayout {
  const HomeLayout({
    this.hero = const <String>[], this.strip = const <String>[], this.featured = const <String>[],
    this.standard = const <String>[], this.standardColumns = 3,
  });
  final List<String> hero;
  final List<String> strip;
  final List<String> featured;
  final List<String> standard;

  /// How many Standard tiles sit in a row on a wide screen (the prototype's 3-up and 4-up).
  final int standardColumns;

  List<String> get all => <String>[...hero, ...strip, ...featured, ...standard];
}

/// The four homes. t34 is AgeHome34 (family_structure_screens.dart) and t1317 is wave 2b, both listed here so
/// the vector covers every band; [kBandsDrawnHere] says which ones child_home_bands_ui.dart draws.
const Map<String, HomeLayout> kHomeLayout = <String, HomeLayout>{
  't34': HomeLayout(standard: <String>['people', 'stories', 'colour']),
  't57': HomeLayout(
    hero: <String>['day'], featured: <String>['play', 'msgs', 'stories', 'showtell'],
    standard: <String>['people', 'colour', 'more']),
  't812': HomeLayout(
    strip: <String>['weeks'], featured: <String>['msgs', 'play', 'list', 'storyteller'],
    standard: <String>['people', 'showtell', 'journal', 'more'], standardColumns: 4),
  't1317': HomeLayout(
    featured: <String>['msgs', 'cal'], standard: <String>['journal', 'draw', 'people', 'ladder', 'privacy', 'more']),
};

/// The bands whose home this client draws from the table (2a). t34 keeps AgeHome34; t1317 is wave 2b.
const Set<String> kBandsDrawnHere = <String>{'t57', 't812'};

/// The tiles whose destination exists in this client today. A tile without one never appears (it would be a
/// dead end). Wave 6 adds cal and privacy; the grown-up door is a separate row; Feelings and My things have
/// no screen of their own yet.
const Set<String> kTilesWithDestination = <String>{
  'people', 'stories', 'colour', 'day', 'play', 'msgs', 'showtell', 'more', 'list', 'weeks', 'journal',
  'memory', 'capsule', 'growth', 'jokes', 'draw', 'storyteller', 'birthday', 'ladder', 'feel',
};

/// The prototype's tile id -> the key the family structure's ChildView.tiles uses (family_structure_logic).
/// A tile with no entry is not governed by a suite switch.
const Map<String, String> kTileViewKey = <String, String>{
  'day': 'myDay', 'play': 'play', 'msgs': 'messages', 'stories': 'stories', 'storyteller': 'stories',
  'showtell': 'showTell', 'people': 'myPeople', 'list': 'myList', 'more': 'more',
};

/// The guardian's hide switch (activity_overrides.dart 'tile:*' keys) for each tile a guardian may hide.
const Map<String, String> kTileOverrideKey = <String, String>{
  'stories': 'tile:storyteller', 'storyteller': 'tile:storyteller', 'showtell': 'tile:showAndTell',
  'list': 'tile:myList', 'more': 'tile:more',
};

/// Messages is never hideable, by any switch, in any band.
bool tileHideable(String id) => id != 'msgs';

/// Her band for the home, in the prototype's four bands. The client's own 't13' (13 and up) is the
/// prototype's t1317; this client has no 18 handover band yet (wave 2b decides).
String protoBand(String clientBand) => clientBand == 't13' ? 't1317' : clientBand;

/// The band's layout for her age: at 13 the Downtime (Play) tile shows in the Standard row and from 14 it
/// has moved to More (the prototype's `if(a<14)std.unshift('play')`).
HomeLayout homeLayoutFor(String band, {int age = 0}) {
  final HomeLayout base = kHomeLayout[band] ?? kHomeLayout['t57']!;
  if (band != 't1317') return base;
  return HomeLayout(
    featured: base.featured,
    standard: <String>[if (age < 14) 'play', ...base.standard],
    standardColumns: base.standardColumns,
  );
}

/// The title of a tile on a band's home: the registry's, renamed for the band.
String bandTileTitle(String id, String band) {
  final BandTile? t = kBandTiles[id];
  if (t == null) return id;
  return t.alt[band] ?? t.title;
}

/// The More page: the band's list, filtered, cut to [kMoreLimit].
const Map<String, int> kMoreLimit = <String, int>{'t57': 6, 't812': 7, 't1317': 7};

List<String> moreIdsFor(String band, int age,
    {required bool hasBirthday, required bool shelfOn, Set<String> hidden = const <String>{}}) {
  final List<String> src = kMoreSet[band] ?? kMoreSet['t57']!;
  final List<String> ids = <String>[
    for (final String i in src)
      if (!(i == 'play' && age < 14) &&
          !(i == 'shelf' && !shelfOn) &&
          !(i == 'birthday' && (!hasBirthday || age >= 11)) &&
          !(hidden.contains(i) && tileHideable(i)))
        i,
  ];
  final int limit = kMoreLimit[band] ?? 7;
  return ids.length > limit ? ids.sublist(0, limit) : ids;
}

/// What a band's home actually draws: its layout, minus tiles with no destination here, minus what a
/// guardian hid, minus what the family structure switched off ([viewTiles] null = no family structure).
List<String> visibleHomeIds(String band, int age, {List<String>? viewTiles, Set<String> hidden = const <String>{}}) {
  return <String>[
    for (final String id in homeLayoutFor(band, age: age).all)
      if (kTilesWithDestination.contains(id) &&
          !(hidden.contains(id) && tileHideable(id)) &&
          (viewTiles == null || kTileViewKey[id] == null || viewTiles.contains(kTileViewKey[id])))
        id,
  ];
}
