// OLIVE BRANCH — the jokebook, pure logic. No longer UNVERIFIED — verified by
// CI (a Flutter toolchain runs for real in tools/verify.sh's automated
// pipeline). MASTERFILE §9.2. Prohibition P2.
//
// A 1:1 semantic port of packages/jokes/src/jokes.ts, kept close to the TS
// original for the same reason lock_controller.dart stays close to lock.ts
// and game_logic.dart to games.ts: the two should be auditable side by side.
//
// A fixed, hand-written library of kid-friendly jokes — dad jokes, puns,
// wordplay, plain silliness, knock-knocks. Nothing here is generated. Every
// entry was written and read by a person before it shipped, which is why
// this file needs no safety sweep: there is no unbounded supply to sweep.
//
// Age gating follows game_logic.dart's forAge() exactly: each joke carries a
// minAge and forAge(age) keeps the ones at or below her real age. That floor
// is a COMPREHENSION floor, not a content rating — every joke here is
// appropriate for every age; the floor only stops a joke she can't get yet
// (a spelling gag before she spells) from landing flat and teaching her the
// jokebook isn't for her. Nothing is gated above 12.
//
// `category` is for whoever writes this list, so the mix stays honest. It is
// not surfaced to her as a picker — she asked for a joke, not a genre.
//
// P2 governs the favourites half: a favourite is an id and a timestamp and
// nothing else. No timesRead, no tally, no streak — the type has no field to
// leak, the same construction library_logic.dart's ChildLibraryEntry uses.
//
// No Flutter import in this file, on purpose — same posture as
// storyteller_logic.dart, library_logic.dart and lock_controller.dart.
library;

import 'dart:math' as math;

enum JokeCategory { dadJoke, pun, wordplay, silly, knockKnock }

class Joke {
  const Joke({
    required this.id,
    required this.setup,
    required this.punchline,
    required this.minAge,
    required this.category,
  });

  /// Stable — favourites are lists of these, so it never changes once shipped.
  final String id;
  final String setup;
  final String punchline;
  /// Comprehension floor — see the file header. Never a content rating.
  final int minAge;
  final JokeCategory category;
}

