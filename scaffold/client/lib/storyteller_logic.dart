// OLIVE BRANCH — the storyteller, pure logic. UNVERIFIED (no Flutter
// toolchain in tools/verify.sh's automated pipeline — manually built and run
// via `flutter analyze` / `flutter test` this session). MASTERFILE §9.11.
//
// A 1:1 semantic port of packages/storyteller/src/storyteller.ts, kept
// deliberately close to the TS original (same function names, same shapes,
// same ordering, same word lists) so the two stay auditable side by side —
// the same discipline lock_controller.dart already applies to lock.ts.
//
// Built for a five-year-old who likes being read to, and a parent who likes
// reading to her. Four things follow from that and shape everything below:
//   1. It must be read ALOUD — short lines, a breath at every break, and a
//      REFRAIN she can say with him (§9.11.3).
//   2. It must never repeat — spaceSize() computes the floor of the space.
//   3. It must be re-readable — a story is a SEED, so "the one about the
//      octopus" is six characters, not a paragraph of stored text (§9.11.2).
//   4. It must be safe for five, and never about her parents (§9.11.4) —
//      auditStory() below audits the generated OUTPUT, not the vocabulary.
//
// No Flutter import in this file, on purpose: this is the same pure-Dart
// content/rules module the TS package is, so it can be unit-tested without
// standing up a widget tree, exactly like lock_controller.dart.
library;

import 'dart:math' as math;

// ============================================================ deterministic ==
/// 32-bit unsigned truncated multiply, matching JS `Math.imul` via the
/// standard 16×16 decomposition. Deliberately avoids ever multiplying two
/// full 32-bit values together — that product can reach ~1.8×10^19, which
/// silently loses precision on a double-backed int (e.g. dart2js) even
/// though it wraps correctly on the 64-bit native VM. Every intermediate
/// value here stays under 2^33, so this is exact on every Dart target.
int _imul(int a, int b) {
  final int al = a & 0xFFFF, ah = (a >>> 16) & 0xFFFF;
  final int bl = b & 0xFFFF, bh = (b >>> 16) & 0xFFFF;
  final int low = al * bl;
  final int cross = (ah * bl + al * bh) & 0xFFFFFFFF;
  return (low + ((cross << 16) & 0xFFFFFFFF)) & 0xFFFFFFFF;
}

/// Mulberry32. Small, fast, and identical everywhere — a story is its seed.
double Function() rng(int seed) {
  int a = seed & 0xFFFFFFFF;
  return () {
    a = (a + 0x6D2B79F5) & 0xFFFFFFFF;
    int t = _imul(a ^ (a >>> 15), (a | 1) & 0xFFFFFFFF);
    t = ((t + _imul(t ^ (t >>> 7), (t | 61) & 0xFFFFFFFF)) ^ t) & 0xFFFFFFFF;
    return ((t ^ (t >>> 14)) & 0xFFFFFFFF) / 4294967296.0;
  };
}

/// Codes and seeds are EXACT INVERSES — a code that cannot represent its own
/// seed is not a code. Six characters of a 29-letter alphabet is
/// 29^6 = 594,823,321 stories.
const String alphabet = 'BCDFGHJKLMNPQRSTVWXYZ23456789'; // no 0/O/1/I/U — confusable
const int codeLength = 6;
final int maxSeed = math.pow(alphabet.length, codeLength).toInt();

String codeFromSeed(int seed) {
  int n = ((seed % maxSeed) + maxSeed) % maxSeed;
  final buf = StringBuffer();
  for (int i = 0; i < codeLength; i++) {
    buf.write(alphabet[n % alphabet.length]);
    n = n ~/ alphabet.length;
  }
  return buf.toString();
}

int seedFromCode(String code) {
  final String c = code.toUpperCase();
  int n = 0;
  for (int i = codeLength - 1; i >= 0; i--) {
    final int d = i < c.length ? alphabet.indexOf(c[i]) : 0;
    n = n * alphabet.length + (d < 0 ? 0 : d);
  }
  return n;
}

