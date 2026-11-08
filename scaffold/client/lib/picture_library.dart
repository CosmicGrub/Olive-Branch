// OLIVE BRANCH — the picture library for suites B (Rhythm) and C (Voice).
// No longer UNVERIFIED — verified by CI (client/test/picture_library_test.dart).
//
// Pure data, no Flutter import. Every Rhythm and Voice surface is
// PICTURE-FIRST (she is five going on six: a non-reader to an early reader), so
// a step, a bag item, a room, a helper, a worry, a weather or a symbol is an id
// into THIS table, and the id carries the plain spoken name read aloud for it.
// The matching drawing for each id lives in picture_icons.dart (Material icons
// for now: a commissioned, diverse picture set is an open owner decision).
//
// Names are plain nouns and verbs. Nothing here names a feeling as good or bad,
// and the weather pictures are WEATHER, not moods: "Stormy" is a sky, never a
// verdict on her. A test holds both lines.
library;

enum PictureGroup { routine, thing, room, person, worry, weather, symbolCore, symbolExtra }

class PictureDef {
  const PictureDef(this.id, this.label, this.group);
  final String id;

  /// What is spoken (and shown beside the picture where words are shown).
  final String label;
  final PictureGroup group;
}

const List<PictureDef> pictureLibrary = <PictureDef>[
  // ---- routine steps (one routine, the first-then board) ----
  PictureDef('wake-up', 'Wake up', PictureGroup.routine),
  PictureDef('breakfast', 'Breakfast', PictureGroup.routine),
  PictureDef('get-dressed', 'Get dressed', PictureGroup.routine),
  PictureDef('teeth', 'Brush teeth', PictureGroup.routine),
  PictureDef('shoes', 'Shoes on', PictureGroup.routine),
  PictureDef('coat', 'Coat on', PictureGroup.routine),
  PictureDef('bag', 'Get my bag', PictureGroup.routine),
  PictureDef('bath', 'Bath', PictureGroup.routine),
  PictureDef('pyjamas', 'Pyjamas', PictureGroup.routine),
  PictureDef('book', 'A book', PictureGroup.routine),
  PictureDef('song', 'A song', PictureGroup.routine),
  PictureDef('cuddle', 'A cuddle', PictureGroup.routine),
  PictureDef('lights-out', 'Lights out', PictureGroup.routine),
  PictureDef('tidy', 'Tidy up', PictureGroup.routine),
  PictureDef('wash-hands', 'Wash hands', PictureGroup.routine),
  PictureDef('snack', 'A snack', PictureGroup.routine),
  PictureDef('drink', 'A drink', PictureGroup.routine),
  PictureDef('toilet', 'Toilet', PictureGroup.routine),
  PictureDef('car', 'Car ride', PictureGroup.routine),
  PictureDef('play', 'Play', PictureGroup.routine),
  // ---- things for the bag ----
  PictureDef('owl', 'Owl', PictureGroup.thing),
  PictureDef('teddy', 'Teddy', PictureGroup.thing),
  PictureDef('blanket', 'Blanket', PictureGroup.thing),
  PictureDef('night-light', 'Night-light', PictureGroup.thing),
  PictureDef('boots', 'Rain boots', PictureGroup.thing),
  PictureDef('lunch', 'Lunch box', PictureGroup.thing),
  PictureDef('bottle', 'Water bottle', PictureGroup.thing),
  PictureDef('toothbrush', 'Toothbrush', PictureGroup.thing),
  PictureDef('library-book', 'Library book', PictureGroup.thing),
  PictureDef('glasses', 'Glasses', PictureGroup.thing),
  // ---- rooms (a new place; rooms only, never an address) ----
  PictureDef('door', 'The front door', PictureGroup.room),
  PictureDef('hall', 'The hall', PictureGroup.room),
  PictureDef('my-room', 'Your room', PictureGroup.room),
  PictureDef('bed', 'The bed', PictureGroup.room),
  PictureDef('window', 'The window', PictureGroup.room),
  PictureDef('kitchen', 'The kitchen', PictureGroup.room),
  PictureDef('bathroom', 'The bathroom', PictureGroup.room),
  PictureDef('garden', 'The garden', PictureGroup.room),
  // ---- grown-ups she can go to ----
  PictureDef('grandparent', 'Grandparent', PictureGroup.person),
  PictureDef('aunt-uncle', 'Aunt or uncle', PictureGroup.person),
  PictureDef('teacher', 'Teacher', PictureGroup.person),
  PictureDef('friend', 'Family friend', PictureGroup.person),
  PictureDef('neighbour', 'Neighbour', PictureGroup.person),
  PictureDef('counsellor', 'Counsellor', PictureGroup.person),
  PictureDef('sibling', 'Brother or sister', PictureGroup.person),
  PictureDef('grown-up', 'Grown-up', PictureGroup.person),
  // ---- worry pictures (things, not feelings; chosen by her) ----
  PictureDef('worry-dark', 'The dark', PictureGroup.worry),
  PictureDef('worry-noise', 'A loud noise', PictureGroup.worry),
  PictureDef('worry-apart', 'Being apart', PictureGroup.worry),
  PictureDef('worry-new-place', 'A new place', PictureGroup.worry),
  PictureDef('worry-tummy', 'A tummy ache', PictureGroup.worry),
  PictureDef('worry-storm', 'A big storm', PictureGroup.worry),
  PictureDef('worry-school', 'Something at school', PictureGroup.worry),
  PictureDef('worry-dream', 'A dream', PictureGroup.worry),
  PictureDef('worry-other', 'Something else', PictureGroup.worry),
  // ---- weather (how today feels, as a sky) ----
  PictureDef('sunny', 'Sunny', PictureGroup.weather),
  PictureDef('cloudy', 'Cloudy', PictureGroup.weather),
  PictureDef('rainy', 'Rainy', PictureGroup.weather),
  PictureDef('stormy', 'Stormy', PictureGroup.weather),
  PictureDef('windy', 'Windy', PictureGroup.weather),
  PictureDef('foggy', 'Foggy', PictureGroup.weather),
  // ---- symbols: core words (always on the board) ----
  PictureDef('sym-i', 'I', PictureGroup.symbolCore),
  PictureDef('sym-want', 'want', PictureGroup.symbolCore),
  PictureDef('sym-more', 'more', PictureGroup.symbolCore),
  PictureDef('sym-stop', 'stop', PictureGroup.symbolCore),
  PictureDef('sym-help', 'help', PictureGroup.symbolCore),
  PictureDef('sym-hurt', 'hurt', PictureGroup.symbolCore),
  PictureDef('sym-tired', 'tired', PictureGroup.symbolCore),
  PictureDef('sym-play', 'play', PictureGroup.symbolCore),
  PictureDef('sym-yes', 'yes', PictureGroup.symbolCore),
  PictureDef('sym-no', 'no', PictureGroup.symbolCore),
  PictureDef('sym-eat', 'eat', PictureGroup.symbolCore),
  PictureDef('sym-drink', 'drink', PictureGroup.symbolCore),
  PictureDef('sym-toilet', 'toilet', PictureGroup.symbolCore),
  PictureDef('sym-hug', 'hug', PictureGroup.symbolCore),
  PictureDef('sym-look', 'look', PictureGroup.symbolCore),
  PictureDef('sym-all-done', 'all done', PictureGroup.symbolCore),
  // ---- symbols a guardian may add to her personal board ----
  PictureDef('sym-bath', 'bath', PictureGroup.symbolExtra),
  PictureDef('sym-book', 'book', PictureGroup.symbolExtra),
  PictureDef('sym-music', 'music', PictureGroup.symbolExtra),
  PictureDef('sym-outside', 'outside', PictureGroup.symbolExtra),
  PictureDef('sym-sleep', 'sleep', PictureGroup.symbolExtra),
  PictureDef('sym-blanket', 'blanket', PictureGroup.symbolExtra),
  PictureDef('sym-owl', 'owl', PictureGroup.symbolExtra),
  PictureDef('sym-home', 'home', PictureGroup.symbolExtra),
];

final Map<String, PictureDef> _byId = <String, PictureDef>{
  for (final PictureDef p in pictureLibrary) p.id: p,
};

PictureDef? pictureById(Object? id) => id is String ? _byId[id] : null;

/// True when [id] is a library picture belonging to one of [groups].
bool isPictureIn(Object? id, Set<PictureGroup> groups) {
  final PictureDef? p = pictureById(id);
  return p != null && groups.contains(p.group);
}

/// The spoken name for [id], or an empty string for an unknown id.
String pictureLabel(Object? id) => pictureById(id)?.label ?? '';

List<PictureDef> picturesIn(PictureGroup g) =>
    <PictureDef>[for (final PictureDef p in pictureLibrary) if (p.group == g) p];