const List<Joke> kJokeCatalogue = <Joke>[
  // ---- 4+ : the simplest possible shapes — a sound, an animal, a knock ----
  Joke(id: 'dino-snore', minAge: 4, category: JokeCategory.silly,
    setup: 'What do you call a sleeping dinosaur?', punchline: 'A dino-snore!'),
  Joke(id: 'gummy-bear', minAge: 4, category: JokeCategory.silly,
    setup: 'What do you call a bear with no teeth?', punchline: 'A gummy bear!'),
  Joke(id: 'cow-reads', minAge: 4, category: JokeCategory.silly,
    setup: 'What do cows like to read?', punchline: 'Moo-spapers!'),
  Joke(id: 'kk-boo', minAge: 4, category: JokeCategory.knockKnock,
    setup: 'Knock knock. Who’s there? Boo. Boo who?', punchline: 'Don’t cry, it’s just a joke!'),
  Joke(id: 'kk-cow-says', minAge: 4, category: JokeCategory.knockKnock,
    setup: 'Knock knock. Who’s there? Cow says. Cow says who?', punchline: 'No, silly — a cow says MOO!'),
  Joke(id: 'brown-sticky', minAge: 4, category: JokeCategory.silly,
    setup: 'What’s brown and sticky?', punchline: 'A stick!'),

  // ---- 5+ : one simple pun she can hear -----------------------------------
  Joke(id: 'teddy-stuffed', minAge: 5, category: JokeCategory.pun,
    setup: 'Why did the teddy bear say no to dessert?', punchline: 'Because she was already stuffed!'),
  Joke(id: 'wall-corner', minAge: 5, category: JokeCategory.silly,
    setup: 'What did one wall say to the other wall?', punchline: 'Meet you at the corner!'),
  Joke(id: 'kk-lettuce', minAge: 5, category: JokeCategory.knockKnock,
    setup: 'Knock knock. Who’s there? Lettuce. Lettuce who?', punchline: 'Lettuce in, it’s cold out here!'),
  Joke(id: 'ocean-waves', minAge: 5, category: JokeCategory.pun,
    setup: 'How does the ocean say hello?', punchline: 'It waves!'),
  Joke(id: 'carrot-parrot', minAge: 5, category: JokeCategory.wordplay,
    setup: 'What’s orange and sounds like a parrot?', punchline: 'A carrot!'),
  Joke(id: 'flower-bud', minAge: 5, category: JokeCategory.pun,
    setup: 'What did the big flower say to the little flower?', punchline: 'Hi, bud!'),
  Joke(id: 'cookie-crummy', minAge: 5, category: JokeCategory.pun,
    setup: 'Why did the cookie go to the doctor?', punchline: 'Because it was feeling crummy!'),
  Joke(id: 'elsa-balloon', minAge: 5, category: JokeCategory.silly,
    setup: 'Why can’t Elsa have a balloon?', punchline: 'Because she’ll let it go!'),

  // ---- 6+ : a pun that needs one more word in her vocabulary --------------
  Joke(id: 'palm-tree', minAge: 6, category: JokeCategory.pun,
    setup: 'What kind of tree fits in your hand?', punchline: 'A palm tree!'),
  Joke(id: 'cornfield-ears', minAge: 6, category: JokeCategory.pun,
    setup: 'What has ears but cannot hear?', punchline: 'A cornfield!'),
  Joke(id: 'nacho-cheese', minAge: 6, category: JokeCategory.pun,
    setup: 'What do you call cheese that isn’t yours?', punchline: 'Nacho cheese!'),
  Joke(id: 'eggs-crack-up', minAge: 6, category: JokeCategory.pun,
    setup: 'Why don’t eggs tell jokes?', punchline: 'They’d crack each other up!'),
  Joke(id: 'boomerang-stick', minAge: 6, category: JokeCategory.silly,
    setup: 'What do you call a boomerang that won’t come back?', punchline: 'A stick!'),
  Joke(id: 'zero-eight-belt', minAge: 6, category: JokeCategory.wordplay,
    setup: 'What did the zero say to the eight?', punchline: 'Nice belt!'),
  Joke(id: 'bees-honeycomb', minAge: 6, category: JokeCategory.pun,
    setup: 'Why do bees have sticky hair?', punchline: 'Because they use honeycombs!'),
  Joke(id: 'cant-opener', minAge: 6, category: JokeCategory.wordplay,
    setup: 'What do you call a can opener that doesn’t work?', punchline: 'A can’t opener!'),
  Joke(id: 'tissue-boogie', minAge: 6, category: JokeCategory.pun,
    setup: 'How do you make a tissue dance?', punchline: 'You put a little boogie in it!'),
  Joke(id: 'cat-mountain', minAge: 6, category: JokeCategory.wordplay,
    setup: 'What do you call a pile of cats?', punchline: 'A meow-ntain!'),
  Joke(id: 'bulldozer', minAge: 6, category: JokeCategory.pun,
    setup: 'What do you call a sleeping bull?', punchline: 'A bulldozer!'),
  Joke(id: 'seven-eight-nine', minAge: 6, category: JokeCategory.wordplay,
    setup: 'Why was six afraid of seven?', punchline: 'Because seven eight nine!'),
  Joke(id: 'robot-chips', minAge: 6, category: JokeCategory.pun,
    setup: 'What’s a robot’s favourite snack?', punchline: 'Computer chips!'),
  Joke(id: 'pork-chop', minAge: 6, category: JokeCategory.pun,
    setup: 'What do you call a pig that does karate?', punchline: 'A pork chop!'),

  // ---- 7+ : two ideas colliding, or a bit of spelling ---------------------
  Joke(id: 'fsh', minAge: 7, category: JokeCategory.wordplay,
    setup: 'What do you call a fish with no eyes?', punchline: 'A fsh!'),
  Joke(id: 'labracadabrador', minAge: 7, category: JokeCategory.wordplay,
    setup: 'What do you call a dog who does magic tricks?', punchline: 'A labracadabrador!'),
  Joke(id: 'math-problems', minAge: 7, category: JokeCategory.pun,
    setup: 'Why was the maths book sad?', punchline: 'It had too many problems!'),
  Joke(id: 'two-tired', minAge: 7, category: JokeCategory.pun,
    setup: 'Why did the bicycle fall over?', punchline: 'It was two-tired!'),
  Joke(id: 'impasta', minAge: 7, category: JokeCategory.pun,
    setup: 'What do you call a fake noodle?', punchline: 'An impasta!'),
  Joke(id: 'open-toad', minAge: 7, category: JokeCategory.pun,
    setup: 'What kind of shoes do frogs wear?', punchline: 'Open-toad sandals!'),
  Joke(id: 't-rex-wrecks', minAge: 7, category: JokeCategory.wordplay,
    setup: 'What do you call a dinosaur that crashes his car?', punchline: 'Tyrannosaurus wrecks!'),
  Joke(id: 'dont-know-y', minAge: 7, category: JokeCategory.dadJoke,
    setup: 'I only know 25 letters of the alphabet.', punchline: 'I don’t know Y.'),
  Joke(id: 'homework-cake', minAge: 7, category: JokeCategory.pun,
    setup: 'Why did the student eat his homework?', punchline: 'Because the teacher said it was a piece of cake!'),
  Joke(id: 'little-horse', minAge: 7, category: JokeCategory.pun,
    setup: 'Why couldn’t the pony sing?', punchline: 'She was a little horse!'),

  // ---- 8+ : an idiom she has started to hear grown-ups use ----------------
  Joke(id: 'outstanding-field', minAge: 8, category: JokeCategory.dadJoke,
    setup: 'Why did the scarecrow win an award?', punchline: 'Because he was outstanding in his field!'),
  Joke(id: 'dinners-on-me', minAge: 8, category: JokeCategory.pun,
    setup: 'What did one plate say to the other plate?', punchline: 'Dinner’s on me!'),
  Joke(id: 'salad-dressing', minAge: 8, category: JokeCategory.pun,
    setup: 'Why did the tomato turn red?', punchline: 'Because it saw the salad dressing!'),
  Joke(id: 'frostbite', minAge: 8, category: JokeCategory.pun,
    setup: 'What do you get when you cross a snowman with a dog?', punchline: 'Frostbite!'),
  Joke(id: 'investigator', minAge: 8, category: JokeCategory.wordplay,
    setup: 'What do you call an alligator in a vest?', punchline: 'An investigator!'),
  Joke(id: 'skeleton-guts', minAge: 8, category: JokeCategory.pun,
    setup: 'Why don’t skeletons fight each other?', punchline: 'They don’t have the guts!'),
  Joke(id: 'you-planet', minAge: 8, category: JokeCategory.pun,
    setup: 'How do you organise a party in space?', punchline: 'You planet!'),

  // ---- 9+ : a reference she has to already own ----------------------------
  Joke(id: 'abdominal-snowman', minAge: 9, category: JokeCategory.wordplay,
    setup: 'What do you call a snowman with a six-pack?', punchline: 'An abdominal snowman!'),
  Joke(id: 'hole-in-one', minAge: 9, category: JokeCategory.dadJoke,
    setup: 'Why did the golfer bring two pairs of trousers?', punchline: 'In case he got a hole in one!'),
  Joke(id: 'picture-framed', minAge: 9, category: JokeCategory.wordplay,
    setup: 'Why did the picture go to jail?', punchline: 'Because it was framed!'),
  Joke(id: 'janitor-supplies', minAge: 9, category: JokeCategory.wordplay,
    setup: 'What did the janitor shout when he jumped out of the cupboard?', punchline: '“Supplies!”'),
  Joke(id: 'bison', minAge: 9, category: JokeCategory.wordplay,
    setup: 'What did the buffalo say when his son left for school?', punchline: 'Bison!'),

  // ---- 10+ : proper dad jokes — a groan is the correct response -----------
  Joke(id: 'anti-gravity', minAge: 10, category: JokeCategory.dadJoke,
    setup: 'I’m reading a book about anti-gravity.', punchline: 'It’s impossible to put down!'),
  Joke(id: 'atoms-make-up', minAge: 10, category: JokeCategory.dadJoke,
    setup: 'Why don’t scientists trust atoms?', punchline: 'Because they make up everything!'),
  Joke(id: 'facial-hair', minAge: 10, category: JokeCategory.dadJoke,
    setup: 'I used to hate facial hair.', punchline: 'But then it grew on me.'),
  Joke(id: 'astronaut-space', minAge: 10, category: JokeCategory.dadJoke,
    setup: 'Did you hear about the claustrophobic astronaut?', punchline: 'He just needed a little space!'),
  Joke(id: 'coffee-mugged', minAge: 10, category: JokeCategory.dadJoke,
    setup: 'Why did the coffee file a police report?', punchline: 'It got mugged!'),

  // ---- 11+ / 12+ : wordplay that needs a bigger vocabulary ----------------
  Joke(id: 'satisfactory', minAge: 11, category: JokeCategory.wordplay,
    setup: 'What do you call a factory that makes okay products?', punchline: 'A satisfactory!'),
  Joke(id: 'swiss-flag', minAge: 11, category: JokeCategory.dadJoke,
    setup: 'What’s the best thing about Switzerland?', punchline: 'I don’t know, but the flag is a big plus!'),
  Joke(id: 'emotional-baggage', minAge: 12, category: JokeCategory.dadJoke,
    setup: 'I told my suitcase there’d be no holiday this year.', punchline: 'Now I’m dealing with emotional baggage.'),
  Joke(id: 'parallel-lines', minAge: 12, category: JokeCategory.dadJoke,
    setup: 'Parallel lines have so much in common.', punchline: 'It’s a shame they’ll never meet.'),
];