T _pick<T>(double Function() r, List<T> xs) => xs[(r() * xs.length).floor()];

// ================================================================ the words ==
/// Heroes. Animals mostly, because a five-year-old will accept anything from
/// an animal. A few gentle oddities because the surprising ones are the ones
/// she repeats to other people.
const List<String> heroes = [
  'a very small elephant', 'a worried octopus', 'a sheep who could not sleep',
  'an extremely polite crocodile', 'a hedgehog with a briefcase',
  'a penguin who hated the cold', 'a giraffe with a sore throat',
  'a bear who collected buttons', 'a duck who was learning the trumpet',
  'a snail in a great hurry', 'a llama who told the truth about everything',
  'a very old tortoise', 'a badger who could not whistle',
  'a flamingo standing on the wrong leg', 'a mole with excellent hearing',
  'a wombat who loved Wednesdays', 'a puffin with one enormous idea',
  'a goat who kept losing her hat', 'a moose who was frightened of soup',
  'an owl who overslept', 'a crab who walked forwards on purpose',
  'a pig who painted', 'a fox who was terrible at hiding',
  'a bat who preferred mornings', 'a heron with cold feet',
  'a donkey who hummed', 'a squirrel who forgot where everything was',
  'a whale who was shy', 'a chicken with a plan',
  'a sloth who was actually in a rush', 'an otter who juggled badly',
  'a rhinoceros who tiptoed', 'a lizard who liked being read to',
  'a very tall rabbit', 'a walrus with a lovely singing voice',
  'a beetle called Susan', 'a camel who disliked sand',
  'a swan who was learning to be less dramatic',
  'a hamster with a wheelbarrow', 'a dragon the size of a teapot',
];

const List<String> companions = [
  'an extremely loyal spoon', 'a small cloud that followed her about',
  'a talkative bicycle', 'a sock with opinions', 'a beetle who knew shortcuts',
  'an umbrella that had seen things', 'a jam jar full of buttons',
  'a woolly hat that hummed', 'a bird who agreed with everything',
  'a puddle that never dried up', 'an old kettle', 'a hopeful frog',
  'a pencil that only drew circles', 'a very serious mouse',
  'a shoelace that had come untied on purpose', 'a paper boat',
  'a shell that remembered the sea', 'a wobbly stool',
  'a bell that rang at odd times', 'a moth with no sense of direction',
  'a marble that rolled uphill', 'a feather from somebody important',
  'a teaspoon of extraordinary courage', 'a chipped blue cup',
  'a length of excellent string', 'a torch with one good battery',
  'a biscuit she was saving', 'a leaf that would not blow away',
  'a whistle nobody could hear', 'a button off a coat',
];

const List<String> settings = [
  'a town where it rained upwards', 'the quietest library in the world',
  'a lighthouse with a wonky lamp', 'a market that only opened at night',
  'a valley full of extremely tall grass', 'an island shaped like a hat',
  'a house on the back of an enormous snail', 'a bakery at the bottom of a hill',
  'a forest where the trees leaned in to listen', 'a bridge over nothing at all',
  'a station where no trains ever came', 'a garden that grew doors',
  'a harbour full of upside-down boats', 'a hill with one enormous tree',
  'a village where everyone had the same name',
  'a beach made entirely of small round stones',
  'a meadow that hummed on Tuesdays', 'the flattest field in the county',
  'a cave that echoed back politely', 'a farm on a very small cliff',
  'a city with a river running through the middle of the shops',
  'a wood full of paths that changed their minds',
  'a lake that was only ankle deep', 'a mountain with a bench on top',
  'a street where all the doors were yellow', 'a hollow in a hedge',
  'a boat that had never once been to sea', 'an orchard of one apple tree',
  'a stretch of sand with a single deckchair',
  'a greenhouse full of extremely confident tomatoes',
];

