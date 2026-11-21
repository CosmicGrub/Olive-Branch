// OLIVE BRANCH — the recovery sheet: a backup key written as plain words a person can put on paper, read back and
// type. UNVERIFIED on a device; pure Dart, runs headless in CI. See docs/planning/BACKUP-RESTORE-CLIENT.md.
//
// SHAPE. 16 random bytes (128 bits) become 16 words from a fixed list of 256, then two CHECK words (a short digest of
// the 16) so a mistyped or mis-copied sheet is caught on the spot, in the person's own words, before anything is
// tried against a backup. 18 words in all, read in rows of six. The list is fixed forever: the order IS the value,
// so a test pins its length, its uniqueness and its first four letters (typing four letters is enough).
//
// WHAT THE WORDS ARE. The seed the backup key pair is derived from (backup_crypto.dart). They are the ONLY copy of the
// secret half: no phone keeps them, no server sees them, and nothing in this app can show them again after the sheet
// is made. Two sheets are made, never mixed: the family's (kept by the grown-ups) and, for a child's tablet, the
// keepsake sheet (backup_keepsake.dart).
import 'dart:math';
import 'dart:typed_data';

import 'sha256.dart';

/// 256 words, one per byte value. NEVER reorder or change one: a sheet written today must open next year.
const List<String> kBackupWords = <String>[
  'acorn', 'amber', 'anchor', 'apple', 'apron', 'arrow', 'aspen', 'autumn',
  'bacon', 'badge', 'baker', 'banjo', 'barley', 'basil', 'beach', 'berry',
  'bison', 'blanket', 'bloom', 'boat', 'bottle', 'branch', 'bread', 'bridge',
  'brook', 'bucket', 'butter', 'cabin', 'cactus', 'candle', 'canoe', 'carpet',
  'castle', 'cedar', 'cherry', 'circle', 'clover', 'cobweb', 'cocoa', 'comet',
  'copper', 'coral', 'cotton', 'cradle', 'crayon', 'crystal', 'daisy', 'dance',
  'denim', 'desert', 'dinner', 'dolphin', 'dragon', 'drum', 'eagle', 'earth',
  'ember', 'engine', 'fabric', 'falcon', 'feather', 'fiddle', 'field', 'finch',
  'flame', 'flute', 'forest', 'fossil', 'fountain', 'garden', 'garlic', 'ginger',
  'glacier', 'glove', 'goose', 'grape', 'gravel', 'guitar', 'hammer', 'harbor',
  'hazel', 'heron', 'honey', 'horizon', 'island', 'ivory', 'jacket', 'jelly',
  'jigsaw', 'jungle', 'kettle', 'kitten', 'ladder', 'lagoon', 'lantern', 'laurel',
  'lemon', 'lilac', 'linen', 'lizard', 'locket', 'maple', 'marble', 'meadow',
  'melon', 'mitten', 'mirror', 'muffin', 'napkin', 'needle', 'nutmeg', 'oasis',
  'ocean', 'olive', 'onion', 'orange', 'orchard', 'otter', 'paddle', 'pebble',
  'pepper', 'piano', 'pillow', 'planet', 'pocket', 'pollen', 'pond', 'poppy',
  'puddle', 'pumpkin', 'quilt', 'rabbit', 'radish', 'rain', 'raven', 'ribbon',
  'river', 'robin', 'rocket', 'saddle', 'salmon', 'season', 'shell', 'silver',
  'sketch', 'spoon', 'spring', 'squirrel', 'stable', 'station', 'sunset', 'swan',
  'table', 'teapot', 'thimble', 'thunder', 'tiger', 'timber', 'toast', 'tomato',
  'tower', 'trail', 'tulip', 'tunnel', 'turtle', 'umbrella', 'valley', 'velvet',
  'violin', 'walnut', 'wagon', 'waffle', 'willow', 'window', 'winter', 'wombat',
  'wool', 'yarn', 'zebra', 'zipper', 'breeze', 'cliff', 'dune', 'ferry',
  'gate', 'hill', 'kite', 'lake', 'lamp', 'mist', 'moon', 'nest',
  'pear', 'plum', 'quiet', 'road', 'sand', 'star', 'tent', 'vine',
  'wave', 'yard', 'zest', 'cloud', 'apricot', 'bamboo', 'bell', 'birch',
  'brick', 'canyon', 'chalk', 'cider', 'cobble', 'crane', 'dove', 'drift',
  'fern', 'flint', 'frost', 'goat', 'harp', 'jade', 'lark', 'leaf',
  'lotus', 'mango', 'moss', 'mule', 'oak', 'owl', 'palm', 'plain',
  'quartz', 'reed', 'ridge', 'sage', 'shore', 'slate', 'sparrow', 'stone',
  'storm', 'sugar', 'swing', 'trout', 'walrus', 'wren', 'yacht', 'cinder',
  'dusk', 'tide', 'kayak', 'nectar', 'pine', 'raisin', 'sofa', 'cello',
];