/// Mirrors jokes.ts's `forAge` — a floor, never a ceiling.
List<Joke> forAge(int age) => kJokeCatalogue.where((j) => age >= j.minAge).toList();

Joke? byId(String id) {
  for (final j in kJokeCatalogue) {
    if (j.id == id) return j;
  }
  return null;
}

/// "Tell me another!" — one joke she can get, never the one she just heard.
/// [pick] is injectable so a test can drive it deterministically; production
/// passes nothing and gets a real random. Returns null only if the age floor
/// leaves nothing at all, which cannot happen at any age ≥ 4.
Joke? randomJoke(int age, {String? excludeId, double Function()? pick}) {
  final pool = forAge(age).where((j) => j.id != excludeId).toList();
  if (pool.isEmpty) return null;
  final r = pick != null ? pick() : math.Random().nextDouble();
  return pool[(r * pool.length).floor() % pool.length];
}

// ============================================================== favourites ==
/// A joke id and when she starred it. Nothing else — no timesRead, no tally.
/// Mirrors library_logic.dart's Favourite shape for stories, deliberately
/// without the count that file keeps for the parent-side book (P2).
class JokeFavourite {
  const JokeFavourite({required this.id, required this.starredAt});
  final String id;
  final String starredAt;
}

bool isStarred(List<JokeFavourite> list, String id) => list.any((f) => f.id == id);