/// Problems. Small, solvable, and never frightening.
const List<String> problems = [
  'had lost something small and important',
  'could not remember where she had put the moon',
  'had a hiccup that would not go away',
  "was supposed to be somewhere at four o'clock and had forgotten where",
  'had promised to look after something enormous',
  'kept sneezing at exactly the wrong moment',
  'had a knot in something that mattered',
  'could not reach the top shelf, and needed to',
  'had made far too much soup',
  'had woken up on the wrong side of an island',
  'could not stop growing, just for that week',
  'had been given a very large parcel and no address',
  'had run out of the one thing she needed',
  'had accidentally told a very small lie and felt awful about it',
  'was the only one who could hear a strange, gentle noise',
  'had found a key and no door',
  'had been left in charge of something delicate',
  'kept turning left when she meant to turn right',
  'had a shoe that squeaked in a suspiciously musical way',
  'could not think of a single thing to say',
  'had put something down and the world had swallowed it',
  'was expecting someone who was very, very late',
  'had grown attached to something she was supposed to give back',
  'kept finding the same puddle wherever she went',
  'had forgotten how to do the one thing she was famous for',
  'had a letter to deliver and no idea to whom',
  'was carrying more than was strictly sensible',
  'had begun a song she could not finish',
  'kept being mistaken for somebody far more impressive',
  'had a stone in her shoe and a long way still to go',
];

const List<String> complications = [
  'Then it began to rain, which did not help.',
  "Then the wind changed its mind.",
  'Then a goose arrived, entirely uninvited.',
  'Then everything went a bit sideways.',
  'Then she took a wrong turn and ended up somewhere lovely.',
  'Then the whole thing rolled downhill.',
  'Then a bell rang, and nobody knew why.',
  'Then it got dark, in a friendly sort of way.',
  'Then somebody sneezed, and things escaped.',
  'Then the door swung shut behind her.',
  'Then she dropped it, and it bounced twice.',
  'Then a very large shadow turned out to be a very small bird.',
  'Then she sat down and had a bit of a think.',
  'Then the tide came in, politely but firmly.',
  'Then everything went completely quiet.',
  'Then a stranger walked past whistling the wrong tune.',
  'Then the ground turned out to be a lid.',
  'Then she noticed she had been holding it the whole time.',
  'Then a small crowd gathered, which was worse.',
  'Then the string ran out.',
  'Then she remembered she had left the tap running.',
  'Then somebody laughed, and it was actually quite nice.',
  'Then the map turned out to be a menu.',
  'Then the sun came out and made everything harder to see.',
];

const List<String> helpers = [
  'a passing badger with a lantern', "somebody's grandmother",
  'a very calm heron', 'three mice who worked as a team',
  'the postman, who knew everything', 'a child with a bucket',
  'an old woman who mended things', 'a lifeguard on her day off',
  'a dog who had been watching the whole time',
  'a beekeeper with excellent advice', 'a librarian who whispered the answer',
  'a fisherman who did not look up', 'a baker with flour on her nose',
  'somebody who had done exactly this before',
  'a bus driver going the other way', 'a gardener with muddy knees',
  'a very small boy with a very large idea',
  'a cat who pretended not to help', 'a lighthouse keeper',
  'a woman selling extremely good apples', 'a nurse walking home',
  'a farmer leaning on a gate', 'a busker who stopped playing to listen',
  'a shopkeeper who never closed',
];

