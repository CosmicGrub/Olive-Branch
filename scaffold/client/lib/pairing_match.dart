// OLIVE BRANCH — the "Match" step of pairing: three pictures and a colour (about 21 bits) both screens derive from the
// finished key exchange. The child's device shows the real set (pictures only, no words); the adult's phone shows
// four candidate sets and the adult PICKS the one that is on the child's device. A wrong pick, or "None of these",
// refuses the pairing. UNVERIFIED on a device; pure logic, headless in CI (client/test/pairing_match_test.dart).
// Design: docs/planning/PERSISTENT-QR-PAIRING.md decision J8, section 3.
//
// Why a pick and not a "they match" button: tapping "yes" on autopilot is the main human weakness of any
// compare-the-screens check. Choosing one of four costs a glance. Honest limit: about 21 bits, one try per request;
// it defends against a swapped or relayed device only together with the PIN, the open window and the adult's Yes.
import 'dart:math';
import 'dart:typed_data';

/// 64 picture names. The screens map each to one distinct icon (pairing_picture_widgets.dart). None is a word the
/// child ever sees: they are only semantic labels for screen readers on the ADULT phone.
const List<String> kMatchPictures = <String>[
  'sun', 'moon', 'star', 'cloud', 'tree', 'fish', 'bird', 'cat',
  'dog', 'boat', 'house', 'flower', 'apple', 'ball', 'kite', 'bell',
  'key', 'book', 'car', 'bus', 'train', 'plane', 'rocket', 'bike',
  'umbrella', 'snowflake', 'fire', 'drop', 'leaf', 'bee', 'butterfly', 'spa',
  'cup', 'scissors', 'hammer', 'palette', 'phone', 'tv', 'headphones', 'mic',
  'cake', 'icecream', 'pizza', 'cookie', 'bread', 'burger', 'egg', 'tea',
  'music', 'piano', 'wrench', 'cap', 'bag', 'watch', 'clock', 'bulb',
  'gift', 'party', 'trophy', 'heart', 'diamond', 'anchor', 'flag', 'camera',
];

/// Eight colours; each also has a shape so colour is never the only cue (colour-blind adults and children).
const List<String> kMatchColours = <String>['red', 'orange', 'yellow', 'green', 'teal', 'blue', 'purple', 'pink'];
const List<String> kMatchShapes = <String>['circle', 'square', 'triangle', 'pentagon', 'ring', 'hexagon', 'heart', 'plus'];

/// Three pictures (indices 0..63) and a colour (0..7).
class MatchSet {
  const MatchSet(this.pictures, this.colour);
  final List<int> pictures;
  final int colour;

  /// The set the key exchange yields: from three bytes, six bits per picture and three bits of colour.
  factory MatchSet.fromBytes(List<int> b) {
    assert(b.length >= 3);
    return MatchSet(<int>[b[0] & 63, b[1] & 63, b[2] & 63], ((b[0] >> 6) & 3) | (((b[1] >> 6) & 1) << 2));
  }

  List<String> get names => pictures.map((int i) => kMatchPictures[i]).toList();

  @override
  bool operator ==(Object other) =>
      other is MatchSet && other.colour == colour && other.pictures[0] == pictures[0] && other.pictures[1] == pictures[1] && other.pictures[2] == pictures[2];
  @override
  int get hashCode => Object.hash(colour, pictures[0], pictures[1], pictures[2]);
  @override
  String toString() => '${kMatchColours[colour]} ${names.join('+')}';
}

/// Four candidate sets for the adult's phone, in a random order, exactly one of them [real].
class MatchChoices {
  const MatchChoices(this.sets, this.correct);
  final List<MatchSet> sets;
  final int correct;
}

/// Decoys differ from the real set in at least two pictures (so a glance is enough) and from each other.
MatchChoices buildMatchChoices(MatchSet real, Random random) {
  final List<MatchSet> out = <MatchSet>[real];
  int guard = 0;
  while (out.length < 4 && guard++ < 1000) {
    final MatchSet c = MatchSet(
        List<int>.generate(3, (_) => random.nextInt(kMatchPictures.length)), random.nextInt(kMatchColours.length));
    int same = 0;
    for (int i = 0; i < 3; i++) {
      if (c.pictures[i] == real.pictures[i]) same++;
    }
    if (same > 1 || out.contains(c)) continue;
    // Also keep decoys apart from each other in at least one picture, so two cards never look nearly alike.
    if (out.skip(1).any((MatchSet o) => o.pictures[0] == c.pictures[0] && o.pictures[1] == c.pictures[1])) continue;
    out.add(c);
  }
  out.shuffle(random);
  return MatchChoices(List<MatchSet>.unmodifiable(out), out.indexOf(real));
}

/// Used by tests and by the child screen: the real set from the key exchange's three bytes.
MatchSet matchFromKeyBytes(Uint8List b) => MatchSet.fromBytes(b);