/// Idempotent — starring twice is one star, not two. Returns the SAME list
/// when there is nothing to do, so a caller can cheaply skip a re-render.
List<JokeFavourite> star(List<JokeFavourite> list, String id, String at) {
  if (isStarred(list, id)) return list;
  return [...list, JokeFavourite(id: id, starredAt: at)];
}

List<JokeFavourite> unstar(List<JokeFavourite> list, String id) =>
    list.where((f) => f.id != id).toList();

/// Her list, newest first — the one she starred tonight is the one she wants
/// tomorrow. A favourite whose joke has since left the book is dropped, not
/// crashed on.
List<Joke> favouritesChildView(List<JokeFavourite> list) {
  final sorted = [...list]..sort((a, b) => b.starredAt.compareTo(a.starredAt));
  return [for (final f in sorted) ?byId(f.id)];
}

/// Fields that must never reach her — the same runtime-checkable list
/// library_logic.dart keeps, so a test can assert the invariant against
/// loosely-typed data as well as against the narrow types above.
const List<String> jokebookForbidden = [
  'timesRead', 'times_read', 'mostRead', 'rank', 'score', 'streak', 'count', 'told',
];

class JokebookAuditResult {
  const JokebookAuditResult.ok() : ok = true, leaks = const [];
  const JokebookAuditResult.failed(this.leaks) : ok = false;
  final bool ok;
  final List<String> leaks;
}

JokebookAuditResult auditChildView(Object? v) {
  final leaks = <String>{};
  void walk(Object? x) {
    if (x is List) {
      for (final e in x) {
        walk(e);
      }
      return;
    }
    if (x is Map) {
      x.forEach((key, val) {
        final k = key.toString();
        if (jokebookForbidden.any((f) => f.toLowerCase() == k.toLowerCase())) leaks.add(k);
        walk(val);
      });
    }
  }
  walk(v);
  return leaks.isEmpty ? const JokebookAuditResult.ok() : JokebookAuditResult.failed(leaks.toList());
}