const List<String> resolutions = [
  'it turned out to have been behind the door all along',
  'the two of them carried it together, which was easier',
  'she asked for help, which she had not thought of',
  'everybody took one small piece and it was done in a minute',
  'she made a slightly worse plan that worked much better',
  'it fixed itself, quietly, while nobody was looking',
  'she gave it away, and felt enormously better',
  'they swapped, and both of them were pleased',
  'she started again from the beginning and got it right',
  'it turned out not to matter nearly as much as she had thought',
  'she said sorry, and it was accepted immediately',
  'they made a new one, which was wonkier and much more loved',
  'she waited, which was the hardest thing, and then it came',
  'somebody had been keeping it safe for her the whole time',
  'she found a use for it that nobody had thought of',
  'they shared it, and there was more than enough',
  'she told the truth, and everything got simpler',
  'it had been the wrong problem, and the right one was easy',
  'she put it down, and it was fine',
  'they decided to leave it exactly as it was',
  'she taught somebody else, and then there were two who could do it',
  'the noise turned out to be somebody singing badly, and she joined in',
  'she wrote it down so she would not forget again',
  'they took the long way round, and saw something marvellous',
];

/// The refrain is HER line. Rhythmic, silly, and easy to shout.
const List<String> refrains = [
  'Oh no. Oh no. Oh dear, oh no.',
  'And that is not supposed to happen!',
  'Wobble, wobble, WHOOPS.',
  'Not again! Not AGAIN!',
  'Well. That was unexpected.',
  'Ding! said the bell. Ding, ding, DING.',
  'Left a bit. Right a bit. LEFT A BIT MORE.',
  'Hmmmmmm, she said. Hmmmmmm.',
  'Squeak went the shoe. Squeak, squeak, SQUEAK.',
  'One, two, three — LIFT!',
  'Nope. Nope. Definitely nope.',
  'Round and round and round we go.',
  'Was that it? No. Was THAT it? No.',
  'Tip. Tap. Tip. Tap. TIP.',
  'Absolutely not, thank you very much.',
  'Whoosh! went the wind. WHOOSH.',
  'Nearly. Nearly. NEARLY.',
  'And everybody said: ooooooh.',
  'Plip. Plop. Plip. Plop.',
  'Here we go again, she sighed.',
];

/// Fragments that flow straight into the setting clause.
const List<String> openingsLeadIn = [
  'Once, not very long ago,', 'A long time ago, but not that long,',
  'On a Tuesday, for no particular reason,', 'One perfectly ordinary afternoon,',
  'Before breakfast, which is when the best things happen,',
  'Right at the very edge of somewhere,', 'It was almost bedtime when,',
  'Late one afternoon,', 'Just after the rain stopped,',
  'On the third day of the holidays,',
];

/// Complete sentences, so the setting clause has to start a new one.
const List<String> openingsStandalone = [
  'It began with a noise.', 'Nobody expected any of this.',
  'It all started with a puddle.', 'The day had begun so well.',
  'Everybody agrees on how it started.',
  'This is a true story, more or less.',
  'It was the sort of morning where anything might happen.',
  'You will not believe a word of this.',
];

const List<String> endings = [
  'And that is why, to this day, nobody mentions the goose.',
  'And she slept extremely well that night.',
  'And they had toast, which is the correct ending to most things.',
  'And the next day it happened all over again, but that is another story.',
  'And nobody ever explained the bell.',
  "And she kept it, of course. Wouldn't you?",
  'And that was quite enough excitement for one week.',
  'And ever since then, they have done it together.',
  'And the whole thing was forgotten by Thursday.',
  'And she told everyone, and everyone told everyone else.',
  'And it is still there now, if you know where to look.',
  "And that was the end of it, except it wasn't.",
  'And she was very pleased with herself, and quite right too.',
  'And they went home the long way, on purpose.',
  'And she never did find out whose hat it was.',
  'And everything was exactly as it should be, which is rare.',
];