/// How many data words a sheet has (16 bytes) and how many check words follow.
const int kSheetDataWords = 16;
const int kSheetCheckWords = 2;
const int kSheetWords = kSheetDataWords + kSheetCheckWords;

/// Why a typed sheet was not accepted, in a form a screen can turn into plain words.
enum SheetProblem {
  /// Nothing was typed, or not 18 words.
  wrongCount,

  /// One word is not on the list (see [SheetParse.badIndex]).
  unknownWord,

  /// Every word is real but the check words do not match: a word is wrong, swapped or missing.
  checkFailed,
}

class SheetParse {
  const SheetParse.ok(RecoveryKey this.key)
      : problem = null,
        badIndex = null;
  const SheetParse.no(SheetProblem this.problem, {this.badIndex}) : key = null;
  final RecoveryKey? key;
  final SheetProblem? problem;

  /// 0-based position of the first word that was not recognised.
  final int? badIndex;
  bool get ok => key != null;
}

/// A backup key: the 16-byte seed and how it is written down. Make one with [RecoveryKey.generate]; read a typed
/// sheet with [RecoveryKey.parse]. Equality is by seed.
class RecoveryKey {
  RecoveryKey._(this.seed);

  /// The secret. Never stored, never logged, never sent.
  final Uint8List seed;

  factory RecoveryKey.generate({Random? random}) {
    final Random r = random ?? Random.secure();
    return RecoveryKey._(Uint8List.fromList(List<int>.generate(16, (_) => r.nextInt(256))));
  }

  /// For tests and for restoring from a known seed.
  factory RecoveryKey.fromSeed(List<int> seed) {
    if (seed.length != 16) throw ArgumentError('a recovery key seed is 16 bytes');
    return RecoveryKey._(Uint8List.fromList(seed));
  }

  static Uint8List _check(List<int> seed) {
    final Uint8List input = Uint8List.fromList(<int>[...'olive-sheet-check-v1'.codeUnits, ...seed]);
    return Uint8List.fromList(sha256Bytes(input).sublist(0, kSheetCheckWords));
  }

  /// The 18 words: 16 for the seed, then 2 check words.
  List<String> get words => <String>[
        for (final int b in seed) kBackupWords[b],
        for (final int b in _check(seed)) kBackupWords[b],
      ];

  /// The first and last word of the sheet, for "type the first and last words" (prompt B2).
  String get firstWord => words.first;
  String get lastWord => words.last;

  /// Reads whatever a person typed or pasted: any case, any spaces, commas or dashes. A word may be typed in full or
  /// as its first four letters when that is unambiguous. Never throws.
  static SheetParse parse(String input) {
    final List<String> parts =
        input.toLowerCase().split(RegExp(r'[^a-z]+')).where((String s) => s.isNotEmpty).toList();
    if (parts.length != kSheetWords) return const SheetParse.no(SheetProblem.wrongCount);
    final List<int> values = <int>[];
    for (int i = 0; i < parts.length; i++) {
      final int? v = wordValue(parts[i]);
      if (v == null) return SheetParse.no(SheetProblem.unknownWord, badIndex: i);
      values.add(v);
    }
    final Uint8List seed = Uint8List.fromList(values.sublist(0, kSheetDataWords));
    final Uint8List check = _check(seed);
    for (int i = 0; i < kSheetCheckWords; i++) {
      if (values[kSheetDataWords + i] != check[i]) return const SheetParse.no(SheetProblem.checkFailed);
    }
    return SheetParse.ok(RecoveryKey._(seed));
  }

  /// True when [typedFirst] and [typedLast] are this sheet's first and last words (the paper check; nothing is sent).
  bool paperMatches(String typedFirst, String typedLast) {
    final int? a = wordValue(typedFirst.trim().toLowerCase()), b = wordValue(typedLast.trim().toLowerCase());
    return a != null && b != null && kBackupWords[a] == firstWord && kBackupWords[b] == lastWord;
  }

  @override
  bool operator ==(Object other) {
    if (other is! RecoveryKey) return false;
    for (int i = 0; i < 16; i++) {
      if (seed[i] != other.seed[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(seed);

  /// Never shows the secret, even by accident in a log line.
  @override
  String toString() => 'RecoveryKey(hidden)';
}

/// The byte value of a typed word: an exact match, else the one word that starts with these four-or-more letters.
int? wordValue(String w) {
  if (w.isEmpty) return null;
  final int exact = kBackupWords.indexOf(w);
  if (exact >= 0) return exact;
  if (w.length < 4) return null;
  int? hit;
  for (int i = 0; i < kBackupWords.length; i++) {
    if (kBackupWords[i].startsWith(w)) {
      if (hit != null) return null; // ambiguous
      hit = i;
    }
  }
  return hit;
}