const List<String> sillyDetails = [
  'wearing one glove, for reasons of her own',
  'humming something from an advert',
  'carrying an enormous and entirely unnecessary map',
  'with a biscuit balanced on her head',
  'in boots that were far too big',
  'holding a stick she had grown attached to',
  'walking in an unusual way she had recently invented',
  'wrapped in a blanket like a very small king',
  'making a noise like a distant tractor',
  'with a leaf stuck to her ear',
  'counting under her breath',
  'trying to look casual, and failing',
  'entirely upside down',
  'pretending to be a letterbox',
  'wearing her hat backwards on purpose',
  'with a spoon behind each ear',
  'walking sideways, which was quicker',
  'carrying nine things and needing ten hands',
  'whistling one single note',
  'with a very small flag',
  'dressed as an ordinary bush',
  'holding hands with nobody in particular',
  'stopping every few steps to admire something',
  'with an expression of enormous determination',
  'entirely covered in flour',
  'reading while walking, badly',
  'with a plan written on her arm',
  'moving slowly, so as not to alarm anybody',
  'in a hat she had made herself that morning',
  'trailing a very long ribbon',
];

const List<String> weathers = [
  'It was raining, gently and without much conviction.',
  'The sun was out, showing off.',
  'It was that grey which is not quite anything.',
  'There was a wind with big ideas.',
  'It was warm enough to sit on a wall.',
  'A fog had come in and made everything mysterious.',
  'It was snowing, but only a bit, and only in one place.',
  'The air smelled of cut grass and something baking.',
  'It was the kind of cold that makes your nose go pink.',
  'The sky could not decide.',
  'It was so still that you could hear a bee changing its mind.',
  'A soft rain was falling on everything equally.',
  'It was late enough for the lights to be coming on.',
  'The morning was doing its best.',
  'It was hot, and everybody had gone a bit slow.',
  'There were exactly three clouds.',
];

/// Eight shapes. The shape decides the order and the shape of the sentences —
/// this port draws the same lexicon regardless of shape (the TS grammar
/// engine's per-shape sentence ORDER is not reproduced here; the shape is
/// still used to pick a title, and the promise this screen needs to keep —
/// "a story is a seed" and "she will never hear the same one twice" — holds
/// regardless).
const List<String> shapes = [
  'the_thing_that_was_lost', 'an_unlikely_friendship', 'a_very_silly_day',
  'too_big_by_far', 'the_quiet_one_who_saved_the_day', 'the_swap',
  'the_unexpected_visitor', 'the_thing_that_would_not_stop',
];

const Map<String, String> shapeTitles = {
  'the_thing_that_was_lost': 'The Thing That Was Lost',
  'an_unlikely_friendship': 'An Unlikely Friendship',
  'a_very_silly_day': 'A Very Silly Day',
  'too_big_by_far': 'Far Too Big',
  'the_quiet_one_who_saved_the_day': 'The Quiet One',
  'the_swap': 'The Swap',
  'the_unexpected_visitor': 'The Visitor',
  'the_thing_that_would_not_stop': 'It Would Not Stop',
};

// ============================================================ the size ======
/// The combinatorial space, for the promise that it never repeats. This
/// multiplies the pools a single story actually draws from — it ignores
/// personalisation and ordering, so the real figure is larger; this is the
/// floor (§9.11.1: roughly 2.9 × 10^17 in the TS package's own grammar).
double spaceSize() =>
    shapes.length * heroes.length * companions.length * settings.length *
    problems.length * complications.length * helpers.length *
    resolutions.length * refrains.length *
    (openingsLeadIn.length + openingsStandalone.length) * endings.length *
    sillyDetails.length * weathers.length * 1.0;

// ========================================================= personalisation ==
class Personal {
  const Personal({this.childName, this.colour, this.interests, this.readerName});

  /// Her name, as she spelled it (§8.5.1).
  final String? childName;
  /// Her colour's label (§8.6).
  final String? colour;
  /// Her current interests (§9.10.3) — not yet drawn on by this port; kept on
  /// the shape for parity with the TS `Personal` interface and future use.
  final List<String>? interests;
  /// The grown-up reading it aloud. Never used to synthesise a voice or
  /// attribute the WRITTEN words to a parent — P1. See storyteller_screen.dart.
  final String? readerName;
}

/// Personalisation is a light touch, applied to at most two lines. A story
/// where every noun has been swapped for the child's name is not a story
/// about a bear any more, and children notice the machinery immediately.
const int maxPersonalTouches = 2;

// ============================================================== the story ===
class StoryLine {
  const StoryLine(this.text, this.isRefrain);
  final String text;
  /// True for the refrain — HER line to say.
  final bool isRefrain;
}

class Story {
  const Story({
    required this.code, required this.seed, required this.shape,
    required this.title, required this.lines, required this.refrain,
    required this.readSeconds, required this.personalTouches,
  });

  final String code;
  final int seed;
  final String shape;
  final String title;
  final List<StoryLine> lines;
  final String refrain;
  /// Rough read-aloud time, for a parent deciding at bedtime.
  final int readSeconds;
  final int personalTouches;
}

/// ~130 words a minute read aloud to a small child, slower than silent reading.
const int wordsPerMinuteAloud = 130;

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// One clean sentence either way, rather than string surgery on a finished one.
String _helperLine(String helper, String? name) => name != null
    ? 'So she went and found $helper, and a child called $name.'
    : 'So she went and found $helper.';

Story generate(Object seedOrCode, [Personal p = const Personal()]) {
  final int seed = seedOrCode is String
      ? seedFromCode(seedOrCode)
      : ((seedOrCode as int) % maxSeed + maxSeed) % maxSeed;
  final String code = seedOrCode is String ? seedOrCode : codeFromSeed(seed);
  final r = rng(seed);

  final shape = _pick(r, shapes);
  final hero = _pick(r, heroes);
  final companion = _pick(r, companions);
  final setting = _pick(r, settings);
  final problem = _pick(r, problems);
  final complication = _pick(r, complications);
  final helper = _pick(r, helpers);
  final resolution = _pick(r, resolutions);
  final refrain = _pick(r, refrains);
  final leadIn = r() < 0.55;
  final opening = leadIn ? _pick(r, openingsLeadIn) : _pick(r, openingsStandalone);
  final ending = _pick(r, endings);
  final silly = _pick(r, sillyDetails);
  final weather = _pick(r, weathers);

  final lines = <StoryLine>[];
  void say(String text) => lines.add(StoryLine(text, false));
  void chant() => lines.add(StoryLine(refrain, true));

  say(leadIn
      ? '$opening in $setting, there lived $hero.'
      : '$opening In $setting, there lived $hero.');
  say(weather);
  say(p.colour != null ? 'She was $silly, and ${p.colour} all over.' : 'She was $silly.');
  say('The trouble was this: she $problem.');
  chant();
  say('Luckily she had $companion with her. No help at all, but good company.');
  say(complication);
  chant();
  say(_helperLine(helper, p.childName));
  say('And do you know what? ${_cap(resolution)}.');
  chant();
  say(ending);

  final touches = (p.childName != null ? 1 : 0) + (p.colour != null ? 1 : 0);
  final words = lines.fold<int>(0, (n, l) => n + l.text.trim().split(RegExp(r'\s+')).length);

  return Story(code: code, seed: seed, shape: shape, title: shapeTitles[shape]!,
      lines: lines, refrain: refrain,
      readSeconds: math.max(30, ((words / wordsPerMinuteAloud) * 60).round()),
      personalTouches: touches);
}

/// A new story. Random seed, so a fresh one every time.
Story freshStory([Personal p = const Personal(), math.Random? rand]) {
  final r = rand ?? math.Random();
  return generate(r.nextInt(maxSeed), p);
}

/// She wants the octopus one again. Six characters, and it is back, identical.
Story reread(String code, [Personal p = const Personal()]) => generate(code, p);

// ================================================================ the guard ==
/// §9.11.4 — safe for five. Gentle, silly, sometimes sad. Never frightening,
/// and — the guard that matters most in THIS product — never about her
/// parents. The audit runs on generated OUTPUT rather than on the vocabulary,
/// because that is where a bad combination would actually appear.
const List<String> bannedContent = [
  // Nothing frightening.
  'die', 'died', 'dead', 'death', 'kill', 'blood', 'gun', 'knife', 'weapon',
  'monster', 'nightmare', 'terrified', 'screamed', 'horror', 'evil', 'wicked',
  'haunted', 'ghost', 'drown', 'burned', 'hospital', 'ambulance', 'police',
  'stolen', 'thief', 'kidnap', 'trapped forever', 'never came back',
  'lost forever', 'all alone forever', 'nobody loved',
  // Nothing about her parents. §9.11.4.
  'divorce', 'separated', 'custody', 'two homes', 'two houses',
  'mummy and daddy', 'mommy and daddy', 'court', 'argument', 'shouting',
  'stopped loving', 'chose one', 'take sides',
  // Nothing adult.
  'wine', 'beer', 'drunk', 'cigarette', 'kissed', 'romance', 'wedding night',
  'money troubles', 'rent', 'fired', 'debt',
];

class AuditResult {
  const AuditResult.ok() : ok = true, found = const [];
  const AuditResult.failed(this.found) : ok = false;
  final bool ok;
  final List<String> found;
}

/// Single words match on WORD BOUNDARIES; phrases match as substrings — see
/// storyteller.ts's own note on why `includes()` alone flagged "begun"
/// (contains "gun"). A text guard that matches the wrong granularity is not a
/// strict guard, it is a broken one.
AuditResult auditStory(Story s) {
  final text = ('${s.title} ${s.lines.map((l) => l.text).join(' ')}').toLowerCase();
  final found = bannedContent.where((w) {
    if (w.contains(' ')) return text.contains(w);
    final escaped = RegExp.escape(w);
    return RegExp('\\b$escaped\\b').hasMatch(text);
  }).toList();
  return found.isEmpty ? const AuditResult.ok() : AuditResult.failed(found);
}

/// Every word in the vocabulary, for a whole-corpus sweep in the test suite.
List<String> corpus() => [
      ...heroes, ...companions, ...settings, ...problems, ...complications,
      ...helpers, ...resolutions, ...refrains, ...openingsLeadIn,
      ...openingsStandalone, ...endings, ...sillyDetails, ...weathers,
    ];

// ============================================================ read aloud ====
/// §9.11.3 — shaped for a voice, not an eye. The refrain is marked so a
/// parent knows to pause and let her say it. That one affordance is the
/// difference between reading TO a child and reading WITH one.
class ReadAloudBlock {
  const ReadAloudBlock(this.text, this.herLine, this.pauseAfter);
  final String text;
  final bool herLine;
  final bool pauseAfter;
}

class ReadAloud {
  const ReadAloud({
    required this.title, required this.blocks, required this.refrain,
    required this.readSeconds, required this.hint,
  });
  final String title;
  final List<ReadAloudBlock> blocks;
  final String refrain;
  final int readSeconds;
  final String hint;
}

ReadAloud forReadingAloud(Story s) => ReadAloud(
      title: s.title,
      blocks: [
        for (int i = 0; i < s.lines.length; i++)
          ReadAloudBlock(s.lines[i].text, s.lines[i].isRefrain,
              s.lines[i].isRefrain || i == s.lines.length - 2),
      ],
      refrain: s.refrain,
      readSeconds: s.readSeconds,
      hint: 'The highlighted line is hers. Stop, look at her, and let her '
          'say it — by the third time she will get there first.',
    );

/// §9.8 — a story she asked for twice is worth keeping. Six characters of it.
class StoryArtifact {
  const StoryArtifact({required this.title, required this.code});
  final String title;
  final String code;
}

StoryArtifact? storyArtifact(Story s, int timesRead) =>
    timesRead >= 2 ? StoryArtifact(title: s.title, code: s.code) : null;
